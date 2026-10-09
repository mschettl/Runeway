-- Runeway
-- Player-centred, rotating contour overlay (line layers per ADT tile in world coordinates)

local ADDON, ns = ...               -- ns: shared by all addon files
local L = ns.L                      -- texts in the client language (Locales/)
local T = 1600 / 3                 -- edge length of an ADT tile in yards (533.33)
local ADDONS = "Interface\\AddOns\\"
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
-- hatch: the tile file is only the mask of the not walkable area (128 px); the lines are one shared pattern
-- per zoom level (media/hatch<lod>.tga), cut out by that mask.
local FILE_LOD = { fill = { [128] = 128, [256] = 128, [512] = 128 }, shade = { [128] = 128, [256] = 128, [512] = 128 } }
local HATCH_MASK_LOD = 128
local STYLE = 6            -- bump when the default colours change: resets the saved colours once (ADDON_LOADED)

-- One calm colour for terrain and water lines (Diablo IV style)
local LINE = { 0xD1 / 255, 0xDB / 255, 0xE3 / 255 }
local defaults = {
    x = nil, y = nil, w = 800, h = 600, -- map width and height
    zoom = 0.3, alpha = 0.7, rotate = true, locked = false, shown = false,
    mode = "key",            -- "key" = own key binding, "mapkey" = map key (M) opens the overlay, "permanent"
    autoHide = { combat = false, instance = false, mounted = false, city = false },
    hover = true,            -- unlocked: subtle frame while the mouse is over the map
    wheelZoom = true,        -- mouse wheel over the map zooms (off: the wheel goes to the game camera)
    edge = 3,                -- soft edge strength, index into FADE_WIDTH
    arrowSize = 25, pinSize = 25, corpseSize = 25, taxiSize = 20, showTaxi = true, questEdge = 0.8,   -- quest edge = width factor of the quest area outline
    questMerge = true,       -- overlapping quest areas as one combined outline
    zoneDim = 0.3,           -- opacity factor of the adjacent zones (the player is not in)
    colors = {               -- defaults as hex: fill #000000, hatch #CCD6E0, shade #000000, lines #D1DBE3,
        fill    = { r = 0, g = 0, b = 0, a = 0.10 },              -- roads #EBB748, quest areas #73C7FF
        hatch   = { r = 0xCC / 255, g = 0xD6 / 255, b = 0xE0 / 255, a = 0.20 },
        shade   = { r = 0, g = 0, b = 0, a = 0.45 },
        terrain = { r = LINE[1], g = LINE[2], b = LINE[3], a = 0.85 },
        water   = { r = LINE[1], g = LINE[2], b = LINE[3], a = 0.80 },
        roads   = { r = 0xEB / 255, g = 0xB7 / 255, b = 0x48 / 255, a = 0.65 },
        questAreas = { r = 0x73 / 255, g = 0xC7 / 255, b = 0xFF / 255, a = 0.90 },
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
BINDING_NAME_RUNEWAY_TOGGLE = L.BINDING_TOGGLE
BINDING_NAME_RUNEWAY_WORLDMAP = L.BINDING_WORLDMAP

-- Addon version from the .toc
function ns.Version()
    local meta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    return meta and meta(ADDON, "Version") or "?"
end

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

local status = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
status:SetPoint("BOTTOM", 0, 6)

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
-- View mode (/rnw view): the map centres on viewAt = { n, w } instead of the player, north up; dragging pans
local viewAt, pan

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
-- Each tile layer has one texture per zoom level (released after ~20 s unused). Around each switch point the two
-- neighbouring levels are cross-faded, so zooming is seamless; a level that is still loading hands its
-- weight to a loaded one.
local LODS = { 128, 256, 512 }
local SWITCH = { 160, 360 }            -- on-screen tile size (px) where the next finer level takes over
local BAND = 1.25                      -- cross-fade from SWITCH / BAND to SWITCH * BAND
local tiles = {}                       -- ["set:c_r:layer"] = { layer = name, [lod] = Texture }
local frame = 0                        -- update counter; textures not used in the current update get hidden

-- Note: on textures SetAlpha overwrites the vertex colour alpha, so opacity only goes through SetVertexColor
local function ApplyColor(t, layer, weight)
    local c = db.colors[layer]
    t:SetVertexColor(c.r, c.g, c.b, c.a * (weight or 1))
end

---------------------------------------------------------------------------
-- Data packs: the tiles of each map live in a load-on-demand addon (Runeway_EasternKingdoms, ...) whose .toc
-- names its maps ("## X-Runeway-Maps: 0"). The pack of a map is loaded when the map is first needed.
local packOf, packTitle, packTried = nil, {}, {}
local setsByUi                          -- interior tile sets per map and uiMap (SetsFor), nil = rebuild
local function PackOf(inst)
    if not packOf then
        packOf = {}
        local api = C_AddOns or {}
        local num, info, meta = api.GetNumAddOns or GetNumAddOns, api.GetAddOnInfo or GetAddOnInfo,
            api.GetAddOnMetadata or GetAddOnMetadata
        for i = 1, num and num() or 0 do
            local name, title = info(i)
            for id in (meta(name, "X-Runeway-Maps") or ""):gmatch("%d+") do
                packOf[tonumber(id)] = name
                -- shown name: the pack's title in the client language ("Runeway - Eastern Kingdoms") without "Runeway - "
                packTitle[name] = title and title:gsub("^Runeway %- ", "") or name:gsub("^Runeway_", "")
            end
        end
    end
    return packOf[inst]
end

-- Chat note for a data pack that cannot be loaded. The pack shows as a link in Runeway blue with its localized
-- title ("[Eastern Kingdoms]"); a click opens a tooltip with pack, reason and fix, a second click closes it.
local PACK_LINK = "|cff66ccff|Haddon:Runeway:pack:%s|h[%s]|h|r"
local function PackFailed(pack)
    Print(L.PACK_FAILED:format(PACK_LINK:format(pack, packTitle[pack])))
end

-- ItemRefTooltip comes with Blizzard_UIPanels_Game, which may load after this addon: look it up on the click
local packTipLink, tipHooked
if EventRegistry then
    EventRegistry:RegisterCallback("SetItemRef", function(_, link)
        local pack = link:match("^addon:Runeway:pack:(.+)$")
        local tip = ItemRefTooltip
        if not pack or not tip then return end
        if not tipHooked then
            tipHooked = true
            tip:HookScript("OnTooltipCleared", function() packTipLink = nil end)   -- other content or closed
        end
        if tip:IsShown() and packTipLink == link then return tip:Hide() end
        tip:SetOwner(UIParent, "ANCHOR_PRESERVE")
        tip:ClearLines()
        tip:SetPadding(16, 0)                                             -- room for the close button
        tip:AddLine(packTitle[pack] or pack, 0.4, 0.8, 1)
        tip:AddLine(L.PACK_TIP_ADDON:format(pack), 1, 1, 1)
        tip:AddLine(L.PACK_TIP_STATUS:format(tostring(packTried[pack])), 1, 0.3, 0.3)
        tip:AddLine(L.PACK_TIP_HINT:format(pack), nil, nil, nil, true)
        tip:Show()
        packTipLink = link
    end, ns)
end

-- Loads the data pack of a map once; reports a pack that cannot be loaded (disabled, wrong version, ...)
local function LoadPack(inst)
    local pack = inst and PackOf(inst)
    if not pack or packTried[pack] then return end
    packTried[pack] = true
    local loaded, reason = (C_AddOns and C_AddOns.LoadAddOn or LoadAddOn)(pack)
    setsByUi = nil                                   -- the pack may bring interior sets
    if not loaded then
        packTried[pack] = _G["ADDON_" .. tostring(reason)] or tostring(reason)
        PackFailed(pack)
    end
end

-- Pack name and reason when the data pack of the player's map could not be loaded, else nil.
-- Without its data the map stays hidden (no quest areas or player arrow on an empty map).
local function MissingPack()
    local inst = select(4, UnitPosition("player"))
    LoadPack(inst)
    local pack = inst and PackOf(inst)
    local state = pack and packTried[pack]
    if type(state) == "string" then return pack, state end
end

-- Tile sets: the map's own ("0", tiles/0) and interior sets "<map>-<uiMap>" (tiles/0-1458 = Undercity below
-- Tirisfal) in the same world coordinates, both in the map's data pack
local function MapOf(set)
    return tonumber((tostring(set):match("^%d+")))
end

local function TilePath(set, key, layer, lod)
    return ADDONS .. PackOf(MapOf(set)) .. "\\tiles\\" .. set .. "\\" .. (lod < 512 and (lod .. "\\") or "") .. key .. "_" .. layer .. ".tga"
end

-- Footprint of an interior set ({ res = cells per tile side, ["c_r"] = "0110..." }): is (n, w) inside?
function ns.InChunks(chunks, n, w)
    if not chunks then return true end
    local res = chunks.res or 16
    local x, y = 32 - w / T, 32 - n / T
    local c, r = math.floor(x), math.floor(y)
    local g = chunks[c .. "_" .. r]
    local i = math.floor((y - r) * res) * res + math.floor((x - c) * res) + 1
    return g ~= nil and g:sub(i, i) == "1"
end

-- Interior sets per "<map>-<uiMap>" (RunewayZones[set].ui), sets with a subzone list first; rebuilt when a
-- data pack loads
local function SetsFor(inst, ui)
    if not setsByUi then
        setsByUi = {}
        for set, z in pairs(RunewayZones or {}) do
            if type(set) == "string" and z.ui then
                local k = MapOf(set) .. "-" .. z.ui
                setsByUi[k] = setsByUi[k] or {}
                table.insert(setsByUi[k], set)
            end
        end
        for _, list in pairs(setsByUi) do
            table.sort(list, function(a, b)
                local sa, sb = RunewayZones[a].subzones and 0 or 1, RunewayZones[b].subzones and 0 or 1
                if sa ~= sb then return sa < sb end
                return a < b
            end)
        end
    end
    return setsByUi[inst .. "-" .. ui]
end

-- Is the player in one of these subzones (AreaTable IDs)? The subzone text may add an article ("Die Ruinen von
-- Lordaeron"), so the area name is matched inside it.
local areaNames = {}
local function InSubzone(ids)
    local sub = GetSubZoneText():lower()
    for _, id in ipairs(ids) do
        if areaNames[id] == nil then areaNames[id] = (C_Map.GetAreaInfo(id) or ""):lower() end
        if areaNames[id] ~= "" and sub:find(areaNames[id], 1, true) then return true end
    end
    return false
end

-- Tile set at the player's position: the first interior set of the player's uiMap whose rules hold
-- (subzones: in one of them and inside the set's footprint; notSubzones: in none of them), else the map's own.
-- Undercity and the Ruins of Lordaeron above it both report uiMap 1458: in the Ruins subzone the throne room,
-- mausoleum and elevators have their own set, the courtyard shows the surface, elsewhere it is Undercity.
local setCache, setTime = {}, {}
local function TileSet(inst)
    local now = GetTime()
    if setTime[inst] and now - setTime[inst] < 0.2 then return setCache[inst] end   -- called several times a frame
    setTime[inst] = now
    LoadPack(inst)
    local ui = C_Map.GetBestMapForUnit("player")
    local n, w = UnitPosition("player")
    local result = inst
    for _, set in ipairs(ui and n and SetsFor(inst, ui) or {}) do
        local z = RunewayZones[set]
        local ok = true
        if z.notSubzones and InSubzone(z.notSubzones) then
            -- with a surface area the excluded subzone only counts there: no height is available, but the Ruins
            -- surface is only reachable on its courtyard; below it (bottom of the elevators) it is Undercity
            ok = z.surfaceArea ~= nil and not ns.InChunks(z.surfaceArea, n, w) and ns.InChunks(z.inside, n, w)
        end
        if ok and z.subzones then
            ok = InSubzone(z.subzones) and ns.InChunks(z.inside, n, w)
        end
        if ok then result = set break end
    end
    setCache[inst] = result
    return result
end

ns.TileSet = function() return TileSet(select(4, UnitPosition("player"))) end   -- for tests

-- Inside an interior set: its footprint. The interior's uiMap can also list quests of the surface around it
-- (Undercity: Scarlet Crusade quests of Tirisfal); areas and pins outside are left out.
function ns.InteriorChunks()
    local inst = select(4, UnitPosition("player"))
    local set = inst and TileSet(inst)
    return set ~= inst and RunewayZones[set].inside or nil
end

local function IsLoaded(t)
    return not t.IsObjectLoaded or t:IsObjectLoaded()
end

local function GetTex(e, set, key, lod)
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
                e.mask:SetTexture(TilePath(set, key, "hatch", HATCH_MASK_LOD), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                e.maskSet = true
            end
            t:AddMaskTexture(e.mask)
            t:SetTexture(MEDIA .. "hatch" .. lod .. ".tga")
        else
            t:SetTexture(TilePath(set, key, e.layer, lod))
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

-- Zone dimming: the zone the player stands in is drawn in full, all other zones with db.zoneDim.
-- The zone comes from the tile data (zone per tile, per chunk on border tiles), so it matches the map.
local zoneAlpha, lastZoneTime = {}, nil      -- [zone] = current factor, eased towards the target
local ZONE_DIGITS = "123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"   -- one character per chunk
local function ActiveZone(zones)
    local fc, fr = 32 - pW / T, 32 - pN / T
    local c, r = math.floor(fc), math.floor(fr)
    local key = c .. "_" .. r
    local g = zones.chunks[key]
    if g then
        local i = math.floor((fr - r) * 16) * 16 + math.floor((fc - c) * 16) + 1
        return ZONE_DIGITS:find(g:sub(i, i), 1, true)
    end
    return zones.tile[key]
end

local function UpdateZoneAlpha(zones)
    local now = GetTime()
    local step = lastZoneTime and math.min(1, (now - lastZoneTime) / 0.4) or 1   -- ~0.4 s cross-fade
    lastZoneTime = now
    local active = ActiveZone(zones)
    for z in ipairs(zones.names) do
        local target = (not active or z == active) and 1 or db.zoneDim
        local a = zoneAlpha[z] or target
        if math.abs(target - a) < 0.01 then a = target else a = a + (target - a) * step end
        zoneAlpha[z] = a
    end
end

ns.ZoneAlpha = function() return zoneAlpha end     -- for tests

-- Tile list of a tile set (tiles/<set>/Tiles.lua) indexed by "c_r": { { key, layers }, ... } (several parts on
-- zone border tiles), built on first use
local tileIndex = {}
local function TileIndex(set)
    local idx = tileIndex[set]
    if idx == nil then
        LoadPack(MapOf(set))
        local data = RunewayTiles and RunewayTiles[set]
        idx = false
        if data then
            idx = {}
            for key, have in pairs(data) do
                local cr = key:match("^%d+_%d+")
                idx[cr] = idx[cr] or {}
                table.insert(idx[cr], { key, have })
            end
        end
        tileIndex[set] = idx
    end
    return idx
end

local function UpdateTiles(set, angle)
    local idx = TileIndex(set)
    frame = frame + 1
    if not idx then HideTiles() return false end
    local zones = RunewayZones and RunewayZones[set]
    if zones then UpdateZoneAlpha(zones) end

    local W, H = view:GetSize()
    local reach = math.sqrt(W * W + H * H) / 2 / k + T   -- visible radius in yards plus one tile
    local size = T * k
    local loA, wA, loB, wB = LodWeights(size)

    local n = math.ceil(reach / T)
    local pc, pr = math.floor(32 - pW / T), math.floor(32 - pN / T)
    for r = pr - n, pr + n do
        for c = pc - n, pc + n do
            local cn = (32 - r) * T - T / 2
            local cw = (32 - c) * T - T / 2
            local list = idx[c .. "_" .. r]
            if list and math.abs(cn - pN) < reach and math.abs(cw - pW) < reach then
                local x, y = ToScreen(cn, cw)
                for _, part in ipairs(list) do
                    local key, have = part[1], part[2]
                    local zf = zones and zoneAlpha[zones.tile[key]] or 1
                    for _, layer in ipairs(LAYERS) do
                        if db.layers[layer] and have:find(LAYER_CODE[layer], 1, true) and (layer ~= "hatch" or fade) then
                            local id = set .. ":" .. key .. ":" .. layer
                            local e = tiles[id]
                            if not e then e = { layer = layer }; tiles[id] = e end
                            -- levels not stored for this layer: the nearest stored one, cross-fade only between two files
                            local fl = FILE_LOD[layer]
                            local la, lb, ta, tb = loA, loB, wA, wB
                            if fl then la, lb = fl[loA], fl[loB] end
                            if la == lb then ta, tb = 1, 0 end
                            local a = GetTex(e, set, key, la)
                            local b = tb > 0 and GetTex(e, set, key, lb)
                            if e.mask then PlaceMask(e.mask, x, y, size, angle) end
                            local okA, okB = IsLoaded(a), b and IsLoaded(b)
                            if not okA and okB then ta, tb = 0, 1 elseif okA and b and not okB then ta, tb = 1, 0 end
                            if not okA and not okB then
                                -- nothing loaded yet for these levels: keep any loaded level of this tile on screen
                                for _, lod in ipairs(LODS) do
                                    local t = e[lod]
                                    if t and t ~= a and t ~= b and IsLoaded(t) then
                                        PlaceTex(t, x, y, size, angle, layer, zf)
                                        break
                                    end
                                end
                            end
                            PlaceTex(a, x, y, size, angle, layer, okA and ta * zf or 0)   -- shown at weight 0 while loading
                            if b then PlaceTex(b, x, y, size, angle, layer, okB and tb * zf or 0) end
                        end
                    end
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
local taxis = {}       -- flight masters: { {n, w}, name =, atlas =, undiscovered =, faction = }
local tpins = {}
ns.TaxiPins, ns.Taxis = tpins, taxis    -- for tests

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
-- Interior sets have their own level: inside (Undercity) only the interior's map counts; on the surface the
-- maps with an interior set are left out (also when the player's map is one, as in the Ruins of Lordaeron).
local REACH_MARGIN = 200                 -- yards beyond the map corner
local UIMAP_CONTINENT, UIMAP_ZONE = 2, 3 -- Enum.UIMapType
local zoneRect = {}                      -- [mapID] = { n0, n1, w0, w1 } in world yards, or false
local function NearbyMaps()
    local m = C_Map.GetBestMapForUnit("player")
    if not m then return end
    local pn, pw, _, inst = UnitPosition("player")
    if inst and TileSet(inst) ~= inst then return { m } end
    local function Interior(id) return inst and SetsFor(inst, id) end
    local list = {}
    if not Interior(m) then list[1] = m end
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
        if id ~= m and not Interior(id) then
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

-- Discovered flight points: isUndiscovered of GetTaxiNodesForMap is always false in this client, so the
-- nodes a flight master lists as known (taxi map, type ~= "NONE") are kept per character by name
local UNDISCOVERED_ATLAS = "Taxi_Frame_Green"  -- flight map node icons (Mario's choice from /rnw taxi icons)
local KNOWN_ATLAS = "Taxi_Frame_Gray"          -- else the node's world map atlas
local function KnownTaxiNodes()
    db.taxiKnown = db.taxiKnown or {}
    local key = (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "")
    db.taxiKnown[key] = db.taxiKnown[key] or {}
    return db.taxiKnown[key]
end
local function LearnTaxiNodes()
    if not (NumTaxiNodes and TaxiNodeName and TaxiNodeGetType) then return end
    local known = KnownTaxiNodes()
    for i = 1, NumTaxiNodes() do
        if TaxiNodeGetType(i) ~= "NONE" then known[TaxiNodeName(i)] = true end
    end
end

local function RefreshQuests()
    wipe(quests)
    local maps = NearbyMaps()
    if not (maps and C_QuestLog and C_QuestLog.GetQuestsOnMap) then return end
    local seen = {}          -- a quest can show on two zone maps: the first (nearest) map wins
    local inside = ns.InteriorChunks()
    for _, mapID in ipairs(maps) do
        for _, q in ipairs(C_QuestLog.GetQuestsOnMap(mapID) or {}) do
            local n, w = MapToWorld(mapID, q.x, q.y)
            local done = (C_QuestLog.IsComplete and C_QuestLog.IsComplete(q.questID))
                or (C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(q.questID))
            -- inside an interior only quests with an area are filtered by its footprint (areas of the surface
            -- around it); turn-ins and talk-to targets of the interior always show
            local area = not done and GetQuestPOIBlobCount and GetQuestPOIBlobCount(q.questID) > 0
            if n and not seen[q.questID] and (not area or ns.InChunks(inside, n, w)) then
                seen[q.questID] = true
                quests[#quests + 1] = { n, w, questID = q.questID, done = done and true or false }
            end
        end
    end
    -- flight masters of the same maps, as on the world map (C_TaxiMap: discovered or not, own faction and neutral).
    -- On the surface also those of the interior maps (Undercity's bat handler), as they are reached from there.
    wipe(taxis)
    if not (db.showTaxi and C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then return end
    local faction, seenNode, known = UnitFactionGroup("player"), {}, KnownTaxiNodes()
    local FP = Enum and Enum.FlightPathFaction or {}
    local inst = select(4, UnitPosition("player"))
    if not inside and inst then
        local list, has = {}, {}
        for _, id in ipairs(maps) do list[#list + 1], has[id] = id, true end
        for set, z in pairs(RunewayZones or {}) do
            if type(set) == "string" and z.ui and MapOf(set) == inst and not has[z.ui] then
                list[#list + 1], has[z.ui] = z.ui, true
            end
        end
        maps = list
    end
    -- not limited by ShouldMapShowTaxiNodes: it only says whether Blizzard's world map shows them on that map
    for _, mapID in ipairs(maps) do
        for _, t in ipairs(C_TaxiMap.GetTaxiNodesForMap(mapID) or {}) do
            local own = (t.faction ~= FP.Horde or faction == "Horde") and (t.faction ~= FP.Alliance or faction == "Alliance")
            local n, w = MapToWorld(mapID, t.position.x, t.position.y)
            -- "zzOLD..." = retired nodes still in the client data
            if n and own and not seenNode[t.nodeID] and not t.name:find("^zz") and ns.InChunks(inside, n, w) then
                seenNode[t.nodeID] = true
                local undiscovered = t.isUndiscovered or not known[t.name]
                taxis[#taxis + 1] = { n, w, name = t.name, atlas = undiscovered and UNDISCOVERED_ATLAS or KNOWN_ATLAS, nodeAtlas = t.atlasName,
                                      undiscovered = undiscovered, faction = t.faction }
            end
        end
    end
end
ns.RefreshQuests = RefreshQuests

-- Quest pins only for point targets (talk to someone, turn in): quests with an area outline get no pin.
-- Same look as the world map pins: dark round badge with gold rim, "?" for turn-in, yellow "..." in progress.
local function AtlasExists(atlas)
    return not (C_Texture and C_Texture.GetAtlasInfo) or C_Texture.GetAtlasInfo(atlas) ~= nil
end
-- SetAtlas returns nothing and leaves the texture empty for an unknown atlas, so the atlas is checked first
local function SetAtlasOr(t, atlas, file)
    local ok = AtlasExists(atlas) and pcall(t.SetAtlas, t, atlas)
    if not ok then t:SetTexture(file) end
end

-- Mouse-over (also on the locked, click-through map: the cursor position is polled, no mouse events):
-- the marker under the cursor is enlarged; quest marks and areas get a tooltip like on the minimap.
local HOVER_SCALE = 1.3
local hovered                         -- "arrow", "corpse", a quest pin table or nil

-- Corpse marker while dead (ghost): Blizzard's world map corpse icon. The corpse is looked up on the
-- player's map, then on its parent maps (the graveyard can be in another zone); when it is outside the
-- view, the marker sits on the edge in its direction.
local corpse = top:CreateTexture(nil, "OVERLAY", nil, 2)
corpse:SetTexture("Interface\\Minimap\\POIIcons")
corpse:SetTexCoord(0.56640625, 0.6328125, 0.001953125, 0.03515625)
NoSnap(corpse)
corpse:Hide()
local corpseN, corpseW, corpseCheck = nil, nil, 0

local function FindCorpse()
    if not (C_DeathInfo and C_DeathInfo.GetCorpseMapPosition) then return end
    local m = C_Map.GetBestMapForUnit("player")
    while m and m > 0 do
        local pos = C_DeathInfo.GetCorpseMapPosition(m)
        if pos then return MapToWorld(m, pos:GetXY()) end
        local info = C_Map.GetMapInfo(m)
        m = info and info.parentMapID
    end
end

local function UpdateCorpse()
    if not UnitIsDeadOrGhost("player") then
        corpseN = nil
        corpse:Hide()
        return
    end
    local now = GetTime()
    if not corpseN and now >= corpseCheck then   -- the position is known shortly after releasing
        corpseCheck = now + 1
        corpseN, corpseW = FindCorpse()
    end
    if not corpseN then corpse:Hide() return end
    local x, y = ToScreen(corpseN, corpseW)
    local size = db.corpseSize * (hovered == "corpse" and HOVER_SCALE or 1)
    local W, H = view:GetSize()
    -- keep the whole icon inside the oval map
    local rx, ry = math.max(1, W / 2 - db.corpseSize), math.max(1, H / 2 - db.corpseSize)
    local d = math.sqrt((x / rx) ^ 2 + (y / ry) ^ 2)
    if d > 1 then x, y = x / d, y / d end
    corpse.x, corpse.y = x, y
    corpse:SetSize(size, size)
    corpse:ClearAllPoints()
    corpse:SetPoint("CENTER", view, "CENTER", x, y)
    corpse:Show()
end

local tipKey                          -- what the tooltip shows now (avoids rebuilding it every update)

local function AddQuestLines(questID)
    local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID) or ("#" .. questID)
    GameTooltip:AddLine(title, 1, 0.82, 0)
    for _, o in ipairs(C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(questID) or {}) do
        if o.text and o.text ~= "" then
            local c = o.finished and 0.6 or 1
            GameTooltip:AddLine("-" .. o.text, c, c, c)
        end
    end
end

-- The first tooltip line uses the larger header font; Runeway's tooltips list quest titles of equal rank, so
-- line 1 gets the normal font. Restored when the tooltip is cleared for its next owner.
local tipLine1, tipSmall, tipHooked
local function ShowTip(key, fill)
    if tipKey == key then return end
    tipKey = key
    if not key then
        if GameTooltip:IsOwned(view) then GameTooltip:Hide() end
        return
    end
    GameTooltip:SetOwner(view, "ANCHOR_CURSOR")
    fill()
    tipLine1 = tipLine1 or _G[(GameTooltip:GetName() or "GameTooltip") .. "TextLeft1"]
    if tipLine1 and GameTooltipText then
        if not tipHooked and GameTooltip.HookScript then
            tipHooked = true
            GameTooltip:HookScript("OnTooltipCleared", function()
                if tipSmall and GameTooltipHeaderText then tipLine1:SetFontObject(GameTooltipHeaderText) end
                tipSmall = false
            end)
        end
        local r, g, b = tipLine1:GetTextColor()   -- SetFontObject also resets the color to the font's
        tipLine1:SetFontObject(GameTooltipText)
        tipLine1:SetTextColor(r, g, b)
        tipSmall = true
    end
    GameTooltip:Show()
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
            local size = db.pinSize * (hovered == p and HOVER_SCALE or 1)
            if p.size ~= size then
                p.size = size
                p.back:SetSize(size, size)
                p.icon:SetSize(size, size)
            end
            if p.done ~= q.done then
                p.done = q.done
                SetAtlasOr(p.icon, q.done and "UI-QuestIcon-TurnIn-Normal" or "Quest-In-Progress-Icon-yellow",
                    "Interface\\GossipFrame\\ActiveQuestIcon")
            end
            local x, y = ToScreen(q[1], q[2])
            p.x, p.y, p.questID, p.shown = x, y, q.questID, true
            for _, t in ipairs({ p.back, p.icon }) do
                t:ClearAllPoints()
                t:SetPoint("CENTER", view, "CENTER", x, y)
                t:Show()
            end
        end
    end
    for i = n + 1, #qpins do
        qpins[i].shown = false
        qpins[i].back:Hide()
        qpins[i].icon:Hide()
    end
end

-- Flight masters, below the quest pins: discovered = grey flight map node (else the node's world map atlas),
-- not yet discovered = green flight map node (else the green taxi icon)
local function TaxiAtlas(t)
    if AtlasExists(t.atlas) then return t.atlas end
    return not t.undiscovered and t.nodeAtlas or ""
end
local function UpdateTaxiPins()
    for i, t in ipairs(taxis) do
        local p = tpins[i]
        if not p then
            p = { icon = top:CreateTexture(nil, "ARTWORK", nil, -1) }
            Fade(p.icon)
            NoSnap(p.icon)
            tpins[i] = p
        end
        local atlas = TaxiAtlas(t)
        if p.atlas ~= atlas or p.undiscovered ~= t.undiscovered then
            p.atlas, p.undiscovered = atlas, t.undiscovered
            SetAtlasOr(p.icon, atlas, t.undiscovered and "Interface\\TaxiFrame\\UI-Taxi-Icon-Green"
                or "Interface\\TaxiFrame\\UI-Taxi-Icon-White")
        end
        local size = db.taxiSize * (hovered == p and HOVER_SCALE or 1)
        p.icon:SetSize(size, size)
        local x, y = ToScreen(t[1], t[2])
        p.x, p.y, p.taxi, p.shown = x, y, t, true
        p.icon:ClearAllPoints()
        p.icon:SetPoint("CENTER", view, "CENTER", x, y)
        p.icon:Show()
    end
    for i = #taxis + 1, #tpins do
        tpins[i].shown = false
        tpins[i].icon:Hide()
    end
end

---------------------------------------------------------------------------
-- Main loop
---------------------------------------------------------------------------
local elapsed = 0
-- Cursor -> marker or quest areas under it. Only when the cursor is over the visible (oval) map and no
-- other frame lies on top of it (action bars, minimap ...).
local function CursorFree()
    local foci = GetMouseFoci and GetMouseFoci()
    local f = foci and foci[1] or (GetMouseFocus and GetMouseFocus())
    return not f or f == WorldFrame or f == view or f == UIParent
end

local function UpdateHover()
    local target, quests
    if view:IsShown() and view:IsMouseOver() and CursorFree() then
        local cx, cy = GetCursorPosition()
        local s = view:GetEffectiveScale()
        local vx, vy = view:GetCenter()
        local x, y = cx / s - vx, cy / s - vy
        local W, H = view:GetSize()
        if (x / (W / 2)) ^ 2 + (y / (H / 2)) ^ 2 < 1 then
            local function Near(px, py, size) return (x - px) ^ 2 + (y - py) ^ 2 <= (size / 2) ^ 2 end
            if arrow:IsShown() and Near(0, 0, db.arrowSize) then
                target = "arrow"
            elseif corpse:IsShown() and Near(corpse.x, corpse.y, db.corpseSize) then
                target = "corpse"
            else
                for _, p in ipairs(qpins) do
                    if p.shown and Near(p.x, p.y, db.pinSize) then target = p break end
                end
                for _, p in ipairs(target and {} or tpins) do
                    if p.shown and Near(p.x, p.y, db.taxiSize) then target = p break end
                end
            end
            if not target and ns.QuestAreasAt then
                -- screen -> world: inverse of ToScreen
                local sx, sy = x * cosA + y * sinA, -x * sinA + y * cosA
                quests = ns.QuestAreasAt(pN + sy / k, pW - sx / k)
            end
        end
    end
    if not quests and ns.QuestAreasAt then ns.QuestAreasAt(nil) end
    hovered = target
    if target == "corpse" then
        ShowTip("corpse", function() GameTooltip:SetText(CORPSE_RED or L.CORPSE_MARKER) end)
    elseif type(target) == "table" and target.taxi then
        local t = target.taxi
        ShowTip("t" .. t.name, function()
            GameTooltip:AddLine(t.name, 1, 1, 1)
            if t.undiscovered then             -- Blizzard's world map texts
                local FP = Enum and Enum.FlightPathFaction or {}
                local f = (t.faction == FP.Horde and FACTION_HORDE) or (t.faction == FP.Alliance and FACTION_ALLIANCE)
                local text = f and UNDISCOVERED_FACTION_FLIGHTPOINT and UNDISCOVERED_FACTION_FLIGHTPOINT:format(f)
                    or UNDISCOVERED_NEUTRAL_FLIGHTPOINT
                if text then GameTooltip:AddLine(text, 0.5, 1, 0.5, true) end
            end
        end)
    elseif type(target) == "table" then
        ShowTip("q" .. target.questID, function() AddQuestLines(target.questID) end)
    elseif quests and #quests > 0 then
        ShowTip("a" .. table.concat(quests, ","), function()
            for _, qid in ipairs(quests) do AddQuestLines(qid) end
        end)
    else
        ShowTip(nil)
    end
end

view:SetScript("OnHide", function()
    hovered = nil
    if ns.QuestAreasAt then ns.QuestAreasAt(nil) end
    ShowTip(nil)
end)

view:SetScript("OnUpdate", function(self, e)
    elapsed = elapsed + e
    if elapsed < 0.025 then return end
    elapsed = 0

    local n, w, _, inst = UnitPosition("player")
    if not n then
        HideTiles()
        if ns.HideQuestAreas then ns.HideQuestAreas() end
        status:SetText(L.NO_POSITION)
        return
    end
    if pan then
        local cx, cy = GetCursorPosition()
        local s = view:GetEffectiveScale() * db.zoom
        viewAt.n, viewAt.w = pan.n - (cy - pan.y) / s, pan.w + (cx - pan.x) / s
    end
    if viewAt then n, w = viewAt.n, viewAt.w end
    pN, pW, k = n, w, db.zoom

    local facing = GetPlayerFacing() or 0
    local angle = db.rotate and not viewAt and -facing or 0
    arrow:SetShown(not viewAt)
    arrowShadow:SetShown(not viewAt)
    cosA, sinA = math.cos(angle), math.sin(angle)
    local as = db.arrowSize * (hovered == "arrow" and HOVER_SCALE or 1)
    arrow:SetSize(as, as)
    arrowShadow:SetSize(as + 4, as + 4)
    arrow:SetRotation(db.rotate and 0 or facing)
    arrowShadow:SetRotation(db.rotate and 0 or facing)

    if UpdateTiles(TileSet(inst), angle) then
        status:SetText(viewAt and L.VIEW_MODE or "")
    else
        status:SetText(L.NO_DATA)
    end
    UpdateTaxiPins()
    UpdateQuestPins()
    UpdateCorpse()
    UpdateHover()
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

-- Settings rows show values changed outside the panel (wheel, grip, slash commands) right away
local function Notify(...)
    if not (Settings and Settings.NotifyUpdate) then return end
    for _, path in ipairs({ ... }) do Settings.NotifyUpdate("RUNEWAY_" .. path:upper()) end
end

local function ApplySize()
    db.w = math.floor(math.max(SIZE_MIN, math.min(SIZE_MAX, db.w)) + 0.5)
    db.h = math.floor(math.max(SIZE_MIN, math.min(SIZE_MAX, db.h)) + 0.5)
    view:SetSize(db.w, db.h)
end

-- Mouse wheel zooms locked and unlocked (option); clicks only reach the map when unlocked (locked: they pass through)
local function ApplyLock()
    local unlocked = not db.locked
    view:EnableMouse(unlocked or viewAt ~= nil)      -- view mode: dragging pans, also when locked
    view:EnableMouseWheel(db.wheelZoom)
    grip:SetShown(unlocked)
    ShowBorder(unlocked and db.hover and view:IsMouseOver())
end

local function SetZoom(z)
    db.zoom = math.max(ZOOM_MIN, math.min(ZOOM_MAX, z))
end

view:SetScript("OnDragStart", function(self)
    if viewAt then
        local x, y = GetCursorPosition()
        pan = { x = x, y = y, n = viewAt.n, w = viewAt.w }
    elseif not db.locked then
        self:StartMoving()
    end
end)
view:SetScript("OnDragStop", function(self)
    if pan then pan = nil return end
    self:StopMovingOrSizing()
    if self.SetUserPlaced then self:SetUserPlaced(false) end
    SavePos()
    ApplyPos()
end)
view:SetScript("OnMouseWheel", function(_, delta)
    if IsShiftKeyDown() and not db.locked then
        db.w, db.h = db.w + delta * 30, db.h + delta * 30
        ApplySize()
        Notify("w", "h")
    else
        SetZoom(db.zoom * (delta > 0 and 1.15 or 1 / 1.15))
        Notify("zoom")
    end
end)
view:SetScript("OnShow", RefreshQuests)

local function UpdateBorder()
    ShowBorder(not db.locked and db.hover and view:IsMouseOver())
end
view:SetScript("OnEnter", UpdateBorder)
view:SetScript("OnLeave", UpdateBorder)
grip:SetScript("OnEnter", UpdateBorder)
grip:SetScript("OnLeave", UpdateBorder)

-- Sizing from the top left corner, width and height follow the cursor
local sizeLeft, sizeTop
grip:SetScript("OnMouseDown", function()
    sizeLeft, sizeTop = view:GetLeft(), view:GetTop()
    view:ClearAllPoints()
    view:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", sizeLeft, sizeTop)
    grip:SetScript("OnUpdate", function()
        local x, y = GetCursorPosition()
        local s = view:GetEffectiveScale()
        db.w, db.h = x / s - sizeLeft, sizeTop - y / s
        ApplySize()
        Notify("w", "h")
    end)
end)
grip:SetScript("OnMouseUp", function()
    grip:SetScript("OnUpdate", nil)
    SavePos()
    ApplyPos()
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
    want = want and not MissingPack()
    if view:IsShown() ~= want then view:SetShown(want) end
end

function Runeway_Toggle()
    local pack = MissingPack()
    if pack then return PackFailed(pack) end
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
    end
    -- keys of RUNEWAY_WORLDMAP always run Blizzard's own command (calling ToggleWorldMap from addon code
    -- would taint the panel system)
    for _, key in ipairs({ GetBindingKey("RUNEWAY_WORLDMAP") }) do
        SetOverrideBinding(bindOwner, true, key, "TOGGLEWORLDMAP")
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
ns.UpdateVisibility = UpdateVisibility

local function CreateWorldMapButton()
    if not WorldMapFrame then return end
    local b = CreateFrame("Button", nil, WorldMapFrame, "UIPanelButtonTemplate")
    b:SetSize(90, 22)
    b:SetText(L.WORLDMAP_BUTTON)
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
local announced = false
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(self, event, arg1, ...)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        RunewayDB = RunewayDB or {}
        db = RunewayDB
        if (db.style or 0) < STYLE then db.colors = nil end   -- default look changed: colours back to defaults
        db.style = STYLE
        ApplyDefaults(db, defaults)
        canvas:SetAlpha(db.alpha)      -- map layers only; player arrow, quest marks and areas stay opaque
        ApplyEdge()
        ApplySize()
        ApplyPos()
        ApplyLock()
        CreateWorldMapButton()
        if not fade then Print(L.NO_MASKS) end
        self:UnregisterEvent("ADDON_LOADED")
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        self:RegisterEvent("QUEST_LOG_UPDATE")
        self:RegisterEvent("TAXIMAP_OPENED")              -- talking to a flight master discovers its node
        self:RegisterEvent("TAXI_NODE_STATUS_CHANGED")
        self:RegisterEvent("PLAYER_REGEN_DISABLED")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        self:RegisterEvent("UPDATE_BINDINGS")
        self:RegisterEvent("ADDON_ACTION_BLOCKED")
        self:RegisterEvent("ADDON_ACTION_FORBIDDEN")
    elseif event == "UPDATE_BINDINGS" then
        -- key bindings (re)loaded or changed by the player: take the map key over again
        if not binding then ApplyBindings() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if not announced then                 -- once per login / reload: name and version in the chat
            announced = true
            Print(L.LOADED:format(ns.Version()))
        end
        ApplySize()            -- again after WoW's layout restore
        ApplyPos()
        ApplyBindings()
        LoadPack(select(4, UnitPosition("player")))   -- behind the loading screen rather than on the first frame
        UpdateVisibility()
        RefreshQuests()
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        -- taint diagnostics: name the protected function the game blocked under our name
        local func = ...                       -- payload: addon name, function name
        if arg1 == ADDON then Print(("%s: %s"):format(event, tostring(func))) end
    elseif event == "TAXIMAP_OPENED" or event == "TAXI_NODE_STATUS_CHANGED" then
        LearnTaxiNodes()
        if view:IsShown() then RefreshQuests() end
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
-- Centre (north, west) of a mapped zone whose name contains `name` (lower case), or nil and the list of
-- mapped zones
local function ZoneCentre(inst, name)
    LoadPack(inst)
    local zones = RunewayZones and RunewayZones[inst]
    if not zones then return end
    for z, zn in ipairs(zones.names) do
        if zn:lower():find(name, 1, true) then
            local sn, sw, cnt = 0, 0, 0
            for key, kz in pairs(zones.tile) do
                if kz == z then
                    local c, r = key:match("^(%d+)_(%d+)")
                    sn, sw, cnt = sn + (32 - tonumber(r)) * T - T / 2, sw + (32 - tonumber(c)) * T - T / 2, cnt + 1
                end
            end
            if cnt > 0 then return sn / cnt, sw / cnt, zn end
        end
    end
    return nil, nil, table.concat(zones.names, ", ")
end

-- Layer key from a lower-cased slash argument ("questareas" -> "questAreas")
local function LayerKey(name)
    for key in pairs(defaults.layers) do
        if key:lower() == name then return key end
    end
end

SLASH_RUNEWAY1 = "/runeway"
SLASH_RUNEWAY2 = "/rnw"
-- /rnw taxi icons: atlases of the retail client for flight masters, and two classic textures
local TAXI_ICONS = { "FlightMaster", "FlightPath", "TaxiNode_Neutral", "TaxiNode_Horde", "TaxiNode_Alliance",
    "TaxiNode_Continent_Neutral", "TaxiNode_Continent_Horde", "Taxi_Frame_Green", "Taxi_Frame_Gray", "Taxi_Frame_Yellow",
    "TaxiNode_Undiscovered", "Crosshair_Taxi_32", "Interface\\Minimap\\Tracking\\FlightMaster",
    "Interface\\TaxiFrame\\UI-Taxi-Icon-Green" }
-- /rnw quest icons: turn-in icons of the retail client; "+" = on the quest pin badge as Runeway draws it
local QUEST_ICONS = { "UI-QuestIcon-TurnIn-Normal+", "UI-QuestPoi-QuestBangTurnIn+", "UI-QuestPoi-QuestBangTurnIn",
    "UI-QuestIcon-TurnIn-Normal", "QuestTurnin", "UI-QuestPoiCampaign-QuestBangTurnIn",
    "UI-QuestPoiImportant-QuestBangTurnIn", "UI-QuestPoiRecurring-QuestBangTurnIn", "UI-QuestPoiLegendary-QuestBangTurnIn",
    "UI-QuestPoiWrapper-QuestBangTurnIn", "UI-DailyQuestPoiCampaign-QuestBangTurnIn", "Callings-Turnin",
    "questlog-questtypeicon-legendaryturnin", "Interface\\GossipFrame\\ActiveQuestIcon" }

-- Icons side by side, numbered, 40 px; "(-)" = atlas missing in this client. A click hides the panel.
local previews = {}
local function IconPreview(list)
    local f = previews[list]
    if not f then
        f = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
        f:SetPoint("CENTER", 0, 150)
        f:SetFrameStrata("DIALOG")
        if f.SetBackdrop then
            f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
            f:SetBackdropColor(0, 0, 0, 0.8)
        end
        f:SetScript("OnClick", f.Hide)
        for i, entry in ipairs(list) do
            local a, badge = entry:match("^(.-)(%+?)$")
            local x = ((i - 1) % 7) * 90 + 10
            local y = -math.floor((i - 1) / 7) * 90 - 10
            local t = f:CreateTexture(nil, "ARTWORK", nil, 1)
            t:SetSize(40, 40)
            t:SetPoint("TOPLEFT", x + 25, y)
            if badge ~= "" then
                local b = f:CreateTexture(nil, "ARTWORK", nil, 0)
                b:SetAllPoints(t)
                SetAtlasOr(b, "UI-QuestPoi-QuestNumber", MEDIA .. "dot.tga")
            end
            local file = a:find("\\") and a
            if file then t:SetTexture(file) else SetAtlasOr(t, a, "Interface\\Icons\\INV_Misc_QuestionMark") end
            local l = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            l:SetPoint("TOP", t, "BOTTOM", 0, -4)
            l:SetWidth(88)
            l:SetText(i .. ". " .. (file and a:match("[^\\]+$") or a) .. (badge ~= "" and " +" or "")
                .. ((file or AtlasExists(a)) and "" or " (-)"))
        end
        f:SetSize(7 * 90 + 20, math.ceil(#list / 7) * 90 + 20)
        previews[list] = f
    end
    for _, p in pairs(previews) do p:Hide() end
    f:Show()
end

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
        Print(db.locked and L.MSG_LOCKED or L.MSG_UNLOCKED)
    elseif cmd == "alpha" and n then
        db.alpha = math.max(5, math.min(100, n)) / 100
        canvas:SetAlpha(db.alpha)
        Print(L.MSG_OPACITY:format(db.alpha * 100))
    elseif cmd == "zoom" and n then
        SetZoom(n)
        Notify("zoom")
        Print(L.MSG_ZOOM:format(db.zoom))
    elseif cmd == "size" then
        local w, h = arg:match("^(%d+)%s*(%d*)$")
        if w then
            db.w, db.h = tonumber(w), tonumber(h) or tonumber(w)
            ApplySize()
            Notify("w", "h")
        end
        Print(L.MSG_SIZE:format(db.w, db.h))
    elseif cmd == "rotate" then
        db.rotate = not db.rotate
        Print(db.rotate and L.MSG_ROTATE_ON or L.MSG_ROTATE_OFF)
    elseif cmd == "edge" and n then
        db.edge = math.max(1, math.min(#FADE_WIDTH, math.floor(n + 0.5)))
        ApplyEdge()
        Print(L.MSG_EDGE:format(db.edge))
    elseif cmd == "mode" and (arg == "key" or arg == "mapkey" or arg == "permanent") then
        db.mode = arg
        ApplyBindings()
        UpdateVisibility()
        Print(L.MSG_MODE:format(arg))
    elseif cmd == "layer" and LayerKey(arg) then
        local key = LayerKey(arg)
        db.layers[key] = not db.layers[key]
        Print((db.layers[key] and L.MSG_LAYER_SHOWN or L.MSG_LAYER_HIDDEN):format(key))
    elseif cmd == "color" then
        local layer, r, g, b, a = arg:match("^(%a+)%s+([%d.]+)%s+([%d.]+)%s+([%d.]+)%s*([%d.]*)")
        layer = layer and LayerKey(layer)
        local c = layer and db.colors[layer]
        if c then
            c.r, c.g, c.b = tonumber(r), tonumber(g), tonumber(b)
            c.a = tonumber(a) or c.a
            ApplyColors()
            Print(L.MSG_COLOUR:format(layer, c.r, c.g, c.b, c.a))
        else
            Print(L.USAGE_COLOR)
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
        ShowCopy(("%s %s %s map=%s set=%s facing=%.3f"):format(tostring(pn), tostring(pw), tostring(inst),
            tostring(mapID), tostring(inst and TileSet(inst)), GetPlayerFacing() or -1))
    elseif (cmd == "taxi" or cmd == "quest") and arg == "icons" then   -- candidate icons side by side
        IconPreview(cmd == "taxi" and TAXI_ICONS or QUEST_ICONS)
    elseif cmd == "taxi" then                      -- flight masters: what the map draws, nearest first
        local list = {}
        for _, t in ipairs(taxis) do list[#list + 1] = { t, math.sqrt((t[1] - pN) ^ 2 + (t[2] - pW) ^ 2) } end
        table.sort(list, function(a, b) return a[2] < b[2] end)
        local known = 0
        for _ in pairs(KnownTaxiNodes()) do known = known + 1 end
        Print(("taxi: maps=%s nodes=%d known=%d showTaxi=%s"):format(table.concat(NearbyMaps() or {}, ","), #taxis,
            known, tostring(db.showTaxi)))
        for i = 1, math.min(5, #list) do
            local t = list[i][1]
            Print(("  %s %.0f yd undiscovered=%s atlas=%s(%s) icon=%s"):format(t.name, list[i][2], tostring(t.undiscovered),
                tostring(t.atlas), AtlasExists(t.atlas or "") and "ok" or "missing", TaxiAtlas(t)))
        end
    elseif cmd == "view" then
        local vn, vw = arg:match("^(%-?[%d%.]+)%s+(%-?[%d%.]+)$")
        if arg == "" and viewAt then
            viewAt, pan = nil, nil
            Print(L.MSG_VIEW_OFF)
        elseif arg == "" then                       -- start at the player position
            viewAt = { n = pN, w = pW }
            Print(L.MSG_VIEW:format(("%.0f %.0f"):format(pN, pW)))
        elseif vn then
            viewAt = { n = tonumber(vn), w = tonumber(vw) }
            Print(L.MSG_VIEW:format(("%.0f %.0f"):format(viewAt.n, viewAt.w)))
        else
            local name
            vn, vw, name = ZoneCentre(select(4, UnitPosition("player")), arg)
            if vn then
                viewAt = { n = vn, w = vw }
                Print(L.MSG_VIEW:format(name))
            else
                Print(L.MSG_VIEW_UNKNOWN:format(name or "-"))
            end
        end
        ApplyLock()
        if viewAt and not view:IsShown() then Runeway_Toggle() end
    elseif cmd == "reset" then
        ResetSettings()
        Print(L.MSG_RESET)
    else
        Print(L.USAGE)
    end
end
