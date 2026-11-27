local _, VM = ...
VM.BankScanner = {}
local Scanner = VM.BankScanner

local MAX_SLOTS_PER_TAB = 98
local lastScanTime = 0
local SCAN_COOLDOWN = 2.0
local isScanning = false
local ignoreEventsUntil = 0
local suppressChatPrint = false
local pendingRetries = 0

local bankIsOpen = false
local lastObservedNumTabs = 0
local lastObservedNextTabCost = 0
local lastObservedBankMoney = 0
local lastBankMoneyDrop = { amount = 0, at = 0 }

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

-- Scan watchdog timeout frame to guarantee Scan Complete transition
local scanTimeoutFrame = CreateFrame("Frame")
local scanTimeoutLeft = 0
scanTimeoutFrame:Hide()
scanTimeoutFrame:SetScript("OnUpdate", function(self, elapsed)
    scanTimeoutLeft = scanTimeoutLeft - elapsed
    if scanTimeoutLeft <= 0 then
        self:Hide()
        if Scanner.scanState == "SCANNING" or isScanning then
            VM:LogDebug("BankScanner: Scan watchdog timeout reached; completing scan.")
            isScanning = false
            scanDebounceFrame:Hide()
            rescanFrame:Hide()
            Scanner.scanState = "COMPLETE"
            if VM.UI and VM.UI.UpdateScanStatusButton then
                VM.UI:UpdateScanStatusButton()
            end
        end
    end
end)

local function IsSameActor(a, b)
    local na = VM:NormalizeName(a)
    local nb = VM:NormalizeName(b)
    if na == "" or nb == "" then return false end
    local la, lb = na:lower(), nb:lower()
    if la == lb then return true end
    if not la:find("%s") and lb:sub(1, #la + 1) == (la .. " ") then return true end
    if not lb:find("%s") and la:sub(1, #lb + 1) == (lb .. " ") then return true end
    return false
end

local function BuildFulfillmentRawSenderMap()
    local byReq = {}
    for _, tx in pairs(VM.db and VM.db.ledger or {}) do
        if tx and not tx.deleted and tx.fulfillmentId and tx.fulfillmentId ~= "" then
            byReq[tx.fulfillmentId] = byReq[tx.fulfillmentId] or {}
            local actor = tx.rawSender or tx.player
            if actor and actor ~= "" then
                table.insert(byReq[tx.fulfillmentId], actor)
            end
        end
    end
    return byReq
end

local function HasLedgerActorForReq(byReq, reqID, actor)
    local list = byReq and reqID and byReq[reqID]
    if not list then return false end
    for _, a in ipairs(list) do
        if IsSameActor(a, actor) then
            return true
        end
    end
    return false
end

-- Collects officer withdrawals already accounted for by PREPARED or FULFILLED requests
-- (including officer self-alt BANK fulfillments where ledger rawSender is the alt, not the officer).
local function BuildAccountedOfficerItemPool(now)
    local pool = {}
    local WINDOW = 259200
    local byReq = BuildFulfillmentRawSenderMap()

    for _, req in pairs(VM.db and VM.db.requests or {}) do
        if req and not req.isGoldRequest then
            local actor = nil
            if req.status == "PREPARED" and req.preparedBy and req.preparedBy ~= "" then
                actor = req.preparedBy
            elseif req.status == "FULFILLED" then
                local refTs = req.completedAt or req.updatedAt or 0
                if refTs == 0 or math.abs(now - refTs) <= WINDOW then
                    local off = (req.completedMethod == "BANK")
                        and req.fulfilledBy
                        or ((req.preparedBy and req.preparedBy ~= "") and req.preparedBy or req.fulfilledBy)
                    if off and off ~= "" and not IsSameActor(off, req.requester) and not HasLedgerActorForReq(byReq, req.id, off) then
                        actor = off
                    end
                end
            end
            if actor then
                local itemKey = VM:NormalizeItemKey(req.itemID, req.itemLink, req.itemName)
                table.insert(pool, {
                    actor = actor,
                    itemKey = itemKey,
                    remaining = tonumber(req.count) or 1,
                })
            end
        end
    end
    return pool
end

local function ConsumeAccountedOfficerItem(pool, actor, itemKey, count)
    local qty = tonumber(count) or 1
    for _, entry in ipairs(pool) do
        if entry.remaining >= qty and entry.itemKey == itemKey and IsSameActor(entry.actor, actor) then
            entry.remaining = entry.remaining - qty
            return true
        end
    end
    return false
end

local function BuildAccountedOfficerGoldPool(now)
    local pool = {}
    local WINDOW = 259200
    local byReq = BuildFulfillmentRawSenderMap()

    for _, req in pairs(VM.db and VM.db.requests or {}) do
        if req and req.isGoldRequest then
            local actor = nil
            if req.status == "PREPARED" and req.preparedBy and req.preparedBy ~= "" then
                actor = req.preparedBy
            elseif req.status == "FULFILLED" then
                local refTs = req.completedAt or req.updatedAt or 0
                if refTs == 0 or math.abs(now - refTs) <= WINDOW then
                    local off = (req.completedMethod == "BANK")
                        and req.fulfilledBy
                        or ((req.preparedBy and req.preparedBy ~= "") and req.preparedBy or req.fulfilledBy)
                    if off and off ~= "" and not IsSameActor(off, req.requester) and not HasLedgerActorForReq(byReq, req.id, off) then
                        actor = off
                    end
                end
            end
            if actor then
                local amt = tonumber(req.goldAmount or req.quotedTotalPrice or req.quotedUnitPrice) or 0
                if amt > 0 then
                    table.insert(pool, {
                        actor = actor,
                        amount = amt,
                        used = false,
                    })
                end
            end
        end
    end
    return pool
end

local function ConsumeAccountedOfficerGold(pool, actor, copper)
    for _, entry in ipairs(pool) do
        if not entry.used and entry.amount == copper and IsSameActor(entry.actor, actor) then
            entry.used = true
            return true
        end
    end
    return false
end

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

        if event == "GUILDBANKFRAME_CLOSED" then
            bankIsOpen = false
            isScanning = false
            pendingRetries = 0
            lastBankMoneyDrop = { amount = 0, at = 0 }
            scanDebounceFrame:Hide()
            rescanFrame:Hide()
            scanTimeoutFrame:Hide()
            if self.scanState == "SCANNING" then
                self.scanState = "READY"
            end
            if VM.UI and VM.UI.UpdateScanStatusButton then
                VM.UI:UpdateScanStatusButton()
            end
            return
        end

        if event == "GUILDBANKFRAME_OPENED" then
            bankIsOpen = true
            lastObservedNumTabs = (GetNumGuildBankTabs and GetNumGuildBankTabs()) or 0
            lastObservedNextTabCost = (GetGuildBankTabCost and GetGuildBankTabCost()) or 0
            lastObservedBankMoney = (GetGuildBankMoney and GetGuildBankMoney()) or 0
            lastBankMoneyDrop = { amount = 0, at = 0 }
            if VM:IsOfficer() and VM.Fulfillment then
                VM.Fulfillment:OnGuildBankOpened()
            end
            suppressChatPrint = false
            self:RequestAllTabsAndLogs()
            self:TriggerDebouncedScan(true)
            return
        end

        if event == "GUILDBANK_UPDATE_MONEY" and bankIsOpen and GetGuildBankMoney then
            local curMoney = GetGuildBankMoney() or 0
            if lastObservedBankMoney > 0 and curMoney >= 0 and curMoney < lastObservedBankMoney then
                lastBankMoneyDrop = { amount = lastObservedBankMoney - curMoney, at = GetTime() }
            end
            if curMoney >= 0 then
                lastObservedBankMoney = curMoney
            end
        end

        -- Detect newly purchased Guild Bank Tab live ONLY if Guild Bank gold actually dropped by the tab cost
        if event == "GUILDBANK_UPDATE_TABS" and bankIsOpen and GetNumGuildBankTabs then
            local curTabs = GetNumGuildBankTabs() or 0
            if lastObservedNumTabs > 0 and curTabs > lastObservedNumTabs then
                local cost = tonumber(lastObservedNextTabCost) or 0
                local curMoney = (GetGuildBankMoney and GetGuildBankMoney()) or lastObservedBankMoney
                local bankPaidDirect = (cost > 0) and (
                    (lastObservedBankMoney - curMoney == cost)
                    or (lastBankMoneyDrop.amount == cost and (GetTime() - (lastBankMoneyDrop.at or 0)) <= 1.5)
                )
                if bankPaidDirect and VM.Ledger and VM.Ledger.RecordTabPurchase then
                    local serverNow = (GetServerTime and GetServerTime()) or time()
                    VM.Ledger:RecordTabPurchase(cost, VM:GetPlayerName(), serverNow, curTabs)
                    lastBankMoneyDrop = { amount = 0, at = 0 }
                    VM:Print(string.format("Recorded Guild Bank Tab %d purchase (%s) under GUILD (Tabs).", curTabs, VM:FormatMoney(cost)))
                end
                if curMoney >= 0 then
                    lastObservedBankMoney = curMoney
                end
            end
            if curTabs > 0 then
                lastObservedNumTabs = curTabs
                lastObservedNextTabCost = (GetGuildBankTabCost and GetGuildBankTabCost()) or 0
            end
        end

        if VM.Fulfillment and VM.Fulfillment.isWithdrawing then
            return
        end

        if isScanning or GetTime() < ignoreEventsUntil then
            return
        end

        if event == "GUILDBANKBAGSLOTS_CHANGED" or event == "GUILDBANK_UPDATE_TABS" or event == "GUILDBANKLOG_UPDATE" or event == "GUILDBANK_UPDATE_MONEY" then
            suppressChatPrint = true
            self:TriggerDebouncedScan(false)
        end
    end)
end

function Scanner:TriggerDebouncedScan(isFinal)
    if VM.Fulfillment and VM.Fulfillment.isWithdrawing then return end
    self.scanState = "SCANNING"
    isScanning = true
    ignoreEventsUntil = GetTime() + 2.0
    if isFinal then
        scanDebounceIsFinal = true
    end
    scanDebounceTimeLeft = 0.75
    scanDebounceFrame:Show()
    scanTimeoutLeft = 4.0
    scanTimeoutFrame:Show()
    if VM.UI and VM.UI.UpdateScanStatusButton then
        VM.UI:UpdateScanStatusButton()
    end
end

-- Called by Fulfillment immediately after a Prepare withdrawal finishes so stock refreshes cleanly
function Scanner:SchedulePostWithdrawScan()
    if not bankIsOpen or not (GuildBankFrame and GuildBankFrame:IsVisible()) then return end
    if VM.Fulfillment and VM.Fulfillment.isWithdrawing then return end
    ignoreEventsUntil = 0
    isScanning = false
    suppressChatPrint = true
    self:RequestAllTabsAndLogs()
    self:TriggerDebouncedScan(false)
end

function Scanner:RequestAllTabsAndLogs()
    if VM.Fulfillment and VM.Fulfillment.isWithdrawing then return end
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
    if VM.Fulfillment and VM.Fulfillment.isWithdrawing then
        VM:Print("Please wait for the active withdrawal to finish before scanning.")
        return
    end
    local now = time()
    if (now - lastScanTime) < SCAN_COOLDOWN then
        VM:Print("Please wait a moment before scanning again.")
        return
    end
    lastScanTime = now

    suppressChatPrint = false
    self:RequestAllTabsAndLogs()
    self:TriggerDebouncedScan(true)
end

function Scanner:RunFullScanPass(isFinal)
    if VM.Fulfillment and VM.Fulfillment.isWithdrawing then
        scanDebounceIsFinal = isFinal
        scanDebounceTimeLeft = 0.5
        scanDebounceFrame:Show()
        return
    end

    isScanning = true
    ignoreEventsUntil = GetTime() + 2.0
    scanDebounceFrame:Hide()
    scanTimeoutFrame:Hide()

    local itemCount = 0
    local logsAdded = 0
    local moneyAdded = 0

    local ok1, res1 = pcall(function() return self:ScanBank() end)
    if ok1 then itemCount = res1 or 0 else VM:LogDebug("ScanBank error: " .. tostring(res1)) end

    local ok2, res2 = pcall(function() return self:ScanLogs() end)
    if ok2 then logsAdded = res2 or 0 else VM:LogDebug("ScanLogs error: " .. tostring(res2)) end

    local ok3, res3 = pcall(function() return self:ScanMoneyLogs() end)
    if ok3 then moneyAdded = res3 or 0 else VM:LogDebug("ScanMoneyLogs error: " .. tostring(res3)) end

    self.scanState = "COMPLETE"
    isScanning = false
    ignoreEventsUntil = GetTime() + 2.0

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
            lastObservedBankMoney = m
        end
    end

    if hasPendingItems and pendingRetries < 2 then
        pendingRetries = pendingRetries + 1
        VM:LogDebug(string.format("ScanBank detected occupied slots with missing item info; scheduling delayed re-scan (%d/2).", pendingRetries))
        self.scanState = "STALE"
        rescanTimeLeft = 0.75
        rescanFrame:Show()
        if bankMoney > 0 and VM.db.inventory then
            VM.db.inventory.gold = bankMoney
        end
        return 0
    end
    pendingRetries = 0

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
    local pName = UnitName("player") or VM:GetPlayerName()
    VM.db.inventory = {
        lastScan = serverTime,
        lastScanTime = serverTime,
        lastScanBy = pName,
        scannedBy = pName,
        lastSyncedFrom = nil,
        gold = bankMoney,
        numTabs = numTabs,
        tabs = newTabs
    }
    if VM.db.scanMetadata then
        VM.db.scanMetadata.lastScan = serverTime
        VM.db.scanMetadata.lastScanTime = serverTime
        VM.db.scanMetadata.lastScanBy = pName
        VM.db.scanMetadata.scannedBy = pName
    end

    VM.Comms:BroadcastInventory()
    if VM.UI then VM.UI:RefreshAll() end
    return uniqueItemsCount
end

function Scanner:ScanLogs()
    local numTabs = GB_API.GetNumTabs()
    local addedCount = 0
    local bankLogEntries = {}
    local snapshotCounts = {}
    local minLogTs, maxLogTs = nil, nil
    local now = (GetServerTime and GetServerTime()) or time()
    local isOfficer = VM:IsOfficer()
    local officerItemPool = BuildAccountedOfficerItemPool(now)

    for tab = 1, numTabs do
        local numTx = GB_API.GetNumTransactions(tab)
        local rule = VM:GetTabRule(tab)
        local isFFA = (rule.mode == "FREE")

        -- Traverse oldest to newest so occurrence indices match chronological order
        for i = numTx, 1, -1 do
            local txType, name, itemLink, count, tab1, tab2, year, month, day, hour = GB_API.GetTransaction(tab, i)
            if name and name:find("%[") and not (itemLink and itemLink:find("%[")) then
                local temp = name
                name = itemLink
                itemLink = temp
            end
            local typeStr = tostring(txType or ""):lower()
            local isDeposit = (typeStr:find("deposit") or typeStr == "1")
            local isRawWithdraw = (typeStr:find("withdraw") or typeStr == "2" or typeStr:find("take"))

            if isDeposit or isRawWithdraw then
                local cleanLink = itemLink or "[Unknown Item]"
                local itemID = tonumber(cleanLink and cleanLink:match("item:(%d+)")) or 0
                local extractedName = cleanLink:match("%[(.-)%]") or cleanLink:gsub("^%[", ""):gsub("%]$", "")
                local normName = VM:NormalizeActor(name)
                count = tonumber(count) or 1

                local matchesApproved = false
                if isRawWithdraw and isOfficer and VM.Fulfillment and VM.Fulfillment.FindMatchingApprovedRequest then
                    if VM.Fulfillment:FindMatchingApprovedRequest(normName, itemID, extractedName, count, 0) then
                        matchesApproved = true
                    end
                end

                if isDeposit or isFFA or matchesApproved then
                    local hasTime = (year ~= nil or month ~= nil or day ~= nil or hour ~= nil)
                    local computedTimestamp
                    if hasTime then
                        local ageSec = (tonumber(year) or 0) * 31536000
                                     + (tonumber(month) or 0) * 2592000
                                     + (tonumber(day) or 0) * 86400
                                     + (tonumber(hour) or 0) * 3600
                        computedTimestamp = now - ageSec
                    else
                        computedTimestamp = now - ((numTx - i) * 1800)
                    end

                    if not minLogTs or computedTimestamp < minLogTs then minLogTs = computedTimestamp end
                    if not maxLogTs or computedTimestamp > maxLogTs then maxLogTs = computedTimestamp end

                    local txDir = isDeposit and "IN" or "OUT"
                    local itemKey = VM:NormalizeItemKey(itemID, cleanLink, extractedName)
                    local matchKey = string.format("ITEM:%s:%s:%s:%d", txDir, normName, itemKey, count)
                    snapshotCounts[matchKey] = (snapshotCounts[matchKey] or 0) + 1

                    table.insert(bankLogEntries, {
                        tab = tab,
                        rule = rule,
                        txDir = txDir,
                        isDeposit = isDeposit,
                        normName = normName,
                        itemID = itemID,
                        itemKey = itemKey,
                        cleanLink = cleanLink,
                        itemName = extractedName,
                        count = count,
                        computedTimestamp = computedTimestamp,
                        matchKey = matchKey,
                        occIndex = snapshotCounts[matchKey],
                        isFFA = isFFA
                    })
                end
            end
        end
    end

    local WINDOW_72H = 259200 -- 72-hour rolling deduplication window
    local existingCounts = {}

    if VM.db and VM.db.ledger then
        for _, exTx in pairs(VM.db.ledger) do
            if exTx and not exTx.deleted and exTx.timestamp then
                local isGold = (exTx.itemID == 0 or exTx.itemLink == "GOLD" or exTx.source == "BANK_MONEY_LOG" or exTx.source == "MANUAL_GOLD" or (exTx.itemName and (exTx.itemName:find("Gold Deposit") or exTx.itemName:find("Gold Withdrawal"))))
                if not isGold then
                    local exDir = VM:NormalizeAction(exTx.type)
                    local exActor = VM:NormalizeActor(exTx.rawSender or exTx.player)
                    local exItemKey = VM:NormalizeItemKey(exTx.itemID, exTx.itemLink, exTx.itemName)
                    local exCount = tonumber(exTx.count or 1)
                    local exKey = string.format("ITEM:%s:%s:%s:%d", exDir, exActor, exItemKey, exCount)

                    local inWindow = (math.abs(now - exTx.timestamp) <= WINDOW_72H)
                    if not inWindow and minLogTs and maxLogTs then
                        if exTx.timestamp >= (minLogTs - WINDOW_72H) and exTx.timestamp <= (maxLogTs + WINDOW_72H) then
                            inWindow = true
                        end
                    end

                    if inWindow then
                        existingCounts[exKey] = (existingCounts[exKey] or 0) + 1
                    end
                end
            end
        end
    end

    for _, entry in ipairs(bankLogEntries) do
        local existingM = existingCounts[entry.matchKey] or 0
        if entry.occIndex > existingM then
            if entry.isDeposit then
                local activeRet = VM.db.activeReturn
                if activeRet and (entry.itemID == activeRet.itemID or (entry.itemID == 0 and entry.cleanLink == activeRet.itemLink)) then
                    VM.Ledger:RecordReturnDeposit(entry.normName, entry.itemID, entry.cleanLink, entry.count, activeRet.fulfillmentId, entry.computedTimestamp)
                else
                    VM.Ledger:RecordDeposit(entry.normName, entry.itemID, entry.cleanLink, entry.count, "BANK_LOG", entry.computedTimestamp, entry.tab, entry.isFFA)
                end
                existingCounts[entry.matchKey] = existingM + 1
                addedCount = addedCount + 1
            else
                local matchedReq = nil
                if isOfficer and VM.Fulfillment and VM.Fulfillment.FindMatchingApprovedRequest then
                    matchedReq = VM.Fulfillment:FindMatchingApprovedRequest(entry.normName, entry.itemID, entry.itemName, entry.count, 0)
                end

                local ahPrice = VM:GetEffectiveLivePrice(entry.itemID, entry.cleanLink, 0)
                local itemName = entry.itemName or entry.cleanLink:gsub("^%[", ""):gsub("%]$", "")

                if matchedReq then
                    local effMode = matchedReq.priceMode or (entry.rule and entry.rule.mode) or "FREE"
                    local effPct = matchedReq.pricePercent or (entry.rule and entry.rule.percent) or 50
                    local totalCharged = VM:CalculateMemberTotalPrice(ahPrice, entry.count, { mode = effMode, percent = effPct })
                    local unitCharged = (entry.count > 0) and math.floor(totalCharged / entry.count) or totalCharged
                    local targetPlayer = VM:NormalizeName(matchedReq.requester)

                    local tx = {
                        id = string.format("OUT_REQ_%d_%d", time(), math.random(1000, 9999)),
                        type = "OUT",
                        player = targetPlayer,
                        rawSender = entry.normName,
                        attributedTo = targetPlayer,
                        itemID = entry.itemID,
                        itemLink = entry.cleanLink,
                        itemName = itemName,
                        count = entry.count,
                        unitPriceAtTime = ahPrice,
                        chargedUnitPrice = unitCharged,
                        chargedTotalPrice = totalCharged,
                        priceMode = effMode,
                        pricePercent = effPct,
                        isFFA = (effMode == "FREE"),
                        tab = entry.tab,
                        timestamp = entry.computedTimestamp,
                        updatedAt = time(),
                        officer = VM:GetPlayerName(),
                        source = "REQUEST",
                        fulfillmentId = matchedReq.id,
                        recipient = targetPlayer,
                        isManual = false,
                        deleted = false
                    }
                    VM.db.ledger[tx.id] = tx
                    VM.Comms:BroadcastTransaction(tx)
                    VM.Fulfillment:CompleteRequest(matchedReq.id, {
                        skipLedger = true,
                        completedBy = entry.normName,
                        completedAt = entry.computedTimestamp,
                        method = "BANK"
                    })
                    existingCounts[entry.matchKey] = existingM + 1
                    addedCount = addedCount + 1
                elseif ConsumeAccountedOfficerItem(officerItemPool, entry.normName, entry.itemKey, entry.count) then
                    -- Already accounted for by an officer's PREPARED or FULFILLED request
                    existingCounts[entry.matchKey] = existingM + 1
                elseif entry.isFFA then
                    local tx = {
                        id = string.format("OUT_FFA_%d_%d", time(), math.random(1000, 9999)),
                        type = "OUT",
                        player = entry.normName,
                        rawSender = entry.normName,
                        attributedTo = entry.normName,
                        itemID = entry.itemID,
                        itemLink = entry.cleanLink,
                        itemName = itemName,
                        count = entry.count,
                        unitPriceAtTime = ahPrice,
                        chargedUnitPrice = 0,
                        chargedTotalPrice = 0,
                        priceMode = "FREE",
                        timestamp = entry.computedTimestamp,
                        updatedAt = time(),
                        officer = VM:GetPlayerName(),
                        source = "FFA_SCAN",
                        isFFA = true,
                        tab = entry.tab,
                        isManual = false,
                        deleted = false
                    }
                    VM.db.ledger[tx.id] = tx
                    VM.Comms:BroadcastTransaction(tx)
                    existingCounts[entry.matchKey] = existingM + 1
                    addedCount = addedCount + 1
                end
            end
        end
    end

    if addedCount > 0 then
        local serverTime = (GetServerTime and GetServerTime()) or time()
        local pName = UnitName("player") or VM:GetPlayerName()
        if VM.db.inventory then
            if not VM.db.inventory.lastScan or VM.db.inventory.lastScan == 0 then
                VM.db.inventory.lastScan = serverTime
                VM.db.inventory.lastScanTime = serverTime
                VM.db.inventory.lastScanBy = pName
                VM.db.inventory.scannedBy = pName
            end
        end
        if VM.UI then VM.UI:RefreshAll() end
    end
    return addedCount
end

function Scanner:ScanMoneyLogs()
    if GetGuildBankMoney and GetGuildBankMoney() < 0 then
        return 0
    end

    local numMoneyTx = GB_API.GetNumMoneyTransactions()
    local addedCount = 0
    local moneyLogEntries = {}
    local snapshotCounts = {}
    local minLogTs, maxLogTs = nil, nil
    local now = (GetServerTime and GetServerTime()) or time()
    local isOfficer = VM:IsOfficer()
    local officerGoldPool = BuildAccountedOfficerGoldPool(now)

    for i = numMoneyTx, 1, -1 do
        local txType, name, amount, year, month, day, hour = GB_API.GetMoneyTransaction(i)
        local typeStr = tostring(txType or ""):lower()

        -- Filter out guild repairs; capture Guild Bank Tab purchases automatically under GUILD (Tabs)
        if not typeStr:find("repair") then
            local copper = tonumber(amount) or 0
            if copper > 0 then
                local normName = (name and name ~= "") and VM:NormalizeActor(name) or "UNATTRIBUTED"
                local hasTime = (year ~= nil or month ~= nil or day ~= nil or hour ~= nil)
                local computedTimestamp
                if hasTime then
                    local ageSec = (tonumber(year) or 0) * 31536000
                                 + (tonumber(month) or 0) * 2592000
                                 + (tonumber(day) or 0) * 86400
                                 + (tonumber(hour) or 0) * 3600
                    computedTimestamp = now - ageSec
                else
                    computedTimestamp = now - ((numMoneyTx - i) * 1800)
                end

                local isTabBuy = (typeStr:find("buytab") ~= nil) or (typeStr:find("fortab") ~= nil)
                if isTabBuy then
                    if VM.Ledger and VM.Ledger.RecordTabPurchase then
                        local prevCount = 0
                        for _ in pairs(VM.db.ledger or {}) do prevCount = prevCount + 1 end
                        VM.Ledger:RecordTabPurchase(copper, normName, computedTimestamp)
                        local afterCount = 0
                        for _ in pairs(VM.db.ledger or {}) do afterCount = afterCount + 1 end
                        if afterCount > prevCount then
                            addedCount = addedCount + 1
                        end
                    end
                else
                    local isDeposit = (typeStr:find("deposit") or typeStr == "1")
                    local isWithdraw = (typeStr:find("withdraw") or typeStr == "2")

                    if isDeposit or isWithdraw then
                        local txDir = isDeposit and "IN" or "OUT"
                        if not minLogTs or computedTimestamp < minLogTs then minLogTs = computedTimestamp end
                        if not maxLogTs or computedTimestamp > maxLogTs then maxLogTs = computedTimestamp end

                        local matchKey = string.format("GOLD:%s:%s:%d", txDir, normName, copper)
                        snapshotCounts[matchKey] = (snapshotCounts[matchKey] or 0) + 1

                        table.insert(moneyLogEntries, {
                            index = i,
                            txDir = txDir,
                            isDeposit = isDeposit,
                            isWithdraw = isWithdraw,
                            normName = normName,
                            copper = copper,
                            computedTimestamp = computedTimestamp,
                            matchKey = matchKey,
                            occIndex = snapshotCounts[matchKey]
                        })
                    end
                end
            end
        end
    end

    local WINDOW_72H = 259200 -- 72-hour rolling deduplication window
    local existingGoldCounts = {}

    if VM.db and VM.db.ledger then
        for _, exTx in pairs(VM.db.ledger) do
            if exTx and not exTx.deleted and exTx.timestamp and exTx.source ~= "TAB_PURCHASE" then
                local isGold = (exTx.itemID == 0 or exTx.itemLink == "GOLD" or exTx.source == "BANK_MONEY_LOG" or exTx.source == "MANUAL_GOLD" or exTx.source == "GOLD_REQUEST" or exTx.source == "WRITE_OFF" or (exTx.itemName and (exTx.itemName:find("Gold Deposit") or exTx.itemName:find("Gold Withdrawal"))))
                if isGold then
                    local exDir = VM:NormalizeAction(exTx.type)
                    local exActor = VM:NormalizeActor(exTx.rawSender or exTx.player)
                    local exCopper = (exTx.unitPriceAtTime or 0) * (exTx.count or 1)
                    local exKey = string.format("GOLD:%s:%s:%d", exDir, exActor, exCopper)

                    local inWindow = (math.abs(now - exTx.timestamp) <= WINDOW_72H)
                    if not inWindow and minLogTs and maxLogTs then
                        if exTx.timestamp >= (minLogTs - WINDOW_72H) and exTx.timestamp <= (maxLogTs + WINDOW_72H) then
                            inWindow = true
                        end
                    end

                    if inWindow then
                        existingGoldCounts[exKey] = (existingGoldCounts[exKey] or 0) + 1
                    end
                end
            end
        end
    end

    for _, entry in ipairs(moneyLogEntries) do
        local existingM = existingGoldCounts[entry.matchKey] or 0
        if entry.occIndex > existingM then
            if entry.isDeposit then
                -- Trade-to-Bank Auto-Attribution
                local attributedTo = entry.normName
                local rawSender = entry.normName
                if VM.pendingTradePayments and #VM.pendingTradePayments > 0 then
                    local cutoff = time() - 600
                    for idx = #VM.pendingTradePayments, 1, -1 do
                        local p = VM.pendingTradePayments[idx]
                        if p.timestamp < cutoff then
                            table.remove(VM.pendingTradePayments, idx)
                        elseif p.amount == entry.copper then
                            attributedTo = p.payer
                            rawSender = entry.normName
                            table.remove(VM.pendingTradePayments, idx)
                            VM:Print(string.format("Auto-attributed %s gold deposit to |cffffff00%s|r (from recent trade).",
                                VM:FormatMoney(entry.copper), attributedTo))
                            break
                        end
                    end
                end

                local tx = VM.Ledger:RecordGoldDeposit(attributedTo, entry.copper, "BANK_MONEY_LOG", rawSender, attributedTo, entry.computedTimestamp)
                if tx then
                    tx.isFFA = false
                    tx.timestamp = entry.computedTimestamp
                end

                if attributedTo == entry.normName and entry.normName == VM:GetPlayerName() and isOfficer then
                    VM:Print(string.format("Gold deposit of %s recorded. Use 'Reassign' in the Ledger if this was paid by another member.",
                        VM:FormatMoney(entry.copper)))
                end
                existingGoldCounts[entry.matchKey] = existingM + 1
                addedCount = addedCount + 1
            else
                local matchedGoldReq = nil
                if isOfficer and VM.Fulfillment and VM.Fulfillment.FindMatchingApprovedRequest then
                    matchedGoldReq = VM.Fulfillment:FindMatchingApprovedRequest(entry.normName, nil, nil, nil, entry.copper)
                end

                if matchedGoldReq then
                    local tx = VM.Ledger:RecordGoldWithdrawal("GUILD", entry.copper, "GOLD_REQUEST", entry.computedTimestamp, entry.normName, "GUILD", matchedGoldReq.reason, matchedGoldReq.guildCategory or "RAID")
                    if tx then
                        tx.isFFA = false
                        tx.timestamp = entry.computedTimestamp
                        tx.fulfillmentId = matchedGoldReq.id
                    end
                    VM.Fulfillment:CompleteRequest(matchedGoldReq.id, {
                        skipLedger = true,
                        completedBy = entry.normName,
                        completedAt = entry.computedTimestamp,
                        method = "BANK"
                    })
                    existingGoldCounts[entry.matchKey] = existingM + 1
                    addedCount = addedCount + 1
                elseif ConsumeAccountedOfficerGold(officerGoldPool, entry.normName, entry.copper) then
                    -- Already accounted for by an officer's PREPARED or FULFILLED gold request
                    existingGoldCounts[entry.matchKey] = existingM + 1
                else
                    local tx = VM.Ledger:RecordGoldWithdrawal(entry.normName, entry.copper, "BANK_MONEY_LOG", entry.computedTimestamp, entry.normName, entry.normName)
                    if tx then
                        tx.isFFA = false
                        tx.timestamp = entry.computedTimestamp
                    end
                    existingGoldCounts[entry.matchKey] = existingM + 1
                    addedCount = addedCount + 1
                end
            end
        end
    end

    if addedCount > 0 then
        local serverTime = (GetServerTime and GetServerTime()) or time()
        local pName = UnitName("player") or VM:GetPlayerName()
        if VM.db.inventory then
            VM.db.inventory.lastScan = serverTime
            VM.db.inventory.lastScanTime = serverTime
            VM.db.inventory.lastScanBy = pName
            VM.db.inventory.scannedBy = pName
            VM.db.inventory.lastSyncedFrom = nil
            local m = GetGuildBankMoney and GetGuildBankMoney()
            if type(m) == "number" and m >= 0 then
                VM.db.inventory.gold = m
                lastObservedBankMoney = m
            end
        end
        if VM.db.scanMetadata then
            VM.db.scanMetadata.lastScan = serverTime
            VM.db.scanMetadata.lastScanTime = serverTime
            VM.db.scanMetadata.lastScanBy = pName
            VM.db.scanMetadata.scannedBy = pName
        end
        VM.Comms:BroadcastInventory()
        if VM.UI then VM.UI:RefreshAll() end
    end
    return addedCount
end
