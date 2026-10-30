# SPDX-License-Identifier: Apache-2.0
## The Sequencer's mixer: a strip per track and a master strip.
##
##   Track strip   meter, level (dB), pan, reverb send, M(ute), S(olo), the
##                 intensity range it fades in over (from, to), FX (edit its
##                 insert chain below)
##   Master strip  meter, the arrangement's intensity (what bakes use; live, the
##                 music's intensity while it plays), the shared reverb (room,
##                 damp, width, return), FX (the master chain)
##
## Edits go out as `edit(property, value, label, merge)` for the Sequencer to
## commit; slider drags merge into one undo step. `set_levels` feeds meters.
@tool
class_name AKMixerView
extends VBoxContainer

signal edit(property: String, value: Variant, label: String, merge: bool)
## Live intensity while playing (not saved).
signal live_intensity(x: float)

const STRIP_W := 128.0

var arrangement: AKArrangement
## The strip whose effects are shown: a track index, or -1 for the master.
var fx_target := -2
var fx_editor: AKFxChainEditor

var _strips: HBoxContainer
var _meters := {}     # track name or "master" -> AKMixerView.Meter
var _quiet := false


class Meter extends Control:
	var l := 0.0
	var r := 0.0

	func _init() -> void:
		custom_minimum_size = AKUiScale.px(22, 90)

	func set_peaks(pl: float, pr: float) -> void:
		# Instant attack, a gentle fall.
		l = maxf(pl, l * 0.85)
		r = maxf(pr, r * 0.85)
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.08, 0.1))
		var w := size.x * 0.5 - 1.0
		for c in 2:
			var v := l if c == 0 else r
			var db := 20.0 * log(maxf(v, 1e-6)) / log(10.0)
			var h := clampf((db + 60.0) / 60.0, 0.0, 1.0) * size.y
			var col := Color(0.3, 0.85, 0.4) if db < -6.0 else (Color(0.95, 0.8, 0.2) if db < -1.0 else Color(1.0, 0.3, 0.25))
			draw_rect(Rect2(c * (w + 2.0), size.y - h, w, h), col)


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = AKUiScale.px(0, 330)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_strips = HBoxContainer.new()
	scroll.add_child(_strips)
	fx_editor = AKFxChainEditor.new()
	fx_editor.edited.connect(_on_fx_edited)
	add_child(fx_editor)


func set_arrangement(a: AKArrangement) -> void:
	arrangement = a
	fx_target = -2
	refresh()


## Rebuild the strips from the arrangement (after an edit or undo).
func refresh() -> void:
	if arrangement == null or _quiet:
		return
	for c in _strips.get_children():
		_strips.remove_child(c)
		c.queue_free()
	_meters.clear()
	for ti in arrangement.tracks.size():
		_track_strip(ti)
	_master_strip()
	_show_fx()


## Meter levels: {track name or "master": [left, right]} (AKLive.levels()).
func set_levels(levels: Dictionary) -> void:
	for k in _meters:
		var v: Variant = levels.get(k)
		var m: Meter = _meters[k]
		if v is Array and v.size() >= 2:
			m.set_peaks(float(v[0]), float(v[1]))
		else:
			m.set_peaks(0.0, 0.0)


func meter(name: String) -> Meter:
	return _meters.get(name)


## Set a track setting (gain_db, pan, send, mute, solo, intensity, fx).
func set_track(ti: int, key: String, value: Variant, merge := false) -> void:
	var t := _tracks()
	if value == null:
		t[ti].erase(key)
	else:
		t[ti][key] = value
	_send("tracks", t, "%s %s" % [t[ti].get("name", ""), key], merge)


func set_reverb(key: String, value: float, merge := false) -> void:
	var rv := arrangement.reverb.duplicate(true)
	rv[key] = value
	_send("reverb", rv, "Reverb " + key, merge)


func set_intensity(x: float, merge := false) -> void:
	_send("intensity", clampf(x, 0.0, 1.0), "Intensity", merge)


## Show the insert chain of track `ti` (or the master, -1) under the strips.
func show_fx(ti: int) -> void:
	fx_target = ti
	_show_fx()


func _show_fx() -> void:
	if arrangement == null:
		return
	if fx_target == -1:
		fx_editor.master = true
		fx_editor.set_chain(arrangement.master_fx, "Master chain")
		fx_editor.visible = true
	elif fx_target >= 0 and fx_target < arrangement.tracks.size():
		fx_editor.master = false
		fx_editor.set_chain(arrangement.tracks[fx_target].get("fx", []), "Inserts: %s" % arrangement.tracks[fx_target].get("name", ""))
		fx_editor.visible = true
	else:
		fx_editor.visible = false


func _on_fx_edited(chain: Array, label: String, merge: bool) -> void:
	if fx_target == -1:
		var typed: Array[Dictionary] = []
		for e in chain:
			typed.append(e)
		_send("master_fx", typed, "Master: " + label, merge)
	elif fx_target >= 0:
		set_track(fx_target, "fx", chain if not chain.is_empty() else null, merge)


func _send(prop: String, value: Variant, label: String, merge: bool) -> void:
	_quiet = merge   # a drag: don't rebuild the strip under the mouse
	edit.emit(prop, value, label, merge)
	_quiet = false


func _tracks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t in arrangement.tracks:
		out.append(t.duplicate(true))
	return out


func _strip(title: String) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(STRIP_W, 0)
	_strips.add_child(pc)
	var box := VBoxContainer.new()
	pc.add_child(box)
	var l := Label.new()
	l.text = title
	l.clip_text = true
	box.add_child(l)
	return box


func _track_strip(ti: int) -> void:
	var t: Dictionary = arrangement.tracks[ti]
	var name := String(t.get("name", ""))
	var box := _strip(name)
	box.name = "strip_" + name.validate_node_name()
	var row := HBoxContainer.new()
	box.add_child(row)
	var m := Meter.new()
	row.add_child(m)
	_meters[name] = m
	var fader := VSlider.new()
	fader.min_value = -48.0
	fader.max_value = 12.0
	fader.step = 0.1
	fader.value = float(t.get("gain_db", 0.0))
	fader.custom_minimum_size = AKUiScale.px(24, 90)
	fader.name = "level"
	fader.tooltip_text = "Level (dB)"
	fader.value_changed.connect(func(v: float) -> void: set_track(ti, "gain_db", snappedf(v, 0.1), true))
	row.add_child(fader)
	var col := VBoxContainer.new()
	row.add_child(col)
	var ms := HBoxContainer.new()
	col.add_child(ms)
	ms.add_child(_toggle("M", bool(t.get("mute", false)), "Mute", func(on: bool) -> void: set_track(ti, "mute", on if on else null)))
	ms.add_child(_toggle("S", bool(t.get("solo", false)), "Solo", func(on: bool) -> void: set_track(ti, "solo", on if on else null)))
	var fx: Array = t.get("fx", [])
	var fxb := Button.new()
	fxb.text = "FX (%d)" % fx.size()
	fxb.name = "fx"
	fxb.pressed.connect(func() -> void: show_fx(ti))
	col.add_child(fxb)
	box.add_child(_slider("Pan", -1.0, 1.0, float(t.get("pan", 0.0)), func(v: float) -> void: set_track(ti, "pan", v, true)))
	box.add_child(_slider("Send", 0.0, 1.0, float(t.get("send", 0.0)), func(v: float) -> void: set_track(ti, "send", v, true)))
	var ir: Array = t.get("intensity", [0.0, 0.0])
	var has_i := t.has("intensity")
	var ic := CheckBox.new()
	ic.text = "Intensity"
	ic.name = "intensity_on"
	ic.tooltip_text = "Fade this track in with the music's intensity"
	ic.button_pressed = has_i
	ic.toggled.connect(func(on: bool) -> void: set_track(ti, "intensity", [0.3, 0.7] if on else null))
	box.add_child(ic)
	if has_i:
		box.add_child(_slider("from", 0.0, 1.0, float(ir[0]), func(v: float) -> void:
			set_track(ti, "intensity", [v, maxf(v, float(arrangement.tracks[ti].get("intensity", [0.0, 1.0])[1]))], true)))
		box.add_child(_slider("to", 0.0, 1.0, float(ir[1]), func(v: float) -> void:
			set_track(ti, "intensity", [minf(v, float(arrangement.tracks[ti].get("intensity", [0.0, 1.0])[0])), v], true)))


func _master_strip() -> void:
	var box := _strip("Master")
	box.name = "strip_master"
	var row := HBoxContainer.new()
	box.add_child(row)
	var m := Meter.new()
	row.add_child(m)
	_meters["master"] = m
	var col := VBoxContainer.new()
	row.add_child(col)
	var fxb := Button.new()
	fxb.text = "FX (%d)" % arrangement.master_fx.size()
	fxb.name = "fx"
	fxb.pressed.connect(func() -> void: show_fx(-1))
	col.add_child(fxb)
	box.add_child(_slider("Intensity", 0.0, 1.0, arrangement.intensity, func(v: float) -> void:
		set_intensity(v, true)
		live_intensity.emit(v)))
	var rv := arrangement.reverb
	box.add_child(_slider("Room", 0.0, 1.0, float(rv.get("room", 0.5)), func(v: float) -> void: set_reverb("room", v, true)))
	box.add_child(_slider("Damp", 0.0, 1.0, float(rv.get("damp", 0.5)), func(v: float) -> void: set_reverb("damp", v, true)))
	box.add_child(_slider("Width", 0.0, 1.0, float(rv.get("width", 1.0)), func(v: float) -> void: set_reverb("width", v, true)))
	box.add_child(_slider("Return", -24.0, 6.0, float(rv.get("return_db", 0.0)), func(v: float) -> void: set_reverb("return_db", v, true)))


func _slider(text: String, lo: float, hi: float, v: float, f: Callable) -> AKParamSlider:
	var s := AKParamSlider.make(text, lo, hi, v)
	s.name = text.to_lower()
	s.changed.connect(func(x: float) -> void: f.call(x))
	return s


func _toggle(text: String, on: bool, tip: String, f: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = on
	b.tooltip_text = tip
	b.name = text
	b.toggled.connect(func(x: bool) -> void: f.call(x))
	return b
