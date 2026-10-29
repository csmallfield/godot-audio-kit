# SPDX-License-Identifier: Apache-2.0
@tool
## Chord symbols to notes, for the Loops tab's chord guide (and for code).
##
## parse("Cm9") gives the root's pitch class and the chord's tones as semitones
## above the root: {ok, root, tones, pcs, bass, error}. Symbols are read the way
## lead sheets write them, in pieces after the root (C, F#, Bb):
##   triad     m min minor -   dim °   aug +   sus2 sus4 sus (= sus4)   5 (power)
##   sevenths  7 (dominant), maj7 M7 Δ7 (major), m7, m(maj7), dim7, m7b5 ø
##   upper     6 6/9 9 11 13 (each implies the sevenths below it)
##   changes   b5 #5 b9 #9 #11 b13   add2 add4 add6 add9 add11 add13   no3 no5
##   bass      /E, /G# (an inversion or slash chord)
## Words work too: "C minor 9", "F major 7", "G dominant 7 sus 4". A sus
## replaces the third, so "C minor sus 9" reads as C9sus4 (C F G Bb D).
class_name AKChords
extends RefCounted

## Common chords for menus: [symbol after the root, description].
const COMMON := [
	["", "major"], ["m", "minor"], ["dim", "diminished"], ["aug", "augmented"], ["5", "power chord"],
	["sus2", "suspended 2nd"], ["sus4", "suspended 4th"], ["6", "major 6th"], ["m6", "minor 6th"],
	["6/9", "6/9"], ["add9", "add 9"], ["madd9", "minor add 9"],
	["7", "dominant 7th"], ["maj7", "major 7th"], ["m7", "minor 7th"], ["m(maj7)", "minor-major 7th"],
	["m7b5", "half-diminished"], ["dim7", "diminished 7th"], ["aug7", "augmented 7th"],
	["7sus4", "7th sus 4"], ["9", "dominant 9th"], ["maj9", "major 9th"], ["m9", "minor 9th"],
	["9sus4", "9th sus 4"], ["7b9", "7th flat 9"], ["7#9", "7th sharp 9"], ["7#11", "7th sharp 11"],
	["maj7#11", "major 7th sharp 11 (lydian)"], ["11", "dominant 11th"], ["m11", "minor 11th"],
	["13", "dominant 13th"], ["maj13", "major 13th"], ["m13", "minor 13th"],
]

const _LETTERS := {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
const _SHARPS := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
const _LETTER_ORDER := ["C", "D", "E", "F", "G", "A", "B"]
## Letters above the root for each interval (a 3rd is two letters up).
const _DEGREE_LETTER := {0: 0, 1: 1, 2: 1, 3: 2, 4: 2, 5: 3, 6: 4, 7: 4, 8: 4, 9: 5, 10: 6, 11: 6,
	13: 1, 14: 1, 15: 1, 17: 3, 18: 3, 20: 5, 21: 5}
const _FLATS := ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
## Interval names by semitones above the root.
const _INTERVALS := {0: "R", 1: "b2", 2: "2", 3: "b3", 4: "3", 5: "4", 6: "b5", 7: "5", 8: "#5", 9: "6",
	10: "b7", 11: "7", 13: "b9", 14: "9", 15: "#9", 17: "11", 18: "#11", 20: "b13", 21: "13"}
## Words to symbol pieces (longest first, so "minor" is read before "min").
const _WORDS := [["half-diminished", "m7b5"], ["halfdiminished", "m7b5"], ["diminished", "dim"],
	["augmented", "aug"], ["suspended", "sus"], ["dominant", ""], ["major", "maj"], ["minor", "min"],
	["flat", "b"], ["sharp", "#"], ["♭", "b"], ["♯", "#"], ["ø7", "m7b5"], ["ø", "m7b5"], ["°", "dim"], ["Δ", "maj"],
	["(", ""], [")", ""], [",", ""], [" ", ""]]


## Read a chord symbol. `ok` false (with `error`) when a piece isn't understood.
static func parse(symbol: String) -> Dictionary:
	var s := symbol.strip_edges()
	for w in _WORDS:
		s = s.replacen(w[0], w[1])
	var fail := func(msg: String) -> Dictionary:
		return {ok = false, root = 0, tones = [], pcs = [], bass = -1, error = msg}
	if s == "":
		return fail.call("no chord")
	var root := _note(s)
	if root.len == 0:
		return fail.call("a chord starts with its root note (C, F#, Bb)")
	var rest := s.substr(root.len)
	# The bass after the last "/" that names a note ("6/9" isn't one).
	var bass := -1
	var bass_letter := 0
	var slash := rest.rfind("/")
	if slash >= 0:
		var b := _note(rest.substr(slash + 1).strip_edges())
		if b.len > 0 and b.len == rest.substr(slash + 1).strip_edges().length():
			bass = b.pc
			bass_letter = b.letter
			rest = rest.substr(0, slash)
	var q := rest
	var minor := false
	var maj := false
	var dim := false
	var aug := false
	var power := false
	var sus := 0
	var ext := 0
	var six_nine := false
	var adds := []
	var alts := {}
	var no3 := false
	var no5 := false
	var i := 0
	while i < q.length():
		var t := q.substr(i)
		var tl := t.to_lower()
		var n := 0
		if tl.begins_with("maj"):
			maj = true
			n = 3
		elif t.begins_with("M") and not tl.begins_with("min"):
			maj = true
			n = 1
		elif tl.begins_with("min"):
			minor = true
			n = 3
		elif tl.begins_with("m") or tl.begins_with("-"):
			minor = true
			n = 1
		elif tl.begins_with("dim"):
			dim = true
			n = 3
		elif tl.begins_with("aug"):
			aug = true
			n = 3
		elif tl.begins_with("+") and (t.length() == 1 or not t[1].is_valid_int()):
			aug = true
			n = 1
		elif tl.begins_with("alt"):
			ext = maxi(ext, 7)
			alts["b9"] = true
			alts["#9"] = true
			alts["b5"] = true
			alts["b13"] = true
			n = 3
		elif tl.begins_with("sus"):
			n = 3
			sus = 4
			if tl.substr(3).begins_with("2"):
				sus = 2
				n = 4
			elif tl.substr(3).begins_with("4"):
				n = 4
		elif tl.begins_with("add") or tl.begins_with("no") or tl.begins_with("omit"):
			var word := "add" if tl.begins_with("add") else ("omit" if tl.begins_with("omit") else "no")
			var num := _digits(tl.substr(word.length()))
			if num == "":
				return fail.call("'%s' needs a number" % word)
			n = word.length() + num.length()
			var d := num.to_int()
			if word == "add":
				var add_semi := {2: 2, 4: 5, 6: 9, 9: 14, 11: 17, 13: 21}
				if not add_semi.has(d):
					return fail.call("add%d isn't a chord tone (add2, 4, 6, 9, 11 or 13)" % d)
				adds.append(add_semi[d])
			elif d == 3:
				no3 = true
			elif d == 5:
				no5 = true
			else:
				return fail.call("only the 3rd or 5th can be left out")
		elif tl.begins_with("b") or tl.begins_with("#") or (tl.begins_with("+") or tl.begins_with("-")) and t.length() > 1 and t[1].is_valid_int():
			var num := _digits(tl.substr(1))
			var key := ("b" if tl[0] == "b" or tl[0] == "-" else "#") + num
			if not key in ["b5", "#5", "b9", "#9", "#11", "b13"]:
				return fail.call("'%s' isn't an alteration (b5, #5, b9, #9, #11, b13)" % t.substr(0, num.length() + 1))
			alts[key] = true
			if key in ["b9", "#9", "#11", "b13"]:
				ext = maxi(ext, 7)
			n = 1 + num.length()
		elif tl.begins_with("6/9") or tl.begins_with("69"):
			six_nine = true
			n = 3 if tl.begins_with("6/9") else 2
		elif tl[0].is_valid_int():
			var num := _digits(tl)
			n = num.length()
			match num.to_int():
				5: power = true
				6: ext = maxi(ext, 6)
				7, 9, 11, 13: ext = maxi(ext, num.to_int())
				_: return fail.call("'%s' isn't a chord extension (6, 7, 9, 11, 13)" % num)
		if n == 0:
			return fail.call("can't read '%s'" % t)
		i += n
	if power and (minor or ext > 0 or sus > 0):
		power = false
	var tones := [0]
	if power:
		tones.append(7)
	else:
		var third := 3 if minor or dim else 4
		if sus == 2:
			third = 2
		elif sus == 4:
			third = 5
		if not no3:
			tones.append(third)
		var fifth := 6 if dim or alts.has("b5") else (8 if aug or alts.has("#5") else 7)
		if not no5:
			tones.append(fifth)
		if six_nine:
			tones.append_array([9, 14])
		elif ext == 6:
			tones.append(9)
		if ext >= 7:
			# "dim7" is the diminished 7th; "maj" makes it major (also with a
			# minor triad, as m(maj7)).
			tones.append(11 if maj else (9 if dim and not minor else 10))
		elif maj and ext == 0 and not minor and adds.is_empty():
			pass   # "Cmaj" is the major triad
		if ext >= 9 and not alts.has("b9") and not alts.has("#9"):
			tones.append(14)
		if ext >= 11 and not alts.has("#11"):
			tones.append(17)
		if ext >= 13 and not alts.has("b13"):
			tones.append(21)
		for a in ["b9", "#9", "#11", "b13"]:
			if alts.has(a):
				tones.append({"b9": 13, "#9": 15, "#11": 18, "b13": 20}[a])
		tones.append_array(adds)
	var uniq := []
	for t in tones:
		if not uniq.has(t):
			uniq.append(t)
	uniq.sort()
	var pcs := []
	for t in uniq:
		var pc := posmod(int(root.pc) + int(t), 12)
		if not pcs.has(pc):
			pcs.append(pc)
	if bass >= 0 and not pcs.has(bass):
		pcs.append(bass)
	return {ok = true, root = root.pc, root_letter = root.letter, tones = uniq, pcs = pcs, bass = bass,
		bass_letter = bass_letter, error = ""}


## The chord's notes as names, root first and spelt by interval from the
## root as written ("Cm9" -> "C Eb G Bb D", "C7#9" -> "C E G Bb D#",
## "Bb13" -> "Bb D F Ab C Eb G"); a slash bass not in the chord last ("/Bb").
static func note_names(c: Dictionary) -> String:
	if not c.get("ok", false):
		return ""
	var out := []
	for t in c.tones:
		var n := _spell(int(c.root), int(c.root_letter), int(_DEGREE_LETTER.get(int(t), 0)), int(t))
		if not out.has(n):
			out.append(n)
	if int(c.bass) >= 0 and not (c.tones as Array).any(func(t: int) -> bool: return posmod(int(c.root) + t, 12) == int(c.bass)):
		out.append("/" + _spell(int(c.bass), int(c.bass_letter), 0, 0))
	return " ".join(out)


## The interval name of a pitch class in the chord ("R", "b3", "5", "9"), or "".
static func interval_name(c: Dictionary, pc: int) -> String:
	if not c.get("ok", false):
		return ""
	for t in c.tones:
		if posmod(int(c.root) + int(t), 12) == posmod(pc, 12):
			return _INTERVALS.get(int(t), "")
	if posmod(pc, 12) == int(c.bass):
		return "bass"
	return ""


## Pitch class (0 = C) to a name, with sharps or flats.
static func pc_name(pc: int, flats := false) -> String:
	return (_FLATS if flats else _SHARPS)[posmod(pc, 12)]


## The note `semis` above a root (pitch class and letter index, C = 0 ... B
## = 6), named with the letter `steps` above the root's: a third is always
## some kind of E above C, so a minor third is Eb, not D#.
static func _spell(root_pc: int, root_letter: int, steps: int, semis: int) -> String:
	var li := (root_letter + steps) % 7
	var natural: int = _LETTERS[_LETTER_ORDER[li]]
	var acc := posmod(root_pc + semis - natural + 6, 12) - 6
	var name: String = _LETTER_ORDER[li]
	if acc > 0:
		name += "#".repeat(acc)
	elif acc < 0:
		name += "b".repeat(-acc)
	return name


static func _note(s: String) -> Dictionary:
	if s == "":
		return {pc = 0, len = 0, letter = 0}
	var letter := s[0].to_upper()
	if not _LETTERS.has(letter):
		return {pc = 0, len = 0, letter = 0}
	var pc: int = _LETTERS[letter]
	var n := 1
	# A "b" right after the letter is a flat (Bb13 is B-flat 13; write C7b9,
	# not Cb9, for an alteration).
	while n < s.length() and s[n] in ["#", "♯", "b", "♭"]:
		pc += 1 if s[n] == "#" or s[n] == "♯" else -1
		n += 1
	return {pc = posmod(pc, 12), len = n, letter = _LETTER_ORDER.find(letter)}


static func _digits(s: String) -> String:
	var out := ""
	for ch in s:
		if ch.is_valid_int():
			out += ch
		else:
			break
	return out
