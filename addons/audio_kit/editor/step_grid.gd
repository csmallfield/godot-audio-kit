# SPDX-License-Identifier: Apache-2.0
## A step grid for an AKPattern: one row per lane, one cell per step.
## Click a cell to cycle rest, soft, normal, accent (". o x X"); right-click
## clears it; click a lane's name to mute or unmute it. Edits rewrite the
## lane's step string in place (spacing and "|" grouping are kept) and emit
## the pattern's `changed`, so a pattern playing live picks them up.
## Lanes written as `notes` without `steps` are shown read-only.
@tool
class_name AKStepGrid
extends Control

## Emitted after a cell or mute changes (the pattern is already updated).
signal edited()

const CYCLE := [".", "o", "x", "X"]
const CELL := 18.0
const NAME_W := 64.0

var pattern: AKPattern
## The step the music is on (a fraction is fine), or -1 for none. Each lane
## wraps it to its own length.
var playhead := -1.0:
	set(v):
		if v != playhead:
			playhead = v
			queue_redraw()


func set_pattern(p: AKPattern) -> void:
	pattern = p
	_resize()
	queue_redraw()


func lane_count() -> int:
	return pattern.lanes.size() if pattern else 0


## Steps in lane `li`'s loop.
func lane_length(li: int) -> int:
	var l: Dictionary = pattern.lanes[li]
	if l.has("length"):
		return int(l.length)
	if l.has("steps"):
		return AKNotes.parse_steps(String(l.steps)).size()
	if l.has("notes"):
		return (l.notes as Array).size()
	return pattern.steps


func is_editable(li: int) -> bool:
	return pattern.lanes[li].has("steps")


## The step character at (lane, step): one of X x o ? . - ~ 1-9.
func cell(li: int, step: int) -> String:
	var l: Dictionary = pattern.lanes[li]
	if l.has("steps"):
		var chars := _step_chars(String(l.steps))
		return chars[step % chars.size()] if not chars.is_empty() else "."
	if l.has("notes"):
		var ns: Array = l.notes
		var s := str(ns[step % ns.size()]) if not ns.is_empty() else "."
		return "." if s in [".", "-", ""] else ("~" if s == "~" else "x")
	return "."


func set_cell(li: int, step: int, ch: String) -> void:
	if not is_editable(li):
		return
	var l: Dictionary = pattern.lanes[li]
	l["steps"] = _replace_step(String(l.steps), step, ch)
	_changed()


## Next state after a click: rest, soft, normal, accent, rest...
static func cycled(ch: String) -> String:
	var i := CYCLE.find(ch)
	return CYCLE[(i + 1) % CYCLE.size()] if i >= 0 else "."


func toggle_mute(li: int) -> void:
	var l: Dictionary = pattern.lanes[li]
	l["mute"] = not bool(l.get("mute", false))
	_changed()


func _changed() -> void:
	pattern.emit_changed()
	edited.emit()
	queue_redraw()


static func _step_chars(s: String) -> Array:
	var out := []
	for ch in s:
		if ch in [" ", "|", "\t", "\n"]:
			continue
		out.append(ch)
	return out


## `s` with its `step`-th step character replaced, keeping spaces and bars.
static func _replace_step(s: String, step: int, ch: String) -> String:
	var k := 0
	for i in s.length():
		if s[i] in [" ", "|", "\t", "\n"]:
			continue
		if k == step:
			return s.substr(0, i) + ch + s.substr(i + 1)
		k += 1
	# Past the end: pad with rests.
	return s + ".".repeat(step - k) + ch


func _resize() -> void:
	var cols := 0
	for li in lane_count():
		cols = maxi(cols, lane_length(li))
	custom_minimum_size = Vector2(NAME_W + cols * CELL + 4.0, lane_count() * CELL + 4.0)


func _gui_input(e: InputEvent) -> void:
	if pattern == null or not (e is InputEventMouseButton) or not e.pressed:
		return
	var p: Vector2 = e.position
	var li := int(p.y / CELL)
	if li < 0 or li >= lane_count():
		return
	if p.x < NAME_W:
		toggle_mute(li)
		accept_event()
		return
	var step := int((p.x - NAME_W) / CELL)
	if step < 0 or step >= lane_length(li):
		return
	if e.button_index == MOUSE_BUTTON_RIGHT:
		set_cell(li, step, ".")
	elif e.button_index == MOUSE_BUTTON_LEFT:
		set_cell(li, step, cycled(cell(li, step)))
	accept_event()


func _draw() -> void:
	if pattern == null:
		return
	var font := get_theme_default_font()
	var fs := 11
	var accent := Color("#ffcf3a")
	for li in lane_count():
		var l: Dictionary = pattern.lanes[li]
		var y := li * CELL
		var muted := bool(l.get("mute", false))
		var name_col := Color(1, 1, 1, 0.35 if muted else 0.85)
		draw_string(font, Vector2(2, y + CELL - 5), String(l.get("name", "lane%d" % li)).left(9), HORIZONTAL_ALIGNMENT_LEFT, NAME_W - 4, fs, name_col)
		var n := lane_length(li)
		var spb := maxi(1, pattern.steps_per_beat)
		var head := posmod(int(floor(playhead)), n) if playhead >= 0.0 and n > 0 else -1
		for s in n:
			var r := Rect2(NAME_W + s * CELL + 1, y + 1, CELL - 2, CELL - 2)
			var beat_start := s % spb == 0
			draw_rect(r, Color(1, 1, 1, 0.10 if beat_start else 0.05))
			var ch := cell(li, s)
			var level: float = {"X": 1.0, "x": 0.7, "o": 0.4, "?": 0.55}.get(ch, 0.0)
			if ch.is_valid_int() and ch != "0":
				level = ch.to_int() / 9.0
			if level > 0.0:
				var c := accent
				c.a = (0.25 + 0.75 * level) * (0.4 if muted else 1.0)
				draw_rect(r.grow(-1), c)
			elif ch in ["-", "~"]:
				draw_line(Vector2(r.position.x, r.get_center().y), Vector2(r.end.x, r.get_center().y), Color(accent, 0.6), 2.0)
			if s == head:
				draw_rect(r, Color(1, 1, 1, 0.8), false, 1.5)
			if not is_editable(li):
				draw_rect(r, Color(0, 0, 0, 0.25))
