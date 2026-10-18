# SPDX-License-Identifier: Apache-2.0
## Gives a Godot Motion Kit composition its sound. Add it as a child of a
## MotionComposition (or point `composition` at one) and give it a cue map.
##
## BAKED (authored pieces): renders the composition's whole cue sheet into one
## track, puts it on the composition's `audio` player and locks the picture to
## it (`clock = AUDIO`). Every hit lands on its exact sample. The track is
## cached by a hash of the cues and recipes; press "Bake track" in the
## inspector to save it into the project so nothing renders at runtime.
##
## EVENTS (interactive pieces): plays each cue as playback crosses it, from
## a pool of players. Timing is within one audio mix buffer; negative recipe
## offsets are honoured by starting the sound part-way in; the shared reverb
## send is not applied. A native sample-exact mixer replaces this in phase 3.
##
## The motion kit is optional: this node finds the composition by its methods
## and signals, and does nothing if there isn't one.
@tool
@icon("res://addons/audio_kit/icons/recipe.svg")
class_name AKCueBridge
extends Node

enum Mode { BAKED, EVENTS }

## Emitted when a baked track is ready (rendered or loaded from cache).
signal baked(stream: AudioStreamWAV)
## Emitted in EVENTS mode when a cue starts a sound.
signal played(cue_name: StringName, player: AudioStreamPlayer)

## The MotionComposition to score. Empty = the parent node.
@export var composition: Node
@export var cue_map: AKCueMap
@export var mode := Mode.BAKED
@export var bus: StringName = &"Master"
## BAKED: set the composition's clock to AUDIO so picture follows sound.
@export var lock_clock := true
## BAKED: a saved bake. Used when its cue hash still matches; otherwise the
## track is re-rendered.
@export var track: AudioStreamWAV
## BAKED: where "Bake track" saves. Empty = res://audio_kit/tracks/<scene name>.res
@export_file("*.res") var track_path := ""
## EVENTS: how many sounds can overlap.
@export_range(1, 64) var voices := 8
## EVENTS: listen to every composition through MotionCue.bus instead of one.
@export var listen_global := false

@export_tool_button("Bake track", "AudioStreamWAV") var _bake_button := _editor_bake

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _counts := {}


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if composition == null:
		composition = get_parent()
	if not is_composition(composition):
		if not (mode == Mode.EVENTS and listen_global):
			push_warning("AKCueBridge: %s is not a motion kit composition; nothing to score" % composition)
			return
	if cue_map == null:
		push_warning("AKCueBridge: no cue map")
		return
	match mode:
		Mode.BAKED:
			bake()
			# Cues declared in the composition's own _ready (after this node's)
			# change the hash; rebake then if needed.
			if composition is Node and not composition.is_node_ready():
				composition.ready.connect(_rebake_if_changed, CONNECT_ONE_SHOT)
		Mode.EVENTS:
			_setup_events()


static func is_composition(n: Variant) -> bool:
	return n is Node and n.has_method("get_cue_sheet") and n.has_signal("cue_fired") and n.get("fps") != null


## The composition's cues as plain dictionaries (export_cue_sheet's shape).
func cues() -> Array:
	var out := []
	for c in composition.call("get_cue_sheet"):
		out.append(c.call("to_dict"))
	return out


func current_key() -> String:
	var fps := float(composition.get("fps"))
	return AK.track_key(cues(), cue_map, fps, float(composition.get("duration")) / fps)


## Render (or reuse) the composition's track and attach it. Returns it.
func bake() -> AudioStreamWAV:
	var fps := float(composition.get("fps"))
	var length := float(composition.get("duration")) / fps
	var cs := cues()
	var key := AK.track_key(cs, cue_map, fps, length)
	if track == null or not track.has_meta("ak_key") or track.get_meta("ak_key") != key:
		var cached := AK.BAKE_DIR + "track_" + key.left(24) + ".res"
		if AK.disk_cache and ResourceLoader.exists(cached):
			track = load(cached)
		else:
			if not Engine.is_editor_hint():
				push_warning("AKCueBridge: rendering %s's track at runtime; bake it in the editor to skip this" % composition.name)
			track = AK.render_cues(cs, cue_map, fps, length).mix.to_stream(key.hash())
			track.set_meta("ak_key", key)
			if AK.disk_cache and OS.has_feature("editor"):
				DirAccess.make_dir_recursive_absolute(AK.BAKE_DIR)
				ResourceSaver.save(track, cached)
	_attach()
	baked.emit(track)
	return track


func _rebake_if_changed() -> void:
	if track == null or not track.has_meta("ak_key") or track.get_meta("ak_key") != current_key():
		bake()


func _attach() -> void:
	var player: AudioStreamPlayer = composition.get("audio")
	if player == null:
		# The player lives under this node: the composition may still be
		# setting up its children, when adding one to it would fail.
		player = AudioStreamPlayer.new()
		player.name = "AudioKitTrack"
		player.bus = bus
		add_child(player)
		composition.set("audio", player)
	var was_playing := player.playing
	player.stream = track
	if lock_clock:
		composition.set("clock", 1)   # MotionComposition.Clock.AUDIO
	# The composition may already be playing (its autoplay ran before the bake).
	if composition.get("playing") and not was_playing and is_inside_tree():
		player.play(float(composition.get("frame")) / float(composition.get("fps")))


func _editor_bake() -> void:
	if composition == null:
		composition = get_parent()
	if not is_composition(composition) or cue_map == null:
		push_error("AKCueBridge: needs a composition and a cue map")
		return
	track = null
	bake()
	var path := track_path
	if path == "":
		var scene := owner.scene_file_path.get_file().get_basename() if owner else String(composition.name)
		path = "res://audio_kit/tracks/%s.res" % scene
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	ResourceSaver.save(track, path)
	track = load(path)
	track_path = path
	print("AKCueBridge: baked %.2f s to %s" % [track.get_length(), path])


# ------------------------------------------------------------------ events

func _setup_events() -> void:
	for i in voices:
		var p := AudioStreamPlayer.new()
		p.bus = bus
		add_child(p)
		_players.append(p)
	var source: Object = _global_bus() if listen_global else composition
	if source == null:
		push_warning("AKCueBridge: MotionCue.bus not found")
		return
	if listen_global:
		source.connect("fired", _on_cue)
		source.connect("sync", func(_comp: Variant, _f: float, state: StringName) -> void: _on_sync(state))
	else:
		source.connect("cue_fired", _on_cue)
		source.connect("cue_sync", func(_f: float, state: StringName) -> void: _on_sync(state))
	# Bake every sound the sheet will need now, so playback doesn't hitch.
	if is_composition(composition):
		var counts := {}
		for c in cues():
			var r := cue_map.recipe_for(StringName(c.name))
			if r:
				var idx: int = counts.get(c.name, 0)
				counts[c.name] = idx + 1
				AK.bake(r, float(c.get("intensity", 1.0)), c.get("data", {}), idx)


## Play one cue now. Called for each fired cue; callable directly too.
func _on_cue(c: Object) -> void:
	if bool(c.get("reversed")):
		return
	var name := StringName(c.get("name"))
	var r := cue_map.recipe_for(name)
	if r == null or _players.is_empty():
		return
	var idx: int = _counts.get(name, 0)
	_counts[name] = idx + 1
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = AK.bake(r, float(c.get("intensity")), c.get("data"), idx)
	if p.is_inside_tree():
		p.play(maxf(0.0, -r.offset_s))
	played.emit(name, p)


func _on_sync(state: StringName) -> void:
	if state == &"seek" or state == &"stop" or state == &"start":
		for p in _players:
			p.stop()
		if state != &"stop":
			_counts.clear()


static func _global_bus() -> Object:
	for c in ProjectSettings.get_global_class_list():
		if c.class == &"MotionCue":
			var script: Script = load(c.path)
			return script.get("bus") if script else null
	return null
