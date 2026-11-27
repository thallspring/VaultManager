local _, VM = ...
VM.Ledger = {}
local Ledger = VM.Ledger

Ledger.GUILD_CATEGORIES = { "RAID", "MEMBER", "TABS" }
Ledger.GUILD_CATEGORY_LABELS = {
    RAID = "Raid",
    MEMBER = "Member",
    TABS = "Tabs",
}

function Ledger:NormalizeGuildCategory(cat)
    if not cat or cat == "" then return nil end
    local u = strupper(strtrim(tostring(cat)))
    if u == "RAID" or u == "RAIDS" then return "RAID" end
    if u == "MEMBER" or u == "MEMBERS" then return "MEMBER" end
    if u == "TAB" or u == "TABS" then return "TABS" end
    return nil
end

function Ledger:GetGuildCategoryLabel(cat)
    local norm = self:NormalizeGuildCategory(cat)
    return norm and self.GUILD_CATEGORY_LABELS[norm] or nil
end

local function GenerateTxID(prefix)
    return string.format("%s_%d_%d", prefix, time(), math.random(10000, 99999))
end

function Ledger:RecordFulfillment(req, officerName, customTimestamp)
    local livePrice = VM:GetEffectiveLivePrice(req.itemID, req.itemLink, req.priceAtRequest or req.quotedUnitPrice)
    local qty = tonumber(req.count) or 1
    local rule = { mode = req.priceMode or "FREE", percent = req.pricePercent or 50 }
    local totalCharged = VM:CalculateMemberTotalPrice(livePrice, qty, rule)
    local unitCharged = (qty > 0) and math.floor(totalCharged / qty) or totalCharged

    local now = time()
    local txTimestamp = customTimestamp or now
    local tx = {
        id = GenerateTxID("OUT"),
        type = "OUT",
        player = VM:NormalizeName(req.requester),
        rawSender = VM:NormalizeName(req.requester),
        attributedTo = VM:NormalizeName(req.requester),
        itemID = req.itemID,
        itemLink = req.itemLink,
        itemName = req.itemName,
        count = qty,
        unitPriceAtTime = livePrice,
        chargedUnitPrice = unitCharged,
        chargedTotalPrice = totalCharged,
        priceMode = req.priceMode,
        pricePercent = req.pricePercent,
        isFFA = (req.priceMode == "FREE"),
        tab = req.tab,
        timestamp = txTimestamp,
        updatedAt = now,
        officer = VM:NormalizeName(officerName),
        source = "REQUEST",
        status = "pending_confirmation",
        fulfillmentId = req.id,
        withdrawnBy = VM:NormalizeName(officerName),
        recipient = VM:NormalizeName(req.requester),
        isManual = false,
        deleted = false
    }

    VM.db.ledger[tx.id] = tx
    VM.Comms:BroadcastTransaction(tx)
    return tx
end

function Ledger:RecordGoldFulfillment(req, officerName, customTimestamp)
    local amount = tonumber(req.goldAmount or req.quotedTotalPrice or req.quotedUnitPrice) or 0
    if amount <= 0 then return nil end

    local now = time()
    local txTimestamp = customTimestamp or now
    local requesterNorm = VM:NormalizeName(req.requester)
    local guildCat = self:NormalizeGuildCategory(req.guildCategory) or "RAID"
    local tx = {
        id = GenerateTxID("GOLD_OUT"),
        type = "OUT",
        player = "GUILD",
        rawSender = requesterNorm,
        attributedTo = "GUILD",
        guildCategory = guildCat,
        itemID = 0,
        itemLink = "GOLD",
        itemName = "Gold Withdrawal",
        count = 1,
        unitPriceAtTime = amount,
        chargedUnitPrice = amount,
        chargedTotalPrice = amount,
        note = req.reason or "",
        timestamp = txTimestamp,
        updatedAt = now,
        officer = VM:NormalizeName(officerName),
        source = "GOLD_REQUEST",
        fulfillmentId = req.id,
        recipient = requesterNorm,
        isFFA = false,
        isManual = false,
        deleted = false
    }

    VM.db.ledger[tx.id] = tx
    VM.Comms:BroadcastTransaction(tx)
    return tx
end

-- Write off a PREPARED request when the responsible officer has left the guild (100% AH / gold charged to departed officer)
function Ledger:RecordWriteOff(req, officerName)
    if not req then return nil end
    local departedOfficer = VM:NormalizeName(req.preparedBy or req.approvedBy or "")
    if departedOfficer == "" then return nil end

    local now = time()
    local reqName = VM:NormalizeName(req.requester or "Unknown")
    local tx

    if req.isGoldRequest then
        local amount = tonumber(req.goldAmount or req.quotedTotalPrice or req.quotedUnitPrice) or 0
        if amount <= 0 then return nil end
        tx = {
            id = GenerateTxID("GOLD_WO"),
            type = "OUT",
            player = departedOfficer,
            rawSender = departedOfficer,
            attributedTo = departedOfficer,
            itemID = 0,
            itemLink = "GOLD",
            itemName = "Gold Write-Off",
            count = 1,
            unitPriceAtTime = amount,
            chargedUnitPrice = amount,
            chargedTotalPrice = amount,
            note = string.format("Write-off: unfulfilled gold request for %s", reqName),
            timestamp = now,
            updatedAt = now,
            officer = VM:NormalizeName(officerName),
            source = "WRITE_OFF",
            fulfillmentId = req.id,
            recipient = departedOfficer,
            isFFA = false,
            isManual = false,
            deleted = false
        }
    else
        local qty = tonumber(req.count) or 1
        local fullUnit = VM:GetEffectiveLivePrice(req.itemID, req.itemLink, req.priceAtRequest or req.quotedUnitPrice)
        local fullTotal = fullUnit * qty
        tx = {
            id = GenerateTxID("OUT_WO"),
            type = "OUT",
            player = departedOfficer,
            rawSender = departedOfficer,
            attributedTo = departedOfficer,
            itemID = req.itemID,
            itemLink = req.itemLink,
            itemName = req.itemName,
            count = qty,
            unitPriceAtTime = fullUnit,
            chargedUnitPrice = fullUnit,
            chargedTotalPrice = fullTotal,
            priceMode = "WRITE_OFF",
            isFFA = false,
            tab = req.tab,
            note = string.format("Write-off: unfulfilled request for %s", reqName),
            timestamp = now,
            updatedAt = now,
            officer = VM:NormalizeName(officerName),
            source = "WRITE_OFF",
            fulfillmentId = req.id,
            recipient = departedOfficer,
            isManual = false,
            deleted = false
        }
    end

    VM.db.ledger[tx.id] = tx
    VM.Comms:BroadcastTransaction(tx)
    return tx
end

-- General officer guild expense / write-off under GUILD (categorized as RAID, MEMBER, or TABS)
function Ledger:RecordGuildExpense(copperAmount, guildCategory, note, actorName)
    if not VM:IsOfficer() then return nil end
    local amount = math.floor(tonumber(copperAmount) or 0)
    if amount <= 0 then return nil end

    local now = time()
    local cat = self:NormalizeGuildCategory(guildCategory) or "MEMBER"
    local actor = (actorName and actorName ~= "") and VM:NormalizeName(actorName) or VM:GetPlayerName()
    local tx = {
        id = GenerateTxID("GOLD_EXP"),
        type = "OUT",
        player = "GUILD",
        rawSender = actor,
        attributedTo = "GUILD",
        guildCategory = cat,
        itemID = 0,
        itemLink = "GOLD",
        itemName = "Guild Expense",
        count = 1,
        unitPriceAtTime = amount,
        chargedUnitPrice = amount,
        chargedTotalPrice = amount,
        note = strtrim(tostring(note or "")),
        timestamp = now,
        updatedAt = now,
        officer = VM:GetPlayerName(),
        source = "GUILD_EXPENSE",
        isFFA = false,
        isManual = true,
        deleted = false
    }

    VM.db.ledger[tx.id] = tx
    VM.Comms:BroadcastTransaction(tx)
    if VM.UI then VM.UI:RefreshAll() end
    return tx
end

-- Automatic Guild Bank Tab purchase booking under GUILD (Tabs) with 48h duplicate protection
function Ledger:RecordTabPurchase(copperAmount, buyerName, customTimestamp, tabNumber)
    local amount = math.floor(tonumber(copperAmount) or 0)
    if amount <= 0 then return nil end

    local now = time()
    local txTimestamp = customTimestamp or now
    for _, exTx in pairs(VM.db.ledger or {}) do
        if not exTx.deleted and exTx.source == "TAB_PURCHASE" then
            local exCopper = (exTx.unitPriceAtTime or 0) * (exTx.count or 1)
            if exCopper == amount and math.abs((exTx.timestamp or 0) - txTimestamp) <= 172800 then
                return exTx
            end
        end
    end

    local actor = (buyerName and buyerName ~= "") and VM:NormalizeName(buyerName) or "GUILD"
    local noteStr = tabNumber and ("Guild Bank Tab " .. tostring(tabNumber)) or "New Guild Bank Tab"
    local tx = {
        id = GenerateTxID("GOLD_TAB"),
        type = "OUT",
        player = "GUILD",
        rawSender = actor,
        attributedTo = "GUILD",
        guildCategory = "TABS",
        itemID = 0,
        itemLink = "GOLD",
        itemName = "Guild Bank Tab Purchase",
        count = 1,
        unitPriceAtTime = amount,
        chargedUnitPrice = amount,
        chargedTotalPrice = amount,
        note = noteStr,
        timestamp = txTimestamp,
        updatedAt = now,
        officer = VM:GetPlayerName(),
        source = "TAB_PURCHASE",
        isFFA = false,
        isManual = false,
        deleted = false
    }

    VM.db.ledger[tx.id] = tx
    VM.Comms:BroadcastTransaction(tx)
    return tx
end

function Ledger:RecordReturnDeposit(playerName, itemID, itemLink, count, fulfillmentId, customTimestamp)
    local ahPrice = VM:GetItemAHPrice(itemID, itemLink) or 0
    local cleanLink = itemLink or "item:0"
    local itemName = cleanLink:gsub("^%[", ""):gsub("%]$", "")
    local now = time()
    local txTimestamp = customTimestamp or now
    local normPlayer = VM:NormalizeName(playerName)
    local tx = {
        id = GenerateTxID("IN"),
        type = "IN",
        player = normPlayer,
        rawSender = normPlayer,
        attributedTo = normPlayer,
        itemID = itemID or 0,
        itemLink = cleanLink,
        itemName = itemName,
        count = count or 1,
        unitPriceAtTime = ahPrice,
        chargedUnitPrice = 0,
        timestamp = txTimestamp,
        updatedAt = now,
        officer = VM:GetPlayerName(),
        source = "RETURN",
        tag = "[RETURNED]",
        netValue = 0,
        deleted = false
    }

    for _, otx in pairs(VM.db.ledger) do
        if otx.fulfillmentId == fulfillmentId and not otx.deleted then
            otx.voided = true
            otx.netValue = 0
            otx.updatedAt = now
        end
    end

    VM.db.ledger[tx.id] = tx
    VM.db.activeReturn = nil
    VM.Comms:BroadcastTransaction(tx)
    if VM.UI then VM.UI:RefreshAll() end
    return tx
end

function Ledger:RecordDeposit(playerName, itemID, itemLink, count, source, customTimestamp, tab, isFFA)
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
    local txTimestamp = customTimestamp or now
    local isMan = (source == "MANUAL")
    local normPlayer = (playerName == "UNATTRIBUTED") and "UNATTRIBUTED" or VM:NormalizeName(playerName)
    local tx = {
        id = GenerateTxID("IN"),
        type = "IN",
        player = normPlayer,
        rawSender = normPlayer,
        attributedTo = normPlayer,
        itemID = itemID or 0,
        itemLink = cleanLink,
        itemName = itemName,
        count = count or 1,
        unitPriceAtTime = ahPrice,
        chargedUnitPrice = 0,
        tab = tab,
        isFFA = isFFA,
        timestamp = txTimestamp,
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

function Ledger:RecordGoldDeposit(playerName, copperAmount, source, rawSender, attributedTo, customTimestamp, note, guildCategory)
    local now = time()
    local txTimestamp = customTimestamp or now
    local isMan = (source == "MANUAL_GOLD" or source == "MANUAL")
    local finalPlayer = attributedTo or playerName
    local normFinal = (finalPlayer == "UNATTRIBUTED") and "UNATTRIBUTED" or VM:NormalizeName(finalPlayer)
    local normRaw = (rawSender and rawSender ~= "") and VM:NormalizeName(rawSender) or VM:NormalizeName(playerName)
    local normCat = (normFinal == "GUILD") and self:NormalizeGuildCategory(guildCategory) or nil
    local tx = {
        id = GenerateTxID("GOLD_IN"),
        type = "IN",
        player = normFinal,
        rawSender = normRaw,
        attributedTo = normFinal,
        guildCategory = normCat,
        itemID = 0,
        itemLink = "GOLD",
        itemName = "Gold Deposit",
        count = 1,
        unitPriceAtTime = copperAmount or 0,
        chargedUnitPrice = 0,
        note = note or "",
        timestamp = txTimestamp,
        updatedAt = now,
        officer = VM:GetPlayerName(),
        source = source or "BANK_MONEY_LOG",
        isFFA = false,
        isManual = isMan,
        deleted = false
    }

    VM.db.ledger[tx.id] = tx
    VM.Comms:BroadcastTransaction(tx)
    return tx
end

function Ledger:RecordGoldWithdrawal(playerName, copperAmount, source, customTimestamp, rawSender, attributedTo, note, guildCategory)
    local now = time()
    local txTimestamp = customTimestamp or now
    local finalPlayer = attributedTo or playerName
    local normFinal = (finalPlayer == "UNATTRIBUTED") and "UNATTRIBUTED" or VM:NormalizeName(finalPlayer)
    local normRaw = (rawSender and rawSender ~= "") and VM:NormalizeName(rawSender) or VM:NormalizeName(playerName)
    local normCat = (normFinal == "GUILD") and self:NormalizeGuildCategory(guildCategory) or nil
    local tx = {
        id = GenerateTxID("GOLD_OUT"),
        type = "OUT",
        player = normFinal,
        rawSender = normRaw,
        attributedTo = normFinal,
        guildCategory = normCat,
        itemID = 0,
        itemLink = "GOLD",
        itemName = "Gold Withdrawal",
        count = 1,
        unitPriceAtTime = copperAmount or 0,
        chargedUnitPrice = 0,
        note = note or "",
        timestamp = txTimestamp,
        updatedAt = now,
        officer = VM:GetPlayerName(),
        source = source or "BANK_MONEY_LOG",
        isFFA = false,
        isManual = false,
        deleted = false
    }

    VM.db.ledger[tx.id] = tx
    VM.Comms:BroadcastTransaction(tx)
    return tx
end

function Ledger:ReassignTransaction(txID, newPlayerName, guildCategory)
    if not VM:IsOfficer() then return end
    local tx = VM.db.ledger[txID]
    if not tx or tx.deleted or tx.type == "SUMMARY" or tx.isDerived then return end
    local norm = VM:NormalizeName(newPlayerName)
    if norm == "" then return end

    if not tx.rawSender or tx.rawSender == "" then
        tx.rawSender = tx.player
    end
    tx.attributedTo = norm
    tx.player = norm
    if norm == "GUILD" then
        tx.guildCategory = self:NormalizeGuildCategory(guildCategory) or tx.guildCategory or "MEMBER"
    else
        tx.guildCategory = nil
    end
    tx.updatedAt = time()

    VM.Comms:BroadcastTransaction(tx)
    if VM.UI then VM.UI:RefreshAll() end
end

function Ledger:ReassignGoldDeposit(txID, newPlayerName, guildCategory)
    return self:ReassignTransaction(txID, newPlayerName, guildCategory)
end

function Ledger:AssignUnattributed(txID, memberName, guildCategory)
    if not VM:IsOfficer() then return end
    local tx = VM.db.ledger[txID]
    if not tx or tx.isDerived then return end
    local norm = VM:NormalizeName(memberName)
    if norm == "" then return end
    if not tx.rawSender or tx.rawSender == "" then
        tx.rawSender = tx.player
    end
    tx.player = norm
    tx.attributedTo = norm
    if norm == "GUILD" then
        tx.guildCategory = self:NormalizeGuildCategory(guildCategory) or tx.guildCategory or "MEMBER"
    else
        tx.guildCategory = nil
    end
    tx.updatedAt = time()
    VM.Comms:BroadcastTransaction(tx)
    if VM.UI then VM.UI:RefreshAll() end
end

function Ledger:DeleteTransaction(txID)
    if not VM:IsOfficer() then return end
    local tx = VM.db.ledger[txID]
    if not tx or not tx.isManual or tx.isDerived then return end
    tx.deleted = true
    tx.updatedAt = time()
    VM.Comms:BroadcastTransaction(tx)
    if VM.UI then VM.UI:RefreshAll() end
end

function Ledger:GetFullItemValue(tx, useHistorical, priceMode)
    if not tx or tx.voided or tx.netValue == 0 or tx.tag == "[RETURNED]" then
        return 0
    end
    if tx.itemID == 0 or tx.itemLink == "GOLD" then
        return (tx.unitPriceAtTime or 0) * (tx.count or 1)
    end

    local mode = priceMode or (VM.db and VM.db.uiPrefs and VM.db.uiPrefs.rankingPriceMode) or "live"
    local unitVal = 0
    if mode == "locked" or useHistorical then
        unitVal = (tx.unitPriceAtTime and tx.unitPriceAtTime > 0) and tx.unitPriceAtTime or (VM:GetEffectiveLivePrice(tx.itemID, tx.itemLink, tx.unitPriceAtTime) or 0)
    else -- "live"
        local livePrice = VM:GetEffectiveLivePrice(tx.itemID, tx.itemLink, tx.unitPriceAtTime) or 0
        unitVal = (livePrice > 0) and livePrice or (tx.unitPriceAtTime or 0)
    end
    return unitVal * (tx.count or 0)
end

-- Returns member/account valuation:
-- * Gold: exact copper
-- * FFA (FREE) & WRITE_OFF OUT: 100% AH value on member
-- * % of AH OUT: rounded member price (chargedTotalPrice); remainder goes dynamically to GUILD (Member)
function Ledger:GetTransactionValue(tx, useHistorical, priceMode)
    if not tx then return 0 end
    if tx.isDerived and tx.derivedValue ~= nil then
        return tx.derivedValue
    end
    if tx.voided or tx.netValue == 0 or tx.tag == "[RETURNED]" then
        return 0
    end
    if tx.itemID == 0 or tx.itemLink == "GOLD" then
        return (tx.unitPriceAtTime or 0) * (tx.count or 1)
    end

    local isFFA = (tx.isFFA == true) or (tx.priceMode == "FREE")
    if tx.type == "OUT" and not isFFA and tx.source ~= "WRITE_OFF" then
        if tx.chargedTotalPrice ~= nil and tx.chargedTotalPrice >= 0 then
            return tx.chargedTotalPrice
        elseif tx.chargedUnitPrice ~= nil and tx.chargedUnitPrice >= 0 then
            return tx.chargedUnitPrice * (tx.count or 1)
        elseif tx.priceMode == "PERCENT" then
            local base = (tx.unitPriceAtTime and tx.unitPriceAtTime > 0) and tx.unitPriceAtTime or (VM:GetEffectiveLivePrice(tx.itemID, tx.itemLink, tx.unitPriceAtTime) or 0)
            return VM:CalculateMemberTotalPrice(base, tx.count or 1, { mode = "PERCENT", percent = tx.pricePercent or 50 })
        end
    end

    return self:GetFullItemValue(tx, useHistorical, priceMode)
end

-- Computes dynamic zero-sum GUILD adjustment for discounted (% of AH) member withdrawals:
-- Positive = Guild subsidy (OUT on GUILD); Negative = 1g min rounding surplus (IN on GUILD)
function Ledger:GetGuildSubsidyDelta(tx, useHistorical, priceMode)
    if not tx or tx.deleted or tx.voided or tx.netValue == 0 or tx.tag == "[RETURNED]" then return 0 end
    if tx.type ~= "OUT" or tx.type == "SUMMARY" or tx.isDerived then return 0 end
    if tx.itemID == 0 or tx.itemLink == "GOLD" then return 0 end
    if tx.source == "WRITE_OFF" then return 0 end

    local pNorm = VM:NormalizeName(tx.player)
    if pNorm == "GUILD" then return 0 end

    local isFFA = (tx.isFFA == true) or (tx.priceMode == "FREE")
    if isFFA then return 0 end

    local isDiscounted = (tx.priceMode == "PERCENT")
        or (tx.chargedTotalPrice ~= nil and tx.chargedTotalPrice >= 0)
        or (tx.chargedUnitPrice ~= nil and tx.chargedUnitPrice > 0)
    if not isDiscounted then return 0 end

    local fullAH = self:GetFullItemValue(tx, useHistorical, priceMode)
    if fullAH <= 0 then return 0 end

    local memberVal = self:GetTransactionValue(tx, useHistorical, priceMode)
    return fullAH - memberVal
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

local function EnsureGroup(groups, key)
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
            transactions = {},
            latestDonationTimestamp = 0
        }
    end
    return groups[key]
end

function Ledger:GetAggregatedByMain(useHistorical, periodFilter, priceMode)
    local groups = {}
    local includeFFA = (VM.db and VM.db.uiPrefs and VM.db.uiPrefs.includeFFA ~= false)

    for _, tx in pairs(VM.db.ledger) do
        local isGold = (tx.itemID == 0 or tx.itemLink == "GOLD")
        local isFFA = (tx.isFFA == true) or (tx.priceMode == "FREE")
        if not tx.deleted and (includeFFA or not isFFA or isGold) and MatchesPeriod(tx.timestamp, periodFilter) then
            local pNorm = VM:NormalizeName(tx.player)
            local key
            if pNorm == "UNATTRIBUTED" or pNorm == "GUILD" then
                key = pNorm
            else
                key = VM:GetMainFor(pNorm)
            end

            local grp = EnsureGroup(groups, key)
            local val = self:GetTransactionValue(tx, useHistorical, priceMode)

            if tx.type == "SUMMARY" then
                grp.totalInValue = grp.totalInValue + (tx.contributed or 0)
                grp.totalOutValue = grp.totalOutValue + (tx.received or 0)
                grp.totalGoldIn = grp.totalGoldIn + (tx.goldIn or 0)
                grp.totalGoldOut = (grp.totalGoldOut or 0) + (tx.goldOut or 0)
                grp.totalItemsIn = grp.totalItemsIn + (tx.itemsIn or 0)
                grp.latestDonationTimestamp = math.max(grp.latestDonationTimestamp, tx.timestamp or 0)
            elseif tx.type == "OUT" then
                grp.totalOutValue = grp.totalOutValue + val
                local chargedAmt = (tx.chargedTotalPrice ~= nil) and tx.chargedTotalPrice or ((tx.chargedUnitPrice or 0) * (tx.count or 0))
                grp.totalCharged = grp.totalCharged + chargedAmt
                if isGold then
                    grp.totalGoldOut = (grp.totalGoldOut or 0) + val
                end
            else
                grp.totalInValue = grp.totalInValue + val
                grp.latestDonationTimestamp = math.max(grp.latestDonationTimestamp, tx.timestamp or 0)
                if isGold then
                    grp.totalGoldIn = grp.totalGoldIn + val
                else
                    grp.totalItemsIn = grp.totalItemsIn + val
                end
            end

            table.insert(grp.transactions, tx)

            -- Zero-sum dynamic GUILD entry for % of AH member subsidy or 1g-minimum rounding surplus
            local delta = self:GetGuildSubsidyDelta(tx, useHistorical, priceMode)
            if delta ~= 0 then
                local guildGrp = EnsureGroup(groups, "GUILD")
                if delta > 0 then
                    local subTx = {
                        id = "DERIVED_SUB_" .. tostring(tx.id),
                        type = "OUT",
                        player = "GUILD",
                        rawSender = pNorm,
                        attributedTo = "GUILD",
                        guildCategory = "MEMBER",
                        itemID = tx.itemID,
                        itemLink = tx.itemLink,
                        itemName = tx.itemName,
                        count = tx.count or 1,
                        unitPriceAtTime = tx.unitPriceAtTime,
                        derivedValue = delta,
                        isDerived = true,
                        derivedKind = "SUBSIDY",
                        note = string.format("Member subsidy (%d%% AH)", tx.pricePercent or 50),
                        timestamp = tx.timestamp or 0,
                        source = "DERIVED_SUBSIDY",
                    }
                    guildGrp.totalOutValue = guildGrp.totalOutValue + delta
                    table.insert(guildGrp.transactions, subTx)
                else
                    local surplus = -delta
                    local surTx = {
                        id = "DERIVED_SUR_" .. tostring(tx.id),
                        type = "IN",
                        player = "GUILD",
                        rawSender = pNorm,
                        attributedTo = "GUILD",
                        guildCategory = "MEMBER",
                        itemID = tx.itemID,
                        itemLink = tx.itemLink,
                        itemName = tx.itemName,
                        count = tx.count or 1,
                        unitPriceAtTime = tx.unitPriceAtTime,
                        derivedValue = surplus,
                        isDerived = true,
                        derivedKind = "SURPLUS",
                        note = "Rounding surplus (1g min)",
                        timestamp = tx.timestamp or 0,
                        source = "DERIVED_SURPLUS",
                    }
                    guildGrp.totalInValue = guildGrp.totalInValue + surplus
                    table.insert(guildGrp.transactions, surTx)
                end
            end
        end
    end

    local sorted = {}
    for _, grp in pairs(groups) do
        table.sort(grp.transactions, function(a, b) return (a.timestamp or 0) > (b.timestamp or 0) end)
        table.insert(sorted, grp)
    end

    table.sort(sorted, function(a, b)
        if a.mainName ~= b.mainName then
            if a.mainName == "UNATTRIBUTED" then return true end
            if b.mainName == "UNATTRIBUTED" then return false end
            if a.mainName == "GUILD" then return true end
            if b.mainName == "GUILD" then return false end
        end
        if a.isLegacy ~= b.isLegacy then
            return not a.isLegacy
        end
        if (a.latestDonationTimestamp or 0) ~= (b.latestDonationTimestamp or 0) then
            return (a.latestDonationTimestamp or 0) > (b.latestDonationTimestamp or 0)
        end
        if a.totalOutValue ~= b.totalOutValue then
            return a.totalOutValue > b.totalOutValue
        end
        return a.mainName < b.mainName
    end)

    return sorted
end

-- Donation leaderboard (sortMode: "TOTAL" | "GOLD" | "ITEMS", periodFilter, hideOfficers)
function Ledger:GetDonationRanking(sortMode, useHistorical, periodFilter, hideOfficers, priceMode)
    local allGroups = self:GetAggregatedByMain(useHistorical, periodFilter, priceMode)
    local ranked = {}

    for _, grp in ipairs(allGroups) do
        local isOfficer = VM:IsOfficerName(grp.mainName)
        if (not hideOfficers or not isOfficer) and grp.mainName ~= "UNATTRIBUTED" and grp.mainName ~= "GUILD" then
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

function Ledger:HasCompactedMonth(playerName, timestamp)
    if not VM.db or not VM.db.ledger or not timestamp or timestamp <= 0 then return false end
    local ym = date("%Y-%m", timestamp)
    local norm = VM:NormalizeName(playerName)
    local main = (norm == "UNATTRIBUTED" or norm == "GUILD" or norm == "") and norm or VM:GetMainFor(norm)
    if main == "" then return false end
    local summaryID = string.format("SUM_%s_%s", main, ym)
    local sumTx = VM.db.ledger[summaryID]
    return (sumTx ~= nil and not sumTx.deleted and sumTx.type == "SUMMARY")
end

-- Monthly History Compaction (Rolls up ledger entries older than 60 days into monthly summaries & purges 90-day tombstones)
function Ledger:CompactMonthlyHistory()
    if not VM.db or not VM.db.ledger then return end
    local now = time()
    local cutoff = now - (60 * 86400)
    local tombstoneCutoff = now - (90 * 86400)
    local groups = {}
    local guildSubsidyByMonth = {}
    local purgedTombstones = 0

    for id, tx in pairs(VM.db.ledger) do
        if tx and tx.deleted then
            if (tx.updatedAt or tx.timestamp or 0) < tombstoneCutoff then
                VM.db.ledger[id] = nil
                purgedTombstones = purgedTombstones + 1
            end
        elseif tx and not tx.isCompacted and (tx.timestamp or 0) < cutoff and tx.type ~= "SUMMARY" then
            local ym = date("%Y-%m", tx.timestamp or 0)
            local pNorm = VM:NormalizeName(tx.player)
            local main = (pNorm == "UNATTRIBUTED" or pNorm == "GUILD") and pNorm or VM:GetMainFor(pNorm)
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

            -- Preserve derived GUILD subsidy/surplus if this member transaction gets compacted
            local delta = self:GetGuildSubsidyDelta(tx, true)
            if delta ~= 0 then
                guildSubsidyByMonth[ym] = guildSubsidyByMonth[ym] or { inVal = 0, outVal = 0, ts = tx.timestamp or 0, sourceKeys = {} }
                if delta > 0 then
                    guildSubsidyByMonth[ym].outVal = guildSubsidyByMonth[ym].outVal + delta
                else
                    guildSubsidyByMonth[ym].inVal = guildSubsidyByMonth[ym].inVal + (-delta)
                end
                guildSubsidyByMonth[ym].sourceKeys[key] = true
            end

            table.insert(groups[key].txs, id)
        end
    end

    local compactedKeys = {}
    local compactedCount = 0
    for key, g in pairs(groups) do
        local summaryID = string.format("SUM_%s_%s", g.main, g.ym)
        local existingSum = VM.db.ledger[summaryID]
        if #g.txs > 1 or (existingSum and not existingSum.deleted and existingSum.type == "SUMMARY") then
            local baseIn = (existingSum and existingSum.contributed) or 0
            local baseOut = (existingSum and existingSum.received) or 0
            local baseGoldIn = (existingSum and existingSum.goldIn) or 0
            local baseGoldOut = (existingSum and existingSum.goldOut) or 0
            local baseItemsIn = (existingSum and existingSum.itemsIn) or 0

            local totalIn = baseIn + g.totalIn
            local totalOut = baseOut + g.totalOut
            local summaryTx = {
                id = summaryID,
                type = "SUMMARY",
                player = g.main,
                itemName = string.format("%s Monthly Summary", g.ym),
                itemLink = "SUMMARY",
                itemID = 0,
                isManual = false,
                isCompacted = true,
                contributed = totalIn,
                received = totalOut,
                goldIn = baseGoldIn + g.totalGoldIn,
                goldOut = baseGoldOut + g.totalGoldOut,
                itemsIn = baseItemsIn + g.totalItemsIn,
                unitPriceAtTime = totalIn - totalOut,
                chargedUnitPrice = 0,
                count = 1,
                timestamp = (existingSum and existingSum.timestamp) or g.ts,
                updatedAt = now,
                officer = VM:GetPlayerName(),
                source = "COMPACTED",
                deleted = false
            }

            for _, oldID in ipairs(g.txs) do
                VM.db.ledger[oldID] = nil
            end

            VM.db.ledger[summaryID] = summaryTx
            compactedKeys[key] = true
            compactedCount = compactedCount + 1
        end
    end

    -- Roll preserved subsidy/surplus into GUILD's monthly summary for any compacted member groups
    for ym, sub in pairs(guildSubsidyByMonth) do
        local anyCompacted = false
        for sKey in pairs(sub.sourceKeys) do
            if compactedKeys[sKey] then anyCompacted = true; break end
        end
        if anyCompacted and (sub.inVal > 0 or sub.outVal > 0) then
            local gSumID = "SUM_GUILD_" .. ym
            local existing = VM.db.ledger[gSumID]
            local totalIn = ((existing and existing.contributed) or 0) + sub.inVal
            local totalOut = ((existing and existing.received) or 0) + sub.outVal
            VM.db.ledger[gSumID] = {
                id = gSumID,
                type = "SUMMARY",
                player = "GUILD",
                itemName = string.format("%s Monthly Summary", ym),
                itemLink = "SUMMARY",
                itemID = 0,
                isManual = false,
                isCompacted = true,
                contributed = totalIn,
                received = totalOut,
                goldIn = (existing and existing.goldIn) or 0,
                goldOut = (existing and existing.goldOut) or 0,
                itemsIn = (existing and existing.itemsIn) or 0,
                unitPriceAtTime = totalIn - totalOut,
                chargedUnitPrice = 0,
                count = 1,
                timestamp = (existing and existing.timestamp) or sub.ts,
                updatedAt = now,
                officer = VM:GetPlayerName(),
                source = "COMPACTED",
                deleted = false
            }
        end
    end

    if compactedCount > 0 or purgedTombstones > 0 then
        VM:LogDebug(string.format("Compacted %d monthly summaries, purged %d old tombstones.", compactedCount, purgedTombstones))
    end
end

function Ledger:CleanupDuplicates()
    if not VM.db or not VM.db.ledger then return 0 end

    local protectedSources = {
        MANUAL = true,
        MANUAL_GOLD = true,
        MANUAL_ASSIGN = true,
        MANUAL_ASSIGN_PAYMENT = true,
        REQUEST = true,
        GOLD_REQUEST = true,
        RETURN = true,
        COMPACTED = true,
        WRITE_OFF = true,
        TAB_PURCHASE = true,
        GUILD_EXPENSE = true,
    }

    local groups = {}
    for id, tx in pairs(VM.db.ledger) do
        if tx and tx.timestamp and not tx.deleted and not tx.isManual and tx.type ~= "SUMMARY" and not protectedSources[tx.source or ""] then
            local isGold = (tx.itemID == 0 or tx.itemLink == "GOLD" or tx.source == "BANK_MONEY_LOG" or (tx.itemName and (tx.itemName:find("Gold Deposit") or tx.itemName:find("Gold Withdrawal"))))
            local action = VM:NormalizeAction(tx.type)
            local actor = VM:NormalizeActor(tx.rawSender or tx.player)
            local groupKey
            if isGold then
                local copper = (tx.unitPriceAtTime or 0) * (tx.count or 1)
                groupKey = string.format("GOLD:%s:%s:%d", action, actor, copper)
            else
                local itemKey = VM:NormalizeItemKey(tx.itemID, tx.itemLink, tx.itemName)
                local count = tonumber(tx.count or 1)
                groupKey = string.format("ITEM:%s:%s:%s:%d", action, actor, itemKey, count)
            end
            groups[groupKey] = groups[groupKey] or {}
            table.insert(groups[groupKey], { id = id, tx = tx })
        end
    end

    local WINDOW_48H = 172800
    local removedCount = 0

    for _, entries in pairs(groups) do
        if #entries > 1 then
            table.sort(entries, function(a, b)
                local tsA = a.tx.timestamp or 0
                local tsB = b.tx.timestamp or 0
                if tsA ~= tsB then
                    return tsA < tsB
                end
                return tostring(a.id) < tostring(b.id)
            end)

            local kept = {}
            for _, entry in ipairs(entries) do
                local isDup = false
                for _, keptTx in ipairs(kept) do
                    local timeDiff = math.abs((entry.tx.timestamp or 0) - (keptTx.timestamp or 0))
                    if timeDiff <= WINDOW_48H then
                        isDup = true
                        break
                    end
                end

                if isDup then
                    VM.db.ledger[entry.id] = nil
                    removedCount = removedCount + 1
                else
                    table.insert(kept, entry.tx)
                end
            end
        end
    end

    if removedCount > 0 then
        VM:LogDebug(string.format("Ledger:CleanupDuplicates purged %d duplicate transactions.", removedCount))
        if VM.UI and VM.UI.RefreshAll then
            VM.UI:RefreshAll()
        end
    end
    return removedCount
end
