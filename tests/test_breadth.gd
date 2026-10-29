# SPDX-License-Identifier: Apache-2.0
# Phase 4, sound breadth: the ladder filter, wavetables, hard sync, ring
# modulation, stereo unison, and the effects (chorus, flanger, phaser, eq,
# compressor, saturate) in patches, in recipes and on Godot buses.
extends RefCounted

const SR := 48000
const ALL_FX := [{type = "chorus"}, {type = "flanger"}, {type = "phaser"}, {type = "eq", low_db = 6.0, mid_db = -4.0, high_db = 3.0},
	{type = "compressor", threshold_db = -24.0}, {type = "saturate"}]


func _sine_patch() -> AKPatch:
	var p := AKPatch.new()
	p.oscillators = [{shape = "sine", level = 0.8}]
	p.filter = {type = "off"}
	p.amp_env = {attack_s = 0.0, decay_s = 0.1, sustain = 1.0, release_s = 0.05}
	p.velocity_sens = 0.0
	return p


func _diff(a: PackedFloat32Array, b: PackedFloat32Array, from := 0, to := -1) -> float:
	var n := mini(a.size(), b.size()) if to < 0 else to
	var d := 0.0
	for i in range(from, n):
		d = maxf(d, absf(a[i] - b[i]))
	return d


func _goertzel(x: PackedFloat32Array, start: int, n: int, f: float) -> float:
	var w := TAU * f / SR
	var c := 2.0 * cos(w)
	var s1 := 0.0
	var s2 := 0.0
	for i in n:
		var win := 0.5 - 0.5 * cos(TAU * i / (n - 1))
		var s0 := x[start + i] * win + c * s1 - s2
		s2 = s1
		s1 = s0
	return sqrt(maxf(0.0, s1 * s1 + s2 * s2 - c * s1 * s2)) / n * 4.0


func _rms(x: PackedFloat32Array, a: int, b: int) -> float:
	var s := 0.0
	for i in range(a, b):
		s += x[i] * x[i]
	return sqrt(s / maxf(1, b - a))


# ------------------------------------------------------------------ effects

func test_effects_native_matches_gdscript() -> String:
	var src := AKSynth.render_note(AKPatchLib.preset(&"saw_lead"), 48, 1.0, 0.3)
	for sp in ALL_FX:
		var a := AKStreamFx.process([sp], src.l, src.r, SR)
		if AKDsp.nat() != null:
			AKDsp.native_enabled = false
			var b := AKStreamFx.process([sp], src.l, src.r, SR)
			AKDsp.native_enabled = true
			var d := _diff(a[0], b[0]) + _diff(a[1], b[1])
			if d > 1e-6:
				return "%s: native and GDScript differ by %.2e" % [sp.type, d]
		if _diff(a[0], src.l) < 0.01:
			return "%s changed nothing" % sp.type
	return ""


func test_effects_do_what_they_say() -> String:
	var n := SR
	var sine := PackedFloat32Array()
	var noise := PackedFloat32Array()
	sine.resize(n)
	noise.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in n:
		sine[i] = 0.5 * sin(TAU * 1000.0 * i / SR)
		noise[i] = rng.randf_range(-0.5, 0.5)
	# EQ: +12 dB low shelf at 200 Hz lifts 50 Hz by about 12 dB, leaves 5 kHz.
	var lo := PackedFloat32Array()
	lo.resize(n)
	for i in n:
		lo[i] = 0.1 * sin(TAU * 50.0 * i / SR) + 0.1 * sin(TAU * 5000.0 * i / SR)
	var eq := AKStreamFx.process([{type = "eq", low_db = 12.0, low_hz = 200.0}], lo, lo, SR)
	var g50 := 20.0 * log(_goertzel(eq[0], n / 2, 8192, 50.0) / _goertzel(lo, n / 2, 8192, 50.0)) / log(10.0)
	var g5k := 20.0 * log(_goertzel(eq[0], n / 2, 8192, 5000.0) / _goertzel(lo, n / 2, 8192, 5000.0)) / log(10.0)
	if absf(g50 - 12.0) > 0.7 or absf(g5k) > 0.3:
		return "eq low shelf: %+.1f dB at 50 Hz (want +12), %+.1f at 5 kHz (want 0)" % [g50, g5k]
	# Compressor: a steady -6 dBFS sine, threshold -18, ratio 4, hard knee:
	# 12 dB over -> 9 dB of gain reduction once settled.
	var comp := AKStreamFx.process([{type = "compressor", threshold_db = -18.0, ratio = 4.0, knee_db = 0.0, attack_s = 0.005}], sine, sine, SR)
	var red := 20.0 * log(_rms(comp[0], n / 2, n) / _rms(sine, n / 2, n)) / log(10.0)
	if absf(red + 9.0) > 1.0:   # a peak detector on a sine: a little under the static curve
		return "compressor: %.2f dB of reduction (want about -9)" % red
	# Saturate: a sine grows odd harmonics.
	var sat := AKStreamFx.process([{type = "saturate", drive_db = 18.0, tone_hz = 18000.0}], sine, sine, SR)
	var h3 := _goertzel(sat[0], n / 2, 8192, 3000.0) / _goertzel(sat[0], n / 2, 8192, 1000.0)
	if h3 < 0.05:
		return "saturate should add a third harmonic (%.3f of the fundamental)" % h3
	# Chorus: stereo out of mono in; the wet signal moves (the left and right differ).
	var ch := AKStreamFx.process([{type = "chorus", mix = 0.5}], sine, sine, SR)
	if _diff(ch[0], ch[1], n / 2) < 0.01:
		return "chorus should make left and right differ"
	# Phaser on noise: the spectrum gets moving notches; at least the output
	# isn't the input and stays the same level within a few dB.
	var ph := AKStreamFx.process([{type = "phaser", mix = 0.5, rate_hz = 1.0}], noise, noise, SR)
	var lv := 20.0 * log(_rms(ph[0], 0, n) / _rms(noise, 0, n)) / log(10.0)
	if absf(lv) > 4.0 or _diff(ph[0], noise) < 0.05:
		return "phaser level %.1f dB" % lv
	# Flanger with feedback rings: an impulse leaves a decaying comb.
	var imp := PackedFloat32Array()
	imp.resize(n / 4)
	imp[0] = 1.0
	var fl := AKStreamFx.process([{type = "flanger", feedback = 0.8, mix = 1.0, depth_ms = 0.0, delay_ms = 2.0}], imp, imp, SR)
	var echo2 := absf(fl[0][192])   # second echo at 2 x 2 ms (linear between samples)
	if echo2 < 0.5:
		return "flanger feedback: echo at 4 ms is %.3f (want about 0.8)" % echo2
	return ""


## The phase gate: an effect sounds the same in a patch, a bake (a recipe's
## effect chain) and on a Godot bus.
func test_gate_same_effect_everywhere() -> String:
	var dry := _sine_patch()
	dry.oscillators = [{shape = "saw", level = 0.5}, {shape = "square", semitones = 7.0, level = 0.3}]
	for sp in ALL_FX:
		var chain: Array[Dictionary] = [sp]
		# 1. In a patch: the engine runs the effect on its output.
		var wet := dry.duplicate(true) as AKPatch
		wet.effects = chain
		var in_patch := AKSynth.render_note(wet, 57, 1.0, 0.4, 0.9)
		# 2. In a bake: a recipe of the dry patch with the effect in its fx.
		var r := AKRecipe.new()
		r.voice = &"patch"
		r.params = {patch = dry, freq_hz = AKNotes.midi_to_hz(57), gate_s = 0.4, length_s = 0.9}
		r.fx = chain
		var baked := AK.render(r)
		var n := mini(in_patch.frames(), baked.frames())
		var d1 := _diff(in_patch.l, baked.l, 0, n) + _diff(in_patch.r, baked.r, 0, n)
		if d1 > 1e-5:
			return "%s: patch and bake differ by %.2e" % [sp.type, d1]
		# 3. On a bus: the bus effect's own instance, over the dry signal.
		if not ClassDB.class_exists(&"AKChorus"):
			continue
		var cls: String = {"chorus": "AKChorus", "flanger": "AKFlanger", "phaser": "AKPhaser", "eq": "AKEQ3",
			"compressor": "AKCompressor", "saturate": "AKSaturate"}[sp.type]
		var bus_fx: Object = ClassDB.instantiate(StringName(cls))
		for k in sp:
			if k != "type":
				bus_fx.set(k, sp[k])
		var plain := AKSynth.render_note(dry, 57, 1.0, 0.4, 0.9)
		var on_bus: Array = bus_fx.process_offline(plain.l, plain.r, SR)
		var d2 := _diff(on_bus[0], in_patch.l, 0, n) + _diff(on_bus[1], in_patch.r, 0, n)
		if d2 > 1e-5:
			return "%s: bus effect and patch differ by %.2e" % [sp.type, d2]
	return ""


## The same, through a real Godot bus while the audio server mixes: a dry
## sound plays on a bus carrying AKEQ3, AKCompressor and AKSaturate and is
## captured after them. (Effects without an LFO, so the time the bus spent
## on silence before the sound doesn't matter.)
func test_gate_on_a_running_bus() -> String:
	if not ClassDB.class_exists(&"AKEQ3"):
		return ""
	var tree := Engine.get_main_loop() as SceneTree
	var dry := _sine_patch()
	dry.oscillators = [{shape = "saw", level = 0.5}]
	var buf := AKSynth.render_note(dry, 57, 1.0, 0.3, 0.5)
	var wav := buf.to_stream()
	var specs := [{type = "eq", low_db = 4.0, high_db = -6.0}, {type = "compressor", threshold_db = -20.0, ratio = 3.0},
		{type = "saturate", drive_db = 9.0}]
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, "ak_fx_test")
	for sp: Dictionary in specs:
		var e: Object = ClassDB.instantiate({"eq": &"AKEQ3", "compressor": &"AKCompressor", "saturate": &"AKSaturate"}[sp.type])
		for k in sp:
			if k != "type":
				e.set(k, sp[k])
		AudioServer.add_bus_effect(idx, e)
	var cap := AudioEffectCapture.new()
	cap.buffer_length = 2.0
	AudioServer.add_bus_effect(idx, cap)
	var p := AudioStreamPlayer.new()
	p.bus = &"ak_fx_test"
	p.stream = wav
	tree.root.add_child(p)
	p.play()
	var got := PackedVector2Array()
	for i in 240:
		await tree.process_frame
		got.append_array(cap.get_buffer(cap.get_frames_available()))
		if got.size() > SR * 0.8:
			break
	p.queue_free()
	AudioServer.remove_bus(idx)
	if got.size() < SR * 0.5:
		return "the bus captured only %d frames (is the audio server mixing?)" % got.size()
	# What the WAV holds (16-bit), through the same chain offline.
	var src_l := PackedFloat32Array()
	src_l.resize(wav.data.size() / 4)
	for i in src_l.size():
		src_l[i] = wav.data.decode_s16(i * 4) / 32767.0
	var want := AKStreamFx.process(specs, src_l, src_l, SR)
	# Find where the sound starts in the capture (Godot's WAV playback runs a
	# couple of samples behind), then compare.
	var start := -1
	for i in got.size():
		if absf(got[i].x) > 1e-4:
			start = i
			break
	var first := -1
	for i in want[0].size():
		if absf(want[0][i]) > 1e-4:
			first = i
			break
	var best := INF
	for lag in range(-4, 5):
		var e := 0.0
		for i in range(0, 20000):
			var j := start - first + i + lag
			if j < 0 or j >= got.size():
				continue
			e = maxf(e, absf(got[j].x - want[0][i]))
		best = minf(best, e)
	return "" if best < 1e-3 else "the running bus differs from the offline chain by %.4f" % best


func test_bus_effects_register_and_keep_settings() -> String:
	if not ClassDB.class_exists(&"AKChorus"):
		return ""
	for cls in [&"AKChorus", &"AKFlanger", &"AKPhaser", &"AKEQ3", &"AKCompressor", &"AKSaturate"]:
		if not ClassDB.is_parent_class(cls, &"AudioEffect"):
			return "%s should be an AudioEffect" % cls
	var c: Resource = ClassDB.instantiate(&"AKChorus")
	c.set(&"rate_hz", 1.7)
	c.set(&"voices", 3)
	var path := "user://ak_chorus_test.tres"
	if ResourceSaver.save(c, path) != OK:
		return "couldn't save a bus effect"
	var back: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if back == null or not is_equal_approx(float(back.get(&"rate_hz")), 1.7) or int(back.get(&"voices")) != 3:
		return "a saved AKChorus should keep its settings (%s)" % (back.call(&"get_spec") if back else null)
	var spec: Dictionary = back.call(&"get_spec")
	if spec.type != "chorus" or not is_equal_approx(float(spec.rate_hz), 1.7):
		return "get_spec: %s" % spec
	return ""


# ------------------------------------------------------------------ modules

func test_ladder_filter() -> String:
	var p := _sine_patch()
	p.oscillators = [{shape = "noise", level = 0.1}]
	p.filter = {type = "ladder", cutoff_hz = 1000.0, resonance = 0.0}
	var flat := AKSynth.render_note(p, 60, 1.0, 1.0)
	# 24 dB per octave: two octaves above the cutoff is about 48 dB down
	# (measured against an octave below).
	var below := _goertzel(flat.l, 8000, 16384, 500.0)
	var above := _goertzel(flat.l, 8000, 16384, 4000.0)
	var slope := 20.0 * log(above / below) / log(10.0)
	if slope > -35.0:
		return "ladder slope: 4 kHz is only %.1f dB under 500 Hz" % slope
	# Resonance near 1 rings at the cutoff: a peak there on noise.
	p.filter = {type = "ladder", cutoff_hz = 1000.0, resonance = 0.95}
	var res := AKSynth.render_note(p, 60, 1.0, 1.0)
	var at := _goertzel(res.l, 8000, 16384, 1000.0)
	var off := _goertzel(res.l, 8000, 16384, 600.0)
	if at < off * 3.0:
		return "a resonant ladder should peak at its cutoff (%.4f vs %.4f)" % [at, off]
	return ""


func test_wavetables() -> String:
	# Band-limited: a high note keeps only harmonics below Nyquist (no aliases).
	var p := _sine_patch()
	p.oscillators = [{shape = "table", table = "basic", position = 1.0 / 3.0 * 2.0, level = 0.6}]   # the saw frame
	var hz := AKNotes.midi_to_hz(100)   # 2637 Hz: 9 harmonics under Nyquist
	var b := AKSynth.render_note(p, 100, 1.0, 0.5)
	var harm := 0.0
	var alias := 0.0
	for k in range(1, 10):
		harm += _goertzel(b.l, 2000, 8192, hz * k)
	for f in [hz * 1.5, hz * 2.5, 48000.0 - hz * 10.0, 48000.0 - hz * 11.0]:
		if f > 50.0 and f < 23900.0:
			alias = maxf(alias, _goertzel(b.l, 2000, 8192, f))
	if alias > harm * 0.002:
		return "aliasing in the table oscillator: %.5f against %.4f of harmonics" % [alias, harm]
	# Position sweeps frames: the sine frame is darker than the square frame.
	p.oscillators = [{shape = "table", table = "basic", position = 0.0, level = 0.6}]
	var s0 := AKSoundFeatures.of(AKSynth.render_note(p, 48, 1.0, 0.4))
	p.oscillators = [{shape = "table", table = "basic", position = 1.0, level = 0.6}]
	var s1 := AKSoundFeatures.of(AKSynth.render_note(p, 48, 1.0, 0.4))
	if s1.centroid_hz < s0.centroid_hz * 2.0:
		return "position 1 (square) should be much brighter than 0 (sine): %.0f vs %.0f Hz" % [s1.centroid_hz, s0.centroid_hz]
	# Samples and harmonics describe the same table.
	var cyc := []
	for i in 256:
		cyc.append(sin(TAU * i / 256.0) + 0.5 * sin(TAU * 3.0 * i / 256.0))
	var ts := AKWavetables.build({frames = [{samples = cyc}]})
	var th := AKWavetables.build({frames = [{harmonics = [1.0, 0.0, 0.5]}]})
	var d := _diff(ts.data, th.data)
	if d > 0.01:
		return "a table from samples and the same from harmonics differ by %.4f" % d
	for name in AKWavetables.BUILTIN:
		var t := AKWavetables.build(name)
		if t.frames < 1 or t.data.size() != t.frames * AKWavetables.LEVELS * AKWavetables.SIZE:
			return "built-in table %s is malformed" % name
	return ""


func test_sync_and_ring() -> String:
	# Hard sync: a saw synced to a sine at the note keeps the note's pitch
	# whatever its own tuning.
	var p := _sine_patch()
	p.oscillators = [{shape = "sine", level = 0.0}, {shape = "saw", level = 0.6, sync_to = 1, semitones = 5.0}]
	var f := AKSoundFeatures.of(AKSynth.render_note(p, 57, 1.0, 0.5))
	var semis := 12.0 * log(f.pitch_start_hz / 220.0) / log(2.0)
	if absf(semis) > 0.3 and absf(semis - 12.0) > 0.3:
		return "a synced saw should sound at its master's pitch (220 Hz; measured %.1f Hz)" % f.pitch_start_hz
	var no_sync := _sine_patch()
	no_sync.oscillators = [{shape = "saw", level = 0.6, semitones = 5.0}]
	var g := AKSoundFeatures.of(AKSynth.render_note(no_sync, 57, 1.0, 0.5))
	if absf(12.0 * log(g.pitch_start_hz / 220.0) / log(2.0) - 5.0) > 0.3:
		return "without sync it plays 5 semitones up (%.1f Hz)" % g.pitch_start_hz
	# Ring modulation: 440 x 660 gives 220 and 1100, not 440 or 660.
	var r := _sine_patch()
	r.oscillators = [{shape = "sine", level = 0.8, ring_from = 2}, {shape = "sine", level = 0.0, semitones = 12.0 * log(1.5) / log(2.0)}]
	var rb := AKSynth.render_note(r, 69, 1.0, 0.5)
	var e220 := _goertzel(rb.l, 4000, 8192, 220.0)
	var e1100 := _goertzel(rb.l, 4000, 8192, 1100.0)
	var e440 := _goertzel(rb.l, 4000, 8192, 440.0)
	if e220 < 0.1 or e1100 < 0.1 or e440 > 0.01:
		return "ring modulation: 220 Hz %.3f, 1100 Hz %.3f, 440 Hz %.3f" % [e220, e1100, e440]
	return ""


func test_stereo_unison_spread() -> String:
	var p := _sine_patch()
	p.oscillators = [{shape = "saw", level = 0.6}]
	p.unison = 5
	p.detune_cents = 20.0
	var mono := AKSynth.render_note(p, 48, 1.0, 0.5)
	if _diff(mono.l, mono.r) != 0.0:
		return "spread 0 should stay mono"
	p.spread = 1.0
	var wide := AKSynth.render_note(p, 48, 1.0, 0.5)
	var lr := _diff(wide.l, wide.r)
	if lr < 0.05:
		return "spread 1 should make the channels differ (%.3f)" % lr
	var ml := AKDynamics.lufs(mono)
	var wl := AKDynamics.lufs(wide)
	if absf(ml - wl) > 1.5:
		return "spreading shouldn't change the loudness much: %.1f vs %.1f LUFS" % [ml, wl]
	return ""


func test_new_presets_and_bank_play() -> String:
	for n in ["sync_lead", "vowel_pad", "ring_bell", "pwm_strings", "acid_bass", "strings", "organ", "wobble_bass"]:
		var p := AKPatchLib.preset(StringName(n))
		var b := AKSynth.render_note(p, 60, 1.0, 0.5)
		if b.peak() < 0.3 or b.peak() > 0.7:
			return "%s: one note peaks at %.3f (want about 0.5)" % [n, b.peak()]
		if AKDsp.nat() != null:
			var c := p.compile()
			var ev := AKSynth.events_for([{time_s = 0.0, note = 60, length_s = 0.2}, {time_s = 0.05, note = 67, length_s = 0.2}])
			var a := AKSynth.render_events(c, ev, 14400)
			var g := AKSynth.render_events(c, ev, 14400, SR, true)
			if _diff(a.l, g.l) + _diff(a.r, g.r) > 1e-6:
				return "%s: native and GDScript differ" % n
	return ""
