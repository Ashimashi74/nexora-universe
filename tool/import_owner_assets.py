from pathlib import Path
from PIL import Image
import shutil

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'asset-inspect' / 'assests '
# The archive is extracted outside the repo by the task setup; use the known inspection copy if present.
if not SRC.exists():
    SRC = Path('/home/ubuntu/asset-inspect/assests ')
OUT = ROOT / 'assets/games/bermuda'
fields = [
    ('Picsart_26-11-23_19-58-41-565.png', 'nx_green_plain'),
    ('Picsart_26-11-23_19-59-27-530.png', 'nx_rings_green_new'),
    ('Picsart_26-11-23_20-00-23-320.png', 'nx_checker_green'),
    ('Picsart_26-11-23_20-01-52-653.jpg', 'nx_stripes_green'),
    ('Picsart_26-11-23_20-03-14-604.jpg', 'nx_stripes_teal'),
    ('Picsart_26-11-23_20-06-27-896.png', 'nx_ember_street'),
    ('Picsart_26-11-23_20-09-41-779.png', 'nx_black_sockerbox'),
]
balls = [
    ('file_0000000011d48210b49581a8ac734aff.png', 'nx_ball_black'),
    ('file_000000006be48210b2abb0ce2f93396e.png', 'nx_ball_color'),
]
pieces = [
    'file_0000000092f0821089684e2c75a62250.png',
    'file_00000000a45c82108666faf1991bc2f6.png',
    'file_00000000dda88210baf3e473df6fb605.png',
]

def save_webp(im, path, quality=92):
    path.parent.mkdir(parents=True, exist_ok=True)
    if im.mode not in ('RGB', 'RGBA'):
        im = im.convert('RGBA')
    im.save(path, 'WEBP', quality=quality, method=6)

# Replace the field set with exactly the seven supplied full-resolution arts.
field_dir = OUT / 'fields'
thumb_dir = OUT / 'thumbs'
for p in field_dir.glob('*'):
    p.unlink()
for p in thumb_dir.glob('*'):
    p.unlink()
for filename, slug in fields:
    im = Image.open(SRC / filename).convert('RGB')
    assert im.size == (1992, 3155), (filename, im.size)
    save_webp(im, field_dir / f'{slug}.webp')
    thumb = im.copy(); thumb.thumbnail((240, 380), Image.Resampling.LANCZOS)
    save_webp(thumb, thumb_dir / f'{slug}.webp')

# Replace every old ball art with the twelve supplied balls, cropped from 3 columns x 2 rows.
ball_dir = OUT / 'balls/v9'
for p in ball_dir.glob('*'):
    p.unlink()
for src_name, prefix in balls:
    im = Image.open(SRC / src_name).convert('RGB')
    assert im.size == (1254, 1254), (src_name, im.size)
    cell = 418
    for row in range(2):
        for col in range(3):
            box = (col * cell, row * cell, (col + 1) * cell, (row + 1) * cell)
            tile = im.crop(box)
            # Use the central 360px circle, preserving transparent corners for clean in-game rendering.
            out = Image.new('RGBA', tile.size, (0, 0, 0, 0))
            mask = Image.new('L', tile.size, 0)
            from PIL import ImageDraw
            ImageDraw.Draw(mask).ellipse((25, 25, cell - 25, cell - 25), fill=255)
            out.paste(tile, (0, 0), mask)
            slug = f'{prefix}_{row * 3 + col + 1}'
            save_webp(out, ball_dir / f'{slug}.webp')

# Add all new piece/badge crops; do not touch existing v9/v10 pieces.
disc_dir = OUT / 'discs/v11'
disc_dir.mkdir(parents=True, exist_ok=True)
for old in disc_dir.glob('*'):
    old.unlink()
for sheet_i, src_name in enumerate(pieces, 1):
    im = Image.open(SRC / src_name).convert('RGBA')
    assert im.size == (1536, 1024), (src_name, im.size)
    for row in range(2):
        for col in range(4):
            # Eight evenly spaced badges; the generous inset removes the checkerboard/transparent gutter.
            cx = int((col + .5) * im.width / 4)
            cy = int((row + .5) * im.height / 2)
            r = 150
            crop = im.crop((cx-r, cy-r, cx+r, cy+r))
            crop.thumbnail((320, 320), Image.Resampling.LANCZOS)
            save_webp(crop, disc_dir / f'owner_{sheet_i:02d}_{row * 4 + col + 1:02d}.webp')
print('imported', len(fields), 'fields,', len(balls) * 6, 'balls,', len(pieces) * 8, 'pieces')
