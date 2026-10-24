# SPDX-License-Identifier: Apache-2.0
@tool
## Plays patches from a MIDI keyboard (or from code): MIDI in, sound out.
##
##   var r := AKMidiRouter.new()
##   r.patch = load("res://addons/audio_kit/patches/saw_lead.tres")
##   add_child(r)                 # opens the MIDI inputs and starts listening
##   r.note_on(60, 0.8)           # or play it from code / an on-screen keyboard
##
## Every channel gets its own AKSynthStream on an AudioStreamPlayer (on
## `bus`), so the sound goes through Godot's mixer like any other. Notes,
## velocity, pitch bend, the mod wheel (CC 1), the sustain pedal (CC 64),
## channel pressure and all-notes-off (CC 120/123) reach the engine.
## Program changes pick the bank's patch for the program when `bank` is set.
## Channel 10 plays the bank's drum recipes (baked, so drums work without
## the native core); melodic channels need the native core.
class_name AKMidiRouter
extends Node

signal note_started(channel: int, note: int, velocity: float)
signal note_stopped(channel: int, note: int)
signal controller_changed(channel: int, number: int, value: int)

## The patch every melodic channel plays unless `channel_patches` names one.
@export var patch: AKPatch:
	set(v):
		patch = v
		for ch in _synths:
			if not channel_patches.has(ch + 1):
				_apply_patch(ch)
## Channel (1-16) -> AKPatch or path, overriding `patch`.
@export var channel_patches: Dictionary = {}
## For program changes and channel 10 drums. Empty: the shipped GM bank.
@export var bank: AKBank
## Follow program changes (pick the bank's patch for the program).
@export var follow_program_changes := true
## Ignore the channel: every note plays `patch` on one synth.
@export var omni := true
## Godot bus the sound goes to.
@export var bus: StringName = &"Master"
@export var volume_db := 0.0
## Call OS.open_midi_inputs() when added to the tree.
@export var open_inputs := true
## Velocity response: 1 linear, below 1 lifts soft playing, above 1 needs more force.
@export_range(0.2, 3.0) var velocity_curve := 1.0
## Listen to InputEventMIDI (off: only note_on()/note_off() from code).
@export var listen := true

var _synths := {}   # channel (0-15) -> AKSynthStream
var _players := {}  # channel -> AudioStreamPlayer
var _drums: AudioStreamPlayer
var _drum_cache := {}
var _sounding := {}  # "ch:note" -> true


func _ready() -> void:
	if open_inputs and listen:
		OS.open_midi_inputs()
	set_process_input(listen)


func _exit_tree() -> void:
	for ch in _synths:
		_synths[ch].call(&"panic")


## The MIDI inputs the OS reports.
static func devices() -> PackedStringArray:
	return OS.get_connected_midi_inputs()


func _input(event: InputEvent) -> void:
	if listen and event is InputEventMIDI:
		handle(event as InputEventMIDI)


## Handle one MIDI event (what _input does; call it with your own events).
func handle(e: InputEventMIDI) -> void:
	var ch := e.channel
	match e.message:
		MIDI_MESSAGE_NOTE_ON:
			if e.velocity > 0:
				note_on(e.pitch, float(e.velocity) / 127.0, ch + 1)
			else:
				note_off(e.pitch, ch + 1)
		MIDI_MESSAGE_NOTE_OFF:
			note_off(e.pitch, ch + 1)
		MIDI_MESSAGE_PITCH_BEND:
			# Godot puts the 14-bit bend value (0..16383, 8192 = centre) in `pitch`.
			_synth_call(ch, &"set_bend", [clampf((e.pitch - 8192) / 8192.0, -1.0, 1.0)])
		MIDI_MESSAGE_CHANNEL_PRESSURE:
			_synth_call(ch, &"set_aftertouch", [e.pressure / 127.0])
		MIDI_MESSAGE_CONTROL_CHANGE:
			controller(e.controller_number, e.controller_value, ch + 1)
		MIDI_MESSAGE_PROGRAM_CHANGE:
			program_change(e.instrument, ch + 1)


## Start a note (velocity 0..1) on `channel` 1-16.
func note_on(note: int, velocity := 0.8, channel := 1) -> void:
	var ch := clampi(channel, 1, 16) - 1
	var v := pow(clampf(velocity, 0.0, 1.0), velocity_curve)
	_sounding["%d:%d" % [ch, note]] = true
	note_started.emit(ch + 1, note, v)
	if ch == 9 and not omni:
		_drum(note, v)
		return
	_synth_call(ch, &"note_on", [float(note), v])


func note_off(note: int, channel := 1) -> void:
	var ch := clampi(channel, 1, 16) - 1
	_sounding.erase("%d:%d" % [ch, note])
	note_stopped.emit(ch + 1, note)
	if ch == 9 and not omni:
		return
	_synth_call(ch, &"note_off", [float(note)])


## A control change: 1 mod wheel, 64 sustain, 120/123 all notes off, 7 volume.
func controller(number: int, value: int, channel := 1) -> void:
	var ch := clampi(channel, 1, 16) - 1
	controller_changed.emit(ch + 1, number, value)
	match number:
		1: _synth_call(ch, &"set_mod_wheel", [value / 127.0])
		64: _synth_call(ch, &"set_sustain", [value >= 64])
		120, 123: _synth_call(ch, &"all_notes_off", [])
		7:
			var p: AudioStreamPlayer = _players.get(_key(ch))
			if p:
				p.volume_db = volume_db + (40.0 * log(maxf(1.0, value) / 127.0) / log(10.0) if value < 127 else 0.0)


func program_change(program: int, channel := 1) -> void:
	if not follow_program_changes:
		return
	var ch := clampi(channel, 1, 16) - 1
	var b := _bank()
	if b == null or ch == 9:
		return
	var p := b.patch_for(program)
	if p:
		channel_patches[_key(ch) + 1] = p
		_apply_patch(_key(ch))


func set_sustain(down: bool, channel := 1) -> void:
	controller(64, 127 if down else 0, channel)


func all_notes_off() -> void:
	for ch in _synths:
		_synths[ch].call(&"all_notes_off")
	_sounding.clear()


## Notes held now, as "channel:note" keys.
func sounding() -> Array:
	return _sounding.keys()


## The live synth for `channel` (1-16; with omni, channel 1's), made on first use.
func synth(channel := 1) -> Object:
	return _ensure(_key(clampi(channel, 1, 16) - 1))


# ------------------------------------------------------------------ inside

func _key(ch: int) -> int:
	return 0 if omni else ch


func _synth_call(ch: int, method: StringName, args: Array) -> void:
	var s := _ensure(_key(ch))
	if s:
		s.callv(method, args)


func _ensure(ch: int) -> Object:
	if _synths.has(ch):
		return _synths[ch]
	if not AKSynth.available():
		push_warning("AKMidiRouter: playing patches live needs the native core (native/README.md)")
		return null
	var s: Object = ClassDB.instantiate(&"AKSynthStream")
	_synths[ch] = s
	_apply_patch(ch)
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.bus = bus
	p.volume_db = volume_db
	add_child(p)
	_players[ch] = p
	if p.is_inside_tree():
		p.play()
	return s


func _apply_patch(ch: int) -> void:
	var s: Object = _synths.get(ch)
	if s == null:
		return
	var v: Variant = channel_patches.get(ch + 1, patch)
	var pt: AKPatch = v if v is AKPatch else (load(String(v)) if (v is String and ResourceLoader.exists(v)) else patch)
	if pt == null:
		pt = AKPatch.new()
	s.set(&"patch", pt)


func _bank() -> AKBank:
	if bank == null:
		bank = AKGeneralMidi.default_bank()
	return bank


func _drum(note: int, vel: float) -> void:
	var b := _bank()
	if b == null:
		return
	var d := b.drum_for(note)
	var r: Variant = d.get("recipe")
	var recipe: AKRecipe = r if r is AKRecipe else (load(String(r)) if (r is String and ResourceLoader.exists(r)) else null)
	if recipe == null:
		return
	if _drums == null:
		_drums = AudioStreamPlayer.new()
		_drums.stream = AudioStreamPolyphonic.new()
		(_drums.stream as AudioStreamPolyphonic).polyphony = 16
		_drums.bus = bus
		add_child(_drums)
		if _drums.is_inside_tree():
			_drums.play()
	var wav: AudioStreamWAV = AK.bake(recipe)
	var pb := _drums.get_stream_playback() as AudioStreamPlaybackPolyphonic
	if pb:
		pb.play_stream(wav, 0.0, volume_db + linear_to_db(maxf(vel, 1e-3)))
