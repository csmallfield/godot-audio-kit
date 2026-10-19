# SPDX-License-Identifier: Apache-2.0
extends AKVoice

const SHAPES := [&"sine", &"triangle", &"saw", &"square"]


func doc() -> String:
	return "A morphing oscillator (sine, triangle, saw, square) with unison detune, a sub, and a low-pass with its own envelope: basses, pads, leads, stabs, arps."


func schema() -> Dictionary:
	return {
		freq_hz = param(110.0, 20.0, 8000.0, "Pitch"),
		position = param(0.66, 0.0, 1.0, "Shape: 0 sine, 0.33 triangle, 0.66 saw, 1 square, blended between"),
		unison = param(1, 1, 7, "Stacked detuned voices (thicker, costs more)"),
		detune_cents = param(12.0, 0.0, 100.0, "Spread of the unison voices"),
		sub = param(0.0, 0.0, 1.0, "Sine one octave down"),
		cutoff_hz = param(1800.0, 40.0, 18000.0, "Low-pass cutoff after the envelope settles"),
		env_octaves = param(2.0, 0.0, 6.0, "How far the envelope opens the filter above the cutoff"),
		filter_decay_s = param(0.18, 0.001, 8.0, "How fast the filter closes"),
		q = param(0.9, 0.3, 10.0, "Filter resonance"),
		attack_s = param(0.004, 0.0, 4.0, "Attack"),
		decay_s = param(0.25, 0.001, 8.0, "Decay to sustain"),
		sustain = param(0.6, 0.0, 1.0, "Sustain level"),
		release_s = param(0.1, 0.001, 4.0, "Release time constant after the gate"),
		gate_s = param(0.25, 0.0, 30.0, "How long the note is held"),
		length_s = param(0.0, 0.0, 30.0, "Total length; 0 = gate plus five release times"),
	}


func render(p: Dictionary, sr: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var len_s: float = p.length_s if p.length_s > 0.0 else p.gate_s + 5.0 * p.release_s
	var n := AKDsp.samples(len_s, sr)
	var out := AKDsp.filled(n, 0.0)
	var pos: float = clampf(p.position, 0.0, 1.0) * 3.0
	var a := mini(2, floori(pos))
	var w := pos - a
	var voices := clampi(int(p.unison), 1, 7)
	for u in voices:
		var spread := 0.0 if voices == 1 else (float(u) / (voices - 1) - 0.5) * 2.0
		var f := AKDsp.filled(n, p.freq_hz * pow(2.0, spread * p.detune_cents / 1200.0))
		var ph := rng.randf() if voices > 1 else 0.0
		var x := _shape(SHAPES[a], f, sr, ph)
		if w > 0.0:
			AKDsp.scale(x, 1.0 - w)
			AKDsp.add(x, _shape(SHAPES[a + 1], f, sr, ph), w)
		AKDsp.add(out, x, 1.0 / sqrt(voices))
	if p.sub > 0.0:
		AKDsp.add(out, AKOsc.sine_const(n, p.freq_hz * 0.5, sr), p.sub)
	var cut := PackedFloat32Array()
	cut.resize(n)
	var k := exp(-1.0 / maxf(1.0, p.filter_decay_s * sr))
	var e := 1.0
	var base: float = p.cutoff_hz
	var oct: float = p.env_octaves
	for i in n:
		cut[i] = base * pow(2.0, oct * e)
		e *= k
	out = AKFilter.svf(out, cut, p.q, sr, &"low")
	AKDsp.mul(out, AKEnv.adsr(n, sr, p.attack_s, p.decay_s, p.sustain, p.release_s, p.gate_s))
	return AKDsp.scale(out, 0.6)


static func _shape(s: StringName, f: PackedFloat32Array, sr: int, ph: float) -> PackedFloat32Array:
	match s:
		&"triangle": return AKOsc.triangle(f, sr, ph)
		&"saw": return AKOsc.saw(f, sr, ph)
		&"square": return AKOsc.square(f, sr, 0.5, ph)
	return AKOsc.sine(f, sr, ph)
