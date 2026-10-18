# SPDX-License-Identifier: Apache-2.0
## Filters. `cutoff` is a float or a per-sample array (Hz), so sweeps are a
## line or glide from `AKDsp`.
class_name AKFilter
extends RefCounted


## One-pole low-pass, 6 dB/octave.
static func lowpass1(x: PackedFloat32Array, cutoff: Variant, sample_rate: int) -> PackedFloat32Array:
	var n := x.size()
	var c := AKDsp.arr(cutoff, n)
	var out := PackedFloat32Array()
	out.resize(n)
	var acc := 0.0
	var w := -TAU / sample_rate
	for i in n:
		var a := 1.0 - exp(w * c[i])
		acc += a * (x[i] - acc)
		out[i] = acc
	return out


## One-pole high-pass, 6 dB/octave.
static func highpass1(x: PackedFloat32Array, cutoff: Variant, sample_rate: int) -> PackedFloat32Array:
	var lp := lowpass1(x, cutoff, sample_rate)
	for i in lp.size():
		lp[i] = x[i] - lp[i]
	return lp


## State-variable filter (topology-preserving transform), 12 dB/octave.
## `mode`: &"low", &"high", &"band", &"notch". `q` 0.5 is gentle, 10 rings.
static func svf(x: PackedFloat32Array, cutoff: Variant, q: float, sample_rate: int, mode: StringName = &"low") -> PackedFloat32Array:
	var n := x.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var k := 1.0 / maxf(0.05, q)
	var nyq := 0.49 * sample_rate
	var varying := cutoff is PackedFloat32Array
	var c := AKDsp.arr(cutoff, n) if varying else PackedFloat32Array()
	var g := tan(PI * clampf(float(cutoff) if not varying else 1000.0, 10.0, nyq) / sample_rate)
	var a1 := 1.0 / (1.0 + g * (g + k))
	var a2 := g * a1
	var a3 := g * a2
	var ic1 := 0.0
	var ic2 := 0.0
	var m := 0
	match mode:
		&"high": m = 1
		&"band": m = 2
		&"notch": m = 3
	for i in n:
		if varying:
			g = tan(PI * clampf(c[i], 10.0, nyq) / sample_rate)
			a1 = 1.0 / (1.0 + g * (g + k))
			a2 = g * a1
			a3 = g * a2
		var v0 := x[i]
		var v3 := v0 - ic2
		var v1 := a1 * ic1 + a2 * v3
		var v2 := ic2 + a2 * ic1 + a3 * v3
		ic1 = 2.0 * v1 - ic1
		ic2 = 2.0 * v2 - ic2
		match m:
			0: out[i] = v2
			1: out[i] = v0 - k * v1 - v2
			2: out[i] = v1
			_: out[i] = v0 - k * v1
	return out
