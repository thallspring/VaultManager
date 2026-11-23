local _, VM = ...
VM.Ledger = {}
local Ledger = VM.Ledger

local function GenerateTxID(prefix)
    return string.format("%s_%d_%d", prefix, time(), math.random(10000, 99999))
end

function Ledger:RecordFulfillment(req, officerName)
    local ahPrice = VM:GetItemAHPrice(req.itemID) or 0
    local unitCharged = 0
    if req.priceMode == "PERCENT" and ahPrice > 0 then
        unitCharged = math.floor(ahPrice * ((req.pricePercent or 50) / 100))
    end

    local now = time()
    local tx = {
        id = GenerateTxID("OUT"),
        type = "OUT",
        player = VM:NormalizeName(req.requester),
        itemID = req.itemID,
        itemLink = req.itemLink,
        itemName = req.itemName,
        count = req.count,
        unitPriceAtTime = ahPrice,
        chargedUnitPrice = unitCharged,
        timestamp = now,
        updatedAt = now,
        officer = VM:NormalizeName(officerName),
        source = "REQUEST",
        deleted = false
    }

    VM.db.ledger[tx.id] = tx
    VM.Comms:BroadcastTransaction(tx)
    return tx
end

function Ledger:RecordDeposit(playerName, itemID, itemLink, count, source)
    local ahPrice = VM:GetItemAHPrice(itemID) or 0
    local cleanLink = itemLink or "item:0"
    local itemName = "Item " .. tostring(itemID or 0)
    if cleanLink:find("%[") then
        local m = cleanLink:match("%[(.-)%]")
        if m then itemName = m end
    elseif cleanLink ~= "" and cleanLink ~= "Unknown" then
        itemName = cleanLink:gsub("^%[", ""):gsub("%]$", "")
    end

    local now = time()
    local tx = {
        id = GenerateTxID("IN"),
        type = "IN",
        player = (playerName == "UNATTRIBUTED") and "UNATTRIBUTED" or VM:NormalizeName(playerName),
        itemID = itemID or 0,
        itemLink = cleanLink,
        itemName = itemName,
        count = count or 1,
        unitPriceAtTime = ahPrice,
        chargedUnitPrice = 0,
        timestamp = now,
        updatedAt = now,
        officer = VM:GetPlayerName(),
        source = source or "BANK_LOG",
        deleted = false
    }

    VM.db.ledger[tx.id] = tx
    VM.Comms:BroadcastTransaction(tx)
    return tx
end

function Ledger:RecordGoldDeposit(playerName, copperAmount, source)
    local now = time()
    local tx = {
        id = GenerateTxID("GOLD_IN"),
        type = "IN",
        player = (playerName == "UNATTRIBUTED") and "UNATTRIBUTED" or VM:NormalizeName(playerName),
        itemID = 0,
        itemLink = "GOLD",
        itemName = "Gold Deposit",
        count = 1,
        unitPriceAtTime = copperAmount or 0,
        chargedUnitPrice = 0,
        timestamp = now,
        updatedAt = now,
        officer = VM:GetPlayerName(),
        source = source or "BANK_MONEY_LOG",
        deleted = false
    }

    VM.db.ledger[tx.id] = tx
    VM.Comms:BroadcastTransaction(tx)
    return tx
end

function Ledger:AssignUnattributed(txID, memberName)
    local tx = VM.db.ledger[txID]
    if not tx then return end
    tx.player = VM:NormalizeName(memberName)
    tx.updatedAt = time()
    VM.Comms:BroadcastTransaction(tx)
    if VM.UI then VM.UI:RefreshAll() end
end

function Ledger:DeleteTransaction(txID)
    if not VM:IsOfficer() then return end
    local tx = VM.db.ledger[txID]
    if not tx then return end
    tx.deleted = true
    tx.updatedAt = time()
    VM.Comms:BroadcastTransaction(tx)
    if VM.UI then VM.UI:RefreshAll() end
end

function Ledger:GetTransactionValue(tx, useHistorical)
    if tx.itemID == 0 or tx.itemLink == "GOLD" then
        return (tx.unitPriceAtTime or 0) * (tx.count or 1)
    end

    local unitVal = 0
    if useHistorical then
        unitVal = tx.unitPriceAtTime or 0
    else
        unitVal = VM:GetItemAHPrice(tx.itemID) or tx.unitPriceAtTime or 0
    end
    return unitVal * (tx.count or 0)
end

function Ledger:GetAggregatedByMain(useHistorical)
    local groups = {}

    for _, tx in pairs(VM.db.ledger) do
        if not tx.deleted then
            local key = (tx.player == "UNATTRIBUTED") and "UNATTRIBUTED" or VM:GetMainFor(tx.player)
            if not groups[key] then
                groups[key] = {
                    mainName = key,
                    isLegacy = VM:IsLegacyMember(key),
                    totalOutValue = 0,
                    totalInValue = 0,
                    totalGoldIn = 0,
                    totalItemsIn = 0,
                    totalCharged = 0,
                    transactions = {}
                }
            end

            local val = self:GetTransactionValue(tx, useHistorical)
            if tx.type == "OUT" then
                groups[key].totalOutValue = groups[key].totalOutValue + val
                groups[key].totalCharged = groups[key].totalCharged + ((tx.chargedUnitPrice or 0) * (tx.count or 0))
            else
                groups[key].totalInValue = groups[key].totalInValue + val
                if tx.itemID == 0 or tx.itemLink == "GOLD" then
                    groups[key].totalGoldIn = groups[key].totalGoldIn + val
                else
                    groups[key].totalItemsIn = groups[key].totalItemsIn + val
                end
            end

            table.insert(groups[key].transactions, tx)
        end
    end

    local sorted = {}
    for _, grp in pairs(groups) do
        table.sort(grp.transactions, function(a, b) return (a.timestamp or 0) > (b.timestamp or 0) end)
        table.insert(sorted, grp)
    end

    table.sort(sorted, function(a, b)
        if a.mainName == "UNATTRIBUTED" then return true end
        if b.mainName == "UNATTRIBUTED" then return false end
        if a.isLegacy ~= b.isLegacy then
            return not a.isLegacy
        end
        if a.totalOutValue ~= b.totalOutValue then
            return a.totalOutValue > b.totalOutValue
        end
        return a.mainName < b.mainName
    end)

    return sorted
end

-- Donation leaderboard (sortMode: "TOTAL" | "GOLD" | "ITEMS")
function Ledger:GetDonationRanking(sortMode, useHistorical)
    local allGroups = self:GetAggregatedByMain(useHistorical)
    local ranked = {}

    for _, grp in ipairs(allGroups) do
        if grp.mainName ~= "UNATTRIBUTED" and grp.totalInValue > 0 then
            local metric = grp.totalInValue
            if sortMode == "GOLD" then
                metric = grp.totalGoldIn
            elseif sortMode == "ITEMS" then
                metric = grp.totalItemsIn
            end

            if metric > 0 then
                table.insert(ranked, grp)
            end
        end
    end

    table.sort(ranked, function(a, b)
        if a.isLegacy ~= b.isLegacy then
            return not a.isLegacy
        end
        local valA = (sortMode == "GOLD" and a.totalGoldIn) or (sortMode == "ITEMS" and a.totalItemsIn) or a.totalInValue
        local valB = (sortMode == "GOLD" and b.totalGoldIn) or (sortMode == "ITEMS" and b.totalItemsIn) or b.totalInValue
        if valA ~= valB then
            return valA > valB
        end
        return a.mainName < b.mainName
    end)

    return ranked
end
