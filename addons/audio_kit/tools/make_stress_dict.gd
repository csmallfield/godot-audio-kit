# SPDX-License-Identifier: Apache-2.0
# Packs speech/data/en_stress.txt (written by tools/build_stress_dict.py) into
# en_stress.res, the AKStressDict the kit loads:
#   godot --headless --path . -s res://addons/audio_kit/tools/make_stress_dict.gd
extends SceneTree


func _init() -> void:
	var f := FileAccess.open(AKStressDict.TEXT_PATH, FileAccess.READ)
	if f == null:
		print("FAIL  can't read %s: run tools/build_stress_dict.py first" % AKStressDict.TEXT_PATH)
		quit(1)
		return
	var t := Time.get_ticks_msec()
	var d := AKStressDict.from_text(f.get_as_text())
	var err := ResourceSaver.save(d, AKStressDict.RES_PATH)
	print("%s  %s (%d words, %d KB packed, %d ms)" % ["ok  " if err == OK else "FAIL", AKStressDict.RES_PATH, d.size(),
		d.data.size() / 1024, Time.get_ticks_msec() - t])
	quit()
