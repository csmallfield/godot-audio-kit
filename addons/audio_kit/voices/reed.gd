# SPDX-License-Identifier: Apache-2.0
@tool
extends AKVoice
## A breathy reed lead in the spirit of a tenor or alto saxophone: a
## saw-and-pulse source through two formant resonances and an
## envelope-driven low-pass, breath noise, a scoop up into each note, and
## vibrato that arrives after the note has settled. Not a physical model;
## it's built to sit like a sax line over a band.


func doc() -> String:
	return "Saxophone-like lead: formant-filtered saw/pulse, breath noise, attack scoop, delayed vibrato, brightness that follows the envelope."


func schema() -> Dictionary:
	return {
		freq_hz = param(233.08, 40.0, 2000.0, "Pitch"),
		brightness = param(0.6, 0.0, 1.0, "How open the tone gets at the peak of the envelope (blow harder: brighter)"),
		tone_hz = param(4200.0, 500.0, 12000.0, "Low-pass ceiling at full brightness"),
		formant1_hz = param(620.0, 200.0, 1500.0, "First resonance (body)"),
		formant2_hz = param(1550.0, 600.0, 4000.0, "Second resonance (reediness)"),
		formants = param(0.8, 0.0, 2.0, "How strongly the resonances colour the tone"),
		breath = param(0.12, 0.0, 1.0, "Breath noise level"),
		growl = param(0.15, 0.0, 1.0, "Saturation for an edgier, raspier tone"),
		scoop_semitones = param(0.8, 0.0, 4.0, "How far below the note it starts"),
		scoop_s = param(0.05, 0.001, 0.5, "How fast it reaches the note"),
		vibrato_hz = param(5.3, 0.0, 9.0, "Vibrato rate"),
		vibrato_cents = param(22.0, 0.0, 100.0, "Vibrato depth"),
		vibrato_delay_s = param(0.28, 0.0, 2.0, "Time before the vibrato fades in"),
		attack_s = param(0.035, 0.001, 1.0, "Attack"),
		decay_s = param(0.35, 0.001, 4.0, "Decay to sustain"),
		sustain = param(0.78, 0.0, 1.0, "Sustain level"),
		release_s = param(0.09, 0.001, 2.0, "Release time constant after the gate"),
		gate_s = param(0.5, 0.0, 30.0, "How long the note is held"),
		length_s = param(0.0, 0.0, 30.0, "Total length; 0 = gate plus five release times"),
	}


func render(p: Dictionary, sr: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var len_s: float = p.length_s if p.length_s > 0.0 else p.gate_s + 5.0 * p.release_s
	var n := AKDsp.samples(len_s, sr)
	var hz: float = p.freq_hz
	# Pitch: scoop up from below, then delayed vibrato (small depths, so a
	# linear factor stands in for 2^(cents/1200)).
	var f := AKDsp.glide(n, sr, hz * pow(2.0, -float(p.scoop_semitones) / 12.0), hz, p.scoop_s)
	if p.vibrato_hz > 0.0 and p.vibrato_cents > 0.0:
		var vib := AKOsc.sine_const(n, p.vibrato_hz, sr)
		var ramp := PackedFloat32Array()
		ramp.resize(n)
		var d0 := roundi(float(p.vibrato_delay_s) * sr)
		var rise := maxf(1.0, 0.35 * sr)
		var depth: float = float(p.vibrato_cents) / 1200.0 * log(2.0)
		for i in n:
			ramp[i] = clampf((i - d0) / rise, 0.0, 1.0) * depth
		f = AKDsp.mul(f, AKDsp.add(AKDsp.filled(n, 1.0), AKDsp.mul(vib, ramp)))
	# Source: mostly saw with some narrow pulse for the hollow reed edge.
	var x := AKDsp.add(AKOsc.saw(f, sr), AKOsc.square(f, sr, 0.42), 0.45)
	var env := AKEnv.adsr(n, sr, p.attack_s, p.decay_s, p.sustain, p.release_s, p.gate_s)
	# Breath: band-limited noise riding the envelope, strongest at the attack.
	if p.breath > 0.0:
		var noise := AKFilter.svf(AKNoise.white(n, rng), 2400.0, 0.9, sr, &"band")
		var air := AKEnv.decay(n, sr, 0.01, 0.12)
		x = AKDsp.add(x, AKDsp.mul(noise, AKDsp.add(AKDsp.scale(air, 1.5), env, 0.6)), float(p.breath) * 2.0)
	# Brightness follows the envelope: the tone opens as it's blown.
	var cut := PackedFloat32Array()
	cut.resize(n)
	var top: float = p.tone_hz
	var b: float = p.brightness
	for i in n:
		cut[i] = maxf(hz * 1.5, top * (0.18 + 0.82 * b * env[i]))
	var body := AKFilter.svf(x, cut, 0.6, sr, &"low")
	var f1 := AKFilter.svf(body, p.formant1_hz, 2.2, sr, &"band")
	var f2 := AKFilter.svf(body, p.formant2_hz, 3.0, sr, &"band")
	var k: float = p.formants
	var y := AKDsp.add(AKDsp.add(body, f1, 1.1 * k), f2, 0.8 * k)
	if p.growl > 0.0:
		y = AKShape.drive(AKDsp.scale(y, 0.6), float(p.growl) * 0.5)
	return AKDsp.mul(AKDsp.scale(y, 0.55), env)
