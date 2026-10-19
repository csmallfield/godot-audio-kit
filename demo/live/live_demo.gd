# SPDX-License-Identifier: Apache-2.0
# The live mixer from the scene, no motion kit:
#   - an AKLivePlayer plays the E1 bed live, looping each section;
#     1 / 2 / 3 move to arp / full / light on the next bar, M stops or starts it;
#   - an AKLiveVoice drone follows the mouse (x = pitch, y = filter) through
#     a binding on this node's `pointer` property;
#   - click fires "go", Space fires "count"; the music ducks under them.
# Recorded with Movie Maker (--write-movie), an autopilot plays a short tour.
# Needs the native core built.
extends Node2D

const MAP := preload("res://demo/recipes/race_ident_map.tres")
const SONG := preload("res://demo/music/e1/e1_song.tres")

## 0..1 across and down the window; the drone's bindings read it.
var pointer := Vector2(0.5, 0.5)

var _lp: AKLivePlayer
var _drone: AKLiveVoice
var _label: Label
var _music_on := true
var _t := 0.0
var _tour := [[0.4, "go"], [2.0, "queue:light"], [3.5, "count"], [4.2, "count"], [5.0, "queue:full"], [6.5, "go"], [8.0, "stop"]]


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(24, 24)
	add_child(_label)
	if not AKLive.available():
		_label.text = "The native core isn't built: see native/README.md"
		return
	_lp = AKLivePlayer.new()
	_lp.cue_map = MAP.duplicate()
	_lp.cue_map.duck = {depth_db = 9.0, full_at_db = -14.0, attack_s = 0.004, release_s = 0.25}
	_lp.song = SONG
	_lp.song_follow = "loop"
	_lp.autoplay_song = true
	_lp.section_started.connect(func(n: String) -> void: _status(n))
	add_child(_lp)
	_drone = AKLiveVoice.new()
	_drone.shape = "saw"
	_drone.gain = 0.12
	_drone.cutoff_hz = 600.0
	_drone.q = 2.0
	_drone.send = 0.3
	_drone.attack_s = 0.6
	_drone.bindings = [
		{param = "freq_hz", node = ^"..", property = "pointer:x", from = [0.0, 1.0], to = [55.0, 220.0], curve = "exp", glide_s = 0.08},
		{param = "cutoff_hz", node = ^"..", property = "pointer:y", from = [1.0, 0.0], to = [200.0, 6400.0], curve = "exp", glide_s = 0.05},
	]
	add_child(_drone)
	_status("arp")


func _status(section: String) -> void:
	_label.text = "Section: %s\n1 / 2 / 3: arp / full / light on the next bar.  M: music.\nMouse: drone pitch and filter.  Click: go.  Space: count." % section


func _process(delta: float) -> void:
	if _lp == null:
		return
	if Engine.get_write_movie_path() != "":
		_autopilot(delta)
		return
	pointer = get_viewport().get_mouse_position() / get_viewport_rect().size


func _autopilot(delta: float) -> void:
	_t += delta
	pointer = Vector2(0.5 + 0.4 * sin(_t * 0.7), 0.5 + 0.35 * cos(_t * 0.45))
	while not _tour.is_empty() and _t >= float(_tour[0][0]):
		var step: String = _tour.pop_front()[1]
		if step.begins_with("queue:"):
			_lp.song_queue(step.substr(6))
		elif step == "stop":
			_lp.song_stop()
			_drone.stop(1.0)
		else:
			_lp.trigger(StringName(step), 1.0, {pitch = 1.0})


func _unhandled_input(e: InputEvent) -> void:
	if _lp == null:
		return
	if e is InputEventMouseButton and e.pressed:
		_lp.trigger(&"go")
	elif e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_SPACE:
				_lp.trigger(&"count", randf_range(0.6, 1.0), {pitch = randf_range(0.9, 1.15)})
			KEY_1:
				_lp.song_queue("arp")
			KEY_2:
				_lp.song_queue("full")
			KEY_3:
				_lp.song_queue("light")
			KEY_M:
				_music_on = not _music_on
				if _music_on:
					_lp.song_play()
				else:
					_lp.song_stop()
