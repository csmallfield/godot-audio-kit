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
const VERSION := 3
## The kit's voices, and the project's.
const KIT_VOICE_DIR := "res://addons/audio_kit/speech/voices/"
const USER_VOICE_DIR := "res://audio/speech/voices/"
## Scratch King's records: sung vowels ee, eh, ah, oh, oo (the vowel voice).
const VOWEL_DIR := "res://addons/audio_kit/speech/vowels/"
## The project's own pronunciations (an AKSpeechLexicon), checked before the dictionary.
const LEXICON_PATH := "res://audio/speech/lexicon.tres"
## Controller updates: one every 1/CONTROL_RATE s, when the value moved.
const CONTROL_RATE := 200
const CONTROL_EPS := 0.004


## Fill `line`'s compiled fields from its text and voice.
static func compile_into(line: AKSpeechLine) -> void:
	var text := line.source_text.strip_edges()
	var m := AKSpeechMarkup.parse(text)
	line.display_text = m.display
	var a := AKSpeechText.analyse(m.display, project_lexicon())
	AKSpeechMarkup.apply(a, m)
	line.warnings = PackedStringArray(m.warnings)
	for tag in AKSpeechMarkup.unknown_tags(m, line.voice):
		line.warnings.append("unknown voice state {%s}: it plays as {normal}" % tag)
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
##
## With `only`, the notes are those of the syllables that patch plays (a
## voice state such as "shout" can bring its own patch); the controller
## moves are always all of them.
static func notes_for(line: AKSpeechLine, only: AKPatch = null) -> Array:
	line.compile()
	var out := []
	var v := line.voice
	var main := only if only else v.patch if v else null
	if v == null or main == null or line.events.is_empty():
		return out
	var bend_range := maxf(0.01, main.bend_range)
	var gates := []
	for e in line.events:
		# The vowel's note starts after the onset's lead (a hiss runs first) and
		# ends where the gate says, so onsets shift the vowel, not the rhythm.
		var start := float(e.t_start)
		var span := float(e.t_end) - start
		var on := start + minf(v.lead_for(int(e.onset_class)), 0.5 * span)
		var length := maxf(0.02, start + span * v.gate - on)
		gates.append(Vector2(on, on + length))
		# The bend for the start of this note goes in before the note.
		var b0 := clampf((line.curve_at("pitch", on) - float(e.pitch)) / bend_range, -1.0, 1.0)
		if only and patch_of(v, e) != only:
			continue
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
## the voice's gain applied. Empty for an empty line or a voice without a sound
## source (a patch, or scratch samples).
static func render(line: AKSpeechLine, sample_rate := 0) -> AKBuffer:
	var sr := sample_rate if sample_rate > 0 else AK.sample_rate
	line.compile()
	if line.voice == null or line.events.is_empty():
		return AKBuffer.new(0, sr)
	var buf: AKBuffer
	if line.voice.source == "scratch":
		buf = AKSpeechScratch.render(line, sr)
	else:
		var patches := patches_for(line)
		if patches.is_empty():
			return AKBuffer.new(0, sr)
		buf = AKSynth.render_notes(patches[0], notes_for(line, patches[0]), 0.0, sr)
		for k in range(1, patches.size()):
			var other := AKSynth.render_notes(patches[k], notes_for(line, patches[k]), 0.0, sr)
			if other.frames() > buf.frames():
				buf.resize(other.frames())
			other.mix_into(buf, 0, 1.0)
	if buf.frames() == 0:
		return buf
	_mix_onsets(line, buf, sr)
	if not is_zero_approx(line.voice.gain_db):
		buf.apply_gain(db_to_linear(line.voice.gain_db))
	# Loud consonants (a voice's onset_gain_db turned up) would clip: limit
	# what goes over, and leave a line that doesn't alone.
	if buf.peak() > db_to_linear(CEILING_DB):
		AKDynamics.limit(buf, CEILING_DB)
	return buf


## Just the onsets of a line, mixed (before the voice's gain): what a live
## speaker plays beside the synth.
static func render_onsets(line: AKSpeechLine, sample_rate := 0) -> AKBuffer:
	var sr := sample_rate if sample_rate > 0 else AK.sample_rate
	var buf := AKBuffer.new(0, sr)
	_mix_onsets(line, buf, sr)
	return buf


static func _mix_onsets(line: AKSpeechLine, buf: AKBuffer, sr: int) -> void:
	for o in onsets_for(line):
		var hit := AK.render(o.recipe, 1.0, {}, int(o.variant))
		if hit.sample_rate != sr or hit.frames() == 0:
			continue
		var at := roundi(float(o.time_s) * sr)
		if at + hit.frames() > buf.frames():
			buf.resize(at + hit.frames())
		hit.mix_into(buf, at, float(o.gain))


## The onset sounds of a line: [{time_s, recipe, variant, gain, kind}] for
## every syllable whose first consonant the voice has a sound for (plosive,
## fricative or an h's breath), and, with `coda_fricatives`, a quieter hiss where a syllable
## ends in a fricative. The variant comes from the syllable's seed, so a word
## keeps its own consonants; the level follows the syllable's intensity.
static func onsets_for(line: AKSpeechLine) -> Array[Dictionary]:
	line.compile()
	var out: Array[Dictionary] = []
	var v := line.voice
	if v == null or (v.plosive == null and v.fricative == null and v.breath == null):
		return out
	var base := db_to_linear(v.onset_gain_db)
	for e in line.events:
		var start := float(e.t_start)
		var span := float(e.t_end) - start
		var vel := float(e.velocity)
		var variant := 1 + int(e.seed) % 997
		match int(e.onset_class):
			AKSpeechText.PLOSIVE:
				if v.plosive:
					out.append({time_s = start, recipe = v.plosive, variant = variant, gain = base * vel, kind = "plosive"})
			AKSpeechText.FRICATIVE:
				if v.fricative:
					out.append({time_s = start, recipe = v.fricative, variant = variant, gain = base * vel, kind = "fricative"})
			AKSpeechText.BREATH:
				if v.breath:
					out.append({time_s = start, recipe = v.breath, variant = variant, gain = base * vel, kind = "breath"})
		if v.coda_fricatives and v.fricative and int(e.coda_class) == AKSpeechText.FRICATIVE:
			var end := start + span * v.gate
			out.append({time_s = maxf(start, end - 0.5 * v.fricative_lead_s), recipe = v.fricative, variant = variant + 1,
				gain = 0.6 * base * vel, kind = "coda"})
	return out


## The project's lexicon (LEXICON_PATH), or null when it has none.
static func project_lexicon() -> AKSpeechLexicon:
	if ResourceLoader.exists(LEXICON_PATH):
		return load(LEXICON_PATH) as AKSpeechLexicon
	return null


## What besides the text and voice decides how a line reads: the dictionary
## and the project's lexicon (for keys and bake caches).
static func data_key() -> String:
	var d := AKStressDict.shared()
	var lx := project_lexicon()
	return "%s|%s" % [d.source_md5 if d else "", lx.text.md5_text() if lx else ""]


## The patch a syllable plays: its voice state's own patch (a "shout" state
## for ** words, say), else the voice's.
static func patch_of(v: AKSpeechVoice, e: Dictionary) -> AKPatch:
	var st := AKSpeechMarkup.state_of(v, String(e.get("patch_state", "normal")))
	if st.has("patch"):
		var p: Variant = st.patch
		if p is AKPatch:
			return p
		if (p is String or p is StringName) and ResourceLoader.exists(String(p)):
			var r: Resource = load(String(p))
			if r is AKPatch:
				return r
	return v.patch


## The patches a line plays, the voice's first.
static func patches_for(line: AKSpeechLine) -> Array[AKPatch]:
	line.compile()
	var out: Array[AKPatch] = []
	if line.voice == null:
		return out
	if line.voice.patch:
		out.append(line.voice.patch)
	for e in line.events:
		var p := patch_of(line.voice, e)
		if p and not out.has(p):
			out.append(p)
	return out


## Voices to pick from: the kit's, then the project's. [{name, path, source}].
static func voices(user_dir := USER_VOICE_DIR) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for pair in [[KIT_VOICE_DIR, "kit"], [user_dir, "yours"]]:
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
	return PackedStringArray(["blip", "critter", "hollow", "drone_priest", "scratch_king"])


## A spoken line never peaks above this (dBFS): AKSpeech.render limits it.
const CEILING_DB := -1.0
## How long a plosive's aspiration lasts: past the vowel's start (the
## voice's plosive_lead_s) and into its attack.
const ASPIRATION_S := 0.06


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
		&"critter":
			# Squeaky and quick, Animalese-adjacent: high, fast, a wide wobbly melody.
			v.salt = "critter"
			v.patch = AKPatchLib.load_preset(&"speech_critter")
			v.base_note = 79.0
			v.range_semitones = 9.0
			v.tempo = 1.35
			v.syllable_s = 0.1
			v.gate = 0.7
			v.jitter = 0.25
			v.seed_pitch_semitones = 1.5
			v.seed_time = 0.15
			v.plosive = _plosive({freq_hz = 6000.0, mode = &"band", q = 2.0, attack_s = 0.001, decay_s = 0.002}, {freq_hz = 0.25}, -8.7,
				{color_hz = 2500.0, q = 0.7, lowpass_hz = 6000.0}, 3.0)
			v.fricative = _onset(&"static", {length_s = 0.04, hiss = 1.0, crackle = 0.0, color_hz = 5000.0, q = 1.2, fade_s = 0.01,
				lowpass_hz = 7000.0}, {color_hz = 0.2}, -12.0)
			v.breath = _onset(&"static", {length_s = 0.05, hiss = 1.0, crackle = 0.0, color_hz = 1500.0, q = 0.6, fade_s = 0.02,
				lowpass_hz = 3500.0}, {color_hz = 0.2}, -9.2)
			v.fricative_lead_s = 0.03
			v.onset_gain_db = -2.0
		&"hollow":
			# Whispered and unsettling: breath through a moving formant, almost no pitch.
			v.salt = "hollow"
			v.patch = AKPatchLib.load_preset(&"speech_hollow")
			v.base_note = 60.0
			v.range_semitones = 3.0
			v.tempo = 0.85
			v.syllable_s = 0.14
			v.gate = 0.9
			v.jitter = 0.2
			v.seed_pitch_semitones = 0.5
			v.plosive = _plosive({freq_hz = 1800.0, mode = &"band", q = 0.8, attack_s = 0.001, decay_s = 0.003}, {freq_hz = 0.3}, -8.8,
				{color_hz = 1400.0, q = 0.6, lowpass_hz = 4000.0}, 0.0)
			v.fricative = _onset(&"static", {length_s = 0.08, hiss = 1.0, crackle = 0.0, color_hz = 3800.0, q = 0.8, fade_s = 0.02,
				lowpass_hz = 6500.0}, {color_hz = 0.25}, -17.9)
			v.breath = _onset(&"static", {length_s = 0.07, hiss = 1.0, crackle = 0.0, color_hz = 1200.0, q = 0.6, fade_s = 0.025,
				lowpass_hz = 3000.0}, {color_hz = 0.25}, -13.2)
			v.fricative_lead_s = 0.06
		&"drone_priest":
			# Ominous: a low chant, slow, legato, long pauses.
			v.salt = "priest"
			v.patch = AKPatchLib.load_preset(&"speech_drone")
			v.base_note = 43.0
			v.range_semitones = 4.0
			v.tempo = 0.65
			v.syllable_s = 0.16
			v.gate = 0.97
			v.jitter = 0.1
			v.seed_pitch_semitones = 0.6
			v.pause_scale = 1.4
			v.plosive = _plosive({freq_hz = 700.0, mode = &"band", q = 0.8, attack_s = 0.002, decay_s = 0.004, body_hz = 90.0, body = 0.5},
				{body_hz = 0.15}, -5.5, {color_hz = 900.0, q = 0.6, lowpass_hz = 2500.0}, -2.0)
			v.fricative = _onset(&"static", {length_s = 0.07, hiss = 1.0, crackle = 0.0, color_hz = 1800.0, q = 1.0, fade_s = 0.02,
				lowpass_hz = 4500.0}, {color_hz = 0.2}, -9.5)
			v.breath = _onset(&"static", {length_s = 0.07, hiss = 1.0, crackle = 0.0, color_hz = 900.0, q = 0.6, fade_s = 0.025,
				lowpass_hz = 2500.0}, {color_hz = 0.2}, -7.8)
			v.onset_gain_db = -3.0
		&"scratch_king":
			# Katamari-style: sung vowels (the vowel voice, speech/vowels/)
			# scrubbed like a record, a baby-scratch back stroke on accents,
			# needle clicks and crackle.
			v.salt = "king"
			v.source = "scratch"
			var recs: Array[AKSample] = []
			for vowel in ["ee", "eh", "ah", "oh", "oo"]:
				# Sung at the voice's base note (E4), so at rest the formants sit where they belong.
				var smp := AKSample.from_recipe(load(VOWEL_DIR + "vowel_%s.tres" % vowel), 64.0)
				smp.resource_name = "vowel_" + vowel
				smp.gain_db = AKLibrary.PITCHED_TRIM_DB
				recs.append(smp)
			v.scratch_samples = recs
			v.scratch_wobble = 0.45
			v.scratch_back = 0.3
			v.base_note = 64.0
			v.range_semitones = 8.0
			v.tempo = 1.05
			v.syllable_s = 0.12
			v.gate = 0.85
			v.jitter = 0.2
			v.seed_pitch_semitones = 1.0
			v.plosive = _plosive({freq_hz = 2500.0, mode = &"band", q = 1.2, attack_s = 0.001, decay_s = 0.002}, {freq_hz = 0.3}, -2.9,
				{color_hz = 1800.0, q = 0.6, lowpass_hz = 5000.0}, 0.0)
			v.fricative = _onset(&"static", {length_s = 0.05, hiss = 0.6, crackle = 0.5, crackles_per_s = 600.0, color_hz = 4500.0,
				q = 0.8, fade_s = 0.008, lowpass_hz = 7000.0}, {color_hz = 0.2}, -5.5)
			v.breath = _onset(&"static", {length_s = 0.05, hiss = 1.0, crackle = 0.3, crackles_per_s = 300.0, color_hz = 1500.0,
				q = 0.6, fade_s = 0.015, lowpass_hz = 3500.0}, {color_hz = 0.2}, -9.2)
			v.fricative_lead_s = 0.035
			v.onset_gain_db = -6.0
			v.gain_db = 3.0
		_:
			push_error("AKSpeech: no voice preset '%s'" % preset)
			return null
	v.resource_name = String(preset)
	return v


## An onset recipe: one voice, its params, a seeded spread so each word gets
## its own version of the consonant (six to cycle through), and a trim that
## brings it to about half full scale (the voice's onset_gain_db balances it);
## the presets' hisses sit 4 dB under that and their breaths (h) 10 dB under.
## A plosive: a short release tick (the click voice) and then aspiration, a
## breathy hiss (the static voice, `asp` its params, `asp_db` against the
## tick) that runs on into the vowel's attack, so the release isn't left alone
## in the gap before the voice comes in.
static func _plosive(burst: Dictionary, spread: Dictionary, trim_db: float, asp: Dictionary, asp_db: float) -> AKRecipe:
	var r := _onset(&"click", burst, spread, trim_db)
	var p := {length_s = ASPIRATION_S, hiss = 1.0, crackle = 0.0, fade_s = 0.003, fade_out_s = ASPIRATION_S - 0.006}
	p.merge(asp, true)
	r.layers = [{voice = &"static", params = p, gain_db = asp_db, offset_s = 0.002}]
	return r


static func _onset(voice_name: StringName, params: Dictionary, spread: Dictionary, trim_db: float) -> AKRecipe:
	var r := AKRecipe.make(voice_name, params)
	r.gain_db = trim_db
	r.vary = spread
	r.vary_variants = 6
	return r


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
## Words whose stress the rules guessed (not in the lexicon or dictionary)
## are marked "(?)": candidates for the project's lexicon. Markup shows as
## written (*accent*, **max**, ^rise, _fall, stretch~, / pause, {state}).
## "HEY! | WHERE did you COME from? | ..."
static func describe_analysis(line: AKSpeechLine) -> String:
	line.compile()
	var parts := PackedStringArray()
	var last_state := "normal"
	for cl in line.clauses:
		var ws := PackedStringArray()
		for wi in range(int(cl.first), int(cl.last) + 1):
			var w: Dictionary = line.words[wi]
			var syl := PackedStringArray()
			for s in w.syllables:
				syl.append(String(s.letters).to_upper() if int(s.stress) == 1 else String(s.letters))
			var guessed: bool = not w.function and w.syllables.size() > 1 and String(w.get("source", "")).begins_with("rule")
			var shown := "·".join(syl) + ("(?)" if guessed else "")
			var emph := int(w.get("emphasis", 0))
			if emph > 0:
				shown = "*".repeat(emph) + shown + "*".repeat(emph)
			match String(w.get("contour", "")):
				"rise":
					shown = "^" + shown
				"fall":
					shown = "_" + shown
			shown += "~".repeat(int(w.get("stretch", 0)))
			var state := String(w.get("state", "normal"))
			if state != last_state:
				shown = "{%s} %s" % [state, shown]
				last_state = state
			if w.get("pause_after", false):
				shown += " /"
			ws.append(shown)
		parts.append(" ".join(ws) + String(cl.end))
	return " | ".join(parts)
