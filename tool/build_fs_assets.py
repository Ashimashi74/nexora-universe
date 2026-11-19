#!/usr/bin/env python3
"""Finger-soccer asset pipeline (owner art pack -> game assets).

Discs: every sheet cell is circle/ellipse-fitted on its rim, resampled so the rim is an exact circle of radius
DISC_R px centred in a DISC_S px canvas, and masked to that circle. The game draws every disc sprite so the rim radius
equals the physics radius (kBmDiscArtFill = DISC_R / (DISC_S / 2)), so what you see is exactly what collides.
Balls: every frame of a 4x4 rotation sheet is fitted the same way and packed into a 16-frame strip (BALL_S px cells,
ball radius BALL_R px); kBmBallArtFill = BALL_R / (BALL_S / 2).
Usage: python3 tool/build_fs_assets.py <owner PNG dir> <repo root>
"""
import json, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage as nd

DISC_S, DISC_R = 256, 120
BALL_S, BALL_R = 160, 76

def fit_small(rgb, thr=40, close=3, maxdim=300):
    """Ellipse fit on a downscaled copy (fast), mapped back to full-resolution pixels."""
    h, w = rgb.shape[:2]
    k = min(1.0, maxdim / max(h, w))
    small = np.array(Image.fromarray(rgb).resize((max(1, int(w * k)), max(1, int(h * k))), Image.BILINEAR))
    cx, cy, rx, ry = fit_ellipse(mask_of(small, thr, close))
    return cx / k, cy / k, rx / k, ry / k

def mask_of(rgb, thr=40, close=5):
    m = rgb[:, :, :3].max(2) > thr
    m = nd.binary_closing(m, iterations=close)
    m = nd.binary_fill_holes(m)
    lab, n = nd.label(m)
    if n == 0:
        return m
    sizes = nd.sum(m, lab, range(1, n + 1))
    return lab == (int(np.argmax(sizes)) + 1)

def fit_ellipse(m):
    H, W = m.shape
    anyr = m.any(1)
    left = np.argmax(m, 1); right = W - 1 - np.argmax(m[:, ::-1], 1)
    widths = np.where(anyr, right - left + 1, 0).astype(float); mids = (left + right) / 2
    top = np.where(widths >= widths.max() * 0.995)[0]
    cy = top.mean(); cx = mids[top].mean(); rx = widths.max() / 2
    ext, cys = [], []
    for x in (int(cx - rx * 0.5), int(cx + rx * 0.5)):
        c = np.where(m[:, x])[0]
        if len(c):
            ext.append((c.max() - c.min() + 1) / 2 / np.sqrt(1 - 0.25))
            cys.append((c.max() + c.min()) / 2)
    ry = float(np.mean(ext)) if ext else rx
    if cys:
        cy = float(np.mean(cys))
    return float(cx), float(cy), float(rx), ry

def circle_alpha(size, r, feather=1.2):
    yy, xx = np.mgrid[0:size, 0:size] + 0.5
    d = np.sqrt((xx - size / 2) ** 2 + (yy - size / 2) ** 2)
    return np.clip((r - d) / feather + 0.5, 0, 1)

def normalize(rgba, cx, cy, rx, ry, size, r):
    """Affine-resample so the fitted rim (rx, ry) becomes a circle of radius r centred in a size x size canvas."""
    im = Image.fromarray(rgba)
    sx, sy = rx / r, ry / r
    # output (u,v) -> input (cx + (u - size/2) * sx, cy + (v - size/2) * sy)
    out = im.transform((size, size), Image.AFFINE, (sx, 0, cx - size / 2 * sx, 0, sy, cy - size / 2 * sy),
                       resample=Image.BICUBIC)
    a = np.array(out).astype(float)
    a[:, :, 3] = 255 * circle_alpha(size, r)
    return Image.fromarray(a.astype(np.uint8))

def cells(img, cols, rows, special=None):
    W, H = img.size
    out = []
    for j in range(rows):
        row_cols = cols if not (special and j in special) else 1
        for i in range(row_cols):
            out.append(img.crop((int(W * i / row_cols), int(H * j / rows), int(W * (i + 1) / row_cols), int(H * (j + 1) / rows))))
    return out

def disc_from_cell(cell, thr=40):
    a = np.array(cell.convert('RGBA'))
    if (a[:, :, 3] < 250).mean() > 0.05:
        a[:, :, :3] = (a[:, :, :3] * (a[:, :, 3:4] / 255.0)).astype(np.uint8)  # premultiply onto black
    a[:, :, 3] = 255
    cx, cy, rx, ry = fit_small(a, thr)
    return normalize(a, cx, cy, rx, ry, DISC_S, DISC_R), (cx, cy, rx, ry)

# ---------------------------------------------------------------- owner sheets
DISC_SHEETS = [
    # (file prefix, cols, rows, single-cell rows, names)
    ('1795082126645', 2, 3, None, ['real_madrid', 'barcelona', 'man_city', 'bayern', 'psg', 'liverpool']),
    ('2e0048f2543b', 2, 3, None, ['chelsea', 'man_united', 'arsenal', 'tottenham', 'newcastle', 'atletico']),
    ('37ef77d31f9b', 2, 3, None, ['al_hilal', 'persepolis', 'esteghlal', 'inter_miami', 'al_nassr', 'dortmund']),
    ('file_0000000017ac', 2, 3, None, ['inter_miami_alt', 'ajax', 'wolfsburg', 'tottenham_alt', 'roma', 'shakhtar']),
    ('file_0000000058f8', 2, 3, None, ['arsenal_alt', 'celtic', 'rangers', 'ajax_alt', 'marseille', 'monaco']),
    ('file_0000000080f4', 2, 3, None, ['ac_milan', 'inter', 'liverpool_alt', 'chelsea_alt', 'man_united_alt', 'psg_alt']),
    ('file_000000008b6c', 2, 3, {2}, ['germany', 'brazil', 'argentina', 'spain', 'portugal']),
    ('file_00000000a580', 2, 1, None, ['barcelona_blaugrana', 'barcelona_gold']),
    ('file_00000000a9a4', 2, 3, {2}, ['italy', 'iran', 'france', 'qatar', 'lebanon']),
    ('file_00000000ef1c', 2, 3, None, ['liverpool_alt2', 'ac_milan_alt', 'dortmund_alt', 'barcelona_alt', 'chelsea_alt2', 'inter_alt']),
    ('file_00000000fc40', 2, 3, None, ['real_madrid_alt', 'barcelona_alt2', 'bayern_alt', 'man_city_alt', 'arsenal_alt2', 'juventus']),
]
# NEXORA wood/carbon pucks (luxury): 4 columns x 3 rows of discs, label strips under each row.
PUCK_SHEET = ('file_00000000eeec', ['nx_star_dark', 'nx_star_light', 'nx_ring_dark', 'nx_ring_light',
                                     'nx_carved_dark', 'nx_carved_light', 'nx_hex_dark', 'nx_hex_light',
                                     'nx_carbon_dark', 'nx_carbon_light', 'nx_minimal_dark', 'nx_minimal_light'])
BALL_SHEETS = [
    ('file_000000005ae0', 'anix_green'),
    ('file_000000008ce8', 'anix_blue'),
    ('file_00000000918481f4bdeb6d0219365e36.png', 'nx_electron'),
]

def find(src, prefix):
    for f in sorted(os.listdir(src)):
        if f.startswith(prefix):
            return os.path.join(src, f)
    raise SystemExit('missing ' + prefix)

def build_discs(src, out_dir, report):
    os.makedirs(out_dir, exist_ok=True)
    for prefix, cols, rows, special, names in DISC_SHEETS:
        img = Image.open(find(src, prefix)).convert('RGBA')
        cs = cells(img, cols, rows, special)
        for name, cell in zip(names, cs):
            d, fit = disc_from_cell(cell)
            d.save(os.path.join(out_dir, name + '.webp'), quality=86, method=3)
            report[name] = [round(v, 1) for v in fit]
    img = Image.open(find(src, PUCK_SHEET[0])).convert('RGBA')
    centres = [(217, 160), (509, 160), (980, 151), (1267, 151), (217, 480), (509, 480), (980, 480), (1267, 480),
               (217, 807), (509, 807), (980, 807), (1267, 807)]
    for name, (x, y) in zip(PUCK_SHEET[1], centres):
        crop = img.crop((x - 150, y - 150, x + 150, y + 150))
        d, fit = disc_from_cell(crop, 55)
        if not (125 <= fit[2] <= 132 and 118 <= fit[3] <= 135):  # dark faces need a lower threshold
            d, fit = disc_from_cell(crop, 30)
        d.save(os.path.join(out_dir, name + '.webp'), quality=86, method=3)
        report[name] = [round(v, 1) for v in fit]

def renorm_existing(team_dir, report):
    for f in sorted(os.listdir(team_dir)):
        if not f.endswith('.webp') or not f[:3] in ('car', 'clu', 'lux', 'nat', 'spt'):
            continue
        p = os.path.join(team_dir, f)
        a = np.array(Image.open(p).convert('RGBA'))
        m = a[:, :, 3] > 128
        m = nd.binary_fill_holes(m)
        cx, cy, rx, ry = fit_ellipse(m)
        rgb = a.copy()
        rgb[:, :, :3] = (a[:, :, :3] * (a[:, :, 3:4] / 255.0)).astype(np.uint8)
        rgb[:, :, 3] = 255
        normalize(rgb, cx, cy, rx, ry, DISC_S, DISC_R).save(p, quality=88, method=3)
        report[f[:-5]] = [round(v, 1) for v in (cx, cy, rx, ry)]

def build_ball(path, out_png, report_key, report):
    img = Image.open(path).convert('RGBA')
    frames = []
    for c in cells(img, 4, 4):
        a = np.array(c)
        a[:, :, 3] = 255
        cx, cy, rx, ry = fit_small(a, thr=45, close=2, maxdim=160)
        r = (rx + ry) / 2  # balls are spheres: one radius
        frames.append(normalize(a, cx, cy, r, r, BALL_S, BALL_R))
    strip = Image.new('RGBA', (BALL_S * 16, BALL_S))
    for i, f in enumerate(frames):
        strip.paste(f, (i * BALL_S, 0))
    strip.save(out_png, quality=86, method=3)
    frames[0].save(out_png.replace('_16.webp', '_thumb.webp'), quality=88, method=3)
    report[report_key] = len(frames)

def renorm_ball_strip(path, n, out_png):
    img = Image.open(path).convert('RGBA'); fw = img.width // n
    strip = Image.new('RGBA', (BALL_S * n, BALL_S))
    for i in range(n):
        a = np.array(img.crop((i * fw, 0, (i + 1) * fw, img.height)))
        m = a[:, :, 3] > 128
        cx, cy, rx, ry = fit_ellipse(nd.binary_fill_holes(m))
        r = (rx + ry) / 2
        rgb = a.copy(); rgb[:, :, :3] = (a[:, :, :3] * (a[:, :, 3:4] / 255.0)).astype(np.uint8); rgb[:, :, 3] = 255
        strip.paste(normalize(rgb, cx, cy, r, r, BALL_S, BALL_R), (i * BALL_S, 0))
    strip.save(out_png, quality=86, method=3)

if __name__ == '__main__':
    src, root = sys.argv[1], sys.argv[2]
    rep = {}
    team_dir = os.path.join(root, 'assets/games/bermuda/teams')
    if '--existing' in sys.argv:
        renorm_existing(team_dir, rep)
    build_discs(src, os.path.join(root, 'assets/games/bermuda/discs'), rep)
    bdir = os.path.join(root, 'assets/games/bermuda/balls')
    for prefix, name in BALL_SHEETS:
        build_ball(find(src, prefix), os.path.join(bdir, name + '_16.webp'), name, rep)
    if '--existing' in sys.argv:
        renorm_ball_strip(os.path.join(root, 'assets/games/finger_soccer/nx_ball_test_16.webp'), 16,
                          os.path.join(bdir, 'anix_spin_16.webp'))
    json.dump(rep, open('/tmp/fs_assets_report.json', 'w'), indent=1)
    print('ok', len(rep))
