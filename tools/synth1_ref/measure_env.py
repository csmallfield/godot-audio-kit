# SPDX-License-Identifier: Apache-2.0
"""Synth1's amp envelope per panel value: attack, decay, sustain, release.

Writes data/amp_env.json. A 440 Hz sine (osc1 shape 0) through the open
filter; the level is the sine's analytic envelope. Times are from the event
(note on, or note off for the release) to the level crossing each mark."""
import json
import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from synth1 import SR, Synth1, mono, neutral  # noqa: E402

OUT = pathlib.Path(__file__).parent / "data"


def envelope(x, smooth=96):
	"""The level of a sine-like signal: |analytic signal|, smoothed over `smooth` samples."""
	n = len(x)
	X = np.fft.fft(x)
	h = np.zeros(n)
	h[0] = 1
	h[1:(n + 1) // 2] = 2
	if n % 2 == 0:
		h[n // 2] = 1
	e = np.abs(np.fft.ifft(X * h))
	k = np.ones(smooth) / smooth
	return np.convolve(e, k, mode="same")


def first_cross(e, start, level, rising):
	idx = np.nonzero(e[start:] >= level)[0] if rising else np.nonzero(e[start:] <= level)[0]
	return float((start + idx[0]) / SR) if len(idx) else None


def run(values=range(128)):
	s = Synth1()
	out = {"note": 69, "attack": {}, "decay": {}, "sustain": {}, "release": {}}
	# Reference level: sustain 127, no envelope movement.
	s.load(neutral(osc1_shape=0))
	ref = float(np.median(envelope(mono(s.render([(69, 127, 0.0, 1.0)], 1.0)))[12000:36000]))
	out["ref_level"] = ref
	for v in values:
		# Attack: time to 10/50/90/99 % of the held level, and the shape (level at 20 shares of t99).
		dur = 2.0 + v * 0.45
		s.load(neutral(osc1_shape=0, a_attack=v))
		e = envelope(mono(s.render([(69, 127, 0.0, dur)], dur)))
		peak = float(np.max(e))
		t = {f"t{int(m * 100)}": first_cross(e, 0, m * peak, True) for m in (0.1, 0.5, 0.9, 0.99)}
		shape = []
		if t["t99"]:
			n99 = int(t["t99"] * SR)
			shape = [round(float(e[int(n99 * k / 20)] / peak), 4) for k in range(21)]
		out["attack"][v] = dict(t, shape=shape)
		# Decay to sustain 0: times to -6/-20/-40/-60 dB.
		s.load(neutral(osc1_shape=0, a_decay=v, a_sustain=0))
		dur = 2.0 + v * 0.55
		e = envelope(mono(s.render([(69, 127, 0.0, dur)], dur)))
		pk = float(np.max(e))
		i0 = int(np.argmax(e))
		out["decay"][v] = {f"db{d}": first_cross(e, i0, pk * 10 ** (-d / 20), False) for d in (6, 20, 40, 60)}
		# Sustain level (decay short).
		s.load(neutral(osc1_shape=0, a_decay=0, a_sustain=v))
		e = envelope(mono(s.render([(69, 127, 0.0, 1.0)], 1.0)))
		out["sustain"][v] = round(20 * np.log10(max(1e-9, float(np.median(e[24000:42000]))) / ref), 3)
		# Release from full sustain, note off at 0.3 s.
		s.load(neutral(osc1_shape=0, a_release=v))
		dur = 1.0 + v * 0.55
		e = envelope(mono(s.render([(69, 127, 0.0, 0.3)], dur)))
		off = int(0.3 * SR)
		lv = float(np.median(e[off - 4800:off - 200]))
		out["release"][v] = {f"db{d}": (lambda c: None if c is None else round(c - 0.3, 5))(first_cross(e, off, lv * 10 ** (-d / 20), False)) for d in (6, 20, 40, 60)}
		print(v, out["attack"][v]["t90"], out["decay"][v]["db20"], out["sustain"][v], out["release"][v]["db20"], flush=True)
	OUT.mkdir(exist_ok=True)
	(OUT / "amp_env.json").write_text(json.dumps(out, indent=1))


if __name__ == "__main__":
	vals = range(128) if len(sys.argv) < 2 else [int(a) for a in sys.argv[1:]]
	run(vals)
