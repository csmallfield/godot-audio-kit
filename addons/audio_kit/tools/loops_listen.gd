# SPDX-License-Identifier: Apache-2.0
# Renders the phase 6 material for listening: the same two-bar beat on each
# default kit, a sample loop (a library bass and keys played as loops over
# it) and every library sound, to WAVs under out/loops/ (git-ignored), with
# a line of measurements each.
#
#   godot --headless --path . -s res://addons/audio_kit/tools/loops_listen.gd -- [--sounds] [--out out/loops]
extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := "res://out/loops/"
	var sounds := args.has("--sounds")
	for i in args.size():
		if args[i] == "--out" and i + 1 < args.size():
			out_dir = "res://" + args[i + 1].trim_prefix("res://").trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(out_dir)
	AK.disk_cache = false
	for kn in AKLibrary.KIT_NAMES:
		var song := _song(AKLibrary.kit(kn), kn == "boom")
		var buf: AKBuffer = song.render().mix
		_save(buf, out_dir + "beat_%s.wav" % kn.replace("-", ""))
	if sounds:
		for s: Dictionary in AKLibrary.sounds():
			_save(AK.render(load(AKLibrary.path_of(s.folder, s.name))), out_dir + "library/%s/%s.wav" % [s.folder, s.name])
	quit()


## Two bars at 100 bpm: kick, snare, hats (open hats choked by closed ones),
## and on the boom kit a bass and keys loop from the library.
func _song(kit: AKKit, melodic: bool) -> AKSong:
	var beat := AKLoop.new()
	beat.kind = "percussive"
	beat.instrument = kit
	beat.bars = 2
	beat.swing = 0.56
	var k := kit.find_piece("kick")
	var s := kit.find_piece("snare")
	var ch := kit.find_piece("closed_hat")
	var oh := kit.find_piece("open_hat")
	for t in [0, 168, 288, 384, 552, 648]:
		beat.add_note(t, 24, k, 1.0)
	for t in [96, 288, 480, 672]:
		beat.add_note(t, 24, s, 0.9)
	for i in 16:
		beat.add_note(i * 48, 24, oh if i % 8 == 7 else ch, 0.8 if i % 2 == 0 else 0.55)
	beat.add_note(744, 24, kit.find_piece("crash"), 0.7)
	var song := AKSong.new()
	song.tempo = AKTempoMap.new()
	song.tempo.bpm = 100.0
	var patterns := [beat.to_pattern(16.0)]
	if melodic:
		var bass := AKLoop.new()
		bass.kind = "sample"
		bass.instrument = AKLibrary.sample_for(AKLibrary.path_of("bass", "bass_808"), "gate")
		bass.bars = 2
		bass.resource_name = "bass"
		for n in [[0, 144, 33], [168, 72, 33], [288, 96, 36], [384, 144, 31], [552, 72, 31], [672, 96, 28]]:
			bass.add_note(n[0], n[1], n[2], 0.9)
		var keys := AKLoop.new()
		keys.kind = "sample"
		keys.instrument = AKLibrary.sample_for(AKLibrary.path_of("keys", "epiano"))
		keys.bars = 2
		keys.resource_name = "keys"
		for c in [[0, [57, 60, 64]], [384, [55, 59, 62]]]:
			for n in c[1]:
				keys.add_note(c[0], 288, n, 0.6)
		patterns.append_array([bass.to_pattern(16.0), keys.to_pattern(16.0)])
		song.mix = {"keys": {gain_db = -8.0, send = 0.25}, "bass": {gain_db = -4.0}}
	song.sections = [{name = "a", bars = 4, patterns = patterns}]
	return song


func _save(buf: AKBuffer, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	buf.save_wav(path)
	var f := AKSoundFeatures.of(buf)
	print("%-48s %5.2f s  peak %5.1f dBFS  %5.1f LUFS" % [path.trim_prefix("res://"), buf.seconds(),
		20.0 * log(maxf(1e-9, buf.peak())) / log(10.0), float(f.get("lufs", 0.0))])
