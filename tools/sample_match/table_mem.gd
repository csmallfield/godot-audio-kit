extends SceneTree
# godot --headless --path <repo> -s table_mem.gd -- patch.json ...: memory the patch's wavetables take
func _init() -> void:
	for f in OS.get_cmdline_user_args():
		var spec: Variant = JSON.parse_string(FileAccess.get_file_as_string(f))
		if spec == null:
			printerr("can't read ", f)
			continue
		var t0 := Time.get_ticks_msec()
		var n := 0
		for o: Dictionary in spec.oscillators:
			if o.get("shape") == "table":
				n += (AKWavetables.build(o.table).data as PackedFloat32Array).size() * 4
		print("%s %.1f MB, built in %.1f s" % [f.get_file(), n / 1048576.0, (Time.get_ticks_msec() - t0) / 1000.0])
	quit()
