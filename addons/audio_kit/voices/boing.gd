# SPDX-License-Identifier: Apache-2.0
extends AKVoice


func doc() -> String:
	return "A sine whose pitch drops fast, with optional spring wobble, sub layer and click: hits, landings, thumps, boings."


func schema() -> Dictionary:
	return {
		start_hz = param(180.0, 20.0, 8000.0, "Pitch at the hit"),
		end_hz = param(45.0, 20.0, 4000.0, "Pitch it falls to"),
		drop_s = param(0.11, 0.001, 2.0, "Pitch drop time constant"),
		decay_s = param(0.28, 0.005, 4.0, "Level decay time constant"),
		wobble_hz = param(0.0, 0.0, 40.0, "Spring wobble rate; 0 = none"),
		wobble_semitones = param(2.0, 0.0, 12.0, "Wobble depth, fading with the level"),
		sub = param(0.0, 0.0, 1.0, "Sine an octave under the end pitch"),
		click = param(0.5, 0.0, 1.0, "Noise transient at the start"),
		click_hz = param(6000.0, 200.0, 20000.0, "Transient brightness"),
		length_s = param(0.0, 0.0, 8.0, "Total length; 0 = five decay times"),
	}


func render(p: Dictionary, sr: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var len_s: float = p.length_s if p.length_s > 0.0 else 5.0 * p.decay_s
	var n := AKDsp.samples(len_s, sr)
	var f := AKDsp.glide(n, sr, p.start_hz, p.end_hz, p.drop_s)
	var env := AKEnv.decay(n, sr, 0.001, p.decay_s)
	if p.wobble_hz > 0.0:
		var depth: float = p.wobble_semitones
		var rate: float = p.wobble_hz
		for i in n:
			f[i] *= pow(2.0, depth / 12.0 * sin(TAU * rate * i / sr) * env[i])
	var body := AKDsp.scale(AKDsp.mul(AKOsc.sine(f, sr), env), 0.8)
	if p.sub > 0.0:
		var sub := AKOsc.sine(AKDsp.filled(n, p.end_hz * 0.5), sr)
		AKDsp.add(body, AKDsp.mul(sub, AKEnv.decay(n, sr, 0.004, p.decay_s * 1.3)), p.sub)
	if p.click > 0.0:
		var c := AKFilter.lowpass1(AKNoise.white(n, rng), p.click_hz, sr)
		AKDsp.add(body, AKDsp.mul(c, AKEnv.decay(n, sr, 0.0005, 0.03)), p.click * 0.55)
	return body
