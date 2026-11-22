# SPDX-License-Identifier: Apache-2.0
# A headless "listening" pass over Flavor (AKFlavor): for every knob and switch,
# render the base and the control at each step to one WAV, and print a table of
# how each step measures, so a control's range can be judged and re-tuned.
#
#   godot --headless --path . -s res://addons/audio_kit/tools/flavor_listen.gd -- [--only lean_beefy] [--out out/flavor]
#
# Two-way knobs play: base, half up, full up, base, half down, full down.
# Add-only knobs play: base, quarter, half, three-quarters, full. Switches: off, on.
extends SceneTree

const GAP_S := 0.4


func _phrase() -> Array:
	var n: Array = []
	var t := 0.0
	for x: String in ["C2", "G2", "A#1", "C2"]:
		n.append({time_s = t, note = x, velocity = 0.85, length_s = 0.4})
		t += 0.5
	for k: String in ["A3", "C4", "E4", "G4"]:
		n.append({time_s = 2.0, note = k, velocity = 0.7, length_s = 1.4})
	return n


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var only := ""
	var out_dir := "res://out/flavor/"
	for i in args.size():
		if args[i] == "--only" and i + 1 < args.size():
			only = args[i + 1]
		elif args[i] == "--out" and i + 1 < args.size():
			out_dir = args[i + 1].trim_suffix("/") + "/"
			if not out_dir.begins_with("res://") and not out_dir.is_absolute_path():
				out_dir = "res://" + out_dir
	AK.disk_cache = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var notes := _phrase()
	print("| control | step | LUFS | peak dBFS | oscillators | matrix rows | effects |")
	print("| --- | --- | --- | --- | --- | --- | --- |")
	var controls: Array = []
	for k: Dictionary in AKFlavor.KNOBS:
		controls.append({id = k.id, steps = [0.0, 0.5, 1.0, 0.0, -0.5, -1.0] if k.two_way else [0.0, 0.25, 0.5, 0.75, 1.0]})
	for sw: Dictionary in AKFlavor.SWITCHES:
		controls.append({id = sw.id, steps = [false, true]})
	for c: Dictionary in controls:
		if only != "" and c.id != only:
			continue
		var parts: Array[AKBuffer] = []
		var cache := {}
		for step: Variant in c.steps:
			if not cache.has(step):
				var st := {c.id: step}
				if c.id == "minor":
					st["note_chord"] = 1.0
				var p := AKFlavor.build(st)
				var b := AKSynth.render_notes(p, notes, 5.0)
				cache[step] = b
				print("| %s | %s | %.1f | %.1f | %d | %d | %d |" % [c.id, str(step), AKDynamics.lufs(b), linear_to_db(maxf(b.peak(), 1e-9)),
					p.oscillators.size(), p.mods.size(), p.effects.size()])
			parts.append(cache[step])
		var gap := roundi(GAP_S * AK.sample_rate)
		var total := 0
		for b: AKBuffer in parts:
			total += b.frames() + gap
		var all := AKBuffer.new(total, AK.sample_rate)
		var at := 0
		for b: AKBuffer in parts:
			b.mix_into(all, at)
			at += b.frames() + gap
		all.save_wav(out_dir + c.id + ".wav")
	quit()
