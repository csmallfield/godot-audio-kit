# SPDX-License-Identifier: Apache-2.0
@tool
## Level control on stereo buffers.
class_name AKDynamics
extends RefCounted


## Peak limiter with instant attack and exponential release, linked across
## channels, in place. Nothing leaves above `ceiling_db`.
static func limit(buf: AKBuffer, ceiling_db := -1.0, release_s := 0.08) -> AKBuffer:
	var ceiling := AKDsp.db_to_gain(ceiling_db)
	var k := exp(-1.0 / maxf(1e-4, release_s * buf.sample_rate))
	var nn := AKDsp.nat()
	if nn:
		var res: Array = nn.limit(buf.l, buf.r, ceiling, k)
		buf.l = res[0]
		buf.r = res[1]
		return buf
	var g := 1.0
	for i in buf.frames():
		var p := maxf(absf(buf.l[i]), absf(buf.r[i]))
		var need := ceiling / p if p > ceiling else 1.0
		if need < g:
			g = need
		else:
			g = need - (need - g) * k
		buf.l[i] *= g
		buf.r[i] *= g
	return buf


## Sidechain ducking, in place: turns `buf` down while `src` is loud. Full
## `depth_db` once the source's envelope reaches `full_at_db`, proportionally
## less below. The live mixer's buses use the same follower.
static func duck(buf: AKBuffer, src: AKBuffer, depth_db: float, full_at_db := -24.0, attack_s := 0.01, release_s := 0.3) -> AKBuffer:
	if depth_db <= 0.0:
		return buf
	var sr := buf.sample_rate
	var full := maxf(1e-6, AKDsp.db_to_gain(full_at_db))
	var nn := AKDsp.nat()
	if nn:
		var res: Array = nn.duck(buf.l, buf.r, src.l, src.r, sr, depth_db, full, attack_s, release_s)
		buf.l = res[0]
		buf.r = res[1]
		return buf
	var att := 1.0 - exp(-1.0 / maxf(1.0, attack_s * sr))
	var rel := 1.0 - exp(-1.0 / maxf(1.0, release_s * sr))
	var env := 0.0
	var ns := src.frames()
	for i in buf.frames():
		var x := maxf(absf(src.l[i]), absf(src.r[i])) if i < ns else 0.0
		env += (x - env) * (att if x > env else rel)
		var g := pow(10.0, -depth_db * minf(1.0, env / full) / 20.0)
		buf.l[i] *= g
		buf.r[i] *= g
	return buf


## Integrated loudness in LUFS (ITU-R BS.1770-4: K-weighting, 400 ms blocks,
## absolute and relative gates). Short sounds are measured ungated.
static func lufs(buf: AKBuffer) -> float:
	var sr := float(buf.sample_rate)
	var n := buf.frames()
	if n == 0:
		return -INF
	var nn := AKDsp.nat()
	if nn:
		return nn.lufs(buf.l, buf.r, buf.sample_rate)
	var kl := _k_weight(buf.l, sr)
	var kr := _k_weight(buf.r, sr)
	var block := int(0.4 * sr)
	var step := int(0.1 * sr)
	if n < block:
		var s := 0.0
		for i in n:
			s += kl[i] * kl[i] + kr[i] * kr[i]
		return -0.691 + 10.0 * log(maxf(s / n, 1e-12)) / log(10.0)
	# Running sums of squared samples make each block an O(1) lookup.
	var cum := PackedFloat64Array()
	cum.resize(n + 1)
	cum[0] = 0.0
	for i in n:
		cum[i + 1] = cum[i] + kl[i] * kl[i] + kr[i] * kr[i]
	var zs := PackedFloat64Array()
	var i0 := 0
	while i0 + block <= n:
		var z := (cum[i0 + block] - cum[i0]) / block
		if -0.691 + 10.0 * log(maxf(z, 1e-12)) / log(10.0) > -70.0:
			zs.append(z)
		i0 += step
	if zs.is_empty():
		return -INF
	var mean := 0.0
	for z in zs:
		mean += z
	mean /= zs.size()
	var rel := -0.691 + 10.0 * log(mean) / log(10.0) - 10.0
	var kept := 0.0
	var count := 0
	for z in zs:
		if -0.691 + 10.0 * log(z) / log(10.0) > rel:
			kept += z
			count += 1
	return -0.691 + 10.0 * log((kept / count) if count > 0 else mean) / log(10.0)


## Scale so the integrated loudness sits at `target_lufs`.
static func loudness(buf: AKBuffer, target_lufs := -16.0) -> AKBuffer:
	var now := lufs(buf)
	if is_finite(now):
		buf.apply_gain(AKDsp.db_to_gain(target_lufs - now))
	return buf


static func _k_weight(x: PackedFloat32Array, sr: float) -> PackedFloat32Array:
	# Stage 1: high shelf (+4 dB above ~1.7 kHz); stage 2: high-pass (~38 Hz).
	var f0 := 1681.974450955533
	var gain := 3.999843853973347
	var q := 0.7071752369554196
	var k := tan(PI * f0 / sr)
	var vh := pow(10.0, gain / 20.0)
	var vb := pow(vh, 0.4996667741545416)
	var a0 := 1.0 + k / q + k * k
	var y := _biquad(x, (vh + vb * k / q + k * k) / a0, 2.0 * (k * k - vh) / a0, (vh - vb * k / q + k * k) / a0,
		2.0 * (k * k - 1.0) / a0, (1.0 - k / q + k * k) / a0)
	f0 = 38.13547087602444
	q = 0.5003270373238773
	k = tan(PI * f0 / sr)
	a0 = 1.0 + k / q + k * k
	return _biquad(y, 1.0, -2.0, 1.0, 2.0 * (k * k - 1.0) / a0, (1.0 - k / q + k * k) / a0)


static func _biquad(x: PackedFloat32Array, b0: float, b1: float, b2: float, a1: float, a2: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(x.size())
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in x.size():
		var v := x[i]
		var y := b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = v
		y2 = y1
		y1 = y
		out[i] = y
	return out


## Scale so the peak sits at `peak_db`.
static func normalize(buf: AKBuffer, peak_db := -1.0) -> AKBuffer:
	var p := buf.peak()
	if p > 0.0:
		buf.apply_gain(AKDsp.db_to_gain(peak_db) / p)
	return buf
