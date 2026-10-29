# SPDX-License-Identifier: Apache-2.0
@tool
## Records notes played along with a song into a take: an AKLoop that
## doesn't repeat, placed on the timeline at the bar of its first note (or,
## going round a cycle, an AKLoop of the cycle's bars).
##
##   var r := AKRecorder.new()
##   r.start(arrangement.tempo, kit, origin_frame, 0.0)   # song time 0 s is heard at origin_frame
##   r.note_on(36, 0.9, frame) ... r.note_off(36, frame) ... r.sustain(true, frame)
##   r.stop(frame)
##   var t := r.take("verse_drums")     # {loop, bar, bars}, or {} when nothing was played
##
## Frames are the mixer's (AK.sample_rate), as heard: the caller corrects
## for output latency (AKLive.heard_frame). Notes are kept in ticks from bar
## 0 of the song (96 a beat), rounded to the nearest tick. For a kit, MIDI
## notes map to pieces by the General MIDI drum names (36 kick, 38 snare,
## 42 closed hat ...), falling back to pad order from note 36.
##
## Cycle recording (`cycle_bars` > 0): the music goes round bars
## [cycle_from_bar, cycle_from_bar + cycle_bars) and every pass lands in
## the same span; `replace` clears earlier passes once a new pass has a
## note. The cycle's tempo is taken as constant.
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
## The cycle: from bar, bars (0 = none), replace.
var cycle_from_bar := 0.0
var cycle_bars := 0.0
var replace := false
## The pass of each finished note (cycle recording), as `notes`.
var passes: Array[int] = []
## Controller moves: [tick (unwrapped), "bend" | "mod_wheel", value, pass].
var moves: Array = []

var _held := {}        # MIDI note -> [start tick (unwrapped), row, velocity]
var _pedal := false
var _pedal_held := {}  # MIDI note -> [start tick (unwrapped), row, velocity]
var _from_tick := 0.0
var _len_ticks := 0.0
var _from_s := 0.0
var _spb := 0.5
var _latest_pass := -1


static func kind_of(inst: Resource) -> String:
	if inst is AKKit:
		return "percussive"
	if inst is AKSample:
		return "sample"
	return "synth"


## Start a take: song time `p_origin_s` is heard at mixer frame `p_origin_frame`.
func start(p_tempo: AKTempoMap, p_instrument: Resource, p_origin_frame: int, p_origin_s := 0.0, p_punch_bar := 0.0,
		p_cycle_from_bar := 0.0, p_cycle_bars := 0.0, p_replace := false) -> void:
	tempo = p_tempo
	instrument = p_instrument
	kind = kind_of(p_instrument)
	origin_frame = p_origin_frame
	origin_s = p_origin_s
	cycle_from_bar = p_cycle_from_bar
	cycle_bars = maxf(0.0, p_cycle_bars)
	replace = p_replace
	if cycle_bars > 0.0:
		_from_tick = tempo.beats_at_bar(cycle_from_bar) * TPB
		_len_ticks = tempo.beats_at_bar(cycle_from_bar + cycle_bars) * TPB - _from_tick
		_from_s = tempo.bar_to_seconds(cycle_from_bar)
		_spb = tempo.seconds_per_beat_at(cycle_from_bar)
		punch_tick = roundi(_from_tick)
	else:
		punch_tick = roundi(tempo.beats_at_bar(p_punch_bar) * TPB)
	notes.clear()
	passes.clear()
	moves.clear()
	_held.clear()
	_pedal_held.clear()
	_pedal = false
	_latest_pass = -1
	recording = true


func is_cycle() -> bool:
	return cycle_bars > 0.0


## The song tick (fractional) heard at mixer frame `frame`; going round a
## cycle, the tick in the cycle.
func frame_to_tick(frame: float) -> float:
	return _wrap(_unwrapped(frame))


## An unwrapped tick (as `moves` keep them) wrapped into the cycle.
func wrap_tick(unwrapped_tick: float) -> float:
	return _wrap(unwrapped_tick)


## The mixer frame at which (unwrapped) song beat `beat` is heard.
func beat_frame(beat: float) -> float:
	var s := tempo.beat_to_seconds(beat)
	if is_cycle():
		s = _from_s + (beat - _from_tick / TPB) * _spb
	return float(origin_frame) + (s - origin_s) * float(AK.sample_rate)


## Which pass round the cycle mixer frame `frame` is in (0 first; 0 without a cycle).
func pass_at(frame: float) -> int:
	if not is_cycle():
		return 0
	return maxi(0, floori((_unwrapped(frame) - _from_tick) / _len_ticks))


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
	var t := _unwrapped(frame)
	_close(note, t)
	var row := row_for(note)
	if row < 0:
		return
	if is_cycle() and replace:
		var p := floori((t - _from_tick) / _len_ticks)
		if p > _latest_pass and t >= _from_tick - TPB / 8.0:
			for i in range(notes.size() - 1, -1, -1):
				if passes[i] < p:
					notes.remove_at(i)
					passes.remove_at(i)
			moves = moves.filter(func(m: Array) -> bool: return int(m[3]) >= p)
			_latest_pass = p
	_held[note] = [t, row, snappedf(clampf(velocity, 0.0, 1.0), 0.001)]


func note_off(note: int, frame: float) -> void:
	if not recording or not _held.has(note):
		return
	var t := _unwrapped(frame)
	var h: Array = _held[note]
	_held.erase(note)
	if _pedal:
		_pedal_held[note] = h
	else:
		_finish(h[0], t, h[1], h[2])


func sustain(down: bool, frame: float) -> void:
	if not recording:
		return
	_pedal = down
	if down:
		return
	var t := _unwrapped(frame)
	for n in _pedal_held.keys():
		var h: Array = _pedal_held[n]
		_finish(h[0], t, h[1], h[2])
	_pedal_held.clear()


## A controller move: "bend" (-1..1) or "mod_wheel" (0..1), as played.
## Moves before the punch-in count from it (the take starts bent).
func control(kind_name: String, value: float, frame: float) -> void:
	if not recording:
		return
	var v := snappedf(value, 0.001)
	var seen := false
	for i in range(moves.size() - 1, -1, -1):
		if String(moves[i][1]) == kind_name:
			if is_equal_approx(float(moves[i][2]), v):
				return
			seen = true
			break
	if not seen and is_zero_approx(v):
		return   # at rest: nothing to keep
	var t := maxf(_unwrapped(frame), float(punch_tick))
	var p := maxi(0, floori((t - _from_tick) / _len_ticks)) if is_cycle() else 0
	moves.append([t, kind_name, v, p])


## End the take: notes still held (or held by the pedal) end at `frame`.
func stop(frame: float) -> void:
	if not recording:
		return
	var t := _unwrapped(frame)
	for n in _held.keys():
		var h: Array = _held[n]
		_finish(h[0], t, h[1], h[2])
	for n in _pedal_held.keys():
		var h: Array = _pedal_held[n]
		_finish(h[0], t, h[1], h[2])
	_held.clear()
	_pedal_held.clear()
	recording = false


## The take as a loop in `{loop, bar, bars}` (bars of the song): from the
## bar of its first note to the end of the bar of its last; going round a
## cycle, the cycle's bars. {} when nothing was played.
func take(take_name := "take") -> Dictionary:
	if notes.is_empty():
		return {}
	var sorted := notes.duplicate()
	sorted.sort()
	var start_bar := cycle_from_bar
	var end_bar := cycle_from_bar + cycle_bars
	if not is_cycle():
		var last := 0
		for n: Array in sorted:
			last = maxi(last, int(n[0]) + int(n[1]))
		start_bar = floorf(_tick_to_bar(int(sorted[0][0])) + 1e-9)
		end_bar = maxf(start_bar + 1.0, ceilf(_tick_to_bar(last) - 1e-9))
	var base := roundi(tempo.beats_at_bar(start_bar) * TPB)
	var l := AKLoop.new()
	l.kind = kind
	l.instrument = instrument
	l.beats_per_bar = roundi(tempo.beats_per_bar_at(start_bar))
	l.bars = maxi(1, roundi(end_bar - start_bar))
	l.category = "take"
	l.resource_name = take_name
	for n: Array in sorted:
		l.notes.append([int(n[0]) - base, int(n[1]), int(n[2]), float(n[3])])
	if kind == "synth" and not moves.is_empty():
		var span := l.length_ticks()
		for m: Array in moves:
			var t := roundi(_wrap(float(m[0]))) - base
			var k := String(m[1])
			var pts: Array = l.controls.get(k, [])
			if t < 0:
				pts = pts.filter(func(q: Array) -> bool: return int(q[0]) > 0)
				pts.push_front([0, float(m[2])])
			elif t < span:
				pts.append([t, float(m[2])])
			l.controls[k] = pts
		for k in l.controls:
			(l.controls[k] as Array).sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return {loop = l, bar = start_bar, bars = end_bar - start_bar}


func _unwrapped(frame: float) -> float:
	var s := origin_s + (frame - float(origin_frame)) / float(AK.sample_rate)
	if is_cycle():
		return _from_tick + (s - _from_s) / _spb * TPB
	if s < 0.0:
		return s * TPB / tempo.seconds_per_beat_at(0.0)
	return tempo.beats_at_bar(tempo.seconds_to_bar(s)) * TPB


func _wrap(t: float) -> float:
	if not is_cycle() or t < _from_tick:
		return t
	return _from_tick + fposmod(t - _from_tick, _len_ticks)


func _tick_to_bar(tick: int) -> float:
	# Inverse of beats_at_bar, through seconds (the tempo map knows both).
	return tempo.seconds_to_bar(tempo.beat_to_seconds(float(tick) / TPB))


func _close(note: int, t: float) -> void:
	if _held.has(note):
		var h: Array = _held[note]
		_finish(h[0], t, h[1], h[2])
		_held.erase(note)
	if _pedal_held.has(note):
		var h: Array = _pedal_held[note]
		_finish(h[0], t, h[1], h[2])
		_pedal_held.erase(note)


func _finish(start_u: float, end_u: float, row: int, velocity: float) -> void:
	if start_u < punch_tick - TPB / 8.0:
		return
	var p := 0
	var start := roundi(maxf(start_u, float(punch_tick)))
	var length := maxi(1, roundi(end_u) - roundi(start_u))
	if is_cycle():
		p = maxi(0, floori((start_u - _from_tick) / _len_ticks))
		if replace and p < _latest_pass:
			return
		start = roundi(_wrap(maxf(start_u, _from_tick)))
		if start >= roundi(_from_tick + _len_ticks):
			start = roundi(_from_tick)
		length = mini(length, roundi(_len_ticks))
	notes.append([start, length, row, velocity])
	passes.append(p)
