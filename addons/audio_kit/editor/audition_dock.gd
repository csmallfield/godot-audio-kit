# SPDX-License-Identifier: Apache-2.0
## The Audio Kit dock: hear whatever is in the inspector.
##
##   AKRecipe   play once (intensity, variant), or loop it at a rate; replays
##              as you edit; length, peak, loudness, render time and a waveform
##   AKSong     play live, jump between sections on the bar, intensity
##   AKPattern  loop it at a tempo
##   AKCueMap   a button per cue
##
## Songs, patterns and loops need the native core; recipes and cue maps play
## without it (baked in GDScript).
@tool
class_name AKAuditionDock
extends VBoxContainer

const AUTO_DELAY_S := 0.35
## Where "Save WAV" writes.
const SAVE_DIR := "res://audio_kit/auditions/"

## The mixer the dock plays through (null without the native core).
var live: AKLive
var player: AudioStreamPlayer
## What the dock shows (an AKRecipe, AKSong, AKPattern or AKCueMap), or null.
var resource: Resource
## The last recipe render: {length_s, peak_db, lufs, ms}.
var last_stats := {}
## The last file "Save WAV" wrote.
var last_saved := ""
var _last_buf: AKBuffer

var _title: Label
var _body: VBoxContainer
var _stats: Label
var _wave: _Wave
var _intensity: HSlider
var _variant: SpinBox
var _rate: HSlider
var _loop: CheckBox
var _auto: CheckBox
var _bpm: SpinBox
var _bars: SpinBox
var _follow_loop: CheckBox
var _pos: Label
var _loop_voice := -1
var _replay_at := -1.0
var _temp_song: AKSong
## The pattern's step grid (shown for AKPattern).
var grid: AKStepGrid


func _init() -> void:
	name = "Audio Kit"
	custom_minimum_size = Vector2(260, 200)
	_title = Label.new()
	_title.text = "Select a recipe, song, pattern or cue map."
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_title)
	_body = VBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_body)
	player = AudioStreamPlayer.new()
	add_child(player)
	if AKLive.available():
		live = AKLive.new()
		live.lookahead_s = 0.3
		_prepare(null)
		player.stream = live.stream


func _ready() -> void:
	if live and is_inside_tree():
		player.play()


func _process(delta: float) -> void:
	if live:
		live.update()
		if _pos and _pos.is_inside_tree():
			var p := live.song_position()
			_pos.text = "" if p.is_empty() else "%s  bar %d  beat %.1f" % [p.section, p.bar + 1, p.beat + 1.0]
		if grid and is_instance_valid(grid) and resource is AKPattern:
			var q := live.song_position()
			var pat := resource as AKPattern
			grid.playhead = -1.0 if q.is_empty() else (float(q.bar) * 4.0 + float(q.beat)) * pat.steps_per_beat
	if _replay_at >= 0.0:
		_replay_at -= delta
		if _replay_at < 0.0:
			play()


## Show `res` (anything else clears the dock).
func show_resource(res: Object) -> void:
	if res == resource:
		return
	stop()
	if resource and resource.changed.is_connected(_on_changed):
		resource.changed.disconnect(_on_changed)
	resource = res as Resource if (res is AKRecipe or res is AKSong or res is AKPattern or res is AKCueMap) else null
	for c in _body.get_children():
		c.queue_free()
	_stats = null
	_pos = null
	grid = null
	if resource == null:
		_title.text = "Select a recipe, song, pattern or cue map."
		return
	resource.changed.connect(_on_changed)
	var label := resource.resource_path.get_file() if resource.resource_path != "" else "(unsaved)"
	if resource is AKRecipe:
		_title.text = "Recipe  %s" % label
		_build_recipe()
	elif resource is AKSong:
		_title.text = "Song  %s" % label
		_build_song()
	elif resource is AKPattern:
		_title.text = "Pattern  %s" % label
		_build_pattern()
	else:
		_title.text = "Cue map  %s" % label
		_build_cue_map()


func play() -> void:
	_replay_at = -1.0
	if resource is AKRecipe:
		_play_recipe()
	elif resource is AKSong:
		_play_song(resource)
	elif resource is AKPattern:
		_play_song(_pattern_song(resource))


func stop() -> void:
	_replay_at = -1.0
	if live:
		live.song_stop(&"now")
		live.stream.clear()
		if _loop_voice >= 0:
			live.voice_stop(_loop_voice, 0.05)
			_loop_voice = -1
	elif player.playing:
		player.stop()


# ------------------------------------------------------------------ recipe

func _build_recipe() -> void:
	var row := _row()
	_button(row, "Play", play)
	_button(row, "Stop", stop)
	_button(row, "Save WAV", save_wav)
	_loop = _check(row, "Loop", false)
	_loop.disabled = live == null
	_loop.tooltip_text = "Play it as a seamless loop (native core)"
	_auto = _check(_body, "Replay when edited", true)
	_intensity = _slider("Intensity", 0.0, 1.0, 1.0, 0.01)
	_variant = SpinBox.new()
	_variant.min_value = 0
	_variant.max_value = 64
	_labelled("Variant", _variant)
	_rate = _slider("Loop rate", 0.25, 4.0, 1.0, 0.01)
	_rate.value_changed.connect(func(v: float) -> void:
		if live and _loop_voice >= 0:
			live.voice_set(_loop_voice, "rate", v, 0.05))
	_stats = Label.new()
	_body.add_child(_stats)
	_wave = _Wave.new()
	_wave.custom_minimum_size = Vector2(0, 90)
	_body.add_child(_wave)


func _play_recipe() -> void:
	var r := resource as AKRecipe
	var t := Time.get_ticks_usec()
	var buf := AK.render(r, _intensity.value, {}, int(_variant.value))
	var ms := (Time.get_ticks_usec() - t) / 1000.0
	_last_buf = buf
	var peak := buf.peak()
	last_stats = {length_s = buf.seconds(), peak_db = linear_to_db(peak) if peak > 0.0 else -INF,
		lufs = AKDynamics.lufs(buf), ms = ms}
	if _stats:
		_stats.text = "%.2f s   peak %.1f dBFS   %.1f LUFS   rendered in %.0f ms" % [last_stats.length_s, last_stats.peak_db, last_stats.lufs, ms]
	if _wave:
		_wave.set_buffer(buf)
	if live == null:
		player.stream = buf.to_stream()
		if player.is_inside_tree():
			player.play()
		return
	if _loop_voice >= 0:
		live.voice_stop(_loop_voice, 0.03)
		_loop_voice = -1
	if _loop and _loop.button_pressed:
		_loop_voice = live.loop_start(r, {gain = 1.0, rate = _rate.value, attack_s = 0.01}, 0.1, _intensity.value)
	else:
		live.play_buffer(buf)


# ------------------------------------------------------------------ song

func _build_song() -> void:
	var song := resource as AKSong
	var row := _row()
	_button(row, "Play", play)
	_button(row, "Stop", stop)
	_button(row, "Save WAV", save_wav)
	_follow_loop = _check(row, "Loop sections", true)
	if live == null:
		_note("Live music needs the native core (native/README.md).")
		return
	var flow := HFlowContainer.new()
	_body.add_child(flow)
	for L in song.layout():
		var n := String(L.name)
		_button(flow, n, func() -> void: _queue(song, n))
	_intensity = _slider("Intensity", 0.0, 1.0, song.intensity, 0.01)
	_intensity.value_changed.connect(func(v: float) -> void: live.set_music_intensity(v, 0.3))
	_pos = Label.new()
	_body.add_child(_pos)


func _queue(song: AKSong, section: String) -> void:
	if live.song_position().is_empty():
		_play_song(song, section)
	else:
		live.song_queue(section, &"bar")


func _play_song(song: AKSong, section := "") -> void:
	if live == null:
		_note_once("Live music needs the native core.")
		return
	_prepare(song)
	var follow := &"loop" if (_follow_loop == null or _follow_loop.button_pressed) else &"song"
	live.song_play(song, follow, section)
	if _intensity:
		live.set_music_intensity(_intensity.value, 0.0)


# ------------------------------------------------------------------ pattern

func _build_pattern() -> void:
	var row := _row()
	_button(row, "Play", play)
	_button(row, "Stop", stop)
	_button(row, "Save WAV", save_wav)
	_bpm = SpinBox.new()
	_bpm.min_value = 40
	_bpm.max_value = 240
	_bpm.value = 120
	_labelled("BPM", _bpm)
	_bars = SpinBox.new()
	_bars.min_value = 1
	_bars.max_value = 16
	_bars.value = maxf(1.0, ceilf((resource as AKPattern).beats() / 4.0))
	_labelled("Bars", _bars)
	if live == null:
		_note("Patterns play live: needs the native core.")
	_note("Click a step: rest, soft, normal, accent. Right-click clears. Click a lane's name to mute it.")
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	grid = AKStepGrid.new()
	grid.set_pattern(resource as AKPattern)
	scroll.custom_minimum_size = Vector2(0, grid.custom_minimum_size.y + 14.0)
	scroll.add_child(grid)
	_body.add_child(scroll)
	var row2 := _row()
	_button(row2, "Save pattern", func() -> void:
		var p := resource as AKPattern
		if p.resource_path != "":
			ResourceSaver.save(p)
			_note_once("Saved %s." % p.resource_path.get_file())
		else:
			_note_once("This pattern is embedded: save the resource that holds it."))


func _pattern_song(p: AKPattern) -> AKSong:
	var s := AKSong.new()
	s.tempo = AKTempoMap.new()
	s.tempo.bpm = _bpm.value if _bpm else 120.0
	s.sections = [{name = "pattern", bars = _bars.value if _bars else 1.0, patterns = [p]}]
	_temp_song = s
	return s


# ------------------------------------------------------------------ cue map

func _build_cue_map() -> void:
	var map := resource as AKCueMap
	_prepare(null, map)
	var flow := HFlowContainer.new()
	_body.add_child(flow)
	var names := map.sounds.keys()
	names.sort()
	for k in names:
		var cue := String(k)
		_button(flow, cue, func() -> void: _play_cue(map, cue))
	if names.is_empty():
		_note("No sounds in this cue map.")


func _play_cue(map: AKCueMap, cue: String) -> void:
	var name := StringName(cue.trim_suffix("*") + ("x" if cue.ends_with("*") else ""))
	if live:
		live.trigger(name, 1.0, {}, 0.0, map)
		return
	var r := map.recipe_for(name)
	if r:
		player.stream = AK.bake(r)
		if player.is_inside_tree():
			player.play()


# ------------------------------------------------------------------ save

## Write what's shown to a WAV under SAVE_DIR and return its path ("" if
## there's nothing to save). Recipes: the last render (at the dock's
## intensity and variant). Songs: the whole song at the dock's intensity,
## through its own reverb and master. Patterns: the bars set in the dock.
func save_wav() -> String:
	var buf: AKBuffer = null
	var tag := ""
	if resource is AKRecipe:
		if _last_buf == null:
			_play_recipe()
		buf = _last_buf
		tag = "_i%d_v%d" % [roundi(_intensity.value * 100.0), int(_variant.value)]
	elif resource is AKSong or resource is AKPattern:
		var song: AKSong = resource if resource is AKSong else _pattern_song(resource)
		var keep := song.intensity
		if _intensity and resource is AKSong:
			song.intensity = _intensity.value
			tag = "_i%d" % roundi(_intensity.value * 100.0)
		buf = song.render().mix
		song.intensity = keep
	if buf == null or buf.frames() == 0:
		return ""
	var base := resource.resource_path.get_file().get_basename() if resource.resource_path != "" else "audition"
	var path := SAVE_DIR + base + tag + ".wav"
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	if buf.save_wav(path) != OK:
		_note_once("Couldn't write %s." % path)
		return ""
	last_saved = path
	_note_once("Saved %s (%.2f s)." % [path, buf.seconds()])
	# Let the editor's file panel see it (without naming EditorInterface,
	# which exported builds don't have).
	if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		var fs: Object = Engine.get_singleton(&"EditorInterface").call(&"get_resource_filesystem")
		if fs:
			fs.call(&"scan")
	return path


# ------------------------------------------------------------------ inside

## Reset the mixer with a gentle audition chain (DC block, a limiter) and
## the space of `song` or `map`.
func _prepare(song: AKSong, map: AKCueMap = null) -> void:
	if live == null:
		return
	var m := AKCueMap.new()
	m.master_fx = [{type = &"dcblock"}, {type = &"limit", ceiling_db = -1.0}]
	if map:
		m.reverb = map.reverb
		m.sounds = map.sounds
		m.duck = map.duck
	elif song:
		m.reverb = song.reverb
	live.prepare([], m)


func _on_changed() -> void:
	if resource is AKRecipe and _auto and _auto.button_pressed:
		_replay_at = AUTO_DELAY_S
	elif resource is AKSong or resource is AKPattern:
		if live and not live.song_position().is_empty():
			live.song_changed()


func _row() -> HBoxContainer:
	var r := HBoxContainer.new()
	_body.add_child(r)
	return r


func _button(parent: Control, text: String, f: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(f)
	parent.add_child(b)
	return b


func _check(parent: Control, text: String, on: bool) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	parent.add_child(c)
	return c


func _slider(text: String, lo: float, hi: float, v: float, step: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = v
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_labelled(text, s)
	var v_label := Label.new()
	v_label.custom_minimum_size = Vector2(40, 0)
	v_label.text = "%.2f" % v
	s.value_changed.connect(func(x: float) -> void: v_label.text = "%.2f" % x)
	s.get_parent().add_child(v_label)
	return s


func _labelled(text: String, c: Control) -> void:
	var r := _row()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(80, 0)
	r.add_child(l)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(c)


func _note(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.modulate = Color(1, 1, 1, 0.6)
	_body.add_child(l)


func _note_once(text: String) -> void:
	for c in _body.get_children():
		if c is Label and c.text == text:
			return
	_note(text)


## A min/max waveform of the last render.
class _Wave:
	extends Control
	var _cols := PackedVector2Array()
	var _scale := 1.0

	func set_buffer(buf: AKBuffer) -> void:
		var w := maxi(64, int(size.x) if size.x > 0 else 256)
		_cols.resize(w)
		var n := buf.frames()
		# Raw recipes can peak over full scale (the master chain limits them):
		# scale so the picture still fits.
		_scale = 1.0 / maxf(1.0, buf.peak())
		for c in w:
			var a := int(float(c) / w * n)
			var b := maxi(a + 1, int(float(c + 1) / w * n))
			var lo := 0.0
			var hi := 0.0
			for i in range(a, mini(b, n), maxi(1, (b - a) / 64)):
				var v := 0.5 * (buf.l[i] + buf.r[i])
				lo = minf(lo, v)
				hi = maxf(hi, v)
			_cols[c] = Vector2(lo, hi)
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.25))
		var mid := size.y * 0.5
		draw_line(Vector2(0, mid), Vector2(size.x, mid), Color(1, 1, 1, 0.15))
		var w := _cols.size()
		for c in w:
			var x := float(c) / maxf(1.0, w) * size.x
			draw_line(Vector2(x, mid - _cols[c].y * _scale * mid), Vector2(x, mid - _cols[c].x * _scale * mid), Color("#ffcf3a"))
