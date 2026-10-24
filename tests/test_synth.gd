# SPDX-License-Identifier: Apache-2.0
# The synth engine (phase 2): patches, the engine in GDScript and native,
# voices rebuilt as patches, live play against bakes, polyphony and cost.
extends RefCounted

const SR := 48000


## A patch that touches most of the engine.
func _rich() -> AKPatch:
	var p := AKPatch.new()
	p.oscillators = [{shape = "saw", level = 0.5}, {shape = "pulse", width = 0.3, semitones = -12.0, level = 0.3, fm_from = 3, fm_index = 0.4},
		{shape = "morph", position = 0.4, level = 0.3, fm_from = 3, fm_index = 0.8}, {shape = "sine", level = 0.0, fm_from = 4, fm_index = 0.5}]
	p.unison = 3
	p.detune_cents = 12.0
	p.filter = {type = "lowpass", cutoff_hz = 700.0, q = 2.0, slope_db = 24.0}
	p.env2 = {attack_s = 0.0, decay_s = 0.2, sustain = 0.1, curve = "exp"}
	p.env3 = {attack_s = 0.05, decay_s = 0.1, sustain = 0.5, release_s = 0.1, curve = "linear"}
	p.lfo1 = {shape = "sine", rate_hz = 5.0, delay_s = 0.1}
	p.lfo2 = {shape = "random", rate_hz = 9.0}
	p.mods = [{source = "env2", dest = "cutoff", amount = 3.0}, {source = "lfo1", dest = "pitch", amount = 0.3},
		{source = "lfo2", dest = "osc2.width", amount = 0.2}, {source = "velocity", dest = "cutoff", amount = 1.0},
		{source = "env3", dest = "osc.position", amount = 0.3}, {source = "key", dest = "q", amount = 0.2},
		{source = "mod_wheel", dest = "amp", amount = -0.5}, {source = "bend", dest = "pan", amount = 0.5},
		{source = "random", dest = "osc3.fm", amount = 0.5}, {source = "aftertouch", dest = "osc1.level", amount = 0.3}]
	p.glide_s = 0.02
	p.seed = 7
	return p


func _notes() -> Array:
	return [{time_s = 0.0, note = "C3", length_s = 0.3, velocity = 0.8}, {time_s = 0.1, note = "E3", length_s = 0.3},
		{time_s = 0.15, mod_wheel = 0.5}, {time_s = 0.2, note = "G3", length_s = 0.4, velocity = 0.5},
		{time_s = 0.25, bend = 0.7}, {time_s = 0.3, aftertouch = 0.6}, {time_s = 0.35, note = "C3", length_s = 0.2}]


func _diff(a: AKBuffer, b: AKBuffer) -> float:
	if a.frames() != b.frames():
		return INF
	var w := 0.0
	for i in a.frames():
		w = maxf(w, maxf(absf(a.l[i] - b.l[i]), absf(a.r[i] - b.r[i])))
	return w


func _snr(ref: PackedFloat32Array, got: PackedFloat32Array) -> float:
	var n := mini(ref.size(), got.size())
	var s := 0.0
	var e := 0.0
	for i in n:
		s += ref[i] * ref[i]
		e += (ref[i] - got[i]) * (ref[i] - got[i])
	return 10.0 * log(s / maxf(e, 1e-30)) / log(10.0)


func test_compile_names_to_numbers() -> String:
	var p := _rich()
	var c := p.compile()
	if c.osc.size() != 4 or int(c.osc[0].shape) != 2 or int(c.osc[1].fm_from) != 2 or int(c.filter_type) != 1 or int(c.stages) != 2:
		return "oscillators or filter compiled wrong: %s" % [c]
	var row: Dictionary = c.mods[2]
	if int(row.src) != AKSynthCore.SRC_LFO2 or int(row.dst) != AKSynthCore.D_OWIDTH or int(row.osc) != 1:
		return "osc2.width compiled to %s" % [row]
	if int(c.mods[4].osc) != -1:
		return "osc.position should target every oscillator"
	p.mods = [{source = "nope", dest = "pitch", amount = 1.0}, {source = "lfo1", dest = "osc9.pitch", amount = 1.0}]
	if not p.compile().mods.is_empty():
		return "unknown mod rows should be dropped"
	return ""


func test_native_matches_gdscript() -> String:
	if AKDsp.nat() == null:
		return ""
	for patch in [_rich(), AKPatchLib.preset(&"saw_lead"), AKPatchLib.preset(&"strings"), AKPatchLib.preset(&"wobble_bass")]:
		var c: Dictionary = patch.compile()
		var ev := AKSynth.events_for(_notes())
		var a := AKSynth.render_events(c, ev, roundi(SR * 0.8))
		var b := AKSynth.render_events(c, ev, roundi(SR * 0.8), SR, true)
		var d := _diff(a, b)
		if d > 1e-6:
			return "%s: native and GDScript differ by %.2e" % [patch.resource_name, d]
		if a.peak() < 0.01:
			return "%s: silent" % patch.resource_name
	return ""


func test_deterministic_and_seeded() -> String:
	var p := _rich()
	p.oscillators.append({shape = "noise", level = 0.1})
	p.oscillators.remove_at(3)
	var a := AKSynth.render_notes(p, _notes(), 0.6)
	var b := AKSynth.render_notes(p, _notes(), 0.6)
	if _diff(a, b) != 0.0:
		return "the same notes rendered differently"
	p.seed = 8
	var c := AKSynth.render_notes(p, _notes(), 0.6)
	if _diff(a, c) == 0.0:
		return "a new seed should change the noise and unison phases"
	return ""


func test_voices_rebuilt_as_patches() -> String:
	# Same algorithm: within float rounding of the voice (tone), or close
	# (filter cutoffs and FM ratios go through different rounding).
	# Modulation runs at a control rate (every 8 samples), so a vibrato
	# steps where the voice's glides: still close, not exact.
	var exact := [[&"tone", {}, 100.0], [&"tone", {wave = &"saw", vibrato_hz = 6.0, vibrato_semitones = 0.5, sustain = 0.5}, 25.0],
		[&"tone", {wave = &"pulse", width = 0.2, attack_s = 0.01}, 100.0],
		[&"wavetable", {}, 30.0], [&"wavetable", {position = 0.2, sub = 0.5, q = 3.0}, 30.0],
		[&"fm", {}, 30.0], [&"fm", {ratio = 1.0, ratio2 = 3.0, index2 = 2.0}, 25.0]]
	for row in exact:
		var got := _voice_vs_patch(row[0], row[1])
		if got.snr < row[2]:
			return "%s %s: SNR %.1f dB against the voice (want %.0f)" % [row[0], row[1], got.snr, row[2]]
	# Different curve or phases: the measurements still agree.
	# (tone's glide curves in semitones, not Hz, so its first 50 ms differ:
	# compare where it lands and how it measures overall. Unison phases are
	# random, so a stack's harmonics cancel differently each seed: compare
	# loudness averaged over a few seeds; brightness and the strongest
	# partial depend on the phases.)
	for row in [[&"tone", {wave = &"square", end_hz = 220.0, glide_s = 0.05}], [&"wavetable", {unison = 3, detune_cents = 20.0}]]:
		var keys := ["length_s", "lufs"] if row[0] == &"wavetable" else ["pitch_end_hz", "centroid_hz", "length_s", "lufs"]
		var fa := {}
		var fb := {}
		var seeds := 4 if row[0] == &"wavetable" else 1
		for sd in seeds:
			var got := _voice_vs_patch(row[0], row[1], sd + 1)
			var a := AKSoundFeatures.of(AKBuffer.from_mono(got.voice))
			var b := AKSoundFeatures.of(AKBuffer.from_mono(got.patch))
			for k in keys:
				fa[k] = float(fa.get(k, 0.0)) + float(a[k]) / seeds
				fb[k] = float(fb.get(k, 0.0)) + float(b[k]) / seeds
		for k in keys:
			var tol := 2.0 if k == "lufs" else 0.08 * maxf(absf(fa[k]), 1.0)
			if absf(fa[k] - fb[k]) > tol:
				return "%s %s: %s %.2f (voice) vs %.2f (patch)" % [row[0], row[1], k, fa[k], fb[k]]
	return ""


func _voice_vs_patch(voice: StringName, params: Dictionary, seed := 1) -> Dictionary:
	var v := AK.voice(voice)
	var p := v.defaults()
	p.merge(params, true)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var a := v.render(p, SR, rng)
	var patch := AKPatchLib.from_voice(voice, params)
	patch.seed = seed
	var len_s: float = p.length_s if p.length_s > 0.0 else p.gate_s + 5.0 * p.release_s
	var b := AKSynth.render_note(patch, AKPatchLib.note_of(voice, params), 1.0, p.gate_s, len_s)
	return {snr = _snr(a, b.l), voice = a, patch = b.l}


func test_envelope_shapes() -> String:
	var p := AKPatch.new()
	p.oscillators = [{shape = "sine", level = 1.0}]
	p.filter = {type = "off"}
	p.velocity_sens = 0.0
	p.amp_env = {attack_s = 0.01, decay_s = 0.05, sustain = 0.5, release_s = 0.02}
	# A DC-ish reading of the envelope: a very low sine, sampled at its peaks
	# would be fiddly; instead read the engine's envelope directly.
	var core := AKSynthCore.new(p.compile())
	core.note_on(0, 60.0, 1.0)
	core.note_off(roundi(0.1 * SR), 60.0)
	var levels := []
	for i in roundi(0.2 * SR):
		core.render(1)
		levels.append(core.voices[0].level[0] if core.voices[0].active else 0.0)
	var want := AKEnv.adsr(roundi(0.2 * SR), SR, 0.01, 0.05, 0.5, 0.02, 0.1)
	for i in [0, 240, 480, 1200, 3000, 4799, 4800, 5000, 6000]:
		if absf(float(levels[i]) - want[i]) > 1e-5:
			return "amp envelope at %d: %.5f, AKEnv.adsr %.5f" % [i, levels[i], want[i]]
	core.render(SR / 2)
	if core.voice_count() != 0:
		return "the voice should be done after its release"
	return ""


func test_polyphony_and_stealing() -> String:
	var p := AKPatchLib.preset(&"pluck")
	p.polyphony = 4
	var core := AKSynthCore.new(p.compile())
	for i in 10:
		core.note_on(i * 100, 48.0 + i, 1.0)
	core.render(1200 + 4800)   # stolen voices fade out over a few ms
	if core.voice_count() != 4:
		return "polyphony 4 played %d voices" % core.voice_count()
	var notes := []
	for v in core.voices:
		if v.active:
			notes.append(v.note)
	notes.sort()
	if notes != [54.0, 55.0, 56.0, 57.0]:
		return "the oldest voices should be stolen (kept %s)" % [notes]
	core.all_notes_off(core.frame)
	core.render(SR * 3)
	return "" if core.voice_count() == 0 else "voices should end after release (%d left)" % core.voice_count()


func test_mono_legato_and_glide() -> String:
	var p := AKPatchLib.preset(&"saw_lead")   # legato, glide 0.06 s
	var core := AKSynthCore.new(p.compile())
	core.note_on(0, 60.0, 1.0)
	core.note_on(4800, 72.0, 1.0)
	core.render(4800 + 1440)
	var v: Object = core.voices[0]
	if core.voices.size() != 1 or v.stage[0] == AKSynthCore.ATTACK:
		return "legato should keep one voice and not restart its envelope"
	if not (v.cur > 60.5 and v.cur < 71.5):
		return "glide should be on its way (at %.2f)" % v.cur
	core.render(SR)
	if absf(v.cur - 72.0) > 0.01:
		return "glide should arrive (at %.2f)" % v.cur
	core.note_off(core.frame, 72.0)
	core.render(10)
	if absf(v.target - 60.0) > 1e-9 or not v.gated:
		return "releasing the top note should fall back to the held one"
	p.mode = "mono"
	var m := AKSynthCore.new(p.compile())
	m.note_on(0, 60.0, 1.0)
	m.note_on(4800, 64.0, 1.0)
	m.render(4801)
	if m.voices[0].stage[0] != AKSynthCore.ATTACK:
		return "mono should restart the envelope on each note"
	return ""


func test_bend_and_matrix_move_the_sound() -> String:
	var p := AKPatch.new()
	p.oscillators = [{shape = "sine", level = 1.0}]
	p.filter = {type = "off"}
	p.amp_env = {attack_s = 0.0, decay_s = 0.1, sustain = 1.0, release_s = 0.05}
	p.bend_range = 2.0
	var flat := AKSoundFeatures.of(AKSynth.render_notes(p, [{time_s = 0.0, note = 69, length_s = 0.5}]))
	var bent := AKSoundFeatures.of(AKSynth.render_notes(p, [{time_s = 0.0, bend = 1.0}, {time_s = 0.0, note = 69, length_s = 0.5}]))
	var semis := 12.0 * log(bent.pitch_start_hz / flat.pitch_start_hz) / log(2.0)
	if absf(flat.pitch_start_hz - 440.0) > 3.0 or absf(semis - 2.0) > 0.1:
		return "bend: %.1f Hz -> %.1f Hz (%.2f semitones, want 2)" % [flat.pitch_start_hz, bent.pitch_start_hz, semis]
	# Velocity opens a filter: brighter.
	var q := AKPatchLib.preset(&"brass")
	var soft := AKSoundFeatures.of(AKSynth.render_note(q, 60, 0.1, 0.4))
	var hard := AKSoundFeatures.of(AKSynth.render_note(q, 60, 1.0, 0.4))
	if hard.centroid_hz < soft.centroid_hz * 1.15:
		return "velocity -> cutoff: %.0f Hz soft, %.0f Hz hard" % [soft.centroid_hz, hard.centroid_hz]
	# An LFO on amp: tremolo.
	var t := AKPatchLib.preset(&"organ")
	var env: PackedFloat32Array = AKSoundFeatures.of(AKSynth.render_note(t, 60, 1.0, 1.0)).rms_env
	var lo := 0.0
	var hi := -100.0
	for i in range(20, 90):
		lo = minf(lo, env[i])
		hi = maxf(hi, env[i])
	if hi - lo < 1.0:
		return "lfo1 -> amp should wobble the level (%.2f dB)" % (hi - lo)
	return ""


## The phase gate, part 1: a patch played live matches its bake.
func test_live_matches_bake() -> String:
	if not AKSynth.available():
		return ""
	for patch in [_rich(), AKPatchLib.preset(&"fm_epiano")]:
		var s: Object = ClassDB.instantiate(&"AKSynthStream")
		s.patch = patch
		# Notes arrive while it plays, as a game would send them.
		s.render_offline(1000)
		s.note_on(48.0, 0.8, 0.0)
		s.render_offline(2000)
		s.note_on(55.0, 1.0, 0.01)
		s.set_mod_wheel(0.4, 0.015)
		s.render_offline(5000)
		s.note_off(48.0, 0.0)
		s.set_bend(-0.5, 0.002)
		s.render_offline(1234)
		s.note_off(55.0, 0.0)
		var lr: Array = s.render_offline(SR)
		var live := AKBuffer.new(0, SR)
		live.l = lr[0]
		live.r = lr[1]
		# The same events, baked on the same clock: the live engine had run
		# 1000 frames before the first note (its effects, like any running
		# effect, were already going), so the bake starts there too.
		var ev := [[1000, AKSynth.E_ON, 48.0, 0.8], [3000 + 480, AKSynth.E_ON, 55.0, 1.0], [3000 + 720, AKSynth.E_MOD, 0.4, 0.0],
			[8000, AKSynth.E_OFF, 48.0, 0.0], [8000 + 96, AKSynth.E_BEND, -0.5, 0.0], [9234, AKSynth.E_OFF, 55.0, 0.0]]
		var baked := AKSynth.render_events(patch.compile(), ev, 9234 + SR)
		var tail := AKBuffer.new(0, SR)
		tail.l = baked.l.slice(9234)
		tail.r = baked.r.slice(9234)
		var d := _diff(live, tail)
		if d > 1e-6 or live.peak() < 0.01:
			return "%s: live and baked differ by %.2e (peak %.3f)" % [patch.resource_name, d, live.peak()]
		var gd := AKSynth.render_events(patch.compile(), ev, 9234 + SR, SR, true)
		if _diff(baked, gd) > 1e-6:
			return "%s: the GDScript bake differs from live" % patch.resource_name
	return ""


func test_stream_plays_in_a_player() -> String:
	if not AKSynth.available():
		return ""
	var s: Object = ClassDB.instantiate(&"AKSynthStream")
	s.patch = AKPatchLib.preset(&"organ")
	var pb: AudioStreamPlayback = s.instantiate_playback()
	pb.start(0.0)
	s.note_on(60.0, 1.0)
	var out := pb.mix_audio(1.0, 4096)
	var peak := 0.0
	for v in out:
		peak = maxf(peak, absf(v.x))
	if peak < 0.05:
		return "the playback is silent (%.3f)" % peak
	# Editing the patch takes effect while it plays.
	var before: int = s.voice_count()
	s.patch.gain_db = -60.0
	s.patch.emit_changed()
	var quiet: Array = s.render_offline(4800)
	var qp := 0.0
	for i in range(2400, 4800):   # after the effects' delay lines have passed the old level
		qp = maxf(qp, absf(quiet[0][i]))
	if before != 1 or qp > peak * 0.01:
		return "a patch edit should apply live (voices %d, peak %.4f)" % [before, qp]
	return ""


## The phase gate, part 2: 32 voices of a two-oscillator patch (filter
## envelope, vibrato) under 10% of a core.
func test_32_voices_cost() -> String:
	if AKDsp.nat() == null:
		return ""
	var p := AKPatch.new()
	p.oscillators = [{shape = "saw", level = 0.5}, {shape = "square", cents = 7.0, level = 0.4}]
	p.filter = {type = "lowpass", cutoff_hz = 900.0, q = 1.5, slope_db = 12.0}
	p.amp_env = {attack_s = 0.01, decay_s = 0.3, sustain = 0.8, release_s = 0.3}
	p.env2 = {attack_s = 0.0, decay_s = 0.4, sustain = 0.3, curve = "exp"}
	p.mods = [{source = "env2", dest = "cutoff", amount = 2.0}, {source = "lfo1", dest = "pitch", amount = 0.1}]
	p.polyphony = 32
	var notes := []
	for i in 32:
		notes.append({time_s = 0.0, note = 36 + i, velocity = 0.8, length_s = 2.0})
	var ev := AKSynth.events_for(notes)
	var c := p.compile()
	var best := INF
	for attempt in 3:
		var t := Time.get_ticks_usec()
		AKSynth.render_events(c, ev, SR * 2)
		best = minf(best, (Time.get_ticks_usec() - t) / 1e6)
	var share := best / 2.0
	print("        32 voices: %.1f%% of a core (%.0f ms for 2 s)" % [share * 100.0, best * 1000.0])
	return "" if share < 0.10 else "32 voices take %.1f%% of a core" % (share * 100.0)


func test_patch_voice_in_a_recipe() -> String:
	var patch := AKPatchLib.preset(&"pluck")
	var r := AKRecipe.new()
	r.voice = &"patch"
	r.params = {patch = patch, freq_hz = 220.0, gate_s = 0.2}
	var a := AK.render(r)
	var direct := AKSynth.render_note(patch, 57.0, 1.0, 0.2)
	if _snr(direct.l, a.l) < 100.0:
		return "the patch voice should render the patch's note (SNR %.1f)" % _snr(direct.l, a.l)
	# The sequencer retunes it.
	var up := AK.render(r, 1.0, {}, 0, {_note_hz = 440.0})
	var fu := AKSoundFeatures.of(up)
	if absf(fu.pitch_start_hz - 440.0) > 20.0:
		return "retuned to 440 Hz but measures %.0f" % fu.pitch_start_hz
	# Editing the patch changes the bake key, by resource or by path.
	var k1 := AK.bake_key(r)
	patch.filter.cutoff_hz = 900.0
	if AK.bake_key(r) == k1:
		return "editing an embedded patch should change the bake key"
	var r2 := AKRecipe.new()
	r2.voice = &"patch"
	r2.params = {patch = "res://addons/audio_kit/patches/fm_bell.tres", freq_hz = 880.0}
	var bell: AKPatch = load("res://addons/audio_kit/patches/fm_bell.tres")
	var k2 := AK.bake_key(r2)
	var keep := bell.gain_db
	bell.gain_db = keep - 3.0
	var k3 := AK.bake_key(r2)
	bell.gain_db = keep
	if k2 == k3:
		return "editing a patch loaded by path should change the bake key"
	if AK.render(r2).peak() < 0.05:
		return "a patch by path didn't render"
	return ""


## Deep equality, numbers within 1e-9 relative (text loses the last bit).
func _close(a: Variant, b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		return absf(float(a) - float(b)) <= 1e-9 * maxf(1.0, absf(float(a)))
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not _close(a[k], b[k]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _close(a[i], b[i]):
				return false
		return true
	return a == b


func test_presets_load_and_play() -> String:
	for n in AKPatchLib.preset_names():
		var path := AKPatchLib.PRESET_DIR + n + ".tres"
		var p: AKPatch = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if p == null:
			return "%s doesn't load" % path
		if not _close(p.describe(), AKPatchLib.preset(StringName(n)).describe()):
			return "%s is stale: run tools/make_patches.gd" % path
		var buf := AKSynth.render_notes(p, [{time_s = 0.0, note = "C4", length_s = 0.4}, {time_s = 0.0, note = "E4", length_s = 0.4}], 1.2)
		var peak := buf.peak()
		if peak < 0.05 or peak > 2.0 or not is_finite(peak):
			return "%s: peak %.3f" % [n, peak]
	return ""


func test_dock_plays_a_patch() -> String:
	var d := AKAuditionDock.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(d)
	var patch := AKPatchLib.preset(&"fm_epiano")
	d.show_resource(patch)
	var out := ""
	if d.resource != patch:
		out = "the dock should show a patch"
	else:
		d.play_notes([{time_s = 0.0, note = "C4", length_s = 0.3}, {time_s = 0.0, note = "E4", length_s = 0.3}])
		if d.last_stats.is_empty() or d.last_stats.length_s < 0.3:
			out = "no stats after playing the patch"
		elif AKSynth.available():
			var lr: Array = d.synth.render_offline(2400)
			var peak := 0.0
			for x in lr[0]:
				peak = maxf(peak, absf(x))
			if peak < 0.05 or d.synth.voice_count() != 2:
				out = "the patch didn't play live (peak %.3f, voices %d)" % [peak, d.synth.voice_count()]
		if out == "":
			var path := d.save_wav()
			if path == "" or not FileAccess.file_exists(path):
				out = "Save WAV didn't write the patch's notes"
	d.stop()
	d.queue_free()
	return out
