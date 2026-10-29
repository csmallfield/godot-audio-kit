# SPDX-License-Identifier: Apache-2.0
## Imports .mid / .midi files as AKSongs (through AKMidi and the starter
## bank), so a MIDI file can be dropped into the project and played, baked
## or opened in the Sound Lab like any song. "Save song" in the lab (or
## ResourceSaver) turns one into an editable .tres.
@tool
extends EditorImportPlugin


func _get_importer_name() -> String:
	return "audio_kit.midi_song"


func _get_visible_name() -> String:
	return "AKSong (Audio Kit)"


func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["mid", "midi"])


func _get_save_extension() -> String:
	return "res"


func _get_resource_type() -> String:
	return "Resource"


func _get_priority() -> float:
	return 1.0


func _get_import_order() -> int:
	return 0


func _get_preset_count() -> int:
	return 1


func _get_preset_name(_i: int) -> String:
	return "Default"


func _get_import_options(_path: String, _preset: int) -> Array[Dictionary]:
	return [
		{name = "bank", default_value = "", property_hint = PROPERTY_HINT_FILE, hint_string = "*.tres"},
		{name = "quantize", default_value = 0, property_hint = PROPERTY_HINT_ENUM, hint_string = "Off:0,Quarter:1,Eighth:2,Sixteenth:4,Thirty-second:8"},
		{name = "velocity_curve", default_value = 1.0, property_hint = PROPERTY_HINT_RANGE, hint_string = "0.2,3.0,0.05"},
		{name = "sections", default_value = true},
		{name = "reverb_send", default_value = 0.12, property_hint = PROPERTY_HINT_RANGE, hint_string = "0,1,0.01"},
	]


func _get_option_visibility(_path: String, _option: StringName, _options: Dictionary) -> bool:
	return true


func _import(source_file: String, save_path: String, options: Dictionary, _platform_variants: Array[String], _gen_files: Array[String]) -> Error:
	var song := AKMidi.import_file(source_file, options)
	if song == null:
		return ERR_PARSE_ERROR
	return ResourceSaver.save(song, "%s.%s" % [save_path, _get_save_extension()])
