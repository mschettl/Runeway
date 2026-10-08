# Road skeleton helper used by build_raw.py
import cv2
import numpy as np


def prune(sk, n=15):
    """Removes spurs: end pixels of the skeleton are cut n times (short side branches vanish)."""
    sk = (sk > 0).astype(np.uint8)
    k = np.ones((3, 3), np.uint8)
    for _ in range(n):
        nb = cv2.filter2D(sk, -1, k, borderType=cv2.BORDER_CONSTANT) - sk
        sk[(sk == 1) & (nb <= 1)] = 0
    return sk * 255
