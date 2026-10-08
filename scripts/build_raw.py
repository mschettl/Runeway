# Builds the overlay tiles from the RAW ADT export: white layers fill / hatch / shade / terrain / water / roads
# per ADT tile and zoom level, clipped to the selected zones, plus the tile list and preview images.
#   python scripts/build_raw.py [--map ID] ["Zone Name" ...]    default: map 0, zones in scripts/zones_<ID>.txt
# The mosaic is one logical map, computed in blocks of BLOCK x BLOCK tiles with MARGIN tiles of overlap; only
# the inner part of a block is kept. Float rasters (heights, slopes, blurs, lines) exist per block only;
# whole-map steps that are not local (small islands, road paths, outlines) run on 1-byte masks of the mosaic.
import os
import re
import sys
import csv
import glob
import shutil
import urllib.request
import numpy as np
import cv2
from collections import defaultdict
from PIL import Image
from skimage.morphology import skeletonize
from adt import read_area
from raw_mosaic import Mosaic, load_listfile, MAPS, LISTFILE
from roads import prune
import structures

ROOT = os.path.join(os.path.dirname(__file__), '..')
# Data pack (load-on-demand addon) per map ID: <pack>/tiles/<map ID>/ holds the tile files and Tiles.lua
PACKS = {0: ('Runeway_EasternKingdoms', 'Eastern Kingdoms'), 1: ('Runeway_Kalimdor', 'Kalimdor')}
BUILD = os.path.join(ROOT, 'build')                      # cache and previews (not in git)
AREATABLE = os.path.join(MAPS, '..', 'AreaTable.csv')
MAP_NAMES = {0: 'azeroth', 1: 'kalimdor'}                # map ID (= instance ID of UnitPosition) -> wow.export folder
BLOCK = 8                  # tiles per block side
MARGIN = 1                 # tiles of overlap around a block; every local filter reaches less than one tile
LISTFILE_URL = 'https://github.com/wowdev/wow-listfile/releases/latest/download/community-listfile.csv'

P = 512                    # pixels per ADT tile (~1.04 yd/px)
LODS = (512, 256, 128)     # zoom levels written per layer
LAYERS = ('fill', 'hatch', 'shade', 'terrain', 'water', 'roads')
# Zoom levels stored per layer (file size). Soft area layers need little resolution; the addon draws a
# missing level with the nearest stored one. hatch = mask of the not walkable area: the hatch lines come
# from one shared pattern per zoom level (media/hatch<lod>.tga), cut out by this mask at runtime.
FILE_LODS = dict(fill=(128,), hatch=(128,), shade=(128,))
HATCH = {512: 57, 256: 43, 128: 32}   # hatch lines per tile and zoom level (spacing ~9 / 6 / 4 px)
MEDIA = os.path.join(ROOT, 'Runeway', 'media')
MAX_SLOPE = 50             # degrees; steeper terrain counts as not walkable
MIN_BLOCK = 1500           # px; smaller steep patches are ignored (single rocks, bumps)
BLOCK_CLOSE = 15           # px; merges rugged cliffs into one solid block
MIN_WALK = 25000           # px; smaller walkable islands are merged into the surrounding block
MIN_ISLAND = 300           # px; walkable islands / shore patches smaller than this are dropped
MIN_WATER = 800            # px; smaller ponds are dropped
ROAD_KEYS = ('road', 'path')   # texture name fragments that mark roads
ROAD_MIN = 0.3             # texture weight threshold for road pixels
ROAD_MIN_LEN = 60          # px; shorter road skeleton pieces are dropped
ZONE_SOFT = 32             # px; rounds the chunk-based (33 yd) zone border
ZONE_FEATHER = 0.7         # chunks; soft transition between the zone parts of a border tile
EDGE_FADE = 160            # px (~165 yd); everything fades out towards the edge of the built zones


# --- zones ------------------------------------------------------------------

def zone_of_area(map_id):
    """AreaTable: area ID -> top-level zone ID, and zone name -> zone ID (zones of this map only)."""
    rows = {int(r['ID']): r for r in csv.DictReader(open(AREATABLE, encoding='utf8'), delimiter=';')}
    top = {}
    for i in rows:
        z = i
        while int(rows[z]['ParentAreaID']) in rows and int(rows[z]['ParentAreaID']) != 0:
            z = int(rows[z]['ParentAreaID'])
        top[i] = z
    names = {rows[i]['AreaName_lang'].lower(): i for i in rows
             if int(rows[i]['ParentAreaID']) == 0 and rows[i]['ContinentID'] == str(map_id)}
    seas = {i for i in rows if re.search(r'\b(sea|ocean)\b', rows[i]['AreaName_lang'].lower())}
    return top, names, seas


def area_index(map_id):
    """Area IDs of all ADT chunks of a map, cached: {(c, r): 16x16 array}."""
    name = MAP_NAMES[map_id]
    cache = os.path.join(BUILD, f'area_index_{map_id}.npz')
    if os.path.exists(cache):
        d = np.load(cache)
        return {tuple(map(int, k.split('_'))): d[k] for k in d.files}
    idx = {}
    for p in glob.glob(os.path.join(MAPS, name, f'{name}_*_*.adt')):
        mt = re.search(rf'{name}_(\d+)_(\d+)\.adt$', p)
        if mt:
            idx[(int(mt[1]), int(mt[2]))] = read_area(p)
    os.makedirs(BUILD, exist_ok=True)
    np.savez_compressed(cache, **{f'{c}_{r}': a for (c, r), a in idx.items()})
    return idx


# --- blocks -----------------------------------------------------------------

def blocks(n_cols, n_rows):
    """Blocks of the mosaic as tile index ranges (i0, i1, j0, j1): the inner part and the window read with
    MARGIN tiles of overlap (clipped to the mosaic)."""
    for j in range(0, n_rows, BLOCK):
        for i in range(0, n_cols, BLOCK):
            inner = (i, min(i + BLOCK, n_cols), j, min(j + BLOCK, n_rows))
            win = (max(0, i - MARGIN), min(n_cols, inner[1] + MARGIN),
                   max(0, j - MARGIN), min(n_rows, inner[3] + MARGIN))
            yield inner, win


def px(rng, s=P, base=(0, 0, 0, 0)):
    """Pixel slices (rows, cols) of a tile range at s pixels per tile, relative to the range `base`."""
    return (slice((rng[2] - base[2]) * s, (rng[3] - base[2]) * s),
            slice((rng[0] - base[0]) * s, (rng[1] - base[0]) * s))


# --- masks ------------------------------------------------------------------

def u8(m):
    """Bool mask as uint8 without a copy."""
    return m.view(np.uint8) if m.dtype == bool else m.astype(np.uint8)


def blobs(m, min_area):
    """Drops connected components smaller than min_area."""
    n, lab, st, _ = cv2.connectedComponentsWithStats(u8(m), connectivity=8)
    keep = np.zeros(n, bool)
    keep[1:] = st[1:, cv2.CC_STAT_AREA] >= min_area
    return keep[lab]


def smooth(m, sigma, strip=2048):
    """Rounds mask outlines (blur + threshold); in row strips, so the float raster stays small."""
    pad = int(4 * sigma) + 2                                   # > kernel radius
    out = np.empty(m.shape, bool)
    for y in range(0, m.shape[0], strip):
        y0, y1 = max(0, y - pad), min(m.shape[0], y + strip + pad)
        b = cv2.GaussianBlur(m[y0:y1].astype(np.float32), (0, 0), sigma) > 0.5
        out[y:y + strip] = b[y - y0:y - y0 + strip]
    return out


def raw_masks(name, cols, rows):
    """Per-pixel masks of the mosaic from the ADT data, computed block by block: present, water (MH2O surface
    above terrain, smoothed), steep (slope only), road (road texture weight, smoothed), built (structures)."""
    shape = (len(rows) * P, len(cols) * P)
    R = {k: np.zeros(shape, bool) for k in ('present', 'water', 'steep', 'road', 'built')}
    lf = load_listfile()
    names = sorted({n for n in lf.values() if any(k in n for k in ROAD_KEYS)})
    for inner, win in blocks(len(cols), len(rows)):
        m = Mosaic(cols[win[0]:win[1]], rows[win[2]:win[3]], P, name)
        if not any(True for _ in m.tiles()):
            continue
        m.build_terrain()
        present = m.present & ~cv2.dilate(u8(~m.present), np.ones((3, 3), np.uint8)).astype(bool)
        a = dict(present=present, water=smooth(m.water, 1.5) & present, steep=m.slope_deg() > MAX_SLOPE,
                 road=smooth(m.build_textures(lf, names) > ROAD_MIN, 1.5), built=structures.blocked(m))
        dst, src = px(inner), px(inner, P, win)
        for k, v in a.items():
            R[k][dst] = v[src]
        print(f'  raw block cols {cols[inner[0]]}-{cols[inner[1] - 1]} rows {rows[inner[2]]}-{rows[inner[3] - 1]}', flush=True)
    if structures.USED:
        print('structures:', len(structures.USED), 'placements, e.g.', list(structures.USED.values())[:3])
    return R


def masks(R):
    """Whole-map masks (walk, water, road centre lines, present) from the raw masks; consumes R."""
    present = R['present']
    # Water: exact MH2O surface above terrain
    water = blobs(R.pop('water'), MIN_WATER)

    # Terrain: walkable = not steep, not water
    steep = R.pop('steep') & ~water
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (BLOCK_CLOSE, BLOCK_CLOSE))
    steep = cv2.morphologyEx(u8(steep), cv2.MORPH_CLOSE, k).astype(bool)
    steep = blobs(steep, MIN_BLOCK)
    walk = present & ~steep & ~water
    del steep
    walk = smooth(walk, 4)
    # drop small walkable patches inside mountains, but keep islands and shore strips (they touch water)
    n, lab, st, _ = cv2.connectedComponentsWithStats(u8(walk), connectivity=8)
    shore = np.zeros(n, bool)
    shore[np.unique(lab[walk & (cv2.dilate(u8(water), np.ones((7, 7), np.uint8)) > 0)])] = True
    area = st[:, cv2.CC_STAT_AREA]
    keepc = (area >= MIN_WALK) | (shore & (area >= MIN_ISLAND))
    keepc[0] = False
    walk = keepc[lab]
    del lab
    walk = ~blobs(~walk & present, MIN_BLOCK) & present        # fill small holes
    walk &= ~R.pop('built')                                     # building walls, towers (WMO / M2 exports)

    # Roads: road textures -> centre lines
    road = cv2.morphologyEx(u8(R.pop('road')), cv2.MORPH_CLOSE,
                            cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9))).astype(bool) & ~water
    sk = prune(skeletonize(road).astype(np.uint8) * 255, 12) > 0
    sk = blobs(sk, ROAD_MIN_LEN)
    return dict(walk=walk, water=water, road=sk, present=present)


# Lines are drawn per zoom level from the outlines (not shrunk from the 512 image): same stroke width at
# every level, coarser simplification and no small details when zoomed out.
LINE_LOD = {512: (40, 1.0, 2), 256: (90, 2.0, 1), 128: (300, 3.5, 1)}   # min outline length, simplification (full px), stroke px


def contours(mask):
    cnts, _ = cv2.findContours(mask.astype(np.uint8), cv2.RETR_LIST, cv2.CHAIN_APPROX_NONE)
    return cnts


def chaikin(p, n=2):
    """Chaikin corner cutting for an open polyline; the end points stay."""
    for _ in range(n):
        if len(p) < 3:
            return p
        q = np.empty((2 * len(p) - 2, 2))
        q[0::2] = 0.75 * p[:-1] + 0.25 * p[1:]
        q[1::2] = 0.25 * p[:-1] + 0.75 * p[1:]
        p = np.vstack([p[:1], q, p[-1:]])
    return p


OFFS = ((-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1))


def trace_paths(sk):
    """Skeleton -> open polylines (x, y). Paths run between end points and junctions; paths that meet
    at a junction of exactly two ends (pseudo junctions on pixel stairs) are joined again."""
    sk = (sk > 0).astype(np.uint8)
    H, W = sk.shape
    nb = cv2.filter2D(sk, cv2.CV_16S, np.ones((3, 3), np.float32), borderType=cv2.BORDER_CONSTANT) - sk
    node = (sk > 0) & (nb != 2)
    _, cluster = cv2.connectedComponents(node.astype(np.uint8), connectivity=8)
    seen = np.zeros((H, W), bool)

    def nbrs(y, x):
        for dy, dx in OFFS:
            ny, nx = y + dy, x + dx
            if 0 <= ny < H and 0 <= nx < W and sk[ny, nx]:
                yield ny, nx

    def follow(y, x, ny, nx):
        pts, prev = [(x, y)], (y, x)
        while True:
            pts.append((nx, ny))
            if node[ny, nx]:
                return pts, cluster[ny, nx]
            seen[ny, nx] = True
            nxt = [q for q in nbrs(ny, nx) if q != prev and not seen[q]]
            if not nxt:
                return pts, 0
            prev, (ny, nx) = (ny, nx), nxt[0]

    paths = []                                         # [pts, start cluster, end cluster]
    for y, x in zip(*np.nonzero(node)):
        for ny, nx in nbrs(y, x):
            if not node[ny, nx] and not seen[ny, nx]:
                pts, end = follow(y, x, ny, nx)
                paths.append([pts, cluster[y, x], end])
    for y, x in zip(*np.nonzero(sk.astype(bool) & ~node & ~seen)):   # closed rings without junctions
        if not seen[y, x]:
            seen[y, x] = True
            nxt = [q for q in nbrs(y, x) if not seen[q]]
            if nxt:
                pts, _ = follow(y, x, *nxt[0])
                paths.append([pts + [(x, y)], 0, 0])

    ends = defaultdict(list)
    for i, (_, a, b) in enumerate(paths):
        for c in (a, b):
            if c:
                ends[c].append(i)
    alias = list(range(len(paths)))

    def find(i):
        while alias[i] != i:
            i = alias[i]
        return i
    for c, ids in ends.items():
        if len(ids) != 2:
            continue
        i, j = find(ids[0]), find(ids[1])
        if i == j:
            continue
        pi, pj = paths[i], paths[j]
        if pi[2] != c:                                 # orient: i ends at c, j starts at c
            pi[:] = [pi[0][::-1], pi[2], pi[1]]
        if pj[1] != c:
            pj[:] = [pj[0][::-1], pj[2], pj[1]]
        paths[i] = [pi[0] + pj[0][1:], pi[1], pj[2]]
        paths[j] = None
        alias[j] = i
    return [np.array(p[0], np.float64) for p in paths if p]


def prepare_lines(lines, s, closed):
    """Outlines (closed) or road paths (open, smoothed) for zoom level s (pixels per tile): simplified points
    in 1/16 px of the scaled mosaic and their bounding boxes, so each block draws only its own lines."""
    min_len, eps, _ = LINE_LOD[s]
    f = s / P
    pts = []
    for c in lines:
        c = c.reshape(-1, 1, 2).astype(np.float32)
        if closed and cv2.arcLength(c, True) < min_len:   # road pieces end at junctions: keep all of them
            continue
        a = cv2.approxPolyDP(c, eps, closed).reshape(-1, 2).astype(np.float64)
        if not closed:
            a = chaikin(a)
        pts.append(np.round(a * f * 16).astype(np.int32))
    box = np.array([(*p.min(0), *p.max(0)) for p in pts], np.int64).reshape(-1, 4) // 16
    return pts, box, closed


def draw_lines(prep, s, x0, y0, shape):
    """Draws prepared lines of zoom level s on a canvas showing the scaled mosaic from pixel (x0, y0);
    same stroke width for outlines and roads."""
    pts, box, closed = prep
    width = LINE_LOD[s][2]
    out = np.zeros(shape, np.uint8)
    h, w = shape
    sel = np.nonzero((box[:, 2] >= x0 - 4) & (box[:, 0] < x0 + w + 4) &
                     (box[:, 3] >= y0 - 4) & (box[:, 1] < y0 + h + 4))[0]
    if len(sel):
        off = np.array([x0 * 16, y0 * 16], np.int32)
        cv2.polylines(out, [pts[i] - off for i in sel], closed, 255, width, cv2.LINE_AA, shift=4)
    if width == 1:                                             # thin anti-aliased strokes: lift the faint pixels
        out = np.clip(out.astype(np.float32) * 1.4, 0, 255).astype(np.uint8)
    return out


def map_lines(L):
    """Whole-map line sources: per zoom level the prepared terrain, water and road lines, the mosaic edge
    (missing tiles, border) and the area near water (no terrain line on the shore)."""
    edge = ~L['present']                                       # missing tiles and mosaic border
    edge[:3, :] = edge[-3:, :] = edge[:, :3] = edge[:, -3:] = True
    edge = cv2.dilate(u8(edge), np.ones((9, 9), np.uint8)) > 0
    near_water = cv2.dilate(u8(L['water']), np.ones((9, 9), np.uint8))
    walk_c, water_c = contours(L['walk']), contours(L['water'])
    road_p = trace_paths(L['road'])
    lines = {s: dict(terrain=prepare_lines(walk_c, s, True), water=prepare_lines(water_c, s, True),
                     roads=prepare_lines(road_p, s, False)) for s in LODS}
    return dict(lines=lines, edge=edge, near_water=near_water)


def zone_fade(keep, edge):
    """Soft map end (0..1): rounds the chunk border of the selected zones (keep), then fades in over
    EDGE_FADE px from the edge of the built zones."""
    inside = (cv2.GaussianBlur(keep.astype(np.float32), (0, 0), ZONE_SOFT / 2) > 0.5).astype(np.uint8)
    # centre the fade on the zone border (mostly outwards), so places right at the border stay visible
    r = int(EDGE_FADE * 0.6)
    inside = cv2.dilate(inside, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * r + 1, 2 * r + 1)))
    inside = (inside.astype(bool) & ~edge).astype(np.uint8)
    dist = cv2.distanceTransform(np.pad(inside, 1), cv2.DIST_L2, 5)[1:-1, 1:-1]
    zf = np.clip(dist / EDGE_FADE, 0, 1)
    zf = (zf * zf * (3 - 2 * zf)).astype(np.float32)
    zf[edge] = 0
    return zf


def block_layers(L, G, keep, inner, win):
    """White layers (alpha 0..255) of one block, computed on its window and cut to the inner part.
    fill (walkable area) and blocked (source of the hatch layer: mountains, water) at full resolution;
    lines (terrain, water, roads) and the dark shade under them per zoom level:
    {'fill': ..., 'blocked': ..., 512: {...}, 256: {...}, 128: {...}}.
    keep: chunk mask of the selected zones (whole mosaic); everything outside fades out."""
    wy, wx = px(win)
    H, W = wy.stop - wy.start, wx.stop - wx.start
    k = keep[win[2] * 16:win[3] * 16, win[0] * 16:win[1] * 16]
    zf = zone_fade(np.repeat(np.repeat(k, 32, 0), 32, 1), G['edge'][wy, wx])
    iy, ix = px(inner, P, win)
    walk, present = L['walk'][wy, wx], L['present'][wy, wx]
    out = dict(fill=(walk * 255 * zf)[iy, ix].astype(np.uint8),
               blocked=((present & ~walk) * 255 * zf)[iy, ix].astype(np.uint8))
    for s in LODS:
        f = s / P
        shape = (int(H * f), int(W * f))
        size = (shape[1], shape[0])
        lines = G['lines'][s]
        terrain, water, roads = (draw_lines(lines[n], s, win[0] * s, win[2] * s, shape)
                                 for n in ('terrain', 'water', 'roads'))
        terrain[cv2.resize(G['near_water'][wy, wx], size, interpolation=cv2.INTER_NEAREST) > 0] = 0
        z = zf if s == P else cv2.resize(zf, size, interpolation=cv2.INTER_AREA)
        layer = {}
        for n, a in (('terrain', terrain), ('water', water), ('roads', roads)):
            layer[n] = (a * z).astype(np.uint8)
        k = 7 if s == P else 3
        shade = cv2.dilate(np.maximum(np.maximum(layer['terrain'], layer['water']), layer['roads']), np.ones((k, k), np.uint8))
        layer['shade'] = (cv2.GaussianBlur(shade, (0, 0), 1.5 if s == P else 0.8).astype(np.float32) * 0.65).astype(np.uint8)
        sy, sx = px(inner, s, win)
        out[s] = {n: np.ascontiguousarray(a[sy, sx]) for n, a in layer.items()}
    return out


# --- output -----------------------------------------------------------------

def hatch_pattern(size):
    """Diagonal hatch lines, a whole number per tile, so the pattern is continuous across tiles."""
    sp = size / HATCH[size]
    y, x = np.mgrid[0:size, 0:size]
    t = (x + y + 0.5) % sp                                    # lines run bottom left -> top right
    d = np.minimum(t, sp - t) / np.sqrt(2)                    # distance to the nearest line in pixels
    return (np.clip(1.2 - d, 0, 1) * 255).astype(np.uint8)


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


def zone_weights(zgrid, c0, r0, n):
    """Soft per-pixel weights (P x P, summing to 1) of the zones 1..n for the tile at chunk offset (c0, r0)."""
    m = 3                                                      # chunk margin for the blur
    g = np.pad(zgrid, m, mode='edge')[r0:r0 + 16 + 2 * m, c0:c0 + 16 + 2 * m]
    w = []
    for z in range(1, n + 1):
        b = cv2.GaussianBlur((g == z).astype(np.float32), (0, 0), ZONE_FEATHER)
        b = cv2.resize(b, ((16 + 2 * m) * 32, (16 + 2 * m) * 32), interpolation=cv2.INTER_LINEAR)
        w.append(b[m * 32:(m + 16) * 32, m * 32:(m + 16) * 32])
    w = np.array(w)
    return w / np.maximum(w.sum(0), 1e-6)


ZONE_DIGITS = '123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'   # zone number -> one character


def write_block(out_dir, layers, inner, cols, rows, zgrid, n_zones, state):
    """Writes the tiles of one block to tiles/<map>/[lod/]<key>_<layer>.tga and records them in state.
    key = "<c>_<r>" for tiles inside one zone; tiles on a zone border are split into one part per zone,
    key = "<c>_<r>_z<zone>", each part weighted by its zone (soft transition, parts add up to the tile)."""
    written, tile_zone, chunk_zones = state
    for j in range(inner[2], inner[3]):
        for i in range(inner[0], inner[1]):
            c, r = cols[i], rows[j]
            g = zgrid[j * 16:(j + 1) * 16, i * 16:(i + 1) * 16]
            present = [int(z) for z in np.unique(g)]
            if len(present) == 1:
                parts = [(f'{c}_{r}', present[0], None)]
            else:
                w = zone_weights(zgrid, i * 16, j * 16, n_zones)
                parts = [(f'{c}_{r}_z{z}', z, w[z - 1]) for z in present]
                chunk_zones[f'{c}_{r}'] = ''.join(ZONE_DIGITS[int(z) - 1] for z in g.flatten())   # row by row, north first
            ti = (i, i + 1, j, j + 1)
            for key, z, wz in parts:
                have = ''
                for n in LAYERS:
                    area = n in ('fill', 'hatch')
                    src = layers['blocked' if n == 'hatch' else n] if area else layers[P][n]
                    blk = np.ascontiguousarray(src[px(ti, P, inner)])
                    if wz is not None:
                        blk = (blk * wz).astype(np.uint8)
                    if blk.max() < 8:
                        continue
                    have += n[0]
                    for s in FILE_LODS.get(n, LODS):
                        d = out_dir if s == P else os.path.join(out_dir, str(s))
                        if area:
                            img = downscale(blk, s, False)
                        else:                                  # lines: drawn at this zoom level
                            img = np.ascontiguousarray(layers[s][n][px(ti, s, inner)])
                            if wz is not None:
                                img = (img * cv2.resize(wz, (s, s), interpolation=cv2.INTER_AREA)).astype(np.uint8)
                        save_tga(img, os.path.join(d, f'{key}_{n}.tga'))
                if have:
                    written[key] = have
                    tile_zone[key] = z


def write_tiles_lua(path, map_id, zone_names, state):
    written, tile_zone, chunk_zones = state
    with open(path, 'w', newline='\n') as fh:
        fh.write(f'-- generated by scripts/build_raw.py: tiles of map {map_id} ("col_row" = layers present:\n')
        fh.write('-- f = fill, h = hatch, s = shade, t = terrain, w = water, r = roads).\n')
        fh.write('-- Tiles on a zone border are split into one part per zone: "col_row_z<zone>".\n')
        fh.write(f'RunewayTiles = RunewayTiles or {{}}\nRunewayTiles[{map_id}] = {{\n')
        for key, h in sorted(written.items()):
            fh.write(f'    ["{key}"] = "{h}",\n')
        fh.write('}\n')
        fh.write('-- Zones: names (index = zone number), zone per tile key, and per border tile the zone of each of its\n')
        fh.write(f'-- 16 x 16 chunks (row by row from north, columns from west; one character per chunk: {ZONE_DIGITS[:12]}...)\n')
        fh.write(f'RunewayZones = RunewayZones or {{}}\nRunewayZones[{map_id}] = {{\n    names = {{ ')
        fh.write(', '.join(f'"{n}"' for n in zone_names) + ' },\n    tile = {\n')
        for key, z in sorted(tile_zone.items()):
            fh.write(f'        ["{key}"] = {z},\n')
        fh.write('    },\n    chunks = {\n')
        for key, g in sorted(chunk_zones.items()):
            fh.write(f'        ["{key}"] = "{g}",\n')
        fh.write('    },\n}\n')


def write_pack_toc(map_id):
    """<pack>/<pack>.toc: load on demand, needs the core addon; X-Runeway-Maps tells the core which maps it holds.
    Interface and version follow Runeway/Runeway.toc."""
    pack, title = PACKS[map_id]
    core = open(os.path.join(ROOT, 'Runeway', 'Runeway.toc')).read()
    meta = lambda key: re.search(rf'^## {key}: (.+)$', core, re.M)[1].strip()
    with open(os.path.join(ROOT, pack, pack + '.toc'), 'w', newline='\n') as fh:
        fh.write(f'## Interface: {meta("Interface")}\n## Title: Runeway - {title}\n'
                 f'## Notes: Map data of Runeway ({title}), loaded when needed\n## Version: {meta("Version")}\n'
                 f'## Dependencies: Runeway\n## LoadOnDemand: 1\n## X-Runeway-Maps: {map_id}\n\n'
                 f'tiles\\{map_id}\\Tiles.lua\n')


# RGBA as the defaults in Core.lua (drawn in LAYERS order)
COLORS = dict(fill=(0, 0, 0, 0.10), hatch=(0.80, 0.84, 0.88, 0.20), shade=(0, 0, 0, 0.45),
              terrain=(0.82, 0.86, 0.89, 0.85), water=(0.82, 0.86, 0.89, 0.80), roads=(0.92, 0.72, 0.28, 0.65))


def compose(layers, base=None):
    """Tints the white layers like the addon does at runtime (BGR output). Hatch uses the 512 pattern."""
    H, W = layers['terrain'].shape
    out = np.full((H, W, 3), 30, np.float32) if base is None else base.astype(np.float32)
    pat = hatch_pattern(P).astype(np.float32) / 255
    hatch_full = np.tile(pat, (H // P, W // P)) * layers['blocked'].astype(np.float32)
    for n in LAYERS:
        a = (hatch_full if n == 'hatch' else layers[n].astype(np.float32))[..., None] / 255.0 * COLORS[n][3]
        out = out * (1 - a) + np.array(COLORS[n][2::-1], np.float32) * 255 * a
    return out.clip(0, 255).astype(np.uint8)


def minimap(name, cols, rows):
    img = np.zeros((len(rows) * P, len(cols) * P, 3), np.uint8)
    for f in glob.glob(os.path.join(MAPS, name, 'minimap', 'map*.png')):
        c, r = map(int, re.findall(r'map(\d+)_(\d+)', f)[0])
        if c in cols and r in rows:
            t = cv2.imread(f)
            if t.shape[0] != P:
                t = cv2.resize(t, (P, P), interpolation=cv2.INTER_AREA)
            img[(r - rows[0]) * P:(r - rows[0] + 1) * P, (c - cols[0]) * P:(c - cols[0] + 1) * P] = t
    return img


def main(map_id, zone_names):
    name = MAP_NAMES[map_id]
    if not os.path.exists(LISTFILE):
        print('downloading listfile ...')
        urllib.request.urlretrieve(LISTFILE_URL, LISTFILE)
    top, names, seas = zone_of_area(map_id)
    zones = set()
    for n in zone_names:
        if n.lower() not in names:
            sys.exit(f'unknown zone on map {map_id}: {n}')
        zones.add(names[n.lower()])
    if len(zone_names) > len(ZONE_DIGITS):
        sys.exit(f'at most {len(ZONE_DIGITS)} zones per map')
    idx = area_index(map_id)
    zone_of = np.vectorize(lambda x: top.get(int(x), int(x)))
    land = lambda a: np.isin(zone_of(a), list(zones)) & ~np.isin(a, list(seas))
    tiles = {k for k, a in idx.items() if land(a).any()}
    if not tiles:
        sys.exit('no tiles found for ' + ', '.join(zone_names))
    # mosaic with one tile margin for clean borders
    cols = list(range(min(c for c, _ in tiles) - 1, max(c for c, _ in tiles) + 2))
    rows = list(range(min(r for _, r in tiles) - 1, max(r for _, r in tiles) + 2))
    print(f'map {map_id}: {len(tiles)} tiles, mosaic cols {cols[0]}-{cols[-1]} rows {rows[0]}-{rows[-1]}', flush=True)

    # zone number (1..n, order of zone_names) per chunk; chunks outside the built zones (sea, fade area)
    # belong to the nearest built zone
    order = [names[n.lower()] for n in zone_names]
    zgrid = np.zeros((len(rows) * 16, len(cols) * 16), np.uint8)
    for (c, r), a in idx.items():
        if c in cols and r in rows:
            za = zone_of(a)
            for i, z in enumerate(order):
                zgrid[(r - rows[0]) * 16:(r - rows[0] + 1) * 16,
                      (c - cols[0]) * 16:(c - cols[0] + 1) * 16][(za == z) & ~np.isin(a, list(seas))] = i + 1
    _, lab = cv2.distanceTransformWithLabels((zgrid == 0).astype(np.uint8), cv2.DIST_L2, 5,
                                             labelType=cv2.DIST_LABEL_PIXEL)
    ys, xs = np.nonzero(zgrid)
    nearest = np.zeros(lab.max() + 1, np.uint8)
    nearest[lab[ys, xs]] = zgrid[ys, xs]
    zgrid = nearest[lab]

    L = masks(raw_masks(name, cols, rows))
    print('masks done', flush=True)
    # zone mask per chunk: zone land, plus sea chunks next to it (the coast belongs to the zone). Open water
    # chunks of a zone (no dry ground, connected to the mosaic border) count as sea, so the zone's ocean is
    # kept only near its coast; enclosed lakes stay.
    d = (L['present'] & ~L['water']).view(np.uint8)
    d *= 255
    dry = cv2.resize(d, (len(cols) * 16, len(rows) * 16), interpolation=cv2.INTER_AREA) > 5   # > 2 % dry
    del d
    keep = np.zeros((len(rows) * 16, len(cols) * 16), bool)
    sea = np.zeros_like(keep)
    for (c, r), a in idx.items():
        if c in cols and r in rows:
            ys = slice((r - rows[0]) * 16, (r - rows[0] + 1) * 16)
            xs = slice((c - cols[0]) * 16, (c - cols[0] + 1) * 16)
            keep[ys, xs] = land(a)
            sea[ys, xs] = np.isin(a, list(seas))
    _, lab = cv2.connectedComponents(np.pad(u8(~(keep & dry)), 1, constant_values=1), connectivity=4)
    ocean = keep & ~dry & (lab[1:-1, 1:-1] == lab[0, 0])
    sea |= ocean
    keep &= ~ocean
    keep |= sea & (cv2.dilate(keep.astype(np.uint8), np.ones((5, 5), np.uint8)) > 0)
    G = map_lines(L)
    print('lines done', flush=True)

    pack = PACKS[map_id][0]
    out_dir = os.path.join(ROOT, pack, 'tiles', str(map_id))
    shutil.rmtree(out_dir, ignore_errors=True)
    for s in LODS:
        os.makedirs(out_dir if s == P else os.path.join(out_dir, str(s)), exist_ok=True)
    for s in LODS:
        save_tga(hatch_pattern(s), os.path.join(MEDIA, f'hatch{s}.tga'))
    # previews at half resolution; every mosaic tile with content is written (the fade reaches a bit into
    # neighbouring tiles)
    pv = np.zeros((len(rows) * P // 2, len(cols) * P // 2, 3), np.uint8)
    pm = np.zeros_like(pv)
    half = lambda a: cv2.resize(a, (a.shape[1] // 2, a.shape[0] // 2), interpolation=cv2.INTER_AREA)
    state = ({}, {}, {})
    for inner, win in blocks(len(cols), len(rows)):
        layers = block_layers(L, G, keep, inner, win)
        write_block(out_dir, layers, inner, cols, rows, zgrid, len(zone_names), state)
        flat = dict(layers[P], fill=layers['fill'], blocked=layers['blocked'])
        dst = px(inner, P // 2)
        pv[dst] = half(compose(flat))
        pm[dst] = half(compose(flat, (minimap(name, cols[inner[0]:inner[1]], rows[inner[2]:inner[3]]) * 0.45).astype(np.uint8)))
    write_tiles_lua(os.path.join(out_dir, 'Tiles.lua'), map_id, zone_names, state)
    write_pack_toc(map_id)
    os.makedirs(BUILD, exist_ok=True)
    cv2.imwrite(os.path.join(BUILD, 'preview_lines.png'), pv)
    cv2.imwrite(os.path.join(BUILD, 'preview_over_minimap.png'), pm)
    size = sum(os.path.getsize(os.path.join(d, f)) for d, _, fs in os.walk(out_dir) for f in fs)
    print(f'{len(state[0])} tiles written, {size / 1e6:.1f} MB, previews in build/')


if __name__ == '__main__':
    args = sys.argv[1:]
    map_id = 0
    if args[:1] == ['--map']:
        map_id, args = int(args[1]), args[2:]
    zl = args or [l.strip() for l in open(os.path.join(os.path.dirname(__file__), f'zones_{map_id}.txt'))
                  if l.strip() and not l.startswith('#')]
    main(map_id, zl)
