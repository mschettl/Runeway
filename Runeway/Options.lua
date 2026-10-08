-- Runeway options in Blizzard's own settings list: Options -> AddOns -> Runeway,
-- or /rnw config. All values live in RunewayDB and apply immediately.

local ADDON, ns = ...

local LAYER_LABELS = {
    fill = "Walkable area", hatch = "Not walkable (hatching)", shade = "Dark edge", terrain = "Terrain lines",
    water = "Water lines", roads = "Roads", questAreas = "Quest areas",
}
local MODES = {
    { "key", "Own key", "Overlay on its own key binding (Toggle overlay map). The map key stays the world map." },
    { "mapkey", "Map key (M)", "The world map key opens the overlay. The world map moves to the key bound to \"World map\"." },
    { "permanent", "Permanent", "The overlay is always shown (except when auto-hidden)." },
}
local AUTO_HIDE = {
    { "combat", "In combat" }, { "instance", "In instances" }, { "mounted", "Mounted, flying or on a taxi" },
    { "city", "In cities and inns (resting)" },
}

local category

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
    return Settings.RegisterProxySetting(category, "RUNEWAY_" .. path:upper():gsub("%.", "_"), varType, label,
        Get(ns.DEFAULTS, path), function() return Get(ns.db(), path) end,
        function(v) Set(path, v); if apply then apply(v) end end)
end

local function Check(path, label, tooltip, apply)
    Settings.CreateCheckbox(category, Setting(path, Settings.VarType.Boolean, label, apply), tooltip)
end

local function SliderOptions(min, max, step, fmt)
    local options = Settings.CreateSliderOptions(min, max, step)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, fmt)
    return options
end

local function Slider(path, label, min, max, step, fmt, apply, tooltip)
    Settings.CreateSlider(category, Setting(path, Settings.VarType.Number, label, apply),
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
    local layout
    category, layout = Settings.RegisterVerticalLayoutCategory("Runeway")
    local function Header(text) layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text)) end

    Header("Open with")
    local mode = Setting("mode", Settings.VarType.String, "Open with", function() ns.ApplyAll() end)
    Settings.CreateDropdown(category, mode, function()
        local container = Settings.CreateControlTextContainer()
        for _, m in ipairs(MODES) do container:Add(m[1], m[2], m[3]) end
        return container:GetData()
    end)
    Binding(layout, "RUNEWAY_TOGGLE")
    Binding(layout, "RUNEWAY_WORLDMAP")

    Header("Hide automatically")
    for _, a in ipairs(AUTO_HIDE) do
        Check("autoHide." .. a[1], a[2], nil, function() ns.UpdateVisibility() end)
    end

    Header("Window")
    Check("rotate", "Rotate with the player")
    Check("locked", "Locked (clicks pass through)",
        "Unlocked: drag to move, corner grip to resize. The mouse wheel zooms in both states.", function() ns.ApplyAll() end)
    Check("hover", "Frame on mouse-over (unlocked)", nil, function() ns.ApplyAll() end)
    Slider("w", "Size", ns.SIZE_MIN, ns.SIZE_MAX, 10, function(v) return ("%d px"):format(v) end, function() ns.ApplyAll() end)
    layout:AddInitializer(CreateSettingsButtonInitializer("Overlay", "Show / hide", function() Runeway_Toggle() end, nil, false))

    Header("Display")
    Slider("alpha", "Map opacity", 0.05, 1, 0.01, Pct, function() ns.ApplyAll() end)
    Slider("zoom", "Zoom", ns.ZOOM_MIN, ns.ZOOM_MAX, 0.01, function(v) return ("%.2f"):format(v) end, function(v) ns.SetZoom(v) end)
    Slider("zoneDim", "Other zones", 0, 1, 0.01, Pct, nil,
        "Opacity of the zones you are not in, relative to your current zone.")
    Slider("edge", "Soft edge", 1, 5, 1, function(v) return ("%d"):format(v) end, function() ns.ApplyAll() end)
    Slider("arrowSize", "Player arrow", 12, 48, 1, function(v) return ("%d px"):format(v) end)
    Slider("pinSize", "Quest marks", 14, 48, 1, function(v) return ("%d px"):format(v) end)
    Slider("questEdge", "Quest area edge", 0.5, 2.5, 0.05, function(v) return ("%.2f x"):format(v) end)
    Check("questMerge", "Combine overlapping quest areas",
        "Quests whose areas overlap get one shared outline. Off: every quest keeps its own outline.")

    -- Layers: show + opacity in one row, colour in the row below
    Header("Layers")
    local function Apply() ns.ApplyColors() end
    for _, layer in ipairs(ns.LAYER_KEYS) do
        local label, c = LAYER_LABELS[layer], "colors." .. layer
        local shown = Settings.RegisterProxySetting(category, "RUNEWAY_LAYER_" .. layer:upper(), Settings.VarType.Boolean,
            label, ns.DEFAULTS.layers[layer], function() return ns.db().layers[layer] end,
            function(v) ns.db().layers[layer] = v; Apply() end)
        local opacity = Settings.RegisterProxySetting(category, "RUNEWAY_OPACITY_" .. layer:upper(), Settings.VarType.Number,
            label .. " opacity", ns.DEFAULTS.colors[layer].a, function() return ns.db().colors[layer].a end,
            function(v) ns.db().colors[layer].a = v; Apply() end)
        layout:AddInitializer(CreateSettingsCheckboxSliderInitializer(shown, label, nil, opacity,
            SliderOptions(0, 1, 0.01, Pct), label .. " opacity"))
        local function Hex(col) return CreateColor(col.r, col.g, col.b):GenerateHexColor() end
        local color = Settings.RegisterProxySetting(category, "RUNEWAY_COLOR_" .. layer:upper(), Settings.VarType.String,
            label .. " colour", Hex(Get(ns.DEFAULTS, c)), function() return Hex(Get(ns.db(), c)) end,
            function(v)
                local col = Get(ns.db(), c)
                col.r, col.g, col.b = CreateColorFromHexString(v):GetRGB()
                Apply()
            end)
        Settings.CreateColorSwatch(category, color)
    end

    Settings.RegisterAddOnCategory(category)
end

-- After login: the key binding list (GetNumBindings) includes our Bindings.xml entries then
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:SetScript("OnEvent", nil)
    Build()
end)

function ns.OpenOptions()
    if category then Settings.OpenToCategory(category:GetID()) end
end
