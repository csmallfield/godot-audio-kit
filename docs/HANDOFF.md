# Handoff

Where the kit stands and what comes next, for whoever picks it up (a person or a fresh Claude session).

## Design in one paragraph

Sounds are **recipes** (text resources: voice layers, effects, seed, bind rules), never samples. Recipes **bake deterministically** to `AudioStreamWAV`, cached by a hash of everything that affects the sound. A **cue sheet** from the Godot Motion Kit (`MotionComposition.export_cue_sheet()`, or the live `MotionCue.bus`) says where each sound lands; the kit renders one sample-accurate track per composition. A **review render** proves timing and level with numbers and pictures, because an LLM working on the sound cannot hear it; taste stays a human listening call. Live synthesis (a native GDExtension mixer) comes later and must not need recipe changes.

Decisions taken: own synthesis core (no Csound / Pd / Faust dependency), baked first and live later, music as a pattern sequencer with better voices, desktop only, Apache-2.0, Godot 4.5+, 48 kHz. SCF parity is a test bed, not a target: close enough by ear and spectrum.

## Phases

| Phase | Scope | Gate | Status |
| --- | --- | --- | --- |
| 0 Foundations | Recipe resource, DSP blocks, starter voices, bake cache, review renderer and analysis, determinism tests | The same recipe bakes identically twice; the review report renders | Done |
| 1 Voices, palettes, bridge | SCF-family voices, palettes, vocabulary, motion kit bridge, E1 port and compare tool, skill file | E1 sound rebuilt close enough by ear and spectrum, approved by Chris | Built; awaiting Chris's listen |
| 2 Music | Tempo map, patterns (step strings, swing, polymeter), songs, mixer; FM, wavetable, drums; notes emitted as cues | A music bed worth keeping for a public cut | **Built; awaiting Chris's listen** |
| 3 Live | Native DSP core (GDExtension), custom AudioStream, sample-exact cue mixer, game-state parameters | Live and baked renders of a recipe match within tolerance | |

## What exists

**Core** (`addons/audio_kit/core/`): `AK` (render, bake, bake_key, render_cues with a shared reverb send, track_key, effects, transforms), `AKRecipe`, `AKCueMap` (master chain: dcblock → loudness −16 LUFS → limit −1.5 dB; shared `reverb`), `AKPalette`, `AKVocab`, `AKBuffer`.

**Voices** (`voices/`, reference in `docs/voices.md`): whoosh (12/24 dB sweep), tone, boing, click, pluck, mallet (modal: wood, metal, glass, bar), ratchet, static, follow (breakpoint pitch/level curves).

**Effects**: lowpass/highpass/bandpass/notch (12 or 24 dB), lowpass1, highpass1, drive, bitcrush, room (small/full), echo, gain, limit, normalize, loudness, dcblock. **Transforms**: reverse, fade, varispeed, width, trim.

**Bridge** (`bridge_motion/cue_bridge.gd`, `AKCueBridge`): BAKED mode renders the composition's cue sheet into one track on its `audio` player with `clock = AUDIO` (cached by hash; inspector button "Bake track" saves it into the project); EVENTS mode plays cues from a player pool. Duck-typed: the motion kit is optional. Verified in a live scene (`demo/with_motion_kit/bridge_demo.tscn`).

**Palettes**: supergraphic, print, signal. **Vocabulary**: 23 words in `vocabulary.json`.

**Music** (`addons/audio_kit/sequencer/`): `AKTempoMap` (bpm, meter, downbeat offset, tempo changes), `AKNotes` (note names, MIDI, scales, step-string parsing), `AKPattern` (lanes with step strings, notes or scale degrees, chords, ties, swing, humanize, probability, polymeter lane lengths), `AKSong` (sections with fractional bars, mutes, transpose, automation; lane mix; own reverb and master when rendered alone; `to_cues()` turns notes and sections into cue-shaped events with `data.source = "song"`, which renderers skip). `AK.render` takes `overrides` (`_note_hz`, `_keytrack`, `_gate_s`, automation targets); voices declare `pitch_params()`. `render_cues(..., song)` mixes a song under the effects sharing reverb and master; `AKCueBridge.song` and `song_cues` do the same for compositions. Recipes gain `vary_variants` to cap per-hit variants. Cue maps gain `end_fade_s` to fade and stop on the picture's last frame.

**Music voices**: fm (2–3 operator, decaying index), wavetable (sine→triangle→saw→square morph, unison, sub, enveloped low-pass), kick, snare, clap, hat (808-style metal cluster).

**Demos**: race ident (motion kit cue sheet, `demo/recipes/`), E1 Supergraphic port (`demo/cues/e1_supergraphic.json` transcribed from the motion kit source, 56 cues; `demo/recipes/supergraphic/make.py` writes 17 recipes and the map), E1 music bed (`demo/music/e1/make.py`: 120 bpm, downbeat at 0.25 s, the original's A-A-G-C arp, sections arp / full / light following the picture). All reviews pass every check.

**Tools**: `addons/audio_kit/tools/review.gd` (render) + `tools/analyze/analyze.py` (measure, picture); `tools/compare/compare.py` (against a reference); `tools/write_recipes.py` (batch recipes from Python); `tools/link_motion_kit.sh`; `addons/audio_kit/tools/voice_docs.gd`.

**Skill**: `skills/godot-audio-kit/SKILL.md`.

**Tests**: 52 headless (`tests/run_tests.gd`), bridge tests run when the motion kit is linked and pass trivially otherwise. A suite that fails to parse now fails the run instead of hanging it.

## E1 comparison (Godot render vs the SCF soundtrack)

Same events in the same places: letter-pluck run, wipes, disc landings with falling pitch, node mallet stack, rising launches on the outro. Hits register in both on 31 of 56 cues; the misses are mostly the reference's **music bed** (a kick on every beat and bass) masking its effects, which also makes the reference low-heavy where ours is mid-heavy. The bed comes with phase 2. Letter plucks were softened after the first comparison (tone 7 kHz → 3.2 kHz).

## E1 with music

Mixed under the effects, the bed brings the band balance at the cues close to the original (ours low −1.4 / mid −8.2 / high −25.0 dB of each window's energy; original −2.2 / −7.6 / −22.4). The piece ends exactly on 14.00 s with a clean last frame (end fade 0.5 s). Hit agreement is 32–35 of 56 depending on the bed; that metric is crude with music under both.

## Measured performance (GDScript, Linux cloud VM)

| Render | Time | Audio | Real-time factor |
| --- | --- | --- | --- |
| Dry effects (count, pop, tick, whoosh) | 4–37 ms | 0.05–0.5 s | 6–33× |
| E1 track, 56 cues, shared reverb | 6.6 s | 14.6 s | 2.2× |
| Full-quality reverb over 15 s | 2.6 s | — | the largest single cost |
| 30 s, 8-voice bed stand-in with reverb | 12.8 s | 31.6 s | 2.5× |
| E1 song alone (186 notes, 5 lanes, reverb) | ~8–11 s | 15.8 s | ~1.5× |
| E1 effects + music, no stems | ~13–15 s | 14 s | ~1× |

Bakes are cached and "Bake track" removes runtime cost, so this is fine for authored pieces. Live use (phase 3) needs native DSP; the reverb is the first thing to port. Phase 1 wins: recursive sines for fixed pitches, constant-coefficient filters, per-partial truncation in mallet (mallet renders went from ~150 ms to a fraction).

Music is where GDScript runs out of headroom: a piece with a full groove renders at about real time. Fine for baked tracks (bake once in the editor); not for live music. This makes phase 3's native core the priority, starting with the reverb, oscillators and filters.

## Next steps

1. **Chris listens** to the E1 renders (effects only, and with music) and the race ident; translate notes with `AKVocab` or recipe edits.
2. **Phase 3 live**: native DSP core (GDExtension: C++ via godot-cpp or Rust via godot-rust, open question) with the same algorithms; golden renders compare it with GDScript; a custom `AudioStream`/`AudioStreamPlayback` mixer scheduling cues from `cues_between()` at exact sample offsets; recipes unchanged. Start with reverb, oscillators and filters, which dominate render time.
3. Point the motion kit skill's sound section (section 6) at this kit's skill and the bridge.
4. Nice to have: an editor dock to audition recipes and patterns; Print and Signal ports as further test beds.
