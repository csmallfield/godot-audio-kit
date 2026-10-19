# SPDX-License-Identifier: Apache-2.0
## A continuous synth voice on an AKLivePlayer, driven by game state: an
## engine hum that follows speed, wind that follows height, a drone that
## follows a tension meter.
##
## Each binding reads a property (any node, any property path; vectors use
## their length) and maps it onto a voice parameter every frame:
##
##   {param = "freq_hz", node = ^"../Car", property = "speed",
##    from = [0.0, 60.0], to = [60.0, 240.0], curve = "exp", glide_s = 0.08}
##
## `curve`: "linear" (default) or "exp" (for pitch and cutoff: equal ratios
## per step). Values outside `from` are clamped.
@icon("res://addons/audio_kit/icons/recipe.svg")
class_name AKLiveVoice
extends Node

## The AKLivePlayer to play on. Empty: the nearest ancestor, else the first
## one in the scene.
@export var live_player: AKLivePlayer
## Loop this recipe instead of an oscillator (an engine, a wind bed, a
## crowd): rendered once, made seamless, played at `rate`.
@export var recipe: AKRecipe
## Loop crossfade (seconds).
@export var loop_xfade_s := 0.1
## Loop playback speed (1 = as rendered). Bind it to rpm, speed...
@export var rate := 1.0
@export_enum("sine", "saw", "square", "triangle", "noise") var shape := "saw"
@export var freq_hz := 110.0
@export_range(0.0, 1.0) var gain := 0.3
## Low-pass cutoff; 0 = unfiltered.
@export var cutoff_hz := 1200.0
@export var q := 0.9
@export_range(-1.0, 1.0) var pan := 0.0
@export_range(0.0, 1.0) var send := 0.0
## Pulse width (square).
@export_range(0.01, 0.99) var width := 0.5
## Noise mixed into the shape.
@export_range(0.0, 1.0) var noise := 0.0
@export var attack_s := 0.2
@export var release_s := 0.3
## Pan follows the parent's horizontal position on screen (a Node2D or
## Control parent). Ignored when `spatial` is on.
@export var pan_follows_parent := false
@export_group("Spatial")
## Position the sound at its parent (Node2D or Node3D) relative to the
## listener: distance sets the level (and air absorption the highs),
## direction the pan. See AKSpatial for the settings.
@export_enum("off", "on") var spatial := "off"
## Distance at which the level starts to fall (px in 2D, metres in 3D).
@export var unit_size := 100.0
## Silent from here (fades over the last 10%).
@export var max_distance := 2000.0
@export_enum("inverse", "inverse_square", "linear") var attenuation := "inverse"
## 0..1: how much distance dulls the sound.
@export_range(0.0, 1.0) var air_absorption := 0.0
## Doppler: 0 = off, 1 = physical. The pitch rises as the source approaches
## and falls as it recedes.
@export_range(0.0, 2.0) var doppler := 0.0
## Speed of sound in your units: 343 for metres; in 2D pick what feels right
## for your pixel scale (a few thousand px/s).
@export var speed_of_sound := 343.0
## Occlusion: when something on `occlusion_mask` lies between the listener
## and the source, it's turned down and muffled.
@export var occlusion := false
@export_flags_2d_physics var occlusion_mask := 1
@export var occlusion_db := -12.0
## Cutoff factor when fully occluded (0.2 = a fifth of the open cutoff).
@export_range(0.01, 1.0) var occlusion_lowpass := 0.2
## Seconds to fade between open and occluded.
@export var occlusion_fade_s := 0.15
@export_group("")
## Start when the scene starts.
@export var autostart := true
@export var bindings: Array[Dictionary] = []

var _id := -1
var _sp := {}
const _MIX := ["gain", "pan", "cutoff_hz", "pitch"]
var _last_dist := -1.0
var _last_t := 0.0
var _clock := 0.0
var _radial := 0.0
var _occluded := false
## 0 = open, 1 = fully occluded (eases between them).
var occlusion_amount := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if autostart:
		start.call_deferred()


func _exit_tree() -> void:
	stop()


func is_playing() -> bool:
	return _id >= 0


func start() -> void:
	if _id >= 0:
		return
	var lp := _player()
	if lp == null or not lp.setup():
		push_warning("AKLiveVoice %s: no AKLivePlayer to play on" % name)
		return
	_sp = _spatial()
	var p := {shape = shape, freq_hz = freq_hz, gain = _eff("gain"), cutoff_hz = _eff("cutoff_hz"), q = q, pan = _eff("pan"),
		send = send, width = width, noise = noise, attack_s = attack_s, rate = rate, seed = get_instance_id() & 0xffff}
	if recipe:
		_id = lp.live.loop_start(recipe, p, loop_xfade_s)
	else:
		_id = lp.live.voice_start(p)
	apply_bindings(0.0)


func stop(p_release_s := -1.0) -> void:
	if _id < 0:
		return
	var lp := _player()
	if lp and lp.live:
		lp.live.voice_stop(_id, release_s if p_release_s < 0.0 else p_release_s)
	_id = -1


## Glide one parameter (freq_hz, gain, cutoff_hz, q, pan, send, width,
## noise; rate for recipe loops).
func set_param(param: String, value: float, glide_s := 0.05) -> void:
	set(param, value)
	var lp := _player()
	if _id >= 0 and lp and lp.live:
		lp.live.voice_set(_id, param, _eff(param), glide_s)


## The value sent for `param`: gain, pan and cutoff pass through the spatial
## (or follow-the-parent) position.
func _eff(param: String) -> float:
	match param:
		"gain":
			return gain * float(_sp.get("gain", 1.0))
		"pan":
			return clampf(pan + float(_sp.pan), -1.0, 1.0) if _sp.has("pan") else pan
		"cutoff_hz":
			var scale := float(_sp.get("cutoff_scale", 1.0))
			if scale >= 0.999:
				return cutoff_hz
			return (cutoff_hz if cutoff_hz > 0.0 else 18000.0) * scale
		"pitch":
			return float(_sp.get("pitch", 1.0))
	return float(get(param))


func _spatial() -> Dictionary:
	var p := get_parent()
	if spatial == "on":
		var r := AKSpatial.for_node(p, {unit_size = unit_size, max_distance = max_distance, attenuation = attenuation,
			air_absorption = air_absorption})
		if r.is_empty():
			return r
		if doppler > 0.0:
			# Game time (frame deltas), so fixed-fps Movie Maker renders bend right too.
			if _last_dist >= 0.0 and _clock > _last_t:
				var raw := (float(r.distance) - _last_dist) / (_clock - _last_t)
				_radial = lerpf(_radial, raw, 0.35)   # frame-to-frame jitter would warble
			_last_dist = float(r.distance)
			_last_t = _clock
			r["pitch"] = AKSpatial.doppler_factor(_radial, speed_of_sound, doppler)
		if occlusion and occlusion_amount > 0.0:
			r["gain"] = float(r.gain) * lerpf(1.0, AKDsp.db_to_gain(occlusion_db), occlusion_amount)
			r["cutoff_scale"] = float(r.cutoff_scale) * lerpf(1.0, occlusion_lowpass, occlusion_amount)
		return r
	if pan_follows_parent and p is CanvasItem and p.is_inside_tree():
		var vp: Vector2 = p.get_viewport_rect().size
		var at: Vector2 = (p as CanvasItem).get_global_transform_with_canvas().origin
		return {pan = clampf(at.x / maxf(1.0, vp.x) * 2.0 - 1.0, -1.0, 1.0)}
	return {}


func _process(delta: float) -> void:
	_clock += delta
	if _id >= 0:
		var target := 1.0 if (occlusion and _occluded) else 0.0
		occlusion_amount = move_toward(occlusion_amount, target, delta / maxf(1e-3, occlusion_fade_s))
		apply_bindings()


func _physics_process(_delta: float) -> void:
	if _id >= 0 and occlusion and spatial == "on":
		_occluded = AKSpatial.occluded(get_parent(), occlusion_mask)


## Read every binding's property and push it to the voice.
func apply_bindings(glide_override := -1.0) -> void:
	var mix_glide := 0.05 if glide_override < 0.0 else glide_override
	for b: Dictionary in bindings:
		var n: Node = get_node_or_null(b.get("node", ^".."))
		if n == null:
			continue
		var v: Variant = n.get_indexed(NodePath(String(b.get("property", ""))))
		var param := String(b.get("param", "freq_hz"))
		var g := float(b.get("glide_s", 0.05)) if glide_override < 0.0 else glide_override
		if param in _MIX:
			set(param, map_value(v, b))
			mix_glide = g
		else:
			set_param(param, map_value(v, b), g)
	# Gain, pan and cutoff every frame: bindings and the position both move them.
	_sp = _spatial()
	var lp := _player()
	if _id >= 0 and lp and lp.live:
		for param in _MIX:
			if param == "cutoff_hz" and _eff(param) <= 0.0:
				continue   # 0 = unfiltered: don't switch the filter on
			if param == "pitch" and doppler <= 0.0:
				continue
			lp.live.voice_set(_id, param, _eff(param), 0.1 if param == "pitch" else mix_glide)


## A binding's value for property value `v`.
static func map_value(v: Variant, b: Dictionary) -> float:
	var x := 0.0
	if v is Vector2 or v is Vector3 or v is Vector4:
		x = v.length()
	elif v is bool:
		x = 1.0 if v else 0.0
	else:
		x = float(v)
	var from: Array = b.get("from", [0.0, 1.0])
	var to: Array = b.get("to", [0.0, 1.0])
	var t := clampf(inverse_lerp(float(from[0]), float(from[1]), x), 0.0, 1.0) if from[0] != from[1] else 0.0
	if String(b.get("curve", "linear")) == "exp" and float(to[0]) > 0.0 and float(to[1]) > 0.0:
		return float(to[0]) * pow(float(to[1]) / float(to[0]), t)
	return lerpf(float(to[0]), float(to[1]), t)


func _player() -> AKLivePlayer:
	if live_player == null:
		live_player = AKLivePlayer.find(self)
	return live_player
