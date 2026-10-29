# SPDX-License-Identifier: Apache-2.0
## A character who talks: type a line (markup welcome) or pick one, choose a
## voice, and the AKSpeaker says it while a subtitle lights each word and a
## face opens its mouth on every syllable. Live with the native core (it
## starts at once, however long the line), baked without.
extends Control

const LINES := [
	"Hey! Where did you come from? Get out of here with that stupid stupid haircut!",
	"Oh, hello there. {whisper} I wasn't expecting anyone... {} *Who* are you?",
	"**WHAT** have you done to my ^garden~?",
	"Zorblax says / the rocket is ready.",
]

var speaker: AKSpeaker
var _voices: Array[Dictionary] = []
var _input: LineEdit
var _voice: OptionButton
var _subtitle: RichTextLabel
var _face: Control
var _status: Label


func _ready() -> void:
	speaker = AKSpeaker.new()
	add_child(speaker)
	speaker.word_started.connect(_on_word)
	speaker.line_finished.connect(func(_l: AKSpeechLine) -> void: _show_subtitle(-1))
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 16
	box.offset_top = 12
	box.offset_right = -16
	add_child(box)
	var title := Label.new()
	title.text = "Audio Kit: pseudo-speech (type a line, press Enter)"
	box.add_child(title)
	_face = _Face.new()
	_face.custom_minimum_size = Vector2(0, 200)
	box.add_child(_face)
	_subtitle = RichTextLabel.new()
	_subtitle.bbcode_enabled = true
	_subtitle.fit_content = true
	_subtitle.scroll_active = false
	_subtitle.add_theme_font_size_override(&"normal_font_size", 24)
	box.add_child(_subtitle)
	var row := HBoxContainer.new()
	box.add_child(row)
	_voice = OptionButton.new()
	_voices = AKSpeech.voices()
	for v in _voices:
		_voice.add_item(v.name)
	row.add_child(_voice)
	_input = LineEdit.new()
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.text = LINES[0]
	_input.text_submitted.connect(func(t: String) -> void: say(t))
	row.add_child(_input)
	var b := Button.new()
	b.text = "Say"
	b.pressed.connect(func() -> void: say(_input.text))
	row.add_child(b)
	for l in LINES:
		var lb := Button.new()
		lb.text = l
		lb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		lb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		lb.pressed.connect(func() -> void:
			_input.text = l
			say(l))
		box.add_child(lb)
	_status = Label.new()
	_status.modulate = Color(1, 1, 1, 0.6)
	box.add_child(_status)


func say(text: String) -> void:
	var i := _voice.selected
	if i < 0 or i >= _voices.size():
		return
	speaker.voice = AKSpeech.resolve_voice(_voices[i].path)
	var t := Time.get_ticks_usec()
	var l := speaker.say(text)
	_status.text = "%s, %s: started in %.0f ms, %.2f s long%s" % [_voices[i].name, speaker.playing_mode,
		(Time.get_ticks_usec() - t) / 1000.0, l.duration, ("   " + "; ".join(l.warnings)) if not l.warnings.is_empty() else ""]
	_show_subtitle(-1)


func _process(_delta: float) -> void:
	_face.set(&"open", speaker.mouth())
	_face.set(&"glow", speaker.intensity())


func _on_word(index: int, _word: String) -> void:
	_show_subtitle(index)


func _show_subtitle(current: int) -> void:
	var l := speaker.line
	if l == null:
		_subtitle.text = ""
		return
	var out := ""
	var at := 0
	for wi in l.words.size():
		var w: Dictionary = l.words[wi]
		out += l.display_text.substr(at, int(w.start) - at).replace("[", "[lb]")
		var word := l.display_text.substr(int(w.start), int(w.end) - int(w.start)).replace("[", "[lb]")
		out += ("[color=#ffcf3b]%s[/color]" % word) if wi == current else word
		at = int(w.end)
	_subtitle.text = out + l.display_text.substr(at).replace("[", "[lb]")


## A round face whose mouth follows the speaker.
class _Face:
	extends Control
	var open := 0.0:
		set(v):
			open = lerpf(open, v, 0.6)
			queue_redraw()
	var glow := 0.0

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, size.y * 0.5)
		var r := minf(size.y * 0.45, 90.0)
		draw_circle(c, r, Color(0.95, 0.75, 0.3).lerp(Color(1.0, 0.9, 0.5), glow))
		draw_circle(c + Vector2(-r * 0.35, -r * 0.25), r * 0.09, Color(0.1, 0.1, 0.12))
		draw_circle(c + Vector2(r * 0.35, -r * 0.25), r * 0.09, Color(0.1, 0.1, 0.12))
		var mw := r * 0.5
		var mh := maxf(2.0, r * 0.45 * open)
		draw_rect(Rect2(c + Vector2(-mw * 0.5, r * 0.3 - mh * 0.5), Vector2(mw, mh)), Color(0.35, 0.08, 0.1))
