# SPDX-License-Identifier: Apache-2.0
@tool
extends AKVoice


func doc() -> String:
	return "A hand clap: a few noise bursts a few milliseconds apart, then a short band-passed tail."


func schema() -> Dictionary:
	return {
		bursts = param(3, 1, 6, "Bursts before the tail"),
		spacing_s = param(0.011, 0.002, 0.04, "Gap between bursts"),
		burst_decay_s = param(0.005, 0.001, 0.03, "Each burst's decay"),
		tail_decay_s = param(0.12, 0.01, 1.0, "Tail decay"),
		color_hz = param(1200.0, 300.0, 8000.0, "Band centre"),
		q = param(1.2, 0.3, 8.0, "Band resonance"),
	}


func render(p: Dictionary, sr: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var bursts := int(p.bursts)
	var tail_at := roundi(bursts * p.spacing_s * sr)
	var n := tail_at + AKDsp.samples(5.0 * p.tail_decay_s, sr)
	var noise := AKNoise.white(n, rng)
	var env := AKDsp.filled(n, 0.0)
	var kb := exp(-1.0 / maxf(1.0, p.burst_decay_s * sr))
	for b in bursts:
		var g := 1.0
		var at := roundi(b * p.spacing_s * sr)
		for i in range(at, mini(n, at + roundi(p.spacing_s * sr))):
			env[i] = maxf(env[i], g)
			g *= kb
	var kt := exp(-1.0 / maxf(1.0, p.tail_decay_s * sr))
	var g2 := 1.0
	for i in range(tail_at, n):
		env[i] = maxf(env[i], g2)
		g2 *= kt
	var x := AKFilter.svf(AKDsp.mul(noise, env), p.color_hz, p.q, sr, &"band")
	return AKDsp.scale(x, 1.6 / maxf(1.0, p.q))
