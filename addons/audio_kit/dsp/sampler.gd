# SPDX-License-Identifier: Apache-2.0
@tool
## Plays a mono sample at a rate: the kernel under the `sample` voice.
## 4-point Hermite interpolation (as AKLive's loop voices), so a sample can be
## pitched without a resampling filter. The native core's `sample_play` is
## the same steps in the same order, in doubles, so both give the same bits.
class_name AKSampler
extends RefCounted


## `n` samples of `data` read from `start` at `rate` source samples per output
## sample. Reads stop at `end` (later samples are silent) unless `looping`,
## when the read position wraps from `loop_end` back to `loop_start` (both in
## source samples, inside start..end) for as long as `n` lasts. Neighbours
## outside start..end read as silence.
static func play(data: PackedFloat32Array, rate: float, n: int, start: int, end: int, loop_start := 0, loop_end := 0,
		looping := false) -> PackedFloat32Array:
	var nn := AKDsp.nat()
	if nn:
		return nn.sample_play(data, rate, n, start, end, loop_start, loop_end, looping)
	var out := PackedFloat32Array()
	out.resize(maxi(0, n))
	var size := data.size()
	start = clampi(start, 0, size)
	end = clampi(end, start, size)
	looping = looping and loop_end - loop_start >= 2 and loop_start >= start and loop_end <= end
	var span := loop_end - loop_start
	var pos := float(start)
	for j in out.size():
		if not looping and pos >= end:
			break
		var i0 := int(pos)
		var t := pos - i0
		var xm1 := _at(data, i0 - 1, start, end, looping, loop_start, loop_end, span)
		var x0 := _at(data, i0, start, end, looping, loop_start, loop_end, span)
		var x1 := _at(data, i0 + 1, start, end, looping, loop_start, loop_end, span)
		var x2 := _at(data, i0 + 2, start, end, looping, loop_start, loop_end, span)
		var c1 := 0.5 * (x1 - xm1)
		var c2 := xm1 - 2.5 * x0 + 2.0 * x1 - 0.5 * x2
		var c3 := 0.5 * (x2 - xm1) + 1.5 * (x0 - x1)
		out[j] = ((c3 * t + c2) * t + c1) * t + x0
		pos += rate
		if looping and pos >= loop_end:
			pos -= span
	return out


static func _at(d: PackedFloat32Array, i: int, start: int, end: int, looping: bool, ls: int, le: int, span: int) -> float:
	if looping and i >= le:
		i = ls + (i - ls) % span
	if i < start or i >= end:
		return 0.0
	return d[i]
