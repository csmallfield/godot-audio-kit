# SPDX-License-Identifier: Apache-2.0
# Pseudo-speech, phase 1: text analysis (rule-based stress), prosody (phrase
# and accent curves, clause shapes, repetition), the deterministic compile,
# the Blip voice (pitch measured in the audio), the `speech` recipe voice and
# the Sound Lab's Pseudo-Speech page.
extends RefCounted

const LINE := "Hey! Where did you come from? Get out of here with that stupid stupid haircut!"
const BLIP := "res://addons/audio_kit/speech/voices/blip.tres"


func _blip() -> AKSpeechVoice:
	return load(BLIP)


func _line(text: String, v: AKSpeechVoice = null) -> AKSpeechLine:
	return AKSpeechLine.make(text, v if v else _blip()).compile()


## The events of word `wi`.
func _of_word(l: AKSpeechLine, wi: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in l.events:
		if int(e.word_index) == wi:
			out.append(e)
	return out


# ------------------------------------------------------------------ text

func test_the_test_line_reads_right() -> String:
	var got := AKSpeech.describe_analysis(_line(LINE))
	var want := "HEY! | WHERE did you COME from? | GET OUT of HERE with that STU·pid STU·pid HAIR·cut!"
	return "" if got == want else "analysis: %s" % got


func test_syllables() -> String:
	var want := {"hey": 1, "where": 1, "come": 1, "here": 1, "haircut": 2, "stupid": 2, "table": 2, "little": 2,
		"stopped": 1, "wanted": 2, "makes": 1, "boxes": 2, "beyond": 2, "you": 1, "hmm": 1, "shh": 1, "banana": 3,
		"electrical": 4, "haircuts": 2, "rhythm": 1}
	for w in want:
		var n := AKSpeechText.syllables(w).size()
		if n != want[w]:
			return "%s: %d syllables, want %d" % [w, n, want[w]]
	var hc := AKSpeechText.syllables("haircut")
	if hc[0].letters != "hair" or hc[1].letters != "cut":
		return "haircut splits %s|%s" % [hc[0].letters, hc[1].letters]
	var st := AKSpeechText.syllables("stupid")
	if st[0].letters != "stu" or st[1].letters != "pid":
		return "stupid splits %s|%s" % [st[0].letters, st[1].letters]
	return ""


func test_stress_rules() -> String:
	# word -> index of the primary stress, and the rule that puts it there.
	var want := {
		"stupid": 0,        # two syllables: the first
		"haircut": 0,
		"return": 1,        # verb-like prefix: the second
		"nation": 0,        # -tion: the syllable before
		"electrical": 1,    # -ical
		"ability": 1,       # -ity
		"career": 1,        # -eer takes it (and beats neutral -er)
		"employee": 2,      # -ee
		"employees": 2,     # neutral -s stripped, then -ee
		"dominate": 0,      # -ate: two before
		"hopelessness": 0,  # neutral -ness, -less
		"stupidly": 0,
		"haircuts": 0,
	}
	for w in want:
		var s := AKSpeechText.stress(w)
		var p := Array(s).find(1)
		if p != want[w]:
			return "%s: primary on syllable %d, want %d (%s)" % [w, p, want[w], s]
	if Array(AKSpeechText.stress("hey")) != [1]:
		return "one syllable is stressed"
	return ""


func test_tokens_marks_and_folding() -> String:
	var a := AKSpeechText.analyse("Café — résumé?! Don't... well")
	var norms: Array = a.words.map(func(w: Dictionary) -> String: return w.norm)
	if norms != ["cafe", "resume", "dont", "well"]:
		return "words: %s" % [norms]
	var marks: Array = a.clauses.map(func(c: Dictionary) -> String: return c.end)
	if marks != [",", "?", "…", "."]:
		return "marks: %s" % [marks]
	if not a.clauses[1].excited:
		return "?! is an excited question"
	if not a.words[2].function or a.words[0].function:
		return "function words: %s" % [a.words.map(func(w: Dictionary) -> bool: return w.function)]
	if a.words[1].start != 7 or a.words[1].end != 13:
		return "offsets of résumé: %d..%d" % [a.words[1].start, a.words[1].end]
	if not AKSpeechText.analyse("").words.is_empty() or not AKSpeechText.analyse("?! 42 ...").words.is_empty():
		return "no letters, no words"
	var occ: Array = AKSpeechText.analyse("no no no. no").words.map(func(w: Dictionary) -> int: return w.occurrence)
	if occ != [0, 1, 2, 0]:
		return "occurrences count within the clause: %s" % [occ]
	return ""


func test_hash_is_stable() -> String:
	# FNV-1a reference values: if these move, every word in every voice changes.
	if AKSpeechText.hash32("") != 0x811C9DC5 or AKSpeechText.hash32("a") != 0xE40C292C:
		return "fnv-1a: %x %x" % [AKSpeechText.hash32(""), AKSpeechText.hash32("a")]
	return ""


# ------------------------------------------------------------------ compile

func test_compile_is_deterministic() -> String:
	var a := _line(LINE)
	var b := AKSpeechLine.make(LINE, load(BLIP)).compile()
	if var_to_str(a.events) != var_to_str(b.events) or var_to_str(a.curves) != var_to_str(b.curves):
		return "the same text and voice compiled differently"
	if a.key() != b.key():
		return "keys differ"
	var c := AKSpeechLine.make(LINE + " ", load(BLIP))
	if c.key() == a.key():
		return "the key ignores the text"
	if a.events.size() != 18:
		return "%d syllables, want 18" % a.events.size()
	for i in range(1, a.events.size()):
		if float(a.events[i].t_start) < float(a.events[i - 1].t_end) - 1e-9:
			return "syllables overlap at %d" % i
	if absf(a.duration - float(a.events.back().t_end)) > 1e-9:
		return "duration"
	for k in ["pitch", "intensity", "brightness", "noise", "formant"]:
		var cv: PackedFloat32Array = a.curves[k]
		if cv.size() != ceili(a.duration * a.curve_rate) + 1:
			return "%s curve has %d samples" % [k, cv.size()]
		for x in cv:
			if not is_finite(x):
				return "%s curve isn't finite" % k
	return ""


func test_words_keep_their_sound() -> String:
	var l := _line("Stupid. You are so stupid, stupid friend.")
	var seeds := {}
	for e in l.events:
		var w: Dictionary = l.words[int(e.word_index)]
		if w.norm == "stupid":
			var k := int(e.syllable_index)
			if seeds.has(k) and seeds[k] != e.seed:
				return "a content word's seed changed between occurrences"
			seeds[k] = e.seed
	# The same word in another line, same voice: same seed.
	var other := _line("stupid")
	if other.events[0].seed != seeds[0]:
		return "a content word's seed depends on the line"
	# Another voice (another salt): a different seed.
	var v: AKSpeechVoice = load(BLIP).duplicate()
	v.salt = "critter"
	if _line("stupid", v).events[0].seed == seeds[0]:
		return "the salt doesn't change the word"
	# Function words: one of four variants per occurrence, reproducible.
	var f := _line("the cat and the dog and the cow and the hen and the fox and the owl and the end")
	var picks := {}
	for e in f.events:
		if f.words[int(e.word_index)].norm == "the":
			picks[e.seed] = true
	if picks.size() < 2 or picks.size() > 4:
		return "'the' took %d variants (want 2-4)" % picks.size()
	if var_to_str(f.events) != var_to_str(_line(f.source_text).events):
		return "function-word variants aren't reproducible"
	return ""


func test_prosody_follows_the_text() -> String:
	var l := _line(LINE)
	var r := l.voice.range_semitones
	# "Hey!": the strongest accent, short.
	var hey := _of_word(l, 0)[0]
	if float(hey.stress) < 0.99:
		return "Hey isn't fully accented (%.2f)" % hey.stress
	var get_ev := _of_word(l, 6)[0]
	if float(hey.t_end) - float(hey.t_start) >= float(get_ev.t_end) - float(get_ev.t_start):
		return "Hey isn't clipped short"
	# The question rises to its end, from wherever "come" was.
	var come := _of_word(l, 4)[0]
	var from := _of_word(l, 5)[0]
	var rise := l.curve_at("pitch", float(from.t_end)) - l.curve_at("pitch", float(come.t_start))
	if rise < 0.4 * r:
		return "the question rises only %.2f st" % rise
	# The exclamation falls: its last syllable well under its first.
	var fall := l.curve_at("pitch", float(_of_word(l, 6)[0].t_start)) - l.curve_at("pitch", float(l.events.back().t_end))
	if fall < 0.5 * r:
		return "the exclamation falls only %.2f st" % fall
	# stupid stupid: the second is stronger and higher.
	var s1 := _of_word(l, 12)[0]
	var s2 := _of_word(l, 13)[0]
	if float(s2.stress) <= float(s1.stress) * 1.2 or float(s2.pitch) <= float(s1.pitch):
		return "no escalation: %.2f -> %.2f stress, %.2f -> %.2f st" % [s1.stress, s2.stress, s1.pitch, s2.pitch]
	# Function words: unaccented, shorter and quieter than content words.
	var fn_len := 0.0
	var fn_n := 0
	var ct_len := 0.0
	var ct_n := 0
	for e in l.events:
		var w: Dictionary = l.words[int(e.word_index)]
		var d := float(e.t_end) - float(e.t_start)
		if w.function:
			if float(e.stress) > 0.0:
				return "%s is accented" % w.norm
			fn_len += d
			fn_n += 1
		elif int(e.syllable_index) == 0:
			ct_len += d
			ct_n += 1
	if fn_len / fn_n > 0.8 * ct_len / ct_n:
		return "function words aren't shorter (%.3f vs %.3f)" % [fn_len / fn_n, ct_len / ct_n]
	var did := _of_word(l, 2)[0]
	if float(did.velocity) >= float(come.velocity):
		return "a function word is as loud as a content word"
	# Pauses: a sentence end pauses longer than a comma.
	var c := _line("one, two. three")
	var gap_comma := float(c.events[1].t_start) - float(c.events[0].t_end)
	var gap_stop := float(c.events[2].t_start) - float(c.events[1].t_end)
	if gap_stop <= gap_comma or gap_comma <= 0.0:
		return "pauses: comma %.3f, stop %.3f" % [gap_comma, gap_stop]
	# Tempo 2 is twice as fast.
	var fast: AKSpeechVoice = load(BLIP).duplicate()
	fast.tempo = 2.0
	var lf := _line(LINE, fast)
	if absf(lf.duration * 2.0 - l.duration) > 0.01:
		return "tempo 2: %.3f s vs %.3f s" % [lf.duration, l.duration]
	return ""


# ------------------------------------------------------------------ sound

## The pitch (as a MIDI note) of `buf` between `a` and `b` seconds, from
## interpolated rising zero crossings.
func _pitch(buf: AKBuffer, a: float, b: float) -> float:
	var sr := buf.sample_rate
	var crossings: Array[float] = []
	for i in range(int(a * sr) + 1, mini(buf.frames(), int(b * sr))):
		var p := buf.l[i - 1]
		var q := buf.l[i]
		if p < 0.0 and q >= 0.0:
			crossings.append(i - 1 + p / (p - q))
	if crossings.size() < 3:
		return -1.0
	var hz := float(sr) * (crossings.size() - 1) / (float(crossings.back()) - crossings[0])
	return 69.0 + 12.0 * log(hz / 440.0) / log(2.0)


func test_blip_speaks() -> String:
	var l := _line(LINE)
	var buf := AKSpeech.render(l)
	if buf.frames() == 0:
		return "nothing rendered"
	var peak := buf.peak()
	if not is_finite(peak) or peak < 0.1 or peak > 1.0:
		return "peak %.3f" % peak
	var first := buf.first_above(1e-4)
	if first < 0 or first > 0.005 * buf.sample_rate:
		return "first audible at sample %d" % first
	var again := AKSpeech.render(_line(LINE))
	if buf.l != again.l or buf.r != again.r:
		return "two renders differ"
	# Each syllable's note sounds at its pitch (within a third of a semitone).
	for k in [0, 4, 6, 12, 14]:
		var e: Dictionary = l.events[k]
		var on := float(e.t_start)
		var want := l.voice.base_note + l.curve_at("pitch", on + 0.025)
		var got := _pitch(buf, on + 0.012, on + 0.04)
		if absf(got - want) > 0.35:
			return "syllable %d plays %.2f, want %.2f" % [k, got, want]
	# Silence between clauses.
	var gap_at := 0.5 * (float(l.events[0].t_end) + float(l.events[1].t_start))
	if absf(buf.l[int(gap_at * buf.sample_rate)]) > 0.01:
		return "sound in the pause after Hey"
	return ""


func test_the_question_rises_in_the_audio() -> String:
	# A slow, legato Blip so the last syllable is long enough to measure the
	# bend carrying the rise inside one note.
	var v: AKSpeechVoice = load(BLIP).duplicate()
	v.tempo = 0.4
	v.gate = 0.95
	v.jitter = 0.0
	var l := _line("Where did you come from?", v)
	var buf := AKSpeech.render(l)
	var last: Dictionary = l.events.back()
	var t0 := float(last.t_start)
	var t1 := t0 + (float(last.t_end) - t0) * v.gate
	var early := _pitch(buf, t0 + 0.01, t0 + 0.05)
	var late := _pitch(buf, t1 - 0.05, t1 - 0.01)
	var curve_rise := l.curve_at("pitch", t1 - 0.03) - l.curve_at("pitch", t0 + 0.03)
	if curve_rise < 0.5:
		return "the curve rises only %.2f st over the last syllable" % curve_rise
	if absf((late - early) - curve_rise) > 0.3:
		return "the audio rises %.2f st (%.2f -> %.2f), the curve %.2f" % [late - early, early, late, curve_rise]
	var want_late := v.base_note + l.curve_at("pitch", t1 - 0.03)
	if absf(late - want_late) > 0.35:
		return "the bend lands at %.2f, the curve says %.2f" % [late, want_late]
	return ""


func test_speech_recipe_voice() -> String:
	var r := AKRecipe.make(&"speech", {text = LINE, voice = BLIP})
	var b := AK.render(r)
	if b.frames() == 0 or b.peak() < 0.1:
		return "the speech voice is silent"
	var other := AKRecipe.make(&"speech", {text = "Hey!", voice = BLIP})
	if AK.bake_key(r) == AK.bake_key(other):
		return "the bake key ignores the text"
	if AK.bake_key(r) != AK.bake_key(AKRecipe.make(&"speech", {text = LINE, voice = BLIP})):
		return "the bake key isn't stable"
	return ""


func test_blip_voice_file_is_current() -> String:
	var path := AKSpeech.KIT_VOICE_DIR + "blip.tres"
	var v: AKSpeechVoice = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if v == null:
		return "%s doesn't load" % path
	if var_to_str(v.describe()) != var_to_str(AKSpeech.preset_voice(&"blip").describe()):
		return "%s is stale: run tools/make_speech_voices.gd" % path
	if v.patch == null or v.patch.resource_path != AKPatchLib.PRESET_DIR + "speech_blip.tres":
		return "blip should use the speech_blip patch file"
	return ""


# ------------------------------------------------------------------ tab

func test_speech_tab() -> String:
	var lab := AKSpeechLab.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(lab)
	var out := _tab(lab)
	lab.stop()
	lab.queue_free()
	return out


func _tab(lab: AKSpeechLab) -> String:
	if lab.line.voice == null or not lab.line.voice.resource_path.ends_with("blip.tres"):
		return "the tab should start on the Blip voice"
	if not lab.select_voice(BLIP):
		return "select_voice"
	lab.set_text(LINE, false)
	var buf := lab.render()
	if buf.frames() == 0 or int(lab.last_stats.syllables) != 18 or int(lab.last_stats.words) != 15:
		return "render from the tab: %s" % [lab.last_stats]
	if lab._analysis.text != AKSpeech.describe_analysis(lab.line):
		return "analysis label"
	# Subtitles: the word sounding at each syllable's start.
	for e in lab.line.events:
		if lab.line.word_at(float(e.t_start) + 0.001) != int(e.word_index):
			return "word_at"
	lab._draw_subtitle(1)
	if not lab._subtitle.text.contains("[color=#ffcf3b]Where[/color]"):
		return "subtitle highlight: %s" % lab._subtitle.text
	# Typing replays after a moment; an empty line says so instead.
	lab.set_text("", false)
	lab.play()
	if lab._status.text == "":
		return "an empty line should explain itself"
	return ""
