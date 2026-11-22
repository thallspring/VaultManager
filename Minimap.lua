local _, VM = ...
VM.Minimap = {}
local MM = VM.Minimap

local BUTTON_RADIUS = 80
local minimapBtn

local function UpdatePosition(angleDeg)
    local rad = math.rad(angleDeg or 220)
    local x = math.cos(rad) * BUTTON_RADIUS
    local y = math.sin(rad) * BUTTON_RADIUS
    minimapBtn:ClearAllPoints()
    minimapBtn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function MM:UpdateBadge()
    if not minimapBtn or not VM.db then return end

    local count = 0
    if VM:IsOfficer() then
        for _, req in pairs(VM.db.requests or {}) do
            if req.status == "PENDING" or req.status == "APPROVED" then
                count = count + 1
            end
        end
    else
        local me = VM:GetPlayerName()
        for _, req in pairs(VM.db.requests or {}) do
            if req.requester == me and (req.status == "PENDING" or req.status == "APPROVED") then
                count = count + 1
            end
        end
    end

    if count > 0 then
        minimapBtn.badge:Show()
        minimapBtn.badgeText:SetText(count)
    else
        minimapBtn.badge:Hide()
    end
end

function MM:Create()
    if minimapBtn then return end

    VM.db.minimap = VM.db.minimap or { angle = 220, hide = false }

    minimapBtn = CreateFrame("Button", "VaultManagerMinimapButton", Minimap)
    minimapBtn:SetSize(31, 31)
    minimapBtn:SetFrameStrata("MEDIUM")
    minimapBtn:SetFrameLevel(8)
    minimapBtn:EnableMouse(true)
    minimapBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    minimapBtn:RegisterForDrag("LeftButton")

    -- Standard circular minimap border
    local overlay = minimapBtn:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT", 0, 0)

    local bg = minimapBtn:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("CENTER", 0, 0)

    local icon = minimapBtn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetPoint("CENTER", 0, 0)
    minimapBtn.icon = icon

    local highlight = minimapBtn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetSize(24, 24)
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetBlendMode("ADD")
    highlight:SetPoint("CENTER", 0, 0)

    -- Notification badge (number of open requests)
    local badge = CreateFrame("Frame", nil, minimapBtn, "BackdropTemplate")
    badge:SetSize(16, 16)
    badge:SetPoint("BOTTOMRIGHT", 2, -2)
    if not badge.SetBackdrop then Mixin(badge, BackdropTemplateMixin) end
    badge:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
        tile = false, edgeSize = 1,
    })
    badge:SetBackdropColor(0.85, 0.15, 0.15, 1)
    badge:SetBackdropBorderColor(0.05, 0.05, 0.05, 1)
    badge:Hide()
    minimapBtn.badge = badge

    local badgeText = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    badgeText:SetPoint("CENTER", 0, 0)
    badgeText:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    minimapBtn.badgeText = badgeText

    -- Drag around the minimap
    minimapBtn:SetScript("OnDragStart", function(self)
        self.isDragging = true
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            local angle = math.deg(math.atan2(cy - my, cx - mx))
            VM.db.minimap.angle = angle
            UpdatePosition(angle)
        end)
    end)

    minimapBtn:SetScript("OnDragStop", function(self)
        self.isDragging = false
        self:SetScript("OnUpdate", nil)
    end)

    -- Click actions
    minimapBtn:SetScript("OnClick", function(self, button)
        if self.isDragging then return end
        if button == "LeftButton" then
            VM.UI:Toggle()
        elseif button == "RightButton" then
            if VM.UI then
                VM.UI:Toggle()
            end
        end
    end)

    -- Tooltip
    minimapBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cff26a6f2Vault Manager|r")
        GameTooltip:AddLine("|cffffffffLeft-click:|r Open / close window", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("|cffffffffDrag:|r Move button around minimap", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    minimapBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    UpdatePosition(VM.db.minimap.angle)
    self:UpdateBadge()
end

-- Create button on login and update badge periodically
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    C_Timer.After(0.5, function()
        MM:Create()
        C_Timer.NewTicker(3, function()
            MM:UpdateBadge()
        end)
    end)
end)