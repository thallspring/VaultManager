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
        isManual = false,
        deleted = false
    }

    VM.db.ledger[tx.id] = tx
    VM.Comms:BroadcastTransaction(tx)
    return tx
end

function Ledger:RecordDeposit(playerName, itemID, itemLink, count, source)
    local ahPrice = VM:GetItemAHPrice(itemID, itemLink) or 0
    local cleanLink = itemLink or "item:0"
    local itemName = "Item " .. tostring(itemID or 0)
    if cleanLink:find("%[") then
        local m = cleanLink:match("%[(.-)%]")
        if m then itemName = m end
    elseif cleanLink ~= "" and cleanLink ~= "Unknown" then
        itemName = cleanLink:gsub("^%[", ""):gsub("%]$", "")
    end

    local now = time()
    local isMan = (source == "MANUAL")
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
        isManual = isMan,
        deleted = false
    }

    VM.db.ledger[tx.id] = tx
    VM.Comms:BroadcastTransaction(tx)
    return tx
end

function Ledger:RecordGoldDeposit(playerName, copperAmount, source, rawSender, attributedTo)
    local now = time()
    local isMan = (source == "MANUAL_GOLD" or source == "MANUAL")
    local finalPlayer = attributedTo or playerName
    local tx = {
        id = GenerateTxID("GOLD_IN"),
        type = "IN",
        player = (finalPlayer == "UNATTRIBUTED") and "UNATTRIBUTED" or VM:NormalizeName(finalPlayer),
        rawSender = (rawSender and rawSender ~= "") and VM:NormalizeName(rawSender) or VM:NormalizeName(playerName),
        attributedTo = (attributedTo and attributedTo ~= "") and VM:NormalizeName(attributedTo) or VM:NormalizeName(playerName),
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
        isManual = isMan,
        deleted = false
    }

    VM.db.ledger[tx.id] = tx
    VM.Comms:BroadcastTransaction(tx)
    return tx
end

function Ledger:RecordGoldWithdrawal(playerName, copperAmount, source)
    local now = time()
    local tx = {
        id = GenerateTxID("GOLD_OUT"),
        type = "OUT",
        player = (playerName == "UNATTRIBUTED") and "UNATTRIBUTED" or VM:NormalizeName(playerName),
        itemID = 0,
        itemLink = "GOLD",
        itemName = "Gold Withdrawal",
        count = 1,
        unitPriceAtTime = copperAmount or 0,
        chargedUnitPrice = 0,
        timestamp = now,
        updatedAt = now,
        officer = VM:GetPlayerName(),
        source = source or "BANK_MONEY_LOG",
        isManual = false,
        deleted = false
    }

    VM.db.ledger[tx.id] = tx
    VM.Comms:BroadcastTransaction(tx)
    return tx
end

function Ledger:ReassignGoldDeposit(txID, newPlayerName)
    if not VM:IsOfficer() then return end
    local tx = VM.db.ledger[txID]
    if not tx then return end
    local norm = VM:NormalizeName(newPlayerName)
    if norm == "" then return end

    tx.rawSender = tx.rawSender or tx.player
    tx.attributedTo = norm
    tx.player = norm
    tx.updatedAt = time()

    VM.Comms:BroadcastTransaction(tx)
    if VM.UI then VM.UI:RefreshAll() end
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
    if not tx or not tx.isManual then return end
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
        unitVal = VM:GetItemAHPrice(tx.itemID, tx.itemLink) or tx.unitPriceAtTime or 0
    end
    return unitVal * (tx.count or 0)
end

local function MatchesPeriod(txTimestamp, period)
    if not period or period == "ALL" or period == "" then return true end
    local txDate = date("*t", txTimestamp or 0)
    local nowDate = date("*t", time())
    if period == "CURRENT" then
        return txDate.year == nowDate.year and txDate.month == nowDate.month
    elseif period == "PREVIOUS" then
        local prevMonth = nowDate.month - 1
        local prevYear = nowDate.year
        if prevMonth <= 0 then
            prevMonth = 12
            prevYear = prevYear - 1
        end
        return txDate.year == prevYear and txDate.month == prevMonth
    end
    return true
end

function Ledger:GetAggregatedByMain(useHistorical, periodFilter)
    local groups = {}

    for _, tx in pairs(VM.db.ledger) do
        if not tx.deleted and MatchesPeriod(tx.timestamp, periodFilter) then
            local key = (tx.player == "UNATTRIBUTED") and "UNATTRIBUTED" or VM:GetMainFor(tx.player)
            if not groups[key] then
                groups[key] = {
                    mainName = key,
                    isLegacy = VM:IsLegacyMember(key),
                    totalOutValue = 0,
                    totalInValue = 0,
                    totalGoldIn = 0,
                    totalGoldOut = 0,
                    totalItemsIn = 0,
                    totalCharged = 0,
                    transactions = {}
                }
            end

            local val = self:GetTransactionValue(tx, useHistorical)
            if tx.type == "SUMMARY" then
                groups[key].totalInValue = groups[key].totalInValue + (tx.contributed or 0)
                groups[key].totalOutValue = groups[key].totalOutValue + (tx.received or 0)
                groups[key].totalGoldIn = groups[key].totalGoldIn + (tx.goldIn or 0)
                groups[key].totalGoldOut = (groups[key].totalGoldOut or 0) + (tx.goldOut or 0)
                groups[key].totalItemsIn = groups[key].totalItemsIn + (tx.itemsIn or 0)
            elseif tx.type == "OUT" then
                groups[key].totalOutValue = groups[key].totalOutValue + val
                groups[key].totalCharged = groups[key].totalCharged + ((tx.chargedUnitPrice or 0) * (tx.count or 0))
                if tx.itemID == 0 or tx.itemLink == "GOLD" then
                    groups[key].totalGoldOut = (groups[key].totalGoldOut or 0) + val
                end
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

-- Donation leaderboard (sortMode: "TOTAL" | "GOLD" | "ITEMS", periodFilter, hideOfficers)
function Ledger:GetDonationRanking(sortMode, useHistorical, periodFilter, hideOfficers)
    local allGroups = self:GetAggregatedByMain(useHistorical, periodFilter)
    local ranked = {}

    for _, grp in ipairs(allGroups) do
        local isOfficer = VM:IsOfficerName(grp.mainName)
        if (not hideOfficers or not isOfficer) and grp.mainName ~= "UNATTRIBUTED" then
            local netTotal = grp.totalInValue - grp.totalOutValue
            local netGold = grp.totalGoldIn - (grp.totalGoldOut or 0)
            local netItems = grp.totalItemsIn - (grp.totalOutValue - (grp.totalGoldOut or 0))

            grp.netTotal = netTotal
            grp.netGold = netGold
            grp.netItems = netItems

            if netTotal > 0 or grp.totalInValue > 0 then
                table.insert(ranked, grp)
            end
        end
    end

    table.sort(ranked, function(a, b)
        if a.isLegacy ~= b.isLegacy then
            return not a.isLegacy
        end
        local valA = (sortMode == "GOLD" and a.netGold) or (sortMode == "ITEMS" and a.netItems) or a.netTotal
        local valB = (sortMode == "GOLD" and b.netGold) or (sortMode == "ITEMS" and b.netItems) or b.netTotal
        if valA ~= valB then
            return valA > valB
        end
        return a.mainName < b.mainName
    end)

    return ranked
end

-- Monthly History Compaction (Rolls up ledger entries older than 60 days into monthly summaries)
function Ledger:CompactMonthlyHistory()
    if not VM.db or not VM.db.ledger then return end
    local cutoff = time() - (60 * 86400)
    local groups = {}

    for id, tx in pairs(VM.db.ledger) do
        if not tx.deleted and not tx.isCompacted and (tx.timestamp or 0) < cutoff and tx.type ~= "SUMMARY" then
            local ym = date("%Y-%m", tx.timestamp or 0)
            local main = (tx.player == "UNATTRIBUTED") and "UNATTRIBUTED" or VM:GetMainFor(tx.player)
            local key = main .. "_" .. ym
            if not groups[key] then
                groups[key] = {
                    txs = {},
                    totalIn = 0,
                    totalOut = 0,
                    totalGoldIn = 0,
                    totalGoldOut = 0,
                    totalItemsIn = 0,
                    main = main,
                    ym = ym,
                    ts = tx.timestamp or 0
                }
            end

            local val = self:GetTransactionValue(tx, true)
            if tx.type == "OUT" then
                groups[key].totalOut = groups[key].totalOut + val
                if tx.itemID == 0 or tx.itemLink == "GOLD" then
                    groups[key].totalGoldOut = groups[key].totalGoldOut + val
                end
            else
                groups[key].totalIn = groups[key].totalIn + val
                if tx.itemID == 0 or tx.itemLink == "GOLD" then
                    groups[key].totalGoldIn = groups[key].totalGoldIn + val
                else
                    groups[key].totalItemsIn = groups[key].totalItemsIn + val
                end
            end
            table.insert(groups[key].txs, id)
        end
    end

    local compactedCount = 0
    for key, g in pairs(groups) do
        if #g.txs > 1 then
            local summaryID = string.format("SUM_%s_%s", g.main, g.ym)
            local summaryTx = {
                id = summaryID,
                type = "SUMMARY",
                player = g.main,
                itemName = string.format("%s Monthly Summary", g.ym),
                itemLink = "SUMMARY",
                itemID = 0,
                isManual = false,
                isCompacted = true,
                contributed = g.totalIn,
                received = g.totalOut,
                goldIn = g.totalGoldIn,
                goldOut = g.totalGoldOut,
                itemsIn = g.totalItemsIn,
                unitPriceAtTime = g.totalIn - g.totalOut,
                chargedUnitPrice = 0,
                count = 1,
                timestamp = g.ts,
                updatedAt = time(),
                officer = VM:GetPlayerName(),
                source = "COMPACTED",
                deleted = false
            }

            for _, oldID in ipairs(g.txs) do
                VM.db.ledger[oldID] = nil
            end

            VM.db.ledger[summaryID] = summaryTx
            compactedCount = compactedCount + 1
        end
    end

    if compactedCount > 0 then
        VM:LogDebug(string.format("Compacted %d monthly ledger summaries.", compactedCount))
    end
end
