local _, VM = ...
VM.Fulfillment = {}
local Fulfillment = VM.Fulfillment

Fulfillment.activeOrder = nil -- Order currently being fulfilled by officer

local currentTradeTargetMoney = 0
local currentTradeTargetName = ""

function Fulfillment:Init()
    local f = CreateFrame("Frame")
    f:RegisterEvent("MAIL_SHOW")
    f:RegisterEvent("MAIL_SEND_SUCCESS")
    f:RegisterEvent("TRADE_SHOW")
    f:RegisterEvent("TRADE_MONEY_CHANGED")
    f:RegisterEvent("TRADE_ACCEPT_UPDATE")
    f:RegisterEvent("TRADE_CLOSED")

    f:SetScript("OnEvent", function(_, event, arg1, arg2)
        if event == "MAIL_SHOW" then
            if self.activeOrder then
                C_Timer.After(0.2, function() self:PopulateMail(self.activeOrder) end)
            end
        elseif event == "MAIL_SEND_SUCCESS" then
            if self.activeOrder then
                self:CompleteRequest(self.activeOrder.id)
                print("|cff00ccff[Vault Manager]|r Mail sent - order marked as fulfilled!")
                self.activeOrder = nil
            end
        elseif event == "TRADE_SHOW" then
            currentTradeTargetMoney = 0
            currentTradeTargetName = VM:NormalizeName(UnitName("NPC") or "")
            if self.activeOrder then
                C_Timer.After(0.2, function() self:PopulateTrade(self.activeOrder) end)
            end
        elseif event == "TRADE_MONEY_CHANGED" then
            currentTradeTargetMoney = GetTargetTradeMoney and GetTargetTradeMoney() or 0
        elseif event == "TRADE_ACCEPT_UPDATE" then
            -- arg1 == 1 (player accepted), arg2 == 1 (target accepted)
            if arg1 == 1 and arg2 == 1 then
                if currentTradeTargetMoney > 0 and currentTradeTargetName ~= "" then
                    VM.pendingTradePayments = VM.pendingTradePayments or {}
                    local payerMain = VM:GetMainFor(currentTradeTargetName)
                    table.insert(VM.pendingTradePayments, {
                        amount = currentTradeTargetMoney,
                        payer = payerMain,
                        rawPayer = currentTradeTargetName,
                        timestamp = time()
                    })
                    VM:LogDebug(string.format("Recorded pending trade payment: %s from %s", VM:FormatMoney(currentTradeTargetMoney), payerMain))
                end
                if self.activeOrder then
                    self:CompleteRequest(self.activeOrder.id)
                    print("|cff00ccff[Vault Manager]|r Trade completed - order marked as fulfilled!")
                    self.activeOrder = nil
                end
            end
        elseif event == "TRADE_CLOSED" then
            currentTradeTargetMoney = 0
            currentTradeTargetName = ""
        end
    end)
end

-- Create new request (Member)
function Fulfillment:CreateRequest(tabIndex, itemKey, count)
    local rule = VM:GetTabRule(tabIndex)
    if rule.mode == "LOCKED" then
        print("|cffff4444[Vault Manager]|r This bank tab is locked and cannot be ordered from.")
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

    local available = itemData.count - VM:GetReservedCount(itemKey, tabIndex)
    if count <= 0 or count > available then
        print("|cffff4444[Vault Manager]|r Not enough available items (Available: " .. available .. ").")
        return
    end

    local ahPrice = (itemData.itemID ~= 0 and VM:GetItemAHPrice(itemData.itemID)) or 0
    local quotedUnit = 0
    if rule.mode == "PERCENT" and ahPrice > 0 then
        quotedUnit = math.floor(ahPrice * ((rule.percent or 50) / 100))
    end

    local reqID = string.format("REQ_%s_%d_%d", VM:GetPlayerName(), time(), math.random(1000, 9999))
    local req = {
        id = reqID,
        requester = VM:GetPlayerName(),
        itemID = itemData.itemID ~= 0 and itemData.itemID or itemData.name,
        itemLink = itemData.link,
        itemName = itemData.name,
        count = count,
        tab = tabIndex,
        status = "PENDING",
        createdAt = time(),
        updatedAt = time(),
        approvedBy = "",
        fulfilledBy = "",
        quotedUnitPrice = quotedUnit,
        priceMode = rule.mode,
        pricePercent = rule.percent or 0
    }

    VM.db.requests[reqID] = req
    VM.Comms:BroadcastRequest(req)
    print(string.format("|cff00ccff[Vault Manager]|r Request sent: %dx %s", count, itemData.link))
    if VM.UI then VM.UI:RefreshAll() end
end

-- Approve request (Officer) -> Activates soft-lock
function Fulfillment:ApproveRequest(reqID)
    if not VM:IsOfficer() then return end
    local req = VM.db.requests[reqID]
    if not req or req.status ~= "PENDING" then return end

    req.status = "APPROVED"
    req.approvedBy = VM:GetPlayerName()
    req.updatedAt = time()

    VM.Comms:BroadcastRequest(req)
    if VM.UI then VM.UI:RefreshAll() end
end

-- Reject request (Officer)
function Fulfillment:RejectRequest(reqID)
    if not VM:IsOfficer() then return end
    local req = VM.db.requests[reqID]
    if not req or (req.status ~= "PENDING" and req.status ~= "APPROVED") then return end

    req.status = "REJECTED"
    req.approvedBy = VM:GetPlayerName()
    req.updatedAt = time()

    VM.Comms:BroadcastRequest(req)
    if VM.UI then VM.UI:RefreshAll() end
end

-- Mark order as fulfilled -> Record in ledger & release soft-lock
function Fulfillment:CompleteRequest(reqID)
    if not VM:IsOfficer() then return end
    local req = VM.db.requests[reqID]
    if not req or req.status ~= "APPROVED" then return end

    req.status = "FULFILLED"
    req.fulfilledBy = VM:GetPlayerName()
    req.updatedAt = time()

    VM.Ledger:RecordFulfillment(req, VM:GetPlayerName())
    VM.Comms:BroadcastRequest(req)
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

-- Finds items in player's bags and places them in Send Mail
function Fulfillment:PopulateMail(req)
    if not SendMailFrame or not SendMailFrame:IsVisible() then
        MailFrameTab_OnClick(nil, 2) -- Switch to Send Mail tab
    end
    SendMailNameEditBox:SetText(req.requester)
    SendMailSubjectEditBox:SetText(string.format("Guild Bank: %dx %s", req.count, req.itemName))

    if req.quotedUnitPrice and req.quotedUnitPrice > 0 then
        local totalCOD = req.quotedUnitPrice * req.count
        SendMailSendMoneyButton:SetChecked(false)
        SendMailCODButton:SetChecked(true)
        MoneyInputFrame_SetCopper(SendMailMoney, totalCOD)
    end

    local remaining = req.count
    for bag = 0, 4 do
        local slots = C_Container and C_Container.GetContainerNumSlots(bag) or GetContainerNumSlots(bag)
        for slot = 1, slots do
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
                if id == req.itemID or name == req.itemName or req.itemID == req.itemName and remaining > 0 then
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

-- Finds items in player's bags and places them in Trade window
function Fulfillment:PopulateTrade(req)
    local tradeTarget = VM:NormalizeName(UnitName("NPC") or "")
    if tradeTarget ~= req.requester then
        print(string.format("|cffffaa00[Vault Manager]|r Trading with %s, but order is for %s.", tradeTarget, req.requester))
        return
    end

    local remaining = req.count
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
                if id == req.itemID or name == req.itemName or req.itemID == req.itemName then
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
