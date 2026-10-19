# SPDX-License-Identifier: Apache-2.0
## Oscillators driven by a per-sample frequency array (Hz). Saw and square are
## band-limited with PolyBLEP; triangle is naive (its harmonics fall fast
## enough that aliasing stays low).
class_name AKOsc
extends RefCounted


static func sine(freq: PackedFloat32Array, sample_rate: int, phase0 := 0.0) -> PackedFloat32Array:
	var nn := AKDsp.nat()
	if nn:
		return nn.sine(freq, sample_rate, phase0)
	var n := freq.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := phase0
	var inv := 1.0 / sample_rate
	for i in n:
		out[i] = sin(TAU * ph)
		ph += freq[i] * inv
		ph -= floorf(ph)
	return out


## Constant-pitch sine by recursion (y = 2cos(w)·y1 - y2): no sin() per
## sample, several times faster than `sine()` for fixed pitches.
static func sine_const(n: int, freq: float, sample_rate: int, phase0 := 0.0) -> PackedFloat32Array:
	var nn := AKDsp.nat()
	if nn:
		return nn.sine_const(n, freq, sample_rate, phase0)
	var out := PackedFloat32Array()
	out.resize(n)
	var w := TAU * freq / sample_rate
	var c := 2.0 * cos(w)
	var y2 := sin(TAU * phase0 - w)
	var y1 := sin(TAU * phase0)
	for i in n:
		out[i] = y1
		var y := c * y1 - y2
		y2 = y1
		y1 = y
	return out


static func saw(freq: PackedFloat32Array, sample_rate: int, phase0 := 0.0) -> PackedFloat32Array:
	var nn := AKDsp.nat()
	if nn:
		return nn.saw(freq, sample_rate, phase0)
	var n := freq.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := phase0
	var inv := 1.0 / sample_rate
	for i in n:
		var dt := freq[i] * inv
		out[i] = 2.0 * ph - 1.0 - _blep(ph, dt)
		ph += dt
		ph -= floorf(ph)
	return out


static func square(freq: PackedFloat32Array, sample_rate: int, width := 0.5, phase0 := 0.0) -> PackedFloat32Array:
	var nn := AKDsp.nat()
	if nn:
		return nn.square(freq, sample_rate, width, phase0)
	var n := freq.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := phase0
	var inv := 1.0 / sample_rate
	var w := clampf(width, 0.01, 0.99)
	for i in n:
		var dt := freq[i] * inv
		var v := 1.0 if ph < w else -1.0
		v += _blep(ph, dt)
		var p2 := ph - w
		p2 -= floorf(p2)
		v -= _blep(p2, dt)
		out[i] = v
		ph += dt
		ph -= floorf(ph)
	return out


static func triangle(freq: PackedFloat32Array, sample_rate: int, phase0 := 0.0) -> PackedFloat32Array:
	var nn := AKDsp.nat()
	if nn:
		return nn.triangle(freq, sample_rate, phase0)
	var n := freq.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := phase0
	var inv := 1.0 / sample_rate
	for i in n:
		out[i] = 1.0 - 4.0 * absf(ph - 0.5)
		ph += freq[i] * inv
		ph -= floorf(ph)
	return out


## By name: &"sine", &"saw", &"square", &"pulse" (uses `width`), &"triangle".
static func wave(shape: StringName, freq: PackedFloat32Array, sample_rate: int, width := 0.5) -> PackedFloat32Array:
	match shape:
		&"saw": return saw(freq, sample_rate)
		&"square": return square(freq, sample_rate, 0.5)
		&"pulse": return square(freq, sample_rate, width)
		&"triangle": return triangle(freq, sample_rate)
	return sine(freq, sample_rate)


static func _blep(t: float, dt: float) -> float:
	if dt <= 0.0:
		return 0.0
	if t < dt:
		var x := t / dt
		return x + x - x * x - 1.0
	if t > 1.0 - dt:
		var x := (t - 1.0) / dt
		return x * x + x + x + 1.0
	return 0.0
