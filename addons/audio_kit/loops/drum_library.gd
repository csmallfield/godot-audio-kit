# SPDX-License-Identifier: Apache-2.0
## The drum library: every drum sound and kit in your drum library folders (each with a
## gak_drums.json written by tools/drum_prep/index_drums.py), with your stars, favourites, hidden
## flags and tags from a user file that is never part of a kit or sound. Kits and sounds play
## straight from the library folder; copy_kit / copy_sound put them into the project to ship.
##
##   var lib := AKDrumLibrary.new()
##   lib.roots = PackedStringArray(["D:/12_library/gak/processed_drums"])
##   lib.load_all()
##   var kits := lib.filter({type = "kit", machine = "Roland TR-909"})
##   var kit := lib.kit(kits[0])                       # an AKKit reading the library's WAVs
##   var path := lib.copy_kit(kits[0], "res://audio/") # res://audio/kits/<name>.tres
##
## An entry is a Dictionary. Sounds: id, type "sound", path (absolute), name, machine, collection,
## folder, category, kind, sure, how, tags, seconds, channels, rate, note, layer. Kits: id, type
## "kit", path, name, machine, collection, from (folder, assembled, percussion, all), folder,
## pieces, sure_share, layered. Both get rating, favourite, hidden, user_tags from the user file.
@tool
class_name AKDrumLibrary
extends RefCounted

## The editor setting holding the drum library folders.
const ROOTS_SETTING := "audio_kit/drum_library/roots"
## Filter keys that pick one value of an entry's field.
const FACETS := ["category", "kind", "machine", "from", "tag"]
const CATEGORIES := ["kick", "snare", "rim", "clap", "hat", "cymbal", "tom", "perc", "fx", "vox", "loop", "tonal"]
const USER_VERSION := 1
## Where copy_* put things, under the project folder given.
const KITS_SUBDIR := "kits"
const SAMPLES_SUBDIR := "samples/drums"
## The meta key on a copied kit or sample: where in the library it came from.
const LIBRARY_META := &"drum_library"

var roots := PackedStringArray()
## Where ratings and the rest are kept; empty means the editor's data folder (or user://).
var user_path := ""
## Where parsed indexes are cached; empty means the editor's cache folder (or user://).
var cache_dir := ""
var entries: Array = []
var problems := PackedStringArray()

var _by_id := {}
var _user := {}


static func editor_roots() -> PackedStringArray:
	if not Engine.is_editor_hint() or not Engine.has_singleton(&"EditorInterface"):
		return PackedStringArray()
	var es: Object = Engine.get_singleton(&"EditorInterface").call(&"get_editor_settings")
	if es == null or not es.call(&"has_setting", ROOTS_SETTING):
		return PackedStringArray()
	return PackedStringArray(es.call(&"get_setting", ROOTS_SETTING))


static func set_editor_roots(r: PackedStringArray) -> void:
	if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		var es: Object = Engine.get_singleton(&"EditorInterface").call(&"get_editor_settings")
		if es:
			es.call(&"set_setting", ROOTS_SETTING, r)


## Load every drum library folder's index and the user file.
func load_all() -> void:
	entries.clear()
	_by_id.clear()
	problems.clear()
	for r in roots:
		_load_root(r)
	load_user()


func get_entry(id: String) -> Dictionary:
	return _by_id.get(id, {})


# ------------------------------------------------------------------ filtering

## Entries matching a filter. Keys (all optional): type ("kit", "sound" or "" for both), query
## (words in the name, machine, folder, category, kind and tags), category, kind, machine, from
## (a kit's source), tag (a descriptive word), sure (sounds with a sure category only),
## favourites, min_rating, show_hidden, sort ("name", "rating", "machine", "random"), seed.
func filter(f: Dictionary) -> Array:
	return query(f).items


## As filter(), with the counts per value of each facet that the other filters leave:
## {items, counts: {facet: {value: n}}}.
func query(f: Dictionary) -> Dictionary:
	var type := String(f.get("type", ""))
	var words := String(f.get("query", "")).strip_edges().to_lower().split(" ", false)
	var want := {}
	for k in FACETS:
		var v := String(f.get(k, ""))
		if v != "" and v != "all":
			want[k] = v
	var sure := bool(f.get("sure", false))
	var favs := bool(f.get("favourites", false))
	var min_rating := int(f.get("min_rating", 0))
	var hidden := bool(f.get("show_hidden", false))
	var counts := {}
	for k in FACETS:
		counts[k] = {}
	var items := []
	for e: Dictionary in entries:
		if type != "" and e.type != type:
			continue
		if not hidden and e.hidden:
			continue
		if favs and not e.favourite:
			continue
		if min_rating > 0 and int(e.rating) < min_rating:
			continue
		if sure and e.type == "sound" and not e.sure:
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
		var failed := ""
		var fails := 0
		for k in want:
			if not _has(e, k, want[k]):
				fails += 1
				failed = k
				if fails > 1:
					break
		if fails == 0:
			items.append(e)
			for k in FACETS:
				_count(counts[k], e, k)
		elif fails == 1:
			_count(counts[failed], e, failed)
	_sort(items, String(f.get("sort", "name")), int(f.get("seed", 0)))
	return {items = items, counts = counts}


static func _has(e: Dictionary, k: String, v: String) -> bool:
	if k == "tag":
		return (e.tags as PackedStringArray).has(v) or (e.user_tags as PackedStringArray).has(v)
	return String(e.get(k, "")) == v


static func _count(c: Dictionary, e: Dictionary, k: String) -> void:
	if k == "tag":
		for t in e.tags:
			c[t] = c.get(t, 0) + 1
		return
	var v := String(e.get(k, ""))
	if v != "":
		c[v] = c.get(v, 0) + 1


func _sort(items: Array, how: String, seed_value: int) -> void:
	match how:
		"rating":
			items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return a.rating > b.rating or (a.rating == b.rating and a._key < b._key))
		"machine":
			items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return a._mkey < b._mkey)
		"random":
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			for i in range(items.size() - 1, 0, -1):
				var j := rng.randi_range(0, i)
				var t: Variant = items[i]
				items[i] = items[j]
				items[j] = t
		_:
			items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a._key < b._key)


# ------------------------------------------------------------------ playing and copying

## The kit for a kit entry, reading the library's WAVs (null when it won't load).
func kit(e: Dictionary) -> AKKit:
	if e.get("type", "") != "kit":
		return null
	var k := AKKit.load_json(String(e.path))
	if k:
		k.set_meta(LIBRARY_META, _origin(e))
	return k


## A sample of a sound entry, reading the library's WAV.
func sample(e: Dictionary) -> AKSample:
	if e.get("type", "") != "sound":
		return null
	var s := AKSample.new()
	s.source = String(e.path)
	s.resource_name = String(e.name)
	return s


## Copy a sound into the project: its WAV to <project_dir>/samples/drums/<machine>/ and an
## AKSample beside it (<name>.sample.tres) holding the decoded sound, so an exported game plays it.
## Returns the sample's path ("" on failure); a sound copied before is reused.
func copy_sound(e: Dictionary, project_dir := "res://audio/") -> String:
	if e.get("type", "") != "sound":
		return ""
	var dir := project_dir.path_join(SAMPLES_SUBDIR).path_join(String(e.machine).validate_filename())
	return _copy_wav(String(e.path), dir, _origin(e))


## Copy a kit into the project: each WAV it plays as copy_sound does (one folder per machine),
## and the kit as <project_dir>/kits/<name>.tres pointing at those samples. Returns the kit's
## path ("" on failure); a kit copied before is reused.
func copy_kit(e: Dictionary, project_dir := "res://audio/") -> String:
	if e.get("type", "") != "kit":
		return ""
	var text := FileAccess.get_file_as_string(String(e.path))
	var d: Variant = JSON.parse_string(text) if text != "" else null
	if not d is Dictionary:
		return ""
	var root := String(e.path).get_base_dir().path_join(String(d.get("root", "."))).simplify_path()
	var kits_dir := project_dir.path_join(KITS_SUBDIR)
	var out := kits_dir.path_join(String(e.name).validate_filename() + ".tres")
	if ResourceLoader.exists(out):
		var old := load(out)
		if old and old.has_meta(LIBRARY_META) and String(old.get_meta(LIBRARY_META).get("id", "")) == String(e.id):
			return out
		var n := 2
		while ResourceLoader.exists(out):
			out = kits_dir.path_join("%s %d.tres" % [String(e.name).validate_filename(), n])
			n += 1
	var k := AKKit.new()
	k.resource_name = String(e.name)
	k.category = String(e.machine)
	for p: Dictionary in d.get("pieces", []):
		var q := p.duplicate(true)
		if q.has("sound"):
			q["sound"] = _copy_piece_sound(root, String(q["sound"]), project_dir, e)
			if q["sound"] == "":
				return ""
		if q.has("layers"):
			for l: Dictionary in q["layers"]:
				var t: Variant = l.get("sound")
				if t is Array:
					var arr := []
					for x: Variant in t:
						arr.append(_copy_piece_sound(root, String(x), project_dir, e))
					l["sound"] = arr
				else:
					l["sound"] = _copy_piece_sound(root, String(t), project_dir, e)
		k.pieces.append(q)
	k.set_meta(LIBRARY_META, _origin(e))
	DirAccess.make_dir_recursive_absolute(kits_dir)
	if ResourceSaver.save(k, out) != OK:
		return ""
	return out


func _copy_piece_sound(root: String, rel: String, project_dir: String, e: Dictionary) -> String:
	var machine_dir := rel.split("/")[0] if rel.contains("/") else String(e.machine)
	var dir := project_dir.path_join(SAMPLES_SUBDIR).path_join(machine_dir.validate_filename())
	var origin := _origin(e)
	origin["sound"] = rel
	return _copy_wav(root.path_join(rel), dir, origin)


func _copy_wav(src: String, dir: String, origin: Dictionary) -> String:
	if not FileAccess.file_exists(src):
		problems.append("missing %s" % src)
		return ""
	DirAccess.make_dir_recursive_absolute(dir)
	var base := src.get_file().get_basename().validate_filename()
	var wav := dir.path_join(base + ".wav")
	var res := dir.path_join(base + ".sample.tres")
	if ResourceLoader.exists(res):
		var old := load(res) as AKSample
		if old and old.has_meta(LIBRARY_META) and String(old.get_meta(LIBRARY_META).get("from", "")) == src:
			return res
		var n := 2
		while FileAccess.file_exists(wav) or ResourceLoader.exists(res):
			wav = dir.path_join("%s %d.wav" % [base, n])
			res = dir.path_join("%s %d.sample.tres" % [base, n])
			n += 1
	if DirAccess.copy_absolute(src, ProjectSettings.globalize_path(wav)) != OK:
		problems.append("couldn't copy %s" % src)
		return ""
	var s := AKSample.new()
	s.source = wav
	s.resource_name = base
	if s.import_source(true) != "":
		problems.append("couldn't read %s" % src)
		return ""
	var o := origin.duplicate()
	o["from"] = src
	s.set_meta(LIBRARY_META, o)
	if ResourceSaver.save(s, res) != OK:
		return ""
	return res


static func _origin(e: Dictionary) -> Dictionary:
	return {id = String(e.id), machine = String(e.machine), collection = String(e.collection)}


# ------------------------------------------------------------------ the user file

func set_rating(id: String, stars: int) -> void:
	_user_set(id, "rating", clampi(stars, 0, 5))


func set_favourite(id: String, on: bool) -> void:
	_user_set(id, "favourite", on)


func set_hidden(id: String, on: bool) -> void:
	_user_set(id, "hidden", on)


func set_tags(id: String, tags: PackedStringArray) -> void:
	var clean := PackedStringArray()
	for t in tags:
		var s := t.strip_edges().to_lower()
		if s != "" and not clean.has(s):
			clean.append(s)
	_user_set(id, "user_tags", Array(clean))


func user_file() -> String:
	if user_path != "":
		return user_path
	if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		var paths: Object = Engine.get_singleton(&"EditorInterface").call(&"get_editor_paths")
		if paths:
			return String(paths.call(&"get_data_dir")).path_join("audio_kit/drum_library_user.json")
	return "user://audio_kit/drum_library_user.json"


func load_user() -> void:
	_user = {}
	var path := user_file()
	if FileAccess.file_exists(path):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary and (data as Dictionary).get("entries") is Dictionary:
			_user = data.entries
		else:
			problems.append("Couldn't read %s" % path)
	for e in entries:
		_apply_user(e)


func save_user() -> bool:
	var path := user_file()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({version = USER_VERSION, entries = _user}, " ", true))
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
	e._hay = (" ".join([e.name, e.machine, e.get("folder", ""), e.get("category", ""), e.get("kind", ""),
		e.get("from", ""), " ".join(e.tags), " ".join(e.user_tags)])).to_lower()


# ------------------------------------------------------------------ loading

func _cache_file(index: String) -> String:
	var dir := cache_dir
	if dir == "":
		dir = "user://audio_kit/drum_library_cache"
		if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
			var paths: Object = Engine.get_singleton(&"EditorInterface").call(&"get_editor_paths")
			if paths:
				dir = String(paths.call(&"get_cache_dir")).path_join("audio_kit_drum_library")
	return dir.path_join(index.md5_text() + ".bin")


func _load_root(root: String) -> void:
	var index := root.path_join("gak_drums.json")
	if not FileAccess.file_exists(index):
		problems.append("No index in %s (run tools/drum_prep/index_drums.py)" % root)
		return
	var stamp := "%d:%d" % [FileAccess.get_modified_time(index), FileAccess.get_size(index)]
	var cache := _cache_file(index)
	var data: Variant = null
	if FileAccess.file_exists(cache):
		var cf := FileAccess.open(cache, FileAccess.READ)
		if cf:
			var c: Variant = cf.get_var()
			if c is Dictionary and c.get("stamp", "") == stamp:
				data = c.get("data")
	if not data is Dictionary:
		data = JSON.parse_string(FileAccess.get_file_as_string(index))
		if not data is Dictionary or not (data as Dictionary).get("sounds") is Array:
			problems.append("Couldn't read %s" % index)
			return
		DirAccess.make_dir_recursive_absolute(cache.get_base_dir())
		var cw := FileAccess.open(cache, FileAccess.WRITE)
		if cw:
			cw.store_var({stamp = stamp, data = data})
	for e: Dictionary in data.get("kits", []):
		e.type = "kit"
		e.tags = PackedStringArray([String(e.from) + " kit"] + (["layered"] if int(e.get("layered", 0)) > 0 else []))
		_add(root, e)
	for e: Dictionary in data.sounds:
		e.type = "sound"
		e.tags = PackedStringArray(e.get("tags", []))
		_add(root, e)


func _add(root: String, e: Dictionary) -> void:
	if _by_id.has(e.id):
		return
	e.path = root.path_join(String(e.path))
	for k in ["name", "machine", "collection", "folder", "category", "kind", "from", "note", "how", "layer"]:
		e[k] = String(e[k]) if e.has(k) and e[k] != null else ""
	e._key = String(e.name).to_lower() + "\t" + String(e.id)
	e._mkey = String(e.machine).to_lower() + "\t" + String(e.folder).to_lower() + "\t" + e._key
	e.rating = 0
	e.favourite = false
	e.hidden = false
	e.user_tags = PackedStringArray()
	e._hay = ""
	_by_id[e.id] = e
	entries.append(e)
