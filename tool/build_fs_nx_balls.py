#!/usr/bin/env python3
"""Finger soccer v7: build the two GIF match balls (owner art, 2026-11-20) into game strips.

  nx_spin_24.webp   <- tool/ball_src/nx_spin_png/frame_01..24.png (clean PNG frames of
                       nx_ball_fixed_center_spin.gif: 256x256, 24 frames, 90 ms)
  nx_star_16.webp   <- tool/ball_src/nx_football_16_frames.gif (384x256, 16 frames, 90 ms; the ball sits in the
                       middle of a wide transparent canvas with a 1-bit alpha edge)

Every frame keeps the GIF's own order (the game plays them at the GIF's 90 ms). Each frame is re-centred on its own
ball silhouette (alpha centroid, sub-pixel) so the ball turns about a fixed centre with no wobble, scaled so the ball
radius is BALL_R px in a BALL_S px cell (kBmBallArtFill = 76 / 80, like tool/build_fs_assets.py), and trimmed with
one anti-aliased circular mask (clean round edge, transparent background, no GIF matte fringe).
Usage: python3 tool/build_fs_nx_balls.py [repo root]
"""
import os
import sys

import numpy as np
from PIL import Image, ImageSequence

BALL_S = 160
BALL_R = 76.0


def silhouette(fr):
    a = np.asarray(fr.convert('RGBA'))[..., 3] > 127
    ys, xs = np.nonzero(a)
    return xs.mean() + .5, ys.mean() + .5, float(np.sqrt(a.sum() / np.pi))


def fit(frames, out_strip, out_thumb, mask_r):
    st = [silhouette(f) for f in frames]
    r_src = float(np.median([s[2] for s in st]))  # one scale for every frame (a sphere does not change size)
    k = BALL_R / r_src
    yy, xx = np.mgrid[0:BALL_S, 0:BALL_S]
    d = np.sqrt((xx + .5 - BALL_S / 2) ** 2 + (yy + .5 - BALL_S / 2) ** 2)
    mask = np.clip(mask_r + .5 - d, 0, 1)
    strip = Image.new('RGBA', (BALL_S * len(frames), BALL_S), (0, 0, 0, 0))
    big = 4  # supersample the resample, then box down (crisper than one bicubic pass)
    for i, (f, (cx, cy, _)) in enumerate(zip(frames, st)):
        src = f.convert('RGBA')
        # premultiply so transparent matte colour never bleeds into the edge
        a = np.asarray(src).astype(np.float32)
        a[..., :3] *= a[..., 3:4] / 255.0
        pm = Image.fromarray(a.clip(0, 255).astype(np.uint8), 'RGBA')
        S = BALL_S * big
        kk = k * big
        # output pixel (u, v) <- source (cx + (u - S/2) / kk, cy + (v - S/2) / kk)
        coeffs = (1 / kk, 0, cx - S / 2 / kk, 0, 1 / kk, cy - S / 2 / kk)
        o = pm.transform((S, S), Image.AFFINE, coeffs, resample=Image.BICUBIC)
        o = o.resize((BALL_S, BALL_S), Image.BOX)
        b = np.asarray(o).astype(np.float32)
        al = b[..., 3] * mask
        rgb = np.where(b[..., 3:4] > 0, b[..., :3] * 255.0 / np.maximum(b[..., 3:4], 1), 0)
        out = np.dstack([rgb, al]).clip(0, 255).astype(np.uint8)
        strip.paste(Image.fromarray(out, 'RGBA'), (i * BALL_S, 0))
    strip.save(out_strip, 'WEBP', quality=92, method=6, alpha_quality=100)
    strip.crop((0, 0, BALL_S, BALL_S)).save(out_thumb, 'WEBP', quality=92, method=6, alpha_quality=100)
    return r_src, st


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    src = os.path.join(root, 'tool/ball_src')
    out = os.path.join(root, 'assets/games/bermuda/balls')
    spin = [Image.open(os.path.join(src, 'nx_spin_png', 'frame_%02d.png' % i)) for i in range(1, 25)]
    gif = Image.open(os.path.join(src, 'nx_football_16_frames.gif'))
    star = [f.copy() for f in ImageSequence.Iterator(gif)]
    assert len(spin) == 24 and len(star) == 16, (len(spin), len(star))
    for f in ImageSequence.Iterator(gif):
        assert f.info.get('duration') == 90
    r1, _ = fit(spin, os.path.join(out, 'nx_spin_24.webp'), os.path.join(out, 'nx_spin_thumb.webp'), BALL_R)
    # the GIF edge is 1-bit with a grey matte: trim half a pixel more
    r2, _ = fit(star, os.path.join(out, 'nx_star_16.webp'), os.path.join(out, 'nx_star_thumb.webp'), BALL_R - .6)
    print('nx_spin: src radius %.2f px, 24 frames; nx_star: src radius %.2f px, 16 frames' % (r1, r2))


if __name__ == '__main__':
    main()
