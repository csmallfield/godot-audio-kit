# SPDX-License-Identifier: Apache-2.0
@tool
## The Sound Lab's game-sound generator: a category and a seed give an
## ordinary, editable recipe built from the kit's own voices and effects.
##
##   var r := AKSfxGen.generate(&"jump", 42)     # the same recipe every time
##   var m := AKSfxGen.mutate(r, 7)              # a near neighbour of it
##   var w := AKSfxGen.generate(&"random", 3)    # anything goes
##
## Each category is a small hand-written design (which voices, which
## parameter ranges, which effects) in the spirit of the classic retro sound
## generators, reimplemented from the idea rather than from their code. A
## seed picks values inside the ranges, so the same category and seed always
## give the same recipe, and the recipe always renders the same samples.
## Every recipe ends in a DC block and a peak normalise to -1 dBFS, and
## carries a little `vary` (pitch) so it can differ per play.
class_name AKSfxGen
extends RefCounted

## The categories, in the order the lab shows them.
const CATEGORIES: Array[StringName] = [&"pickup", &"jump", &"laser", &"hit", &"explosion", &"powerup",
	&"ui_click", &"ui_confirm", &"ui_cancel", &"blip"]
## What each category sounds like, for tooltips and docs.
const ABOUT := {
	&"pickup": "Coin or pickup: two or three quick rising notes.",
	&"jump": "Jump: a short tone that glides up.",
	&"laser": "Laser or shot: a bright tone diving down fast.",
	&"hit": "Hit or hurt: a noisy thump with a falling, driven tone.",
	&"explosion": "Explosion: a low noise burst with a thump and crackle.",
	&"powerup": "Power-up: a longer rising sweep or arpeggio.",
	&"ui_click": "UI click: a tiny tuned tick.",
	&"ui_confirm": "UI confirm: two soft notes going up.",
	&"ui_cancel": "UI cancel: two soft notes (or a slide) going down.",
	&"blip": "Blip: one short beep (text, menus, counters).",
	&"random": "Random: any voices, any settings, a few effects. Wild.",
}
## Bumped when a generator changes, so old category + seed pairs are known
## to give different recipes now. Stored on each recipe's metadata.
const VERSION := 1


## A recipe for `category` from `seed`. Unknown categories give null.
static func generate(category: StringName, seed: int) -> AKRecipe:
	var g := _Gen.new(category, seed)
	var r := AKRecipe.new()
	r.seed = seed
	match category:
		&"pickup": g.pickup(r)
		&"jump": g.jump(r)
		&"laser": g.laser(r)
		&"hit": g.hit(r)
		&"explosion": g.explosion(r)
		&"powerup": g.powerup(r)
		&"ui_click": g.ui_click(r)
		&"ui_confirm": g.ui_note_pair(r, true)
		&"ui_cancel": g.ui_note_pair(r, false)
		&"blip": g.blip(r)
		&"random": g.random(r)
		_:
			push_error("AKSfxGen: no category '%s'" % category)
			return null
	r.fx.append({type = "dcblock"})
	r.fx.append({type = "normalize", peak_db = -1.0})
	r.resource_name = "%s %d" % [category, seed]
	r.set_meta(&"sfx_category", String(category))
	r.set_meta(&"sfx_seed", seed)
	r.set_meta(&"sfx_version", VERSION)
	return r


## A copy of `recipe` with its numbers nudged: frequencies by up to `amount`
## octaves, times and levels by up to `amount` × 150%, all kept inside each
## voice's ranges. Text choices (wave, mode) and the final normalise stay.
## Deterministic in `seed`.
static func mutate(recipe: AKRecipe, seed: int, amount := 0.15) -> AKRecipe:
	var r: AKRecipe = recipe.duplicate(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = ("mutate:%d" % seed).hash()
	if r.voice != &"":
		r.params = _nudge(r.params, AK.voice(r.voice), rng, amount)
	var layers: Array[Dictionary] = []
	for l in r.layers:
		var d: Dictionary = l.duplicate(true)
		d["params"] = _nudge(d.get("params", {}), AK.voice(StringName(d.get("voice", &""))), rng, amount)
		if d.has("offset_s"):
			d["offset_s"] = maxf(0.0, _snap(float(d.offset_s) * (1.0 + rng.randf_range(-amount, amount))))
		layers.append(d)
	r.layers = layers
	var fx: Array[Dictionary] = []
	for e in r.fx:
		var t := String(e.get("type", ""))
		fx.append(e.duplicate(true) if t in ["normalize", "dcblock", "limit", "loudness"] else _nudge(e, null, rng, amount))
	r.fx = fx
	var n := int(recipe.get_meta(&"sfx_mutations", 0)) + 1
	r.set_meta(&"sfx_mutations", n)
	r.resource_name = "%s m%d" % [recipe.resource_name, n]
	return r


## A file-friendly name for a generated recipe: "jump_42", "jump_42_m2".
static func name_for(recipe: AKRecipe) -> String:
	var base := "%s_%d" % [recipe.get_meta(&"sfx_category", "sound"), int(recipe.get_meta(&"sfx_seed", recipe.seed))]
	var m := int(recipe.get_meta(&"sfx_mutations", 0))
	return base + ("_m%d" % m if m > 0 else "")


# ------------------------------------------------------------------ inside

static func _nudge(p: Dictionary, v: AKVoice, rng: RandomNumberGenerator, amount: float) -> Dictionary:
	var schema := v.schema() if v else {}
	var out := {}
	var keys := p.keys()
	keys.sort()   # the same draws in the same order, whatever the dictionary's history
	for k in keys:
		var x: Variant = p[k]
		var ks := String(k)
		if not (x is float or x is int) or x is bool or ks == "type":
			out[k] = x
			continue
		var f := float(x)
		if ks.ends_with("_hz"):
			f *= pow(2.0, rng.randf_range(-amount, amount))
		elif ks.ends_with("_db"):
			f += rng.randf_range(-amount, amount) * 6.0
		else:
			f *= 1.0 + rng.randf_range(-amount, amount) * 1.5
		var s: Dictionary = schema.get(ks, schema.get(StringName(ks), {}))
		if s.get("min") != null:
			f = maxf(f, float(s.min))
		if s.get("max") != null:
			f = minf(f, float(s.max))
		out[k] = roundi(f) if x is int else _snap(f)
	return out


## Keep a few significant digits, so recipes read well as text.
static func _snap(x: float) -> float:
	if x == 0.0:
		return 0.0
	var mag := pow(10.0, floorf(log(absf(x)) / log(10.0)) - 3.0)
	return snappedf(x, mag)


## The per-category designs. One instance per generate() call.
class _Gen:
	var rng := RandomNumberGenerator.new()

	func _init(category: StringName, seed: int) -> void:
		rng.seed = ("sfx:%s:%d" % [category, seed]).hash()

	func u(lo: float, hi: float) -> float:
		return AKSfxGen._snap(rng.randf_range(lo, hi))

	## Log-uniform: right for frequencies and times.
	func lg(lo: float, hi: float) -> float:
		return AKSfxGen._snap(exp(rng.randf_range(log(lo), log(hi))))

	func pick(items: Array) -> Variant:
		return items[rng.randi_range(0, items.size() - 1)]

	func chance(p: float) -> bool:
		return rng.randf() < p

	func note(wave: String, hz: float, gate_s: float, sustain: float, release_s: float, extra := {}) -> Dictionary:
		var p := {wave = wave, freq_hz = AKSfxGen._snap(hz), attack_s = 0.001, decay_s = u(0.03, 0.08),
			sustain = sustain, gate_s = gate_s, release_s = release_s}
		if wave == "pulse":
			p["width"] = u(0.15, 0.4)
		p.merge(extra, true)
		return p

	func pickup(r: AKRecipe) -> void:
		# Bright and quick (square-ish waves), where UI confirm is soft.
		var wave: String = pick(["square", "pulse", "square", "triangle"])
		var base := lg(700.0, 1600.0)
		var ratio: float = pick([1.25, 1.3348, 1.4983, 2.0])
		var step := u(0.035, 0.075)
		r.voice = &"tone"
		r.params = note(wave, base, step, u(0.4, 0.7), u(0.01, 0.025))
		r.layers = [{voice = &"tone", offset_s = step,
			params = note(wave, base * ratio, u(0.06, 0.14), u(0.4, 0.7), u(0.04, 0.1))}]
		if chance(0.3):
			r.layers[0].params.gate_s = step
			r.layers[0].params.release_s = 0.015
			r.layers.append({voice = &"tone", offset_s = AKSfxGen._snap(step * 2.0),
				params = note(wave, base * ratio * ratio, u(0.06, 0.12), 0.5, u(0.04, 0.1))})
		r.fx = [{type = "highpass1", cutoff_hz = 150.0}]
		if chance(0.25):
			r.fx.append({type = "echo", time_s = u(0.06, 0.1), feedback = u(0.15, 0.3), mix = u(0.15, 0.25), tail_s = 0.3})
		r.vary = {pitch_scale = 0.03}

	func jump(r: AKRecipe) -> void:
		var wave: String = pick(["square", "pulse", "triangle", "square"])
		var f0 := lg(150.0, 420.0)
		r.voice = &"tone"
		r.params = note(wave, f0, u(0.08, 0.2), u(0.5, 0.9), u(0.02, 0.06),
			{end_hz = AKSfxGen._snap(f0 * u(1.7, 3.2)), glide_s = u(0.04, 0.1), decay_s = 0.1})
		r.fx = []
		if chance(0.5):
			r.fx.append({type = "lowpass", cutoff_hz = lg(2500.0, 8000.0)})
		r.vary = {pitch_scale = 0.05}

	func laser(r: AKRecipe) -> void:
		var wave: String = pick(["saw", "square", "pulse", "saw"])
		var f0 := lg(900.0, 2600.0)
		var extra := {end_hz = AKSfxGen._snap(f0 * u(0.08, 0.3)), glide_s = u(0.03, 0.1), decay_s = 0.1}
		if chance(0.35):
			extra["vibrato_hz"] = u(12.0, 20.0)
			extra["vibrato_semitones"] = u(0.5, 2.0)
		r.voice = &"tone"
		r.params = note(wave, f0, u(0.06, 0.16), u(0.6, 1.0), u(0.02, 0.06), extra)
		if chance(0.4):
			var p2: Dictionary = r.params.duplicate()
			p2.freq_hz = AKSfxGen._snap(f0 * u(1.008, 1.03))
			p2.end_hz = AKSfxGen._snap(float(r.params.end_hz) * u(1.008, 1.03))
			r.layers = [{voice = &"tone", params = p2, gain_db = -6.0}]
		r.fx = []
		if chance(0.3):
			r.fx.append({type = "bitcrush", bits = u(6.0, 10.0), hold = 1})
		if chance(0.4):
			r.fx.append({type = "echo", time_s = u(0.05, 0.12), feedback = u(0.2, 0.4), mix = u(0.15, 0.3), tail_s = 0.4})
		r.vary = {pitch_scale = 0.05}

	func hit(r: AKRecipe) -> void:
		r.voice = &"click"
		r.params = {mode = "low", freq_hz = lg(1500.0, 5000.0), q = u(0.6, 1.5), decay_s = u(0.015, 0.045),
			body_hz = lg(80.0, 200.0), body = u(0.3, 0.7)}
		var f0 := lg(250.0, 600.0)
		r.layers = [{voice = &"tone", gain_db = -3.0, params = note(pick(["square", "saw"]), f0, u(0.04, 0.09), 0.7, 0.03,
			{end_hz = AKSfxGen._snap(f0 * u(0.2, 0.4)), glide_s = u(0.02, 0.06)})}]
		r.fx = [{type = "normalize", peak_db = -3.0}, {type = "drive", amount = u(0.2, 0.6)}]
		if chance(0.5):
			r.fx.append({type = "bitcrush", bits = u(5.0, 9.0), hold = rng.randi_range(1, 3)})
		r.fx.append({type = "lowpass", cutoff_hz = lg(2500.0, 7000.0)})
		r.vary = {pitch_scale = 0.06}

	func explosion(r: AKRecipe) -> void:
		# A short bright burst over a thump, then a long dark rumble and
		# (often) crackle: loud at once, dying slowly.
		var burst := u(0.35, 0.7)
		var length := u(1.0, 1.6)
		r.voice = &"whoosh"
		r.params = {length_s = burst, low_hz = lg(60.0, 140.0), high_hz = lg(900.0, 3000.0), peak = u(0.01, 0.03),
			shape = 4.0, q = u(0.5, 1.0), mode = "low", noise = pick(["pink", "white"]), slope_db = 24.0}
		r.layers = [{voice = &"boing", gain_db = 2.0, params = {start_hz = lg(90.0, 160.0), end_hz = lg(30.0, 45.0),
				drop_s = u(0.1, 0.2), decay_s = u(0.15, 0.35), sub = u(0.4, 0.9), click = u(0.3, 0.7), click_hz = lg(2000.0, 4000.0)}},
			{voice = &"whoosh", gain_db = u(-11.0, -7.0), params = {length_s = length, low_hz = lg(30.0, 50.0), high_hz = lg(200.0, 500.0),
				peak = 0.02, shape = u(1.5, 2.5), q = 0.7, mode = "low", noise = "brown", slope_db = 24.0}}]
		if chance(0.6):
			r.layers.append({voice = &"static", gain_db = -10.0, params = {length_s = AKSfxGen._snap(length * 0.6), hiss = 0.05,
				color_hz = 1500.0, crackles_per_s = lg(30.0, 120.0), crackle = 0.6, fade_s = 0.05}})
		# Level before the drive, so it colours rather than flattens.
		r.fx = [{type = "normalize", peak_db = -6.0}, {type = "drive", amount = u(0.2, 0.45)}]
		if chance(0.5):
			r.fx.append({type = "room", room = u(0.4, 0.7), damp = 0.5, mix = 0.15, quality = "small"})
		r.vary = {pitch_scale = 0.08}

	func powerup(r: AKRecipe) -> void:
		var wave: String = pick(["square", "pulse", "triangle", "sine"])
		var f0 := lg(200.0, 480.0)
		if chance(0.4):
			# A rising arpeggio: root, third, fifth, octave.
			var step := u(0.05, 0.08)
			var thirds := [1.0, 1.2599, 1.4983, 2.0]
			r.voice = &"tone"
			r.params = note(wave, f0, step, 0.6, 0.015)
			var top := rng.randi_range(3, 4)
			for i in range(1, top + 1):
				var oct := 2.0 if i >= 4 else 1.0
				var last := i == top
				r.layers.append({voice = &"tone", offset_s = AKSfxGen._snap(step * i),
					params = note(wave, f0 * thirds[i % 4] * oct, step * (3.0 if last else 1.0), 0.6, 0.08 if last else 0.015,
						{vibrato_hz = 10.0, vibrato_semitones = 0.3} if last else {})})
		else:
			var extra := {end_hz = AKSfxGen._snap(f0 * u(2.2, 4.0)), glide_s = u(0.12, 0.25), decay_s = 0.2}
			if chance(0.6):
				extra["vibrato_hz"] = u(8.0, 16.0)
				extra["vibrato_semitones"] = u(0.3, 1.0)
			r.voice = &"tone"
			r.params = note(wave, f0, u(0.3, 0.55), 0.8, u(0.06, 0.12), extra)
		r.fx = []
		if chance(0.4):
			r.fx.append({type = "echo", time_s = u(0.08, 0.14), feedback = u(0.2, 0.35), mix = 0.2, tail_s = 0.4})
		r.vary = {pitch_scale = 0.03}

	func ui_click(r: AKRecipe) -> void:
		r.voice = &"click"
		r.params = {mode = "band", freq_hz = lg(1500.0, 6000.0), q = u(2.0, 8.0), decay_s = u(0.002, 0.007),
			body_hz = lg(150.0, 500.0) if chance(0.5) else 0.0, body = 0.3}
		if chance(0.4):
			var p2: Dictionary = r.params.duplicate()
			p2.freq_hz = AKSfxGen._snap(float(p2.freq_hz) * u(1.1, 1.5))
			r.layers = [{voice = &"click", offset_s = u(0.02, 0.045), gain_db = -6.0, params = p2}]
		r.fx = [{type = "highpass1", cutoff_hz = 100.0}]
		r.vary = {pitch_scale = 0.05}

	func ui_note_pair(r: AKRecipe, up: bool) -> void:
		var wave: String = pick(["sine", "triangle", "sine", "triangle"])
		var f0 := lg(440.0, 880.0) if up else lg(440.0, 800.0)
		var ratio: float = pick([1.2599, 1.3348, 1.4983])
		r.voice = &"tone"
		if not up and chance(0.35):
			# A short slide down instead of two notes.
			r.params = note(wave, f0, u(0.1, 0.16), 0.7, 0.04, {end_hz = AKSfxGen._snap(f0 / ratio / ratio), glide_s = u(0.04, 0.07)})
		else:
			var g1 := u(0.04, 0.07)
			r.params = note(wave, f0, g1, 0.6, 0.012)
			r.layers = [{voice = &"tone", offset_s = AKSfxGen._snap(g1 + u(0.0, 0.02)),
				params = note(wave, f0 * ratio if up else f0 / ratio, u(0.07, 0.12), 0.6, u(0.04, 0.08))}]
		r.vary = {pitch_scale = 0.02}

	func blip(r: AKRecipe) -> void:
		var wave: String = pick(["square", "pulse", "triangle", "sine"])
		var f0 := lg(400.0, 1800.0)
		var extra := {}
		if chance(0.3):
			extra = {end_hz = AKSfxGen._snap(f0 * u(0.9, 1.25)), glide_s = 0.02}
		r.voice = &"tone"
		r.params = note(wave, f0, u(0.02, 0.06), 0.8, u(0.005, 0.015), extra)
		r.vary = {pitch_scale = 0.04}

	## Anything goes: one to three layers of any of these voices, each
	## parameter drawn from its whole range (times capped), plus effects.
	func random(r: AKRecipe) -> void:
		var pool := [&"tone", &"tone", &"fm", &"whoosh", &"click", &"boing", &"mallet", &"ratchet", &"pluck", &"wavetable"]
		var count := rng.randi_range(1, 3)
		for i in count:
			var vn: StringName = pick(pool)
			var p := {}
			var schema := AK.voice(vn).schema()
			var keys := schema.keys()
			keys.sort()
			for k in keys:
				var s: Dictionary = schema[k]
				var d: Variant = s.default
				var ks := String(k)
				if d is StringName or d is String:
					var opts := {wave = ["sine", "triangle", "saw", "square", "pulse"], mode = ["low", "band", "high"],
						noise = ["white", "pink", "brown"], material = ["wood", "metal", "glass", "bar"]}
					if opts.has(ks):
						p[ks] = pick(opts[ks])
				elif d is float or d is int:
					var lo := float(s.min) if s.min != null else float(d) * 0.5
					var hi := float(s.max) if s.max != null else float(d) * 2.0
					if ks == "length_s" or ks == "gate_s":
						lo = maxf(lo, 0.05)
						hi = minf(hi, 0.9)
					elif ks.ends_with("_s"):
						hi = minf(hi, 0.5)
					if ks.ends_with("_hz"):
						lo = maxf(lo, 60.0)
						hi = minf(hi, 6000.0)
					var x := lg(maxf(lo, 1e-3), maxf(hi, 2e-3)) if (ks.ends_with("_hz") or ks.ends_with("_s")) and lo > 0.0 else u(lo, hi)
					p[ks] = roundi(x) if d is int else x
			if i == 0:
				r.voice = vn
				r.params = p
			else:
				r.layers.append({voice = vn, params = p, gain_db = u(-9.0, 0.0), offset_s = u(0.0, 0.15)})
		var fx_pool := ["lowpass", "highpass", "drive", "bitcrush", "echo"]
		for i in rng.randi_range(0, 2):
			match String(pick(fx_pool)):
				"lowpass": r.fx.append({type = "lowpass", cutoff_hz = lg(800.0, 8000.0), q = u(0.6, 3.0)})
				"highpass": r.fx.append({type = "highpass", cutoff_hz = lg(100.0, 1500.0)})
				"drive": r.fx.append({type = "drive", amount = u(0.1, 0.7)})
				"bitcrush": r.fx.append({type = "bitcrush", bits = u(4.0, 10.0), hold = rng.randi_range(1, 4)})
				"echo": r.fx.append({type = "echo", time_s = u(0.05, 0.2), feedback = u(0.2, 0.5), mix = u(0.15, 0.35), tail_s = 0.5})
		r.transforms = [{type = "trim", length_s = 2.0}, {type = "fade", out_s = 0.02}]
		r.vary = {pitch_scale = 0.05}
