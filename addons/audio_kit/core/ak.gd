# SPDX-License-Identifier: Apache-2.0
@tool
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
const VERSION := 2
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
## `overrides` sets targets after binding (any bind target name), plus the
## sequencer's `_note_hz` (play at this pitch), `_keytrack` (false: move only
## the voices' pitch parameters, not filters), `_gate_s` (hold length) and
## `_cut_s` (stop the sound there: a drum kit's choke group).
static func render(recipe: AKRecipe, intensity := 1.0, data := {}, variant := 0, overrides := {}) -> AKBuffer:
	var sr := sample_rate
	var pal: AKPalette = recipe.palette if recipe.palette else palette
	var var_used := _variant(recipe, variant)
	var level := {gain_db = recipe.gain_db, pan = recipe.pan, pitch_scale = 1.0, send = recipe.send}
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
	if not overrides.is_empty():
		_apply_overrides(overrides, voices, level, lparams, fx)

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
	# Delay-based effects (chorus, flanger) ring on: give them room.
	var stream_tail := AKStreamFx.tail_s(fx)
	if stream_tail > 0.0:
		out.resize(out.frames() + roundi(stream_tail * sr))
	for e in fx:
		apply_fx(out, e)
	for t in transforms:
		out = apply_transform(out, t)
	out.apply_gain(AKDsp.db_to_gain(float(level.gain_db)))
	_balance(out, float(level.pan))
	out.send = clampf(float(level.send), 0.0, 1.0)
	if overrides.has("_cut_s"):
		cut(out, float(overrides._cut_s))
	return out


## How long a choked sound takes to fade out (see `cut`).
const CHOKE_FADE_S := 0.003


## Stop a sound at `at_s`, fading over CHOKE_FADE_S before it: how a drum
## kit's choke group silences a ringing piece (the `_cut_s` override, which
## songs set from a pattern event's `cut_s`). Shorter sounds are untouched.
static func cut(buf: AKBuffer, at_s: float) -> void:
	var end := maxi(0, roundi(at_s * buf.sample_rate))
	if end >= buf.frames():
		return
	var fade := maxi(1, roundi(CHOKE_FADE_S * buf.sample_rate))
	var start := maxi(0, end - fade)
	for i in range(start, end):
		var g := float(end - i) / float(end - start + 1)
		buf.l[i] *= g
		buf.r[i] *= g
	buf.resize(end)


## Render and encode to a 16-bit `AudioStreamWAV`, cached in memory and (in
## the editor) on disk under BAKE_DIR.
static func bake(recipe: AKRecipe, intensity := 1.0, data := {}, variant := 0, overrides := {}) -> AudioStreamWAV:
	var key := bake_key(recipe, intensity, data, variant, overrides)
	if _mem.has(key):
		return _mem[key]
	var path := BAKE_DIR + key.left(24) + ".res"
	var stream: AudioStreamWAV = null
	if disk_cache and ResourceLoader.exists(path):
		stream = load(path)
	if stream == null:
		stream = render(recipe, intensity, data, variant, overrides).to_stream(_seed(recipe.seed, _variant(recipe, variant), 77))
		if disk_cache and OS.has_feature("editor"):
			DirAccess.make_dir_recursive_absolute(BAKE_DIR)
			ResourceSaver.save(stream, path)
	_mem[key] = stream
	return stream


## Render a recipe and write it to `path` as a 16-bit WAV with the same
## samples `bake` gives (same dither), so it can live in the project as an
## ordinary AudioStreamWAV. In the editor the file panel is rescanned.
static func bake_wav(recipe: AKRecipe, path: String, intensity := 1.0, data := {}, variant := 0, overrides := {}) -> Error:
	var buf := render(recipe, intensity, data, variant, overrides)
	return save_wav(buf, path, _seed(recipe.seed, _variant(recipe, variant), 77))


## Write a buffer to `path` as a 16-bit WAV (making folders as needed); in
## the editor, rescan so it shows up and imports.
static func save_wav(buf: AKBuffer, path: String, dither_seed := 0) -> Error:
	if buf == null or buf.frames() == 0:
		return ERR_INVALID_DATA
	var err := buf.save_wav(path, dither_seed)
	if err == OK:
		refresh_editor_files()
	return err


## Ask the editor (when running in it) to rescan the project's files. A
## no-op in games and headless runs. Doesn't name EditorInterface, which
## exported builds don't have.
static func refresh_editor_files() -> void:
	if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		var fs: Object = Engine.get_singleton(&"EditorInterface").call(&"get_resource_filesystem")
		if fs:
			fs.call(&"scan")


## Hash of everything that can change a bake. Intensity, data and variant
## count only when the recipe's bind and vary rules use them, so identical
## hits share one bake.
static func bake_key(recipe: AKRecipe, intensity := 1.0, data := {}, variant := 0, overrides := {}) -> String:
	var used := {}
	if recipe.voice != &"":
		used[String(recipe.voice)] = _voice_version(recipe.voice)
		_key_extra(used, recipe.voice, recipe.params, 0)
	for li in recipe.layers.size():
		var l: Dictionary = recipe.layers[li]
		var vn := StringName(l.get("voice", &""))
		used[String(vn)] = _voice_version(vn)
		_key_extra(used, vn, l.get("params", {}), li + 1)
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
	var payload := {kit = VERSION, sr = sample_rate, recipe = _hashable(recipe.describe()), voices = used, overrides = overrides,
		intensity = snappedf(intensity, 1e-6) if bound_i else 0.0, data = bound_d,
		variant = _variant(recipe, variant),
		palette = pal.tokens if pal else {}}
	return JSON.stringify(payload, "", true, true).sha256_text()


## A copy of `v` that hashes by content: resources inside (an AKPatch in a
## layer's params, say) become their describe() or, failing that, their path.
## Plain values are untouched, so existing recipes keep their keys.
static func _hashable(v: Variant) -> Variant:
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = _hashable(v[k])
		return d
	if v is Array:
		var a := []
		for x in v:
			a.append(_hashable(x))
		return a
	if v is Resource:
		if v.has_method(&"describe"):
			return {resource = v.get_class(), content = _hashable(v.call(&"describe"))}
		return {resource = v.get_class(), path = v.resource_path}
	return v


static func clear_cache() -> void:
	_mem.clear()


# ------------------------------------------------------------------ cue sheets

## Render a list of cues into one track. Each cue is a dictionary with
## `name` and either `time` (seconds) or `frame` (at `fps`), plus optional
## `intensity` and `data`: the shape of the motion kit's export_cue_sheet().
## Returns {mix: AKBuffer, stems: {name: AKBuffer}, cues: [placement info]}.
## `length_s` sets a minimum length (the picture's duration). A `song` (an
## AKSong, or an AKArrangement, which plays its timeline) is mixed
## underneath, sharing the cue map's reverb and master chain. Cues whose
## data.source is "song" (from AKSong.to_cues) are skipped: the song plays them.
static func render_cues(cues: Array, cue_map: AKCueMap, fps := 30.0, length_s := 0.0, with_stems := false, music: Resource = null) -> Dictionary:
	var song := as_song(music)
	var sr := sample_rate
	var mix := AKBuffer.new(roundi(length_s * sr), sr)
	var stems := {}
	var placed := []
	var counts := {}
	var memo := {}
	var send_bus := AKBuffer.new(0, sr)
	for c: Dictionary in cues:
		if String(c.get("data", {}).get("source", "")) == "song":
			continue
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
		if buf.send > 0.0:
			buf.mix_into(send_bus, at, buf.send)
		if with_stems:
			if not stems.has(name):
				stems[name] = AKBuffer.new(0, sr)
			buf.mix_into(stems[name], at)
		placed.append({name = name, time = t, sample = at, cue_sample = roundi(t * sr), intensity = intensity,
			frames = buf.frames(), lead_in = maxi(0, buf.first_above(1e-4)), recipe = recipe.resource_path,
			offset_s = recipe.offset_s})
	if song:
		var sr_song := song.render(with_stems, false, send_bus)
		var dk := cue_map.duck_settings()
		if not dk.is_empty():
			# `mix` holds the effects alone at this point: the sidechain.
			AKDynamics.duck(sr_song.mix, mix, dk.depth_db, dk.full_at_db, dk.attack_s, dk.release_s)
			if with_stems:
				for k in sr_song.stems:
					AKDynamics.duck(sr_song.stems[k], mix, dk.depth_db, dk.full_at_db, dk.attack_s, dk.release_s)
		sr_song.mix.mix_into(mix, 0)
		if with_stems:
			stems.merge(sr_song.stems)
	if send_bus.frames() > 0 and send_bus.peak() > 0.0:
		var rv := cue_map.reverb
		var wet := AKReverb.wet(send_bus, float(rv.get("room", 0.5)), float(rv.get("damp", 0.5)), float(rv.get("width", 1.0)),
			float(rv.get("tail_s", -1.0)), StringName(rv.get("quality", &"full")))
		wet.mix_into(mix, 0, AKDsp.db_to_gain(float(rv.get("return_db", 0.0))))
		if with_stems:
			stems["reverb"] = AKBuffer.new(0, sr)
			wet.mix_into(stems["reverb"], 0, AKDsp.db_to_gain(float(rv.get("return_db", 0.0))))
	if cue_map.end_fade_s > 0.0 and length_s > 0.0:
		_fit_end(mix, length_s, cue_map.end_fade_s)
		for k in stems:
			_fit_end(stems[k], length_s, cue_map.end_fade_s)
	# The master chain's tails (room, echo) are padded up front, so every
	# stage runs over the whole length, as the live mixer does.
	var tail := master_tail_frames(cue_map.master_fx, sr)
	if tail > 0:
		mix.resize(mix.frames() + tail)
	for e in cue_map.master_fx:
		apply_fx(mix, _without_tail(e))
	for k in stems:
		stems[k].resize(mix.frames())
	return {mix = mix, stems = stems, cues = placed}


## Hash of everything that can change render_cues' mix for these cues: the
## cue placements and each hit's bake key, the map's master chain and reverb.
static func track_key(cues: Array, cue_map: AKCueMap, fps := 30.0, length_s := 0.0, music: Resource = null) -> String:
	var song := as_song(music)
	var parts := []
	var counts := {}
	for c: Dictionary in cues:
		if String(c.get("data", {}).get("source", "")) == "song":
			continue
		var name := String(c.get("name", ""))
		var t: float = float(c.time) if c.has("time") else float(c.get("frame", 0.0)) / fps
		var recipe := cue_map.recipe_for(StringName(name))
		if recipe == null:
			parts.append([name, snappedf(t, 1e-6), "-"])
			continue
		var idx: int = counts.get(name, 0)
		counts[name] = idx + 1
		parts.append([name, snappedf(t, 1e-6), recipe.offset_s, bake_key(recipe, float(c.get("intensity", 1.0)), c.get("data", {}), idx)])
	var payload := {kit = VERSION, track_format = 2, sr = sample_rate, length = snappedf(length_s, 1e-6), cues = parts, song = song.key() if song else "",
		end_fade = cue_map.end_fade_s, duck = cue_map.duck_settings(),
		master = cue_map.master_fx, reverb = cue_map.reverb}
	return JSON.stringify(payload, "", true, true).sha256_text()


## Music as a song: an AKSong as it is, an AKArrangement's timeline compiled
## (cached), anything else null.
static func as_song(music: Resource) -> AKSong:
	if music is AKSong:
		return music
	if music is AKArrangement:
		return (music as AKArrangement).to_song("timeline")
	return null


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
			var stages := 2 if float(e.get("slope_db", 12.0)) >= 24.0 else 1
			for _s in stages:
				buf.l = AKFilter.svf(buf.l, cut, q, sr, mode)
				buf.r = AKFilter.svf(buf.r, cut, q, sr, mode)
		&"lowpass1":
			buf.l = AKFilter.lowpass1(buf.l, float(e.get("cutoff_hz", 1000.0)), sr)
			buf.r = AKFilter.lowpass1(buf.r, float(e.get("cutoff_hz", 1000.0)), sr)
		&"highpass1":
			buf.l = AKFilter.highpass1(buf.l, float(e.get("cutoff_hz", 100.0)), sr)
			buf.r = AKFilter.highpass1(buf.r, float(e.get("cutoff_hz", 100.0)), sr)
		&"drive":
			buf.l = AKShape.drive(buf.l, float(e.get("amount", 0.3)))
			buf.r = AKShape.drive(buf.r, float(e.get("amount", 0.3)))
		&"bitcrush":
			buf.l = AKShape.bitcrush(buf.l, float(e.get("bits", 8.0)), int(e.get("hold", 1)))
			buf.r = AKShape.bitcrush(buf.r, float(e.get("bits", 8.0)), int(e.get("hold", 1)))
		&"room":
			AKReverb.process(buf, float(e.get("room", 0.5)), float(e.get("damp", 0.5)), float(e.get("mix", 0.2)),
				float(e.get("width", 1.0)), float(e.get("tail_s", -1.0)), StringName(e.get("quality", &"full")))
		&"echo":
			AKDelay.echo(buf, float(e.get("time_s", 0.25)), float(e.get("feedback", 0.35)), float(e.get("mix", 0.3)),
				float(e.get("tail_s", 1.0)))
		&"gain":
			buf.apply_gain(AKDsp.db_to_gain(float(e.get("db", 0.0))))
		&"limit":
			AKDynamics.limit(buf, float(e.get("ceiling_db", -1.0)), float(e.get("release_s", 0.08)))
		&"normalize":
			AKDynamics.normalize(buf, float(e.get("peak_db", -1.0)))
		&"dcblock":
			buf.l = AKFilter.highpass1(buf.l, float(e.get("cutoff_hz", 10.0)), sr)
			buf.r = AKFilter.highpass1(buf.r, float(e.get("cutoff_hz", 10.0)), sr)
		&"loudness":
			AKDynamics.loudness(buf, float(e.get("target_lufs", -16.0)))
		&"chorus", &"flanger", &"phaser", &"eq", &"compressor", &"saturate":
			var lr := AKStreamFx.process([e], buf.l, buf.r, sr)
			buf.l = lr[0]
			buf.r = lr[1]
		_:
			push_error("AK: unknown effect '%s'" % type)


static func apply_transform(buf: AKBuffer, t: Dictionary) -> AKBuffer:
	var type := StringName(t.get("type", &""))
	match type:
		&"reverse":
			buf.l.reverse()
			buf.r.reverse()
		&"fade":
			buf.l = AKEnv.fade(buf.l, buf.sample_rate, float(t.get("in_s", 0.0)), float(t.get("out_s", 0.0)))
			buf.r = AKEnv.fade(buf.r, buf.sample_rate, float(t.get("in_s", 0.0)), float(t.get("out_s", 0.0)))
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

## The variant a hit actually uses: 0 without `vary`, cycled by vary_variants.
static func _variant(recipe: AKRecipe, variant: int) -> int:
	if recipe.vary.is_empty():
		return 0
	return variant % recipe.vary_variants if recipe.vary_variants > 0 else variant


## Content a voice's output depends on beyond its parameters (the patch a
## `patch` voice loads by path), added to the bake key only when present.
static func _key_extra(used: Dictionary, vn: StringName, params: Dictionary, slot: int) -> void:
	var v := voice(vn)
	if v == null:
		return
	var ex: Variant = v.key_extra(params)
	if ex != null:
		used["%s#%d" % [vn, slot]] = _hashable(ex)


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


static func _apply_overrides(ov: Dictionary, voices: Array[AKVoice], level: Dictionary, lparams: Array[Dictionary], fx: Array[Dictionary]) -> void:
	for k in ov:
		if not String(k).begins_with("_"):
			_set_target(String(k), ov[k], level, lparams, fx)
	if ov.has("_gate_s"):
		var g := float(ov._gate_s)
		for p in lparams:
			if p.has("gate_s"):
				p.gate_s = g
				if p.has("length_s") and float(p.length_s) > 0.0 and float(p.length_s) < g + 0.02:
					p.length_s = 0.0   # auto: gate plus release
	if ov.has("_note_hz") and not voices.is_empty():
		var pp := voices[0].pitch_params()
		if not pp.is_empty() and lparams[0].has(pp[0]) and float(lparams[0][pp[0]]) > 0.0:
			var ratio := float(ov._note_hz) / float(lparams[0][pp[0]])
			if bool(ov.get("_keytrack", true)):
				level.pitch_scale = float(level.pitch_scale) * ratio
			else:
				for i in voices.size():
					for name in voices[i].pitch_params():
						if lparams[i].has(name):
							lparams[i][name] = float(lparams[i][name]) * ratio


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


## Fade out over `fade_s` ending at `length_s`, then cut there.
## Frames the room and echo steps of a master chain add after the mix.
static func master_tail_frames(chain: Array, sr: int) -> int:
	var n := 0
	for e: Dictionary in chain:
		match StringName(e.get("type", &"")):
			&"room":
				if float(e.get("mix", 0.2)) > 0.0:
					var t := float(e.get("tail_s", -1.0))
					n += roundi((t if t >= 0.0 else 0.3 + 2.2 * clampf(float(e.get("room", 0.5)), 0.0, 1.0)) * sr)
			&"echo":
				n += roundi(float(e.get("tail_s", 1.0)) * sr)
	return n


static func _without_tail(e: Dictionary) -> Dictionary:
	var t := StringName(e.get("type", &""))
	if t == &"room" or t == &"echo":
		var d := e.duplicate()
		d["tail_s"] = 0.0
		return d
	return e


static func _fit_end(buf: AKBuffer, length_s: float, fade_s: float) -> void:
	var end := roundi(length_s * buf.sample_rate)
	var start := maxi(0, end - roundi(fade_s * buf.sample_rate))
	buf.resize(maxi(end, buf.frames()))
	for i in range(start, end):
		var g := float(end - i) / maxf(1.0, end - start)
		g *= g
		buf.l[i] *= g
		buf.r[i] *= g
	buf.resize(end)


static func _balance(buf: AKBuffer, pan: float) -> void:
	if pan > 0.0:
		buf.l = AKDsp.scale(buf.l, 1.0 - pan)
	elif pan < 0.0:
		buf.r = AKDsp.scale(buf.r, 1.0 + pan)


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
