# Loads the addon with a WoW API stub, fires the login events, renders frames and runs slash commands.
#   python tests/run_stub.py
import os
import lupa
from lupa import lua51       # WoW runs Lua 5.1

ROOT = os.path.join(os.path.dirname(__file__), '..')
L = lua51.LuaRuntime(unpack_returned_tuples=True)
L.execute(open(os.path.join(ROOT, 'tests', 'wow_stub.lua')).read())
for f in ('Runeway/Tiles.lua', 'Runeway/Core.lua', 'Runeway/QuestAreas.lua', 'Runeway/Options.lua', 'tools/Probe.lua'):
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
    db.worldMapKey = "SHIFT-M"
    SlashCmdList.RUNEWAY("mode mapkey")
    check("mapkey: M -> overlay", BINDINGS.M == "RUNEWAY_TOGGLE")
    check("mapkey: SHIFT-M -> world map", BINDINGS["SHIFT-M"] == "TOGGLEWORLDMAP")
    wipe(BINDINGS); fire("UPDATE_BINDINGS")
    check("mapkey: re-applied on UPDATE_BINDINGS", BINDINGS.M == "RUNEWAY_TOGGLE")
    SlashCmdList.RUNEWAY("keys")
    SlashCmdList.RUNEWAY("mode key")
    check("key mode: no override bindings", next(BINDINGS) == nil)
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
    -- resize grip: left 150, top 750, cursor 700/300 -> 550 x 450 -> square 550
    local grip
    for _, f in ipairs(FRAMES) do if f:GetScript("OnMouseDown") then grip = f end end
    grip:GetScript("OnMouseDown")(grip)
    grip:GetScript("OnUpdate")(grip, 0.1)
    grip:GetScript("OnMouseUp")(grip)
    check("grip sizes square (550)", db.w == 550)
    CURSOR[1] = 5000
    grip:GetScript("OnMouseDown")(grip); grip:GetScript("OnUpdate")(grip, 0.1); grip:GetScript("OnMouseUp")(grip)
    check("grip clamps to 1400", db.w == 1400)
    -- options panel
    SlashCmdList.RUNEWAY("config")
    check("/rnw config opens category", OPENED == 77)
    SETTINGS_PANEL:GetScript("OnShow")(SETTINGS_PANEL)
    SlashCmdList.RUNEWAY("edge 5")
    check("edge 5 -> fade5.tga", TEXTURES[#TEXTURES]:find("fade5.tga") ~= nil)
    rawset(ColorPickerFrame, "info", nil)
    -- the first swatch button (fill): click and pick a colour
    for _, f in ipairs(FRAMES) do
        if f:GetScript("OnClick") and not rawget(ColorPickerFrame, "info") then
            local h = f:GetScript("OnClick")
            if rawget(f, "Refresh") and not rawget(f.Text, "_text") and f:GetScript("OnEnter") then h(f) end
        end
    end
    if rawget(ColorPickerFrame, "info") then ColorPickerFrame.info.swatchFunc() end
    check("colour picker sets fill", db.colors.fill.r == 0.1 and db.colors.fill.b == 0.3)
    SETTINGS_PANEL:OnDefault()
    check("defaults restored", db.edge == 3 and db.w == 600 and db.mode == "key")
    view:GetScript("OnUpdate")(view, 0.05)
''')

# every referenced texture file must exist
missing = [p for p in L.globals().TEXTURES.values() if p.startswith('Interface\\AddOns\\Runeway')
           and not os.path.exists(os.path.join(ROOT, p.replace('Interface\\AddOns\\', '').replace('\\', os.sep)))]
print('missing texture files:', missing or 'none')
