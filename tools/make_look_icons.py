# -*- coding: utf-8 -*-
"""Görünümlerin uygulama simgelerini üretir (10.13.0).

    python3 tools/make_look_icons.py        (deponun kökünden)

Renkler `lib/theme/app_look.dart` içindeki tablodan okunur; varsayılan
görünümün ("yesil") simgesi bugünkü `ic_launcher`'dır ve üretilmez.

Her görünüm için:
  android/app/src/main/res/drawable-xxxhdpi/ic_look_<ad>_fg.png  432 px,
      uyarlanabilir simgenin ön planı (zemin geçişi + at, kenara kadar)
  android/app/src/main/res/mipmap-xxxhdpi/ic_look_<ad>.png       192 px,
      Android 7 için yuvarlak köşeli simge
  android/app/src/main/res/mipmap-anydpi-v26/ic_look_<ad>.xml
  android/app/src/main/res/values/look_colors.xml                (hepsi)

Düzen bugünkü simgeyle aynı: sol üstten sağ alta geçiş, ortada Noto Sans
Symbols 2'nin ♞ işareti, yüksekliğin %42,4'ü (ic_launcher'da ölçüldü),
köşe yarıçapı kenarın 16/54'ü (ana menü logosu).

Gereken: Pillow.
"""
import os
import re
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TABLE = os.path.join(ROOT, 'lib', 'theme', 'app_look.dart')
FONT = os.path.join(ROOT, 'assets', 'fonts', 'NotoSansSymbols2-Regular.ttf')
RES = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res')

KNIGHT = '♞'
KNIGHT_HEIGHT = 0.424
RADIUS = 16 / 54
DEFAULT = 'yesil'


def looks():
    """app_look.dart'taki tablo: [{id, iconTop, iconBottom, knight}, ...]."""
    with open(TABLE, encoding='utf-8') as f:
        source = f.read()
    found = []
    for block in re.findall(r'= AppLook\((.*?)\);', source, re.S):
        pairs = re.findall(
            r"(\w+): (?:Color\(0xFF([0-9A-Fa-f]{6})\)|'(\w+)')", block)
        fields = {key: (color or text) for key, color, text in pairs}
        missing = [k for k in ('id', 'iconTop', 'iconBottom', 'knight')
                   if k not in fields]
        if missing:
            sys.exit('app_look.dart okunamadı; eksik alan: %s' % missing)
        found.append(fields)
    ids = [f['id'] for f in found]
    if len(found) < 2 or DEFAULT not in ids or len(set(ids)) != len(ids):
        sys.exit('app_look.dart okunamadı: %s' % ids)
    if not all(re.fullmatch(r'[a-z][a-z0-9]*', i) for i in ids):
        sys.exit('görünüm adları küçük harf ve rakam olmalı: %s' % ids)
    return found


def rgb(hex6):
    return tuple(int(hex6[i:i + 2], 16) for i in (0, 2, 4))


def render(size, top, bottom, knight):
    """Kenara kadar dolu kare: zemin geçişi ve at."""
    n = 256
    small = Image.new('RGB', (n, n))
    px = small.load()
    for y in range(n):
        for x in range(n):
            t = (x + y) / (2 * (n - 1))
            px[x, y] = tuple(round(top[i] + (bottom[i] - top[i]) * t)
                             for i in range(3))
    img = small.resize((size, size), Image.BICUBIC).convert('RGBA')
    probe = ImageFont.truetype(FONT, 1000)
    box = probe.getbbox(KNIGHT)
    font = ImageFont.truetype(
        FONT, int(1000 * size * KNIGHT_HEIGHT / (box[3] - box[1])))
    box = font.getbbox(KNIGHT)
    w, h = box[2] - box[0], box[3] - box[1]
    ImageDraw.Draw(img).text(
        ((size - w) / 2 - box[0], (size - h) / 2 - box[1]),
        KNIGHT, font=font, fill=knight + (255,))
    return img


def rounded(img):
    size = img.size[0]
    mask = Image.new('L', (size * 4, size * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size * 4 - 1, size * 4 - 1],
        radius=int(size * 4 * RADIUS), fill=255)
    out = Image.new('RGBA', img.size, (0, 0, 0, 0))
    out.paste(img, (0, 0), mask.resize((size, size), Image.LANCZOS))
    return out


def main():
    table = looks()
    for d in ('drawable-xxxhdpi', 'mipmap-xxxhdpi', 'mipmap-anydpi-v26',
              'values'):
        os.makedirs(os.path.join(RES, d), exist_ok=True)
    colors = []
    for look in table:
        name = look['id']
        top, bottom, knight = (rgb(look[k])
                               for k in ('iconTop', 'iconBottom', 'knight'))
        if name == DEFAULT:
            continue
        big = render(1024, top, bottom, knight)
        big.resize((432, 432), Image.LANCZOS).convert('RGB').save(
            os.path.join(RES, 'drawable-xxxhdpi', 'ic_look_%s_fg.png' % name),
            optimize=True)
        rounded(big.resize((192, 192), Image.LANCZOS)).save(
            os.path.join(RES, 'mipmap-xxxhdpi', 'ic_look_%s.png' % name),
            optimize=True)
        with open(os.path.join(RES, 'mipmap-anydpi-v26',
                               'ic_look_%s.xml' % name), 'w',
                  encoding='utf-8', newline='\n') as f:
            f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                    '<!-- tools/make_look_icons.py üretiyor; elle düzenleme. -->\n'
                    '<adaptive-icon xmlns:android='
                    '"http://schemas.android.com/apk/res/android">\n'
                    '  <background android:drawable="@color/ic_look_%s_bg"/>\n'
                    '  <foreground android:drawable="@drawable/ic_look_%s_fg"/>\n'
                    '</adaptive-icon>\n' % (name, name))
        middle = tuple(round((top[i] + bottom[i]) / 2) for i in range(3))
        colors.append('    <color name="ic_look_%s_bg">#%02X%02X%02X</color>'
                      % ((name,) + middle))
        print('ic_look_%s' % name)
    with open(os.path.join(RES, 'values', 'look_colors.xml'), 'w',
              encoding='utf-8', newline='\n') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<!-- tools/make_look_icons.py üretiyor; elle düzenleme. -->\n'
                '<resources>\n%s\n</resources>\n' % '\n'.join(colors))
    print('%d görünüm; %d Android simgesi' % (len(table), len(colors)))


if __name__ == '__main__':
    main()
