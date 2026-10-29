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
@icon("res://addons/audio_kit/icons/palette.svg")
class_name AKKit
extends Resource

@export var pieces: Array[Dictionary] = []
## For the library browser (boom, punch, room, lo-fi, electro, or anything).
@export var category := ""

var _recipes := {}


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


## The AKSample piece `i` plays (a recipe sound is wrapped in one).
func piece_sample(i: int) -> AKSample:
	var p: Dictionary = pieces[i]
	var snd: Variant = p.get("sound")
	if (snd is String or snd is StringName) and ResourceLoader.exists(String(snd)):
		snd = load(String(snd))
	var s: AKSample = null
	if snd is AKSample:
		s = snd
	elif snd is AKRecipe:
		s = AKSample.from_recipe(snd, 60.0, "gate" if is_gated(i) else "oneshot")
	if s == null:
		push_error("AKKit: piece '%s' has no sound" % piece_name(i))
	return s


## The recipe piece `i` plays: the `sample` voice at the piece's tuning,
## level and pan, velocity from intensity. Made once and kept.
func piece_recipe(i: int) -> AKRecipe:
	if _recipes.has(i):
		return _recipes[i]
	var s := piece_sample(i)
	if s == null:
		return null
	var p: Dictionary = pieces[i]
	var r := s.to_recipe(float(p.get("tune_semitones", 0.0)), float(p.get("gain_db", 0.0)), float(p.get("pan", 0.0)))
	if is_gated(i) and s.mode == "oneshot":
		var g: AKSample = s.duplicate()
		g.mode = "gate"
		r.params["sample"] = g
	_recipes[i] = r
	return r


## Forget the cached piece recipes (after editing `pieces` in code).
func refresh() -> void:
	_recipes.clear()
	emit_changed()


func describe() -> Dictionary:
	var out := []
	for i in pieces.size():
		var s := piece_sample(i)
		var p: Dictionary = pieces[i]
		out.append({name = piece_name(i), sound = s.describe() if s else null, gain_db = float(p.get("gain_db", 0.0)),
			pan = float(p.get("pan", 0.0)), tune = float(p.get("tune_semitones", 0.0)), choke = choke_of(i), gate = is_gated(i)})
	return {pieces = out}
