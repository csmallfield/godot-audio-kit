# Handoff

Where the kit stands and what comes next, for whoever picks it up (a person or a fresh Claude session).

## Design in one paragraph

Sounds are **recipes** (text resources: voice layers, effects, seed, bind rules), never samples. Recipes **bake deterministically** to `AudioStreamWAV`, cached by a hash of everything that affects the sound. A **cue sheet** from the Godot Motion Kit (`MotionComposition.export_cue_sheet()`, or the live `MotionCue.bus`) says where each sound lands; the kit renders one sample-accurate track per composition. A **review render** proves timing and level with numbers and pictures, because an LLM working on the sound cannot hear it; taste stays a human listening call. A **native core** (C++ GDExtension) runs the same DSP about 14× faster and adds a **live mixer**: the same timeline mixed as it plays, plus game-event one-shots and continuous voices, without recipe changes.

Decisions taken: own synthesis core (no Csound / Pd / Faust dependency), baked first and live later, music as a pattern sequencer with better voices, desktop only, Apache-2.0, Godot 4.5+, 48 kHz. SCF parity is a test bed, not a target: close enough by ear and spectrum.

## Phases

| Phase | Scope | Gate | Status |
| --- | --- | --- | --- |
| 0 Foundations | Recipe resource, DSP blocks, starter voices, bake cache, review renderer and analysis, determinism tests | The same recipe bakes identically twice; the review report renders | Done |
| 1 Voices, palettes, bridge | SCF-family voices, palettes, vocabulary, motion kit bridge, E1 port and compare tool, skill file | E1 sound rebuilt close enough by ear and spectrum, approved by Chris | Built; awaiting Chris's listen |
| 2 Music | Tempo map, patterns (step strings, swing, polymeter), songs, mixer; FM, wavetable, drums; notes emitted as cues | A music bed worth keeping for a public cut | **Built; awaiting Chris's listen** |
| 3 Live | Native DSP core (GDExtension), custom AudioStream, sample-exact cue mixer, game-state parameters | Live and baked renders of a recipe match within tolerance | **Built; gate met** (E1 with music: SNR 140 dB live vs baked) |

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

**Native core** (`native/`, C++17, godot-cpp at godot-4.5-stable, SCons): `AKNative` kernels mirroring the GDScript DSP (sine, saw, square, triangle with PolyBLEP; glide, mul, add, scale; decay and ADSR envelopes; one-pole and SVF filters with swept cutoffs; Karplus-Strong; FM; Freeverb; limiter; BS.1770 loudness; buffer mixing). GDScript delegates through `AKDsp.nat()` and falls back to its own code when the library is missing; `AKDsp.native_enabled` toggles it. Packed arrays are copy-on-write, so every native call returns a new array and callers assign it. Libraries go to `addons/audio_kit/native/bin/` (git-ignored; built by CI).

**Live mixer** (`native/src/live_core.*`, `ak_live.*`; GDScript `AKLive` in `core/live.gd`): `AKLiveStream` (an `AudioStream`) and its `AudioStreamPlaybackResampled` playback at 48 kHz. Buffers are registered once and scheduled on an absolute frame timeline (they survive seeks), one-shots go in at the current frame plus a delay, and continuous voices (sine, saw, square, triangle, noise; SVF low-pass; smoothed freq, gain, cutoff, q, pan, send, width, noise) glide while they play. A streaming Freeverb send and a master chain (gain, one-pole and SVF filters, end fade, limiter) follow the same order as `render_cues`. Loudness and normalize steps are measured once at `prepare()` by rendering the timeline offline on the same mixer, then run as a fixed gain; master effects that can't stream (room, echo, drive, bitcrush) are skipped with a warning. The mixer state sits behind a mutex shared with the audio thread. `render_offline(frames)` runs exactly the playback code, which is what the gate tests use.

**Bridge LIVE mode**: `AKCueBridge.mode = LIVE` prepares the composition's timeline (and song) on an `AKLive`, attaches its stream to the composition's `audio` player with `clock = AUDIO`, re-prepares if cues change in the composition's `_ready`, and offers `trigger()` for game events. Without the native core it falls back to BAKED. Checked end to end with Movie Maker: the demo composition recorded in LIVE and in BAKED lines up at lag 0, SNR 75 dB (the 16-bit dither floor of the bake).

**Live master chain**: every master effect runs live (gain, filters, dcblock, drive, bitcrush, echo, room, limit, end fade); loudness and normalize become a fixed gain measured at `prepare()`. Room and echo tails are now padded up front in `render_cues` too, so every stage of the baked chain runs over the full length as the live one does (only master chains with a room or echo after a stateful effect change; the track key carries `track_format = 2`). Bitcrush is a quantiser, so float-rounding differences upstream can flip a sample by one step; its test allows that.

**Buses and ducking**: live sources play on buses with gliding faders (dry and send). `AKCueMap.duck` ({depth_db, full_at_db, attack_s, release_s}) ducks the music's dry signal under the effects with one envelope follower (`ak::Ducker`, mirrored by `AKDynamics.duck`), baked and live. The reverb send isn't ducked, so tails don't pump. Effects, triggers and voices use bus 0; each song lane gets its own bus (`AKLive.lane_bus`, `set_lane_gain`).

**Live sequencer** (`AKLive.song_play/queue/stop/changed/seek/update`): song notes rendered a lookahead (default 0.5 s) before they're due and scheduled on lane buses. "song" follow plays the sections in order; "loop" repeats a section until `song_queue` moves on at the next beat, bar or section end. Repeats reseed humanize and probability (`AKSong.section_events(si, take)`). Edits re-derive the notes not yet sounding. A straight play-through matches the bake exactly (E1: 142 dB). `prepare(..., live_song = true)` sequences the song but still measures loudness with it in. `AKSong.events()` now breaks time ties by lane and pitch, so every caller sees the same order. Limits: a seek restarts the notes from the new time (notes that started earlier don't resume); queued jumps use the target section's own tempo from its first bar.

**Scene nodes** (`addons/audio_kit/live/`): `AKLivePlayer` (owns an AKLive and its player; trigger, song_play/queue/stop, set_lane_gain, section_started) and `AKLiveVoice` (a continuous voice; `bindings` map node properties onto parameters with linear or exponential curves, vectors by length; optional pan from the parent's screen position). The bridge's LIVE mode gains `live_song` and pumps the sequencer, following seeks.

**Demo**: `demo/live/live_demo.tscn`: the E1 bed live with sections on 1/2/3, a mouse-driven drone through an AKLiveVoice binding, and ducked one-shots on click and Space. Under Movie Maker an autopilot plays a 10 s tour.

**CI** (`.github/workflows/native.yml`): builds Linux x86_64, Windows x86_64 and macOS universal (debug and release), runs the suite with the native core and again without it, and bundles every library into one `audio-kit-native` artifact.

**Skill**: `skills/godot-audio-kit/SKILL.md`.

**Tests**: 76 headless (`tests/run_tests.gd`). Bridge tests run when the motion kit is linked; native and live tests run when the core is built; both pass trivially otherwise. `test_native.gd` compares every kernel, every voice and a full cue sheet between C++ and GDScript (within 1e-4 of peak); `test_live.gd` holds the live mixer to `render_cues` for the race ident and E1 with music, and checks seeks, one-shots, voice glides and releases, and mixing through the engine's playback; also every master effect live, ducked music, lane faders, the sequencer (play-through parity, loops, bar-quantised queueing, edits, seek), and the scene nodes (`test_live_nodes.gd`).

## E1 comparison (Godot render vs the SCF soundtrack)

Same events in the same places: letter-pluck run, wipes, disc landings with falling pitch, node mallet stack, rising launches on the outro. Hits register in both on 31 of 56 cues; the misses are mostly the reference's **music bed** (a kick on every beat and bass) masking its effects, which also makes the reference low-heavy where ours is mid-heavy. The bed comes with phase 2. Letter plucks were softened after the first comparison (tone 7 kHz → 3.2 kHz).

## E1 with music

Mixed under the effects, the bed brings the band balance at the cues close to the original (ours low −1.4 / mid −8.2 / high −25.0 dB of each window's energy; original −2.2 / −7.6 / −22.4). The piece ends exactly on 14.00 s with a clean last frame (end fade 0.5 s). Hit agreement is 32–35 of 56 depending on the bed; that metric is crude with music under both.

## Measured performance (Linux cloud VM)

With the native core (debug build of the extension; the release build is similar or faster):

| Render | Native | GDScript | Speed-up |
| --- | --- | --- | --- |
| Race ident, 6 s, with reverb send | 109 ms | 1.56 s | 14× |
| E1 effects + music, 14 s | 1.06 s | ~13–15 s | ~13× |
| Live: prepare E1 (166 buffers, 242 hits, loudness probe) | 0.63 s | — | — |
| Live: mixing E1 | 37 ms for 14 s | — | 383× real time |

GDScript only (the fallback):

| Render | Time | Audio | Real-time factor |
| --- | --- | --- | --- |
| Dry effects (count, pop, tick, whoosh) | 4–37 ms | 0.05–0.5 s | 6–33× |
| E1 track, 56 cues, shared reverb | 6.6 s | 14.6 s | 2.2× |
| Full-quality reverb over 15 s | 2.6 s | — | the largest single cost |
| 30 s, 8-voice bed stand-in with reverb | 12.8 s | 31.6 s | 2.5× |
| E1 song alone (186 notes, 5 lanes, reverb) | ~8–11 s | 15.8 s | ~1.5× |
| E1 effects + music, no stems | ~13–15 s | 14 s | ~1× |

Bakes are cached and "Bake track" removes runtime cost, so this is fine for authored pieces. Live use (phase 3) needs native DSP; the reverb is the first thing to port. Phase 1 wins: recursive sines for fixed pitches, constant-coefficient filters, per-partial truncation in mallet (mallet renders went from ~150 ms to a fraction).

Music is where GDScript runs out of headroom: a piece with a full groove renders at about real time. The native core fixes that, and the live mixer costs well under 1% of a core.

## Next steps

1. **Chris listens** to the E1 renders (effects only, and with music) and the race ident; translate notes with `AKVocab` or recipe edits.
2. **Chris tries LIVE**: build the core (or take the CI artifact), run `demo/live/live_demo.tscn` and the bridge demo with `mode = LIVE`. Check that Windows and macOS CI builds load in the editor (only Linux has been run here).
3. **Live, next**: recipe-based loops as continuous voices (an engine sample rendered from a recipe, played with rate and filter modulation), positional 2D/3D attenuation for AKLiveVoice, stingers (a one-bar transition rendered on a section change), an editor dock to audition patterns live.
4. Point the motion kit skill's sound section (section 6) at this kit's skill and the bridge.
5. Nice to have: an editor dock to audition recipes and patterns; Print and Signal ports as further test beds.
