# SPDX-License-Identifier: Apache-2.0
# Converts every Synth1 patch in a prep-tool library and renders it in the reference's layout:
#
#   godot --headless --path . --script res://tools/patch_convert/synth1_batch.gd -- [library folder | list.txt]
#
# A .txt argument lists patch folders, one per line (tools/patch_convert/synth1_chunks.py).
#
# It converts the values Synth1 held after loading the file (content.render_synth1.values:
# Synth1 converts an old version's values), and beside each patch's instrument.json it writes
# gak_patch.tres, gak_render_v100.wav (16-bit stereo; each note rendered alone for its
# slot, as render_synth1.py renders Synth1) and gak_convert.json (converter version,
# caveats, the file's scale). tools/patch_convert/check_synth1.py then compares the two
# renders and writes gak_report.json and gak_synth1_summary.json.
extends SceneTree

const LIB := "D:/12_library/gak/processed_synth1"
const Synth1 := preload("res://tools/patch_convert/synth1.gd")

var _ran := false


func _process(_d: float) -> bool:
	if not _ran:
		_ran = true
		_run()
	return false


func _sidecars(dir: String, out: Array) -> void:
	if FileAccess.file_exists(dir.path_join("instrument.json")):
		out.append(dir)
	for d in DirAccess.get_directories_at(dir):
		_sidecars(dir.path_join(d), out)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var lib: String = args[0] if args.size() > 0 else LIB
	var folders := []
	if lib.ends_with(".txt"):
		for line in FileAccess.get_file_as_string(lib).split("\n"):
			if not line.strip_edges().is_empty():
				folders.append(line.strip_edges().replace("\\", "/").trim_suffix("/instrument.json"))
	else:
		_sidecars(lib, folders)
	folders.sort()
	var done := 0
	var t0 := Time.get_ticks_msec()
	for folder: String in folders:
		var sc: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("instrument.json")))
		if not (sc is Dictionary):
			continue
		var content: Dictionary = sc.get("content", {})
		if not content.has("synth1") or not content.has("render_synth1"):
			continue
		# The values Synth1 held once it converted the file from its version (render_synth1.py
		# records them); the file's own values otherwise.
		var params: Dictionary = content.render_synth1.get("values", content.synth1.params)
		params.name = content.synth1.get("name", "")
		var patch: AKPatch = Synth1.convert(params)
		var err := ResourceSaver.save(patch, folder.path_join("gak_patch.tres"))
		var scale := _render(patch, content.render_synth1, folder.path_join("gak_render_v100.wav"))
		var info := {converter = "patch_convert/synth1.gd %d" % Synth1.VERSION, engine = AKSynthCore.VERSION,
			patch = "gak_patch.tres" if err == OK else "save failed (%d)" % err, render = "gak_render_v100.wav",
			scale = scale, caveats = Synth1.caveats(params)}
		var f := FileAccess.open(folder.path_join("gak_convert.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify(info, "  ") + "\n")
		f.close()
		done += 1
		if done % 100 == 0:
			print("%d converted" % done)
	print("%d patches converted and rendered in %.0f s" % [done, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(0)


## Renders each note of the layout alone, for its slot, and joins them; writes a 16-bit
## stereo WAV, scaled down to fit when louder than full scale. Returns that scale.
func _render(patch: AKPatch, st: Dictionary, path: String) -> float:
	var sr := int(st.sample_rate)
	var c := patch.compile()
	var vel := int((st.velocities as Array)[0])
	var hold := roundi(float(st.hold_s) * sr)
	var per := roundi((float(st.hold_s) + float(st.release_s) + float(st.gap_s)) * sr)
	var notes: Array = st.notes
	var l := PackedFloat32Array()
	var r := PackedFloat32Array()
	for key: Variant in notes:
		var b := AKSynth.render_events(c, [[0, AKSynth.E_ON, float(key), vel / 127.0], [hold, AKSynth.E_OFF, float(key), 0.0]], per, sr)
		var bl := b.l.duplicate()
		var br := b.r.duplicate() if b.r.size() == b.l.size() else b.l.duplicate()
		bl.resize(per)
		br.resize(per)
		l.append_array(bl)
		r.append_array(br)
	var peak := 0.0
	for i in l.size():
		peak = maxf(peak, maxf(absf(l[i]), absf(r[i])))
	var scale := 1.0 if peak <= 0.999 else 0.999 / peak
	var data := PackedByteArray()
	data.resize(l.size() * 4)
	for i in l.size():
		data.encode_s16(i * 4, clampi(roundi(l[i] * scale * 32767.0), -32768, 32767))
		data.encode_s16(i * 4 + 2, clampi(roundi(r[i] * scale * 32767.0), -32768, 32767))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + data.size())
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)
	f.store_16(2)
	f.store_32(sr)
	f.store_32(sr * 4)
	f.store_16(4)
	f.store_16(16)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(data.size())
	f.store_buffer(data)
	f.close()
	return scale
