# SPDX-License-Identifier: Apache-2.0
## The Sound Lab's preset browser: every patch in the kit's presets, the
## starter bank and your own patch folder, filtered by category and by name.
## A click picks a patch; a double-click (or Enter) picks it and auditions it.
@tool
class_name AKPresetBrowser
extends VBoxContainer

## A patch was picked.
signal patch_selected(path: String)
## A patch was double-clicked or Enter was pressed on it.
signal patch_activated(path: String)

## Where patches are listed from, with a label for each.
const SOURCES := [
	["res://addons/audio_kit/patches/", "kit"],
	["res://addons/audio_kit/bank/patches/", "bank"],
	["res://audio/patches/", "yours"],
]

## [folder, label] pairs listed, in order (a copy of SOURCES to change).
var sources: Array = SOURCES.duplicate(true)

var _search: LineEdit
var _category: OptionButton
var _list: ItemList
var _entries: Array = []     # {path, name, category, source}
var _shown: Array = []       # paths in list order


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(190, 0)
	var row := HBoxContainer.new()
	add_child(row)
	_search = LineEdit.new()
	_search.placeholder_text = "Search patches"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t: String) -> void: _fill())
	row.add_child(_search)
	_category = OptionButton.new()
	_category.add_item("all")
	for c in AKPatch.CATEGORIES:
		_category.add_item(c)
	_category.item_selected.connect(func(_i: int) -> void: _fill())
	row.add_child(_category)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(i: int) -> void: patch_selected.emit(_shown[i]))
	_list.item_activated.connect(func(i: int) -> void:
		patch_selected.emit(_shown[i])
		patch_activated.emit(_shown[i]))
	add_child(_list)
	refresh()


## Re-scan the folders (after saving a patch, say).
func refresh() -> void:
	_entries.clear()
	for src in sources:
		var dir: String = src[0]
		if not DirAccess.dir_exists_absolute(dir):
			continue
		var files := Array(DirAccess.get_files_at(dir))
		files.sort()
		for f: String in files:
			# Exported projects list "x.tres.remap"; strip it.
			f = f.trim_suffix(".remap")
			if not f.ends_with(".tres") and not f.ends_with(".res"):
				continue
			var path := dir + f
			var p := load(path) as AKPatch
			if p == null:
				continue
			_entries.append({path = path, name = f.get_basename(), category = p.category if p.category != "" else "other", source = src[1]})
	_fill()


## Every patch found: [{path, name, category, source}].
func entries() -> Array:
	return _entries


## The paths shown for a search text and a category ("" or "all" for any).
func filtered(query: String, category := "") -> Array:
	var q := query.strip_edges().to_lower()
	var out := []
	for e in _entries:
		if category != "" and category != "all" and e.category != category:
			continue
		if q != "" and not (String(e.name).to_lower().contains(q) or String(e.category).contains(q) or String(e.source).contains(q)):
			continue
		out.append(e.path)
	return out


## Show the list for this search and category.
func set_filter(query: String, category := "all") -> void:
	_search.text = query
	var i := AKPatch.CATEGORIES.find(category)
	_category.select(i + 1 if i >= 0 else 0)
	_fill()


## Paths currently listed.
func shown() -> Array:
	return _shown


## Highlight `path` if it's listed.
func select_path(path: String) -> void:
	var i := _shown.find(path)
	if i >= 0:
		_list.select(i)
		_list.ensure_current_is_visible()


func _fill() -> void:
	var cat := _category.get_item_text(_category.selected) if _category.selected >= 0 else "all"
	_shown = filtered(_search.text, cat)
	_list.clear()
	var by_path := {}
	for e in _entries:
		by_path[e.path] = e
	for p in _shown:
		var e: Dictionary = by_path[p]
		var i := _list.add_item("%s   ·  %s" % [e.name, e.category if e.source != "yours" else "yours, " + e.category])
		_list.set_item_tooltip(i, p)
