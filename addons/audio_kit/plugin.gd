# SPDX-License-Identifier: Apache-2.0
@tool
extends EditorPlugin
## Adds the Sound Lab main screen (beside 2D, 3D and Script: the SFX generator,
## the synth page with its preset browser, patch panels and scopes, and the
## Loops page with its grid, loop and sound browsers, and the Sequencer
## with its scenes, timeline and tracks, and the Pseudo-Speech page), the
## .mid importer, and the Audio Kit dock, which
## plays whatever recipe, recipe stream, song, pattern, cue map or patch is in
## the inspector.

var _dock: AKAuditionDock
var _screen: TabContainer
var _lab: AKSoundLab
var _synth: AKSynthLab
var _loops: AKLoopLab
var _seq: AKSequencerLab
var _speech: AKSpeechLab
var _midi_import: EditorImportPlugin


func _enter_tree() -> void:
	_dock = AKAuditionDock.new()
	_dock.open_in_lab.connect(_open_patch_in_lab)
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, _dock)   # under the inspector: edit and listen side by side
	EditorInterface.get_inspector().edited_object_changed.connect(_on_edited)
	EditorInterface.get_inspector().property_edited.connect(_on_property_edited)
	# The Sound Lab screen: SFX (generator) and Synth (patches, keyboard, songs).
	_screen = TabContainer.new()
	_screen.name = "Sound Lab"
	_screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lab = AKSoundLab.new()
	_lab.name = "SFX"
	_screen.add_child(_lab)
	_synth = AKSynthLab.new()
	_synth.name = "Synth"
	_screen.add_child(_synth)
	_loops = AKLoopLab.new()
	_loops.name = "Loops"
	_loops.open_patch.connect(_open_patch_in_lab)
	_screen.add_child(_loops)
	_seq = AKSequencerLab.new()
	_seq.name = "Sequencer"
	_seq.open_loop.connect(_open_loop_in_lab)
	_seq.tempo_changed.connect(func(bpm: float) -> void: _loops.set_tempo(bpm))
	_screen.add_child(_seq)
	_speech = AKSpeechLab.new()
	_speech.name = "Pseudo-Speech"
	_screen.add_child(_speech)
	EditorInterface.get_editor_main_screen().add_child(_screen)
	_make_visible(false)
	_midi_import = preload("res://addons/audio_kit/editor/midi_import.gd").new()
	add_import_plugin(_midi_import)


func _exit_tree() -> void:
	var insp := EditorInterface.get_inspector()
	if insp.edited_object_changed.is_connected(_on_edited):
		insp.edited_object_changed.disconnect(_on_edited)
	if insp.property_edited.is_connected(_on_property_edited):
		insp.property_edited.disconnect(_on_property_edited)
	if _dock:
		_dock.stop()
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
	if _midi_import:
		remove_import_plugin(_midi_import)
		_midi_import = null
	if _screen:
		_lab.stop()
		_synth.stop_song()
		_synth.router.all_notes_off()
		_loops.stop()
		_seq.stop()
		_speech.stop()
		_screen.queue_free()
		_screen = null
		_lab = null
		_synth = null
		_loops = null
		_seq = null
		_speech = null


func _has_main_screen() -> bool:
	return true


func _get_plugin_name() -> String:
	return "Sound Lab"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon(&"AudioStreamPlayer", &"EditorIcons")


func _make_visible(visible: bool) -> void:
	if _screen:
		_screen.visible = visible
		_lab.set_process(visible)


func _open_patch_in_lab(patch: AKPatch) -> void:
	if patch == null or _synth == null:
		return
	EditorInterface.set_main_screen_editor("Sound Lab")
	_screen.current_tab = _synth.get_index()
	_synth.select_patch(patch)


## A Sequencer clip's loop, opened in the Loops tab with the music around it
## as context, at the arrangement's tempo.
func _open_loop_in_lab(path: String, context: Array, bpm: float) -> void:
	if _loops == null or path == "":
		return
	_seq.stop()
	_screen.current_tab = _loops.get_index()
	_loops.open_loop(path)
	_loops.clear_context()
	for l in context:
		_loops.add_context(l)
	_loops.set_tempo(bpm)
	_loops.set_context(not context.is_empty())


## A patch edited in the inspector tells its listeners (a playing stream,
## the lab's panels), as an edit in the lab does.
func _on_property_edited(_property: String) -> void:
	var p := EditorInterface.get_inspector().get_edited_object() as AKPatch
	if p:
		p.emit_changed()


func _on_edited() -> void:
	if _dock:
		_dock.show_resource(EditorInterface.get_inspector().get_edited_object())
