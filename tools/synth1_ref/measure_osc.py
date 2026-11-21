# SPDX-License-Identifier: Apache-2.0
"""Synth1's oscillators, mix, FM, detune, sub, unison, gain, velocity and
portamento per panel value. Writes data/osc.json."""
import json
import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from synth1 import SR, Synth1, mono, neutral  # noqa: E402
from measure_env import envelope  # noqa: E402
from measure_lfo import inst_freq  # noqa: E402

OUT = pathlib.Path(__file__).parent / "data"


def spectrum(x):
	w = np.hanning(len(x))
	return np.abs(np.fft.rfft(x * w)) * 4.0 / len(x), np.fft.rfftfreq(len(x), 1 / SR)


def peak_hz(x, lo=20.0, hi=20000.0):
	"""The strongest partial's frequency, parabolically interpolated."""
	S, f = spectrum(x)
	a, b = np.searchsorted(f, lo), np.searchsorted(f, hi)
	k = a + int(np.argmax(S[a:b]))
	y0, y1, y2 = np.log(S[k - 1] + 1e-20), np.log(S[k] + 1e-20), np.log(S[k + 1] + 1e-20)
	d = 0.5 * (y0 - y2) / (y0 - 2 * y1 + y2)
	return float(f[k] + d * (f[1] - f[0]))


def level_at(x, hz, width=3):
	S, f = spectrum(x)
	k = int(round(hz / (f[1] - f[0])))
	return float(np.max(S[max(0, k - width):k + width + 1]))


def rms(x):
	return float(np.sqrt(np.mean(x ** 2)))


def held(s, note=57, dur=2.0, vel=127, **v):
	s.load(neutral(**v))
	return mono(s.render([(note, vel, 0.0, dur)], dur))[SR // 2:]


def osc2_pitch_table(s):
	"""Semitones per osc2 pitch value (osc2 triangle alone). Low values are read at a high
	note and high values at a low one, so every partial stays between 20 Hz and Nyquist."""
	t = []
	for v in range(128):
		note = 93 if v < 64 else 33
		x = held(s, note=note, osc2_shape=3, osc_mix=127, osc2_pitch=v, osc2_fine=64, dur=3.0)
		t.append(int(round(12 * np.log2(peak_hz(x, hi=23000.0) / (440.0 * 2 ** ((note - 69) / 12))))))
	return t


def run():
	s = Synth1()
	out = {}
	# osc2 shapes (alone): harmonic levels in dB against the fundamental.
	out["osc2_shapes"] = {}
	for sh in range(1, 5):
		x = held(s, osc2_shape=sh, osc_mix=127)
		h = [level_at(x, 220.0 * k) for k in range(1, 8)]
		out["osc2_shapes"][sh] = dict(rms=round(rms(x), 4), harm_db=[round(20 * np.log10(max(v, 1e-9) / max(h[0], 1e-9)), 1) for v in h])
	print("osc2 shapes", out["osc2_shapes"], flush=True)
	out["osc1_shapes"] = {}
	for sh in range(4):
		x = held(s, osc1_shape=sh)
		h = [level_at(x, 220.0 * k) for k in range(1, 8)]
		out["osc1_shapes"][sh] = dict(rms=round(rms(x), 4), harm_db=[round(20 * np.log10(max(v, 1e-9) / max(h[0], 1e-9)), 1) for v in h])
	print("osc1 shapes", out["osc1_shapes"], flush=True)
	out["osc2_pitch_semitones"] = osc2_pitch_table(s)
	# osc2 fine (osc2 triangle alone, note 57 = 220 Hz): cents from the note.
	out["osc2_fine"] = {}
	for v in range(0, 128, 4):
		x = held(s, osc2_shape=3, osc_mix=127, osc2_pitch=64, osc2_fine=v, dur=4.0)
		out["osc2_fine"][v] = round(1200 * np.log2(peak_hz(x) / 220.0), 2)
	out["osc_tune"] = {}
	for v in range(0, 128, 8):
		x = held(s, osc1_shape=0, osc_tune=v, dur=4.0)
		out["osc_tune"][v] = round(1200 * np.log2(peak_hz(x) / 220.0), 2)
	print("pitch", out["osc2_pitch_semitones"][0], out["osc2_pitch_semitones"][127], "fine", out["osc2_fine"].get(0), out["osc2_fine"].get(124), flush=True)
	# Fixed osc2 (track off): its frequency per pitch value at two notes.
	out["osc2_untracked"] = {v: [round(peak_hz(held(s, note=n, osc2_shape=3, osc_mix=127, osc2_track=0, osc2_pitch=v)), 2) for n in (45, 69)] for v in (40, 64, 88)}
	# Mix law: osc1 saw at the note, osc2 saw a fifth up; each one's fundamental level per mix value.
	out["mix"] = {}
	for v in range(0, 128, 4):
		x = held(s, osc1_shape=1, osc2_shape=1, osc2_pitch=71, osc_mix=v)
		f2 = 220.0 * 2 ** (7 / 12)
		out["mix"][v] = [round(20 * np.log10(max(level_at(x, 220.0), 1e-9)), 2), round(20 * np.log10(max(level_at(x, f2), 1e-9)), 2)]
	print("mix", out["mix"].get(0), out["mix"].get(64), out["mix"].get(124), flush=True)
	# FM (osc2 -> osc1): osc1 sine, osc2 a slow untracked triangle (about 33 Hz). Synth1's FM
	# moves the frequency, so the carrier sweeps a band; its upper edge (99.5 % of the energy)
	# less the carrier is the peak deviation in Hz, at two carrier notes (does it scale with the note?).
	out["fm_dev_hz"] = {}
	for v in range(0, 128, 4):
		row = []
		for note in (45, 57):
			s.load(neutral(osc1_shape=0, osc2_shape=3, osc2_track=0, osc2_pitch=16, osc_mix=0, osc1_fm=v))
			x = mono(s.render([(note, 127, 0.0, 3.0)], 3.0))[SR // 2:]
			S, f = spectrum(x)
			c = np.cumsum(S ** 2)
			edge = float(f[np.searchsorted(c, 0.995 * c[-1])])
			fc = 440.0 * 2 ** ((note - 69) / 12)
			row.append(round(edge - fc, 1))
		out["fm_dev_hz"][v] = row
	print("fm", out["fm_dev_hz"].get(32), out["fm_dev_hz"].get(64), out["fm_dev_hz"].get(124), flush=True)
	# Pulse width: osc1 shape 3, the share of each cycle above zero.
	out["pulse_width"] = {}
	for v in range(0, 128, 4):
		s.load(neutral(osc1_shape=2, pulse_width=v))
		x = mono(s.render([(45, 127, 0.0, 1.0)], 1.0))[SR // 4:]
		out["pulse_width"][v] = round(float(np.mean(x > 0)), 4)
	# osc1 detune (its 8x stack): sine at 440 Hz, the spread of the partials (cents, outermost)
	# and how many there are.
	out["osc1_detune"] = {}
	for v in (1, 2, 4, 8, 16, 24, 32, 48, 64, 80, 96, 112, 127):
		x = held(s, note=69, dur=6.0, osc1_shape=0, osc1_detune=v)
		S, f = spectrum(x)
		a, b = np.searchsorted(f, 300), np.searchsorted(f, 650)
		seg = S[a:b]
		thr = 0.08 * seg.max()
		pk = [a + i for i in range(1, len(seg) - 1) if seg[i] > thr and seg[i] >= seg[i - 1] and seg[i] >= seg[i + 1]]
		cents = [1200 * np.log2(f[k] / 440.0) for k in pk]
		out["osc1_detune"][v] = dict(n=len(pk), lo=round(min(cents), 1) if cents else None, hi=round(max(cents), 1) if cents else None,
			rms=round(rms(x), 4))
	print("detune", out["osc1_detune"], flush=True)
	# Sub oscillator: its level against osc1 (sine osc1), per gain, shape and octave.
	out["sub"] = {}
	for sh in range(4):
		for octv in (0, 1):
			for g in (32, 64, 96, 127):
				x = held(s, osc1_shape=0, sub_gain=g, sub_shape=sh, sub_octave=octv)
				out["sub"][f"{sh}/{octv}/{g}"] = dict(f110=round(20 * np.log10(max(level_at(x, 110.0), 1e-9)), 2),
					f220=round(20 * np.log10(max(level_at(x, 220.0), 1e-9)), 2), f330=round(20 * np.log10(max(level_at(x, 330.0), 1e-9)), 2))
	print("sub done", flush=True)
	# Unison detune: 8 voices of a sine, the partials' spread per value; and the level per voice count.
	out["unison_detune"] = {}
	for v in (1, 4, 8, 16, 32, 64, 96, 127):
		x = held(s, note=69, dur=6.0, osc1_shape=0, unison_on=1, unison_voices=8, unison_detune=v, unison_spread=64, unison_pitch=24)
		S, f = spectrum(x)
		a, b = np.searchsorted(f, 300), np.searchsorted(f, 650)
		seg = S[a:b]
		pk = [a + i for i in range(1, len(seg) - 1) if seg[i] > 0.08 * seg.max() and seg[i] >= seg[i - 1] and seg[i] >= seg[i + 1]]
		cents = [1200 * np.log2(f[k] / 440.0) for k in pk]
		out["unison_detune"][v] = dict(n=len(pk), lo=round(min(cents), 1) if cents else None, hi=round(max(cents), 1) if cents else None)
	out["unison_level"] = {}
	for n in range(2, 9):
		lv = [rms(held(s, osc1_shape=1, unison_on=1, unison_voices=n, unison_detune=40, unison_spread=64, unison_pitch=24, unison_phase=0)) for _ in range(3)]
		out["unison_level"][n] = round(20 * np.log10(np.mean(lv) / rms(held(s, osc1_shape=1))), 2)
	print("unison", out["unison_detune"], out["unison_level"], flush=True)
	# Gain and velocity: level (dB) per gain value; per velocity at three sensitivity values.
	ref = rms(held(s, osc1_shape=0, a_gain=127))
	out["gain_db"] = {v: round(20 * np.log10(max(rms(held(s, osc1_shape=0, a_gain=v)), 1e-9) / ref), 2) for v in range(0, 128, 4)}
	out["velocity_db"] = {}
	for sens in (0, 32, 64, 96, 127):
		out["velocity_db"][sens] = {vel: round(20 * np.log10(max(rms(held(s, vel=vel, osc1_shape=0, a_vel=sens)), 1e-9) / ref), 2) for vel in (1, 16, 32, 64, 96, 127)}
	print("gain", out["gain_db"].get(0), out["gain_db"].get(64), "vel", out["velocity_db"][127], flush=True)
	# Portamento: mono, a jump of an octave; the time to cover 50 % and 90 % of it, in cents.
	out["portamento"] = {}
	for v in (0, 8, 16, 32, 48, 64, 80, 96, 112, 127):
		s.load(neutral(osc1_shape=0, play_mode=1, porta_time=v, porta_auto=0))
		a = s.render([(57, 127, 0.0, 1.0), (69, 127, 1.0, 6.0)], 7.0)
		f = inst_freq(mono(a))
		c = 1200 * np.log2(np.maximum(f, 1) / 220.0)
		i0 = SR
		t50 = next((i for i in range(i0, len(c)) if c[i] >= 600), None)
		t90 = next((i for i in range(i0, len(c)) if c[i] >= 1080), None)
		out["portamento"][v] = [None if t50 is None else round((t50 - i0) / SR, 4), None if t90 is None else round((t90 - i0) / SR, 4)]
	print("porta", out["portamento"], flush=True)
	OUT.mkdir(exist_ok=True)
	(OUT / "osc.json").write_text(json.dumps(out, indent=1))


if __name__ == "__main__":
	run()
