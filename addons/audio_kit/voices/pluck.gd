# SPDX-License-Identifier: Apache-2.0
@tool
extends AKVoice


func doc() -> String:
	return "A Karplus-Strong plucked string: letter plucks, harp-like runs, muted pings."


func schema() -> Dictionary:
	return {
		freq_hz = param(440.0, 30.0, 4000.0, "Pitch"),
		decay_s = param(0.6, 0.02, 8.0, "Time to fall to 1/e"),
		brightness = param(0.5, 0.0, 1.0, "0 dark and soft, 1 bright and ringing"),
		tone_hz = param(9000.0, 200.0, 20000.0, "Low-pass after the string"),
		length_s = param(0.0, 0.0, 10.0, "Total length; 0 = four decay times"),
	}


func render(p: Dictionary, sr: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var len_s: float = p.length_s if p.length_s > 0.0 else 4.0 * p.decay_s
	var n := AKDsp.samples(len_s, sr)
	var x := AKDelay.karplus(n, sr, p.freq_hz, p.decay_s, p.brightness, rng)
	return AKFilter.lowpass1(x, p.tone_hz, sr)
