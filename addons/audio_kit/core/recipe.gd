# SPDX-License-Identifier: Apache-2.0
@tool
## A sound as data: one or more voice layers, an effects chain, transforms,
## a seed, and the rules that map a cue's intensity and data onto parameters.
## Recipes are the authored asset; WAVs are build products (`AK.bake`).
##
##   voice = &"boing"
##   params = {start_hz = 220.0, decay_s = 0.35, sub = 0.6}
##   layers = [{voice = &"click", params = {freq_hz = 4000.0}, gain_db = -6.0}]
##   fx = [{type = &"lowpass", cutoff_hz = 6000.0}, {type = &"room", room = 0.3, mix = 0.15}]
##   bind = {intensity = {gain_db = [-12.0, 0.0]}, "data.pitch": &"pitch_scale"}
##
## Any parameter value written as "$name" is read from the palette.
@icon("res://addons/audio_kit/icons/recipe.svg")
class_name AKRecipe
extends Resource

## Main voice (a file in addons/audio_kit/voices/, or one registered with
## `AK.register_voice`). Leave empty to use `layers` only.
@export var voice: StringName
## Parameters for the main voice; unset ones take the voice's defaults.
@export var params: Dictionary = {}
## Extra layers summed with the main voice: {voice, params, gain_db, offset_s, pan}.
@export var layers: Array[Dictionary] = []
## Effects applied in order to the summed stereo signal: {type, ...}. Types:
## lowpass, highpass, bandpass, notch (cutoff_hz, q, slope_db 12 or 24), lowpass1 / highpass1
## (cutoff_hz), drive (amount), bitcrush (bits, hold), room (room, damp, mix,
## width, tail_s, quality small|full), echo (time_s, feedback, mix, tail_s), gain (db),
## limit (ceiling_db, release_s), normalize (peak_db), loudness (target_lufs),
## dcblock (cutoff_hz, default 10).
@export var fx: Array[Dictionary] = []
## Applied after the effects: {type, ...}. Types: reverse, fade (in_s, out_s),
## varispeed (from, to: playback rate ramp, e.g. 1 -> 0 is a tape stop),
## width (amount: 0 mono, 1 as is, 2 wider), trim (length_s).
@export var transforms: Array[Dictionary] = []
## How a cue drives parameters. `intensity` maps names to [at 0, at 1]
## ranges; "data.<key>" copies a cue data value onto a name. Names can be
## gain_db, pan, pitch_scale (multiplies every *_hz), a voice parameter, or an
## effect parameter.
@export var bind: Dictionary = {}
## Seeded per-hit variation: parameter -> relative spread (0.05 = up to ±5%).
## When set, every hit of the cue renders differently but repeatably.
@export var vary: Dictionary = {}
## With `vary`: how many distinct variants to cycle through (0 = a new one
## every hit). A few (3-6) still sound varied and render far less.
@export var vary_variants := 0
@export var seed := 0
@export var gain_db := 0.0
## How much of the sound feeds the cue map's shared reverb (0..1). Cheaper
## and more cohesive than a room effect on every recipe. Bindable as "send".
@export_range(0.0, 1.0) var send := 0.0
## Stereo balance of the whole sound, -1 left to 1 right.
@export_range(-1.0, 1.0) var pan := 0.0
## Where the sound starts relative to its cue, in seconds. Negative = before
## (a whoosh that builds into the hit on the cue).
@export var offset_s := 0.0
## Palette for "$name" values; empty uses `AK.palette`.
@export var palette: AKPalette


## A plain dictionary of everything that affects the sound (for hashing).
func describe() -> Dictionary:
	return {voice = voice, params = params, layers = layers, fx = fx, transforms = transforms,
		bind = bind, vary = vary, vary_variants = vary_variants, seed = seed, gain_db = gain_db, pan = pan, send = send}


## Build a recipe in code: `AKRecipe.make(&"tone", {freq_hz = 660.0})`.
static func make(p_voice: StringName, p_params := {}, p_fx: Array[Dictionary] = []) -> AKRecipe:
	var r := AKRecipe.new()
	r.voice = p_voice
	r.params = p_params
	r.fx = p_fx
	return r
