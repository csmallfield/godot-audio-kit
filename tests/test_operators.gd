# SPDX-License-Identifier: Apache-2.0
# Synth expansion phase 2 (docs/plans/synth-expansion-phase2.md): operator
# graphs, per-oscillator envelopes, frequencies, and msfa's DX7 pieces
# (frequencies, pitch envelope, LFO, amp modulation) against msfa's own numbers;
# native against GDScript, live against baked; DX7 voices against msfa renders.
extends RefCounted

const SR := 48000
const REF := "res://tests/data/dx7_ref.json"
## A one-shot at level 1: the amp envelope stays out of the way.
const FLAT := {stages = [{time_s = 0.0, level = 1.0}], sustain = -1}


func _flat(oscs: Array) -> AKPatch:
	var p := AKPatch.new()
	p.oscillators.assign(oscs)
	p.filter = {type = "off"}
	p.velocity_sens = 0.0
	p.amp_env = FLAT
	return p


## The first `n` samples of one note.
func _out(p: AKPatch, n: int, note := 60.0, vel := 1.0, off_at := -1) -> PackedFloat32Array:
	var core := AKSynthCore.new(p.compile())
	core.note_on(0, note, vel)
	if off_at >= 0:
		core.note_off(off_at, note)
	return core.render(n)[0]


func _hz(note: float) -> float:
	return 440.0 * pow(2.0, (note - 69.0) / 12.0)


func _diff(a: AKBuffer, b: AKBuffer) -> float:
	if a.frames() != b.frames():
		return INF
	var w := 0.0
	for i in a.frames():
		w = maxf(w, maxf(absf(a.l[i] - b.l[i]), absf(a.r[i] - b.r[i])))
	return w


## msfa's operator frequencies: osc_freq's Q24 log frequency and Freqlut's increment, exactly.
func test_dx7_frequencies_match_msfa() -> String:
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REF))
	var core := AKSynthCore.new(AKPatch.new().compile())
	for f: Dictionary in ref.freq:
		var lf := AKSynthCore.dx7_osc_logfreq(int(f.note), int(f.mode), int(f.coarse), int(f.fine), int(f.detune))
		var inc := core.freqlut(lf if int(f.mode) == 1 else lf + int(f.pitch_mod))
		if lf != int(f.logfreq) or inc != int(f.inc):
			return "%s: logfreq %d inc %d, msfa %d %d" % [f, lf, inc, f.logfreq, f.inc]
	return ""


## msfa's pitch envelope, block by block.
func test_dx7_pitch_env_matches_msfa() -> String:
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REF))
	var core := AKSynthCore.new(AKPatch.new().compile())
	for c: Dictionary in ref.pitch_env:
		var e := AKPatch._compile_env({mode = "dx7_pitch", rates = c.rates, levels = c.levels})
		var d := AKSynthCore._Dx7P.new()
		d.unit = core._penv_unit
		d.set_up(e)
		var want: Array = c.levels_q24
		for b in want.size():
			if b == int(c.keyoff_block):
				d.down = false
				d.advance(e, 3)
			var got := d.getsample(e)
			if got != int(want[b]):
				return "%s %s: block %d level %d, msfa %d" % [c.rates, c.levels, b, got, want[b]]
	return ""


## msfa's LFO with Dx7Note's pitch and amp modulation, and the amp modulation's drop in an
## operator's level, block by block.
func test_dx7_lfo_matches_msfa() -> String:
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REF))
	var core := AKSynthCore.new(AKPatch.new().compile())
	for c: Dictionary in ref.lfo:
		var p := AKPatch.new()
		p.lfo1 = {mode = "dx7", speed = c.speed, delay = c.delay, wave = c.wave, sync = int(c.sync) != 0,
			pitch_mod_depth = c.pitch_mod_depth, pitch_mod_sens = c.pitch_mod_sens, amp_mod_depth = c.amp_mod_depth}
		var l: Dictionary = p.compile().lfo[0]
		var d := AKSynthCore._Dx7Lfo.new()
		d.reset(core, l)
		for b in (c.value as Array).size():
			d.step(l)
			if d.value != int(c.value[b]) or d.delay_q24 != int(c.delay_q24[b]) or d.pitch_mod != int(c.pitch_mod[b]) or d.amd != int(c.amp_mod[b]):
				return "lfo %s block %d: %d %d %d %d, msfa %d %d %d %d" % [[c.speed, c.wave, c.sync], b, d.value, d.delay_q24,
					d.pitch_mod, d.amd, c.value[b], c.delay_q24[b], c.pitch_mod[b], c.amp_mod[b]]
			for s in 3:
				var got := AKSynthCore.dx7_amp_mod(3840 << 16, d.amd, s + 1)
				if got != int(c.ldiff[s][b]):
					return "lfo %s block %d: amp mod drop %d at sensitivity %d, msfa %d" % [[c.speed, c.wave], b, got, s + 1, c.ldiff[s][b]]
	return ""


## The DX7 algorithms as graphs, from msfa's buses.
func test_dx7_algorithms() -> String:
	var a1 := AKPatchLib.dx7_algorithm(1)
	if a1.carriers != [1, 3] or a1.mods[1] != [2] or a1.mods[3] != [4] or a1.mods[4] != [5] or a1.mods[5] != [6] or a1.feedback != 6:
		return "algorithm 1: %s" % [a1]
	var a32 := AKPatchLib.dx7_algorithm(32)
	if a32.carriers != [1, 2, 3, 4, 5, 6] or a32.feedback != 6:
		return "algorithm 32: %s" % [a32]
	# 5: three pairs; 16: OP1 hears OP2, OP3 (<- OP4) and OP5 (<- OP6).
	var a5 := AKPatchLib.dx7_algorithm(5)
	if a5.carriers != [1, 3, 5] or a5.mods[1] != [2] or a5.mods[5] != [6]:
		return "algorithm 5: %s" % [a5]
	var a16 := AKPatchLib.dx7_algorithm(16)
	var m16: Array = (a16.mods[1] as Array).duplicate()
	m16.sort()
	if a16.carriers != [1] or m16 != [2, 3, 5] or a16.mods[3] != [4] or a16.mods[5] != [6]:
		return "algorithm 16: %s" % [a16]
	return ""


## Several modulators sum; feedback averages the last two outputs; a level envelope scales both what
## is heard and what is sent; all against the formulas, sample by sample.
func test_fm_graph_feedback_and_level_env() -> String:
	var f1 := _hz(60.0)
	var a := 1.3
	var b := 0.7
	var p := _flat([{shape = "sine", level = 1.0, fm = [{from = 2, index = a}, {from = 3, index = b}]},
		{shape = "sine", level = 0.0, ratio = 2.0}, {shape = "sine", level = 0.0, fixed_hz = 333.0}])
	var y := _out(p, 2000)
	var d1 := f1 / SR
	var d2 := f1 * 2.0 / SR
	var d3 := 333.0 / SR
	for n in 2000:
		var ph1 := fmod(n * d1, 1.0)
		var want := sin(TAU * ph1 + a * sin(TAU * fmod(n * d2, 1.0)) + b * sin(TAU * fmod(n * d3, 1.0)))
		if absf(y[n] - want) > 1e-5:
			return "two modulators at %d: %.6f, want %.6f" % [n, y[n], want]
	var fb := 2.0
	p = _flat([{shape = "sine", level = 1.0, feedback = fb}])
	y = _out(p, 2000)
	var y1 := 0.0
	var y2 := 0.0
	for n in 2000:
		var want := sin(TAU * fmod(n * d1, 1.0) + fb * 0.5 * (y1 + y2))
		y2 = y1
		y1 = want
		if absf(y[n] - want) > 1e-5:
			return "feedback at %d: %.6f, want %.6f" % [n, y[n], want]
	p = _flat([{shape = "sine", level = 1.0, level_env = 3, fm = [{from = 2, index = a}]}, {shape = "sine", level = 0.0, level_env = 2}])
	p.env2 = FLAT.duplicate(true)
	p.env2.stages = [{time_s = 0.0, level = 0.5}]
	p.env3 = FLAT.duplicate(true)
	p.env3.stages = [{time_s = 0.0, level = 0.25}]
	y = _out(p, 1000)
	for n in 1000:
		var want := 0.25 * sin(TAU * fmod(n * d1, 1.0) + a * 0.5 * sin(TAU * fmod(n * d1, 1.0)))
		if absf(y[n] - want) > 1e-5:
			return "level_env at %d: %.6f, want %.6f" % [n, y[n], want]
	return ""


## A voice whose audible oscillators all follow their own envelopes ends when those do.
func test_voice_ends_with_its_carriers() -> String:
	var p := _flat([{shape = "sine", level = 1.0, level_env = 2}, {shape = "sine", level = 0.0}])
	p.env2 = {stages = [{time_s = 0.0, level = 1.0}, {time_s = 0.05, level = 0.0}], sustain = 0}
	var core := AKSynthCore.new(p.compile())
	core.note_on(0, 60.0, 1.0)
	core.note_off(4800, 60.0)
	core.render(4800 + 2399)
	if core.voice_count() != 1:
		return "the voice should still sound during its carrier's release"
	core.render(10)
	if core.voice_count() != 0:
		return "the voice should end with its carrier's release"
	# One audible oscillator without its own envelope: the amp envelope decides, as before.
	p.oscillators = [{shape = "sine", level = 1.0, level_env = 2}, {shape = "sine", level = 0.5}]
	core = AKSynthCore.new(p.compile())
	core.note_on(0, 60.0, 1.0)
	core.note_off(4800, 60.0)
	core.render(SR)
	if core.voice_count() != 1:
		return "with an oscillator on the amp envelope (a one-shot here), the voice should go on"
	return ""


## velocity_sens and key_scaling scale an oscillator's level per note.
func test_velocity_and_key_scaling() -> String:
	var peak := func(y: PackedFloat32Array) -> float:
		var m := 0.0
		for v in y:
			m = maxf(m, absf(v))
		return m
	var p := _flat([{shape = "sine", level = 1.0, velocity_sens = 0.5}])
	var lo: float = peak.call(_out(p, 2400, 60.0, 0.0))
	if absf(lo - 0.5) > 1e-3:
		return "velocity_sens 0.5 at velocity 0: peak %.4f, want 0.5" % lo
	p = _flat([{shape = "sine", level = 1.0, key_scaling = {break_key = 60, left_db_oct = -6.0, right_db_oct = -12.0, right_curve = "exp"}}])
	var up: float = peak.call(_out(p, 2400, 84.0))
	var down: float = peak.call(_out(p, 2400, 48.0))
	# Two octaves up, exp: -12 x (2^2 - 1) = -36 dB; one octave down, lin: -6 dB.
	if absf(20.0 * log(up) / log(10.0) + 36.0) > 0.1 or absf(20.0 * log(down) / log(10.0) + 6.0) > 0.1:
		return "key scaling: %.2f dB up, %.2f dB down" % [20.0 * log(up) / log(10.0), 20.0 * log(down) / log(10.0)]
	return ""


## A dx7 operator advances exactly msfa's phase increment, with the pitch envelope (in octaves
## through the matrix) added in Q24 log frequency; a fixed one ignores it.
func test_dx7_operator_increment() -> String:
	var p := _flat([{shape = "sine", level = 1.0, dx7_freq = {mode = 0, coarse = 2, fine = 50, detune = 10}, semitones = -12.0},
		{shape = "sine", level = 0.0, dx7_freq = {mode = 1, coarse = 1, fine = 0, detune = 7}}])
	p.envelopes = [{mode = "dx7_pitch", rates = [99, 99, 99, 99], levels = [60, 60, 60, 60]}]
	p.mods = [{source = "env4", dest = "pitch", amount = 12.0}]
	var core := AKSynthCore.new(p.compile())
	core.note_on(0, 72.0, 1.0)
	core.render(65)
	var v = core.voices[0]
	var penv := AKSynthCore.DX7_PENV_TAB[60] << 19
	var want := core.freqlut(AKSynthCore.dx7_osc_logfreq(60, 0, 2, 50, 10) + penv)
	if v.dt[0] != float(want) / 16777216.0:
		return "ratio operator increment %.12f, want msfa's %d / 2^24" % [v.dt[0] * 16777216.0, want]
	var wf := core.freqlut(AKSynthCore.dx7_osc_logfreq(72, 1, 1, 0, 7))
	if v.dt[AKSynthCore.MAX_SLOT] != float(wf) / 16777216.0:
		return "fixed operator increment %.3f, want %d" % [v.dt[AKSynthCore.MAX_SLOT] * 16777216.0, wf]
	return ""


## A DX7-style patch by hand: algorithm 5 (three pairs, OP6 feedback), dx7 envelopes per operator,
## the pitch envelope and a DX7 LFO with amp modulation.
func _dx7_like() -> AKPatch:
	var alg := AKPatchLib.dx7_algorithm(5)
	var oscs := []
	var envs := []
	for op in range(1, 7):
		var fm := []
		for m: int in alg.mods[op]:
			fm.append({from = m, index = 4.0 * PI})
		oscs.append({shape = "sine", level = 1.0 if op in alg.carriers else 0.0, level_env = op + 1, fm = fm,
			dx7_freq = {mode = 1 if op == 4 else 0, coarse = [1, 2, 1, 3, 1, 5][op - 1], fine = [0, 0, 7, 0, 50, 0][op - 1], detune = 7 + op % 3},
			feedback = 4.0 * PI / 4.0 if op == alg.feedback else 0.0})
		envs.append({mode = "dx7", rates = [90 - op * 5, 40 + op, 30, 50], levels = [99, 80 - op * 3, 60, 0], output_level = 99 - op * 4,
			rate_scaling = op % 4, velocity_sens = op % 3, amp_mod_sens = op % 4, key_offset = -12,
			key_scaling = {break_point = 39, left_depth = 10, right_depth = 20, left_curve = 1, right_curve = 2}})
	var p := _flat(oscs)
	p.env2 = envs[0]
	p.env3 = envs[1]
	p.envelopes.assign(envs.slice(2))
	p.envelopes.append({mode = "dx7_pitch", rates = [80, 60, 50, 50], levels = [60, 45, 50, 50]})
	p.lfo1 = {mode = "dx7", speed = 40, delay = 10, wave = 4, sync = true, pitch_mod_depth = 20, pitch_mod_sens = 3, amp_mod_depth = 30}
	p.mods = [{source = "env8", dest = "pitch", amount = 12.0}, {source = "lfo1", dest = "pitch", amount = 12.0}]
	p.gain_db = -18.06
	p.polyphony = 16
	return p


## Native and GDScript give the same samples for operator patches, and live matches the bake.
func test_native_matches_gdscript() -> String:
	if AKDsp.nat() == null:
		return ""
	var p2 := _flat([{shape = "sine", level = 1.0, fm = [{from = 2, index = 2.0}, {from = 3, index = 0.5}], velocity_sens = 0.4,
		key_scaling = {break_key = 50, left_db_oct = -3.0, right_db_oct = -4.0, left_curve = "exp"}},
		{shape = "triangle", level = 0.2, ratio = 3.5, feedback = 1.1, level_env = 2}, {shape = "sine", level = 0.0, fixed_hz = 220.0}])
	p2.env2 = {stages = [{time_s = 0.02, level = 1.0}, {time_s = 0.2, level = 0.3, curve = "exp"}, {time_s = 0.1, level = 0.0}], sustain = 1}
	p2.unison = 2
	p2.detune_cents = 8.0
	var notes := [{time_s = 0.0, note = "C3", length_s = 0.3, velocity = 0.8}, {time_s = 0.1, note = "E4", length_s = 0.3},
		{time_s = 0.2, note = "G2", length_s = 0.15, velocity = 0.4}, {time_s = 0.3, bend = 0.5}, {time_s = 0.37, note = "C3", length_s = 0.2}]
	for pat: AKPatch in [_dx7_like(), p2]:
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


## 16 voices of a 6-operator DX7-style patch under 15% of a core. Measured (2026-11-20): about 12%;
## six plain sines alone take about 9.6%, so most of it is the per-oscillator loop, not the DX7 parts.
func test_16_dx7_voices_cost() -> String:
	if AKDsp.nat() == null:
		return ""
	var notes := []
	for i in 16:
		notes.append({time_s = 0.0, note = 40 + i * 2, velocity = 0.8, length_s = 2.0})
	var ev := AKSynth.events_for(notes)
	var c := _dx7_like().compile()
	var best := INF
	for attempt in 5:
		var t := Time.get_ticks_usec()
		AKSynth.render_events(c, ev, SR * 2)
		best = minf(best, (Time.get_ticks_usec() - t) / 1e6)
	var share := best / 2.0
	print("        16 six-operator voices: %.1f%% of a core" % (share * 100.0))
	return "" if share < 0.15 else "16 six-operator voices take %.1f%% of a core" % (share * 100.0)


## Converted DX7 factory voices against msfa's renders (render_msfa_v100.wav, from
## tools/patch_convert/render_msfa.py), when the library is on this machine: every note's SNR
## over its hold and release at least 60 dB. Between them: algorithms 6, 18, 19, 22, 25; fixed
## frequencies, feedback, the pitch envelope, vibrato, amp modulation, keyboard scaling.
func test_dx7_voices_match_msfa() -> String:
	const LIB := "D:/12_library/gak/processed_soundarchive/yamaha-dx7/yamaha-factory-rom/"
	const VOICES := ["yamaha-rom-1a-master-group-jp/02-brass-2", "yamaha-rom-1a-master-group-jp/08-piano-1",
		"yamaha-rom-1a-master-group-jp/29-refs-whisl", "yamaha-rom-2b-synth-complex-and-effects-group/13-syn-vox",
		"yamaha-rom-4a-orchestral-and-percussive-group/27-cowbell", "yamaha-rom-4b-complex-and-effects-group/19-whistles",
		"yamaha-rom-1a-master-group-jp/01-brass-1", "yamaha-rom-3a-master-group-us/31-brass-s-h"]
	if AKDsp.nat() == null or not DirAccess.dir_exists_absolute(LIB):
		return ""
	var Dx7 = load("res://tools/patch_convert/dx7.gd")
	for v: String in VOICES:
		var folder := LIB + v
		if not FileAccess.file_exists(folder + "/render_msfa_v100.wav"):
			continue
		var sc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder + "/instrument.json"))
		var rep: Dictionary = Dx7.check(Dx7.convert(sc.content.dx7.params), sc, folder)
		if float(rep.get("snr_min_db", -1.0)) < 60.0:
			return "%s: worst note %s dB against msfa (%s)" % [v, rep.get("snr_min_db"), rep.get("notes")]
	return ""
