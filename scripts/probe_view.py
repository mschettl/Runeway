# Renders the quest area samples of /rnw probe from the SavedVariables file.
#   python scripts/probe_view.py <path to WTF/Account/<ACCOUNT>/SavedVariables/Runeway.lua>
import os
import sys
import numpy as np
import cv2
import lupa

L = lupa.LuaRuntime(unpack_returned_tuples=True)
L.execute(open(sys.argv[1], encoding='utf8').read())
probe = L.globals().RunewayDB.probe
out = os.path.join(os.path.dirname(__file__), '..', 'build')
os.makedirs(out, exist_ok=True)
print('map', probe.mapID, 'time', probe.time,
      'corners (north/west at map 0,0 and 1,1):', list(probe.corners.values()) if probe.corners else None)
colours = {'0': (30, 30, 30), '1': (60, 200, 255), '2': (255, 120, 60)}


def mask_img(g, size=384):
    rows = list(g.rows.values())
    img = np.array([[colours[c] for c in r] for r in rows], np.uint8)
    h, w = img.shape[:2]
    s = size / max(h, w)
    return cv2.resize(img, (max(1, int(w * s)), max(1, int(h * s))), interpolation=cv2.INTER_NEAREST)


def world(x, y):
    """Normalized map position -> (north, west) using the map corners."""
    n0, w0, n1, w1 = list(probe.corners.values())
    return n0 + (n1 - n0) * y, w0 + (w1 - w0) * x


tiles = []
for q in probe.quests.values():
    c, f = q.coarse, q.fine
    print(f'quest {q.questID} {q.title}: coarse {c.hits} hits, fine {f.nx}x{f.ny} {f.hits} hits' if f else
          f'quest {q.questID} {q.title}: coarse {c.hits} hits, no fine pass')
    if f and f.bbox and probe.corners:
        b = list(f.bbox.values())
        (na, wa), (nb, wb) = world(b[0], b[1]), world(b[2], b[3])
        print(f'    world bbox north {nb:.0f}..{na:.0f}, west {wb:.0f}..{wa:.0f} ({abs(wa - wb):.0f} x {abs(na - nb):.0f} yd)')
    for g, tag in ((c, 'coarse'), (f, 'fine')):
        if not g:
            continue
        img = np.zeros((384, 384, 3), np.uint8)
        m = mask_img(g)
        img[:m.shape[0], :m.shape[1]] = m
        cv2.putText(img, f'{q.questID} {tag} {q.title or ""}'[:44], (6, 18), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (255, 255, 255), 1)
        tiles.append(img)
if tiles:
    while len(tiles) % 4:
        tiles.append(np.zeros_like(tiles[0]))
    sheet = np.vstack([np.hstack(tiles[i:i + 4]) for i in range(0, len(tiles), 4)])
    cv2.imwrite(os.path.join(out, 'probe.png'), sheet)
    print('build/probe.png written')

# Overlay: quest area outlines (fine pass) on the Tirisfal preview from build_raw.py, in world coordinates
T = 1600 / 3
prev = os.path.join(out, 'preview_over_minimap.png')
if probe.corners and os.path.exists(prev):
    base = cv2.imread(prev)
    tiles_lua = open(os.path.join(os.path.dirname(__file__), '..', 'Runeway_EasternKingdoms', 'tiles', '0', 'Tiles.lua')).read()
    import re
    keys = [tuple(map(int, k)) for k in re.findall(r'\["(\d+)_(\d+)"\]', tiles_lua)]
    c0, r0 = min(c for c, _ in keys) - 1, min(r for _, r in keys) - 1     # same margin as build_raw.py
    ppt = base.shape[1] / (max(c for c, _ in keys) + 2 - c0)                # preview pixels per tile
    palette = [(0, 220, 255), (0, 255, 120), (255, 160, 0), (255, 80, 200), (80, 160, 255), (200, 255, 80),
               (255, 255, 255), (120, 120, 255)]
    for k, q in enumerate(probe.quests.values()):
        f = q.fine
        if not f or not f.hits:
            continue
        rows = list(f.rows.values())
        m = np.array([[ch == '1' for ch in r] for r in rows], np.uint8)
        x0, y0, x1, y1 = list(f.rect.values())
        cnts, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        col = palette[k % len(palette)]
        for cnt in cnts:
            pts = []
            for px, py in cnt[:, 0, :]:
                nx_, ny_ = x0 + (px + 0.5) * (x1 - x0) / f.nx, y0 + (py + 0.5) * (y1 - y0) / f.ny
                north, west = world(nx_, ny_)
                pts.append(((32 - west / T - c0) * ppt, (32 - north / T - r0) * ppt))
            cv2.polylines(base, [np.array(pts, np.int32)], True, col, 2, cv2.LINE_AA)
        n, w = world(*list(q.pin.values()))
        cv2.circle(base, (int((32 - w / T - c0) * ppt), int((32 - n / T - r0) * ppt)), 5, col, -1)
        cv2.putText(base, str(q.questID), (int((32 - w / T - c0) * ppt) + 6, int((32 - n / T - r0) * ppt) - 6),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, col, 1, cv2.LINE_AA)
    cv2.imwrite(os.path.join(out, 'probe_overlay.png'), base)
    print('build/probe_overlay.png written')
