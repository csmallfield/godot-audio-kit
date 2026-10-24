# SPDX-License-Identifier: Apache-2.0
# A headless "listening" pass over the SFX generator: render a few seeds of
# every category to WAVs and print a table of what they measure like, so the
# categories can be told apart without ears.
#
#   godot --headless --path . -s res://addons/audio_kit/tools/sfx_listen.gd -- [--seeds 4] [--out out/sfx_lab]
extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var seeds := 4
	var out_dir := "res://out/sfx_lab/"
	for i in args.size():
		if args[i] == "--seeds" and i + 1 < args.size():
			seeds = args[i + 1].to_int()
		elif args[i] == "--out" and i + 1 < args.size():
			out_dir = args[i + 1].trim_suffix("/") + "/"
			if not out_dir.begins_with("res://") and not out_dir.is_absolute_path():
				out_dir = "res://" + out_dir
	AK.disk_cache = false
	print("| category | seed | length s | peak dB | LUFS | attack ms | decay ms | onsets | centroid Hz | tonality | pitch Hz start -> end |")
	print("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
	var cats: Array = AKSfxGen.CATEGORIES.duplicate()
	cats.append(&"random")
	for cat in cats:
		for s in range(1, seeds + 1):
			var r := AKSfxGen.generate(cat, s)
			var buf := AK.render(r)
			AK.save_wav(buf, out_dir + "%s_%d.wav" % [cat, s])
			var f := AKSoundFeatures.of(buf)
			print("| %s | %d | %.3f | %.1f | %.1f | %.0f | %.0f | %d | %.0f | %.2f | %.0f -> %.0f |" % [cat, s, f.length_s, f.peak_db, f.lufs,
				f.attack_s * 1000.0, f.decay_s * 1000.0, f.onsets, f.centroid_hz, f.tonality, f.pitch_start_hz, f.pitch_end_hz])
	print("WAVs in %s" % ProjectSettings.globalize_path(out_dir))
	quit()
