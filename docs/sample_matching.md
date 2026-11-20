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

The notes are found from the audio: each starts where the level climbs past 25 dB under the file's loudest and ends at its key-up (a drop of 12 dB inside 50 ms that stays down, or else where the level starts falling at least 3× as fast as it was and keeps falling). A pad whose own decay looks like a release can be misread; when every note was held the same time, give it (`hold_s`, or `--hold 2.42` on the command line: the Open Samples synths were sampled with 2.42 s holds). Each note should be held at least a second. With no velocity pair or repeated pass, the velocity curve stays linear and there is no floor score. The table sweeps through the whole held note (`sweep_s`, 1 to 8 s), so a slow pad keeps moving, and a release that drops at once and then trails off gets two stages.

**Detuned layers.** Sample-playback synths often stack two copies of a wave a few cents apart, so each harmonic beats at k × the detune. The match looks for that (`find_layers`, on any recording with held notes): the detune that explains the most of the harmonics' movement, the same on most notes, then per note the two layers' level ratio and start phase (they change across the keyboard, from one root sample to the next). It takes the beating out of the measured frames and plays the sound as two table oscillators, a little flat and a little sharp; the second plays a copy of the table whose zones carry their level and phase, so a layered patch holds two tables. It tries the patch with and without layers and keeps the better (`layers = 1` always uses them when found, `-1` never looks; `--layers` on the command line).

**Vibrato.** A pitch wobble at one rate on every note (2.5 to 12 Hz) is found from each held note's pitch, measured every 5 ms (`find_vibrato`). Each rate is fitted over all the notes at once, both in file time (an LFO that runs on through the recording, as a hardware LFO does) and in time from each note-on, and the best is taken when it stands well clear of the rest. Detuned layers also make the pitch wobble, but at rates that follow the note, so they don't line up across notes. The patch plays it as LFO 1 on pitch, free-running or restarting, at the measured rate, depth and phase. The harmonic score hardly sees a few cents of vibrato, so it's kept unless it costs the full patch over 0.3 dB (`vibrato = 1` always uses it when found, `-1` never looks; `--vibrato` on the command line).

**Movement.** Pads and leads made of many detuned voices or run through a chorus drift in a way that never lines up with the recording moment by moment, so the harmonic score can't reward copying it. `motion` measures, for each held note, how far and how fast each harmonic's level, the pitch and the width (side against mid) move, every 10 ms through the hold. One 2 s hold is a single random take (low notes may not finish one beat in it), so `motion_gap` pools the notes before comparing: the gap in how far each kind moves (dB) plus 3 dB per octave of gap in how fast. A separate tone gap (each harmonic's mean level) catches a fit that colours the sound. `fit_movement` tries a grid of unison (2 to 5 voices, 3 to 25 cents) and chorus (0.5 to 4 Hz, 2 to 7 ms) settings, closes in on the best of each, then tries the two together. A stack of voices starts at random phases, so each setting is judged over four seeds. It's kept when it brings the movement at least 2 dB closer and costs the harmonic score at most 2.5 dB (more means the wrong kind of movement: a pure or layered sound whose frames already move right; `movement = 1` always uses the closest, `-1` never looks; `--movement` on the command line). The harmonic score gets 2 to 3 dB worse when movement is added, as expected for motion that can't line up, so whether it's right is for listening.

**Delay.** A delay keeps playing the echo of a held note after its key-up, so the tail sits on a plateau for one delay time and then drops suddenly when the echo of the key-up arrives, and again at each later echo. `find_delay` looks for that drop at the same time after every held note's key-up (beating moves the level too, but differently on each note), from 150 ms on, clear of the release's own fall. It's found when the drop stands 8 MADs over the rest and is at least 4 dB on every note. The earliest strong drop is the delay (with feedback the later echoes end in drops nearly as deep), timed from the key-up's own steepest point to the echo's. The first plateau gives the mix and the fall from one plateau to the next the feedback. `fit_delay` closes in on time, mix, feedback, damping and a shorter release (the release fit had stretched the release to stand in for the echoes), judged by the release tails: the level every 25 ms and its 50 ms steps, so the drops have to land at the same times. It's kept when the tails come at least 1 dB closer and the harmonic score is at most 1.5 dB worse: echoes of a moving sound add movement that can't line up moment by moment, as a chorus does (`delay = 1` always uses it when found, `-1` never looks; `--delay` on the command line).

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
