# SPDX-License-Identifier: Apache-2.0
# AKLivePlayer and AKLiveVoice: game state driving live voices, music
# control from the scene. Native-only parts pass trivially without the core.
extends RefCounted

const SR := 48000


func test_map_value() -> String:
	var lin := {from = [0.0, 10.0], to = [100.0, 200.0]}
	if absf(AKLiveVoice.map_value(5.0, lin) - 150.0) > 1e-6:
		return "linear midpoint is %f" % AKLiveVoice.map_value(5.0, lin)
	if absf(AKLiveVoice.map_value(50.0, lin) - 200.0) > 1e-6:
		return "values past the range are not clamped"
	var ex := {from = [0.0, 1.0], to = [100.0, 400.0], curve = "exp"}
	if absf(AKLiveVoice.map_value(0.5, ex) - 200.0) > 1e-3:
		return "exp midpoint is %f, wanted 200" % AKLiveVoice.map_value(0.5, ex)
	if absf(AKLiveVoice.map_value(Vector2(3, 4), {from = [0.0, 10.0], to = [0.0, 1.0]}) - 0.5) > 1e-6:
		return "vectors should map by length"
	return ""


static func _hz(b: AKBuffer, from: int, to: int) -> float:
	var z := 0
	for i in range(from + 1, to):
		if (b.l[i - 1] < 0.0) != (b.l[i] < 0.0):
			z += 1
	return z / 2.0 / (float(to - from) / SR)


func test_voice_follows_game_state() -> String:
	if not AKLive.available():
		return ""
	var root := Node.new()
	var lp := AKLivePlayer.new()
	lp.cue_map = AKCueMap.new()
	lp.cue_map.master_fx = []
	root.add_child(lp)
	var car := Node2D.new()
	car.name = "Car"
	root.add_child(car)
	var v := AKLiveVoice.new()
	v.live_player = lp
	v.shape = "sine"
	v.cutoff_hz = 0.0
	v.attack_s = 0.005
	v.bindings = [{param = "freq_hz", node = ^"../Car", property = "position:x", from = [0.0, 100.0], to = [100.0, 400.0], curve = "exp", glide_s = 0.01}]
	root.add_child(v)
	car.position.x = 50.0
	v.start()
	var a := lp.live.render_offline(SR)
	var hz := _hz(a, SR / 2, SR)
	if absf(hz - 200.0) > 3.0:
		root.free()
		return "voice at %.1f Hz for x = 50, wanted 200" % hz
	car.position.x = 100.0
	v.apply_bindings()
	var b := lp.live.render_offline(SR)
	hz = _hz(b, SR / 2, SR)
	v.stop(0.02)
	lp.live.render_offline(SR / 2)
	var left: int = lp.live.stream.voice_count()
	root.free()
	if absf(hz - 400.0) > 4.0:
		return "voice at %.1f Hz for x = 100, wanted 400" % hz
	return "" if left == 0 else "voice still running after stop"


func test_player_triggers_and_music() -> String:
	if not AKLive.available():
		return ""
	var lp := AKLivePlayer.new()
	lp.cue_map = load("res://demo/recipes/race_ident_map.tres")
	lp.song = load("res://demo/music/e1/e1_song.tres")
	lp.setup()
	var starts := []
	lp.section_started.connect(func(n: String) -> void: starts.append(n))
	lp.song_play(null, "full")
	lp.trigger(&"go")
	var out := lp.live.render_playing(SR)
	lp.free()
	if out.peak() < 0.05:
		return "the player made no sound"
	return "" if starts == ["full"] else "sections started: %s" % [starts]


func test_layer_weights() -> String:
	var ats := [1000.0, 3000.0, 6000.0]
	var w := AKLiveLayers.weights(ats, 500.0)
	if w[0].gain != 1.0 or w[1].gain != 0.0 or absf(w[0].rate - 0.5) > 1e-9:
		return "below the first layer it alone plays, slowed down"
	w = AKLiveLayers.weights(ats, sqrt(1000.0 * 3000.0))
	if absf(w[0].gain - w[1].gain) > 1e-9 or absf(w[0].gain * w[0].gain + w[1].gain * w[1].gain - 1.0) > 1e-9 or w[2].gain != 0.0:
		return "halfway (on a log scale) between two layers should be an equal-power split"
	w = AKLiveLayers.weights(ats, 9000.0, Vector2(0.5, 1.4))
	if w[2].gain != 1.0 or absf(w[2].rate - 1.4) > 1e-6:
		return "above the last layer it plays alone, its rate clamped"
	return ""


func test_layers_crossfade_live() -> String:
	if not AKLive.available():
		return ""
	var lp := AKLivePlayer.new()
	lp.cue_map = AKCueMap.new()
	lp.cue_map.master_fx = []
	lp.setup()
	var low := AKRecipe.make(&"tone")
	low.params = {freq_hz = 200.0, attack_s = 0.0, decay_s = 0.01, sustain = 1.0, gate_s = 1.0, release_s = 0.01, length_s = 1.0}
	var high := AKRecipe.make(&"tone")
	high.params = {freq_hz = 2000.0, attack_s = 0.0, decay_s = 0.01, sustain = 1.0, gate_s = 1.0, release_s = 0.01, length_s = 1.0}
	var layers := AKLiveLayers.new()
	layers.live_player = lp
	layers.layers = [{recipe = low, at = 1000.0}, {recipe = high, at = 4000.0}]
	layers.value = 1000.0
	layers.attack_s = 0.001
	layers.gain = 0.5
	lp.add_child(layers)
	layers.start()
	var a := lp.live.render_offline(SR)
	layers.value = 4000.0
	layers._apply(0.0)
	lp.live.render_offline(SR / 10)
	var b := lp.live.render_offline(SR)
	var ha := _hz(a, SR / 2, SR)
	var hb := _hz(b, SR / 2, SR)
	layers.stop(0.01)
	lp.free()
	if absf(ha - 200.0) > 4.0:
		return "at the low layer's value it should play alone at 200 Hz (%.0f)" % ha
	return "" if absf(hb - 2000.0) < 20.0 else "at the high layer's value it should play alone at 2000 Hz (%.0f)" % hb
