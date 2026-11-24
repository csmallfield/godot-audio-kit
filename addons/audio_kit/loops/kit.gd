# SPDX-License-Identifier: Apache-2.0
@tool
## A drum kit: the instrument of a percussive loop, one row per piece.
##
##   pieces = [
##     {name = "kick", sound = "res://addons/audio_kit/library/kicks/kick_round.tres"},
##     {name = "closed_hat", sound = closed_hat_sample, gain_db = -4.0, choke = "hats"},
##     {name = "open_hat", sound = open_hat_sample, pan = 0.2, choke = "hats", gate = true},
##   ]
##
## Piece keys: name, sound (an AKSample, an AKRecipe, or a res:// path to
## either), gain_db, pan (-1..1), tune_semitones, choke (a group name: a hit
## cuts every piece of its group still ringing, itself included, as a closed
## hat stops an open one; "" = none), gate (true: the piece stops at the
## note's end, with the sample's release; false: it plays out, the usual
## drum behaviour). Every piece plays through the `sample` voice, so a
## recipe sound is rendered once and tuned by resampling.
##
## A sound recorded at several strengths, or several times, plays as one
## piece:
##
##     {name = "snare", layers = [
##         {sound = snare_soft, up_to = 0.35},
##         {sound = snare_mid, up_to = 0.7},
##         {sound = [snare_hard_a, snare_hard_b, snare_hard_c], up_to = 1.0}]}
##     {name = "ride", sound = [ride_1, ride_2]}
##
## `layers`: velocity layers, each a `sound` (or an array of alternate takes)
## and `up_to`, the highest velocity it plays (the top layer also takes
## anything above). `sound` as an array: alternate takes cycled hit by hit
## (round-robin). Velocity still scales each take's level.
@icon("res://addons/audio_kit/icons/palette.svg")
class_name AKKit
extends Resource

@export var pieces: Array[Dictionary] = []
## For the library browser (boom, punch, room, lo-fi, electro, or anything).
@export var category := ""

var _recipes := {}
## Samples made by from_dict, by absolute path: kits that share a sound share its decode.
static var _file_samples := {}


## A kit from a drum library kit file (tools/drum_prep/build_kits.py): JSON whose pieces name
## their sounds by path inside the collection, and whose `root` is the collection relative to
## the file ("../.."). The samples decode from the WAVs on first play, so the files must stay
## where they are; copy a kit into the project to ship it.
static func load_json(path: String) -> AKKit:
	var text := FileAccess.get_file_as_string(path)
	var d: Variant = JSON.parse_string(text) if text != "" else null
	if not d is Dictionary:
		push_error("AKKit: %s is not a kit file" % path)
		return null
	var root := path.get_base_dir().path_join(String(d.get("root", "."))).simplify_path()
	return from_dict(d, root)


## A kit from a kit file's dictionary, its sound paths relative to `root`. Keys other than
## the piece keys (category, kind, sure ...) are kept on the pieces as they are.
static func from_dict(d: Dictionary, root: String) -> AKKit:
	var k := AKKit.new()
	k.resource_name = String(d.get("name", ""))
	k.category = String(d.get("machine", d.get("category", "")))
	for p: Dictionary in d.get("pieces", []):
		var q := p.duplicate(true)
		if q.has("sound"):
			q["sound"] = _file_sample(root, q["sound"])
		if q.has("layers"):
			var layers := []
			for l: Dictionary in q["layers"]:
				var takes: Variant = l.get("sound")
				if takes is Array:
					var arr := []
					for t: Variant in takes:
						arr.append(_file_sample(root, t))
					takes = arr
				else:
					takes = _file_sample(root, takes)
				layers.append({sound = takes, up_to = float(l.get("up_to", 1.0))})
			q["layers"] = layers
		k.pieces.append(q)
	return k


static func _file_sample(root: String, v: Variant) -> Variant:
	if not (v is String or v is StringName):
		return v
	var rel := String(v)
	if rel.begins_with("res://") or rel.begins_with("user://"):
		return rel
	var full := root.path_join(rel)
	if not _file_samples.has(full):
		var s := AKSample.new()
		s.source = full
		s.resource_name = rel.get_file().get_basename()
		_file_samples[full] = s
	return _file_samples[full]


func piece_count() -> int:
	return pieces.size()


func piece_name(i: int) -> String:
	return String(pieces[i].get("name", "piece%d" % i)) if i >= 0 and i < pieces.size() else ""


## Index of the piece called `piece`, or -1.
func find_piece(piece: String) -> int:
	for i in pieces.size():
		if piece_name(i) == piece:
			return i
	return -1


## Choke group of piece `i` ("" = none).
func choke_of(i: int) -> String:
	return String(pieces[i].get("choke", "")) if i >= 0 and i < pieces.size() else ""


func is_gated(i: int) -> bool:
	return bool(pieces[i].get("gate", false)) if i >= 0 and i < pieces.size() else false


## The AKSample piece `i` plays (a recipe sound is wrapped in one): with
## layers or takes, the top layer's first take, which also sets the pitch
## the others follow.
func piece_sample(i: int) -> AKSample:
	var ls := piece_layers(i)
	if ls.is_empty():
		push_error("AKKit: piece '%s' has no sound" % piece_name(i))
		return null
	return (ls[ls.size() - 1].takes as Array)[0]


## Piece `i`'s velocity layers, softest first: [{up_to, takes = [AKSample]}];
## a plain piece is one layer of one take. Takes that don't load are left
## out, and layers left with none.
func piece_layers(i: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if i < 0 or i >= pieces.size():
		return out
	var p: Dictionary = pieces[i]
	var given: Variant = p.get("layers", [])
	if given is Array and not (given as Array).is_empty():
		for l: Variant in given:
			if not l is Dictionary:
				continue
			var takes := _takes((l as Dictionary).get("sound"), i)
			if not takes.is_empty():
				out.append({up_to = clampf(float((l as Dictionary).get("up_to", 1.0)), 0.0, 1.0), takes = takes})
		out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.up_to) < float(b.up_to))
	else:
		var takes := _takes(p.get("sound"), i)
		if not takes.is_empty():
			out.append({up_to = 1.0, takes = takes})
	return out


## Every sample piece `i` can play, layer by layer.
func piece_take_count(i: int) -> int:
	var n := 0
	for l in piece_layers(i):
		n += (l.takes as Array).size()
	return n


func _takes(v: Variant, i: int) -> Array:
	var out := []
	if v is Array:
		for x: Variant in v:
			var s := _one(x, i)
			if s:
				out.append(s)
	else:
		var s := _one(v, i)
		if s:
			out.append(s)
	return out


func _one(snd: Variant, i: int) -> AKSample:
	if (snd is String or snd is StringName) and ResourceLoader.exists(String(snd)):
		snd = load(String(snd))
	if snd is AKSample:
		return snd
	if snd is AKRecipe:
		return AKSample.from_recipe(snd, 60.0, "gate" if is_gated(i) else "oneshot")
	return null


## The recipe piece `i` plays: the `sample` voice at the piece's tuning,
## level and pan, velocity from intensity (and picking the layer), the
## recipe's round_robin cycling the takes. Made once and kept.
func piece_recipe(i: int) -> AKRecipe:
	if _recipes.has(i):
		return _recipes[i]
	var ls := piece_layers(i)
	if ls.is_empty():
		push_error("AKKit: piece '%s' has no sound" % piece_name(i))
		return null
	var p: Dictionary = pieces[i]
	var gated := is_gated(i)
	var top: Array = ls[ls.size() - 1].takes
	var s: AKSample = top[0]
	var r := s.to_recipe(float(p.get("tune_semitones", 0.0)), float(p.get("gain_db", 0.0)), float(p.get("pan", 0.0)))
	r.params["sample"] = _gate(s, gated)
	if ls.size() == 1 and top.size() > 1:
		var takes := []
		for t: AKSample in top:
			takes.append(_gate(t, gated))
		r.params["sample"] = takes
	elif ls.size() > 1:
		var layers := []
		for l in ls:
			var takes := []
			for t: AKSample in l.takes:
				takes.append(_gate(t, gated))
			layers.append({sample = takes if takes.size() > 1 else takes[0], up_to = float(l.up_to)})
		r.params["layers"] = layers
	var cycle := 1
	for l in ls:
		var n := (l.takes as Array).size()
		cycle = mini(64, cycle * n / _gcd(cycle, n))
	if cycle > 1:
		r.round_robin = cycle
	_recipes[i] = r
	return r


## A gated piece's one-shot take plays as `gate` (stops at the note's end).
func _gate(s: AKSample, gated: bool) -> AKSample:
	if gated and s.mode == "oneshot":
		var g: AKSample = s.duplicate()
		g.mode = "gate"
		return g
	return s


static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t := a % b
		a = b
		b = t
	return maxi(a, 1)


## Forget the cached piece recipes (after editing `pieces` in code).
func refresh() -> void:
	_recipes.clear()
	emit_changed()


func describe() -> Dictionary:
	var out := []
	for i in pieces.size():
		var s := piece_sample(i)
		var p: Dictionary = pieces[i]
		var d := {name = piece_name(i), sound = s.describe() if s else null, gain_db = float(p.get("gain_db", 0.0)),
			pan = float(p.get("pan", 0.0)), tune = float(p.get("tune_semitones", 0.0)), choke = choke_of(i), gate = is_gated(i)}
		var ls := piece_layers(i)
		if ls.size() > 1 or (ls.size() == 1 and (ls[0].takes as Array).size() > 1):
			var lay := []
			for l in ls:
				var takes := []
				for t: AKSample in l.takes:
					takes.append(t.describe())
				lay.append({up_to = l.up_to, takes = takes})
			d.layers = lay
		out.append(d)
	return {pieces = out}
