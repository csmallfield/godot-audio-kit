# SPDX-License-Identifier: Apache-2.0
## The Sound Lab's patch library browser (docs/plans/patch-library.md): the kit's presets, the
## starter bank, your own patches and every library folder, with a search, filters that show how
## many patches each choice leaves, sorting, and your stars, favourites, tags and category overrides
## (kept in a user file, never in the patches). A click picks a patch; a double-click (or Enter)
## picks it and auditions it.
@tool
class_name AKLibraryBrowser
extends VBoxContainer

## A patch was picked.
signal patch_selected(path: String)
## A patch was double-clicked or Enter was pressed on it.
signal patch_activated(path: String)
## A library patch was copied into the project (its new path).
signal copied(path: String)

## Rows listed at a time ("More" adds as many again).
const PAGE := 300
const SORTS := ["name", "rating", "confidence", "error", "random"]
const SORT_LABELS := ["A-Z", "Stars", "Surest category", "Closest to source", "Shuffle"]
const FACET_LABELS := {category = "Category", source = "Source", origin = "Origin", emulates_maker = "Maker",
	emulates_model = "Model", creator = "Creator", bank = "Bank"}

## The data: entries, filters, the user file.
var library := AKPatchLibrary.new()
## [folder, label] pairs listed from the project; label "yours" marks your own patches (the Synth
## page points the last at its save folder).
var sources: Array = [
	["res://addons/audio_kit/patches/", "kit"],
	["res://addons/audio_kit/bank/patches/", "bank"],
	["res://audio/patches/", "yours"],
]
## Library folders; empty reads them from the editor settings.
var roots := PackedStringArray()
## Where "Use in project" copies a library patch.
var copy_dir := "res://audio/patches/"

var _search: LineEdit
var _sort: OptionButton
var _count: Label
var _filters_box: GridContainer
var _facets := {}            # facet -> OptionButton
var _min_rating: OptionButton
var _favs: CheckBox
var _confident: CheckBox
var _hidden: CheckBox
var _list: ItemList
var _more: Button
var _detail: VBoxContainer
var _d_title: Label
var _d_info: Label
var _stars: Array[Button] = []
var _fav_btn: Button
var _hide_btn: Button
var _d_cat: OptionButton
var _d_tags: LineEdit
var _problems: Label
var _folders_dialog: AcceptDialog
var _folders_list: ItemList
var _dir_dialog: FileDialog
var _debounce: Timer

var _items: Array = []       # entries matching, in order
var _shown: Array = []       # paths of every match, in order
var _limit := PAGE
var _selected := ""          # selected entry ID
var _seed := 1
var _filling := false


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = AKUiScale.px(190, 0)
	_build()
	refresh()


# ------------------------------------------------------------------ the old preset browser's calls

## Reload the project's patches, the library folders and the user file (after saving, say).
func refresh() -> void:
	library.project_dirs = []
	for s in sources:
		var yours: bool = s[1] == "yours"
		library.project_dirs.append([s[0], "sound-lab" if yours else "kit", "created" if yours else "default"])
	library.roots = roots if not roots.is_empty() else AKPatchLibrary.editor_roots()
	library.load_all()
	_problems.text = "\n".join(library.problems)
	_problems.visible = not library.problems.is_empty()
	_fill()


## Every patch: [{path, name, category, source, ...}].
func entries() -> Array:
	return library.entries


## The paths for a search text and a category ("" or "all" for any).
func filtered(query: String, category := "") -> Array:
	return library.filter({query = query, category = category}).map(func(e: Dictionary) -> String: return e.path)


## Show the list for this search and category.
func set_filter(query: String, category := "all") -> void:
	_search.text = query
	_select_facet("category", category if category != "all" else "")
	_fill()


## Paths currently matching, in order.
func shown() -> Array:
	return _shown


## Highlight `path` if it's listed.
func select_path(path: String) -> void:
	var i := _shown.find(path)
	if i < 0:
		return
	if i >= _limit:
		_limit = i + 1
		_fill_list()
	_list.select(i)
	_list.ensure_current_is_visible()
	_show_detail(_items[i])


# ------------------------------------------------------------------ filters

## The filter the controls describe (for AKPatchLibrary.query).
func current_filter() -> Dictionary:
	var f := {query = _search.text, sort = SORTS[maxi(0, _sort.selected)], seed = _seed,
		min_rating = maxi(0, _min_rating.selected), favourites = _favs.button_pressed,
		confident = _confident.button_pressed, show_hidden = _hidden.button_pressed}
	for k in _facets:
		var ob: OptionButton = _facets[k]
		f[k] = String(ob.get_item_metadata(ob.selected)) if ob.selected > 0 else ""
	return f


## Pick a facet's value ("" for any) without waiting for the menus to be refilled.
func set_facet(facet: String, value: String) -> void:
	_select_facet(facet, value)
	_fill()


func _select_facet(facet: String, value: String) -> void:
	var ob: OptionButton = _facets[facet]
	if value == "":
		ob.select(0)
		return
	for i in ob.item_count:
		if String(ob.get_item_metadata(i)) == value:
			ob.select(i)
			return
	ob.add_item(value)
	ob.set_item_metadata(ob.item_count - 1, value)
	ob.select(ob.item_count - 1)


func _fill() -> void:
	if _filling:
		return
	_filling = true
	var f := current_filter()
	var r := library.query(f)
	_items = r.items
	_shown = _items.map(func(e: Dictionary) -> String: return e.path)
	_count.text = "%d patch%s" % [_items.size(), "" if _items.size() == 1 else "es"]
	for k in _facets:
		_fill_facet(k, r.counts[k], String(f[k]))
	_limit = PAGE
	_fill_list()
	_filling = false


func _fill_facet(facet: String, counts: Dictionary, chosen: String) -> void:
	var ob: OptionButton = _facets[facet]
	ob.clear()
	var total := 0
	for v in counts:
		total += int(counts[v])
	ob.add_item("any %s" % FACET_LABELS[facet].to_lower())
	ob.set_item_metadata(0, "")
	var values: Array = counts.keys()
	if facet == "category":
		values.sort_custom(func(a: String, b: String) -> bool: return AKPatch.CATEGORIES.find(a) < AKPatch.CATEGORIES.find(b))
	else:
		values.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	if chosen != "" and not values.has(chosen):
		values.append(chosen)
	for v: String in values:
		if v == "":
			continue
		ob.add_item("%s (%d)" % [v, int(counts.get(v, 0))])
		ob.set_item_metadata(ob.item_count - 1, v)
		if v == chosen:
			ob.select(ob.item_count - 1)
	if chosen == "":
		ob.select(0)


func _fill_list() -> void:
	_list.clear()
	var n := mini(_limit, _items.size())
	for i in n:
		var e: Dictionary = _items[i]
		var i2 := _list.add_item(_row_text(e))
		_list.set_item_tooltip(i2, "%s\n%s · %s%s" % [e.path, e.source, e.bank, (" · " + e.creator) if e.creator != "" else ""])
		if e.id == _selected:
			_list.select(i2)
	_more.visible = _items.size() > n
	_more.text = "More (%d left)" % (_items.size() - n)


func _row_text(e: Dictionary) -> String:
	var stars := "★".repeat(int(e.rating)) + " " if int(e.rating) > 0 else ""
	var fav := "♥ " if e.favourite else ""
	var unsure: bool = e.category_from == "" or (e.category_from == "analysis" and float(e.category_conf) < AKPatchLibrary.CONFIDENT)
	var cat: String = e.category + ("?" if unsure and not e.has("user_category") else "")
	return "%s%s%s   ·  %s" % [fav, stars, e.name, cat]


# ------------------------------------------------------------------ the selected patch

func _show_detail(e: Dictionary) -> void:
	_selected = e.id
	_detail.visible = true
	_d_title.text = e.name
	var bits := PackedStringArray([e.source, e.bank])
	if e.creator != "":
		bits.append("by " + e.creator)
	if e.emulates_maker != "":
		bits.append("emulates %s %s%s" % [e.emulates_maker, e.emulates_model, " (from its name)" if e.emulates_from == "name" else ""])
	var how := {source = "the source's folder", name = "its name", bank = "its bank", patch = "the patch",
		analysis = "analysis, %d%% sure" % roundi(float(e.category_conf) * 100.0)}
	how[""] = "not known"
	bits.append("%s (%s)" % [e.category, "yours" if e.has("user_category") else how.get(e.category_from, e.category_from)])
	if e.also_in.size() > 0:
		bits.append("also in " + ", ".join(e.also_in))
	_d_info.text = "\n".join(bits)
	for i in 5:
		_stars[i].text = "★" if i < int(e.rating) else "☆"
	_fav_btn.text = "♥" if e.favourite else "♡"
	_hide_btn.text = "Unhide" if e.hidden else "Hide"
	_d_cat.select(0 if not e.has("user_category") else AKPatch.CATEGORIES.find(e.user_category) + 1)
	_d_cat.set_item_text(0, "library: %s" % e._category)
	_d_tags.text = ", ".join(e.user_tags)


func _selected_entry() -> Dictionary:
	return library.get_entry(_selected)


## Rate the selected patch (clicking its current rating clears it).
func rate_selected(stars: int) -> void:
	var e := _selected_entry()
	if e.is_empty():
		return
	library.set_rating(e.id, 0 if int(e.rating) == stars else stars)
	_after_edit(e)


func _after_edit(e: Dictionary) -> void:
	_show_detail(e)
	var i := _items.find(e)
	if i >= 0 and i < _list.item_count:
		_list.set_item_text(i, _row_text(e))


## Copy the selected library patch into the project (copy_dir), with its category and where it came
## from; returns the new path ("" when there's nothing to copy).
func copy_selected() -> String:
	var e := _selected_entry()
	if e.is_empty():
		return ""
	var src: AKPatch = ResourceLoader.load(e.path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if src == null:
		return ""
	var p: AKPatch = src.duplicate(true)
	p.category = e.category if AKPatch.CATEGORIES.has(e.category) else ""
	var info := AKPatch.library_info(p)
	info.merge({source = e.source, derived_from = e.id, bank = e.bank, creator = e.creator,
		emulates_maker = e.emulates_maker, emulates_model = e.emulates_model, emulates_from = e.emulates_from}, true)
	p.set_meta(AKPatch.LIBRARY_META, info)
	var base := String(e.name).validate_filename()
	var path := copy_dir.path_join(base + ".tres")
	var k := 2
	while FileAccess.file_exists(path):
		path = copy_dir.path_join("%s %d.tres" % [base, k])
		k += 1
	p.resource_name = path.get_file().get_basename()
	DirAccess.make_dir_recursive_absolute(copy_dir)
	if ResourceSaver.save(p, path) != OK:
		return ""
	AKPatch.ensure_library_id(path)
	AK.refresh_editor_files()
	refresh()
	copied.emit(path)
	return path


# ------------------------------------------------------------------ library folders

func _show_folders() -> void:
	_folders_list.clear()
	for r in AKPatchLibrary.editor_roots():
		_folders_list.add_item(r)
	_folders_dialog.popup_centered(AKUiScale.px(520, 300))


func _set_roots(r: PackedStringArray) -> void:
	AKPatchLibrary.set_editor_roots(r)
	_show_folders()
	refresh()


## Rebuild each library folder's index with tools/patch_library/index.py (needs Python; the
## script is in the kit's repository, not the addon).
func rebuild_indexes() -> String:
	var script := ProjectSettings.globalize_path("res://tools/patch_library/index.py")
	if not FileAccess.file_exists(script):
		return "tools/patch_library/index.py isn't in this project"
	var said := PackedStringArray()
	for r in library.roots:
		var out := []
		var code := OS.execute("python", [script, "--library", r], out, true)
		said.append("%s: %s" % [r, "rebuilt" if code == 0 else "failed (%d)" % code])
	refresh()
	return "\n".join(said)


# ------------------------------------------------------------------ building

func _build() -> void:
	var row := HBoxContainer.new()
	add_child(row)
	_search = LineEdit.new()
	_search.placeholder_text = "Search name, bank, creator, tags"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t: String) -> void: _debounce.start())
	row.add_child(_search)
	_sort = OptionButton.new()
	for s in SORT_LABELS:
		_sort.add_item(s)
	_sort.tooltip_text = "Sort"
	_sort.item_selected.connect(func(i: int) -> void:
		if SORTS[i] == "random":
			_seed += 1
		_fill())
	row.add_child(_sort)
	_debounce = Timer.new()
	_debounce.one_shot = true
	_debounce.wait_time = 0.15
	_debounce.timeout.connect(_fill)
	add_child(_debounce)

	var bar := HBoxContainer.new()
	add_child(bar)
	var toggle := Button.new()
	toggle.text = "Filters"
	toggle.toggle_mode = true
	toggle.toggled.connect(func(on: bool) -> void: _filters_box.visible = on)
	bar.add_child(toggle)
	_count = Label.new()
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_count)
	var clear := Button.new()
	clear.text = "Clear"
	clear.tooltip_text = "Clear the search and every filter"
	clear.pressed.connect(func() -> void:
		_search.text = ""
		for k in _facets:
			(_facets[k] as OptionButton).select(0)
		_min_rating.select(0)
		_favs.button_pressed = false
		_confident.button_pressed = false
		_hidden.button_pressed = false
		_fill())
	bar.add_child(clear)

	_filters_box = GridContainer.new()
	_filters_box.columns = 2
	_filters_box.visible = false
	add_child(_filters_box)
	for k in AKPatchLibrary.FACETS:
		var l := Label.new()
		l.text = FACET_LABELS[k]
		_filters_box.add_child(l)
		var ob := OptionButton.new()
		ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ob.fit_to_longest_item = false
		ob.clip_text = true
		ob.add_item("any")
		ob.set_item_metadata(0, "")
		ob.item_selected.connect(func(_i: int) -> void: _fill())
		_filters_box.add_child(ob)
		_facets[k] = ob
	var lr := Label.new()
	lr.text = "Stars"
	_filters_box.add_child(lr)
	_min_rating = OptionButton.new()
	for s in ["any", "★ or more", "★★ or more", "★★★ or more", "★★★★ or more", "★★★★★"]:
		_min_rating.add_item(s)
	_min_rating.item_selected.connect(func(_i: int) -> void: _fill())
	_filters_box.add_child(_min_rating)
	_favs = _check("Favourites")
	_confident = _check("Sure category")
	_confident.tooltip_text = "Hide patches whose category is a guess"
	_hidden = _check("Show hidden")

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size = AKUiScale.px(0, 220)
	_list.item_selected.connect(func(i: int) -> void:
		_show_detail(_items[i])
		patch_selected.emit(_items[i].path))
	_list.item_activated.connect(func(i: int) -> void:
		patch_selected.emit(_items[i].path)
		patch_activated.emit(_items[i].path))
	add_child(_list)
	_more = Button.new()
	_more.visible = false
	_more.pressed.connect(func() -> void:
		_limit += PAGE
		_fill_list())
	add_child(_more)

	_detail = VBoxContainer.new()
	_detail.visible = false
	add_child(_detail)
	_d_title = Label.new()
	_d_title.add_theme_font_size_override(&"font_size", roundi(15 * AKUiScale.factor()))
	_d_title.clip_text = true
	_detail.add_child(_d_title)
	_d_info = Label.new()
	_d_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_info.modulate = Color(1, 1, 1, 0.75)
	_detail.add_child(_d_info)
	var srow := HBoxContainer.new()
	_detail.add_child(srow)
	for i in 5:
		var b := Button.new()
		b.text = "☆"
		b.flat = true
		b.tooltip_text = "%d star%s (click again to clear)" % [i + 1, "" if i == 0 else "s"]
		var n := i + 1
		b.pressed.connect(func() -> void: rate_selected(n))
		srow.add_child(b)
		_stars.append(b)
	_fav_btn = Button.new()
	_fav_btn.flat = true
	_fav_btn.text = "♡"
	_fav_btn.tooltip_text = "Favourite"
	_fav_btn.pressed.connect(func() -> void:
		var e := _selected_entry()
		if not e.is_empty():
			library.set_favourite(e.id, not e.favourite)
			_after_edit(e))
	srow.add_child(_fav_btn)
	_hide_btn = Button.new()
	_hide_btn.flat = true
	_hide_btn.text = "Hide"
	_hide_btn.pressed.connect(func() -> void:
		var e := _selected_entry()
		if not e.is_empty():
			library.set_hidden(e.id, not e.hidden)
			_after_edit(e))
	srow.add_child(_hide_btn)
	var crow := HBoxContainer.new()
	_detail.add_child(crow)
	_d_cat = OptionButton.new()
	_d_cat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_d_cat.tooltip_text = "Your category for this patch"
	_d_cat.add_item("library")
	for c in AKPatch.CATEGORIES:
		_d_cat.add_item(c)
	_d_cat.item_selected.connect(func(i: int) -> void:
		var e := _selected_entry()
		if not e.is_empty():
			library.set_category(e.id, "" if i == 0 else AKPatch.CATEGORIES[i - 1])
			_after_edit(e))
	crow.add_child(_d_cat)
	var use := Button.new()
	use.text = "Use in project"
	use.tooltip_text = "Copy this patch into your patch folder, with its category and where it came from"
	use.pressed.connect(func() -> void: copy_selected())
	crow.add_child(use)
	_d_tags = LineEdit.new()
	_d_tags.placeholder_text = "Your tags, comma separated"
	_d_tags.text_submitted.connect(func(t: String) -> void:
		var e := _selected_entry()
		if not e.is_empty():
			library.set_tags(e.id, t.split(","))
			_after_edit(e))
	_detail.add_child(_d_tags)

	var frow := HBoxContainer.new()
	add_child(frow)
	var folders := Button.new()
	folders.text = "Library folders…"
	folders.tooltip_text = "Folders of converted patches (each with a gak_library.json)"
	folders.pressed.connect(_show_folders)
	frow.add_child(folders)
	_problems = Label.new()
	_problems.visible = false
	_problems.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_problems.modulate = Color(1, 0.75, 0.5)
	add_child(_problems)

	_folders_dialog = AcceptDialog.new()
	_folders_dialog.title = "Library folders"
	var fv := VBoxContainer.new()
	_folders_dialog.add_child(fv)
	_folders_list = ItemList.new()
	_folders_list.custom_minimum_size = AKUiScale.px(480, 160)
	fv.add_child(_folders_list)
	var fb := HBoxContainer.new()
	fv.add_child(fb)
	var add := Button.new()
	add.text = "Add…"
	add.pressed.connect(func() -> void: _dir_dialog.popup_centered_ratio(0.6))
	fb.add_child(add)
	var rem := Button.new()
	rem.text = "Remove"
	rem.pressed.connect(func() -> void:
		var sel := _folders_list.get_selected_items()
		if sel.is_empty():
			return
		var r := AKPatchLibrary.editor_roots()
		r.remove_at(sel[0])
		_set_roots(r))
	fb.add_child(rem)
	var rebuild := Button.new()
	rebuild.text = "Rebuild indexes"
	rebuild.tooltip_text = "Run tools/patch_library/index.py on each folder (needs Python)"
	rebuild.pressed.connect(func() -> void:
		_problems.text = rebuild_indexes()
		_problems.visible = true)
	fb.add_child(rebuild)
	add_child(_folders_dialog)
	_dir_dialog = FileDialog.new()
	_dir_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dir_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_dir_dialog.title = "Add a library folder"
	_dir_dialog.dir_selected.connect(func(d: String) -> void:
		var r := AKPatchLibrary.editor_roots()
		if not r.has(d):
			r.append(d)
		_set_roots(r))
	add_child(_dir_dialog)


func _check(text: String) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.toggled.connect(func(_on: bool) -> void: _fill())
	_filters_box.add_child(c)
	return c
