# SPDX-License-Identifier: Apache-2.0
# The Sound Lab: the SFX generator, recipe streams, baking to WAV, the lab
# screen itself, and a numeric "listening" check that the categories differ.
extends RefCounted

const SEEDS := [1, 2, 3, 4, 5]
const OUT := "user://test_sound_lab/"

## [min, max] length in seconds (to 60 dB below the peak) per category.
const LENGTHS := {
	&"pickup": [0.15, 0.9], &"jump": [0.1, 0.6], &"laser": [0.08, 1.0], &"hit": [0.08, 0.5],
	&"explosion": [0.7, 2.6], &"powerup": [0.3, 1.4], &"ui_click": [0.01, 0.15], &"ui_confirm": [0.12, 0.7],
	&"ui_cancel": [0.12, 0.7], &"blip": [0.02, 0.2],
}


func _same(a: AKBuffer, b: AKBuffer) -> bool:
	return a.frames() == b.frames() and a.l == b.l and a.r == b.r


func _bad(buf: AKBuffer) -> bool:
	for i in buf.frames():
		if not is_finite(buf.l[i]) or not is_finite(buf.r[i]):
			return true
	return false


func test_generators_are_deterministic() -> String:
	for cat in AKSfxGen.CATEGORIES:
		for s in SEEDS:
			var a := AKSfxGen.generate(cat, s)
			var b := AKSfxGen.generate(cat, s)
			if var_to_str(a.describe()) != var_to_str(b.describe()):
				return "%s %d: two recipes from the same seed differ" % [cat, s]
			if AK.bake_key(a) != AK.bake_key(b):
				return "%s %d: bake keys differ" % [cat, s]
			if not _same(AK.render(a), AK.render(b)):
				return "%s %d: the same recipe rendered different samples" % [cat, s]
		var seen := {}
		for s in SEEDS:
			seen[var_to_str(AKSfxGen.generate(cat, s).describe())] = true
		if seen.size() < SEEDS.size():
			return "%s: different seeds gave the same recipe" % cat
	return ""


func test_every_category_is_sane() -> String:
	for cat in AKSfxGen.CATEGORIES:
		for s in SEEDS:
			var r := AKSfxGen.generate(cat, s)
			if r.get_meta(&"sfx_category") != String(cat) or int(r.get_meta(&"sfx_seed")) != s:
				return "%s %d: metadata missing" % [cat, s]
			var buf := AK.render(r)
			if _bad(buf):
				return "%s %d: NaN or infinity in the render" % [cat, s]
			var f := AKSoundFeatures.of(buf)
			var peak := buf.peak()
			if peak < 0.5:
				return "%s %d: too quiet (peak %.3f)" % [cat, s, peak]
			if peak > 0.9:
				return "%s %d: clips or runs hot (peak %.3f)" % [cat, s, peak]
			if f.lufs < -24.0:
				return "%s %d: too quiet (%.1f LUFS)" % [cat, s, f.lufs]
			var lim: Array = LENGTHS[cat]
			if f.length_s < lim[0] or f.length_s > lim[1]:
				return "%s %d: length %.3f s outside %s" % [cat, s, f.length_s, lim]
			if buf.first_above(0.01) > 0.01 * buf.sample_rate:
				return "%s %d: starts late (%d samples of silence)" % [cat, s, buf.first_above(0.01)]
	return ""


## The headless listening check: per category (median over seeds) the
## numbers that tell game sounds apart must point the right way, and no two
## categories may measure alike.
func test_categories_sound_distinct() -> String:
	var med := {}
	for cat in AKSfxGen.CATEGORIES:
		var rows := []
		for s in SEEDS:
			rows.append(AKSoundFeatures.of(AK.render(AKSfxGen.generate(cat, s))))
		var m := {}
		for k in ["length_s", "attack_s", "centroid_hz", "tonality", "onsets"]:
			m[k] = _median(rows.map(func(f: Dictionary) -> float: return float(f[k])))
		# Pitch direction in octaves, from the seeds where both ends were found.
		var dirs := []
		for f: Dictionary in rows:
			if f.pitch_start_hz > 20.0 and f.pitch_end_hz > 20.0:
				dirs.append(log(f.pitch_end_hz / f.pitch_start_hz) / log(2.0))
		m["pitch_oct"] = _median(dirs) if not dirs.is_empty() else 0.0
		med[cat] = m
	var checks := [
		[&"pickup", "pitch_oct", ">", 0.2], [&"pickup", "length_s", ">", 0.2],
		[&"jump", "pitch_oct", ">", 0.3], [&"laser", "pitch_oct", "<", -0.4],
		[&"hit", "pitch_oct", "<", -0.2], [&"hit", "length_s", "<", 0.5],
		[&"explosion", "length_s", ">", 0.9], [&"explosion", "centroid_hz", "<", 400.0], [&"explosion", "attack_s", "<", 0.15],
		[&"powerup", "pitch_oct", ">", 0.5], [&"powerup", "length_s", ">", 0.4],
		[&"ui_click", "length_s", "<", 0.1], [&"ui_click", "tonality", "<", 0.6],
		[&"ui_confirm", "pitch_oct", ">", 0.2], [&"ui_cancel", "pitch_oct", "<", -0.2],
		[&"blip", "length_s", "<", 0.15], [&"blip", "tonality", ">", 0.6],
	]
	for c in checks:
		var v: float = med[c[0]][c[1]]
		var ok: bool = v > c[3] if c[2] == ">" else (v >= c[3] if c[2] == ">=" else v < c[3])
		if not ok:
			return "%s: %s is %.3f, expected %s %.2f  (%s)" % [c[0], c[1], v, c[2], c[3], med[c[0]]]
	# Pairwise: every two categories differ clearly on at least one axis.
	var axes := {length_s = 0.4, centroid_hz = 0.25, pitch_oct = 0.35, tonality = 0.25}
	var cats := AKSfxGen.CATEGORIES
	for i in cats.size():
		for j in range(i + 1, cats.size()):
			var a: Dictionary = med[cats[i]]
			var b: Dictionary = med[cats[j]]
			var apart := false
			for k in axes:
				var d: float
				if k == "length_s" or k == "centroid_hz":
					d = absf(log(maxf(a[k], 1e-3) / maxf(b[k], 1e-3)) / log(2.0))   # octaves / doublings
				else:
					d = absf(float(a[k]) - float(b[k]))
				if d >= axes[k]:
					apart = true
			if not apart:
				return "%s and %s measure alike: %s vs %s" % [cats[i], cats[j], a, b]
	return ""


func _median(xs: Array) -> float:
	if xs.is_empty():
		return 0.0
	var s := xs.duplicate()
	s.sort()
	return float(s[s.size() / 2])


func test_mutate_is_close_and_deterministic() -> String:
	for cat in AKSfxGen.CATEGORIES:
		var r := AKSfxGen.generate(cat, 11)
		var a := AKSfxGen.mutate(r, 5)
		var b := AKSfxGen.mutate(r, 5)
		if var_to_str(a.describe()) != var_to_str(b.describe()):
			return "%s: mutate isn't deterministic" % cat
		if var_to_str(a.describe()) == var_to_str(r.describe()):
			return "%s: mutate changed nothing" % cat
		if a.voice != r.voice or a.layers.size() != r.layers.size() or a.fx.size() != r.fx.size():
			return "%s: mutate changed the recipe's shape" % cat
		if a.fx.back() != r.fx.back():
			return "%s: mutate touched the final normalise" % cat
		var v := AK.voice(a.voice)
		var schema := v.schema()
		for k in a.params:
			var s: Dictionary = schema.get(String(k), {})
			var x: Variant = a.params[k]
			if (x is float or x is int) and s.get("min") != null and (float(x) < float(s.min) - 1e-9 or float(x) > float(s.max) + 1e-9):
				return "%s: mutated %s = %s is out of range" % [cat, k, x]
		if a.get_meta(&"sfx_mutations") != 1 or AKSfxGen.mutate(a, 6).get_meta(&"sfx_mutations") != 2:
			return "%s: mutation count wrong" % cat
		var buf := AK.render(a)
		if _bad(buf) or buf.peak() < 0.5 or buf.peak() > 0.9:
			return "%s: a mutation renders badly (peak %.3f)" % [cat, buf.peak()]
	if AKSfxGen.name_for(AKSfxGen.mutate(AKSfxGen.generate(&"jump", 42), 1)) != "jump_42_m1":
		return "name_for: %s" % AKSfxGen.name_for(AKSfxGen.mutate(AKSfxGen.generate(&"jump", 42), 1))
	return ""


func test_random_generator_stays_usable() -> String:
	for s in range(1, 13):
		var r := AKSfxGen.generate(&"random", s)
		if var_to_str(r.describe()) != var_to_str(AKSfxGen.generate(&"random", s).describe()):
			return "random %d isn't deterministic" % s
		var buf := AK.render(r)
		if _bad(buf):
			return "random %d: NaN in the render" % s
		if buf.seconds() > 2.0 + 1e-3:
			return "random %d: %.2f s, longer than its 2 s trim" % [s, buf.seconds()]
		if buf.peak() < 0.5 or buf.peak() > 0.9:
			return "random %d: peak %.3f" % [s, buf.peak()]
	return ""


## The phase gate: ten game sounds, one per category, generated and baked to
## WAVs that load back as AudioStreamWAVs, in seconds rather than minutes.
func test_gate_ten_sounds_baked() -> String:
	DirAccess.make_dir_recursive_absolute(OUT)
	var t := Time.get_ticks_msec()
	var paths := []
	for cat in AKSfxGen.CATEGORIES:
		var r := AKSfxGen.generate(cat, 7)
		var path := OUT + "%s.wav" % AKSfxGen.name_for(r)
		var err := AK.bake_wav(r, path)
		if err != OK:
			return "%s: bake_wav failed (%s)" % [cat, error_string(err)]
		paths.append([path, r])
	var ms := Time.get_ticks_msec() - t
	if paths.size() != 10:
		return "expected ten sounds"
	for pr in paths:
		var wav := AudioStreamWAV.load_from_file(pr[0])
		if wav == null:
			return "couldn't load %s back" % pr[0]
		var baked := AK.bake(pr[1])
		if wav.data != baked.data or wav.mix_rate != 48000 or not wav.stereo or wav.format != AudioStreamWAV.FORMAT_16_BITS:
			return "%s: the WAV on disk differs from AK.bake" % pr[0]
		if wav.get_length() < 0.01:
			return "%s: empty" % pr[0]
	print("        ten sounds generated and baked in %d ms (native: %s)" % [ms, AKDsp.nat() != null])
	return "" if ms < 30000 else "baking ten sounds took %d ms" % ms


func test_recipe_stream_plays_and_varies() -> String:
	var r := AKSfxGen.generate(&"laser", 3)
	var s := AKRecipeStream.of(r, true, 4)
	if s.get_length() <= 0.0:
		return "no length"
	var pb := s.instantiate_playback()
	if pb == null:
		return "no playback"
	# A playback mixes exactly the baked samples.
	pb.start(0.0)
	var got := pb.mix_audio(1.0, 2048)
	var want := AK.bake(r, 1.0, {}, s.last_variant)
	var ok := false
	for i in got.size():
		if absf(got[i].x) > 0.01:
			ok = true
			break
	if not ok:
		return "the playback is silent"
	# Godot's WAV playback runs a couple of samples behind (interpolation):
	# find the lag, then the samples must match.
	var best := INF
	for lag in range(-4, 5):
		var e := 0.0
		for i in range(100, 1500):
			e = maxf(e, absf(got[i].x - float(want.data.decode_s16((i + lag) * 4)) / 32767.0))
		best = minf(best, e)
	if best > 1e-4:
		return "the playback doesn't play the baked samples (error %.5f)" % best
	var variants := {}
	for i in 24:
		s.instantiate_playback()
		variants[s.last_variant] = true
	if variants.size() < 3:
		return "plays should spread over the variants (%s)" % [variants.keys()]
	if s.stream_for(1) != s.stream_for(1):
		return "variants should be cached"
	if s.stream_for(0).data == s.stream_for(1).data:
		return "variants should differ (the recipe has vary)"
	s.vary_per_play = false
	for i in 5:
		s.instantiate_playback()
		if s.last_variant != 0:
			return "vary_per_play off should always play variant 0"
	return ""


func test_recipe_stream_in_players_and_randomizer() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var s := AKRecipeStream.of(AKSfxGen.generate(&"pickup", 2))
	s.warm()
	for p: Node in [AudioStreamPlayer.new(), AudioStreamPlayer2D.new(), AudioStreamPlayer3D.new()]:
		p.set(&"stream", s)
		tree.root.add_child(p)
		p.call(&"play")
		var playing: bool = p.call(&"has_stream_playback")
		p.queue_free()
		if not playing:
			return "%s didn't start a playback" % p.get_class()
	var rnd := AudioStreamRandomizer.new()
	rnd.add_stream(-1, s)
	rnd.add_stream(-1, AKRecipeStream.of(AKSfxGen.generate(&"pickup", 3)))
	var pb := rnd.instantiate_playback()
	pb.start(0.0)
	var mixed := pb.mix_audio(1.0, 4096)
	var peak := 0.0
	for v in mixed:
		peak = maxf(peak, absf(v.x))
	if peak < 0.05:
		return "silent inside an AudioStreamRandomizer (peak %.3f)" % peak
	# Saved and loaded as text, it still plays.
	DirAccess.make_dir_recursive_absolute(OUT)
	var path := OUT + "stream.tres"
	if ResourceSaver.save(s, path) != OK:
		return "couldn't save the stream"
	var back: AKRecipeStream = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if back == null or back.recipe == null or back.stream_for(0).data != s.stream_for(0).data:
		return "the saved stream doesn't play the same"
	return ""


func test_recipe_stream_bakes_wav() -> String:
	var s := AKRecipeStream.of(AKSfxGen.generate(&"hit", 4))
	s.wav_path = OUT + "hit_from_stream.wav"
	var path := s.bake_wav()
	if path != s.wav_path or not FileAccess.file_exists(path):
		return "bake_wav didn't write %s" % s.wav_path
	var wav := AudioStreamWAV.load_from_file(path)
	if wav == null or wav.data != s.stream_for(0).data:
		return "the baked WAV differs from what the stream plays"
	s.wav_path = ""
	s.resource_path = ""
	if not s.default_wav_path().begins_with("res://audio_kit/sfx/"):
		return "default path for an unsaved stream: %s" % s.default_wav_path()
	return ""


## Exported games without the native core render the same sounds in
## GDScript (within float rounding, as test_native checks for voices).
func test_generated_sounds_without_native() -> String:
	if AKDsp.nat() == null:
		return ""
	for cat in AKSfxGen.CATEGORIES:
		var r := AKSfxGen.generate(cat, 9)
		var a := AK.render(r)
		AKDsp.native_enabled = false
		var b := AK.render(r)
		AKDsp.native_enabled = true
		if a.frames() != b.frames():
			return "%s: lengths differ natively and in GDScript" % cat
		var worst := 0.0
		for i in a.frames():
			worst = maxf(worst, absf(a.l[i] - b.l[i]))
		if worst > 2e-3:
			return "%s: native and GDScript renders differ by %.5f" % [cat, worst]
	return ""


func test_lab_screen() -> String:
	var lab := AKSoundLab.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(lab)
	var out := _lab_checks(lab)
	lab.queue_free()
	return out


func _lab_checks(lab: AKSoundLab) -> String:
	if lab.recipe == null:
		return "the lab should open on a sound"
	var r := lab.generate(&"jump", 42)
	if var_to_str(r.describe()) != var_to_str(AKSfxGen.generate(&"jump", 42).describe()):
		return "the lab's jump 42 isn't AKSfxGen's"
	if lab.last_stats.is_empty() or lab.last_stats.length_s <= 0.0:
		return "generate should play and measure"
	if lab._seed.value != 42 or lab._name.text != "jump_42":
		return "seed or name not shown (%d, %s)" % [lab._seed.value, lab._name.text]
	lab._seed.value = 43
	if int(lab.recipe.get_meta(&"sfx_seed")) != 43 or String(lab.recipe.get_meta(&"sfx_category")) != "jump":
		return "typing a seed should regenerate that seed"
	var m := lab.mutate()
	if m == null or lab.recipe != m or int(m.get_meta(&"sfx_mutations")) != 1:
		return "mutate didn't replace the sound"
	var w := lab.randomise()
	if w == null or String(w.get_meta(&"sfx_category")) != "random":
		return "randomise should use the random generator"
	if lab.history.size() < 4:
		return "history should hold each sound (%d)" % lab.history.size()
	lab.restore(1)
	if lab.recipe != lab.history[1]:
		return "restore didn't bring back the earlier sound"
	# Edits replay.
	lab.generate(&"blip", 5)
	var before: float = lab.last_stats.length_s
	lab.recipe.params["gate_s"] = 0.4
	lab.recipe.emit_changed()
	lab._process(1.0)
	if lab.last_stats.length_s < before + 0.2:
		return "editing the recipe didn't replay it (%.2f -> %.2f s)" % [before, lab.last_stats.length_s]
	# Keep it: WAV, recipe, stream.
	lab._dir.text = OUT + "lab"
	lab._name.text = "my blip"
	var wav_path := lab.bake_wav()
	if wav_path != OUT + "lab/my_blip.wav" or AudioStreamWAV.load_from_file(wav_path) == null:
		return "Bake WAV wrote %s" % wav_path
	if AudioStreamWAV.load_from_file(wav_path).data != AK.bake(lab.recipe).data:
		return "the lab's WAV differs from AK.bake"
	var rp := lab.save_recipe()
	var back: AKRecipe = ResourceLoader.load(rp, "", ResourceLoader.CACHE_MODE_IGNORE)
	if back == null or var_to_str(back.describe()) != var_to_str(lab.recipe.describe()):
		return "the saved recipe doesn't load back the same (%s)" % rp
	if String(back.get_meta(&"sfx_category", "")) != "blip":
		return "the saved recipe lost its category"
	var sp := lab.save_stream()
	var st: AKRecipeStream = ResourceLoader.load(sp, "", ResourceLoader.CACHE_MODE_IGNORE)
	if st == null or st.recipe == null or st.stream_for(0).data != AK.bake(lab.recipe).data:
		return "the saved stream doesn't play the recipe (%s)" % sp
	lab._vary.button_pressed = true
	lab.play()
	lab.play()
	if lab._variant < 2:
		return "new variant each play should advance the variant"
	return ""


func test_dock_bakes_a_stream() -> String:
	var d := AKAuditionDock.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(d)
	var s := AKRecipeStream.of(AKSfxGen.generate(&"ui_confirm", 2))
	s.wav_path = OUT + "dock_stream.wav"
	d.show_resource(s)
	var out := ""
	if d.resource != s.recipe or d.stream != s:
		out = "the dock should show the stream's recipe"
	else:
		d.play()
		if d.last_stats.is_empty():
			out = "the dock didn't play the stream's recipe"
		elif d.bake_stream_wav() != s.wav_path or AudioStreamWAV.load_from_file(s.wav_path) == null:
			out = "the dock didn't bake the stream"
		else:
			d.show_resource(s.recipe)   # the same recipe on its own
			if d.stream != null:
				out = "showing a plain recipe should drop the stream"
	d.queue_free()
	return out
