# SPDX-License-Identifier: Apache-2.0
# Phase 7: the Loops tab. The grid (mouse and keys, as a person uses it),
# the toolbar and tools, the loop and sound browsers, the sample and kit
# panels, live looping with edits heard on the next pass, Context play; and
# the gate: a two-bar beat, a bass line and a chord loop built from New
# through the tab's own controls, saved, reloaded field for field and measured.
extends RefCounted

const OUT := "user://test_loops_tab/"
const SR := 48000


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _lab() -> AKLoopLab:
	var lab := AKLoopLab.new()
	_tree().root.add_child(lab)
	# Headless, Godot's dummy audio driver would pull the live stream in real
	# time beside render_playing: the tests pull it themselves.
	lab.player.stop()
	lab.set_save_dir(OUT)
	return lab


## Notes equal to `want` ([start, length, row, velocity]), velocities within 0.002.
func _eqn(got: Array, want: Array) -> bool:
	if got.size() != want.size():
		return false
	for i in got.size():
		for k in 3:
			if int(got[i][k]) != int(want[i][k]):
				return false
		if absf(float(got[i][3]) - float(want[i][3])) > 0.002:
			return false
	return true


func _done(lab: AKLoopLab) -> void:
	lab.stop()
	lab.queue_free()


# ------------------------------------------------------------------ input helpers

func _mouse(g: AKLoopGrid, pos: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT, shift := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = pos
	e.shift_pressed = shift
	g._gui_input(e)


func _move(g: AKLoopGrid, pos: Vector2, shift := false) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.shift_pressed = shift
	g._gui_input(e)


func _click(g: AKLoopGrid, pos: Vector2) -> void:
	_mouse(g, pos, true)
	_mouse(g, pos, false)


## Press at `from`, move through a few points to `to`, release there.
func _drag(g: AKLoopGrid, from: Vector2, to: Vector2, button := MOUSE_BUTTON_LEFT, shift := false) -> void:
	_mouse(g, from, true, button)
	for k in range(1, 5):
		_move(g, from.lerp(to, k / 4.0), shift)
	_mouse(g, to, false, button, shift)


func _key(g: AKLoopGrid, code: Key, ctrl := false, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.ctrl_pressed = ctrl
	e.shift_pressed = shift
	g._gui_input(e)


## Add a note by clicking its first cell and dragging to `length` ticks.
func _draw_note(g: AKLoopGrid, tick: int, row: int, length := 0) -> void:
	var c := g.cell_center(tick, row)
	if length <= g.loop.cell_ticks():
		_click(g, c)
		return
	var end := Vector2(g.tick_to_x(tick + length) - 2.0, c.y)
	_drag(g, c, end)


## The y in the velocity strip for velocity `v`.
func _vel_y(g: AKLoopGrid, v: float) -> float:
	return g.vel_top() + (1.0 - v) * AKLoopGrid.VEL_H


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


## Pick the item starting with `prefix` in the toolbar menu whose tooltip is `tip`.
func _choose(lab: AKLoopLab, tip: String, prefix: String) -> String:
	var ob := _option(lab, tip)
	if ob == null:
		return "no %s menu" % tip
	for i in ob.item_count:
		if ob.get_item_text(i).begins_with(prefix):
			ob.select(i)
			ob.item_selected.emit(i)
			return ""
	return "the %s menu has no %s" % [tip, prefix]


func _option(n: Node, tip: String) -> OptionButton:
	for c in n.get_children():
		if c is OptionButton and (c as OptionButton).tooltip_text.begins_with(tip):
			return c
		var o := _option(c, tip)
		if o:
			return o
	return null


func _new(lab: AKLoopLab, kind: String) -> void:
	var mb: MenuButton = null
	for c in lab.find_children("*", "MenuButton", true, false):
		if (c as MenuButton).text == "New":
			mb = c
	mb.get_popup().id_pressed.emit(AKLoopLab.NEW_KINDS.find(kind))


# ------------------------------------------------------------------ the grid

func test_grid_mouse_and_keys() -> String:
	var lab := _lab()
	lab.new_loop("synth")
	var g := lab.grid
	var l := lab.loop
	# Click: a one-cell note; drag right: longer; click a note: it's gone.
	_click(g, g.cell_center(0, 60))
	if l.notes != [[0, 24, 60, 0.8]]:
		_done(lab)
		return "a click should add a 16th: %s" % [l.notes]
	_draw_note(g, 96, 64, 72)
	if l.notes.size() != 2 or l.notes[1] != [96, 72, 64, 0.8]:
		_done(lab)
		return "a drag should add a longer note: %s" % [l.notes]
	_click(g, g.cell_center(0, 60))
	if l.notes != [[96, 72, 64, 0.8]]:
		_done(lab)
		return "clicking a note should delete it: %s" % [l.notes]
	# Undo brings it back, redo removes it again: each gesture is one step.
	g.undo_last()
	if l.notes.size() != 2:
		_done(lab)
		return "undo should restore the deleted note: %s" % [l.notes]
	g.redo_last()
	if l.notes.size() != 1:
		_done(lab)
		return "redo: %s" % [l.notes]
	# Drag the body: move in time and pitch; drag the edge: resize.
	var body := g.cell_center(96, 64)
	_drag(g, body, body + Vector2(g.tick_to_x(144) - g.tick_to_x(96), g.row_to_y(62) - g.row_to_y(64)))
	if l.notes != [[144, 72, 62, 0.8]]:
		_done(lab)
		return "moving a note: %s" % [l.notes]
	g.undo_last()
	if l.notes != [[96, 72, 64, 0.8]]:
		_done(lab)
		return "a whole drag should undo in one step: %s" % [l.notes]
	var edge := Vector2(g.tick_to_x(96 + 72) - 2.0, g.cell_center(96, 64).y)
	_drag(g, edge, Vector2(g.tick_to_x(192) + 3.0, edge.y))
	if l.notes != [[96, 96, 64, 0.8]]:
		_done(lab)
		return "resizing from the edge: %s" % [l.notes]
	# Shift snaps to the next finer division (32nds on a 16th grid).
	_drag(g, Vector2(g.tick_to_x(192) - 2.0, edge.y), Vector2(g.tick_to_x(204) + 1.0, edge.y), MOUSE_BUTTON_LEFT, true)
	if l.notes != [[96, 108, 64, 0.8]]:
		_done(lab)
		return "a shift-drag should snap to 32nds: %s" % [l.notes]
	# Box-select, arrows, octave, duplicate, delete.
	_draw_note(g, 0, 60)
	_drag(g, Vector2(g.KEY_W + 1.0, g.row_to_y(66)), Vector2(g.tick_to_x(250), g.row_to_y(59)), MOUSE_BUTTON_RIGHT)
	if g.selection.size() != 2:
		_done(lab)
		return "right-drag should select both notes, got %s" % [g.selection]
	_key(g, KEY_RIGHT)
	_key(g, KEY_UP)
	_key(g, KEY_UP, false, true)
	if not _eqn(l.sorted_notes(), [[24, 24, 73, 0.8], [120, 108, 77, 0.8]]):
		_done(lab)
		return "arrows: %s" % [l.sorted_notes()]
	_key(g, KEY_D, true)
	if l.notes.size() != 4 or g.selection.size() != 2:
		_done(lab)
		return "Ctrl+D should duplicate the selection: %s" % [l.notes]
	var dup := l.sorted_notes()
	if not _eqn([dup[1]], [[120, 108, 77, 0.8]]) or dup[2][0] != 24 + 216 or dup[3][0] != 120 + 216:
		_done(lab)
		return "the copies should follow the selection's span: %s" % [dup]
	_key(g, KEY_DELETE)
	if l.notes.size() != 2:
		_done(lab)
		return "Delete: %s" % [l.notes]
	# The velocity strip.
	var vx := g.tick_to_x(24) + 2.0
	_drag(g, Vector2(vx, _vel_y(g, 0.8)), Vector2(vx, _vel_y(g, 0.35)))
	var n24: Array = l.sorted_notes()[0]
	if absf(float(n24[3]) - 0.35) > 0.02 or absf(float(l.sorted_notes()[1][3]) - 0.8) > 1e-6:
		_done(lab)
		return "the velocity strip: %s" % [l.sorted_notes()]
	# Changing the division changes the snap, never the notes.
	var before := l.sorted_notes()
	lab.set_division(12)
	if l.sorted_notes() != before or g.loop.cell_ticks() != 32:
		_done(lab)
		return "division 12: %s" % [l.sorted_notes()]
	_click(g, g.cell_center(32 * 5, 50))
	if not l.notes.has([160, 32, 50, 0.8]):
		_done(lab)
		return "a click on a triplet grid should add a triplet 8th: %s" % [l.notes]
	# Fold to a scale hides the rows outside it.
	lab.set_scale_key("minor", 9)
	lab.set_fold(true)
	for r in g.rows():
		if not posmod(r - 9, 12) in AKNotes.SCALES.minor:
			_done(lab)
			return "folded rows hold %d, not in A minor" % r
	_done(lab)
	return ""


func test_kit_rows_ignore_length_unless_gated() -> String:
	var lab := _lab()
	lab.new_loop("percussive")
	var g := lab.grid
	var kit := lab.loop.instrument as AKKit
	if g.rows().size() != kit.piece_count() or g.rows()[0] != 0:
		_done(lab)
		return "kit rows: %s" % [g.rows()]
	_draw_note(g, 0, 0, 96)   # a drag on a kick: still one cell drawn
	if g.shown_length(lab.loop.notes[0]) != 24:
		_done(lab)
		return "a kick hit should be one cell"
	# Mute a row: its lane is muted in what plays, the loop file isn't touched.
	var row_y := g.row_to_y(0) + 5.0
	_click(g, Vector2(8.0, row_y))
	if not g.muted.has(0):
		_done(lab)
		return "the M box should mute the row"
	var p := lab.compiled_song().sections[0].patterns[0] as AKPattern
	if not bool(p.lanes[0].get("mute", false)):
		_done(lab)
		return "a muted row should be muted in what plays"
	# A gated piece (set in the kit panel, which copies a shipped kit) keeps length.
	lab.set_piece(4, "gate", true)
	var own := lab.loop.instrument as AKKit
	if own == kit or own.resource_path.begins_with("res://addons/") or not own.is_gated(4):
		_done(lab)
		return "editing a shipped kit should edit a copy"
	_draw_note(g, 192, 4, 96)
	var n: Array = lab.loop.notes.filter(func(x: Array) -> bool: return int(x[2]) == 4)[0]
	if int(n[1]) != 96 or g.shown_length(n) != 96:
		_done(lab)
		return "a gated piece should keep its length: %s" % [n]
	if not AKLibrary.kit("punch").pieces == kit.pieces:
		_done(lab)
		return "the shipped kit changed"
	_done(lab)
	return ""


# ------------------------------------------------------------------ toolbar and tools

func test_toolbar_and_tools() -> String:
	var lab := _lab()
	_new(lab, "sample")
	if lab.loop.kind != "sample" or not lab.loop.instrument is AKSample:
		_done(lab)
		return "New -> sample"
	if lab.instrument_choices().size() < 120:
		_done(lab)
		return "the sample instruments should list the library (%d)" % lab.instrument_choices().size()
	var err := _choose(lab, "Instrument", "marimba")
	if err != "":
		_done(lab)
		return err
	var s := lab.loop.instrument as AKSample
	if s == null or s.root_note != 60.0 or not s.recipe.resource_path.ends_with("keys/marimba.tres"):
		_done(lab)
		return "the marimba as a sample: %s" % s
	err = _choose(lab, "Bars", "4 bars")
	if err != "" or lab.loop.bars != 4:
		_done(lab)
		return "bars: %s %d" % [err, lab.loop.bars]
	lab.grid.add_note(0, 96, 60)
	lab.grid.add_note(96, 48, 64)
	_press(lab, "Double")
	if lab.loop.bars != 8 or lab.loop.notes.size() != 4 or not lab.loop.notes.has([96 + 1536, 48, 64, 0.8]):
		_done(lab)
		return "Double: %d bars, %s" % [lab.loop.bars, lab.loop.notes]
	lab.grid.undo_last()
	if lab.loop.bars != 4 or lab.loop.notes.size() != 2:
		_done(lab)
		return "Double should undo in one step"
	_press(lab, "+1 st")
	if not _eqn(lab.loop.sorted_notes(), [[0, 96, 61, 0.8], [96, 48, 65, 0.8]]):
		_done(lab)
		return "+1 st: %s" % [lab.loop.sorted_notes()]
	_press(lab, "Halve")
	if lab.loop.bars != 2:
		_done(lab)
		return "Halve: %d bars" % lab.loop.bars
	_press(lab, "Ramp down")
	var v := lab.loop.sorted_notes().map(func(n: Array) -> float: return n[3])
	if absf(v[0] - 1.0) > 1e-6 or absf(v[1] - 0.4) > 1e-6:
		_done(lab)
		return "Ramp down: %s" % [v]
	err = _choose(lab, "Type", "percussive")
	if err != "" or lab.loop.kind != "percussive" or not lab.loop.instrument is AKKit:
		_done(lab)
		return "Type -> percussive: %s" % err
	lab.grid.undo_last()
	if lab.loop.kind != "sample":
		_done(lab)
		return "the type change should undo"
	# The sample panel: root note, mode, detect.
	lab.set_sample_param("mode", "gate")
	lab.set_sample_param("root_note", 62.0)
	s = lab.loop.instrument as AKSample
	if s.mode != "gate" or s.root_note != 62.0:
		_done(lab)
		return "sample settings"
	lab.grid.undo_last()
	if (lab.loop.instrument as AKSample).root_note != 60.0:
		_done(lab)
		return "sample settings should undo"
	var det := AKLoopLab.detect_root(AKLibrary.sample_for(AKLibrary.path_of("keys", "epiano")))
	if det != 60:
		_done(lab)
		return "detect_root of the epiano (made at C4): %d" % det
	# Audition a row: a note at that pitch comes back.
	var buf := lab.audition_row(64)
	if buf == null or buf.peak() < 0.05:
		_done(lab)
		return "auditioning a row"
	_done(lab)
	return ""


func test_browsers_and_saving() -> String:
	DirAccess.make_dir_recursive_absolute(OUT + "loops/")
	var lab := _lab()
	lab.new_loop("synth")
	lab.grid.add_note(0, 48, 57)
	lab._name.text = "browse_bass"; lab._name.text_changed.emit("browse_bass")
	_choose(lab, "Category", "bass")
	var path := lab.save_loop()
	if path != OUT + "loops/browse_bass.tres" or not lab.loops.filtered("browse").has(path):
		_done(lab)
		return "the saved loop should be listed: %s, %s" % [path, lab.loops.shown()]
	if not lab.loops.filtered("", "synth").has(path) or lab.loops.filtered("", "percussive").has(path) or not lab.loops.filtered("bass").has(path):
		_done(lab)
		return "the loop browser's filters"
	lab.new_loop("percussive")
	lab.open_loop(path)
	if lab.loop.resource_path != path or lab.loop.notes != [[0, 48, 57, 0.8]] or lab._name.text != "browse_bass":
		_done(lab)
		return "opening a loop"
	# The sound browser: the library and the project's own files.
	var sb := lab.sounds
	if sb.filtered("", "kicks").size() != 14 or not sb.filtered("epiano").has(AKLibrary.path_of("keys", "epiano")):
		_done(lab)
		return "the sound browser lists the library by folder"
	DirAccess.make_dir_recursive_absolute(OUT + "samples/")
	var tone := PackedFloat32Array()
	for i in 24000:
		var t := float(i) / SR
		tone.append(0.3 * (sin(TAU * 220.0 * t) + 0.5 * sin(TAU * 440.0 * t) + 0.3 * sin(TAU * 660.0 * t)) * exp(-t * 3.0))
	AKBuffer.from_mono(tone).save_wav(OUT + "samples/tone_a3.wav")
	sb.refresh()
	if not sb.filtered("tone_a3", "project").has(OUT + "samples/tone_a3.wav"):
		_done(lab)
		return "the project's own sounds should be listed"
	# Picking a project file for a sample loop makes an AKSample beside it,
	# its root note detected.
	lab.new_loop("sample")
	lab.set_instrument(OUT + "samples/tone_a3.wav")
	var s := lab.loop.instrument as AKSample
	if s == null or s.resource_path != OUT + "samples/tone_a3.sample.tres" or s.root_note != 57.0 or s.data.size() != 24000:
		_done(lab)
		return "a sample beside the file: %s, root %s" % [s.resource_path if s else "none", s.root_note if s else -1]
	_done(lab)
	return ""


# ------------------------------------------------------------------ playing

## The live loop picks up an edit for the notes not yet sounding: a note
## added where the playhead has passed sounds on the next pass, as a bake of
## (old pass, new pass) does.
func test_live_edit_heard_on_the_next_pass() -> String:
	if not AKLive.available():
		print("        (native core not built: skipped)")
		return ""
	var lab := _lab()
	lab.new_loop("percussive")
	var l := lab.loop
	for t in [0, 192]:
		lab.grid.add_note(t, 24, 0, 1.0)
	for t in range(0, 384, 48):
		lab.grid.add_note(t, 24, 3, 0.6)
	lab.set_tempo(120.0)
	var before := l.duplicate(true) as AKLoop
	before.instrument = l.instrument
	lab.play()
	var bar := 2.0   # seconds at 120 bpm
	var a := lab.live.render_playing(roundi(1.5 * SR))
	# Three beats in: add a snare on beat 2 (already passed this time round).
	lab.grid.add_note(96, 24, 1, 0.9)
	var b := lab.live.render_playing(roundi((2.0 * bar - 1.5 + 1.0) * SR))
	var got := AKBuffer.new(0, SR)
	a.mix_into(got, 0)
	b.mix_into(got, a.frames())
	var ref := AKSong.new()
	ref.tempo = AKTempoMap.make(120.0)
	ref.sections = [{name = "a", bars = 1, patterns = [before.to_pattern()]}, {name = "b", bars = 1, patterns = [l.to_pattern()]}]
	ref.master_fx = lab.compiled_song().master_fx
	var want: AKBuffer = ref.render().mix
	var snr := _snr(got, want, roundi(2.0 * bar * SR))
	print("        live loop edited mid-pass vs a bake of (old, new): SNR %.1f dB" % snr)
	_done(lab)
	return "" if snr > 90.0 else "edit mid-pass: SNR %.1f dB" % snr


func test_context_plays_other_loops() -> String:
	var lab := _lab()
	var bass := AKLoop.new()
	bass.kind = "synth"
	bass.instrument = load("res://addons/audio_kit/patches/pluck.tres")
	bass.bars = 2
	bass.notes = [[0, 96, 45, 0.9]]
	bass.resource_name = "ctx_bass"
	lab.new_loop("percussive")
	lab.grid.add_note(0, 24, 0)
	lab.add_context(bass)
	if lab.compiled_song().sections[0].patterns.size() != 1:
		_done(lab)
		return "context loops play only with Context on"
	_press(lab, "Context")
	var s := lab.compiled_song()
	if not lab.context_on or s.sections[0].patterns.size() != 2 or s.sections[0].bars != 2:
		_done(lab)
		return "with Context the bass plays too, over its two bars: %s" % [s.sections[0]]
	var names := []
	for p: AKPattern in s.sections[0].patterns:
		for ln in p.lanes:
			names.append(ln.name)
	if not names.has("ctx_bass") or not names.has("drums.kick"):
		_done(lab)
		return "lanes %s" % [names]
	_press(lab, "Clear context")
	if lab.compiled_song().sections[0].patterns.size() != 1:
		_done(lab)
		return "Clear context"
	_done(lab)
	return ""


func test_baked_play_without_native() -> String:
	var lab := _lab()
	var was := AKDsp.native_enabled
	var live := lab.live
	lab.live = null   # as without the native core
	AKDsp.native_enabled = false
	lab.new_loop("percussive")
	lab.grid.add_note(0, 24, 0)
	lab.play()
	var st := lab.player.stream as AudioStreamWAV
	var ok := st != null and st.loop_mode == AudioStreamWAV.LOOP_FORWARD and st.loop_end == roundi(2.0 * SR) and lab.is_playing()
	lab.stop()
	AKDsp.native_enabled = was
	lab.live = live
	_done(lab)
	return "" if ok else "without the native core Play should loop a bake of one pass"


# ------------------------------------------------------------------ the gate

func test_gate_three_loops_from_new() -> String:
	DirAccess.make_dir_recursive_absolute(OUT)
	var lab := _lab()
	var g := lab.grid
	var steps: Array[Callable] = []
	# 1. A two-bar beat on the electro kit: kick, snare, hats, an open hat choked.
	var kicks := [0, 192, 384, 456, 576]
	var snares := [96, 288, 480, 672]
	var hats := []
	for t in range(0, 768, 48):
		if t != 336 and t != 720:
			hats.append(t)
	steps.append(func() -> String:
		_new(lab, "percussive")
		return "")
	steps.append(func() -> String: return _choose(lab, "Instrument", "electro"))
	steps.append(func() -> String: return _choose(lab, "Bars", "2 bars"))
	steps.append(func() -> String:
		for t in kicks:
			_draw_note(g, t, 0)
		for t in snares:
			_draw_note(g, t, 1)
		for t in hats:
			_draw_note(g, t, 3)
		for t in [336, 720]:
			_draw_note(g, t, 4)
		# Off-beat hats softer: drag their velocity bars down.
		for t in hats:
			if t % 96 == 48:
				var x := g.tick_to_x(t) + 2.0
				_drag(g, Vector2(x, _vel_y(g, 0.8)), Vector2(x, _vel_y(g, 0.45)))
		return "")
	steps.append(func() -> String: return _choose(lab, "Category", "beat"))
	steps.append(func() -> String:
		lab._name.text = "gate_beat"; lab._name.text_changed.emit("gate_beat")
		return _press(lab, "Save"))
	# 2. A bass line on the wavetable bass, an octave down, notes dragged long.
	var bass := [[0, 72, 45], [96, 48, 45], [192, 96, 48], [288, 72, 52], [384, 144, 43], [576, 96, 43], [672, 72, 47]]
	steps.append(func() -> String:
		_new(lab, "synth")
		return "")
	steps.append(func() -> String: return _choose(lab, "Instrument", "wavetable_bass"))
	steps.append(func() -> String: return _choose(lab, "Bars", "2 bars"))
	steps.append(func() -> String: return _press(lab, "Oct-"))
	steps.append(func() -> String:
		for n in bass:
			_draw_note(g, n[0], n[2], n[1])
		return "")
	steps.append(func() -> String:
		lab._name.text = "gate_bass"; lab._name.text_changed.emit("gate_bass")
		_choose(lab, "Category", "bass")
		return _press(lab, "Save"))
	# 3. Chords on the library's epiano: A minor then F, folded to A minor.
	var chords := [[0, [57, 60, 64]], [384, [53, 57, 60]]]
	steps.append(func() -> String:
		_new(lab, "sample")
		return "")
	steps.append(func() -> String: return _choose(lab, "Instrument", "epiano"))
	steps.append(func() -> String: return _choose(lab, "Bars", "2 bars"))
	steps.append(func() -> String: return _choose(lab, "Scale", "minor"))
	steps.append(func() -> String: return _choose(lab, "Root", "A"))
	steps.append(func() -> String: return _press(lab, "Fold"))
	steps.append(func() -> String:
		for c in chords:
			for m in c[1]:
				_draw_note(g, c[0], m, 384)
		var x := g.tick_to_x(0) + 2.0
		_drag(g, Vector2(x, _vel_y(g, 0.8)), Vector2(x, _vel_y(g, 0.6)))
		return "")
	steps.append(func() -> String:
		lab._name.text = "gate_chords"; lab._name.text_changed.emit("gate_chords")
		_choose(lab, "Category", "chords")
		return _press(lab, "Save"))
	for i in steps.size():
		var err: String = steps[i].call()
		if err != "":
			_done(lab)
			return "step %d: %s" % [i, err]
		await _tree().process_frame

	# Reloaded from disk, field for field.
	var beat: AKLoop = ResourceLoader.load(OUT + "loops/gate_beat.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	var bl: AKLoop = ResourceLoader.load(OUT + "loops/gate_bass.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	var ch: AKLoop = ResourceLoader.load(OUT + "loops/gate_chords.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	if beat == null or bl == null or ch == null:
		_done(lab)
		return "the loops weren't saved"
	var want_beat := []
	for t in kicks:
		want_beat.append([t, 24, 0, 0.8])
	for t in snares:
		want_beat.append([t, 24, 1, 0.8])
	for t in hats:
		want_beat.append([t, 24, 3, 0.45 if t % 96 == 48 else 0.8])
	for t in [336, 720]:
		want_beat.append([t, 24, 4, 0.8])
	want_beat.sort()
	var err := _same(beat, "percussive", 2, AKLibrary.kit_path("electro"), want_beat, "beat")
	if err == "":
		var wb := []
		for n in bass:
			wb.append([n[0], n[1], n[2], 0.8])
		wb.sort()
		err = _same(bl, "synth", 2, "res://addons/audio_kit/patches/wavetable_bass.tres", wb, "bass")
	if err == "":
		var wc := []
		for c in chords:
			for m in c[1]:
				wc.append([c[0], 384, m, 0.6 if c[0] == 0 else 0.8])
		wc.sort()
		err = _same(ch, "sample", 2, AKLibrary.path_of("keys", "epiano"), wc, "chords")
	if err == "" and (beat.category != "beat" or bl.category != "bass" or ch.category != "chords" or beat.division != 16):
		err = "categories or division: %s %s %s %d" % [beat.category, bl.category, ch.category, beat.division]
	if err != "":
		_done(lab)
		return err

	# Measured: the three loops together, two bars at 120 bpm.
	var song := AKSong.new()
	song.tempo = AKTempoMap.make(120.0)
	song.sections = [{name = "a", bars = 2, patterns = [beat.to_pattern(8.0), bl.to_pattern(8.0), ch.to_pattern(8.0)]}]
	song.master_fx = []
	var out := song.render(true)
	var st: Dictionary = out.stems
	var spt := 0.5 / 96.0   # seconds a tick at 120 bpm
	# Every kick and snare lands where it was clicked; the open hats are cut by the next closed hat.
	for t in kicks:
		if not _onset(st["music.drums.kick"], t * spt):
			_done(lab)
			return "no kick at tick %d" % t
	for t in snares:
		if not _onset(st["music.drums.snare"], t * spt):
			_done(lab)
			return "no snare at tick %d" % t
	var oh: AKBuffer = st["music.drums.open_hat"]
	var cut_at := roundi((384 + 6) * spt * SR)   # the closed hat on bar 2's downbeat, plus the fade
	if _rms(oh, cut_at, cut_at + 2400) > 1e-4 or _rms(oh, roundi(336 * spt * SR), roundi(336 * spt * SR) + 2400) < 1e-3:
		_done(lab)
		return "the open hat should ring and then be choked"
	# Every bass note at its written pitch.
	var bs: AKBuffer = st["music.gate_bass"]
	var good := 0
	for n in bass:
		if _pitch_ok(bs, (n[0] + n[1] * 0.5) * spt, AKNotes.midi_to_hz(n[2])):
			good += 1
	if good < bass.size():
		_done(lab)
		return "only %d of %d bass notes at their pitch" % [good, bass.size()]
	# Each chord's three notes stand above their semitone neighbours.
	var cs: AKBuffer = st["music.gate_chords"]
	for c in chords:
		var at := roundi((c[0] + 96) * spt * SR)
		for m in c[1]:
			var e := _band(cs, at, AKNotes.midi_to_hz(m))
			if e < 3.0 * _band(cs, at, AKNotes.midi_to_hz(m - 1)) or e < 3.0 * _band(cs, at, AKNotes.midi_to_hz(m + 1)):
				_done(lab)
				return "chord at tick %d: %s isn't there" % [c[0], AKNotes.midi_to_name(m)]
	if out.mix.peak() < 0.1 or out.mix.peak() > 2.0:
		_done(lab)
		return "level %.2f" % out.mix.peak()
	print("        a beat, a bass line (%d/%d notes at pitch) and chords, built from New" % [good, bass.size()])
	# And the tab plays a saved loop live as it bakes.
	if AKLive.available():
		lab.open_loop(OUT + "loops/gate_beat.tres")
		lab.set_tempo(120.0)
		lab.play()
		var live := lab.live.render_playing(roundi(4.0 * SR))
		var baked: AKBuffer = lab.compiled_song().render().mix
		var snr := _snr(live, baked, roundi(3.9 * SR))
		if snr < 90.0:
			_done(lab)
			return "the beat live vs baked: SNR %.1f dB" % snr
	_done(lab)
	return ""


func _same(l: AKLoop, kind: String, bars: int, inst: String, notes: Array, what: String) -> String:
	if l.kind != kind or l.bars != bars:
		return "%s: %s, %d bars" % [what, l.kind, l.bars]
	var ip := ""
	if l.instrument is AKSample:
		var s := l.instrument as AKSample
		ip = s.recipe.resource_path if s.recipe else s.source
	elif l.instrument:
		ip = l.instrument.resource_path
	if ip != inst:
		return "%s: instrument %s, want %s" % [what, ip, inst]
	var got := l.sorted_notes()
	var want := []
	for n in notes:
		want.append([int(n[0]), int(n[1]), int(n[2]), snappedf(float(n[3]), 1e-6)])
	want.sort()
	if got.size() != want.size():
		return "%s: %d notes, want %d" % [what, got.size(), want.size()]
	for i in got.size():
		if got[i][0] != want[i][0] or got[i][1] != want[i][1] or got[i][2] != want[i][2] or absf(got[i][3] - want[i][3]) > 0.02:
			return "%s note %d: %s, want %s" % [what, i, got[i], want[i]]
	return ""


# ------------------------------------------------------------------ measuring

static func _snr(a: AKBuffer, ref: AKBuffer, n: int) -> float:
	var se := 0.0
	var ss := 0.0
	for i in mini(n, mini(a.frames(), ref.frames())):
		var el := a.l[i] - ref.l[i]
		var er := a.r[i] - ref.r[i]
		se += el * el + er * er
		ss += ref.l[i] * ref.l[i] + ref.r[i] * ref.r[i]
	return 10.0 * log(ss / maxf(se, 1e-30)) / log(10.0)


func _rms(b: AKBuffer, from: int, to: int) -> float:
	var s := 0.0
	var n := 0
	for i in range(maxi(0, from), mini(to, b.frames())):
		s += b.l[i] * b.l[i]
		n += 1
	return sqrt(s / maxi(1, n))


## A hit starts at `t`: clearly louder in the 30 ms after than in the 5 ms
## before (a long 909 kick can land on the last one's tail, so not by much).
func _onset(b: AKBuffer, t: float) -> bool:
	var at := roundi(t * SR)
	return _rms(b, at, at + 1440) > 1.3 * _rms(b, at - 240, at) + 1e-3


func _band(b: AKBuffer, at: int, f: float) -> float:
	return _goertzel(b, at, 8192, f)


func _pitch_ok(buf: AKBuffer, t: float, hz: float) -> bool:
	var n := 2048
	var start := clampi(roundi(t * buf.sample_rate) - n / 2, 0, maxi(0, buf.frames() - n))
	var best := -1
	var best_e := -INF
	for k in range(-12, 13):
		var f := hz * pow(2.0, k / 12.0)
		var e := 0.0
		for h in [1, 2, 3]:
			e += log(_goertzel(buf, start, n, f * h) + 1e-12)
		if e > best_e:
			best_e = e
			best = k
	return best == 0


func _goertzel(buf: AKBuffer, start: int, n: int, f: float) -> float:
	var w := TAU * f / buf.sample_rate
	var c := 2.0 * cos(w)
	var s1 := 0.0
	var s2 := 0.0
	for i in mini(n, buf.frames() - start):
		var win := 0.5 - 0.5 * cos(TAU * i / (n - 1))
		var x := 0.5 * (buf.l[start + i] + buf.r[start + i]) * win
		var s0 := x + c * s1 - s2
		s2 = s1
		s1 = s0
	return s1 * s1 + s2 * s2 - c * s1 * s2
