# SPDX-License-Identifier: Apache-2.0
## The Pseudo-Speech page's curve view: the compiled line drawn on the same
## time axis as the waveform above it. Words as bands with their text,
## syllables as ticks (a dot sized by stress on accented ones), and the
## curves the voice hears: pitch (in semitones around the voice's base, the
## voice's range marked), intensity, brightness, formant and noise (0..1).
## Click a word to hear it (`word_clicked`); a playhead follows playback.
@tool
class_name AKSpeechCurves
extends Control

## A word was clicked (its index in the line's words).
signal word_clicked(index: int)

const CURVES := ["pitch", "intensity", "brightness", "formant", "noise"]
const COLORS := {pitch = Color(1.0, 0.81, 0.23), intensity = Color(0.45, 0.85, 0.55), brightness = Color(0.4, 0.7, 1.0),
	formant = Color(0.85, 0.5, 1.0), noise = Color(0.75, 0.75, 0.75)}
const LABEL_H := 18.0

## The line drawn (compiled).
var line: AKSpeechLine
## Seconds across the full width (the waveform's length, so they line up).
var span_s := 1.0
## Which curves are drawn.
var shown := {pitch = true, intensity = true, brightness = false, formant = false, noise = false}
## Where playback is, in seconds (negative = hidden).
var playhead := -1.0
## The word under the mouse (-1 = none).
var hover := -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = AKUiScale.px(0, 170)
	tooltip_text = "Click a word to hear it."


## Show a compiled line over `seconds` (the rendered length; 0 = the line's own).
func set_line(p_line: AKSpeechLine, seconds := 0.0) -> void:
	line = p_line
	span_s = seconds if seconds > 0.0 else maxf(0.01, line.duration if line else 1.0)
	hover = -1
	queue_redraw()


func set_shown(curve: String, on: bool) -> void:
	shown[curve] = on
	queue_redraw()


func set_playhead(t: float) -> void:
	if not is_equal_approx(t, playhead):
		playhead = t
		queue_redraw()


## The x of a time and the time of an x.
func x_of(t: float) -> float:
	return t / maxf(1e-4, span_s) * size.x


func time_at(x: float) -> float:
	return x / maxf(1.0, size.x) * span_s


## The word whose span (first syllable's start to last syllable's end, plus
## half the gaps around it) holds x; -1 when none.
func word_at_x(x: float) -> int:
	if line == null:
		return -1
	var spans := word_spans()
	var t := time_at(x)
	for i in spans.size():
		var s: Vector2 = spans[i]
		var lo := s.x - (0.5 * (s.x - spans[i - 1].y) if i > 0 else 0.05)
		var hi := s.y + (0.5 * (spans[i + 1].x - s.y) if i + 1 < spans.size() else 0.15)
		if t >= lo and t < hi:
			return int(_word_index_of_span(i))
	return -1


## [start, end] of each spoken word, in time order.
func word_spans() -> Array[Vector2]:
	var out: Array[Vector2] = []
	_span_words.clear()
	if line == null:
		return out
	var cur := -1
	for e in line.events:
		var wi := int(e.word_index)
		if wi != cur:
			out.append(Vector2(float(e.t_start), float(e.t_end)))
			_span_words.append(wi)
			cur = wi
		else:
			out[out.size() - 1].y = float(e.t_end)
	return out


var _span_words: Array[int] = []


func _word_index_of_span(i: int) -> int:
	return _span_words[i] if i < _span_words.size() else -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var w := word_at_x(event.position.x)
		if w != hover:
			hover = w
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var w := word_at_x(event.position.x)
		if w >= 0:
			word_clicked.emit(w)
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and hover != -1:
		hover = -1
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.25))
	if line == null or line.events.is_empty():
		return
	var font := get_theme_default_font()
	var ui := AKUiScale.factor()
	var fs := roundi(12 * ui)
	var top := LABEL_H * ui
	var h := size.y - top - 4.0 * ui
	# Words: bands and labels.
	var spans := word_spans()
	for i in spans.size():
		var s: Vector2 = spans[i]
		var wi := _word_index_of_span(i)
		var r := Rect2(x_of(s.x), top, maxf(1.0, x_of(s.y) - x_of(s.x)), h)
		var tint := Color(1, 1, 1, 0.10 if wi == hover else (0.05 if i % 2 == 0 else 0.025))
		draw_rect(r, tint)
		var w: Dictionary = line.words[wi]
		var label := String(w.text)
		if int(w.get("emphasis", 0)) > 0:
			label = "*".repeat(int(w.emphasis)) + label
		draw_string(font, Vector2(r.position.x + 2 * ui, top - 5 * ui), label, HORIZONTAL_ALIGNMENT_LEFT, maxf(8.0, r.size.x + 40.0 * ui), fs,
			Color(1, 1, 1, 0.9 if wi == hover else 0.6))
	# Syllables: ticks, and a dot for accented ones.
	for e in line.events:
		var x := x_of(float(e.t_start))
		draw_line(Vector2(x, top), Vector2(x, top + 6 * ui), Color(1, 1, 1, 0.35), ui)
		var st := float(e.stress)
		if st > 0.0:
			var ax := x_of(float(e.t_start) + 0.35 * (float(e.t_end) - float(e.t_start)))
			draw_circle(Vector2(ax, top + 10 * ui), (2.0 + 4.0 * st) * ui, Color(1.0, 0.81, 0.23, 0.35 + 0.5 * st))
	# Pitch: centred on the voice's base, the range marked.
	var r_st := maxf(1.0, line.voice.range_semitones if line.voice else 6.0)
	var lim := r_st * 2.0
	var mid := top + h * 0.55
	var y_pitch := func(v: float) -> float: return mid - v / lim * h * 0.45
	draw_line(Vector2(0, mid), Vector2(size.x, mid), Color(1, 1, 1, 0.12), ui)
	for k in [-1.0, 1.0]:
		var yk: float = y_pitch.call(k * r_st)
		draw_dashed_line(Vector2(0, yk), Vector2(size.x, yk), Color(1, 1, 1, 0.08), ui, 4.0 * ui)
	var rate := float(line.curve_rate)
	for c in CURVES:
		if not shown.get(c, false):
			continue
		var data: PackedFloat32Array = line.curves.get(c, PackedFloat32Array())
		if data.size() < 2:
			continue
		var pts := PackedVector2Array()
		var step := maxi(1, int(data.size() / maxf(1.0, size.x)))
		for i in range(0, data.size(), step):
			var x := x_of(float(i) / rate)
			var y: float
			if c == "pitch":
				y = y_pitch.call(clampf(data[i], -lim, lim))
			else:
				y = top + h - clampf(data[i], 0.0, 1.0) * h * 0.9
			pts.append(Vector2(x, y))
		draw_polyline(pts, COLORS[c], (2.0 if c == "pitch" else 1.2) * ui, true)
	# Legend.
	var lx := size.x - 4.0 * ui
	var lfs := roundi(11 * ui)
	for c in CURVES:
		if shown.get(c, false):
			var tw := font.get_string_size(c, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs).x
			lx -= tw + 10.0 * ui
			draw_string(font, Vector2(lx, size.y - 6 * ui), c, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs, COLORS[c])
	if playhead >= 0.0:
		var px := x_of(playhead)
		draw_line(Vector2(px, 0), Vector2(px, size.y), Color(1.0, 0.81, 0.23, 0.9), 1.5 * ui)
