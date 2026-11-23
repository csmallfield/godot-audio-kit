# Flavor tab: plan

The live, commentable version of this plan, with every control's tuning history and measurements, is the doc "Audio Kit: Flavor Tab" (https://claude.ai/artifact/FNwRnMQCohfwEGmnPYncq4; its title still reads "Vibe Tab"). This file is the in-repo summary that work on the Flavor tab follows; if the two disagree, ask.

## Goal and principles

The Synth tab can match or build nearly any sound, and that depth is overwhelming when you just want something beefy, silky or filthy. The Flavor tab is a second way to design a patch: fourteen knobs and five switches named for what you hear.

- **Knobs are named for what you hear.** Each has a word at either end (Lean ↔ Beefy) and does what the word says.
- **One knob moves many settings**, some up and some down, along whatever curves produce the named result.
- **Every control is strong.** Moved alone from rest, any knob or switch changes the sound obviously. The ends are meant to overshoot: full Beefy is too beefy.
- **Knobs overlap.** Two knobs may move the same setting; their offsets add.
- **It makes an ordinary `AKPatch`.** Tone and effects bake into one resource that plays, bakes and opens in the Synth tab like any other.

## Decisions

| Question | Decision |
| --- | --- |
| Name | Flavor (Vibe was the working name) |
| Output | A normal `AKPatch`, effects included, ending in a limiter |
| Relation to the Synth tab | One-way: a Flavor patch opens in the Synth tab; an arbitrary patch cannot be mapped back onto the knobs |
| Starting point | One neutral base sound, approved by ear; no "body" picker |
| Knob ranges | Eight two-way knobs rest in the middle (−1 .. 1); six add-only knobs rest at zero (0 .. 1) |
| Combining | Offsets to the same setting add, with ceilings; controls apply in a fixed order |
| Tuning | Each control tuned alone, by ear, from rendered examples; every end value approved |
| Left out | Wispy ↔ Chonky (overlapped Lean ↔ Beefy and Pluck ↔ Bloom) |
| Clean ↔ Filthy | Add-only: the base has too little dirt to remove for a Clean half |
| Wonky, Slinky | Promoted from switches to knobs: no single amount of drift or glide suits every sound |
| Slinky's mode | `mono`, not `legato`: every note re-strikes, so Pluck, Quack and Farty stay audible |
| Engine | 8 LFOs, 16 oscillators, 32 matrix rows (2ea8452) and a `limiter` effect (eaffdb7) were added for this |
| Loudness | One measured, fixed gain per patch; a window of 3 LU either side of the base; never raised into the limiter |
| Stored settings | Patch metadata (`flavor`) with a fingerprint, saved in the `.tres`; stale once the patch is edited elsewhere |
| Randomise, Mutate | Both in, after the Sound Lab's buttons |
| Layout | One screen: toolbar, a row of two-way knobs, a row of add-only knobs with the switches beside it, scope and keyboard |
| Knob control | Rotary knobs (a new control; the kit's editors use sliders) |
| MIDI | A learn function links knobs to controller knobs, in the editor only; links live in editor settings |

## Controls

All values are in `addons/audio_kit/synth/flavor.gd` (`AKFlavor`), one function per control; `tests/test_flavor.gd` pins the approved end values.

| Knob | Down / at rest | Up |
| --- | --- | --- |
| Lean ↔ Beefy | Sub removed, lows cut 24 dB below about 700 Hz, one voice | Sine and square subs, lows and low-mids lifted, 4:1 compression, saturation |
| Silky ↔ Gritty | Triangle with pure upper-octave sheen, no resonance, almost no saturation | Saw, open resonant filter, noise FM and a hard-synced overtone |
| Woody ↔ Glassy | Near-square, a bright knock, fast damped decay | Near-sine with bell FM at 3.5 times the note, long ringing release |
| Murky ↔ Sparkly | Filter closed three octaves, top cut, dark reverb | Filter open, beating upper octaves, a ting on each note, chorus, octave-up shimmer |
| Pluck ↔ Bloom | Instant attack, hard filter ping, dies within a fifth of a second | Swell over more than a second, filter opens with it, slow release |
| Solo ↔ Crowd | One voice, mono, delayed vibrato | Seven voices 45 cents apart, full width, random pitch per note, chorus |
| Shut ↔ Quack | Resonant filter parked low: a nasal honk | Filter thrown open up to five octaves on every note: an auto-wah |
| Dry ↔ Drenched | No delay or reverb, release cut to a quarter | Long dark delay, full-wet reverb, a second reverb at the top |
| Clean ↔ Filthy | The base's touch of saturation | Saturation, then growl, then crush to 3 bits |
| Still ↔ Swirl | No movement | Phaser, then flanger; an LFO swings each note left and right |
| Note ↔ Chord | One pitch | An octave, a fifth, then a third (major, or minor with the switch) |
| Polite ↔ Farty | Steady and rounded | Flap, rasp, squelch and sag |
| Steady ↔ Wonky | In tune | Slow random pitch drift and off-pitch starts |
| Stiff ↔ Slinky | Polyphonic, no glide | One note at a time, gliding; longer as it rises |

Switches: **Bounce** (arpeggiator: up, two octaves, sixteenths), **Pump** (a 14 dB duck on every beat), **Lo-Fi** (band-limited, crushed, hiss), **Wide** (hard-panned voices, ping-pong delay), **Minor** (Note ↔ Chord's third).

## How controls combine

- **Order.** Fixed, so the result does not depend on which control moved last. Pluck ↔ Bloom and Dry ↔ Drenched apply last because they scale times other controls add to.
- **Ceilings.** Resonance 0.8; `env2` → cutoff 5 octaves; cutoff 60 Hz to 18 kHz; delay feedback 0.85; reverb room 0.98; mixes, sustains and morph position 0 to 1.
- **Voices.** Crowd sets the unison count; full Lean or half Solo force one voice only when Crowd is not up.
- **Matrix rows** with the same source and destination merge, amounts added.
- **LFOs.** `lfo1` Solo, `lfo2` Swirl, `lfo3` Farty, `lfo4` Wonky, `lfo5` Pump.
- **FM.** Glassy uses the main oscillator's single FM slot and Gritty its `fm` list, so both can be up.
- **Chorus.** Sparkly's and Crowd's merge into one, mix capped at 0.7.
- **Chord notes** take the main oscillator's final morph position.
- **Silent oscillators stay** in the patch, so the numbers FM and sync refer to never shift.
- **Chain.** EQ, compressor, saturate, the knobs' effects, delay, reverb, (second reverb), (level gain), limiter at −1 dBFS.

With everything at full the patch has 13 oscillators, 16 matrix rows, 5 LFOs and 15 effects.

## What tuning found about the engine

- **Ladder `drive` and oscillator `feedback` dull the tone**; they do not add grit. Roughness comes from noise FM and a hard-synced oscillator.
- **Square is no brighter than saw** on the morph oscillator, which is quietest around position 0.75 and loudest near square.
- **A narrow `pulse` carries a constant offset.** Through a `growl` it became a sub-bass thump (94% of the energy below 150 Hz). Flavor does not use narrow pulses.
- **Changes below 150 Hz are inaudible on small speakers.** Lean ↔ Beefy works in the 200–700 Hz range for that reason.
- **Stacked resonance spikes.** Four knobs raising resonance and the envelope's throw together gave onset spikes up to 11 dB over full scale; ceilings did not remove them and the compressor is too slow. The limiter holds them.
- **The level gain** is a ratio-1 compressor with `makeup_db`; it matches plain scaling to 85 dB below the signal.

## Built

- `AKFlavor` (`addons/audio_kit/synth/flavor.gd`): `build`, `apply_to`, `settings_of`, `is_stale`, `measure`, `level`, `randomise`, `mutate`. It reproduces the prototype that made every approved example to the sample.
- `AKKnob` (`addons/audio_kit/editor/knob.gd`): the rotary knob.
- `AKFlavorLab` (`addons/audio_kit/editor/flavor_lab.gd`): the Flavor page, added to the Sound Lab after Synth. Toolbar, both knob rows, switches, scope, limiter light, keyboard; Randomise, Mutate, Undo, Reset; Save, reopen with the "edited since" notice, Open in Synth; levelling on Save; MIDI learn with pickup.
- `tests/test_flavor.gd`, `tests/test_flavor_lab.gd`.
- `addons/audio_kit/tools/flavor_listen.gd`: renders every control's steps to WAVs and prints how they measure.
- `docs/flavor.md`.

## To do

1. Use it in the editor with the native core: live play, knob feel, the limiter light, MIDI learn with a real controller. None of that could be tried where this was built.
2. Tune from use: knob drag speed, Randomise and Mutate amounts, the loudness window.
3. Done: a tutorial (docs/tutorials, tutorial 8), with what each knob changes behind the scenes.

## Going back to Flavor after editing in Synth

Documented 2026-11-23; no change made yet.

**What happens.** The Flavor page never adds to edits made elsewhere. It rebuilds the whole patch from the control positions every time (`AKFlavor.apply_to`), so Synth-page edits are not in what it plays.

- **Open in Synth hands over a copy** (`AKFlavorLab.open_in_synth`). Edits on the Synth page change that copy only. Switching back to the Flavor tab, the page is still playing its own patch, without those edits, before any knob is touched.
- **Reopening an edited patch rebuilds it.** `open_flavor` reads the stored control positions and calls `set_settings`, which rebuilds from them. The "edited since" notice shows (the stored fingerprint no longer matches), and the sound is the one from before the Synth edits. Turning a knob rebuilds again from the controls.
- **Save can then overwrite the edits.** `open_flavor` puts the file's name in the name box, and `save_patch` writes `<save_dir>patches/<name>.tres` without asking. Pressing Save after reopening an edited patch replaces the file with the control-built version, and the Synth edits in that file are lost. Nothing warns of this beyond the "edited since" notice.

**Why.** A control only says "set these settings to these values". The page keeps no record of what was changed by hand, so there is nothing for a control's change to be added on top of.

**Until it is addressed.** Finish on the Flavor page before moving to Synth, and save a patch edited in Synth under a different name from its Flavor original.

**Options, undecided.**

1. **Warn before overwriting.** When the open patch is stale, Save asks first or proposes a new name. Small, and worth doing whichever way the rest goes.
2. **Additive control moves.** Each move applies only the difference it causes, on top of whatever the patch holds. Hand edits to settings no control touches would survive. Edits to settings a control does touch would drift or clash, and switches and stepped settings (oscillators or effects that appear, the unison count, poly to mono) cannot be expressed as a difference cleanly. A larger change with rough edges; only worth it if going back and forth between the two pages is the intended way of working.

## Open

- **Live cost of heavy patches.** Unmeasured. Everything at full is 13 oscillators with seven unison voices each, per note. All tuning renders used the GDScript engine.
- **Knob sweeps on held notes.** Resolved in the engine (979a5a1): a held note follows an edit at once, and a changed effect keeps its tail.
- **Loudness measurement.** It takes 0.1 to 0.3 s with the native core (measured 2026-11-22), so the page levels on Save only. Whether the reference notes (two bass notes and a chord) are the fairest reading is still open. Plucked sounds stay quiet on average: their peaks are already at the ceiling.
- **Combinations not yet heard.** Eight pairs and two stress cases were checked by ear. The switches in combination and most three-way mixes were not.
- **Chord notes under Gritty and Glassy** do not get the noise or bell FM; not yet judged by ear.
- **Randomise and Mutate numbers** (how many knobs are pushed, how far, how often a switch flips) are first guesses.
- **Knob feel**: drag speed and fine adjustment are first guesses; a value cannot be typed.
- **Levelling while playing.** Levelling runs on Save only, so while you play, loud combinations are louder than the base (up to about +8 LU for full Beefy); the limiter holds their peaks.
