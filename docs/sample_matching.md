# Sample matching: recording guide

How to record an instrument so its sound can be matched as a synth patch. The analysis finds each note, then measures its pitch, harmonics, envelope, filter movement, vibrato and noise, and checks a guessed patch against the recording until the two line up.

Two routes:

- **From Auxy** (iOS), matched in the Sound Lab now: play the scale MIDI and export it (below).
- **A plain WAV of held notes** with silence between them, such as a sampled multisample (one patch, a note every octave), matched by `AKSampleMatch.run_wav` (below).
- **Your own WAV recordings**, to the takes below. The scale takes aren't read as a set yet; a take of held notes (Take 2) goes through `run_wav`.

## From a plain WAV

```gdscript
var m := AKSampleMatch.new()
var res := m.run_wav("res://recordings/pad.wav", 36, 12)   # the first note's key, the step to the next
```

or from the command line, for several files at once (patches, A/B renders and a `report.json` in the output folder; `--notes` only prints the notes it finds):

```
godot --headless --path . -s res://tools/sample_match/match_wav.gd -- out/match 36 12 pad.wav bass.wav
```

The notes are found from the audio: each starts where the level climbs past 25 dB under the file's loudest and ends at its key-up (a drop of 12 dB inside 50 ms that stays down, or else where the level starts falling at least 3× as fast as it was and keeps falling). A pad whose own decay looks like a release can be misread; when every note was held the same time, give it (`hold_s`, or `--hold 2.42` on the command line: the Open Samples synths were sampled with 2.42 s holds). Each note should be held at least a second. With no velocity pair or repeated pass, the velocity curve stays linear and there is no floor score. The table sweeps through the whole held note (`sweep_s`, 1 to 8 s), so a slow pad keeps moving.

Tried on twelve patches from the [Open Samples](https://github.com/pumodi/open-samples) Roland JV-2080 and Korg M1 folders (C2, C3 and C4 held 2.4–6 s, or C1–C3 on the M1).

## From Auxy

1. On the Sound Lab's Synth page, under **Match a recording**, press **Scale MIDI** and pick a folder: it writes `scale_1_run.mid` (a chromatic run from F#7 down to G2), `scale_2_holds.mid` (1-second holds on C7 to C3, fast repeats, an octave arpeggio) and `scale_3_velocity.mid` (one note at two strengths and four lengths, then fast repeats).
2. In Auxy, start a project at 60 BPM with one instrument: the sound to match. Import each file as a loop, one per scene, in that order (each scene 8 bars).
3. Turn off the project's effects if you can. Settings → Export Project → **Export for Bitwig Studio**.
4. Back in the Sound Lab: **Pick export**, then **Match**.

The export holds the MIDI and the audio together, lined up to the millisecond, so the tool knows exactly where every note is.

## File format

- WAV, 44.1 or 48 kHz, 24-bit (16-bit is fine).
- Mono, unless the sound is noticeably wide in stereo (chorus, stereo delay); then stereo.
- Dry: no reverb, delay, compressor, limiter or normalising. Turn off the instrument's built-in effects if you can; if you can't, note which are on.
- Peaks around −6 dB. Never clip.
- 2 seconds of silence at the start of every file, so the noise floor can be measured.
- One file per take.

## Take 1: short notes (`name_short.wav`)

- C2 to C6, every 3 semitones (C, D#, F#, A, C …): 17 notes.
- Hold each note for 1 second, then 3 seconds of silence so the release rings out fully.
- The same medium strength on every note.
- No pedal or hold.
- A metronome at 60 BPM makes it easy: press on 1, let go on 2, wait for the next bar.

About 70 seconds.

## Take 2: held notes (`name_held.wav`)

- C2, C3, C4, C5, C6.
- Hold each for 8 seconds, so the note can settle (or fade away), then let go and leave 4 seconds of silence.
- On a piano this is the sustain-pedal take; on a synth, just hold the key.

About 60 seconds.

## Take 3: strength (`name_velocity.wav`, optional)

- C4 three times: soft, medium, hard. 1 second each, 3 seconds apart.
- Shows whether playing harder makes the sound brighter as well as louder.

## Take 4: glide (`name_legato.wav`, mono synths only)

- A few overlapping notes, C4 → G4 → C5, to capture any slide between notes.

## Notes file (`name_notes.txt`)

- The lowest note and the step.
- The hold and gap times used.
- What the instrument is ("Juno-60 bass patch", "upright piano").
- Anything that couldn't be turned off.

## Why this layout

| What | Shows |
|---|---|
| Even gaps | Where each note starts and ends, and the whole release |
| 1 s against 8 s holds | Attack and decay apart from the sustain level |
| Five octaves | How brightness and length follow the keyboard |
| Silence at the start | The noise floor, so it isn't read as part of the sound |

A shorter instrument: cover the range it has. A one-shot sound with no sustain (a drum, a pluck): Take 1 alone is enough.

## What to expect

- **Synth sounds** (an analog bass, a pad, a chiptune lead) can come out very close.
- **Plucked and struck sounds** (guitar, piano, marimba) get the right shape and brightness, though not a real instrument's body.
- **Bowed, blown and sung sounds** become a "string-ish" or "flute-ish" patch. A waveform taken from the recording as a custom oscillator gets closer.
