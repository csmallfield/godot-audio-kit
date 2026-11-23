# SPDX-License-Identifier: Apache-2.0
# Converts every Casio CZ tone in a prep-tool library:
#
#   godot --headless --path . --script res://tools/patch_convert/cz_batch.gd -- [library folder]
#
# Beside each tone's instrument.json it writes gak_patch.tres and gak_report.json (caveats, and
# the peak and length of a middle-C note); in the library folder, gak_cz_summary.json. There is no
# reference recording to measure against: the engine's part is held to the chip by tests/test_cz.gd.
extends SceneTree

const LIB := "D:/12_library/gak/processed_polynominal/casio-cz-101"
const Cz := preload("res://tools/patch_convert/cz.gd")

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
	var lib: String = args[0] if args.size() > 0 else LIB
	var folders := []
	_sidecars(lib, folders)
	folders.sort()
	var rows := []
	for folder: String in folders:
		var sc: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("instrument.json")))
		if not (sc is Dictionary) or not ((sc.get("content", {}) as Dictionary).get("cz_tone", {}) as Dictionary).has("params"):
			continue
		var params: Dictionary = sc.content.cz_tone.params
		var name := String((sc.get("identity", {}) as Dictionary).get("patch", folder.get_file()))
		var patch: AKPatch = Cz.convert(params, name)
		var err := ResourceSaver.save(patch, folder.path_join("gak_patch.tres"))
		# A middle-C note held 1 s, then 3 s to ring out.
		var ev := AKSynth.events_for([{time_s = 0.0, note = 60, length_s = 1.0}])
		var b := AKSynth.render_events(patch.compile(), ev, 48000 * 4)
		var peak := 0.0
		var last := 0
		for i in b.l.size():
			var a := maxf(absf(b.l[i]), absf(b.r[i]))
			peak = maxf(peak, a)
			if a > 1e-4:
				last = i
		var rep := {converter = "patch_convert/cz.gd %d" % Cz.VERSION, engine = AKSynthCore.VERSION,
			patch = "gak_patch.tres" if err == OK else "save failed (%d)" % err,
			line_select = params.line_select, peak_dbfs = 20.0 * log(maxf(peak, 1e-9)) / log(10.0),
			sounds_s = last / 48000.0, caveats = Cz.caveats(params)}
		var f := FileAccess.open(folder.path_join("gak_report.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify(rep, "  ") + "\n")
		f.close()
		rows.append({id = String(sc.get("id", folder)), name = name, line_select = params.line_select,
			peak_dbfs = rep.peak_dbfs, sounds_s = rep.sounds_s, caveats = rep.caveats, duplicate_of = sc.get("duplicate_of", null)})
	var f := FileAccess.open(lib.path_join("gak_cz_summary.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({converter = "patch_convert/cz.gd %d" % Cz.VERSION, engine = AKSynthCore.VERSION,
		tones = rows.size(), rows = rows}, "  ") + "\n")
	f.close()
	print("converted %d tones" % rows.size())
	quit()
