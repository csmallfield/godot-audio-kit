extends SceneTree
# godot --headless --path <repo> -s render_patch.gd -- notes.json patch.json out.wav
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var notes: Array = JSON.parse_string(FileAccess.get_file_as_string(a[0]))
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(a[1]))
	var p := AKPatch.new()
	for k: String in spec:
		var v: Variant = spec[k]
		if k in ["oscillators", "mods", "effects"]:
			var arr: Array[Dictionary] = []
			for d: Dictionary in v:
				arr.append(d)
			p.set(k, arr)
		else:
			p.set(k, v)
	var buf := AKSynth.render_notes(p, notes, 96.386, 44100)
	buf.save_wav(a[2])
	print("rendered ", a[2])
	quit()
