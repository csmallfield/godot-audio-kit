# Handoff

Where the kit stands and what comes next, for whoever picks it up (a person or a fresh Claude session).

## Design in one paragraph

Sounds are **recipes** (text resources: voice layers, effects, seed, bind rules), never samples. Recipes **bake deterministically** to `AudioStreamWAV`, cached by a hash of everything that affects the sound. A **cue sheet** from the Godot Motion Kit (`MotionComposition.export_cue_sheet()`, or the live `MotionCue.bus`) says where each sound lands; the kit renders one sample-accurate track per composition. A **review render** proves timing and level with numbers and pictures, because an LLM working on the sound cannot hear it; taste stays a human listening call. Live synthesis (a native GDExtension mixer) comes later and must not need recipe changes.

Decisions taken: own synthesis core (no Csound / Pd / Faust dependency), baked first and live later, music as a pattern sequencer with better voices, desktop only, Apache-2.0, Godot 4.5+, 48 kHz.

## Phases

| Phase | Scope | Gate | Status |
| --- | --- | --- | --- |
| 0 Foundations | Recipe resource, DSP blocks, five starter voices, bake cache, review renderer and analysis, determinism tests | The same recipe bakes identically twice; the review report renders | **Done** |
| 1 SCF voices and bridge | SCF-family voices and palettes (Supergraphic, Print, Signal), motion kit bridge node, vocabulary, first skill file | SCF intro sounds rebuilt close enough by ear and spectrum, approved by Chris | Next |
| 2 Music | Tempo map, patterns (step strings, swing, polymeter), songs, mixer; FM, wavetable, better reverb; notes emitted as cues | A music bed worth keeping for a public cut | |
| 3 Live | Native DSP core (GDExtension), custom AudioStream, sample-exact cue mixer, game-state parameters | Live and baked renders of a recipe match within tolerance | |

SCF parity is a test bed, not a target: "close enough" by ear and spectrum. The motion kit's `demo/assets/audio/` holds the SCF soundtracks (full mixes) for comparison.

## Phase 0: what exists

- `AK.render / bake / bake_key / render_cues / load_cue_sheet`, effects (`lowpass highpass bandpass notch lowpass1 highpass1 drive bitcrush room echo gain limit normalize loudness`), transforms (`reverse fade varispeed width trim`).
- Recipe features: layers, palette tokens (`"$name"`), `bind` (intensity ranges, `data.<key>` mapping, targets: gain_db, pan, pitch_scale, voice params, effect params, `fx<i>.<key>`), seeded per-hit `vary`, `offset_s` (negative = starts before its cue).
- Voices: `whoosh`, `tone`, `boing`, `click`, `pluck`. Reference: `docs/voices.md` (regenerate with `addons/audio_kit/tools/voice_docs.gd`).
- Cue maps match like `MotionCuePlayer`; the default master chain sets −16 LUFS then limits at −1.5 dB (keeps true peak under −1 dBTP).
- Review: `addons/audio_kit/tools/review.gd` renders, `tools/analyze/analyze.py` measures. Alignment is reported as placement error (mix onset minus the hit's own lead-in), so soft-starting sounds don't read as late.
- Demo: the motion kit's race ident cue sheet (`demo/cues/race_ident.json`) with recipes in `demo/recipes/`. Its review passes every check.
- Tests: 24 headless tests (DSP correctness incl. a BS.1770 reference sine, voice hygiene, determinism, bindings, palettes, transforms, cue placement to the sample, stems summing to the mix, memoisation).

## Measured performance (GDScript, Linux cloud VM)

| Render | Time | Audio | Real-time factor |
| --- | --- | --- | --- |
| Dry effects (count, pop, tick, whoosh) | 4–41 ms | 0.05–0.5 s | 4–33× |
| GO hit with reverb | 622 ms | 2.6 s | 4× |
| 30 s, 8-voice bed stand-in with reverb | 12.3 s | 31.6 s | 3× |

Dry effects meet the 50 ms target; reverb misses it, and the bed is 23% over its 10 s target. Reverb (Freeverb: 16 combs + 8 all-passes) is the cost. Options, in order: a lighter reverb for short effects (fewer combs, or a small FDN); render reverb once per cue sheet on a send bus instead of per recipe; move the reverb alone to native code before Phase 3.

## Next steps (Phase 1)

1. Bridge node (`bridge_motion/`): bakes a composition's cue sheet into one track on its `audio` player with `clock = AUDIO`; event-playback fallback on `MotionCue.bus`; inert when the motion kit is absent.
2. SCF voices: mallet (modal), ratchet, static, follow (tone following a curve); steeper filter option for whoosh (two SVF stages); reverb send instead of per-recipe rooms.
3. Palettes: supergraphic, print, signal as `.tres`; vocabulary data file and `AKVocab.apply()`.
4. Ports: rebuild the sound of the SCF intros in the motion kit demos and compare (`tools/compare/`: loudness difference, per-cue spectral distance, side-by-side spectrograms).
5. Skill file `skills/godot-audio-kit/SKILL.md` covering recipes, cue maps, the review loop and vocabulary; point the motion kit skill's sound section at it.
