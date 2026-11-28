# Synth engine and patches

A **patch** (`AKPatch`, a `.tres`) describes a synth sound: oscillators, two filters, envelopes, LFOs, a modulation matrix, effects and how notes are played. One engine renders it, live or baked, so what you hear while playing is what a bake writes.

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

## What it can do

A quick tour; each part has its section below. Tutorial 10 (`docs/tutorials/index.md`, "The synth's toolbox") builds a pad with most of it.

- **Oscillators** (up to 16): sine, triangle, saw, square, pulse with width, white, pink or red noise, a morph from sine to square, wavetables (six built in, your own frames, or key-zoned tables taken from a recording), and Casio CZ phase distortion. Each has a level, tuning, pan, start phase and filter routing. Saw, square, pulse and tables are band-limited, with an optional windowed-sinc BLEP.
- **Between oscillators**: FM (phase, pitch or through-zero linear; several modulators per oscillator; feedback; DX7-style operators with their own envelopes, ratios, fixed frequencies, velocity and key scaling, and the DX7's 32 algorithms), hard sync (optionally band-limited) and ring modulation.
- **Thickness**: unison up to 16 voices per oscillator with detune, stereo spread, side-voice level and an interval on every other voice; per-oscillator stacks of up to 16 detuned copies.
- **Filters**: two, in series or parallel, each oscillator choosing its path. State-variable low-pass, high-pass, band-pass and notch (12 or 24 dB), a four-pole ladder (resonance to self-oscillation, drive, 1–4 poles or any pole mix, such as the Xpander's modes), a diode mode, a `mix` type morphing low-pass, notch and high-pass, shelves and a bell, allpass and comb. Around them: a feedback loop, soft saturation, a one-pole pre-filter, and a comb tuned to the note.
- **Envelopes** (up to 8): ADSR with an exponential decay and two-stage release; multi-stage envelopes (up to 32 stages with linear, power, exponential and hold curves, a sustain stage, loops, delay and hold, times scaled by key or velocity); DX7 amplitude and pitch envelopes and CZ envelopes in those synths' own values.
- **LFOs** (up to 8): sine, triangle, saw, square with width, random, smooth random, and custom drawn shapes (stepped or joined, or played once as a drawn envelope); fade-in delay, start phase, free-running or per note, tempo sync in note lengths (dotted and triplet too), and the DX7's LFO.
- **Modulation matrix** (32 rows): envelopes, LFOs, velocity, key, mod wheel, aftertouch, bend, a random value per note and four macros, each row scaled by up to two more sources, onto pitch, both filters' cutoff and resonance, filter feedback, amp, pan, every oscillator's pitch, level, FM depth, width and wavetable position, LFO rates, the comb, and envelope times.
- **Playing**: poly up to 32 voices, mono and legato with last, low or high note priority and optional retrigger from zero; glide; bend range; velocity sensitivity and curve; a level by key; an arpeggiator (up, down, up-down, random; 1–4 octaves; synced rate; gate up to tied); per-voice-slot pan and analogue-style slop in pitch, cutoff, envelope times and level.
- **Effects**, chained in any order: chorus, flanger, phaser, three-band EQ, compressor, saturation, pitch shift, ring modulator, growl, bit crusher, delay (stereo, cross or ping-pong, tempo-synced, spread), Freeverb-style reverb (predelay, filters), a filter, a peak limiter, a frequency shifter and a rotary speaker. Chorus, flanger, phaser, EQ, compressor, saturation, the limiter, the frequency shifter and the rotary speaker also run on Godot buses.
- **Live and baked alike**: the same notes and seed give the same samples live (native), baked natively and baked in GDScript; edits are heard on held notes, and effect tails ring on through edits.
- **From other synths**: converters for DX7, Casio CZ, Synth1, TAL-NoiseMaker, Helm, OB-Xd/OB-Xf and Surge XT patches (`tools/patch_convert/README.md`), a library of 21,817 converted patches (`docs/library.md`), and sample matching that turns a recording into a patch (`docs/sample_matching.md`).

## Building patches

The easiest way to build one is the Sound Lab's Synth page: panels for every setting below, a library browser (the kit's presets, your patches and folders of converted patches, with filters and ratings), a scope and spectrum, and a keyboard (`docs/sound_lab.md`). In the editor you can also select a patch to play it from the Audio Kit dock (single notes, a chord, an arpeggio, a glide), live when the native core is installed, and edit it in the inspector; the next note uses the edit, and a playing `AKSynthStream` picks it up at once. From a script, call `patch.emit_changed()` after changing a patch's keys: the stream recompiles on that signal, and held notes carry on.

## Signal path

Per voice: oscillators (each stacked `unison` times, spread across the stereo field by `spread`) are summed by their levels, run through the filter block (`comb`, `pre_filter`, `filter` and `filter2`, the saturation; see Filter), and multiplied by the amp envelope, velocity, the `amp` modulation and `gain_db`; then panned. Voices sum into a stereo output, which runs through the patch's `effects`.

Envelopes, oscillators and the filter run every sample. Modulation (LFOs, the matrix, glide, pitch, oscillator settings, filter coefficients, amp and pan) is worked out every 8 samples (6 kHz) and held in between. That keeps 32 two-oscillator voices under 10% of a core (about 9% on the test machine; `tests/test_synth.gd` checks it); the steps are far too small to hear on vibrato, sweeps and FM envelopes.

## Oscillators

Up to sixteen, in `oscillators`:

| Key | Default | What it does |
| --- | --- | --- |
| `shape` | sine | `sine`, `triangle`, `saw`, `square`, `pulse`, `noise`, `morph`, `table` (a wavetable), `pd` (phase distortion, as the Casio CZ: see Phase distortion), `sample` (a recorded or rendered sound: see Sample layers), `partials` (additive sine partials), `modal` (a struck or resonating mode bank: see Partials and modes) or `grains` (a granular cloud: see Grains); saw, square, pulse and tables are band-limited |
| `level` | 1.0 | Its level in the mix; 0 makes a pure modulator |
| `semitones`, `cents` | 0 | Offset from the note |
| `width` | 0.5 | Pulse width (`pulse` only), 0.01–0.99 |
| `position` | 0 | `morph`: 0 sine, 0.33 triangle, 0.66 saw, 1 square, blended between. `table`: 0 the first frame .. 1 the last |
| `table` | basic | `table` only: a built-in name (`basic`, `pwm`, `vowel`, `organ`, `bright`, `digital`) or `{frames = [...]}` (see Wavetables) |
| `fm_from` | 0 | 1-based number of another oscillator that phase-modulates this one; 0 = none |
| `fm_index` | 0 | Modulation depth in radians |
| `sync_to` | 0 | 1-based oscillator whose cycle restarts this one's (hard sync); sweep this one's pitch for the classic sync sound |
| `ring_from` | 0 | 1-based oscillator this one is multiplied by (ring modulation: sum and difference tones) |
| `pan` | 0 | −1 left .. 1 right, equal power: oscillators placed apart in the stereo field (a layer to one side, a sub in the middle) |
| `filtered` | true | false: the oscillator goes around the filter, straight to the amp (a bright noise click over a filtered tone) |
| `filter` | both | Which filter path it takes: `"1"`, `"2"`, `"both"` or `"none"` (`"none"` is `filtered = false`; the others matter only with `filter2`, see Filter 2) |
| `fm_mode` | phase | How `fm_from` and `fm` move this oscillator: `phase` (phase modulation, `fm_index` in radians), `pitch` (its pitch, `fm_index` semitones per unit of the modulator's output: exponential FM, an analog cross mod) or `linear` (its frequency, `fm_index` Hz per unit, through zero: the phase runs backwards when the frequency goes negative) |
| `color` | white | A `noise` oscillator's color: `white`, `pink` (−3 dB an octave) or `red` (−6 dB an octave), all at the same level |
| `phase` | – | Where the oscillator starts each note, in cycles (0–1). Absent: at 0, or at seeded random phases with unison or a stack; set, every copy starts here |
| `phase_with` | 0 | 1-based oscillator whose start phases this one takes (copy for copy), plus `phase`: a saw and a pulse built from one analog oscillator stay aligned under unison |
| `stack`, `stack_cents` | 1, 0 | This oscillator alone copied 1–16 times, spread evenly across `stack_cents`, with seeded random start phases: a thick detuned osc 1 beside a plain osc 2. It multiplies `unison` (a stack of 8 with unison 3 is 24 copies), up to 64 copies: a stack is cut to fit under wide unison (unison 16 holds a stack of 4). FM, sync and ring between oscillators with different stacks read the same unison voice of the other oscillator (and its copy, when it has as many) |

Oscillators are computed last to first, so an oscillator modulated by a later one hears it this sample; one modulated by itself or by an earlier one hears the previous sample (feedback). The classic two-operator FM pair is `[{shape = "sine", fm_from = 2, fm_index = 2.0}, {shape = "sine", level = 0.0, semitones = 12.0}]`.

`unison` (1–16) stacks every oscillator, spread evenly across `detune_cents` (0–100), with seeded random start phases; noise isn't stacked. `unison_level` (0–1, default 1) is the stacked voices' level against the middle one (or the middle two, for an even count): 1 keeps them equal, lower gives a solid centre with a quieter shimmer around it. The stack is scaled to keep its power, so turning it down doesn't change the loudness much. `spread` (0–1) pans the stacked voices across the stereo field, equal power (0 keeps the patch mono). A patch with `spread` or any oscillator `pan` runs its filter on left and right separately.

`unison_pitch` (semitones, −24 to 24, default 0) raises the odd-numbered unison voices (the 2nd, 4th ...) by an interval: 12 an octave, 7 a fifth, negative for below. With two voices and no detune it is the plain interval; with more, every other voice of the detuned spread.

`drift = {cents, rate_hz}` (default off) makes the oscillators wander in pitch the way analogue ones do: each voice's each oscillator glides along a half cosine to a new random offset within ±`cents` about `rate_hz` times a second (default 0.5), seeded by `seed`, so two oscillators of one voice and the same oscillator in two voices all drift apart. An oscillator's own `drift` (default 1) scales its share, 0 holding it steady (a sub, an FM modulator whose ratio must stay exact). A few cents at 0.2–1 Hz gives the gentle life of an old polysynth; 20–50 cents is a warped tape or a failing oscillator. Unlike `slop`, which fixes an offset per voice slot, drift keeps moving while a note is held.

Hard sync isn't band-limited: the restart is a hard edge, so very bright sync sweeps alias a little at high notes.

### Operators (FM graphs)

These fields turn oscillators into FM operators; an oscillator without them is a plain oscillator.

| Key | Default | What it does |
| --- | --- | --- |
| `fm` | – | `[{from, index}, ...]`: several modulators, summed (index in radians per unit of the modulator's output). Runs alongside `fm_from`/`fm_index`; the matrix's `oscN.fm` still moves `fm_index` |
| `feedback` | 0 | Self-modulation in radians on the average of its last two outputs (a DX7's smoothing) |
| `level_env` | 0 | 1-based envelope (1 `amp_env`, 2 `env2`, 3 `env3`, 4.. `envelopes`) this oscillator follows: what you hear of it, and what it sends to the oscillators it modulates |
| `ratio` | 1 | Multiplies the note's frequency (after `semitones`, `cents`) |
| `fixed_hz` | 0 | A fixed frequency that ignores the key; bend and matrix pitch still move it |
| `dx7_freq` | – | `{mode, coarse, fine, detune}` (defaults 0, 1, 0, 7), a DX7 operator's raw values: msfa's exact phase increment (its log frequency and lookup table), the matrix pitch added in its log domain for ratio operators, only the bend for fixed ones. The key is the note plus `semitones` (a voice's transpose). Its sine is read from msfa's 1024-point table |
| `velocity_sens` | 0 | Level × `1 − s · (1 − velocity)` |
| `key_scaling` | – | `{break_key, left_db_oct, right_db_oct, left_curve, right_curve}`: dB per octave either side of the break key (default 60); curves `lin`, or `exp` (depth × (2^octaves − 1)) |

When every audible oscillator has a `level_env`, the voice ends when all of those envelopes have finished (as a DX7 voice ends with its carriers), whatever `amp_env` does.

`AKPatchLib.dx7_algorithm(n)` gives the DX7's 32 algorithms as `{carriers, mods, feedback}` (from msfa's table) for building `fm` lists. `tools/patch_convert/dx7.gd` converts DX7 voices this way (see its README); converted factory voices match msfa's renders to about 66 dB SNR (median of each voice's worst note).

### Phase distortion

A `pd` oscillator is the Casio CZ's: a cosine whose phase is bent by a transfer function, as MAME's emulation of the CZ's uPD933 chip (`upd933.cpp`, BSD-3-Clause, Devin Acker) does it, in the chip's own integer arithmetic (an 11-bit phase, a 12-bit cosine), so it has the chip's grit. It isn't band-limited, as the chip isn't.

| Key | Default | What it does |
| --- | --- | --- |
| `pd_wave` | saw | `saw`, `square`, `pulse`, `double_sine`, `saw_pulse`, `resonance` (the cosine's frequency multiplied by the amount and restarted each cycle: a hard-sync sweep), `double_pulse`; `silent` plays only the window's offset |
| `pd_wave2` | – | A second wave the oscillator alternates with, a cycle each (the CZ's wave pairs, which sound an octave down) |
| `pd_window` | none | `saw`, `triangle`, `trapezoid`, `pulse`, `double_saw`: fades each cycle (the CZ's resonance waves are `resonance` with the `saw`, `triangle` or `trapezoid` window). The chip's centring keeps an offset under a window |
| `pd_amount` | 0 | 0 a cosine .. 1 the full wave (the CZ's DCW). It is the oscillator's `position`, so `oscN.position` rows move it |
| `shape_env` | 0 | 1-based envelope added to the amount (a `cz` `dcw` envelope, or any other) |
| `pitch_env` | 0 | 1-based envelope added to the pitch in semitones (a `cz` `dco` envelope) |
| `pd_noise` | false | The chip's noise modulation: every 8 chip samples (5 kHz), the pitch is the note's or 32 semitones up, at random |

As on the chip, the amount is held down at high pitches (1 − f / 5 kHz at most), so narrow waves stay audible and high notes don't alias as much. `ring_from` multiplies by another oscillator, as the CZ's ring modulation does; `fm`, `sync_to` and `fm_mode` don't apply. One line at full level from the chip is 1/8 of full scale: a `pd` oscillator at level 1 is that line × 8.

### Sample layers

A `sample` oscillator plays a sound once per note, pitched by the key: an attack layer (a hammer, a pick, a breath, a bow's scrape) on top of synthesis, a key-up noise, or a whole sampled sound. `sample` is an `AKSample` (`root_note`, trim `start_s`/`end_s`, `mode`, loop points, `reverse`, `gain_db` all apply), an `AKRecipe` (rendered once, played as recorded at middle C), or a path to either or to a .wav, .aif or .ogg. Recipe sources keep a patch licence-clean and small: the sound is rendered from its recipe wherever the patch plays.

| Key | Default | What it does |
| --- | --- | --- |
| `sample` | – | The sound (above). A sample oscillator without one is silent |
| `track` | 1 | How far it follows the key: 1 transposes by the key against the sample's `root_note` (its root plays it as recorded); 0 plays it at its root on every key (noises, clicks); between, part way |
| `start_s` | 0 | Seconds into the (trimmed) sound to start |

The oscillator's `semitones`, `cents`, pitch rows, bend, glide and drift move it as any oscillator; `level`, `pan`, `filter` and `level_env` apply too. A `oneshot` or `gate` sample plays to its end and then stays silent (the amp envelope still ends the note); a `loop` sample repeats its loop for as long as the voice sounds. It restarts at each note and at a mono retrigger. With a key-up envelope as its `level_env` (`trigger = "release"`, see Envelopes) it waits at its start until the key-up and plays from there: a release layer (a harpsichord's jack falling back, a piano's damper, an organ's key-off click). One play head per voice: unison, `stack` and FM to it don't copy or bend it (it can be an FM or ring source). Reading uses 4-point interpolation without band-limiting, so a sound transposed far up can alias: keep sample layers for noisy, short material, or record near the pitch they play. The sound is mono (a stereo file plays as its mid); the bake key holds the sound's description, so a different sound gives a different bake.

### Partials and modes

A `partials` oscillator sums sine partials, each at its own `ratio` to the oscillator's pitch, with its own `level` and `decay_s`: inharmonic tones, bells, piano strings, organ-like additive sounds. A `modal` oscillator is the same bank as a struck object: it defaults to a `material`'s modes and decays and rings from note-on, or resonates another oscillator (`excite_from`).

| Key | Default | What it does |
| --- | --- | --- |
| `partials` (or `modes`) | 8 (partials) / the material's (modal) | A count N (the harmonic series 1..N, levels 1/n^`rolloff`), or a list of ratios or `{ratio, level, decay_s}`. Up to 32 per oscillator, 64 per patch |
| `material` | – / `wood` | Modes from physics: `wood` (a tuned marimba bar), `bar` (a free bar: 1, 2.76, 5.40, 8.93 ...), `metal` (the same, ringing long), `glass`, `stone`, `skin` (a membrane's Bessel modes), `plate` (dense), `bell` (hum, prime, tierce, quint, nominal ...). Sets the modes, `decay_s` and `damping` (each overridable) |
| `decay_s` | 0 / the material's | The fundamental's decay time constant (0: partials sustain) |
| `damping` | 0 / the material's | Higher partials decay faster: decay_s × ratio^−damping (a partial's own `decay_s` wins) |
| `rolloff` | 1 | The count form's level slope (1: a saw's 1/n; 2: a triangle-ish 1/n²; 0: all equal) |
| `stretch` | 0 | Inharmonicity B: every ratio r becomes r √(1 + B r²), a stiff string's stretched partials (piano: 0.0001–0.001, low strings more) |
| `hardness` | 1 | Softer (lower) takes the high modes down (level × ratio^−2(1 − hardness)): a felt mallet against a hard one |
| `normalize` | true | Scale the levels so their root-sum-square is 1 (a sine-level oscillator whatever the count) |
| `excite_from` | 0 | modal only: resonate this oscillator (1-based; often a noise or a short burst at level 0) instead of striking at note-on. Each mode is a resonator of unity gain at its frequency; modes need a decay (1 s if none) |

Each mode is a phasor turned and shrunk by its decay each sample (no per-sample sine), recomputed when the pitch moves (bend, glide, pitch rows, drift). Partials above Nyquist are silent, so nothing aliases. The bank restarts (is struck again) at each note and mono retrigger; `level_env`, `level`, `pan` and the filters apply as to any oscillator; one bank per voice (unison and `stack` don't copy it). Cost, native, per voice: 32 partials about 0.4% of a core (0.55% with the pitch moving every control step), a material's 6–12 modes about 0.2%, against 0.16% for a saw.

### Grains

A `grains` oscillator is a cloud of short windowed grains: rain, fire, crackle, water, crowds, debris, and evolving pads. Each grain plays its `source` at the oscillator's pitch (sample sources: transposed against the sample's root by `track`, as a sample layer) for `grain_ms`, shaped by its window, and starts `density` times a second.

| Key | Default | What it does |
| --- | --- | --- |
| `source` | sine | What a grain plays: `sine`, `triangle`, `saw`, `square` (band-limited), `noise`, or `sample` (with `sample`, `track` as a sample layer; an `AKSample`, `AKRecipe` or path) |
| `density` | 20 | Grains a second (0.1–1000) |
| `grain_ms` | 50 | Each grain's length (1–2000 ms) |
| `jitter` | 0 | Timing: each gap between grains is the even gap × (1 ± jitter) at random (0: a steady stream; 1: anywhere from none to twice) |
| `spray` | 0 | Pitch: each grain up to this many semitones up or down at random |
| `pan_spread` | 0 | Each grain placed at random across this share of the stereo field (makes the synth stereo) |
| `envelope` | hann | The grain window: `hann` (smooth), `tri`, or `perc` (a 10% attack, then a fall as (1 − u)²: clicks, drops, crackle) |
| `position` | 0 | sample source: where grains read in the sound, 0..1 (the matrix's `oscN.position` scans it) |
| `position_jitter` | 0 | sample source: each grain's read point up to this far (a share of the sound) either way at random |

Each grain is at level 1 / √(density × grain length) (at most 1), so the cloud stays near one level as it thickens; `level`, `level_env`, `pan` and the filters apply as to any oscillator. A grain's pitch, place and read point are fixed when it starts: pitch rows, bend and glide reach the grains that start after them. Grains are seeded from the voice (the patch's `seed`), from their own random stream, so adding a grains oscillator doesn't change other noise. A cloud starts with a grain at note-on (and at a mono retrigger). Grains re-reading one place of a sound at a steady density beat at the density's rate (a comb at its harmonics): `position_jitter` or `jitter` smears it. One bank of 32 grains per voice, shared by its grains oscillators (unison and `stack` don't copy it); a grain due while all 32 sound is skipped. Cost, native, per voice: 50 grains/s of 50 ms about 0.25% of a core, 400 grains/s of 80 ms (32 at once) about 0.75%, against 0.16% for a saw.

### Wavetables

A `table` oscillator reads a wavetable: a few frames of one cycle, swept by `position` (modulate `oscN.position` with an LFO or envelope). Built in: `basic` (sine, triangle, saw, square), `pwm` (a pulse narrowing from square), `vowel` (a, e, i, o, u formants on a saw), `organ` (drawbar settings), `bright` (a saw tilting brighter), `digital` (seeded metallic harmonic sets). Your own: `{frames = [{harmonics = [1.0, 0.5, 0.33 ...], phases = [...]}, {samples = [one cycle of any length]}]}` inline, or a path to a JSON file holding that. Each frame is stored at up to 19 band limits (a half octave apart, up to 512 harmonics), and a note reads the richest one whose harmonics all sit below Nyquist, so tables don't alias; limits above the one that holds all of a table's harmonics would be copies, so they aren't stored. Tables are built once per content (`AKWavetables.build`) and cached. A frame normally has its level normalised; `normalize = false` keeps each frame's level against the others, so a table can carry a decay swept by `position`.

**Key zones.** `{zones = [{key = 48, frames = [...]}, {key = 60, frames = [...]}], normalize = false, blend = false}`: a set of frames per key, like a sampler's key zones. A note plays the two zones around it, blended by key, or with `blend = false` the nearest zone alone (blending zones whose harmonics' phases differ can thin the sound between them). Below the first zone and above the last, the end zone plays. A zoned table stores only four band limits below its richest (two octaves of headroom above each zone's key), since each zone plays near its own key. This is what the sample-matching tools build from a recording: cycles taken from the held notes at points through each note, every three semitones (see `docs/plans/sample-matching.md`).

## Filter

`filter = {type, cutoff_hz, q, slope_db}`: `off`, `lowpass`, `highpass`, `bandpass` or `notch`; a state-variable filter, 12 dB per octave, or 24 with `slope_db = 24`. Missing keys are `lowpass`, 18000 Hz, q 0.707 and 12 dB; an unknown type is `off`.

`filter = {type = "ladder", cutoff_hz, resonance, drive}`: a four-pole (24 dB) ladder low-pass, solved without delay in its feedback. `resonance` 0–1 (default 0.3; near 1 it rings at the cutoff; up to 1.2 it oscillates on its own); `drive` (default 1) pushes it into soft saturation, which also tames the resonance on loud input. Some of the bass a resonant ladder loses is made up. The matrix's `q` destination scales the resonance.
- `poles` (1–4, default 4): the low-pass taken after that many poles (6, 12, 18 or 24 dB per octave); a fractional value crossfades the two around it (an OB-Xd's 24 dB mode morphing from four poles to one). Resonance always feeds back from the fourth pole.
- `pole_mix` (`[input, pole 1, pole 2, pole 3, pole 4]`): the output is this mix of the ladder's input (after the feedback) and its poles, overriding `poles`. The Oberheim Xpander's modes come from it: `[1, -4, 6, -4, 1]` a four-pole high-pass, `[0, 0, 4, -8, 4]` a band-pass, `[1, -2, 2, 0, 0]` a notch, and so on.

`filter = {type = "mix", cutoff_hz, q, low, band, high}`: the state-variable filter's three outputs mixed (weights; defaults 1, 0, 0). `low = 1` alone is `lowpass` exactly, `high = 1` alone `highpass`; `low = high = 1` a notch; sliding the weights morphs LP → notch → HP or LP → BP → HP.

`filter = {type, cutoff_hz, q, gain_db}` with type `lowshelf`, `highshelf` or `bandshelf` (a bell at the cutoff): `gain_db` (−48..48) boosts (or, negative, cuts) that side. All the state-variable types take `slope_db = 24` (two in a row).

`diode = true` on `lowpass`, `highpass`, `bandpass`, `notch` or `mix` gives the filter OB-Xf's diode-pair damping: each sample, the damping (1 / (2 q)) grows with the filter's band state, by OB-Xf's polynomial on 0.0876 × that state. At small signals it is the plain filter; loud resonant signals are held back, and `damping` (instead of q; it may be negative) lets it self-oscillate at the cutoff with the diodes holding the level, as OB-Xf's 2-pole does at full resonance and with push. A matrix `q` row scales the damping as it scales 1 / q. The diode's term depends on the signal level, so it sounds as OB-Xf's only with oscillators at OB-Xf's levels (as the OB-Xf converter sets them).

`filter = {type = "allpass", cutoff_hz, q}`: every frequency at its level, the phase turning through the cutoff (x − 2k band of the state-variable filter); the phaser's building block, or a smear when another path is summed with it.

`filter = {type = "comb", cutoff_hz, comb_feedback}` (feedback −0.99–0.99, default 0.5; negative gives the odd harmonics): a comb at the cutoff frequency, as either filter. Each sample adds `comb_feedback` times the output one period of the cutoff back, read between samples; `q` rows scale the feedback. Unlike `comb` (below) it doesn't follow the note on its own: a `key → cutoff` row of 1 makes it track the keyboard. `comb_damp_hz` (default 0, off) puts a one-pole low-pass in its loop, as `comb`'s `damp_hz` does. Up to 64 voices have one.

`filter = {type = "formant", vowel, formant_set, formant_shift, formant_q}`: a vocal tract. Five resonant band-passes in parallel, each unity at its peak and set to a formant's frequency, bandwidth and level, so a buzzy source (a saw, a pulse, a stack) comes out as a sung vowel. `vowel` (0–1, default 0) morphs a → e → i → o → u (0, 0.25, 0.5, 0.75, 1), the formants joined by straight lines in between; `formant_set` picks the voice the tables describe, `bass`, `tenor` (default), `alto` or `soprano`; `formant_shift` (semitones) moves every formant together, smaller or larger throat; `formant_q` (default 1) scales every formant's Q, sharper and more whistly above 1, blurrier below. The matrix's `vowel` (filter 1) and `vowel2` (filter 2) move the vowel (an LFO makes "wah-oh-wah", the mod wheel or an envelope a talking sweep), `cutoff`/`cutoff2` rows shift the formants in octaves, `q`/`q2` rows scale their Q. The tables follow the formant table in the Csound manual (after published measurements of sung vowels). Choirs, voices, talk boxes; in filter 2 in parallel with a low-pass, a horn or a reed's body.

`filter_feedback` (−1..1, default 0) feeds the filter block's output (after filter 2) back into filter 1's input through tanh, a sample late: Surge's filter feedback, from a gentle thickening to screaming self-oscillation with a resonant filter. The matrix's `feedback` moves it (clamped to −1..1).

`sat_gain_db` and `sat_ceiling` on any filter add a soft clipper after it, before the amp: c (1 − e^−|u|) with u = g x / c, g the small-signal gain (from `sat_gain_db`) and c the ceiling the output never passes. Quiet signals take the gain, loud ones flatten toward c with odd harmonics, and since it comes before the amp envelope a release fades without changing its tone (Synth1's filter saturation).

`sat_curve = "tanh"` makes it c tanh(g x / c): the same gain and ceiling, a softer knee (Surge's soft waveshaper).

`pre_filter = {lowpass_hz, highpass_hz}`: one-pole filters (6 dB per octave) on the filtered oscillators before the main filter, each off when absent: an OB-Xd's brightness knob, or a gentle high-pass ahead of a resonant low-pass.

`comb = {semitones, cents, feedback}` (feedback −0.99–0.99): a comb tuned to the note, on the filtered oscillators before `pre_filter`. Each sample adds `feedback` times the output one period back, the period of the voice's pitch (with bend, glide and pitch modulation) moved by `semitones` and `cents`, read between samples by a straight line. Positive feedback rings at the note's harmonics, negative at the odd ones; this is Helm's oscillator feedback. Periods are capped at 4,096 samples (12 Hz at 48 kHz).
- `damp_hz` (default 0, off): a one-pole low-pass inside the loop, so each pass round it takes a little more of the highs and the high harmonics die faster than the low ones, as on a plucked or struck string (Karplus-Strong). With a short noise burst or click as the input (an oscillator with a fast `level_env`) and feedback near 0.98, it is a plucked string. Lower is duller and dies sooner.
- `damp_track` (0–1, default 0): the damping cutoff follows the comb's pitch, `damp_hz × (pitch / middle C)^damp_track`; 1 keeps the tone the same up the keyboard, 0 makes high notes relatively brighter-sounding and shorter-lived.
- The matrix's `comb.damp` moves the damping cutoff in octaves.

### Filter 2

`filter2` takes the same types and fields as `filter` (state-variable types, ladder, `mix`, shelves, `allpass` and the `comb` type; not `diode`, the saturation, `pre_filter` or the note-tuned `comb`, which stay on filter 1). Empty, the default, is off. `filter_routing`:

- `series` (default): filter 1, then filter 2: a Juno-106's high-pass and low-pass, or two low-passes for 36 or 48 dB.
- `parallel`: the two side by side, their outputs summed.

Each oscillator's `filter` picks its path: `"1"`, `"2"`, `"both"` or `"none"` (`filtered = false` is `none`). In series, `1` and `both` (the default) run through filter 1 and then filter 2, and `2` goes into filter 2 only. In parallel, `both` (the default) feeds each filter, and `1` or `2` feeds one. Matrix destinations `cutoff2` and `q2` move it as `cutoff` and `q` move filter 1, and a voice slot's cutoff slop moves both.

## Envelopes

`amp_env`, `env2`, `env3`, each `{attack_s, decay_s, sustain, release_s, curve}`. Attack rises linearly (0 = start at full level). Decay is linear, or with `curve = "exp"` a time constant toward `sustain`. Release is a time constant from wherever the level is when the note ends. An optional second stage, `release_knee` (0–1, a share of the level at key-up) and `release2_s`: once the release falls to the knee it goes on with the second time constant, so a release can drop at once and then trail off (as sample-playback synths' releases often do). Without `release2_s` the release is one stage. Missing keys are attack 0, decay 0.2 s, sustain 0 and release 0.15 s. `amp_env` sets the level (and is the matrix source `env1`); `env2` and `env3` only act through the matrix.

**Key-up envelopes.** `trigger = "release"` on any envelope (an ADSR or stages one) starts it at the key-up instead of the key-down: it holds at 0 while the key is down, then runs once from the release, ignoring its sustain and loop. An ADSR becomes a one-shot of its attack, decay to the sustain level, and a fall to 0 over five release time constants. Give an oscillator `level_env` on it and that oscillator sounds only when the key is let go: a harpsichord's jack falling back, an organ key's release click, fret noise, a piano's damper. A mono or legato note change doesn't fire it (no key-up happened); the last key-up does. The amp envelope still shapes the whole voice, so give `amp_env` a release at least as long as the layer; a voice whose every audible oscillator follows its own envelope ends when those finish, key-up layers included.

`envelopes` adds up to five more, the matrix sources `env4` to `env8`. Any envelope, these and the first three alike, can take one of two other forms. A dictionary with neither `stages` nor `mode` is the ADSR above, unchanged.

### Stages

```
env2 = {stages = [{time_s = 0.01, level = 1.0}, {time_s = 0.3, level = 0.4, curve = "exp"},
		{time_s = 1.5, level = 0.2, curve = "power", amount = -2.0}, {time_s = 0.4, level = 0.0, curve = "exp"}],
	sustain = 2, loop = [1, 2], start = 0.0, delay_s = 0.0, hold_s = 0.0,
	time_key = 0.0, time_key_center = 60, time_key_stages = [], time_velocity = 0.0, time_velocity_stages = [],
	level_velocity = 0.0}
```

- **Stages and curves.** Up to 32 stages (counting the ones `delay_s` and `hold_s` add). Each stage moves from wherever the level is to its `level` over `time_s` (0 jumps). The curves are:
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

### CZ

```
envelopes = [{mode = "cz", kind = "dca", steps = [[119, 127], [80, 110], [60, 0]], sustain = 1, end = 2}]
```

A Casio CZ envelope in the CZ's uPD933 values, as a tone's data holds them: up to 8 steps of `[rate, level]` or `{rate, level}` (0–127 each), the `sustain` step (0-based, −1 none) and the `end` step. It runs as MAME's emulation of the chip does: each step moves linearly in the chip's units, by `(8 + rate mod 8) × 2^(rate / 8)` per 40 kHz sample (scaled to the mix rate), to its level; when it lands the next step starts, the sustain step holds until the key-off, which moves on to the step after it, and the end step stays. A step goes up or down from wherever the envelope is.

`kind`:
- `dca`, a level: the chip's log volume, 13 doublings over levels 0–127 (about 0.6 dB a step, 127 = 1, 0 silent). Follow it with an oscillator's `level_env`. The voice ends when it is released and at its end step.
- `dcw`, the phase distortion amount: level / 127 (follow it with `shape_env`).
- `dco`, pitch: levels below 64 are 1/16 semitone each; with 64 added, 2 semitones each (follow it with `pitch_env`).

`AKPatch.cz_tail_s` gives its time from the key-off to the end step. `tests/test_cz.gd` holds `pd` oscillators with `cz` envelopes to MAME's chip itself (`tools/cz_ref`).

## LFOs

`lfo1`, `lfo2`, each `{shape, rate_hz, delay_s, width, phase, free}`: `sine`, `triangle`, `saw`, `square`, `random` (a new random value each cycle), `smooth` (a new random value each cycle, glided to along a half cosine) or `custom` (drawn points, below). `rate_hz` is 1 when absent. They restart with every note, at `phase` (cycles, default 0); `delay_s` fades them in (delayed vibrato). `free = true` runs the LFO from the start of playback instead, as a hardware LFO or chorus does: each note picks it up where it is, and `phase` is where it was when playback started (the matrix's `lfoN.rate` rows still bend it, per voice, from there). `width` (square only, 0.01–0.99, default 0.5) is the part of each cycle it's high: a short width on an oscillator's level makes rhythmic clicks or gates. The matrix can move an LFO's rate (`lfo1.rate`, `lfo2.rate`, in octaves): an envelope there makes a wobble that speeds up or slows down through the note.

`rate_sync` sets the rate from the tempo instead of `rate_hz`: a note length per cycle, `"1/4"` (a beat), `"1/8."` (dotted), `"1/8t"` (triplet), `"2/1"`, or a number of beats. A free synced LFO counts from the start of playback, so it lines up with the beat; a tempo change keeps its phase and changes its speed from there.

Shape `custom` takes `points` (2–256 values, −1..1, spread across one cycle), `interp` (`linear`, joining them, or `step`, holding each) and `once` (true: from the first point to the last in one cycle, then the last held: a drawn envelope, which with `rate_sync` follows the tempo). Summed classic shapes, step sequences and drawn curves all go in points.

`lfos` adds up to six more, lfo3 to lfo8 in order, each with lfo1's keys (all but the dx7 mode's): matrix sources `lfo3` .. `lfo8`, destinations `lfo3.rate` .. `lfo8.rate`. Only the LFOs a patch defines run, so a patch without `lfos` costs nothing extra. Their `random` and `smooth` shapes draw from streams of their own, so adding one doesn't change lfo1's, lfo2's, the `random` source's or noise's values.

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
- **`mode`**: `up` (default), `down`, `updown` (the top and bottom notes aren't repeated), or `random` (seeded by the patch's `seed`, so the same notes give the same order).
- **`octaves`** 1–4 (default 1): the chord repeated an octave higher each time.
- **`rate`**: the step, a note length as for `rate_sync`, at the tempo (default `"1/16"`).
- **`gate`** 0.01–1 (default 0.5): the share of each step a note sounds. At 1 the steps tie: each note starts before the last one ends, so a `legato` patch glides through the pattern without retriggering.
- **Timing.** The pattern starts with the first key down, whose first step plays on that sample. Keys added later join from the next step. Releasing the last key stops it and releases the sounding note.
- **Velocity.** Each note plays at the velocity of the key it came from.
- **Voices.** Steps play through the patch's own voice allocation (poly, mono or legato). The sustain pedal doesn't hold the arpeggiator's keys.

Live, baked, native and GDScript give the same steps.

## Modulation matrix

`mods`, up to 32 rows of `{source, dest, amount}`. Each row adds `amount × source` to the destination. A row may name a second source in `via`: it then adds `amount × source × via` (vibrato as `{source = "lfo1", via = "mod_wheel", dest = "pitch", amount = 0.5}`, an envelope's depth following the key as `via = "key"`). `via2` multiplies it by a third (an LFO faded in by an envelope, its depth on a macro).

| Source | Range |
| --- | --- |
| `env1` (amp), `env2`, `env3`, `env4` .. `env8` (`envelopes`) | 0..1 (a dx7 envelope can exceed 1 with velocity) |
| `lfo1`, `lfo2`, `lfo3` .. `lfo8` (`lfos`) | -1..1 |
| `velocity` | 0..1 |
| `key` | octaves from middle C (C5 = 1) |
| `mod_wheel`, `aftertouch` | 0..1 (from `set_mod_wheel`, `set_aftertouch`) |
| `random` | -1..1, new for every note |
| `bend` | -1..1 (the pitch bend also moves pitch by `bend_range` on its own) |
| `macro1` .. `macro4` | 0..1: the patch's `macros` (`[m1, m2, m3, m4]`, default 0), knobs a host turns by editing the patch (held notes carry on) |

| Destination | Unit |
| --- | --- |
| `pitch` | semitones |
| `cutoff`, `q` | octaves (multiplies by 2^amount) |
| `cutoff2`, `q2` | the same for `filter2` |
| `feedback` | added to `filter_feedback` (−1..1) |
| `env1.attack` .. `env8.attack`, `.decay`, `.release` | as `envN.time`, for one part: the first stage, the stages after it up to the sustain stage, or those after the sustain stage (all after the first, for a one-shot) |
| `env1.time` .. `env8.time` | octaves of time: +1 doubles every stage's time. Read as each stage starts, so it works on `stages` envelopes (not classic ADSR or dx7 ones); at note-on, from the sources a note starts with (velocity, key, random, the controllers, macros; envelopes and LFOs count as 0) |
| `amp` | added to a gain of 1 (−1 silences, +1 doubles) |
| `pan` | −1 left .. 1 right |
| `oscN.pitch` | semitones (N is 1-based; for every `oscN` destination, `osc.` without a number, as `osc.pitch`, means every oscillator) |
| `lfo1.rate` .. `lfo8.rate` | octaves (multiplies the rate by 2^amount) |
| `comb.feedback` | added to `comb`'s feedback (kept within ±0.99) |
| `comb.pitch` | semitones (moves `comb`'s tuning) |
| `comb.damp` | octaves (moves `comb`'s damping cutoff, when `damp_hz` is set) |
| `vowel`, `vowel2` | added to the formant filter's `vowel` (filter 1, filter 2), 0–1 across a e i o u |
| `oscN.level`, `oscN.fm` (radians), `oscN.width`, `oscN.position` | added to the oscillator's setting |
| `fxN.key` | an effect's setting (below) |

**Effect settings.** `fxN.key` moves setting `key` of the Nth effect in `effects` (1-based): `fx1.cutoff_hz`, `fx2.mix`, `fx3.shift_hz`, `fx4.speed`. Frequencies, rates and times marked log below take the amount in octaves (the setting × 2^amount); the others add it in the setting's units; either way the result stays within the setting's range. The effects run once, on the summed voices, so a row reads the newest voice's sources (as a mono synth would): its envelopes and LFOs, its velocity and key, and the patch-wide ones (macros, the mod wheel, aftertouch, bend, free LFOs) the same in any voice. They move every control step (8 samples) while that voice sounds; when it has ended, the settings hold where they were until the next note. Wah (`env2 → fx1.cutoff_hz`), a rotary's speed on the mod wheel (`mod_wheel → fx2.speed`, which eases in as the cabinet does), a growing echo (`macro1 → fx3.time_ms`), a filter sweep on a reverb's tail.

| Effect | Settings rows move (log: octaves) |
| --- | --- |
| every effect with `mix` | `mix`, `dry`, `wet` (a `dry` or `wet` row fixes that gain from the effect's own; `mix` rows no longer move it) |
| chorus, flanger, phaser, delay, freqshift | `feedback` |
| chorus, flanger | `rate_hz` (log), `depth_ms` (0–50), `delay_ms` (log, up to 50), `spread` |
| phaser | `rate_hz`, `center_hz` (log), `range_octaves`, `depth`, `spread` |
| eq | `low_db`, `mid_db`, `high_db` (±48), `low_hz`, `mid_hz`, `high_hz`, `mid_q` (log) |
| compressor | `threshold_db`, `ratio`, `knee_db`, `makeup_db` |
| saturate | `drive_db`, `tone_hz` (log), `asymmetry`, `output_db` |
| pitch | `semitones` |
| ring | `freq_hz`, `rate_hz` (log), `depth` |
| growl | `rate_hz` (log), `depth`, `jitter` |
| crush | `bits` |
| delay | `time_ms` (log; not on a `time_sync` delay), `damp_hz` (log) |
| reverb | `room`, `damp`, `width` |
| filter | `cutoff_hz`, `q` (log) |
| limiter | `ceiling_db` |
| freqshift | `shift_hz` (in Hz, as it can cross 0), `stereo` |
| rotary | `speed`, `drive`, `spread`, `doppler`, `tremolo`, `horn_hz`, `drum_hz`, `crossover_hz`, `accel_s` (log) |
| stutter | `rate_hz`, `resample_hz` (log; not when synced), `softness`, `pitch` |
| conditioner | `bass_db`, `treble_db`, `width`, `balance`, `threshold_db`, `output_db` |
| geq | `band1_db` .. `band11_db`, `output_db` |
| resonator | `freq1_hz` .. `freq3_hz`, `q1` .. `q3` (log), `gain1_db` .. `gain3_db`, `output_db` |
| exciter | `freq_hz` (log), `drive` |
| waveshaper | `drive_db`, `bias`, `output_db` |
| midside | `mid_db`, `side_db`, `mid_pan` |
| ensemble | `slow_hz`, `fast_hz`, `center_ms`, `tone_hz` (log), `slow_depth`, `fast_depth`, `width` |
| combulator | `tune_hz`, `tone_hz` (log), `offset2`, `offset3`, `resonance`, `noise`, `gain1_db` .. `gain3_db`, `width` |
| tape | `bump_hz`, `hf_hz` (log), `drive_db`, `hyst`, `wow`, `flutter`, `bump_db`, `output_db` |
| treemonster | `track_lp_hz`, `track_hp_hz` (log), `threshold_db`, `glide_ms`, `pitch`, `width` |
| spring | `decay_s`, `length_ms`, `tone_hz` (log), `chirp`, `width` |
| bonsai | `bass_hz`, `tone_hz` (log), `boost_db`, `harmonics`, `drive_db`, `output_db` |
| chow | `ratio`, `tone_hz` (log), `threshold_db`, `drive_db`, `output_db` |
| neuron | `size_ms`, `wobble_hz`, `tone_hz` (log), `regen`, `drive`, `wobble`, `width` |

Settings that size a buffer (`window_ms`, `echo_ms`, `predelay_ms`, `spread_ms`) or pick a structure (`voices`, `stages`, `mode`, `slope_db`, `hold`) can't be moved. A moved chorus or flanger delay gets a line for 100 ms, a moved delay time one for 2 s, so they never run out; a delay's time moves in whole samples, so a fast sweep of it ticks (slow sweeps and steps are clean). Up to 32 settings per patch. A row naming an effect that isn't there or a setting that can't move is dropped with a warning.

## Playing

| Setting | What it does |
| --- | --- |
| `mode` | `poly`; `mono` (one voice, envelopes restart on each note); `legato` (one voice, envelopes carry on while notes overlap). In mono and legato, releasing the top note returns to the one still held |
| `polyphony` | 1–32 voices (default 8). A new note beyond that takes over the oldest releasing voice, else the oldest |
| `glide_s` | Portamento time constant, 0–2 s (0, the default, jumps) |
| `bend_range` | Semitones at full bend, 0–24 (default 2) |
| `velocity_sens` | 0: velocity doesn't change the level; 1: level follows velocity (default 0.5) |
| `velocity_curve` | How velocity maps to level (0.25–4): 1 linear (at full sensitivity velocity 64 is 6 dB down), 2 squared (12 dB), below 1 gentler. Only the level: the matrix's `velocity` source stays linear |
| `key_levels` | Level by key: `[[key, dB], ...]`, joined by straight lines in dB and flat past the ends (empty: the same on every key). For an instrument whose loudness doesn't follow a straight line across the keyboard; the matrix's `key → amp` is linear |
| `gain_db`, `pan` | Output level and balance |
| `band_limited_sync` | Smooth each hard-sync reset (a polyBLEP across the two samples around it) instead of jumping: sync sweeps alias far less. The synced oscillator resets where its master wrapped, a sample later than without. Off by default (older patches render as they did) |
| `sinc_blep` | Smooth saw and pulse edges (morph's too) with a windowed-sinc BLEP, 8 samples each side, instead of the 2-sample polyBLEP. Flat to about 16 kHz at 48 kHz (1 dB down at 16-20 kHz), where the polyBLEP is 2.4 dB down at 12-16 kHz, and about 11 dB less aliasing (18 dB below 20 kHz). Saw and pulse oscillators cost about 10% more at C3 and nearly twice as much at C6. Off by default (older patches render as they did) |
| `note_priority` | Mono and legato: which held key sounds. `last` (default, the newest), `low` or `high` (the lowest or highest held key, as many analog monosynths; a new key that doesn't win changes nothing, and releasing the sounding key moves to the next by the same rule) |
| `retrigger_from_zero` | Mono and legato: a new note restarts the envelopes from zero rather than from where they are (Helm's and many monosynths' way; legato notes that overlap still don't restart) |
| `nyquist_clamp` | Hold every oscillator's pitch just under Nyquist (0.49 of the sample rate) instead of letting a big pitch sweep or FM shift fold back down as aliasing. Off by default (older patches render as they did) |
| `seed` | Seeds noise, unison phases, the random source, random LFOs and the voice slots' slop |
| `voice_pan` | `[p1, p2 ...]`: each voice slot's pan (−1..1). New voices take the slots in turn (round robin), as a polysynth's voice cards do; mono and legato patches play slot 1 |
| `slop` | `{pitch_cents, cutoff_octaves, env_time, level_db}`: each voice slot gets its own fixed offsets within ± these, from `seed`: pitch, cutoff, every envelope's times (× 1 ± `env_time`, at most 0.9) and level. The slots are `voice_pan`'s (up to 32), or 8. A vintage polysynth's voices each sound a little different; a run of notes moves through them |

The same notes, controller changes and seed always give the same samples, in GDScript, natively and live.

## Live and baked

`AKSynthStream` (native) is the engine running in the audio thread. Calls take effect at the next mix block, or exactly `delay_s` later, so notes can be scheduled to the sample. `AKSynth.render_notes` bakes through the native engine when it's installed and through `AKSynthCore` (the same steps in GDScript, about 100× slower) when not; tests hold all three to the same samples.

Latency for keyboard play is Godot's mix buffer (about 15–30 ms by default).

## Effects

`effects`: a chain run on the patch's output, in order. Each is a spec dictionary, the same in a patch, a recipe's `fx` and (as the effect's properties) a Godot bus effect, so an effect sounds the same wherever it runs:

| Type | Keys (defaults) | Bus effect |
| --- | --- | --- |
| `chorus` | `rate_hz` 0.8, `depth_ms` 3, `delay_ms` 12, `voices` 2 (1–4), `mix` 0.5, `spread` 1 (left/right LFO offset, quarter cycles), `feedback` 0 | `AKChorus` |
| `flanger` | `rate_hz` 0.25, `depth_ms` 2, `delay_ms` 1, `voices` 1 (1–4), `feedback` 0.6, `mix` 0.5, `spread` 1 | `AKFlanger` |
| `phaser` | `rate_hz` 0.4, `stages` 4 (1–12), `center_hz` 800, `range_octaves` 2, `depth` 1, `feedback` 0.4, `mix` 0.5, `spread` 1 | `AKPhaser` |
| `eq` | `low_db` 0 at `low_hz` 120 (shelf), `mid_db` 0 at `mid_hz` 1000 with `mid_q` 0.7 (peak), `high_db` 0 at `high_hz` 6000 (shelf) | `AKEQ3` |
| `compressor` | `threshold_db` −18, `ratio` 4, `attack_s` 0.01, `release_s` 0.12, `knee_db` 6, `makeup_db` 0 (peak detector, stereo linked) | `AKCompressor` |
| `saturate` | `drive_db` 12, `tone_hz` 6000 (a low-pass after it), `asymmetry` 0 (even harmonics), `mix` 1, `output_db` 0 | `AKSaturate` |
| `pitch` | `semitones` −12 (−36–36), `window_ms` 60 (5–200; longer is smoother, shorter crisper), `mix` 0.5: a pitch-shifted copy blended in (an octave-down double, a shimmer) | — |
| `ring` | `freq_hz` 220 (0.1–8000), `rate_hz` 0 and `depth` 0 (octaves the carrier sweeps), `mix` 1: ring modulation, metallic sidebands | — |
| `growl` | `rate_hz` 45, `depth` 0.6, `jitter` 0.5 (how uneven each pulse is), `mix` 1: rough loudness pulses, a rasp | — |
| `crush` | `bits` 8 (1–24), `hold` 1 (samples held, 1–64), `mix` 1 | — |
| `delay` | `time_ms` 250 (1–2000; or `time_sync`, a note length at the tempo, as `"1/8."`), `feedback` 0.35, `damp_hz` 4000 (repeats get darker), `mix` 0.3 (added to the dry), `mode` `stereo` (each side repeats itself), `cross` (the repeats change sides) or `pingpong` (both sides in on the left, then bouncing right and left), `spread_ms` 0 (−100–100: the right side's repeats later by that much, the left's when negative) | — |
| `reverb` | `room` 0.6, `damp` 0.5 (up to 2.5: 1 is Freeverb's most damping, 2.5 takes the tail's highs off entirely), `width` 1, `mix` 0.25 (added to the dry), `predelay_ms` 0, `low_cut_hz` 0, `high_cut_hz` 0 (one-pole filters on the reverb's input; 0 leaves each off): Freeverb's tunings | — |
| `filter` | `mode` `lowpass` or `highpass`, `cutoff_hz` 1000, `q` 0.707, `slope_db` 12 (6: one pole; 12, 24: the state-variable filter): a filter after the voices, all wet (a synth's master high-pass) | — |
| `limiter` | `ceiling_db` −1 (−60..0; the bus effect's knob −12..0), `release_s` 0.08 (0.001..10; the knob 0.005..1): a peak limiter, as `AKDynamics.limit`: instant attack, exponential release, both channels linked, no lookahead or latency. Nothing leaves above the ceiling; a signal that stays under it passes unchanged. Put it last to give a patch a guaranteed ceiling (a resonant filter's onset spikes) | `AKLimiter` |
| `freqshift` | `shift_hz` 100 (−20000..20000; the bus knob ±2000), `stereo` 0 (0..1: the right channel shifts by `shift_hz` × (1 − 2 `stereo`), so 1 shifts it the other way), `echo_ms` 0 (0..1000: the feedback's delay; 0, one sample), `feedback` 0, `mix` 1: a single-sideband frequency shifter. Every partial moves by the same number of Hz (not the same ratio, so harmonic sounds turn inharmonic: bells, metallic voices, detuned beating at a few Hz, barber-pole sweeps with feedback). A Hilbert pair of allpass chains (Olli Niemitalo's published 90° design) splits the signal; the unwanted sideband stays 35–55 dB down from 30 Hz to 20 kHz. Feedback goes back through the echo, so each repeat is shifted again | `AKFreqShift` |
| `rotary` | `speed` 0 (0 slow, chorale .. 1 fast, tremolo; or `"slow"`, `"fast"`), `horn_hz` 6.7 and `drum_hz` 5.7 (the fast rates; slow is 0.12 of them), `accel_s` 0.5 (the horn's time constant when the speed changes; the heavier drum takes five times as long), `drive` 0 (0..1, a tube stage before the cabinet: unity for quiet signals, rounding loud ones), `spread` 1 (the two mics: 0 together, mono .. 1 half a turn apart), `crossover_hz` 800, `doppler` 1 and `tremolo` 1 (0..2, how much pitch and level swing), `mix` 1: a two-way rotary speaker (Leslie). The crossover splits the mono sum; the horn and the drum turn at their own rates, each heard by two mics through a delay that follows the rotor's distance (Doppler) and a gain that follows where it points (the horn's beam more than the drum's). A speed change eases in, so a speed edit (or an `fxN.speed` row) ramps the rotors as a real cabinet does. About 0.3% of a core (0.45% with drive) | `AKRotary` |
| `stutter` | `rate_hz` 8 (1..100: repeats a second; a slice is 1 / rate_hz long), `resample_hz` 1 (0.05..100: how often a new slice is taken), `softness` 0.2 (0 hard edges, a click per repeat .. 1 each repeat a raised-cosine swell), `pitch` 0 (−24..24 semitones: the repeats read faster or slower, looping inside the slice), `mix` 1; or `rate_sync`, `resample_sync` (note lengths at the tempo, as `"1/16"`, in place of the Hz): Helm's stutter, an original take. The input always records; once a slice's worth has come in, the last 1 / rate_hz of it plays over and over, and when 1 / resample_hz has passed a repeat's end takes the newest slice (so resampling never cuts a repeat short). Until the first slice the input passes. Glitch, beat repeats, frozen game SFX; with `fx1.mix` on a macro or the mod wheel, a stutter switch. Two 1 s stereo buffers (768 KB); about 0.1% of a core | `AKStutter` |
| `conditioner` | `bass_db` 0 and `treble_db` 0 (±24: shelves at 200 Hz and 4 kHz), `width` 1 (0 mono .. 2: the side's gain), `balance` 0 (−1..1), `threshold_db` 0 (−48..0), `attack_ms` 5, `release_ms` 120, `output_db` 0: a mastering strip, Surge's conditioner as an original design. The limiter holds the peak (falling at the release) and eases its gain at the attack, with a 6 dB soft knee, so a steady tone sits at the threshold. All wet | `AKConditioner` |
| `geq` | `band1_db` .. `band11_db` 0 (±12 dB peaks at 30, 60, 120, 250, 500, 1k, 2k, 4k, 8k, 12k, 16k Hz, Q 1.41), `output_db` 0: a graphic EQ. Bands at 0 dB are skipped (a flat EQ passes its input untouched and costs nothing); bands above 0.45 of the mix rate too | `AKGraphicEQ` |
| `resonator` | `freq1_hz` 300, `freq2_hz` 1200, `freq3_hz` 3500, `q1`..`q3` 8 (0.5..100), `gain1_db`..`gain3_db` 0, `series` 0 (or `mode = "series"`: one band into the next, their gains multiplied), `output_db` 0, `mix` 1: three resonant band-passes (0 dB at their peaks) summed: formant-like bodies, tuned rings on noise | `AKResonator` |
| `exciter` | `freq_hz` 3000 (500..16000), `drive` 0.5, `mix` 0.5 (added to the dry): the highs above `freq_hz` (a 12 dB/octave high-pass) through a soft saturator of gain 1 + 24 drive (unity for quiet highs), high-passed again and added: presence on quiet material, new harmonics on loud | `AKExciter` |
| `waveshaper` | `curve` `soft` (tanh), `hard` (clip at ±1), `fold` (a triangle fold), `sine`, `asym` (even harmonics: falls to −0.6 below), `digital` (eighths); `drive_db` 6, `bias` 0 (±1, moves the curve's middle; its offset is taken off so silence stays silent), `pre_hp_hz` 0 and `post_lp_hz` 0 (one-pole filters around the curve; 0 off), `output_db` 0, `mix` 1 | `AKWaveshaper` |
| `midside` | `mid_db` 0, `side_db` 0 (−48..24), `side_hp_hz` 0 (a one-pole high-pass on the side: mono lows; 0 off), `mid_pan` 0 (−1..1, moves the middle): mid/side gains. All wet | `AKMidSide` |
| `ensemble` | `slow_hz` 0.6 and `slow_depth` 0.5, `fast_hz` 6 and `fast_depth` 0.2 (the two sweeps), `center_ms` 10 (2..30), `tone_hz` 9000 (the bucket-brigade band limit), `width` 1, `mix` 0.5: a string-ensemble chorus as the BBD ones (Solina, Surge's ensemble; an original design). The mono sum, low-passed twice, goes into one line read by three taps a third of a cycle apart on both sweeps (so their mean delay holds still and the pitch doesn't drift), left, middle and right by `width`. About 0.4% of a core | `AKEnsemble` |
| `combulator` | `tune_hz` 220 (20..4000), `offset2` 7 and `offset3` 12 (semitones above it for combs 2 and 3), `resonance` 0.9 (−0.995..0.995: the feedback; negative rings at odd harmonics an octave down), `tone_hz` 6000 (a low-pass in each loop: highs die first), `noise` 0 (0..1: the input swapped for white noise following its envelope, so anything rings the combs at their pitch), `gain1_db` .. `gain3_db` 0, `width` 0.7 (comb 1 in the middle, 2 left, 3 right), `mix` 1: three tuned combs on the mono sum, each normalised for broadband input (× √(1 − resonance²)). Combs below 20 Hz are held at 20 | `AKCombulator` |
| `tape` | `drive_db` 6 (−12..36), `hyst` 0.3 (0..1: the saturation remembers which way the signal moves, so rising and falling halves trace different curves, a hysteresis loop, more as it saturates), `wow` 0.2 (0.7 Hz) and `flutter` 0.2 (6.1 and 13.3 Hz) (pitch wander from a swinging 3 ms delay; with both 0 the delay is skipped, so no latency), `bump_hz` 80 and `bump_db` 3 (the head bump, a peak; 0 off), `hf_hz` 12000 (the high-frequency loss, 12 dB/octave), `output_db` 0, `mix` 1. Quiet signals pass at unity; loud ones compress. About 0.7% of a core | `AKTape` |
| `treemonster` | `threshold_db` −40 (the tracker ignores what stays below it), `glide_ms` 20 (how fast the sine follows a new pitch), `pitch` 0 (−48..48 semitones from the tracked pitch), `track_lp_hz` 1200 and `track_hp_hz` 40 (the tracker's band), `width` 0 (0..1: the right channel's sine up to a quarter cycle ahead), `mix` 1: pitch-tracking ring modulation (Surge's treemonster; an original design). Positive-going zero crossings of the band-limited mono sum, timed to the fraction of a sample, give the pitch (20 Hz .. 5 kHz); a sine there times the input: a tone at pitch 0 becomes its octave (and DC), at 12 its fundamental and its third harmonic. Silent until a first pitch is found | `AKTreemonster` |
| `spring` | `decay_s` 2 (0.2..10: a 60 dB fall at low frequencies), `chirp` 0.6 (0..0.85: the dispersion; 0 plain echoes), `length_ms` 35 (10..80: the spring's line; the right spring is 1.13 times longer), `tone_hz` 4500 (a low-pass in the loop; above about 4.5 kHz the allpasses mirror, so higher settings brighten with a metallic edge), `width` 1, `mix` 0.3 (dry kept, as `reverb`): a spring reverb. Each spring is a feedback loop of a line, the low-pass and 40 stretched first-order allpasses (K = sr / 9000 samples each), the dispersive structure of the published spring models: low frequencies lag the highs by about 12 ms per pass at the default, so every echo is the falling "drip". 2 × 40 allpasses a sample: about 0.9% of a core, the heaviest of the group (Freeverb is about 0.2%) | `AKSpringReverb` |
| `bonsai` | `bass_hz` 120 (40..400), `boost_db` 6 (0..18), `harmonics` 0.3 (0..1), `drive_db` 3 (−12..24), `tone_hz` 12000, `output_db` 0, `mix` 1: bass enhancement and tape-style saturation (Surge's bonsai; an original design). A two-pole split at `bass_hz` (the bands sum back to the input), the low band lifted by `boost_db` and its harmonics (a tanh of it, high-passed at twice `bass_hz`) added so small speakers hear the bass, then a tanh saturator (unity for quiet signals) and a one-pole low-pass. With nothing on it passes the input | `AKBonsai` |
| `chow` | `threshold_db` −12 (−48..0), `ratio` 10 (1..100), `flip` 0 (0 crushes the positive side, 1 the negative), `drive_db` 12 (0..48, taken back off after, so `ratio` 1 is clean), `tone_hz` 20000 (a one-pole low-pass), `output_db` 0, `mix` 1: a heavy one-sided distortion (after Surge's chow; an original design): past the threshold one side is cut by the ratio, the other passes, so the even harmonics are strong and the wave lopsided; a 10 Hz DC blocker follows | `AKChow` |
| `neuron` | `size_ms` 40 (2..250), `regen` 0.6 (0..1.2: above 1 it keeps going on its own), `drive` 0.3 (0..1), `wobble` 0.2 and `wobble_hz` 0.3 (the lines' lengths swing up to 10%), `tone_hz` 6000, `width` 1, `mix` 0.5: an original feedback network (Surge's neuron is a different design): four lines (`size_ms` × 1, 0.811, 0.677, 0.543) mixed through a 4 × 4 Hadamard matrix back into four tanh "neurons" (gain 1 + 7 `drive`, bounded, so a regen above 1 sings, howls or churns without blowing up), each low-passed into its line. Metallic rooms, self-playing drones, feedback squalls. Four 0.3 s lines (450 KB); about 0.9% of a core | `AKNeuron` |

Every effect with a `mix` also takes `dry` and `wet`, linear gains that replace what `mix` gives (a crossfade, 1 − mix and mix; for `delay`, `reverb` and `spring` the dry kept at 1 and the wet at mix). Either may pass 1: a reverb louder than its dry, as Surge's. Chorus, flanger and phaser feedback is held within ±0.95.

Patch effects run continuously: a held note's chorus keeps moving, and live they keep running between notes. An edit that changes an effect's settings keeps its running state (a reverb or delay tail rings on, filters and gains carry on, a rotary's rotors keep turning and ease to a new speed, no click); only an effect that is added, removed, changes type or needs a different buffer size (a chorus's delay range, a delay's spread, a reverb's predelay, a pitch window, a shifter's echo) starts afresh. A held note follows an edit at once, including one that turns operators on (an `fm` list, a `ratio`, a `level_env`). In a recipe, the buffer is lengthened for a chorus, flanger, phaser, pitch, delay or reverb tail. `pitch`, `ring`, `growl`, `crush`, `delay` and `reverb` (the character effects speech voices use, `docs/speech.md`) and `filter` have no bus effect; for reverb, delay or a filter on a bus, Godot's own are there.

The bus effects appear in Godot's Audio panel under Add Effect when the native core is installed (they are native only: GDScript can't process Godot's bus buffers). `effect.get_spec()` gives the matching spec dictionary, and `effect.process_offline(l, r, sample_rate)` runs the bus effect's own code over arrays. The bus runs at the project's mix rate (48 kHz in this project); at another rate the effect sounds the same but the samples differ.

## Voices as patches

`AKPatchLib.from_voice(voice, params)` rebuilds `tone`, `wavetable` and `fm` as patches: the same sound, polyphonic and playable live. `AKPatchLib.note_of(voice, params)` gives the note to play. Measured against the voices, plain tones match to float rounding; vibrato, the wavetable filter envelope and FM come within 25–40 dB SNR (the control rate, and float32 rounding inside the voices); `tone`'s glide curves in semitones rather than in Hz (timed to agree halfway); `wavetable` unison phases differ. The voices themselves are unchanged, so existing recipes and bakes don't move.

## Presets

In `addons/audio_kit/patches/` (written by `addons/audio_kit/tools/make_patches.gd` from `AKPatchLib.preset`): `tone_beep`, `wavetable_bass`, `wavetable_pad` (spread, chorus), `fm_epiano` (chorus), `fm_bell` (from the voices); `saw_lead` (ladder, chorus), `sub_bass`, `brass` (ladder, EQ), `pluck` (ladder), `strings` (spread, chorus, EQ), `organ` (fast chorus, light drive), `wobble_bass` (ladder, saturation); and, showing hard sync, wavetables, ring modulation and the ladder, `sync_lead` (hard sync swept by an envelope and the mod wheel), `vowel_pad` (the vowel wavetable swept by an LFO), `ring_bell` (ring modulation), `pwm_strings` (the pwm wavetable), `acid_bass` (a resonant, driven ladder); and `speech_blip`, `speech_critter`, `speech_hollow` and `speech_drone`, the patches of the pseudo-speech voices (`docs/speech.md`). A single note of each peaks around −6 dBFS, leaving room for chords (`addons/audio_kit/tools/measure_levels.gd` measures the trims). All are original.

**GAK_ presets.** Richer versions of the originals, using what the engine has gained since they were made (stacks, filter 2, stages envelopes, FM operators, tempo sync, macros, slop, more effects), added beside them so nothing that uses an original changes. Each is named after its original with a `GAK_` prefix and sounds right with its macros at 0; the macros add range.

| Preset | What's added | Macro 1 | Macro 2 |
| --- | --- | --- | --- |
| `GAK_wavetable_bass` | A stacked morph wave, a clean sub around the filter, a digital edge an octave up, compressor | Growl | More pluck |
| `GAK_sub_bass` | Harmonics small speakers can play, a pitch thump, a level by key, saturation | Grit | – |
| `GAK_wobble_bass` | An eighth-note wobble at the tempo, a moving vowel bell, a clean sub; the mod wheel deepens it | Faster wobble | – |
| `GAK_acid_bass` | An 18 dB ladder, accents from velocity, legato slides, distortion, a dotted echo | Saw to square | Longer decay |
| `GAK_tone_beep` | Two pulses with PWM, a chirp at each note, delayed vibrato, bit grit, a ping-pong echo | Deeper PWM | Bigger chirp |
| `GAK_saw_lead` | A stacked saw, a detuned saw and a sub square, a driven ladder, vibrato on the mod wheel, echo and room | Brighter | Second saw up a fifth |
| `GAK_sync_lead` | Band-limited sync swept by a stages envelope and a slow LFO, a saw body beneath, high-pass, drive, echo | More sync | More body |
| `GAK_brass` | A section: stacked saw and pulse, a stages filter swell with blat (slower when soft), a scoop, voices placed across the field with slop, a hall | Brighter | Slower swells |
| `GAK_pluck` | A pick transient, a comb tuned to the note ringing like a string, velocity-deepened snap, echo and room | More ring | Brighter |
| `GAK_strings` | A stacked, unison ensemble with an octave above, high-pass and 24 dB low-pass, per-voice slop and placement, a slow drift, a hall | More octave | Brighter |
| `GAK_pwm_strings` | Juno style: a pulse swept by two free LFOs, a square sub, high-pass and low-pass, both chorus modes | Brighter | Faster PWM |
| `GAK_wavetable_pad` | A stacked morph wave and a bright table, a breath of noise, a slow stages filter swell, three free drifting LFOs, a dotted echo and a long hall | Open filter | More shimmer |
| `GAK_vowel_pad` | A choir: two vowel layers drifting at their own pace, slop, a presence lift, slow vibrato, a hall; the mod wheel moves the vowels | Shift vowel | Brighter |
| `GAK_organ` | Seven drawbars, a fading third-harmonic percussion, a key click, a rotary speaker from a free LFO, tube drive | Upper drawbars | Rotor slow to fast |
| `GAK_fm_epiano` | Two FM pairs (body and tine), the tine thinning up the keyboard, velocity bite, chorus and room | Stereo tremolo | Bark |
| `GAK_fm_bell` | Two inharmonic FM pairs beating against each other, a hum below, stereo, a dotted echo and a hall | More metal | More hum |
| `GAK_ring_bell` | A metallophone: two ring-modulated partials, a beating pair (ombak), a mallet strike, a hall | High partial | Different metal |

The richer presets cost more to play: about 1% of a core per bass or lead note against 0.2–0.8% for the originals, and 5–10% for a four-note pad or string chord with its tails against 2–4%. For many simultaneous game sounds, the originals stay the lighter choice.

`addons/audio_kit/tools/preset_ab.gd` renders each beside its original (loudness-matched) and prints peak, loudness and CPU.

## Categories

`category` (bass, lead, pad, keys, pluck, bell, strings, brass, organ, woodwind, arp, perc, fx, voice, other, or anything) groups patches in the Sound Lab's library browser. It doesn't change the sound or the bake key. Patches saved from the Sound Lab or Flavor also carry library metadata in the resource's metadata (`ak_library`: the tool that saved it, the author from the editor setting `audio_kit/library/author`, and the patch it was made from); it doesn't change the sound either.

## Scope tap

`AKSynthStream.get_recent(frames)` returns the last frames it played (up to 8192, mono, oldest first), for scopes and meters; `render_offline` fills it too.
