#!/usr/bin/env python3
"""Disc art audit: every team id in src/core/data.gd CATS -> its image (TEAM_IMG, else assets/g/teams/<key>.webp),
checked for a clean round coin: alpha circularity (IoU with the best circle), edge roughness (radial std of the alpha
edge), centring (mask centroid / bbox centre vs image centre) and coverage.  Prints JSON {bad:[...], stats}.
Usage: python3 tests/tools/disc_audit.py [project_root] [--verbose]"""
import sys, os, re, json, math, ast
import numpy as np
from PIL import Image
root = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith('-') else os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
src = open(os.path.join(root, 'src/core/data.gd'), encoding='utf-8').read()
cats = ast.literal_eval(re.search(r'^const CATS := (\[.*\])$', src, re.M).group(1))
timg = dict(re.findall(r'^\t"(\w+)": "res://(assets/[^"]+)",$', src[src.index('const TEAM_IMG'):src.index('const BALL_IMG')], re.M))

def check(path):
    im = Image.open(path).convert('RGBA'); w, h = im.size
    a = np.asarray(im)[..., 3].astype(np.float32) / 255.0
    m = a > 0.5
    area = m.sum()
    if area < 50: return {'ok': False, 'why': 'empty'}
    ys, xs = np.nonzero(m)
    cx, cy = xs.mean(), ys.mean()
    r = math.sqrt(area / math.pi)
    # IoU with circle of same area at the centroid
    Y, X = np.mgrid[0:h, 0:w]
    circ = (X + 0.5 - cx - 0.5) ** 2 + (Y + 0.5 - cy - 0.5) ** 2 <= r * r
    iou = (m & circ).sum() / max(1, (m | circ).sum())
    # radial edge profile over 180 angles
    rs = []
    for k in range(180):
        t = k * math.pi / 90
        dx, dy = math.cos(t), math.sin(t)
        last = 0.0
        for s in np.arange(0, max(w, h), 0.5):
            px, py = int(cx + dx * s), int(cy + dy * s)
            if px < 0 or py < 0 or px >= w or py >= h: break
            if m[py, px]: last = s
        rs.append(last)
    rs = np.array(rs)
    rough = float(rs.std() / max(1.0, rs.mean()))
    jag = float((np.abs(np.diff(np.r_[rs, rs[:1]])).max()) / max(1.0, rs.mean()))
    # visible silhouette: the coin as the eye sees it (alpha AND not near-black). Gear/jagged rims cut onto a dark
    # backing show up here as a ragged outer edge even when the alpha itself is a perfect circle.
    vis = m & (np.asarray(im)[..., :3].max(-1) > 23)
    vr = []
    for k in range(360):
        t = k * math.pi / 180
        dx, dy = math.cos(t), math.sin(t)
        last = 0.0
        for s in np.arange(r * 0.5, r * 1.05, 0.5):
            px, py = int(cx + dx * s), int(cy + dy * s)
            if 0 <= px < w and 0 <= py < h and vis[py, px]: last = s
        vr.append(last / r)
    vr = np.array(vr)
    vstd = float(vr.std())
    off = math.hypot(cx - (w - 1) / 2, cy - (h - 1) / 2) / max(1.0, r)
    cover = r / (min(w, h) / 2)
    why = []
    if iou < 0.965: why.append('not-circular iou=%.3f' % iou)
    if rough > 0.03: why.append('rough edge std=%.3f' % rough)
    if jag > 0.08: why.append('jagged edge step=%.3f' % jag)
    if vstd > 0.025: why.append('ragged visible rim std=%.3f' % vstd)
    if off > 0.05: why.append('off-centre %.3f' % off)
    if cover < 0.72: why.append('small/padded cover=%.2f' % cover)
    if abs(w - h) > max(w, h) * 0.04: why.append('non-square %dx%d' % (w, h))
    return {'ok': not why, 'why': ', '.join(why), 'iou': round(float(iou), 4), 'rough': round(rough, 4), 'jag': round(jag, 4), 'off': round(off, 4), 'cover': round(cover, 3), 'vstd': round(vstd, 4), 'size': [w, h]}

# Manual art review of the automatic 'ragged visible rim' flag (2026-11-13): these are clean round coins whose rim is
# simply dark (black glossy coins) or a segmented neon ring inside a round rim -> kept.
REVIEWED_KEEP = {'lux10', 'club30', 'club52', 'club59', 'spt10', 'spt12', 'spt16', 'spt18', 'gal8', 'gal12', 'gal15',
	'vip2', 'vip5', 'vip7', 'vip11', 'emb0', 'emb4', 'emb7', 'emb12', 'emb15'}
# Manual review: the whole 'elite' set (gear rims cut by the alpha circle, art off-centre — e.g. Al Nassr) and the
# 'chrome' set (logo swooshes on black, rim cut, not a coin) are removed even where a single metric passes.
REVIEWED_REMOVE_CATS = {'elite', 'chrome'}
out = {'bad': [], 'ok': 0, 'missing': []}
for c in cats:
    k = c[0]
    for i, name in enumerate(c[2]):
        key = '%s%02d' % (k, i)
        p = timg.get(key, '')
        if not p or not os.path.exists(os.path.join(root, p)): p = 'assets/g/teams/%s.webp' % key
        fp = os.path.join(root, p)
        if not os.path.exists(fp): out['missing'].append(key); continue
        r = check(fp)
        if r['ok']: out['ok'] += 1
        else: out['bad'].append({'id': k + str(i), 'key': key, 'name': name, 'file': p, **r})
        if '--verbose' in sys.argv: print(key, name, r)
rm = sorted({b['id'] for b in out['bad'] if b['id'] not in REVIEWED_KEEP} |
	{'%s%d' % (c[0], i) for c in cats if c[0] in REVIEWED_REMOVE_CATS for i in range(len(c[2]))}, key=lambda x: (re.sub(r'\d', '', x), int(re.sub(r'\D', '', x))))
out['remove'] = rm
print(json.dumps(out, ensure_ascii=False, indent=1))
