# Builds the overlay tiles from the RAW ADT export: white layers terrain / water / roads / shade
# per ADT tile and zoom level, clipped to the selected zones, plus Tiles.lua and preview images.
#   python scripts/build_raw.py ["Zone Name" ...]      default: zones listed in scripts/zones.txt
import os
import re
import sys
import csv
import glob
import shutil
import urllib.request
import numpy as np
import cv2
from PIL import Image
from skimage.morphology import skeletonize
from adt import read_area
from raw_mosaic import Mosaic, load_listfile, SRC, LISTFILE
from roads import prune

ROOT = os.path.join(os.path.dirname(__file__), '..')
OUT = os.path.join(ROOT, 'Runeway', 'tiles', '0')       # 0 = instance ID of the Eastern Kingdoms
TILES_LUA = os.path.join(ROOT, 'Runeway', 'Tiles.lua')
BUILD = os.path.join(ROOT, 'build')                      # cache and previews (not in git)
AREATABLE = os.path.join(SRC, '..', '..', 'AreaTable.csv')
LISTFILE_URL = 'https://github.com/wowdev/wow-listfile/releases/latest/download/community-listfile.csv'

P = 512                    # pixels per ADT tile (~1.04 yd/px)
LODS = (512, 256, 128)     # zoom levels written per layer
LAYERS = ('fill', 'hatch', 'shade', 'terrain', 'water', 'roads')
HATCH = {512: 9, 256: 6, 128: 4}   # hatch line spacing in pixels per zoom level
MAX_SLOPE = 50             # degrees; steeper terrain counts as not walkable
MIN_BLOCK = 1500           # px; smaller steep patches are ignored (single rocks, bumps)
BLOCK_CLOSE = 15           # px; merges rugged cliffs into one solid block
MIN_WALK = 25000           # px; smaller walkable islands are merged into the surrounding block
MIN_ISLAND = 300           # px; walkable islands / shore patches smaller than this are dropped
MIN_WATER = 800            # px; smaller ponds are dropped
ROAD_KEYS = ('road', 'path')   # texture name fragments that mark roads
ROAD_MIN = 0.3             # texture weight threshold for road pixels
ROAD_MIN_LEN = 60          # px; shorter road skeleton pieces are dropped
ZONE_SOFT = 12             # px; rounds the chunk-based (33 yd) zone border


# --- zones ------------------------------------------------------------------

def zone_of_area():
    """AreaTable: area ID -> top-level zone ID, and zone name -> zone ID."""
    rows = {int(r['ID']): r for r in csv.DictReader(open(AREATABLE, encoding='utf8'), delimiter=';')}
    top = {}
    for i in rows:
        z = i
        while int(rows[z]['ParentAreaID']) in rows and int(rows[z]['ParentAreaID']) != 0:
            z = int(rows[z]['ParentAreaID'])
        top[i] = z
    names = {rows[i]['AreaName_lang'].lower(): i for i in rows if int(rows[i]['ParentAreaID']) == 0}
    seas = {i for i in rows if re.search(r'\b(sea|ocean)\b', rows[i]['AreaName_lang'].lower())}
    return top, names, seas


def area_index():
    """Area IDs of all ADT chunks, cached: {(c, r): 16x16 array}."""
    cache = os.path.join(BUILD, 'area_index.npz')
    if os.path.exists(cache):
        d = np.load(cache)
        return {tuple(map(int, k.split('_'))): d[k] for k in d.files}
    idx = {}
    for p in glob.glob(os.path.join(SRC, 'azeroth_*_*.adt')):
        mt = re.search(r'azeroth_(\d+)_(\d+)\.adt$', p)
        if mt:
            idx[(int(mt[1]), int(mt[2]))] = read_area(p)
    os.makedirs(BUILD, exist_ok=True)
    np.savez_compressed(cache, **{f'{c}_{r}': a for (c, r), a in idx.items()})
    return idx


# --- masks ------------------------------------------------------------------

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
    # drop small walkable patches inside mountains, but keep islands and shore strips (they touch water)
    n, lab, st, _ = cv2.connectedComponentsWithStats(walk.astype(np.uint8), connectivity=8)
    shore = np.zeros(n, bool)
    shore[np.unique(lab[walk & (cv2.dilate(water.astype(np.uint8), np.ones((7, 7), np.uint8)) > 0)])] = True
    area = st[:, cv2.CC_STAT_AREA]
    keepc = (area >= MIN_WALK) | (shore & (area >= MIN_ISLAND))
    keepc[0] = False
    walk = keepc[lab]
    walk = ~blobs(~walk & present, MIN_BLOCK) & present        # fill small holes

    # Roads: road textures -> centre lines
    lf = load_listfile()
    names = sorted({n for n in lf.values() if any(k in n for k in ROAD_KEYS)})
    tex = m.build_textures(lf, names)
    rw = sum(tex.values()) if tex else np.zeros_like(m.height)
    road = smooth(rw > ROAD_MIN, 1.5)
    road = cv2.morphologyEx(road.astype(np.uint8), cv2.MORPH_CLOSE,
                            cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9))).astype(bool) & ~water
    sk = prune(skeletonize(road).astype(np.uint8) * 255, 12) > 0
    sk = blobs(sk, ROAD_MIN_LEN)
    return m, dict(walk=walk, water=water, road=sk, present=present)


def contours(mask, min_len=40):
    cnts, _ = cv2.findContours(mask.astype(np.uint8), cv2.RETR_LIST, cv2.CHAIN_APPROX_NONE)
    return [cv2.approxPolyDP(c, 1.0, True) for c in cnts if cv2.arcLength(c, True) >= min_len]


def line_layers(L, keep):
    """White layers (alpha 0..255): fill (walkable area), blocked (source of the hatch layer: mountains,
    water), terrain / water / roads lines and the dark shade under them.
    keep: mask of the selected zones; everything outside is cleared."""
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
    edge = ~L['present']                                       # missing tiles and mosaic border
    edge[:3, :] = edge[-3:, :] = edge[:, :3] = edge[:, -3:] = True
    edge = cv2.dilate(edge.astype(np.uint8), np.ones((9, 9), np.uint8)) > 0
    fade = cv2.GaussianBlur(keep.astype(np.float32), (0, 0), ZONE_SOFT / 2)  # soft zone border
    zf = np.clip((fade - 0.3) / 0.4, 0, 1)
    fill = (L['walk'] * 255).astype(np.uint8)
    blocked = ((L['present'] & ~L['walk']) * 255).astype(np.uint8)
    for a in (terrain, water, roads, fill, blocked):
        a[edge] = 0
        a[:] = (a * zf).astype(np.uint8)
    shade = cv2.dilate(np.maximum(np.maximum(terrain, water), roads), np.ones((7, 7), np.uint8))
    shade = (cv2.GaussianBlur(shade, (0, 0), 1.5).astype(np.float32) * 0.65).astype(np.uint8)
    return dict(fill=fill, blocked=blocked, terrain=terrain, water=water, roads=roads, shade=shade)


# --- output -----------------------------------------------------------------

def hatch(mask, size, c, r):
    """Diagonal hatch lines inside mask, spacing per zoom level, continuous across tiles (global pixel grid)."""
    m = cv2.resize(mask, (size, size), interpolation=cv2.INTER_AREA).astype(np.float32) / 255
    sp = HATCH[size]
    y, x = np.mgrid[0:size, 0:size]
    t = (c * size + x + r * size + y) % sp                    # lines run bottom left -> top right
    d = np.minimum(t, sp - t) / np.sqrt(2)                    # distance to the nearest line in pixels
    line = np.clip(1.2 - d, 0, 1)
    return (line * m * 255).astype(np.uint8)


def downscale(a, size, lines=True):
    """Shrinks a layer; line layers are widened first so they stay visible."""
    f = a.shape[0] // size
    if f == 1:
        return a
    if not lines:
        return cv2.resize(a, (size, size), interpolation=cv2.INTER_AREA)
    b = cv2.resize(cv2.dilate(a, np.ones((f, f), np.uint8)), (size, size), interpolation=cv2.INTER_AREA)
    return np.clip(b.astype(np.int32) * 2, 0, 255).astype(np.uint8)


def save_tga(alpha, path):
    """White RGBA TGA, RLE compressed, origin bottom left."""
    rgba = np.dstack([np.full_like(alpha, 255)] * 3 + [alpha])
    rgba[alpha == 0, :3] = 0                                   # better RLE runs
    Image.fromarray(rgba, 'RGBA').save(path, compression='tga_rle', orientation=1)


def write_tiles(layers, cols, rows, tiles):
    """Writes Runeway/tiles/0/[lod/]<c>_<r>_<layer>.tga and returns {(c, r): 'twrs'}."""
    shutil.rmtree(OUT, ignore_errors=True)
    for s in LODS:
        os.makedirs(OUT if s == P else os.path.join(OUT, str(s)), exist_ok=True)
    written = {}
    for c, r in sorted(tiles):
        ys = slice((r - rows[0]) * P, (r - rows[0] + 1) * P)
        xs = slice((c - cols[0]) * P, (c - cols[0] + 1) * P)
        have = ''
        for n in LAYERS:
            blk = np.ascontiguousarray(layers['blocked' if n == 'hatch' else n][ys, xs])
            if blk.max() < 8:
                continue
            have += n[0]
            for s in LODS:
                d = OUT if s == P else os.path.join(OUT, str(s))
                img = hatch(blk, s, c, r) if n == 'hatch' else downscale(blk, s, n != 'fill')
                save_tga(img, os.path.join(d, f'{c}_{r}_{n}.tga'))
        if have:
            written[(c, r)] = have
    with open(TILES_LUA, 'w', newline='\n') as fh:
        fh.write('-- generated by scripts/build_raw.py: tiles per instance ("col_row" = layers present:\n')
        fh.write('-- f = fill, h = hatch, s = shade, t = terrain, w = water, r = roads)\n')
        fh.write('RunewayTiles = {\n    [0] = {\n')
        for (c, r), h in sorted(written.items()):
            fh.write(f'        ["{c}_{r}"] = "{h}",\n')
        fh.write('    },\n}\n')
    return written


# RGBA as the defaults in Core.lua (drawn in LAYERS order)
COLORS = dict(fill=(1, 1, 1, 0.09), hatch=(0.80, 0.84, 0.88, 0.22), shade=(0.05, 0.05, 0.06, 0.45),
              terrain=(0.82, 0.86, 0.89, 0.85), water=(0.82, 0.86, 0.89, 0.85), roads=(0.82, 0.86, 0.89, 0.4))


def compose(layers, base=None):
    """Tints the white layers like the addon does at runtime (BGR output). Hatch uses the 512 pattern."""
    H, W = layers['terrain'].shape
    out = np.full((H, W, 3), 30, np.float32) if base is None else base.astype(np.float32)
    y, x = np.mgrid[0:H, 0:W]
    t = (x + y) % HATCH[512]
    hatch_full = (np.clip(1.2 - np.minimum(t, HATCH[512] - t) / np.sqrt(2), 0, 1) * layers['blocked']).astype(np.float32)
    for n in LAYERS:
        a = (hatch_full if n == 'hatch' else layers[n].astype(np.float32))[..., None] / 255.0 * COLORS[n][3]
        out = out * (1 - a) + np.array(COLORS[n][2::-1], np.float32) * 255 * a
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


def main(zone_names):
    if not os.path.exists(LISTFILE):
        print('downloading listfile ...')
        urllib.request.urlretrieve(LISTFILE_URL, LISTFILE)
    top, names, seas = zone_of_area()
    zones = set()
    for n in zone_names:
        if n.lower() not in names:
            sys.exit(f'unknown zone: {n}')
        zones.add(names[n.lower()])
    idx = area_index()
    zone_of = np.vectorize(lambda x: top.get(int(x), int(x)))
    land = lambda a: np.isin(zone_of(a), list(zones)) & ~np.isin(a, list(seas))
    tiles = {k for k, a in idx.items() if land(a).any()}
    if not tiles:
        sys.exit('no tiles found for ' + ', '.join(zone_names))
    # mosaic with one tile margin for clean borders
    cols = list(range(min(c for c, _ in tiles) - 1, max(c for c, _ in tiles) + 2))
    rows = list(range(min(r for _, r in tiles) - 1, max(r for _, r in tiles) + 2))
    print(f'{len(tiles)} tiles, mosaic cols {cols[0]}-{cols[-1]} rows {rows[0]}-{rows[-1]}')
    m, L = build(cols, rows)
    # zone mask per chunk: zone land, plus sea chunks next to it (the coast belongs to the zone)
    keep = np.zeros((len(rows) * 16, len(cols) * 16), bool)
    sea = np.zeros_like(keep)
    for (c, r), a in idx.items():
        if c in cols and r in rows:
            ys = slice((r - rows[0]) * 16, (r - rows[0] + 1) * 16)
            xs = slice((c - cols[0]) * 16, (c - cols[0] + 1) * 16)
            keep[ys, xs] = land(a)
            sea[ys, xs] = np.isin(a, list(seas))
    keep |= sea & (cv2.dilate(keep.astype(np.uint8), np.ones((5, 5), np.uint8)) > 0)
    keep = cv2.resize(keep.astype(np.uint8), (m.W, m.H), interpolation=cv2.INTER_NEAREST) > 0
    layers = line_layers(L, keep)
    written = write_tiles(layers, cols, rows, tiles)
    os.makedirs(BUILD, exist_ok=True)
    half = lambda a: cv2.resize(a, (a.shape[1] // 2, a.shape[0] // 2), interpolation=cv2.INTER_AREA)
    cv2.imwrite(os.path.join(BUILD, 'preview_lines.png'), half(compose(layers)))
    cv2.imwrite(os.path.join(BUILD, 'preview_over_minimap.png'),
                half(compose(layers, (minimap(cols, rows) * 0.45).astype(np.uint8))))
    size = sum(os.path.getsize(os.path.join(d, f)) for d, _, fs in os.walk(OUT) for f in fs)
    print(f'{len(written)} tiles written, {size / 1e6:.1f} MB, previews in build/')


if __name__ == '__main__':
    zl = sys.argv[1:] or [l.strip() for l in open(os.path.join(os.path.dirname(__file__), 'zones.txt'))
                          if l.strip() and not l.startswith('#')]
    main(zl)
