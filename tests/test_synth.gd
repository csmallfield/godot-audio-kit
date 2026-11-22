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
	p.mods = [{source = "nope", dest = "pitch", amount = 1.0}, {source = "lfo1", dest = "osc17.pitch", amount = 1.0}]
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


## Side-voice level, per-oscillator pan and the velocity curve: what each
## does, defaults unchanged, and native against GDScript.
func test_side_voices_pan_and_velocity_curve() -> String:
	var rms := func(b: AKBuffer, right := false) -> float:
		var x := b.r if right else b.l
		var s := 0.0
		for v in x:
			s += v * v
		return sqrt(s / maxf(1.0, x.size()))
	# Velocity curve: at full sensitivity, half velocity is 6 dB down linear, 12 squared.
	var p := AKPatch.new()
	p.oscillators = [{shape = "saw", level = 0.5}]
	p.velocity_sens = 1.0
	for curve in [1.0, 2.0]:
		p.velocity_curve = curve
		var hi: float = rms.call(AKSynth.render_note(p, "C4", 1.0, 0.4, 0.4))
		var lo: float = rms.call(AKSynth.render_note(p, "C4", 0.5, 0.4, 0.4))
		var db := 20.0 * log(hi / lo) / log(10.0)
		if absf(db - 6.02 * curve) > 0.3:
			return "velocity curve %.0f: half velocity %.1f dB down, want %.1f" % [curve, db, 6.02 * curve]
	# Side voices at 0 leave the middle voice alone, as loud as a single voice.
	p = AKPatch.new()
	p.oscillators = [{shape = "saw", level = 0.5}]
	var one: float = rms.call(AKSynth.render_note(p, "A3", 1.0, 0.5, 0.5))
	p.unison = 3
	p.detune_cents = 40.0
	p.unison_level = 0.0
	var mid: float = rms.call(AKSynth.render_note(p, "A3", 1.0, 0.5, 0.5))
	if absf(20.0 * log(mid / one) / log(10.0)) > 0.5:
		return "unison 3 with silent side voices should sound like one voice (%.2f against %.2f)" % [mid, one]
	# Pan: hard left is silent on the right, and two oscillators split.
	p = AKPatch.new()
	p.oscillators = [{shape = "saw", level = 0.5, pan = -1.0}]
	var b := AKSynth.render_note(p, "C4", 1.0, 0.3, 0.3)
	if rms.call(b, true) > 1e-6 or rms.call(b) < 0.05:
		return "an oscillator panned hard left should be heard only on the left"
	p.oscillators = [{shape = "saw", level = 0.5, pan = -1.0}, {shape = "sine", level = 0.5, semitones = 7.0, pan = 1.0}]
	p.unison = 3
	p.detune_cents = 20.0
	p.unison_level = 0.3
	p.velocity_curve = 2.0
	p.filter = {type = "ladder", cutoff_hz = 900.0, resonance = 0.4}
	b = AKSynth.render_note(p, "C4", 0.7, 0.3, 0.3)
	if absf(rms.call(b) - rms.call(b, true)) < 0.01:
		return "two oscillators panned apart should differ left to right"
	# Defaults stay out of describe() (bake keys unchanged); set, they're in it.
	if AKPatch.new().describe().has("unison_level") or not p.describe().has("velocity_curve"):
		return "describe() should list the new settings only when set"
	if AKDsp.nat() != null:
		var c := p.compile()
		var ev := AKSynth.events_for(_notes())
		var d := _diff(AKSynth.render_events(c, ev, roundi(SR * 0.8)), AKSynth.render_events(c, ev, roundi(SR * 0.8), SR, true))
		if d > 1e-6:
			return "native and GDScript differ by %.2e with the new settings" % d
	return ""


## A two-stage release (release_knee, release2_s): a fast drop to the knee, then the slower tail; without
## release2_s the samples don't change; native matches GDScript.
func test_two_stage_release() -> String:
	var lv := func(b: AKBuffer, t0: float, t1: float) -> float:
		var s := 0.0
		var a := int(t0 * b.sample_rate)
		var e := int(t1 * b.sample_rate)
		for i in range(a, e):
			s += b.l[i] * b.l[i]
		return 10.0 * log(s / maxf(1.0, e - a) + 1e-30) / log(10.0)
	var p := AKPatch.new()
	p.oscillators = [{shape = "saw", level = 0.5}]
	p.amp_env = {attack_s = 0.0, decay_s = 0.1, sustain = 1.0, release_s = 0.01, curve = "exp"}
	var one := AKSynth.render_note(p, "C4", 1.0, 0.3, 1.2)
	p.amp_env.release2_s = 0.0
	p.amp_env.release_knee = 0.5
	if _diff(one, AKSynth.render_note(p, "C4", 1.0, 0.3, 1.2)) > 0.0:
		return "release2_s 0 should leave the release as it was"
	p.amp_env.release_knee = 0.02   # -34 dB
	p.amp_env.release2_s = 0.4
	var b := AKSynth.render_note(p, "C4", 1.0, 0.3, 1.2)
	var held: float = lv.call(b, 0.2, 0.29)
	# The drop takes about 40 ms (r1 x ln 50); then -8.7 dB per 0.4 s.
	var k1: float = lv.call(b, 0.36, 0.38) - held
	var k2: float = lv.call(b, 0.76, 0.78) - held
	if absf(k1 + 34.0 - 8.686 * 0.03 / 0.4) > 2.0:
		return "the release should sit near the knee (-34 dB) just after the drop, got %.1f dB" % k1
	if absf(k2 - k1 + 8.686) > 1.0:
		return "the tail should fall 8.7 dB in 0.4 s, fell %.1f" % (k1 - k2)
	if lv.call(one, 0.76, 0.78) > held - 100.0:
		return "one stage should be silent by then"
	if p.tail_s() < 2.0:
		return "tail_s should follow the slower stage (%.2f)" % p.tail_s()
	if AKDsp.nat() != null:
		var c := p.compile()
		var ev := AKSynth.events_for(_notes())
		var d := _diff(AKSynth.render_events(c, ev, roundi(SR * 1.2)), AKSynth.render_events(c, ev, roundi(SR * 1.2), SR, true))
		if d > 1e-6:
			return "native and GDScript differ by %.2e with two release stages" % d
	return ""


## An LFO's phase, and a free LFO: it runs from the start of playback, so a later note picks it up where
## it is instead of starting it again. A square LFO on pan shows which half of its cycle a stretch is in.
func test_free_lfo() -> String:
	var side := func(b: AKBuffer, t0: float, t1: float) -> float:
		var d := 0.0
		var s := 0.0
		for i in range(int(t0 * b.sample_rate), int(t1 * b.sample_rate)):
			d += b.r[i] * b.r[i] - b.l[i] * b.l[i]
			s += b.r[i] * b.r[i] + b.l[i] * b.l[i]
		return d / maxf(s, 1e-30)
	var p := AKPatch.new()
	p.oscillators = [{shape = "sine", level = 0.5}]
	p.amp_env = {attack_s = 0.0, decay_s = 0.1, sustain = 1.0, release_s = 0.01}
	p.lfo1 = {shape = "square", rate_hz = 2.0, free = true}
	p.mods = [{source = "lfo1", dest = "pan", amount = 1.0}]
	var notes := [{time_s = 0.0, note = "C4", length_s = 0.3}, {time_s = 0.6, note = "C4", length_s = 0.4}]
	var b := AKSynth.render_notes(p, notes, 1.1, SR)
	var hi: float = signf(side.call(b, 0.02, 0.2))
	if hi == 0.0:
		return "the square LFO on pan should push the first note to one side"
	# Free at 2 Hz: the second note starts 0.2 cycles in, so it flips at 0.725 s (from its own start: 0.85 s).
	if signf(side.call(b, 0.62, 0.7)) != hi or signf(side.call(b, 0.76, 0.84)) != -hi:
		return "a free LFO should be where playback has taken it when the second note starts"
	p.lfo1.free = false
	b = AKSynth.render_notes(p, notes, 1.1, SR)
	if signf(side.call(b, 0.76, 0.84)) != hi:
		return "an LFO that isn't free should start again with each note"
	p.lfo1.phase = 0.5
	b = AKSynth.render_notes(p, notes, 1.1, SR)
	if signf(side.call(b, 0.62, 0.7)) != -hi:
		return "phase 0.5 should start each note in the other half of the cycle"
	if AKDsp.nat() != null:
		p.lfo1 = {shape = "sine", rate_hz = 3.3, free = true, phase = 0.3}
		var c := p.compile()
		var ev := AKSynth.events_for(_notes())
		var d := _diff(AKSynth.render_events(c, ev, roundi(SR * 1.2)), AKSynth.render_events(c, ev, roundi(SR * 1.2), SR, true))
		if d > 1e-6:
			return "native and GDScript differ by %.2e with a free LFO" % d
	return ""


## key_levels: the level follows the curve by key (straight in dB between
## points, flat past the ends), stays out of describe() when empty, and
## native matches GDScript.
func test_key_levels() -> String:
	var rms := func(b: AKBuffer) -> float:
		var s := 0.0
		for v in b.l:
			s += v * v
		return sqrt(s / maxf(1.0, b.l.size()))
	var p := AKPatch.new()
	p.oscillators = [{shape = "sine", level = 0.5}]
	var flat := {}
	for n in ["C3", "C4", "F#4", "C5", "C6"]:
		flat[n] = rms.call(AKSynth.render_note(p, n, 1.0, 0.3, 0.3))
	if AKPatch.new().describe().has("key_levels"):
		return "describe() should leave key_levels out when empty"
	p.key_levels = [[72, -6.0], [60, 0.0]]   # out of order on purpose
	var want := {"C3": 0.0, "C4": 0.0, "F#4": -3.0, "C5": -6.0, "C6": -6.0}
	for n: String in want:
		var db := 20.0 * log(rms.call(AKSynth.render_note(p, n, 1.0, 0.3, 0.3)) / flat[n]) / log(10.0)
		if absf(db - want[n]) > 0.1:
			return "key_levels: %s is %.2f dB, want %.1f" % [n, db, want[n]]
	if not p.describe().has("key_levels"):
		return "describe() should list key_levels when set"
	if AKDsp.nat() != null:
		p.oscillators = [{shape = "saw", level = 0.5}]
		p.key_levels = [[48, 3.0], [55, -2.0], [64, 1.0]]
		var c := p.compile()
		var ev := AKSynth.events_for(_notes())
		var d := _diff(AKSynth.render_events(c, ev, roundi(SR * 0.8)), AKSynth.render_events(c, ev, roundi(SR * 0.8), SR, true))
		if d > 1e-6:
			return "native and GDScript differ by %.2e with key_levels" % d
	return ""


## LFO rate as a matrix destination, the square LFO's width, and
## oscillators routed around the filter; native against GDScript.
func test_lfo_rate_width_and_filter_bypass() -> String:
	# Gate a sine with a square LFO on the amp (amp mod 1 + lfo: 2 high, 0 low).
	var gated := func(width: float, mods: Array) -> AKBuffer:
		var p := AKPatch.new()
		p.oscillators = [{shape = "sine", level = 0.3}]
		p.amp_env = {attack_s = 0.0, decay_s = 0.1, sustain = 1.0, release_s = 0.01}
		p.lfo1 = {shape = "square", rate_hz = 4.0, width = width}
		var m: Array[Dictionary] = [{source = "lfo1", dest = "amp", amount = 1.0}]
		for r: Dictionary in mods:
			m.append(r)
		p.mods = m
		return AKSynth.render_note(p, "A4", 1.0, 1.0, 1.0)
	var bursts := func(b: AKBuffer) -> int:
		var n := 0
		var on := false
		for i in range(0, b.frames(), 48):
			var loud := absf(b.l[i]) > 1e-4 or absf(b.l[mini(i + 24, b.frames() - 1)]) > 1e-4
			if loud and not on:
				n += 1
			on = loud
		return n
	var ms := func(b: AKBuffer) -> float:
		var s := 0.0
		for v in b.l:
			s += v * v
		return s / b.frames()
	var half: AKBuffer = gated.call(0.5, [])
	var quarter: AKBuffer = gated.call(0.25, [])
	var ratio: float = ms.call(quarter) / ms.call(half)
	if absf(ratio - 0.5) > 0.06:
		return "a square LFO at width 0.25 should be high half as long as at 0.5 (power ratio %.2f)" % ratio
	var n4: int = bursts.call(half)
	# velocity (1.0) -> lfo1.rate +1 octave: twice as many gates.
	var n8: int = bursts.call(gated.call(0.5, [{source = "velocity", dest = "lfo1.rate", amount = 1.0}]))
	if n4 != 4 or n8 != 8:
		return "lfo1.rate +1 octave should double a 4 Hz gate (got %d then %d)" % [n4, n8]
	# Noise around a 200 Hz low-pass keeps its highs; through it, it doesn't.
	var hf := func(filtered: bool) -> float:
		var p := AKPatch.new()
		p.oscillators = [{shape = "saw", level = 0.3}, {shape = "noise", level = 0.2, filtered = filtered}]
		p.filter = {type = "lowpass", cutoff_hz = 200.0, q = 0.7}
		var b := AKSynth.render_note(p, "C3", 1.0, 0.3, 0.3)
		var s := 0.0
		for i in range(1, b.frames()):
			s += (b.l[i] - b.l[i - 1]) * (b.l[i] - b.l[i - 1])
		return s
	if hf.call(false) < 20.0 * float(hf.call(true)):
		return "noise routed around the filter should keep its highs"
	if AKDsp.nat() != null:
		var p := AKPatch.new()
		p.oscillators = [{shape = "saw", level = 0.4}, {shape = "noise", level = 0.1, filtered = false, pan = 0.4}]
		p.filter = {type = "ladder", cutoff_hz = 400.0, resonance = 0.3}
		p.lfo1 = {shape = "square", rate_hz = 12.0, width = 0.15}
		p.env2 = {attack_s = 0.0, decay_s = 0.3, sustain = 0.0, curve = "exp"}
		p.mods = [{source = "lfo1", dest = "osc2.level", amount = 0.1}, {source = "env2", dest = "lfo1.rate", amount = 2.0},
			{source = "lfo2", dest = "lfo2.rate", amount = 0.5}, {source = "lfo2", dest = "cutoff", amount = 1.0}]
		var c := p.compile()
		var ev := AKSynth.events_for(_notes())
		var d := _diff(AKSynth.render_events(c, ev, roundi(SR * 0.8)), AKSynth.render_events(c, ev, roundi(SR * 0.8), SR, true))
		if d > 1e-6:
			return "native and GDScript differ by %.2e with LFO rate, width and bypass" % d
	return ""


func test_key_zoned_wavetables() -> String:
	# Zone 48 a sine at half level, zone 72 its second harmonic at full; levels kept.
	var spec := {zones = [{key = 48, frames = [{harmonics = [0.5]}]}, {key = 72, frames = [{harmonics = [0.0, 1.0]}]}], normalize = false}
	var amp := func(table: Dictionary, note: int, k: int) -> float:
		var p := AKPatch.new()
		p.oscillators = [{shape = "table", table = table, level = 1.0}]
		p.amp_env = {attack_s = 0.0, decay_s = 0.1, sustain = 1.0, release_s = 0.01}
		var b := AKSynth.render_note(p, note, 1.0, 0.5, 0.5)
		var f := k * 440.0 * pow(2.0, (note - 69) / 12.0)
		var re := 0.0
		var im := 0.0
		for i in range(4800, 19200):
			re += b.l[i] * cos(TAU * f * i / SR)
			im += b.l[i] * sin(TAU * f * i / SR)
		return 2.0 * sqrt(re * re + im * im) / 14400.0
	var near := spec.duplicate()
	near.blend = false
	var a50: float = amp.call(near, 50, 1)
	var b50: float = amp.call(near, 50, 2)
	var b70: float = amp.call(near, 70, 2)
	if b50 > 0.01 * a50 or absf(a50 / b70 - 0.5) > 0.02:
		return "blend off: note 50 should play the sine zone alone, at half the level of zone 72 (%.3f, %.3f, %.3f)" % [a50, b50, b70]
	var a60: float = amp.call(spec, 60, 1)
	var c60: float = amp.call(spec, 60, 2)
	if absf(a60 / b70 - 0.25) > 0.02 or absf(c60 / b70 - 0.5) > 0.02:
		return "halfway between zones should blend them evenly (%.3f, %.3f of %.3f)" % [a60, c60, b70]
	# Only the levels the harmonics need are stored, plus four below for a zoned table.
	var t := AKWavetables.build(spec)
	if t.zones != 2 or t.levels > 5 or t.data.size() != t.zones * t.frames * t.levels * AKWavetables.SIZE:
		return "a two-zone table of two harmonics should keep at most 5 levels (zones %d, levels %d)" % [t.zones, t.levels]
	if AKDsp.nat() != null:
		var p := AKPatch.new()
		p.oscillators = [{shape = "table", table = {zones = [{key = 50, frames = [{harmonics = [1.0, 0.5, 0.3]}, {harmonics = [0.2]}]},
			{key = 64, frames = [{harmonics = [1.0, 0.0, 0.6], phases = [0.0, 0.0, 0.25]}, {harmonics = [0.1, 0.1]}]}], normalize = false, blend = false},
			level = 0.5, pan = -0.5, position = 1.0}, {shape = "table", table = spec, level = 0.3, position = 0.5}]
		p.env2 = {attack_s = 0.0, decay_s = 0.2, sustain = 0.0, curve = "exp"}
		p.mods = [{source = "env2", dest = "osc.position", amount = -1.0}]
		var c := p.compile()
		var ev := AKSynth.events_for(_notes())
		var d := _diff(AKSynth.render_events(c, ev, roundi(SR * 0.8)), AKSynth.render_events(c, ev, roundi(SR * 0.8), SR, true))
		if d > 1e-6:
			return "native and GDScript differ by %.2e on zoned tables" % d
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


# Stopping a line partway through (panic: what AKSpeaker.stop sends) and
# scheduling again crashed the native core: the event list was cleared but its
# read position stayed past the end, and the next schedule erased beyond it.
func test_panic_mid_play_then_schedule() -> String:
	if not AKSynth.available():
		return ""
	var s: Object = ClassDB.instantiate(&"AKSynthStream")
	s.patch = AKPatchLib.preset(&"organ")
	for k in 4:
		s.schedule(100 * (k + 1), AKSynthCore.E_ON, 60.0 + k, 1.0)
	s.schedule(48000, AKSynthCore.E_ON, 72.0, 1.0)
	s.render_offline(1000)   # the first four played, the last still waiting
	for k in 3:
		s.panic()
		s.note_on(64.0, 1.0)
		s.render_offline(500)
	var out: Array = s.render_offline(2400)
	var peak := 0.0
	for v in out[0]:
		peak = maxf(peak, absf(v))
	if peak < 0.05:
		return "the stream is silent after a panic (%.3f)" % peak
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


# ------------------------------------------------------------------ tempo and arpeggiator

## Frequency of a sine-ish signal between two frames, from its rising zero crossings.
func _pitch(x: PackedFloat32Array, a: int, b: int) -> float:
	var first := -1
	var last := -1
	var n := 0
	for i in range(a + 1, b):
		if x[i - 1] <= 0.0 and x[i] > 0.0:
			if first < 0:
				first = i
			last = i
			n += 1
	return 0.0 if n < 2 else float(n - 1) * SR / float(last - first)


func _semis(hz: float) -> float:
	return 69.0 + 12.0 * log(hz / 440.0) / log(2.0)


## Tempo: a synced LFO at the patch's tempo, and after a tempo event, gives the
## same samples as the matching rate_hz; a synced delay the same as its time_ms.
## The new fields stay out of describe() until set.
func test_tempo_sync_lfo_and_delay() -> String:
	if AKPatch.new().describe().has("tempo_bpm") or AKPatch.new().describe().has("arp"):
		return "describe() should leave tempo_bpm and arp out until they're set"
	if not is_equal_approx(AKPatch.sync_beats("1/8."), 0.75) or not is_equal_approx(AKPatch.sync_beats("1/8t"), 1.0 / 3.0) \
			or AKPatch.sync_beats("2/1") != 8.0 or AKPatch.sync_beats(1.5) != 1.5:
		return "note lengths in beats are wrong"
	var base := AKPatch.new()
	base.oscillators = [{shape = "saw", level = 0.4}]
	base.mods = [{source = "lfo1", dest = "pitch", amount = 0.7}, {source = "lfo2", dest = "cutoff", amount = 1.0}]
	base.filter = {type = "lowpass", cutoff_hz = 1200.0}
	var notes := [{time_s = 0.0, note = "C3", length_s = 0.5}, {time_s = 0.3, note = "G3", length_s = 0.4}]
	for gd in [false, true]:
		var synced: AKPatch = base.duplicate(true)
		synced.lfo1 = {shape = "sine", rate_sync = "1/4"}
		synced.lfo2 = {shape = "triangle", rate_sync = "1/8.", free = true}
		synced.effects = [{type = "delay", time_sync = "1/8", feedback = 0.4, mix = 0.3}]
		var plain: AKPatch = base.duplicate(true)
		plain.lfo1 = {shape = "sine", rate_hz = 2.0}
		plain.lfo2 = {shape = "triangle", rate_hz = 120.0 / 60.0 / 0.75, free = true}
		plain.effects = [{type = "delay", time_ms = 250.0, feedback = 0.4, mix = 0.3}]
		var a := AKSynth.render_events(synced.compile(), AKSynth.events_for(notes), SR, SR, gd)
		var b := AKSynth.render_events(plain.compile(), AKSynth.events_for(notes), SR, SR, gd)
		if _diff(a, b) > 1e-6:
			return "synced at 120 BPM should match rate_hz and time_ms (differ by %.2e, gdscript %s)" % [_diff(a, b), gd]
		# 90 BPM from a tempo event before the notes.
		var t90 := [{time_s = 0.0, tempo_bpm = 90.0}]
		t90.append_array(notes)
		plain.lfo1.rate_hz = 1.5
		plain.lfo2.rate_hz = 90.0 / 60.0 / 0.75
		plain.effects[0].time_ms = 60000.0 / 90.0 / 2.0
		a = AKSynth.render_events(synced.compile(), AKSynth.events_for(t90), SR, SR, gd)
		b = AKSynth.render_events(plain.compile(), AKSynth.events_for(notes), SR, SR, gd)
		if _snr(b.l, a.l) < 100.0:
			return "a tempo event should retime synced LFOs and delays (SNR %.1f dB, gdscript %s)" % [_snr(b.l, a.l), gd]
		# The patch's own tempo does the same.
		synced.tempo_bpm = 90.0
		var c := AKSynth.render_events(synced.compile(), AKSynth.events_for(notes), SR, SR, gd)
		if _diff(a, c) > 1e-6:
			return "tempo_bpm 90 should sound as a 90 BPM tempo event"
	return ""


## The arpeggiator: steps on the tempo, its modes' note orders, the gate,
## octaves, velocity per key, and a seeded random order.
func test_arpeggiator_patterns() -> String:
	var p := AKPatch.new()
	p.oscillators = [{shape = "sine", level = 0.5}]
	p.amp_env = {attack_s = 0.0, decay_s = 0.1, sustain = 1.0, release_s = 0.001}
	p.tempo_bpm = 120.0
	var step := roundi(SR * 60.0 / 120.0 / 4.0)   # 1/16 at 120 BPM
	var chord := [{time_s = 0.0, note = 60, length_s = 1.0, velocity = 1.0}, {time_s = 0.0, note = 67, length_s = 1.0, velocity = 0.5}]
	var expect := {"up": [60, 67, 72, 79, 60, 67], "down": [79, 72, 67, 60, 79, 72], "updown": [60, 67, 72, 79, 72, 67, 60, 67]}
	for mode: String in expect:
		p.arp = {mode = mode, octaves = 2, rate = "1/16", gate = 0.5}
		var b := AKSynth.render_events(p.compile(), AKSynth.events_for(chord), SR, SR, true)
		var got := []
		for s in (expect[mode] as Array).size():
			got.append(roundi(_semis(_pitch(b.l, s * step + 50, s * step + step / 2 - 50))))
		if got != expect[mode]:
			return "arp %s played %s, expected %s" % [mode, got, expect[mode]]
		# Gate 0.5: silent in the second half of each step.
		var q := 0.0
		for i in range(step * 3 / 4, step - 10):
			q = maxf(q, absf(b.l[i]))
		if q > 1e-3:
			return "arp %s: a 0.5 gate should leave the second half of the step quiet (peak %.4f)" % [mode, q]
	# Velocity per key: the G (velocity 0.5) quieter than the C.
	p.arp = {mode = "up", octaves = 1, rate = "1/16", gate = 0.5}
	p.velocity_sens = 1.0
	var vb := AKSynth.render_events(p.compile(), AKSynth.events_for(chord), SR, SR, true)
	var pk := func(a: int, z: int) -> float:
		var m := 0.0
		for i in range(a, z):
			m = maxf(m, absf(vb.l[i]))
		return m
	if pk.call(step, step + step / 2) > 0.7 * pk.call(0, step / 2):
		return "each arp note should play at its key's velocity"
	# Random: the same seed repeats, another seed doesn't.
	p.arp = {mode = "random", octaves = 3, rate = "1/32", gate = 0.5}
	p.seed = 3
	var r1 := AKSynth.render_events(p.compile(), AKSynth.events_for(chord), SR, SR, true)
	var r2 := AKSynth.render_events(p.compile(), AKSynth.events_for(chord), SR, SR, true)
	p.seed = 4
	var r3 := AKSynth.render_events(p.compile(), AKSynth.events_for(chord), SR, SR, true)
	if _diff(r1, r2) != 0.0 or _diff(r1, r3) < 1e-3:
		return "random arp order should follow the seed"
	# Releasing every key stops it.
	var short := [{time_s = 0.0, note = 60, length_s = 0.2}]
	var sb := AKSynth.render_events(p.compile(), AKSynth.events_for(short), SR, SR, true)
	var after := 0.0
	for i in range(roundi(SR * 0.25), SR):
		after = maxf(after, absf(sb.l[i]))
	if after > 1e-4:
		return "the arp should stop when the last key is released"
	return ""


## Gate 1 ties steps (a legato arp plays without gaps); tempo changes
## mid-pattern move the steps; native, GDScript and live agree.
func test_arpeggiator_legato_tempo_and_native() -> String:
	var p := AKPatch.new()
	p.oscillators = [{shape = "saw", level = 0.4}]
	p.amp_env = {attack_s = 0.002, decay_s = 0.1, sustain = 0.8, release_s = 0.05}
	p.mode = "legato"
	p.glide_s = 0.01
	p.arp = {mode = "updown", octaves = 2, rate = "1/8", gate = 1.0}
	p.lfo1 = {shape = "triangle", rate_sync = "1/2"}
	p.mods = [{source = "lfo1", dest = "cutoff", amount = 1.0}]
	p.filter = {type = "lowpass", cutoff_hz = 1500.0}
	p.effects = [{type = "delay", time_sync = "1/8.", feedback = 0.3, mix = 0.25}]
	var notes := [{time_s = 0.0, note = 48, length_s = 1.2, velocity = 0.9}, {time_s = 0.1, note = 55, length_s = 1.0},
		{time_s = 0.4, tempo_bpm = 150.0}, {time_s = 0.7, note = 51, length_s = 0.3}, {time_s = 0.9, tempo_bpm = 100.0}]
	var ev := AKSynth.events_for(notes)
	var gd := AKSynth.render_events(p.compile(), ev, roundi(SR * 1.6), SR, true)
	if gd.peak() < 0.01:
		return "the legato arp is silent"
	# Tied steps: the amp envelope never releases while keys are held, so no 10 ms stretch goes quiet.
	var quiet := 0
	var longest := 0
	for i in range(200, roundi(SR * 1.15)):
		quiet = quiet + 1 if absf(gd.l[i]) < 1e-3 else 0
		longest = maxi(longest, quiet)
	if longest > SR / 100:
		return "a gate-1 legato arp shouldn't leave gaps (%d quiet samples)" % longest
	if AKDsp.nat() != null:
		var nb := AKSynth.render_events(p.compile(), ev, roundi(SR * 1.6), SR)
		if _diff(nb, gd) > 1e-6:
			return "native and GDScript arps differ by %.2e" % _diff(nb, gd)
	if AKSynth.available():
		var s: Object = ClassDB.instantiate(&"AKSynthStream")
		s.patch = p
		s.note_on(48.0, 0.9, 0.0)
		s.note_on(55.0, 1.0, 0.1)
		s.set_tempo(150.0, 0.4)
		s.note_on(51.0, 1.0, 0.7)
		s.note_off(51.0, 1.0)
		s.set_tempo(100.0, 0.9)
		s.note_off(55.0, 1.1)
		s.note_off(48.0, 1.2)
		var lr: Array = s.render_offline(roundi(SR * 1.6))
		var live := AKBuffer.new(0, SR)
		live.l = lr[0]
		live.r = lr[1]
		if _diff(live, gd) > 1e-6:
			return "the live arp differs from the bake by %.2e" % _diff(live, gd)
	return ""


# ------------------------------------------------------------------ stacks, unison pitch, smooth LFO, stereo delay

## A sine's magnitude at `hz` over x[a..b) (one DFT bin, Hann-windowed).
func _mag(x: PackedFloat32Array, a: int, b: int, hz: float) -> float:
	var re := 0.0
	var im := 0.0
	var n := b - a
	for i in n:
		var w := 0.5 - 0.5 * cos(TAU * i / n)
		var ph := TAU * hz * i / SR
		re += x[a + i] * w * cos(ph)
		im += x[a + i] * w * sin(ph)
	return sqrt(re * re + im * im) * 4.0 / n


## An oscillator's stack: one oscillator stacked 3 times is exactly unison 3;
## stacks mix with unison, FM, sync and ring the same natively and in GDScript;
## unison_pitch raises every other unison voice; unison goes to 8.
func test_oscillator_stack_and_unison_pitch() -> String:
	var notes := [{time_s = 0.0, note = 45, length_s = 0.6}, {time_s = 0.2, note = 52, length_s = 0.5}]
	var ev := AKSynth.events_for(notes)
	var a := AKPatch.new()
	a.oscillators = [{shape = "saw", level = 0.5, stack = 3, stack_cents = 15.0}]
	var b := AKPatch.new()
	b.oscillators = [{shape = "saw", level = 0.5}]
	b.unison = 3
	b.detune_cents = 15.0
	var one := AKPatch.new()
	one.oscillators = [{shape = "saw", level = 0.5, stack = 1}]
	var none := AKPatch.new()
	none.oscillators = [{shape = "saw", level = 0.5}]
	for gd in [true, false]:
		if not gd and AKDsp.nat() == null:
			continue
		var ra := AKSynth.render_events(a.compile(), ev, SR, SR, gd)
		var rb := AKSynth.render_events(b.compile(), ev, SR, SR, gd)
		if _diff(ra, rb) > 1e-9:
			return "a stack of 3 on the only oscillator should be unison 3 (differ by %.2e, gdscript %s)" % [_diff(ra, rb), gd]
		if _diff(AKSynth.render_events(one.compile(), ev, SR, SR, gd), AKSynth.render_events(none.compile(), ev, SR, SR, gd)) != 0.0:
			return "stack 1 should change nothing"
	# A stacked osc1 with unison, FM from and sync to unstacked oscillators, ring, a stacked sub.
	var p := AKPatch.new()
	p.oscillators = [{shape = "saw", level = 0.4, stack = 8, stack_cents = 25.0, fm_from = 2, fm_index = 0.8},
		{shape = "pulse", level = 0.3, sync_to = 1, semitones = 7.0}, {shape = "square", level = 0.3, semitones = -12.0, stack = 4, stack_cents = 10.0},
		{shape = "sine", level = 0.2, ring_from = 1}]
	p.unison = 3
	p.detune_cents = 8.0
	p.spread = 0.6
	p.unison_pitch = 12.0
	var gdb := AKSynth.render_events(p.compile(), ev, SR, SR, true)
	if gdb.peak() < 0.01:
		return "the stacked patch is silent"
	if AKDsp.nat() != null:
		var nb := AKSynth.render_events(p.compile(), ev, SR, SR)
		if _diff(nb, gdb) > 1e-6:
			return "native and GDScript stacks differ by %.2e" % _diff(nb, gdb)
		p.unison = 8
		var n8 := AKSynth.render_events(p.compile(), ev, SR / 4, SR)
		var g8 := AKSynth.render_events(p.compile(), ev, SR / 4, SR, true)
		if _diff(n8, g8) > 1e-6:
			return "unison 8 differs natively by %.2e" % _diff(n8, g8)
	# Unison pitch: two sine voices, the second an octave up.
	var up := AKPatch.new()
	up.oscillators = [{shape = "sine", level = 0.5}]
	up.amp_env = {attack_s = 0.0, decay_s = 0.1, sustain = 1.0, release_s = 0.05}
	up.unison = 2
	up.unison_pitch = 12.0
	var ub := AKSynth.render_events(up.compile(), AKSynth.events_for([{time_s = 0.0, note = 57, length_s = 0.8}]), SR, SR, true)
	var m1 := _mag(ub.l, 4800, 4800 + 9600, 220.0)
	var m2 := _mag(ub.l, 4800, 4800 + 9600, 440.0)
	if absf(m1 - m2) > 0.1 * m1 or m1 < 0.05:
		return "unison_pitch 12 with two voices should give equal 220 and 440 Hz (%.3f, %.3f)" % [m1, m2]
	if not AKPatch.new().describe().has("unison") or AKPatch.new().describe().has("unison_pitch"):
		return "describe() should leave unison_pitch out until it's set"
	return ""


## Smooth random: a new random value each cycle, glided to (no steps, unlike
## random); native and GDScript agree.
func test_smooth_random_lfo() -> String:
	var steps := {}
	for shape in ["random", "smooth"]:
		var p := AKPatch.new()
		p.oscillators = [{shape = "sine", level = 0.5, fixed_hz = 2000.0}]
		p.amp_env = {attack_s = 0.0, decay_s = 0.1, sustain = 1.0, release_s = 0.05}
		p.lfo1 = {shape = shape, rate_hz = 5.0}
		p.mods = [{source = "lfo1", dest = "amp", amount = 0.5}]
		p.seed = 7
		var ev := AKSynth.events_for([{time_s = 0.0, note = 60, length_s = 1.2}])
		var g := AKSynth.render_events(p.compile(), ev, SR, SR, true)
		if AKDsp.nat() != null:
			var n := AKSynth.render_events(p.compile(), ev, SR, SR)
			if _diff(n, g) > 1e-6:
				return "native and GDScript %s LFOs differ by %.2e" % [shape, _diff(n, g)]
		# Level per 2 ms (four cycles of 2 kHz): the biggest step and the range.
		var lv := []
		for w in range(10, 470):
			var m := 0.0
			for i in range(w * 96, w * 96 + 96):
				m = maxf(m, absf(g.l[i]))
			lv.append(m)
		var big := 0.0
		for i in range(1, lv.size()):
			big = maxf(big, absf(lv[i] - lv[i - 1]))
		steps[shape] = big
		if lv.max() - lv.min() < 0.05:
			return "the %s LFO should move the level (range %.3f)" % [shape, lv.max() - lv.min()]
	if steps.smooth > 0.2 * steps.random:
		return "smooth random should glide, not step (biggest 2 ms step %.4f, random's %.4f)" % [steps.smooth, steps.random]
	return ""


## The delay's modes and spread, on an impulse: stereo repeats each side,
## cross alternates sides, ping-pong starts left and bounces; spread delays one
## side. Native and GDScript agree, in a patch too.
func test_stereo_delay_modes() -> String:
	var n := SR
	var l := PackedFloat32Array()
	l.resize(n)
	var r := PackedFloat32Array()
	r.resize(n)
	l[0] = 1.0
	var d := 4800   # 100 ms
	# Where each channel's echoes land (the dry impulse at 0 aside).
	var expect := {"stereo": [[d, 2 * d, 3 * d], []], "cross": [[d, 3 * d], [2 * d]], "pingpong": [[d, 3 * d], [2 * d]]}
	for mode: String in expect:
		var spec := {type = "delay", time_ms = 100.0, feedback = 0.5, damp_hz = 20000.0, mix = 1.0, mode = mode}
		for native in [false, true]:
			var out: Array
			if native:
				if AKDsp.nat() == null:
					continue
				out = AKStreamFx.process([spec], l, r, SR)
			else:
				var chain := AKStreamFx.Chain.new([AKStreamFx.compile(spec)], SR)
				var ol := l.duplicate()
				var orr := r.duplicate()
				var io := PackedFloat64Array([0.0, 0.0])
				for i in n:
					io[0] = ol[i]
					io[1] = orr[i]
					chain.tick(io)
					ol[i] = io[0]
					orr[i] = io[1]
				out = [ol, orr]
			for ch in 2:
				var got := []
				var x: PackedFloat32Array = out[ch]
				for i in range(1, 4 * d):
					if absf(x[i]) > 0.05:
						got.append(i)
				if got != expect[mode][ch]:
					return "%s delay, %s channel: echoes at %s, expected %s (native %s)" % [mode, ["left", "right"][ch], got, expect[mode][ch], native]
	# Spread: the right side 10 ms later.
	r[0] = 1.0
	var sp: Array = AKStreamFx.process([{type = "delay", time_ms = 100.0, feedback = 0.0, damp_hz = 20000.0, mix = 1.0, spread_ms = 10.0}], l, r, SR)
	if absf(sp[0][d]) < 0.5 or absf(sp[1][d + 480]) < 0.5 or absf(sp[1][d]) > 0.05:
		return "spread_ms 10 should delay the right side's repeat by 480 samples"
	# In a patch, synced and with a tempo change: native = GDScript; "stereo" with no spread = no mode.
	var p := AKPatch.new()
	p.oscillators = [{shape = "saw", level = 0.4}]
	p.amp_env = {attack_s = 0.0, decay_s = 0.05, sustain = 0.0, release_s = 0.02}
	var notes := [{time_s = 0.0, note = 60, length_s = 0.05}, {time_s = 0.3, tempo_bpm = 140.0}, {time_s = 0.4, note = 67, length_s = 0.05}]
	var ev := AKSynth.events_for(notes)
	for mode in ["stereo", "cross", "pingpong"]:
		p.effects = [{type = "delay", time_sync = "1/8.", spread_ms = -12.0, feedback = 0.5, mix = 0.5, mode = mode}]
		var g := AKSynth.render_events(p.compile(), ev, SR, SR, true)
		if AKDsp.nat() != null:
			var nb := AKSynth.render_events(p.compile(), ev, SR, SR)
			if _diff(nb, g) > 1e-6:
				return "native and GDScript %s delays differ by %.2e" % [mode, _diff(nb, g)]
	p.effects = [{type = "delay", time_ms = 180.0, feedback = 0.5, mix = 0.5, mode = "stereo"}]
	var with_mode := AKSynth.render_events(p.compile(), ev, SR, SR, true)
	p.effects = [{type = "delay", time_ms = 180.0, feedback = 0.5, mix = 0.5}]
	if _diff(with_mode, AKSynth.render_events(p.compile(), ev, SR, SR, true)) != 0.0:
		return "mode stereo without spread should be the delay as before"
	return ""


# ------------------------------------------------------------------ OB-Xd / Helm / TAL engine work

## RMS in dB of the left channel between two times.
func _rms_db(b: AKBuffer, t0: float, t1: float, right := false) -> float:
	var x: PackedFloat32Array = b.r if right else b.l
	var s := 0.0
	var n := 0
	for i in range(roundi(t0 * SR), mini(roundi(t1 * SR), x.size())):
		s += x[i] * x[i]
		n += 1
	return 10.0 * log(s / maxf(1.0, n) + 1e-30) / log(10.0)


## Zero crossings (upward) of the left channel between two times.
func _ups(b: AKBuffer, t0: float, t1: float) -> int:
	var n := 0
	for i in range(roundi(t0 * SR) + 1, mini(roundi(t1 * SR), b.l.size())):
		if b.l[i - 1] < 0.0 and b.l[i] >= 0.0:
			n += 1
	return n


## A held note through `p`, native unless gd.
func _held(p: AKPatch, note: Variant, secs: float, gd := false) -> AKBuffer:
	var ev := AKSynth.events_for([{time_s = 0.0, note = note, length_s = secs}])
	return AKSynth.render_events(p.compile(), ev, roundi(secs * SR), SR, gd or AKDsp.nat() == null)


## Native and GDScript agree on these notes through `p` (within 1e-6), or the reason not.
func _parity(p: AKPatch, notes: Array, secs: float, what: String) -> String:
	if AKDsp.nat() == null:
		return ""
	var ev := AKSynth.events_for(notes)
	var a := AKSynth.render_events(p.compile(), ev, roundi(secs * SR))
	var b := AKSynth.render_events(p.compile(), ev, roundi(secs * SR), SR, true)
	var d := _diff(a, b)
	return "" if d < 1e-6 else "%s: native and GDScript differ by %s" % [what, d]


func _tone(hz: float) -> AKPatch:
	var p := AKPatch.new()
	p.oscillators = [{shape = "sine", level = 0.5, fixed_hz = hz}]
	p.amp_env = {attack_s = 0.0, decay_s = 1.0, sustain = 1.0, release_s = 0.01}
	p.velocity_sens = 0.0
	return p


func test_ladder_poles_and_pole_mix() -> String:
	var base := _tone(4000.0)
	base.filter = {type = "ladder", cutoff_hz = 500.0, resonance = 0.0}
	var ref := _held(base, 60, 0.3, true)
	base.filter = {type = "ladder", cutoff_hz = 500.0, resonance = 0.0, poles = 4.0}
	if _diff(ref, _held(base, 60, 0.3, true)) != 0.0:
		return "poles 4 should be the ladder as before"
	base.filter = {type = "ladder", cutoff_hz = 500.0, resonance = 0.0, pole_mix = [0, 0, 0, 0, 1]}
	if _diff(ref, _held(base, 60, 0.3, true)) != 0.0:
		return "pole_mix [0, 0, 0, 0, 1] should be the fourth pole"
	# A tone three octaves above the cutoff: about 18 dB down per pole.
	var lv := []
	for n in [1, 2, 3, 4]:
		base.filter = {type = "ladder", cutoff_hz = 500.0, resonance = 0.0, poles = float(n)}
		lv.append(_rms_db(_held(base, 60, 0.3), 0.1, 0.3))
	for i in 3:
		var drop: float = lv[i] - lv[i + 1]
		if drop < 14.0 or drop > 22.0:
			return "each pole should take about 18 dB off a tone 3 octaves up: %s" % [lv]
	base.filter = {type = "ladder", cutoff_hz = 500.0, resonance = 0.0, poles = 2.5}
	var half := _rms_db(_held(base, 60, 0.3), 0.1, 0.3)
	if half > lv[1] or half < lv[2]:
		return "poles 2.5 should sit between 2 and 3 poles: %.1f (%s)" % [half, lv]
	# The Xpander's four-pole highpass from the same poles: a tone 3 octaves below is cut, one above passes.
	var hp := [1, -4, 6, -4, 1]
	var lo := _tone(62.5)
	lo.filter = {type = "ladder", cutoff_hz = 500.0, resonance = 0.0, pole_mix = hp}
	var hi := _tone(4000.0)
	hi.filter = {type = "ladder", cutoff_hz = 500.0, resonance = 0.0, pole_mix = hp}
	var cut := _rms_db(_held(hi, 60, 0.3), 0.1, 0.3) - _rms_db(_held(lo, 60, 0.3), 0.1, 0.3)
	if cut < 50.0:
		return "the pole-mix highpass should pass 4 kHz over 62.5 Hz by 50 dB or more, got %.1f" % cut
	var rich := _rich()
	rich.filter = {type = "ladder", cutoff_hz = 900.0, resonance = 0.7, drive = 2.0, pole_mix = [0.2, -1.0, 2.0, -0.5, 0.3]}
	var r := _parity(rich, _notes(), 0.8, "pole mix")
	if r:
		return r
	rich.filter = {type = "ladder", cutoff_hz = 900.0, resonance = 0.7, poles = 1.7}
	return _parity(rich, _notes(), 0.8, "fractional poles")


func test_svf_mix_and_shelves() -> String:
	var p := _rich()
	for pair in [["lowpass", {low = 1.0}], ["highpass", {low = 0.0, high = 1.0}]]:
		p.filter = {type = pair[0], cutoff_hz = 900.0, q = 2.0, slope_db = 24.0}
		var a := _held(p, 48, 0.4, true)
		var f := {type = "mix", cutoff_hz = 900.0, q = 2.0, slope_db = 24.0}
		f.merge(pair[1], true)
		p.filter = f
		if _diff(a, _held(p, 48, 0.4, true)) != 0.0:
			return "mix %s should equal the %s type exactly" % [pair[1], pair[0]]
	# Shelves at +12 dB: the boosted side gains about 12 dB, the other side stays.
	var cases := [["lowshelf", 60.0, 12.0], ["lowshelf", 8000.0, 0.0], ["highshelf", 8000.0, 12.0], ["highshelf", 60.0, 0.0],
		["bandshelf", 700.0, 12.0], ["bandshelf", 60.0, 0.0]]
	for cs in cases:
		var t := _tone(cs[1])
		var dry := _rms_db(_held(t, 60, 0.3), 0.1, 0.3)
		t.filter = {type = cs[0], cutoff_hz = 700.0, q = 0.707, gain_db = 12.0}
		var wet := _rms_db(_held(t, 60, 0.3), 0.1, 0.3)
		if absf(wet - dry - cs[2]) > 1.5:
			return "%s +12 dB at %.0f Hz: %.1f dB, expected %.0f" % [cs[0], cs[1], wet - dry, cs[2]]
	for ft in ["mix", "lowshelf", "highshelf", "bandshelf"]:
		p.filter = {type = ft, cutoff_hz = 900.0, q = 1.5, slope_db = 24.0, low = 0.5, band = 1.0, high = 0.5, gain_db = -9.0}
		p.spread = 0.5
		var r := _parity(p, _notes(), 0.8, ft)
		if r:
			return r
	return ""


func test_fm_pitch_and_linear_modes() -> String:
	var p := AKPatch.new()
	# A 2 Hz square bends a 220 Hz carrier: +1 for the first quarter second, -1 for the next.
	p.oscillators = [{shape = "sine", level = 0.5, fixed_hz = 220.0, fm_from = 2, fm_index = 12.0, fm_mode = "pitch"},
		{shape = "square", level = 0.0, fixed_hz = 2.0}]
	p.amp_env = {attack_s = 0.0, decay_s = 1.0, sustain = 1.0, release_s = 0.01}
	var b := _held(p, 60, 0.5)
	var up := _ups(b, 0.0, 0.24)
	var down := _ups(b, 0.26, 0.5)
	if absi(up - roundi(440.0 * 0.24)) > 2 or absi(down - roundi(110.0 * 0.24)) > 2:
		return "pitch FM of 12 semitones should play 440 then 110 Hz: %d and %d crossings" % [up, down]
	p.oscillators[0].fm_mode = "linear"
	p.oscillators[0].fm_index = 100.0
	b = _held(p, 60, 0.5)
	up = _ups(b, 0.0, 0.24)
	down = _ups(b, 0.26, 0.5)
	if absi(up - roundi(320.0 * 0.24)) > 2 or absi(down - roundi(120.0 * 0.24)) > 2:
		return "linear FM of 100 Hz should play 320 then 120 Hz: %d and %d crossings" % [up, down]
	# Through zero, and with unison, stacks and a saw: no NaN, native = GDScript.
	p.oscillators = [{shape = "saw", level = 0.4, fm_from = 2, fm_index = 400.0, fm_mode = "linear", stack = 2, stack_cents = 10.0},
		{shape = "sine", level = 0.3, semitones = 7.0, fm_from = 3, fm_index = 5.0, fm_mode = "pitch"}, {shape = "triangle", level = 0.0}]
	p.unison = 2
	p.detune_cents = 8.0
	b = _held(p, 48, 0.4)
	for x in b.l:
		if is_nan(x) or absf(x) > 10.0:
			return "through-zero FM went out of range"
	return _parity(p, [{time_s = 0.0, note = 48, length_s = 0.3}, {time_s = 0.1, note = 55, length_s = 0.3}], 0.6, "FM modes")


func test_voice_pan_and_slop() -> String:
	var p := AKPatch.new()
	p.oscillators = [{shape = "saw", level = 0.5}]
	p.amp_env = {attack_s = 0.0, decay_s = 1.0, sustain = 1.0, release_s = 0.005}
	p.voice_pan = [-1.0, 1.0]
	var notes := [{time_s = 0.0, note = 60, length_s = 0.1}, {time_s = 0.2, note = 60, length_s = 0.1}, {time_s = 0.4, note = 60, length_s = 0.1}]
	var b := AKSynth.render_events(p.compile(), AKSynth.events_for(notes), roundi(0.6 * SR), SR, AKDsp.nat() == null)
	for t: Array in [[0.02, 0.08, true], [0.22, 0.28, false], [0.42, 0.48, true]]:
		var silent := _rms_db(b, t[0], t[1], t[2])
		var loud := _rms_db(b, t[0], t[1], not t[2])
		if silent > -80.0 or loud < -30.0:
			return "voice slots should alternate left, right, left: %.1f / %.1f dB at %.2f s" % [loud, silent, t[0]]
	# Slop: fixed per slot. The same key on successive slots differs in pitch; slot 1 again repeats it.
	p.voice_pan = []
	p.slop = {pitch_cents = 60.0}
	p.seed = 11
	p.oscillators = [{shape = "sine", level = 0.5}]
	notes = []
	for i in 9:
		notes.append({time_s = 0.4 * i, note = 69, length_s = 0.35})
	b = AKSynth.render_events(p.compile(), AKSynth.events_for(notes), roundi(3.6 * SR), SR, AKDsp.nat() == null)
	var counts := []
	for i in 9:
		counts.append(_ups(b, 0.4 * i + 0.05, 0.4 * i + 0.3))
	if counts[0] != counts[8] or counts.slice(0, 8).count(counts[0]) == 8:
		return "slop should give each of 8 slots its own pitch and slot 1 the same again: %s" % [counts]
	for x in counts:
		if absi(int(x) - 110) > 6:
			return "60 cents of slop moved a 440 Hz tone too far: %s" % [counts]
	if AKSynthCore.slot_rand(11, 3, 2) != AKSynthCore.slot_rand(11, 3, 2) or AKSynthCore.slot_rand(11, 3, 2) == AKSynthCore.slot_rand(12, 3, 2):
		return "slot offsets should follow the seed"
	# Every kind of slop, ADSR and stages envelopes, poly and mono: native = GDScript.
	var q := _rich()
	q.slop = {pitch_cents = 20.0, cutoff_octaves = 0.5, env_time = 0.3, level_db = 2.0}
	q.voice_pan = [-0.5, 0.5, 0.0]
	q.amp_env = {attack_s = 0.01, decay_s = 0.2, sustain = 0.6, release_s = 0.1, curve = "exp"}
	var r := _parity(q, _notes(), 0.8, "slop with ADSR")
	if r:
		return r
	q.env2 = {stages = [{time_s = 0.05, level = 1.0}, {time_s = 0.2, level = 0.2, curve = "exp"}], sustain = 1}
	r = _parity(q, _notes(), 0.8, "slop with stages")
	if r:
		return r
	q.mode = "mono"
	return _parity(q, _notes(), 0.8, "slop in mono")


func test_custom_lfo_and_extra_lfos() -> String:
	var p := _tone(440.0)
	# A step shape at 4 Hz on the level: full for the first half of each cycle, silent for the second.
	p.lfos = [{shape = "custom", points = [0.0, -1.0], interp = "step", rate_hz = 4.0}]
	p.mods = [{source = "lfo3", dest = "amp", amount = 1.0}]
	var b := _held(p, 60, 0.5)
	if _rms_db(b, 0.01, 0.12) < -20.0 or _rms_db(b, 0.13, 0.24) > -90.0 or _rms_db(b, 0.26, 0.37) < -20.0:
		return "a stepped custom LFO should gate the level on and off"
	# One-shot: a ramp from 0 to -1 over a quarter second, then held (silent).
	p.lfos = [{shape = "custom", points = [0.0, -1.0], once = true, rate_hz = 4.0}]
	b = _held(p, 60, 0.6)
	var mid := _rms_db(b, 0.11, 0.14)
	if _rms_db(b, 0.0, 0.03) < -20.0 or mid > _rms_db(b, 0.0, 0.03) - 3.0 or _rms_db(b, 0.3, 0.6) > -90.0:
		return "a one-shot custom LFO should ramp down and hold its last point"
	# Extra LFOs that nothing reads change nothing, random ones too: lfo3 and on have their own
	# random streams, so lfo1 (sine), lfo2 (random), the random source and noise keep theirs.
	var q := _rich()
	q.oscillators.append({shape = "noise", level = 0.1})
	q.mods.append({source = "lfo2", dest = "pan", amount = 0.5})
	var ev := AKSynth.events_for(_notes())
	var engines := [true, false] if AKDsp.nat() != null else [true]
	var before := []
	for gd: bool in engines:
		before.append(AKSynth.render_events(q.compile(), ev, roundi(0.8 * SR), SR, gd))
	q.lfos = [{shape = "random", rate_hz = 11.0}, {shape = "smooth", rate_hz = 3.0},
		{shape = "custom", points = [0.0, 1.0, -0.5, 0.25], rate_sync = "1/8", delay_s = 0.05}]
	for i in engines.size():
		if _diff(before[i], AKSynth.render_events(q.compile(), ev, roundi(0.8 * SR), SR, engines[i])) != 0.0:
			return "extra LFOs that nothing reads should change nothing (%s)" % ("GDScript" if engines[i] else "native")
	q.mods.append({source = "lfo3", dest = "cutoff", amount = 1.0})
	q.mods.append({source = "lfo4", dest = "osc1.pitch", amount = 0.5})
	q.mods.append({source = "lfo5", dest = "amp", amount = 0.3})
	q.mods.append({source = "env2", dest = "lfo5.rate", amount = 1.0})
	q.mods.append({source = "lfo5", dest = "lfo3.rate", amount = 1.0})
	return _parity(q, _notes(), 0.8, "lfo3 to lfo5")


## The Flavor tab's ceiling: lfo1 .. lfo8 (every shape, one synced, one free), sixteen
## oscillators linked past the eighth, and 32 matrix rows; native, GDScript and live agree,
## through two tempo changes.
func test_eight_lfos_sixteen_oscillators_32_rows() -> String:
	var p := AKPatch.new()
	var oscs: Array[Dictionary] = []
	for i in 16:
		var o := {shape = ["saw", "pulse", "sine", "triangle"][i % 4], level = 0.06, semitones = float(i % 5) * 7.0 - 12.0,
			pan = float(i % 3) - 1.0}
		oscs.append(o)
	oscs[9].merge({fm_from = 16, fm_index = 1.5})
	oscs[12].merge({sync_to = 11})
	oscs[14].merge({ring_from = 10})
	oscs[15].merge({fm = [{from = 13, index = 0.7}, {from = 9, index = 0.3}]})
	p.oscillators = oscs
	p.lfo1 = {shape = "sine", rate_hz = 5.0, delay_s = 0.05}
	p.lfo2 = {shape = "custom", points = [0.0, 1.0, 0.5, -1.0], rate_hz = 3.0}
	p.lfos = [{shape = "sine", rate_hz = 5.0, phase = 0.3}, {shape = "triangle", rate_hz = 0.7, delay_s = 0.1},
		{shape = "saw", rate_sync = "1/8"}, {shape = "square", rate_hz = 2.0, width = 0.3, free = true, phase = 0.25},
		{shape = "random", rate_hz = 6.0}, {shape = "smooth", rate_sync = "1/4", free = true}]
	p.filter = {type = "lowpass", cutoff_hz = 3000.0, q = 1.2}
	p.seed = 3
	var dests := ["pitch", "cutoff", "q", "amp", "pan", "osc16.pitch", "osc10.level", "osc10.fm", "osc13.width", "osc.position"]
	var rows: Array[Dictionary] = []
	for i in 32:
		# Rows 16..21 read lfo3 .. lfo8; rows 24..31 bend lfo1 .. lfo8's rates.
		rows.append({source = AKPatch.SOURCES[i % AKPatch.SOURCES.size()],
			dest = "lfo%d.rate" % (i - 23) if i >= 24 else dests[i % dests.size()], amount = 0.05 + 0.01 * i})
	p.mods = rows
	var c := p.compile()
	if (c.osc as Array).size() != 16 or (c.mods as Array).size() != 32 or int(c.n_lfo) != 8:
		return "the patch should compile to 16 oscillators, 32 rows and 8 LFOs (%d, %d, %d)" % [
			(c.osc as Array).size(), (c.mods as Array).size(), int(c.n_lfo)]
	var notes := [{time_s = 0.0, note = 48, length_s = 1.2, velocity = 0.9}, {time_s = 0.1, note = 55, length_s = 1.0},
		{time_s = 0.4, tempo_bpm = 150.0}, {time_s = 0.7, note = 63, length_s = 0.3}, {time_s = 0.9, tempo_bpm = 100.0}]
	var ev := AKSynth.events_for(notes)
	var gd := AKSynth.render_events(c, ev, roundi(SR * 1.6), SR, true)
	if gd.peak() < 0.01 or gd.peak() > 4.0:
		return "the patch should play (peak %.3f)" % gd.peak()
	if AKDsp.nat() != null:
		var nb := AKSynth.render_events(c, ev, roundi(SR * 1.6), SR)
		if _diff(nb, gd) > 1e-6:
			return "native and GDScript differ by %s" % _diff(nb, gd)
	if AKSynth.available():
		var s: Object = ClassDB.instantiate(&"AKSynthStream")
		s.patch = p
		s.note_on(48.0, 0.9, 0.0)
		s.note_on(55.0, 1.0, 0.1)
		s.set_tempo(150.0, 0.4)
		s.note_on(63.0, 1.0, 0.7)
		s.note_off(63.0, 1.0)
		s.set_tempo(100.0, 0.9)
		s.note_off(55.0, 1.1)
		s.note_off(48.0, 1.2)
		var lr: Array = s.render_offline(roundi(SR * 1.6))
		var live := AKBuffer.new(0, SR)
		live.l = lr[0]
		live.r = lr[1]
		if _diff(live, gd) > 1e-6:
			return "live differs from the bake by %s" % _diff(live, gd)
	return ""


## An lfoN.rate row past lfo2 bends that LFO: key (+1 an octave above C4) doubles lfo6's rate.
func test_extra_lfo_rate_row() -> String:
	var p := _tone(440.0)
	p.lfos = [{}, {}, {}, {shape = "custom", points = [0.0, -1.0], interp = "step", rate_hz = 2.0}]
	p.mods = [{source = "lfo6", dest = "amp", amount = 1.0}]
	# At 2 Hz the level is on for the first quarter second.
	var b := _held(p, 72, 0.4)
	if _rms_db(b, 0.14, 0.23) < -20.0:
		return "lfo6 at 2 Hz should still be on at 0.14..0.23 s"
	p.mods.append({source = "key", dest = "lfo6.rate", amount = 1.0})
	b = _held(p, 72, 0.4)
	if _rms_db(b, 0.01, 0.11) < -20.0 or _rms_db(b, 0.14, 0.23) > -90.0 or _rms_db(b, 0.26, 0.36) < -20.0:
		return "an lfo6.rate row of one octave should double lfo6's rate"
	return _parity(p, [{time_s = 0.0, note = 72, length_s = 0.3}], 0.4, "lfo6.rate")


func test_comb_and_pre_filter() -> String:
	var p := AKPatch.new()
	p.oscillators = [{shape = "noise", level = 0.3}]
	p.amp_env = {attack_s = 0.0, decay_s = 1.0, sustain = 1.0, release_s = 0.01}
	p.seed = 5
	var dry := _held(p, 69, 0.4, true)
	p.comb = {semitones = 0.0, feedback = 0.0}
	if _diff(dry, _held(p, 69, 0.4, true)) != 0.0:
		return "a comb with no feedback should pass the signal unchanged"
	# Tuned to 440 Hz: the output correlates with itself one period back, not half a period.
	p.comb = {semitones = 0.0, feedback = 0.95}
	var b := _held(p, 69, 0.5)
	var per := SR / 440.0
	var corr := func(lag: float) -> float:
		var s := 0.0
		var e := 0.0
		var li := roundi(lag)
		for i in range(roundi(0.2 * SR), roundi(0.45 * SR)):
			s += b.l[i] * b.l[i - li]
			e += b.l[i] * b.l[i]
		return s / e
	if float(corr.call(per)) < 0.6 or float(corr.call(per * 0.5)) > 0.3:
		return "the comb should ring at the note's period: %.2f at one period, %.2f at half" % [corr.call(per), corr.call(per * 0.5)]
	# The pre-filter: one pole each way.
	var t := _tone(5000.0)
	var lvl := _rms_db(_held(t, 60, 0.3), 0.1, 0.3)
	t.pre_filter = {lowpass_hz = 100.0}
	var low := _rms_db(_held(t, 60, 0.3), 0.1, 0.3)
	if lvl - low < 30.0 or lvl - low > 40.0:
		return "a 100 Hz one-pole lowpass should take about 34 dB off 5 kHz, took %.1f" % (lvl - low)
	t = _tone(100.0)
	lvl = _rms_db(_held(t, 60, 0.3), 0.1, 0.3)
	t.pre_filter = {highpass_hz = 5000.0}
	var high := _rms_db(_held(t, 60, 0.3), 0.15, 0.3)
	if lvl - high < 30.0:
		return "a 5 kHz one-pole highpass should cut 100 Hz by 30 dB or more, cut %.1f" % (lvl - high)
	var q := _rich()
	q.comb = {semitones = 12.0, cents = -7.0, feedback = -0.7}
	q.pre_filter = {lowpass_hz = 3000.0, highpass_hz = 80.0}
	q.spread = 0.6
	return _parity(q, _notes(), 0.8, "comb and pre-filter")


func test_filter_effect() -> String:
	var n := SR / 4
	var make := func(hz: float) -> Array:
		var l := PackedFloat32Array()
		l.resize(n)
		for i in n:
			l[i] = 0.5 * sin(TAU * hz * i / SR)
		return [l, l.duplicate()]
	var level := func(out: Array) -> float:
		var s := 0.0
		var x: PackedFloat32Array = out[0]
		for i in range(n / 2, n):
			s += x[i] * x[i]
		return 10.0 * log(s / (n / 2) + 1e-30) / log(10.0)
	var lo: Array = make.call(250.0)
	var hi: Array = make.call(4000.0)
	var drops := []
	for slope in [6.0, 12.0, 24.0]:
		var spec := {type = "filter", mode = "highpass", cutoff_hz = 1000.0, slope_db = slope}
		var outs := []
		for src: Array in [lo, hi]:
			var gd := AKStreamFx.Chain.new([AKStreamFx.compile(spec)], SR)
			var ol: PackedFloat32Array = src[0].duplicate()
			var orr: PackedFloat32Array = src[1].duplicate()
			var io := PackedFloat64Array([0.0, 0.0])
			for i in n:
				io[0] = ol[i]
				io[1] = orr[i]
				gd.tick(io)
				ol[i] = io[0]
				orr[i] = io[1]
			outs.append([ol, orr])
			if AKDsp.nat() != null:
				var nat: Array = AKStreamFx.process([spec], src[0], src[1], SR)
				var d := 0.0
				for i in n:
					d = maxf(d, absf(nat[0][i] - ol[i]))
				if d > 1e-6:
					return "filter effect (%s dB): native and GDScript differ by %s" % [slope, d]
		drops.append(float(level.call(outs[1])) - float(level.call(outs[0])))
	# Two octaves below a highpass: about 12, 24 and 48 dB under the tone above it (less for the one pole).
	if drops[0] < 9.0 or drops[1] < 20.0 or drops[2] < 40.0 or drops[0] >= drops[1] or drops[1] >= drops[2]:
		return "highpass slopes should cut 250 Hz harder at 6, 12, 24 dB: %s" % [drops]
	var lp: Array = AKStreamFx.process([{type = "filter", cutoff_hz = 1000.0, slope_db = 24.0}], hi[0], hi[1], SR)
	if float(level.call(lp)) > float(level.call(hi)) - 40.0:
		return "a 24 dB lowpass at 1 kHz should cut 4 kHz by 40 dB or more"
	return ""


## Oscillator start phases: `phase` starts every copy there, `phase_with` copies another
## oscillator's (random, unison) phases; `nyquist_clamp` holds a pitch past Nyquist under it
## instead of aliasing; a noise oscillator follows its `level_env`.
func test_start_phase_nyquist_and_noise_env() -> String:
	var p := _tone(440.0)
	# Five samples in: sin(0.29 rad) from phase 0, cos(0.29 rad) a quarter cycle on.
	var b0 := _held(p, 60, 0.05, true)
	p.oscillators = [{shape = "sine", level = 0.5, fixed_hz = 440.0, phase = 0.25}]
	var b := _held(p, 60, 0.05, true)
	# (The envelope is still rising there, so compare the two: cos / sin of 0.29 rad, about 3.4.)
	var ratio := b.l[5] / b0.l[5] if absf(b0.l[5]) > 1e-9 else 0.0
	if ratio < 2.8 or ratio > 4.0:
		return "phase 0.25 should start a sine a quarter cycle on (%.3f against %.3f)" % [b.l[5], b0.l[5]]
	# phase_with: a saw minus a saw that takes its random unison phases is silent.
	var q := AKPatch.new()
	q.oscillators = [{shape = "saw", level = 0.5}, {shape = "saw", level = -0.5}]
	q.unison = 3
	q.detune_cents = 10.0
	q.seed = 4
	q.amp_env = {attack_s = 0.0, decay_s = 1.0, sustain = 1.0, release_s = 0.01}
	if _rms_db(_held(q, 48, 0.3, true), 0.0, 0.3) < -60.0:
		return "two unison saws with their own random phases shouldn't cancel"
	q.oscillators[1].phase_with = 1
	if _rms_db(_held(q, 48, 0.3, true), 0.0, 0.3) > -120.0:
		return "a saw taking the other's start phases should cancel it exactly"
	var e := _parity(q, [{time_s = 0.0, note = 48, length_s = 0.2}], 0.3, "phase_with")
	if e != "":
		return e
	# A sine at 30 kHz aliases to 18 kHz; clamped, it plays just under Nyquist.
	var n := _tone(30000.0)
	n.filter = {type = "off"}
	var raw := _held(n, 60, 0.2, true)
	n.nyquist_clamp = true
	var held := _held(n, 60, 0.2, true)
	var top := 0.49 * SR
	if _mag(raw.l, 1000, 5800, 18000.0) < 0.1 or _mag(held.l, 1000, 5800, 18000.0) > 0.01 or _mag(held.l, 1000, 5800, top) < 0.1:
		return "nyquist_clamp should hold a 30 kHz sine at %.0f Hz instead of folding it to 18 kHz (%.3f, %.3f, %.3f)" % [
			top, _mag(raw.l, 1000, 5800, 18000.0), _mag(held.l, 1000, 5800, 18000.0), _mag(held.l, 1000, 5800, top)]
	e = _parity(n, [{time_s = 0.0, note = 60, length_s = 0.15}], 0.2, "nyquist_clamp")
	if e != "":
		return e
	# Noise following its own envelope: loud at first, gone once the envelope has decayed.
	var z := AKPatch.new()
	z.oscillators = [{shape = "noise", level = 0.5, level_env = 2}]
	z.env2 = {attack_s = 0.0, decay_s = 0.05, sustain = 0.0, release_s = 0.01}
	z.amp_env = {attack_s = 0.0, decay_s = 1.0, sustain = 1.0, release_s = 0.01}
	z.seed = 2
	var zb := _held(z, 60, 0.4, true)
	if _rms_db(zb, 0.0, 0.02) < -30.0 or _rms_db(zb, 0.3, 0.4) > -80.0:
		return "a noise oscillator should follow its level_env"
	return _parity(z, [{time_s = 0.0, note = 60, length_s = 0.3}], 0.4, "noise level_env")


## Band-limited sync: a synced saw is periodic at its master's pitch, so its energy off the
## master's harmonics (and DC) is aliasing. Band-limiting the resets brings it down to a plain
## saw's own (polyBLEP) floor: 2-3 dB less here, at the same level.
func test_band_limited_sync() -> String:
	var p := AKPatch.new()
	p.oscillators = [{shape = "saw", level = 0.0001}, {shape = "saw", level = 0.5, semitones = 14.95, sync_to = 1}]
	p.filter = {type = "off"}
	p.amp_env = {attack_s = 0.0, decay_s = 1.0, sustain = 1.0, release_s = 0.01}
	p.velocity_sens = 0.0
	var f0 := 440.0 * pow(2.0, 3.0 / 12.0)
	var resid := func(b: AKBuffer) -> Array:
		var a := 4800
		var n := 24000
		var tot := 0.0
		var mean := 0.0
		for i in range(a, a + n):
			tot += b.l[i] * b.l[i]
			mean += b.l[i]
		tot /= n
		mean /= n
		var harm := mean * mean
		var k := 1
		while k * f0 < SR * 0.5:
			var m := _mag(b.l, a, a + n, k * f0)
			harm += m * m * 0.5
			k += 1
		return [maxf(tot - harm, 1e-12) / tot, tot]
	var off: Array = resid.call(_held(p, 72, 0.6, true))
	p.band_limited_sync = true
	var on: Array = resid.call(_held(p, 72, 0.6, true))
	var gain := 10.0 * log(float(off[0]) / float(on[0])) / log(10.0)
	if gain < 1.5:
		return "band-limited sync should cut the aliasing (%.1f dB: %s to %s)" % [gain, off[0], on[0]]
	if absf(10.0 * log(float(on[1]) / float(off[1])) / log(10.0)) > 1.0:
		return "band-limited sync should keep the level"
	print("        band-limited sync: aliasing %.1f dB lower" % gain)
	return _parity(p, [{time_s = 0.0, note = 72, length_s = 0.25}], 0.3, "band-limited sync")


## Note priority (mono and legato): low keeps the lowest held key sounding when a higher one
## comes, and moves up when it's released; high the other way; last is the newest, as before.
func test_note_priority() -> String:
	var p := AKPatch.new()
	p.oscillators = [{shape = "sine", level = 0.5}]
	p.filter = {type = "off"}
	p.amp_env = {attack_s = 0.0, decay_s = 1.0, sustain = 1.0, release_s = 0.01}
	p.mode = "legato"
	var lo := AKNotes.midi_to_hz(48)
	var hi := AKNotes.midi_to_hz(55)
	# 48 held 0..0.6, 55 held 0.2..0.8 (and the reverse order for high).
	var plays := func(first: int, second: int) -> Array:
		var ev := AKSynth.events_for([{time_s = 0.0, note = first, length_s = 0.6}, {time_s = 0.2, note = second, length_s = 0.6}])
		var b := AKSynth.render_events(p.compile(), ev, roundi(0.85 * SR), SR, true)
		var out := []
		for t in [0.1, 0.4, 0.7]:
			var a := roundi(t * SR)
			out.append(lo if _mag(b.l, a, a + 4800, lo) > _mag(b.l, a, a + 4800, hi) else hi)
		return out
	p.note_priority = "low"
	if plays.call(48, 55) != [lo, lo, hi]:
		return "low priority: %s" % [plays.call(48, 55)]
	p.note_priority = "high"
	if plays.call(55, 48) != [hi, hi, lo]:
		return "high priority: %s" % [plays.call(55, 48)]
	p.note_priority = "last"
	if plays.call(48, 55) != [lo, hi, hi]:
		return "last priority: %s" % [plays.call(48, 55)]
	p.note_priority = "low"
	return _parity(p, [{time_s = 0.0, note = 48, length_s = 0.6}, {time_s = 0.2, note = 55, length_s = 0.6}], 0.85, "note priority")


## Noise colors: pink and red keep white's level, and tilt it: red has far more low end than
## white against its highs, pink in between.
func test_noise_colors() -> String:
	var tilt := {}
	for c in ["white", "pink", "red"]:
		var p := AKPatch.new()
		p.oscillators = [{shape = "noise", level = 0.5, color = c}]
		p.filter = {type = "off"}
		p.amp_env = {attack_s = 0.0, decay_s = 1.0, sustain = 1.0, release_s = 0.01}
		p.velocity_sens = 0.0
		p.seed = 3
		var b := _held(p, 60, 0.5, true)
		var lvl := _rms_db(b, 0.1, 0.5)
		var lowf := 0.0
		var highf := 0.0
		for f in [100.0, 150.0, 200.0]:
			lowf += _mag(b.l, 4800, 24000, f)
		for f in [8000.0, 9000.0, 10000.0]:
			highf += _mag(b.l, 4800, 24000, f)
		tilt[c] = [lvl, 20.0 * log(lowf / highf) / log(10.0)]
		var e := _parity(p, [{time_s = 0.0, note = 60, length_s = 0.4}], 0.5, c + " noise")
		if e != "":
			return e
	for c in ["pink", "red"]:
		if absf(float(tilt[c][0]) - float(tilt.white[0])) > 2.0:
			return "%s noise should keep white's level (%.1f against %.1f dB)" % [c, tilt[c][0], tilt.white[0]]
	if not (float(tilt.white[1]) + 10.0 < float(tilt.pink[1]) and float(tilt.pink[1]) + 10.0 < float(tilt.red[1])):
		return "low against high (dB): white %.1f, pink %.1f, red %.1f" % [tilt.white[1], tilt.pink[1], tilt.red[1]]
	return ""


## The comb as a matrix destination: comb.feedback adds feedback (a comb at 0 rings once a row
## pushes it), comb.pitch retunes it (an octave up halves its period).
## The diode-damped 2-pole (filter.diode, OB-Xf's): at small signals it is the plain filter; with
## negative `damping` it self-oscillates at the cutoff and the diodes hold the level; native and
## GDScript agree, in stereo too.
func test_diode_filter() -> String:
	var t := _tone(1000.0)
	t.oscillators[0].level = 0.001
	t.filter = {type = "lowpass", cutoff_hz = 1000.0, q = 2.0}
	var plain := _rms_db(_held(t, 60, 0.3), 0.1, 0.3)
	t.filter = {type = "lowpass", cutoff_hz = 1000.0, q = 2.0, diode = true}
	var dio := _rms_db(_held(t, 60, 0.3), 0.1, 0.3)
	if absf(dio - plain) > 0.01:
		return "at small signals the diode filter should be the plain one: %.3f dB against %.3f" % [dio, plain]
	var p := AKPatch.new()
	p.oscillators = [{shape = "saw", level = 0.3}]
	p.amp_env = {attack_s = 0.0, decay_s = 1.0, sustain = 1.0, release_s = 0.01}
	p.filter = {type = "lowpass", cutoff_hz = 1000.0, q = 10.0, diode = true}
	var calm := _rms_db(_held(p, 33, 0.6), 0.3, 0.6)
	p.filter = {type = "lowpass", cutoff_hz = 1000.0, diode = true, damping = -0.035}
	var b := _held(p, 33, 0.6)
	var peak := 0.0
	var cross := 0
	for i in range(roundi(0.3 * SR), roundi(0.6 * SR)):
		var x := b.l[i]
		if not is_finite(x):
			return "the self-oscillating diode filter should stay finite"
		peak = maxf(peak, absf(x))
		if (x >= 0.0) != (b.l[i - 1] >= 0.0):
			cross += 1
	var hz := cross / 2.0 / 0.3
	var ring := _rms_db(b, 0.3, 0.6)
	if ring < calm + 6.0 or peak > 20.0 or absf(hz - 1000.0) > 100.0:
		return "negative damping should ring near 1 kHz at a held level: %.1f dB (q 10: %.1f), peak %.2f, %.0f Hz" % [ring, calm, peak, hz]
	var r := _parity(p, [{time_s = 0.0, note = 33, length_s = 0.4}, {time_s = 0.1, note = 40, length_s = 0.3}], 0.5, "diode, self-oscillating")
	if r != "":
		return r
	p.filter = {type = "mix", cutoff_hz = 700.0, q = 4.0, low = 0.5, band = 0.3, high = 0.2, diode = true, slope_db = 24.0}
	p.unison = 2
	p.spread = 1.0
	p.mods = [{source = "env2", dest = "q", amount = 1.0}]
	p.env2 = {attack_s = 0.0, decay_s = 0.2, sustain = 0.0}
	return _parity(p, [{time_s = 0.0, note = 45, length_s = 0.4}], 0.5, "diode mix, stereo")


func test_comb_destinations() -> String:
	var p := AKPatch.new()
	p.oscillators = [{shape = "noise", level = 0.3}]
	p.amp_env = {attack_s = 0.0, decay_s = 1.0, sustain = 1.0, release_s = 0.01}
	p.env2 = {attack_s = 0.0, decay_s = 1.0, sustain = 1.0, release_s = 0.01}
	p.seed = 5
	p.comb = {semitones = 0.0, feedback = 0.0}
	var dry := _held(p, 57, 0.5, true)
	var corr := func(b: AKBuffer, lag: float) -> float:
		var s := 0.0
		var e := 0.0
		var li := roundi(lag)
		for i in range(roundi(0.2 * SR), roundi(0.45 * SR)):
			s += b.l[i] * b.l[i - li]
			e += b.l[i] * b.l[i]
		return s / e
	var per := SR / AKNotes.midi_to_hz(57)
	if float(corr.call(dry, per)) > 0.3:
		return "a comb at 0 shouldn't ring"
	p.mods = [{source = "env2", dest = "comb.feedback", amount = 0.95}]
	var rung := _held(p, 57, 0.5, true)
	if float(corr.call(rung, per)) < 0.6:
		return "a comb.feedback row should make the comb ring at the note's period (%.2f)" % corr.call(rung, per)
	p.mods.append({source = "env2", dest = "comb.pitch", amount = 12.0})
	var up := _held(p, 57, 0.5, true)
	if float(corr.call(up, per * 0.5)) < 0.6:
		return "a comb.pitch row of 12 should ring an octave up (%.2f at half the period)" % corr.call(up, per * 0.5)
	return _parity(p, [{time_s = 0.0, note = 57, length_s = 0.4}], 0.5, "comb destinations")


## retrigger_from_zero: a mono patch's second note restarts its envelopes from zero (here a slow
## attack rises again), where by default they carry on from their level.
func test_retrigger_from_zero() -> String:
	var p := AKPatch.new()
	p.oscillators = [{shape = "saw", level = 0.5}]
	p.filter = {type = "off"}
	p.amp_env = {attack_s = 0.1, decay_s = 1.0, sustain = 1.0, release_s = 0.01}
	p.mode = "mono"
	var notes := [{time_s = 0.0, note = 48, length_s = 0.6}, {time_s = 0.3, note = 55, length_s = 0.3}]
	var ev := AKSynth.events_for(notes)
	var b := AKSynth.render_events(p.compile(), ev, roundi(0.6 * SR), SR, true)
	var held := _rms_db(b, 0.31, 0.33) - _rms_db(b, 0.25, 0.29)
	p.retrigger_from_zero = true
	var z := AKSynth.render_events(p.compile(), ev, roundi(0.6 * SR), SR, true)
	var dip := _rms_db(z, 0.30, 0.31) - _rms_db(z, 0.25, 0.29)
	if absf(held) > 1.5 or dip > -10.0:
		return "the second note should carry on by default (%.1f dB) and restart from zero with the flag (%.1f dB)" % [held, dip]
	return _parity(p, notes, 0.6, "retrigger_from_zero")


## A row's `via` multiplies it by a second source: an LFO on pitch via the mod wheel does
## nothing with the wheel down and bends with it up; native and GDScript agree.
func test_mod_row_via() -> String:
	var p := _tone(440.0)
	p.oscillators = [{shape = "sine", level = 0.5}]
	p.lfo1 = {shape = "square", rate_hz = 4.0}
	var plain := _held(p, 69, 0.4, true)
	p.mods = [{source = "lfo1", via = "mod_wheel", dest = "pitch", amount = 12.0}]
	if _diff(plain, _held(p, 69, 0.4, true)) != 0.0:
		return "with the mod wheel down, a row via it should do nothing"
	var notes := [{time_s = 0.0, mod_wheel = 1.0}, {time_s = 0.0, note = 69, length_s = 0.4}]
	var b := AKSynth.render_events(p.compile(), AKSynth.events_for(notes), roundi(0.4 * SR), SR, true)
	# The square LFO is high for the first 1/8 s: an octave up there, once the wheel has glided in.
	if _mag(b.l, 3600, 5600, 880.0) < 2.0 * _mag(b.l, 3600, 5600, 440.0):
		return "with the mod wheel up, the LFO should bend the pitch an octave"
	return _parity(p, notes, 0.4, "via")


## Live edits while a note sounds, natively (AKSynthStream) and in GDScript (AKSynthCore):
## 1. turning operators on (an fm list) keeps the held note sounding, where it used to fall silent;
## 2. changing an effect's settings keeps its running state: a reverb tail rings on across the
##    edit (and across an EQ added ahead of it), where the chain used to start afresh.
func test_live_edits_keep_notes_and_tails() -> String:
	var rmsl := func(l: PackedFloat32Array, a: int, b: int) -> float:
		var s := 0.0
		for i in range(a, b):
			s += l[i] * l[i]
		return 20.0 * log(sqrt(s / (b - a)) + 1e-12) / log(10.0)
	for native in ([true, false] if AKSynth.available() else [false]):
		var tag := "native" if native else "GDScript"
		# 1. Operators turned on mid-note.
		var p := AKPatch.new()
		p.oscillators = [{shape = "saw", level = 0.5}, {shape = "noise", level = 0.0}]
		p.amp_env = {attack_s = 0.0, decay_s = 1.0, sustain = 1.0, release_s = 0.05}
		var c1 := p.compile()
		p.oscillators = [{shape = "saw", level = 0.5, fm = [{from = 2, index = 0.3}]}, {shape = "noise", level = 0.0}]
		var c2 := p.compile()
		var parts := _live_edit(native, c1, c2, 57.0, 0.0, 0.2, 0.2)
		if float(rmsl.call(parts[1], 0, parts[1].size())) < float(rmsl.call(parts[0], 4800, parts[0].size())) - 6.0:
			return "%s: a held note should keep sounding when an edit turns operators on" % tag
		# 2. A reverb tail across a settings change, and across an EQ added in front.
		var q := AKPatch.new()
		q.oscillators = [{shape = "saw", level = 0.5}]
		q.amp_env = {attack_s = 0.0, decay_s = 1.0, sustain = 1.0, release_s = 0.01}
		q.effects = [{type = "reverb", room = 0.9, mix = 0.5}]
		var r1 := q.compile()
		q.effects = [{type = "reverb", room = 0.92, mix = 0.5}]
		var r2 := q.compile()
		q.effects = [{type = "eq", high_db = -3.0}, {type = "reverb", room = 0.92, mix = 0.5}]
		var r3 := q.compile()
		for pair in [[r2, "a reverb setting"], [r3, "an EQ added ahead"]]:
			var t := _live_edit(native, r1, pair[0], 48.0, 0.1, 0.3, 0.3)
			var before := float(rmsl.call(t[0], t[0].size() - 2400, t[0].size()))
			var after := float(rmsl.call(t[1], 0, 2400))
			if after < before - 6.0:
				return "%s: the reverb tail should ring on across %s (%.1f dB to %.1f dB)" % [tag, pair[1], before, after]
	return ""


## Plays `note` (released after `off_s`, unless 0) on c1, renders `pre_s`, switches to c2,
## renders `post_s`: [before, after] (left channel).
func _live_edit(native: bool, c1: Dictionary, c2: Dictionary, note: float, off_s: float, pre_s: float, post_s: float) -> Array:
	var pre := roundi(pre_s * SR)
	var post := roundi(post_s * SR)
	if native:
		var s: Object = ClassDB.instantiate(&"AKSynthStream")
		s.set_patch_data(c1)
		s.note_on(note, 0.8, 0.0)
		if off_s > 0.0:
			s.note_off(note, off_s)
		var x: Array = s.render_offline(pre)
		s.set_patch_data(c2)
		var y: Array = s.render_offline(post)
		return [x[0], y[0]]
	var core := AKSynthCore.new(c1, SR)
	core.note_on(0, note, 0.8)
	if off_s > 0.0:
		core.note_off(roundi(off_s * SR), note)
	var a: Array = core.render(pre)
	core.set_patch(c2)
	var b: Array = core.render(post)
	return [a[0], b[0]]
