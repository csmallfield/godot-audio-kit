# SPDX-License-Identifier: Apache-2.0
@tool
## Playing along on a MIDI keyboard, for the Sequencer and the Loops tab:
## hears the keyboard on an instrument (patches through an AKMidiRouter, kit
## pieces and sample notes on the live mixer), clicks a metronome, and takes
## notes down into an AKRecorder while recording.
##
##   along.live = live; along.instrument = kit
##   along.listen(true)                      # the keyboard plays the instrument
##   along.start_take(tempo, origin_frame, origin_s, punch_bar)   # and is recorded
##   along.count_in(4, 0.5, 4)               # four clicks before the music
##   ... along.stop_take() -> the AKRecorder
##
## Notes are timed by `clock` (the frame heard when the key went down; tests
## replace it). See docs/plans/recording.md.
class_name AKPlayAlong
extends Node

## A note was taken down (the recorder's `notes` grew).
signal note_taken()

var live: AKLive
## What the keyboard plays: an AKPatch, AKKit or AKSample.
var instrument: Resource:
	set(v):
		instrument = v
		if v is AKPatch and router and router.patch != v:
			router.patch = v
var router: AKMidiRouter
## The mixer frame a note was heard at.
var clock: Callable
## Notes are placed this much earlier than heard (a MIDI interface's delay, habit).
var latency_ms := 0.0
## A metronome while recording.
var click := true
## Off: listening doesn't open the OS's MIDI inputs (tests, headless).
var open_midi := true
var recorder: AKRecorder
var listening := false
## Play notes on the live mixer once a buffer: buffer -> stream id. Clear it
## whenever the live stream is cleared.
var ids := {}

var _bufs := {}
var _tempo: AKTempoMap
var _next_beat := 0.0
var _low_proc := true
var _ending := 0.0          # cycle: song beats where the range ends (0 = none)
var _cycle_from := 0.0      # cycle: song beats where it starts


func _init() -> void:
	router = AKMidiRouter.new()
	router.open_inputs = false
	router.listen = false
	add_child(router)
	clock = func() -> float: return live.heard_frame() - latency_ms * AK.sample_rate / 1000.0 if live else 0.0
	set_process_input(false)


## Listen to the keyboard (opening the OS's MIDI inputs) or stop.
func listen(on: bool) -> void:
	listening = on
	set_process_input(on)
	if on and open_midi:
		OS.open_midi_inputs()
	if not on:
		router.all_notes_off()


## The connected MIDI inputs, as a line for a label.
func devices_text() -> String:
	if not listening:
		return ""
	var d := AKMidiRouter.devices() if open_midi else PackedStringArray()
	return "MIDI in: " + (", ".join(d) if not d.is_empty() else "no devices")


func is_recording() -> bool:
	return recorder != null and recorder.recording


## Start taking notes down: song time `origin_s` is heard at `origin_frame`.
## `cycle_from_bar`/`cycle_bars` (bars > 0): the music goes round that range
## and each pass layers onto the take (`replace`: a pass with notes clears
## the passes before it).
func start_take(tempo: AKTempoMap, origin_frame: int, origin_s: float, punch_bar := 0.0, cycle_from_bar := 0.0, cycle_bars := 0.0, replace := false) -> AKRecorder:
	recorder = AKRecorder.new()
	recorder.start(tempo, instrument, origin_frame, origin_s, punch_bar, cycle_from_bar, cycle_bars, replace)
	_tempo = tempo
	_next_beat = tempo.beats_at_bar(punch_bar if cycle_bars <= 0.0 else cycle_from_bar)
	_cycle_from = tempo.beats_at_bar(cycle_from_bar) if cycle_bars > 0.0 else 0.0
	_ending = tempo.beats_at_bar(cycle_from_bar + cycle_bars) if cycle_bars > 0.0 else 0.0
	_low_proc = OS.low_processor_usage_mode
	OS.low_processor_usage_mode = false
	schedule_clicks()
	return recorder


## Finish the take (held notes end now) and return the recorder.
func stop_take() -> AKRecorder:
	if recorder and recorder.recording:
		recorder.stop(float(clock.call()))
		OS.low_processor_usage_mode = _low_proc
	router.all_notes_off()
	return recorder


## `beats` clicks `beat_s` apart from now (accents every `per_bar`).
func count_in(beats: int, beat_s: float, per_bar: int) -> void:
	for i in beats:
		play_buffer(click_buffer(i % maxi(1, per_bar) == 0), -6.0, i * beat_s)


func _process(_delta: float) -> void:
	if is_recording():
		schedule_clicks()


func _input(event: InputEvent) -> void:
	if listening and event is InputEventMIDI:
		handle_midi(event)


## A MIDI message: notes, the sustain pedal, and (for patches) bend, mod
## wheel and the rest through the router.
func handle_midi(e: InputEventMIDI) -> void:
	match e.message:
		MIDI_MESSAGE_NOTE_ON:
			if e.velocity > 0:
				note_pressed(e.pitch, e.velocity / 127.0)
			else:
				note_released(e.pitch)
		MIDI_MESSAGE_NOTE_OFF:
			note_released(e.pitch)
		MIDI_MESSAGE_CONTROL_CHANGE:
			if e.controller_number == 64:
				pedal(e.controller_value >= 64)
			elif instrument is AKPatch:
				router.handle(e)
		_:
			if instrument is AKPatch and e.message != MIDI_MESSAGE_PROGRAM_CHANGE:
				router.handle(e)


func note_pressed(note: int, velocity: float) -> void:
	if is_recording():
		recorder.note_on(note, velocity, float(clock.call()))
	_monitor(note, velocity)


func note_released(note: int) -> void:
	if is_recording():
		var n := recorder.notes.size()
		recorder.note_off(note, float(clock.call()))
		if recorder.notes.size() != n:
			note_taken.emit()
	if instrument is AKPatch:
		router.note_off(note)


func pedal(down: bool) -> void:
	if is_recording():
		var n := recorder.notes.size()
		recorder.sustain(down, float(clock.call()))
		if recorder.notes.size() != n:
			note_taken.emit()
	if instrument is AKPatch:
		router.set_sustain(down)


func _monitor(note: int, velocity: float) -> void:
	if instrument is AKPatch:
		if router.patch != instrument:
			router.patch = instrument
		router.note_on(note, velocity)
		return
	if live == null or instrument == null:
		return
	var vb := roundi(clampf(velocity, 0.0, 1.0) * 8.0)
	var key := [instrument.get_instance_id(), note, vb]
	var buf: AKBuffer = _bufs.get(key)
	if buf == null:
		var r: AKRecipe = null
		var ov := {}
		if instrument is AKKit:
			var row := AKRecorder.kit_row(instrument, note)
			r = (instrument as AKKit).piece_recipe(row) if row >= 0 else null
		elif instrument is AKSample:
			r = (instrument as AKSample).to_recipe()
			ov = {_note_hz = AKNotes.midi_to_hz(note), _gate_s = 0.6}
		if r == null:
			return
		buf = AK.render(r, maxf(0.05, vb / 8.0), {}, 0, ov)
		_bufs[key] = buf
	play_buffer(buf, 0.0, 0.0)


## Play a buffer on the live mixer `delay_s` from now, adding it to the
## stream once.
func play_buffer(buf: AKBuffer, gain_db: float, delay_s: float) -> void:
	if live == null or buf == null:
		return
	if not ids.has(buf):
		ids[buf] = live.stream.add_buffer(buf.l, buf.r)
	var g := AKDsp.db_to_gain(gain_db)
	live.stream.play_now(ids[buf], g, g, 0.0, roundi(maxf(0.0, delay_s) * AK.sample_rate))


func click_buffer(accent: bool) -> AKBuffer:
	var key := "click_hi" if accent else "click"
	if not _bufs.has(key):
		var r := AKRecipe.make(&"tone", {wave = "sine", freq_hz = 1760.0 if accent else 1320.0, attack_s = 0.001, decay_s = 0.03, sustain = 0.0, gate_s = 0.03, release_s = 0.02})
		_bufs[key] = AK.render(r)
	return _bufs[key]


## Metronome clicks for the beats coming up (while recording; going round
## the cycle when there is one).
func schedule_clicks() -> void:
	if not click or recorder == null or live == null or _tempo == null:
		return
	var horizon := float(live.get_frame()) + live.lookahead_s * AK.sample_rate
	var guard := 0
	while guard < 64:
		guard += 1
		var beat := _next_beat
		var f := recorder.beat_frame(beat)
		if f > horizon:
			break
		var song_beat := beat
		if _ending > 0.0:
			song_beat = _cycle_from + fposmod(beat - _cycle_from, _ending - _cycle_from)
		var bar := _tempo.seconds_to_bar(_tempo.beat_to_seconds(song_beat))
		var accent := absf(bar - roundf(bar)) < 1e-6
		var delay := (f - float(live.get_frame())) / AK.sample_rate
		if delay >= -0.005:
			play_buffer(click_buffer(accent), -6.0, delay)
		_next_beat += 1.0
