# SPDX-License-Identifier: Apache-2.0
## The Sound Lab: an editor main screen (beside 2D, 3D and Script) for
## making game sounds quickly.
##
##   Generate   pick a category; each press gives a new seed's sound
##   Seed       type one to get that exact sound back
##   Randomise  anything goes (the "random" generator)
##   Mutate     a near neighbour of the current sound
##   Play       hear it (new variant each play, if you like); it also plays
##              by itself after each change
##   Bake WAV   write it into the project as an ordinary WAV
##   Save recipe / Save stream   keep it editable: an AKRecipe, or an
##              AKRecipeStream that plays (and varies) in any AudioStreamPlayer
##
## The current sound is an ordinary AKRecipe, shown in an inspector on the
## right: edit anything there and it replays. Everything is deterministic:
## the same category and seed always give the same recipe and samples.
@tool
class_name AKSoundLab
extends HSplitContainer

## Where bakes and saves go unless changed in the lab.
const DEFAULT_DIR := "res://audio/sfx/"
const AUTO_DELAY_S := 0.3
const HISTORY_MAX := 40

## Emitted whenever the current recipe is replaced (generate, mutate, history).
signal recipe_changed(recipe: AKRecipe)

## The sound being worked on.
var recipe: AKRecipe
## The category new sounds come from.
var category: StringName = &"pickup"
## The last render: {length_s, peak_db, lufs, ms}.
var last_stats := {}
## The last file Bake WAV or a save wrote.
var last_saved := ""
## Earlier sounds, newest last.
var history: Array[AKRecipe] = []
var player: AudioStreamPlayer

var _rng := RandomNumberGenerator.new()
var _last_buf: AKBuffer
var _variant := 0
var _replay_at := -1.0
var _quiet := false

var _seed: SpinBox
var _mutate_amount: HSlider
var _vary: CheckBox
var _auto: CheckBox
var _title: Label
var _stats: Label
var _summary: Label
var _wave: Control
var _history_list: ItemList
var _dir: LineEdit
var _name: LineEdit
var _status: Label
var _inspector: Control
var _cat_buttons := {}


func _init() -> void:
	name = "Sound Lab"
	_rng.randomize()
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	player = AudioStreamPlayer.new()
	add_child(player)
	_build_left()
	var right := HSplitContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(right)
	_build_centre(right)
	_build_inspector(right)
	generate(category, 1, false)


func _process(delta: float) -> void:
	if _replay_at >= 0.0:
		_replay_at -= delta
		if _replay_at < 0.0:
			play()


# ------------------------------------------------------------------ actions

## Make the sound for `cat` and `seed` (a random seed when negative) the
## current one, and play it unless `audible` is false.
func generate(cat: StringName, seed := -1, audible := true) -> AKRecipe:
	var s := seed if seed >= 0 else _rng.randi_range(1, 99999)
	var r := AKSfxGen.generate(cat, s)
	if r == null:
		return null
	category = cat
	_set_recipe(r, audible)
	return r


## A wild sound from the "random" generator.
func randomise() -> AKRecipe:
	return generate(&"random", -1)


## Replace the current sound with a nudged copy of it.
func mutate() -> AKRecipe:
	if recipe == null:
		return null
	var amount := _mutate_amount.value if _mutate_amount else 0.15
	var r := AKSfxGen.mutate(recipe, _rng.randi(), amount)
	_set_recipe(r, true)
	return r


## Render the current sound (the next variant when "new variant each play"
## is on), measure it, draw it and play it.
func play() -> void:
	_replay_at = -1.0
	if recipe == null:
		return
	if _vary and _vary.button_pressed:
		_variant += 1
	else:
		_variant = 0
	var t := Time.get_ticks_usec()
	var buf := AK.render(recipe, 1.0, {}, _variant)
	var ms := (Time.get_ticks_usec() - t) / 1000.0
	_last_buf = buf
	var peak := buf.peak()
	last_stats = {length_s = buf.seconds(), peak_db = linear_to_db(peak) if peak > 0.0 else -INF,
		lufs = AKDynamics.lufs(buf), ms = ms}
	if _stats:
		_stats.text = "%.2f s   peak %.1f dBFS   %.1f LUFS   rendered in %.0f ms%s" % [last_stats.length_s,
			last_stats.peak_db, last_stats.lufs, ms, "   variant %d" % _variant if _variant > 0 else ""]
	if _wave:
		_wave.call(&"set_buffer", buf)
	player.stream = buf.to_stream(AK._seed(recipe.seed, AK._variant(recipe, _variant), 77))
	if player.is_inside_tree():
		player.play()


func stop() -> void:
	_replay_at = -1.0
	player.stop()


## Write the current sound (variant 0, exactly what AK.bake gives) to
## <folder>/<name>.wav and return the path, or "".
func bake_wav() -> String:
	if recipe == null:
		return ""
	var path := _path("wav")
	if AK.bake_wav(recipe, path) != OK:
		_say("Couldn't write %s." % path)
		return ""
	last_saved = path
	_say("Baked %s. Godot imports it as an AudioStreamWAV." % path)
	return path


## Save the current recipe as <folder>/<name>.tres and return the path.
func save_recipe() -> String:
	if recipe == null:
		return ""
	var path := _path("tres")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var r: AKRecipe = recipe.duplicate(true)
	if ResourceSaver.save(r, path) != OK:
		_say("Couldn't save %s." % path)
		return ""
	last_saved = path
	AK.refresh_editor_files()
	_say("Saved recipe %s." % path)
	return path


## Save an AKRecipeStream holding the current recipe as
## <folder>/<name>_stream.tres (the recipe embedded) and return the path.
func save_stream() -> String:
	if recipe == null:
		return ""
	var path := _path("tres", "_stream")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var s := AKRecipeStream.of(recipe.duplicate(true))
	if ResourceSaver.save(s, path) != OK:
		_say("Couldn't save %s." % path)
		return ""
	last_saved = path
	AK.refresh_editor_files()
	_say("Saved stream %s: drop it on any AudioStreamPlayer." % path)
	return path


## Go back to an earlier sound.
func restore(index: int) -> void:
	if index >= 0 and index < history.size():
		_set_recipe(history[index], true, false)


# ------------------------------------------------------------------ inside

func _set_recipe(r: AKRecipe, audible: bool, remember := true) -> void:
	if recipe and recipe.changed.is_connected(_on_recipe_edited):
		recipe.changed.disconnect(_on_recipe_edited)
	recipe = r
	recipe.changed.connect(_on_recipe_edited)
	if remember:
		history.append(r)
		if history.size() > HISTORY_MAX:
			history.remove_at(0)
		_refresh_history()
	var cat := StringName(r.get_meta(&"sfx_category", String(category)))
	_quiet = true
	if _seed:
		_seed.value = int(r.get_meta(&"sfx_seed", r.seed))
	_quiet = false
	for k in _cat_buttons:
		_cat_buttons[k].button_pressed = k == cat
	if _title:
		_title.text = String(r.resource_name)
	if _name:
		_name.text = AKSfxGen.name_for(r)
	_refresh_summary()
	if _inspector:
		_inspector.call(&"edit", r)
	recipe_changed.emit(r)
	if audible:
		play()
	else:
		_replay_at = -1.0


func _on_recipe_edited() -> void:
	_refresh_summary()
	if _auto and _auto.button_pressed:
		_replay_at = AUTO_DELAY_S


func _refresh_history() -> void:
	if _history_list == null:
		return
	_history_list.clear()
	for i in range(history.size() - 1, -1, -1):
		var idx := _history_list.add_item(String(history[i].resource_name))
		_history_list.set_item_metadata(idx, i)


func _refresh_summary() -> void:
	if _summary == null or recipe == null:
		return
	var lines := PackedStringArray()
	var specs: Array = []
	if recipe.voice != &"":
		specs.append({voice = recipe.voice, params = recipe.params})
	specs.append_array(recipe.layers)
	for sp in specs:
		var p: Dictionary = sp.get("params", {})
		var bits := PackedStringArray()
		for k in ["wave", "freq_hz", "end_hz", "start_hz", "length_s", "gate_s", "mode", "noise", "material"]:
			if p.has(k):
				bits.append("%s %s" % [k, str(p[k])])
		var extra := ""
		if float(sp.get("offset_s", 0.0)) > 0.0:
			extra += "  +%.3f s" % float(sp.offset_s)
		if float(sp.get("gain_db", 0.0)) != 0.0:
			extra += "  %+.1f dB" % float(sp.gain_db)
		lines.append("%s%s: %s" % [sp.get("voice", "?"), extra, ", ".join(bits)])
	var fx := PackedStringArray()
	for e in recipe.fx:
		fx.append(String(e.get("type", "?")))
	lines.append("fx: " + (" > ".join(fx) if not fx.is_empty() else "none"))
	_summary.text = "\n".join(lines)


func _path(ext: String, suffix := "") -> String:
	var dir := (_dir.text if _dir and _dir.text.strip_edges() != "" else DEFAULT_DIR).strip_edges()
	if not dir.ends_with("/"):
		dir += "/"
	var base := (_name.text if _name and _name.text.strip_edges() != "" else AKSfxGen.name_for(recipe)).strip_edges()
	base = base.validate_filename().replace(" ", "_")
	return dir + base + suffix + "." + ext


func _say(text: String) -> void:
	if _status:
		_status.text = text


func _build_left() -> void:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = AKUiScale.px(230, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	_heading(box, "Generate")
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	for cat in AKSfxGen.CATEGORIES:
		var b := Button.new()
		b.text = String(cat).capitalize() if not String(cat).begins_with("ui_") else "UI " + String(cat).substr(3)
		b.tooltip_text = String(AKSfxGen.ABOUT.get(cat, "")) + "\nEach press: a new seed."
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void: generate(cat, -1))
		grid.add_child(b)
		_cat_buttons[cat] = b
	var seed_row := HBoxContainer.new()
	box.add_child(seed_row)
	var sl := Label.new()
	sl.text = "Seed"
	seed_row.add_child(sl)
	_seed = SpinBox.new()
	_seed.min_value = 0
	_seed.max_value = 9999999
	_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed.tooltip_text = "The same category and seed always give the same sound."
	_seed.value_changed.connect(func(v: float) -> void:
		if not _quiet:
			generate(category, int(v)))
	seed_row.add_child(_seed)
	var rnd := _button(box, "Randomise", func() -> void: randomise())
	rnd.tooltip_text = String(AKSfxGen.ABOUT[&"random"])
	_heading(box, "Change")
	var m := _button(box, "Mutate", func() -> void: mutate())
	m.tooltip_text = "Nudge every number a little (pitches, times, levels). Repeat to wander."
	var mrow := HBoxContainer.new()
	box.add_child(mrow)
	var ml := Label.new()
	ml.text = "Amount"
	mrow.add_child(ml)
	_mutate_amount = HSlider.new()
	_mutate_amount.min_value = 0.02
	_mutate_amount.max_value = 0.5
	_mutate_amount.step = 0.01
	_mutate_amount.value = 0.15
	_mutate_amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mrow.add_child(_mutate_amount)
	_heading(box, "Listen")
	var prow := HBoxContainer.new()
	box.add_child(prow)
	_button(prow, "Play", play)
	_button(prow, "Stop", stop)
	_vary = CheckBox.new()
	_vary.text = "New variant each play"
	_vary.tooltip_text = "Each play takes the next variant of the recipe's vary spread, as an AKRecipeStream does."
	box.add_child(_vary)
	_auto = CheckBox.new()
	_auto.text = "Replay when edited"
	_auto.button_pressed = true
	box.add_child(_auto)
	_heading(box, "History")
	_history_list = ItemList.new()
	_history_list.custom_minimum_size = AKUiScale.px(0, 120)
	_history_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_history_list.item_selected.connect(func(i: int) -> void: restore(int(_history_list.get_item_metadata(i))))
	box.add_child(_history_list)


func _build_centre(parent: Control) -> void:
	# Scrolls, like the left column, so a short editor window never clips it.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = AKUiScale.px(320, 0)
	parent.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override(&"font_size", roundi(20 * AKUiScale.factor()))
	box.add_child(_title)
	_stats = Label.new()
	box.add_child(_stats)
	_wave = AKAuditionDock._Wave.new()
	_wave.custom_minimum_size = AKUiScale.px(0, 140)
	box.add_child(_wave)
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.modulate = Color(1, 1, 1, 0.75)
	box.add_child(_summary)
	_heading(box, "Keep it")
	var drow := HBoxContainer.new()
	box.add_child(drow)
	var dl := Label.new()
	dl.text = "Folder"
	dl.custom_minimum_size = AKUiScale.px(60, 0)
	drow.add_child(dl)
	_dir = LineEdit.new()
	_dir.text = DEFAULT_DIR
	_dir.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drow.add_child(_dir)
	var nrow := HBoxContainer.new()
	box.add_child(nrow)
	var nl := Label.new()
	nl.text = "Name"
	nl.custom_minimum_size = AKUiScale.px(60, 0)
	nrow.add_child(nl)
	_name = LineEdit.new()
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nrow.add_child(_name)
	var brow := HBoxContainer.new()
	box.add_child(brow)
	var bw := _button(brow, "Bake WAV", bake_wav)
	bw.tooltip_text = "Write a 16-bit WAV into the project (imports as AudioStreamWAV; needs nothing from the kit to play)."
	var sr := _button(brow, "Save recipe", save_recipe)
	sr.tooltip_text = "Save the AKRecipe (.tres): text you can edit, diff and bake later."
	var ss := _button(brow, "Save stream", save_stream)
	ss.tooltip_text = "Save an AKRecipeStream (.tres): an AudioStream that renders the recipe, varying each play."
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = Color(1, 1, 1, 0.6)
	box.add_child(_status)


## An EditorInspector for the current recipe when running in the editor;
## outside it (tests, games), a note and nothing else.
func _build_inspector(parent: Control) -> void:
	var box := VBoxContainer.new()
	box.custom_minimum_size = AKUiScale.px(300, 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_stretch_ratio = 0.8
	parent.add_child(box)
	_heading(box, "Recipe")
	if Engine.is_editor_hint() and ClassDB.can_instantiate(&"EditorInspector"):
		_inspector = ClassDB.instantiate(&"EditorInspector")
		_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
		if _inspector.has_signal(&"property_edited"):
			_inspector.connect(&"property_edited", func(_p: String) -> void: _on_recipe_edited())
		box.add_child(_inspector)
	else:
		var l := Label.new()
		l.text = "The recipe's inspector shows here in the editor."
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(l)
	var b := _button(box, "Open in Inspector", func() -> void:
		if recipe and Engine.has_singleton(&"EditorInterface"):
			Engine.get_singleton(&"EditorInterface").call(&"edit_resource", recipe))
	b.tooltip_text = "Edit it in the main inspector too (the Audio Kit dock follows it there)."


func _heading(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", roundi(15 * AKUiScale.factor()))
	l.modulate = Color(1.0, 0.81, 0.23)
	parent.add_child(l)


func _button(parent: Control, text: String, f: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(f)
	parent.add_child(b)
	return b
