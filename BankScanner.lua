local _, VM = ...
VM.BankScanner = {}
local Scanner = VM.BankScanner

local MAX_SLOTS_PER_TAB = 98
local lastScanTime = 0
local SCAN_COOLDOWN = 2.0
local isScanning = false
local ignoreEventsUntil = 0
local suppressChatPrint = false

Scanner.scanState = "READY" -- "READY" | "SCANNING" | "COMPLETE" | "STALE"

-- Debounce frame using OnUpdate (without C_Timer)
local scanDebounceFrame = CreateFrame("Frame")
local scanDebounceTimeLeft = 0
local scanDebounceIsFinal = false
scanDebounceFrame:Hide()
scanDebounceFrame:SetScript("OnUpdate", function(self, elapsed)
    scanDebounceTimeLeft = scanDebounceTimeLeft - elapsed
    if scanDebounceTimeLeft <= 0 then
        self:Hide()
        if Scanner.RunFullScanPass then
            Scanner:RunFullScanPass(scanDebounceIsFinal)
        end
    end
end)

-- Delayed re-scan frame using OnUpdate (without C_Timer)
local rescanFrame = CreateFrame("Frame")
local rescanTimeLeft = 0
rescanFrame:Hide()
rescanFrame:SetScript("OnUpdate", function(self, elapsed)
    rescanTimeLeft = rescanTimeLeft - elapsed
    if rescanTimeLeft <= 0 then
        self:Hide()
        if Scanner.RunFullScanPass then
            Scanner:RunFullScanPass(true)
        end
    end
end)

local GB_API = {
    GetNumTabs = function() 
        local n = GetNumGuildBankTabs and GetNumGuildBankTabs() or 0 
        if n > 0 then return n end
        local inv = VM.db and VM.db.inventory
        if inv and inv.numTabs and inv.numTabs > 0 then return inv.numTabs end
        return 1
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

function Scanner:GetScanStatus()
    local isBankOpen = GuildBankFrame and GuildBankFrame:IsVisible()
    if self.scanState == "SCANNING" then
        return "SCANNING", "Scanning...", { 0.85, 0.65, 0.15, 1 }
    elseif self.scanState == "COMPLETE" or (VM.db and VM.db.inventory and VM.db.inventory.lastScan and VM.db.inventory.lastScan > 0) then
        local inv = VM.db and VM.db.inventory
        local lastSyncedFrom = inv and inv.lastSyncedFrom
        local scannedBy = inv and inv.scannedBy
        local lastScanBy = inv and inv.lastScanBy
        local pName = UnitName("player") or VM:GetPlayerName()
        local isSynced = (lastSyncedFrom and lastSyncedFrom ~= "") or (scannedBy and scannedBy ~= "" and scannedBy ~= pName) or (lastScanBy and lastScanBy ~= "" and lastScanBy ~= pName)

        if isSynced then
            return "COMPLETE", "Synced", { 0.20, 0.75, 0.35, 1 }
        else
            return "COMPLETE", "Scan Complete", { 0.20, 0.75, 0.35, 1 }
        end
    elseif isBankOpen and self.scanState == "STALE" then
        return "STALE", "Force Scan", { 0.85, 0.30, 0.30, 1 }
    elseif isBankOpen then
        return "READY", "Scan Bank", { 0.25, 0.55, 0.85, 1 }
    else
        return "READY", "Bank Closed", { 0.40, 0.40, 0.45, 1 }
    end
end

function Scanner:Init()
    local f = CreateFrame("Frame")
    f:RegisterEvent("GUILDBANKFRAME_OPENED")
    f:RegisterEvent("GUILDBANKFRAME_CLOSED")
    f:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED")
    f:RegisterEvent("GUILDBANKLOG_UPDATE")
    f:RegisterEvent("GUILDBANK_UPDATE_MONEY")
    f:RegisterEvent("GUILDBANK_UPDATE_TABS")

    f:SetScript("OnEvent", function(_, event)
        if VM.isUnguilded then return end
        VM:LogDebug("BankScanner event: " .. tostring(event))
        if event == "GUILDBANKLOG_UPDATE" or event == "GUILDBANK_UPDATE_MONEY" then
            suppressChatPrint = true
            self:TriggerDebouncedScan(false)
            return
        end

        if isScanning or GetTime() < ignoreEventsUntil then
            if event == "GUILDBANKBAGSLOTS_CHANGED" or event == "GUILDBANK_UPDATE_TABS" then
                return
            end
        end

        if event == "GUILDBANKFRAME_OPENED" then
            if VM:IsOfficer() then
                VM.Fulfillment:OnGuildBankOpened()
            end
            self.scanState = "SCANNING"
            isScanning = true
            ignoreEventsUntil = GetTime() + 2.0
            suppressChatPrint = false
            self:RequestAllTabsAndLogs()
            self:TriggerDebouncedScan(true)
        elseif event == "GUILDBANKFRAME_CLOSED" then
            isScanning = false
            scanDebounceFrame:Hide()
            if self.scanState == "SCANNING" then
                self.scanState = "READY"
            end
            if VM.UI and VM.UI.UpdateScanStatusButton then
                VM.UI:UpdateScanStatusButton()
            end
        elseif event == "GUILDBANKBAGSLOTS_CHANGED" or event == "GUILDBANK_UPDATE_TABS" then
            if isScanning or GetTime() < ignoreEventsUntil then return end
            suppressChatPrint = true
            self:TriggerDebouncedScan(false)
        end
    end)
end

function Scanner:TriggerDebouncedScan(isFinal)
    self.scanState = "SCANNING"
    isScanning = true
    ignoreEventsUntil = GetTime() + 2.0
    if isFinal then
        scanDebounceIsFinal = true
    end
    scanDebounceTimeLeft = 0.75
    scanDebounceFrame:Show()
    if VM.UI and VM.UI.UpdateScanStatusButton then
        VM.UI:UpdateScanStatusButton()
    end
end

function Scanner:RequestAllTabsAndLogs()
    isScanning = true
    ignoreEventsUntil = GetTime() + 2.0
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
        VM:Print("Please wait a moment before scanning again.")
        return
    end
    lastScanTime = now

    self.scanState = "SCANNING"
    isScanning = true
    ignoreEventsUntil = GetTime() + 2.0
    suppressChatPrint = false
    if VM.UI and VM.UI.UpdateScanStatusButton then
        VM.UI:UpdateScanStatusButton()
    end

    self:RequestAllTabsAndLogs()
    scanDebounceIsFinal = true
    scanDebounceTimeLeft = 0.75
    scanDebounceFrame:Show()
end

function Scanner:RunFullScanPass(isFinal)
    isScanning = true
    ignoreEventsUntil = GetTime() + 2.0
    local itemCount = self:ScanBank()
    local logsAdded = self:ScanLogs()
    local moneyAdded = self:ScanMoneyLogs()
    
    self.scanState = "COMPLETE"
    isScanning = false

    if isFinal and not suppressChatPrint then
        VM:Print(string.format("Scan complete: %d items, %d item logs, %d gold logs stored.",
            itemCount or 0, logsAdded or 0, moneyAdded or 0))
    end
    suppressChatPrint = false

    if VM.UI and VM.UI.UpdateScanStatusButton then
        VM.UI:UpdateScanStatusButton()
    end
end

function Scanner:ScanBank()
    local numTabs = GB_API.GetNumTabs()
    if numTabs == 0 then return 0 end

    local maxTabs = math.max(numTabs, 6)
    local newTabs = {}
    local totalItemsScanned = 0
    local uniqueItemsCount = 0
    local oldTabs = VM.db.inventory and VM.db.inventory.tabs or {}
    local hasPendingItems = false

    for tab = 1, maxTabs do
        local isPurchased = (tab <= numTabs)
        local name, icon, isViewable = GB_API.GetTabInfo(tab)
        if not isPurchased then
            newTabs[tab] = {
                name = "Not purchased",
                icon = "Interface\\Icons\\INV_Misc_QuestionMark",
                isPurchased = false,
                items = {}
            }
        else
            if SetCurrentGuildBankTab then SetCurrentGuildBankTab(tab) end
            if QueryGuildBankTab then QueryGuildBankTab(tab) end

            if isViewable == false and oldTabs[tab] then
                newTabs[tab] = oldTabs[tab]
                newTabs[tab].isPurchased = true
            else
                newTabs[tab] = {
                    name = name or ("Tab " .. tab),
                    icon = icon or "Interface\\Icons\\INV_Misc_Bag_08",
                    isPurchased = true,
                    items = {}
                }

                for slot = 1, MAX_SLOTS_PER_TAB do
                    local texture, count = GB_API.GetItemInfo(tab, slot)
                    local link = GB_API.GetItemLink(tab, slot)

                    count = tonumber(count) or 1
                    if texture and count > 0 and (not link or link == "") then
                        hasPendingItems = true
                    end

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

                        local scannedType, scannedEquip
                        local isInfoChecked = false
                        if GetItemInfo then
                            local numID = tonumber(itemID)
                            if numID and numID <= 0 then numID = nil end

                            local lookup
                            if link and type(link) == "string" and link:find("|Hitem:", 1, true) then
                                lookup = link
                            elseif numID then
                                lookup = numID
                            end

                            if lookup then
                                local r1, r2, r3, r4, r5, r6, r7, r8, r9, r10 = GetItemInfo(lookup)
                                if not r1 and numID and lookup ~= numID then
                                    r1, r2, r3, r4, r5, r6, r7, r8, r9, r10 = GetItemInfo(numID)
                                end
                                if r1 then
                                    isInfoChecked = true
                                    local rets = { r1, r2, r3, r4, r5, r6, r7, r8, r9, r10 }
                                    for idx = 1, 10 do
                                        local val = rets[idx]
                                        if type(val) == "string" then
                                            if not scannedType and (val == "Weapon" or val == "Armor" or val == "Consumable" or
                                                                    val == "Trade Goods" or val == "Reagent" or val == "Recipe") then
                                                scannedType = val
                                            end
                                            if not scannedEquip and val:find("^INVTYPE_") then
                                                scannedEquip = val
                                            end
                                        end
                                    end
                                end
                            end
                        end

                        texture = texture or "Interface\\Icons\\INV_Misc_QuestionMark"
                        local ahVal = VM:GetItemAHPrice(itemID, link) or 0
                        if not newTabs[tab].items[key] then
                            newTabs[tab].items[key] = {
                                itemID = itemID,
                                link = link,
                                itemLink = link,
                                name = itemName,
                                icon = texture,
                                ahPrice = ahVal,
                                count = 0,
                                itemType = scannedType,
                                equipSlot = scannedEquip,
                                infoChecked = isInfoChecked
                            }
                            uniqueItemsCount = uniqueItemsCount + 1
                        else
                            if ahVal > 0 then newTabs[tab].items[key].ahPrice = ahVal end
                            if scannedType then
                                newTabs[tab].items[key].itemType = scannedType
                            end
                            if scannedEquip then
                                newTabs[tab].items[key].equipSlot = scannedEquip
                            end
                            if isInfoChecked then
                                newTabs[tab].items[key].infoChecked = true
                            end
                        end
                        newTabs[tab].items[key].count = newTabs[tab].items[key].count + count
                        totalItemsScanned = totalItemsScanned + count
                    end
                end
            end
        end
    end

    local bankMoney = 0
    if GetGuildBankMoney then
        local m = GetGuildBankMoney()
        if type(m) == "number" and m >= 0 then
            bankMoney = m
        end
    end

    if hasPendingItems then
        VM:LogDebug("ScanBank detected occupied slots with missing item info; scheduling delayed re-scan.")
        self.scanState = "STALE"
        rescanTimeLeft = 0.75
        rescanFrame:Show()
        if bankMoney > 0 and VM.db.inventory then
            VM.db.inventory.gold = bankMoney
        end
        return 0
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
            self.scanState = "STALE"
            if bankMoney > 0 then
                VM.db.inventory.gold = bankMoney
            end
            return 0
        end
    end

    local serverTime = (GetServerTime and GetServerTime()) or time()
    VM.db.inventory = {
        lastScan = serverTime,
        lastScanBy = UnitName("player") or VM:GetPlayerName(),
        scannedBy = VM:GetPlayerName(),
        lastSyncedFrom = nil,
        gold = bankMoney,
        numTabs = numTabs,
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
        local rule = VM:GetTabRule(tab)
        local isFFA = (rule.mode == "FREE")
        
        local snapshotCounts = {}
        local txDataList = {}
        for i = 1, numTx do
            local txType, name, itemLink, count = GB_API.GetTransaction(tab, i)
            if name and name:find("%[") and not (itemLink and itemLink:find("%[")) then
                local temp = name
                name = itemLink
                itemLink = temp
            end
            local typeStr = tostring(txType or ""):lower()
            local isDeposit = (typeStr:find("deposit") or typeStr == "1")
            local isWithdraw = (isFFA and (typeStr:find("withdraw") or typeStr == "2" or typeStr:find("take")))

            if isDeposit or isWithdraw then
                local cleanLink = itemLink or "[Unknown Item]"
                local itemID = tonumber(cleanLink and cleanLink:match("item:(%d+)")) or 0
                local normName = (name and name ~= "") and VM:NormalizeName(name) or "UNATTRIBUTED"
                count = tonumber(count) or 1
                local computedTimestamp = time() - ((numTx - i) * 1800)
                local itemKey = (itemID > 0) and tostring(itemID) or cleanLink
                local txDir = isDeposit and "IN" or "OUT"
                local tupleKey = string.format("t%d:%s:%s:%s:%d", tab, txDir, normName, itemKey, count)
                
                snapshotCounts[tupleKey] = (snapshotCounts[tupleKey] or 0) + 1
                table.insert(txDataList, {
                    tab = tab,
                    txDir = txDir,
                    normName = normName,
                    itemID = itemID,
                    cleanLink = cleanLink,
                    count = count,
                    computedTimestamp = computedTimestamp,
                    tupleKey = tupleKey,
                    isFFA = isFFA
                })
            end
        end

        for _, data in ipairs(txDataList) do
            local existingCount = 0
            for _, existingTx in pairs(VM.db.ledger) do
                if not existingTx.deleted and existingTx.type == data.txDir and (existingTx.tab or 1) == data.tab and existingTx.player == data.normName and existingTx.count == data.count and (existingTx.isFFA == data.isFFA) then
                    local exItemKey = (existingTx.itemID and existingTx.itemID > 0) and tostring(existingTx.itemID) or tostring(existingTx.itemLink or existingTx.itemName or "")
                    local dataItemKey = (data.itemID > 0) and tostring(data.itemID) or data.cleanLink
                    if exItemKey == dataItemKey then
                        if math.abs((existingTx.timestamp or 0) - data.computedTimestamp) <= 259200 then
                            existingCount = existingCount + 1
                        end
                    end
                end
            end

            local sig = string.format("v141_t%d:%s:%s:%s:%d:%d", data.tab, data.txDir, data.normName, (data.itemID > 0) and tostring(data.itemID) or data.cleanLink, data.count, math.floor(data.computedTimestamp / 259200))
            if not VM.db.processedBankLogs[sig] then
                local totalAllowed = snapshotCounts[data.tupleKey] or 1
                if existingCount < totalAllowed then
                    VM.db.processedBankLogs[sig] = true
                    if data.txDir == "IN" then
                        local activeRet = VM.db.activeReturn
                        if activeRet and (data.itemID == activeRet.itemID or (data.itemID == 0 and data.cleanLink == activeRet.itemLink)) then
                            VM.Ledger:RecordReturnDeposit(data.normName, data.itemID, data.cleanLink, data.count, activeRet.fulfillmentId)
                        else
                            local tx = VM.Ledger:RecordDeposit(data.normName, data.itemID, data.cleanLink, data.count, "BANK_LOG")
                            if tx then
                                tx.isFFA = data.isFFA
                                tx.tab = data.tab
                            end
                        end
                    else
                        local ahPrice = VM:GetItemAHPrice(data.itemID, data.cleanLink) or 0
                        local itemName = data.cleanLink:gsub("^%[", ""):gsub("%]$", "")
                        local tx = {
                            id = string.format("OUT_FFA_%d_%d", time(), math.random(1000, 9999)),
                            type = "OUT",
                            player = data.normName,
                            itemID = data.itemID,
                            itemLink = data.cleanLink,
                            itemName = itemName,
                            count = data.count,
                            unitPriceAtTime = ahPrice,
                            chargedUnitPrice = 0,
                            timestamp = data.computedTimestamp,
                            updatedAt = time(),
                            officer = VM:GetPlayerName(),
                            source = "FFA_SCAN",
                            isFFA = true,
                            tab = data.tab,
                            isManual = false,
                            deleted = false
                        }
                        VM.db.ledger[tx.id] = tx
                        VM.Comms:BroadcastTransaction(tx)
                    end
                    addedCount = addedCount + 1
                    existingCount = existingCount + 1
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
    if GetGuildBankMoney and GetGuildBankMoney() < 0 then
        return 0
    end

    if QueryGuildBankLog then 
        local moneyTabIndex = (MAX_GUILDBANK_TABS or 8) + 1
        QueryGuildBankLog(moneyTabIndex)
        QueryGuildBankLog(7)
    end
    local numMoneyTx = GB_API.GetNumMoneyTransactions()
    local addedCount = 0
    VM.db.processedBankLogs = VM.db.processedBankLogs or {}

    local snapshotCounts = {}
    local txDataList = {}

    for i = 1, numMoneyTx do
        local txType, name, amount, years, months, days, hours = GB_API.GetMoneyTransaction(i)
        local typeStr = tostring(txType or ""):lower()

        -- Filter out repairs and tab purchases explicitly
        if not (typeStr:find("repair") or typeStr:find("buytab")) then
            local copper = tonumber(amount) or 0
            if copper > 0 then
                local normName = (name and name ~= "") and VM:NormalizeName(name) or "UNATTRIBUTED"
                local isDeposit = (typeStr:find("deposit") or typeStr == "1")
                local isWithdraw = (typeStr:find("withdraw") or typeStr == "2")

                if isDeposit or isWithdraw then
                    local txDir = isDeposit and "IN" or "OUT"
                    local ageSec = nil
                    if years or months or days or hours then
                        ageSec = ((tonumber(years) or 0) * 365 * 86400)
                               + ((tonumber(months) or 0) * 30 * 86400)
                               + ((tonumber(days) or 0) * 86400)
                               + ((tonumber(hours) or 0) * 3600)
                    end
                    local computedTimestamp = ageSec and (time() - ageSec) or (time() - ((numMoneyTx - i) * 1800))
                    local dayKey = date("%Y-%m-%d", computedTimestamp)
                    local tupleKey = string.format("money:%s:%s:%d:%s", txDir, normName, copper, dayKey)

                    snapshotCounts[tupleKey] = (snapshotCounts[tupleKey] or 0) + 1
                    local occIdx = snapshotCounts[tupleKey]

                    table.insert(txDataList, {
                        index = i,
                        txDir = txDir,
                        isDeposit = isDeposit,
                        isWithdraw = isWithdraw,
                        normName = normName,
                        copper = copper,
                        computedTimestamp = computedTimestamp,
                        dayKey = dayKey,
                        tupleKey = tupleKey,
                        occIdx = occIdx
                    })
                end
            end
        end
    end

    for _, data in ipairs(txDataList) do
        local existingCount = 0
        for _, existingTx in pairs(VM.db.ledger) do
            if not existingTx.deleted and existingTx.player == data.normName and existingTx.type == data.txDir and (existingTx.itemLink == "GOLD" or existingTx.itemID == 0) and ((existingTx.unitPriceAtTime or 0) * (existingTx.count or 1)) == data.copper then
                local exDay = date("%Y-%m-%d", existingTx.timestamp or 0)
                if exDay == data.dayKey or math.abs((existingTx.timestamp or 0) - data.computedTimestamp) <= 86400 then
                    existingCount = existingCount + 1
                end
            end
        end

        local sig = string.format("v142_m:%s:%s:%d:%s:%d", data.txDir, data.normName, data.copper, data.dayKey, data.occIdx)
        if not VM.db.processedBankLogs[sig] then
            local totalAllowed = snapshotCounts[data.tupleKey] or 1
            if existingCount < totalAllowed then
                VM.db.processedBankLogs[sig] = true
                if data.isDeposit then
                    -- Trade-to-Bank Auto-Attribution
                    local attributedTo = data.normName
                    local rawSender = data.normName
                    if VM.pendingTradePayments and #VM.pendingTradePayments > 0 then
                        local cutoff = time() - 600
                        for idx = #VM.pendingTradePayments, 1, -1 do
                            local p = VM.pendingTradePayments[idx]
                            if p.timestamp < cutoff then
                                table.remove(VM.pendingTradePayments, idx)
                            elseif p.amount == data.copper then
                                attributedTo = p.payer
                                rawSender = data.normName
                                table.remove(VM.pendingTradePayments, idx)
                                VM:Print(string.format("Auto-attributed %s gold deposit to |cffffff00%s|r (from recent trade).",
                                    VM:FormatMoney(data.copper), attributedTo))
                                break
                            end
                        end
                    end

                    local tx = VM.Ledger:RecordGoldDeposit(attributedTo, data.copper, "BANK_MONEY_LOG", rawSender)
                    if tx then
                        tx.isFFA = false
                    end

                    if attributedTo == data.normName and data.normName == VM:GetPlayerName() and VM:IsOfficer() then
                        VM:Print(string.format("Gold deposit of %s recorded. Use 'Reassign' in the Ledger if this was paid by another member.",
                            VM:FormatMoney(data.copper)))
                    end
                else
                    local tx = VM.Ledger:RecordGoldWithdrawal(data.normName, data.copper, "BANK_MONEY_LOG")
                    if tx then
                        tx.isFFA = false
                    end
                end
                addedCount = addedCount + 1
                existingCount = existingCount + 1
            end
        end
    end

    if addedCount > 0 then
        VM.Comms:BroadcastLedgerSync()
        if VM.UI then VM.UI:RefreshAll() end
    end
    return addedCount
end
