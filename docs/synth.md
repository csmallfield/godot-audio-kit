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

Up to four, in `oscillators`:

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

Oscillators are computed last to first, so an oscillator modulated by a later one hears it this sample; one modulated by itself or by an earlier one hears the previous sample (feedback). The classic two-operator FM pair is `[{shape = "sine", fm_from = 2, fm_index = 2.0}, {shape = "sine", level = 0.0, semitones = 12.0}]`.

`unison` (1–7) stacks every oscillator, spread evenly across `detune_cents`, with seeded random start phases; noise isn't stacked. `unison_level` (0–1, default 1) is the stacked voices' level against the middle one (or the middle two, for an even count): 1 keeps them equal, lower gives a solid centre with a quieter shimmer around it. The stack is scaled to keep its power, so turning it down doesn't change the loudness much. `spread` (0–1) pans the stacked voices across the stereo field, equal power (0 keeps the patch mono, exactly as before). A patch with `spread` or any oscillator `pan` runs its filter on left and right separately.

Hard sync isn't band-limited: the restart is a hard edge, so very bright sync sweeps alias a little at high notes.

### Wavetables

A `table` oscillator reads a wavetable: a few frames of one cycle, swept by `position` (modulate `oscN.position` with an LFO or envelope). Built in: `basic` (sine, triangle, saw, square), `pwm` (a pulse narrowing from square), `vowel` (a, e, i, o, u formants on a saw), `organ` (drawbar settings), `bright` (a saw tilting brighter), `digital` (seeded metallic harmonic sets). Your own: `{frames = [{harmonics = [1.0, 0.5, 0.33 ...], phases = [...]}, {samples = [one cycle of any length]}]}` inline, or a path to a JSON file holding that. Each frame is stored at 19 band limits (a half octave apart, up to 512 harmonics), and a note reads the richest one whose harmonics all sit below Nyquist, so tables don't alias. Tables are built once per content (`AKWavetables.build`) and cached.

## Filter

`filter = {type, cutoff_hz, q, slope_db}`: `off`, `lowpass`, `highpass`, `bandpass` or `notch`; a state-variable filter, 12 dB per octave, or 24 with `slope_db = 24`.

`filter = {type = "ladder", cutoff_hz, resonance, drive}`: a four-pole (24 dB) ladder low-pass, solved without delay in its feedback. `resonance` 0–1 (near 1 it rings at the cutoff; up to 1.2 it oscillates on its own); `drive` (default 1) pushes it into soft saturation, which also tames the resonance on loud input. Some of the bass a resonant ladder loses is made up. The matrix's `q` destination scales the resonance.

## Envelopes

`amp_env`, `env2`, `env3`, each `{attack_s, decay_s, sustain, release_s, curve}`. Attack rises linearly (0 = start at full level). Decay is linear, or with `curve = "exp"` a time constant toward `sustain`. Release is a time constant from wherever the level is when the note ends. `amp_env` sets the level (and is the matrix source `env1`); `env2` and `env3` only act through the matrix.

## LFOs

`lfo1`, `lfo2`, each `{shape, rate_hz, delay_s}`: `sine`, `triangle`, `saw`, `square` or `random` (a new random value each cycle). They restart with every note; `delay_s` fades them in (delayed vibrato).

## Modulation matrix

`mods`, up to 16 rows of `{source, dest, amount}`. Each row adds `amount × source` to the destination.

| Source | Range |
| --- | --- |
| `env1` (amp), `env2`, `env3` | 0..1 |
| `lfo1`, `lfo2` | -1..1 |
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
| `gain_db`, `pan` | Output level and balance |
| `seed` | Seeds noise, unison phases, the random source and random LFOs |

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
| `delay` | `time_ms` 250, `feedback` 0.35, `damp_hz` 4000 (repeats get darker), `mix` 0.3 (added to the dry) | — |
| `reverb` | `room` 0.6, `damp` 0.5, `width` 1, `mix` 0.25 (added to the dry): Freeverb's tunings | — |

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
