# SPDX-License-Identifier: Apache-2.0
"""Synth1's filter: cutoff per panel value, each type's slope, resonance,
key tracking and envelope amount. Writes data/filter.json.

The source is osc2's noise alone; each response is the filtered noise's
power spectrum over the open filter's (Welch averages, 2 s)."""
import json
import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from synth1 import SR, Synth1, mono, neutral  # noqa: E402

OUT = pathlib.Path(__file__).parent / "data"
NFFT = 4096


def psd(x):
	w = np.hanning(NFFT)
	segs = [x[i:i + NFFT] * w for i in range(0, len(x) - NFFT, NFFT // 2)]
	return np.mean([np.abs(np.fft.rfft(s)) ** 2 for s in segs], axis=0)


FREQ = np.fft.rfftfreq(NFFT, 1 / SR)


def response(s, note=60, **over):
	"""dB per FREQ bin of the filter set by `over`, against the open low-pass."""
	base = dict(osc2_shape=4, osc_mix=127, a_gain=100)
	s.load(neutral(**base, filter_type=0, f_freq=127, f_res=0))
	ref = psd(mono(s.render([(note, 127, 0.0, 2.5)], 2.5))[SR // 4:])
	s.load(neutral(**dict(base, **over)))
	got = psd(mono(s.render([(note, 127, 0.0, 2.5)], 2.5))[SR // 4:])
	return 10 * np.log10((got + 1e-20) / (ref + 1e-20))


def smooth(db, k=9):
	return np.convolve(db, np.ones(k) / k, mode="same")


def cross(db, level, low_to_high=True):
	"""First frequency where the response falls below `level` dB (scanning up or down)."""
	idx = range(4, len(db) - 4) if low_to_high else range(len(db) - 5, 3, -1)
	for i in idx:
		if db[i] <= level:
			return float(FREQ[i])
	return None


def run():
	s = Synth1()
	out = {"types": {}, "cutoff_lp12": {}, "cutoff_lp24": {}, "resonance": {}, "key_track": {}, "env_amount": {}}
	# Each type at a mid cutoff: the response in 1/3 octaves, to name them.
	bands = [31.5 * 2 ** (k / 3) for k in range(29)]
	for t in range(6):
		db = smooth(response(s, filter_type=t, f_freq=64, f_res=0))
		out["types"][t] = [round(float(np.interp(b, FREQ, db)), 2) for b in bands]
	out["bands_hz"] = [round(b, 1) for b in bands]
	# Cutoff per value: the -3 dB point (LP12) and -3 dB (LP24), resonance 0.
	for v in range(128):
		db = smooth(response(s, filter_type=0, f_freq=v, f_res=0))
		out["cutoff_lp12"][v] = cross(db, -3.0)
		if v % 8 == 0 or v == 127:
			db = smooth(response(s, filter_type=1, f_freq=v, f_res=0))
			out["cutoff_lp24"][v] = cross(db, -3.0)
		print("cutoff", v, out["cutoff_lp12"][v], out["cutoff_lp24"].get(v), flush=True)
	# Resonance: peak gain and where, at cutoff value 64, LP12 and LP24.
	for v in range(0, 128, 4):
		r = {}
		for t in (0, 1):
			db = smooth(response(s, filter_type=t, f_freq=64, f_res=v), 5)
			i = int(np.argmax(db[4:])) + 4
			r[t] = [round(float(db[i]), 2), round(float(FREQ[i]), 1)]
		out["resonance"][v] = r
		print("res", v, r, flush=True)
	# Key tracking: the cutoff at notes 48 and 72 per track value (cutoff 64).
	for v in range(0, 128, 8):
		c = [cross(smooth(response(s, note=n, filter_type=0, f_freq=64, f_res=0, f_track=v)), -3.0) for n in (48, 72)]
		out["key_track"][v] = c
		print("track", v, c, flush=True)
	# Envelope amount: sustain 127, attack 0, cutoff 40; the cutoff per amount value.
	for v in range(0, 128, 8):
		db = smooth(response(s, filter_type=0, f_freq=40, f_res=0, f_amount=v, f_attack=0, f_decay=0, f_sustain=127))
		out["env_amount"][v] = cross(db, -3.0)
		print("amount", v, out["env_amount"][v], flush=True)
	OUT.mkdir(exist_ok=True)
	(OUT / "filter.json").write_text(json.dumps(out, indent=1))


if __name__ == "__main__":
	run()
