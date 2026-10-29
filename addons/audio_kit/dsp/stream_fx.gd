# SPDX-License-Identifier: Apache-2.0
@tool
## Sound-shaping effects that stream a stereo sample at a time: chorus,
## flanger, phaser, eq, compressor, saturate. The reference for the native
## effects (native/src/fx.h), which run the same steps in the same order, and
## the fallback without the native core. One effect is a spec dictionary:
##
##   {type = "chorus", rate_hz = 0.8, depth_ms = 3.0, delay_ms = 12.0, voices = 2, mix = 0.5, spread = 1.0, feedback = 0.0}
##   {type = "flanger", rate_hz = 0.25, depth_ms = 2.0, delay_ms = 1.0, feedback = 0.6, mix = 0.5, spread = 1.0}
##   {type = "phaser", rate_hz = 0.4, stages = 4, center_hz = 800.0, range_octaves = 2.0, depth = 1.0, feedback = 0.4, mix = 0.5, spread = 1.0}
##   {type = "eq", low_db = 0.0, low_hz = 120.0, mid_db = 0.0, mid_hz = 1000.0, mid_q = 0.7, high_db = 0.0, high_hz = 6000.0}
##   {type = "compressor", threshold_db = -18.0, ratio = 4.0, attack_s = 0.01, release_s = 0.12, knee_db = 6.0, makeup_db = 0.0}
##   {type = "saturate", drive_db = 12.0, tone_hz = 6000.0, asymmetry = 0.0, mix = 1.0, output_db = 0.0}
##
## The same specs go in a recipe's `fx`, a patch's `effects`, and (as the
## AKChorus, AKPhaser ... bus effects' properties) on a Godot bus.
class_name AKStreamFx
extends RefCounted

const TYPES := ["", "chorus", "flanger", "phaser", "eq", "compressor", "saturate"]
const DEFAULTS := {
	"chorus": {rate_hz = 0.8, depth_ms = 3.0, delay_ms = 12.0, voices = 2, mix = 0.5, spread = 1.0, feedback = 0.0},
	"flanger": {rate_hz = 0.25, depth_ms = 2.0, delay_ms = 1.0, voices = 1, mix = 0.5, spread = 1.0, feedback = 0.6},
	"phaser": {rate_hz = 0.4, stages = 4, center_hz = 800.0, range_octaves = 2.0, depth = 1.0, feedback = 0.4, mix = 0.5, spread = 1.0},
	"eq": {low_db = 0.0, low_hz = 120.0, mid_db = 0.0, mid_hz = 1000.0, mid_q = 0.7, high_db = 0.0, high_hz = 6000.0},
	"compressor": {threshold_db = -18.0, ratio = 4.0, attack_s = 0.01, release_s = 0.12, knee_db = 6.0, makeup_db = 0.0},
	"saturate": {drive_db = 12.0, tone_hz = 6000.0, asymmetry = 0.0, mix = 1.0, output_db = 0.0},
}


## True for the types this class streams (recipes route these here).
static func handles(type: StringName) -> bool:
	return DEFAULTS.has(String(type))


## A spec with defaults filled and ranges clamped, as plain numbers (the
## form the native effects take). `type` becomes its index in TYPES.
static func compile(spec: Dictionary) -> Dictionary:
	var t := String(spec.get("type", ""))
	var d: Dictionary = DEFAULTS.get(t, {}).duplicate()
	for k in spec:
		if String(k) != "type":
			d[String(k)] = spec[k]
	var c := {type = TYPES.find(t)}
	for k in d:
		c[k] = float(d[k]) if not (d[k] is bool) else (1.0 if d[k] else 0.0)
	if c.has("voices"):
		c.voices = clampi(int(c.voices), 1, 4)
	if c.has("stages"):
		c.stages = clampi(int(c.stages), 1, 12)
	if c.has("mix"):
		c.mix = clampf(c.mix, 0.0, 1.0)
	if c.has("feedback"):
		c.feedback = clampf(c.feedback, -0.95, 0.95)
	if c.has("delay_ms"):
		c.delay_ms = maxf(c.delay_ms, 1000.0 / 48000.0)   # at least about a sample
	if c.has("depth_ms"):
		c.depth_ms = maxf(0.0, c.depth_ms)
	if c.has("ratio"):
		c.ratio = maxf(1.0, c.ratio)
	return c


## Run a chain of specs over stereo arrays (in place on copies): [l, r].
static func process(specs: Array, l: PackedFloat32Array, r: PackedFloat32Array, sr: int) -> Array:
	var nn := AKDsp.nat()
	var compiled := []
	for s in specs:
		compiled.append(compile(s))
	if nn and nn.has_method(&"fx_process"):
		return nn.fx_process(compiled, l, r, sr)
	var chain := Chain.new(compiled, sr)
	var ol := l.duplicate()
	var orr := r.duplicate()
	var io := PackedFloat64Array([0.0, 0.0])
	for i in ol.size():
		io[0] = ol[i]
		io[1] = orr[i]
		chain.tick(io)
		ol[i] = io[0]
		orr[i] = io[1]
	return [ol, orr]


## The tail an effect chain adds (delay lines ring on): a little room so
## a recipe doesn't cut it off.
static func tail_s(specs: Array) -> float:
	var t := 0.0
	for s in specs:
		match String(s.get("type", "")):
			"chorus", "flanger":
				var c := compile(s)
				t += (c.delay_ms + c.depth_ms) / 1000.0 * (1.0 + 6.0 * absf(c.get("feedback", 0.0)))
			"phaser":
				t += 0.05
	return t


## A chain of compiled effects with state, ticking one stereo sample (a
## PackedFloat64Array [l, r]) at a time.
class Chain:
	var fx: Array[Effect] = []

	func _init(compiled: Array, sr: int) -> void:
		for c: Dictionary in compiled:
			if int(c.get("type", 0)) > 0:
				fx.append(Effect.new(c, sr))

	func tick(io: PackedFloat64Array) -> void:
		for f in fx:
			f.tick(io)

	func is_empty() -> bool:
		return fx.is_empty()


## One effect (mirrors ak::Fx).
class Effect:
	var type := 0
	var sr := 48000
	var p := {}
	var ph := 0.0
	# Members, not arrays of arrays: a packed array inside an Array would be
	# copied on every write.
	var line_l := PackedFloat32Array()
	var line_r := PackedFloat32Array()
	var w := 0
	var ap_z := PackedFloat64Array()   # 12 allpass states for L, then 12 for R
	var ph_last := PackedFloat64Array([0.0, 0.0])
	var bq := PackedFloat64Array()     # 3 biquads x 13: b0 b1 b2 a1 a2, x1 x2 y1 y2 for L, then for R
	var gr_db := 0.0
	var k_att := 0.0
	var k_rel := 0.0
	var sat_g := 1.0
	var sat_off := 0.0
	var sat_lp := 0.0
	var sat_out := 1.0
	var sat_z := PackedFloat64Array([0.0, 0.0])
	# Knobs as fields (looked up per sample otherwise).
	var rate := 0.0
	var depth_ms := 0.0
	var delay_ms := 0.0
	var feedback := 0.0
	var mix := 0.5
	var spread := 1.0
	var voices := 1
	var stages := 4
	var center := 800.0
	var range_oct := 2.0
	var depth := 1.0
	var threshold := -18.0
	var ratio := 4.0
	var knee := 6.0
	var makeup := 0.0
	var asym := 0.0

	func _init(c: Dictionary, p_sr: int) -> void:
		p = c
		sr = p_sr
		type = int(c.type)
		rate = float(c.get("rate_hz", 0.0))
		depth_ms = float(c.get("depth_ms", 0.0))
		delay_ms = float(c.get("delay_ms", 0.0))
		feedback = float(c.get("feedback", 0.0))
		mix = float(c.get("mix", 0.5))
		spread = float(c.get("spread", 1.0))
		voices = int(c.get("voices", 1))
		stages = int(c.get("stages", 4))
		center = float(c.get("center_hz", 800.0))
		range_oct = float(c.get("range_octaves", 2.0))
		depth = float(c.get("depth", 1.0))
		threshold = float(c.get("threshold_db", -18.0))
		ratio = float(c.get("ratio", 4.0))
		knee = float(c.get("knee_db", 6.0))
		makeup = float(c.get("makeup_db", 0.0))
		asym = float(c.get("asymmetry", 0.0))
		ap_z.resize(24)
		ap_z.fill(0.0)
		if type == 1 or type == 2:
			var n := maxi(8, ceili((delay_ms + depth_ms) * sr / 1000.0) + 4)
			line_l.resize(n)
			line_l.fill(0.0)
			line_r.resize(n)
			line_r.fill(0.0)
		if type == 4:
			bq = _shelf(float(c.low_hz), float(c.low_db), false) + _peak(float(c.mid_hz), float(c.mid_db), float(c.mid_q)) \
				+ _shelf(float(c.high_hz), float(c.high_db), true)
		if type == 5:
			var a := float(c.attack_s) * sr
			var r := float(c.release_s) * sr
			k_att = exp(-1.0 / (a if a > 1.0 else 1.0))
			k_rel = exp(-1.0 / (r if r > 1.0 else 1.0))
		if type == 6:
			sat_g = pow(10.0, float(c.drive_db) / 20.0)
			sat_off = tanh(asym)
			sat_lp = 1.0 - exp(-TAU * float(c.tone_hz) / sr)
			sat_out = pow(10.0, float(c.output_db) / 20.0) / tanh(sat_g)

	func _coef(b0: float, b1: float, b2: float, a0: float, a1: float, a2: float) -> PackedFloat64Array:
		var q := PackedFloat64Array([b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0, 0, 0, 0, 0, 0, 0, 0, 0])
		return q

	func _shelf(f: float, gain_db: float, high: bool) -> PackedFloat64Array:
		var A := pow(10.0, gain_db / 40.0)
		var w0 := TAU * f / sr
		var cw := cos(w0)
		var sw := sin(w0)
		var alpha := sw / 2.0 * sqrt(2.0)
		var t := 2.0 * sqrt(A) * alpha
		if not high:
			return _coef(A * ((A + 1) - (A - 1) * cw + t), 2 * A * ((A - 1) - (A + 1) * cw), A * ((A + 1) - (A - 1) * cw - t),
				(A + 1) + (A - 1) * cw + t, -2 * ((A - 1) + (A + 1) * cw), (A + 1) + (A - 1) * cw - t)
		return _coef(A * ((A + 1) + (A - 1) * cw + t), -2 * A * ((A - 1) + (A + 1) * cw), A * ((A + 1) + (A - 1) * cw - t),
			(A + 1) - (A - 1) * cw + t, 2 * ((A - 1) - (A + 1) * cw), (A + 1) - (A - 1) * cw - t)

	func _peak(f: float, gain_db: float, q: float) -> PackedFloat64Array:
		var A := pow(10.0, gain_db / 40.0)
		var w0 := TAU * f / sr
		var cw := cos(w0)
		var sw := sin(w0)
		var alpha := sw / (2.0 * (q if q >= 0.05 else 0.05))
		var a0 := 1 + alpha / A
		return PackedFloat64Array([(1 + alpha * A) / a0, -2 * cw / a0, (1 - alpha * A) / a0, -2 * cw / a0, (1 - alpha / A) / a0, 0, 0, 0, 0, 0, 0, 0, 0])

	func _read(ch: int, d: float) -> float:
		var n := line_l.size()
		var pos := w - d
		while pos < 0.0:
			pos += n
		var i0 := int(pos)
		var fr := pos - i0
		var i1 := (i0 + 1) % n
		if ch == 0:
			return line_l[i0 % n] * (1.0 - fr) + line_l[i1] * fr
		return line_r[i0 % n] * (1.0 - fr) + line_r[i1] * fr

	func tick(io: PackedFloat64Array) -> void:
		match type:
			1, 2:
				var inl := io[0]
				var inr := io[1]
				var wet := PackedFloat64Array([0.0, 0.0])
				for ch in 2:
					var pp := ph + (spread * 0.25 if ch == 1 else 0.0)
					var acc := 0.0
					for v in voices:
						var lfo := sin(TAU * (pp + float(v) / voices))
						var d := (delay_ms + depth_ms * 0.5 * (1.0 + lfo)) * sr / 1000.0
						acc += _read(ch, d)
					wet[ch] = acc / voices
				var n := line_l.size()
				line_l[w] = inl + feedback * wet[0]
				line_r[w] = inr + feedback * wet[1]
				w = (w + 1) % n
				io[0] = inl * (1.0 - mix) + wet[0] * mix
				io[1] = inr * (1.0 - mix) + wet[1] * mix
				ph += rate / sr
				ph -= floorf(ph)
			3:
				for ch in 2:
					var lfo := sin(TAU * (ph + (spread * 0.25 if ch == 1 else 0.0)))
					var fc := center * pow(2.0, range_oct * 0.5 * depth * lfo)
					var nyq := 0.49 * sr
					fc = 20.0 if fc < 20.0 else (nyq if fc > nyq else fc)
					var t := tan(PI * fc / sr)
					var a := (t - 1.0) / (t + 1.0)
					var x := io[ch] + feedback * ph_last[ch]
					var zo := ch * 12
					for s in stages:
						var y := a * x + ap_z[zo + s]
						ap_z[zo + s] = x - a * y
						x = y
					ph_last[ch] = x
					io[ch] = io[ch] * (1.0 - mix) + x * mix
				ph += rate / sr
				ph -= floorf(ph)
			4:
				for b in 3:
					var q := b * 13
					for ch in 2:
						var o := q + 5 + ch * 4
						var x := io[ch]
						var y := bq[q] * x + bq[q + 1] * bq[o] + bq[q + 2] * bq[o + 1] - bq[q + 3] * bq[o + 2] - bq[q + 4] * bq[o + 3]
						bq[o + 1] = bq[o]
						bq[o] = x
						bq[o + 3] = bq[o + 2]
						bq[o + 2] = y
						io[ch] = y
			5:
				var det := absf(io[0]) if absf(io[0]) > absf(io[1]) else absf(io[1])
				var lev := 20.0 * log(det + 1e-12) / log(10.0)
				var over := lev - threshold
				var target := 0.0
				var hk := knee * 0.5
				if knee > 0.0 and over > -hk and over < hk:
					var x := over + hk
					target = -(1.0 - 1.0 / ratio) * x * x / (2.0 * knee)
				elif over >= hk:
					target = -(1.0 - 1.0 / ratio) * over
				var k := k_att if target < gr_db else k_rel
				gr_db = target + (gr_db - target) * k
				var g := pow(10.0, (gr_db + makeup) / 20.0)
				io[0] *= g
				io[1] *= g
			6:
				for ch in 2:
					var y := (tanh(io[ch] * sat_g + asym) - sat_off) * sat_out
					sat_z[ch] += sat_lp * (y - sat_z[ch])
					io[ch] = io[ch] * (1.0 - mix) + sat_z[ch] * mix
