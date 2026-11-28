# SPDX-License-Identifier: Apache-2.0
# Phase 4, sound breadth: the ladder filter, wavetables, hard sync, ring
# modulation, stereo unison, and the effects (chorus, flanger, phaser, eq,
# compressor, saturate) in patches, in recipes and on Godot buses.
extends RefCounted

const SR := 48000
const ALL_FX := [{type = "chorus"}, {type = "flanger"}, {type = "phaser"}, {type = "eq", low_db = 6.0, mid_db = -4.0, high_db = 3.0},
	{type = "compressor", threshold_db = -24.0}, {type = "saturate"}, {type = "pitch"}, {type = "pitch", semitones = 7.0},
	{type = "ring", rate_hz = 0.5, depth = 0.5}, {type = "growl"}, {type = "crush", bits = 6.0, hold = 3},
	{type = "delay", time_ms = 50.0}, {type = "reverb"}, {type = "freqshift"}, {type = "freqshift", shift_hz = -30.0, stereo = 1.0, feedback = 0.6, echo_ms = 40.0},
	{type = "rotary"}, {type = "rotary", speed = "fast", drive = 0.5, spread = 0.6}]


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


## Separate dry and wet gains: unset (or set to what mix gives) the effect is unchanged; set, the
## wet can pass 1 (Surge's reverbs and inserts), and both engines agree.
func test_effects_dry_and_wet() -> String:
	var src := AKSynth.render_note(AKPatchLib.preset(&"saw_lead"), 48, 1.0, 0.3)
	for t in ["chorus", "flanger", "phaser", "saturate", "pitch", "ring", "growl", "crush", "delay", "reverb", "freqshift", "rotary"]:
		var sp: Dictionary = {type = t}
		sp.merge(AKStreamFx.DEFAULTS[t])
		var base := AKStreamFx.process([sp], src.l, src.r, SR)
		var same := sp.duplicate()
		var mix := float(sp.mix)
		same.dry = 1.0 if t in ["delay", "reverb"] else 1.0 - mix
		same.wet = mix
		var b := AKStreamFx.process([same], src.l, src.r, SR)
		if _diff(base[0], b[0]) + _diff(base[1], b[1]) != 0.0:
			return "%s: dry and wet as mix gives should change nothing" % t
		var loud := sp.duplicate()
		loud.dry = 0.3
		loud.wet = 1.6
		var c := AKStreamFx.process([loud], src.l, src.r, SR)
		if _diff(base[0], c[0]) < 0.01:
			return "%s: dry 0.3, wet 1.6 should change the sound" % t
		if AKDsp.nat() != null:
			AKDsp.native_enabled = false
			var g := AKStreamFx.process([loud], src.l, src.r, SR)
			AKDsp.native_enabled = true
			if _diff(c[0], g[0]) + _diff(c[1], g[1]) > 1e-6:
				return "%s: dry and wet, native and GDScript differ" % t
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
			return "%s: patch and bake differ by %s" % [sp, d1]
		# 3. On a bus: the bus effect's own instance, over the dry signal.
		if not ClassDB.class_exists(&"AKChorus"):
			continue
		var cls: String = {"chorus": "AKChorus", "flanger": "AKFlanger", "phaser": "AKPhaser", "eq": "AKEQ3",
			"compressor": "AKCompressor", "saturate": "AKSaturate"}.get(sp.type, "")
		if cls.is_empty():
			continue   # the character effects have no bus effect
		var bus_fx: Object = ClassDB.instantiate(StringName(cls))
		for k in sp:
			if k != "type":
				bus_fx.set(k, sp[k])
		var plain := AKSynth.render_note(dry, 57, 1.0, 0.4, 0.9)
		var on_bus: Array = bus_fx.process_offline(plain.l, plain.r, SR)
		var d2 := _diff(on_bus[0], in_patch.l, 0, n) + _diff(on_bus[1], in_patch.r, 0, n)
		if d2 > 1e-5:
			return "%s: bus effect and patch differ by %s" % [sp.type, d2]
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
	for cls in [&"AKChorus", &"AKFlanger", &"AKPhaser", &"AKEQ3", &"AKCompressor", &"AKSaturate", &"AKLimiter", &"AKFreqShift", &"AKRotary"]:
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


## The limiter: a hot signal (peaks 9 dB over full scale) comes out no higher than the
## ceiling; a quiet one comes out bit for bit; native, GDScript, AKDynamics.limit, the bus
## effect (its own blocks) and a patch played live in odd-sized blocks all agree.
func test_limiter() -> String:
	var src := AKSynth.render_note(AKPatchLib.preset(&"saw_lead"), 48, 1.0, 0.3)
	var pk := 0.0
	for i in src.frames():
		pk = maxf(pk, maxf(absf(src.l[i]), absf(src.r[i])))
	var hot_g := pow(10.0, 9.0 / 20.0) / pk
	var hl := src.l.duplicate()
	var hr := src.r.duplicate()
	for i in hl.size():
		hl[i] *= hot_g
		hr[i] *= hot_g
	var spec := {type = "limiter", ceiling_db = -1.0}
	var ceiling := pow(10.0, -1.0 / 20.0)
	var paths := [true, false] if AKDsp.nat() != null else [true]
	var outs := []
	for gd: bool in paths:
		AKDsp.native_enabled = not gd
		var o := AKStreamFx.process([spec], hl, hr, SR)
		AKDsp.native_enabled = true
		var top := 0.0
		for ch in 2:
			for x in (o[ch] as PackedFloat32Array):
				top = maxf(top, absf(x))
		if top > ceiling * (1.0 + 1e-6):
			return "%s: the limiter let %.2f dBFS through" % ["GDScript" if gd else "native", 20.0 * log(top) / log(10.0)]
		# A signal under the ceiling passes unchanged.
		var q := AKStreamFx.process([spec], src.l.duplicate(), src.r.duplicate(), SR) if pk < ceiling else [src.l, src.r]
		if _diff(q[0], src.l) != 0.0 or _diff(q[1], src.r) != 0.0:
			return "a signal under the ceiling should pass bit for bit"
		outs.append(o)
	if outs.size() == 2 and _diff(outs[0][0], outs[1][0]) + _diff(outs[0][1], outs[1][1]) > 1e-6:
		return "native and GDScript limiters differ"
	# The same as AKDynamics.limit on the whole buffer.
	var b := AKBuffer.new(0, SR)
	b.l = hl.duplicate()
	b.r = hr.duplicate()
	AKDynamics.limit(b, -1.0, 0.08)
	if _diff(b.l, outs[0][0]) + _diff(b.r, outs[0][1]) > 1e-6:
		return "the streaming limiter should match AKDynamics.limit"
	# The bus effect, which runs in its own blocks.
	if ClassDB.class_exists(&"AKLimiter"):
		var bus: Object = ClassDB.instantiate(&"AKLimiter")
		bus.set(&"ceiling_db", -1.0)
		var on_bus: Array = bus.process_offline(hl, hr, SR)
		if _diff(on_bus[0], outs[0][0]) + _diff(on_bus[1], outs[0][1]) > 1e-6:
			return "the AKLimiter bus effect should match the patch effect"
	# A patch whose onsets spike (a resonant ladder thrown by its envelope) with the limiter
	# last: under the ceiling, and the same live (odd blocks) as baked.
	var p := AKPatch.new()
	p.oscillators = [{shape = "saw", level = 0.9}, {shape = "square", semitones = 7.0, level = 0.6}]
	p.filter = {type = "ladder", cutoff_hz = 272.0, resonance = 0.8, drive = 3.0}
	p.env2 = {attack_s = 0.04, decay_s = 0.08, sustain = 0.0, release_s = 0.1}
	p.mods = [{source = "env2", dest = "cutoff", amount = 5.0}, {source = "velocity", dest = "cutoff", amount = 2.0}]
	p.gain_db = 6.0
	var notes := [{time_s = 0.0, note = 40, length_s = 0.5, velocity = 0.85}, {time_s = 0.3, note = 47, length_s = 0.5, velocity = 0.85}]
	var ev := AKSynth.events_for(notes)
	var raw := AKSynth.render_events(p.compile(), ev, SR, SR, true)
	if raw.peak() <= 1.0:
		return "the test patch should go over full scale without the limiter (peak %.2f)" % raw.peak()
	p.effects = [{type = "limiter", ceiling_db = -1.0}]
	var baked := AKSynth.render_events(p.compile(), ev, SR, SR, true)
	if baked.peak() > ceiling * (1.0 + 1e-6):
		return "the patch's limiter let %.2f through" % baked.peak()
	if AKSynth.available():
		var nb := AKSynth.render_events(p.compile(), ev, SR, SR)
		if _diff(nb.l, baked.l) + _diff(nb.r, baked.r) > 1e-6:
			return "native and GDScript patch limiters differ"
		var s: Object = ClassDB.instantiate(&"AKSynthStream")
		s.patch = p
		s.note_on(40.0, 0.85, 0.0)
		s.note_on(47.0, 0.85, 0.3)
		s.note_off(40.0, 0.5)
		s.note_off(47.0, 0.8)
		var ll := PackedFloat32Array()
		var lr := PackedFloat32Array()
		var left := SR
		var sizes := [1, 37, 512, 1031, 4096]
		var k := 0
		while left > 0:
			var n := mini(left, sizes[k % sizes.size()])
			var part: Array = s.render_offline(n)
			ll.append_array(part[0])
			lr.append_array(part[1])
			left -= n
			k += 1
		if _diff(ll, baked.l) + _diff(lr, baked.r) > 1e-6:
			return "the limiter live (odd blocks) should match the bake"
	if AKStreamFx.tail_s([spec]) != 0.0:
		return "the limiter adds no tail"
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
		if t.frames < 1 or t.levels < 1 or t.data.size() != t.zones * t.frames * t.levels * AKWavetables.SIZE:
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


## The reverb's input options: a predelay holds the tail back by that much; a high cut on its
## input darkens the tail; at their defaults (0) nothing changes; native and GDScript agree.
func test_reverb_predelay_and_cuts() -> String:
	var n := 24000
	var l := PackedFloat32Array()
	l.resize(n)
	l[100] = 1.0   # a click
	var r := l.duplicate()
	var base := AKStreamFx.process([{type = "reverb", mix = 1.0}], l.duplicate(), r.duplicate(), SR)
	var same := AKStreamFx.process([{type = "reverb", mix = 1.0, predelay_ms = 0.0, low_cut_hz = 0.0, high_cut_hz = 0.0}], l.duplicate(), r.duplicate(), SR)
	if _diff(base[0], same[0]) != 0.0:
		return "a reverb with the input options at 0 should be unchanged"
	var first := func(x: PackedFloat32Array) -> int:
		for i in range(101, x.size()):
			if absf(x[i]) > 1e-6:
				return i
		return -1
	var pre := AKStreamFx.process([{type = "reverb", mix = 1.0, predelay_ms = 50.0}], l.duplicate(), r.duplicate(), SR)
	var lag: int = first.call(pre[0]) - first.call(base[0])
	if absf(lag - 2400) > 2:
		return "a 50 ms predelay should hold the tail back 2400 samples (%d)" % lag
	var dark := AKStreamFx.process([{type = "reverb", mix = 1.0, high_cut_hz = 1000.0}], l.duplicate(), r.duplicate(), SR)
	if _goertzel(dark[0], 4800, 9600, 6000.0) > 0.5 * _goertzel(base[0], 4800, 9600, 6000.0):
		return "a 1 kHz high cut should darken the tail"
	if AKDsp.nat() != null:
		var spec := {type = "reverb", mix = 0.5, predelay_ms = 30.0, low_cut_hz = 200.0, high_cut_hz = 3000.0}
		var a := AKStreamFx.process([spec], l.duplicate(), r.duplicate(), SR)
		AKDsp.native_enabled = false
		var b := AKStreamFx.process([spec], l.duplicate(), r.duplicate(), SR)
		AKDsp.native_enabled = true
		if _diff(a[0], b[0]) + _diff(a[1], b[1]) > 1e-6:
			return "native and GDScript reverb input options differ"
	return ""


# ------------------------------------------------------------------ engine expansion effects

## `spec` agrees everywhere it runs: native and GDScript on buffers, the bus effect `bus_cls`
## (its own blocks, its own knobs set from the spec), and a patch carrying it (native and
## GDScript renders). "" or the reason not.
func _fx_everywhere(spec: Dictionary, l: PackedFloat32Array, r: PackedFloat32Array, bus_cls: StringName) -> String:
	if AKDsp.nat() == null:
		return ""
	var a := AKStreamFx.process([spec], l, r, SR)
	AKDsp.native_enabled = false
	var b := AKStreamFx.process([spec], l, r, SR)
	AKDsp.native_enabled = true
	var d := _diff(a[0], b[0]) + _diff(a[1], b[1])
	if d > 1e-6:
		return "%s: native and GDScript differ by %s" % [spec.type, d]
	if bus_cls != &"" and ClassDB.class_exists(bus_cls):
		var bus: Object = ClassDB.instantiate(bus_cls)
		var cs := AKStreamFx.compile(spec)
		for k in spec:
			if k != "type":
				bus.set(k, cs[k])
		var on_bus: Array = bus.process_offline(l, r, SR)
		d = _diff(on_bus[0], a[0]) + _diff(on_bus[1], a[1])
		if d > 1e-6:
			return "%s: the bus effect differs from the patch effect by %s" % [bus_cls, d]
	var p := _sine_patch()
	p.oscillators = [{shape = "saw", level = 0.4}, {shape = "pulse", level = 0.2, semitones = 7.0, pan = 0.4}]
	p.effects = [spec]
	var ev := AKSynth.events_for([{time_s = 0.0, note = 57, length_s = 0.3}, {time_s = 0.15, note = 64, length_s = 0.3}])
	var pn := AKSynth.render_events(p.compile(), ev, SR / 2, SR)
	var pg := AKSynth.render_events(p.compile(), ev, SR / 2, SR, true)
	d = _diff(pn.l, pg.l) + _diff(pn.r, pg.r)
	if d > 1e-6:
		return "%s in a patch: native and GDScript differ by %s" % [spec.type, d]
	return ""


func _sine_at(hz: float, n: int, amp := 0.5) -> PackedFloat32Array:
	var x := PackedFloat32Array()
	x.resize(n)
	for i in n:
		x[i] = amp * sin(TAU * hz * i / SR)
	return x


## The frequency shifter moves every partial by the same Hz (single sideband: the mirror
## image and the original 35 dB down or more), the other way on the right with stereo 1,
## and its feedback through the echo shifts each repeat again.
func test_freqshift() -> String:
	var n := SR / 2
	for hz in [60.0, 440.0, 2500.0, 12000.0]:
		var x := _sine_at(hz, n)
		var o := AKStreamFx.process([{type = "freqshift", shift_hz = 150.0, stereo = 1.0}], x, x, SR)
		var up := _goertzel(o[0], n / 2, 8192, hz + 150.0)
		var mirror := _goertzel(o[0], n / 2, 8192, absf(hz - 150.0))
		var orig := _goertzel(o[0], n / 2, 8192, hz)
		if absf(up - 0.5) > 0.02 or mirror > up * 0.018 or orig > up * 0.018:
			return "%d Hz shifted 150: %.4f at +150, %.4f at -150, %.4f left (want 0.5, under 1.8%%)" % [hz, up, mirror, orig]
		if _goertzel(o[1], n / 2, 8192, absf(hz - 150.0)) < 0.48:
			return "stereo 1: the right channel of %d Hz should shift down 150" % hz
	# Spectra keep their spacing (not their ratios): a 200 Hz saw-ish pair 200 + 400 -> 300 + 500.
	var pair := _sine_at(200.0, n, 0.3)
	var p2 := _sine_at(400.0, n, 0.3)
	for i in n:
		pair[i] += p2[i]
	var po := AKStreamFx.process([{type = "freqshift", shift_hz = 100.0}], pair, pair, SR)
	if _goertzel(po[0], n / 2, 8192, 300.0) < 0.28 or _goertzel(po[0], n / 2, 8192, 500.0) < 0.28 or _goertzel(po[0], n / 2, 8192, 600.0) > 0.01:
		return "200 + 400 shifted 100 should give 300 + 500"
	# A 1 kHz burst (40 ms) into feedback 0.5 through a 100 ms echo: 1.1 kHz at once, 1.2 kHz
	# a repeat later at half the level, 1.3 kHz after two.
	var burst := _sine_at(1000.0, n)
	for i in range(roundi(0.04 * SR), n):
		burst[i] = 0.0
	var e := AKStreamFx.process([{type = "freqshift", shift_hz = 100.0, feedback = 0.5, echo_ms = 100.0}], burst, burst, SR)
	var at := func(t0: float, hz: float) -> float:
		return _goertzel(e[0], roundi(t0 * SR), 1024, hz)
	if float(at.call(0.005, 1100.0)) < 0.4 or float(at.call(0.105, 1200.0)) < 0.2 or float(at.call(0.105, 1200.0)) > 0.3 \
			or float(at.call(0.205, 1300.0)) < 0.1 or float(at.call(0.105, 1100.0)) > 0.02:
		return "feedback through the echo: %.3f at 1.1 kHz, %.3f at 1.2 kHz after 100 ms, %.3f at 1.3 kHz after 200 ms" % [
			at.call(0.005, 1100.0), at.call(0.105, 1200.0), at.call(0.205, 1300.0)]
	if AKStreamFx.tail_s([{type = "freqshift", feedback = 0.5, echo_ms = 100.0}]) < 0.9:
		return "a fed-back shifter's echoes need a tail"
	var src := AKSynth.render_note(AKPatchLib.preset(&"saw_lead"), 48, 1.0, 0.3)
	for sp in [{type = "freqshift", shift_hz = -230.0, mix = 0.7}, {type = "freqshift", shift_hz = 12.0, stereo = 0.7, feedback = -0.8},
			{type = "freqshift", shift_hz = 300.0, feedback = 0.6, echo_ms = 75.0, dry = 0.5, wet = 1.2}]:
		var err := _fx_everywhere(sp, src.l, src.r, &"AKFreqShift" if not sp.has("dry") else &"")
		if err != "":
			return err
	return ""


## Peak absolute value of x between frames a and b.
func _peak_in(x: PackedFloat32Array, a: int, b: int) -> float:
	var m := 0.0
	for i in range(a, mini(b, x.size())):
		m = maxf(m, absf(x[i]))
	return m


## The conditioner's shelves boost and cut where they should, width 0 is mono, balance 1 silences
## the left, and its limiter holds a loud tone at the threshold. Everywhere agrees.
func test_conditioner() -> String:
	var n := SR / 2
	var lo := _sine_at(80.0, n, 0.05)
	var o := AKStreamFx.process([{type = "conditioner", bass_db = 12.0}], lo, lo, SR)
	var g := _goertzel(o[0], n / 2, 8192, 80.0) / 0.05
	if g < 3.0 or g > 4.1:
		return "bass +12 should lift 80 Hz about 11 dB (x%.2f)" % g
	var hi := _sine_at(10000.0, n, 0.05)
	o = AKStreamFx.process([{type = "conditioner", treble_db = -12.0}], hi, hi, SR)
	g = _goertzel(o[0], n / 2, 8192, 10000.0) / 0.05
	if g < 0.23 or g > 0.3:
		return "treble -12 should cut 10 kHz about 12 dB (x%.2f)" % g
	var r := _sine_at(330.0, n, 0.05)
	o = AKStreamFx.process([{type = "conditioner", width = 0.0}], lo, r, SR)
	if _diff_arr(o[0], o[1]) > 1e-9:
		return "width 0 should make it mono"
	o = AKStreamFx.process([{type = "conditioner", balance = 1.0}], lo, r, SR)
	if _peak_in(o[0], 0, n) > 0.0 or _peak_in(o[1], 0, n) < 0.04:
		return "balance 1 should leave only the right"
	var loud := _sine_at(440.0, n, 0.5)
	o = AKStreamFx.process([{type = "conditioner", threshold_db = -20.0}], loud, loud, SR)
	var pk := 20.0 * log(_peak_in(o[0], n - 4800, n)) / log(10.0)
	if pk > -19.5 or pk < -21.0:
		return "the limiter should hold a -6 dB tone at -20 dB (%.2f dB)" % pk
	return _fx_everywhere({type = "conditioner", bass_db = 5.0, treble_db = -3.0, width = 1.4, balance = -0.2, threshold_db = -12.0,
		attack_ms = 2.0, release_ms = 80.0, output_db = 2.0}, loud, r, &"AKConditioner")


func _diff_arr(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var m := 0.0
	for i in mini(a.size(), b.size()):
		m = maxf(m, absf(a[i] - b[i]))
	return m


## The graphic EQ: a band's peak lifts its centre by its gain and leaves a tone two octaves away
## near alone; all bands at 0 pass the input untouched. Everywhere agrees.
func test_geq() -> String:
	var n := SR / 2
	var t1 := _sine_at(1000.0, n, 0.1)
	var t4 := _sine_at(4000.0, n, 0.1)
	var o := AKStreamFx.process([{type = "geq", band6_db = 12.0}], t1, t4, SR)
	var g1 := _goertzel(o[0], n / 2, 8192, 1000.0) / 0.1
	var g4 := _goertzel(o[1], n / 2, 8192, 4000.0) / 0.1
	if absf(g1 - 3.981) > 0.15 or g4 < 0.95 or g4 > 1.12:
		return "band 6 +12 should lift 1 kHz 12 dB and leave 4 kHz (x%.3f, x%.3f)" % [g1, g4]
	o = AKStreamFx.process([{type = "geq"}], t1, t4, SR)
	if _diff_arr(o[0], t1) > 0.0 or _diff_arr(o[1], t4) > 0.0:
		return "a flat graphic EQ should pass the input"
	return _fx_everywhere({type = "geq", band1_db = 6.0, band3_db = -4.0, band6_db = 3.0, band9_db = -8.0, band11_db = 5.0, output_db = -2.0},
		t1, _sine_at(130.0, n, 0.3), &"AKGraphicEQ")


## The resonator: a tone at a band's frequency passes at its gain, one between bands is cut,
## series chains the bands. Everywhere agrees.
func test_resonator() -> String:
	var n := SR / 2
	var t := _sine_at(300.0, n, 0.2)
	var o := AKStreamFx.process([{type = "resonator"}], t, t, SR)
	var g := _goertzel(o[0], n / 2, 8192, 300.0) / 0.2
	if g < 0.95 or g > 1.08:
		return "a tone at freq1 should pass at unity (x%.3f)" % g
	var mid := _sine_at(600.0, n, 0.2)
	o = AKStreamFx.process([{type = "resonator"}], mid, mid, SR)
	if _goertzel(o[0], n / 2, 8192, 600.0) / 0.2 > 0.3:
		return "a tone between the bands should be cut"
	o = AKStreamFx.process([{type = "resonator", gain1_db = -48.0}], t, t, SR)
	if _goertzel(o[0], n / 2, 8192, 300.0) / 0.2 > 0.05:
		return "gain1 -48 should take freq1 out"
	o = AKStreamFx.process([{type = "resonator", mode = "series", freq2_hz = 300.0, freq3_hz = 300.0}], t, t, SR)
	g = _goertzel(o[0], n / 2, 8192, 300.0) / 0.2
	if g < 0.9 or g > 1.08:
		return "three bands in series at 300 Hz should pass 300 Hz (x%.3f)" % g
	var nz := PackedFloat32Array()
	nz.resize(n)
	seed(7)
	for i in n:
		nz[i] = randf_range(-0.3, 0.3)
	var err := _fx_everywhere({type = "resonator", freq1_hz = 220.0, freq2_hz = 990.0, freq3_hz = 2800.0, q1 = 20.0, q2 = 5.0, gain3_db = -6.0,
		mix = 0.8}, nz, t, &"AKResonator")
	if err != "":
		return err
	return _fx_everywhere({type = "resonator", mode = "series", freq1_hz = 400.0, freq2_hz = 500.0, q3 = 2.0}, nz, t, &"")


## The exciter leaves lows alone and adds harmonics above its frequency to highs. Everywhere agrees.
func test_exciter() -> String:
	var n := SR / 2
	var lo := _sine_at(200.0, n, 0.5)
	var o := AKStreamFx.process([{type = "exciter", drive = 1.0}], lo, lo, SR)
	if _diff_arr(o[0], lo) > 0.01:
		return "the exciter should leave 200 Hz alone (%.4f)" % _diff_arr(o[0], lo)
	var hi := _sine_at(5000.0, n, 0.5)
	o = AKStreamFx.process([{type = "exciter", drive = 1.0, mix = 0.5}], hi, hi, SR)
	if _goertzel(o[0], n / 2, 8192, 15000.0) < 0.004 or _goertzel(o[0], n / 2, 8192, 5000.0) < 0.45:
		return "the exciter should add a third harmonic to 5 kHz and keep the dry (%.4f)" % _goertzel(o[0], n / 2, 8192, 15000.0)
	return _fx_everywhere({type = "exciter", freq_hz = 2000.0, drive = 0.7, mix = 0.6}, hi, _sine_at(2600.0, n, 0.4), &"AKExciter")


## The waveshaper's curves: hard clips at 1, asym makes even harmonics where soft doesn't,
## digital steps in eighths, fold stays within 1. Everywhere agrees.
func test_waveshaper() -> String:
	var n := SR / 2
	var t := _sine_at(500.0, n, 0.5)
	var o := AKStreamFx.process([{type = "waveshaper", curve = "hard", drive_db = 12.0}], t, t, SR)
	if _peak_in(o[0], 0, n) > 1.0 + 1e-9 or _peak_in(o[0], 0, n) < 0.999:
		return "hard should clip at 1"
	o = AKStreamFx.process([{type = "waveshaper", curve = "soft", drive_db = 12.0}], t, t, SR)
	if _goertzel(o[0], n / 2, 8192, 1000.0) > 1e-3:
		return "soft should make no even harmonics"
	o = AKStreamFx.process([{type = "waveshaper", curve = "asym", drive_db = 12.0}], t, t, SR)
	if _goertzel(o[0], n / 2, 8192, 1000.0) < 0.02:
		return "asym should make even harmonics"
	o = AKStreamFx.process([{type = "waveshaper", curve = "digital", drive_db = 0.0}], t, t, SR)
	for i in 2000:
		if absf(o[0][i] * 8.0 - roundf(o[0][i] * 8.0)) > 1e-6:
			return "digital should step in eighths (%.5f)" % o[0][i]
	o = AKStreamFx.process([{type = "waveshaper", curve = "fold", drive_db = 18.0}], t, t, SR)
	if _peak_in(o[0], 0, n) > 1.0 + 1e-9 or _goertzel(o[0], n / 2, 8192, 2500.0) < 0.02:
		return "fold should stay within 1 and fold in harmonics"
	var r := _sine_at(170.0, n, 0.4)
	for cv in AKStreamFx.WS_CURVES:
		var err := _fx_everywhere({type = "waveshaper", curve = cv, drive_db = 9.0, bias = 0.2, pre_hp_hz = 80.0, post_lp_hz = 6000.0,
			output_db = -3.0, mix = 0.9}, t, r, &"AKWaveshaper" if cv == "fold" else &"")
		if err != "":
			return err
	return ""


## The mid-side tool: side down is mono, a mono signal's mid down is silence, mid_pan moves the
## middle, side_hp takes the lows out of the sides. Everywhere agrees.
func test_midside() -> String:
	var n := SR / 2
	var a := _sine_at(300.0, n, 0.3)
	var b := _sine_at(470.0, n, 0.3)
	var o := AKStreamFx.process([{type = "midside", side_db = -48.0}], a, b, SR)
	if _diff_arr(o[0], o[1]) > 0.01:
		return "side -48 should be all but mono"
	o = AKStreamFx.process([{type = "midside", mid_db = -48.0}], a, a, SR)
	if _peak_in(o[0], 0, n) > 0.002:
		return "a mono signal with mid -48 should be all but silent"
	o = AKStreamFx.process([{type = "midside", mid_pan = 1.0}], a, a, SR)
	if _peak_in(o[0], 0, n) > 0.0 or _peak_in(o[1], 0, n) < 0.29:
		return "mid_pan 1 should put the middle right"
	var low := _sine_at(50.0, n, 0.3)
	var zero := PackedFloat32Array()
	zero.resize(n)
	o = AKStreamFx.process([{type = "midside", side_hp_hz = 800.0}], low, zero, SR)
	if _goertzel(o[0], n / 2, 8192, 50.0) > 0.2:
		return "side_hp should take 50 Hz out of the side (%.3f)" % _goertzel(o[0], n / 2, 8192, 50.0)
	return _fx_everywhere({type = "midside", mid_db = -2.0, side_db = 4.0, side_hp_hz = 150.0, mid_pan = -0.3}, a, b, &"AKMidSide")


## The stutter passes the input until it has a slice, then repeats the last 1 / rate_hz of it
## (with no softness, sample for sample) until 1 / resample_hz has passed and a repeat ends,
## when it takes the newest slice; pitch reads the repeats faster; softness fades each repeat's
## edges; rate_sync follows the tempo. Native, GDScript, the bus effect and a patch agree.
func test_stutter() -> String:
	var n := SR * 2
	var x := PackedFloat32Array()
	x.resize(n)
	for i in n:
		x[i] = 0.5 * sin(TAU * (200.0 + 300.0 * float(i) / n) * i / SR) * (0.5 + 0.5 * float(i) / n)
	var o := AKStreamFx.process([{type = "stutter", rate_hz = 10.0, resample_hz = 2.0, softness = 0.0}], x, x, SR)
	var y: PackedFloat32Array = o[0]
	var cap := 4799   # the slice is taken as its last sample comes in, and plays from there
	for i in cap:
		if absf(y[i] - x[i]) > 1e-6:
			return "before its first slice the stutter should pass the input (frame %d)" % i
	for k in 5 * 4800:
		if absf(y[cap + k] - x[k % 4800]) > 1e-6:
			return "the first slice should repeat (frame %d: %.4f, want %.4f)" % [cap + k, y[cap + k], x[k % 4800]]
	# 0.5 s on (five repeats), the newest 0.1 s is the next slice.
	var cap2 := cap + 5 * 4800
	for k in 4800:
		if absf(y[cap2 + k] - x[cap2 - 4799 + k]) > 1e-6:
			return "the second slice should be the newest 0.1 s (frame %d)" % (cap2 + k)
	# Pitch +12: a 300 Hz tone repeats at 600 Hz.
	var tone := _sine_at(300.0, n)
	o = AKStreamFx.process([{type = "stutter", rate_hz = 5.0, resample_hz = 0.5, pitch = 12.0, softness = 0.0}], tone, tone, SR)
	if _goertzel(o[0], SR / 2, 8192, 600.0) < 4.0 * _goertzel(o[0], SR / 2, 8192, 300.0):
		return "pitch 12 should read the repeats an octave up"
	# Softness 1: each repeat swells from silence, so the samples at its edges are quiet.
	o = AKStreamFx.process([{type = "stutter", rate_hz = 10.0, resample_hz = 0.5, softness = 1.0}], tone, tone, SR)
	var edge := 0.0
	var mid := 0.0
	for k in range(0, 4 * 4800, 4800):
		for j in 20:
			edge = maxf(edge, absf(o[0][cap + k + j]))
		for j in range(2300, 2500):
			mid = maxf(mid, absf(o[0][cap + k + j]))
	if edge > 0.01 or mid < 0.4:
		return "softness 1 should fade each repeat's edges (%.4f at the edges, %.4f mid)" % [edge, mid]
	# rate_sync 1/8 at 120 BPM: a 0.25 s slice (12000 frames).
	var c := AKStreamFx.compile({type = "stutter", rate_sync = "1/8"})
	if absf(float(c.rate_hz) - 4.0) > 1e-9 or absf(float(c.rate_beats) - 0.5) > 1e-9:
		return "rate_sync 1/8 should be 4 Hz at 120 BPM (%s)" % c.rate_hz
	var ch := AKStreamFx.Chain.new([c], SR)
	ch.set_tempo(60.0)
	if absf(ch.fx[0].xk[0] - 2.0) > 1e-9:
		return "at 60 BPM a 1/8 stutter should repeat twice a second"
	var r := _sine_at(450.0, n, 0.3)
	var err := _fx_everywhere({type = "stutter", rate_hz = 7.3, resample_hz = 1.7, softness = 0.3, pitch = -5.0, mix = 0.8}, x, r, &"AKStutter")
	if err != "":
		return err
	return _fx_everywhere({type = "stutter", rate_sync = "1/16", resample_sync = "1/2", softness = 0.1}, x, r, &"")


## The rotary speaker: the horn's beam swings the level at the horn's rate (0.8 Hz slow,
## 6.7 Hz fast), the two mics hear it differently, Doppler moves the pitch (and with doppler 0
## it doesn't), a low tone goes to the slower, gentler drum, and a speed change takes time.
func test_rotary() -> String:
	var n := SR * 2
	var hi := _sine_at(4000.0, n, 0.4)
	# The level, 5 ms blocks.
	var env := func(x: PackedFloat32Array) -> PackedFloat32Array:
		var e := PackedFloat32Array()
		for b in range(0, x.size() - 240, 240):
			e.append(_rms(x, b, b + 240))
		return e
	var tone_at := func(e: PackedFloat32Array, hz: float) -> float:
		var re := 0.0
		var im := 0.0
		var mean := 0.0
		for v in e:
			mean += v
		mean /= e.size()
		for k in e.size():
			re += (e[k] - mean) * cos(TAU * hz * k * 0.005)
			im += (e[k] - mean) * sin(TAU * hz * k * 0.005)
		return sqrt(re * re + im * im) / e.size()
	var fast := AKStreamFx.process([{type = "rotary", speed = "fast"}], hi, hi, SR)
	var slow := AKStreamFx.process([{type = "rotary", speed = "slow"}], hi, hi, SR)
	var ef: PackedFloat32Array = env.call(fast[0])
	var es: PackedFloat32Array = env.call(slow[0])
	if float(tone_at.call(ef, 6.7)) < 4.0 * float(tone_at.call(ef, 0.8)) or float(tone_at.call(ef, 6.7)) < 0.02:
		return "fast: the level should swing at 6.7 Hz (%.4f) not 0.8 (%.4f)" % [tone_at.call(ef, 6.7), tone_at.call(ef, 0.8)]
	if float(tone_at.call(es, 0.804)) < 4.0 * float(tone_at.call(es, 6.7)):
		return "slow: the level should swing at 0.8 Hz (%.4f) not 6.7 (%.4f)" % [tone_at.call(es, 0.804), tone_at.call(es, 6.7)]
	if _diff(fast[0], fast[1], SR / 2) < 0.05:
		return "the two mics should hear the horn differently"
	# Doppler: the 4 kHz tone's cycle length over 10 ms windows swings about 2% when fast.
	var swing := func(x: PackedFloat32Array) -> float:
		var lo := INF
		var top := 0.0
		for w0 in range(SR / 2, n - 480, 480):
			var ups := 0
			var first := -1.0
			var last := -1.0
			for i in range(w0 + 1, w0 + 480):
				if x[i - 1] < 0.0 and x[i] >= 0.0:
					var t := i - 1 + x[i - 1] / (x[i - 1] - x[i])
					if first < 0.0:
						first = t
					last = t
					ups += 1
			var hz := (ups - 1) * SR / (last - first)
			lo = minf(lo, hz)
			top = maxf(top, hz)
		return (top - lo) / 4000.0
	var sw: float = swing.call(fast[0])
	var flat: float = swing.call((AKStreamFx.process([{type = "rotary", speed = "fast", doppler = 0.0}], hi, hi, SR))[0])
	if sw < 0.02 or sw > 0.08 or flat > 0.004:
		return "Doppler: the pitch swings %.2f%% fast (want about 4%% peak to peak), %.2f%% with doppler 0" % [sw * 100.0, flat * 100.0]
	# A low tone goes to the drum: a gentler level swing at the drum's rate.
	var low := _sine_at(100.0, n, 0.4)
	var dr := AKStreamFx.process([{type = "rotary", speed = "fast"}], low, low, SR)
	var ed: PackedFloat32Array = env.call(dr[0])
	if float(tone_at.call(ed, 5.7)) < 3.0 * float(tone_at.call(ed, 6.7)) or float(tone_at.call(ed, 5.7)) > float(tone_at.call(ef, 6.7)):
		return "a low tone should swing gently at the drum's 5.7 Hz (%.4f; horn %.4f)" % [tone_at.call(ed, 5.7), tone_at.call(ed, 6.7)]
	# A patch whose rotor goes from slow to fast mid-note (a settings edit, live): the horn
	# takes about accel_s to get there, so the level swings are slow just after the change.
	if AKSynth.available():
		var p := _sine_patch()
		p.oscillators = [{shape = "sine", level = 0.4, fixed_hz = 4000.0}]
		p.effects = [{type = "rotary", speed = 0.0, accel_s = 1.0}]
		var s: Object = ClassDB.instantiate(&"AKSynthStream")
		s.patch = p
		s.note_on(60.0, 1.0, 0.0)
		var pre: Array = s.render_offline(SR)
		var q: AKPatch = p.duplicate()
		q.effects = [{type = "rotary", speed = 1.0, accel_s = 1.0}]
		s.patch = q
		var post: Array = s.render_offline(SR * 4)
		var e1: PackedFloat32Array = env.call((post[0] as PackedFloat32Array).slice(0, SR / 2))
		var e3: PackedFloat32Array = env.call((post[0] as PackedFloat32Array).slice(SR * 3, SR * 4))
		if float(tone_at.call(e1, 6.7)) > float(tone_at.call(e3, 6.7)) * 0.5:
			return "the horn should take time to speed up (%.4f at 6.7 Hz just after, %.4f 3 s on)" % [tone_at.call(e1, 6.7), tone_at.call(e3, 6.7)]
		if _diff(pre[0], post[0]) == 0.0:
			return "?"
	var src := AKSynth.render_note(AKPatchLib.preset(&"organ"), 48, 1.0, 0.3)
	for sp in [{type = "rotary"}, {type = "rotary", speed = 0.6, drive = 0.7, spread = 0.3, crossover_hz = 1200.0, mix = 0.8},
			{type = "rotary", speed = "fast", horn_hz = 9.0, drum_hz = 1.5, doppler = 2.0, tremolo = 0.4, accel_s = 0.1}]:
		var err := _fx_everywhere(sp, src.l, src.r, &"AKRotary")
		if err != "":
			return err
	return ""
