# SPDX-License-Identifier: Apache-2.0
@tool
extends EditorPlugin
## Adds the Sound Lab main screen (beside 2D, 3D and Script: the SFX generator
## and the synth page), the .mid importer, and the Audio Kit dock, which
## plays whatever recipe, recipe stream, song, pattern, cue map or patch is in
## the inspector.

var _dock: AKAuditionDock
var _screen: TabContainer
var _lab: AKSoundLab
var _synth: AKSynthLab
var _midi_import: EditorImportPlugin


func _enter_tree() -> void:
	_dock = AKAuditionDock.new()
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, _dock)   # under the inspector: edit and listen side by side
	EditorInterface.get_inspector().edited_object_changed.connect(_on_edited)
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
	EditorInterface.get_editor_main_screen().add_child(_screen)
	_make_visible(false)
	_midi_import = preload("res://addons/audio_kit/editor/midi_import.gd").new()
	add_import_plugin(_midi_import)


func _exit_tree() -> void:
	var insp := EditorInterface.get_inspector()
	if insp.edited_object_changed.is_connected(_on_edited):
		insp.edited_object_changed.disconnect(_on_edited)
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
		_screen.queue_free()
		_screen = null
		_lab = null
		_synth = null


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


func _on_edited() -> void:
	if _dock:
		_dock.show_resource(EditorInterface.get_inspector().get_edited_object())
