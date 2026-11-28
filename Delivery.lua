local _, VM = ...
VM.Delivery = {}
local D = VM.Delivery

-- Delivery helpers: name variants (full two-word name -> first name fallback), online lookup,
-- member notifications (in addon + whisper), CoD payment tracking via the mailbox, automatic
-- next-mail filling and batch withdrawal of approved requests.

local WHISPER_PREFIX = "[Guild Bank] "

local function Prefs()
    return (VM.db and VM.db.uiPrefs) or {}
end

local function PlainText(s)
    s = tostring(s or "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", "")
    s = s:gsub("^%[", ""):gsub("%]$", ""):gsub("%[", ""):gsub("%]", "")
    return (s:match("^%s*(.-)%s*$") or s)
end

local function ReqLabel(req)
    if req.isGoldRequest then
        return string.format("gold request (%s)", VM:FormatMoneyPlain(tonumber(req.goldAmount or req.quotedTotalPrice) or 0))
    end
    return string.format("%dx %s", tonumber(req.count) or 1, PlainText(req.itemName or req.itemLink or "Item"))
end

local function JoinLabels(reqs, maxShown)
    local parts = {}
    for i, r in ipairs(reqs) do
        if i > (maxShown or 3) then
            table.insert(parts, string.format("+%d more", #reqs - (maxShown or 3)))
            break
        end
        table.insert(parts, ReqLabel(r))
    end
    return table.concat(parts, ", ")
end

local function MyName()
    return VM:CanonicalActor(VM:GetPlayerName())
end

local function IsMyMain(name)
    local me = VM:GetMainFor(VM:GetPlayerName())
    return me ~= "" and VM:GetMainFor(VM:NormalizeName(name)) == me
end

--------------------------------------------------------------------------------
-- Name variants: try the full roster name first, fall back to the first name
--------------------------------------------------------------------------------
function D:GetNameVariants(name)
    local norm = VM:NormalizeName(name)
    if norm == "" then return {} end
    local full = VM:CanonicalActor(norm)
    if full == "UNATTRIBUTED" then full = norm end
    local first = full:match("^(%S+)") or full
    local list = {}
    local pref = VM.db and VM.db.nameFormat and VM.db.nameFormat[full]
    if pref == "first" then
        table.insert(list, first)
        if full ~= first then table.insert(list, full) end
    else
        table.insert(list, full)
        if first ~= full then table.insert(list, first) end
    end
    return list, full
end

function D:RememberNameFormat(name, usedVariant)
    local _, full = self:GetNameVariants(name)
    if not full or not VM.db then return end
    VM.db.nameFormat = VM.db.nameFormat or {}
    VM.db.nameFormat[full] = (usedVariant and usedVariant:lower() == full:lower()) and "full" or "first"
end

-- Mail recipient: start with the preferred variant; switched automatically if the server rejects it
function D:BeginMailRecipient(requester)
    local variants = self:GetNameVariants(requester)
    self.mailFill = { requester = requester, variants = variants, idx = 1, at = time() }
    return variants[1] or requester
end

function D:GetCurrentMailRecipient()
    local m = self.mailFill
    return m and m.variants and m.variants[m.idx]
end

function D:SwapMailRecipient(silent)
    local m = self.mailFill
    if not m or not m.variants or #m.variants < 2 then return false end
    m.idx = (m.idx % #m.variants) + 1
    m.at = time()
    local name = m.variants[m.idx]
    if SendMailNameEditBox then SendMailNameEditBox:SetText(name) end
    if not silent then
        VM:Print(string.format("|cffffaa00Mail recipient changed to '%s'. Check the name and click Send.|r", name))
    end
    return true
end

local function IsMailTargetError(msg)
    if not msg or msg == "" then return false end
    if ERR_MAIL_TARGET_NOT_FOUND and msg == ERR_MAIL_TARGET_NOT_FOUND then return true end
    local l = msg:lower()
    return l:find("cannot find") ~= nil or l:find("not found") ~= nil or l:find("unknown player") ~= nil
end

function D:OnUIError(msg)
    local m = self.mailFill
    if m and (time() - (m.at or 0)) <= 120 and IsMailTargetError(msg) then
        if not self:SwapMailRecipient(true) then return end
        VM:Print(string.format("|cffffaa00Recipient not found — switched to '%s'. Check the name and click Send again.|r", self:GetCurrentMailRecipient() or "?"))
    end
end

function D:OnMailFailed()
end

function D:OnMailSent(snap)
    local m = self.mailFill
    if m and snap and VM:IsSameCharacter(snap.recipient, m.requester) then
        self:RememberNameFormat(m.requester, snap.recipient)
    end
    self.mailFill = nil
end

--------------------------------------------------------------------------------
-- Online lookup + whispers with name fallback
--------------------------------------------------------------------------------
-- Returns the online roster name of the character or one of their alts (same main), or nil
function D:FindOnlineCharacter(name)
    if not IsInGuild() or not GetNumGuildMembers then return nil end
    local norm = VM:NormalizeName(name)
    if norm == "" then return nil end
    local main = VM:GetMainFor(norm)
    local exact, alt = nil, nil
    for i = 1, (GetNumGuildMembers() or 0) do
        local rName, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
        if rName and online then
            local rn = VM:NormalizeName(rName)
            if VM:IsSameCharacter(rn, norm) then
                exact = rn
            elseif main ~= "" and VM:GetMainFor(rn) == main then
                alt = alt or rn
            end
        end
    end
    return exact or alt
end

local pendingWhispers = {}

local function SendWhisperAttempt(entry)
    local target = entry.variants[entry.idx]
    if not target or not SendChatMessage then return end
    entry.at = GetTime()
    pcall(SendChatMessage, entry.msg, "WHISPER", nil, target)
    local idx = entry.idx
    if C_Timer and C_Timer.After then
        C_Timer.After(3, function()
            -- No "player not found" for this variant => it works; remember it (only for roster-based lookups)
            if not entry.done and entry.idx == idx then
                entry.done = true
                if entry.remember then D:RememberNameFormat(entry.forName, target) end
            end
        end)
    end
end

-- variants: ordered list of names to try (used for the trade partner's client name)
function D:WhisperTo(variants, msg, forName, remember)
    if not variants or #variants == 0 or not msg then return false end
    local entry = { variants = variants, idx = 1, msg = msg, forName = forName or variants[1], remember = remember }
    table.insert(pendingWhispers, entry)
    if #pendingWhispers > 20 then table.remove(pendingWhispers, 1) end
    SendWhisperAttempt(entry)
    return true
end

-- Whisper a member if they (or one of their alts) are online
function D:WhisperMember(name, msg)
    local online = self:FindOnlineCharacter(name)
    if not online then return false end
    local variants = self:GetNameVariants(online)
    return self:WhisperTo(variants, msg, online, true)
end

local notFoundPattern
local function GetNotFoundPattern()
    if notFoundPattern then return notFoundPattern end
    local fmt = ERR_CHAT_PLAYER_NOT_FOUND_S or "No player named '%s' is currently playing."
    local escaped = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    notFoundPattern = "^" .. escaped:gsub("%%s", "(.+)") .. "$"
    return notFoundPattern
end

function D:OnSystemMessage(msg)
    if type(msg) ~= "string" then return end
    local name = msg:match(GetNotFoundPattern())
    if not name then return end
    local lname = name:lower()
    for _, entry in ipairs(pendingWhispers) do
        local cur = entry.variants[entry.idx]
        if not entry.done and cur and cur:lower() == lname and (GetTime() - (entry.at or 0)) < 5 then
            if entry.variants[entry.idx + 1] then
                entry.idx = entry.idx + 1
                SendWhisperAttempt(entry)
            else
                entry.done = true
            end
            return
        end
    end
end

--------------------------------------------------------------------------------
-- Officer -> member status whispers
--------------------------------------------------------------------------------
local notified = {}

function D:NotifyMember(reqs, kind, extra)
    if not reqs or #reqs == 0 then return end
    if Prefs().memberWhispers == false then return end
    extra = extra or {}
    local byMain = {}
    for _, req in ipairs(reqs) do
        local key = tostring(req.id) .. ":" .. kind
        if not notified[key] and not IsMyMain(req.requester) then
            notified[key] = true
            local main = VM:GetMainFor(VM:NormalizeName(req.requester))
            byMain[main] = byMain[main] or { requester = req.requester, reqs = {} }
            table.insert(byMain[main].reqs, req)
        end
    end
    local me = MyName()
    for _, grp in pairs(byMain) do
        local list = JoinLabels(grp.reqs)
        local first = grp.reqs[1]
        local msg
        if kind == "APPROVED" then
            msg = string.format("Your request for %s was approved.", list)
        elseif kind == "READY" then
            local due = 0
            for _, r in ipairs(grp.reqs) do due = due + (VM.Fulfillment:GetExpectedMemberPayment(r) or 0) end
            local priceTxt = (due > 0) and (" Price: " .. VM:FormatMoneyPlain(due) .. ".") or ""
            local how
            if first.deliveryPref == "TRADE" then
                how = string.format(" Open a trade with %s to pick it up.", me)
            elseif first.deliveryPref == "MAIL" then
                how = " It will be sent to you by mail" .. ((due > 0) and " (CoD)." or ".")
            else
                how = string.format(" It will be mailed to you, or open a trade with %s.", me)
            end
            msg = string.format("%s is ready with %s.%s%s", list, me, priceTxt, how)
        elseif kind == "SENT_MAIL" then
            local cod = tonumber(extra.cod) or 0
            msg = string.format("Sent %s to you by mail%s.", list, (cod > 0) and (" with CoD " .. VM:FormatMoneyPlain(cod)) or "")
        elseif kind == "DELIVERED" then
            local owed = tonumber(extra.owed) or 0
            msg = string.format("%s was delivered%s.", list, (owed > 0) and (". You owe " .. VM:FormatMoneyPlain(owed) .. " for it") or "")
        elseif kind == "REJECTED" then
            msg = string.format("Your request for %s was declined.", list)
        elseif kind == "COD_RETURNED" then
            msg = string.format("The CoD mail with %s came back unpaid. Tell %s if you still want it.", list, me)
        end
        if msg then
            self:WhisperMember(grp.requester, WHISPER_PREFIX .. msg)
        end
    end
end

-- After a trade: thank the member and state any amount still owed (always sent; payment info)
function D:NotifyTradeResult(payer, paid, stillOwed, reqs)
    paid = tonumber(paid) or 0
    stillOwed = tonumber(stillOwed) or 0
    local msg
    if stillOwed > 0 then
        msg = string.format("Thanks! Received %s. You still owe %s for your Guild Bank requests - please pay %s.",
            VM:FormatMoneyPlain(paid), VM:FormatMoneyPlain(stillOwed), MyName())
    elseif paid > 0 then
        msg = string.format("Thanks! Payment of %s received - everything is paid.", VM:FormatMoneyPlain(paid))
    elseif reqs and #reqs > 0 then
        msg = string.format("Delivered: %s. Nothing to pay.", JoinLabels(reqs))
    end
    if msg then
        local raw = UnitName and UnitName("NPC")
        local variants = self:GetNameVariants(payer)
        if raw and raw ~= "" then table.insert(variants, 1, raw) end
        self:WhisperTo(variants, WHISPER_PREFIX .. msg, payer)
    end
end

-- When filling the trade: what is delivered and the total to pay (incl. older debt)
function D:WhisperTradeSummary(rawTarget, target, orders)
    local due, gold = 0, 0
    local items = {}
    for _, r in ipairs(orders or {}) do
        if r.isGoldRequest then
            gold = gold + (tonumber(r.goldAmount or r.quotedTotalPrice) or 0)
        else
            due = due + (VM.Fulfillment:GetExpectedMemberPayment(r) or 0)
            table.insert(items, r)
        end
    end
    local outstanding = VM.Fulfillment:GetOutstandingFor(target)
    local total = due + outstanding
    local parts = {}
    if #items > 0 then table.insert(parts, "Delivering " .. JoinLabels(items, 4) .. ".") end
    if gold > 0 then table.insert(parts, "Gold for you: " .. VM:FormatMoneyPlain(gold) .. ".") end
    if total > 0 then
        local inclTxt = (outstanding > 0) and string.format(" (incl. %s still owed from earlier)", VM:FormatMoneyPlain(outstanding)) or ""
        table.insert(parts, string.format("Please enter %s in the trade window%s.", VM:FormatMoneyPlain(total), inclTxt))
    elseif #items > 0 then
        table.insert(parts, "No payment needed.")
    end
    if #parts == 0 then return end
    local variants = self:GetNameVariants(target)
    if rawTarget and rawTarget ~= "" then table.insert(variants, 1, rawTarget) end
    self:WhisperTo(variants, WHISPER_PREFIX .. table.concat(parts, " "), target)
end

function D:WhisperDebtReminder(target)
    local outstanding = VM.Fulfillment:GetOutstandingFor(target)
    if outstanding <= 0 then return end
    local raw = UnitName and UnitName("NPC")
    local variants = self:GetNameVariants(target)
    if raw and raw ~= "" then table.insert(variants, 1, raw) end
    self:WhisperTo(variants, WHISPER_PREFIX .. string.format("Reminder: you still owe %s for earlier Guild Bank requests. Please add it to the trade.",
        VM:FormatMoneyPlain(outstanding)), target)
end

--------------------------------------------------------------------------------
-- Member side: in-addon notification when one of MY requests changes status
--------------------------------------------------------------------------------
function D:OnRequestUpdated(old, new)
    if not new or not IsMyMain(new.requester) then return end
    if old and old.status == new.status then return end
    local label = ReqLabel(new)
    local msg
    if new.status == "APPROVED" and (not old or old.status == "PENDING") then
        msg = string.format("Your request for %s was approved by %s.", label, new.approvedBy or "an officer")
    elseif new.status == "PREPARED" then
        local how = (new.deliveryPref == "TRADE") and (" Open a trade with " .. (new.preparedBy or "the officer") .. ".")
            or " It will be mailed to you or handed over in a trade."
        msg = string.format("%s has withdrawn %s for you.%s", new.preparedBy or "An officer", label, how)
    elseif new.status == "FULFILLED" then
        if new.completedMethod == "MAIL" then
            local cod = VM.Fulfillment:GetExpectedMemberPayment(new) or 0
            msg = string.format("%s was sent to you by mail%s.", label, (cod > 0) and (" (CoD " .. VM:FormatMoneyPlain(cod) .. ")") or "")
        else
            msg = string.format("%s was delivered.", label)
        end
    elseif new.status == "REJECTED" and new.completedMethod ~= "CANCELLED" then
        msg = string.format("Your request for %s was declined.", label)
    end
    if msg then
        VM:Print("|cff44dd77" .. msg .. "|r")
        if UIErrorsFrame and UIErrorsFrame.AddMessage then
            UIErrorsFrame:AddMessage("Vault Manager: " .. msg, 0.3, 0.9, 0.5)
        end
    end
end

--------------------------------------------------------------------------------
-- CoD payment tracking: "awaiting payment" until the CoD money shows up in the mailbox,
-- or back to PREPARED when the mail is returned unpaid.
--------------------------------------------------------------------------------
function D:TrackCod(snap, reqs)
    if not VM.db or not snap or (snap.cod or 0) <= 0 then return end
    VM.db.pendingCod = VM.db.pendingCod or {}
    local ids, shares = {}, {}
    for _, r in ipairs(reqs or {}) do
        if not r.isGoldRequest then
            table.insert(ids, r.id)
            shares[r.id] = VM.Fulfillment:GetExpectedMemberPayment(r) or 0
        end
    end
    if #ids == 0 then return end
    local key = string.format("COD_%d_%d", time(), math.random(1000, 9999))
    VM.db.pendingCod[key] = {
        reqIds = ids,
        shares = shares,
        amount = snap.cod,
        recipient = snap.recipient,
        subject = snap.subject or "",
        sentAt = time(),
    }
    VM:Print(string.format("CoD of %s to |cffffff00%s|r is awaiting payment. It is recorded when the money arrives in your mailbox.",
        VM:FormatMoney(snap.cod), snap.recipient or "?"))
end

function D:ForgetCod(reqId)
    if not VM.db or not VM.db.pendingCod then return end
    for key, entry in pairs(VM.db.pendingCod) do
        for i = #entry.reqIds, 1, -1 do
            if entry.reqIds[i] == reqId then table.remove(entry.reqIds, i) end
        end
        if #entry.reqIds == 0 then VM.db.pendingCod[key] = nil end
    end
end

function D:SettleCod(key, entry, money)
    local remaining = math.floor(tonumber(money) or 0)
    local me = VM:GetPlayerName()
    local payer
    for _, id in ipairs(entry.reqIds) do
        local req = VM.db.requests[id]
        if req then
            payer = payer or req.requester
            local due = VM.Fulfillment:GetOwedAmount(req)
            local pay = math.min(due, remaining)
            if pay > 0 then
                VM.Ledger:RecordPayment(req.requester, pay, me, "MAIL", nil, req.id)
                remaining = remaining - pay
            end
        end
    end
    if remaining > 0 and payer then
        VM.Ledger:RecordPayment(payer, remaining, me, "MAIL")
    end
    VM.db.pendingCod[key] = nil
    VM:Print(string.format("CoD payment of %s from |cffffff00%s|r received. Deposit it in the Guild Bank as a transfer.",
        VM:FormatMoney(money), entry.recipient or payer or "?"))
    if VM.UI then VM.UI:RefreshAll() end
end

function D:ScanInbox()
    if not VM.db or not VM.db.pendingCod or not next(VM.db.pendingCod) then return end
    if not GetInboxNumItems or not GetInboxHeaderInfo then return end
    local n = GetInboxNumItems() or 0
    for i = 1, n do
        local _, _, sender, subject, money, _, _, hasItem, _, wasReturned = GetInboxHeaderInfo(i)
        if subject and subject ~= "" then
            for key, entry in pairs(VM.db.pendingCod) do
                if entry.subject ~= "" then
                    if wasReturned and hasItem and subject == entry.subject then
                        local ids = {}
                        for _, id in ipairs(entry.reqIds) do table.insert(ids, id) end
                        VM.db.pendingCod[key] = nil
                        for _, id in ipairs(ids) do VM.Fulfillment:MarkCodReturned(id) end
                        break
                    elseif (money or 0) > 0 and not wasReturned and subject:find(entry.subject, 1, true)
                        and (not sender or VM:IsSameCharacter(sender, entry.recipient)) then
                        self:SettleCod(key, entry, money)
                        break
                    end
                end
            end
        end
    end
end

-- Pending CoD entries for a request (for the UI)
function D:IsCodTracked(reqId)
    if not VM.db or not VM.db.pendingCod then return false end
    for _, entry in pairs(VM.db.pendingCod) do
        for _, id in ipairs(entry.reqIds) do
            if id == reqId then return true end
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Mailbox chain: after Send, the next member's prepared orders are filled automatically
--------------------------------------------------------------------------------
function D:ScheduleNextMailFill()
    if Prefs().autoFillNextMail == false then return end
    if not (C_Timer and C_Timer.After) then return end
    C_Timer.After(1.0, function()
        local F = VM.Fulfillment
        if not F.isMailOpen then return end
        local mine = F:GetMyPreparedOrders()
        if #mine > 0 then
            F:PopulateMailFor(mine[1].requester)
        end
    end)
end

--------------------------------------------------------------------------------
-- Withdraw all approved requests, one after another (each one verified)
--------------------------------------------------------------------------------
local batchFrame = CreateFrame("Frame")
batchFrame:Hide()
local batchAccum = 0

function D:GetWithdrawableApproved()
    local list = {}
    local me = VM:GetPlayerName()
    for _, req in pairs((VM.db and VM.db.requests) or {}) do
        if req.status == "APPROVED" then
            local claim = VM.Fulfillment:GetActiveClaim(req)
            if not claim or VM:IsSameCharacter(claim, me) then
                table.insert(list, req)
            end
        end
    end
    table.sort(list, function(a, b) return (a.createdAt or 0) < (b.createdAt or 0) end)
    return list
end

function D:WithdrawAllApproved()
    if not VM:IsOfficer() then return end
    if self.batch then
        VM:Print("|cffffaa00Withdraw all is already running.|r")
        return
    end
    local list = self:GetWithdrawableApproved()
    if #list == 0 then
        VM:Print("No approved requests to withdraw.")
        return
    end
    self.batch = { list = list, idx = 0, ok = 0 }
    VM:Print(string.format("Withdrawing %d approved request(s) one by one...", #list))
    self:BatchStep()
end

function D:BatchStep()
    local b = self.batch
    if not b then return end
    b.idx = b.idx + 1
    local req = b.list[b.idx]
    if not req then
        VM:Print(string.format("Withdraw all finished: %d of %d withdrawn.", b.ok, #b.list))
        self.batch = nil
        batchFrame:Hide()
        if VM.UI then VM.UI:RefreshAll() end
        return
    end
    local live = VM.db.requests[req.id]
    if not live or live.status ~= "APPROVED" then
        return self:BatchStep()
    end
    b.current = req.id
    b.startedAt = GetTime()
    VM.Fulfillment:PrepareRequest(req.id)
    batchAccum = 0
    batchFrame:Show()
end

batchFrame:SetScript("OnUpdate", function(selfFrame, elapsed)
    local b = D.batch
    if not b then selfFrame:Hide() return end
    batchAccum = batchAccum + elapsed
    if batchAccum < 0.5 then return end
    batchAccum = 0
    local F = VM.Fulfillment
    if (F.prepareBusy or F.isWithdrawing) and (GetTime() - (b.startedAt or 0)) < 30 then return end
    selfFrame:Hide()
    local live = VM.db.requests[b.current]
    if live and (live.status == "PREPARED" or live.status == "FULFILLED") then
        b.ok = b.ok + 1
        if C_Timer and C_Timer.After then C_Timer.After(0.4, function() D:BatchStep() end) else D:BatchStep() end
    else
        VM:Print(string.format("|cffff4444Withdraw all stopped at %s (%d of %d done).|r",
            live and ReqLabel(live) or "a request", b.ok, #b.list))
        D.batch = nil
    end
end)

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("CHAT_MSG_SYSTEM")
f:RegisterEvent("MAIL_INBOX_UPDATE")
f:RegisterEvent("MAIL_SHOW")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "CHAT_MSG_SYSTEM" then
        D:OnSystemMessage(arg1)
    elseif event == "MAIL_INBOX_UPDATE" or event == "MAIL_SHOW" then
        if VM:IsOfficer() then D:ScanInbox() end
    end
end)
