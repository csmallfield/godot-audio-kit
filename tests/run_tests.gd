# SPDX-License-Identifier: Apache-2.0
# Headless test runner:  godot --headless --path . --script res://tests/run_tests.gd
extends SceneTree

const SUITES := [
	"res://tests/test_dsp.gd",
	"res://tests/test_voices.gd",
	"res://tests/test_recipes.gd",
	"res://tests/test_cues.gd",
]


func _init() -> void:
	AK.disk_cache = false
	var failed := 0
	var passed := 0
	for path in SUITES:
		if not ResourceLoader.exists(path):
			continue
		var suite: Object = load(path).new()
		for m in suite.get_method_list():
			var name: String = m.name
			if not name.begins_with("test_"):
				continue
			var err: String = suite.call(name)
			if err == "":
				passed += 1
				print("  ok    %s::%s" % [path.get_file(), name])
			else:
				failed += 1
				print("  FAIL  %s::%s  %s" % [path.get_file(), name, err])
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
