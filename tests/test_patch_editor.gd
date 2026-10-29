# SPDX-License-Identifier: Apache-2.0
# Phase 5: the patch panels, the scope and spectrum, the preset browser, and
# the gate: an instrument built from scratch in the lab, through its
# controls, without writing a .tres by hand.
extends RefCounted

const OUT := "user://test_patch_editor/"
const SR := 48000


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _lab() -> AKSynthLab:
	var lab := AKSynthLab.new()
	_tree().root.add_child(lab)
	lab.set_save_dir(OUT)
	return lab


func _done(lab: AKSynthLab) -> void:
	lab.router.all_notes_off()
	lab.queue_free()


## The first Button under `n` whose text is `text`.
func _button(n: Node, text: String) -> Button:
	for c in n.get_children():
		if c is Button and not (c is OptionButton) and (c as Button).text == text:
			return c
		var b := _button(c, text)
		if b:
			return b
	return null


## Pick `value` in the menu bound to `path`, as a click would.
func _pick(ed: AKPatchEditor, path: String, label: String) -> String:
	var ob := ed.controls().get(path) as OptionButton
	if ob == null:
		return "no menu for %s" % path
	for i in ob.item_count:
		if ob.get_item_text(i) == label:
			ob.select(i)
			ob.item_selected.emit(i)
			return ""
	return "menu %s has no item %s" % [path, label]


## Move the slider bound to `path` to `v`, as a drag would.
func _drag(ed: AKPatchEditor, path: String, v: float) -> String:
	var s := ed.controls().get(path) as AKParamSlider
	if s == null:
		return "no slider for %s (have %s)" % [path, ed.controls().keys()]
	s.set_value_from_user(v)
	return ""


func _click(n: Node, text: String) -> String:
	var b := _button(n, text)
	if b == null:
		return "no button %s" % text
	b.pressed.emit()
	return ""


## Spectral centroid (Hz) of `n` samples from `at`.
func _centroid(m: PackedFloat32Array, at: int, n := 4096) -> float:
	var db := AKSpectrum.magnitudes_db(m.slice(at, at + n), n)
	var num := 0.0
	var den := 0.0
	for k in range(1, db.size()):
		var mag := pow(10.0, db[k] / 20.0)
		num += mag * AKSpectrum.bin_hz(k, n, SR)
		den += mag
	return num / maxf(den, 1e-12)


## A value as text, typed and untyped arrays alike.
func _text(v: Variant) -> String:
	if v is Array:
		return "[" + ", ".join(v.map(func(e: Variant) -> String: return var_to_str(e))) + "]"
	return var_to_str(v)


func _mono(b: AKBuffer) -> PackedFloat32Array:
	var m := PackedFloat32Array()
	m.resize(b.frames())
	for i in m.size():
		m[i] = 0.5 * (b.l[i] + b.r[i])
	return m


# ------------------------------------------------------------------ controls

func test_param_slider_maps_and_types() -> String:
	var s := AKParamSlider.make("Cutoff", 20.0, 20000.0, 1000.0, {log = true, unit = " Hz"})
	if absf(s.to_position(632.456) - 0.5) > 1e-3:
		return "a log slider's middle should be the geometric mean (%.4f)" % s.to_position(632.456)
	for p in [0.0, 0.25, 0.7, 1.0]:
		if absf(s.to_position(s.from_position(p)) - p) > 1e-9:
			return "position %.2f doesn't round-trip" % p
	var got := []
	s.changed.connect(func(v: float) -> void: got.append(v))
	s._typed("440 Hz")
	s._typed("not a number")
	s._typed("25000")   # typed values may leave the slider's range
	if got != [440.0, 25000.0]:
		return "typed values: %s" % [got]
	var i := AKParamSlider.make("Voices", 1.0, 7.0, 3.0, {integer = true})
	i.set_value_from_user(4.4)
	if i.get_value() != 4.0:
		return "an integer slider should round (%s)" % i.get_value()
	s.free()
	i.free()
	return ""


func test_editor_paths_undo_and_links() -> String:
	var ed := AKPatchEditor.new()
	var p := AKPatch.new()
	ed.edit(p)
	if ed.get_param("filter.cutoff_hz") != 18000.0 or ed.get_param("oscillators.0.cents") != 0.0 or ed.get_param("env2.curve") != "exp":
		return "get_param should fill defaults: %s %s %s" % [ed.get_param("filter.cutoff_hz"), ed.get_param("oscillators.0.cents"), ed.get_param("env2.curve")]
	var before := var_to_str(p.describe())
	ed.set_param("filter.cutoff_hz", 900.0)
	ed.set_param("filter.cutoff_hz", 700.0)   # a drag: merged into one action
	ed.set_param("unison", 3)
	if p.filter.cutoff_hz != 700.0 or p.unison != 3:
		return "edits didn't land: %s %d" % [p.filter, p.unison]
	ed.undo_last()
	ed.undo_last()
	if var_to_str(p.describe()) != before:
		return "two undos (one per edit, the drag merged) should restore the patch"
	ed.redo_last()
	if p.filter.cutoff_hz != 700.0:
		return "redo should bring back the drag's last value (%s)" % p.filter.cutoff_hz
	# Removing an oscillator renumbers links and drops rows aimed at it.
	ed.add_oscillator({shape = "sine", level = 0.0})
	ed.add_oscillator({shape = "sine", level = 0.0})
	ed.set_param("oscillators.0.fm_from", 3)
	ed.set_param("oscillators.0.fm_index", 2.0)
	ed.set_param("oscillators.2.sync_to", 2)
	ed.add_mod("lfo1", "osc2.pitch", 1.0)
	ed.add_mod("env2", "osc3.fm", 2.0)
	ed.remove_oscillator(1)
	if p.oscillators.size() != 2 or int(p.oscillators[0].fm_from) != 2 or p.oscillators[1].has("sync_to"):
		return "links after removing oscillator 2: %s" % [p.oscillators]
	if p.mods.size() != 1 or p.mods[0].dest != "osc2.fm":
		return "matrix after removing oscillator 2: %s" % [p.mods]
	ed.undo_last()
	if p.oscillators.size() != 3 or p.mods.size() != 2:
		return "undoing the removal should restore oscillators and rows together"
	# Effects: add, reorder, remove.
	ed.add_effect("eq")
	ed.add_effect("chorus")
	ed.move_effect(1, -1)
	if p.effects.map(func(e: Dictionary) -> String: return e.type) != ["chorus", "eq"]:
		return "effect order: %s" % [p.effects]
	if p.effects[0].rate_hz != AKStreamFx.DEFAULTS.chorus.rate_hz:
		return "a new effect should carry its defaults"
	ed.remove_effect(0)
	if p.effects.size() != 1:
		return "remove effect"
	# The patch must still compile cleanly.
	if p.compile().osc.size() != 3:
		return "the edited patch should compile"
	ed.free()
	return ""


func test_panels_follow_the_patch() -> String:
	var ed := AKPatchEditor.new()
	var p := AKPatchLib.preset(&"sync_lead")
	ed.edit(p)
	var c := ed.controls()
	for path in ["oscillators.0.shape", "oscillators.1.sync_to", "filter.resonance", "amp_env.attack_s", "env2.curve",
			"lfo1.rate_hz", "mods.0.amount", "polyphony", "seed"]:
		if not c.has(path):
			return "no control for %s" % path
	if c.has("filter.q"):
		return "a ladder filter has resonance, not Q"
	if absf((c["filter.cutoff_hz"] as AKParamSlider).get_value() / float(p.filter.cutoff_hz) - 1.0) > 0.005:
		return "the cutoff slider should show the patch's value (%s vs %s)" % [(c["filter.cutoff_hz"] as AKParamSlider).get_value(), p.filter.cutoff_hz]
	# A menu edit rebuilds: switching to an SVF shows Q and slope.
	var err := _pick(ed, "filter.type", "lowpass")
	if err != "":
		return err
	ed.rebuild()
	c = ed.controls()
	if not c.has("filter.q") or not c.has("filter.slope_db") or c.has("filter.resonance"):
		return "after switching to lowpass the filter panel should show Q and slope"
	# Matrix destinations name each oscillator.
	var d := ed.mod_destinations()
	if not d.has("osc2.pitch") or not d.has("osc.position") or d.has("osc3.pitch"):
		return "matrix destinations for two oscillators: %s" % [d]
	# Effect panels: one slider per setting.
	ed.add_effect("phaser")
	ed.rebuild()
	for k in AKStreamFx.DEFAULTS.phaser:
		if not ed.controls().has("effects.%d.%s" % [p.effects.size() - 1, k]):
			return "the phaser panel lacks %s" % k
	ed.free()
	return ""


# ------------------------------------------------------------------ scope and spectrum

func test_spectrum_measures() -> String:
	var n := 8192
	var x := PackedFloat32Array()
	x.resize(n)
	for i in n:
		x[i] = 0.5 * sin(TAU * 1000.0 * i / SR) + 0.05 * sin(TAU * 5000.0 * i / SR)
	var hz := AKSpectrum.peak_hz(x, SR, n)
	if absf(hz - 1000.0) > 1.0:
		return "peak at %.2f Hz (want 1000)" % hz
	var db := AKSpectrum.magnitudes_db(x, n)
	var k := roundi(1000.0 * n / SR)
	var peak := maxf(db[k], maxf(db[k - 1], db[k + 1]))
	if absf(peak - (-6.02)) > 1.6:   # Hann scalloping is up to 1.4 dB
		return "a half-scale sine should read about -6 dB (%.2f)" % peak
	# The FFT against a direct DFT.
	var re := PackedFloat64Array()
	var im := PackedFloat64Array()
	var src := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 64:
		src.append(rng.randf_range(-1.0, 1.0))
		re.append(src[i])
		im.append(0.0)
	AKSpectrum.fft(re, im)
	for kk in 64:
		var dr := 0.0
		var di := 0.0
		for i in 64:
			dr += src[i] * cos(-TAU * kk * i / 64.0)
			di += src[i] * sin(-TAU * kk * i / 64.0)
		if absf(dr - re[kk]) > 1e-9 or absf(di - im[kk]) > 1e-9:
			return "FFT bin %d differs from the DFT" % kk
	return ""


func test_scope_trigger_and_live_tap() -> String:
	var sc := AKScope.new()
	sc.window = 400
	var x := PackedFloat32Array()
	for i in 4096:
		x.append(sin(TAU * 220.0 * (i + 37) / SR))
	sc.show_samples(x)
	var t := sc.trigger_index()
	if not (x[t - 1] <= 0.0 and x[t] > 0.0) or t > x.size() - sc.window:
		return "the scope should start on a rising zero crossing that leaves a window (%d)" % t
	sc.free()
	if not AKSynth.available():
		return ""
	# The live stream keeps its last frames for the scope: exactly what it played.
	var s: Object = ClassDB.instantiate(&"AKSynthStream")
	s.patch = AKPatchLib.preset(&"organ")
	s.note_on(60, 0.9)
	var out: Array = s.render_offline(6000)
	var recent: PackedFloat32Array = s.get_recent(2048)
	for i in 2048:
		var j := 6000 - 2048 + i
		if absf(recent[i] - 0.5 * (out[0][j] + out[1][j])) > 1e-7:
			return "get_recent should hold the last frames played (frame %d)" % j
	if s.get_recent(100000).size() != 8192:
		return "get_recent caps at 8192 frames"
	return ""


# ------------------------------------------------------------------ browser

func test_preset_browser() -> String:
	var b := AKPresetBrowser.new()
	var all := b.entries()
	if all.size() < AKPatchLib.preset_names().size() + 16:
		return "the browser should list the presets and the bank (%d)" % all.size()
	for e in all:
		if e.source != "yours" and not AKPatch.CATEGORIES.has(e.category):
			return "%s has no category" % e.path
	var bells := b.filtered("", "bell")
	for want in ["fm_bell.tres", "ring_bell.tres", "gm_chromatic_percussion.tres"]:
		if not bells.any(func(pth: String) -> bool: return pth.ends_with(want)):
			return "the bell category should hold %s: %s" % [want, bells]
	var q := b.filtered("acid")
	if q.size() != 1 or not String(q[0]).ends_with("acid_bass.tres"):
		return "searching 'acid': %s" % [q]
	b.set_filter("", "bass")
	if b.shown().is_empty() or b.shown().any(func(pth: String) -> bool: return (load(pth) as AKPatch).category != "bass"):
		return "the bass filter should show only basses"
	b.free()
	return ""


# ------------------------------------------------------------------ the lab

func test_lab_edits_copies_and_saves() -> String:
	DirAccess.make_dir_recursive_absolute(OUT)
	var lab := _lab()
	var shipped: AKPatch = load("res://addons/audio_kit/patches/pluck.tres")
	var before := var_to_str(shipped.describe())
	lab.select_patch("res://addons/audio_kit/patches/pluck.tres")
	lab.editor.set_param("filter.cutoff_hz", 3000.0)
	if var_to_str(shipped.describe()) != before:
		_done(lab)
		return "editing a kit preset in the lab should change a copy, not the preset"
	if lab.router.patch != lab.patch:
		_done(lab)
		return "the keyboard should play the patch being edited"
	lab._save_name.text = "my_pluck"
	var path := lab.save_patch()
	if path != OUT + "patches/my_pluck.tres" or lab.patch.resource_path != path:
		_done(lab)
		return "Save should write %spatches/my_pluck.tres and go on editing it (%s, %s)" % [OUT, path, lab.patch.resource_path]
	if not lab.browser.shown().has(path):
		_done(lab)
		return "the browser should list the saved patch under yours"
	var p := lab.preview_note()
	if p == null or p.peak() < 0.05:
		_done(lab)
		return "the preview note should render"
	if lab.note_view.get(&"_samples").size() != p.frames():
		_done(lab)
		return "the preview should show in the note view"
	_done(lab)
	DirAccess.remove_absolute(path)
	return ""


## The gate: build an instrument from a blank patch with the lab's controls
## only, save it, and check the file holds exactly what was built and that it
## sounds like it.
func test_gate_instrument_from_scratch() -> String:
	DirAccess.make_dir_recursive_absolute(OUT)
	var lab := _lab()
	var ed := lab.editor
	var steps: Array[Callable] = [
		func() -> String: return _click(lab, "New"),
		# A square an octave below a saw.
		func() -> String: return _pick(ed, "oscillators.0.shape", "square"),
		func() -> String: return _drag(ed, "oscillators.0.semitones", -12.0),
		func() -> String: return _click(ed, "+ Oscillator"),
		func() -> String: return _pick(ed, "oscillators.1.shape", "saw"),
		func() -> String: return _drag(ed, "oscillators.1.cents", 7.0),
		# A resonant ladder, opened by envelope 2 and velocity.
		func() -> String: return _pick(ed, "filter.type", "ladder"),
		func() -> String: return _drag(ed, "filter.cutoff_hz", 300.0),
		func() -> String: return _drag(ed, "filter.resonance", 0.55),
		func() -> String: return _drag(ed, "env2.decay_s", 0.25),
		func() -> String: return _click(ed, "+ Row"),
		func() -> String: return _pick(ed, "mods.0.source", "env2"),
		func() -> String: return _pick(ed, "mods.0.dest", "cutoff"),
		func() -> String: return _drag(ed, "mods.0.amount", 4.0),
		func() -> String: return _click(ed, "+ Row"),
		func() -> String: return _pick(ed, "mods.1.source", "velocity"),
		func() -> String: return _pick(ed, "mods.1.dest", "cutoff"),
		func() -> String: return _drag(ed, "mods.1.amount", 1.0),
		# Envelope, voice and an effect.
		func() -> String: return _drag(ed, "amp_env.sustain", 0.6),
		func() -> String: return _drag(ed, "amp_env.release_s", 0.3),
		func() -> String: return _drag(ed, "unison", 2.0),
		func() -> String: return _drag(ed, "detune_cents", 12.0),
		func() -> String: return _drag(ed, "spread", 0.8),
		func() -> String: return _pick(ed, "mode", "poly"),
		func() -> String: return _click(ed, "chorus"),
		func() -> String: return _drag(ed, "effects.0.mix", 0.35),
	]
	for i in steps.size():
		var err: String = steps[i].call()
		if err != "":
			_done(lab)
			return "step %d: %s" % [i, err]
		# Structural edits rebuild the panels on the next frame, as in the editor.
		await _tree().process_frame
	lab._save_name.text = "gate_bass"
	var path := lab.save_patch()
	var want := {oscillators = [{shape = "square", level = 0.7, semitones = -12}, {shape = "saw", level = 0.5, cents = 7.0}],
		filter = {type = "ladder", cutoff_hz = 300.0, q = 0.707, slope_db = 12.0, resonance = 0.55},
		env2 = {attack_s = 0.0, decay_s = 0.25, sustain = 0.0, release_s = 0.2, curve = "exp"},
		mods = [{source = "env2", dest = "cutoff", amount = 4.0}, {source = "velocity", dest = "cutoff", amount = 1.0}],
		amp_env = {attack_s = 0.005, decay_s = 0.2, sustain = 0.6, release_s = 0.3},
		unison = 2, detune_cents = 12.0, spread = 0.8}
	var saved: AKPatch = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if saved == null:
		_done(lab)
		return "the instrument wasn't saved (%s)" % path
	for k in want:
		if _text(saved.get(k)) != _text(want[k]):
			_done(lab)
			return "%s in the saved file: %s (want %s)" % [k, _text(saved.get(k)), _text(want[k])]
	if saved.effects.size() != 1 or saved.effects[0].type != "chorus" or saved.effects[0].mix != 0.35:
		_done(lab)
		return "the saved effects: %s" % [saved.effects]
	# It sounds like what was built: the filter envelope makes the attack
	# brighter than the held part, harder notes are brighter, and the spread
	# and chorus make it stereo.
	var hard := AKSynth.render_notes(saved, [{time_s = 0.0, note = 48, length_s = 0.8, velocity = 1.0}])
	var soft := AKSynth.render_notes(saved, [{time_s = 0.0, note = 48, length_s = 0.8, velocity = 0.3}])
	var m := _mono(hard)
	var early := _centroid(m, int(0.02 * SR))
	var late := _centroid(m, int(0.6 * SR))
	if early < late * 1.5:
		_done(lab)
		return "the filter envelope should brighten the attack (centroid %.0f Hz early, %.0f Hz held)" % [early, late]
	var soft_early := _centroid(_mono(soft), int(0.02 * SR))
	if soft_early > early * 0.9:
		_done(lab)
		return "velocity should brighten (%.0f Hz soft vs %.0f Hz hard)" % [soft_early, early]
	var diff := 0.0
	for i in range(int(0.3 * SR), int(0.5 * SR)):
		diff = maxf(diff, absf(hard.l[i] - hard.r[i]))
	if diff < 0.01:
		_done(lab)
		return "spread and chorus should make it stereo"
	if hard.peak() < 0.1 or hard.peak() > 1.5:
		_done(lab)
		return "level %.2f" % hard.peak()
	# And the live engine plays the saved file (when the native core is here).
	if AKSynth.available():
		lab.select_patch(path)
		lab.note_on(48, 1.0)
		var s: Object = lab.router.synth()
		var live: Array = s.render_offline(4800)
		var peak := 0.0
		for x in live[0]:
			peak = maxf(peak, absf(x))
		if peak < 0.05:
			_done(lab)
			return "the keyboard should play the new instrument live"
	_done(lab)
	DirAccess.remove_absolute(path)
	return ""


# ------------------------------------------------------------------ demos

func test_demo_scenes_run() -> String:
	var tree := _tree()
	var kb: Node = (load("res://demo/sound_lab/keyboard_demo.tscn") as PackedScene).instantiate()
	tree.root.add_child(kb)
	await tree.process_frame
	if kb.get(&"router") == null or kb.get(&"keyboard") == null:
		kb.queue_free()
		return "the keyboard demo didn't build"
	var bus := AudioServer.get_bus_index(&"Synth FX")
	if bus < 0 or (AKSynth.available() and not AudioServer.get_bus_effect(bus, 0).is_class("AKChorus")):
		kb.queue_free()
		return "the keyboard demo should route through a bus with the kit's chorus"
	if AKSynth.available():
		var r: AKMidiRouter = kb.get(&"router")
		r.note_on(60, 0.9)
		var s: Object = r.synth()
		s.render_offline(960)
		if s.voice_count() != 1:
			kb.queue_free()
			return "the keyboard demo should play its patch"
		r.all_notes_off()
	kb.queue_free()
	await tree.process_frame
	AudioServer.remove_bus(AudioServer.get_bus_index(&"Synth FX"))
	var sfx: Node = (load("res://demo/sound_lab/sfx_demo.tscn") as PackedScene).instantiate()
	tree.root.add_child(sfx)
	var players: Dictionary = sfx.get(&"players")
	if players.size() != AKSfxGen.CATEGORIES.filter(func(c: StringName) -> bool: return c != &"random").size():
		sfx.queue_free()
		return "the SFX demo should have a button per category (%d)" % players.size()
	for cat in players:
		if not ((players[cat] as AudioStreamPlayer).stream is AKRecipeStream):
			sfx.queue_free()
			return "%s should play a recipe stream" % cat
	sfx.call(&"play", &"laser")
	sfx.queue_free()
	# The song demo's .mid imports as a song; it plays live with the native
	# core (without, it renders the whole song first: too slow for a test).
	var song := load("res://demo/sound_lab/minuet.mid") as AKSong
	if song == null or song.sections.is_empty():
		return "minuet.mid should import as a song"
	if AKSynth.available():
		var md: Node = (load("res://demo/sound_lab/midi_song_demo.tscn") as PackedScene).instantiate()
		tree.root.add_child(md)
		var live: AKLive = md.get(&"live")
		var a := live.render_playing(SR)
		md.queue_free()
		if a.peak() < 0.02:
			return "the song demo should play"
	return ""


func test_all_off_clears_lit_keys() -> String:
	var lab := _lab()
	lab.note_on(60, 0.8)
	lab.note_on(64, 0.8)
	if lab.keyboard.get(&"_marked").size() != 2:
		_done(lab)
		return "played notes should light their keys"
	lab.router.all_notes_off()
	var left: int = lab.keyboard.get(&"_marked").size()
	_done(lab)
	return "" if left == 0 else "all notes off should unlight the keys (%d still lit)" % left
