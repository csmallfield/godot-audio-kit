# SPDX-License-Identifier: Apache-2.0
extends AKVoice


func doc() -> String:
	return "Noise through a swept filter under a bump envelope: wipes, passes, swishes."


func schema() -> Dictionary:
	return {
		length_s = param(0.55, 0.05, 4.0, "Total length"),
		low_hz = param(300.0, 20.0, 20000.0, "Cutoff at the start and end of the sweep"),
		high_hz = param(5300.0, 20.0, 20000.0, "Cutoff at the top of the sweep"),
		peak = param(0.5, 0.05, 0.95, "Where in the sound the sweep and level peak (0..1)"),
		shape = param(1.5, 0.3, 4.0, "Envelope power: higher is more pointed"),
		q = param(0.7, 0.3, 8.0, "Filter resonance"),
		mode = param(&"low", null, null, "Filter mode: low, band or high"),
		noise = param(&"white", null, null, "Noise colour: white, pink or brown"),
	}


func render(p: Dictionary, sr: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := AKDsp.samples(p.length_s, sr)
	var env := AKEnv.bump(n, p.shape, p.peak)
	var cut := PackedFloat32Array()
	cut.resize(n)
	var lo: float = p.low_hz
	var hi: float = p.high_hz
	for i in n:
		cut[i] = lo + (hi - lo) * env[i]
	var x := AKNoise.color(StringName(p.noise), n, rng)
	x = AKFilter.svf(x, cut, p.q, sr, StringName(p.mode))
	return AKDsp.mul(x, env)
