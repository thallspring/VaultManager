local _, VM = ...
VM.Comms = {}
local Comms = VM.Comms

local MSG_QUEUE = {}
local THROTTLE_INTERVAL = 0.35
local elapsedSinceSend = 0

local function EscapeStr(s)
    return tostring(s or ""):gsub("%%", "%%25"):gsub("|", "%%7C"):gsub("\n", "%%0A"):gsub("\r", "")
end

local function UnescapeStr(s)
    return tostring(s or ""):gsub("%%0A", "\n"):gsub("%%7C", "|"):gsub("%%25", "%%")
end

function Comms:GetMaxTimestamp(tbl, field)
    local maxTs = 0
    for _, v in pairs(tbl or {}) do
        local ts = (type(v) == "table" and v[field]) or 0
        if ts > maxTs then maxTs = ts end
    end
    return maxTs
end

function Comms:GetRulesMaxTimestamp(tbl)
    local maxTs = 0
    for _, v in pairs(tbl or {}) do
        if type(v) == "table" and not v.tampered then
            local ts = v.updatedAt or 0
            if ts > maxTs then maxTs = ts end
        end
    end
    return maxTs
end

function Comms:Init()
    local f = CreateFrame("Frame")
    f:RegisterEvent("CHAT_MSG_ADDON")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")

    f:SetScript("OnEvent", function(_, event, prefix, msg, channel, sender)
        if event == "CHAT_MSG_ADDON" then
            if prefix == VM.PREFIX and channel == "GUILD" then
                self:OnMessageReceived(msg, VM:NormalizeName(sender))
            end
        elseif event == "PLAYER_ENTERING_WORLD" then
            C_Timer.After(4, function()
                if IsInGuild() then
                    self:SendHello()
                end
            end)
        end
    end)

    f:SetScript("OnUpdate", function(_, elapsed)
        elapsedSinceSend = elapsedSinceSend + elapsed
        if elapsedSinceSend >= THROTTLE_INTERVAL and #MSG_QUEUE > 0 then
            elapsedSinceSend = 0
            local payload = table.remove(MSG_QUEUE, 1)
            if IsInGuild() then
                if C_ChatInfo and C_ChatInfo.SendAddonMessage then
                    C_ChatInfo.SendAddonMessage(VM.PREFIX, payload, "GUILD")
                elseif SendAddonMessage then
                    SendAddonMessage(VM.PREFIX, payload, "GUILD")
                end
            end
        end
    end)
end

function Comms:SendRaw(payload)
    if VM.isUnguilded then return end
    local guildName = GetGuildInfo("player") or ""
    if guildName == "" then return end
    local fullPayload = payload .. "|" .. EscapeStr(guildName)
    for _, existing in ipairs(MSG_QUEUE) do
        if existing == fullPayload then return end
    end
    table.insert(MSG_QUEUE, fullPayload)
end

function Comms:BroadcastEpoch()
    self:SendRaw(string.format("EPOCH|%d", VM.db.dbEpoch or 1))
end

function Comms:SendHello()
    local epoch = VM.db.dbEpoch or 1
    local invTs = VM.db.inventory.lastScan or 0
    local reqTs = self:GetMaxTimestamp(VM.db.requests, "updatedAt")
    local mainTs = self:GetMaxTimestamp(VM.db.mains, "updatedAt")
    local ruleTs = self:GetRulesMaxTimestamp(VM.db.tabRules)
    local txTs = self:GetMaxTimestamp(VM.db.ledger, "updatedAt")
    self:SendRaw(string.format("HELLO|%d|%d|%d|%d|%d|%d|%d", VM.VERSION, epoch, invTs, reqTs, mainTs, ruleTs, txTs))
end

local function CheckAndAdoptEpoch(peerEpoch)
    if peerEpoch and peerEpoch > (VM.db.dbEpoch or 1) then
        VM.db.dbEpoch = peerEpoch
        VM.db.inventory = { lastScan = 0, scannedBy = "", tabs = {} }
        VM.db.ledger = {}
        VM.db.processedBankLogs = {}
        VM.db.requests = {}
        VM.db.tabRules = {}
        VM.db.mains = {}
        print(string.format("|cff00ccff[Vault Manager]|r Guild reset detected from peer (Epoch %d). Local data reset.", peerEpoch))
        if VM.UI then VM.UI:RefreshAll() end
        return true
    end
    return false
end

function Comms:OnMessageReceived(msg, sender)
    if sender == VM:GetPlayerName() then return end
    if VM.isUnguilded then return end

    local parts = { strsplit("|", msg) }
    if #parts < 2 then return end
    local incomingGuild = UnescapeStr(parts[#parts])
    local playerGuild = GetGuildInfo("player") or ""
    if not playerGuild or playerGuild == "" or incomingGuild ~= playerGuild then
        return -- Drop mismatched payloads silently
    end
    table.remove(parts, #parts)

    local cmd = parts[1]
    local fromOfficer = VM:IsOfficerName(sender)

    if cmd == "EPOCH" then
        local peerEpoch = tonumber(parts[2]) or 1
        CheckAndAdoptEpoch(peerEpoch)
        return
    end

    if cmd == "HELLO" then
        local peerVersion = 2
        local peerEpoch = 1
        local peerInvTs, peerReqTs, peerMainTs, peerRuleTs, peerTxTs = 0, 0, 0, 0, 0

        if #parts >= 8 then
            peerVersion = tonumber(parts[2]) or 2
            peerEpoch = tonumber(parts[3]) or 1
            peerInvTs = tonumber(parts[4]) or 0
            peerReqTs = tonumber(parts[5]) or 0
            peerMainTs = tonumber(parts[6]) or 0
            peerRuleTs = tonumber(parts[7]) or 0
            peerTxTs = tonumber(parts[8]) or 0
        elseif #parts >= 7 then
            peerVersion = tonumber(parts[2]) or 2
            peerInvTs = tonumber(parts[3]) or 0
            peerReqTs = tonumber(parts[4]) or 0
            peerMainTs = tonumber(parts[5]) or 0
            peerRuleTs = tonumber(parts[6]) or 0
            peerTxTs = tonumber(parts[7]) or 0
        else
            peerInvTs = tonumber(parts[2]) or 0
            peerReqTs = tonumber(parts[3]) or 0
            peerMainTs = tonumber(parts[4]) or 0
            peerRuleTs = tonumber(parts[5]) or 0
            peerTxTs = tonumber(parts[6]) or 0
        end

        if CheckAndAdoptEpoch(peerEpoch) then return end
        if peerEpoch < (VM.db.dbEpoch or 1) then return end

        if peerVersion > VM.VERSION then
            if not Comms.notifiedNewVersion then
                Comms.notifiedNewVersion = true
                print(string.format("|cff00ccff[Vault Manager]|r A newer version of Vault Manager is available on CurseForge (peer running protocol v%d). Please update your addon!", peerVersion))
            end
            VM.newerVersionAvailable = true
            if VM.UI and VM.UI.RefreshAll then VM.UI:RefreshAll() end
        end

        if (VM.db.inventory.lastScan or 0) > peerInvTs then
            self:BroadcastInventory()
        end

        if self:GetMaxTimestamp(VM.db.requests, "updatedAt") > peerReqTs then
            local cutoff = time() - (30 * 86400)
            for _, req in pairs(VM.db.requests) do
                if req.status == "PENDING" or req.status == "APPROVED" or (req.updatedAt or 0) > cutoff then
                    self:BroadcastRequest(req)
                end
            end
        end

        if self:GetMaxTimestamp(VM.db.mains, "updatedAt") > peerMainTs then
            self:BroadcastMains()
        end

        if self:GetRulesMaxTimestamp(VM.db.tabRules) > peerRuleTs then
            self:BroadcastTabRules()
        end

        if self:GetMaxTimestamp(VM.db.ledger, "updatedAt") > peerTxTs then
            self:BroadcastLedgerSync()
        end

    elseif cmd == "INV_META" then
        local scanTime = tonumber(parts[2]) or 0
        local scannedBy = UnescapeStr(parts[3])
        if scanTime == 0 then return end

        local nowServer = (GetServerTime and GetServerTime()) or time()
        if scanTime > nowServer + 60 then
            scanTime = nowServer
        end

        if scanTime > (VM.db.inventory.lastScan or 0) then
            VM.db.inventory.lastScan = scanTime
            VM.db.inventory.lastScanBy = scannedBy
            VM.db.inventory.scannedBy = scannedBy
            VM.db.inventory.lastSyncedFrom = sender
            VM.db.inventory.tabs = {}
        elseif scanTime == (VM.db.inventory.lastScan or 0) then
            VM.db.inventory.lastSyncedFrom = sender
        end
        if VM.BankScanner then
            VM.BankScanner.scanState = "COMPLETE"
        end
        if VM.UI then VM.UI:RefreshAll() end

    elseif cmd == "INV_TAB" then
        local scanTime = tonumber(parts[2]) or 0
        local tabIdx = tonumber(parts[3])
        local tabName = UnescapeStr(parts[4])
        local tabIcon = UnescapeStr(parts[5])
        if VM.db.inventory.lastScan == 0 then return end
        if scanTime >= (VM.db.inventory.lastScan or 0) and tabIdx then
            VM.db.inventory.tabs[tabIdx] = VM.db.inventory.tabs[tabIdx] or { items = {} }
            VM.db.inventory.tabs[tabIdx].name = tabName
            VM.db.inventory.tabs[tabIdx].icon = tabIcon
        end

    elseif cmd == "INV_ITEM" then
        local scanTime = tonumber(parts[2]) or 0
        local tabIdx = tonumber(parts[3])
        local itemID = tonumber(parts[4])
        local count = tonumber(parts[5])
        local itemName = UnescapeStr(parts[6])
        local itemLink = UnescapeStr(parts[7])
        local icon = UnescapeStr(parts[8])
        local ahPrice = tonumber(parts[9]) or 0
        if VM.db.inventory.lastScan == 0 then return end
        if scanTime >= (VM.db.inventory.lastScan or 0) and tabIdx and (itemID or itemName) then
            local key = (itemID and itemID ~= 0) and itemID or itemName
            VM.db.inventory.tabs[tabIdx] = VM.db.inventory.tabs[tabIdx] or { name = "Tab " .. tabIdx, items = {} }
            VM.db.inventory.tabs[tabIdx].items[key] = {
                itemID = itemID or 0,
                count = count,
                name = itemName,
                link = itemLink,
                icon = icon,
                ahPrice = ahPrice
            }
            if VM.UI then VM.UI:RefreshAll() end
        end

    elseif cmd == "REQ" then
        local req = {
            id = UnescapeStr(parts[2]),
            requester = UnescapeStr(parts[3]),
            itemID = tonumber(parts[4]) or parts[4],
            count = tonumber(parts[5]),
            tab = tonumber(parts[6]),
            status = UnescapeStr(parts[7]),
            createdAt = tonumber(parts[8]),
            updatedAt = tonumber(parts[9]) or 0,
            approvedBy = UnescapeStr(parts[10]),
            fulfilledBy = UnescapeStr(parts[11]),
            quotedUnitPrice = tonumber(parts[12]) or 0,
            priceMode = UnescapeStr(parts[13]),
            pricePercent = tonumber(parts[14]) or 0,
            itemName = UnescapeStr(parts[15]),
            itemLink = UnescapeStr(parts[16]),
        }
        local existing = VM.db.requests[req.id]
        if not fromOfficer and (existing or req.status ~= "PENDING") then return end
        if not existing or req.updatedAt > (existing.updatedAt or 0) then
            VM.db.requests[req.id] = req
            if VM:IsOfficer() and req.status == "PENDING" and not existing then
                print(string.format("|cff00ccff[Vault Manager]|r New request from |cffffff00%s|r: %dx %s",
                    req.requester, req.count, req.itemLink or req.itemName))
            end
            if VM.UI then VM.UI:RefreshAll() end
        end

    elseif cmd == "RULE" then
        local tabIdx = tonumber(parts[2])
        local mode = UnescapeStr(parts[3])
        local pct = tonumber(parts[4]) or 50
        local updatedAt = tonumber(parts[5]) or 0
        local updatedBy = (#parts >= 6) and UnescapeStr(parts[6]) or sender
        local sig = (#parts >= 7) and UnescapeStr(parts[7]) or ""

        if not tabIdx then return end

        local cleanBy = updatedBy:match("^[^-]+") or updatedBy
        cleanBy = VM:NormalizeName(cleanBy)

        if cleanBy == "System(TamperReset)" or not VM:IsOfficerName(cleanBy) then
            return
        end

        VM:UpdateRosterCache()
        local normBy = VM:NormalizeName(updatedBy)
        if VM.db.rosterCache and next(VM.db.rosterCache) then
            local rankIdx = VM.db.rosterCache[normBy]
            if rankIdx ~= nil and rankIdx > VM.OFFICER_MAX_RANK_INDEX and rankIdx ~= 0 then
                return
            end
        end

        local ruleData = {
            mode = mode,
            percent = pct,
            updatedAt = updatedAt,
            updatedBy = updatedBy
        }
        local guildName = incomingGuild or GetGuildInfo("player") or ""
        local expectedSig = VM:ComputeRuleSignature(guildName, tabIdx, ruleData)
        if sig == "" or sig ~= expectedSig then
            return
        end
        ruleData.sig = sig
        ruleData.tampered = nil

        local existing = VM.db.tabRules[tabIdx]
        if existing and (existing.updatedAt or 0) >= updatedAt then
            return
        end

        VM.db.tabRules[tabIdx] = ruleData
        if VM.UI then VM.UI:RefreshAll() end

    elseif cmd == "MAIN" then
        if not fromOfficer then return end
        local alt = UnescapeStr(parts[2])
        local main = UnescapeStr(parts[3])
        local updatedAt = tonumber(parts[4]) or 0
        local existing = VM.db.mains[alt]
        local existingTs = (type(existing) == "table" and existing.updatedAt) or 0
        if alt ~= "" and updatedAt > existingTs then
            VM.db.mains[alt] = { main = main, updatedAt = updatedAt }
            if VM.UI then VM.UI:RefreshAll() end
        end

    elseif cmd == "TX" then
        local isNewFormat = (#parts >= 15)
        local tx = {
            id = UnescapeStr(parts[2]),
            type = UnescapeStr(parts[3]),
            player = UnescapeStr(parts[4]),
            itemID = tonumber(parts[5]) or 0,
            count = tonumber(parts[6]),
            unitPriceAtTime = tonumber(parts[7]) or 0,
            chargedUnitPrice = tonumber(parts[8]) or 0,
            timestamp = tonumber(parts[9]) or 0,
            officer = UnescapeStr(parts[10]),
            source = UnescapeStr(parts[11]),
            itemName = UnescapeStr(parts[12]),
            itemLink = UnescapeStr(parts[13]),
            deleted = isNewFormat and (tonumber(parts[14]) == 1) or false,
            updatedAt = tonumber(isNewFormat and parts[15] or parts[14]) or tonumber(parts[9]) or 0,
            rawSender = (#parts >= 16) and UnescapeStr(parts[16]) or UnescapeStr(parts[4]),
            attributedTo = (#parts >= 17) and UnescapeStr(parts[17]) or UnescapeStr(parts[4]),
            isManual = (UnescapeStr(parts[11]) == "MANUAL_GOLD" or UnescapeStr(parts[11]) == "MANUAL")
        }
        local existing = VM.db.ledger[tx.id]
        if existing and existing.unitPriceAtTime and existing.unitPriceAtTime > 0 then
            tx.unitPriceAtTime = existing.unitPriceAtTime
        end
        if not fromOfficer and (existing or (tx.source ~= "BANK_LOG" and tx.source ~= "BANK_MONEY_LOG")) then return end
        if tx.id ~= "" and (not existing or tx.updatedAt > (existing.updatedAt or existing.timestamp or 0)) then
            VM.db.ledger[tx.id] = tx
            if VM.UI then VM.UI:RefreshAll() end
        end
    end
end

function Comms:BroadcastInventory()
    local inv = VM.db.inventory
    if not inv or not inv.lastScan or inv.lastScan == 0 then return end
    local scanBy = inv.lastScanBy or inv.scannedBy or UnitName("player")
    self:SendRaw(string.format("INV_META|%d|%s", inv.lastScan, EscapeStr(scanBy)))
    for tabIdx, tabData in pairs(inv.tabs) do
        self:SendRaw(string.format("INV_TAB|%d|%d|%s|%s",
            inv.lastScan, tabIdx, EscapeStr(tabData.name), EscapeStr(tabData.icon)))
        for itemID, item in pairs(tabData.items) do
            self:SendRaw(string.format("INV_ITEM|%d|%d|%d|%d|%s|%s|%s|%d",
                inv.lastScan, tabIdx, item.itemID or 0, item.count,
                EscapeStr(item.name), EscapeStr(item.link), EscapeStr(item.icon), item.ahPrice or 0))
        end
    end
end

function Comms:BroadcastRequest(req)
    if not VM.db.inventory or VM.db.inventory.lastScan == 0 then return end
    self:SendRaw(string.format("REQ|%s|%s|%s|%d|%d|%s|%d|%d|%s|%s|%d|%s|%d|%s|%s",
        EscapeStr(req.id), EscapeStr(req.requester), tostring(req.itemID), req.count, req.tab,
        EscapeStr(req.status), req.createdAt or 0, req.updatedAt or 0,
        EscapeStr(req.approvedBy), EscapeStr(req.fulfilledBy),
        req.quotedUnitPrice or 0, EscapeStr(req.priceMode), req.pricePercent or 0,
        EscapeStr(req.itemName), EscapeStr(req.itemLink)))
end

function Comms:BroadcastTabRules()
    if not VM.db.inventory or VM.db.inventory.lastScan == 0 then return end
    local guildName = GetGuildInfo("player") or VM:GetActiveGuildKey() or ""
    for tabIdx, rule in pairs(VM.db.tabRules) do
        if rule and not rule.tampered then
            local uBy = rule.updatedBy or VM:GetPlayerName()
            local sig = rule.sig or VM:ComputeRuleSignature(guildName, tabIdx, rule)
            rule.sig = sig
            self:SendRaw(string.format("RULE|%d|%s|%d|%d|%s|%s",
                tabIdx, EscapeStr(rule.mode), rule.percent or 50, rule.updatedAt or 0, EscapeStr(uBy), EscapeStr(sig)))
        end
    end
end

function Comms:BroadcastMains()
    for alt, entry in pairs(VM.db.mains) do
        local main = type(entry) == "table" and entry.main or entry
        local ts = type(entry) == "table" and entry.updatedAt or 0
        self:SendRaw(string.format("MAIN|%s|%s|%d", EscapeStr(alt), EscapeStr(main), ts))
    end
end

function Comms:BroadcastTransaction(tx)
    if not VM.db.inventory or VM.db.inventory.lastScan == 0 then return end
    local delVal = tx.deleted and 1 or 0
    self:SendRaw(string.format("TX|%s|%s|%s|%s|%d|%d|%d|%d|%s|%s|%s|%s|%d|%d|%s|%s",
        EscapeStr(tx.id), EscapeStr(tx.type), EscapeStr(tx.player),
        tostring(tx.itemID), tx.count, tx.unitPriceAtTime or 0, tx.chargedUnitPrice or 0,
        tx.timestamp or 0, EscapeStr(tx.officer), EscapeStr(tx.source),
        EscapeStr(tx.itemName), EscapeStr(tx.itemLink), delVal, tx.updatedAt or tx.timestamp or 0,
        EscapeStr(tx.rawSender or tx.player), EscapeStr(tx.attributedTo or tx.player)))
end

function Comms:BroadcastLedgerSync()
    if not VM.db.inventory or VM.db.inventory.lastScan == 0 then return end
    local cutoff = time() - (90 * 86400)
    for _, tx in pairs(VM.db.ledger) do
        if not tx.deleted and (tx.updatedAt or tx.timestamp or 0) > cutoff then
            self:BroadcastTransaction(tx)
        elseif tx.deleted and (tx.updatedAt or tx.timestamp or 0) > cutoff then
            self:BroadcastTransaction(tx)
        end
    end
end
