# SPDX-License-Identifier: Apache-2.0
# Prints the level trims (AKPatchLib.TRIM_DB, AKGeneralMidi.FAMILY_TRIM_DB)
# that make one note (C4, velocity 1, held 0.5 s) of each preset and GM
# family patch peak at 0.5 (-6 dBFS). Run after changing a patch, copy the
# numbers in, run again until they settle (drive and saturation make it a
# little nonlinear), then rebuild with make_patches.gd and make_bank.gd.
#   godot --headless --path . -s res://addons/audio_kit/tools/measure_levels.gd
extends SceneTree
func _init() -> void:
	var pre := {}
	for n in AKPatchLib.preset_names():
		var p := AKPatchLib.preset(StringName(n))
		var cur := float(AKPatchLib.TRIM_DB.get(StringName(n), 0.0))
		var b := AKSynth.render_note(p, 60, 1.0, 0.5)
		pre[n] = snappedf(cur + linear_to_db(0.5 / b.peak()), 0.1)
	print("PRESETS ", pre)
	var fam := {}
	for i in 16:
		var cur := float(AKGeneralMidi.FAMILY_TRIM_DB.get(i, 0.0))
		var b := AKSynth.render_note(AKGeneralMidi.family_patch(i), 60, 1.0, 0.5)
		fam[i] = snappedf(cur + linear_to_db(0.5 / b.peak()), 0.1)
	print("FAMILIES ", fam)
	quit()
