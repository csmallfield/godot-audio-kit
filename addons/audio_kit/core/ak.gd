# SPDX-License-Identifier: Apache-2.0
## The kit's entry point: render and bake recipes, render cue sheets.
##
##   var hit := AK.bake(load("res://sfx/hit.tres"))            # AudioStreamWAV, cached
##   var buf := AK.render(recipe, 0.8, {pitch = 1.1})           # AKBuffer, float
##   var out := AK.render_cues(cues, cue_map, 30.0)             # {mix, stems, cues}
##
## Everything is deterministic: the same recipe, cue and sample rate always
## give the same samples on the same platform.
class_name AK
extends RefCounted

## Bumped when a change to the pipeline alters output (invalidates bakes).
const VERSION := 1
const VOICE_DIR := "res://addons/audio_kit/voices/"
const BAKE_DIR := "res://audio_kit/baked/"

## 48 kHz divides evenly by 24, 25, 30 and 60 fps (Movie Maker needs that).
static var sample_rate := 48000
## Default palette for "$name" values.
static var palette: AKPalette
## Save bakes under BAKE_DIR when running in the editor (or headless editor).
static var disk_cache := true

static var _voices := {}
static var _mem := {}


# ------------------------------------------------------------------ voices

static func voice(name: StringName) -> AKVoice:
	if _voices.has(name):
		return _voices[name]
	var path := VOICE_DIR + String(name) + ".gd"
	if String(name) == "" or String(name) == "voice" or not ResourceLoader.exists(path):
		push_error("AK: no voice '%s'" % name)
		return null
	var v: AKVoice = load(path).new()
	_voices[name] = v
	return v


## Make a voice defined elsewhere available to recipes by name.
static func register_voice(name: StringName, v: AKVoice) -> void:
	_voices[name] = v


static func voice_names() -> PackedStringArray:
	var names := PackedStringArray()
	for f in DirAccess.get_files_at(VOICE_DIR):
		if f.ends_with(".gd") and f != "voice.gd":
			names.append(f.get_basename())
	for k in _voices:
		if not names.has(String(k)):
			names.append(String(k))
	names.sort()
	return names


# ------------------------------------------------------------------ render

## Render a recipe for one hit: `intensity` and `data` drive its `bind`
## rules; `variant` selects its per-hit variation (when `vary` is set).
static func render(recipe: AKRecipe, intensity := 1.0, data := {}, variant := 0) -> AKBuffer:
	var sr := sample_rate
	var pal: AKPalette = recipe.palette if recipe.palette else palette
	var var_used := variant if not recipe.vary.is_empty() else 0
	var level := {gain_db = recipe.gain_db, pan = recipe.pan, pitch_scale = 1.0}
	var fx := _resolve_list(recipe.fx, pal)
	var transforms := _resolve_list(recipe.transforms, pal)

	var specs: Array[Dictionary] = []
	if recipe.voice != &"":
		specs.append({voice = recipe.voice, params = recipe.params})
	for l in recipe.layers:
		specs.append(l)
	var voices: Array[AKVoice] = []
	var lparams: Array[Dictionary] = []
	var lspecs: Array[Dictionary] = []
	for spec in specs:
		var v := voice(StringName(spec.get("voice", &"")))
		if v == null:
			continue
		var p := v.defaults()
		var given: Dictionary = spec.get("params", {})
		for k in given:
			p[String(k)] = _token(given[k], pal)
		voices.append(v)
		lparams.append(p)
		lspecs.append(spec)

	_apply_bind(recipe.bind, intensity, data, level, lparams, fx)

	if not recipe.vary.is_empty():
		var vr := RandomNumberGenerator.new()
		vr.seed = _seed(recipe.seed, var_used, 9973)
		for k in recipe.vary:
			var f := 1.0 + vr.randf_range(-1.0, 1.0) * float(recipe.vary[k])
			_scale_target(String(k), f, level, lparams, fx)

	var ps := float(level.pitch_scale)
	if not is_equal_approx(ps, 1.0):
		for p in lparams:
			for k in p:
				if String(k).ends_with("_hz") and (p[k] is float or p[k] is int):
					p[k] = float(p[k]) * ps

	var out := AKBuffer.new(0, sr)
	for i in voices.size():
		var rng := RandomNumberGenerator.new()
		rng.seed = _seed(recipe.seed, var_used, i)
		var mono := voices[i].render(lparams[i], sr, rng)
		var b := AKBuffer.from_mono(mono, sr, float(lspecs[i].get("pan", 0.0)))
		var at := roundi(maxf(0.0, float(lspecs[i].get("offset_s", 0.0))) * sr)
		b.mix_into(out, at, AKDsp.db_to_gain(float(lspecs[i].get("gain_db", 0.0))))
	for e in fx:
		apply_fx(out, e)
	for t in transforms:
		out = apply_transform(out, t)
	out.apply_gain(AKDsp.db_to_gain(float(level.gain_db)))
	_balance(out, float(level.pan))
	return out


## Render and encode to a 16-bit `AudioStreamWAV`, cached in memory and (in
## the editor) on disk under BAKE_DIR.
static func bake(recipe: AKRecipe, intensity := 1.0, data := {}, variant := 0) -> AudioStreamWAV:
	var key := bake_key(recipe, intensity, data, variant)
	if _mem.has(key):
		return _mem[key]
	var path := BAKE_DIR + key.left(24) + ".res"
	var stream: AudioStreamWAV = null
	if disk_cache and ResourceLoader.exists(path):
		stream = load(path)
	if stream == null:
		stream = render(recipe, intensity, data, variant).to_stream(_seed(recipe.seed, variant, 77))
		if disk_cache and OS.has_feature("editor"):
			DirAccess.make_dir_recursive_absolute(BAKE_DIR)
			ResourceSaver.save(stream, path)
	_mem[key] = stream
	return stream


## Hash of everything that can change a bake. Intensity, data and variant
## count only when the recipe's bind and vary rules use them, so identical
## hits share one bake.
static func bake_key(recipe: AKRecipe, intensity := 1.0, data := {}, variant := 0) -> String:
	var used := {}
	if recipe.voice != &"":
		used[String(recipe.voice)] = _voice_version(recipe.voice)
	for l in recipe.layers:
		var vn := StringName(l.get("voice", &""))
		used[String(vn)] = _voice_version(vn)
	var bound_i := false
	var bound_d := {}
	for k in recipe.bind:
		var ks := String(k)
		if ks == "intensity":
			bound_i = true
		elif ks.begins_with("data."):
			var dk := ks.substr(5)
			if data.has(dk):
				bound_d[dk] = data[dk]
			elif data.has(StringName(dk)):
				bound_d[dk] = data[StringName(dk)]
	var pal: AKPalette = recipe.palette if recipe.palette else palette
	var payload := {kit = VERSION, sr = sample_rate, recipe = recipe.describe(), voices = used,
		intensity = snappedf(intensity, 1e-6) if bound_i else 0.0, data = bound_d,
		variant = variant if not recipe.vary.is_empty() else 0,
		palette = pal.tokens if pal else {}}
	return JSON.stringify(payload, "", true, true).sha256_text()


static func clear_cache() -> void:
	_mem.clear()


# ------------------------------------------------------------------ cue sheets

## Render a list of cues into one track. Each cue is a dictionary with
## `name` and either `time` (seconds) or `frame` (at `fps`), plus optional
## `intensity` and `data`: the shape of the motion kit's export_cue_sheet().
## Returns {mix: AKBuffer, stems: {name: AKBuffer}, cues: [placement info]}.
## `length_s` sets a minimum length (the picture's duration).
static func render_cues(cues: Array, cue_map: AKCueMap, fps := 30.0, length_s := 0.0, with_stems := false) -> Dictionary:
	var sr := sample_rate
	var mix := AKBuffer.new(roundi(length_s * sr), sr)
	var stems := {}
	var placed := []
	var counts := {}
	var memo := {}
	for c: Dictionary in cues:
		var name := String(c.get("name", ""))
		var t: float = float(c.time) if c.has("time") else float(c.get("frame", 0.0)) / fps
		var recipe := cue_map.recipe_for(StringName(name))
		if recipe == null:
			placed.append({name = name, time = t, missing = true})
			continue
		var idx: int = counts.get(name, 0)
		counts[name] = idx + 1
		var intensity := float(c.get("intensity", 1.0))
		var data: Dictionary = c.get("data", {})
		var key := bake_key(recipe, intensity, data, idx)
		var buf: AKBuffer = memo.get(key)
		if buf == null:
			buf = render(recipe, intensity, data, idx)
			memo[key] = buf
		var at := roundi((t + recipe.offset_s) * sr)
		buf.mix_into(mix, at)
		if with_stems:
			if not stems.has(name):
				stems[name] = AKBuffer.new(0, sr)
			buf.mix_into(stems[name], at)
		placed.append({name = name, time = t, sample = at, cue_sample = roundi(t * sr), intensity = intensity,
			frames = buf.frames(), lead_in = maxi(0, buf.first_above(1e-4)), recipe = recipe.resource_path,
			offset_s = recipe.offset_s})
	for e in cue_map.master_fx:
		apply_fx(mix, e)
	for k in stems:
		stems[k].resize(mix.frames())
	return {mix = mix, stems = stems, cues = placed}


## Read a cue sheet JSON written by MotionComposition.export_cue_sheet().
static func load_cue_sheet(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var d: Variant = JSON.parse_string(text)
	if d is Dictionary:
		return d
	push_error("AK: could not read cue sheet %s" % path)
	return {}


# ------------------------------------------------------------------ effects

static func apply_fx(buf: AKBuffer, e: Dictionary) -> void:
	var sr := buf.sample_rate
	var type := StringName(e.get("type", &""))
	match type:
		&"lowpass", &"highpass", &"bandpass", &"notch":
			var mode: StringName = {&"lowpass": &"low", &"highpass": &"high", &"bandpass": &"band", &"notch": &"notch"}[type]
			var cut := float(e.get("cutoff_hz", 1000.0))
			var q := float(e.get("q", 0.707))
			buf.l = AKFilter.svf(buf.l, cut, q, sr, mode)
			buf.r = AKFilter.svf(buf.r, cut, q, sr, mode)
		&"lowpass1":
			buf.l = AKFilter.lowpass1(buf.l, float(e.get("cutoff_hz", 1000.0)), sr)
			buf.r = AKFilter.lowpass1(buf.r, float(e.get("cutoff_hz", 1000.0)), sr)
		&"highpass1":
			buf.l = AKFilter.highpass1(buf.l, float(e.get("cutoff_hz", 100.0)), sr)
			buf.r = AKFilter.highpass1(buf.r, float(e.get("cutoff_hz", 100.0)), sr)
		&"drive":
			AKShape.drive(buf.l, float(e.get("amount", 0.3)))
			AKShape.drive(buf.r, float(e.get("amount", 0.3)))
		&"bitcrush":
			AKShape.bitcrush(buf.l, float(e.get("bits", 8.0)), int(e.get("hold", 1)))
			AKShape.bitcrush(buf.r, float(e.get("bits", 8.0)), int(e.get("hold", 1)))
		&"room":
			AKReverb.process(buf, float(e.get("room", 0.5)), float(e.get("damp", 0.5)), float(e.get("mix", 0.2)),
				float(e.get("width", 1.0)), float(e.get("tail_s", -1.0)))
		&"echo":
			AKDelay.echo(buf, float(e.get("time_s", 0.25)), float(e.get("feedback", 0.35)), float(e.get("mix", 0.3)),
				float(e.get("tail_s", 1.0)))
		&"gain":
			buf.apply_gain(AKDsp.db_to_gain(float(e.get("db", 0.0))))
		&"limit":
			AKDynamics.limit(buf, float(e.get("ceiling_db", -1.0)), float(e.get("release_s", 0.08)))
		&"normalize":
			AKDynamics.normalize(buf, float(e.get("peak_db", -1.0)))
		&"loudness":
			AKDynamics.loudness(buf, float(e.get("target_lufs", -16.0)))
		_:
			push_error("AK: unknown effect '%s'" % type)


static func apply_transform(buf: AKBuffer, t: Dictionary) -> AKBuffer:
	var type := StringName(t.get("type", &""))
	match type:
		&"reverse":
			buf.l.reverse()
			buf.r.reverse()
		&"fade":
			AKEnv.fade(buf.l, buf.sample_rate, float(t.get("in_s", 0.0)), float(t.get("out_s", 0.0)))
			AKEnv.fade(buf.r, buf.sample_rate, float(t.get("in_s", 0.0)), float(t.get("out_s", 0.0)))
		&"varispeed":
			return _varispeed(buf, float(t.get("from", 1.0)), float(t.get("to", 0.0)))
		&"width":
			var w := float(t.get("amount", 1.0))
			for i in buf.frames():
				var m := (buf.l[i] + buf.r[i]) * 0.5
				var s := (buf.l[i] - buf.r[i]) * 0.5 * w
				buf.l[i] = m + s
				buf.r[i] = m - s
		&"trim":
			buf.resize(roundi(float(t.get("length_s", buf.seconds())) * buf.sample_rate))
		_:
			push_error("AK: unknown transform '%s'" % type)
	return buf


# ------------------------------------------------------------------ internals

static func _voice_version(name: StringName) -> int:
	var v := voice(name)
	return v.version() if v else -1


static func _seed(a: int, b: int, c: int) -> int:
	return ((a * 73856093) ^ (b * 19349663) ^ (c * 83492791)) & 0x7fffffffffff


static func _token(v: Variant, pal: AKPalette) -> Variant:
	if (v is String or v is StringName) and String(v).begins_with("$"):
		if pal == null:
			push_error("AK: '%s' needs a palette" % v)
			return null
		return pal.lookup(String(v))
	return v


static func _resolve_list(list: Array[Dictionary], pal: AKPalette) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in list:
		var d := {}
		for k in e:
			d[String(k)] = _token(e[k], pal)
		out.append(d)
	return out


static func _apply_bind(bind: Dictionary, intensity: float, data: Dictionary, level: Dictionary, lparams: Array[Dictionary], fx: Array[Dictionary]) -> void:
	for key in bind:
		var ks := String(key)
		if ks == "intensity":
			var rules: Dictionary = bind[key]
			for name in rules:
				var rg: Array = rules[name]
				_set_target(String(name), lerpf(float(rg[0]), float(rg[1]), clampf(intensity, 0.0, 1.0)), level, lparams, fx)
		elif ks.begins_with("data."):
			var dk := ks.substr(5)
			var has := data.has(dk) or data.has(StringName(dk))
			if has:
				var v: Variant = data[dk] if data.has(dk) else data[StringName(dk)]
				_set_target(String(bind[key]), v, level, lparams, fx)


static func _set_target(name: String, v: Variant, level: Dictionary, lparams: Array[Dictionary], fx: Array[Dictionary]) -> void:
	if level.has(name):
		level[name] = v
		return
	if name.begins_with("fx") and name.contains("."):
		var idx := name.substr(2, name.find(".") - 2).to_int()
		if idx >= 0 and idx < fx.size():
			fx[idx][name.substr(name.find(".") + 1)] = v
		return
	var hit := false
	for p in lparams:
		if p.has(name):
			p[name] = v
			hit = true
	if hit:
		return
	for e in fx:
		if e.has(name):
			e[name] = v
			hit = true
	if not hit:
		push_warning("AK: bind target '%s' matches nothing" % name)


static func _scale_target(name: String, f: float, level: Dictionary, lparams: Array[Dictionary], fx: Array[Dictionary]) -> void:
	if level.has(name):
		level[name] = float(level[name]) * f if name != "gain_db" else float(level[name]) + 20.0 * log(f) / log(10.0)
		return
	for p in lparams:
		if p.has(name) and (p[name] is float or p[name] is int):
			p[name] = float(p[name]) * f
	for e in fx:
		if e.has(name) and (e[name] is float or e[name] is int):
			e[name] = float(e[name]) * f


static func _balance(buf: AKBuffer, pan: float) -> void:
	if pan > 0.0:
		for i in buf.frames():
			buf.l[i] *= 1.0 - pan
	elif pan < 0.0:
		for i in buf.frames():
			buf.r[i] *= 1.0 + pan


static func _varispeed(buf: AKBuffer, from: float, to: float) -> AKBuffer:
	var n_in := buf.frames()
	var avg := maxf(0.02, (absf(from) + absf(to)) * 0.5)
	var n_out := roundi(n_in / avg)
	var out := AKBuffer.new(n_out, buf.sample_rate)
	var pos := 0.0
	for i in n_out:
		var rate := lerpf(from, to, float(i) / maxf(1.0, n_out - 1))
		var j := int(pos)
		if j >= n_in - 1:
			break
		var fr := pos - j
		out.l[i] = lerpf(buf.l[j], buf.l[j + 1], fr)
		out.r[i] = lerpf(buf.r[j], buf.r[j + 1], fr)
		pos += maxf(0.0, rate)
	return out
