#!/usr/bin/env python3
"""Finger soccer v10 asset builder (owner art 2026-11-22).

Inputs: tool/inputs/teams_2026_11_22/ (20 PNGs; see docs/anix_pro/TEAM_ART_INPUTS.md).
Outputs (webp):
  assets/games/bermuda/discs/v10/<slug>.webp   256 x 256, badge rim exactly at radius 120 (kBmDiscArtFill)
  assets/basketball/arena.webp                 900 x 1600, the owner's arena
  assets/basketball/*.webp                     ball, hoop, player_a, player_b, fx_spark, fx_ring, scoreboard, cup, medal, shield
  assets/ui/anix/scenes/nexora_stage.webp      1568 x 880, the NEXORA stage hero

Every disc is cut with the same rule as v9 (tool/build_fs_v9_assets.py): the badge's tight box is found on a
luminance mask, the box's inscribed circle becomes the sprite's outer rim at radius 120 of 256, and the sprite is
faded to alpha outside it. So kBmDiscArtFill = 120 / 128 keeps holding for every new badge.

The sheets are 3 x 3 (nine coins) or 3 x 2 (six coins); each cell is tightened independently, so the coins do not
need to be evenly spaced in the source.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, 'tool', 'inputs', 'teams_2026_11_22')
DISC_OUT = os.path.join(REPO, 'assets', 'games', 'bermuda', 'discs', 'v10')

# --------------------------------------------------------------------------------------------- source sheets
# file -> (columns, rows, [slug per cell in reading order])
SHEETS = {
    'Picsart_26-11-03_17-09-22-823.png': (3, 3, ['tottenham', 'atletico', 'dortmund',
                                                'napoli', 'ajax', 'celtic',
                                                'flamengo', 'riverplate', 'alhilal']),
    'Picsart_26-11-03_17-09-51-477.png': (3, 3, ['sevilla', 'leverkusen', 'leipzig',
                                                'marseille', 'lyon', 'galatasaray',
                                                'fenerbahce', 'sporting', 'shakhtar']),
    'Picsart_26-11-03_17-10-17-417.png': (3, 3, ['inter', 'lazio', 'sevilla_ii',
                                                'tottenham_ii', 'wolfsburg', 'persepolis',
                                                'esteghlal', 'alnassr', 'alhilal_ii']),
    'Picsart_26-11-03_17-10-52-817.png': (3, 3, ['intermiami', 'newcastle', 'astonvilla',
                                                'westham', 'everton', 'valencia',
                                                'villarreal', 'fiorentina', 'corinthians']),
    'Picsart_26-11-06_03-46-01-962.png': (3, 3, ['realmadrid', 'barcelona', 'bayern',
                                                'juventus', 'acmilan', 'inter_ii',
                                                'mancity', 'liverpool', 'arsenal']),
    'file_00000000058081f487c8497da8e9daed.png': (3, 2, ['tottenham_iii', 'atletico_ii', 'napoli_ii',
                                                         'roma', 'benfica', 'marseille_ii']),
    'file_00000000172481f4a96cae46e84115fe.png': (3, 2, ['barcelona_ii', 'realmadrid_ii', 'bayern_ii',
                                                         'psg', 'chelsea', 'dortmund_ii']),
    'file_00000000ae8c81f5889a108346740d63.png': (3, 3, ['realmadrid_iii', 'barcelona_iii', 'liverpool_ii',
                                                         'manunited', 'mancity_ii', 'bayern_iii',
                                                         'psg_ii', 'juventus_ii', 'acmilan_ii']),
    'file_000000005a3c8243a0a92cf4d88e246f.png': (3, 2, ['argentina', 'germany', 'belgium',
                                                         'uruguay', 'croatia', 'portugal']),
    'file_00000000642881f48d385bfc7331d799.png': (3, 2, ['italy', 'brazil', 'france',
                                                         'spain', 'england', 'germany_ii']),
    'file_0000000084e081f4bc8812bca285645d.png': (3, 2, ['germany_iii', 'brazil_ii', 'argentina_ii',
                                                         'italy_ii', 'france_ii', 'spain_ii']),
    'file_00000000e81081f4bd8e9a9eee26aac6.png': (3, 2, ['spain_iii', 'portugal_ii', 'england_ii',
                                                         'japan', 'france_iii', 'netherlands']),
    'file_00000000f65c81f48ba792338df2629b.png': (3, 2, ['intermiami_ii', 'alhilal_iii', 'liverpool_iii',
                                                         'lazio_ii', 'ajax_ii', 'villarreal_ii']),
    'file_00000000559882438b59d2c90f38eb54.png': (3, 2, ['nx_lion_gold', 'nx_core_green', 'nx_eagle_gold',
                                                         'nx_dragon_gold', 'nx_frost', 'nx_phoenix_violet']),
    'file_000000009ce081f4b9b0de8bb5c49d28.png': (3, 2, ['nx_lion_red', 'nx_cyan', 'nx_dragon_gloss',
                                                         'nx_eagle_white', 'nx_frost_blue', 'nx_phoenix_purple']),
    'file_00000000ca90820a86d7b5b26e8cf9f9.png': (3, 2, ['arena_scorpion', 'arena_wolf', 'arena_torii',
                                                         'arena_dragon', 'arena_bermuda', 'arena_golem']),
}


def bands(profile, thr, min_len):
    out, s = [], None
    for i, v in enumerate(profile):
        if v > thr and s is None:
            s = i
        if v <= thr and s is not None:
            if i - s >= min_len:
                out.append((s, i - 1))
            s = None
    if s is not None and len(profile) - s >= min_len:
        out.append((s, len(profile) - 1))
    return out


def cell_boxes(im, cols, rows):
    """Tight coin boxes, segmented against each cell's own corner/background color (not a global luminance cutoff)."""
    rgb = np.asarray(im.convert('RGB')).astype(np.int16)
    H, W = rgb.shape[:2]
    boxes = []
    for r in range(rows):
        y0, y1 = r * H // rows, (r + 1) * H // rows
        for c in range(cols):
            x0, x1 = c * W // cols, (c + 1) * W // cols
            tile = rgb[y0:y1, x0:x1]
            h, w = tile.shape[:2]
            # Four corner patches estimate the sheet background; per-cell contrast also works on white, grey or
            # transparent-looking black atlases, unlike luminance thresholds which can select the whole cell.
            patch = max(3, min(h, w) // 24)
            corners = np.concatenate((tile[:patch, :patch].reshape(-1, 3), tile[:patch, -patch:].reshape(-1, 3),
                                      tile[-patch:, :patch].reshape(-1, 3), tile[-patch:, -patch:].reshape(-1, 3)))
            bg = np.median(corners, axis=0)
            delta = np.max(np.abs(tile - bg), axis=2)
            mask = delta > 26
            # Ignore isolated sparkle/noise; require a small but definite fraction of a row/column to be foreground.
            row = (mask.mean(axis=1) > .035).nonzero()[0]
            col = (mask.mean(axis=0) > .035).nonzero()[0]
            if len(row) < 2 or len(col) < 2:
                raise SystemExit(f'cannot segment coin in cell r{r} c{c} of {im.filename}')
            boxes.append((int(col[0]) + x0, int(row[0]) + y0, int(col[-1]) + x0, int(row[-1]) + y0))
    return boxes


def cut_circle(img, box, size=256, fill_r=120):
    """Square crop centred on `box`, scaled so the coin's radius -> fill_r px, round alpha edge."""
    x0, y0, x1, y1 = box
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    rad = min(x1 - x0, y1 - y0) / 2 * .985
    scale = fill_r / rad
    half = size / 2 / scale
    crop = img.crop((int(round(cx - half)), int(round(cy - half)),
                     int(round(cx + half)), int(round(cy + half)))).resize((size, size), Image.LANCZOS)
    crop = crop.convert('RGBA')
    ss = 4
    mask = Image.new('L', (size * ss, size * ss), 0)
    ImageDraw.Draw(mask).ellipse(((size / 2 - fill_r) * ss, (size / 2 - fill_r) * ss,
                                  (size / 2 + fill_r) * ss, (size / 2 + fill_r) * ss), fill=255)
    crop.putalpha(mask.resize((size, size), Image.LANCZOS))
    return crop


def build_discs():
    os.makedirs(DISC_OUT, exist_ok=True)
    made = []
    for fn, (cols, rows, slugs) in SHEETS.items():
        im = Image.open(os.path.join(SRC, fn)).convert('RGB')
        boxes = cell_boxes(im, cols, rows)
        assert len(boxes) == len(slugs), (fn, len(boxes), len(slugs))
        for box, slug in zip(boxes, slugs):
            cut_circle(im, box).save(os.path.join(DISC_OUT, slug + '.webp'), 'WEBP', quality=90, method=6)
            made.append(slug)
    print('discs', len(made))


# --------------------------------------------------------------------------------------------- basketball kit
BASKET_OUT = os.path.join(REPO, 'assets', 'basketball')


def cut_rect(img, box, size, pad_color=(0, 0, 0)):
    """Crop, keep the aspect, fit inside `size` (w, h) on a flat background."""
    crop = img.crop(box).convert('RGBA')
    crop.thumbnail(size, Image.LANCZOS)
    out = Image.new('RGBA', size, pad_color + (0,))
    out.paste(crop, ((size[0] - crop.width) // 2, (size[1] - crop.height) // 2), crop)
    return out


def build_basketball():
    """Owner atlas (file_8) -> separate drawables; arena (file_9) -> background."""
    os.makedirs(BASKET_OUT, exist_ok=True)
    atlas = Image.open(os.path.join(SRC, 'file_000000003a6c81f4a80a1386813f8edc.png')).convert('RGB')
    W, H = atlas.size
    # measured on the atlas (proportions of W x H): player 23, player 24, hoop; then the FX strip; then the HUD row
    parts = {
        'player_a': (0.00, 0.00, 0.30, 0.50),
        'player_b': (0.28, 0.00, 0.58, 0.50),
        'hoop': (0.66, 0.00, 1.00, 0.47),
        'ball': (0.00, 0.49, 0.11, 0.66),
        'ball_fast': (0.10, 0.49, 0.24, 0.66),
        'ball_fire': (0.23, 0.47, 0.40, 0.68),
        'fx_spark': (0.39, 0.47, 0.55, 0.67),
        'fx_ring': (0.55, 0.49, 0.68, 0.66),
        'scoreboard': (0.00, 0.68, 0.60, 0.88),
        'cup': (0.60, 0.68, 0.77, 0.90),
        'medal': (0.76, 0.68, 0.86, 0.90),
        'shield': (0.85, 0.68, 1.00, 0.90),
    }
    sizes = {
        'player_a': (300, 520), 'player_b': (300, 520), 'hoop': (340, 470),
        'ball': (150, 150), 'ball_fast': (150, 150), 'ball_fire': (170, 170),
        'fx_spark': (160, 160), 'fx_ring': (170, 170),
        'scoreboard': (760, 200), 'cup': (200, 220), 'medal': (140, 200), 'shield': (180, 220),
    }
    for name, (x0, y0, x1, y1) in parts.items():
        box = (int(x0 * W), int(y0 * H), int(x1 * W), int(y1 * H))
        cut_rect(atlas, box, sizes[name]).save(os.path.join(BASKET_OUT, name + '.webp'), 'WEBP', quality=90, method=6)
    arena = Image.open(os.path.join(SRC, 'file_00000000459481f489473715057fadaa.png')).convert('RGB')
    arena = arena.resize((900, 1600), Image.LANCZOS) if arena.width / arena.height < .6 else arena
    # the arena art is 2:3; keep it, the painter covers the canvas with BoxFit.cover semantics
    arena.save(os.path.join(BASKET_OUT, 'arena.webp'), 'WEBP', quality=88, method=6)
    print('basketball', len(parts) + 1)


# --------------------------------------------------------------------------------------------- hero art
def build_scenes():
    out = os.path.join(REPO, 'assets', 'ui', 'anix', 'scenes')
    os.makedirs(out, exist_ok=True)
    im = Image.open(os.path.join(SRC, 'file_0000000014a08210b5e388e0ba70ee9d.png')).convert('RGB')
    im.resize((1568, round(im.height * 1568 / im.width)), Image.LANCZOS).save(
        os.path.join(out, 'nexora_stage.webp'), 'WEBP', quality=88, method=6)
    print('scenes 1')


if __name__ == '__main__':
    build_discs()
    build_basketball()
    build_scenes()
