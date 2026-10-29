# SPDX-License-Identifier: Apache-2.0
## An effect chain editor: a panel per effect with its settings as sliders
## (the patch editor's ranges), ↑ ↓ to reorder, x to remove, and a button per
## effect type to add one. The Sequencer's mixer uses it for track inserts
## (chorus, flanger, phaser, eq, compressor, saturate) and for the master
## (those, plus gain, filters, dcblock, loudness and limit).
##
## It edits a copy and reports each change as `edited(chain, label, merge)`;
## the owner commits it (undoably) and calls `set_chain` when the chain
## changed elsewhere. `merge` is true for a slider drag's steps.
@tool
class_name AKFxChainEditor
extends VBoxContainer

signal edited(chain: Array, label: String, merge: bool)

## Settings of the master-only steps (the live master runs all of them).
const MASTER_DEFAULTS := {
	"gain": {db = 0.0}, "lowpass": {cutoff_hz = 18000.0, q = 0.707}, "highpass": {cutoff_hz = 30.0, q = 0.707},
	"dcblock": {cutoff_hz = 10.0}, "loudness": {target_lufs = -16.0}, "limit": {ceiling_db = -1.5, release_s = 0.08},
}
const MASTER_RANGES := {db = [-24.0, 12.0, {unit = " dB"}], target_lufs = [-30.0, -6.0, {unit = " LUFS"}],
	ceiling_db = [-12.0, 0.0, {unit = " dB"}]}

var chain: Array = []
## Offer the master-only steps too.
var master := false
var title := "Effects"

var _box: VBoxContainer
var _quiet := false


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box = VBoxContainer.new()
	add_child(_box)


func set_chain(c: Array, p_title := "") -> void:
	chain = c.duplicate(true)
	if p_title != "":
		title = p_title
	if not _quiet:
		_rebuild()


func types() -> Array:
	var t := AKStreamFx.DEFAULTS.keys()
	if master:
		t = MASTER_DEFAULTS.keys() + t
	return t


func defaults_of(type: String) -> Dictionary:
	return AKStreamFx.DEFAULTS.get(type, MASTER_DEFAULTS.get(type, {}))


func add(type: String) -> void:
	chain.append({type = type})
	_emit("Add %s" % type, false, true)


func remove(i: int) -> void:
	chain.remove_at(i)
	_emit("Remove effect", false, true)


func move(i: int, by: int) -> void:
	var j := i + by
	if j < 0 or j >= chain.size():
		return
	var x: Variant = chain[i]
	chain[i] = chain[j]
	chain[j] = x
	_emit("Move effect", false, true)


## Set one setting (as a slider drag does).
func set_value(i: int, key: String, v: float) -> void:
	chain[i][key] = v
	_quiet = true
	_emit("%s %s" % [chain[i].get("type", ""), key], true, false)
	_quiet = false


func _emit(label: String, merge: bool, rebuild: bool) -> void:
	var c := chain.duplicate(true)
	if rebuild:
		_rebuild()
	edited.emit(c, label, merge)


## Every slider by "index.key" (for tools and tests).
func sliders() -> Dictionary:
	var out := {}
	for c in find_children("*", "AKParamSlider", true, false):
		if c.has_meta(&"fx_key"):
			out[String(c.get_meta(&"fx_key"))] = c
	return out


func _rebuild() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	var head := Label.new()
	head.text = title
	head.modulate = Color(1.0, 0.81, 0.23)
	_box.add_child(head)
	var flow := HFlowContainer.new()
	_box.add_child(flow)
	for i in chain.size():
		var e: Dictionary = chain[i]
		var t := String(e.get("type", ""))
		var panel := VBoxContainer.new()
		panel.custom_minimum_size = Vector2(230, 0)
		flow.add_child(panel)
		var row := HBoxContainer.new()
		panel.add_child(row)
		var l := Label.new()
		l.text = "%d: %s" % [i + 1, t]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		_small(row, "↑", func() -> void: move(i, -1))
		_small(row, "↓", func() -> void: move(i, 1))
		_small(row, "x", func() -> void: remove(i))
		var d := defaults_of(t)
		for k in d:
			if t == "flanger" and k == "voices":
				continue
			var ranges := AKPatchEditor.FX_RANGES.duplicate()
			ranges.merge(MASTER_RANGES)
			ranges.merge(AKPatchEditor.RANGES)
			var r: Array = ranges.get(k, [0.0, 1.0, {}])
			var s := AKParamSlider.make(String(AKPatchEditor.NICE.get(k, String(k).capitalize())), r[0], r[1], float(e.get(k, d[k])), r[2])
			s.set_meta(&"fx_key", "%d.%s" % [i, k])
			var key: String = k
			s.changed.connect(func(x: float) -> void: set_value(i, key, float(int(x)) if s.integer else x))
			panel.add_child(s)
	var add_row := HFlowContainer.new()
	_box.add_child(add_row)
	var al := Label.new()
	al.text = "Add:"
	add_row.add_child(al)
	for t in types():
		var tt: String = t
		_small(add_row, t, func() -> void: add(tt))


func _small(parent: Control, text: String, f: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(f)
	parent.add_child(b)
	return b
