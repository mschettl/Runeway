# Writes the edge masks of the map: media/mask/s<S>f<F>.tga (white, alpha = shape with soft edge).
#   S = shape step 0-5 (0 = rectangle ... 5 = oval; the steps to a circle shrink the oval mask in Core.lua)
#   F = soft edge step 0-10 (fade width F/10 * 0.75 of the radius; 0 = hard edge)
# The shape is a superellipse |x|^n + |y|^n = 1 stretched to the window; Core.lua (ns.ShapeAlpha) computes the same
# alpha for quest lines, hover and the corpse marker, so EXPONENT and FADE_MAX must match it.
#   python scripts/make_masks.py
import os
import numpy as np
from PIL import Image

FADE_MAX = 0.75                     # soft edge 100 % (the former strength 5)
OUT = os.path.join(os.path.dirname(__file__), '..', 'Runeway', 'media', 'mask')


def exponent(s):                    # shape 0 .. 0.5 -> superellipse exponent 20 .. 2
    return 2 + (1 - 2 * s) ** 2 * 18


os.makedirs(OUT, exist_ok=True)
for si in range(6):
    n = exponent(si / 10)
    for fi in range(11):
        size = 128 if fi else 256   # the hard edge needs more pixels to stay sharp when stretched
        c = (np.arange(size) + 0.5) / size * 2 - 1
        x, y = np.meshgrid(c, c)
        d = (np.abs(x) ** n + np.abs(y) ** n) ** (1 / n)
        fw = fi / 10 * FADE_MAX
        if fw:
            t = np.clip((1 - d) / fw, 0, 1)
            a = t * t * (3 - 2 * t)
        else:                       # hard edge, one pixel of anti-aliasing
            a = np.clip((1 - d) * size / 2 + 0.5, 0, 1)
        a = np.round(a * 255).astype(np.uint8)
        rgba = np.dstack([np.full_like(a, 255)] * 3 + [a])
        Image.fromarray(rgba, 'RGBA').save(os.path.join(OUT, f's{si}f{fi}.tga'), orientation=1)
print(f'66 masks -> {os.path.normpath(OUT)}')
