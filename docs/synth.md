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

The easiest way to build one is the Sound Lab's Synth page: panels for every setting below, a preset browser, a scope and spectrum, and a keyboard (`docs/sound_lab.md`). In the editor you can also select a patch to play it from the Audio Kit dock (single notes, a chord, an arpeggio, a glide), live when the native core is installed, and edit it in the inspector; the next note uses the edit, and a playing `AKSynthStream` picks it up at once.

## Signal path

Per voice: oscillators (each stacked `unison` times, spread across the stereo field by `spread`) are summed by their levels, run through the filter, and multiplied by the amp envelope, velocity, the `amp` modulation and `gain_db`; then panned. Voices sum into a stereo output, which runs through the patch's `effects`.

Envelopes, oscillators and the filter run every sample. Modulation (LFOs, the matrix, glide, pitch, oscillator settings, filter coefficients, amp and pan) is worked out every 8 samples (6 kHz) and held in between. That keeps 32 two-oscillator voices at about 6–8% of a core; the steps are far too small to hear on vibrato, sweeps and FM envelopes.

## Oscillators

Up to sixteen, in `oscillators`:

| Key | Default | What it does |
| --- | --- | --- |
| `shape` | sine | `sine`, `triangle`, `saw`, `square`, `pulse`, `noise`, `morph`, or `table` (a wavetable); saw, square, pulse and tables are band-limited |
| `level` | 1.0 | Its level in the mix; 0 makes a pure modulator |
| `semitones`, `cents` | 0 | Offset from the note |
| `width` | 0.5 | Pulse width (`pulse` only) |
| `position` | 0 | `morph`: 0 sine, 0.33 triangle, 0.66 saw, 1 square, blended between. `table`: 0 the first frame .. 1 the last |
| `table` | basic | `table` only: a built-in name (`basic`, `pwm`, `vowel`, `organ`, `bright`, `digital`) or `{frames = [...]}` (see Wavetables) |
| `fm_from` | 0 | 1-based number of another oscillator that phase-modulates this one; 0 = none |
| `fm_index` | 0 | Modulation depth in radians |
| `sync_to` | 0 | 1-based oscillator whose cycle restarts this one's (hard sync); sweep this one's pitch for the classic sync sound |
| `ring_from` | 0 | 1-based oscillator this one is multiplied by (ring modulation: sum and difference tones) |
| `pan` | 0 | −1 left .. 1 right, equal power: oscillators placed apart in the stereo field (a layer to one side, a sub in the middle) |
| `filtered` | true | false: the oscillator goes around the filter, straight to the amp (a bright noise click over a filtered tone) |
| `fm_mode` | phase | How `fm_from` and `fm` move this oscillator: `phase` (phase modulation, `fm_index` in radians), `pitch` (its pitch, `fm_index` semitones per unit of the modulator's output: exponential FM, an analog cross mod) or `linear` (its frequency, `fm_index` Hz per unit, through zero: the phase runs backwards when the frequency goes negative) |
| `color` | white | A `noise` oscillator's color: `white`, `pink` (−3 dB an octave) or `red` (−6 dB an octave), all at the same level |
| `phase` | – | Where the oscillator starts each note, in cycles (0–1). Absent: at 0, or at seeded random phases with unison or a stack; set, every copy starts here |
| `phase_with` | 0 | 1-based oscillator whose start phases this one takes (copy for copy), plus `phase`: a saw and a pulse built from one analog oscillator stay aligned under unison |
| `stack`, `stack_cents` | 1, 0 | This oscillator alone copied 1–8 times, spread evenly across `stack_cents`, with seeded random start phases: a thick detuned osc 1 beside a plain osc 2. It multiplies `unison` (a stack of 8 with unison 3 is 24 copies). FM, sync and ring between oscillators with different stacks read the same unison voice of the other oscillator (and its copy, when it has as many) |

Oscillators are computed last to first, so an oscillator modulated by a later one hears it this sample; one modulated by itself or by an earlier one hears the previous sample (feedback). The classic two-operator FM pair is `[{shape = "sine", fm_from = 2, fm_index = 2.0}, {shape = "sine", level = 0.0, semitones = 12.0}]`.

`unison` (1–8) stacks every oscillator, spread evenly across `detune_cents`, with seeded random start phases; noise isn't stacked. `unison_level` (0–1, default 1) is the stacked voices' level against the middle one (or the middle two, for an even count): 1 keeps them equal, lower gives a solid centre with a quieter shimmer around it. The stack is scaled to keep its power, so turning it down doesn't change the loudness much. `spread` (0–1) pans the stacked voices across the stereo field, equal power (0 keeps the patch mono, exactly as before). A patch with `spread` or any oscillator `pan` runs its filter on left and right separately.

`unison_pitch` (semitones, −24 to 24, default 0) raises the odd-numbered unison voices (the 2nd, 4th ...) by an interval: 12 an octave, 7 a fifth, negative for below. With two voices and no detune it is the plain interval; with more, every other voice of the detuned spread.

Hard sync isn't band-limited: the restart is a hard edge, so very bright sync sweeps alias a little at high notes.

### Operators (FM graphs)

More fields turn oscillators into FM operators. An oscillator without them behaves exactly as before.

| Key | Default | What it does |
| --- | --- | --- |
| `fm` | – | `[{from, index}, ...]`: several modulators, summed (index in radians per unit of the modulator's output). Runs alongside `fm_from`/`fm_index`; the matrix's `oscN.fm` still moves `fm_index` |
| `feedback` | 0 | Self-modulation in radians on the average of its last two outputs (a DX7's smoothing) |
| `level_env` | 0 | 1-based envelope (1 `amp_env`, 2 `env2`, 3 `env3`, 4.. `envelopes`) this oscillator follows: what you hear of it, and what it sends to the oscillators it modulates |
| `ratio` | 1 | Multiplies the note's frequency (after `semitones`, `cents`) |
| `fixed_hz` | 0 | A fixed frequency that ignores the key; bend and matrix pitch still move it |
| `dx7_freq` | – | `{mode, coarse, fine, detune}`, a DX7 operator's raw values: msfa's exact phase increment (its log frequency and lookup table), the matrix pitch added in its log domain for ratio operators, only the bend for fixed ones. The key is the note plus `semitones` (a voice's transpose). Its sine is read from msfa's 1024-point table |
| `velocity_sens` | 0 | Level × `1 − s · (1 − velocity)` |
| `key_scaling` | – | `{break_key, left_db_oct, right_db_oct, left_curve, right_curve}`: dB per octave either side of the break key; curves `lin`, or `exp` (depth × (2^octaves − 1)) |

When every audible oscillator has a `level_env`, the voice ends when all of those envelopes have finished (as a DX7 voice ends with its carriers), whatever `amp_env` does.

`AKPatchLib.dx7_algorithm(n)` gives the DX7's 32 algorithms as `{carriers, mods, feedback}` (from msfa's table) for building `fm` lists. `tools/patch_convert/dx7.gd` converts DX7 voices this way (see its README); converted factory voices match msfa's renders to about 66 dB SNR (median of each voice's worst note).

### Wavetables

A `table` oscillator reads a wavetable: a few frames of one cycle, swept by `position` (modulate `oscN.position` with an LFO or envelope). Built in: `basic` (sine, triangle, saw, square), `pwm` (a pulse narrowing from square), `vowel` (a, e, i, o, u formants on a saw), `organ` (drawbar settings), `bright` (a saw tilting brighter), `digital` (seeded metallic harmonic sets). Your own: `{frames = [{harmonics = [1.0, 0.5, 0.33 ...], phases = [...]}, {samples = [one cycle of any length]}]}` inline, or a path to a JSON file holding that. Each frame is stored at up to 19 band limits (a half octave apart, up to 512 harmonics), and a note reads the richest one whose harmonics all sit below Nyquist, so tables don't alias; limits above the one that holds all of a table's harmonics would be copies, so they aren't stored. Tables are built once per content (`AKWavetables.build`) and cached. A frame normally has its level normalised; `normalize = false` keeps each frame's level against the others, so a table can carry a decay swept by `position`.

**Key zones.** `{zones = [{key = 48, frames = [...]}, {key = 60, frames = [...]}], normalize = false, blend = false}`: a set of frames per key, like a sampler's key zones. A note plays the two zones around it, blended by key, or with `blend = false` the nearest zone alone (blending zones whose harmonics' phases differ can thin the sound between them). Below the first zone and above the last, the end zone plays. A zoned table stores only four band limits below its richest (two octaves of headroom above each zone's key), since each zone plays near its own key. This is what the sample-matching tools build from a recording: cycles taken from the held notes at points through each note, every three semitones (see `docs/plans/sample-matching.md`).

## Filter

`filter = {type, cutoff_hz, q, slope_db}`: `off`, `lowpass`, `highpass`, `bandpass` or `notch`; a state-variable filter, 12 dB per octave, or 24 with `slope_db = 24`.

`filter = {type = "ladder", cutoff_hz, resonance, drive}`: a four-pole (24 dB) ladder low-pass, solved without delay in its feedback. `resonance` 0–1 (near 1 it rings at the cutoff; up to 1.2 it oscillates on its own); `drive` (default 1) pushes it into soft saturation, which also tames the resonance on loud input. Some of the bass a resonant ladder loses is made up. The matrix's `q` destination scales the resonance.
- `poles` (1–4, default 4): the low-pass taken after that many poles (6, 12, 18 or 24 dB per octave); a fractional value crossfades the two around it (an OB-Xd's 24 dB mode morphing from four poles to one). Resonance always feeds back from the fourth pole.
- `pole_mix` (`[input, pole 1, pole 2, pole 3, pole 4]`): the output is this mix of the ladder's input (after the feedback) and its poles, overriding `poles`. The Oberheim Xpander's modes come from it: `[1, -4, 6, -4, 1]` a four-pole high-pass, `[0, 0, 4, -8, 4]` a band-pass, `[1, -2, 2, 0, 0]` a notch, and so on.

`filter = {type = "mix", cutoff_hz, q, low, band, high}`: the state-variable filter's three outputs mixed (weights; defaults 1, 0, 0). `low = 1` alone is `lowpass` exactly, `high = 1` alone `highpass`; `low = high = 1` a notch; sliding the weights morphs LP → notch → HP or LP → BP → HP.

`filter = {type, cutoff_hz, q, gain_db}` with type `lowshelf`, `highshelf` or `bandshelf` (a bell at the cutoff): `gain_db` boosts (or, negative, cuts) that side. All the state-variable types take `slope_db = 24` (two in a row).

`pre_filter = {lowpass_hz, highpass_hz}`: one-pole filters (6 dB per octave) on the filtered oscillators before the main filter, each off when absent: an OB-Xd's brightness knob, or a gentle high-pass ahead of a resonant low-pass.

`comb = {semitones, cents, feedback}` (feedback −0.99–0.99): a comb tuned to the note, on the filtered oscillators before `pre_filter`. Each sample adds `feedback` times the output one period back, the period of the voice's pitch (with bend, glide and pitch modulation) moved by `semitones` and `cents`, read between samples by a straight line. Positive feedback rings at the note's harmonics, negative at the odd ones; this is Helm's oscillator feedback. Periods are capped at 4,096 samples (12 Hz at 48 kHz).

## Envelopes

`amp_env`, `env2`, `env3`, each `{attack_s, decay_s, sustain, release_s, curve}`. Attack rises linearly (0 = start at full level). Decay is linear, or with `curve = "exp"` a time constant toward `sustain`. Release is a time constant from wherever the level is when the note ends. An optional second stage, `release_knee` (0–1, a share of the level at key-up) and `release2_s`: once the release falls to the knee it goes on with the second time constant, so a release can drop at once and then trail off (as sample-playback synths' releases often do). Without `release2_s` the release is one stage, as before. `amp_env` sets the level (and is the matrix source `env1`); `env2` and `env3` only act through the matrix.

`envelopes` adds up to five more, the matrix sources `env4` to `env8`. Any envelope, these and the first three alike, can take one of two other forms. A dictionary with neither `stages` nor `mode` is the ADSR above, unchanged.

### Stages

```
env2 = {stages = [{time_s = 0.01, level = 1.0}, {time_s = 0.3, level = 0.4, curve = "exp"},
		{time_s = 1.5, level = 0.2, curve = "power", amount = -2.0}, {time_s = 0.4, level = 0.0, curve = "exp"}],
	sustain = 2, loop = [1, 2], start = 0.0, delay_s = 0.0, hold_s = 0.0,
	time_key = 0.0, time_key_center = 60, time_key_stages = [], time_velocity = 0.0, time_velocity_stages = [],
	level_velocity = 0.0}
```

- **Stages and curves.** Each stage moves from wherever the level is to its `level` over `time_s` (0 jumps). The curves are:
  - `linear`;
  - `power` with `amount`, Vital's `(e^(a·x) − 1) / (e^a − 1)`: 0 is straight, positive starts slow, negative starts fast;
  - `exp`, which is `power` with amount −5 (or −`amount`): a fast start that lands exactly on time;
  - `hold`, which keeps the level for `time_s`.
- **Sustain.** The stages up to `sustain` run while the key is down, and the level then holds there. Key-off moves to the next stage from wherever the level is, even mid-stage; the stages after `sustain` are the release.
  - Without release stages, the release is a `release_s` time constant, as an ADSR's.
  - Without `sustain`, the last stage holds.
  - `sustain = -1` makes a one-shot that ignores key-off.
- **Loop.** `loop = [a, b]` (with `b` no later than `sustain`) goes back from the end of stage `b` to stage `a` while the key is down.
- **Start, delay and hold.** `start` is the level at note-on. `delay_s` and `hold_s` become `hold` stages before the first stage and after it.
- **Retrigger.** A retrigger (mono, or a voice taken while ringing) restarts the stages from the level where the envelope is.
- **Time scaling per note:**
  - `time_key` multiplies each stage's time by 2^(−time_key · (key − time_key_center) / 12), so higher keys are faster for positive values;
  - `time_velocity` multiplies by 2^(−time_velocity · (velocity − 1)), so times are as written at full velocity, and softer notes are slower for positive values;
  - `time_key_stages` and `time_velocity_stages` list the stages each applies to (empty means all), as the M3R's per-segment switches do.
- **Level scaling.** `level_velocity` scales every level by `1 − level_velocity · (1 − velocity)`.
- **Ending the voice.** As the amp envelope, a stages envelope ends its voice once it is released and no stage ahead can rise again.

### DX7

```
amp_env = {mode = "dx7", rates = [99, 50, 35, 40], levels = [99, 80, 60, 0], output_level = 99,
	rate_scaling = 2, velocity_sens = 3,
	key_scaling = {break_point = 39, left_depth = 0, right_depth = 20, left_curve = 0, right_curve = 3}}
```

A DX7 operator's whole amplitude block, in raw DX7 values: rates and levels 0–99, `rate_scaling` and `velocity_sens` 0–7, keyboard curves 0–3 (−lin, −exp, +exp, +lin), as the prep tool's sidecars name them.

It runs Dexed's msfa envelope (`env.cc`, Apache-2.0) with msfa's integer arithmetic:
- **Per note.** The output level, keyboard level scaling and velocity are worked out from the key and velocity (MIDI = velocity × 127).
- **Every 64 samples**, msfa's step runs, and the gain ramps linearly between steps, as msfa's operator kernel does. A key-off is taken at the next step.
- **Gain.** Level 99 at output level 99 is a gain of 1.
- **Ending the voice.** The envelope goes silent where msfa's note would end, at level 4 = 0 after the release. As the amp envelope, it then ends its voice.

`tests/test_envelopes.gd` holds the levels to msfa's own, from `tools/dx7_env_ref` (a harness built on msfa's `env.cc`).

Further `dx7` fields:
- `amp_mod_sens` (0–3): the first DX7 LFO's amp modulation, applied in msfa's log domain.
- `key_offset`: semitones added to the key for its scaling (a voice's transpose).

Below msfa's operator gain threshold at both ends of a 64-sample step, the envelope is silent for that step, as msfa skips the operator.

`mode = "dx7_pitch"` `{rates, levels}`: the DX7 pitch envelope (msfa `pitchenv.cc`), in octaves, stepped every 64 samples. Route it with `{source = "envN", dest = "pitch", amount = 12}`.

## LFOs

`lfos` adds up to six more, lfo3 to lfo8 in order, each with lfo1's keys (all but the dx7 mode's): matrix sources `lfo3` .. `lfo8`, destinations `lfo3.rate` .. `lfo8.rate`. Only the LFOs a patch defines run, so a patch without `lfos` costs what it did. Their `random` and `smooth` shapes draw from streams of their own, so adding one leaves lfo1's, lfo2's, the `random` source's and noise's values as they were. Shape `custom` takes `points` (2–256 values, −1..1, spread across one cycle), `interp` (`linear`, joining them, or `step`, holding each) and `once` (true: from the first point to the last in one cycle, then the last held: a drawn envelope, which with `rate_sync` follows the tempo). Summed classic shapes, step sequences and drawn curves all go in points.

`lfo1`, `lfo2`, each `{shape, rate_hz, delay_s, width, phase, free}`: `sine`, `triangle`, `saw`, `square`, `random` (a new random value each cycle) or `smooth` (a new random value each cycle, glided to along a half cosine). They restart with every note, at `phase` (cycles, default 0); `delay_s` fades them in (delayed vibrato). `free = true` runs the LFO from the start of playback instead, as a hardware LFO or chorus does: each note picks it up where it is, and `phase` is where it was when playback started (the matrix's `lfoN.rate` rows still bend it, per voice, from there). `width` (square only, default 0.5) is the part of each cycle it's high: a short width on an oscillator's level makes rhythmic clicks or gates. The matrix can move an LFO's rate (`lfo1.rate`, `lfo2.rate`, in octaves): an envelope there makes a wobble that speeds up or slows down through the note.

`rate_sync` sets the rate from the tempo instead of `rate_hz`: a note length per cycle, `"1/4"` (a beat), `"1/8."` (dotted), `"1/8t"` (triplet), `"2/1"`, or a number of beats. A free synced LFO counts from the start of playback, so it lines up with the beat; a tempo change keeps its phase and changes its speed from there.

`lfo1` or `lfo2` can be `{mode = "dx7", speed, delay, wave, sync, pitch_mod_depth, pitch_mod_sens, amp_mod_depth}`, in raw DX7 values. Waves 0–5 are triangle, saw down, saw up, square, sine and sample-and-hold. It is msfa's LFO (`lfo.cc`), stepped every 64 samples:
- **As a source,** it is msfa's pitch modulation in octaves, with depth, sensitivity and delay applied; route it with `amount = 12` to `pitch`.
- **Amp modulation:** its amp modulation drives `dx7` envelopes with `amp_mod_sens`.
- **Each note** restarts it: at the key-sync point with `sync`, otherwise from phase 0.

## Tempo

`tempo_bpm` (default 120) is the patch's tempo when the player sets none. `AKSynthStream.set_tempo(bpm, delay_s)` sets it live, to the sample, and a `{time_s, tempo_bpm}` entry does the same in `AKSynth.render_notes` (event `AKSynth.E_TEMPO`); once set, it overrides the patch's. Three things follow it: LFOs with `rate_sync`, the `delay` effect's `time_sync`, and the arpeggiator.

## Arpeggiator

```
arp = {mode = "updown", octaves = 2, rate = "1/16", gate = 0.5}
```

With `arp` set (and `on` not false), held keys don't play directly: they form a chord the arpeggiator plays one note per step.
- **`mode`**: `up`, `down`, `updown` (the top and bottom notes aren't repeated), or `random` (seeded by the patch's `seed`, so the same notes give the same order).
- **`octaves`** 1–4: the chord repeated an octave higher each time.
- **`rate`**: the step, a note length as for `rate_sync`, at the tempo.
- **`gate`** 0.01–1: the share of each step a note sounds. At 1 the steps tie: each note starts before the last one ends, so a `legato` patch glides through the pattern without retriggering.
- **Timing.** The pattern starts with the first key down, whose first step plays on that sample. Keys added later join from the next step. Releasing the last key stops it and releases the sounding note.
- **Velocity.** Each note plays at the velocity of the key it came from.
- **Voices.** Steps play through the patch's own voice allocation (poly, mono or legato). The sustain pedal doesn't hold the arpeggiator's keys.

Live, baked, native and GDScript give the same steps.

## Modulation matrix

`mods`, up to 32 rows of `{source, dest, amount}`. Each row adds `amount × source` to the destination. A row may name a second source in `via`: it then adds `amount × source × via` (vibrato as `{source = "lfo1", via = "mod_wheel", dest = "pitch", amount = 0.5}`, an envelope's depth following the key as `via = "key"`).

| Source | Range |
| --- | --- |
| `env1` (amp), `env2`, `env3`, `env4` .. `env8` (`envelopes`) | 0..1 (a dx7 envelope can exceed 1 with velocity) |
| `lfo1`, `lfo2`, `lfo3` .. `lfo8` (`lfos`) | -1..1 |
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
| `lfo1.rate` .. `lfo8.rate` | octaves (multiplies the rate by 2^amount) |
| `comb.feedback` | added to `comb`'s feedback (kept within ±0.99) |
| `comb.pitch` | semitones (moves `comb`'s tuning) |
| `oscN.level`, `oscN.fm` (radians), `oscN.width`, `oscN.position` | added to the oscillator's setting |

## Playing

| Setting | What it does |
| --- | --- |
| `mode` | `poly`; `mono` (one voice, envelopes restart on each note); `legato` (one voice, envelopes carry on while notes overlap). In mono and legato, releasing the top note returns to the one still held |
| `polyphony` | 1–32 voices. A new note beyond that takes over the oldest releasing voice, else the oldest |
| `glide_s` | Portamento time constant (0 = jump) |
| `bend_range` | Semitones at full bend |
| `velocity_sens` | 0: velocity doesn't change the level; 1: level follows velocity |
| `velocity_curve` | How velocity maps to level (0.25–4): 1 linear (at full sensitivity velocity 64 is 6 dB down), 2 squared (12 dB), below 1 gentler. Only the level: the matrix's `velocity` source stays linear |
| `key_levels` | Level by key: `[[key, dB], ...]`, joined by straight lines in dB and flat past the ends (empty: the same on every key). For an instrument whose loudness doesn't follow a straight line across the keyboard; the matrix's `key → amp` is linear |
| `gain_db`, `pan` | Output level and balance |
| `band_limited_sync` | Smooth each hard-sync reset (a polyBLEP across the two samples around it) instead of jumping: sync sweeps alias far less. The synced oscillator resets where its master wrapped, a sample later than without. Off by default (older patches render as they did) |
| `note_priority` | Mono and legato: which held key sounds. `last` (default, the newest), `low` or `high` (the lowest or highest held key, as many analog monosynths; a new key that doesn't win changes nothing, and releasing the sounding key moves to the next by the same rule) |
| `retrigger_from_zero` | Mono and legato: a new note restarts the envelopes from zero rather than from where they are (Helm's and many monosynths' way; legato notes that overlap still don't restart) |
| `nyquist_clamp` | Hold every oscillator's pitch just under Nyquist (0.49 of the sample rate) instead of letting a big pitch sweep or FM shift fold back down as aliasing. Off by default (older patches render as they did) |
| `seed` | Seeds noise, unison phases, the random source, random LFOs and the voice slots' slop |
| `voice_pan` | `[p1, p2 ...]`: each voice slot's pan (−1..1). New voices take the slots in turn (round robin), as a polysynth's voice cards do; mono and legato patches play slot 1 |
| `slop` | `{pitch_cents, cutoff_octaves, env_time, level_db}`: each voice slot gets its own fixed offsets within ± these, from `seed`: pitch, cutoff, every envelope's times (× 1 ± `env_time`) and level. The slots are `voice_pan`'s, or 8. A vintage polysynth's voices each sound a little different; a run of notes moves through them |

The same notes, controller changes and seed always give the same samples, in GDScript, natively and live.

## Live and baked

`AKSynthStream` (native) is the engine running in the audio thread. Calls take effect at the next mix block, or exactly `delay_s` later, so notes can be scheduled to the sample. `AKSynth.render_notes` bakes through the native engine when it's installed and through `AKSynthCore` (the same steps in GDScript, about 100× slower) when not; tests hold all three to the same samples.

Latency for keyboard play is Godot's mix buffer (about 15–30 ms by default).

## Effects

`effects`: a chain run on the patch's output, in order. Each is a spec dictionary, the same in a patch, a recipe's `fx` and (as the effect's properties) a Godot bus effect, so an effect sounds the same wherever it runs:

| Type | Keys (defaults) | Bus effect |
| --- | --- | --- |
| `chorus` | `rate_hz` 0.8, `depth_ms` 3, `delay_ms` 12, `voices` 2 (1–4), `mix` 0.5, `spread` 1 (left/right LFO offset, quarter cycles), `feedback` 0 | `AKChorus` |
| `flanger` | `rate_hz` 0.25, `depth_ms` 2, `delay_ms` 1, `feedback` 0.6, `mix` 0.5, `spread` 1 | `AKFlanger` |
| `phaser` | `rate_hz` 0.4, `stages` 4 (1–12), `center_hz` 800, `range_octaves` 2, `depth` 1, `feedback` 0.4, `mix` 0.5, `spread` 1 | `AKPhaser` |
| `eq` | `low_db` 0 at `low_hz` 120 (shelf), `mid_db` 0 at `mid_hz` 1000 with `mid_q` 0.7 (peak), `high_db` 0 at `high_hz` 6000 (shelf) | `AKEQ3` |
| `compressor` | `threshold_db` −18, `ratio` 4, `attack_s` 0.01, `release_s` 0.12, `knee_db` 6, `makeup_db` 0 (peak detector, stereo linked) | `AKCompressor` |
| `saturate` | `drive_db` 12, `tone_hz` 6000 (a low-pass after it), `asymmetry` 0 (even harmonics), `mix` 1, `output_db` 0 | `AKSaturate` |
| `pitch` | `semitones` −12 (−36–36), `window_ms` 60 (5–200; longer is smoother, shorter crisper), `mix` 0.5: a pitch-shifted copy blended in (an octave-down double, a shimmer) | — |
| `ring` | `freq_hz` 220, `rate_hz` 0 and `depth` 0 (octaves the carrier sweeps), `mix` 1: ring modulation, metallic sidebands | — |
| `growl` | `rate_hz` 45, `depth` 0.6, `jitter` 0.5 (how uneven each pulse is), `mix` 1: rough loudness pulses, a rasp | — |
| `crush` | `bits` 8 (1–24), `hold` 1 (samples held, 1–64), `mix` 1 | — |
| `delay` | `time_ms` 250 (or `time_sync`, a note length at the tempo, as `"1/8."`), `feedback` 0.35, `damp_hz` 4000 (repeats get darker), `mix` 0.3 (added to the dry), `mode` `stereo` (each side repeats itself), `cross` (the repeats change sides) or `pingpong` (both sides in on the left, then bouncing right and left), `spread_ms` 0 (−100–100: the right side's repeats later by that much, the left's when negative) | — |
| `reverb` | `room` 0.6, `damp` 0.5 (up to 2.5: 1 is Freeverb's most damping, 2.5 takes the tail's highs off entirely), `width` 1, `mix` 0.25 (added to the dry), `predelay_ms` 0, `low_cut_hz` 0, `high_cut_hz` 0 (one-pole filters on the reverb's input; 0 leaves each off): Freeverb's tunings | — |
| `filter` | `mode` `lowpass` or `highpass`, `cutoff_hz` 1000, `q` 0.707, `slope_db` 12 (6: one pole; 12, 24: the state-variable filter): a filter after the voices, all wet (a synth's master high-pass) | — |
| `limiter` | `ceiling_db` −1 (about −12..0), `release_s` 0.08 (about 0.005..1): a peak limiter, as `AKDynamics.limit`: instant attack, exponential release, both channels linked, no lookahead or latency. Nothing leaves above the ceiling; a signal that stays under it passes unchanged. Put it last to give a patch a guaranteed ceiling (a resonant filter's onset spikes) | `AKLimiter` |

Patch effects run continuously: a held note's chorus keeps moving, and live they keep running between notes (an edit that leaves an effect's settings alone doesn't restart it). In a recipe, the buffer is lengthened for a chorus, flanger, pitch, delay or reverb tail. The last six (the character effects speech voices use, `docs/speech.md`) have no bus effect; for reverb or delay on a bus, Godot's own are there.

The bus effects appear in Godot's Audio panel under Add Effect when the native core is installed (they are native only: GDScript can't process Godot's bus buffers). `effect.get_spec()` gives the matching spec dictionary, and `effect.process_offline(l, r, sample_rate)` runs the bus effect's own code over arrays. The bus runs at the project's mix rate (48 kHz in this project); at another rate the effect sounds the same but the samples differ.

## Today's voices as patches

`AKPatchLib.from_voice(voice, params)` rebuilds `tone`, `wavetable` and `fm` as patches: the same sound, polyphonic and playable live. `AKPatchLib.note_of(voice, params)` gives the note to play. Measured against the voices, plain tones match to float rounding; vibrato, the wavetable filter envelope and FM come within 25–40 dB SNR (the control rate, and float32 rounding inside the voices); `tone`'s glide curves in semitones rather than in Hz (timed to agree halfway); `wavetable` unison phases differ. The voices themselves are unchanged, so existing recipes and bakes don't move.

## Presets

In `addons/audio_kit/patches/` (written by `tools/make_patches.gd` from `AKPatchLib.preset`): `tone_beep`, `wavetable_bass`, `wavetable_pad` (spread, chorus), `fm_epiano` (chorus), `fm_bell` (from the voices); `saw_lead` (ladder, chorus), `sub_bass`, `brass` (ladder, EQ), `pluck` (ladder), `strings` (spread, chorus, EQ), `organ` (fast chorus, light drive), `wobble_bass` (ladder, saturation); and, showing the phase 4 modules, `sync_lead` (hard sync swept by an envelope and the mod wheel), `vowel_pad` (the vowel wavetable swept by an LFO), `ring_bell` (ring modulation), `pwm_strings` (the pwm wavetable), `acid_bass` (a resonant, driven ladder); and `speech_blip`, `speech_critter`, `speech_hollow` and `speech_drone`, the patches of the pseudo-speech voices (`docs/speech.md`). A single note of each peaks around −6 dBFS, leaving room for chords (`tools/measure_levels.gd` measures the trims). All are original.

## Categories

`category` (bass, lead, pad, keys, pluck, bell, strings, brass, organ, fx, voice, other, or anything) groups patches in the Sound Lab's preset browser. It doesn't change the sound or the bake key.

## Scope tap

`AKSynthStream.get_recent(frames)` returns the last frames it played (up to 8192, mono, oldest first), for scopes and meters; `render_offline` fills it too.
