-- Runeway
-- Player-centred, rotating contour overlay (line layers per ADT tile in world coordinates)

local ADDON, ns = ...               -- ns: shared with QuestAreas.lua
local T = 1600 / 3                 -- edge length of an ADT tile in yards (533.33)
local PATH = "Interface\\AddOns\\Runeway\\tiles\\"
local MEDIA = "Interface\\AddOns\\Runeway\\media\\"
local ZOOM_MIN, ZOOM_MAX = 0.08, 5

-- Tile layers, drawn bottom to top. Tiles are white; colours are applied with SetVertexColor.
-- fill = walkable area, hatch = not walkable (mountains, water), lines on top.
local LAYERS = { "fill", "hatch", "shade", "terrain", "water", "roads" }
local LAYER_CODE = { fill = "f", hatch = "h", shade = "s", terrain = "t", water = "w", roads = "r" }
local LAYER_LEVEL = { fill = 0, hatch = 1, shade = 2, terrain = 3, water = 4, roads = 5 }   -- texture sublevel
local STYLE = 3            -- bump when the default look changes (see migration in ADDON_LOADED)

-- One calm colour for all lines (Diablo IV style); quest areas glow blue like the minimap blobs
local LINE = { 0.82, 0.86, 0.89 }
local defaults = {
    x = nil, y = nil, w = 700, h = 450,
    zoom = 1.5, alpha = 0.7, rotate = true, locked = false, shown = false,
    colors = {
        fill    = { r = 1, g = 1, b = 1, a = 0.06 },
        hatch   = { r = 0.80, g = 0.84, b = 0.88, a = 0.22 },
        shade   = { r = 0.05, g = 0.05, b = 0.06, a = 0.45 },
        terrain = { r = LINE[1], g = LINE[2], b = LINE[3], a = 0.85 },
        water   = { r = LINE[1], g = LINE[2], b = LINE[3], a = 0.85 },
        roads   = { r = LINE[1], g = LINE[2], b = LINE[3], a = 0.4 },
        questAreas = { r = 0.35, g = 0.60, b = 1.00, a = 1 },
    },
    layers = { fill = true, hatch = true, shade = true, terrain = true, water = true, roads = true, questAreas = true },
}
local db

-- Fills missing keys (also in nested tables) from the defaults
local function ApplyDefaults(dst, src)
    for key, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[key]) ~= "table" then dst[key] = {} end
            ApplyDefaults(dst[key], v)
        elseif dst[key] == nil then
            dst[key] = v
        end
    end
end

BINDING_HEADER_RUNEWAY = "Runeway"
BINDING_NAME_RUNEWAY_TOGGLE = "Toggle overlay map"

local function Print(msg)
    print("|cff66ccffRuneway:|r " .. msg)
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local view = CreateFrame("Frame", "RunewayFrame", UIParent)
view:SetFrameStrata("BACKGROUND")
view:SetClampedToScreen(true)
view:SetMovable(true)
view:SetResizable(true)
view:RegisterForDrag("LeftButton")
view:Hide()
ns.view = view
ns.db = function() return db end

-- Soft fade towards the edge (like PoE). Without mask support: hard clipping
local fade
if view.CreateMaskTexture then
    fade = view:CreateMaskTexture()
    fade:SetTexture(MEDIA .. "fade.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    fade:SetAllPoints()
else
    view:SetClipsChildren(true)
end
local function Fade(tex)
    if fade and tex.AddMaskTexture then tex:AddMaskTexture(fade) end
end
ns.Fade = Fade

local canvas = CreateFrame("Frame", nil, view)
canvas:SetAllPoints()

local top = CreateFrame("Frame", nil, view)
top:SetAllPoints()
top:SetFrameLevel(canvas:GetFrameLevel() + 5)

local editHint = top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
editHint:SetPoint("TOP", 0, -4)
editHint:SetText("Drag = move  |  Mouse wheel = zoom  |  Shift+wheel = size  |  /rnw lock")

local status = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
status:SetPoint("BOTTOM", 0, 6)

-- Player arrow, fixed in the centre
local arrow = top:CreateTexture(nil, "OVERLAY")
arrow:SetTexture(MEDIA .. "arrow.tga")
arrow:SetSize(40, 40)
arrow:SetPoint("CENTER")

---------------------------------------------------------------------------
-- World coordinates -> screen
---------------------------------------------------------------------------
-- UnitPosition returns (north, west). Screen: x right = east, y up = north.
local pN, pW, cosA, sinA, k = 0, 0, 1, 0, 1

local function ToScreen(n, w)
    local sx = -(w - pW) * k
    local sy = (n - pN) * k
    return sx * cosA - sy * sinA, sx * sinA + sy * cosA
end
ns.ToScreen = ToScreen
ns.Player = function() return pN, pW, k end

---------------------------------------------------------------------------
-- Contour tiles
---------------------------------------------------------------------------
local tileTex = {}     -- ["inst:c_r:layer"] = Texture

local function ApplyColor(t, layer)
    local c = db.colors[layer]
    t:SetVertexColor(c.r, c.g, c.b, c.a)
end

local function GetTileTex(inst, key, layer, lod)
    local id = inst .. ":" .. key .. ":" .. layer
    local t = tileTex[id]
    if not t then
        t = canvas:CreateTexture(nil, "ARTWORK", nil, LAYER_LEVEL[layer])
        Fade(t)
        ApplyColor(t, layer)
        t.layer = layer
        tileTex[id] = t
    end
    if t.lod ~= lod then
        t:SetTexture(PATH .. inst .. "\\" .. (lod < 512 and (lod .. "\\") or "") .. key .. "_" .. layer .. ".tga")
        t.lod = lod
    end
    return t
end

local function ApplyColors()
    for _, t in pairs(tileTex) do ApplyColor(t, t.layer) end
    if ns.ApplyQuestAreaColor then ns.ApplyQuestAreaColor() end
end

local function HideTiles()
    for _, t in pairs(tileTex) do t:Hide() end
end

local function UpdateTiles(inst, angle)
    local data = RunewayTiles and RunewayTiles[inst]
    HideTiles()
    if not data then return false end

    local W, H = view:GetSize()
    local reach = math.sqrt(W * W + H * H) / 2 / k + T   -- visible radius in yards plus one tile
    local size = T * k
    local lod = (size < 160 and 128) or (size < 360 and 256) or 512   -- zoomed out: coarser tiles

    for key, have in pairs(data) do
        local c, r = key:match("(%d+)_(%d+)")
        c, r = tonumber(c), tonumber(r)
        local cn = (32 - r) * T - T / 2
        local cw = (32 - c) * T - T / 2
        if math.abs(cn - pN) < reach and math.abs(cw - pW) < reach then
            local x, y = ToScreen(cn, cw)
            for _, layer in ipairs(LAYERS) do
                if db.layers[layer] and have:find(LAYER_CODE[layer], 1, true) then
                    local t = GetTileTex(inst, key, layer, lod)
                    t:ClearAllPoints()
                    t:SetPoint("CENTER", view, "CENTER", x, y)
                    t:SetSize(size, size)
                    t:SetRotation(angle)
                    t:Show()
                end
            end
        end
    end
    return true
end

---------------------------------------------------------------------------
-- Quest markers (map position -> world position, once per refresh)
---------------------------------------------------------------------------
local quests = {}      -- { {n, w}, ... }
local qpins = {}

local function WorldFromMap(mapID, x, y)
    if not (C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
    local _, pos = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
    if pos then return pos.x, pos.y end
end

-- Map position -> world (north, west). The axis order of GetWorldPosFromMapPos is checked once per map
-- against the player position.
local swapByMap = {}
local function MapToWorld(mapID, x, y)
    local a, b = WorldFromMap(mapID, x, y)
    if not a then return end
    local swap = swapByMap[mapID]
    if swap == nil then
        local mp = C_Map.GetPlayerMapPosition(mapID, "player")
        local un, uw = UnitPosition("player")
        if mp and un then
            local pa, pb = WorldFromMap(mapID, mp:GetXY())
            if pa then
                swap = math.abs(pa - un) + math.abs(pb - uw) > math.abs(pb - un) + math.abs(pa - uw)
                swapByMap[mapID] = swap
            end
        end
    end
    if swap then return b, a end
    return a, b
end
ns.MapToWorld = MapToWorld

local function RefreshQuests()
    wipe(quests)
    local mapID = C_Map.GetBestMapForUnit("player")
    if not (mapID and C_QuestLog and C_QuestLog.GetQuestsOnMap) then return end
    for _, q in ipairs(C_QuestLog.GetQuestsOnMap(mapID) or {}) do
        local n, w = MapToWorld(mapID, q.x, q.y)
        if n then quests[#quests + 1] = { n, w } end
    end
end

local function UpdateQuestPins()
    for i, q in ipairs(quests) do
        local t = qpins[i]
        if not t then
            t = top:CreateTexture(nil, "ARTWORK")
            t:SetSize(14, 14)
            t:SetTexture(MEDIA .. "dot.tga")
            Fade(t)
            qpins[i] = t
        end
        local x, y = ToScreen(q[1], q[2])
        t:ClearAllPoints()
        t:SetPoint("CENTER", view, "CENTER", x, y)
        t:Show()
    end
    for i = #quests + 1, #qpins do qpins[i]:Hide() end
end

---------------------------------------------------------------------------
-- Main loop
---------------------------------------------------------------------------
local elapsed = 0
view:SetScript("OnUpdate", function(self, e)
    elapsed = elapsed + e
    if elapsed < 0.025 then return end
    elapsed = 0

    local n, w, _, inst = UnitPosition("player")
    if not n then
        HideTiles()
        if ns.HideQuestAreas then ns.HideQuestAreas() end
        status:SetText("No position (instance?)")
        return
    end
    pN, pW, k = n, w, db.zoom

    local facing = GetPlayerFacing() or 0
    local angle = db.rotate and -facing or 0
    cosA, sinA = math.cos(angle), math.sin(angle)
    arrow:SetRotation(db.rotate and 0 or facing)

    if UpdateTiles(inst, angle) then
        status:SetText("")
    else
        status:SetText("No contours for this area yet")
    end
    UpdateQuestPins()
    if ns.DrawQuestAreas then ns.DrawQuestAreas() end
end)

---------------------------------------------------------------------------
-- Position / size / lock
---------------------------------------------------------------------------
local function SavePos()
    db.x, db.y = view:GetCenter()
end

local function ApplyPos()
    view:ClearAllPoints()
    if db.x then
        view:SetPoint("CENTER", UIParent, "BOTTOMLEFT", db.x, db.y)
    else
        view:SetPoint("CENTER")
    end
end

local function ApplySize()
    view:SetSize(db.w, db.h)
end

local function ApplyLock()
    local unlocked = not db.locked
    view:EnableMouse(unlocked)          -- locked: clicks pass through
    view:EnableMouseWheel(unlocked)
    editHint:SetShown(unlocked)
end

local function SetZoom(z)
    db.zoom = math.max(ZOOM_MIN, math.min(ZOOM_MAX, z))
end

view:SetScript("OnDragStart", function(self) self:StartMoving() end)
view:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePos()
    ApplyPos()
end)
view:SetScript("OnMouseWheel", function(_, delta)
    if IsShiftKeyDown() then
        db.w = math.max(200, math.min(2000, db.w + delta * 40))
        db.h = math.max(150, math.min(1400, db.h + delta * 26))
        ApplySize()
    else
        SetZoom(db.zoom * (delta > 0 and 1.15 or 1 / 1.15))
    end
end)
view:SetScript("OnShow", RefreshQuests)

---------------------------------------------------------------------------
-- Show position as copyable text (/rnw pos)
---------------------------------------------------------------------------
local copy
local function ShowCopy(text)
    if not copy then
        copy = CreateFrame("EditBox", "RunewayCopyBox", UIParent, "InputBoxTemplate")
        copy:SetSize(360, 24)
        copy:SetPoint("CENTER", 0, 200)
        copy:SetAutoFocus(true)
        copy:SetScript("OnEscapePressed", copy.Hide)
        copy:SetScript("OnEnterPressed", copy.Hide)
    end
    copy:SetText(text)
    copy:Show()
    copy:SetFocus()
    copy:HighlightText()
end

---------------------------------------------------------------------------
-- Toggle
---------------------------------------------------------------------------
function Runeway_Toggle()
    db.shown = not db.shown
    view:SetShown(db.shown)
end

local function CreateWorldMapButton()
    if not WorldMapFrame then return end
    local b = CreateFrame("Button", nil, WorldMapFrame, "UIPanelButtonTemplate")
    b:SetSize(90, 22)
    b:SetText("Overlay")
    b:SetPoint("TOPRIGHT", WorldMapFrame, "TOPRIGHT", -40, -2)
    b:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 20)
    b:SetScript("OnClick", function()
        HideUIPanel(WorldMapFrame)
        db.shown = true
        view:Show()
    end)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        RunewayDB = RunewayDB or {}
        db = RunewayDB
        local style = db.style or 0
        if style < 2 then db.colors = nil end                              -- 2: Diablo IV style
        if style < 3 and db.colors then db.colors.questAreas = nil end     -- 3: blue glow quest areas
        db.style = STYLE
        ApplyDefaults(db, defaults)
        view:SetAlpha(db.alpha)
        ApplySize()
        ApplyPos()
        ApplyLock()
        CreateWorldMapButton()
        if not fade then Print("Note: this client does not support mask textures, the edge is clipped hard.") end
        self:UnregisterEvent("ADDON_LOADED")
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        self:RegisterEvent("QUEST_LOG_UPDATE")
    elseif event == "PLAYER_ENTERING_WORLD" then
        view:SetShown(db.shown)
        RefreshQuests()
    elseif view:IsShown() then
        RefreshQuests()
    end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
-- Layer key from a lower-cased slash argument ("questareas" -> "questAreas")
local function LayerKey(name)
    for key in pairs(defaults.layers) do
        if key:lower() == name then return key end
    end
end

SLASH_RUNEWAY1 = "/runeway"
SLASH_RUNEWAY2 = "/rnw"
SlashCmdList.RUNEWAY = function(msg)
    local cmd, arg = msg:lower():match("^(%S*)%s*(.-)$")
    local n = tonumber(arg)

    if cmd == "" or cmd == "toggle" then
        Runeway_Toggle()
    elseif cmd == "lock" or cmd == "unlock" then
        db.locked = (cmd == "lock")
        ApplyLock()
        Print(db.locked and "locked (clicks pass through)" or "unlocked")
    elseif cmd == "alpha" and n then
        db.alpha = math.max(5, math.min(100, n)) / 100
        view:SetAlpha(db.alpha)
        Print(("Opacity %d %%"):format(db.alpha * 100))
    elseif cmd == "zoom" and n then
        SetZoom(n)
        Print(("Zoom %.2f"):format(db.zoom))
    elseif cmd == "size" then
        local w, h = arg:match("(%d+)%s+(%d+)")
        if w then
            db.w, db.h = tonumber(w), tonumber(h)
            ApplySize()
        end
        Print(("Size %d x %d"):format(db.w, db.h))
    elseif cmd == "rotate" then
        db.rotate = not db.rotate
        Print(db.rotate and "map rotates with the player" or "north up")
    elseif cmd == "layer" and LayerKey(arg) then
        local key = LayerKey(arg)
        db.layers[key] = not db.layers[key]
        Print(("%s %s"):format(key, db.layers[key] and "shown" or "hidden"))
    elseif cmd == "color" then
        local layer, r, g, b, a = arg:match("^(%a+)%s+([%d.]+)%s+([%d.]+)%s+([%d.]+)%s*([%d.]*)")
        layer = layer and LayerKey(layer)
        local c = layer and db.colors[layer]
        if c then
            c.r, c.g, c.b = tonumber(r), tonumber(g), tonumber(b)
            c.a = tonumber(a) or c.a
            ApplyColors()
            Print(("%s colour %.2f %.2f %.2f, opacity %.2f"):format(layer, c.r, c.g, c.b, c.a))
        else
            Print("/rnw color fill|hatch|shade|terrain|water|roads|questareas R G B [A]   (0-1)")
        end
    elseif cmd == "probe" then
        Runeway_Probe(arg)
    elseif cmd == "pos" then
        local pn, pw, _, inst = UnitPosition("player")
        local mapID = C_Map.GetBestMapForUnit("player")
        ShowCopy(("%s %s %s map=%s facing=%.3f"):format(
            tostring(pn), tostring(pw), tostring(inst), tostring(mapID), GetPlayerFacing() or -1))
    elseif cmd == "reset" then
        local shown = db.shown
        wipe(db)
        ApplyDefaults(db, defaults)
        db.shown = shown
        ApplyColors()
        view:SetAlpha(db.alpha)
        ApplySize()
        ApplyPos()
        ApplyLock()
        Print("settings reset")
    else
        Print("/rnw [toggle] | lock | unlock | alpha 5-100 | zoom 0.08-5 | size W H | rotate | layer NAME | color NAME R G B [A] | probe [show] [RES] | pos | reset")
    end
end
