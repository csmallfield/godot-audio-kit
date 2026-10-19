# SPDX-License-Identifier: Apache-2.0
## Array helpers shared by the DSP blocks. Signals are `PackedFloat32Array`s,
## one value per sample; a parameter that can vary over time is either a
## float or an array of the same length (`arr()` turns either into an array).
class_name AKDsp
extends RefCounted

## Use the native core (the aknative GDExtension) when it is installed. The
## GDScript code below is the reference and the fallback; the native kernels
## follow the same algorithms (see tests/test_native.gd).
static var native_enabled := true
static var _native: Object = null
static var _checked := false


## The native kernels object, or null when not installed or disabled.
static func nat() -> Object:
	if not native_enabled:
		return null
	if not _checked:
		_checked = true
		if ClassDB.class_exists(&"AKNative"):
			_native = ClassDB.instantiate(&"AKNative")
	return _native


static func samples(seconds: float, sample_rate: int) -> int:
	return maxi(0, roundi(seconds * sample_rate))


## A float or an array as an array of `n` samples.
static func arr(v: Variant, n: int) -> PackedFloat32Array:
	if v is PackedFloat32Array:
		var a: PackedFloat32Array = v
		if a.size() == n:
			return a
		var out := a.duplicate()
		var last := a[a.size() - 1] if a.size() > 0 else 0.0
		var old := out.size()
		out.resize(n)
		for i in range(old, n):
			out[i] = last
		return out
	return filled(n, float(v))


static func filled(n: int, value: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(n)
	a.fill(value)
	return a


## Straight line from `a` to `b` over `n` samples.
static func line(n: int, a: float, b: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var d := (b - a) / maxf(1.0, n - 1)
	for i in n:
		out[i] = a + d * i
	return out


## Exponential glide from `a` towards `b` with time constant `time_s`.
static func glide(n: int, sample_rate: int, a: float, b: float, time_s: float) -> PackedFloat32Array:
	var nn := nat()
	if nn:
		return nn.glide(n, sample_rate, a, b, time_s)
	var out := PackedFloat32Array()
	out.resize(n)
	var k := exp(-1.0 / maxf(1e-6, time_s * sample_rate))
	var v := a - b
	for i in n:
		out[i] = b + v
		v *= k
	return out


## `a *= b`, element-wise. Use the returned array (the native path returns a new one).
static func mul(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var nn := nat()
	if nn:
		return nn.mul(a, b)
	var n := mini(a.size(), b.size())
	for i in n:
		a[i] *= b[i]
	return a


## `a += b * gain`, `b` starting at sample `at` of `a`. Use the returned array.
static func add(a: PackedFloat32Array, b: PackedFloat32Array, gain := 1.0, at := 0) -> PackedFloat32Array:
	var nn := nat()
	if nn:
		return nn.add(a, b, gain, at)
	var n := b.size()
	if at + n > a.size():
		var old := a.size()
		a.resize(at + n)
		for i in range(old, at + n):
			a[i] = 0.0
	for i in range(maxi(0, -at), n):
		a[at + i] += b[i] * gain
	return a


static func scale(a: PackedFloat32Array, gain: float) -> PackedFloat32Array:
	var nn := nat()
	if nn:
		return nn.scale(a, gain)
	for i in a.size():
		a[i] *= gain
	return a


static func db_to_gain(db: float) -> float:
	return pow(10.0, db / 20.0)


static func semitones_to_ratio(st: float) -> float:
	return pow(2.0, st / 12.0)
