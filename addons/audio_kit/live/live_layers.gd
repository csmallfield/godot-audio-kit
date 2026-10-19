# SPDX-License-Identifier: Apache-2.0
## Several recipe loops crossfaded by one value: an engine with loops at a
## few rpm points, wind at a few speeds, a crowd at a few sizes. Each layer
## is loudest at its `at` value and is pitched by value / at (so a loop made
## at 3000 rpm plays at 1.5x speed at 4500 rpm); between two layers the
## crossfade is equal power on a log scale.
##
##   layers = [{recipe = idle, at = 900.0}, {recipe = mid, at = 3000.0}, {recipe = high, at = 6500.0}]
##
## Bind `value` to game state like an AKLiveVoice binding, or set it from
## code. Gain, filter, send and spatial settings apply to every layer.
@icon("res://addons/audio_kit/icons/recipe.svg")
class_name AKLiveLayers
extends Node

@export var live_player: AKLivePlayer
## {recipe: AKRecipe, at: float, gain_db (optional)} per layer.
@export var layers: Array[Dictionary] = []
## The control value (rpm, speed...).
@export var value := 1000.0
## Read `value` from here every frame (empty node = don't).
@export var value_node: NodePath
@export var value_property := ""
## Smoothing for value changes (seconds).
@export var glide_s := 0.08
## Each layer's rate is kept inside this range (value / at, clamped).
@export var rate_range := Vector2(0.5, 2.0)
@export_range(0.0, 1.0) var gain := 0.4
@export var cutoff_hz := 0.0
@export var q := 0.707
@export_range(0.0, 1.0) var send := 0.0
@export var loop_xfade_s := 0.12
@export var attack_s := 0.3
@export var release_s := 0.4
@export var autostart := true
@export_group("Spatial")
@export_enum("off", "on") var spatial := "off"
@export var unit_size := 100.0
@export var max_distance := 2000.0
@export_enum("inverse", "inverse_square", "linear") var attenuation := "inverse"
@export_range(0.0, 1.0) var air_absorption := 0.0
@export_range(0.0, 2.0) var doppler := 0.0
@export var speed_of_sound := 343.0
@export var occlusion := false
@export_flags_2d_physics var occlusion_mask := 1
@export var occlusion_db := -12.0
@export_range(0.01, 1.0) var occlusion_lowpass := 0.2
@export_group("")

var _voices: Array[AKLiveVoice] = []


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if autostart:
		start.call_deferred()


func start() -> void:
	if not _voices.is_empty():
		return
	var lp := live_player if live_player else AKLivePlayer.find(self)
	for l: Dictionary in _sorted():
		var v := AKLiveVoice.new()
		v.live_player = lp
		v.recipe = l.recipe
		v.loop_xfade_s = loop_xfade_s
		v.cutoff_hz = cutoff_hz
		v.q = q
		v.send = send
		v.attack_s = attack_s
		v.release_s = release_s
		v.spatial = spatial
		v.unit_size = unit_size
		v.max_distance = max_distance
		v.attenuation = attenuation
		v.air_absorption = air_absorption
		v.doppler = doppler
		v.speed_of_sound = speed_of_sound
		v.occlusion = occlusion
		v.occlusion_mask = occlusion_mask
		v.occlusion_db = occlusion_db
		v.occlusion_lowpass = occlusion_lowpass
		v.autostart = false
		v.set_meta(&"at", float(l.get("at", 1.0)))
		v.set_meta(&"gain", AKDsp.db_to_gain(float(l.get("gain_db", 0.0))))
		add_child(v)
		_voices.append(v)
	_apply(0.0, true)
	for v in _voices:
		v.start()


func stop(p_release_s := -1.0) -> void:
	for v in _voices:
		v.stop(p_release_s)
		v.queue_free()
	_voices.clear()


func _process(_delta: float) -> void:
	if _voices.is_empty():
		return
	if not value_node.is_empty() and value_property != "":
		var n := get_node_or_null(value_node)
		if n:
			var x: Variant = n.get_indexed(NodePath(value_property))
			value = x.length() if (x is Vector2 or x is Vector3) else float(x)
	_apply(glide_s)


## Each layer's {gain, rate} at `x` (layers sorted by `at`).
static func weights(ats: Array, x: float, rate_range := Vector2(0.5, 2.0)) -> Array:
	var out := []
	var n := ats.size()
	for i in n:
		out.append({gain = 0.0, rate = clampf(x / maxf(1e-6, float(ats[i])), rate_range.x, rate_range.y)})
	if n == 0:
		return out
	if x <= float(ats[0]):
		out[0].gain = 1.0
	elif x >= float(ats[n - 1]):
		out[n - 1].gain = 1.0
	else:
		for i in n - 1:
			var a := float(ats[i])
			var b := float(ats[i + 1])
			if x >= a and x <= b:
				var t := log(maxf(x, 1e-6) / a) / log(b / a) if b > a else 0.0
				out[i].gain = cos(t * PI * 0.5)
				out[i + 1].gain = sin(t * PI * 0.5)
				break
	return out


func _apply(glide: float, init := false) -> void:
	var ats := []
	for v in _voices:
		ats.append(v.get_meta(&"at"))
	var w := weights(ats, value, rate_range)
	for i in _voices.size():
		var v := _voices[i]
		var g := gain * float(v.get_meta(&"gain")) * float(w[i].gain)
		if init:
			v.gain = g
			v.rate = float(w[i].rate)
		else:
			v.set_param("gain", g, glide)
			v.set_param("rate", float(w[i].rate), glide)


func _sorted() -> Array:
	var ls := layers.filter(func(l: Dictionary) -> bool: return l.get("recipe") is AKRecipe)
	ls.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("at", 0.0)) < float(b.get("at", 0.0)))
	return ls
