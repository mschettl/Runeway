# Reproduces the Lua rendering: layer tiles in world coordinates, tinted like SetVertexColor,
# player in the centre, rotation. Reads the generated TGAs, so it also checks orientation and paths.
#   python scripts/simulate.py [north west]       default: north-east of Undercity
import os
import re
import sys
import math
import numpy as np
import cv2
from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), '..')
T = 1600 / 3
LAYERS = ('fill', 'hatch', 'shade', 'terrain', 'water', 'roads')
COLORS = dict(fill=(0.80, 0.64, 0.44, 0.07), hatch=(0.80, 0.84, 0.88, 0.22), shade=(0.05, 0.05, 0.06, 0.45),
              terrain=(0.82, 0.86, 0.89, 0.85), water=(0.82, 0.86, 0.89, 0.85),
              roads=(0.82, 0.86, 0.89, 0.4))     # defaults in Core.lua
W, H, k = 600, 600, 1.5
pN, pW = (float(sys.argv[1]), float(sys.argv[2])) if len(sys.argv) > 2 else (1917.6, 84.9)

tiles = dict(re.findall(r'\["(\d+_\d+)"\] = "(\w+)"', open(os.path.join(ROOT, 'Runeway', 'Tiles.lua')).read()))


def render(facing):
    ang = -facing
    can = np.full((H, W, 3), 30, np.float32)
    size = T * k
    lod = 128 if size < 160 else 256 if size < 360 else 512
    d = os.path.join(ROOT, 'Runeway', 'tiles', '0', '' if lod == 512 else str(lod))
    for layer in LAYERS:
        for key, have in tiles.items():
            if layer[0] not in have:
                continue
            c, r = map(int, key.split('_'))
            cn = (32 - r) * T - T / 2
            cw = (32 - c) * T - T / 2
            sx, sy = -(cw - pW) * k, (cn - pN) * k
            x = sx * math.cos(ang) - sy * math.sin(ang)
            y = sx * math.sin(ang) + sy * math.cos(ang)
            img = np.array(Image.open(os.path.join(d, f'{key}_{layer}.tga')).convert('RGBA')).astype(np.float32) / 255
            s = size / lod
            ca, sa = math.cos(ang) * s, math.sin(ang) * s
            h = lod / 2
            M = np.array([[ca, sa, W / 2 + x - (ca * h + sa * h)], [-sa, ca, H / 2 - y - (-sa * h + ca * h)]], np.float32)
            wimg = cv2.warpAffine(img, M, (W, H), flags=cv2.INTER_LINEAR, borderValue=(0, 0, 0, 0))
            col = np.array(COLORS[layer][:3], np.float32) * 255
            a = wimg[..., 3:4] * COLORS[layer][3]
            can = can * (1 - a) + wimg[..., :3] * col * a
    out = can.clip(0, 255).astype(np.uint8)
    cv2.arrowedLine(out, (W // 2, H // 2 + 10), (W // 2, H // 2 - 12), (255, 80, 60), 3, tipLength=0.5)
    cv2.putText(out, f'facing {math.degrees(facing):.0f} deg', (10, 25), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (200, 200, 200), 1)
    return cv2.cvtColor(out, cv2.COLOR_RGB2BGR)


os.makedirs(os.path.join(ROOT, 'build'), exist_ok=True)
cv2.imwrite(os.path.join(ROOT, 'build', 'sim.png'), np.vstack([render(0), render(math.pi / 2)]))
print('build/sim.png written')
