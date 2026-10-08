-- Runeway options in Blizzard's own settings list: Options -> AddOns -> Runeway,
-- or /rnw config. All values live in RunewayDB and apply immediately.

local ADDON, ns = ...
local L = ns.L                       -- texts in the client language (Locales/)

local LAYER_LABELS = {
    fill = L.LAYER_FILL, hatch = L.LAYER_HATCH, shade = L.LAYER_SHADE, terrain = L.LAYER_TERRAIN,
    water = L.LAYER_WATER, roads = L.LAYER_ROADS, questAreas = L.LAYER_QUESTAREAS,
}
local MODES = {
    { "key", L.MODE_KEY, L.MODE_KEY_TIP },
    { "mapkey", L.MODE_MAPKEY, L.MODE_MAPKEY_TIP },
    { "permanent", L.MODE_PERMANENT, L.MODE_PERMANENT_TIP },
}
-- Quick commands: shown at the top of the settings (command stays English, description translated)
local COMMANDS = {
    { "/rnw", L.CMD_TOGGLE },
    { "/rnw config", L.CMD_CONFIG },
    { "/rnw lock  |  unlock", L.CMD_LOCK },
    { "/rnw alpha 5-100", L.CMD_ALPHA },
    { "/rnw zoom 0.08-5", L.CMD_ZOOM },
    { "/rnw size 200-1400", L.CMD_SIZE },
    { "/rnw rotate", L.CMD_ROTATE },
    { "/rnw edge 1-5", L.CMD_EDGE },
    { "/rnw mode key | mapkey | permanent", L.CMD_MODE },
    { "/rnw layer NAME", L.CMD_LAYER },
    { "/rnw color NAME R G B [A]", L.CMD_COLOR },
    { "/rnw keys", L.CMD_KEYS },
    { "/rnw pos", L.CMD_POS },
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

local AUTO_HIDE = {
    { "combat", L.HIDE_COMBAT }, { "instance", L.HIDE_INSTANCE }, { "mounted", L.HIDE_MOUNTED },
    { "city", L.HIDE_CITY },
}

local category, cat                 -- main category; category the settings below are added to
local ours = {}                     -- [category] = true for the Runeway pages

-- Value at a dotted path in RunewayDB or in the defaults, e.g. "colors.fill.a"
local function Get(tbl, path)
    for part in path:gmatch("[^.]+") do tbl = tbl[part] end
    return tbl
end
local function Set(path, v)
    local tbl, last = ns.db(), path:match("([^.]+)$")
    for part in path:gmatch("([^.]+)%.") do tbl = tbl[part] end
    tbl[last] = v
end

-- Proxy setting bound to a db path; apply runs after every change
local function Setting(path, varType, label, apply)
    return Settings.RegisterProxySetting(cat, "RUNEWAY_" .. path:upper():gsub("%.", "_"), varType, label,
        Get(ns.DEFAULTS, path), function() return Get(ns.db(), path) end,
        function(v) Set(path, v); if apply then apply(v) end end)
end

local function Check(path, label, tooltip, apply)
    Settings.CreateCheckbox(cat, Setting(path, Settings.VarType.Boolean, label, apply), tooltip)
end

local function SliderOptions(min, max, step, fmt)
    local options = Settings.CreateSliderOptions(min, max, step)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, fmt)
    return options
end

local function Slider(path, label, min, max, step, fmt, apply, tooltip)
    Settings.CreateSlider(cat, Setting(path, Settings.VarType.Number, label, apply),
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
    Check("rotate", L.ROTATE)
    Check("locked", L.LOCKED, L.LOCKED_TIP, function() ns.ApplyAll() end)
    Check("hover", L.HOVER, nil, function() ns.ApplyAll() end)
    Slider("w", L.SIZE, ns.SIZE_MIN, ns.SIZE_MAX, 10, function(v) return ("%d px"):format(v) end, function() ns.ApplyAll() end)

    Page(L.HEADER_DISPLAY)
    Slider("alpha", L.MAP_OPACITY, 0.05, 1, 0.01, Pct, function() ns.ApplyAll() end)
    Slider("zoom", L.ZOOM, ns.ZOOM_MIN, ns.ZOOM_MAX, 0.01, function(v) return ("%.2f"):format(v) end, function(v) ns.SetZoom(v) end)
    Slider("zoneDim", L.NEIGHBOUR_ZONES, 0, 1, 0.01, Pct, nil, L.NEIGHBOUR_ZONES_TIP)
    Slider("edge", L.SOFT_EDGE, 1, 5, 1, function(v) return ("%d"):format(v) end, function() ns.ApplyAll() end)
    Slider("arrowSize", L.PLAYER_ARROW, 12, 48, 1, function(v) return ("%d px"):format(v) end)
    Slider("pinSize", L.QUEST_MARKS, 12, 48, 1, function(v) return ("%d px"):format(v) end)
    Slider("corpseSize", L.CORPSE_MARKER, 12, 48, 1, function(v) return ("%d px"):format(v) end)
    Slider("questEdge", L.QUEST_EDGE, 0.5, 2.5, 0.05, function(v) return ("%.2f x"):format(v) end)
    Check("questMerge", L.QUEST_MERGE, L.QUEST_MERGE_TIP)

    -- Layers: show + opacity in one row, colour in the row below
    Page(L.HEADER_LAYERS)
    local function Apply() ns.ApplyColors() end
    for _, layer in ipairs(ns.LAYER_KEYS) do
        local label, c = LAYER_LABELS[layer], "colors." .. layer
        local shown = Settings.RegisterProxySetting(cat, "RUNEWAY_LAYER_" .. layer:upper(), Settings.VarType.Boolean,
            label, ns.DEFAULTS.layers[layer], function() return ns.db().layers[layer] end,
            function(v) ns.db().layers[layer] = v; Apply() end)
        local opacity = Settings.RegisterProxySetting(cat, "RUNEWAY_OPACITY_" .. layer:upper(), Settings.VarType.Number,
            L.LAYER_OPACITY:format(label), ns.DEFAULTS.colors[layer].a, function() return ns.db().colors[layer].a end,
            function(v) ns.db().colors[layer].a = v; Apply() end)
        layout:AddInitializer(CreateSettingsCheckboxSliderInitializer(shown, label, nil, opacity,
            SliderOptions(0, 1, 0.01, Pct), L.LAYER_OPACITY:format(label)))
        local function Hex(col) return CreateColor(col.r, col.g, col.b):GenerateHexColor() end
        local color = Settings.RegisterProxySetting(cat, "RUNEWAY_COLOR_" .. layer:upper(), Settings.VarType.String,
            L.LAYER_COLOUR:format(label), Hex(Get(ns.DEFAULTS, c)), function() return Hex(Get(ns.db(), c)) end,
            function(v)
                local col = Get(ns.db(), c)
                col.r, col.g, col.b = CreateColorFromHexString(v):GetRGB()
                Apply()
            end)
        Settings.CreateColorSwatch(cat, color)
    end

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
