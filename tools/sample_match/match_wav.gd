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
# --movement 1 always copies the random movement with unison or a chorus, -1 never looks
# (AKSampleMatch.movement).
# --delay 1 always uses a delay when echoes are found, -1 never looks (AKSampleMatch.delay).
# --reverb 1 always uses the closest reverb, -1 never looks (AKSampleMatch.reverb).
# For each file it writes <name>_full.tres, <name>_lite.tres, <name>_orig.wav,
# <name>_ab.wav (note by note: the original's note, then the full copy's, then the
# next note), <name>_ab_lite.wav (the same against the lite copy) and <name>_seq.wav
# (original, full and lite whole, back to back), and prints the report. All reports
# go to <out_dir>/report.json.
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
	var move_mode := int(opt.call("--movement"))
	var delay_mode := int(opt.call("--delay"))
	var rev_mode := int(opt.call("--reverb"))
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
		m.movement = move_mode
		m.delay = delay_mode
		m.reverb = rev_mode
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
		var df: Dictionary = res.report.delay_found
		if not df.is_empty():
			var dfit: Dictionary = res.report.delay_fit
			lays += "  echo %.0f ms (drop %.1f dB, x%.0f, mix %.2f fb %.2f)" % [df.time_ms, df.drop_db, df.x, df.mix, df.feedback]
			if not dfit.is_empty():
				lays += " -> delay %.1f ms mix %.2f fb %.2f damp %.0f, release %.3f s: tails %.1f -> %.1f dB, score %.1f (%s)" % [dfit.fx.time_ms, dfit.fx.mix,
					dfit.fx.feedback, dfit.fx.damp_hz, dfit.release.release_s, dfit.tail_before, dfit.tail, dfit.score,
					"used" if not (res.report.delay as Dictionary).is_empty() else "not used"]
		if int(res.report.get("interval", 0)) != 0:
			lays += "  second pitch +%d semitones" % int(res.report.interval)
		var rf: Dictionary = res.report.reverb_fit
		if not rf.is_empty():
			lays += "  reverb room %.2f damp %.2f mix %.3f, release %.3f s: tails %.1f -> %.1f dB, L/R %.2f -> %.2f, score %.1f (%s)" % [rf.fx.room, rf.fx.damp,
				rf.fx.mix, rf.release.release_s, rf.tail_before, rf.tail, rf.corr_before, rf.corr, rf.score,
				"used" if not (res.report.reverb as Dictionary).is_empty() else "not used"]
		var mv: Dictionary = res.report.movement_found
		if not mv.is_empty():
			var what := []
			if mv.has("unison"):
				what.append("unison %d x %.1f c" % [mv.unison, mv.detune_cents])
			if mv.has("chorus"):
				what.append("chorus %.2f Hz %.1f ms" % [mv.chorus.rate_hz, mv.chorus.depth_ms])
			lays += "  movement %s: gap %.1f -> %.1f dB, tone %.1f, score %.1f (%s)" % [" + ".join(what), mv.gap_before, mv.gap, mv.tone, float(mv.get("score", NAN)), "used" if not (res.report.movement as Dictionary).is_empty() else "not used"]
		print("%s: %s%s  notes %s  lite centre %d  [%.0f s]" % [name, AKSampleMatch.summary(res.report), lays, " ".join(notes), m.lite_center,
			(Time.get_ticks_msec() - t0) / 1000.0])
		ResourceSaver.save(res.full, out_dir.path_join(name + "_full.tres"))
		ResourceSaver.save(res.lite, out_dir.path_join(name + "_lite.tres"))
		var orig: AKBuffer = res.original
		orig.save_wav(out_dir.path_join(name + "_orig.wav"))
		var seq := AKBuffer.new(0, orig.sample_rate)
		seq.l = orig.l + res.renders.full.l + res.renders.lite.l
		seq.r = orig.r + res.renders.full.r + res.renders.lite.r
		seq.save_wav(out_dir.path_join(name + "_seq.wav"))
		_note_by_note(orig, res.renders.full, m._x.notes).save_wav(out_dir.path_join(name + "_ab.wav"))
		_note_by_note(orig, res.renders.lite, m._x.notes).save_wav(out_dir.path_join(name + "_ab_lite.wav"))
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


## A against B one note at a time: each note of `a` (from just before it starts until its release has
## had 1.5 s, or the next note), then the same stretch of `b`, with 0.4 s of silence after each.
static func _note_by_note(a: AKBuffer, b: AKBuffer, notes: Array) -> AKBuffer:
	var sr := a.sample_rate
	var out := AKBuffer.new(0, sr)
	var gap := PackedFloat32Array()
	gap.resize(int(0.4 * sr))
	var ns := notes.duplicate()
	ns.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.t < y.t)
	for i in ns.size():
		var n: Dictionary = ns[i]
		var s0 := maxi(0, int((float(n.t) - 0.05) * sr))
		var e := int((float(n.t) + float(n.len) + 1.5) * sr)
		if i + 1 < ns.size():
			e = mini(e, int((float(ns[i + 1].t) - 0.05) * sr))
		e = mini(e, mini(a.l.size(), b.l.size()))
		if e <= s0:
			continue
		for src: AKBuffer in [a, b]:
			out.l += src.l.slice(s0, e) + gap
			out.r += src.r.slice(s0, e) + gap
	return out
