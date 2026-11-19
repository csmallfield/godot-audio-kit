# SPDX-License-Identifier: Apache-2.0
# Matches plain WAVs (held notes with silence between, such as the Open Samples synth
# multisamples) as patches with AKSampleMatch.run_wav.
#
#   godot --headless --path . -s res://tools/sample_match/match_wav.gd -- \
#       <out_dir> <first_note> <step> <file.wav> [<file.wav> ...] [--notes]
#
# --notes only prints the notes each file is read as (no matching). --sweep S sets
# AKSampleMatch.sweep_s (default: picked from the held notes). --hold S gives every note
# that length instead of finding its key-up (the Open Samples synths hold each note 2.42 s).
# --layers 1 always uses detuned layers when found, -1 never looks (AKSampleMatch.layers).
# --vibrato 1 always uses a vibrato when found, -1 never looks (AKSampleMatch.vibrato).
# For each file it writes <name>_full.tres, <name>_lite.tres, <name>_orig.wav and
# <name>_ab.wav (original, then full, then lite, back to back), and prints the
# report. All reports go to <out_dir>/report.json.
extends SceneTree


func _init() -> void:
	var a := Array(OS.get_cmdline_user_args())
	if a.size() < 4:
		printerr("usage: -- <out_dir> <first_note> <step> <file.wav> ...")
		quit(1)
		return
	var notes_only := a.has("--notes")
	a = a.filter(func(s: String) -> bool: return s != "--notes")
	var opt := func(flag: String) -> float:
		var at := a.find(flag)
		if at < 0:
			return 0.0
		var v := float(a[at + 1])
		a.remove_at(at + 1)
		a.remove_at(at)
		return v
	var sweep: float = opt.call("--sweep")
	var hold: float = opt.call("--hold")
	var lay_mode := int(opt.call("--layers"))
	var vib_mode := int(opt.call("--vibrato"))
	var out_dir: String = a[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var first := int(a[1])
	var step := int(a[2])
	var all := {}
	if notes_only:
		for path: String in a.slice(3):
			var rd := AKSampleMatch.read_wav_notes(path, first, step, 0.8, hold)
			print("%s: %s" % [path.get_file(), " ".join(rd.notes.map(func(n: Dictionary) -> String: return "%d@%.2fs(%.2fs)" % [n.note, n.t, n.len])) if rd.ok else rd.error])
		quit()
		return
	for path: String in a.slice(3):
		var t0 := Time.get_ticks_msec()
		var m := AKSampleMatch.new()
		m.sweep_s = sweep
		m.layers = lay_mode
		m.vibrato = vib_mode
		var res := m.run_wav(path, first, step, hold)
		var name := path.get_file().get_basename().validate_filename().replace(" ", "_")
		if not res.ok:
			print("%s: FAILED %s" % [name, res.error])
			all[name] = {error = res.error}
			continue
		var notes: Array = m._x.notes.map(func(n: Dictionary) -> String: return "%d@%.2fs(%.2fs)" % [n.note, n.t, n.len])
		var lay: Dictionary = res.report.layers_found
		var lays := "" if lay.is_empty() else "  layers %.2f c, score %.2f, %s (%s)" % [lay.cents, lay.score, " ".join((lay.notes as Dictionary).keys().map(func(k: int) -> String: return "%d: r %.2f ph %.3f" % [k, lay.notes[k].r, lay.notes[k].phase])), "used" if not (res.report.layers as Dictionary).is_empty() else "not used"]
		var vb: Dictionary = res.report.vibrato_found
		lays += "" if vb.is_empty() else "  vibrato %.3f Hz %.1f c ph %.3f %s x%.1f (%s)" % [vb.rate_hz, vb.cents, vb.phase, "free" if vb.free else "from note-on", vb.x, "used" if not (res.report.vibrato as Dictionary).is_empty() else "not used"]
		print("%s: %s%s  notes %s  lite centre %d  [%.0f s]" % [name, AKSampleMatch.summary(res.report), lays, " ".join(notes), m.lite_center,
			(Time.get_ticks_msec() - t0) / 1000.0])
		ResourceSaver.save(res.full, out_dir.path_join(name + "_full.tres"))
		ResourceSaver.save(res.lite, out_dir.path_join(name + "_lite.tres"))
		var orig: AKBuffer = res.original
		orig.save_wav(out_dir.path_join(name + "_orig.wav"))
		var ab := AKBuffer.new(0, orig.sample_rate)
		ab.l = orig.l + res.renders.full.l + res.renders.lite.l
		ab.r = orig.r + res.renders.full.r + res.renders.lite.r
		ab.save_wav(out_dir.path_join(name + "_ab.wav"))
		var rep: Dictionary = res.report.duplicate()
		rep.floor_db = null
		rep.notes = notes
		rep.lite_center = m.lite_center
		rep.sweep_s = m._pos_t
		all[name] = rep
	var f := FileAccess.open(out_dir.path_join("report.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(all, "  "))
	f.close()
	quit()
