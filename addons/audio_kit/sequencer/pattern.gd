# SPDX-License-Identifier: Apache-2.0
@tool
## A loop of steps holding lanes, like a pattern in Auxy or a drum machine.
## Each lane plays one recipe:
##
##   {name = "kick", recipe = kick_recipe, steps = "X...x...X...x..."}
##   {name = "hat",  recipe = hat_recipe,  steps = "..x...x...x...x.", swing = 0.6}
##   {name = "bass", recipe = bass_recipe, steps = "x.x.x.x.", notes = ["A1", "A2", "A1", "E2"], gate = 0.5}
##   {name = "bell", recipe = bell_recipe, steps = "x..x..", degrees = [1, 5, 3, 8], scale = &"minor", root = "A4"}
##   {name = "lead", recipe = lead_recipe, notes = ["E4", "~", "~", ".", "G4", "~", "A4", "."]}
##
## Lane keys: name, recipe (AKRecipe or a res:// path), steps (step string,
## see AKNotes), notes (note names / MIDI numbers, cycled over the hits; or,
## without `steps`, one entry per step with "." rest and "~" tie), degrees +
## scale + root (scale degrees instead of notes), length (the lane's own loop
## length in steps: lanes of different lengths drift against each other),
## gate (fraction of a step a note holds, default 0.8; ties extend it),
## velocity (scales every hit), probability (chance each hit plays),
## swing (overrides the pattern's), octave (shifts notes), chord (semitone
## offsets: each hit plays them all, e.g. [0, 3, 7] minor), keytrack (false:
## only the pitch moves, not filters), gain_db, pan, send, mute.
##
## A lane can play a synth patch instead of a recipe: `patch` (an AKPatch or
## a res:// path) in place of `recipe`; velocity sets the patch's note
## velocity. And instead of steps it can hold freely timed notes, as a
## .mid import writes them: `events` = [[beat, length_beats, midi (-1 =
## unpitched), velocity 0..1], ...], beats from the pattern's start, played
## once (not looped), following the song's tempo changes exactly.
@icon("res://addons/audio_kit/icons/palette.svg")
class_name AKPattern
extends Resource

## Steps in the pattern (its loop length, for lanes without their own).
@export var steps := 16
## Steps per beat: 4 = sixteenth notes in 4/4.
@export var steps_per_beat := 4
## 0.5 is straight; higher delays every second step (0.66 is a triplet shuffle).
@export_range(0.5, 0.8) var swing := 0.5
## Seeded timing wobble, in milliseconds either way.
@export var humanize_ms := 0.0
## Seeded velocity wobble (0.1 = up to ±0.1).
@export var humanize_velocity := 0.0
@export var seed := 0
@export var lanes: Array[Dictionary] = []


func beats() -> float:
	return float(steps) / steps_per_beat


## Note events for this pattern placed at `start_bar`, looping for
## `length_beats`. Each: {time_s, lane, recipe, velocity, midi, note_hz,
## gate_s, step, beat, keytrack, gain_db, pan, send}. `salt` varies the
## seeded choices between placements.
func events(tempo: AKTempoMap, start_bar: float, length_beats: float, transpose := 0, mutes: Array = [], salt := 0) -> Array:
	var out := []
	var spb := 60.0 / tempo.bpm if tempo.changes.is_empty() else tempo.seconds_per_beat_at(start_bar)
	var step_beats := 1.0 / steps_per_beat
	var total := roundi(length_beats * steps_per_beat)
	for li in lanes.size():
		var l: Dictionary = lanes[li]
		var name := String(l.get("name", "lane%d" % li))
		if bool(l.get("mute", false)) or mutes.has(name):
			continue
		var recipe: AKRecipe = lane_recipe(li)
		if recipe == null:
			continue
		if l.has("events"):
			out.append_array(_free_events(l, name, recipe, tempo, start_bar, length_beats, transpose))
			continue
		var table := _table(l)
		if table.is_empty():
			continue
		var n := int(l.get("length", table.size()))
		var rng := RandomNumberGenerator.new()
		rng.seed = AK._seed(seed, salt, li + 101)
		var lane_swing := float(l.get("swing", swing))
		var gate := float(l.get("gate", 0.8))
		var vel_scale := float(l.get("velocity", 1.0))
		var prob := float(l.get("probability", 1.0))
		var octave := int(l.get("octave", 0))
		var chord: Array = l.get("chord", [0])
		for s in total:
			var e: Dictionary = table[s % n]
			# Draw for every step so later steps' choices don't depend on earlier ones.
			var roll := rng.randf()
			var jit := rng.randf_range(-1.0, 1.0)
			var vj := rng.randf_range(-1.0, 1.0)
			if e.tie or float(e.vel) <= 0.0 or roll >= float(e.chance) * prob:
				continue
			var ties := 0
			while ties + 1 < n and s + ties + 1 < total and bool(table[(s + ties + 1) % n].tie):
				ties += 1
			var beat := s * step_beats
			if s % 2 == 1:
				beat += (lane_swing - 0.5) * 2.0 * step_beats
			var t := tempo.to_seconds(start_bar, beat) + jit * humanize_ms * 0.001
			var base: int = int(e.midi) + transpose + octave * 12 if int(e.midi) >= 0 else -1
			var vel := clampf(float(e.vel) * vel_scale + vj * humanize_velocity, 0.0, 1.0)
			var chord_gain := -10.0 * log(float(chord.size())) / log(10.0) if base >= 0 else 0.0
			for off in (chord if base >= 0 else [0]):
				var midi: int = base + int(off) if base >= 0 else -1
				out.append({time_s = t, lane = name, recipe = recipe, velocity = vel,
					midi = midi, note_hz = AKNotes.midi_to_hz(midi) if midi >= 0 else 0.0,
					gate_s = (gate + ties) * step_beats * spb, step = s, beat = beat,
					keytrack = bool(l.get("keytrack", true)), gain_db = float(l.get("gain_db", 0.0)) + chord_gain,
					pan = float(l.get("pan", 0.0)), send = float(l.get("send", -1.0))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.time_s < b.time_s)
	return out


var _patch_recipes := {}


## The recipe lane `li` plays: its `recipe`, or for a `patch` lane a recipe
## of the `patch` voice (made once and kept, so bake keys stay stable).
func lane_recipe(li: int) -> AKRecipe:
	var l: Dictionary = lanes[li]
	if not l.has("patch"):
		return _recipe(l.get("recipe"))
	var p: Variant = l.patch
	var key := ""
	if p is Resource:
		key = p.resource_path if p.resource_path != "" else str(p.get_instance_id())
	else:
		key = str(p)
	if _patch_recipes.has(key):
		return _patch_recipes[key]
	var r := AKRecipe.new()
	r.voice = &"patch"
	r.params = {patch = p}
	r.bind = {intensity = {velocity = [0.0, 1.0]}}
	r.send = float(l.get("send", 0.0)) if float(l.get("send", -1.0)) >= 0.0 else 0.0
	_patch_recipes[key] = r
	return r


## Events of a lane with freely timed notes (see the class notes).
func _free_events(l: Dictionary, name: String, recipe: AKRecipe, tempo: AKTempoMap, start_bar: float, length_beats: float,
		transpose: int) -> Array:
	var out := []
	var base_beat := tempo.beats_at_bar(start_bar)
	var vel_scale := float(l.get("velocity", 1.0))
	var octave := int(l.get("octave", 0))
	for ev in l.events:
		var beat := float(ev[0])
		if beat >= length_beats or beat < 0.0:
			continue
		var t0 := tempo.beat_to_seconds(base_beat + beat)
		var t1 := tempo.beat_to_seconds(base_beat + beat + maxf(0.0, float(ev[1])))
		var midi: int = int(ev[2]) + transpose + octave * 12 if int(ev[2]) >= 0 else -1
		out.append({time_s = t0, lane = name, recipe = recipe, velocity = clampf(float(ev[3]) * vel_scale, 0.0, 1.0),
			midi = midi, note_hz = AKNotes.midi_to_hz(midi) if midi >= 0 else 0.0,
			gate_s = t1 - t0, step = roundi(beat * steps_per_beat), beat = beat,
			keytrack = bool(l.get("keytrack", true)), gain_db = float(l.get("gain_db", 0.0)),
			pan = float(l.get("pan", 0.0)), send = float(l.get("send", -1.0))})
	return out


## Per-step entries {vel, chance, tie, midi} for a lane.
func _table(l: Dictionary) -> Array:
	var pitches := _pitches(l)
	var table := []
	if l.has("steps"):
		var hit := 0
		for e in AKNotes.parse_steps(String(l.steps)):
			var d: Dictionary = e.duplicate()
			d["midi"] = -1
			if float(d.vel) > 0.0 and not pitches.is_empty():
				d["midi"] = pitches[hit % pitches.size()]
				hit += 1
			table.append(d)
	elif l.has("notes"):
		var v := 0.85
		for x in l.notes:
			var s := str(x)
			if s == "." or s == "-" or s == "":
				table.append({vel = 0.0, chance = 0.0, tie = false, midi = -1})
			elif s == "~":
				table.append({vel = 0.0, chance = 0.0, tie = true, midi = -1})
			else:
				table.append({vel = v, chance = 1.0, tie = false, midi = AKNotes.name_to_midi(x)})
	return table


func _pitches(l: Dictionary) -> Array:
	var out := []
	if l.has("degrees"):
		for d in l.degrees:
			out.append(AKNotes.degree_to_midi(int(d), StringName(l.get("scale", &"major")), l.get("root", "C4")))
	elif l.has("notes") and l.has("steps"):
		for x in l.notes:
			if str(x) not in [".", "-", "~", ""]:
				out.append(AKNotes.name_to_midi(x))
	return out


static func _recipe(r: Variant) -> AKRecipe:
	if r is AKRecipe:
		return r
	if (r is String or r is StringName) and ResourceLoader.exists(String(r)):
		return load(String(r))
	push_error("AKPattern: lane recipe %s not found" % r)
	return null
