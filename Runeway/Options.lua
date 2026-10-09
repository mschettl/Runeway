-- Runeway options in Blizzard's own settings list: Options -> AddOns -> Runeway,
-- or /rnw config. All values live in RunewayDB and apply immediately.

local ADDON, ns = ...
local L = ns.L                       -- texts in the client language (Locales/)
local Get = ns.GetPath                -- dotted paths into RunewayDB or the defaults (Profile.lua)
local function Hex(r, g, b) return CreateColor(r, g, b):GenerateHexColor() end

local LAYER_LABELS = {
    fill = L.LAYER_FILL, hatch = L.LAYER_HATCH, shade = L.LAYER_SHADE, terrain = L.LAYER_TERRAIN,
    water = L.LAYER_WATER, roads = L.LAYER_ROADS, questAreas = L.LAYER_QUESTAREAS,
}
local MODES = {
    { "key", L.MODE_KEY, L.MODE_KEY_TIP },
    { "mapkey", L.MODE_MAPKEY, L.MODE_MAPKEY_TIP },
    { "permanent", L.MODE_PERMANENT, L.MODE_PERMANENT_TIP },
}
local AUTO_HIDE = {
    { "combat", L.HIDE_COMBAT }, { "instance", L.HIDE_INSTANCE }, { "mounted", L.HIDE_MOUNTED },
    { "city", L.HIDE_CITY },
}

-- Quick commands: shown at the top of the settings (command stays English, description translated)
local COMMANDS = {
    { "/rnw", L.CMD_TOGGLE },
    { "/rnw config", L.CMD_CONFIG },
    { "/rnw lock  |  unlock", L.CMD_LOCK },
    { "/rnw alpha 5-100", L.CMD_ALPHA },
    { "/rnw zoom 0-100", L.CMD_ZOOM },
    { "/rnw size W [H]", L.CMD_SIZE },
    { "/rnw rotate", L.CMD_ROTATE },
    { "/rnw edge 1-5", L.CMD_EDGE },
    { "/rnw mode key | mapkey | permanent", L.CMD_MODE },
    { "/rnw layer NAME", L.CMD_LAYER },
    { "/rnw color NAME R G B [A]", L.CMD_COLOR },
    { "/rnw keys", L.CMD_KEYS },
    { "/rnw pos", L.CMD_POS },
    { "/rnw view [ZONE | N W]", L.CMD_VIEW },
    { "/rnw reset", L.CMD_RESET },
}

-- Settings row: command on the left, description on the right (template in Options.xml)
RunewayCommandRowMixin = CreateFromMixins(SettingsListElementMixin)
function RunewayCommandRowMixin:Init(initializer)
    SettingsListElementMixin.Init(self, initializer)
    self.Text:SetPoint("RIGHT", self, "CENTER", -10, 0)   -- wider than the default label column
    self.Desc:SetText(initializer.data.desc)
end

-- Settings row with a wrapped paragraph (intro text); the row height comes from the initializer
RunewayTextRowMixin = CreateFromMixins(SettingsListElementMixin)
function RunewayTextRowMixin:Init(initializer)
    SettingsListElementMixin.Init(self, initializer)
    self.Text:Hide()
    self.Body:SetText(initializer.data.text)
end

-- Layer row: checkbox (shown), colour swatch and opacity slider in one row (template in Options.xml).
-- Builds on Blizzard's checkbox + slider row; the colour is its own proxy setting, so "Defaults" resets it.
RunewayLayerRowMixin = CreateFromMixins(SettingsCheckboxSliderControlMixin)
function RunewayLayerRowMixin:OnLoad()
    SettingsCheckboxSliderControlMixin.OnLoad(self)
    self.ColorSwatch = CreateFrame("Button", nil, self, "ColorSwatchTemplate")
    self.ColorSwatch:SetPoint("LEFT", self.Checkbox, "RIGHT", 8, -2)
    self.SliderWithSteppers:SetWidth(190)
    self.SliderWithSteppers:ClearAllPoints()
    self.SliderWithSteppers:SetPoint("LEFT", self.ColorSwatch, "RIGHT", 8, 2)
end

function RunewayLayerRowMixin:Init(initializer)
    SettingsCheckboxSliderControlMixin.Init(self, initializer)
    local setting, title = initializer.data.colorSetting, initializer.data.colorLabel
    local swatch = self.ColorSwatch
    local function Show() swatch:SetColor(CreateColorFromHexString(setting:GetValue())) end
    Show()
    swatch:SetScript("OnClick", function()
        local r, g, b = CreateColorFromHexString(setting:GetValue()):GetRGB()
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b, hasOpacity = false,
            swatchFunc = function() setting:SetValue(Hex(ColorPickerFrame:GetColorRGB())) end,
            cancelFunc = function() setting:SetValue(Hex(r, g, b)) end,
        })
    end)
    swatch:SetScript("OnEnter", function()
        GameTooltip:SetOwner(swatch, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1)
        GameTooltip:Show()
    end)
    swatch:SetScript("OnLeave", GameTooltip_Hide)
    self.cbrHandles:SetOnValueChangedCallback(setting:GetVariable(), Show)   -- picker, Defaults
end

local category, cat                 -- main category; category the settings below are added to
local ours = {}                     -- [category] = true for the Runeway pages

-- All proxy settings, so an import can refresh every row
local vars = {}
local function Proxy(categoryTbl, var, ...)
    vars[#vars + 1] = var
    return Settings.RegisterProxySetting(categoryTbl, var, ...)
end
function ns.NotifyAllSettings()
    for _, v in ipairs(vars) do Settings.NotifyUpdate(v) end
end

-- Proxy setting bound to a db path; apply runs after every change
local function Setting(path, varType, label, apply)
    return Proxy(cat, "RUNEWAY_" .. path:upper():gsub("%.", "_"), varType, label,
        Get(ns.DEFAULTS, path), function() return Get(ns.db(), path) end,
        function(v) ns.SetPath(ns.db(), path, v); if apply then apply(v) end end)
end

local function Check(path, label, tooltip, apply)
    return Settings.CreateCheckbox(cat, Setting(path, Settings.VarType.Boolean, label, apply), tooltip)
end

local function SliderOptions(min, max, step, fmt)
    local options = Settings.CreateSliderOptions(min, max, step)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, fmt)
    return options
end

local function Slider(path, label, min, max, step, fmt, apply, tooltip)
    return Settings.CreateSlider(cat, Setting(path, Settings.VarType.Number, label, apply),
        SliderOptions(min, max, step, fmt), tooltip)
end

local function Pct(v) return ("%d %%"):format(v * 100 + 0.5) end

-- Native key binding row (saved by the settings panel when it closes)
local function Binding(layout, action)
    for i = 1, GetNumBindings() do
        if GetBinding(i) == action then
            layout:AddInitializer(CreateKeybindingEntryInitializer(i, true))
            return
        end
    end
end

local function Build()
    -- Main page: intro and quick commands; the settings are sub-entries in the tree on the left
    local main
    category, main = Settings.RegisterVerticalLayoutCategory("Runeway")
    local version = Settings.CreateElementInitializer("RunewayTextRowTemplate", { name = "", text = L.VERSION:format(ns.Version()) })
    version.GetExtent = function() return 24 end
    main:AddInitializer(version)
    local intro = Settings.CreateElementInitializer("RunewayTextRowTemplate", { name = "", text = L.INTRO })
    intro.GetExtent = function() return 62 end
    main:AddInitializer(intro)
    main:AddInitializer(CreateSettingsListSectionHeaderInitializer(L.HEADER_COMMANDS))
    for _, c in ipairs(COMMANDS) do
        main:AddInitializer(Settings.CreateElementInitializer("RunewayCommandRowTemplate", { name = c[1], desc = c[2] }))
    end

    local layout
    ours[category] = true
    local function Page(name)
        cat, layout = Settings.RegisterVerticalLayoutSubcategory(category, name)
        ours[cat] = true
    end

    Page(L.HEADER_OPEN)
    local mode = Setting("mode", Settings.VarType.String, L.OPEN_WITH, function() ns.ApplyAll() end)
    Settings.CreateDropdown(cat, mode, function()
        local container = Settings.CreateControlTextContainer()
        for _, m in ipairs(MODES) do container:Add(m[1], m[2], m[3]) end
        return container:GetData()
    end)
    Binding(layout, "RUNEWAY_TOGGLE")
    Binding(layout, "RUNEWAY_WORLDMAP")

    Page(L.HEADER_AUTOHIDE)
    for _, a in ipairs(AUTO_HIDE) do
        Check("autoHide." .. a[1], a[2], nil, function() ns.UpdateVisibility() end)
    end

    Page(L.HEADER_WINDOW)
    Check("locked", L.LOCKED, L.LOCKED_TIP, function() ns.ApplyAll() end)
    Check("wheelZoom", L.WHEEL_ZOOM, L.WHEEL_ZOOM_TIP, function() ns.ApplyAll() end)
    Check("rotate", L.ROTATE)
    Check("hover", L.HOVER, nil, function() ns.ApplyAll() end)
    local function Px(v) return ("%d px"):format(v) end
    Slider("h", L.HEIGHT, ns.SIZE_MIN, ns.SIZE_MAX, 10, Px, function() ns.ApplyAll() end)
    Slider("w", L.WIDTH, ns.SIZE_MIN, ns.SIZE_MAX, 10, Px, function() ns.ApplyAll() end)

    Page(L.HEADER_DISPLAY)
    Slider("alpha", L.MAP_OPACITY, 0.05, 1, 0.01, Pct, function() ns.ApplyAll() end)
    Slider("zoom", L.ZOOM, ns.ZOOM_MIN, ns.ZOOM_MAX, (ns.ZOOM_MAX - ns.ZOOM_MIN) / 100,
        function(v) return ("%d %%"):format(ns.ZoomPct(v) + 0.5) end, function(v) ns.SetZoom(v) end)
    Slider("zoneDim", L.NEIGHBOUR_ZONES, 0, 1, 0.01, Pct, nil, L.NEIGHBOUR_ZONES_TIP)
    Slider("edge", L.SOFT_EDGE, 1, 5, 1, function(v) return ("%d"):format(v) end, function() ns.ApplyAll() end)
    -- markers: one row each with show and size, like the layer rows
    local function Marker(show, size, label, apply)
        local cb = Setting(show, Settings.VarType.Boolean, label, apply)
        local sizeLabel = L.MARKER_SIZE:format(label)
        local row = CreateSettingsCheckboxSliderInitializer(cb, label, nil,
            Setting(size, Settings.VarType.Number, sizeLabel), SliderOptions(12, 48, 1, Px), sizeLabel)
        row.data.setting = cb               -- so rows below can follow the checkbox (SetParentInitializer)
        row:AddSearchTags(label)
        layout:AddInitializer(row)
        return row
    end
    Marker("showArrow", "arrowSize", L.PLAYER_ARROW)
    Marker("showCorpse", "corpseSize", L.CORPSE_MARKER)
    Marker("showTaxi", "taxiSize", L.FLIGHT_MASTERS, function() ns.RefreshQuests() end)
    local quests = Marker("showQuests", "pinSize", L.QUEST_MARKS)
    local function QuestsShown() return ns.db().showQuests end
    Slider("questEdge", L.QUEST_EDGE, 0.5, 2.5, 0.05, function(v) return ("%.2f x"):format(v) end)
        :SetParentInitializer(quests, QuestsShown)
    Check("questMerge", L.QUEST_MERGE, L.QUEST_MERGE_TIP):SetParentInitializer(quests, QuestsShown)

    -- Layers: one row each with show, colour and opacity
    Page(L.HEADER_LAYERS)
    local function Apply() ns.ApplyColors() end
    for _, layer in ipairs(ns.LAYER_KEYS) do
        local label, c = LAYER_LABELS[layer], "colors." .. layer
        local shown = Proxy(cat, "RUNEWAY_LAYER_" .. layer:upper(), Settings.VarType.Boolean,
            label, ns.DEFAULTS.layers[layer], function() return ns.db().layers[layer] end,
            function(v) ns.db().layers[layer] = v; Apply() end)
        local opacity = Proxy(cat, "RUNEWAY_OPACITY_" .. layer:upper(), Settings.VarType.Number,
            L.LAYER_OPACITY:format(label), ns.DEFAULTS.colors[layer].a, function() return ns.db().colors[layer].a end,
            function(v) ns.db().colors[layer].a = v; Apply() end)
        local function HexOf(col) return Hex(col.r, col.g, col.b) end
        local color = Proxy(cat, "RUNEWAY_COLOR_" .. layer:upper(), Settings.VarType.String,
            L.LAYER_COLOUR:format(label), HexOf(Get(ns.DEFAULTS, c)), function() return HexOf(Get(ns.db(), c)) end,
            function(v)
                local col = Get(ns.db(), c)
                col.r, col.g, col.b = CreateColorFromHexString(v):GetRGB()
                Apply()
            end)
        local row = Settings.CreateSettingInitializer("RunewayLayerRowTemplate", {
            name = label, cbSetting = shown, cbLabel = label, sliderSetting = opacity,
            sliderOptions = SliderOptions(0, 1, 0.01, Pct), sliderLabel = L.LAYER_OPACITY:format(label),
            colorSetting = color, colorLabel = L.LAYER_COLOUR:format(label),
        })
        row:AddSearchTags(label)
        layout:AddInitializer(row)
    end

    -- Profile: export / import all settings as text
    Page(L.HEADER_PROFILE)
    local info = Settings.CreateElementInitializer("RunewayTextRowTemplate", { name = "", text = L.PROFILE_INTRO })
    info.GetExtent = function() return 62 end
    layout:AddInitializer(info)
    layout:AddInitializer(CreateSettingsButtonInitializer(L.PROFILE_EXPORT_TITLE, L.PROFILE_EXPORT, function() ns.ShowExport() end, nil, true))
    layout:AddInitializer(CreateSettingsButtonInitializer(L.PROFILE_IMPORT_TITLE, L.PROFILE_IMPORT, function() ns.ShowImport() end, nil, true))

    Settings.RegisterAddOnCategory(category)
end

-- Show / hide button in the header of the settings panel, next to "Defaults", on the Runeway pages only
local toggle
local function UpdateToggle()
    if toggle then toggle:SetText(ns.view:IsShown() and L.MAP_HIDE or L.MAP_SHOW) end
end
local function CreateToggle()
    local header = SettingsPanel and SettingsPanel.Container and SettingsPanel.Container.SettingsList
        and SettingsPanel.Container.SettingsList.Header
    if not header then return end
    toggle = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    toggle:SetSize(140, 22)
    toggle:SetPoint("TOPRIGHT", -138, -16)          -- left of the Defaults button (96 px at -36)
    toggle:SetScript("OnClick", function()
        Runeway_Toggle()
        UpdateToggle()
    end)
    toggle:SetScript("OnShow", UpdateToggle)
    toggle:Hide()
    ns.ToggleButton = toggle                         -- for tests
    EventRegistry:RegisterCallback("Settings.CategoryChanged", function(_, c) toggle:SetShown(ours[c] or false) end, toggle)
end

-- After login: the key binding list (GetNumBindings) includes our Bindings.xml entries then
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:SetScript("OnEvent", nil)
    Build()
    CreateToggle()
end)

function ns.OpenOptions()
    if category then Settings.OpenToCategory(category:GetID()) end
end
