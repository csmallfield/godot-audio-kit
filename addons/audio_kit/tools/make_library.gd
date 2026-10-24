# SPDX-License-Identifier: Apache-2.0
# Writes the kit-made sample library (AKLibrary) to addons/audio_kit/library/:
# a recipe per sound in a folder per category, and the five default kits.
#   godot --headless --path . -s res://addons/audio_kit/tools/make_library.gd
extends SceneTree


func _init() -> void:
	var bad := 0
	var n := 0
	for s: Dictionary in AKLibrary.sounds():
		DirAccess.make_dir_recursive_absolute(AKLibrary.DIR + String(s.folder))
		bad += _save(s.recipe, AKLibrary.path_of(s.folder, s.name))
		n += 1
	DirAccess.make_dir_recursive_absolute(AKLibrary.KITS_DIR)
	for k: AKKit in AKLibrary.kits():
		bad += _save(k, AKLibrary.kit_path(k.resource_name))
	print("%d sounds, %d kits, %d failed" % [n, AKLibrary.KIT_NAMES.size(), bad])
	quit(1 if bad else 0)


func _save(r: Resource, path: String) -> int:
	var err := ResourceSaver.save(r, path)
	if err != OK:
		print("FAIL  %s" % path)
	return 0 if err == OK else 1
