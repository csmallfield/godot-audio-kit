# SPDX-License-Identifier: Apache-2.0
@tool
extends AKVoice


func doc() -> String:
	return "A train of clicks whose rate changes over the sound: ratchets, zips, gear teeth, stepped slides, film rattle."


func schema() -> Dictionary:
	return {
		length_s = param(0.3, 0.02, 8.0, "Total length"),
		start_rate_hz = param(30.0, 1.0, 400.0, "Clicks per second at the start"),
		end_rate_hz = param(14.0, 1.0, 400.0, "Clicks per second at the end"),
		click_hz = param(3000.0, 100.0, 18000.0, "Click filter centre"),
		q = param(3.0, 0.3, 30.0, "Click resonance"),
		click_decay_s = param(0.004, 0.0005, 0.1, "Each click's decay"),
		jitter = param(0.1, 0.0, 0.5, "Seeded timing wobble, as a fraction of the gap"),
		accent_every = param(0.0, 0.0, 16.0, "Every nth click louder; 0 = even"),
		fade = param(0.3, 0.0, 1.0, "Level fall across the sound (0 = none)"),
	}


func render(p: Dictionary, sr: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := AKDsp.samples(p.length_s, sr)
	var exc := AKDsp.filled(n, 0.0)
	var burst := maxi(8, roundi(p.click_decay_s * 6.0 * sr))
	var k := exp(-1.0 / maxf(1.0, p.click_decay_s * sr))
	var t := 0.0
	var idx := 0
	var accent := int(p.accent_every)
	while t < n:
		var u := t / n
		var level: float = (1.0 - p.fade * u) * (1.0 if accent <= 0 or idx % accent == 0 else 0.55)
		var start := int(t)
		var g := level
		for j in burst:
			if start + j >= n:
				break
			exc[start + j] += rng.randf_range(-1.0, 1.0) * g
			g *= k
		var rate := lerpf(p.start_rate_hz, p.end_rate_hz, u)
		var gap := sr / maxf(1.0, rate)
		t += gap * (1.0 + rng.randf_range(-1.0, 1.0) * p.jitter)
		idx += 1
	var y := AKFilter.svf(exc, p.click_hz, p.q, sr, &"band")
	# The band-pass gain rises with q; normalise so the patch level is stable.
	var pk := 0.0
	for v in y:
		pk = maxf(pk, absf(v))
	return AKDsp.scale(y, 0.8 / pk) if pk > 0.0 else y
