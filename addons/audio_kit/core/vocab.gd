# SPDX-License-Identifier: Apache-2.0
## Words to parameter moves, so notes like "a bit brighter and drier" become
## the same change every time:
##
##   var r2 := AKVocab.apply(recipe, ["brighter", "drier"])        # a new recipe
##   var r3 := AKVocab.apply(recipe, ["punchier"], 0.5)            # half a step
##
## The words live in addons/audio_kit/vocabulary.json. Targets name voice
## parameters (in the main voice and every layer), recipe fields (gain_db,
## send), effect parameters as "fx.<type>.<param>", and "vary.*".
class_name AKVocab
extends RefCounted

const PATH := "res://addons/audio_kit/vocabulary.json"
static var _words := {}

const UNIT_CONTROLS := ["brightness", "hardness", "click", "sub", "send", "jitter", "mix", "amount", "sustain"]


static func words() -> Dictionary:
	if _words.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if d is Dictionary:
			for k in d:
				if not String(k).begins_with("_"):
					_words[String(k)] = d[k]
	return _words


## A copy of `recipe` with `moves` applied, scaled by `amount`.
static func apply(recipe: AKRecipe, moves: Array, amount := 1.0) -> AKRecipe:
	var r: AKRecipe = recipe.duplicate()
	r.params = recipe.params.duplicate(true)
	var layers: Array[Dictionary] = []
	for l in recipe.layers:
		layers.append(l.duplicate(true))
	r.layers = layers
	var fx: Array[Dictionary] = []
	for e in recipe.fx:
		fx.append(e.duplicate(true))
	r.fx = fx
	r.vary = recipe.vary.duplicate(true)
	var all := words()
	for w in moves:
		var key := String(w).to_lower()
		if not all.has(key):
			push_warning("AKVocab: unknown word '%s'" % w)
			continue
		for m: Dictionary in all[key]:
			_move(r, m, amount)
	return r


static func _move(r: AKRecipe, m: Dictionary, amount: float) -> void:
	match String(m.get("op", "")):
		"ensure_fx":
			var e: Dictionary = m.fx
			for x in r.fx:
				if String(x.get("type", "")) == String(e.type):
					return
			r.fx.append(e.duplicate(true))
		"remove_fx":
			var types: Array = m.types
			var kept: Array[Dictionary] = []
			for x in r.fx:
				if not types.has(String(x.get("type", ""))):
					kept.append(x)
			r.fx = kept
		_:
			for t in m.get("targets", []):
				_apply_target(r, String(t), String(m.op), m.get("value"), amount)


static func _apply_target(r: AKRecipe, t: String, op: String, v: Variant, amount: float) -> void:
	if t == "gain_db":
		r.gain_db = _op(r.gain_db, op, v, amount, t, true)
	elif t == "send":
		r.send = clampf(_op(r.send, op, v, amount, t, false), 0.0, 1.0)
	elif t.begins_with("fx."):
		var parts := t.split(".")
		for e in r.fx:
			if String(e.get("type", "")) == parts[1] and e.has(parts[2]):
				e[parts[2]] = _op(e[parts[2]], op, v, amount, parts[2], false)
	elif t == "vary.*":
		for k in r.vary:
			r.vary[k] = _op(r.vary[k], op, v, amount, "vary", true)
	else:
		_param(r, r.params, r.voice, t, op, v, amount)
		for l in r.layers:
			if not l.has("params"):
				l["params"] = {}
			_param(r, l.params, StringName(l.get("voice", &"")), t, op, v, amount)


## Moves a voice parameter, filling in the voice default first so a move on
## an unset parameter starts from what the voice would have used.
static func _param(_r: AKRecipe, params: Dictionary, voice: StringName, t: String, op: String, v: Variant, amount: float) -> void:
	if voice == &"":
		return
	var vo := AK.voice(voice)
	if vo == null:
		return
	var schema := vo.schema()
	if not schema.has(t):
		return
	var cur: Variant = params.get(t, schema[t].default)
	if cur is String and String(cur).begins_with("$"):
		return   # palette-driven: leave the palette to decide
	var out: Variant = _op(cur, op, v, amount, t, false)
	if (out is float or out is int) and schema[t].get("min") != null:
		out = clampf(float(out), float(schema[t].min), float(schema[t].max))
	params[t] = out


static func _op(cur: Variant, op: String, v: Variant, amount: float, name: String, unbounded: bool) -> Variant:
	match op:
		"set":
			return StringName(v) if v is String else v
		"mul":
			return float(cur) * pow(float(v), amount)
		"add":
			var out := float(cur) + float(v) * amount
			if not unbounded and UNIT_CONTROLS.has(name):
				out = clampf(out, 0.0, 1.0)
			return out
	return cur
