# SPDX-License-Identifier: Apache-2.0
## The Sound Lab's Pseudo-Speech page: type a line, pick a voice, hear it.
##
##   Text       the line; it replays a moment after each edit
##   Voice      the kit's voices and the project's (res://audio/speech/voices/)
##   Play/Stop  bakes the line and plays it; the subtitle below lights each
##              word as it's spoken
##   Consonants the picked voice's onset level (its onset_gain_db), for this
##              editor session; set it on a voice resource to keep it
##   Live       plays the line on the live synth instead (it starts at once;
##              needs the native core and a patch voice), then bakes it for
##              the waveform and curves
##   Replay     replays a moment after each edit, unless the voice took longer
##              than SLOW_MS to bake (no native core): then press Play
##   Curves     the line on the waveform's time axis: words, syllables,
##              accents and the curves the voice hears (pick which); click a
##              word to hear it alone, in its place in the line
##   Analysis   how the text was read: syllables split with "·", stressed
##              syllables in capitals, clauses with their end marks, markup
##              as written, (?) on words the rules guessed
@tool
class_name AKSpeechLab
extends VBoxContainer

const DEFAULT_TEXT := "Hey! Where did you come from? Get out of here with that stupid stupid haircut!"
const AUTO_DELAY_S := 0.4
## A voice whose last bake took longer than this doesn't replay on every edit.
const SLOW_MS := 1500.0
const CONSONANT_TIP := "How loud the voice's consonants are (its onset_gain_db): the clicks of p, t, k and the hiss of s, f, h. Changes the voice for this editor session."

## The line being worked on (its voice is the picked one).
var line: AKSpeechLine
## The last render: {length_s, peak_db, ms, syllables, words}.
var last_stats := {}
var player: AudioStreamPlayer
## Speaks the line when Live is on.
var speaker: AKSpeaker

var _voices: Array[Dictionary] = []
var _text: TextEdit
var _voice: OptionButton
var _auto: CheckBox
var _live: CheckBox
var _consonants: AKParamSlider
## Voice path -> how long its last bake took (ms).
var _bake_ms := {}
var _stats: Label
var _subtitle: RichTextLabel
var _wave: Control
var _curves: AKSpeechCurves
var _last_buf: AKBuffer
## Where the playing stream starts in the line (a word's audition starts mid-line).
var _play_from := 0.0
var _analysis: Label
var _status: Label
var _replay_at := -1.0
var _rendered_key := ""
var _shown_word := -2
var _quiet := false


func _init() -> void:
	name = "Pseudo-Speech"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	player = AudioStreamPlayer.new()
	add_child(player)
	speaker = AKSpeaker.new()
	speaker.mode = "live"
	add_child(speaker)
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
	if speaker.is_speaking():
		var t := speaker.position()
		if t >= 0.0:
			w = line.word_at(t)
			if _curves:
				_curves.set_playhead(t)
	elif player.playing:
		var t := _play_from + player.get_playback_position()
		w = line.word_at(t)
		if _curves:
			_curves.set_playhead(t)
	elif _curves and _curves.playhead >= 0.0:
		_curves.set_playhead(-1.0)
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
	_rendered_key = line.key()
	var ms := (Time.get_ticks_usec() - t) / 1000.0
	if line.voice:
		_bake_ms[line.voice.resource_path] = ms
	var peak := buf.peak()
	last_stats = {length_s = buf.seconds(), peak_db = linear_to_db(peak) if peak > 0.0 else -INF, ms = ms,
		syllables = line.events.size(), words = line.words.size()}
	if _stats:
		_stats.text = "%d words, %d syllables   %.2f s   peak %.1f dBFS   rendered in %.0f ms" % [last_stats.words,
			last_stats.syllables, last_stats.length_s, last_stats.peak_db, ms]
	if _wave:
		_wave.call(&"set_buffer", buf)
	_last_buf = buf
	if _curves:
		_curves.set_line(line, buf.seconds())
	_show_analysis()
	return buf


## Play word `index` alone, cut from the line as rendered (so it keeps its
## place in the melody), with a little of the tail; returns the cut.
func audition_word(index: int) -> AKBuffer:
	speaker.stop()
	if _last_buf == null or _last_buf.frames() == 0 or line.key() != _rendered_key:
		render()
	var a := -1.0
	var b := -1.0
	for e in line.events:
		if int(e.word_index) == index:
			if a < 0.0:
				a = float(e.t_start)
			b = float(e.t_end)
	if a < 0.0 or _last_buf.frames() == 0:
		return AKBuffer.new(0, _last_buf.sample_rate if _last_buf else AK.sample_rate)
	var sr := _last_buf.sample_rate
	var i0 := clampi(roundi(a * sr), 0, _last_buf.frames())
	var i1 := clampi(roundi((b + 0.08) * sr), i0, _last_buf.frames())
	var cut := AKBuffer.new(i1 - i0, sr)
	for i in i1 - i0:
		cut.l[i] = _last_buf.l[i0 + i]
		cut.r[i] = _last_buf.r[i0 + i]
	# A short fade at the cut so it doesn't click.
	var fade := mini(cut.frames(), roundi(0.004 * sr))
	for i in fade:
		var g := float(i) / fade
		cut.l[cut.frames() - 1 - i] *= g
		cut.r[cut.frames() - 1 - i] *= g
	_play_from = a
	player.stream = cut.to_stream()
	if player.is_inside_tree():
		player.play()
	_say("“%s”" % String(line.words[index].text))
	return cut


## True when the picked voice can play live (the native core and a patch).
func live_available() -> bool:
	return AKSynth.available() and line.voice != null and line.voice.source == "patch" and line.voice.patch != null


## True when the picked voice's last bake took longer than SLOW_MS.
func is_slow() -> bool:
	return line.voice != null and float(_bake_ms.get(line.voice.resource_path, 0.0)) > SLOW_MS


## Play the line: live when Live is on and the voice can, baked otherwise
## (a line already baked plays again without baking).
func play() -> void:
	_replay_at = -1.0
	speaker.stop()
	if _live and _live.button_pressed and live_available():
		_play_live()
		return
	var buf := _last_buf if _last_buf and _last_buf.frames() > 0 and line.key() == _rendered_key else render()
	if buf.frames() == 0:
		_say("Nothing to say: type a line and pick a voice." if line.voice else "Pick a voice.")
		player.stop()
		return
	_say("Live needs the native core and a patch voice: this one plays baked." if _live and _live.button_pressed else "")
	_play_from = 0.0
	player.stream = buf.to_stream()
	if player.is_inside_tree():
		player.play()


func stop() -> void:
	_replay_at = -1.0
	player.stop()
	speaker.stop()


func _play_live() -> void:
	line.compile()
	if line.events.is_empty():
		_say("Nothing to say: type a line.")
		return
	player.stop()
	speaker.voice = line.voice
	speaker.say(line.source_text)
	_say("")
	# The notes are all scheduled, so baking now doesn't hold the sound up.
	if line.key() != _rendered_key:
		render()


# ------------------------------------------------------------------ inside

func _use_voice(i: int) -> void:
	if i < 0 or i >= _voices.size():
		return
	line.voice = AKSpeech.resolve_voice(_voices[i].path)
	_show_consonants()
	_show_analysis()


## The consonant slider follows the picked voice (off for one without onsets).
func _show_consonants() -> void:
	if _consonants == null:
		return
	var v := line.voice
	var has := v != null and (v.plosive != null or v.fricative != null or v.breath != null)
	_consonants.set_value(v.onset_gain_db if v else 0.0)
	_consonants.modulate.a = 1.0 if has else 0.4
	_consonants.tooltip_text = CONSONANT_TIP if has else "This voice has no consonant sounds."


func _set_consonants(db: float) -> void:
	var v := line.voice
	if v == null or (v.plosive == null and v.fricative == null and v.breath == null):
		_show_consonants()
		return
	v.onset_gain_db = db
	_say("Consonants %+.1f dB for this session. To keep it, set Onset Gain Db to %.1f on a voice of your own (res://audio/speech/voices/)." % [db, db])
	_schedule_replay()


func _on_edited() -> void:
	if _quiet:
		return
	line.source_text = _text.text
	_show_analysis()
	_schedule_replay()


func _schedule_replay() -> void:
	if _auto and _auto.button_pressed:
		if is_slow() and not (_live and _live.button_pressed and live_available()):
			_say("This voice took %.1f s to bake (no native core), so edits don't replay on their own: press Play." % (
				float(_bake_ms[line.voice.resource_path]) / 1000.0))
		else:
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
	_text.custom_minimum_size = AKUiScale.px(0, 72)
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
	_voice.custom_minimum_size = AKUiScale.px(160, 0)
	_voice.tooltip_text = "The kit's voices and yours (res://audio/speech/voices/)."
	_voice.item_selected.connect(func(i: int) -> void:
		_use_voice(i)
		if _auto and _auto.button_pressed and not is_slow():
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
	_auto.tooltip_text = "Replay a moment after each edit (not for voices that take over %.1f s to bake)." % (SLOW_MS / 1000.0)
	row.add_child(_auto)
	_live = CheckBox.new()
	_live.text = "Live"
	_live.tooltip_text = "Play on the live synth: starts at once. Needs the native core and a patch voice (Scratch King always bakes)."
	_live.disabled = not AKSynth.available()
	row.add_child(_live)
	_consonants = AKParamSlider.make("Consonants", -24.0, 12.0, 0.0, {unit = "dB", width = AKUiScale.px(84, 0).x,
		tip = CONSONANT_TIP})
	_consonants.custom_minimum_size.x = AKUiScale.px(260, 0).x
	_consonants.changed.connect(_set_consonants)
	row.add_child(_consonants)
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
	_wave.custom_minimum_size = AKUiScale.px(0, 110)
	add_child(_wave)
	_curves = AKSpeechCurves.new()
	_curves.word_clicked.connect(func(i: int) -> void: audition_word(i))
	add_child(_curves)
	var crow := HBoxContainer.new()
	add_child(crow)
	var cl := Label.new()
	cl.text = "Curves"
	cl.modulate = Color(1, 1, 1, 0.6)
	crow.add_child(cl)
	for c in AKSpeechCurves.CURVES:
		var cb := CheckBox.new()
		cb.text = c
		cb.button_pressed = bool(_curves.shown.get(c, false))
		cb.add_theme_color_override(&"font_color", AKSpeechCurves.COLORS[c])
		cb.toggled.connect(func(on: bool) -> void: _curves.set_shown(c, on))
		crow.add_child(cb)
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
