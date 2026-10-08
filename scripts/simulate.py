# Reproduces the Lua rendering: layer tiles in world coordinates, tinted like SetVertexColor,
# player in the centre, rotation. Reads the generated TGAs, so it also checks orientation and paths.
#   python scripts/simulate.py [north west [zoom [out.png]]]      default: north-east of Undercity, zoom 1.5
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
COLORS = dict(fill=(0, 0, 0, 0.10), hatch=(0.80, 0.84, 0.88, 0.20), shade=(0, 0, 0, 0.45),
              terrain=(0.82, 0.86, 0.89, 0.85), water=(0.82, 0.86, 0.89, 0.80), roads=(0.92, 0.72, 0.28, 0.65))     # defaults in Core.lua
W, H = 600, 600
pN, pW = (float(sys.argv[1]), float(sys.argv[2])) if len(sys.argv) > 2 else (1917.6, 84.9)
k = float(sys.argv[3]) if len(sys.argv) > 3 else 1.5
OUT = sys.argv[4] if len(sys.argv) > 4 else os.path.join(ROOT, 'build', 'sim.png')

FILE_LOD = dict(fill={128: 128, 256: 128, 512: 128}, shade={128: 128, 256: 256, 512: 256})   # as in Core.lua
HATCH_MASK_LOD = 256
tiles = dict(re.findall(r'\["(\d+_\d+)"\] = "(\w+)"', open(os.path.join(ROOT, 'Runeway', 'Tiles.lua')).read()))


def render(facing):
    ang = -facing
    can = np.full((H, W, 3), 30, np.float32)
    size = T * k
    lod = 128 if size < 160 else 256 if size < 360 else 512
    path = lambda lo, key, layer: os.path.join(ROOT, 'Runeway', 'tiles', '0', '' if lo == 512 else str(lo), f'{key}_{layer}.tga')
    rgba = lambda p: np.array(Image.open(p).convert('RGBA')).astype(np.float32) / 255
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
            if layer == 'hatch':           # shared line pattern cut out by the tile mask
                img = rgba(os.path.join(ROOT, 'Runeway', 'media', f'hatch{lod}.tga'))
                m = rgba(path(HATCH_MASK_LOD, key, 'hatch'))[..., 3]
                img[..., 3] *= cv2.resize(m, (lod, lod), interpolation=cv2.INTER_LINEAR)
            else:
                img = rgba(path(FILE_LOD.get(layer, {}).get(lod, lod), key, layer))
            n = img.shape[0]
            s = size / n
            ca, sa = math.cos(ang) * s, math.sin(ang) * s
            h = n / 2
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
cv2.imwrite(OUT, np.vstack([render(0), render(math.pi / 2)]))
print(OUT, 'written')
