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
tiles = []
for q in probe.quests.values():
    rows = list(q.rows.values())
    img = np.array([[colours[c] for c in r] for r in rows], np.uint8)
    img = cv2.resize(img, (384, 384), interpolation=cv2.INTER_NEAREST)
    cv2.putText(img, f'{q.questID} {q.title or ""}'[:40], (6, 18), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (255, 255, 255), 1)
    tiles.append(img)
    print(f'quest {q.questID} {q.title}: hits {q.hits}, other {q.other}, errors {q.errors}')
if tiles:
    while len(tiles) % 3:
        tiles.append(np.zeros_like(tiles[0]))
    sheet = np.vstack([np.hstack(tiles[i:i + 3]) for i in range(0, len(tiles), 3)])
    cv2.imwrite(os.path.join(out, 'probe.png'), sheet)
    print('build/probe.png written')
