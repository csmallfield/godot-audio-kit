# SPDX-License-Identifier: Apache-2.0
@tool
extends AKVoice
## A line of pseudo-speech as a recipe voice, so a recipe layer (and so a cue
## map, a recipe stream, a bake cached by its text and voice) can speak:
##   {voice = &"speech", params = {text = "Hey! Where did you come from?", voice = "res://addons/audio_kit/speech/voices/blip.tres"}}


func version() -> int:
	return 1000 * AKSpeech.VERSION + AKSynthCore.VERSION


func doc() -> String:
	return "Speaks a line of text as pseudo-speech (gibberish whose rhythm, stress and melody follow the text) through an AKSpeechVoice's patch."


func schema() -> Dictionary:
	return {
		text = param("Hey!", null, null, "The line to say"),
		voice = param(AKSpeech.KIT_VOICE_DIR + "blip.tres", null, null, "The AKSpeechVoice, or its res:// path"),
	}


func render(p: Dictionary, sr: int, _rng: RandomNumberGenerator) -> PackedFloat32Array:
	var v := AKSpeech.resolve_voice(p.voice)
	if v == null:
		return PackedFloat32Array()
	var buf := AKSpeech.render(AKSpeechLine.make(String(p.text), v), sr)
	var out := buf.l.duplicate()
	for i in out.size():
		out[i] = 0.5 * (buf.l[i] + buf.r[i])
	return out


## The voice's content (and its patch's), the dictionary and the project's
## lexicon, so editing any of them re-bakes.
func key_extra(params: Dictionary) -> Variant:
	var v: Variant = params.get("voice", "")
	if (v is String or v is StringName) and String(v) != "" and ResourceLoader.exists(String(v)):
		var r := AKSpeech.resolve_voice(v)
		return [r.describe() if r else null, AKSpeech.data_key()]
	return AKSpeech.data_key()
