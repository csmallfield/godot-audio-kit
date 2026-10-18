# SPDX-License-Identifier: Apache-2.0
## Waveshaping and degradation.
class_name AKShape
extends RefCounted


## Soft saturation: `amount` 0 is clean, 1 is heavy. Level-compensated so the
## peak stays roughly where it was.
static func drive(x: PackedFloat32Array, amount: float) -> PackedFloat32Array:
	var k := 1.0 + clampf(amount, 0.0, 1.0) * 19.0
	var norm := 1.0 / tanh(k)
	for i in x.size():
		x[i] = tanh(x[i] * k) * norm
	return x


## Bit depth reduction plus sample-and-hold over `hold` samples.
static func bitcrush(x: PackedFloat32Array, bits := 8.0, hold := 1) -> PackedFloat32Array:
	var steps := pow(2.0, clampf(bits, 1.0, 24.0) - 1.0)
	var h := maxi(1, hold)
	var v := 0.0
	for i in x.size():
		if i % h == 0:
			v = roundf(x[i] * steps) / steps
		x[i] = v
	return x
