# SPDX-License-Identifier: Apache-2.0
@tool
## Base class for voices: a voice turns resolved parameters into a mono
## signal. Sample 0 is where its cue lands (no lead-in silence).
##
## A voice declares its parameters in `schema()`: name -> {default, min, max,
## unit, doc}. Names carry their unit (`_hz`, `_s`, `_db`, `_semitones`,
## `_ratio`); unitless 0..1 controls have no suffix. The schema fills
## defaults, drives the inspector and generates the skill file's tables.
##
## Bump `version()` whenever a change alters the sound: it invalidates cached
## bakes of every recipe that uses the voice.
class_name AKVoice
extends RefCounted


func version() -> int:
	return 1


func doc() -> String:
	return ""


func schema() -> Dictionary:
	return {}


## Parameters arrive complete (defaults filled, bindings applied).
func render(_p: Dictionary, _sample_rate: int, _rng: RandomNumberGenerator) -> PackedFloat32Array:
	return PackedFloat32Array()


## Parameters that carry the voice's pitch; the first is the reference the
## sequencer retunes from. Default: freq_hz when the voice has one.
func pitch_params() -> PackedStringArray:
	return PackedStringArray(["freq_hz"]) if schema().has("freq_hz") else PackedStringArray()


func defaults() -> Dictionary:
	var d := {}
	var s := schema()
	for k in s:
		d[k] = s[k].default
	return d


## Shorthand for schema entries.
static func param(default: Variant, min_v: Variant = null, max_v: Variant = null, doc_text := "") -> Dictionary:
	return {default = default, min = min_v, max = max_v, doc = doc_text}
