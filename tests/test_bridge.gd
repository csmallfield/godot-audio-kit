# SPDX-License-Identifier: Apache-2.0
# Bridge tests. They need the motion kit linked in (tools/link_motion_kit.sh)
# and pass trivially without it, so the audio kit's suite never depends on it.
extends RefCounted


func _comp_script() -> Script:
	for c in ProjectSettings.get_global_class_list():
		if c.class == &"MotionComposition":
			return load(c.path)
	return null


func _make() -> Node:
	var cs := _comp_script()
	if cs == null:
		return null
	var comp: Node = cs.new()
	comp.set("fps", 30.0)
	comp.set("duration", 60.0)
	comp.set("autoplay", false)
	comp.call("cue", 15.0, &"go", 1.0)
	comp.call("cue", 30.0, &"tick", 0.5)
	return comp


func _map() -> AKCueMap:
	var m := AKCueMap.new()
	m.sounds = {"go": AKRecipe.make(&"boing"), "tick": AKRecipe.make(&"click")}
	return m


func test_detects_compositions() -> String:
	if AKCueBridge.is_composition(Node.new()):
		return "a plain Node passed as a composition"
	var comp := _make()
	if comp and not AKCueBridge.is_composition(comp):
		return "a MotionComposition was not recognised"
	return ""


func test_baked_track_lands_cues() -> String:
	var comp := _make()
	if comp == null:
		print("        (motion kit not linked: skipped)")
		return ""
	var bridge := AKCueBridge.new()
	bridge.composition = comp
	bridge.cue_map = _map()
	AK.disk_cache = false
	var stream := bridge.bake()
	var player: AudioStreamPlayer = comp.get("audio")
	if player == null or player.stream != stream:
		return "track not attached to the composition's audio player"
	if int(comp.get("clock")) != 1:
		return "clock not switched to AUDIO"
	var r := AK.render_cues(bridge.cues(), bridge.cue_map, 30.0, 2.0)
	var lead := AK.render(bridge.cue_map.sounds["go"]).first_above(1e-4)
	var expected := roundi(0.5 * AK.sample_rate) + lead
	if r.mix.first_above(1e-4) != expected:
		return "first cue at sample %d, expected %d" % [r.mix.first_above(1e-4), expected]
	if absf(stream.get_length() - r.mix.seconds()) > 0.001:
		return "attached track length %.3f differs from the render %.3f" % [stream.get_length(), r.mix.seconds()]
	comp.free()
	return ""


func test_track_key_follows_cues() -> String:
	var comp := _make()
	if comp == null:
		return ""
	var bridge := AKCueBridge.new()
	bridge.composition = comp
	bridge.cue_map = _map()
	var k1 := bridge.current_key()
	comp.call("cue", 45.0, &"go", 0.8)
	var k2 := bridge.current_key()
	comp.free()
	return "" if k1 != k2 else "adding a cue did not change the track key"


func test_event_mode_plays_cues() -> String:
	var comp := _make()
	if comp == null:
		return ""
	var bridge := AKCueBridge.new()
	bridge.composition = comp
	bridge.cue_map = _map()
	bridge.mode = AKCueBridge.Mode.EVENTS
	bridge.voices = 2
	bridge._setup_events()
	var got := []
	bridge.played.connect(func(n: StringName, p: AudioStreamPlayer) -> void: got.append([n, p.stream]))
	for c in comp.call("get_cue_sheet"):
		comp.emit_signal("cue_fired", c)
	comp.free()
	bridge.free()
	if got.size() != 2 or got[0][0] != &"go" or not (got[0][1] is AudioStreamWAV):
		return "expected go and tick to play, got %s" % str(got)
	return ""


func test_global_bus_lookup() -> String:
	if _comp_script() == null:
		return ""
	return "" if AKCueBridge._global_bus() != null else "MotionCue.bus not found"


func test_song_cues_and_bed() -> String:
	var comp := _make()
	if comp == null:
		return ""
	var song := AKSong.new()
	song.tempo = AKTempoMap.make(120.0)
	var p := AKPattern.new()
	p.lanes.assign([{name = "kick", recipe = AKRecipe.make(&"kick"), steps = "x...x...x...x..."}])
	song.sections.assign([{name = "a", bars = 1, patterns = [p]}])
	var bridge := AKCueBridge.new()
	bridge.composition = comp
	bridge.cue_map = _map()
	bridge.song = song
	bridge.add_song_cues()
	var names := bridge.cues().map(func(c): return c.name)
	if names.count("music.kick") != 4 or not names.has("music.section"):
		return "song cues not added to the composition: %s" % str(names)
	AK.disk_cache = false
	var stream := bridge.bake()
	comp.free()
	return "" if stream and stream.get_length() >= 1.99 else "baked track missing or short"


func test_live_mode_matches_the_bake() -> String:
	var comp := _make()
	if comp == null or not AKLive.available():
		if comp:
			comp.free()
		return ""
	var bridge := AKCueBridge.new()
	bridge.composition = comp
	bridge.cue_map = _map()
	bridge.mode = AKCueBridge.Mode.LIVE
	var live := bridge.prepare_live()
	var player: AudioStreamPlayer = comp.get("audio")
	if player == null or player.stream != live.stream:
		comp.free()
		bridge.free()
		return "live stream not attached to the composition's audio player"
	if int(comp.get("clock")) != 1:
		comp.free()
		bridge.free()
		return "clock not switched to AUDIO"
	var ref: AKBuffer = AK.render_cues(bridge.cues(), bridge.cue_map, 30.0, 2.0).mix
	var out := live.render_offline(live.length_frames())
	var d := 0.0
	for i in mini(out.frames(), ref.frames()):
		d = maxf(d, absf(out.l[i] - ref.l[i]))
	comp.free()
	bridge.free()
	if out.frames() != ref.frames():
		return "live length %d, baked %d" % [out.frames(), ref.frames()]
	return "" if d < 1e-4 else "live mix differs from the bake by %f" % d
