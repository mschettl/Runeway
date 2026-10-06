# Erzeugt pro ADT-Kachel ein 512x512 TGA mit Konturen (lila), Wasser (blau), Wegen (beige)
import cv2, numpy as np, glob, re, os
from PIL import Image
from skimage.morphology import skeletonize
from roads import road_mask, prune, keep_long

SRC = '/mnt/user-data/uploads/maps/azeroth/minimap'
OUT = 'Runeway/tiles/0'          # 0 = Instanz-ID der Oestlichen Koenigreiche
S = 512

tiles = {}
for f in glob.glob(SRC + '/*.png'):
    c, r = map(int, re.findall(r'map(\d+)_(\d+)', f)[0])
    tiles[(c, r)] = f
cs = sorted({k[0] for k in tiles}); rs = sorted({k[1] for k in tiles})
c0, r0 = cs[0], rs[0]
full = np.zeros(((rs[-1] - r0 + 1) * S, (cs[-1] - c0 + 1) * S, 3), np.uint8)
present = np.zeros(full.shape[:2], bool)
for (c, r), f in tiles.items():
    full[(r - r0) * S:(r - r0 + 1) * S, (c - c0) * S:(c - c0 + 1) * S] = cv2.imread(f)
    present[(r - r0) * S:(r - r0 + 1) * S, (c - c0) * S:(c - c0 + 1) * S] = True

# Masken auf halber Aufloesung (glattere Konturen)
work = cv2.resize(full, (full.shape[1] // 2, full.shape[0] // 2), interpolation=cv2.INTER_AREA)
hsv = cv2.cvtColor(cv2.GaussianBlur(cv2.bilateralFilter(work, 9, 50, 50), (7, 7), 0), cv2.COLOR_BGR2HSV)
h, s, v = cv2.split(hsv)
empty = (work.sum(axis=2) < 15)
water = ((h >= 90) & (h <= 125) & (s >= 60)) & ~empty
rock = (h >= 4) & (h <= 22) & (s >= 130) & (v >= 55)

def clean(m, k, min_area):
    m = m.astype(np.uint8) * 255
    ker = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k, k))
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, ker)
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, ker, iterations=2)
    n, lab, st, _ = cv2.connectedComponentsWithStats(m)
    return np.isin(lab, [i for i in range(1, n) if st[i, 4] >= min_area]).astype(np.uint8) * 255

water = clean(water, 9, 3000)
rock = clean(rock, 9, 2500)
walk = cv2.bitwise_not(cv2.bitwise_or(water, rock)); walk[empty] = 0
walk = clean(walk > 0, 9, 5000)
inv = cv2.bitwise_not(walk)
n, lab, st, _ = cv2.connectedComponentsWithStats(inv)
for i in range(1, n):
    if st[i, 4] < 2500: walk[lab == i] = 255

# Zeichnen in voller Aufloesung
H, W = full.shape[:2]
lines = np.zeros((H, W, 4), np.uint8)
shade = np.zeros((H, W), np.uint8)              # Alpha des dunklen Saums
def draw(mask, color):
    cnts, _ = cv2.findContours(mask, cv2.RETR_LIST, cv2.CHAIN_APPROX_NONE)
    cnts = [(cv2.approxPolyDP(c, 1.5, True) * 2) for c in cnts if cv2.arcLength(c, True) > 120]
    cv2.drawContours(shade, cnts, -1, 170, 7, cv2.LINE_AA)
    cv2.drawContours(lines, cnts, -1, color, 2, cv2.LINE_AA)
draw(walk, (250, 205, 220, 255))
draw(water, (250, 180, 100, 255))
sk = keep_long(prune(skeletonize(road_mask(full) > 0).astype(np.uint8) * 255, 20))
waterF = cv2.resize(water, (W, H), interpolation=cv2.INTER_NEAREST)
road = (cv2.dilate(sk, np.ones((2, 2), np.uint8)) > 0) & (waterF == 0)
lines[road] = (185, 220, 238, 230)
shade[cv2.dilate(road.astype(np.uint8), np.ones((5, 5), np.uint8)) > 0] = np.maximum(shade[cv2.dilate(road.astype(np.uint8), np.ones((5, 5), np.uint8)) > 0], 140)

# Raender und fehlende Kacheln ausblenden
bad = ~present
emptyF = cv2.resize(empty.astype(np.uint8), (W, H), interpolation=cv2.INTER_NEAREST) > 0
bad |= emptyF
bad = cv2.dilate(bad.astype(np.uint8), np.ones((15, 15), np.uint8)) > 0
edge = np.zeros_like(bad); edge[:8, :] = edge[-8:, :] = edge[:, :8] = edge[:, -8:] = True
lines[bad | edge] = 0
shade[bad | edge] = 0
# Saum unter die Linien legen: Ergebnis = Linie ueber dunklem Grund
a = lines[..., 3:4].astype(np.float32) / 255
sa = shade[..., None].astype(np.float32) / 255
dark = np.array([28, 18, 22], np.float32)
out_a = a + sa * (1 - a)
rgb = (lines[..., :3] * a + dark * sa * (1 - a)) / np.maximum(out_a, 1e-6)
lines = np.dstack([rgb, out_a * 255]).clip(0, 255).astype(np.uint8)

os.makedirs(OUT, exist_ok=True)
import shutil; shutil.rmtree(OUT, ignore_errors=True); os.makedirs(OUT)
written = []
for (c, r) in sorted(tiles):
    blk = lines[(r - r0) * S:(r - r0 + 1) * S, (c - c0) * S:(c - c0 + 1) * S]
    if blk[..., 3].max() == 0: continue
    for size in (512, 256, 128):
        b = blk
        if size < S:
            f = S // size
            # Linien vor dem Verkleinern verbreitern, damit sie sichtbar bleiben
            a = cv2.dilate(blk[..., 3], np.ones((f, f), np.uint8))
            col = cv2.dilate(blk[..., :3], np.ones((f, f), np.uint8))
            b = cv2.resize(np.dstack([col, a]), (size, size), interpolation=cv2.INTER_AREA)
            b[..., 3] = np.clip(b[..., 3].astype(np.int32) * 2, 0, 255)
        d = OUT if size == 512 else f'{OUT}/{size}'
        os.makedirs(d, exist_ok=True)
        Image.fromarray(cv2.cvtColor(b, cv2.COLOR_BGRA2RGBA), 'RGBA').save(f'{d}/{c}_{r}.tga', orientation=1)
    written.append((c, r))
with open('Runeway/Tiles.lua', 'w') as fh:
    fh.write('-- automatisch erzeugt: vorhandene Kontur-Kacheln je Instanz (Spalte_Zeile)\n')
    fh.write('RunewayTiles = {\n    [0] = {\n')
    for c, r in written: fh.write(f'        ["{c}_{r}"] = true,\n')
    fh.write('    },\n}\n')
cv2.imwrite('lines_full_preview.png', cv2.resize(lines[..., :3], (W // 4, H // 4), interpolation=cv2.INTER_AREA))
print(len(written), 'Kacheln', lines.shape)
