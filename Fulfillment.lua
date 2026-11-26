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
    s = s:gsub("^%[", ""):gsub("%]\$", "")
    return (s:match("^%s*(.-)%s*\$") or s):lower()
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
                    local reqGold = tonumber
