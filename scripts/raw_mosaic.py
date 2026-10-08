# Assembles ADT data of a tile range into world-aligned rasters (row = north->south, col = west->east).
import os
import numpy as np
import cv2
from adt import read_root, read_tex0, layer_weights, U

SRC = os.path.join(os.path.dirname(__file__), '..', 'Wow export files', 'maps', 'azeroth')
LISTFILE = os.environ.get('RUNEWAY_LISTFILE', os.path.join(os.path.dirname(__file__), '..', 'listfile.csv'))


def load_listfile(path=LISTFILE):
    lf = {}
    for line in open(path, encoding='utf8', errors='replace'):
        i, _, p = line.rstrip('\n').partition(';')
        if p.startswith('tileset/'):
            lf[int(i)] = p.split('/')[-1].replace('_s.blp', '')
    return lf


class Mosaic:
    """Tile range c0..c1 / r0..r1 at P pixels per tile (P = 512 -> ~1.04 yd/px)."""

    def __init__(self, cols, rows, P=512, src=SRC):
        self.cols, self.rows, self.P, self.src = list(cols), list(rows), P, src
        self.H, self.W = len(self.rows) * P, len(self.cols) * P
        self.present = np.zeros((self.H, self.W), bool)

    def tiles(self):
        for j, r in enumerate(self.rows):
            for i, c in enumerate(self.cols):
                p = os.path.join(self.src, f'azeroth_{c}_{r}.adt')
                if os.path.exists(p):
                    yield i, j, c, r, p

    def blk(self, i, j):
        P = self.P
        return slice(j * P, (j + 1) * P), slice(i * P, (i + 1) * P)

    def build_terrain(self):
        """Height (exact triangle mesh sampled on 2x grid, then bilinear), holes, water, area."""
        P = self.P
        self.height = np.zeros((self.H, self.W), np.float32)
        self.holes = np.zeros((self.H, self.W), bool)
        self.water = np.zeros((self.H, self.W), bool)
        self.area = np.zeros((self.H, self.W), np.int32)
        for i, j, c, r, p in self.tiles():
            d = read_root(p)
            g = mesh_grid(d['outer'], d['inner'])                 # 257x257, spacing U/2
            h = sample(g, P)
            ys, xs = self.blk(i, j)
            self.height[ys, xs] = h
            self.present[ys, xs] = True
            self.holes[ys, xs] = cv2.resize(d['holes'].astype(np.uint8), (P, P), interpolation=cv2.INTER_NEAREST) > 0
            self.area[ys, xs] = cv2.resize(d['area'], (P, P), interpolation=cv2.INTER_NEAREST)
            wm = np.zeros((P, P), bool)
            for w in d['water']:
                if w['type'] in (3, 4):                           # magma, slime: skip for now
                    continue
                m = cv2.resize(w['mask'].astype(np.uint8), (P, P), interpolation=cv2.INTER_NEAREST) > 0
                wh = w['height'].copy()
                wh[np.isnan(wh)] = np.nanmax(wh) if np.isfinite(wh).any() else -1e9
                wh = sample(wh, P)
                wm |= m & (wh > h)
            self.water[ys, xs] = wm

    def build_textures(self, lf, names):
        """Summed weight raster (0..1) of the textures in `names` (P/16 px per chunk)."""
        P, q = self.P, self.P // 16
        names = set(names)
        out = np.zeros((self.H, self.W), np.float32)
        for i, j, c, r, p in self.tiles():
            fd, layers = read_tex0(p.replace('.adt', '_tex0.adt'))
            y0, x0 = j * P, i * P
            for k, w in enumerate(layer_weights(layers)):
                cy, cx = divmod(k, 16)
                for t, a in w.items():
                    n = lf.get(fd[t], str(fd[t]))
                    if n in names:
                        a = cv2.resize(np.asarray(a, np.float32), (q, q), interpolation=cv2.INTER_AREA if q < 64 else cv2.INTER_LINEAR)
                        out[y0 + cy * q:y0 + (cy + 1) * q, x0 + cx * q:x0 + (cx + 1) * q] += a
        return out

    def slope_deg(self):
        yd = (16 * 33.3333333) / self.P                            # yards per pixel
        gy, gx = np.gradient(self.height, yd)
        return np.degrees(np.arctan(np.hypot(gx, gy)))


def mesh_grid(outer, inner):
    """Exact terrain mesh on a 257x257 grid: outer vertices, cell centres, edge midpoints."""
    g = np.zeros((257, 257), np.float32)
    g[0::2, 0::2] = outer
    g[1::2, 1::2] = inner
    g[0::2, 1::2] = (outer[:, :-1] + outer[:, 1:]) / 2
    g[1::2, 0::2] = (outer[:-1, :] + outer[1:, :]) / 2
    return g


def sample(g, P):
    """Bilinear resample of an (n+1)x(n+1) vertex grid to P x P pixel centres."""
    n = g.shape[0] - 1
    t = (np.arange(P) + 0.5) * n / P
    i0 = np.clip(np.floor(t).astype(int), 0, n - 1)
    f = (t - i0).astype(np.float32)
    a = g[i0][:, i0] * (1 - f)[None, :] + g[i0][:, i0 + 1] * f[None, :]
    b = g[i0 + 1][:, i0] * (1 - f)[None, :] + g[i0 + 1][:, i0 + 1] * f[None, :]
    return a * (1 - f)[:, None] + b * f[:, None]
