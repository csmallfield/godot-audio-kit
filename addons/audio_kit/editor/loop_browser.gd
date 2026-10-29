# SPDX-License-Identifier: Apache-2.0
## The Loops tab's loop browser: the project's loops (res://audio/loops/ by
## default) by kind and category, with a search, like the preset browser.
## A click opens a loop; a double-click (or Enter) also auditions it.
@tool
class_name AKLoopBrowser
extends VBoxContainer

signal loop_selected(path: String)
signal loop_activated(path: String)

## Folders listed (each searched one level deep).
var folders: Array[String] = ["res://audio/loops/"]

var _search: LineEdit
var _kind: OptionButton
var _list: ItemList
var _entries: Array = []     # {path, name, kind, category}
var _shown: Array = []


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(180, 0)
	var row := HBoxContainer.new()
	add_child(row)
	_search = LineEdit.new()
	_search.placeholder_text = "Search loops"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t: String) -> void: _fill())
	row.add_child(_search)
	_kind = OptionButton.new()
	for k in ["all"] + AKLoop.KINDS:
		_kind.add_item(k)
	_kind.item_selected.connect(func(_i: int) -> void: _fill())
	row.add_child(_kind)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(i: int) -> void: loop_selected.emit(_shown[i]))
	_list.item_activated.connect(func(i: int) -> void:
		loop_selected.emit(_shown[i])
		loop_activated.emit(_shown[i]))
	add_child(_list)
	refresh()


func refresh() -> void:
	_entries.clear()
	for dir in folders:
		if not DirAccess.dir_exists_absolute(dir):
			continue
		var files := Array(DirAccess.get_files_at(dir))
		files.sort()
		for f: String in files:
			f = f.trim_suffix(".remap")
			if not f.ends_with(".tres") and not f.ends_with(".res"):
				continue
			var l := ResourceLoader.load(dir + f, "", ResourceLoader.CACHE_MODE_REUSE) as AKLoop
			if l == null:
				continue
			_entries.append({path = dir + f, name = f.get_basename(), kind = l.kind, category = l.category})
	_fill()


func entries() -> Array:
	return _entries


## Paths matching a search and a kind ("" or "all" for any).
func filtered(query: String, kind := "") -> Array:
	var q := query.strip_edges().to_lower()
	var out := []
	for e in _entries:
		if kind != "" and kind != "all" and e.kind != kind:
			continue
		if q != "" and not (String(e.name).to_lower().contains(q) or String(e.category).to_lower().contains(q) or String(e.kind).contains(q)):
			continue
		out.append(e.path)
	return out


func shown() -> Array:
	return _shown


func select_path(path: String) -> void:
	var i := _shown.find(path)
	if i >= 0:
		_list.select(i)
		_list.ensure_current_is_visible()


func _fill() -> void:
	var kind := _kind.get_item_text(_kind.selected) if _kind.selected >= 0 else "all"
	_shown = filtered(_search.text, kind)
	_list.clear()
	var by := {}
	for e in _entries:
		by[e.path] = e
	for p in _shown:
		var e: Dictionary = by[p]
		var i := _list.add_item("%s  ·  %s%s" % [e.name, e.kind, ", " + e.category if e.category != "" else ""])
		_list.set_item_tooltip(i, p)
