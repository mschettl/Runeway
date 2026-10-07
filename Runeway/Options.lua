-- Runeway options panel: Options -> AddOns -> Runeway, or /rnw config.
-- All values live in RunewayDB and apply immediately.

local ADDON, ns = ...

local LAYER_LABELS = {
    fill = "Walkable area", hatch = "Not walkable (hatching)", shade = "Dark edge", terrain = "Terrain lines",
    water = "Water lines", roads = "Roads", questAreas = "Quest areas",
}
local MODES = {
    { "key", "Own key", "Overlay on its own key binding (Options -> Keybindings -> Runeway). The map key stays the world map." },
    { "mapkey", "Map key (M)", "The world map key opens the overlay. The world map moves to the key below." },
    { "permanent", "Permanent", "The overlay is always shown (except when auto-hidden)." },
}
local AUTO_HIDE = {
    { "combat", "In combat" }, { "instance", "In instances" }, { "mounted", "Mounted, flying or on a taxi" },
    { "city", "In cities and inns (resting)" },
}

local panel = CreateFrame("Frame")
panel.name = "Runeway"
panel:Hide()
local controls = {}         -- each: { Refresh = function() }
local db = function() return ns.db() end

local function Header(text, x, y)
    local h = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    h:SetPoint("TOPLEFT", x, y)
    h:SetText(text)
    return h
end

local function Tooltip(f, text)
    if not text then return end
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", GameTooltip_Hide)
end

local function Check(label, x, y, get, set, tip)
    local c = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    c:SetPoint("TOPLEFT", x, y)
    c:SetSize(24, 24)
    c.Text:SetText(label)
    c.Text:SetFontObject("GameFontHighlight")
    c:SetScript("OnClick", function(self) set(self:GetChecked()) end)
    Tooltip(c, tip)
    c.Refresh = function() c:SetChecked(get()) end
    controls[#controls + 1] = c
    return c
end

-- Slider with the value shown in its label; fmt formats the value
local function Slider(label, x, y, width, min, max, step, fmt, get, set)
    local s = CreateFrame("Slider", nil, panel, "UISliderTemplateWithLabels")
    s:SetPoint("TOPLEFT", x, y)
    s:SetWidth(width)
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s.Low:SetText("")
    s.High:SetText("")
    local function Label(v) s.Text:SetText(label and (label .. ": " .. fmt(v)) or fmt(v)) end
    s:SetScript("OnValueChanged", function(self, v, user)
        Label(v)
        if user then set(v) end
    end)
    s.Refresh = function()
        local v = get()
        s:SetValue(v)
        Label(v)
    end
    controls[#controls + 1] = s
    return s
end

local function Button(text, x, y, width, onClick)
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT", x, y)
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

-- Colour swatch: opens Blizzard's ColorPickerFrame for the RGB of a layer (opacity has its own slider)
local function Swatch(layer, x, y)
    local b = CreateFrame("Button", nil, panel)
    b:SetPoint("TOPLEFT", x, y)
    b:SetSize(18, 18)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.5, 0.5, 0.5, 1)
    local col = b:CreateTexture(nil, "ARTWORK")
    col:SetPoint("TOPLEFT", 1, -1)
    col:SetPoint("BOTTOMRIGHT", -1, 1)
    b.Refresh = function()
        local c = db().colors[layer]
        col:SetColorTexture(c.r, c.g, c.b, 1)
    end
    local function SetRGB(r, g, bl)
        local c = db().colors[layer]
        c.r, c.g, c.b = r, g, bl
        ns.ApplyColors()
        b.Refresh()
    end
    b:SetScript("OnClick", function()
        local c = db().colors[layer]
        ColorPickerFrame:SetupColorPickerAndShow({
            r = c.r, g = c.g, b = c.b, hasOpacity = false,
            swatchFunc = function() SetRGB(ColorPickerFrame:GetColorRGB()) end,
            cancelFunc = function(prev) SetRGB(prev.r, prev.g, prev.b) end,
        })
    end)
    Tooltip(b, "Colour")
    controls[#controls + 1] = b
    return b
end

-- Key capture button: click, then press a key (with modifiers); Escape clears
local function KeyButton(x, y, get, set)
    local b = Button("", x, y, 140)
    b:EnableKeyboard(false)
    b.Refresh = function() b:SetText(get() or "Not set") end
    b:SetScript("OnClick", function(self)
        self:SetText("Press a key...")
        self:EnableKeyboard(true)
    end)
    b:SetScript("OnHide", function(self)
        self:EnableKeyboard(false)
        self.Refresh()
    end)
    b:SetScript("OnKeyDown", function(self, key)
        if key:find("SHIFT") or key:find("CTRL") or key:find("ALT") then return end
        self:EnableKeyboard(false)
        if key == "ESCAPE" then
            set(nil)
        else
            local mod = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "") .. (IsShiftKeyDown() and "SHIFT-" or "")
            set(mod .. key)
        end
        self.Refresh()
    end)
    controls[#controls + 1] = b
    return b
end

local function Pct(v) return ("%d %%"):format(v * 100 + 0.5) end

---------------------------------------------------------------------------
-- Layout: left column display, right column behaviour and window
---------------------------------------------------------------------------
local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("Runeway")

local L, R = 16, 340
local y = -50
Header("Layers (colour, opacity)", L, y)
y = y - 22
for _, layer in ipairs(ns.LAYER_KEYS) do
    Check(LAYER_LABELS[layer], L, y,
        function() return db().layers[layer] end,
        function(v) db().layers[layer] = v; ns.ApplyColors() end)
    Swatch(layer, L + 180, y - 3)
    Slider(nil, L + 210, y - 6, 90, 0, 1, 0.01, Pct,
        function() return db().colors[layer].a end,
        function(v) db().colors[layer].a = v; ns.ApplyColors() end)
    y = y - 30
end

y = y - 16
Header("Display", L, y)
y = y - 32
Slider("Map opacity", L + 4, y, 280, 0.05, 1, 0.01, Pct,
    function() return db().alpha end, function(v) db().alpha = v; ns.ApplyAll() end)
y = y - 40
Slider("Zoom", L + 4, y, 280, ns.ZOOM_MIN, ns.ZOOM_MAX, 0.01, function(v) return ("%.2f"):format(v) end,
    function() return db().zoom end, function(v) ns.SetZoom(v) end)
y = y - 40
Slider("Soft edge", L + 4, y, 280, 1, 5, 1, function(v) return ("%d"):format(v) end,
    function() return db().edge end, function(v) db().edge = math.floor(v + 0.5); ns.ApplyAll() end)
y = y - 40
Slider("Player arrow", L + 4, y, 280, 12, 48, 1, function(v) return ("%d px"):format(v) end,
    function() return db().arrowSize end, function(v) db().arrowSize = v end)
y = y - 40
Slider("Quest marks", L + 4, y, 280, 14, 48, 1, function(v) return ("%d px"):format(v) end,
    function() return db().pinSize end, function(v) db().pinSize = v end)
y = y - 40
Slider("Quest area edge", L + 4, y, 280, 0.5, 2.5, 0.05, function(v) return ("%.2f x"):format(v) end,
    function() return db().questEdge end, function(v) db().questEdge = v end)

y = -50
Header("Open with", R, y)
y = y - 22
for _, m in ipairs(MODES) do
    local key = m[1]
    Check(m[2], R, y, function() return db().mode == key end,
        function()
            db().mode = key
            ns.ApplyAll()
            for _, c in ipairs(controls) do c.Refresh() end
        end, m[3])
    y = y - 26
end
local keyLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
keyLabel:SetPoint("TOPLEFT", R + 4, y - 6)
keyLabel:SetText("World map key:")
KeyButton(R + 100, y, function() return db().worldMapKey end,
    function(key) db().worldMapKey = key; ns.ApplyAll() end)
y = y - 36

Header("Hide automatically", R, y)
y = y - 22
for _, a in ipairs(AUTO_HIDE) do
    local key = a[1]
    Check(a[2], R, y, function() return db().autoHide[key] end,
        function(v) db().autoHide[key] = v; ns.UpdateVisibility() end)
    y = y - 26
end

y = y - 16
Header("Window", R, y)
y = y - 22
Check("Rotate with the player", R, y, function() return db().rotate end, function(v) db().rotate = v end)
y = y - 26
Check("Locked (clicks pass through)", R, y, function() return db().locked end,
    function(v) db().locked = v; ns.ApplyAll() end, "Unlocked: drag to move, corner grip to resize. The mouse wheel zooms in both states.")
y = y - 26
Check("Frame on mouse-over (unlocked)", R, y, function() return db().hover end, function(v) db().hover = v; ns.ApplyAll() end)
y = y - 32
Slider("Size", R + 4, y, 260, ns.SIZE_MIN, ns.SIZE_MAX, 10, function(v) return ("%d px"):format(v) end,
    function() return db().w end, function(v) db().w = v; ns.ApplyAll() end)
y = y - 40
Button("Show / hide overlay", R, y, 160, function() Runeway_Toggle() end)
Button("Defaults", R + 170, y, 100, function()
    ns.ResetSettings()
    panel:Refresh()
end)

function panel:Refresh()
    if not ns.db() then return end
    for _, c in ipairs(controls) do c.Refresh() end
end
panel:SetScript("OnShow", panel.Refresh)

-- Settings panel callbacks
panel.OnRefresh = panel.Refresh
function panel:OnDefault()
    ns.ResetSettings()
    self:Refresh()
end
function panel:OnCommit() end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------
local category
if Settings and Settings.RegisterCanvasLayoutCategory then
    category = Settings.RegisterCanvasLayoutCategory(panel, "Runeway")
    Settings.RegisterAddOnCategory(category)
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
end

function ns.OpenOptions()
    if category and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end
