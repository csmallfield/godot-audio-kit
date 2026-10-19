# SPDX-License-Identifier: Apache-2.0
## Headless review render: a cue sheet (or one recipe) to WAVs plus a render
## summary, then the analysis report.
##
##   godot --headless --path . -s res://addons/audio_kit/tools/review.gd -- \
##       --cues demo/cues/race_ident.json --map res://demo/recipes/race_ident_map.tres \
##       --out out/review/race_ident
##
##   godot --headless --path . -s res://addons/audio_kit/tools/review.gd -- \
##       --recipe res://demo/recipes/go.tres --intensity 0.8 --out out/review/go
##
##   --song res://music/song.tres   alone renders the song; with --cues it is
##                                  mixed under the effects.
##
## Writes mix.wav, stems/<cue>.wav (cue sheets) and render.json to --out, then
## runs tools/analyze/analyze.py on it (skip with --no-analyze), which adds
## report.md, report.json, spectrogram.png and cues.png.
extends SceneTree


func _init() -> void:
	var args := _parse(OS.get_cmdline_user_args())
	if not args.has("out") or not (args.has("cues") or args.has("recipe") or args.has("song")):
		printerr("usage: -- (--cues sheet.json --map map.tres [--song s.tres] | --recipe r.tres [--intensity x] | --song s.tres) --out dir [--fps 30] [--no-analyze]")
		quit(2)
		return
	var out := _abs(String(args.out))
	DirAccess.make_dir_recursive_absolute(out)
	var t0 := Time.get_ticks_msec()
	var summary := {sample_rate = AK.sample_rate}
	var song: AKSong = load(String(args.song)) if args.has("song") else null
	if song and not args.has("cues"):
		var rs := song.render(true)
		rs.mix.save_wav(out.path_join("mix.wav"))
		DirAccess.make_dir_recursive_absolute(out.path_join("stems"))
		for name in rs.stems:
			rs.stems[name].save_wav(out.path_join("stems").path_join(String(name) + ".wav"))
		var marks := []
		for L in song.layout():
			marks.append({name = "section." + String(L.name), time = L.start_s, sample = roundi(L.start_s * AK.sample_rate),
				cue_sample = roundi(L.start_s * AK.sample_rate), intensity = 1.0, lead_in = 0, offset_s = 0.0,
				frames = roundi((L.end_s - L.start_s) * AK.sample_rate), stem = "mix.wav"})
		summary.merge({mode = "song", song = String(args.song), duration = rs.mix.seconds(), events = rs.events.size(), cues = marks})
	elif args.has("recipe"):
		var recipe: AKRecipe = load(String(args.recipe))
		var intensity := float(args.get("intensity", "1.0"))
		var buf := AK.render(recipe, intensity)
		buf.save_wav(out.path_join("mix.wav"))
		summary.merge({mode = "recipe", recipe = String(args.recipe), intensity = intensity, duration = buf.seconds(),
			cues = [{name = String(args.recipe).get_file().get_basename(), time = 0.0, sample = 0, cue_sample = 0,
				intensity = intensity, frames = buf.frames(), lead_in = maxi(0, buf.first_above(1e-4)), recipe = String(args.recipe), offset_s = recipe.offset_s,
				stem = "mix.wav"}]})
	else:
		var sheet := AK.load_cue_sheet(_abs(String(args.cues)) if not String(args.cues).begins_with("res://") else String(args.cues))
		var fps := float(args.get("fps", str(sheet.get("fps", 30.0))))
		var duration := float(sheet.get("duration", 0.0)) / fps
		var map: AKCueMap = load(String(args.map))
		var r := AK.render_cues(sheet.get("cues", []), map, fps, duration, true, song)
		r.mix.save_wav(out.path_join("mix.wav"))
		DirAccess.make_dir_recursive_absolute(out.path_join("stems"))
		for name in r.stems:
			r.stems[name].save_wav(out.path_join("stems").path_join(String(name) + ".wav"))
		for c in r.cues:
			if not c.get("missing", false):
				c["stem"] = "stems/" + String(c.name) + ".wav"
		summary.merge({mode = "cues", cue_sheet = String(args.cues), map = String(args.map), fps = fps,
			duration = duration, rendered_s = r.mix.seconds(), cues = r.cues})
	summary["render_ms"] = Time.get_ticks_msec() - t0
	var f := FileAccess.open(out.path_join("render.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(summary, "\t"))
	f.close()
	print("rendered %s in %d ms" % [out, summary.render_ms])
	var code := 0
	if not args.has("no-analyze"):
		var analyzer := ProjectSettings.globalize_path("res://tools/analyze/analyze.py")
		var lines := []
		code = OS.execute("python3", [analyzer, out], lines, true)
		for l in lines:
			print(l)
	quit(code)


func _parse(argv: PackedStringArray) -> Dictionary:
	var d := {}
	var i := 0
	while i < argv.size():
		var a := argv[i]
		if a.begins_with("--"):
			var k := a.substr(2)
			if i + 1 < argv.size() and not argv[i + 1].begins_with("--"):
				d[k] = argv[i + 1]
				i += 1
			else:
				d[k] = true
		i += 1
	return d


func _abs(p: String) -> String:
	if p.begins_with("res://") or p.begins_with("user://"):
		return ProjectSettings.globalize_path(p)
	if p.is_absolute_path():
		return p
	return ProjectSettings.globalize_path("res://").path_join(p)
