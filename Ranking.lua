local _, VM = ...
VM.Ranking = {}
local Ranking = VM.Ranking

-- Single valuation path shared with the Ledger (voided pairs, TRANSFER deposits, FFA/WRITE_OFF at
-- 100% AH, discounted member price on % of AH tabs) so Ranking can never diverge from Ledger totals.
function Ranking:GetTransactionValuation(tx, priceMode)
    if not tx then return 0 end
    local mode = priceMode or (VM.db and VM.db.uiPrefs and VM.db.uiPrefs.rankingPriceMode) or "live"
    return VM.Ledger:GetTransactionValue(tx, mode == "locked", mode)
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

function Ranking:GetRankingData(sortMode, sortDir, priceMode, periodFilter, hideOfficers, showLegacy)
    if not VM.db then return {} end
    local pMode = priceMode or VM.db.uiPrefs.rankingPriceMode or "live"
    local sMode = sortMode or VM.db.uiPrefs.rankingSortBy or "net"
    local sDir = sortDir or VM.db.uiPrefs.rankingSortDir or "desc"
    local period = periodFilter or VM.db.uiPrefs.rankingPeriod or "ALL"
    local hideOff = (hideOfficers ~= nil) and hideOfficers or (VM.db.uiPrefs.hideOfficers or false)
    local showLeg = (showLegacy ~= nil) and showLegacy or (VM.db.uiPrefs.showLegacyRanking ~= false)
    local includeFFA = (VM.db and VM.db.uiPrefs and VM.db.uiPrefs.includeFFA ~= false)

    local groups = {}

    for _, tx in pairs(VM.db.ledger) do
        local isGold = (tx.itemID == 0 or tx.itemLink == "GOLD")
        local isFFA = (tx.isFFA == true) or (tx.priceMode == "FREE")
        if not tx.deleted and (includeFFA or not isFFA or isGold) and MatchesPeriod(tx.timestamp, period) then
            local pNorm = VM:NormalizeName(tx.player)
            local key
            if pNorm == "UNATTRIBUTED" or pNorm == "GUILD" then
                key = pNorm
            else
                key = VM:GetMainFor(pNorm)
            end

            if not groups[key] then
                groups[key] = {
                    mainName = key,
                    isLegacy = VM:IsLegacyMember(key),
                    totalContributed = 0,
                    totalWithdrawn = 0,
                    totalGoldIn = 0,
                    totalGoldOut = 0,
                    totalItemsIn = 0,
                    netBalance = 0,
                    transactions = {}
                }
            end

            local val = self:GetTransactionValuation(tx, pMode)
            if tx.type == "SUMMARY" then
                groups[key].totalContributed = groups[key].totalContributed + (tx.contributed or 0)
                groups[key].totalWithdrawn = groups[key].totalWithdrawn + (tx.received or 0)
                groups[key].totalGoldIn = groups[key].totalGoldIn + (tx.goldIn or 0)
                groups[key].totalGoldOut = (groups[key].totalGoldOut or 0) + (tx.goldOut or 0)
                groups[key].totalItemsIn = groups[key].totalItemsIn + (tx.itemsIn or 0)
            elseif tx.type == "OUT" then
                groups[key].totalWithdrawn = groups[key].totalWithdrawn + val
                if isGold then
                    groups[key].totalGoldOut = (groups[key].totalGoldOut or 0) + val
                end
            else
                groups[key].totalContributed = groups[key].totalContributed + val
                if isGold then
                    groups[key].totalGoldIn = groups[key].totalGoldIn + val
                else
                    groups[key].totalItemsIn = groups[key].totalItemsIn + val
                end
            end

            table.insert(groups[key].transactions, tx)
        end
    end

    local ranked = {}
    for _, grp in pairs(groups) do
        if grp.mainName ~= "UNATTRIBUTED" and grp.mainName ~= "GUILD" then
            local isOfficer = VM:IsOfficerName(grp.mainName)
            if not hideOff or not isOfficer then
                if showLeg or not grp.isLegacy then
                    grp.netBalance = grp.totalContributed - grp.totalWithdrawn
                    table.sort(grp.transactions, function(a, b) return (a.timestamp or 0) > (b.timestamp or 0) end)
                    table.insert(ranked, grp)
                end
            end
        end
    end

    table.sort(ranked, function(a, b)
        if a.isLegacy ~= b.isLegacy then
            return not a.isLegacy
        end

        local valA, valB
        if sMode == "contributed" then
            valA = a.totalContributed
            valB = b.totalContributed
        elseif sMode == "withdrawn" then
            valA = a.totalWithdrawn
            valB = b.totalWithdrawn
        elseif sMode == "name" then
            if sDir == "asc" then
                return a.mainName < b.mainName
            else
                return a.mainName > b.mainName
            end
        else -- "net"
            valA = a.netBalance
            valB = b.netBalance
        end

        if valA ~= valB then
            if sDir == "asc" then
                return valA < valB
            else
                return valA > valB
            end
        end

        if a.totalContributed ~= b.totalContributed then
            return a.totalContributed > b.totalContributed
        end
        return a.mainName < b.mainName
    end)

    return ranked
end
