# SPDX-License-Identifier: Apache-2.0
## Live playback through the native mixer: the same recipes and cue maps as
## the baked path, mixed at play time instead of baked to a WAV.
##
## Hits are rendered once (memoised), registered with the mixer and scheduled
## at exact frames on a timeline, so seeking keeps them. Game events can fire
## extra one-shots with `trigger()`, and `voice_start()` runs continuous
## synths whose parameters glide while they play (engines, wind, drones).
## The shared reverb send and the master chain run live too.
##
## Loudness and normalize steps in a master chain need the whole piece to
## measure: `prepare()` measures them once by rendering the scheduled
## timeline offline, then plays it with that fixed gain. Hits added later
## (triggers, voices) don't move it. Effects that can't run live (room, echo,
## drive, bitcrush in the master chain) are skipped with a warning.
##
## Needs the native core; `AKLive.available()` says whether it's built.
class_name AKLive
extends RefCounted

## The AudioStream to give an AudioStreamPlayer (an AKLiveStream).
var stream: AudioStream
## Fixed master gain (dB) each loudness/normalize step measured, in order.
var measured_db: Array[float] = []

var _cue_map: AKCueMap
var _ids := {}
var _buffers := {}
var _counts := {}
var _length_frames := 0
var _end_frame := 0


static func available() -> bool:
	return ClassDB.class_exists(&"AKLiveStream")


func _init() -> void:
	if available():
		stream = ClassDB.instantiate(&"AKLiveStream")
	else:
		push_error("AKLive: the native core isn't built (see native/README.md)")


## The mixer's position on its timeline, in frames at AK.sample_rate.
func get_frame() -> int:
	return stream.get_frame()


func seek(seconds: float) -> void:
	stream.seek_frame(roundi(seconds * AK.sample_rate))


## Set up the reverb and master chain from `cue_map`, schedule every cue (and
## the song's notes), and measure any loudness steps. Returns the placements
## like render_cues' `cues`. `length_s` is the picture length (for end_fade_s).
func prepare(cues: Array, cue_map: AKCueMap, fps := 30.0, length_s := 0.0, song: AKSong = null) -> Array:
	_cue_map = cue_map
	stream.clear()
	_counts.clear()
	var sr := AK.sample_rate
	var placed := []
	var end := roundi(length_s * sr)
	var send_end := 0
	for c: Dictionary in cues:
		if String(c.get("data", {}).get("source", "")) == "song":
			continue
		var name := String(c.get("name", ""))
		var t: float = float(c.time) if c.has("time") else float(c.get("frame", 0.0)) / fps
		var recipe := cue_map.recipe_for(StringName(name))
		if recipe == null:
			placed.append({name = name, time = t, missing = true})
			continue
		var idx: int = _counts.get(name, 0)
		_counts[name] = idx + 1
		var intensity := float(c.get("intensity", 1.0))
		var data: Dictionary = c.get("data", {})
		var id := _buffer_for(recipe, intensity, data, idx)
		var buf: AKBuffer = _buffers[id]
		var at := roundi((t + recipe.offset_s) * sr)
		stream.schedule(id, at, 1.0, 1.0, buf.send, 1)
		end = maxi(end, at + buf.frames())
		if buf.send > 0.0:
			send_end = maxi(send_end, at + buf.frames())
		placed.append({name = name, time = t, sample = at, intensity = intensity, frames = buf.frames()})
	if song:
		var r := _schedule_song(song)
		end = maxi(end, r.end)
		send_end = maxi(send_end, r.send_end)
	var rv := cue_map.reverb
	var has_send := send_end > 0
	stream.set_reverb(has_send, float(rv.get("room", 0.5)), float(rv.get("damp", 0.5)), float(rv.get("width", 1.0)),
		StringName(rv.get("quality", &"full")) == &"small", AKDsp.db_to_gain(float(rv.get("return_db", 0.0))))
	if has_send:
		var room := clampf(float(rv.get("room", 0.5)), 0.0, 1.0)
		var tail := float(rv.get("tail_s", -1.0))
		end = maxi(end, send_end + roundi((tail if tail >= 0.0 else 0.3 + 2.2 * room) * sr))
	_end_frame = end
	_length_frames = roundi(length_s * sr) if cue_map.end_fade_s > 0.0 and length_s > 0.0 else end
	_build_chain(length_s)
	return placed


## Frames the prepared piece lasts (what render_cues' mix would hold).
func length_frames() -> int:
	return _length_frames


## Fire a cue now (plus `delay_s`), outside the prepared timeline: for game
## events. Uses the cue map given to prepare() or `cue_map`.
func trigger(cue_name: StringName, intensity := 1.0, data := {}, delay_s := 0.0, cue_map: AKCueMap = null) -> void:
	var map := cue_map if cue_map else _cue_map
	var recipe := map.recipe_for(cue_name) if map else null
	if recipe == null:
		push_warning("AKLive: no recipe for cue '%s'" % cue_name)
		return
	var idx: int = _counts.get(String(cue_name), 0)
	_counts[String(cue_name)] = idx + 1
	var id := _buffer_for(recipe, intensity, data, idx)
	var buf: AKBuffer = _buffers[id]
	stream.play_now(id, 1.0, 1.0, buf.send, roundi(maxf(0.0, delay_s + recipe.offset_s) * AK.sample_rate))


## Play any AKBuffer now (gain in dB, send 0..1).
func play_buffer(buf: AKBuffer, gain_db := 0.0, send := -1.0, delay_s := 0.0) -> void:
	var id: int = stream.add_buffer(buf.l, buf.r)
	_buffers[id] = buf
	var g := AKDsp.db_to_gain(gain_db)
	stream.play_now(id, g, g, g * (send if send >= 0.0 else buf.send), roundi(delay_s * AK.sample_rate))


## Start a continuous voice. `params`: shape (sine, saw, square, triangle,
## noise), freq_hz, gain, cutoff_hz (0 = no filter), q, pan, send, width
## (square pulse width), noise (0..1 noise mixed in), attack_s, seed.
func voice_start(params: Dictionary) -> int:
	return stream.voice_start(params)


## Glide a voice parameter to `value` over roughly `glide_s`.
func voice_set(id: int, param: String, value: float, glide_s := 0.05) -> void:
	stream.voice_set(id, param, value, glide_s)


func voice_stop(id: int, release_s := 0.1) -> void:
	stream.voice_stop(id, release_s)


## Render `frames` offline from the current position (tests, previews).
func render_offline(frames: int) -> AKBuffer:
	var res: Array = stream.render_offline(frames)
	var b := AKBuffer.new(0, AK.sample_rate)
	b.l = res[0]
	b.r = res[1]
	return b


# ------------------------------------------------------------------ inside

func _buffer_for(recipe: AKRecipe, intensity: float, data: Dictionary, idx: int, ov := {}) -> int:
	var key := AK.bake_key(recipe, intensity, data, idx, ov)
	if _ids.has(key):
		return _ids[key]
	var buf := AK.render(recipe, intensity, data, idx, ov)
	var id: int = stream.add_buffer(buf.l, buf.r)
	_ids[key] = id
	_buffers[id] = buf
	return id


func _schedule_song(song: AKSong) -> Dictionary:
	var sr := AK.sample_rate
	var end := roundi(song.length_s() * sr)
	var send_end := 0
	var lane_pan := {}
	var counts := {}
	for e in song.events():
		var recipe: AKRecipe = e.recipe
		var ov := AKSong.event_overrides(e)
		var idx: int = counts.get(e.lane, 0)
		counts[e.lane] = idx + 1
		var id := _buffer_for(recipe, float(e.velocity), {}, idx, ov)
		var buf: AKBuffer = _buffers[id]
		var at := roundi((float(e.time_s) + recipe.offset_s) * sr)
		if not lane_pan.has(e.lane):
			lane_pan[e.lane] = float(e.pan)
		var pan: float = lane_pan[e.lane]
		var g := AKDsp.db_to_gain(float(e.gain_db) + song.gain_db)
		var gl := g * (1.0 - pan if pan > 0.0 else 1.0)
		var gr := g * (1.0 + pan if pan < 0.0 else 1.0)
		var send := float(e.send) if float(e.send) >= 0.0 else buf.send
		stream.schedule(id, at, gl, gr, g * send if send > 0.0 else 0.0, 2)
		end = maxi(end, at + buf.frames())
		if send > 0.0:
			send_end = maxi(send_end, at + buf.frames())
	return {end = end, send_end = send_end}


## The live master chain: end fade, then the cue map's master_fx with each
## loudness/normalize step measured offline into a fixed gain.
func _build_chain(length_s: float) -> void:
	var sr := AK.sample_rate
	var steps := []
	if _cue_map.end_fade_s > 0.0 and length_s > 0.0:
		var e := roundi(length_s * sr)
		steps.append({type = "fade_end", start = maxi(0, e - roundi(_cue_map.end_fade_s * sr)), end = e})
	measured_db.clear()
	for fx: Dictionary in _cue_map.master_fx:
		var type := StringName(fx.get("type", &""))
		match type:
			&"dcblock":
				steps.append({type = "highpass1", cutoff_hz = float(fx.get("cutoff_hz", 10.0))})
			&"highpass1", &"lowpass1":
				steps.append({type = String(type), cutoff_hz = float(fx.get("cutoff_hz", 100.0 if type == &"highpass1" else 1000.0))})
			&"lowpass", &"highpass", &"bandpass", &"notch":
				var mode: int = {&"lowpass": 0, &"highpass": 1, &"bandpass": 2, &"notch": 3}[type]
				steps.append({type = "svf", mode = mode, cutoff_hz = float(fx.get("cutoff_hz", 1000.0)), q = float(fx.get("q", 0.707)),
					stages = 2 if float(fx.get("slope_db", 12.0)) >= 24.0 else 1})
			&"gain":
				steps.append({type = "gain", gain = AKDsp.db_to_gain(float(fx.get("db", 0.0)))})
			&"limit":
				var rel := float(fx.get("release_s", 0.08))
				steps.append({type = "limit", ceiling = AKDsp.db_to_gain(float(fx.get("ceiling_db", -1.0))),
					release_k = exp(-1.0 / maxf(1e-4, rel * sr))})
			&"loudness", &"normalize":
				var probe := _measure(steps)
				var db := 0.0
				if type == &"loudness":
					var now := AKDynamics.lufs(probe)
					db = float(fx.get("target_lufs", -16.0)) - now if is_finite(now) else 0.0
				else:
					var p := probe.peak()
					db = float(fx.get("peak_db", -1.0)) - linear_to_db(p) if p > 0.0 else 0.0
				measured_db.append(db)
				steps.append({type = "gain", gain = AKDsp.db_to_gain(db)})
			_:
				push_warning("AKLive: master effect '%s' can't run live; skipped" % type)
	stream.set_chain(steps)
	stream.seek_frame(0)


func _measure(steps: Array) -> AKBuffer:
	stream.set_chain(steps)
	stream.seek_frame(0)
	return render_offline(_length_frames)
