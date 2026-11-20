# Synth expansion, phase 2: the DX7 family (F1, F3, F4, F6 `dx7`)

Status: **built** (agreed 2026-11-20). See "As built" at the end. Part of `docs/plans/synth-expansion.md`. It follows phase 1 (`synth-expansion-phase1.md`, built).

## Decisions (2026-11-20)

- **Reference: msfa.** Dexed's "Mark I" engine, which made the existing 256 renders, is GPL-3 and can't be ported into Apache-2.0 GAK. msfa's own FM engine (Dexed's "Modern" engine) is Apache-2.0. `dx7render --engine msfa` renders it, and those renders are the target. Each voice gains a `render_msfa_v100.wav` beside its Mark I render; existing files are not touched.
- **Exactness: float plus DX7 timing.** Operators stay float. Wherever msfa's integer behaviour changes the sound, GAK copies it:
  - integer phase increments;
  - pitch, LFO and envelope steps every 64 samples;
  - feedback from the average of the last two outputs;
  - the operator gain threshold.

  The goal is very high SNR against msfa, not identical samples.
- **Scope: DX7 first.** OPZ waveforms and TX81Z come once their SysEx is fetched.
- **Converter:** in this repo (`tools/patch_convert/`). It writes patches and comparison reports into `D:\12_library\gak\`, next to each voice's sidecar.

## Promise (as phase 1)

- **Old patches keep their samples.** A patch without the new fields renders the same samples, natively and in GDScript, live and baked. `VERSION` stays 3, and new fields enter `describe()` only when set. The same before/after hashes as phase 1 check this.
- **The matcher's API stays.** `fm_from`, `fm_index` and today's oscillator fields keep their meaning. The sample matcher doesn't read `MAX_OSC` or the FM fields.
- **Native = GDScript, live = bake.**

## What msfa does, and how GAK copies it

Read from `D:\tools\dx7render\msfa` (commit fea2f0f):

| msfa | Behaviour | GAK |
| --- | --- | --- |
| `fm_core.cc` | 32 algorithms. Six operators run in a fixed order (OP6 first), each hearing its modulators' outputs from the same sample. One operator can feed back on itself. An operator whose gain is below 1120 (Q24) at both ends of a block is skipped. | **F1** per-oscillator `fm` lists and `feedback`. GAK already runs oscillators last to first, so osc 6 runs before osc 1, matching msfa. Algorithm presets fill in the lists. The threshold lives in the `dx7` envelope (below). |
| `fm_op_kernel.cc` | `sin(phase + input)`: `input` is the sum of modulator outputs, Q24, where 2^24 is one cycle. Feedback is `(y[n−1] + y[n−2]) >> (fb_shift + 1)`. | In radians, a modulator's output (its envelope × sine) gives phase modulation `4π · out`, so `index = 4π`. Feedback depth is `4π / 2^(8 − feedback)` on the average of the last two outputs. |
| `dx7note.cc` `osc_freq`, `freqlut.cc` | Ratio and fixed frequencies in Q24 log frequency, including the detune curve. The phase increment comes from a lookup table, truncated to an integer. | **F4** `dx7_freq = {mode, coarse, fine, detune}` per oscillator. GAK computes msfa's integer increment, and the float phase then advances by exactly `inc / 2^24`, the same phase as msfa's. Generic `ratio` and `fixed_hz` are for other formats. |
| `dx7note.cc` compute | Every 64 samples: pitch = pitch EG + LFO × sensitivity (Q24 log), applied to ratio operators. Fixed operators get only the bend. | Pitch EG and dx7 LFO values change only at 64-sample steps. `dx7_freq` oscillators turn the matrix pitch (in semitones) into Q24 log frequency, and fixed ones take only the bend. |
| `pitchenv.cc` | 4 rates and 4 levels, with its own tables. | Phase 1's envelopes gain `mode = "dx7_pitch"`, whose output is in octaves. |
| `lfo.cc` | Six waves, speed table, delay ramp, key sync. Pitch depth × sensitivity, and amp depth × delay × wave. | **F6** `lfo1 = {mode = "dx7", speed, delay, wave, sync, pitch_mod_depth, pitch_mod_sens, amp_mod_depth}`. As a source it is msfa's pitch modulation in octaves; its amp modulation goes to `dx7` envelopes. |
| `env.cc` | Built in phase 1. Amp modulation is applied in the log domain per operator (`ampmodsens`). | The `dx7` envelope gains `amp_mod_sens` (0–3), driven by the voice's dx7 LFO, and msfa's gain threshold (below 1120 Q24 at both ends of a block → silent). |
| `dx7render` output | Sum of carriers, `>> 13` to 16-bit. | Patch `gain_db = −18.06` (1/8), with carriers at `level` 1. |

## Data model

### F1: operator graph

- **`MAX_OSC` 4 → 8.** Per-voice oscillator arrays grow; only oscillators in use run.
- **`fm = [{from, index}, ...]`** per oscillator. `from` is the 1-based modulator, and `index` the depth in radians per unit of its output. Several entries sum. `fm_from` and `fm_index` stay as today: they run alongside `fm`, and the matrix's `oscN.fm` still adds to `fm_index`.
- **`feedback`** per oscillator: self-modulation in radians on the average of its last two outputs, msfa's smoothing. Today's self-`fm_from` (previous sample only) keeps its behaviour.
- **What modulators send.** An oscillator with `level_env` (F3) sends its sine × that envelope, which is what msfa's buses carry. Without one it sends the bare waveform, as today.
- **`AKPatchLib.dx7_algorithm(n)`** returns the `fm` and `feedback` routing for DX7 algorithms 1–32, from msfa's table. Converters store the explicit graph; the engine never sees an algorithm number.

### F3: per-oscillator envelopes and scaling

- **`level_env`** (1–8) per oscillator: the oscillator's level and its modulation output follow that envelope.
- **Voice end.** A voice ends when its amp envelope has finished, or when every audible oscillator has a `level_env` and all of those have finished. That makes a DX7 voice end when its carriers do. Its `amp_env` is a one-shot at level 1.
- **`velocity_sens`** per oscillator: level × `(1 − s · (1 − velocity))`.
- **`key_scaling = {break_key, left_db_oct, right_db_oct, left_curve, right_curve}`** per oscillator, with `lin` or `exp` curves: a generic version for CZ, M3R and Matrix-6. DX7 doesn't need it, because its `dx7` envelope already scales by key exactly.
- **Later (F7):** `pitch_env`, `shape_env` and key tables.

### F4: frequency

- **`ratio`**: an exact multiplier of the note's frequency, after `semitones` and `cents`.
- **`fixed_hz`**: ignores the key; the bend and matrix pitch still apply.
- **`dx7_freq = {mode, coarse, fine, detune}`**: raw DX7 values, as above. The key is `note + semitones`, rounded, so a voice's transpose rides on `semitones`.

### Envelopes and LFO (phase 1 continued)

- `mode = "dx7_pitch"`: `rates`, `levels`.
- `dx7` envelopes gain `amp_mod_sens`.
- `lfo1` or `lfo2` can be `mode = "dx7"`. The first dx7 LFO drives the `dx7` envelopes' amp modulation.

### A converted DX7 voice

- **Envelopes:** `amp_env` is a one-shot at 1, and `envelopes` holds the six operators' `dx7` envelopes and the `dx7_pitch` envelope. That is 8 envelopes, exactly `MAX_ENV`.
- **Oscillators:** six sines with `dx7_freq`, `level_env`, `fm` lists from the algorithm, and `feedback` on the feedback operator.
- **Carriers and modulators:** carriers have `level` 1; modulators have `level` 0.
- **Matrix:** `{env8 → pitch, 12}` and `{lfo1 → pitch, 12}`.
- **Voice settings:** `velocity_sens` 0, `filter` off, `gain_db` −18.06.

## Converter: `tools/patch_convert/`

- **`dx7.gd`:** `content.dx7.params` → `AKPatch`. Also a headless batch: `godot --headless --script res://tools/patch_convert/dx7_batch.gd -- <library folder>`.
- **What it writes,** per voice, beside the sidecar:
  - `gak_patch.tres`;
  - `gak_report.json`: SNR per note against `render_msfa_v100.wav`, plus the converter version.
- **How it renders:** the same layout as `dx7render` (notes 36–84, voice transpose, velocity 100/127, hold 2 s, release 2.5 s, gap 0.25 s), baked through `AKSynth`.
- **msfa references:** a small script reruns `dx7render --engine msfa` from each voice's `voice.syx` to make `render_msfa_v100.wav`, and updates the sidecar's `content.render` with an `engine_msfa` entry.

## Tests

1. **Old patches unchanged:** the before/after hashes.
2. **msfa pieces, exactly:** the harness in `tools/dx7_env_ref` grows to cover `osc_freq` + Freqlut (increments for every mode, coarse, fine, detune and a range of notes), the pitch EG, and the LFO (all waves, delay, sync). GDScript and native must match its integers.
3. **F1, F3, F4 behaviour:**
   - several modulators sum;
   - feedback averages the last two outputs;
   - a `level_env` scales both what is heard and what is sent;
   - the voice ends with its carriers;
   - `ratio` and `fixed_hz` give the right frequencies;
   - `velocity_sens` and `key_scaling` scale levels.
4. **Native = GDScript, live = bake** for a 6-operator patch.
5. **Against msfa renders:** a sample of factory voices (one per algorithm family, plus feedback, fixed-frequency, LFO and pitch-EG voices) converted and rendered. They must reach an SNR floor against `render_msfa_v100.wav`. The floor is set from what the first runs show; I expect 60 dB or better, limited by the reference's 16 bits. The batch reports all 256.
6. **CPU:** 16 voices of a 6-operator patch under 10% of a core (native), and old patches' cost as in phase 1.

## Order of work

1. msfa references: render `render_msfa_v100.wav` for the 256 voices; extend the harness.
2. GDScript: F4 frequencies, F1 graph and feedback, F3 level envelopes and voice end, `dx7_pitch`, the dx7 LFO and amp modulation sensitivity.
3. Native: the same; parity, live and cost.
4. Converter and batch; run it on the 256 voices; set the test's SNR floor.
5. Docs and spec; commit.

## Risks

- **The SNR floor is an expectation, not a promise.** Places where float and msfa's integers can differ: msfa's sine table (about −106 dB), Exp2 interpolation, per-sample gain-ramp rounding, and feedback's integer shift. Where a voice falls short, the report says where, and I'll look before lowering the floor.
- **Cost.** Six `sin()` calls per sample per voice. If the CPU test fails, a sine table for FM operators is the fallback. It would change no existing patch.

## As built

- **Old patches:** renders and `describe()` are bit-identical before and after, natively and in GDScript (the phase 1 hashes).
- **msfa pieces, exactly:** the extended harness (`tools/dx7_env_ref/dx7_ref.cpp`) checks frequencies (540 cases), the pitch envelope (18) and the LFO with its pitch and amp modulation (10). GDScript matches its integers exactly; native matches GDScript.
- **Against msfa renders.** All 256 voices were converted and checked (`gak_dx7_summary.json` in the library). The 83 voices with no caveat have a worst-note SNR of at least 36 dB, a 10th percentile of 58.5 dB and a median of 66.6 dB. The lowest are quiet voices, where the 16-bit reference is the limit (Take Off's error sits at a constant floor near −95 dB). The test holds six voices at ≥ 60 dB on every note: algorithms 6, 18, 19, 22 and 25, covering fixed frequencies, feedback, the pitch envelope, vibrato, amp modulation and keyboard scaling.
- **Caveats: `dx7render` leaves state uninitialised.** Each note's LFO (phase and random state) and the note's feedback buffer start from whatever memory holds. That affects 173 voices: unsynced LFOs, sample-and-hold, and feedback 7. A scratch build of `dx7render` that zeroes that state brings the tested low voices to 50–79 dB. The exception is chaotic feedback-7 noise voices (snares, Wasp Sting, Train): float and msfa's integers diverge there within milliseconds, so they can't be matched sample by sample, only by ear or spectrum. The fix belongs in `tools/open_samples_prep/dx7render/dx7render.cpp` on the prep tool's branch; after that, `render_msfa.py` would re-render the references.
- **One msfa detail the batch found:** a factory voice (60s Organ) has `fine = 100`, beyond the panel's 0–99. msfa uses the raw byte, so GAK no longer clamps frequency bytes below 127.
- **Cost (native):**
  - Old patches: within about 1.5% of phase 1 (152–153 ms against 150–152 ms, alternated). The phase 2 oscillator fields live in their own array (`OscOp`), and a per-patch `plain` flag keeps the fast path.
  - 16 voices of a 6-operator DX7 patch: about 12% of a core, so the gate is 15%, not the planned 10%. Six plain sines alone take about 9.6%, so most of the cost is the per-oscillator loop. dx7 operators read msfa's sine table, which is faster than `sin()` and closer to msfa; an operator silent under msfa's threshold skips its sine.
  - Timings read up to 1.5× higher after long runs of heavy tests on this machine; standalone numbers are quoted.
- **Files:**
  - `patch.gd` (`_compile_operator`, `dx7_pitch`, the dx7 LFO, `MAX_OSC` 8);
  - `patch_lib.gd` (`dx7_algorithm`);
  - `synth_core.gd` and `native/src/synth.*`, `ak_synth.cpp`;
  - `tests/test_operators.gd`, `tests/data/dx7_ref.json`;
  - `tools/dx7_env_ref/dx7_ref.cpp`;
  - `tools/patch_convert/` (`dx7.gd`, `dx7_batch.gd`, `render_msfa.py`).
- **Not done:** OPZ waveforms and TX81Z (once SysEx is fetched); the Sound Lab patch editor has no panels for the operator fields.
