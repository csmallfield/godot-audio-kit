# SPDX-License-Identifier: Apache-2.0
extends AKVoice


func doc() -> String:
	return "Two- or three-operator FM (phase modulation) with a decaying index: bells, electric piano, metallic plucks, bright basses, chimes."


func schema() -> Dictionary:
	return {
		freq_hz = param(220.0, 20.0, 8000.0, "Carrier pitch"),
		ratio = param(2.0, 0.125, 16.0, "Modulator frequency as a multiple of the carrier (integers sound harmonic)"),
		index = param(3.0, 0.0, 20.0, "Modulation depth at the attack: brightness"),
		index_end = param(0.5, 0.0, 20.0, "Depth it decays to"),
		index_decay_s = param(0.2, 0.001, 8.0, "How fast the brightness falls"),
		ratio2 = param(0.0, 0.0, 16.0, "A second modulator driving the first; 0 = off"),
		index2 = param(1.0, 0.0, 20.0, "Depth of the second modulator"),
		attack_s = param(0.003, 0.0, 4.0, "Attack"),
		decay_s = param(0.4, 0.001, 8.0, "Decay to sustain"),
		sustain = param(0.0, 0.0, 1.0, "Sustain level"),
		release_s = param(0.15, 0.001, 4.0, "Release time constant after the gate"),
		gate_s = param(0.3, 0.0, 30.0, "How long the note is held"),
		length_s = param(0.0, 0.0, 30.0, "Total length; 0 = gate plus five release times"),
	}


func render(p: Dictionary, sr: int, _rng: RandomNumberGenerator) -> PackedFloat32Array:
	var len_s: float = p.length_s if p.length_s > 0.0 else p.gate_s + 5.0 * p.release_s
	var n := AKDsp.samples(len_s, sr)
	var out := PackedFloat32Array()
	out.resize(n)
	var fc: float = p.freq_hz / sr
	var fm: float = p.freq_hz * p.ratio / sr
	var f2: float = p.freq_hz * p.ratio2 / sr
	var use2: bool = p.ratio2 > 0.0
	var i0: float = p.index
	var i1: float = p.index_end
	var k := exp(-1.0 / maxf(1.0, p.index_decay_s * sr))
	var di := i0 - i1
	var i2: float = p.index2
	var pc := 0.0
	var pm := 0.0
	var p2 := 0.0
	for i in n:
		var m2 := sin(TAU * p2) * i2 if use2 else 0.0
		var mod := sin(TAU * pm + m2)
		out[i] = sin(TAU * pc + (i1 + di) * mod)
		di *= k
		pc += fc
		pm += fm
		p2 += f2
		pc -= floorf(pc)
		pm -= floorf(pm)
		p2 -= floorf(p2)
	return AKDsp.mul(out, AKEnv.adsr(n, sr, p.attack_s, p.decay_s, p.sustain, p.release_s, p.gate_s))
