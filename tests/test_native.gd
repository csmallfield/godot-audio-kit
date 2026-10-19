# SPDX-License-Identifier: Apache-2.0
# The native core against the GDScript reference: every kernel and every voice
# rendered both ways must agree closely. Passes trivially without the extension.
extends RefCounted

const SR := 48000
## Largest allowed difference between the paths, relative to the signal peak.
const TOL := 1e-4


func _has_native() -> bool:
	AKDsp.native_enabled = true
	return AKDsp.nat() != null


func _both(f: Callable) -> Array:
	AKDsp.native_enabled = true
	var a: Variant = f.call()
	AKDsp.native_enabled = false
	var b: Variant = f.call()
	AKDsp.native_enabled = true
	return [a, b]


static func _diff(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	if a.size() != b.size():
		return INF
	var d := 0.0
	var p := 1e-9
	for i in a.size():
		d = maxf(d, absf(a[i] - b[i]))
		p = maxf(p, absf(b[i]))
	return d / p


func _check(name: String, f: Callable) -> String:
	var r := _both(f)
	var a: Variant = r[0]
	var b: Variant = r[1]
	if a is AKBuffer:
		var d := maxf(_diff(a.l, b.l), _diff(a.r, b.r))
		return "" if d <= TOL else "%s differs by %s (sizes %d / %d)" % [name, String.num_scientific(d), a.frames(), b.frames()]
	if a is PackedFloat32Array:
		var d := _diff(a, b)
		return "" if d <= TOL else "%s differs by %s (sizes %d / %d)" % [name, String.num_scientific(d), a.size(), b.size()]
	return "" if absf(float(a) - float(b)) < 1e-6 else "%s: %s vs %s" % [name, a, b]


func test_kernels_match() -> String:
	if not _has_native():
		print("        (native core not built: skipped)")
		return ""
	var sweep := AKDsp.line(SR, 100.0, 4000.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var noise := AKNoise.white(SR, rng)
	var cases := {
		glide = func(): return AKDsp.glide(SR, SR, 800.0, 50.0, 0.05),
		mul = func(): return AKDsp.mul(noise.duplicate(), sweep),
		add = func(): return AKDsp.add(noise.duplicate(), sweep, 0.3, 100),
		sine = func(): return AKOsc.sine(sweep, SR, 0.1),
		sine_const = func(): return AKOsc.sine_const(SR, 440.0, SR),
		saw = func(): return AKOsc.saw(sweep, SR),
		square = func(): return AKOsc.square(sweep, SR, 0.3),
		triangle = func(): return AKOsc.triangle(sweep, SR),
		decay = func(): return AKEnv.decay(SR, SR, 0.01, 0.2),
		adsr = func(): return AKEnv.adsr(SR, SR, 0.01, 0.1, 0.5, 0.2, 0.6),
		lowpass1 = func(): return AKFilter.lowpass1(noise, 1200.0, SR),
		lowpass1_sweep = func(): return AKFilter.lowpass1(noise, sweep, SR),
		svf_band = func(): return AKFilter.svf(noise, 2000.0, 3.0, SR, &"band"),
		svf_sweep = func(): return AKFilter.svf(noise, sweep, 0.9, SR, &"low"),
		svf_high = func(): return AKFilter.svf(noise, 500.0, 0.7, SR, &"high"),
	}
	for k in cases:
		var e := _check(k, cases[k])
		if e != "":
			return e
	return ""


func test_buffer_kernels_match() -> String:
	if not _has_native():
		return ""
	var src := AK.render(AKRecipe.make(&"pluck"))
	var e := _check("reverb", func(): return AKReverb.wet(src, 0.6, 0.4, 1.0, 1.0, &"full"))
	if e != "":
		return e
	e = _check("reverb_small", func(): return AKReverb.wet(src, 0.6, 0.4, 0.8, 0.5, &"small"))
	if e != "":
		return e
	e = _check("limit", func(): var b := src.duplicate_buffer(); b.apply_gain(4.0); return AKDynamics.limit(b, -1.5))
	if e != "":
		return e
	var side := AK.render(AKRecipe.make(&"kick"))
	e = _check("duck", func(): return AKDynamics.duck(src.duplicate_buffer(), side, 9.0, -20.0, 0.005, 0.2))
	if e != "":
		return e
	var r := _both(func(): return AKDynamics.lufs(src))
	return "" if absf(float(r[0]) - float(r[1])) < 0.01 else "lufs %.3f vs %.3f" % [r[0], r[1]]


func test_every_voice_matches() -> String:
	if not _has_native():
		return ""
	for v in AK.voice_names():
		var rec := AKRecipe.make(StringName(v))
		rec.seed = 9
		var e := _check("voice " + v, func(): return AK.render(rec))
		if e != "":
			return e
	return ""


func test_cue_sheet_matches() -> String:
	if not _has_native():
		return ""
	var sheet := AK.load_cue_sheet("res://demo/cues/race_ident.json")
	var map: AKCueMap = load("res://demo/recipes/race_ident_map.tres")
	return _check("race ident", func(): return AK.render_cues(sheet.cues, map, 30.0, 6.0).mix)


func test_native_is_faster() -> String:
	if not _has_native():
		return ""
	var sheet := AK.load_cue_sheet("res://demo/cues/race_ident.json")
	var map: AKCueMap = load("res://demo/recipes/race_ident_map.tres")
	var t := Time.get_ticks_usec()
	AK.render_cues(sheet.cues, map, 30.0, 6.0)
	var fast := Time.get_ticks_usec() - t
	AKDsp.native_enabled = false
	t = Time.get_ticks_usec()
	AK.render_cues(sheet.cues, map, 30.0, 6.0)
	var slow := Time.get_ticks_usec() - t
	AKDsp.native_enabled = true
	print("        race ident: native %.0f ms, GDScript %.0f ms (%.1fx)" % [fast / 1000.0, slow / 1000.0, float(slow) / fast])
	return "" if fast * 2 < slow else "native only %.1fx faster" % (float(slow) / fast)
