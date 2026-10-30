# SPDX-License-Identifier: Apache-2.0
## A character who speaks pseudo-speech in a game: give it a voice, call
## say(), hook its signals to subtitles, a mouth or a bounce.
##
##   $Speaker.voice = load("res://addons/audio_kit/speech/voices/critter.tres")
##   $Speaker.word_started.connect(func(i, word): $Subtitle.highlight(i))
##   $Speaker.line_finished.connect(func(_line): $Subtitle.hide())
##   $Speaker.say("Hey! Where did you come *from*?")
##   ...
##   $Mouth.scale.y = 0.2 + $Speaker.mouth()     # every frame: open on syllables
##
## Live or baked (`mode`):
##   live   the line is scheduled on an AKSynthStream (the native core's synth)
##          a few ms ahead and starts at once, whatever its length: for
##          player-typed text and barks. Onsets play beside it, pre-rendered.
##   baked  the line is rendered whole, then played (and cached by its text and
##          voice): for anything without the native core, scratch voices,
##          and when every line must match its bake exactly.
##   auto   live when the native core is there and the voice uses a patch;
##          baked otherwise.
## Both play the same engine, so a live line sounds as its bake does. (A
## voice's effects run on the live synth and on the onsets apart, so a
## growl or ring modulator's swing can fall a little differently.)
##
## Signals come from the line's syllable timings against what has been heard
## (the playback position, less the audio output's latency), so subtitles and
## mouths stay with the sound.
@tool
@icon("res://addons/audio_kit/icons/recipe.svg")
class_name AKSpeaker
extends Node

## A line started (its first syllable is about to be heard).
signal line_started(line: AKSpeechLine)
## A word is being heard: its index in line.words and its text as written.
signal word_started(index: int, word: String)
## A syllable is being heard: its index in line.events.
signal syllable_started(index: int)
## The line's last syllable has ended (the tail may still ring).
signal line_finished(line: AKSpeechLine)

## Who speaks.
@export var voice: AKSpeechVoice
@export_enum("auto", "baked", "live") var mode := "auto"
## An AudioStreamPlayer, AudioStreamPlayer2D or AudioStreamPlayer3D to speak
## through (for positional speech). Empty: the speaker makes its own.
@export var player: Node
@export var bus := &"Master"
@export var volume_db := 0.0
## Live lines are scheduled this far ahead, so the first note is never late.
@export_range(0.0, 0.5) var live_lead_s := 0.05
## Baked lines kept for saying again (by text and voice).
@export var cache_size := 32
## Play to the speakers (false: tests and offline renders pull the streams themselves).
@export var audio_output := true
## Signals and mouth only: the sound comes from elsewhere (a cue in a baked
## track, say). The line's clock starts when say() is called.
@export var silent := false

## The line being spoken (or the last one), compiled.
var line: AKSpeechLine
## "live" or "baked": how the current line plays.
var playing_mode := ""

var _players: Array[Node] = []          # [main] or the live streams' players, then the onset player
var _streams := {}                       # AKPatch -> AKSynthStream (live)
var _stream_players := {}                # AKPatch -> player
var _onsets_player: AudioStreamPlayer
var _start := {}                         # live: AKPatch -> engine frame where the line starts
var _speaking := false
var _next_event := 0
var _word := -1
var _finished_sent := true
var _manual := false
var _manual_t := 0.0
var _silent_start_us := 0
static var _baked := {}
static var _baked_order: Array[String] = []


## Speak `text` (markup welcome), interrupting whatever is being said.
## Returns the compiled line.
func say(text: String) -> AKSpeechLine:
	stop()
	line = AKSpeechLine.make(text, voice).compile()
	if voice == null or line.events.is_empty():
		return line
	if silent:
		playing_mode = "silent"
		_silent_start_us = Time.get_ticks_usec()
	else:
		playing_mode = _pick_mode()
		if playing_mode == "live":
			_start_live()
		else:
			_start_baked()
	_speaking = true
	_next_event = 0
	_word = -1
	_finished_sent = false
	line_started.emit(line)
	return line


## Stop at once: notes cut, signals stop (line_finished isn't sent).
func stop() -> void:
	_speaking = false
	for s in _streams.values():
		s.call(&"panic")
	if _onsets_player:
		_onsets_player.stop()
	var p := _main_player()
	if p and p.has_method(&"stop") and playing_mode == "baked":
		p.call(&"stop")


func is_speaking() -> bool:
	return _speaking


## Seconds into the line, as heard (output latency taken off). Negative
## during a live line's lead-in.
func position() -> float:
	if not _speaking:
		return -1.0
	if _manual:
		return _manual_t
	if playing_mode == "silent":
		return (Time.get_ticks_usec() - _silent_start_us) / 1e6
	var latency := AudioServer.get_output_latency() if audio_output else 0.0
	if playing_mode == "live":
		var patch: AKPatch = _streams.keys()[0]
		var s: Object = _streams[patch]
		var sr := float(AK.sample_rate)
		var mixed := float(int(s.call(&"get_frame")) - int(_start[patch])) / sr
		return mixed + (AudioServer.get_time_since_last_mix() if audio_output else 0.0) - latency
	var p := _main_player()
	if p == null or not p.call(&"is_playing"):
		return line.duration + 1.0 if line else -1.0
	return float(p.call(&"get_playback_position")) + AudioServer.get_time_since_last_mix() - latency


## The line's intensity now (0..1), for a bounce or a glow.
func intensity() -> float:
	if not _speaking or line == null:
		return 0.0
	var t := position()
	return line.curve_at("intensity", t) if t >= 0.0 and t <= line.duration else 0.0


## How open a mouth should be now: the intensity while a syllable's note
## sounds, closed in the gaps between syllables and words.
func mouth() -> float:
	if not _speaking or line == null:
		return 0.0
	var t := position()
	for e in line.events:
		var a := float(e.t_start)
		if t < a:
			break
		if t <= a + (float(e.t_end) - a) * voice.gate:
			return line.curve_at("intensity", t)
	return 0.0


## Send the signals due by `t` seconds into the line. _process calls it with
## position(); call it yourself (with `manual` true) to drive a speaker from
## another clock, such as a timeline or a test.
func update(t: float) -> void:
	_manual_t = t
	if not _speaking or line == null:
		return
	while _next_event < line.events.size() and float(line.events[_next_event].t_start) <= t:
		var e: Dictionary = line.events[_next_event]
		syllable_started.emit(_next_event)
		if int(e.word_index) != _word:
			_word = int(e.word_index)
			word_started.emit(_word, String(line.words[_word].text))
		_next_event += 1
	if not _finished_sent and t >= line.duration:
		_finished_sent = true
		_speaking = false
		line_finished.emit(line)


## True: _process leaves the clock to whoever calls update().
func set_manual(on: bool) -> void:
	_manual = on


## The live synth streams (one per patch the voice uses), for offline renders.
func live_streams() -> Dictionary:
	return _streams


func _process(_delta: float) -> void:
	if _speaking and not _manual:
		update(position())


func _exit_tree() -> void:
	stop()


# ------------------------------------------------------------------ inside

func _pick_mode() -> String:
	var live_ok := AKSynth.available() and voice.source == "patch" and voice.patch != null
	match mode:
		"live":
			if not live_ok:
				push_warning("AKSpeaker: live needs the native core and a patch voice; this line plays baked")
			return "live" if live_ok else "baked"
		"baked":
			return "baked"
	return "live" if live_ok else "baked"


func _main_player() -> Node:
	if player:
		return player
	if _players.is_empty():
		var p := AudioStreamPlayer.new()
		p.bus = bus
		add_child(p)
		_players.append(p)
	return _players[0]


func _start_baked() -> void:
	var key := line.key()
	var stream: AudioStreamWAV = _baked.get(key)
	if stream == null:
		stream = AKSpeech.render(line).to_stream()
		_baked[key] = stream
		_baked_order.append(key)
		while _baked_order.size() > maxi(0, cache_size):
			_baked.erase(_baked_order.pop_front())
	var p := _main_player()
	# A player that carried a live stream gives it up.
	for patch in _stream_players.keys():
		if _stream_players[patch] == p:
			_stream_players.erase(patch)
			_streams.erase(patch)
	p.set(&"volume_db", volume_db)
	p.set(&"stream", stream)
	if audio_output and p.is_inside_tree():
		p.call(&"play")


func _start_live() -> void:
	var sr := AK.sample_rate
	var lead := roundi(live_lead_s * sr)
	_start.clear()
	var chain := voice.effect_chain().map(func(e: Dictionary) -> Dictionary: return AKStreamFx.compile(e))
	for patch in AKSpeech.patches_for(line):
		var s := _stream_for(patch)
		# The voice's effects run after the patch's own, on the live synth.
		var data := patch.compile()
		data.effects = (data.effects as Array) + chain
		s.call(&"set_patch_data", data)
		var f0 := int(s.call(&"get_frame")) + lead
		_start[patch] = f0
		for ev: Array in AKSynth.events_for(AKSpeech.notes_for(line, patch), sr):
			s.call(&"schedule", f0 + int(ev[0]), int(ev[1]), float(ev[2]), float(ev[3]) if ev.size() > 3 else 0.0)
	# Onsets: rendered (cheap: no synth) and started with the same lead.
	var hits := AKSpeech.render_onsets(line, sr)
	AKSpeech.apply_effects(voice, hits)
	# As a bake limits the line, keep loud consonants from clipping.
	var ceiling := db_to_linear(AKSpeech.CEILING_DB - voice.gain_db)
	if hits.peak() > ceiling:
		AKDynamics.limit(hits, AKSpeech.CEILING_DB - voice.gain_db)
	if hits.frames() > 0:
		var pad := AKBuffer.new(lead, sr)
		hits.mix_into(pad, lead, 1.0)
		if _onsets_player == null:
			_onsets_player = AudioStreamPlayer.new()
			_onsets_player.bus = bus
			add_child(_onsets_player)
		_onsets_player.volume_db = volume_db + voice.gain_db
		_onsets_player.stream = pad.to_stream()
		if audio_output and _onsets_player.is_inside_tree():
			_onsets_player.play()


## The live synth for a patch: made once, kept playing.
func _stream_for(patch: AKPatch) -> Object:
	if _streams.has(patch):
		return _streams[patch]
	var s: Object = ClassDB.instantiate(&"AKSynthStream")
	s.set(&"patch", patch)
	_streams[patch] = s
	var p: Node = player if player and _streams.size() == 1 else null
	if p == null:
		var ap := AudioStreamPlayer.new()
		ap.bus = bus
		add_child(ap)
		p = ap
	p.set(&"stream", s)
	p.set(&"volume_db", volume_db + voice.gain_db)
	_stream_players[patch] = p
	if audio_output and p.is_inside_tree():
		p.call(&"play")
	return s
