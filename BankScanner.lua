local _, VM = ...
VM.BankScanner = {}
local Scanner = VM.BankScanner

local MAX_SLOTS_PER_TAB = 98
local lastScanTime = 0
local SCAN_COOLDOWN = 2.0
local isScanning = false
local isTabSwitching = false
local ignoreSlotEventsUntil = 0
local ignoreLogEventsUntil = 0
local lastMoneyLogQueryAt = 0
local lastItemLogQueryAt = 0
local suppressChatPrint = false
local pendingRetries = 0

local lastObservedNumTabs = 0
local lastObservedNextTabCost = 0
local lastObservedBankMoney = 0
local lastBankMoneyDrop = { amount = 0, at = 0 }

Scanner.isBankOpen = false
Scanner.bankOpenReason = nil
Scanner.lastBankActivityAt = nil
Scanner.scanState = "READY" -- "READY" | "SCANNING" | "COMPLETE" | "STALE"

-- Bank session detection (WoW Forever 1.15.x fires neither GUILDBANKFRAME_OPENED nor
-- PLAYER_INTERACTION_MANAGER_FRAME_SHOW for the Guild Bank, and bag addons hide GuildBankFrame).
-- A session is opened by any Guild Bank server event and closed only by real close signals
-- (CloseGuildBankFrame hook, frame hide, close events, loading screens) or a long idle timeout.
-- No active probing: this server does not reliably answer repeated tab/log queries, and a missed
-- answer must never block withdrawals or money log updates. Actions (Withdraw/Return/Scan) are
-- always attempted directly and verified afterwards.
local IDLE_CLOSE_SEC = 600     -- treat the session as ended after 10 minutes without any bank traffic
local LOGIN_GUARD_SEC = 4      -- ignore bank traffic right after a loading screen
local AUTO_OPEN_SUPPRESS_SEC = 300
local lastBankClosedAt = 0
local lastCloseReason = nil
local loginGuardUntil = 0
local pendingRescan = false
local pendingRescanChain = 0   -- caps back-to-back follow-up scans so echo events can never loop
local moneyFollowupLeft = 0
local closeHooksInstalled = false

local AUTO_LOG_SOURCES = {
    BANK_LOG = true,
    FFA_SCAN = true,
    BANK_MONEY_LOG = true,
    REQUEST = true,
    GOLD_REQUEST = true,
    TRANSFER = true,
}

local PAYMENT_SOURCES = {
    PAYMENT = true,
    MANUAL_ASSIGN_PAYMENT = true,
    DEBT_WRITEOFF = true,
}

function Scanner:IsBankOpen()
    if self.isBankOpen then return true end
    return (GuildBankFrame and GuildBankFrame:IsVisible()) and true or false
end

local function GetMoneyLogTab()
    return (MAX_GUILDBANK_TABS or 8) + 1
end

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
            isTabSwitching = false
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

local function QueryMoneyLogThrottled()
    if not QueryGuildBankLog then return end
    local nowGT = GetTime and GetTime() or 0
    if (nowGT - lastMoneyLogQueryAt) < 0.5 then return end
    lastMoneyLogQueryAt = nowGT
    QueryGuildBankLog(GetMoneyLogTab())
end

local function QueryCurrentTabLogThrottled()
    if not QueryGuildBankLog then return end
    local nowGT = GetTime and GetTime() or 0
    if (nowGT - lastItemLogQueryAt) < 0.5 then return end
    lastItemLogQueryAt = nowGT
    local curTab = (GetCurrentGuildBankTab and GetCurrentGuildBankTab()) or 1
    if curTab and curTab >= 1 then
        QueryGuildBankLog(curTab)
    end
end

function Scanner:GetScanStatus()
    local isBankOpen = self:IsBankOpen()
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

-- Heartbeat: idle timeout, visible-frame keepalive and money-log follow-ups (no server probing)
local heartbeatFrame = CreateFrame("Frame")
heartbeatFrame:Hide()
local heartbeatAccum = 0
heartbeatFrame:SetScript("OnUpdate", function(selfFrame, elapsed)
    if moneyFollowupLeft > 0 then
        moneyFollowupLeft = moneyFollowupLeft - elapsed
        if moneyFollowupLeft <= 0 then
            moneyFollowupLeft = 0
            if QueryGuildBankLog then
                lastMoneyLogQueryAt = GetTime()
                QueryGuildBankLog(GetMoneyLogTab())
            end
            Scanner:TriggerDebouncedScan(false, 0.9)
        end
    end

    heartbeatAccum = heartbeatAccum + elapsed
    if heartbeatAccum < 1 then return end
    heartbeatAccum = 0

    if not Scanner.isBankOpen then
        if moneyFollowupLeft <= 0 then selfFrame:Hide() end
        return
    end
    local now = GetTime()
    if GuildBankFrame and GuildBankFrame:IsVisible() then
        Scanner.lastBankActivityAt = now
    end
    if (now - (Scanner.lastBankActivityAt or now)) > IDLE_CLOSE_SEC then
        Scanner:SetBankOpen(false, "idle")
    end
end)

-- Kept for compatibility: actions no longer wait for a probe, they are attempted and verified.
function Scanner:EnsureBankOpen(callback)
    if callback then callback(true) end
end

-- Called for every Guild Bank server event. Any of them proves the bank is reachable.
-- quiet = open the session without auto-opening the window (money/tab updates).
function Scanner:MarkBankActivity(reason, quiet)
    if VM.isUnguilded or not IsInGuild() then return end
    local now = GetTime()
    if not self.isBankOpen and now < loginGuardUntil then return end
    self.lastBankActivityAt = now
    if not self.isBankOpen then
        self:SetBankOpen(true, reason, quiet)
    end
end

function Scanner:SetBankOpen(open, reason, quiet)
    if open then
        if self.isBankOpen then return end
        self.isBankOpen = true
        self.bankOpenReason = reason
        self.lastBankActivityAt = GetTime()
        VM:LogDebug("BankScanner: bank session OPEN (" .. tostring(reason) .. ")")
        lastObservedNumTabs = (GetNumGuildBankTabs and GetNumGuildBankTabs()) or 0
        lastObservedNextTabCost = (GetGuildBankTabCost and GetGuildBankTabCost()) or 0
        lastObservedBankMoney = (GetGuildBankMoney and GetGuildBankMoney()) or 0
        lastBankMoneyDrop = { amount = 0, at = 0 }
        heartbeatFrame:Show()

        -- No window pop-up for quiet (money/tab) openings or right after an idle timeout at the same bank
        local suppressAuto = quiet or ((lastCloseReason == "idle") and ((GetTime() - lastBankClosedAt) < AUTO_OPEN_SUPPRESS_SEC))
        self.sessionOpenedAt = GetTime()
        self.sessionId = (self.sessionId or 0) + 1
        if suppressAuto then
            VM:LogDebug("AutoOpen: suppressed (" .. (quiet and "quiet open" or "recent idle close") .. ")")
        elseif VM.Fulfillment and VM.Fulfillment.OnGuildBankOpened then
            -- Several attempts: bank/bag addons may hide or re-show frames during the first second
            local sid = self.sessionId
            local openedAt = self.sessionOpenedAt
            local function TryAutoOpen(attempt)
                if Scanner.sessionId ~= sid then return end
                VM.Fulfillment:OnGuildBankOpened(attempt, openedAt)
            end
            if C_Timer and C_Timer.After then
                C_Timer.After(0.25, function() TryAutoOpen(1) end)
                C_Timer.After(1.5, function() TryAutoOpen(2) end)
                C_Timer.After(3.0, function() TryAutoOpen(3) end)
            else
                TryAutoOpen(1)
            end
        end

        suppressChatPrint = false
        pendingRescanChain = 0
        self:RequestAllTabsAndLogs()
        self:TriggerDebouncedScan(true, 0.75)
    else
        if not self.isBankOpen then return end
        self.isBankOpen = false
        self.bankOpenReason = nil
        lastBankClosedAt = GetTime()
        lastCloseReason = reason
        VM:LogDebug("BankScanner: bank session CLOSED (" .. tostring(reason) .. ")")
        isScanning = false
        isTabSwitching = false
        pendingRetries = 0
        pendingRescan = false
        moneyFollowupLeft = 0
        lastBankMoneyDrop = { amount = 0, at = 0 }
        scanDebounceFrame:Hide()
        rescanFrame:Hide()
        scanTimeoutFrame:Hide()
        if self.scanState == "SCANNING" then
            self.scanState = "READY"
        end
        if VM.Fulfillment and VM.Fulfillment.OnGuildBankClosed then
            VM.Fulfillment:OnGuildBankClosed()
        end
        if VM.UI and VM.UI.UpdateScanStatusButton then
            VM.UI:UpdateScanStatusButton()
        end
    end
end

local function HookGuildBankFrame()
    if GuildBankFrame and not GuildBankFrame.__vmHooked and GuildBankFrame.HookScript then
        GuildBankFrame.__vmHooked = true
        GuildBankFrame:HookScript("OnShow", function() Scanner:MarkBankActivity("frame-show", false) end)
        GuildBankFrame:HookScript("OnHide", function()
            -- Bag/bank addons (Bagnon, ElvUI, ...) hide the default frame right after it opens and show
            -- their own: that is not the bank closing. Only a later hide counts as a close.
            if Scanner.isBankOpen and (GetTime() - (Scanner.sessionOpenedAt or 0)) < 3 then
                VM:LogDebug("BankScanner: GuildBankFrame hidden right after opening (bag addon) - session kept")
                return
            end
            Scanner:SetBankOpen(false, "frame-hide")
        end)
    end
end

function Scanner:InstallCloseHooks()
    if closeHooksInstalled then return end
    closeHooksInstalled = true
    if hooksecurefunc and type(CloseGuildBankFrame) == "function" then
        hooksecurefunc("CloseGuildBankFrame", function()
            Scanner:SetBankOpen(false, "CloseGuildBankFrame")
        end)
    end
    HookGuildBankFrame()
end

local function SafeRegister(frame, event)
    local ok = pcall(frame.RegisterEvent, frame, event)
    if not ok then
        VM:LogDebug("BankScanner: event not available on this client: " .. tostring(event))
    end
    return ok
end

local function IsGuildBankerInteraction(arg)
    local guildBanker = (Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.GuildBanker) or 10
    return arg == guildBanker
end

function Scanner:Init()
    local f = CreateFrame("Frame")
    SafeRegister(f, "GUILDBANKFRAME_OPENED")
    SafeRegister(f, "GUILDBANKFRAME_CLOSED")
    SafeRegister(f, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
    SafeRegister(f, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
    SafeRegister(f, "GUILDBANKBAGSLOTS_CHANGED")
    SafeRegister(f, "GUILDBANKLOG_UPDATE")
    SafeRegister(f, "GUILDBANK_UPDATE_MONEY")
    SafeRegister(f, "GUILDBANK_UPDATE_WITHDRAWMONEY")
    SafeRegister(f, "GUILDBANK_UPDATE_TABS")
    SafeRegister(f, "PLAYER_ENTERING_WORLD")
    SafeRegister(f, "ADDON_LOADED")

    self:InstallCloseHooks()
    loginGuardUntil = GetTime() + LOGIN_GUARD_SEC

    f:SetScript("OnEvent", function(_, event, arg1)
        if event == "ADDON_LOADED" then
            if arg1 == "Blizzard_GuildBankUI" then HookGuildBankFrame() end
            return
        end
        if event == "PLAYER_ENTERING_WORLD" then
            loginGuardUntil = GetTime() + LOGIN_GUARD_SEC
            if self.isBankOpen then self:SetBankOpen(false, "loading-screen") end
            return
        end
        if VM.isUnguilded then return end
        VM:LogDebug("BankScanner event: " .. tostring(event) .. (arg1 ~= nil and (" " .. tostring(arg1)) or ""))


        if event == "GUILDBANKFRAME_CLOSED" then
            self:SetBankOpen(false, event)
            return
        end
        if event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
            if IsGuildBankerInteraction(arg1) then self:SetBankOpen(false, event) end
            return
        end
        if event == "GUILDBANKFRAME_OPENED" then
            self:MarkBankActivity(event, false)
            return
        end
        if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
            if IsGuildBankerInteraction(arg1) then self:MarkBankActivity(event, false) end
            return
        end

        -- Every Guild Bank event opens/renews the session. Slot/log answers come from opening the
        -- bank (window may auto-open); money/tab updates open it quietly.
        local quiet = not (event == "GUILDBANKBAGSLOTS_CHANGED" or event == "GUILDBANKLOG_UPDATE")
        local wasOpen = self.isBankOpen
        self:MarkBankActivity(event, quiet)
        if not self.isBankOpen then return end
        if not wasOpen then
            -- SetBankOpen already requested all tabs/logs and scheduled the initial scan
            return
        end

        if event == "GUILDBANK_UPDATE_MONEY" or event == "GUILDBANK_UPDATE_WITHDRAWMONEY" then
            if event == "GUILDBANK_UPDATE_MONEY" and GetGuildBankMoney then
                local curMoney = GetGuildBankMoney() or 0
                if lastObservedBankMoney > 0 and curMoney >= 0 and curMoney < lastObservedBankMoney then
                    lastBankMoneyDrop = { amount = lastObservedBankMoney - curMoney, at = GetTime() }
                end
                if curMoney >= 0 then
                    lastObservedBankMoney = curMoney
                end
            end
            if VM.Fulfillment and VM.Fulfillment.isWithdrawing then
                pendingRescan = true
                return
            end
            -- Fetch the money log now and once more shortly after: the server often answers the
            -- first query with the pre-transaction log.
            QueryMoneyLogThrottled()
            suppressChatPrint = true
            pendingRescanChain = 0
            self:TriggerDebouncedScan(false, 0.65)
            moneyFollowupLeft = 2.0
            heartbeatFrame:Show()
            return
        end

        -- Detect newly purchased Guild Bank Tab live ONLY if Guild Bank gold actually dropped by the tab cost
        if event == "GUILDBANK_UPDATE_TABS" and GetNumGuildBankTabs then
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
            pendingRescan = true
            return
        end

        if event == "GUILDBANKBAGSLOTS_CHANGED" then
            if isTabSwitching then return end
            if GetTime() < ignoreSlotEventsUntil or isScanning then
                pendingRescan = true
                return
            end
            QueryCurrentTabLogThrottled()
            suppressChatPrint = true
            pendingRescanChain = 0
            self:TriggerDebouncedScan(false, 0.65)
        elseif event == "GUILDBANK_UPDATE_TABS" then
            if isTabSwitching or isScanning then
                pendingRescan = true
                return
            end
            suppressChatPrint = true
            self:TriggerDebouncedScan(false, 0.65)
        elseif event == "GUILDBANKLOG_UPDATE" then
            -- Never drop a log answer: if it lands during/just after a scan, rescan afterwards
            if isScanning or GetTime() < ignoreLogEventsUntil then
                pendingRescan = true
                return
            end
            suppressChatPrint = true
            self:TriggerDebouncedScan(false, 0.55)
        end
    end)
end

function Scanner:TriggerDebouncedScan(isFinal, delaySec)
    if VM.Fulfillment and VM.Fulfillment.isWithdrawing then return end
    self.scanState = "SCANNING"
    if isFinal then
        scanDebounceIsFinal = true
    end
    scanDebounceTimeLeft = delaySec or 0.75
    scanDebounceFrame:Show()
    scanTimeoutLeft = 4.0
    scanTimeoutFrame:Show()
    if VM.UI and VM.UI.UpdateScanStatusButton then
        VM.UI:UpdateScanStatusButton()
    end
end

-- Called by Fulfillment immediately after a Prepare withdrawal finishes so stock and logs refresh cleanly
function Scanner:SchedulePostWithdrawScan()
    if VM.Fulfillment and VM.Fulfillment.isWithdrawing then return end
    ignoreSlotEventsUntil = 0
    ignoreLogEventsUntil = 0
    isScanning = false
    pendingRescan = false
    suppressChatPrint = true
    self:RequestAllTabsAndLogs()
    self:TriggerDebouncedScan(false, 0.65)
    moneyFollowupLeft = 2.0
    heartbeatFrame:Show()
end

function Scanner:RequestAllTabsAndLogs()
    if VM.Fulfillment and VM.Fulfillment.isWithdrawing then return end
    local numTabs = GB_API.GetNumTabs()
    local origTab = (GetCurrentGuildBankTab and GetCurrentGuildBankTab()) or 1
    isTabSwitching = true
    ignoreSlotEventsUntil = GetTime() + 0.8
    ignoreLogEventsUntil = GetTime() + 0.8
    VM:LogDebug(string.format("RequestAllTabsAndLogs: %d tabs", numTabs))
    for tab = 1, numTabs do
        if SetCurrentGuildBankTab then SetCurrentGuildBankTab(tab) end
        if QueryGuildBankTab then QueryGuildBankTab(tab) end
        if QueryGuildBankLog then QueryGuildBankLog(tab) end
    end
    if origTab and origTab >= 1 and origTab <= numTabs and SetCurrentGuildBankTab then
        SetCurrentGuildBankTab(origTab)
    end
    if QueryGuildBankLog then
        lastMoneyLogQueryAt = GetTime()
        QueryGuildBankLog(GetMoneyLogTab())
    end
    isTabSwitching = false
end

function Scanner:ForceScan()
    VM:LogDebug("ForceScan triggered")
    if VM.Fulfillment and VM.Fulfillment.isWithdrawing then
        VM:Print("Please wait for the active withdrawal to finish before scanning.")
        return
    end
    -- Attempted even when no session was detected: queries are simply ignored if the bank is closed
    local now = time()
    if (now - lastScanTime) < SCAN_COOLDOWN then
        VM:Print("Please wait a moment before scanning again.")
        return
    end
    lastScanTime = now

    suppressChatPrint = false
    self:RequestAllTabsAndLogs()
    self:TriggerDebouncedScan(true, 0.75)
end

function Scanner:RunFullScanPass(isFinal)
    if VM.Fulfillment and VM.Fulfillment.isWithdrawing then
        scanDebounceIsFinal = isFinal
        scanDebounceTimeLeft = 0.5
        scanDebounceFrame:Show()
        return
    end

    isScanning = true
    ignoreSlotEventsUntil = GetTime() + 0.8
    ignoreLogEventsUntil = GetTime() + 0.9
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
    ignoreSlotEventsUntil = GetTime() + 0.6
    ignoreLogEventsUntil = GetTime() + 0.9

    if isFinal and not suppressChatPrint then
        VM:Print(string.format("Scan complete: %d items, %d item logs, %d gold logs stored.",
            itemCount or 0, logsAdded or 0, moneyAdded or 0))
    end
    suppressChatPrint = false

    -- A log/slot answer arrived while scanning (or inside the echo window): run one more pass
    if pendingRescan and self.isBankOpen and pendingRescanChain < 3 then
        pendingRescan = false
        pendingRescanChain = pendingRescanChain + 1
        suppressChatPrint = true
        self:TriggerDebouncedScan(false, 1.0)
    else
        pendingRescan = false
    end

    if VM.UI and VM.UI.UpdateScanStatusButton then
        VM.UI:UpdateScanStatusButton()
    end
end

function Scanner:ScanBank()
    local numTabs = GB_API.GetNumTabs()
    if numTabs == 0 then return 0 end

    local origTab = (GetCurrentGuildBankTab and GetCurrentGuildBankTab()) or 1
    local maxTabs = math.max(numTabs, 6)
    local newTabs = {}
    local totalItemsScanned = 0
    local uniqueItemsCount = 0
    local oldTabs = VM.db.inventory and VM.db.inventory.tabs or {}
    local hasPendingItems = false

    isTabSwitching = true
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
            -- Read cached tab data only (server queries are issued by RequestAllTabsAndLogs);
            -- querying here caused slot-event echo loops and repeated inventory broadcasts.
            if SetCurrentGuildBankTab and numTabs > 1 and (GetCurrentGuildBankTab and GetCurrentGuildBankTab()) ~= tab then
                SetCurrentGuildBankTab(tab)
            end

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
    if origTab and origTab >= 1 and origTab <= numTabs and SetCurrentGuildBankTab then
        SetCurrentGuildBankTab(origTab)
    end
    isTabSwitching = false

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

    -- Content signature: unchanged contents => no new inventory snapshot / broadcast (prevents queue floods)
    local sigParts = { tostring(numTabs) }
    for tab = 1, maxTabs do
        local t = newTabs[tab]
        if t then
            table.insert(sigParts, string.format("#%d:%s:%s", tab, tostring(t.name), t.isPurchased and "1" or "0"))
            local keys = {}
            for k in pairs(t.items or {}) do table.insert(keys, tostring(k)) end
            table.sort(keys)
            for _, k in ipairs(keys) do
                local it = t.items[k] or t.items[tonumber(k) or k]
                table.insert(sigParts, k .. "=" .. tostring(it and it.count or 0))
            end
        end
    end
    local contentSig = table.concat(sigParts, "|")

    local inv = VM.db.inventory
    if inv and inv.contentSig == contentSig and (inv.lastScan or 0) > 0 and inv.tabs and next(inv.tabs) then
        if bankMoney > 0 and inv.gold ~= bankMoney then
            inv.gold = bankMoney
            if VM.Comms and VM.Comms.BroadcastInventoryGold then
                VM.Comms:BroadcastInventoryGold()
            end
            if VM.UI then VM.UI:RefreshAll() end
        end
        return uniqueItemsCount
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
        contentSig = contentSig,
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
                local normName = VM:CanonicalActor(name)
                count = tonumber(count) or 1

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

    local WINDOW_72H = 259200 -- 72-hour rolling deduplication window
    local existingCounts = {}

    if VM.db and VM.db.ledger then
        for _, exTx in pairs(VM.db.ledger) do
            -- Tombstones of bank-log sourced entries still "consume" their log occurrence, so an
            -- officer-deleted entry is never re-imported from the 72h bank log window.
            local countable = exTx and exTx.timestamp and (not exTx.deleted or (AUTO_LOG_SOURCES[exTx.source or ""] and not exTx.dupOf))
            if countable then
                local isGold = (exTx.itemID == 0 or exTx.itemLink == "GOLD" or exTx.source == "BANK_MONEY_LOG" or exTx.source == "MANUAL_GOLD" or (exTx.itemName and (exTx.itemName:find("Gold Deposit") or exTx.itemName:find("Gold Withdrawal"))))
                if not isGold then
                    local exDir = VM:NormalizeAction(exTx.type)
                    local exActor = VM:CanonicalActor(exTx.rawSender or exTx.player)
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
                local depTx = VM.Ledger:RecordDeposit(entry.normName, entry.itemID, entry.cleanLink, entry.count, "BANK_LOG", entry.computedTimestamp, entry.tab, entry.isFFA)
                -- Quick return: the same person put back exactly what they took out shortly before => void both
                if depTx and isOfficer and VM.Ledger.FindQuickReturnMatch then
                    local outTx = VM.Ledger:FindQuickReturnMatch(depTx)
                    if outTx then
                        VM.Ledger:PairTransactions(outTx.id, depTx.id)
                        VM:LogDebug("Auto-paired quick return: " .. tostring(depTx.itemName))
                    end
                end
                existingCounts[entry.matchKey] = existingM + 1
                addedCount = addedCount + 1
            else
                local matchedReq = nil
                if isOfficer and VM.Fulfillment and VM.Fulfillment.FindMatchingApprovedRequest then
                    matchedReq = VM.Fulfillment:FindMatchingApprovedRequest(entry.normName, entry.itemID, entry.itemName, entry.count, 0, true)
                end

                local ahPrice = VM:GetEffectiveLivePrice(entry.itemID, entry.cleanLink, 0)
                local itemName = entry.itemName or entry.cleanLink:gsub("^%[", ""):gsub("%]$", "")

                if matchedReq then
                    local effMode = matchedReq.priceMode or (entry.rule and entry.rule.mode) or "FREE"
                    local effPct = matchedReq.pricePercent or (entry.rule and entry.rule.percent) or 50
                    -- Locked price from approval (falls back to live price for old requests)
                    if tonumber(matchedReq.priceAtRequest) and tonumber(matchedReq.priceAtRequest) > 0 then
                        ahPrice = tonumber(matchedReq.priceAtRequest)
                    end
                    local totalCharged = (matchedReq.quotedTotalPrice ~= nil) and tonumber(matchedReq.quotedTotalPrice)
                        or VM:CalculateMemberTotalPrice(ahPrice, entry.count, { mode = effMode, percent = effPct })
                    if effMode == "FREE" then totalCharged = 0 end
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
                else
                    -- Direct withdrawal from non-FFA tab without an approved request:
                    -- booked at 100% AH value on actor (zero GUILD subsidy) so withdraw + redeposit nets to 0g.
                    local tx = {
                        id = string.format("OUT_DIR_%d_%d", time(), math.random(1000, 9999)),
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
                        chargedTotalPrice = nil,
                        priceMode = "DIRECT",
                        timestamp = entry.computedTimestamp,
                        updatedAt = time(),
                        officer = VM:GetPlayerName(),
                        source = "BANK_LOG",
                        isFFA = false,
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
                local normName = (name and name ~= "") and VM:CanonicalActor(name) or "UNATTRIBUTED"
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
            local countable = exTx and exTx.timestamp and exTx.source ~= "TAB_PURCHASE"
                and not PAYMENT_SOURCES[exTx.source or ""]
                and (not exTx.deleted or (AUTO_LOG_SOURCES[exTx.source or ""] and not exTx.dupOf))
            if countable then
                local isGold = (exTx.itemID == 0 or exTx.itemLink == "GOLD" or exTx.source == "BANK_MONEY_LOG" or exTx.source == "MANUAL_GOLD" or exTx.source == "GOLD_REQUEST" or exTx.source == "WRITE_OFF" or (exTx.itemName and (exTx.itemName:find("Gold Deposit") or exTx.itemName:find("Gold Withdrawal"))))
                if isGold then
                    local exDir = VM:NormalizeAction(exTx.type)
                    local exActor = VM:CanonicalActor(exTx.rawSender or exTx.player)
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
                -- Member CoD/Trade payments were already credited to the member at delivery.
                -- The officer's later deposit of that gold is a TRANSFER (not a personal donation).
                local held = (VM.Ledger and VM.Ledger.GetHeldCash) and VM.Ledger:GetHeldCash(entry.normName) or 0
                local transferPart = math.min(held, entry.copper)
                local tx
                if transferPart > 0 and VM.Ledger.RecordTransferDeposit then
                    tx = VM.Ledger:RecordTransferDeposit(entry.normName, entry.copper, transferPart, entry.computedTimestamp)
                    if IsSameActor(entry.normName, VM:GetPlayerName()) then
                        VM:Print(string.format("Deposit of %s booked as transfer of collected member payments (%s)%s.",
                            VM:FormatMoney(entry.copper), VM:FormatMoney(transferPart),
                            (entry.copper > transferPart) and (", remainder " .. VM:FormatMoney(entry.copper - transferPart) .. " as your donation") or ""))
                    end
                else
                    tx = VM.Ledger:RecordGoldDeposit(entry.normName, entry.copper, "BANK_MONEY_LOG", entry.normName, entry.normName, entry.computedTimestamp)
                end
                if tx then
                    tx.isFFA = false
                    tx.timestamp = entry.computedTimestamp
                end

                if transferPart <= 0 and IsSameActor(entry.normName, VM:GetPlayerName()) and isOfficer then
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
            if not VM.db.inventory.lastScan or VM.db.inventory.lastScan == 0 then
                VM.db.inventory.lastScan = serverTime
                VM.db.inventory.lastScanTime = serverTime
                VM.db.inventory.lastScanBy = pName
                VM.db.inventory.scannedBy = pName
            end
            local m = GetGuildBankMoney and GetGuildBankMoney()
            if type(m) == "number" and m >= 0 then
                local changed = (VM.db.inventory.gold ~= m)
                VM.db.inventory.gold = m
                lastObservedBankMoney = m
                -- Gold-only update: never re-broadcast the whole inventory for a money log change
                if changed and VM.Comms.BroadcastInventoryGold then
                    VM.Comms:BroadcastInventoryGold()
                end
            end
        end
        if VM.UI then VM.UI:RefreshAll() end
    end
    return addedCount
end
