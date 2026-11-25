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
    local addonVer = VM:GetAddonVersion()
    self:SendRaw(string.format("HELLO|%d|%d|%d|%d|%d|%d|%d|%s", VM.VERSION, epoch, invTs, reqTs, mainTs, ruleTs, txTs, EscapeStr(addonVer)))
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
        VM:Print(string.format("Guild reset detected from peer (Epoch %d). Local data reset.", peerEpoch))
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
        local peerAddonVer = nil

        if #parts >= 9 then
            peerVersion = tonumber(parts[2]) or 2
            peerEpoch = tonumber(parts[3]) or 1
            peerInvTs = tonumber(parts[4]) or 0
            peerReqTs = tonumber(parts[5]) or 0
            peerMainTs = tonumber(parts[6]) or 0
            peerRuleTs = tonumber(parts[7]) or 0
            peerTxTs = tonumber(parts[8]) or 0
            peerAddonVer = UnescapeStr(parts[9])
        elseif #parts >= 8 then
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

        local hasNewerAddon = peerAddonVer and (peerAddonVer ~= "") and VM:IsNewerVersion(peerAddonVer, VM:GetAddonVersion())
        local hasNewerProto = (peerVersion > VM.VERSION)

        if hasNewerAddon or hasNewerProto then
            VM.newerVersionAvailable = true
            local prefs = VM.db and VM.db.uiPrefs
            local notifyEnabled = (prefs == nil or prefs.notifyNewerVersion ~= false)
            if notifyEnabled and not Comms.notifiedNewVersion then
                Comms.notifiedNewVersion = true
                local displayVer = (peerAddonVer and peerAddonVer ~= "") and ("v" .. peerAddonVer) or ("protocol v" .. peerVersion)
                print(string.format("|cff00ccff[Vault Manager]|r A newer version of Vault Manager (%s) is available on CurseForge. Please update your addon!", displayVer))
            end
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
        local gold = tonumber(parts[4]) or 0
        local numTabs = tonumber(parts[5]) or 0
        if scanTime == 0 then return end
        if scanTime < (VM.db.inventory.lastScan or 0) then return end

        local nowServer = (GetServerTime and GetServerTime()) or time()
        if scanTime > nowServer + 60 then
            scanTime = nowServer
        end

        if scanTime > (VM.db.inventory.lastScan or 0) then
            VM.db.inventory.lastScan = scanTime
            VM.db.inventory.lastScanBy = scannedBy
            VM.db.inventory.scannedBy = scannedBy
            VM.db.inventory.lastSyncedFrom = sender
            VM.db.inventory.gold = gold
            if numTabs > 0 then VM.db.inventory.numTabs = numTabs end
            VM.db.inventory.tabs = {}
        elseif scanTime == (VM.db.inventory.lastScan or 0) then
            VM.db.inventory.lastSyncedFrom = sender
            if gold > 0 then VM.db.inventory.gold = gold end
            if numTabs > 0 and (not VM.db.inventory.numTabs or VM.db.inventory.numTabs == 0) then
                VM.db.inventory.numTabs = numTabs
            end
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
        local isPurchasedNum = tonumber(parts[6])
        local isPurchased = (isPurchasedNum == nil) or (isPurchasedNum == 1)
        if tabName == "Not purchased" then isPurchased = false end
        if VM.db.inventory.lastScan == 0 then return end
        if scanTime < (VM.db.inventory.lastScan or 0) then return end
        if tabIdx then
            local localTab = VM.db.inventory.tabs[tabIdx]
            if localTab and localTab.items and next(localTab.items) and (not isPurchased or tabName == "Not purchased") then
                local hasUnaccountedItems = false
                for _, lItem in pairs(localTab.items) do
                    local foundOut = false
                    for _, tx in pairs(VM.db.ledger) do
                        if not tx.deleted and tx.type == "OUT" and (tx.tab or 1) == tabIdx then
                            local txItemKey = (tx.itemID and tx.itemID > 0) and tostring(tx.itemID) or tostring(tx.itemLink or tx.itemName or "")
                            local lItemKey = (lItem.itemID and lItem.itemID > 0) and tostring(lItem.itemID) or tostring(lItem.link or lItem.name or "")
                            if txItemKey == lItemKey and math.abs((tx.timestamp or 0) - scanTime) <= 86400 then
                                foundOut = true
                                break
                            end
                        end
                    end
                    if not foundOut then
                        hasUnaccountedItems = true
                        break
                    end
                end
                if hasUnaccountedItems then
                    return
                end
            end
            VM.db.inventory.tabs[tabIdx] = VM.db.inventory.tabs[tabIdx] or { items = {} }
            VM.db.inventory.tabs[tabIdx].name = tabName
            VM.db.inventory.tabs[tabIdx].icon = tabIcon
            VM.db.inventory.tabs[tabIdx].isPurchased = isPurchased
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
        local itemType = (#parts >= 10) and UnescapeStr(parts[10]) or ""
        local equipSlot = (#parts >= 11) and UnescapeStr(parts[11]) or ""
        if VM.db.inventory.lastScan == 0 then return end
        if scanTime < (VM.db.inventory.lastScan or 0) then return end
            local key = (itemID and itemID ~= 0) and itemID or itemName
            VM.db.inventory.tabs[tabIdx] = VM.db.inventory.tabs[tabIdx] or { name = "Tab " .. tabIdx, items = {} }
            local syncItemType = (itemType ~= "") and itemType or nil
            local syncEquipSlot = (equipSlot ~= "") and equipSlot or nil
            if (not syncItemType or not syncEquipSlot) and GetItemInfo then
                local lookup = (itemLink ~= "") and itemLink or (itemID and itemID ~= 0 and itemID)
                if lookup then
                    local r1, r2, r3, r4, r5, r6, r7, r8, r9 = GetItemInfo(lookup)
                    if not syncItemType then
                        if type(r5) == "string" and not tonumber(r5) then
                            syncItemType = r5
                        elseif type(r6) == "string" and not tonumber(r6) then
                            syncItemType = r6
                        end
                    end
                    if not syncEquipSlot then
                        if type(r8) == "string" and r8:find("^INVTYPE_") then
                            syncEquipSlot = r8
                        elseif type(r9) == "string" and r9:find("^INVTYPE_") then
                            syncEquipSlot = r9
                        end
                    end
                end
            end
            VM.db.inventory.tabs[tabIdx].items[key] = {
                itemID = itemID or 0,
                count = count,
                name = itemName,
                link = itemLink,
                icon = icon,
                ahPrice = ahPrice,
                itemType = syncItemType,
                equipSlot = syncEquipSlot
            }
            if VM.UI then VM.UI:RefreshAll() end

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
                VM:Print(string.format("New request from |cffffff00%s|r: %dx %s",
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
        local rawType = UnescapeStr(parts[3])
        local player = UnescapeStr(parts[4])
        local itemID = tonumber(parts[5]) or 0
        local count = tonumber(parts[6]) or 1
        local copper = tonumber(parts[7]) or 0
        local charged = tonumber(parts[8]) or 0
        local timestamp = tonumber(parts[9]) or 0
        local officer = UnescapeStr(parts[10])
        local source = UnescapeStr(parts[11])
        local itemName = UnescapeStr(parts[12])
        local itemLink = UnescapeStr(parts[13])
        local deleted = isNewFormat and (tonumber(parts[14]) == 1) or false
        local updatedAt = tonumber(isNewFormat and parts[15] or parts[14]) or timestamp or 0
        local rawSender = (#parts >= 16) and UnescapeStr(parts[16]) or player
        local attributedTo = (#parts >= 17) and UnescapeStr(parts[17]) or player
        local txId = UnescapeStr(parts[2])

        if copper == 0 and charged > 0 and (itemLink == "GOLD" or rawType:find("GOLD")) then
            copper = charged
        end

        local isGold = (itemLink == "GOLD" or itemLink:find("GOLD"))
            or (itemID == 0 and (copper > 0 or rawType:find("GOLD") or txId:find("^GOLD") or source:find("GOLD") or source == "BANK_MONEY_LOG" or source == "MANUAL_ASSIGN_PAYMENT"))
            or (txId:find("^GOLD_"))
            or (rawType:find("GOLD"))

        local txType = rawType
        if isGold then
            itemID = 0
            itemLink = "GOLD"
            if rawType:find("OUT") or txId:find("^GOLD_OUT") or source:find("OUT") then
                txType = "OUT"
                if itemName == "" or itemName == "Gold Deposit" then itemName = "Gold Withdrawal" end
            else
                txType = "IN"
                if itemName == "" or itemName == "Gold Withdrawal" then itemName = "Gold Deposit" end
            end
        elseif rawType == "GOLD_IN" or (itemID == 0 and rawType == "IN" and (source == "BANK_MONEY_LOG" or itemLink == "GOLD")) then
            txType = "IN"
            if itemLink == "" then itemLink = "GOLD" end
            isGold = true
        elseif rawType == "GOLD_OUT" or (itemID == 0 and rawType == "OUT" and (source == "BANK_MONEY_LOG" or itemLink == "GOLD")) then
            txType = "OUT"
            if itemLink == "" then itemLink = "GOLD" end
            isGold = true
        end

        local tx = {
            id = txId,
            type = txType,
            player = player,
            itemID = itemID,
            count = count,
            unitPriceAtTime = copper,
            chargedUnitPrice = charged,
            timestamp = timestamp,
            officer = officer,
            source = source,
            itemName = itemName,
            itemLink = itemLink,
            deleted = deleted,
            updatedAt = updatedAt,
            rawSender = rawSender,
            attributedTo = attributedTo,
            isFFA = isGold and false or nil,
            isManual = (source == "MANUAL_GOLD" or source == "MANUAL")
        }
        local existing = VM.db.ledger[tx.id]

        -- Deduplicate gold transactions across clients that generated different IDs
        if not existing and isGold then
            for _, exTx in pairs(VM.db.ledger) do
                if not exTx.deleted and exTx.player == tx.player and exTx.type == tx.type and (exTx.itemLink == "GOLD" or exTx.itemID == 0) and (exTx.unitPriceAtTime or 0) == (tx.unitPriceAtTime or 0) then
                    -- Only merge if created by different officers/scanners for the same log line within a 24h window
                    if exTx.officer ~= tx.officer and math.abs((exTx.timestamp or 0) - (tx.timestamp or 0)) <= 86400 then
                        existing = exTx
                        tx.id = exTx.id -- adopt existing id to merge
                        break
                    end
                end
            end
        end

        if existing and existing.unitPriceAtTime and existing.unitPriceAtTime > 0 and (tx.itemLink == "GOLD" or tx.itemID == 0) then
            tx.unitPriceAtTime = existing.unitPriceAtTime
        end
        if not fromOfficer and not isGold and (tx.source ~= "BANK_LOG" and tx.source ~= "BANK_MONEY_LOG" and tx.source ~= "GOLD_IN" and tx.source ~= "GOLD_OUT" and tx.source ~= "MANUAL_GOLD" and tx.itemLink ~= "GOLD") then return end
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
    local gold = tonumber(inv.gold) or 0
    local numTabs = tonumber(inv.numTabs) or 1
    self:SendRaw(string.format("INV_META|%d|%s|%d|%d", inv.lastScan, EscapeStr(scanBy), gold, numTabs))
    for tabIdx, tabData in pairs(inv.tabs) do
        local isPurchased = (tabData.isPurchased ~= false) and 1 or 0
        self:SendRaw(string.format("INV_TAB|%d|%d|%s|%s|%d",
            inv.lastScan, tabIdx, EscapeStr(tabData.name), EscapeStr(tabData.icon), isPurchased))
        for itemID, item in pairs(tabData.items) do
            self:SendRaw(string.format("INV_ITEM|%d|%d|%d|%d|%s|%s|%s|%d|%s|%s",
                inv.lastScan, tabIdx, item.itemID or 0, item.count,
                EscapeStr(item.name), EscapeStr(item.link), EscapeStr(item.icon), item.ahPrice or 0,
                EscapeStr(item.itemType or ""), EscapeStr(item.equipSlot or "")))
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
    if not VM.db or not VM.db.tabRules then return end
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
