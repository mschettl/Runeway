# Buildings on the surface: walls of placed WMOs (from their OBJ export) and selected M2 doodads
# (towers) become "not walkable" in the terrain mask. Placements come from wow.export's
# adt_<c>_<r>_ModelPlacementInformation.csv; only models whose export is present are used.
import os
import csv
import glob
import math
import struct
from functools import lru_cache
import numpy as np
import cv2

T = 1600 / 3
ORIGIN = 32 * T                                     # placement position -> world: north = ORIGIN - z, west = ORIGIN - x
WALL_BAND = (0.5, 2.5)                              # yd above the terrain: a steep face crossing this band blocks
STEEP = 0.35                                        # |normal z| below this: wall
M2_BLOCKERS = ('undercitytower',)                   # M2 doodads that block (name fragments); trees etc. stay walkable
USED = {}                                           # placements used so far: ModelId -> description (build log)


def placements(src, cols, rows):
    seen, out = set(), []
    for c in cols:
        for r in rows:
            p = os.path.join(src, f'adt_{c}_{r}_ModelPlacementInformation.csv')
            if not os.path.exists(p):
                continue
            for row in csv.DictReader(open(p, encoding='utf8'), delimiter=';'):
                key = row['ModelId']                 # unique per placement, repeated in every ADT it touches
                if key in seen:
                    continue
                seen.add(key)
                out.append(row)
    return out


def model_path(src, row):
    return os.path.normpath(os.path.join(src, row['ModelFile'].replace('\\', '/')))   # paths start with ..\..\world


def world_xform(row):
    """Model space (x, y, z up) -> world (north, west, height). Calibrated on Undercity (rotation y = 179.5):
    model x -> north, model y -> west. Heading = rotation y - 180 (sign verified only near 0)."""
    px, py, pz = float(row['PositionX']), float(row['PositionY']), float(row['PositionZ'])
    phi = math.radians(float(row['RotationY']) - 180)
    s = float(row['ScaleFactor'] or 1)
    cn, cw, ch = ORIGIN - pz, ORIGIN - px, py
    ca, sa = math.cos(phi), math.sin(phi)

    def f(v):
        x, y, z = v[:, 0] * s, v[:, 1] * s, v[:, 2] * s
        return np.stack([cn + ca * x - sa * y, cw + sa * x + ca * y, ch + z], -1)
    return f


@lru_cache(maxsize=8)
def load_obj_groups(wmo_file):
    """Triangles (n, 3, 3) of all exported OBJ groups of a WMO, in model space (x, y, z up)."""
    stem = os.path.splitext(wmo_file)[0]
    tris = []
    for f in glob.glob(glob.escape(stem) + '_*.obj'):
        v, faces = [], []
        for line in open(f):
            if line.startswith('v '):
                x, y, z = map(float, line.split()[1:4])
                v.append((x, -z, y))                 # wow.export OBJ is y-up: (x, z, -y)
            elif line.startswith('f '):
                faces.append([int(p.split('/')[0]) - 1 for p in line.split()[1:4]])
        if faces:
            tris.append(np.array(v)[np.array(faces)])
    return np.concatenate(tris) if tris else None


def m2_radius(m2_file):
    """Footprint radius from the M2 bounding box."""
    b = open(m2_file, 'rb').read()
    o = 8 if b[:4] == b'MD21' else 0
    x0, y0, _, x1, y1, _ = struct.unpack_from('<6f', b, o + 0xA0)
    return (abs(x0) + abs(x1) + abs(y0) + abs(y1)) / 4


def blocked(m):
    """Mask (mosaic pixels) of building walls and tower footprints for Mosaic m (needs m.height)."""
    P = m.P
    out = np.zeros((m.H, m.W), np.uint8)

    def to_px(n, w):
        return ((32 - w / T) - m.cols[0]) * P, ((32 - n / T) - m.rows[0]) * P

    def ground(x, y):
        xi = np.clip(x.astype(int), 0, m.W - 1)
        yi = np.clip(y.astype(int), 0, m.H - 1)
        return m.height[yi, xi]

    for row in placements(m.src, m.cols, m.rows):
        path = model_path(m.src, row)
        if row['Type'] == 'wmo':
            tris = load_obj_groups(path)
            if tris is None:
                continue
            t = world_xform(row)(tris.reshape(-1, 3)).reshape(-1, 3, 3)
            nrm = np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0])
            steep = np.abs(nrm[:, 2]) / (np.linalg.norm(nrm, axis=1) + 1e-9) < STEEP
            x, y = to_px(t[..., 0], t[..., 1])
            h = ground(x.mean(1), y.mean(1))
            zlo, zhi = t[..., 2].min(1) - h, t[..., 2].max(1) - h
            wall = steep & (zlo < WALL_BAND[1]) & (zhi > WALL_BAND[0])
            pts = np.stack([x[wall], y[wall]], -1)
            cv2.polylines(out, list(np.round(pts * 4).astype(np.int32)), True, 255, 2, cv2.LINE_8, shift=2)
            USED[row['ModelId']] = f'{os.path.basename(path)}: {wall.sum()} wall faces'
        elif row['Type'] == 'm2' and any(k in path.lower() for k in M2_BLOCKERS) and os.path.exists(path):
            r = m2_radius(path) * float(row['ScaleFactor'] or 1) * P / T
            x, y = to_px(ORIGIN - float(row['PositionZ']), ORIGIN - float(row['PositionX']))
            cv2.circle(out, (int(round(x)), int(round(y))), max(1, int(round(r))), 255, -1)
            USED[row['ModelId']] = os.path.basename(path)
    return out > 0
