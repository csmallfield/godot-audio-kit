# SPDX-License-Identifier: Apache-2.0
## OB-Xd / OB-Xf patch -> AKPatch, by direct parameter conversion through OB-Xf's own formulas
## (OB-Xf 1.0.3's engine: src/engine/SynthEngine.h and the voice code it drives), checked
## against OB-Xf's renders (tools/patch_convert/check_vsynth.py obxf).
##
##   var ObXf := preload("res://tools/patch_convert/obxf.gd")
##   var patch: AKPatch = ObXf.convert(sidecar.content.obxf)
##   var notes: Array = ObXf.caveats(sidecar.content.obxf)
##
## `content` is the prep tool's content.obxf: `params` holds OB-Xf 1.0.3's 102 parameters,
## normalized 0..1 by name (OB-Xd programs already converted by osp/obxd.py, a port of OB-Xf's
## importer).
##
## The patch: each oscillator's saw, pulse (or the triangle when both are off) as oscillators of
## their own, osc2 after osc1's pitch, detune, cross mod (fm_mode pitch from osc1's parts), sync
## to osc1, ring mod (an osc2 copy ring-modulated by each of osc1's parts), noise, brightness
## (pre_filter), the 2-pole filter as the state-variable mix (LP-notch-HP, or LP-BP-HP) and the
## 4-pole one as the ladder (its pole morph or the Xpander pole mixes), both envelopes as stages
## envelopes with OB-Xf's curves, both LFOs (their blended waves drawn as custom shapes, S&H and
## S&G as random LFOs of their own) through the matrix, glide, unison, voice pans and slop. Two
## measured make-ups: a high shelf for OB-Xf's brighter oscillators, and osc2 started a quarter
## cycle on (`phase`: OB-Xf's oscillators run free from random phases; GAK's start together).
extends RefCounted

const VERSION := 2
## GAK's level against OB-Xf's (dB). Left at 0: the formulas alone give a median level error of
## 0.01 dB over the 1,620 library patches.
const CAL_DB := 0.0
const LN10 := 2.302585092994046
## OB-Xf's oscillators are 1 V peak to peak (saw -0.5..0.5) and the mixer multiplies by 3; GAK's
## are -1..1. So a part at OB-Xf's mix v plays at GAK level 1.5 v, in the same units.
const OSC_LEVEL := 1.5
## Noise: white is uniform +-0.5 sqrt(sr / 44100) (x 3 in the mixer); pink and red measured from
## OB-Xf itself (rms 0.57 and 0.88 of white's). GAK's noise is uniform -1..1.
const NOISE_LEVEL := [1.565, 0.898, 1.382]
## LFO 1's phase at note-on, in cycles from its -pi start (measured: a fresh OB-Xf's global LFO
## sits at 0.428 pi, and the references' 0.1 s pre-roll moves it on at its rate).
const LFO1_PHASE0 := 0.214
const PREROLL_S := 0.1
## The hold the release's rate is set for (OB-Xf's release falls to -100 dB in its time from
## wherever it starts; GAK's power curve needs one start level): the references' 2 s.
const HOLD_S := 2.0
## The Xpander's pole mixes (src/engine/Filter.h poleMixFactors): [input, pole 1 .. pole 4].
const XPANDER := [[0, 0, 0, 0, 1], [0, 0, 0, 1, 0], [0, 0, 1, 0, 0], [0, 1, 0, 0, 0],
	[1, -3, 3, -1, 0], [1, -2, 1, 0, 0], [1, -1, 0, 0, 0], [0, 0, 2, -4, 2], [0, -2, 2, 0, 0],
	[1, -2, 2, 0, 0], [1, -3, 6, -4, 0], [0, -1, 2, -1, 0], [0, -1, 3, -3, 1], [0, -1, 2, -2, 0],
	[0, -1, 3, -6, 4]]
## Tempo-synced LFO rates: cycles per quarter note, by int(v * 20) (core/Constants.h, the values).
const SYNC_MULT := [1.0 / 12.0, 1.0 / 8.0, 1.0 / 6.0, 3.0 / 16.0, 0.25, 1.0 / 3.0, 3.0 / 8.0, 0.5,
	2.0 / 3.0, 0.75, 1.0, 1.5, 4.0 / 3.0, 2.0, 8.0 / 3.0, 3.0, 4.0, 6.0, 8.0, 12.0, 16.0]
const LFO_POINTS := 256
## Start osc2 a quarter cycle on (its `phase`; see convert()).
const PHASE_SHIFT := true
## OB-Xf's oscillators are brighter at the top than GAK's (its 16-sample minBLEP against GAK's
## polyBLEP, plus its aliasing): a high shelf after the voices makes it up, set from a plain saw
## at notes 36, 60 and 84 (dB at 12 kHz, without and with HQ mode's 2x oversampling).
const SHELF_HZ := 12000.0
const SHELF_DB := [3.75, 1.5]


# --- OB-Xf's curves ------------------------------------------------------------------------

static func _v(p: Dictionary, k: String) -> float:
	return float(p.get(k, 0.0))


static func _on(p: Dictionary, k: String) -> bool:
	return _v(p, k) >= 0.5


## ((r + 1)^v - 1) / r, scaled to min..max (engine/ParamScales.h).
static func logsc(v: float, lo: float, hi: float, r := 19.0) -> float:
	return (pow(r + 1.0, v) - 1.0) / r * (hi - lo) + lo


## Off, on or inverted: 0, 0.5, 1 -> 0, 1, -1.
static func tristate(v: float) -> float:
	var x := roundf(2.0 * v) / 2.0
	return roundf(5.0 * x - 6.0 * x * x)


static func _db(x: float) -> float:
	return 20.0 * log(maxf(x, 1e-9)) / LN10


static func resonance(v: float) -> float:
	return 0.991 - logsc(1.0 - v, 0.0, 0.991, 40.0)


## LFO mod amount 1 (pitch, cutoff) in semitones.
static func lfo_amt1(v: float) -> float:
	return logsc(logsc(v, 0.0, 1.0, 60.0), 0.0, 60.0, 10.0)


static func lfo_rate_hz(v: float) -> float:
	return logsc(v, 0.0, 250.0, 3775.0)


static func voices(v: float) -> int:
	return clampi(1 + roundi(v * 31.0), 1, 32)


## OB-Xf's pan (L 1 - p, R p) as GAK's equal-power pan with the same balance.
static func pan_of(p: float) -> float:
	return clampf(atan2(p, 1.0 - p) * 4.0 / PI - 1.0, -1.0, 1.0)


## A one-pole low-pass cutoff for GAK's pre-filter (exp(-2 pi f / sr) form) that is 3 dB down
## where OB-Xf's (a prewarped TPT one-pole) is.
static func pre_lp_hz(fc: float, sr := 48000.0) -> float:
	var w := TAU * fc / sr
	var lo := fc * 0.5
	var hi := 0.49 * sr
	for i in 40:
		var m := (lo + hi) * 0.5
		var k := 1.0 - exp(-TAU * m / sr)
		var re := 1.0 - (1.0 - k) * cos(w)
		var im := (1.0 - k) * sin(w)
		if k / sqrt(re * re + im * im) < 0.70710678:
			lo = m
		else:
			hi = m
	return lo


## An OB-Xf ADSR (engine/AdsrEnvelope.h) as a stages envelope, normalized to its 0.9 peak (the
## caller scales by 0.9). Times in ms. Attack: an RC charge toward 1.3 stopped at 0.9, blended with
## a line by `curve`: a power curve through the blend's midpoint. Decay: exponential toward 0,
## stopped at the sustain (exactly a power curve with amount ln(level ratio)). Release: from the
## key-up level to 1e-5 in its time.
static func envelope(a_ms: float, d_ms: float, s: float, r_ms: float, curve: float, vel_amt: float) -> Dictionary:
	var at := 0.965 * a_ms / 1000.0
	var y := (1.0 - curve) * 0.75975 + 0.5 * curve
	var aa := 2.0 * log(1.0 / clampf(y, 0.01, 0.99) - 1.0)
	var st := []
	st.append({time_s = at, level = 1.0, curve = "power", amount = aa} if absf(aa) > 0.01 else {time_s = at, level = 1.0})
	var sus := minf(s, 0.9) / 0.9
	var dt := 0.0
	var da := 0.0
	var dl := sus
	if sus >= 0.9999:
		dl = 1.0
	elif s > 1e-5:
		dt = d_ms / 1000.0 * log(s / 0.9) / log(s + 1e-4)
		da = log(sus)
	else:
		dl = 0.0
		dt = d_ms / 1000.0 * log(1e-5 / 0.9) / log(1e-4)
		da = log(1e-5 / 0.9)
	st.append({time_s = dt, level = dl, curve = "power", amount = da})
	# the level at key-up after HOLD_S
	var lv := dl
	if HOLD_S < at:
		lv = HOLD_S / maxf(at, 1e-6)
	elif HOLD_S < at + dt and dt > 0.0:
		var x := (HOLD_S - at) / dt
		lv = 1.0 - (1.0 - dl) * (exp(da * x) - 1.0) / (exp(da) - 1.0) if absf(da) > 1e-6 else 1.0 + (dl - 1.0) * x
	var l_ob := maxf(lv * 0.9, 0.0)
	var ra := log(1e-5 / (l_ob + 1e-4))
	st.append({time_s = r_ms / 1000.0, level = 0.0, curve = "power", amount = minf(ra, -0.5)})
	# OB-Xf delays its envelopes 16 samples (at 48 kHz), to line up with its oscillators' BLEP latency
	var e := {stages = st, sustain = 1, delay_s = 16.0 / 48000.0}
	if vel_amt > 0.0:
		e.level_velocity = clampf(vel_amt, 0.0, 1.0)
	return e


## An LFO's deterministic waves (sine/triangle, square/saw) at phase phi (-pi..pi), as Lfo.h.
static func _lfo_wave(phi: float, w1: float, w2: float, pw: float) -> float:
	var out := 0.0
	if w1 < 0.0:
		out += sin(phi) * -w1
	elif w1 > 0.0:
		out += (2.0 / PI * absf(phi + PI / 2.0 - (TAU if phi > PI / 2.0 else 0.0)) - 1.0) * w1
	if w2 < 0.0:
		out += (-1.0 if phi > PI * pw * 0.9 else 1.0) * -w2
	elif w2 > 0.0:
		var x := -phi / PI
		var a := 0.5 * -pw
		if a != 0.0:
			for i in 3:
				x = x - a * x * x + a
		out += x * w2
	return out


# --- conversion ----------------------------------------------------------------------------

static func _params(content: Dictionary) -> Dictionary:
	return content.get("params", content)


## The parts of one oscillator: [{shape, sign}] (saw, pulse, or the triangle when both are off).
static func _parts(p: Dictionary, n: int) -> Array:
	var out := []
	if _on(p, "Osc%dSawWave" % n):
		out.append("saw")
	if _on(p, "Osc%dPulseWave" % n):
		out.append("pulse")
	if out.is_empty():
		out.append("triangle")
	return out


## An OB-Xd / OB-Xf patch (the prep tool's content.obxf) as a patch.
static func convert(content: Dictionary) -> AKPatch:
	var p := _params(content)
	var out := AKPatch.new()
	var tune := 2.0 * _v(p, "Tune") - 1.0
	var tr := roundf((2.0 * _v(p, "Transpose") - 1.0) * 24.0)
	var s1 := 48.0 * _v(p, "Osc1Pitch") - 24.0 + tune + tr
	var s2 := 48.0 * _v(p, "Osc2Pitch") - 24.0 + tune + tr + logsc(_v(p, "Osc2Detune"), 0.001, 0.6)
	var duty1 := clampf(0.5 + 0.475 * _v(p, "OscPW"), 0.1, 1.0)
	var duty2 := clampf(0.5 + 0.475 * (_v(p, "OscPW") + _v(p, "Osc2PWOffset")), 0.1, 1.0)
	var m1 := _v(p, "Osc1Mix")
	var m2 := _v(p, "Osc2Mix")
	var ring := _v(p, "RingModMix")
	var noise := _v(p, "NoiseMix")
	var xmod := 48.0 * _v(p, "OscCrossmod")
	var sync := _on(p, "OscSync")
	var parts1 := _parts(p, 1)
	var parts2 := _parts(p, 2)
	var need_ring := ring > 0.0
	# A pulse is OB-Xf's -0.5 x GAK's plus a DC offset (duty - 0.5). Ring mod multiplies the
	# offsets in: each oscillator's offset times the other's wave, added to that wave's level.
	var dc1 := (duty1 - 0.5) if "pulse" in parts1 else 0.0
	var dc2 := (duty2 - 0.5) if "pulse" in parts2 else 0.0
	var need2 := m2 > 0.0 or (need_ring and dc1 != 0.0)
	var need1 := m1 > 0.0 or need_ring or ((need2) and (xmod > 0.0 or sync))

	# Oscillators, in GAK's order: noise, osc2's parts, the ring copies, osc1's parts last (they
	# modulate the others: computed first, heard the same sample).
	var oscs: Array[Dictionary] = []
	var g1 := []   # GAK indices (0-based) of osc1's parts
	var g2 := []   # of osc2's parts and the ring copies (they follow osc2's pitch and width)
	var pulses1 := []
	var pulses2 := []
	if noise > 0.0:
		var col := 0 if _v(p, "NoiseColor") < 1.0 / 3.0 else (1 if _v(p, "NoiseColor") < 2.0 / 3.0 else 2)
		oscs.append({shape = "noise", level = NOISE_LEVEL[col] * noise})
	var n2 := oscs.size()
	var o2_specs := []
	if need2:
		for sh: String in parts2:
			o2_specs.append({shape = sh, level = (OSC_LEVEL * m2 + (1.5 * ring * dc1 if need_ring else 0.0)) * (-1.0 if sh == "pulse" else 1.0)})
	if need_ring and need1:
		for a: String in parts1:
			for b: String in parts2:
				var sg := (-1.0 if a == "pulse" else 1.0) * (-1.0 if b == "pulse" else 1.0)
				o2_specs.append({shape = b, level = 0.75 * ring * sg, ring_part = a})
	var first1 := n2 + o2_specs.size()
	var idx1 := {}
	if need1:
		for i in parts1.size():
			idx1[parts1[i]] = first1 + i
	# crossmod: osc1's parts (OB-Xf units: 0.5 x GAK's, the pulse inverted and offset) into osc2's pitch
	var fm := []
	var xdc := 0.0
	if xmod > 0.0 and need1:
		for a: String in parts1:
			fm.append({from = idx1[a] + 1, index = xmod * 0.5 * (-1.0 if a == "pulse" else 1.0)})
			if a == "pulse":
				xdc += xmod * (duty1 - 0.5)
	for spec: Dictionary in o2_specs:
		var o := {shape = spec.shape, level = spec.level}
		if s2 + xdc != 0.0:
			o.semitones = s2 + xdc
		if spec.shape == "pulse":
			o.width = clampf(duty2, 0.01, 0.99)
			pulses2.append(oscs.size())
		if sync and need1:
			o.sync_to = first1 + 1
		if not fm.is_empty():
			o.fm_mode = "pitch"
			if fm.size() == 1:
				o.fm_from = fm[0].from
				o.fm_index = fm[0].index
			else:
				o.fm = fm.duplicate(true)
		if spec.has("ring_part"):
			o.ring_from = idx1[spec.ring_part] + 1
		g2.append(oscs.size())
		oscs.append(o)
	if need1:
		for sh: String in parts1:
			var o := {shape = sh, level = (OSC_LEVEL * m1 + 1.5 * ring * dc2) * (-1.0 if sh == "pulse" else 1.0)}
			if s1 != 0.0:
				o.semitones = s1
			if sh == "pulse":
				o.width = clampf(duty1, 0.01, 0.99)
				pulses1.append(oscs.size())
			g1.append(oscs.size())
			oscs.append(o)
	if oscs.is_empty():
		oscs.append({shape = "saw", level = 0.0})
	out.oscillators = oscs

	# voices: polyphony, unison, pans
	var n_poly := voices(_v(p, "Polyphony"))
	var n_uni := mini(voices(_v(p, "UnisonVoices")), n_poly) if _on(p, "Unison") else 1
	var keys := maxi(1, n_poly / n_uni)
	var gain_db := 0.0
	var pans := []
	for i in 8:
		pans.append(clampf(_v(p, "PanVoice%d" % (i + 1)) if p.has("PanVoice%d" % (i + 1)) else 0.5, 0.0, 1.0))
	var pow_ob := 0.0
	for i in n_uni:
		var q: float = pans[i % 8]
		pow_ob += (1.0 - q) * (1.0 - q) + q * q
	gain_db += 10.0 * log(pow_ob / n_uni / 2.0) / LN10
	var udet := logsc(_v(p, "UnisonDetune"), 0.001, 1.0)
	if n_uni > 1:
		out.unison = mini(n_uni, 8)
		out.detune_cents = 100.0 * udet * (n_uni - 1.0) / (n_uni + 1.0)
		gain_db += 10.0 * log(float(n_uni)) / LN10
		var lo := 1.0
		var hi := -1.0
		for i in n_uni:
			var pp := pan_of(pans[i % 8])
			lo = minf(lo, pp)
			hi = maxf(hi, pp)
		out.spread = clampf((hi - lo) * 0.5, 0.0, 1.0)
	var vp := []
	var any_pan := false
	for j in mini(keys, 32):
		var s := 0.0
		for i in n_uni:
			s += pan_of(pans[(j * n_uni + i) % 8])
		vp.append(snappedf(s / n_uni, 0.0001))
		any_pan = any_pan or absf(vp.back()) > 0.001
	# a GAK voice slot holds n_uni of OB-Xf's voices, whose own offsets average out
	var su := 1.0 / sqrt(float(n_uni))
	var slop := {}
	if udet > 0.002:
		slop.pitch_cents = 50.0 * udet * su
	if _v(p, "FilterSlop") > 0.0:
		slop.cutoff_octaves = 0.75 * _v(p, "FilterSlop") * su
	if _v(p, "EnvelopeSlop") > 0.0:
		slop.env_time = 0.5 * _v(p, "EnvelopeSlop") * su
	if _v(p, "LevelSlop") > 0.0:
		slop.level_db = _db(1.0 + 0.335 * _v(p, "LevelSlop") * su)
	if any_pan or not slop.is_empty():
		out.voice_pan = vp
	out.slop = slop
	var sha := String(content.get("sound_sha256", ""))
	out.seed = sha.substr(0, 7).hex_to_int() if sha.length() >= 7 else 1
	if keys > 1:
		out.mode = "poly"
		out.polyphony = keys
	else:
		var lm := roundi(_v(p, "EnvLegatoMode") * 3.0)
		out.mode = "legato" if lm == 0 or lm == 2 else "mono"
		out.polyphony = 1

	# filter
	var r := resonance(_v(p, "FilterResonance"))
	var kt := _v(p, "FilterKeyFollow")
	var cut := 440.0 * pow(2.0, (120.0 * _v(p, "FilterCutoff") - 45.0 + kt * 7.0) / 12.0)
	var fmode := _v(p, "FilterMode")
	if _on(p, "Filter4PoleMode"):
		var f := {type = "ladder", cutoff_hz = cut, resonance = 0.875 * r, drive = 0.1}
		if _on(p, "Filter4PoleXpander"):
			f.pole_mix = XPANDER[clampi(roundi(_v(p, "FilterXpanderMode") * 14.0), 0, 14)].duplicate()
		elif fmode > 0.0:
			f.poles = 4.0 - 3.0 * fmode
		out.filter = f
		# OB-Xf makes up 1 + 0.45 k for its k = 3.5 r; GAK 1 + 0.5 k for its k = 4 x 0.875 r
		gain_db += _db((1.0 + 1.575 * r) / (1.0 + 1.75 * r))
	else:
		var push := _on(p, "Filter2PolePush")
		var damp := maxf(1.0 - r - (0.035 if push else 0.0), 0.0125)
		var f := {type = "mix", cutoff_hz = minf(cut, 19000.0) if push else cut, q = 1.0 / (2.0 * damp)}
		if _on(p, "Filter2PoleBPBlend"):
			if fmode < 0.5:
				f.merge({low = 2.0 * (0.5 - fmode), band = 2.0 * fmode, high = 0.0}, true)
			else:
				f.merge({low = 0.0, band = 2.0 * (1.0 - fmode), high = 2.0 * (fmode - 0.5)}, true)
		else:
			f.merge({low = 1.0 - fmode, band = 0.0, high = fmode}, true)
		out.filter = f
	var pre := {highpass_hz = 12.0}
	var bright := 7000.0 + 19000.0 * _v(p, "OscBrightness")
	if bright < 23000.0:
		pre.lowpass_hz = pre_lp_hz(bright)
	out.pre_filter = pre

	# envelopes: amp (env1), filter (env2)
	out.amp_env = envelope(logsc(_v(p, "AmpEnvAttack"), 4.0, 60000.0, 900.0), logsc(_v(p, "AmpEnvDecay"), 4.0, 60000.0, 900.0),
		_v(p, "AmpEnvSustain"), logsc(_v(p, "AmpEnvRelease"), 8.0, 60000.0, 900.0), _v(p, "AmpEnvAttackCurve"), 0.0)
	out.env2 = envelope(logsc(_v(p, "FilterEnvAttack"), 1.0, 60000.0, 900.0), logsc(_v(p, "FilterEnvDecay"), 1.0, 60000.0, 900.0),
		_v(p, "FilterEnvSustain"), logsc(_v(p, "FilterEnvRelease"), 1.0, 60000.0, 900.0), _v(p, "FilterEnvAttackCurve"),
		_v(p, "VelToFilterEnv"))
	out.velocity_sens = clampf(_v(p, "VelToAmpEnv"), 0.0, 1.0)
	out.velocity_curve = 1.0

	# modulation, gathered per source: pitch (semitones) of osc1 / osc2, pulse width (OB-Xf's pw
	# units) of osc1 / osc2, cutoff (octaves), amp
	var acc := {}
	var add := func(src: String, what: String, amt: float) -> void:
		if amt == 0.0:
			return
		if not acc.has(src):
			acc[src] = {}
		acc[src][what] = float(acc[src].get(what, 0.0)) + amt
	var fenv := -1.0 if _on(p, "FilterEnvInvert") else 1.0
	add.call("env2", "cutoff", 140.0 * _v(p, "FilterEnvAmount") * 0.9 / 12.0 * fenv)
	var ep := 40.0 * _v(p, "EnvToPitchAmount") * 0.9 * fenv * (-1.0 if _on(p, "EnvToPitchInvert") else 1.0)
	add.call("env2", "pitch2", ep)
	if _on(p, "EnvToPitchBothOscs"):
		add.call("env2", "pitch1", ep)
	var ew := 1.0556 * _v(p, "EnvToPWAmount") * 0.9 * fenv * (-1.0 if _on(p, "EnvToPWInvert") else 1.0)
	add.call("env2", "pw2", ew)
	if _on(p, "EnvToPWBothOscs"):
		add.call("env2", "pw1", ew)

	# LFOs: each OB-Xf LFO's sine/triangle and square/saw blend as one custom LFO, its S&H or
	# S&G as a random one
	var lfos := []
	var amp_const := 1.0
	for l in [1, 2]:
		var pre_k := "LFO%d" % l
		var a1 := lfo_amt1(_v(p, pre_k + "ModAmount1"))
		var v2 := _v(p, pre_k + "ModAmount2")
		var dst := {pitch1 = tristate(_v(p, pre_k + "ToOsc1Pitch")) * a1, pitch2 = tristate(_v(p, pre_k + "ToOsc2Pitch")) * a1,
			cutoff = tristate(_v(p, pre_k + "ToFilterCutoff")) * a1 / 12.0,
			pw1 = tristate(_v(p, pre_k + "ToOsc1PW")) * 0.7 * v2, pw2 = tristate(_v(p, pre_k + "ToOsc2PW")) * 0.7 * v2}
		var tv := tristate(_v(p, pre_k + "ToVolume"))
		var vol := 0.0
		if tv != 0.0 and v2 > 0.0:
			var c0 := 1.0 - 0.5 * v2 * absf(tv)
			amp_const *= c0
			vol = -0.5 * v2 * tv / maxf(c0, 0.01)
		var any := vol != 0.0
		for k: String in dst:
			any = any or dst[k] != 0.0
		if not any:
			continue
		var w1 := 2.0 * _v(p, pre_k + "Wave1") - 1.0
		var w2 := 2.0 * _v(p, pre_k + "Wave2") - 1.0
		var w3 := 2.0 * _v(p, pre_k + "Wave3") - 1.0
		var pw := _v(p, pre_k + "PW")
		var base := {free = l == 1}
		var hz := 0.0
		if _on(p, pre_k + "TempoSync"):
			var mult: float = SYNC_MULT[clampi(int(_v(p, pre_k + "Rate") * 20.0), 0, 20)]
			base.rate_sync = 1.0 / mult
			hz = 2.0 * mult
		else:
			hz = lfo_rate_hz(_v(p, pre_k + "Rate"))
			if l == 2:
				hz = maxf(hz, 0.01)
			base.rate_hz = hz
		var ph := 0.0
		if l == 1:
			ph = fposmod(0.5 + LFO1_PHASE0 + hz * PREROLL_S, 1.0)
		var parts := []
		if absf(w1) > 1e-4 or absf(w2) > 1e-4:
			var pts := []
			var peak := 0.0
			for i in LFO_POINTS:
				var y := _lfo_wave(-PI + TAU * i / LFO_POINTS, w1, w2, pw)
				pts.append(y)
				peak = maxf(peak, absf(y))
			if peak > 1e-6:
				for i in pts.size():
					pts[i] = snappedf(pts[i] / peak, 0.00001)
				var d := base.duplicate()
				d.merge({shape = "custom", points = pts, interp = "linear", phase = snappedf(ph, 0.0001)}, true)
				parts.append([d, peak])
		if absf(w3) > 1e-4:
			var d := base.duplicate()
			d.merge({shape = "random" if w3 < 0.0 else "smooth", phase = snappedf(ph, 0.0001)}, true)
			parts.append([d, absf(w3)])
		for pr: Array in parts:
			if lfos.size() >= 8:
				break
			var src := "lfo%d" % (lfos.size() + 1)
			lfos.append(pr[0])
			for k: String in dst:
				add.call(src, k, dst[k] * pr[1])
			add.call(src, "amp", vol * pr[1])
	if lfos.size() > 0:
		out.lfo1 = lfos[0]
	if lfos.size() > 1:
		out.lfo2 = lfos[1]
	if lfos.size() > 2:
		var extra: Array[Dictionary] = []
		for i in range(2, lfos.size()):
			extra.append(lfos[i])
		out.lfos = extra
	gain_db += _db(amp_const)

	# matrix rows
	var mods: Array[Dictionary] = []
	if kt != 0.0:
		mods.append({source = "key", dest = "cutoff", amount = kt})
	# Start phases. OB-Xf's oscillators run free from random phases; GAK's start at 0 (or at seeded
	# random ones under unison). Two oscillators near one pitch started in phase sum 6 dB up where
	# OB-Xf's average 3, so osc2 starts a quarter cycle on. The parts of one OB-Xf oscillator (saw,
	# pulse, osc2's ring copies) share its phases, under unison too (phase_with).
	var shift := PHASE_SHIFT and not g1.is_empty() and not g2.is_empty() and m1 > 0.0 and m2 > 0.0 and not sync and out.unison == 1
	for grp: Array in [g1, g2]:
		for k in range(1, grp.size()):
			oscs[grp[k]].phase_with = grp[0] + 1
	if shift:
		oscs[g2[0]].phase = 0.25
		if out.unison == 1:
			for k in range(1, g2.size()):
				oscs[g2[k]].erase("phase_with")
				oscs[g2[k]].phase = 0.25
	# OB-Xf holds each oscillator under 0.45 cycles a sample; cross mod and env to pitch can push past
	out.nyquist_clamp = true
	out.oscillators = oscs
	for src: String in acc:
		var a: Dictionary = acc[src]
		var pa1 := float(a.get("pitch1", 0.0))
		var pa2 := float(a.get("pitch2", 0.0))
		if g1.is_empty():
			pa1 = pa2
		if g2.is_empty():
			pa2 = pa1
		if pa1 == pa2:
			if pa1 != 0.0:
				mods.append({source = src, dest = "pitch", amount = pa1})
		elif pa1 == 0.0:
			for j: int in g2:
				mods.append({source = src, dest = "osc%d.pitch" % (j + 1), amount = pa2})
		elif pa2 == 0.0:
			for j: int in g1:
				mods.append({source = src, dest = "osc%d.pitch" % (j + 1), amount = pa1})
		else:
			mods.append({source = src, dest = "pitch", amount = pa1})
			for j: int in g2:
				mods.append({source = src, dest = "osc%d.pitch" % (j + 1), amount = pa2 - pa1})
		# the pulse width: GAK's width is OB-Xf's duty here (the pulse is inverted), half a pw unit
		for j: int in pulses1:
			if a.has("pw1"):
				mods.append({source = src, dest = "osc%d.width" % (j + 1), amount = 0.5 * float(a.pw1)})
		for j: int in pulses2:
			if a.has("pw2"):
				mods.append({source = src, dest = "osc%d.width" % (j + 1), amount = 0.5 * float(a.pw2)})
		if a.has("cutoff"):
			mods.append({source = src, dest = "cutoff", amount = float(a.cutoff)})
		if a.has("amp"):
			mods.append({source = src, dest = "amp", amount = float(a.amp)})
	out.mods = mods

	# playing
	out.bend_range = minf(48.0 * _v(p, "PitchBendUp"), 24.0)
	var porta := _v(p, "Portamento")
	if porta > 0.0:
		var tau := 1.0 / (TAU * logsc(1.0 - porta, 0.14, 250.0, 150.0))
		out.glide_s = snappedf(tau, 0.0001) if tau > 0.001 else 0.0
	out.tempo_bpm = 120.0
	var fx: Array[Dictionary] = [{type = "eq", high_hz = SHELF_HZ, high_db = SHELF_DB[1 if _on(p, "HQMode") else 0]}]
	out.effects = fx
	# OB-Xf's output: the amp envelope peaks at 0.9, x 0.3 x Volume
	gain_db += _db(0.9 * 0.3 * _v(p, "Volume")) + CAL_DB
	out.gain_db = maxf(gain_db, -120.0)
	out.resource_name = String(content.get("name", ""))
	return out


## What the conversion only approximates, for this patch.
static func caveats(content: Dictionary) -> Array:
	var p := _params(content)
	var out := []
	var parts1 := _parts(p, 1)
	var parts2 := _parts(p, 2)
	if _v(p, "NoiseMix") > 0.0 and _v(p, "NoiseColor") >= 1.0 / 3.0:
		out.append("noise: %s noise played as white at its level" % ("pink" if _v(p, "NoiseColor") < 2.0 / 3.0 else "red"))
	var pwm := _v(p, "EnvToPWAmount") > 0.0
	for l in [1, 2]:
		for k in ["ToOsc1PW", "ToOsc2PW"]:
			pwm = pwm or (tristate(_v(p, "LFO%d%s" % [l, k])) != 0.0 and _v(p, "LFO%dModAmount2" % l) > 0.0)
	if _v(p, "RingModMix") > 0.0 and ("pulse" in parts1 or "pulse" in parts2) and pwm:
		out.append("ring mod of a modulated pulse: its DC terms taken at the knob's width")
	var d2 := 0.5 + 0.475 * (_v(p, "OscPW") + _v(p, "Osc2PWOffset"))
	var ew := 0.5 * 1.0556 * 0.9 * _v(p, "EnvToPWAmount") * (-1.0 if _on(p, "EnvToPWInvert") != _on(p, "FilterEnvInvert") else 1.0)
	if ("pulse" in parts2 and (d2 >= 0.99 or d2 + ew >= 0.99)) or ("pulse" in parts1 and _on(p, "EnvToPWBothOscs") and 0.5 + 0.475 * _v(p, "OscPW") + ew >= 0.99):
		out.append("pulse width at OB-Xf's 100% (silent) stops at GAK's 99%")
	var n_poly := voices(_v(p, "Polyphony"))
	var n_uni := mini(voices(_v(p, "UnisonVoices")), n_poly) if _on(p, "Unison") else 1
	if n_uni > 8:
		out.append("unison: %d voices stacked as 8" % n_uni)
	var vols := 0
	for l in [1, 2]:
		var pre_k := "LFO%d" % l
		if tristate(_v(p, pre_k + "ToVolume")) != 0.0 and _v(p, pre_k + "ModAmount2") > 0.0:
			vols += 1
		var used := false
		for k in ["ToOsc1Pitch", "ToOsc2Pitch", "ToFilterCutoff"]:
			used = used or (tristate(_v(p, pre_k + k)) != 0.0 and _v(p, pre_k + "ModAmount1") > 0.0)
		for k in ["ToOsc1PW", "ToOsc2PW", "ToVolume"]:
			used = used or (tristate(_v(p, pre_k + k)) != 0.0 and _v(p, pre_k + "ModAmount2") > 0.0)
		if used and absf(2.0 * _v(p, pre_k + "Wave3") - 1.0) > 1e-4:
			out.append("lfo%d: sample and hold/glide is random (and S&G glides along a half cosine)" % l)
	if vols > 1:
		out.append("both LFOs to volume: their product taken as a sum")
	var porta := _v(p, "Portamento")
	if porta > 0.0:
		var tau := 1.0 / (TAU * logsc(1.0 - porta, 0.14, 250.0, 150.0))
		if tau > 0.02:
			out.append("glide: OB-Xf's fresh voice glides its first note from A6; GAK's doesn't")
	if _on(p, "BendOsc2Only"):
		out.append("bend on osc2 only not converted")
	var keys := maxi(1, n_poly / n_uni)
	if keys == 1:
		var lm := roundi(_v(p, "EnvLegatoMode") * 3.0)
		if lm == 1 or lm == 2:
			out.append("legato mode: one envelope legato, the other retriggered, taken as %s" % ("mono" if lm == 1 else "legato"))
		if int(_v(p, "NotePriority") * 2.0) != 0:
			out.append("note priority low/high not converted (last)")
	if not _on(p, "Filter4PoleMode"):
		var r := resonance(_v(p, "FilterResonance"))
		if 1.0 - r - (0.035 if _on(p, "Filter2PolePush") else 0.0) < 0.02:
			out.append("2-pole filter near self-oscillation: OB-Xf's diode damping not modelled")
	return out
