# Synth expansion, phase 1: envelopes v2 (F2)

Status: **plan, for agreement.** Part of `docs/plans/synth-expansion.md` (feature F2). The user chose the build order: phase 1 comes first, and the phase 0 converters follow it.

## Promise

- **Nothing existing moves.** A patch that doesn't use the new fields renders the same samples as before, natively and in GDScript, live and baked. `AKSynthCore.VERSION` stays 3. New fields appear in `describe()` only when set, so existing bake keys don't change.
- **The sample matcher's API stays.** `amp_env`, `env2` and `env3` stay dictionaries with today's ADSR fields (`attack_s`, `decay_s`, `sustain`, `release_s`, `curve`, `release_knee`, `release2_s`), and `compile()`, `describe()` and `tail_s()` keep their signatures. The matcher (`addons/audio_kit/lab/sample_match.gd`) is not touched.
- **Native and GDScript agree.** Every new feature lands in `native/src/synth.*` and `addons/audio_kit/synth/synth_core.gd`, step for step. The tests hold them together, and hold live playback to the bake.

## Data model

An envelope is still a dictionary. It is read one of three ways:

1. **ADSR** (today): no `stages` and no `mode`. It compiles to today's kernel, unchanged.
2. **Stages**: has `stages`.
3. **`dx7`**: has `mode = "dx7"`.

`amp_env`, `env2` and `env3` are envelopes 1–3. A new export, `envelopes: Array[Dictionary]`, holds envelopes 4–8. Each of them can take any of the three forms. The matrix gains the sources `env4` to `env8`. They are appended to `SOURCES`, so existing source indices don't move.

### Stages

```
env2 = {
	stages = [
		{time_s = 0.01, level = 1.0},                                # linear by default
		{time_s = 0.3, level = 0.4, curve = "exp"},
		{time_s = 1.5, level = 0.2, curve = "power", amount = -2.0},
		{time_s = 0.4, level = 0.0, curve = "exp"},                  # after `sustain`: a release stage
	],
	sustain = 2,           # hold stage 2's level while the key is down
	loop = [1, 2],         # optional: while the key is down, go back from the end of stage 2 to stage 1
	start = 0.0,           # level at note-on (pitch envelopes start elsewhere)
	delay_s = 0.0, hold_s = 0.0,
	time_key = 0.0, time_key_center = 60, time_key_stages = [],
	time_velocity = 0.0, time_velocity_stages = [],
	level_velocity = 0.0,
}
```

- **Stages.** Each stage moves from wherever the level is to its `level` over `time_s`. A `time_s` of 0 jumps.
- **Sustain.** Stages up to and including `sustain` run while the key is down; the level then holds at that stage's level. Key-off moves to stage `sustain + 1` from the current level, even if it arrives mid-stage. The later stages are the release.
  - With no stages after `sustain`, the release is today's: a time constant `release_s` (default 0.15) from the level at key-off.
  - Leaving out `sustain` means the last stage holds.
  - `sustain = -1` runs every stage and ignores key-off (a one-shot).
- **Loop** `[a, b]`, with `b <= sustain`. While the key is down, the end of stage `b` goes back to stage `a`. Key-off leaves the loop for the release.
- **Curves** per stage:
  - `linear`;
  - `power` with `amount`, using Vital's formula `(e^(a·x) − 1) / (e^a − 1)`: 0 is linear, positive starts slow, negative starts fast;
  - `exp`, which is `power` with amount −5 by default: a fast start and a slow landing, like an analog decay, reaching the target exactly at `time_s`;
  - `hold`, which keeps the current level for `time_s`.
- **Sugar.** `delay_s` becomes a leading `hold` stage. `hold_s` becomes a `hold` stage after stage 0. On a retrigger (mono, or a voice taken while ringing) the envelope restarts from its current level, as ADSR does today.
- **Time scaling per note:**
  - `time_key`: each stage's time × 2^(−time_key · (key − time_key_center) / 12), so positive values make higher keys faster;
  - `time_velocity`: each stage's time × 2^(−time_velocity · (velocity − 1)). Times are as written at full velocity; positive values make softer notes slower.
  - `time_key_stages` and `time_velocity_stages` list the stages each applies to (empty means all), which covers the M3R's per-segment switches.
- **Level scaling by velocity:** `level_velocity` scales every level (and `start`) by `1 − level_velocity · (1 − velocity)`.

**Cost.** Stage lengths are worked out when a stage starts. Inside a stage, `linear` is one multiply-add per sample, and `power`/`exp` are one multiply (`g *= r`) plus a multiply-add, the same arithmetic as today's exp decay.

### `dx7`

The operator's whole amplitude block, so a DX7 operator's gain is exact without anything else:

```
amp_env = {mode = "dx7", rates = [99, 50, 35, 40], levels = [99, 80, 60, 0],
	output_level = 99, rate_scaling = 2, velocity_sens = 3,
	key_scaling = {break_point = 39, left_depth = 0, right_depth = 20, left_curve = 0, right_curve = 3}}
```

These are the raw DX7 values (0–99, 0–7, curves 0–3: −lin, −exp, +exp, +lin), named as in the sidecars' `content.dx7.params`.

The port follows msfa's `env.cc` (Dexed, Apache-2.0, commit fea2f0f), with `ScaleRate`, `ScaleLevel`, `ScaleCurve` and `ScaleVelocity` from `dx7note.cc`. It keeps msfa's integer arithmetic exactly (Q24 log levels, `statics`, `jumptarget`, `sr_multiplier`):

- **Per note** (key and velocity → MIDI 0–127): outlevel = scaleoutlevel(output_level) + key level scaling, capped at 127, then ×32, plus velocity scaling; rate scaling from the key.
- **Every 64 samples**, as msfa's N, msfa's `getsample()` runs. The gain is `2^((level − L99) / 2^24)`, normalised so that level 99 at output level 99 is 1.0. Between updates the gain ramps linearly, as msfa's operator kernel does, from 0 at note-on.
- **Key-off** is taken at the next 64-sample step, as msfa takes events between blocks. **Retrigger** is `keydown(true)`: back to stage 0 from the current level.
- **Silence.** Once the release has reached level 4 = 0, the gain is exactly 0, matching msfa's `isActive()`. A `dx7` amp envelope therefore ends its voice. msfa's floor of 16 microsteps would otherwise sit above `SILENT`.

As `amp_env`, it gives a single-carrier patch DX7 timing today. Per-operator envelopes come with F3 in phase 2, and the DX7 pitch EG (msfa `pitchenv.cc`) comes with F1/F6 in phase 2.

Not in phase 1: the `cz` and `m1` modes (phase 4, and once `m1` is measured), and envelope times and levels as matrix destinations (F7).

## Engine changes

- **`AKPatch`:**
  - add the `envelopes` export and the sources `env4`–`env8`;
  - `compile()` turns each envelope into one of three kinds: ADSR (today's numbers), stages (flat arrays) or dx7 (raw ints), with an `n_env` count;
  - `tail_s()` handles stages (the sum of the release stage times at their longest scaling, plus the `release_s` fallback) and `dx7` (simulating the release stage from level 99);
  - `describe()` adds `envelopes` only when it isn't empty.
- **`native/src/synth.h/.cpp`, `ak_synth.cpp` (parse), and `synth_core.gd`:**
  - per-voice envelope state grows from 3 to 8 (`stage`, `t`, `level` and so on), plus stage state (index, length, from, g, r) and dx7 state (level, target, rising, ix, inc, staticcount, gain1/2);
  - `env_tick(k)` branches on kind: the ADSR branch is today's code untouched, so old patches keep their samples bit for bit;
  - only envelopes in use are ticked: `n_env` is 3 unless `envelopes` is set;
  - `control()` takes the envelope values as an array, and `src[]` grows to 16.
- **`AKSynthStream` and live:** nothing new; they share the engine.
- **Docs:** the envelopes section of `docs/synth.md`, `patch.gd`'s doc comment, and decisions recorded in the spec.

## Tests (`tests/test_synth.gd`, plus test data)

1. **Old patches unchanged:** checksums of `_rich()` and the shipped presets are taken before the change, native and GDScript, and asserted after. `describe()` is the same for patches without new fields.
2. **Stages:** each curve reaches its level at the right sample. Also covered: sustain hold, loop, key-off mid-stage, the `release_s` fallback, one-shot, delay/hold sugar, `start`, `time_key`, `time_velocity` with stage lists, and `level_velocity`.
3. **env4–env8** as matrix sources.
4. **`dx7` against msfa itself.** A small harness, `tools/dx7_env_ref/` (C++), compiles msfa's `env.cc` and the scaling functions from `D:\tools\dx7render\msfa`. It writes `tests/data/dx7_env_ref.json`: the 64-sample levels for about a dozen cases (the factory voices' rate and level sets, several keys and velocities, key-off mid-attack, rate 99/level 0 corners, static counts). The GDScript and native ports must match those integers exactly.
5. **Native = GDScript** for each new feature, sample for sample (to float rounding, as the existing parity tests), and **live = bake** for a stages patch and a dx7 patch.
6. **CPU:** like `test_32_voices_cost`, with stages envelopes on amp and filter. The goal is within 10% of the ADSR patch's cost, and the existing 10%-of-a-core gate still passes.

Only the affected files run (`test_synth.gd`, `test_native.gd`, `test_recipes.gd`). The engine is shared code, so the full suite runs once before the work is handed over.

## Order of work

1. Record the checksums, then build the msfa reference harness and its JSON.
2. GDScript: compile, then `synth_core` stages, then dx7, with tests.
3. Native: the same, then parity, live and CPU tests.
4. Docs and spec. Commit on `claude/synth-expansion-51eda9`.
