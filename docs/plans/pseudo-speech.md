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

1. `tools/build_stress_dict.py` (Python, standard library): CMUdict's first pronunciation per plain-letter word, its stress digits mapped onto spelling. Spellings are split as the runtime splits them, then adjusted until the piece count matches CMU's syllable count (a vowel pair split, a silent e put back, a final syllabic consonant, the closest vowel groups merged); `docs/stress/build_report.md` counts each. `--freq/--top` (Leipzig), `--moby-hyph` and `--moby-pron`.
2. `en_stress.txt` (the readable source, 40,890 words) packed by `tools/make_stress_dict.gd` into `en_stress.res` (`AKStressDict`: the sorted text gzipped plus line offsets, binary search, 442 KB on disk, about 1.3 MB loaded, ~30 µs a lookup).
3. `AKSpeechLexicon` (`res://audio/speech/lexicon.tres`), then the dictionary, then a neutral suffix on a known stem, then a compound of two known words, then the rules. Words read by the rules are marked `(?)` in the analysis.
4. `tools/stress_report.gd` measures the rules against 2,000 held-out words (`docs/stress/held_out.txt`: the most frequent known words past the cut): `docs/stress/fallback_report.md`. `tools/stress_coverage.gd` measures dictionary sizes on dialogue: `docs/stress/coverage.md`.
5. Line keys and the `speech` voice's bake key include the dictionary's and lexicon's hashes.

Built as the doc specifies on branch `stress-dict` (the first cut on this branch shipped every CMU word, as Leipzig and Gutenberg weren't reachable then):
- **The top 50,000 word forms** of Leipzig's `eng_news_2023_1M` (inflected forms), not the doc's 20,000: Chris's choice after measuring sizes on dialogue (`docs/stress/coverage.md`: 20k mis-stressed 1.5-2.1% of content words, 50k 0.4-1.0%, for 442 KB against 204 KB). 40,890 ship: 39,577 from CMU, 1,313 from Moby. 8,819 are in neither source (acronyms, names, brands) and are listed in the build report; the rules read them.
- **CMU vs Moby Pronunciator**: 642 shipped words put the primary stress on another syllable (CMU kept; listed in the build report). Over every word both know, 5.2% of comparable words differ: mostly noun/verb homographs (address, content, export), names, and Moby's own slips.
- **Moby Hyphenator is read but not used for the shipped build (Chris agreed).** Its splits are typographic, not phonetic: of the 13,058 shipped words it could split, 4,137 differ from the runtime's split, and in 3,419 of those a syllable loses its onset consonant (ac|cept|ed, nev|er, ab|i|gail against ac|cep|ted, ne|ver, a|bi|gail). The voices build each syllable from its onset, so the runtime-style split is kept; `--moby-hyph` still works. Its separator is Mac Roman 0xA5, a bullet (•) once decoded, not the yen sign the first reader assumed.
- **Held-out words are held out**: the fallback report measures the rules on the 2,000 most frequent multi-syllable words past the cut (75.5% right primary, against 75.4% on the old hash-picked CMU sample).
- Moby readings are kept for every casing a word has (Moby lists a foreign "canada" beside "Canada"); a word is a disagreement only if no reading matches CMU.

## Phase 5 (this branch, built): markup

1. `AKSpeechMarkup.parse` turns the source text into the subtitle text and marks with positions; `apply` puts them on the analysed words (`emphasis`, `contour`, `stretch`, `pause_after`, `state`). `\*` and friends escape a mark.
2. Prosody: `*word*` at least a strong accent (an accented function word is spoken as a content word); `**word**` the strongest accent, clipped to 85%, with the "shout" state's loudness and brightness, through its patch if it has one; `^` / `_` a rise or fall of 0.6 x the range across the word, let go over 0.2 s; `~` stretches the last syllable by 60% a tilde; `/` adds 0.18 s; escalation still multiplies on top.
3. `{tag}` voice states: built-in whisper, shout, excited, sad, fast, slow, high, low (pitch, range, tempo, intensity, brightness); `AKSpeechVoice.states` adds or overrides them and can give a state its own patch. Lines render once per patch they use and mix.
4. Unclosed marks and unknown states play anyway and are listed in `AKSpeechLine.warnings`.

## Phase 6 (this branch, built): curves and per-word audition

`AKSpeechCurves` under the waveform on the Pseudo-Speech page, on the same time axis: word bands with their text, syllable ticks, accent dots sized by stress, and the pitch (around the base, range dashed), intensity, brightness, formant and noise curves, each switchable; a playhead. Clicking a word plays it cut from the rendered line (its place in the melody kept, a 4 ms fade at the cut).

## Phase 7 (this branch, built): the speaker, live and baked

`AKSpeaker` (a Node): `say(text)` compiles a line and plays it live (notes and controller moves scheduled on an `AKSynthStream` 50 ms ahead, one stream per patch the line uses, onsets pre-rendered beside it) or baked (rendered whole, cached by key). Signals `line_started`, `word_started(index, word)`, `syllable_started`, `line_finished` from the syllable timings against the heard position (latency taken off); `mouth()` and `intensity()` for animation; `set_manual` / `update(t)` for an outside clock. Demo: `demo/speech/speech_demo.tscn`.

The doc's open question, settled by measuring (native core): live costs 0.2-1.1% of a core per speaker (Blip to Drone Priest) and bakes take 19-116 ms per line, so both are cheap with the native core. Default: `auto` (live where possible). The doc's "try both and decide" leans live for typed and procedural lines and baked for shipped dialogue that must match a reviewed render.

## Phase 8 (this branch, built): motion kit hook

`AKSpeaker.silent` (signals and mouth from the line's clock, no sound) and `AKCueBridge.speaker`: speech cues (recipes using the `speech` voice) make the speaker speak in EVENTS mode, or follow silently in BAKED and LIVE modes where the line is already in the mix. Tested with a stand-in cue object and with the real motion kit (a `MotionComposition` firing a speech cue in EVENTS and BAKED modes). Demo video: `demo/with_motion_kit/speech_scene.tscn` ("The Haircut"), two characters in two voices.

## Decisions taken in phase 1

- wh-question words (where, what, who ...) are content words: they carry the accent in a question. out, up, down, off, back and away are content words too: in dialogue they are mostly stressed particles ("get out").
- Compounds (hair + cut) need the dictionary; until then the two-syllable rule gives the same answer for most.
- Among neutral suffixes, one that uncovers a stress-placing suffix wins (employees → employee → -ee).

## Follow-ups (branch `stress-dict`, built)

- **Scratch King's vowels**: a `vowel` voice (a differenced saw and breath through three formant resonators in series, nothing bypassing them) and five recipes in `speech/vowels/`, sung at the voice's base note (E4) so the record plays near its own speed at rest. The vowels are 10.7 dB apart on average in third-octave spectrum (3.7 dB with the `reed` vowels); in a scratched line "mee" and "moo" are 26 dB apart at 1.8-3.5 kHz (1.5 dB before). The old centroid test was a poor proxy (a real ee has a low centroid: its first formant dominates), so the test now measures the second-formant band and the records' spacing. A recorded set is still an option.
- **Live switch** on the Pseudo-Speech page: plays through an `AKSpeaker` in live mode (now `@tool`, so it runs in the editor), then bakes for the waveform and curves. Needs the native core and a patch voice; otherwise it plays baked and says so.
- **Slow voices**: a voice whose last bake took over 1.5 s doesn't replay on every edit (the status says to press Play), and Play plays an unchanged line's bake again instead of baking it twice. Baking in a background thread was left out: the kit's render caches (`AK._mem`, wavetables) are shared static dictionaries, unsafe to touch from two threads.
- **Consonants, after Chris heard a high scratchy noise on every voice but Blip** (the only one without onsets): h had the same hiss as s, and the `static` hiss's broad band sprayed energy above 8 kHz. Now h is its own onset class (`BREATH`, a final h silent) with a soft dark `breath` recipe, the `static` voice has a 24 dB/octave `lowpass_hz`, and the hisses are 4 dB quieter. Above 8 kHz the full voices now measure close to their synths alone (Drone Priest −63 dB, was −32; Scratch King −35, was −20; Critter −23, was −17; Hollow −20, was −15).
- **Drone Priest's click**: two bugs in the synth's mono/legato voice (GDScript and C++ alike). A note arriving while the last one was still releasing restarted the voice from zero, cutting the tail in one sample; it now carries on from where it is. And a legato note's velocity changed the level in one sample; it now glides over 4 ms (`VEL_GLIDE_S`). The worst click burst went from 26 dB above its surroundings to 9 (the measurement's floor).
- **The noise curve's clicks and spikes** (heard on Hollow most): the curve itself drives nothing, it marks where the onset sounds go, and those were out of balance. Hollow's plosives peaked 10.5 dB over the voice (the "t" of "Get" was the line's peak) and its hiss was as loud as the voice; every plosive rose in 0.3 ms. Now every preset's plosives peak about 2 dB over the voice, hisses sit 11 to 13 dB under it and breaths lower still, and the click voice has an `attack_s` (1.5 ms for the bright plosives, 3 ms for the dark ones). And the synth's mod wheel and aftertouch, which speech steps every 5 ms (brightness jumps at every fricative), now glide over 6 ms per voice (`CTL_GLIDE_S`, both engines): a step in cutoff or FM depth was a crackle, on Critter (aftertouch to FM) most.
- **Plosives rebuilt, and a ceiling**: a plosive was a 10 to 20 ms burst of filtered noise, which comes out as a few big random spikes, and after a pause it sat alone in the gap before the vowel faded in: a click, worse with the Consonants slider up. Now it's a short release tick (2 to 4 ms) then aspiration, a breathy hiss in the voice's colour (`ASPIRATION_S`, 60 ms, fading out) that is still sounding when the vowel starts, as in speech. Every preset: tick 2 dB under the voice, aspiration 14 under. And loud consonants can't clip: `AKSpeech.render` limits a line that would go over `CEILING_DB` (-1 dBFS), and a live speaker limits its consonants the same way; a line that stays under is untouched. The static voice gained `fade_out_s`.

## Next

- **Stress rules tuned** (Chris's go-ahead). Tuned on 8,575 words well past the dictionary's cut (none in `held_out.txt`), then checked once on the held-out words: rules alone 75.5% → 81.1% right primary, and the path a game takes for a word the dictionary lacks (a dictionary stem + suffix, a compound, the rules) 80.8% → 85.1%. What changed: words of three or more syllables ending in a, o, i, u take the penult (mostly borrowings: bodega, kimono; 86% right); the heavy-penult rule went (once those were out it was right 22% of the time: the rest are front-stressed names and compounds, hoskinson, hungerford), so the antepenult takes them; -ary / -ory / -ery put it one further back (formulary); the verb-like prefix counts only when it is the whole first syllable (re·TURN, not BEL·low); a compound's vowel-initial second part is a borrowing cut in two (kim + ono), and after a prefix-like first part (dis, non, pre, sub, inter, anti ...) the second part keeps the primary (dis·em·BARK). Tried and dropped: two consonants after the penult making it heavy (no gain), a Latin prefix passing the stress on (44% right), dropping -ee (noise). On the plays the dictionary already covers almost every word: wrong primary 1.0% → 0.9% (Pygmalion), 0.4% (Earnest).
