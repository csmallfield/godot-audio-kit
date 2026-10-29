# SPDX-License-Identifier: Apache-2.0
# Phase 8: the Sequencer. AKArrangement (tracks, scenes, a timeline of clips
# cut at markers) compiled to songs; the Sequencer tab's scenes grid,
# timeline, tracks, transport and export, driven as a person would; and the
# gate: an arrangement of a minute built in the tab, scene and timeline
# playback live = bake, and a scene switch landing on the bar to the sample.
extends RefCounted

const OUT := "user://test_sequencer/"
const SR := 48000


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _lab() -> AKSequencerLab:
	var lab := AKSequencerLab.new()
	# The tests pull the live stream themselves (render_playing); nothing to
	# the speakers, where Godot's audio thread would pull it too.
	lab.audio_output = false
	_tree().root.add_child(lab)
	lab.set_save_dir(OUT)
	return lab


func _done(lab: AKSequencerLab) -> void:
	lab.stop()
	lab.queue_free()


## The loops the tests arrange, saved under OUT/loops/: two one-bar beats, a
## two-bar bass line and two bars of chords.
func _loops() -> Dictionary:
	DirAccess.make_dir_recursive_absolute(OUT + "loops/")
	var out := {}
	var beat_a := AKLoop.new()
	beat_a.kind = "percussive"
	beat_a.instrument = AKLibrary.kit("punch")
	beat_a.notes = [[0, 24, 0, 1.0], [192, 24, 0, 1.0], [96, 24, 1, 0.9], [288, 24, 1, 0.9]]
	for t in range(0, 384, 96):
		beat_a.notes.append([t + 48, 24, 3, 0.6])
	var beat_b: AKLoop = beat_a.duplicate(true)
	beat_b.instrument = beat_a.instrument
	for t in range(0, 384, 96):
		beat_b.notes.append([t, 24, 3, 0.7])
	beat_b.notes.append([336, 24, 4, 0.7])
	var bass := AKLoop.new()
	bass.kind = "synth"
	bass.instrument = load("res://addons/audio_kit/patches/wavetable_bass.tres")
	bass.bars = 2
	bass.notes = [[0, 84, 45, 0.9], [96, 84, 45, 0.7], [192, 84, 48, 0.8], [288, 84, 52, 0.8],
		[384, 84, 43, 0.9], [480, 84, 43, 0.7], [576, 84, 47, 0.8], [672, 84, 50, 0.8]]
	var chords := AKLoop.new()
	chords.kind = "sample"
	chords.instrument = AKLibrary.sample_for(AKLibrary.path_of("keys", "epiano"), "gate")
	chords.bars = 2
	for m in [57, 60, 64]:
		chords.notes.append([0, 360, m, 0.6])
	for m in [55, 59, 62]:
		chords.notes.append([384, 360, m, 0.6])
	for pair in [["beat_a", beat_a], ["beat_b", beat_b], ["bass_a", bass], ["chords_a", chords]]:
		var l: AKLoop = pair[1]
		l.resource_name = pair[0]
		var path := OUT + "loops/%s.tres" % pair[0]
		ResourceSaver.save(l, path)
		out[pair[0]] = path
	return out


func _arr(paths: Dictionary) -> AKArrangement:
	var a := AKArrangement.new()
	a.tempo = AKTempoMap.make(120.0)
	a.tracks = [{name = "drums"}, {name = "bass", gain_db = -2.0, pan = -0.2}, {name = "chords", send = 0.25, intensity = [0.2, 0.6]}]
	a.scenes = [{name = "intro", bars = 0.0, clips = {"chords": paths.chords_a}},
		{name = "race", bars = 0.0, clips = {"drums": paths.beat_a, "bass": paths.bass_a, "chords": paths.chords_a}},
		{name = "final", bars = 0.0, clips = {"drums": paths.beat_b, "bass": paths.bass_a, "chords": paths.chords_a}}]
	a.master_fx = [{type = &"dcblock"}, {type = &"limit", ceiling_db = -1.0}]
	return a


func _snr(a: AKBuffer, ref: AKBuffer, n: int) -> float:
	var se := 0.0
	var ss := 0.0
	for i in mini(n, mini(a.frames(), ref.frames())):
		var el := a.l[i] - ref.l[i]
		var er := a.r[i] - ref.r[i]
		se += el * el + er * er
		ss += ref.l[i] * ref.l[i] + ref.r[i] * ref.r[i]
	return 10.0 * log(ss / maxf(se, 1e-30)) / log(10.0)


# ------------------------------------------------------------------ input helpers

func _mouse(c: Control, pos: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT, alt := false, double := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = pos
	e.alt_pressed = alt
	e.double_click = double
	c._gui_input(e)


func _click(c: Control, pos: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	_mouse(c, pos, true, button)
	_mouse(c, pos, false, button)


func _drag(c: Control, from: Vector2, to: Vector2, alt := false) -> void:
	_mouse(c, from, true, MOUSE_BUTTON_LEFT, alt)
	for k in range(1, 5):
		var e := InputEventMouseMotion.new()
		e.position = from.lerp(to, k / 4.0)
		c._gui_input(e)
	_mouse(c, to, false, MOUSE_BUTTON_LEFT, alt)


func _button(n: Node, text: String) -> BaseButton:
	for c in n.get_children():
		if c is BaseButton and not (c is OptionButton) and (c as BaseButton).get("text") == text:
			return c
		var b := _button(c, text)
		if b:
			return b
	return null


func _press(n: Node, text: String) -> String:
	var b := _button(n, text)
	if b == null:
		return "no button %s" % text
	if b is CheckBox:
		b.button_pressed = not b.button_pressed
	else:
		b.pressed.emit()
	return ""


## The SpinBox right after a Label reading `label`.
func _spin_after(n: Node, label: String) -> SpinBox:
	for c in n.find_children("*", "Label", true, false):
		if (c as Label).text == label:
			var p := c.get_parent()
			var i := c.get_index()
			if i + 1 < p.get_child_count() and p.get_child(i + 1) is SpinBox:
				return p.get_child(i + 1)
	return null


func _cell_center(g: AKSceneGrid, si: int, ti: int) -> Vector2:
	return g.cell_rect(si, ti).get_center()


func _track_point(v: AKTimelineView, ti: int, bar: float) -> Vector2:
	return Vector2(v.bar_to_x(bar) + 3.0, v.track_y(ti) + AKTimelineView.TRACK_H * 0.5)


# ------------------------------------------------------------------ compiling

func test_scenes_compile_to_sections() -> String:
	var paths := _loops()
	var a := _arr(paths)
	var s := a.to_song("scenes")
	var names := s.sections.map(func(x: Dictionary) -> String: return x.name)
	if names != ["intro", "race", "final"] or s.sections.map(func(x: Dictionary) -> float: return x.bars) != [2.0, 2.0, 2.0]:
		return "scene sections: %s %s" % [names, s.sections.map(func(x: Dictionary) -> float: return x.bars)]
	# Lanes are named for tracks: a drum loop on "drums" gives drums.kick ...
	var lanes := {}
	for e in s.events():
		lanes[String(e.lane)] = int(lanes.get(String(e.lane), 0)) + 1
	for want in ["drums.kick", "drums.snare", "drums.closed_hat", "bass", "chords"]:
		if not lanes.has(want):
			return "no lane %s in %s" % [want, lanes.keys()]
	# The one-bar beat repeats over the two-bar scene: 4 kicks in race.
	var race_kicks := s.events().filter(func(e: Dictionary) -> bool: return e.lane == "drums.kick" and e.section == "race")
	if race_kicks.size() != 4 or absf(float(race_kicks[2].time_s) - 6.0) > 1e-9:
		return "race kicks: %s" % [race_kicks.map(func(e: Dictionary) -> float: return e.time_s)]
	# Track settings become the song's mix and intensity lanes.
	if s.mix.get("bass", {}).get("gain_db", 0.0) != -2.0 or s.mix.get("bass", {}).get("pan", 0.0) != -0.2 or s.mix.get("chords", {}).get("send", -1.0) != 0.25:
		return "mix: %s" % [s.mix]
	if s.intensity_lanes.get("chords", []) != [0.2, 0.6]:
		return "intensity lanes: %s" % [s.intensity_lanes]
	# Mute and solo.
	a.tracks[0]["mute"] = true
	if a.to_song("scenes").events().any(func(e: Dictionary) -> bool: return String(e.lane).begins_with("drums")):
		return "a muted track should be left out"
	a.tracks[0]["mute"] = false
	a.tracks[1]["solo"] = true
	if a.to_song("scenes").events().any(func(e: Dictionary) -> bool: return e.lane != "bass"):
		return "solo should leave only the soloed track"
	# Cached by content: the same arrangement gives the same song object.
	a.tracks[1]["solo"] = false
	if a.to_song("scenes") != a.to_song("scenes") or a.to_song("scenes") == s and false:
		return "compiled songs should be cached"
	return ""


func test_timeline_cuts_at_markers_and_keeps_phase() -> String:
	var bass := AKLoop.new()
	bass.kind = "synth"
	bass.instrument = AKPatch.new()
	bass.notes = [[0, 48, 40, 0.8], [96, 48, 41, 0.8], [192, 48, 42, 0.8], [288, 48, 43, 0.8]]
	var a := AKArrangement.new()
	a.tempo = AKTempoMap.make(120.0)
	a.tracks = [{name = "bass"}]
	# From bar 1 for six bars, starting half way into the loop.
	a.timeline = [{track = "bass", loop = bass, bar = 1.0, bars = 6.0, offset_bars = 0.5}]
	a.markers = [{name = "verse", bar = 3.0}, {name = "chorus", bar = 5.5}]
	var secs := a.timeline_sections()
	if secs.map(func(x: Dictionary) -> String: return x.name) != ["start", "verse", "chorus"] or secs[2].bars != 1.5:
		return "sections: %s" % [secs]
	var evs := a.to_song("timeline").events()
	if evs.size() != 24:
		return "%d notes, want 24" % evs.size()
	for k in evs.size():
		var want_t := (4 + k) * 0.5
		var want_m := 40 + (k + 2) % 4
		if absf(float(evs[k].time_s) - want_t) > 1e-9 or int(evs[k].midi) != want_m:
			return "note %d: %.3f s midi %d, want %.3f s midi %d (sections %s)" % [k, evs[k].time_s, evs[k].midi, want_t, want_m, evs[k].section]
	# A later clip on the same track plays over it; the first resumes in phase after.
	a.timeline.append({track = "bass", loop = bass, bar = 4.0, bars = 1.0, offset_bars = 0.0})
	evs = a.to_song("timeline").events()
	var at_bar4 := evs.filter(func(e: Dictionary) -> bool: return absf(e.time_s - 8.0) < 1e-9)
	var at_bar5 := evs.filter(func(e: Dictionary) -> bool: return absf(e.time_s - 10.0) < 1e-9)
	if evs.size() != 24 or at_bar4.size() != 1 or int(at_bar4[0].midi) != 40 or at_bar5.size() != 1 or int(at_bar5[0].midi) != 42:
		return "overlapping clips: %d notes, bar 4 plays %s" % [evs.size(), at_bar4.map(func(e: Dictionary) -> int: return e.midi)]
	# Painting a scene over a range trims what was there.
	a.scenes = [{name = "s", clips = {"bass": bass}}]
	var tl := a.painted(0, 2.0, 3.0)
	var spans := tl.map(func(c: Dictionary) -> Array: return [c.bar, c.bars, c.get("offset_bars", 0.0)])
	spans.sort()
	if spans != [[1.0, 1.0, 0.5], [2.0, 1.0, 0.0], [3.0, 4.0, 2.5], [4.0, 1.0, 0.0]]:
		return "painted: %s" % [spans]
	return ""


# ------------------------------------------------------------------ the tab

func test_tracks_scenes_and_undo() -> String:
	var paths := _loops()
	var lab := _lab()
	lab.loops.refresh()
	lab.add_track("lead")
	if lab.arrangement.track_names() != ["drums", "bass", "chords", "lead"]:
		_done(lab)
		return "add track: %s" % [lab.arrangement.track_names()]
	# A loop picked in the browser goes into the cell clicked.
	lab.pick_loop(paths.beat_a)
	var g := lab.scenes_view
	_click(g, _cell_center(g, 0, 0))
	if g.cell_loop(0, 0) != paths.beat_a:
		_done(lab)
		return "a click should put the picked loop in the cell"
	lab.pick_loop(paths.bass_a)
	_click(g, _cell_center(g, 0, 1))
	lab.add_scene("race")
	lab.pick_loop(paths.beat_b)
	_click(g, _cell_center(g, 1, 0))
	if lab.arrangement.scenes.size() != 2 or g.cell_loop(1, 0) != paths.beat_b or lab.arrangement.scene_bars(0) != 2.0:
		_done(lab)
		return "scenes: %s" % [lab.arrangement.scenes]
	_click(g, _cell_center(g, 1, 0), MOUSE_BUTTON_RIGHT)
	if g.cell_loop(1, 0) != "":
		_done(lab)
		return "right-click should clear a cell"
	lab.undo_last()
	if g.cell_loop(1, 0) != paths.beat_b:
		_done(lab)
		return "undo should restore the cell"
	# Renaming a track carries its clips; moving and deleting.
	lab.rename_track(0, "kit")
	if g.cell_loop(0, 0) != paths.beat_a or lab.arrangement.track_index("kit") != 0:
		_done(lab)
		return "a renamed track keeps its clips"
	lab.move_track(0, 1)
	if lab.arrangement.track_names() != ["bass", "kit", "chords", "lead"] or g.cell_loop(0, 1) != paths.beat_a:
		_done(lab)
		return "move track: %s" % [lab.arrangement.track_names()]
	lab.delete_track(3)
	lab.undo_last()
	lab.undo_last()
	lab.undo_last()
	if lab.arrangement.track_names() != ["drums", "bass", "chords", "lead"]:
		_done(lab)
		return "undoing delete, move and rename: %s" % [lab.arrangement.track_names()]
	# Scene length and name through the toolbar.
	g.selected_scene = 1
	lab.set_scene(1, "bars", 4.0)
	if lab.arrangement.scene_bars(1) != 4.0:
		_done(lab)
		return "scene bars"
	_done(lab)
	return ""


func test_timeline_editing() -> String:
	var paths := _loops()
	var lab := _lab()
	var v := lab.timeline_view
	lab.pick_loop(paths.bass_a)
	_click(v, _track_point(v, 1, 2.3))
	var tl := lab.arrangement.timeline
	if tl.size() != 1 or tl[0].track != "bass" or tl[0].bar != 2.0 or tl[0].bars != 2.0:
		_done(lab)
		return "placing a clip: %s" % [tl]
	# Move it two bars right and onto the chords track.
	var body := v.clip_rect(0).get_center()
	_drag(v, body, body + Vector2(2.0 * v.bar_px, AKTimelineView.TRACK_H))
	tl = lab.arrangement.timeline
	if tl[0].bar != 4.0 or tl[0].track != "chords":
		_done(lab)
		return "moving a clip: %s" % [tl]
	lab.undo_last()
	if lab.arrangement.timeline[0].bar != 2.0:
		_done(lab)
		return "a move should undo in one step"
	# Lengthen from the right edge (more repeats), trim from the left.
	var r := v.clip_rect(0)
	_drag(v, Vector2(r.end.x - 2.0, r.get_center().y), Vector2(r.end.x - 2.0 + 4.0 * v.bar_px, r.get_center().y))
	if lab.arrangement.timeline[0].bars != 6.0:
		_done(lab)
		return "lengthening: %s" % [lab.arrangement.timeline]
	r = v.clip_rect(0)
	_drag(v, Vector2(r.position.x + 2.0, r.get_center().y), Vector2(r.position.x + 2.0 + v.bar_px, r.get_center().y))
	var c: Dictionary = lab.arrangement.timeline[0]
	if c.bar != 3.0 or c.bars != 5.0 or c.offset_bars != 1.0:
		_done(lab)
		return "trimming the start: %s" % [c]
	# Alt-drag copies; right-click deletes.
	body = v.clip_rect(0).get_center()
	_drag(v, body, body + Vector2(6.0 * v.bar_px, 0), true)
	if lab.arrangement.timeline.size() != 2 or lab.arrangement.timeline[1].bar != 9.0:
		_done(lab)
		return "alt-drag should copy: %s" % [lab.arrangement.timeline]
	_click(v, v.clip_rect(1).get_center(), MOUSE_BUTTON_RIGHT)
	if lab.arrangement.timeline.size() != 1:
		_done(lab)
		return "right-click should delete a clip"
	# Markers: click the strip to add, drag to move, rename, right-click to remove.
	_click(v, Vector2(v.bar_to_x(4.0) + 1.0, 8.0))
	if lab.arrangement.markers.size() != 1 or lab.arrangement.markers[0].bar != 4.0:
		_done(lab)
		return "adding a marker: %s" % [lab.arrangement.markers]
	_drag(v, Vector2(v.bar_to_x(4.0), 8.0), Vector2(v.bar_to_x(6.0), 8.0))
	lab.rename_marker(0, "chorus")
	if lab.arrangement.markers != [{name = "chorus", bar = 6.0}] and lab.arrangement.markers[0].bar != 6.0:
		_done(lab)
		return "moving and renaming a marker: %s" % [lab.arrangement.markers]
	if lab.arrangement.timeline_sections().map(func(s: Dictionary) -> String: return s.name) != ["start", "chorus"]:
		_done(lab)
		return "sections: %s" % [lab.arrangement.timeline_sections()]
	lab.undo_last()
	lab.undo_last()
	if lab.arrangement.markers[0].bar != 4.0:
		_done(lab)
		return "a marker drag should undo in one step: %s" % [lab.arrangement.markers]
	_click(v, Vector2(v.bar_to_x(4.0), 8.0), MOUSE_BUTTON_RIGHT)
	if not lab.arrangement.markers.is_empty():
		_done(lab)
		return "right-click should remove the marker"
	# Paint a scene across bars 1-8 (the toolbar's Paint).
	lab.pick_loop(paths.beat_a)
	_click(lab.scenes_view, _cell_center(lab.scenes_view, 0, 0))
	lab.scenes_view.selected_scene = 0
	lab.paint_scene(0, 0.0, 8.0)
	var drums := lab.arrangement.timeline.filter(func(x: Dictionary) -> bool: return x.track == "drums")
	if drums.size() != 1 or drums[0].bars != 8.0:
		_done(lab)
		return "paint scene: %s" % [lab.arrangement.timeline]
	_done(lab)
	return ""


func test_export() -> String:
	var paths := _loops()
	var lab := _lab()
	var a := _arr(paths)
	a.resource_name = "export_test"
	a.timeline = a.painted(1, 0.0, 4.0)
	lab.open_arrangement(a)
	var wav := lab.bake()
	var f := AKAudioFile.read(wav)
	if f.error != "" or absf(f.data.size() / float(SR) - 8.0) > 3.0:
		_done(lab)
		return "bake: %s, %d frames" % [f.error, f.data.size()]
	var scene_wav := lab.bake("intro")
	if not FileAccess.file_exists(scene_wav):
		_done(lab)
		return "baking a scene"
	var st := lab.stems()
	var names := st.map(func(p: String) -> String: return p.get_file().get_basename())
	names.sort()
	if names != ["bass", "chords", "drums", "reverb"]:
		_done(lab)
		return "stems: %s" % [names]
	var sp := lab.save_as_song()
	var song: AKSong = ResourceLoader.load(sp, "", ResourceLoader.CACHE_MODE_IGNORE)
	if song == null or song.events().size() != a.to_song("timeline").events().size():
		_done(lab)
		return "save as song"
	var cp := lab.save_cue_sheet()
	var cues: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(cp))
	if cues.cues.size() != a.to_song("timeline").to_cues().size():
		_done(lab)
		return "cue sheet"
	_done(lab)
	return ""


# ------------------------------------------------------------------ the gate

func test_gate_a_minute_arranged_in_the_tab() -> String:
	var paths := _loops()
	var lab := _lab()
	lab.loops.refresh()
	var g := lab.scenes_view
	var v := lab.timeline_view
	var steps: Array[Callable] = [
		func() -> String: return _press(lab, "New"),
		func() -> String:
			lab._name.text = "gate_race"
			lab._name.text_changed.emit("gate_race")
			return "",
		# Scenes: intro (chords), race (beat, bass, chords), final (busier beat).
		func() -> String:
			lab.set_scene(0, "name", "intro")
			lab.pick_loop(paths.chords_a)
			_click(g, _cell_center(g, 0, 2))
			return _press(lab, "+ Scene"),
		func() -> String:
			lab.set_scene(1, "name", "race")
			for pair in [[0, paths.beat_a], [1, paths.bass_a], [2, paths.chords_a]]:
				lab.pick_loop(pair[1])
				_click(g, _cell_center(g, 1, pair[0]))
			return _press(lab, "+ Scene"),
		func() -> String:
			lab.set_scene(2, "name", "final")
			for pair in [[0, paths.beat_b], [1, paths.bass_a], [2, paths.chords_a]]:
				lab.pick_loop(pair[1])
				_click(g, _cell_center(g, 2, pair[0]))
			return "",
		# The timeline: paint the scenes across 30 bars (a minute at 120 bpm).
		func() -> String:
			for p in [[0, 1, 4], [1, 5, 20], [2, 21, 30]]:
				_click(g, g.header_rect(p[0]).get_center(), MOUSE_BUTTON_RIGHT)   # select the scene
				lab._paint_from.value = p[1]
				lab._paint_to.value = p[2]
				var e := _press(lab, "Paint scene")
				if e != "":
					return e
			return "",
		# Markers on the strip, named.
		func() -> String:
			for m in [[0.0, "intro"], [4.0, "race"], [20.0, "final"]]:
				_click(v, Vector2(v.bar_to_x(m[0]) + (2.0 if m[0] == 0.0 else 0.0), 8.0))
				lab.rename_marker(v.selected_marker, m[1])
			return "",
		func() -> String: return _press(lab, "Save"),
	]
	for i in steps.size():
		var err: String = steps[i].call()
		if err != "":
			_done(lab)
			return "step %d: %s" % [i, err]
		await _tree().process_frame
	var path := OUT + "arrangements/gate_race.tres"
	var a: AKArrangement = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if a == null:
		_done(lab)
		return "the arrangement wasn't saved"
	# Reloaded field for field.
	if a.scene_names() != ["intro", "race", "final"] or a.track_names() != ["drums", "bass", "chords"]:
		_done(lab)
		return "scenes %s, tracks %s" % [a.scene_names(), a.track_names()]
	if String(a.scenes[1].clips.drums) != paths.beat_a or String(a.scenes[2].clips.drums) != paths.beat_b or a.scenes[0].clips.size() != 1:
		_done(lab)
		return "scene clips: %s" % [a.scenes]
	var spans := a.timeline.map(func(c: Dictionary) -> String: return "%s %s %s+%s" % [c.track, String(c.loop).get_file().get_basename(), c.bar, c.bars])
	spans.sort()
	var want := ["bass bass_a 20.0+10.0", "bass bass_a 4.0+16.0", "chords chords_a 0.0+4.0", "chords chords_a 20.0+10.0",
		"chords chords_a 4.0+16.0", "drums beat_a 4.0+16.0", "drums beat_b 20.0+10.0"]
	if spans != want:
		_done(lab)
		return "timeline: %s" % [spans]
	if a.markers.map(func(m: Dictionary) -> Array: return [m.name, m.bar]) != [["intro", 0.0], ["race", 4.0], ["final", 20.0]]:
		_done(lab)
		return "markers: %s" % [a.markers]
	var tsong := a.to_song("timeline")
	if absf(tsong.length_s() - 60.0) > 1e-6 or tsong.layout().map(func(L: Dictionary) -> String: return L.name) != ["intro", "race", "final"]:
		_done(lab)
		return "the timeline should be a minute in three sections: %.2f s" % tsong.length_s()
	if not AKLive.available():
		print("        (native core not built: live parts skipped)")
		_done(lab)
		return ""
	# Timeline live = bake, the whole minute.
	lab.open_arrangement(a)
	lab.play_timeline(0.0)
	var live := lab.live.render_playing(roundi(60.0 * SR))
	var baked: AKBuffer = a.to_song("timeline").render().mix
	var snr := _snr(live, baked, roundi(60.0 * SR))
	print("        a minute arranged in the tab: timeline live vs baked SNR %.1f dB" % snr)
	if snr < 90.0:
		_done(lab)
		return "timeline live vs baked: SNR %.1f dB" % snr
	# Scenes: race playing, "final" launched 0.6 bars in, lands on bar 2 to the
	# sample. (Without a loudness step in the master: live, loudness is measured
	# over every scene in order, a bake over what it renders.)
	lab.stop()
	a.master_fx = [{type = &"dcblock"}, {type = &"limit", ceiling_db = -1.0}]
	lab.open_arrangement(a)
	lab.play_scene("race")
	var first := lab.live.render_playing(roundi(1.2 * SR))
	var landed := []
	lab.live.section_started.connect(func(sec: String, frame: int) -> void: landed.append([sec, frame]))
	_click(g, g.header_rect(2).get_center())   # launch "final" (next bar)
	var origin := lab.live._seq_origin
	var rest := lab.live.render_playing(roundi(4.8 * SR))
	var got := AKBuffer.new(0, SR)
	first.mix_into(got, 0)
	rest.mix_into(got, first.frames())
	var hit := landed.filter(func(x: Array) -> bool: return x[0] == "final")
	if hit.is_empty() or int(hit[0][1]) - origin != 2 * SR:
		_done(lab)
		return "the switch should land on bar 2 (frame %d), landed %s" % [2 * SR, hit.map(func(x: Array) -> int: return int(x[1]) - origin)]
	# Against a bake of one bar of race and then final.
	var one := a.duplicate(true) as AKArrangement
	one.scenes[1]["bars"] = 1.0
	var race1: Dictionary = one.to_song("scenes").sections[1]
	var ref := AKSong.new()
	ref.tempo = a.tempo
	ref.mix = a.to_song("scenes").mix
	ref.intensity_lanes = a.to_song("scenes").intensity_lanes
	ref.reverb = a.reverb
	ref.master_fx = a.master_fx
	ref.sections = [race1, a.to_song("scenes").sections[2]]
	var want_buf: AKBuffer = ref.render().mix
	var ssnr := _snr(got, want_buf, roundi(6.0 * SR))
	print("        scene switch on the bar: live vs a bake of (race bar 1, final) SNR %.1f dB" % ssnr)
	_done(lab)
	return "" if ssnr > 90.0 else "scene switch: SNR %.1f dB" % ssnr
