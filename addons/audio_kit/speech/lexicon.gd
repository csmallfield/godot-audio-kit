# SPDX-License-Identifier: Apache-2.0
@tool
## A project's own pronunciations for pseudo-speech, mostly invented names
## the dictionary can't know. Checked before the dictionary. One word a line,
## as in the dictionary, with or without the split:
##
##   zorblax zor|blax 10
##   kthulu 01             # the kit's own split (kthu|lu): one digit a syllable
##
## Lines starting with # are comments. The kit reads
## res://audio/speech/lexicon.tres when it exists (AKSpeech.LEXICON_PATH).
@icon("res://addons/audio_kit/icons/recipe.svg")
class_name AKSpeechLexicon
extends Resource

@export_multiline var text := "":
	set(v):
		text = v
		_parsed = {}
		_parsed_ok = false
		emit_changed()

var _parsed := {}
var _parsed_ok := false
var _bad := PackedStringArray()


## word -> {groups, stress}.
func entries() -> Dictionary:
	if not _parsed_ok:
		_parsed = {}
		_bad = PackedStringArray()
		for raw in text.split("\n", false):
			var line := raw.split("#", true, 1)[0].strip_edges()
			if line == "":
				continue
			var e := AKStressDict.parse_line(line)
			if e.is_empty():
				_bad.append(line)
			else:
				_parsed[e.word] = e
		_parsed_ok = true
	return _parsed


## Lines that didn't parse (a split that doesn't spell the word, or a stress
## digit per syllable missing).
func bad_lines() -> PackedStringArray:
	entries()
	return _bad


func lookup(word: String) -> Dictionary:
	return entries().get(word, {})
