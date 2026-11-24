local ADDON_NAME, VM = ...
_G.VaultManager = VM

VM.PREFIX = "VMGR_V1"
VM.VERSION = 5
VM.OFFICER_MAX_RANK_INDEX = 1
VM.debugLog = {}
VM.pendingTradePayments = {}

function VM:LogDebug(msg)
    local line = string.format("[%s] %s", date("%H:%M:%S"), tostring(msg or ""))
    table.insert(VM.debugLog, line)
    if #VM.debugLog > 50 then
        table.remove(VM.debugLog, 1)
    end
end

local DEFAULT_DB = {
    dbEpoch = 1,
    guilds = {},
    charGuilds = {},
    uiPrefs = {
        useHistoricalPrices = false,
        rankingPriceMode = "live",
        hideOfficers = false,
        rankingPeriod = "ALL",
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
    return clean:sub(1, 1):upper() .. clean:sub(2)
end

function VM:GetPlayerName()
    return self:NormalizeName(UnitName("player"))
end

function VM:IsOfficer()
    if not IsInGuild() then return false end
    local _, _, rankIndex = GetGuildInfo("player")
    return rankIndex ~= nil and rankIndex <= VM.OFFICER_MAX_RANK_INDEX
end

function VM:IsOfficerName(name)
    local norm = self:NormalizeName(name)
    if norm == "" then return false end
    local rankIndex = self.db.rosterCache[norm]
    if type(rankIndex) ~= "number" then
        if IsInGuild() then
            local total = GetNumGuildMembers() or 0
            for i = 1, total do
                local rName, _, rIndex = GetGuildRosterInfo(i)
                if rName and self:NormalizeName(rName) == norm then
                    self.db.rosterCache[norm] = rIndex or 99
                    return (rIndex ~= nil and rIndex <= VM.OFFICER_MAX_RANK_INDEX)
                end
            end
        end
        return false
    end
    return rankIndex <= VM.OFFICER_MAX_RANK_INDEX
end

function VM:UpdateRosterCache()
    if not IsInGuild() then return end
    local total = GetNumGuildMembers()
    if total and total > 0 then
        local fresh = {}
        for i = 1, total do
            local name, _, rankIndex = GetGuildRosterInfo(i)
            if name then
                fresh[self:NormalizeName(name)] = rankIndex
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

function VM:SetMainCharacter(newMain, charsToLink)
    local targetMain = self:NormalizeName(newMain)
    if targetMain == "" then return end

    local now = time()
    local group = { [targetMain] = true }

    local queue = {}
    if charsToLink then
        for _, c in ipairs(charsToLink) do
            local normC = self:NormalizeName(c)
            if normC ~= "" then table.insert(queue, normC) end
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
    if oldNorm == "" or newNorm == "" or oldNorm == oldNorm then return end

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
        table.insert(hierarchy, {
            name = mainName,
            isLegacy = isLeg,
            alts = alts
        })
    end

    table.sort(hierarchy, function(a, b)
        if a.isLegacy ~= b.isLegacy then return not a.isLegacy end
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

function VM:FormatMoney(copper)
    if not copper then return "|cff777777N/A|r" end
    if copper == 0 then return "|cffaaaaaa0g|r" end
    if GetCoinTextureString then
        local ok, res = pcall(GetCoinTextureString, math.floor(copper))
        if ok and res then return res end
    end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local txt = ""
    if g > 0 then txt = txt .. g .. "|cffffd700g|r " end
    if s > 0 or g > 0 then txt = txt .. s .. "|cffc0c0c0s|r " end
    txt = txt .. c .. "|cffcd7f32c|r"
    return txt
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
        if req.status == "APPROVED" and (req.itemID == itemID or req.itemName == itemID) then
            if not tabIndex or req.tab == tabIndex then
                reserved = reserved + (req.count or 0)
            end
        end
    end
    return reserved
end

function VM:GetActiveGuildKey()
    if not IsInGuild() then return nil end
    local guildName = GetGuildInfo("player")
    local realm = GetRealmName() or "Unknown"
    if not guildName or guildName == "" then return nil end
    return string.format("%s-%s", realm, guildName)
end

function VM:SwitchGuildContext()
    VaultManagerDB = VaultManagerDB or {}
    VaultManagerDB.guilds = VaultManagerDB.guilds or {}
    VaultManagerDB.charGuilds = VaultManagerDB.charGuilds or {}
    VaultManagerDB.uiPrefs = VaultManagerDB.uiPrefs or DEFAULT_DB.uiPrefs

    local guildKey = self:GetActiveGuildKey()
    local charKey = self:GetPlayerName() .. "-" .. (GetRealmName() or "")
    local prevGuildKey = VaultManagerDB.charGuilds[charKey]

    if not guildKey then
        VaultManagerDB.charGuilds[charKey] = nil
        VM.isUnguilded = true
        VM.db = {
            inventory = { lastScan = 0, scannedBy = "", tabs = {} },
            tabRules = {},
            requests = {},
            ledger = {},
            processedBankLogs = {},
            mains = {},
            rosterCache = {},
            archivedMembers = {},
            dbEpoch = 1
        }
        if prevGuildKey and prevGuildKey ~= "" then
            local stillUsed = false
            for c, g in pairs(VaultManagerDB.charGuilds) do
                if g == prevGuildKey then stillUsed = true; break end
            end
            if not stillUsed then
                VaultManagerDB.guilds[prevGuildKey] = nil
            end
        end
        if self.UI then self.UI:RefreshAll() end
        return
    end

    VM.isUnguilded = false
    VaultManagerDB.charGuilds[charKey] = guildKey

    if prevGuildKey and prevGuildKey ~= guildKey then
        local stillUsed = false
        for c, g in pairs(VaultManagerDB.charGuilds) do
            if g == prevGuildKey then stillUsed = true; break end
        end
        if not stillUsed then
            VaultManagerDB.guilds[prevGuildKey] = nil
        end
    end

    if not VaultManagerDB.guilds[guildKey] then
        if VaultManagerDB.inventory and (VaultManagerDB.inventory.lastScan > 0 or (VaultManagerDB.inventory.tabs and next(VaultManagerDB.inventory.tabs))) then
            VaultManagerDB.guilds[guildKey] = {
                dbEpoch = VaultManagerDB.dbEpoch or 1,
                inventory = VaultManagerDB.inventory,
                tabRules = VaultManagerDB.tabRules or {},
                requests = VaultManagerDB.requests or {},
                ledger = VaultManagerDB.ledger or {},
                processedBankLogs = VaultManagerDB.processedBankLogs or {},
                mains = VaultManagerDB.mains or {},
                rosterCache = VaultManagerDB.rosterCache or {},
                archivedMembers = VaultManagerDB.archivedMembers or {},
                activeReturn = VaultManagerDB.activeReturn,
            }
            VaultManagerDB.inventory = nil
            VaultManagerDB.ledger = nil
            VaultManagerDB.requests = nil
            VaultManagerDB.tabRules = nil
            VaultManagerDB.mains = nil
            VaultManagerDB.processedBankLogs = nil
            VaultManagerDB.rosterCache = nil
        else
            VaultManagerDB.guilds[guildKey] = {
                dbEpoch = 1,
                inventory = { lastScan = 0, scannedBy = "", tabs = {} },
                tabRules = {},
                requests = {},
                ledger = {},
                processedBankLogs = {},
                mains = {},
                rosterCache = {},
                archivedMembers = {},
            }
        end
    end

    VM.db = VaultManagerDB.guilds[guildKey]
    if self.UI then self.UI:RefreshAll() end
end

local guildEventFrame = CreateFrame("Frame")
guildEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
guildEventFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
guildEventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
guildEventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_GUILD_UPDATE" or event == "GUILD_ROSTER_UPDATE" then
        C_Timer.After(0.5, function()
            if VM.SwitchGuildContext then
                VM:SwitchGuildContext()
            end
        end)
    end
end)

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
initFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        VaultManagerDB = VaultManagerDB or {}
        DeepCopyDefaults(VaultManagerDB, DEFAULT_DB)
        VM:SwitchGuildContext()
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
        if VM.db.ledger then
            local seenLogs = {}
            for id, tx in pairs(VM.db.ledger) do
                if tx and tx.timestamp then
                    local dayKey = date("%Y-%m-%d", tx.timestamp)
                    local itemKey = (tx.itemID and tx.itemID > 0) and tostring(tx.itemID) or tostring(tx.itemLink or "GOLD")
                    local sig = string.format("%s:%s:%s:%s:%s:%s", tostring(tx.tab or 1), tostring(tx.type or "IN"), tostring(tx.player or ""), itemKey, tostring(tx.count or 1), dayKey)
                    if seenLogs[sig] then
                        VM.db.ledger[id] = nil
                    else
                        seenLogs[sig] = id
                    end
                end
            end
        end

        -- v1.3.1 Migration (v131): Purge duplicate Guild Bank entries within 48-hour rolling window, keeping earliest entry
        if not VM.db.migrationVersion or VM.db.migrationVersion < 131 then
            if VM.db.ledger then
                local groups = {}
                for id, tx in pairs(VM.db.ledger) do
                    if tx and tx.type == "IN" and tx.timestamp then
                        local itemKey = (tx.itemID and tx.itemID > 0) and tostring(tx.itemID) or tostring(tx.itemLink or tx.itemName or "GOLD")
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

        if VM.Ledger and VM.Ledger.CompactMonthlyHistory then
            VM.Ledger:CompactMonthlyHistory()
        end

        SLASH_VAULTMANAGER1 = "/vm"
        SLASH_VAULTMANAGER2 = "/vaultmanager"
        SlashCmdList["VAULTMANAGER"] = function(msg)
            local args = { strsplit(" ", strtrim(msg or "")) }
            local cmd = (args[1] or ""):lower()
            if cmd == "scan" then
                VM.BankScanner:ForceScan()
                print("|cff00ccff[Vault Manager]|r Manual Guild Bank scan triggered.")
            elseif cmd == "debug" then
                print("|cff00ccff[Vault Manager Debug Log (last 15)]|r")
                local startIdx = math.max(1, #VM.debugLog - 14)
                for i = startIdx, #VM.debugLog do
                    print("  " .. VM.debugLog[i])
                end
            elseif cmd == "resetlocal" then
                VM.db.inventory = { lastScan = 0, scannedBy = "", tabs = {} }
                VM.db.ledger = {}
                VM.db.processedBankLogs = {}
                VM.db.requests = {}
                print("|cff00ccff[Vault Manager]|r Local cache reset. (Not broadcasted to guild).")
                if VM.UI then VM.UI:RefreshAll() end
            elseif cmd == "resetguild" then
                if not VM:IsOfficer() then
                    print("|cffff4444[Vault Manager]|r Only officers or Guild Master can perform a guild-wide reset.")
                    return
                end
                VM.db.dbEpoch = (VM.db.dbEpoch or 1) + 1
                VM.db.inventory = { lastScan = 0, scannedBy = "", tabs = {} }
                VM.db.ledger = {}
                VM.db.processedBankLogs = {}
                VM.db.requests = {}
                VM.db.tabRules = {}
                VM.db.mains = {}
                if VM.Comms then VM.Comms:BroadcastEpoch() end
                print("|cff00ccff[Vault Manager]|r Guild-wide reset performed (Epoch " .. VM.db.dbEpoch .. "). Broadcasted to guild.")
                if VM.UI then VM.UI:RefreshAll() end
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
