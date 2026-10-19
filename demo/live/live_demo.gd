# SPDX-License-Identifier: Apache-2.0
# The live mixer on its own, no motion kit: a continuous voice that follows
# the mouse (x = pitch, y = filter) and one-shot cues on click and keys, all
# through one shared reverb and limiter. Needs the native core built.
extends Node2D

const MAP := preload("res://demo/recipes/race_ident_map.tres")

var live: AKLive
var drone := -1
var _label: Label


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(24, 24)
	add_child(_label)
	if not AKLive.available():
		_label.text = "The native core isn't built: see native/README.md"
		return
	live = AKLive.new()
	live.prepare([], MAP)          # no timeline: reverb and master chain only
	var player := AudioStreamPlayer.new()
	player.stream = live.stream
	add_child(player)
	player.play()
	drone = live.voice_start({shape = "saw", freq_hz = 110.0, gain = 0.25, cutoff_hz = 600.0, q = 2.0, send = 0.3, attack_s = 0.3})
	_label.text = "Move the mouse: pitch and filter.  Click: go.  Space: count.  D: drone on/off."


func _process(_delta: float) -> void:
	if live == null or drone < 0:
		return
	var vp := get_viewport_rect().size
	var m := get_viewport().get_mouse_position() / vp
	live.voice_set(drone, "freq_hz", 55.0 * pow(2.0, clampf(m.x, 0.0, 1.0) * 3.0), 0.08)
	live.voice_set(drone, "cutoff_hz", 200.0 * pow(2.0, (1.0 - clampf(m.y, 0.0, 1.0)) * 5.0), 0.05)


func _unhandled_input(e: InputEvent) -> void:
	if live == null:
		return
	if e is InputEventMouseButton and e.pressed:
		live.trigger(&"go", 1.0)
	elif e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_SPACE:
				live.trigger(&"count", randf_range(0.6, 1.0), {pitch = randf_range(0.9, 1.15)})
			KEY_D:
				if drone >= 0:
					live.voice_stop(drone, 0.4)
					drone = -1
				else:
					drone = live.voice_start({shape = "saw", freq_hz = 110.0, gain = 0.25, cutoff_hz = 600.0, q = 2.0, send = 0.3, attack_s = 0.3})
