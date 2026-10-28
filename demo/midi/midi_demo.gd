# SPDX-License-Identifier: Apache-2.0
# Play the kit from a MIDI keyboard (written against an AKAI MPK Mini Mk II;
# any class-compliant controller works):
#   - the keys play the chosen instrument: 1 / 2 / 3 / 4 on the computer
#     keyboard (or a MIDI program change) pick electric piano, bass, pad or
#     lead, the Last Ferry recipes;
#   - the pads (MIDI notes 36-51, the MPK's two banks) play a drum kit: kick,
#     snare, clap, hat, rim, crash; D turns that off so low keys play notes;
#   - the pitch bend bends held notes two semitones; CC 7 (K7 on the MPK's
#     default map) is the master volume; CC 1 (K1, or the joystick's Y)
#     sweeps the filter on the live mixer.
# With the native core built, notes run on the live mixer as continuous
# voices (oscillators that start, glide and release with the keys) and the
# drums as triggers through the shared reverb. Without it, every note is baked
# once at its pitch (AK.bake, cached in memory) and played on an
# AudioStreamPlayer, and letting go fades the player. The keyboard's default
# two octaves are baked ahead on start; other notes bake on first press.
extends Control

const INSTRUMENTS := {
	"ep": preload("res://demo/song/last_ferry/ep.tres"),
	"bass": preload("res://demo/song/last_ferry/bass.tres"),
	"pad": preload("res://demo/song/last_ferry/pad.tres"),
	"lead": preload("res://demo/song/last_ferry/lead.tres"),
}
const ORDER := ["ep", "bass", "pad", "lead"]
## Release when a key is let go, and what each instrument becomes on the live
## mixer (plain oscillators: the recipes themselves can't run as voices).
const SHAPES := {
	"ep": {shape = "triangle", cutoff_hz = 3000.0, attack_s = 0.005, release_s = 0.35},
	"bass": {shape = "saw", cutoff_hz = 500.0, attack_s = 0.005, release_s = 0.1},
	"pad": {shape = "saw", cutoff_hz = 1100.0, attack_s = 0.6, release_s = 0.9},
	"lead": {shape = "square", cutoff_hz = 2500.0, attack_s = 0.03, release_s = 0.15},
}
const DRUMS := [
	[&"kick", preload("res://demo/music/e1/kick.tres")],
	[&"snare", preload("res://demo/song/last_ferry/snare.tres")],
	[&"clap", preload("res://demo/music/e1/clap.tres")],
	[&"hat", preload("res://demo/music/e1/hat.tres")],
	[&"rim", preload("res://demo/song/last_ferry/rim.tres")],
	[&"crash", preload("res://demo/song/last_ferry/crash.tres")],
]
const PAD_FIRST := 36
const PAD_LAST := 51
## How long a baked note sustains before its own release (seconds held).
const HOLD_S := 3.0
## The MPK's default two octaves, C3..C5: baked ahead on start.
const PREBAKE_FROM := 48
const PREBAKE_TO := 72
const BEND_SEMITONES := 2.0
const POOL := 24

var _instrument := "ep"
var _pads_drums := true
var _bend := 1.0
var _cutoff := -1.0       # live filter from CC 1, 0..1; -1 = the instrument's own
var _volume_db := 0.0
var _last_cc := "none yet"
var _use_live := false
var _lp: AKLivePlayer
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _held := {}           # note -> AudioStreamPlayer (baked) or voice id (live)
var _prebake: Array[int] = []
var _prebake_drums: Array = []
var _label: Label
var _midi_inputs: PackedStringArray


func _ready() -> void:
	OS.open_midi_inputs()
	_midi_inputs = OS.get_connected_midi_inputs()
	_label = Label.new()
	_label.position = Vector2(24, 24)
	add_child(_label)
	_use_live = AKLive.available()
	if _use_live:
		_lp = AKLivePlayer.new()
		var map := AKCueMap.new()
		for d in DRUMS:
			map.sounds[d[0]] = d[1]
		map.master_fx = [{type = &"dcblock"}, {type = &"limit", ceiling_db = -1.5}]
		map.reverb = {room = 0.6, damp = 0.4, width = 1.0, quality = &"small", return_db = -6.0}
		_lp.cue_map = map
		add_child(_lp)
	else:
		for i in POOL:
			var p := AudioStreamPlayer.new()
			add_child(p)
			_players.append(p)
		_prebake_drums = DRUMS.duplicate()
	_queue_prebake()
	_status()


func _exit_tree() -> void:
	OS.close_midi_inputs()


func _process(_delta: float) -> void:
	if _use_live or (_prebake.is_empty() and _prebake_drums.is_empty()):
		return
	# Bake ahead, one or two a frame, so the window stays responsive.
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < 12:
		if not _prebake_drums.is_empty():
			AK.bake(_prebake_drums.pop_front()[1], 1.0)
		elif not _prebake.is_empty():
			_stream_for(_prebake.pop_front())
		else:
			break
	_status()


func _input(e: InputEvent) -> void:
	if e is InputEventMIDI:
		_midi(e)
	elif e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_1:
				_set_instrument("ep")
			KEY_2:
				_set_instrument("bass")
			KEY_3:
				_set_instrument("pad")
			KEY_4:
				_set_instrument("lead")
			KEY_D:
				_pads_drums = not _pads_drums
				_status()


func _midi(e: InputEventMIDI) -> void:
	match e.message:
		MIDI_MESSAGE_NOTE_ON:
			if e.velocity > 0:
				_note_on(e.pitch, e.velocity / 127.0)
			else:
				_note_off(e.pitch)   # some controllers send note-on at 0 for off
		MIDI_MESSAGE_NOTE_OFF:
			_note_off(e.pitch)
		MIDI_MESSAGE_PITCH_BEND:
			_set_bend((e.pitch - 8192) / 8192.0)   # 14-bit, 8192 = centre
		MIDI_MESSAGE_CONTROL_CHANGE:
			_control(e.controller_number, e.controller_value)
		MIDI_MESSAGE_PROGRAM_CHANGE:
			_set_instrument(ORDER[e.instrument % ORDER.size()])
	_status()


# ---------------------------------------------------------------- notes

func _note_on(note: int, vel: float) -> void:
	if _pads_drums and note >= PAD_FIRST and note <= PAD_LAST:
		_drum(note, vel)
		return
	if _held.has(note):
		_note_off(note)
	var hz := AKNotes.midi_to_hz(float(note))
	if _use_live:
		var s: Dictionary = SHAPES[_instrument]
		_held[note] = _lp.live.voice_start({shape = s.shape, freq_hz = hz * _bend, gain = lerpf(0.04, 0.25, vel),
			cutoff_hz = _live_cutoff(), q = 1.2, send = 0.25, attack_s = s.attack_s})
	else:
		var p := _free_player()
		p.stream = _stream_for(note)
		p.volume_db = linear_to_db(lerpf(0.12, 1.0, vel))
		p.pitch_scale = _bend
		p.play()
		_held[note] = p


func _note_off(note: int) -> void:
	if not _held.has(note):
		return
	var h: Variant = _held[note]
	_held.erase(note)
	var rel: float = SHAPES[_instrument].release_s
	if _use_live:
		_lp.live.voice_stop(int(h), rel)
	else:
		_release(h, rel)


func _drum(note: int, vel: float) -> void:
	var d: Array = DRUMS[(note - PAD_FIRST) % DRUMS.size()]
	if _use_live:
		_lp.trigger(d[0], vel)
	else:
		var p := _free_player()
		p.stream = AK.bake(d[1], maxf(0.25, snappedf(vel, 0.25)))   # four velocity layers
		p.volume_db = 0.0
		p.pitch_scale = 1.0
		p.play()


## The instrument baked at this pitch, held HOLD_S then released; cached.
func _stream_for(note: int) -> AudioStreamWAV:
	return AK.bake(INSTRUMENTS[_instrument], 1.0, {}, 0, {_note_hz = AKNotes.midi_to_hz(float(note)), _gate_s = HOLD_S})


func _set_instrument(name: String) -> void:
	if name == _instrument:
		return
	for note in _held.keys():
		_note_off(note)
	_instrument = name
	_queue_prebake()
	_status()


func _queue_prebake() -> void:
	_prebake.assign(range(PREBAKE_FROM, PREBAKE_TO + 1))


# ---------------------------------------------------------------- controls

func _set_bend(x: float) -> void:
	_bend = pow(2.0, clampf(x, -1.0, 1.0) * BEND_SEMITONES / 12.0)
	for note in _held:
		if _use_live:
			_lp.live.voice_set(int(_held[note]), "freq_hz", AKNotes.midi_to_hz(float(note)) * _bend, 0.02)
		else:
			_held[note].pitch_scale = _bend


func _control(cc: int, v: int) -> void:
	_last_cc = "%d = %d" % [cc, v]
	match cc:
		7:
			_volume_db = lerpf(-36.0, 0.0, v / 127.0)
			AudioServer.set_bus_volume_db(0, _volume_db)
		1:
			if _use_live:
				_cutoff = v / 127.0
				for note in _held:
					_lp.live.voice_set(int(_held[note]), "cutoff_hz", _live_cutoff(), 0.05)


func _live_cutoff() -> float:
	if _cutoff < 0.0:
		return float(SHAPES[_instrument].cutoff_hz)
	return 200.0 * pow(40.0, _cutoff)   # 200 Hz .. 8 kHz


# ---------------------------------------------------------------- players

func _free_player() -> AudioStreamPlayer:
	for i in POOL:
		var p := _players[(_next_player + i) % POOL]
		if not p.playing:
			_next_player = (_next_player + i + 1) % POOL
			return _claim(p)
	var p := _players[_next_player]   # all busy: take the oldest
	_next_player = (_next_player + 1) % POOL
	return _claim(p)


func _claim(p: AudioStreamPlayer) -> AudioStreamPlayer:
	if p.has_meta(&"fade"):
		var tw: Tween = p.get_meta(&"fade")
		if tw and tw.is_valid():
			tw.kill()
		p.remove_meta(&"fade")
	var k: Variant = _held.find_key(p)
	if k != null:
		_held.erase(k)
	return p


func _release(p: AudioStreamPlayer, rel: float) -> void:
	var tw := create_tween()
	tw.tween_property(p, "volume_db", -60.0, rel)
	tw.tween_callback(p.stop)
	p.set_meta(&"fade", tw)


# ---------------------------------------------------------------- status

func _status() -> void:
	var lines := PackedStringArray()
	if _midi_inputs.is_empty():
		lines.append("MIDI inputs: none found. Connect the controller, then run the scene again.")
	else:
		lines.append("MIDI inputs: " + ", ".join(_midi_inputs))
	if _use_live:
		lines.append("Engine: native live mixer (continuous voices, triggers, shared reverb)")
	else:
		lines.append("Engine: GDScript, baked notes (the native core isn't built; see native/README.md)")
	lines.append("Instrument: %s    1 ep   2 bass   3 pad   4 lead   (or a MIDI program change)" % _instrument)
	lines.append("Pads (notes %d-%d): %s    D toggles.   kick  snare  clap  hat  rim  crash" % [PAD_FIRST, PAD_LAST, "drums" if _pads_drums else "notes"])
	lines.append("Held: %d    Bend: %+.2f st    Volume (CC 7): %.0f dB    Last CC: %s" % [_held.size(), 12.0 * log(_bend) / log(2.0), _volume_db, _last_cc])
	if not _prebake.is_empty() or not _prebake_drums.is_empty():
		lines.append("Baking ahead: %d notes and %d drums left (anything else bakes on first press)" % [_prebake.size(), _prebake_drums.size()])
	_label.text = "\n".join(lines)
