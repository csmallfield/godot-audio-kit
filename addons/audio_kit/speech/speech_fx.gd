# SPDX-License-Identifier: Apache-2.0
@tool
## Character effects for pseudo-speech voices: the presets the Pseudo-Speech
## page offers (a demon, an angel, an alien ...) and how a voice's
## `effects`, `effects_amount` and `size_semitones` become one effect chain.
##
##   AKSpeechFx.apply(voice, "demon")    # its effects and size, amount kept
##   AKSpeechFx.preset_of(voice)         # "demon", "" (none) or "custom"
##
## A preset is a starting point: its effects land in the voice's `effects`,
## where the Inspector edits them like any patch effect (AKStreamFx specs).
class_name AKSpeechFx
extends RefCounted

## The size shift's window: short enough to keep syllables crisp.
const SIZE_WINDOW_MS := 40.0
## Effects change a voice's character, not its level: a chain ends with
## make-up gain (within this many dB) so a reference phrase comes out as loud
## as it went in.
const MAX_MAKEUP_DB := 12.0

static var _makeup := {}
static var _reference: AKBuffer

## name -> {size, effects, tip}. `size` is the voice's size_semitones (up =
## bigger, lower formants).
const PRESETS := {
	"demon": {size = 3.0, tip = "An octave-down double, a growl, grit and a dark hall.", effects = [
		{type = "pitch", semitones = -12.0, window_ms = 70.0, mix = 0.45},
		{type = "growl", rate_hz = 38.0, depth = 0.45, jitter = 0.6, mix = 1.0},
		{type = "saturate", drive_db = 10.0, tone_hz = 3000.0, mix = 0.45},
		{type = "eq", low_db = 4.0, low_hz = 150.0, high_db = -5.0, high_hz = 5000.0},
		{type = "reverb", room = 0.85, damp = 0.7, mix = 0.3}]},
	"angel": {size = -1.0, tip = "A shimmering choir: three-voice chorus, an octave up, a bright long hall.", effects = [
		{type = "chorus", rate_hz = 0.3, depth_ms = 4.0, delay_ms = 15.0, voices = 3, mix = 0.45},
		{type = "pitch", semitones = 12.0, window_ms = 40.0, mix = 0.18},
		{type = "eq", low_db = -3.0, low_hz = 200.0, high_db = 4.0, high_hz = 6000.0},
		{type = "reverb", room = 0.86, damp = 0.15, mix = 0.4}]},
	"alien": {size = 0.0, tip = "A swept ring modulator, a deep phaser, a short echo, a few lost bits.", effects = [
		{type = "ring", freq_hz = 330.0, rate_hz = 0.35, depth = 0.6, mix = 0.55},
		{type = "phaser", rate_hz = 0.7, stages = 6, feedback = 0.6, mix = 0.5},
		{type = "delay", time_ms = 140.0, feedback = 0.3, mix = 0.2},
		{type = "crush", bits = 10.0, hold = 1, mix = 0.3}]},
	"beast": {size = 5.0, tip = "A big body, a ragged growl, grit and a fifth below.", effects = [
		{type = "growl", rate_hz = 55.0, depth = 0.65, jitter = 0.8, mix = 1.0},
		{type = "saturate", drive_db = 14.0, tone_hz = 2500.0, mix = 0.6},
		{type = "pitch", semitones = -7.0, window_ms = 60.0, mix = 0.3},
		{type = "reverb", room = 0.4, damp = 0.6, mix = 0.12}]},
	"sprite": {size = -5.0, tip = "A tiny body with a quick warble and a little echo.", effects = [
		{type = "chorus", rate_hz = 6.5, depth_ms = 0.8, delay_ms = 2.0, voices = 1, mix = 1.0},
		{type = "eq", low_db = -6.0, low_hz = 250.0, high_db = 3.0, high_hz = 5000.0},
		{type = "delay", time_ms = 90.0, feedback = 0.2, mix = 0.15}]},
	"ghost": {size = 0.0, tip = "Thin and far away: a faint octave up, flanging, long echoes, a huge room.", effects = [
		{type = "pitch", semitones = 12.0, window_ms = 50.0, mix = 0.15},
		{type = "flanger", rate_hz = 0.15, feedback = 0.7, mix = 0.5},
		{type = "eq", low_db = -8.0, low_hz = 300.0},
		{type = "delay", time_ms = 320.0, feedback = 0.5, damp_hz = 2500.0, mix = 0.35},
		{type = "reverb", room = 0.86, damp = 0.4, mix = 0.45}]},
	"robot": {size = 0.0, tip = "A low ring modulator, crushed and held samples, a tin can.", effects = [
		{type = "ring", freq_hz = 95.0, mix = 0.7},
		{type = "crush", bits = 7.0, hold = 2, mix = 0.6},
		{type = "eq", mid_db = 6.0, mid_hz = 1200.0, mid_q = 1.5, low_db = -6.0, low_hz = 200.0},
		{type = "reverb", room = 0.2, damp = 0.3, mix = 0.1}]},
	"radio": {size = 0.0, tip = "A narrow, crunchy, squashed band, like a walkie-talkie.", effects = [
		{type = "eq", low_db = -18.0, low_hz = 450.0, mid_db = 6.0, mid_hz = 1600.0, mid_q = 1.0, high_db = -14.0, high_hz = 3500.0},
		{type = "saturate", drive_db = 16.0, tone_hz = 4000.0, mix = 0.7},
		{type = "crush", bits = 9.0, hold = 2, mix = 0.4},
		{type = "compressor", threshold_db = -24.0, ratio = 6.0, makeup_db = 6.0}]},
}


## The names, in menu order.
static func names() -> Array[String]:
	var out: Array[String] = []
	for k: String in PRESETS:
		out.append(k)
	return out


## Give `voice` a preset's effects and size ("" or "none" clears both).
## The amount stays as it is.
static func apply(voice: AKSpeechVoice, preset: String) -> void:
	var p: Dictionary = PRESETS.get(preset, {})
	voice.effects.assign((p.get("effects", []) as Array).duplicate(true))
	voice.size_semitones = float(p.get("size", 0.0))


## Which preset `voice` carries: its name, "" for none, "custom" otherwise.
static func preset_of(voice: AKSpeechVoice) -> String:
	if voice.effects.is_empty() and is_zero_approx(voice.size_semitones):
		return ""
	for k: String in PRESETS:
		var fx: Array = PRESETS[k].effects
		if not is_equal_approx(float(PRESETS[k].size), voice.size_semitones) or fx.size() != voice.effects.size():
			continue
		var same := true
		for i in fx.size():
			same = same and fx[i] == voice.effects[i]
		if same:
			return k
	return "custom"


## The chain a voice's line goes through: the size shift (sung `size` up, so
## shifted that far down at full mix), then `effects` scaled by `amount`.
static func chain(effects: Array[Dictionary], amount: float, size := 0.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not is_zero_approx(size):
		out.append({type = "pitch", semitones = -size, window_ms = SIZE_WINDOW_MS, mix = 1.0})
	if amount > 0.0:
		for e in effects:
			out.append(scaled(e, amount))
	if out.is_empty():
		return out
	var db := makeup_db(out)
	if absf(db) > 0.05:
		# A compressor at ratio 1 is a plain gain of its make-up.
		out.append({type = "compressor", threshold_db = 0.0, ratio = 1.0, knee_db = 0.0, makeup_db = db})
	return out


## The gain that brings `chain`'s output back to its input's loudness, on a
## reference phrase (a buzzy voice-like tone in syllables). Cached per chain.
static func makeup_db(chain: Array[Dictionary]) -> float:
	var key := var_to_str(chain).hash()
	if _makeup.has(key):
		return _makeup[key]
	var ref := _reference_phrase()
	var lr := AKStreamFx.process(chain, ref.l, ref.r, ref.sample_rate)
	var wet := _power(lr[0]) + _power(lr[1])
	var dry := _power(ref.l) + _power(ref.r)
	var db := 0.0
	if wet > 1e-12:
		db = clampf(10.0 * log(dry / wet) / log(10.0), -MAX_MAKEUP_DB, MAX_MAKEUP_DB)
	_makeup[key] = db
	return db


# Power heard: below a few hundred Hz counts less (a one-pole high-pass, as
# loudness weighting does), so a bass boost doesn't read as much louder.
static func _power(x: PackedFloat32Array) -> float:
	var k := exp(-TAU * 300.0 / AK.sample_rate)
	var s := 0.0
	var prev := 0.0
	var y := 0.0
	for v in x:
		y = k * (y + v - prev)
		prev = v
		s += y * y
	return s


# Six syllables of a 180 Hz buzz with a gliding vowel-like peak, then a
# second of quiet for tails to ring into.
static func _reference_phrase() -> AKBuffer:
	if _reference:
		return _copy(_reference)
	var sr := AK.sample_rate
	var b := AKBuffer.new(roundi(2.2 * sr), sr)
	var ph := 0.0
	var lp := 0.0
	for i in roundi(1.2 * sr):
		var t := float(i) / sr
		var syl := fmod(t, 0.2)
		var env := 0.0 if syl > 0.16 else sin(PI * syl / 0.16)
		ph = fmod(ph + (180.0 + 30.0 * sin(TAU * 0.8 * t)) / sr, 1.0)
		var k := 1.0 - exp(-TAU * (700.0 + 900.0 * (0.5 + 0.5 * sin(TAU * 2.5 * t))) / sr)
		lp += k * ((2.0 * ph - 1.0) - lp)
		b.l[i] = 0.5 * env * lp
		b.r[i] = b.l[i]
	_reference = b
	return _copy(b)


static func _copy(b: AKBuffer) -> AKBuffer:
	var c := AKBuffer.new(0, b.sample_rate)
	c.l = b.l.duplicate()
	c.r = b.r.duplicate()
	return c


## One effect at `amount` (0..1): its mix scaled, or for an EQ its gains.
static func scaled(e: Dictionary, amount: float) -> Dictionary:
	var d := e.duplicate()
	if is_equal_approx(amount, 1.0):
		return d
	var t := String(e.get("type", ""))
	var defaults: Dictionary = AKStreamFx.DEFAULTS.get(t, {})
	if defaults.has("mix"):
		d.mix = float(e.get("mix", defaults.mix)) * amount
	if t == "eq":
		for k in ["low_db", "mid_db", "high_db"]:
			d[k] = float(e.get(k, 0.0)) * amount
	return d
