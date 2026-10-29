# SPDX-License-Identifier: Apache-2.0
@tool
extends AKVoice
## An AKSample played at a pitch, so a recipe layer (and so a loop, a kit
## piece, a song lane, a cue) can play a sample:
##   {voice = &"sample", params = {sample = "res://audio/samples/kick.sample.tres", freq_hz = 110.0}}


func version() -> int:
	return 1


func doc() -> String:
	return "Plays an AKSample (a sound file or a recipe) at a pitch: resampled by 2^((note - root) / 12) with 4-point interpolation, one-shot, gated or looped."


func schema() -> Dictionary:
	return {
		sample = param("", null, null, "The AKSample, or its res:// path; empty plays a soft mallet at C4"),
		freq_hz = param(261.63, 8.0, 12000.0, "Pitch to play (the sample's root pitch plays it as made; the sequencer retunes it)"),
		velocity = param(1.0, 0.0, 1.0, "Level of the note"),
		gate_s = param(0.3, 0.0, 30.0, "How long the note is held (gate and loop modes)"),
		length_s = param(0.0, 0.0, 30.0, "Total length; 0 = to the sample's end (one-shot) or the gate plus five release times"),
	}


func render(p: Dictionary, sr: int, _rng: RandomNumberGenerator) -> PackedFloat32Array:
	var s := resolve(p.sample)
	if s == null:
		return PackedFloat32Array()
	var got: Array = s.samples()
	var src: PackedFloat32Array = got[0]
	var src_rate: int = got[1]
	var fr := s.frames_at(src_rate, src.size())
	var start: int = fr.start
	var end: int = fr.end
	if s.reverse:
		src = src.slice(start, end)
		src.reverse()
		end = end - start
		start = 0
	var rate := float(p.freq_hz) / s.root_hz() * float(src_rate) / float(sr)
	if rate <= 0.0 or end <= start:
		return PackedFloat32Array()
	var looping := s.mode == "loop" and int(fr.loop_end) - int(fr.loop_start) >= 2
	var gate := float(p.gate_s)
	var n: int
	if float(p.length_s) > 0.0:
		n = AKDsp.samples(float(p.length_s), sr)
	elif s.mode == "oneshot":
		n = ceili((end - start) / rate)
	else:
		n = AKDsp.samples(gate + 5.0 * s.release_s, sr)
		if not looping:
			n = mini(n, ceili((end - start) / rate))
	var x := AKSampler.play(src, rate, n, start, end, start + int(fr.loop_start), start + int(fr.loop_end), looping)
	if s.mode != "oneshot":
		x = AKDsp.mul(x, AKEnv.adsr(n, sr, 0.0, 0.0, 1.0, s.release_s, gate))
	return AKDsp.scale(x, float(p.velocity) * AKDsp.db_to_gain(s.gain_db))


## The sample's content, so editing a sample saved in its own file re-bakes.
func key_extra(params: Dictionary) -> Variant:
	var v: Variant = params.get("sample", "")
	if (v is String or v is StringName) and String(v) != "" and ResourceLoader.exists(String(v)):
		var s := resolve(v)
		return s.describe() if s else null
	return null


static var _default: AKSample


## An AKSample from a resource or a path; nothing gives the default sample.
static func resolve(v: Variant) -> AKSample:
	if v is AKSample:
		return v
	if v == null or ((v is String or v is StringName) and String(v) == ""):
		if _default == null:
			_default = AKSample.default_sample()
		return _default
	if (v is String or v is StringName) and ResourceLoader.exists(String(v)):
		var r: Resource = load(String(v))
		if r is AKSample:
			return r
	push_error("AK sample voice: '%s' is not an AKSample" % [v])
	return null
