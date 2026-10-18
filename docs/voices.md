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

## `pluck` (v1)

A Karplus-Strong plucked string: letter plucks, harp-like runs, muted pings.

| Parameter | Default | Range | What it does |
| --- | --- | --- | --- |
| `freq_hz` | 440.0 | 30.0 – 4000.0 | Pitch |
| `decay_s` | 0.6 | 0.02 – 8.0 | Time to fall to 1/e |
| `brightness` | 0.5 | 0.0 – 1.0 | 0 dark and soft, 1 bright and ringing |
| `tone_hz` | 9000.0 | 200.0 – 20000.0 | Low-pass after the string |
| `length_s` | 0.0 | 0.0 – 10.0 | Total length; 0 = four decay times |

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

## `whoosh` (v1)

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
