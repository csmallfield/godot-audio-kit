# SPDX-License-Identifier: Apache-2.0
@tool
## A pseudo-speech voice: who is speaking. A salt (so two species say the
## same word differently), a pitch, a range, a tempo, how loose the timing
## is, and the Sound Lab patch that makes the sound. One character, one
## asset.
##
## The patch is an ordinary AKPatch. It hears the line through the standard
## pseudo-speech inputs, all of which already exist on every patch:
##
##   gate        a note per syllable, held `gate` of the syllable's length
##   pitch       the note (a fractional MIDI number) at the syllable's accent,
##               plus pitch bend for the rest of the curve (keep the patch's
##               bend_range wide: 12 semitones is a good start)
##   intensity   the note's velocity
##   formant     the mod wheel (0 dark u .. 1 bright i), glided between vowels
##   brightness  aftertouch (0..1)
##
## A patch uses whichever it likes through its modulation matrix (mod_wheel
## -> cutoff for a wah, aftertouch -> cutoff for brightness ...). Run it in
## mono mode so a new syllable restarts the envelopes.
@icon("res://addons/audio_kit/icons/recipe.svg")
class_name AKSpeechVoice
extends Resource

## Mixed into every word's seed: the same word sounds different in two
## voices with different salts, and always the same in one.
@export var salt := "voice"
## What makes the sound: a Sound Lab `patch`, or `scratch` (vocal samples
## scrubbed back and forth like a record, see AKSpeechScratch).
@export_enum("patch", "scratch") var source := "patch"
## The Sound Lab patch that speaks (source "patch").
@export var patch: AKPatch
## The pitch the voice rests on, as a MIDI note (67 = G4).
@export_range(24.0, 108.0) var base_note := 60.0
## How far accents and phrase shapes move the pitch, in semitones.
@export_range(0.0, 24.0) var range_semitones := 6.0
## Speaking rate: 2 talks twice as fast.
@export_range(0.25, 4.0) var tempo := 1.0
## A plain unstressed syllable's length at tempo 1.
@export_range(0.03, 0.5) var syllable_s := 0.12
## How much of each syllable the note is held (the rest is a gap).
@export_range(0.1, 1.0) var gate := 0.75
## Per-occurrence looseness in timing (0 = metronomic).
@export_range(0.0, 1.0) var jitter := 0.15
## How far a word's own seed moves each syllable's pitch (± semitones): the
## melody that makes a word recognisable.
@export_range(0.0, 6.0) var seed_pitch_semitones := 0.8
## How far a word's seed stretches or squeezes its syllables (± fraction).
@export_range(0.0, 0.5) var seed_time := 0.12
## Gap between words and after punctuation, scaled together.
@export_range(0.0, 4.0) var pause_scale := 1.0
## Output level.
@export var gain_db := 0.0

## Voice states for {tag} markup, added to or overriding the built-in ones
## (AKSpeechMarkup.STATES): tag -> {pitch (semitones), range (x), tempo (x),
## intensity (x), brightness (+), patch (an AKPatch or its path: this state
## speaks through it)}. A "shout" state's patch also speaks **word**.
@export var states: Dictionary = {}

@export_group("Scratch")
## The records (source "scratch"): sustained vowel sounds, one per vowel
## from bright to dark (i, e, a, o, u), or fewer (shared out across the
## vowels). Each plays at its root note when the pitch curve is there.
@export var scratch_samples: Array[AKSample] = []
## How far the hand's speed swings within a stroke: 0 = a steady drag, 1 =
## from rest to twice the speed and back (the warble of a real scratch).
@export_range(0.0, 1.0) var scratch_wobble := 0.4
## The share of an accented syllable spent pulling the record back.
@export_range(0.0, 0.6) var scratch_back := 0.3
## Syllables with at least this stress get a back stroke.
@export_range(0.0, 1.0) var scratch_back_stress := 0.4
## The crossfader's ramp at each syllable's start and end.
@export_range(0.0005, 0.03) var scratch_cut_s := 0.003

@export_group("Onsets")
## Played where a syllable starts with a plosive (p t k b d g ...): a click or
## a burst. Empty = none. Any recipe; its `vary` gives each word its own
## version (picked by the syllable's seed), the same every time.
@export var plosive: AKRecipe
## Played where a syllable starts with a fricative (s sh f z th ...): a hiss.
## Empty = none.
@export var fricative: AKRecipe
## Played where a syllable starts with an h: a soft breath, darker and quieter
## than the hiss. Empty = none (the vowel starts on its own).
@export var breath: AKRecipe
## How long after a plosive the vowel's note starts.
@export_range(0.0, 0.1) var plosive_lead_s := 0.012
## How long the hiss runs before the vowel's note starts.
@export_range(0.0, 0.2) var fricative_lead_s := 0.045
## How long the breath runs before the vowel's note starts.
@export_range(0.0, 0.2) var breath_lead_s := 0.03
## Also hiss where a syllable ends in a fricative (haircuts, yes), quieter.
@export var coda_fricatives := true
## Onset level; each onset also follows its syllable's intensity.
@export var onset_gain_db := 0.0


## How long after the syllable's start its note begins: the onset's lead,
## when the voice has a sound for that onset.
func lead_for(onset_class: int) -> float:
	match onset_class:
		AKSpeechText.PLOSIVE:
			return plosive_lead_s if plosive else 0.0
		AKSpeechText.FRICATIVE:
			return fricative_lead_s if fricative else 0.0
		AKSpeechText.BREATH:
			return breath_lead_s if breath else 0.0
	return 0.0


## Everything that affects the sound, for hashing.
func describe() -> Dictionary:
	var st := {}
	for tag in states:
		var d: Dictionary = (states[tag] as Dictionary).duplicate()
		if d.get("patch") is AKPatch:
			d.patch = (d.patch as AKPatch).describe()
		st[tag] = d
	var records := []
	for smp in scratch_samples:
		records.append(smp.describe() if smp else null)
	return {salt = salt, source = source, patch = patch.describe() if patch else null, records = records,
		scratch_wobble = scratch_wobble, scratch_back = scratch_back, scratch_back_stress = scratch_back_stress,
		scratch_cut_s = scratch_cut_s, states = st, base_note = base_note,
		range_semitones = range_semitones, tempo = tempo, syllable_s = syllable_s, gate = gate, jitter = jitter,
		seed_pitch_semitones = seed_pitch_semitones, seed_time = seed_time, pause_scale = pause_scale, gain_db = gain_db,
		plosive = plosive.describe() if plosive else null, fricative = fricative.describe() if fricative else null,
		breath = breath.describe() if breath else null, breath_lead_s = breath_lead_s,
		plosive_lead_s = plosive_lead_s, fricative_lead_s = fricative_lead_s, coda_fricatives = coda_fricatives,
		onset_gain_db = onset_gain_db}
