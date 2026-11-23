local _, VM = ...
VM.BankScanner = {}
local Scanner = VM.BankScanner

local MAX_SLOTS_PER_TAB = 98
local lastScanTime = 0
local SCAN_COOLDOWN = 4.0

local GB_API = {
    GetNumTabs = function() 
        local n = GetNumGuildBankTabs and GetNumGuildBankTabs() or 0 
        return (n > 0) and n or (MAX_GUILDBANK_TABS or 8)
    end,
    GetTabInfo = function(tab)
        if GetGuildBankTabInfo then return GetGuildBankTabInfo(tab) end
    end,
    SetTab = function(tab)
        if SetCurrentGuildBankTab then SetCurrentGuildBankTab(tab) end
    end,
    QueryTab = function(tab)
        if QueryGuildBankTab then QueryGuildBankTab(tab) end
    end,
    GetItemInfo = function(tab, slot)
        if GetGuildBankItemInfo then return GetGuildBankItemInfo(tab, slot) end
    end,
    GetItemLink = function(tab, slot)
        if GetGuildBankItemLink then return GetGuildBankItemLink(tab, slot) end
    end,
    QueryLog = function(tab)
        if QueryGuildBankLog then QueryGuildBankLog(tab) end
    end,
    GetNumTransactions = function(tab)
        if GetNumGuildBankTransactions then return GetNumGuildBankTransactions(tab) or 0 end
        return 0
    end,
    GetTransaction = function(tab, idx)
        if GetGuildBankTransaction then return GetGuildBankTransaction(tab, idx) end
    end,
    GetNumMoneyTransactions = function()
        if GetNumGuildBankMoneyTransactions then return GetNumGuildBankMoneyTransactions() or 0 end
        return 0
    end,
    GetMoneyTransaction = function(idx)
        if GetGuildBankMoneyTransaction then return GetGuildBankMoneyTransaction(idx) end
    end,
}

function Scanner:Init()
    local f = CreateFrame("Frame")
    f:RegisterEvent("GUILDBANKFRAME_OPENED")
    f:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED")
    f:RegisterEvent("GUILDBANKLOG_UPDATE")
    f:RegisterEvent("GUILDBANK_UPDATE_MONEY")
    f:RegisterEvent("GUILDBANK_UPDATE_TABS")

    local scanQueued = false
    f:SetScript("OnEvent", function(_, event)
        VM:LogDebug("BankScanner event: " .. tostring(event))
        if event == "GUILDBANKFRAME_OPENED" then
            if VM:IsOfficer() then
                VM.Fulfillment:OnGuildBankOpened()
            end
            self:ScheduleScan()
        elseif event == "GUILDBANK_UPDATE_TABS" or event == "GUILDBANKBAGSLOTS_CHANGED" then
            if not scanQueued then
                scanQueued = true
                C_Timer.After(1.0, function()
                    scanQueued = false
                    self:ScanBank()
                end)
            end
        elseif event == "GUILDBANKLOG_UPDATE" or event == "GUILDBANK_UPDATE_MONEY" then
            if not scanQueued then
                scanQueued = true
                C_Timer.After(1.5, function()
                    scanQueued = false
                    self:ScanLogs()
                    self:ScanMoneyLogs()
                end)
            end
        end
    end)
end

function Scanner:ScheduleScan()
    local now = time()
    if (now - lastScanTime) < SCAN_COOLDOWN then return end
    lastScanTime = now

    C_Timer.After(1.0, function()
        self:ForceScan()
    end)
end

function Scanner:RequestAllTabsAndLogs()
    local numTabs = GB_API.GetNumTabs()
    VM:LogDebug(string.format("RequestAllTabsAndLogs: %d tabs", numTabs))
    for tab = 1, numTabs do
        if SetCurrentGuildBankTab then SetCurrentGuildBankTab(tab) end
        if QueryGuildBankTab then QueryGuildBankTab(tab) end
        if QueryGuildBankLog then QueryGuildBankLog(tab) end
    end
    if QueryGuildBankLog then
        QueryGuildBankLog((MAX_GUILDBANK_TABS or 8) + 1)
        QueryGuildBankLog(7)
    end
end

function Scanner:ForceScan()
    VM:LogDebug("ForceScan triggered")
    local now = time()
    if (now - lastScanTime) < SCAN_COOLDOWN then
        print("|cff00ccff[Vault Manager]|r Please wait a few seconds before scanning again.")
        return
    end
    lastScanTime = now

    self:RequestAllTabsAndLogs()
    C_Timer.After(1.0, function() self:RunFullScanPass(true) end)
end

function Scanner:RunFullScanPass(isFinal)
    local itemCount = self:ScanBank()
    local logsAdded = self:ScanLogs()
    local moneyAdded = self:ScanMoneyLogs()
    
    if isFinal then
        print(string.format("|cff00ccff[Vault Manager]|r Scan complete: %d items, %d item logs, %d gold logs stored.",
            itemCount or 0, logsAdded or 0, moneyAdded or 0))
    end
end

function Scanner:ScanBank()
    local numTabs = GB_API.GetNumTabs()
    if numTabs == 0 then return 0 end

    local newTabs = {}
    local totalItemsScanned = 0
    local uniqueItemsCount = 0

    for tab = 1, numTabs do
        if SetCurrentGuildBankTab then SetCurrentGuildBankTab(tab) end
        if QueryGuildBankTab then QueryGuildBankTab(tab) end

        local name, icon = GB_API.GetTabInfo(tab)
        newTabs[tab] = {
            name = name or ("Tab " .. tab),
            icon = icon or "Interface\\Icons\\INV_Misc_Bag_08",
            items = {}
        }

        for slot = 1, MAX_SLOTS_PER_TAB do
            local texture, count = GB_API.GetItemInfo(tab, slot)
            local link = GB_API.GetItemLink(tab, slot)

            count = tonumber(count) or 1
            if link and link ~= "" and count > 0 then
                local itemID = tonumber(link:match("item:(%d+)"))
                local itemName = link:match("%[(.-)%]") or link
                itemName = itemName:gsub("^%[", ""):gsub("%]$", "")

                if not itemID and GetItemInfo then
                    local _, foundLink, _, _, _, _, _, _, _, _, _, foundItemID = GetItemInfo(itemName)
                    if foundItemID then itemID = foundItemID
                    elseif foundLink then itemID = tonumber(foundLink:match("item:(%d+)")) end
                end

                itemID = itemID or 0
                local key = (itemID ~= 0) and itemID or itemName

                texture = texture or "Interface\\Icons\\INV_Misc_QuestionMark"
                if not newTabs[tab].items[key] then
                    newTabs[tab].items[key] = {
                        itemID = itemID,
                        link = link,
                        name = itemName,
                        icon = texture,
                        count = 0
                    }
                    uniqueItemsCount = uniqueItemsCount + 1
                end
                newTabs[tab].items[key].count = newTabs[tab].items[key].count + count
                totalItemsScanned = totalItemsScanned + count
            end
        end
    end

    if totalItemsScanned == 0 and VM.db.inventory and VM.db.inventory.tabs and next(VM.db.inventory.tabs) then
        local hasExistingItems = false
        for _, tabData in pairs(VM.db.inventory.tabs) do
            if tabData.items and next(tabData.items) then
                hasExistingItems = true
                break
            end
        end
        if hasExistingItems then
            VM:LogDebug("ScanBank skipped overwriting with empty data (server data pending).")
            return 0
        end
    end

    VM.db.inventory = {
        lastScan = time(),
        scannedBy = VM:GetPlayerName(),
        tabs = newTabs
    }

    VM.Comms:BroadcastInventory()
    if VM.UI then VM.UI:RefreshAll() end
    return uniqueItemsCount
end

function Scanner:ScanLogs()
    local numTabs = GB_API.GetNumTabs()
    local addedCount = 0
    VM.db.processedBankLogs = VM.db.processedBankLogs or {}

    for tab = 1, numTabs do
        if QueryGuildBankLog then QueryGuildBankLog(tab) end
        local numTx = GB_API.GetNumTransactions(tab)
        for i = 1, numTx do
            local txType, name, itemLink, count = GB_API.GetTransaction(tab, i)
            if name and name:find("%[") and not (itemLink and itemLink:find("%[")) then
                local temp = name
                name = itemLink
                itemLink = temp
            end

            local typeStr = tostring(txType or ""):lower()
            if typeStr:find("deposit") or typeStr == "1" then
                local cleanLink = itemLink or "[Unknown Item]"
                local itemID = tonumber(cleanLink and cleanLink:match("item:(%d+)")) or 0
                local normName = (name and name ~= "") and VM:NormalizeName(name) or "UNATTRIBUTED"
                count = tonumber(count) or 1

                local sig = string.format("t%d_i%d_%s_%s_%d", tab, i, normName, cleanLink, count)
                if not VM.db.processedBankLogs[sig] then
                    VM.db.processedBankLogs[sig] = true
                    local exists = false
                    for _, existingTx in pairs(VM.db.ledger) do
                        if not existingTx.deleted and existingTx.player == normName and existingTx.count == count and (existingTx.itemLink == cleanLink or existingTx.itemName == cleanLink) then
                            exists = true
                            break
                        end
                    end

                    if not exists then
                        VM.Ledger:RecordDeposit(normName, itemID, cleanLink, count, "BANK_LOG")
                        addedCount = addedCount + 1
                    end
                end
            end
        end
    end

    if addedCount > 0 then
        VM.Comms:BroadcastLedgerSync()
        if VM.UI then VM.UI:RefreshAll() end
    end
    return addedCount
end

function Scanner:ScanMoneyLogs()
    if QueryGuildBankLog then 
        local moneyTabIndex = (MAX_GUILDBANK_TABS or 8) + 1
        QueryGuildBankLog(moneyTabIndex)
        QueryGuildBankLog(7)
    end
    local numMoneyTx = GB_API.GetNumMoneyTransactions()
    local addedCount = 0
    VM.db.processedBankLogs = VM.db.processedBankLogs or {}

    for i = 1, numMoneyTx do
        local txType, name, amount = GB_API.GetMoneyTransaction(i)
        local typeStr = tostring(txType or ""):lower()

        if (typeStr:find("deposit") or typeStr == "1") and amount and tonumber(amount) > 0 then
            local normName = (name and name ~= "") and VM:NormalizeName(name) or "UNATTRIBUTED"
            local copper = tonumber(amount) or 0

            local sig = string.format("money_%d_%s_%d", i, normName, copper)
            if not VM.db.processedBankLogs[sig] then
                VM.db.processedBankLogs[sig] = true
                local exists = false
                for _, existingTx in pairs(VM.db.ledger) do
                    if not existingTx.deleted and existingTx.player == normName and (existingTx.unitPriceAtTime * (existingTx.count or 1)) == copper and (existingTx.itemLink == "GOLD" or existingTx.source == "BANK_MONEY_LOG") then
                        exists = true
                        break
                    end
                end

                if not exists then
                    VM.Ledger:RecordGoldDeposit(normName, copper, "BANK_MONEY_LOG")
                    addedCount = addedCount + 1
                end
            end
        end
    end

    if addedCount > 0 then
        VM.Comms:BroadcastLedgerSync()
        if VM.UI then VM.UI:RefreshAll() end
    end
    return addedCount
end
