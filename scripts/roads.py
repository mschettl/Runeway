import cv2, numpy as np
from skimage.morphology import skeletonize
def road_mask(img):
    hsv = cv2.cvtColor(cv2.GaussianBlur(img, (3, 3), 0), cv2.COLOR_BGR2HSV).astype(np.int16)
    g = np.clip(hsv[..., 2] - 0.6 * hsv[..., 1] + 60, 0, 255).astype(np.uint8)   # hell + grau
    th = cv2.morphologyEx(g, cv2.MORPH_TOPHAT, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (21, 21)))
    m = ((th > 18) & (hsv[..., 1] < 90)).astype(np.uint8) * 255
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5)))
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3)))
    n, lab, st, _ = cv2.connectedComponentsWithStats(m)
    out = np.zeros_like(m)
    for i in range(1, n):
        w, h, a = st[i, 2], st[i, 3], st[i, 4]
        if max(w, h) >= 60 and a / (w * h) < 0.35:   # lang und duenn
            out[lab == i] = 255
    return out
def prune(sk, n=15):
    sk = (sk > 0).astype(np.uint8)
    k = np.ones((3, 3), np.uint8)
    for _ in range(n):
        nb = cv2.filter2D(sk, -1, k, borderType=cv2.BORDER_CONSTANT) - sk
        sk[(sk == 1) & (nb <= 1)] = 0
    return sk * 255
def keep_long(sk, min_px=150, max_ratio=2.2):
    n, lab, st, _ = cv2.connectedComponentsWithStats((sk > 0).astype(np.uint8), connectivity=8)
    out = np.zeros_like(sk)
    for i in range(1, n):
        w, h, a = st[i, 2], st[i, 3], st[i, 4]
        if a >= min_px and (a / max(np.hypot(w, h), 1) <= max_ratio or a / float(w * h) <= 0.02):
            out[lab == i] = 255
    return out
if __name__ == '__main__':
    c = cv2.imread('crop_brill.png')
    m = road_mask(c)
    sk = prune(skeletonize(m > 0).astype(np.uint8) * 255)
    vis = (c * 0.4).astype(np.uint8)
    vis[cv2.dilate(sk, np.ones((3, 3), np.uint8)) > 0] = (200, 220, 235)
    cv2.imwrite('roads_test.png', np.hstack([c, vis]))
