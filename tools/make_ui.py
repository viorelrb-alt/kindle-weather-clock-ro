#!/usr/bin/env python3
"""Builds the static parts of the v2 screens (frames, gray headers, buttons; *-antet: only
the header, while the first forecast loads) as PNGs in
extensions/meteoalarmkindle/ui/. The script draws text and data on top of them.
Run from the repository root: python3 tools/make_ui.py"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'extensions', 'meteoalarmkindle')
ICONS = os.path.join(ROOT, 'icons')
OUT = os.path.join(ROOT, 'ui')
SS = 4  # supersampling, for smooth rounded corners
R = 10  # corner radius
LW = 2  # line width
HEAD = 0xDD  # header bands: light gray, the script writes black text on them
PRESS = 0xAA  # medium gray: a pressed button, and the orange / red warning codes (GRAYA)
FONTS = os.path.join(ROOT, 'fonts')


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.im = Image.new('L', (w * SS, h * SS), 255)
        self.d = ImageDraw.Draw(self.im)

    def s(self, *v):
        return [int(round(x * SS)) for x in v]

    def frame(self, x, y, w, h, header=0, r=R, fill=255):
        """Rounded box with a 2 px outline and, optionally, a light gray header band."""
        self.d.rounded_rectangle(self.s(x, y, x + w - 1, y + h - 1), radius=r * SS, fill=0)
        self.d.rounded_rectangle(self.s(x + LW, y + LW, x + w - 1 - LW, y + h - 1 - LW),
                                 radius=(r - LW) * SS, fill=fill)
        if header:
            self.d.rounded_rectangle(self.s(x + LW, y + LW, x + w - 1 - LW, y + header + r),
                                     radius=(r - LW) * SS, fill=HEAD)
            self.d.rectangle(self.s(x + LW, y + header, x + w - 1 - LW, y + header + r + 1), fill=fill)
            self.d.rectangle(self.s(x, y + header - LW, x + w - 1, y + header - 1), fill=0)

    def rect(self, x, y, w, h, c=0):
        self.d.rectangle(self.s(x, y, x + w - 1, y + h - 1), fill=c)

    def icon(self, name, x, y, w, h):
        src = Image.open(os.path.join(ICONS, name)).convert('RGBA').resize((w * SS, h * SS), Image.LANCZOS)
        base = self.im.crop((x * SS, y * SS, (x + w) * SS, (y + h) * SS)).convert('RGBA')
        base.alpha_composite(src)
        self.im.paste(base.convert('L'), (x * SS, y * SS))

    def button(self, kind, x, y, size=64, fill=255):
        self.frame(x, y, size, size, r=8, fill=fill)
        if kind == 'menu':
            for k in range(3):
                self.rect(x + 15, y + 19 + k * 11, 34, 4)
        else:
            ic = {'light': 'btn-light.png', 'exit': 'btn-exit.png', 'city': 'btn-city.png'}[kind]
            self.icon(ic, x + 12, y + 12, size - 24, size - 24)

    def save(self, name):
        os.makedirs(OUT, exist_ok=True)
        self.im.resize((self.w, self.h), Image.LANCZOS).save(os.path.join(OUT, name), optimize=True)


# Portrait, 758 x 1024 ------------------------------------------------------------------
def portrait(body):
    c = Canvas(758, 1024)
    c.button('menu', 40, 24)
    c.button('light', 580, 24)
    c.button('exit', 654, 24)
    # The line under the clock is drawn by the script: it stops at the first warning box.
    c.button('city', 40, 944)
    body(c)
    return c


def p_5zile(c):
    c.frame(40, 574, 331, 200, header=52)
    c.frame(387, 574, 331, 200, header=52)
    for x in (40, 271, 503):  # three separate day boxes, like the two above
        c.frame(x, 788, 215, 150, header=44)


def p_ploaie(c):
    c.frame(40, 574, 678, 364, header=46)


def p_simplu(c):
    for x in (40, 272, 503):
        c.frame(x, 616, 215, 300, header=44)


# Landscape, 1024 x 758 -----------------------------------------------------------------
def landscape(body):
    c = Canvas(1024, 758)
    c.button('light', 846, 24)
    c.button('exit', 920, 24)
    c.rect(516, 102, 468, 2)
    c.button('menu', 846, 680)
    c.button('city', 920, 680)
    body(c)
    return c


def l_panel(c):
    c.frame(40, 55, 460, 659)


def l_5zile(c):
    l_panel(c)
    c.frame(516, 156, 226, 242, header=48)
    c.frame(758, 156, 226, 242, header=48)
    for x in (516, 676, 836):  # three separate day boxes, the width of the capsules (l_simplu)
        c.frame(x, 416, 148, 246, header=46)


def l_ploaie(c):
    l_panel(c)
    c.frame(516, 156, 468, 506, header=46)


def l_simplu(c):
    l_panel(c)
    for x in (516, 676, 836):
        c.frame(x, 156, 148, 289, header=46)
    for x in (516, 676, 836):  # sun, UV index, pollen: separate boxes under the day capsules
        c.frame(x, 458, 148, 206, header=46)


# Pop-ups --------------------------------------------------------------------------------
def menu():
    c = Canvas(380, 378)
    c.frame(0, 0, 380, 378)
    for k in range(1, 7):
        c.rect(12, k * 54 - 1, 356, 2, 0x99)
    return c


def pill_ends(fill):
    # Rounded ends of the warning code band (42 px high); the script fills the middle.
    c = Canvas(48, 42)
    c.frame(0, 0, 48, 42, r=8, fill=fill)
    im = c.im.resize((48, 42), Image.LANCZOS)
    return im.crop((0, 0, 12, 42)), im.crop((36, 0, 48, 42))


def swipe_dots(h):
    # Light swipe zone marker: 14 gray dots in a 40 px wide strip, larger toward the top.
    c = Canvas(40, h)
    n = 14
    for k in range(n):
        y = h - 12 - k * (h - 24) / (n - 1)
        r = 1.5 + k * 5.5 / (n - 1)
        c.d.ellipse(c.s(20 - r, y - r, 20 + r, y + r), fill=0x99)
    return c


def places(rows):
    # City picker bubble: title row 58, ROWS rows of 54, nav row 62; lines drawn by the script.
    c = Canvas(678, 58 + rows * 54 + 62)
    c.frame(0, 0, 678, c.h)
    return c


def light_info():
    # Light bubble 340 x 150 under the light button: the script writes the step and how to set
    # the light (swipe on the left edge); its tip is drawn on its own, 222 px in.
    c = Canvas(340, 150)
    c.frame(0, 0, 340, 150, r=12)
    c.rect(224, 0, 20, 3, 255)  # opening for the tip
    return c


def light_bar(h):
    """Light bar over the swipe dots while the light pop-up is open, like the Kobo Libra 2's:
    a rounded frame 22 px wide at the right of the 40 px strip, 24 steps from light gray (top)
    to dark gray (bottom). The script puts the arrow (lumina-sageata.png) at the left."""
    c = Canvas(40, h)
    c.frame(16, 0, 22, h, r=6)
    seg = (h - 8) / 24
    for k in range(24):  # k = 0 at the top
        g = int(0xDD - (0xDD - 0x33) * k / 23)
        y0 = 4 + k * seg
        c.d.rectangle(c.s(20, y0 + 1, 33.999, y0 + seg - 1.001), fill=g)
    return c


def light_arrow():
    # Black arrow pointing right at the bar, 13 x 22.
    c = Canvas(13, 22)
    c.d.polygon([tuple(c.s(0, 0)), tuple(c.s(13, 11)), tuple(c.s(0, 22))], fill=0)
    return c


def tip(down=False):
    # Tip of a speech bubble (light bubble, menu), drawn over the box outline so it opens into it.
    c = Canvas(24, 14)
    c.d.polygon([(0, 14 * SS), (12 * SS, 0), (24 * SS, 14 * SS)], fill=0)
    c.d.polygon([(3 * SS, 14 * SS), (12 * SS, 3 * SS), (21 * SS, 14 * SS)], fill=255)
    if down:
        c.im = c.im.transpose(Image.FLIP_TOP_BOTTOM)
    return c


def warn_sign():
    # Red warning: a triangle with a black outline, white inside and a black "!", 46 x 42.
    c = Canvas(46, 42)
    c.d.polygon([tuple(c.s(23, 1)), tuple(c.s(45, 41)), tuple(c.s(1, 41))], fill=0)
    c.d.polygon([tuple(c.s(23, 8)), tuple(c.s(39.5, 37.5)), tuple(c.s(6.5, 37.5))], fill=255)
    c.d.rounded_rectangle(c.s(21.2, 16, 24.8, 29), radius=1.5 * SS, fill=0)
    c.d.ellipse(c.s(21, 31, 25, 35), fill=0)
    return c


def text_w(font, px, text, _cache={}):
    """Width of TEXT in px, from the same glyph table the script uses (fonts/*.wid)."""
    if font not in _cache:
        tab = {}
        with open(os.path.join(FONTS, font + '.wid'), encoding='utf-8') as f:
            for line in f:
                line = line.rstrip('\n')
                sp = line.index(' ')
                tab[line[sp + 1:]] = int(line[:sp])
        _cache[font] = tab
    tab = _cache[font]
    return int(sum(tab.get(ch, 1100) for ch in text) * px / 2288 + 0.5)


def fit_px(font, px, maxw, text):
    while px > 14 and text_w(font, px, text) > maxw:
        px = px * 92 // 100
    return px


def place_pages():
    """The rows of every city picker page drawn ahead of time, as the script would draw them:
    ui/loc/<md5 of the page's names>.png, 654 px wide (inside the bubble's 12 px margins),
    54 px a row. Level 0 pages hold the counties (the favourites row above them is drawn by the
    script); level 1 pages hold a county's towns, 24 a page. If cities.txt is edited, pages
    whose names changed have no image and the script draws them itself."""
    import hashlib
    rows_c, towns = [], {}
    with open(os.path.join(ROOT, 'cities.txt'), encoding='utf-8') as f:
        for line in f:
            p = line.rstrip('\n').split('|')
            if line.startswith('#') or len(p) < 4 or p[0] == '*':
                continue
            if p[0] not in towns:
                rows_c.append(p[0])
                towns[p[0]] = []
            towns[p[0]].append(p[1])
    half = (len(rows_c) + 1) // 2
    pages = [rows_c[:half], rows_c[half:]]
    for t in towns.values():
        pages += [t[k:k + 24] for k in range(0, len(t), 24)]
    out = os.path.join(OUT, 'loc')
    os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):
        os.remove(os.path.join(out, f))
    font = ImageFont.truetype(os.path.join(FONTS, 'LiberationSans-Regular.ttf'), 2048)
    for names in pages:
        key = hashlib.md5(''.join(n + '\n' for n in names).encode('utf-8')).hexdigest()
        rows = (len(names) + 2) // 3
        im = Image.new('L', (654, rows * 54), 255)
        d = ImageDraw.Draw(im)
        for i, n in enumerate(names):
            r, col = divmod(i, 3)
            ry = r * 54 + 1
            if col == 0:
                d.rectangle([0, ry - 1, 653, ry], fill=0x99)
            lp = fit_px('LiberationSans-Regular', 27, 206, n)
            x = col * 218 + 109 - text_w('LiberationSans-Regular', lp, n) // 2
            y = ry + (54 - lp) // 2 + lp * 1854 / 2288
            d.text((x, y), n, font=font.font_variant(size=round(lp * 2048 / 2288)), fill=0, anchor='ls')
        im.save(os.path.join(out, key + '.png'), optimize=True)
    print('place pages:', len(pages))


def now_arrow():
    # "acum" marker on the precipitation chart: a black arrowhead pointing down, 16 x 11.
    c = Canvas(16, 11)
    c.d.polygon([tuple(c.s(0, 0)), tuple(c.s(16, 0)), tuple(c.s(8, 11))], fill=0)
    return c


def dotted():
    # Threshold line of the precipitation chart: 5 px dashes, 4 px apart, mid gray.
    im = Image.new('L', (720, 2), 255)
    for x in range(0, 720, 9):
        im.paste(0x55, (x, 0, x + 5, 2))
    return im


def icon_boxes():
    # icons/centru.txt: for each weather icon, the box of its dark pixels in a 200 px frame
    # ("name left top right bottom"), so the script can centre the drawing, not the file.
    from PIL import ImageOps
    rows = []
    for f in sorted(x for x in os.listdir(ICONS) if x.endswith('.png')):
        im = Image.open(os.path.join(ICONS, f)).convert('L')
        if im.size != (200, 200):
            continue
        box = ImageOps.invert(im).point(lambda v: 255 if v > 40 else 0).getbbox()
        rows.append('%s %d %d %d %d' % ((f[:-4],) + box))
    with open(os.path.join(ICONS, 'centru.txt'), 'w') as out:
        out.write('\n'.join(rows) + '\n')


if __name__ == '__main__':
    icon_boxes()
    portrait(lambda c: None).save('p-antet.png')
    landscape(lambda c: None).save('l-antet.png')
    portrait(p_5zile).save('p-5zile.png')
    portrait(p_ploaie).save('p-ploaie.png')
    portrait(p_simplu).save('p-simplu.png')
    landscape(l_5zile).save('l-5zile.png')
    landscape(l_ploaie).save('l-ploaie.png')
    landscape(l_simplu).save('l-simplu.png')
    menu().save('meniu.png')
    swipe_dots(930 - 110).save('glisare-p.png')  # SW_TOP..SW_BOT in set_bands
    swipe_dots(700 - 60).save('glisare-l.png')
    for fill, suf in ((HEAD, ''), (255, '-alb'), (PRESS, '-gri')):
        left, right = pill_ends(fill)
        left.save(os.path.join(OUT, 'cod-st%s.png' % suf), optimize=True)
        right.save(os.path.join(OUT, 'cod-dr%s.png' % suf), optimize=True)
    for k in range(1, 9):
        places(k).save('loc-%d.png' % k)
    light_info().save('lumina-info.png')
    light_bar(930 - 110).save('lumina-bara-p.png')  # SW_TOP..SW_BOT, as the dots
    light_bar(700 - 60).save('lumina-bara-l.png')
    light_arrow().save('lumina-sageata.png')
    for kind in ('menu', 'light', 'exit', 'city'):  # pressed: medium gray inside
        b = Canvas(64, 64)
        b.button(kind, 0, 0, fill=PRESS)
        b.save('btn-%s-apasat.png' % kind)
    warn_sign().save('atentie.png')
    now_arrow().save('acum.png')
    place_pages()
    tip().save('varf-sus.png')
    tip(down=True).save('varf-jos.png')
    dotted().save(os.path.join(OUT, 'punctat.png'), optimize=True)
