# SPDX-License-Identifier: Apache-2.0
@tool
## Pseudo-speech markup: a writer's overrides, inline in the line. Each mark
## changes only the word or span it touches; the subtitle shows the text with
## the marks taken out.
##
##   *word*        strong accent: pitch, volume and brightness up
##   **word**      maximum accent, clipped, shouted (the voice's "shout" state)
##   ^word         a rise on this word, whatever the clause
##   _word         a fall on this word
##   word~         stretch the last syllable (repeat ~ for longer)
##   /             a short pause
##   {tag}         switch voice state until the next tag or the line's end
##                 ({normal} or {} goes back)
##   \*  \^ ...    the character itself, not a mark
##
## Spans can cover several words: **GET OUT**, *really quite*. Escalation of a
## repeated word still applies under markup: *stupid* stupid stacks.
class_name AKSpeechMarkup
extends RefCounted

## Built-in voice states for {tag}: pitch (semitones), range (x the voice's
## range), tempo (x), intensity (x), brightness (+). A voice's `states`
## override or add to these, and may give a state its own `patch`.
const STATES := {
	"normal": {},
	"whisper": {range = 0.4, tempo = 0.9, intensity = 0.45, brightness = -0.25},
	"shout": {pitch = 3.0, range = 1.3, tempo = 1.1, intensity = 1.35, brightness = 0.3},
	"excited": {pitch = 2.0, range = 1.5, tempo = 1.2, intensity = 1.1, brightness = 0.1},
	"sad": {pitch = -2.0, range = 0.6, tempo = 0.8, intensity = 0.8, brightness = -0.15},
	"fast": {tempo = 1.5},
	"slow": {tempo = 0.7},
	"high": {pitch = 5.0},
	"low": {pitch = -5.0},
}


## {display (the text without marks), emphasis: [[start, end, level]],
## rises, falls, pauses: [position], stretches: [[position, count]],
## tags: [[position, name]], warnings} with positions in `display`.
static func parse(source: String) -> Dictionary:
	var out := ""
	var emph := []
	var rises := []
	var falls := []
	var pauses := []
	var stretches := []
	var tags := []
	var warnings := PackedStringArray()
	var open1 := -1
	var open2 := -1
	var i := 0
	var n := source.length()
	while i < n:
		var c := source[i]
		if c == "\\" and i + 1 < n:
			out += source[i + 1]
			i += 2
			continue
		if c == "*":
			if i + 1 < n and source[i + 1] == "*":
				if open2 < 0:
					open2 = out.length()
				else:
					emph.append([open2, out.length(), 2])
					open2 = -1
				i += 2
				continue
			if open1 < 0:
				open1 = out.length()
			else:
				emph.append([open1, out.length(), 1])
				open1 = -1
			i += 1
			continue
		if (c == "^" or c == "_") and i + 1 < n and AKSpeechText._is_letter(source[i + 1]):
			(rises if c == "^" else falls).append(out.length())
			i += 1
			continue
		if c == "~":
			var k := 0
			while i < n and source[i] == "~":
				k += 1
				i += 1
			stretches.append([out.length(), k])
			continue
		if c == "/":
			pauses.append(out.length())
			i += 1
			# One space stays between the words around it.
			while i < n and source[i] == " " and out.ends_with(" "):
				i += 1
			continue
		if c == "{":
			var close := source.find("}", i)
			if close < 0:
				warnings.append("an unclosed { at %d" % i)
				i += 1
				continue
			var tag := source.substr(i + 1, close - i - 1).strip_edges().to_lower()
			tags.append([out.length(), tag if tag != "" else "normal"])
			i = close + 1
			while i < n and source[i] == " " and (out == "" or out.ends_with(" ")):
				i += 1
			continue
		out += c
		i += 1
	if open1 >= 0:
		emph.append([open1, out.length(), 1])
		warnings.append("an unclosed * (accent runs to the end)")
	if open2 >= 0:
		emph.append([open2, out.length(), 2])
		warnings.append("an unclosed ** (accent runs to the end)")
	# The display text loses leading spaces the marks left; shift positions to match.
	var lead := out.length() - out.lstrip(" ").length()
	var display := out.strip_edges()
	return {display = display, emphasis = _shift(emph, lead, 2), rises = _shift(rises, lead), falls = _shift(falls, lead),
		pauses = _shift(pauses, lead), stretches = _shift(stretches, lead), tags = _shift(tags, lead), warnings = warnings}


## Put the marks on an analysis of the display text: each word gets
## emphasis (0, 1 or 2), contour ("", "rise", "fall"), stretch (how many ~),
## pause_after (true for a / after it) and state (the {tag} it's in).
static func apply(a: Dictionary, m: Dictionary) -> void:
	var words: Array = a.words
	for w in words:
		w.emphasis = 0
		w.contour = ""
		w.stretch = 0
		w.pause_after = false
		w.state = "normal"
	for e in m.emphasis:
		for w in words:
			if int(w.start) < int(e[1]) and int(w.end) > int(e[0]):
				w.emphasis = maxi(int(w.emphasis), int(e[2]))
	for p in m.rises:
		var w := _word_starting(words, int(p))
		if not w.is_empty():
			w.contour = "rise"
	for p in m.falls:
		var w := _word_starting(words, int(p))
		if not w.is_empty():
			w.contour = "fall"
	for s in m.stretches:
		var w := _word_before(words, int(s[0]))
		if not w.is_empty():
			w.stretch = int(w.stretch) + int(s[1])
	for p in m.pauses:
		var w := _word_before(words, int(p))
		if not w.is_empty():
			w.pause_after = true
	var tags: Array = m.tags
	for w in words:
		for t in tags:
			if int(t[0]) <= int(w.start):
				w.state = String(t[1])


## A voice state's settings: the built-in ones, overridden by the voice's.
static func state_of(voice: AKSpeechVoice, tag: String) -> Dictionary:
	var s: Dictionary = STATES.get(tag, {}).duplicate()
	if voice and voice.states.has(tag):
		s.merge(voice.states[tag], true)
	return s


## Tags in a parse that neither the kit nor the voice knows.
static func unknown_tags(m: Dictionary, voice: AKSpeechVoice) -> PackedStringArray:
	var out := PackedStringArray()
	for t in m.tags:
		var tag := String(t[1])
		if not STATES.has(tag) and not (voice and voice.states.has(tag)) and not out.has(tag):
			out.append(tag)
	return out


## Positions moved left by `by`: plain positions, or the first `fields`
## entries of each list item.
static func _shift(list: Array, by: int, fields := 1) -> Array:
	var out := []
	for x in list:
		if x is Array:
			var y: Array = x.duplicate()
			for k in fields:
				y[k] = maxi(0, int(y[k]) - by)
			out.append(y)
		else:
			out.append(maxi(0, int(x) - by))
	return out


static func _word_starting(words: Array, pos: int) -> Dictionary:
	for w in words:
		if int(w.start) >= pos:
			return w
	return {}


static func _word_before(words: Array, pos: int) -> Dictionary:
	var best := {}
	for w in words:
		if int(w.end) <= pos:
			best = w
	return best
