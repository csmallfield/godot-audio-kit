# SPDX-License-Identifier: Apache-2.0
## The Sound Lab's Sequencer tab: arrange loops on tracks, as scenes a game
## switches between and as a timeline for a fixed piece, both compiled to
## the same kind of AKSong, so either plays live or bakes.
##
##   Left       the project's loops: pick one, then click a scene cell or an
##              empty stretch of a track to place it
##   Transport  name, New, open, Save; Play, Stop, a loop range; tempo and
##              meter; where the music is; when a scene switch lands (bar,
##              beat, or the end of the scene)
##   Scenes     a column per scene, a cell per track; click a scene to launch
##              it; Paint writes a scene's clips across a bar range of the
##              timeline
##   Timeline   clips on tracks, markers naming the sections; drag to move,
##              lengthen, trim; Alt-drag copies
##   Mixer      a strip per track (meter, level, pan, send, mute, solo,
##              intensity range, insert effects) and the master (meter,
##              intensity, the shared reverb, the master chain)
##   Tracks     add, rename, reorder, delete
##   Export     Bake (the timeline or the selected scene), Stems (a WAV per
##              track), Save as song, Cue sheet
##
## Every edit is undoable and joins the editor's history. Double-click a
## clip or cell to edit its loop in the Loops tab with the rest playing
## around it. Arrangements save to res://audio/arrangements/<name>.tres.
@tool
class_name AKSequencerLab
extends HSplitContainer

## Edit this loop in the Loops tab, with `context` (other loops) around it at `bpm`.
signal open_loop(path: String, context: Array, bpm: float)
## The arrangement's tempo (the Loops tab follows it).
signal tempo_changed(bpm: float)

const SAVE_DIR := "res://audio/"
const QUANTIZE := ["bar", "beat", "section"]
const QUANTIZE_LABELS := ["next bar", "next beat", "end of scene"]

var arrangement: AKArrangement
var arrangement_path := ""
var save_dir := SAVE_DIR
var undo: Object
var loops: AKLoopBrowser
var scenes_view: AKSceneGrid
var timeline_view: AKTimelineView
var live: AKLive
var player: AudioStreamPlayer
## "scenes" or "timeline": what's playing (or "" when stopped).
var playing := ""
## The song playing (a copy the sequencer updates in place on edits).
var song: AKSong
var quantize := "bar"
var loop_range := false
var range_from := 0.0
var range_to := 4.0
var last_saved := ""

var _own_undo: UndoRedo
var _status: Label
var _name: LineEdit
var _arr_list: OptionButton
var _arr_paths: Array = []
var _tempo: SpinBox
var _meter: SpinBox
var _pos: Label
var _views: TabContainer
var _scene_name: LineEdit
var _scene_bars: SpinBox
var _paint_from: SpinBox
var _paint_to: SpinBox
var _marker_name: LineEdit
var _tracks_box: VBoxContainer
var _pending: Label
var _quiet := false
var _play_origin_bar := 0.0
var _last_props: Array = []
var mixer: AKMixerView


func _init() -> void:
	name = "Sequencer"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_own_undo = UndoRedo.new()
	undo = _own_undo
	if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		undo = Engine.get_singleton(&"EditorInterface").call(&"get_editor_undo_redo")
	player = AudioStreamPlayer.new()
	add_child(player)
	if AKLive.available():
		live = AKLive.new()
		live.lookahead_s = 0.3
		player.stream = live.stream
		live.section_started.connect(_on_section_started)
	_build()
	new_arrangement()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _own_undo:
		_own_undo.free()


## Off: nothing is sent to the speakers (tests pull the live stream
## themselves with render_playing).
var audio_output := true


func _ready() -> void:
	_start_output()


## The live stream plays through `player` from the first Play on.
func _start_output() -> void:
	if live and audio_output and is_inside_tree() and not player.playing:
		player.play()


func _process(_delta: float) -> void:
	if live:
		live.update()
	if playing != "" and is_visible_in_tree():
		_show_position()
		if live and mixer.is_visible_in_tree():
			mixer.set_levels(live.levels())


func set_save_dir(dir: String) -> void:
	save_dir = dir if dir.ends_with("/") else dir + "/"
	loops.folders = [save_dir + "loops/"]
	loops.refresh()
	_fill_arrangements()


# ------------------------------------------------------------------ documents

## Start a new arrangement: three tracks (drums, bass, chords), one scene, 120 bpm.
func new_arrangement() -> AKArrangement:
	var a := AKArrangement.new()
	a.resource_name = "new_arrangement"
	a.tempo = AKTempoMap.make(120.0)
	a.tracks = [{name = "drums"}, {name = "bass"}, {name = "chords"}]
	a.scenes = [{name = "scene 1", bars = 0.0, clips = {}}]
	arrangement_path = ""
	_set_arrangement(a)
	_say("New arrangement: pick a loop on the left, then click a scene cell or a track in the timeline.")
	return a


func open_arrangement(v: Variant) -> AKArrangement:
	var a: AKArrangement = v if v is AKArrangement else (ResourceLoader.load(String(v), "", ResourceLoader.CACHE_MODE_REUSE) as AKArrangement if ResourceLoader.exists(String(v)) else null)
	if a == null:
		_say("Not an arrangement: %s" % v)
		return null
	arrangement_path = a.resource_path
	_set_arrangement(a)
	_say("Arrangement: %s" % arrangement_path)
	return a


## Import an Auxy project ("Export for Bitwig Studio", .axbw): its loops,
## drum kits, stems and an arrangement go under save_dir, then it opens.
## See AKAuxy.
func import_auxy(path: String, options := {}) -> AKArrangement:
	var res := AKAuxy.import_file(path, save_dir, options)
	if not res.ok:
		_say("Auxy import failed: %s" % res.error)
		return null
	loops.refresh()
	_fill_arrangements()
	open_arrangement(res.arrangement)
	var msg := "Imported %s: %d tracks, %d loops, %d scenes, %d bars, %d stems" % [path.get_file(), res.arrangement.tracks.size(),
		res.loops.size(), res.arrangement.scenes.size(), int(res.arrangement.length_bars), res.stems.size()]
	if not res.warnings.is_empty():
		msg += " (%d warnings: %s)" % [res.warnings.size(), "; ".join(res.warnings)]
	_say(msg)
	return res.arrangement


func _pick_auxy() -> void:
	var d := FileDialog.new()
	d.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.filters = PackedStringArray(["*.axbw ; Auxy \"Export for Bitwig Studio\""])
	d.title = "Import an Auxy project"
	d.file_selected.connect(func(p: String) -> void:
		import_auxy(p)
		d.queue_free())
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered_ratio(0.6)


func save_arrangement() -> String:
	var base := _name.text.strip_edges().validate_filename()
	if base == "":
		base = "arrangement"
	var path := save_dir + "arrangements/" + base + ".tres"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	arrangement.resource_name = base
	if ResourceSaver.save(arrangement, path) != OK:
		_say("Couldn't save %s" % path)
		return ""
	if arrangement.resource_path != path:
		arrangement.take_over_path(path)
	arrangement_path = path
	last_saved = path
	AK.refresh_editor_files()
	_fill_arrangements()
	_say("Saved %s" % path)
	return path


# ------------------------------------------------------------------ editing (undoable)

## One undoable edit of the arrangement's properties; `merge` joins a
## slider drag's steps into one.
func commit(props: Dictionary, label: String, merge := false) -> void:
	var a := arrangement
	var action := "Sequencer: " + label
	var mode := UndoRedo.MERGE_ENDS if merge else UndoRedo.MERGE_DISABLE
	_last_props = props.keys()
	if undo == null:
		for k in props:
			a.set(k, props[k])
		_after_edit()
	elif undo is UndoRedo:
		undo.create_action(action, mode)
		for k in props:
			undo.add_do_property(a, k, props[k])
			undo.add_undo_property(a, k, _copy(a.get(k)))
		undo.add_do_method(_after_edit)
		undo.add_undo_method(_after_edit)
		undo.commit_action()
	else:
		undo.call(&"create_action", action, mode, a)
		for k in props:
			undo.call(&"add_do_property", a, k, props[k])
			undo.call(&"add_undo_property", a, k, _copy(a.get(k)))
		undo.call(&"add_do_method", self, &"_after_edit")
		undo.call(&"add_undo_method", self, &"_after_edit")
		undo.call(&"commit_action")


func undo_last() -> void:
	if undo is UndoRedo:
		undo.undo()


func redo_last() -> void:
	if undo is UndoRedo:
		undo.redo()


func add_track(track_name := "") -> void:
	var t := _typed(arrangement.tracks)
	var n := track_name if track_name != "" else "track %d" % (t.size() + 1)
	while arrangement.track_index(n) >= 0:
		n += "+"
	t.append({name = n})
	commit({tracks = t}, "Add track")


## Rename a track; its clips and scene cells follow.
func rename_track(ti: int, new_name: String) -> void:
	new_name = new_name.strip_edges()
	var old := String(arrangement.tracks[ti].get("name", ""))
	if new_name == "" or new_name == old or arrangement.track_index(new_name) >= 0:
		return
	var t := _typed(arrangement.tracks)
	t[ti]["name"] = new_name
	var tl := _typed(arrangement.timeline)
	for c in tl:
		if String(c.track) == old:
			c["track"] = new_name
	var sc := _typed(arrangement.scenes)
	for s in sc:
		var clips: Dictionary = s.get("clips", {})
		for k in clips.keys():
			if String(k) == old:
				clips[new_name] = clips[k]
				clips.erase(k)
	commit({tracks = t, timeline = tl, scenes = sc}, "Rename track")


func move_track(ti: int, by: int) -> void:
	var j := ti + by
	if j < 0 or j >= arrangement.tracks.size():
		return
	var t := _typed(arrangement.tracks)
	var x: Dictionary = t[ti]
	t[ti] = t[j]
	t[j] = x
	commit({tracks = t}, "Move track")


## Delete a track with its clips.
func delete_track(ti: int) -> void:
	var n := String(arrangement.tracks[ti].get("name", ""))
	var t := _typed(arrangement.tracks)
	t.remove_at(ti)
	var tl := _typed(arrangement.timeline).filter(func(c: Dictionary) -> bool: return String(c.track) != n)
	var tl2: Array[Dictionary] = []
	tl2.assign(tl)
	var sc := _typed(arrangement.scenes)
	for s in sc:
		var clips: Dictionary = s.get("clips", {})
		clips.erase(n)
		clips.erase(StringName(n))
	commit({tracks = t, timeline = tl2, scenes = sc}, "Delete track")


func add_scene(scene_name := "") -> void:
	var sc := _typed(arrangement.scenes)
	var n := scene_name if scene_name != "" else "scene %d" % (sc.size() + 1)
	while arrangement.scene_index(n) >= 0:
		n += "+"
	sc.append({name = n, bars = 0.0, clips = {}})
	scenes_view.selected_scene = sc.size() - 1
	commit({scenes = sc}, "Add scene")


func set_scene(si: int, key: String, value: Variant) -> void:
	if si < 0 or si >= arrangement.scenes.size():
		return
	var sc := _typed(arrangement.scenes)
	sc[si][key] = value
	commit({scenes = sc}, "Scene " + key)


func delete_scene(si: int) -> void:
	var sc := _typed(arrangement.scenes)
	sc.remove_at(si)
	scenes_view.selected_scene = -1
	commit({scenes = sc}, "Delete scene")


## Write scene `si`'s clips across bars [from_bar, to_bar) of the timeline.
func paint_scene(si: int, from_bar: float, to_bar: float) -> void:
	if si < 0 or to_bar <= from_bar:
		return
	commit({timeline = arrangement.painted(si, from_bar, to_bar)}, "Paint scene")


func add_marker(marker_name: String, bar: float) -> void:
	var ms := _typed(arrangement.markers)
	ms.append({name = marker_name, bar = bar})
	commit({markers = ms}, "Add marker")


func rename_marker(mi: int, marker_name: String) -> void:
	if mi < 0 or mi >= arrangement.markers.size() or marker_name.strip_edges() == "":
		return
	var ms := _typed(arrangement.markers)
	ms[mi]["name"] = marker_name.strip_edges()
	commit({markers = ms}, "Rename marker")


func set_tempo(bpm: float, beats_per_bar := -1) -> void:
	var t: AKTempoMap = arrangement.tempo.duplicate()
	t.bpm = clampf(bpm, 20.0, 400.0)
	if beats_per_bar > 0:
		t.beats_per_bar = beats_per_bar
	commit({tempo = t}, "Tempo")


## The loop picked in the browser, placed by the next click on a cell or track.
func pick_loop(path: String) -> void:
	scenes_view.pending_loop = path
	timeline_view.pending_loop = path
	if _pending:
		_pending.text = "placing: " + path.get_file().get_basename() if path != "" else ""


static func _copy(v: Variant) -> Variant:
	if v is Array or v is Dictionary:
		return v.duplicate(true)
	if v is Resource:
		return v
	return v


static func _typed(a: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d in a:
		out.append((d as Dictionary).duplicate(true))
	return out


func _after_edit() -> void:
	scenes_view.refresh()
	timeline_view.refresh()
	mixer.refresh()
	_sync_toolbar()
	_build_tracks()
	if playing == "":
		return
	if _last_props.has("master_fx"):
		# The live master chain is built when playing starts: start again.
		if playing == "scenes":
			play_scene(maxi(0, scenes_view.playing_scene))
		else:
			play_timeline(_play_origin_bar)
		return
	if _last_props.has("reverb") and live:
		live.set_reverb_space(arrangement.reverb, 0.2)
	_recompile()


# ------------------------------------------------------------------ playing

## Launch a scene: start the scenes playing there, or switch on the next
## bar (or beat, or the scene's end: `quantize`) if they're playing.
func play_scene(scene: Variant, q := "") -> void:
	var si := scene if scene is int else arrangement.scene_index(String(scene))
	if si < 0 or si >= arrangement.scenes.size():
		return
	var name := String(arrangement.scenes[si].name)
	if playing == "scenes" and live:
		live.song_queue(name, StringName(q if q != "" else quantize))
		scenes_view.queued_scene = si
		_say("Scene %s on the %s" % [name, QUANTIZE_LABELS[QUANTIZE.find(q if q != "" else quantize)]])
		return
	stop()
	song = _song_copy(arrangement.to_song("scenes"))
	playing = "scenes"
	if live:
		_prepare()
		live.song_play(song, &"loop", name)
	else:
		_play_baked(_section_song(song, si))
	scenes_view.playing_scene = si
	_say("Playing scene %s%s" % [name, "" if live else " (baked)"])


## Play the timeline from the start of the section holding `from_bar` (or
## loop the bar range, when `loop_range` is on).
func play_timeline(from_bar := -1.0) -> void:
	stop()
	var src := arrangement
	if loop_range and range_to > range_from:
		src = arrangement.duplicate(true)
		src.markers = [{name = "loop", bar = range_from}]
		src.length_bars = range_to
	var s := src.to_song("timeline")
	song = _song_copy(s)
	playing = "timeline"
	var start := ""
	var fb := from_bar if from_bar >= 0.0 else maxf(0.0, timeline_view.playhead_bar)
	if loop_range:
		start = "loop"
		fb = range_from
	else:
		for L in song.layout():
			if float(L.start_bar) <= fb + 1e-6:
				start = String(L.name)
				fb = float(L.start_bar)
	_play_origin_bar = fb
	if live:
		_prepare()
		live.song_play(song, &"loop" if loop_range else &"song", start)
	else:
		_play_baked(song, song.tempo.bar_to_seconds(fb))
	_say("Playing the timeline%s" % (" (bars %s-%s, looped)" % [range_from + 1, range_to] if loop_range else ""))


func stop() -> void:
	if live:
		live.song_stop(&"now")
		live.stream.clear()
	elif player.playing:
		player.stop()
	playing = ""
	scenes_view.playing_scene = -1
	scenes_view.queued_scene = -1
	timeline_view.playhead_bar = -1.0


func _prepare() -> void:
	_start_output()
	var m := AKCueMap.new()
	m.master_fx = song.master_fx
	m.reverb = song.reverb
	live.prepare([], m, 30.0, 0.0, song, true)


## Re-compile after an edit and let the live sequencer re-derive the notes
## not yet sounding.
func _recompile() -> void:
	if playing == "" or song == null:
		return
	if not live:
		if playing == "scenes":
			play_scene(maxi(0, scenes_view.playing_scene))
		else:
			play_timeline(_play_origin_bar)
		return
	var src := arrangement
	if playing == "timeline" and loop_range and range_to > range_from:
		src = arrangement.duplicate(true)
		src.markers = [{name = "loop", bar = range_from}]
		src.length_bars = range_to
	var s := src.to_song(playing)
	song.sections = s.sections
	song.mix = s.mix
	song.intensity_lanes = s.intensity_lanes
	song.lane_groups = s.lane_groups
	song.group_fx = s.group_fx
	song.tempo = s.tempo
	live.song_changed()


func _song_copy(s: AKSong) -> AKSong:
	var c := AKSong.new()
	c.tempo = s.tempo
	c.sections = s.sections.duplicate()
	c.mix = s.mix.duplicate(true)
	c.reverb = s.reverb.duplicate(true)
	c.master_fx = s.master_fx.duplicate(true)
	c.stingers = s.stingers.duplicate(true)
	c.intensity_lanes = s.intensity_lanes.duplicate(true)
	c.lane_groups = s.lane_groups.duplicate(true)
	c.group_fx = s.group_fx.duplicate(true)
	c.intensity = s.intensity
	c.gain_db = s.gain_db
	return c


## A song of one section of `s` (a scene alone).
func _section_song(s: AKSong, si: int) -> AKSong:
	var c := _song_copy(s)
	c.sections = [s.sections[si]]
	return c


func _play_baked(s: AKSong, from_s := 0.0) -> void:
	var buf: AKBuffer = s.render().mix
	var st := buf.to_stream()
	if playing == "scenes" or loop_range:
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_end = mini(buf.frames(), roundi(s.length_s() * AK.sample_rate))
	player.stream = st
	if player.is_inside_tree():
		player.play(from_s)


func _on_section_started(section: String, _frame: int) -> void:
	if playing == "scenes":
		var si := arrangement.scene_index(section)
		scenes_view.playing_scene = si
		if scenes_view.queued_scene == si:
			scenes_view.queued_scene = -1


func _show_position() -> void:
	if not live or song == null:
		return
	var p := live.song_position()
	if p.is_empty():
		return
	var bar := float(p.bar) + float(p.beat) / maxf(1.0, float(song.tempo.beats_per_bar))
	if playing == "timeline":
		for L in song.layout():
			if String(L.name) == String(p.section):
				bar += float(L.start_bar)
				break
		timeline_view.playhead_bar = bar
	if _pos:
		_pos.text = "%s  bar %d.%d" % [p.section, int(bar) + 1, int(p.beat) + 1]


# ------------------------------------------------------------------ export

## Bake the timeline ("" scene) or one scene to save_dir/renders/<name>[_scene].wav.
func bake(scene := "") -> String:
	var s := _export_song(scene)
	var path := save_dir + "renders/%s%s.wav" % [_base(), "_" + scene.validate_filename() if scene != "" else ""]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := AK.save_wav(s.render().mix, path)
	_say("Baked %s" % path if err == OK else "Couldn't bake %s" % path)
	return path if err == OK else ""


## A WAV per track (the shared reverb as its own), beside the bake.
func stems(scene := "") -> Array:
	var s := _export_song(scene)
	var out: Dictionary = s.render(true)
	var by_track := {}
	for k: String in out.stems:
		var lane := k.trim_prefix("music.")
		var track := "reverb" if lane == "reverb" else lane
		for t in arrangement.track_names():
			if lane == t or lane.begins_with(t + "."):
				track = t
		if not by_track.has(track):
			by_track[track] = AKBuffer.new(0, AK.sample_rate)
		(out.stems[k] as AKBuffer).mix_into(by_track[track], 0)
	var paths := []
	for t in by_track:
		var path := save_dir + "renders/%s_stems/%s.wav" % [_base(), String(t).validate_filename()]
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		if AK.save_wav(by_track[t], path) == OK:
			paths.append(path)
	_say("Wrote %d stems to %srenders/%s_stems/" % [paths.size(), save_dir, _base()])
	return paths


## Save the compiled timeline as an AKSong (save_dir/songs/<name>.tres).
func save_as_song(mode := "timeline") -> String:
	var s := _song_copy(arrangement.to_song(mode))
	var path := save_dir + "songs/%s.tres" % _base()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := ResourceSaver.save(s, path)
	AK.refresh_editor_files()
	_say("Saved the song %s" % path if err == OK else "Couldn't save %s" % path)
	return path if err == OK else ""


## The timeline's notes and sections as a cue sheet (save_dir/cues/<name>.json).
func save_cue_sheet(fps := 30.0) -> String:
	var s := arrangement.to_song("timeline")
	var path := save_dir + "cues/%s.json" % _base()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify({fps = fps, duration = s.length_s(), cues = s.to_cues(fps)}, "\t"))
	f.close()
	AK.refresh_editor_files()
	_say("Wrote the cue sheet %s" % path)
	return path


func _export_song(scene: String) -> AKSong:
	if scene != "":
		var full := arrangement.to_song("scenes")
		return _section_song(full, arrangement.scene_index(scene))
	return arrangement.to_song("timeline")


func _base() -> String:
	var b := String(arrangement.resource_name).validate_filename()
	return b if b != "" else "arrangement"


# ------------------------------------------------------------------ loops tab link

## Open a timeline clip's loop for editing, with the clips sounding around it.
func edit_clip(ci: int) -> void:
	var c: Dictionary = arrangement.timeline[ci]
	var ctx := []
	for j in arrangement.timeline.size():
		var d: Dictionary = arrangement.timeline[j]
		if j != ci and float(d.bar) < float(c.bar) + float(c.bars) and float(d.bar) + float(d.bars) > float(c.bar):
			var l := AKArrangement.loop_of(d.loop)
			if l and not ctx.has(l):
				ctx.append(l)
	open_loop.emit(AKTimelineView._loop_path(c.loop), ctx, arrangement.tempo.bpm)


## Open a scene cell's loop, the rest of the scene around it.
func edit_cell(si: int, track: String) -> void:
	var clips: Dictionary = arrangement.scenes[si].get("clips", {})
	var ctx := []
	var path := ""
	for t in clips:
		var l := AKArrangement.loop_of(clips[t])
		if String(t) == track:
			path = l.resource_path if l else ""
		elif l:
			ctx.append(l)
	open_loop.emit(path, ctx, arrangement.tempo.bpm)


# ------------------------------------------------------------------ building

func _set_arrangement(a: AKArrangement) -> void:
	stop()
	arrangement = a
	scenes_view.set_arrangement(a)
	timeline_view.set_arrangement(a)
	mixer.set_arrangement(a)
	_sync_toolbar()
	_build_tracks()
	tempo_changed.emit(a.tempo.bpm)


func _sync_toolbar() -> void:
	if _tempo == null or arrangement == null:
		return
	_quiet = true
	if _name.text.strip_edges() != String(arrangement.resource_name):
		_name.text = String(arrangement.resource_name)
	if not is_equal_approx(_tempo.value, arrangement.tempo.bpm):
		_tempo.set_value_no_signal(arrangement.tempo.bpm)
		tempo_changed.emit(arrangement.tempo.bpm)
	_meter.set_value_no_signal(arrangement.tempo.beats_per_bar)
	var si := scenes_view.selected_scene
	if si >= 0 and si < arrangement.scenes.size():
		if _scene_name.text != String(arrangement.scenes[si].name):
			_scene_name.text = String(arrangement.scenes[si].name)
		_scene_bars.set_value_no_signal(float(arrangement.scenes[si].get("bars", 0.0)))
	var mi := timeline_view.selected_marker
	if mi >= 0 and mi < arrangement.markers.size() and _marker_name.text != String(arrangement.markers[mi].name):
		_marker_name.text = String(arrangement.markers[mi].name)
	_quiet = false


func _fill_arrangements() -> void:
	if _arr_list == null:
		return
	_arr_list.clear()
	_arr_paths.clear()
	_arr_list.add_item("(open)")
	_arr_paths.append("")
	var dir := save_dir + "arrangements/"
	if DirAccess.dir_exists_absolute(dir):
		var fs := Array(DirAccess.get_files_at(dir))
		fs.sort()
		for f: String in fs:
			f = f.trim_suffix(".remap")
			if f.ends_with(".tres"):
				_arr_list.add_item(f.get_basename())
				_arr_paths.append(dir + f)


func _build() -> void:
	loops = AKLoopBrowser.new()
	loops.custom_minimum_size = Vector2(200, 0)
	loops.folders = [save_dir + "loops/"]
	loops.refresh()
	loops.loop_selected.connect(pick_loop)
	add_child(loops)
	var centre := VBoxContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(centre)

	var bar := HFlowContainer.new()
	centre.add_child(bar)
	_name = LineEdit.new()
	_name.placeholder_text = "arrangement name"
	_name.custom_minimum_size = Vector2(140, 0)
	_name.text_changed.connect(func(t: String) -> void:
		if arrangement and not _quiet:
			arrangement.resource_name = t.strip_edges())
	bar.add_child(_name)
	_button(bar, "New", func() -> void: new_arrangement())
	_arr_list = OptionButton.new()
	_arr_list.tooltip_text = "Open an arrangement"
	_arr_list.item_selected.connect(func(i: int) -> void:
		if i > 0:
			open_arrangement(_arr_paths[i]))
	bar.add_child(_arr_list)
	_fill_arrangements()
	_button(bar, "Save", save_arrangement)
	_button(bar, "Import Auxy…", _pick_auxy).tooltip_text = "An Auxy project exported with \"Export for Bitwig Studio\" (.axbw)"
	_button(bar, "Play", func() -> void:
		if _views.current_tab == 0:
			play_scene(maxi(0, scenes_view.selected_scene))
		else:
			play_timeline())
	_button(bar, "Stop", stop)
	var lr := CheckBox.new()
	lr.text = "Loop bars"
	lr.toggled.connect(func(on: bool) -> void: loop_range = on)
	bar.add_child(lr)
	var rf := _spin(bar, "", 1, 1, 999, 1, func(v: float) -> void: range_from = v - 1.0)
	rf.tooltip_text = "Loop from bar"
	var rt := _spin(bar, "to", 4, 1, 999, 1, func(v: float) -> void: range_to = v)
	rt.tooltip_text = "Loop to the end of bar"
	_tempo = _spin(bar, "", 120, 20, 400, 1, func(v: float) -> void:
		if not _quiet:
			set_tempo(v))
	_tempo.suffix = "bpm"
	_tempo.custom_minimum_size = Vector2(96, 0)
	_meter = _spin(bar, "", 4, 1, 16, 1, func(v: float) -> void:
		if not _quiet:
			set_tempo(arrangement.tempo.bpm, int(v)))
	_meter.suffix = "/4"
	_pos = Label.new()
	_pos.custom_minimum_size = Vector2(120, 0)
	bar.add_child(_pos)
	var q := OptionButton.new()
	q.tooltip_text = "Scene switches land on"
	for l in QUANTIZE_LABELS:
		q.add_item(l)
	q.item_selected.connect(func(i: int) -> void: quantize = QUANTIZE[i])
	bar.add_child(q)

	var ex := HFlowContainer.new()
	centre.add_child(ex)
	_button(ex, "Bake", func() -> void:
		bake(String(arrangement.scenes[scenes_view.selected_scene].name) if _views.current_tab == 0 and scenes_view.selected_scene >= 0 else ""))
	_button(ex, "Stems", func() -> void:
		stems(String(arrangement.scenes[scenes_view.selected_scene].name) if _views.current_tab == 0 and scenes_view.selected_scene >= 0 else ""))
	_button(ex, "Save as song", func() -> void: save_as_song())
	_button(ex, "Cue sheet", func() -> void: save_cue_sheet())
	_button(ex, "Undo", undo_last)
	_button(ex, "Redo", redo_last)
	_pending = Label.new()
	ex.add_child(_pending)

	_views = TabContainer.new()
	_views.size_flags_vertical = Control.SIZE_EXPAND_FILL
	centre.add_child(_views)
	var sv := VBoxContainer.new()
	sv.name = "Scenes"
	_views.add_child(sv)
	var srow := HFlowContainer.new()
	sv.add_child(srow)
	_button(srow, "+ Scene", func() -> void: add_scene())
	_scene_name = LineEdit.new()
	_scene_name.placeholder_text = "scene name"
	_scene_name.custom_minimum_size = Vector2(110, 0)
	_scene_name.text_submitted.connect(func(t: String) -> void:
		if t.strip_edges() != "" and arrangement.scene_index(t.strip_edges()) < 0:
			set_scene(scenes_view.selected_scene, "name", t.strip_edges()))
	srow.add_child(_scene_name)
	_scene_bars = _spin(srow, "bars (0 = longest loop)", 0, 0, 256, 1, func(v: float) -> void:
		if not _quiet:
			set_scene(scenes_view.selected_scene, "bars", v))
	_button(srow, "Delete scene", func() -> void:
		if scenes_view.selected_scene >= 0:
			delete_scene(scenes_view.selected_scene))
	_paint_from = _spin(srow, "Paint into bars", 1, 1, 999, 1, Callable())
	_paint_to = _spin(srow, "to", 8, 1, 999, 1, Callable())
	_button(srow, "Paint scene", func() -> void:
		paint_scene(scenes_view.selected_scene, _paint_from.value - 1.0, _paint_to.value))
	var sscroll := ScrollContainer.new()
	sscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sv.add_child(sscroll)
	scenes_view = AKSceneGrid.new()
	scenes_view.edit.connect(func(p: String, v: Variant, label: String) -> void: commit({p: v}, label))
	scenes_view.launch.connect(func(si: int) -> void: play_scene(si))
	scenes_view.open_loop.connect(func(_p: String, si: int, t: String) -> void: edit_cell(si, t))
	scenes_view.selection_changed.connect(_sync_toolbar)
	sscroll.add_child(scenes_view)

	var tv := VBoxContainer.new()
	tv.name = "Timeline"
	_views.add_child(tv)
	var trow := HFlowContainer.new()
	tv.add_child(trow)
	var snap := OptionButton.new()
	snap.tooltip_text = "Snap"
	for s in ["snap: bar", "snap: beat", "snap: off"]:
		snap.add_item(s)
	snap.item_selected.connect(func(i: int) -> void: timeline_view.snap = ["bar", "beat", "off"][i])
	trow.add_child(snap)
	_button(trow, "Zoom -", func() -> void:
		timeline_view.bar_px = maxf(6.0, timeline_view.bar_px / 1.5)
		timeline_view.refresh())
	_button(trow, "Zoom +", func() -> void:
		timeline_view.bar_px = minf(240.0, timeline_view.bar_px * 1.5)
		timeline_view.refresh())
	_marker_name = LineEdit.new()
	_marker_name.placeholder_text = "marker name"
	_marker_name.custom_minimum_size = Vector2(110, 0)
	_marker_name.text_submitted.connect(func(t: String) -> void: rename_marker(timeline_view.selected_marker, t))
	trow.add_child(_marker_name)
	var tscroll := ScrollContainer.new()
	tscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tv.add_child(tscroll)
	timeline_view = AKTimelineView.new()
	timeline_view.edit.connect(func(p: String, v: Variant, label: String) -> void: commit({p: v}, label))
	timeline_view.open_loop.connect(func(_p: String, ci: int) -> void: edit_clip(ci))
	timeline_view.seek.connect(func(b: float) -> void:
		timeline_view.playhead_bar = b
		if playing == "timeline":
			play_timeline(b))
	timeline_view.selection_changed.connect(_sync_toolbar)
	tscroll.add_child(timeline_view)

	var mx := ScrollContainer.new()
	mx.name = "Mixer"
	mx.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_views.add_child(mx)
	mixer = AKMixerView.new()
	mixer.edit.connect(func(p: String, v: Variant, label: String, merge: bool) -> void: commit({p: v}, label, merge))
	mixer.live_intensity.connect(func(x: float) -> void:
		if live and playing != "":
			live.set_music_intensity(x, 0.1))
	mx.add_child(mixer)

	var tracks_head := HBoxContainer.new()
	centre.add_child(tracks_head)
	var tl := Label.new()
	tl.text = "Tracks"
	tracks_head.add_child(tl)
	_button(tracks_head, "+ Track", func() -> void: add_track())
	_tracks_box = VBoxContainer.new()
	centre.add_child(_tracks_box)
	_status = Label.new()
	centre.add_child(_status)


func _build_tracks() -> void:
	if _tracks_box == null:
		return
	for c in _tracks_box.get_children():
		_tracks_box.remove_child(c)
		c.queue_free()
	var row := HFlowContainer.new()
	_tracks_box.add_child(row)
	for ti in arrangement.tracks.size():
		var box := HBoxContainer.new()
		row.add_child(box)
		var e := LineEdit.new()
		e.text = String(arrangement.tracks[ti].get("name", ""))
		e.custom_minimum_size = Vector2(90, 0)
		e.text_submitted.connect(func(t: String) -> void: rename_track(ti, t))
		box.add_child(e)
		_button(box, "↑", func() -> void: move_track(ti, -1))
		_button(box, "↓", func() -> void: move_track(ti, 1))
		_button(box, "x", func() -> void: delete_track(ti))


func _say(text: String) -> void:
	if _status:
		_status.text = text


func _spin(parent: Control, label: String, value: float, lo: float, hi: float, step: float, f: Callable) -> SpinBox:
	if label != "":
		var l := Label.new()
		l.text = label
		parent.add_child(l)
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(64, 0)
	if f.is_valid():
		s.value_changed.connect(func(v: float) -> void: f.call(v))
	parent.add_child(s)
	return s


func _button(parent: Control, text: String, f: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(f)
	parent.add_child(b)
	return b
