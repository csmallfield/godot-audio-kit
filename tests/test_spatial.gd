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


func test_doppler_factor() -> String:
	if AKSpatial.doppler_factor(0.0, 343.0) != 1.0:
		return "a still source has no shift"
	var toward := AKSpatial.doppler_factor(-34.3, 343.0)
	var away := AKSpatial.doppler_factor(34.3, 343.0)
	if absf(toward - 1.0 / 0.9) > 1e-6 or absf(away - 1.0 / 1.1) > 1e-6:
		return "10%% of the speed of sound should shift by c/(c±v): %f %f" % [toward, away]
	if AKSpatial.doppler_factor(-1000.0, 343.0) != 2.0 or AKSpatial.doppler_factor(34.3, 343.0, 0.0) != 1.0:
		return "clamped at double; amount 0 turns it off"
	return ""


func test_pitch_param_bends_voices() -> String:
	if not AKLive.available():
		return ""
	var live := AKLive.new()
	var m := AKCueMap.new()
	m.master_fx = []
	live.prepare([], m)
	var v := live.voice_start({shape = "sine", freq_hz = 400.0, gain = 0.5, attack_s = 0.001, pitch = 1.5})
	var out := live.render_offline(48000)
	var z := 0
	for i in range(24001, 48000):
		if (out.l[i - 1] < 0.0) != (out.l[i] < 0.0):
			z += 1
	live.voice_stop(v, 0.01)
	var hz := z / 2.0 / 0.5
	return "" if absf(hz - 600.0) < 6.0 else "pitch 1.5 on 400 Hz plays %.0f Hz" % hz


func test_occlusion_2d() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var root := Node2D.new()
	tree.root.add_child(root)
	var centre := AKSpatial.listener_2d(root.get_viewport())
	var emitter := Node2D.new()
	emitter.global_position = centre + Vector2(400, 0)
	root.add_child(emitter)
	var wall := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20, 400)
	shape.shape = rect
	wall.add_child(shape)
	wall.global_position = centre + Vector2(200, 0)
	root.add_child(wall)
	await tree.physics_frame
	await tree.physics_frame
	var blocked := AKSpatial.occluded(emitter, 1)
	wall.global_position = centre + Vector2(200, 1000)
	await tree.physics_frame
	await tree.physics_frame
	var open := AKSpatial.occluded(emitter, 1)
	# The source's own body never occludes it.
	var car := CharacterBody2D.new()
	var cs := CollisionShape2D.new()
	var circ := CircleShape2D.new()
	circ.radius = 30.0
	cs.shape = circ
	car.add_child(cs)
	car.global_position = centre + Vector2(400, 0)
	root.add_child(car)
	var engine := Node.new()
	car.add_child(engine)
	await tree.physics_frame
	await tree.physics_frame
	var own := AKSpatial.occluded(engine, 1)
	root.queue_free()
	if not blocked:
		return "a wall between listener and source should occlude it"
	if open:
		return "with the wall moved away it should be open"
	return "" if not own else "the source's own body occluded it"


func test_doppler_voice_passing_by() -> String:
	if not AKLive.available():
		return ""
	var tree := Engine.get_main_loop() as SceneTree
	var root := Node2D.new()
	tree.root.add_child(root)
	var lp := AKLivePlayer.new()
	lp.cue_map = AKCueMap.new()
	lp.cue_map.master_fx = []
	root.add_child(lp)
	var car := Node2D.new()
	root.add_child(car)
	var v := AKLiveVoice.new()
	v.live_player = lp
	v.shape = "sine"
	v.freq_hz = 500.0
	v.cutoff_hz = 0.0
	v.attack_s = 0.001
	v.spatial = "on"
	v.unit_size = 5000.0          # keep the level steady: only pitch should move
	v.max_distance = 100000.0
	v.doppler = 1.0
	v.speed_of_sound = 3000.0
	v.autostart = false
	car.add_child(v)
	var centre := AKSpatial.listener_2d(root.get_viewport())
	var speed := 600.0
	car.global_position = centre + Vector2(-3000, 0)
	v.start()
	var dt := 1.0 / 60.0
	for i in 30:   # approach at 600 px/s
		car.global_position.x += speed * dt
		v._process(dt)
	lp.live.render_offline(36000)   # the pitch glides (0.1 s): let it settle
	var a := lp.live.render_offline(24000)
	car.global_position = centre + Vector2(100, 0)
	v._last_dist = -1.0
	for i in 30:   # recede
		car.global_position.x += speed * dt
		v._process(dt)
	lp.live.render_offline(36000)
	var b := lp.live.render_offline(24000)
	root.queue_free()
	var ha := _hz(a)
	var hb := _hz(b)
	var want_a := 500.0 * 3000.0 / (3000.0 - speed)
	var want_b := 500.0 * 3000.0 / (3000.0 + speed)
	if absf(ha - want_a) > 8.0 or absf(hb - want_b) > 8.0:
		return "approaching %.0f Hz (want %.0f), receding %.0f Hz (want %.0f)" % [ha, want_a, hb, want_b]
	return ""


static func _hz(b: AKBuffer) -> float:
	var z := 0
	for i in range(1, b.frames()):
		if (b.l[i - 1] < 0.0) != (b.l[i] < 0.0):
			z += 1
	return z / 2.0 / (b.frames() / 48000.0)


func test_reverb_space_glides() -> String:
	if not AKLive.available():
		return ""
	var live := AKLive.new()
	var m := AKCueMap.new()
	m.master_fx = []
	m.reverb = {room = 0.5, damp = 0.5, width = 1.0, return_db = 0.0}
	live.prepare([], m)
	var r := AKRecipe.make(&"click")
	r.send = 1.0
	var tail := func() -> float:
		live.trigger(&"x", 1.0, {}, 0.0, _map_with(r, m))
		live.render_offline(9600)
		var t := live.render_offline(48000)
		var e := 0.0
		for i in t.frames():
			e += t.l[i] * t.l[i]
		return e
	var base: float = tail.call()
	live.set_reverb_space({room = 0.95, damp = 0.1, width = 1.0, return_db = 0.0}, 0.01)
	live.render_offline(48000 * 3)   # let the old tail die
	var big: float = tail.call()
	live.set_reverb_space({room = 0.5, damp = 0.5, width = 1.0, return_db = -60.0}, 0.01)
	live.render_offline(48000 * 6)
	var muted: float = tail.call()
	if base <= 0.0:
		return "the reverb didn't run without a timeline (sends were dropped)"
	if big < base * 2.0:
		return "a bigger room should leave a longer tail (%f vs %f)" % [big, base]
	return "" if muted < base * 0.01 else "return -60 dB should all but silence the wet (%f vs %f)" % [muted, base]


static func _map_with(r: AKRecipe, base: AKCueMap) -> AKCueMap:
	var m := base.duplicate()
	m.sounds = {"x": r}
	return m


func test_zone_follows_listener() -> String:
	if not AKLive.available():
		return ""
	var tree := Engine.get_main_loop() as SceneTree
	var root := Node2D.new()
	tree.root.add_child(root)
	var lp := AKLivePlayer.new()
	lp.cue_map = AKCueMap.new()
	root.add_child(lp)
	var centre := AKSpatial.listener_2d(root.get_viewport())
	var zone := AKReverbZone2D.new()
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(200, 200)
	cs.shape = rect
	zone.add_child(cs)
	zone.global_position = centre
	root.add_child(zone)
	var changes := []
	lp.zone_changed.connect(func(z: Node) -> void: changes.append(z))
	for i in 3:
		await tree.physics_frame
	var inside := lp.current_zone
	zone.global_position = centre + Vector2(5000, 0)
	for i in 3:
		await tree.physics_frame
	var outside := lp.current_zone
	root.queue_free()
	if inside != zone:
		return "the listener is inside the zone but the player didn't follow it"
	return "" if outside == null and changes.size() == 2 else "leaving the zone should return to the default (%s, %d changes)" % [outside, changes.size()]
