# SPDX-License-Identifier: Apache-2.0
# Headless test runner:  godot --headless --path . --script res://tests/run_tests.gd
extends SceneTree

const SUITES := [
	"res://tests/test_dsp.gd",
	"res://tests/test_voices.gd",
	"res://tests/test_recipes.gd",
	"res://tests/test_cues.gd",
	"res://tests/test_bridge.gd",
	"res://tests/test_music.gd",
	"res://tests/test_native.gd",
	"res://tests/test_live.gd",
	"res://tests/test_live_nodes.gd",
	"res://tests/test_spatial.gd",
	"res://tests/test_dock.gd",
	"res://tests/test_sound_lab.gd",
	"res://tests/test_synth.gd",
]


var _ran := false


# Run on the first frame, when the tree is up and accepts children, so tests
# can put nodes in it.
func _process(_delta: float) -> bool:
	if not _ran:
		_ran = true
		_run()
	return false


func _run() -> void:
	AK.disk_cache = false
	var failed := 0
	var passed := 0
	for path in SUITES:
		if not ResourceLoader.exists(path):
			continue
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			failed += 1
			print("  FAIL  %s  does not load (parse error above)" % path.get_file())
			continue
		var suite: Object = script.new()
		for m in suite.get_method_list():
			var name: String = m.name
			if not name.begins_with("test_"):
				continue
			# A test may await (physics frames, timers): wait for it.
			var res: Variant = await suite.call(name)
			# A test that hit a script error returns null: that's a failure.
			var err: String = res if res is String else "crashed (script error above)"
			if err == "":
				passed += 1
				print("  ok    %s::%s" % [path.get_file(), name])
			else:
				failed += 1
				print("  FAIL  %s::%s  %s" % [path.get_file(), name, err])
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
