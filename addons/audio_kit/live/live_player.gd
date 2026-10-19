# SPDX-License-Identifier: Apache-2.0
## A live mixer in the scene: one AKLive and the AudioStreamPlayer that plays
## it. Game code fires cues (`trigger`), plays and steers music (`song_play`,
## `song_queue`, `set_lane_gain`), and AKLiveVoice nodes below it (or
## pointing at it) run continuous voices from game state.
##
## Needs the native core; without it the node warns and stays silent.
@icon("res://addons/audio_kit/icons/recipe.svg")
class_name AKLivePlayer
extends Node

## Emitted when the music starts a section.
signal section_started(section_name: String)

## Recipes for trigger(), the shared reverb, ducking and the master chain.
@export var cue_map: AKCueMap
@export var bus: StringName = &"Master"
## Music to play live (sequenced as it plays).
@export var song: AKSong
## Start the song when the scene starts.
@export var autoplay_song := false
## "song" plays the sections in order; "loop" repeats each until queued on.
@export_enum("song", "loop") var song_follow := "loop"
## How far ahead notes are rendered and scheduled (seconds).
@export_range(0.05, 2.0, 0.01) var lookahead_s := 0.4
## Follow AKReverbZone2D/3D areas: the shared reverb glides to the zone the
## listener is in.
@export var follow_reverb_zones := true
@export var zone_glide_s := 0.8
@export_group("Positional triggers")
## trigger_at(): distance where the level starts to fall (px in 2D, m in 3D).
@export var unit_size := 100.0
@export var max_distance := 2000.0
@export_enum("inverse", "inverse_square", "linear") var attenuation := "inverse"
@export_group("")

var live: AKLive
var player: AudioStreamPlayer
## The reverb zone the listener is in (null: the cue map's reverb).
var current_zone: Node
## Emitted when the listener moves into another reverb zone (null = none).
signal zone_changed(zone: Node)


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group(&"ak_live_player")
	if setup() and autoplay_song and song:
		song_play()


## Build the mixer and start it (called by _ready; callable before that).
func setup() -> bool:
	if live:
		return true
	if not AKLive.available():
		push_warning("AKLivePlayer: the native core isn't built; no live sound")
		return false
	live = AKLive.new()
	live.lookahead_s = lookahead_s
	live.prepare([], cue_map if cue_map else AKCueMap.new())
	live.section_started.connect(func(n: String, _f: int) -> void: section_started.emit(n))
	player = AudioStreamPlayer.new()
	player.name = "AudioKitLive"
	player.bus = bus
	player.stream = live.stream
	add_child(player)
	if is_inside_tree():
		player.play()
	return true


func _process(_delta: float) -> void:
	if live:
		live.update()


func _physics_process(_delta: float) -> void:
	if live and follow_reverb_zones:
		follow_zone(AKSpatial.reverb_zone_at(self))


## Glide the reverb to `zone` (an AKReverbZone2D/3D, or null for the cue
## map's). Called each physics frame when follow_reverb_zones is on.
func follow_zone(zone: Node) -> void:
	if zone == current_zone or live == null:
		return
	current_zone = zone
	var g := zone_glide_s
	if zone and float(zone.get("glide_s")) >= 0.0:
		g = float(zone.get("glide_s"))
	live.set_reverb_space(zone.call("settings") if zone else live.default_reverb(), g)
	zone_changed.emit(zone)


## Play a cue from the cue map now (game events).
func trigger(cue_name: StringName, intensity := 1.0, data := {}, delay_s := 0.0) -> void:
	if live:
		live.trigger(cue_name, intensity, data, delay_s)


## Play a cue at a position (Vector2 in 2D, Vector3 in 3D): quieter and
## panned by where it is from the listener (see AKSpatial and the spatial
## settings below).
func trigger_at(cue_name: StringName, position: Variant, intensity := 1.0, data := {}) -> void:
	if live == null or not is_inside_tree():
		return
	var vp := get_viewport()
	var sp := {}
	var s := spatial_settings()
	if position is Vector3:
		var l: Variant = AKSpatial.listener_3d(vp)
		sp = AKSpatial.compute_3d(l, position, s) if l != null else {}
	elif position is Vector2:
		sp = AKSpatial.compute_2d(AKSpatial.listener_2d(vp), position, s, vp.get_visible_rect().size.x * 0.5)
	var g := float(sp.get("gain", 1.0))
	if g <= 1e-4:
		return
	live.trigger(cue_name, intensity, data, 0.0, null, linear_to_db(g), float(sp.get("pan", 0.0)))


func spatial_settings() -> Dictionary:
	return {unit_size = unit_size, max_distance = max_distance, attenuation = attenuation}


## Start the music (this node's `song` unless another is given), from the
## top or from `section`.
func song_play(p_song: AKSong = null, section := "") -> void:
	if live:
		live.song_play(p_song if p_song else song, StringName(song_follow), section)


## Move to `section_name` at the next "bar" (or "beat", "section", "now").
func song_queue(section_name: String, quantize: StringName = &"bar") -> void:
	if live:
		live.song_queue(section_name, quantize)


func song_stop(quantize: StringName = &"bar") -> void:
	if live:
		live.song_stop(quantize)


## Vertical remix: 0..1, fading the song's intensity_lanes in and out.
func set_music_intensity(x: float, glide_s := 1.0) -> void:
	if live:
		live.set_music_intensity(x, glide_s)


func set_lane_gain(lane: StringName, db: float, glide_s := 0.2) -> void:
	if live:
		live.set_lane_gain(lane, db, glide_s)


## The nearest AKLivePlayer: an ancestor of `from`, else the first in the
## scene tree's "ak_live_player" group.
static func find(from: Node) -> AKLivePlayer:
	var n := from.get_parent()
	while n:
		if n is AKLivePlayer:
			return n
		n = n.get_parent()
	if from.is_inside_tree():
		return from.get_tree().get_first_node_in_group(&"ak_live_player") as AKLivePlayer
	return null
