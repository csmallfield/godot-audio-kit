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


# ------------------------------------------------------------------ dictionary

func test_dictionary_is_packed_and_current() -> String:
	var f := FileAccess.open(AKStressDict.TEXT_PATH, FileAccess.READ)
	if f == null:
		return "no %s" % AKStressDict.TEXT_PATH
	var d: AKStressDict = ResourceLoader.load(AKStressDict.RES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	if d == null:
		return "no %s" % AKStressDict.RES_PATH
	if d.source_md5 != f.get_as_text().md5_text():
		return "en_stress.res is stale: run tools/make_stress_dict.gd"
	if d.size() < 100000:
		return "only %d words" % d.size()
	var want := {"haircut": ["hair|cut", [1, 2]], "banana": ["ba|na|na", [0, 1, 0]], "create": ["cre|ate", [0, 1]],
		"seeing": ["see|ing", [1, 0]], "fire": ["fi|re", [1, 0]], "hey": ["hey", [1]]}
	for w in want:
		var e := d.lookup(w)
		if e.is_empty() or "|".join(e.groups) != want[w][0] or Array(e.stress) != want[w][1]:
			return "%s: %s" % [w, e]
	for w in ["", "zorblax", "aaaaa", "zzzzzzzz"]:
		if not d.lookup(w).is_empty():
			return "found '%s'" % w
	# Every entry is findable (a sample across the sort order).
	for i in range(0, d.size(), 997):
		var e := d.entry_at(i)
		if d.lookup(e.word).is_empty() or "".join(e.groups) != e.word:
			return "entry %d (%s) doesn't round-trip" % [i, e.word]
	return ""


func test_where_stress_comes_from() -> String:
	var lx := AKSpeechLexicon.new()
	lx.text = "# names\nzorblax zor|blax 01\nbanana ba|na|na 100\nnope x|y 1"
	if lx.bad_lines() != PackedStringArray(["nope x|y 1"]):
		return "bad lines: %s" % lx.bad_lines()
	var cases := {
		"zorblax": ["lexicon", "zor·BLAX"],          # an invented name
		"banana": ["lexicon", "BA·na·na"],           # the lexicon beats the dictionary
		"electrical": ["dictionary", "e·LEC·tri·cal"],
		"zorblaxes": ["lexicon: zorblax + -es", "zor·BLA·xes"],  # a suffix on a lexicon stem
		"hairbrushes": ["compound: hair + brushes", "HAIR·bru·shes"],
		"glorpish": ["rule: neutral -ish", "GLOR·pish"],
	}
	for w in cases:
		var r := AKSpeechText.read_word(w, lx)
		var shown := PackedStringArray()
		for sy in r.syllables:
			shown.append(String(sy.letters).to_upper() if int(sy.stress) == 1 else String(sy.letters))
		if r.source != cases[w][0] or "·".join(shown) != cases[w][1]:
			return "%s: %s from %s" % [w, "·".join(shown), r.source]
	var hb := AKSpeechText.read_word("hairbrushes", lx)
	if Array(hb.stress) != [1, 2, 0]:
		return "a compound's second part is secondary: %s" % hb.stress
	# Changing the lexicon changes the reading (the cache follows it).
	lx.text = "zorblax zor|blax 10"
	if AKSpeechText.read_word("zorblax", lx).stress[0] != 1:
		return "the lexicon edit wasn't picked up"
	# Rules alone when the dictionary is off.
	if AKSpeechText.read_word("banana", null, false).source != "rule: antepenult":
		return "rules only: %s" % AKSpeechText.read_word("banana", null, false).source
	# The analysis marks guessed words for the lexicon.
	var l := _line("Zorblax took the banana.")
	if AKSpeech.describe_analysis(l) != "ZOR·blax(?) TOOK the ba·NA·na.":
		return "analysis: %s" % AKSpeech.describe_analysis(l)
	return ""


# ------------------------------------------------------------------ markup

func test_markup_parses() -> String:
	var m := AKSpeechMarkup.parse("{whisper} come here / ^really? **GET OUT** heyyy~~ \\*no\\* _never. {} fine")
	if m.display != "come here really? GET OUT heyyy *no* never. fine":
		return "display: '%s'" % m.display
	if m.emphasis != [[18, 25, 2]]:
		return "emphasis: %s" % [m.emphasis]
	if m.rises != [10] or m.falls != [37] or m.pauses != [10] or m.stretches != [[31, 2]]:
		return "marks: rises %s falls %s pauses %s stretches %s" % [m.rises, m.falls, m.pauses, m.stretches]
	if m.tags != [[0, "whisper"], [44, "normal"]]:
		return "tags: %s" % [m.tags]
	if not m.warnings.is_empty():
		return "warnings: %s" % m.warnings
	var bad := AKSpeechMarkup.parse("*open {oops")
	if bad.warnings.size() != 2 or bad.display != "open oops":
		return "bad markup: %s, '%s'" % [bad.warnings, bad.display]
	# The words carry the marks; the analysis shows them as written.
	var l := _line("{whisper} come here / ^really? **GET OUT** heyyy~~ _never. {} fine")
	var got := AKSpeech.describe_analysis(l)
	if got != "{whisper} COME HERE / ^REAL·ly? | **GET** **OUT** HEYYY~~ _NE·ver. | {normal} FINE.":
		return "analysis: %s" % got
	if l.display_text != "come here really? GET OUT heyyy never. fine":
		return "subtitle: '%s'" % l.display_text
	var w := _line("hi {grumpy} there")
	if w.warnings.size() != 1 or not w.warnings[0].contains("grumpy"):
		return "unknown state: %s" % w.warnings
	return ""


## The first syllable event of the word `word` (its occurrence `n`).
func _ev(l: AKSpeechLine, word: String, n := 0) -> Dictionary:
	var seen := 0
	for e in l.events:
		if l.words[int(e.word_index)].norm == word and int(e.syllable_index) == 0:
			if seen == n:
				return e
			seen += 1
	return {}


func _word_span(l: AKSpeechLine, word: String) -> Vector2:
	var a := -1.0
	var b := -1.0
	for e in l.events:
		if l.words[int(e.word_index)].norm == word:
			if a < 0.0:
				a = float(e.t_start)
			b = float(e.t_end)
	return Vector2(a, b)


func test_markup_shapes_the_line() -> String:
	var r := _blip().range_semitones
	# *word*: a strong accent where there was a plain one.
	var plain := _line("You took my stupid hat.")
	var marked := _line("You took my *stupid* hat.")
	if float(_ev(marked, "stupid").stress) <= float(_ev(plain, "stupid").stress) + 0.1:
		return "*stupid*: %.2f vs %.2f" % [_ev(marked, "stupid").stress, _ev(plain, "stupid").stress]
	# ... and an accented function word is spoken as a content word.
	if float(_ev(_line("You took *my* hat."), "my").stress) < 0.5:
		return "*my* isn't accented"
	# **word**: the strongest accent, clipped.
	var pg := _ev(_line("Get out."), "get")
	var mg := _ev(_line("**Get** out."), "get")
	if float(mg.stress) < 0.999 or float(mg.t_end) - float(mg.t_start) >= float(pg.t_end) - float(pg.t_start):
		return "**get**: stress %.2f, %.3f s vs %.3f s" % [mg.stress, float(mg.t_end) - float(mg.t_start), float(pg.t_end) - float(pg.t_start)]
	# Escalation stacks on markup.
	var esc := _line("stupid stupid.")
	var esc_m := _line("stupid *stupid*.")
	if float(_ev(esc_m, "stupid", 1).stress) <= float(_ev(esc, "stupid", 1).stress):
		return "marked repeat: %.2f vs %.2f" % [_ev(esc_m, "stupid", 1).stress, _ev(esc, "stupid", 1).stress]
	# ^ rises across its word, _ falls, whatever the clause.
	for case in [["really.", "^really.", 1.0], ["really?", "_really?", -1.0]]:
		var p := _line(case[0])
		var m := _line(case[1])
		var sp := _word_span(p, "really")
		var sm := _word_span(m, "really")
		var dp := p.curve_at("pitch", sp.y) - p.curve_at("pitch", sp.x)
		var dm := m.curve_at("pitch", sm.y) - m.curve_at("pitch", sm.x)
		if (dm - dp) * float(case[2]) < 0.4 * r:
			return "%s moves the word by %.2f st against %.2f plain" % [case[1], dm, dp]
	# word~: the last syllable stretched, more for more tildes.
	var h0 := _ev(_line("Hey."), "hey")
	var h2 := _ev(_line("Hey~~."), "hey")
	var ratio := (float(h2.t_end) - float(h2.t_start)) / (float(h0.t_end) - float(h0.t_start))
	if absf(ratio - (1.0 + 2.0 * AKSpeechProsody.MARK_STRETCH)) > 0.05:
		return "hey~~ is %.2fx as long" % ratio
	# /: a pause between words.
	var g0 := _line("wait what")
	var g1 := _line("wait / what")
	var gap0 := float(g0.events[1].t_start) - float(g0.events[0].t_end)
	var gap1 := float(g1.events[1].t_start) - float(g1.events[0].t_end)
	if absf((gap1 - gap0) - AKSpeechProsody.MARK_PAUSE_S * _blip().pause_scale / _blip().tempo) > 1e-6:
		return "/ adds %.3f s" % (gap1 - gap0)
	# {whisper} is quieter; {fast} is quicker; {} goes back.
	var n := _line("come here now")
	var wl := _line("{whisper} come here {} now")
	if float(_ev(wl, "come").velocity) >= 0.7 * float(_ev(n, "come").velocity):
		return "whisper: %.2f vs %.2f" % [_ev(wl, "come").velocity, _ev(n, "come").velocity]
	if absf(float(_ev(wl, "now").velocity) - float(_ev(n, "now").velocity)) > 0.05:
		return "{} didn't go back to normal"
	var f := _line("{fast} come here now")
	if f.duration >= 0.8 * n.duration:
		return "fast: %.2f s vs %.2f s" % [f.duration, n.duration]
	return ""


func test_shout_state_brings_its_patch() -> String:
	var v: AKSpeechVoice = _blip().duplicate()
	var critter := AKPatchLib.load_preset(&"speech_critter")
	v.states = {"shout": {patch = critter}, "growl": {pitch = -6.0, patch = "res://addons/audio_kit/patches/speech_drone.tres"}}
	var l := _line("Hey **you** there {growl} now", v)
	var ps := AKSpeech.patches_for(l)
	if ps.size() != 3 or ps[0] != v.patch or ps[1] != critter:
		return "patches: %s" % [ps]
	var shouted := AKSpeech.notes_for(l, critter).filter(func(x: Dictionary) -> bool: return x.has("note"))
	if shouted.size() != 1:
		return "%d notes through the shout patch" % shouted.size()
	var buf := AKSpeech.render(l)
	if buf.frames() == 0 or not is_finite(buf.peak()) or buf.peak() > 1.0:
		return "render: peak %.3f" % buf.peak()
	if v.describe().states.shout.patch != critter.describe():
		return "the voice's describe() should hold the state's patch"
	if l.key() == _line("Hey **you** there {growl} now").key():
		return "the states don't reach the line's key"
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


func test_voice_files_are_current() -> String:
	if Array(AKSpeech.preset_names()) != ["blip", "critter", "hollow", "drone_priest", "scratch_king"]:
		return "presets: %s" % [AKSpeech.preset_names()]
	for n in AKSpeech.preset_names():
		var path := AKSpeech.KIT_VOICE_DIR + n + ".tres"
		var v: AKSpeechVoice = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if v == null:
			return "%s doesn't load" % path
		if var_to_str(v.describe()) != var_to_str(AKSpeech.preset_voice(StringName(n)).describe()):
			return "%s is stale: run tools/make_speech_voices.gd" % path
		if v.source == "scratch":
			if v.patch != null or v.scratch_samples.size() != 5:
				return "%s: a scratch voice has five records and no patch" % n
			continue
		if v.patch == null or not v.patch.resource_path.begins_with(AKPatchLib.PRESET_DIR + "speech_"):
			return "%s should use a speech_ patch file (%s)" % [n, v.patch.resource_path if v.patch else "none"]
		if v.patch.category != "voice" or v.patch.mode == "poly":
			return "%s's patch: category %s, mode %s" % [n, v.patch.category, v.patch.mode]
	return ""


func test_every_voice_speaks() -> String:
	for n in AKSpeech.preset_names():
		var v: AKSpeechVoice = load(AKSpeech.KIT_VOICE_DIR + n + ".tres")
		var l := _line(LINE, v)
		var buf := AKSpeech.render(l)
		var peak := buf.peak()
		if buf.frames() == 0 or not is_finite(peak) or peak < 0.1 or peak > 1.0:
			return "%s: peak %.3f" % [n, peak]
		var lufs := AKDynamics.lufs(buf)
		if lufs < -18.0 or lufs > -6.0:
			return "%s: %.1f LUFS, out of the kit's range for voices" % [n, lufs]
		if buf.l != AKSpeech.render(_line(LINE, v)).l:
			return "%s: two renders differ" % n
	# Each voice has its own pace and register.
	var lens := {}
	for n in AKSpeech.preset_names():
		lens[n] = _line(LINE, load(AKSpeech.KIT_VOICE_DIR + n + ".tres")).duration
	if not (lens.critter < lens.blip and lens.blip < lens.hollow and lens.hollow < lens.drone_priest):
		return "paces: %s" % [lens]
	return ""


func test_formant_reaches_the_patch() -> String:
	# The same word with a bright vowel and a dark one: the mod wheel (the
	# formant curve) should move the spectrum, in every voice that reads it.
	for n in ["critter", "hollow", "drone_priest"]:
		var v: AKSpeechVoice = load(AKSpeech.KIT_VOICE_DIR + n + ".tres")
		var ee: float = AKSoundFeatures.of(AKSpeech.render(_line("Meeee.", v))).centroid_hz
		var oo: float = AKSoundFeatures.of(AKSpeech.render(_line("Moooo.", v))).centroid_hz
		if ee < oo * 1.2:
			return "%s: mee %.0f Hz vs moo %.0f Hz" % [n, ee, oo]
	# The formant curve itself: i bright, u dark.
	var l := _line("Meeee. Moooo.")
	var i_at := float(l.events[0].t_start) + 0.05
	var u_at := float(l.events[1].t_start) + 0.08
	if l.curve_at("formant", i_at) < 0.8 or l.curve_at("formant", u_at) > 0.2:
		return "formant curve: i %.2f, u %.2f" % [l.curve_at("formant", i_at), l.curve_at("formant", u_at)]
	return ""


func test_onsets() -> String:
	var v: AKSpeechVoice = load(AKSpeech.KIT_VOICE_DIR + "critter.tres")
	var l := _line(LINE, v)
	var on := AKSpeech.onsets_for(l)
	var want := 0
	for e in l.events:
		if int(e.onset_class) in [AKSpeechText.PLOSIVE, AKSpeechText.FRICATIVE]:
			want += 1
		if int(e.coda_class) == AKSpeechText.FRICATIVE:
			want += 1
	if on.size() != want or want == 0:
		return "%d onsets, want %d" % [on.size(), want]
	# The same word keeps its consonants: both stupids' "st" are the same variant.
	var st := on.filter(func(o: Dictionary) -> bool: return o.kind == "fricative" and _word_of(l, float(o.time_s)) in [12, 13])
	if st.size() != 2 or st[0].variant != st[1].variant:
		return "stupid's onsets: %s" % [st.map(func(o: Dictionary) -> int: return o.variant)]
	# A fricative runs before the vowel: Hey's note starts `fricative_lead_s` in.
	var hey: Dictionary = l.events[0]
	var notes := AKSpeech.notes_for(l)
	var first_note: Dictionary = notes.filter(func(n: Dictionary) -> bool: return n.has("note"))[0]
	if absf(float(first_note.time_s) - (float(hey.t_start) + v.fricative_lead_s)) > 1e-6:
		return "Hey's note starts at %.3f" % first_note.time_s
	# ... and is heard there: high, noisy, before the note.
	var buf := AKSpeech.render(l)
	var a := roundi((float(hey.t_start) + 0.004) * buf.sample_rate)
	var b := roundi((float(hey.t_start) + v.fricative_lead_s - 0.004) * buf.sample_rate)
	var hiss := AKBuffer.new(b - a, buf.sample_rate)
	for i in b - a:
		hiss.l[i] = buf.l[a + i]
		hiss.r[i] = buf.r[a + i]
	if hiss.peak() < 0.05:
		return "no hiss before Hey's vowel (peak %.3f)" % hiss.peak()
	var f := AKSoundFeatures.of(hiss)
	if f.centroid_hz < 3000.0:
		return "the hiss is dark (%.0f Hz)" % f.centroid_hz
	# A voice without onset sounds keeps its notes on the syllable starts.
	var plain := _line(LINE)
	if not AKSpeech.onsets_for(plain).is_empty():
		return "blip has no onsets"
	var pn: Dictionary = AKSpeech.notes_for(plain).filter(func(n: Dictionary) -> bool: return n.has("note"))[0]
	if absf(float(pn.time_s) - float(plain.events[0].t_start)) > 1e-9:
		return "blip's first note moved"
	return ""


func test_scratch_king() -> String:
	var v: AKSpeechVoice = load(AKSpeech.KIT_VOICE_DIR + "scratch_king.tres")
	# The hand: mean speed 1 over a stroke, slow at the ends.
	var sum := 0.0
	for i in 1000:
		sum += AKSpeechScratch.head_speed((i + 0.5) / 1000.0, 0.45)
	if absf(sum / 1000.0 - 1.0) > 0.002 or absf(AKSpeechScratch.head_speed(0.0, 0.45) - 0.55) > 1e-6:
		return "head speed: mean %.4f, start %.3f" % [sum / 1000.0, AKSpeechScratch.head_speed(0.0, 0.45)]
	var l := _line(LINE, v)
	var plan := AKSpeechScratch.plan(l)
	if plan.size() != l.events.size():
		return "%d strokes for %d syllables" % [plan.size(), l.events.size()]
	for k in plan.size():
		var st: Dictionary = plan[k]
		var e: Dictionary = l.events[k]
		var backs := float(st.back_at) < float(st.off) - 1e-9
		if backs != (float(e.stress) >= v.scratch_back_stress):
			return "syllable %d (stress %.2f): back stroke %s" % [k, e.stress, backs]
		if float(st.on) < float(e.t_start) or float(st.off) > float(e.t_end) + 1e-9:
			return "stroke %d outside its syllable" % k
	# A word scratches the same groove each time: both stupids land alike.
	var s1 := plan[12]
	var s2 := plan[14]
	if s1.record != s2.record or absf(float(s1.pos0) - float(s2.pos0)) > 1e-6:
		return "stupid lands at %.0f and %.0f" % [s1.pos0, s2.pos0]
	# The record follows the vowel.
	if AKSpeechScratch.plan(_line("Meeee.", v))[0].record != 0 or AKSpeechScratch.plan(_line("Moooo.", v))[0].record != 4:
		return "records by vowel"
	var buf := AKSpeech.render(l)
	var peak := buf.peak()
	if not is_finite(peak) or peak < 0.1 or peak > 1.0:
		return "peak %.3f" % peak
	if buf.l != AKSpeech.render(_line(LINE, v)).l:
		return "two renders differ"
	var ee: float = AKSoundFeatures.of(AKSpeech.render(_line("Meeee.", v))).centroid_hz
	var oo: float = AKSoundFeatures.of(AKSpeech.render(_line("Moooo.", v))).centroid_hz
	if ee < oo * 1.1:
		return "mee %.0f Hz vs moo %.0f Hz" % [ee, oo]
	return ""


func test_scratch_rate_follows_the_pitch_curve() -> String:
	# A record of a pure 220 Hz tone (root A3), a steady hand and no back
	# strokes: the scratched pitch is exactly the curve.
	var v: AKSpeechVoice = load(AKSpeech.KIT_VOICE_DIR + "scratch_king.tres").duplicate()
	var tone := AKRecipe.make(&"tone", {freq_hz = 220.0, gate_s = 1.5, attack_s = 0.001, decay_s = 0.01, sustain = 1.0, release_s = 0.05})
	var rec := AKSample.from_recipe(tone, 57.0)
	var recs: Array[AKSample] = [rec]
	v.scratch_samples = recs
	v.scratch_wobble = 0.0
	v.scratch_back = 0.0
	v.plosive = null
	v.fricative = null
	v.tempo = 0.5
	var l := _line("Where did you come from?", v)
	var buf := AKSpeech.render(l)
	for k in [0, 3, 4]:
		var e: Dictionary = l.events[k]
		var mid := 0.5 * (float(e.t_start) + float(e.t_start) + (float(e.t_end) - float(e.t_start)) * v.gate)
		var want := v.base_note + l.curve_at("pitch", mid)
		var got := _pitch(buf, mid - 0.015, mid + 0.015)
		if absf(got - want) > 0.3:
			return "syllable %d scratches at %.2f, the curve says %.2f" % [k, got, want]
	# With the hand's wobble the middle of a stroke runs fast: higher.
	v.scratch_wobble = 0.45
	var lw := _line("Where did you come from?", v)
	var bw := AKSpeech.render(lw)
	var e0: Dictionary = lw.events[0]
	var mid0 := 0.5 * (float(e0.t_start) + float(e0.t_start) + (float(e0.t_end) - float(e0.t_start)) * v.gate)
	var lift := 12.0 * log(AKSpeechScratch.head_speed(0.5, 0.45)) / log(2.0)
	var want0 := v.base_note + lw.curve_at("pitch", mid0) + lift
	var got0 := _pitch(bw, mid0 - 0.006, mid0 + 0.006)
	if absf(got0 - want0) > 0.5:
		return "with wobble, the stroke's middle plays %.2f, want %.2f" % [got0, want0]
	return ""


func _word_of(l: AKSpeechLine, t: float) -> int:
	return l.word_at(t + 1e-4)


# ------------------------------------------------------------------ speaker

func _speaker(v: AKSpeechVoice, p_mode := "baked") -> AKSpeaker:
	var sp := AKSpeaker.new()
	sp.voice = v
	sp.mode = p_mode
	sp.audio_output = false
	sp.set_manual(true)
	(Engine.get_main_loop() as SceneTree).root.add_child(sp)
	return sp


func test_speaker_signals() -> String:
	var sp := _speaker(_blip())
	var words := []
	var syls := []
	var finished := [0]
	var started := [0]
	sp.line_started.connect(func(_l: AKSpeechLine) -> void: started[0] += 1)
	sp.word_started.connect(func(i: int, w: String) -> void: words.append([i, w, sp.position()]))
	sp.syllable_started.connect(func(i: int) -> void: syls.append(i))
	sp.line_finished.connect(func(_l: AKSpeechLine) -> void: finished[0] += 1)
	var l := sp.say(LINE)
	var out := ""
	var mouth_open := 0
	var mouth_shut := 0
	var t := 0.0
	while t < l.duration + 0.2:
		sp.update(t)
		if sp.is_speaking():
			if sp.mouth() > 0.0:
				mouth_open += 1
			else:
				mouth_shut += 1
		t += 0.005
	if started[0] != 1 or finished[0] != 1:
		out = "line_started %d, line_finished %d" % [started[0], finished[0]]
	elif words.size() != 15 or words[0][1] != "Hey" or words[14][1] != "haircut":
		out = "words: %s" % [words.map(func(x: Array) -> String: return x[1])]
	elif syls != range(18):
		out = "syllables: %s" % [syls]
	elif mouth_open == 0 or mouth_shut == 0:
		out = "the mouth never moves (%d open, %d shut)" % [mouth_open, mouth_shut]
	else:
		# Each word arrives within one step of its first syllable.
		for wd in words:
			var start := -1.0
			for e in l.events:
				if int(e.word_index) == int(wd[0]):
					start = float(e.t_start)
					break
			if float(wd[2]) < start or float(wd[2]) > start + 0.0051:
				out = "%s arrived at %.3f, starts at %.3f" % [wd[1], wd[2], start]
				break
	# A second say() interrupts: no finish for the first.
	if out == "":
		finished[0] = 0
		sp.say("one two three")
		sp.update(0.1)
		sp.say("four")
		sp.update(5.0)
		if finished[0] != 1:
			out = "interrupting: %d finishes" % finished[0]
	sp.queue_free()
	return out


func test_speaker_bakes_once() -> String:
	var sp := _speaker(_blip())
	sp.say("Hey you.")
	var a: Variant = (sp._main_player() as AudioStreamPlayer).stream
	sp.say("Hey you.")
	var b: Variant = (sp._main_player() as AudioStreamPlayer).stream
	sp.say("Hey there.")
	var c: Variant = (sp._main_player() as AudioStreamPlayer).stream
	sp.queue_free()
	if a == null or a != b or c == a:
		return "the bake cache: %s %s %s" % [a, b, c]
	if sp.playing_mode != "baked":
		return "mode %s" % sp.playing_mode
	return ""


func test_speaker_live_matches_the_bake() -> String:
	if not AKSynth.available():
		print("        (native core not built: live speech skipped)")
		return ""
	var out := ""
	for n in ["blip", "critter", "drone_priest"]:
		var v: AKSpeechVoice = load(AKSpeech.KIT_VOICE_DIR + n + ".tres")
		var sp := _speaker(v, "live")
		var l := sp.say("Hey! Where did you come *from*? Get **out**.")
		if sp.playing_mode != "live":
			out = "%s didn't play live" % n
		else:
			var lead := roundi(sp.live_lead_s * AK.sample_rate)
			for patch in sp.live_streams():
				# The bake with the same lead-in, so effects (Drone Priest's chorus) run
				# from the same moment as on the live stream.
				var notes := AKSpeech.notes_for(l, patch).map(func(x: Dictionary) -> Dictionary:
					var y := x.duplicate()
					y.time_s = float(x.time_s) + float(lead) / AK.sample_rate
					return y)
				var want := AKSynth.render_notes(patch, notes, 0.0, AK.sample_rate)
				var got: Array = sp.live_streams()[patch].render_offline(want.frames())
				var gl: PackedFloat32Array = got[0]
				var sig := 0.0
				var err := 0.0
				for i in want.frames():
					sig += want.l[i] * want.l[i]
					var d := gl[i] - want.l[i]
					err += d * d
				var snr := 10.0 * log(sig / maxf(err, 1e-30)) / log(10.0)
				if snr < 90.0:
					out = "%s live vs baked: %.1f dB" % [n, snr]
					break
		sp.queue_free()
		if out != "":
			break
	return out


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
	if lab._voices.size() < 4 or lab._voice.item_count != lab._voices.size():
		return "the voice picker lists %d voices" % lab._voice.item_count
	if not lab.select_voice(AKSpeech.KIT_VOICE_DIR + "critter.tres") or lab.line.voice.salt != "critter":
		return "picking critter"
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
	lab.set_text("*Hey* you ^there~", false)
	lab.render()
	lab._draw_subtitle(-1)
	if lab._subtitle.text != "Hey you there":
		return "the subtitle shows markup: %s" % lab._subtitle.text
	lab.set_text(LINE, false)
	lab.render()
	lab._draw_subtitle(1)
	if not lab._subtitle.text.contains("[color=#ffcf3b]Where[/color]"):
		return "subtitle highlight: %s" % lab._subtitle.text
	# The curve view: the line on the waveform's time axis; click a word to hear it.
	var cv := lab._curves
	cv.size = Vector2(1000, 170)
	if cv.line != lab.line or absf(cv.span_s - buf.seconds()) > 1e-6:
		return "the curves show another line or length"
	for wi in [0, 4, 12, 14]:
		var span := Vector2(-1, -1)
		for e in lab.line.events:
			if int(e.word_index) == wi:
				if span.x < 0.0:
					span.x = float(e.t_start)
				span.y = float(e.t_end)
		var x := cv.x_of(0.5 * (span.x + span.y))
		if cv.word_at_x(x) != wi:
			return "word at x %.0f is %d, want %d" % [x, cv.word_at_x(x), wi]
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = Vector2(x, 80)
		cv._gui_input(click)
		var st := lab.player.stream as AudioStreamWAV
		var frames := st.data.size() / 2 / (2 if st.stereo else 1)
		var want := roundi((span.y + 0.08 - span.x) * buf.sample_rate)
		if absi(frames - want) > 2 or absf(lab._play_from - span.x) > 1e-5:
			return "clicking word %d plays %d frames from %.3f, want %d from %.3f" % [wi, frames, lab._play_from, want, span.x]
	lab.stop()
	# Typing replays after a moment; an empty line says so instead.
	lab.set_text("", false)
	lab.play()
	if lab._status.text == "":
		return "an empty line should explain itself"
	return ""
