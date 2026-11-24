#!/usr/bin/env python3
"""Finger soccer v11 pitch builder (owner art 2026-11-23): the owner's five pitches replace the three v9 ones.

Inputs: the owner's uploads (default directory: ../files/uploads relative to the repo, or argv[1]), five PNGs of
1086 x 1448 px each (see PITCHES). Every art has its goals and nets drawn at the top and bottom and two vertical score
displays (a printed "00" each) on the left / right frame.

Outputs:
  assets/games/bermuda/fields/<id>.webp   the full art; the printed "00" digits erased (the live score is drawn there)
                                          and, between the rails only, rows remapped so the drawn halfway line sits
                                          exactly halfway between the two goal lines (the engine's kickoff spot)
  assets/games/bermuda/thumbs/<id>.webp   240 x 320 picker thumbs
  build/fs_v11/<id>_overlay.png           the measured boundary, corners, posts, nets and digit boxes over the art
  stdout                                  the BmField / BmScoreDisplay rows for lib/games/finger_soccer/core/bm_data.dart

What is measured on every art (image px):
  rails    the inner edge of the frame's bright rail line on all four sides (the line the ball bounces on). Each art has
           its own rail colour test (RAIL); the edge is the most common first-rail pixel over ~120 rows / ~90 columns,
           scanned from inside the field outward, so field lines, graffiti and floor highlights are voted out.
  corner   the rail edge traced along the 70 rows / columns next to each corner, fitted with a quarter circle tangent
           to both rails; the engine has one radius, the median of the four corners.
  posts    the white tubes: centre of the widest bright run per row along each tube, a straight line fitted through
           those centres and read on the goal line; radius = half the median tube width. The engine places both posts
           symmetric about the field's centre line, so the four post offsets are averaged.
  nets     the back bar of each goal (rows that are white across the goal's middle); depth = goal line -> the bar's
           inner edge. The engine keeps both goals the same depth (online mirrored phones stay deterministic), so the
           shallower of the two drawn goals is used: the ball never shows through a back bar.
  digits   the two "0" glyphs of each display (connected bright components of digit size, stacked vertically): centre x,
           tens / ones centre y, and the glyph's core box (the seven-segment painter's cell).
Scale: one raw unit = 1 / kBmV11ArtScale px with kBmV11ArtScale = W0 / 1086, chosen so the playing width stays ~880
world units (the v9 proportions: discs ~0.12 of the width). The engine walls sit 4 world units inside the raw
boundary (BmEngine.geo: Fl = L + 4), so the raw values are offset by that much and the walls land on the drawn rail.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(REPO), 'files', 'uploads')
A = os.path.join(REPO, 'assets', 'games', 'bermuda')
OVER = os.path.join(REPO, 'build', 'fs_v11')

ART_W, ART_H = 1086, 1448
W0 = 810  # raw width of every art; H0 keeps the art's aspect
H0 = round(ART_H * W0 / ART_W)
FS = 1.12 * 1.215  # bm_engine.dart FS
WW, WH = round(W0 * FS), round(H0 * FS)  # world size of the art (BmFieldS.W / H)
KX, KY = WW / ART_W, WH / ART_H  # art px -> world


def _lum(a):
    return a.mean(axis=2)


def _sat(a):
    return a.max(axis=2) - a.min(axis=2)


# Rail colour test per art (True = frame rail pixel). Picked by looking at each art's edge at 5x (silver, gold, neon).
RAIL = {
    # silver / copper rail on green checker grass: bright and not grass-green
    'checker': lambda a: (_lum(a) >= 100) & ~((a[..., 1] > a[..., 0] + 40) & (a[..., 1] > a[..., 2] + 40)),
    # thin white / neon-green line on dark ring grass
    'rings': lambda a: (_lum(a) >= 95) | (a[..., 1] >= 200),
    # silver rail, yellow / black hazard strip in the middle of the long sides, on dark asphalt
    'street': lambda a: ((_lum(a) >= 140) & (_sat(a) < 60)) | ((a[..., 0] >= 170) & (a[..., 1] >= 120) & (a[..., 2] < 100)),
    # gold / cyan / white rail on a saturated blue floor (the floor never has red, nor green >= 200)
    'neon': lambda a: (a[..., 0] >= 120) | (a[..., 1] >= 200),
    # white rail on green grass
    'royal': lambda a: _lum(a) >= 110,
}

# The corners are traced with the same test except on the street art, whose corners are plain silver (the yellow test
# would pick up the yellow graffiti that runs into the top-left corner).
RAIL_CORNER = {'street': lambda a: (_lum(a) >= 140) & (_sat(a) < 60)}
# The royal art's white touch line meets at square corners (checked at 6x); the white quarter circles just inside
# them are corner-arc markings on the grass, not barrier, and the trace above would follow them. Square = radius 0.
CORNER_FIXED = {'royal': 0.0}

# id, upload, English name, Persian name, rail test, live-score colours (left, right), goal fx (k, colours)
PITCHES = [
    ('nx_checker_silver', '142802-1fc3c09b0f2a.png', 'Silver Checker', 'شطرنجی نقره‌ای', 'checker'),
    ('nx_rings_green', '142803-210da3b8b913.png', 'Green Rings', 'حلقه‌های سبز', 'rings'),
    ('nx_street', '142804-a3e4ccc17d58.png', 'Street', 'خیابانی', 'street'),
    ('nx_neon_blue', '142805-2a70fddf8b27.png', 'Neon Blue', 'نئون آبی', 'neon'),
    ('nx_royal_purple', '142810-b71f449ca52e.png', 'Royal Purple', 'سلطنتی بنفش', 'royal'),
]


def _mode(vals):
    v = [x for x in vals if x is not None]
    if not v:
        raise ValueError('no rail found')
    c = np.bincount(np.array(v))
    return int(np.argmax(c))


def _first(line, start, step, n):
    """Index of the first rail pixel (two in a row) walking from [start] by [step]."""
    for k in range(n):
        i = start + k * step
        if line[i] and line[i + step]:
            return i
    return None


def measure_rails(rail):
    rows = list(range(200, 680, 4)) + list(range(780, 1260, 4))  # clear of the halfway line and the penalty areas
    cols = list(range(150, 290, 3)) + list(range(800, 936, 3))  # clear of the goals and the penalty box sides
    L = _mode([_first(rail[y], 160, -1, 100) for y in rows]) + 1  # first field column
    R = _mode([_first(rail[y], 926, 1, 100) for y in rows])  # first rail column on the right
    T = _mode([_first(rail[:, x], 170, -1, 140) for x in cols]) + 1
    B = _mode([_first(rail[:, x], 1278, 1, 140) for x in cols])
    return L, R, T, B  # boundary lines (pixel edges): field = [L, R) x [T, B)


def measure_corner(rail, L, R, T, B):
    """Corner radius: per corner, the rail edge is traced along the 70 rows and 70 columns nearest the corner (first
    rail pixel walking out of the field, as for the straight rails) and the quarter circle tangent to both rails that
    fits those edges best is kept. The engine has one radius for all four corners (online mirroring), so the median."""
    rs = []
    for (sx, sy) in ((1, 1), (-1, 1), (1, -1), (-1, -1)):
        x0 = L if sx > 0 else R - 1  # first field column / row next to the corner
        y0 = T if sy > 0 else B - 1
        pts = []  # (distance from the corner along the rail, inset of the rail edge into the field)
        for j in range(0, 70):
            line = rail[y0 + sy * j]
            o = next((o for o in range(90, -2, -1) if line[x0 + sx * o] and line[x0 + sx * (o - 1)]), None)
            if o is not None:
                pts.append((j, o + 1))
            col = rail[:, x0 + sx * j]
            o = next((o for o in range(90, -2, -1) if col[y0 + sy * o] and col[y0 + sy * (o - 1)]), None)
            if o is not None:
                pts.append((j, o + 1))
        best = None
        for r in np.arange(0, 90, .5):
            err = []
            for j, m in pts:
                jj = j + .5
                pred = r - math.sqrt(max(0, r * r - (r - jj) ** 2)) if jj < r else 0
                err.append(abs(pred - m))
            e = float(np.median(err)) + float(np.mean(err)) * .2
            if best is None or e < best[0]:
                best = (e, float(r))
        rs.append(best[1])
    return float(np.median(rs)), rs


def _runs(mask, off):
    out, s = [], None
    for i, v in enumerate(mask):
        if v and s is None:
            s = i
        if not v and s is not None:
            out.append((s + off, i - 1 + off))
            s = None
    if s is not None:
        out.append((s + off, len(mask) - 1 + off))
    return out


def measure_goal(a, top, line):
    """Back bar inner edge and the two post tubes of one goal. [line] = its goal line (T or B)."""
    white = (a.min(axis=2) >= 150)
    mid = white[:, 470:616].mean(axis=1)
    if top:
        bar = [y for y in range(0, line - 20) if mid[y] > .8]
        back = max(y for y in bar if y < 40) + 1  # inner (field side) edge of the back bar
        rows = range(back + 4, line - 6)
    else:
        bar = [y for y in range(line + 20, ART_H) if mid[y] > .8]
        back = min(y for y in bar if y > ART_H - 40)
        rows = range(line + 6, back - 4)
    tube = (_lum(a) >= 110) & (_sat(a) < 110)
    posts = []
    for (x0, x1, guess) in ((360, 440, 405), (646, 726, 687)):
        ys, cs, ws = [], [], []
        for y in rows:
            rr = [r for r in _runs(tube[y, x0:x1], x0) if r[1] - r[0] >= 6]
            if not rr:
                continue
            r = min(rr, key=lambda r: abs((r[0] + r[1]) / 2 - guess))
            if r[1] - r[0] > 18:  # merged with a bar: skip the row
                continue
            ys.append(y)
            cs.append((r[0] + r[1] + 1) / 2)
            ws.append(r[1] - r[0] + 1)
        p = np.polyfit(ys, cs, 1)
        posts.append((float(np.polyval(p, line)), float(np.median(ws)) / 2, float(np.percentile(ws, 90)) / 2))
    return back, posts


def measure_digits(a):
    out = []
    for (x0, x1) in ((0, 150), (936, 1086)):
        sub = a[560:900, x0:x1]
        lab, _ = ndimage.label(sub.max(axis=2) >= 150)
        cand = []
        for i, sl in enumerate(ndimage.find_objects(lab)):
            h, w = sl[0].stop - sl[0].start, sl[1].stop - sl[1].start
            fill = (lab[sl] == i + 1).mean()
            if 25 <= h <= 70 and 15 <= w <= 60 and .9 <= h / w <= 2.2 and fill > .5:
                cand.append((sl[1].start + x0, sl[0].start + 560, sl[1].stop - 1 + x0, sl[0].stop - 1 + 560, i + 1, sl))
        assert len(cand) == 2, cand
        cand.sort(key=lambda c: c[1])
        boxes = []
        for (bx0, by0, bx1, by1, li, sl) in cand:
            m = np.zeros(a.shape[:2], bool)
            m[560:900, x0:x1] = lab == li
            core = m & (a.max(axis=2) >= 225)
            ys, xs = np.nonzero(core)
            boxes.append(dict(glow=(bx0, by0, bx1, by1), core=(int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())),
                              mask=m))
        out.append(boxes)
    return out


def glyph_colour(a, boxes):
    """The printed digits' colour: median of the glyph pixels in the 200..239 brightness band (the lit segment body,
    between the dim glow and the white-hot core), scaled to full brightness. The painter adds its own white core
    and glow around it, like the art."""
    px = np.concatenate([a[b['mask']] for b in boxes])
    mx = px.max(axis=1)
    c = np.median(px[(mx >= 200) & (mx < 240)], axis=0)
    c = c * (255 / max(1, c.max()))
    return '0xFF%02X%02X%02X' % tuple(int(round(v)) for v in c)


def halfway_line(a, L, R):
    w = a.min(axis=2) >= 150
    p = w[600:850, L + 30:L + 220].mean(axis=1)
    rows = [y + 600 for y, v in enumerate(p) if v > .5]
    return (rows[0] + rows[-1] + 1) / 2, rows


def remap_rows(im, L, R, T, B, src_mid, dst_mid):
    """Piecewise-linear vertical remap of the field columns [L, R) only (the frame, goals and displays stay as drawn)."""
    a = np.asarray(im).astype(np.float32)
    out = a.copy()
    for y in range(T, B):
        yc = y + .5
        if yc <= dst_mid:
            sy = T + (yc - T) * (src_mid - T) / (dst_mid - T)
        else:
            sy = src_mid + (yc - dst_mid) * (B - src_mid) / (B - dst_mid)
        sy -= .5
        y0 = int(math.floor(sy))
        f = sy - y0
        y1 = min(y0 + 1, a.shape[0] - 1)
        out[y, L:R] = a[y0, L:R] * (1 - f) + a[y1, L:R] * f
    return Image.fromarray(np.clip(out + .5, 0, 255).astype(np.uint8))


def erase_digits(im, digits):
    """Paint the display glass over the printed glyphs and all of their glow (a feathered box around each glyph), so
    only the live score shows on the displays."""
    a = np.asarray(im).astype(np.float32)
    for side in digits:
        for b in side:
            x0, y0, x1, y1 = b['glow']
            box = a[y0 - 10:y1 + 11, x0 - 10:x1 + 11].reshape(-1, 3)
            lum = box.sum(axis=1)
            glass = np.median(box[lum <= np.percentile(lum, 25)], axis=0)
            m = np.zeros(a.shape[:2], np.float32)
            m[y0 - 5:y1 + 6, x0 - 5:x1 + 6] = 1
            alpha = np.clip(ndimage.gaussian_filter(m, 2.0) * 1.15, 0, 1)[..., None]
            a = a * (1 - alpha) + glass[None, None, :] * alpha
    return Image.fromarray(np.clip(a + .5, 0, 255).astype(np.uint8))


def raw_x(px, wall):
    """Image x of a wall -> raw unit such that the engine wall (round(raw * FS) -/+ 4) lands on it."""
    return round((px * KX + 4 * wall) / FS)


def raw_y(px, wall):
    return round((px * KY + 4 * wall) / FS)


def build():
    os.makedirs(os.path.join(A, 'fields'), exist_ok=True)
    os.makedirs(os.path.join(A, 'thumbs'), exist_ok=True)
    os.makedirs(OVER, exist_ok=True)
    rows_out = []
    for pid, fn, name, fa, rk in PITCHES:
        im = Image.open(os.path.join(SRC, fn)).convert('RGB')
        assert im.size == (ART_W, ART_H), im.size
        a = np.asarray(im).astype(int)
        rail = RAIL[rk](a)
        L, R, T, B = measure_rails(rail)
        rad, ds = (CORNER_FIXED[rk], []) if rk in CORNER_FIXED else measure_corner(RAIL_CORNER[rk](a) if rk in RAIL_CORNER else rail, L, R, T, B)
        backT, postsT = measure_goal(a, True, T)
        backB, postsB = measure_goal(a, False, B)
        digits = measure_digits(a)
        cx = (L + R) / 2
        offs = [cx - postsT[0][0], postsT[1][0] - cx, cx - postsB[0][0], postsB[1][0] - cx]
        gh = float(np.mean(offs))
        gr = float(np.median([p[1] for p in postsT + postsB]))
        depth_t, depth_b = T - backT, backB - B
        depth = min(depth_t, depth_b)
        mid, mrows = halfway_line(a, L, R)
        dst_mid = (T + B) / 2
        cols = (glyph_colour(a, digits[0]), glyph_colour(a, digits[1]))
        # ---- art
        out = im
        if abs(mid - dst_mid) > .75:
            out = remap_rows(out, L, R, T, B, mid, dst_mid)
        out = erase_digits(out, digits)
        out.save(os.path.join(A, 'fields', pid + '.webp'), 'WEBP', quality=86, method=6)
        out.resize((240, 320), Image.LANCZOS).save(os.path.join(A, 'thumbs', pid + '.webp'), 'WEBP', quality=82, method=6)
        mid2, _ = halfway_line(np.asarray(out).astype(int), L, R)
        # ---- digit geometry (core boxes)
        def disp(side):
            t, o = side[0]['core'], side[1]['core']
            dcx = (t[0] + t[2] + o[0] + o[2] + 2) / 4
            return dcx, (t[1] + t[3] + 1) / 2, (o[1] + o[3] + 1) / 2, max(t[2] - t[0], o[2] - o[0]) + 1, max(t[3] - t[1], o[3] - o[1]) + 1
        dl, dr = disp(digits[0]), disp(digits[1])
        sd = dict(leftCx=dl[0], rightCx=dr[0], tensCy=(dl[1] + dr[1]) / 2, onesCy=(dl[2] + dr[2]) / 2,
                  digitW=(dl[3] + dr[3]) / 2, digitH=(dl[4] + dr[4]) / 2, tensL=dl[1], tensR=dr[1])
        # ---- raw values
        l0, r0, t0, b0 = raw_x(L, -1), raw_x(R, 1), raw_y(T, -1), raw_y(B, 1)
        k_raw = KX / FS  # art px -> raw (x); y differs from x by < 0.05%
        rec = dict(id=pid, name=name, fa=fa, L=L, R=R, T=T, B=B, corner_d=ds, corner_r_px=round(rad, 1),
                   posts_top=[(round(p[0], 1), round(p[1], 1)) for p in postsT],
                   posts_bot=[(round(p[0], 1), round(p[1], 1)) for p in postsB], gh_px=round(gh, 2), gr_px=gr,
                   back_top=backT, back_bot=backB, depth_top=depth_t, depth_bot=depth_b, depth=depth,
                   mid_drawn=mid, mid_rows=(mrows[0], mrows[-1]), mid_target=dst_mid, mid_after=mid2, score=sd,
                   colours=cols, w0=W0, h0=H0, l0=l0, r0=r0, t0=t0, b0=b0, cs0=round((t0 + b0) / 2),
                   rc=round(rad * KX, 1), gh0=round(gh * k_raw, 2), gr0=round(gr * k_raw, 2), gd0=round(depth * KY / FS, 2))
        rows_out.append(rec)
        overlay(out, rec, digits)
        print(rec)
    print()
    for r in rows_out:
        s = r['score']
        print(f"  BmField('{r['id']}', '{r['name']}', {r['w0']}, {r['h0']}, {r['l0']}, {r['r0']}, {r['t0']}, {r['b0']}, "
              f"{r['cs0']}, 0, 'none',\n      rc: {r['rc']}, gh0: {r['gh0']}, gr0: {r['gr0']}, gd0: {r['gd0']}, "
              f"faName: '{r['fa']}',\n      score: BmScoreDisplay({ART_W}, {s['leftCx']}, {s['rightCx']}, {s['tensCy']}, "
              f"{s['onesCy']}, {s['digitW']}, {s['digitH']}),\n      scoreLeft: Color({r['colours'][0]}), "
              f"scoreRight: Color({r['colours'][1]})),")


def overlay(im, r, digits):
    """The measured geometry over the art (what the engine will collide with), for visual checking."""
    o = im.convert('RGB').copy()
    d = ImageDraw.Draw(o)
    L, R, T, B = r['L'], r['R'], r['T'], r['B']
    rad = r['corner_r_px']
    d.rounded_rectangle((L, T, R - 1, B - 1), radius=max(0, int(round(rad))), outline=(255, 0, 0), width=2)
    cx = (L + R) / 2
    gh, gr = r['gh_px'], r['gr_px']
    for y, sgn in ((T, -1), (B, 1)):
        for px in (cx - gh, cx + gh):
            d.ellipse((px - gr, y - gr, px + gr, y + gr), outline=(0, 255, 255), width=2)
        back = y + sgn * r['depth']
        d.line([(cx - gh + gr, y), (cx - gh + gr, back), (cx + gh - gr, back), (cx + gh - gr, y)], fill=(255, 255, 0), width=2)
    d.line([(L, (T + B) / 2), (R, (T + B) / 2)], fill=(255, 0, 255), width=1)
    s = r['score']
    for c in (s['leftCx'], s['rightCx']):
        for cy in (s['tensCy'], s['onesCy']):
            d.rectangle((c - s['digitW'] / 2, cy - s['digitH'] / 2, c + s['digitW'] / 2, cy + s['digitH'] / 2),
                        outline=(255, 128, 0), width=2)
    o.save(os.path.join(OVER, r['id'] + '_overlay.png'))


if __name__ == '__main__':
    build()
