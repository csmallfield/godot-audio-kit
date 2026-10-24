# SPDX-License-Identifier: Apache-2.0
@tool
## A loop: one instrument and its notes, a few bars long, written on a grid
## (the Sound Lab's Loops tab) and played by the kit's sequencer.
##
##   kind = "synth"            # synth (an AKPatch) | sample (an AKSample) | percussive (an AKKit)
##   bars = 2
##   beats_per_bar = 4
##   division = 16             # 16 | 32 | 12 | 24 cells a bar: the grid shown and the snap, nothing else
##   instrument = <AKPatch>
##   notes = [[0, 24, 45, 0.9], [48, 24, 57, 0.7]]   # [start tick, length ticks, row, velocity 0..1]
##
## Time is in ticks, 96 to a beat, so every division lands on whole ticks
## (a 16th is 24, a 32nd 12, a triplet 8th 32, a triplet 16th 16). Changing
## `division` never moves or drops a note; notes off the grid still play.
## A row is a MIDI note for synth and sample loops and a piece index
## (`instrument.pieces[row]`) for percussive ones.
##
## `to_pattern()` unrolls the notes over a section into AKPattern `events`
## lanes, so a loop plays anywhere a pattern does: songs, AKLive, bakes.
@icon("res://addons/audio_kit/icons/palette.svg")
class_name AKLoop
extends Resource

const TICKS_PER_BEAT := 96
const DIVISIONS := [16, 32, 12, 24]
const KINDS := ["synth", "sample", "percussive"]

@export_enum("synth", "sample", "percussive") var kind := "synth"
@export_range(1, 64, 1, "or_greater") var bars := 1
@export_range(1, 16, 1) var beats_per_bar := 4
## Cells a bar on the grid (16, 32, 12 or 24): a view and a snap only.
@export var division := 16
## An AKPatch (synth), an AKSample (sample) or an AKKit (percussive).
@export var instrument: Resource
## [start tick, length ticks, row, velocity 0..1], in any order.
@export var notes: Array = []
## 0.5 is straight; higher delays notes that start on an off-beat 16th
## (0.66 is a triplet shuffle). Swing doesn't depend on `division`.
@export_range(0.5, 0.8) var swing := 0.5
@export var gain_db := 0.0
## For the loop browser (beat, bass, chords, lead, fx ...).
@export var category := ""

var _sample_recipe: AKRecipe
var _sample_for: AKSample


## Ticks in one pass of the loop.
func length_ticks() -> int:
	return bars * beats_per_bar * TICKS_PER_BEAT


func length_beats() -> float:
	return float(bars * beats_per_bar)


## Ticks in one grid cell at `div` (default: the loop's division).
func cell_ticks(div := 0) -> int:
	var d := div if div > 0 else division
	return maxi(1, beats_per_bar * TICKS_PER_BEAT / d)


## `tick` snapped to the nearest cell of the grid (at `div`, or the loop's).
func snap(tick: float, div := 0) -> int:
	var c := cell_ticks(div)
	return roundi(tick / c) * c


## Whether a note starts and ends on the current grid.
func on_grid(note: Array, div := 0) -> bool:
	var c := cell_ticks(div)
	return int(note[0]) % c == 0 and int(note[1]) % c == 0


## Change the grid. Notes keep their ticks: only the view and snap change.
func set_division(div: int) -> void:
	if not div in DIVISIONS:
		push_warning("AKLoop: division %d isn't one of %s" % [div, DIVISIONS])
	division = div
	emit_changed()


## The lane name a loop plays on (its resource name, its file name, or "loop").
func lane_name() -> String:
	if resource_name != "":
		return resource_name
	if resource_path != "" and not resource_path.contains("::"):
		return resource_path.get_file().get_basename()
	return "loop"


## The loop as a pattern of `section_beats` (default: one pass), the notes
## repeating to fill it. Synth and sample loops give one `events` lane named
## `lane` (default `lane_name()`); percussive loops one lane per kit piece in
## use, named `<drum_prefix>.<piece>` (`drums.kick`, as .mid drums import).
##
## A window of the endless loop can be placed instead (how arrangement clips
## play): the notes from `from_beats` into the loop (counting every pass:
## 6.0 on a one-bar loop is beat 2 of its second pass), for `length_beats`
## (default: to the section's end), starting at `at_beats` in the section.
func to_pattern(section_beats := -1.0, lane := "", from_beats := 0.0, at_beats := 0.0, length_beats := -1.0,
		drum_prefix := "drums") -> AKPattern:
	var beats := section_beats if section_beats > 0.0 else length_beats()
	var p := AKPattern.new()
	p.steps_per_beat = 4
	p.steps = maxi(1, roundi(beats * 4.0))
	p.resource_name = lane_name()
	var name := lane if lane != "" else lane_name()
	var span := length_beats if length_beats >= 0.0 else beats - at_beats
	var unrolled := _unrolled(from_beats, at_beats, minf(span, beats - at_beats))
	match kind:
		"percussive":
			var kit := instrument as AKKit
			if kit == null:
				push_error("AKLoop %s: a percussive loop needs an AKKit" % name)
				return p
			var by_piece := {}
			for ev in _choked(unrolled, kit):
				var row := int(ev[2])
				if not by_piece.has(row):
					by_piece[row] = []
				var gated := kit.is_gated(row)
				var e := [ev[0], ev[1] if gated else 0.0, -1, ev[3]]
				if ev.size() > 4:
					e.append(ev[4])
				by_piece[row].append(e)
			var rows := by_piece.keys()
			rows.sort()
			for row in rows:
				var r := kit.piece_recipe(row)
				if r == null:
					continue
				p.lanes.append({name = drum_prefix + "." + kit.piece_name(row), recipe = r, events = by_piece[row], gain_db = gain_db})
		"sample":
			var s := instrument as AKSample
			if s == null:
				push_error("AKLoop %s: a sample loop needs an AKSample" % name)
				return p
			p.lanes.append({name = name, recipe = _sample_lane_recipe(s), events = unrolled, gain_db = gain_db})
		_:
			if not instrument is AKPatch:
				push_error("AKLoop %s: a synth loop needs an AKPatch" % name)
				return p
			p.lanes.append({name = name, patch = instrument, events = unrolled, gain_db = gain_db})
	return p


## Pattern events [beat, length_beats, row, velocity] for the notes that
## start in [from, from + length) beats of the endlessly repeating loop,
## swung, placed from `at` beats; in time order (ties by row).
func _unrolled(from: float, at: float, length: float) -> Array:
	var out := []
	if length <= 0.0:
		return out
	var L := length_ticks()
	var lo := from * TICKS_PER_BEAT
	var hi := (from + length) * TICKS_PER_BEAT
	var sorted := notes.duplicate()
	sorted.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[2] < b[2]))
	for k in range(floori(lo / L), ceili(hi / L)):
		for n: Array in sorted:
			if int(n[0]) < 0 or int(n[0]) >= L:
				continue   # outside the loop: kept in `notes`, not played
			var t := int(n[0]) + k * L
			if t < lo - 1e-6 or t >= hi - 1e-6:
				continue
			var beat := at + (_swung(int(n[0])) + k * L - lo) / TICKS_PER_BEAT
			out.append([beat, float(n[1]) / TICKS_PER_BEAT, int(n[2]), clampf(float(n[3]), 0.0, 1.0)])
	return out


## A tick moved by swing: notes on an off-beat 16th (tick 24 of each 48)
## move later by (swing - 0.5) * 2 sixteenths.
func _swung(t: int) -> float:
	if swing > 0.5 and t % 48 == 24:
		return t + (swing - 0.5) * 2.0 * 24.0
	return float(t)


## Choke groups: each hit gets a fifth value, the beats until the next hit
## of a piece in its group (itself included) starts, when there is one in
## the section. Hits at the same instant don't cut each other.
func _choked(evs: Array, kit: AKKit) -> Array:
	var out := []
	for i in evs.size():
		var e: Array = evs[i].duplicate()
		var g := kit.choke_of(int(e[2]))
		if g != "":
			for j in range(i + 1, evs.size()):
				var f: Array = evs[j]
				if float(f[0]) > float(e[0]) and kit.choke_of(int(f[2])) == g:
					e.append(float(f[0]) - float(e[0]))
					break
		out.append(e)
	return out


func _sample_lane_recipe(s: AKSample) -> AKRecipe:
	if _sample_recipe == null or _sample_for != s:
		_sample_for = s
		_sample_recipe = s.to_recipe()
	return _sample_recipe


## Every note's [start, length, row, velocity] with numbers normalised
## (ints for ticks and rows), sorted: for comparing loops.
func sorted_notes() -> Array:
	var out := []
	for n: Array in notes:
		out.append([int(n[0]), int(n[1]), int(n[2]), snappedf(float(n[3]), 1e-6)])
	out.sort()
	return out


## Add a note (ticks). Returns its index.
func add_note(start: int, length: int, row: int, velocity := 0.8) -> int:
	notes.append([start, length, row, velocity])
	emit_changed()
	return notes.size() - 1


func describe() -> Dictionary:
	return {kind = kind, bars = bars, beats_per_bar = beats_per_bar, notes = sorted_notes(), swing = swing, gain_db = gain_db,
		instrument = AK._hashable(instrument)}
