# SPDX-License-Identifier: Apache-2.0
# The audition dock outside the editor: it shows, plays and measures.
extends RefCounted

const SR := 48000


func _dock() -> AKAuditionDock:
	var d := AKAuditionDock.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(d)
	return d


func test_recipe_plays_and_measures() -> String:
	var d := _dock()
	var r := AKRecipe.make(&"boing")
	d.show_resource(r)
	d.play()
	var s := d.last_stats
	if s.is_empty() or s.length_s <= 0.0 or not is_finite(s.lufs):
		d.queue_free()
		return "no stats after playing a recipe: %s" % [s]
	if d.live:
		var out := d.live.render_offline(SR / 2)
		if out.peak() < 0.05:
			d.queue_free()
			return "the recipe didn't reach the mixer"
	d.queue_free()
	return ""


func test_recipe_loops_at_a_rate() -> String:
	var d := _dock()
	if d.live == null:
		d.queue_free()
		return ""
	var r := AKRecipe.make(&"static")
	d.show_resource(r)
	d._loop.button_pressed = true
	d.play()
	d.live.render_offline(SR)
	var held := d.live.render_offline(SR)
	var voices: int = d.live.stream.voice_count()
	d.stop()
	d.queue_free()
	if voices != 1:
		return "looping should run one voice (%d)" % voices
	return "" if held.peak() > 0.01 else "the loop is silent"


func test_replays_on_edit() -> String:
	var d := _dock()
	var r := AKRecipe.make(&"tone")
	d.show_resource(r)
	d.play()
	var first: float = d.last_stats.length_s
	r.params = {length_s = 2.0, gate_s = 1.9}
	r.emit_changed()
	d._process(1.0)   # past the debounce
	var second: float = d.last_stats.length_s
	d.queue_free()
	return "" if second > first + 0.5 else "editing the recipe didn't replay it (%.2f -> %.2f s)" % [first, second]


func test_song_and_pattern() -> String:
	var d := _dock()
	if d.live == null:
		d.queue_free()
		return ""
	var song: AKSong = load("res://demo/music/e1/e1_song.tres")
	d.show_resource(song)
	d.play()
	var a := d.live.render_playing(SR)
	var p: AKPattern = load("res://demo/music/e1/full.tres")
	d.show_resource(p)
	d.play()
	var b := d.live.render_playing(SR)
	d.stop()
	d.queue_free()
	if a.peak() < 0.05:
		return "the song made no sound"
	return "" if b.peak() > 0.05 else "the pattern made no sound"


func test_cue_map_buttons() -> String:
	var d := _dock()
	var map: AKCueMap = load("res://demo/recipes/race_ident_map.tres")
	d.show_resource(map)
	var buttons := 0
	for c in d._body.get_children():
		if c is HFlowContainer:
			buttons += c.get_child_count()
	d.queue_free()
	return "" if buttons == map.sounds.size() else "%d buttons for %d cues" % [buttons, map.sounds.size()]
