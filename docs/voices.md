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

## `click` (v1)

A short noise burst through a resonant filter, with an optional low body: ticks, clacks, stamps, keys.

| Parameter | Default | Range | What it does |
| --- | --- | --- | --- |
| `freq_hz` | 9000.0 | 100.0 – 20000.0 | Filter centre (band) or cutoff (low/high) |
| `q` | 0.7 | 0.3 – 30.0 | Resonance: high values ring like wood or metal |
| `mode` | low |  | Filter mode: low, band or high |
| `decay_s` | 0.008 | 0.0005 – 1.0 | Decay time constant |
| `body_hz` | 0.0 | 0.0 – 2000.0 | Low thump under the click; 0 = none |
| `body` | 0.5 | 0.0 – 1.0 | Thump level |
| `length_s` | 0.0 | 0.0 – 2.0 | Total length; 0 = six decay times, at least 20 ms |

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
