# SPDX-License-Identifier: Apache-2.0
# Writes the built-in patch presets (AKPatchLib.preset) to
# addons/audio_kit/patches/ as .tres text:
#   godot --headless --path . -s res://addons/audio_kit/tools/make_patches.gd
extends SceneTree


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(AKPatchLib.PRESET_DIR)
	for n in AKPatchLib.preset_names():
		var p := AKPatchLib.preset(StringName(n))
		var path := AKPatchLib.PRESET_DIR + n + ".tres"
		var err := ResourceSaver.save(p, path)
		print("%s  %s" % ["ok  " if err == OK else "FAIL", path])
	quit()
