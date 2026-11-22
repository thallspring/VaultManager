local _, VM = ...
VM.BankScanner = {}
local Scanner = VM.BankScanner

local MAX_SLOTS_PER_TAB = 98

local GB_API = {
    GetNumTabs = function() return GetNumGuildBankTabs and GetNumGuildBankTabs() or 0 end,
    GetTabInfo = function(tab) return GetGuildBankTabInfo and GetGuildBankTabInfo(tab) end,
    QueryTab = function(tab) if QueryGuildBankTab then QueryGuildBankTab(tab) end end,
    GetItemInfo = function(tab, slot) return GetGuildBankItemInfo and GetGuildBankItemInfo(tab, slot) end,
    GetItemLink = function(tab, slot) return GetGuildBankItemLink and GetGuildBankItemLink(tab, slot) end,
    QueryLog = function(tab) if QueryGuildBankLog then QueryGuildBankLog(tab) end end,
    GetNumTransactions = function(tab) return GetNumGuildBankTransactions and GetNumGuildBankTransactions(tab) or 0 end,
    GetTransaction = function(tab, idx) return GetGuildBankTransaction and GetGuildBankTransaction(tab, idx) end,
    GetNumMoneyTransactions = function() return GetNumGuildBankMoneyTransactions and GetNumGuildBankMoneyTransactions() or 0 end,
    GetMoneyTransaction = function(idx) return GetGuildBankMoneyTransaction and GetGuildBankMoneyTransaction(idx) end,
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
        if event == "GUILDBANKFRAME_OPENED" or event == "GUILDBANK_UPDATE_TABS" then
            self:RequestAllTabsAndLogs()
            self:ScheduleScan()
            if event == "GUILDBANKFRAME_OPENED" and VM:IsOfficer() then
                VM.Fulfillment:OnGuildBankOpened()
            end
        elseif event == "GUILDBANKBAGSLOTS_CHANGED" then
            if not scanQueued then
                scanQueued = true
                C_Timer.After(0.4, function()
                    scanQueued = false
                    self:ScanBank()
                end)
            end
        elseif event == "GUILDBANKLOG_UPDATE" or event == "GUILDBANK_UPDATE_MONEY" then
            self:ScanLogs()
            self:ScanMoneyLogs()
        end
    end)
end

function Scanner:ScheduleScan()
    C_Timer.After(0.6, function()
        self:ScanBank()
    end)
end

function Scanner:RequestAllTabsAndLogs()
    local numTabs = GB_API.GetNumTabs()
    for tab = 1, numTabs do
        GB_API.QueryTab(tab)
        GB_API.QueryLog(tab)
    end
    -- Query Guild Bank Money Log (Classic/TBC client uses MAX_GUILDBANK_TABS + 1, typically 9)
    local moneyTabIndex = (MAX_GUILDBANK_TABS or 8) + 1
    GB_API.QueryLog(moneyTabIndex)
    if moneyTabIndex ~= 7 then
        GB_API.QueryLog(7)
    end
end

function Scanner:ForceScan()
    self:RequestAllTabsAndLogs()
    C_Timer.After(0.6, function()
        self:ScanBank()
        self:ScanLogs()
        self:ScanMoneyLogs()
    end)
end

function Scanner:ScanBank()
    local numTabs = GB_API.GetNumTabs()
    if numTabs == 0 then return end

    local newTabs = {}
    for tab = 1, numTabs do
        local name, icon = GB_API.GetTabInfo(tab)
        newTabs[tab] = {
            name = name or ("Tab " .. tab),
            icon = icon or "Interface\\Icons\\INV_Misc_Bag_08",
            items = {}
        }

        for slot = 1, MAX_SLOTS_PER_TAB do
            local texture, count = GB_API.GetItemInfo(tab, slot)
            local link = GB_API.GetItemLink(tab, slot)
            if link and count and count > 0 then
                local itemID = tonumber(link:match("item:(%d+)"))
                if itemID then
                    local itemName = GetItemInfo(link) or link:match("%[(.-)%]") or ("Item " .. itemID)
                    if not newTabs[tab].items[itemID] then
                        newTabs[tab].items[itemID] = {
                            itemID = itemID,
                            link = link,
                            name = itemName,
                            icon = texture,
                            count = 0
                        }
                    end
                    newTabs[tab].items[itemID].count = newTabs[tab].items[itemID].count + count
                end
            end
        end
    end

    VM.db.inventory = {
        lastScan = time(),
        scannedBy = VM:GetPlayerName(),
        tabs = newTabs
    }

    VM.Comms:BroadcastInventory()
    if VM.UI then VM.UI:RefreshAll() end
end

function Scanner:ScanLogs()
    local numTabs = GB_API.GetNumTabs()
    local addedNew = false

    for tab = 1, numTabs do
        local numTx = GB_API.GetNumTransactions(tab)
        for i = 1, numTx do
            local txType, playerName, itemLink, count, _, _, year, month, day, hour = GB_API.GetTransaction(tab, i)
            if txType == "deposit" and itemLink and count and count > 0 then
                local itemID = tonumber(itemLink:match("item:(%d+)"))
                if itemID then
                    local hash = string.format("ITEM_%d_%s_%d_%d_%d_%d_%d_%d",
                        tab, tostring(playerName or "UNKNOWN"), itemID, count,
                        year or 0, month or 0, day or 0, hour or 0)

                    if not VM.db.processedBankLogs[hash] then
                        VM.db.processedBankLogs[hash] = true
                        local donor = (playerName and playerName ~= "") and VM:NormalizeName(playerName) or "UNATTRIBUTED"
                        VM.Ledger:RecordDeposit(donor, itemID, itemLink, count, "BANK_LOG")
                        addedNew = true
                    end
                end
            end
        end
    end

    if addedNew then
        VM.Comms:BroadcastLedgerSync()
        if VM.UI then VM.UI:RefreshAll() end
    end
end

function Scanner:ScanMoneyLogs()
    local numMoneyTx = GB_API.GetNumMoneyTransactions()
    local addedNew = false

    for i = 1, numMoneyTx do
        local txType, playerName, amount, year, month, day, hour = GB_API.GetMoneyTransaction(i)
        if txType == "deposit" and amount and amount > 0 then
            local hash = string.format("GOLD_%s_%d_%d_%d_%d_%d",
                tostring(playerName or "UNKNOWN"), amount,
                year or 0, month or 0, day or 0, hour or 0)

            if not VM.db.processedBankLogs[hash] then
                VM.db.processedBankLogs[hash] = true
                local donor = (playerName and playerName ~= "") and VM:NormalizeName(playerName) or "UNATTRIBUTED"
                VM.Ledger:RecordGoldDeposit(donor, amount, "BANK_MONEY_LOG")
                addedNew = true
            end
        end
    end

    if addedNew then
        VM.Comms:BroadcastLedgerSync()
        if VM.UI then VM.UI:RefreshAll() end
    end
end