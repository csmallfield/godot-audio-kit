# SPDX-License-Identifier: Apache-2.0
## Cue names to recipes, matched like the motion kit's MotionCuePlayer: the
## exact name, then the longest matching `prefix*`, then `*`.
@icon("res://addons/audio_kit/icons/recipe.svg")
class_name AKCueMap
extends Resource

## Cue name or pattern -> AKRecipe.
@export var sounds: Dictionary = {}
## Effects on the final mix (same types as AKRecipe.fx). The default sets the
## loudness, then limits 1.5 dB under full scale so inter-sample peaks stay
## below -1 dBTP.
@export var master_fx: Array[Dictionary] = [{type = &"loudness", target_lufs = -16.0}, {type = &"limit", ceiling_db = -1.5}]


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
