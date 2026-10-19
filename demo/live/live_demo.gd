# SPDX-License-Identifier: Apache-2.0
# The live mixer from the scene, no motion kit:
#   - an AKLivePlayer plays the E1 bed live, looping each section;
#     1 / 2 / 3 move to arp / full / light on the next bar, M stops or starts it;
#   - an AKLiveVoice drone follows the mouse (x = pitch, y = filter) through
#     a binding on this node's `pointer` property;
#   - click fires "go" where you click (positional: quieter and panned with
#     distance from the middle), Space fires "count"; the music ducks under them;
#   - a car (the orange square) circles the screen with a two-layer engine
#     (idle and high loops crossfaded by speed) whose level and pan follow
#     its position;
#     with Doppler as it swings past and muffled while it's behind the wall
#     (the grey bar) on the right;
#   - Up / Down raise and lower the music's intensity: hats and claps fade in
#     and out (vertical remix);
#   - moving into "full" plays a riser stinger, any other change a click.
# Recorded with Movie Maker (--write-movie), an autopilot plays a short tour.
# Needs the native core built.
extends Node2D

const MAP := preload("res://demo/recipes/race_ident_map.tres")
const SONG := preload("res://demo/music/e1/e1_song.tres")

## 0..1 across and down the window; the drone's bindings read it.
var pointer := Vector2(0.5, 0.5)
## The car's speed (px/s); its engine loop's rate binding reads it.
var car_speed := 0.0

var _lp: AKLivePlayer
var _drone: AKLiveVoice
var _label: Label
var _music_on := true
var _t := 0.0
var _car: Node2D
var _car_angle := 0.0
var _intensity := 0.5
var _tour := [[0.4, "go"], [1.0, "intensity:0.2"], [2.0, "queue:light"], [3.5, "count"], [4.2, "count"], [5.0, "queue:full"],
	[5.5, "intensity:1.0"], [6.5, "go"], [8.0, "stop"]]


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
	_lp.song = _song_with_stingers()
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
	_add_car()


func _song_with_stingers() -> AKSong:
	var song: AKSong = SONG.duplicate(true)
	var riser := AKRecipe.make(&"whoosh")
	riser.params = {length_s = 0.4}
	riser.offset_s = -0.35
	riser.send = 0.4
	var tick := AKRecipe.make(&"click")
	tick.params = {freq_hz = 3200.0}
	song.stingers = [{to = "full", recipe = riser, gain_db = -4.0}, {to = "*", recipe = tick, gain_db = -10.0}]
	song.intensity_lanes = {"hat": [0.3, 0.6], "clap": [0.55, 0.9]}
	song.intensity = _intensity
	return song


func _add_car() -> void:
	_car = Node2D.new()
	add_child(_car)
	var body := ColorRect.new()
	body.color = Color("#ff8a3a")
	body.size = Vector2(28, 28)
	body.position = Vector2(-14, -14)
	_car.add_child(body)
	# Two loops "recorded" at different speeds: a soft idle and a gritty high.
	var idle := AKRecipe.make(&"fm")
	idle.params = {freq_hz = 55.0, ratio = 0.5, index = 2.0, index_end = 2.0, sustain = 1.0, decay_s = 0.01,
		attack_s = 0.0, gate_s = 1.3, release_s = 0.01, length_s = 1.3}
	var high := AKRecipe.make(&"fm")
	high.params = {freq_hz = 110.0, ratio = 0.5, index = 5.0, index_end = 5.0, ratio2 = 1.5, index2 = 0.8, sustain = 1.0,
		decay_s = 0.01, attack_s = 0.0, gate_s = 1.3, release_s = 0.01, length_s = 1.3}
	var engine := AKLiveLayers.new()
	engine.layers = [{recipe = idle, at = 150.0}, {recipe = high, at = 600.0, gain_db = -3.0}]
	engine.value_node = ^"../.."
	engine.value_property = "car_speed"
	engine.rate_range = Vector2(0.6, 1.6)
	engine.gain = 0.5
	engine.cutoff_hz = 2500.0
	engine.attack_s = 0.5
	engine.spatial = "on"
	engine.unit_size = 150.0
	engine.max_distance = 1400.0
	engine.air_absorption = 0.6
	engine.doppler = 1.0
	engine.speed_of_sound = 4000.0
	engine.occlusion = true
	engine.occlusion_db = -10.0
	_car.add_child(engine)
	_add_wall()


func _add_wall() -> void:
	var vp := get_viewport_rect().size
	var wall := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(24, vp.y * 0.45)
	shape.shape = rect
	wall.add_child(shape)
	var look := ColorRect.new()
	look.color = Color("#8a8a8a")
	look.size = rect.size
	look.position = -rect.size * 0.5
	wall.add_child(look)
	wall.position = vp * 0.5 + Vector2(vp.x * 0.25, 0)
	add_child(wall)


var _section := "arp"


func _status(section: String) -> void:
	_section = section
	_label.text = "Section: %s\n1 / 2 / 3: arp / full / light on the next bar.  M: music.\nMouse: drone pitch and filter.  Click: go, where you click.  Space: count.\nUp / Down: music intensity (%.2f).  The car's engine follows its speed and position, muffled behind the wall." % [section, _intensity]


func _process(delta: float) -> void:
	if _lp == null:
		return
	_drive(delta)
	if Engine.get_write_movie_path() != "":
		_autopilot(delta)
		return
	pointer = get_viewport().get_mouse_position() / get_viewport_rect().size


func _drive(delta: float) -> void:
	# Round an ellipse, fast on the straights at the sides, slow at the ends.
	var vp := get_viewport_rect().size
	var w := 0.9 + 0.7 * absf(cos(_car_angle))
	_car_angle += w * delta
	var p := vp * 0.5 + Vector2(cos(_car_angle) * vp.x * 0.4, sin(_car_angle) * vp.y * 0.3)
	if _car.position != Vector2.ZERO:
		car_speed = _car.position.distance_to(p) / maxf(delta, 1e-4)
	_car.position = p


func _autopilot(delta: float) -> void:
	_t += delta
	pointer = Vector2(0.5 + 0.4 * sin(_t * 0.7), 0.5 + 0.35 * cos(_t * 0.45))
	while not _tour.is_empty() and _t >= float(_tour[0][0]):
		var step: String = _tour.pop_front()[1]
		if step.begins_with("intensity:"):
			_set_intensity(float(step.substr(10)))
		elif step.begins_with("queue:"):
			_lp.song_queue(step.substr(6))
		elif step == "stop":
			_lp.song_stop()
			_drone.stop(1.0)
			for c in _car.get_children():
				if c is AKLiveLayers:
					c.stop(1.0)
		else:
			var at := get_viewport_rect().size * Vector2(0.15 if step == "go" else 0.85, 0.5)
			_lp.trigger_at(StringName(step), at, 1.0, {pitch = 1.0})


func _set_intensity(x: float) -> void:
	_intensity = clampf(x, 0.0, 1.0)
	_lp.set_music_intensity(_intensity, 0.8)
	_status(_section)


func _unhandled_input(e: InputEvent) -> void:
	if _lp == null:
		return
	if e is InputEventMouseButton and e.pressed:
		_lp.trigger_at(&"go", get_global_mouse_position())
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
			KEY_UP:
				_set_intensity(_intensity + 0.15)
			KEY_DOWN:
				_set_intensity(_intensity - 0.15)
			KEY_M:
				_music_on = not _music_on
				if _music_on:
					_lp.song_play()
				else:
					_lp.song_stop()
