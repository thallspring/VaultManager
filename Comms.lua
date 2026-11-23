local _, VM = ...
VM.Comms = {}
local Comms = VM.Comms

local MSG_QUEUE = {}
local THROTTLE_INTERVAL = 0.20
local elapsedSinceSend = 0

local function EscapeStr(s)
    return tostring(s or ""):gsub("%%", "%%25"):gsub("|", "%%7C"):gsub("\n", "%%0A"):gsub("\r", "")
end

local function UnescapeStr(s)
    return tostring(s or ""):gsub("%%0A", "\n"):gsub("%%7C", "|"):gsub("%%25", "%%")
end

function Comms:GetMaxTimestamp(tbl, field)
    local maxTs = 0
    for _, v in pairs(tbl or {}) do
        local ts = (type(v) == "table" and v[field]) or 0
        if ts > maxTs then maxTs = ts end
    end
    return maxTs
end

function Comms:Init()
    local f = CreateFrame("Frame")
    f:RegisterEvent("CHAT_MSG_ADDON")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")

    f:SetScript("OnEvent", function(_, event, prefix, msg, channel, sender)
        if event == "CHAT_MSG_ADDON" then
            if prefix == VM.PREFIX and channel == "GUILD" then
                self:OnMessageReceived(msg, VM:NormalizeName(sender))
            end
        elseif event == "PLAYER_ENTERING_WORLD" then
            C_Timer.After(4, function()
                if IsInGuild() then
                    self:SendHello()
                end
            end)
        end
    end)

    f:SetScript("OnUpdate", function(_, elapsed)
        elapsedSinceSend = elapsedSinceSend + elapsed
        if elapsedSinceSend >= THROTTLE_INTERVAL and #MSG_QUEUE > 0 then
            elapsedSinceSend = 0
            local payload = table.remove(MSG_QUEUE, 1)
            if IsInGuild() then
                if C_ChatInfo and C_ChatInfo.SendAddonMessage then
                    C_ChatInfo.SendAddonMessage(VM.PREFIX, payload, "GUILD")
                elseif SendAddonMessage then
                    SendAddonMessage(VM.PREFIX, payload, "GUILD")
                end
            end
        end
    end)
end

function Comms:SendRaw(payload)
    for _, existing in ipairs(MSG_QUEUE) do
        if existing == payload then return end
    end
    table.insert(MSG_QUEUE, payload)
end

function Comms:SendHello()
    local invTs = VM.db.inventory.lastScan or 0
    local reqTs = self:GetMaxTimestamp(VM.db.requests, "updatedAt")
    local mainTs = self:GetMaxTimestamp(VM.db.mains, "updatedAt")
    local ruleTs = self:GetMaxTimestamp(VM.db.tabRules, "updatedAt")
    local txTs = self:GetMaxTimestamp(VM.db.ledger, "updatedAt")
    self:SendRaw(string.format("HELLO|%d|%d|%d|%d|%d", invTs, reqTs, mainTs, ruleTs, txTs))
end

function Comms:OnMessageReceived(msg, sender)
    if sender == VM:GetPlayerName() then return end
    local fromOfficer = VM:IsOfficerName(sender)
    local parts = { strsplit("|", msg) }
    local cmd = parts[1]

    if cmd == "HELLO" then
        local peerInvTs = tonumber(parts[2]) or 0
        local peerReqTs = tonumber(parts[3]) or 0
        local peerMainTs = tonumber(parts[4]) or 0
        local peerRuleTs = tonumber(parts[5]) or 0
        local peerTxTs = tonumber(parts[6]) or 0

        if (VM.db.inventory.lastScan or 0) > peerInvTs then
            self:BroadcastInventory()
        end

        if self:GetMaxTimestamp(VM.db.requests, "updatedAt") > peerReqTs then
            local cutoff = time() - (30 * 86400)
            for _, req in pairs(VM.db.requests) do
                if req.status == "PENDING" or req.status == "APPROVED" or (req.updatedAt or 0) > cutoff then
                    self:BroadcastRequest(req)
                end
            end
        end

        if self:GetMaxTimestamp(VM.db.mains, "updatedAt") > peerMainTs then
            self:BroadcastMains()
        end

        if self:GetMaxTimestamp(VM.db.tabRules, "updatedAt") > peerRuleTs then
            self:BroadcastTabRules()
        end

        if self:GetMaxTimestamp(VM.db.ledger, "updatedAt") > peerTxTs then
            self:BroadcastLedgerSync()
        end

    elseif cmd == "INV_META" then
        local scanTime = tonumber(parts[2]) or 0
        local scannedBy = UnescapeStr(parts[3])
        if scanTime > (VM.db.inventory.lastScan or 0) then
            VM.db.inventory = {
                lastScan = scanTime,
                scannedBy = scannedBy,
                tabs = {}
            }
        end

    elseif cmd == "INV_TAB" then
        local scanTime = tonumber(parts[2]) or 0
        local tabIdx = tonumber(parts[3])
        local tabName = UnescapeStr(parts[4])
        local tabIcon = UnescapeStr(parts[5])
        if scanTime >= (VM.db.inventory.lastScan or 0) and tabIdx then
            VM.db.inventory.tabs[tabIdx] = VM.db.inventory.tabs[tabIdx] or { items = {} }
            VM.db.inventory.tabs[tabIdx].name = tabName
            VM.db.inventory.tabs[tabIdx].icon = tabIcon
        end

    elseif cmd == "INV_ITEM" then
        local scanTime = tonumber(parts[2]) or 0
        local tabIdx = tonumber(parts[3])
        local itemID = tonumber(parts[4])
        local count = tonumber(parts[5])
        local itemName = UnescapeStr(parts[6])
        local itemLink = UnescapeStr(parts[7])
        local icon = UnescapeStr(parts[8])
        if scanTime >= (VM.db.inventory.lastScan or 0) and tabIdx and itemID then
            VM.db.inventory.tabs[tabIdx] = VM.db.inventory.tabs[tabIdx] or { name = "Tab " .. tabIdx, items = {} }
            VM.db.inventory.tabs[tabIdx].items[itemID] = {
                itemID = itemID,
                count = count,
                name = itemName,
                link = itemLink,
                icon = icon
            }
            if VM.UI then VM.UI:RefreshAll() end
        end

    elseif cmd == "REQ" then
        local req = {
            id = UnescapeStr(parts[2]),
            requester = UnescapeStr(parts[3]),
            itemID = tonumber(parts[4]),
            count = tonumber(parts[5]),
            tab = tonumber(parts[6]),
            status = UnescapeStr(parts[7]),
            createdAt = tonumber(parts[8]),
            updatedAt = tonumber(parts[9]) or 0,
            approvedBy = UnescapeStr(parts[10]),
            fulfilledBy = UnescapeStr(parts[11]),
            quotedUnitPrice = tonumber(parts[12]) or 0,
            priceMode = UnescapeStr(parts[13]),
            pricePercent = tonumber(parts[14]) or 0,
            itemName = UnescapeStr(parts[15]),
            itemLink = UnescapeStr(parts[16]),
        }
        local existing = VM.db.requests[req.id]
        if not fromOfficer and (existing or req.status ~= "PENDING") then return end
        if not existing or req.updatedAt > (existing.updatedAt or 0) then
            VM.db.requests[req.id] = req
            if VM:IsOfficer() and req.status == "PENDING" and not existing then
                print(string.format("|cff00ccff[Vault Manager]|r New request from |cffffff00%s|r: %dx %s",
                    req.requester, req.count, req.itemLink or req.itemName))
            end
            if VM.UI then VM.UI:RefreshAll() end
        end

    elseif cmd == "RULE" then
        if not fromOfficer then return end
        local tabIdx = tonumber(parts[2])
        local mode = UnescapeStr(parts[3])
        local pct = tonumber(parts[4]) or 50
        local updatedAt = tonumber(parts[5]) or 0
        local existing = VM.db.tabRules[tabIdx]
        if tabIdx and (not existing or updatedAt > (existing.updatedAt or 0)) then
            VM.db.tabRules[tabIdx] = { mode = mode, percent = pct, updatedAt = updatedAt }
            if VM.UI then VM.UI:RefreshAll() end
        end

    elseif cmd == "MAIN" then
        if not fromOfficer then return end
        local alt = UnescapeStr(parts[2])
        local main = UnescapeStr(parts[3])
        local updatedAt = tonumber(parts[4]) or 0
        local existing = VM.db.mains[alt]
        local existingTs = (type(existing) == "table" and existing.updatedAt) or 0
        if alt ~= "" and updatedAt > existingTs then
            VM.db.mains[alt] = { main = main, updatedAt = updatedAt }
            if VM.UI then VM.UI:RefreshAll() end
        end

    elseif cmd == "TX" then
        local tx = {
            id = UnescapeStr(parts[2]),
            type = UnescapeStr(parts[3]),
            player = UnescapeStr(parts[4]),
            itemID = tonumber(parts[5]),
            count = tonumber(parts[6]),
            unitPriceAtTime = tonumber(parts[7]) or 0,
            chargedUnitPrice = tonumber(parts[8]) or 0,
            timestamp = tonumber(parts[9]) or 0,
            officer = UnescapeStr(parts[10]),
            source = UnescapeStr(parts[11]),
            itemName = UnescapeStr(parts[12]),
            itemLink = UnescapeStr(parts[13]),
            updatedAt = tonumber(parts[14]) or tonumber(parts[9]) or 0,
        }
        local existing = VM.db.ledger[tx.id]
        if not fromOfficer and (existing or (tx.source ~= "BANK_LOG" and tx.source ~= "BANK_MONEY_LOG")) then return end
        if tx.id ~= "" and (not existing or tx.updatedAt > (existing.updatedAt or existing.timestamp or 0)) then
            VM.db.ledger[tx.id] = tx
            if VM.UI then VM.UI:RefreshAll() end
        end
    end
end

function Comms:BroadcastInventory()
    local inv = VM.db.inventory
    if not inv or inv.lastScan == 0 then return end
    self:SendRaw(string.format("INV_META|%d|%s", inv.lastScan, EscapeStr(inv.scannedBy)))
    for tabIdx, tabData in pairs(inv.tabs) do
        self:SendRaw(string.format("INV_TAB|%d|%d|%s|%s",
            inv.lastScan, tabIdx, EscapeStr(tabData.name), EscapeStr(tabData.icon)))
        for itemID, item in pairs(tabData.items) do
            self:SendRaw(string.format("INV_ITEM|%d|%d|%d|%d|%s|%s|%s",
                inv.lastScan, tabIdx, itemID, item.count,
                EscapeStr(item.name), EscapeStr(item.link), EscapeStr(item.icon)))
        end
    end
end

function Comms:BroadcastRequest(req)
    self:SendRaw(string.format("REQ|%s|%s|%d|%d|%d|%s|%d|%d|%s|%s|%d|%s|%d|%s|%s",
        EscapeStr(req.id), EscapeStr(req.requester), req.itemID, req.count, req.tab,
        EscapeStr(req.status), req.createdAt or 0, req.updatedAt or 0,
        EscapeStr(req.approvedBy), EscapeStr(req.fulfilledBy),
        req.quotedUnitPrice or 0, EscapeStr(req.priceMode), req.pricePercent or 0,
        EscapeStr(req.itemName), EscapeStr(req.itemLink)))
end

function Comms:BroadcastTabRules()
    for tabIdx, rule in pairs(VM.db.tabRules) do
        self:SendRaw(string.format("RULE|%d|%s|%d|%d",
            tabIdx, EscapeStr(rule.mode), rule.percent or 50, rule.updatedAt or 0))
    end
end

function Comms:BroadcastMains()
    for alt, entry in pairs(VM.db.mains) do
        local main = type(entry) == "table" and entry.main or entry
        local ts = type(entry) == "table" and entry.updatedAt or 0
        self:SendRaw(string.format("MAIN|%s|%s|%d", EscapeStr(alt), EscapeStr(main), ts))
    end
end

function Comms:BroadcastTransaction(tx)
    self:SendRaw(string.format("TX|%s|%s|%s|%d|%d|%d|%d|%d|%s|%s|%s|%s|%d",
        EscapeStr(tx.id), EscapeStr(tx.type), EscapeStr(tx.player),
        tx.itemID, tx.count, tx.unitPriceAtTime or 0, tx.chargedUnitPrice or 0,
        tx.timestamp or 0, EscapeStr(tx.officer), EscapeStr(tx.source),
        EscapeStr(tx.itemName), EscapeStr(tx.itemLink), tx.updatedAt or tx.timestamp or 0))
end

function Comms:BroadcastLedgerSync()
    local cutoff = time() - (90 * 86400)
    for _, tx in pairs(VM.db.ledger) do
        if (tx.updatedAt or tx.timestamp or 0) > cutoff then
            self:BroadcastTransaction(tx)
        end
    end
end