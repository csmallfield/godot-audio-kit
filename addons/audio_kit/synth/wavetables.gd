# SPDX-License-Identifier: Apache-2.0
@tool
## Wavetables for the `table` oscillator: a few frames of a single cycle,
## swept by the oscillator's `position` (0 = first frame, 1 = last).
##
##   oscillators = [{shape = "table", table = "vowel", position = 0.3}]
##   oscillators = [{shape = "table", table = {frames = [{harmonics = [1.0, 0.5, 0.33]}, {samples = [...]}]}}]
##   table = {zones = [{key = 48, frames = [...]}, {key = 60, frames = [...]}], normalize = false}
##
## Zones (a table per key, like a sampler's key zones): a note plays the two
## zones around it, blended by key (`blend = false`: the nearest zone alone,
## as a sampler does: no blending of zones whose phases differ); below the
## first and above the last it plays that zone alone. `normalize = false` keeps each frame's level against
## the others (a recorded decay swept by position, zones louder or quieter).
##
## A frame is `harmonics` (amplitudes of harmonic 1, 2, 3 ..., with optional
## `phases` in cycles) or `samples` (one cycle, any length, read through an
## FFT). Every frame is stored band-limited at 19 half-octave levels, so a
## high note plays only the harmonics below Nyquist: no aliasing. Tables are
## built once per content and cached.
##
## Built in: basic (sine, triangle, saw, square), pwm (a pulse narrowing),
## vowel (a, e, i, o, u formants on a saw), organ (drawbar settings), bright
## (a saw tilting brighter), digital (seeded harmonic sets, metallic).
class_name AKWavetables
extends RefCounted

## Samples per cycle.
const SIZE := 1024
## Harmonics kept at each band-limit level: floor(2^(level/2)), 1 .. 512.
const LEVELS := 19
const BUILTIN := ["basic", "pwm", "vowel", "organ", "bright", "digital"]

static var _cache := {}


## The highest harmonic each level keeps.
static func level_limit(level: int) -> int:
	return floori(pow(2.0, level * 0.5))


## The table for a name, an AKWavetable-like dictionary {frames = [...]},
## or a res:// path to a JSON or text resource holding one. Returns
## {frames, size, levels, lv0, zones, keys, data: PackedFloat32Array, peak} (data
## is [zone][frame][level][sample], levels lv0 .. lv0 + levels - 1 stored;
## peak is the loudest frame's full-band cycle peak before any normalising),
## cached by content.
static func build(spec: Variant) -> Dictionary:
	if spec is String and String(spec).begins_with("res://") and FileAccess.file_exists(spec):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(spec))
		spec = d if d is Dictionary else {}
	var zones := _zones(spec)
	var norm_each := bool((spec as Dictionary).get("normalize", true)) if spec is Dictionary else true
	var blend := bool((spec as Dictionary).get("blend", true)) if spec is Dictionary else true
	var key := var_to_str([zones, norm_each]).sha256_text()
	if _cache.has(key):
		return _with_blend(_cache[key], blend)
	var nf := 1
	for z: Dictionary in zones:
		nf = maxi(nf, (z.frames as Array).size())
	# The spectra first: the band-limit levels kept depend on them.
	var spectra := []
	var keys := PackedFloat64Array()
	var top := 1
	for z: Dictionary in zones:
		keys.append(float(z.get("key", 60.0)))
		var frames: Array = z.frames
		for fi in nf:
			# A zone with fewer frames holds its last one.
			var f: Dictionary = frames[mini(fi, frames.size() - 1)] if not frames.is_empty() else {harmonics = [1.0]}
			var amps := PackedFloat64Array()
			var phs := PackedFloat64Array()
			_spectrum(f, amps, phs)
			for h in range(amps.size() - 1, top - 1, -1):
				if amps[h] != 0.0:
					top = h + 1
					break
			spectra.append([amps, phs])
	# Levels above the one holding every harmonic would be copies of it: not stored. A zoned table
	# plays each zone near its own key, so it keeps only four levels below (two octaves up).
	var lv_hi := 0
	while lv_hi + 1 < LEVELS and level_limit(lv_hi) < top:
		lv_hi += 1
	var lv_lo := maxi(0, lv_hi - 4) if zones.size() > 1 else 0
	var nl := lv_hi - lv_lo + 1
	var data := PackedFloat32Array()
	data.resize(spectra.size() * nl * SIZE)
	var at := 0
	var gpk := 0.0
	for sp: Array in spectra:
		var levels := _levels(sp[0], sp[1])
		var pk := 0.0
		for x in levels[LEVELS - 1]:
			pk = maxf(pk, absf(x))
		gpk = maxf(gpk, pk)
		# Normalise each frame so its full-band cycle peaks at 1 (frames morph evenly).
		var norm := 1.0 / pk if norm_each and pk > 0.0 else 1.0
		for lv in range(lv_lo, lv_hi + 1):
			var cyc: PackedFloat64Array = levels[lv]
			for i in SIZE:
				data[at + i] = cyc[i] * norm
			at += SIZE
	if not norm_each and gpk > 0.0:
		# normalize = false: frames keep their levels against each other (a recorded decay,
		# louder and quieter zones); the loudest frame peaks at 1.
		for i in data.size():
			data[i] /= gpk
	var t := {frames = nf, size = SIZE, levels = nl, lv0 = lv_lo, zones = zones.size(), keys = keys, data = data, peak = gpk}
	_cache[key] = t
	return _with_blend(t, blend)


## The cached table, or a copy marked to play only the nearest zone (the data is shared).
static func _with_blend(t: Dictionary, blend: bool) -> Dictionary:
	if blend:
		return t
	var c := t.duplicate()
	c.blend = false
	return c


## The zones of a spec, each {key, frames}: one zone unless the spec has `zones`.
static func _zones(spec: Variant) -> Array:
	if spec is Dictionary and (spec as Dictionary).has("zones"):
		var out := []
		for z: Dictionary in spec.zones:
			out.append({key = float(z.get("key", 60.0)), frames = z.get("frames", [])})
		out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.key < b.key)
		return out if not out.is_empty() else [{key = 60.0, frames = [{harmonics = [1.0]}]}]
	var fr := _frames(spec)
	return [{key = 60.0, frames = fr if not fr.is_empty() else [{harmonics = [1.0]}]}]


## The frame list for a spec (names expand to their built-in frames).
static func _frames(spec: Variant) -> Array:
	if spec is Dictionary:
		return (spec as Dictionary).get("frames", [])
	if spec is Array:
		return spec
	var s := String(spec)
	if s.begins_with("res://") and FileAccess.file_exists(s):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(s))
		return d.get("frames", []) if d is Dictionary else []
	return builtin(s)


## The frames of a built-in table.
static func builtin(name: String) -> Array:
	var out := []
	match name:
		"basic":
			out.append({harmonics = [1.0]})
			out.append({harmonics = _series(64, func(n: int) -> float: return (8.0 / (PI * PI)) / (n * n) * (1.0 if (n / 2) % 2 == 0 else -1.0) if n % 2 == 1 else 0.0)})
			out.append({harmonics = _series(256, func(n: int) -> float: return 2.0 / (PI * n))})
			out.append({harmonics = _series(256, func(n: int) -> float: return 4.0 / (PI * n) if n % 2 == 1 else 0.0)})
		"pwm":
			for i in 8:
				var w := lerpf(0.5, 0.05, i / 7.0)
				out.append({harmonics = _series(256, func(n: int) -> float: return 2.0 / (PI * n) * sin(PI * n * w))})
		"vowel":
			# F1, F2, F3 of a, e, i, o, u (Hz), as resonances on a saw at 130 Hz.
			var formants := [[730, 1090, 2440], [530, 1840, 2480], [270, 2290, 3010], [570, 840, 2410], [300, 870, 2240]]
			for fm in formants:
				var f: Array = fm
				out.append({harmonics = _series(160, func(n: int) -> float:
					var hz := n * 130.0
					var env := 0.0
					for k in 3:
						var bw := 80.0 + 40.0 * k
						env += [1.0, 0.6, 0.25][k] / (1.0 + pow((hz - float(f[k])) / bw, 2.0))
					return (1.0 / n) * (0.05 + env))})
		"organ":
			# Drawbars 8', 4', 2 2/3', 2', 1 3/5', 1 1/3', 1' = harmonics 1, 2, 3, 4, 5, 6, 8
			# (the 16' and 5 1/3' bars sit below the fundamental: a single cycle can't hold them).
			var settings := [[8, 0, 0, 0, 0, 0, 0], [8, 8, 0, 0, 0, 0, 0], [8, 8, 8, 0, 0, 0, 0], [8, 6, 4, 8, 0, 3, 0],
				[8, 8, 8, 8, 8, 8, 8], [6, 8, 0, 6, 0, 0, 8]]
			var harm := [1, 2, 3, 4, 5, 6, 8]
			for st in settings:
				var h := []
				h.resize(8)
				h.fill(0.0)
				for i in 7:
					h[int(harm[i]) - 1] = float(st[i]) / 8.0
				out.append({harmonics = h})
		"bright":
			for i in 6:
				var tilt := lerpf(-12.0, 0.0, i / 5.0)   # dB per octave below the saw's own -6
				out.append({harmonics = _series(256, func(n: int) -> float: return 1.0 / n * pow(10.0, tilt * log(n) / log(2.0) / 20.0))})
		"digital":
			var rng := RandomNumberGenerator.new()
			rng.seed = 2600
			for i in 8:
				var h := []
				for n in range(1, 49):
					h.append(rng.randf() / sqrt(n) if rng.randf() < 0.35 or n == 1 else 0.0)
				out.append({harmonics = h})
		_:
			push_error("AKWavetables: no table '%s' (built in: %s)" % [name, ", ".join(BUILTIN)])
			out.append({harmonics = [1.0]})
	return out


static func _series(n: int, f: Callable) -> Array:
	var a := []
	for i in range(1, n + 1):
		a.append(snappedf(f.call(i), 1e-9))
	return a


## Harmonic amplitudes and phases of a frame (index 0 = harmonic 1).
static func _spectrum(f: Dictionary, amps: PackedFloat64Array, phs: PackedFloat64Array) -> void:
	var half := SIZE / 2
	amps.resize(half)
	amps.fill(0.0)
	phs.resize(half)
	phs.fill(0.0)
	if f.has("harmonics"):
		var h: Array = f.harmonics
		var p: Array = f.get("phases", [])
		for i in mini(h.size(), half - 1):
			amps[i] = float(h[i])
			phs[i] = float(p[i]) if i < p.size() else 0.0
		return
	var smp: Array = f.get("samples", [])
	if smp.is_empty():
		return
	# Resample one cycle to SIZE points (linear), then FFT.
	var re := PackedFloat32Array()
	var im := PackedFloat32Array()
	re.resize(SIZE)
	im.resize(SIZE)
	for i in SIZE:
		var pos := float(i) / SIZE * smp.size()
		var i0 := int(pos)
		var fr := pos - i0
		re[i] = float(smp[i0 % smp.size()]) * (1.0 - fr) + float(smp[(i0 + 1) % smp.size()]) * fr
	AKSoundFeatures._fft(re, im)
	for k in range(1, half):
		var mag := sqrt(re[k] * re[k] + im[k] * im[k]) * 2.0 / SIZE
		amps[k - 1] = mag
		# A sine component sin(2 pi k t + 2 pi phase): phase from atan2.
		phs[k - 1] = (atan2(im[k], re[k]) + PI * 0.5) / TAU


## One cycle per level, each holding harmonics 1..level_limit(level) (sine
## phase): built up level by level, adding each harmonic once, as direct sums
## over a sine table, so the same everywhere.
static func _levels(amps: PackedFloat64Array, phs: PackedFloat64Array) -> Array:
	var sines := _sine_table()
	var cur := PackedFloat64Array()
	cur.resize(SIZE)
	cur.fill(0.0)
	var out := []
	var done := 0
	for lv in LEVELS:
		var limit := mini(level_limit(lv), amps.size())
		for h in range(done, limit):
			var a := amps[h]
			if a == 0.0:
				continue
			var n := h + 1
			var off := roundi(phs[h] * SIZE)
			for i in SIZE:
				cur[i] += a * sines[(i * n + off) % SIZE]
		done = maxi(done, limit)
		out.append(cur.duplicate())
	return out


static var _sines := PackedFloat64Array()


static func _sine_table() -> PackedFloat64Array:
	if _sines.is_empty():
		_sines.resize(SIZE)
		for i in SIZE:
			_sines[i] = sin(TAU * i / SIZE)
	return _sines
