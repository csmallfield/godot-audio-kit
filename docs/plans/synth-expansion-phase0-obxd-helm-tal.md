# Synth expansion, phase 0: OB-Xd, Helm and TAL-NoiseMaker → AKPatch

Status: **converted** (2026-11-22; see "Converted"). All three libraries convert and are checked against the synths themselves. Part of `docs/plans/synth-expansion.md` (phase 0, after Synth1: `synth-expansion-phase0-synth1.md`).

## What's on disk

| Synth | Presets (`D:\12_library\gak\to_process\…`) | Format | Reference plugin (`D:\tools\…`) |
| --- | --- | --- | --- |
| OB-Xd | `OB-Xd\obxd-banks`: the 24 banks that shipped with OB-Xd, 3,072 slots, **1,174 distinct programs** (the rest are empty or duplicates); `OB-Xd\obxf-factory`: OB-Xf's **493** factory patches | `.fxb` (FBCh chunk: `<discoDSP>` XML, `Val_0`..`Val_79` per program) and `.fxp` (FPCh chunk: `<OB-Xf>` XML, named values) | `obxf\obxf_products\OB-Xf.vst3`, OB-Xf 1.0.3 (GPL-3, the Surge team's continuation of OB-Xd). OB-Xd 2.20 is not installed (its installer needs admin rights); the user chose OB-Xf for all references |
| Helm | `Helm\factory`: **274** factory presets (58 in Percussion, out of scope), CC-BY 4.0 | `.helm` JSON: `settings` with named values and a `modulations` list `{source, destination, amount}` | `helm\Steinberg\VstPlugins\helm64.dll` (VST2) or `helm\VST3\Helm\helm64.vst3`, Helm 0.9.0 |
| TAL-NoiseMaker | `TAL-NoiseMaker\factory`: 255 factory presets; `sci-fi-sensation`: TAL's free 32; **286 distinct** | `.vstpreset` (VST3 preset whose chunk is `<tal>` XML holding the whole bank; the preset is the program at `curprogram`) and `.noisemakerpreset` (the same XML) | `tal-noisemaker\TAL-NoiseMaker-64.dll` (VST2) or `.vst3` |

Each folder has a `SOURCES.txt`. Not downloaded (they need a login or an email): the TAL community banks on KVR and rekkerd (Noise4U, Emerge Suplement, Richard Semper, NoiseMachine) and the Helm packs on Gumroad.

All three plugins load in DawDreamer and play a note. OB-Xf is VST3 only, and DawDreamer's `load_preset` reads only VST2 `.fxp`, so references set OB-Xf's parameters one by one: its plugin parameters 0–101 are in the same order as the attributes of its `<OB-Xf>` XML. OB-Xd programs go through OB-Xf's own importer first (`src/state/ObxdImporter.cpp`: it rescales LFO rates, attack times and the sync-rate table so old banks sound as they did), ported to Python.

Sources for the parameter meanings: OB-Xd's `Source/Engine/ParamsEnum.h` and `PluginProcessor.cpp` (archive of github.com/reales/OB-Xd), OB-Xf's `src/` (github.com/surge-synthesizer/OB-Xf, e03452f), Helm's `mopo/src` and `src/` (github.com/mtytel/helm), TAL-NoiseMaker's open port in DISTRHO-Ports (`ports-juce5/tal-noisemaker`), all in `D:\tools\_downloads\`.

## Feature usage

Share of presets using each feature. "GAK" says what today's engine has: **yes**, **approx** (close, with a known difference) or **gap**.

### OB-Xd banks (1,174) and OB-Xf factory (493)

| Feature | OB-Xd | OB-Xf | GAK |
| --- | --- | --- | --- |
| Voice slop: per-voice offsets of envelope times, cutoff, glide and level (on by default in OB-Xd) | 100% | 89% | **gap** (the `random` source covers cutoff, pitch and level, not envelope times) |
| Per-voice pan (8 pan knobs, one per voice slot) | 62% | 66% | **gap** |
| Cross mod: osc 1 bends osc 2's **pitch in semitones** at audio rate (exponential FM) | 41% | 66% | **gap** (GAK's FM is phase modulation) |
| LFO (sine, square, S&H, summed when several are on) to pitch, PW, cutoff | 63% | 68% | yes; the summed shapes (4%, 24%) are a gap |
| Filter "warm" (saturation in the filter) | 42% | – | approx (ladder `drive`) |
| Brightness: a lowpass on the oscillators before the filter | 24% | 42% | **gap** (one filter per voice) |
| 24 dB mode with the pole morph (4 → 1 pole) | 20% | 9% | **gap** |
| OB-Xf's Xpander modes (15 pole mixes: LP, HP, BP, notch, phaser, combinations) | – | 27% | **gap** |
| 12 dB mode: LP → notch → HP morph, BP blend | 8%, 10% | 2%, 11% | type yes; the morph is a gap |
| Ring mod | – | 54% | yes |
| Hard sync, noise, unison, glide, legato, velocity, env to pitch and PW | 10–35% | 20–73% | yes |

### Helm factory (274)

| Feature | Share | GAK |
| --- | --- | --- |
| Distortion (soft clip 99%, else sine fold) | 91% | yes (`saturate`) |
| Reverb, delay | 78%, 26% | yes |
| Sub oscillator; its "shuffle" (a phase-offset copy) | 66%; 44% | sub yes; shuffle approx |
| **Oscillator feedback**: a comb filter tuned to the note (amount, transpose, tune) | 60% | **gap** |
| Per-oscillator unison | 56% | yes (`stack`) |
| Cross mod (each oscillator phase-modulates the other) | 52% | yes (`fm_from` both ways) |
| Waveforms: sine, triangle, square, saws; 3/4/8-step and 3/5/9-pyramid shapes | 34% sine; steps and pyramids 22% | yes (steps and pyramids as wavetable frames) |
| Filter: 12 dB with LP/BP/HP blend; shelves | 68%; 13% | blend endpoints yes; shelves **gap** |
| Modulation rows to destinations GAK lacks (resonance, cross mod, formant, osc feedback, LFO amplitude, envelope settings, delay time) | 27% | **gap** (matrix v2, F7) |
| Formant filter; stutter; step sequencer as a source | 6%; 7%; 6% | **gap** |
| LFO shapes beyond GAK's (steps, pyramids) | 3% | **gap** (custom shapes, F6) |

### TAL-NoiseMaker (286)

| Feature | Share | GAK |
| --- | --- | --- |
| Chorus (Juno-style, two modes); reverb; delay | 46%; 43%; 23% | yes |
| Master high-pass | 36% | **gap** as a voice filter; an effect would do (it's after the voices) |
| Master detune (analog drift per voice) | 36% | **gap** (voice slop) |
| **Drawn envelope**: a Bézier curve, tempo-synced, looped or one-shot, to cutoff, osc pitch, FM, ring mod or volume | 36% | **gap** (custom shapes, F6) |
| Filter LP 24 / 12; LP 6 and LP 18; BP, notch, HP 24; Moog LP 24 | 35%/17%; 17% + 14%; 17% | 12/24 yes; **6 and 18 dB gap** |
| Osc 2 FM (linear, depth follows osc 2's pitch, so a fixed index) | 25% | yes (phase-modulation index) |
| Ring mod, sync, sub osc (osc 3) | 20%, 20%, 36% | yes |
| LFO shapes: sine, triangle, saw, square, random step, smooth random | – | yes |
| Free AD envelope to PW, pitch, FM, cutoff | 25% | yes (an extra envelope in the matrix) |
| Vintage noise; osc bitcrusher | 16%; 7% | approx (noise osc; `crush` effect) |

## Engine features worth building first

Ranked by the share of all ~2,200 presets they unlock (with Synth1's 16,706 where they help it too):

1. **More filter types** (part of F5): a four-pole filter whose pole outputs are mixed (the OB-Xd pole morph, OB-Xf's Xpander modes, TAL's 6 and 18 dB lowpasses, Moog), a continuous LP → notch → HP and LP → BP → HP morph on the state-variable filter, and shelves. About 35% of OB-Xd/OB-Xf, 31% of TAL, 13% of Helm.
2. **Exponential (pitch) FM between oscillators**, besides phase modulation: OB-Xd and OB-Xf's cross mod (41%, 66%). A fixed-Hz linear mode in the same option is the follow-up noted for Synth1's FM (48% of Synth1 presets).
3. **Voice character**: per-voice slop (envelope times, cutoff, pitch, level) and per-voice pan by voice slot. Nearly every OB-Xd/OB-Xf patch, and TAL's master detune (36%). The effect on a note is small, but the references play successive notes on different voices, so they differ note to note.
4. **Custom shapes for LFOs and envelopes** (F6): TAL's drawn envelope (36%), OB-Xf's summed LFO shapes (24%), Helm's step and pyramid LFOs and its step sequencer (~9%).
5. **A pre-filter tone stage or a second filter** (F5): OB-Xd brightness (24%, 42% in OB-Xf). TAL's master high-pass (36%) needs only a `filter` effect after the voices.
6. **A tuned comb (oscillator feedback)**: Helm only, but 60% of it.
7. Later: matrix v2 destinations (F7, Helm 27%), the formant filter, stutter.

1–3 and 5 are small to medium; 4 is phase 3's F6. Without them, every preset still converts, approximately, as Synth1's did; the comparison shows how much each gap costs.

## Engine work (agreed 2026-11-21: all six)

Same promises as before: a patch without the new fields renders the same samples (native, GDScript, `describe()`), native = GDScript, live = baked. New fields enter `describe()` only when set.

1. **Filters.**
   - `ladder` gains `poles` (1–4, default 4: the lowpass taken after that many poles, a fractional value crossfading the two around it) and `pole_mix` (`[input, pole1, pole2, pole3, pole4]` weights, overriding `poles`: the Xpander's and OB-Xf's modes, highpasses and bandpasses from the same ladder). Resonance always feeds back from the fourth pole.
   - State-variable `mix` (`low`, `band`, `high` weights: LP → notch → HP and LP → BP → HP morphs) and shelves `lowshelf`, `highshelf`, `bandshelf` (`gain_db`, `q`). `slope_db = 24` cascades them, as the other types.
   - `pre_filter = {lowpass_hz, highpass_hz}`: one-pole filters on the filtered oscillators before the main filter (OB-Xd's brightness).
2. **FM modes.** An oscillator's `fm_mode`: `phase` (today), `pitch` (the source's output × `fm_index` semitones, added to this oscillator's pitch every sample: OB-Xd's cross mod) or `linear` (× `fm_index` Hz, through zero: Synth1's fixed-Hz FM). It applies to `fm_from` and the `fm` list.
3. **Voice character.**
   - `voice_pan = [p1, p2 ...]`: the pan of each voice slot (−1..1).
   - `slop = {pitch_cents, cutoff_octaves, env_time, level_db}`: each voice slot gets fixed offsets within ± these (seeded by the patch's `seed`), as OB-Xd's voices each have their own: pitch, cutoff, every envelope's times (× 1 ± `env_time`) and level.
   - Slots: new voices take slots in turn (round robin, as OB-Xd), the count being `voice_pan`'s length, or 8. Mono and legato patches always play slot 1.
4. **LFOs.** `lfo3` and `lfo4` (sources `lfo3`, `lfo4`; destinations `lfo3.rate`, `lfo4.rate`). Shape `custom`: `points` (2–256 values, −1..1, one cycle), `interp` (`linear` or `step`), `once` (after one cycle it holds the last point: TAL's drawn envelope in one-shot mode).
5. **Tuned comb.** `comb = {semitones, cents, feedback}` (−0.99..0.99): y = x + feedback · y[n − P], with P one period of the voice's current pitch moved by `semitones` and `cents` (Helm's oscillator feedback). On the filtered oscillators, before `pre_filter` and the filter. Periods up to 4,096 samples (12 Hz at 48 kHz), read with linear interpolation.
6. **A `filter` effect** after the voices: `{type = "filter", mode = "highpass" | "lowpass", cutoff_hz, q, slope_db: 6 | 12 | 24}` (TAL's master high-pass).

## As built (2026-11-22)

All six, in both engines, with the promise kept: the rich test patch, a mono patch (legato, stacks, sync, ladder, stages amp envelope, free synced LFO, chorus, synced ping-pong delay, phaser, saturation, arpeggiator), every shipped preset and twelve converted Synth1 patches (FM, unison 8, delay, chorus, ring, sync, synced LFOs, mod envelope, legato, noise, compressor, arpeggiator) hash the same before and after: native, GDScript and `describe()`.
- **Filters.** The ladder computes its four pole outputs only when `poles` or `pole_mix` is set; otherwise it runs the old code. The new state-variable types are Simper's: one generic output, `m0·x + m1·band + m2·low`, with the shelves' frequency warp; the old four types keep their own outputs. The pre-filter is two one-poles per channel.
- **FM modes** move the slot's increment for that sample (`d · 2^(m/12)`, `d + m/sr`) instead of the phase. A negative increment runs the phase backwards; the band-limiting uses its size.
- **Voice character.** The engine keeps a round-robin counter; each new poly voice takes the next slot. Slot offsets come from a 32-bit xorshift of the seed, slot and kind (`AKSynthCore.slot_rand`), the same in both engines. With `env_time`, a voice whose slot changes its times runs its own copy of the ADSR numbers (the time factor folded into the attack and decay lengths and the decay and release coefficients); stages envelopes multiply their stage lengths.
- **LFOs.** Four per patch; the engine runs lfo3 and lfo4 only when one is set (`n_lfo`), and a random shape there draws from the voice's random stream after lfo1 and lfo2, so a patch without them keeps its numbers. Custom shapes read their points at the control rate.
- **Comb.** The native engine keeps the lines in one pool allocated by `set_patch` (64 voices × 2 × 4,096), so nothing allocates on the audio thread.
- **Filter effect**, type 13, in `AKStreamFx` and `ak::Fx`.
- **Later the same day** (for the Synth tab's Flavor generator): `lfo3` and `lfo4` became `lfos`, up to lfo8, with random streams of their own; oscillators go to 16 and matrix rows to 32. The same 35 patches still hash the same.
- **Tests** (`tests/test_synth.gd`): poles 4 and `pole_mix [0, 0, 0, 0, 1]` equal the old ladder exactly, each pole takes about 18 dB off a tone three octaves up, the pole-mix high-pass; `mix` with `low = 1` or `high = 1` equals the low-pass and high-pass exactly, and each shelf boosts its side by 12 dB; pitch and linear FM play the expected frequencies, through-zero FM stays finite; voice slots alternate pans, slop pitches repeat after the slots wrap; a stepped custom LFO gates, a one-shot one ramps and holds, unread lfo3 and lfo4 change nothing; a comb with no feedback is transparent and one with feedback rings at the note's period; the pre-filter's slopes; the filter effect's slopes. Each also renders natively and in GDScript, which agree within 1e-6.

## Converted (2026-11-22)

Pipeline (see `tools/patch_convert/README.md`): the prep tool reads `.vstpreset`/`.noisemakerpreset`, `.helm` and OB-Xd `.fxb`/`.fxp` and OB-Xf `.fxp` (`osp/tal.py`, `osp/helm.py`, `osp/obxd.py`; OB-Xd programs go through a port of OB-Xf's importer); `render_vsynth.py` renders each synth itself through DawDreamer (TAL and Helm load the patch as plugin state, OB-Xf by parameter; all three play overlapping voices, unlike Synth1); `vsynth_batch.gd` converts (`tal.gd`, `helm.gd`, `obxf.gd`) and renders with GAK; `check_vsynth.py` compares. Drums left out (TAL's DR presets, Helm's and OB-Xf's percussion folders).

| Library | Patches | Level (median) | Envelope error median / p90 | Spectral error median / p90 | Without caveats: env / spec |
| --- | --- | --- | --- | --- | --- |
| TAL-NoiseMaker (`processed_tal`) | 259 | 0.0 dB | 2.26 / 4.89 dB | 4.37 / 7.98 dB | 0.25 / 1.04 dB (5 patches) |
| Helm (`processed_helm`) | 216 | −0.01 dB | 2.04 / 3.69 dB | 3.52 / 5.61 dB | 1.21 / 1.66 dB (28) |
| OB-Xd + OB-Xf (`processed_obx`) | 1,620 | 0.01 dB | 2.21 / 4.22 dB | 3.07 / 5.05 dB | 1.97 / 2.62 dB (1,007) |

OB-Xf isn't repeatable (random phases, detune, slop, S&H): a second OB-Xf render of 240 patches scores 2.10 / 2.85 dB against the first, GAK 2.33 / 3.11 on the same patches.

Engine additions the converters asked for, by how much they'd help:
1. **A start phase per oscillator** (all three; OB-Xf and TAL fake it with a pitch blip or phase modulation): the largest remaining envelope error.
2. **Band-limited hard sync** (382 OB-X sync patches alias under cross mod) and better oscillator anti-aliasing; clamping oscillator frequency at Nyquist (TAL's big pitch sweeps).
3. **The comb as a matrix destination** (Helm feedback sweeps, 13 patches), **mono envelopes restarting from zero** (Helm arps), a **self-oscillating 2-pole** (OB-Xf push, ~130 patches).
4. Reverb: damping past 0.4 (Helm, 128 patches, small effect), predelay, input filters, RT60 under 0.6 s (TAL). Delay: first-echo and loop filtering. Chorus: wet low-pass, triangle LFO.
5. A matrix source that multiplies two sources (vibrato = mod wheel × LFO; key × envelope), a constant source, pink/red noise, unison over 8 per stack, `level_env` on noise oscillators (skipped in the noise branch: a bug).

## Built since (2026-11-22)

From the list above, in both engines, each opt-in (older patches render as before) and used by the converters: oscillator `phase` / `phase_with`, `nyquist_clamp`, `level_env` on noise (the bug), `band_limited_sync`, `note_priority`, noise `color`, `comb.feedback` / `comb.pitch`, `retrigger_from_zero`, a row's `via` (a second source multiplying it), reverb `damp` to 2.5 with `predelay_ms`, `low_cut_hz`, `high_cut_hz`. The prep tool's TAL names are fixed. Converters now: Helm v3 (spectral 3.31 / 5.32 dB median / p90), OB-Xf v4 (3.05 / 4.90), TAL v5 (4.22 / 7.42). Band-limited sync reaches GAK's plain-saw polyBLEP floor; TAL keeps it off (TAL's own sync isn't band-limited).

## To do (on hold, 2026-11-22)

1. **A self-oscillating 2-pole filter**: OB-Xf's push and diode damping near self-oscillation (about 130 OB-Xf patches up to 5 dB quiet there).
2. **Unison above 8 copies per stack** (about 85 Helm and OB-Xf patches). Costs per-voice memory: MAX_SLOT doubles again.
3. **Cleaner oscillator anti-aliasing** (a higher-order BLEP): the polyBLEP floor now limits plain and synced saws alike, and OB-Xf adds a treble shelf to match. It changes every patch, so opt-in.
4. **Helm's remaining wishes**: formant x/y and unison detune as matrix destinations, a drive on the state-variable filter.
5. **Synth1's FM patches**: about 5 dB quiet with 7.2 dB spectral error (median, 400-patch subset). Linear FM was tried and is worse (`synth1.gd` FM_LINEAR); needs its own investigation before re-rendering the 16,706 references (about 5.5 hours).
6. **The DX7 voice-cost test** (16 voices under 15% of a core) runs at its limit when the whole suite runs under load (13.5–14% alone): find the small voice cost the extra LFOs added, or loosen the limit.
7. **OB-Xf's noise and the treble shelf**: the high shelf added for OB-Xf's brighter oscillators also lifts noise (about 1.9 dB); a per-oscillator shelf or keeping noise out of it.
8. **TAL's fx-alien-storm** (−14.5 dB from the start of the note; not aliasing, not sync).
