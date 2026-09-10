# -*- coding: utf-8 -*-
"""Uygulama simgesini üretir.

Koyu yeşil bir zemin üzerinde altın rengi bir at silueti; kenarda ince bir
satranç tahtası şeridi. Çıktılar:
  assets/icon/icon.png            1024x1024, tam simge (mağaza / iOS)
  assets/icon/icon_foreground.png 1024x1024, saydam zeminli ön plan (Android)
  windows/runner/resources/app_icon.ico  çok çözünürlüklü (Windows)
"""
from PIL import Image, ImageDraw, ImageFilter

S = 1024
GREEN_DARK = (46, 74, 26)
GREEN = (110, 155, 60)
GOLD = (232, 196, 122)
GOLD_DEEP = (176, 132, 58)
CREAM = (246, 240, 226)


def rounded(size, radius, color):
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(img).rounded_rectangle([0, 0, size - 1, size - 1],
                                          radius=radius, fill=color)
    return img


def vertical_gradient(size, top, bottom):
    grad = Image.new('RGB', (1, size))
    px = grad.load()
    for y in range(size):
        t = y / (size - 1)
        px[0, y] = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
    return grad.resize((size, size))


def knight_path(scale, dx, dy):
    """Bir at silueti; 0..1 aralığındaki noktalar ölçeklenir."""
    points = [
        (0.34, 0.92), (0.30, 0.86), (0.31, 0.75), (0.36, 0.64),
        (0.44, 0.55), (0.52, 0.50), (0.47, 0.44), (0.38, 0.47),
        (0.30, 0.53), (0.24, 0.52), (0.22, 0.45), (0.26, 0.36),
        (0.34, 0.28), (0.42, 0.23), (0.44, 0.16), (0.47, 0.09),
        (0.53, 0.13), (0.56, 0.09), (0.60, 0.14), (0.68, 0.19),
        (0.75, 0.28), (0.79, 0.40), (0.79, 0.55), (0.75, 0.70),
        (0.72, 0.82), (0.71, 0.92),
    ]
    return [(dx + x * scale, dy + y * scale) for x, y in points]


def build():
    # Zemin
    base = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    grad = vertical_gradient(S, GREEN, GREEN_DARK).convert('RGBA')
    mask = rounded(S, int(S * 0.22), (255, 255, 255, 255)).split()[3]
    base.paste(grad, (0, 0), mask)

    draw = ImageDraw.Draw(base)

    # Alt kenarda satranç tahtası şeridi
    cell = S // 16
    for i in range(16):
        if i % 2 == 0:
            continue
        draw.rectangle([i * cell, S - cell * 2, (i + 1) * cell, S - cell],
                       fill=CREAM + (46,))
    for i in range(16):
        if i % 2 == 1:
            continue
        draw.rectangle([i * cell, S - cell, (i + 1) * cell, S],
                       fill=CREAM + (46,))

    # At silueti: önce koyu gölge, sonra altın gövde
    shadow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).polygon(
        [(x * S, y * S) for x, y in
         [(p[0], p[1] + 0.018) for p in knight_path(1.0, 0.0, 0.0)]],
        fill=(20, 30, 12, 120))
    shadow = shadow.filter(ImageFilter.GaussianBlur(S * 0.012))
    base.alpha_composite(shadow)

    body = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(body).polygon(
        [(x * S, y * S) for x, y in knight_path(1.0, 0.0, 0.0)], fill=GOLD)
    base.alpha_composite(body)

    # Ata bir miktar boşluk bırakmak için son kompozisyonu yeniden kur.
    base = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    base.paste(grad, (0, 0), mask)
    strip = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(strip)
    cell = S // 16
    for i in range(16):
        top = S - cell * 2 if i % 2 else S - cell
        sd.rectangle([i * cell, top, (i + 1) * cell, top + cell],
                     fill=CREAM + (52,))
    base.alpha_composite(strip)

    art = _knight_art(shadow, body)
    k = 0.80
    scaled = art.resize((int(S * k), int(S * k)), Image.LANCZOS)
    base.alpha_composite(scaled, (int(S * (1 - k) / 2), int(S * 0.06)))

    base.save('assets/icon/icon.png')

    # Android uyarlanabilir simge ön planı: güvenli alan için %58 ölçek
    fg = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    art = _knight_art(shadow, body)
    k = 0.58
    scaled = art.resize((int(S * k), int(S * k)), Image.LANCZOS)
    fg.alpha_composite(scaled, (int(S * (1 - k) / 2), int(S * 0.20)))
    fg.save('assets/icon/icon_foreground.png')

    # Windows uygulama simgesi.
    #
    # Flutter'in Windows sablonu varsayilan olarak kendi logosunu koyar;
    # degistirilmezse pencere basliginda, gorev cubugunda ve kurulum
    # dosyasinda Flutter logosu gorunur. Cok cozunurluklu ICO uretiyoruz:
    # Windows duruma gore 16'dan 256'ya kadar uygun boyutu secer.
    sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64),
             (128, 128), (256, 256)]
    base.save('windows/runner/resources/app_icon.ico', sizes=sizes)
    print('windows/runner/resources/app_icon.ico  (%s)' %
          ', '.join('%dx%d' % s for s in sizes))
    print('simge üretildi')


def _knight_art(shadow, body):
    """Gölge + gövde + yele + göz + tabandan oluşan at görseli."""
    art = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    art.alpha_composite(shadow)
    art.alpha_composite(body)
    d = ImageDraw.Draw(art)
    d.polygon([(x * S, y * S) for x, y in [
        (0.60, 0.14), (0.68, 0.19), (0.75, 0.28), (0.79, 0.40),
        (0.79, 0.55), (0.74, 0.55), (0.73, 0.40), (0.68, 0.28),
        (0.61, 0.21),
    ]], fill=GOLD_DEEP)
    d.ellipse([0.545 * S, 0.235 * S, 0.585 * S, 0.275 * S], fill=(40, 52, 22))
    d.rounded_rectangle([0.27 * S, 0.885 * S, 0.75 * S, 0.945 * S],
                        radius=int(0.02 * S), fill=GOLD)
    return art


if __name__ == '__main__':
    build()
