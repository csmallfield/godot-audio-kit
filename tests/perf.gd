# SPDX-License-Identifier: Apache-2.0
# Bake timings against the design targets:
#   godot --headless --path . --script res://tests/perf.gd
# Targets: a typical effect under 50 ms; a 30 s, eight-voice bed with reverb
# under 10 s (measured here with layered tones until the sequencer exists).
extends SceneTree


func _time(label: String, recipe: AKRecipe) -> float:
	var t := Time.get_ticks_usec()
	var b := AK.render(recipe)
	var ms := (Time.get_ticks_usec() - t) / 1000.0
	print("  %-34s %7.1f ms  (%.2f s of audio, %.0fx real time)" % [label, ms, b.seconds(), b.seconds() * 1000.0 / maxf(ms, 0.001)])
	return ms


func _init() -> void:
	AK.disk_cache = false
	print("Effects:")
	for f in DirAccess.get_files_at("res://demo/recipes"):
		if f.ends_with(".tres") and not f.ends_with("_map.tres"):
			_time(f, load("res://demo/recipes/" + f))
	print("Bed stand-in (8 layered 30 s tones + room):")
	var bed := AKRecipe.make(&"tone", {wave = &"saw", freq_hz = 110.0, gate_s = 30.0, sustain = 0.5, length_s = 30.0})
	for i in 7:
		bed.layers.append({voice = &"tone", params = {wave = &"triangle", freq_hz = 110.0 * (i + 2), gate_s = 30.0, sustain = 0.4, length_s = 30.0}, gain_db = -12.0})
	bed.fx = [{type = &"lowpass", cutoff_hz = 3000.0}, {type = &"room", room = 0.6, mix = 0.25}] as Array[Dictionary]
	_time("bed_30s_8_voices", bed)
	quit()
