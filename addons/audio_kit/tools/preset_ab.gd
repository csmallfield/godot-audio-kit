# SPDX-License-Identifier: Apache-2.0
# Renders each GAK_ preset beside the preset it comes from, for listening,
# and prints what they measure like. One WAV per pair in --out: the original,
# a pause, the GAK_ preset with its macros at 0, a pause, the GAK_ preset with
# every macro at 1 (its range), each brought to the same loudness. The phrase depends on the category.
#   godot --headless --path . -s res://addons/audio_kit/tools/preset_ab.gd -- [--out out/presets] [GAK_name ...]
# With no names, every GAK_ preset. CPU is render time over audio
# time for that phrase (lower is cheaper; the native core when it's built).
extends SceneTree

const STEP := 0.125   # a 16th at 120 bpm, the presets' default tempo
const GAP_S := 0.8
## The WAVs' segments are each brought to this loudness (the printed figures are before it).
const MATCH_LUFS := -16.0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := "out/presets"
	var names: Array[String] = []
	var i := 0
	while i < args.size():
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
			i += 1
		else:
			names.append(args[i])
		i += 1
	if names.is_empty():
		for n in AKPatchLib.preset_names():
			if n.begins_with("GAK_"):
				names.append(n)
	DirAccess.make_dir_recursive_absolute(out)
	print("native core: %s" % ("yes" if AKSynth.available() else "no (GDScript: CPU figures are ~100x)"))
	print("%-22s %8s %8s %8s %7s" % ["preset", "peak dB", "LUFS", "CPU %", "len s"])
	for n in names:
		var gak := AKPatchLib.preset(StringName(n))
		var orig := AKPatchLib.preset(StringName(n.trim_prefix("GAK_")))
		if gak == null or orig == null:
			continue
		var notes := phrase(gak.category)
		var a := _measure(orig, notes, n.trim_prefix("GAK_"))
		var b := _measure(gak, notes, n)
		var up: AKPatch = gak.duplicate(true)
		up.macros = [1.0, 1.0, 1.0, 1.0]
		var c := _measure(up, notes, n + " (macros 1)")
		var all := AKBuffer.new(0, a.sample_rate)
		var at := 0
		for buf: AKBuffer in [a, b, c]:
			# Matched loudness, so the comparison is of the sound, not the level
			# (louder tends to sound better); never past -1 dBFS.
			var g := db_to_linear(MATCH_LUFS - AKDynamics.lufs(buf))
			buf.apply_gain(minf(g, db_to_linear(-1.0) / maxf(1e-6, buf.peak())))
			buf.mix_into(all, at)
			at += buf.frames() + int(GAP_S * a.sample_rate)
		all.save_wav(out.path_join(n + "_ab.wav"))
	quit()


func _measure(p: AKPatch, notes: Array, label: String) -> AKBuffer:
	var t0 := Time.get_ticks_usec()
	var buf := AKSynth.render_notes(p, notes)
	var cpu := float(Time.get_ticks_usec() - t0) / 1e6 / maxf(0.001, buf.seconds())
	print("%-22s %8.1f %8.1f %8.1f %7.2f" % [label, linear_to_db(buf.peak()), AKDynamics.lufs(buf), 100.0 * cpu, buf.seconds()])
	return buf


## A phrase that shows off a preset of this category: [{time_s, note, length_s, velocity}].
static func phrase(category: String) -> Array:
	var notes := []
	match category:
		"bass":
			# Two bars of 16ths with accents and slides (a slide overlaps the
			# next note, so legato patches glide), then a held note to hear
			# movement, then a slide up and back.
			var steps := [["C2", 2, 1.0, false], ["C2", 1, 0.55, false], ["C3", 1, 0.9, true], ["C2", 2, 0.7, false],
				["Eb2", 2, 1.0, false], ["F2", 1, 0.6, false], ["G2", 1, 0.95, true], ["Bb1", 2, 0.7, false],
				["C2", 1, 1.0, false], ["C2", 1, 0.5, false], ["Eb2", 1, 0.8, true], ["F2", 1, 0.6, false],
				["G2", 2, 1.0, false], ["Bb2", 1, 0.7, true], ["C3", 1, 0.9, false], ["G1", 4, 0.8, false]]
			var t := 0.0
			for s in steps:
				var len: float = STEP * float(s[1])
				notes.append({time_s = t, note = s[0], length_s = len * 0.85 + (0.03 if s[3] else 0.0), velocity = s[2]})
				t += len
			notes.append({time_s = t, note = "C2", length_s = 2.0, velocity = 0.85})
			t += 2.0
			notes.append({time_s = t, note = "C2", length_s = 0.3, velocity = 0.9})
			notes.append({time_s = t + 0.25, note = "C3", length_s = 0.3, velocity = 1.0})
			notes.append({time_s = t + 0.5, note = "C2", length_s = 0.4, velocity = 0.7})
		"lead":
			# A melody with slurs (overlapping notes glide on legato patches),
			# a held note with the mod wheel raised and lowered, then a run.
			var mel := [["G4", 0.25], ["A4", 0.25], ["C5", 0.5], ["D5", 0.25], ["E5", 0.25], ["D5", 0.5],
				["C5", 0.25], ["A4", 0.25], ["G4", 0.5]]
			var t := 0.0
			for m in mel:
				notes.append({time_s = t, note = m[0], length_s = m[1] + 0.02, velocity = 0.85})
				t += m[1]
			notes.append({time_s = t, note = "C5", length_s = 2.2, velocity = 0.95})
			for k in 9:
				notes.append({time_s = t + 0.6 + 0.12 * k, mod_wheel = minf(1.0, k / 4.0) if k <= 4 else maxf(0.0, (8 - k) / 4.0)})
			t += 2.4
			for nm in ["C5", "D5", "E5", "G5", "A5", "C6"]:
				notes.append({time_s = t, note = nm, length_s = 0.13, velocity = 0.8})
				t += 0.125
		"keys", "pluck":
			# Chords soft and hard, then an arpeggio across the keyboard.
			var t := 0.0
			for ch in [[["C4", "E4", "G4", "B4"], 0.5], [["A3", "C4", "E4", "G4"], 0.9], [["F3", "A3", "C4", "E4"], 0.6], [["G3", "B3", "D4", "F4"], 1.0]]:
				for nm in ch[0]:
					notes.append({time_s = t, note = nm, length_s = 0.7, velocity = ch[1]})
				t += 0.8
			for nm in ["C3", "G3", "E4", "C5", "G5", "E6", "C6", "G5", "E5", "C5", "G4", "E4"]:
				notes.append({time_s = t, note = nm, length_s = 0.2, velocity = 0.75})
				t += 0.15
		"bell":
			# Single strikes soft and hard, low and high, left to ring, then a chord.
			var t := 0.0
			for b in [["C4", 0.5], ["G4", 1.0], ["C5", 0.7], ["E5", 0.9], ["C3", 0.8]]:
				notes.append({time_s = t, note = b[0], length_s = 0.3, velocity = b[1]})
				t += 0.9
			for nm in ["C4", "E4", "G4", "C5"]:
				notes.append({time_s = t, note = nm, length_s = 0.5, velocity = 0.8})
		"brass":
			# Stabs, then a swell held long, soft then loud.
			var t := 0.0
			for k in 4:
				for nm in ["C4", "E4", "G4"]:
					notes.append({time_s = t, note = nm, length_s = 0.15, velocity = 1.0 if k % 2 == 0 else 0.7})
				t += 0.375
			for ch in [[["F3", "A3", "C4"], 0.5], [["G3", "B3", "D4"], 1.0]]:
				for nm in ch[0]:
					notes.append({time_s = t, note = nm, length_s = 1.6, velocity = ch[1]})
				t += 1.8
		"pad", "strings", "organ":
			# Held chords: Cmaj7, Am9, Fmaj7, G6, with the mod wheel moved on the last.
			var t := 0.0
			for ch in [["C3", "G3", "B3", "E4"], ["A2", "E3", "B3", "C4"], ["F2", "C3", "E3", "A3"], ["G2", "D3", "E3", "B3"]]:
				for nm in ch:
					notes.append({time_s = t, note = nm, length_s = 1.9, velocity = 0.8})
				t += 2.0
			for k in 9:
				notes.append({time_s = 6.2 + 0.2 * k, mod_wheel = minf(1.0, k / 4.0) if k <= 4 else maxf(0.0, (8 - k) / 4.0)})
		_:
			# Anything else: a short melody and a held chord.
			var t := 0.0
			for nm in ["C4", "E4", "G4", "C5", "B4", "G4"]:
				notes.append({time_s = t, note = nm, length_s = 0.22, velocity = 0.85})
				t += 0.25
			for nm in ["C4", "E4", "G4", "B4"]:
				notes.append({time_s = t + 0.1, note = nm, length_s = 2.0, velocity = 0.8})
	return notes
