# SPDX-License-Identifier: Apache-2.0
## An arrangement: sections of patterns on one tempo map, with lane mixing,
## automation, a shared reverb and a master chain.
##
##   sections = [
##     {name = "intro", bars = 2, patterns = [arp]},
##     {name = "drop",  bars = 4, patterns = [arp, drums], automation = {"arp.cutoff_hz": [[0.0, 600.0], [1.0, 3000.0]]}},
##     {name = "outro", bars = 1, patterns = [arp], mute = ["hat"], gain_db = -4.0},
##   ]
##
## Section keys: name, bars (may be fractional), patterns (AKPattern or
## res:// paths; each restarts at the section start), mute (lane names),
## transpose (semitones), gain_db, automation ("lane.param" -> breakpoints
## [[position 0..1 across the section, value], ...]; param is any voice or
## effect parameter, or gain_db).
##
## Every note can also become a cue (`to_cues`), so motion can follow music.
@icon("res://addons/audio_kit/icons/palette.svg")
class_name AKSong
extends Resource

@export var tempo: AKTempoMap
@export var sections: Array[Dictionary] = []
## Per-lane mix: lane name -> {gain_db, pan, send}. Adds to the lane's own.
@export var mix: Dictionary = {}
## Overall level of the song when mixed under effects (render_cues).
@export var gain_db := 0.0
## The song's shared reverb (as AKCueMap.reverb). Used when rendered alone;
## under a cue map, the cue map's reverb is used for both.
@export var reverb: Dictionary = {room = 0.5, damp = 0.5, width = 1.0, quality = &"full", return_db = 0.0}
## Master chain when rendered alone.
@export var master_fx: Array[Dictionary] = [{type = &"dcblock"}, {type = &"loudness", target_lufs = -16.0}, {type = &"limit", ceiling_db = -1.5}]


## Start time (seconds) and length (bars) of each section, in order.
func layout() -> Array:
	var out := []
	var bar := 0.0
	for s in sections:
		var bars := float(s.get("bars", 1.0))
		out.append({name = String(s.get("name", "")), start_bar = bar, bars = bars,
			start_s = tempo.bar_to_seconds(bar), end_s = tempo.bar_to_seconds(bar + bars)})
		bar += bars
	return out


func length_s() -> float:
	var l := layout()
	return l[l.size() - 1].end_s if not l.is_empty() else 0.0


## Every note event, in time order, with section, bar and automation applied.
func events() -> Array:
	var out := []
	var lay := layout()
	for si in sections.size():
		out.append_array(section_events(si, lay))
	out.sort_custom(_before)
	return out


## Time order with ties broken by lane, then pitch, so every caller sees the
## same sequence (per-lane variant counters depend on it).
static func _before(a: Dictionary, b: Dictionary) -> bool:
	if a.time_s != b.time_s:
		return a.time_s < b.time_s
	if String(a.lane) != String(b.lane):
		return String(a.lane) < String(b.lane)
	return int(a.get("midi", -1)) < int(b.get("midi", -1))


## Index of the section called `section_name`, or -1.
func section_index(section_name: String) -> int:
	for i in sections.size():
		if String(sections[i].get("name", "")) == section_name:
			return i
	return -1


## One section's note events in song time (as `events()` gives them), sorted.
## `take` > 0 reseeds humanize and probability for a repeat of the section
## (the live sequencer's loops), so repeats aren't identical.
func section_events(si: int, lay: Array = [], take := 0) -> Array:
	if lay.is_empty():
		lay = layout()
	var out := []
	var s: Dictionary = sections[si]
	var L: Dictionary = lay[si]
	var beats := float(L.bars) * tempo.beats_per_bar_at(L.start_bar)
	var auto: Dictionary = s.get("automation", {})
	for pi in s.get("patterns", []).size():
		var p := _pattern(s.patterns[pi])
		if p == null:
			continue
		for e in p.events(tempo, L.start_bar, beats, int(s.get("transpose", 0)), s.get("mute", []), si * 31 + pi + take * 1009):
			e["section"] = L.name
			e["bar"] = floori(tempo.seconds_to_bar(e.time_s) + 1e-6)
			e["gain_db"] = float(e.gain_db) + float(s.get("gain_db", 0.0)) + float(mix.get(e.lane, {}).get("gain_db", 0.0))
			e["pan"] = clampf(float(e.pan) + float(mix.get(e.lane, {}).get("pan", 0.0)), -1.0, 1.0)
			if mix.get(e.lane, {}).has("send"):
				e["send"] = float(mix[e.lane].send)
			var ov := {}
			var pos := (float(e.time_s) - float(L.start_s)) / maxf(1e-6, float(L.end_s) - float(L.start_s))
			for k in auto:
				var ks := String(k)
				if ks.begins_with(String(e.lane) + "."):
					var v := _curve_at(auto[k], pos)
					var param := ks.substr(String(e.lane).length() + 1)
					if param == "gain_db":
						e["gain_db"] = float(e.gain_db) + v
					else:
						ov[param] = v
			e["overrides"] = ov
			out.append(e)
	out.sort_custom(_before)
	return out


## The render overrides for one event (pitch, gate, automation).
static func event_overrides(e: Dictionary) -> Dictionary:
	var ov: Dictionary = e.get("overrides", {}).duplicate()
	ov["_gate_s"] = snappedf(float(e.gate_s), 1e-5)
	if int(e.midi) >= 0:
		ov["_note_hz"] = snappedf(float(e.note_hz), 1e-4)
		ov["_keytrack"] = bool(e.keytrack)
	return ov


## Render the song: {mix, stems, events}. `send_bus`, when given, collects
## the reverb sends instead of a reverb here (render_cues shares one reverb).
## `master` applies the master chain.
func render(with_stems := false, master := true, send_bus: AKBuffer = null) -> Dictionary:
	var sr := AK.sample_rate
	var out := AKBuffer.new(roundi(length_s() * sr), sr)
	var lane_bufs := {}
	var own_send := send_bus == null
	var bus := AKBuffer.new(0, sr) if own_send else send_bus
	var memo := {}
	var counts := {}
	var evs := events()
	for e in evs:
		var recipe: AKRecipe = e.recipe
		var ov := event_overrides(e)
		var idx: int = counts.get(e.lane, 0)
		counts[e.lane] = idx + 1
		var key := AK.bake_key(recipe, float(e.velocity), {}, idx, ov)
		var buf: AKBuffer = memo.get(key)
		if buf == null:
			buf = AK.render(recipe, float(e.velocity), {}, idx, ov)
			memo[key] = buf
		var at := roundi((float(e.time_s) + recipe.offset_s) * sr)
		if not lane_bufs.has(e.lane):
			lane_bufs[e.lane] = {buf = AKBuffer.new(0, sr), send = AKBuffer.new(0, sr), pan = float(e.pan)}
		var g := AKDsp.db_to_gain(float(e.gain_db) + gain_db)
		buf.mix_into(lane_bufs[e.lane].buf, at, g)
		var send := float(e.send) if float(e.send) >= 0.0 else buf.send
		if send > 0.0:
			buf.mix_into(bus, at, g * send)
	var stems := {}
	for lane in lane_bufs:
		var lb: AKBuffer = lane_bufs[lane].buf
		AK._balance(lb, float(lane_bufs[lane].pan))
		lb.mix_into(out, 0)
		if with_stems:
			stems["music." + String(lane)] = lb
	if own_send and bus.frames() > 0 and bus.peak() > 0.0:
		var wet := AKReverb.wet(bus, float(reverb.get("room", 0.5)), float(reverb.get("damp", 0.5)), float(reverb.get("width", 1.0)),
			float(reverb.get("tail_s", -1.0)), StringName(reverb.get("quality", &"full")))
		wet.mix_into(out, 0, AKDsp.db_to_gain(float(reverb.get("return_db", 0.0))))
		if with_stems:
			stems["music.reverb"] = wet
	if master:
		for f in master_fx:
			AK.apply_fx(out, f)
	for k in stems:
		stems[k].resize(out.frames())
	return {mix = out, stems = stems, events = evs}


## Hash of everything that changes the song's sound.
func key() -> String:
	var parts := []
	var counts := {}
	for e in events():
		var idx: int = counts.get(e.lane, 0)
		counts[e.lane] = idx + 1
		parts.append([snappedf(float(e.time_s), 1e-6), e.lane, snappedf(float(e.gain_db), 1e-4), snappedf(float(e.pan), 1e-4),
			snappedf(float(e.send), 1e-4), AK.bake_key(e.recipe, float(e.velocity), {}, idx, event_overrides(e))])
	return JSON.stringify({events = parts, gain = gain_db, reverb = reverb, master = master_fx, length = length_s()}, "", true, true).sha256_text()


## The song as motion kit-style cues: "music.<lane>" per note (intensity =
## velocity; data: lane, note, section, bar, source = "song") and
## "music.section" at each section start. Renderers skip cues whose
## data.source is "song", so adding them to a composition doesn't play twice.
func to_cues(fps := 30.0) -> Array:
	var out := []
	for L in layout():
		out.append({name = "music.section", time = L.start_s, frame = L.start_s * fps, intensity = 1.0,
			data = {source = "song", section = L.name}})
	for e in events():
		out.append({name = "music." + String(e.lane), time = e.time_s, frame = float(e.time_s) * fps, intensity = e.velocity,
			data = {source = "song", lane = e.lane, note = e.midi, section = e.section, bar = e.bar}})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.time < b.time)
	return out


static func _pattern(p: Variant) -> AKPattern:
	if p is AKPattern:
		return p
	if (p is String or p is StringName) and ResourceLoader.exists(String(p)):
		return load(String(p))
	push_error("AKSong: pattern %s not found" % p)
	return null


static func _curve_at(points: Variant, pos: float) -> float:
	var pts: Array = points
	if pts.is_empty():
		return 0.0
	if pos <= float(pts[0][0]):
		return float(pts[0][1])
	for i in range(1, pts.size()):
		var a: Array = pts[i - 1]
		var b: Array = pts[i]
		if pos <= float(b[0]):
			var u := (pos - float(a[0])) / maxf(1e-9, float(b[0]) - float(a[0]))
			return lerpf(float(a[1]), float(b[1]), u)
	return float(pts[pts.size() - 1][1])
