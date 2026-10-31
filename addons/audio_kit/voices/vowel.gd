# SPDX-License-Identifier: Apache-2.0
@tool
extends AKVoice
## A sung vowel, for pseudo-speech records and choirs of one: a buzzy source
## (a saw, its spectrum flattened the way lips radiate it, plus a little
## breath) through three formant resonators in series, as in a cascade
## formant synthesiser. Nothing bypasses the resonators, so the vowel is the
## whole sound, not a tint on it (the reed voice's formants colour a dry tone).
##
## Typical formants (Hz, F1 / F2 / F3): ee 270 / 2290 / 3010, eh 530 / 1840 /
## 2480, ah 730 / 1090 / 2440, oh 570 / 840 / 2410, oo 300 / 870 / 2240.


func doc() -> String:
	return "Sung vowel: a saw and breath through three formant resonators in series (a cascade formant synth); set the formants for ee, ah, oo ..."


func schema() -> Dictionary:
	return {
		freq_hz = param(220.0, 40.0, 1000.0, "Pitch"),
		f1_hz = param(730.0, 150.0, 1200.0, "First formant: low for ee and oo, high for ah"),
		f2_hz = param(1090.0, 500.0, 3000.0, "Second formant: high for ee, low for oo"),
		f3_hz = param(2440.0, 1500.0, 4000.0, "Third formant"),
		bw1_hz = param(90.0, 30.0, 400.0, "First formant's bandwidth (narrower: more resonant)"),
		bw2_hz = param(120.0, 30.0, 500.0, "Second formant's bandwidth"),
		bw3_hz = param(170.0, 30.0, 600.0, "Third formant's bandwidth"),
		breath = param(0.04, 0.0, 1.0, "Breath noise through the formants (whisper at 1)"),
		vibrato_hz = param(5.5, 0.0, 9.0, "Vibrato rate"),
		vibrato_cents = param(10.0, 0.0, 100.0, "Vibrato depth"),
		attack_s = param(0.02, 0.001, 1.0, "Attack"),
		decay_s = param(0.1, 0.001, 4.0, "Decay to sustain"),
		sustain = param(0.85, 0.0, 1.0, "Sustain level"),
		release_s = param(0.08, 0.001, 2.0, "Release time constant after the gate"),
		gate_s = param(0.5, 0.0, 30.0, "How long the note is held"),
		length_s = param(0.0, 0.0, 30.0, "Total length; 0 = gate plus five release times"),
	}


func render(p: Dictionary, sr: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var len_s: float = p.length_s if p.length_s > 0.0 else p.gate_s + 5.0 * p.release_s
	var n := AKDsp.samples(len_s, sr)
	var hz: float = p.freq_hz
	var f := AKDsp.filled(n, hz)
	if p.vibrato_hz > 0.0 and p.vibrato_cents > 0.0:
		var vib := AKOsc.sine_const(n, p.vibrato_hz, sr)
		f = AKDsp.mul(f, AKDsp.add(AKDsp.filled(n, 1.0), AKDsp.scale(vib, float(p.vibrato_cents) / 1200.0 * log(2.0))))
	# The source: a saw (falling 6 dB an octave) differenced (rising 6 dB an
	# octave, as the lips radiate), so every harmonic enters the formants level.
	var saw := AKOsc.saw(f, sr)
	var x := PackedFloat32Array()
	x.resize(n)
	var prev := 0.0
	for i in n:
		x[i] = (saw[i] - prev) * 0.5
		prev = saw[i]
	# Breath: white noise is already flat.
	if p.breath > 0.0:
		x = AKDsp.add(x, AKNoise.white(n, rng), float(p.breath) * hz / sr * 4.0)
	# Three resonators in series; each is scaled by 1/Q so its peak is about
	# unity and the formants' levels come from the cascade, as in speech.
	for k in [[p.f1_hz, p.bw1_hz], [p.f2_hz, p.bw2_hz], [p.f3_hz, p.bw3_hz]]:
		var q := maxf(0.5, float(k[0]) / float(k[1]))
		x = AKDsp.scale(AKFilter.svf(x, float(k[0]), q, sr, &"low"), 1.0 / q)
	var env := AKEnv.adsr(n, sr, p.attack_s, p.decay_s, p.sustain, p.release_s, p.gate_s)
	return AKDsp.mul(AKDsp.scale(x, sr / hz * 8.0), env)
