# SPDX-License-Identifier: Apache-2.0
## The Sound Lab's synth page: build and play patches, and open songs.
##
##   Presets   browse the kit's presets, the starter bank and your own
##             patches by category and name; New starts from a blank patch
##   Panels    every part of the patch (oscillators, voice, filter,
##             envelopes, LFOs, matrix, effects), undoable; edits are heard
##             at once
##   Scope     the live output as a wave and a spectrum, and a rendered
##             preview note (re-rendered after edits with the native core)
##   Keyboard  click or drag, or the computer keys (Z S X ... / Q 2 W ...);
##             a connected MIDI keyboard plays too (bend, mod wheel, sustain)
##   Song      open a .mid or song, play it (live with the native core,
##             baked without), give each lane another patch, save it as text
##
## Presets from the kit and the bank are edited as copies, so they stay as
## shipped; Save writes the patch to res://audio/patches/ and goes on
## editing the saved file.
@tool
class_name AKSynthLab
extends HSplitContainer

const PRESET_GLOBS := ["res://addons/audio_kit/patches/", "res://addons/audio_kit/bank/patches/"]
## Where Save and "Save song" write by default (see set_save_dir).
const SAVE_DIR := "res://audio/"
## The preview note: middle C, held this long.
const PREVIEW_NOTE := 60
const PREVIEW_GATE_S := 0.6

## The patch being played and edited.
var patch: AKPatch
## Where the patch came from (a preset's path when editing a copy of it).
var patch_source := ""
## The song that's open (or null).
var song: AKSong
var router: AKMidiRouter
var keyboard: AKKeyboard
var live: AKLive
var player: AudioStreamPlayer
var editor: AKPatchEditor
var browser: AKPresetBrowser
var wave: AKScope
var spectrum: AKScope
var note_view: AKScope
var last_saved := ""
## Where Save writes patches (<dir>patches/) and songs (<dir>songs/).
var save_dir := SAVE_DIR
## The last preview note rendered (an AKBuffer), or null.
var preview: AKBuffer

var _patch_paths: Array = []
var _status: Label
var _title: Label
var _song_path: LineEdit
var _song_info: Label
var _lanes_box: VBoxContainer
var _devices: Label
var _vel: HSlider
var _sustain: CheckBox
var _save_name: LineEdit
var _preview_due := -1.0
var _scope_t := 0.0


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


func _process(delta: float) -> void:
	if live:
		live.update()
	if not is_visible_in_tree():
		return
	if _preview_due >= 0.0 and Time.get_ticks_msec() / 1000.0 >= _preview_due:
		_preview_due = -1.0
		preview_note()
	_scope_t += delta
	if _scope_t >= 0.05:
		_scope_t = 0.0
		update_scopes()


## Save patches and songs under `dir` (patches/ and songs/ inside it); the
## browser lists that patches folder as "yours".
func set_save_dir(dir: String) -> void:
	save_dir = dir if dir.ends_with("/") else dir + "/"
	browser.sources[2] = [save_dir + "patches/", "yours"]
	browser.refresh()


## The Sound Lab passes the editor's undo history here.
func set_undo(u: Object) -> void:
	editor.undo = u


## Listen to connected MIDI keyboards (opens the OS's MIDI inputs).
func set_midi_input(on: bool) -> void:
	router.listen = on
	router.set_process_input(on)
	if on:
		OS.open_midi_inputs()
	if _devices:
		var d := AKMidiRouter.devices()
		_devices.text = "MIDI in: " + (", ".join(d) if not d.is_empty() else "no devices") if on else "MIDI in: off"


## Play and edit the patch at `path` (or a patch). Kit and bank presets are
## edited as copies.
func select_patch(p: Variant) -> void:
	var pt: AKPatch = p if p is AKPatch else (load(String(p)) if ResourceLoader.exists(String(p)) else null)
	if pt == null:
		_say("Not a patch: %s" % p)
		return
	patch_source = pt.resource_path
	if _is_shipped(patch_source):
		var copy: AKPatch = pt.duplicate(true)
		copy.resource_name = patch_source.get_file().get_basename()
		pt = copy
	_set_patch(pt)
	if browser and patch_source != "":
		browser.select_path(patch_source)
	_say("Patch: %s%s" % [patch_source if patch_source != "" else String(pt.resource_name),
		" (a copy: Save keeps it in %spatches/)" % save_dir if _is_shipped(patch_source) else ""])


## Start a blank patch: one saw, an open filter, a plain envelope.
func new_patch() -> AKPatch:
	var p := AKPatch.new()
	p.resource_name = "init"
	patch_source = ""
	_set_patch(p)
	_say("New patch: build it in the panels, then Save.")
	return p


func note_on(note: int, velocity: float) -> void:
	router.note_on(note, velocity)


func note_off(note: int) -> void:
	router.note_off(note)


## Save the patch under save_dir/patches/<name>.tres and go on editing the
## saved file (presets stay as shipped).
func save_patch() -> String:
	if patch == null:
		return ""
	var base := _save_name.text.strip_edges().validate_filename() if _save_name else "patch"
	var path := save_dir + "patches/" + (base if base != "" else "patch") + ".tres"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var copy: AKPatch = patch if patch.resource_path == path else patch.duplicate(true)
	copy.resource_name = path.get_file().get_basename()
	if ResourceSaver.save(copy, path) != OK:
		_say("Couldn't save %s" % path)
		return ""
	last_saved = path
	AK.refresh_editor_files()
	if copy != patch:
		copy.take_over_path(path)
		patch_source = path
		_set_patch(copy)
	if browser:
		browser.refresh()
		browser.select_path(path)
	_say("Saved %s" % path)
	return path


## Render the preview note (middle C) and show it; returns the buffer.
func preview_note() -> AKBuffer:
	if patch == null:
		return null
	preview = AKSynth.render_notes(patch, [{time_s = 0.0, note = PREVIEW_NOTE, length_s = PREVIEW_GATE_S, velocity = 0.8}],
		PREVIEW_GATE_S + minf(patch.tail_s(), 1.4))
	var mono := _mono(preview)
	if note_view:
		note_view.show_samples(mono, preview.sample_rate)
	if spectrum and not _sounding():
		# The held part, after the attack.
		var a := mini(mono.size(), int(0.15 * preview.sample_rate))
		spectrum.show_samples(mono.slice(a, a + 8192), preview.sample_rate)
	return preview


## Refresh the wave and spectrum from what's playing.
func update_scopes() -> void:
	var s: Object = router.synth() if AKSynth.available() else null
	if s == null or not s.has_method(&"get_recent"):
		return
	var buf: PackedFloat32Array = s.get_recent(4096)
	if wave:
		wave.show_samples(buf)
	if spectrum and _sounding():
		spectrum.show_samples(buf)


func _sounding() -> bool:
	if not AKSynth.available():
		return false
	var s: Object = router.synth()
	return s != null and s.voice_count() > 0


func _mono(b: AKBuffer) -> PackedFloat32Array:
	var m := PackedFloat32Array()
	m.resize(b.frames())
	for i in m.size():
		m[i] = 0.5 * (b.l[i] + b.r[i])
	return m


func _is_shipped(path: String) -> bool:
	for d in PRESET_GLOBS:
		if path.begins_with(d):
			return true
	return false


func _set_patch(pt: AKPatch) -> void:
	if patch and patch.changed.is_connected(_on_patch_edited):
		patch.changed.disconnect(_on_patch_edited)
	patch = pt
	patch.changed.connect(_on_patch_edited)
	router.patch = pt
	if editor:
		editor.edit(pt)
	if _save_name:
		_save_name.text = (pt.resource_path.get_file().get_basename() if pt.resource_path != "" else String(pt.resource_name)).validate_filename()
	if _title:
		_title.text = String(pt.resource_name) if pt.resource_path == "" else pt.resource_path.get_file()
	var bar := _title.get_parent() if _title else null
	if bar and bar.has_meta(&"category"):
		var i := AKPatch.CATEGORIES.find(pt.category)
		(bar.get_meta(&"category") as OptionButton).select(i if i >= 0 else AKPatch.CATEGORIES.size() - 1)
	_on_patch_edited()


func _on_patch_edited() -> void:
	# Re-render the preview a moment after the last edit (natively it's quick).
	if AKSynth.available():
		_preview_due = Time.get_ticks_msec() / 1000.0 + 0.25


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


## Save the open song as text under save_dir/songs/<name>.tres.
func save_song() -> String:
	if song == null:
		return ""
	var base := String(song.resource_name).validate_filename()
	var path := save_dir + "songs/" + (base if base != "" else "song") + ".tres"
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


func _build() -> void:
	# Left: presets, then the song.
	var left := VBoxContainer.new()
	left.custom_minimum_size = AKUiScale.px(240, 0)
	add_child(left)
	_heading(left, "Presets")
	browser = AKPresetBrowser.new()
	browser.patch_selected.connect(func(path: String) -> void:
		if path != patch_source:
			select_patch(path))
	browser.patch_activated.connect(func(_path: String) -> void: audition())
	left.add_child(browser)
	_heading(left, "Song")
	var srow := HBoxContainer.new()
	left.add_child(srow)
	_song_path = LineEdit.new()
	_song_path.placeholder_text = "res://music/song.mid or a song .tres"
	_song_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	srow.add_child(_song_path)
	_button(srow, "Open", func() -> void: open_song(_song_path.text.strip_edges()))
	var srow2 := HBoxContainer.new()
	left.add_child(srow2)
	_button(srow2, "Play", play_song)
	_button(srow2, "Stop", stop_song)
	_button(srow2, "Save song", func() -> void: save_song())
	_song_info = Label.new()
	_song_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_song_info)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = AKUiScale.px(0, 90)
	left.add_child(scroll)
	_lanes_box = VBoxContainer.new()
	_lanes_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_lanes_box)

	# Right: the patch's toolbar, its panels beside the scopes, then the keyboard.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(right)
	var bar := HBoxContainer.new()
	right.add_child(bar)
	_title = Label.new()
	_title.add_theme_font_size_override(&"font_size", 15)
	_title.modulate = Color(1.0, 0.81, 0.23)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	bar.add_child(_title)
	_button(bar, "New", func() -> void: new_patch()).tooltip_text = "Start from a blank patch"
	_save_name = LineEdit.new()
	_save_name.custom_minimum_size = AKUiScale.px(130, 0)
	_save_name.tooltip_text = "Save as res://audio/patches/<name>.tres"
	bar.add_child(_save_name)
	_button(bar, "Save", func() -> void: save_patch())
	var cat := OptionButton.new()
	cat.tooltip_text = "The patch's category (for the preset browser)"
	for c in AKPatch.CATEGORIES:
		cat.add_item(c)
	cat.item_selected.connect(func(i: int) -> void:
		if patch:
			patch.category = AKPatch.CATEGORIES[i])
	bar.add_child(cat)
	bar.set_meta(&"category", cat)
	if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		_button(bar, "Inspector", func() -> void:
			if patch:
				Engine.get_singleton(&"EditorInterface").call(&"edit_resource", patch)).tooltip_text = "Show the patch in the inspector (the Audio Kit dock plays it there too)"
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(split)
	editor = AKPatchEditor.new()
	editor.custom_minimum_size = AKUiScale.px(320, 0)
	if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		editor.undo = Engine.get_singleton(&"EditorInterface").call(&"get_editor_undo_redo")   # Ctrl+Z in the editor
	split.add_child(editor)
	var scopes := VBoxContainer.new()
	scopes.custom_minimum_size = AKUiScale.px(240, 0)
	split.add_child(scopes)
	_heading(scopes, "Scope")
	wave = AKScope.new()
	wave.mode = AKScope.Mode.WAVE
	scopes.add_child(wave)
	_heading(scopes, "Spectrum")
	spectrum = AKScope.new()
	spectrum.mode = AKScope.Mode.SPECTRUM
	scopes.add_child(spectrum)
	var nrow := HBoxContainer.new()
	scopes.add_child(nrow)
	_heading(nrow, "Preview note")
	_button(nrow, "Render", func() -> void: preview_note()).tooltip_text = "Render middle C held %.1f s (automatic after edits with the native core)" % PREVIEW_GATE_S
	_button(nrow, "Play", audition)
	note_view = AKScope.new()
	note_view.mode = AKScope.Mode.NOTE
	scopes.add_child(note_view)
	_status = Label.new()
	_status.modulate = Color(1, 1, 1, 0.6)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scopes.add_child(_status)

	var krow := HBoxContainer.new()
	right.add_child(krow)
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
	_vel.custom_minimum_size = AKUiScale.px(100, 0)
	_vel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
	_devices = Label.new()
	_devices.modulate = Color(1, 1, 1, 0.6)
	_devices.text = "MIDI in: off" if AKSynth.available() else "Live play needs the native core (native/README.md)."
	krow.add_child(_devices)
	keyboard = AKKeyboard.new()
	keyboard.custom_minimum_size = AKUiScale.px(0, 100)
	keyboard.note_on.connect(note_on)
	keyboard.note_off.connect(note_off)
	right.add_child(keyboard)


## Play the patch: live (a short phrase on the synth) with the native core,
## else the preview note.
func audition() -> void:
	if patch == null:
		return
	if AKSynth.available():
		var s: Object = router.synth()
		for i in 3:
			var n: int = PREVIEW_NOTE + [0, 4, 7][i]
			s.note_on(n, 0.8, 0.18 * i)
			s.note_off(n, 0.18 * i + 0.3)
		s.note_on(PREVIEW_NOTE + 12, 0.8, 0.56)
		s.note_off(PREVIEW_NOTE + 12, 1.3)
		return
	var b := preview if preview else preview_note()
	player.stream = b.to_stream()
	if player.is_inside_tree():
		player.play()


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
		l.custom_minimum_size = AKUiScale.px(170, 0)
		row.add_child(l)
		var ob := OptionButton.new()
		ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cur: String = lanes[n].resource_path if lanes[n] is Resource else str(lanes[n])
		# The lane's own patch first when it isn't a kit or bank preset.
		var paths: Array = _patch_paths.duplicate()
		if cur != "" and not paths.has(cur):
			paths.push_front(cur)
		for i in paths.size():
			ob.add_item(String(paths[i]).get_file().get_basename())
			ob.set_item_tooltip(i, paths[i])
			if paths[i] == cur:
				ob.select(i)
		var lane: String = n
		ob.item_selected.connect(func(i: int) -> void: set_lane_patch(lane, paths[i]))
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
