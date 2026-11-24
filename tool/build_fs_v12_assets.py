#!/usr/bin/env python3
"""Finger Soccer v12 assets (owner upload 2026-11-24).

  python3 tool/build_fs_v12_assets.py <upload dir>

* fields: the owner's eleven pitch arts. Ten of them are full-resolution arts already in this repo's history
  (assets/g/fields/<id>.webp, commits 2cacc89 / 895d039: the upload carried only their 240x320 thumbnails, which
  match them); `tropical` is the uploaded full art itself. The uploaded thumbnails become the picker thumbs.
  -> assets/games/bermuda/fields/<id>.webp + assets/games/bermuda/thumbs/<id>.webp
* balls: 18 balls, each cut on its own circle (detected on the art, not on a fixed grid), fully transparent outside
  -> assets/games/bermuda/balls/v9/<slug>.webp (folder name kept: pubspec + tests), 256 x 256, the ball fills its square (rolled by BmBallRenderer).
    - six single balls (RGBA on transparent),
    - file_0000000011d48210b49581a8ac734aff.png: 2 columns x 3 rows on black (floor glow under each ball),
    - file_00000000bafc82108a2e5877885ed4d1.png: 3 columns x 2 rows on white (soft shadow under each ball).
* goal: the uploaded white.webp (1024 x 374, already cut) -> assets/games/bermuda/goals/white.webp.
"""
import io
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
A = os.path.join(ROOT, 'assets', 'games', 'bermuda')

# (id, source: 'git:<rev>:<path>' or an upload file name)
FIELDS = [
    ('pitch', 'git:2cacc89:assets/g/fields/pitch.webp'),
    ('tropical', 'tropical.webp'),
    ('checker', 'git:2cacc89:assets/g/fields/checker.webp'),
    ('futsal', 'git:2cacc89:assets/g/fields/futsal.webp'),
    ('arena', 'git:2cacc89:assets/g/fields/arena.webp'),
    ('psg', 'git:2cacc89:assets/g/fields/psg.webp'),
    ('campnou', 'git:895d039:assets/g/fields/campnou.webp'),
    ('blackice', 'git:895d039:assets/g/fields/blackice.webp'),
    ('autumn', 'git:895d039:assets/g/fields/autumn.webp'),
    ('frost', 'git:895d039:assets/g/fields/frost.webp'),
    ('glacier', 'git:895d039:assets/g/fields/glacier.webp'),
]

SINGLES = [
    ('6ba5f1733df56779666a528651acdd85.webp', 'nx_red_classic'),
    ('87a60592169748e10ecb1613468ca1c4.webp', 'nx_blue_wave'),
    ('6fb7326b7840d31562a0f41b3fb16ded.webp', 'nx_blue_stripe'),
    ('66ef6bbf7fba64bd80b2dccd29674a2f.webp', 'nx_cobalt'),
    ('4e55f1cd69ab2281c9ee4ae091cdc022.webp', 'nx_red_hex'),
    ('69d445703f9e387396781b681905f1bc.webp', 'nx_carbon'),
]
SHEETS = [
    ('file_0000000011d48210b49581a8ac734aff.png', 2, 3,
     ['nx_white_strike', 'nx_black_strike', 'nx_red_strike', 'nx_blue_strike', 'nx_red_flash', 'nx_blue_flash']),
    ('file_00000000bafc82108a2e5877885ed4d1.png', 3, 2,
     ['pro_sky', 'pro_red', 'pro_lime', 'pro_violet', 'pro_orange', 'pro_teal']),
]
BALL_SIZE = 256


def load(src, up):
    if src.startswith('git:'):
        _, rev, path = src.split(':', 2)
        data = subprocess.run(['git', '-C', ROOT, 'show', f'{rev}:{path}'], check=True, capture_output=True).stdout
        return Image.open(io.BytesIO(data))
    return Image.open(os.path.join(up, src))


def circle_cut(img, cx, cy, rad, size):
    """Square crop centred on (cx, cy), the ball radius `rad` filling the sprite, anti-aliased round alpha."""
    fill_r = size / 2 - .5
    half = rad * (size / 2) / fill_r
    rgba = img.convert('RGBA')
    crop = rgba.crop((int(round(cx - half)), int(round(cy - half)), int(round(cx + half)), int(round(cy + half))))
    crop = crop.resize((size, size), Image.LANCZOS)
    ss = 4
    m = Image.new('L', (size * ss, size * ss), 0)
    ImageDraw.Draw(m).ellipse(((size / 2 - fill_r) * ss, (size / 2 - fill_r) * ss,
                               (size / 2 + fill_r) * ss, (size / 2 + fill_r) * ss), fill=255)
    m = m.resize((size, size), Image.LANCZOS)
    a = np.minimum(np.asarray(crop.split()[3]), np.asarray(m))
    crop.putalpha(Image.fromarray(a.astype(np.uint8)))
    return crop


def ball_circle(tile, bg):
    """(cx, cy, r) of the ball in `tile`. The ball's horizontal extent is its diameter and its top edge is reliable;
    the bottom is not (a floor glow or a soft shadow hangs under the ball), so cy = top + r."""
    a = np.asarray(tile.convert('RGBA')).astype(int)
    rgb = a[..., :3]
    if bg is None:
        m = a[..., 3] > 128
    else:
        delta = np.max(np.abs(rgb - np.array(bg)), axis=2)
        m = (a[..., 3] > 128) & (delta > 40)
    rows = np.flatnonzero(m.mean(axis=1) > .04)
    cols = np.flatnonzero(m.mean(axis=0) > .04)
    x0, x1, y0 = int(cols[0]), int(cols[-1]), int(rows[0])
    r = (x1 - x0 + 1) / 2
    return (x0 + x1 + 1) / 2, y0 + r, r


def build(up):
    fdir, tdir = os.path.join(A, 'fields'), os.path.join(A, 'thumbs')
    for d in (fdir, tdir):
        os.makedirs(d, exist_ok=True)
        for f in os.listdir(d):
            os.remove(os.path.join(d, f))
    for fid, src in FIELDS:
        im = load(src, up).convert('RGB')
        im.save(os.path.join(fdir, fid + '.webp'), 'WEBP', quality=90, method=6)
        tp = os.path.join(up, fid + '.webp')
        if fid != 'tropical' and os.path.exists(tp):
            th = Image.open(tp).convert('RGB')
        else:  # cover-crop the art to the 3:4 picker thumb
            w, h = im.size
            ch = min(h, int(w * 4 / 3))
            th = im.crop((0, (h - ch) // 2, w, (h - ch) // 2 + ch)).resize((240, 320), Image.LANCZOS)
        th.save(os.path.join(tdir, fid + '.webp'), 'WEBP', quality=88, method=6)
        print('field', fid, im.size)

    bdir = os.path.join(A, 'balls', 'v9')
    os.makedirs(bdir, exist_ok=True)
    for f in os.listdir(bdir):
        os.remove(os.path.join(bdir, f))
    out = []
    for fn, slug in SINGLES:
        im = Image.open(os.path.join(up, fn)).convert('RGBA')
        cx, cy, r = ball_circle(im, None)
        out.append((slug, circle_cut(im, cx, cy, r * .985, BALL_SIZE)))
    for fn, cols, rows, slugs in SHEETS:
        im = Image.open(os.path.join(up, fn)).convert('RGBA')
        w, h = im.size
        rgb = np.asarray(im)[..., :3].astype(int)
        p = 12
        bg = np.median(np.concatenate([rgb[:p, :p].reshape(-1, 3), rgb[:p, -p:].reshape(-1, 3)]), axis=0)
        for k, slug in enumerate(slugs):
            c, r0 = k % cols, k // cols
            box = (c * w // cols, r0 * h // rows, (c + 1) * w // cols, (r0 + 1) * h // rows)
            cx, cy, r = ball_circle(im.crop(box), bg)
            out.append((slug, circle_cut(im, box[0] + cx, box[1] + cy, r * .975, BALL_SIZE)))
    for slug, sp in out:
        sp.save(os.path.join(bdir, slug + '.webp'), 'WEBP', quality=90, method=6)
    print('balls', len(out), [s for s, _ in out])

    g = Image.open(os.path.join(up, 'white.webp')).convert('RGBA')
    g.save(os.path.join(A, 'goals', 'white.webp'), 'WEBP', quality=92, method=6)
    print('goal', g.size)


if __name__ == '__main__':
    build(sys.argv[1] if len(sys.argv) > 1 else '/tmp/arena-coding-uploads')
