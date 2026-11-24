"""Measurements of a drum sample, for the classifier and the descriptive tags (numpy).

Read from the converted WAV, mixed to mono; only the first MAX_S seconds are measured (the
length is the whole file's). Frequencies are absolute, so a sound from a low-rate machine
simply has no energy in the top bands.
"""

import math

import numpy as np

from . import audio

MAX_S = 3.0
BANDS = [(20, 80), (80, 200), (200, 500), (500, 1200), (1200, 3000), (3000, 6000), (6000, 12000), (12000, 24000)]
ENV_HOP_S = 0.002


def load(path):
    """(mono float array, rate, channels, stereo width 0..1, seconds) from a WAV or AIFF."""
    with open(path, "rb") as fh:
        s = audio.read(fh.read())
    w, ch = s.width, s.channels
    n = s.frames
    d = s.data[: n * s.block]
    if s.is_float:
        x = np.frombuffer(d, dtype="<f4" if w == 4 else "<f8").astype(np.float64)
    elif w == 1:
        x = (np.frombuffer(d, dtype=np.uint8).astype(np.float64) - 128.0) / 128.0
    elif w == 2:
        x = np.frombuffer(d, dtype="<i2") / 32768.0
    elif w == 3:
        b = np.frombuffer(d, dtype=np.uint8).reshape(-1, 3).astype(np.int32)
        v = b[:, 0] | (b[:, 1] << 8) | (b[:, 2] << 16)
        x = np.where(v & 0x800000, v - 0x1000000, v) / 8388608.0
    else:
        x = np.frombuffer(d, dtype="<i4") / 2147483648.0
    x = x.reshape(-1, ch) if ch > 1 else x.reshape(-1, 1)
    width = 0.0
    if ch == 2:
        mid = 0.5 * (x[:, 0] + x[:, 1])
        side = 0.5 * (x[:, 0] - x[:, 1])
        em, es = float(np.sum(mid ** 2)), float(np.sum(side ** 2))
        width = es / (em + es) if em + es > 0 else 0.0
    mono = x.mean(axis=1)
    return mono, s.rate, ch, width, n / s.rate if s.rate else 0.0


def _db(v):
    return 20.0 * math.log10(max(v, 1e-9))


def _f0(seg, sr, lo=25.0, hi=2500.0):
    """(Hz, clarity 0..1) from the normalised autocorrelation's strongest peak."""
    if len(seg) < 64:
        return 0.0, 0.0
    seg = seg - seg.mean()
    if np.max(np.abs(seg)) < 1e-5:
        return 0.0, 0.0
    n = len(seg)
    sp = np.fft.rfft(seg * np.hanning(n), 2 * n)
    ac = np.fft.irfft(sp * np.conj(sp))[:n]
    if ac[0] <= 0:
        return 0.0, 0.0
    ac = ac / ac[0]
    a, b = max(2, int(sr / hi)), min(n - 1, int(sr / lo))
    if b <= a:
        return 0.0, 0.0
    # Search only past the first dip below zero: before it, every lag of a low sound is near 1.
    neg = np.nonzero(ac[a:b] < 0)[0]
    if not len(neg):
        return 0.0, 0.0
    a2 = a + int(neg[0])
    if b - a2 < 2:
        return 0.0, 0.0
    k = a2 + int(np.argmax(ac[a2:b]))
    return float(sr / k), float(max(0.0, ac[k]))


def measure(path):
    x, sr, ch, width, seconds = load(path)
    m = {"seconds": round(seconds, 4), "rate": sr, "channels": ch, "width": round(width, 4)}
    peak = float(np.max(np.abs(x))) if len(x) else 0.0
    m["peak_db"] = round(_db(peak), 2)
    if peak < 1e-4:
        m["silent"] = True
        return m
    m["silent"] = False
    x = x[: int(MAX_S * sr)]
    # Envelope: RMS in 2 ms hops over 4 ms windows.
    hop = max(1, int(ENV_HOP_S * sr))
    win = 2 * hop
    nfr = max(1, (len(x) - win) // hop + 1)
    idx = np.arange(win)[None, :] + hop * np.arange(nfr)[:, None]
    env = np.sqrt(np.mean(x[np.minimum(idx, len(x) - 1)] ** 2, axis=1)) + 1e-12
    t = np.arange(nfr) * ENV_HOP_S
    ep = float(env.max())
    pk = int(np.argmax(env))
    onset = int(np.argmax(env > ep * 0.01))          # -40 dB under the peak
    m["onset_s"] = round(float(t[onset]), 4)
    m["attack_s"] = round(float(t[pk] - t[onset]), 4)

    def after(db_down):
        below = np.nonzero(env[pk:] < ep * 10 ** (-db_down / 20.0))[0]
        return float(below[0] * ENV_HOP_S) if len(below) else float(t[-1] - t[pk]) + ENV_HOP_S

    m["decay20_s"] = round(after(20), 4)
    m["decay40_s"] = round(after(40), 4)
    for ms in (20, 50, 100, 200, 400, 800):
        i = min(nfr - 1, pk + int(ms / 1000.0 / ENV_HOP_S))
        m["lvl_%d" % ms] = round(_db(env[i] / ep), 2)
    # Onsets later in the sound (loops, flams, rolls): rises of 9 dB over 30 ms after 60 ms.
    sm = np.convolve(env, np.ones(5) / 5.0, mode="same")
    lag = int(0.03 / ENV_HOP_S)
    rise = sm[lag:] / (sm[:-lag] + 1e-12) if len(sm) > lag else np.zeros(1)
    hits = np.nonzero((rise > 2.8) & (sm[lag:] > ep * 0.1))[0]
    starts = [h for i, h in enumerate(hits) if i == 0 or h - hits[i - 1] > lag]
    m["onsets"] = int(sum(1 for h in starts if (h + lag) * ENV_HOP_S > m["onset_s"] + 0.06))

    # Spectrum: the first 80 ms from the onset (the hit) and 80..400 ms (the body/tail).
    o = int(m["onset_s"] * sr)
    for name, a, b in (("hit", 0.0, 0.08), ("body", 0.08, 0.4)):
        seg = x[o + int(a * sr): o + int(b * sr)]
        if len(seg) < 256 or np.max(np.abs(seg)) < peak * 0.003:
            m[name + "_silent"] = True
            for key in ("centroid", "rolloff", "flatness", "zcr"):
                m["%s_%s" % (name, key)] = 0.0
            for i in range(len(BANDS)):
                m["%s_b%d" % (name, i)] = 0.0
            continue
        m[name + "_silent"] = False
        spec = np.abs(np.fft.rfft(seg * np.hanning(len(seg)))) ** 2 + 1e-18
        f = np.fft.rfftfreq(len(seg), 1.0 / sr)
        tot = spec.sum()
        m[name + "_centroid"] = round(float((spec * f).sum() / tot), 1)
        c = np.cumsum(spec) / tot
        m[name + "_rolloff"] = round(float(f[min(len(f) - 1, int(np.searchsorted(c, 0.85)))]), 1)
        m[name + "_flatness"] = round(float(np.exp(np.mean(np.log(spec))) / np.mean(spec)), 5)
        m[name + "_zcr"] = round(float(np.mean(np.abs(np.diff(np.sign(seg))) > 0) * sr / 2.0), 1)
        for i, (lo, hi) in enumerate(BANDS):
            m["%s_b%d" % (name, i)] = round(float(spec[(f >= lo) & (f < hi)].sum() / tot), 5)
    # A finer picture for the classifier: 16 log-spaced bands (40 Hz-16 kHz) in three windows (the
    # transient 0-15 ms, the hit 15-80 ms, the body 80-400 ms), each band in dB under the window's
    # loudest, and each window's level under the sound's peak.
    edges = np.geomspace(40.0, 16000.0, 17)
    for wi, (a0, b0) in enumerate(((0.0, 0.015), (0.015, 0.08), (0.08, 0.4))):
        seg = x[o + int(a0 * sr): o + int(b0 * sr)]
        if len(seg) < 64:
            seg = np.zeros(64)
        n_fft = 1 << max(9, int(np.ceil(np.log2(len(seg)))))
        spec = np.abs(np.fft.rfft(seg * np.hanning(len(seg)), n_fft)) ** 2 + 1e-18
        f = np.fft.rfftfreq(n_fft, 1.0 / sr)
        bands = np.array([spec[(f >= edges[i]) & (f < edges[i + 1])].sum() for i in range(16)]) + 1e-18
        db = 10.0 * np.log10(bands / bands.max())
        m["sp%d" % wi] = [round(float(max(v, -80.0)), 1) for v in db]
        m["lv%d" % wi] = round(_db(float(np.sqrt(np.mean(seg ** 2))) / peak), 1)
    # Pitch: early (10-50 ms) and later (100-200 ms), so a falling kick or tom shows its drop.
    f_early, c_early = _f0(x[o + int(0.005 * sr): o + int(0.06 * sr)], sr)
    f_late, c_late = _f0(x[o + int(0.1 * sr): o + int(0.2 * sr)], sr)
    m["f0_early"], m["clarity_early"] = round(f_early, 1), round(c_early, 3)
    m["f0_late"], m["clarity_late"] = round(f_late, 1), round(c_late, 3)
    m["pitch_drop"] = round(12.0 * math.log2(f_early / f_late), 2) if f_early > 0 and f_late > 0 else 0.0
    # Bandwidth: where the spectrum of the whole measured part falls 60 dB under its peak bin.
    spec = np.abs(np.fft.rfft(x[o:o + int(0.5 * sr)] * np.hanning(len(x[o:o + int(0.5 * sr)])))) if len(x) - o > 256 else None
    if spec is not None:
        f = np.fft.rfftfreq(len(x[o:o + int(0.5 * sr)]), 1.0 / sr)
        sm = np.convolve(spec, np.ones(31) / 31.0, mode="same")
        live = np.nonzero(sm > sm.max() * 1e-3)[0]
        m["bandwidth_hz"] = round(float(f[live[-1]]), 1) if len(live) else 0.0
    else:
        m["bandwidth_hz"] = 0.0
    return m
