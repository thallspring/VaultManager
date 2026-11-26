local _, VM = ...
VM.Comms = {}
local Comms = VM.Comms

local MSG_QUEUE = {}
local THROTTLE_INTERVAL = 0.35
local elapsedSinceSend = 0

local uiRefreshNeeded = false
local uiRefreshTimer = 0
local UI_REFRESH_DEBOUNCE = 0.35

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
}

local function EscapeStr(s)
    return tostring(s or ""):gsub("%%", "%%25"):gsub("|", "%%7C"):gsub("\n", "%%0A"):gsub("\r", "")
end

local function UnescapeStr(s)
    return tostring(s or ""):gsub("%%0A", "\n"):gsub("%%7C", "|"):gsub("%%25", "%%")
end

local function ScheduleUIRefresh()
    uiRefreshNeeded = true
    uiRefreshTimer = UI_REFRESH_DEBOUNCE
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
            if C_Timer and C_Timer.After then
                C_Timer.After(4, function()
                    if IsInGuild() then
                        self:SendHello()
                    end
                end)
            elseif IsInGuild() then
                self:SendHello()
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
            Comms:Broadcast
