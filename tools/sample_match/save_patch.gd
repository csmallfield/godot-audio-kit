extends SceneTree
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	for f in a.slice(0, 2):
		if f.ends_with(".json") and JSON.parse_string(FileAccess.get_file_as_string(f)) == null:
			printerr("can't read ", f)
			quit(1)
			return
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(a[0]))
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
	p.resource_name = a[2]
	p.category = a[3] if a.size() > 3 else "other"
	print(ResourceSaver.save(p, a[1]))
	quit()
