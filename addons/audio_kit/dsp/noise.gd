# SPDX-License-Identifier: Apache-2.0
@tool
## Seeded noise. The same generator state always gives the same samples.
class_name AKNoise
extends RefCounted


static func white(n: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = rng.randf_range(-1.0, 1.0)
	return out


## Pink (-3 dB/octave), Paul Kellet's economy filter.
static func pink(n: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var b0 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	for i in n:
		var w := rng.randf_range(-1.0, 1.0)
		b0 = 0.99765 * b0 + w * 0.0990460
		b1 = 0.96300 * b1 + w * 0.2965164
		b2 = 0.57000 * b2 + w * 1.0526913
		out[i] = (b0 + b1 + b2 + w * 0.1848) * 0.25
	return out


## Brown (-6 dB/octave): leaky integrated white noise.
static func brown(n: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var acc := 0.0
	for i in n:
		acc = acc * 0.998 + rng.randf_range(-1.0, 1.0) * 0.06
		out[i] = acc
	return out


## By name: &"white", &"pink", &"brown".
static func color(name: StringName, n: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	match name:
		&"pink": return pink(n, rng)
		&"brown": return brown(n, rng)
	return white(n, rng)
