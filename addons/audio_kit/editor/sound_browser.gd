# SPDX-License-Identifier: Apache-2.0
## The sound library browser, shared by the Loops tab's instrument picker
## and its kit editor: the kit-made library (addons/audio_kit/library/, by
## folder) beside the project's own sounds (.wav and .ogg files and AKSample
## resources under res://audio/), with a search, a folder filter and a
## waveform of the selected sound. A click selects (and auditions, when
## `audition_on_click`); a double-click (or Enter) picks it.
@tool
class_name AKSoundBrowser
extends VBoxContainer

signal sound_selected(path: String)
signal sound_activated(path: String)
## Play this sound (the tab owns the player).
signal audition(path: String)

## Project folder searched for sounds (recursively).
var project_dir := "res://audio/"
var audition_on_click := true

var _search: LineEdit
var _folder: OptionButton
var _list: ItemList
var _wave: Control
var _entries: Array = []     # {path, name, folder, source (library|project), root}
var _shown: Array = []
var _selected := ""
var _peaks := PackedFloat32Array()


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = AKUiScale.px(180, 0)
	var row := HBoxContainer.new()
	add_child(row)
	_search = LineEdit.new()
	_search.placeholder_text = "Search sounds"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t: String) -> void: _fill())
	row.add_child(_search)
	_folder = OptionButton.new()
	_folder.add_item("all")
	for f in AKLibrary.FOLDERS:
		_folder.add_item(f)
	_folder.add_item("project")
	_folder.item_selected.connect(func(_i: int) -> void: _fill())
	row.add_child(_folder)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(i: int) -> void: _pick(_shown[i], false))
	_list.item_activated.connect(func(i: int) -> void: _pick(_shown[i], true))
	add_child(_list)
	_wave = Control.new()
	_wave.custom_minimum_size = AKUiScale.px(0, 48)
	_wave.draw.connect(_draw_wave)
	add_child(_wave)
	refresh()


func refresh() -> void:
	_entries.clear()
	for s: Dictionary in AKLibrary.sounds():
		_entries.append({path = AKLibrary.path_of(s.folder, s.name), name = s.name, folder = s.folder, source = "library", root = s.root})
	_scan(project_dir)
	_fill()


func _scan(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		if not d.begins_with("."):
			_scan(dir.path_join(d))
	var files := Array(DirAccess.get_files_at(dir))
	files.sort()
	for f: String in files:
		f = f.trim_suffix(".remap")
		var ext := f.get_extension().to_lower()
		var path := dir.path_join(f)
		if ext in ["wav", "ogg"]:
			_entries.append({path = path, name = f, folder = "project", source = "project", root = -1})
		elif ext == "tres" and f.ends_with(".sample.tres"):
			var s := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE) as AKSample
			if s:
				_entries.append({path = path, name = f.trim_suffix(".tres"), folder = "project", source = "project", root = int(s.root_note)})


func entries() -> Array:
	return _entries


## Paths for a search and a folder ("" or "all" for any; "project" for the project's own).
func filtered(query: String, folder := "") -> Array:
	var q := query.strip_edges().to_lower()
	var out := []
	for e in _entries:
		if folder != "" and folder != "all" and e.folder != folder:
			continue
		if q != "" and not (String(e.name).to_lower().contains(q) or String(e.folder).contains(q)):
			continue
		out.append(e.path)
	return out


func set_filter(query: String, folder := "all") -> void:
	_search.text = query
	for i in _folder.item_count:
		if _folder.get_item_text(i) == folder:
			_folder.select(i)
	_fill()


func shown() -> Array:
	return _shown


func selected() -> String:
	return _selected


func select_path(path: String) -> void:
	var i := _shown.find(path)
	if i >= 0:
		_list.select(i)
		_list.ensure_current_is_visible()
		_pick(path, false, false)


func _pick(path: String, activate: bool, play := true) -> void:
	_selected = path
	sound_selected.emit(path)
	_peaks = _wave_of(path)
	_wave.queue_redraw()
	if activate:
		sound_activated.emit(path)
	if play and (audition_on_click or activate):
		audition.emit(path)


## A sample for any listed sound: a library recipe at its root note, an
## AKSample resource, or a sound file (decoded, not yet saved).
static func sample_for(path: String) -> AKSample:
	var ext := path.get_extension().to_lower()
	if ext in ["wav", "ogg"]:
		var s := AKSample.new()
		s.source = path
		if s.import_source(true) != "":
			return null
		s.resource_name = path.get_file().get_basename()
		return s
	var r: Resource = load(path) if ResourceLoader.exists(path) else null
	if r is AKSample:
		return r
	if r is AKRecipe:
		return AKLibrary.sample_for(path)
	return null


func _wave_of(path: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var s := sample_for(path)
	if s == null:
		return out
	var d: PackedFloat32Array = s.samples()[0]
	var cols := 160
	out.resize(cols)
	var per := maxi(1, d.size() / cols)
	for c in cols:
		var m := 0.0
		for i in range(c * per, mini(d.size(), (c + 1) * per), maxi(1, per / 64)):
			m = maxf(m, absf(d[i]))
		out[c] = m
	return out


func _draw_wave() -> void:
	var sz := _wave.size
	_wave.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.1, 0.105, 0.12))
	if _peaks.is_empty():
		return
	var pk := 1e-6
	for v in _peaks:
		pk = maxf(pk, v)
	var w := sz.x / _peaks.size()
	for c in _peaks.size():
		var h := _peaks[c] / pk * (sz.y * 0.5 - 2.0)
		_wave.draw_rect(Rect2(c * w, sz.y * 0.5 - h, maxf(1.0, w - 0.5), 2.0 * h), Color(0.5, 0.75, 1.0))


func _fill() -> void:
	var folder := _folder.get_item_text(_folder.selected) if _folder.selected >= 0 else "all"
	_shown = filtered(_search.text, folder)
	_list.clear()
	var by := {}
	for e in _entries:
		by[e.path] = e
	for p in _shown:
		var e: Dictionary = by[p]
		var root := " · %s" % AKNotes.midi_to_name(int(e.root)) if int(e.root) >= 0 else ""
		var i := _list.add_item("%s  ·  %s%s" % [e.name, e.folder, root])
		_list.set_item_tooltip(i, p)
