# SPDX-License-Identifier: Apache-2.0
# The drum library (AKDrumLibrary) and its browser (AKDrumBrowser): a small library made here,
# with an index as tools/drum_prep/index_drums.py writes it.
extends RefCounted

const SR := 48000
const TMP := "user://test_drum_library/"


func _const(v: float, frames := 4800) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(frames)
	out.fill(v)
	return out


## A library: <root>/col/Box/{Kick,Snare,Hat,Open}.wav, a kit file and gak_drums.json.
func _library() -> String:
	var root := ProjectSettings.globalize_path(TMP + "lib")
	if DirAccess.dir_exists_absolute(root):
		_rm(root)
	DirAccess.make_dir_recursive_absolute(root + "/col/Box")
	DirAccess.make_dir_recursive_absolute(root + "/col/kits/Box")
	for spec in [["Kick", 0.5], ["Snare", 0.3], ["Hat", 0.2], ["Open", 0.25]]:
		AKBuffer.from_mono(_const(float(spec[1])), SR).save_wav(root + "/col/Box/%s.wav" % spec[0])
	var kit := {name = "Box Kit", machine = "Box", root = "../..", pieces = [
		{name = "kick", sound = "Box/Kick.wav", gain_db = -1.0}, {name = "snare", sound = "Box/Snare.wav"},
		{name = "closed_hat", sound = "Box/Hat.wav", choke = "hats"}, {name = "open_hat", sound = "Box/Open.wav", choke = "hats"}]}
	_write(root + "/col/kits/Box/Box Kit.json", JSON.stringify(kit))
	var sounds := []
	for spec in [["Kick", "kick", "", true, ["short", "punchy"]], ["Snare", "snare", "", true, ["short"]],
			["Hat", "hat", "closed", false, ["short", "bright"]], ["Open", "hat", "open", true, ["long"]]]:
		sounds.append({id = "col/Box/%s.wav" % spec[0], path = "col/Box/%s.wav" % spec[0], name = spec[0], machine = "Box",
			collection = "col", folder = "", category = spec[1], kind = spec[2], sure = spec[3], how = "both",
			tags = spec[4], seconds = 0.1, channels = 1, rate = SR, note = ""})
	var index := {version = 1, collections = [{name = "col"}], sounds = sounds, kits = [
		{id = "kit:col/Box/Box Kit.json", path = "col/kits/Box/Box Kit.json", name = "Box Kit", machine = "Box",
			collection = "col", from = "assembled", folder = "", pieces = 4, sure_share = 0.75, layered = 0}]}
	_write(root + "/gak_drums.json", JSON.stringify(index))
	return root


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _rm(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_rm(dir.path_join(d))
	DirAccess.remove_absolute(dir)


func _lib(root: String) -> AKDrumLibrary:
	var lib := AKDrumLibrary.new()
	lib.roots = PackedStringArray([root])
	lib.user_path = TMP + "user.json"
	lib.cache_dir = TMP + "cache"
	if FileAccess.file_exists(lib.user_path):
		DirAccess.remove_absolute(lib.user_path)
	lib.load_all()
	return lib


func test_index_filters_and_counts() -> String:
	var lib := _lib(_library())
	if lib.entries.size() != 5 or not lib.problems.is_empty():
		return "5 entries expected, got %d (%s)" % [lib.entries.size(), lib.problems]
	var r := lib.query({type = "sound", category = "hat"})
	if r.items.size() != 2 or int(r.counts.category.get("kick", 0)) != 1 or int(r.counts.kind.get("open", 0)) != 1:
		return "hats: %d, counts %s" % [r.items.size(), r.counts]
	if lib.filter({type = "sound", sure = true, category = "hat"}).size() != 1:
		return "sure should hide the guessed hat"
	if lib.filter({type = "sound", tag = "short"}).size() != 3 or lib.filter({query = "box kit"}).size() != 1:
		return "tag and search"
	if lib.filter({type = "kit"})[0].tags[0] != "assembled kit":
		return "a kit's tags say how it was made"
	# the user file
	var e := lib.get_entry("col/Box/Snare.wav")
	lib.set_rating(e.id, 4)
	lib.set_favourite(e.id, true)
	lib.set_tags(e.id, PackedStringArray(["Crisp", " crisp", "dry"]))
	lib.set_hidden("col/Box/Hat.wav", true)
	var lib2 := AKDrumLibrary.new()
	lib2.roots = lib.roots
	lib2.user_path = lib.user_path
	lib2.cache_dir = lib.cache_dir
	lib2.load_all()       # from the cache this time
	var e2 := lib2.get_entry("col/Box/Snare.wav")
	if int(e2.rating) != 4 or not e2.favourite or Array(e2.user_tags) != ["crisp", "dry"]:
		return "the user file should come back: %s" % e2
	if lib2.filter({type = "sound"}).size() != 3 or lib2.filter({type = "sound", show_hidden = true}).size() != 4:
		return "hidden sounds stay out unless asked for"
	if lib2.filter({favourites = true, min_rating = 3}).size() != 1 or lib2.filter({query = "crisp"}).size() != 1:
		return "favourites, stars and your tags filter"
	return ""


func test_kits_and_sounds_play_from_the_library() -> String:
	var lib := _lib(_library())
	var kit := lib.kit(lib.filter({type = "kit"})[0])
	if kit == null or kit.piece_count() != 4 or not kit.has_meta(AKDrumLibrary.LIBRARY_META):
		return "the kit should load with where it came from"
	if absf(AK.render(kit.piece_recipe(0)).l[2400]) < 0.3:
		return "the kick should play"
	var s := lib.sample(lib.get_entry("col/Box/Snare.wav"))
	if s == null or absf(AK.render(s.to_recipe()).l[2400]) < 0.2:
		return "a sound should play"
	var beat := AKDrumBrowser.beat_for(kit)
	if beat == null or beat.seconds() < 4.0:
		return "a kit's beat is two bars at 100 bpm"
	return ""


func test_use_in_project_copies_kits_and_sounds() -> String:
	var lib := _lib(_library())
	var proj := TMP + "project/"
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(proj)):
		_rm(ProjectSettings.globalize_path(proj))
	var ke: Dictionary = lib.filter({type = "kit"})[0]
	var path := lib.copy_kit(ke, proj)
	if path != proj + "kits/Box Kit.tres":
		return "kit copied to %s (%s)" % [path, lib.problems]
	var k := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as AKKit
	if k == null or k.piece_count() != 4 or String(k.get_meta(AKDrumLibrary.LIBRARY_META).id) != ke.id:
		return "the copied kit should load with its origin"
	var snd: Variant = k.pieces[1].sound
	if not (snd is String and String(snd).begins_with(proj + "samples/drums/Box/")):
		return "pieces should point at the copied samples: %s" % [snd]
	var smp := ResourceLoader.load(String(snd), "", ResourceLoader.CACHE_MODE_IGNORE) as AKSample
	if smp == null or smp.data.is_empty() or not FileAccess.file_exists(smp.source):
		return "a copied sample holds its sound and its WAV is beside it"
	if absf(AK.render(k.piece_recipe(1)).l[2400]) < 0.2:
		return "the copied kit should play"
	if lib.copy_kit(ke, proj) != path:
		return "copying the same kit again reuses it"
	var sp := lib.copy_sound(lib.get_entry("col/Box/Kick.wav"), proj)
	if sp != proj + "samples/drums/Box/Kick.sample.tres":
		return "a sound copied again reuses the kit's copy: %s" % sp
	return ""


func test_browser() -> String:
	var root := _library()
	var b := AKDrumBrowser.new()
	b.library.user_path = TMP + "user_b.json"
	if FileAccess.file_exists(b.library.user_path):
		DirAccess.remove_absolute(b.library.user_path)    # a fresh start: no ratings from an earlier run
	b.library.cache_dir = TMP + "cache"
	b.roots = PackedStringArray([root])
	b.refresh()
	if b.items().size() != 1 or b.items()[0].type != "kit":
		return "the browser opens on kits"
	var heard := []
	b.audition.connect(func(buf: AKBuffer) -> void: heard.append(buf))
	b.select_row(0)
	if heard.size() != 1 or heard[0].seconds() < 4.0:
		return "selecting a kit plays its beat"
	b.set_type("sound")
	if b.items().size() != 4:
		return "4 sounds expected, %d" % b.items().size()
	b.set_facet("category", "hat")
	if b.items().size() != 2:
		return "the category filter"
	b.select_row(1)
	if heard.size() != 2:
		return "selecting a sound plays it"
	b.rate_selected(3)
	if int(b.items()[1].rating) != 3 or not AKDrumBrowser._row_text(b.items()[1]).begins_with("★★★"):
		return "rating shows on the row"
	var used := []
	b.activated.connect(func(e: Dictionary) -> void: used.append(e))
	b._list.item_activated.emit(0)
	if used.size() != 1:
		return "a double-click activates"
	b.free()
	return ""
