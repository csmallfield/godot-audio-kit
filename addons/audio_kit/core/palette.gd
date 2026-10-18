# SPDX-License-Identifier: Apache-2.0
## A sound family's character as named values. Recipes write "$room" or
## "$root_hz" where a value should come from the palette, so swapping the
## palette restyles every recipe that uses it.
@icon("res://addons/audio_kit/icons/palette.svg")
class_name AKPalette
extends Resource

@export var description := ""
## Token name (without the $) -> value.
@export var tokens: Dictionary = {}


func lookup(token: String) -> Variant:
	var key := token.trim_prefix("$")
	if tokens.has(key):
		return tokens[key]
	if tokens.has(StringName(key)):
		return tokens[StringName(key)]
	push_error("AKPalette: no token '%s'" % key)
	return null
