# SPDX-License-Identifier: Apache-2.0
# Phase 9: the mixer and track effects. A track's insert chain runs on its
# lanes' sum, baked (AKSong.render, AKStreamFx) and live (the track's AKLive
# bus, ak::Fx); the Sequencer's mixer edits levels, pan, send, mute, solo,
# intensity ranges, inserts and the master. The gate: each effect on a track
# sounds the same live and baked (float rounding), and 10 tracks with two
# effects each stay under 10% of a core.
extends RefCounted

const OUT := "user://test_mixer/"
const SR := 48000
## A setting of each effect that does something to a drum and bass mix.
const SPECS := {
	chorus = {type = "chorus", rate_hz = 1.3, depth_ms = 4.0, mix = 0.5},
	flanger = {type = "flanger", rate_hz = 0.4, feedback = 0.7, mix = 0.5},
	phaser = {type = "phaser", rate_hz = 0.7, stages = 6, feedback = 0.5, mix = 0.6},
	eq = {type = "eq", low_db = 6.0, mid_db = -4.0, mid_hz = 700.0, high_db = 5.0},
	compressor = {type = "compressor", threshold_db = -28.0, ratio = 8.0, attack_s = 0.003, release_s = 0.08, makeup_db = 6.0},
	saturate = {type = "saturate", drive_db = 18.0, tone_hz = 5000.0, asymmetry = 0.3},
}


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _loops() -> Dictionary:
	DirAccess.make_dir_recursive_absolute(OUT + "loops/")
	var beat := AKLoop.new()
	beat.kind = "percussive"
	beat.instrument = AKLibrary.kit("punch")
	beat.notes = [[0, 24, 0, 1.0], [192, 24, 0, 1.0], [96, 24, 1, 0.9], [288, 24, 1, 0.9], [336, 24, 4, 0.7]]
	for t in range(0, 384, 48):
		if t != 336:
			beat.notes.append([t, 24, 3, 0.6])
	var bass := AKLoop.new()
	bass.kind = "synth"
	bass.instrument = load("res://addons/audio_kit/patches/wavetable_bass.tres")
	bass.notes = [[0, 84, 45, 0.9], [96, 84, 48, 0.7], [192, 84, 43, 0.8], [288, 84, 47, 0.8]]
	var keys := AKLoop.new()
	keys.kind = "sample"
	keys.instrument = AKLibrary.sample_for(AKLibrary.path_of("keys", "epiano"), "gate")
	keys.bars = 2
	for m in [57, 60, 64]:
		keys.notes.append([0, 360, m, 0.6])
	for m in [55, 59, 62]:
		keys.notes.append([384, 360, m, 0.6])
	var out := {}
	for pair in [["beat", beat], ["bass", bass], ["keys", keys]]:
		var l: AKLoop = pair[1]
		l.resource_name = pair[0]
		var path := OUT + "loops/%s.tres" % pair[0]
		ResourceSaver.save(l, path)
		out[pair[0]] = path
	return out


## Drums and bass on a timeline of `bars`; `fx` on the drums track, an EQ on the bass.
func _arr(paths: Dictionary, fx: Array, bars := 4.0) -> AKArrangement:
	var a := AKArrangement.new()
	a.tempo = AKTempoMap.make(120.0)
	a.tracks = [{name = "drums", fx = fx, gain_db = -2.0, send = 0.15}, {name = "bass", fx = [SPECS.eq], pan = -0.2}]
	a.timeline = [{track = "drums", loop = paths.beat, bar = 0.0, bars = bars}, {track = "bass", loop = paths.bass, bar = 0.0, bars = bars}]
	a.master_fx = [{type = &"dcblock"}, {type = &"limit", ceiling_db = -1.0}]
	return a


func _live_render(song: AKSong, frames: int) -> AKBuffer:
	var live := AKLive.new()
	var m := AKCueMap.new()
	m.master_fx = song.master_fx
	m.reverb = song.reverb
	live.prepare([], m, 30.0, 0.0, song, true)
	live.song_play(song, &"song")
	return live.render_playing(frames)


static func _snr(a: AKBuffer, ref: AKBuffer, n: int) -> float:
	var se := 0.0
	var ss := 0.0
	for i in mini(n, mini(a.frames(), ref.frames())):
		var el := a.l[i] - ref.l[i]
		var er := a.r[i] - ref.r[i]
		se += el * el + er * er
		ss += ref.l[i] * ref.l[i] + ref.r[i] * ref.r[i]
	return 10.0 * log(ss / maxf(se, 1e-30)) / log(10.0)


# ------------------------------------------------------------------ compiling and baking

func test_track_fx_compile_and_bake() -> String:
	var paths := _loops()
	var a := _arr(paths, [SPECS.compressor, SPECS.chorus])
	var s := a.to_song("timeline")
	if s.group_of("drums.kick") != "drums" or s.group_of("bass") != "bass" or s.fx_of("drums").size() != 2:
		return "groups %s, fx %s" % [s.lane_groups, s.group_fx]
	# The bake runs the drums' lanes together through the chain: their stem
	# is one "music.drums", equal to the dry lanes' sum through AKStreamFx.
	var wet := s.render(true, false)
	var dry_a := _arr(paths, [])
	var dry := dry_a.to_song("timeline").render(true, false)
	if not wet.stems.has("music.drums") or wet.stems.has("music.drums.kick"):
		return "stems: %s" % [wet.stems.keys()]
	var sum := AKBuffer.new(0, SR)
	for k: String in dry.stems:
		if k.begins_with("music.drums."):
			(dry.stems[k] as AKBuffer).mix_into(sum, 0)
	sum.resize(wet.stems["music.drums"].frames())
	var lr := AKStreamFx.process([SPECS.compressor, SPECS.chorus], sum.l, sum.r, SR)
	var want := AKBuffer.new(0, SR)
	want.l = lr[0]
	want.r = lr[1]
	var snr := _snr(wet.stems["music.drums"], want, want.frames())
	if snr < 120.0:
		return "the drums stem should be the dry lanes through the chain: SNR %.1f dB" % snr
	# The compressor did compress, and the chain changed the bake key.
	if wet.stems["music.drums"].peak() >= sum.peak() * AKDsp.db_to_gain(6.0) * 0.99:
		return "the compressor should hold the drum peaks down"
	if s.key() == dry_a.to_song("timeline").key():
		return "track effects should change the song's key"
	return ""


# ------------------------------------------------------------------ the gate

func test_gate_each_effect_live_equals_baked() -> String:
	if not AKLive.available():
		print("        (native core not built: skipped)")
		return ""
	var paths := _loops()
	var worst := INF
	var line := []
	for t in SPECS:
		var a := _arr(paths, [SPECS[t]])
		# A track faded by intensity as well, so the fader's place (before the
		# inserts, as the bake's note levels are) is checked too.
		a.tracks[0]["intensity"] = [0.0, 1.0]
		a.intensity = 0.7
		var s := a.to_song("timeline")
		var baked: AKBuffer = s.render().mix
		var live := _live_render(s, baked.frames())
		var snr := _snr(live, baked, baked.frames())
		line.append("%s %.0f" % [t, snr])
		worst = minf(worst, snr)
		if snr < 100.0:
			return "%s on a track, live vs baked: SNR %.1f dB" % [t, snr]
	print("        each effect on a track, live vs baked (dB): %s" % ", ".join(line))
	return ""


func test_gate_ten_tracks_two_effects_under_ten_percent() -> String:
	if not AKLive.available():
		print("        (native core not built: skipped)")
		return ""
	var paths := _loops()
	var pairs := [["compressor", "eq"], ["chorus", "saturate"], ["phaser", "eq"], ["flanger", "compressor"], ["eq", "saturate"],
		["compressor", "chorus"], ["saturate", "phaser"], ["eq", "flanger"], ["chorus", "compressor"], ["phaser", "saturate"]]
	var a := AKArrangement.new()
	a.tempo = AKTempoMap.make(120.0)
	a.master_fx = [{type = &"dcblock"}, {type = &"limit", ceiling_db = -1.0}]
	var loops := [paths.beat, paths.bass, paths.keys]
	for i in 10:
		a.tracks.append({name = "t%d" % i, fx = [SPECS[pairs[i][0]], SPECS[pairs[i][1]]], gain_db = -10.0})
		a.timeline.append({track = "t%d" % i, loop = loops[i % 3], bar = 0.0, bars = 2.0})
	a.markers = [{name = "loop", bar = 0.0}]
	var s := a.to_song("timeline")
	var live := AKLive.new()
	var m := AKCueMap.new()
	m.master_fx = s.master_fx
	live.prepare([], m)
	live.song_play(s, &"loop")
	live.render_playing(roundi(4.0 * SR))   # the first pass renders and caches every note
	var secs := 8.0
	var t0 := Time.get_ticks_usec()
	var out := live.render_playing(roundi(secs * SR))
	var used := (Time.get_ticks_usec() - t0) / 1e6
	var share := used / secs
	print("        10 tracks with two effects each: %.1f%% of a core (%.0f ms for %.0f s)" % [share * 100.0, used * 1000.0, secs])
	if out.peak() < 0.05:
		return "the ten tracks are silent"
	return "" if share < 0.10 else "10 tracks x 2 effects take %.1f%% of a core" % (share * 100.0)


# ------------------------------------------------------------------ the mixer in the tab

func _lab() -> AKSequencerLab:
	var lab := AKSequencerLab.new()
	lab.audio_output = false   # the tests pull the live stream themselves
	_tree().root.add_child(lab)
	lab.set_save_dir(OUT)
	return lab


func _strip(lab: AKSequencerLab, name: String) -> Node:
	return lab.mixer.find_child("strip_" + name, true, false)


func test_mixer_strips_edit_the_tracks() -> String:
	var paths := _loops()
	var lab := _lab()
	lab.open_arrangement(_arr(paths, []))
	var mx := lab.mixer
	var drums := _strip(lab, "drums")
	if drums == null or _strip(lab, "bass") == null or _strip(lab, "master") == null:
		lab.queue_free()
		return "a strip per track and a master strip"
	# The fader: a drag of three steps is one undo step.
	var fader := drums.find_child("level", true, false) as VSlider
	for v in [-4.0, -6.0, -9.5]:
		fader.value = v
	if float(lab.arrangement.tracks[0].gain_db) != -9.5:
		lab.queue_free()
		return "the fader should set the level: %s" % [lab.arrangement.tracks[0]]
	lab.undo_last()
	if float(lab.arrangement.tracks[0].get("gain_db", 0.0)) != -2.0:
		lab.queue_free()
		return "a fader drag should undo in one step: %s" % [lab.arrangement.tracks[0]]
	(drums.find_child("pan", true, false) as AKParamSlider).set_value_from_user(0.4)
	(drums.find_child("send", true, false) as AKParamSlider).set_value_from_user(0.3)
	(lab.mixer.find_child("strip_bass", true, false).find_child("M", true, false) as Button).button_pressed = true
	var t0: Dictionary = lab.arrangement.tracks[0]
	if absf(float(t0.pan) - 0.4) > 1e-6 or absf(float(t0.send) - 0.3) > 1e-6 or not bool(lab.arrangement.tracks[1].get("mute", false)):
		lab.queue_free()
		return "pan, send, mute: %s %s" % [t0, lab.arrangement.tracks[1]]
	var s := lab.arrangement.to_song("timeline")
	if s.events().any(func(e: Dictionary) -> bool: return e.lane == "bass") or absf(float(s.mix["drums.kick"].pan) - 0.4) > 1e-6:
		lab.queue_free()
		return "the compiled song should follow the mixer"
	# Solo, and the intensity range.
	(_strip(lab, "drums").find_child("S", true, false) as Button).button_pressed = true
	(_strip(lab, "drums").find_child("intensity_on", true, false) as CheckBox).button_pressed = true
	if not bool(lab.arrangement.tracks[0].get("solo", false)) or lab.arrangement.tracks[0].get("intensity", []) != [0.3, 0.7]:
		lab.queue_free()
		return "solo and intensity: %s" % [lab.arrangement.tracks[0]]
	await _tree().process_frame
	(_strip(lab, "drums").find_child("to", true, false) as AKParamSlider).set_value_from_user(0.9)
	if lab.arrangement.tracks[0].intensity != [0.3, 0.9]:
		lab.queue_free()
		return "intensity to: %s" % [lab.arrangement.tracks[0].intensity]
	# Inserts: FX opens the chain; add a compressor and set its ratio.
	(_strip(lab, "drums").find_child("fx", true, false) as Button).pressed.emit()
	mx.fx_editor.add("compressor")
	mx.fx_editor.add("chorus")
	mx.fx_editor.sliders()["0.ratio"].set_value_from_user(8.0)
	mx.fx_editor.move(1, -1)
	var fx: Array = lab.arrangement.tracks[0].get("fx", [])
	if fx.size() != 2 or fx[0].type != "chorus" or fx[1].type != "compressor" or float(fx[1].ratio) != 8.0:
		lab.queue_free()
		return "the insert chain: %s" % [fx]
	if lab.arrangement.to_song("timeline").fx_of("drums").size() != 2:
		lab.queue_free()
		return "the inserts should reach the song"
	mx.fx_editor.remove(0)
	lab.undo_last()
	if lab.arrangement.tracks[0].fx.size() != 2:
		lab.queue_free()
		return "removing an insert should undo"
	# The master strip: its chain and the shared reverb.
	(_strip(lab, "master").find_child("fx", true, false) as Button).pressed.emit()
	mx.fx_editor.add("eq")
	(_strip(lab, "master").find_child("room", true, false) as AKParamSlider).set_value_from_user(0.8)
	if lab.arrangement.master_fx.size() != 3 or lab.arrangement.master_fx[2].type != "eq" or absf(float(lab.arrangement.reverb.room) - 0.8) > 1e-6:
		lab.queue_free()
		return "master chain and reverb: %s %s" % [lab.arrangement.master_fx, lab.arrangement.reverb]
	# Saved and reloaded with everything.
	lab._name.text = "mixed"
	lab._name.text_changed.emit("mixed")
	var path := lab.save_arrangement()
	var back: AKArrangement = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if back.tracks[0].fx.size() != 2 or back.tracks[0].intensity != [0.3, 0.9] or not bool(back.tracks[1].mute) or back.master_fx.size() != 3:
		lab.queue_free()
		return "saved: %s" % [back.tracks]
	lab.queue_free()
	return ""


func test_meters_and_live_insert_edits() -> String:
	if not AKLive.available():
		print("        (native core not built: skipped)")
		return ""
	var paths := _loops()
	var lab := _lab()
	lab.open_arrangement(_arr(paths, [SPECS.compressor]))
	lab._views.current_tab = 2
	lab.play_timeline(0.0)
	lab.live.render_playing(roundi(0.6 * SR))
	var lv := lab.live.levels()
	lab.mixer.set_levels(lv)
	if lab.mixer.meter("drums").l <= 0.01 or lab.mixer.meter("master").l <= 0.01 or not lv.has("bass"):
		lab.stop()
		lab.queue_free()
		return "meters: %s" % [lv]
	# An insert edited while playing reaches the track's bus.
	lab.mixer.show_fx(0)
	lab.mixer.fx_editor.sliders()["0.threshold_db"].set_value_from_user(-40.0)
	var bus := lab.live.lane_bus("drums", lab.song)
	var on_bus: Array = lab.live._bus_fx.get(bus, [])
	lab.stop()
	lab.queue_free()
	if on_bus.size() != 1 or float(on_bus[0].threshold_db) != -40.0:
		return "the live insert should follow the edit: %s" % [on_bus]
	return ""
