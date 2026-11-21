# Synth expansion, phase 0: Synth1 → AKPatch

Status: **engine work built** (tempo and arpeggiator, then the five Synth1 gaps, 2026-11-20; see "As built"); the measuring harness is next. Part of `docs/plans/synth-expansion.md`. Phase 0 was "converters on today's engine", but this converter now starts with two engine features: tempo-synced rates and an arpeggiator.

## What's on disk

| What | Where | Notes |
| --- | --- | --- |
| Synth1 1.13 beta 3 (Daichi Laboratory, Ichiro Toda; freeware, closed source) | `D:\tools\synth1` | `Synth1 VST64.dll` (VST 2.4), `readmeeng.html` (the manual). Downloaded from daichilab.sakura.ne.jp |
| Factory bank (128) and Ryd's bank (15) | `D:\12_library\gak\to_process\Synth1\daichi-factory`, `daichi-rydsound` | From the same page |
| KVR "Clean zipbank" (16,563 presets, deduplicated by its compiler, 182 banks) | `D:\12_library\gak\to_process\Synth1\kvr-cleanzipbank\<bank>\` | Linked from the KVR forum; a cleaned version of the "25K" community pack. Only `.sy1` and readme `.txt` files were extracted |
| DawDreamer 0.9.0 (GPL-3, Python) | `D:\tools\dawdreamer\venv` | Loads Synth1's VST2, sets all 255 parameters and renders notes. Never shipped |

## The `.sy1` format

A text file: line 1 is the program name, then `color=...`, `ver=105`..`113`, then `index,value` lines. `value` is the panel's 0–127 integer (or an enum index). **`index` is the VST parameter index**: DawDreamer names them (`0 osc1 shape` .. `98 delay tone`), and `get_parameter_text` reads back the same integer. Older versions omit the later indices (68 to 102 lines per file), so a missing index takes Synth1's default for that version.

Setting a value: enum parameters don't split 0–1 evenly (`osc2 shape` 1–4, `filter type` 0–5, `lfo dest` 0–7), so the reference renderer finds each value's normalised position once, by scanning `get_parameter_text`, and caches the table.

## Usage in the 16,706 presets

| Feature | Use | Maps to |
| --- | --- | --- |
| osc1 sine/tri/saw/pulse, osc2 tri/saw/pulse/noise | all | `oscillators[0..1].shape` |
| osc2 pitch, fine, key track off (1,281) | all | `semitones`, `cents`; tracking off → `fixed_hz` |
| FM osc2 → osc1 | many | `fm_from = 2`, `fm_index` (curve to measure) |
| ring (3,527), sync (3,973) | | `ring_from`, `sync_to` |
| sub oscillator (4,265 with gain > 0) | v1.11+ | a third oscillator, square, 0 or −12 semitones, with osc1's FM |
| osc1 detune (5,669 non-zero): 9 voices in Synth1 | | osc1's `stack` 8 (GAK's maximum) and `stack_cents` at the same outer spread (built; the sub's stack follows, as Synth1's does) |
| mod envelope (AD) → osc2 pitch, FM, pulse width (8,535 on) | | a stages envelope (`env3`) and a matrix row |
| filter 0 LP12, 1 LP24, 2 HP12, 3 BP, 4 LPDL (measured; 5 = 4, no HP24) | all | SVF 12/24, highpass, bandpass; LPDL → `ladder` |
| filter env ADSR, amount ±, key track, velocity switch, saturation | all | `env2` → `cutoff`, `key` → `cutoff`, `velocity` → `cutoff`, `drive` (or a `saturate` effect) |
| amp ADSR, gain, velocity sens | all | `amp_env`, `gain_db`, `velocity_sens` |
| 2 LFOs: 0 saw, 1 tri, 2 square, 3 S&H, 4 smooth random, 5 sine (measured) | | `lfo1/2`; smooth random → `smooth` (built) |
| LFO destinations: 1 osc2 pitch, 2 osc pitch, 3 cutoff, 4 amp, 5 pulse width, 6 FM, 7 pan (0 = 1; measured) | | matrix rows |
| LFO tempo sync (4,938), key sync off | | LFO `sync` (engine work, below); `free = true` |
| play mode poly/mono/legato, portamento, auto portamento, bend range | | `mode`, `glide_s`, `bend_range` |
| unison on (9,368): voices 2–8, detune, pan spread, pitch offset, phase | | `unison` (now up to 8), `detune_cents`, `spread`, `unison_pitch` (built; about 3,700 presets use an offset, mostly an octave or a fifth) |
| chorus/flanger, 4 types (10,204 on) | | `chorus` / `flanger` |
| tempo delay ST/X/PP, spread, tone (10,685 on) | | `delay` with `time_sync`, `mode` (`stereo`, `cross`, `pingpong`) and `spread_ms` (built; 3,784 use cross or ping-pong) |
| effect, 10 types (4,517 on) | | `saturate`, `crush`, `phaser`... per type, once each is identified by listening |
| EQ: tone (LP/HP tilt), parametric, pan | | `eq`, `pan` |
| arpeggiator (3,055 on) | | the patch's `arp` (engine work, below) |
| mod wheel → LFO1 speed and amount, MIDI CC assigns | | `mod_wheel` → `lfo1.rate`; amount is a **gap** (no LFO-depth destination); CC assigns ignored |

The gaps don't stop a patch converting; they make it approximate. Phase 3's matrix v2 (F7) closes the LFO-depth gap.

## Curves: measured, not guessed

The panel shows only 0–127, and the manual gives no units. The curves come from Synth1 itself, rendered through DawDreamer by a measuring harness (`tools/synth1_ref/`, Python, run in the DawDreamer venv; like `tools/dx7_env_ref`, nothing of Synth1 is copied):
- envelope times (attack, decay, release per value, and their shapes) and the sustain level curve;
- filter cutoff per value (from a resonant self-oscillating sweep), resonance, key tracking, envelope amount in octaves;
- LFO rate per value, and depth per destination;
- osc2 pitch and fine, FM index, pulse width, mix law, sub level, detune spreads;
- gain and velocity laws, chorus, delay and effect settings.

The results become tables in the converter, one per curve, with the harness's measurements checked in as data.

## Measured curves (2026-11-21)

Measured by `tools/synth1_ref/` against Synth1 1.13 at 48 kHz, so `v` is the stored 0–127 value. The full tables are in `tools/synth1_ref/data/*.json`, and the converter reads them from there rather than using the fitted formulas. The formulas below are for reading.

**Amp envelope** (`amp_env.json`)
- Attack is a linear ramp. Time to 90 %: 1.2 ms at 0, 7 ms at 32, 0.113 s at 64, 1.78 s at 96, about 26 s at 127. That is ×4 per 16 steps above about 32, with a floor near 1 ms.
- Decay and release share one curve, exponential (constant dB per second): −20 dB takes 4 ms at 0, 0.20 s at 64 (a time constant of 88 ms), 1.8 s at 96 and 15 s at 127, so ×3 per 16 steps.
- Sustain level in dB: −30.7 at 16, −22.5 at 32, −12.3 at 64, −5.3 at 96, −2.5 at 112, silent at 0. That is close to the gain knob's curve.

**Filter** (`filter.json`)
- Types, measured: 0 LP12 (a small +1 dB bump), 1 LP24, 2 HP12, 3 BP, 4 a ladder-like low-pass (`LPDL`: a +1.4 dB low-end bump, about 18 dB per octave, its corner about 1.3 octaves below LP12's at the same value). Value 5 renders the same as 4. No HP24 exists, so the usage table's HP24 is wrong.
- Cutoff (LP12, −3 dB) ≈ 715 Hz × 2^((v − 64) × 0.0795), about 21 Hz to 23 kHz. Values ≤ 16 sit below the measurement floor, and the table holds every value. LP24's −3 dB point lies about 1.3 octaves lower at the same value.
- Resonance peak at cutoff 64: LP12 +1.2 dB at 0, +2.5 dB at 64, +16 dB at 124. LP24 dips below 0 dB until about 100 and reaches +17 dB at 124.
- Key track pivots at note 48: at 120 the cutoff follows about 0.97 octave per octave, at 64 about 0.59. The curve is a table, not linear.
- Envelope amount: 64 is zero, about 0.157 octave per step, linear (about ±10 octaves at the ends).

**LFO** (`lfo.json`)
- Waves (`.sy1` value): 0 saw, 1 triangle, 2 square, 3 sample & hold, 4 smooth random, 5 sine. So smooth random is value 4 (about 1,000 per LFO) and sine is value 5 (about 2,600).
- Destinations: 1 osc2 pitch, 2 osc1+2 pitch, 3 filter cutoff, 4 amp, 5 pulse width, 6 FM, 7 pan. Value 0 behaves exactly like 1.
- Rate ≈ 3.33 Hz × 2^((v − 64)/12), one semitone per step: 0.17 Hz at 12, 125 Hz at 127. Values below 12 are slower than a 30 s render can measure, so the converter extends the line.
- Depth, pitch destination (peak to peak): 1.9 semitones at 8, 12 at 36, 29 at 64, 62 at 96, about 115 at 127. A convex curve, used as a table. Amp destination: 2.5 dB of swing at 32, 6 dB at 64, 12 dB at 96, 32 dB at 124.

**Oscillators** (`osc.json`)
- osc1 shapes: 0 sine, 1 saw, 2 pulse, 3 triangle. osc2 shapes: 1 saw, 2 pulse, 3 triangle, 4 noise.
- osc2 pitch: `osc2_pitch_semitones`, 128 integers from −60 to +60, one semitone per step. Values 1, 19, 37, 55, 73, 91 and 109 repeat their neighbour.
- osc2 fine and the master tune: cents = (v − 64) × 0.969 (±62 cents).
- osc2 with key track off: plays note 57 (220 Hz) shifted by its pitch, whatever the key.
- Mix: a linear crossfade, osc1 × (1 − v/127) and osc2 × v/127.
- FM (osc2 → osc1) is frequency modulation by a fixed deviation in Hz, the same at every note: 49 Hz at 16, 131 Hz at 32, 770 Hz at 64, 4.4 kHz at 96, about 18.7 kHz at 124. The converter turns it into GAK's index by dividing by osc2's frequency.
- Pulse width: a near-50 % square at 127, narrowing to a thin pulse at 0 (duty 0.51 at 124, 0.74 at 64, 0.99 at 0).
- osc1 detune: 9 partials, the outermost at ±1.1 cents per step (±71 cents at 64, ±140 at 127). GAK's stack stops at 8, so the converter uses 8 with the same outer spread.
- Sub: shapes 0 sine, 1 triangle, 2 saw, 3 square; octave 0 plays at the note, octave 1 an octave down. Gain crossfades against osc1 rather than adding: the sub's share is about g/(g + 32), osc1's 32/(g + 32), so 32 is an equal mix.
- Unison detune: the outer voices at ±5 cents at 32, ±13.6 at 64, ±27.6 at 96, ±50 at 127, roughly the square of the value. The level grows like voices summing in power: +3 dB at 2 voices, +10 dB at 8.
- Gain dB: −12.3 at 64, −4.6 at 100, 0 at 127.
- Velocity: the drop in dB = (127 − vel)/126 × sens × 0.234, linear in both (sens 127 at vel 1: −29.8 dB).
- Portamento is an exponential glide. Halfway takes 2.6 ms at 8, 14 ms at 32, 50 ms at 64, 0.14 s at 96, 0.28 s at 127; 90 % takes about 3.2× as long.

**Not yet measured**: chorus and flanger (4 types), delay time and tone, the 10 effect types, the EQ, the mod envelope. Measure these before the converter maps them.

## Checking a conversion

Synth1's oscillators are free-running unless `osc phase` is set, and unison, noise and S&H are random, so sample-by-sample SNR (as with the DX7) won't work. The check is per note, against a DawDreamer render in the same layout as the DX7 references (notes 36–84, velocity 100, hold 2 s, release 2.5 s, 48 kHz):
- **loudness envelope** error in dB (RMS in 10 ms frames);
- **spectral distance**: log-magnitude difference per frame across 1/3-octave bands;
- for fixed-phase patches without randomness, SNR as well.

A batch summary (as `gak_dx7_summary.json`) gives the median and worst notes, and flags each patch's gaps.

## Pipeline

1. **Catalogue** (open-samples prep tool): a `synth1` parser turns each `.sy1` into an `instrument.json` sidecar with every parameter named (`content.synth1.params`), the bank and its readme, version, and a parameter hash for duplicates. Output: `D:\12_library\gak\processed_synth1\<bank>\<program>\`.
2. **Render** the references: `tools/patch_convert/render_synth1.py` (DawDreamer venv) writes `render_synth1_v100.wav` beside each sidecar.
3. **Convert and check**: `tools/patch_convert/synth1.gd` and `synth1_batch.gd`, which write `gak_patch.tres` and `gak_report.json` per patch and `gak_synth1_summary.json`.

## Decisions (2026-11-20)

1. **References: DawDreamer renders.** Installed and working.
2. **Scope: a subset first.** The factory bank and a handful of KVR banks (a few hundred presets) while the measured curves settle, then all 16,706 in one batch.
3. **Catalogue in the prep tool.** A `synth1` parser writes `instrument.json` sidecars with every parameter named, so search and the matcher see Synth1 patches too.
4. **Tempo support in the engine first**, not a fixed 120 BPM. Synced LFOs and the delay keep their musical values.
5. **An arpeggiator in the engine first.** This overturns the spec's "arpeggiators belong to the sequencer": 3,055 presets (18%) use Synth1's, and their sound depends on it.
6. **Presets stay in the personal library.** Community banks were shared freely for use, not relicensed, so converted patches stay outside the repo, as with the other sources.

## Engine work first (agreed 2026-11-20, built)

Both features follow the engine's promises: a patch without the new fields renders the same samples, native = GDScript, live = baked, and the same notes, controllers and seed give the same samples.

**Tempo.**
- The synth gains a tempo: `AKSynthStream.set_tempo(bpm)` live, a `tempo_bpm` argument to the render calls, and a patch default `tempo_bpm` (120) used when nothing else sets one. The sequencer and live player pass their `AKTempoMap`'s tempo, so a synced patch follows the music.
- Synced values are note lengths: `"1/4"`, `"1/8."` (dotted), `"1/8t"` (triplet), `"1/16"`, or a beat count. LFOs take `rate_sync` in place of `rate_hz` (`sync` already means key sync on a dx7 LFO); the `delay` effect takes `time_sync` in place of `time_ms`.
- Synth1's own sync values (whole note to 1/32, with its `+`, `*` and `/3` combinations) map onto these.

**Arpeggiator.** A patch field, `arp = {mode, octaves, rate, gate, on}`, as Synth1's:
- `mode`: `up`, `down`, `updown`, `random` (seeded);
- `octaves` 1–4; `rate` a synced note length (it uses the tempo above); `gate` 0–1, the share of each step a note sounds (1 ties into the next, for legato and glide).
- It runs inside the voice allocator, sample-exact: held keys form the chord, and each step plays one voice. Live, baked, native and GDScript give the same steps.
- It starts on the first key down (the user didn't pick between that and the beat grid; the first key is what a render of held notes needs).

## Order of work

1. Tempo (engine, native and GDScript, with tests), then the arpeggiator on top of it. **Built.**
2. The measuring harness (`tools/synth1_ref/`) and its curve tables. **Built** ("Measured curves"; effects still to measure).
3. The prep tool's `synth1` parser and sidecars for the subset.
4. Reference renders, then the converter and its batch, on the subset.
5. The full 16,706.

## As built (engine work)

- **Tempo** is an engine event (`E_TEMPO` = 8), so it lands on an exact sample, live and baked: `AKSynthStream.set_tempo(bpm, delay_s)`, `AKSynthCore.set_tempo(frame, bpm)`, and `{time_s, tempo_bpm}` in `AKSynth.render_notes` (sorted before notes at the same time). The patch's `tempo_bpm` applies until one is set. Range 20–400 BPM.
- **Synced LFOs** (`rate_sync`) compile to `beats` per cycle. A tempo change starts a new segment of the free-running clock (cycles so far plus the new rate from that frame), so a free synced LFO stays continuous. Unsynced LFOs take the same arithmetic with a zero base, which leaves their samples unchanged.
- **Synced delays** (`time_sync`) compile to `time_beats` (and `time_ms` at 120 BPM, for recipes and the tail estimate). The line is allocated at the longest time (2 s), and a tempo change only moves the read length, so nothing allocates on the audio thread.
- **The arpeggiator** sits in front of the voice allocator, in both engines. Each sample it closes the gate, plays a due step and advances its beat clock by `tempo / 60 / rate`. The held keys are a fixed array of 128 in the native engine. The random order is a xorshift32 seeded from the patch seed and a count of pattern starts, identical in both.
- **Promise kept.** HEAD was exported to a scratch folder and its native core built there. The rich test patch, every shipped preset, and a mono patch with a free LFO, a delay, a chorus and the sustain pedal were rendered in both versions. Native renders, GDScript renders and `describe()` hash identically before and after. New patch fields enter `describe()` only when set.
- **Tests** (`tests/test_synth.gd`):
  - synced LFOs and delays match `rate_hz` and `time_ms` at 120 BPM, after a tempo event, and with `tempo_bpm`;
  - each mode's note order, the gate, velocity per key, the seeded random order, and stopping on release;
  - a gate-1 legato arpeggio with no gaps, and tempo changes mid-pattern that agree across native, GDScript and live.

## As built (the five Synth1 gaps, 2026-11-20)

Counted across all 16,706 presets first; these were the gaps that would audibly change a conversion. Same promises as the tempo work: old patches hash identically (native, GDScript, `describe()`), native = GDScript.
- **Oscillator `stack`** (1–8) and `stack_cents`: one oscillator's copies inside each unison voice, multiplying `unison`. Each oscillator now has up to 64 phase slots (unison voice × copy). FM, sync and ring between oscillators with different stacks read the same unison voice of the source, and its copy when it has as many. One oscillator stacked n times is exactly unison n.
- **`unison_pitch`** (−24–24 semitones) raises the odd-numbered unison voices. Rendering Synth1 confirmed that only two pitches sound (the note and the interval, nothing between). How it splits the voices could not be settled from renders, because its random phases make the measurement noisy. Every other voice is the engine's choice; the harness checks it against Synth1, and the converter can compensate with levels if it differs.
- **`unison` up to 8.**
- **LFO shape `smooth`**: a new seeded random value each cycle, reached along a half cosine from the last one.
- **Delay `mode`** (`stereo`, `cross`, `pingpong`) and **`spread_ms`** (−100–100). The line holds the longest time plus the spread. Each side reads its own length back from the write position, so a tempo change still only moves read lengths. `stereo` with no spread is the old delay sample for sample.
- **Tests** (`tests/test_synth.gd`): a stack of 3 equals unison 3; a stacked patch with unison, FM, sync, ring, `unison_pitch` and unison 8 agrees natively; a two-voice octave gives equal partials; smooth random glides where random steps; each delay mode's echoes land on the expected side and sample, natively and in GDScript, and spread delays one side.

