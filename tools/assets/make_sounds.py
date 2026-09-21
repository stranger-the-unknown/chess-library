# -*- coding: utf-8 -*-
"""Satranc arayuzu icin ozgun ses seti uretir.

Tahta tasin tahtaya vurusu, kisa ve inharmonik modlarin ustuste binmesiyle
modellenir: her mod ussel olarak soner, en tepede kisa bir gurultu patlamasi
"tik" vurusunu verir. Cikti mono 44.1 kHz MP3'tur.
"""
import math
import os
import sys

import numpy as np
import lameenc

SR = 44100
rng = np.random.default_rng(20260910)


def silence(seconds):
    return np.zeros(int(SR * seconds), dtype=np.float64)


def place(base, sound, at):
    """`sound`u `base` icine `at` saniyesinden itibaren ekler."""
    start = int(at * SR)
    end = min(len(base), start + len(sound))
    if end > start:
        base[start:end] += sound[:end - start]
    return base


def modes(freqs, decays, amps, seconds, detune=0.0):
    """Inharmonik sonumlu sinuslerin toplami."""
    n = int(SR * seconds)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for f, d, a in zip(freqs, decays, amps):
        f = f * (1.0 + detune * (rng.random() - 0.5))
        phase = rng.random() * 2 * math.pi
        out += a * np.exp(-t / d) * np.sin(2 * math.pi * f * t + phase)
    return out


def noise_burst(seconds, decay, lo, hi):
    """Bant gecirgen suzgecten gecirilmis kisa gurultu (vurus transiyenti)."""
    n = int(SR * seconds)
    t = np.arange(n) / SR
    x = rng.standard_normal(n)
    # Frekans alaninda basit bir pencere ile bantla.
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(n, 1 / SR)
    window = np.exp(-((freqs - (lo + hi) / 2) ** 2) / (2 * ((hi - lo) / 2.5) ** 2))
    x = np.fft.irfft(spec * window, n)
    x /= (np.max(np.abs(x)) or 1)
    return x * np.exp(-t / decay)


def click(base_freq=520.0, seconds=0.16, bright=1.0, body=1.0, detune=0.02):
    """Tahta parcanin tahtaya vurusu."""
    ratios = [1.0, 1.59, 2.14, 2.78, 3.61, 4.9]
    decays = [0.055, 0.038, 0.028, 0.020, 0.014, 0.010]
    amps = [0.55 * body, 0.34, 0.22 * bright, 0.15 * bright,
            0.10 * bright, 0.07 * bright]
    tone = modes([base_freq * r for r in ratios], decays, amps, seconds,
                 detune=detune)
    hit = noise_burst(seconds, 0.006, 1800 * bright, 6500 * bright) * 0.5
    thump = modes([base_freq * 0.42], [0.045], [0.30 * body], seconds)
    return tone + hit + thump


def chime(freqs, seconds=0.55, decay=0.22, amp=0.5):
    """Yumusak, cana benzer iki-uc kismi harmonikli ton."""
    out = np.zeros(int(SR * seconds))
    for i, f in enumerate(freqs):
        part = modes([f, f * 2.01, f * 3.02], [decay, decay * 0.6, decay * 0.4],
                     [amp, amp * 0.28, amp * 0.12], seconds)
        out = place(out, part, i * 0.11)
    return out


def soften(x, attack=0.0015, release=0.012):
    """Tiklama olmasin diye kenarlari yumusatir."""
    n = len(x)
    a = min(int(SR * attack), n // 2)
    r = min(int(SR * release), n // 2)
    env = np.ones(n)
    if a:
        env[:a] = np.linspace(0, 1, a) ** 0.5
    if r:
        env[-r:] = np.linspace(1, 0, r) ** 0.7
    return x * env


def normalize(x, peak=0.80):
    m = np.max(np.abs(x))
    if m < 1e-9:
        return x
    return x / m * peak


def write_mp3(path, x, bitrate=128):
    x = soften(normalize(x))
    pcm = np.clip(x, -1.0, 1.0)
    pcm = (pcm * 32767).astype('<i2')
    enc = lameenc.Encoder()
    enc.set_bit_rate(bitrate)
    enc.set_in_sample_rate(SR)
    enc.set_channels(1)
    enc.set_quality(2)
    data = enc.encode(pcm.tobytes())
    data += enc.flush()
    with open(path, 'wb') as f:
        f.write(bytes(data))
    return len(data)


def build(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    sounds = {}

    # Kendi hamlen: net, orta tonlu bir tok ses.
    sounds['move-self'] = click(540, 0.18, bright=1.0, body=1.0)

    # Rakibin hamlesi: bir tik daha kalin ve donuk, ayirt edilebilsin.
    sounds['move-opponent'] = click(430, 0.18, bright=0.75, body=1.15)

    # Alma: daha sert vurus, altta govde.
    cap = click(620, 0.22, bright=1.35, body=0.9) * 1.0
    cap += noise_burst(0.22, 0.020, 900, 4200) * 0.35
    cap += modes([180, 240], [0.07, 0.05], [0.30, 0.18], 0.22)
    sounds['capture'] = cap

    # Rok: iki kisa vurus (sah, sonra kale).
    cas = silence(0.36)
    cas = place(cas, click(500, 0.16, body=0.95), 0.0)
    cas = place(cas, click(470, 0.18, body=1.05) * 0.9, 0.085)
    sounds['castle'] = cas

    # Sah: vurus + kisa uyarici ust ton.
    chk = silence(0.42)
    chk = place(chk, click(560, 0.18), 0.0)
    chk = place(chk, chime([1245.0], seconds=0.30, decay=0.09, amp=0.34), 0.035)
    sounds['move-check'] = chk

    # Terfi: yukselen ucluk.
    sounds['promote'] = chime([659.25, 830.61, 1046.50],
                              seconds=0.62, decay=0.20, amp=0.42)

    # Oyun basi: yumusak yukselen ikili.
    sounds['game-start'] = chime([392.00, 587.33], seconds=0.70,
                                 decay=0.26, amp=0.40)

    # Oyun sonu: alcalan ikili.
    sounds['game-end'] = chime([587.33, 392.00], seconds=0.85,
                               decay=0.30, amp=0.40)

    # Kural disi: donuk, bogazlanmis bir tok ses.
    ill = modes([150, 196, 233], [0.075, 0.055, 0.040],
                [0.5, 0.3, 0.2], 0.24, detune=0.03)
    ill += noise_burst(0.24, 0.012, 200, 900) * 0.35
    sounds['illegal'] = ill

    # Bildirim: kisa, parlak can.
    sounds['notify'] = chime([880.00, 1174.66], seconds=0.55,
                             decay=0.18, amp=0.38)

    total = 0
    for name, wave in sorted(sounds.items()):
        path = os.path.join(out_dir, name + '.mp3')
        size = write_mp3(path, wave)
        total += size
        print('  %-16s %6.2f s  %6d bayt' % (name, len(wave) / SR, size))
    print('toplam %d dosya, %.1f KB' % (len(sounds), total / 1024))


if __name__ == '__main__':
    build(sys.argv[1])
