# SPDX-License-Identifier: Apache-2.0
## A rotary knob with a word at either end, for the Flavor page.
##
## Two kinds: two-way (-1 .. 1, rests in the middle, the arc grows from the top
## toward either side) and add-only (0 .. 1, rests fully left, the arc grows
## from the lower left). Drag up or right to turn it up (Shift: fine), roll the
## wheel, or use the arrow keys when it has focus; double-click returns it to
## rest. A right-click emits `menu_requested` (the Flavor page offers MIDI
## learn there).
@tool
class_name AKKnob
extends Control

## While dragging, rolling or keying, with the new value.
signal changed(value: float)
## A drag (or a wheel or key step) ended: the value has settled.
signal released
signal menu_requested

## The sweep from fully left to fully right, about the top.
const SWEEP := deg_to_rad(270.0)
## Pixels of drag for the whole range (times the UI scale).
const DRAG_PX := 180.0

## Rests in the middle and turns either way; false: rests at 0, only turns up.
var two_way := true:
	set(v):
		two_way = v
		value = value
		queue_redraw()
## The words at either end.
var low_text := "":
	set(v):
		low_text = v
		queue_redraw()
var high_text := "":
	set(v):
		high_text = v
		queue_redraw()
## -1 .. 1 (two-way) or 0 .. 1.
var value := 0.0:
	set(v):
		value = clampf(v, min_value(), 1.0)
		queue_redraw()
## Two-way knobs snap to rest within this distance of the middle.
var detent := 0.04
## Shown in place of the arc's colour while the knob waits for a MIDI controller.
var learning := false:
	set(v):
		learning = v
		queue_redraw()
## A small mark when a MIDI controller is linked.
var linked := false:
	set(v):
		linked = v
		queue_redraw()

var _dragging := false
var _drag_from := 0.0
var _drag_at := Vector2.ZERO
var _moved := false


func _init() -> void:
	custom_minimum_size = AKUiScale.px(96, 118)
	focus_mode = Control.FOCUS_CLICK
	mouse_default_cursor_shape = Control.CURSOR_VSIZE


func min_value() -> float:
	return -1.0 if two_way else 0.0


## Set the value as a person would (clamped, snapped to rest near the middle)
## and emit `changed`. Returns the value it ended at.
func turn_to(v: float) -> float:
	var x := clampf(v, min_value(), 1.0)
	if two_way and absf(x) < detent:
		x = 0.0
	if not two_way and x < detent * 0.5:
		x = 0.0
	if x != value:
		value = x
		changed.emit(value)
	return value


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and mb.double_click:
				_dragging = false
				turn_to(0.0)
				released.emit()
			elif mb.pressed:
				_dragging = true
				_moved = false
				_drag_from = value
				_drag_at = mb.position
				grab_focus()
			elif _dragging:
				_dragging = false
				if _moved:
					released.emit()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			menu_requested.emit()
			accept_event()
		elif mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var step := (0.01 if mb.shift_pressed else 0.05) * (1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0)
			turn_to(value + step)
			released.emit()
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		var d := (mm.position.x - _drag_at.x) - (mm.position.y - _drag_at.y)
		var span := 1.0 - min_value()
		var fine := 0.2 if mm.shift_pressed else 1.0
		_moved = true
		turn_to(_drag_from + d / (DRAG_PX * AKUiScale.factor()) * span * fine)
		accept_event()
	elif event is InputEventKey and (event as InputEventKey).pressed:
		var k := event as InputEventKey
		var step := 0.01 if k.shift_pressed else 0.05
		if k.keycode == KEY_UP or k.keycode == KEY_RIGHT:
			turn_to(value + step)
			released.emit()
			accept_event()
		elif k.keycode == KEY_DOWN or k.keycode == KEY_LEFT:
			turn_to(value - step)
			released.emit()
			accept_event()
		elif k.keycode == KEY_DELETE or k.keycode == KEY_BACKSPACE:
			turn_to(0.0)
			released.emit()
			accept_event()


## The pointer's angle from straight up, clockwise, for `v`.
func angle_of(v: float) -> float:
	var t := (v - min_value()) / (1.0 - min_value())
	return -SWEEP * 0.5 + SWEEP * t


func _draw() -> void:
	var s := AKUiScale.factor()
	var font := get_theme_default_font()
	var fs := roundi(12 * s)
	var r := 28.0 * s
	var c := Vector2(size.x * 0.5, r + 8.0 * s)
	var ink := get_theme_color(&"font_color", &"Label") if has_theme_color(&"font_color", &"Label") else Color(0.9, 0.9, 0.9)
	var dim := Color(ink, 0.55)
	var accent := Color(1.0, 0.55, 0.2) if learning else Color(0.45, 0.85, 1.0)
	var track := Color(ink, 0.22)
	# The track, the arc from rest to the value, then the pointer. Angles for
	# draw_arc are from the x axis, clockwise; ours are from straight up.
	var a0 := -SWEEP * 0.5 - PI * 0.5
	draw_arc(c, r, a0, a0 + SWEEP, 48, track, 2.0 * s, true)
	var rest := angle_of(0.0)
	var now := angle_of(value)
	if not is_equal_approx(rest, now):
		draw_arc(c, r, minf(rest, now) - PI * 0.5, maxf(rest, now) - PI * 0.5, 32, accent, 3.0 * s, true)
	var dir := Vector2(sin(now), -cos(now))
	draw_line(c + dir * r * 0.25, c + dir * (r - 3.0 * s), accent, 2.5 * s, true)
	if two_way:
		draw_line(c + Vector2(0, -r - 2.0 * s), c + Vector2(0, -r - 6.0 * s), track, 1.5 * s)
	if linked:
		draw_circle(c + Vector2(r, -r), 2.5 * s, accent)
	if has_focus():
		draw_arc(c, r + 4.0 * s, 0.0, TAU, 48, Color(accent, 0.35), 1.0 * s, true)
	# The words: the low one dimmed, the high one bright; whichever the knob
	# has moved toward lights up.
	var y := c.y + r + 6.0 * s + font.get_ascent(fs)
	var low_col := accent if value < 0.0 else dim
	var high_col := accent if value > 0.0 else ink
	draw_string(font, Vector2(0, y), low_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, low_col)
	draw_string(font, Vector2(0, y + font.get_height(fs)), high_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, high_col)
	if _dragging:
		var txt := "%+.2f" % value if two_way else "%.2f" % value
		draw_string(font, Vector2(0, c.y + font.get_ascent(roundi(10 * s)) * 0.5), txt, HORIZONTAL_ALIGNMENT_CENTER, size.x, roundi(10 * s), ink)
