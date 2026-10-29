# SPDX-License-Identifier: Apache-2.0
@tool
## Pseudo-speech, stage 1: a line of dialogue as words, syllables, stress and
## a rough phonetic class per letter group. Heuristics only: nothing here has
## to be right, only stable (the same text always analyses the same way).
##
##   var a := AKSpeechText.analyse("Hey! Where did you come from?")
##   a.words[1]   # {text = "Where", norm = "where", function = false, clause = 1,
##                #  syllables = [{letters = "where", stress = 1, onset_class = NASAL, vowel = VOWEL_E, ...}]}
##   a.clauses    # [{end = "!", first = 0, last = 0}, {end = "?", first = 1, last = 5}]
##
## English only for now. Letters other than a-z are folded (é -> e) or
## ignored; digits and symbols separate words. Stress comes from the
## rule-based fallback (the stress dictionary comes later): neutral suffixes
## are stripped, stress-shifting suffixes place it, and otherwise the basic
## rule decides (first of two syllables unless a verb-like prefix; penult if
## heavy, else antepenult).
class_name AKSpeechText
extends RefCounted

enum { NONE, PLOSIVE, FRICATIVE, NASAL }
## Vowel targets, bright to dark: what the formant and brightness follow.
enum { VOWEL_I, VOWEL_E, VOWEL_A, VOWEL_O, VOWEL_U }
## Each vowel's position on the dark (0) .. bright (1) scale.
const VOWEL_BRIGHTNESS := [1.0, 0.75, 0.5, 0.25, 0.0]
const CLASS_NAMES := ["none", "plosive", "fricative", "nasal"]
const VOWEL_NAMES := ["i", "e", "a", "o", "u"]

## Clause end marks, in the order a run of punctuation picks them.
const ENDS := ["…", "?", "!", ".", ",", ";", ":"]

## Closed-class words: articles, pronouns, prepositions, auxiliaries and
## conjunctions. They are always unstressed, shortened and vary a little per
## occurrence. Left out on purpose: wh-question words (they carry the accent
## in a question) and out, up, down, off, back, away, which in dialogue are
## mostly stressed particles ("get out", "shut up").
const FUNCTION_WORDS := [
	"a", "an", "the", "this", "that", "these", "those", "some", "any", "each", "every", "no", "all", "both", "either", "neither",
	"i", "me", "my", "mine", "myself", "you", "your", "yours", "yourself", "yourselves", "he", "him", "his", "himself",
	"she", "her", "hers", "herself", "it", "its", "itself", "we", "us", "our", "ours", "ourselves", "they", "them",
	"their", "theirs", "themselves", "one", "ones",
	"of", "to", "in", "on", "at", "by", "for", "with", "from", "into", "onto", "upon", "about", "above", "across",
	"after", "against", "along", "among", "around", "as", "before", "behind", "below", "beneath", "beside", "between",
	"beyond", "but", "despite", "during", "except", "inside", "near", "outside", "over", "past", "since", "than",
	"through", "throughout", "till", "toward", "towards", "under", "underneath", "until", "unto", "via", "within", "without",
	"am", "is", "are", "was", "were", "be", "been", "being", "do", "does", "did", "have", "has", "had", "having",
	"will", "would", "shall", "should", "can", "could", "may", "might", "must", "ought",
	"im", "youre", "hes", "shes", "theyre", "ive", "youve", "weve", "theyve", "youll",
	"theyll", "id", "youd", "hed", "theyd", "isnt", "arent", "wasnt", "werent",
	"dont", "doesnt", "didnt", "hasnt", "havent", "hadnt", "wont", "wouldnt", "cant", "couldnt", "shouldnt",
	"and", "or", "nor", "so", "yet", "if", "because", "though", "although", "while", "whether", "unless", "whereas",
	"then", "there", "not", "just",
]

## Neutral suffixes: stripped, the stem's stress kept (-s, -ed, -ing ...).
const NEUTRAL_SUFFIXES := ["ness", "less", "ment", "hood", "ship", "ing", "ful", "ish", "dom", "es", "ed", "er", "ly", "s"]
## The suffix itself takes the stress.
const SELF_STRESS := ["esque", "ette", "ique", "eer", "ese", "ee"]
## The syllable before the suffix takes it.
const PRE_STRESS := ["ical", "tion", "sion", "ious", "ity", "ial", "ian", "ic"]
## The syllable two before the suffix (3+ syllables).
const ANTE_STRESS := ["ate", "ize", "ise"]
## Two-syllable words starting like a verb take the stress second.
const VERB_PREFIXES := ["pre", "con", "be", "re", "de", "ex"]
## Consonant runs that start a syllable together (hair|cut, but a|stride).
const ONSETS := ["str", "spr", "scr", "spl", "thr", "shr", "squ", "bl", "br", "cl", "cr", "dr", "fl", "fr", "gl", "gr",
	"pl", "pr", "sc", "sk", "sl", "sm", "sn", "sp", "st", "sw", "tr", "tw", "th", "sh", "ch", "ph", "wh", "qu", "kn", "wr"]

const _FOLD := {"à": "a", "á": "a", "â": "a", "ã": "a", "ä": "a", "å": "a", "æ": "ae", "ç": "c", "è": "e", "é": "e",
	"ê": "e", "ë": "e", "ì": "i", "í": "i", "î": "i", "ï": "i", "ñ": "n", "ò": "o", "ó": "o", "ô": "o", "õ": "o",
	"ö": "o", "ø": "o", "œ": "oe", "ù": "u", "ú": "u", "û": "u", "ü": "u", "ý": "y", "ÿ": "y", "ß": "ss"}
const _VOWELS := "aeiou"


## The whole line: {words, clauses, line_hash}. Each word: {text, norm,
## start, end (character offsets into `text`), function, clause, occurrence
## (how many times this word came before in its clause), syllables}. Each
## clause: {end (its end mark), first, last (word indices), excited (a "!"
## in a "?!" run)}.
static func analyse(text: String) -> Dictionary:
	var words: Array[Dictionary] = []
	var clauses: Array[Dictionary] = []
	var clause_start := 0
	var i := 0
	var n := text.length()
	while i < n:
		var c := text[i]
		if _is_letter(c):
			var s := i
			while i < n and (_is_letter(text[i]) or (_is_apostrophe(text[i]) and i + 1 < n and _is_letter(text[i + 1]))):
				i += 1
			var raw := text.substr(s, i - s)
			var norm := fold(raw)
			if norm != "":
				words.append({text = raw, norm = norm, start = s, end = i, function = FUNCTION_WORDS.has(norm),
					clause = clauses.size()})
			continue
		if _is_punct(c):
			var s := i
			while i < n and (_is_punct(text[i]) or text[i] == " " and i + 1 < n and _is_punct(text[i + 1])):
				i += 1
			var mark := _end_mark(text.substr(s, i - s))
			if words.size() > clause_start:
				clauses.append({end = mark, first = clause_start, last = words.size() - 1,
					excited = mark == "?" and text.substr(s, i - s).contains("!")})
				clause_start = words.size()
			continue
		i += 1
	if words.size() > clause_start:
		clauses.append({end = ".", first = clause_start, last = words.size() - 1, excited = false, implied = true})
	# Clause numbers for words after a final unpunctuated run are already right.
	for ci in clauses.size():
		var seen := {}
		for wi in range(clauses[ci].first, clauses[ci].last + 1):
			var w: Dictionary = words[wi]
			w.clause = ci
			w.occurrence = int(seen.get(w.norm, 0))
			seen[w.norm] = w.occurrence + 1
			w.syllables = syllables(w.norm)
			var st := stress(w.norm) if not w.function else PackedInt32Array()
			for si in w.syllables.size():
				w.syllables[si].stress = st[si] if si < st.size() else 0
	var norms := PackedStringArray()
	for w in words:
		norms.append(w.norm)
	return {words = words, clauses = clauses, line_hash = hash32(" ".join(norms))}


## Lowercase a-z only: accented letters folded, apostrophes and everything
## else dropped.
static func fold(s: String) -> String:
	var out := ""
	for c in s.to_lower():
		if c >= "a" and c <= "z":
			out += c
		elif _FOLD.has(c):
			out += _FOLD[c]
	return out


## A word's syllables by vowel clusters, at least one: each {letters, onset,
## nucleus, coda, onset_class, coda_class, vowel, heavy}. A silent final "e"
## (come, here), and the "e" of "-es" / "-ed" where English swallows it
## (makes, stopped), don't make a syllable.
static func syllables(norm: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if norm == "":
		return out
	var nuclei := _nuclei(norm)
	if nuclei.is_empty():
		out.append(_syllable(norm, "", norm, ""))
		return out
	# Boundaries: consonants between two nuclei; one goes right (ba|by), a
	# run splits before its longest onset-forming tail (hair|cut, a|stride).
	var cuts := [0]
	for k in range(1, nuclei.size()):
		var gap_s: int = nuclei[k - 1].y
		var gap_e: int = nuclei[k].x
		var run := norm.substr(gap_s, gap_e - gap_s)
		var keep := 0
		if run.length() == 1:
			keep = 0
		elif run.length() > 1:
			keep = run.length() - 1
			for o in ONSETS:
				if run.ends_with(o) and run.length() - o.length() < keep:
					keep = run.length() - o.length()
			if run.ends_with("ck") or run.ends_with("ng"):
				keep = run.length()
		cuts.append(gap_s + keep)
	cuts.append(norm.length())
	for k in nuclei.size():
		var a: int = cuts[k]
		var b: int = cuts[k + 1]
		var ns: int = nuclei[k].x
		var ne: int = nuclei[k].y
		# A swallowed "e" is coda, not nucleus, for the last syllable.
		out.append(_syllable(norm.substr(a, b - a), norm.substr(a, ns - a), norm.substr(ns, ne - ns), norm.substr(ne, b - ne)))
	return out


## Primary (1), secondary (2) or no (0) stress per syllable, by the rules.
static func stress(norm: String) -> PackedInt32Array:
	var syl := syllables(norm)
	var n := syl.size()
	var out := PackedInt32Array()
	out.resize(n)
	out.fill(0)
	if n <= 1:
		if n == 1:
			out[0] = 1
		return out
	var primary := _primary(norm, syl)
	out[primary] = 1
	if primary >= 2:
		out[primary - 2] = 2
	return out


## Phonetic class of a consonant run as it starts (onset) or ends (coda).
static func consonant_class(letters: String, at_end := false) -> int:
	var run := ""
	for ch in letters:
		if not _VOWELS.contains(ch):
			run += ch
	if run == "":
		return NONE
	var c := run[run.length() - 1] if at_end else run[0]
	var two := run.substr(run.length() - 2) if at_end else run.substr(0, 2)
	if two in ["sh", "th", "ph"]:
		return FRICATIVE
	if two == "ch":
		return PLOSIVE
	if c in ["p", "t", "k", "b", "d", "g", "c", "q", "x", "j"]:
		return PLOSIVE
	if c in ["s", "f", "h", "z", "v"]:
		return FRICATIVE
	if c in ["m", "n", "l", "r", "w", "y"]:
		return NASAL
	return NONE


## The vowel target of a nucleus: a few English spellings (ee, ea, ie -> i;
## oo, ew -> u; ou, ow -> o), else its first vowel letter (y counts as i).
static func vowel_of(nucleus: String) -> int:
	var two := nucleus.substr(0, 2)
	if two in ["ee", "ea", "ie"]:
		return VOWEL_I
	if two in ["oo", "ew"]:
		return VOWEL_U
	if two in ["ou", "ow"]:
		return VOWEL_O
	for c in nucleus:
		match c:
			"i", "y":
				return VOWEL_I
			"e":
				return VOWEL_E
			"a":
				return VOWEL_A
			"o":
				return VOWEL_O
			"u":
				return VOWEL_U
	return VOWEL_A


## 32-bit FNV-1a over the UTF-8 bytes: stable across Godot versions and
## platforms, unlike String.hash().
static func hash32(s: String) -> int:
	var h := 0x811C9DC5
	for b in s.to_utf8_buffer():
		h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF
	return h


## Mix integers into one non-negative 31-bit seed.
static func mix(a: int, b: int, c := 0) -> int:
	var h := hash32("%d:%d:%d" % [a, b, c])
	return h & 0x7FFFFFFF


# ------------------------------------------------------------------ inside

static func _primary(norm: String, syl: Array[Dictionary]) -> int:
	var n := syl.size()
	# The longest suffix wins, so -eer beats -er (career) and -ical beats -ic;
	# among neutral ones, one that uncovers a stress-placing suffix wins
	# (employees: -s, not -es, leaves employee).
	var best := ""
	var kind := ""
	for group in [["self", SELF_STRESS], ["pre", PRE_STRESS], ["ante", ANTE_STRESS]]:
		for suf: String in group[1]:
			if norm.ends_with(suf) and norm.length() - suf.length() >= 3 and suf.length() > best.length():
				best = suf
				kind = group[0]
	var neutral := ""
	for suf: String in NEUTRAL_SUFFIXES:
		if not norm.ends_with(suf) or norm.length() - suf.length() < 3:
			continue
		if _placing_suffix(norm.substr(0, norm.length() - suf.length())):
			neutral = suf
			break
		if suf.length() > neutral.length():
			neutral = suf
	if neutral.length() > best.length():
		best = neutral
		kind = "neutral"
	if best != "":
		var stem := norm.substr(0, norm.length() - best.length())
		var stem_n := syllables(stem).size()
		match kind:
			"self":
				return n - 1
			"pre":
				return clampi(stem_n - 1, 0, n - 1)
			"ante":
				if n >= 3:
					return clampi(stem_n - 2, 0, n - 1)
			"neutral":
				if stem_n <= n:
					var st := stress(stem)
					for k in st.size():
						if st[k] == 1:
							return k
	if n == 2:
		for p in VERB_PREFIXES:
			if norm.begins_with(p) and norm.length() > p.length() + 2:
				return 1
		return 0
	return n - 2 if syl[n - 2].heavy else n - 3


## True when `stem` ends with a suffix that places stress.
static func _placing_suffix(stem: String) -> bool:
	for group in [SELF_STRESS, PRE_STRESS, ANTE_STRESS]:
		for suf: String in group:
			if stem.ends_with(suf) and stem.length() - suf.length() >= 3:
				return true
	return false


## [start, end) of each vowel cluster that makes a syllable.
static func _nuclei(norm: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var n := norm.length()
	var i := 0
	while i < n:
		if _vowel_at(norm, i):
			var s := i
			while i < n and _vowel_at(norm, i):
				i += 1
			out.append(Vector2i(s, i))
		else:
			i += 1
	if out.size() < 2:
		return out
	var last: Vector2i = out.back()
	var tail := norm.substr(last.x)
	var before := norm[last.x - 1] if last.x > 0 else ""
	var silent := false
	if tail == "e" and before != "" and not _VOWELS.contains(before):
		# -le after a consonant is a syllable (table, little).
		silent = not (before == "l" and last.x >= 2 and not _VOWELS.contains(norm[last.x - 2]))
	elif tail == "es" and before != "" and not before in ["s", "x", "z", "c", "g", "h"]:
		silent = true
	elif tail == "ed" and before != "" and not before in ["t", "d"] and not _VOWELS.contains(before):
		silent = true
	if silent:
		out.remove_at(out.size() - 1)
	return out


static func _vowel_at(norm: String, i: int) -> bool:
	var c := norm[i]
	if _VOWELS.contains(c):
		return true
	# y is a vowel unless it starts the word or a syllable before a vowel (you, beyond).
	if c == "y":
		if i == 0:
			return false
		var next_vowel := i + 1 < norm.length() and _VOWELS.contains(norm[i + 1])
		return not next_vowel
	return false


static func _syllable(letters: String, onset: String, nucleus: String, coda: String) -> Dictionary:
	return {letters = letters, onset = onset, nucleus = nucleus, coda = coda,
		onset_class = consonant_class(onset), coda_class = consonant_class(coda, true),
		vowel = vowel_of(nucleus), heavy = coda != "" or nucleus.length() >= 2, stress = 0}


static func _end_mark(run: String) -> String:
	if run.contains("…") or run.contains(".."):
		return "…"
	if run.contains("?"):
		return "?"
	if run.contains("!"):
		return "!"
	if run.contains("."):
		return "."
	for m in [";", ":"]:
		if run.contains(m):
			return m
	return ","


static func _is_letter(c: String) -> bool:
	var l := c.to_lower()
	return (l >= "a" and l <= "z") or _FOLD.has(l)


static func _is_apostrophe(c: String) -> bool:
	return c == "'" or c == "’"


static func _is_punct(c: String) -> bool:
	return c in [".", "?", "!", ",", ";", ":", "…", "—", "–"]
