# Synth expansion, phase 0: Synth1 → AKPatch

Status: **engine work built** (tempo and arpeggiator, 2026-11-20; see "As built"); the converter is next. Part of `docs/plans/synth-expansion.md`. Phase 0 was "converters on today's engine", but this converter now starts with two engine features: tempo-synced rates and an arpeggiator.

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
| osc1 8× detune (5,669 non-zero) | | **gap**: GAK's unison stacks every oscillator; approximate with `unison` when osc2 is off, else flag |
| mod envelope (AD) → osc2 pitch, FM, pulse width (8,535 on) | | a stages envelope (`env3`) and a matrix row |
| filter LP12, LP24, HP12, HP24, BP (71), LPDL (2) | all | SVF 12/24, highpass, bandpass; LPDL → `ladder` |
| filter env ADSR, amount ±, key track, velocity switch, saturation | all | `env2` → `cutoff`, `key` → `cutoff`, `velocity` → `cutoff`, `drive` (or a `saturate` effect) |
| amp ADSR, gain, velocity sens | all | `amp_env`, `gain_db`, `velocity_sens` |
| 2 LFOs: saw, tri, sine, square, S&H, smooth random (~1,250 each) | | `lfo1/2`; smooth random is a **gap** (closest: `random`) |
| LFO destinations: osc2 pitch, osc pitch, cutoff, amp, pulse width, FM, pan | | matrix rows |
| LFO tempo sync (4,938), key sync off | | LFO `sync` (engine work, below); `free = true` |
| play mode poly/mono/legato, portamento, auto portamento, bend range | | `mode`, `glide_s`, `bend_range` |
| unison on (9,368): voices 2–8, detune, pan spread, pitch offset, phase | | `unison` (max 7), `detune_cents`, `spread`; the pitch offset is a **gap** |
| chorus/flanger, 4 types (10,204 on) | | `chorus` / `flanger` |
| tempo delay ST/X/PP, spread, tone (10,685 on) | | `delay` with `time_sync` (engine work, below); mono today, so PP and spread are a **gap** |
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
2. The measuring harness (`tools/synth1_ref/`) and its curve tables.
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

