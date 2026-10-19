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
## Control parent).
@export var pan_follows_parent := false
## Start when the scene starts.
@export var autostart := true
@export var bindings: Array[Dictionary] = []

var _id := -1


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
	_id = lp.live.voice_start({shape = shape, freq_hz = freq_hz, gain = gain, cutoff_hz = cutoff_hz, q = q, pan = pan,
		send = send, width = width, noise = noise, attack_s = attack_s, seed = get_instance_id() & 0xffff})
	apply_bindings(0.0)


func stop(p_release_s := -1.0) -> void:
	if _id < 0:
		return
	var lp := _player()
	if lp and lp.live:
		lp.live.voice_stop(_id, release_s if p_release_s < 0.0 else p_release_s)
	_id = -1


## Glide one parameter (freq_hz, gain, cutoff_hz, q, pan, send, width, noise).
func set_param(param: String, value: float, glide_s := 0.05) -> void:
	set(param, value)
	var lp := _player()
	if _id >= 0 and lp and lp.live:
		lp.live.voice_set(_id, param, value, glide_s)


func _process(_delta: float) -> void:
	if _id >= 0:
		apply_bindings()


## Read every binding's property and push it to the voice.
func apply_bindings(glide_override := -1.0) -> void:
	for b: Dictionary in bindings:
		var n: Node = get_node_or_null(b.get("node", ^".."))
		if n == null:
			continue
		var v: Variant = n.get_indexed(NodePath(String(b.get("property", ""))))
		set_param(String(b.get("param", "freq_hz")), map_value(v, b), float(b.get("glide_s", 0.05)) if glide_override < 0.0 else glide_override)
	if pan_follows_parent:
		var p := get_parent()
		var x := NAN
		if p is CanvasItem and p.is_inside_tree():
			var vp: Vector2 = p.get_viewport_rect().size
			var at: Vector2 = (p as CanvasItem).get_global_transform_with_canvas().origin
			x = at.x / maxf(1.0, vp.x)
		if is_finite(x):
			set_param("pan", clampf(x * 2.0 - 1.0, -1.0, 1.0), 0.05)


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
