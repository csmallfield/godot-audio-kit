extends SceneTree
# godot --headless --path <repo> -s render_batch.gd -- notes.json patches.json out_prefix length_s
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	for f in a.slice(0, 2):
		if f.ends_with(".json") and JSON.parse_string(FileAccess.get_file_as_string(f)) == null:
			printerr("can't read ", f)
			quit(1)
			return
	var notes: Array = JSON.parse_string(FileAccess.get_file_as_string(a[0]))
	var specs: Array = JSON.parse_string(FileAccess.get_file_as_string(a[1]))
	for i in specs.size():
		var p := AKPatch.new()
		var spec: Dictionary = specs[i]
		for k: String in spec:
			var v: Variant = spec[k]
			if k in ["oscillators", "mods", "effects"]:
				var arr: Array[Dictionary] = []
				for d: Dictionary in v:
					arr.append(d)
				p.set(k, arr)
			else:
				p.set(k, v)
		AKSynth.render_notes(p, notes, float(a[3]), 44100).save_wav("%s%02d.wav" % [a[2], i])
	print("rendered ", specs.size())
	quit()
