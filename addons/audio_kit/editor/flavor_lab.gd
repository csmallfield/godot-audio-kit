# SPDX-License-Identifier: Apache-2.0
## The Sound Lab's Flavor page: a synth patch from a few knobs named for what
## you hear (AKFlavor; docs/plans/flavor-tab.md).
##
##   Toolbar    name the sound, Randomise, Mutate (with how far), Undo, Reset,
##              Save, open one you saved, and Open in Synth to fine-tune it
##   Two-way    eight knobs that rest in the middle and turn either way
##   Add        six knobs that rest at zero and only turn up, and the switches
##   Play       the scope, a light when the limiter acts, and the keyboard:
##              click, the computer keys, or a MIDI keyboard
##
## Every move rebuilds the same AKPatch in place, so it is heard at once. On Save
## the sound's loudness is evened out with one fixed gain (measuring takes 0.1 to
## 0.3 s, too long to run after every move); while playing, the limiter holds peaks. Right-click a knob to
## link it to a MIDI controller knob: "Learn", then turn the hardware knob.
## Links are kept in the editor's settings, not in the patch.
@tool
class_name AKFlavorLab
extends VBoxContainer

## "Open in Synth": a copy of the sound, for the Synth page's panels.
signal open_patch(patch: AKPatch)

## Where Save writes by default (<dir>patches/<name>.tres); see set_save_dir.
const SAVE_DIR := "res://audio/"
## Seconds after the last move before the controls count as settled.
const SETTLE_S := 0.35
const HISTORY_MAX := 64
## Editor setting that keeps the MIDI links ({knob id: controller number}).
const MIDI_SETTING := "audio_kit/flavor/midi_links"
## A two-way knob reads as "at rest" this close to the controller's middle (64).
const MIDI_DEAD := 2

## The sound: one AKPatch, rebuilt in place as the controls move.
var patch: AKPatch
## The controls' positions ({knob id: float, switch id: bool}).
var settings: Dictionary
var router: AKMidiRouter
var keyboard: AKKeyboard
var wave: AKScope
## Knob id -> AKKnob, switch id -> CheckBox.
var knobs := {}
var switches := {}
var save_dir := SAVE_DIR
var last_saved := ""
## Knob id -> MIDI controller number.
var midi_links := {}
## The knob waiting for a controller ("" when none).
var learning := ""
## Even out loudness on Save. Off: never.
var auto_level := true
## Settled sounds, oldest first; the last is the current one.
var history: Array = []
## The gain the last levelling set, in dB.
var level_gain_db := 0.0

var _status: Label
var _name: LineEdit
var _saved: OptionButton
var _saved_paths: Array = []
var _amount: HSlider
var _notice: Label
var _mono_note: Label
var _limit_light: ColorRect
var _devices: Label
var _menu: PopupMenu
var _menu_knob := ""
var _settle_due := -1.0
var _scope_t := 0.0
var _limit_t := 0.0
var _seed := 0
var _pickup := {}   # knob id -> {armed: bool, last: float}
var _quiet := false


func _init() -> void:
	name = "Flavor"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	router = AKMidiRouter.new()
	router.open_inputs = false   # see set_midi_input
	router.listen = false
	add_child(router)
	router.note_started.connect(func(_c: int, n: int, _v: float) -> void:
		if keyboard:
			keyboard.mark(n, true))
	router.note_stopped.connect(func(_c: int, n: int) -> void:
		if keyboard:
			keyboard.mark(n, false))
	router.controller_changed.connect(func(_c: int, number: int, value: int) -> void: handle_controller(number, value))
	settings = AKFlavor.defaults()
	patch = AKFlavor.build(settings)
	patch.resource_name = "flavor"
	router.patch = patch
	_seed = int(Time.get_ticks_usec() & 0x7fffffff)
	_load_links()
	_build()
	history = [settings.duplicate()]
	_refresh_saved()
	_refresh_state()


func _process(delta: float) -> void:
	if _settle_due >= 0.0 and Time.get_ticks_msec() / 1000.0 >= _settle_due:
		settle()
	if not is_visible_in_tree():
		return
	_limit_t = maxf(0.0, _limit_t - delta)
	_scope_t += delta
	if _scope_t >= 0.05:
		_scope_t = 0.0
		_update_scope()
	if _limit_light:
		_limit_light.color = Color(1.0, 0.45, 0.2) if _limit_t > 0.0 else Color(1, 1, 1, 0.12)


# ------------------------------------------------------------------ controls

## Turn a knob (as a drag would). The sound changes at once; it counts as
## settled a moment after the last move (or call settle()).
func set_knob(id: String, value: float) -> void:
	if not knobs.has(id):
		return
	var k: AKKnob = knobs[id]
	_quiet = true
	k.value = value
	_quiet = false
	settings[id] = k.value
	_pickup.erase(id)
	_changed()


func set_switch(id: String, on: bool) -> void:
	if not switches.has(id):
		return
	_quiet = true
	(switches[id] as CheckBox).button_pressed = on
	_quiet = false
	settings[id] = on
	_changed()


## Put every control where `d` says and rebuild the sound.
func set_settings(d: Dictionary) -> void:
	settings = AKFlavor.clean(d)
	_quiet = true
	for id: String in knobs:
		(knobs[id] as AKKnob).value = settings[id]
	for id: String in switches:
		(switches[id] as CheckBox).button_pressed = settings[id]
	_quiet = false
	_pickup.clear()
	_changed()


## The controls have stopped moving: remember the sound for Undo. (Loudness is
## evened out on Save, not here.) Returns the level gain in dB: 0, as moving a
## control drops it.
func settle() -> float:
	_settle_due = -1.0
	if history.is_empty() or history.back() != settings:
		history.append(settings.duplicate())
		if history.size() > HISTORY_MAX:
			history.pop_front()
	return level_gain_db


## Measure the sound and set its one fixed gain (see AKFlavor.level).
func level_now() -> float:
	level_gain_db = AKFlavor.level(patch)
	patch.emit_changed()
	_say("Loudness evened out: %+.1f dB." % level_gain_db if absf(level_gain_db) > 0.05 else "Loudness is within the window; no gain needed.")
	return level_gain_db


## A new sound from scratch.
func randomise() -> void:
	_seed += 1
	set_settings(AKFlavor.randomise(_seed))
	settle()
	_say("Randomised. Undo steps back.")


## A near neighbour of the current sound; the slider sets how far.
func mutate() -> void:
	_seed += 1
	set_settings(AKFlavor.mutate(settings, _seed, _amount.value if _amount else 0.15))
	settle()
	_say("Mutated. Undo steps back.")


## Back to the sound before the last settled change.
func undo() -> bool:
	if history.size() < 2:
		_say("Nothing to undo.")
		return false
	history.pop_back()
	var prev: Dictionary = history.pop_back()
	set_settings(prev)
	settle()
	return true


## Every control to rest: the base sound.
func reset() -> void:
	set_settings(AKFlavor.defaults())
	settle()
	_say("Reset to the base sound.")


# ---------------------------------------------------------- saving, opening

## Save patches under `dir` (in patches/ inside it).
func set_save_dir(dir: String) -> void:
	save_dir = dir if dir.ends_with("/") else dir + "/"
	_refresh_saved()


## Even out the loudness and save a copy as <save_dir>patches/<name>.tres, with
## the control positions stored in it. Returns the path ("" on failure).
func save_patch() -> String:
	settle()
	if auto_level:
		level_now()
	var base := _name.text.strip_edges().validate_filename() if _name else "flavor"
	var path := save_dir + "patches/" + (base if base != "" else "flavor") + ".tres"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var copy: AKPatch = patch.duplicate(true)
	copy.resource_name = path.get_file().get_basename()
	AKPatch.stamp_library(copy, "flavor", AKPatch.editor_author())
	if ResourceSaver.save(copy, path) != OK:
		_say("Couldn't save %s" % path)
		return ""
	last_saved = path
	AK.refresh_editor_files()
	_refresh_saved()
	_say("Saved %s (loudness %+.1f dB)" % [path, level_gain_db])
	return path


## Open a patch made here (a path or an AKPatch): the controls go to where it
## was made. False when it isn't a Flavor patch. A patch edited since (in the
## Synth page, say) still opens, with a notice: its controls describe the sound
## before those edits, and turning one rebuilds it from the controls.
func open_flavor(p: Variant) -> bool:
	var pt: AKPatch = p if p is AKPatch else (ResourceLoader.load(String(p), "", ResourceLoader.CACHE_MODE_IGNORE) as AKPatch if ResourceLoader.exists(String(p)) else null)
	if pt == null:
		_say("Not a patch: %s" % p)
		return false
	var st := AKFlavor.settings_of(pt)
	if st.is_empty():
		_say("%s wasn't made on the Flavor page, so there are no knob positions to open. Open it in the Synth page." % (pt.resource_path if pt.resource_path != "" else String(pt.resource_name)))
		return false
	var stale := AKFlavor.is_stale(pt)
	if _name:
		_name.text = (pt.resource_path.get_file().get_basename() if pt.resource_path != "" else String(pt.resource_name)).validate_filename()
	set_settings(st)
	history = [settings.duplicate()]
	settle()
	if _notice:
		_notice.text = "Edited since it was made here: the knobs show the sound before those edits, and this is that sound rebuilt." if stale else ""
		_notice.visible = stale
	_say("Opened %s" % (pt.resource_path if pt.resource_path != "" else String(pt.resource_name)))
	return true


## Hand a copy of the sound to the Synth page (through `open_patch`).
func open_in_synth() -> AKPatch:
	settle()
	var copy: AKPatch = patch.duplicate(true)
	copy.resource_name = (_name.text.strip_edges() if _name and _name.text.strip_edges() != "" else "flavor")
	open_patch.emit(copy)
	return copy


# ---------------------------------------------------------------------- MIDI

func note_on(note: int, velocity: float) -> void:
	router.note_on(note, velocity)


func note_off(note: int) -> void:
	router.note_off(note)


## Listen to connected MIDI keyboards and controllers.
func set_midi_input(on: bool) -> void:
	router.listen = on
	router.set_process_input(on)
	if on:
		OS.open_midi_inputs()
	if _devices:
		var d := AKMidiRouter.devices()
		_devices.text = "MIDI in: " + (", ".join(d) if not d.is_empty() else "no devices") if on else "MIDI in: off"


## Wait for the next controller message and link it to knob `id`.
func learn(id: String) -> void:
	if learning != "" and knobs.has(learning):
		(knobs[learning] as AKKnob).learning = false
	learning = id if knobs.has(id) else ""
	if learning != "":
		(knobs[learning] as AKKnob).learning = true
		_say("Turn a knob on your MIDI controller to link it to %s." % _knob_title(id))


## Drop knob `id`'s link.
func forget(id: String) -> void:
	midi_links.erase(id)
	_pickup.erase(id)
	if knobs.has(id):
		(knobs[id] as AKKnob).linked = false
	_save_links()


## A controller message (number 0-127, value 0-127): finish a Learn, or move
## the linked knob. A hardware knob somewhere else than the one on screen does
## nothing until it reaches the on-screen position, so nothing jumps.
func handle_controller(number: int, value: int) -> void:
	if learning != "":
		for id: String in midi_links.keys():
			if int(midi_links[id]) == number:
				forget(id)
		midi_links[learning] = number
		var k: AKKnob = knobs[learning]
		k.learning = false
		k.linked = true
		_say("%s follows controller %d." % [_knob_title(learning), number])
		learning = ""
		_save_links()
		return
	for id: String in midi_links:
		if int(midi_links[id]) != number or not knobs.has(id):
			continue
		var k: AKKnob = knobs[id]
		var t := controller_value(k.two_way, value)
		var cur := float(settings[id])
		var st: Dictionary = _pickup.get(id, {armed = false, last = NAN})
		if not st.armed:
			var crossed: bool = not is_nan(st.last) and (float(st.last) - cur) * (t - cur) <= 0.0
			if absf(t - cur) <= 0.06 or crossed:
				st.armed = true
		st.last = t
		if st.armed:
			_quiet = true
			k.value = t
			_quiet = false
			settings[id] = k.value
			_changed()
		_pickup[id] = st


## Where a controller value puts a knob: 0 .. 127 across the range, with the
## middle (64) of a two-way knob as rest.
static func controller_value(two_way: bool, value: int) -> float:
	var v := clampi(value, 0, 127)
	if not two_way:
		return v / 127.0
	if absi(v - 64) <= MIDI_DEAD:
		return 0.0
	return clampf((v - 64) / 63.0, -1.0, 1.0)


# -------------------------------------------------------------------- inside

func _changed() -> void:
	AKFlavor.apply_to(patch, settings)
	level_gain_db = 0.0
	_settle_due = Time.get_ticks_msec() / 1000.0 + SETTLE_S
	if _notice:
		_notice.visible = false
	_refresh_state()


func _refresh_state() -> void:
	# Minor only matters once Note/Chord's third is in.
	if switches.has("minor"):
		var on: bool = float(settings.get("note_chord", 0.0)) > 0.6
		(switches["minor"] as CheckBox).disabled = not on
		(switches["minor"] as CheckBox).tooltip_text = _switch_hint("minor") + ("" if on else "\nTurn Note ↔ Chord past 0.6 first: that is where the third comes in.")
	if _mono_note:
		_mono_note.visible = float(settings.get("stiff_slinky", 0.0)) > 0.0


func _update_scope() -> void:
	var s: Object = router.synth() if AKSynth.available() else null
	if s == null or not s.has_method(&"get_recent"):
		return
	var buf: PackedFloat32Array = s.get_recent(2048)
	if wave:
		wave.show_samples(buf)
	var peak := 0.0
	for x in buf:
		peak = maxf(peak, absf(x))
	if peak >= db_to_linear(AKFlavor.CEILING_DB - 0.15):
		_limit_t = 0.3


func _knob_title(id: String) -> String:
	for k: Dictionary in AKFlavor.KNOBS:
		if k.id == id:
			return "%s ↔ %s" % [k.low, k.high]
	return id


func _switch_hint(id: String) -> String:
	for sw: Dictionary in AKFlavor.SWITCHES:
		if sw.id == id:
			return sw.hint
	return ""


func _refresh_saved() -> void:
	if _saved == null:
		return
	_saved.clear()
	_saved_paths.clear()
	_saved.add_item("Open a saved sound …")
	var dir := save_dir + "patches/"
	var da := DirAccess.open(dir)
	if da:
		var files: Array = Array(da.get_files())
		files.sort()
		for f: String in files:
			if f.get_extension() == "tres":
				_saved_paths.append(dir + f)
				_saved.add_item(f.get_basename())
	_saved.select(0)


func _load_links() -> void:
	if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		var es: Object = Engine.get_singleton(&"EditorInterface").call(&"get_editor_settings")
		if es and es.call(&"has_setting", MIDI_SETTING):
			var v: Variant = es.call(&"get_setting", MIDI_SETTING)
			if v is Dictionary:
				midi_links = (v as Dictionary).duplicate()


func _save_links() -> void:
	if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		var es: Object = Engine.get_singleton(&"EditorInterface").call(&"get_editor_settings")
		if es:
			es.call(&"set_setting", MIDI_SETTING, midi_links.duplicate())


func _build() -> void:
	add_theme_constant_override(&"separation", roundi(6 * AKUiScale.factor()))
	# Toolbar.
	var bar := HBoxContainer.new()
	add_child(bar)
	_name = LineEdit.new()
	_name.text = "flavor"
	_name.custom_minimum_size = AKUiScale.px(150, 0)
	_name.tooltip_text = "The sound's name: Save writes res://audio/patches/<name>.tres"
	bar.add_child(_name)
	_button(bar, "Randomise", randomise).tooltip_text = "A new sound from scratch: most knobs near rest, a few pushed far"
	_button(bar, "Mutate", mutate).tooltip_text = "A near neighbour of this sound"
	_amount = HSlider.new()
	_amount.min_value = 0.02
	_amount.max_value = 0.6
	_amount.step = 0.01
	_amount.value = 0.15
	_amount.custom_minimum_size = AKUiScale.px(80, 0)
	_amount.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_amount.tooltip_text = "How far Mutate moves the knobs"
	bar.add_child(_amount)
	_button(bar, "Undo", func() -> void: undo()).tooltip_text = "Back to the sound before the last change"
	_button(bar, "Reset", reset).tooltip_text = "Every control to rest: the base sound"
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(gap)
	_saved = OptionButton.new()
	_saved.tooltip_text = "Sounds saved from this page"
	_saved.item_selected.connect(func(i: int) -> void:
		if i >= 1 and i <= _saved_paths.size():
			open_flavor(_saved_paths[i - 1])
		_saved.select(0))
	bar.add_child(_saved)
	_button(bar, "Save", func() -> void: save_patch()).tooltip_text = "Even out the loudness and save the sound, with its knob positions"
	_button(bar, "Open in Synth", func() -> void: open_in_synth()).tooltip_text = "Fine-tune a copy in the Synth page's panels (one way: the knobs here can't follow those edits)"
	_notice = Label.new()
	_notice.modulate = Color(1.0, 0.7, 0.3)
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.visible = false
	add_child(_notice)

	# Two-way knobs.
	_heading(self, "Two-way knobs: rest in the middle, turn either way")
	var row1 := HFlowContainer.new()
	add_child(row1)
	# Add-only knobs with the switches beside them.
	_heading(self, "Add knobs: rest at zero, only turn up")
	var lower := HBoxContainer.new()
	add_child(lower)
	var row2 := HBoxContainer.new()
	lower.add_child(row2)
	for k: Dictionary in AKFlavor.KNOBS:
		var kn := AKKnob.new()
		kn.two_way = k.two_way
		kn.low_text = k.low
		kn.high_text = k.high
		kn.tooltip_text = "%s ↔ %s\n%s\nDrag up or right (Shift: fine). Double-click: back to rest. Right-click: link a MIDI knob." % [k.low, k.high, k.hint]
		var id: String = k.id
		kn.linked = midi_links.has(id)
		kn.changed.connect(func(v: float) -> void:
			if _quiet:
				return
			settings[id] = v
			_pickup.erase(id)
			_changed())
		kn.released.connect(func() -> void: _settle_due = 0.0)
		kn.menu_requested.connect(func() -> void: _open_menu(id))
		(row1 if k.two_way else row2).add_child(kn)
		knobs[id] = kn
	var sw_gap := Control.new()
	sw_gap.custom_minimum_size = AKUiScale.px(28, 0)
	lower.add_child(sw_gap)
	var sw_box := VBoxContainer.new()
	sw_box.custom_minimum_size = AKUiScale.px(170, 0)
	lower.add_child(sw_box)
	for sw: Dictionary in AKFlavor.SWITCHES:
		var cb := CheckBox.new()
		cb.text = sw.name
		cb.tooltip_text = sw.hint
		var id: String = sw.id
		cb.toggled.connect(func(on: bool) -> void:
			if _quiet:
				return
			settings[id] = on
			_changed()
			_settle_due = 0.0)
		sw_box.add_child(cb)
		switches[id] = cb

	# The knobs' right-click menu.
	_menu = PopupMenu.new()
	_menu.add_item("Learn MIDI controller", 0)
	_menu.add_item("Forget MIDI controller", 1)
	_menu.add_item("Back to rest", 2)
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(spacer)

	# Play: scope, the limiter's light, the keyboard.
	_status = Label.new()
	_status.modulate = Color(1, 1, 1, 0.6)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "Turn a knob and play the keyboard." if AKSynth.available() else "Live play needs the native core (native/README.md). Save still works."
	add_child(_status)
	var krow := HBoxContainer.new()
	add_child(krow)
	_button(krow, "Oct -", func() -> void: keyboard.low_note -= 12)
	_button(krow, "Oct +", func() -> void: keyboard.low_note += 12)
	var vl := Label.new()
	vl.text = "Velocity"
	krow.add_child(vl)
	var vel := HSlider.new()
	vel.min_value = 0.05
	vel.max_value = 1.0
	vel.step = 0.01
	vel.value = 0.8
	vel.custom_minimum_size = AKUiScale.px(100, 0)
	vel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vel.value_changed.connect(func(v: float) -> void: keyboard.velocity = v)
	krow.add_child(vel)
	_button(krow, "All off", func() -> void:
		router.all_notes_off()
		keyboard.release_all())
	var midi := CheckBox.new()
	midi.text = "MIDI input"
	midi.tooltip_text = "Play from a MIDI keyboard, and move linked knobs from its controllers"
	midi.toggled.connect(set_midi_input)
	krow.add_child(midi)
	_devices = Label.new()
	_devices.modulate = Color(1, 1, 1, 0.6)
	_devices.text = "MIDI in: off"
	krow.add_child(_devices)
	_mono_note = Label.new()
	_mono_note.text = "Slinky: one note at a time"
	_mono_note.modulate = Color(1.0, 0.7, 0.3)
	_mono_note.visible = false
	krow.add_child(_mono_note)
	var gap2 := Control.new()
	gap2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	krow.add_child(gap2)
	var ll := Label.new()
	ll.text = "Limiter"
	ll.modulate = Color(1, 1, 1, 0.6)
	ll.tooltip_text = "Lights when the sound reaches the limiter's ceiling (%.0f dBFS)" % AKFlavor.CEILING_DB
	krow.add_child(ll)
	_limit_light = ColorRect.new()
	_limit_light.custom_minimum_size = AKUiScale.px(14, 14)
	_limit_light.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_limit_light.color = Color(1, 1, 1, 0.12)
	krow.add_child(_limit_light)
	var play := HBoxContainer.new()
	add_child(play)
	wave = AKScope.new()
	wave.mode = AKScope.Mode.WAVE
	wave.custom_minimum_size = AKUiScale.px(220, 100)
	wave.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	play.add_child(wave)
	keyboard = AKKeyboard.new()
	keyboard.custom_minimum_size = AKUiScale.px(0, 100)
	keyboard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	keyboard.note_on.connect(note_on)
	keyboard.note_off.connect(note_off)
	play.add_child(keyboard)


func _on_menu(i: int) -> void:
	if i == 0:
		learn(_menu_knob)
	elif i == 1:
		forget(_menu_knob)
	elif i == 2:
		set_knob(_menu_knob, 0.0)
		settle()


func _open_menu(id: String) -> void:
	_menu_knob = id
	_menu.set_item_disabled(1, not midi_links.has(id))
	if is_inside_tree():
		_menu.position = Vector2i(get_screen_position() + get_local_mouse_position())
		_menu.popup()


func _say(text: String) -> void:
	if _status:
		_status.text = text


func _heading(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.modulate = Color(1.0, 0.81, 0.23)
	parent.add_child(l)


func _button(parent: Control, text: String, f: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(f)
	parent.add_child(b)
	return b
