# SPDX-License-Identifier: Apache-2.0
## The patch library (docs/plans/patch-library.md): AKPatchLibrary reads an index and the project's
## patches, filters with counts, keeps ratings in a user file; AKLibraryBrowser lists, rates and
## copies; the Synth page treats library patches as read-only.
extends RefCounted

const OUT := "user://test_library/"
const ROOT := OUT + "lib/"
const USER := OUT + "user.json"


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## A small library: three kit patches copied as library patches, and an index describing them.
func _make_library(extra := 0) -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "synth1/bank a")
	DirAccess.make_dir_recursive_absolute(ROOT + "surge/factory")
	var src := ["acid_bass", "fm_bell", "pluck"]
	var rows := [
		{id = "synth1:a/acid", name = "Acid Squelch", path = "synth1/bank a/001 Acid Squelch.tres", source = "synth1", origin = "ingested",
			engine = "Synth1", bank = "bank a", category = "bass", category_from = "name", category_conf = 0.9, category_alt = "",
			emulates_maker = "Roland", emulates_model = "TB-303", emulates_from = "name", creator = "Someone", tags = ["mono"], also_in = ["bank b"],
			spec_err_db = 4.0, caveats = 0},
		{id = "synth1:a/bell", name = "Glass Bell", path = "synth1/bank a/002 Glass Bell.tres", source = "synth1", origin = "ingested",
			engine = "Synth1", bank = "bank a", category = "other", category_from = "", category_conf = 0.0, category_alt = "",
			emulates_maker = "", emulates_model = "", emulates_from = "", creator = "Someone", tags = [], also_in = [], spec_err_db = 6.0, caveats = 1},
		{id = "surge:f/pluck", name = "Harp Pluck", path = "surge/factory/Harp Pluck.tres", source = "surge", origin = "ingested",
			engine = "Surge XT", bank = "factory", category = "pluck", category_from = "source", category_conf = 1.0, category_alt = "",
			emulates_maker = "", emulates_model = "", emulates_from = "", creator = "Claes", tags = ["chorus"], also_in = [], spec_err_db = 2.0, caveats = 0},
	]
	for i in 3:
		var p: AKPatch = (load("res://addons/audio_kit/patches/%s.tres" % src[i]) as AKPatch).duplicate(true)
		p.category = ""
		ResourceSaver.save(p, ROOT + rows[i].path)
	for i in extra:
		var r: Dictionary = rows[i % 3].duplicate()
		r.id = "synth1:x/%d" % i
		r.name = "Extra %05d %s" % [i, ["saw", "pad", "lead"][i % 3]]
		r.category = AKPatch.CATEGORIES[i % AKPatch.CATEGORIES.size()]
		r.bank = "bank %d" % (i % 50)
		rows.append(r)
	var f := FileAccess.open(ROOT + "gak_library.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({version = 1, patches = rows}))
	f.close()


func _lib() -> AKPatchLibrary:
	var lib := AKPatchLibrary.new()
	lib.roots = PackedStringArray([ROOT])
	lib.user_path = USER
	lib.cache_dir = OUT + "cache"
	lib.load_all()
	return lib


func _clean() -> void:
	for d in [ROOT + "synth1/bank a", ROOT + "surge/factory", OUT + "cache"]:
		for f in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(d.path_join(f))
	for f in DirAccess.get_files_at(ROOT):
		DirAccess.remove_absolute(ROOT + f)
	if FileAccess.file_exists(USER):
		DirAccess.remove_absolute(USER)


func test_index_filters_and_counts() -> String:
	_clean()
	_make_library()
	var lib := _lib()
	if not lib.problems.is_empty():
		return "problems: %s" % lib.problems
	if lib.get_entry("synth1:a/acid").is_empty() or not lib.entries.any(func(e: Dictionary) -> bool: return e.source == "kit"):
		return "the library should hold the index's patches and the kit's"
	var acid := lib.get_entry("synth1:a/acid")
	if not String(acid.path).begins_with(ROOT) or not FileAccess.file_exists(acid.path):
		return "an index path should resolve under its library folder: %s" % acid.path
	var r: Dictionary = lib.query({source = "synth1"})
	if r.items.size() != 2:
		return "source synth1: %d" % r.items.size()
	# The source menu counts every source the other filters leave; category counts within synth1.
	if int(r.counts.source.get("surge", 0)) != 1 or int(r.counts.category.get("bass", 0)) != 1 or r.counts.category.has("pluck"):
		return "counts: %s" % r.counts
	if lib.filter({emulates_maker = "Roland", emulates_model = "TB-303"}).size() != 1:
		return "maker and model together"
	if lib.filter({query = "someone glass"}).size() != 1:
		return "search should match name and creator words"
	if lib.filter({tag = "chorus"}).size() != 1 or lib.filter({bank = "factory"}).size() != 1:
		return "tag and bank filters"
	if lib.filter({confident = true, source = "synth1"}).size() != 1:
		return "confident only should hide the unknown category"
	var by_err := lib.filter({sort = "error", origin = "ingested"})
	if by_err.map(func(e: Dictionary) -> String: return e.name) != ["Harp Pluck", "Acid Squelch", "Glass Bell"]:
		return "sort by error: %s" % [by_err.map(func(e: Dictionary) -> String: return e.name)]
	return ""


func test_user_file_ratings_and_overrides() -> String:
	_clean()
	_make_library()
	var lib := _lib()
	lib.set_rating("synth1:a/bell", 4)
	lib.set_favourite("synth1:a/bell", true)
	lib.set_category("synth1:a/bell", "bell")
	lib.set_tags("synth1:a/bell", PackedStringArray(["Intro", " intro", "dark"]))
	lib.set_hidden("surge:f/pluck", true)
	lib.set_rating("missing:patch", 2)  # kept though no patch has it (a folder may be offline)
	if FileAccess.file_exists(USER + ".tmp"):
		return "the temporary file should be renamed over the user file"
	var lib2 := _lib()
	var e := lib2.get_entry("synth1:a/bell")
	if e.rating != 4 or not e.favourite or e.category != "bell" or Array(e.user_tags) != ["intro", "dark"]:
		return "the user file should come back: %s" % [[e.rating, e.favourite, e.category, e.user_tags]]
	if lib2.filter({category = "bell", origin = "ingested"}).size() != 1 or lib2.filter({min_rating = 4}).size() != 1:
		return "filters should use your category and rating"
	if lib2.filter({favourites = true}).size() != 1 or lib2.filter({tag = "dark"}).size() != 1:
		return "favourites and your tags"
	if lib2.filter({source = "surge"}).size() != 0 or lib2.filter({source = "surge", show_hidden = true}).size() != 1:
		return "hidden patches show only when asked"
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(USER))
	if not data.patches.has("missing:patch"):
		return "entries for patches not found should be kept"
	lib2.set_category("synth1:a/bell", "")
	if lib2.get_entry("synth1:a/bell").category != "other":
		return "clearing your category goes back to the library's"
	var raw := FileAccess.get_file_as_string(ROOT + "synth1/bank a/002 Glass Bell.tres")
	if raw.contains("rating") or raw.contains("favourite"):
		return "ratings must not be written into patches"
	return ""


func test_ids_survive_a_rename() -> String:
	var dir := "res://.test_library_ids/"
	DirAccess.make_dir_recursive_absolute(dir)
	var p: AKPatch = (load("res://addons/audio_kit/patches/pluck.tres") as AKPatch).duplicate(true)
	ResourceSaver.save(p, dir + "one.tres")
	var id := AKPatch.ensure_library_id(dir + "one.tres")
	DirAccess.rename_absolute(dir + "one.tres", dir + "two.tres")
	var id2 := AKPatch.library_id(dir + "two.tres")
	DirAccess.remove_absolute(dir + "two.tres")
	DirAccess.remove_absolute(dir)
	if not id.begins_with("res:uid://") or id != id2:
		return "a project patch's ID should be its UID and survive a rename: %s, %s" % [id, id2]
	return ""


func test_speed_25000() -> String:
	_clean()
	_make_library(25000)
	var lib := _lib()
	if lib.entries.size() < 25000:
		return "only %d entries" % lib.entries.size()
	var worst := 0.0
	for f in [{query = "pad"}, {category = "bass"}, {query = "extra lead", bank = "bank 7"}, {min_rating = 0, source = "synth1"}]:
		var t := Time.get_ticks_usec()
		lib.query(f)
		worst = maxf(worst, (Time.get_ticks_usec() - t) / 1000.0)
	print("        25,000 entries: worst filter %.1f ms" % worst)
	_clean()
	# 50 ms on a quiet machine (the plan's target); the limit leaves room for a busy one.
	if worst > 150.0:
		return "filtering 25,000 entries took %.0f ms" % worst
	return ""


func test_browser_rates_copies_and_lab_keeps_library_read_only() -> String:
	_clean()
	_make_library()
	var lab := AKSynthLab.new()
	_tree().root.add_child(lab)
	lab.browser.library.user_path = USER
	lab.browser.library.cache_dir = OUT + "cache"
	lab.browser.roots = PackedStringArray([ROOT])
	lab.set_save_dir(OUT)
	var err := ""
	var acid_path := ROOT + "synth1/bank a/001 Acid Squelch.tres"
	if not lab.browser.shown().has(acid_path):
		err = "the browser should list library patches"
	if err == "":
		lab.browser.set_facet("source", "synth1")
		if lab.browser.shown().size() != 2:
			err = "the source filter in the browser: %d" % lab.browser.shown().size()
		lab.browser.set_facet("source", "")
	if err == "":
		var before := FileAccess.get_file_as_string(acid_path)
		lab.select_patch(acid_path)
		lab.editor.set_param("filter.cutoff_hz", 2345.0)
		if FileAccess.get_file_as_string(acid_path) != before or lab.patch.category != "bass":
			err = "a library patch should be edited as a copy, with the library's category"
		lab._save_name.text = "my acid"
		var saved := lab.save_patch()
		var info := AKPatch.library_info(ResourceLoader.load(saved, "", ResourceLoader.CACHE_MODE_IGNORE))
		if err == "" and (FileAccess.get_file_as_string(acid_path) != before or info.get("derived_from", "") != "synth1:a/acid"):
			err = "saving should write a copy derived from the library patch: %s" % info
		DirAccess.remove_absolute(saved)
	if err == "":
		lab.browser.select_path(ROOT + "synth1/bank a/002 Glass Bell.tres")
		lab.browser.rate_selected(3)
		if lab.browser.library.get_entry("synth1:a/bell").rating != 3:
			err = "rating from the browser"
		lab.browser.rate_selected(3)
		if err == "" and lab.browser.library.get_entry("synth1:a/bell").rating != 0:
			err = "clicking the current rating should clear it"
	if err == "":
		lab.browser.select_path(ROOT + "surge/factory/Harp Pluck.tres")
		var path := lab.browser.copy_selected()
		var c: AKPatch = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) if path != "" else null
		var info := AKPatch.library_info(c) if c else {}
		if c == null or c.category != "pluck" or info.get("derived_from", "") != "surge:f/pluck" or info.get("source", "") != "surge" \
				or info.get("creator", "") != "Claes" or not path.begins_with(OUT + "patches/"):
			err = "Use in project should copy with its category and origin: %s %s" % [path, info]
		elif not lab.browser.library.entries.any(func(e: Dictionary) -> bool: return e.path == path and e.source == "surge" and e.origin == "created"):
			err = "the copy should be listed among your patches, keeping its source"
		if path != "":
			DirAccess.remove_absolute(path)
	lab.queue_free()
	_clean()
	return err
