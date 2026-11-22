# SPDX-License-Identifier: Apache-2.0
# Converts every TAL-NoiseMaker, Helm or OB-Xd/OB-Xf patch in a prep-tool library and renders it
# in the reference's layout:
#
#   godot --headless --path . --script res://tools/patch_convert/vsynth_batch.gd -- <tal|helm|obxf> [library | list.txt] [part/parts]
#
# A .txt argument lists patch folders, one per line. "part/parts" (e.g. 3/8) takes every
# parts-th patch from the part-th, so several Godot processes can share a library.
#
# Beside each patch's instrument.json (with content.<synth> and content.render_<synth>, from
# render_vsynth.py) it writes gak_patch.tres, gak_render_v100.wav (16-bit stereo; each note
# rendered alone for its slot, as the reference) and gak_convert.json (converter version,
# caveats, the file's scale). check_vsynth.py then compares the two renders.
extends SceneTree

const LIBS := {tal = "D:/12_library/gak/processed_tal", helm = "D:/12_library/gak/processed_helm",
	obxf = "D:/12_library/gak/processed_obx"}
const CONVERTERS := {tal = "res://tools/patch_convert/tal.gd", helm = "res://tools/patch_convert/helm.gd",
	obxf = "res://tools/patch_convert/obxf.gd"}
const Synth1Batch := preload("res://tools/patch_convert/synth1_batch.gd")

var _ran := false


func _process(_d: float) -> bool:
	if not _ran:
		_ran = true
		_run()
	return false


func _sidecars(dir: String, out: Array) -> void:
	if FileAccess.file_exists(dir.path_join("instrument.json")):
		out.append(dir)
	for d in DirAccess.get_directories_at(dir):
		_sidecars(dir.path_join(d), out)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var synth: String = args[0]
	var conv: GDScript = load(CONVERTERS[synth])
	var lib: String = args[1] if args.size() > 1 else LIBS[synth]
	var part := 0
	var parts := 1
	if args.size() > 2:
		part = args[2].get_slice("/", 0).to_int()
		parts = args[2].get_slice("/", 1).to_int()
	var folders := []
	if lib.ends_with(".txt"):
		for line in FileAccess.get_file_as_string(lib).split("\n"):
			if not line.strip_edges().is_empty():
				folders.append(line.strip_edges().replace("\\", "/").trim_suffix("/instrument.json"))
	else:
		_sidecars(lib, folders)
	folders.sort()
	var done := 0
	var t0 := Time.get_ticks_msec()
	for fi in folders.size():
		if fi % parts != part:
			continue
		var folder: String = folders[fi]
		var sc: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("instrument.json")))
		if not (sc is Dictionary):
			continue
		var content: Dictionary = sc.get("content", {})
		if not content.has(synth) or not content.has("render_" + synth):
			continue
		var c: Dictionary = content[synth]
		var patch: AKPatch = conv.convert(c)
		var err := ResourceSaver.save(patch, folder.path_join("gak_patch.tres"))
		var scale: float = Synth1Batch._render(patch, content["render_" + synth], folder.path_join("gak_render_v100.wav"))
		var info := {converter = "patch_convert/%s.gd %d" % [synth, conv.VERSION], engine = AKSynthCore.VERSION,
			patch = "gak_patch.tres" if err == OK else "save failed (%d)" % err, render = "gak_render_v100.wav",
			scale = scale, caveats = conv.caveats(c)}
		var f := FileAccess.open(folder.path_join("gak_convert.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify(info, "  ") + "\n")
		f.close()
		done += 1
		if done % 100 == 0:
			print("%d converted" % done)
	print("%d patches converted and rendered in %.0f s" % [done, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(0)
