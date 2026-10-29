# SPDX-License-Identifier: Apache-2.0
@tool
## Musical time: tempo, meter and tempo changes, converting bars and beats to
## seconds. Authored, never detected, so it is exact and deterministic.
##
## Bars and beats count from 0 (bar 0 beat 0 is the downbeat at `offset_s`).
## A beat is one `bpm` count; `beats_per_bar` sets the meter.
@icon("res://addons/audio_kit/icons/palette.svg")
class_name AKTempoMap
extends Resource

@export var bpm := 120.0
@export var beats_per_bar := 4
## Time of the first downbeat (bar 0), in seconds. Negative starts the music
## before the piece's time zero.
@export var offset_s := 0.0
## Later changes: [{bar = 8, bpm = 140.0, beats_per_bar = 3}, ...], each from
## the start of that bar (a fractional bar puts a change mid-bar; a change's
## beats_per_bar may be fractional, e.g. 3.5 quarter beats for 7/8). Each from
## the start of that bar. Tempo jumps (no ramps).
@export var changes: Array[Dictionary] = []


static func make(p_bpm: float, p_beats_per_bar := 4, p_offset_s := 0.0) -> AKTempoMap:
	var t := AKTempoMap.new()
	t.bpm = p_bpm
	t.beats_per_bar = p_beats_per_bar
	t.offset_s = p_offset_s
	return t


## Segments [{bar, bpm, bpb, start_s}], sorted, starting at bar 0.
func segments() -> Array:
	var segs := [{bar = 0.0, bpm = bpm, bpb = float(beats_per_bar), start_s = offset_s}]
	var sorted := changes.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.bar) < float(b.bar))
	for c in sorted:
		var last: Dictionary = segs[segs.size() - 1]
		var at := float(c.bar)
		if at <= last.bar:
			last.bpm = float(c.get("bpm", last.bpm))
			last.bpb = float(c.get("beats_per_bar", last.bpb))
			continue
		var start := float(last.start_s) + (at - float(last.bar)) * float(last.bpb) * 60.0 / float(last.bpm)
		segs.append({bar = at, bpm = float(c.get("bpm", last.bpm)), bpb = float(c.get("beats_per_bar", last.bpb)), start_s = start})
	return segs


## Seconds at a (fractional) bar.
func bar_to_seconds(bar: float) -> float:
	var seg: Dictionary = _segment_for_bar(bar)
	return float(seg.start_s) + (bar - float(seg.bar)) * float(seg.bpb) * 60.0 / float(seg.bpm)


## Seconds at bar `bar` plus `beat` beats (beats may run past the bar).
func to_seconds(bar: float, beat := 0.0) -> float:
	var seg: Dictionary = _segment_for_bar(bar)
	return bar_to_seconds(bar) + beat * 60.0 / float(seg.bpm)


## The (fractional) bar playing at `seconds`.
func seconds_to_bar(seconds: float) -> float:
	var segs := segments()
	var seg: Dictionary = segs[0]
	for s in segs:
		if seconds >= float(s.start_s):
			seg = s
	return float(seg.bar) + (seconds - float(seg.start_s)) * float(seg.bpm) / (60.0 * float(seg.bpb))


## Beats from bar 0 to the (fractional) bar `bar`, across meter changes.
func beats_at_bar(bar: float) -> float:
	var segs := segments()
	var beats := 0.0
	for i in segs.size():
		var s: Dictionary = segs[i]
		var end_bar: float = float(segs[i + 1].bar) if i + 1 < segs.size() else INF
		if bar <= float(s.bar):
			break
		beats += (minf(bar, end_bar) - float(s.bar)) * float(s.bpb)
	return beats


## Seconds at `beat` beats from bar 0, following every tempo change (where
## `to_seconds` uses the tempo of the bar it starts from).
func beat_to_seconds(beat: float) -> float:
	var segs := segments()
	var start_beat := 0.0
	for i in segs.size():
		var s: Dictionary = segs[i]
		var seg_beats: float = (float(segs[i + 1].bar) - float(s.bar)) * float(s.bpb) if i + 1 < segs.size() else INF
		if beat < start_beat + seg_beats or i == segs.size() - 1:
			return float(s.start_s) + (beat - start_beat) * 60.0 / float(s.bpm)
		start_beat += seg_beats
	return offset_s


func seconds_per_beat_at(bar: float) -> float:
	return 60.0 / float(_segment_for_bar(bar).bpm)


func beats_per_bar_at(bar: float) -> float:
	return float(_segment_for_bar(bar).bpb)


func _segment_for_bar(bar: float) -> Dictionary:
	var segs := segments()
	var seg: Dictionary = segs[0]
	for s in segs:
		if bar >= float(s.bar):
			seg = s
	return seg
