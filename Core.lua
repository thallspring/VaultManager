local ADDON_NAME, VM = ...
_G.VaultManager = VM

VM.PREFIX = "VMGR_V1"
VM.VERSION = 2

local DEFAULT_DB = {
    inventory = {
        lastScan = 0,
        scannedBy = "",
        tabs = {},
    },
    tabRules = {},
    requests = {},
    ledger = {},
    processedBankLogs = {},
    mains = {},
    rosterCache = {},
    uiPrefs = {
        useHistoricalPrices = false,
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
    local short = strsplit("-", name)
    return short:sub(1, 1):upper() .. short:sub(2)
end

function VM:GetPlayerName()
    return self:NormalizeName(UnitName("player"))
end

function VM:IsOfficer()
    if not IsInGuild() then return false end
    if IsGuildLeader() then return true end
    if C_GuildInfo and C_GuildInfo.CanViewOfficerNote then
        return C_GuildInfo.CanViewOfficerNote()
    end
    if CanViewOfficerNote then
        return CanViewOfficerNote()
    end
    local _, _, rankIndex = GetGuildInfo("player")
    return rankIndex ~= nil and rankIndex <= 1
end

function VM:UpdateRosterCache()
    if not IsInGuild() then return end
    local total = GetNumGuildMembers()
    if total and total > 0 then
        local fresh = {}
        for i = 1, total do
            local name = GetGuildRosterInfo(i)
            if name then
                fresh[self:NormalizeName(name)] = true
            end
        end
        self.db.rosterCache = fresh
    end
end

function VM:IsLegacyMember(charName)
    local norm = self:NormalizeName(charName)
    if norm == "" or norm == "Unattributed" or norm == "UNATTRIBUTED" then return false end
    if not next(self.db.rosterCache) then return false end
    return not self.db.rosterCache[norm]
end

function VM:MigrateMainsFormat()
    for char, val in pairs(self.db.mains) do
        if type(val) == "string" then
            self.db.mains[char] = { main = val, updatedAt = time() }
        end
    end
end

function VM:GetMainFor(charName)
    local norm = self:NormalizeName(charName)
    local visited = {}
    while self.db.mains[norm] and self.db.mains[norm].main and self.db.mains[norm].main ~= "" and not visited[norm] do
        visited[norm] = true
        norm = self.db.mains[norm].main
    end
    return norm
end

-- Links characters to newMain (each ledger transaction retains its original tx.player and merges dynamically)
function VM:SetMainCharacter(newMain, charsToLink)
    local targetMain = self:NormalizeName(newMain)
    if targetMain == "" then return end

    local now = time()
    local group = { [targetMain] = true }
    if charsToLink then
        for _, c in ipairs(charsToLink) do
            local normC = self:NormalizeName(c)
            if normC ~= "" then group[normC] = true end
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

-- Unlinks a specific character from its current Main (and syncs via P2P)
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
            if not seen[char] then
                table.insert(legacy, char)
                seen[char] = true
            end
        end
        for _, tx in pairs(self.db.ledger) do
            if tx.player and tx.player ~= "UNATTRIBUTED" and not seen[tx.player] then
                table.insert(legacy, tx.player)
                seen[tx.player] = true
            end
        end
        table.sort(legacy)
        for _, lName in ipairs(legacy) do
            table.insert(active, lName)
        end
    end

    return active
end

function VM:HasPriceAddon()
    return Auctionator ~= nil and Auctionator.API ~= nil and Auctionator.API.v1 ~= nil
end

function VM:GetItemAHPrice(itemID)
    if not itemID or not self:HasPriceAddon() then return nil end
    local ok, price = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, ADDON_NAME, itemID)
    if ok and type(price) == "number" and price > 0 then
        return price
    end
    return nil
end

function VM:FormatMoney(copper)
    if not copper then return "|cff777777N/A|r" end
    if copper == 0 then return "|cffaaaaaa0g|r" end
    return GetCoinTextureString(math.floor(copper))
end

function VM:GetTabRule(tabIndex)
    if not self.db.tabRules[tabIndex] then
        self.db.tabRules[tabIndex] = { mode = "FREE", percent = 50, updatedAt = 0 }
    end
    return self.db.tabRules[tabIndex]
end

function VM:SetTabRule(tabIndex, mode, percent)
    self.db.tabRules[tabIndex] = {
        mode = mode or "FREE",
        percent = tonumber(percent) or 50,
        updatedAt = time()
    }
    if self.Comms then self.Comms:BroadcastTabRules() end
    if self.UI then self.UI:RefreshAll() end
end

function VM:GetReservedCount(itemID, tabIndex)
    local reserved = 0
    for _, req in pairs(self.db.requests) do
        if req.status == "APPROVED" and req.itemID == itemID then
            if not tabIndex or req.tab == tabIndex then
                reserved = reserved + (req.count or 0)
            end
        end
    end
    return reserved
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
initFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        VaultManagerDB = VaultManagerDB or {}
        DeepCopyDefaults(VaultManagerDB, DEFAULT_DB)
        VM.db = VaultManagerDB
        VM:MigrateMainsFormat()
    elseif event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            C_ChatInfo.RegisterAddonMessagePrefix(VM.PREFIX)
        elseif RegisterAddonMessagePrefix then
            RegisterAddonMessagePrefix(VM.PREFIX)
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

        SLASH_VAULTMANAGER1 = "/vm"
        SLASH_VAULTMANAGER2 = "/vaultmanager"
        SlashCmdList["VAULTMANAGER"] = function(msg)
            local cmd = strtrim(msg or ""):lower()
            if cmd == "scan" then
                VM.BankScanner:ForceScan()
                print("|cff00ccff[Vault Manager]|r Manual Guild Bank scan triggered.")
            else
                VM.UI:Toggle()
            end
        end

        print("|cff00ccff[Vault Manager]|r Loaded. Type |cffffff00/vm|r to open.")
    elseif event == "GUILD_ROSTER_UPDATE" then
        VM:UpdateRosterCache()
        if VM.UI then VM.UI:RefreshAll() end
    end
end)