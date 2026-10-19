# SPDX-License-Identifier: Apache-2.0
extends AKVoice

## Square-wave cluster of the TR-808 cymbal circuit (Hz).
const METAL := [205.3, 304.4, 369.6, 522.7, 540.0, 800.0]


func doc() -> String:
	return "A hi-hat or cymbal: a cluster of square waves and noise through a high band. Short decay is closed, long is open."


func pitch_params() -> PackedStringArray:
	return PackedStringArray()


func schema() -> Dictionary:
	return {
		decay_s = param(0.05, 0.005, 3.0, "Decay: short closed, long open or ride"),
		tone_hz = param(8000.0, 2000.0, 16000.0, "Centre of the band"),
		metal = param(0.6, 0.0, 1.0, "Metallic squares versus plain noise"),
		tune = param(1.0, 0.5, 2.0, "Scales the metal cluster"),
	}


func render(p: Dictionary, sr: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := AKDsp.samples(maxf(0.02, 5.0 * p.decay_s), sr)
	var x := AKDsp.scale(AKNoise.white(n, rng), 1.0 - p.metal)
	if p.metal > 0.0:
		for f in METAL:
			AKDsp.add(x, AKOsc.square(AKDsp.filled(n, float(f) * p.tune), sr, 0.5, rng.randf()), p.metal / 3.0)
	x = AKFilter.svf(x, p.tone_hz, 1.0, sr, &"band")
	x = AKFilter.highpass1(x, p.tone_hz * 0.6, sr)
	AKDsp.mul(x, AKEnv.decay(n, sr, 0.0003, p.decay_s))
	return AKDsp.scale(x, 1.2)
