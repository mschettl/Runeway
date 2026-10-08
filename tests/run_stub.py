# Loads the addon with a WoW API stub, fires the login events, renders frames and runs slash commands.
#   python tests/run_stub.py
import os
import glob
import lupa
from lupa import lua51       # WoW runs Lua 5.1

ROOT = os.path.join(os.path.dirname(__file__), '..')
L = lua51.LuaRuntime(unpack_returned_tuples=True)
L.execute(open(os.path.join(ROOT, 'tests', 'wow_stub.lua')).read())
LOCALES = ['Runeway/Locales/enUS.lua'] + sorted(f'Runeway/Locales/{os.path.basename(p)}' for p in glob.glob(os.path.join(ROOT, 'Runeway', 'Locales', '*.lua')) if not p.endswith('enUS.lua'))
L.execute('LOCALE = ...', os.environ.get('RUNEWAY_LOCALE', 'enUS'))   # client language for this run
for f in (*LOCALES, 'Runeway/Tiles.lua', 'Runeway/Core.lua', 'Runeway/QuestAreas.lua', 'Runeway/Profile.lua', 'Runeway/Options.lua', 'tools/Probe.lua'):
    src = open(os.path.join(ROOT, f), encoding='utf8').read()
    L.execute('NS = NS or {}; local f = assert(loadstring(..., "@' + f + '")); f("Runeway", NS)', src)

L.execute('''
    function fire(event, arg)
        for _, f in ipairs(FRAMES) do
            local h = f:GetScript("OnEvent")
            if h then h(f, event, arg) end
        end
    end
    fire("ADDON_LOADED", "Runeway")
    fire("PLAYER_LOGIN")
    fire("PLAYER_ENTERING_WORLD")
    SlashCmdList.RUNEWAY("toggle")
    local upd = RunewayFrame:GetScript("OnUpdate")
    upd(RunewayFrame, 0.05)
    print("textures after first frame:", #TEXTURES)
    for i = 1, math.min(4, #TEXTURES) do print("  " .. TEXTURES[i]) end
    SlashCmdList.RUNEWAY("layer roads")
    SlashCmdList.RUNEWAY("color water 0.2 0.4 1")
    -- zoom level change with slow texture loading: every visible tile layer must keep a shown texture
    LOAD_FRAMES = 3
    SlashCmdList.RUNEWAY("zoom 0.5")
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
    SlashCmdList.RUNEWAY("zoom 0.2")
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
    STATE.dead = false
    view:GetScript("OnUpdate")(view, 0.05)
    check("corpse marker while dead", corpseShown and not TEXTURE_OBJECTS[("Interface/Minimap/POIIcons"):gsub("/", string.char(92))]:IsShown())
    local za = NS.ZoneAlpha()
    check("zones: Tirisfal full, Silverpine dimmed", za[1] == 1 and math.abs(za[2] - db.zoneDim) < 0.02)
    local tg = NS.ToggleButton
    EVENT_CALLBACKS["Settings.CategoryChanged"]({ GetID = function() return 1 end })
    local hiddenElsewhere = not tg:IsShown()
    EVENT_CALLBACKS["Settings.CategoryChanged"](SETTINGS_MAIN)
    check("show/hide button only on Runeway pages", hiddenElsewhere and tg:IsShown())
    check("main page: intro + 14 quick commands (+ profile text)", kinds.element == 16 and INITS[1].data.text == NS.L.INTRO and INITS[3].data.desc ~= nil)
    check("settings rows: 1 header, 2 bindings, 7 layers",
        kinds.header == 1 and kinds.binding == 2 and kinds.layerrow == 7)
    check("mode dropdown has 3 entries", #INITS[17].options == 3)
    -- values changed outside the panel are pushed to the settings rows
    local notified = {}
    Settings.NotifyUpdate = function(v) notified[v] = true end
    view:GetScript("OnMouseWheel")(view, 1)
    SlashCmdList.RUNEWAY("size 900 500")
    check("live update: zoom and size notified", notified.RUNEWAY_ZOOM and notified.RUNEWAY_W and notified.RUNEWAY_H
        and db.w == 900 and db.h == 500)
    -- mouse-over: arrow in the centre is enlarged; inside a quest area the tooltip lists its quest(s)
    local tipLines = {}
    GameTooltip.AddLine = function(_, text) tipLines[#tipLines + 1] = text end
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
    -- combined outline (4242 + 4243 overlap): the tooltip lists only the quests whose own area is hovered
    local only, both = false, false
    local b = A[4242].box
    for i = 0, 20 do
        for j = 0, 20 do
            local h = NS.QuestAreasAt(b[1] + (b[2] - b[1]) * i / 20, b[3] + (b[4] - b[3]) * j / 20)
            if #h == 1 then only = true elseif #h == 2 then both = true end
        end
    end
    check("hover: merged areas list only the hovered quests", db.questMerge and only and both)
    NS.QuestAreasAt(nil)
    rawset(view, "IsMouseOver", nil)
    if not wasShown then view:Hide() end
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
    local f = setmetatable({ ColorSwatch = CreateFrame("Button"), cbrHandles = { SetOnValueChangedCallback = function() end } },
        { __index = RunewayLayerRowMixin })
    f.ColorSwatch.SetColor = function() end
    RunewayLayerRowMixin.Init(f, row)
    f.ColorSwatch:GetScript("OnClick")()
    ColorPickerFrame.info.swatchFunc()
    check("layer row: swatch sets the roads colour", math.abs(db.colors.roads.r - 0.1) < 0.01 and math.abs(db.colors.roads.b - 0.3) < 0.01)
    for var, st in pairs(SETTINGS) do
        if st:GetValue() == nil then check("setting reads a value: " .. var, false) end
    end
    SETTINGS.RUNEWAY_EDGE:SetValue(5)
    check("edge 5 -> fade5.tga", TEXTURES[#TEXTURES]:find("fade5.tga") ~= nil)
    SETTINGS.RUNEWAY_COLOR_FILL:SetValue("ff1a334d")
    check("colour swatch sets fill", math.abs(db.colors.fill.r - 0.1) < 0.01 and math.abs(db.colors.fill.b - 0.3) < 0.01)
    check("colour swatch reads hex", SETTINGS.RUNEWAY_COLOR_FILL:GetValue() == "ff1a334d")
    SETTINGS.RUNEWAY_OPACITY_ROADS:SetValue(0.5)
    SETTINGS.RUNEWAY_AUTOHIDE_COMBAT:SetValue(true)
    check("opacity and auto-hide write the db", db.colors.roads.a == 0.5 and db.autoHide.combat == true)
    for _, st in pairs(SETTINGS) do st:SetValue(st.default) end
    check("defaults restored", db.edge == 3 and db.w == 800 and db.h == 600 and db.mode == "key" and db.colors.roads.a == 0.65
        and math.abs(db.colors.fill.r) < 0.01 and db.zoom == 0.3 and db.questMerge == true and db.corpseSize == 25)
    view:GetScript("OnUpdate")(view, 0.05)
''')

# every referenced texture file must exist
missing = [p for p in L.globals().TEXTURES.values() if p.startswith('Interface\\AddOns\\Runeway')
           and not os.path.exists(os.path.join(ROOT, p.replace('Interface\\AddOns\\', '').replace('\\', os.sep)))]
print('missing texture files:', missing or 'none')
