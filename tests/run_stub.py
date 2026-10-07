# Loads the addon with a WoW API stub, fires the login events, renders frames and runs slash commands.
#   python tests/run_stub.py
import os
import lupa

ROOT = os.path.join(os.path.dirname(__file__), '..')
L = lupa.LuaRuntime(unpack_returned_tuples=True)
L.execute(open(os.path.join(ROOT, 'tests', 'wow_stub.lua')).read())
for f in ('Tiles.lua', 'Core.lua', 'Probe.lua'):
    src = open(os.path.join(ROOT, 'Runeway', f), encoding='utf8').read()
    L.execute('local f = assert(load(..., "@' + f + '")); f("Runeway")', src)

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
    SlashCmdList.RUNEWAY("zoom 0.2")
    upd(RunewayFrame, 0.05)
    print("textures after zoom out:", #TEXTURES, TEXTURES[#TEXTURES])
    SlashCmdList.RUNEWAY("reset")
    POS[1] = nil
    upd(RunewayFrame, 0.05)
    SlashCmdList.RUNEWAY("help")
    SlashCmdList.RUNEWAY("probe 16")
    for _ = 1, 30 do
        for _, f in ipairs(FRAMES) do
            local h = f:GetScript("OnUpdate")
            if h and f ~= RunewayFrame then h(f, 0.25) end
        end
    end
    local p = RunewayDB.probe.quests[1]
    print("probe rows:")
    for _, r in ipairs(p.rows) do print("  " .. r) end
''')

# every referenced texture file must exist
missing = [p for p in L.globals().TEXTURES.values()
           if not os.path.exists(os.path.join(ROOT, p.replace('Interface\\AddOns\\', '').replace('\\', os.sep)))]
print('missing texture files:', missing or 'none')
