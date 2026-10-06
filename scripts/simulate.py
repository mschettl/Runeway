# Bildet die Lua-Logik nach: Kacheln in Weltkoordinaten, Spieler in der Mitte, Rotation
import numpy as np, cv2, glob, re, math
from PIL import Image
T = 1600/3
pN, pW = 1917.5999755859, 84.900001525879     # Position aus dem Screenshot
W, H, k = 700, 450, 1.5
def render(facing):
    ang = -facing
    can = np.zeros((H, W, 4), np.float32)
    for f in glob.glob('Runeway/tiles/0/*.tga'):
        c, r = map(int, re.findall(r'(\d+)_(\d+)', f)[0])
        cn = (32-r)*T - T/2; cw = (32-c)*T - T/2
        sx = -(cw-pW)*k; sy = (cn-pN)*k
        x = sx*math.cos(ang) - sy*math.sin(ang); y = sx*math.sin(ang) + sy*math.cos(ang)
        img = np.array(Image.open(f).convert('RGBA')).astype(np.float32)
        size = T*k; s = size/512
        # Affine: Texturmitte -> Bildschirm (W/2+x, H/2-y), Rotation ang (CCW auf Bildschirm)
        ca, sa = math.cos(ang)*s, math.sin(ang)*s
        M = np.array([[ca, sa, W/2+x - (ca*256 + sa*256)], [-sa, ca, H/2-y - (-sa*256 + ca*256)]], np.float32)
        warped = cv2.warpAffine(img, M, (W, H), flags=cv2.INTER_LINEAR, borderValue=(0,0,0,0))
        a = warped[..., 3:4]/255
        can[..., :3] = can[..., :3]*(1-a) + warped[..., :3]*a
        can[..., 3:4] = np.maximum(can[..., 3:4], a*255)
    out = (can[..., :3]*(can[..., 3:4]/255) + 30*(1-can[..., 3:4]/255)).astype(np.uint8)
    cv2.arrowedLine(out, (W//2, H//2+10), (W//2, H//2-12), (60, 60, 255), 3, tipLength=0.5)
    cv2.putText(out, f'facing {math.degrees(facing):.0f} deg', (10, 25), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (200,200,200), 1)
    return cv2.cvtColor(out, cv2.COLOR_RGB2BGR)
cv2.imwrite('sim.png', np.vstack([render(0), render(math.pi/2)]))
