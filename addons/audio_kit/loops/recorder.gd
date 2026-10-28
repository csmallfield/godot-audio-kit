# SPDX-License-Identifier: Apache-2.0
@tool
## Records notes played along with a song into a take: an AKLoop that
## doesn't repeat, placed on the timeline at the bar of its first note.
##
##   var r := AKRecorder.new()
##   r.start(arrangement.tempo, kit, origin_frame, 0.0)   # song time 0 s plays at origin_frame
##   r.note_on(36, 0.9, frame) ... r.note_off(36, frame) ... r.sustain(true, frame)
##   r.stop(frame)
##   var t := r.take("verse_drums")     # {loop, bar, bars}, or {} when nothing was played
##
## Frames are the mixer's (AK.sample_rate), as heard: the caller corrects
## for output latency (AKLive.heard_frame). Notes are kept in ticks from bar
## 0 of the song (96 a beat), rounded to the nearest tick. For a kit, MIDI
## notes map to pieces by the General MIDI drum names (36 kick, 38 snare,
## 42 closed hat ...), falling back to pad order from note 36.
class_name AKRecorder
extends RefCounted

## General MIDI drum notes to the piece names the kit's kits use.
const GM_DRUMS := {35: "kick", 36: "kick", 37: "rim", 38: "snare", 39: "clap", 40: "snare",
	41: "tom_low", 42: "closed_hat", 43: "tom_low", 44: "pedal_hat", 45: "tom_mid", 46: "open_hat",
	47: "tom_mid", 48: "tom_high", 49: "crash", 50: "tom_high", 51: "ride", 52: "crash", 53: "ride",
	54: "shaker", 55: "crash", 56: "rim", 57: "crash", 59: "ride", 69: "shaker", 70: "shaker", 82: "shaker"}
## Other names a kit's piece may go by.
const ALIASES := {closed_hat = ["hat", "hihat", "hh", "chh"], open_hat = ["ohh", "open"], pedal_hat = ["closed_hat", "hat"],
	kick = ["bd", "bass_drum"], snare = ["sd"], clap = ["snare"], rim = ["rimshot", "stick", "snare"],
	tom_low = ["tom", "low_tom"], tom_mid = ["tom", "mid_tom"], tom_high = ["tom", "high_tom"],
	crash = ["cymbal", "ride"], ride = ["crash", "cymbal"], shaker = ["perc", "tamb"]}
const TPB := AKLoop.TICKS_PER_BEAT

var tempo: AKTempoMap
## What the take plays: an AKPatch, an AKSample or an AKKit.
var instrument: Resource
## "synth", "sample" or "percussive", from the instrument.
var kind := "synth"
## The mixer frame at which song time `origin_s` is heard.
var origin_frame := 0
var origin_s := 0.0
## Notes starting before this tick (less a 32nd) are dropped; just before
## it, they start on it (a pickup in the count-in).
var punch_tick := 0
var recording := false
## Finished notes: [start tick, length ticks, row, velocity], ticks from bar 0.
var notes: Array = []

var _held := {}        # MIDI note -> [start tick, row, velocity]
var _pedal := false
var _pedal_held := {}  # MIDI note -> [start tick, row, velocity, end tick]


static func kind_of(inst: Resource) -> String:
	if inst is AKKit:
		return "percussive"
	if inst is AKSample:
		return "sample"
	return "synth"


## Start a take: song time `p_origin_s` is heard at mixer frame `p_origin_frame`.
func start(p_tempo: AKTempoMap, p_instrument: Resource, p_origin_frame: int, p_origin_s := 0.0, p_punch_bar := 0.0) -> void:
	tempo = p_tempo
	instrument = p_instrument
	kind = kind_of(p_instrument)
	origin_frame = p_origin_frame
	origin_s = p_origin_s
	punch_tick = roundi(tempo.beats_at_bar(p_punch_bar) * TPB)
	notes.clear()
	_held.clear()
	_pedal_held.clear()
	_pedal = false
	recording = true


## The song tick (fractional) heard at mixer frame `frame`.
func frame_to_tick(frame: float) -> float:
	var s := origin_s + (frame - float(origin_frame)) / float(AK.sample_rate)
	return tempo.beats_at_bar(tempo.seconds_to_bar(s)) * TPB if s >= 0.0 else s * TPB / tempo.seconds_per_beat_at(0.0)


## The row a MIDI note plays: the note itself, or a kit's piece (-1: none).
func row_for(note: int) -> int:
	return kit_row(instrument as AKKit, note) if kind == "percussive" else note


## The piece of `kit` a MIDI note plays: by its General MIDI drum name (or a
## similar name), else by pad order from note 36; -1 for an empty kit.
static func kit_row(kit: AKKit, note: int) -> int:
	if kit == null or kit.piece_count() == 0:
		return -1
	if GM_DRUMS.has(note):
		var want: String = GM_DRUMS[note]
		var i := kit.find_piece(want)
		if i >= 0:
			return i
		for alt: String in ALIASES.get(want, []):
			i = kit.find_piece(alt)
			if i >= 0:
				return i
	return posmod(note - 36, kit.piece_count())


func note_on(note: int, velocity: float, frame: float) -> void:
	if not recording:
		return
	var t := roundi(frame_to_tick(frame))
	_close(note, t)
	var row := row_for(note)
	if row < 0:
		return
	_held[note] = [t, row, snappedf(clampf(velocity, 0.0, 1.0), 0.001)]


func note_off(note: int, frame: float) -> void:
	if not recording or not _held.has(note):
		return
	var t := roundi(frame_to_tick(frame))
	var h: Array = _held[note]
	_held.erase(note)
	if _pedal:
		_pedal_held[note] = [h[0], h[1], h[2], t]
	else:
		_finish(h[0], t, h[1], h[2])


func sustain(down: bool, frame: float) -> void:
	if not recording:
		return
	_pedal = down
	if down:
		return
	var t := roundi(frame_to_tick(frame))
	for n in _pedal_held.keys():
		var h: Array = _pedal_held[n]
		_finish(h[0], t, h[1], h[2])
	_pedal_held.clear()


## End the take: notes still held (or held by the pedal) end at `frame`.
func stop(frame: float) -> void:
	if not recording:
		return
	var t := roundi(frame_to_tick(frame))
	for n in _held.keys():
		var h: Array = _held[n]
		_finish(h[0], t, h[1], h[2])
	for n in _pedal_held.keys():
		var h: Array = _pedal_held[n]
		_finish(h[0], t, h[1], h[2])
	_held.clear()
	_pedal_held.clear()
	recording = false


## The take as a loop: from the bar of its first note to the end of the bar
## of its last, in `{loop, bar, bars}` (bars of the song); {} when empty.
func take(take_name := "take") -> Dictionary:
	if notes.is_empty():
		return {}
	var sorted := notes.duplicate()
	sorted.sort()
	var first := int(sorted[0][0])
	var last := 0
	for n: Array in sorted:
		last = maxi(last, int(n[0]) + int(n[1]))
	var start_bar := floorf(_tick_to_bar(first) + 1e-9)
	var end_bar := maxf(start_bar + 1.0, ceilf(_tick_to_bar(last) - 1e-9))
	var bpb := roundi(tempo.beats_per_bar_at(start_bar))
	var base := roundi(tempo.beats_at_bar(start_bar) * TPB)
	var l := AKLoop.new()
	l.kind = kind
	l.instrument = instrument
	l.beats_per_bar = bpb
	l.bars = roundi(end_bar - start_bar)
	l.category = "take"
	l.resource_name = take_name
	for n: Array in sorted:
		l.notes.append([int(n[0]) - base, int(n[1]), int(n[2]), float(n[3])])
	return {loop = l, bar = start_bar, bars = end_bar - start_bar}


func _tick_to_bar(tick: int) -> float:
	# Inverse of beats_at_bar, through seconds (the tempo map knows both).
	return tempo.seconds_to_bar(tempo.beat_to_seconds(float(tick) / TPB))


func _close(note: int, t: int) -> void:
	if _held.has(note):
		var h: Array = _held[note]
		_finish(h[0], t, h[1], h[2])
		_held.erase(note)
	if _pedal_held.has(note):
		var h: Array = _pedal_held[note]
		_finish(h[0], t, h[1], h[2])
		_pedal_held.erase(note)


func _finish(start: int, end: int, row: int, velocity: float) -> void:
	if start < punch_tick - TPB / 8:
		return
	start = maxi(start, punch_tick)
	notes.append([start, maxi(1, end - start), row, velocity])
