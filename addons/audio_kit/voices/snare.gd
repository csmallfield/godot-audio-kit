# SPDX-License-Identifier: Apache-2.0
extends AKVoice


func doc() -> String:
	return "A snare drum: a short pitched body plus filtered noise for the wires."


func pitch_params() -> PackedStringArray:
	return PackedStringArray(["tone_hz"])


func schema() -> Dictionary:
	return {
		tone_hz = param(190.0, 60.0, 600.0, "Body pitch"),
		tone = param(0.5, 0.0, 1.0, "Body level"),
		tone_decay_s = param(0.07, 0.005, 1.0, "Body decay"),
		noise = param(0.8, 0.0, 1.0, "Wire (noise) level"),
		noise_hz = param(5000.0, 500.0, 16000.0, "Wire brightness"),
		noise_decay_s = param(0.14, 0.01, 2.0, "Wire decay"),
	}


func render(p: Dictionary, sr: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := AKDsp.samples(5.0 * maxf(p.tone_decay_s, p.noise_decay_s), sr)
	var body := AKOsc.sine(AKDsp.glide(n, sr, p.tone_hz * 1.5, p.tone_hz, 0.01), sr)
	body = AKDsp.mul(body, AKEnv.decay(n, sr, 0.0005, p.tone_decay_s))
	var wires := AKFilter.svf(AKNoise.white(n, rng), p.noise_hz, 0.7, sr, &"band")
	wires = AKDsp.add(wires, AKFilter.highpass1(AKNoise.white(n, rng), p.noise_hz * 0.5, sr), 0.5)
	wires = AKDsp.mul(wires, AKEnv.decay(n, sr, 0.0005, p.noise_decay_s))
	var x := AKDsp.scale(body, p.tone)
	x = AKDsp.add(x, wires, p.noise * 1.2)
	return AKDsp.scale(x, 0.8)
