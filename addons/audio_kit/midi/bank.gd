# SPDX-License-Identifier: Apache-2.0
@tool
## Which sounds MIDI programs and drum notes play: a patch per General MIDI
## family (16 of them, programs 0-127 in eights), optional per-program
## patches, and a recipe per drum note on channel 10.
##
##   var bank: AKBank = load("res://addons/audio_kit/bank/gm_bank.tres")
##   bank.patch_for(33)        # an AKPatch for program 33 (fingered bass: the bass family)
##   bank.drum_for(38)         # {lane = "snare", recipe = "res://…snare.tres"}
##
## The shipped bank (`AKGeneralMidi.DEFAULT_BANK`) is original, synthesised,
## "sketch quality": recognisable families, not a sampled GM set. Make your
## own by copying it and pointing entries at your patches.
@icon("res://addons/audio_kit/icons/palette.svg")
class_name AKBank
extends Resource

## 16 AKPatch paths (or patches), one per GM family, in family order.
@export var families: Array = []
## Program number (0-127) -> AKPatch path (or patch), overriding its family.
@export var programs: Dictionary = {}
## GM drum note (35-81) -> {lane, recipe (AKRecipe path or recipe)}.
@export var drums: Dictionary = {}
## The drum lane and recipe for notes `drums` doesn't list.
@export var drum_default: Dictionary = {}


## The patch for `program` (0-127): its own entry, else its family's.
func patch_for(program: int) -> AKPatch:
	var p := clampi(program, 0, 127)
	var v: Variant = programs.get(p, programs.get(str(p)))
	if v == null and families.size() > p / 8:
		v = families[p / 8]
	return _patch(v)


## The path or patch entry `patch_for` would use (for writing songs that
## reference the bank's files rather than copies).
func patch_ref_for(program: int) -> Variant:
	var p := clampi(program, 0, 127)
	var v: Variant = programs.get(p, programs.get(str(p)))
	if v == null and families.size() > p / 8:
		v = families[p / 8]
	return v


## {lane, recipe} for a drum note on channel 10.
func drum_for(note: int) -> Dictionary:
	var d: Variant = drums.get(note, drums.get(str(note)))
	if d == null:
		d = drum_default
	return d if d is Dictionary else {}


static func _patch(v: Variant) -> AKPatch:
	if v is AKPatch:
		return v
	if (v is String or v is StringName) and ResourceLoader.exists(String(v)):
		var r: Resource = load(String(v))
		if r is AKPatch:
			return r
	return null
