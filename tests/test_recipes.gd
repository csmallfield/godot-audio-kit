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


func test_vocab_moves() -> String:
	var r := AKRecipe.make(&"pluck", {freq_hz = 440.0, tone_hz = 4000.0})
	r.send = 0.3
	var b := AKVocab.apply(r, ["brighter", "drier", "higher"])
	if not is_equal_approx(float(b.params.tone_hz), 6000.0):
		return "brighter: tone_hz %s" % b.params.tone_hz
	if not is_equal_approx(b.send, 0.15):
		return "drier: send %s" % b.send
	if absf(float(b.params.freq_hz) - 493.88) > 0.05:
		return "higher: freq_hz %s" % b.params.freq_hz
	if not is_equal_approx(float(r.params.tone_hz), 4000.0):
		return "apply changed the original recipe"
	var half := AKVocab.apply(r, ["brighter"], 0.5)
	if absf(float(half.params.tone_hz) - 4000.0 * sqrt(1.5)) > 0.01:
		return "amount 0.5 should be half a step"
	return ""


func test_vocab_fx_words() -> String:
	var r := AKRecipe.make(&"click")
	var g := AKVocab.apply(r, ["grittier"])
	if g.fx.size() != 1 or String(g.fx[0].type) != "drive":
		return "grittier did not add drive"
	var c := AKVocab.apply(g, ["cleaner"])
	if not is_equal_approx(float(c.fx[0].amount), 0.3 * 1.4 * 0.5):
		return "cleaner did not halve drive"
	return ""


func test_shipped_palettes_load() -> String:
	for f in DirAccess.get_files_at("res://addons/audio_kit/palettes"):
		if f.ends_with(".tres"):
			var p: AKPalette = load("res://addons/audio_kit/palettes/" + f)
			if p == null or p.tokens.is_empty() or p.description == "":
				return "%s is empty" % f
	return ""


func test_follow_tracks_curve() -> String:
	var r := AKRecipe.make(&"follow", {wave = &"saw", length_s = 1.0, pitch = [[0.0, 200.0], [1.0, 400.0]], fade_s = 0.0})
	var b := AK.render(r)
	var crossings := 0
	for i in range(1, b.frames()):
		if b.l[i - 1] > 0.0 and b.l[i] <= 0.0:
			crossings += 1
	return "" if absi(crossings - 300) <= 2 else "200 -> 400 Hz glide crossed %d times (expected ~300)" % crossings


func test_small_reverb_is_cheaper() -> String:
	# Best of three each: timing on a shared machine is noisy.
	var b := AK.render(AKRecipe.make(&"pluck"))
	var full := INF
	var small := INF
	for i in 3:
		var t := Time.get_ticks_usec()
		AKReverb.wet(b, 0.5, 0.5, 1.0, 1.0, &"full")
		full = minf(full, Time.get_ticks_usec() - t)
		t = Time.get_ticks_usec()
		AKReverb.wet(b, 0.5, 0.5, 1.0, 1.0, &"small")
		small = minf(small, Time.get_ticks_usec() - t)
	return "" if small < full * 0.8 else "small reverb took %.0f%% of full" % (100.0 * small / full)


func test_vary_variants_cycle() -> String:
	var r := AKRecipe.make(&"click")
	r.vary = {freq_hz = 0.2}
	r.vary_variants = 3
	if AK.bake_key(r, 1.0, {}, 1) != AK.bake_key(r, 1.0, {}, 4):
		return "variant 4 should reuse variant 1 with 3 variants"
	if AK.bake_key(r, 1.0, {}, 1) == AK.bake_key(r, 1.0, {}, 2):
		return "variants 1 and 2 should differ"
	return ""
