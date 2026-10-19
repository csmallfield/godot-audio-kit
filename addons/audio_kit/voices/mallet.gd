# SPDX-License-Identifier: Apache-2.0
extends AKVoice


func version() -> int:
	return 2

## Partial frequency ratios per material (tuned-bar approximations).
const MATERIALS := {
	wood = [1.0, 3.93, 9.2],
	metal = [1.0, 2.76, 5.4, 8.93],
	glass = [1.0, 2.32, 4.25, 6.63],
	bar = [1.0, 4.0, 10.0],
}


func doc() -> String:
	return "Modal synthesis: a few damped partials struck by a soft or hard mallet. Marimba, glockenspiel, vibes, glass, nodes and pings."


func schema() -> Dictionary:
	return {
		freq_hz = param(660.0, 40.0, 8000.0, "Pitch of the fundamental"),
		material = param(&"wood", null, null, "Partial ratios: wood, metal, glass or bar"),
		decay_s = param(0.4, 0.01, 8.0, "Fundamental's decay time constant"),
		damping = param(0.7, 0.0, 2.0, "How much faster high partials die (0 = all equal)"),
		hardness = param(0.4, 0.0, 1.0, "Mallet hardness: brighter partials and a strike click"),
		length_s = param(0.0, 0.0, 12.0, "Total length; 0 = five decay times"),
	}


func render(p: Dictionary, sr: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var len_s: float = p.length_s if p.length_s > 0.0 else 5.0 * p.decay_s
	var n := AKDsp.samples(len_s, sr)
	var ratios: Array = MATERIALS.get(String(p.material), MATERIALS.wood)
	var out := AKDsp.filled(n, 0.0)
	var hard: float = p.hardness
	var nyq := 0.45 * sr
	for k in ratios.size():
		var r := float(ratios[k])
		var f: float = p.freq_hz * r
		if f >= nyq:
			continue
		var amp := pow(r, -1.6 + 1.4 * hard)
		var dec: float = p.decay_s / pow(r, p.damping)
		# Render each partial only until it is 80 dB down (9.2 time constants).
		var nk := mini(n, roundi(9.2 * dec * sr) + 1)
		var tone := AKOsc.sine_const(nk, f, sr)
		out = AKDsp.add(out, AKDsp.mul(tone, AKEnv.decay(nk, sr, 0.0008, dec)), amp)
	if hard > 0.0:
		var nc := mini(n, roundi(0.04 * sr))
		var click := AKFilter.svf(AKNoise.white(nc, rng), minf(nyq, p.freq_hz * 6.0), 1.2, sr, &"band")
		out = AKDsp.add(out, AKDsp.mul(click, AKEnv.decay(nc, sr, 0.0002, 0.004)), hard * 0.6)
	return AKDsp.scale(out, 0.7)
