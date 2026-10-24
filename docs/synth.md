# Synth engine and patches

A **patch** (`AKPatch`, a `.tres`) describes a synth sound: oscillators, a filter, envelopes, LFOs, a modulation matrix and how notes are played. One engine renders it, live or baked, so what you hear while playing is what a bake writes.

```gdscript
var p: AKPatch = load("res://addons/audio_kit/patches/saw_lead.tres")

# Live (needs the native core): an AudioStream for any AudioStreamPlayer and any Godot bus.
var s := AKSynthStream.new()
s.patch = p
$Player.stream = s
$Player.play()
s.note_on(60, 0.9)           # middle C, at the next mix
s.note_off(60, 0.5)          # half a second from now, to the sample
s.set_bend(0.5)              # half of bend_range up
s.set_mod_wheel(0.8)

# Baked (native or GDScript): an AKBuffer.
var buf := AKSynth.render_notes(p, [{time_s = 0.0, note = "C4", length_s = 0.4},
	{time_s = 0.5, note = "E4", velocity = 0.7, length_s = 0.4}, {time_s = 0.6, bend = 1.0}])
buf.save_wav("res://audio/lead_phrase.wav")

# In a recipe (so in songs, cue maps and recipe streams too): the `patch` voice.
var r := AKRecipe.make(&"patch", {patch = "res://addons/audio_kit/patches/pluck.tres", freq_hz = 220.0, gate_s = 0.2})
```

In the editor, select a patch to play it from the Audio Kit dock (single notes, a chord, an arpeggio, a glide), live when the native core is installed. Edit it in the inspector; the next note uses the edit, and a playing `AKSynthStream` picks it up at once.

## Signal path

Per voice: oscillators (each stacked `unison` times) are summed by their levels, run through the filter, and multiplied by the amp envelope, velocity, the `amp` modulation and `gain_db`; then panned. Voices sum into a stereo output.

Envelopes, oscillators and the filter run every sample. Modulation (LFOs, the matrix, glide, pitch, oscillator settings, filter coefficients, amp and pan) is worked out every 8 samples (6 kHz) and held in between. That keeps 32 voices at about 5–6% of a core; the steps are far too small to hear on vibrato, sweeps and FM envelopes.

## Oscillators

Up to four, in `oscillators`:

| Key | Default | What it does |
| --- | --- | --- |
| `shape` | sine | `sine`, `triangle`, `saw`, `square`, `pulse`, `noise` or `morph` (band-limited saw, square and pulse) |
| `level` | 1.0 | Its level in the mix; 0 makes a pure modulator |
| `semitones`, `cents` | 0 | Offset from the note |
| `width` | 0.5 | Pulse width (`pulse` only) |
| `position` | 0 | `morph` only: 0 sine, 0.33 triangle, 0.66 saw, 1 square, blended between |
| `fm_from` | 0 | 1-based number of another oscillator that phase-modulates this one; 0 = none |
| `fm_index` | 0 | Modulation depth in radians |

Oscillators are computed last to first, so an oscillator modulated by a later one hears it this sample; one modulated by itself or by an earlier one hears the previous sample (feedback). The classic two-operator FM pair is `[{shape = "sine", fm_from = 2, fm_index = 2.0}, {shape = "sine", level = 0.0, semitones = 12.0}]`.

`unison` (1–7) stacks every oscillator, spread evenly across `detune_cents`, with seeded random start phases; noise isn't stacked.

## Filter

`filter = {type, cutoff_hz, q, slope_db}`: `off`, `lowpass`, `highpass`, `bandpass` or `notch`; a state-variable filter, 12 dB per octave, or 24 with `slope_db = 24`.

## Envelopes

`amp_env`, `env2`, `env3`, each `{attack_s, decay_s, sustain, release_s, curve}`. Attack rises linearly (0 = start at full level). Decay is linear, or with `curve = "exp"` a time constant toward `sustain`. Release is a time constant from wherever the level is when the note ends. `amp_env` sets the level (and is the matrix source `env1`); `env2` and `env3` only act through the matrix.

## LFOs

`lfo1`, `lfo2`, each `{shape, rate_hz, delay_s}`: `sine`, `triangle`, `saw`, `square` or `random` (a new random value each cycle). They restart with every note; `delay_s` fades them in (delayed vibrato).

## Modulation matrix

`mods`, up to 16 rows of `{source, dest, amount}`. Each row adds `amount × source` to the destination.

| Source | Range |
| --- | --- |
| `env1` (amp), `env2`, `env3` | 0..1 |
| `lfo1`, `lfo2` | -1..1 |
| `velocity` | 0..1 |
| `key` | octaves from middle C (C5 = 1) |
| `mod_wheel`, `aftertouch` | 0..1 (from `set_mod_wheel`, `set_aftertouch`) |
| `random` | -1..1, new for every note |
| `bend` | -1..1 (the pitch bend also moves pitch by `bend_range` on its own) |

| Destination | Unit |
| --- | --- |
| `pitch` | semitones |
| `cutoff`, `q` | octaves (multiplies by 2^amount) |
| `amp` | added to a gain of 1 (−1 silences, +1 doubles) |
| `pan` | −1 left .. 1 right |
| `oscN.pitch` | semitones (N is 1-based; `osc.pitch` means every oscillator) |
| `oscN.level`, `oscN.fm` (radians), `oscN.width`, `oscN.position` | added to the oscillator's setting |

## Playing

| Setting | What it does |
| --- | --- |
| `mode` | `poly`; `mono` (one voice, envelopes restart on each note); `legato` (one voice, envelopes carry on while notes overlap). In mono and legato, releasing the top note returns to the one still held |
| `polyphony` | 1–32 voices. A new note beyond that takes over the oldest releasing voice, else the oldest |
| `glide_s` | Portamento time constant (0 = jump) |
| `bend_range` | Semitones at full bend |
| `velocity_sens` | 0: velocity doesn't change the level; 1: level follows velocity |
| `gain_db`, `pan` | Output level and balance |
| `seed` | Seeds noise, unison phases, the random source and random LFOs |

The same notes, controller changes and seed always give the same samples, in GDScript, natively and live.

## Live and baked

`AKSynthStream` (native) is the engine running in the audio thread. Calls take effect at the next mix block, or exactly `delay_s` later, so notes can be scheduled to the sample. `AKSynth.render_notes` bakes through the native engine when it's installed and through `AKSynthCore` (the same steps in GDScript, about 100× slower) when not; tests hold all three to the same samples.

Latency for keyboard play is Godot's mix buffer (about 15–30 ms by default).

## Today's voices as patches

`AKPatchLib.from_voice(voice, params)` rebuilds `tone`, `wavetable` and `fm` as patches: the same sound, polyphonic and playable live. `AKPatchLib.note_of(voice, params)` gives the note to play. Measured against the voices, plain tones match to float rounding; vibrato, the wavetable filter envelope and FM come within 25–40 dB SNR (the control rate, and float32 rounding inside the voices); `tone`'s glide curves in semitones rather than in Hz (timed to agree halfway); `wavetable` unison phases differ. The voices themselves are unchanged, so existing recipes and bakes don't move.

## Presets

In `addons/audio_kit/patches/` (written by `tools/make_patches.gd` from `AKPatchLib.preset`): `tone_beep`, `wavetable_bass`, `wavetable_pad`, `fm_epiano`, `fm_bell` (from the voices), and `saw_lead`, `sub_bass`, `brass`, `pluck`, `strings`, `organ`, `wobble_bass`. A single note of each peaks around −6 dBFS, leaving room for chords. All are original.

## Not yet (later phases)

MIDI input and `.mid` import (phase 3), the ladder filter, wavetables from tables, sync, ring modulation, stereo unison and patch effects such as chorus (phase 4), the patch editor panels (phase 5).
