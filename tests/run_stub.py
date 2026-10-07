# Loads the addon with a WoW API stub, fires the login events, renders frames and runs slash commands.
#   python tests/run_stub.py
import os
import lupa
from lupa import lua51       # WoW runs Lua 5.1

ROOT = os.path.join(os.path.dirname(__file__), '..')
L = lua51.LuaRuntime(unpack_returned_tuples=True)
L.execute(open(os.path.join(ROOT, 'tests', 'wow_stub.lua')).read())
for f in ('Tiles.lua', 'Core.lua', 'QuestAreas.lua', 'Probe.lua'):
    src = open(os.path.join(ROOT, 'Runeway', f), encoding='utf8').read()
    L.execute('NS = NS or {}; local f = assert(loadstring(..., "@' + f + '")); f("Runeway", NS)', src)

L.execute('''
    local function fire(event, arg)
        for _, f in ipairs(FRAMES) do
            local h = f:GetScript("OnEvent")
            if h then h(f, event, arg) end
        end
    end
    fire("ADDON_LOADED", "Runeway")
    fire("PLAYER_ENTERING_WORLD")
    RunewayFrame:Show()
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

# every referenced texture file must exist
missing = [p for p in L.globals().TEXTURES.values() if p.startswith('Interface\\AddOns\\Runeway')
           and not os.path.exists(os.path.join(ROOT, p.replace('Interface\\AddOns\\', '').replace('\\', os.sep)))]
print('missing texture files:', missing or 'none')
