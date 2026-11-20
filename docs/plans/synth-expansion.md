# Synth expansion: plan

Status: **draft for discussion.** Nothing here is built yet. This file grows as more archives are surveyed (see [Archive log](#archive-log)). Work on the engine starts only once the user agrees the scope.

## Goal

A personal library of **synthesized** GAK instruments, made from sample and patch collections. They are kept outside the repo and sorted with light metadata and tags. `tools/open_samples_prep` turns each collection into neutral data: WAVs, SFZ/DecentSampler mappings, renders, and an `instrument.json` per instrument. GAK's ingestion then turns that data into `AKPatch` patches, and the library is reprocessed whenever ingestion improves.

The question this plan answers: **what must the GAK synth gain so that as many sources as possible become good patches, ideally by direct conversion?**

## Principles

- **Direct conversion first.** Where a source holds the synthesis parameters themselves (a DX7 voice, a CZ patch, an analog patch sheet, the envelopes and filter of a sampler zone), translate them into the patch exactly. Resynthesis by analysis (the sample matcher) is the fallback for what has no parameters: recordings, PCM ROMs, missing pieces.
- **Analysis checks direct conversions.** Every directly converted patch is rendered and compared with a reference: the source's own render (Dexed for DX7), or its samples. The comparison is part of the converter's report. When a translation is lossy, the matcher may refine it, starting from the direct values.
- **Grow the engine where it pays.** A new feature earns its place when it lets a family of sources convert directly. Families with hundreds of DX7 or TX81Z voices count for more than one-off oddities.
- **Old patches keep sounding the same.** New fields default to today's behaviour. Existing `.tres` patches, recipes and bakes don't move.
- **Live and baked stay one.** Every feature goes into the native core (`AKSynthStream`, AKNative kernels) and the GDScript mirror (`addons/audio_kit/dsp/`), and their renders agree as they do today (`docs/synth.md`).
- **Patches stay text.** New features are readable fields, as now: no opaque blobs.
- **No sample playback.** The library is synthesized. Wavetables made *from analysis* are fine (the engine already has them); playing back the source recordings is not the aim.

## The engine today (`AKPatch`, `docs/synth.md`)

- **Oscillators:** up to 4: sine, triangle, saw, square, pulse, noise, morph, and wavetable. Each has level, semitones and cents.
- **Modulation between oscillators:** each oscillator can take phase modulation from **one** other (`fm_from` / `fm_index`, feedback through self or an earlier one), plus hard sync and ring modulation.
- **Filter:** one state-variable filter (LP/HP/BP/notch, 12/24 dB) or a 24 dB ladder.
- **Envelopes:** 3 ADSR envelopes (amp, env2, env3), shared by every oscillator. The amp envelope has an optional second release stage.
- **Modulation:** 2 LFOs (with delay, phase, free-running) and a 16-row modulation matrix, whose sources include velocity, key, mod wheel and aftertouch. Per-oscillator destinations are pitch, level, fm, width and position.
- **Voice:** unison, spread, glide, bend range, global velocity sensitivity and curve, a key-to-level table, and an effects chain.

## What the sources need

| Source family | Example | What it holds | Direct conversion needs | Now |
| --- | --- | --- | --- | --- |
| 6-op FM (DX7, TX802, TX816) | SoundArchive DX7 factory ROMs, 256 voices (rendered, with full parameters) | 155 parameters per voice | 6 operators, 32 algorithms (several modulators per operator), a 4-rate/4-level envelope per operator, keyboard level and rate scaling, per-operator velocity and amp-mod sensitivity, fixed frequency, feedback depth, pitch envelope, DX7 LFO | Approximate only: 4 ops, 1 modulator each, shared ADSRs |
| 4-op FM (TX81Z, DX11, DX21/27/100, YS200) | SoundArchive TX81Z banks (not fetched yet) | 4-op voices; TX81Z adds 8 operator waveforms and fixed frequencies | 8 algorithms (a subset of the 6-op graph), **operator waveforms** (half-sine and the other OPZ shapes), per-operator envelopes, the TX81Z's finer frequency steps | Algorithms mostly fit; waves and envelopes don't |
| Altered FM (Korg opsix) | Polynominal opsix pack (Kontakt, recordings only) | Recordings; the opsix's own patch format isn't in the pack | Operators that can be a filter, ring modulator or wavefolder; 40 algorithms | Analysis only |
| Phase distortion (Casio CZ) | Polynominal CZ-1/CZ-101 packs (recordings) | Recordings; CZ SysEx patches exist elsewhere | **Phase-distortion oscillator** (the CZ shapes, with DCW depth), **8-stage envelopes** with sustain and end points (DCO, DCW and DCA), line select, ring and noise mod | No PD; ADSR only |
| Analog subtractive | Polynominal Yamaha CS20m (980 looped notes, 20 patches), Elka Synthex, Crumar Toccata; Open Samples synth WAVs | Recordings, plus manuals with the panel parameters | Mostly fits. Possibly two filters (series/parallel, HPF into LPF), a sub/sine oscillator (a 5th oscillator, or a level on one), keyboard filter tracking (the matrix `key` source covers it) | Mostly covered |
| PCM / ROMpler / LA (Roland JV30, D-50, Korg 01/W, M3r) | Polynominal JV30, 01/W, M3r 1200 patches; Open Samples JV-2080 WAVs | Recordings; D-50 SysEx on SoundArchive | The synth half (TVF/TVA envelopes, filter, LFOs) converts directly from SysEx. The PCM attack and loop waves can't; at best a wavetable or noise burst found by analysis | Analysis only |
| 8-bit samplers (Ensoniq Mirage) | SoundArchive Mirage factory library, 30 disks (converted) | 8-bit samples, plus each program's filter, envelopes and velocity settings | **Partial direct conversion**: filter type, cutoff, key tracking, filter and amp envelopes with their key and velocity tracking map onto the patch; the oscillator is found by analysis | Envelope, filter and velocity map today |
| Sampler instruments (Kontakt, EXS, SF2) | Open Samples (28 converted) | Zones and samples, plus amp/filter envelopes, LFOs and velocity curves in SFZ | Same partial route as the Mirage. Key-to-level, velocity curve, envelopes and filter are direct; the tone comes from analysis | Mostly maps today |

## Expansion features, in priority order

Each item says which sources it unlocks for direct conversion. The order follows how many voices each one converts.

1. **An operator graph instead of a single `fm_from`.**
   - Up to 6 oscillators, perhaps 8 for headroom.
   - Each oscillator can take modulation from any set of others, each with its own depth, plus a feedback depth.
   - Named algorithm presets (DX7 1–32, TX81Z 1–8) that just fill in the graph.
   - Today's `fm_from` / `fm_index` stays as the one-modulator shorthand.
   - *Unlocks: all DX7/TX/DX voices.*
2. **Per-oscillator envelopes and multi-stage envelopes.**
   - An envelope with N rate/level stages, a sustain point, an optional loop, and release stages after key-off. DX7 4-stage, CZ 8-stage and D-50 5-stage envelopes are all instances of it.
   - Each oscillator may have its own level envelope. When none is set, the shared amp envelope applies as today.
   - The DX7's own rate and level curves (its "EG rate" in seconds, its level steps) would come as a curve mode, so translated values are exact rather than fitted.
   - *Unlocks: DX7, TX, CZ; D-50 TVA/TVF.*
3. **Per-oscillator keyboard and velocity scaling.**
   - Level scaling: break point, left and right depth, curves (−/+ linear and exponential).
   - Rate scaling: envelopes faster up the keyboard.
   - Velocity sensitivity and amp-mod sensitivity per oscillator.
   - *Unlocks: DX7 and TX voices sounding right across the keyboard, not only at the rendered keys.*
4. **Fixed-frequency oscillators and fine ratios.**
   - An oscillator that ignores the key (a frequency in Hz), and exact frequency ratios such as 1.41 or 3.5, not only semitones and cents.
   - *Unlocks: DX7/TX bells and percussion, which use them heavily.*
5. **Pitch envelope.**
   - A multi-stage envelope on pitch, in semitones, as a voice-level field (the matrix can already route `env2` to pitch, but not with DX7 shapes and levels).
   - *Unlocks: DX7, CZ.*
6. **Operator waveforms.**
   - The TX81Z/OPZ set (sine, half-sine, absolute sine, quarter-sine and the others) as oscillator shapes.
   - *Unlocks: TX81Z, DX11, YS200.*
7. **Phase-distortion oscillator.**
   - A shape with a distortion amount (the CZ's DCW), driven by its own envelope: saw, square, pulse, double sine, saw-pulse and the resonance shapes.
   - *Unlocks: Casio CZ (CZ SysEx would need finding; Polynominal has recordings only).*
8. **Second filter.**
   - Series or parallel, with its own type and cutoff.
   - *Unlocks: analog synths with HPF+LPF (CS20m-style), D-50-style setups, and some sampler instruments with two filters.*
9. **DX7 LFO model.**
   - The DX7's LFO speed curve, delay ramp, key sync and its six waves (sample-and-hold included). Pitch and amp mod depth go through each operator's sensitivity.
   - Mostly a mapping on top of today's LFOs, plus the per-operator amp-mod routing from item 3.

10. **Layered instruments.**
    - Two (or more) patches as one instrument: stacked or split by key range, each with its own detune and level.
    - Probably a small resource next to `AKPatch` rather than more fields in it.
    - *Unlocks: D-50 upper/lower, ROMpler layers, and analog play modes like the Synthex's double/split, once such presets are found.*

Later or undecided:
- Operators that act as filters or wavefolders (opsix).
- Drum-synthesis voices for the analog drum machines (out of scope today).
- Raising `MAX_OSC` past 6.

## Direct converters to build (after the engine work)

All live outside the addon, in the prep tool or a GAK ingestion tool. Each writes a patch plus a comparison report.

| Converter | Input | Output | Check against |
| --- | --- | --- | --- |
| DX7 → AKPatch | `instrument.json` `content.dx7.params` (or `voice.syx`) | An exact patch, once items 1–5 and 9 exist; approximate before | `render_v100.wav` (Dexed), same keys and timings |
| TX81Z / DX21 → AKPatch | 4-op voice banks (SoundArchive) | Exact once item 6 also exists | A render from an OPZ emulator (ymfm), if one is built |
| Sampler zones → AKPatch envelope, filter and velocity | `instrument.json` zones: `amp_envelope`, `filter`, `filter_envelope`, `amp_veltrack` and `amp_velcurve_*` opcodes, `lfos`, plus Mirage's key and velocity tracking from `cwm/analysis.txt` | Those parts of a patch, direct; the matcher fills the oscillator | The zone's samples |
| CZ → AKPatch | 48 CZ-101 tone dumps (Polynominal, downloaded) | Exact once items 2 and 7 exist | A CZ emulator render, if one can be run offline; else Polynominal's CZ-101 Kontakt pack (17 patches) |
| M3R → AKPatch | 2,000 decoded M3R programs (`processed_polynominal`, `content.m3r_program.params`), about 950 distinct | **232 on plain waveforms** (saw 147, sine 41, square, 10%/20% pulse): fully direct into today's engine. Oscillator, VDF lowpass with key tracking and its envelope, VDA envelope, pitch envelope, two MGs (LFOs), aftertouch and velocity routing. The rest: everything but the PCM wave direct; the wave from analysis or an analysis-made wavetable | Needs M3R recordings or an emulator. Envelope times are in 0–99 units whose curves the manual doesn't give: they'd have to be measured, or found in M1-family references |
| M3R combinations → layered instrument | 2,000 decoded combinations (single, layer, split, velocity switch, multi; 8 timbres each with key and velocity windows, transpose, detune, pan) | Item 10, directly | Same as above |
| Analog patch sheets → AKPatch | Hand-entered panel settings from manuals | Direct starting patch | The pack's recordings |

## VST plugins and other synth formats

The pipeline now has two patterns that carry over to plugins:
- **Decode a format and keep every parameter** (DX7, M3R, CZ).
- **Render a patch through an engine into held notes with known timings** (dx7render), so the matcher and the comparison reports can use it.

There are three ways to bring plugins in.

1. **Direct converters for open preset formats (preferred).** Several free synths store presets as readable text with documented parameters. Many map onto the GAK engine, today's or expanded, almost 1:1:

   | Synth | Preset format | Engine | Fit |
   | --- | --- | --- | --- |
   | Synth1 (Daichi) | `.sy1`, plain text parameter list | 2 oscillators, filter, 2 envelopes, 2 LFOs, FM/ring/sync, arpeggiator, effects | **Today's engine.** Thousands of free presets in circulation; the biggest single source of analog-style patches |
   | Vital (Matt Tytel) | `.vital`, JSON including its wavetables | 3 wavetable oscillators, 2 filters, 6 envelopes, 8 LFOs, a modulation matrix | Mostly today's engine (wavetable oscillator, matrix). Needs more envelopes and LFOs and the second filter (item 8); its wavetables load as tables directly |
   | Helm (Matt Tytel) | `.helm`, JSON | 2 oscillators + sub, filter, envelopes, step sequencer | Today's engine, nearly 1:1 |
   | Surge XT | `.fxp` with an XML patch inside | 3 oscillators × many types, 2 filters, 2 scenes, many envelopes and LFOs | Partly: classic, sine, FM2/FM3 and wavetable oscillators map; the rest via render + matcher |
   | Odin 2, OB-Xf/OB-Xd, TAL-NoiseMaker | XML / `.fxb` | Virtual analog | Today's engine, plus item 8 for some |
   | Dexed | `.syx` (DX7) | DX7 | Already decoded and rendered (items 1–5) |
   | Closed formats (Serum, Massive, Sylenth...) | Proprietary binary | — | Render only (route 2) |

2. **Offline rendering through a plugin host.** For plugins whose presets can't be read, or to make reference renders for direct conversions: load the plugin (VST3, or VST2 where you have it) headless, apply a preset, play the same held-note layout as dx7render, and write WAVs plus a sidecar.
   - **Spotify `pedalboard`:** Python, GPL-3, hosts VST3/AU instruments and renders MIDI.
   - **DawDreamer:** Python, GPL-3, VST2/VST3 with presets and MIDI.
   - Either needs installing (pip) and the plugins themselves; your call, per plugin. Renders feed the matcher like any recording.
3. **Hosting VSTs inside GAK at runtime.** Not recommended. Godot has no plugin hosting. It would tie games to native, per-platform plugins, and it goes against "synthesized in GAK". Routes 1 and 2 bring the sounds in as GAK patches instead.

Other hardware patch formats worth a decoder, all documented SysEx, mostly on SoundArchive or similar archives:
- **Analog, direct into today's engine:** Roland Juno-106 and JX-8P, Oberheim Matrix-6/1000, Sequential Prophet-5/600, Korg Poly-800.
- **Virtual analog:** Korg MS2000/microKorg (needs item 8 and the vocoder left out).
- **LA synthesis:** Roland D-50 (the synth half direct; item 10 for upper/lower).
- **FM:** Yamaha TX81Z/DX11 (item 6), Yamaha FB-01.

## Questions for the user

1. **How many operators?** 6 covers the DX7. 8 gives room for stacked layers and opsix-style patches at a CPU cost (32-voice polyphony with 8 operators is roughly 4× today's two-oscillator patch). Recommendation: 6.
2. **Exactness or simplicity for DX7 envelopes?** Exact DX7 curve modes (recommended, since you prefer direct conversions), or generic multi-stage envelopes plus fitting.
3. **Second filter:** now, or after FM?
4. **Phase distortion:** CZ-101 factory patches exist (Polynominal). Move it up, right after the FM items?
5. **Layered instruments (item 10):** a separate resource, or more fields on `AKPatch`? The M3R's 2,000 combinations now give concrete data for it.
6. **Plugins:** start with direct converters for Synth1 and Vital presets? Install `pedalboard` for reference renders?

## Archive log

| Archive | Surveyed | What's there | Fit for GAK | Status |
| --- | --- | --- | --- | --- |
| Open Samples (github.com/pumodi/open-samples) | 2026-11-20 | Kontakt/EXS/SF2 instruments, synth WAVs (Korg, Roland, Kawai), percussion | Analysis. Partial direct (envelopes, filters) for sampler instruments | Converted: 28 instruments + 1,370 WAV entries (`D:\12_library\gak\processed`) |
| SoundArchive (soundarchive.co) | 2026-11-20 | SysEx banks (DX7 27 packs, TX81Z, D-50, Matrix-6), sampler disk images (Mirage, S-50, MPC60), drum WAVs | **Direct**: DX7 (and later TX81Z, D-50, Matrix-6 SysEx). Partial: Mirage | Pilot done: 256 DX7 factory voices rendered with parameters, 30 Mirage disks converted (`D:\12_library\gak\processed_soundarchive`) |
| Polynominal (polynominal.com) | 2026-11-20 | 75 pages: about 47 drum machines, about 20 synths, 4 samplers, Atari ST speech. Packs are Kontakt (24-bit/44 kHz) or WAV one-shots, sold or free through Gumroad, with user and service manuals. **Patch data, linked directly on the pages:** `casio-cz101-factory-patch.zip` (CZ-101 factory patches), `ELKA_Synthex_EPROM.zip` (the Synthex's preset memory), `DX7-factory-patch.zip` (DX7 factory voices, which SoundArchive already gave us). Through a free Gumroad link: **Korg M3r, 1,200 patches in SysEx** (20 banks) | **Direct**: CZ-101 patches (needs items 2 and 7). The Synthex EPROM turned out to be firmware (see *New ideas* below). Partial direct: M3r SysEx (envelopes and filter; its PCM waves need analysis). Analysis: **CS20m** (20 patches × 49 notes, looped, analog), Crumar Toccata, opsix (all its samples are at C; recordings only), JV30, 01/W. Drum machines are out of scope. Licence: royalty free for music and sound design; some sampler packs "may not have clearance" | Downloaded to `D:\12_library\gak\to_process\Polynominal` (originals in `_dl/`): CZ-101 patches, the Synthex EPROM, the M3R banks (which you fetched from Gumroad) and the M3R manual. **Processed** to `D:\12_library\gak\processed_polynominal`: 2,000 M3R programs (1,044 duplicates marked; 232 on plain waveforms, tagged `basic-wave`) and 2,000 combinations, all named from the manual's tables (pp. 86–95), plus 48 CZ tones kept as raw tone data (status `decoded`) |

### New ideas from the Polynominal survey

- **CZ phase distortion now has data** (downloaded to `D:\12_library\gak\to_process\Polynominal\Casio CZ-101\Factory Patches`). The files are 48 standard CZ-101 single-tone dumps: 32 factory presets, named in the file names (Brass Ens.1, Elec.Piano, Synth.Bass, Fat Bass, Carillon...), and 16 internal tones. Each is 264 bytes: header `F0 44 00 00 70 20 60`, then 128 bytes of tone data sent as low/high nibbles, then `F7`. A CZ tone has:
  - line select (1, 2, 1+1', 1+2') and octave;
  - line detune and vibrato;
  - per line, a DCO waveform pair, and a DCW and DCA with key follow;
  - an 8-step rate/level envelope each for DCO, DCW and DCA, with sustain and end steps;
  - ring and noise modulation.

  This makes item 7 (phase-distortion oscillator) and the 8-stage envelopes of item 2 direct conversions, not just analysis targets. Item 7 should probably move up, next to item 6.
- **The Synthex files are firmware, not presets.** `ELKA_Synthex_EPROM.zip` holds the 6502 CPU's program EPROMs. Its README documents the memory map and the swapped address and data lines. A Synthex keeps its presets in battery-backed RAM, so these files very likely contain none. They're not a usable source; recordings or a RAM dump would be needed.
- **Play modes: layer and split.** The Synthex (double/split), the D-50 (upper/lower) and many ROMplers combine two patches. Rather than growing one patch, GAK could get a small "layered instrument" (two patches with key ranges or a stack, and detune). *New item 10.*
- **Opsix-style operators** (filter, wavefolder, ring operators) stay on the later list: the opsix pack has recordings at C only, and no patch data.
