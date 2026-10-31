"""App Store frames, 1320×2868 (6.9"): headline on an intro step colour, the real screenshot in a phone frame below.
Usage: python3 scripts/compose-store-screenshots.py <raw shots dir> <out dir>. Raw shots come from AnkkaUITests/AppStoreScreenshots."""
import os, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont
RAW, OUT = sys.argv[1], sys.argv[2]
W, H = 1320, 2868
HEAVY = ImageFont.truetype('/Library/Fonts/SF-Pro-Display-Heavy.otf', 132)
BODY = ImageFont.truetype('/Library/Fonts/SF-Pro-Display-Medium.otf', 50)
# (lit, base, deep, shadow, ink) from IntroPalette
PAL = {2: ('FFCE76', 'FFBA2E', 'EEA50F', '603901', '2B1A00'), 3: ('B1D173', '9FC45E', '87B24D', '1B3D0C', '142300'),
       4: ('84CBFD', '71BCF4', '61A8E2', '183354', '032036'), 5: ('C4ADFB', 'B59EF2', '9F8CE1', '2A2752', '1F1838'),
       1: ('FD8C6F', 'FF6F4F', 'EB5842', '4B020B', '320100'), 6: ('AD3424', 'A3170F', '8A000E', '140001', 'FFF0EB')}
SLIDES = [
    ('01-home', 2, 'A card for\nevery purpose.', 'Daily spending, a trip, the house.\nEach card keeps its own total.'),
    ('04-chat-add', 3, 'Type it like\na text.', '“kopi 28rb” becomes an expense.\nIn English or Bahasa.'),
    ('03-tokyo', 4, 'Spend in\nany currency.', 'Log yen on the road and see it\nin your own money too.'),
    ('06-budgets', 5, 'Know what’s\nleft.', 'Budgets that keep pace\nwith your month.'),
    ('07-analytics', 1, 'See where it\nall goes.', 'Trends, categories and pace\nat a glance.'),
    ('08-entry', 6, 'Log it in\nseconds.', 'A keypad made for one thumb.\nNo account. No bank login.'),
]

def rgb(h): return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))

def background(lit, base, deep):
    # The intro's lit top-left corner falling to a deeper bottom-right.
    small = Image.new('RGB', (66, 143))
    px = small.load()
    a, b, c = rgb(lit), rgb(base), rgb(deep)
    for y in range(143):
        for x in range(66):
            t = min(1, ((x / 66 - 0.28) ** 2 * 0.6 + (y / 143 - 0.14) ** 2) ** 0.5 / 0.9)
            u = t * 2 if t < 0.5 else (t - 0.5) * 2
            p, q = (a, b) if t < 0.5 else (b, c)
            px[x, y] = tuple(round(p[i] + (q[i] - p[i]) * u) for i in range(3))
    return small.resize((W, H), Image.BICUBIC).filter(ImageFilter.GaussianBlur(30))

def rounded(img, r):
    mask = Image.new('L', img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, img.width - 1, img.height - 1), r, fill=255)
    img.putalpha(mask)
    return img

for i, (name, step, title, sub) in enumerate(SLIDES, start=2):
    lit, base, deep, shadow, ink = PAL[step]
    canvas = background(lit, base, deep).convert('RGBA')
    d = ImageDraw.Draw(canvas)
    d.multiline_text((96, 210), title, font=HEAVY, fill=rgb(ink), spacing=6)
    d.multiline_text((100, 540), sub, font=BODY, fill=rgb(ink), spacing=14)
    shot = Image.open(os.path.join(RAW, name + '.png')).convert('RGBA')
    sw = 1000
    shot = rounded(shot.resize((sw, round(shot.height * sw / shot.width)), Image.LANCZOS), 112)
    bezel = Image.new('RGBA', (sw + 28, shot.height + 28), (0, 0, 0, 0))
    ImageDraw.Draw(bezel).rounded_rectangle((0, 0, bezel.width - 1, bezel.height - 1), 126, fill=(18, 18, 20, 255))
    bezel.alpha_composite(shot, (14, 14))
    x, y = (W - bezel.width) // 2, 790
    glow = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).rounded_rectangle((x + 10, y + 40, x + bezel.width - 10, y + bezel.height + 40), 126, fill=rgb(shadow) + (110,))
    canvas.alpha_composite(glow.filter(ImageFilter.GaussianBlur(50)))
    canvas.alpha_composite(bezel, (x, y))
    canvas.convert('RGB').save(os.path.join(OUT, f'{i:02d}-{name[3:]}.png'))

Image.open(os.path.join(RAW, '09-intro.png')).convert('RGB').save(os.path.join(OUT, '01-intro.png'))
print('ok')
