# Minimal ADT reader (split files, modern format): heights (MCVT), water (MH2O),
# ground texture layers (MCLY/MCAL in _tex0), area IDs. World axes: north = X, west = Y.
import struct
import numpy as np

T = 1600 / 3            # tile edge in yards
C = T / 16              # chunk edge
U = C / 8               # vertex spacing (outer grid)


def chunks(buf, start=0, end=None):
    end = len(buf) if end is None else end
    o = start
    while o + 8 <= end:
        tag = buf[o:o + 4][::-1].decode('latin1')
        n = struct.unpack_from('<I', buf, o + 4)[0]
        yield tag, o + 8, n
        o += 8 + n


def read_root(path):
    """Returns heights (129x129 outer grid, absolute Z), inner (128x128),
    holes (128x128 bool, per cell), area (16x16), water instances, tile origin (north, west)."""
    b = open(path, 'rb').read()
    outer = np.zeros((129, 129), np.float32)
    inner = np.zeros((128, 128), np.float32)
    holes = np.zeros((128, 128), bool)
    area = np.zeros((16, 16), np.int32)
    origin = None
    mh2o = None
    for tag, o, n in chunks(b):
        if tag == 'MH2O':
            mh2o = (o, n)
        elif tag == 'MCNK':
            flags, ix, iy = struct.unpack_from('<3I', b, o)
            area[iy, ix] = struct.unpack_from('<I', b, o + 0x34)[0]
            px, py, pz = struct.unpack_from('<3f', b, o + 0x68)
            if ix == 0 and iy == 0:
                origin = (px, py)
            if flags & 0x10000:          # high-res holes: 8x8 bits
                hb = b[o + 0x14:o + 0x1C]
                for r in range(8):
                    for c in range(8):
                        if hb[r] >> c & 1:
                            holes[iy * 8 + r, ix * 8 + c] = True
            else:                        # low-res holes: 4x4 bits, each 2x2 cells
                h = struct.unpack_from('<H', b, o + 0x3C)[0]
                for i in range(16):
                    if h >> i & 1:
                        r, c = i // 4, i % 4
                        holes[iy * 8 + r * 2:iy * 8 + r * 2 + 2, ix * 8 + c * 2:ix * 8 + c * 2 + 2] = True
            for st, so, sn in chunks(b, o + 128, o + n):
                if st == 'MCVT':
                    v = np.frombuffer(b, '<f4', 145, so) + pz
                    rows = [v[i * 17:i * 17 + 9] for i in range(9)]
                    mids = [v[i * 17 + 9:i * 17 + 17] for i in range(8)]
                    outer[iy * 8:iy * 8 + 9, ix * 8:ix * 8 + 9] = np.array(rows)
                    inner[iy * 8:iy * 8 + 8, ix * 8:ix * 8 + 8] = np.array(mids)
    water = read_mh2o(b, *mh2o) if mh2o else []
    return dict(outer=outer, inner=inner, holes=holes, area=area, water=water, origin=origin)


def read_mh2o(b, base, n):
    """List of (liquid_type, cell-level height 9x9 grid per chunk placed in 128x128 tile cells).
    Returns list of dicts: type, mask (128x128 bool per cell), height (129x129 vertex heights, nan outside)."""
    out = {}
    for ci in range(256):
        ofs_inst, count, _ = struct.unpack_from('<3I', b, base + ci * 12)
        iy, ix = divmod(ci, 16)
        for k in range(count):
            io = base + ofs_inst + k * 24
            ltype, lvf, hmin, hmax, xo, yo, w, h, ofs_ex, ofs_v = struct.unpack_from('<HHffBBBBII', b, io)
            if ltype not in out:
                out[ltype] = dict(mask=np.zeros((128, 128), bool), height=np.full((129, 129), np.nan, np.float32))
            m, hv = out[ltype]['mask'], out[ltype]['height']
            if ofs_ex:
                bits = int.from_bytes(b[base + ofs_ex:base + ofs_ex + (w * h + 7) // 8], 'little')
            else:
                bits = (1 << (w * h)) - 1
            heights = None
            if ofs_v and lvf in (0, 1, 3) and lvf < 42:
                heights = np.frombuffer(b, '<f4', (w + 1) * (h + 1), base + ofs_v).reshape(h + 1, w + 1)
            for r in range(h):
                for c in range(w):
                    if bits >> (r * w + c) & 1:
                        m[iy * 8 + yo + r, ix * 8 + xo + c] = True
            r0, c0 = iy * 8 + yo, ix * 8 + xo
            hv[r0:r0 + h + 1, c0:c0 + w + 1] = heights if heights is not None else hmax
    return [dict(type=t, **d) for t, d in out.items()]


def read_tex0(path):
    """Returns fdids (list of texture file IDs) and per chunk a list of (texture index, alpha 64x64 float or None)."""
    b = open(path, 'rb').read()
    fdids, layers = [], []
    for tag, o, n in chunks(b):
        if tag == 'MDID':
            fdids = list(struct.unpack_from(f'<{n // 4}I', b, o))
        elif tag == 'MCNK':
            mcly, mcal = None, None
            for st, so, sn in chunks(b, o, o + n):
                if st == 'MCLY':
                    mcly = [struct.unpack_from('<4I', b, so + i * 16) for i in range(sn // 16)]
                elif st == 'MCAL':
                    mcal = (so, sn)
            lst = []
            for tex, flags, ofs, _ in mcly or []:
                a = None
                if flags & 0x100 and mcal:
                    a = decode_alpha(b, mcal[0] + ofs, flags & 0x200)
                lst.append((tex, a))
            layers.append(lst)
    return fdids, layers


def decode_alpha(b, o, compressed):
    """8-bit 64x64 alpha map (big alpha), RLE compressed or raw."""
    if not compressed:
        return np.frombuffer(b, np.uint8, 4096, o).reshape(64, 64) / 255.0
    out = np.zeros(4096, np.uint8)
    i = 0
    while i < 4096:
        hdr = b[o]; o += 1
        cnt = hdr & 0x7F
        if hdr & 0x80:                   # fill
            out[i:i + cnt] = b[o]; o += 1
        else:                            # copy
            out[i:i + cnt] = np.frombuffer(b, np.uint8, cnt, o); o += cnt
        i += cnt
    return out[:4096].reshape(64, 64) / 255.0


def layer_weights(layers):
    """Per chunk: dict texture index -> 64x64 weight (layer 0 = 1 - sum of others)."""
    res = []
    for lst in layers:
        w = {}
        rest = np.zeros((64, 64))
        for tex, a in lst[1:]:
            a = a if a is not None else np.zeros((64, 64))
            w[tex] = w.get(tex, 0) + a
            rest += a
        if lst:
            w[lst[0][0]] = w.get(lst[0][0], 0) + np.clip(1 - rest, 0, 1)
        res.append(w)
    return res


def read_area(path):
    """Area IDs (16x16 chunks) only; fast scan of a root ADT."""
    b = open(path, 'rb').read()
    area = np.zeros((16, 16), np.int32)
    for tag, o, n in chunks(b):
        if tag == 'MCNK':
            ix, iy = struct.unpack_from('<2I', b, o + 4)
            area[iy, ix] = struct.unpack_from('<I', b, o + 0x34)[0]
    return area
