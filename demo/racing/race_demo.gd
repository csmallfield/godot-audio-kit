# SPDX-License-Identifier: Apache-2.0
# A small race whose state drives the music: "Neon Circuit" as an
# arrangement (demo/racing/arrangement/), its scenes switched by an
# AKLivePlayer on the next bar as the race moves on:
#
#   menu         intro      (Space, or the autopilot, starts the race)
#   countdown    build      three beeps and GO on the beats
#   racing       race       laps 1 .. laps-1; a checkpoint chime each lap
#   final lap    final_lap
#   finished     finish     the fanfare
#
# The car drives itself round the oval; Up / Down change its speed (a
# faster lap). The HUD shows the race state and the scene playing.
# Recorded with Movie Maker, the autopilot runs the whole race. Needs the
# native core built (without it the music stays silent; the race still runs).
extends Node2D

## Emitted when the race moves to another state.
signal state_changed(state: String)

const ARR := preload("res://demo/racing/arrangement/neon_circuit.tres")
const CUES := preload("res://demo/racing/race_cues.tres")
## Which scene plays in each race state.
const SCENE_FOR := {menu = "intro", countdown = "build", racing = "race", final_lap = "final_lap", finished = "finish"}

@export var laps := 3
## Seconds a lap takes at normal speed.
@export var lap_time_s := 9.0
## Seconds on the menu before the autopilot starts the race.
@export var menu_s := 3.0
## Start and finish the race by itself (Movie Maker, tests).
@export var autopilot := true
## Play the race's sound effects (tests of the music alone turn them off).
@export var sfx := true
## Send the music to the speakers (tests pull the live stream themselves).
@export var audio := true
## The music: "Neon Circuit" unless another arrangement is given.
@export var arrangement: AKArrangement = ARR

var state := ""
var lap := 0
var speed := 1.0
var progress := 0.0   # laps driven, fractional
var player: AKLivePlayer

var _t := 0.0         # seconds in the current state
var _beeps := 0
var _label: Label


func _ready() -> void:
	player = AKLivePlayer.new()
	player.name = "Music"
	player.arrangement = arrangement
	player.cue_map = CUES
	player.audio_output = audio
	add_child(player)
	_label = Label.new()
	_label.position = Vector2(24, 20)
	_label.add_theme_font_size_override(&"font_size", 22)
	add_child(_label)
	set_state("menu")


func _process(delta: float) -> void:
	advance(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_accept") and state == "menu":
		set_state("countdown")
	elif event.is_action_pressed(&"ui_up"):
		speed = minf(2.0, speed + 0.25)
	elif event.is_action_pressed(&"ui_down"):
		speed = maxf(0.5, speed - 0.25)


## Move the race on by `dt` seconds of game time (the scene's _process, or a test).
func advance(dt: float) -> void:
	_t += dt
	match state:
		"menu":
			if autopilot and _t >= menu_s:
				set_state("countdown")
		"countdown":
			# A beep a beat apart, then GO; the race starts on GO.
			var beat := 60.0 / arrangement.tempo.bpm
			while _beeps < 4 and _t >= (_beeps + 1) * beat * 2.0:
				_beeps += 1
				_sfx(&"countdown_beep" if _beeps < 4 else &"countdown_go")
			if _beeps >= 4:
				lap = 1
				progress = 0.0
				set_state("final_lap" if laps <= 1 else "racing")
		"racing", "final_lap":
			progress += dt * speed / lap_time_s
			while progress >= lap:
				lap += 1
				if lap > laps:
					set_state("finished")
					_sfx(&"finish_fanfare")
					break
				_sfx(&"lap_complete")
				if lap == laps:
					set_state("final_lap")
		"finished":
			pass
	queue_redraw()
	if _label:
		_label.text = "%s   lap %d/%d   music: %s" % [state.replace("_", " "), clampi(lap, 0, laps), laps, player.current_scene if player else ""]


func set_state(s: String) -> void:
	if s == state:
		return
	state = s
	_t = 0.0
	if s == "countdown":
		_beeps = 0
	if player and player.live:
		player.play_scene(SCENE_FOR[s], &"bar")
	state_changed.emit(s)


func _sfx(cue: StringName) -> void:
	if sfx and player:
		player.trigger(cue)


func _draw() -> void:
	var size := get_viewport_rect().size if is_inside_tree() else Vector2(1280, 720)
	var c := size * 0.5 + Vector2(0, 30)
	var r := Vector2(size.x * 0.36, size.y * 0.3)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.05, 0.12))
	var pts := PackedVector2Array()
	for i in 65:
		var a := TAU * i / 64.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	draw_polyline(pts, Color(0.95, 0.2, 0.7), 26.0, true)
	draw_polyline(pts, Color(0.1, 0.08, 0.18), 18.0, true)
	draw_line(c + Vector2(0, r.y - 14), c + Vector2(0, r.y + 14), Color.WHITE, 3.0)
	var a := TAU * fposmod(progress, 1.0) + PI * 0.5
	var car := c + Vector2(cos(a) * r.x, sin(a) * r.y)
	draw_circle(car, 10.0, Color(0.2, 0.9, 1.0))
