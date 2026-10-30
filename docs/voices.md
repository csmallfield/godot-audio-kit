# Voices

Generated from each voice's `schema()` by `addons/audio_kit/tools/voice_docs.gd`. Do not edit by hand.

## `boing` (v1)

A sine whose pitch drops fast, with optional spring wobble, sub layer and click: hits, landings, thumps, boings.

| Parameter | Default | Range | What it does |
| --- | --- | --- | --- |
| `start_hz` | 180.0 | 20.0 – 8000.0 | Pitch at the hit |
| `end_hz` | 45.0 | 20.0 – 4000.0 | Pitch it falls to |
| `drop_s` | 0.11 | 0.001 – 2.0 | Pitch drop time constant |
| `decay_s` | 0.28 | 0.005 – 4.0 | Level decay time constant |
| `wobble_hz` | 0.0 | 0.0 – 40.0 | Spring wobble rate; 0 = none |
| `wobble_semitones` | 2.0 | 0.0 – 12.0 | Wobble depth, fading with the level |
| `sub` | 0.0 | 0.0 – 1.0 | Sine an octave under the end pitch |
| `click` | 0.5 | 0.0 – 1.0 | Noise transient at the start |
| `click_hz` | 6000.0 | 200.0 – 20000.0 | Transient brightness |
| `length_s` | 0.0 | 0.0 – 8.0 | Total length; 0 = five decay times |

## `clap` (v1)

A hand clap: a few noise bursts a few milliseconds apart, then a short band-passed tail.

| Parameter | Default | Range | What it does |
| --- | --- | --- | --- |
| `bursts` | 3 | 1 – 6 | Bursts before the tail |
| `spacing_s` | 0.011 | 0.002 – 0.04 | Gap between bursts |
| `burst_decay_s` | 0.005 | 0.001 – 0.03 | Each burst's decay |
| `tail_decay_s` | 0.12 | 0.01 – 1.0 | Tail decay |
| `color_hz` | 1200.0 | 300.0 – 8000.0 | Band centre |
| `q` | 1.2 | 0.3 – 8.0 | Band resonance |

## `click` (v1)

A short noise burst through a resonant filter, with an optional low body: ticks, clacks, stamps, keys.

| Parameter | Default | Range | What it does |
| --- | --- | --- | --- |
| `freq_hz` | 9000.0 | 100.0 – 20000.0 | Filter centre (band) or cutoff (low/high) |
| `q` | 0.7 | 0.3 – 30.0 | Resonance: high values ring like wood or metal |
| `mode` | low |  | Filter mode: low, band or high |
| `attack_s` | 0.0003 | 0.0001 – 0.02 | Rise time: the default snaps; a few ms softens it to a puff |
| `decay_s` | 0.008 | 0.0005 – 1.0 | Decay time constant |
| `body_hz` | 0.0 | 0.0 – 2000.0 | Low thump under the click; 0 = none |
| `body` | 0.5 | 0.0 – 1.0 | Thump level |
| `length_s` | 0.0 | 0.0 – 2.0 | Total length; 0 = six decay times, at least 20 ms |

## `fm` (v1)

Two- or three-operator FM (phase modulation) with a decaying index: bells, electric piano, metallic plucks, bright basses, chimes.

| Parameter | Default | Range | What it does |
| --- | --- | --- | --- |
| `freq_hz` | 220.0 | 20.0 – 8000.0 | Carrier pitch |
| `ratio` | 2.0 | 0.125 – 16.0 | Modulator frequency as a multiple of the carrier (integers sound harmonic) |
| `index` | 3.0 | 0.0 – 20.0 | Modulation depth at the attack: brightness |
| `index_end` | 0.5 | 0.0 – 20.0 | Depth it decays to |
| `index_decay_s` | 0.2 | 0.001 – 8.0 | How fast the brightness falls |
| `ratio2` | 0.0 | 0.0 – 16.0 | A second modulator driving the first; 0 = off |
| `index2` | 1.0 | 0.0 – 20.0 | Depth of the second modulator |
| `attack_s` | 0.003 | 0.0 – 4.0 | Attack |
| `decay_s` | 0.4 | 0.001 – 8.0 | Decay to sustain |
| `sustain` | 0.0 | 0.0 – 1.0 | Sustain level |
| `release_s` | 0.15 | 0.001 – 4.0 | Release time constant after the gate |
| `gate_s` | 0.3 | 0.0 – 30.0 | How long the note is held |
| `length_s` | 0.0 | 0.0 – 30.0 | Total length; 0 = gate plus five release times |

## `follow` (v1)

An oscillator whose pitch and level follow breakpoint curves: sound that traces a motion (a scope wave, a rising bar, a moving needle).

| Parameter | Default | Range | What it does |
| --- | --- | --- | --- |
| `wave` | sine |  | sine, triangle, saw, square or pulse |
| `length_s` | 1.0 | 0.02 – 60.0 | Total length |
| `pitch` | [[0.0, 440.0], [1.0, 880.0]] |  | [[seconds, Hz], ...] breakpoints, linear between them |
| `level` | [[0.0, 1.0], [1.0, 1.0]] |  | [[seconds, 0..1], ...] breakpoints |
| `glide` | 0.0 | 0.0 – 1.0 | Smooths the pitch curve (0 = exact) |
| `fade_s` | 0.005 | 0.0 – 2.0 | Fade in and out |

## `hat` (v1)

A hi-hat or cymbal: a cluster of square waves and noise through a high band. Short decay is closed, long is open.

| Parameter | Default | Range | What it does |
| --- | --- | --- | --- |
| `decay_s` | 0.05 | 0.005 – 3.0 | Decay: short closed, long open or ride |
| `tone_hz` | 8000.0 | 2000.0 – 16000.0 | Centre of the band |
| `metal` | 0.6 | 0.0 – 1.0 | Metallic squares versus plain noise |
| `tune` | 1.0 | 0.5 – 2.0 | Scales the metal cluster |

## `kick` (v1)

A kick drum: a sine that drops from a punch pitch to its tune, a click, and optional drive.

| Parameter | Default | Range | What it does |
| --- | --- | --- | --- |
| `tune_hz` | 50.0 | 25.0 – 200.0 | Pitch the body settles at |
| `punch` | 3.0 | 0.0 – 10.0 | Start pitch as multiples above the tune |
| `drop_s` | 0.03 | 0.002 – 0.3 | Pitch drop time constant |
| `decay_s` | 0.3 | 0.02 – 2.0 | Body decay time constant |
| `click` | 0.4 | 0.0 – 1.0 | Beater click |
| `drive` | 0.2 | 0.0 – 1.0 | Saturation |

## `mallet` (v2)

Modal synthesis: a few damped partials struck by a soft or hard mallet. Marimba, glockenspiel, vibes, glass, nodes and pings.

| Parameter | Default | Range | What it does |
| --- | --- | --- | --- |
| `freq_hz` | 660.0 | 40.0 – 8000.0 | Pitch of the fundamental |
| `material` | wood |  | Partial ratios: wood, metal, glass or bar |
| `decay_s` | 0.4 | 0.01 – 8.0 | Fundamental's decay time constant |
| `damping` | 0.7 | 0.0 – 2.0 | How much faster high partials die (0 = all equal) |
| `hardness` | 0.4 | 0.0 – 1.0 | Mallet hardness: brighter partials and a strike click |
| `length_s` | 0.0 | 0.0 – 12.0 | Total length; 0 = five decay times |

## `patch` (v103)

Plays one note of an AKPatch (a resource or its path) through the synth engine: any sound the patch engine can make, in a recipe.

| Parameter | Default | Range | What it does |
| --- | --- | --- | --- |
| `patch` |  |  | The AKPatch, or its res:// path |
| `freq_hz` | 261.63 | 8.0 – 12000.0 | Pitch (sets the note; the sequencer retunes it) |
| `velocity` | 1.0 | 0.0 – 1.0 | Note velocity |
| `gate_s` | 0.3 | 0.0 – 30.0 | How long the note is held |
| `length_s` | 0.0 | 0.0 – 30.0 | Total length; 0 = gate plus five amp-release times |
| `controls` | [] |  | Controller moves during the note: [[seconds from its start, "bend" (-1..1) or "mod_wheel" (0..1), value], ...] |

## `pluck` (v1)

A Karplus-Strong plucked string: letter plucks, harp-like runs, muted pings.

| Parameter | Default | Range | What it does |
| --- | --- | --- | --- |
| `freq_hz` | 440.0 | 30.0 – 4000.0 | Pitch |
| `decay_s` | 0.6 | 0.02 – 8.0 | Time to fall to 1/e |
| `brightness` | 0.5 | 0.0 – 1.0 | 0 dark and soft, 1 bright and ringing |
| `tone_hz` | 9000.0 | 200.0 – 20000.0 | Low-pass after the string |
| `length_s` | 0.0 | 0.0 – 10.0 | Total length; 0 = four decay times |

## `ratchet` (v1)

A train of clicks whose rate changes over the sound: ratchets, zips, gear teeth, stepped slides, film rattle.

| Parameter | Default | Range | What it does |
| --- | --- | --- | --- |
| `length_s` | 0.3 | 0.02 – 8.0 | Total length |
| `start_rate_hz` | 30.0 | 1.0 – 400.0 | Clicks per second at the start |
| `end_rate_hz` | 14.0 | 1.0 – 400.0 | Clicks per second at the end |
| `click_hz` | 3000.0 | 100.0 – 18000.0 | Click filter centre |
| `q` | 3.0 | 0.3 – 30.0 | Click resonance |
| `click_decay_s` | 0.004 | 0.0005 – 0.1 | Each click's decay |
| `jitter` | 0.1 | 0.0 – 0.5 | Seeded timing wobble, as a fraction of the gap |
| `accent_every` | 0.0 | 0.0 – 16.0 | Every nth click louder; 0 = even |
| `fade` | 0.3 | 0.0 – 1.0 | Level fall across the sound (0 = none) |

## `reed` (v1)

Saxophone-like lead: formant-filtered saw/pulse, breath noise, attack scoop, delayed vibrato, brightness that follows the envelope.

| Parameter | Default | Range | What it does |
| --- | --- | --- | --- |
| `freq_hz` | 233.08 | 40.0 – 2000.0 | Pitch |
| `brightness` | 0.6 | 0.0 – 1.0 | How open the tone gets at the peak of the envelope (blow harder: brighter) |
| `tone_hz` | 4200.0 | 500.0 – 12000.0 | Low-pass ceiling at full brightness |
| `formant1_hz` | 620.0 | 200.0 – 1500.0 | First resonance (body) |
| `formant2_hz` | 1550.0 | 600.0 – 4000.0 | Second resonance (reediness) |
| `formants` | 0.8 | 0.0 – 2.0 | How strongly the resonances colour the tone |
| `breath` | 0.12 | 0.0 – 1.0 | Breath noise level |
| `growl` | 0.15 | 0.0 – 1.0 | Saturation for an edgier, raspier tone |
| `scoop_semitones` | 0.8 | 0.0 – 4.0 | How far below the note it starts |
| `scoop_s` | 0.05 | 0.001 – 0.5 | How fast it reaches the note |
| `vibrato_hz` | 5.3 | 0.0 – 9.0 | Vibrato rate |
| `vibrato_cents` | 22.0 | 0.0 – 100.0 | Vibrato depth |
| `vibrato_delay_s` | 0.28 | 0.0 – 2.0 | Time before the vibrato fades in |
| `attack_s` | 0.035 | 0.001 – 1.0 | Attack |
| `decay_s` | 0.35 | 0.001 – 4.0 | Decay to sustain |
| `sustain` | 0.78 | 0.0 – 1.0 | Sustain level |
| `release_s` | 0.09 | 0.001 – 2.0 | Release time constant after the gate |
| `gate_s` | 0.5 | 0.0 – 30.0 | How long the note is held |
| `length_s` | 0.0 | 0.0 – 30.0 | Total length; 0 = gate plus five release times |

## `sample` (v1)

Plays an AKSample (a sound file or a recipe) at a pitch: resampled by 2^((note - root) / 12) with 4-point interpolation, one-shot, gated or looped.

| Parameter | Default | Range | What it does |
| --- | --- | --- | --- |
| `sample` |  |  | The AKSample, or its res:// path; empty plays a soft mallet at C4 |
| `freq_hz` | 261.63 | 8.0 – 12000.0 | Pitch to play (the sample's root pitch plays it as made; the sequencer retunes it) |
| `velocity` | 1.0 | 0.0 – 1.0 | Level of the note |
| `gate_s` | 0.3 | 0.0 – 30.0 | How long the note is held (gate and loop modes) |
| `length_s` | 0.0 | 0.0 – 30.0 | Total length; 0 = to the sample's end (one-shot) or the gate plus five release times |

## `snare` (v1)

A snare drum: a short pitched body plus filtered noise for the wires.

| Parameter | Default | Range | What it does |
| --- | --- | --- | --- |
| `tone_hz` | 190.0 | 60.0 – 600.0 | Body pitch |
| `tone` | 0.5 | 0.0 – 1.0 | Body level |
| `tone_decay_s` | 0.07 | 0.005 – 1.0 | Body decay |
| `noise` | 0.8 | 0.0 – 1.0 | Wire (noise) level |
| `noise_hz` | 5000.0 | 500.0 – 16000.0 | Wire brightness |
| `noise_decay_s` | 0.14 | 0.01 – 2.0 | Wire decay |

## `speech` (v3003)

Speaks a line of text as pseudo-speech (gibberish whose rhythm, stress and melody follow the text) through an AKSpeechVoice's patch.

| Parameter | Default | Range | What it does |
| --- | --- | --- | --- |
| `text` | Hey! |  | The line to say |
| `voice` | res://addons/audio_kit/speech/voices/blip.tres |  | The AKSpeechVoice, or its res:// path |

## `static` (v1)

Band-limited hiss with random crackles and optional flicker: TV static, radio noise, vinyl crackle, decoding glitches.

| Parameter | Default | Range | What it does |
| --- | --- | --- | --- |
| `length_s` | 1.0 | 0.02 – 30.0 | Total length |
| `hiss` | 0.4 | 0.0 – 1.0 | Level of the noise floor |
| `color_hz` | 2500.0 | 100.0 – 18000.0 | Centre of the hiss band |
| `q` | 0.6 | 0.2 – 10.0 | Width of the hiss band (higher = narrower) |
| `crackles_per_s` | 40.0 | 0.0 – 2000.0 | Average crackle rate |
| `crackle` | 0.7 | 0.0 – 1.0 | Crackle level |
| `flicker_hz` | 0.0 | 0.0 – 60.0 | Random level steps per second; 0 = steady |
| `flicker_depth` | 0.6 | 0.0 – 1.0 | How deep the flicker dips |
| `fade_s` | 0.01 | 0.0 – 2.0 | Fade in and out |
| `lowpass_hz` | 0.0 | 0.0 – 20000.0 | A steep (24 dB an octave) low-pass over everything, crackles too; 0 = off |

## `tone` (v1)

An oscillator with an ADSR envelope, optional glide and vibrato: beeps, blips, line-up tones, chimes.

| Parameter | Default | Range | What it does |
| --- | --- | --- | --- |
| `wave` | sine |  | sine, triangle, saw, square or pulse |
| `width` | 0.5 | 0.01 – 0.99 | Pulse width (pulse only) |
| `freq_hz` | 880.0 | 20.0 – 20000.0 | Start pitch |
| `end_hz` | 0.0 | 0.0 – 20000.0 | Glide target; 0 = no glide |
| `glide_s` | 0.05 | 0.001 – 4.0 | Glide time constant |
| `vibrato_hz` | 0.0 | 0.0 – 20.0 | Vibrato rate; 0 = none |
| `vibrato_semitones` | 0.3 | 0.0 – 12.0 | Vibrato depth |
| `attack_s` | 0.002 | 0.0 – 4.0 | Attack |
| `decay_s` | 0.05 | 0.001 – 4.0 | Decay to sustain |
| `sustain` | 0.0 | 0.0 – 1.0 | Sustain level |
| `release_s` | 0.05 | 0.001 – 4.0 | Release time constant after the gate |
| `gate_s` | 0.15 | 0.0 – 30.0 | How long the note is held |
| `length_s` | 0.0 | 0.0 – 30.0 | Total length; 0 = gate plus five release times |

## `vowel` (v1)

Sung vowel: a saw and breath through three formant resonators in series (a cascade formant synth); set the formants for ee, ah, oo ...

| Parameter | Default | Range | What it does |
| --- | --- | --- | --- |
| `freq_hz` | 220.0 | 40.0 – 1000.0 | Pitch |
| `f1_hz` | 730.0 | 150.0 – 1200.0 | First formant: low for ee and oo, high for ah |
| `f2_hz` | 1090.0 | 500.0 – 3000.0 | Second formant: high for ee, low for oo |
| `f3_hz` | 2440.0 | 1500.0 – 4000.0 | Third formant |
| `bw1_hz` | 90.0 | 30.0 – 400.0 | First formant's bandwidth (narrower: more resonant) |
| `bw2_hz` | 120.0 | 30.0 – 500.0 | Second formant's bandwidth |
| `bw3_hz` | 170.0 | 30.0 – 600.0 | Third formant's bandwidth |
| `breath` | 0.04 | 0.0 – 1.0 | Breath noise through the formants (whisper at 1) |
| `vibrato_hz` | 5.5 | 0.0 – 9.0 | Vibrato rate |
| `vibrato_cents` | 10.0 | 0.0 – 100.0 | Vibrato depth |
| `attack_s` | 0.02 | 0.001 – 1.0 | Attack |
| `decay_s` | 0.1 | 0.001 – 4.0 | Decay to sustain |
| `sustain` | 0.85 | 0.0 – 1.0 | Sustain level |
| `release_s` | 0.08 | 0.001 – 2.0 | Release time constant after the gate |
| `gate_s` | 0.5 | 0.0 – 30.0 | How long the note is held |
| `length_s` | 0.0 | 0.0 – 30.0 | Total length; 0 = gate plus five release times |

## `wavetable` (v1)

A morphing oscillator (sine, triangle, saw, square) with unison detune, a sub, and a low-pass with its own envelope: basses, pads, leads, stabs, arps.

| Parameter | Default | Range | What it does |
| --- | --- | --- | --- |
| `freq_hz` | 110.0 | 20.0 – 8000.0 | Pitch |
| `position` | 0.66 | 0.0 – 1.0 | Shape: 0 sine, 0.33 triangle, 0.66 saw, 1 square, blended between |
| `unison` | 1 | 1 – 7 | Stacked detuned voices (thicker, costs more) |
| `detune_cents` | 12.0 | 0.0 – 100.0 | Spread of the unison voices |
| `sub` | 0.0 | 0.0 – 1.0 | Sine one octave down |
| `cutoff_hz` | 1800.0 | 40.0 – 18000.0 | Low-pass cutoff after the envelope settles |
| `env_octaves` | 2.0 | 0.0 – 6.0 | How far the envelope opens the filter above the cutoff |
| `filter_decay_s` | 0.18 | 0.001 – 8.0 | How fast the filter closes |
| `q` | 0.9 | 0.3 – 10.0 | Filter resonance |
| `attack_s` | 0.004 | 0.0 – 4.0 | Attack |
| `decay_s` | 0.25 | 0.001 – 8.0 | Decay to sustain |
| `sustain` | 0.6 | 0.0 – 1.0 | Sustain level |
| `release_s` | 0.1 | 0.001 – 4.0 | Release time constant after the gate |
| `gate_s` | 0.25 | 0.0 – 30.0 | How long the note is held |
| `length_s` | 0.0 | 0.0 – 30.0 | Total length; 0 = gate plus five release times |

## `whoosh` (v2)

Noise through a swept filter under a bump envelope: wipes, passes, swishes.

| Parameter | Default | Range | What it does |
| --- | --- | --- | --- |
| `length_s` | 0.55 | 0.05 – 4.0 | Total length |
| `low_hz` | 300.0 | 20.0 – 20000.0 | Cutoff at the start and end of the sweep |
| `high_hz` | 5300.0 | 20.0 – 20000.0 | Cutoff at the top of the sweep |
| `peak` | 0.5 | 0.05 – 0.95 | Where in the sound the sweep and level peak (0..1) |
| `shape` | 1.5 | 0.3 – 4.0 | Envelope power: higher is more pointed |
| `q` | 0.7 | 0.3 – 8.0 | Filter resonance |
| `mode` | low |  | Filter mode: low, band or high |
| `noise` | white |  | Noise colour: white, pink or brown |
| `slope_db` | 24.0 | 12.0 – 24.0 | Filter steepness: 12 or 24 dB per octave |
