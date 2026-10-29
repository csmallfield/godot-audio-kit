# SPDX-License-Identifier: Apache-2.0
@tool
## A line of pseudo-speech: the text and the voice that says it. That's all
## that is saved; everything else is compiled from it, deterministically, on
## demand (the same text and voice always give the same syllables, curves and
## samples), so the .tres stays two readable fields.
##
##   var line := AKSpeechLine.make("Hey! Where did you come from?", load("res://addons/audio_kit/speech/voices/blip.tres"))
##   line.compile()
##   line.events[0]        # {t_start, t_end, word_index, seed, onset_class, vowel, stress, ...}
##   line.curves.pitch     # PackedFloat32Array at curve_rate, semitones from the voice's base
##   var buf := AKSpeech.render(line)
##
## Syllable events (dictionaries, in time order):
##   t_start, t_end   seconds from the line's start
##   word_index       which word (an index into `words`), for subtitles
##   syllable_index   which syllable of that word
##   seed             the word's seed mixed with the syllable's index
##   onset_class      AKSpeechText.NONE, PLOSIVE, FRICATIVE or NASAL
##   coda_class       the same for the consonants that end it
##   vowel            AKSpeechText.VOWEL_I .. VOWEL_U (bright to dark)
##   stress           0..1 after the rules: how strongly it's accented
##   pitch            semitones from the base at the accent (the note played)
##   velocity         intensity at the accent (the note's velocity)
## Curves (PackedFloat32Array, `curve_rate` samples a second, from 0 to
## `duration`): pitch (semitones from the base), intensity, brightness, noise
## and formant (0..1).
@icon("res://addons/audio_kit/icons/recipe.svg")
class_name AKSpeechLine
extends Resource

## What is said (with markup, once markup exists).
@export_multiline var source_text := ""
## Who says it.
@export var voice: AKSpeechVoice

## The text for subtitles (markup stripped).
var display_text := ""
## The words: {text, norm, start, end (offsets into display_text), function, clause, syllables ...}.
var words: Array[Dictionary] = []
## The clauses: {end (its end mark), first, last (word indices)}.
var clauses: Array[Dictionary] = []
## Syllable events, in time order (see above).
var events: Array[Dictionary] = []
## pitch, intensity, brightness, noise, formant -> PackedFloat32Array.
var curves := {}
## Samples a second in `curves`.
var curve_rate := 200
## Seconds from the first syllable's start to the last one's end.
var duration := 0.0

var _compiled_key := ""


static func make(text: String, p_voice: AKSpeechVoice) -> AKSpeechLine:
	var l := AKSpeechLine.new()
	l.source_text = text
	l.voice = p_voice
	return l


## Compile (if the text or voice changed since the last time) and return self.
func compile() -> AKSpeechLine:
	var k := key()
	if k != _compiled_key:
		AKSpeech.compile_into(self)
		_compiled_key = k
	return self


## A hash of everything that affects the result: text, voice, compiler.
func key() -> String:
	return var_to_str([AKSpeech.VERSION, source_text, voice.describe() if voice else null]).md5_text()


## The value of a curve at `t` seconds (linear between samples).
func curve_at(curve_name: String, t: float) -> float:
	var c: PackedFloat32Array = curves.get(curve_name, PackedFloat32Array())
	if c.is_empty():
		return 0.0
	var x := clampf(t * curve_rate, 0.0, float(c.size() - 1))
	var i := int(x)
	if i >= c.size() - 1:
		return c[c.size() - 1]
	return lerpf(c[i], c[i + 1], x - i)


## The word sounding at `t` seconds (the last one started), or -1 before the first.
func word_at(t: float) -> int:
	var w := -1
	for e in events:
		if float(e.t_start) > t:
			break
		w = int(e.word_index)
	return w
