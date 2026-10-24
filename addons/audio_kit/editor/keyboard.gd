# SPDX-License-Identifier: Apache-2.0
## An on-screen piano keyboard: click (higher on a key = softer, lower =
## harder), drag across keys, or play from the computer keyboard
## (Z S X D C V G B H N J M for one octave, Q 2 W 3 E R 5 T 6 Y 7 U for the
## next; [ and ] shift octaves). Emits note_on / note_off; keys light up
## while held, including notes `mark()`ed from elsewhere (MIDI input).
@tool
class_name AKKeyboard
extends Control

signal note_on(note: int, velocity: float)
signal note_off(note: int)

## Lowest C shown (MIDI note).
@export var low_note := 48:
	set(v):
		low_note = clampi(v, 0, 108)
		queue_redraw()
@export_range(1, 6) var octaves := 3:
	set(v):
		octaves = v
		queue_redraw()
## Velocity for computer-keyboard notes.
@export_range(0.0, 1.0) var velocity := 0.8
## Play from the computer keyboard while the mouse is over the keyboard or
## it has focus.
@export var computer_keys := true

const LOWER := [KEY_Z, KEY_S, KEY_X, KEY_D, KEY_C, KEY_V, KEY_G, KEY_B, KEY_H, KEY_N, KEY_J, KEY_M]
const UPPER := [KEY_Q, KEY_2, KEY_W, KEY_3, KEY_E, KEY_R, KEY_5, KEY_T, KEY_6, KEY_Y, KEY_7, KEY_U]
const BLACK := [1, 3, 6, 8, 10]

var _held := {}       # note -> true (from this keyboard)
var _marked := {}     # note -> true (from elsewhere)
var _mouse_note := -1
var _hover := false


func _init() -> void:
	custom_minimum_size = Vector2(420, 90)
	focus_mode = Control.FOCUS_ALL
	mouse_entered.connect(func() -> void: _hover = true)
	mouse_exited.connect(func() -> void: _hover = false)


## Light a key (or not) for a note played elsewhere.
func mark(note: int, on: bool) -> void:
	if on:
		_marked[note] = true
	else:
		_marked.erase(note)
	queue_redraw()


func release_all() -> void:
	for n in _held.keys():
		_stop(n)
	_mouse_note = -1


func white_count() -> int:
	return octaves * 7 + 1


## The note under a point on the keyboard, or -1.
func note_at(p: Vector2) -> int:
	var ww := size.x / white_count()
	if p.y < size.y * 0.6:
		for i in octaves * 12 + 1:
			var n := low_note + i
			if (n % 12) in BLACK:
				var r := _black_rect(n, ww)
				if r.has_point(p):
					return n
	var wi := floori(p.x / ww)
	if wi < 0 or wi >= white_count():
		return -1
	var octave := wi / 7
	var step: int = [0, 2, 4, 5, 7, 9, 11][wi % 7]
	return low_note + octave * 12 + step


func _black_rect(n: int, ww: float) -> Rect2:
	var rel := n - low_note
	var octave := rel / 12
	var whites_before: int = [0, 1, 1, 2, 2, 3, 4, 4, 5, 5, 6, 6][rel % 12]
	var x := (octave * 7 + whites_before) * ww - ww * 0.3
	return Rect2(x, 0, ww * 0.6, size.y * 0.6)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			grab_focus()
			var n := note_at(event.position)
			if n >= 0:
				_mouse_note = n
				_start(n, _vel_at(event.position))
		elif _mouse_note >= 0:
			_stop(_mouse_note)
			_mouse_note = -1
		accept_event()
	elif event is InputEventMouseMotion and _mouse_note >= 0 and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		var n := note_at(event.position)
		if n >= 0 and n != _mouse_note:
			_stop(_mouse_note)
			_mouse_note = n
			_start(n, _vel_at(event.position))
	elif event is InputEventKey and computer_keys and not event.echo:
		if _key(event as InputEventKey):
			accept_event()


## A computer key: true when it played or released a note (or moved octave).
func _key(e: InputEventKey) -> bool:
	if e.pressed and e.keycode == KEY_BRACKETLEFT:
		low_note = maxi(0, low_note - 12)
		return true
	if e.pressed and e.keycode == KEY_BRACKETRIGHT:
		low_note = mini(108, low_note + 12)
		return true
	var i := LOWER.find(e.keycode)
	var base := low_note
	if i < 0:
		i = UPPER.find(e.keycode)
		base = low_note + 12
	if i < 0:
		return false
	var n := base + i
	if e.pressed:
		if not _held.has(n):
			_start(n, velocity)
	else:
		_stop(n)
	return true


func _vel_at(p: Vector2) -> float:
	return clampf(0.3 + 0.7 * p.y / maxf(1.0, size.y), 0.05, 1.0)


func _start(n: int, v: float) -> void:
	_held[n] = true
	note_on.emit(n, v)
	queue_redraw()


func _stop(n: int) -> void:
	if _held.erase(n):
		note_off.emit(n)
		queue_redraw()


func _draw() -> void:
	var ww := size.x / white_count()
	var lit := Color("#ffcf3a")
	for wi in white_count():
		var octave := wi / 7
		var n: int = low_note + octave * 12 + [0, 2, 4, 5, 7, 9, 11][wi % 7]
		var r := Rect2(wi * ww, 0, ww - 1.0, size.y)
		draw_rect(r, lit if (_held.has(n) or _marked.has(n)) else Color(0.92, 0.92, 0.9))
		if n % 12 == 0:
			draw_string(get_theme_default_font(), Vector2(wi * ww + 3.0, size.y - 6.0), AKNotes.midi_to_name(n), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.3, 0.3, 0.3))
	for i in octaves * 12 + 1:
		var n := low_note + i
		if (n % 12) in BLACK and i < octaves * 12:
			draw_rect(_black_rect(n, ww), lit.darkened(0.2) if (_held.has(n) or _marked.has(n)) else Color(0.12, 0.12, 0.13))
