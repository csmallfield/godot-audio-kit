# Handoff

Where the kit stands and what comes next, for whoever picks it up (a person or a fresh Claude session).

## Design in one paragraph

Sounds are **recipes** (text resources: voice layers, effects, seed, bind rules), never samples. Recipes **bake deterministically** to `AudioStreamWAV`, cached by a hash of everything that affects the sound. A **cue sheet** from the Godot Motion Kit (`MotionComposition.export_cue_sheet()`, or the live `MotionCue.bus`) says where each sound lands; the kit renders one sample-accurate track per composition. A **review render** proves timing and level with numbers and pictures, because an LLM working on the sound cannot hear it; taste stays a human listening call. Live synthesis (a native GDExtension mixer) comes later and must not need recipe changes.

Decisions taken: own synthesis core (no Csound / Pd / Faust dependency), baked first and live later, music as a pattern sequencer with better voices, desktop only, Apache-2.0, Godot 4.5+, 48 kHz. SCF parity is a test bed, not a target: close enough by ear and spectrum.

## Phases

| Phase | Scope | Gate | Status |
| --- | --- | --- | --- |
| 0 Foundations | Recipe resource, DSP blocks, starter voices, bake cache, review renderer and analysis, determinism tests | The same recipe bakes identically twice; the review report renders | Done |
| 1 Voices, palettes, bridge | SCF-family voices, palettes, vocabulary, motion kit bridge, E1 port and compare tool, skill file | E1 sound rebuilt close enough by ear and spectrum, approved by Chris | **Built; awaiting Chris's listen** |
| 2 Music | Tempo map, patterns (step strings, swing, polymeter), songs, mixer; FM, wavetable, better reverb; notes emitted as cues | A music bed worth keeping for a public cut | Next |
| 3 Live | Native DSP core (GDExtension), custom AudioStream, sample-exact cue mixer, game-state parameters | Live and baked renders of a recipe match within tolerance | |

## What exists

**Core** (`addons/audio_kit/core/`): `AK` (render, bake, bake_key, render_cues with a shared reverb send, track_key, effects, transforms), `AKRecipe`, `AKCueMap` (master chain: dcblock → loudness −16 LUFS → limit −1.5 dB; shared `reverb`), `AKPalette`, `AKVocab`, `AKBuffer`.

**Voices** (`voices/`, reference in `docs/voices.md`): whoosh (12/24 dB sweep), tone, boing, click, pluck, mallet (modal: wood, metal, glass, bar), ratchet, static, follow (breakpoint pitch/level curves).

**Effects**: lowpass/highpass/bandpass/notch (12 or 24 dB), lowpass1, highpass1, drive, bitcrush, room (small/full), echo, gain, limit, normalize, loudness, dcblock. **Transforms**: reverse, fade, varispeed, width, trim.

**Bridge** (`bridge_motion/cue_bridge.gd`, `AKCueBridge`): BAKED mode renders the composition's cue sheet into one track on its `audio` player with `clock = AUDIO` (cached by hash; inspector button "Bake track" saves it into the project); EVENTS mode plays cues from a player pool. Duck-typed: the motion kit is optional. Verified in a live scene (`demo/with_motion_kit/bridge_demo.tscn`).

**Palettes**: supergraphic, print, signal. **Vocabulary**: 23 words in `vocabulary.json`.

**Demos**: race ident (motion kit cue sheet, `demo/recipes/`), E1 Supergraphic port (`demo/cues/e1_supergraphic.json` transcribed from the motion kit source, 56 cues; `demo/recipes/supergraphic/make.py` writes 17 recipes and the map). Both reviews pass every check.

**Tools**: `addons/audio_kit/tools/review.gd` (render) + `tools/analyze/analyze.py` (measure, picture); `tools/compare/compare.py` (against a reference); `tools/write_recipes.py` (batch recipes from Python); `tools/link_motion_kit.sh`; `addons/audio_kit/tools/voice_docs.gd`.

**Skill**: `skills/godot-audio-kit/SKILL.md`.

**Tests**: 36 headless (`tests/run_tests.gd`), bridge tests run when the motion kit is linked and pass trivially otherwise. A suite that fails to parse now fails the run instead of hanging it.

## E1 comparison (Godot render vs the SCF soundtrack)

Same events in the same places: letter-pluck run, wipes, disc landings with falling pitch, node mallet stack, rising launches on the outro. Hits register in both on 31 of 56 cues; the misses are mostly the reference's **music bed** (a kick on every beat and bass) masking its effects, which also makes the reference low-heavy where ours is mid-heavy. The bed comes with phase 2. Letter plucks were softened after the first comparison (tone 7 kHz → 3.2 kHz).

## Measured performance (GDScript, Linux cloud VM)

| Render | Time | Audio | Real-time factor |
| --- | --- | --- | --- |
| Dry effects (count, pop, tick, whoosh) | 4–37 ms | 0.05–0.5 s | 6–33× |
| E1 track, 56 cues, shared reverb | 6.6 s | 14.6 s | 2.2× |
| Full-quality reverb over 15 s | 2.6 s | — | the largest single cost |
| 30 s, 8-voice bed stand-in with reverb | 12.8 s | 31.6 s | 2.5× |

Bakes are cached and "Bake track" removes runtime cost, so this is fine for authored pieces. Live use (phase 3) needs native DSP; the reverb is the first thing to port. Phase 1 wins: recursive sines for fixed pitches, constant-coefficient filters, per-partial truncation in mallet (mallet renders went from ~150 ms to a fraction).

## Next steps

1. **Chris listens** to the E1 and race ident renders and gives notes; translate them with `AKVocab` or recipe edits.
2. **Phase 2 music**: `AKTempoMap`, `AKPattern` with step strings (`"X...x..."`), swing, humanize, polymeter, probability; `AKSong` sections and automation; mixer; FM and wavetable voices; notes emitted as cue-shaped events so motion can follow music. First target: a bed for E1 comparable to the original's bright electro.
3. Point the motion kit skill's sound section (section 6) at this kit's skill and the bridge.
4. Print and Signal ports are optional test beds; their palettes exist.
