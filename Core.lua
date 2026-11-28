local ADDON_NAME, VM = ...
_G.VaultManager = VM

VM.PREFIX = "VMGR_V1"
VM.VERSION = 7
-- Development build marker (the .toc version stays at the last release until in-game tests pass)
VM.BUILD = "1.5.0-dev.8 (2026-11-28)"
VM.OFFICER_MAX_RANK_INDEX = 1
-- Admin ranks (by index, never by name): 0 = Guild Master, 1 = the guild's built-in officer rank.
-- Only admin ranks may change Vault Manager configuration (officer ranks, tab rules, guild reset).
VM.ADMIN_MAX_RANK_INDEX = 1
-- Monthly compaction is paused until P2P ledger state is stable across clients (tombstone purge still runs)
VM.COMPACTION_ENABLED = false
VM.debugLog = {}
VM.pendingTradePayments = {}

function VM:LogDebug(msg)
    local line = string.format("[%s] %s", date("%H:%M:%S"), tostring(msg or ""))
    table.insert(VM.debugLog, line)
    if #VM.debugLog > 50 then
        table.remove(VM.debugLog, 1)
    end
end

local DEFAULT_UI_PREFS = {
    useHistoricalPrices = false,
    showLockedPrices = false,
    rankingPriceMode = "live",
    hideOfficers = false,
    showLegacyRanking = true,
    hideLegacyLedger = false,
    rankingPeriod = "ALL",
    rankingSortBy = "net",
    rankingSortDir = "desc",
    enableChatNotifications = true,
    notifyNewerVersion = true,
    autoOpenAtBank = true,
    memberWhispers = true,
    autoFillNextMail = true,
}

function VM:Print(msg)
    local prefs = self.db and self.db.uiPrefs
    if prefs and prefs.enableChatNotifications == false then
        return
    end
    print(string.format("|cff00ccff[Vault Manager]|r %s", tostring(msg)))
end

function VM:GetAddonVersion()
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local ver = getMeta and getMeta("VaultManager", "Version")
    if not ver or ver == "" then
        ver = "1.4.3"
    end
    ver = tostring(ver):gsub("^[vV]", ""):gsub("^%s*(.-)%s*$", "%1")
    return ver
end

function VM:ParseSemVer(verStr)
    if not verStr then return 0, 0, 0 end
    local clean = tostring(verStr):gsub("^[vV]", "")
    local nums = {}
    for n in clean:gmatch("%d+") do
        table.insert(nums, tonumber(n) or 0)
    end
    return nums[1] or 0, nums[2] or 0, nums[3] or 0
end

function VM:CompareVersions(v1, v2)
    local maj1, min1, pat1 = self:ParseSemVer(v1)
    local maj2, min2, pat2 = self:ParseSemVer(v2)
    if maj1 ~= maj2 then
        return (maj1 > maj2) and 1 or -1
    end
    if min1 ~= min2 then
        return (min1 > min2) and 1 or -1
    end
    if pat1 ~= pat2 then
        return (pat1 > pat2) and 1 or -1
    end
    return 0
end

function VM:IsNewerVersion(remoteVer, localVer)
    return self:CompareVersions(remoteVer, localVer) > 0
end

local function InitGuildSubTables(db)
    if not db then return end
    db.uiPrefs = db.uiPrefs or {}
    for k, v in pairs(DEFAULT_UI_PREFS) do
        if db.uiPrefs[k] == nil then
            db.uiPrefs[k] = v
        end
    end
    db.minimap = db.minimap or { angle = 220, hide = false }
    if db.minimap.angle == nil then db.minimap.angle = 220 end
    if db.minimap.hide == nil then db.minimap.hide = false end

    db.inventory = db.inventory or { lastScan = 0, scannedBy = "", gold = 0, tabs = {} }
    if db.inventory.gold == nil then db.inventory.gold = 0 end
    db.vault = db.vault or db.inventory
    db.ledger = db.ledger or {}
    db.requests = db.requests or {}
    db.fulfillments = db.fulfillments or db.requests
    db.mains = db.mains or {}
    db.roster = db.roster or db.mains
    db.rosterCache = db.rosterCache or {}
    db.memberClasses = db.memberClasses or {}
    db.rankNames = db.rankNames or {}
    db.archivedMembers = db.archivedMembers or {}
    db.tabRules = db.tabRules or {}
    db.scanMetadata = db.scanMetadata or db.inventory
    db.processedBankLogs = db.processedBankLogs or {}
    db.dbEpoch = db.dbEpoch or 1
    return db
end
VM.InitGuildSubTables = InitGuildSubTables

VM.CLASS_COLORS = {
    WARRIOR = "C79C6E",
    PALADIN = "F58CBA",
    HUNTER = "ABD473",
    ROGUE = "FFF569",
    PRIEST = "FFFFFF",
    SHAMAN = "0070DE",
    MAGE = "69CCF0",
    WARLOCK = "9482C9",
    DRUID = "FF7D0A",
    DEATHKNIGHT = "C41F3B",
    MONK = "00FF96",
    DEMONHUNTER = "A330C9",
    EVOKER = "33937F",
}

function VM:NormalizeClassToken(classStr)
    if not classStr or classStr == "" then return nil end
    local upper = strupper(tostring(classStr)):gsub("%s+", "")
    if self.CLASS_COLORS[upper] or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[upper]) then
        return upper
    end
    local lowerIn = tostring(classStr):lower()
    if LOCALIZED_CLASS_NAMES_MALE then
        for token, locName in pairs(LOCALIZED_CLASS_NAMES_MALE) do
            if type(locName) == "string" and locName:lower() == lowerIn then
                return strupper(token):gsub("%s+", "")
            end
        end
    end
    if LOCALIZED_CLASS_NAMES_FEMALE then
        for token, locName in pairs(LOCALIZED_CLASS_NAMES_FEMALE) do
            if type(locName) == "string" and locName:lower() == lowerIn then
                return strupper(token):gsub("%s+", "")
            end
        end
    end
    return upper
end

function VM:GetHexForClassToken(token)
    if not token or token == "" then return nil end
    local normToken = self:NormalizeClassToken(token)
    if not normToken then return nil end
    if self.CLASS_COLORS[normToken] then
        return self.CLASS_COLORS[normToken]
    end
    if RAID_CLASS_COLORS and RAID_CLASS_COLORS[normToken] then
        local c = RAID_CLASS_COLORS[normToken]
        if c.colorStr and type(c.colorStr) == "string" and #c.colorStr >= 8 then
            return c.colorStr:sub(3, 8)
        elseif c.r and c.g and c.b then
            return string.format("%02X%02X%02X",
                math.floor(c.r * 255 + 0.5),
                math.floor(c.g * 255 + 0.5),
                math.floor(c.b * 255 + 0.5))
        end
    end
    return nil
end

-- Generic name key resolver: exact match -> case-insensitive exact -> unambiguous first-word match
function VM:ResolveNameKey(tbl, charName)
    if type(tbl) ~= "table" then return nil end
    local norm = self:NormalizeName(charName)
    if norm == "" or norm == "GUILD" or norm == "UNATTRIBUTED" then return nil end
    if tbl[norm] ~= nil then return norm end

    local normLower = norm:lower()
    for k in pairs(tbl) do
        if type(k) == "string" and k:lower() == normLower then
            return k
        end
    end

    -- First-word fallback (for servers with two-word character names where logs only record the first name)
    if not norm:find("%s") then
        local prefix = normLower .. " "
        local prefixLen = #prefix
        local matchedKey = nil
        local matchCount = 0
        for k in pairs(tbl) do
            if type(k) == "string" then
                local kl = k:lower()
                if #kl > prefixLen and kl:sub(1, prefixLen) == prefix then
                    matchedKey = k
                    matchCount = matchCount + 1
                    if matchCount > 1 then
                        return nil -- Ambiguous first name
                    end
                end
            end
        end
        if matchCount == 1 then
            return matchedKey
        end
    end

    return nil
end

function VM:GetClassHex(charName)
    local norm = self:NormalizeName(charName)
    if norm == "" or norm == "GUILD" or norm == "UNATTRIBUTED" then return nil end
    local classes = self.db and self.db.memberClasses
    if classes then
        local key = self:ResolveNameKey(classes, norm)
        if key then
            local hex = self:GetHexForClassToken(classes[key])
            if hex then return hex end
        end
    end
    if IsInGuild() and GetNumGuildMembers then
        local normLower = norm:lower()
        local allowPrefix = not norm:find("%s")
        local prefix = normLower .. " "
        local prefixLen = #prefix
        local total = GetNumGuildMembers() or 0
        local prefixToken, prefixCount = nil, 0

        for i = 1, total do
            local rName, _, _, _, rClass, _, _, _, _, _, rClassFile = GetGuildRosterInfo(i)
            if rName then
                local rNorm = self:NormalizeName(rName)
                local rLower = rNorm:lower()
                local token = (rClassFile and rClassFile ~= "") and self:NormalizeClassToken(rClassFile) or self:NormalizeClassToken(rClass)
                if rLower == normLower then
                    local hex = self:GetHexForClassToken(token)
                    if hex then
                        if self.db then
                            self.db.memberClasses = self.db.memberClasses or {}
                            self.db.memberClasses[rNorm] = token
                        end
                        return hex
                    end
                    return nil
                elseif allowPrefix and #rLower > prefixLen and rLower:sub(1, prefixLen) == prefix then
                    prefixToken = token
                    prefixCount = prefixCount + 1
                end
            end
        end

        if prefixCount == 1 and prefixToken then
            return self:GetHexForClassToken(prefixToken)
        end
    end
    return nil
end

function VM:ColorizeName(charName, fallbackHex)
    if not charName or charName == "" then return "" end
    local hex = self:GetClassHex(charName)
    if hex then
        return string.format("|cff%s%s|r", hex, charName)
    elseif fallbackHex then
        return string.format("|cff%s%s|r", fallbackHex, charName)
    else
        return charName
    end
end

VM.db = InitGuildSubTables({})

local DEFAULT_DB = {
    dbEpoch = 1,
    guilds = {},
    charGuilds = {},
    uiPrefs = {
        useHistoricalPrices = false,
        rankingPriceMode = "live",
        hideOfficers = false,
        rankingPeriod = "ALL",
        autoOpenAtBank = true,
    }
}

local function DeepCopyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            DeepCopyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

function VM:NormalizeName(name)
    if not name or name == "" then return "" end
    local clean = strtrim(strsplit("-", name))
    if clean == "" then return "" end
    local upper = clean:upper()
    if upper == "GUILD" then return "GUILD" end
    if upper == "UNATTRIBUTED" then return "UNATTRIBUTED" end
    return clean:sub(1, 1):upper() .. clean:sub(2)
end

function VM:NormalizeActor(name)
    if not name or name == "" then return "UNATTRIBUTED" end
    local n = self:NormalizeName(name)
    if n == "" or n == "UNATTRIBUTED" then return "UNATTRIBUTED" end
    return n
end

function VM:NormalizeAction(actionOrType)
    local s = tostring(actionOrType or ""):upper()
    if s:find("OUT") or s:find("WITHDRAW") or s == "2" then
        return "OUT"
    end
    return "IN"
end

function VM:NormalizeItemKey(itemID, itemLink, itemName)
    local id = tonumber(itemID) or 0
    if id == 0 and itemLink and type(itemLink) == "string" then
        id = tonumber(itemLink:match("item:(%d+)")) or 0
    end
    local name = ""
    if itemName and type(itemName) == "string" and itemName ~= "" and not itemName:find("^Item %d+$") then
        name = itemName:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%[", ""):gsub("%]$", ""):match("^%s*(.-)%s*$")
    end
    if (not name or name == "") and itemLink and type(itemLink) == "string" then
        name = itemLink:match("%[(.-)%]")
        if name then
            name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
        end
    end
    if (not name or name == "") and id > 0 and GetItemInfo then
        local n = GetItemInfo(id)
        if n and n ~= "" then name = n end
    end
    if name and name ~= "" and name:lower() ~= "unknown item" and name:lower() ~= "unknown" then
        return "NAME:" .. name:lower()
    elseif id > 0 then
        return "ID:" .. id
    else
        return "ID:0"
    end
end

-- Canonical actor key for log deduplication: resolves first-word log/UnitName variants
-- (e.g. "Thallock" vs "Thallock Dotcom") to the guild roster name when unambiguous.
function VM:CanonicalActor(name)
    local n = self:NormalizeActor(name)
    if n == "UNATTRIBUTED" or n == "GUILD" then return n end
    local cache = self.db and self.db.rosterCache
    if cache and next(cache) then
        local key = self:ResolveNameKey(cache, n)
        if key then return key end
    end
    return n
end

-- Loose character comparison: exact, case-insensitive, or first-word vs two-word name
function VM:IsSameCharacter(a, b)
    local na, nb = self:NormalizeName(a), self:NormalizeName(b)
    if na == "" or nb == "" then return false end
    local la, lb = na:lower(), nb:lower()
    if la == lb then return true end
    if not la:find("%s") and lb:sub(1, #la + 1) == (la .. " ") then return true end
    if not lb:find("%s") and la:sub(1, #lb + 1) == (lb .. " ") then return true end
    return self:CanonicalActor(na) == self:CanonicalActor(nb)
end

function VM:GetTxMatchKey(tx)
    if not tx then return "" end
    local isGold = (tx.itemID == 0 or tx.itemLink == "GOLD" or tx.source == "BANK_MONEY_LOG" or tx.source == "MANUAL_GOLD" or (tx.itemName and (tx.itemName:find("Gold Deposit") or tx.itemName:find("Gold Withdrawal"))))
    local action = self:NormalizeAction(tx.type)
    local actor = self:CanonicalActor(tx.rawSender or tx.player)
    if isGold then
        local copper = (tx.unitPriceAtTime or 0) * (tx.count or 1)
        return string.format("GOLD:%s:%s:%d", action, actor, copper)
    else
        local itemKey = self:NormalizeItemKey(tx.itemID, tx.itemLink, tx.itemName)
        local count = tonumber(tx.count or 1)
        return string.format("ITEM:%s:%s:%s:%d", action, actor, itemKey, count)
    end
end

function VM:GetPlayerName()
    return self:NormalizeName(UnitName("player"))
end

-- Single source of truth for officer ranks (used locally, for peers, for tab rules and P2P trust).
-- Guild Master (rank 0) is always an officer. Other ranks come from the guild-wide officer rank
-- setting (Settings > Officer Ranks, synced between officers); default = ranks 0 and 1.
function VM:IsAdminRank(rankIndex)
    return type(rankIndex) == "number" and rankIndex >= 0 and rankIndex <= VM.ADMIN_MAX_RANK_INDEX
end

function VM:IsAdmin()
    if not IsInGuild() then return false end
    local _, _, rankIndex = GetGuildInfo("player")
    if self:IsAdminRank(rankIndex) then return true end
    return (IsGuildLeader and IsGuildLeader()) and true or false
end

function VM:IsOfficerRank(rankIndex)
    if type(rankIndex) ~= "number" or rankIndex < 0 then return false end
    -- Admin ranks are always officers; delegated ranks come from the admin-managed setting
    if self:IsAdminRank(rankIndex) then return true end
    local cfg = self.db and self.db.officerRanks
    if type(cfg) == "table" and type(cfg.ranks) == "table" then
        return cfg.ranks[rankIndex] == true
    end
    return rankIndex <= VM.OFFICER_MAX_RANK_INDEX
end

-- Guild ranks as { index = 0.., name = "..." } (index 0 = Guild Master)
function VM:GetGuildRankList()
    local list = {}
    local num = (GuildControlGetNumRanks and GuildControlGetNumRanks()) or 0
    if num <= 0 and self.db and self.db.rankNames then
        for idx in pairs(self.db.rankNames) do
            if type(idx) == "number" and idx + 1 > num then num = idx + 1 end
        end
    end
    for i = 0, math.max(0, num - 1) do
        local name = (self.db and self.db.rankNames and self.db.rankNames[i]) or nil
        if (not name or name == "") and GuildControlGetRankName then
            local ok, n = pcall(GuildControlGetRankName, i + 1)
            if ok and n and n ~= "" then name = n end
        end
        table.insert(list, { index = i, name = name or ("Rank " .. i) })
    end
    return list
end

-- Admin (Guild Master / built-in officer rank): choose which additional ranks get officer functions
-- (e.g. "Raid Leader", "Officer Alt"). Delegated ranks can never change this setting themselves.
function VM:SetOfficerRank(rankIndex, isOfficer)
    if type(rankIndex) ~= "number" or self:IsAdminRank(rankIndex) then return end
    if not self:IsAdmin() then
        self:Print("|cffff4444Only the Guild Master and the guild's officer rank can change officer ranks.|r")
        return
    end
    local ranks = {}
    for _, r in ipairs(self:GetGuildRankList()) do
        if not self:IsAdminRank(r.index) and self:IsOfficerRank(r.index) then ranks[r.index] = true end
    end
    ranks[rankIndex] = isOfficer and true or nil
    self.db.officerRanks = { ranks = ranks, updatedAt = time(), updatedBy = self:GetPlayerName() }
    if self.Comms and self.Comms.BroadcastOfficerRanks then self.Comms:BroadcastOfficerRanks() end
    self:ValidateTabRules()
    if self.UI then self.UI:RefreshAll() end
end

function VM:IsOfficer()
    if not IsInGuild() then return false end
    local _, _, rankIndex = GetGuildInfo("player")
    if self:IsOfficerRank(rankIndex) then
        return true
    end
    if IsGuildLeader and IsGuildLeader() then
        return true
    end
    return false
end

-- Guild rank index of a character (roster cache, then live roster incl. first-word match); nil if unknown
function VM:GetRankIndexForName(name)
    local norm = self:NormalizeName(name)
    if norm == "" or norm == "GUILD" or norm == "UNATTRIBUTED" then return nil end

    local key = self:ResolveNameKey(self.db.rosterCache, norm)
    local rankIndex = key and self.db.rosterCache[key] or nil
    if type(rankIndex) == "number" then return rankIndex end

    if IsInGuild() and GetNumGuildMembers then
        local total = GetNumGuildMembers() or 0
        local normLower = norm:lower()
        local allowPrefix = not norm:find("%s")
        local prefix = normLower .. " "
        local prefixLen = #prefix
        local prefixRank, prefixCount = nil, 0

        for i = 1, total do
            local rName, _, rIndex = GetGuildRosterInfo(i)
            if rName then
                local rNorm = self:NormalizeName(rName)
                local rLower = rNorm:lower()
                if rLower == normLower then
                    self.db.rosterCache[rNorm] = rIndex or 99
                    return rIndex
                elseif allowPrefix and #rLower > prefixLen and rLower:sub(1, prefixLen) == prefix then
                    prefixRank = rIndex
                    prefixCount = prefixCount + 1
                end
            end
        end
        if prefixCount == 1 and type(prefixRank) == "number" then
            return prefixRank
        end
    end
    return nil
end

function VM:IsOfficerName(name)
    return self:IsOfficerRank(self:GetRankIndexForName(name))
end

function VM:IsGuildMaster()
    if not IsInGuild() then return false end
    local _, _, rankIndex = GetGuildInfo("player")
    if rankIndex == 0 then return true end
    return (IsGuildLeader and IsGuildLeader()) and true or false
end

function VM:IsGuildMasterName(name)
    return self:GetRankIndexForName(name) == 0
end

--------------------------------------------------------------------------------
-- Guild-wide data reset (two-step: an admin requests, the Guild Master approves)
-- Data only (ledger, requests, vault cache, pending CoD); configuration (tab rules, officer ranks,
-- alt links) is kept. Everything is rebuilt from the visible Guild Bank logs on the next scan.
--------------------------------------------------------------------------------
VM.RESET_REQUEST_TTL = 24 * 3600

function VM:WipeGuildData()
    if not self.db then return end
    self.db.inventory = { lastScan = 0, scannedBy = "", gold = 0, tabs = {} }
    self.db.vault = self.db.inventory
    self.db.scanMetadata = self.db.inventory
    self.db.ledger = {}
    self.db.processedBankLogs = {}
    self.db.requests = {}
    self.db.fulfillments = self.db.requests
    self.db.pendingCod = nil
    self.db.pendingReset = nil
    if self.Fulfillment then self.Fulfillment.fulfillStarted = {} end
end

function VM:GetPendingReset()
    local r = self.db and self.db.pendingReset
    if type(r) ~= "table" then return nil end
    if (time() - (tonumber(r.at) or 0)) > VM.RESET_REQUEST_TTL then
        self.db.pendingReset = nil
        return nil
    end
    return r
end

-- Guild Master only: performs the reset and announces the new epoch to the guild
function VM:ResetGuildData(requestedBy)
    if not self:IsGuildMaster() then
        self:Print("|cffff4444Only the Guild Master can carry out a guild-wide reset.|r")
        return
    end
    local me = self:CanonicalActor(self:GetPlayerName())
    self.db.dbEpoch = (self.db.dbEpoch or 1) + 1
    self:WipeGuildData()
    self.db.epochApprovedBy = me
    self.db.epochAt = time()
    if self.Comms then self.Comms:BroadcastEpoch() end
    self:Print(string.format("|cffffaa00Guild-wide reset done (epoch %d%s). All members' data is cleared; it is rebuilt from the Guild Bank logs on the next scan.|r",
        self.db.dbEpoch, (requestedBy and requestedBy ~= "") and (", requested by " .. requestedBy) or ""))
    if self.BankScanner and self.BankScanner:IsBankOpen() then
        self.BankScanner:SchedulePostWithdrawScan()
    end
    if self.Minimap and self.Minimap.UpdateBadge then self.Minimap:UpdateBadge() end
    if self.UI then self.UI:RefreshAll() end
end

-- Step 1 (admin): the Guild Master resets directly; other admins send a request for GM approval
function VM:RequestGuildReset()
    if not self:IsAdmin() then
        self:Print("|cffff4444Only the Guild Master or the guild's officer rank can request a guild-wide reset.|r")
        return
    end
    if self:IsGuildMaster() then
        self:ResetGuildData()
        return
    end
    local me = self:CanonicalActor(self:GetPlayerName())
    self.db.pendingReset = {
        id = string.format("RST_%d_%d", time(), math.random(1000, 9999)),
        by = me,
        at = time(),
    }
    if self.Comms then self.Comms:BroadcastResetRequest() end
    self:Print("|cffffaa00Guild-wide reset requested. The Guild Master must approve it (valid for 24 hours).|r")
    if self.UI then self.UI:RefreshAll() end
end

-- Step 2 (Guild Master)
function VM:ApproveGuildReset(id)
    local r = self:GetPendingReset()
    if not r or (id and r.id ~= id) then return end
    self:ResetGuildData(r.by)
end

function VM:DeclineGuildReset(id)
    local r = self:GetPendingReset()
    if not r or (id and r.id ~= id) or not self:IsGuildMaster() then return end
    self.db.pendingReset = nil
    if self.Comms then self.Comms:BroadcastResetDecline(r.id) end
    self:Print("Guild-wide reset request declined.")
    if self.UI then self.UI:RefreshAll() end
end

function VM:IsAdminName(name)
    return self:IsAdminRank(self:GetRankIndexForName(name))
end

function VM:UpdateRosterCache()
    if not IsInGuild() then return end
    local total = GetNumGuildMembers()
    if total and total > 0 then
        local fresh = {}
        self.db.memberClasses = self.db.memberClasses or {}
        self.db.rankNames = self.db.rankNames or {}
        for i = 1, total do
            local name, rankName, rankIndex, _, class, _, _, _, _, _, classFileName = GetGuildRosterInfo(i)
            if name then
                local norm = self:NormalizeName(name)
                fresh[norm] = rankIndex
                if rankIndex ~= nil and rankName and rankName ~= "" then
                    self.db.rankNames[rankIndex] = rankName
                end
                local token = (classFileName and classFileName ~= "") and self:NormalizeClassToken(classFileName) or self:NormalizeClassToken(class)
                if token and token ~= "" then
                    self.db.memberClasses[norm] = token
                end
            end
        end
        self.db.rosterCache = fresh
    end
    local pName = self:GetPlayerName()
    if pName ~= "" then
        self.db.memberClasses = self.db.memberClasses or {}
        local _, pClass = UnitClass("player")
        if pClass then
            self.db.memberClasses[pName] = self:NormalizeClassToken(pClass)
        end
    end
end

function VM:GetMemberRankIndex(charName)
    local norm = self:NormalizeName(charName)
    if norm == "" or not self.db or not self.db.rosterCache then return 999 end
    local key = self:ResolveNameKey(self.db.rosterCache, norm)
    if key and type(self.db.rosterCache[key]) == "number" then
        return self.db.rosterCache[key]
    end
    return 999
end

function VM:GetRankName(rankIndex)
    if type(rankIndex) ~= "number" or rankIndex >= 999 then return "Legacy Members" end
    if self.db and self.db.rankNames and self.db.rankNames[rankIndex] then
        return self.db.rankNames[rankIndex]
    end
    if GuildControlGetRankName then
        local ok, rName = pcall(GuildControlGetRankName, rankIndex + 1)
        if ok and rName and rName ~= "" then return rName end
    end
    return "Rank " .. tostring(rankIndex)
end

function VM:IsLegacyMember(charName)
    local norm = self:NormalizeName(charName)
    if norm == "" or norm == "UNATTRIBUTED" or norm == "GUILD" then return false end
    if not self.db or not self.db.rosterCache or not next(self.db.rosterCache) then return false end
    if self:ResolveNameKey(self.db.rosterCache, norm) ~= nil then
        return false
    end
    return true
end

function VM:MigrateMainsFormat()
    for char, val in pairs(self.db.mains) do
        if type(val) == "string" then
            self.db.mains[char] = { main = val, updatedAt = time() }
        end
    end
end

-- Resolves character to its canonical guild-roster name (merges first-word log names with two-word roster names) and main link
function VM:GetMainFor(charName)
    local norm = self:NormalizeName(charName)
    if norm == "" or norm == "GUILD" or norm == "UNATTRIBUTED" then return norm end

    local function Canonicalize(n)
        if self.db and self.db.rosterCache then
            local rKey = self:ResolveNameKey(self.db.rosterCache, n)
            if rKey then return rKey end
        end
        return n
    end

    local visited = {}
    local curr = norm
    while not visited[curr] do
        visited[curr] = true
        local canonical = Canonicalize(curr)
        visited[canonical] = true

        local entry = self.db and self.db.mains and (self.db.mains[canonical] or self.db.mains[curr])
        if entry and entry.main and entry.main ~= "" then
            curr = self:NormalizeName(entry.main)
        else
            return canonical
        end
    end
    return Canonicalize(curr)
end

function VM:SetMainCharacter(newMain, charsToLink)
    local targetMain = self:NormalizeName(newMain)
    if targetMain == "" or targetMain == "GUILD" or targetMain == "UNATTRIBUTED" then return end

    local now = time()
    local group = { [targetMain] = true }

    local queue = {}
    if charsToLink then
        for _, c in ipairs(charsToLink) do
            local normC = self:NormalizeName(c)
            if normC ~= "" and normC ~= "GUILD" and normC ~= "UNATTRIBUTED" then
                table.insert(queue, normC)
            end
        end
    end

    while #queue > 0 do
        local curr = table.remove(queue, 1)
        if not group[curr] then
            group[curr] = true
            for char, entry in pairs(self.db.mains) do
                local m = type(entry) == "table" and entry.main or entry
                if m == curr and not group[char] then
                    table.insert(queue, char)
                end
            end
        end
    end

    local changed = true
    while changed do
        changed = false
        for char, entry in pairs(self.db.mains) do
            local m = type(entry) == "table" and entry.main or entry
            if m and m ~= "" and (group[char] or group[m]) then
                if not group[char] then group[char] = true; changed = true end
                if not group[m] then group[m] = true; changed = true end
            end
        end
    end

    for char in pairs(group) do
        if char == targetMain then
            self.db.mains[char] = { main = "", updatedAt = now }
        else
            self.db.mains[char] = { main = targetMain, updatedAt = now }
        end
    end

    if self.Comms then self.Comms:BroadcastMains() end
    if self.UI then self.UI:RefreshAll() end
end

function VM:UnlinkCharacter(charName)
    local norm = self:NormalizeName(charName)
    if norm == "" then return end

    local now = time()
    local parentMain = self:GetMainFor(norm)
    for otherChar, entry in pairs(self.db.mains) do
        local m = type(entry) == "table" and entry.main or entry
        if m == norm then
            if parentMain ~= norm then
                self.db.mains[otherChar] = { main = parentMain, updatedAt = now }
            else
                self.db.mains[otherChar] = { main = "", updatedAt = now }
            end
        end
    end

    self.db.mains[norm] = { main = "", updatedAt = now }

    if self.Comms then self.Comms:BroadcastMains() end
    if self.UI then self.UI:RefreshAll() end
end

function VM:MergeCharacter(oldName, newName)
    local oldNorm = self:NormalizeName(oldName)
    local newNorm = self:NormalizeName(newName)
    if oldNorm == "" or newNorm == "" or oldNorm == newNorm then return end

    if self.db.ledger then
        for _, tx in pairs(self.db.ledger) do
            if tx.player and self:NormalizeName(tx.player) == oldNorm then
                tx.player = newNorm
            end
            if tx.rawSender and self:NormalizeName(tx.rawSender) == oldNorm then
                tx.rawSender = newNorm
            end
        end
    end

    if self.db.mains[oldNorm] then
        self.db.mains[newNorm] = self.db.mains[oldNorm]
        self.db.mains[oldNorm] = nil
    end
    for char, entry in pairs(self.db.mains) do
        local m = type(entry) == "table" and entry.main or entry
        if m == oldNorm then
            if type(entry) == "table" then
                entry.main = newNorm
            else
                self.db.mains[char] = { main = newNorm, updatedAt = time() }
            end
        end
    end

    if self.Comms then
        self.Comms:BroadcastMains()
        self.Comms:BroadcastLedgerSync()
    end
    if self.UI then self.UI:RefreshAll() end
end

function VM:ToggleArchiveMember(charName)
    local norm = self:NormalizeName(charName)
    if norm == "" then return end
    if not self.db.archivedMembers then self.db.archivedMembers = {} end
    self.db.archivedMembers[norm] = not self.db.archivedMembers[norm]
    if self.UI then self.UI:RefreshAll() end
end

function VM:IsArchivedMember(charName)
    local norm = self:NormalizeName(charName)
    if norm == "" then return false end
    return self.db.archivedMembers and self.db.archivedMembers[norm] == true
end

function VM:GetGuildRosterNames(includeLegacy)
    self:UpdateRosterCache()
    local active = {}
    local seen = {}

    for name in pairs(self.db.rosterCache) do
        table.insert(active, name)
        seen[name] = true
    end
    table.sort(active)

    if includeLegacy then
        local legacy = {}
        for char in pairs(self.db.mains) do
            if char ~= "UNATTRIBUTED" and char ~= "GUILD" and not seen[char] then
                local canon = self:GetMainFor(char)
                if not seen[canon] then
                    table.insert(legacy, char)
                    seen[char] = true
                end
            end
        end
        for _, tx in pairs(self.db.ledger) do
            if tx.player and tx.player ~= "UNATTRIBUTED" and tx.player ~= "GUILD" and not seen[tx.player] then
                local canon = self:GetMainFor(tx.player)
                if not seen[canon] then
                    table.insert(legacy, tx.player)
                    seen[tx.player] = true
                end
            end
        end
        table.sort(legacy)
        for _, lName in ipairs(legacy) do
            table.insert(active, lName)
        end
    end

    return active
end

function VM:GetRosterHierarchy(includeLegacy)
    local allNames = self:GetGuildRosterNames(includeLegacy)
    local nameSet = {}
    for _, name in ipairs(allNames) do nameSet[name] = true end

    local mainsMap = {}
    for _, name in ipairs(allNames) do
        local main = self:GetMainFor(name)
        if not nameSet[main] then
            main = name
        end
        mainsMap[main] = mainsMap[main] or {}
        if name ~= main then
            table.insert(mainsMap[main], name)
        end
    end

    local hierarchy = {}
    for mainName, alts in pairs(mainsMap) do
        table.sort(alts)
        local isLeg = self:IsLegacyMember(mainName)
        local rankIdx = isLeg and 999 or self:GetMemberRankIndex(mainName)
        local rankName = isLeg and "Legacy Members" or self:GetRankName(rankIdx)
        table.insert(hierarchy, {
            name = mainName,
            isLegacy = isLeg,
            rankIndex = rankIdx,
            rankName = rankName,
            alts = alts
        })
    end

    table.sort(hierarchy, function(a, b)
        if a.isLegacy ~= b.isLegacy then return not a.isLegacy end
        if (a.rankIndex or 999) ~= (b.rankIndex or 999) then
            return (a.rankIndex or 999) < (b.rankIndex or 999)
        end
        return a.name < b.name
    end)

    return hierarchy
end

function VM:HasPriceAddon()
    if Auctionator and Auctionator.API and Auctionator.API.v1 then return true end
    if Atr_GetAuctionBuyout then return true end
    if TSM_API and TSM_API.GetCustomPriceValueFromItemString then return true end
    if aux and aux.history then return true end
    if AucAdvanced and AucAdvanced.API and AucAdvanced.API.GetMarketValue then return true end
    return false
end

function VM:GetItemAHPrice(itemID, itemLink)
    if not itemID or itemID == 0 then return nil end

    -- 1. TradeSkillMaster (TSM_API)
    if TSM_API and TSM_API.GetCustomPriceValueFromItemString then
        local ok, price = pcall(TSM_API.GetCustomPriceValueFromItemString, "DBMarket", "i:" .. tostring(itemID))
        if ok and type(price) == "number" and price > 0 then
            return price
        end
    end

    -- 2. Auctionator (API v1 or classic Atr_GetAuctionBuyout)
    if Auctionator and Auctionator.API and Auctionator.API.v1 then
        local ok, price = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, ADDON_NAME, itemID)
        if ok and type(price) == "number" and price > 0 then
            return price
        end
    end
    if Atr_GetAuctionBuyout then
        local ok, price = pcall(Atr_GetAuctionBuyout, itemLink or itemID)
        if ok and type(price) == "number" and price > 0 then
            return price
        end
    end

    -- 3. Aux (aux.history)
    if aux and aux.history and aux.history.value then
        local ok, price = pcall(aux.history.value, itemID)
        if ok and type(price) == "number" and price > 0 then
            return price
        end
    end

    -- 4. Auctioneer (AucAdvanced)
    if AucAdvanced and AucAdvanced.API and AucAdvanced.API.GetMarketValue then
        local ok, price = pcall(AucAdvanced.API.GetMarketValue, itemLink or ("item:" .. tostring(itemID)))
        if ok and type(price) == "number" and price > 0 then
            return price
        end
    end

    -- 5. Vendor Sell Price Fallback
    if GetItemInfo then
        local _, _, _, _, _, _, _, _, _, _, sellPrice = GetItemInfo(itemID)
        if type(sellPrice) == "number" and sellPrice > 0 then
            return sellPrice
        end
    end

    return nil
end

-- Max stack size for an item (nil when the item is not cached yet)
function VM:GetItemMaxStack(itemID, itemLink)
    if not GetItemInfo then return nil end
    local lookup = (tonumber(itemID) and tonumber(itemID) > 0) and tonumber(itemID) or itemLink
    if not lookup then return nil end
    local _, _, _, _, _, _, _, stack = GetItemInfo(lookup)
    stack = tonumber(stack)
    if stack and stack > 0 then return stack end
    return nil
end

-- A single request may hold at most 6 stacks (the Trade window limit): 6 items for unstackable gear, 6 x stack size otherwise
VM.MAX_REQUEST_STACKS = 6
function VM:GetMaxRequestQty(itemID, itemLink)
    local stack = self:GetItemMaxStack(itemID, itemLink)
    if not stack then return nil end
    return stack * VM.MAX_REQUEST_STACKS
end

function VM:GetEffectiveLivePrice(itemID, itemLink, fallbackScanPrice)
    local livePrice = self:GetItemAHPrice(itemID, itemLink)
    if livePrice and livePrice > 0 then
        return livePrice
    end
    if fallbackScanPrice and type(fallbackScanPrice) == "number" and fallbackScanPrice > 0 then
        return fallbackScanPrice
    end
    return 0
end

function VM:CalculateMemberTotalPrice(unitAHPrice, count, rule)
    local qty = tonumber(count) or 1
    if qty <= 0 then return 0 end
    local mode = rule and rule.mode or "FREE"
    if mode == "FREE" then
        return 0
    elseif mode == "PERCENT" then
        local unit = tonumber(unitAHPrice) or 0
        if unit <= 0 then return 0 end
        local pct = tonumber(rule.percent) or 50
        local rawTotal = unit * (pct / 100) * qty
        return math.max(10000, math.floor((rawTotal + 5000) / 10000) * 10000)
    else
        return math.floor((tonumber(unitAHPrice) or 0) * qty)
    end
end

function VM:FormatMoney(copper)
    if not copper then return "|cff777777N/A|r" end
    if copper == 0 then return "|cffaaaaaa0g|r" end
    local isNeg = copper < 0
    local absCopper = math.floor(math.abs(copper))
    local prefix = isNeg and "-" or ""
    if GetCoinTextureString then
        local ok, res = pcall(GetCoinTextureString, absCopper)
        if ok and res then return prefix .. res end
    end
    local g = math.floor(absCopper / 10000)
    local s = math.floor((absCopper % 10000) / 100)
    local c = absCopper % 100
    local txt = ""
    if g > 0 then txt = txt .. g .. "|cffffd700g|r " end
    if s > 0 or g > 0 then txt = txt .. s .. "|cffc0c0c0s|r " end
    txt = txt .. c .. "|cffcd7f32c|r"
    return prefix .. txt
end

function VM:FormatMoneyShort(copper)
    if not copper or copper == 0 then return "0g" end
    local isNeg = copper < 0
    local absCopper = math.floor(math.abs(copper))
    local prefix = isNeg and "-" or ""
    local g = math.floor(absCopper / 10000)
    local s = math.floor((absCopper % 10000) / 100)
    if g > 0 then
        if s > 0 and g < 100 then
            return string.format("%s%dg %ds", prefix, g, s)
        else
            return string.format("%s%dg", prefix, g)
        end
    elseif s > 0 then
        return string.format("%s%ds", prefix, s)
    else
        return string.format("%s%dc", prefix, absCopper)
    end
end

-- Plain-text currency string safe for SendChatMessage / whispers (no escape codes or textures)
function VM:FormatMoneyPlain(copper)
    if not copper or copper == 0 then return "0g" end
    local isNeg = copper < 0
    local absCopper = math.floor(math.abs(copper))
    local prefix = isNeg and "-" or ""
    local g = math.floor(absCopper / 10000)
    local s = math.floor((absCopper % 10000) / 100)
    local c = absCopper % 100
    local parts = {}
    if g > 0 then table.insert(parts, g .. "g") end
    if s > 0 then table.insert(parts, s .. "s") end
    if c > 0 and g == 0 then table.insert(parts, c .. "c") end
    if #parts == 0 then return "0g" end
    return prefix .. table.concat(parts, " ")
end

function VM:CalculateBankWealth()
    local inv = self.db and self.db.inventory or {}
    local gold = tonumber(inv.gold) or 0
    local tabsResult = {}
    local itemsTotal = 0

    if inv.tabs then
        local tabIndices = {}
        for tabIdx in pairs(inv.tabs) do
            table.insert(tabIndices, tonumber(tabIdx) or tabIdx)
        end
        table.sort(tabIndices, function(a, b) return tostring(a) < tostring(b) end)

        for _, tabIdx in ipairs(tabIndices) do
            local tabData = inv.tabs[tabIdx]
            if tabData and tabData.isPurchased ~= false and self:IsTabPurchased(tabIdx) then
                local tabItemCount = 0
                local tabVal = 0
                if tabData.items then
                    local itemKeys = {}
                    for k in pairs(tabData.items) do table.insert(itemKeys, k) end
                    table.sort(itemKeys, function(a, b) return tostring(a) < tostring(b) end)
                    for _, k in ipairs(itemKeys) do
                        local item = tabData.items[k]
                        if item then
                            local count = tonumber(item.count) or 1
                            tabItemCount = tabItemCount + count
                            local price = self:GetEffectiveLivePrice(item.itemID, item.itemLink or item.link, item.ahPrice) or 0
                            tabVal = tabVal + (price * count)
                        end
                    end
                end
                itemsTotal = itemsTotal + tabVal
                table.insert(tabsResult, {
                    index = tabIdx,
                    name = tabData.name or ("Tab " .. tabIdx),
                    itemCount = tabItemCount,
                    value = tabVal
                })
            end
        end
    end

    local total = gold + itemsTotal
    return {
        total = total,
        gold = gold,
        itemsTotal = itemsTotal,
        tabs = tabsResult
    }
end

function VM:GetTabRule(tabIndex)
    if not self.db.tabRules[tabIndex] then
        self.db.tabRules[tabIndex] = { mode = "FREE", percent = 50, updatedAt = 0 }
    else
        if not self.db.tabRules[tabIndex].percent or self.db.tabRules[tabIndex].percent <= 0 then
            self.db.tabRules[tabIndex].percent = 50
        end
    end
    return self.db.tabRules[tabIndex]
end

function VM:ComputeRuleSignature(guildName, tabIdx, rule)
    if not rule then return "" end
    local gName = tostring(guildName or GetGuildInfo("player") or self:GetActiveGuildKey() or "")
    local tIdx = tonumber(tabIdx) or 1
    local mode = tostring(rule.mode or "FREE")
    local pct = tonumber(rule.percent) or 50
    local uBy = tostring(rule.updatedBy or "")
    local uAt = tonumber(rule.updatedAt) or 0

    local str = string.format("%s:%d:%s:%d:%s:%d",
        gName, tIdx, mode, pct, uBy, uAt
    )
    local hash = 5381
    for i = 1, #str do
        hash = (hash * 33 + str:byte(i)) % 2147483647
    end
    return string.format("%x", hash)
end

function VM:SetTabRule(tabIndex, mode, percent)
    if not self:IsAdmin() then return end
    local pName = self:GetPlayerName()
    local pct = tonumber(percent) or 50
    local m = mode or "FREE"
    if m == "PERCENT" and (not pct or pct <= 0) then
        pct = 50
    end
    local guildName = GetGuildInfo("player") or self:GetActiveGuildKey() or ""
    local rule = {
        mode = m,
        percent = pct,
        updatedAt = time(),
        updatedBy = pName ~= "" and pName or UnitName("player") or "Officer",
        tampered = nil
    }
    rule.sig = self:ComputeRuleSignature(guildName, tabIndex, rule)
    self.db.tabRules[tabIndex] = rule
    if self.Comms then self.Comms:BroadcastTabRules() end
    if self.UI then self.UI:RefreshAll() end
end

function VM:IsTabPurchased(tabIdx)
    tabIdx = tonumber(tabIdx)
    if not tabIdx or tabIdx < 1 then return false end
    if GetNumGuildBankTabs then
        local liveTabs = GetNumGuildBankTabs()
        if liveTabs and liveTabs > 0 then
            return tabIdx <= liveTabs
        end
    end
    local inv = self.db and self.db.inventory
    if inv then
        if inv.numTabs and inv.numTabs > 0 then
            return tabIdx <= inv.numTabs
        end
        if inv.tabs and inv.tabs[tabIdx] then
            local t = inv.tabs[tabIdx]
            if t.isPurchased ~= nil then return t.isPurchased end
            if t.name == "Not purchased" then return false end
            return true
        end
    end
    return tabIdx == 1
end

function VM:ValidateTabRules()
    if not self.db or not self.db.tabRules then return end
    if not IsInGuild() or GetNumGuildMembers() == 0 then return end
    self:UpdateRosterCache()
    local guildName = GetGuildInfo("player") or self:GetActiveGuildKey() or ""
    local isLocalOfficer = self:IsAdmin()

    for i, rule in pairs(self.db.tabRules) do
        if rule then
            if not self:IsTabPurchased(i) then
                if rule.updatedBy == "System(TamperReset)" then
                    self.db.tabRules[i] = nil
                end
            else
                local updatedBy = tostring(rule.updatedBy or "")
                local cleanBy = updatedBy:match("^[^-]+") or updatedBy
                cleanBy = self:NormalizeName(cleanBy)

                if cleanBy ~= "" and cleanBy ~= "System(TamperReset)" and cleanBy ~= "Default" then
                    local expectedSig = self:ComputeRuleSignature(guildName, i, rule)
                    local hasInvalidSig = not rule.sig or rule.sig == "" or rule.sig ~= expectedSig

                    local foundInRoster = false
                    local isNonOfficer = false
                    local rKey = self:ResolveNameKey(self.db.rosterCache, cleanBy)
                    local rankIndex = rKey and self.db.rosterCache[rKey] or nil

                    if rankIndex == nil then
                        local total = GetNumGuildMembers() or 0
                        for j = 1, total do
                            local rName, _, rIndex = GetGuildRosterInfo(j)
                            if rName then
                                local rClean = rName:match("^[^-]+") or rName
                                if self:NormalizeName(rClean) == cleanBy then
                                    rankIndex = rIndex
                                    foundInRoster = true
                                    self.db.rosterCache[cleanBy] = rIndex or 99
                                    break
                                end
                            end
                        end
                    else
                        foundInRoster = true
                    end

                    if foundInRoster and rankIndex ~= nil then
                        if not self:IsAdminRank(rankIndex) then
                            isNonOfficer = true
                        end
                    end

                    local isTampered = false
                    if isNonOfficer then
                        isTampered = true
                    elseif hasInvalidSig then
                        if isLocalOfficer then
                            rule.sig = expectedSig
                            rule.tampered = nil
                        else
                            isTampered = true
                        end
                    end

                    if isTampered then
                        local resetRule = {
                            mode = "LOCKED",
                            percent = 50,
                            updatedAt = time(),
                            updatedBy = "System(TamperReset)",
                            tampered = true
                        }
                        resetRule.sig = self:ComputeRuleSignature(guildName, i, resetRule)
                        self.db.tabRules[i] = resetRule
                    else
                        rule.tampered = (rule.updatedBy == "System(TamperReset)") and true or nil
                    end
                end
            end
        end
    end
end

-- PENDING and APPROVED items still sitting in the bank are reserved, so nobody can request more than
-- the bank actually holds; PREPARED items have already been withdrawn
function VM:GetReservedCount(itemID, tabIndex)
    local reserved = 0
    for _, req in pairs(self.db.requests) do
        if (req.status == "APPROVED" or req.status == "PENDING") and not req.isGoldRequest and (req.itemID == itemID or req.itemName == itemID) then
            if not tabIndex or req.tab == tabIndex then
                reserved = reserved + (req.count or 0)
            end
        end
    end
    return reserved
end

function VM:GetRealmName()
    local realm = ""
    if GetNormalizedRealmName then
        local ok, r = pcall(GetNormalizedRealmName)
        if ok and type(r) == "string" and r ~= "" then
            realm = r
        end
    end
    if realm == "" and GetRealmName then
        local ok, r = pcall(GetRealmName)
        if ok and type(r) == "string" and r ~= "" then
            realm = r
        end
    end
    return realm
end

function VM:GetCharKey()
    local pName = self:GetPlayerName()
    if pName == "" then return "" end
    return pName
end

function VM:GetStoredGuildKeyForPlayer()
    if not VaultManagerDB or not VaultManagerDB.charGuilds then return nil end
    local pName = self:GetPlayerName()
    if pName == "" then return nil end

    if VaultManagerDB.charGuilds[pName] and VaultManagerDB.charGuilds[pName] ~= "" then
        local gKey = VaultManagerDB.charGuilds[pName]
        if gKey:sub(1, 1) == "-" then gKey = gKey:sub(2) end
        local ext = gKey:match("^.-%-(.+)$")
        if ext and ext ~= "" then gKey = ext end
        return strtrim(gKey)
    end

    for cKey, gKey in pairs(VaultManagerDB.charGuilds) do
        local cleanC = self:NormalizeName(cKey)
        if cleanC == pName and gKey and gKey ~= "" then
            local cleanG = gKey
            if cleanG:sub(1, 1) == "-" then cleanG = cleanG:sub(2) end
            local ext = cleanG:match("^.-%-(.+)$")
            if ext and ext ~= "" then cleanG = ext end
            cleanG = strtrim(cleanG)

            VaultManagerDB.charGuilds[pName] = cleanG
            if cKey ~= pName then
                VaultManagerDB.charGuilds[cKey] = nil
            end
            return cleanG
        end
    end
    return nil
end

function VM:NormalizeGuildKey(guildName)
    if not guildName or guildName == "" then return nil end
    local clean = strtrim(guildName)
    if clean:sub(1, 1) == "-" then clean = clean:sub(2) end
    local ext = clean:match("^.-%-(.+)$")
    if ext and ext ~= "" then clean = ext end
    clean = strtrim(clean)
    return clean ~= "" and clean or nil
end

function VM:MergeGuildData(target, source)
    if not target or not source or target == source then return target end

    -- 1. inventory (and vault / scanMetadata)
    local tScan = (target.inventory and target.inventory.lastScan) or 0
    local sScan = (source.inventory and source.inventory.lastScan) or 0
    local tHasTabs = target.inventory and target.inventory.tabs and next(target.inventory.tabs)
    local sHasTabs = source.inventory and source.inventory.tabs and next(source.inventory.tabs)

    if sScan > tScan or (not tHasTabs and sHasTabs) then
        target.inventory = source.inventory
    elseif tHasTabs and sHasTabs then
        target.inventory = target.inventory or { lastScan = 0, scannedBy = "", tabs = {} }
        target.inventory.tabs = target.inventory.tabs or {}
        for tabIdx, tabData in pairs(source.inventory.tabs) do
            if not target.inventory.tabs[tabIdx] then
                target.inventory.tabs[tabIdx] = tabData
            end
        end
    end
    target.vault = target.inventory
    target.scanMetadata = target.inventory

    -- 2. ledger & processedBankLogs
    target.ledger = target.ledger or {}
    if source.ledger then
        for id, tx in pairs(source.ledger) do
            if not target.ledger[id] then
                target.ledger[id] = tx
            end
        end
    end

    target.processedBankLogs = target.processedBankLogs or {}
    if source.processedBankLogs then
        for sig, val in pairs(source.processedBankLogs) do
            if not target.processedBankLogs[sig] then
                target.processedBankLogs[sig] = val
            end
        end
    end

    -- 3. mains & roster
    target.mains = target.mains or {}
    if source.mains then
        for char, entry in pairs(source.mains) do
            if not target.mains[char] then
                target.mains[char] = entry
            else
                local tUp = (type(target.mains[char]) == "table" and target.mains[char].updatedAt) or 0
                local sUp = (type(entry) == "table" and entry.updatedAt) or 0
                if sUp > tUp then
                    target.mains[char] = entry
                end
            end
        end
    end
    target.roster = target.mains

    -- 4. archivedMembers, memberClasses & rankNames
    target.archivedMembers = target.archivedMembers or {}
    if source.archivedMembers then
        for char, isArchived in pairs(source.archivedMembers) do
            if target.archivedMembers[char] == nil then
                target.archivedMembers[char] = isArchived
            end
        end
    end

    target.memberClasses = target.memberClasses or {}
    if source.memberClasses then
        for char, token in pairs(source.memberClasses) do
            if not target.memberClasses[char] then
                target.memberClasses[char] = token
            end
        end
    end

    target.rankNames = target.rankNames or {}
    if source.rankNames then
        for rIdx, rName in pairs(source.rankNames) do
            if not target.rankNames[rIdx] then
                target.rankNames[rIdx] = rName
            end
        end
    end

    -- 5. requests & fulfillments
    target.requests = target.requests or {}
    if source.requests then
        for id, req in pairs(source.requests) do
            if not target.requests[id] then
                target.requests[id] = req
            end
        end
    end
    target.fulfillments = target.requests

    -- 6. tabRules
    target.tabRules = target.tabRules or {}
    if source.tabRules then
        for i, rule in pairs(source.tabRules) do
            if not target.tabRules[i] then
                target.tabRules[i] = rule
            else
                local tUp = (target.tabRules[i] and target.tabRules[i].updatedAt) or 0
                local sUp = (rule and rule.updatedAt) or 0
                if sUp > tUp then
                    target.tabRules[i] = rule
                end
            end
        end
    end

    -- 7. uiPrefs
    target.uiPrefs = target.uiPrefs or {}
    if source.uiPrefs then
        for k, v in pairs(source.uiPrefs) do
            if target.uiPrefs[k] == nil then
                target.uiPrefs[k] = v
            end
        end
    end

    -- 8. dbEpoch
    target.dbEpoch = math.max(target.dbEpoch or 1, (source and source.dbEpoch) or 1)

    InitGuildSubTables(target)
    return target
end

function VM:MergeSplitBucketsForGuild(guildName)
    if not guildName or guildName == "" or not VaultManagerDB or not VaultManagerDB.guilds then
        return
    end
    local canonicalKey = self:NormalizeGuildKey(guildName)
    if not canonicalKey or canonicalKey == "" then return end

    local suffix = "-" .. canonicalKey
    local canonicalBucket = VaultManagerDB.guilds[canonicalKey]

    local keysToMerge = {}
    for k in pairs(VaultManagerDB.guilds) do
        if k ~= canonicalKey then
            local cleanK = k
            if cleanK:sub(1, 1) == "-" then cleanK = cleanK:sub(2) end
            local ext = cleanK:match("^.-%-(.+)$")
            if ext and ext ~= "" then cleanK = ext end
            cleanK = strtrim(cleanK)

            if cleanK == canonicalKey or k == suffix or (k:len() >= #suffix and k:sub(-#suffix) == suffix) then
                table.insert(keysToMerge, k)
            end
        end
    end

    for _, oldKey in ipairs(keysToMerge) do
        local oldBucket = VaultManagerDB.guilds[oldKey]
        if oldBucket then
            if not canonicalBucket then
                VaultManagerDB.guilds[canonicalKey] = oldBucket
                canonicalBucket = VaultManagerDB.guilds[canonicalKey]
            else
                self:MergeGuildData(canonicalBucket, oldBucket)
            end
            VaultManagerDB.guilds[oldKey] = nil

            if VaultManagerDB.charGuilds then
                for c, g in pairs(VaultManagerDB.charGuilds) do
                    local cleanG = g
                    if cleanG:sub(1, 1) == "-" then cleanG = cleanG:sub(2) end
                    local ext = cleanG:match("^.-%-(.+)$")
                    if ext and ext ~= "" then cleanG = ext end
                    cleanG = strtrim(cleanG)
                    if g == oldKey or cleanG == canonicalKey then
                        VaultManagerDB.charGuilds[c] = canonicalKey
                    end
                end
            end
        end
    end

    if canonicalBucket then
        InitGuildSubTables(canonicalBucket)
    end
end

function VM:MergeAllSplitBuckets()
    if not VaultManagerDB or not VaultManagerDB.guilds then return end
    local guildsToProcess = {}
    for k in pairs(VaultManagerDB.guilds) do
        if k and k ~= "" then
            local gName = k
            if gName:sub(1, 1) == "-" then gName = gName:sub(2) end
            local ext = gName:match("^.-%-(.+)$")
            if ext and ext ~= "" then gName = ext end
            gName = strtrim(gName)
            if gName ~= "" then
                guildsToProcess[gName] = true
            end
        end
    end

    for gName in pairs(guildsToProcess) do
        self:MergeSplitBucketsForGuild(gName)
    end
end

function VM:GetActiveGuildKey()
    VaultManagerDB = VaultManagerDB or {}
    VaultManagerDB.charGuilds = VaultManagerDB.charGuilds or {}
    VaultManagerDB.guilds = VaultManagerDB.guilds or {}

    local liveGuildName = GetGuildInfo("player")
    if liveGuildName and liveGuildName ~= "" then
        return self:NormalizeGuildKey(liveGuildName)
    end

    local storedKey = self:GetStoredGuildKeyForPlayer()
    if storedKey and storedKey ~= "" then
        return self:NormalizeGuildKey(storedKey)
    end

    return nil
end

function VM:SwitchGuildContext(triggerEvent)
    VaultManagerDB = VaultManagerDB or {}
    VaultManagerDB.guilds = VaultManagerDB.guilds or {}
    VaultManagerDB.charGuilds = VaultManagerDB.charGuilds or {}
    VaultManagerDB.uiPrefs = VaultManagerDB.uiPrefs or {}
    for k, v in pairs(DEFAULT_UI_PREFS) do
        if VaultManagerDB.uiPrefs[k] == nil then
            VaultManagerDB.uiPrefs[k] = v
        end
    end

    local pName = self:GetPlayerName()
    local charKey = pName

    if pName ~= "" then
        for cKey, gKey in pairs(VaultManagerDB.charGuilds) do
            local cleanC = self:NormalizeName(cKey)
            if cleanC == pName then
                local cleanG = gKey
                if cleanG:sub(1, 1) == "-" then cleanG = cleanG:sub(2) end
                local ext = cleanG:match("^.-%-(.+)$")
                if ext and ext ~= "" then cleanG = ext end
                cleanG = strtrim(cleanG)

                if not VaultManagerDB.charGuilds[pName] or VaultManagerDB.charGuilds[pName] == "" then
                    VaultManagerDB.charGuilds[pName] = cleanG
                end
                if cKey ~= pName then
                    VaultManagerDB.charGuilds[cKey] = nil
                end
            end
        end
    end

    self:MergeAllSplitBuckets()

    local liveGuildName = GetGuildInfo("player")
    local guildKey = nil

    if liveGuildName and liveGuildName ~= "" then
        local gName = strtrim(liveGuildName)
        if gName ~= "" then
            self:MergeSplitBucketsForGuild(gName)
            guildKey = self:NormalizeGuildKey(gName)
        end
    else
        local storedKey = self:GetStoredGuildKeyForPlayer()
        if storedKey and storedKey ~= "" then
            local gName = storedKey
            if gName:sub(1, 1) == "-" then gName = gName:sub(2) end
            local ext = gName:match("^.-%-(.+)$")
            if ext and ext ~= "" then gName = ext end
            gName = strtrim(gName)
            if gName ~= "" then
                self:MergeSplitBucketsForGuild(gName)
                guildKey = self:NormalizeGuildKey(gName)
            end
        end
    end

    local isLoginEvent = (triggerEvent == "ADDON_LOADED" or triggerEvent == "PLAYER_LOGIN" or triggerEvent == "PLAYER_ENTERING_WORLD")

    if not guildKey or guildKey == "" then
        if not isLoginEvent and triggerEvent == "PLAYER_GUILD_UPDATE" and not IsInGuild() then
            if charKey ~= "" then
                VaultManagerDB.charGuilds[charKey] = nil
            end
        end

        if isLoginEvent and not guildKey then
            for gK, _ in pairs(VaultManagerDB.guilds) do
                if gK and gK ~= "" then
                    local gName = gK
                    if gName:sub(1, 1) == "-" then gName = gName:sub(2) end
                    local ext = gName:match("^.-%-(.+)$")
                    if ext and ext ~= "" then gName = ext end
                    guildKey = strtrim(gName)
                    break
                end
            end
        end

        if not guildKey or guildKey == "" then
            VM.isUnguilded = true
            VM.db = {
                inventory = { lastScan = 0, scannedBy = "", tabs = {} },
                vault = { lastScan = 0, scannedBy = "", tabs = {} },
                tabRules = {},
                requests = {},
                fulfillments = {},
                ledger = {},
                processedBankLogs = {},
                mains = {},
                roster = {},
                rosterCache = {},
                memberClasses = {},
                rankNames = {},
                archivedMembers = {},
                dbEpoch = 1,
                uiPrefs = VaultManagerDB.uiPrefs,
                scanMetadata = { lastScan = 0, scannedBy = "", tabs = {} },
            }
            InitGuildSubTables(VM.db)
            if self.Minimap and self.Minimap.SyncVisibility then self.Minimap:SyncVisibility() end
            if self.UI then self.UI:RefreshAll() end
            return
        end
    end

    VM.isUnguilded = false
    if charKey ~= "" then
        VaultManagerDB.charGuilds[charKey] = guildKey
    end

    if not VaultManagerDB.guilds[guildKey] then
        if VaultManagerDB.inventory and (VaultManagerDB.inventory.lastScan > 0 or (VaultManagerDB.inventory.tabs and next(VaultManagerDB.inventory.tabs))) then
            VaultManagerDB.guilds[guildKey] = {
                dbEpoch = VaultManagerDB.dbEpoch or 1,
                inventory = VaultManagerDB.inventory,
                vault = VaultManagerDB.vault or VaultManagerDB.inventory,
                tabRules = VaultManagerDB.tabRules or {},
                requests = VaultManagerDB.requests or {},
                fulfillments = VaultManagerDB.fulfillments or VaultManagerDB.requests,
                ledger = VaultManagerDB.ledger or {},
                processedBankLogs = VaultManagerDB.processedBankLogs or {},
                mains = VaultManagerDB.mains or {},
                roster = VaultManagerDB.roster or VaultManagerDB.mains,
                rosterCache = VaultManagerDB.rosterCache or {},
                archivedMembers = VaultManagerDB.archivedMembers or {},
                activeReturn = VaultManagerDB.activeReturn,
                uiPrefs = VaultManagerDB.uiPrefs,
                scanMetadata = VaultManagerDB.scanMetadata or VaultManagerDB.inventory,
            }
            VaultManagerDB.inventory = nil
            VaultManagerDB.vault = nil
            VaultManagerDB.ledger = nil
            VaultManagerDB.requests = nil
            VaultManagerDB.fulfillments = nil
            VaultManagerDB.tabRules = nil
            VaultManagerDB.mains = nil
            VaultManagerDB.roster = nil
            VaultManagerDB.processedBankLogs = nil
            VaultManagerDB.rosterCache = nil
            VaultManagerDB.scanMetadata = nil
        else
            VaultManagerDB.guilds[guildKey] = {
                dbEpoch = 1,
                inventory = { lastScan = 0, scannedBy = "", tabs = {} },
                vault = { lastScan = 0, scannedBy = "", tabs = {} },
                tabRules = {},
                requests = {},
                fulfillments = {},
                ledger = {},
                processedBankLogs = {},
                mains = {},
                roster = {},
                rosterCache = {},
                archivedMembers = {},
                uiPrefs = VaultManagerDB.uiPrefs,
                scanMetadata = { lastScan = 0, scannedBy = "", tabs = {} },
            }
        end
        InitGuildSubTables(VaultManagerDB.guilds[guildKey])
    end

    VM.db = VaultManagerDB.guilds[guildKey]
    InitGuildSubTables(VM.db)
    self:ValidateTabRules()
    if self.Ledger and self.Ledger.CleanupDuplicates then
        self.Ledger:CleanupDuplicates()
    end
    if self.Minimap and self.Minimap.SyncVisibility then
        self.Minimap:SyncVisibility()
    end
    if self.UI then self.UI:RefreshAll() end
end

-- Top-level slash command registration before UI:Init()
SLASH_VAULTMANAGER1 = "/vm"
SLASH_VAULTMANAGER2 = "/vaultmanager"
SlashCmdList["VAULTMANAGER"] = function(msg)
    local args = { strsplit(" ", strtrim(msg or "")) }
    local cmd = (args[1] or ""):lower()
    if cmd == "scan" then
        if VM.BankScanner then VM.BankScanner:ForceScan() end
        print("|cff00ccff[Vault Manager]|r Manual Guild Bank scan triggered.")
    elseif cmd == "diag" then
        local S = VM.BankScanner
        local p = function(k, v) print(string.format("  %s: |cffffff00%s|r", k, tostring(v))) end
        print("|cff00ccff[Vault Manager Diagnostics]|r")
        p("Build", VM.BUILD)
        p("Bank open (detected)", S and S:IsBankOpen())
        p("Bank open reason", S and S.bankOpenReason)
        p("Last bank activity (s ago)", S and S.lastBankActivityAt and string.format("%.1f", GetTime() - S.lastBankActivityAt) or "never")
        p("Scan state", S and S.scanState)
        p("Withdrawing", VM.Fulfillment and VM.Fulfillment.isWithdrawing)
        p("Officer / Admin / GM", tostring(VM:IsOfficer()) .. " / " .. tostring(VM:IsAdmin()) .. " / " .. tostring(VM:IsGuildMaster()))
        p("Data epoch", tostring(VM.db and VM.db.dbEpoch))
        p("Player / canonical", VM:GetPlayerName() .. " / " .. VM:CanonicalActor(VM:GetPlayerName()))
        p("Tabs / money log index", tostring(GetNumGuildBankTabs and GetNumGuildBankTabs()) .. " / " .. tostring((MAX_GUILDBANK_TABS or 8) + 1))
        p("Comms queue (high/low)", VM.Comms and VM.Comms.GetQueueSizes and string.format("%d/%d", VM.Comms:GetQueueSizes()) or "?")
        if VM.Ledger and VM.Ledger.GetHeldCash then
            p("Held member payments", VM:FormatMoneyPlain(VM.Ledger:GetHeldCash(VM:GetPlayerName())))
        end
    elseif cmd == "debug" then
        print("|cff00ccff[Vault Manager Debug Log (last 15)]|r")
        local startIdx = math.max(1, #VM.debugLog - 14)
        for i = startIdx, #VM.debugLog do
            print("  " .. VM.debugLog[i])
        end
    elseif cmd == "reset" then
        if VM.db and VM.db.uiPrefs then
            VM.db.uiPrefs.uiScale = 1.0
            VM.db.uiPrefs.windowPos = nil
            VM.db.uiPrefs.showMinimap = true
        end
        if VM.Minimap and VM.Minimap.ResetPosition then
            VM.Minimap:ResetPosition()
        end
        local f = _G["VaultManagerMainFrame"]
        if f then
            f:SetScale(1.0)
            f:ClearAllPoints()
            f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            if not f:IsShown() then
                f:Show()
            end
        end
        if VM.UI and VM.UI.RefreshAll then
            VM.UI:RefreshAll()
        end
        print("|cff00ccff[Vault Manager]|r UI scale, window position, and minimap button reset.")
    elseif cmd == "resetlocal" then
        if VM.db then
            VM.db.inventory = { lastScan = 0, scannedBy = "", tabs = {} }
            VM.db.vault = VM.db.inventory
            VM.db.ledger = {}
            VM.db.processedBankLogs = {}
            VM.db.requests = {}
            VM.db.fulfillments = VM.db.requests
        end
        print("|cff00ccff[Vault Manager]|r Local cache reset. (Not broadcasted to guild).")
        if VM.UI then VM.UI:RefreshAll() end
    elseif cmd == "resetguild" then
        -- Same two-step flow as Settings: typed confirmation, then Guild Master approval
        if VM.UI and VM.UI.ShowResetGuildConfirm then
            VM.UI:ShowResetGuildConfirm()
        else
            VM:RequestGuildReset()
        end
    else
        if VM.UI then VM.UI:Toggle() end
    end
end

local guildEventFrame = CreateFrame("Frame")
guildEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
guildEventFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
guildEventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        VM:UpdateRosterCache()
    end
    if event == "PLAYER_GUILD_UPDATE" and VM.SwitchGuildContext then
        VM:SwitchGuildContext(event)
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, function()
            VM:UpdateRosterCache()
            if VM.SwitchGuildContext then
                VM:SwitchGuildContext(event)
            end
        end)
    else
        VM:UpdateRosterCache()
        if VM.SwitchGuildContext then
            VM:SwitchGuildContext(event)
        end
    end
end)

local rosterUpdatePending = false

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
initFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        VaultManagerDB = VaultManagerDB or {}
        DeepCopyDefaults(VaultManagerDB, DEFAULT_DB)
        VaultManagerDB.guilds = VaultManagerDB.guilds or {}
        for _, gTable in pairs(VaultManagerDB.guilds) do
            InitGuildSubTables(gTable)
        end
        VM:SwitchGuildContext("ADDON_LOADED")
        VM:MigrateMainsFormat()

        -- Purge any old 0g or invalid unattributed gold ledger entries
        if VM.db.ledger then
            for id, tx in pairs(VM.db.ledger) do
                if tx and (tx.itemLink == "GOLD" or tx.itemID == 0) and (not tx.unitPriceAtTime or tx.unitPriceAtTime <= 0 or tx.count == 0) then
                    VM.db.ledger[id] = nil
                end
            end
        end

        -- v1.3.0 Migration: Purge duplicate Guild Bank log entries sharing same tab, type, player, item/gold, count, and calendar day
        if not VM.db.migrationVersion or VM.db.migrationVersion < 130 then
            if VM.db.ledger then
                local seenLogs = {}
                for id, tx in pairs(VM.db.ledger) do
                    if tx and tx.timestamp then
                        local dayKey = date("%Y-%m-%d", tx.timestamp)
                        local isGold = (tx.itemID == 0 or tx.itemLink == "GOLD")
                        local itemKey = isGold and ("GOLD:" .. tostring((tx.unitPriceAtTime or 0) * (tx.count or 1))) or ((tx.itemID and tx.itemID > 0) and tostring(tx.itemID) or tostring(tx.itemLink or "GOLD"))
                        local sig = string.format("%s:%s:%s:%s:%s:%s", tostring(tx.tab or 1), tostring(tx.type or "IN"), tostring(tx.player or ""), itemKey, tostring(tx.count or 1), dayKey)
                        if seenLogs[sig] then
                            VM.db.ledger[id] = nil
                        else
                            seenLogs[sig] = id
                        end
                    end
                end
            end
            VM.db.migrationVersion = 130
        end

        -- v1.3.1 Migration (v131): Purge duplicate Guild Bank entries within 48-hour rolling window, keeping earliest entry
        if not VM.db.migrationVersion or VM.db.migrationVersion < 131 then
            if VM.db.ledger then
                local groups = {}
                for id, tx in pairs(VM.db.ledger) do
                    if tx and tx.type == "IN" and tx.timestamp then
                        local isGold = (tx.itemID == 0 or tx.itemLink == "GOLD")
                        local itemKey = isGold and ("GOLD:" .. tostring((tx.unitPriceAtTime or 0) * (tx.count or 1))) or ((tx.itemID and tx.itemID > 0) and tostring(tx.itemID) or tostring(tx.itemLink or tx.itemName or "GOLD"))
                        local groupKey = string.format("%s:%s:%s:%s:%d", tostring(tx.tab or 1), tostring(tx.type), tostring(tx.player or ""), itemKey, tonumber(tx.count or 1))
                        groups[groupKey] = groups[groupKey] or {}
                        table.insert(groups[groupKey], { id = id, tx = tx })
                    end
                end

                for _, entries in pairs(groups) do
                    table.sort(entries, function(a, b) return (a.tx.timestamp or 0) < (b.tx.timestamp or 0) end)
                    local kept = {}
                    for _, entry in ipairs(entries) do
                        local isDuplicate = false
                        for _, keptTx in ipairs(kept) do
                            if math.abs((entry.tx.timestamp or 0) - (keptTx.timestamp or 0)) <= 172800 then
                                isDuplicate = true
                                break
                            end
                        end
                        if isDuplicate then
                            VM.db.ledger[entry.id] = nil
                        else
                            table.insert(kept, entry.tx)
                        end
                    end
                end
            end
            VM.db.migrationVersion = 131
        end

        -- 48-hour rolling ledger duplication cleanup across all transaction types
        if VM.Ledger and VM.Ledger.CleanupDuplicates then
            VM.Ledger:CleanupDuplicates()
        end
    elseif event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            C_ChatInfo.RegisterAddonMessagePrefix(VM.PREFIX)
        elseif RegisterAddonMessagePrefix then
            RegisterAddonMessagePrefix(VM.PREFIX)
        end

        VM:SwitchGuildContext("PLAYER_LOGIN")
        if VM.Ledger and VM.Ledger.CleanupDuplicates then
            VM.Ledger:CleanupDuplicates()
        end

        if IsInGuild() then
            if C_GuildInfo and C_GuildInfo.GuildRoster then
                C_GuildInfo.GuildRoster()
            elseif GuildRoster then
                GuildRoster()
            end
        end

        VM.BankScanner:Init()
        VM.Comms:Init()
        VM.Fulfillment:Init()
        VM.UI:Init()

        if VM.Ledger and VM.Ledger.CompactMonthlyHistory then
            VM.Ledger:CompactMonthlyHistory()
        end

        print("|cff00ccff[Vault Manager]|r Loaded (build " .. tostring(VM.BUILD) .. "). Type |cffffff00/vm|r to open.")
    elseif event == "GUILD_ROSTER_UPDATE" then
        if not rosterUpdatePending then
            rosterUpdatePending = true
            local function HandleRosterUpdate()
                rosterUpdatePending = false
                if VM.isUnguilded and IsInGuild() and VM.SwitchGuildContext then
                    VM:SwitchGuildContext("GUILD_ROSTER_UPDATE")
                end
                VM:UpdateRosterCache()
                VM:ValidateTabRules()
                local f = _G["VaultManagerMainFrame"]
                if f and f:IsShown() and VM.UI then
                    VM.UI:RefreshAll()
                end
            end
            if C_Timer and C_Timer.After then
                C_Timer.After(0.5, HandleRosterUpdate)
            else
                HandleRosterUpdate()
            end
        end
    end
end)
