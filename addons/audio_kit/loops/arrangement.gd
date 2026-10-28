# SPDX-License-Identifier: Apache-2.0
@tool
## An arrangement of loops on tracks, the Sequencer's document. It holds two
## linked views of the same tracks, and compiles either to an AKSong, so it
## plays live (AKLive) and bakes like any song:
##
##   scenes    one loop per track per scene; a game switches scenes on the
##             beat or bar ("menu", "race", "final_lap")
##   timeline  clips of loops at bars, cut into sections at named markers,
##             for a fixed piece
##
##   tempo = AKTempoMap.make(128.0)
##   tracks = [{name = "drums"}, {name = "bass", gain_db = -3.0}, {name = "chords", send = 0.2, intensity = [0.3, 0.7]}]
##   scenes = [{name = "race", bars = 4, clips = {"drums": "res://audio/loops/beat_a.tres", "bass": "res://audio/loops/bass_a.tres"}}]
##   timeline = [{track = "drums", loop = "res://audio/loops/beat_a.tres", bar = 8.0, bars = 16.0, offset_bars = 0.0}]
##   markers = [{name = "intro", bar = 0.0}, {name = "race", bar = 8.0}]
##
## Track keys: name, gain_db, pan, send (reverb, 0..1), mute, solo,
## intensity ([from, to]: the track fades in between these music
## intensities), fx (the track's insert chain: effect specs as in a patch's
## `effects`, run on the track's mixed lanes, live and baked alike), color. A track plays
## one clip at a time: where clips overlap on a track, the one that starts
## later plays, and the earlier one resumes (in phase) after it. A clip plays its loop from `offset_bars`, repeating,
## for `bars`; a clip that crosses a marker carries on in phase.
@icon("res://addons/audio_kit/icons/palette.svg")
class_name AKArrangement
extends Resource

@export var tempo: AKTempoMap
@export var tracks: Array[Dictionary] = []
@export var scenes: Array[Dictionary] = []
@export var timeline: Array[Dictionary] = []
@export var markers: Array[Dictionary] = []
## The timeline's length in bars; 0 = to the end of the last clip.
@export var length_bars := 0.0
## As AKSong.stingers: sounds that mark a change of section (or scene).
@export var stingers: Array[Dictionary] = []
@export var reverb: Dictionary = {room = 0.5, damp = 0.5, width = 1.0, quality = &"full", return_db = 0.0}
@export var master_fx: Array[Dictionary] = [{type = &"dcblock"}, {type = &"loudness", target_lufs = -16.0}, {type = &"limit", ceiling_db = -1.5}]
## The music intensity baked renders use (tracks with an `intensity` range follow it).
@export_range(0.0, 1.0) var intensity := 1.0

static var _songs := {}


func _init() -> void:
	if tempo == null:
		tempo = AKTempoMap.make(120.0)


# ------------------------------------------------------------------ queries

func track_index(track_name: String) -> int:
	for i in tracks.size():
		if String(tracks[i].get("name", "")) == track_name:
			return i
	return -1


func track_names() -> Array:
	return tracks.map(func(t: Dictionary) -> String: return String(t.get("name", "")))


func scene_index(scene_name: String) -> int:
	for i in scenes.size():
		if String(scenes[i].get("name", "")) == scene_name:
			return i
	return -1


func scene_names() -> Array:
	return scenes.map(func(s: Dictionary) -> String: return String(s.get("name", "")))


## A loop from a resource or a res:// path (null when it isn't one).
static func loop_of(v: Variant) -> AKLoop:
	if v is AKLoop:
		return v
	if (v is String or v is StringName) and String(v) != "" and ResourceLoader.exists(String(v)):
		return load(String(v)) as AKLoop
	return null


## A scene's length in bars: its `bars`, or its longest loop's (at least 1).
func scene_bars(si: int) -> float:
	var s: Dictionary = scenes[si]
	if float(s.get("bars", 0.0)) > 0.0:
		return float(s.bars)
	var bars := 1.0
	for t in s.get("clips", {}):
		var l := loop_of(s.clips[t])
		if l:
			bars = maxf(bars, l.bars)
	return bars


## The stretches [from, to) in bars where clip `ci` sounds: its own span,
## less wherever a clip that starts later on the same track covers it (one
## clip per track at a time; the earlier one resumes, in phase, after).
func clip_spans(ci: int) -> Array:
	var c: Dictionary = timeline[ci]
	var b0 := float(c.get("bar", 0.0))
	var spans := [[b0, b0 + float(c.get("bars", 1.0))]]
	for j in timeline.size():
		var d: Dictionary = timeline[j]
		if j == ci or String(d.track) != String(c.track):
			continue
		var d0 := float(d.get("bar", 0.0))
		if d0 < b0 or (d0 == b0 and j < ci):
			continue
		var d1 := d0 + float(d.get("bars", 1.0))
		var cut := []
		for sp in spans:
			if d1 <= sp[0] or d0 >= sp[1]:
				cut.append(sp)
				continue
			if sp[0] < d0:
				cut.append([sp[0], d0])
			if d1 < sp[1]:
				cut.append([d1, sp[1]])
		spans = cut
	return spans


## The timeline's length: `length_bars`, or the end of its last clip.
func timeline_bars() -> float:
	if length_bars > 0.0:
		return length_bars
	var end := 0.0
	for c in timeline:
		end = maxf(end, float(c.get("bar", 0.0)) + float(c.get("bars", 1.0)))
	return end


## The timeline's sections: [{name, bar, bars}], cut at the markers (before
## the first marker, a section called "start").
func timeline_sections() -> Array:
	var end := timeline_bars()
	var ms := markers.duplicate()
	ms.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.bar) < float(b.bar))
	var cuts := []
	if ms.is_empty() or float(ms[0].bar) > 0.0:
		cuts.append({name = "start", bar = 0.0})
	for m in ms:
		if float(m.bar) < end and (cuts.is_empty() or float(m.bar) > float(cuts[-1].bar)):
			cuts.append({name = String(m.name), bar = float(m.bar)})
	var out := []
	for i in cuts.size():
		var b0 := float(cuts[i].bar)
		var b1 := float(cuts[i + 1].bar) if i + 1 < cuts.size() else end
		if b1 > b0:
			out.append({name = String(cuts[i].name), bar = b0, bars = b1 - b0})
	return out


func _audible(track_name: String) -> bool:
	var ti := track_index(track_name)
	if ti < 0:
		return true
	if bool(tracks[ti].get("mute", false)):
		return false
	var soloed := tracks.filter(func(t: Dictionary) -> bool: return bool(t.get("solo", false)))
	return soloed.is_empty() or bool(tracks[ti].get("solo", false))


# ------------------------------------------------------------------ editing helpers

## A new timeline with scene `si`'s clips written over bars [from_bar,
## to_bar) on its tracks (clips there are trimmed or split around it).
func painted(si: int, from_bar: float, to_bar: float) -> Array[Dictionary]:
	var s: Dictionary = scenes[si]
	var clips: Dictionary = s.get("clips", {})
	var out: Array[Dictionary] = []
	for c in timeline:
		if not clips.has(String(c.track)) and not clips.has(StringName(c.track)):
			out.append(c.duplicate())
			continue
		var b0 := float(c.get("bar", 0.0))
		var b1 := b0 + float(c.get("bars", 1.0))
		if b1 <= from_bar or b0 >= to_bar:
			out.append(c.duplicate())
			continue
		if b0 < from_bar:
			var left: Dictionary = c.duplicate()
			left["bars"] = from_bar - b0
			out.append(left)
		if b1 > to_bar:
			var right: Dictionary = c.duplicate()
			right["bar"] = to_bar
			right["bars"] = b1 - to_bar
			right["offset_bars"] = float(c.get("offset_bars", 0.0)) + (to_bar - b0)
			out.append(right)
	for t in clips:
		var lv: Variant = clips[t]
		if loop_of(lv) == null:
			continue
		out.append({track = String(t), loop = lv.resource_path if lv is Resource else String(lv), bar = from_bar, bars = to_bar - from_bar, offset_bars = 0.0})
	return out


## A new timeline with `clip` ({track, loop, bar, bars, offset_bars}) placed
## and the other clips on its track trimmed or split around it (a recorded
## take lands this way).
func with_clip(clip: Dictionary) -> Array[Dictionary]:
	var track := String(clip.track)
	var from_bar := float(clip.get("bar", 0.0))
	var to_bar := from_bar + float(clip.get("bars", 1.0))
	var out: Array[Dictionary] = []
	for c in timeline:
		var b0 := float(c.get("bar", 0.0))
		var b1 := b0 + float(c.get("bars", 1.0))
		if String(c.track) != track or b1 <= from_bar or b0 >= to_bar:
			out.append(c.duplicate())
			continue
		if b0 < from_bar:
			var left: Dictionary = c.duplicate()
			left["bars"] = from_bar - b0
			out.append(left)
		if b1 > to_bar:
			var right: Dictionary = c.duplicate()
			right["bar"] = to_bar
			right["bars"] = b1 - to_bar
			right["offset_bars"] = float(c.get("offset_bars", 0.0)) + (to_bar - b0)
			out.append(right)
	var placed := clip.duplicate()
	placed["track"] = track
	placed["offset_bars"] = float(clip.get("offset_bars", 0.0))
	out.append(placed)
	return out


# ------------------------------------------------------------------ compiling

## The arrangement as a song: `mode` "timeline" (sections at the markers) or
## "scenes" (a section per scene). Tracks become lanes (a drum loop on
## track "drums" gives drums.kick, drums.snare ...); a track's gain, pan and
## send become the song's `mix`, its `intensity` range `intensity_lanes`, its
## lanes one group (`lane_groups`) with the track's `fx` (`group_fx`).
## Muted tracks (and, when any track is soloed, the others) are left out.
## Cached by a hash of the arrangement and its loops.
func to_song(mode := "timeline") -> AKSong:
	var k := key(mode)
	if _songs.has(k):
		return _songs[k]
	var song := AKSong.new()
	song.tempo = tempo
	song.reverb = reverb.duplicate(true)
	song.master_fx = master_fx.duplicate(true)
	song.stingers = stingers.duplicate(true)
	song.intensity = intensity
	var lanes := {}
	if mode == "scenes":
		for si in scenes.size():
			var s: Dictionary = scenes[si]
			var bars := scene_bars(si)
			var start := 0.0
			for sec in song.sections:
				start += float(sec.bars)
			var beats := tempo.beats_at_bar(start + bars) - tempo.beats_at_bar(start)
			var pats := []
			for t in tracks:
				var tn := String(t.get("name", ""))
				var clips: Dictionary = s.get("clips", {})
				var lv: Variant = clips.get(tn, clips.get(StringName(tn)))
				var l := loop_of(lv)
				if l == null or not _audible(tn):
					continue
				var p := l.to_pattern(beats, tn, 0.0, 0.0, -1.0, tn)
				_note_lanes(p, tn, lanes)
				pats.append(p)
			song.sections.append({name = String(s.get("name", "scene%d" % si)), bars = bars, patterns = pats})
	else:
		for sec: Dictionary in timeline_sections():
			var s0 := float(sec.bar)
			var s1 := s0 + float(sec.bars)
			var beat0 := tempo.beats_at_bar(s0)
			var beats := tempo.beats_at_bar(s1) - beat0
			var pats := []
			for ci in timeline.size():
				var c: Dictionary = timeline[ci]
				var tn := String(c.get("track", ""))
				if track_index(tn) < 0 or not _audible(tn):
					continue
				var l := loop_of(c.get("loop"))
				if l == null:
					continue
				var cb := float(c.get("bar", 0.0))
				for sp in clip_spans(ci):
					var from := maxf(s0, float(sp[0]))
					var to := minf(s1, float(sp[1]))
					if to <= from:
						continue
					var phase := tempo.beats_at_bar(from) - tempo.beats_at_bar(cb) + float(c.get("offset_bars", 0.0)) * l.beats_per_bar
					var at := tempo.beats_at_bar(from) - beat0
					var p := l.to_pattern(beats, tn, phase, at, tempo.beats_at_bar(to) - tempo.beats_at_bar(from), tn)
					_note_lanes(p, tn, lanes)
					pats.append(p)
			song.sections.append({name = String(sec.name), bars = float(sec.bars), patterns = pats})
	for lane in lanes:
		var t: Dictionary = tracks[track_index(lanes[lane])]
		var m := {gain_db = float(t.get("gain_db", 0.0)), pan = float(t.get("pan", 0.0))}
		if t.has("send"):
			m["send"] = float(t.send)
		song.mix[lane] = m
		song.lane_groups[lane] = String(lanes[lane])
		if t.has("intensity"):
			song.intensity_lanes[lane] = (t.intensity as Array).duplicate()
		var fx: Array = t.get("fx", [])
		if not fx.is_empty():
			song.group_fx[String(lanes[lane])] = fx.duplicate(true)
	_songs[k] = song
	return song


func _note_lanes(p: AKPattern, track_name: String, lanes: Dictionary) -> void:
	for l in p.lanes:
		lanes[String(l.name)] = track_name


## Forget compiled songs (they're also re-made whenever the hash changes).
static func clear_cache() -> void:
	_songs.clear()


## Hash of everything that changes the compiled song in `mode`.
func key(mode := "timeline") -> String:
	return JSON.stringify({mode = mode, a = AK._hashable(describe())}, "", true, true).sha256_text()


func describe() -> Dictionary:
	var loops := {}
	for s in scenes:
		for t in s.get("clips", {}):
			_describe_loop(s.clips[t], loops)
	for c in timeline:
		_describe_loop(c.get("loop"), loops)
	return {tempo = {bpm = tempo.bpm, beats_per_bar = tempo.beats_per_bar, offset_s = tempo.offset_s, changes = tempo.changes},
		tracks = tracks, scenes = scenes, timeline = timeline, markers = markers, length_bars = length_bars,
		stingers = stingers, reverb = reverb, master_fx = master_fx, intensity = intensity, loops = loops}


func _describe_loop(v: Variant, into: Dictionary) -> void:
	var l := loop_of(v)
	if l == null:
		return
	var id: String = l.resource_path if l.resource_path != "" else str(l.get_instance_id())
	into[id] = l.describe()
