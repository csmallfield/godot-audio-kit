# SPDX-License-Identifier: Apache-2.0
# Writes the built-in pseudo-speech voices (AKSpeech.preset_voice) to
# addons/audio_kit/speech/voices/ as .tres text. Run tools/make_patches.gd
# first: a voice refers to its patch's file.
#   godot --headless --path . -s res://addons/audio_kit/tools/make_speech_voices.gd
extends SceneTree


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(AKSpeech.KIT_VOICE_DIR)
	for n in AKSpeech.preset_names():
		var v := AKSpeech.preset_voice(StringName(n))
		var path := AKSpeech.KIT_VOICE_DIR + n + ".tres"
		var err := ResourceSaver.save(v, path)
		print("%s  %s" % ["ok  " if err == OK else "FAIL", path])
	quit()
