# SPDX-License-Identifier: Apache-2.0
## The Loops tab's grid: an AKLoop's notes drawn over rows (a piano for synth
## and sample loops, the kit's pieces for percussive ones) and columns in
## ticks, with a velocity strip underneath. Everything is drawn in one
## `_draw`, so a long, dense loop stays cheap.
##
##   Click an empty cell    a note one cell long at the default velocity;
##                          drag right to make it longer
##   Click a note           delete it
##   Drag a note's body     move it (time and row; the selection moves with it)
##   Drag its right edge    resize it
##   Shift while dragging   snap to the next finer division
##   Right-drag             box-select; then arrows move by a cell or a row
##                          (Shift+arrows: an octave), Ctrl+D duplicates,
##                          Delete removes, Ctrl+A selects all
##   Velocity strip         drag a bar up or down (the selection, if any)
##   Piano / piece column   click to audition the row; a kit row's M mutes it
##
## Percussive rows ignore length unless the piece is gated: a hit is a cell.
## Every edit is one undoable action through `undo` (the editor's history in
## the editor, a local UndoRedo elsewhere); a drag is one step.
@tool
class_name AKLoopGrid
extends Control

## After an edit is committed (the loop is already updated).
signal edited(label: String)
## A row's key or name was clicked: play it.
signal audition(row: int)
## A kit row was muted or unmuted.
signal mutes_changed()

const KEY_W := 88.0
const HEADER_H := 18.0
const VEL_H := 56.0
const GAP := 6.0
const EDGE_PX := 5.0
const BLACK := [1, 3, 6, 8, 10]

## An UndoRedo or EditorUndoRedoManager; null makes edits immediate.
var undo: Object
var loop: AKLoop
## Pixels per 16th note.
var cell_px := 22.0
var row_px := 16.0
## Velocity of new notes.
var default_velocity := 0.8
## The lowest piano row and how many semitones are shown above it.
var view_low := 48
var view_span := 24
## Scale highlighting: root pitch class (0 = C) and a scale name from
## AKNotes.SCALES ("" = none). `fold` shows only the rows in the scale.
var scale_root := 0
var scale_name := ""
var fold := false
## Chord highlighting: a parsed chord (AKChords.parse) or {} for none. Its
## rows get a warm tint and the interval ("R", "b3", "9") by the key.
var chord := {}
## Kit rows muted in the tab (by piece index): not saved with the loop.
var muted := {}
## Indices into loop.notes.
var selection: Array[int] = []
## Where the music is, in ticks into the loop (-1 = not playing).
var playhead := -1.0:
	set(v):
		if v != playhead:
			playhead = v
			queue_redraw()

var _own_undo: UndoRedo
var _drag := {}


func _init() -> void:
	_own_undo = UndoRedo.new()
	undo = _own_undo
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _own_undo:
		_own_undo.free()


func set_loop(l: AKLoop) -> void:
	loop = l
	selection.clear()
	muted.clear()
	_drag = {}
	if loop and loop.kind != "percussive":
		if loop.notes.is_empty():
			view_low = 48   # a new loop starts on C3..C5
			view_span = 24
		fit_view()
	_resize()
	queue_redraw()


## Show the notes: the piano range moves to hold them (two octaves at least).
func fit_view() -> void:
	if loop == null or loop.notes.is_empty():
		return
	var lo := 127
	var hi := 0
	for n: Array in loop.notes:
		lo = mini(lo, int(n[2]))
		hi = maxi(hi, int(n[2]))
	if lo >= view_low and hi <= view_low + view_span:
		return
	view_low = clampi(lo - (lo % 12), 0, 127 - view_span)
	view_span = maxi(24, ceili((hi - view_low + 1) / 12.0) * 12)


## Move the piano range by octaves.
func shift_octave(octaves: int) -> void:
	view_low = clampi(view_low + 12 * octaves, 0, 127 - view_span)
	_resize()
	queue_redraw()


func is_kit() -> bool:
	return loop != null and loop.kind == "percussive"


func kit() -> AKKit:
	return loop.instrument as AKKit if loop else null


## Row values from top to bottom: MIDI notes (high first) or piece indices.
func rows() -> Array[int]:
	var out: Array[int] = []
	if loop == null:
		return out
	if is_kit():
		var k := kit()
		for i in (k.piece_count() if k else 0):
			out.append(i)
		return out
	for m in range(view_low + view_span, view_low - 1, -1):
		if m < 0 or m > 127:
			continue
		if fold and scale_name != "" and not in_scale(m):
			continue
		out.append(m)
	return out


func in_scale(midi: int) -> bool:
	if scale_name == "" or not AKNotes.SCALES.has(scale_name):
		return true
	return posmod(midi - scale_root, 12) in AKNotes.SCALES[scale_name]


## Whether a row is a tone of the highlighted chord (false with no chord).
func in_chord(midi: int) -> bool:
	return chord.get("ok", false) and (chord.pcs as Array).has(posmod(midi, 12))


## A row's tint: the piano's light and dark rows, then the scale (cool) and
## the chord (warm) on top; their roots a little stronger.
func row_color(row: int) -> Color:
	var c := Color(0.16, 0.17, 0.2)
	if posmod(row, 12) in BLACK:
		c = Color(0.13, 0.14, 0.16)
	if scale_name != "" and in_scale(row):
		var root := posmod(row - scale_root, 12) == 0
		c = c.lerp(Color(0.3, 0.5, 0.85), 0.2 if root else 0.1)
	if in_chord(row):
		var croot := posmod(row, 12) == int(chord.root)
		c = c.lerp(Color(0.95, 0.65, 0.25), 0.3 if croot else 0.17)
	return c


func row_height() -> float:
	return 22.0 if is_kit() else row_px


func px_per_tick() -> float:
	return cell_px / 24.0


func grid_height() -> float:
	return rows().size() * row_height()


func tick_to_x(tick: float) -> float:
	return KEY_W + tick * px_per_tick()


func x_to_tick(x: float) -> float:
	return (x - KEY_W) / px_per_tick()


## The y of a row value's top, or -1 when it isn't shown.
func row_to_y(row: int) -> float:
	var i := rows().find(row)
	return HEADER_H + i * row_height() if i >= 0 else -1.0


## The row value at `y`, or -1 outside the rows.
func y_to_row(y: float) -> int:
	var r := rows()
	var i := floori((y - HEADER_H) / row_height())
	return r[i] if i >= 0 and i < r.size() else -1


## Where a cell or note is drawn (length in ticks; 0 = one cell).
func cell_rect(tick: int, row: int, length := 0) -> Rect2:
	var len := length if length > 0 else loop.cell_ticks()
	return Rect2(tick_to_x(tick), row_to_y(row), len * px_per_tick(), row_height())


## The centre of the cell at (tick, row): where to click it.
func cell_center(tick: int, row: int) -> Vector2:
	return cell_rect(tick, row).get_center()


## The y range of the velocity strip.
func vel_top() -> float:
	return HEADER_H + grid_height() + GAP


## Ticks a drawn note covers (percussive pieces that aren't gated: one cell).
func shown_length(n: Array) -> int:
	if is_kit() and kit() and not kit().is_gated(int(n[2])):
		return loop.cell_ticks()
	return maxi(1, int(n[1]))


## Index of the note under `pos`, or -1.
func note_at(pos: Vector2) -> int:
	var row := y_to_row(pos.y)
	if row < 0 or pos.x < KEY_W:
		return -1
	var t := x_to_tick(pos.x)
	for i in range(loop.notes.size() - 1, -1, -1):
		var n: Array = loop.notes[i]
		if int(n[2]) == row and t >= int(n[0]) and t < int(n[0]) + shown_length(n):
			return i
	return -1


# ------------------------------------------------------------------ edits

## Add a note (ticks); returns its index.
func add_note(tick: int, length: int, row: int, velocity := -1.0) -> int:
	var ns := _notes()
	ns.append([tick, length, row, snappedf(velocity if velocity >= 0.0 else default_velocity, 0.001)])
	_commit(ns, "Add note")
	return ns.size() - 1


func delete_notes(idx: Array) -> void:
	if idx.is_empty():
		return
	var ns := []
	for i in loop.notes.size():
		if not idx.has(i):
			ns.append(loop.notes[i].duplicate())
	selection.clear()
	_commit(ns, "Delete notes")


## Move notes by ticks and rows (semitones, or piece indices), clamped.
func move_notes(idx: Array, d_ticks: int, d_rows: int, label := "Move notes") -> void:
	var ns := _notes()
	var top := (kit().piece_count() - 1) if is_kit() and kit() else 127
	for i in idx:
		var n: Array = ns[i]
		n[0] = clampi(int(n[0]) + d_ticks, 0, loop.length_ticks() - 1)
		n[2] = clampi(int(n[2]) + d_rows, 0, top)
	_commit(ns, label)


func set_length(i: int, length: int) -> void:
	var ns := _notes()
	ns[i][1] = maxi(1, length)
	_commit(ns, "Resize note")


## Velocities by index: {index: velocity}.
func set_velocities(v: Dictionary, label := "Velocity") -> void:
	var ns := _notes()
	for i in v:
		ns[i][3] = snappedf(clampf(float(v[i]), 0.0, 1.0), 0.001)
	_commit(ns, label)


func select(idx: Array) -> void:
	selection.clear()
	for i in idx:
		if i >= 0 and i < loop.notes.size() and not selection.has(i):
			selection.append(i)
	queue_redraw()


func select_all() -> void:
	select(range(loop.notes.size()))


## Select the notes touching `rect` (local coordinates).
func select_rect(rect: Rect2) -> void:
	var out := []
	for i in loop.notes.size():
		var n: Array = loop.notes[i]
		var y := row_to_y(int(n[2]))
		if y < 0.0:
			continue
		var r := Rect2(tick_to_x(int(n[0])), y, shown_length(n) * px_per_tick(), row_height())
		if r.intersects(rect.abs()):
			out.append(i)
	select(out)


## Copy the selection to just after its own span; the copies become the selection.
func duplicate_selection() -> void:
	if selection.is_empty():
		return
	var start := 1 << 30
	var end := 0
	for i in selection:
		var n: Array = loop.notes[i]
		start = mini(start, int(n[0]))
		end = maxi(end, int(n[0]) + shown_length(n))
	var span := ceili(float(end - start) / loop.cell_ticks()) * loop.cell_ticks()
	var ns := _notes()
	var added := []
	for i in selection:
		var n: Array = loop.notes[i].duplicate()
		n[0] = int(n[0]) + span
		if int(n[0]) < loop.length_ticks():
			ns.append(n)
			added.append(ns.size() - 1)
	_commit(ns, "Duplicate notes")
	select(added)


## Arrow keys: a cell in time, a row (or an octave) in pitch, for the selection.
func nudge(cells: int, row_steps: int) -> void:
	if selection.is_empty():
		return
	move_notes(selection, cells * loop.cell_ticks(), row_steps, "Nudge notes")


## A velocity ramp across the selection (or every note), in time order.
func velocity_ramp(from: float, to: float) -> void:
	var idx := _targets()
	idx.sort_custom(func(a: int, b: int) -> bool: return int(loop.notes[a][0]) < int(loop.notes[b][0]))
	var v := {}
	for k in idx.size():
		v[idx[k]] = lerpf(from, to, float(k) / maxf(1.0, idx.size() - 1))
	set_velocities(v, "Velocity ramp")


## Move each targeted velocity by up to ±amount, seeded.
func randomise_velocity(amount: float, seed := 0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var v := {}
	for i in _targets():
		v[i] = float(loop.notes[i][3]) + rng.randf_range(-amount, amount)
	set_velocities(v, "Randomise velocity")


func set_mute(row: int, on: bool) -> void:
	if on:
		muted[row] = true
	else:
		muted.erase(row)
	queue_redraw()
	mutes_changed.emit()


func undo_last() -> void:
	if undo is UndoRedo:
		undo.undo()


func redo_last() -> void:
	if undo is UndoRedo:
		undo.redo()


func _targets() -> Array:
	return selection.duplicate() if not selection.is_empty() else range(loop.notes.size())


func _notes() -> Array:
	var out := []
	for n: Array in loop.notes:
		out.append(n.duplicate())
	return out


## One undoable action setting loop.notes to `ns` (from `before`, or the
## notes as they are now).
func _commit(ns: Array, label: String, before: Variant = null) -> void:
	var old: Array = before if before != null else _notes()
	var action := "Loop: " + label
	if undo == null:
		loop.notes = ns
		loop.emit_changed()
	elif undo is UndoRedo:
		undo.create_action(action)
		undo.add_do_property(loop, &"notes", ns)
		undo.add_undo_property(loop, &"notes", old)
		undo.add_do_method(loop.emit_changed)
		undo.add_undo_method(loop.emit_changed)
		undo.add_do_method(queue_redraw)
		undo.add_undo_method(queue_redraw)
		undo.commit_action()
	else:
		undo.call(&"create_action", action, UndoRedo.MERGE_DISABLE, loop)
		undo.call(&"add_do_property", loop, &"notes", ns)
		undo.call(&"add_undo_property", loop, &"notes", old)
		undo.call(&"add_do_method", loop, &"emit_changed")
		undo.call(&"add_undo_method", loop, &"emit_changed")
		undo.call(&"commit_action")
	_resize()
	queue_redraw()
	edited.emit(label)


# ------------------------------------------------------------------ input

func _gui_input(event: InputEvent) -> void:
	if loop == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			grab_focus()
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press(mb.position)
			else:
				_release(mb.position, mb.shift_pressed)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_drag = {mode = "box", from = mb.position, to = mb.position}
			elif _drag.get("mode", "") == "box":
				select_rect(Rect2(_drag.from, mb.position - _drag.from))
				_drag = {}
			accept_event()
	elif event is InputEventMouseMotion and not _drag.is_empty():
		_motion((event as InputEventMouseMotion).position, (event as InputEventMouseMotion).shift_pressed)
		accept_event()
	elif event is InputEventKey and event.pressed:
		if _key(event as InputEventKey):
			accept_event()


func _press(pos: Vector2) -> void:
	if pos.y < HEADER_H:
		return
	if pos.y >= vel_top():
		_drag = {mode = "velocity", before = _notes()}
		_velocity_at(pos)
		return
	var row := y_to_row(pos.y)
	if row < 0:
		return
	if pos.x < KEY_W:
		if is_kit() and pos.x < 18.0:
			set_mute(row, not muted.has(row))
		else:
			audition.emit(row)
		return
	var i := note_at(pos)
	if i >= 0:
		var n: Array = loop.notes[i]
		var right := tick_to_x(int(n[0]) + shown_length(n))
		var resizable := not is_kit() or (kit() and kit().is_gated(int(n[2])))
		var group: Array = selection.duplicate() if selection.has(i) else [i]
		_drag = {mode = "resize" if resizable and right - pos.x <= EDGE_PX else "move", index = i, from = pos, moved = false,
			before = _notes(), group = group, row = row, tick = x_to_tick(pos.x)}
		return
	var t := floori(x_to_tick(pos.x) / loop.cell_ticks()) * loop.cell_ticks()
	if t < 0 or t >= loop.length_ticks():
		return
	var before := _notes()
	var ns := _notes()
	ns.append([t, loop.cell_ticks(), row, snappedf(default_velocity, 0.001)])
	loop.notes = ns
	queue_redraw()
	_drag = {mode = "create", index = ns.size() - 1, from = pos, before = before, start = t}


func _motion(pos: Vector2, fine: bool) -> void:
	_drag["to"] = pos
	var cell := loop.cell_ticks()
	var snap := maxi(1, cell / 2) if fine else cell
	match String(_drag.get("mode", "")):
		"box":
			queue_redraw()
		"velocity":
			_velocity_at(pos)
		"create":
			var end := ceilf(x_to_tick(pos.x) / snap) * snap
			loop.notes[_drag.index][1] = maxi(snap, int(end) - int(_drag.start))
			queue_redraw()
		"resize":
			var n0: Array = _drag.before[_drag.index]
			var end := roundf(x_to_tick(pos.x) / snap) * snap
			loop.notes[_drag.index][1] = maxi(snap, int(end) - int(n0[0]))
			_drag.moved = true
			queue_redraw()
		"move":
			if pos.distance_to(_drag.from) < 3.0 and not _drag.moved:
				return
			_drag.moved = true
			var d_ticks := int(roundf((x_to_tick(pos.x) - float(_drag.tick)) / snap) * snap)
			var r := y_to_row(clampf(pos.y, HEADER_H, HEADER_H + grid_height() - 1.0))
			var d_rows := (r - int(_drag.row)) if r >= 0 else 0
			var top := (kit().piece_count() - 1) if is_kit() and kit() else 127
			for i in _drag.group:
				var n0: Array = _drag.before[i]
				loop.notes[i][0] = clampi(int(n0[0]) + d_ticks, 0, loop.length_ticks() - 1)
				loop.notes[i][2] = clampi(int(n0[2]) + d_rows, 0, top)
			queue_redraw()


func _release(pos: Vector2, fine: bool) -> void:
	var mode := String(_drag.get("mode", ""))
	if mode == "":
		return
	if mode in ["create", "resize", "move"]:
		_motion(pos, fine)
	var before: Array = _drag.get("before", [])
	var label: String = {"create": "Add note", "resize": "Resize note", "move": "Move notes", "velocity": "Velocity"}[mode]
	if mode == "move" and not _drag.moved:
		# A click on a note deletes it.
		var i: int = _drag.index
		loop.notes = before
		_drag = {}
		delete_notes([i])
		return
	var after := _notes()
	_drag = {}
	if after != before:
		loop.notes = before
		_commit(after, label, before)


func _velocity_at(pos: Vector2) -> void:
	var t := x_to_tick(pos.x)
	var v := clampf(1.0 - (pos.y - vel_top()) / VEL_H, 0.0, 1.0)
	# The note(s) whose start is nearest this x (the selection only, if any).
	var best := -1.0
	var hit := []
	for i in loop.notes.size():
		if not selection.is_empty() and not selection.has(i):
			continue
		var d := absf(float(loop.notes[i][0]) - t)
		if d > loop.cell_ticks() * 0.75:
			continue
		if best < 0.0 or d < best - 0.01:
			best = d
			hit = [i]
		elif absf(d - best) <= 0.01:
			hit.append(i)
	for i in hit:
		loop.notes[i][3] = snappedf(v, 0.001)
	queue_redraw()


func _key(k: InputEventKey) -> bool:
	match k.keycode:
		KEY_DELETE, KEY_BACKSPACE:
			delete_notes(selection.duplicate())
			return true
		KEY_LEFT, KEY_RIGHT:
			nudge(-1 if k.keycode == KEY_LEFT else 1, 0)
			return true
		KEY_UP, KEY_DOWN:
			var step := (12 if k.shift_pressed and not is_kit() else 1) * (1 if k.keycode == KEY_UP else -1)
			nudge(0, -step if is_kit() else step)
			return true
		KEY_D:
			if k.ctrl_pressed or k.meta_pressed:
				duplicate_selection()
				return true
		KEY_A:
			if k.ctrl_pressed or k.meta_pressed:
				select_all()
				return true
		KEY_ESCAPE:
			select([])
			return true
	return false


# ------------------------------------------------------------------ drawing

func _resize() -> void:
	if loop == null:
		custom_minimum_size = Vector2.ZERO
		return
	custom_minimum_size = Vector2(tick_to_x(loop.length_ticks()) + 8.0, vel_top() + VEL_H + 4.0)


func _draw() -> void:
	var bg := Color(0.12, 0.13, 0.15)
	draw_rect(Rect2(Vector2.ZERO, size), bg)
	if loop == null:
		return
	var font := get_theme_default_font()
	var fs := 11
	var r := rows()
	var rh := row_height()
	var w := tick_to_x(loop.length_ticks())
	var gh := grid_height()
	# Rows.
	for i in r.size():
		var y := HEADER_H + i * rh
		var row := r[i]
		var c := Color(0.16, 0.17, 0.2)
		if not is_kit():
			c = row_color(row)
		elif i % 2 == 1:
			c = Color(0.145, 0.155, 0.18)
		draw_rect(Rect2(KEY_W, y, w - KEY_W, rh), c)
		# The key / name column.
		var kc := Color(0.85, 0.85, 0.85) if not is_kit() and not posmod(row, 12) in BLACK else Color(0.25, 0.26, 0.3)
		if is_kit():
			kc = Color(0.22, 0.23, 0.27)
		draw_rect(Rect2(0, y, KEY_W - 2.0, rh - 1.0), kc)
		var label := ""
		if is_kit():
			label = kit().piece_name(row) if kit() else str(row)
			var mc := Color(0.9, 0.5, 0.2) if muted.has(row) else Color(0.4, 0.42, 0.48)
			draw_rect(Rect2(3, y + 4, 12, rh - 8), mc)
			draw_string(font, Vector2(6, y + rh - 7), "M", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color.BLACK)
			draw_string(font, Vector2(20, y + rh - 7), label, HORIZONTAL_ALIGNMENT_LEFT, KEY_W - 22, fs, Color(0.9, 0.9, 0.9))
		elif posmod(row, 12) == 0 or rh >= 16.0:
			label = AKNotes.midi_to_name(row)
			var tc := Color.BLACK if not posmod(row, 12) in BLACK else Color(0.8, 0.8, 0.8)
			draw_string(font, Vector2(4, y + rh - 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 1, tc)
		# Guide marks on the key's right edge: scale (cool) and chord (warm,
		# with the interval when the row is tall enough).
		if not is_kit():
			if scale_name != "" and in_scale(row):
				draw_rect(Rect2(KEY_W - 6.0, y + 1.0, 3.0, rh - 3.0), Color(0.35, 0.6, 1.0, 0.8))
			if in_chord(row):
				draw_rect(Rect2(KEY_W - 2.0, y, 2.0, rh - 1.0), Color(1.0, 0.7, 0.3))
				if rh >= 12.0:
					var iv := AKChords.interval_name(chord, row)
					var ic := Color(0.7, 0.33, 0.0) if not posmod(row, 12) in BLACK else Color(1.0, 0.72, 0.35)
					draw_string(font, Vector2(KEY_W - 38.0, y + rh - 4), iv, HORIZONTAL_ALIGNMENT_RIGHT, 30, fs, ic)
	# Columns: cells, beats, bars.
	var cell := loop.cell_ticks()
	var beat := AKLoop.TICKS_PER_BEAT
	var bar := beat * loop.beats_per_bar
	var t := 0
	while t <= loop.length_ticks():
		var x := tick_to_x(t)
		var col := Color(1, 1, 1, 0.05)
		if t % bar == 0:
			col = Color(1, 1, 1, 0.45)
		elif t % beat == 0:
			col = Color(1, 1, 1, 0.18)
		draw_line(Vector2(x, HEADER_H), Vector2(x, HEADER_H + gh), col, 1.0)
		draw_line(Vector2(x, vel_top()), Vector2(x, vel_top() + VEL_H), Color(col, col.a * 0.6), 1.0)
		if t % bar == 0 and t < loop.length_ticks():
			draw_string(font, Vector2(x + 3, HEADER_H - 5), "Bar %d" % (t / bar + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.8, 0.8, 0.8))
		t += cell
	# Notes.
	for i in loop.notes.size():
		var n: Array = loop.notes[i]
		var y := row_to_y(int(n[2]))
		if y < 0.0:
			continue
		var rect := Rect2(tick_to_x(int(n[0])) + 1.0, y + 1.0, maxf(3.0, shown_length(n) * px_per_tick() - 2.0), rh - 2.0)
		var v := float(n[3])
		var nc := Color(0.35, 0.65, 1.0).lerp(Color(1.0, 0.55, 0.25), v)
		if is_kit() and muted.has(int(n[2])):
			nc = nc.darkened(0.6)
		draw_rect(rect, nc)
		if selection.has(i):
			draw_rect(rect.grow(1.0), Color.WHITE, false, 2.0)
		if not loop.on_grid([int(n[0]), shown_length(n)] if is_kit() else n):
			draw_rect(Rect2(rect.position, Vector2(4, 4)), Color(1, 1, 0.3))   # off the current grid
		if int(n[0]) >= loop.length_ticks():
			draw_rect(rect, Color(1, 0, 0, 0.5), false, 1.0)
	# Velocity strip.
	var vt := vel_top()
	draw_rect(Rect2(KEY_W, vt, w - KEY_W, VEL_H), Color(0.1, 0.105, 0.12))
	draw_string(font, Vector2(4, vt + 14), "Velocity", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.7, 0.7, 0.7))
	for i in loop.notes.size():
		var n: Array = loop.notes[i]
		var x := tick_to_x(int(n[0]))
		var hgt := float(n[3]) * VEL_H
		var c := Color(1, 1, 1) if selection.has(i) else Color(0.5, 0.75, 1.0)
		draw_rect(Rect2(x + 1.0, vt + VEL_H - hgt, 4.0, hgt), c)
	# Box selection and playhead.
	if _drag.get("mode", "") == "box" and _drag.has("to"):
		var br := Rect2(_drag.from, _drag.to - _drag.from).abs()
		draw_rect(br, Color(1, 1, 1, 0.12))
		draw_rect(br, Color(1, 1, 1, 0.6), false, 1.0)
	if playhead >= 0.0:
		var px := tick_to_x(fmod(playhead, float(loop.length_ticks())))
		draw_line(Vector2(px, 0), Vector2(px, vt + VEL_H), Color(1, 0.9, 0.3), 2.0)
