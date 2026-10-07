# Writes the soft edge masks media/fade1.tga .. fade5.tga (white, alpha = round fade towards the edge).
# The widths must match FADE_WIDTH in Core.lua; QuestAreas.lua fades the quest lines with the same formula.
#   python scripts/make_masks.py
import os
import numpy as np
from PIL import Image

FADE_WIDTH = (0.12, 0.25, 0.38, 0.55, 0.75)   # share of the radius
SIZE = 256
OUT = os.path.join(os.path.dirname(__file__), '..', 'Runeway', 'media')

c = (np.arange(SIZE) + 0.5) / SIZE * 2 - 1
x, y = np.meshgrid(c, c)
r = np.sqrt(x * x + y * y)
for i, w in enumerate(FADE_WIDTH, 1):
    t = np.clip((1 - r) / w, 0, 1)
    a = np.round(t * t * (3 - 2 * t) * 255).astype(np.uint8)
    rgba = np.dstack([np.full_like(a, 255)] * 3 + [a])
    Image.fromarray(rgba, 'RGBA').save(os.path.join(OUT, f'fade{i}.tga'), orientation=1)
    print(f'fade{i}.tga  width {w}')
