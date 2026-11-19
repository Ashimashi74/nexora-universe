#!/usr/bin/env python3
"""Owner UI pack (2026-11-19, 15 images) -> app assets.

* Pedestal sheets (already cut out, alpha ~0 / ~252): split into connected components, alpha cleaned (faint haze < 14
  dropped, solid >= 240 made opaque, light fringe pixels de-whitened), trimmed and saved 384 px wide into
  assets/arcade/pedestals/<gameId>.webp - the art used by every games list, game setup page and the room game picker.
* Trophy sheet -> assets/ui/anix/trophies/<tier>.webp, icon grid (6x5, dark bg) -> assets/ui/anix/icons/<name>.webp
  (dark backdrop keyed to alpha), scene backgrounds -> assets/ui/anix/scenes/<name>.webp (1080 px tall max).
Usage: python3 tool/build_ui_assets.py <dir with the 15 images> <repo root>
"""
import os, sys
import numpy as np
from PIL import Image, ImageFile
from scipy import ndimage as nd
ImageFile.LOAD_TRUNCATED_IMAGES = True

def find(src, prefix):
    for f in sorted(os.listdir(src)):
        if f.startswith(prefix):
            return os.path.join(src, f)
    raise SystemExit('missing ' + prefix)

def clean_alpha(a):
    a = a.astype(float)
    al = a[:, :, 3]
    al[al < 14] = 0
    al[al >= 240] = 255
    # de-white fringe: semi-transparent pixels that are much lighter than their opaque neighbours get darkened
    semi = (al > 0) & (al < 240)
    lum = a[:, :, :3].mean(2)
    fringe = semi & (lum > 200)
    a[fringe, :3] *= 0.55
    a[:, :, 3] = al
    return a.astype(np.uint8)

def components(a, min_area):
    m = a[:, :, 3] > 60
    m = nd.binary_closing(m, iterations=4)
    lab, n = nd.label(m)
    boxes = []
    for i, sl in enumerate(nd.find_objects(lab)):
        if (lab[sl] == i + 1).sum() >= min_area:
            boxes.append((sl[1].start, sl[0].start, sl[1].stop, sl[0].stop))
    h = a.shape[0]
    boxes.sort(key=lambda b: (int(((b[1] + b[3]) / 2) / (h / 2)), b[0]))  # two rows: top row first, then left->right
    return boxes

PEDESTALS = {
    '142312': ['carrom', 'finger_soccer', 'snakes_ladders', None, 'backgammon', 'billiards'],
    '142313': ['traffic_racer', 'chess_blitz', None, 'ludo', 'mafia', 'pool8'],
    '142314': ['spy_mafia', 'quiz', 'uno', 'bomb_arena', 'obstacle_race', None],
    '142315': ['basketball_battle', 'mini_golf', None, 'ludo_battle', 'kart_racing'],
}

def build_pedestals(src, root):
    out = os.path.join(root, 'assets/arcade/pedestals')
    for prefix, names in PEDESTALS.items():
        a = np.array(Image.open(find(src, prefix)).convert('RGBA'))
        a = clean_alpha(a)
        boxes = components(a, 15000)
        assert len(boxes) == len(names), (prefix, len(boxes))
        for name, (x0, y0, x1, y1) in zip(names, boxes):
            if not name:
                continue
            im = Image.fromarray(a[max(0, y0 - 4):y1 + 4, max(0, x0 - 4):x1 + 4])
            im.thumbnail((384, 384), Image.LANCZOS)
            im.save(os.path.join(out, name + '.webp'), quality=88, method=4)
            print('pedestal', name, im.size)

def key_dark(a, lo=18, hi=60):
    """Dark backdrop -> alpha (for art painted on near-black)."""
    a = a.astype(float)
    v = a[:, :, :3].max(2)
    al = np.clip((v - lo) / (hi - lo), 0, 1) * 255
    out = np.dstack([a[:, :, :3], al]).astype(np.uint8)
    return out

def build_trophies(src, root):
    a = np.array(Image.open(find(src, '142291')).convert('RGBA'))
    if (a[:, :, 3] < 250).mean() < 0.05:
        a = key_dark(a)
    a = clean_alpha(a)
    boxes = components(a, 20000)
    names = ['bronze', 'silver', 'gold', 'amethyst', 'champion', 'diamond']
    for name, (x0, y0, x1, y1) in zip(names, boxes):
        im = Image.fromarray(a[y0:y1, x0:x1]); im.thumbnail((256, 256), Image.LANCZOS)
        im.save(os.path.join(root, 'assets/ui/anix/trophies', name + '.webp'), quality=88, method=4)
    print('trophies', len(boxes))

ICONS = ['pool', 'poker', 'soccer', 'backgammon', 'roulette', 'chess',
         'snake', 'ludo', 'cards', 'mafia', 'trophy_gold', 'leaderboard',
         'mic', 'headset', 'chat', 'friends', 'calendar', 'gift',
         'shop', 'settings', 'star', 'shield', 'gamepad', 'versus',
         'rocket', 'target', 'megaphone', 'cup', 'joystick', 'wheel']

def build_icons(src, root):
    img = Image.open(find(src, '142310')).convert('RGB')
    W, H = img.size
    for j in range(5):
        for i in range(6):
            c = np.array(img.crop((int(W * i / 6), int(H * j / 5), int(W * (i + 1) / 6), int(H * (j + 1) / 5))).convert('RGBA'))
            # the grid sits on a star-field: key everything outside the icon's main blob
            k = key_dark(c, 45, 95)
            m = nd.binary_fill_holes(nd.binary_closing(k[:, :, 3] > 100, iterations=3))
            lab, n = nd.label(m)
            if n:
                sizes = nd.sum(m, lab, range(1, n + 1)); keep = lab == (int(np.argmax(sizes)) + 1)
                keep = nd.binary_dilation(keep, iterations=3)
                al = np.where(keep, np.maximum(k[:, :, 3], (nd.binary_erosion(keep, iterations=6) * 255)), 0)
                c[:, :, 3] = nd.uniform_filter(al.astype(float), 2).astype(np.uint8)
            ys, xs = np.where(c[:, :, 3] > 20)
            im = Image.fromarray(c[ys.min():ys.max() + 1, xs.min():xs.max() + 1])
            im.thumbnail((160, 160), Image.LANCZOS)
            im.save(os.path.join(root, 'assets/ui/anix/icons', ICONS[j * 6 + i] + '.webp'), quality=88, method=4)
    print('icons', len(ICONS))

SCENES = {'142298': 'portal_blue', '142299': 'portal_gold', '142306': 'voice_stage'}

def build_scenes(src, root):
    for prefix, name in SCENES.items():
        im = Image.open(find(src, prefix)).convert('RGB')
        im.thumbnail((720, 1280), Image.LANCZOS)
        im.save(os.path.join(root, 'assets/ui/anix/scenes', name + '.webp'), quality=80, method=4)
    # wide hub panorama (top strip of the 142294 sheet)
    im = Image.open(find(src, '142294')).convert('RGB')
    W, H = im.size
    pano = im.crop((0, 0, W, int(H * 0.36)))
    pano.thumbnail((1280, 720), Image.LANCZOS)
    pano.save(os.path.join(root, 'assets/ui/anix/scenes', 'hub_panorama.webp'), quality=80, method=4)
    im = Image.open(find(src, '142307')).convert('RGB')
    W, H = im.size
    arena = im.crop((0, 0, W, int(H * 0.29)))
    arena.thumbnail((1280, 720), Image.LANCZOS)
    arena.save(os.path.join(root, 'assets/ui/anix/scenes', 'trophy_hall.webp'), quality=80, method=4)
    print('scenes')

if __name__ == '__main__':
    src, root = sys.argv[1], sys.argv[2]
    build_pedestals(src, root)
    build_trophies(src, root)
    build_icons(src, root)
    build_scenes(src, root)
