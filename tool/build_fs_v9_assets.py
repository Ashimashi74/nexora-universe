#!/usr/bin/env python3
"""Finger soccer v9 asset builder (owner art 2026-11-22).

Inputs: the owner's uploads (default directory: ../files/uploads relative to the repo, or argv[1]).
  pitches  142742-ec5be00ddf31.png (Neon Arena), 142744-b68cf4f3fa83.png (Gold Checker), 142745-e589a9aa5b52.png (Gold Stripes)
  badges   142520-db0a7d5177cd.jpg, 142521-5661d0278c8d.jpg (4 x 6 grids of round NX badges)
  balls    142627-69ea402edd47.png (2 x 2 grid), 142629-1459146bbdae.jpg, 142631-a12a78d3b0a6.jpg, 142634-41843c8cf098.png
Outputs (webp):
  assets/games/bermuda/fields/<id>.webp   full pitch art; the mock "تغییر ترکیب" button and the printed "00" digits removed
  assets/games/bermuda/thumbs/<id>.webp   240 x 320 picker thumbs
  assets/games/bermuda/discs/v9/<slug>.webp  256 x 256, badge rim exactly at radius 120 (kBmDiscArtFill = 120 / 128)
  assets/games/bermuda/balls/v9/<slug>.webp  192 x 192, the ball fills its square (rolled by BmBallRenderer)
Every measurement the engine uses (frame inner edges, post centres, net depth, score display boxes) is printed by
work/measure-style code in this file (measure_pitch) and copied into lib/games/finger_soccer/core/bm_data.dart.
"""
import os, sys
import numpy as np
from PIL import Image, ImageFilter, ImageDraw

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(REPO), 'files', 'uploads')
A = os.path.join(REPO, 'assets', 'games', 'bermuda')

PITCHES = [
    ('nx_neon_arena', '142742-ec5be00ddf31.png'),
    ('nx_gold_checker', '142744-b68cf4f3fa83.png'),
    ('nx_gold_stripes', '142745-e589a9aa5b52.png'),
]
# The printed "00" on both side displays: one box per digit (image px, inclusive), erased to the display's black glass.
DIGIT_BOXES = [(22, 701, 63, 749), (22, 761, 63, 812), (877, 701, 918, 749), (877, 761, 918, 812)]
# The mock formation button drawn in the bottom-left corner of every pitch (image px).
BUTTON_BOX = (40, 1524, 326, 1668)


def frame(p):
    r, g, b = int(p[0]), int(p[1]), int(p[2])
    return (r > 140 and g < 70 and b < 70) or (r > 190 and g > 120 and b < 90)


def measure_pitch(a):
    """Inner edges of the coloured frame line (the rails), median over many rows / columns."""
    Ls, Rs, Ts, Bs = [], [], [], []
    for y in range(300, 1400, 25):
        xs = [x for x in range(40, 140) if frame(a[y, x])]
        xr = [x for x in range(800, 900) if frame(a[y, x])]
        if xs: Ls.append(max(xs) + 1)
        if xr: Rs.append(min(xr) - 1)
    for x in list(range(130, 300, 10)) + list(range(650, 820, 10)):
        ts = [y for y in range(60, 160) if frame(a[y, x])]
        bs = [y for y in range(1450, 1600) if frame(a[y, x])]
        if ts: Ts.append(max(ts) + 1)
        if bs: Bs.append(min(bs) - 1)
    return int(np.median(Ls)), int(np.median(Rs)), int(np.median(Ts)), int(np.median(Bs))


def remap_rows(im, T, B, src_mid, dst_mid):
    """Piecewise-linear vertical remap so the drawn halfway line sits exactly halfway between the goal lines."""
    a = np.asarray(im)
    out = a.copy()
    for y in range(T, B + 1):
        if y <= dst_mid:
            sy = T + (y - T) * (src_mid - T) / (dst_mid - T)
        else:
            sy = src_mid + (y - dst_mid) * (B - src_mid) / (B - dst_mid)
        y0 = int(np.floor(sy)); f = sy - y0
        y1 = min(y0 + 1, a.shape[0] - 1)
        out[y] = (a[y0] * (1 - f) + a[y1] * f).astype(a.dtype)
    return Image.fromarray(out)


def build_pitches():
    os.makedirs(os.path.join(A, 'fields'), exist_ok=True)
    os.makedirs(os.path.join(A, 'thumbs'), exist_ok=True)
    for pid, fn in PITCHES:
        im = Image.open(os.path.join(SRC, fn)).convert('RGB')
        a = np.asarray(im)
        L, R, T, B = measure_pitch(a)
        # halfway line: the white row band across the left half of the pitch
        w = a.min(axis=2) > 170
        rows = [y for y in range(600, 1050) if w[y, 120:300].mean() > .6]
        mid_drawn = (rows[0] + rows[-1]) / 2
        mid = (T + B) / 2
        if abs(mid_drawn - mid) > 2:
            im = remap_rows(im, T, B, mid_drawn, mid)
        # remove the mock button: the art is left / right symmetric, so the bottom-left corner is rebuilt from the
        # bottom-right corner mirrored horizontally, with a soft vertical seam at the top of the patch
        x0, y0, x1, y1 = BUTTON_BOX
        W = im.width
        patch = im.crop((W - 1 - x1, y0, W - x0, y1 + 1)).transpose(Image.FLIP_LEFT_RIGHT)
        m = Image.new('L', patch.size, 255)
        md = ImageDraw.Draw(m)
        for k in range(8):
            md.line([(0, k), (patch.size[0], k)], fill=int(255 * (k + 1) / 9))
        im.paste(patch, (x0, y0), m)
        # erase the printed digits: the display glass is near-black
        d = ImageDraw.Draw(im)
        for bx in DIGIT_BOXES:
            g = np.asarray(im.crop((bx[0] - 3, bx[1] - 3, bx[2] + 4, bx[3] + 4))).reshape(-1, 3)
            dark = g[g.sum(axis=1) < 60]
            col = tuple(int(v) for v in (np.median(dark, axis=0) if len(dark) else (6, 6, 9)))
            d.rectangle(bx, fill=col)
        im.save(os.path.join(A, 'fields', pid + '.webp'), 'WEBP', quality=86, method=6)
        im.resize((240, 426), Image.LANCZOS).crop((0, 53, 240, 373)).save(
            os.path.join(A, 'thumbs', pid + '.webp'), 'WEBP', quality=82, method=6)
        print(pid, dict(L=L, R=R, T=T, B=B, mid_drawn=mid_drawn, mid=mid))


BADGES = [
    ('142520-db0a7d5177cd.jpg', [
        'bmw', 'mercedes', 'audi', 'bugatti',
        'ferrari', 'porsche', 'mclaren', 'aston_martin',
        'volkswagen', 'lamborghini', 'toyota', 'nissan',
        'nike', 'adidas', 'nx_core', 'nx_pulse',
        'puma', 'under_armour', 'nx_prism', 'nx_infinity',
        'reebok', 'new_balance', 'nx_nova', 'nx_summit',
    ]),
    ('142521-5661d0278c8d.jpg', [
        'bmw_ii', 'mercedes_ii', 'audi_ii', 'toyota_ii',
        'ferrari_ii', 'porsche_ii', 'honda', 'ford',
        'volkswagen_ii', 'lamborghini_ii', 'chevrolet', 'nissan_ii',
        'nike_ii', 'adidas_ii', 'nx_circuit', 'nx_holo',
        'puma_ii', 'under_armour_ii', 'nx_dragon', 'nx_galaxy',
        'new_balance_ii', 'reebok_ii', 'nx_inferno', 'nx_frost',
    ]),
]


def bands(profile, thr, min_len):
    out, s = [], None
    for i, v in enumerate(profile):
        if v > thr and s is None: s = i
        if v <= thr and s is not None:
            if i - s >= min_len: out.append((s, i - 1))
            s = None
    if s is not None and len(profile) - s >= min_len: out.append((s, len(profile) - 1))
    return out


def circle_cut(img, cx, cy, rad, size, fill_r):
    """Square crop centred on (cx, cy), scaled so radius `rad` -> `fill_r` px in a `size` sprite, round alpha."""
    scale = fill_r / rad
    half = size / 2 / scale
    crop = img.crop((int(round(cx - half)), int(round(cy - half)), int(round(cx + half)), int(round(cy + half))))
    crop = crop.resize((size, size), Image.LANCZOS).convert('RGBA')
    ss = 4
    m = Image.new('L', (size * ss, size * ss), 0)
    ImageDraw.Draw(m).ellipse(((size / 2 - fill_r) * ss, (size / 2 - fill_r) * ss,
                               (size / 2 + fill_r) * ss, (size / 2 + fill_r) * ss), fill=255)
    m = m.resize((size, size), Image.LANCZOS)
    crop.putalpha(m)
    return crop


def build_badges():
    out = os.path.join(A, 'discs', 'v9')
    os.makedirs(out, exist_ok=True)
    for fn, names in BADGES:
        im = Image.open(os.path.join(SRC, fn)).convert('RGB')
        g = np.asarray(im.convert('L')).astype(int)
        mask = g > 45
        rows = bands(mask.mean(axis=1), .18, 150)
        assert len(rows) == 6, (fn, rows)
        k = 0
        for (y0, y1) in rows:
            q = im.width / 4
            cols = [(int(i * q), int((i + 1) * q) - 1) for i in range(4)]
            for (x0, x1) in cols:
                sub = mask[y0:y1 + 1, x0:x1 + 1]
                # tight box from rows / columns that are mostly badge (sparkles and glow ignored)
                ry = bands(sub.mean(axis=1), .12, 20)
                rx = bands(sub.mean(axis=0), .12, 20)
                by0, by1 = ry[0][0] + y0, ry[-1][1] + y0
                bx0, bx1 = rx[0][0] + x0, rx[-1][1] + x0
                cx, cy = (bx0 + bx1) / 2, (by0 + by1) / 2
                rad = min(bx1 - bx0, by1 - by0) / 2 * .985
                circle_cut(im, cx, cy, rad, 256, 120).save(os.path.join(out, names[k] + '.webp'), 'WEBP',
                                                          quality=88, method=6)
                k += 1
        print(fn, 'badges', k)


def ball_from(img, box=None, size=192):
    """Trim one ball (bright on black or alpha) to its circle and fill a size x size sprite with it."""
    if box: img = img.crop(box)
    rgba = img.convert('RGBA')
    a = np.asarray(rgba).astype(int)
    # Segment against the tile's actual corner background. A luminance-only mask includes the whole tile
    # on light atlases, while a fixed threshold can shave dark panels off coloured balls.
    rgb = a[..., :3]
    h, w = rgb.shape[:2]
    patch = max(2, min(h, w) // 20)
    corners = np.concatenate((rgb[:patch, :patch].reshape(-1, 3), rgb[:patch, -patch:].reshape(-1, 3),
                              rgb[-patch:, :patch].reshape(-1, 3), rgb[-patch:, -patch:].reshape(-1, 3)))
    bg = np.median(corners, axis=0)
    delta = np.max(np.abs(rgb.astype(int) - bg.astype(int)), axis=2)
    m = (a[..., 3] > 40) & (delta > 24)
    # Occupancy-based extents ignore isolated highlights but retain dark artwork connected to the ball body.
    ry = np.flatnonzero(m.mean(axis=1) > .03)
    rx = np.flatnonzero(m.mean(axis=0) > .03)
    if len(ry) < 2 or len(rx) < 2:
        lum = a[..., :3].max(axis=2)
        m = (a[..., 3] > 40) & (lum > 30)
        ry = np.flatnonzero(m.mean(axis=1) > .12)
        rx = np.flatnonzero(m.mean(axis=0) > .12)
    if len(ry) < 2 or len(rx) < 2:
        raise ValueError('cannot detect ball bounds')
    y0, y1 = int(ry[0]), int(ry[-1])
    x0, x1 = int(rx[0]), int(rx[-1])
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    rad = min(x1 - x0, y1 - y0) / 2 * .985
    return circle_cut(rgba, cx, cy, rad, size, size / 2 - .5)


BALLS = [
    # (source, grid n x n, slugs in reading order)
    ('142627-69ea402edd47.png', 2, ['nx_yellow', 'nx_green', 'nx_blue', 'nx_pink']),
    ('142629-1459146bbdae.jpg', 1, ['nx_ice']),
    ('142631-a12a78d3b0a6.jpg', 2, ['pro_lime', 'pro_green', 'pro_blue', 'pro_magenta']),
    ('142634-41843c8cf098.png', 3, ['classic_noir', 'classic_plum', 'classic', 'hex_lime', 'hex_violet', 'hex_teal',
                                    'frost', 'pearl', 'street']),
]


def build_balls():
    out = os.path.join(A, 'balls', 'v9')
    os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):
        os.remove(os.path.join(out, f))
    n_out = 0
    for fn, n, slugs in BALLS:
        img = Image.open(os.path.join(SRC, fn))
        w, h = img.size
        for k, slug in enumerate(slugs):
            cx, cy = k % n, k // n
            box = (cx * w // n, cy * h // n, (cx + 1) * w // n, (cy + 1) * h // n)
            ball_from(img, box).save(os.path.join(out, slug + '.webp'), 'WEBP', quality=90, method=6)
            n_out += 1
    print('balls', n_out)


if __name__ == '__main__':
    build_pitches()
    build_badges()
    build_balls()
