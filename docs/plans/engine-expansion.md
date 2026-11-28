# Engine expansion: acoustic sounds, SFX and the Surge effects

Status: in progress (started 2026-11-28). The status table at the end is the source of truth for
what's done; update it with each feature's commit.

## Why

Three things need more from the synth engine than it has:
- **The General MIDI bank**, rebuilt as 128 separate patches (it's 16 shared family patches now).
  The synth families are covered; the acoustic ones (pianos, guitars, plucked and bowed strings,
  reeds, pipes, choirs, sound effects) need string damping, attack layers, formants and inharmonic
  partials.
- **Game SFX** (the SFX page, later): material impacts, textures (rain, fire, crowds), sci-fi
  and magic sounds.
- **Conversions**: Helm's moving formant filter and Surge's string oscillator are approximated,
  and 18 of Surge's effects aren't converted at all (`tools/patch_convert/README.md`, Surge).

The aim is a robust engine: every feature below, not a minimal set.

## Rules for every feature

- **Off by default, and old patches don't move.** A new key absent means the engine runs exactly
  as before, so the presets, the GM bank, every saved patch and the 21,817 converted patches render
  as they did. `tests/test_synth.gd`'s stale-preset test and the parity tests catch a change.
- **Both engines.** Each feature goes into the C++ engine (`native/src/synth.cpp`, `fx.h`,
  parsed in `ak_synth.cpp`) and its GDScript twin (`addons/audio_kit/synth/synth_core.gd`,
  `dsp/stream_fx.gd`), the same steps in doubles, with a test holding them to the same samples.
  Effects that also run on buses get the bus class too (`ak_fx.*`).
- **Compiled once.** Patch keys are read in `AKPatch` (`synth/patch.gd`), which compiles them into
  the dictionary both engines read. Validation and clamping happen there.
- **Original code, or MIT/BSD ports with attribution.** GAK is Apache-2.0. Surge XT is GPL-3, so its
  effects are reimplemented from the idea, never ported. Airwindows (MIT) and Mutable Instruments'
  Clouds (MIT, what Surge's Nimbus is built on) can be ported, credited in `NOTICE`.
- **Documented** in `docs/synth.md` (patch keys) and, for effects, its Effects table; the Sound Lab
  panels expose the new keys where they fit (later pass if not).
- **Committed one feature at a time**, full test suite first.

## The features, in build order

### 1. Comb damping
`comb.damp_hz` (the note-tuned comb) and `comb_damp_hz` (the comb filter type): a one-pole
low-pass inside the feedback loop, so high harmonics die faster than low ones, as on a string
(Karplus-Strong). 0 = off. Plus `comb.damp_track` (0..1): the damping cutoff follows the note
(1 = proportional to the pitch, so every note decays alike). Matrix: `comb.damp` (octaves).

### 2. Release envelope
An envelope triggered by key-up instead of key-down: `{..., trigger = "release"}` on any envelope
(ADSR or stages). It runs once from the note-off, so an oscillator with `level_env` on it sounds
only on release (harpsichord jack, organ key click, piano damper). Built as a compile step: the
compiler turns it into a one-shot stages envelope flagged `trig`; the voice holds it at 0 (and again
on a mono retrigger) and starts it at release() with the stages' note-on event.

### 3. Oscillator drift
`drift = {cents, rate_hz}` on the patch (and per oscillator `drift_cents`): slow, smooth random
pitch wander, its own per voice and per oscillator, seeded, as analogue oscillators do. Distinct
from slop (fixed per voice slot) and the random LFO shapes (patch-wide sources).

### 4. Formant filter
Filter type `formant`: five resonant peaks (F1..F5) per vowel, with `vowel` 0..1 morphing through
a, e, i, o, u (interpolated frequencies, bandwidths and levels), `formant_shift` in semitones and
`formant_q`. Matrix `vowel` / `vowel2` (filter 2). Tables: the Csound manual's formant table
(bass, tenor, alto, soprano; `formant_set`). Helm's filter maps onto it (converter update pending).

### 5. Frequency shifter (effect)
`{type = "freqshift", shift_hz, mix, feedback, stereo}`: single-sideband shift by a Hilbert
transform (allpass pair network), every partial moved by the same Hz; `stereo` shifts the right
channel the other way. Also a bus effect `AKFreqShift`. Surge's frequency shifter maps onto it.

### 6. Rotary speaker (effect)
`{type = "rotary", speed (slow|fast), horn_hz, drum_hz, accel_s, drive, mix, spread}`: a two-way
Leslie: crossover, horn and drum rotating at their own rates with acceleration between slow and
fast, Doppler (modulated delays) and amplitude modulation, a little cabinet drive. Bus effect
`AKRotary`. Surge's rotary speaker maps onto it; GM organs use it.

### 7. Sample layer
Oscillator shape `sample`: plays an `AKSample` (a file or a recipe, rendered once) per note, pitched
by the note relative to its root (`track` 0..1: 0 plays at the root on every key, for noises), with
`start_s`, `oneshot`/`loop`, its own level envelope via `level_env`. Recipe sources keep it
licence-clean (hammers, picks, breaths, bow noise, the GM sound effects).

### 8. Modal resonators and inharmonic partials
Oscillator shape `partials`: up to 32 sine partials with their own `ratio`, `level` and
`decay_s` (and a `stretch` term for piano inharmonicity, ratio_n = n * sqrt(1 + B n^2)).
And the resonator form: shape `modal` with `material` presets (wood, metal, glass, stone, skin,
bar, plate) or explicit modes, excited by an impulse or by the oscillators routed into it
(`excite = "self" | "mix"`), for struck sounds. Bells, mallets, pianos, steel drums, impacts.

### 9. Granular texture oscillator
Oscillator shape `grains`: a cloud of short windowed grains from a source (an oscillator shape,
noise, or an `AKSample`), with `density` (grains/s), `grain_ms`, `jitter` (time), `spray`
(pitch), `pan_spread`, `envelope` (hann, tri, perc), seeded. Rain, fire, crackle, water, crowds,
debris; evolving pads.

### 10. Effect-parameter modulation
Matrix rows whose destination is an effect setting: `fx2.cutoff_hz`, `fx1.mix`, `fx3.shift_hz`...
(the effect's index in `effects`, then its key; units as the key's range, octaves for frequencies).
Effects run once on the summed output, so only patch-wide sources reach them: LFOs that are
`free`, macros, the mod wheel, aftertouch, bend, and the newest voice's envelopes (as a mono synth
does). Wah, filter sweeps, a growing echo; Surge's and Helm's effect modulation.

### 11. Stutter (effect)
`{type = "stutter", rate (note length), resample, softness, mix}` as Helm's: repeats the last slice
of audio at a tempo-synced rate, optionally resampled (pitched) and with soft edges. Glitch,
game SFX.

### 12. The Surge effects GAK lacks
Original implementations, each a patch/recipe effect and, where it suits a bus, a bus effect:

| Surge effect | GAK effect | Notes |
| --- | --- | --- |
| frequency shifter | `freqshift` (5) | |
| rotary speaker | `rotary` (6) | |
| ring modulator | `ring` (exists) | converter mapping only |
| conditioner | `conditioner` | bass/treble shelves, width, a soft-knee limiter with attack/release |
| graphic eq | `geq` | 11 octave bands, 12 dB each |
| resonator | `resonator` | 3 resonant band-passes (freq, Q, gain) in parallel or series |
| exciter | `exciter` | high-passed harmonics generated and mixed back |
| ensemble | `ensemble` | a 3-phase BBD string-ensemble chorus |
| combulator | `combulator` | 3 tuned combs with feedback and a noise/tone mix |
| tape | `tape` | saturation with hysteresis-like memory, wow and flutter, head-bump EQ, loss |
| treemonster | `treemonster` | pitch-tracking ring modulation |
| waveshaper | `waveshaper` | selectable curves (soft, hard, fold, sine, asym, digital), pre/post filters |
| mid-side tool | `midside` | M/S gains and EQ, width |
| spring reverb | `spring` | dispersive allpass chain with a chirp, decay, tone |
| bonsai | `bonsai` | bass boost and saturation, tape-style |
| chow | `chow` | a heavy asymmetric distortion with a threshold and a ratio |
| neuron | `neuron` | a feedback network of delays and nonlinearities (an original take) |
| nimbus | `granular` (fx) | a port of Clouds' granular mode (MIT) |
| airwindows | `airwindows` | ports of the Airwindows algorithms Surge offers (MIT), added in groups, the ones Surge patches use first |
| vocoder, audio input | – | need live audio input; out of scope |

Then the Surge converter maps onto them (a converter run happens on the library's machine).

## Where things go (notes for whoever picks this up)

- **Patch keys** are read and compiled in `AKPatch._compile*` (`synth/patch.gd`); new exported
  properties also go in `describe()` (only when set, so bake keys don't move).
- **The compiled dictionary** is parsed for C++ in `native/src/ak_synth.cpp` (`parse_filt`, the
  patch fields) into `SynthPatch` (`synth.h`); GDScript reads it in `AKSynthCore._set_extras`
  and the voice (`synth_core.gd`).
- **Matrix destinations**: append to `AKPatch.DESTS`, the `D_*` enums in `synth_core.gd` and
  `synth.cpp` (keep the order, bump `N_DST` in `synth.h`), handle them in both control loops
  (GDScript: before the `dst >= D_FB` branch), add a range to `patch_editor.gd` `MOD_RANGES` and
  offer them in `mod_destinations()`.
- **Filters**: a type is an `F_*` enum value in both engines and an entry in `AKPatch.FILTERS`;
  `FiltState::control` / `tick` (C++) and `AKSynthCore._Filt` (GDScript). In GDScript, filter 1
  of the comb and formant types runs through the voice's `f1x`; other types run inline.
- **Effects**: `Fx::Type` and its process code in `native/src/fx.h`; `AKStreamFx` `TYPES`,
  `DEFAULTS` and process code in `dsp/stream_fx.gd`; bus classes in `native/src/ak_fx.*`
  (registered in `register_types.cpp`); `tests/test_breadth.gd` holds native to GDScript.
- **Tests**: `tests/test_synth.gd` `_parity()` renders a patch both ways (needs the native core:
  `cd native && scons platform=linux target=template_debug`).

## Status

| # | Feature | Status | Commit |
| --- | --- | --- | --- |
| 1 | Comb damping | done | 29f9088 |
| 2 | Release envelope | done | 29f9088 |
| 3 | Oscillator drift | done | 29f9088 |
| 4 | Formant filter | done | see git log |
| 5 | Frequency shifter | | |
| 6 | Rotary speaker | | |
| 7 | Sample layer | | |
| 8 | Modal resonators, partials | | |
| 9 | Granular oscillator | | |
| 10 | Effect-parameter modulation | | |
| 11 | Stutter | | |
| 12 | Surge effects (16 + granular + Airwindows) | | |
| – | Converter updates (Helm formant, Surge string/effects) | | |
