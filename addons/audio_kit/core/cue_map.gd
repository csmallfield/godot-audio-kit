# SPDX-License-Identifier: Apache-2.0
@tool
## Cue names to recipes, matched like the motion kit's MotionCuePlayer: the
## exact name, then the longest matching `prefix*`, then `*`.
@icon("res://addons/audio_kit/icons/recipe.svg")
class_name AKCueMap
extends Resource

## Cue name or pattern -> AKRecipe.
@export var sounds: Dictionary = {}
## Effects on the final mix (same types as AKRecipe.fx). The default removes
## DC offset, sets the loudness, then limits 1.5 dB under full scale so
## inter-sample peaks stay below -1 dBTP.
@export var master_fx: Array[Dictionary] = [{type = &"dcblock"}, {type = &"loudness", target_lufs = -16.0}, {type = &"limit", ceiling_db = -1.5}]

## The shared reverb that recipes feed through their `send`: room, damp,
## width, quality (small|full), tail_s, and return_db (wet level in the mix).
@export var reverb: Dictionary = {room = 0.5, damp = 0.5, width = 1.0, quality = &"full", return_db = 0.0}
## Fit to the picture: when above 0 and the render has a length, the mix
## fades out over this many seconds before the last frame and stops there,
## so the piece cuts clean. 0 lets tails ring past the end.
@export var end_fade_s := 0.0
## Music ducks under the effects (sidechain): depth_db (0 = off), full_at_db
## (effects level, dBFS, at which the full depth applies; quieter hits duck
## proportionally less), attack_s, release_s. Ducks the music's dry signal;
## its reverb send is left alone so tails don't pump.
@export var duck: Dictionary = {}


## The duck settings with defaults filled in, or {} when ducking is off.
func duck_settings() -> Dictionary:
	if float(duck.get("depth_db", 0.0)) <= 0.0:
		return {}
	return {depth_db = float(duck.depth_db), full_at_db = float(duck.get("full_at_db", -24.0)),
		attack_s = float(duck.get("attack_s", 0.01)), release_s = float(duck.get("release_s", 0.3))}


func recipe_for(cue_name: StringName) -> AKRecipe:
	if sounds.has(cue_name):
		return sounds[cue_name]
	var n := String(cue_name)
	if sounds.has(n):
		return sounds[n]
	var best: AKRecipe = null
	var best_len := -1
	for k in sounds:
		var ks := String(k)
		if ks.ends_with("*") and ks != "*":
			var prefix := ks.left(-1)
			if n.begins_with(prefix) and prefix.length() > best_len:
				best = sounds[k]
				best_len = prefix.length()
	if best:
		return best
	if sounds.has("*"):
		return sounds["*"]
	if sounds.has(&"*"):
		return sounds[&"*"]
	return null
