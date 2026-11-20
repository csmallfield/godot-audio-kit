# Synth expansion: spec

Status: **agreed spec** (decisions of 2026-11-20 below). **Phases 1 (F2) and 2 (F1, F3, F4 frequencies, F6 `dx7`) are built**: `docs/plans/synth-expansion-phase1.md` and `-phase2.md`; user docs in `docs/synth.md` (Oscillators: Operators; Envelopes; LFOs). Each engine feature is tied to the source formats it lets us convert directly. Archives are logged at the end and the spec grows with them.

## Goal

A personal library of **synthesized** GAK instruments, made from sample and patch collections. They are kept outside the repo and sorted with light metadata and tags. `tools/open_samples_prep` turns each collection into neutral data: WAVs, mappings, renders, and an `instrument.json` per instrument with every source parameter it could read. Converters and the sample matcher then turn that into `AKPatch` patches, and the library is reprocessed whenever they improve.

This spec answers: **which engine features let which formats convert directly, and in what order should we build them?**

## Principles

- **Direct conversion first.** Where a source holds synthesis parameters, translate them exactly. The sample matcher is the fallback for what has none (recordings, PCM waves), and the refiner when a translation is approximate.
- **Every conversion is checked.** A converted patch is rendered and compared with a reference (the source engine's render, or its samples), and the report travels with the patch.
- **Features follow formats.** A feature earns its place by the number of patches it converts directly (see the coverage matrix). Exact source behaviour beats a generic feature plus fitting, wherever the source's behaviour is known.
- **Old patches don't move.** New fields default to today's behaviour. Existing patches, recipes and bakes sound the same.
- **Live and baked stay one.** Every feature lands in the native core and the GDScript mirror, and their renders agree as today (`docs/synth.md`).
- **Patches stay text.** New features are readable fields.
- **No sample playback.** Wavetables made from analysis, or loaded from a synth's own tables (Vital), are fine. Playing back recordings is not the aim.

## The engine today (`AKPatch`)

| Area | Today | Limit |
| --- | --- | --- |
| Oscillators | sine, triangle, saw, square, pulse (width), noise, morph, wavetable; level, semitones, cents, pan, filtered/unfiltered | 8 (`MAX_OSC`, phase 2) |
| Between oscillators | phase modulation from **one** source (`fm_from`, `fm_index`), feedback via self/earlier, hard sync, ring | one modulator each |
| Filter | state-variable LP/HP/BP/notch 12/24 dB, or a 24 dB ladder with drive | one filter |
| Envelopes | `amp_env`, `env2`, `env3` and `envelopes` (env4–env8): ADSR, stages (F2) or `dx7` (F2) | 8, shared by all oscillators (per-oscillator: F3) |
| LFOs | sine, triangle, saw, square, random; rate, delay, width, phase, free-running | 2 |
| Matrix | sources env1–3, lfo1–2, velocity, key, mod wheel, aftertouch, random, bend; per-oscillator and global destinations | 16 rows |
| Voice | poly/mono/legato, glide, bend range, unison (7, detune, spread, level), velocity sensitivity and curve, key-to-level table | global unison only |
| Effects | chorus, flanger, phaser, EQ, compressor, saturate, pitch, ring, growl, crush, delay, reverb | — |

## Feature spec

Each feature lists its proposed patch fields (a sketch, to be settled when built) and what it unlocks. The **F** numbers are used in the coverage matrix.

### F1. Operator graph

- **`MAX_OSC` 4 → 8** (decided). Patches use what they need; cost scales with oscillators in use.
- **Several modulators per oscillator.** `mods: [{from, index}]`, each with its own depth in radians. Today's `fm_from` / `fm_index` stays as shorthand for one entry.
- **Feedback depth** on any oscillator: `feedback`.
- **Algorithm presets** fill in `mods`: `algorithm = "dx7:5"` or `"tx81z:3"`. They're a convenience; the explicit graph is what's stored.
- *Unlocks:* DX7/TX802/TX816, TX81Z/DX11/DX21/27/100, FB-01, Dexed. Also Synth1's and Surge's FM routings, and Vital's oscillator cross-FM.

### F2. Envelope generator v2

- **Any number of stages.** `{stages: [{time_s, level, curve}], sustain: i, loop: [a, b], delay_s, hold_s}`, plus release stages after key-off.
- **Today's envelopes become special cases.** ADSR (`amp_env`, `env2`, `env3`) keeps its fields.
- **More envelopes.** `envelopes: [...]`, up to 8 per patch. `amp_env`, `env2` and `env3` stay as names for the first three. Every envelope is a matrix source.
- **Per-stage curves.** `linear`, `exp`, `power` (with an amount, as Vital), and **source curve modes** that reproduce a synth's own rates and level steps exactly:
  - `dx7`: the msfa envelope, ported from Dexed's `env.cc`, so DX7/TX voices use their raw rates and levels.
  - `cz`: the CZ 8-step rate/level model.
  - `m1`: Korg M1/M3R units. These need measuring first: the M3R manual gives 0–99 values, not seconds.
- **Time scaling** per envelope: `time_key_track` (signed, around a center key) and `time_velocity`, each applied to chosen stages. The M3R's per-segment switches and polarity map onto this, and so does the DX7's rate scaling.
- **Level scaling by velocity:** `level_velocity`.
- *Unlocks:* DX7 and TX (with F1/F3), CZ, M3R VDF/VDA/pitch EGs, D-50 TVA/TVF/TVP (5-stage), Matrix-6 (DADSR), SFZ/sampler zones (delay, attack, hold, decay, sustain, release with attack shape), Vital (DAHDSR with power curves), Helm, Surge.

### F3. Per-oscillator envelopes and scaling

- **An oscillator can follow its own envelope:** `level_env` (an index into `envelopes`); otherwise the shared amp envelope applies, as today. Optionally `pitch_env` and `shape_env` (for PD depth or wavetable position).
- **Keyboard level scaling:** `key_scaling: {break_key, left_depth, right_depth, left_curve, right_curve}`, with curves `-lin`, `-exp`, `+exp`, `+lin` (DX7, TX).
- **Velocity and mod sensitivity:** `velocity_sens` and `amp_mod_sens` per oscillator.
- **Key tables as a modulation source.** `key_tables: [[[key, value], ...]]`, usable as matrix sources. This generalises today's `key_levels` and covers the Matrix-6 tracking generator and the CZ's key follow.
- *Unlocks:* DX7/TX across the whole keyboard (not only at the rendered keys), CZ lines, Matrix-6, M3R VDA keyboard tracking.

### F4. Oscillator additions

- **Frequency:** `ratio` (an exact multiplier, e.g. 1.41, 3.5) and `fixed_hz` (ignores the key), beside semitones and cents. Covers DX7/TX ratios and fixed operators, and Surge/Vital fine tuning.
- **OPZ waveforms:** `sine`, `half_sine`, `abs_sine`, `quarter_sine`, the alternating variants, and the TX81Z's other shapes. For TX81Z, DX11, YS200.
- **Phase distortion:** `shape = "pd"` with `pd_wave` (saw, square, pulse, double sine, saw-pulse, resonance 1–3) and `pd_amount` (the CZ's DCW), which an envelope can drive through `shape_env`. For the Casio CZ series.
- **Per-oscillator unison:** `unison`, `detune_cents`, `spread` on an oscillator, as Vital and Helm have. Patch-level unison stays.
- **Oscillator delay:** `delay_s`, the time before the oscillator starts (the M3R's "delay start").
- **Later:** Vital's warp modes (sync, formant, quantize, bend, squeeze, PD); a wavetable import path for Vital tables (the engine already plays tables; this is format reading).

### F5. Second filter and routing

- **`filter2`** with the same fields as `filter`.
- **Routing:** `filter_routing = "series" | "parallel"`, and per oscillator `filter = 1 | 2 | both | none`. Today's `filtered: false` is the same as `none`.
- **Later:** comb and formant filter types (Vital, Helm), and audio-rate cutoff modulation from an oscillator (Prophet-5 poly-mod).
- *Unlocks:* Juno-106 (fixed HPF + LPF), CS20m-style HPF/LPF, Vital, Surge, Odin 2, MS2000 dual setups, D-50 partials, and sampler instruments with two filters.

### F6. LFOs v2

- **More LFOs:** 2 → 8 (`lfos: [...]`, `lfo1` and `lfo2` stay).
- **Custom shapes:** `shape = "points"` with `[[phase, value, curve], ...]`, covering Vital and Surge. A step mode gives Helm's step sequencer and Vital's stepped LFOs.
- **Source LFO models:**
  - `dx7`: speed curve, delay ramp, key sync, six waves, pitch and amp depth through each oscillator's sensitivity.
  - `m1`: the M3R's MG frequency and delay units, once measured.
- *Unlocks:* DX7/TX (exact modulation), Vital, Helm, Surge, M3R MGs.

### F7. Modulation matrix v2

- **32 rows.**
- **Sources** gain every envelope and LFO from F2/F6, key tables (F3), mod wheel and aftertouch curves, and **macros** (`macro1`–`macro4`: patch-level knobs that Vital, Surge and the Sound Lab can use).
- **Destinations** gain filter 2, each envelope's times and levels, and LFO rates and amounts.
- *Unlocks:* Vital, Surge, Matrix-6 (10-slot matrix), MS2000 (virtual patch), Synth1 modulation routings.

### F8. Layered instruments

- **A new resource, `AKLayered`** (decided), next to `AKPatch`. It holds `layers: [{patch, key_range, velocity_range, transpose, detune_cents, level_db, pan}]` and a mode (`stack`, `split`, `velocity_switch`). Each layer is an ordinary patch.
- **Players accept it wherever they take a patch.**
- *Unlocks:* M3R combinations (2,000 decoded, 8 timbres with key and velocity windows), D-50 upper/lower, CZ line modes 1+1' and 1+2' (or F3 inside one patch), Synthex-style double/split, Kontakt multi-group instruments.

### Out of scope

- Sample playback oscillators, vocoders, arpeggiators. Arpeggiators belong to the sequencer, not a patch.
- Drum-machine voices: the user excluded drum sampling, and synthesized drums are a separate question.
- Opsix-style filter or wavefolder operators: no patch data exists yet.

## Coverage matrix

**✓** converts directly today. **F*n*** needs that feature for an exact conversion. **(a)** part of the sound needs analysis whatever we build.

| Format | Have | Count | Direct today | Exact needs | Notes |
| --- | --- | --- | --- | --- | --- |
| Synth1 `.sy1` | – | thousands, free | **almost all** | F7 for some routings | 2 osc, FM, ring, sync, LP/HP/BP, 2 ADSR, 2 LFO, unison, chorus, delay. **Best first converter** |
| Helm `.helm` | – | hundreds | most | F4 (osc unison), F6 (step seq) | |
| OB-Xd / OB-Xf `.fxb` | – | hundreds | most | F5 (some) | Oberheim-style VA |
| TAL-NoiseMaker | – | hundreds | most | – | |
| Odin 2 `.odin` | – | hundreds | some | F2, F5, F6, F7 | |
| Vital `.vital` (JSON + tables) | – | thousands | basic patches | F2, F4 (osc unison, warp later), F5, F6, F7 | Tables load as wavetables directly |
| Surge XT `.fxp` (XML) | – | thousands (factory and third-party) | classic/sine/wavetable patches | F1, F2, F5, F6, F7 | Exotic oscillators by render + matcher |
| Juno-106 SysEx | – | many banks | most | F5 (HPF + LPF) | One DCO, sub, noise, PWM, one env, chorus |
| Prophet-5 / 600 | – | some | most | F5-later (poly-mod to cutoff) | |
| Matrix-6/1000 SysEx | – (SoundArchive) | ~1,000 | some | F2 (DADSR), F3 (tracking generator), F7 | |
| MS2000 / microKorg | – | many | most | F5, F7 | Vocoder left out |
| **M3R programs** | **2,000 decoded** (~950 distinct) | | **232 on basic waves, pending F2-m1 timing** | F2 (`m1` curves, time scaling), F4 (osc delay), F6 (`m1` MG) | Others: everything direct except the PCM wave **(a)** |
| **M3R combinations** | **2,000 decoded** | | – | F8 | |
| **DX7 / TX802 / TX816** | **256 rendered + params** | 27 packs on SoundArchive | **direct** (phase 2; ~66 dB SNR against msfa, median worst note) | F1, F2 (`dx7`), F3, F4 (ratio/fixed), F6 (`dx7`) | Reference: Dexed renders, checkable per voice |
| TX81Z / DX11 / DX21 | – (SoundArchive) | ~4,000 | approximate | DX7's list + F4 (OPZ waves) | |
| **Casio CZ** | **48 tones** (raw) | | – | F2 (`cz`), F3, F4 (PD), F8 or F3 for line modes | Parameter naming still to do |
| D-50 | – (SoundArchive) | ~8,000 | synth partials, partly | F2, F5, F8 | PCM partials **(a)** |
| Mirage disks | **30 converted** | | envelopes, filter, velocity | F2 (time scaling) | Wave **(a)**; 8-bit |
| SFZ / Kontakt / EXS / SF2 zones | **28 converted** | | envelopes, filter, velocity curve, key levels | F2 (delay/hold/shape) | Wave **(a)** |
| Recordings (Open Samples WAVs, Polynominal packs) | 1,370 entries | | – | – | Matcher only **(a)** |
| Closed plugins (Serum, Massive...) | – | – | – | – | Render via a plugin host + matcher **(a)** |

## Build order

The order weighs patches unlocked against work.

| Phase | Features | What it unlocks | Size |
| --- | --- | --- | --- |
| 0. Converters on today's engine | none | **Synth1**, Helm, TAL-NoiseMaker, OB-Xd (most of each), Juno-106 (minus HPF), sampler-zone envelopes and filters | Converters only |
| 1 (**built**) | **F2** envelopes v2 (generic stages and curves, time scaling, `dx7` mode) | M3R timing (once `m1` is measured), SFZ zones exact, Matrix-6, D-50 envelopes, groundwork for DX7 and CZ | Medium |
| 2 (**built**, DX7) | **F1 + F3 + F4** (ratio/fixed) + F6 `dx7` | **DX7 family exact** (checked against 256 Dexed renders), then TX81Z with F4 OPZ waves | Large |
| 3 | **F5** second filter, **F6** more LFOs and custom shapes, **F7** matrix v2 | Vital, Surge, Odin 2, MS2000, Juno HPF | Medium |
| 4 | **F4** phase distortion + F2 `cz` mode, **F8** layered instruments | CZ, M3R combinations, D-50 upper/lower | Medium |
| Later | F4 warp modes, F5 comb/formant/poly-mod | Vital and Prophet extras | – |

Phase 0 needs no engine work, but the user chose to build phase 1 first, so sampler-zone converters can use exact envelopes from the start.

## Converters

All live outside the addon, in the prep tool or a GAK ingestion tool. Each writes a patch and a comparison report.

| Converter | Input | Phase | Check against |
| --- | --- | --- | --- |
| Synth1 → AKPatch | `.sy1` text | 0 | Synth1 renders through a plugin host (optional), or by ear |
| Helm / TAL / OB-Xd → AKPatch | JSON / XML / `.fxb` | 0 | Plugin-host renders |
| Sampler zones → envelope, filter, velocity | `instrument.json` zones, Mirage analysis | 0 (partial), 1 (exact) | The zone's samples |
| M3R → AKPatch | `content.m3r_program.params` | 0 for structure, 1 for timing | Needs M3R recordings or a measured `m1` table |
| DX7 → AKPatch (**built**: `tools/patch_convert/dx7.gd`) | `content.dx7.params` | 2 | `render_msfa_v100.wav` (msfa engine), same keys and timings |
| TX81Z → AKPatch | SysEx (to fetch) | 2 | An OPZ emulator render (ymfm), if built |
| Vital / Surge → AKPatch | `.vital` JSON / `.fxp` XML | 3 | Plugin-host renders |
| CZ → AKPatch | 48 tone dumps (to name) | 4 | A CZ emulator, if one runs offline; else Polynominal's CZ recordings |
| M3R combinations → AKLayered | `content.m3r_combination.params` | 4 | – |

**Plugin hosting for reference renders.** Spotify's `pedalboard` or DawDreamer (both Python, GPL-3) can load a VST3 headless, apply a preset, and play the same held-note layout as `dx7render`. That gives references for phases 0 and 3 and covers closed formats. `pedalboard` is installed in its own venv at `D:\tools\pedalboard\venv` (outside the repo, never shipped). Hosting VSTs inside GAK at runtime is not recommended: Godot has no plugin hosting, it would tie games to per-platform native plugins, and the aim is sounds made in GAK.

## Decisions (2026-11-20)

1. **Build order:** phase 1 (F2) first, then the phase 0 converters.
2. **Oscillator limit:** 8.
3. **Source curve modes:** exact source models. `dx7` comes in phase 1, `cz` in phase 4, and `m1` once its timing is measured. The same goes for LFO models.
4. **Layered instruments:** a separate `AKLayered` resource.
5. **Plugin host:** `pedalboard` is installed now, at `D:\tools\pedalboard\venv`.
7. **Phase 2 (2026-11-20):** match msfa's FM engine (Apache-2.0), not Dexed's Mark I (GPL-3, can't be ported), using msfa-engine renders as references. Float operators with DX7 timing (very high SNR, not bit-identical). DX7 first; TX81Z/OPZ later. The converter lives in this repo and writes into the library. Plan: `docs/plans/synth-expansion-phase2.md`.
6. **`dx7` envelope scope:** a `dx7` envelope takes the operator's whole amplitude block (rates, levels, output level, rate scaling, keyboard level scaling, velocity sensitivity). msfa works in the log domain, where these shape the attack too, so only the whole block is exact.

## Archive log

| Archive | Surveyed | What's there | Fit | Status |
| --- | --- | --- | --- | --- |
| Open Samples (github.com/pumodi/open-samples) | 2026-11-20 | Kontakt/EXS/SF2 instruments, synth WAVs (Korg, Roland, Kawai), percussion | Analysis; partial direct (envelopes, filters) for sampler instruments | 28 instruments converted + 1,370 WAV entries (`D:\12_library\gak\processed`); marching percussion excluded |
| SoundArchive (soundarchive.co) | 2026-11-20 | SysEx banks (DX7 27 packs, TX81Z, D-50, Matrix-6), sampler disk images (Mirage, S-50, MPC60), drum WAVs | **Direct**: DX7 now; TX81Z, D-50, Matrix-6 later. Partial: Mirage | 256 DX7 factory voices rendered with parameters; 30 Mirage disks converted (`D:\12_library\gak\processed_soundarchive`) |
| Polynominal (polynominal.com) | 2026-11-20 | About 75 packs, mostly drum machines (out of scope) and ~20 synth recordings (Kontakt/WAV, Gumroad). Patch data: CZ-101 factory tones, M3R 1,200 patches (free on Gumroad), DX7 factory (duplicate). The Synthex "EPROM" is firmware, not presets | **Direct**: M3R, CZ. Analysis: CS20m (20 patches × 49 looped notes), Toccata, opsix, JV30, 01/W | M3R: 2,000 programs + 2,000 combinations decoded, every parameter named from the manual; CZ: 48 tones catalogued (`D:\12_library\gak\processed_polynominal`) |

### Format notes

- **M3R** (from the manual's MIDI exclusive pages): a program is 75 bytes:
  - 1 oscillator on one of 90 multisounds; numbers 76–80 are plain waveforms (232 programs use them);
  - pitch and cutoff MGs, each with wave, frequency, delay, intensity and key sync;
  - aftertouch and controller routing;
  - a pitch EG;
  - the VDF (lowpass) with key tracking and velocity, and its EG: attack, decay to a break point, slope to sustain, release, with per-segment key and velocity time switches;
  - the VDA, with an EG of the same shape.

  A combination has 8 timbres, each with its program, level, transpose, detune, pan, and key and velocity windows. Envelope units (0–99) are not given in seconds.
- **CZ-101**: a tone is 128 bytes (nibble-encoded):
  - line select and octave, detune and vibrato;
  - per line, a DCO waveform pair with DCW and DCA key follow;
  - an 8-step rate/level envelope each for DCO, DCW and DCA, with sustain and end steps;
  - ring and noise modulation.
- **DX7**: the voice has 155 parameters. All are named in each sidecar, and Dexed's engine (`dx7render`) gives a reference render for each voice.
