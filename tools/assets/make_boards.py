# -*- coding: utf-8 -*-
"""Ahşap tahta dokularını üretir (PNG).

Düz renkli tahtalar dosya olarak tutulmaz; uygulama onları iki renkten
doğrudan çizer (bkz. `BoardAssets.flatBoards`). Burada yalnızca ahşap
görünümlü olanlar üretilir.

Damar bilerek çok hafif tutulmuştur: tahta ahşap hissi versin ama taşların
okunmasını zorlaştırmasın, göz yormasın.
"""
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from noise import fbm, stretch, normalize01  # noqa: E402

SIZE = 1024
SQ = SIZE // 8


def checker_mask():
    yy, xx = np.mgrid[0:SIZE, 0:SIZE]
    return (((xx // SQ) + (yy // SQ)) % 2 == 0).astype('float32')


def grain(seed, rings, strength):
    """Neredeyse doğrusal, yumuşak damar alanı (0..1 ortalaması 0.5)."""
    rng = np.random.default_rng(seed)
    warp = stretch(fbm(SIZE, rng, octaves=3, base_cells=3), 10.0) - 0.5
    yy, xx = np.mgrid[0:SIZE, 0:SIZE]
    ring = 0.5 + 0.5 * np.sin(((xx / SIZE) + warp * 0.05) * rings * np.pi * 2)
    fibers = stretch(fbm(SIZE, rng, octaves=4, base_cells=80), 26.0)
    field = normalize01(ring * 0.55 + fibers * 0.45)
    # Karşıtlığı kısarak damarı fısıltı seviyesine indir.
    return 0.5 + (field - 0.5) * strength


def wood_board(seed, light, dark, rings=28.0, strength=0.30):
    field = grain(seed, rings, strength)[..., None]
    mask = checker_mask()[..., None]

    def shade(base):
        base = np.array(base, 'float32')
        # Damar yalnızca parlaklığı ±%6 dolayında oynatır.
        return base * (1 + (field - 0.5) * 0.12)

    img = shade(light) * mask + shade(dark) * (1 - mask)
    return Image.fromarray(np.clip(img, 0, 255).astype('uint8'), 'RGB')


# ad -> (tohum, açık kare, koyu kare, halka sayısı, damar gücü)
BOARDS = [
    ('dark_wood', 201, (183, 144, 98), (83, 51, 31), 26, 0.30),
    ('walnut', 202, (194, 160, 118), (101, 67, 40), 32, 0.28),
    ('oak', 203, (220, 191, 146), (152, 109, 69), 38, 0.26),
]


def build(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    total = 0
    for name, seed, light, dark, rings, strength in BOARDS:
        img = wood_board(seed, light, dark, rings, strength)
        path = os.path.join(out_dir, name + '.png')
        img.save(path, 'PNG', optimize=True)
        size = os.path.getsize(path)
        total += size
        print('  %-12s %6.1f KB' % (name, size / 1024))
    print('toplam %d tahta, %.1f KB' % (len(BOARDS), total / 1024))


if __name__ == '__main__':
    build(sys.argv[1])
