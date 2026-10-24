# SPDX-License-Identifier: Apache-2.0
@tool
## A recipe as a Godot `AudioStream`: put it in any AudioStreamPlayer (2D,
## 3D), an AudioStreamRandomizer, an AnimationPlayer audio track.
##
##   var s := AKRecipeStream.new()
##   s.recipe = load("res://sfx/jump.tres")
##   $Player.stream = s
##   $Player.play()          # renders on first use, then plays from the cache
##
## Each play renders through `AK.bake` (deterministic, cached by content
## hash), so the first play of a variant pays its render (a few ms with the
## native core, more in GDScript) and later plays are free. `warm()` renders
## them all up front. With `vary_per_play` each play picks another of
## `variants` variants of the recipe's `vary` spread. Works without the
## native core and in exported games.
##
## "Bake to WAV" in the inspector writes the sound to a WAV beside this
## resource (or to `wav_path`), which Godot imports as an AudioStreamWAV.
@icon("res://addons/audio_kit/icons/recipe.svg")
class_name AKRecipeStream
extends AudioStream

## The sound.
@export var recipe: AKRecipe:
	set(v):
		if recipe and recipe.changed.is_connected(emit_changed):
			recipe.changed.disconnect(emit_changed)
		recipe = v
		if recipe:
			recipe.changed.connect(emit_changed)
		emit_changed()
## Drives the recipe's `bind` intensity rules.
@export_range(0.0, 1.0) var intensity := 1.0
## Cue data for the recipe's "data.<key>" bind rules.
@export var data := {}
## Pick a different variant on each play (only changes anything when the
## recipe has `vary`).
@export var vary_per_play := true
## How many distinct variants to cycle among. Each is rendered once and
## cached, so a few keep memory and render time down.
@export_range(1, 32) var variants := 4
## Where "Bake to WAV" writes; empty = beside this resource (or under
## res://audio_kit/sfx/ for an unsaved one).
@export_file("*.wav") var wav_path := ""
@export_tool_button("Bake to WAV", "Save") var bake_button := bake_wav

## The variant the last play used.
var last_variant := -1
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


## Build one in code.
static func of(p_recipe: AKRecipe, p_vary := true, p_variants := 4) -> AKRecipeStream:
	var s := AKRecipeStream.new()
	s.recipe = p_recipe
	s.vary_per_play = p_vary
	s.variants = p_variants
	return s


func _instantiate_playback() -> AudioStreamPlayback:
	var wav := stream_for(next_variant())
	return wav.instantiate_playback() if wav else null


func _get_stream_name() -> String:
	if recipe == null:
		return "AKRecipeStream (empty)"
	return recipe.resource_name if recipe.resource_name != "" else recipe.resource_path.get_file()


func _get_length() -> float:
	var wav := stream_for(0)
	return wav.get_length() if wav else 0.0


func _is_monophonic() -> bool:
	return false


## The baked sound of variant `v` (cached).
func stream_for(v: int) -> AudioStreamWAV:
	if recipe == null:
		return null
	return AK.bake(recipe, intensity, data, clampi(v, 0, maxi(1, variants) - 1))


## The variant the next play uses, and remember it as last_variant.
func next_variant() -> int:
	var n := maxi(1, variants)
	if not vary_per_play or n == 1 or recipe == null or recipe.vary.is_empty():
		last_variant = 0
		return 0
	var v := _rng.randi_range(0, n - 1)
	if v == last_variant:
		v = (v + 1 + _rng.randi_range(0, n - 2)) % n
	last_variant = v
	return v


## Render every variant now so no play waits for one.
func warm() -> void:
	for v in maxi(1, variants) if vary_per_play else 1:
		stream_for(v)


## Where bake_wav() writes by default.
func default_wav_path() -> String:
	if wav_path != "":
		return wav_path
	if resource_path != "" and not resource_path.contains("::"):
		return resource_path.get_basename() + ".wav"
	var base := recipe.resource_path.get_file().get_basename() if recipe and recipe.resource_path != "" else "sound"
	return "res://audio_kit/sfx/%s.wav" % base


## Write variant `variant` as a 16-bit WAV (the same samples a play gives)
## and return its path, or "" on failure. In the editor the file panel is
## rescanned so it imports as an AudioStreamWAV.
func bake_wav(path := "", variant := 0) -> String:
	if recipe == null:
		push_error("AKRecipeStream: no recipe to bake")
		return ""
	var p := path if path != "" else default_wav_path()
	return p if AK.bake_wav(recipe, p, intensity, data, variant) == OK else ""
