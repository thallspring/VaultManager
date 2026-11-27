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

local function CaptureMailSnapshot(target)
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
            if refTs > 0 and refTs < cutoff then
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
function Fulfillment:FindMatchingApprovedRequest(recipientName, itemID, itemName, count, goldCopper)
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

    local preparedMatch = SearchByStatus("PREPARED", true)
    if preparedMatch then return preparedMatch end
    return SearchByStatus("APPROVED", false)
end

function Fulfillment:CompleteFromTransfer(recipient, itemsByKey, moneySent, method)
    if not VM:IsOfficer() or not recipient or recipient == "" then return 0 end
    local completedCount = 0

    if moneySent and moneySent > 0 then
        local goldReq = self:FindMatchingDeliverableRequest(recipient, nil, nil, nil, moneySent)
        if goldReq then
            self:CompleteRequest(goldReq.id, {
                completedBy = VM:GetPlayerName(),
                method = method
            })
            completedCount = completedCount + 1
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
            end
        end
    end

    return completedCount
end

function Fulfillment:Init()
    self:PruneOldRequests()

    if not sendMailHooked and hooksecurefunc and type(SendMail) == "function" then
        sendMailHooked = true
        hooksecurefunc("SendMail", function(target)
            CaptureMailSnapshot(target)
        end)
    end

    -- Delayed relog reminder if this officer still has unfulfilled PREPARED requests
    if C_Timer and C_Timer.After then
        C_Timer.After(5, function()
            if not VM.isUnguilded and VM:IsOfficer() then
                local mine = self:GetMyPreparedOrders()
                if #mine > 0 and VM.UI and VM.UI.ShowRelogPreparedReminder then
                    VM.UI:ShowRelogPreparedReminder(mine)
                end
            end
        end)
    end

    local f = CreateFrame("Frame")
    f:RegisterEvent("GUILDBANKFRAME_CLOSED")
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
        if event == "GUILDBANKFRAME_CLOSED" then
            self.isWithdrawing = false
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
        elseif event == "MAIL_SEND_SUCCESS" then
            local snap = pendingMailSnapshot
            pendingMailSnapshot = nil
            if snap and (time() - (snap.timestamp or 0)) <= 30 then
                local done = self:CompleteFromTransfer(snap.recipient, snap.items, snap.money, "MAIL")
                if done > 0 then
                    VM:Print(string.format("Mail sent — auto-completed %d request(s).", done))
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
                if #matches > 0 and VM.UI and VM.UI.ShowTradeFulfillmentPrompt then
                    VM.UI:ShowTradeFulfillmentPrompt(currentTradeTargetName, matches)
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

                if snap.targetMoney and snap.targetMoney > 0 and snap.recipient ~= "" then
                    VM.pendingTradePayments = VM.pendingTradePayments or {}
                    local payerMain = VM:GetMainFor(snap.recipient)
                    table.insert(VM.pendingTradePayments, {
                        amount = snap.targetMoney,
                        payer = payerMain,
                        rawPayer = snap.recipient,
                        timestamp = time()
                    })
                    VM:LogDebug(string.format("Recorded pending trade payment: %s from %s", VM:FormatMoney(snap.targetMoney), payerMain))
                end

                local done = self:CompleteFromTransfer(snap.recipient, snap.items, snap.playerMoney, "TRADE")
                if done > 0 then
                    VM:Print(string.format("Trade completed — auto-completed %d request(s).", done))
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
        reason = ""
    }

    VM.db.requests[reqID] = req
    VM.Comms:BroadcastRequest(req)
    if VM.Minimap and VM.Minimap.UpdateBadge then VM.Minimap:UpdateBadge() end
    VM:Print(string.format("Request sent: %dx %s", qty, itemData.link or itemData.name))
    if VM.UI then VM.UI:RefreshAll() end
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

    VM.Comms:BroadcastRequest(req)
    if VM.Minimap and VM.Minimap.UpdateBadge then VM.Minimap:UpdateBadge() end
    if VM.UI then VM.UI:RefreshAll() end
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
end

-- Executes Guild Bank item withdrawal steps into reserved empty bag slots
function Fulfillment:ExecuteBankWithdrawSteps(req, tab, steps)
    local function RunStep(idx)
        local step = steps[idx]
        if not step then
            self.isWithdrawing = false
            self:FinalizePreparedState(req, true)
            if VM.BankScanner and VM.BankScanner.SchedulePostWithdrawScan then
                VM.BankScanner:SchedulePostWithdrawScan()
            end
            return
        end

        if not IsBankCurrentlyOpen() then
            self.isWithdrawing = false
            VM:Print("|cffff4444Guild Bank closed before withdrawal finished.|r")
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
        PickupBagSlot(step.destBag, step.destSlot)
        ClearCursor()

        if idx < #steps then
            if C_Timer and C_Timer.After then
                C_Timer.After(0.28, function() RunStep(idx + 1) end)
            else
                RunStep(idx + 1)
            end
        else
            self.isWithdrawing = false
            self:FinalizePreparedState(req, true)
            if VM.BankScanner and VM.BankScanner.SchedulePostWithdrawScan then
                VM.BankScanner:SchedulePostWithdrawScan()
            end
        end
    end

    RunStep(1)
end

-- Prepare request: requires open Guild Bank (event-based check so Bagnon/ElvUI/custom frames work)
function Fulfillment:PrepareRequest(reqID)
    if not VM:IsOfficer() then return end
    local req = VM.db.requests[reqID]
    if not req or req.status ~= "APPROVED" then return end

    if self.isWithdrawing then
        VM:Print("|cffffaa00Already withdrawing a request from the Guild Bank. Please wait a moment.|r")
        return
    end

    if not IsBankCurrentlyOpen() then
        VM:Print("|cffff4444Open the Guild Bank to prepare and withdraw this request.|r")
        return
    end

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

        self.isWithdrawing = true
        if WithdrawGuildBankMoney then
            WithdrawGuildBankMoney(goldAmt)
        end
        self.isWithdrawing = false
        self:FinalizePreparedState(req, true)
        if VM.BankScanner and VM.BankScanner.SchedulePostWithdrawScan then
            VM.BankScanner:SchedulePostWithdrawScan()
        end
        return
    end

    -- Item Request
    local needed = tonumber(req.count) or 1
    local targetTab = tonumber(req.tab) or 1
    self.isWithdrawing = true

    local function ScanAndWithdrawFromTab(attempt)
        if not IsBankCurrentlyOpen() then
            self.isWithdrawing = false
            return
        end

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
            if attempt < 2 and C_Timer and C_Timer.After then
                if SetCurrentGuildBankTab then SetCurrentGuildBankTab(targetTab) end
                if QueryGuildBankTab then QueryGuildBankTab(targetTab) end
                C_Timer.After(0.45, function() ScanAndWithdrawFromTab(attempt + 1) end)
                return
            end
            self.isWithdrawing = false
            VM:Print(string.format("|cffff4444Only %d of %d %s found in Tab %d. Try again after the tab loads.|r",
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

        for _, s in ipairs(matchingSlots) do
            if remaining <= 0 then break end
            if not empties[emptyIdx] then
                self.isWithdrawing = false
                VM:Print(string.format("|cffff4444Not enough free general bag slots to withdraw %dx %s.|r",
                    needed, req.itemLink or req.itemName or "Item"))
                return
            end
            local take = math.min(s.count, remaining)
            table.insert(steps, {
                gbSlot = s.slot,
                takeCount = take,
                isFullStack = (take == s.count),
                destBag = empties[emptyIdx].bag,
                destSlot = empties[emptyIdx].slot,
            })
            remaining = remaining - take
            emptyIdx = emptyIdx + 1
        end

        self:ExecuteBankWithdrawSteps(req, targetTab, steps)
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

    if self.activeOrder and self.activeOrder.id == req.id then
        self.activeOrder = nil
    end

    VM.Comms:BroadcastRequest(req)
    if VM.Minimap and VM.Minimap.UpdateBadge then VM.Minimap:UpdateBadge() end
    if VM.UI then VM.UI:RefreshAll() end
    VM:Print("Request returned to APPROVED status.")
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
    end

    if self.activeOrder and self.activeOrder.id == req.id then
        self.activeOrder = nil
    end

    VM.Comms:BroadcastRequest(req)
    if VM.Minimap and VM.Minimap.UpdateBadge then VM.Minimap:UpdateBadge() end
    if VM.UI then VM.UI:RefreshAll() end
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
function Fulfillment:OnGuildBankOpened()
    if not IsBankCurrentlyOpen() then return end
    local prefs = VM.db and VM.db.uiPrefs
    if prefs and prefs.autoOpenAtBank == false then return end

    if VM:IsOfficer() then
        local pendingCount, approvedCount = self:GetPendingAndApprovedCounts()
        local myPrepared = self:GetMyPreparedOrders()
        if (pendingCount > 0 or approvedCount > 0 or #myPrepared > 0) and VM.UI and VM.UI.OpenToRequestsTab then
            VM.UI:OpenToRequestsTab()
            return
        end
    end

    if VM.UI and VM.UI.OpenToVaultTab then
        VM.UI:OpenToVaultTab()
    elseif VM.UI and VM.UI.OpenToRequestsTab then
        VM.UI:OpenToRequestsTab()
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
        SendMailNameEditBox:SetText(req.requester or "")
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
        ClickSendMailItemButton()
        return true
    end)
    if left > 0 then
        VM:Print(string.format("|cffffaa00Attached available items, but %d more %s missing from bags.|r",
            left, req.itemLink or req.itemName or "Item"))
    end
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
