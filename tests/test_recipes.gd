# SPDX-License-Identifier: Apache-2.0
extends RefCounted


func test_bake_is_byte_identical() -> String:
	var r: AKRecipe = load("res://demo/recipes/go.tres")
	var a := AK.render(r).to_stream(7).data
	var b := AK.render(r).to_stream(7).data
	return "" if a == b else "two bakes of go.tres differ"


func test_seed_changes_noise() -> String:
	var r := AKRecipe.make(&"click")
	r.seed = 1
	var a := AK.render(r)
	r.seed = 2
	var b := AK.render(r)
	return "" if a.l != b.l else "different seeds gave the same click"


func test_intensity_binding_sets_gain() -> String:
	var r := AKRecipe.make(&"tone")
	r.bind = {intensity = {gain_db = [-20.0, 0.0]}}
	var loud := AK.render(r, 1.0).peak()
	var soft := AK.render(r, 0.0).peak()
	var diff := 20.0 * log(loud / soft) / log(10.0)
	return "" if absf(diff - 20.0) < 0.01 else "intensity 0..1 changed level by %.2f dB" % diff


func test_pitch_scale_binding() -> String:
	var r := AKRecipe.make(&"tone", {wave = &"saw", freq_hz = 400.0, gate_s = 1.0, sustain = 1.0, length_s = 1.0})
	r.bind = {"data.pitch": "pitch_scale"}
	var b := AK.render(r, 1.0, {pitch = 1.5})
	var crossings := 0
	for i in range(1, b.frames()):
		if b.l[i - 1] > 0.0 and b.l[i] <= 0.0:
			crossings += 1
	return "" if absi(crossings - 600) <= 2 else "expected ~600 Hz, counted %d" % crossings


func test_vary_differs_per_hit_but_repeats() -> String:
	var r := AKRecipe.make(&"pluck")
	r.vary = {freq_hz = 0.1}
	var a0 := AK.render(r, 1.0, {}, 0)
	var a1 := AK.render(r, 1.0, {}, 1)
	var a0b := AK.render(r, 1.0, {}, 0)
	if a0.l == a1.l:
		return "hits 0 and 1 are identical"
	if a0.l != a0b.l:
		return "hit 0 differs between renders"
	return ""


func test_bake_key_ignores_unbound_inputs() -> String:
	var r := AKRecipe.make(&"tone")
	if AK.bake_key(r, 0.2, {pitch = 2.0}, 3) != AK.bake_key(r, 1.0, {}, 0):
		return "unbound intensity/data/variant changed the key"
	r.bind = {intensity = {gain_db = [-6.0, 0.0]}}
	if AK.bake_key(r, 0.2) == AK.bake_key(r, 1.0):
		return "bound intensity did not change the key"
	return ""


func test_palette_tokens() -> String:
	var pal := AKPalette.new()
	pal.tokens = {root_hz = 330.0}
	var r := AKRecipe.make(&"tone", {wave = &"saw", freq_hz = "$root_hz", gate_s = 1.0, sustain = 1.0, length_s = 1.0})
	r.palette = pal
	var b := AK.render(r)
	var crossings := 0
	for i in range(1, b.frames()):
		if b.l[i - 1] > 0.0 and b.l[i] <= 0.0:
			crossings += 1
	return "" if absi(crossings - 330) <= 2 else "palette pitch gave %d Hz" % crossings


func test_transforms() -> String:
	var r := AKRecipe.make(&"click")
	var fwd := AK.render(r)
	r.transforms = [{type = &"reverse"}] as Array[Dictionary]
	var rev := AK.render(r)
	if not is_equal_approx(rev.l[rev.frames() - 1], fwd.l[0]):
		return "reverse did not mirror the buffer"
	r.transforms = [{type = &"varispeed", from = 1.0, to = 0.0}] as Array[Dictionary]
	var stop := AK.render(r)
	if absi(stop.frames() - fwd.frames() * 2) > 2:
		return "tape stop should double the length (got %d from %d)" % [stop.frames(), fwd.frames()]
	return ""


func test_effects_chain_runs() -> String:
	var r := AKRecipe.make(&"pluck")
	r.fx = [{type = &"highpass", cutoff_hz = 200.0}, {type = &"drive", amount = 0.4}, {type = &"bitcrush", bits = 10.0},
		{type = &"echo", time_s = 0.1}, {type = &"room", room = 0.3, mix = 0.2}, {type = &"limit"}] as Array[Dictionary]
	var b := AK.render(r)
	return "" if is_finite(b.peak()) and b.peak() <= AKDsp.db_to_gain(-1.0) + 1e-6 else "chain peak %.3f" % b.peak()
