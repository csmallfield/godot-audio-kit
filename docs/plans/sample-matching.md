# Sample matching: process log

Turning a recording of an instrument into an `AKPatch`. Five trials so far (2026-11-01), all scale exports (`.axbw`) of the same three-scene MIDI. This log records what worked, what didn't, and what the importer needs.

Scripts: `tools/sample_match/` (Python with numpy and scipy, plus Godot scripts that render through the kit's engine). Recording guide for users: `docs/sample_matching.md`.

## Input

An `.axbw` is a zip:

- `stem_0.wav`: the audio, 16-bit stereo, 44.1 kHz, 96 s.
- `loop_0_0.mid` … `loop_0_2.mid`: the notes of each 32-second scene (60 BPM, so beats are seconds; scene N starts at N × 32 s).
- `manifest.json`: the title, BPM and instrument label.

The scenes:

1. A chromatic run from note 102 down to 43, each held ¼ s, ½ s apart.
2. 1 s holds on C7–C3, repeated notes, and an octave arpeggio.
3. Velocity 127 against 64 at several lengths, then fast repeats.

The audio lines up with the MIDI to the millisecond, so no onset detection is needed. That's the biggest win of a MIDI-plus-stem export over a bare WAV.

## Pipeline

1. **Unpack and align.** Note times come from the MIDI; the stem is cut per note.
2. **Clean.** High-pass at 15 Hz first. Panda carried a slowly decaying DC drift (around 2 Hz) after every note, and it skewed every loudness figure until removed.
3. **Analyze** (`analyze.py <dir>`): a report on:
   - the transposition;
   - each note's tuning, level, harmonics, noise and brightness;
   - key-zone detection;
   - the envelope on the 1 s holds;
   - brightness and pitch over a held note;
   - tremolo;
   - velocity's effect on level and brightness;
   - tails after release;
   - stereo width.
4. **Measure directly** what the search can't see (`probe.py`): unison detune and per-voice levels from the fine spectrum around the first harmonics, left against right, the tail's structure, and noise between harmonics.
5. **Search** (`search.py <dir> <transpose> <out> [gens] [seed]`):
   - Build a probe timeline of 24 notes: the holds, the velocity pair, and every sixth note of the chromatic run.
   - Try a grid of oscillator stacks.
   - Run a (1+23) evolution strategy over about 35 parameters: two oscillators (shape, interval, level, cents, pan), unison (count, detune, side level, spread), a ladder filter, filter envelope, key tracking, velocity → cutoff, the amp envelope, velocity sensitivity and curve, noise, poly or mono, glide, vibrato, tremolo, chorus and reverb. Everything past the first set starts switched off.
   - A seed file sets the starting point; `nogrid` as the sixth argument skips the grid so the seed's oscillators are kept.
   - Each generation is one Godot run rendering 23 candidates, about 10 s on the native core.
   - The score is the mean absolute dB difference of third-octave band energy over time (10 ms frames, 60 dB floor), with the level matched by total energy.
6. **Fix by hand** what the measure misses, checked with `score.py`: detune and voice levels, and stereo width, set by matching the original's left/right correlation over the whole file.
7. **Render** the whole MIDI through the patch and make an A/B clip.

## Results

| Sound | What it is | Patch found | Score (dB) |
| --- | --- | --- | --- |
| Fat Basset | Sampled: 10 key zones, each a pitch-shifted recording | Saw −24 st, ladder 300 Hz res 0.25, A 4 ms / S 1 / R 3 ms, velocity squared | 8.1 (search) / 9.2 (hand) |
| Flag | Continuous, detuned, wide | Saw −36 st + pulse (w 0.45) +12 st at ½; ladder 1.5 kHz, velocity → cutoff 0.7; decay 0.7 s to 0.12, release 1.1 s; voices at ±28 cents, 17 dB down | 7.6 |
| Panda | Mono pluck | Saw −36 st + pulse (w 0.35) +12 st −20 cents; ladder 130 Hz with a 5-octave filter envelope decaying 0.15 s; amp decay 0.3 s to 0.03; mono, rings until the next note | 9.9 |
| Avenue | Wide, decaying, an octave down | Saw −12 st + a quiet square +19 st (the strong 3rd harmonic); unison 3 at 25 cents, spread 1; mono, decay 0.5 s to 0, velocity curve 1.7, a slow 1 Hz tremolo | 8.0 |
| Apollo | At pitch, two beating layers, reverb | Square + saw −43 cents (beating about 6.6 Hz at middle C) with the saw panned −0.5; filter at 800 Hz tracking the keyboard, velocity → cutoff; mono; reverb room 0.71, mix 0.36 | 6.6 |

Avenue and Apollo were fitted after the new engine features went in, with no hand work beyond the width. Bass-range harmonics on Fat Basset match to about 1–2 dB. Most of what's left in each score is behaviour the patch can't copy: Fat Basset's zone jumps, and Flag's and Panda's beating.

## Lessons

- **Find the transposition first.** Fat Basset, Flag and Panda sound two or three octaves below the MIDI note, Avenue one, Apollo none. Choose the lowest offset whose fundamental is consistently present, within 30 dB of the strongest peak. The first version picked by "strongest peak" and was fooled by overtones; a 20 dB threshold then missed Avenue's weak fundamental.
- **Beating isn't vibrato.** Apollo's analysis showed a 5.4 Hz "wobble" and pitch scoops of up to a semitone, which looked like vibrato and glide. The search found two layers 43 cents apart instead, and the beating between them explains both. Report wobble as "beating or vibrato" and let the search decide.
- **Every sound so far wants mono.** Panda, Avenue and Apollo all fitted best in mono with a long release: they ring until the next note. Try mono early.
- **Width is its own measurement.** The search set `spread` on Avenue but left unison at 1, so it did nothing, and the patch came out mono against a very wide original (correlation 0.38). Match the left/right correlation after the search, with unison, spread and oscillator pan.
- **Detect sampled instruments.** Identical harmonic ratios across 3+ neighbouring notes, with jumps between them, mean key zones. Then fit the range people will play, and expect a leftover error.
- **Some features have to be measured, not searched.** Band energy can't see detune and beating; scores moved under 0.1 dB with unison on or off. Read detune, voice levels and stereo width straight from the fine spectrum and set them.
- **Test voice behaviour.** Panda's fast repeats piled up in poly mode with a long release: peaks went 8 dB over the original. Mono fixed it with no loss in score. The importer should try poly against mono, and "rings until the next note" against "stops at note-off", using the repeated-note passages.
- **Peak against energy.** Matching by energy can still leave peaks far off. Check peak level and crest factor too. Apollo's match peaks 5 dB under the original (a sharper attack there), Panda's in poly went 8 dB over.
- **Window lengths must follow pitch.** At 16–65 Hz, 2 ms windows measure the waveform, not the envelope. Use at least two periods.
- **Weigh the registers.** An unweighted score across the keyboard trades bass accuracy for high-note level, which is wrong for a bass. Weight by the instrument's register. A recording-guide range of C2–C6 may be enough.
- **The search gets stuck at the ends of its ranges.** Panda's filter envelope sat at 6 octaves until the range was widened, and the grid stage overrode the seed's oscillators. Widen ranges when a value sits at a limit, and let a seed skip the grid.
- **Values left at defaults.** The amp `decay_s` (Fat Basset, sustain 1) and `width` on saws have no effect; the importer should drop unused values.

## Engine features these sounds asked for

Items 1–3 are now in the engine (2026-11-01, GDScript and native, held to the same samples by `test_side_voices_pan_and_velocity_curve`): `velocity_curve`, `unison_level` and an oscillator `pan`. The matched patches use them. Fat Basset's velocity curve scores exactly what the matrix workaround did. Flag gets three-voice unison (±28.5 cents, side voices 0.25, spread 1) with its octave layer panned 0.5. That frees two oscillator slots and matches the original's width (left/right correlation 0.80 against 0.83; the old version was mono).

1. **Velocity curve** (Fat Basset): 127 against 64 was 12 dB, a squared curve. `velocity_sens` tops out at linear (6 dB). Workaround: velocity → amp +1 and env1 → amp −1, which is squared only while sustaining. A `velocity_curve` exponent would do it properly.
2. **Unison side-voice level** (Flag): side voices about 17 dB below the center. Unison voices are equal. Workaround: two extra oscillators at ±28 cents, which uses up all four slots.
3. **Per-oscillator pan, or unison voices panned differently** (Flag): the left and right channels hold different detuned voices (L/R correlation 0.83–0.91, with a mono tail). `spread` only pans unison stacks, which are equal level.
4. **A DC blocker or high-pass** after the voice (Panda): the original had DC drift, so it's not needed for matching. Our own patches might use one where saturation or asymmetry adds DC.

Each would need tests holding the GDScript and native engines to the same samples.

## Importer: a suggested shape

- **In Sound Lab:** "Match a recording" on the Synth page. Pick an `.axbw` (or a WAV plus MIDI, or a WAV recorded to the recording guide's timing), see the analysis summary, run the fit (a progress bar, about 3–5 minutes), then A/B the original against the match. The result opens as a patch to edit and save.
- **Where the code runs:** the analysis and search would need porting from Python to GDScript, or to the native core for speed. Rendering is already the engine's own; the FFT and band energy are the main new pieces. Running the Python tools from the editor isn't an option for users without Python.
- **Stages,** as above:
  1. align;
  2. clean;
  3. measure the transposition, zones, detune, width and voice mode;
  4. search the rest;
  5. check peak and crest;
  6. report what couldn't be matched ("sampled instrument: zone jumps", "uses effects the patch can't copy").
