# Pseudo-speech: plan

The live, commentable design doc is "Audio Kit — Pseudo-Speech (Text → Gibberish Voice)" (https://claude.ai/artifact/JHcbKYcEM1LxjkDzKAjBA6). This file is the in-repo copy that work on the `pseudo-speech` branch follows, with the decisions taken when the doc was mapped onto the kit; if the two disagree, ask.

## Goal

A written line of dialogue becomes a gibberish voice whose rhythm, stress and melody follow the text, delivered with subtitles: the King in Katamari Damacy, Animalese, Simlish, Undertale's blips. Getting close enough to sound plausible is the bar; intelligible speech, real TTS, ML and accurate phonetics are not goals. English first.

Three principles from the doc: a word always sounds the same (its seed fixes its timbre and melody, prosody only bends it); prosody and timbre are separate layers (the text side makes neutral curves, the voice is an ordinary Sound Lab patch); authored markup overrides inference (later phase).

## How the doc maps onto the kit

```
text ──► AKSpeechText.analyse ──► AKSpeechProsody.build ──► AKSpeechLine (events + curves)
         words, syllables,        timed syllables,           │
         stress, classes          pitch / intensity /         ▼
                                  brightness / noise /     AKSpeech.notes_for ──► AKSynth.render_notes(voice.patch)
                                  formant curves             notes, velocity, bend,      (baked, GDScript or native)
                                                             mod wheel, aftertouch
```

| Doc | In the kit |
| --- | --- |
| `PseudoSpeechLine`, `PseudoVoice`, `SyllableEvent` | `AKSpeechLine`, `AKSpeechVoice` (resources); syllable events are dictionaries in `AKSpeechLine.events` |
| Compiled events and curves stored on the line | Only `source_text` and `voice` are saved. Events and curves are compiled on demand (pure, deterministic, a few ms), so a line's `.tres` stays two readable fields. Curves are `PackedFloat32Array` at 200 Hz, not `Curve` resources |
| "Standard pseudo-speech inputs" on a patch | `AKPatch` has no named inputs, so the inputs are a fixed mapping onto what every patch already hears: a note per syllable (gate), the note's pitch at the syllable's accent plus pitch bend for the rest of the curve (pitch), velocity (intensity), mod wheel (formant), aftertouch (brightness). A patch reads them through its matrix. No engine change |
| `seed` and `onset_class` driving the patch per syllable | Not expressible in one patch: the engine's `random` source is keyed to note order, not to the word. For now the seed drives a small per-syllable pitch offset and length change (the word's melody), the same every time the word is said. Onsets (clicks, noise bursts) come later as recipe layers (`click`, `static`), or as a per-note engine value if that sounds thin |
| Baked output cached by hash of (text, voice) | The `speech` recipe voice (`{text, voice}`): `AK.bake_key` covers the text, the voice's settings and its patch, so cue maps, recipe streams and bakes work unchanged |
| Word seed `hash(word + salt)` | FNV-1a 32 over UTF-8 (`AKSpeechText.hash32`), stable across Godot versions, unlike `String.hash()` |
| `word_started` / `line_finished` signals | A resource can't emit timed signals. Phase 1 keeps `word_index` on every syllable and `AKSpeechLine.word_at(t)`; a player node with the signals comes with live playback |
| Sound Lab tab | `AKSpeechLab`, the **Pseudo-Speech** page after Sequencer |

## Phase 1 (this branch, built)

1. Text analysis, rule-based fallback only (`addons/audio_kit/speech/text.gd`): tokenize with clause end marks, fold accents, vowel-cluster syllables (silent final e, swallowed -es / -ed), stress rules (neutral suffixes stripped, stress-shifting suffixes, verb-like prefixes, heavy penult), phonetic class of onset and coda, vowel target, about 170 function words.
2. Prosody (`prosody.gd`): phrase shape per clause from its end mark, accent bumps (first content word strong, nuclear accent, one-word exclamation maximal and clipped), repetition escalation, function words short and quiet, timing from stress and letters, pauses from punctuation, seeded word melody and per-occurrence jitter. Function words pick one of four seeded variants per occurrence.
3. `AKSpeechLine`, `AKSpeechVoice`, `AKSpeech` (compile, `notes_for`, `render`, voices, presets).
4. The Blip voice: patch `patches/speech_blip.tres` (category `voice`, via `AKPatchLib.preset`) and voice `speech/voices/blip.tres` (via `tools/make_speech_voices.gd`).
5. The Pseudo-Speech page: text, voice picker, Play/Stop (baked), a subtitle that lights the spoken word, the analysis, stats and waveform.
6. `tests/test_speech.gd`.

Out of scope for phase 1: the stress dictionary build script, markup, curve display, other presets, live synthesis.

## Phase 2 (this branch, built)

Scope chosen: the patch presets and onset layers, which make the formant, brightness and onset paths audible without an engine change.

1. Three voices as ordinary patches with the standard inputs: Critter (`speech_critter`: pulse + FM, mod wheel -> cutoff, aftertouch -> FM), Hollow (`speech_hollow`: noise through a moving bandpass), Drone Priest (`speech_drone`: saws and a sub through a ladder, legato). Patches in the new `voice` category.
2. Onset layers on `AKSpeechVoice`: `plosive` and `fricative` recipes, coda fricatives, per-class leads that start the vowel after the consonant, level from the syllable's intensity, the variant from the syllable's seed (so a word keeps its consonants). `AKSpeech.onsets_for(line)`.
3. Vowel targets read a few spellings (ee, ea, ie as i; oo as u; ou, ow as o).
4. Tests: every voice file current, every voice speaks within level bounds, the formant moves the spectrum in each voice that reads it, onsets land where and how they should.

Scratch King and the stress dictionary were left for later.

## Phase 3 (this branch, built)

Scratch King, the doc's reference voice.

1. `AKSpeechVoice.source`: `patch` (as before) or `scratch`, with `scratch_samples` (records, one per vowel), `scratch_wobble`, `scratch_back`, `scratch_back_stress`, `scratch_cut_s`.
2. `AKSpeechScratch`: per-syllable stroke plans (record by vowel, landing point from the seed, back stroke on accents) and a GDScript renderer (4-point Hermite reads, rate = pitch curve x hand speed, crossfader cut, intensity level, brightness and formant low-pass). Onsets and gain stay in `AKSpeech.render`.
3. The `scratch_king` preset: the library's `vox_ee` .. `vox_oo` as records, needle clicks and crackle as onsets.
4. Tests: the hand's speed averages 1, strokes stay in their syllables, accents and only accents get back strokes, a word lands in the same groove, a pure-tone record scratches exactly the pitch curve (and the wobble lifts a stroke's middle by the predicted amount).

## Phase 4 (this branch, built): the stress dictionary

1. `tools/build_stress_dict.py` (Python, standard library): CMUdict's first pronunciation per plain-letter word, its stress digits mapped onto spelling. Spellings are split as the runtime splits them, then adjusted until the piece count matches CMU's syllable count (a vowel pair split, a silent e put back, a final syllabic consonant, the closest vowel groups merged); `docs/stress/build_report.md` counts each. Optional `--freq/--top` and `--moby-hyph`.
2. `en_stress.txt` (the readable source, ~116,000 words) packed by `tools/make_stress_dict.gd` into `en_stress.res` (`AKStressDict`: the sorted text gzipped plus line offsets, binary search, ~3.6 MB loaded, ~30 µs a lookup).
3. `AKSpeechLexicon` (`res://audio/speech/lexicon.tres`), then the dictionary, then a neutral suffix on a known stem, then a compound of two known words, then the rules. Words read by the rules are marked `(?)` in the analysis.
4. `tools/stress_report.gd` measures the rules against 2,000 dictionary words: `docs/stress/fallback_report.md`.
5. Line keys and the `speech` voice's bake key include the dictionary's and lexicon's hashes.

Departures from the doc, for review:
- **Every CMU word ships, not the top 20,000 by frequency.** The Leipzig frequency lists (and Gutenberg, for Moby) aren't reachable from the build machine this was made on; CMUdict is. Shipping all of it costs 2.5 MB of text and a 1.2 MB packed file but leaves no common word out. Running the script with a Leipzig list (`--freq eng_news_2023_1M-words.txt --top 20000`) gives the doc's version.
- **Moby Pronunciator isn't read yet**, so there is no CMU vs Moby disagreement list: its file format needs checking against the real file. Moby Hyphenator is supported but untested on the real file for the same reason.
- **Held-out words aren't held out**: with every CMU word shipped, the 2,000 measured words are in the dictionary too. The measurement runs the rules alone, so it's still the rules' accuracy on unseen-by-rules words.
- CMUdict is mostly names and rare words, so the rule accuracy is measured on a sample heavy with names; a frequency-weighted sample would be fairer.

## Phase 5 (this branch, built): markup

1. `AKSpeechMarkup.parse` turns the source text into the subtitle text and marks with positions; `apply` puts them on the analysed words (`emphasis`, `contour`, `stretch`, `pause_after`, `state`). `\*` and friends escape a mark.
2. Prosody: `*word*` at least a strong accent (an accented function word is spoken as a content word); `**word**` the strongest accent, clipped to 85%, with the "shout" state's loudness and brightness, through its patch if it has one; `^` / `_` a rise or fall of 0.6 x the range across the word, let go over 0.2 s; `~` stretches the last syllable by 60% a tilde; `/` adds 0.18 s; escalation still multiplies on top.
3. `{tag}` voice states: built-in whisper, shout, excited, sad, fast, slow, high, low (pitch, range, tempo, intensity, brightness); `AKSpeechVoice.states` adds or overrides them and can give a state its own patch. Lines render once per patch they use and mix.
4. Unclosed marks and unknown states play anyway and are listed in `AKSpeechLine.warnings`.

## Phase 6 (this branch, built): curves and per-word audition

`AKSpeechCurves` under the waveform on the Pseudo-Speech page, on the same time axis: word bands with their text, syllable ticks, accent dots sized by stress, and the pitch (around the base, range dashed), intensity, brightness, formant and noise curves, each switchable; a playhead. Clicking a word plays it cut from the rendered line (its place in the melody kept, a 4 ms fade at the cut).

## Decisions taken in phase 1

- wh-question words (where, what, who ...) are content words: they carry the accent in a question. out, up, down, off, back and away are content words too: in dialogue they are mostly stressed particles ("get out").
- Compounds (hair + cut) need the dictionary; until then the two-syllable rule gives the same answer for most.
- Among neutral suffixes, one that uncovers a stress-placing suffix wins (employees → employee → -ee).

## Next

- **Later (on the list, not now):** tune the weakest stress rules from `docs/stress/fallback_report.md` (antepenult 48.5%, heavy penult 54%, verb-like prefix 28%), then rerun `tools/stress_report.gd`.
- The doc's 20,000-word frequency-ranked dictionary and the CMU vs Moby cross-check (needs the Leipzig list and the Moby files on a machine that can download them).
- Live synthesis and a speaker node with `word_started` / `line_finished`.
