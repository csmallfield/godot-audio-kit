# SPDX-License-Identifier: Apache-2.0
## Writes docs/voices.md from the voices' own schemas, so the reference can't
## drift from the code:
##   godot --headless --path . -s res://addons/audio_kit/tools/voice_docs.gd
extends SceneTree


func _init() -> void:
	var md := PackedStringArray(["# Voices", "",
		"Generated from each voice's `schema()` by `addons/audio_kit/tools/voice_docs.gd`. Do not edit by hand.", ""])
	for name in AK.voice_names():
		var v := AK.voice(StringName(name))
		md.append("## `%s` (v%d)" % [name, v.version()])
		md.append("")
		md.append(v.doc())
		md.append("")
		md.append("| Parameter | Default | Range | What it does |")
		md.append("| --- | --- | --- | --- |")
		var s := v.schema()
		for k in s:
			var e: Dictionary = s[k]
			var rng := ""
			if e.get("min") != null:
				rng = "%s – %s" % [str(e.min), str(e.max)]
			md.append("| `%s` | %s | %s | %s |" % [k, str(e.default), rng, e.get("doc", "")])
		md.append("")
	var path := ProjectSettings.globalize_path("res://docs/voices.md")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(md))
	f.close()
	print("wrote ", path)
	quit()
