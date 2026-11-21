#!/usr/bin/env python3
"""Procedural sound generator for Nordic Hunt: Moose Country.

Every sound in the game is synthesised here with numpy (no samples, no
third-party audio). Run:  python3 tools/gen_audio.py
Output: audio/*.wav (16-bit PCM, 44.1 kHz).
"""
import os
import sys
import wave
import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio")
rng = np.random.default_rng(1905)


# ----------------------------------------------------------------- helpers
def secs(t):
    return int(SR * t)


def tt(n):
    return np.arange(n) / SR


def white(n):
    return rng.standard_normal(n)


def shape(x, fn):
    """Filter x with an arbitrary magnitude response fn(freq_hz) -> gain."""
    n = len(x)
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    return np.fft.irfft(spec * fn(f), n)


def lp(x, fc, order=2):
    return shape(x, lambda f: 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order)))


def hp(x, fc, order=2):
    return shape(x, lambda f: 1.0 - 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order)))


def bp(x, f0, f1, order=2):
    return hp(lp(x, f1, order), f0, order)


def peak(x, f0, q, gain):
    """Resonant boost around f0."""
    return shape(x, lambda f: 1.0 + gain / (1.0 + ((f - f0) / (f0 / q)) ** 2))


def norm(x, level=0.95):
    m = np.max(np.abs(x))
    return x if m < 1e-9 else x * (level / m)


def fade(x, a=0.002, r=0.01):
    n = len(x)
    na, nr = min(secs(a), n // 2), min(secs(r), n // 2)
    y = x.copy()
    if na > 0:
        y[:na] *= np.linspace(0, 1, na)
    if nr > 0:
        y[-nr:] *= np.linspace(1, 0, nr)
    return y


def env_exp(n, tau):
    return np.exp(-tt(n) / tau)


def pad(x, n):
    if len(x) >= n:
        return x[:n]
    return np.concatenate([x, np.zeros(n - len(x))])


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def place(buf, x, t, gain=1.0):
    i = secs(t)
    j = min(len(buf), i + len(x))
    if j > i:
        buf[i:j] += x[: j - i] * gain


def convolve(x, ir):
    n = len(x) + len(ir) - 1
    m = 1 << (n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(x, m) * np.fft.rfft(ir, m), m)[:n]


def periodic_noise(n, fn):
    """Noise with magnitude response fn that loops seamlessly over n samples."""
    f = np.fft.rfftfreq(n, 1.0 / SR)
    mag = fn(f)
    phase = rng.uniform(0, 2 * np.pi, len(f))
    spec = mag * np.exp(1j * phase)
    spec[0] = 0
    x = np.fft.irfft(spec, n)
    return x / (np.std(x) + 1e-12)


def sine_sweep(n, f_start, f_end, curve=1.0):
    u = np.linspace(0, 1, n) ** curve
    f = f_start + (f_end - f_start) * u
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def tone(freq_arr):
    return np.sin(2 * np.pi * np.cumsum(freq_arr) / SR)


def write(name, x, level=0.95, stereo=False, normalize=True):
    os.makedirs(OUT, exist_ok=True)
    if normalize:
        x = norm(x, level)
    x = np.clip(x, -1, 1)
    data = (x * 32767).astype("<i2")
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(2 if stereo else 1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    dur = len(x) / SR
    print(f"  {name:22s} {dur:5.2f}s")


# ------------------------------------------------------------- gunshots
def outdoor_ir(length=2.6, decay=0.55, echoes=70, density=1.0, seed=1):
    """Impulse response of a forest valley: sparse slap-backs + diffuse tail."""
    r = np.random.default_rng(seed)
    n = secs(length)
    ir = np.zeros(n)
    for _ in range(echoes):
        t = r.uniform(0.07, length * 0.92) ** 1.25
        if t >= length * 0.95:
            continue
        a = r.uniform(0.25, 1.0) * np.exp(-t / decay) * r.choice([-1, 1])
        blob_n = secs(r.uniform(0.004, 0.02) * (1 + 2 * t))
        blob = r.standard_normal(blob_n) * np.hanning(blob_n)
        i = secs(t)
        j = min(n, i + blob_n)
        ir[i:j] += blob[: j - i] * a * 0.5
    diffuse = r.standard_normal(n) * np.exp(-tt(n) / (decay * 1.15)) * 0.10 * density
    diffuse[: secs(0.05)] *= np.linspace(0, 1, secs(0.05))
    ir += diffuse
    # distance eats the highs: darker the later it arrives
    early = lp(ir, 3800)
    late = lp(ir, 950)
    k = np.clip(tt(n) / 0.9, 0, 1)
    return early * (1 - k) + late * k


def gunshot(crack=1.0, body=1.0, boom=1.0, body_fc=850.0, boom_f=(120, 42),
            tail=0.42, tail_decay=0.55, length=2.9, drive=2.6, seed=1, mech=0.0):
    n = secs(0.5)
    t = tt(n)
    # supersonic crack: extremely short broadband burst
    c = hp(white(n), 1800) * np.exp(-t / 0.0035) * crack * 1.4
    c += hp(white(n), 5000) * np.exp(-t / 0.0012) * crack * 0.8
    # muzzle blast: band-limited body
    b = lp(white(n), body_fc) * np.exp(-t / 0.055) * body * 2.2
    b += bp(white(n), 250, 2600) * np.exp(-t / 0.026) * body * 1.1
    # sub thump
    s = sine_sweep(n, boom_f[0], boom_f[1], 0.5) * np.exp(-t / 0.085) * boom * 1.6
    dry = np.tanh((c + b + s) * drive)
    if mech > 0:  # semi-auto action clatter riding on the shot
        m = np.zeros(n)
        place(m, metal_click(2600, 0.03, 0.9), 0.055, mech)
        place(m, metal_click(1900, 0.035, 1.0), 0.105, mech)
        dry = dry + m
    ir = outdoor_ir(length - 0.45, tail_decay, seed=seed)
    wet = convolve(dry, ir)
    out = np.zeros(secs(length))
    place(out, dry, 0.0)
    place(out, wet / (np.max(np.abs(wet)) + 1e-9), 0.0, tail)
    out = np.tanh(out * 1.25)
    return fade(out, 0.0002, 0.35)


# ------------------------------------------------------------ mechanics
def metal_click(f0=2400.0, dur=0.04, bright=1.0):
    n = secs(dur + 0.12)
    t = tt(n)
    x = bp(white(n), 1500, 9000) * np.exp(-t / (dur * 0.22)) * 0.9 * bright
    for mult, a, d in ((1.0, 1.0, 1.0), (1.53, 0.6, 0.7), (2.31, 0.45, 0.5), (3.42, 0.25, 0.35)):
        x += np.sin(2 * np.pi * f0 * mult * t + rng.uniform(0, 6)) * np.exp(-t / (dur * d)) * a * 0.5
    x += lp(white(n), 500) * np.exp(-t / 0.012) * 0.8  # body knock
    return fade(x, 0.0003, 0.02)


def slide(dur=0.09, f0=1500, f1=4200):
    n = secs(dur)
    x = bp(white(n), f0, f1) * np.hanning(n) ** 0.6
    # grit
    x *= 0.6 + 0.4 * np.abs(lp(white(n), 240)) * 3
    return x


def casing_tink():
    n = secs(0.5)
    t = tt(n)
    out = np.zeros(n)
    for t0, g in ((0.0, 1.0), (0.11, 0.55), (0.19, 0.3), (0.245, 0.16)):
        m = secs(0.2)
        tm = tt(m)
        f = rng.uniform(4300, 5200)
        ping = (np.sin(2 * np.pi * f * tm) + 0.6 * np.sin(2 * np.pi * f * 1.48 * tm)
                + 0.4 * np.sin(2 * np.pi * f * 2.17 * tm)) * np.exp(-tm / 0.03)
        ping += hp(white(m), 3000) * np.exp(-tm / 0.004) * 0.6
        place(out, ping, t0, g)
    return fade(out, 0.0003, 0.05)


# ------------------------------------------------------------ footsteps
def step_soft(seed, crunch=0.5, dark=1.0):
    r = np.random.default_rng(seed)
    n = secs(0.28)
    t = tt(n)
    x = lp(r.standard_normal(n), 420 * dark) * np.exp(-t / 0.035) * 1.5       # heel thud
    x += bp(r.standard_normal(n), 900, 5200) * np.exp(-((t - 0.05) / 0.045) ** 2) * 0.35  # brush
    grains = np.zeros(n)
    for _ in range(int(26 * crunch)):
        t0 = r.uniform(0.01, 0.17)
        m = secs(r.uniform(0.002, 0.007))
        g = r.standard_normal(m) * np.hanning(m)
        place(grains, g, t0, r.uniform(0.2, 0.9))
    x += hp(grains, 1500) * 0.55 * crunch
    return fade(x, 0.001, 0.05)


def step_twig(seed):
    r = np.random.default_rng(seed)
    x = step_soft(seed, 0.9, 0.9)
    n = len(x)
    for _ in range(r.integers(1, 4)):
        m = secs(0.02)
        tm = tt(m)
        snap = (bp(r.standard_normal(m), 1200, 7000) * np.exp(-tm / 0.003)
                + np.sin(2 * np.pi * r.uniform(900, 1700) * tm) * np.exp(-tm / 0.006) * 0.6)
        place(x, snap, r.uniform(0.02, 0.15), r.uniform(0.5, 1.1))
    return fade(x[:n], 0.001, 0.05)


def step_rock(seed):
    r = np.random.default_rng(seed)
    n = secs(0.2)
    t = tt(n)
    x = bp(r.standard_normal(n), 500, 4200) * np.exp(-t / 0.014) * 1.2
    x += lp(r.standard_normal(n), 300) * np.exp(-t / 0.03)
    for _ in range(8):
        m = secs(0.004)
        place(x, r.standard_normal(m) * np.hanning(m), r.uniform(0.02, 0.11), r.uniform(0.2, 0.5))
    return fade(x, 0.0005, 0.04)


def splash(seed, dur=0.45, big=1.0):
    r = np.random.default_rng(seed)
    n = secs(dur)
    t = tt(n)
    x = bp(r.standard_normal(n), 350, 6500) * (np.exp(-t / (0.09 * big)) + 0.35 * np.exp(-t / (0.3 * big)))
    x += lp(r.standard_normal(n), 260) * np.exp(-t / 0.06) * 1.2 * big
    # bubbles
    for _ in range(int(14 * big)):
        m = secs(r.uniform(0.012, 0.035))
        tm = tt(m)
        f0 = r.uniform(500, 2400)
        bub = np.sin(2 * np.pi * (f0 + f0 * 0.6 * tm / tm[-1]) * tm) * np.hanning(m)
        place(x, bub, r.uniform(0.03, dur * 0.8), r.uniform(0.05, 0.25))
    return fade(x, 0.002, 0.12)


# -------------------------------------------------------------- impacts
def hit_flesh():
    n = secs(0.3)
    t = tt(n)
    x = lp(white(n), 520) * np.exp(-t / 0.03) * 2.0
    x += sine_sweep(n, 160, 60, 0.5) * np.exp(-t / 0.05) * 1.4
    x += bp(white(n), 700, 2600) * np.exp(-t / 0.012) * 0.7
    return fade(np.tanh(x * 1.6), 0.0003, 0.08)


def hit_dirt():
    n = secs(0.4)
    t = tt(n)
    x = lp(white(n), 700) * np.exp(-t / 0.045) * 1.6
    x += sine_sweep(n, 120, 50) * np.exp(-t / 0.05)
    grit = hp(white(n), 2200) * np.exp(-((t - 0.07) / 0.07) ** 2) * 0.3
    return fade(np.tanh((x + grit) * 1.4), 0.0003, 0.12)


def hit_wood():
    n = secs(0.35)
    t = tt(n)
    x = np.zeros(n)
    for f, a, d in ((420, 1.0, 0.03), (780, 0.8, 0.022), (1340, 0.5, 0.015), (2300, 0.3, 0.01)):
        x += np.sin(2 * np.pi * f * t) * np.exp(-t / d) * a
    x += bp(white(n), 900, 6000) * np.exp(-t / 0.01) * 1.1
    for _ in range(9):
        m = secs(0.005)
        place(x, hp(white(m), 2000) * np.hanning(m), rng.uniform(0.02, 0.2), rng.uniform(0.08, 0.3))
    return fade(np.tanh(x * 1.5), 0.0003, 0.08)


def ricochet():
    n = secs(0.85)
    t = tt(n)
    f = 3900 * np.exp(-t / 0.5) + 900 + 160 * np.sin(2 * np.pi * 21 * t) * np.exp(-t / 0.3)
    x = tone(f) * np.exp(-t / 0.22) * 0.8
    x += tone(f * 1.51) * np.exp(-t / 0.14) * 0.3
    x += bp(white(n), 1500, 8000) * np.exp(-t / 0.012) * 1.6
    x += lp(white(n), 600) * np.exp(-t / 0.025) * 1.2
    return fade(np.tanh(x * 1.3), 0.0003, 0.15)


def body_fall():
    n = secs(0.9)
    t = tt(n)
    x = lp(white(n), 180) * np.exp(-t / 0.09) * 3.0
    x += sine_sweep(n, 85, 38) * np.exp(-t / 0.13) * 1.8
    brush = bp(white(n), 800, 5000) * np.exp(-((t - 0.12) / 0.16) ** 2) * 0.28
    brush *= 0.5 + np.abs(lp(white(n), 60)) * 4
    x2 = np.zeros(n)
    place(x2, lp(white(secs(0.3)), 220) * env_exp(secs(0.3), 0.06), 0.27, 1.2)
    return fade(np.tanh((x + brush + x2) * 1.3), 0.001, 0.25)


def hoof(seed):
    r = np.random.default_rng(seed)
    n = secs(0.22)
    t = tt(n)
    x = lp(r.standard_normal(n), 240) * np.exp(-t / 0.04) * 2.4
    x += sine_sweep(n, 110, 55) * np.exp(-t / 0.045) * 1.2
    x += bp(r.standard_normal(n), 600, 3000) * np.exp(-t / 0.012) * 0.3
    return fade(np.tanh(x * 1.4), 0.0005, 0.06)


# ---------------------------------------------------------------- moose
def voiced(f0_arr, formants, breath=0.12, bright=0.9):
    """Glottal pulse train through a formant bank."""
    n = len(f0_arr)
    ph = np.cumsum(f0_arr) / SR
    saw = 2.0 * (ph % 1.0) - 1.0
    pulse = np.sign(np.sin(2 * np.pi * ph)) * 0.3
    src = saw * bright + pulse + white(n) * breath
    out = np.zeros(n)
    for f, q, g in formants:
        out += peak(src, f, q, 12) * g - src * g
    return lp(out + src * 0.25, 4200)


def moose_cow_call(dur=1.9, base=250.0, seed=3):
    r = np.random.default_rng(seed)
    n = secs(dur)
    u = np.linspace(0, 1, n)
    f0 = base * (0.78 + 0.34 * np.sin(np.pi * u ** 0.8) ** 1.4)
    f0 *= 1 + 0.018 * np.sin(2 * np.pi * 5.5 * tt(n)) + 0.01 * lp(r.standard_normal(n), 12) * 4
    x = voiced(f0, ((520, 5, 1.0), (1150, 7, 0.75), (2300, 8, 0.25)), 0.16)
    env = np.sin(np.pi * u) ** 0.55 * (0.75 + 0.25 * np.sin(np.pi * u * 2) ** 2)
    x = x * env
    x = hp(x, 140)
    return fade(x, 0.06, 0.25)


def moose_bull_grunt():
    out = np.zeros(secs(1.5))
    for t0, g, f in ((0.0, 1.0, 96), (0.52, 0.85, 90), (0.98, 0.7, 86)):
        n = secs(0.3)
        u = np.linspace(0, 1, n)
        f0 = f * (1.12 - 0.3 * u)
        x = voiced(f0, ((330, 4, 1.0), (760, 6, 0.6), (1500, 6, 0.15)), 0.3, 0.8)
        x *= np.sin(np.pi * u ** 0.55) ** 1.3
        place(out, x, t0, g)
    out = hp(out, 60)
    return fade(out, 0.01, 0.15)


def moose_snort():
    n = secs(0.5)
    t = tt(n)
    x = bp(white(n), 500, 4200) * (np.exp(-((t - 0.07) / 0.06) ** 2) + 0.4 * np.exp(-((t - 0.2) / 0.11) ** 2))
    x *= 0.7 + 0.3 * np.sin(2 * np.pi * 38 * t)
    x += lp(white(n), 300) * np.exp(-((t - 0.06) / 0.04) ** 2) * 0.9
    return fade(x, 0.01, 0.15)


# ----------------------------------------------------------------- birds
def chirp(f_a, f_b, dur, harm=0.2, curve=1.0):
    n = secs(dur)
    f = f_a + (f_b - f_a) * np.linspace(0, 1, n) ** curve
    x = tone(f) + harm * tone(f * 2)
    return x * np.hanning(n) ** 0.7


def bird_tit():  # two-note "tee-cha tee-cha"
    out = np.zeros(secs(1.5))
    for i in range(4):
        place(out, chirp(5200, 5000, 0.11), i * 0.34)
        place(out, chirp(3700, 3550, 0.13), i * 0.34 + 0.15, 0.9)
    return out


def bird_finch():  # accelerating descending rattle with a flourish
    out = np.zeros(secs(2.2))
    t0 = 0.0
    for i in range(11):
        f = 5600 - i * 260
        place(out, chirp(f + 500, f, 0.07, 0.25), t0, 0.7 + 0.03 * i)
        t0 += 0.13 - i * 0.005
    place(out, chirp(2600, 4600, 0.12, 0.3), t0 + 0.02)
    place(out, chirp(4600, 2300, 0.16, 0.3), t0 + 0.15)
    return out


def bird_warbler():  # soft descending whistles
    out = np.zeros(secs(2.4))
    t0 = 0.0
    for i in range(9):
        f = 5400 - i * 290 + rng.uniform(-80, 80)
        place(out, chirp(f + 350, f - 250, 0.14, 0.1, 0.7), t0, 0.5 + 0.05 * i)
        t0 += 0.2
    return out


def bird_robin():  # liquid random warble
    out = np.zeros(secs(2.6))
    t0 = 0.0
    r = np.random.default_rng(11)
    while t0 < 2.2:
        f = r.uniform(2600, 6200)
        d = r.uniform(0.05, 0.16)
        place(out, chirp(f, f * r.uniform(0.75, 1.3), d, 0.15, r.uniform(0.6, 1.6)), t0, r.uniform(0.5, 1.0))
        t0 += d + r.uniform(0.0, 0.09)
        if r.random() < 0.18:
            t0 += 0.18
    return out


def bird_thrush():  # repeated fluty phrases
    out = np.zeros(secs(2.8))
    r = np.random.default_rng(23)
    t0 = 0.0
    for _ in range(3):
        fa, fb = r.uniform(2200, 3600), r.uniform(2200, 4200)
        for _ in range(3):
            place(out, chirp(fa, fb, 0.16, 0.3), t0)
            t0 += 0.24
        t0 += 0.3
    return out


def woodpecker():
    out = np.zeros(secs(1.2))
    t0 = 0.0
    for i in range(17):
        m = secs(0.035)
        tm = tt(m)
        k = (np.sin(2 * np.pi * 950 * tm) + 0.6 * np.sin(2 * np.pi * 1730 * tm)) * np.exp(-tm / 0.006)
        k += bp(white(m), 800, 5000) * np.exp(-tm / 0.002) * 0.7
        g = np.sin(np.pi * (i + 1) / 18) ** 0.5
        place(out, k, t0, g)
        t0 += 0.058 - i * 0.0011
    return out


def crow(n_caws=3, f=520.0, rough=1.0):
    out = np.zeros(secs(0.5 * n_caws + 0.3))
    for i in range(n_caws):
        n = secs(0.33)
        u = np.linspace(0, 1, n)
        f0 = f * (1.08 - 0.2 * u) * (1 + 0.05 * rough * lp(white(n), 90) * 3)
        x = voiced(f0, ((1250, 4, 1.0), (2400, 5, 0.8), (3600, 6, 0.3)), 0.5 * rough, 1.0)
        x *= np.sin(np.pi * u ** 0.6) ** 0.8
        x *= 0.6 + 0.4 * np.sign(np.sin(2 * np.pi * 62 * tt(n)))
        place(out, x, i * 0.5 + rng.uniform(0, 0.04))
    return hp(out, 500)


def owl():
    out = np.zeros(secs(3.4))
    for t0, d, g in ((0.0, 0.5, 1.0), (1.45, 0.16, 0.8), (1.72, 0.7, 1.0)):
        n = secs(d)
        u = np.linspace(0, 1, n)
        f0 = 365 * (1 + 0.04 * np.sin(np.pi * u)) * (1 + 0.012 * np.sin(2 * np.pi * 14 * tt(n)))
        x = (tone(f0) + 0.18 * tone(f0 * 2) + 0.06 * tone(f0 * 3)) * np.sin(np.pi * u) ** 0.7
        place(out, x, t0, g)
    return lp(out, 2500)


def loon():
    n = secs(3.0)
    u = np.linspace(0, 1, n)
    f0 = np.interp(u, [0, 0.12, 0.3, 0.72, 0.9, 1.0], [560, 600, 905, 930, 720, 640])
    f0 = f0 * (1 + 0.006 * np.sin(2 * np.pi * 6 * tt(n)))
    x = tone(f0) + 0.32 * tone(f0 * 2) + 0.1 * tone(f0 * 3)
    env = np.interp(u, [0, 0.08, 0.3, 0.75, 1.0], [0, 0.5, 1.0, 0.85, 0])
    return lp(x * env, 3800)


# -------------------------------------------------------------- ambience
def wind_loop(dur=14.0):
    n = secs(dur)
    chans = []
    for c in range(2):
        low = periodic_noise(n, lambda f: 1.0 / (1.0 + (f / 180.0) ** 2) * (f > 25))
        mid = periodic_noise(n, lambda f: np.exp(-((np.log(f + 1) - np.log(650)) / 0.75) ** 2))
        high = periodic_noise(n, lambda f: np.exp(-((np.log(f + 1) - np.log(3600)) / 0.6) ** 2))
        t = tt(n)
        # gust LFOs with whole numbers of cycles so the loop is seamless
        g1 = 0.5 + 0.5 * np.sin(2 * np.pi * 2 * t / dur + c * 1.3)
        g2 = 0.5 + 0.5 * np.sin(2 * np.pi * 5 * t / dur + 2.1 + c * 0.7)
        g3 = 0.5 + 0.5 * np.sin(2 * np.pi * 9 * t / dur + 4.0 + c)
        gust = 0.35 + 0.4 * g1 + 0.25 * g2 * g1
        x = low * 0.55 + mid * gust * 0.55 + high * (0.1 + 0.25 * g3 * gust)
        chans.append(x)
    st = np.stack(chans, axis=1)
    return st / np.max(np.abs(st))


def water_loop(dur=9.0):
    n = secs(dur)
    chans = []
    for c in range(2):
        t = tt(n)
        x = periodic_noise(n, lambda f: np.exp(-((np.log(f + 1) - np.log(1100)) / 0.9) ** 2))
        lap = 0.25 + 0.75 * (0.5 + 0.5 * np.sin(2 * np.pi * 4 * t / dur + c)) ** 2
        lap2 = 0.5 + 0.5 * np.sin(2 * np.pi * 11 * t / dur + 1.7 * c)
        x = x * lap * (0.6 + 0.4 * lap2)
        low = periodic_noise(n, lambda f: 1.0 / (1.0 + (f / 220.0) ** 2) * (f > 30)) * 0.35 * lap
        r = np.random.default_rng(40 + c)
        bub = np.zeros(n)
        for _ in range(int(dur * 9)):
            m = secs(r.uniform(0.012, 0.04))
            tm = tt(m)
            f0 = r.uniform(450, 1900)
            b = np.sin(2 * np.pi * (f0 + f0 * 0.5 * tm / tm[-1]) * tm) * np.hanning(m)
            t0 = r.uniform(0, dur - 0.06)
            place(bub, b, t0, r.uniform(0.3, 1.0))
        chans.append(x + low + bub * 1.4)
    st = np.stack(chans, axis=1)
    return st / np.max(np.abs(st))


def menu_pad(dur=24.0):
    """Slow, cold drone for the menu: D minor add9 built from drifting partials."""
    n = secs(dur)
    t = tt(n)
    chans = []
    notes = [73.42, 110.0, 146.83, 174.61, 220.0, 329.63, 440.0, 587.33]
    for c in range(2):
        r = np.random.default_rng(70 + c)
        x = np.zeros(n)
        for i, f in enumerate(notes):
            for h in (1, 2, 3):
                # quantise so every partial completes whole cycles -> seamless loop
                fq = round(f * h * (1 + r.uniform(-0.003, 0.003)) * dur) / dur
                cyc = r.integers(1, 5)
                lfo = 0.5 + 0.5 * np.sin(2 * np.pi * cyc * t / dur + r.uniform(0, 6.28))
                amp = (1.0 / h ** 1.6) * (0.9 if i < 5 else 0.45)
                x += np.sin(2 * np.pi * fq * t + r.uniform(0, 6.28)) * amp * (0.35 + 0.65 * lfo)
        air = periodic_noise(n, lambda f: np.exp(-((np.log(f + 1) - np.log(2400)) / 0.5) ** 2))
        x += air * 0.5 * (0.5 + 0.5 * np.sin(2 * np.pi * 3 * t / dur + c))
        chans.append(x)
    st = np.stack(chans, axis=1)
    return st / np.max(np.abs(st))


# -------------------------------------------------------------------- ui
def ui_tick(f=1800, dur=0.05):
    n = secs(dur)
    t = tt(n)
    return fade((np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * f * 2.02 * t)) * np.exp(-t / (dur * 0.25)), 0.001, 0.01)


def chime(freqs, dur=0.6, gap=0.09):
    out = np.zeros(secs(dur + gap * len(freqs)))
    for i, f in enumerate(freqs):
        n = secs(dur)
        t = tt(n)
        x = (np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * f * 2 * t) + 0.12 * np.sin(2 * np.pi * f * 3.01 * t))
        place(out, x * np.exp(-t / (dur * 0.28)), i * gap)
    return fade(out, 0.002, 0.08)


def kill_stinger():
    n = secs(1.6)
    t = tt(n)
    drum = sine_sweep(n, 95, 44, 0.4) * np.exp(-t / 0.22) * 1.5 + lp(white(n), 300) * np.exp(-t / 0.05)
    out = np.tanh(drum * 1.5) * 0.9
    for f, t0, g in ((293.66, 0.02, 0.5), (440.0, 0.1, 0.45), (587.33, 0.2, 0.42), (880.0, 0.32, 0.2)):
        m = secs(1.2)
        tm = tt(m)
        x = (np.sin(2 * np.pi * f * tm) + 0.4 * np.sin(2 * np.pi * f * 2 * tm)) * np.exp(-tm / 0.38)
        place(out, fade(x, 0.01, 0.1), t0, g)
    return fade(out, 0.001, 0.2)


def breath(inhale=True):
    n = secs(1.1 if inhale else 1.4)
    u = np.linspace(0, 1, n)
    fc = 1500 + 1400 * (u if inhale else (1 - u))
    x = np.zeros(n)
    for f0, f1 in ((600, 1400), (1400, 2600), (2600, 4200)):
        w = np.exp(-((np.log(fc) - np.log((f0 + f1) / 2)) / 0.5) ** 2)
        x += bp(white(n), f0, f1) * w
    env = np.sin(np.pi * u ** (0.7 if inhale else 0.45)) ** 1.2
    return fade(x * env, 0.03, 0.1)


def cloth_rustle(dur=0.35, seed=5):
    r = np.random.default_rng(seed)
    n = secs(dur)
    x = bp(r.standard_normal(n), 700, 5200) * np.hanning(n) ** 0.8
    x *= 0.35 + np.abs(lp(r.standard_normal(n), 35)) * 5
    return fade(x, 0.01, 0.05)


# -------------------------------------------------------------------- run
def main():
    print("Generating audio ->", os.path.normpath(OUT))

    # rifles -------------------------------------------------------------
    write("shot_308", gunshot(seed=1))
    write("shot_65", gunshot(crack=1.15, body=0.9, boom=0.75, body_fc=1000, boom_f=(135, 50), tail=0.38, seed=2))
    write("shot_93", gunshot(crack=0.9, body=1.15, boom=1.2, body_fc=700, boom_f=(110, 38), tail=0.44, seed=3, mech=0.2))
    write("shot_4570", gunshot(crack=0.6, body=1.3, boom=1.5, body_fc=560, boom_f=(100, 34), tail=0.46, tail_decay=0.6, seed=4, drive=3.0))
    write("shot_300", gunshot(crack=1.3, body=1.2, boom=1.35, body_fc=820, boom_f=(125, 36), tail=0.52, tail_decay=0.75, length=3.5, seed=5, drive=3.2))
    write("shot_470", gunshot(crack=0.7, body=1.5, boom=1.9, body_fc=480, boom_f=(92, 30), tail=0.5, tail_decay=0.7, length=3.3, seed=6, drive=3.4))

    up = mix(metal_click(2300, 0.03, 0.8), pad(np.zeros(1), 1))
    write("bolt_up", up, 0.55)
    back = np.zeros(secs(0.3))
    place(back, slide(0.1, 1300, 3800), 0.0, 0.5)
    place(back, metal_click(1700, 0.045, 1.0), 0.095, 1.0)
    write("bolt_back", back, 0.7)
    fwd = np.zeros(secs(0.3))
    place(fwd, slide(0.09, 1500, 4400), 0.0, 0.5)
    place(fwd, metal_click(2000, 0.04, 1.0), 0.085, 1.0)
    write("bolt_fwd", fwd, 0.7)
    write("bolt_down", metal_click(2700, 0.035, 0.9), 0.6)

    lev = np.zeros(secs(0.3))
    place(lev, metal_click(1500, 0.03, 0.8), 0.0, 0.8)
    place(lev, slide(0.07, 1100, 3200), 0.01, 0.45)
    place(lev, metal_click(2100, 0.035, 1.0), 0.085, 1.0)
    write("lever_open", lev, 0.7)
    lev2 = np.zeros(secs(0.3))
    place(lev2, slide(0.06, 1300, 3600), 0.0, 0.45)
    place(lev2, metal_click(2500, 0.03, 1.0), 0.06, 1.0)
    place(lev2, metal_click(1800, 0.03, 0.6), 0.1, 0.6)
    write("lever_close", lev2, 0.7)

    mo = np.zeros(secs(0.35))
    place(mo, metal_click(1400, 0.03, 0.7), 0.0, 0.9)
    place(mo, slide(0.12, 700, 2400), 0.03, 0.4)
    write("mag_out", mo, 0.6)
    mi = np.zeros(secs(0.4))
    place(mi, slide(0.09, 800, 2600), 0.0, 0.35)
    place(mi, metal_click(1650, 0.05, 1.0), 0.09, 1.0)
    place(mi, metal_click(2500, 0.02, 0.5), 0.13, 0.4)
    write("mag_in", mi, 0.7)

    write("dry_fire", metal_click(3100, 0.018, 0.7), 0.4)
    bo = np.zeros(secs(0.4))
    place(bo, metal_click(1250, 0.05, 0.9), 0.0, 1.0)
    place(bo, metal_click(900, 0.06, 0.6), 0.09, 0.7)
    write("break_open", bo, 0.7)
    bc = np.zeros(secs(0.35))
    place(bc, metal_click(1100, 0.06, 1.0), 0.0, 1.0)
    place(bc, metal_click(2300, 0.03, 0.7), 0.012, 0.6)
    write("break_close", bc, 0.75)
    si = np.zeros(secs(0.25))
    place(si, slide(0.06, 2000, 5200), 0.0, 0.3)
    place(si, metal_click(3300, 0.02, 0.8), 0.055, 0.8)
    write("shell_insert", si, 0.5)
    write("casing", casing_tink(), 0.35)
    write("rustle_1", cloth_rustle(0.35, 5), 0.3)
    write("rustle_2", cloth_rustle(0.5, 6), 0.3)

    # movement -----------------------------------------------------------
    for i in range(4):
        write(f"step_grass_{i + 1}", step_soft(100 + i, 0.45, 1.0), 0.5)
        write(f"step_forest_{i + 1}", step_twig(200 + i), 0.55)
    for i in range(3):
        write(f"step_rock_{i + 1}", step_rock(300 + i), 0.5)
        write(f"step_water_{i + 1}", splash(400 + i, 0.4, 0.6), 0.55)
    write("land", mix(step_soft(500, 0.8, 0.8) * 1.3, pad(cloth_rustle(0.25, 9) * 0.3, secs(0.28))), 0.7)

    # impacts ------------------------------------------------------------
    write("hit_flesh", hit_flesh(), 0.9)
    write("hit_dirt", hit_dirt(), 0.8)
    write("hit_wood", hit_wood(), 0.85)
    write("hit_rock", ricochet(), 0.8)
    write("hit_water", splash(600, 0.8, 1.6), 0.85)
    write("body_fall", body_fall(), 0.95)
    for i in range(3):
        write(f"hoof_{i + 1}", hoof(700 + i), 0.8)

    # moose --------------------------------------------------------------
    write("moose_cow_1", moose_cow_call(1.9, 250, 3), 0.85)
    write("moose_cow_2", moose_cow_call(2.4, 228, 4), 0.85)
    write("moose_bull", moose_bull_grunt(), 0.9)
    write("moose_snort", moose_snort(), 0.7)
    write("call_blow", moose_cow_call(2.1, 262, 8), 0.9)

    # birds --------------------------------------------------------------
    write("bird_1", fade(bird_tit(), 0.01, 0.05), 0.5)
    write("bird_2", fade(bird_finch(), 0.01, 0.05), 0.5)
    write("bird_3", fade(bird_warbler(), 0.01, 0.05), 0.45)
    write("bird_4", fade(bird_robin(), 0.01, 0.05), 0.45)
    write("bird_5", fade(bird_thrush(), 0.01, 0.05), 0.5)
    write("woodpecker", fade(woodpecker(), 0.005, 0.05), 0.6)
    write("crow", fade(crow(3, 520, 1.0), 0.01, 0.1), 0.6)
    write("raven", fade(crow(2, 330, 1.5), 0.01, 0.1), 0.6)
    write("owl", fade(owl(), 0.02, 0.2), 0.6)
    write("loon", fade(loon(), 0.05, 0.3), 0.55)

    # ambience (stereo, seamless) ---------------------------------------
    write("wind_loop", wind_loop().reshape(-1), 0.8, stereo=True)
    write("water_loop", water_loop().reshape(-1), 0.7, stereo=True)
    write("menu_pad", menu_pad().reshape(-1), 0.75, stereo=True)

    # ui ------------------------------------------------------------------
    write("ui_hover", ui_tick(2300, 0.035), 0.18)
    write("ui_click", mix(ui_tick(1500, 0.06), ui_tick(3000, 0.03) * 0.4), 0.35)
    write("ui_back", ui_tick(1000, 0.07), 0.3)
    write("ui_buy", chime([659.25, 880.0, 1318.5], 0.7, 0.085), 0.5)
    write("ui_error", chime([196.0, 185.0], 0.25, 0.1), 0.4)
    write("zoom_tick", ui_tick(3400, 0.02), 0.2)
    write("kill", kill_stinger(), 0.75)
    write("tag", chime([587.33, 880.0], 0.5, 0.11), 0.4)
    write("breath_in", breath(True), 0.35)
    write("breath_out", breath(False), 0.35)
    main_dog()
    print("done.")


# ------------------------------------------------------------------- dog
def dog_bark(seed, base=560.0, dur=0.2, rough=1.0):
    """An elkhound's bark: sharp and high, a quick rise and fall of pitch through a
    small dog's mouth, a breathy burst at the start, a little forest echo."""
    r = np.random.default_rng(seed)
    n = secs(dur)
    u = np.linspace(0, 1, n)
    f0 = base * (0.86 + 0.32 * np.sin(np.pi * np.minimum(u * 1.6, 1.0)) ** 0.7) * (1.0 - 0.22 * u)
    f0 *= 1 + 0.03 * rough * lp(r.standard_normal(n), 60) * 3
    src_n = len(f0)
    ph = np.cumsum(f0) / SR
    saw = 2.0 * (ph % 1.0) - 1.0
    src = saw + 0.35 * np.sign(np.sin(2 * np.pi * ph)) + r.standard_normal(src_n) * 0.28 * rough
    out = np.zeros(src_n)
    for f, q, g in ((900, 4, 1.0), (1750, 5, 0.8), (3100, 6, 0.45)):
        out += peak(src, f, q, 12) * g - src * g
    x = lp(out + src * 0.2, 5200)
    env = np.minimum(u / 0.04, 1.0) ** 0.6 * np.exp(-u * 2.4) * (1.0 - u) ** 0.5
    x *= env
    burst = bp(r.standard_normal(secs(0.05)), 900, 5000) * np.exp(-tt(secs(0.05)) / 0.012)
    x = mix(x, burst * 0.5)
    x = hp(x, 260)
    wet = convolve(x, outdoor_ir(1.2, 0.3, 40, 0.8, seed + 50)) * 0.12
    return fade(mix(x, wet), 0.002, 0.2)


def dog_whistle():
    """Two shrill blasts on a dog whistle: come in."""
    out = np.zeros(secs(1.05))
    for t0, d, f in ((0.0, 0.32, 2650.0), (0.45, 0.5, 2580.0)):
        n = secs(d)
        u = np.linspace(0, 1, n)
        fr = f * (1 + 0.012 * np.sin(2 * np.pi * 26 * tt(n))) * (1.0 - 0.02 * u)
        x = tone(fr) + 0.12 * tone(fr * 2) + white(n) * 0.06
        x *= np.minimum(u / 0.05, 1.0) * np.minimum((1 - u) / 0.12, 1.0)
        place(out, x, t0)
    return bp(out, 1500, 7000)


def main_dog():
    for i, (seed, base, dur, rough) in enumerate(((901, 560, 0.2, 1.0), (902, 610, 0.17, 0.9), (903, 520, 0.23, 1.2), (904, 585, 0.19, 1.05))):
        write(f"dog_bark_{i + 1}", dog_bark(seed, base, dur, rough), 0.9)
    write("dog_whistle", dog_whistle(), 0.6)


if __name__ == "__main__":
    sys.exit(main())
