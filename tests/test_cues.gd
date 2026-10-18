# SPDX-License-Identifier: Apache-2.0
extends RefCounted


func _map() -> AKCueMap:
	var m := AKCueMap.new()
	m.sounds = {"go": AKRecipe.make(&"click"), "whoosh.*": AKRecipe.make(&"whoosh"), "*": AKRecipe.make(&"tone")}
	m.master_fx = [] as Array[Dictionary]
	return m


func test_cue_map_matching() -> String:
	var m := _map()
	if m.recipe_for(&"go").voice != &"click":
		return "exact match failed"
	if m.recipe_for(&"whoosh.out").voice != &"whoosh":
		return "prefix match failed"
	if m.recipe_for(&"anything").voice != &"tone":
		return "fallback failed"
	return ""


func test_cue_lands_on_its_sample() -> String:
	# A click cued at frame 45 (30 fps) must start at exactly 1.5 s.
	var r := AK.render_cues([{name = "go", frame = 45.0}], _map(), 30.0)
	var first: int = r.mix.first_above(1e-6)
	var expected := roundi(1.5 * AK.sample_rate)
	return "" if absi(first - expected) <= 1 else "started at %d, expected %d" % [first, expected]


func test_negative_offset_starts_early() -> String:
	var m := _map()
	var rec: AKRecipe = m.sounds["go"]
	rec.offset_s = -0.25
	var r := AK.render_cues([{name = "go", time = 1.0}], m)
	var first: int = r.mix.first_above(1e-6)
	return "" if absi(first - roundi(0.75 * AK.sample_rate)) <= 1 else "started at %d" % first


func test_stems_sum_to_mix() -> String:
	var cues := [{name = "go", time = 0.1}, {name = "whoosh.in", time = 0.3}, {name = "other", time = 0.5}]
	var r := AK.render_cues(cues, _map(), 30.0, 1.0, true)
	if r.stems.size() != 3:
		return "expected 3 stems, got %d" % r.stems.size()
	var mix: AKBuffer = r.mix
	for i in range(0, mix.frames(), 97):
		var s := 0.0
		for k in r.stems:
			s += r.stems[k].l[i]
		if absf(s - mix.l[i]) > 1e-5:
			return "stems differ from the mix at sample %d" % i
	return ""


func test_motion_kit_cue_sheet() -> String:
	var sheet := AK.load_cue_sheet("res://demo/cues/race_ident.json")
	var map: AKCueMap = load("res://demo/recipes/race_ident_map.tres")
	var r := AK.render_cues(sheet.cues, map, float(sheet.fps), float(sheet.duration) / float(sheet.fps))
	for c in r.cues:
		if c.get("missing", false):
			return "cue '%s' has no recipe" % c.name
	var lufs := AKDynamics.lufs(r.mix)
	if absf(lufs + 16.0) > 1.0:
		return "mix at %.1f LUFS, expected -16" % lufs
	return ""


func test_repeated_hits_render_once() -> String:
	# An expensive recipe (string plus reverb), so rendering dominates mixing.
	var m := _map()
	m.sounds["go"] = AKRecipe.make(&"pluck", {}, [{type = &"room", room = 0.6, mix = 0.3}] as Array[Dictionary])
	var cues := []
	for i in 20:
		cues.append({name = "go", time = i * 0.05})
	var t := Time.get_ticks_usec()
	AK.render_cues(cues, m)
	var many := Time.get_ticks_usec() - t
	t = Time.get_ticks_usec()
	AK.render_cues([cues[0]], m)
	var one := Time.get_ticks_usec() - t
	return "" if many < one * 6 else "20 identical hits took %.1fx one hit: not memoised" % (float(many) / one)


func test_send_bus_adds_one_reverb() -> String:
	var m := _map()
	var dry: AKRecipe = m.sounds["go"]
	var r0 := AK.render_cues([{name = "go", time = 0.1}], m, 30.0, 0.0, true)
	if r0.stems.has("reverb"):
		return "no send, but a reverb stem appeared"
	dry.send = 0.5
	var r1 := AK.render_cues([{name = "go", time = 0.1}, {name = "go", time = 0.4}], m, 30.0, 0.0, true)
	if not r1.stems.has("reverb"):
		return "send set, but no reverb stem"
	if r1.mix.frames() <= r0.mix.frames() + AK.sample_rate:
		return "reverb tail missing from the mix"
	return ""


func test_e1_port_maps_every_cue() -> String:
	var sheet := AK.load_cue_sheet("res://demo/cues/e1_supergraphic.json")
	var map: AKCueMap = load("res://demo/recipes/supergraphic/e1_map.tres")
	for c in sheet.cues:
		if map.recipe_for(StringName(c.name)) == null:
			return "cue '%s' has no recipe" % c.name
	return ""
