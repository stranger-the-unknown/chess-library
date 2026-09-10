# -*- coding: utf-8 -*-
"""Dokular icin basit deger gurultusu (value noise) araclari."""
import numpy as np
from PIL import Image


def value_noise(size, cells, rng):
    """`cells` x `cells` rastgele izgaranin yumusatilmis buyutulmesi."""
    grid = rng.random((cells + 1, cells + 1)).astype('float32')
    img = Image.fromarray((grid * 255).astype('uint8'), mode='L')
    img = img.resize((size, size), Image.BICUBIC)
    return np.asarray(img, dtype='float32') / 255.0


def fbm(size, rng, octaves=5, base_cells=4, gain=0.5, lacunarity=2.0):
    """Fraktal toplam: kaba katmanlarin uzerine ince ayrinti."""
    total = np.zeros((size, size), dtype='float32')
    amp, cells, norm = 1.0, base_cells, 0.0
    for _ in range(octaves):
        total += amp * value_noise(size, int(cells), rng)
        norm += amp
        amp *= gain
        cells *= lacunarity
    return total / norm


def stretch(field, factor):
    """Damar yonu icin alani bir eksende uzatir."""
    h, w = field.shape
    img = Image.fromarray((np.clip(field, 0, 1) * 255).astype('uint8'), 'L')
    img = img.resize((w, max(1, int(h / factor))), Image.BICUBIC)
    img = img.resize((w, h), Image.BICUBIC)
    return np.asarray(img, dtype='float32') / 255.0


def normalize01(field):
    lo, hi = float(field.min()), float(field.max())
    if hi - lo < 1e-6:
        return np.zeros_like(field)
    return (field - lo) / (hi - lo)
