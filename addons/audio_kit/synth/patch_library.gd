# SPDX-License-Identifier: Apache-2.0
## The patch library (docs/plans/patch-library.md): every patch you can pick, from the kit, the
## starter bank, your own folder and any library folders (each with a gak_library.json written by
## tools/patch_library/index.py), with your ratings, favourites, tags and category overrides from a
## user file that is never part of a patch.
##
##   var lib := AKPatchLibrary.new()
##   lib.roots = PackedStringArray(["D:/12_library/gak/library"])
##   lib.load_all()
##   var basses := lib.filter({category = "bass", min_rating = 3, query = "acid"})
##   lib.set_rating(basses[0].id, 5)
##
## An entry is a Dictionary: id, name, path (absolute or res://), source, origin (default, ingested,
## created), engine, bank, category (yours when you set one), category_from, category_conf,
## category_alt, emulates_maker, emulates_model, emulates_from, creator, tags, also_in, spec_err_db,
## and from the user file rating, favourite, hidden, user_tags.
class_name AKPatchLibrary
extends RefCounted

## Folders inside the project listed as patches: [folder, source, origin].
const PROJECT_DIRS := [
	["res://addons/audio_kit/patches/", "kit", "default"],
	["res://addons/audio_kit/bank/patches/", "kit", "default"],
	["res://audio/patches/", "sound-lab", "created"],
]
## The editor setting holding the library folders.
const ROOTS_SETTING := "audio_kit/library/roots"
## Filter keys that pick one value of an entry's field (the facets).
const FACETS := ["category", "source", "origin", "emulates_maker", "emulates_model", "creator", "bank"]
## Below this confidence, an analysis guess counts as unsure ("confident only" hides it).
const CONFIDENT := 0.8
const USER_VERSION := 1

## Library folders (each holding gak_library.json).
var roots := PackedStringArray()
## [folder, source, origin] triples listed from the project (a copy of PROJECT_DIRS to change).
var project_dirs: Array = PROJECT_DIRS.duplicate(true)
## Where ratings and the rest are kept; empty means the editor's data folder (or user:// outside it).
var user_path := ""
## Where parsed indexes are cached; empty means the editor's cache folder (or user://).
var cache_dir := ""
## Every entry, in load order.
var entries: Array = []
## What the last load_all() found wrong (a missing index, a bad file), for the browser to show.
var problems := PackedStringArray()

var _by_id := {}
var _user := {}


## The library folders from the editor settings (empty outside the editor).
static func editor_roots() -> PackedStringArray:
	if not Engine.is_editor_hint() or not Engine.has_singleton(&"EditorInterface"):
		return PackedStringArray()
	var es: Object = Engine.get_singleton(&"EditorInterface").call(&"get_editor_settings")
	if es == null or not es.call(&"has_setting", ROOTS_SETTING):
		return PackedStringArray()
	return PackedStringArray(es.call(&"get_setting", ROOTS_SETTING))


## Store the library folders in the editor settings.
static func set_editor_roots(r: PackedStringArray) -> void:
	if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		var es: Object = Engine.get_singleton(&"EditorInterface").call(&"get_editor_settings")
		if es:
			es.call(&"set_setting", ROOTS_SETTING, r)


## Load the project's patches, every library folder's index and the user file.
func load_all() -> void:
	entries.clear()
	_by_id.clear()
	problems.clear()
	for d in project_dirs:
		_load_project_dir(String(d[0]), String(d[1]), String(d[2]))
	for r in roots:
		_load_root(r)
	# Kept in name order, so the default sort is free.
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a._key < b._key)
	load_user()


## The entry with this ID ({} when unknown).
func get_entry(id: String) -> Dictionary:
	return _by_id.get(id, {})


## The entry for a patch path ({} when unknown).
func entry_for_path(path: String) -> Dictionary:
	for e in entries:
		if e.path == path:
			return e
	return {}


# ------------------------------------------------------------------ filtering

## Entries matching a filter, sorted. Keys (all optional): query (name, bank, creator, tags),
## category, source, origin, emulates_maker, emulates_model, creator, bank (each one value; "" for
## any), tag, min_rating (0..5), favourites, confident, show_hidden, sort ("name", "rating",
## "confidence", "error", "random"), seed (for random).
func filter(f: Dictionary) -> Array:
	return query(f).items


## As filter(), with the counts per value of each facet that the other filters leave:
## {items: [...], counts: {facet: {value: n}}}.
func query(f: Dictionary) -> Dictionary:
	var q := String(f.get("query", "")).strip_edges().to_lower()
	var words := q.split(" ", false)
	var want := {}
	for k in FACETS:
		var v := String(f.get(k, ""))
		if v != "" and v != "all":
			want[k] = v
	var tag := String(f.get("tag", "")).to_lower()
	var min_rating := int(f.get("min_rating", 0))
	var favs := bool(f.get("favourites", false))
	var confident := bool(f.get("confident", false))
	var hidden := bool(f.get("show_hidden", false))
	var counts := {}
	for k in FACETS:
		counts[k] = {}
	var items := []
	for e: Dictionary in entries:
		# Filters that aren't facets must pass for the entry to count anywhere.
		if not hidden and e.hidden:
			continue
		if favs and not e.favourite:
			continue
		if min_rating > 0 and int(e.rating) < min_rating:
			continue
		if confident and float(e.category_conf) < CONFIDENT and not e.has("user_category"):
			continue
		if tag != "" and not (e.tags.has(tag) or e.user_tags.has(tag)):
			continue
		if not words.is_empty():
			var hay: String = e._hay
			var ok := true
			for w in words:
				if not hay.contains(w):
					ok = false
					break
			if not ok:
				continue
		# Facets: an entry that fails exactly one still counts for that one's menu.
		var failed := ""
		var fails := 0
		for k in want:
			if e[k] != want[k]:
				fails += 1
				failed = k
				if fails > 1:
					break
		if fails == 0:
			items.append(e)
			for k in FACETS:
				var c: Dictionary = counts[k]
				var v: String = e[k]
				c[v] = c.get(v, 0) + 1
		elif fails == 1:
			var c: Dictionary = counts[failed]
			var v: String = e[failed]
			c[v] = c.get(v, 0) + 1
	_sort(items, String(f.get("sort", "name")), int(f.get("seed", 0)))
	return {items = items, counts = counts}


func _sort(items: Array, how: String, seed_value: int) -> void:
	match how:
		"rating":
			items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return a.rating > b.rating or (a.rating == b.rating and a._key < b._key))
		"confidence":
			items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return a.category_conf > b.category_conf or (a.category_conf == b.category_conf and a._key < b._key))
		"error":
			items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var x := float(a.spec_err_db) if a.spec_err_db != null else 999.0
				var y := float(b.spec_err_db) if b.spec_err_db != null else 999.0
				return x < y or (x == y and a._key < b._key))
		"random":
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			for i in range(items.size() - 1, 0, -1):
				var j := rng.randi_range(0, i)
				var t: Variant = items[i]
				items[i] = items[j]
				items[j] = t
		_:
			pass  # entries are kept in name order


# ------------------------------------------------------------------ the user file

## Rate a patch 0..5 (0 clears the rating).
func set_rating(id: String, stars: int) -> void:
	_user_set(id, "rating", clampi(stars, 0, 5))


func set_favourite(id: String, on: bool) -> void:
	_user_set(id, "favourite", on)


func set_hidden(id: String, on: bool) -> void:
	_user_set(id, "hidden", on)


## Your category for a patch ("" goes back to the library's).
func set_category(id: String, category: String) -> void:
	_user_set(id, "user_category", category)


## Your tags for a patch (lower case, no duplicates).
func set_tags(id: String, tags: PackedStringArray) -> void:
	var clean := PackedStringArray()
	for t in tags:
		var s := t.strip_edges().to_lower()
		if s != "" and not clean.has(s):
			clean.append(s)
	_user_set(id, "user_tags", Array(clean))


## The user file's path.
func user_file() -> String:
	if user_path != "":
		return user_path
	if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		var paths: Object = Engine.get_singleton(&"EditorInterface").call(&"get_editor_paths")
		if paths:
			return String(paths.call(&"get_data_dir")).path_join("audio_kit/library_user.json")
	return "user://audio_kit/library_user.json"


## Read the user file and apply it to the entries (keys of patches not found are kept).
func load_user() -> void:
	_user = {}
	var path := user_file()
	if FileAccess.file_exists(path):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary and (data as Dictionary).get("patches") is Dictionary:
			_user = data.patches
		else:
			problems.append("Couldn't read %s" % path)
	for e in entries:
		_apply_user(e)


## Write the user file (to a temporary file, then renamed over it).
func save_user() -> bool:
	var path := user_file()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({version = USER_VERSION, patches = _user}, " ", true))
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path) == OK


func _user_set(id: String, key: String, value: Variant) -> void:
	var u: Dictionary = _user.get(id, {})
	var empty: bool = value == null or (value is bool and not value) or (value is int and value == 0) \
		or (value is String and value == "") or (value is Array and value.is_empty())
	if empty:
		u.erase(key)
	else:
		u[key] = value
	if u.is_empty():
		_user.erase(id)
	else:
		_user[id] = u
	if _by_id.has(id):
		_apply_user(_by_id[id])
	save_user()


func _apply_user(e: Dictionary) -> void:
	var u: Dictionary = _user.get(e.id, {})
	e.rating = int(u.get("rating", 0))
	e.favourite = bool(u.get("favourite", false))
	e.hidden = bool(u.get("hidden", false))
	e.user_tags = PackedStringArray(u.get("user_tags", []))
	if u.has("user_category"):
		e.user_category = String(u.user_category)
		e.category = e.user_category
	elif e.has("user_category"):
		e.erase("user_category")
		e.category = e._category
	e._hay = (String(e.name) + " " + String(e.bank) + " " + String(e.creator) + " " + " ".join(e.tags) + " " + " ".join(e.user_tags)).to_lower()


# ------------------------------------------------------------------ loading

func _add(e: Dictionary) -> void:
	for k in ["engine", "bank", "category_from", "category_alt", "emulates_maker", "emulates_model", "emulates_from", "creator",
			"source", "origin"]:
		e[k] = String(e[k]) if e.has(k) and e[k] != null else ""
	if not e.has("category_conf") or e.category_conf == null:
		e.category_conf = 0.0
	if not e.has("spec_err_db"):
		e.spec_err_db = null
	e.tags = PackedStringArray(e.get("tags", []))
	e.also_in = PackedStringArray(e.get("also_in", []))
	e._category = String(e.get("category", "other"))
	e.category = e._category
	e._key = String(e.name).to_lower() + "\t" + String(e.id)
	e.rating = 0
	e.favourite = false
	e.hidden = false
	e.user_tags = PackedStringArray()
	e._hay = ""
	if _by_id.has(e.id):
		return
	_by_id[e.id] = e
	entries.append(e)


func _load_project_dir(dir: String, source: String, origin: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	var files := Array(DirAccess.get_files_at(dir))
	files.sort()
	for f: String in files:
		f = f.trim_suffix(".remap")  # exported projects list "x.tres.remap"
		if not f.ends_with(".tres") and not f.ends_with(".res"):
			continue
		var path := dir + f
		var p := load(path) as AKPatch
		if p == null:
			continue
		var info := AKPatch.library_info(p)
		var cat := p.category if AKPatch.CATEGORIES.has(p.category) else "other"
		_add({
			id = AKPatch.library_id(path),
			name = f.get_basename(),
			path = path,
			source = String(info.get("source", source)),
			origin = origin,
			engine = "GAK",
			bank = String(info.get("bank", "kit" if origin == "default" else "yours")),
			category = cat,
			category_from = "patch" if p.category != "" else "",
			category_conf = 1.0 if p.category != "" else 0.0,
			creator = String(info.get("author", info.get("creator", ""))),
			emulates_maker = String(info.get("emulates_maker", "")),
			emulates_model = String(info.get("emulates_model", "")),
			emulates_from = String(info.get("emulates_from", "")),
			derived_from = String(info.get("derived_from", "")),
		})


func _cache_file(index: String) -> String:
	var dir := cache_dir
	if dir == "":
		dir = "user://audio_kit/library_cache"
		if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
			var paths: Object = Engine.get_singleton(&"EditorInterface").call(&"get_editor_paths")
			if paths:
				dir = String(paths.call(&"get_cache_dir")).path_join("audio_kit_library")
	return dir.path_join(index.md5_text() + ".bin")


## Load one library folder's index, from the cache when the index hasn't changed.
func _load_root(root: String) -> void:
	var index := root.path_join("gak_library.json")
	if not FileAccess.file_exists(index):
		problems.append("No index in %s (run tools/patch_library/index.py)" % root)
		return
	var stamp := "%d:%d" % [FileAccess.get_modified_time(index), FileAccess.get_size(index)]
	var cache := _cache_file(index)
	var patches: Variant = null
	if FileAccess.file_exists(cache):
		var cf := FileAccess.open(cache, FileAccess.READ)
		if cf:
			var c: Variant = cf.get_var()
			if c is Dictionary and c.get("stamp", "") == stamp:
				patches = c.get("patches")
	if not patches is Array:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(index))
		if not data is Dictionary or not (data as Dictionary).get("patches") is Array:
			problems.append("Couldn't read %s" % index)
			return
		patches = data.patches
		DirAccess.make_dir_recursive_absolute(cache.get_base_dir())
		var cw := FileAccess.open(cache, FileAccess.WRITE)
		if cw:
			cw.store_var({stamp = stamp, patches = patches})
	for e: Dictionary in patches:
		e.path = root.path_join(String(e.path))
		_add(e)
