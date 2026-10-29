# SPDX-License-Identifier: Apache-2.0
# Writes the General MIDI starter bank (AKGeneralMidi) to addons/audio_kit/bank/:
# a patch per GM family, a recipe per drum lane, and gm_bank.tres.
#   godot --headless --path . -s res://addons/audio_kit/tools/make_bank.gd
extends SceneTree


func _init() -> void:
	var dir := AKGeneralMidi.BANK_DIR
	DirAccess.make_dir_recursive_absolute(dir + "patches")
	DirAccess.make_dir_recursive_absolute(dir + "drums")
	var bad := 0
	for i in 16:
		bad += _save(AKGeneralMidi.family_patch(i), dir + "patches/gm_%s.tres" % AKGeneralMidi.FAMILIES[i])
	var lanes: Array = AKGeneralMidi.DRUM_LANES.keys()
	lanes.append("perc")
	for lane in lanes:
		bad += _save(AKGeneralMidi.drum_recipe(lane), dir + "drums/%s.tres" % lane)
	bad += _save(AKGeneralMidi.make_bank(), AKGeneralMidi.DEFAULT_BANK)
	print("%d failed" % bad)
	quit(1 if bad else 0)


func _save(r: Resource, path: String) -> int:
	var err := ResourceSaver.save(r, path)
	print("%s  %s" % ["ok  " if err == OK else "FAIL", path])
	return 0 if err == OK else 1
