# SPDX-License-Identifier: Apache-2.0
@tool
extends AKVoice


func doc() -> String:
	return "A kick drum: a sine that drops from a punch pitch to its tune, a click, and optional drive."


func pitch_params() -> PackedStringArray:
	return PackedStringArray(["tune_hz"])


func schema() -> Dictionary:
	return {
		tune_hz = param(50.0, 25.0, 200.0, "Pitch the body settles at"),
		punch = param(3.0, 0.0, 10.0, "Start pitch as multiples above the tune"),
		drop_s = param(0.03, 0.002, 0.3, "Pitch drop time constant"),
		decay_s = param(0.3, 0.02, 2.0, "Body decay time constant"),
		click = param(0.4, 0.0, 1.0, "Beater click"),
		drive = param(0.2, 0.0, 1.0, "Saturation"),
	}


func render(p: Dictionary, sr: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := AKDsp.samples(5.0 * p.decay_s, sr)
	var f := AKDsp.glide(n, sr, p.tune_hz * (1.0 + p.punch), p.tune_hz, p.drop_s)
	var x := AKDsp.mul(AKOsc.sine(f, sr), AKEnv.decay(n, sr, 0.0008, p.decay_s))
	if p.click > 0.0:
		var nc := mini(n, roundi(0.02 * sr))
		var c := AKFilter.svf(AKNoise.white(nc, rng), 3500.0, 0.8, sr, &"band")
		x = AKDsp.add(x, AKDsp.mul(c, AKEnv.decay(nc, sr, 0.0002, 0.003)), p.click * 0.8)
	if p.drive > 0.0:
		x = AKShape.drive(x, p.drive)
	return AKDsp.scale(x, 0.9)
