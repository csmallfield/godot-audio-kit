# SPDX-License-Identifier: Apache-2.0
## The Sound Lab's Pseudo-Speech page: type a line, pick a voice, hear it.
##
##   Text       the line; it replays a moment after each edit
##   Voice      the kit's voices and the project's (res://audio/speech/voices/)
##   Play/Stop  bakes the line and plays it; the subtitle below lights each
##              word as it's spoken
##   Analysis   how the text was read: syllables split with "·", stressed
##              syllables in capitals, clauses with their end marks
##
## Baked playback only for now (live synthesis comes later).
@tool
class_name AKSpeechLab
extends VBoxContainer

const DEFAULT_TEXT := "Hey! Where did you come from? Get out of here with that stupid stupid haircut!"
const AUTO_DELAY_S := 0.4

## The line being worked on (its voice is the picked one).
var line: AKSpeechLine
## The last render: {length_s, peak_db, ms, syllables, words}.
var last_stats := {}
var player: AudioStreamPlayer

var _voices: Array[Dictionary] = []
var _text: TextEdit
var _voice: OptionButton
var _auto: CheckBox
var _stats: Label
var _subtitle: RichTextLabel
var _wave: Control
var _analysis: Label
var _status: Label
var _replay_at := -1.0
var _shown_word := -2
var _quiet := false


func _init() -> void:
	name = "Pseudo-Speech"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	player = AudioStreamPlayer.new()
	add_child(player)
	line = AKSpeechLine.make(DEFAULT_TEXT, null)
	_build()
	refresh_voices()
	_show_analysis()


func _process(delta: float) -> void:
	if _replay_at >= 0.0:
		_replay_at -= delta
		if _replay_at < 0.0:
			play()
	var w := -1
	if player.playing:
		w = line.word_at(player.get_playback_position())
	if w != _shown_word:
		_shown_word = w
		_draw_subtitle(w)


# ------------------------------------------------------------------ actions

## Say `text` (replaces the text box) and play it unless `audible` is false.
func set_text(text: String, audible := true) -> void:
	_quiet = true
	_text.text = text
	_quiet = false
	line.source_text = text
	_show_analysis()
	if audible:
		play()


## Pick a voice by path (or resource); returns false if it isn't listed or loadable.
func select_voice(v: Variant) -> bool:
	var path: String = (v as AKSpeechVoice).resource_path if v is AKSpeechVoice else String(v)
	for i in _voices.size():
		if _voices[i].path == path:
			_voice.select(i)
			_use_voice(i)
			return true
	var res := AKSpeech.resolve_voice(v)
	if res == null:
		return false
	line.voice = res
	_show_analysis()
	return true


## Read the voice folders again (after saving one, say).
func refresh_voices() -> void:
	var keep := line.voice.resource_path if line.voice else ""
	_voices = AKSpeech.voices()
	_voice.clear()
	var pick := 0
	for i in _voices.size():
		var e := _voices[i]
		_voice.add_item("%s%s" % [e.name, "  (yours)" if e.source == "yours" else ""])
		if e.path == keep:
			pick = i
	if not _voices.is_empty():
		_voice.select(pick)
		_use_voice(pick)


## Compile and bake the line: the buffer, or an empty one.
func render() -> AKBuffer:
	_replay_at = -1.0
	var t := Time.get_ticks_usec()
	var buf := AKSpeech.render(line)
	var ms := (Time.get_ticks_usec() - t) / 1000.0
	var peak := buf.peak()
	last_stats = {length_s = buf.seconds(), peak_db = linear_to_db(peak) if peak > 0.0 else -INF, ms = ms,
		syllables = line.events.size(), words = line.words.size()}
	if _stats:
		_stats.text = "%d words, %d syllables   %.2f s   peak %.1f dBFS   rendered in %.0f ms" % [last_stats.words,
			last_stats.syllables, last_stats.length_s, last_stats.peak_db, ms]
	if _wave:
		_wave.call(&"set_buffer", buf)
	_show_analysis()
	return buf


## Bake and play the line.
func play() -> void:
	var buf := render()
	if buf.frames() == 0:
		_say("Nothing to say: type a line and pick a voice." if line.voice else "Pick a voice.")
		player.stop()
		return
	_say("")
	player.stream = buf.to_stream()
	if player.is_inside_tree():
		player.play()


func stop() -> void:
	_replay_at = -1.0
	player.stop()


# ------------------------------------------------------------------ inside

func _use_voice(i: int) -> void:
	if i < 0 or i >= _voices.size():
		return
	line.voice = AKSpeech.resolve_voice(_voices[i].path)
	_show_analysis()


func _on_edited() -> void:
	if _quiet:
		return
	line.source_text = _text.text
	_show_analysis()
	if _auto and _auto.button_pressed:
		_replay_at = AUTO_DELAY_S


func _show_analysis() -> void:
	if _analysis == null:
		return
	line.compile()
	_analysis.text = AKSpeech.describe_analysis(line) if not line.words.is_empty() else ""
	_shown_word = -2


func _draw_subtitle(current: int) -> void:
	if _subtitle == null:
		return
	var text := line.display_text
	var out := ""
	var at := 0
	for wi in line.words.size():
		var w: Dictionary = line.words[wi]
		out += _escape(text.substr(at, int(w.start) - at))
		var word := _escape(text.substr(int(w.start), int(w.end) - int(w.start)))
		out += "[color=#ffcf3b]%s[/color]" % word if wi == current else word
		at = int(w.end)
	out += _escape(text.substr(at))
	_subtitle.text = out


static func _escape(s: String) -> String:
	return s.replace("[", "[lb]")


func _say(text: String) -> void:
	if _status:
		_status.text = text


func _build() -> void:
	var title := Label.new()
	title.text = "Pseudo-Speech"
	title.add_theme_font_size_override(&"font_size", 15)
	title.modulate = Color(1.0, 0.81, 0.23)
	add_child(title)
	_text = TextEdit.new()
	_text.text = DEFAULT_TEXT
	_text.custom_minimum_size = Vector2(0, 72)
	_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text.placeholder_text = "Type a line of dialogue."
	_text.text_changed.connect(_on_edited)
	add_child(_text)
	var row := HBoxContainer.new()
	add_child(row)
	var vl := Label.new()
	vl.text = "Voice"
	row.add_child(vl)
	_voice = OptionButton.new()
	_voice.custom_minimum_size = Vector2(160, 0)
	_voice.tooltip_text = "The kit's voices and yours (res://audio/speech/voices/)."
	_voice.item_selected.connect(func(i: int) -> void:
		_use_voice(i)
		if _auto and _auto.button_pressed:
			play())
	row.add_child(_voice)
	var p := Button.new()
	p.text = "Play"
	p.pressed.connect(play)
	row.add_child(p)
	var s := Button.new()
	s.text = "Stop"
	s.pressed.connect(stop)
	row.add_child(s)
	_auto = CheckBox.new()
	_auto.text = "Replay when edited"
	_auto.button_pressed = true
	row.add_child(_auto)
	_stats = Label.new()
	_stats.modulate = Color(1, 1, 1, 0.75)
	add_child(_stats)
	_subtitle = RichTextLabel.new()
	_subtitle.bbcode_enabled = true
	_subtitle.fit_content = true
	_subtitle.scroll_active = false
	_subtitle.add_theme_font_size_override(&"normal_font_size", 20)
	_subtitle.tooltip_text = "The subtitle: each word lights as it's spoken."
	add_child(_subtitle)
	_wave = AKAuditionDock._Wave.new()
	_wave.custom_minimum_size = Vector2(0, 140)
	add_child(_wave)
	var al := Label.new()
	al.text = "Analysis"
	al.modulate = Color(1, 1, 1, 0.6)
	add_child(al)
	_analysis = Label.new()
	_analysis.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_analysis.tooltip_text = "Syllables split with ·, stressed ones in capitals (function words are never stressed)."
	add_child(_analysis)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = Color(1, 1, 1, 0.6)
	add_child(_status)
