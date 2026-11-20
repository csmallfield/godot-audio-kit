# SPDX-License-Identifier: Apache-2.0
# Converts every DX7 voice in a prep-tool library and checks it against msfa:
#
#   godot --headless --path . --script res://tools/patch_convert/dx7_batch.gd -- [library folder]
#
# Beside each voice's instrument.json it writes gak_patch.tres (the patch) and
# gak_report.json (SNR per note against render_msfa_v100.wav, see
# tools/patch_convert/render_msfa.py); in the library folder, gak_dx7_summary.json.
extends SceneTree

const LIB := "D:/12_library/gak/processed_soundarchive/yamaha-dx7"
const Dx7 := preload("res://tools/patch_convert/dx7.gd")

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
	var t0 := Time.get_ticks_msec()
	for folder: String in folders:
		var sc: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("instrument.json")))
		if not (sc is Dictionary) or not (sc.get("content", {}) as Dictionary).has("dx7"):
			continue
		var patch: AKPatch = Dx7.convert(sc.content.dx7.params)
		var err := ResourceSaver.save(patch, folder.path_join("gak_patch.tres"))
		var rep: Dictionary = Dx7.check(patch, sc, folder)
		rep.patch = "gak_patch.tres" if err == OK else "save failed (%d)" % err
		var f := FileAccess.open(folder.path_join("gak_report.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify(rep, "  ") + "\n")
		f.close()
		rows.append({id = String(sc.get("id", folder)), name = patch.resource_name, algorithm = int(sc.content.dx7.params.algorithm),
			snr_min_db = rep.get("snr_min_db", -1.0), snr_median_db = rep.get("snr_median_db", -1.0),
			caveats = rep.get("caveats", []), duplicate_of = sc.get("duplicate_of", null)})
	var clean := rows.filter(func(r: Dictionary) -> bool: return (r.caveats as Array).is_empty())
	var mins := clean.map(func(r: Dictionary) -> float: return float(r.snr_min_db))
	mins.sort()
	var summary := {converter = "patch_convert/dx7.gd %d" % Dx7.VERSION, engine = AKSynthCore.VERSION, voices = rows.size(),
		without_caveats = clean.size(), clean_snr_min_db = mins[0] if not mins.is_empty() else null,
		clean_snr_p10_db = mins[mins.size() / 10] if not mins.is_empty() else null,
		clean_snr_median_db = mins[mins.size() / 2] if not mins.is_empty() else null,
		seconds = (Time.get_ticks_msec() - t0) / 1000.0, rows = rows}
	var out := FileAccess.open(lib.path_join("gak_dx7_summary.json"), FileAccess.WRITE)
	out.store_string(JSON.stringify(summary, "  ") + "\n")
	out.close()
	print("%d voices (%d without caveats): worst-note SNR min %s, 10th pct %s, median %s dB, %.0f s" % [rows.size(), clean.size(),
		summary.clean_snr_min_db, summary.clean_snr_p10_db, summary.clean_snr_median_db, summary.seconds])
	quit(0)
