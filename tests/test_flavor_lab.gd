# SPDX-License-Identifier: Apache-2.0
# The Flavor page (docs/plans/flavor-tab.md): its knobs and switches drive one
# patch, with undo, randomise, save and reopen, and MIDI learn with pickup.
extends RefCounted

const OUT := "user://test_flavor_lab/"


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _lab() -> AKFlavorLab:
	var lab := AKFlavorLab.new()
	_tree().root.add_child(lab)
	lab.set_save_dir(OUT)
	lab.auto_level = false   # levelling renders; test_flavor.gd covers it
	return lab


func _done(lab: AKFlavorLab) -> void:
	lab.router.all_notes_off()
	lab.queue_free()


func _near(a: float, b: float, tol := 1e-6) -> bool:
	return absf(a - b) <= tol


func test_knob_control() -> String:
	var k := AKKnob.new()
	k.two_way = true
	var got := []
	k.changed.connect(func(v: float) -> void: got.append(v))
	if not _near(k.turn_to(0.5), 0.5) or got != [0.5]:
		return "turn_to(0.5) gave %s, signals %s" % [k.value, str(got)]
	if not _near(k.turn_to(0.02), 0.0):
		return "a two-way knob should snap to rest near the middle (%s)" % k.value
	if not _near(k.turn_to(-3.0), -1.0) or not _near(k.turn_to(3.0), 1.0):
		return "a two-way knob should clamp to -1 .. 1"
	if not _near(k.angle_of(0.0), 0.0) or not _near(k.angle_of(1.0), AKKnob.SWEEP * 0.5) or not _near(k.angle_of(-1.0), -AKKnob.SWEEP * 0.5):
		return "a two-way knob should point straight up at rest"
	k.two_way = false
	if not _near(k.value, 1.0) or not _near(k.turn_to(-0.5), 0.0):
		return "an add-only knob should clamp to 0 .. 1 (%s)" % k.value
	if not _near(k.angle_of(0.0), -AKKnob.SWEEP * 0.5):
		return "an add-only knob should rest fully left"
	k.free()
	return ""


func test_page_has_every_control() -> String:
	var lab := _lab()
	var err := ""
	for k: Dictionary in AKFlavor.KNOBS:
		var kn := lab.knobs.get(k.id) as AKKnob
		if kn == null or kn.two_way != k.two_way or kn.high_text != k.high or kn.low_text != k.low:
			err = "no proper knob for %s" % k.id
	for sw: Dictionary in AKFlavor.SWITCHES:
		if not (lab.switches.get(sw.id) is CheckBox):
			err = "no switch for %s" % sw.id
	if err == "" and AKFlavor.fingerprint(lab.patch) != AKFlavor.fingerprint(AKFlavor.build()):
		err = "the page should start on the base sound"
	if err == "" and lab.router.patch != lab.patch:
		err = "the keyboard does not play the page's patch"
	_done(lab)
	return err


func test_controls_rebuild_the_same_patch() -> String:
	var lab := _lab()
	var p := lab.patch
	var edits := [0]
	p.changed.connect(func() -> void: edits[0] += 1)
	lab.set_knob("lean_beefy", 1.0)
	lab.set_switch("pump", true)
	var err := ""
	if lab.patch != p:
		err = "a move replaced the patch object (a playing synth would not hear it as an edit)"
	elif edits[0] < 2:
		err = "the patch did not signal its edits"
	elif AKFlavor.fingerprint(p) != AKFlavor.fingerprint(AKFlavor.build({lean_beefy = 1.0, pump = true})):
		err = "the patch is not what the controls say"
	elif not _near(AKFlavor.settings_of(p).lean_beefy, 1.0) or AKFlavor.is_stale(p):
		err = "the patch should carry the control positions"
	# A drag on the knob itself.
	if err == "":
		(lab.knobs["shut_quack"] as AKKnob).turn_to(-0.5)
		if not _near(lab.settings.shut_quack, -0.5) or not _near(p.filter.resonance, 0.4):
			err = "turning the knob control did not reach the patch (resonance %s)" % p.filter.resonance
	# A click on a switch.
	if err == "":
		(lab.switches["wide"] as CheckBox).button_pressed = true
		if not lab.settings.wide or not _near(p.spread, 1.0):
			err = "ticking a switch did not reach the patch"
	_done(lab)
	return err


func test_minor_and_slinky_notes() -> String:
	var lab := _lab()
	var minor := lab.switches["minor"] as CheckBox
	var err := ""
	if not minor.disabled:
		err = "Minor should be greyed out until Note/Chord's third is in"
	lab.set_knob("note_chord", 0.8)
	if err == "" and minor.disabled:
		err = "Minor should be available once Note/Chord is past 0.6"
	if err == "" and lab._mono_note.visible:
		err = "the one-note-at-a-time note should be hidden while Slinky is at rest"
	lab.set_knob("stiff_slinky", 0.3)
	if err == "" and (not lab._mono_note.visible or lab.patch.mode != "mono"):
		err = "Slinky should show its note and play one note at a time"
	_done(lab)
	return err


func test_undo_reset_randomise_mutate() -> String:
	var lab := _lab()
	var err := ""
	lab.set_knob("murky_sparkly", 0.7)
	lab.settle()
	lab.set_knob("clean_filthy", 1.0)
	lab.settle()
	if lab.history.size() != 3:
		err = "three settled sounds expected, got %d" % lab.history.size()
	if err == "" and (not lab.undo() or not _near(lab.settings.clean_filthy, 0.0) or not _near(lab.settings.murky_sparkly, 0.7)):
		err = "undo should step back one change: %s" % str(lab.settings)
	if err == "" and not _near((lab.knobs["clean_filthy"] as AKKnob).value, 0.0):
		err = "undo did not move the knob on screen"
	if err == "":
		lab.undo()
		if lab.undo() or AKFlavor.fingerprint(lab.patch) != AKFlavor.fingerprint(AKFlavor.build()):
			err = "undo should stop at the first sound"
	if err == "":
		lab.randomise()
		var a := lab.settings.duplicate()
		if a == AKFlavor.defaults():
			err = "randomise left the base sound"
		lab.mutate()
		if err == "" and lab.settings == a:
			err = "mutate changed nothing"
		lab.undo()
		if err == "" and lab.settings != a:
			err = "undo after mutate should return the randomised sound"
		lab.reset()
		if err == "" and lab.settings != AKFlavor.defaults():
			err = "reset should put every control at rest"
	_done(lab)
	return err


func test_save_open_and_stale_notice() -> String:
	var lab := _lab()
	lab.set_settings({woody_glassy = 1.0, dry_drenched = 0.4, lofi = true})
	lab._name.text = "glass test"
	var path := lab.save_patch()
	var err := ""
	if path != OUT + "patches/glass test.tres" or not FileAccess.file_exists(path):
		err = "saved to %s" % path
	if err == "" and AKPatch.library_info(ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)).get("source", "") != "flavor":
		err = "a saved sound should carry library metadata with source flavor"
	lab.reset()
	if err == "" and not lab.open_flavor(path):
		err = "could not reopen the saved sound"
	if err == "" and (not _near(lab.settings.woody_glassy, 1.0) or not _near(lab.settings.dry_drenched, 0.4) or not lab.settings.lofi
			or not _near((lab.knobs["woody_glassy"] as AKKnob).value, 1.0) or lab._notice.visible):
		err = "the controls did not return to the saved positions"
	if err == "" and not lab._saved_paths.has(path):
		err = "the saved sound is not in the page's list"
	# Edited elsewhere, then reopened: it opens, with a notice.
	if err == "":
		var q: AKPatch = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		q.unison = 5
		ResourceSaver.save(q, path)
		if not lab.open_flavor(path) or not lab._notice.visible:
			err = "an edited patch should open with the 'edited since' notice"
	# A patch that never came from this page has no knob positions.
	if err == "" and lab.open_flavor(AKPatch.new()):
		err = "a plain patch should not open on the Flavor page"
	# Open in Synth hands over a copy that still carries the positions.
	if err == "":
		var got := []
		lab.open_patch.connect(func(p: AKPatch) -> void: got.append(p))
		var copy := lab.open_in_synth()
		if got != [copy] or copy == lab.patch or AKFlavor.settings_of(copy).is_empty():
			err = "Open in Synth should emit a copy that keeps its settings"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_done(lab)
	return err


func test_midi_learn_and_pickup() -> String:
	var lab := _lab()
	var err := ""
	if not _near(AKFlavorLab.controller_value(true, 64), 0.0) or not _near(AKFlavorLab.controller_value(true, 127), 1.0) \
			or not _near(AKFlavorLab.controller_value(true, 0), -1.0) or not _near(AKFlavorLab.controller_value(true, 66), 0.0) \
			or not _near(AKFlavorLab.controller_value(false, 0), 0.0) or not _near(AKFlavorLab.controller_value(false, 127), 1.0):
		err = "controller values map wrongly onto the knob ranges"
	# Learn: the next controller links to the knob, and moves nothing.
	lab.learn("lean_beefy")
	if err == "" and not (lab.knobs["lean_beefy"] as AKKnob).learning:
		err = "the knob should show it is learning"
	lab.handle_controller(21, 100)
	if err == "" and (lab.midi_links.get("lean_beefy") != 21 or lab.learning != "" or not _near(lab.settings.lean_beefy, 0.0)
			or not (lab.knobs["lean_beefy"] as AKKnob).linked):
		err = "learn should link controller 21 without moving the knob"
	# Pickup: the hardware knob is at 100 (about +0.57), the screen at 0: nothing
	# moves until the hardware passes the on-screen position.
	lab.handle_controller(21, 110)
	if err == "" and not _near(lab.settings.lean_beefy, 0.0):
		err = "the knob jumped to the hardware position"
	lab.handle_controller(21, 80)
	if err == "" and not _near(lab.settings.lean_beefy, 0.0):
		err = "the knob moved before the hardware reached it"
	lab.handle_controller(21, 60)   # crosses rest
	lab.handle_controller(21, 96)
	if err == "" and not _near(lab.settings.lean_beefy, AKFlavorLab.controller_value(true, 96)):
		err = "after pickup the knob should follow the hardware (%s)" % lab.settings.lean_beefy
	if err == "" and not _near((lab.knobs["lean_beefy"] as AKKnob).value, lab.settings.lean_beefy):
		err = "the knob on screen did not follow"
	# Moving it on screen drops the pickup again.
	lab.set_knob("lean_beefy", -1.0)
	lab.handle_controller(21, 100)
	if err == "" and not _near(lab.settings.lean_beefy, -1.0):
		err = "a knob moved on screen should need picking up again"
	# Another controller does nothing; a second learn moves the link.
	lab.handle_controller(22, 127)
	if err == "" and not _near(lab.settings.lean_beefy, -1.0):
		err = "an unlinked controller moved a knob"
	lab.learn("clean_filthy")
	lab.handle_controller(21, 5)
	if err == "" and (lab.midi_links.has("lean_beefy") or lab.midi_links.get("clean_filthy") != 21):
		err = "a controller should link to one knob at a time"
	lab.forget("clean_filthy")
	if err == "" and not lab.midi_links.is_empty():
		err = "forget should drop the link"
	# Through the router, as a real controller message arrives.
	lab.learn("still_swirl")
	lab.router.controller(30, 64)   # links
	lab.router.controller(30, 0)    # at the on-screen position: picked up
	lab.router.controller(30, 127)
	if err == "" and not _near(lab.settings.still_swirl, 1.0):
		err = "a controller message through the router did not reach the knob (%s)" % lab.settings.still_swirl
	_done(lab)
	return err


## Levelling runs on Save only: settling a loud sound leaves it alone (no hitch after a
## move), and saving it sets its fixed gain (full Beefy comes down a few dB).
func test_levels_on_save_only() -> String:
	var lab := _lab()
	lab.auto_level = true
	lab.set_settings({lean_beefy = 1.0})
	lab._name.text = "level test"
	var err := ""
	if lab.settle() != 0.0 or lab.level_gain_db != 0.0:
		err = "settling should not level (gain %.2f dB)" % lab.level_gain_db
	if err == "":
		var path := lab.save_patch()
		if path == "":
			err = "the save failed"
		elif lab.level_gain_db > -1.0 or lab.level_gain_db < -8.0:
			err = "saving full Beefy should bring it down a few dB (%.2f)" % lab.level_gain_db
		else:
			var q: AKPatch = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
			var has_gain := false
			for e: Dictionary in q.effects:
				has_gain = has_gain or e.get("flavor_gain", false)
			if not has_gain:
				err = "the saved patch should carry its level gain"
	_done(lab)
	return err
