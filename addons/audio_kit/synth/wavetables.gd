# SPDX-License-Identifier: Apache-2.0
@tool
## Wavetables for the `table` oscillator: a few frames of a single cycle,
## swept by the oscillator's `position` (0 = first frame, 1 = last).
##
##   oscillators = [{shape = "table", table = "vowel", position = 0.3}]
##   oscillators = [{shape = "table", table = {frames = [{harmonics = [1.0, 0.5, 0.33]}, {samples = [...]}]}}]
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
## {frames, size, levels, data: PackedFloat32Array} (data is
## [frame][level][sample]), cached by content.
static func build(spec: Variant) -> Dictionary:
	var frames := _frames(spec)
	var key := var_to_str(frames).sha256_text()
	if _cache.has(key):
		return _cache[key]
	var data := PackedFloat32Array()
	data.resize(frames.size() * LEVELS * SIZE)
	var at := 0
	for f: Dictionary in frames:
		var amps := PackedFloat64Array()
		var phs := PackedFloat64Array()
		_spectrum(f, amps, phs)
		# Normalise each frame so its full-band peak is 1 (frames morph evenly).
		var levels := _levels(amps, phs)
		# Normalise each frame so its full-band cycle peaks at 1 (frames morph evenly).
		var pk := 0.0
		for x in levels[LEVELS - 1]:
			pk = maxf(pk, absf(x))
		var norm := 1.0 / pk if pk > 0.0 else 1.0
		for lv in LEVELS:
			var cyc: PackedFloat64Array = levels[lv]
			for i in SIZE:
				data[at + i] = cyc[i] * norm
			at += SIZE
	var t := {frames = frames.size(), size = SIZE, levels = LEVELS, data = data}
	_cache[key] = t
	return t


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
