# SPDX-License-Identifier: Apache-2.0
# AKSpatial: distance, pan and air absorption; and positional live voices.
extends RefCounted

const S := {unit_size = 100.0, max_distance = 2000.0}


func test_attenuation_curves() -> String:
	if absf(AKSpatial.attenuate(50.0, S) - 1.0) > 1e-6:
		return "inside unit_size should be full level"
	if absf(AKSpatial.attenuate(200.0, S) - 0.5) > 1e-6:
		return "inverse at twice unit_size should be half (%f)" % AKSpatial.attenuate(200.0, S)
	var sq := S.duplicate()
	sq.attenuation = "inverse_square"
	if absf(AKSpatial.attenuate(200.0, sq) - 0.25) > 1e-6:
		return "inverse square at twice unit_size should be a quarter"
	if AKSpatial.attenuate(2000.0, S) != 0.0 or AKSpatial.attenuate(1900.0, S) >= AKSpatial.attenuate(1700.0, S):
		return "the edge of the range should fade to silence"
	var last := 2.0
	for d in range(0, 2100, 50):
		var g := AKSpatial.attenuate(float(d), S)
		if g > last + 1e-9:
			return "level rises with distance at %d" % d
		last = g
	return ""


func test_pan_and_air() -> String:
	var r := AKSpatial.compute_2d(Vector2(500, 300), Vector2(500 + 288, 300), S, 576.0)
	if absf(r.pan - 0.5) > 1e-6:
		return "2D pan %f, wanted 0.5" % r.pan
	var l3 := Transform3D(Basis(), Vector3.ZERO)
	var right := AKSpatial.compute_3d(l3, Vector3(10, 0, 0), {unit_size = 1.0, max_distance = 100.0})
	var ahead := AKSpatial.compute_3d(l3, Vector3(0, 0, -10), {unit_size = 1.0, max_distance = 100.0})
	if right.pan < 0.7 or absf(ahead.pan) > 1e-6:
		return "3D pan: right %f, ahead %f" % [right.pan, ahead.pan]
	var turned := AKSpatial.compute_3d(Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO), Vector3(10, 0, 0), {unit_size = 1.0, max_distance = 100.0})
	if turned.pan > -0.7:
		return "turning the listener around should swap sides (%f)" % turned.pan
	var air := {max_distance = 1000.0, air_absorption = 1.0}
	if absf(AKSpatial.air_cutoff(1000.0, air, 10000.0) - 1000.0) > 1e-3 or AKSpatial.air_cutoff(0.0, air, 10000.0) != 10000.0:
		return "air absorption should take the cutoff down a decade over the range"
	return ""


func test_positional_voice() -> String:
	if not AKLive.available():
		return ""
	var tree := Engine.get_main_loop() as SceneTree
	var root := Node2D.new()
	tree.root.add_child(root)
	var lp := AKLivePlayer.new()
	lp.cue_map = AKCueMap.new()
	lp.cue_map.master_fx = []
	lp.autoplay_song = false
	root.add_child(lp)
	var emitter := Node2D.new()
	root.add_child(emitter)
	var v := AKLiveVoice.new()
	v.live_player = lp
	v.shape = "sine"
	v.cutoff_hz = 0.0
	v.gain = 0.5
	v.attack_s = 0.001
	v.spatial = "on"
	v.autostart = false
	emitter.add_child(v)
	var centre := AKSpatial.listener_2d(root.get_viewport())
	emitter.global_position = centre
	v.start()
	var near := lp.live.render_offline(4800)
	emitter.global_position = centre + Vector2(400, 0)   # 4 units right
	v.apply_bindings(0.0)
	lp.live.render_offline(2400)
	var far := lp.live.render_offline(4800)
	v.stop(0.01)
	root.queue_free()
	# Equal-power panning keeps l² + r², so compare power, not one channel's peak.
	var ratio := sqrt(_power(far) / maxf(_power(near), 1e-12))
	if absf(ratio - 0.25) > 0.02:
		return "4 units away the level is %.2f of near, wanted about 0.25" % ratio
	var lr := 0.0
	var rr := 0.0
	for i in far.frames():
		lr = maxf(lr, absf(far.l[i]))
		rr = maxf(rr, absf(far.r[i]))
	return "" if rr > lr * 1.5 else "a source to the right should pan right (l %.3f, r %.3f)" % [lr, rr]


static func _power(b: AKBuffer) -> float:
	var p := 0.0
	for i in b.frames():
		p += b.l[i] * b.l[i] + b.r[i] * b.r[i]
	return p / maxf(1.0, b.frames())
