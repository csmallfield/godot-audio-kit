# SPDX-License-Identifier: Apache-2.0
extends AKVoice


func doc() -> String:
	return "A short noise burst through a resonant filter, with an optional low body: ticks, clacks, stamps, keys."


func schema() -> Dictionary:
	return {
		freq_hz = param(9000.0, 100.0, 20000.0, "Filter centre (band) or cutoff (low/high)"),
		q = param(0.7, 0.3, 30.0, "Resonance: high values ring like wood or metal"),
		mode = param(&"low", null, null, "Filter mode: low, band or high"),
		decay_s = param(0.008, 0.0005, 1.0, "Decay time constant"),
		body_hz = param(0.0, 0.0, 2000.0, "Low thump under the click; 0 = none"),
		body = param(0.5, 0.0, 1.0, "Thump level"),
		length_s = param(0.0, 0.0, 2.0, "Total length; 0 = six decay times, at least 20 ms"),
	}


func render(p: Dictionary, sr: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var len_s: float = p.length_s if p.length_s > 0.0 else maxf(0.02, 6.0 * p.decay_s)
	var n := AKDsp.samples(len_s, sr)
	var x := AKFilter.svf(AKNoise.white(n, rng), p.freq_hz, p.q, sr, StringName(p.mode))
	x = AKDsp.mul(x, AKEnv.decay(n, sr, 0.0003, p.decay_s))
	if p.body_hz > 0.0:
		var b := AKOsc.sine(AKDsp.glide(n, sr, p.body_hz * 1.6, p.body_hz, 0.006), sr)
		x = AKDsp.add(x, AKDsp.mul(b, AKEnv.decay(n, sr, 0.0005, maxf(0.01, p.decay_s * 3.0))), p.body)
	return x
