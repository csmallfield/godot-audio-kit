# SPDX-License-Identifier: Apache-2.0
# Phase distortion (shape "pd") and the cz envelope mode (docs/plans/synth-expansion-phase4.md):
# both engines against MAME's uPD933, the Casio CZ's sound chip (tools/cz_ref, tests/data/cz_ref.json),
# and against each other.
extends RefCounted

const REF := "res://tests/data/cz_ref.json"
const RATE := 40000
## The chip's output for one line at full level is 1/8 of full scale.
const CHIP_GAIN := 0.125
## Edges a sample apart (the double pulse, the resonance windows) and the chip's fine pitch
## table (the pitch envelope) keep the worst case near 29 dB; most cases are near 45 dB.
const MIN_SNR_DB := 27.0


func _patch(spec: Dictionary) -> AKPatch:
	var p := AKPatch.new()
	p.oscillators.assign(spec.oscillators)
	p.envelopes.assign(spec.envelopes)
	p.amp_env = {attack_s = 0.0, decay_s = 1.0, sustain = 1.0, release_s = 5.0}
	p.velocity_sens = 0.0
	return p


func _render(p: AKPatch, case: Dictionary, gd: bool) -> AKBuffer:
	var ev := AKSynth.events_for([{time_s = 0.0, note = int(case.note), length_s = float(case.off) / RATE}], RATE)
	return AKSynth.render_events(p.compile(), ev, int(case.frames), RATE, gd)


func test_pd_matches_the_chip() -> String:
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REF))
	for case: Dictionary in ref.cases:
		var b := _render(_patch(case.patch), case, false)
		var sig := 0.0
		var err := 0.0
		for ex: Dictionary in case.excerpts:
			var want: Array = ex.samples
			var a := int(ex.start)
			for i in want.size():
				var w := float(want[i])
				var e := w - CHIP_GAIN * b.l[a + i]
				sig += w * w
				err += e * e
		var snr := 10.0 * log(sig / maxf(err, 1e-30)) / log(10.0)
		if snr < MIN_SNR_DB:
			return "%s: %.1f dB against the chip" % [case.label, snr]
	return ""


func test_pd_parity() -> String:
	if AKDsp.nat() == null:
		return ""
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REF))
	for case: Dictionary in ref.cases:
		var p := _patch(case.patch)
		var a := _render(p, case, false)
		var b := _render(p, case, true)
		for i in a.l.size():
			if absf(a.l[i] - b.l[i]) > 1e-6:
				return "%s: native and GDScript differ at sample %d" % [case.label, i]
	# At 48 kHz, with a hand-made amount, noise modulation, a matrix row and a pan.
	var p := AKPatch.new()
	p.oscillators = [{shape = "pd", pd_wave = "saw_pulse", pd_wave2 = "double_sine", pd_amount = 0.4, pd_noise = true, level = 0.5},
		{shape = "pd", pd_wave = "resonance", pd_window = "triangle", pd_amount = 0.6, semitones = 12.0, level = 0.4, pan = 0.5}]
	p.mods = [{source = "lfo1", dest = "osc1.position", amount = 0.3}]
	p.lfo1 = {shape = "sine", rate_hz = 3.0}
	var ev := AKSynth.events_for([{time_s = 0.0, note = 48, length_s = 0.2}, {time_s = 0.05, note = 55, length_s = 0.2}])
	var x := AKSynth.render_events(p.compile(), ev, 14400)
	var y := AKSynth.render_events(p.compile(), ev, 14400, 48000, true)
	for i in x.l.size():
		if absf(x.l[i] - y.l[i]) > 1e-6 or absf(x.r[i] - y.r[i]) > 1e-6:
			return "48 kHz pd patch: native and GDScript differ at sample %d" % i
	return ""


## The cz envelope's own behaviour: the sustain step holds until the key-off, which moves on to
## the step after it; the end step stays.
func test_cz_envelope_steps() -> String:
	var p := AKPatch.new()
	p.oscillators = [{shape = "pd", pd_wave = "saw", level = 1.0, level_env = 4, filtered = false}]
	p.envelopes = [{mode = "cz", kind = "dca", steps = [[110, 127], [90, 100], [80, 0]], sustain = 1, end = 2}]
	p.velocity_sens = 0.0
	var ev := AKSynth.events_for([{time_s = 0.0, note = 60, length_s = 0.3}], RATE)
	var b := AKSynth.render_events(p.compile(), ev, RATE, RATE)
	var peak := func(a: int, n: int) -> float:
		var m := 0.0
		for i in range(a, a + n):
			m = maxf(m, absf(b.l[i]))
		return m
	# Level 100 of 127 in the chip's log volume, 2^(13 (400/511 - 1)), panned to the middle (equal power).
	var held := float(peak.call(8000, 2000))
	var want := pow(2.0, 13.0 * (400.0 / 511.0 - 1.0)) * sqrt(0.5)
	if absf(held - want) > 0.02 * want + 1e-3:
		return "sustain level %.4f, want %.4f" % [held, want]
	if float(peak.call(int(0.3 * RATE) + 4000, 2000)) > 1e-4:
		return "the release to the end step (level 0) should be silent by 0.4 s"
	if not is_equal_approx(AKPatch.env_tail_s(p.envelopes[0]), AKPatch.cz_tail_s(AKPatch._compile_env(p.envelopes[0]))):
		return "env_tail_s should use the cz tail"
	return ""
