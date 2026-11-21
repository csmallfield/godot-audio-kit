# synth1_ref: measuring Synth1's curves

Measures what each Synth1 panel value does, so the Synth1 → AKPatch converter (`tools/patch_convert/synth1.gd`, to come) can use tables instead of guesses. The manual gives no units, and Synth1 is closed source, so every curve here comes from rendering Synth1 itself. Nothing of Synth1 is copied or shipped: these scripts load the user's own copy of the plugin, and `data/` holds only measurements.

Plan and decisions: `docs/plans/synth-expansion-phase0-synth1.md`.

## Setup

- Synth1 1.13 (Daichi Laboratory, freeware VST2): `D:\tools\synth1\Synth1 VST64.dll`, or set `SYNTH1_DLL`.
- DawDreamer 0.9 in a venv: `D:\tools\dawdreamer\venv`.

Run each script with that venv's Python, from anywhere:

```
D:\tools\dawdreamer\venv\Scripts\python.exe -I tools\synth1_ref\measure_env.py
```

## How values reach Synth1

Synth1 saves its state as a VST chunk in which each parameter is the integer a `.sy1` file stores, at byte `732 + 8 × index`, followed by a 1. `synth1.py` writes integers there and loads the chunk, so Synth1 interprets a preset's values itself. The VST automation scale (0–1) doesn't line up with the stored integers for many parameters (osc2 pitch is stored 0–127 but labelled −60..+60; arp beat is stored 0–64 but has 19 automation steps), so it isn't used.

Parameters a `.sy1` leaves out (older versions write fewer) take Synth1's initial values, which are the neutral ones for the later features (sub gain 0, unison off). `neutral()` is the plain test patch every measurement starts from: osc1 alone, filter open, a gate-shaped amp envelope, everything else off. Note that `key_shift` is stored signed (0 = none).

## Scripts and data

| Script | Writes | Measures |
| --- | --- | --- |
| `measure_env.py` | `data/amp_env.json` | Amp envelope per value: attack (times to 10/50/90/99 % and its shape), decay and release (times to −6/−20/−40/−60 dB), sustain level (dB) |
| `measure_filter.py` | `data/filter.json` | Each type's response, cutoff per value (LP12 and LP24, −3 dB), resonance peak, key tracking, envelope amount |
| `measure_lfo.py` | `data/lfo.json` | What each destination moves, each wave's shape, rate per speed value, depth per depth value |
| `measure_osc.py` | `data/osc.json` | Oscillator shapes, osc2 pitch (a semitone table) and fine, tune, untracked osc2, mix law, FM depth, pulse width, osc1 detune, sub, unison detune and level, gain, velocity, portamento |
| `measure_fx.py` | `data/fx_*.json` | Display text per value (`fx_texts`), tempo delay (`fx_delay`), chorus/flanger (`fx_chorus`), equalizer (`fx_eq`), the ten effect types (`fx_effects`) and their controls (`fx_controls`), mod envelope (`fx_modenv`; its amount on FM and pulse width in `fx_modenv_amount`). Runs at 120 bpm (DawDreamer's `set_bpm`) |
| `measure_sync.py` | `data/sync.json` | At 120 bpm, one note at a time: the synced LFO's cycle per speed value, the arpeggiator's step per beat value, its note order per type value and its octave range |

`docs/plans/synth-expansion-phase0-synth1.md` ("Measured curves") summarises what the data says.
