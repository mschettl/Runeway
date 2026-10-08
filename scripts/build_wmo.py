# Builds the tile set of a city interior from its WMO export (floor plan seen from above), e.g. Undercity
# below Tirisfal. Same tile grid, layers and file format as build_raw.py; the set goes into the data pack of
# its map as tiles/<map>-<uiMap>/ and the addon shows it while the player is on that uiMap (outside the
# surface subzones listed in its `surface` entry).
#   python scripts/build_wmo.py [set ...]      default: all sets in SETS
# Walkable = the largest connected network of upward floor faces of the indoor groups, seen from above (highest
# floor per pixel); water = WMO liquid where it lies above that floor (canals; bridges stay walkable).
import os
import sys
import csv
import glob
import json
import shutil
import numpy as np
import cv2
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
import build_raw as B
import structures
from raw_mosaic import MAPS

T = structures.T
P = B.P
EXPORT = os.path.join(MAPS, '..')
# set -> map ID, WMO export (without extension), group descriptions left out (surface parts), surface areas
# (AreaTable IDs: in these subzones the addon keeps the surface map), zone name
SETS = {
    '0-1458': dict(map=0, wmo='world/wmo/autogen-names/undercity/20736', skip=('Ruins of Lordaeron',),
                   surface=(153,), name='Undercity'),
}
FLOOR_UP = 0.75            # |normal z| above this (upward): floor (~41 deg)
INDOOR = 0x2000            # WMO group flag: indoor
LIQUID_UNIT = 25 / 6       # yd per WMO liquid tile
STEP = 1.2                 # yd; neighbouring floor pixels closer in height than this are connected (stairs)
MIN_GAP = 30               # px; smaller holes in the floor are closed
ENVELOPE = 96              # px around the floor plan that belong to the set (hatch, then fade out)


def placement(wmo):
    """ModelPlacementInformation row of the WMO (first ADT that places it)."""
    name = os.path.basename(wmo) + '.wmo'
    for f in sorted(glob.glob(os.path.join(MAPS, '*', 'adt_*_ModelPlacementInformation.csv'))):
        for row in csv.DictReader(open(f, encoding='utf8'), delimiter=';'):
            if row['Type'] == 'wmo' and row['ModelFile'].replace('\\', '/').endswith('/' + name):
                return row
    raise SystemExit(f'no placement of {name} found')


def load_groups(wmo, skip):
    """Floor triangles (n, 3, 3) and liquid squares (n, 4, 3) of the indoor groups, model space (x, y, z up)."""
    d = json.load(open(os.path.join(EXPORT, wmo + '.json'), encoding='utf8'))
    floors, liquid = [], []
    for g in d['groups']:
        if not g['flags'] & INDOOR or g.get('groupDescription') in skip:
            continue
        path = os.path.join(EXPORT, f"{wmo}_{g['groupName']}.obj")
        if os.path.exists(path):
            v, faces = [], []
            for line in open(path):
                if line.startswith('v '):
                    x, y, z = map(float, line.split()[1:4])
                    v.append((x, -z, y))                   # wow.export OBJ is y-up: (x, z, -y)
                elif line.startswith('f '):
                    faces.append([int(p.split('/')[0]) - 1 for p in line.split()[1:4]])
            if faces:
                t = np.array(v)[np.array(faces)]
                n = np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0])
                up = n[:, 2] / (np.linalg.norm(n, axis=1) + 1e-9)
                floors.append(t[up > FLOOR_UP])
        lq = g.get('liquid')
        if lq and lq.get('tiles'):
            x0, y0, z0 = lq['corner']
            for k, f in enumerate(lq['tiles']):
                if f & 0xF == 0xF:                          # no liquid on this square
                    continue
                i, j = k % lq['tileX'], k // lq['tileX']
                x, y = x0 + i * LIQUID_UNIT, y0 + j * LIQUID_UNIT
                u = LIQUID_UNIT
                liquid.append([(x, y, z0), (x + u, y, z0), (x + u, y + u, z0), (x, y + u, z0)])
    return np.concatenate(floors), np.array(liquid, float).reshape(-1, 4, 3)


def reachable_top(faces, to_px, H, W):
    """Height raster (NaN = none) of the highest walkable floor per pixel. Floors are sampled per pixel on all
    levels; pixels next to each other with less than STEP height difference are connected (floors, ramps,
    stairs). The largest network is the walkable city; the rest are tops of walls, arches and roof beams."""
    ys, xs, zs = [], [], []
    for poly, t in zip(to_px(faces), faces):
        x0, y0 = poly.min(0) // 4
        x1, y1 = poly.max(0) // 4 + 2
        m = np.zeros((y1 - y0, x1 - x0), np.uint8)
        cv2.fillConvexPoly(m, poly - np.array([x0, y0]) * 4, 1, cv2.LINE_8, shift=2)
        py, px_ = np.nonzero(m)
        if not len(py):
            continue
        # height on the face plane at the pixel centres
        q = poly / 4.0
        a = np.c_[q, np.ones(3)]
        coef = np.linalg.lstsq(a, t[:, 2], rcond=None)[0]
        ys.append(py + y0)
        xs.append(px_ + x0)
        zs.append(coef[0] * (px_ + x0 + 0.5) + coef[1] * (py + y0 + 0.5) + coef[2])
    y, x, z = np.concatenate(ys), np.concatenate(xs), np.concatenate(zs)
    ok = (y >= 0) & (y < H) & (x >= 0) & (x < W)
    key = (y[ok] * W + x[ok]).astype(np.int64)
    zq = np.round(z[ok] / 0.5).astype(np.int64)                # one node per pixel and 0.5 yd of height
    nodes = np.unique(np.stack([key, zq], 1), axis=0)
    key, z = nodes[:, 0], nodes[:, 1] * 0.5
    pix, start, count = np.unique(key, return_index=True, return_counts=True)
    edges = []
    for off in (1, W, W + 1, W - 1):                            # right, down and both diagonals
        i = np.searchsorted(pix, key + off)
        hit = (i < len(pix)) & (pix[np.minimum(i, len(pix) - 1)] == key + off)
        src, s0, c = np.nonzero(hit)[0], start[i[hit]], count[i[hit]]
        for k in range(c.max() if len(c) else 0):
            sel = c > k
            j = s0[sel] + k
            close = np.abs(z[src[sel]] - z[j]) < STEP
            edges.append(np.stack([src[sel][close], j[close]]))
    e = np.concatenate(edges, 1)
    n = len(nodes)
    _, lab = connected_components(coo_matrix((np.ones(e.shape[1]), (e[0], e[1])), shape=(n, n)), directed=False)
    size = np.bincount(lab)
    keep = lab == np.argmax(size)
    out = np.full(H * W, -np.inf, np.float32)
    np.maximum.at(out, key[keep], z[keep])
    out[np.isinf(out)] = np.nan
    print(f'  floor nodes {n}, {len(size)} networks, walkable network {size.max()} px', flush=True)
    return out.reshape(H, W)


def build(set_id, cfg):
    row = placement(cfg['wmo'])
    xf = structures.world_xform(row)
    floors, liquid = load_groups(cfg['wmo'], cfg['skip'])
    fw = xf(floors.reshape(-1, 3)).reshape(-1, 3, 3)
    lw = xf(liquid.reshape(-1, 3)).reshape(-1, 4, 3) if len(liquid) else liquid
    allp = fw.reshape(-1, 3)
    # tile grid: every tile the floor plan touches plus one tile around it
    c0, c1 = int(32 - allp[:, 1].max() / T) - 1, int(32 - allp[:, 1].min() / T) + 1
    r0, r1 = int(32 - allp[:, 0].max() / T) - 1, int(32 - allp[:, 0].min() / T) + 1
    cols, rows = list(range(c0, c1 + 1)), list(range(r0, r1 + 1))
    H, W = len(rows) * P, len(cols) * P
    print(f'{set_id}: {len(fw)} floor faces, {len(lw)} liquid squares, cols {c0}-{c1} rows {r0}-{r1}', flush=True)

    def to_px(t):                                           # world (north, west) -> mosaic pixels, 1/4 px
        x = ((32 - t[..., 1] / T) - c0) * P
        y = ((32 - t[..., 0] / T) - r0) * P
        return np.round(np.stack([x, y], -1) * 4).astype(np.int32)

    def top(polys, heights):
        """Height raster of the highest face per pixel (faces drawn from low to high), NaN where none."""
        out = np.full((H, W), np.nan, np.float32)
        order = np.argsort(heights)
        for poly, h in zip(to_px(polys)[order], heights[order]):
            cv2.fillConvexPoly(out, poly, float(h), cv2.LINE_8, shift=2)
        return out

    floor = reachable_top(fw, to_px, H, W)
    level = top(lw, lw[..., 2].mean(1)) if len(lw) else np.full((H, W), np.nan, np.float32)
    with np.errstate(invalid='ignore'):
        # water where the liquid surface is the top: canal floors below it; bridges and walkways above stay
        water = ~np.isnan(level) & ~(floor > level + 1)
    water = B.smooth(water, 1.5)
    walk = ~np.isnan(floor)
    walk = ~B.blobs(~walk, MIN_GAP) & ~water                 # close small gaps
    walk = B.smooth(walk, 1.0)
    print(f'  walkable {walk.sum()} px, water {water.sum()} px', flush=True)
    present = np.ones((H, W), bool)
    L = dict(walk=walk, water=water, road=np.zeros((H, W), bool), present=present)
    G = B.map_lines(L)
    # chunks of the set: around the floor plan; the fade (EDGE_FADE) runs outwards from there
    env = cv2.dilate(B.u8(walk | water), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * ENVELOPE + 1,) * 2))
    keep = cv2.resize(env, (len(cols) * 16, len(rows) * 16), interpolation=cv2.INTER_AREA) > 0

    pack = B.PACKS[cfg['map']][0]
    out_dir = os.path.join(B.ROOT, pack, 'tiles', set_id)
    shutil.rmtree(out_dir, ignore_errors=True)
    for s in B.LODS:
        os.makedirs(out_dir if s == P else os.path.join(out_dir, str(s)), exist_ok=True)
    zgrid = np.ones((len(rows) * 16, len(cols) * 16), np.uint8)
    state = ({}, {}, {})
    pv = np.zeros((H // 2, W // 2, 3), np.uint8)
    half = lambda a: cv2.resize(a, (a.shape[1] // 2, a.shape[0] // 2), interpolation=cv2.INTER_AREA)
    for inner, win in B.blocks(len(cols), len(rows)):
        layers = B.block_layers(L, G, keep, inner, win)
        B.write_block(out_dir, layers, inner, cols, rows, zgrid, 1, state)
        pv[B.px(inner, P // 2)] = half(B.compose(dict(layers[P], fill=layers['fill'], blocked=layers['blocked'])))
    lua = os.path.join(out_dir, 'Tiles.lua')
    B.write_tiles_lua(lua, f'"{set_id}"', [cfg['name']], state)
    with open(lua, 'a', newline='\n') as fh:
        fh.write('-- Surface subzones (AreaTable IDs): there the addon keeps the map\'s own (surface) tiles\n')
        fh.write(f'RunewayZones["{set_id}"].surface = {{ {", ".join(map(str, cfg["surface"]))} }}\n')
    B.write_pack_toc(cfg['map'])
    cv2.imwrite(os.path.join(B.BUILD, f'preview_{set_id}.png'), pv)
    size = sum(os.path.getsize(os.path.join(d, f)) for d, _, fs in os.walk(out_dir) for f in fs)
    print(f'{len(state[0])} tiles written, {size / 1e6:.1f} MB, preview build/preview_{set_id}.png')


if __name__ == '__main__':
    for sid in sys.argv[1:] or SETS:
        build(sid, SETS[sid])
