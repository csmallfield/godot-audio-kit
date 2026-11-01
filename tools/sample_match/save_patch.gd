extends SceneTree
func _init() -> void:
	var a := OS.get_cmdline_user_args()
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
	p.category = "bass"
	print(ResourceSaver.save(p, a[1]))
	quit()
