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

## In a game: AKSpeaker

```gdscript
var speaker := AKSpeaker.new()
speaker.voice = load("res://addons/audio_kit/speech/voices/critter.tres")
add_child(speaker)
speaker.word_started.connect(func(index, word): subtitle.highlight(index))
speaker.line_finished.connect(func(_line): subtitle.hide())
speaker.say("Hey! Where did you come *from*?")
# every frame:
mouth.scale.y = 0.2 + speaker.mouth()      # open while a syllable sounds, shut in the gaps
glow.energy = speaker.intensity()          # the line's intensity curve
```

| Signal | When |
| --- | --- |
| `line_started(line)` | `say()` started a line |
| `word_started(index, word)` | a word is heard (index into `line.words`, its text as written) |
| `syllable_started(index)` | a syllable is heard (index into `line.events`) |
| `line_finished(line)` | the last syllable ended (not sent when a new `say()` or `stop()` interrupts) |

Signals follow what's heard: the playback position less the audio output's latency. `set_manual(true)` and `update(t)` drive them from your own clock instead (a timeline, a cutscene, a test).

**Live or baked** (`mode`). `live` schedules the line's notes on an `AKSynthStream` (the native core's synth) 50 ms ahead (`live_lead_s`), so a line starts at once however long it is: typed text, barks, chat bubbles; its consonants are rendered (no synth, a few ms) and started beside it. `baked` renders the whole line and plays it, cached by text and voice (`cache_size` lines). `auto` (the default) is live when the native core is there and the voice uses a patch, baked otherwise; Scratch King always bakes. Live and baked play the same engine: the tests hold a live line to its bake at better than 90 dB.

**Cost** (native core, the test line, this build machine): live synthesis takes 0.2% of a core for Blip, 0.3% for Hollow, 0.5% for Critter and 1.1% for Drone Priest, per speaker; baking the line takes 19, 33, 51 and 116 ms (Scratch King: 280 ms, GDScript). Without the native core everything bakes in GDScript, about 100 times slower: 1 to 10 s a line.

`player` takes an `AudioStreamPlayer2D` or `3D` for positional speech (live lines with a second patch, from a voice state, play it on an extra non-positional player). `bus` and `volume_db` as usual.

**Signals only.** `silent = true`: `say()` runs the line's clock, signals and `mouth()` without playing anything, for a line whose sound is already in a mix.

**With the motion kit.** Put speech in the cue map as `speech` recipes and give the `AKCueBridge` a `speaker`: in EVENTS mode the speaker says each speech cue itself (live where it can), with its signals; in BAKED and LIVE modes the line is baked into the track and the speaker follows it silently, so a title card's subtitle and a character's mouth stay with the sound.

A worked example: `demo/with_motion_kit/speech_scene.tscn` ("The Haircut"), two characters arguing in two voices, scored by an `AKCueBridge` whose cue map holds the lines as `speech` recipes. The picture reads the same compiled lines for mouths, accents, head tilt and the word-lit subtitle, so it can't drift from the sound. Under it, a music bed (an `AKSong` built in the scene from library sounds) whose sections are cut where the lines change, sidechained gently under the speech with the cue map's `duck` (6 dB, full at −36 dBFS, a 0.6 s release so it doesn't pump between words) on a bed kept low: speech sits 7–9 dB above the music while lines play, and the bed comes back up between them. Render it with the motion kit's `tools/render.sh`.

Demo: `demo/speech/speech_demo.tscn` (type a line, pick a voice; a face mouths it and a subtitle follows).

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

## Markup

Writers can override what the text implies, inline. The subtitle (`line.display_text`, and the page's subtitle) shows the text without the marks.

| Mark | Example | Effect |
| --- | --- | --- |
| `*word*` | `that *stupid* haircut` | at least a strong accent: pitch, volume and brightness up. An accented function word (`*my* hat`) is spoken as a content word |
| `**word**` | `**GET OUT**` | the strongest accent, clipped, shouted: the "shout" state's loudness and brightness, through its patch if the voice gives it one |
| `^word` | `^really` | a rise across the word, whatever the clause |
| `_word` | `_no` | a fall across the word |
| `word~` | `heyyy~~` | the last syllable 60% longer per tilde |
| `/` | `wait / what` | a short pause (0.18 s at tempo 1) |
| `{tag}` | `{whisper} come here` | a voice state until the next tag or the line's end; `{normal}` or `{}` goes back |
| `\*` | `5 \* 3` | the character itself |

Spans can cover several words (`**GET OUT**`). A repeated word's escalation still applies under markup, so `stupid *stupid*` lands harder than either alone.

**Voice states.** Built in: `whisper` (quiet, flat, darker), `shout` (loud, higher, wider, brighter), `excited`, `sad`, `fast`, `slow`, `high`, `low`; each is a few numbers: `pitch` (semitones), `range` (x), `tempo` (x), `intensity` (x), `brightness` (+). A voice's `states` dictionary adds its own or overrides these, and a state can bring its own `patch` (an AKPatch or its path), so `{growl}` can switch to a rougher sound and a voice's `shout` patch speaks every `**word**`:

```gdscript
voice.states = {"shout": {patch = load("res://audio/patches/blip_shout.tres")}, "growl": {pitch = -6.0, range = 0.5}}
```

A line with an unclosed `*` or an unknown `{state}` still plays (the accent runs to the end; the state plays as normal); `line.warnings` lists the problems.

## Where stress comes from

For each word, in order (`AKSpeechText.read_word`; the source is on every analysed word as `source`):

1. **The project's lexicon**, `res://audio/speech/lexicon.tres` (an `AKSpeechLexicon`): your own pronunciations, mostly invented names. One word a line, as in the dictionary: `zorblax zor|blax 10` (the split, then a stress digit per syllable: 1 primary, 2 secondary, 0 none), or `zorblax 10` to keep the kit's own split. Lines that don't parse are listed by `bad_lines()`.
2. **The stress dictionary**: about 116,000 English words from the CMU Pronouncing Dictionary (`addons/audio_kit/speech/data/en_stress.txt`, one word a line, packed into `en_stress.res`). Homographs keep CMU's first reading (record is the verb, re·CORD); the lexicon or, later, markup fixes the rest.
3. **A known stem with a neutral suffix**: zorblax-es, stopp-ing, glorp-ed take the stem's stress and leave the suffix unstressed.
4. **A compound of two known words**: hair + brushes is HAIR·bru·shes, the second part's primary stress made secondary.
5. **The rules** (as before). How good they are is measured in `docs/stress/fallback_report.md`.

The analysis on the Pseudo-Speech page marks words whose stress the rules guessed with `(?)`: those are the ones to put in the lexicon.

**Rebuilding the dictionary.** `python3 tools/build_stress_dict.py` downloads CMUdict and writes `en_stress.txt` and `docs/stress/build_report.md`; `godot --headless --path . -s res://addons/audio_kit/tools/make_stress_dict.gd` packs it; `-s res://addons/audio_kit/tools/stress_report.gd` re-measures the rules. With a word-frequency list (`--freq file --top 20000`) only the most frequent forms ship, which shrinks the files; with Moby Hyphenator (`--moby-hyph mhyph.txt`) its spelling splits are used where they agree with CMU.

The dictionary costs about 3.6 MB of memory once loaded (on first use) and a lookup takes about 30 µs in GDScript.

## Voices

An `AKSpeechVoice` is one character: `salt` (two voices with different salts say the same word differently), `patch`, `base_note` (MIDI), `range_semitones`, `tempo`, `syllable_s`, `gate` (how much of a syllable sounds), `jitter`, `seed_pitch_semitones` and `seed_time` (how much a word's seed shapes it), `pause_scale`, `gain_db`. The kit's are in `addons/audio_kit/speech/voices/` (written by `tools/make_speech_voices.gd` from `AKSpeech.preset_voice`); the page also lists yours from `res://audio/speech/voices/`.

| Voice | Patch | Character |
| --- | --- | --- |
| `blip` | `speech_blip`: a square blip per syllable, mono | Undertale-style UI talk, pitch only, no onsets |
| `critter` | `speech_critter`: a squeaky pulse with a little FM; mod wheel sweeps the filter, aftertouch adds FM edge | Cute and quick, Animalese-adjacent: high, fast, a wide melody, tiny clicks and hisses |
| `hollow` | `speech_hollow`: noise through one formant band, a faint sine under it; mod wheel moves the band | Whispered and unsettling, almost no pitch, breathy onsets |
| `drone_priest` | `speech_drone`: low detuned saws and a sub through a resonant ladder, legato; mod wheel opens it | Ominous chant: low, slow, long pauses, thumped plosives. Put it on a bus with a big reverb |
| `scratch_king` | no patch: source `scratch`, the kit's sung vowels (`vox_ee` .. `vox_oo`) scrubbed like a record | The Katamari King: warbling record scratches, a back stroke on accents, needle clicks and vinyl crackle |

The test line ("Hey! Where did you come from? ...") runs about 2.3 s in Critter, 3.1 s in Scratch King, 3.2 s in Blip, 4.7 s in Hollow and 8 s in Drone Priest, each peaking between −4 and −1 dBFS.

**Scratch voices.** A voice with `source = "scratch"` has no patch: each syllable scrubs one of its `scratch_samples` (sustained vowel sounds, bright to dark: i, e, a, o, u) under a virtual needle (`AKSpeechScratch`).

| What | How |
| --- | --- |
| formant | the syllable's vowel picks the record; the formant and brightness curves also open a low-pass |
| pitch | the playback rate: a record plays at its `root_note` when the pitch curve is there |
| the hand | `scratch_wobble`: the speed swings from slow at a stroke's ends to fast in its middle (the warble), keeping the stroke's average on the curve |
| accents | syllables with at least `scratch_back_stress` end with a back stroke (`scratch_back` of the syllable, pulled backwards) |
| word identity | where the needle lands comes from the syllable's seed, so a word scratches the same groove every time |
| level | a crossfader cut (`scratch_cut_s`) at each end, the intensity curve in between |

Any AKSample works as a record: the kit's vocal sounds, a recipe, or a recording of your own (a held "ahh" is the classic).

**Making a patch speak.** Any `AKPatch` can be a voice's patch. It hears the line as:

| Input | Arrives as | Typical use in the patch |
| --- | --- | --- |
| gate | a note per syllable, held `gate` of its length | the amp envelope |
| pitch | the note (fractional MIDI) at the syllable's accent, then pitch bend for the rest of the curve | set `bend_range` wide (12) |
| intensity | velocity | `velocity_sens`, velocity → cutoff |
| formant | mod wheel, 0 (u, dark) .. 1 (i, bright), glided | mod_wheel → cutoff (a wah), or → a vowel table's position |
| brightness | aftertouch, 0..1 | aftertouch → cutoff |

Use `mode = "mono"` so each syllable restarts the envelopes (or `legato` with a little glide for a sung, joined line, as Drone Priest does).

**Onsets.** Consonants are separate sounds, mixed in at the syllable's start: `plosive` (a recipe played where a syllable starts with p, t, k, b, d, g ...) and `fricative` (one played where it starts with s, sh, f, h, z, th ...), and, with `coda_fricatives`, a quieter hiss where a syllable ends in one (haircuts). They are ordinary recipes, so any voice in the kit can make them (the presets use `click` for plosives and `static` for hiss). The vowel's note starts `plosive_lead_s` or `fricative_lead_s` after the syllable's start, so the hiss runs before the vowel the way it does in speech; a syllable's timing and subtitle don't move. Each onset's level follows the syllable's intensity, times `onset_gain_db`. A recipe's `vary` gives each word its own version of its consonants, picked by the syllable's seed, so a word keeps them every time it's said (`AKSpeech.onsets_for(line)` lists them). A voice without onset recipes, like Blip, is just the patch.

## Limits

- English-shaped text only. Words outside the dictionary and lexicon get the rules' guess (about three in four right).
- Scratch voices bake only.
- No curve display yet.
- The kit's sung vowels differ less from each other than real voices do, so Scratch King's vowels are subtle; a recorded "ahh / ee / oo" set makes them clearer.
- Reverb, distortion and radio belong on a Godot bus, as everywhere in the kit; the page plays the dry voice.
- Drone Priest takes about 10 s to render the test line in GDScript (three oscillators and a chorus for 8 s of speech); the native core makes it a fraction of a second.
