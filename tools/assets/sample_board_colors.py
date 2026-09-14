# -*- coding: utf-8 -*-
"""Bir tahta görselinden açık ve koyu kare rengini ölçer.

Görselli tahtaların kare renkleri `BoardAssets._squareColors` içinde
kayıtlıdır; liste önizlemeleri ve kare adlarının rengi oradan gelir. Bu
renkleri gözle tahmin etmek yerine görselin kendisinden ölçmek gerekir,
yoksa önizleme oyun tahtasına benzemez.

Kullanım:

    python tools/assets/sample_board_colors.py assets/boards/wood.jpg
    python tools/assets/sample_board_colors.py assets/boards

Çıktı, doğrudan `settings_service.dart` içine yapıştırılabilecek
biçimdedir.

Gerekli: pillow
"""
import os
import statistics
import sys

from PIL import Image


def sample(path):
    """(açık, koyu) kare rengini 0xRRGGBB olarak döner.

    Her karenin ortasındaki yüzde otuzluk alan alınır ve kanal başına
    ortanca değer hesaplanır: ortalama yerine ortanca kullanılması,
    damar ya da tahtanın üstündeki çizim gibi aykırı piksellerin sonucu
    kaydırmasını önler.
    """
    image = Image.open(path).convert('RGB')
    cell = image.width / 8.0
    light, dark = [], []

    for row in range(8):
        for col in range(8):
            box = (
                int((col + 0.35) * cell), int((row + 0.35) * cell),
                int((col + 0.65) * cell), int((row + 0.65) * cell),
            )
            pixels = list(image.crop(box).getdata())
            median = tuple(
                int(statistics.median(p[channel] for p in pixels))
                for channel in range(3))
            (light if (row + col) % 2 == 0 else dark).append(median)

    def middle(values):
        return tuple(
            int(statistics.median(v[channel] for v in values))
            for channel in range(3))

    def to_int(rgb):
        return (rgb[0] << 16) | (rgb[1] << 8) | rgb[2]

    return to_int(middle(light)), to_int(middle(dark))


def main(target):
    paths = []
    if os.path.isdir(target):
        for name in sorted(os.listdir(target)):
            if name.lower().endswith(('.png', '.jpg', '.jpeg')):
                paths.append(os.path.join(target, name))
    else:
        paths.append(target)

    for path in paths:
        light, dark = sample(path)
        name = os.path.splitext(os.path.basename(path))[0]
        print("    '%s': (0x%06X, 0x%06X)," % (name, light, dark))


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print(__doc__)
        raise SystemExit(1)
    main(sys.argv[1])
