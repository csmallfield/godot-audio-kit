# SPDX-License-Identifier: Apache-2.0
## Freeverb-style stereo reverb (Jezar's public-domain design): eight damped
## combs and four all-passes per channel, tunings scaled to the sample rate.
## Each filter runs as its own pass over the whole buffer, which keeps the
## GDScript inner loops short.
class_name AKReverb
extends RefCounted

const COMBS := [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617]
const ALLPASSES := [556, 441, 341, 225]
const SPREAD := 23


## In place on `buf`, which grows by `tail_s` (default from `room`).
## `room` 0..1 sets size and decay, `damp` 0..1 dulls the tail, `mix` is the
## wet level (dry stays at 1), `width` 0 mono to 1 wide.
static func process(buf: AKBuffer, room := 0.5, damp := 0.5, mix := 0.2, width := 1.0, tail_s := -1.0) -> AKBuffer:
	if mix <= 0.0:
		return buf
	var sr := buf.sample_rate
	var tail := tail_s if tail_s >= 0.0 else 0.3 + 2.2 * clampf(room, 0.0, 1.0)
	var n0 := buf.frames()
	buf.resize(n0 + roundi(tail * sr))
	var n := buf.frames()
	var input := PackedFloat32Array()
	input.resize(n)
	for i in n:
		input[i] = (buf.l[i] + buf.r[i]) * 0.015
	var fb := clampf(room, 0.0, 1.0) * 0.28 + 0.7
	var d := clampf(damp, 0.0, 1.0) * 0.4
	var scale := float(sr) / 44100.0
	var wl := _channel(input, fb, d, scale, 0)
	var wr := _channel(input, fb, d, scale, SPREAD)
	var w1 := mix * (width * 0.5 + 0.5)
	var w2 := mix * ((1.0 - width) * 0.5)
	for i in n:
		var a := wl[i]
		var b := wr[i]
		buf.l[i] += a * w1 + b * w2
		buf.r[i] += b * w1 + a * w2
	return buf


static func _channel(input: PackedFloat32Array, fb: float, damp: float, scale: float, spread: int) -> PackedFloat32Array:
	var n := input.size()
	var acc := PackedFloat32Array()
	acc.resize(n)
	acc.fill(0.0)
	for c in COMBS:
		var len_c := maxi(1, roundi((int(c) + spread) * scale))
		var line := PackedFloat32Array()
		line.resize(len_c)
		line.fill(0.0)
		var store := 0.0
		var idx := 0
		for i in n:
			var y := line[idx]
			store = y * (1.0 - damp) + store * damp
			line[idx] = input[i] + store * fb
			acc[i] += y
			idx += 1
			if idx == len_c:
				idx = 0
	for a in ALLPASSES:
		var len_a := maxi(1, roundi((int(a) + spread) * scale))
		var line := PackedFloat32Array()
		line.resize(len_a)
		line.fill(0.0)
		var idx := 0
		for i in n:
			var bufout := line[idx]
			var x := acc[i]
			acc[i] = bufout - x
			line[idx] = x + bufout * 0.5
			idx += 1
			if idx == len_a:
				idx = 0
	return acc
