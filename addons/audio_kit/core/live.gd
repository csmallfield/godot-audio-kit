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
## (triggers, voices) don't move it. Every other master effect runs live.
##
## Needs the native core; `AKLive.available()` says whether it's built.
class_name AKLive
extends RefCounted

## Effects, triggers and voices play on bus 0; each song lane gets its own
## bus (`lane_bus()`), so lanes have faders and duck under the effects.
const FX_BUS := 0
const _FIRST_LANE_BUS := 16

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
var _lane_buses := {}
var _probe_song: AKSong

## Live sequencer: how far ahead (seconds) update() renders and schedules
## song notes. Edits and section changes land after at most this long when
## quantized to "now"; bar and section changes land exactly on the boundary
## as long as it's further away than this.
var lookahead_s := 0.5
## Emitted when the live sequencer starts a section (`frame` on the timeline).
signal section_started(section_name: String, frame: int)
## Emitted when the live sequencer reaches the end with nothing to follow.
signal song_finished()

const _SONG_TAG := 3
var _seq_song: AKSong
var _seq_follow := &"song"
var _seq_origin := 0
var _seq_until := 0
var _seq_inst: Dictionary = {}
var _seq_queue := -1
var _seq_takes := {}
var _seq_counts := {}
var _seq_pan := {}
var _seq_layout := []


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
##
## `live_song`: sequence the song's notes as they play (song_play) instead of
## scheduling them all now, so it can be edited, queued and looped while it
## plays. Loudness is still measured with the song in.
func prepare(cues: Array, cue_map: AKCueMap, fps := 30.0, length_s := 0.0, song: AKSong = null, live_song := false) -> Array:
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
	_probe_song = song if live_song else null
	_seq_song = null
	if song:
		var r := _schedule_song(song, live_song)
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
	_apply_duck()
	_length_frames = roundi(length_s * sr) if cue_map.end_fade_s > 0.0 and length_s > 0.0 else end
	_length_frames += AK.master_tail_frames(cue_map.master_fx, sr)
	_build_chain(length_s)
	if _probe_song:
		song_play(_probe_song)
	return placed


## Frames the prepared piece lasts (what render_cues' mix would hold).
func length_frames() -> int:
	return _length_frames


## The bus a song lane plays on.
func lane_bus(lane: Variant) -> int:
	lane = StringName(lane)
	if not _lane_buses.has(lane):
		_lane_buses[lane] = _FIRST_LANE_BUS + _lane_buses.size()
		_apply_duck()
	return _lane_buses[lane]


## Fade a song lane to `db` over about `glide_s` (0 = at once).
func set_lane_gain(lane: StringName, db: float, glide_s := 0.1) -> void:
	set_bus_gain(lane_bus(lane), db, glide_s)


## Fade a bus (FX_BUS or a lane bus) to `db`.
func set_bus_gain(bus: int, db: float, glide_s := 0.1) -> void:
	stream.set_bus_gain(bus, AKDsp.db_to_gain(db), glide_s)


func _apply_duck() -> void:
	var dk := _cue_map.duck_settings() if _cue_map else {}
	for lane in _lane_buses:
		if dk.is_empty():
			stream.set_bus_duck(_lane_buses[lane], -1, 0.0, 1.0, 0.01, 0.3)
		else:
			stream.set_bus_duck(_lane_buses[lane], FX_BUS, dk.depth_db, AKDsp.db_to_gain(dk.full_at_db), dk.attack_s, dk.release_s)


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


## Render `frames` offline with update() between chunks, as playback runs
## the sequencer: what a listener would hear, for tests and reviews.
func render_playing(frames: int, chunk_s := 0.02) -> AKBuffer:
	var out := AKBuffer.new(0, AK.sample_rate)
	var chunk := maxi(64, roundi(chunk_s * AK.sample_rate))
	while out.frames() < frames:
		update()
		var part := render_offline(mini(chunk, frames - out.frames()))
		out.l.append_array(part.l)
		out.r.append_array(part.r)
	return out


# ------------------------------------------------------------------ live sequencer

## Play `song` on the timeline, its notes rendered as they come up rather
## than all at prepare(). Call update() regularly (AKLivePlayer and the bridge
## do, every frame). `follow`: "song" plays sections in order and stops,
## "loop" repeats the current section until song_queue() moves on.
## `section` starts there instead of the top; `delay_s` from now.
func song_play(song: AKSong, follow: StringName = &"song", section := "", delay_s := 0.0) -> void:
	song_stop()
	_seq_song = song
	_seq_follow = follow
	_seq_layout = song.layout()
	_seq_takes.clear()
	_seq_counts.clear()
	_seq_pan.clear()
	_seq_queue = -1
	var now: int = stream.get_frame() + roundi(maxf(0.0, delay_s) * AK.sample_rate)
	_seq_origin = now
	var si := maxi(0, song.section_index(section)) if section != "" else 0
	if _seq_layout.is_empty():
		return
	# Starting at the top keeps song time exactly (shift 0), so a straight
	# play-through places every note where prepare() would.
	var shift := 0.0 if si == 0 else -float(_seq_layout[si].start_s)
	_start_instance(si, shift, now)
	update()


## Jump a straight play-through to song time `t_s` (after a seek). Notes
## already scheduled are dropped and those from `t_s` on are rescheduled;
## notes that started before `t_s` don't resume.
func song_seek(t_s: float) -> void:
	if _seq_song == null:
		return
	stream.cancel(_SONG_TAG)
	_seq_queue = -1
	var si := _seq_layout.size() - 1
	for i in _seq_layout.size():
		if t_s < float(_seq_layout[i].end_s):
			si = i
			break
	if si < 0 or t_s >= float(_seq_layout[-1].end_s):
		_seq_inst = {}
		return
	var now := _seq_origin + roundi(t_s * AK.sample_rate)
	_start_instance(si, 0.0, _seq_origin + roundi(float(_seq_layout[si].start_s) * AK.sample_rate))
	while _seq_inst.next < _seq_inst.events.size() and int(_seq_inst.events[_seq_inst.next].t_f) < now:
		_seq_inst.next += 1
	_seq_until = now
	update()


## Change section at the next `quantize` boundary: "now", "beat", "bar" or
## "section" (when the current one ends).
func song_queue(section_name: String, quantize: StringName = &"bar") -> void:
	if _seq_song == null:
		return
	var si := _seq_song.section_index(section_name)
	if si < 0:
		push_warning("AKLive: no section '%s'" % section_name)
		return
	if _seq_inst.is_empty():
		var now: int = stream.get_frame()
		_start_instance(si, float(now - _seq_origin) / AK.sample_rate - float(_seq_layout[si].start_s), now)
		update()
		return
	var b := _boundary(quantize)
	_seq_queue = si
	if b < int(_seq_inst.end_f):
		_seq_inst.end_f = b
		stream.cancel_after(_SONG_TAG, b)
		_seq_until = mini(_seq_until, b)
	update()


## Stop the song at a boundary ("now", "beat", "bar", "section"); notes
## already sounding ring out.
func song_stop(quantize: StringName = &"now") -> void:
	if _seq_song == null or _seq_inst.is_empty():
		_seq_inst = {}
		return
	var b := _boundary(quantize)
	stream.cancel_after(_SONG_TAG, b)
	_seq_inst.end_f = b
	_seq_until = mini(_seq_until, b)
	_seq_follow = &"stop"
	_seq_queue = -1


## The song was edited (patterns, mutes, automation, mix): re-derive the
## notes not yet sounding. The section in progress keeps its place.
func song_changed() -> void:
	if _seq_song == null or _seq_inst.is_empty():
		return
	var now: int = stream.get_frame()
	_seq_layout = _seq_song.layout()
	stream.cancel_after(_SONG_TAG, now)
	_seq_inst.events = _instance_events(int(_seq_inst.si), float(_seq_inst.shift), int(_seq_inst.take))
	_seq_inst.next = 0
	while _seq_inst.next < _seq_inst.events.size() and int(_seq_inst.events[_seq_inst.next].t_f) < now:
		_seq_inst.next += 1
	_seq_until = now
	update()


## Where the sequencer is: {section, bar (within the section), beat}, or {}.
func song_position() -> Dictionary:
	if _seq_inst.is_empty():
		return {}
	var L: Dictionary = _seq_layout[int(_seq_inst.si)]
	var bar_f := float(L.end_s - L.start_s) / maxf(1e-6, float(L.bars)) * AK.sample_rate
	var into := float(stream.get_frame() - int(_seq_inst.start_f)) / bar_f
	var bpb := float(_seq_song.tempo.beats_per_bar_at(L.start_bar))
	return {section = String(L.name), bar = floori(into), beat = fposmod(into, 1.0) * bpb}


## Render and schedule what the next `lookahead_s` needs. Cheap when nothing
## is due; call it every frame.
func update() -> void:
	if _seq_song == null:
		return
	var target: int = stream.get_frame() + roundi(lookahead_s * AK.sample_rate)
	var guard := 0
	while not _seq_inst.is_empty() and _seq_until < target and guard < 64:
		guard += 1
		var inst := _seq_inst
		var stop := mini(target, int(inst.end_f))
		var evs: Array = inst.events
		while int(inst.next) < evs.size() and int(evs[inst.next].t_f) < stop:
			var ev: Dictionary = evs[inst.next]
			inst.next += 1
			_schedule_note(ev.e, float(inst.shift))
		_seq_until = stop
		if stop >= int(inst.end_f):
			_next_instance()


func _boundary(quantize: StringName) -> int:
	var now: int = stream.get_frame()
	if _seq_inst.is_empty() or quantize == &"now":
		return now
	if quantize == &"section":
		return int(_seq_inst.end_f)
	var L: Dictionary = _seq_layout[int(_seq_inst.si)]
	var bar_f := float(L.end_s - L.start_s) / maxf(1e-6, float(L.bars)) * AK.sample_rate
	var unit := bar_f
	if quantize == &"beat":
		unit = bar_f / maxf(1.0, float(_seq_song.tempo.beats_per_bar_at(L.start_bar)))
	var start := int(_seq_inst.start_f)
	var k := ceili(float(now - start) / unit - 1e-9)
	return mini(start + roundi(k * unit), int(_seq_inst.end_f))


func _start_instance(si: int, shift: float, start_f: int) -> void:
	var take: int = _seq_takes.get(si, 0)
	_seq_takes[si] = take + 1
	var L: Dictionary = _seq_layout[si]
	var end_f := _seq_origin + roundi((float(L.end_s) + shift) * AK.sample_rate)
	_seq_inst = {si = si, shift = shift, take = take, start_f = start_f, end_f = maxi(end_f, start_f + 1),
		events = _instance_events(si, shift, take), next = 0}
	_seq_until = start_f
	section_started.emit(String(L.name), start_f)


func _instance_events(si: int, shift: float, take: int) -> Array:
	var out := []
	for e in _seq_song.section_events(si, _seq_layout, take):
		out.append({e = e, t_f = _seq_origin + roundi((float(e.time_s) + shift) * AK.sample_rate)})
	return out


func _next_instance() -> void:
	var cur := _seq_inst
	var si := int(cur.si)
	var next := -1
	if _seq_queue >= 0:
		next = _seq_queue
		_seq_queue = -1
	elif _seq_follow == &"loop":
		next = si
	elif _seq_follow == &"song" and si + 1 < _seq_layout.size():
		next = si + 1
	if next < 0:
		_seq_inst = {}
		song_finished.emit()
		return
	var shift: float
	if next == si + 1 and int(cur.end_f) == _seq_origin + roundi((float(_seq_layout[si].end_s) + float(cur.shift)) * AK.sample_rate):
		shift = float(cur.shift)   # straight on: song time carries over exactly
	else:
		shift = float(int(cur.end_f) - _seq_origin) / AK.sample_rate - float(_seq_layout[next].start_s)
	_start_instance(next, shift, int(cur.end_f))


func _schedule_note(e: Dictionary, shift: float) -> void:
	var sr := AK.sample_rate
	var recipe: AKRecipe = e.recipe
	var ov := AKSong.event_overrides(e)
	var lane := StringName(e.lane)
	var idx: int = _seq_counts.get(lane, 0)
	_seq_counts[lane] = idx + 1
	var id := _buffer_for(recipe, float(e.velocity), {}, idx, ov)
	var buf: AKBuffer = _buffers[id]
	var at := _seq_origin + roundi((float(e.time_s) + shift + recipe.offset_s) * sr)
	if not _seq_pan.has(lane):
		_seq_pan[lane] = float(e.pan)
	var pan: float = _seq_pan[lane]
	var g := AKDsp.db_to_gain(float(e.gain_db) + _seq_song.gain_db)
	var gl := g * (1.0 - pan if pan > 0.0 else 1.0)
	var gr := g * (1.0 + pan if pan < 0.0 else 1.0)
	var send := float(e.send) if float(e.send) >= 0.0 else buf.send
	stream.schedule(id, at, gl, gr, g * send if send > 0.0 else 0.0, _SONG_TAG, lane_bus(lane))


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


func _schedule_song(song: AKSong, extent_only := false) -> Dictionary:
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
		if extent_only:
			# Only the extent: the sequencer schedules these as they come up.
			var snd := float(e.send) if float(e.send) >= 0.0 else buf.send
			end = maxi(end, at + buf.frames())
			if snd > 0.0:
				send_end = maxi(send_end, at + buf.frames())
			continue
		if not lane_pan.has(e.lane):
			lane_pan[e.lane] = float(e.pan)
		var pan: float = lane_pan[e.lane]
		var g := AKDsp.db_to_gain(float(e.gain_db) + song.gain_db)
		var gl := g * (1.0 - pan if pan > 0.0 else 1.0)
		var gr := g * (1.0 + pan if pan < 0.0 else 1.0)
		var send := float(e.send) if float(e.send) >= 0.0 else buf.send
		stream.schedule(id, at, gl, gr, g * send if send > 0.0 else 0.0, 2, lane_bus(e.lane))
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
			&"room":
				var room := float(fx.get("room", 0.5))
				var mix := float(fx.get("mix", 0.2))
				if mix > 0.0:
					steps.append({type = "room", room = room, damp = float(fx.get("damp", 0.5)), mix = mix,
						width = float(fx.get("width", 1.0)), small = StringName(fx.get("quality", &"full")) == &"small"})
			&"echo":
				steps.append({type = "echo", delay = maxi(1, roundi(float(fx.get("time_s", 0.25)) * sr)),
					feedback = float(fx.get("feedback", 0.35)), mix = float(fx.get("mix", 0.3))})
			&"drive":
				steps.append({type = "drive", amount = float(fx.get("amount", 0.3))})
			&"bitcrush":
				steps.append({type = "bitcrush", bits = float(fx.get("bits", 8.0)), hold = int(fx.get("hold", 1))})
			_:
				push_warning("AKLive: master effect '%s' can't run live; skipped" % type)
	stream.set_chain(steps)
	stream.seek_frame(0)


func _measure(steps: Array) -> AKBuffer:
	stream.set_chain(steps)
	stream.seek_frame(0)
	if _probe_song == null:
		return render_offline(_length_frames)
	# Run the sequencer through the probe as playback would, then clear it.
	song_play(_probe_song)
	var out := render_playing(_length_frames, lookahead_s * 0.5)
	stream.cancel(_SONG_TAG)
	_seq_song = null
	_seq_inst = {}
	return out
