# Renders the quest area outlines exactly as QuestAreas.lua traces them (Lua code via lupa), using the fine
# grids of a /rnw probe SavedVariables file, as a blue glow over the map preview from build_raw.py.
#   python tests/render_quest_outlines.py <SavedVariables/Runeway.lua>
import os
import re
import sys
import numpy as np
import cv2
import lupa
from lupa import lua51       # WoW runs Lua 5.1

ROOT = os.path.join(os.path.dirname(__file__), '..')
L = lua51.LuaRuntime(unpack_returned_tuples=True)
L.execute(open(os.path.join(ROOT, 'tests', 'wow_stub.lua')).read())
for f in ('Tiles.lua', 'Core.lua', 'QuestAreas.lua'):
    src = open(os.path.join(ROOT, 'Runeway', f), encoding='utf8').read()
    L.execute('NS = NS or {}; local f = assert(loadstring(..., "@' + f + '")); f("Runeway", NS)', src)
L.execute(open(sys.argv[1], encoding='utf8').read())
probe = L.globals().RunewayDB.probe
trace = L.globals().NS.TraceOutline
to_grid = L.eval('function(rows, nx, ny) local g = {} for r = 1, ny do local s = rows[r] '
                 'for c = 1, nx do g[(r - 1) * nx + c] = s:sub(c, c) == "1" end end return g end')

n0, w0, n1, w1 = list(probe.corners.values())
T = 1600 / 3
SCALE = 2                                            # render at 2x the half-size preview = full resolution
base = cv2.imread(os.path.join(ROOT, 'build', 'preview_lines.png'))
base = cv2.resize(base, (base.shape[1] * SCALE, base.shape[0] * SCALE), interpolation=cv2.INTER_LINEAR).astype(np.float32)
keys = [tuple(map(int, k)) for k in re.findall(r'\["(\d+)_(\d+)"\]', open(os.path.join(ROOT, 'Runeway', 'Tiles.lua')).read())]
c0, r0 = min(c for c, _ in keys) - 1, min(r for _, r in keys) - 1
ppt = base.shape[1] / (max(c for c, _ in keys) + 2 - c0)
core = np.zeros(base.shape[:2], np.float32)
halo = np.zeros_like(core)
for q in probe.quests.values():
    f = q.fine
    if not f or not f.hits:
        continue
    x0, y0, x1, y1 = list(f.rect.values())
    for loop in trace(to_grid(f.rows, f.nx, f.ny), f.nx, f.ny).values():
        xs, ys = list(loop[1].values()), list(loop[2].values())
        pts = []
        for sx, sy in zip(xs, ys):
            mx, my = x0 + (sx + 0.5) * (x1 - x0) / f.nx, y0 + (sy + 0.5) * (y1 - y0) / f.ny
            north, west = n0 + (n1 - n0) * my, w0 + (w1 - w0) * mx
            pts.append(((32 - west / T - c0) * ppt * 16, (32 - north / T - r0) * ppt * 16))
        pts = np.array(pts, np.int32)
        cv2.polylines(core, [pts], True, 1.0, 2, cv2.LINE_AA, shift=4)
        cv2.polylines(halo, [pts], True, 1.0, 8, cv2.LINE_AA, shift=4)
glow = np.clip(core * 0.9 + cv2.GaussianBlur(halo, (0, 0), 3) * 0.45, 0, 1)
out = np.clip(base + glow[..., None] * np.array([1.00, 0.60, 0.35], np.float32) * 255, 0, 255).astype(np.uint8)
cv2.imwrite(os.path.join(ROOT, 'build', 'quest_outlines.png'), out)
print('build/quest_outlines.png written', out.shape)
