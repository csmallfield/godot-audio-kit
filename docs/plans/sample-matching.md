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

## Lite versions

`lite_fit.py <dir> <transpose> full.json <center key> out.json [frames]` keeps one zone (key 72) for the whole keyboard and replaces the other zones with curves. On its own, that zone drifts fast: Basset is 4.6 dB off at its key and 16.5 dB three octaves away.

**Is the zone-to-zone difference a pattern?** `curves.py` fits the full patches' zones as the center zone plus a curve, by least squares on harmonic levels. Nearby zones differ by 2–5 dB of measurement noise, so that's the floor for any curve.
- A level per key plus one EQ curve fixed in Hz explains Basset (14.6 → 4.4 dB), Avenue (13.7 → 7.1) and Pixel.
- Stack, Panda and Spiral need the curve to move through the note: with a static curve they stay at 6–7 dB, with a moving one they drop to 3–5. That's a filter envelope.
- Flag, Dread and Apollo change little across the keyboard anyway.

**What the lite patch uses,** fitted in that order, each on the one-zone render's harmonics with the curve applied in dB (seconds per fit), then rendered and checked:
1. A 12 dB low-pass with partial key tracking and an envelope. The envelope reuses env2 and env3, the envelopes that already sweep the table, so it costs no new parts.
2. Two `eq` effects (a shelf, a peak and a shelf each), fitted with the engine's own biquads: the fixed curve in Hz.
3. `key_levels`, a level every 6 semitones. This is new in the engine (2026-11-01, `test_key_levels`), because the matrix's key → amp is a straight line and Basset's level swings by up to 25 dB from key to key.

The zone's frames are divided by the filter's and EQ's complex response at the center key, frame by frame (at each frame's time on the filter envelope). So the center note keeps its exact level and waveform. The engine scales a `normalize = false` table by its peak, so the oscillator level is corrected for the peak the division changed; without that, finalize's gain clipped.

Harmonic score on scenes 1–2 at the file's one level (dB), by distance from the center key:

| Sound | Full | One zone | Lite with curves | ±0–3 | ±7–13 | ±19–25 | ±25–40 | Memory full → lite |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Basset | 3.6 | 9.5 | 6.9 | 4.6 | 6.4 | 8.7 | 10.5 | 6.2 → 0.6 MB |
| Stack | 4.4 | 10.3 | 7.2 | 4.7 | 6.1 | 8.3 | 11.8 | 6.2 → 1.0 MB |
| Panda | 6.3 | 10.2 | 7.7 | 6.7 | 7.2 | 8.3 | 8.7 | 6.2 → 1.1 MB |
| Avenue | 7.3 | 13.4 | 10.9 | 7.0 | 12.1 | 10.5 | 12.3 | 12.5 → 1.8 MB |
| Flag | 7.6 | 9.4 | 8.9 | 8.6 | 9.3 | 8.9 | 8.8 | 12.5 → 2.2 MB |
| Dread | 6.9 | 8.9 | 8.3 | 7.3 | 7.5 | 9.3 | 10.4 | 12.5 → 2.0 MB |
| Pixel | 7.2 | 8.8 | 8.6 | 7.7 | 8.6 | 9.6 | 10.1 | 12.5 → 1.5 MB |
| Apollo | 7.5 | 7.9 | 7.8 | 7.6 | 7.5 | 7.7 | 7.1 | 18.8 → 2.2 MB |
| Spiral | 10.7 | 13.3 | 12.6 | 9.9 | 11.9 | 14.5 | 15.8 | 18.8 → 2.6 MB |

The curves themselves cost nothing in memory: two EQ effects, a filter and 11 numbers. A single zone stores every band limit (it's played over five octaves), so memory drops by 6–10×, not by the zone count.

**Gotchas:**
- Score per note at the file's one level (`spread.py`). Matching each note's level on its own hides level errors by key.
- The fits land in local minima, so they use several starts and bounds (cutoff 40–18000 Hz, Q 0.3–3). Without the bounds they ran to degenerate filters.
- What's left far from the center is mostly the waveform's phases, which no curve over level can move (Basset's note 48).

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

## Importer (built 2026-11-01)

The Synth page's **Match a recording** (`editor/match_panel.gd`) runs `AKSampleMatch` (`lab/sample_match.gd`) on a thread: version 2's full patch, then the lite patch, from an `.axbw` of the scale MIDI. **Scale MIDI** writes the three loops (`AKSampleMatch.scale_loops()`, the same notes and ticks as the exports used here).

- **Ported, step for step:** align (scenes and loop repeats from the manifest), the 15 Hz high-pass, the transposition, the zoned table (stereo when wide), tuning, release, velocity curve, the level, the three lite fits, and the checks (`check.py`, `floor.py`, `spread.py`'s distances).
- **Native:** `AKMatch` (`native/src/ak_match.cpp`) does the heavy parts: the high-pass, spectra, harmonic measurement at any frequency, `hfeats`, and `hloss` with the lite model's corrections (filter, EQ, level by key). The minimisers are GDScript (`lab/fit.gd`): Nelder-Mead and Powell, ported from scipy. On a test with a kink, Powell stops where scipy's does, to 8 digits. There's no GDScript fallback: the match needs the native core.
- **Frames:** 16 and 24 are both tried, and 24 is kept when it scores 0.5 dB better. Spiral takes 24 (15.0 → 11.7 on the whole file); Apollo gains only 0.4 dB (8.2 → 7.8), so it keeps 16.
- **Not automatic:** noise bursts (`add_bursts.py`) and moving effects (`fx_fit.py`). They were fitted by hand for Spiral and Apollo, which is why those two score worse here than the Python patches.
- **Time:** 20–55 s a sound on this Mac, mostly checking and fitting.

Against the Python patches, scored by `spread.py` (scenes 1–2, one level, dB). The importer's full patches match the Python ones within 0.1 dB, except for Spiral and Apollo (above). Its lite patches land within ±0.3 dB of the Python lite, or worse by up to 0.9 dB. The fits are the same, but they land in slightly different local minima, as seen on Basset: the filter ends at 12.3 in both, the EQ at 11.8 against 11.6.

| Sound | Python full | Importer full | Python lite | Importer lite |
| --- | --- | --- | --- | --- |
| Basset | 3.6 | 3.6 | 6.9 | 7.6 |
| Stack | 4.4 | 4.3 | 7.2 | 7.2 |
| Panda | 6.3 | 6.3 | 7.7 | 8.0 |
| Avenue | 7.3 | 7.3 | 10.9 | 11.8 |
| Flag | 7.6 | 7.6 | 8.9 | 8.8 |
| Dread | 6.9 | 6.9 | 8.3 | 8.7 |
| Pixel | 7.2 | 7.2 | 8.6 | 8.3 |
| Apollo | 7.5 | 8.1 | 7.8 | 7.6 |
| Spiral | 10.7 | 11.2 | 12.6 | 13.5 |

Gate: `tests/test_sample_match.gd`. It checks the scale MIDI, the kernels against known tones, and the minimisers. It also runs a round trip: a known patch is played through the scale MIDI, packed as an export, and matched back (transposition 0, full under 3 dB, lite under 6 dB, the level within 1.5 dB). Song exports are refused.

Next:
- automatic bursts and effects, found by the check (movement the table lacks);
- reading WAV takes made to the recording guide;
- the lite center chosen per sound (where the recording is steadiest).
