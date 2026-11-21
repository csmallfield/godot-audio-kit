# SPDX-License-Identifier: Apache-2.0
"""Synth1's effects and mod envelope: the display text per value, the tempo
delay (times, types, spread, feedback, mix, tone), the chorus/flanger (taps,
time, depth, rate, feedback, level per type), the equalizer, the ten effect
types and what their two controls do, and the mod envelope (its times, and its
amount on FM and pulse width as an equivalent knob value). Each part writes
data/fx_<part>.json; name parts to run only those (python measure_fx.py delay eq).

Synth1's display text (the texts part) is right for the chorus time, rate and
feedback, the delay spread and mix, and the EQ frequency and level, but not for
the delay time: its text doesn't follow the stored value, so use time_s."""
import json
import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from synth1 import P, SR, Synth1, mono, neutral  # noqa: E402
from measure_env import envelope  # noqa: E402
from measure_filter import FREQ, psd  # noqa: E402
from measure_lfo import inst_freq, period  # noqa: E402

OUT = pathlib.Path(__file__).parent / "data"
BPM = 120.0

# A short click: a high saw with the shortest amp decay and no sustain (about 4 ms).
BLIP = dict(osc1_shape=1, a_attack=0, a_decay=0, a_sustain=0, a_release=0, a_gain=127)
FX_OFF = dict(delay_on=0, chorus_on=0, fx_on=0)


def db(x):
	return float(20 * np.log10(max(float(x), 1e-12)))


def bands_db(got, ref, bands):
	"""Per band (Hz edges a third of an octave around each centre), 10 log10 of got/ref power."""
	r = []
	for b in bands:
		a, c = np.searchsorted(FREQ, b * 2 ** (-1 / 6)), np.searchsorted(FREQ, b * 2 ** (1 / 6))
		c = max(c, a + 1)
		r.append(round(float(10 * np.log10((np.sum(got[a:c]) + 1e-20) / (np.sum(ref[a:c]) + 1e-20))), 2))
	return r


BANDS = [31.5 * 2 ** (k / 3) for k in range(29)]


def texts(s):
	"""What Synth1 displays for each value of the effect parameters."""
	ranges = dict(delay_time=41, delay_type=3, delay_spread=128, delay_tone=128, delay_fb=128, delay_mix=128,
		ch_type=5, ch_delay=128, ch_depth=128, ch_rate=128, ch_fb=128, ch_level=128,
		eq_freq=128, eq_level=128, eq_q=128, eq_tone=128, fx_type=10, fx_ctl1=128, fx_ctl2=128, fx_mix=128,
		modenv_dest=3, modenv_amount=128, modenv_attack=128, modenv_decay=128)
	out = {}
	for n, k in ranges.items():
		out[n] = {}
		for v in range(k):
			s.load(neutral(**{n: v}))
			out[n][v] = s.text(n)
		print("text", n, out[n].get(0), out[n].get(k // 2), out[n].get(k - 1), flush=True)
	return out


def dry_blip(s, note=81):
	s.load(neutral(**BLIP, **FX_OFF))
	a = s.render([(note, 127, 0.1, 0.01)], 0.4)
	return a


def peaks(env, lo, hi, thr):
	"""Local maxima of env in [lo, hi) above thr, as (index, value), strongest first."""
	seg = env[lo:hi]
	idx = [i for i in range(1, len(seg) - 1) if seg[i] > thr and seg[i] >= seg[i - 1] and seg[i] > seg[i + 1]]
	return sorted(((lo + i, float(seg[i])) for i in idx), key=lambda p: -p[1])


def delay(s):
	out = {"time_s": {}, "time_60bpm_s": {}, "types": {}, "fb_ratio_db": {}, "mix_db": {}, "tone_db": {}, "spread_s": {}}
	d = dry_blip(s)
	dpk = int(np.argmax(np.abs(mono(d))))
	base = dict(neutral(**BLIP), delay_on=1, delay_type=0, delay_fb=0, delay_mix=127, delay_spread=64, delay_tone=64)

	def echo_times(over, bpm=BPM, seconds=4.5, n=1, chan=None):
		s.engine.set_bpm(bpm)
		s.load(dict(base, **over))
		a = s.render([(81, 127, 0.1, 0.01)], seconds)
		x = mono(a) if chan is None else a[chan]
		e = envelope(x, 24)
		pk = peaks(e, dpk + 48, len(e) - 10, 0.05 * float(np.max(e)))
		pk = sorted(pk[:n], key=lambda p: p[0])
		return [round((i - dpk) / SR, 4) for i, _ in pk], [round(db(v), 2) for _, v in pk], a

	for v in range(1, 41):
		t, _, _ = echo_times(dict(delay_time=v))
		out["time_s"][v] = t[0] if t else None
		if v % 4 == 0:
			t2, _, _ = echo_times(dict(delay_time=v), bpm=60.0, seconds=7.0)
			out["time_60bpm_s"][v] = t2[0] if t2 else None
		print("delay time", v, out["time_s"][v], out["time_60bpm_s"].get(v), flush=True)
	s.engine.set_bpm(BPM)
	# Types: the source panned hard left, feedback 90; the first echoes on each side.
	for ty in range(3):
		row = {}
		for ch, name in ((0, "L"), (1, "R")):
			t, lv, _ = echo_times(dict(delay_time=8, delay_type=ty, delay_fb=90, pan=0), n=6, chan=ch, seconds=3.0)
			row[name] = dict(t=t, db=lv)
		out["types"][ty] = row
		print("delay type", ty, row, flush=True)
	# Spread: each side's first echo (type 0, centred source).
	for v in (0, 16, 32, 48, 64, 80, 96, 112, 127):
		tl, _, _ = echo_times(dict(delay_time=8, delay_spread=v), chan=0, seconds=2.0)
		tr, _, _ = echo_times(dict(delay_time=8, delay_spread=v), chan=1, seconds=2.0)
		out["spread_s"][v] = [tl[0] if tl else None, tr[0] if tr else None]
	print("spread", out["spread_s"], flush=True)
	# Feedback and mix, by energy in windows: the dry click (around its peak) and echo k (k quarter
	# seconds later at 120 bpm, value 8), against the dry click with the delay off.
	def win_db(x, centre):
		i = dpk + int(round(centre * SR))
		return db(np.sqrt(np.sum(x[i - 240:i + 960] ** 2)))

	ref = win_db(mono(d), 0.0)
	for v in range(0, 128, 8):
		s.load(dict(base, delay_time=8, delay_fb=v, delay_mix=127))
		x = mono(s.render([(81, 127, 0.1, 0.01)], 1.2))
		e1, e2 = win_db(x, 0.25), win_db(x, 0.5)
		out["fb_ratio_db"][v] = round(e2 - e1, 2)
	print("fb", out["fb_ratio_db"], flush=True)
	for v in range(0, 128, 8):
		s.load(dict(base, delay_time=8, delay_mix=v))
		x = mono(s.render([(81, 127, 0.1, 0.01)], 0.6))
		out["mix_db"][v] = [round(win_db(x, 0.0) - ref, 2), round(win_db(x, 0.25) - ref, 2)]
	print("mix", out["mix_db"], flush=True)
	# Values 0 and 1: every echo peak in the first 0.3 s.
	out["short"] = {}
	for v in (0, 1, 2):
		s.load(dict(base, delay_time=v, delay_fb=60, delay_mix=64))
		x = mono(s.render([(81, 127, 0.1, 0.01)], 0.6))
		e = envelope(x, 12)
		out["short"][v] = [round((i - dpk) / SR, 4) for i, _ in sorted(peaks(e, dpk - 200, dpk + int(0.3 * SR), 0.08 * float(np.max(e)))[:8])]
	print("short", out["short"], flush=True)
	# Tone: a burst of noise; the echo's spectrum over the dry burst's, per tone value.
	for v in (0, 16, 32, 48, 64, 80, 96, 112, 127):
		s.load(dict(neutral(osc2_shape=4, osc_mix=127, a_gain=100), delay_on=1, delay_type=0, delay_fb=0, delay_mix=64,
			delay_spread=64, delay_time=12, delay_tone=v))
		a = mono(s.render([(60, 127, 0.0, 0.4)], 1.4))
		dry, wet = a[int(0.05 * SR):int(0.4 * SR)], a[int(0.6 * SR):int(0.9 * SR)]
		out["tone_db"][v] = bands_db(psd(wet), psd(dry), BANDS)
	out["bands_hz"] = [round(b, 1) for b in BANDS]
	print("tone", {k: (v[6], v[15], v[24]) for k, v in out["tone_db"].items()}, flush=True)
	return out


def chorus(s):
	"""Blips every `gap` s through the chorus; each blip's echoes (taps) per side, by cross-correlation
	with the dry blip, give the tap delays over time."""
	out = {"types": {}, "time_ms": {}, "depth_ms": {}, "rate_hz": {}, "fb_db": {}, "level_db": {}}
	d = dry_blip(s, 93)
	dk = int(np.argmax(np.abs(mono(d))))
	tmpl = mono(d)[dk - 96:dk + 192]

	def taps(over, gap=0.06, seconds=4.0, ntap=4):
		s.load(dict(neutral(**BLIP), chorus_on=1, **over))
		starts = np.arange(0.1, seconds - 0.1, gap)
		a = s.render([(93, 127, float(t0), 0.005) for t0 in starts], seconds)
		res = {0: [], 1: []}
		for ch in (0, 1):
			for t0 in starts:
				i0 = int(round(t0 * SR)) + (dk - int(0.1 * SR)) - 96
				seg = a[ch][i0:i0 + int(gap * SR)]
				if len(seg) < len(tmpl) + 10:
					continue
				c = np.abs(np.correlate(seg, tmpl, mode="valid"))
				pk = peaks(c, 0, len(c) - 1, 0.12 * float(np.max(c)))
				res[ch].append([(round(i / SR * 1000, 3), round(v / (np.max(c) + 1e-12), 3)) for i, v in pk[:ntap]])
		return res, starts

	def track(res, gap):
		"""The strongest non-zero-lag tap's delay per blip (ms), and its swing and rate."""
		out = {}
		for ch in (0, 1):
			series = []
			for row in res[ch]:
				nz = [t for t, _ in row if t > 0.25]
				series.append(nz[0] if nz else np.nan)
			sr = np.array(series)
			ok = ~np.isnan(sr)
			if ok.sum() < 8:
				out[ch] = None
				continue
			sr = np.interp(np.arange(len(sr)), np.flatnonzero(ok), sr[ok])
			ac = np.correlate(sr - sr.mean(), sr - sr.mean(), mode="full")[len(sr) - 1:]
			k = next((j for j in range(2, len(ac) - 1) if ac[j] > ac[j - 1] and ac[j] >= ac[j + 1] and ac[j] > 0.3 * ac[0]), None)
			out[ch] = dict(min_ms=round(float(np.percentile(sr, 3)), 3), max_ms=round(float(np.percentile(sr, 97)), 3),
				mean_ms=round(float(np.mean(sr)), 3), rate_hz=None if k is None else round(1.0 / (k * gap), 4))
		return out

	common = dict(ch_delay=64, ch_depth=64, ch_rate=50, ch_fb=64, ch_level=127)  # ch_fb is bipolar: 64 = none
	for ty in range(5):
		res, _ = taps(dict(common, ch_type=ty), seconds=6.0)
		out["types"][ty] = dict(first_blip={ch: res[ch][3] if len(res[ch]) > 3 else None for ch in (0, 1)}, track=track(res, 0.06))
		print("chorus type", ty, out["types"][ty], flush=True)
	for v in (0, 16, 32, 48, 64, 80, 96, 112, 127):
		res, _ = taps(dict(common, ch_type=2, ch_depth=0, ch_delay=v), seconds=1.5)
		out["time_ms"][v] = {ch: res[ch][3] if len(res[ch]) > 3 else None for ch in (0, 1)}
	print("chorus time", out["time_ms"], flush=True)
	for v in (0, 16, 32, 48, 64, 80, 96, 112, 127):
		res, _ = taps(dict(common, ch_type=2, ch_depth=v, ch_rate=64), seconds=6.0)
		out["depth_ms"][v] = track(res, 0.06)
	print("chorus depth", out["depth_ms"], flush=True)
	for v in (0, 16, 32, 48, 64, 80, 96, 112, 127):
		res, _ = taps(dict(common, ch_type=2, ch_delay=32, ch_depth=64, ch_rate=v), gap=0.035, seconds=12.0 if v < 40 else 5.0)
		out["rate_hz"][v] = track(res, 0.035)
	print("chorus rate", out["rate_hz"], flush=True)
	for v in (0, 32, 64, 96, 127):
		res, _ = taps(dict(common, ch_type=2, ch_depth=0, ch_fb=v), gap=0.12, seconds=1.5, ntap=6)
		out["fb_db"][v] = {ch: res[ch][3] if len(res[ch]) > 3 else None for ch in (0, 1)}
	print("chorus fb", out["fb_db"], flush=True)
	ref = float(np.max(np.abs(mono(d))))
	for v in range(0, 128, 16):
		s.load(dict(neutral(**BLIP), chorus_on=1, **dict(common, ch_type=2, ch_depth=0, ch_level=v)))
		a = mono(s.render([(93, 127, 0.1, 0.005)], 0.4))
		dry = float(np.max(np.abs(a[dk - 96:dk + 96])))
		wet = float(np.max(np.abs(a[dk + 300:dk + 3000])))
		out["level_db"][v] = [round(db(dry / ref), 2), round(db(wet / ref), 2)]
	print("chorus level", out["level_db"], flush=True)
	return out


def eq(s):
	"""The equalizer's response to steady noise, against the flat setting."""
	out = {"peak": {}, "q": {}, "level": {}, "tone": {}}
	base = dict(osc2_shape=4, osc_mix=127, a_gain=100)

	def resp(**over):
		s.load(neutral(**base, eq_tone=64, eq_freq=64, eq_level=64, eq_q=64))
		ref = psd(mono(s.render([(60, 127, 0.0, 2.5)], 2.5))[SR // 4:])
		s.load(neutral(**dict(base, **over)))
		got = psd(mono(s.render([(60, 127, 0.0, 2.5)], 2.5))[SR // 4:])
		return np.convolve(10 * np.log10((got + 1e-20) / (ref + 1e-20)), np.ones(7) / 7, mode="same")

	for v in range(0, 128, 8):
		r = resp(eq_freq=v, eq_level=127, eq_q=64)
		i = int(np.argmax(r[3:-3])) + 3
		out["peak"][v] = [round(float(FREQ[i]), 1), round(float(r[i]), 2)]
	print("eq freq", out["peak"], flush=True)
	for v in range(0, 128, 16):
		r = resp(eq_freq=64, eq_level=v, eq_q=64)
		i = int(np.argmax(np.abs(r[3:-3]))) + 3
		out["level"][v] = [round(float(FREQ[i]), 1), round(float(r[i]), 2)]
	for v in range(0, 128, 16):
		r = resp(eq_freq=64, eq_level=127, eq_q=v)
		i = int(np.argmax(r[3:-3])) + 3
		half = r[i] - 3.0
		lo = next((j for j in range(i, 2, -1) if r[j] < half), 3)
		hi = next((j for j in range(i, len(r) - 3) if r[j] < half), len(r) - 4)
		out["q"][v] = dict(peak_db=round(float(r[i]), 2), bw_oct=round(float(np.log2(FREQ[hi] / max(FREQ[lo], 1))), 3))
	print("eq level", out["level"], "q", out["q"], flush=True)
	for v in range(0, 128, 8):
		r = resp(eq_tone=v)
		out["tone"][v] = [round(float(np.interp(b, FREQ, r)), 2) for b in BANDS]
	out["bands_hz"] = [round(b, 1) for b in BANDS]
	print("eq tone done", flush=True)
	return out


def effects(s):
	"""Each of the ten effect types at ctl1/ctl2 = 0, 64, 127 (mix 127): what it does to a sine
	(harmonics, inharmonic energy, level and its movement, the stereo difference) and to noise
	(spectral shape and its movement)."""
	out = {}
	for ty in range(10):
		out[ty] = {}
		for c1 in (0, 64, 127):
			for c2 in (0, 64, 127):
				fx = dict(fx_on=1, fx_type=ty, fx_ctl1=c1, fx_ctl2=c2, fx_mix=127)
				s.load(neutral(osc1_shape=0, a_gain=100, **fx))
				a = s.render([(57, 127, 0.0, 3.0)], 3.0)[:, SR // 2:]
				x = mono(a)
				S = np.abs(np.fft.rfft(x * np.hanning(len(x))))
				f = np.fft.rfftfreq(len(x), 1 / SR)
				tot = float(np.sum(S ** 2))
				harm = []
				hmask = np.zeros(len(S), bool)
				for k in range(1, 9):
					j = int(round(220.0 * k / (f[1] - f[0])))
					w = slice(max(0, j - 4), j + 5)
					hmask[w] = True
					harm.append(round(db(np.sqrt(np.sum(S[w] ** 2) / tot)), 1))
				inh = round(db(np.sqrt(np.sum(S[~hmask] ** 2) / tot)), 1)
				e = envelope(x, 480)
				side = float(np.sqrt(np.mean((a[0] - a[1]) ** 2)) / (np.sqrt(np.mean(x ** 2)) + 1e-12))
				s.load(neutral(osc2_shape=4, osc_mix=127, a_gain=100, **fx))
				n = mono(s.render([(57, 127, 0.0, 3.0)], 3.0))[SR // 2:]
				s.load(neutral(osc2_shape=4, osc_mix=127, a_gain=100))
				n0 = mono(s.render([(57, 127, 0.0, 3.0)], 3.0))[SR // 2:]
				cent = []
				for k in range(0, len(n) - 4096, 2048):
					P_ = np.abs(np.fft.rfft(n[k:k + 4096] * np.hanning(4096))) ** 2
					cent.append(float(np.sum(P_ * FREQ) / (np.sum(P_) + 1e-20)))
				out[ty][f"{c1}/{c2}"] = dict(sine_rms_db=round(db(np.sqrt(np.mean(x ** 2))), 2), harm_db=harm, inharm_db=inh,
					level_cv=round(float(np.std(e) / (np.mean(e) + 1e-12)), 4), side=round(side, 3),
					noise_db=bands_db(psd(n), psd(n0), BANDS[::3]), centroid_hz=round(float(np.mean(cent)), 0),
					centroid_cv=round(float(np.std(cent) / (np.mean(cent) + 1e-12)), 4))
			print("fx", ty, c1, out[ty][f"{c1}/127"], flush=True)
	return {"types": out, "noise_bands_hz": [round(b, 1) for b in BANDS[::3]]}


def modenv(s):
	"""The mod envelope: per destination what moves; osc2 pitch offset per amount; attack and decay times."""
	out = {"dests": {}, "amount_semitones": {}, "decay_s": {}, "attack_s": {}}
	base = dict(osc2_shape=3, osc_mix=127, modenv_on=1, modenv_dest=0, modenv_amount=127, modenv_attack=0, modenv_decay=64)

	def pitch(over, dur=3.0):
		s.load(neutral(**dict(base, **over)))
		f = inst_freq(mono(s.render([(57, 127, 0.1, dur)], dur + 0.2)))
		return 12 * np.log2(np.maximum(f, 1) / 220.0)

	def early_late(over, measure):
		s.load(neutral(**dict(base, modenv_decay=80, **over)))
		a = mono(s.render([(57, 127, 0.1, 2.0)], 2.2))
		return round(measure(a[int(0.11 * SR):int(0.11 * SR) + 2400]), 3), round(measure(a[int(1.8 * SR):int(1.8 * SR) + 2400]), 3)

	def width(x):
		S = np.abs(np.fft.rfft(x * np.hanning(len(x)))) ** 2
		f = np.fft.rfftfreq(len(x), 1 / SR)
		return float(np.sqrt(np.sum(S * (f - 220.0) ** 2) / np.sum(S)))

	def h2(x):
		S = np.abs(np.fft.rfft(x * np.hanning(len(x))))
		return db(S[int(round(440 * len(x) / SR))] / (S[int(round(220 * len(x) / SR))] + 1e-12))

	for d in range(3):
		c = pitch(dict(modenv_dest=d, modenv_decay=80))
		out["dests"][d] = dict(osc2_pitch_start=round(float(np.median(c[int(0.11 * SR):int(0.13 * SR)])), 2),
			fm_width_hz=early_late(dict(modenv_dest=d, osc1_shape=0, osc_mix=0, osc1_fm=0), width),
			pulse_h2_db=early_late(dict(modenv_dest=d, osc1_shape=2, osc_mix=0, pulse_width=127), h2))
	print("modenv dests", out["dests"], flush=True)
	for v in range(0, 128, 8):
		c = pitch(dict(modenv_amount=v, modenv_decay=127), dur=1.0)
		out["amount_semitones"][v] = round(float(np.median(c[int(0.12 * SR):int(0.15 * SR)])), 2)
	print("modenv amount", out["amount_semitones"], flush=True)
	for v in (0, 16, 32, 48, 64, 80, 96, 112, 127):
		dur = 3.0 if v < 90 else 12.0
		c = pitch(dict(modenv_amount=96, modenv_decay=v), dur=dur)
		i0 = int(0.1 * SR) + 600
		c0 = float(np.median(c[i0:i0 + 240]))
		t50 = next((i for i in range(i0, len(c)) if c[i] < c0 * 0.5), None)
		t10 = next((i for i in range(i0, len(c)) if c[i] < c0 * 0.1), None)
		out["decay_s"][v] = [None if t50 is None else round((t50 - int(0.1 * SR)) / SR, 4), None if t10 is None else round((t10 - int(0.1 * SR)) / SR, 4), round(c0, 2)]
	print("modenv decay", out["decay_s"], flush=True)
	for v in (0, 16, 32, 48, 64, 80, 96, 112, 127):
		dur = 3.0 if v < 90 else 12.0
		c = pitch(dict(modenv_amount=96, modenv_attack=v, modenv_decay=127), dur=dur)
		i0 = int(0.1 * SR)
		top = float(np.max(c[i0:]))
		t50 = next((i for i in range(i0, len(c)) if c[i] > top * 0.5), None)
		t90 = next((i for i in range(i0, len(c)) if c[i] > top * 0.9), None)
		out["attack_s"][v] = [None if t50 is None else round((t50 - i0) / SR, 4), None if t90 is None else round((t90 - i0) / SR, 4), round(top, 2)]
	print("modenv attack", out["attack_s"], flush=True)
	return out


def effect_controls(s):
	"""What ctl1 and ctl2 do, per type (the manual names them: 0 a.d.1, 1 a.d.2, 2 d.d., 3 deci.,
	4 r.m., 5 comp., then the phasers): distortion THD per ctl1 and the tone's -3 dB point per ctl2;
	the decimator's sample rate per ctl1 (the image of a 1 kHz sine); the ring modulator's frequency
	per ctl1; the compressor's gain change; each phaser's static notches and sweep rate."""
	out = {"dist": {}, "tone_hz": {}, "deci_rate_hz": {}, "deci_bits_snr_db": {}, "ring_hz": {}, "comp": {}, "phaser": {}}

	def sine(fx, hz_note=57, dur=2.0, **over):
		s.load(neutral(**dict(dict(osc1_shape=0, a_gain=100), **over, fx_on=1, fx_mix=127, **fx)))
		return mono(s.render([(hz_note, 127, 0.0, dur)], dur))[SR // 2:]

	def spec(x):
		S = np.abs(np.fft.rfft(x * np.hanning(len(x))))
		return S, np.fft.rfftfreq(len(x), 1 / SR)

	for ty in (0, 1, 2):
		out["dist"][ty] = {}
		for c1 in range(0, 128, 16):
			S, f = spec(sine(dict(fx_type=ty, fx_ctl1=c1, fx_ctl2=127)))
			h = [float(np.max(S[int(220 * k / f[1]) - 3:int(220 * k / f[1]) + 4])) for k in range(1, 10)]
			out["dist"][ty][c1] = dict(thd_db=round(db(np.sqrt(sum(v * v for v in h[1:])) / h[0]), 2), h1_db=round(db(h[0] / (len(S))), 2))
		out["tone_hz"][ty] = {}
		for c2 in range(0, 128, 16):
			s.load(neutral(osc2_shape=4, osc_mix=127, a_gain=60))
			ref = psd(mono(s.render([(60, 127, 0.0, 2.0)], 2.0))[SR // 4:])
			s.load(neutral(osc2_shape=4, osc_mix=127, a_gain=60, fx_on=1, fx_mix=127, fx_type=ty, fx_ctl1=0, fx_ctl2=c2))
			got = psd(mono(s.render([(60, 127, 0.0, 2.0)], 2.0))[SR // 4:])
			r = np.convolve(10 * np.log10((got + 1e-20) / (ref + 1e-20)), np.ones(9) / 9, mode="same")
			top = float(np.max(r[20:400]))
			j = next((i for i in range(int(np.argmax(r[20:400])) + 20, len(r) - 5) if r[i] < top - 3.0), None)
			out["tone_hz"][ty][c2] = None if j is None else round(float(FREQ[j]), 1)
		print("dist", ty, out["dist"][ty], out["tone_hz"][ty], flush=True)
	for c1 in range(0, 128, 8):
		S, f = spec(sine(dict(fx_type=3, fx_ctl1=c1, fx_ctl2=127), hz_note=83))
		k0 = int(round(987.77 / f[1]))
		m = S.copy()
		m[k0 - 6:k0 + 7] = 0
		j = int(np.argmax(m[50:]) + 50)
		out["deci_rate_hz"][c1] = round(float(f[j]), 1)
	for c2 in range(0, 128, 16):
		S, f = spec(sine(dict(fx_type=3, fx_ctl1=127, fx_ctl2=c2), hz_note=83))
		k0 = int(round(987.77 / f[1]))
		sig = float(np.sum(S[k0 - 6:k0 + 7] ** 2))
		out["deci_bits_snr_db"][c2] = round(float(10 * np.log10(sig / (np.sum(S ** 2) - sig + 1e-20))), 2)
	print("deci", out["deci_rate_hz"], out["deci_bits_snr_db"], flush=True)
	for c1 in range(0, 128, 8):
		S, f = spec(sine(dict(fx_type=4, fx_ctl1=c1, fx_ctl2=64), dur=4.0))
		pk = sorted(range(2, len(S) - 1), key=lambda i: -S[i])[:1]
		out["ring_hz"][c1] = round(abs(float(f[pk[0]]) - 220.0), 2)
	print("ring", out["ring_hz"], flush=True)
	for c1 in (0, 32, 64, 96, 127):
		for c2 in (0, 64, 127):
			# A loud and a quiet note: output level each, against the effect off.
			row = []
			for g in (127, 40):
				x = sine(dict(fx_type=5, fx_ctl1=c1, fx_ctl2=c2), a_gain=g)
				s.load(neutral(osc1_shape=0, a_gain=g))
				x0 = mono(s.render([(57, 127, 0.0, 2.0)], 2.0))[SR // 2:]
				row.append(round(db(np.sqrt(np.mean(x ** 2)) / np.sqrt(np.mean(x0 ** 2))), 2))
			out["comp"][f"{c1}/{c2}"] = row
	print("comp", out["comp"], flush=True)
	for ty in (6, 7, 8, 9):
		row = {}
		s.load(neutral(osc2_shape=4, osc_mix=127, a_gain=60))
		ref = psd(mono(s.render([(60, 127, 0.0, 3.0)], 3.0))[SR // 4:])
		for c1 in (0, 64, 127):
			s.load(neutral(osc2_shape=4, osc_mix=127, a_gain=60, fx_on=1, fx_mix=127, fx_type=ty, fx_ctl1=c1, fx_ctl2=0))
			r = 10 * np.log10((psd(mono(s.render([(60, 127, 0.0, 3.0)], 3.0))[SR // 4:]) + 1e-20) / (ref + 1e-20))
			r = np.convolve(r, np.ones(5) / 5, mode="same")
			notches = [round(float(FREQ[i]), 0) for i in range(3, len(r) - 3) if r[i] < -6 and r[i] == min(r[i - 3:i + 4])]
			row[f"static_{c1}"] = notches[:12]
		for c2 in (0, 32, 64, 96, 127):
			x = sine(dict(fx_type=ty, fx_ctl1=127, fx_ctl2=c2), hz_note=81, dur=12.0)
			e = envelope(x, 480)
			# period() counts samples at SR; the envelope is decimated by 48, so scale both ways.
			p_ = period(e[::48], 0.01 / 48, len(e) / SR / 2.2 / 48)
			row[f"rate_{c2}"] = None if not p_ else round(1.0 / (p_ * 48), 4)
		out["phaser"][ty] = row
		print("phaser", ty, row, flush=True)
	return out


def modenv_amount(s):
	"""How far the mod envelope moves FM and pulse width per amount, read as the knob value that
	gives the same sound: each is measured over the same early window (the envelope at its peak:
	attack 0, the longest decay) for the knob alone and for the envelope added to a knob setting."""
	out = {"fm_knob_edge_hz": {}, "fm": {}, "pw_knob_duty": {}, "pw": {}}
	w0, w1 = int(0.15 * SR), int(0.45 * SR)

	def fm_edge(**over):
		s.load(neutral(**dict(dict(osc1_shape=0, osc2_shape=3, osc2_track=0, osc2_pitch=16, osc_mix=0, osc1_fm=0), **over)))
		x = mono(s.render([(57, 127, 0.1, 1.0)], 1.0))[w0:w1]
		S = np.abs(np.fft.rfft(x * np.hanning(len(x)))) ** 2
		f = np.fft.rfftfreq(len(x), 1 / SR)
		c = np.cumsum(S)
		return float(f[np.searchsorted(c, 0.995 * c[-1])]) - 220.0

	def duty(**over):
		s.load(neutral(**dict(dict(osc1_shape=2, pulse_width=64), **over)))
		x = mono(s.render([(45, 127, 0.1, 1.0)], 1.0))[w0:w1]
		return float(np.mean(x > 0))

	def equiv(table, y):
		"""The knob value whose measurement is nearest y (tables rise or fall monotonically)."""
		ks = sorted(table)
		vs = [table[k] for k in ks]
		if vs[0] > vs[-1]:
			vs = [-v for v in vs]
			y = -y
		return round(float(np.interp(y, vs, ks)), 1)

	for k in range(0, 128, 4):
		out["fm_knob_edge_hz"][k] = round(fm_edge(osc1_fm=k), 1)
	out["fm_knob_edge_hz"][127] = round(fm_edge(osc1_fm=127), 1)
	print("fm knob", out["fm_knob_edge_hz"], flush=True)
	env = dict(modenv_on=1, modenv_dest=1, modenv_attack=0, modenv_decay=127)
	for base in (0, 32, 64, 96):
		out["fm"][base] = {}
		for v in range(0, 128, 8):
			e = fm_edge(osc1_fm=base, modenv_amount=v, **env)
			out["fm"][base][v] = [round(e, 1), equiv(out["fm_knob_edge_hz"], e)]
		print("fm base", base, out["fm"][base], flush=True)
	for k in range(0, 128, 4):
		out["pw_knob_duty"][k] = round(duty(pulse_width=k), 4)
	out["pw_knob_duty"][127] = round(duty(pulse_width=127), 4)
	print("pw knob", out["pw_knob_duty"], flush=True)
	env = dict(modenv_on=1, modenv_dest=2, modenv_attack=0, modenv_decay=127)
	for base in (0, 32, 64, 96, 127):
		out["pw"][base] = {}
		for v in range(0, 128, 8):
			d = duty(pulse_width=base, modenv_amount=v, **env)
			out["pw"][base][v] = [round(d, 4), equiv(out["pw_knob_duty"], d)]
		print("pw base", base, out["pw"][base], flush=True)
	return out


PARTS = dict(texts=texts, delay=delay, chorus=chorus, eq=eq, effects=effects, controls=effect_controls, modenv=modenv, modenv_amount=modenv_amount)


def run(names):
	s = Synth1()
	s.engine.set_bpm(BPM)
	OUT.mkdir(exist_ok=True)
	for n in names:
		r = PARTS[n](s)
		(OUT / f"fx_{n}.json").write_text(json.dumps(r, indent=1, default=float))


if __name__ == "__main__":
	run(sys.argv[1:] or list(PARTS))
