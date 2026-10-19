# SPDX-License-Identifier: Apache-2.0
@tool
extends AKVoice


func doc() -> String:
	return "An oscillator with an ADSR envelope, optional glide and vibrato: beeps, blips, line-up tones, chimes."


func schema() -> Dictionary:
	return {
		wave = param(&"sine", null, null, "sine, triangle, saw, square or pulse"),
		width = param(0.5, 0.01, 0.99, "Pulse width (pulse only)"),
		freq_hz = param(880.0, 20.0, 20000.0, "Start pitch"),
		end_hz = param(0.0, 0.0, 20000.0, "Glide target; 0 = no glide"),
		glide_s = param(0.05, 0.001, 4.0, "Glide time constant"),
		vibrato_hz = param(0.0, 0.0, 20.0, "Vibrato rate; 0 = none"),
		vibrato_semitones = param(0.3, 0.0, 12.0, "Vibrato depth"),
		attack_s = param(0.002, 0.0, 4.0, "Attack"),
		decay_s = param(0.05, 0.001, 4.0, "Decay to sustain"),
		sustain = param(0.0, 0.0, 1.0, "Sustain level"),
		release_s = param(0.05, 0.001, 4.0, "Release time constant after the gate"),
		gate_s = param(0.15, 0.0, 30.0, "How long the note is held"),
		length_s = param(0.0, 0.0, 30.0, "Total length; 0 = gate plus five release times"),
	}


func render(p: Dictionary, sr: int, _rng: RandomNumberGenerator) -> PackedFloat32Array:
	var len_s: float = p.length_s if p.length_s > 0.0 else p.gate_s + 5.0 * p.release_s
	var n := AKDsp.samples(len_s, sr)
	var f: PackedFloat32Array
	if p.end_hz > 0.0:
		f = AKDsp.glide(n, sr, p.freq_hz, p.end_hz, p.glide_s)
	else:
		f = AKDsp.filled(n, p.freq_hz)
	if p.vibrato_hz > 0.0:
		var depth: float = p.vibrato_semitones
		var rate: float = p.vibrato_hz
		for i in n:
			f[i] *= pow(2.0, depth / 12.0 * sin(TAU * rate * i / sr))
	var x := AKOsc.wave(StringName(p.wave), f, sr, p.width)
	var env := AKEnv.adsr(n, sr, p.attack_s, p.decay_s, p.sustain, p.release_s, p.gate_s)
	return AKDsp.mul(x, env)
