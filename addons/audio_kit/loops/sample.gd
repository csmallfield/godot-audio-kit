# SPDX-License-Identifier: Apache-2.0
@tool
## One sound to play at pitch: the instrument of a sample loop, a piece of a
## drum kit, or the `sample` voice in any recipe.
##
##   var s := AKSample.new()
##   s.source = "res://audio/samples/kick_01.wav"   # .wav, .aif or .ogg in the project
##   s.import_source()                               # decode into `data` (the editor does this)
##   # or a recipe, rendered once and cached by its bake key:
##   s.recipe = load("res://addons/audio_kit/library/kicks/kick_round.tres")
##
## A sample plays resampled by 2^((note - root_note) / 12) with 4-point
## interpolation. `mode`: `oneshot` plays to its end whatever the note's
## length; `gate` stops at the note's end with a `release_s` fade; `loop`
## repeats loop_start_s..loop_end_s while the note is held, then releases.
##
## File sources are decoded into `data` (floats at `data_rate`), saved with
## the resource, so an exported game plays them without the source file or
## Godot's import compression. A stereo file keeps both channels: `data` is
## the left and `data_r` the right (empty for mono); a file whose channels
## are identical is kept mono. Recipe sources store nothing: recipes render
## anywhere, natively or in GDScript.
@icon("res://addons/audio_kit/icons/recipe.svg")
class_name AKSample
extends Resource

## A .wav, .aif(f) or .ogg in the project, or a recipe (.tres) path. Ignored
## when `recipe` is set.
@export_file("*.wav", "*.aif", "*.aiff", "*.ogg", "*.tres") var source := ""
## A recipe to render as the sample (wins over `source`).
@export var recipe: AKRecipe
## The MIDI note the sound was made at (60 = middle C): playing this note
## plays it as recorded.
@export_range(0.0, 127.0, 0.01) var root_note := 60.0
## Trim: where playing starts, and ends (0 = the end of the sound), in seconds.
@export var start_s := 0.0
@export var end_s := 0.0
@export_enum("oneshot", "gate", "loop") var mode := "oneshot"
## The loop, in seconds of the sound (loop_end_s 0 = the trimmed end).
@export var loop_start_s := 0.0
@export var loop_end_s := 0.0
## Fade after the note ends (gate and loop modes), a time constant.
@export_range(0.001, 10.0, 0.001, "or_greater") var release_s := 0.05
@export var gain_db := 0.0
## Play the trimmed sound backwards (loops are in the reversed sound's time).
@export var reverse := false
## Decoded samples of a file source (empty for recipes): what plays. The
## left channel when `data_r` holds a right one, else the mono sound.
@export_storage var data := PackedFloat32Array():
	set(v):
		data = v
		_data_key = ""
		_mono = PackedFloat32Array()
## The right channel of a stereo file source; empty for mono.
@export_storage var data_r := PackedFloat32Array():
	set(v):
		data_r = v
		_data_key = ""
		_mono = PackedFloat32Array()
## The sample rate of `data`.
@export_storage var data_rate := 0

static var _rendered := {}
var _data_key := ""
var _mono := PackedFloat32Array()


## Decode `source` into `data` (and `data_r` for stereo): a .wav or .aif
## through the kit's reader, an .ogg through Godot's decoder. Returns "" or an
## error. Takes the file's root
## note and loop from a WAV `smpl` chunk when `read_markers` is set.
func import_source(read_markers := false) -> String:
	if source == "" or source.get_extension().to_lower() in ["tres", "res"]:
		return "no audio file to import"
	var f := AKAudioFile.read(source)
	if f.error != "":
		return f.error
	_take(f)
	if read_markers:
		if f.root_note >= 0:
			root_note = f.root_note
		if f.loop.size() == 2:
			loop_start_s = float(f.loop[0]) / f.rate
			loop_end_s = float(f.loop[1]) / f.rate
	emit_changed()
	return ""


## The recipe this sample renders, or null for a file source.
func source_recipe() -> AKRecipe:
	if recipe:
		return recipe
	if source.get_extension().to_lower() in ["tres", "res"] and ResourceLoader.exists(source):
		var r: Resource = load(source)
		return r as AKRecipe
	return null


## The sound before trimming: [mono samples, their rate]. Recipes render
## once per bake key (in memory); files use `data`, decoding the source on
## first use when `data` is empty (editor and tests; exports need `data`).
func samples() -> Array:
	var r := source_recipe()
	if r:
		var key := AK.bake_key(r)
		if not _rendered.has(key):
			var buf := AK.render(r)
			var mono := buf.l.duplicate()
			for i in mono.size():
				mono[i] = 0.5 * (buf.l[i] + buf.r[i])
			_rendered[key] = mono
		return [_rendered[key], AK.sample_rate]
	_ensure_data()
	if data_r.is_empty():
		return [data, maxi(1, data_rate)]
	if _mono.size() != data.size():
		var n := mini(data.size(), data_r.size())
		_mono.resize(data.size())
		for i in data.size():
			_mono[i] = 0.5 * (data[i] + data_r[i]) if i < n else 0.5 * data[i]
	return [_mono, maxi(1, data_rate)]


## The sound before trimming in stereo: [left, right, rate], right empty for
## a mono sound (recipes are always mono here).
func stereo_samples() -> Array:
	if source_recipe():
		var m: Array = samples()
		return [m[0], PackedFloat32Array(), m[1]]
	_ensure_data()
	return [data, data_r, maxi(1, data_rate)]


## True when the sound has two different channels.
func is_stereo() -> bool:
	if source_recipe():
		return false
	_ensure_data()
	return not data_r.is_empty()


func _ensure_data() -> void:
	if data.is_empty() and source != "" and not source_recipe():
		var f := AKAudioFile.read(source)
		if f.error == "":
			_take(f)
		else:
			push_error("AKSample: %s" % f.error)


## Keep a read file's sound: both channels when they differ, else mono.
func _take(f: AKAudioFile) -> void:
	data_rate = f.rate
	if f.right.size() > 0 and not _same(f.left, f.right):
		data = f.left
		data_r = f.right
	else:
		data = f.data
		data_r = PackedFloat32Array()
	_data_key = ""


static func _same(a: PackedFloat32Array, b: PackedFloat32Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if absf(a[i] - b[i]) > 1e-7:
			return false
	return true


## Trim and loop in source frames for `rate`: {start, end, loop_start, loop_end}.
func frames_at(rate: int, total: int) -> Dictionary:
	var a := clampi(roundi(start_s * rate), 0, total)
	var b := clampi(roundi(end_s * rate), a, total) if end_s > 0.0 else total
	var ls := clampi(roundi(loop_start_s * rate), 0, b - a)
	var le := clampi(roundi(loop_end_s * rate), ls, b - a) if loop_end_s > 0.0 else b - a
	return {start = a, end = b, loop_start = ls, loop_end = le}


## The root note's pitch in Hz.
func root_hz() -> float:
	return 440.0 * pow(2.0, (root_note - 69.0) / 12.0)


## Everything that changes how it sounds, for bake keys: the settings and
## the sound itself (a recipe's bake key, or a hash of the data).
func describe() -> Dictionary:
	var r := source_recipe()
	var what: Variant
	if r:
		what = {recipe = AK.bake_key(r)}
	else:
		if _data_key == "" or data.is_empty():
			_ensure_data()
			_data_key = _hash(data) if data_r.is_empty() else _hash(data) + ":" + _hash(data_r)
		what = {data = _data_key, rate = data_rate}
	return {sound = what, root_note = root_note, start_s = start_s, end_s = end_s, mode = mode,
		loop_start_s = loop_start_s, loop_end_s = loop_end_s, release_s = release_s, gain_db = gain_db, reverse = reverse}


static func _hash(d: PackedFloat32Array) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(d.to_byte_array())
	return ctx.finish().hex_encode()


## A recipe playing this sample through the `sample` voice at its root
## pitch, velocity from intensity: what loops and kits use.
func to_recipe(semitones := 0.0, p_gain_db := 0.0, p_pan := 0.0) -> AKRecipe:
	var r := AKRecipe.new()
	r.voice = &"sample"
	r.params = {sample = self, freq_hz = root_hz() * pow(2.0, semitones / 12.0)}
	r.bind = {intensity = {velocity = [0.0, 1.0]}}
	r.gain_db = p_gain_db
	r.pan = p_pan
	return r


## A sample made from a recipe.
static func from_recipe(p_recipe: AKRecipe, p_root_note := 60.0, p_mode := "oneshot") -> AKSample:
	var s := AKSample.new()
	s.recipe = p_recipe
	s.root_note = p_root_note
	s.mode = p_mode
	return s


## What the `sample` voice plays with no sample given: a soft mallet at C4.
static func default_sample() -> AKSample:
	var r := AKRecipe.make(&"mallet", {freq_hz = 261.63, material = &"bar", decay_s = 0.5, hardness = 0.5})
	r.gain_db = -3.0
	return from_recipe(r, 60.0)
