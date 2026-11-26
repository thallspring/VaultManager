local _, VM = ...
VM.Fulfillment = {}
local Fulfillment = VM.Fulfillment

Fulfillment.activeOrder = nil -- Order currently being prepared by officer

local currentTradeTargetMoney = 0
local currentTradeTargetName = ""
local pendingMailSnapshot = nil
local lastAcceptedTrade = nil
local sendMailHooked = false

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

local function DoesBagItemMatchRequest(bagItemID, bagItemName, req)
    if not req or req.isGoldRequest then return false end
    local reqID = tonumber(req.itemID) or 0
    local bID = tonumber(bagItemID) or 0
    if reqID > 0 and bID > 0 then
        return bID == reqID
    end
    local reqName = CleanItemName(req.itemName or req.itemLink)
    local bagName = CleanItemName(bagItemName)
    return reqName ~= "" and bagName ~= "" and reqName == bagName
end

local function IsSameRecipient(reqRequester, targetName)
    local rNorm = VM:NormalizeName(reqRequester)
    local tNorm = VM:NormalizeName(targetName)
    if rNorm == "" or tNorm == "" then return false end
    if rNorm:lower() == tNorm:lower() then return true end
    local rMain = VM:GetMainFor(rNorm)
    local tMain = VM:GetMainFor(tNorm)
    if rMain ~= "" and tMain ~= "" and rMain:lower() == tMain:lower() then
        return true
    end
    return false
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
        if req and (req.status == "FULFILLED" or req.status == "REJECTED") then
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

function Fulfillment:CompleteFromTransfer(recipient, itemsByKey, moneySent, method)
    if not VM:IsOfficer() or not recipient or recipient == "" then return 0 end
    local completedCount = 0

    if moneySent and moneySent > 0 then
        local goldReq = self:FindMatchingApprovedRequest(recipient, nil, nil, nil, moneySent)
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
                local matchedReq = self:FindMatchingApprovedRequest(recipient, entry.itemID, entry.itemName, remainingQty, 0)
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

    local f = CreateFrame("Frame")
    f:RegisterEvent("MAIL_SHOW")
    f:RegisterEvent("MAIL_SEND_SUCCESS")
    f:RegisterEvent("MAIL_FAILED")
    f:RegisterEvent("TRADE_SHOW")
    f:RegisterEvent("TRADE_MONEY_CHANGED")
    f:RegisterEvent("TRADE_ACCEPT_UPDATE")
    f:RegisterEvent("TRADE_CLOSED")
    f:RegisterEvent("UI_INFO_MESSAGE")

    f:SetScript("OnEvent", function(_, event, arg1, arg2)
        if event == "MAIL_SHOW" then
            pendingMailSnapshot = nil
            if self.activeOrder then
                if C_Timer and C_Timer.After then
                    C_Timer.After(0.2, function()
                        if self.activeOrder then self:PopulateMail(self.activeOrder) end
                    end)
                else
                    self:PopulateMail(self.activeOrder)
                end
            end
        elseif event == "MAIL_FAILED" then
            pendingMailSnapshot = nil
        elseif event == "MAIL_SEND_SUCCESS" then
            local snap = pendingMailSnapshot
            pendingMailSnapshot = nil
            if snap and (time() - (snap.timestamp or 0)) <= 30 then
                local done = self:CompleteFromTransfer(snap.recipient, snap.items, snap.money, "MAIL")
                if done > 0 then
                    VM:Print(string.format("Mail sent — auto-completed %d approved request(s).", done))
                end
            end
        elseif event == "TRADE_SHOW" then
            currentTradeTargetMoney = 0
            currentTradeTargetName = VM:NormalizeName(UnitName("NPC") or "")
            lastAcceptedTrade = nil
            if self.activeOrder then
                if C_Timer and C_Timer.After then
                    C_Timer.After(0.2, function()
                        if self.activeOrder then self:PopulateTrade(self.activeOrder) end
                    end)
                else
                    self:PopulateTrade(self.activeOrder)
                end
            end
        elseif event == "TRADE_MONEY_CHANGED" then
            currentTradeTargetMoney = (GetTargetTradeMoney and GetTargetTradeMoney()) or 0
        elseif event == "TRADE_ACCEPT_UPDATE" then
            -- arg1 == 1 (player accepted), arg2 == 1 (target accepted)
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
                    VM:Print(string.format("Trade completed — auto-completed %d approved request(s).", done))
                end
            end
        elseif event == "TRADE_CLOSED" then
            currentTradeTargetMoney = 0
            currentTradeTargetName = ""
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
function Fulfillment:CreateGoldRequest(copperAmount, reason)
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

    local now = time()
    local reqID = string.format("REQ_GOLD_%s_%d_%d", VM:GetPlayerName(), now, math.random(1000, 9999))
    local req = {
        id = reqID,
        requester = VM:GetPlayerName(),
        isGoldRequest = true,
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

-- Reject / cancel request (Officer)
function Fulfillment:RejectRequest(reqID)
    if not VM:IsOfficer() then return end
    local req = VM.db.requests[reqID]
    if not req or (req.status ~= "PENDING" and req.status ~= "APPROVED") then return end

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
    if not req or req.status ~= "APPROVED" then return end

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

-- Shows popup when an officer opens the Guild Bank and there are approved orders
function Fulfillment:OnGuildBankOpened()
    local approved = self:GetApprovedOrders()
    if #approved > 0 and VM.UI then
        VM.UI:ShowOfficerBankPopup(approved)
    end
    if VM.UI and VM.UI.CheckPendingFulfillmentReturns then
        VM.UI:CheckPendingFulfillmentReturns()
    end
end

-- Finds items in player's bags (or sets Send Money for gold requests) in Send Mail
function Fulfillment:PopulateMail(req)
    if not req then return end
    if not SendMailFrame or not SendMailFrame:IsVisible() then
        if MailFrameTab_OnClick then
            MailFrameTab_OnClick(nil, 2) -- Switch to Send Mail tab
        end
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
        SendMailSubjectEditBox:SetText(string.format("Guild Bank: %dx %s", req.count or 1, req.itemName or "Item"))
    end

    local totalCOD = 0
    if req.priceMode == "FREE" then
        totalCOD = 0
    elseif req.quotedTotalPrice and req.quotedTotalPrice > 0 then
        totalCOD = req.quotedTotalPrice
    elseif req.priceMode == "PERCENT" then
        local liveUnit = VM:GetEffectiveLivePrice(req.itemID, req.itemLink, req.priceAtRequest or req.quotedUnitPrice)
        totalCOD = VM:CalculateMemberTotalPrice(liveUnit, req.count or 1, { mode = "PERCENT", percent = req.pricePercent or 50 })
    elseif req.quotedUnitPrice and req.quotedUnitPrice > 0 then
        totalCOD = req.quotedUnitPrice * (req.count or 1)
    end

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

    local remaining = tonumber(req.count) or 1
    for bag = 0, 4 do
        if remaining <= 0 then return end
        local slots = C_Container and C_Container.GetContainerNumSlots(bag) or GetContainerNumSlots(bag)
        for slot = 1, slots do
            if remaining <= 0 then return end
            local link, count
            if C_Container and C_Container.GetContainerItemInfo then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info then link = info.hyperlink; count = info.stackCount end
            else
                _, count, _, _, _, _, link = GetContainerItemInfo(bag, slot)
            end

            if link then
                local id = tonumber(link:match("item:(%d+)"))
                local name = link:match("%[(.-)%]") or link
                if DoesBagItemMatchRequest(id, name, req) and remaining > 0 then
                    if C_Container and C_Container.PickupContainerItem then
                        C_Container.PickupContainerItem(bag, slot)
                    else
                        PickupContainerItem(bag, slot)
                    end
                    ClickSendMailItemButton()
                    remaining = remaining - (count or 1)
                end
            end
        end
    end
end

-- Finds items in player's bags (or fills gold for gold requests) in Trade window
function Fulfillment:PopulateTrade(req)
    if not req then return end
    local tradeTarget = VM:NormalizeName(UnitName("NPC") or "")
    if not IsSameRecipient(req.requester, tradeTarget) then
        print(string.format("|cffffaa00[Vault Manager]|r Trading with %s, but order is for %s.", tradeTarget, req.requester))
        return
    end

    if req.isGoldRequest then
        local goldAmt = tonumber(req.goldAmount or req.quotedTotalPrice or req.quotedUnitPrice) or 0
        if goldAmt > 0 and SetTradeMoney then
            SetTradeMoney(goldAmt)
        end
        return
    end

    local remaining = tonumber(req.count) or 1
    local tradeSlot = 1
    for bag = 0, 4 do
        local slots = C_Container and C_Container.GetContainerNumSlots(bag) or GetContainerNumSlots(bag)
        for slot = 1, slots do
            if tradeSlot > 6 or remaining <= 0 then return end
            local link, count
            if C_Container and C_Container.GetContainerItemInfo then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info then link = info.hyperlink; count = info.stackCount end
            else
                _, count, _, _, _, _, link = GetContainerItemInfo(bag, slot)
            end

            if link then
                local id = tonumber(link:match("item:(%d+)"))
                local name = link:match("%[(.-)%]") or link
                if DoesBagItemMatchRequest(id, name, req) and remaining > 0 then
                    if C_Container and C_Container.PickupContainerItem then
                        C_Container.PickupContainerItem(bag, slot)
                    else
                        PickupContainerItem(bag, slot)
                    end
                    ClickTradeButton(tradeSlot)
                    tradeSlot = tradeSlot + 1
                    remaining = remaining - (count or 1)
                end
            end
        end
    end
end
