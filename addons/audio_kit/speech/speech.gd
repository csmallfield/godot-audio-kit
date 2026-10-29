# SPDX-License-Identifier: Apache-2.0
@tool
## Pseudo-speech: a written line becomes a gibberish voice whose rhythm,
## stress and melody follow the text, timed for subtitles.
##
##   var voice: AKSpeechVoice = load("res://addons/audio_kit/speech/voices/blip.tres")
##   var line := AKSpeechLine.make("Hey! Where did you come from?", voice)
##   var buf := AKSpeech.render(line)          # AKBuffer (compiles the line first)
##   $Player.stream = buf.to_stream()
##
##   # In a recipe (so in cue maps, recipe streams and bakes, cached by text and voice):
##   var r := AKRecipe.make(&"speech", {text = "Hey!", voice = "res://addons/audio_kit/speech/voices/blip.tres"})
##
## Three stages: AKSpeechText (words, syllables, stress), AKSpeechProsody
## (timed syllables and curves), and the voice's patch (AKSynth), which hears
## the curves as notes, velocity, pitch bend, mod wheel and aftertouch (see
## AKSpeechVoice). Every stage is deterministic.
class_name AKSpeech
extends RefCounted

## Bump when a change alters what a line compiles to (it changes bake keys).
const VERSION := 1
## The kit's voices, and the project's.
const KIT_VOICE_DIR := "res://addons/audio_kit/speech/voices/"
const USER_VOICE_DIR := "res://audio/speech/voices/"
## Controller updates: one every 1/CONTROL_RATE s, when the value moved.
const CONTROL_RATE := 200
const CONTROL_EPS := 0.004


## Fill `line`'s compiled fields from its text and voice.
static func compile_into(line: AKSpeechLine) -> void:
	var text := line.source_text.strip_edges()
	line.display_text = text
	var a := AKSpeechText.analyse(text)
	line.words = a.words
	line.clauses = a.clauses
	if line.voice == null or a.words.is_empty():
		line.events = []
		line.curves = {}
		line.duration = 0.0
		return
	var p := AKSpeechProsody.build(a, line.voice)
	line.events = p.events
	line.curves = p.curves
	line.curve_rate = p.curve_rate
	line.duration = p.duration


## The notes and controller moves the voice's patch plays, in the form
## AKSynth.render_notes takes: a note per syllable at its accent's pitch and
## intensity, then bend (the rest of the pitch curve, while the note sounds),
## mod wheel (formant) and aftertouch (brightness).
static func notes_for(line: AKSpeechLine) -> Array:
	line.compile()
	var out := []
	var v := line.voice
	if v == null or v.patch == null or line.events.is_empty():
		return out
	var bend_range := maxf(0.01, v.patch.bend_range)
	var gates := []
	for e in line.events:
		var on := float(e.t_start)
		var length := maxf(0.02, (float(e.t_end) - on) * v.gate)
		gates.append(Vector2(on, on + length))
		# The bend for the start of this note goes in before the note.
		var b0 := clampf((line.curve_at("pitch", on) - float(e.pitch)) / bend_range, -1.0, 1.0)
		out.append({time_s = on, bend = b0})
		out.append({time_s = on, note = v.base_note + float(e.pitch), velocity = float(e.velocity), length_s = length})
	var last := {bend = INF, mod_wheel = INF, aftertouch = INF}
	var ev := 0
	var steps := ceili(line.duration * CONTROL_RATE) + 1
	for i in steps:
		var t := float(i) / CONTROL_RATE
		while ev + 1 < line.events.size() and t >= float(line.events[ev + 1].t_start):
			ev += 1
			last.bend = INF
		var e: Dictionary = line.events[ev]
		var g: Vector2 = gates[ev]
		var moves := {mod_wheel = clampf(line.curve_at("formant", t), 0.0, 1.0),
			aftertouch = clampf(line.curve_at("brightness", t), 0.0, 1.0)}
		if t > g.x and t <= g.y:
			moves.bend = clampf((line.curve_at("pitch", t) - float(e.pitch)) / bend_range, -1.0, 1.0)
		for k in moves:
			if absf(float(moves[k]) - float(last[k])) > CONTROL_EPS:
				var d := {"time_s": t}
				d[k] = moves[k]
				out.append(d)
				last[k] = moves[k]
	return out


## The line, spoken: a stereo AKBuffer at `sample_rate` (0 = the kit's),
## the voice's gain applied. Empty for an empty line or a voice without a patch.
static func render(line: AKSpeechLine, sample_rate := 0) -> AKBuffer:
	var sr := sample_rate if sample_rate > 0 else AK.sample_rate
	var notes := notes_for(line)
	if notes.is_empty():
		return AKBuffer.new(0, sr)
	var buf := AKSynth.render_notes(line.voice.patch, notes, 0.0, sr)
	if not is_zero_approx(line.voice.gain_db):
		buf.apply_gain(db_to_linear(line.voice.gain_db))
	return buf


## Voices to pick from: the kit's, then the project's. [{name, path, source}].
static func voices() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for pair in [[KIT_VOICE_DIR, "kit"], [USER_VOICE_DIR, "yours"]]:
		var dir: String = pair[0]
		if not DirAccess.dir_exists_absolute(dir):
			continue
		var files := Array(DirAccess.get_files_at(dir))
		files.sort()
		for f: String in files:
			var fname := f.trim_suffix(".remap")
			if fname.ends_with(".tres") or fname.ends_with(".res"):
				out.append({name = fname.get_basename(), path = dir + fname, source = pair[1]})
	return out


## The kit's voice presets, built in code (the .tres files in KIT_VOICE_DIR
## are these, saved by tools/make_speech_voices.gd).
static func preset_names() -> PackedStringArray:
	return PackedStringArray(["blip"])


static func preset_voice(preset: StringName) -> AKSpeechVoice:
	var v := AKSpeechVoice.new()
	match preset:
		&"blip":
			# Short square blips, pitch only: Undertale-style UI talk.
			v.salt = "blip"
			v.patch = AKPatchLib.load_preset(&"speech_blip")
			v.base_note = 67.0
			v.range_semitones = 6.0
			v.syllable_s = 0.11
			v.gate = 0.6
			v.jitter = 0.15
			v.seed_pitch_semitones = 0.8
			v.seed_time = 0.12
		_:
			push_error("AKSpeech: no voice preset '%s'" % preset)
			return null
	v.resource_name = String(preset)
	return v


## A voice from a resource or a res:// path; null (with an error) otherwise.
static func resolve_voice(v: Variant) -> AKSpeechVoice:
	if v is AKSpeechVoice:
		return v
	if (v is String or v is StringName) and String(v) != "" and ResourceLoader.exists(String(v)):
		var r: Resource = load(String(v))
		if r is AKSpeechVoice:
			return r
	push_error("AKSpeech: '%s' is not an AKSpeechVoice" % [v])
	return null


## A short readable view of the analysis: syllables split with "·", stressed
## ones in capitals, function words in lower case, clauses with their marks.
## "HEY! | WHERE did you COME from? | ..."
static func describe_analysis(line: AKSpeechLine) -> String:
	line.compile()
	var parts := PackedStringArray()
	for cl in line.clauses:
		var ws := PackedStringArray()
		for wi in range(int(cl.first), int(cl.last) + 1):
			var w: Dictionary = line.words[wi]
			var syl := PackedStringArray()
			for s in w.syllables:
				syl.append(String(s.letters).to_upper() if int(s.stress) == 1 else String(s.letters))
			ws.append("·".join(syl))
		parts.append(" ".join(ws) + String(cl.end))
	return " | ".join(parts)
