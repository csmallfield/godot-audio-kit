# SPDX-License-Identifier: Apache-2.0
## The Sequencer's scenes: a column per scene, a cell per track, as in a clip
## launcher. Drawn in one `_draw`.
##
##   Click a scene's name    launch it (on the next bar, beat or scene end)
##   Click a cell            put the loop picked in the browser there
##   Right-click a cell      clear it
##   Double-click a cell     edit its loop (the Loops tab), the scene around it
##
## Edits go out as `edit("scenes", value, label)` for the Sequencer to commit.
@tool
class_name AKSceneGrid
extends Control

signal edit(property: String, value: Variant, label: String)
signal launch(scene: int)
signal open_loop(path: String, scene: int, track: String)
signal selection_changed()

const NAME_W := 96.0
const HEAD_H := 28.0
const CELL_W := 120.0
const ROW_H := 30.0

var arrangement: AKArrangement
var pending_loop := ""
var selected_scene := -1
## The scene sounding and the one queued (-1 = none), drawn highlighted.
var playing_scene := -1:
	set(v):
		if v != playing_scene:
			playing_scene = v
			queue_redraw()
var queued_scene := -1:
	set(v):
		if v != queued_scene:
			queued_scene = v
			queue_redraw()


## Pixels per layout unit: the editor's scale (2 on a Retina Mac, 1 on a
## plain display), read once, so the drawing keeps up with the rest of the
## editor. Every size above is in layout units; drawing and mouse input go
## through this factor.
var ui_scale := 1.0


static func _editor_scale() -> float:
	return AKUiScale.factor()


func _init() -> void:
	ui_scale = _editor_scale()
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_arrangement(a: AKArrangement) -> void:
	arrangement = a
	selected_scene = -1
	refresh()


func refresh() -> void:
	if arrangement:
		custom_minimum_size = Vector2(NAME_W + (arrangement.scenes.size() + 1) * CELL_W, HEAD_H + arrangement.tracks.size() * ROW_H + 8.0) * ui_scale
	queue_redraw()


func header_rect(si: int) -> Rect2:
	return Rect2(NAME_W + si * CELL_W, 0, CELL_W - 2.0, HEAD_H - 2.0)


func cell_rect(si: int, ti: int) -> Rect2:
	return Rect2(NAME_W + si * CELL_W, HEAD_H + ti * ROW_H, CELL_W - 2.0, ROW_H - 2.0)


## [scene, track] under `pos`; scene -1 off the grid, track -1 in the header.
func cell_at(pos: Vector2) -> Array:
	if arrangement == null or pos.x < NAME_W:
		return [-1, -1]
	var si := floori((pos.x - NAME_W) / CELL_W)
	if si < 0 or si >= arrangement.scenes.size():
		return [-1, -1]
	if pos.y < HEAD_H:
		return [si, -1]
	var ti := floori((pos.y - HEAD_H) / ROW_H)
	return [si, ti if ti < arrangement.tracks.size() else -2]


## The loop in a cell ("" = empty).
func cell_loop(si: int, ti: int) -> String:
	var clips: Dictionary = arrangement.scenes[si].get("clips", {})
	var tn := String(arrangement.tracks[ti].get("name", ""))
	var v: Variant = clips.get(tn, clips.get(StringName(tn), ""))
	return (v as Resource).resource_path if v is Resource else String(v)


func set_cell(si: int, ti: int, loop: String) -> void:
	var sc := _scenes_copy()
	var clips: Dictionary = sc[si].get("clips", {})
	var tn := String(arrangement.tracks[ti].get("name", ""))
	clips.erase(StringName(tn))
	if loop == "":
		clips.erase(tn)
	else:
		clips[tn] = loop
	sc[si]["clips"] = clips
	edit.emit("scenes", sc, "Scene clip" if loop != "" else "Clear scene clip")


func _scenes_copy() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in arrangement.scenes:
		out.append(s.duplicate(true))
	return out


func _gui_input(event: InputEvent) -> void:
	if arrangement == null or not event is InputEventMouseButton or not event.pressed:
		return
	event = event.xformed_by(Transform2D().scaled(Vector2.ONE / ui_scale))
	var mb := event as InputEventMouseButton
	var at := cell_at(mb.position)
	var si: int = at[0]
	var ti: int = at[1]
	if si < 0:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if ti == -1:
			selected_scene = si
			selection_changed.emit()
			launch.emit(si)
		elif ti >= 0:
			if mb.double_click:
				var p := cell_loop(si, ti)
				if p != "":
					open_loop.emit(p, si, String(arrangement.tracks[ti].name))
			elif pending_loop != "":
				set_cell(si, ti, pending_loop)
			selected_scene = si
			selection_changed.emit()
		accept_event()
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		if ti >= 0:
			set_cell(si, ti, "")
		elif ti == -1:
			selected_scene = si
			selection_changed.emit()
		accept_event()


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(ui_scale, ui_scale))
	draw_rect(Rect2(Vector2.ZERO, size / ui_scale), Color(0.12, 0.13, 0.15))
	if arrangement == null:
		return
	var font := get_theme_default_font()
	var fs := 11
	for ti in arrangement.tracks.size():
		var y := HEAD_H + ti * ROW_H
		draw_rect(Rect2(0, y, NAME_W - 2.0, ROW_H - 2.0), Color(0.2, 0.21, 0.25))
		draw_string(font, Vector2(6, y + ROW_H * 0.5 + 4), String(arrangement.tracks[ti].get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, NAME_W - 10, fs, Color(0.92, 0.92, 0.92))
	for si in arrangement.scenes.size():
		var hr := header_rect(si)
		var hc := Color(0.25, 0.3, 0.4)
		if si == playing_scene:
			hc = Color(0.25, 0.55, 0.3)
		elif si == queued_scene:
			hc = Color(0.55, 0.5, 0.2)
		draw_rect(hr, hc)
		if si == selected_scene:
			draw_rect(hr, Color.WHITE, false, 1.0)
		var s: Dictionary = arrangement.scenes[si]
		draw_string(font, hr.position + Vector2(6, 17), "▶ %s · %s" % [s.get("name", ""), _bars_text(arrangement.scene_bars(si))], HORIZONTAL_ALIGNMENT_LEFT, hr.size.x - 8, fs, Color.WHITE)
		for ti in arrangement.tracks.size():
			var r := cell_rect(si, ti)
			var p := cell_loop(si, ti)
			if p == "":
				draw_rect(r, Color(0.16, 0.17, 0.2))
				draw_string(font, r.position + Vector2(r.size.x * 0.5 - 3, 19), "-", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.5, 0.5, 0.5))
			else:
				draw_rect(r, Color.from_hsv(fposmod(ti * 0.13 + 0.55, 1.0), 0.45, 0.75 if si == playing_scene else 0.6))
				draw_string(font, r.position + Vector2(6, 19), p.get_file().get_basename(), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 8, fs, Color(0.08, 0.08, 0.1))


static func _bars_text(b: float) -> String:
	return "%s bar%s" % [str(b) if b != floorf(b) else str(int(b)), "" if b == 1.0 else "s"]
