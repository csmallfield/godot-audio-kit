# SPDX-License-Identifier: Apache-2.0
@tool
extends EditorPlugin
## Adds the Audio Kit dock, which plays whatever recipe, song, pattern or cue
## map is in the inspector.

var _dock: AKAuditionDock


func _enter_tree() -> void:
	_dock = AKAuditionDock.new()
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, _dock)   # under the inspector: edit and listen side by side
	EditorInterface.get_inspector().edited_object_changed.connect(_on_edited)


func _exit_tree() -> void:
	var insp := EditorInterface.get_inspector()
	if insp.edited_object_changed.is_connected(_on_edited):
		insp.edited_object_changed.disconnect(_on_edited)
	if _dock:
		_dock.stop()
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null


func _on_edited() -> void:
	if _dock:
		_dock.show_resource(EditorInterface.get_inspector().get_edited_object())
