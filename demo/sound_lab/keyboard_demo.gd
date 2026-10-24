# SPDX-License-Identifier: Apache-2.0
## Play the kit's patches in a running game: an on-screen keyboard (or the
## computer keys, or a MIDI keyboard), a patch per button, mod wheel and
## pitch bend sliders, a scope, and the patch's sound through a Godot bus
## carrying the kit's chorus bus effect. Needs the native core.
extends Control

const PATCHES := ["saw_lead", "pluck", "fm_epiano", "vowel_pad", "acid_bass", "ring_bell", "organ", "strings"]

var router: AKMidiRouter
var keyboard: AKKeyboard
var scope: AKScope


func _ready() -> void:
	var bus := _fx_bus()
	router = AKMidiRouter.new()
	router.bus = bus
	# Open the OS's MIDI inputs, except in headless runs (tests, servers).
	router.open_inputs = DisplayServer.get_name() != "headless"
	router.patch = AKPatchLib.load_preset(&"saw_lead")
	add_child(router)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 16
	box.offset_right = -16
	box.offset_top = 12
	box.offset_bottom = -12
	add_child(box)
	var title := Label.new()
	title.text = "Audio Kit: play a patch" + ("" if AKSynth.available() else "  (needs the native core: see native/README.md)")
	box.add_child(title)
	var row := HFlowContainer.new()
	box.add_child(row)
	for n in PATCHES:
		var b := Button.new()
		b.text = n
		var name_: String = n
		b.pressed.connect(func() -> void: router.patch = AKPatchLib.load_preset(StringName(name_)))
		row.add_child(b)
	box.add_child(_slider("Mod wheel", 0.0, func(v: float) -> void: router.controller(1, roundi(v * 127.0))))
	var bend := _slider("Pitch bend", 0.5, func(v: float) -> void:
		var s: Object = router.synth()
		if s:
			s.set_bend(v * 2.0 - 1.0))
	box.add_child(bend)
	scope = AKScope.new()
	scope.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scope)
	keyboard = AKKeyboard.new()
	keyboard.custom_minimum_size = Vector2(0, 120)
	keyboard.note_on.connect(func(n: int, v: float) -> void: router.note_on(n, v))
	keyboard.note_off.connect(func(n: int) -> void: router.note_off(n))
	router.note_started.connect(func(_c: int, n: int, _v: float) -> void: keyboard.mark(n, true))
	router.note_stopped.connect(func(_c: int, n: int) -> void: keyboard.mark(n, false))
	box.add_child(keyboard)
	keyboard.grab_focus()


func _process(_delta: float) -> void:
	var s: Object = router.synth() if AKSynth.available() else null
	if s and s.has_method(&"get_recent"):
		scope.show_samples(s.get_recent(2048))


## A bus with the kit's chorus on it (a Godot bus effect), feeding Master.
func _fx_bus() -> StringName:
	var name_ := &"Synth FX"
	if AudioServer.get_bus_index(name_) >= 0:
		return name_
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, name_)
	AudioServer.set_bus_send(i, &"Master")
	if ClassDB.class_exists(&"AKChorus"):
		var fx: AudioEffect = ClassDB.instantiate(&"AKChorus")
		fx.set(&"mix", 0.3)
		AudioServer.add_bus_effect(i, fx)
	return name_


func _slider(text: String, value: float, f: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = 100
	row.add_child(l)
	var s := HSlider.new()
	s.max_value = 1.0
	s.step = 0.01
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(f)
	row.add_child(s)
	return row
