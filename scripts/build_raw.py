# Builds the overlay masks (terrain, water, roads) from the RAW ADT export and writes a preview.
#   python scripts/build_raw.py [c0 c1 r0 r1]      default: Tirisfal 26 34 26 29
import os
import re
import sys
import glob
import numpy as np
import cv2
from skimage.morphology import skeletonize
from raw_mosaic import Mosaic, load_listfile, SRC
from roads import prune

P = 512                    # pixels per ADT tile (~1.04 yd/px)
MAX_SLOPE = 50             # degrees; steeper terrain counts as not walkable
MIN_BLOCK = 1500           # px; smaller steep patches are ignored (single rocks, bumps)
BLOCK_CLOSE = 15           # px; merges rugged cliffs into one solid block
MIN_WALK = 25000           # px; smaller walkable islands are merged into the surrounding block
MIN_WATER = 800            # px; smaller ponds are dropped
ROAD_KEYS = ('road', 'path')   # texture name fragments that mark roads
ROAD_MIN = 0.3             # texture weight threshold for road pixels
ROAD_MIN_LEN = 60          # px; shorter road skeleton pieces are dropped


def blobs(m, min_area):
    """Drops connected components smaller than min_area."""
    n, lab, st, _ = cv2.connectedComponentsWithStats(m.astype(np.uint8), connectivity=8)
    keep = np.zeros(n, bool)
    keep[1:] = st[1:, cv2.CC_STAT_AREA] >= min_area
    return keep[lab]


def smooth(m, sigma):
    """Rounds mask outlines (blur + threshold)."""
    return cv2.GaussianBlur(m.astype(np.float32), (0, 0), sigma) > 0.5


def build(cols, rows):
    m = Mosaic(cols, rows, P)
    m.build_terrain()
    present = m.present & ~cv2.dilate((~m.present).astype(np.uint8), np.ones((3, 3), np.uint8)).astype(bool)

    # Water: exact MH2O surface above terrain
    water = smooth(m.water, 1.5) & present
    water = blobs(water, MIN_WATER)

    # Terrain: walkable = not steep, not water
    steep = (m.slope_deg() > MAX_SLOPE) & ~water
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (BLOCK_CLOSE, BLOCK_CLOSE))
    steep = cv2.morphologyEx(steep.astype(np.uint8), cv2.MORPH_CLOSE, k).astype(bool)
    steep = blobs(steep, MIN_BLOCK)
    walk = present & ~steep & ~water
    walk = smooth(walk, 4)
    walk = blobs(walk, MIN_WALK)
    walk = ~blobs(~walk & present, MIN_BLOCK) & present        # fill small holes

    # Roads: road textures -> centre lines
    lf = load_listfile()
    names = sorted({n for n in lf.values() if any(k in n for k in ROAD_KEYS)})
    tex = m.build_textures(lf, names)
    rw = sum(tex.values()) if tex else np.zeros_like(m.height)
    road = smooth(rw > ROAD_MIN, 1.5)
    road = cv2.morphologyEx(road.astype(np.uint8), cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9))).astype(bool) & ~water
    sk = prune(skeletonize(road).astype(np.uint8) * 255, 12) > 0
    sk = blobs(sk, ROAD_MIN_LEN)
    return m, dict(walk=walk, water=water, road=sk, present=present)


def contours(mask, min_len=40):
    cnts, _ = cv2.findContours(mask.astype(np.uint8), cv2.RETR_LIST, cv2.CHAIN_APPROX_NONE)
    return [cv2.approxPolyDP(c, 1.0, True) for c in cnts if cv2.arcLength(c, True) >= min_len]


def line_layers(L):
    """White line layers (alpha only): terrain, water, roads, plus the dark shade under them."""
    H, W = L['walk'].shape
    terrain = np.zeros((H, W), np.uint8)
    water = np.zeros((H, W), np.uint8)
    cv2.drawContours(terrain, contours(L['walk']), -1, 255, 2, cv2.LINE_AA)
    cv2.drawContours(water, contours(L['water']), -1, 255, 2, cv2.LINE_AA)
    # shore: terrain line only where the walk edge borders steep ground, not water
    near_water = cv2.dilate(L['water'].astype(np.uint8), np.ones((9, 9), np.uint8)) > 0
    terrain[near_water] = 0
    roads = (cv2.dilate(L['road'].astype(np.uint8), np.ones((2, 2), np.uint8)) * 230).astype(np.uint8)
    roads[L['water']] = 0
    edge = ~L['present']
    for a in (terrain, water, roads):
        a[edge] = 0
    shade = cv2.dilate(np.maximum(np.maximum(terrain, water), roads), np.ones((7, 7), np.uint8))
    shade = (cv2.GaussianBlur(shade, (0, 0), 1.5).astype(np.float32) * 0.65).astype(np.uint8)
    return dict(terrain=terrain, water=water, roads=roads, shade=shade)


COLORS = dict(terrain=(220, 205, 250), water=(100, 180, 250), roads=(238, 220, 185))   # RGB


def compose(layers, base=None):
    """Colours the white layers like the addon will do at runtime (BGR output)."""
    H, W = layers['terrain'].shape
    out = np.full((H, W, 3), 30, np.float32) if base is None else base.astype(np.float32)
    a = layers['shade'][..., None] / 255.0
    out = out * (1 - a) + np.array([22, 18, 28], np.float32) * a
    for n in ('terrain', 'water', 'roads'):
        a = layers[n][..., None] / 255.0
        out = out * (1 - a) + np.array(COLORS[n][::-1], np.float32) * a
    return out.clip(0, 255).astype(np.uint8)


def minimap(cols, rows):
    img = np.zeros((len(rows) * P, len(cols) * P, 3), np.uint8)
    for f in glob.glob(os.path.join(SRC, 'minimap', 'map*.png')):
        c, r = map(int, re.findall(r'map(\d+)_(\d+)', f)[0])
        if c in cols and r in rows:
            t = cv2.imread(f)
            if t.shape[0] != P:
                t = cv2.resize(t, (P, P), interpolation=cv2.INTER_AREA)
            img[(r - rows[0]) * P:(r - rows[0] + 1) * P, (c - cols[0]) * P:(c - cols[0] + 1) * P] = t
    return img


if __name__ == '__main__':
    c0, c1, r0, r1 = map(int, sys.argv[1:5]) if len(sys.argv) >= 5 else (26, 34, 26, 29)
    cols, rows = list(range(c0, c1 + 1)), list(range(r0, r1 + 1))
    m, L = build(cols, rows)
    layers = line_layers(L)
    out = os.environ.get('RUNEWAY_PREVIEW', 'preview')
    os.makedirs(out, exist_ok=True)
    mm = minimap(cols, rows)
    half = lambda a: cv2.resize(a, (a.shape[1] // 2, a.shape[0] // 2), interpolation=cv2.INTER_AREA)
    cv2.imwrite(f'{out}/raw_lines.png', half(compose(layers)))
    cv2.imwrite(f'{out}/raw_over_minimap.png', half(compose(layers, (mm * 0.45).astype(np.uint8))))
    np.savez_compressed(f'{out}/raw_layers.npz', cols=cols, rows=rows, **layers)
    print('preview written to', out)
