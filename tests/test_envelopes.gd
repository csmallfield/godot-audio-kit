# SPDX-License-Identifier: Apache-2.0
# Envelopes v2 (docs/plans/synth-expansion-phase1.md): stages envelopes, the
# dx7 mode against msfa's own levels, env4 .. env8, and the same samples
# natively, in GDScript, live and baked.
extends RefCounted

const SR := 48000
const REF := "res://tests/data/dx7_env_ref.json"


## A sine through no filter, so the envelope is all there is.
func _plain(env: Dictionary) -> AKPatch:
	var p := AKPatch.new()
	p.oscillators = [{shape = "sine", level = 1.0}]
	p.filter = {type = "off"}
	p.velocity_sens = 0.0
	p.amp_env = env
	return p


## Envelope `k`'s level at every sample of a note held `hold_s`, read from the engine.
func _levels(p: AKPatch, n: int, hold_s: float, note := 60.0, vel := 1.0, k := 0) -> PackedFloat64Array:
	var core := AKSynthCore.new(p.compile())
	core.note_on(0, note, vel)
	core.note_off(roundi(hold_s * SR), note)
	var out := PackedFloat64Array()
	out.resize(n)
	for i in n:
		core.render(1)
		out[i] = core.voices[0].level[k] if core.voices[0].active else 0.0
	return out


func _near(got: float, want: float, tol := 1e-9) -> bool:
	return absf(got - want) <= tol


func _diff(a: AKBuffer, b: AKBuffer) -> float:
	if a.frames() != b.frames():
		return INF
	var w := 0.0
	for i in a.frames():
		w = maxf(w, maxf(absf(a.l[i] - b.l[i]), absf(a.r[i] - b.r[i])))
	return w


## Linear stages land on their levels at the end of each stage; sustain holds; key-off runs the
## release stages from wherever the level is; the voice then ends.
func test_stages_linear_sustain_release() -> String:
	var p := _plain({stages = [{time_s = 0.01, level = 1.0}, {time_s = 0.02, level = 0.5}, {time_s = 0.01, level = 0.0}], sustain = 1})
	var lv := _levels(p, 9000, 0.1)
	for c in [[239, 0.5], [479, 1.0], [479 + 480, 0.75], [479 + 960, 0.5], [4000, 0.5], [4799, 0.5], [4800 + 239, 0.25]]:
		if not _near(lv[c[0]], c[1]):
			return "at %d: %.6f, want %.3f" % [c[0], lv[c[0]], c[1]]
	if lv[4800 + 480] != 0.0:
		return "the voice should be done after its release stage (%s)" % str(lv[4800 + 480])
	# Key-off mid-attack: the release starts from where the attack got to.
	var mid := _levels(p, 2000, 0.005)
	if not _near(mid[239], 0.5) or not _near(mid[240 + 239], 0.25):
		return "release from mid-attack: %.4f, %.4f" % [mid[239], mid[240 + 239]]
	return ""


## power is Vital's curve; exp is power -5 (or -amount); hold keeps the level; delay_s and hold_s
## become hold stages; `start` is where the note begins.
func test_stage_curves_delay_hold_start() -> String:
	var a := 3.0
	var p := _plain({stages = [{time_s = 0.01, level = 1.0, curve = "power", amount = a}, {time_s = 0.01, level = 0.0, curve = "exp"},
		{time_s = 0.01, level = 0.0, curve = "hold"}], sustain = 2})
	var lv := _levels(p, 1500, 1.0)
	var f := func(x: float, am: float) -> float: return (exp(am * x) - 1.0) / (exp(am) - 1.0)
	if not _near(lv[239], f.call(0.5, a), 1e-9) or not _near(lv[479], 1.0):
		return "power: %.9f at the middle (want %.9f), %.9f at the end" % [lv[239], f.call(0.5, a), lv[479]]
	if not _near(lv[480 + 239], 1.0 - f.call(0.5, -5.0), 1e-9):
		return "exp: %.9f at the middle (want %.9f)" % [lv[480 + 239], 1.0 - f.call(0.5, -5.0)]
	p.amp_env = {stages = [{time_s = 0.01, level = 1.0}, {time_s = 0.01, level = 0.5}], delay_s = 0.005, hold_s = 0.005, start = 0.2}
	lv = _levels(p, 2000, 1.0)
	if not _near(lv[0], 0.2) or not _near(lv[239], 0.2):
		return "delay should hold the start level: %.4f, %.4f" % [lv[0], lv[239]]
	if not _near(lv[240 + 239], 0.6) or not _near(lv[720 + 100], 1.0) or not _near(lv[960 + 479], 0.5):
		return "attack after the delay, hold after the attack: %.4f, %.4f, %.4f" % [lv[479], lv[820], lv[1439]]
	return ""


## A loop runs while the key is down and gives way to the release at key-off.
func test_stage_loop() -> String:
	var p := _plain({stages = [{time_s = 0.01, level = 1.0}, {time_s = 0.01, level = 0.2}, {time_s = 0.01, level = 1.0},
		{time_s = 0.01, level = 0.0}], sustain = 2, loop = [1, 2]})
	var lv := _levels(p, 6000, 0.05)
	for c in [[479, 1.0], [959, 0.2], [1439, 1.0], [1919, 0.2], [2399, 1.0], [2159, 0.6]]:
		if not _near(lv[c[0]], c[1]):
			return "loop at %d: %.4f, want %.2f" % [c[0], lv[c[0]], c[1]]
	# Key-off at 2400 (the top of a loop): the release stage falls from 1 to 0 in 10 ms.
	if not _near(lv[2400 + 239], 0.5) or lv[2400 + 480] != 0.0:
		return "release out of the loop: %.4f, %.4f" % [lv[2639], lv[2880]]
	return ""


## No release stages: release_s as an ADSR's; sustain -1: a one-shot that ignores key-off.
func test_stage_fallback_release_and_one_shot() -> String:
	var p := _plain({stages = [{time_s = 0.0, level = 1.0}], release_s = 0.01})
	var lv := _levels(p, 2000, 0.01)
	var k := exp(-1.0 / (0.01 * SR))
	if not _near(lv[100], 1.0) or not _near(lv[480 + 99], pow(k, 100), 1e-9):
		return "release_s fallback: %.6f, %.6f (want %.6f)" % [lv[100], lv[579], pow(k, 100)]
	p.amp_env = {stages = [{time_s = 0.0, level = 1.0}, {time_s = 0.02, level = 0.0}], sustain = -1}
	lv = _levels(p, 1200, 0.001)
	if not _near(lv[479], 0.5) or lv[1000] != 0.0:
		return "one-shot should run on past key-off: %.4f, %.4f" % [lv[479], lv[1000]]
	return ""


## time_key, time_velocity (with a stage list) and level_velocity.
func test_stage_time_and_level_scaling() -> String:
	var env := {stages = [{time_s = 0.02, level = 1.0}, {time_s = 0.02, level = 0.0}], sustain = 1, time_key = 1.0}
	var lv := _levels(_plain(env), 2000, 1.0, 72.0)
	if not _near(lv[479], 1.0) or not _near(lv[959], 0.0):
		return "an octave up with time_key 1 should halve the times: %.4f, %.4f" % [lv[479], lv[959]]
	env = {stages = [{time_s = 0.01, level = 1.0}, {time_s = 0.01, level = 0.0}], sustain = 1, time_velocity = 1.0,
		time_velocity_stages = [1], level_velocity = 0.5}
	lv = _levels(_plain(env), 2000, 1.0, 60.0, 0.0)
	# Velocity 0: the level is halved, the attack keeps its time, the decay takes twice as long.
	if not _near(lv[479], 0.5) or not _near(lv[480 + 479], 0.25) or not _near(lv[480 + 959], 0.0):
		return "velocity scaling: %.4f, %.4f, %.4f" % [lv[479], lv[959], lv[1439]]
	return ""


## env4 .. env8 are matrix sources; describe() leaves `envelopes` out until it's used.
func test_more_envelopes_and_describe() -> String:
	var p := _plain({attack_s = 0.0, decay_s = 0.2, sustain = 1.0})
	var before := var_to_str(p.describe())
	if "envelopes" in p.describe():
		return "describe() should leave out an empty envelopes list"
	p.envelopes = [{attack_s = 0.0, decay_s = 0.01, sustain = 0.0}, {stages = [{time_s = 0.01, level = 0.7}]}]
	p.mods = [{source = "env5", dest = "amp", amount = -0.5}]
	var c := p.compile()
	if (c.env as Array).size() != 5 or int(c.mods[0].src) != AKSynthCore.SRC_ENV5:
		return "envelopes should compile as env4, env5"
	var core := AKSynthCore.new(c)
	core.note_on(0, 60.0, 1.0)
	core.render(481)
	var v = core.voices[0]
	if not _near(v.level[4], 0.7) or not _near(v.src[AKSynthCore.SRC_ENV5], 0.7) or v.level[3] > 0.01:
		return "env4/env5 levels %.4f, %.4f, source %.4f" % [v.level[3], v.level[4], v.src[AKSynthCore.SRC_ENV5]]
	p.envelopes = []
	p.mods = []
	if var_to_str(p.describe()) != before:
		return "describe() changed for a patch without new fields"
	return ""


## The bake's tail follows a stages or dx7 amp envelope.
func test_tail_s() -> String:
	var p := _plain({stages = [{time_s = 0.0, level = 1.0}, {time_s = 0.5, level = 0.3}, {time_s = 0.25, level = 0.0}], sustain = 1})
	if not _near(p.tail_s(), 0.25):
		return "stages tail %.3f, want 0.25" % p.tail_s()
	p.amp_env = {mode = "dx7", rates = [99, 99, 99, 50], levels = [99, 99, 99, 0]}
	var t := p.tail_s()
	var lv := _levels(p, roundi((t + 0.1) * SR), 0.0)
	if t <= 0.05 or lv[lv.size() - 1] != 0.0:
		return "dx7 tail %.3f s should cover the release" % t
	return ""


## The msfa port, state machine alone: every reference case's Q24 levels, exactly.
func test_dx7_levels_match_msfa() -> String:
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REF))
	for case: Dictionary in ref.cases:
		var e := AKPatch._compile_env(case.env)
		var d := AKSynthCore._Dx7.new()
		d.srm = int(44100.0 / SR * 16777216.0)
		var note := int(case.note)
		d.outlevel = AKSynthCore.dx7_outlevel(e, note, int(case.velocity))
		d.rate_scaling = AKSynthCore.dx7_rate_scaling(e, note)
		if d.outlevel != int(case.outlevel) or d.rate_scaling != int(case.rate_scaling_q):
			return "%s: outlevel %d / rate scaling %d, msfa %d / %d" % [case.label, d.outlevel, d.rate_scaling, case.outlevel, case.rate_scaling_q]
		d.level = 0
		d.down = true
		d.advance(e, 0)
		var want: Array = case.levels_q24
		for b in want.size():
			if b == int(case.keyoff_block):
				d.down = false
				d.advance(e, 3)
			var got := d.getsample(e)
			if got != int(want[b]):
				return "%s: block %d level %d, msfa %d" % [case.label, b, got, want[b]]
	return ""


## The dx7 mode in a voice: the engine's levels each block are msfa's (velocity as MIDI / 127),
## the gain ramps between blocks, the voice ends when msfa's note would, and a key-off inside a
## block is taken at the next block.
func test_dx7_in_a_voice() -> String:
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REF))
	var done := 0
	for case: Dictionary in ref.cases:
		if not (String(case.label) in ["BRASS   1 op1", "TUB BELLS op5", "SYN-CLAV 2 op5", "attack to 0 (static)", "held level, release up"]):
			continue
		var p := _plain(case.env)
		var core := AKSynthCore.new(p.compile())
		var note := float(case.note)
		core.note_on(0, note, float(case.velocity) / 127.0)
		core.note_off(int(case.keyoff_block) * 64, note)
		var want: Array = case.levels_q24
		var active: String = case.active
		var g_prev := 0.0
		for b in want.size():
			if b > 0 and not core.voices[0].active:
				# Ending in the block msfa's note ends (already silent under its threshold) is msfa's end.
				if active[b - 1] == "0":
					break
				return "%s: the voice ended before block %d, msfa's note was still active" % [case.label, b]
			core.render(1)
			var v = core.voices[0]
			if b > 0 and active[b - 1] == "0":
				if v.active or v.level[0] != 0.0:
					return "%s: the voice should end at block %d, as msfa's note does" % [case.label, b]
				break
			if v.dx[0].level != int(want[b]):
				return "%s: block %d level %d, msfa %d" % [case.label, b, v.dx[0].level, want[b]]
			var g := pow(2.0, float(int(want[b]) - AKSynthCore.DX7_FULL) / 16777216.0)
			# msfa skips an operator whose gain is below its threshold at both ends of a block.
			var quiet := g_prev < AKSynthCore.DX7_THRESH and g < AKSynthCore.DX7_THRESH
			if not _near(v.level[0], 0.0 if quiet else g_prev + (g - g_prev) / 64.0, 1e-12):
				return "%s: block %d gain ramp %s" % [case.label, b, str(v.level[0])]
			core.render(63)
			if not _near(v.level[0], 0.0 if quiet else g, 1e-12):
				return "%s: block %d ends at %s, want %s" % [case.label, b, str(v.level[0]), str(g)]
			g_prev = g
		done += 1
	if done != 5:
		return "only %d voice cases ran" % done
	var p := _plain({mode = "dx7", rates = [99, 99, 99, 60], levels = [99, 99, 99, 0]})
	var c2 := AKSynthCore.new(p.compile())
	c2.note_on(0, 60.0, 1.0)
	c2.note_off(10 * 64 + 17, 60.0)
	c2.render(10 * 64 + 30)
	if not c2.voices[0].dx[0].down:
		return "a key-off inside a block should wait for the next block"
	c2.render(64)
	if c2.voices[0].dx[0].down:
		return "the key-off should be taken at the next block"
	c2.render(SR)
	if c2.voice_count() != 0:
		return "a dx7 release to level 0 should end the voice"
	return ""


## Native and GDScript give the same samples for every new envelope, and live matches the bake.
func test_native_matches_gdscript() -> String:
	if AKDsp.nat() == null:
		return ""
	var pats := []
	var p := _plain({stages = [{time_s = 0.01, level = 1.0, curve = "power", amount = 2.0}, {time_s = 0.05, level = 0.4, curve = "exp"},
		{time_s = 0.03, level = 0.7}, {time_s = 0.1, level = 0.0, curve = "exp", amount = 3.0}], sustain = 2, loop = [1, 2],
		delay_s = 0.003, hold_s = 0.004, start = 0.1, time_key = 0.5, time_velocity = 0.7, time_velocity_stages = [1, 3], level_velocity = 0.3})
	p.oscillators = [{shape = "saw", level = 0.5}, {shape = "square", level = 0.3}]
	p.filter = {type = "lowpass", cutoff_hz = 800.0, q = 2.0}
	p.envelopes = [{mode = "dx7", rates = [80, 40, 30, 60], levels = [99, 70, 50, 0], output_level = 90, rate_scaling = 3,
		velocity_sens = 4, key_scaling = {break_point = 40, left_depth = 20, right_depth = 30, left_curve = 1, right_curve = 2}},
		{stages = [{time_s = 0.2, level = 1.0}], sustain = -1}]
	p.mods = [{source = "env4", dest = "cutoff", amount = 2.0}, {source = "env5", dest = "osc2.level", amount = -0.3}]
	p.velocity_sens = 0.5
	pats.append(p)
	var q := _plain({mode = "dx7", rates = [72, 76, 99, 71], levels = [99, 88, 96, 0], output_level = 98, velocity_sens = 2, rate_scaling = 2})
	q.mode = "mono"
	pats.append(q)
	var notes := [{time_s = 0.0, note = "C3", length_s = 0.3, velocity = 0.8}, {time_s = 0.1, note = "E3", length_s = 0.3},
		{time_s = 0.2, note = "G4", length_s = 0.15, velocity = 0.4}, {time_s = 0.37, note = "C3", length_s = 0.2}]
	for pat: AKPatch in pats:
		var c := pat.compile()
		var ev := AKSynth.events_for(notes)
		var a := AKSynth.render_events(c, ev, roundi(SR * 1.0))
		var b := AKSynth.render_events(c, ev, roundi(SR * 1.0), SR, true)
		var d := _diff(a, b)
		if d > 1e-6 or a.peak() < 0.01:
			return "native and GDScript differ by %s (peak %.3f)" % [str(d), a.peak()]
		if AKSynth.available():
			var s: Object = ClassDB.instantiate(&"AKSynthStream")
			s.patch = pat
			s.note_on(48.0, 0.8, 0.0)
			s.render_offline(3000)
			s.note_off(48.0, 0.0)
			var lr: Array = s.render_offline(SR / 2)
			var baked := AKSynth.render_events(c, [[0, AKSynth.E_ON, 48.0, 0.8], [3000, AKSynth.E_OFF, 48.0, 0.0]], 3000 + SR / 2)
			var w := 0.0
			for i in SR / 2:
				w = maxf(w, absf(lr[0][i] - baked.l[3000 + i]))
			if w > 1e-6:
				return "live and baked differ by %s" % str(w)
	return ""


## Stages envelopes on amp and filter cost about what ADSRs do: 32 voices within 10% of a core,
## and within 15% of the same patch with ADSRs.
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
	var c_adsr := p.compile()
	p.amp_env = {stages = [{time_s = 0.01, level = 1.0}, {time_s = 0.3, level = 0.8, curve = "exp"}, {time_s = 0.3, level = 0.0, curve = "exp"}], sustain = 1}
	p.env2 = {stages = [{time_s = 0.0, level = 1.0}, {time_s = 0.4, level = 0.3, curve = "power", amount = -4.0}], sustain = 1}
	var c_staged := p.compile()
	# Alternated, best of five each: load that comes and goes during a long run hits both alike.
	var adsr := INF
	var staged := INF
	for attempt in 5:
		for which in 2:
			var t := Time.get_ticks_usec()
			AKSynth.render_events(c_adsr if which == 0 else c_staged, ev, SR * 2)
			var share := (Time.get_ticks_usec() - t) / 1e6 / 2.0
			if which == 0:
				adsr = minf(adsr, share)
			else:
				staged = minf(staged, share)
	print("        32 voices: ADSR %.1f%%, stages %.1f%% of a core" % [adsr * 100.0, staged * 100.0])
	if staged > 0.13:
		return "32 voices with stages envelopes take %.1f%% of a core" % (staged * 100.0)
	if staged > adsr * 1.15:
		return "stages envelopes cost %.0f%% more than ADSRs" % ((staged / adsr - 1.0) * 100.0)
	return ""
