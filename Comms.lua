local _, VM = ...
VM.Comms = {}
local Comms = VM.Comms

local MSG_QUEUE = {}
local THROTTLE_INTERVAL = 0.35
local elapsedSinceSend = 0

local uiRefreshNeeded = false
local uiRefreshTimer = 0
local UI_REFRESH_DEBOUNCE = 0.35

local ZONE_HELLO_INTERVAL = 900 -- 15 min cooldown on regular zone/instance loading screens
local MANUAL_SYNC_COOLDOWN = 10

Comms.lastHelloSentAt = 0
Comms.lastManualSyncAt = 0
Comms.lastDataReceivedAt = 0
Comms.isSyncingUntil = 0
Comms.peerHasNewerData = false
Comms.peerNewerSetAt = 0
local helloTimerPending = false

local pendingHelloSync = nil
local recentPeerBroadcasts = {
    invScan = 0, invAt = 0,
    reqTs = 0, reqAt = 0,
    mainTs = 0, mainAt = 0,
    ruleTs = 0, ruleAt = 0,
    txTs = 0, txAt = 0,
}

local PROTECTED_TX_SOURCES = {
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

local function EscapeStr(s)
    return tostring(s or ""):gsub("%%", "%%25"):gsub("|", "%%7C"):gsub("\n", "%%0A"):gsub("\r", "")
end

local function UnescapeStr(s)
    return tostring(s or ""):gsub("%%0A", "\n"):gsub("%%7C", "|"):gsub("%%25", "%%")
end

local function GetMaxPayloadLen()
    local guildName = GetGuildInfo("player") or ""
    local suffixLen = 1 + #EscapeStr(guildName)
    return math.max(100, 254 - suffixLen)
end

local function ResolveReceivedItemLink(itemID, itemLink, itemName)
    if itemLink and itemLink ~= "" then
        return itemLink
    end
    local numID = tonumber(itemID)
    if numID and numID > 0 and GetItemInfo then
        local _, realLink = GetItemInfo(numID)
        if realLink and realLink ~= "" then
            return realLink
        end
    end
    if itemName and itemName ~= "" then
        return itemName
    end
    return nil
end

local function ScheduleUIRefresh()
    uiRefreshNeeded = true
    uiRefreshTimer = UI_REFRESH_DEBOUNCE
end

local function MarkDataReceived()
    local nowGT = GetTime and GetTime() or 0
    Comms.lastDataReceivedAt = time()
    Comms.peerHasNewerData = false
    Comms.isSyncingUntil = math.max(Comms.isSyncingUntil or 0, nowGT + 1.5)
    if C_Timer and C_Timer.After then
        C_Timer.After(1.7, function()
            if VM.UI and VM.UI.UpdateScanStatusButton then
                VM.UI:UpdateScanStatusButton()
            end
        end)
    end
end

local function ScheduleHelloWithDelay(delaySec)
    if helloTimerPending then return end
    helloTimerPending = true
    local function RunHello()
        helloTimerPending = false
        if IsInGuild() and not VM.isUnguilded then
            Comms:SendHello()
        end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(delaySec, RunHello)
    else
        RunHello()
    end
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

function Comms:RequestManualSync()
    if VM.isUnguilded or not IsInGuild() then
        return false, 0
    end
    local nowGT = GetTime and GetTime() or 0
    local elapsed = nowGT - (self.lastManualSyncAt or 0)
    if self.lastManualSyncAt > 0 and elapsed < MANUAL_SYNC_COOLDOWN then
        return false, math.ceil(MANUAL_SYNC_COOLDOWN - elapsed)
    end

    self.lastManualSyncAt = nowGT
    self.isSyncingUntil = nowGT + 4.0
    self:SendHello()
    if VM.UI and VM.UI.UpdateScanStatusButton then
        VM.UI:UpdateScanStatusButton()
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(4.2, function()
            if VM.UI and VM.UI.UpdateScanStatusButton then
                VM.UI:UpdateScanStatusButton()
            end
        end)
    end
    return true, 0
end

function Comms:GetSyncButtonStatus()
    if VM.isUnguilded then
        return "NO_GUILD", "No Guild", { 0.35, 0.35, 0.35, 1 }, "Join a guild to sync vault data."
    end
    if VM.BankScanner and VM.BankScanner.scanState == "SCANNING" then
        return "SCANNING", "Scanning...", { 0.70, 0.55, 0.10, 1 }, "Scanning Guild Bank tabs and logs..."
    end

    local nowGT = GetTime and GetTime() or 0
    if nowGT < (self.isSyncingUntil or 0) then
        return "SYNCING", "Syncing...", { 0.70, 0.55, 0.10, 1 }, "Checking online guild members for newer data..."
    end

    -- Expire stale peer-newer hint after 30s if the peer went offline
    if self.peerHasNewerData and (nowGT - (self.peerNewerSetAt or 0)) > 30 then
        self.peerHasNewerData = false
    end

    local lastScan = (VM.db and VM.db.inventory and VM.db.inventory.lastScan) or 0
    if lastScan == 0 then
        return "NEED_SYNC", "Request Sync", { 0.15, 0.50, 0.80, 1 }, "No local bank data. Click to request guild sync from online members."
    end

    if self.peerHasNewerData then
        return "NEED_SYNC", "Sync Data", { 0.15, 0.50, 0.80, 1 }, "An online guild member has newer data. Click to sync."
    end

    local lastRxStr = (self.lastDataReceivedAt and self.lastDataReceivedAt > 0)
        and ("Last guild update: " .. date("%H:%M", self.lastDataReceivedAt))
        or "Up to date with online peers"
    return "SYNCED", "Data Synced", { 0.18, 0.55, 0.28, 1 }, lastRxStr .. "\nClick to check online members for updates."
end

function Comms:Init()
    local f = CreateFrame("Frame")
    f:RegisterEvent("CHAT_MSG_ADDON")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")

    f:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4)
        if event == "CHAT_MSG_ADDON" then
            local prefix, msg, channel, sender = arg1, arg2, arg3, arg4
            if prefix == VM.PREFIX and channel == "GUILD" then
                self:OnMessageReceived(msg, VM:NormalizeName(sender))
            end
        elseif event == "PLAYER_ENTERING_WORLD" then
            local isInitialLogin, isReloadingUi = arg1, arg2
            local emptyCache = (not VM.db or not VM.db.inventory or (VM.db.inventory.lastScan or 0) == 0)
            if isInitialLogin or isReloadingUi or emptyCache then
                -- Randomized 3-8s delay on login/reload to prevent guild-wide spikes
                ScheduleHelloWithDelay(3 + (math.random() * 5))
            else
                -- Regular zone/instance loading screens: only sync if 15+ min elapsed
                local now = time()
                if (now - (self.lastHelloSentAt or 0)) >= ZONE_HELLO_INTERVAL then
                    ScheduleHelloWithDelay(4 + (math.random() * 8))
                end
            end
        end
    end)

    f:SetScript("OnUpdate", function(_, elapsed)
        if uiRefreshNeeded then
            uiRefreshTimer = uiRefreshTimer - elapsed
            if uiRefreshTimer <= 0 then
                uiRefreshNeeded = false
                if VM.UI and VM.UI.RefreshAll then
                    VM.UI:RefreshAll()
                end
            end
        end

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
    if #fullPayload > 255 then
        VM:LogDebug(string.format("Comms:SendRaw skipped oversized payload (%d bytes): %s", #fullPayload, tostring(payload):sub(1, 32)))
        return
    end
    for _, existing in ipairs(MSG_QUEUE) do
        if existing == fullPayload then return end
    end
    table.insert(MSG_QUEUE, fullPayload)
end

function Comms:BroadcastEpoch()
    self:SendRaw(string.format("EPOCH|%d", VM.db.dbEpoch or 1))
end

function Comms:SendHello()
    if VM.isUnguilded or not IsInGuild() then return end
    self.lastHelloSentAt = time()
    local epoch = VM.db.dbEpoch or 1
    local invTs = (VM.db.inventory and VM.db.inventory.lastScan) or 0
    local reqTs = self:GetMaxTimestamp(VM.db.requests, "updatedAt")
    local mainTs = self:GetMaxTimestamp(VM.db.mains, "updatedAt")
    local ruleTs = self:GetRulesMaxTimestamp(VM.db.tabRules)
    local txTs = self:GetMaxTimestamp(VM.db.ledger, "updatedAt")
    local addonVer = VM:GetAddonVersion()
    self:SendRaw(string.format("HELLO|%d|%d|%d|%d|%d|%d|%d|%s",
        VM.VERSION, epoch, invTs, reqTs, mainTs, ruleTs, txTs, EscapeStr(addonVer)))
end

local function CheckAndAdoptEpoch(peerEpoch)
    if peerEpoch and peerEpoch > (VM.db.dbEpoch or 1) then
        VM.db.dbEpoch = peerEpoch
        VM.db.inventory = { lastScan = 0, scannedBy = "", gold = 0, tabs = {} }
        VM.db.vault = VM.db.inventory
        VM.db.scanMetadata = VM.db.inventory
        VM.db.ledger = {}
        VM.db.processedBankLogs = {}
        VM.db.requests = {}
        VM.db.fulfillments = VM.db.requests
        VM.db.tabRules = {}
        VM.db.mains = {}
        VM.db.roster = VM.db.mains
        VM:Print(string.format("Guild reset detected from peer (Epoch %d). Local data reset.", peerEpoch))
        if VM.Minimap and VM.Minimap.UpdateBadge then VM.Minimap:UpdateBadge() end
        ScheduleUIRefresh()
        return true
    end
    return false
end

local function ExecutePendingHelloSync()
    local req = pendingHelloSync
    pendingHelloSync = nil
    if not req or VM.isUnguilded or not VM.db then return end

    local nowGT = GetTime and GetTime() or 0
    local SUPPRESS_WINDOW = 10

    local myInvTs = (VM.db.inventory and VM.db.inventory.lastScan) or 0
    if myInvTs > req.invTs then
        local peerCovered = (recentPeerBroadcasts.invScan >= myInvTs) and ((nowGT - recentPeerBroadcasts.invAt) < SUPPRESS_WINDOW)
        if not peerCovered then
            Comms:BroadcastInventory()
        end
    end

    local myReqTs = Comms:GetMaxTimestamp(VM.db.requests, "updatedAt")
    if myReqTs > req.reqTs then
        local peerCovered = (recentPeerBroadcasts.reqTs >= myReqTs) and ((nowGT - recentPeerBroadcasts.reqAt) < SUPPRESS_WINDOW)
        if not peerCovered then
            local cutoff = time() - (30 * 86400)
            for _, r in pairs(VM.db.requests or {}) do
                local rUpd = r.updatedAt or r.createdAt or 0
                local isActive = (r.status == "PENDING" or r.status == "APPROVED" or r.status == "PREPARED")
                if rUpd > req.reqTs and (isActive or rUpd > cutoff) then
                    Comms:BroadcastRequest(r)
                end
            end
        end
    end

    local myMainTs = Comms:GetMaxTimestamp(VM.db.mains, "updatedAt")
    if myMainTs > req.mainTs then
        local peerCovered = (recentPeerBroadcasts.mainTs >= myMainTs) and ((nowGT - recentPeerBroadcasts.mainAt) < SUPPRESS_WINDOW)
        if not peerCovered then
            Comms:BroadcastMains(req.mainTs)
        end
    end

    local myRuleTs = Comms:GetRulesMaxTimestamp(VM.db.tabRules)
    if myRuleTs > req.ruleTs then
        local peerCovered = (recentPeerBroadcasts.ruleTs >= myRuleTs) and ((nowGT - recentPeerBroadcasts.ruleAt) < SUPPRESS_WINDOW)
        if not peerCovered then
            Comms:BroadcastTabRules(req.ruleTs)
        end
    end

    local myTxTs = Comms:GetMaxTimestamp(VM.db.ledger, "updatedAt")
    if myTxTs > req.txTs then
        local peerCovered = (recentPeerBroadcasts.txTs >= myTxTs) and ((nowGT - recentPeerBroadcasts.txAt) < SUPPRESS_WINDOW)
        if not peerCovered then
            Comms:BroadcastLedgerSync(req.txTs)
        end
    end
end

function Comms:ScheduleHelloResponse(peerInvTs, peerReqTs, peerMainTs, peerRuleTs, peerTxTs)
    if pendingHelloSync then
        pendingHelloSync.invTs = math.min(pendingHelloSync.invTs, peerInvTs)
        pendingHelloSync.reqTs = math.min(pendingHelloSync.reqTs, peerReqTs)
        pendingHelloSync.mainTs = math.min(pendingHelloSync.mainTs, peerMainTs)
        pendingHelloSync.ruleTs = math.min(pendingHelloSync.ruleTs, peerRuleTs)
        pendingHelloSync.txTs = math.min(pendingHelloSync.txTs, peerTxTs)
        return
    end

    pendingHelloSync = {
        invTs = peerInvTs,
        reqTs = peerReqTs,
        mainTs = peerMainTs,
        ruleTs = peerRuleTs,
        txTs = peerTxTs,
    }

    local delay
    if VM:IsOfficer() then
        delay = 0.4 + (math.random() * 1.1)
    else
        delay = 1.5 + (math.random() * 2.0)
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(delay, ExecutePendingHelloSync)
    else
        ExecutePendingHelloSync()
    end
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
    local nowGT = GetTime and GetTime() or 0

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
            ScheduleUIRefresh()
        end

        local myInvTs = (VM.db.inventory and VM.db.inventory.lastScan) or 0
        local myReqTs = self:GetMaxTimestamp(VM.db.requests, "updatedAt")
        local myMainTs = self:GetMaxTimestamp(VM.db.mains, "updatedAt")
        local myRuleTs = self:GetRulesMaxTimestamp(VM.db.tabRules)
        local myTxTs = self:GetMaxTimestamp(VM.db.ledger, "updatedAt")

        local iHaveNewer =
            (myInvTs > peerInvTs)
            or (myReqTs > peerReqTs)
            or (myMainTs > peerMainTs)
            or (myRuleTs > peerRuleTs)
            or (myTxTs > peerTxTs)

        if iHaveNewer then
            self:ScheduleHelloResponse(peerInvTs, peerReqTs, peerMainTs, peerRuleTs, peerTxTs)
        end

        -- If the peer has newer data than us, automatically send our HELLO back (throttled) so they push the delta
        local peerHasNewer =
            (peerInvTs > myInvTs)
            or (peerReqTs > myReqTs)
            or (peerMainTs > myMainTs)
            or (peerRuleTs > myRuleTs)
            or (peerTxTs > myTxTs)

        if peerHasNewer then
            self.peerHasNewerData = true
            self.peerNewerSetAt = nowGT
            if (time() - (self.lastHelloSentAt or 0)) >= 30 then
                ScheduleHelloWithDelay(1.5 + (math.random() * 2.5))
            end
            ScheduleUIRefresh()
        end

    elseif cmd == "INV_META" then
        local scanTime = tonumber(parts[2]) or 0
        local scannedBy = UnescapeStr(parts[3])
        local gold = tonumber(parts[4]) or 0
        local numTabs = tonumber(parts[5]) or 0
        if scanTime == 0 then return end

        if scanTime >= recentPeerBroadcasts.invScan then
            recentPeerBroadcasts.invScan = scanTime
            recentPeerBroadcasts.invAt = nowGT
        end

        local prevLastScan = (VM.db.inventory and VM.db.inventory.lastScan) or 0
        if scanTime < prevLastScan then return end

        local nowServer = (GetServerTime and GetServerTime()) or time()
        if scanTime > nowServer + 60 then
            scanTime = nowServer
        end

        if scanTime > prevLastScan then
            VM.db.inventory.lastScan = scanTime
            VM.db.inventory.lastScanTime = scanTime
            VM.db.inventory.lastScanBy = scannedBy
            VM.db.inventory.scannedBy = scannedBy
            VM.db.inventory.lastSyncedFrom = sender
            VM.db.inventory.gold = gold
            if numTabs > 0 then VM.db.inventory.numTabs = numTabs end
            VM.db.inventory.tabs = {}
            VM.db.vault = VM.db.inventory
            if VM.db.scanMetadata then
                VM.db.scanMetadata.lastScan = scanTime
                VM.db.scanMetadata.lastScanTime = scanTime
                VM.db.scanMetadata.lastScanBy = scannedBy
                VM.db.scanMetadata.scannedBy = scannedBy
            end
        elseif scanTime == prevLastScan then
            VM.db.inventory.lastSyncedFrom = sender
            if gold > 0 then VM.db.inventory.gold = gold end
            if numTabs > 0 and (not VM.db.inventory.numTabs or VM.db.inventory.numTabs == 0) then
                VM.db.inventory.numTabs = numTabs
            end
        end
        if VM.BankScanner then
            VM.BankScanner.scanState = "COMPLETE"
        end
        MarkDataReceived()
        ScheduleUIRefresh()

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
            if not isPurchased then
                VM.db.inventory.tabs[tabIdx].items = {}
            end
            MarkDataReceived()
            ScheduleUIRefresh()
        end

    elseif cmd == "INV_ITEM" then
        local scanTime = tonumber(parts[2]) or 0
        local tabIdx = tonumber(parts[3])
        local itemID = tonumber(parts[4])
        local count = tonumber(parts[5])
        local itemName = UnescapeStr(parts[6])
        local rawItemLink = UnescapeStr(parts[7])
        local icon = UnescapeStr(parts[8])
        local ahPrice = tonumber(parts[9]) or 0
        local itemType = (#parts >= 10) and UnescapeStr(parts[10]) or ""
        local equipSlot = (#parts >= 11) and UnescapeStr(parts[11]) or ""
        if VM.db.inventory.lastScan == 0 then return end
        if scanTime < (VM.db.inventory.lastScan or 0) then return end
        if not tabIdx then return end

        local resolvedLink = ResolveReceivedItemLink(itemID, rawItemLink, itemName)
        local key = (itemID and itemID ~= 0) and itemID or itemName
        VM.db.inventory.tabs[tabIdx] = VM.db.inventory.tabs[tabIdx] or { name = "Tab " .. tabIdx, isPurchased = true, items = {} }
        local syncItemType = (itemType ~= "") and itemType or nil
        local syncEquipSlot = (equipSlot ~= "") and equipSlot or nil
        if (not syncItemType or not syncEquipSlot) and GetItemInfo then
            local lookup = (rawItemLink ~= "") and rawItemLink or (itemID and itemID ~= 0 and itemID)
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
            link = resolvedLink,
            itemLink = resolvedLink,
            icon = icon,
            ahPrice = ahPrice,
            itemType = syncItemType,
            equipSlot = syncEquipSlot
        }
        MarkDataReceived()
        ScheduleUIRefresh()

    elseif cmd == "REQ" then
        local approvedAt = (#parts >= 17) and (tonumber(parts[17]) or 0) or 0
        local completedAt = (#parts >= 18) and (tonumber(parts[18]) or 0) or 0
        local quotedTotalPrice = (#parts >= 19 and parts[19] ~= "") and tonumber(parts[19]) or nil
        local isGoldRequest = (#parts >= 20) and (tonumber(parts[20]) == 1) or false
        local reason = (#parts >= 21) and UnescapeStr(parts[21]) or ""
        local completedMethod = (#parts >= 22) and UnescapeStr(parts[22]) or ""
        local preparedBy = (#parts >= 23) and UnescapeStr(parts[23]) or ""
        local preparedAt = (#parts >= 24) and (tonumber(parts[24]) or 0) or 0

        local rawItemID = UnescapeStr(parts[4])
        local parsedItemID = isGoldRequest and 0 or (tonumber(rawItemID) or rawItemID)
        local itemName = UnescapeStr(parts[15])
        local rawItemLink = UnescapeStr(parts[16])
        local resolvedLink = isGoldRequest and "GOLD" or ResolveReceivedItemLink(parsedItemID, rawItemLink, itemName)

        local req = {
            id = UnescapeStr(parts[2]),
            requester = UnescapeStr(parts[3]),
            isGoldRequest = isGoldRequest,
            itemID = parsedItemID,
            count = tonumber(parts[5]) or 1,
            tab = tonumber(parts[6]) or 0,
            status = UnescapeStr(parts[7]),
            createdAt = tonumber(parts[8]) or 0,
            updatedAt = tonumber(parts[9]) or 0,
            approvedBy = UnescapeStr(parts[10]),
            approvedAt = approvedAt,
            preparedBy = preparedBy,
            preparedAt = preparedAt,
            fulfilledBy = UnescapeStr(parts[11]),
            completedAt = completedAt,
            completedMethod = completedMethod,
            quotedUnitPrice = tonumber(parts[12]) or 0,
            quotedTotalPrice = quotedTotalPrice,
            priceMode = UnescapeStr(parts[13]),
            pricePercent = tonumber(parts[14]) or 0,
            itemName = itemName,
            itemLink = resolvedLink,
            reason = reason,
        }
        if req.isGoldRequest then
            req.itemLink = "GOLD"
            req.goldAmount = req.quotedTotalPrice or req.quotedUnitPrice or 0
        end

        if req.updatedAt >= recentPeerBroadcasts.reqTs then
            recentPeerBroadcasts.reqTs = req.updatedAt
            recentPeerBroadcasts.reqAt = nowGT
        end

        local existing = VM.db.requests[req.id]
        if not fromOfficer and (existing or req.status ~= "PENDING") then return end
        if not existing or req.updatedAt > (existing.updatedAt or 0) then
            VM.db.requests[req.id] = req
            if VM:IsOfficer() and req.status == "PENDING" and not existing then
                if req.isGoldRequest then
                    VM:Print(string.format("New gold request from |cffffff00%s|r: %s (%s)",
                        req.requester, VM:FormatMoney(req.goldAmount or 0), req.reason or "Guild expense"))
                else
                    VM:Print(string.format("New request from |cffffff00%s|r: %dx %s",
                        req.requester, req.count, req.itemLink or req.itemName))
                end
            end
            if VM.Minimap and VM.Minimap.UpdateBadge then VM.Minimap:UpdateBadge() end
            MarkDataReceived()
            ScheduleUIRefresh()
        end

    elseif cmd == "RULE" then
        local tabIdx = tonumber(parts[2])
        local mode = UnescapeStr(parts[3])
        local pct = tonumber(parts[4]) or 50
        local updatedAt = tonumber(parts[5]) or 0
        local updatedBy = (#parts >= 6) and UnescapeStr(parts[6]) or sender
        local sig = (#parts >= 7) and UnescapeStr(parts[7]) or ""

        if not tabIdx then return end

        if updatedAt >= recentPeerBroadcasts.ruleTs then
            recentPeerBroadcasts.ruleTs = updatedAt
            recentPeerBroadcasts.ruleAt = nowGT
        end

        local cleanBy = updatedBy:match("^[^-]+") or updatedBy
        cleanBy = VM:NormalizeName(cleanBy)

        if cleanBy == "System(TamperReset)" or not VM:IsOfficerName(cleanBy) then
            return
        end

        VM:UpdateRosterCache()
        local normBy = VM:NormalizeName(updatedBy)
        if VM.db.rosterCache and next(VM.db.rosterCache) then
            local rKey = VM:ResolveNameKey(VM.db.rosterCache, normBy)
            local rankIdx = rKey and VM.db.rosterCache[rKey] or nil
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
        MarkDataReceived()
        ScheduleUIRefresh()

    elseif cmd == "MAIN" then
        if not fromOfficer then return end
        local alt = UnescapeStr(parts[2])
        local main = UnescapeStr(parts[3])
        local updatedAt = tonumber(parts[4]) or 0

        if updatedAt >= recentPeerBroadcasts.mainTs then
            recentPeerBroadcasts.mainTs = updatedAt
            recentPeerBroadcasts.mainAt = nowGT
        end

        local existing = VM.db.mains[alt]
        local existingTs = (type(existing) == "table" and existing.updatedAt) or 0
        if alt ~= "" and updatedAt > existingTs then
            VM.db.mains[alt] = { main = main, updatedAt = updatedAt }
            MarkDataReceived()
            ScheduleUIRefresh()
        end

    elseif cmd == "TX" then
        local isNewFormat = (#parts >= 15)
        local rawType = UnescapeStr(parts[3])
        if rawType == "SUMMARY" then return end

        local player = VM:NormalizeName(UnescapeStr(parts[4]))
        local itemID = tonumber(parts[5]) or 0
        local count = tonumber(parts[6]) or 1
        local copper = tonumber(parts[7]) or 0
        local charged = tonumber(parts[8]) or 0
        local timestamp = tonumber(parts[9]) or 0
        local officer = UnescapeStr(parts[10])
        local source = UnescapeStr(parts[11])
        local itemName = UnescapeStr(parts[12])
        local rawItemLink = UnescapeStr(parts[13])
        local deleted = isNewFormat and (tonumber(parts[14]) == 1) or false
        local updatedAt = tonumber(isNewFormat and parts[15] or parts[14]) or timestamp or 0
        local rawSender = (#parts >= 16 and parts[16] ~= "") and VM:NormalizeName(UnescapeStr(parts[16])) or player
        local attributedTo = (#parts >= 17 and parts[17] ~= "") and VM:NormalizeName(UnescapeStr(parts[17])) or player
        local chargedTotalPrice = (#parts >= 18 and parts[18] ~= "") and tonumber(parts[18]) or nil
        local note = (#parts >= 19) and UnescapeStr(parts[19]) or ""
        local priceMode = (#parts >= 20 and parts[20] ~= "") and UnescapeStr(parts[20]) or nil
        local pricePercent = (#parts >= 21 and parts[21] ~= "") and tonumber(parts[21]) or nil
        local tab = (#parts >= 22 and parts[22] ~= "") and tonumber(parts[22]) or nil
        local txId = UnescapeStr(parts[2])

        if updatedAt >= recentPeerBroadcasts.txTs then
            recentPeerBroadcasts.txTs = updatedAt
            recentPeerBroadcasts.txAt = nowGT
        end

        if copper == 0 and charged > 0 and (rawItemLink == "GOLD" or rawType:find("GOLD")) then
            copper = charged
        end

        local isGold = (rawItemLink == "GOLD" or rawItemLink:find("GOLD"))
            or (itemID == 0 and (copper > 0 or rawType:find("GOLD") or txId:find("^GOLD") or source:find("GOLD") or source == "BANK_MONEY_LOG" or source == "MANUAL_ASSIGN_PAYMENT" or source == "GOLD_REQUEST" or source == "TAB_PURCHASE" or source == "GUILD_EXPENSE"))
            or (txId:find("^GOLD_"))
            or (rawType:find("GOLD"))

        local txType = rawType
        local itemLink = rawItemLink
        if isGold then
            itemID = 0
            itemLink = "GOLD"
            if rawType:find("OUT") or txId:find("^GOLD_OUT") or source:find("OUT") or source == "GOLD_REQUEST" or source == "TAB_PURCHASE" or source == "GUILD_EXPENSE" or source == "WRITE_OFF" then
                txType = "OUT"
                if itemName == "" or itemName == "Gold Deposit" then itemName = "Gold Withdrawal" end
            else
                txType = "IN"
                if itemName == "" or itemName == "Gold Withdrawal" then itemName = "Gold Deposit" end
            end
        elseif rawType == "GOLD_IN" or (itemID == 0 and rawType == "IN" and (source == "BANK_MONEY_LOG" or rawItemLink == "GOLD")) then
            txType = "IN"
            itemLink = "GOLD"
            isGold = true
        elseif rawType == "GOLD_OUT" or (itemID == 0 and rawType == "OUT" and (source == "BANK_MONEY_LOG" or rawItemLink == "GOLD")) then
            txType = "OUT"
            itemLink = "GOLD"
            isGold = true
        else
            itemLink = ResolveReceivedItemLink(itemID, rawItemLink, itemName)
        end

        local isFFA = nil
        if #parts >= 23 and parts[23] ~= "" then
            isFFA = (tonumber(parts[23]) == 1)
        elseif isGold then
            isFFA = false
        end

        local guildCategory = nil
        if #parts >= 24 and parts[24] ~= "" then
            local rawCat = UnescapeStr(parts[24])
            guildCategory = (VM.Ledger and VM.Ledger.NormalizeGuildCategory) and VM.Ledger:NormalizeGuildCategory(rawCat) or rawCat
        end

        if (source == "GOLD_REQUEST" or source == "WRITE_OFF" or source == "GUILD_EXPENSE") and not fromOfficer then return end
        if not fromOfficer and not isGold and (source ~= "BANK_LOG" and source ~= "BANK_MONEY_LOG" and source ~= "TAB_PURCHASE" and source ~= "FFA_SCAN" and source ~= "GOLD_IN" and source ~= "GOLD_OUT" and source ~= "MANUAL_GOLD" and itemLink ~= "GOLD") then
            return
        end

        if not deleted and VM.Ledger and VM.Ledger.HasCompactedMonth and VM.Ledger:HasCompactedMonth(player, timestamp) then
            return
        end

        local tx = {
            id = txId,
            type = txType,
            player = player,
            itemID = itemID,
            count = count,
            unitPriceAtTime = copper,
            chargedUnitPrice = charged,
            chargedTotalPrice = chargedTotalPrice,
            priceMode = priceMode,
            pricePercent = pricePercent,
            tab = tab,
            note = note,
            guildCategory = guildCategory,
            timestamp = timestamp,
            officer = officer,
            source = source,
            itemName = itemName,
            itemLink = itemLink,
            deleted = deleted,
            updatedAt = updatedAt,
            rawSender = rawSender,
            attributedTo = attributedTo,
            isFFA = isFFA,
            isManual = (source == "MANUAL_GOLD" or source == "MANUAL" or source == "MANUAL_ASSIGN" or source == "GUILD_EXPENSE")
        }
        local existing = VM.db.ledger[tx.id]

        -- Deduplicate automatic bank-log transactions across clients that generated different IDs
        if not existing and not PROTECTED_TX_SOURCES[source or ""] then
            local txAction = VM:NormalizeAction(tx.type)
            local txActor = VM:NormalizeActor(tx.rawSender or tx.player)
            local WINDOW_48H = 172800

            if isGold then
                local txCopper = (tx.unitPriceAtTime or 0) * (tx.count or 1)
                for _, exTx in pairs(VM.db.ledger) do
                    if not exTx.deleted and not PROTECTED_TX_SOURCES[exTx.source or ""] then
                        local exIsGold = (exTx.itemID == 0 or exTx.itemLink == "GOLD" or exTx.source == "BANK_MONEY_LOG" or (exTx.itemName and (exTx.itemName:find("Gold Deposit") or exTx.itemName:find("Gold Withdrawal"))))
                        if exIsGold then
                            local exAction = VM:NormalizeAction(exTx.type)
                            local exActor = VM:NormalizeActor(exTx.rawSender or exTx.player)
                            local exCopper = (exTx.unitPriceAtTime or 0) * (exTx.count or 1)
                            if txAction == exAction and (txActor == exActor or (tx.rawSender and VM:NormalizeActor(tx.rawSender) == exActor) or (exTx.rawSender and VM:NormalizeActor(exTx.rawSender) == txActor)) and txCopper == exCopper then
                                if math.abs((exTx.timestamp or 0) - (tx.timestamp or 0)) <= WINDOW_48H then
                                    existing = exTx
                                    tx.id = exTx.id
                                    if (exTx.timestamp or 0) > 0 and ((tx.timestamp or 0) == 0 or exTx.timestamp < tx.timestamp) then
                                        tx.timestamp = exTx.timestamp
                                    end
                                    break
                                end
                            end
                        end
                    end
                end
            else
                local txItemKey = VM:NormalizeItemKey(tx.itemID, tx.itemLink, tx.itemName)
                local txCount = tonumber(tx.count or 1)
                for _, exTx in pairs(VM.db.ledger) do
                    if not exTx.deleted and not PROTECTED_TX_SOURCES[exTx.source or ""] then
                        local exIsGold = (exTx.itemID == 0 or exTx.itemLink == "GOLD" or exTx.source == "BANK_MONEY_LOG")
                        if not exIsGold then
                            local exAction = VM:NormalizeAction(exTx.type)
                            local exActor = VM:NormalizeActor(exTx.rawSender or exTx.player)
                            local exItemKey = VM:NormalizeItemKey(exTx.itemID, exTx.itemLink, exTx.itemName)
                            local exCount = tonumber(exTx.count or 1)
                            if txAction == exAction and txActor == exActor and txItemKey == exItemKey and txCount == exCount then
                                if math.abs((exTx.timestamp or 0) - (tx.timestamp or 0)) <= WINDOW_48H then
                                    existing = exTx
                                    tx.id = exTx.id
                                    if (exTx.timestamp or 0) > 0 and ((tx.timestamp or 0) == 0 or exTx.timestamp < tx.timestamp) then
                                        tx.timestamp = exTx.timestamp
                                    end
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Also deduplicate TAB_PURCHASE by copper amount within 48h across clients
        if not existing and source == "TAB_PURCHASE" then
            local txCopper = (tx.unitPriceAtTime or 0) * (tx.count or 1)
            for _, exTx in pairs(VM.db.ledger) do
                if not exTx.deleted and exTx.source == "TAB_PURCHASE" then
                    local exCopper = (exTx.unitPriceAtTime or 0) * (exTx.count or 1)
                    if exCopper == txCopper and math.abs((exTx.timestamp or 0) - (tx.timestamp or 0)) <= 172800 then
                        existing = exTx
                        tx.id = exTx.id
                        if (exTx.timestamp or 0) > 0 and ((tx.timestamp or 0) == 0 or exTx.timestamp < tx.timestamp) then
                            tx.timestamp = exTx.timestamp
                        end
                        break
                    end
                end
            end
        end

        if existing and existing.unitPriceAtTime and existing.unitPriceAtTime > 0 and (tx.itemLink == "GOLD" or tx.itemID == 0) then
            tx.unitPriceAtTime = existing.unitPriceAtTime
        end
        if tx.id ~= "" and (not existing or tx.updatedAt > (existing.updatedAt or existing.timestamp or 0)) then
            VM.db.ledger[tx.id] = tx
            MarkDataReceived()
            ScheduleUIRefresh()
        end
    end
end

function Comms:BroadcastInventory()
    local inv = VM.db.inventory
    if not inv or not inv.lastScan or inv.lastScan == 0 then return end
    local maxLen = GetMaxPayloadLen()
    local scanBy = inv.lastScanBy or inv.scannedBy or UnitName("player")
    local gold = math.floor(tonumber(inv.gold) or 0)
    local numTabs = math.floor(tonumber(inv.numTabs) or 1)
    self:SendRaw(string.format("INV_META|%d|%s|%d|%d", math.floor(inv.lastScan), EscapeStr(scanBy), gold, numTabs))
    for tabIdx, tabData in pairs(inv.tabs or {}) do
        local isPurchased = (tabData.isPurchased ~= false) and 1 or 0
        self:SendRaw(string.format("INV_TAB|%d|%d|%s|%s|%d",
            math.floor(inv.lastScan), tonumber(tabIdx) or 1, EscapeStr(tabData.name), EscapeStr(tabData.icon), isPurchased))
        if isPurchased == 1 then
            for _, item in pairs(tabData.items or {}) do
                local itemIDNum = math.floor(tonumber(item.itemID) or 0)
                local function BuildInvItem(linkStr)
                    return string.format("INV_ITEM|%d|%d|%d|%d|%s|%s|%s|%d|%s|%s",
                        math.floor(inv.lastScan), tonumber(tabIdx) or 1,
                        itemIDNum, math.floor(tonumber(item.count) or 1),
                        EscapeStr(item.name), EscapeStr(linkStr), EscapeStr(item.icon),
                        math.floor(tonumber(item.ahPrice) or 0),
                        EscapeStr(item.itemType or ""), EscapeStr(item.equipSlot or ""))
                end
                local payload = BuildInvItem(item.link or "")
                if #payload > maxLen and itemIDNum > 0 then
                    payload = BuildInvItem("")
                end
                self:SendRaw(payload)
            end
        end
    end
end

function Comms:BroadcastRequest(req)
    if not req then return end
    if not req.isGoldRequest and (not VM.db.inventory or (VM.db.inventory.lastScan or 0) == 0) then
        return
    end
    local maxLen = GetMaxPayloadLen()
    local qTotalStr = (req.quotedTotalPrice ~= nil) and tostring(math.floor(tonumber(req.quotedTotalPrice) or 0)) or ""
    local isGoldVal = req.isGoldRequest and 1 or 0
    local numItemID = tonumber(req.itemID) or 0

    local function BuildReqPayload(linkStr, reasonStr)
        return string.format("REQ|%s|%s|%s|%d|%d|%s|%d|%d|%s|%s|%d|%s|%d|%s|%s|%d|%d|%s|%d|%s|%s|%s|%d",
            EscapeStr(req.id),
            EscapeStr(req.requester),
            EscapeStr(tostring(req.itemID or 0)),
            math.floor(tonumber(req.count) or 1),
            math.floor(tonumber(req.tab) or 0),
            EscapeStr(req.status),
            math.floor(tonumber(req.createdAt) or 0),
            math.floor(tonumber(req.updatedAt) or 0),
            EscapeStr(req.approvedBy or ""),
            EscapeStr(req.fulfilledBy or ""),
            math.floor(tonumber(req.quotedUnitPrice) or 0),
            EscapeStr(req.priceMode or ""),
            math.floor(tonumber(req.pricePercent) or 0),
            EscapeStr(req.itemName or ""),
            EscapeStr(linkStr),
            math.floor(tonumber(req.approvedAt) or 0),
            math.floor(tonumber(req.completedAt) or 0),
            qTotalStr,
            isGoldVal,
            EscapeStr(reasonStr),
            EscapeStr(req.completedMethod or ""),
            EscapeStr(req.preparedBy or ""),
            math.floor(tonumber(req.preparedAt) or 0))
    end

    local linkStr = req.itemLink or ""
    local reasonStr = req.reason or ""
    local payload = BuildReqPayload(linkStr, reasonStr)

    if #payload > maxLen and not req.isGoldRequest and numItemID > 0 and linkStr ~= "" then
        linkStr = ""
        payload = BuildReqPayload(linkStr, reasonStr)
    end
    while #payload > maxLen and #reasonStr > 0 do
        reasonStr = reasonStr:sub(1, math.max(0, #reasonStr - 4))
        payload = BuildReqPayload(linkStr, reasonStr)
    end

    self:SendRaw(payload)
end

function Comms:BroadcastTabRules(sinceTs)
    if not VM.db or not VM.db.tabRules then return end
    local minTs = tonumber(sinceTs) or 0
    local guildName = GetGuildInfo("player") or VM:GetActiveGuildKey() or ""
    for tabIdx, rule in pairs(VM.db.tabRules) do
        if rule and not rule.tampered and (minTs == 0 or (rule.updatedAt or 0) > minTs) then
            local uBy = rule.updatedBy or VM:GetPlayerName()
            local sig = rule.sig or VM:ComputeRuleSignature(guildName, tabIdx, rule)
            rule.sig = sig
            self:SendRaw(string.format("RULE|%d|%s|%d|%d|%s|%s",
                tonumber(tabIdx) or 1, EscapeStr(rule.mode), math.floor(tonumber(rule.percent) or 50),
                math.floor(tonumber(rule.updatedAt) or 0), EscapeStr(uBy), EscapeStr(sig)))
        end
    end
end

function Comms:BroadcastMains(sinceTs)
    local minTs = tonumber(sinceTs) or 0
    for alt, entry in pairs(VM.db.mains or {}) do
        local main = type(entry) == "table" and entry.main or entry
        local ts = type(entry) == "table" and entry.updatedAt or 0
        if minTs == 0 or ts > minTs then
            self:SendRaw(string.format("MAIN|%s|%s|%d", EscapeStr(alt), EscapeStr(main), math.floor(ts)))
        end
    end
end

function Comms:BroadcastTransaction(tx)
    if not tx or tx.type == "SUMMARY" or tx.isDerived then return end
    local inv = VM.db.inventory
    if not inv or not inv.lastScan or inv.lastScan == 0 then
        local now = (GetServerTime and GetServerTime()) or time()
        VM.db.inventory = VM.db.inventory or { gold = 0, tabs = {} }
        VM.db.inventory.lastScan = now
        VM.db.inventory.lastScanTime = now
        VM.db.inventory.lastScanBy = UnitName("player") or VM:GetPlayerName()
        VM.db.inventory.scannedBy = VM.db.inventory.lastScanBy
    end

    local maxLen = GetMaxPayloadLen()
    local delVal = tx.deleted and 1 or 0
    local cTotalStr = (tx.chargedTotalPrice ~= nil) and tostring(math.floor(tonumber(tx.chargedTotalPrice) or 0)) or ""
    local pPctStr = (tx.pricePercent ~= nil) and tostring(math.floor(tonumber(tx.pricePercent) or 0)) or ""
    local tabStr = (tx.tab ~= nil) and tostring(math.floor(tonumber(tx.tab) or 0)) or ""
    local ffaStr = (tx.isFFA == true and "1") or (tx.isFFA == false and "0") or ""
    local guildCatStr = tostring(tx.guildCategory or "")
    local numItemID = tonumber(tx.itemID) or 0

    local function BuildTxPayload(linkStr, noteStr)
        return string.format("TX|%s|%s|%s|%s|%d|%d|%d|%d|%s|%s|%s|%s|%d|%d|%s|%s|%s|%s|%s|%s|%s|%s|%s",
            EscapeStr(tx.id),
            EscapeStr(tx.type),
            EscapeStr(tx.player),
            EscapeStr(tostring(tx.itemID or 0)),
            math.floor(tonumber(tx.count) or 1),
            math.floor(tonumber(tx.unitPriceAtTime) or 0),
            math.floor(tonumber(tx.chargedUnitPrice) or 0),
            math.floor(tonumber(tx.timestamp) or 0),
            EscapeStr(tx.officer or ""),
            EscapeStr(tx.source or ""),
            EscapeStr(tx.itemName or ""),
            EscapeStr(linkStr),
            delVal,
            math.floor(tonumber(tx.updatedAt or tx.timestamp) or 0),
            EscapeStr(tx.rawSender or tx.player or ""),
            EscapeStr(tx.attributedTo or tx.player or ""),
            cTotalStr,
            EscapeStr(noteStr),
            EscapeStr(tx.priceMode or ""),
            pPctStr,
            tabStr,
            ffaStr,
            EscapeStr(guildCatStr))
    end

    local linkStr = tx.itemLink or ""
    local noteStr = tx.note or ""
    local payload = BuildTxPayload(linkStr, noteStr)

    if #payload > maxLen and numItemID > 0 and linkStr ~= "" and linkStr ~= "GOLD" then
        linkStr = ""
        payload = BuildTxPayload(linkStr, noteStr)
    end
    while #payload > maxLen and #noteStr > 0 do
        noteStr = noteStr:sub(1, math.max(0, #noteStr - 4))
        payload = BuildTxPayload(linkStr, noteStr)
    end

    self:SendRaw(payload)
end

function Comms:BroadcastLedgerSync(sinceTs)
    if not VM.db or not VM.db.ledger then return end
    local minTs = tonumber(sinceTs) or 0
    local cutoff = time() - (60 * 86400)
    for _, tx in pairs(VM.db.ledger) do
        if tx and tx.type ~= "SUMMARY" and not tx.isDerived then
            local upd = tx.updatedAt or tx.timestamp or 0
            if upd > cutoff and (minTs == 0 or upd > minTs) then
                self:BroadcastTransaction(tx)
            end
        end
    end
end
