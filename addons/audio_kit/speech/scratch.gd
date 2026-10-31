# SPDX-License-Identifier: Apache-2.0
@tool
## Pseudo-speech through a record: the Scratch King's voice (Katamari
## Damacy's King speaks in record scratches). Each syllable scrubs one of the
## voice's sustained vowel sounds (AKSpeechVoice.scratch_samples) like a DJ
## moving a record under the needle:
##
##   - the record is picked by the syllable's vowel (bright i .. dark u), so
##     the formant comes from what's on the record
##   - the playback rate follows the pitch curve (rate 1 = the record's root
##     note), times the hand's speed: from rest, fast in the middle, to rest
##     again (`scratch_wobble`), which gives the scratch its warble
##   - an accented syllable ends with a back stroke (`scratch_back`): the
##     record pulled backwards, the "wika" of a baby scratch
##   - where the needle lands in the record comes from the syllable's seed, so
##     a word scratches the same groove every time it's said
##   - a crossfader cut opens and closes each syllable (`scratch_cut_s`); the
##     intensity curve sets its level, and brightness and formant together
##     open a low-pass (bright vowels and accents sound brighter)
##
## Deterministic, GDScript only (a few hundred ms for a line).
class_name AKSpeechScratch
extends RefCounted

## How fast a back stroke moves, relative to the forward one.
const BACK_SPEED := 0.85
## Skip the record's attack: needles land in the sustained part.
const SKIP_S := 0.06
## Room kept after the landing point for a stroke to run (longer ones stop
## at the record's end).
const TRAVEL_S := 0.45
## Control values (pitch, level, cutoff) are read every this many samples.
const BLOCK := 16


## The hand's speed at `v` (0..1 through a stroke): mean 1 over the stroke,
## from (1 - wobble) at the ends to 1 + wobble (pi/2 - 1) in the middle.
static func head_speed(v: float, wobble: float) -> float:
	return (1.0 - wobble) + wobble * 0.5 * PI * sin(PI * clampf(v, 0.0, 1.0))


## One stroke plan per syllable: {on, off, back_at (= off when there is no
## back stroke), record (index into the voice's records), pos0 (where the
## needle lands, in the record's frames)}. Empty when the voice has no records.
static func plan(line: AKSpeechLine) -> Array[Dictionary]:
	line.compile()
	var out: Array[Dictionary] = []
	var v := line.voice
	var recs := _records(v)
	if recs.is_empty():
		return out
	for e in line.events:
		var start := float(e.t_start)
		var span := float(e.t_end) - start
		var on := start + minf(v.lead_for(int(e.onset_class)), 0.5 * span)
		var off := maxf(on + 0.02, start + span * v.gate)
		var seed := int(e.seed)
		var back_at := off
		if v.scratch_back > 0.0 and float(e.stress) >= v.scratch_back_stress:
			back_at = off - (off - on) * v.scratch_back * (0.8 + 0.4 * _unit(seed, 3))
		var ri := clampi(int(e.vowel) * recs.size() / 5, 0, recs.size() - 1)
		var r: Dictionary = recs[ri]
		var rate := float(r.rate)
		# The landing depends only on the seed and the record, never on this
		# occurrence's pitch or length, so a word lands in the same groove.
		var lo := float(r.a) + SKIP_S * rate
		var room := maxf(0.0, float(r.b) - 4.0 - TRAVEL_S * rate - lo)
		out.append({on = on, off = off, back_at = back_at, record = ri, pos0 = lo + room * _unit(seed, 9)})
	return out


## The line scratched: a stereo AKBuffer (mono in both channels), before the
## voice's onsets and gain (AKSpeech.render adds those).
static func render(line: AKSpeechLine, sr: int) -> AKBuffer:
	var v := line.voice
	var recs := _records(v)
	var strokes := plan(line)
	if recs.is_empty() or strokes.is_empty():
		return AKBuffer.new(0, sr)
	var out := PackedFloat32Array()
	out.resize(roundi((line.duration + 0.05) * sr) + 1)
	out.fill(0.0)
	var w := v.scratch_wobble
	var cut := maxf(0.0005, v.scratch_cut_s)
	for st in strokes:
		var r: Dictionary = recs[int(st.record)]
		var data: PackedFloat32Array = r.data
		var a := int(r.a)
		var b := int(r.b)
		var src_rate := float(r.rate)
		var root := float(r.root)
		var gain := float(r.gain)
		var on := float(st.on)
		var off := float(st.off)
		var back_at := float(st.back_at)
		var fwd_len := maxf(1e-4, back_at - on)
		var back_len := maxf(1e-4, off - back_at)
		var pos := float(st.pos0)
		var y := 0.0
		var step := 0.0
		var level := 0.0
		var coef := 1.0
		var n0 := roundi(on * sr)
		var n1 := mini(roundi(off * sr), out.size())
		for n in range(n0, n1):
			var t := float(n) / sr
			if (n - n0) % BLOCK == 0:
				var note := v.sung_note() + line.curve_at("pitch", t)
				step = pow(2.0, (note - root) / 12.0) * src_rate / sr
				level = line.curve_at("intensity", t)
				var fc := 900.0 * pow(2.0, 2.5 * clampf(line.curve_at("brightness", t), 0.0, 1.0)
					+ 1.5 * clampf(line.curve_at("formant", t), 0.0, 1.0))
				coef = 1.0 - exp(-TAU * minf(fc, 0.45 * sr) / sr)
			var speed: float
			if t < back_at:
				speed = head_speed((t - on) / fwd_len, w)
			else:
				speed = -BACK_SPEED * head_speed((t - back_at) / back_len, w)
			var x := _read(data, pos, a, b)
			pos += step * speed
			# The record's edges stop the needle (it can't run off the record).
			pos = clampf(pos, float(a) + 1.0, float(b) - 3.0)
			y += coef * (x - y)
			var fade := minf(1.0, minf((t - on) / cut, (off - t) / cut))
			out[n] += y * maxf(0.0, fade) * level * gain
	var buf := AKBuffer.new(0, sr)
	buf.l = out
	buf.r = out.duplicate()
	return buf


# ------------------------------------------------------------------ inside

## The voice's records as {data, rate, a, b (trimmed frames), root, gain}.
static func _records(v: AKSpeechVoice) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if v == null:
		return out
	for smp in v.scratch_samples:
		if smp == null:
			continue
		var sm := smp.samples()
		var data: PackedFloat32Array = sm[0]
		if data.size() < 8:
			continue
		var fr := smp.frames_at(int(sm[1]), data.size())
		out.append({data = data, rate = int(sm[1]), a = int(fr.start), b = int(fr.end), root = smp.root_note,
			gain = db_to_linear(smp.gain_db)})
	return out


## 4-point Hermite read at a fractional frame, inside [a, b).
static func _read(d: PackedFloat32Array, pos: float, a: int, b: int) -> float:
	var i := int(floor(pos))
	var f := pos - i
	var xm1 := d[clampi(i - 1, a, b - 1)]
	var x0 := d[clampi(i, a, b - 1)]
	var x1 := d[clampi(i + 1, a, b - 1)]
	var x2 := d[clampi(i + 2, a, b - 1)]
	var c1 := 0.5 * (x1 - xm1)
	var c2 := xm1 - 2.5 * x0 + 2.0 * x1 - 0.5 * x2
	var c3 := 0.5 * (x2 - xm1) + 1.5 * (x0 - x1)
	return ((c3 * f + c2) * f + c1) * f + x0


static func _unit(seed: int, salt: int) -> float:
	return float(AKSpeechText.mix(seed, salt, 13)) / float(0x7FFFFFFF)
