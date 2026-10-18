# SPDX-License-Identifier: Apache-2.0
## Delay-line instruments and effects.
class_name AKDelay
extends RefCounted


## Karplus-Strong plucked string. `decay_s` is the time to fall to 1/e;
## `brightness` 0 is dark and short-lived, 1 bright and long. The delay is a
## whole number of samples, so very high notes tune slightly flat.
static func karplus(n: int, sample_rate: int, freq: float, decay_s: float, brightness: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var period := maxi(2, roundi(sample_rate / maxf(20.0, freq)))
	var buf := PackedFloat32Array()
	buf.resize(period)
	for i in period:
		buf[i] = rng.randf_range(-1.0, 1.0)
	var out := PackedFloat32Array()
	out.resize(n)
	var g := exp(-float(period) / maxf(1e-4, decay_s * sample_rate))
	var b := clampf(brightness, 0.0, 1.0)
	var idx := 0
	for i in n:
		var cur := buf[idx]
		var nxt := buf[(idx + 1) % period]
		out[i] = cur
		buf[idx] = lerpf(0.5 * (cur + nxt), cur, b * 0.5) * g
		idx = (idx + 1) % period
	return out


## Feedback echo on a stereo buffer, in place; the buffer grows by the tail.
static func echo(buf: AKBuffer, time_s: float, feedback: float, mix: float, tail_s := 1.0) -> AKBuffer:
	var d := maxi(1, roundi(time_s * buf.sample_rate))
	var n0 := buf.frames()
	buf.resize(n0 + roundi(tail_s * buf.sample_rate))
	var n := buf.frames()
	var fb := clampf(feedback, 0.0, 0.95)
	var wl := buf.l.duplicate()
	var wr := buf.r.duplicate()
	for i in range(d, n):
		wl[i] += wl[i - d] * fb
		wr[i] += wr[i - d] * fb
	for i in n:
		var el := wl[i - d] if i >= d else 0.0
		var er := wr[i - d] if i >= d else 0.0
		buf.l[i] += el * mix
		buf.r[i] += er * mix
	return buf
