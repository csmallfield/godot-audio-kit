# Sample matching: process log

Turning a recording of an instrument into an `AKPatch`. Nine sounds so far (2026-11-01), all scale exports (`.axbw`) of the same three-scene MIDI. This log records what worked, what didn't, and what the importer needs.

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

Version 2 (2026-11-01, after listening): **resynthesis**. The first version fitted a subtractive patch (oscillators, filter, envelopes, effects) by search, scored on third-octave band energy. Played back, none of the nine sounded close, and the waveforms showed why (see Lessons). Version 2 takes the sound's cycles straight from the recording.

1. **Unpack and align.** Note times come from the MIDI; a loop shorter than its 32-beat scene repeats to fill it (scene 3's is 16 beats, played twice).
2. **Clean.** High-pass at 15 Hz (Panda carried a slow DC drift).
3. **Find the transposition** (`analyze.py`): the lowest octave offset whose fundamental is within 30 dB of the strongest peak.
4. **Build the table** (`resynth.py <dir> <transpose> <out.json> [frames] [zone step]`):
   - A zone every 3 semitones along the chromatic run, plus the five held notes.
   - Per zone, 16 frames (24 for Spiral and Apollo): the complex amplitude of every harmonic up to 18 kHz (at most 511), measured by heterodyning over 2 periods (at least 6 ms) at points through the note. Every frame is turned so the fundamental's phase is 0, so the frames line up and morph cleanly.
   - Frame times follow the position curve 0.5 × (1 − e^(−t/0.08)) + 0.5 × t/1 s, made by env2 (exponential) and env3 (linear) on `osc.position`: dense in the attack, even later. Both envelopes hold through the release, so position stops when the key is let go.
   - A run note gives the first 0.2 s; later frames come from the nearest held note, scaled to meet it, with the run note's phases.
   - `normalize = false`: frames keep their levels, so the table carries the decay and the level across the keyboard. `blend = false`: the nearest zone plays (blending zones whose phases differ thinned the sound by up to 5 dB between zones).
   - Wide sounds (left/right correlation under 0.95) get a table per side, panned hard.
   - Measured: tuning (median cents), release (time constant after note-off), velocity curve (127 against 64).
5. **What a table can't hold:**
   - Bursts of noise (`add_bursts.py`, Spiral): a noise oscillator gated by a square LFO whose rate the amp envelope pulls down. The frames are scaled to cancel the amp envelope's own decay.
   - Effects (`fx_fit.py`, Apollo): a search over chorus, reverb and release on top of the table.
6. **Level** (`finalize.py`): `gain_db` from the energy over the probe notes.
7. **Check** (`check.py`, `motion.py`, `floor.py`):
   - the harmonic score over every note of the whole file;
   - movement inside held notes, and the left/right correlation;
   - the floor: the original against itself (scene 3's two identical passes), which is the best any copy can score when voices run free.

The harmonic score (`fitlib.hfeats`, `hloss`) compares each harmonic's level over time (10 ms frames, windows of 4 periods, low harmonics weighted up), plus the noise between harmonics in four bands, with the level matched once.

## Results

Harmonic score over the whole file, in dB. Lower is closer. The floor is the original against itself.

| Sound | Version 1 (subtractive search) | Version 2 (resynthesis) | Floor | Width (L/R correlation) original / match |
| --- | --- | --- | --- | --- |
| Fat Basset | 7.7 | 2.7 | 0.0 | 1.00 / 1.00 |
| Stack | 23.4 | 3.7 | 0.0 | 1.00 / 1.00 |
| Panda | 12.7 | 6.7 | 4.6 | 0.98 / 1.00 |
| Avenue | 18.6 | 7.1 | 5.7 | 0.47 / 0.48 |
| Dread | 28.6 | 7.3 | 6.3 | 0.79 / 0.79 |
| Flag | 18.9 | 7.6 | 5.5 | 0.86 / 0.87 |
| Pixel | 12.7 | 7.6 | 5.0 | 0.26 / 0.37 |
| Apollo | 12.3 | 7.7 | 1.5 | 0.95 / 0.85 |
| Spiral | 27.8 | 11.4 | 6.3 | 0.75 / 0.77 |

The waveforms now line up cycle for cycle on held notes. Seven of nine are within 1–3 dB of their floor.

The two left:
- **Apollo:** its motion is a chorus or ensemble locked to the tempo, which is why its passes repeat exactly (floor 1.5). Neither the table nor the engine's chorus reproduces it closely; the chorus and reverb search moved the score only 0.1 dB.
- **Spiral:** its bursts are matched in time (within 8 ms) and level, but their noise and the tone between them still differ.

Memory: a zoned table is zones × frames × kept levels × 1024 floats. Stack (mono, 20 zones, 16 frames) is 6 MB. Flag (stereo, 16 Hz fundamental) is 12.5 MB and builds in about 6 s in GDScript. The importer should save the built table, or use fewer zones where neighbouring zones match.

## Lessons

- **Look at the waveforms and listen; a score isn't enough.** Version 1 scored 8–11 dB and sounded nothing like the originals. Overlaid cycles showed it straight away: a square where the original is a saw (Stack), a bright saw where the original is nearly a sine (Spiral's high notes), and noise and long tails that weren't there.
- **Band energy is blind to the things that make a timbre.** Third-octave bands can't tell odd harmonics from all of them, can't see a narrow pulse's spectral notches (Dread) or hard-sync peaks (Pixel), and read a noise layer as a fine way to fill a band. Compare harmonics.
- **A probe window must not hold notes the render doesn't play.** Version 1's slots ran 0.9 s past each fast chromatic note, so the originals held the next two notes; the search added noise, reverb and long releases to fill the gap. Slots now end at the next note.
- **Check the MIDI against the audio.** Scene 3's loop is 16 beats and plays twice; the second half was missing from every check.
- **Measure the floor.** Free-running detuned voices never repeat, so no copy scores 0. The original against itself says what's left to win.
- **Cycles straight from the recording beat a fitted model** for any sound that's mostly periodic: exact harmonics, phases, decay and level per key, with no search. The search is still the way to an editable, small patch (a filter to sweep, one oscillator to change); the resynthesis is the way to an exact one.
- **Don't blend zones whose phases differ.** The sum of two shapes with different harmonic phases partly cancels. Play the nearest zone, with zones close enough that the step isn't heard.
- **Keep left and right apart for wide sounds.** A table per side gives the original's width exactly (Avenue 0.47 → 0.48), with no chorus or detune to tune.
- **Some movement isn't in the tone.** A table taken from a chorused recording holds one moment of the chorus. Apollo's motion needs its effect found, not copied.
- **Everything below still holds for the subtractive search:** find the transposition first, beating isn't vibrato, strip what the search adds for nothing, measure width, detune and rhythm directly, weigh the registers.

## Engine features these sounds asked for

Version 2 asked for key-zoned wavetables (added 2026-11-01 in GDScript and native, `test_key_zoned_wavetables`): `zones` (frames per key), `normalize = false` (frames keep their levels) and `blend = false` (the nearest zone). Tables now store only the band limits they use. Building the test turned up a cache bug: a cached table lost `blend = false`.

Spiral asked for three more, added the same day (`test_lfo_rate_width_and_filter_bypass`): `lfo1.rate` and `lfo2.rate` as matrix destinations (octaves), a `width` for the square LFO, and `filtered = false` on an oscillator (around the filter, straight to the amp). Spiral's burst timing came from fitting the LFO's base rate, push and decay to the measured burst times (within 8 ms), then freezing them in the search.

Items 1–3 are now in the engine (2026-11-01, GDScript and native, held to the same samples by `test_side_voices_pan_and_velocity_curve`): `velocity_curve`, `unison_level` and an oscillator `pan`. The matched patches use them. Fat Basset's velocity curve scores exactly what the matrix workaround did. Flag gets three-voice unison (±28.5 cents, side voices 0.25, spread 1) with its octave layer panned 0.5. That frees two oscillator slots and matches the original's width (left/right correlation 0.80 against 0.83; the old version was mono).

1. **Velocity curve** (Fat Basset): 127 against 64 was 12 dB, a squared curve. `velocity_sens` tops out at linear (6 dB). Workaround: velocity → amp +1 and env1 → amp −1, which is squared only while sustaining. A `velocity_curve` exponent would do it properly.
2. **Unison side-voice level** (Flag): side voices about 17 dB below the center. Unison voices are equal. Workaround: two extra oscillators at ±28 cents, which uses up all four slots.
3. **Per-oscillator pan, or unison voices panned differently** (Flag): the left and right channels hold different detuned voices (L/R correlation 0.83–0.91, with a mono tail). `spread` only pans unison stacks, which are equal level.
4. **A DC blocker or high-pass** after the voice (Panda): the original had DC drift, so it's not needed for matching. Our own patches might use one where saturation or asymmetry adds DC.

Each would need tests holding the GDScript and native engines to the same samples.

## Importer: a suggested shape

- **In Sound Lab:** "Match a recording" on the Synth page. Pick an `.axbw` (or a WAV plus MIDI, or a WAV recorded to the recording guide's timing), see the analysis summary, run the fit (a progress bar, about 3–5 minutes), then A/B the original against the match. The result opens as a patch to edit and save.
- **Where the code runs:** the analysis and search would need porting from Python to GDScript, or to the native core for speed. Rendering is already the engine's own; the FFT and band energy are the main new pieces. Running the Python tools from the editor isn't an option for users without Python.
- **Stages,** as in version 2 above:
  1. align;
  2. clean;
  3. find the transposition;
  4. build the zoned table (stereo if wide);
  5. measure release, tuning and velocity;
  6. add bursts or effects where the check finds movement the table lacks;
  7. set the level;
  8. check against the floor and report what couldn't be matched ("tempo-locked chorus").
- **Offer both:** an exact resynthesis patch, and a small editable subtractive patch from the search (now scored on harmonics), side by side.
