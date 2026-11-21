# SPDX-License-Identifier: Apache-2.0
"""Synth1's LFOs: what each destination moves, each wave's shape, the rate
per speed value and the depth per depth value. Writes data/lfo.json."""
import json
import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from synth1 import SR, Synth1, neutral  # noqa: E402
from measure_env import envelope  # noqa: E402

OUT = pathlib.Path(__file__).parent / "data"


def inst_freq(x):
	"""Instantaneous frequency (Hz) of a sine-like signal, smoothed."""
	n = len(x)
	X = np.fft.fft(x)
	h = np.zeros(n)
	h[0] = 1
	h[1:(n + 1) // 2] = 2
	if n % 2 == 0:
		h[n // 2] = 1
	ph = np.unwrap(np.angle(np.fft.ifft(X * h)))
	f = np.diff(ph) * SR / (2 * np.pi)
	return np.convolve(f, np.ones(480) / 480, mode="same")


def lfo_patch(**over):
	return neutral(**dict(dict(osc1_shape=0, lfo1_on=1, lfo1_type=1, lfo1_speed=64, lfo1_depth=127, lfo1_dest=4, lfo1_sync=0, lfo1_keysync=1), **over))


def period(sig, lo, hi):
	"""The strongest repetition period (s) between lo and hi seconds, by autocorrelation."""
	s = sig - np.mean(sig)
	n = len(s)
	ac = np.fft.irfft(np.abs(np.fft.rfft(s, 2 * n)) ** 2)[:n]
	a, b = max(1, int(lo * SR)), min(n - 1, int(hi * SR))
	if b <= a:
		return None
	k = a + int(np.argmax(ac[a:b]))
	# The first strong peak, so a multiple doesn't win.
	for j in range(a + 1, b - 1):
		if ac[j] > 0.8 * ac[k] and ac[j] >= ac[j - 1] and ac[j] >= ac[j + 1]:
			k = j
			break
	return k / SR


def run():
	s = Synth1()
	out = {"dests": {}, "types": {}, "rate_hz": {}, "depth": {}}
	# Destinations: level, pitch, brightness and balance movement per dest value.
	for d in range(8):
		s.load(lfo_patch(lfo1_dest=d, f_freq=90, osc1_shape=1, lfo1_speed=70))
		a = s.render([(57, 127, 0.0, 3.0)], 3.0)
		l, r = a[0][SR // 2:], a[1][SR // 2:]
		m = (l + r) * 0.5
		e = envelope(m, 480)
		bal = envelope(l, 480) / (envelope(r, 480) + 1e-9)
		s2 = dict(lfo_patch(lfo1_dest=d, lfo1_speed=70))
		s.load(s2)
		f = inst_freq(((lambda q: (q[0] + q[1]) * 0.5)(s.render([(57, 127, 0.0, 3.0)], 3.0)))[SR // 2:])
		out["dests"][d] = dict(level_cv=round(float(np.std(e) / np.mean(e)), 4), pitch_cents=round(float(np.std(1200 * np.log2(np.maximum(f[2000:-2000], 1) / 220.0))), 2),
			balance_db=round(float(np.std(20 * np.log10(bal + 1e-9))), 3), text=s.plugin.get_parameter_text(41))
		print("dest", d, out["dests"][d], flush=True)
	amp_dest = max(out["dests"], key=lambda d: out["dests"][d]["level_cv"] - (out["dests"][d]["pitch_cents"] > 5) * 9)
	out["amp_dest"] = amp_dest
	# Wave shapes at about 1 Hz, read as the level over two cycles.
	for t in range(6):
		s.load(lfo_patch(lfo1_type=t, lfo1_dest=amp_dest, lfo1_speed=48, lfo1_depth=127))
		e = envelope((lambda q: (q[0] + q[1]) * 0.5)(s.render([(69, 127, 0.0, 8.0)], 8.0)), 480)[SR // 10:]
		p = period(e, 0.05, 3.5)
		seg = e[: int((p or 1.0) * 2 * SR)]
		out["types"][t] = dict(period_s=p, text=s.plugin.get_parameter_text(42),
			shape=[round(float(seg[int(len(seg) * k / 40)] / np.max(seg)), 3) for k in range(40)])
		print("type", t, p, out["types"][t]["text"], flush=True)
	# Rate per speed value: a triangle on the level.
	for v in range(128):
		dur = 6.0 if v > 40 else 30.0
		s.load(lfo_patch(lfo1_dest=amp_dest, lfo1_speed=v, lfo1_type=1))
		e = envelope((lambda q: (q[0] + q[1]) * 0.5)(s.render([(81, 127, 0.0, dur)], dur)), 48)[SR // 20:]
		p = period(e, 0.002, dur / 2.2)
		out["rate_hz"][v] = None if not p else round(1.0 / p, 5)
		print("rate", v, out["rate_hz"][v], flush=True)
	# Depth per depth value: cents of pitch swing (osc pitch dest found above) and level swing.
	pitch_dest = max(out["dests"], key=lambda d: out["dests"][d]["pitch_cents"])
	out["pitch_dest"] = pitch_dest
	for v in range(0, 128, 4):
		s.load(lfo_patch(lfo1_dest=pitch_dest, lfo1_speed=40, lfo1_depth=v, lfo1_type=5))
		f = inst_freq((lambda q: (q[0] + q[1]) * 0.5)(s.render([(57, 127, 0.0, 3.0)], 3.0))[SR // 2:])
		c = 1200 * np.log2(np.maximum(f[2000:-2000], 1) / 220.0)
		s.load(lfo_patch(lfo1_dest=amp_dest, lfo1_speed=40, lfo1_depth=v, lfo1_type=5))
		e = envelope((lambda q: (q[0] + q[1]) * 0.5)(s.render([(69, 127, 0.0, 3.0)], 3.0))[SR // 2:], 480)
		out["depth"][v] = dict(pitch_cents_pp=round(float(np.percentile(c, 98) - np.percentile(c, 2)), 2),
			level_max_min_db=round(float(20 * np.log10(np.percentile(e, 98) / max(1e-9, np.percentile(e, 2)))), 2))
		print("depth", v, out["depth"][v], flush=True)
	# Destinations 3 and 5 against the filter (a saw through a low cutoff: level) and the
	# pulse width (a pulse through the open filter: the 2nd harmonic's swing).
	out["dest_check"] = {}
	for d in (3, 5):
		s.load(lfo_patch(lfo1_dest=d, lfo1_speed=40, lfo1_type=5, osc1_shape=1, f_freq=50))
		e = envelope((lambda q: (q[0] + q[1]) * 0.5)(s.render([(45, 127, 0.0, 4.0)], 4.0))[SR // 2:], 480)
		s.load(lfo_patch(lfo1_dest=d, lfo1_speed=40, lfo1_type=5, osc1_shape=2))
		x = (lambda q: (q[0] + q[1]) * 0.5)(s.render([(45, 127, 0.0, 4.0)], 4.0))[SR // 2:]
		h2 = []
		for k in range(0, len(x) - 9600, 4800):
			seg = x[k:k + 9600] * np.hanning(9600)
			S = np.abs(np.fft.rfft(seg))
			h2.append(float(S[int(round(220 * 9600 / SR))]))
		out["dest_check"][d] = dict(filter_level_cv=round(float(np.std(e) / np.mean(e)), 4), h2_cv=round(float(np.std(h2) / (np.mean(h2) + 1e-12)), 4))
		print("dest check", d, out["dest_check"][d], flush=True)
	OUT.mkdir(exist_ok=True)
	(OUT / "lfo.json").write_text(json.dumps(out, indent=1))


if __name__ == "__main__":
	run()
