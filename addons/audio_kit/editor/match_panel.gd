# SPDX-License-Identifier: Apache-2.0
@tool
## The Synth page's "Match a recording": pick an Auxy export of an
## instrument playing the scale MIDI, match it (AKSampleMatch, on a thread),
## hear the original against the full and lite patches, then open either in
## the editor or save both. "Scale MIDI" writes the three loops to play.
class_name AKMatchPanel
extends VBoxContainer

const PASSAGES := ["Run", "Holds", "Velocity"]

## The Synth page the patches open in (and whose save folder they go to).
var lab: AKSynthLab
## The last finished match (AKSampleMatch.run's result), or {}.
var result := {}
var path := ""

var _thread: Thread
var _matcher: AKSampleMatch
var _file: Label
var _go: Button
var _stop: Button
var _bar: ProgressBar
var _info: Label
var _passage: OptionButton
var _after: Array[Control] = []
var _player: AudioStreamPlayer


func _init() -> void:
	_player = AudioStreamPlayer.new()
	add_child(_player)
	var row := HBoxContainer.new()
	add_child(row)
	_button(row, "Pick export", _pick).tooltip_text = "An Auxy \"Export for Bitwig Studio\" (.axbw) of one instrument playing the scale MIDI"
	_go = _button(row, "Match", func() -> void: start(path))
	_go.disabled = true
	_stop = _button(row, "Stop", stop)
	_stop.disabled = true
	_button(row, "Scale MIDI", _pick_midi_dir).tooltip_text = "Write the three loops to play in Auxy (one per scene, 60 BPM)"
	_file = Label.new()
	_file.clip_text = true
	_file.modulate = Color(1, 1, 1, 0.6)
	add_child(_file)
	_bar = ProgressBar.new()
	_bar.max_value = 1.0
	_bar.step = 0.001
	_bar.show_percentage = false
	_bar.visible = false
	add_child(_bar)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = AKUiScale.px(200, 0)
	add_child(_info)
	if not AKSampleMatch.available():
		_info.text = "Matching needs the native core (native/README.md)."
	var hear := HBoxContainer.new()
	add_child(hear)
	_passage = OptionButton.new()
	for p in PASSAGES:
		_passage.add_item(p)
	_passage.tooltip_text = "Which scene to play"
	hear.add_child(_passage)
	_after.append(_passage)
	_after.append(_button(hear, "Original", func() -> void: play("original")))
	_after.append(_button(hear, "Full", func() -> void: play("full")))
	_after.append(_button(hear, "Lite", func() -> void: play("lite")))
	_button(hear, "■", func() -> void: _player.stop()).tooltip_text = "Stop playing"
	var open := HBoxContainer.new()
	add_child(open)
	var tips := ["Open the full patch in the editor (zoned tables)", "Open the lite patch in the editor (one zone and curves)",
		"Save <name>.tres and <name>_lite.tres in your patches"]
	var acts := [func() -> void: _open(result.get("full"), ""), func() -> void: _open(result.get("lite"), "_lite"), func() -> void: save_both()]
	for i in 3:
		var b := _button(open, ["Edit full", "Edit lite", "Save both"][i], acts[i])
		b.tooltip_text = tips[i]
		_after.append(b)
	for c in _after:
		c.set(&"disabled", true)


func _exit_tree() -> void:
	stop()
	_join()


## Match the export at `p` on a thread; the panel fills in when it's done.
func start(p: String) -> void:
	if _thread or p == "" or not AKSampleMatch.available():
		return
	path = p
	result = {}
	for c in _after:
		c.set(&"disabled", true)
	_matcher = AKSampleMatch.new()
	_matcher.progress = func(f: float, text: String) -> void: _progress.call_deferred(f, text)
	_bar.visible = true
	_bar.value = 0.0
	_go.disabled = true
	_stop.disabled = false
	_info.text = "Matching %s ..." % p.get_file()
	_thread = Thread.new()
	_thread.start(func() -> void:
		var res := _matcher.run(p)
		_finished.call_deferred(res))


func stop() -> void:
	if _matcher:
		_matcher.cancelled = true


## True while a match runs.
func busy() -> bool:
	return _thread != null


func _progress(f: float, text: String) -> void:
	_bar.value = f
	_info.text = text


func _finished(res: Dictionary) -> void:
	_join()
	_bar.visible = false
	_go.disabled = path == ""
	_stop.disabled = true
	if not res.ok:
		_info.text = "Couldn't match %s: %s" % [path.get_file(), res.error]
		return
	result = res
	for c in _after:
		c.set(&"disabled", false)
	var rep: Dictionary = res.report
	_info.text = "%s: %s" % [res.name, AKSampleMatch.summary(rep)]
	_info.tooltip_text = "Scores in dB, lower is closer: each harmonic's level through every note against the recording.\nThe original against itself (the same passage played twice) is as close as a copy can get."
	if lab:
		lab._say("Matched %s. Play the passages, then Edit or Save." % res.name)


func _join() -> void:
	if _thread:
		_thread.wait_to_finish()
		_thread = null


## Play a scene of the original ("original"), or of the full or lite patch's render.
func play(which: String) -> void:
	if result.is_empty():
		return
	var b: AKBuffer = result.original if which == "original" else result.renders[which]
	var scenes: Array = result.scenes
	var i := _passage.selected
	var t0: float = scenes[i]
	var t1: float = scenes[i + 1] if i + 1 < scenes.size() else b.seconds()
	_player.stream = _slice(b, t0, t1).to_stream()
	if _player.is_inside_tree():
		_player.play()


static func _slice(b: AKBuffer, t0: float, t1: float) -> AKBuffer:
	var a := clampi(int(t0 * b.sample_rate), 0, b.frames())
	var e := clampi(int(t1 * b.sample_rate), a, b.frames())
	var o := AKBuffer.new(0, b.sample_rate)
	o.l = b.l.slice(a, e)
	o.r = b.r.slice(a, e)
	return o


func _open(p: Variant, suffix: String) -> void:
	if not p is AKPatch or lab == null:
		return
	lab.select_patch(p)
	if lab._save_name:
		lab._save_name.text = _base() + suffix


func _base() -> String:
	return String(result.get("name", "match")).to_snake_case().validate_filename()


## Save the full and lite patches under the Synth page's patches folder; returns their paths.
func save_both() -> Array:
	if result.is_empty():
		return []
	var dir := (lab.save_dir if lab else AKSynthLab.SAVE_DIR) + "patches/"
	DirAccess.make_dir_recursive_absolute(dir)
	var out := []
	for k in ["full", "lite"]:
		var p: AKPatch = result[k]
		var file := dir + _base() + ("_lite" if k == "lite" else "") + ".tres"
		p.category = "other" if p.category == "" else p.category
		if ResourceSaver.save(p, file) != OK:
			_info.text = "Couldn't save %s" % file
			return []
		out.append(file)
	AK.refresh_editor_files()
	if lab and lab.browser:
		lab.browser.refresh()
		lab._say("Saved %s" % ", ".join(out))
	return out


func _pick() -> void:
	var d := FileDialog.new()
	d.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.filters = PackedStringArray(["*.axbw ; Auxy \"Export for Bitwig Studio\""])
	d.title = "Pick an export of the scale MIDI"
	d.file_selected.connect(func(p: String) -> void:
		set_path(p)
		d.queue_free())
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered_ratio(0.6)


func set_path(p: String) -> void:
	path = p
	_file.text = p.get_file()
	_file.tooltip_text = p
	_go.disabled = p == "" or busy() or not AKSampleMatch.available()


func _pick_midi_dir() -> void:
	var d := FileDialog.new()
	d.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.title = "Where to write the scale MIDI"
	d.dir_selected.connect(func(dir: String) -> void:
		var written := AKSampleMatch.save_scale_midi(dir)
		_info.text = ("Wrote %s in %s. In Auxy: one instrument, a scene per loop at 60 BPM, then Export for Bitwig Studio." % [", ".join(AKSampleMatch.SCALE_FILES), dir]) if not written.is_empty() else "Couldn't write to %s" % dir
		d.queue_free())
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered_ratio(0.6)


func _button(parent: Control, text: String, f: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(f)
	parent.add_child(b)
	return b
