-- Minimal permissive WoW API mock for headless addon simulation (Lua 5.1)
local M = {}
M.now = 1000.0          -- GetTime()
M.epoch = 1764300000    -- time()
M.frames = {}
M.timers = {}
M.prints = {}
M.unknownEvents = { GUILDBANKFRAME_OPENED = true, GUILDBANKFRAME_CLOSED = true }
M.errors = {}

local function noop() end
local Proxy
local proxyMT = {}
local stubMT = {}
stubMT.__call = function() return nil end
stubMT.__index = function() return setmetatable({}, stubMT) end
proxyMT.__index = function(t, k)
    local v = rawget(proxyMT, "methods")[k]
    if v then return v end
    -- Addon-private flags (e.g. __vmHooked) must read as nil like on real frames
    if type(k) == "string" and k:sub(1, 2) == "__" then return nil end
    return setmetatable({}, stubMT)
end
local methods = {}
proxyMT.methods = methods
function Proxy(kind, name)
    local o = setmetatable({ __kind = kind, __shown = true, __scripts = {}, __events = {}, __text = "", __enabled = true, __name = name }, proxyMT)
    if name then _G[name] = o end
    return o
end
M.Proxy = Proxy
methods.RegisterEvent = function(self, ev)
    if M.unknownEvents[ev] then error('Frame:RegisterEvent(): Attempt to register unknown event "' .. ev .. '"', 2) end
    self.__events[ev] = true
end
methods.UnregisterEvent = function(self, ev) self.__events[ev] = nil end
methods.SetScript = function(self, s, f) self.__scripts[s] = f end
methods.GetScript = function(self, s) return self.__scripts[s] end
methods.HookScript = function(self, s, f)
    local old = self.__scripts[s]
    self.__scripts[s] = function(...) if old then old(...) end f(...) end
end
methods.Show = function(self) local was = self.__shown; self.__shown = true; if not was and self.__scripts.OnShow then self.__scripts.OnShow(self) end end
methods.Hide = function(self) local was = self.__shown; self.__shown = false; if was and self.__scripts.OnHide then self.__scripts.OnHide(self) end end
methods.IsShown = function(self) return self.__shown end
methods.IsVisible = function(self) return self.__shown end
methods.SetShown = function(self, v) if v then self:Show() else self:Hide() end end
methods.CreateFontString = function(self) return Proxy("FontString") end
methods.CreateTexture = function(self) return Proxy("Texture") end
methods.SetText = function(self, t) self.__text = t end
methods.GetText = function(self) return self.__text or "" end
methods.GetNumber = function(self) return tonumber(self.__text) or 0 end
methods.Enable = function(self) self.__enabled = true end
methods.Disable = function(self) self.__enabled = false end
methods.IsEnabled = function(self) return self.__enabled end
methods.SetEnabled = function(self, v) self.__enabled = v and true or false end
methods.GetChecked = function(self) return self.__checked end
methods.SetChecked = function(self, v) self.__checked = v end
methods.GetPoint = function(self) return "CENTER", nil, "CENTER", 0, 0 end
methods.GetWidth = function() return 100 end
methods.GetHeight = function() return 100 end
methods.GetStringWidth = function() return 50 end
methods.GetScale = function() return 1 end
methods.GetEffectiveScale = function() return 1 end
methods.GetName = function(self) return self.__name end
methods.GetParent = function(self) return UIParent end
methods.GetFrameLevel = function() return 1 end
methods.GetVerticalScroll = function() return 0 end
methods.GetVerticalScrollRange = function() return 0 end
methods.GetCenter = function() return 0, 0 end
methods.GetLeft = function() return 0 end
methods.GetTop = function() return 0 end
methods.GetBottom = function() return 0 end
methods.GetRight = function() return 0 end
methods.GetID = function() return 1 end
methods.IsMouseOver = function() return false end
methods.GetChildren = function() end
methods.GetCursorPosition = function() return 0 end
methods.GetNumLines = function() return 0 end
methods.GetObjectType = function(self) return self.__kind end
methods.IsObjectType = function() return false end
methods.GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end
methods.GetTextColor = function() return 1, 1, 1, 1 end
methods.IsKeyboardEnabled = function() return true end
methods.HasFocus = function() return false end
methods.GetCursorPosition = function() return 0 end
methods.Click = function(self) if self.__scripts.OnClick and self.__enabled then self.__scripts.OnClick(self, "LeftButton") end end

_G.CreateFrame = function(kind, name, parent, template)
    local f = Proxy(kind, name)
    table.insert(M.frames, f)
    return f
end
_G.UIParent = Proxy("Frame", "UIParent"); UIParent.__shown = true
_G.WorldFrame = Proxy("Frame", "WorldFrame")
_G.Minimap = Proxy("Frame", "Minimap")
_G.GameTooltip = Proxy("GameTooltip", "GameTooltip")
_G.GuildBankFrame = Proxy("Frame", "GuildBankFrame")
_G.MailFrame = Proxy("Frame", "MailFrame")
_G.TradeFrame = Proxy("Frame", "TradeFrame")
_G.UISpecialFrames = {}
_G.StaticPopupDialogs = {}
_G.StaticPopup_Show = function(which, a, b) local d = { which = which }; M.lastPopup = d; return d end
_G.Mixin = function(o, ...) return o end
_G.BackdropTemplateMixin = {}
_G.SlashCmdList = {}
_G.Enum = { PlayerInteractionType = { GuildBanker = 10 } }
_G.RAID_CLASS_COLORS = { WARLOCK = { r = 0.58, g = 0.51, b = 0.79, colorStr = "ff9482c9" } }
_G.LOCALIZED_CLASS_NAMES_MALE = { WARLOCK = "Warlock" }
_G.MAX_GUILDBANK_TABS = 8
_G.ATTACHMENTS_MAX_SEND = 12
_G.ERR_TRADE_COMPLETE = "Trade complete."
_G.date = os.date
_G.time = function(t) if t then return os.time(t) end return M.epoch end
_G.GetTime = function() return M.now end
_G.GetServerTime = function() return M.epoch end
_G.print = function(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end table.insert(M.prints, table.concat(t, " ")) end
_G.strtrim = function(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
_G.strsplit = function(sep, s, limit)
    local out = {}
    s = tostring(s)
    local pattern = "([^" .. sep:gsub("%p", "%%%0") .. "]*)"
    local start = 1
    while true do
        local i, j = s:find(sep, start, true)
        if not i then table.insert(out, s:sub(start)) break end
        table.insert(out, s:sub(start, i - 1))
        start = j + 1
    end
    return unpack(out)
end
_G.strupper = string.upper
_G.strlower = string.lower
_G.hooksecurefunc = function(a, b, c)
    if type(a) == "string" then
        local old = _G[a]
        _G[a] = function(...) local r = { old(...) } b(...) return unpack(r) end
    else
        local old = a[b]
        a[b] = function(...) local r = { old(...) } c(...) return unpack(r) end
    end
end
_G.C_Timer = { After = function(sec, fn) table.insert(M.timers, { at = M.now + sec, fn = fn }) end }
_G.InCombatLockdown = function() return false end
_G.IsInGuild = function() return true end
_G.GetGuildInfo = function() return "Test Guild", "Officer Alt", M.playerRank or 1 end
_G.IsGuildLeader = function() return false end
_G.UnitName = function(u) if u == "player" then return M.playerName or "Thallock" end if u == "NPC" then return M.tradeTarget end end
_G.UnitClass = function() return "Warlock", "WARLOCK" end
_G.GetRealmName = function() return "Forever" end
_G.GetNormalizedRealmName = function() return "Forever" end
M.roster = {
    { "Thallock Dotcom", "Officer Alt", 1, 60, "Warlock", "", "", "", true, 0, "WARLOCK" },
    { "Mango Tidecaller", "Member", 3, 60, "Shaman", "", "", "", true, 0, "SHAMAN" },
    { "Raidboss Lead", "Raid Leader", 2, 60, "Warrior", "", "", "", true, 0, "WARRIOR" },
}
_G.GetNumGuildMembers = function() return #M.roster end
_G.GetGuildRosterInfo = function(i) local r = M.roster[i]; if r then return unpack(r) end end
_G.GuildRoster = noop
_G.C_GuildInfo = { GuildRoster = noop }
_G.GuildControlGetNumRanks = function() return 5 end
_G.GuildControlGetRankName = function(i) return ({ "Guild Master", "Officer Alt", "Raid Leader", "Member", "Initiate" })[i] end
_G.GetAddOnMetadata = function() return "1.4.3" end
_G.C_ChatInfo = { RegisterAddonMessagePrefix = noop, SendAddonMessage = function(p, msg, ch) table.insert(M.sent, msg) end }
M.sent = {}
_G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
_G.GetItemInfo = function(id)
    local it = M.items[tonumber(id) or id] 
    if type(id) == "string" then local n = id:match("item:(%d+)"); if n then it = M.items[tonumber(n)] end end
    if not it then return nil end
    return it.name, it.link, 2, 60, 60, it.type or "Armor", "Cloth", it.stack or 1, "INVTYPE_WAIST", "icon", it.sell or 100, 4, 1
end
M.items = {
    [19146] = { name = "Devout Belt", link = "|cff1eff00|Hitem:19146::::::::60:::::|h[Devout Belt]|h|r", stack = 1, sell = 5000 },
    [14047] = { name = "Runecloth", link = "|cffffffff|Hitem:14047::::::::60:::::|h[Runecloth]|h|r", stack = 20, type = "Trade Goods", sell = 400 },
}
-- Guild bank model
M.bank = { open = false, money = 500000, tabs = { [1] = {} }, log = { [1] = {} }, moneylog = {} }
M.bank.tabs[1][1] = { id = 19146, count = 1 }
M.bank.tabs[1][2] = { id = 14047, count = 20 }
M.bank.tabs[1][3] = { id = 14047, count = 20 }
M.bags = { [0] = {} }
M.bagSize = 16
M.money = 100000
M.cursor = nil
M.curTab = 1
_G.GetNumGuildBankTabs = function() return 1 end
_G.GetGuildBankTabInfo = function(t) return "Tab " .. t, "icon", true, true, 25, 19 end
_G.GetCurrentGuildBankTab = function() return M.curTab end
_G.SetCurrentGuildBankTab = function(t) M.curTab = t end
_G.QueryGuildBankTab = function(t) if M.bank.open then M.queueEvent("GUILDBANKBAGSLOTS_CHANGED", 0.2) end end
_G.QueryGuildBankLog = function(t) if M.bank.open then M.queueEvent("GUILDBANKLOG_UPDATE", 0.3) end end
_G.GetGuildBankItemInfo = function(t, s) local it = M.bank.tabs[t] and M.bank.tabs[t][s]; if it then return "icon", it.count, false end end
_G.GetGuildBankItemLink = function(t, s) local it = M.bank.tabs[t] and M.bank.tabs[t][s]; if it then return M.items[it.id].link end end
_G.GetGuildBankMoney = function() return M.bank.money end
_G.GetGuildBankWithdrawMoney = function() return 450000 end
_G.CanWithdrawGuildBankMoney = function() return true end
_G.GetGuildBankTabCost = function() return 0 end
_G.GetNumGuildBankTransactions = function(t) return #(M.bank.log[t] or {}) end
_G.GetGuildBankTransaction = function(t, i) local e = M.bank.log[t][i]; return e.type, e.name, e.link, e.count, 1, 1, 0, 0, 0, 0 end
_G.GetNumGuildBankMoneyTransactions = function() return #M.bank.moneylog end
_G.GetGuildBankMoneyTransaction = function(i) local e = M.bank.moneylog[i]; return e.type, e.name, e.amount, 0, 0, 0, 0 end
_G.CloseGuildBankFrame = function() end
M.logName = "Thallock Dotcom"
_G.PickupGuildBankItem = function(t, s)
    if not M.bank.open then return end
    if M.cursor and M.cursor.fromBag then
        -- deposit
        local c = M.cursor; M.cursor = nil
        M.bank.tabs[t][s] = { id = c.id, count = c.count }
        table.insert(M.bank.log[t], 1, { type = "deposit", name = M.logName, link = M.items[c.id].link, count = c.count })
        M.queueEvent("GUILDBANKBAGSLOTS_CHANGED", 0.3)
        return
    end
    local it = M.bank.tabs[t][s]; if it then M.cursor = { id = it.id, count = it.count, gb = { t, s } } end
end
_G.SplitGuildBankItem = function(t, s, n)
    if not M.bank.open then return end
    local it = M.bank.tabs[t][s]; if it then M.cursor = { id = it.id, count = n, gb = { t, s } } end
end
_G.GetCursorInfo = function() if M.cursor then return "item", M.cursor.id end end
_G.CursorHasItem = function() return M.cursor ~= nil end
_G.ClearCursor = function() M.cursor = nil end
local function bagPlace(bag, slot)
    local c = M.cursor; if not c then return end
    if c.gb then
        local t, s = c.gb[1], c.gb[2]
        local it = M.bank.tabs[t][s]
        it.count = it.count - c.count; if it.count <= 0 then M.bank.tabs[t][s] = nil end
        M.cursor = nil
        M.pendingBag = { bag = bag, slot = slot, id = c.id, count = c.count }
        table.insert(M.bank.log[t], 1, { type = "withdraw", name = M.logName, link = M.items[c.id].link, count = c.count })
        M.queueFn(function() M.bags[bag][slot] = { id = M.pendingBag.id, count = M.pendingBag.count }; M.fire("BAG_UPDATE", bag); M.fire("GUILDBANKBAGSLOTS_CHANGED") end, 0.3)
    end
end
_G.PickupContainerItem = function(bag, slot)
    if M.cursor then bagPlace(bag, slot) return end
    local it = M.bags[bag][slot]; if it then M.cursor = { id = it.id, count = it.count, fromBag = { bag, slot } }; M.bags[bag][slot] = nil end
end
_G.SplitContainerItem = function(bag, slot, n) local it = M.bags[bag][slot]; if it then it.count = it.count - n; if it.count <= 0 then M.bags[bag][slot] = nil end; M.cursor = { id = it.id, count = n, fromBag = { bag, slot } } end end
_G.GetContainerNumSlots = function(bag) return bag == 0 and M.bagSize or 0 end
_G.GetContainerNumFreeSlots = function(bag) return 0, 0 end
_G.GetContainerItemInfo = function(bag, slot) local it = M.bags[bag] and M.bags[bag][slot]; if it then return "icon", it.count, false, 2, false, false, M.items[it.id].link end end
_G.GetMoney = function() return M.money end
_G.WithdrawGuildBankMoney = function(a) if not M.bank.open then return end M.bank.money = M.bank.money - a; table.insert(M.bank.moneylog, 1, { type = "withdraw", name = M.logName, amount = a }); M.queueFn(function() M.money = M.money + a; M.fire("PLAYER_MONEY"); M.fire("GUILDBANK_UPDATE_MONEY") end, 0.3) end
_G.DepositGuildBankMoney = function(a) if not M.bank.open then return end M.bank.money = M.bank.money + a; table.insert(M.bank.moneylog, 1, { type = "deposit", name = M.logName, amount = a }); M.queueFn(function() M.money = M.money - a; M.fire("PLAYER_MONEY"); M.fire("GUILDBANK_UPDATE_MONEY") end, 0.3) end
_G.GetItemCount = function() return 0 end
_G.SendChatMessage = noop
_G.PlaySound = noop
_G.GetCVar = function() return "1" end
_G.IsShiftKeyDown = function() return false end
_G.IsControlKeyDown = function() return false end
_G.GetScreenHeight = function() return 1080 end
_G.GetScreenWidth = function() return 1920 end
_G.GetCursorPosition = function() return 0, 0 end
_G.ChatFrame_OpenChat = noop
_G.ChatEdit_InsertLink = noop

M.queue = {}
function M.queueEvent(ev, delay, ...) local args = { ... }; table.insert(M.queue, { at = M.now + (delay or 0), fn = function() M.fire(ev, unpack(args)) end }) end
function M.queueFn(fn, delay) table.insert(M.queue, { at = M.now + (delay or 0), fn = fn }) end
function M.fire(ev, ...)
    for _, f in ipairs(M.frames) do
        if f.__events[ev] and f.__scripts.OnEvent then
            local ok, err = pcall(f.__scripts.OnEvent, f, ev, ...)
            if not ok then table.insert(M.errors, ev .. ": " .. tostring(err)) end
        end
    end
end
function M.advance(sec, step)
    step = step or 0.05
    local target = M.now + sec
    while M.now < target do
        M.now = M.now + step
        for i = #M.timers, 1, -1 do local t = M.timers[i]; if t.at <= M.now then table.remove(M.timers, i); local ok, e = pcall(t.fn); if not ok then table.insert(M.errors, "timer: " .. tostring(e)) end end end
        for i = #M.queue, 1, -1 do local q = M.queue[i]; if q.at <= M.now then table.remove(M.queue, i); local ok, e = pcall(q.fn); if not ok then table.insert(M.errors, "queue: " .. tostring(e)) end end end
        for _, f in ipairs(M.frames) do
            if f.__shown and f.__scripts.OnUpdate then local ok, e = pcall(f.__scripts.OnUpdate, f, step); if not ok then table.insert(M.errors, "OnUpdate: " .. tostring(e)) end end
        end
    end
end
function M.load(root, files)
    local ns = {}
    for _, fn in ipairs(files) do
        local chunk, err = loadfile(root .. "/" .. fn)
        if not chunk then error(err) end
        local ok, e = pcall(chunk, "VaultManager", ns)
        if not ok then table.insert(M.errors, "load " .. fn .. ": " .. tostring(e)) end
    end
    return ns
end
function M.dumpErrors(label)
    if #M.errors > 0 then print("!! ERRORS " .. (label or "") .. ":") for _, e in ipairs(M.errors) do io.write("   ", e, "\n") end M.errors = {} end
end

-- ===== Mail / Trade / Inbox / Chat extensions =====
M.whispers = {}
M.offlineNames = {}          -- names for which whispers fail with "player not found"
M.mail = { items = {}, money = 0 }
M.inbox = {}
M.trade = { items = {}, myMoney = 0, targetMoney = 0 }
_G.SendMailNameEditBox = Proxy("EditBox", "SendMailNameEditBox")
_G.SendMailSubjectEditBox = Proxy("EditBox", "SendMailSubjectEditBox")
_G.SendMailCODButton = Proxy("CheckButton", "SendMailCODButton")
_G.SendMailSendMoneyButton = Proxy("CheckButton", "SendMailSendMoneyButton")
_G.SendMailMoney = Proxy("Frame", "SendMailMoney")
_G.SendMailFrame = Proxy("Frame", "SendMailFrame")
_G.MoneyInputFrame_SetCopper = function(frame, amt) M.mail.money = amt end
_G.GetSendMailMoney = function() if SendMailCODButton:GetChecked() then return 0 end return M.mail.money end
_G.GetSendMailCOD = function() if SendMailCODButton:GetChecked() then return M.mail.money end return 0 end
_G.ClickSendMailItemButton = function(i) if M.cursor and M.cursor.fromBag then M.mail.items[i] = { id = M.cursor.id, count = M.cursor.count }; M.cursor = nil end end
_G.GetSendMailItem = function(i) local it = M.mail.items[i]; if it then return M.items[it.id].name, it.id, "tex", it.count, 2 end end
_G.GetSendMailItemLink = function(i) local it = M.mail.items[i]; if it then return M.items[it.id].link end end
_G.SendMail = function(target, subject, body)
    M.lastMail = { target = target, subject = subject, items = M.mail.items, money = M.mail.money, cod = GetSendMailCOD() }
    if M.mailFailTargets and M.mailFailTargets[target] then
        M.queueFn(function() M.fire("UI_ERROR_MESSAGE", 0, "Cannot find player") end, 0.2)
        return
    end
    M.queueFn(function() M.mail = { items = {}, money = 0 }; SendMailCODButton:SetChecked(false); M.fire("MAIL_SEND_SUCCESS") end, 0.3)
end
_G.GetInboxNumItems = function() return #M.inbox end
_G.GetInboxHeaderInfo = function(i) local m = M.inbox[i]; return "pkg", "st", m.sender, m.subject, m.money or 0, 0, 30, m.hasItem, false, m.wasReturned end
_G.SendChatMessage = function(msg, chan, lang, target)
    table.insert(M.whispers, { msg = msg, target = target })
    if M.offlineNames[target] then
        M.queueFn(function() M.fire("CHAT_MSG_SYSTEM", "No player named '" .. target .. "' is currently playing.") end, 0.2)
    end
end
_G.ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
_G.GetTradePlayerItemInfo = function(slot) local it = M.trade.items[slot]; if it then return M.items[it.id].name, "tex", it.count end end
_G.GetTradePlayerItemLink = function(slot) local it = M.trade.items[slot]; if it then return M.items[it.id].link end end
_G.ClickTradeButton = function(slot) if M.cursor and M.cursor.fromBag then M.trade.items[slot] = { id = M.cursor.id, count = M.cursor.count }; M.cursor = nil end end
_G.SetTradeMoney = function(a) M.trade.myMoney = a end
_G.GetPlayerTradeMoney = function() return M.trade.myMoney end
_G.GetTargetTradeMoney = function() return M.trade.targetMoney end
_G.UIErrorsFrame = Proxy("Frame", "UIErrorsFrame")
function M.doTrade(target, targetMoney)
    M.tradeTarget = target
    M.trade = { items = {}, myMoney = 0, targetMoney = 0 }
    M.fire("TRADE_SHOW")
end
function M.finishTrade(targetMoney)
    M.trade.targetMoney = targetMoney or 0
    M.fire("TRADE_MONEY_CHANGED")
    M.fire("TRADE_ACCEPT_UPDATE", 1, 1)
    M.fire("UI_INFO_MESSAGE", 0, "Trade complete.")
    M.trade = { items = {}, myMoney = 0, targetMoney = 0 }
    M.fire("TRADE_CLOSED")
end
return M
