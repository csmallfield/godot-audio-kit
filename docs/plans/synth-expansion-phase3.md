# Synth expansion, phase 3: a second filter, macros, envelope-time modulation (F5, F6, F7)

Status: **built** (2026-11-23): see "As built" at the end. Part of `docs/plans/synth-expansion.md`. Phases 0, 1 and 2 are built.

## Where phase 3 stood

Much of it came with phase 0's converters:

- **F6, LFOs v2: built.** Eight LFOs (`lfo1`, `lfo2`, `lfos`), custom shapes (`points`, linear or step, one-shot), and phase 2's `dx7` LFO. Left: the M3R's `m1` LFO, which waits on measured timing, as its envelopes do.
- **F7, matrix v2: mostly built.** 32 rows; every envelope and LFO as a source, the mod wheel and aftertouch; LFO rates as destinations; a second source multiplying a row (`via`).
- **F5, second filter: not started.** Phase 0 added a one-pole pre-filter and a filter effect after the voices, not a second voice filter.

## What this phase builds

### F5. `filter2` and routing

- **`filter2`**, with the main filter's types and fields: lowpass, highpass, bandpass, notch (12 or 24 dB), the ladder (`poles`, `pole_mix`, `resonance`, `drive`), the state-variable `mix` and the shelves (`gain_db`). Empty (the default): off. The main filter's extras stay on filter 1 only: the diode damping, saturation, the pre-filter and the comb.
- **`filter_routing`**: `series` (default: filter 1, then filter 2) or `parallel` (each oscillator into one or both, the two summed).
- **Per oscillator, `filter`**: `1`, `2`, `both` or `none`.
  - Series: `1` or `both` goes through filter 1 and then filter 2; `2` goes into filter 2 only; `none` goes around both.
  - Parallel: `both` (the default) feeds both; `1` or `2` feeds one.
  - `filtered: false` is `none`, as today.
- **Matrix destinations** `cutoff2` and `q2`. A voice slot's cutoff slop moves both filters.
- *Unlocks:* Odin 2's dual setups, Vital and Surge's two filters, and sampler instruments with two filters.

### F7. The rest of the matrix

- **Macros:** `macros = [m1, m2, m3, m4]` (0..1, default 0) on the patch, as sources `macro1` to `macro4`. They are patch values, so a host (the Sound Lab, a game) moves them by editing the patch, which keeps held notes. Live controls like the mod wheel's (events, recording, MIDI) can follow if needed.
- **Envelope times:** destinations `env1.time` to `env8.time`, in octaves of time (+1 doubles every stage's time). Read as each stage starts, as slop and key scaling are, so they work on `stages` envelopes (what the converters write; an ADSR can be written as stages). Not on classic ADSR or `dx7` envelopes.
- **Not built, and why:** envelope levels and LFO amounts as destinations. A row's `via` (a second source multiplying it) already gives "this envelope's or LFO's amount, moved by that source", which is how Vital, Surge and the Matrix-6 use them.

## Promise (as phases 1 and 2)

- **Old patches keep their samples.** A patch without the new fields renders the same samples, natively and in GDScript (the before/after hashes). New fields enter `describe()` only when set.
- **Both engines agree** within 1e-6 on the new features.

## Converters

Surge XT (downloaded 2026-11-23, 3,008 patches) comes first; Odin 2 and Vital are parked (2026-11-23: the library is already larger than anyone could play); docs/plans/manual-downloads.md says what each would need. Juno-106 and the Korg MS2000 are out of consideration (2026-11-23): no free plugin to check against.

## As built (2026-11-23)

- **Native:** the filter's fields became `SynthPatch::Filt` (filter 1 and filter 2) and its voice state `FiltState`, used for both; filter 1 renders the same samples (the 35 before/after hashes match). **GDScript:** filter 1 stays inline for speed; filter 2 runs through `AKSynthCore._Filt`, the same arithmetic.
- **Tests:** `test_filter2` (series high-pass after low-pass, parallel routes kept apart, both engines in series with a ladder and in parallel with `mix`); `test_macros_and_env_time` (a macro opening the cutoff; velocity on `env1.time` doubling an attack; both engines with macros, envelope times and a `via` row).
- **Not done:** the Sound Lab's patch editor has no controls for `filter2`, `filter_routing` or `macros` yet (patches and converters set them).
