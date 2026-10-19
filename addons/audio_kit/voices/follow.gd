# SPDX-License-Identifier: Apache-2.0
@tool
extends AKVoice


func doc() -> String:
	return "An oscillator whose pitch and level follow breakpoint curves: sound that traces a motion (a scope wave, a rising bar, a moving needle)."


func schema() -> Dictionary:
	return {
		wave = param(&"sine", null, null, "sine, triangle, saw, square or pulse"),
		length_s = param(1.0, 0.02, 60.0, "Total length"),
		pitch = param([[0.0, 440.0], [1.0, 880.0]], null, null, "[[seconds, Hz], ...] breakpoints, linear between them"),
		level = param([[0.0, 1.0], [1.0, 1.0]], null, null, "[[seconds, 0..1], ...] breakpoints"),
		glide = param(0.0, 0.0, 1.0, "Smooths the pitch curve (0 = exact)"),
		fade_s = param(0.005, 0.0, 2.0, "Fade in and out"),
	}


func render(p: Dictionary, sr: int, _rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := AKDsp.samples(p.length_s, sr)
	var f := _curve(p.pitch, n, sr)
	if p.glide > 0.0:
		var k := exp(-1.0 / maxf(1.0, p.glide * 0.1 * sr))
		var v := f[0] if n > 0 else 0.0
		for i in n:
			v = f[i] + (v - f[i]) * k
			f[i] = v
	var x := AKOsc.wave(StringName(p.wave), f, sr)
	x = AKDsp.mul(x, _curve(p.level, n, sr))
	return AKEnv.fade(x, sr, p.fade_s, p.fade_s)


## Breakpoints [[t, v], ...] (seconds) sampled per sample, linear between
## points and held beyond the ends. Also accepts a flat [t, v, t, v, ...].
static func _curve(points: Variant, n: int, sr: int) -> PackedFloat32Array:
	var pts := []
	var raw: Array = points if points is Array else []
	if raw.size() > 0 and not (raw[0] is Array):
		for i in range(0, raw.size() - 1, 2):
			pts.append([float(raw[i]), float(raw[i + 1])])
	else:
		for e in raw:
			pts.append([float(e[0]), float(e[1])])
	var out := PackedFloat32Array()
	out.resize(n)
	if pts.is_empty():
		out.fill(0.0)
		return out
	pts.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var seg := 0
	for i in n:
		var t := float(i) / sr
		while seg < pts.size() - 1 and t > pts[seg + 1][0]:
			seg += 1
		if t <= pts[0][0]:
			out[i] = pts[0][1]
		elif seg >= pts.size() - 1:
			out[i] = pts[pts.size() - 1][1]
		else:
			var a: Array = pts[seg]
			var b: Array = pts[seg + 1]
			var t0: float = a[0]
			var t1: float = b[0]
			var u := (t - t0) / maxf(1e-9, t1 - t0)
			out[i] = lerpf(a[1], b[1], u)
	return out
