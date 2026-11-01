# SPDX-License-Identifier: Apache-2.0
## Panels for every part of an AKPatch, so an instrument can be built without
## editing the .tres: oscillators (shape, tuning, FM, sync, ring, tables),
## voice settings, the filter, three envelopes (with a picture of each), two
## LFOs, the modulation matrix and the effect chain.
##
## Every edit is an undoable action (in the editor, part of the editor's
## history, so Ctrl+Z works), and writes the patch at once, so a playing
## AKSynthStream hears it. Edits by path work from code too:
##
##   ed.set_param("filter.cutoff_hz", 800.0)
##   ed.set_param("oscillators.1.shape", "square")
##   ed.add_mod("env2", "cutoff", 3.0)
##   ed.add_effect("chorus")
@tool
class_name AKPatchEditor
extends ScrollContainer

## After any edit made here (the patch has already changed).
signal edited(path: String)

## Missing keys read as these (the same defaults AKPatch.compile uses).
const OSC_DEFAULTS := {shape = "sine", level = 1.0, semitones = 0.0, cents = 0.0, width = 0.5, position = 0.0, pan = 0.0, filtered = true,
	table = "basic", fm_from = 0, fm_index = 0.0, sync_to = 0, ring_from = 0}
const FILTER_DEFAULTS := {type = "lowpass", cutoff_hz = 18000.0, q = 0.707, slope_db = 12.0, resonance = 0.3, drive = 1.0}
const ENV_DEFAULTS := {attack_s = 0.0, decay_s = 0.2, sustain = 0.0, release_s = 0.15, curve = "linear"}
const LFO_DEFAULTS := {shape = "sine", rate_hz = 1.0, delay_s = 0.0, width = 0.5}

## Slider ranges: key -> [min, max, options]. Shared by oscillators,
## envelopes, LFOs, the filter, voice settings and effects.
const RANGES := {
	level = [0.0, 1.5, {}], semitones = [-48.0, 48.0, {integer = true, unit = " st"}], cents = [-100.0, 100.0, {unit = " c"}],
	width = [0.01, 0.99, {}], position = [0.0, 1.0, {}], fm_index = [0.0, 20.0, {tip = "FM depth in radians"}],
	attack_s = [0.001, 10.0, {log = true, unit = " s"}], decay_s = [0.001, 10.0, {log = true, unit = " s"}],
	sustain = [0.0, 1.0, {}], release_s = [0.001, 10.0, {log = true, unit = " s"}],
	rate_hz = [0.01, 50.0, {log = true, unit = " Hz"}], delay_s = [0.0, 5.0, {unit = " s"}],
	cutoff_hz = [20.0, 20000.0, {log = true, unit = " Hz"}], q = [0.1, 20.0, {log = true}],
	resonance = [0.0, 1.2, {tip = "Near 1 the ladder rings at the cutoff; above, it oscillates"}],
	drive = [0.1, 10.0, {log = true}],
	unison = [1.0, 7.0, {integer = true}], detune_cents = [0.0, 100.0, {unit = " c"}], spread = [0.0, 1.0, {}],
	unison_level = [0.0, 1.0, {tip = "The stacked voices' level against the middle one"}],
	velocity_curve = [0.25, 4.0, {log = true, tip = "1 linear, 2 squared (velocity 64 is 12 dB down)"}],
	polyphony = [1.0, 32.0, {integer = true}], glide_s = [0.0, 2.0, {unit = " s"}], bend_range = [0.0, 24.0, {integer = true, unit = " st"}],
	velocity_sens = [0.0, 1.0, {}], gain_db = [-36.0, 12.0, {unit = " dB"}], pan = [-1.0, 1.0, {}],
	seed = [0.0, 9999.0, {integer = true}],
	# Effects
	depth_ms = [0.0, 20.0, {unit = " ms"}], delay_ms = [0.1, 50.0, {log = true, unit = " ms"}], voices = [1.0, 4.0, {integer = true}],
	mix = [0.0, 1.0, {}], feedback = [-0.95, 0.95, {}], stages = [1.0, 12.0, {integer = true}],
	center_hz = [50.0, 10000.0, {log = true, unit = " Hz"}], range_octaves = [0.0, 6.0, {}], depth = [0.0, 1.0, {}],
	low_db = [-18.0, 18.0, {unit = " dB"}], low_hz = [20.0, 1000.0, {log = true, unit = " Hz"}],
	mid_db = [-18.0, 18.0, {unit = " dB"}], mid_hz = [100.0, 10000.0, {log = true, unit = " Hz"}], mid_q = [0.1, 10.0, {log = true}],
	high_db = [-18.0, 18.0, {unit = " dB"}], high_hz = [1000.0, 18000.0, {log = true, unit = " Hz"}],
	threshold_db = [-60.0, 0.0, {unit = " dB"}], ratio = [1.0, 20.0, {log = true}],
	knee_db = [0.0, 24.0, {unit = " dB"}], makeup_db = [0.0, 24.0, {unit = " dB"}],
	drive_db = [0.0, 48.0, {unit = " dB"}], tone_hz = [500.0, 20000.0, {log = true, unit = " Hz"}],
	asymmetry = [-1.0, 1.0, {tip = "Even harmonics"}], output_db = [-24.0, 12.0, {unit = " dB"}],
}
## Effect attack and release need shorter ranges than envelopes.
const FX_RANGES := {attack_s = [0.0005, 0.5, {log = true, unit = " s"}], release_s = [0.01, 2.0, {log = true, unit = " s"}],
	spread = [0.0, 2.0, {tip = "Left/right LFO offset, in quarter cycles"}],
	semitones = [-24.0, 24.0, {unit = " st"}], window_ms = [5.0, 200.0, {log = true, unit = " ms"}],
	freq_hz = [1.0, 4000.0, {log = true, unit = " Hz"}], jitter = [0.0, 1.0, {}], bits = [1.0, 16.0, {}],
	hold = [1.0, 32.0, {integer = true}], time_ms = [10.0, 2000.0, {log = true, unit = " ms"}],
	damp_hz = [200.0, 20000.0, {log = true, unit = " Hz"}], room = [0.0, 1.0, {}], damp = [0.0, 1.0, {}], width = [0.0, 1.0, {}],
	depth = [0.0, 2.0, {}]}
## How far a matrix row can push each destination (the amount slider's range).
const MOD_RANGES := {"pitch": 24.0, "cutoff": 8.0, "q": 4.0, "amp": 1.0, "pan": 1.0, "lfo1.rate": 6.0, "lfo2.rate": 6.0,
	"osc.pitch": 24.0, "osc.level": 1.0, "osc.fm": 10.0, "osc.width": 0.5, "osc.position": 1.0}
const NICE := {fm_index = "FM depth", fm_from = "FM from", sync_to = "Sync to", ring_from = "Ring from", cutoff_hz = "Cutoff",
	q = "Q", attack_s = "Attack", decay_s = "Decay", release_s = "Release", rate_hz = "Rate", delay_s = "Delay",
	detune_cents = "Detune", glide_s = "Glide", bend_range = "Bend range", velocity_sens = "Velocity", gain_db = "Gain",
	unison_level = "Side voices", velocity_curve = "Vel. curve",
	slope_db = "Slope", depth_ms = "Depth", delay_ms = "Delay", range_octaves = "Range", center_hz = "Centre",
	low_db = "Low", low_hz = "Low freq", mid_db = "Mid", mid_hz = "Mid freq", mid_q = "Mid Q", high_db = "High",
	high_hz = "High freq", threshold_db = "Threshold", knee_db = "Knee", makeup_db = "Make-up", drive_db = "Drive",
	tone_hz = "Tone", output_db = "Output", window_ms = "Window", freq_hz = "Frequency", time_ms = "Time",
	damp_hz = "Damping"}

## The patch being edited.
var patch: AKPatch
## An UndoRedo or EditorUndoRedoManager (the Sound Lab passes the editor's);
## null makes edits immediate (not undoable). A local UndoRedo by default.
var undo: Object
## Panels flow into columns this wide.
var panel_width := 300.0

var _flow: HFlowContainer
var _quiet := false          # a slider edit in progress: don't rebuild under it
var _rebuild_queued := false
var _own_undo: UndoRedo      # the local history, until the editor's replaces it


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_flow = HFlowContainer.new()
	_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_flow)
	_own_undo = UndoRedo.new()
	undo = _own_undo


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _own_undo:
		_own_undo.free()


## Edit `p` (or nothing with null).
func edit(p: AKPatch) -> void:
	if patch and patch.changed.is_connected(_on_patch_changed):
		patch.changed.disconnect(_on_patch_changed)
	patch = p
	if patch:
		patch.changed.connect(_on_patch_changed)
	rebuild()


# ------------------------------------------------------------------ reading

## The value at `path` ("filter.cutoff_hz", "oscillators.2.shape",
## "mods.0.amount", "unison"), with the defaults filled in.
func get_param(path: String) -> Variant:
	if patch == null:
		return null
	var parts := path.split(".")
	var v: Variant = patch.get(parts[0])
	for i in range(1, parts.size()):
		if v is Array:
			var idx := parts[i].to_int()
			if idx < 0 or idx >= v.size():
				return null
			v = v[idx]
		elif v is Dictionary:
			v = v.get(parts[i], _default_for(parts, i))
		else:
			return null
	return v


func _default_for(parts: PackedStringArray, i: int) -> Variant:
	var key := parts[i]
	match parts[0]:
		"oscillators":
			return OSC_DEFAULTS.get(key)
		"filter":
			return FILTER_DEFAULTS.get(key)
		"amp_env", "env2", "env3":
			return ENV_DEFAULTS.get(key)
		"lfo1", "lfo2":
			return LFO_DEFAULTS.get(key)
		"effects":
			var e: Dictionary = patch.effects[parts[1].to_int()]
			return AKStreamFx.DEFAULTS.get(String(e.get("type", "")), {}).get(key)
	return null


# ------------------------------------------------------------------ editing

## Set the value at `path` as one undoable edit.
func set_param(path: String, value: Variant) -> void:
	if patch == null:
		return
	var parts := path.split(".")
	var prop := parts[0]
	if parts.size() == 1:
		_commit(prop, value, path)
		return
	var root: Variant = _copy(patch.get(prop))
	var node: Variant = root
	for i in range(1, parts.size() - 1):
		node = node[parts[i].to_int()] if node is Array else node[parts[i]]
	var last := parts[parts.size() - 1]
	if node is Array:
		node[last.to_int()] = value
	else:
		node[StringName(last)] = value   # keys as the .tres files write them (&"cutoff_hz")
	_commit(prop, root, path)


## Add an oscillator (up to four): a copy of the last one, an octave down by
## default when there is one, else a saw.
func add_oscillator(o := {}) -> void:
	if patch == null or patch.oscillators.size() >= AKPatch.MAX_OSC:
		return
	var a: Array[Dictionary] = _copy(patch.oscillators)
	a.append(o if not o.is_empty() else {shape = "saw", level = 0.5})
	_commit("oscillators", a, "Add oscillator")


## Remove oscillator `i` (0-based). FM, sync and ring links to it are cleared
## and links to later oscillators renumbered; matrix rows aimed at it go.
func remove_oscillator(i: int) -> void:
	if patch == null or i < 0 or i >= patch.oscillators.size() or patch.oscillators.size() <= 1:
		return
	var a: Array[Dictionary] = _copy(patch.oscillators)
	a.remove_at(i)
	var gone := i + 1
	for o in a:
		for k in ["fm_from", "sync_to", "ring_from"]:
			var n := int(o.get(k, 0))
			if n == gone:
				o.erase(k)
				if k == "fm_from":
					o.erase("fm_index")
			elif n > gone:
				o[k] = n - 1
	var m: Array[Dictionary] = []
	for row in patch.mods:
		var d := String(row.get("dest", ""))
		var r: Dictionary = row.duplicate()
		if d.begins_with("osc") and d.find(".") > 3:
			var n := d.substr(3, d.find(".") - 3).to_int()
			if n == gone:
				continue
			if n > gone:
				r.dest = "osc%d%s" % [n - 1, d.substr(d.find("."))]
		m.append(r)
	_commit_many({oscillators = a, mods = m}, "Remove oscillator")


func add_mod(source := "lfo1", dest := "pitch", amount := 0.0) -> void:
	if patch == null or patch.mods.size() >= AKPatch.MAX_MODS:
		return
	var m: Array[Dictionary] = _copy(patch.mods)
	m.append({source = source, dest = dest, amount = amount})
	_commit("mods", m, "Add modulation")


func remove_mod(i: int) -> void:
	if patch == null or i < 0 or i >= patch.mods.size():
		return
	var m: Array[Dictionary] = _copy(patch.mods)
	m.remove_at(i)
	_commit("mods", m, "Remove modulation")


## Append an effect of `type` (chorus, flanger, phaser, eq, compressor,
## saturate) with its default settings.
func add_effect(type: String) -> void:
	if patch == null or not AKStreamFx.DEFAULTS.has(type):
		return
	var e: Array[Dictionary] = _copy(patch.effects)
	var spec := {type = type}
	spec.merge(AKStreamFx.DEFAULTS[type])
	e.append(spec)
	_commit("effects", e, "Add %s" % type)


func remove_effect(i: int) -> void:
	if patch == null or i < 0 or i >= patch.effects.size():
		return
	var e: Array[Dictionary] = _copy(patch.effects)
	e.remove_at(i)
	_commit("effects", e, "Remove effect")


## Move effect `i` earlier (-1) or later (+1) in the chain.
func move_effect(i: int, by: int) -> void:
	var j := i + by
	if patch == null or i < 0 or j < 0 or i >= patch.effects.size() or j >= patch.effects.size():
		return
	var e: Array[Dictionary] = _copy(patch.effects)
	var t := e[i]
	e[i] = e[j]
	e[j] = t
	_commit("effects", e, "Move effect")


func _copy(v: Variant) -> Variant:
	return v.duplicate(true) if (v is Array or v is Dictionary) else v


func _commit(prop: String, value: Variant, label: String) -> void:
	_commit_many({prop: value}, label)


func _commit_many(props: Dictionary, label: String) -> void:
	var action := "Patch: " + label
	if undo == null:
		for k in props:
			patch.set(k, props[k])
		patch.emit_changed()
	elif undo is UndoRedo:
		undo.create_action(action, UndoRedo.MERGE_ENDS)
		for k in props:
			undo.add_do_property(patch, k, props[k])
			undo.add_undo_property(patch, k, _copy(patch.get(k)))
		undo.add_do_method(patch.emit_changed)
		undo.add_undo_method(patch.emit_changed)
		undo.commit_action()
	else:
		undo.call(&"create_action", action, UndoRedo.MERGE_ENDS, patch)
		for k in props:
			undo.call(&"add_do_property", patch, k, props[k])
			undo.call(&"add_undo_property", patch, k, _copy(patch.get(k)))
		undo.call(&"add_do_method", patch, &"emit_changed")
		undo.call(&"add_undo_method", patch, &"emit_changed")
		undo.call(&"commit_action")
	edited.emit(label)


## Undo / redo the last patch edit (the local history outside the editor).
func undo_last() -> void:
	if undo is UndoRedo:
		undo.undo()


func redo_last() -> void:
	if undo is UndoRedo:
		undo.redo()


# ------------------------------------------------------------------ building

func _on_patch_changed() -> void:
	if _quiet or _rebuild_queued:
		return
	_rebuild_queued = true
	rebuild.call_deferred()


## Rebuild every panel from the patch.
func rebuild() -> void:
	_rebuild_queued = false
	for c in _flow.get_children():
		_flow.remove_child(c)
		c.queue_free()
	if patch == null:
		var l := Label.new()
		l.text = "Pick a patch, or New for a blank one."
		_flow.add_child(l)
		return
	for i in patch.oscillators.size():
		_osc_panel(i)
	if patch.oscillators.size() < AKPatch.MAX_OSC:
		var b := Button.new()
		b.text = "+ Oscillator"
		b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		b.pressed.connect(func() -> void: add_oscillator())
		_flow.add_child(b)
	_voice_panel()
	_filter_panel()
	_env_panel("amp_env", "Amp envelope (env1)")
	_env_panel("env2", "Envelope 2")
	_env_panel("env3", "Envelope 3")
	_lfo_panel("lfo1", "LFO 1")
	_lfo_panel("lfo2", "LFO 2")
	_matrix_panel()
	_effects_panel()


func _panel(title: String, wide := false) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.custom_minimum_size.x = panel_width * (2.0 if wide else 1.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.14, 0.17, 0.9)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(6)
	pc.add_theme_stylebox_override(&"panel", sb)
	_flow.add_child(pc)
	var box := VBoxContainer.new()
	pc.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var l := Label.new()
	l.text = title
	l.modulate = Color(1.0, 0.81, 0.23)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(l)
	box.set_meta(&"head", head)
	return box


## A slider bound to `path`; `key` picks the range.
func _slider(box: Control, path: String, key: String, ranges := RANGES) -> AKParamSlider:
	var r: Array = ranges.get(key, RANGES.get(key, [0.0, 1.0, {}]))
	var v: Variant = get_param(path)
	var s := AKParamSlider.make(String(NICE.get(key, key.capitalize())), r[0], r[1], float(v if v != null else r[0]), r[2])
	s.name = path.replace(".", "_")
	s.set_meta(&"path", path)
	s.changed.connect(func(x: float) -> void:
		_quiet = true
		set_param(path, int(x) if s.integer else x)
		_quiet = false)
	box.add_child(s)
	return s


## A menu bound to `path`, choosing among `items` (the stored values) shown as `labels`.
func _menu(box: Control, path: String, text: String, items: Array, labels := []) -> OptionButton:
	var row := HBoxContainer.new()
	box.add_child(row)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = 92
	row.add_child(l)
	var ob := OptionButton.new()
	ob.name = path.replace(".", "_")
	ob.set_meta(&"path", path)
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cur: Variant = get_param(path)
	for i in items.size():
		ob.add_item(String(labels[i]) if i < labels.size() else str(items[i]))
		if _same(items[i], cur):
			ob.select(i)
	ob.item_selected.connect(func(i: int) -> void: set_param(path, items[i]))
	row.add_child(ob)
	return ob


func _same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a), float(b))
	return str(a) == str(b)


func _head_button(box: VBoxContainer, text: String, tip: String, f: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.flat = true
	b.pressed.connect(f)
	(box.get_meta(&"head") as HBoxContainer).add_child(b)
	return b


func _osc_panel(i: int) -> void:
	var p := "oscillators.%d." % i
	var box := _panel("Oscillator %d" % (i + 1))
	if patch.oscillators.size() > 1:
		_head_button(box, "x", "Remove this oscillator", func() -> void: remove_oscillator(i))
	var shape := String(get_param(p + "shape"))
	_menu(box, p + "shape", "Shape", AKPatch.SHAPES)
	if shape == "table":
		var tables: Array = AKWavetables.BUILTIN.duplicate()
		var cur: Variant = get_param(p + "table")
		if not (cur is String) or not tables.has(cur):
			tables.append(cur)
		var labels := tables.map(func(t: Variant) -> String: return t if t is String else "(custom)")
		_menu(box, p + "table", "Table", tables, labels)
	_slider(box, p + "level", "level")
	_slider(box, p + "semitones", "semitones")
	_slider(box, p + "cents", "cents")
	_slider(box, p + "pan", "pan")
	_menu(box, p + "filtered", "Filter", [true, false], ["through it", "around it"])
	if shape == "pulse":
		_slider(box, p + "width", "width")
	if shape == "morph" or shape == "table":
		_slider(box, p + "position", "position")
	var others := [0]
	var names := ["none"]
	for j in patch.oscillators.size():
		if j != i:
			others.append(j + 1)
			names.append("osc %d" % (j + 1))
	if patch.oscillators.size() > 1 or int(get_param(p + "fm_from")) != 0:
		var fm_items := others.duplicate()
		var fm_names := names.duplicate()
		fm_items.append(i + 1)
		fm_names.append("itself (feedback)")
		_menu(box, p + "fm_from", "FM from", fm_items, fm_names)
		if int(get_param(p + "fm_from")) != 0:
			_slider(box, p + "fm_index", "fm_index")
		_menu(box, p + "sync_to", "Sync to", others, names)
		_menu(box, p + "ring_from", "Ring from", others, names)


func _voice_panel() -> void:
	var box := _panel("Voice")
	_menu(box, "mode", "Mode", AKPatch.MODES)
	_slider(box, "polyphony", "polyphony")
	_slider(box, "unison", "unison")
	_slider(box, "detune_cents", "detune_cents")
	_slider(box, "unison_level", "unison_level")
	_slider(box, "spread", "spread")
	_slider(box, "glide_s", "glide_s")
	_slider(box, "bend_range", "bend_range")
	_slider(box, "velocity_sens", "velocity_sens")
	_slider(box, "velocity_curve", "velocity_curve")
	_slider(box, "gain_db", "gain_db")
	_slider(box, "pan", "pan")
	var row := HBoxContainer.new()
	box.add_child(row)
	var s := _slider(row, "seed", "seed")
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b := Button.new()
	b.text = "New"
	b.tooltip_text = "A new seed: new noise, unison phases and random values"
	b.pressed.connect(func() -> void: set_param("seed", randi() % 10000))
	row.add_child(b)


func _filter_panel() -> void:
	var box := _panel("Filter")
	var t := String(get_param("filter.type"))
	_menu(box, "filter.type", "Type", AKPatch.FILTERS)
	if t == "off":
		return
	_slider(box, "filter.cutoff_hz", "cutoff_hz")
	if t == "ladder":
		_slider(box, "filter.resonance", "resonance")
		_slider(box, "filter.drive", "drive")
	else:
		_slider(box, "filter.q", "q")
		_menu(box, "filter.slope_db", "Slope", [12.0, 24.0], ["12 dB/oct", "24 dB/oct"])


func _env_panel(prop: String, title: String) -> void:
	var box := _panel(title)
	var view := AKEnvView.new()
	view.env = get_param(prop)
	box.add_child(view)
	for k in ["attack_s", "decay_s", "sustain", "release_s"]:
		var s := _slider(box, prop + "." + k, k)
		s.changed.connect(func(_x: float) -> void:
			view.env = get_param(prop)
			view.queue_redraw())
	_menu(box, prop + ".curve", "Decay curve", ["linear", "exp"], ["linear", "exponential"])


func _lfo_panel(prop: String, title: String) -> void:
	var box := _panel(title)
	_menu(box, prop + ".shape", "Shape", AKPatch.LFO_SHAPES)
	_slider(box, prop + ".rate_hz", "rate_hz")
	_slider(box, prop + ".delay_s", "delay_s")
	if String(get_param(prop + ".shape")) == "square":
		_slider(box, prop + ".width", "width")


## Destinations as the matrix menu offers them: the global ones, then each
## oscillator's own (osc1.pitch ...), then all oscillators (osc.pitch ...).
func mod_destinations() -> Array:
	var out := ["pitch", "cutoff", "q", "amp", "pan", "lfo1.rate", "lfo2.rate"]
	for i in patch.oscillators.size():
		for k in ["pitch", "level", "fm", "width", "position"]:
			out.append("osc%d.%s" % [i + 1, k])
	for k in ["pitch", "level", "fm", "width", "position"]:
		out.append("osc." + k)
	return out


func _matrix_panel() -> void:
	var box := _panel("Modulation matrix", true)
	if patch.mods.size() < AKPatch.MAX_MODS:
		_head_button(box, "+ Row", "Add a modulation row", func() -> void: add_mod())
	if patch.mods.is_empty():
		var l := Label.new()
		l.text = "Each row adds amount × source to a destination."
		l.modulate = Color(1, 1, 1, 0.6)
		box.add_child(l)
	var dests := mod_destinations()
	for i in patch.mods.size():
		var p := "mods.%d." % i
		var row := HBoxContainer.new()
		box.add_child(row)
		var src := OptionButton.new()
		src.name = "mods_%d_source" % i
		src.set_meta(&"path", p + "source")
		for s in AKPatch.SOURCES:
			src.add_item(s)
		src.select(AKPatch.SOURCES.find(String(get_param(p + "source"))))
		src.item_selected.connect(func(k: int) -> void: set_param(p + "source", AKPatch.SOURCES[k]))
		row.add_child(src)
		var arrow := Label.new()
		arrow.text = "→"
		row.add_child(arrow)
		var dst := OptionButton.new()
		dst.name = "mods_%d_dest" % i
		dst.set_meta(&"path", p + "dest")
		var cur := String(get_param(p + "dest"))
		var list := dests.duplicate()
		if not list.has(cur):
			list.append(cur)
		for d in list:
			dst.add_item(d)
		dst.select(list.find(cur))
		dst.item_selected.connect(func(k: int) -> void: set_param(p + "dest", list[k]))
		row.add_child(dst)
		var generic := cur
		if cur.begins_with("osc") and cur.find(".") > 0:
			generic = "osc" + cur.substr(cur.find("."))
		var rng := float(MOD_RANGES.get(generic, 1.0))
		var amt := _slider(row, p + "amount", "amount", {amount = [-rng, rng, {width = 54}]})
		amt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var x := Button.new()
		x.text = "x"
		x.flat = true
		x.tooltip_text = "Remove this row"
		x.pressed.connect(func() -> void: remove_mod(i))
		row.add_child(x)


func _effects_panel() -> void:
	for i in patch.effects.size():
		var e: Dictionary = patch.effects[i]
		var t := String(e.get("type", ""))
		var box := _panel("Effect %d: %s" % [i + 1, t])
		if i > 0:
			_head_button(box, "↑", "Earlier in the chain", func() -> void: move_effect(i, -1))
		if i < patch.effects.size() - 1:
			_head_button(box, "↓", "Later in the chain", func() -> void: move_effect(i, 1))
		_head_button(box, "x", "Remove this effect", func() -> void: remove_effect(i))
		for k in AKStreamFx.DEFAULTS.get(t, {}):
			if t == "flanger" and k == "voices":
				continue
			var ranges := FX_RANGES.duplicate()
			ranges.merge(RANGES)
			_slider(box, "effects.%d.%s" % [i, k], k, ranges)
	var add := _panel("Add effect")
	var row := HFlowContainer.new()
	add.add_child(row)
	for t in AKStreamFx.DEFAULTS:
		var b := Button.new()
		b.text = t
		b.name = "add_" + t
		var tt: String = t
		b.pressed.connect(func() -> void: add_effect(tt))
		row.add_child(b)


## Every control bound to a patch path, by path (for tests and tools).
func controls() -> Dictionary:
	var out := {}
	_collect(_flow, out)
	return out


func _collect(n: Node, out: Dictionary) -> void:
	for c in n.get_children():
		if c.has_meta(&"path"):
			out[String(c.get_meta(&"path"))] = c
		_collect(c, out)
