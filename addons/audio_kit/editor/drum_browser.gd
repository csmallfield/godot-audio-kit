# SPDX-License-Identifier: Apache-2.0
## The Loops page's drum library browser: every kit and drum sound in your drum library folders,
## with a search, filters that show how many each choice leaves (category, kind, machine, kit
## type, descriptive words), sorting, and your stars, favourites, hidden flags and tags. A click
## auditions (a sound plays; a kit plays a short beat); a double-click (or Enter) uses it: the tab
## copies it into the project and makes it the loop's instrument.
@tool
class_name AKDrumBrowser
extends VBoxContainer

## Play this buffer (the tab owns the player).
signal audition(buf: AKBuffer)
## A kit or sound was double-clicked; `entry` is its library entry.
signal activated(entry: Dictionary)
## A kit or sound was copied into the project (its new path).
signal copied(path: String)

const PAGE := 300
const SORTS := ["name", "machine", "rating", "random"]
const SORT_LABELS := ["A-Z", "Machine", "Stars", "Shuffle"]
const FACET_LABELS := {category = "Category", kind = "Kind", machine = "Machine", from = "Kit type", tag = "Sounds"}
const TYPES := ["kit", "sound"]

var library := AKDrumLibrary.new()
## Drum library folders; empty reads them from the editor settings.
var roots := PackedStringArray()
## The project folder "Use in project" copies into (kits/ and samples/drums/ under it).
var project_dir := "res://audio/"

var _type: OptionButton
var _search: LineEdit
var _sort: OptionButton
var _count: Label
var _filters_box: GridContainer
var _facets := {}
var _facet_labels := {}
## The facets each view shows.
const VIEW_FACETS := {kit = ["machine", "from"], sound = ["category", "kind", "machine", "tag"]}
var _sure: CheckBox
var _favs: CheckBox
var _hidden: CheckBox
var _list: ItemList
var _more: Button
var _detail: VBoxContainer
var _d_title: Label
var _d_info: Label
var _stars: Array[Button] = []
var _fav_btn: Button
var _hide_btn: Button
var _d_tags: LineEdit
var _problems: Label
var _folders_dialog: AcceptDialog
var _folders_list: ItemList
var _dir_dialog: FileDialog
var _debounce: Timer

var _items: Array = []
var _limit := PAGE
var _selected := ""
var _seed := 1
var _filling := false
var _loaded := false
var _kits := {}          # kit id -> AKKit (library kits made once)


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = AKUiScale.px(190, 0)
	_build()
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree() and not _loaded:
			refresh())


## Read the library folders' indexes and the user file (the first time the tab shows, or after
## the folders change).
func refresh() -> void:
	_loaded = true
	library.roots = roots if not roots.is_empty() else AKDrumLibrary.editor_roots()
	library.load_all()
	_kits.clear()
	var said := library.problems.duplicate()
	if library.roots.is_empty():
		said.append("No drum library folders yet: Library folders… → Add…")
	_problems.text = "\n".join(said)
	_problems.visible = not said.is_empty()
	_fill()


## The filter the controls describe (for AKDrumLibrary.query).
func current_filter() -> Dictionary:
	var f := {type = TYPES[maxi(0, _type.selected)], query = _search.text, sort = SORTS[maxi(0, _sort.selected)],
		seed = _seed, sure = _sure.button_pressed, favourites = _favs.button_pressed, show_hidden = _hidden.button_pressed}
	for k in _facets:
		var ob: OptionButton = _facets[k]
		f[k] = String(ob.get_item_metadata(ob.selected)) if ob.selected > 0 else ""
	return f


## Show kits or sounds.
func set_type(t: String) -> void:
	_type.select(maxi(0, TYPES.find(t)))
	_fill()


func set_search(text: String) -> void:
	_search.text = text
	_fill()


func set_facet(facet: String, value: String) -> void:
	var ob: OptionButton = _facets[facet]
	var found := value == ""
	if found:
		ob.select(0)
	for i in ob.item_count:
		if String(ob.get_item_metadata(i)) == value and value != "":
			ob.select(i)
			found = true
	if not found:
		ob.add_item(value)
		ob.set_item_metadata(ob.item_count - 1, value)
		ob.select(ob.item_count - 1)
	_fill()


## The entries listed, in order.
func items() -> Array:
	return _items


## Select row `i` (auditioning it when `play`).
func select_row(i: int, play := true) -> void:
	if i < 0 or i >= _items.size():
		return
	if i >= _limit:
		_limit = i + 1
		_fill_list()
	_list.select(i)
	_show_detail(_items[i])
	if play:
		audition_entry(_items[i])


# ------------------------------------------------------------------ audition and use

## The kit of a kit entry (made once per refresh).
func kit_of(e: Dictionary) -> AKKit:
	if not _kits.has(e.id):
		_kits[e.id] = library.kit(e)
	return _kits[e.id]


## A two-bar beat on a kit: kick, snare, eighth-note hats (an open hat at the end), a crash.
static func beat_for(kit: AKKit, bpm := 100.0) -> AKBuffer:
	if kit == null or kit.piece_count() == 0:
		return null
	var loop := AKLoop.new()
	loop.kind = "percussive"
	loop.instrument = kit
	loop.bars = 2
	var t := AKLoop.TICKS_PER_BEAT
	var kick := kit.find_piece("kick")
	var snare := kit.find_piece("snare") if kit.find_piece("snare") >= 0 else kit.find_piece("clap")
	var ch := kit.find_piece("closed_hat")
	var oh := kit.find_piece("open_hat")
	if kick < 0 and snare < 0 and ch < 0:
		for i in mini(8, kit.piece_count()):   # no drum kit rows: each piece in turn
			loop.add_note(i * t, 24, i, 0.9)
	for beat in 8:
		if beat % 2 == 0 and kick >= 0:
			loop.add_note(beat * t, 24, kick, 1.0)
		if beat % 2 == 1 and snare >= 0:
			loop.add_note(beat * t, 24, snare, 0.9)
		for h in 2:
			var r := oh if beat == 7 and h == 1 and oh >= 0 else ch
			if r >= 0:
				loop.add_note(beat * t + h * t / 2, 12, r, 0.6 if h == 1 else 0.8)
	if kit.find_piece("crash") >= 0:
		loop.add_note(0, 24, kit.find_piece("crash"), 0.7)
	var song := AKSong.new()
	song.tempo = AKTempoMap.new()
	song.tempo.bpm = bpm
	song.master_fx = [{type = &"limit", ceiling_db = -1.0}]
	song.sections = [{name = "a", bars = 2, patterns = [loop.to_pattern()]}]
	return song.render(false, true).mix


## Play an entry: a sound as it is, a kit's beat.
func audition_entry(e: Dictionary) -> AKBuffer:
	var buf: AKBuffer = null
	if e.type == "kit":
		buf = beat_for(kit_of(e))
	else:
		var s := library.sample(e)
		if s:
			buf = AK.render(s.to_recipe())
	if buf:
		audition.emit(buf)
	return buf


## Copy the selected entry into the project; returns the new path ("" when nothing was copied).
func copy_selected() -> String:
	var e := library.get_entry(_selected)
	if e.is_empty():
		return ""
	var path := library.copy_kit(e, project_dir) if e.type == "kit" else library.copy_sound(e, project_dir)
	if path == "":
		_problems.text = "Couldn't copy %s\n%s" % [e.name, "\n".join(library.problems)]
		_problems.visible = true
		return ""
	AK.refresh_editor_files()
	copied.emit(path)
	return path


# ------------------------------------------------------------------ the list

func _fill() -> void:
	if _filling:
		return
	_filling = true
	var f := current_filter()
	var r := library.query(f)
	_items = r.items
	var noun: String = "kit" if f.type == "kit" else "sound"
	_count.text = "%d %s%s" % [_items.size(), noun, "" if _items.size() == 1 else "s"]
	for k in _facets:
		_fill_facet(k, r.counts[k], String(f[k]))
		var on: bool = VIEW_FACETS[f.type].has(k)
		(_facets[k] as Control).visible = on
		(_facet_labels[k] as Control).visible = on
	_sure.visible = f.type == "sound"
	_limit = PAGE
	_fill_list()
	_filling = false


func _fill_facet(facet: String, counts: Dictionary, chosen: String) -> void:
	var ob: OptionButton = _facets[facet]
	ob.clear()
	ob.add_item("any %s" % FACET_LABELS[facet].to_lower())
	ob.set_item_metadata(0, "")
	var values: Array = counts.keys()
	if facet == "category":
		values.sort_custom(func(a: String, b: String) -> bool:
			return AKDrumLibrary.CATEGORIES.find(a) < AKDrumLibrary.CATEGORIES.find(b))
	elif facet == "tag":
		values.sort_custom(func(a: String, b: String) -> bool: return int(counts[a]) > int(counts[b]))
	else:
		values.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	if chosen != "" and not values.has(chosen):
		values.append(chosen)
	for v: String in values:
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
		var row := _list.add_item(_row_text(e))
		_list.set_item_tooltip(row, "%s\n%s" % [e.path, e.machine])
		if e.id == _selected:
			_list.select(row)
	_more.visible = _items.size() > n
	_more.text = "More (%d left)" % (_items.size() - n)


static func _row_text(e: Dictionary) -> String:
	var stars := "★".repeat(int(e.rating)) + " " if int(e.rating) > 0 else ""
	var fav := "♥ " if e.favourite else ""
	if e.type == "kit":
		return "%s%s%s   ·  %d pieces, %s" % [fav, stars, e.name, int(e.pieces), e.from]
	var cat: String = e.category if e.category != "" else "?"
	if e.category != "" and not e.sure:
		cat += "?"
	if e.kind != "":
		cat += " " + e.kind
	return "%s%s%s   ·  %s  ·  %s" % [fav, stars, e.name, cat, e.machine]


func _show_detail(e: Dictionary) -> void:
	_selected = e.id
	_detail.visible = true
	_d_title.text = e.name
	var bits := PackedStringArray([e.machine])
	if e.type == "kit":
		var how := {folder = "the machine's own kit folder", assembled = "put together from the machine's sounds",
			percussion = "the machine's percussion", all = "every sound of the machine"}
		bits.append("%d pieces, %s%s" % [int(e.pieces), how.get(e.from, e.from),
			(": " + e.folder) if e.folder != "" else ""])
		bits.append("%d%% of the pieces have a sure category%s" % [roundi(float(e.sure_share) * 100.0),
			", %d velocity-layered" % int(e.layered) if int(e.layered) > 0 else ""])
	else:
		if e.folder != "":
			bits.append(e.folder)
		var how := {both = "name and sound agree", name = "its name", analysis = "its sound"}
		bits.append("%s%s%s (%s%s)" % [e.category if e.category != "" else "no category", " " + e.kind if e.kind != "" else "",
			"" if e.sure else "?", how.get(e.how.split(" ")[0], e.how), "" if e.sure else ", a guess"])
		var facts := PackedStringArray(["%.2f s" % float(e.seconds), "stereo" if int(e.channels) == 2 else "mono",
			"%d Hz" % int(e.rate)])
		if e.note != "":
			facts.append(e.note)
		if e.layer != "":
			facts.append("layer " + e.layer)
		bits.append(", ".join(facts))
		if not e.tags.is_empty():
			bits.append(", ".join(e.tags))
	_d_info.text = "\n".join(bits)
	for i in 5:
		_stars[i].text = "★" if i < int(e.rating) else "☆"
	_fav_btn.text = "♥" if e.favourite else "♡"
	_hide_btn.text = "Unhide" if e.hidden else "Hide"
	_d_tags.text = ", ".join(e.user_tags)


func _after_edit(e: Dictionary) -> void:
	_show_detail(e)
	var i := _items.find(e)
	if i >= 0 and i < _list.item_count:
		_list.set_item_text(i, _row_text(e))


## Rate the selected entry (clicking its current rating clears it).
func rate_selected(stars: int) -> void:
	var e := library.get_entry(_selected)
	if e.is_empty():
		return
	library.set_rating(e.id, 0 if int(e.rating) == stars else stars)
	_after_edit(e)


# ------------------------------------------------------------------ library folders

func _show_folders() -> void:
	_folders_list.clear()
	for r in AKDrumLibrary.editor_roots():
		_folders_list.add_item(r)
	_folders_dialog.popup_centered(AKUiScale.px(520, 300))


func _set_roots(r: PackedStringArray) -> void:
	AKDrumLibrary.set_editor_roots(r)
	_show_folders()
	refresh()


# ------------------------------------------------------------------ building

func _build() -> void:
	var row := HBoxContainer.new()
	add_child(row)
	_type = OptionButton.new()
	_type.add_item("Kits")
	_type.add_item("Sounds")
	_type.item_selected.connect(func(_i: int) -> void:
		for k in _facets:          # a filter of the other view doesn't carry over
			if not VIEW_FACETS[TYPES[_type.selected]].has(k):
				(_facets[k] as OptionButton).select(0)
		_fill())
	row.add_child(_type)
	_search = LineEdit.new()
	_search.placeholder_text = "Search name, machine, tags"
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
	_debounce.wait_time = 0.2
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
		_sure.button_pressed = false
		_favs.button_pressed = false
		_hidden.button_pressed = false
		_fill())
	bar.add_child(clear)

	_filters_box = GridContainer.new()
	_filters_box.columns = 2
	_filters_box.visible = false
	add_child(_filters_box)
	for k in AKDrumLibrary.FACETS:
		var l := Label.new()
		l.text = FACET_LABELS[k]
		_filters_box.add_child(l)
		_facet_labels[k] = l
		var ob := OptionButton.new()
		ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ob.fit_to_longest_item = false
		ob.clip_text = true
		ob.add_item("any")
		ob.set_item_metadata(0, "")
		ob.item_selected.connect(func(_i: int) -> void: _fill())
		_filters_box.add_child(ob)
		_facets[k] = ob
	_sure = _check("Sure category")
	_sure.tooltip_text = "Hide sounds whose category is a guess"
	_favs = _check("Favourites")
	_hidden = _check("Show hidden")

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size = AKUiScale.px(0, 220)
	_list.item_selected.connect(func(i: int) -> void:
		_show_detail(_items[i])
		audition_entry(_items[i]))
	_list.item_activated.connect(func(i: int) -> void: activated.emit(_items[i]))
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
		var e := library.get_entry(_selected)
		if not e.is_empty():
			library.set_favourite(e.id, not e.favourite)
			_after_edit(e))
	srow.add_child(_fav_btn)
	_hide_btn = Button.new()
	_hide_btn.flat = true
	_hide_btn.text = "Hide"
	_hide_btn.pressed.connect(func() -> void:
		var e := library.get_entry(_selected)
		if not e.is_empty():
			library.set_hidden(e.id, not e.hidden)
			_after_edit(e))
	srow.add_child(_hide_btn)
	var arow := HBoxContainer.new()
	_detail.add_child(arow)
	var play := Button.new()
	play.text = "Play"
	play.tooltip_text = "A sound as it is; a kit plays a two-bar beat"
	play.pressed.connect(func() -> void:
		var e := library.get_entry(_selected)
		if not e.is_empty():
			audition_entry(e))
	arow.add_child(play)
	var use := Button.new()
	use.text = "Use in project"
	use.tooltip_text = "Copy into the project (the WAVs to audio/samples/drums/, a kit to audio/kits/) so a game can play it"
	use.pressed.connect(func() -> void: copy_selected())
	arow.add_child(use)
	_d_tags = LineEdit.new()
	_d_tags.placeholder_text = "Your tags, comma separated"
	_d_tags.text_submitted.connect(func(t: String) -> void:
		var e := library.get_entry(_selected)
		if not e.is_empty():
			library.set_tags(e.id, t.split(","))
			_after_edit(e))
	_detail.add_child(_d_tags)

	var frow := HBoxContainer.new()
	add_child(frow)
	var folders := Button.new()
	folders.text = "Library folders…"
	folders.tooltip_text = "Drum library folders (each with a gak_drums.json)"
	folders.pressed.connect(_show_folders)
	frow.add_child(folders)
	_problems = Label.new()
	_problems.visible = false
	_problems.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_problems.modulate = Color(1, 0.75, 0.5)
	add_child(_problems)

	_folders_dialog = AcceptDialog.new()
	_folders_dialog.title = "Drum library folders"
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
		var r := AKDrumLibrary.editor_roots()
		r.remove_at(sel[0])
		_set_roots(r))
	fb.add_child(rem)
	add_child(_folders_dialog)
	_dir_dialog = FileDialog.new()
	_dir_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dir_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_dir_dialog.title = "Add a drum library folder"
	_dir_dialog.dir_selected.connect(func(d: String) -> void:
		var r := AKDrumLibrary.editor_roots()
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
