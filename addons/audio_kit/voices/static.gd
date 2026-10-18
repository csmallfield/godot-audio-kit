# SPDX-License-Identifier: Apache-2.0
extends AKVoice


func doc() -> String:
	return "Band-limited hiss with random crackles and optional flicker: TV static, radio noise, vinyl crackle, decoding glitches."


func schema() -> Dictionary:
	return {
		length_s = param(1.0, 0.02, 30.0, "Total length"),
		hiss = param(0.4, 0.0, 1.0, "Level of the noise floor"),
		color_hz = param(2500.0, 100.0, 18000.0, "Centre of the hiss band"),
		q = param(0.6, 0.2, 10.0, "Width of the hiss band (higher = narrower)"),
		crackles_per_s = param(40.0, 0.0, 2000.0, "Average crackle rate"),
		crackle = param(0.7, 0.0, 1.0, "Crackle level"),
		flicker_hz = param(0.0, 0.0, 60.0, "Random level steps per second; 0 = steady"),
		flicker_depth = param(0.6, 0.0, 1.0, "How deep the flicker dips"),
		fade_s = param(0.01, 0.0, 2.0, "Fade in and out"),
	}


func render(p: Dictionary, sr: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := AKDsp.samples(p.length_s, sr)
	var x := AKDsp.scale(AKFilter.svf(AKNoise.white(n, rng), p.color_hz, p.q, sr, &"band"), p.hiss * (1.0 + p.q))
	var count := roundi(p.crackles_per_s * p.length_s)
	var k := exp(-1.0 / (0.0015 * sr))
	for c in count:
		var at := rng.randi_range(0, maxi(0, n - 1))
		var g: float = p.crackle * rng.randf_range(0.3, 1.0)
		var j := 0
		while at + j < n and g > 0.002:
			x[at + j] += g * rng.randf_range(-1.0, 1.0)
			g *= k
			j += 1
	if p.flicker_hz > 0.0:
		var step := maxi(1, roundi(sr / p.flicker_hz))
		var level := 1.0
		var target := 1.0
		for i in n:
			if i % step == 0:
				target = 1.0 - rng.randf() * p.flicker_depth
			level += (target - level) * 0.01
			x[i] *= level
	return AKEnv.fade(x, sr, p.fade_s, p.fade_s)
