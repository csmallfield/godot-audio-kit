## The editor's UI scale, for sizes written in layout units.
##
## Godot scales its own controls by the editor scale (2 on a Retina Mac, 1 on
## a plain display, whatever the person set in the editor settings), but a
## `custom_minimum_size` or a custom-drawn control is in raw pixels. Multiply
## layout-unit sizes by [method factor] so the lab keeps up with the rest of
## the editor on every platform; it's 1 outside the editor.
class_name AKUiScale


static func factor() -> float:
	return EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0


static func px(x: float, y: float) -> Vector2:
	return Vector2(x, y) * factor()
