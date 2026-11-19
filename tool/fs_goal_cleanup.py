#!/usr/bin/env python3
"""Paint the frame-built goals out of the owner's 2026-11 pitches so every pitch shows the one goal sprite
(assets/games/bermuda/goals/white.webp). The notch between the painted goal pillars is refilled, row by row, with
the frame rail on either side of it (mirrored strips cross-faded across the notch).
Usage: python3 tool/fs_goal_cleanup.py <repo root>   (idempotent on already-cleaned art only by design: run once)"""
import sys, os
import numpy as np
from PIL import Image

# field id: (notch x0, x1, top boundary t0, bottom boundary b0) in image px (bounds as in bm_data.dart)
FIELDS = {
    'neon_grass': (329, 696, 102, 1408),
    'neon_cup': (304, 721, 100, 1398),
    'sockerbox': (309, 721, 100, 1394),
    'gold_leather': (319, 701, 82, 1414),
}
BAND = 48

def fill(a, x0, x1, y0, y1):
    n = x1 - x0
    for x in range(x0, x1):
        k = x - x0
        lx = x0 - 1 - (k % BAND)          # mirrored strip left of the notch
        rx = x1 + ((x1 - 1 - x) % BAND)   # mirrored strip right of the notch
        t = (k + .5) / n
        a[y0:y1, x] = (a[y0:y1, lx] * (1 - t) + a[y0:y1, rx] * t)

if __name__ == '__main__':
    root = sys.argv[1]
    for fid, (x0, x1, t0, b0) in FIELDS.items():
        p = os.path.join(root, 'assets/games/bermuda/fields', fid + '.webp')
        im = Image.open(p).convert('RGB')
        a = np.array(im).astype(float)
        fill(a, x0, x1, 0, t0 - 2)
        fill(a, x0, x1, b0 + 2, a.shape[0])
        Image.fromarray(a.round().clip(0, 255).astype(np.uint8)).save(p, quality=88, method=4)
        print('cleaned', fid)
