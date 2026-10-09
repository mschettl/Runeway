# Loads the addon with a WoW API stub, fires the login events, renders frames and runs slash commands.
#   python tests/run_stub.py
import os
import re
import glob
import lupa
from lupa import lua51       # WoW runs Lua 5.1

ROOT = os.path.join(os.path.dirname(__file__), '..')
L = lua51.LuaRuntime(unpack_returned_tuples=True)
L.execute(open(os.path.join(ROOT, 'tests', 'wow_stub.lua')).read())
# undefined globals read by addon code: usually a local used before its declaration (a nil global)
L.execute('''
UNDEFINED_GLOBALS = {}
setmetatable(_G, { __index = function(_, k)
    local i = debug.getinfo(2, "S")
    if i and i.source:find("Runeway/", 1, true) then UNDEFINED_GLOBALS[k] = i.short_src end
end })''')
LOCALES = ['Runeway/Locales/enUS.lua'] + sorted(f'Runeway/Locales/{os.path.basename(p)}' for p in glob.glob(os.path.join(ROOT, 'Runeway', 'Locales', '*.lua')) if not p.endswith('enUS.lua'))
L.execute('LOCALE = ...', os.environ.get('RUNEWAY_LOCALE', 'enUS'))   # client language for this run
L.execute('TOC_VERSION = ...', re.search(r'## Version: (\S+)', open(os.path.join(ROOT, 'Runeway', 'Runeway.toc')).read())[1])
# installed addons: the core plus every data pack folder (<pack>/<pack>.toc) for C_AddOns; LoadAddOn runs the
# pack's files. DISABLED_ADDONS makes LoadAddOn fail like a pack switched off in the addon list.
def read_toc(name):
    toc = open(os.path.join(ROOT, name, name + '.toc'), encoding='utf8').read()
    meta = dict(re.findall(r'^## ([\w-]+): (.*?)\s*$', toc, re.M))
    files = [ln.strip() for ln in toc.splitlines() if ln.strip() and not ln.startswith('#')]
    return meta, files
packs = sorted(n for n in os.listdir(ROOT) if n.startswith('Runeway_') and os.path.isfile(os.path.join(ROOT, n, n + '.toc')))
L.execute('''
    ADDON_LIST, LOADED_ADDONS, DISABLED_ADDONS, ADDON_DISABLED = {}, {}, {}, "Disabled"
    local read = ...
    C_AddOns.GetNumAddOns = function() return #ADDON_LIST end
    C_AddOns.GetAddOnInfo = function(i)
        local a = ADDON_LIST[i]
        return a.name, a.meta["Title-" .. LOCALE] or a.meta.Title
    end
    C_AddOns.GetAddOnMetadata = function(name, field)
        if name == "Runeway" and field == "Version" then return TOC_VERSION end
        for _, a in ipairs(ADDON_LIST) do if a.name == name then return a.meta[field] end end
    end
    C_AddOns.LoadAddOn = function(name)
        if DISABLED_ADDONS[name] then return false, "DISABLED" end
        for _, a in ipairs(ADDON_LIST) do
            if a.name == name then
                for _, f in ipairs(a.files) do
                    local path = name .. "/" .. f:gsub(string.char(92), "/")
                    assert(loadstring(read(path), "@" .. path))(name, {})
                end
                LOADED_ADDONS[#LOADED_ADDONS + 1] = name
                return true
            end
        end
        return false, "MISSING"
    end''', lambda path: open(os.path.join(ROOT, path), encoding='utf8').read())
add = L.eval('function(name, meta, files) table.insert(ADDON_LIST, { name = name, meta = meta, files = files }) end')
add('Runeway', L.table_from({'Version': 'x'}), L.table_from([]))
for name in packs:
    meta, files = read_toc(name)
    add(name, L.table_from(meta), L.table_from(files))
add('Runeway_Test', L.table_from({'X-Runeway-Maps': '1', 'Title': 'Runeway - Test Lands', 'Title-deDE': 'Runeway - Testlande'}),
    L.table_from([]))   # pack of map 1, switched off
L.execute('DISABLED_ADDONS.Runeway_Test = true')
for f in (*LOCALES, 'Runeway/Core.lua', 'Runeway/QuestAreas.lua', 'Runeway/Profile.lua', 'Runeway/Options.lua', 'tools/Probe.lua'):
    src = open(os.path.join(ROOT, f), encoding='utf8').read()
    L.execute('NS = NS or {}; local f = assert(loadstring(..., "@' + f + '")); f("Runeway", NS)', src)

L.execute('''
    function fire(event, ...)
        for _, f in ipairs(FRAMES) do
            local h = f:GetScript("OnEvent")
            if h then h(f, event, ...) end
        end
    end
    fire("ADDON_LOADED", "Runeway")
    fire("PLAYER_LOGIN")
    fire("PLAYER_ENTERING_WORLD", true, false)
    print("data packs loaded at login:", table.concat(LOADED_ADDONS, ", "), RunewayTiles and RunewayTiles[0] and "ok" or "FAIL")
    SlashCmdList.RUNEWAY("toggle")
    local upd = RunewayFrame:GetScript("OnUpdate")
    upd(RunewayFrame, 0.05)
    print("textures after first frame:", #TEXTURES)
    for i = 1, math.min(4, #TEXTURES) do print("  " .. TEXTURES[i]) end
    SlashCmdList.RUNEWAY("layer roads")
    SlashCmdList.RUNEWAY("color water 0.2 0.4 1")
    -- zoom level change with slow texture loading: every visible tile layer must keep a shown texture
    LOAD_FRAMES = 3
    SlashCmdList.RUNEWAY("zoom 28.5714285714")   -- 0.5
    local function check(label)
        upd(RunewayFrame, 0.05)
        local visible, loading = 0, 0
        for _, f in ipairs(FRAMES) do end
        for _, t in ipairs(ALL_TEX) do
            local col = rawget(t, "_color")
            local a = col and col[4] or 1
            if rawget(t, "_shown") and a > 0 then visible = visible + 1 end
            if rawget(t, "_shown") and a == 0 then loading = loading + 1 end
        end
        print(label, "visible", visible, "loading", loading)
    end
    for i = 1, 5 do check("frame " .. i) end
    LOAD_FRAMES = 0
    SlashCmdList.RUNEWAY("zoom 7.14285714286")   -- 0.2
    SlashCmdList.RUNEWAY("size 500")
    upd(RunewayFrame, 0.05)
    print("textures after zoom out:", #TEXTURES, TEXTURES[#TEXTURES])
    -- quest areas: let the background sampler run, then draw
    for _ = 1, 1200 do
        for _, f in ipairs(FRAMES) do
            local h = f:GetScript("OnUpdate")
            if h and f ~= RunewayFrame then h(f, 0.05) end
        end
    end
    upd(RunewayFrame, 0.05)
    print("lines created for quest areas:", CREATED.CreateLine or 0)
    local A, G = NS.QuestAreaState()
    local a = A[4242]
    local loop = a.loops[1]
    local emin, emax = 9, 0
    for m = 1, #loop, 2 do
        local e = ((loop[m] - 600) / 800) ^ 2 + ((loop[m + 1] + 400) / 1200) ^ 2
        emin, emax = math.min(emin, e), math.max(emax, e)
    end
    print(("quest area: %d loop(s), %d points, ellipse error %.3f .. %.3f (1 = exact)"):format(#a.loops, #loop / 2, emin, emax))
    local ng, gl = 0, 0
    for key, g in pairs(G) do ng = ng + 1; gl = #g.loops; print("group", key, "loops", gl) end
    print("groups:", ng)
    -- neighbouring zone: own quests sampled there, a quest cut off at its map border is drawn from the other map
    local _, _, S, O = NS.QuestAreaState()
    local nb = S[1421] and S[1421].areas or {}
    print(("neighbour map 1421: quest 5001 %d loop(s), quest 4243 cut %s, owners 4243 -> %s, 5001 -> %s"):format(
        nb[5001] and #nb[5001].loops or -1, tostring(nb[4243] and nb[4243].cut), tostring(O[4243]), tostring(O[5001])))
    print("pins textures:", (function() local n = 0 for _, t in ipairs(TEXTURES) do if t:find("Gossip") then n = n + 1 end end return n end)())
    SlashCmdList.RUNEWAY("layer questareas")
    SlashCmdList.RUNEWAY("color questareas 1 0.5 0")
    SlashCmdList.RUNEWAY("color fill 1 1 1 0.1")
    upd(RunewayFrame, 0.05)
    -- a map whose data pack is switched off: reported in the chat, the map is hidden (also against a toggle)
    -- and comes back on a map with data
    local function poll()
        for _, f in ipairs(FRAMES) do
            local h = f:GetScript("OnUpdate")
            if h and f ~= RunewayFrame then h(f, 0.25) end
        end
    end
    POS[4] = 1
    poll()
    print("map without data pack shown:", tostring(RunewayFrame:IsShown()))
    SlashCmdList.RUNEWAY("toggle")
    poll()
    print("after toggle shown:", tostring(RunewayFrame:IsShown()))
    -- the pack link in that note: a click shows its tooltip, a second click closes it
    EVENT_CALLBACKS.SetItemRef("addon:Runeway:pack:Runeway_Test", "[Test]", "LeftButton")
    print("pack link tooltip shown:", tostring(ItemRefTooltip:IsShown()))
    for _, line in ipairs(ItemRefTooltip.lines) do print("  " .. line) end
    EVENT_CALLBACKS.SetItemRef("addon:Runeway:pack:Runeway_Test", "[Test]", "LeftButton")
    print("second click shown:", tostring(ItemRefTooltip:IsShown()))
    EVENT_CALLBACKS.SetItemRef("item:6948", "[Hearthstone]", "LeftButton")   -- other links are not ours
    -- maps without any data pack: hidden, one chat note once the game's info belongs to the new place.
    -- The three kinds of loading screen (PLAYER_ENTERING_WORLD isInitialLogin / isReloadingUi) are played through;
    -- the notes are collected and compared at the end.
    local notes, print0 = {}, print
    print = function(msg, ...)
        if type(msg) == "string" and msg:find("Kalimdor") then   -- the area: the last name in brackets
            local last
            for n in msg:gmatch("%[([^%]]+)%]") do last = n end
            notes[#notes + 1] = last
        end
        return print0(msg, ...)
    end
    local function wait(s) for _ = 1, s * 100 do debugprofilestop() end poll() end
    UI_MAP0 = UI_MAP
    NS.WORLD_MAPS[1000] = true                                       -- map 1000 plays Kalimdor here
    -- 1. login in the Barrens: zone text empty, then the continent's name, then the zone
    fire("LOADING_SCREEN_ENABLED")
    POS[4], ZONE, CONTINENT, UI_MAP = 1000, "", "Kalimdor", 1413
    poll()
    fire("LOADING_SCREEN_DISABLED")
    fire("PLAYER_ENTERING_WORLD", true, false)
    wait(2)
    ZONE = "Kalimdor"
    wait(2)
    ZONE = "The Barrens"
    poll()
    print("map without any pack shown:", tostring(RunewayFrame:IsShown()))
    SlashCmdList.RUNEWAY("toggle")                                    -- asked for the map: the note at once
    poll()
    print("after toggle shown:", tostring(RunewayFrame:IsShown()))
    -- 2. reload there: the note again, at once after the loading screen
    NS.ResetNoData()
    fire("PLAYER_ENTERING_WORLD", false, true)
    wait(1)
    -- 3. into a dungeon of that continent (zone change): its own map; the last continent names the pack
    fire("LOADING_SCREEN_ENABLED")
    POS[4], ZONE, CONTINENT, STATE.instance, UI_MAP = 389, "Orgrimmar", nil, true, 9999
    wait(3)                                                           -- nothing during the loading screen
    fire("LOADING_SCREEN_DISABLED")
    fire("PLAYER_ENTERING_WORLD", false, false)
    wait(2)
    -- 4. out again: the position changes during the loading screen; afterwards the instance ID follows first,
    -- name and type still the dungeon's for a while
    fire("LOADING_SCREEN_ENABLED")
    POS[4] = 1000
    wait(3)
    fire("LOADING_SCREEN_DISABLED")
    fire("PLAYER_ENTERING_WORLD", false, false)
    poll()
    INFO_LAG, ZONE = true, ""                                        -- zone text empty, map still the dungeon's
    wait(2)
    ZONE = "Kalimdor"                                                 -- then the continent's name,
    wait(2)
    ZONE = "Ragefire Chasm"                                           -- then still the dungeon's name
    wait(2)
    INFO_LAG = nil
    STATE.instance, ZONE, CONTINENT, UI_MAP = false, "Orgrimmar", "Kalimdor", 1454
    poll()
    print = print0
    print(("no map data: login, toggle, reload, dungeon in and out name the right area %s (%s)"):format(
        table.concat(notes, ",") == "The Barrens,The Barrens,The Barrens,Ragefire Chasm,Orgrimmar" and "ok" or "FAIL",
        table.concat(notes, ",")))
    STATE.instance, UI_MAP = false, UI_MAP0
    POS[4], ZONE, CONTINENT = 0, nil, nil
    poll()
    print("back on map 0 shown:", tostring(RunewayFrame:IsShown()))
    upd(RunewayFrame, 0.05)
    -- Undercity: interior tile set on uiMap 1458, surface tiles in the Ruins of Lordaeron (same uiMap)
    local function newTextures(from)
        local uc, surface = 0, 0
        for i = from + 1, #TEXTURES do
            local t = TEXTURES[i] or ""
            if t:find("tiles" .. string.char(92) .. "0-1458", 1, true) then uc = uc + 1
            elseif t:find("tiles" .. string.char(92) .. "0" .. string.char(92), 1, true) then surface = surface + 1 end
        end
        return uc, surface
    end
    local function later() for _ = 1, 30 do debugprofilestop() end end   -- the tile set is checked every 0.2 s
    POS[1], POS[2], UI_MAP = 1561.6, 240.7, 1458
    later()
    local before = #TEXTURES
    upd(RunewayFrame, 0.05)
    print(("undercity: interior textures %d, surface textures %d"):format(newTextures(before)))
    print("undercity: quest maps " .. table.concat(NS.NearbyMaps(), ","))
    local inside = NS.InteriorChunks()
    print(("undercity: trade quarter inside %s, canals inside %s, Tirisfal east of the city inside %s"):format(
        tostring(NS.InChunks(inside, 1561.6, 240.7)), tostring(NS.InChunks(inside, 1456.7, 244.1)),
        tostring(NS.InChunks(inside, 1600, -150))))
    SUBZONE = "The Ruins of Lordaeron"          -- the client's subzone text may carry an article
    local function tiles(label)
        later()
        upd(RunewayFrame, 0.05)
        print(("%s: tile set %s, quest maps %s"):format(label, tostring(NS.TileSet()), table.concat(NS.NearbyMaps(), ",")))
    end
    POS[1], POS[2] = 1640, 240
    tiles("throne room")
    -- bottom of the south elevator: out of the shaft the subzone still reads Ruins for a moment
    POS[1], POS[2] = 1540, 241
    tiles("elevator shaft")
    POS[1], POS[2] = 1515, 241
    tiles("bottom of the elevator, subzone still Ruins")
    SUBZONE = "Trade Quarter"
    tiles("bottom of the elevator, subzone updated")
    SUBZONE = "The Ruins of Lordaeron"
    POS[1], POS[2] = 1640, 240
    tiles("throne room")
    POS[1], POS[2] = 1772.1, 239.2
    tiles("ruins courtyard")
    POS[1], POS[2] = 1690, 240
    tiles("rose walk")
    -- interiors keep their own zoom: /rnw zoom inside changes zoomInside only, the surface keeps its zoom
    local db = RunewayDB
    local z0, zi0 = db.zoom, db.zoomInside
    POS[1], POS[2] = 1561.6, 240.7
    SUBZONE = "Trade Quarter"
    later()
    SlashCmdList.RUNEWAY("zoom 100")
    local inside = db.zoomInside == 1.5 and db.zoom == z0
    POS[1], POS[2], SUBZONE = 1772.1, 239.2, "The Ruins of Lordaeron"
    later()
    SlashCmdList.RUNEWAY("zoom 0")
    local surface = db.zoom == 0.1 and db.zoomInside == 1.5
    db.zoom, db.zoomInside = z0, zi0
    print(("zoom: interior and surface separate %s"):format(inside and surface and "ok" or "FAIL"))
    POS[1], POS[2], UI_MAP, SUBZONE = 1917.6, 84.9, 1420, ""
    later()
    SlashCmdList.RUNEWAY("reset")
    POS[1] = nil
    upd(RunewayFrame, 0.05)
    SlashCmdList.RUNEWAY("help")
    SlashCmdList.RUNEWAY("probe 16")
    for _ = 1, 120 do
        for _, f in ipairs(FRAMES) do
            local h = f:GetScript("OnUpdate")
            if h and f ~= RunewayFrame then h(f, 0.25) end
        end
    end
    local p = RunewayDB.probe.quests[1]
    print("coarse rows:")
    for _, r in ipairs(p.coarse.rows) do print("  " .. r) end
    print("fine grid", p.fine.nx, p.fine.ny, "hits", p.fine.hits)
''')

# 3.4: window handling, visibility modes, auto-hide, key modes, options panel
L.execute('''
    local view, db = RunewayFrame, RunewayDB
    local poll = NS.view and nil
    local function tick() for _, f in ipairs(FRAMES) do local h = f:GetScript("OnUpdate") if h and f ~= view then h(f, 0.3) end end end
    local function check(label, ok) print(("%-44s %s"):format(label, ok and "ok" or "FAIL")) end
    -- toggle and auto-hide
    db.shown = false; tick()
    SlashCmdList.RUNEWAY("toggle"); tick()
    check("toggle shows", view:IsShown())
    db.autoHide.combat = true; STATE.combat = true; tick()
    check("auto-hide in combat", not view:IsShown())
    SlashCmdList.RUNEWAY("toggle"); tick()
    check("toggle overrides auto-hide", view:IsShown())
    STATE.combat = false; tick()
    check("after combat: shown (db.shown)", view:IsShown())
    db.autoHide.mounted = true; STATE.mounted = true; tick()
    check("auto-hide mounted", not view:IsShown())
    STATE.mounted = false; db.autoHide.combat = false; db.autoHide.mounted = false; tick()
    SlashCmdList.RUNEWAY("toggle"); tick()
    check("toggle hides", not view:IsShown())
    SlashCmdList.RUNEWAY("mode permanent"); tick()
    check("permanent shows", view:IsShown())
    -- key modes
    SlashCmdList.RUNEWAY("mode mapkey")
    check("mapkey: M -> overlay", BINDINGS.M == "RUNEWAY_TOGGLE")
    check("mapkey: SHIFT-M -> world map", BINDINGS["SHIFT-M"] == "TOGGLEWORLDMAP")
    wipe(BINDINGS); fire("UPDATE_BINDINGS")
    check("mapkey: re-applied on UPDATE_BINDINGS", BINDINGS.M == "RUNEWAY_TOGGLE")
    SlashCmdList.RUNEWAY("keys")
    SlashCmdList.RUNEWAY("mode key")
    check("key mode: M stays the world map", BINDINGS.M == nil)
    check("key mode: world map binding via TOGGLEWORLDMAP", BINDINGS["SHIFT-M"] == "TOGGLEWORLDMAP")
    -- mouse wheel works locked, shift+wheel size only unlocked
    SlashCmdList.RUNEWAY("lock")
    local z = db.zoom
    view:GetScript("OnMouseWheel")(view, 1)
    check("locked: wheel zooms", db.zoom > z)
    IsShiftKeyDown = function() return true end
    local w = db.w
    view:GetScript("OnMouseWheel")(view, 1)
    check("locked: shift+wheel keeps size", db.w == w)
    SlashCmdList.RUNEWAY("unlock")
    view:GetScript("OnMouseWheel")(view, 1)
    check("unlocked: shift+wheel sizes", db.w == w + 30)
    IsShiftKeyDown = function() return false end
    -- resize grip: left 150, top 750, cursor 700/300 -> 550 x 450
    local grip
    for _, f in ipairs(FRAMES) do if f:GetScript("OnMouseDown") then grip = f end end
    grip:GetScript("OnMouseDown")(grip)
    grip:GetScript("OnUpdate")(grip, 0.1)
    grip:GetScript("OnMouseUp")(grip)
    check("grip sizes width and height (550 x 450)", db.w == 550 and db.h == 450)
    CURSOR[1] = 5000
    grip:GetScript("OnMouseDown")(grip); grip:GetScript("OnUpdate")(grip, 0.1); grip:GetScript("OnMouseUp")(grip)
    check("grip clamps to 1400", db.w == 1400)
    -- options panel
    SlashCmdList.RUNEWAY("config")
    check("/rnw config opens category", OPENED == 77)
    local kinds = {}
    for _, i in ipairs(INITS) do kinds[i.kind] = (kinds[i.kind] or 0) + 1 end
    POS[1] = 1917.6                -- position back (cleared by the "no position" test above)
    STATE.dead = true
    view:GetScript("OnUpdate")(view, 0.05)
    local co = TEXTURE_OBJECTS[("Interface/Minimap/POIIcons"):gsub("/", string.char(92))]
    local corpseShown = co:IsShown()
    -- mouse-over on the corpse enlarges it (regression: hover state was read before its declaration)
    rawset(view, "IsMouseOver", function() return true end)
    local shownBefore = view:IsShown()
    view:Show()
    CURSOR[1], CURSOR[2] = 500 + co.x, 400 + co.y
    view:GetScript("OnUpdate")(view, 0.05)
    view:GetScript("OnUpdate")(view, 0.05)
    check("hover: corpse marker enlarged", math.abs(co._w - db.corpseSize * 1.3) < 0.01)
    rawset(view, "IsMouseOver", nil)
    if not shownBefore then view:Hide() end
    STATE.dead = false
    view:GetScript("OnUpdate")(view, 0.05)
    check("corpse marker while dead", corpseShown and not TEXTURE_OBJECTS[("Interface/Minimap/POIIcons"):gsub("/", string.char(92))]:IsShown())
    local za = NS.ZoneAlpha()
    check("zones: Tirisfal full, Silverpine dimmed", za[1] == 1 and math.abs(za[2] - db.zoneDim) < 0.02)
    -- zone numbers above 9 are letters in the chunk codes: stand in the first such chunk
    local DIGITS = "123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    local zkey, zi, zch
    for key, g in pairs(RunewayZones[0].chunks) do
        local i = g:find("%a")
        if i and (not zkey or key < zkey) then zkey, zi, zch = key, i, g:sub(i, i) end
    end
    local zc, zr = zkey:match("(%d+)_(%d+)")
    local fr = zr + (math.floor((zi - 1) / 16) + 0.5) / 16
    local fc = zc + ((zi - 1) % 16 + 0.5) / 16
    local oldN, oldW = POS[1], POS[2]
    POS[1], POS[2] = (32 - fr) * 1600 / 3, (32 - fc) * 1600 / 3
    for _ = 1, 400 do debugprofilestop(); view:GetScript("OnUpdate")(view, 0.05) end
    local zn = DIGITS:find(zch, 1, true)
    za = NS.ZoneAlpha()
    check("zones: zone " .. zn .. " (chunk code " .. zch .. ") active", zn > 9 and za[zn] == 1 and math.abs(za[1] - db.zoneDim) < 0.02)
    POS[1], POS[2] = oldN, oldW
    for _ = 1, 400 do debugprofilestop(); view:GetScript("OnUpdate")(view, 0.05) end
    -- view mode: centre on a mapped zone far from the player, drag pans, empty argument returns
    SlashCmdList.RUNEWAY("view westfall")
    for _ = 1, 400 do debugprofilestop(); view:GetScript("OnUpdate")(view, 0.05) end
    local vn, vw, vk = NS.Player()
    local wz
    for z, name in ipairs(RunewayZones[0].names) do if name == "Westfall" then wz = z end end
    za = NS.ZoneAlpha()
    check("view: centred on Westfall, Westfall active", vn < -8000 and za[wz] == 1 and math.abs(za[1] - db.zoneDim) < 0.02)
    CURSOR[1], CURSOR[2] = 500, 400
    view:GetScript("OnDragStart")(view)
    CURSOR[1], CURSOR[2] = 600, 400
    view:GetScript("OnUpdate")(view, 0.05)
    view:GetScript("OnDragStop")(view)
    local pn2, pw2 = NS.Player()
    check("view: dragging right pans west", math.abs(pw2 - (vw + 100 / vk)) < 0.01 and math.abs(pn2 - vn) < 0.01)
    SlashCmdList.RUNEWAY("view")
    view:GetScript("OnUpdate")(view, 0.05)
    check("view: back to the player", select(1, NS.Player()) == POS[1])
    SlashCmdList.RUNEWAY("view")
    CURSOR[1], CURSOR[2] = 500, 400
    view:GetScript("OnDragStart")(view)
    CURSOR[1], CURSOR[2] = 500, 500
    view:GetScript("OnUpdate")(view, 0.05)
    view:GetScript("OnDragStop")(view)
    check("view: without a value starts at the player, drag up pans south", select(1, NS.Player()) < POS[1] - 1)
    SlashCmdList.RUNEWAY("view")
    view:GetScript("OnUpdate")(view, 0.05)
    check("view: second /rnw view returns", select(1, NS.Player()) == POS[1])
    for _ = 1, 400 do debugprofilestop(); view:GetScript("OnUpdate")(view, 0.05) end
    local tg = NS.ToggleButton
    EVENT_CALLBACKS["Settings.CategoryChanged"]({ GetID = function() return 1 end })
    local hiddenElsewhere = not tg:IsShown()
    EVENT_CALLBACKS["Settings.CategoryChanged"](SETTINGS_MAIN)
    check("show/hide button only on Runeway pages", hiddenElsewhere and tg:IsShown())
    check("main page: version, intro, 15 quick commands (+ profile text)", kinds.element == 18 and INITS[1].data.text:find(TOC_VERSION, 1, true) and INITS[2].data.text == NS.L.INTRO and INITS[4].data.desc ~= nil)
    check("settings rows: 1 header, 2 bindings, 7 layers",
        kinds.header == 1 and kinds.binding == 2 and kinds.layerrow == 7)
    local dropdown
    for _, i in ipairs(INITS) do if i.kind == "dropdown" then dropdown = i end end
    check("mode dropdown has 3 entries", dropdown and #dropdown.options == 3)
    -- values changed outside the panel are pushed to the settings rows
    local notified = {}
    Settings.NotifyUpdate = function(v) notified[v] = true end
    view:GetScript("OnMouseWheel")(view, 1)
    SlashCmdList.RUNEWAY("size 900 500")
    check("live update: zoom and size notified", notified.RUNEWAY_ZOOM and notified.RUNEWAY_W and notified.RUNEWAY_H
        and db.w == 900 and db.h == 500)
    -- mouse-over: arrow in the centre is enlarged; inside a quest area the tooltip lists its quest(s)
    local tipLines = {}
    GameTooltip.AddLine = function(_, text, r, g, b)
        tipLines[#tipLines + 1] = text
        if #tipLines == 1 then GameTooltipTextLeft1:SetTextColor(r or 1, g or 1, b or 1) end
    end
    GameTooltip.IsOwned = function() return true end
    rawset(view, "IsMouseOver", function() return true end)
    local wasShown = view:IsShown()
    view:Show()
    CURSOR[1], CURSOR[2] = 500, 400                    -- view centre (stub GetCenter)
    view:GetScript("OnUpdate")(view, 0.05)
    view:GetScript("OnUpdate")(view, 0.05)
    local arrowTex = TEXTURE_OBJECTS[("Interface/AddOns/Runeway/media/arrow.tga"):gsub("/", string.char(92))]
    check("hover: player arrow enlarged", arrowTex and math.abs(arrowTex._w - db.arrowSize * 1.3) < 0.01)
    local A = NS.QuestAreaState()
    local qa
    for qid, a in pairs(A) do if #a.loops > 0 then qa = a break end end
    local hits = qa and NS.QuestAreasAt((qa.box[1] + qa.box[2]) / 2, (qa.box[3] + qa.box[4]) / 2) or {}
    check("hover: quest area hit test finds its quest", #hits > 0)
    check("hover: point far outside finds nothing", #NS.QuestAreasAt(qa.box[2] + 500, qa.box[4] + 500) == 0)
    -- combined outline (4242 + 4243 overlap): the tooltip lists both quests wherever the outline is hovered
    local one, both = false, false
    local b = A[4242].box
    for i = 0, 20 do
        for j = 0, 20 do
            local h = NS.QuestAreasAt(b[1] + (b[2] - b[1]) * i / 20, b[3] + (b[4] - b[3]) * j / 20)
            if #h == 1 then one = true elseif #h == 2 then both = true end
        end
    end
    check("hover: merged areas list all their quests", db.questMerge and both and not one)
    local pn, pw = POS[1], POS[2]
    POS[1], POS[2] = (b[1] + b[2]) / 2, (b[3] + b[4]) / 2   -- player in the area, cursor just beside the arrow
    CURSOR[1], CURSOR[2] = 520, 400
    wipe(tipLines)
    view:GetScript("OnUpdate")(view, 0.05)
    local spans, filled = 0, 0
    for _, t in ipairs(ALL_TEX) do
        local c = rawget(t, "_color")
        if rawget(t, "_shown") and c and math.abs((c[4] or 1) - 0.15) < 1e-6 then
            spans = spans + 1
            filled = filled + rawget(t, "_w") * rawget(t, "_h")
        end
    end
    local area, l = 0, A[4242].loops[1]            -- the combined outline is at least as large as 4242's
    for m = 1, #l, 2 do
        local j = (m + 1) % #l + 1
        local x0, y0 = NS.ToScreen(l[m], l[m + 1])
        local x1, y1 = NS.ToScreen(l[j], l[j + 1])
        area = area + (x0 * y1 - x1 * y0) / 2
    end
    check(("hover: the hovered area is filled (%d spans, %.0f%% of 4242)"):format(spans, filled / math.abs(area) * 100),
        spans > 10 and filled >= math.abs(area) * 0.95)
    POS[1], POS[2], CURSOR[1], CURSOR[2] = pn, pw, 500, 400
    view:GetScript("OnUpdate")(view, 0.05)
    local left = 0
    for _, t in ipairs(ALL_TEX) do
        local c = rawget(t, "_color")
        if rawget(t, "_shown") and c and math.abs((c[4] or 1) - 0.15) < 1e-6 then left = left + 1 end
    end
    check("hover: fill hidden when the cursor leaves", left == 0)
    local col = GameTooltipTextLeft1._color
    check("hover: tooltip title in the normal font and quest title color", GameTooltipTextLeft1._font == GameTooltipText
        and col[1] == 1 and col[2] == 0.82 and col[3] == 0)
    -- a combined outline with two separate parts: each part lists only the quests inside it
    local grp
    for _, e in ipairs(NS.QuestAreasRepublish()) do if #e[2] == 2 then grp = e end end
    local g, st = grp[1], grp[3]
    local d = (b[2] - b[1]) * 3                        -- a far copy of 4242's outline as quest 9999
    local far = {}
    for _, l in ipairs(A[4242].loops) do
        local fl = {}
        for m = 1, #l, 2 do fl[m], fl[m + 1] = l[m] + d, l[m + 1] end
        far[#far + 1] = fl
    end
    local box0, members0 = { unpack(g.box) }, g.members
    st.areas[9999] = { loops = far, box = { b[1] + d, b[2] + d, b[3], b[4] } }
    for _, fl in ipairs(far) do g.loops[#g.loops + 1] = fl end
    g.members, grp[2] = { 4242, 4243, 9999 }, { 4242, 4243, 9999 }
    g.box[2] = b[2] + d
    local near, apart = {}, {}
    for i = 0, 20 do
        for j = 0, 20 do
            local x, y = b[1] + (b[2] - b[1]) * i / 20, b[3] + (b[4] - b[3]) * j / 20
            for _, q in ipairs(NS.QuestAreasAt(x, y)) do near[q] = true end
            for _, q in ipairs(NS.QuestAreasAt(x + d, y)) do apart[q] = true end
        end
    end
    for _ = 1, #far do table.remove(g.loops) end
    st.areas[9999], g.members, grp[2], g.box = nil, members0, members0, box0
    check("hover: combined outline lists only the quests of the hovered part",
        near[4242] and near[4243] and not near[9999] and apart[9999] and not apart[4242] and not apart[4243])
    -- a neighbouring map lists a quest of the combined outline (4243 on 1421): if its outline there is the
    -- better one (not cut), the combined outline still takes it, and every quest is drawn once
    -- zoomed out: the neighbouring map 1421 is in reach again
    local zoom0 = db.zoom
    db.zoom = 0.2
    for _ = 1, 400 do
        for _, f in ipairs(FRAMES) do
            local h = f:GetScript("OnUpdate")
            if h and f ~= RunewayFrame then h(f, 0.05) end
        end
    end
    check("merge: neighbouring map in reach", table.concat(NS.NearbyMaps(), ",") == "1420,1421")
    local both = false
    for _, e in ipairs(NS.QuestAreasRepublish()) do
        if table.concat(e[2], ",") == "4242,4243" then both = true end
    end
    check("merge: zoomed out the overlapping quests are combined", both)
    local _, _, S = NS.QuestAreaState()
    local function once()
        local count, ok = {}, true
        for _, e in ipairs(NS.QuestAreasRepublish()) do
            for _, qid in ipairs(e[2]) do count[qid] = (count[qid] or 0) + 1 end
        end
        for _, c in pairs(count) do ok = ok and c == 1 end
        return ok, count[4242], count[4243]
    end
    local a1420, a1421 = S[1420].areas[4243], S[1421].areas[4243]
    local cut1420, cut1421 = a1420.cut, a1421.cut
    a1420.cut, a1421.cut = true, false
    local ok = once()
    check("merge: every quest drawn once with a neighbouring map", ok)
    -- zoomed out: the neighbouring map lists only part of an overlapping set (4243, whole there, and 5001), the
    -- player's map 4242, 4243 (cut there) and 9001: the set goes to the map that lists most of it
    local O = select(4, NS.QuestAreaState())
    local function copy(a, dn)
        local loops = {}
        for _, l in ipairs(a.loops) do
            local c = {}
            for m = 1, #l, 2 do c[m], c[m + 1] = l[m] + dn, l[m + 1] end
            loops[#loops + 1] = c
        end
        local bx = a.box
        return { loops = loops, box = { bx[1] + dn, bx[2] + dn, bx[3], bx[4] }, rect = a.rect, sig = "x", cut = false }
    end
    local d9 = (a1420.box[2] - a1420.box[1]) / 2
    S[1420].areas[9001] = copy(a1420, d9)
    a1420.cut, a1421.cut = true, false
    NS.QuestAreasRepublish()
    local same = O[4242] == 1420 and O[4243] == 1420 and O[9001] == 1420
    S[1420].areas[9001] = nil
    check("merge: a neighbouring map with part of a set does not split it", same)
    db.zoom = zoom0
    -- flight masters: own faction and neutral, discovered and undiscovered with their own icons; tooltip.
    -- isUndiscovered is always false in the client: known nodes come from the taxi map of a flight master
    NS.RefreshQuests()
    local allUnknown = true
    for _, t in ipairs(NS.Taxis) do allUnknown = allUnknown and t.undiscovered end
    check("flight masters: unknown before a flight master was visited", allUnknown)
    RunewayDB.taxiKnown = { ["Tester-Realm"] = { ["Tarren Mill"] = true } }   -- learned by the old rule
    fire("TAXIMAP_OPENED")
    local kn = RunewayDB.taxiKnown["Tester-Realm"]
    local tn1 = "Turm der Kronenwache, östliche Pestländer"
    check("flight masters: German zone names capitalised", NS.TaxiName(tn1) == (GetLocale() == "deDE"
        and "Turm der Kronenwache, Östliche Pestländer" or tn1) and NS.TaxiName("Brill, tirisfal") == (GetLocale() == "deDE"
        and "Brill, Tirisfal" or "Brill, tirisfal"))
    check("flight masters: only offered nodes count as discovered", kn.Brill and kn.Undercity and not kn["Tarren Mill"]
        and not kn.Bulwark)
    view:GetScript("OnUpdate")(view, 0.05)
    local atl = {}
    for _, t in ipairs(ALL_TEX) do
        local a = rawget(t, "_atlas")
        if a and (a:find("TaxiNode") or a:find("Taxi_Frame")) and rawget(t, "_shown") then atl[#atl + 1] = a end
    end
    table.sort(atl)
    local names = {}
    for _, t in ipairs(NS.Taxis) do names[#names + 1] = t.name end
    table.sort(names)
    check("flight masters: surface also lists the interior's", table.concat(names, ",") == "Brill,Bulwark,Undercity")
    local green = false
    for _, p in ipairs(NS.TaxiPins) do
        if p.shown and p.taxi.undiscovered then green = (rawget(p.icon, "_tex") or ""):find("Green") ~= nil end
    end
    check("flight masters: own faction shown, discovered with the grey node", table.concat(atl, ",") == "Taxi_Frame_Gray,Taxi_Frame_Gray")
    check("flight masters: missing undiscovered atlas falls back to the green icon", green)
    check("flight masters: /rnw taxi lists them", pcall(SlashCmdList.RUNEWAY, "taxi"))
    check("flight masters: /rnw taxi icons shows the candidates", pcall(SlashCmdList.RUNEWAY, "taxi icons"))
    check("quests: /rnw quest icons shows the turn-in candidates", pcall(SlashCmdList.RUNEWAY, "quest icons"))
    local tip = {}
    local tn, tw = NS.MapToWorld(1420, 0.4, 0.603)
    local pn, pw = POS[1], POS[2]
    POS[1], POS[2] = tn + 80, tw               -- the undiscovered node 80 yd away from the player
    view:GetScript("OnUpdate")(view, 0.05)
    for _, p in ipairs(NS.TaxiPins) do
        if p.shown and p.taxi.undiscovered then
            wipe(tipLines)
            CURSOR[1], CURSOR[2] = 500 + p.x, 400 + p.y
            view:GetScript("OnUpdate")(view, 0.05)
            tip = tipLines
        end
    end
    POS[1], POS[2] = pn, pw
    check("flight masters: tooltip names an undiscovered node", tip[1] == "Bulwark" and tip[2] == "Undiscovered Horde flight point")
    CURSOR[1], CURSOR[2] = 500, 400
    a1420.cut, a1421.cut = cut1420, cut1421
    NS.QuestAreasRepublish()
    -- objective progress in combat: the member is queued for sampling, which waits for the end of combat; the
    -- combined outline must stay (it split into single outlines when the publish timeout hit in combat)
    local function sampler(n)
        for _ = 1, n do
            for _, f in ipairs(FRAMES) do
                local h = f:GetScript("OnUpdate")
                if h and f ~= RunewayFrame then h(f, 0.05) end
            end
        end
    end
    local function merged()
        local together, alone = false, false
        for _, e in ipairs(NS.QuestAreasRepublish()) do
            local ids = table.concat(e[2], ",")
            if ids == "4242,4243" then together = true elseif ids == "4242" or ids == "4243" then alone = true end
        end
        return together and not alone
    end
    sampler(400)
    check("combat: overlapping quests combined before", merged())
    local progress = 1
    C_QuestLog.GetQuestObjectives = function(q) return q == 4243 and { { numFulfilled = progress } } or {} end
    local lockdown = InCombatLockdown
    InCombatLockdown = function() return true end
    fire("QUEST_LOG_UPDATE")
    sampler(100)
    check("combat: objective progress keeps the combined outline", merged())
    InCombatLockdown = lockdown
    sampler(600)
    local A, G = NS.QuestAreaState()
    local ng = 0
    for _ in pairs(G) do ng = ng + 1 end
    check("combat: sampled after combat, new outline replaces the old", merged() and ng == 1
        and A[4243].sig:find(":1$") ~= nil)
    -- death: nothing is sampled while dead; afterwards the blob is not drawn for a while (empty samples): the
    -- quest keeps its outline and is sampled again until the blob is back
    STATE.dead = true
    progress = 2
    fire("QUEST_LOG_UPDATE")
    sampler(400)
    check("death: no sampling while dead, outline kept", #A[4243].loops > 0 and A[4243].sig:find(":1$") ~= nil)
    -- as a ghost the client may report no blobs: the known areas stay (all areas vanished in the game test)
    local blobCount = GetQuestPOIBlobCount
    GetQuestPOIBlobCount = function() return 0 end
    fire("QUEST_LOG_UPDATE")
    sampler(100)
    check("death: no blobs reported while dead, areas kept", A[4242] and A[4243] and merged()
        and NS.HasQuestArea(4242) and NS.HasQuestArea(4243))
    GetQuestPOIBlobCount = blobCount
    local blob = BLOBS[4243]
    BLOBS[4243] = nil
    STATE.dead = false
    fire("PLAYER_UNGHOST")
    sampler(60)
    local kept = #A[4243].loops > 0 and NS.HasQuestArea(4243)
    BLOBS[4243] = blob
    sampler(1200)
    check("death: an empty sample keeps the outline", kept)
    check("death: sampled again once the blob is drawn", #A[4243].loops > 0 and A[4243].sig:find(":2$") ~= nil
        and merged())
    -- an empty area already in the saved cache (0.6) is sampled again
    A[4242].loops = {}
    fire("QUEST_LOG_UPDATE")
    sampler(1200)
    check("cache: empty area of a quest with blobs sampled again", #A[4242].loops > 0 and merged())
    -- a quest of a combined outline is completed: the others stay combined (they split in the game test). In the
    -- client a completed quest either reports no blobs any more or its blob is no longer drawn.
    local function split()
        for _, e in ipairs(NS.QuestAreasRepublish()) do
            local ids = table.concat(e[2], ",")
            if ids == "4242" or ids == "4243" then return true end
        end
    end
    local function combined(ids)
        for _, e in ipairs(NS.QuestAreasRepublish()) do if table.concat(e[2], ",") == ids then return true end end
    end
    local isComplete, objectives = C_QuestLog.IsComplete, C_QuestLog.GetQuestObjectives
    local done45 = false
    C_QuestLog.IsComplete = function(q) return q == 4244 or (q == 4245 and done45) end
    C_QuestLog.GetQuestObjectives = function(q)
        if q == 4245 then return { { numFulfilled = done45 and 1 or 0, finished = done45 } } end
        return objectives(q)
    end
    local list1420 = QUESTS_BY_MAP[1420]
    list1420[#list1420 + 1] = { questID = 4245, x = 0.47, y = 0.6 }
    local function addQuest()
        done45 = false
        BLOBS[4245] = { 0.47, 0.6, 0.12 }
        fire("QUEST_LOG_UPDATE")
        sampler(1500)
        return combined("4242,4243,4245")
    end
    check("complete: three overlapping quests combined", addQuest())
    -- the completed quest reports no blobs (in combat, so nothing is sampled meanwhile)
    InCombatLockdown = function() return true end
    done45, BLOBS[4245] = true, nil
    fire("QUEST_LOG_UPDATE")
    sampler(100)
    local apart = split()
    InCombatLockdown = lockdown
    for _ = 1, 30 do sampler(20); apart = apart or split() end
    check("complete: no blobs, the others stay combined", not apart and combined("4242,4243")
        and not NS.HasQuestArea(4245))
    -- the completed quest still reports blobs, but its blob is not drawn any more
    addQuest()
    done45, BLOBS[4245] = true, nil
    local blobCount = GetQuestPOIBlobCount
    GetQuestPOIBlobCount = function(q) return q == 4245 and 1 or blobCount(q) end
    fire("QUEST_LOG_UPDATE")
    apart = false
    for _ = 1, 60 do sampler(20); apart = apart or split() end
    check("complete: blob not drawn, the others stay combined at once", not apart and combined("4242,4243")
        and not NS.HasQuestArea(4245))
    GetQuestPOIBlobCount = blobCount
    -- random sequence (progress, completion, quest back in the log, combat, death, zoom with the neighbouring map):
    -- a quest drawn in a combined outline is never drawn alone while it is still in a set with others
    math.randomseed(7)
    local prog = { [4242] = 0, [4243] = 0, [4245] = 0 }
    C_QuestLog.GetQuestObjectives = function(q)
        if q == 4245 then return { { numFulfilled = prog[q], finished = done45 } } end
        return prog[q] and { { numFulfilled = prog[q] } } or {}
    end
    addQuest()
    local combat = function() return true end
    local was, broken, events = {}, nil, { 0, 0, 0, 0, 0, 0 }
    for step = 1, 300 do
        local r = math.random(6)
        events[r] = events[r] + 1
        if r == 1 then
            local q = ({ 4242, 4243, 4245 })[math.random(3)]
            prog[q] = prog[q] + 1
        elseif r == 2 then
            done45, BLOBS[4245] = true, nil                       -- completed: no blobs any more
        elseif r == 3 then
            done45, BLOBS[4245] = false, { 0.47, 0.6, 0.12 }     -- (again) in progress
        elseif r == 4 then
            InCombatLockdown = InCombatLockdown == lockdown and combat or lockdown
        elseif r == 5 then
            STATE.dead = not STATE.dead
            if not STATE.dead then fire("PLAYER_UNGHOST") end
        else
            db.zoom = db.zoom == zoom0 and 0.2 or zoom0
        end
        fire("QUEST_LOG_UPDATE")
        sampler(math.random(60))
        local sh, wt = NS.QuestAreasRepublish()
        local inSet, now = {}, {}
        for _, g in ipairs(wt) do for _, q in ipairs(g.members) do inSet[q] = true end end
        for _, e in ipairs(sh) do
            if #e[2] == 1 and was[e[2][1]] and inSet[e[2][1]] then
                broken = broken or ("step " .. step .. ", quest " .. e[2][1])
            end
            for _, q in ipairs(e[2]) do now[q] = #e[2] > 1 end
        end
        was = now
    end
    InCombatLockdown, STATE.dead, db.zoom = lockdown, false, zoom0
    fire("PLAYER_UNGHOST")
    check(("random: combined outlines never split (%s events)"):format(table.concat(events, "/"))
        .. (broken and (" - " .. broken) or ""), not broken)
    table.remove(list1420)
    C_QuestLog.IsComplete = isComplete
    C_QuestLog.GetQuestObjectives = nil
    fire("QUEST_LOG_UPDATE")
    sampler(1200)
    NS.QuestAreasAt(nil)
    rawset(view, "IsMouseOver", nil)
    if not wasShown then view:Hide() end
    -- display page: marker rows (show + size) in order; quest edge and merge follow the quest marker switch
    local L = NS.L
    local order, quest, edge, merge = {}, nil, nil, nil
    for _, i in ipairs(INITS) do
        if i.kind == "checkslider" then
            order[#order + 1] = i.data.cbLabel
            if i.data.cbLabel == L.QUEST_MARKS then quest = i end
        end
        if i.setting == SETTINGS.RUNEWAY_QUESTEDGE then edge = i end
        if i.setting == SETTINGS.RUNEWAY_QUESTMERGE then merge = i end
    end
    check("option: marker rows in order", table.concat(order, ",") == table.concat({ L.PLAYER_ARROW, L.CORPSE_MARKER,
        L.FLIGHT_MASTERS, L.QUEST_MARKS }, ","))
    SETTINGS.RUNEWAY_SHOWQUESTS:SetValue(false)
    local off = edge.parent == quest and merge.parent == quest and not edge.enabled() and not merge.enabled()
    view:GetScript("OnUpdate")(view, 0.05)
    local pinsShown = 0
    for _, p in ipairs(NS.QuestPins or {}) do if p.shown then pinsShown = pinsShown + 1 end end
    local A2 = NS.QuestAreaState()
    local qa2
    for _, a in pairs(A2) do if #a.loops > 0 then qa2 = a end end
    local hits = #NS.QuestAreasAt((qa2.box[1] + qa2.box[2]) / 2, (qa2.box[3] + qa2.box[4]) / 2)
    SETTINGS.RUNEWAY_SHOWQUESTS:SetValue(true)
    NS.QuestAreasAt(nil)
    check("option: quest marks off hides pins and areas, greys out edge and merge",
        off and edge.enabled() and pinsShown == 0 and hits == 0)
    view:GetScript("OnUpdate")(view, 0.05)
    local campaign = false
    for _, p in ipairs(NS.QuestPins) do
        if p.shown then
            local a = rawget(p.icon, "_atlas") or ""
            campaign = a:find("^quest%-campaign%-") ~= nil and not rawget(p.back, "_shown")
        end
    end
    check("quest pins: turn-in with the campaign icon, without the badge", campaign)
    SETTINGS.RUNEWAY_QUESTCLASSIC:SetValue(true)
    view:GetScript("OnUpdate")(view, 0.05)
    local classic = false
    for _, p in ipairs(NS.QuestPins) do
        if p.shown then
            local a = rawget(p.icon, "_atlas") or ""
            classic = a:find("^quest%-campaign%-") == nil and rawget(p.back, "_shown") == true
        end
    end
    SETTINGS.RUNEWAY_QUESTCLASSIC:SetValue(false)
    local child
    for _, i in ipairs(INITS) do if i.setting == SETTINGS.RUNEWAY_QUESTCLASSIC then child = i end end
    check("quest pins: classic icons on the badge (option, follows quest marks)", classic and child.parent ~= nil)
    SETTINGS.RUNEWAY_SHOWARROW:SetValue(false)
    view:GetScript("OnUpdate")(view, 0.05)
    local arrowTex2 = TEXTURE_OBJECTS[("Interface/AddOns/Runeway/media/arrow.tga"):gsub("/", string.char(92))]
    local hidden = not rawget(arrowTex2, "_shown")
    SETTINGS.RUNEWAY_SHOWARROW:SetValue(true)
    view:GetScript("OnUpdate")(view, 0.05)
    check("option: player arrow can be switched off", hidden and rawget(arrowTex2, "_shown"))
    -- unlocked map: frame while the mouse is over it (no option)
    local function frameLines()
        local n = 0
        for _, l in ipairs(ALL_LINES) do
            local c = rawget(l, "_color")
            if rawget(l, "_shown") and c and c[4] == 0.55 then n = n + 1 end
        end
        return n
    end
    local locked0 = db.locked
    db.locked = false
    rawset(view, "IsMouseOver", function() return true end)
    view:GetScript("OnEnter")(view)
    local over = frameLines()
    rawset(view, "IsMouseOver", function() return false end)
    view:GetScript("OnLeave")(view)
    local out = frameLines()
    rawset(view, "IsMouseOver", nil)
    db.locked = locked0
    check("unlocked: rounded frame while the mouse is over the map", over == 36 and out == 0)
    -- option: mouse wheel zoom off -> the map does not take the wheel
    SETTINGS.RUNEWAY_WHEELZOOM:SetValue(false)
    local wheelOff = rawget(view, "_wheel") == false
    SETTINGS.RUNEWAY_WHEELZOOM:SetValue(true)
    check("option: wheel zoom off releases the mouse wheel", wheelOff and rawget(view, "_wheel") == true)
    -- profile: export, change settings, import the export again -> same settings as before
    local text = NS.ExportProfile()
    check("profile: export text", text:sub(1, 5) == "RNW1;" and text:find("colors.fill.a=", 1, true) ~= nil)
    local zoom, roads, hatch, mode = db.zoom, db.colors.roads.r, db.layers.hatch, db.mode
    db.zoom, db.colors.roads.r, db.layers.hatch, db.mode = 2, 0.5, not hatch, "permanent"
    local n = NS.ImportProfile(text)
    check("profile: import restores the settings", n and n > 40 and db.zoom == zoom
        and math.abs(db.colors.roads.r - roads) < 0.001 and db.layers.hatch == hatch and db.mode == mode)
    check("profile: rejects other text", NS.ImportProfile("hello") == nil)
    check("profile: ignores unknown keys and bad values", NS.ImportProfile("RNW1;mode=os.exit;zoom=abc;evil.key=1") == nil
        and db.mode == mode and db.zoom == zoom)
    NS.ShowExport()
    check("profile: export dialog shows the text", RunewayProfileDialog.edit:GetText() == text)
    NS.ShowImport()
    RunewayProfileDialog.edit:SetText(text)
    RunewayProfileDialog.action:GetScript("OnClick")()
    check("profile: import dialog applies the text", not RunewayProfileDialog:IsShown())
    -- layer row: the colour swatch opens the picker and writes the layer colour
    local row
    for _, i in ipairs(INITS) do if i.kind == "layerrow" and i.data.name == NS.L.LAYER_ROADS then row = i end end
    local f = setmetatable({ ColorSwatch = CreateFrame("Button"), Text = CreateFrame("Frame"), Tooltip = CreateFrame("Frame"),
                             cbrHandles = { SetOnValueChangedCallback = function() end } },
        { __index = RunewayLayerRowMixin })
    f.ColorSwatch.SetColor = function() end
    RunewayLayerRowMixin.Init(f, row)
    f.ColorSwatch:GetScript("OnClick")()
    ColorPickerFrame.info.swatchFunc()
    check("layer row: swatch sets the roads colour", math.abs(db.colors.roads.r - 0.1) < 0.01 and math.abs(db.colors.roads.b - 0.3) < 0.01)
    for var, st in pairs(SETTINGS) do
        if st:GetValue() == nil then check("setting reads a value: " .. var, false) end
    end
    -- map shape and soft edge: mask per 10 % step; the shape function matches; 100 % shrinks the oval to a circle
    local function mask() return TEXTURES[#TEXTURES] end
    SETTINGS.RUNEWAY_EDGESOFT:SetValue(1)
    local m1 = mask()
    SETTINGS.RUNEWAY_EDGESOFT:SetValue(0)
    SETTINGS.RUNEWAY_SHAPE:SetValue(0)
    local m2 = mask()
    local W, H = view:GetSize()
    local rectIn = NS.ShapeFn()(W / 2 * 0.9, H / 2 * 0.9)
    SETTINGS.RUNEWAY_SHAPE:SetValue(0.5)
    local ovalOut = NS.ShapeFn()(W / 2 * 0.9, H / 2 * 0.9)
    SETTINGS.RUNEWAY_SHAPE:SetValue(1)
    local fadeTex = TEXTURE_OBJECTS[mask()]
    local m = math.min(W, H)
    local circle = rawget(fadeTex, "_w") == m and rawget(fadeTex, "_h") == m and NS.ShapeFn()(m / 2 * 0.99, 0) == 1
        and NS.ShapeFn()(m / 2 * 1.01, 0) == 0
    SETTINGS.RUNEWAY_SHAPE:SetValue(0.5)
    SETTINGS.RUNEWAY_EDGESOFT:SetValue(0.5)
    check("shape and soft edge: masks, rectangle, oval, circle", m1:find("mask.s5f10%.tga$") and m2:find("mask.s0f0%.tga$")
        and rectIn == 1 and ovalOut == 0 and circle and mask():find("mask.s5f5%.tga$"))
    SETTINGS.RUNEWAY_COLOR_FILL:SetValue("ff1a334d")
    check("colour swatch sets fill", math.abs(db.colors.fill.r - 0.1) < 0.01 and math.abs(db.colors.fill.b - 0.3) < 0.01)
    check("colour swatch reads hex", SETTINGS.RUNEWAY_COLOR_FILL:GetValue() == "ff1a334d")
    SETTINGS.RUNEWAY_OPACITY_ROADS:SetValue(0.5)
    SETTINGS.RUNEWAY_AUTOHIDE_COMBAT:SetValue(true)
    check("opacity and auto-hide write the db", db.colors.roads.a == 0.5 and db.autoHide.combat == true)
    for _, st in pairs(SETTINGS) do st:SetValue(st.default) end
    check("defaults restored", db.edgeSoft == 0.5 and db.shape == 0.5 and db.w == 800 and db.h == 600 and db.mode == "key" and db.colors.roads.a == 0.65
        and math.abs(db.colors.fill.r) < 0.01 and db.zoom == 0.66 and db.questMerge == true and db.corpseSize == 20 and db.alpha == 0.5 and db.zoneDim == 0.5)
    view:GetScript("OnUpdate")(view, 0.05)
''')

# optional WoW APIs the stub leaves out on purpose, the SavedVariables table before the first login and the
# tile tables the first map data file creates
known = {'GetMouseFoci', 'GetMouseFocus', 'RunewayDB', 'CORPSE_RED', 'RunewayTiles', 'RunewayZones'}
undefined = {k: v for k, v in L.eval('UNDEFINED_GLOBALS').items() if k not in known}
print('undefined globals read:', (str(undefined) + '  FAIL') if undefined else 'none')
# every referenced texture file must exist
missing = [p for p in L.globals().TEXTURES.values() if p.startswith('Interface\\AddOns\\Runeway')
           and not os.path.exists(os.path.join(ROOT, p.replace('Interface\\AddOns\\', '').replace('\\', os.sep)))]
print('missing texture files:', missing or 'none')
