local _, VM = ...
VM.Fulfillment = {}
local Fulfillment = VM.Fulfillment

Fulfillment.activeOrder = nil
Fulfillment.isWithdrawing = false
Fulfillment.isMailOpen = false
Fulfillment.isTradeOpen = false

local MAX_SLOTS_PER_TAB = 98
local currentTradeTargetMoney = 0
local currentTradeTargetName = ""
local pendingMailSnapshot = nil
local lastAcceptedTrade = nil
local sendMailHooked = false
local whisperedInCurrentTrade = {}

-- Local (per officer) workflow progress: Fill Mail / Fill Trade was clicked for these PREPARED requests
Fulfillment.fulfillStarted = {}

local OPEN_STATUSES = { PENDING = true, APPROVED = true, PREPARED = true }

-- Payment tracking for Mail (CoD) and manual completions starts with this build (older requests are not
-- retroactively shown as unpaid). Generic timestamp, not guild-specific.
VM.PAYMENT_TRACKING_SINCE = 1764288000
local CLAIM_TTL = 120
Fulfillment.prepareBusy = false

-- Another officer is currently withdrawing this APPROVED request (claim broadcast before withdrawing)
function Fulfillment:GetActiveClaim(req)
    if not req or req.status ~= "APPROVED" then return nil end
    local by = req.preparedBy or ""
    if by == "" then return nil end
    if (time() - (tonumber(req.preparedAt) or 0)) > CLAIM_TTL then return nil end
    return by
end

local function SetClaim(req, name)
    local now = time()
    req.preparedBy = name or ""
    req.preparedAt = name and now or 0
    req.updatedAt = now
    VM.Comms:BroadcastRequest(req)
end

local function IsBankCurrentlyOpen()
    if VM.BankScanner and VM.BankScanner.IsBankOpen then
        return VM.BankScanner:IsBankOpen()
    end
    return GuildBankFrame and GuildBankFrame:IsVisible() and true or false
end

local function CleanItemName(str)
    if type(str) ~= "string" or str == "" then return "" end
    local s = str:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local bracket = s:match("%[(.-)%]")
    if bracket and bracket ~= "" then
        s = bracket
    end
    s = s:gsub("^%[", ""):gsub("%]$", "")
    return (s:match("^%s*(.-)%s*$") or s):lower()
end

local function CleanItemDisplay(str)
    if type(str) ~= "string" or str == "" then return "Item" end
    local s = str:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local bracket = s:match("%[(.-)%]")
    if bracket and bracket ~= "" then
        s = bracket
    end
    s = s:gsub("^%[", ""):gsub("%]$", "")
    s = s:match("^%s*(.-)%s*$") or s
    return (s ~= "") and s or "Item"
end

local function DoesItemMatchRequest(itemID, itemName, req)
    if not req or req.isGoldRequest then return false end
    local reqID = tonumber(req.itemID) or 0
    local bID = tonumber(itemID) or 0
    if reqID > 0 and bID > 0 then
        return bID == reqID
    end
    local reqName = CleanItemName(req.itemName or req.itemLink)
    local bagName = CleanItemName(itemName)
    return reqName ~= "" and bagName ~= "" and reqName == bagName
end

local function IsSameActor(nameA, nameB)
    local a = VM:NormalizeName(nameA)
    local b = VM:NormalizeName(nameB)
    if a == "" or b == "" then return false end
    local la, lb = a:lower(), b:lower()
    if la == lb then return true end
    if not la:find("%s") and lb:sub(1, #la + 1) == (la .. " ") then return true end
    if not lb:find("%s") and la:sub(1, #lb + 1) == (lb .. " ") then return true end
    return false
end

local function IsSameRecipient(reqRequester, targetName)
    if IsSameActor(reqRequester, targetName) then return true end
    local rNorm = VM:NormalizeName(reqRequester)
    local tNorm = VM:NormalizeName(targetName)
    if rNorm == "" or tNorm == "" then return false end
    local rMain = VM:GetMainFor(rNorm)
    local tMain = VM:GetMainFor(tNorm)
    if rMain ~= "" and tMain ~= "" and IsSameActor(rMain, tMain) then
        return true
    end
    return false
end

local function GetContainerSlotCount(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag) or 0
    elseif GetContainerNumSlots then
        return GetContainerNumSlots(bag) or 0
    end
    return 0
end

local function GetContainerFreeSlotsAndType(bag)
    if C_Container and C_Container.GetContainerNumFreeSlots then
        return C_Container.GetContainerNumFreeSlots(bag)
    elseif GetContainerNumFreeSlots then
        return GetContainerNumFreeSlots(bag)
    end
    return 0, 0
end

local function GetBagSlotInfo(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then
            return info.hyperlink, info.stackCount or 1, info.isLocked
        end
        return nil, 0, false
    elseif GetContainerItemInfo then
        local _, count, locked, _, _, _, link = GetContainerItemInfo(bag, slot)
        return link, count or 0, locked
    end
    return nil, 0, false
end

local function PickupBagSlot(bag, slot)
    if C_Container and C_Container.PickupContainerItem then
        C_Container.PickupContainerItem(bag, slot)
    elseif PickupContainerItem then
        PickupContainerItem(bag, slot)
    end
end

local function SplitBagSlot(bag, slot, amount)
    if C_Container and C_Container.SplitContainerItem then
        C_Container.SplitContainerItem(bag, slot, amount)
    elseif SplitContainerItem then
        SplitContainerItem(bag, slot, amount)
    end
end

-- Returns list of empty slots in general-purpose bags (bagType == 0)
local function GetEmptyGeneralBagSlots()
    local empties = {}
    for bag = 0, 4 do
        local _, bagType = GetContainerFreeSlotsAndType(bag)
        if not bagType or bagType == 0 then
            local numSlots = GetContainerSlotCount(bag)
            for slot = 1, numSlots do
                local link = GetBagSlotInfo(bag, slot)
                if not link then
                    table.insert(empties, { bag = bag, slot = slot })
                end
            end
        end
    end
    return empties
end

function Fulfillment:GetExpectedMemberPayment(req)
    if not req or req.isGoldRequest then return 0 end
    if req.priceMode == "FREE" then return 0 end
    if req.quotedTotalPrice and req.quotedTotalPrice > 0 then
        return req.quotedTotalPrice
    elseif req.priceMode == "PERCENT" then
        local liveUnit = VM:GetEffectiveLivePrice(req.itemID, req.itemLink, req.priceAtRequest or req.quotedUnitPrice)
        return VM:CalculateMemberTotalPrice(liveUnit, req.count or 1, { mode = "PERCENT", percent = req.pricePercent or 50 })
    elseif req.quotedUnitPrice and req.quotedUnitPrice > 0 then
        return req.quotedUnitPrice * (req.count or 1)
    end
    return 0
end

local function CaptureMailSnapshot(target, subject)
    if not VM:IsOfficer() then
        pendingMailSnapshot = nil
        return
    end
    local recip = VM:NormalizeName(target or (SendMailNameEditBox and SendMailNameEditBox:GetText()) or "")
    if recip == "" then
        pendingMailSnapshot = nil
        return
    end

    local sentMoney = (GetSendMailMoney and GetSendMailMoney()) or 0
    local codAmount = (GetSendMailCOD and GetSendMailCOD()) or 0
    if codAmount > 0 then
        -- With CoD checked the money field is the CoD amount, not gold sent to the recipient
        sentMoney = 0
    end
    local itemsByKey = {}
    local maxSlots = ATTACHMENTS_MAX_SEND or 12

    for i = 1, maxSlots do
        local link = GetSendMailItemLink and GetSendMailItemLink(i) or nil
        local r1, r2, r3, r4, r5
        if GetSendMailItem then
            r1, r2, r3, r4, r5 = GetSendMailItem(i)
        end
        if r1 or link then
            local count = 1
            if r5 ~= nil then
                count = tonumber(r4) or 1
            elseif r3 ~= nil then
                count = tonumber(r3) or 1
            end
            local itemID = (link and tonumber(link:match("item:(%d+)"))) or (r5 ~= nil and tonumber(r2)) or 0
            local itemName = CleanItemName(link or r1)
            local aggKey = (itemID and itemID > 0) and ("ID:" .. itemID) or ("NAME:" .. itemName)
            if not itemsByKey[aggKey] then
                itemsByKey[aggKey] = {
                    itemID = itemID or 0,
                    itemName = itemName,
                    count = 0
                }
            end
            itemsByKey[aggKey].count = itemsByKey[aggKey].count + count
        end
    end

    pendingMailSnapshot = {
        recipient = recip,
        money = sentMoney,
        cod = codAmount,
        subject = subject or (SendMailSubjectEditBox and SendMailSubjectEditBox:GetText()) or "",
        items = itemsByKey,
        timestamp = time()
    }
end

local function CaptureTradeSnapshot()
    if not currentTradeTargetName or currentTradeTargetName == "" then return end
    local pMoney = (GetPlayerTradeMoney and GetPlayerTradeMoney()) or 0
    local tMoney = (GetTargetTradeMoney and GetTargetTradeMoney()) or currentTradeTargetMoney or 0
    local itemsByKey = {}
    local maxSlots = MAX_TRADE_ITEMS or 6

    for slot = 1, maxSlots do
        local tName, _, tCount = nil, nil, nil
        if GetTradePlayerItemInfo then
            tName, _, tCount = GetTradePlayerItemInfo(slot)
        end
        local link = GetTradePlayerItemLink and GetTradePlayerItemLink(slot) or nil
        if tName or link then
            local count = tonumber(tCount) or 1
            local itemID = (link and tonumber(link:match("item:(%d+)"))) or 0
            local itemName = CleanItemName(link or tName)
            local aggKey = (itemID and itemID > 0) and ("ID:" .. itemID) or ("NAME:" .. itemName)
            if not itemsByKey[aggKey] then
                itemsByKey[aggKey] = {
                    itemID = itemID or 0,
                    itemName = itemName,
                    count = 0
                }
            end
            itemsByKey[aggKey].count = itemsByKey[aggKey].count + count
        end
    end

    lastAcceptedTrade = {
        recipient = currentTradeTargetName,
        playerMoney = pMoney,
        targetMoney = tMoney,
        items = itemsByKey,
        timestamp = time()
    }
end

function Fulfillment:PruneOldRequests()
    if not VM.db or not VM.db.requests then return 0 end
    local cutoff = time() - (30 * 86400)
    local removed = 0
    for id, req in pairs(VM.db.requests) do
        if req and (req.status == "FULFILLED" or req.status == "REJECTED" or req.status == "WRITTEN_OFF") then
            local refTs = req.completedAt or req.updatedAt or req.createdAt or 0
            if refTs > 0 and refTs < cutoff and self:GetOwedAmount(req) <= 0 then
                VM.db.requests[id] = nil
                removed = removed + 1
            end
        end
    end
    if removed > 0 then
        VM:LogDebug(string.format("Fulfillment:PruneOldRequests removed %d old requests.", removed))
        if VM.Minimap and VM.Minimap.UpdateBadge then
            VM.Minimap:UpdateBadge()
        end
    end
    return removed
end

function Fulfillment:GetMyPreparedOrders(optionalRecipient)
    local list = {}
    if not VM.db or not VM.db.requests or VM.isUnguilded then return list end
    local me = VM:GetPlayerName()
    if me == "" then return list end

    for _, req in pairs(VM.db.requests) do
        if req and req.status == "PREPARED" and IsSameActor(req.preparedBy, me) then
            if not optionalRecipient or optionalRecipient == "" or IsSameRecipient(req.requester, optionalRecipient) then
                table.insert(list, req)
            end
        end
    end
    table.sort(list, function(a, b) return (a.preparedAt or a.createdAt or 0) < (b.preparedAt or b.createdAt or 0) end)
    return list
end

function Fulfillment:GetPendingAndApprovedCounts()
    local pendingCount, approvedCount = 0, 0
    if not VM.db or not VM.db.requests or VM.isUnguilded then return 0, 0 end
    for _, req in pairs(VM.db.requests) do
        if req.status == "PENDING" then
            pendingCount = pendingCount + 1
        elseif req.status == "APPROVED" then
            approvedCount = approvedCount + 1
        end
    end
    return pendingCount, approvedCount
end

-- Used by BankScanner for direct member withdrawals of APPROVED requests
-- exactOnly: only match when the withdrawn count equals the requested count (bank log auto-completion)
function Fulfillment:FindMatchingApprovedRequest(recipientName, itemID, itemName, count, goldCopper, exactOnly)
    if not VM.db or not VM.db.requests or not recipientName or recipientName == "" then return nil end

    local numID = tonumber(itemID) or 0
    local cleanTargetName = CleanItemName(itemName)
    local qty = tonumber(count) or 0
    local goldAmt = tonumber(goldCopper) or 0

    local bestExact = nil
    local bestCover = nil

    for _, req in pairs(VM.db.requests) do
        if req and req.status == "APPROVED" and IsSameRecipient(req.requester, recipientName) then
            if goldAmt > 0 then
                if req.isGoldRequest then
                    local reqGold = tonumber(req.goldAmount or req.quotedTotalPrice or req.quotedUnitPrice) or 0
                    if reqGold == goldAmt then
                        if not bestExact or (req.createdAt or 0) < (bestExact.createdAt or 0) then
                            bestExact = req
                        end
                    end
                end
            else
                if not req.isGoldRequest then
                    local reqID = tonumber(req.itemID) or 0
                    local reqCleanName = CleanItemName(req.itemName or req.itemLink)
                    local itemMatches = (numID > 0 and reqID > 0 and numID == reqID)
                        or (cleanTargetName ~= "" and reqCleanName ~= "" and cleanTargetName == reqCleanName)

                    if itemMatches then
                        local reqCount = tonumber(req.count) or 1
                        if qty == reqCount then
                            if not bestExact or (req.createdAt or 0) < (bestExact.createdAt or 0) then
                                bestExact = req
                            end
                        elseif qty > reqCount then
                            if not bestCover or (req.createdAt or 0) < (bestCover.createdAt or 0) then
                                bestCover = req
                            end
                        end
                    end
                end
            end
        end
    end

    if exactOnly then return bestExact end
    return bestExact or bestCover
end

-- Used by Mail / Trade auto-complete: prioritizes THIS officer's PREPARED orders, then falls back to APPROVED
function Fulfillment:FindMatchingDeliverableRequest(recipientName, itemID, itemName, count, goldCopper)
    if not VM.db or not VM.db.requests or not recipientName or recipientName == "" then return nil end

    local me = VM:GetPlayerName()
    local numID = tonumber(itemID) or 0
    local cleanTargetName = CleanItemName(itemName)
    local qty = tonumber(count) or 0
    local goldAmt = tonumber(goldCopper) or 0

    local function SearchByStatus(targetStatus, requirePreparedByMe)
        local bestExact = nil
        local bestCover = nil
        for _, req in pairs(VM.db.requests) do
            if req and req.status == targetStatus and IsSameRecipient(req.requester, recipientName) then
                if not requirePreparedByMe or IsSameActor(req.preparedBy, me) then
                    if goldAmt > 0 then
                        if req.isGoldRequest then
                            local reqGold = tonumber(req.goldAmount or req.quotedTotalPrice or req.quotedUnitPrice) or 0
                            if reqGold == goldAmt then
                                if not bestExact or (req.createdAt or 0) < (bestExact.createdAt or 0) then
                                    bestExact = req
                                end
                            end
                        end
                    else
                        if not req.isGoldRequest then
                            local reqID = tonumber(req.itemID) or 0
                            local reqCleanName = CleanItemName(req.itemName or req.itemLink)
                            local itemMatches = (numID > 0 and reqID > 0 and numID == reqID)
                                or (cleanTargetName ~= "" and reqCleanName ~= "" and cleanTargetName == reqCleanName)

                            if itemMatches then
                                local reqCount = tonumber(req.count) or 1
                                if qty == reqCount then
                                    if not bestExact or (req.createdAt or 0) < (bestExact.createdAt or 0) then
                                        bestExact = req
                                    end
                                elseif qty > reqCount then
                                    if not bestCover or (req.createdAt or 0) < (bestCover.createdAt or 0) then
                                        bestCover = req
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        return bestExact or bestCover
    end

    -- Only orders this officer withdrew from the bank are completed automatically; anything else
    -- (own items, approved-but-not-withdrawn orders) needs a deliberate Complete click.
    return SearchByStatus("PREPARED", true)
end

function Fulfillment:CompleteFromTransfer(recipient, itemsByKey, moneySent, method)
    if not VM:IsOfficer() or not recipient or recipient == "" then return 0, {} end
    local completedCount = 0
    local completedReqs = {}

    if moneySent and moneySent > 0 then
        local goldReq = self:FindMatchingDeliverableRequest(recipient, nil, nil, nil, moneySent)
        local goldList = {}
        if goldReq then
            goldList = { goldReq }
        else
            -- Fill All puts several gold requests into one amount: complete them together if they add up
            local sum = 0
            for _, r in ipairs(self:GetMyPreparedOrders(recipient)) do
                if r.isGoldRequest then
                    sum = sum + (tonumber(r.goldAmount or r.quotedTotalPrice or r.quotedUnitPrice) or 0)
                    table.insert(goldList, r)
                end
            end
            if sum ~= moneySent then goldList = {} end
        end
        for _, gr in ipairs(goldList) do
            self:CompleteRequest(gr.id, {
                completedBy = VM:GetPlayerName(),
                method = method
            })
            completedCount = completedCount + 1
            table.insert(completedReqs, gr)
        end
    end

    if itemsByKey then
        for _, entry in pairs(itemsByKey) do
            local remainingQty = tonumber(entry.count) or 0
            local safety = 0
            while remainingQty > 0 and safety < 20 do
                safety = safety + 1
                local matchedReq = self:FindMatchingDeliverableRequest(recipient, entry.itemID, entry.itemName, remainingQty, 0)
                if not matchedReq then break end
                local reqQty = tonumber(matchedReq.count) or 1
                self:CompleteRequest(matchedReq.id, {
                    completedBy = VM:GetPlayerName(),
                    method = method
                })
                remainingQty = remainingQty - reqQty
                completedCount = completedCount + 1
                table.insert(completedReqs, matchedReq)
            end
        end
    end

    return completedCount, completedReqs
end

function Fulfillment:Init()
    self:PruneOldRequests()

    if not sendMailHooked and hooksecurefunc and type(SendMail) == "function" then
        sendMailHooked = true
        hooksecurefunc("SendMail", function(target, subject)
            CaptureMailSnapshot(target, subject)
        end)
    end

    -- Delayed relog reminder if this officer still has unfulfilled PREPARED requests.
    -- Guild rank info may not be available 5s after login, so retry a few times.
    if C_Timer and C_Timer.After then
        local attempts = 0
        local function CheckRelogReminder()
            attempts = attempts + 1
            local _, _, rankIndex = GetGuildInfo("player")
            if (VM.isUnguilded or rankIndex == nil) and attempts < 4 then
                C_Timer.After(5, CheckRelogReminder)
                return
            end
            if not VM.isUnguilded and VM:IsOfficer() then
                local mine = self:GetMyPreparedOrders()
                if #mine > 0 and VM.UI and VM.UI.ShowRelogPreparedReminder then
                    VM.UI:ShowRelogPreparedReminder(mine)
                end
            end
        end
        C_Timer.After(5, CheckRelogReminder)
    end

    local f = CreateFrame("Frame")
    f:RegisterEvent("BAG_UPDATE")
    f:RegisterEvent("PLAYER_MONEY")
    f:RegisterEvent("UI_ERROR_MESSAGE")
    pcall(f.RegisterEvent, f, "BAG_UPDATE_DELAYED")
    f:RegisterEvent("MAIL_SHOW")
    f:RegisterEvent("MAIL_CLOSED")
    f:RegisterEvent("MAIL_SEND_SUCCESS")
    f:RegisterEvent("MAIL_FAILED")
    f:RegisterEvent("TRADE_SHOW")
    f:RegisterEvent("TRADE_MONEY_CHANGED")
    f:RegisterEvent("TRADE_ACCEPT_UPDATE")
    f:RegisterEvent("TRADE_CLOSED")
    f:RegisterEvent("UI_INFO_MESSAGE")

    f:SetScript("OnEvent", function(_, event, arg1, arg2)
        if event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED" or event == "PLAYER_MONEY" then
            self:CheckWithdrawVerification()
        elseif event == "UI_ERROR_MESSAGE" then
            self:NoteWithdrawError(arg1, arg2)
            if VM.Delivery then VM.Delivery:OnUIError((type(arg2) == "string" and arg2) or (type(arg1) == "string" and arg1) or "") end
            self:NoteReturnError((type(arg2) == "string" and arg2) or (type(arg1) == "string" and arg1) or nil)
        elseif event == "MAIL_SHOW" then
            self.isMailOpen = true
            pendingMailSnapshot = nil
            if VM:IsOfficer() then
                local mine = self:GetMyPreparedOrders()
                if #mine > 0 and VM.UI and VM.UI.ShowMailFulfillmentPanel then
                    VM.UI:ShowMailFulfillmentPanel(mine)
                end
            end
        elseif event == "MAIL_CLOSED" then
            self.isMailOpen = false
            if VM.UI and VM.UI.HideMailFulfillmentPanel then
                VM.UI:HideMailFulfillmentPanel()
            end
        elseif event == "MAIL_FAILED" then
            pendingMailSnapshot = nil
            if VM.Delivery then VM.Delivery:OnMailFailed() end
        elseif event == "MAIL_SEND_SUCCESS" then
            local snap = pendingMailSnapshot
            pendingMailSnapshot = nil
            if snap and (time() - (snap.timestamp or 0)) <= 30 then
                local done, reqs = self:CompleteFromTransfer(snap.recipient, snap.items, snap.money, "MAIL")
                if VM.Delivery then VM.Delivery:OnMailSent(snap) end
                if done > 0 then
                    VM:Print(string.format("Mail sent — auto-completed %d request(s).", done))
                    -- CoD stays "awaiting payment" until the CoD money arrives in your mailbox (or the mail comes back)
                    if VM.Delivery then
                        if (snap.cod or 0) > 0 then VM.Delivery:TrackCod(snap, reqs) end
                        VM.Delivery:NotifyMember(reqs, "SENT_MAIL", { cod = snap.cod })
                        VM.Delivery:ScheduleNextMailFill()
                    end
                end
                if VM.UI and VM.UI.ShowMailFulfillmentPanel and self.isMailOpen then
                    local remaining = self:GetMyPreparedOrders()
                    if #remaining > 0 then
                        VM.UI:ShowMailFulfillmentPanel(remaining)
                    elseif VM.UI.HideMailFulfillmentPanel then
                        VM.UI:HideMailFulfillmentPanel()
                    end
                end
            end
        elseif event == "TRADE_SHOW" then
            self.isTradeOpen = true
            currentTradeTargetMoney = 0
            currentTradeTargetName = VM:NormalizeName(UnitName("NPC") or "")
            lastAcceptedTrade = nil
            whisperedInCurrentTrade = {}
            if VM:IsOfficer() and currentTradeTargetName ~= "" then
                local matches = self:GetMyPreparedOrders(currentTradeTargetName)
                local outstanding = self:GetOutstandingFor(currentTradeTargetName)
                if (#matches > 0 or outstanding > 0) and VM.UI and VM.UI.ShowTradeFulfillmentPrompt then
                    VM.UI:ShowTradeFulfillmentPrompt(currentTradeTargetName, matches, outstanding)
                end
            end
        elseif event == "TRADE_MONEY_CHANGED" then
            currentTradeTargetMoney = (GetTargetTradeMoney and GetTargetTradeMoney()) or 0
        elseif event == "TRADE_ACCEPT_UPDATE" then
            if arg1 == 1 or arg2 == 1 then
                CaptureTradeSnapshot()
            end
        elseif event == "UI_INFO_MESSAGE" then
            local msg = (type(arg2) == "string" and arg2) or (type(arg1) == "string" and arg1) or ""
            local tradeDoneStr = ERR_TRADE_COMPLETE or "Trade complete."
            if msg == tradeDoneStr and lastAcceptedTrade and (time() - (lastAcceptedTrade.timestamp or 0)) <= 15 then
                local snap = lastAcceptedTrade
                lastAcceptedTrade = nil

                local outstandingBefore = self:GetOutstandingFor(snap.recipient)
                local done, reqs = self:CompleteFromTransfer(snap.recipient, snap.items, snap.playerMoney, "TRADE")
                if done > 0 then
                    VM:Print(string.format("Trade completed — auto-completed %d request(s).", done))
                end
                -- Gold the member put in the trade pays the delivered requests first, then older debts.
                -- Anything missing stays visible as debt (Requests tab + Ledger) and the member is told.
                if done > 0 or ((snap.targetMoney or 0) > 0 and outstandingBefore > 0) then
                    self:RecordDeliveryPayments(snap.recipient, snap.targetMoney or 0, "TRADE", reqs)
                end
            end
        elseif event == "TRADE_CLOSED" then
            self.isTradeOpen = false
            currentTradeTargetMoney = 0
            currentTradeTargetName = ""
            whisperedInCurrentTrade = {}
            if VM.UI and VM.UI.HideTradeFulfillmentPrompt then
                VM.UI:HideTradeFulfillmentPrompt()
            end
        end
    end)
end

-- Credits a member's CoD/Trade payment at delivery, split across the delivered requests (each payment
-- carries its fulfillmentId so unpaid remainders stay visible as debt). The receiving officer is the
-- holder, so their later Guild Bank deposit of that gold is booked as a transfer (BankScanner:ScanMoneyLogs).
function Fulfillment:RecordDeliveryPayments(payer, amount, method, reqs)
    if not VM.Ledger or not VM.Ledger.RecordPayment then return end
    local remaining = math.floor(tonumber(amount) or 0)
    local holder = VM:GetPlayerName()
    local total = remaining
    local covered = {}

    local function PayInto(req, due)
        local pay = math.min(due, remaining)
        if pay > 0 then
            VM.Ledger:RecordPayment(payer, pay, holder, method, nil, req.id)
            remaining = remaining - pay
        end
    end

    -- 1) The requests delivered right now
    for _, req in ipairs(reqs or {}) do
        covered[req.id] = true
        if not req.isGoldRequest then
            local due = self:GetOwedAmount(req, true)
            if due > 0 then PayInto(req, due) end
        end
    end
    -- 2) Older unpaid trade/manual deliveries of the same member (oldest first)
    if remaining > 0 then
        for _, old in ipairs(self:GetOutstandingRequests(payer)) do
            if remaining <= 0 then break end
            if not covered[old.id] then
                PayInto(old, self:GetOwedAmount(old))
            end
        end
    end
    -- 3) Anything extra is a plain payment (counts as the member's contribution)
    if remaining > 0 then
        VM.Ledger:RecordPayment(payer, remaining, holder, method)
    end

    local stillOwed = self:GetOutstandingFor(payer)
    if total > 0 then
        VM:Print(string.format("Recorded %s payment of %s from |cffffff00%s|r. Deposit it in the Guild Bank as a transfer.",
            method == "MAIL" and "CoD" or method:lower(), VM:FormatMoney(total), VM:NormalizeName(payer)))
    end
    if stillOwed > 0 then
        VM:Print(string.format("|cffff5555%s still owes %s. It is shown on the request and can be marked Paid or written off.|r",
            VM:NormalizeName(payer), VM:FormatMoney(stillOwed)))
    end
    if method == "TRADE" and VM.Delivery then
        VM.Delivery:NotifyTradeResult(payer, total, stillOwed, reqs)
    end
    if VM.UI then VM.UI:RefreshAll() end
end

-- Unpaid trade/manual deliveries of a member (incl. alts of the same main), oldest first.
-- Mail CoD that is still on its way is "awaiting payment", not debt, and is excluded.
function Fulfillment:GetOutstandingRequests(name)
    local list = {}
    local main = VM:GetMainFor(VM:NormalizeName(name))
    if not VM.db or not VM.db.requests or main == "" then return list end
    for _, req in pairs(VM.db.requests) do
        if req.completedMethod ~= "MAIL" and VM:GetMainFor(VM:NormalizeName(req.requester)) == main and self:GetOwedAmount(req) > 0 then
            table.insert(list, req)
        end
    end
    table.sort(list, function(a, b) return (a.completedAt or 0) < (b.completedAt or 0) end)
    return list
end

function Fulfillment:GetOutstandingFor(name)
    local total = 0
    for _, req in ipairs(self:GetOutstandingRequests(name)) do
        total = total + self:GetOwedAmount(req)
    end
    return total
end

-- Payment state of a delivered request: nil (nothing due), "AWAITING_COD" or "OWES"
function Fulfillment:GetPaymentState(req)
    if self:GetOwedAmount(req) <= 0 then return nil end
    return (req.completedMethod == "MAIL") and "AWAITING_COD" or "OWES"
end

-- Complete without Mail/Trade: the officer says whether the member already paid
function Fulfillment:CompleteManually(reqID, paid)
    local req = VM.db.requests[reqID]
    if not req then return end
    local due = req.isGoldRequest and 0 or self:GetExpectedMemberPayment(req)
    self:CompleteRequest(reqID, { method = "MANUAL" })
    local live = VM.db.requests[reqID]
    if live and live.status == "FULFILLED" then
        if paid and due > 0 then
            VM.Ledger:RecordPayment(live.requester, due, VM:GetPlayerName(), "MANUAL", nil, live.id)
        elseif due > 0 then
            VM:Print(string.format("|cffffaa00%s owes %s for this request (shown under Unpaid).|r", live.requester or "?", VM:FormatMoney(due)))
        end
        if VM.Delivery then VM.Delivery:NotifyMember({ live }, "DELIVERED", { owed = paid and 0 or due }) end
    end
    if VM.UI then VM.UI:RefreshAll() end
end

-- CoD mail came back unpaid: the items are with the officer again => back to PREPARED, charge reversed
function Fulfillment:MarkCodReturned(reqID)
    if not VM:IsOfficer() then return end
    local req = VM.db.requests[reqID]
    if not req or req.status ~= "FULFILLED" or req.completedMethod ~= "MAIL" then return end
    local now = time()
    for _, tx in pairs(VM.db.ledger or {}) do
        if tx.fulfillmentId == req.id and not tx.deleted and (tx.source == "REQUEST" or tx.source == "GOLD_REQUEST") then
            VM.Ledger:TombstoneTransaction(tx, "CoD returned")
        end
    end
    req.status = "PREPARED"
    req.preparedBy = VM:GetPlayerName()
    req.preparedAt = now
    req.fulfilledBy = ""
    req.completedAt = 0
    req.completedMethod = ""
    req.updatedAt = now
    VM.Comms:BroadcastRequest(req)
    if VM.Delivery then
        VM.Delivery:ForgetCod(req.id)
        VM.Delivery:NotifyMember({ req }, "COD_RETURNED")
    end
    VM:Print(string.format("CoD mail to |cffffff00%s|r came back: %dx %s is prepared by you again.", req.requester or "?", req.count or 1, req.itemName or "Item"))
    if VM.UI then VM.UI:RefreshAll() end
end

-- Outstanding member payment for a delivered item request.
-- ignoreStatus: compute what is due right now (used while recording the delivery payment).
function Fulfillment:GetOwedAmount(req, ignoreStatus)
    if not req or req.isGoldRequest then return 0 end
    if not ignoreStatus then
        if req.status ~= "FULFILLED" then return 0 end
        local m = req.completedMethod
        if m == "TRADE" then
            -- always tracked
        elseif (m == "MAIL" or m == "MANUAL") and (tonumber(req.completedAt) or 0) >= VM.PAYMENT_TRACKING_SINCE then
            -- CoD awaiting receipt / manual delivery not (yet) paid
        else
            return 0
        end
    end
    local expected = self:GetExpectedMemberPayment(req)
    if expected <= 0 then return 0 end
    local settled = (VM.Ledger and VM.Ledger.GetSettledForRequest) and VM.Ledger:GetSettledForRequest(req.id) or 0
    return math.max(0, expected - settled)
end

-- Officer: the member paid the outstanding amount later (gold is now held by this officer)
function Fulfillment:MarkDebtPaid(reqID)
    if not VM:IsOfficer() then return end
    local req = VM.db.requests[reqID]
    local owed = self:GetOwedAmount(req)
    if owed <= 0 then return end
    VM.Ledger:RecordPayment(req.requester, owed, VM:GetPlayerName(), "MANUAL", "Late payment", req.id)
    VM:Print(string.format("Recorded late payment of %s from |cffffff00%s|r.", VM:FormatMoney(owed), req.requester or "?"))
    if VM.UI then VM.UI:RefreshAll() end
end

-- Officer: write off an unpaid amount. The loss moves to GUILD (Member) and stays visible on the member.
function Fulfillment:WriteOffDebt(reqID)
    if not VM:IsOfficer() then return end
    local req = VM.db.requests[reqID]
    local owed = self:GetOwedAmount(req)
    if owed <= 0 then return end
    VM.Ledger:RecordDebtWriteOff(req, owed, VM:GetPlayerName())
    VM:Print(string.format("Wrote off %s unpaid by |cffffff00%s|r (charged to GUILD — Member).", VM:FormatMoney(owed), req.requester or "?"))
    if VM.UI then VM.UI:RefreshAll() end
end

-- True when this player already has an open request for the same item on the same tab
function Fulfillment:GetMyOpenRequestCount(itemKey, tabIndex)
    if not VM.db or not VM.db.requests then return 0, nil end
    local me = VM:GetPlayerName()
    local total, found = 0, nil
    for _, req in pairs(VM.db.requests) do
        if req and OPEN_STATUSES[req.status] and not req.isGoldRequest
            and (req.itemID == itemKey or req.itemName == itemKey or tostring(req.itemID) == tostring(itemKey))
            and (not tabIndex or tonumber(req.tab) == tonumber(tabIndex))
            and VM:IsSameCharacter(req.requester, me) then
            total = total + (tonumber(req.count) or 0)
            found = found or req
        end
    end
    return total, found
end

-- Member (or officer) cancels their OWN pending/approved request
function Fulfillment:CancelOwnRequest(reqID)
    local req = VM.db.requests[reqID]
    if not req or (req.status ~= "PENDING" and req.status ~= "APPROVED") then return end
    if not VM:IsSameCharacter(req.requester, VM:GetPlayerName()) then return end
    local now = time()
    req.status = "REJECTED"
    req.completedMethod = "CANCELLED"
    req.completedAt = now
    req.updatedAt = now
    VM.Comms:BroadcastRequest(req)
    if VM.Minimap and VM.Minimap.UpdateBadge then VM.Minimap:UpdateBadge() end
    if VM.UI then VM.UI:RefreshAll() end
    VM:Print(string.format("Request cancelled: %s", req.isGoldRequest and VM:FormatMoney(req.goldAmount or 0) or ((req.count or 1) .. "x " .. (req.itemLink or req.itemName or "Item"))))
end

-- Fill Mail / Fill Trade for a PREPARED request from the Requests tab
function Fulfillment:FulfillPrepared(reqID)
    local req = VM.db.requests[reqID]
    if not req or req.status ~= "PREPARED" or not IsSameActor(req.preparedBy, VM:GetPlayerName()) then return end
    local tradeTarget = VM:NormalizeName(UnitName("NPC") or "")
    if self.isTradeOpen and tradeTarget ~= "" and IsSameRecipient(req.requester, tradeTarget) then
        self:PopulateTradeAll(tradeTarget)
    elseif self.isMailOpen or (MailFrame and MailFrame:IsVisible()) then
        self:PopulateMailFor(req.requester)
    else
        VM:Print(string.format("|cffffaa00Open your mailbox or a trade with %s to fulfill this request.|r", req.requester or "?"))
        return
    end
    self.fulfillStarted[req.id] = true
    if VM.UI then VM.UI:RefreshAll() end
end

-- Create new item request (Member / Officer)
function Fulfillment:CreateRequest(tabIndex, itemKey, count)
    local rule = VM:GetTabRule(tabIndex)
    if rule.mode == "LOCKED" then
        VM:Print("|cffff4444This bank tab is locked and cannot be ordered from.|r")
        return
    end

    local tabData = VM.db.inventory.tabs[tabIndex]
    local itemData = tabData and (tabData.items[itemKey] or tabData.items[tonumber(itemKey) or 0])
    if not itemData and tabData and tabData.items then
        for k, itm in pairs(tabData.items) do
            if k == itemKey or itm.itemID == itemKey or itm.name == itemKey or itm.link == itemKey then
                itemData = itm
                itemKey = k
                break
            end
        end
    end
    if not itemData then return end

    local qty = tonumber(count) or 1
    local available = itemData.count - VM:GetReservedCount(itemKey, tabIndex)
    if qty <= 0 or qty > available then
        VM:Print(string.format("|cffff4444Not enough available items (Available: %d).|r", available))
        return
    end

    local maxQty = VM:GetMaxRequestQty(itemData.itemID, itemData.link or itemData.itemLink)
    if maxQty and qty > maxQty then
        VM:Print(string.format("|cffff4444A request can hold at most %d stacks (%d of this item). Split it into several requests.|r",
            VM.MAX_REQUEST_STACKS, maxQty))
        return
    end

    local openQty = self:GetMyOpenRequestCount(itemData.itemID ~= 0 and itemData.itemID or itemData.name, tabIndex)
    if openQty > 0 then
        VM:Print(string.format("|cffffaa00You already have an open request for %dx %s. Cancel it in Requests to change the amount.|r",
            openQty, itemData.link or itemData.name))
        return
    end

    local effectivePrice = VM:GetEffectiveLivePrice(itemData.itemID, itemData.link or itemData.itemLink, itemData.ahPrice)
    local quotedTotal = VM:CalculateMemberTotalPrice(effectivePrice, qty, rule)
    local quotedUnit = (qty > 0) and math.floor(quotedTotal / qty) or quotedTotal

    local now = time()
    local reqID = string.format("REQ_%s_%d_%d", VM:GetPlayerName(), now, math.random(1000, 9999))
    local req = {
        id = reqID,
        requester = VM:GetPlayerName(),
        isGoldRequest = false,
        itemID = itemData.itemID ~= 0 and itemData.itemID or itemData.name,
        itemLink = itemData.link,
        itemName = itemData.name,
        count = qty,
        tab = tabIndex,
        status = "PENDING",
        createdAt = now,
        updatedAt = now,
        approvedBy = "",
        approvedAt = 0,
        preparedBy = "",
        preparedAt = 0,
        fulfilledBy = "",
        completedAt = 0,
        completedMethod = "",
        quotedUnitPrice = quotedUnit,
        quotedTotalPrice = quotedTotal,
        priceAtRequest = effectivePrice,
        priceMode = rule.mode,
        pricePercent = rule.percent or 0,
        deliveryPref = (VM.db.uiPrefs and VM.db.uiPrefs.deliveryPref) or nil,
        reason = ""
    }

    VM.db.requests[reqID] = req
    VM.Comms:BroadcastRequest(req)
    if VM.Minimap and VM.Minimap.UpdateBadge then VM.Minimap:UpdateBadge() end
    VM:Print(string.format("Request sent: %dx %s", qty, itemData.link or itemData.name))
    if VM.UI then VM.UI:RefreshAll() end
    return req
end

-- Create new gold request for guild expenses (Member / Officer)
function Fulfillment:CreateGoldRequest(copperAmount, reason, guildCategory)
    local amount = math.floor(tonumber(copperAmount) or 0)
    local cleanReason = strtrim(tostring(reason or ""))
    if amount <= 0 then
        VM:Print("|cffff4444Please enter a valid gold/silver amount greater than 0.|r")
        return
    end
    if cleanReason == "" then
        VM:Print("|cffff4444Please specify what the guild expense is for.|r")
        return
    end

    local cat = (VM.Ledger and VM.Ledger.NormalizeGuildCategory) and VM.Ledger:NormalizeGuildCategory(guildCategory) or "RAID"
    local now = time()
    local reqID = string.format("REQ_GOLD_%s_%d_%d", VM:GetPlayerName(), now, math.random(1000, 9999))
    local req = {
        id = reqID,
        requester = VM:GetPlayerName(),
        isGoldRequest = true,
        guildCategory = cat,
        itemID = 0,
        itemLink = "GOLD",
        itemName = "Gold Request",
        count = 1,
        tab = 0,
        goldAmount = amount,
        status = "PENDING",
        createdAt = now,
        updatedAt = now,
        approvedBy = "",
        approvedAt = 0,
        preparedBy = "",
        preparedAt = 0,
        fulfilledBy = "",
        completedAt = 0,
        completedMethod = "",
        quotedUnitPrice = amount,
        quotedTotalPrice = amount,
        priceAtRequest = amount,
        priceMode = "GUILD_EXPENSE",
        pricePercent = 0,
        reason = cleanReason
    }

    VM.db.requests[reqID] = req
    VM.Comms:BroadcastRequest(req)
    if VM.Minimap and VM.Minimap.UpdateBadge then VM.Minimap:UpdateBadge() end
    VM:Print(string.format("Gold request sent: %s (%s)", VM:FormatMoney(amount), cleanReason))
    if VM.UI then VM.UI:RefreshAll() end
end

-- Approve request (Officer) -> Activates soft-lock for items
function Fulfillment:ApproveRequest(reqID)
    if not VM:IsOfficer() then return end
    local req = VM.db.requests[reqID]
    if not req or req.status ~= "PENDING" then return end

    local now = time()
    req.status = "APPROVED"
    req.approvedBy = VM:GetPlayerName()
    req.approvedAt = now
    req.updatedAt = now

    -- Lock the member price at approval: Ledger, CoD, trade whisper and debt all use this amount
    if not req.isGoldRequest then
        local live = VM:GetEffectiveLivePrice(req.itemID, req.itemLink, req.priceAtRequest or req.quotedUnitPrice)
        if live and live > 0 then
            local qty = tonumber(req.count) or 1
            local total = VM:CalculateMemberTotalPrice(live, qty, { mode = req.priceMode or "FREE", percent = req.pricePercent or 50 })
            req.priceAtRequest = live
            req.quotedTotalPrice = total
            req.quotedUnitPrice = (qty > 0) and math.floor(total / qty) or total
        end
    end

    VM.Comms:BroadcastRequest(req)
    if VM.Minimap and VM.Minimap.UpdateBadge then VM.Minimap:UpdateBadge() end
    if VM.UI then VM.UI:RefreshAll() end
    if VM.Delivery then VM.Delivery:NotifyMember({ req }, "APPROVED") end
end

-- Approve and immediately withdraw (one click at the Guild Bank)
function Fulfillment:ApproveAndWithdraw(reqID)
    self:ApproveRequest(reqID)
    local req = VM.db.requests[reqID]
    if req and req.status == "APPROVED" then
        self:PrepareRequest(reqID)
    end
end

-- Helper to mark request PREPARED (or FULFILLED directly if officer prepared their own/alt request at the bank)
function Fulfillment:FinalizePreparedState(req, withdrawnFromBank)
    local me = VM:GetPlayerName()
    local now = time()

    if withdrawnFromBank and IsSameRecipient(req.requester, me) then
        self:CompleteRequest(req.id, {
            completedBy = me,
            completedAt = now,
            method = "BANK"
        })
        VM:Print("Withdrew your own request directly from the Guild Bank — marked Fulfilled.")
        return
    end

    req.status = "PREPARED"
    req.preparedBy = me
    req.preparedAt = now
    req.updatedAt = now
    self.activeOrder = req

    VM.Comms:BroadcastRequest(req)
    if VM.Minimap and VM.Minimap.UpdateBadge then VM.Minimap:UpdateBadge() end
    if VM.UI then VM.UI:RefreshAll() end

    if req.isGoldRequest then
        VM:Print(string.format("Prepared gold request (%s) for |cffffff00%s|r. Open Mail or Trade to fulfill.",
            VM:FormatMoney(req.goldAmount or req.quotedTotalPrice or 0), req.requester))
    else
        VM:Print(string.format("Prepared %dx %s for |cffffff00%s|r. Open Mail or Trade to fulfill.",
            req.count or 1, req.itemLink or req.itemName or "Item", req.requester))
    end
    if VM.Delivery then VM.Delivery:NotifyMember({ req }, "READY") end
end

-- Merge partial stacks of a withdrawn item so it fits the Trade window (max 6 stacks)
function Fulfillment:ConsolidateStacks(req)
    if not req or req.isGoldRequest then return end
    local maxStack = VM:GetItemMaxStack(tonumber(req.itemID), req.itemLink)
    if not maxStack or maxStack <= 1 then return end
    local merges = 0
    local function Step()
        if merges >= 8 then return end
        local partials = {}
        for bag = 0, 4 do
            for slot = 1, GetContainerSlotCount(bag) do
                local link, count, locked = GetBagSlotInfo(bag, slot)
                if link and count and count > 0 and count < maxStack and not locked then
                    local id = tonumber(link:match("item:(%d+)")) or 0
                    if DoesItemMatchRequest(id, link:match("%[(.-)%]") or link, req) then
                        table.insert(partials, { bag = bag, slot = slot, count = count })
                    end
                end
            end
        end
        if #partials < 2 then return end
        table.sort(partials, function(a, b) return a.count < b.count end)
        local src, dst = partials[1], partials[#partials]
        merges = merges + 1
        ClearCursor()
        PickupBagSlot(src.bag, src.slot)
        PickupBagSlot(dst.bag, dst.slot)
        if CursorHasItem and CursorHasItem() then ClearCursor() end
        if C_Timer and C_Timer.After then C_Timer.After(0.4, Step) end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.6, Step) end
end

--------------------------------------------------------------------------------
-- Verified Guild Bank withdrawal (Prepare)
-- A request only becomes PREPARED/FULFILLED after the items arrived in the bags
-- (BAG_UPDATE) or the gold arrived (PLAYER_MONEY). Otherwise it stays APPROVED.
--------------------------------------------------------------------------------
local WITHDRAW_VERIFY_TIMEOUT = 5
local withdrawSession = nil

local function CountMatchingInBags(req)
    local total = 0
    for bag = 0, 4 do
        local numSlots = GetContainerSlotCount(bag)
        for slot = 1, numSlots do
            local link, count = GetBagSlotInfo(bag, slot)
            if link and count and count > 0 then
                local id = tonumber(link:match("item:(%d+)")) or 0
                local name = link:match("%[(.-)%]") or link
                if DoesItemMatchRequest(id, name, req) then
                    total = total + count
                end
            end
        end
    end
    return total
end

local verifyFrame = CreateFrame("Frame")
verifyFrame:Hide()
local verifyAccum = 0
verifyFrame:SetScript("OnUpdate", function(selfFrame, elapsed)
    if not withdrawSession or not withdrawSession.verifying then
        selfFrame:Hide()
        return
    end
    verifyAccum = verifyAccum + elapsed
    if verifyAccum < 0.25 then return end
    verifyAccum = 0
    Fulfillment:CheckWithdrawVerification()
end)

function Fulfillment:NoteWithdrawError(arg1, arg2)
    if not withdrawSession then return end
    local msg = (type(arg2) == "string" and arg2) or (type(arg1) == "string" and arg1) or nil
    if msg and msg ~= "" then
        withdrawSession.lastError = msg
    end
end

local function EndWithdrawSession()
    withdrawSession = nil
    Fulfillment.isWithdrawing = false
    Fulfillment.prepareBusy = false
    verifyFrame:Hide()
end

function Fulfillment:FailWithdraw(reason)
    local s = withdrawSession
    if not s then return end
    local req = s.req
    local gained = 0
    if s.kind == "ITEM" then
        gained = math.max(0, CountMatchingInBags(req) - (s.before or 0))
    else
        gained = math.max(0, ((GetMoney and GetMoney()) or 0) - (s.before or 0))
    end
    EndWithdrawSession()

    -- Release the withdraw claim so the request can be picked up again
    local liveReq = VM.db.requests[req.id]
    if liveReq and liveReq.status == "APPROVED" and IsSameActor(liveReq.preparedBy, VM:GetPlayerName()) then
        SetClaim(liveReq, nil)
    end

    local detail = s.lastError and (" Server: " .. s.lastError) or ""
    VM:Print(string.format("|cffff4444Prepare failed: %s%s Request stays APPROVED.|r", reason or "withdrawal was not confirmed.", detail))
    if gained > 0 then
        if s.kind == "ITEM" then
            VM:Print(string.format("|cffffaa00%d of %d item(s) did arrive in your bags. Put them back or click Prepare again after the bank updates.|r",
                gained, s.expected or 0))
        else
            VM:Print(string.format("|cffffaa00%s arrived in your bags (expected %s).|r", VM:FormatMoney(gained), VM:FormatMoney(s.expected or 0)))
        end
    end
    if VM.BankScanner and VM.BankScanner.SchedulePostWithdrawScan then
        VM.BankScanner:SchedulePostWithdrawScan()
    end
    if VM.UI then VM.UI:RefreshAll() end
end

function Fulfillment:CheckWithdrawVerification()
    local s = withdrawSession
    if not s or not s.verifying then return end
    local gained
    if s.kind == "ITEM" then
        gained = CountMatchingInBags(s.req) - (s.before or 0)
    else
        gained = ((GetMoney and GetMoney()) or 0) - (s.before or 0)
    end

    if gained >= (s.expected or 0) then
        local req = s.req
        local kind = s.kind
        EndWithdrawSession()
        local live = VM.db.requests[req.id]
        if live and live.status == "APPROVED" then
            self:FinalizePreparedState(live, true)
        end
        if kind == "ITEM" then
            self:ConsolidateStacks(req)
        end
        if VM.BankScanner and VM.BankScanner.SchedulePostWithdrawScan then
            VM.BankScanner:SchedulePostWithdrawScan()
        end
        return
    end

    if GetTime() > (s.deadline or 0) then
        self:FailWithdraw("the items/gold did not arrive in your bags in time (is the Guild Bank open?).")
    end
end

local function StartVerification(s, extraSec)
    s.verifying = true
    s.deadline = GetTime() + WITHDRAW_VERIFY_TIMEOUT + (extraSec or 0)
    verifyAccum = 0
    verifyFrame:Show()
    Fulfillment:CheckWithdrawVerification()
end

-- Bank closed (explicit close signal): queued steps fail on their own (empty cursor); in-flight
-- withdrawals keep verifying until their timeout.
function Fulfillment:OnGuildBankClosed()
end

-- Executes Guild Bank item withdrawal steps into reserved empty bag slots, then verifies arrival
function Fulfillment:ExecuteBankWithdrawSteps(req, tab, steps)
    local s = withdrawSession
    if not s then return end

    local function RunStep(idx)
        if withdrawSession ~= s then return end
        local step = steps[idx]
        if not step then
            StartVerification(s, 0)
            return
        end

        ClearCursor()
        if step.isFullStack then
            if PickupGuildBankItem then
                PickupGuildBankItem(tab, step.gbSlot)
            end
        else
            if SplitGuildBankItem then
                SplitGuildBankItem(tab, step.gbSlot, step.takeCount)
            end
        end
        if GetCursorInfo and not GetCursorInfo() then
            -- Nothing landed on the cursor: the bank is not reachable (closed/out of range) or the slot is locked
            Fulfillment:FailWithdraw("nothing could be picked up from the Guild Bank. Make sure the Guild Bank window is open and you are standing at the banker.")
            return
        end
        PickupBagSlot(step.destBag, step.destSlot)
        -- If the drop was rejected the item is still on the cursor: return it instead of leaving it there
        if CursorHasItem and CursorHasItem() then
            ClearCursor()
        end

        if idx < #steps and C_Timer and C_Timer.After then
            C_Timer.After(0.35, function() RunStep(idx + 1) end)
        else
            RunStep(idx + 1)
        end
    end

    RunStep(1)
end

local function BeginPrepare(self, req)
    if req.isGoldRequest then
        local goldAmt = tonumber(req.goldAmount or req.quotedTotalPrice or req.quotedUnitPrice) or 0
        if goldAmt <= 0 then return end

        local bankGold = (GetGuildBankMoney and GetGuildBankMoney()) or 0
        if bankGold < goldAmt then
            VM:Print(string.format("|cffff4444Not enough gold in Guild Bank (Have: %s, Need: %s).|r",
                VM:FormatMoney(bankGold), VM:FormatMoney(goldAmt)))
            return
        end
        local limit = (GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney()) or -1
        if limit >= 0 and limit < goldAmt then
            VM:Print(string.format("|cffff4444Your daily Guild Bank withdraw limit (%s) is below %s.|r",
                VM:FormatMoney(limit), VM:FormatMoney(goldAmt)))
            return
        end
        if CanWithdrawGuildBankMoney and not CanWithdrawGuildBankMoney() then
            VM:Print("|cffff4444Your guild rank is not allowed to withdraw gold from the Guild Bank.|r")
            return
        end
        if not WithdrawGuildBankMoney then
            VM:Print("|cffff4444This client does not support Guild Bank gold withdrawal.|r")
            return
        end

        self.isWithdrawing = true
        withdrawSession = {
            req = req,
            kind = "GOLD",
            before = (GetMoney and GetMoney()) or 0,
            expected = goldAmt,
        }
        WithdrawGuildBankMoney(goldAmt)
        StartVerification(withdrawSession, 0)
        return
    end

    -- Item Request
    local needed = tonumber(req.count) or 1
    local targetTab = tonumber(req.tab) or 1

    if GetGuildBankTabInfo then
        local _, _, isViewable, _, _, remaining = GetGuildBankTabInfo(targetTab)
        if isViewable == false then
            VM:Print(string.format("|cffff4444You cannot view Guild Bank Tab %d.|r", targetTab))
            return
        end
        if type(remaining) == "number" and remaining == 0 then
            VM:Print(string.format("|cffff4444You have no item withdrawals left today on Guild Bank Tab %d.|r", targetTab))
            return
        end
    end

    self.isWithdrawing = true
    withdrawSession = {
        req = req,
        kind = "ITEM",
        before = CountMatchingInBags(req),
        expected = needed,
    }
    local session = withdrawSession

    local function ScanAndWithdrawFromTab(attempt)
        if withdrawSession ~= session then return end

        local matchingSlots = {}
        local totalAvailable = 0
        for slot = 1, MAX_SLOTS_PER_TAB do
            local _, count, locked = GetGuildBankItemInfo(targetTab, slot)
            local link = GetGuildBankItemLink(targetTab, slot)
            if link and count and count > 0 and not locked then
                local id = tonumber(link:match("item:(%d+)")) or 0
                local name = link:match("%[(.-)%]") or link
                if DoesItemMatchRequest(id, name, req) then
                    table.insert(matchingSlots, { slot = slot, count = count })
                    totalAvailable = totalAvailable + count
                end
            end
        end

        if totalAvailable < needed then
            if attempt < 3 and C_Timer and C_Timer.After then
                if SetCurrentGuildBankTab then SetCurrentGuildBankTab(targetTab) end
                if QueryGuildBankTab then QueryGuildBankTab(targetTab) end
                C_Timer.After(0.6, function() ScanAndWithdrawFromTab(attempt + 1) end)
                return
            end
            Fulfillment:FailWithdraw(string.format("only %d of %d %s found in Tab %d (is the Guild Bank open?).",
                totalAvailable, needed, req.itemLink or req.itemName or "Item", targetTab))
            return
        end

        -- Prefer exact-match or smaller stacks first to minimize splitting
        table.sort(matchingSlots, function(a, b)
            if a.count == needed and b.count ~= needed then return true end
            if b.count == needed and a.count ~= needed then return false end
            return a.count < b.count
        end)

        local empties = GetEmptyGeneralBagSlots()
        local steps = {}
        local remaining = needed
        local emptyIdx = 1

        for _, slotInfo in ipairs(matchingSlots) do
            if remaining <= 0 then break end
            if not empties[emptyIdx] then
                Fulfillment:FailWithdraw(string.format("not enough free general bag slots to withdraw %dx %s.",
                    needed, req.itemLink or req.itemName or "Item"))
                return
            end
            local take = math.min(slotInfo.count, remaining)
            table.insert(steps, {
                gbSlot = slotInfo.slot,
                takeCount = take,
                isFullStack = (take == slotInfo.count),
                destBag = empties[emptyIdx].bag,
                destSlot = empties[emptyIdx].slot,
            })
            remaining = remaining - take
            emptyIdx = emptyIdx + 1
        end

        if GetGuildBankTabInfo then
            local _, _, _, _, _, remainingWithdrawals = GetGuildBankTabInfo(targetTab)
            if type(remainingWithdrawals) == "number" and remainingWithdrawals >= 0 and remainingWithdrawals < #steps then
                Fulfillment:FailWithdraw(string.format("this needs %d stack withdrawal(s) but you only have %d left today on Tab %d.",
                    #steps, remainingWithdrawals, targetTab))
                return
            end
        end

        Fulfillment:ExecuteBankWithdrawSteps(req, targetTab, steps)
    end

    local curTab = (GetCurrentGuildBankTab and GetCurrentGuildBankTab()) or 0
    if curTab ~= targetTab then
        if SetCurrentGuildBankTab then SetCurrentGuildBankTab(targetTab) end
        if QueryGuildBankTab then QueryGuildBankTab(targetTab) end
        if C_Timer and C_Timer.After then
            C_Timer.After(0.40, function() ScanAndWithdrawFromTab(1) end)
        else
            ScanAndWithdrawFromTab(1)
        end
    else
        ScanAndWithdrawFromTab(1)
    end
end

-- Prepare request: confirms the Guild Bank is reachable (works with bag addons / no open events),
-- withdraws, and only marks PREPARED/FULFILLED after the withdrawal is verified.
function Fulfillment:PrepareRequest(reqID)
    if not VM:IsOfficer() then return end
    local req = VM.db.requests[reqID]
    if not req or req.status ~= "APPROVED" then return end

    if self.isWithdrawing or self.prepareBusy then
        VM:Print("|cffffaa00Already withdrawing a request from the Guild Bank. Please wait a moment.|r")
        return
    end
    local me = VM:GetPlayerName()
    local claim = self:GetActiveClaim(req)
    if claim and not IsSameActor(claim, me) then
        VM:Print(string.format("|cffffaa00%s is already withdrawing this request.|r", claim))
        return
    end

    -- Claim the request guild-wide first, so two officers never withdraw the same order
    self.prepareBusy = true
    SetClaim(req, me)

    local function Proceed()
        local live = VM.db.requests[reqID]
        if not live or live.status ~= "APPROVED" or not IsSameActor(live.preparedBy, me) then
            self.prepareBusy = false
            local other = live and self:GetActiveClaim(live)
            VM:Print(string.format("|cffffaa00%s is already withdrawing this request.|r", other or "Another officer"))
            if VM.UI then VM.UI:RefreshAll() end
            return
        end
        BeginPrepare(self, live)
        if not withdrawSession then
            -- A pre-check failed (stock, permissions, bag space): release the claim again
            self.prepareBusy = false
            SetClaim(live, nil)
            if VM.UI then VM.UI:RefreshAll() end
        end
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(1.0, Proceed)
    else
        Proceed()
    end
end

-- Release a PREPARED request back to APPROVED (if responsible officer returns item or cancels prepare)
function Fulfillment:ReleasePreparedRequest(reqID)
    if not VM:IsOfficer() then return end
    local req = VM.db.requests[reqID]
    if not req or req.status ~= "PREPARED" then return end

    local now = time()
    req.status = "APPROVED"
    req.preparedBy = ""
    req.preparedAt = 0
    req.updatedAt = now
    self.fulfillStarted[req.id] = nil

    if self.activeOrder and self.activeOrder.id == req.id then
        self.activeOrder = nil
    end

    VM.Comms:BroadcastRequest(req)
    if VM.Minimap and VM.Minimap.UpdateBadge then VM.Minimap:UpdateBadge() end
    if VM.UI then VM.UI:RefreshAll() end
    VM:Print("Request returned to APPROVED status.")
end

-- Return: put a PREPARED order's items/gold back into the Guild Bank (verified), then release it to APPROVED
local returnSession = nil
local returnFrame = CreateFrame("Frame")
returnFrame:Hide()
local returnAccum = 0

local function CountReqItemsInBags(req)
    local total = 0
    for bag = 0, 4 do
        for slot = 1, GetContainerSlotCount(bag) do
            local link, count = GetBagSlotInfo(bag, slot)
            if link and count and count > 0 then
                local id = tonumber(link:match("item:(%d+)")) or 0
                if DoesItemMatchRequest(id, link:match("%[(.-)%]") or link, req) then
                    total = total + count
                end
            end
        end
    end
    return total
end

local function FinishReturn(ok, msg)
    local s = returnSession
    returnSession = nil
    returnFrame:Hide()
    Fulfillment.isWithdrawing = false
    if not s then return end
    if ok then
        Fulfillment:ReleasePreparedRequest(s.req.id)
        VM:Print("Returned to the Guild Bank — request is APPROVED again.")
    else
        VM:Print("|cffff4444Return failed: " .. (msg or "not confirmed") .. (s.lastError and (" Server: " .. s.lastError) or "") .. "|r")
    end
    if VM.BankScanner and VM.BankScanner.SchedulePostWithdrawScan then
        VM.BankScanner:SchedulePostWithdrawScan()
    end
end

returnFrame:SetScript("OnUpdate", function(selfFrame, elapsed)
    local s = returnSession
    if not s or not s.verifying then selfFrame:Hide() return end
    returnAccum = returnAccum + elapsed
    if returnAccum < 0.25 then return end
    returnAccum = 0
    local done
    if s.kind == "GOLD" then
        done = (s.before - ((GetMoney and GetMoney()) or 0)) >= s.expected
    else
        done = (s.before - CountReqItemsInBags(s.req)) >= s.expected
    end
    if done then
        FinishReturn(true)
    elseif GetTime() > s.deadline then
        FinishReturn(false, "the Guild Bank did not receive the items/gold in time (is the Guild Bank open?).")
    end
end)

function Fulfillment:ReturnPreparedRequest(reqID)
    if not VM:IsOfficer() or self.isWithdrawing then return end
    local req = VM.db.requests[reqID]
    if not req or req.status ~= "PREPARED" or not IsSameActor(req.preparedBy, VM:GetPlayerName()) then return end

    local function Proceed(ok)
        if not ok then
            VM:Print("|cffff4444Open the Guild Bank to return this request.|r")
            return
        end
        local live = VM.db.requests[reqID]
        if not live or live.status ~= "PREPARED" or self.isWithdrawing then return end

        if live.isGoldRequest then
            local amt = tonumber(live.goldAmount or live.quotedTotalPrice or live.quotedUnitPrice) or 0
            local have = (GetMoney and GetMoney()) or 0
            if amt <= 0 or have < amt or not DepositGuildBankMoney then
                VM:Print(string.format("|cffff4444You need %s in your bags to return this gold request.|r", VM:FormatMoney(amt)))
                return
            end
            self.isWithdrawing = true
            returnSession = { req = live, kind = "GOLD", before = have, expected = amt, verifying = true, deadline = GetTime() + 5 }
            DepositGuildBankMoney(amt)
            returnFrame:Show()
            return
        end

        local needed = tonumber(live.count) or 1
        local have = CountReqItemsInBags(live)
        if have < needed then
            VM:Print(string.format("|cffff4444Only %d of %d %s are in your bags. Put them back manually, or Cancel the request (items stay charged to you).|r",
                have, needed, live.itemLink or live.itemName or "Item"))
            return
        end

        local tab = tonumber(live.tab) or 1
        if SetCurrentGuildBankTab and GetCurrentGuildBankTab and GetCurrentGuildBankTab() ~= tab then
            SetCurrentGuildBankTab(tab)
        end
        local emptySlots = {}
        for slot = 1, MAX_SLOTS_PER_TAB do
            if not GetGuildBankItemLink(tab, slot) and not GetGuildBankItemInfo(tab, slot) then
                table.insert(emptySlots, slot)
            end
        end

        -- Build deposit steps (split a larger own stack so exactly the requested amount goes back)
        local steps, remaining = {}, needed
        for bag = 0, 4 do
            for slot = 1, GetContainerSlotCount(bag) do
                if remaining <= 0 then break end
                local link, count, locked = GetBagSlotInfo(bag, slot)
                if link and count and count > 0 and not locked then
                    local id = tonumber(link:match("item:(%d+)")) or 0
                    if DoesItemMatchRequest(id, link:match("%[(.-)%]") or link, live) then
                        local take = math.min(count, remaining)
                        table.insert(steps, { bag = bag, slot = slot, take = take, full = (take == count) })
                        remaining = remaining - take
                    end
                end
            end
        end
        if #steps > #emptySlots then
            VM:Print(string.format("|cffff4444Guild Bank Tab %d needs %d free slot(s) for the return.|r", tab, #steps))
            return
        end

        self.isWithdrawing = true
        returnSession = { req = live, kind = "ITEM", before = have, expected = needed, deadline = GetTime() + 5 + #steps * 0.4 }
        local session = returnSession
        local function RunStep(i)
            if returnSession ~= session then return end
            local st = steps[i]
            if not st then
                session.verifying = true
                returnFrame:Show()
                return
            end
            ClearCursor()
            if st.full then
                PickupBagSlot(st.bag, st.slot)
            else
                SplitBagSlot(st.bag, st.slot, st.take)
            end
            if PickupGuildBankItem then PickupGuildBankItem(tab, emptySlots[i]) end
            if CursorHasItem and CursorHasItem() then ClearCursor() end
            if C_Timer and C_Timer.After then
                C_Timer.After(0.35, function() RunStep(i + 1) end)
            else
                RunStep(i + 1)
            end
        end
        RunStep(1)
    end

    if VM.BankScanner and VM.BankScanner.EnsureBankOpen then
        VM.BankScanner:EnsureBankOpen(Proceed)
    else
        Proceed(IsBankCurrentlyOpen())
    end
end

function Fulfillment:NoteReturnError(msg)
    if returnSession and msg and msg ~= "" then returnSession.lastError = msg end
end

-- Write off a PREPARED request when the responsible officer has left the guild
function Fulfillment:WriteOffRequest(reqID)
    if not VM:IsOfficer() then return end
    local req = VM.db.requests[reqID]
    if not req or req.status ~= "PREPARED" then return end

    local departed = VM:NormalizeName(req.preparedBy or "")
    if departed == "" then return end

    local now = time()
    local me = VM:GetPlayerName()
    VM.Ledger:RecordWriteOff(req, me)

    req.status = "WRITTEN_OFF"
    req.fulfilledBy = me
    req.completedAt = now
    req.completedMethod = "WRITEOFF"
    req.updatedAt = now

    if self.activeOrder and self.activeOrder.id == req.id then
        self.activeOrder = nil
    end

    VM.Comms:BroadcastRequest(req)
    if VM.Minimap and VM.Minimap.UpdateBadge then VM.Minimap:UpdateBadge() end
    if VM.UI then VM.UI:RefreshAll() end
    VM:Print(string.format("Request written off and charged to departed officer |cffffff00%s|r.", departed))
end

-- Reject / cancel request (Officer)
function Fulfillment:RejectRequest(reqID)
    if not VM:IsOfficer() then return end
    local req = VM.db.requests[reqID]
    if not req or (req.status ~= "PENDING" and req.status ~= "APPROVED" and req.status ~= "PREPARED") then return end

    local now = time()
    req.status = "REJECTED"
    req.approvedBy = VM:GetPlayerName()
    req.completedAt = now
    req.updatedAt = now

    if self.activeOrder and self.activeOrder.id == req.id then
        self.activeOrder = nil
    end

    VM.Comms:BroadcastRequest(req)
    if VM.Minimap and VM.Minimap.UpdateBadge then VM.Minimap:UpdateBadge() end
    if VM.UI then VM.UI:RefreshAll() end
    if VM.Delivery then VM.Delivery:NotifyMember({ req }, "REJECTED") end
end

-- Mark order as fulfilled -> Record in ledger (unless skipLedger) & release soft-lock
function Fulfillment:CompleteRequest(reqID, opts)
    if not VM:IsOfficer() then return end
    local req = VM.db.requests[reqID]
    if not req or (req.status ~= "APPROVED" and req.status ~= "PREPARED") then return end

    local now = time()
    local completedBy = VM:NormalizeName((opts and opts.completedBy) or VM:GetPlayerName())
    local completedAt = (opts and opts.completedAt) or now
    local method = (opts and opts.method) or "MANUAL"
    -- Not withdrawn through Vault Manager => the officer took the goods by hand (reconcile below)
    local wasApproved = (req.status == "APPROVED")

    self.fulfillStarted[req.id] = nil
    req.status = "FULFILLED"
    req.fulfilledBy = completedBy
    req.completedAt = completedAt
    req.completedMethod = method
    req.updatedAt = now

    if not (opts and opts.skipLedger) then
        if req.isGoldRequest then
            VM.Ledger:RecordGoldFulfillment(req, completedBy, completedAt)
        else
            VM.Ledger:RecordFulfillment(req, completedBy, completedAt)
        end
        if method ~= "BANK" and wasApproved then
            self:ReconcileDirectWithdrawal(req, completedBy)
        end
    end

    if self.activeOrder and self.activeOrder.id == req.id then
        self.activeOrder = nil
    end

    VM.Comms:BroadcastRequest(req)
    if VM.Minimap and VM.Minimap.UpdateBadge then VM.Minimap:UpdateBadge() end
    if VM.UI then VM.UI:RefreshAll() end
end

-- The officer withdrew the items/gold by hand before completing: that bank-log withdrawal was booked on
-- the officer at 100% (OUT_DIR / gold OUT). It is the same goods as this request => tombstone it.
function Fulfillment:ReconcileDirectWithdrawal(req, officerName)
    local actor = VM:CanonicalActor(officerName)
    local now = time()
    local WINDOW = 48 * 3600
    local best = nil
    for _, tx in pairs(VM.db.ledger or {}) do
        if tx.type == "OUT" and not tx.deleted and not tx.voided and math.abs(now - (tx.timestamp or 0)) <= WINDOW
            and VM:CanonicalActor(tx.rawSender or tx.player) == actor then
            if req.isGoldRequest then
                local amt = tonumber(req.goldAmount or req.quotedTotalPrice) or 0
                if tx.source == "BANK_MONEY_LOG" and (tx.unitPriceAtTime or 0) * (tx.count or 1) == amt then best = tx end
            elseif (tx.source == "BANK_LOG" or tx.source == "FFA_SCAN") and (tonumber(tx.count) or 1) == (tonumber(req.count) or 1)
                and VM:NormalizeItemKey(tx.itemID, tx.itemLink, tx.itemName) == VM:NormalizeItemKey(req.itemID, req.itemLink, req.itemName) then
                best = tx
            end
        end
        if best then break end
    end
    if best then
        VM.Ledger:TombstoneTransaction(best, "Reconciled with request " .. tostring(req.id))
        VM:LogDebug("Reconciled direct withdrawal with request " .. tostring(req.id))
    end
end

function Fulfillment:GetApprovedOrders()
    local list = {}
    for _, req in pairs(VM.db.requests) do
        if req.status == "APPROVED" then
            table.insert(list, req)
        end
    end
    table.sort(list, function(a, b) return (a.createdAt or 0) < (b.createdAt or 0) end)
    return list
end

-- Auto-opens VM when Guild Bank opens: Requests tab if officer has open orders, otherwise Vault & Requests
-- attempt: 1..3 (repeated shortly after the bank opened); openedAt: GetTime() of the bank session start
function Fulfillment:OnGuildBankOpened(attempt, openedAt)
    attempt = attempt or 1
    if not VM.UI then return end
    local mf = _G["VaultManagerMainFrame"]
    if attempt > 1 then
        -- Retries only while the bank is open, the window is not up and the player did not close it
        if VM.BankScanner and not VM.BankScanner:IsBankOpen() then return end
        if mf and mf:IsShown() then return end
        if (VM.UI.userClosedAt or 0) >= (openedAt or 0) then
            VM:LogDebug("AutoOpen: retry " .. attempt .. " skipped (closed by player)")
            return
        end
    end
    local prefs = VM.db and VM.db.uiPrefs
    local autoOpen = not (prefs and prefs.autoOpenAtBank == false)

    local isOff = VM:IsOfficer()
    local pendingCount, approvedCount, preparedCount = 0, 0, 0
    if isOff then
        pendingCount, approvedCount = self:GetPendingAndApprovedCounts()
        preparedCount = #self:GetMyPreparedOrders()
    end
    local hasWork = (pendingCount + approvedCount + preparedCount) > 0

    if hasWork and attempt == 1 then
        VM:Print(string.format("Guild Bank: %d pending, %d approved, %d prepared by you.", pendingCount, approvedCount, preparedCount))
    end

    if not autoOpen then
        VM:LogDebug("AutoOpen: disabled in Settings")
        if hasWork and attempt == 1 and VM.UI.ShowBankReminder then
            VM.UI:ShowBankReminder(pendingCount, approvedCount, preparedCount)
        end
        return
    end

    VM:LogDebug(string.format("AutoOpen: attempt %d -> %s", attempt, hasWork and "Requests" or "Vault"))
    if hasWork and VM.UI.OpenToRequestsTab then
        VM.UI:OpenToRequestsTab(true)
    elseif VM.UI.OpenToVaultTab then
        VM.UI:OpenToVaultTab(true)
    end
    if mf and not mf:IsShown() then
        VM:LogDebug("AutoOpen: window did not stay open")
    end
end

-- Safe bag-to-target attachment with 2-step split via an empty bag slot (Classic-safe)
local function AttachItemsFromBags(req, attachFn)
    local remaining = tonumber(req.count) or 1
    local exactOrSmaller = {}
    local larger = {}

    for bag = 0, 4 do
        local numSlots = GetContainerSlotCount(bag)
        for slot = 1, numSlots do
            local link, count, locked = GetBagSlotInfo(bag, slot)
            if link and count and count > 0 and not locked then
                local id = tonumber(link:match("item:(%d+)")) or 0
                local name = link:match("%[(.-)%]") or link
                if DoesItemMatchRequest(id, name, req) then
                    if count <= remaining then
                        table.insert(exactOrSmaller, { bag = bag, slot = slot, count = count })
                    else
                        table.insert(larger, { bag = bag, slot = slot, count = count })
                    end
                end
            end
        end
    end

    -- Prefer exact matches first, then largest full stacks <= remaining
    table.sort(exactOrSmaller, function(a, b) return a.count > b.count end)

    for _, entry in ipairs(exactOrSmaller) do
        if remaining <= 0 then break end
        if entry.count <= remaining then
            ClearCursor()
            PickupBagSlot(entry.bag, entry.slot)
            if attachFn() then
                remaining = remaining - entry.count
            else
                ClearCursor()
                return remaining
            end
        end
    end

    if remaining > 0 and #larger > 0 then
        table.sort(larger, function(a, b) return a.count < b.count end)
        local src = larger[1]
        local empties = GetEmptyGeneralBagSlots()
        if #empties == 0 then
            VM:Print("|cffff4444Free 1 general bag slot so Vault Manager can split the item stack.|r")
            return remaining
        end

        local dest = empties[1]
        ClearCursor()
        SplitBagSlot(src.bag, src.slot, remaining)
        PickupBagSlot(dest.bag, dest.slot)
        ClearCursor()

        local function AttachSplitSlot()
            ClearCursor()
            PickupBagSlot(dest.bag, dest.slot)
            if not attachFn() then
                ClearCursor()
            end
        end

        if C_Timer and C_Timer.After then
            C_Timer.After(0.25, AttachSplitSlot)
        else
            AttachSplitSlot()
        end
        remaining = 0
    end

    return remaining
end

-- Finds items in player's bags (or sets Send Money for gold requests) in Send Mail
function Fulfillment:PopulateMail(req)
    if not req then return end
    if not SendMailFrame or not SendMailFrame:IsVisible() then
        if MailFrameTab_OnClick then
            MailFrameTab_OnClick(nil, 2) -- Switch to Send Mail tab
        end
    end

    -- Guard against accidentally mailing items/gold from a previously filled order to a different recipient
    local hasExistingAttachment = false
    local maxSlots = ATTACHMENTS_MAX_SEND or 12
    for i = 1, maxSlots do
        if (GetSendMailItemLink and GetSendMailItemLink(i)) or (GetSendMailItem and GetSendMailItem(i)) then
            hasExistingAttachment = true
            break
        end
    end
    local existingMoney = (GetSendMailMoney and GetSendMailMoney()) or 0
    if hasExistingAttachment or existingMoney > 0 then
        VM:Print("|cffffaa00Clear existing attachments or gold in Send Mail before filling another request.|r")
        return
    end

    if SendMailNameEditBox then
        local recipName = VM.Delivery and VM.Delivery:BeginMailRecipient(req.requester) or req.requester
        SendMailNameEditBox:SetText(recipName or "")
    end

    if req.isGoldRequest then
        local goldAmt = tonumber(req.goldAmount or req.quotedTotalPrice or req.quotedUnitPrice) or 0
        if SendMailSubjectEditBox then
            local subj = (req.reason and req.reason ~= "") and ("Guild Bank: " .. req.reason) or "Guild Bank: Gold Request"
            SendMailSubjectEditBox:SetText(subj)
        end
        if SendMailCODButton then SendMailCODButton:SetChecked(false) end
        if SendMailSendMoneyButton then SendMailSendMoneyButton:SetChecked(true) end
        if SendMailMoney and MoneyInputFrame_SetCopper and goldAmt > 0 then
            MoneyInputFrame_SetCopper(SendMailMoney, goldAmt)
        end
        return
    end

    if SendMailSubjectEditBox then
        SendMailSubjectEditBox:SetText(string.format("Guild Bank: %dx %s", req.count or 1, CleanItemDisplay(req.itemName or req.itemLink)))
    end

    local totalCOD = self:GetExpectedMemberPayment(req)
    if totalCOD > 0 then
        if SendMailSendMoneyButton then SendMailSendMoneyButton:SetChecked(false) end
        if SendMailCODButton then SendMailCODButton:SetChecked(true) end
        if SendMailMoney and MoneyInputFrame_SetCopper then
            MoneyInputFrame_SetCopper(SendMailMoney, totalCOD)
        end
    else
        if SendMailCODButton then SendMailCODButton:SetChecked(false) end
        if SendMailSendMoneyButton then SendMailSendMoneyButton:SetChecked(true) end
        if SendMailMoney and MoneyInputFrame_SetCopper then
            MoneyInputFrame_SetCopper(SendMailMoney, 0)
        end
    end

    local left = AttachItemsFromBags(req, function()
        -- Attach into the first empty Send Mail slot (calling without an index can overwrite slot 1)
        local maxSlots = ATTACHMENTS_MAX_SEND or 12
        for i = 1, maxSlots do
            local occupied = (GetSendMailItemLink and GetSendMailItemLink(i)) or (GetSendMailItem and GetSendMailItem(i))
            if not occupied then
                ClickSendMailItemButton(i)
                return true
            end
        end
        return false
    end)
    if left > 0 then
        VM:Print(string.format("|cffffaa00Attached available items, but %d more %s missing from bags.|r",
            left, req.itemLink or req.itemName or "Item"))
    end
end

--------------------------------------------------------------------------------
-- Delivery per member: all of this officer's prepared orders for one member in one Mail / one Trade
--------------------------------------------------------------------------------
local function StacksNeeded(req)
    if req.isGoldRequest then return 0 end
    local maxStack = VM:GetItemMaxStack(tonumber(req.itemID), req.itemLink) or 1
    return math.max(1, math.ceil((tonumber(req.count) or 1) / maxStack))
end

local function MailHasContent()
    local maxSlots = ATTACHMENTS_MAX_SEND or 12
    for i = 1, maxSlots do
        if (GetSendMailItemLink and GetSendMailItemLink(i)) or (GetSendMailItem and GetSendMailItem(i)) then
            return true
        end
    end
    return ((GetSendMailMoney and GetSendMailMoney()) or 0) > 0
end

local function AttachToMail()
    local maxSlots = ATTACHMENTS_MAX_SEND or 12
    for i = 1, maxSlots do
        local occupied = (GetSendMailItemLink and GetSendMailItemLink(i)) or (GetSendMailItem and GetSendMailItem(i))
        if not occupied then
            ClickSendMailItemButton(i)
            return true
        end
    end
    return false
end

-- Fills ONE mail with as many of the member's prepared item orders as fit (12 attachments) and the
-- combined CoD. Gold requests go in their own mail (Send Money cannot be combined with CoD).
function Fulfillment:PopulateMailFor(requester)
    local orders = self:GetMyPreparedOrders(requester)
    if #orders == 0 then return end
    if not SendMailFrame or not SendMailFrame:IsVisible() then
        if MailFrameTab_OnClick then MailFrameTab_OnClick(nil, 2) end
    end
    if MailHasContent() then
        VM:Print("|cffffaa00Clear existing attachments or gold in Send Mail before filling another request.|r")
        return
    end

    local items, gold = {}, nil
    local slotsLeft = ATTACHMENTS_MAX_SEND or 12
    for _, req in ipairs(orders) do
        if req.isGoldRequest then
            gold = gold or req
        else
            local need = StacksNeeded(req)
            if need <= slotsLeft then
                table.insert(items, req)
                slotsLeft = slotsLeft - need
            end
        end
    end
    if #items == 0 then
        if gold then self:PopulateMail(gold) end
        return
    end

    local recipName = VM.Delivery and VM.Delivery:BeginMailRecipient(items[1].requester) or items[1].requester
    if SendMailNameEditBox then SendMailNameEditBox:SetText(recipName or "") end
    if SendMailSubjectEditBox then
        local subj = (#items == 1)
            and string.format("Guild Bank: %dx %s", items[1].count or 1, CleanItemDisplay(items[1].itemName or items[1].itemLink))
            or string.format("Guild Bank: %d requests", #items)
        SendMailSubjectEditBox:SetText(subj)
    end

    local totalCOD = 0
    for _, req in ipairs(items) do totalCOD = totalCOD + self:GetExpectedMemberPayment(req) end
    if totalCOD > 0 then
        if SendMailSendMoneyButton then SendMailSendMoneyButton:SetChecked(false) end
        if SendMailCODButton then SendMailCODButton:SetChecked(true) end
    else
        if SendMailCODButton then SendMailCODButton:SetChecked(false) end
        if SendMailSendMoneyButton then SendMailSendMoneyButton:SetChecked(true) end
    end
    if SendMailMoney and MoneyInputFrame_SetCopper then MoneyInputFrame_SetCopper(SendMailMoney, totalCOD) end

    -- Attach one order at a time (stack splits need a moment to settle)
    local idx = 0
    local function Next()
        idx = idx + 1
        local req = items[idx]
        if not req then return end
        self.fulfillStarted[req.id] = true
        local left = AttachItemsFromBags(req, AttachToMail)
        if left > 0 then
            VM:Print(string.format("|cffffaa00Attached available items, but %d more %s missing from bags.|r",
                left, req.itemLink or req.itemName or "Item"))
        end
        if C_Timer and C_Timer.After then C_Timer.After(0.45, Next) else Next() end
    end
    Next()
    if #items < #orders - (gold and 1 or 0) then
        VM:Print("|cffffaa00More orders for this member are waiting — they will be filled into the next mail after you click Send.|r")
    end
    if VM.UI then VM.UI:RefreshRequests() end
end

-- Fills the Trade window with all of this officer's prepared orders for the trade partner (up to the
-- 6 item slots; gold requests are added as one gold amount) and whispers one combined summary.
function Fulfillment:PopulateTradeAll(targetName)
    local rawTarget = UnitName("NPC") or ""
    local tradeTarget = VM:NormalizeName(rawTarget)
    if tradeTarget == "" then return end
    local orders = self:GetMyPreparedOrders(tradeTarget)
    if #orders == 0 then
        if VM.Delivery then VM.Delivery:WhisperTradeSummary(rawTarget, tradeTarget, {}) end
        return
    end

    local goldTotal = 0
    local items = {}
    for _, req in ipairs(orders) do
        if req.isGoldRequest then
            goldTotal = goldTotal + (tonumber(req.goldAmount or req.quotedTotalPrice or req.quotedUnitPrice) or 0)
        else
            table.insert(items, req)
        end
        self.fulfillStarted[req.id] = true
    end
    if goldTotal > 0 and SetTradeMoney then
        local existing = (GetPlayerTradeMoney and GetPlayerTradeMoney()) or 0
        if existing == 0 then SetTradeMoney(goldTotal) end
    end

    local nextTradeSlot = 1
    local function AttachToTrade()
        while nextTradeSlot <= 6 do
            local existingName = GetTradePlayerItemInfo and GetTradePlayerItemInfo(nextTradeSlot)
            if not existingName then
                ClickTradeButton(nextTradeSlot)
                nextTradeSlot = nextTradeSlot + 1
                return true
            end
            nextTradeSlot = nextTradeSlot + 1
        end
        return false
    end

    local idx = 0
    local function Next()
        idx = idx + 1
        local req = items[idx]
        if not req then return end
        local left = AttachItemsFromBags(req, AttachToTrade)
        if left > 0 then
            VM:Print(string.format("|cffffaa00Trade window is full or %d %s missing — deliver the rest in the next trade.|r",
                left, req.itemLink or req.itemName or "Item"))
        end
        if C_Timer and C_Timer.After then C_Timer.After(0.45, Next) else Next() end
    end
    Next()

    for _, req in ipairs(orders) do whisperedInCurrentTrade[req.id] = true end
    if VM.Delivery then VM.Delivery:WhisperTradeSummary(rawTarget, tradeTarget, orders) end
    if VM.UI then VM.UI:RefreshRequests() end
end

-- Plain-text whisper sent to trade partner when officer clicks "Fill Trade"
function Fulfillment:SendTradeFulfillWhisper(req, rawTargetName)
    if not req or not rawTargetName or rawTargetName == "" then return end
    if whisperedInCurrentTrade[req.id] then return end
    if not SendChatMessage then return end

    local msg
    if req.isGoldRequest then
        local goldAmt = tonumber(req.goldAmount or req.quotedTotalPrice or req.quotedUnitPrice) or 0
        local reasonTxt = (req.reason and req.reason ~= "") and (" - " .. req.reason) or ""
        msg = string.format("Your Guild Bank gold request (%s%s) is being fulfilled in this trade.",
            VM:FormatMoneyPlain(goldAmt), reasonTxt)
    else
        local qty = tonumber(req.count) or 1
        local itemLabel = CleanItemDisplay(req.itemName or req.itemLink)
        local due = self:GetExpectedMemberPayment(req)
        if due > 0 then
            msg = string.format("Your Guild Bank request (%dx %s) is being fulfilled. Please enter %s in the trade window.",
                qty, itemLabel, VM:FormatMoneyPlain(due))
        else
            msg = string.format("Your Guild Bank request (%dx %s) is being fulfilled (no payment required).",
                qty, itemLabel)
        end
    end

    local ok = pcall(SendChatMessage, msg, "WHISPER", nil, rawTargetName)
    if ok then
        whisperedInCurrentTrade[req.id] = true
    end
end

-- Finds items in player's bags (or fills gold for gold requests) in Trade window & whispers partner
function Fulfillment:PopulateTrade(req)
    if not req then return end
    local rawTarget = UnitName("NPC") or ""
    local tradeTarget = VM:NormalizeName(rawTarget)
    if tradeTarget == "" or not IsSameRecipient(req.requester, tradeTarget) then
        VM:Print(string.format("|cffffaa00Trading with %s, but order is for %s.|r",
            tradeTarget ~= "" and tradeTarget or "nobody", req.requester or "?"))
        return
    end

    if req.isGoldRequest then
        local existingTradeMoney = (GetPlayerTradeMoney and GetPlayerTradeMoney()) or 0
        if existingTradeMoney > 0 then
            VM:Print("|cffffaa00Gold is already entered in the Trade window. Complete one gold request per trade.|r")
            return
        end
        local goldAmt = tonumber(req.goldAmount or req.quotedTotalPrice or req.quotedUnitPrice) or 0
        if goldAmt > 0 and SetTradeMoney then
            SetTradeMoney(goldAmt)
        end
        self:SendTradeFulfillWhisper(req, rawTarget)
        return
    end

    local nextTradeSlot = 1
    local function FindNextEmptyTradeSlot()
        while nextTradeSlot <= 6 do
            local existingName = GetTradePlayerItemInfo and GetTradePlayerItemInfo(nextTradeSlot)
            if not existingName then
                return nextTradeSlot
            end
            nextTradeSlot = nextTradeSlot + 1
        end
        return nil
    end

    local left = AttachItemsFromBags(req, function()
        local slot = FindNextEmptyTradeSlot()
        if not slot then return false end
        ClickTradeButton(slot)
        nextTradeSlot = slot + 1
        return true
    end)

    if left > 0 then
        VM:Print(string.format("|cffffaa00Placed available items in trade, but %d more %s missing from bags.|r",
            left, req.itemLink or req.itemName or "Item"))
    end

    self:SendTradeFulfillWhisper(req, rawTarget)
end
