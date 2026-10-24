# SPDX-License-Identifier: Apache-2.0
## The Sound Lab's synth page: play patches from an on-screen keyboard or a
## MIDI keyboard, and open songs (an AKSong .tres, or a .mid file imported
## through the starter bank) to play and re-voice them.
##
##   Patch     pick a preset, a GM family patch or a file; edit it in the
##             inspector on the right while playing; save it
##   Keyboard  click or drag, or the computer keys (Z S X ... / Q 2 W ...);
##             a connected MIDI keyboard plays too (with bend, mod wheel,
##             sustain)
##   Song      open a .mid or song, play it (live with the native core,
##             baked without), give each lane another patch, save it as text
@tool
class_name AKSynthLab
extends HSplitContainer

const PRESET_GLOBS := ["res://addons/audio_kit/patches/", "res://addons/audio_kit/bank/patches/"]
## Where "Save patch" and "Save song" write unless changed.
const SAVE_DIR := "res://audio/"

## The patch being played and edited.
var patch: AKPatch
## The song that's open (or null).
var song: AKSong
var router: AKMidiRouter
var keyboard: AKKeyboard
var live: AKLive
var player: AudioStreamPlayer
var last_saved := ""

var _patch_list: OptionButton
var _patch_paths: Array = []
var _status: Label
var _song_path: LineEdit
var _song_info: Label
var _lanes_box: VBoxContainer
var _inspector: Control
var _devices: Label
var _vel: HSlider
var _sustain: CheckBox
var _save_name: LineEdit


func _init() -> void:
	name = "Synth"
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
	player = AudioStreamPlayer.new()
	add_child(player)
	if AKLive.available():
		live = AKLive.new()
		live.lookahead_s = 0.3
		player.stream = live.stream
	_build()
	_refresh_patch_list()
	if not _patch_paths.is_empty():
		select_patch(_patch_paths[0])


func _ready() -> void:
	if live and is_inside_tree():
		player.play()


func _process(_delta: float) -> void:
	if live:
		live.update()


## Listen to connected MIDI keyboards (opens the OS's MIDI inputs).
func set_midi_input(on: bool) -> void:
	router.listen = on
	router.set_process_input(on)
	if on:
		OS.open_midi_inputs()
	if _devices:
		var d := AKMidiRouter.devices()
		_devices.text = "MIDI in: " + (", ".join(d) if not d.is_empty() else "no devices") if on else "MIDI in: off"


## Play and edit the patch at `path` (or a patch).
func select_patch(p: Variant) -> void:
	var pt: AKPatch = p if p is AKPatch else (load(String(p)) if ResourceLoader.exists(String(p)) else null)
	if pt == null:
		_say("Not a patch: %s" % p)
		return
	patch = pt
	router.patch = pt
	if _inspector:
		_inspector.call(&"edit", pt)
	if _save_name:
		_save_name.text = (pt.resource_path.get_file().get_basename() if pt.resource_path != "" else String(pt.resource_name)).validate_filename()
	_say("Patch: %s" % (pt.resource_path if pt.resource_path != "" else pt.resource_name))


func note_on(note: int, velocity: float) -> void:
	router.note_on(note, velocity)


func note_off(note: int) -> void:
	router.note_off(note)


## Save the patch under SAVE_DIR/patches/<name>.tres (a copy, so presets stay as shipped).
func save_patch() -> String:
	if patch == null:
		return ""
	var base := _save_name.text.strip_edges().validate_filename() if _save_name else "patch"
	var path := SAVE_DIR + "patches/" + (base if base != "" else "patch") + ".tres"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var copy: AKPatch = patch.duplicate(true)
	if ResourceSaver.save(copy, path) != OK:
		_say("Couldn't save %s" % path)
		return ""
	last_saved = path
	AK.refresh_editor_files()
	_say("Saved %s" % path)
	return path


## Open a song: an AKSong resource, or a .mid / .midi file (imported with the
## starter bank). Returns the song or null.
func open_song(path: String) -> AKSong:
	var s: AKSong = null
	var ext := path.get_extension().to_lower()
	if ext == "mid" or ext == "midi":
		s = AKMidi.import_file(path)
	elif ResourceLoader.exists(path):
		var r: Resource = load(path)
		s = r as AKSong
	if s == null:
		_say("Couldn't open %s as a song" % path)
		return null
	song = s
	if _song_path:
		_song_path.text = path
	if _song_info:
		_song_info.text = AKMidi.summary(s)
	_build_lanes()
	return s


## Play the open song: live (native core) or baked.
func play_song() -> void:
	if song == null:
		return
	stop_song()
	if live:
		var m := AKCueMap.new()
		m.master_fx = song.master_fx
		m.reverb = song.reverb
		live.prepare([], m)
		live.song_play(song, &"song")
		if player.is_inside_tree() and not player.playing:
			player.play()
		return
	_say("Rendering the song (no native core: this takes a while) ...")
	var buf: AKBuffer = song.render().mix
	player.stream = buf.to_stream()
	if player.is_inside_tree():
		player.play()


func stop_song() -> void:
	if live:
		live.song_stop(&"now")
		live.stream.clear()
	elif player.playing:
		player.stop()


## Give every lane called `lane` the patch `p` (a path or AKPatch), in every
## section.
func set_lane_patch(lane: String, p: Variant) -> void:
	if song == null:
		return
	for s in song.sections:
		for pat in s.get("patterns", []):
			var pt: AKPattern = pat if pat is AKPattern else load(String(pat))
			for i in pt.lanes.size():
				if String(pt.lanes[i].get("name", "")) == lane and pt.lanes[i].has("patch"):
					pt.lanes[i]["patch"] = p
			pt.set(&"_patch_recipes", {})
	song.emit_changed()


## Lanes of the open song with a patch: {name: patch ref}.
func patch_lanes() -> Dictionary:
	var out := {}
	if song == null:
		return out
	for s in song.sections:
		for pat in s.get("patterns", []):
			var pt: AKPattern = pat if pat is AKPattern else load(String(pat))
			for l in pt.lanes:
				if l.has("patch") and not out.has(l.name):
					out[l.name] = l.patch
	return out


## Save the open song as text under SAVE_DIR/songs/<name>.tres.
func save_song() -> String:
	if song == null:
		return ""
	var base := String(song.resource_name).validate_filename()
	var path := SAVE_DIR + "songs/" + (base if base != "" else "song") + ".tres"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if ResourceSaver.save(song, path) != OK:
		_say("Couldn't save %s" % path)
		return ""
	last_saved = path
	AK.refresh_editor_files()
	_say("Saved %s" % path)
	return path


# ------------------------------------------------------------------ building

func _refresh_patch_list() -> void:
	_patch_paths.clear()
	for dir in PRESET_GLOBS:
		var files := Array(DirAccess.get_files_at(dir))
		files.sort()
		for f in files:
			if f.ends_with(".tres"):
				_patch_paths.append(dir + f)
	if _patch_list:
		_patch_list.clear()
		for p in _patch_paths:
			_patch_list.add_item(String(p).get_file().get_basename())


func _build() -> void:
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.custom_minimum_size = Vector2(460, 0)
	add_child(left)
	_heading(left, "Patch")
	var prow := HBoxContainer.new()
	left.add_child(prow)
	_patch_list = OptionButton.new()
	_patch_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_patch_list.item_selected.connect(func(i: int) -> void: select_patch(_patch_paths[i]))
	prow.add_child(_patch_list)
	_save_name = LineEdit.new()
	_save_name.custom_minimum_size = Vector2(120, 0)
	_save_name.tooltip_text = "Name for Save patch"
	prow.add_child(_save_name)
	_button(prow, "Save patch", func() -> void: save_patch())
	_heading(left, "Play")
	var krow := HBoxContainer.new()
	left.add_child(krow)
	_button(krow, "Oct -", func() -> void: keyboard.low_note -= 12)
	_button(krow, "Oct +", func() -> void: keyboard.low_note += 12)
	var vl := Label.new()
	vl.text = "Velocity"
	krow.add_child(vl)
	_vel = HSlider.new()
	_vel.min_value = 0.05
	_vel.max_value = 1.0
	_vel.step = 0.01
	_vel.value = 0.8
	_vel.custom_minimum_size = Vector2(100, 0)
	_vel.value_changed.connect(func(v: float) -> void: keyboard.velocity = v)
	krow.add_child(_vel)
	_sustain = CheckBox.new()
	_sustain.text = "Sustain"
	_sustain.toggled.connect(func(on: bool) -> void: router.set_sustain(on))
	krow.add_child(_sustain)
	_button(krow, "All off", func() -> void:
		router.all_notes_off()
		keyboard.release_all())
	var midi := CheckBox.new()
	midi.text = "MIDI input"
	midi.toggled.connect(set_midi_input)
	krow.add_child(midi)
	keyboard = AKKeyboard.new()
	keyboard.custom_minimum_size = Vector2(0, 110)
	keyboard.note_on.connect(note_on)
	keyboard.note_off.connect(note_off)
	left.add_child(keyboard)
	_devices = Label.new()
	_devices.modulate = Color(1, 1, 1, 0.6)
	_devices.text = "MIDI in: off" if AKSynth.available() else "Live play needs the native core (native/README.md)."
	left.add_child(_devices)
	_heading(left, "Song")
	var srow := HBoxContainer.new()
	left.add_child(srow)
	_song_path = LineEdit.new()
	_song_path.placeholder_text = "res://music/song.mid or a song .tres"
	_song_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	srow.add_child(_song_path)
	_button(srow, "Open", func() -> void: open_song(_song_path.text.strip_edges()))
	_button(srow, "Play", play_song)
	_button(srow, "Stop", stop_song)
	_button(srow, "Save song", func() -> void: save_song())
	_song_info = Label.new()
	_song_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_song_info)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(scroll)
	_lanes_box = VBoxContainer.new()
	_lanes_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_lanes_box)
	_status = Label.new()
	_status.modulate = Color(1, 1, 1, 0.6)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_status)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(300, 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(right)
	_heading(right, "Patch settings")
	if Engine.is_editor_hint() and ClassDB.can_instantiate(&"EditorInspector"):
		_inspector = ClassDB.instantiate(&"EditorInspector")
		_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_inspector.connect(&"property_edited", func(_p: String) -> void:
			if patch:
				patch.emit_changed())
		right.add_child(_inspector)
	else:
		var l := Label.new()
		l.text = "The patch's inspector shows here in the editor."
		right.add_child(l)


## A row per patch lane: its name and a menu of patches to swap in.
func _build_lanes() -> void:
	for c in _lanes_box.get_children():
		c.queue_free()
	var lanes := patch_lanes()
	var names := lanes.keys()
	names.sort()
	for n in names:
		var row := HBoxContainer.new()
		_lanes_box.add_child(row)
		var l := Label.new()
		l.text = n
		l.custom_minimum_size = Vector2(170, 0)
		row.add_child(l)
		var ob := OptionButton.new()
		ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cur: String = lanes[n].resource_path if lanes[n] is Resource else str(lanes[n])
		for i in _patch_paths.size():
			ob.add_item(String(_patch_paths[i]).get_file().get_basename())
			if _patch_paths[i] == cur:
				ob.select(i)
		var lane: String = n
		ob.item_selected.connect(func(i: int) -> void: set_lane_patch(lane, _patch_paths[i]))
		row.add_child(ob)


func _say(text: String) -> void:
	if _status:
		_status.text = text


func _heading(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", 15)
	l.modulate = Color(1.0, 0.81, 0.23)
	parent.add_child(l)


func _button(parent: Control, text: String, f: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(f)
	parent.add_child(b)
	return b
