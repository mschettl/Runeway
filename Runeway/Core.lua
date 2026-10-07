-- Runeway
-- Player-centred, rotating contour overlay (line layers per ADT tile in world coordinates)

local ADDON, ns = ...               -- ns: shared with QuestAreas.lua
local T = 1600 / 3                 -- edge length of an ADT tile in yards (533.33)
local PATH = "Interface\\AddOns\\Runeway\\tiles\\"
local MEDIA = "Interface\\AddOns\\Runeway\\media\\"
local ZOOM_MIN, ZOOM_MAX = 0.08, 5
local SIZE_MIN, SIZE_MAX = 200, 1400
-- Soft edge strength 1-5: width of the fade as a share of the radius (media/fade<N>.tga, scripts/make_masks.py)
local FADE_WIDTH = { 0.12, 0.25, 0.38, 0.55, 0.75 }

-- Tile layers, drawn bottom to top. Tiles are white; colours are applied with SetVertexColor.
-- fill = walkable area, hatch = not walkable (mountains, water), lines on top.
local LAYERS = { "fill", "hatch", "shade", "terrain", "water", "roads" }
local LAYER_CODE = { fill = "f", hatch = "h", shade = "s", terrain = "t", water = "w", roads = "r" }
local LAYER_LEVEL = { fill = 0, hatch = 1, shade = 2, terrain = 3, water = 4, roads = 5 }   -- texture sublevel
-- Zoom levels stored per layer (FILE_LODS in scripts/build_raw.py); a missing level uses the nearest stored one.
-- hatch: the tile file is only the mask of the not walkable area (256 px); the lines are one shared pattern
-- per zoom level (media/hatch<lod>.tga), cut out by that mask.
local FILE_LOD = { fill = { [128] = 128, [256] = 128, [512] = 128 }, shade = { [128] = 128, [256] = 256, [512] = 256 } }
local HATCH_MASK_LOD = 256
local STYLE = 6            -- bump when the default look changes (see migration in ADDON_LOADED)

-- One calm colour for all lines (Diablo IV style); quest areas glow blue like the minimap blobs
local LINE = { 0.82, 0.86, 0.89 }
local defaults = {
    x = nil, y = nil, w = 600,          -- square map (w = edge length)
    zoom = 1.5, alpha = 0.7, rotate = true, locked = false, shown = false,
    mode = "key",            -- "key" = own key binding, "mapkey" = map key (M) opens the overlay, "permanent"
    autoHide = { combat = false, instance = false, mounted = false, city = false },
    hover = true,            -- unlocked: subtle frame while the mouse is over the map
    edge = 3,                -- soft edge strength, index into FADE_WIDTH
    arrowSize = 23, pinSize = 26, questEdge = 1,   -- quest edge = width factor of the quest area outline
    colors = {
        fill    = { r = 0.80, g = 0.64, b = 0.44, a = 0.07 },   -- warm brown like Diablo IV
        hatch   = { r = 0.80, g = 0.84, b = 0.88, a = 0.22 },
        shade   = { r = 0.05, g = 0.05, b = 0.06, a = 0.45 },
        terrain = { r = LINE[1], g = LINE[2], b = LINE[3], a = 0.85 },
        water   = { r = LINE[1], g = LINE[2], b = LINE[3], a = 0.85 },
        roads   = { r = LINE[1], g = LINE[2], b = LINE[3], a = 0.4 },
        questAreas = { r = 0.45, g = 0.78, b = 1.00, a = 1 },
    },
    layers = { fill = true, hatch = true, shade = true, terrain = true, water = true, roads = true, questAreas = true },
    questAreaCache = {},     -- [mapID] = { areas = {}, groups = {} }, see QuestAreas.lua
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
BINDING_NAME_RUNEWAY_WORLDMAP = "World map (map key mode)"

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
-- position and size live in RunewayDB; keep WoW's layout cache from restoring an old size
if view.SetDontSavePosition then view:SetDontSavePosition(true) end
ns.view = view
ns.db = function() return db end

-- Soft fade towards the edge (like PoE). Without mask support: hard clipping
local fade
if view.CreateMaskTexture then
    fade = view:CreateMaskTexture()
    fade:SetAllPoints()
else
    view:SetClipsChildren(true)
end
-- Moving textures: no snapping to whole screen pixels, otherwise they jump pixel by pixel while walking
local function NoSnap(t)
    if t.SetSnapToPixelGrid then
        t:SetSnapToPixelGrid(false)
        t:SetTexelSnappingBias(0)
    end
end
ns.NoSnap = NoSnap

local function Fade(tex)
    if fade and tex.AddMaskTexture then tex:AddMaskTexture(fade) end
end
ns.Fade = Fade
ns.FadeWidth = function() return FADE_WIDTH[db.edge] or FADE_WIDTH[3] end

local function ApplyEdge()
    if fade then
        fade:SetTexture(MEDIA .. "fade" .. (FADE_WIDTH[db.edge] and db.edge or 3) .. ".tga",
            "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    end
end

local canvas = CreateFrame("Frame", nil, view)
canvas:SetAllPoints()

local top = CreateFrame("Frame", nil, view)
top:SetAllPoints()
top:SetFrameLevel(canvas:GetFrameLevel() + 5)

local editHint = top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
editHint:SetPoint("TOP", 0, -4)
editHint:SetText("Drag = move  |  Wheel = zoom  |  Corner or Shift+wheel = size  |  /rnw config")

local status = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
status:SetPoint("BOTTOM", 0, 6)

-- Size and zoom readout while moving, sizing or zooming; fades out shortly after the last action
local info = top:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
info:SetPoint("CENTER", 0, -40)
info:Hide()
local infoUntil, infoHold = 0, false

-- Hover frame (unlocked only): 1 px lines along the edges
local border = {}
for i, pts in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
    local t = top:CreateTexture(nil, "BORDER")
    t:SetColorTexture(1, 1, 1, 0.3)
    t:SetPoint(pts[1])
    t:SetPoint(pts[2])
    if i <= 2 then t:SetHeight(1) else t:SetWidth(1) end
    t:Hide()
    border[i] = t
end
local function ShowBorder(on)
    for _, t in ipairs(border) do t:SetShown(on) end
end

-- Resize grip, bottom right (unlocked only); changes the size only, the zoom stays
local grip = CreateFrame("Button", nil, top)
grip:SetSize(16, 16)
grip:SetPoint("BOTTOMRIGHT", -2, 2)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
grip:Hide()

local function ShowInfo(hold)
    local w, h = view:GetSize()
    info:SetFormattedText("%d \195\151 %d   Zoom %.2f", w + 0.5, h + 0.5, db.zoom)
    info:SetAlpha(1)
    info:Show()
    infoHold = hold or false
    infoUntil = GetTime() + 1.5
end

local function UpdateInfo()
    if infoHold then
        ShowInfo(true)
    elseif info:IsShown() then
        local left = infoUntil - GetTime()
        if left <= 0 then info:Hide() else info:SetAlpha(math.min(1, left / 0.5)) end
    end
end

-- Player arrow, fixed in the centre
local arrowShadow = top:CreateTexture(nil, "OVERLAY", nil, 0)   -- dark silhouette for contrast
arrowShadow:SetTexture(MEDIA .. "arrow.tga")
arrowShadow:SetVertexColor(0, 0, 0, 0.75)
arrowShadow:SetPoint("CENTER")
local arrow = top:CreateTexture(nil, "OVERLAY", nil, 1)
arrow:SetTexture(MEDIA .. "arrow.tga")
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
-- Each tile layer has one texture per zoom level (loaded once, then kept). Around each switch point the two
-- neighbouring levels are cross-faded, so zooming is seamless; a level that is still loading hands its
-- weight to a loaded one.
local LODS = { 128, 256, 512 }
local SWITCH = { 160, 360 }            -- on-screen tile size (px) where the next finer level takes over
local BAND = 1.25                      -- cross-fade from SWITCH / BAND to SWITCH * BAND
local tiles = {}                       -- ["inst:c_r:layer"] = { layer = name, [lod] = Texture }
local frame = 0                        -- update counter; textures not used in the current update get hidden

-- Note: on textures SetAlpha overwrites the vertex colour alpha, so opacity only goes through SetVertexColor
local function ApplyColor(t, layer, weight)
    local c = db.colors[layer]
    t:SetVertexColor(c.r, c.g, c.b, c.a * (weight or 1))
end

local function TilePath(inst, key, layer, lod)
    return PATH .. inst .. "\\" .. (lod < 512 and (lod .. "\\") or "") .. key .. "_" .. layer .. ".tga"
end

local function IsLoaded(t)
    return not t.IsObjectLoaded or t:IsObjectLoaded()
end

local function GetTex(e, inst, key, lod)
    local t = e[lod]
    if not t then
        t = canvas:CreateTexture(nil, "ARTWORK", nil, LAYER_LEVEL[e.layer])
        Fade(t)
        NoSnap(t)
        if e.layer == "hatch" then
            if not e.mask then
                e.mask = canvas:CreateMaskTexture()
                NoSnap(e.mask)
            end
            if not e.maskSet then
                e.mask:SetTexture(TilePath(inst, key, "hatch", HATCH_MASK_LOD), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                e.maskSet = true
            end
            t:AddMaskTexture(e.mask)
            t:SetTexture(MEDIA .. "hatch" .. lod .. ".tga")
        else
            t:SetTexture(TilePath(inst, key, e.layer, lod))
        end
        e[lod] = t
    end
    return t
end

-- Weights of the zoom levels for an on-screen tile size: { [lod] = weight }
local function LodWeights(size)
    for i, sw in ipairs(SWITCH) do
        if size < sw * BAND then
            local lo, hi = LODS[i], LODS[i + 1]
            if size <= sw / BAND then return lo, 1, hi, 0 end
            local f = math.log(size * BAND / sw) / math.log(BAND * BAND)
            f = f * f * (3 - 2 * f)
            return lo, 1 - f, hi, f
        end
    end
    return 512, 1, 256, 0
end

local function ApplyColors()
    for _, e in pairs(tiles) do
        for _, lod in ipairs(LODS) do
            if e[lod] then ApplyColor(e[lod], e.layer, e[lod].weight) end
        end
    end
    if ns.ApplyQuestAreaColor then ns.ApplyQuestAreaColor() end
end

local function HideTiles()
    for _, e in pairs(tiles) do
        for _, lod in ipairs(LODS) do
            if e[lod] then e[lod]:Hide() end
        end
    end
end

local function PlaceMask(m, x, y, size, angle)
    m:ClearAllPoints()
    m:SetPoint("CENTER", view, "CENTER", x, y)
    m:SetSize(size, size)
    m:SetRotation(angle)
end

local function PlaceTex(t, x, y, size, angle, layer, weight)
    t:ClearAllPoints()
    t:SetPoint("CENTER", view, "CENTER", x, y)
    t:SetSize(size, size)
    t:SetRotation(angle)
    if t.weight ~= weight then
        t.weight = weight
        ApplyColor(t, layer, weight)
    end
    t.frame = frame
    t:Show()
end

local function UpdateTiles(inst, angle)
    local data = RunewayTiles and RunewayTiles[inst]
    frame = frame + 1
    if not data then HideTiles() return false end

    local W, H = view:GetSize()
    local reach = math.sqrt(W * W + H * H) / 2 / k + T   -- visible radius in yards plus one tile
    local size = T * k
    local loA, wA, loB, wB = LodWeights(size)

    for key, have in pairs(data) do
        local c, r = key:match("(%d+)_(%d+)")
        c, r = tonumber(c), tonumber(r)
        local cn = (32 - r) * T - T / 2
        local cw = (32 - c) * T - T / 2
        if math.abs(cn - pN) < reach and math.abs(cw - pW) < reach then
            local x, y = ToScreen(cn, cw)
            for _, layer in ipairs(LAYERS) do
                if db.layers[layer] and have:find(LAYER_CODE[layer], 1, true) and (layer ~= "hatch" or fade) then
                    local id = inst .. ":" .. key .. ":" .. layer
                    local e = tiles[id]
                    if not e then e = { layer = layer }; tiles[id] = e end
                    -- levels not stored for this layer: the nearest stored one, cross-fade only between two files
                    local fl = FILE_LOD[layer]
                    local la, lb, ta, tb = loA, loB, wA, wB
                    if fl then la, lb = fl[loA], fl[loB] end
                    if la == lb then ta, tb = 1, 0 end
                    local a = GetTex(e, inst, key, la)
                    local b = tb > 0 and GetTex(e, inst, key, lb)
                    if e.mask then PlaceMask(e.mask, x, y, size, angle) end
                    local okA, okB = IsLoaded(a), b and IsLoaded(b)
                    if not okA and okB then ta, tb = 0, 1 elseif okA and b and not okB then ta, tb = 1, 0 end
                    if not okA and not okB then
                        -- nothing loaded yet for these levels: keep any loaded level of this tile on screen
                        for _, lod in ipairs(LODS) do
                            local t = e[lod]
                            if t and t ~= a and t ~= b and IsLoaded(t) then
                                PlaceTex(t, x, y, size, angle, layer, 1)
                                break
                            end
                        end
                    end
                    PlaceTex(a, x, y, size, angle, layer, okA and ta or 0)   -- shown at weight 0 while loading
                    if b then PlaceTex(b, x, y, size, angle, layer, okB and tb or 0) end
                end
            end
        end
    end
    for _, e in pairs(tiles) do
        for _, lod in ipairs(LODS) do
            local t = e[lod]
            if t and t.frame ~= frame then
                if t:IsShown() then t:Hide() end
                if frame - t.frame > 800 then          -- unused for ~20 s: free the texture memory
                    t:SetTexture(nil)
                    e[lod] = nil
                end
            end
        end
        if e.maskSet and not (e[128] or e[256] or e[512]) then
            e.mask:SetTexture(nil)
            e.maskSet = false
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
-- Maps the player is not on (neighbouring zones) use the order found on another map.
local swapByMap, anySwap = {}, nil
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
                swapByMap[mapID], anySwap = swap, swap
            end
        end
        if swap == nil then swap = anySwap end
    end
    if swap then return b, a end
    return a, b
end
ns.MapToWorld = MapToWorld

-- Zone maps near the player: the player's map first, then the zones of the same continent whose map
-- rectangle comes within view reach (+ margin), nearest first. Quest areas and pins come from all of them.
local REACH_MARGIN = 200                 -- yards beyond the map corner
local UIMAP_CONTINENT, UIMAP_ZONE = 2, 3 -- Enum.UIMapType
local zoneRect = {}                      -- [mapID] = { n0, n1, w0, w1 } in world yards, or false
local function NearbyMaps()
    local m = C_Map.GetBestMapForUnit("player")
    if not m then return end
    local list = { m }
    local pn, pw = UnitPosition("player")
    if not (pn and C_Map.GetMapInfo and C_Map.GetMapChildrenInfo) then return list end
    local cont, info = m, C_Map.GetMapInfo(m)
    while info and info.mapType ~= UIMAP_CONTINENT and (info.parentMapID or 0) > 0 do
        cont = info.parentMapID
        info = C_Map.GetMapInfo(cont)
    end
    if not (info and info.mapType == UIMAP_CONTINENT) then return list end
    MapToWorld(m, 0, 0)                  -- settles the axis order on the player's map first
    local W, H = view:GetSize()
    local reach = math.sqrt(W * W + H * H) / 2 / db.zoom + REACH_MARGIN
    local found = {}
    for _, c in ipairs(C_Map.GetMapChildrenInfo(cont, UIMAP_ZONE) or {}) do
        local id = c.mapID
        if id ~= m then
            local r = zoneRect[id]
            if r == nil then
                local n0, w0 = MapToWorld(id, 0, 0)
                local n1, w1 = MapToWorld(id, 1, 1)
                r = n0 and n1 and { math.min(n0, n1), math.max(n0, n1), math.min(w0, w1), math.max(w0, w1) } or false
                zoneRect[id] = r
            end
            if r then
                local dn, dw = math.max(r[1] - pn, 0, pn - r[2]), math.max(r[3] - pw, 0, pw - r[4])
                local d = math.sqrt(dn * dn + dw * dw)
                if d < reach then found[#found + 1] = { id, d } end
            end
        end
    end
    table.sort(found, function(a, b) return a[2] < b[2] end)
    for _, f in ipairs(found) do list[#list + 1] = f[1] end
    return list
end
ns.NearbyMaps = NearbyMaps

local function RefreshQuests()
    wipe(quests)
    local maps = NearbyMaps()
    if not (maps and C_QuestLog and C_QuestLog.GetQuestsOnMap) then return end
    local seen = {}          -- a quest can show on two zone maps: the first (nearest) map wins
    for _, mapID in ipairs(maps) do
        for _, q in ipairs(C_QuestLog.GetQuestsOnMap(mapID) or {}) do
            local n, w = MapToWorld(mapID, q.x, q.y)
            if n and not seen[q.questID] then
                seen[q.questID] = true
                local done = (C_QuestLog.IsComplete and C_QuestLog.IsComplete(q.questID))
                    or (C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(q.questID))
                quests[#quests + 1] = { n, w, questID = q.questID, done = done and true or false }
            end
        end
    end
end
ns.RefreshQuests = RefreshQuests

-- Quest pins only for point targets (talk to someone, turn in): quests with an area outline get no pin.
-- Same look as the world map pins: dark round badge with gold rim, "?" for turn-in, yellow "..." in progress.
local function SetAtlasOr(t, atlas, file)
    local ok, res = pcall(t.SetAtlas, t, atlas)
    if not ok or res == false then t:SetTexture(file) end
end

local function UpdateQuestPins()
    local n = 0
    for _, q in ipairs(quests) do
        if not (ns.HasQuestArea and ns.HasQuestArea(q.questID)) then
            n = n + 1
            local p = qpins[n]
            if not p then
                p = { back = top:CreateTexture(nil, "ARTWORK", nil, 0), icon = top:CreateTexture(nil, "ARTWORK", nil, 1) }
                SetAtlasOr(p.back, "UI-QuestPoi-QuestNumber", MEDIA .. "dot.tga")
                for _, t in ipairs({ p.back, p.icon }) do
                    Fade(t)
                    NoSnap(t)
                end
                qpins[n] = p
            end
            if p.size ~= db.pinSize then
                p.size = db.pinSize
                p.back:SetSize(p.size, p.size)
                p.icon:SetSize(p.size, p.size)
            end
            if p.done ~= q.done then
                p.done = q.done
                SetAtlasOr(p.icon, q.done and "UI-QuestIcon-TurnIn-Normal" or "Quest-In-Progress-Icon-yellow",
                    "Interface\\GossipFrame\\ActiveQuestIcon")
            end
            local x, y = ToScreen(q[1], q[2])
            for _, t in ipairs({ p.back, p.icon }) do
                t:ClearAllPoints()
                t:SetPoint("CENTER", view, "CENTER", x, y)
                t:Show()
            end
        end
    end
    for i = n + 1, #qpins do
        qpins[i].back:Hide()
        qpins[i].icon:Hide()
    end
end

---------------------------------------------------------------------------
-- Main loop
---------------------------------------------------------------------------
local elapsed = 0
view:SetScript("OnUpdate", function(self, e)
    elapsed = elapsed + e
    if elapsed < 0.025 then return end
    elapsed = 0
    UpdateInfo()

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
    arrow:SetSize(db.arrowSize, db.arrowSize)
    arrowShadow:SetSize(db.arrowSize + 4, db.arrowSize + 4)
    arrow:SetRotation(db.rotate and 0 or facing)
    arrowShadow:SetRotation(db.rotate and 0 or facing)

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
    db.h = nil
    db.w = math.max(SIZE_MIN, math.min(SIZE_MAX, db.w))
    view:SetSize(db.w, db.w)
end

-- Mouse wheel zooms locked and unlocked; clicks only reach the map when unlocked (locked: they pass through)
local function ApplyLock()
    local unlocked = not db.locked
    view:EnableMouse(unlocked)
    view:EnableMouseWheel(true)
    editHint:SetShown(unlocked)
    grip:SetShown(unlocked)
    ShowBorder(unlocked and db.hover and view:IsMouseOver())
end

local function SetZoom(z)
    db.zoom = math.max(ZOOM_MIN, math.min(ZOOM_MAX, z))
end

view:SetScript("OnDragStart", function(self)
    self:StartMoving()
    ShowInfo(true)
end)
view:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if self.SetUserPlaced then self:SetUserPlaced(false) end
    SavePos()
    ApplyPos()
    ShowInfo()
end)
view:SetScript("OnMouseWheel", function(_, delta)
    if IsShiftKeyDown() and not db.locked then
        db.w = db.w + delta * 30
        ApplySize()
    else
        SetZoom(db.zoom * (delta > 0 and 1.15 or 1 / 1.15))
    end
    ShowInfo()
end)
view:SetScript("OnShow", RefreshQuests)

local function UpdateBorder()
    ShowBorder(not db.locked and db.hover and view:IsMouseOver())
end
view:SetScript("OnEnter", UpdateBorder)
view:SetScript("OnLeave", UpdateBorder)
grip:SetScript("OnEnter", UpdateBorder)
grip:SetScript("OnLeave", UpdateBorder)

-- Square sizing from the top left corner, follows the cursor
local sizeLeft, sizeTop
grip:SetScript("OnMouseDown", function()
    sizeLeft, sizeTop = view:GetLeft(), view:GetTop()
    view:ClearAllPoints()
    view:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", sizeLeft, sizeTop)
    grip:SetScript("OnUpdate", function()
        local x, y = GetCursorPosition()
        local s = view:GetEffectiveScale()
        db.w = math.floor(math.max(x / s - sizeLeft, sizeTop - y / s) + 0.5)
        ApplySize()
        ShowInfo(true)
    end)
end)
grip:SetScript("OnMouseUp", function()
    grip:SetScript("OnUpdate", nil)
    SavePos()
    ApplyPos()
    ShowInfo()
    UpdateBorder()
end)

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
-- Visibility: mode, toggle, auto-hide
---------------------------------------------------------------------------
-- First active auto-hide condition, or nil
local function AutoHideReason()
    local a = db.autoHide
    if a.combat and (InCombatLockdown() or UnitAffectingCombat("player")) then return "combat" end
    if a.instance then
        local inInstance, kind = IsInInstance()
        if inInstance and kind ~= "none" then return "instance" end
    end
    if a.mounted and (IsMounted() or IsFlying() or UnitOnTaxi("player")) then return "mounted" end
    if a.city and IsResting() then return "city" end
end

-- A toggle while auto-hidden (or in permanent mode) overrides until the auto-hide state changes
local override, lastReason
local function UpdateVisibility()
    local reason = AutoHideReason()
    if reason ~= lastReason then
        override, lastReason = nil, reason
    end
    local want
    if override ~= nil then
        want = override
    else
        want = (db.mode == "permanent" or db.shown) and not reason
    end
    if view:IsShown() ~= want then view:SetShown(want) end
end

function Runeway_Toggle()
    if lastReason or db.mode == "permanent" then
        override = not view:IsShown()
    else
        db.shown = not db.shown
    end
    UpdateVisibility()
end

-- Key modes via override bindings (no taint: only binding commands, never protected calls)
local bindOwner = CreateFrame("Frame")
local bindPending, binding = false, false
local mapKeys = {}            -- keys taken over from the world map (for /rnw keys)
local function ApplyBindings()
    if InCombatLockdown() then bindPending = true return end
    bindPending = false
    binding = true            -- our own changes fire UPDATE_BINDINGS: ignore those
    ClearOverrideBindings(bindOwner)
    wipe(mapKeys)
    if db.mode == "mapkey" then
        local keys = { GetBindingKey("TOGGLEWORLDMAP") }
        if #keys == 0 then keys = { "M" } end
        -- priority overrides: other addons or the default UI may override the same key as well
        for _, key in ipairs(keys) do
            SetOverrideBinding(bindOwner, true, key, "RUNEWAY_TOGGLE")
            mapKeys[#mapKeys + 1] = key
        end
        -- the world map moves to the keys of RUNEWAY_WORLDMAP, run through Blizzard's own command
        for _, key in ipairs({ GetBindingKey("RUNEWAY_WORLDMAP") }) do
            SetOverrideBinding(bindOwner, true, key, "TOGGLEWORLDMAP")
        end
    end
    binding = false
end

local function ReportBindings()
    Print(("mode %s, world map key %s"):format(tostring(db.mode),
        table.concat({ GetBindingKey("RUNEWAY_WORLDMAP") }, ", ")))
    Print("TOGGLEWORLDMAP keys: " .. table.concat({ GetBindingKey("TOGGLEWORLDMAP") }, ", "))
    local keys = #mapKeys > 0 and mapKeys or { GetBindingKey("TOGGLEWORLDMAP") }
    for _, key in ipairs(keys) do
        Print(("%s -> %s (without overrides: %s)"):format(key, tostring(GetBindingAction(key, true)),
            tostring(GetBindingAction(key, false))))
    end
end

---------------------------------------------------------------------------
-- Settings API (used by Options.lua and the slash commands)
---------------------------------------------------------------------------
local function ApplyAll()
    ApplyColors()
    canvas:SetAlpha(db.alpha)      -- map layers only; player arrow, quest marks and areas stay opaque
    ApplyEdge()
    ApplySize()
    ApplyPos()
    ApplyLock()
    ApplyBindings()
    UpdateVisibility()
end

local function ResetSettings()
    local shown = db.shown
    wipe(db)
    ApplyDefaults(db, defaults)
    db.shown = shown
    ApplyAll()
end

ns.DEFAULTS = defaults
ns.LAYER_KEYS = { "fill", "hatch", "shade", "terrain", "water", "roads", "questAreas" }
ns.ZOOM_MIN, ns.ZOOM_MAX, ns.SIZE_MIN, ns.SIZE_MAX = ZOOM_MIN, ZOOM_MAX, SIZE_MIN, SIZE_MAX
ns.Print = Print
ns.SetZoom = SetZoom
ns.ApplyAll = ApplyAll
ns.ApplyColors = ApplyColors
ns.ResetSettings = ResetSettings
ns.UpdateVisibility = UpdateVisibility

local function CreateWorldMapButton()
    if not WorldMapFrame then return end
    local b = CreateFrame("Button", nil, WorldMapFrame, "UIPanelButtonTemplate")
    b:SetSize(90, 22)
    b:SetText("Overlay")
    b:SetPoint("TOPRIGHT", WorldMapFrame, "TOPRIGHT", -40, -2)
    b:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 20)
    b:SetScript("OnClick", function()
        HideUIPanel(WorldMapFrame)
        if not view:IsShown() then Runeway_Toggle() end
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
        if style < 4 and db.colors then db.colors.fill = nil end           -- 4: brown fill
        if style < 6 and db.colors then db.colors.questAreas = nil end     -- 5/6: quest area colour
        db.style = STYLE
        db.worldMapKey = nil                                               -- 1.1 test builds: now a key binding
        ApplyDefaults(db, defaults)
        canvas:SetAlpha(db.alpha)      -- map layers only; player arrow, quest marks and areas stay opaque
        ApplyEdge()
        ApplySize()
        ApplyPos()
        ApplyLock()
        CreateWorldMapButton()
        if not fade then Print("Note: this client does not support mask textures, the edge is clipped hard.") end
        self:UnregisterEvent("ADDON_LOADED")
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        self:RegisterEvent("QUEST_LOG_UPDATE")
        self:RegisterEvent("PLAYER_REGEN_DISABLED")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        self:RegisterEvent("UPDATE_BINDINGS")
    elseif event == "UPDATE_BINDINGS" then
        -- key bindings (re)loaded or changed by the player: take the map key over again
        if not binding then ApplyBindings() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        ApplySize()            -- again after WoW's layout restore
        ApplyPos()
        ApplyBindings()
        UpdateVisibility()
        RefreshQuests()
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        if bindPending and event == "PLAYER_REGEN_ENABLED" then ApplyBindings() end
        UpdateVisibility()
    elseif view:IsShown() then
        RefreshQuests()
    end
end)
-- Auto-hide conditions without a reliable event (mounting, flying, resting, instances) are polled
local visElapsed = 0
ev:SetScript("OnUpdate", function(_, e)
    visElapsed = visElapsed + e
    if visElapsed < 0.25 or not db then return end
    visElapsed = 0
    UpdateVisibility()
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
    elseif cmd == "config" or cmd == "options" then
        if ns.OpenOptions then ns.OpenOptions() end
    elseif cmd == "lock" or cmd == "unlock" then
        db.locked = (cmd == "lock")
        ApplyLock()
        Print(db.locked and "locked (clicks pass through)" or "unlocked")
    elseif cmd == "alpha" and n then
        db.alpha = math.max(5, math.min(100, n)) / 100
        canvas:SetAlpha(db.alpha)
        Print(("Opacity %d %%"):format(db.alpha * 100))
    elseif cmd == "zoom" and n then
        SetZoom(n)
        Print(("Zoom %.2f"):format(db.zoom))
    elseif cmd == "size" then
        if n then
            db.w = n
            ApplySize()
        end
        Print(("Size %d x %d"):format(db.w, db.w))
    elseif cmd == "rotate" then
        db.rotate = not db.rotate
        Print(db.rotate and "map rotates with the player" or "north up")
    elseif cmd == "edge" and n then
        db.edge = math.max(1, math.min(#FADE_WIDTH, math.floor(n + 0.5)))
        ApplyEdge()
        Print(("Soft edge %d"):format(db.edge))
    elseif cmd == "mode" and (arg == "key" or arg == "mapkey" or arg == "permanent") then
        db.mode = arg
        ApplyBindings()
        UpdateVisibility()
        Print("mode " .. arg)
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
        -- dev tool, not part of the release: add tools/Probe.lua to the .toc to use it
        if Runeway_Probe then Runeway_Probe(arg) else Print("probe is a dev tool (tools/Probe.lua), not loaded") end
    elseif cmd == "keys" then
        ApplyBindings()
        ReportBindings()
    elseif cmd == "pos" then
        local pn, pw, _, inst = UnitPosition("player")
        local mapID = C_Map.GetBestMapForUnit("player")
        ShowCopy(("%s %s %s map=%s facing=%.3f"):format(
            tostring(pn), tostring(pw), tostring(inst), tostring(mapID), GetPlayerFacing() or -1))
    elseif cmd == "reset" then
        ResetSettings()
        Print("settings reset")
    else
        Print("/rnw [toggle] | config | lock | unlock | alpha 5-100 | zoom 0.08-5 | size N | rotate | edge 1-5"
            .. " | mode key|mapkey|permanent | layer NAME | color NAME R G B [A] | keys | pos | reset")
    end
end
