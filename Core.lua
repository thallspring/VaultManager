local ADDON_NAME, VM = ...
_G.VaultManager = VM

VM.PREFIX = "VMGR_V1"
VM.VERSION = 6
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

local DEFAULT_UI_PREFS = {
    useHistoricalPrices = false,
    showLockedPrices = false,
    rankingPriceMode = "live",
    hideOfficers = false,
    showLegacyRanking = true,
    rankingPeriod = "ALL",
    rankingSortBy = "net",
    rankingSortDir = "desc",
    enableChatNotifications = true,
    notifyNewerVersion = true,
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
        ver = "1.4.0"
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
}

function VM:NormalizeClassToken(classStr)
    if not classStr or classStr == "" then return nil end
    local upper = strupper(classStr):gsub("%s+", "")
    return upper
end

function VM:GetClassHex(charName)
    local norm = self:NormalizeName(charName)
    if norm == "" then return nil end
    local classToken = self.db and self.db.memberClasses and self.db.memberClasses[norm]
    if classToken and self.CLASS_COLORS[classToken] then
        return self.CLASS_COLORS[classToken]
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
    if rankIndex ~= nil and rankIndex <= VM.OFFICER_MAX_RANK_INDEX then
        return true
    end
    if IsGuildLeader and IsGuildLeader() then
        return true
    end
    if CanEditOfficerNote and CanEditOfficerNote() then
        return true
    end
    return false
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
        self.db.memberClasses = self.db.memberClasses or {}
        for i = 1, total do
            local name, _, rankIndex, _, class, _, _, _, _, _, classFileName = GetGuildRosterInfo(i)
            if name then
                local norm = self:NormalizeName(name)
                fresh[norm] = rankIndex
                local token = classFileName
                if not token or token == "" then
                    token = self:NormalizeClassToken(class)
                else
                    token = strupper(token):gsub("%s+", "")
                end
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
            self.db.memberClasses[pName] = strupper(pClass):gsub("%s+", "")
        end
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

function VM:FormatMoneyShort(copper)
    if not copper or copper == 0 then return "0g" end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    if g > 0 then
        if s > 0 and g < 100 then
            return string.format("%dg %ds", g, s)
        else
            return string.format("%dg", g)
        end
    elseif s > 0 then
        return string.format("%ds", s)
    else
        return string.format("%dc", copper)
    end
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
            if tabData then
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
    if not self:IsOfficer() then return end
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

function VM:ValidateTabRules()
    if not self.db or not self.db.tabRules then return end
    if not IsInGuild() or GetNumGuildMembers() == 0 then return end
    self:UpdateRosterCache()
    local guildName = GetGuildInfo("player") or self:GetActiveGuildKey() or ""
    local isLocalOfficer = self:IsOfficer()

    for i, rule in pairs(self.db.tabRules) do
        if rule then
            local updatedBy = tostring(rule.updatedBy or "")
            local cleanBy = updatedBy:match("^[^-]+") or updatedBy
            cleanBy = self:NormalizeName(cleanBy)

            if cleanBy ~= "" and cleanBy ~= "System(TamperReset)" and cleanBy ~= "Default" then
                local expectedSig = self:ComputeRuleSignature(guildName, i, rule)
                local hasInvalidSig = not rule.sig or rule.sig == "" or rule.sig ~= expectedSig

                local foundInRoster = false
                local isNonOfficer = false
                local rankIndex = self.db.rosterCache[cleanBy]

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
                    if rankIndex > 1 and rankIndex ~= 0 then
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

    -- 4. archivedMembers
    target.archivedMembers = target.archivedMembers or {}
    if source.archivedMembers then
        for char, isArchived in pairs(source.archivedMembers) do
            if target.archivedMembers[char] == nil then
                target.archivedMembers[char] = isArchived
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

    -- Clean up and normalize split character keys
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

    -- Automatically merge split guild buckets across VaultManagerDB.guilds
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
        -- Fall back to stored guild key for this character from VaultManagerDB.charGuilds
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
        -- Never treat GetGuildInfo("player") == nil during login as leaving a guild
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
                archivedMembers = {},
                dbEpoch = 1,
                uiPrefs = VaultManagerDB.uiPrefs,
                scanMetadata = { lastScan = 0, scannedBy = "", tabs = {} },
            }
            InitGuildSubTables(VM.db)
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
    elseif cmd == "debug" then
        print("|cff00ccff[Vault Manager Debug Log (last 15)]|r")
        local startIdx = math.max(1, #VM.debugLog - 14)
        for i = startIdx, #VM.debugLog do
            print("  " .. VM.debugLog[i])
        end
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
        if not VM:IsOfficer() then
            print("|cffff4444[Vault Manager]|r Only officers or Guild Master can perform a guild-wide reset.")
            return
        end
        if VM.db then
            VM.db.dbEpoch = (VM.db.dbEpoch or 1) + 1
            VM.db.inventory = { lastScan = 0, scannedBy = "", tabs = {} }
            VM.db.vault = VM.db.inventory
            VM.db.ledger = {}
            VM.db.processedBankLogs = {}
            VM.db.requests = {}
            VM.db.fulfillments = VM.db.requests
            VM.db.tabRules = {}
            VM.db.mains = {}
            VM.db.roster = VM.db.mains
        end
        if VM.Comms then VM.Comms:BroadcastEpoch() end
        local epoch = (VM.db and VM.db.dbEpoch) or 1
        print("|cff00ccff[Vault Manager]|r Guild-wide reset performed (Epoch " .. epoch .. "). Broadcasted to guild.")
        if VM.UI then VM.UI:RefreshAll() end
    else
        if VM.UI then VM.UI:Toggle() end
    end
end

local guildEventFrame = CreateFrame("Frame")
guildEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
guildEventFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
guildEventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
guildEventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_GUILD_UPDATE" or event == "GUILD_ROSTER_UPDATE" then
        if event == "PLAYER_ENTERING_WORLD" or event == "GUILD_ROSTER_UPDATE" then
            VM:UpdateRosterCache()
        end
        if event == "PLAYER_GUILD_UPDATE" then
            if VM.SwitchGuildContext then
                VM:SwitchGuildContext(event)
            end
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

        VM:SwitchGuildContext("PLAYER_LOGIN")

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

        print("|cff00ccff[Vault Manager]|r Loaded. Type |cffffff00/vm|r to open.")
    elseif event == "GUILD_ROSTER_UPDATE" then
        VM:UpdateRosterCache()
        VM:ValidateTabRules()
        if VM.UI then VM.UI:RefreshAll() end
    end
end)
