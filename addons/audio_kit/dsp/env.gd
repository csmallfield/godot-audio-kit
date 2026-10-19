# SPDX-License-Identifier: Apache-2.0
## Amplitude envelopes, one gain per sample.
class_name AKEnv
extends RefCounted


## Linear attack over `attack_s`, then exponential decay with time constant
## `decay_s` (the level falls to 1/e after `decay_s`).
static func decay(n: int, sample_rate: int, attack_s: float, decay_s: float) -> PackedFloat32Array:
	var nn := AKDsp.nat()
	if nn:
		return nn.env_decay(n, sample_rate, attack_s, decay_s)
	var out := PackedFloat32Array()
	out.resize(n)
	var a := maxi(1, roundi(attack_s * sample_rate))
	var k := exp(-1.0 / maxf(1e-6, decay_s * sample_rate))
	var v := 1.0
	for i in n:
		if i < a:
			out[i] = float(i) / a
		else:
			out[i] = v
			v *= k
	return out


## Attack, decay to `sustain`, hold until `gate_s`, then release, all linear
## except the exponential release.
static func adsr(n: int, sample_rate: int, attack_s: float, decay_s: float, sustain: float, release_s: float, gate_s: float) -> PackedFloat32Array:
	var nn := AKDsp.nat()
	if nn:
		return nn.env_adsr(n, sample_rate, attack_s, decay_s, sustain, release_s, gate_s)
	var out := PackedFloat32Array()
	out.resize(n)
	var a := maxi(1, roundi(attack_s * sample_rate))
	var d := maxi(1, roundi(decay_s * sample_rate))
	var g := roundi(gate_s * sample_rate)
	var k := exp(-1.0 / maxf(1e-6, release_s * sample_rate))
	var level := 0.0
	for i in n:
		if i < g:
			if i < a:
				level = float(i) / a
			elif i < a + d:
				level = 1.0 - (1.0 - sustain) * float(i - a) / d
			else:
				level = sustain
		else:
			level *= k
		out[i] = level
	return out


## Raised-sine bump over `n` samples (0 → 1 → 0) bent by `power`; `peak`
## (0..1) moves the top earlier or later.
static func bump(n: int, power := 1.0, peak := 0.5) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var pk := clampf(peak, 0.01, 0.99)
	for i in n:
		var u := float(i) / maxf(1.0, n - 1)
		var w := u / pk * 0.5 if u < pk else 0.5 + (u - pk) / (1.0 - pk) * 0.5
		out[i] = pow(maxf(0.0, sin(PI * w)), power)
	return out


## Linear fades in and out, in place. Returns `x`.
static func fade(x: PackedFloat32Array, sample_rate: int, in_s: float, out_s: float) -> PackedFloat32Array:
	var n := x.size()
	var fi := mini(n, roundi(in_s * sample_rate))
	var fo := mini(n, roundi(out_s * sample_rate))
	for i in fi:
		x[i] *= float(i) / fi
	for i in fo:
		x[n - 1 - i] *= float(i) / fo
	return x
