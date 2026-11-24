# SPDX-License-Identifier: Apache-2.0
@tool
extends AKVoice
## An AKSample played at a pitch, so a recipe layer (and so a loop, a kit
## piece, a song lane, a cue) can play a sample:
##   {voice = &"sample", params = {sample = "res://audio/samples/kick.sample.tres", freq_hz = 110.0}}
##
## Velocity layers and round-robin (how a drum kit piece plays a sound
## recorded at several strengths, several times each):
##   params = {sample = snare_soft, layers = [
##       {sample = snare_soft, up_to = 0.4},
##       {sample = [snare_hard_1, snare_hard_2, snare_hard_3], up_to = 1.0}]}
## A hit plays the first layer whose `up_to` reaches its velocity (the last
## layer above them all). A layer (or `sample` itself) given as an array is
## a set of alternate takes, picked by `hit` modulo their count: a recipe's
## `round_robin` sets `hit` hit by hit. Every take plays with the pitch shift
## `freq_hz` gives `sample` (each from its own root), and velocity still
## scales its level. A stereo sample plays in stereo (`render_stereo`).


func version() -> int:
	return 1


func doc() -> String:
	return "Plays an AKSample (a sound file or a recipe) at a pitch: resampled by 2^((note - root) / 12) with 4-point interpolation, one-shot, gated or looped, in stereo when the sample is; optional velocity layers and round-robin takes."


func schema() -> Dictionary:
	return {
		sample = param("", null, null, "The AKSample, or its res:// path, or an array of alternate takes; empty plays a soft mallet at C4"),
		freq_hz = param(261.63, 8.0, 12000.0, "Pitch to play (the sample's root pitch plays it as made; the sequencer retunes it)"),
		velocity = param(1.0, 0.0, 1.0, "Level of the note, and which velocity layer plays"),
		gate_s = param(0.3, 0.0, 30.0, "How long the note is held (gate and loop modes)"),
		length_s = param(0.0, 0.0, 30.0, "Total length; 0 = to the sample's end (one-shot) or the gate plus five release times"),
		layers = param([], null, null, "Velocity layers: [{sample (an AKSample, path or array of takes), up_to (top velocity, 0..1)}]; empty plays `sample`"),
		hit = param(0, 0, 1000000, "Which alternate take plays (modulo their count); a recipe's round_robin sets it per hit"),
	}


func render(p: Dictionary, sr: int, _rng: RandomNumberGenerator) -> PackedFloat32Array:
	var got := _pick(p)
	if got.is_empty():
		return PackedFloat32Array()
	var s: AKSample = got[0]
	if s.is_stereo():
		var lr := _play(s, p, sr, got[1], true)
		if lr.size() == 2:
			var l: PackedFloat32Array = lr[0]
			var r: PackedFloat32Array = lr[1]
			var m := PackedFloat32Array()
			m.resize(l.size())
			for i in l.size():
				m[i] = 0.5 * (l[i] + r[i])
			return m
		return PackedFloat32Array()
	var x := _play(s, p, sr, got[1], false)
	return x[0] if x.size() > 0 else PackedFloat32Array()


func render_stereo(p: Dictionary, sr: int, _rng: RandomNumberGenerator) -> Array:
	var got := _pick(p)
	if got.is_empty():
		return []
	var s: AKSample = got[0]
	if not s.is_stereo():
		return []
	return _play(s, p, sr, got[1], true)


## The take a hit plays and the pitch ratio it plays at: [AKSample, ratio],
## or [] when there's nothing to play.
func _pick(p: Dictionary) -> Array:
	var layers: Array = p.get("layers", []) if p.get("layers", []) is Array else []
	var base_v: Variant = p.get("sample", "")
	if (base_v == null or (base_v is String and String(base_v) == "")) and not layers.is_empty():
		base_v = (layers[0] as Dictionary).get("sample", "")
	var hit := int(p.get("hit", 0))
	var base := _take(base_v, 0)
	if base == null:
		return []
	var chosen := base
	if not layers.is_empty():
		var vel := float(p.get("velocity", 1.0))
		var pick: Dictionary = layers[layers.size() - 1]
		var best := INF
		for l: Dictionary in layers:
			var top := float(l.get("up_to", 1.0))
			if vel <= top + 1e-6 and top < best:
				best = top
				pick = l
		chosen = _take(pick.get("sample", ""), hit)
		if chosen == null:
			return []
	elif base_v is Array:
		chosen = _take(base_v, hit)
	return [chosen, float(p.freq_hz) / base.root_hz()]


## One of a set of takes (or the one sample), by `hit`.
func _take(v: Variant, hit: int) -> AKSample:
	if v is Array:
		var a: Array = v
		if a.is_empty():
			return null
		return resolve(a[posmod(hit, a.size())])
	return resolve(v)


## The sample played: [mono] or, when `stereo`, [left, right]; [] for
## nothing to play.
func _play(s: AKSample, p: Dictionary, sr: int, ratio: float, stereo: bool) -> Array:
	var chans: Array = []
	var src_rate: int
	if stereo:
		var got: Array = s.stereo_samples()
		chans = [got[0], got[1]]
		src_rate = got[2]
	else:
		var got: Array = s.samples()
		chans = [got[0]]
		src_rate = got[1]
	var size := (chans[0] as PackedFloat32Array).size()
	var fr := s.frames_at(src_rate, size)
	var start: int = fr.start
	var end: int = fr.end
	if s.reverse:
		for c in chans.size():
			var rev: PackedFloat32Array = (chans[c] as PackedFloat32Array).slice(start, end)
			rev.reverse()
			chans[c] = rev
		end = end - start
		start = 0
	var rate := ratio * float(src_rate) / float(sr)
	if rate <= 0.0 or end <= start:
		return []
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
	var env := PackedFloat32Array()
	if s.mode != "oneshot":
		env = AKEnv.adsr(n, sr, 0.0, 0.0, 1.0, s.release_s, gate)
	var level := float(p.velocity) * AKDsp.db_to_gain(s.gain_db)
	var out := []
	for c in chans:
		var x := AKSampler.play(c, rate, n, start, end, start + int(fr.loop_start), start + int(fr.loop_end), looping)
		if s.mode != "oneshot":
			x = AKDsp.mul(x, env)
		out.append(AKDsp.scale(x, level))
	return out


## The samples' content, so editing a sample saved in its own file re-bakes.
func key_extra(params: Dictionary) -> Variant:
	var paths := []
	_paths(params.get("sample", ""), paths)
	var layers: Variant = params.get("layers", [])
	if layers is Array:
		for l: Variant in layers:
			if l is Dictionary:
				_paths((l as Dictionary).get("sample", ""), paths)
	if paths.is_empty():
		return null
	if paths.size() == 1 and (params.get("sample", "") is String or params.get("sample", "") is StringName):
		var s := resolve(paths[0])
		return s.describe() if s else null   # one path, as before: older bake keys hold
	var out := []
	for path: String in paths:
		var s := resolve(path)
		out.append(s.describe() if s else null)
	return out


static func _paths(v: Variant, into: Array) -> void:
	if v is Array:
		for x: Variant in v:
			_paths(x, into)
	elif (v is String or v is StringName) and String(v) != "" and ResourceLoader.exists(String(v)):
		into.append(String(v))


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
