# SPDX-License-Identifier: Apache-2.0
## The Sequencer's timeline: bars across, tracks down, clips of loops, and a
## strip of named markers above the bars. Drawn in one `_draw`.
##
##   Click an empty track    place the loop picked in the browser there
##                           (snapped), as long as the loop
##   Drag a clip's body      move it (Alt: copy it); snap to the bar, beat or off
##   Drag its right edge     lengthen or shorten it (more or fewer repeats)
##   Drag its left edge      start part-way into the loop
##   Right-click a clip      delete it; Delete removes the selected one
##   Double-click a clip     edit its loop (the Loops tab)
##   Marker strip            click to add a marker, drag one to move it,
##                           right-click to remove it
##   Ruler                   click to move the playhead
##
## Edits go out as `edit(property, value, label)` for the Sequencer to
## commit as one undoable action each; a drag is one edit.
@tool
class_name AKTimelineView
extends Control

signal edit(property: String, value: Variant, label: String)
signal open_loop(path: String, clip: int)
signal seek(bar: float)
signal selection_changed()

const NAME_W := 96.0
const MARK_H := 18.0
const RULER_H := 16.0
const TRACK_H := 30.0
const EDGE_PX := 6.0

var arrangement: AKArrangement
var bar_px := 40.0
## "bar", "beat" or "off".
var snap := "bar"
## The loop placed by a click on an empty track ("" = none).
var pending_loop := ""
var selected_clip := -1
var selected_marker := -1
var playhead_bar := -1.0:
	set(v):
		if v != playhead_bar:
			playhead_bar = v
			queue_redraw()

var _drag := {}
var _work: Array = []   # the timeline (or markers) while dragging


## Pixels per layout unit: the editor's scale (2 on a Retina Mac, 1 on a
## plain display), read once, so the drawing keeps up with the rest of the
## editor. Every size above is in layout units; drawing and mouse input go
## through this factor.
var ui_scale := 1.0


static func _editor_scale() -> float:
	return AKUiScale.factor()


func _init() -> void:
	ui_scale = _editor_scale()
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func set_arrangement(a: AKArrangement) -> void:
	arrangement = a
	selected_clip = -1
	selected_marker = -1
	_drag = {}
	refresh()


func refresh() -> void:
	if arrangement:
		custom_minimum_size = Vector2(bar_to_x(maxf(arrangement.timeline_bars() + 8.0, 32.0)), tracks_top() + arrangement.tracks.size() * TRACK_H + 8.0) * ui_scale
	queue_redraw()


func tracks_top() -> float:
	return MARK_H + RULER_H


func bar_to_x(bar: float) -> float:
	return NAME_W + bar * bar_px


func x_to_bar(x: float) -> float:
	return (x - NAME_W) / bar_px


func track_y(ti: int) -> float:
	return tracks_top() + ti * TRACK_H


func y_to_track(y: float) -> int:
	var i := floori((y - tracks_top()) / TRACK_H)
	return i if i >= 0 and i < arrangement.tracks.size() else -1


## Where clip `ci` is drawn.
func clip_rect(ci: int) -> Rect2:
	var c: Dictionary = _clips()[ci]
	var ti := arrangement.track_index(String(c.track))
	return Rect2(bar_to_x(float(c.bar)), track_y(ti) + 2.0, float(c.bars) * bar_px, TRACK_H - 4.0)


## Bars a snap step takes ("off": none).
func snap_bars() -> float:
	match snap:
		"bar":
			return 1.0
		"beat":
			return 1.0 / maxf(1.0, float(arrangement.tempo.beats_per_bar))
	return 0.0


func snap_bar(bar: float) -> float:
	var s := snap_bars()
	return roundf(bar / s) * s if s > 0.0 else snappedf(bar, 1e-4)


func clip_at(pos: Vector2) -> int:
	var cs := _clips()
	for i in range(cs.size() - 1, -1, -1):
		var c: Dictionary = cs[i]
		if arrangement.track_index(String(c.track)) < 0:
			continue
		if clip_rect(i).has_point(pos):
			return i
	return -1


func marker_at(x: float) -> int:
	for i in arrangement.markers.size():
		if absf(bar_to_x(float(arrangement.markers[i].bar)) - x) <= EDGE_PX:
			return i
	return -1


func _clips() -> Array:
	return _work if _drag.get("what", "") == "clip" else arrangement.timeline


func _marks() -> Array:
	return _work if _drag.get("what", "") == "marker" else arrangement.markers


# ------------------------------------------------------------------ input

func _gui_input(event: InputEvent) -> void:
	if arrangement == null:
		return
	event = event.xformed_by(Transform2D().scaled(Vector2.ONE / ui_scale))
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and is_inside_tree():
			grab_focus()
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and mb.double_click:
				var ci := clip_at(mb.position)
				if ci >= 0:
					_drag = {}
					open_loop.emit(_loop_path(arrangement.timeline[ci].get("loop")), ci)
			elif mb.pressed:
				_press(mb.position, mb.alt_pressed)
			else:
				_release(mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_right(mb.position)
			accept_event()
	elif event is InputEventMouseMotion and not _drag.is_empty():
		_motion((event as InputEventMouseMotion).position)
		accept_event()
	elif event is InputEventKey and event.pressed and (event as InputEventKey).keycode in [KEY_DELETE, KEY_BACKSPACE]:
		if selected_clip >= 0:
			delete_clip(selected_clip)
			accept_event()


func _press(pos: Vector2, alt: bool) -> void:
	if pos.y < MARK_H:
		var mi := marker_at(pos.x)
		if mi < 0 and pos.x >= NAME_W:
			var ms := _markers_copy()
			ms.append({name = "section %d" % (ms.size() + 1), bar = maxf(0.0, snap_bar(x_to_bar(pos.x)))})
			selected_marker = ms.size() - 1
			edit.emit("markers", ms, "Add marker")
			selection_changed.emit()
			return
		selected_marker = mi
		selection_changed.emit()
		_work = _markers_copy()
		_drag = {what = "marker", index = mi, from = pos, moved = false}
		return
	if pos.y < tracks_top():
		if pos.x >= NAME_W:
			seek.emit(maxf(0.0, snap_bar(x_to_bar(pos.x))))
		return
	var ti := y_to_track(pos.y)
	if ti < 0 or pos.x < NAME_W:
		return
	var ci := clip_at(pos)
	if ci < 0:
		if pending_loop != "":
			place_clip(String(arrangement.tracks[ti].name), pending_loop, maxf(0.0, floorf(x_to_bar(pos.x) / maxf(1e-6, snap_bars())) * snap_bars() if snap_bars() > 0.0 else x_to_bar(pos.x)))
		return
	selected_clip = ci
	selection_changed.emit()
	var r := clip_rect(ci)
	var mode := "move"
	if r.end.x - pos.x <= EDGE_PX:
		mode = "end"
	elif pos.x - r.position.x <= EDGE_PX:
		mode = "start"
	_work = _timeline_copy()
	if alt and mode == "move":
		_work.append(_work[ci].duplicate())
		ci = _work.size() - 1
	_drag = {what = "clip", mode = mode, index = ci, from = pos, moved = false, orig = _work[ci].duplicate(), copy = alt and mode == "move"}


func _motion(pos: Vector2) -> void:
	if _drag.what == "marker":
		_drag.moved = true
		_work[_drag.index]["bar"] = maxf(0.0, snap_bar(x_to_bar(pos.x)))
		queue_redraw()
		return
	if pos.distance_to(_drag.from) < 3.0 and not _drag.moved:
		return
	_drag.moved = true
	var o: Dictionary = _drag.orig
	var c: Dictionary = _work[_drag.index]
	var d := x_to_bar(pos.x) - x_to_bar(_drag.from.x)
	match String(_drag.mode):
		"move":
			c["bar"] = maxf(0.0, snap_bar(float(o.bar) + d))
			var ti := y_to_track(clampf(pos.y, tracks_top(), tracks_top() + arrangement.tracks.size() * TRACK_H - 1.0))
			if ti >= 0:
				c["track"] = String(arrangement.tracks[ti].name)
		"end":
			var step := maxf(snap_bars(), 1.0 / maxf(1.0, float(arrangement.tempo.beats_per_bar)))
			c["bars"] = maxf(step, snap_bar(float(o.bar) + float(o.bars) + d) - float(o.bar))
		"start":
			var end := float(o.bar) + float(o.bars)
			var nb := clampf(snap_bar(float(o.bar) + d), 0.0, end - 0.25)
			c["bar"] = nb
			c["bars"] = end - nb
			c["offset_bars"] = maxf(0.0, float(o.get("offset_bars", 0.0)) + nb - float(o.bar))
	queue_redraw()


func _release(pos: Vector2) -> void:
	if _drag.is_empty():
		return
	if _drag.what == "marker":
		var ms := _work
		_drag = {}
		_work = []
		edit.emit("markers", ms, "Move marker")
		return
	if _drag.moved:
		_motion(pos)
	var moved: bool = _drag.moved
	var label: String = "Copy clip" if _drag.copy else {"move": "Move clip", "end": "Clip length", "start": "Clip start"}[_drag.mode]
	var tl := _work
	var idx: int = _drag.index
	_drag = {}
	_work = []
	if moved:
		selected_clip = idx
		edit.emit("timeline", tl, label)
	queue_redraw()


func _right(pos: Vector2) -> void:
	if pos.y < MARK_H:
		var mi := marker_at(pos.x)
		if mi >= 0:
			var ms := _markers_copy()
			ms.remove_at(mi)
			selected_marker = -1
			edit.emit("markers", ms, "Remove marker")
		return
	var ci := clip_at(pos)
	if ci >= 0:
		delete_clip(ci)


# ------------------------------------------------------------------ edits

## Put `loop` on `track_name` at `bar` (default length: the loop's bars).
func place_clip(track_name: String, loop: String, bar: float, bars := 0.0, offset := 0.0) -> int:
	var l := AKArrangement.loop_of(loop)
	var tl := _timeline_copy()
	tl.append({track = track_name, loop = loop, bar = bar, bars = bars if bars > 0.0 else float(l.bars if l else 1), offset_bars = offset})
	selected_clip = tl.size() - 1
	edit.emit("timeline", tl, "Add clip")
	return selected_clip


func delete_clip(ci: int) -> void:
	var tl := _timeline_copy()
	tl.remove_at(ci)
	selected_clip = -1
	edit.emit("timeline", tl, "Delete clip")


func _timeline_copy() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in arrangement.timeline:
		out.append(c.duplicate(true))
	return out


func _markers_copy() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in arrangement.markers:
		out.append(m.duplicate(true))
	return out


static func _loop_path(v: Variant) -> String:
	if v is Resource:
		return (v as Resource).resource_path
	return String(v) if v != null else ""


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(ui_scale, ui_scale))
	draw_rect(Rect2(Vector2.ZERO, size / ui_scale), Color(0.12, 0.13, 0.15))
	if arrangement == null:
		return
	var font := get_theme_default_font()
	var fs := 11
	var w := size.x / ui_scale
	var nt := arrangement.tracks.size()
	var bottom := tracks_top() + nt * TRACK_H
	var bpb := maxi(1, int(arrangement.tempo.beats_per_bar))
	# Bars and beats.
	var bars := ceili(x_to_bar(w))
	for b in bars + 1:
		var x := bar_to_x(b)
		draw_line(Vector2(x, MARK_H), Vector2(x, bottom), Color(1, 1, 1, 0.3 if b % 4 == 0 else 0.14), 1.0)
		if bar_px >= 24.0:
			for k in range(1, bpb):
				var xb := x + k * bar_px / bpb
				draw_line(Vector2(xb, tracks_top()), Vector2(xb, bottom), Color(1, 1, 1, 0.05), 1.0)
		if b % (1 if bar_px >= 30.0 else 4) == 0:
			draw_string(font, Vector2(x + 2, MARK_H + RULER_H - 4), str(b + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 1, Color(0.75, 0.75, 0.75))
	# Sections and markers.
	var secs := arrangement.timeline_sections()
	for si in secs.size():
		var s: Dictionary = secs[si]
		var x0 := bar_to_x(float(s.bar))
		draw_rect(Rect2(x0, 0, float(s.bars) * bar_px, MARK_H), Color(0.2, 0.25, 0.32) if si % 2 == 0 else Color(0.17, 0.21, 0.27))
	var marks := _marks()
	for mi in marks.size():
		var m: Dictionary = marks[mi]
		var x := bar_to_x(float(m.bar))
		var c := Color(1, 0.85, 0.3) if mi == selected_marker else Color(0.9, 0.9, 0.9)
		draw_line(Vector2(x, 0), Vector2(x, bottom), Color(c, 0.6), 1.0)
		draw_string(font, Vector2(x + 3, MARK_H - 5), String(m.name), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
	# Track rows.
	for ti in nt:
		var y := track_y(ti)
		draw_rect(Rect2(0, y, NAME_W - 2.0, TRACK_H - 1.0), Color(0.2, 0.21, 0.25))
		draw_string(font, Vector2(6, y + TRACK_H * 0.5 + 4), String(arrangement.tracks[ti].get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, NAME_W - 10, fs, Color(0.92, 0.92, 0.92))
		draw_line(Vector2(NAME_W, y + TRACK_H), Vector2(w, y + TRACK_H), Color(1, 1, 1, 0.06), 1.0)
	# Clips.
	var cs := _clips()
	for ci in cs.size():
		var c: Dictionary = cs[ci]
		var ti := arrangement.track_index(String(c.track))
		if ti < 0:
			continue
		var r := clip_rect(ci)
		var col := Color.from_hsv(fposmod(ti * 0.13 + 0.55, 1.0), 0.45, 0.75)
		draw_rect(r, col)
		# Loop repeats inside the clip.
		var l := AKArrangement.loop_of(c.get("loop"))
		if l:
			var lb := float(l.bars)
			var k := ceilf(float(c.get("offset_bars", 0.0)) / lb) * lb - float(c.get("offset_bars", 0.0))
			while k < float(c.bars) - 1e-6:
				if k > 1e-6:
					var xr := r.position.x + k * bar_px
					draw_line(Vector2(xr, r.position.y), Vector2(xr, r.end.y), Color(0, 0, 0, 0.35), 1.0)
				k += lb
		var name := _loop_path(c.get("loop")).get_file().get_basename()
		draw_string(font, r.position + Vector2(4, 15), name, HORIZONTAL_ALIGNMENT_LEFT, maxf(1.0, r.size.x - 6.0), fs, Color(0.08, 0.08, 0.1))
		if ci == selected_clip:
			draw_rect(r.grow(1.0), Color.WHITE, false, 2.0)
	if playhead_bar >= 0.0:
		var px := bar_to_x(playhead_bar)
		draw_line(Vector2(px, MARK_H), Vector2(px, bottom), Color(1, 0.9, 0.3), 2.0)
