# Pseudo-speech

Turn a line of dialogue into a gibberish voice whose rhythm, stress and melody follow the text, timed for subtitles: Katamari's King, Animalese, Undertale's blips. A word always sounds the same in a voice, so the gibberish reads as a language.

```gdscript
var voice: AKSpeechVoice = load("res://addons/audio_kit/speech/voices/blip.tres")
var line := AKSpeechLine.make("Hey! Where did you come from?", voice)
var buf := AKSpeech.render(line)            # AKBuffer; compiles the line first
$Player.stream = buf.to_stream()
$Player.play()
# Subtitles: the word being spoken at a time.
var w := line.word_at($Player.get_playback_position())   # index into line.words, or -1

# As a recipe (cue maps, recipe streams, bakes cached by text and voice):
var r := AKRecipe.make(&"speech", {text = "Hey!", voice = "res://addons/audio_kit/speech/voices/blip.tres"})
```

In the editor, the Sound Lab's **Pseudo-Speech** page does the same: type a line, pick a voice, Play. The subtitle under it lights each word as it's spoken, and the analysis shows how the text was read (syllables split with `·`, stressed ones in capitals).

## How a line is read

1. **Words and syllables** (`AKSpeechText`). Letters only (accents folded: é → e), split into syllables by vowel groups; a silent final e and the swallowed e of -es / -ed don't count. Each word is a function word (the, of, you, did ... about 170 closed-class words, never stressed) or a content word. Stress comes from rules: neutral suffixes (-s, -ed, -ing, -ness ...) are stripped, stress-shifting suffixes place it (-ee, -eer stressed; -tion, -ic, -ity the syllable before; -ate, -ize two before), two-syllable words stress the first unless they start like a verb (be-, re-, de-, con-, ex-, pre-), longer words the penult if heavy, else the antepenult. A stress dictionary comes later.
2. **Prosody** (`AKSpeechProsody`). Each clause gets a phrase shape from its end mark, and stressed syllables get accent bumps on top, summed in semitones:

| End mark | Shape | Last syllable |
| --- | --- | --- |
| `.` | gentle fall, falls at the end | low, lengthened |
| `?` | flat, then a high rise from the last stressed syllable | longer |
| `!` | high start, steep fall | loud, short, bright |
| `, ; :` | partial fall, held up | slight rise, short pause |
| `…` (or `...`) | slow fall, slowing down | trails off, quieter |

   The first content word of a clause is accented strongly, the last stressed syllable carries the clause's final tone, a one-word exclamation ("Hey!") gets the strongest accent clipped short, function words are short and quiet, and a content word repeated in its clause gets stronger and higher each time ("stupid stupid"). Each word's seed (its letters and the voice's salt) gives its syllables a small melody and timing of their own; function words pick one of four variants per occurrence so they don't drone.
3. **The voice** speaks the result through its patch.

The compiled line has `events` (a dictionary per syllable: `t_start`, `t_end`, `word_index`, `syllable_index`, `seed`, `onset_class`, `coda_class`, `vowel`, `stress` 0..1, `pitch` in semitones from the voice's base, `velocity`) and `curves` (`pitch`, `intensity`, `brightness`, `noise`, `formant`, as `PackedFloat32Array` at `curve_rate` samples a second). Only `source_text` and `voice` are saved; the rest compiles again on load, the same every time.

## Voices

An `AKSpeechVoice` is one character: `salt` (two voices with different salts say the same word differently), `patch`, `base_note` (MIDI), `range_semitones`, `tempo`, `syllable_s`, `gate` (how much of a syllable sounds), `jitter`, `seed_pitch_semitones` and `seed_time` (how much a word's seed shapes it), `pause_scale`, `gain_db`. The kit's are in `addons/audio_kit/speech/voices/` (written by `tools/make_speech_voices.gd` from `AKSpeech.preset_voice`); the page also lists yours from `res://audio/speech/voices/`.

| Voice | Patch | Character |
| --- | --- | --- |
| `blip` | `speech_blip`: a square blip per syllable, mono | Undertale-style UI talk, pitch only |

**Making a patch speak.** Any `AKPatch` can be a voice's patch. It hears the line as:

| Input | Arrives as | Typical use in the patch |
| --- | --- | --- |
| gate | a note per syllable, held `gate` of its length | the amp envelope |
| pitch | the note (fractional MIDI) at the syllable's accent, then pitch bend for the rest of the curve | set `bend_range` wide (12) |
| intensity | velocity | `velocity_sens`, velocity → cutoff |
| formant | mod wheel, 0 (u, dark) .. 1 (i, bright), glided | mod_wheel → cutoff (a wah), or → a vowel table's position |
| brightness | aftertouch, 0..1 | aftertouch → cutoff |

Use `mode = "mono"` so each syllable restarts the envelopes. Noise and onset class are in the curves and events but not sent to the patch yet.

## Limits

- English-shaped text only; stress from rules, so some words are wrong (banana is BA-nana). Markup to fix them comes next.
- Baked only; the line renders in about a second in GDScript, much faster with the native core.
- No markup, no curve display, one voice.
