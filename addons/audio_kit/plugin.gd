# SPDX-License-Identifier: Apache-2.0
@tool
extends EditorPlugin
## Adds the Sound Lab main screen (beside 2D, 3D and Script) and the Audio
## Kit dock, which plays whatever recipe, recipe stream, song, pattern or cue
## map is in the inspector.

var _dock: AKAuditionDock
var _lab: AKSoundLab


func _enter_tree() -> void:
	_dock = AKAuditionDock.new()
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, _dock)   # under the inspector: edit and listen side by side
	EditorInterface.get_inspector().edited_object_changed.connect(_on_edited)
	_lab = AKSoundLab.new()
	EditorInterface.get_editor_main_screen().add_child(_lab)
	_make_visible(false)


func _exit_tree() -> void:
	var insp := EditorInterface.get_inspector()
	if insp.edited_object_changed.is_connected(_on_edited):
		insp.edited_object_changed.disconnect(_on_edited)
	if _dock:
		_dock.stop()
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
	if _lab:
		_lab.stop()
		_lab.queue_free()
		_lab = null


func _has_main_screen() -> bool:
	return true


func _get_plugin_name() -> String:
	return "Sound Lab"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon(&"AudioStreamPlayer", &"EditorIcons")


func _make_visible(visible: bool) -> void:
	if _lab:
		_lab.visible = visible
		_lab.set_process(visible)


func _on_edited() -> void:
	if _dock:
		_dock.show_resource(EditorInterface.get_inspector().get_edited_object())
