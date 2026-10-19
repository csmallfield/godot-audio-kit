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

**Recipe loops**: `AKLive.loop_start(recipe, params, xfade_s)` renders a recipe once, makes it seamless (`make_loop`: the last `xfade_s` crossfaded, equal power, into the start) and plays it as a native LOOP voice: mono, 4-point Hermite interpolation, gliding `rate`, plus the usual filter, gain, pan and send. `AKLiveVoice.recipe` does the same from the scene.

**Positional audio** (`AKSpatial`): inverse, inverse-square or linear distance attenuation from `unit_size`, fading to silence over the last 10% of `max_distance`; pan from the listener (2D: horizontal offset over half the screen; 3D: the listener's right vector); optional air absorption (cutoff down a decade at full range). The listener is the viewport's AudioListener2D/3D, else its camera, else the screen centre. `AKLiveVoice.spatial = "on"` applies it every frame; `AKLivePlayer.trigger_at(cue, position)` places one-shots (a balance on the stereo sound). No Doppler.

**Stingers** (`AKSong.stingers`): `{to, from, recipe, gain_db, intensity}`, most specific match wins; emitted by `section_events(si, lay, take, from_si)` as "stinger" lane events at the new section's first beat, so baked renders, prepared live songs and the sequencer all play them (and stay in parity). Not at the song's start. Live lead-ins (negative `offset_s`) up to `lookahead_s` play whole.

**Vertical remix**: `AKSong.intensity_lanes` (lane -> [from, to]) and `intensity`: a lane is silent below `from` and fades in, equal power, by `to`. Baked renders apply it per note (and skip silent lanes); live, `AKLive.set_music_intensity(x, glide_s)` moves the lane buses' faders, so prepared and sequenced playback still match the bake at the song's intensity. `song_play` and `prepare` reset the live intensity to `song.intensity`.

**Engine layers** (`AKLiveLayers`): recipe loops at reference values (`at`), each pitched by value / at within `rate_range`, crossfaded equal power on a log scale between neighbours; value from code or a node property. Its layers are AKLiveVoices, so spatial settings apply; `AKSpatial.for_node` now uses the nearest Node2D/Node3D at or above the voice.

**Audition dock** (`addons/audio_kit/editor/audition_dock.gd`, added by `plugin.gd` under the inspector): follows the inspector's edited object. Recipes: play once at an intensity and variant, or loop at a rate (native); replays 0.35 s after an edit; length, raw peak, LUFS, render time and a waveform. Songs: live play with a button per section (queued on the bar), loop or follow, intensity, position. Patterns: looped at a BPM and bar count. Cue maps: a button per cue. Auditions go through a DC block and a −1 dB limiter. Verified in the running editor under Xvfb (screenshot), and by `tests/test_dock.gd` outside it. Fixing it showed that the kit's scripts weren't `@tool`, so in the editor their methods didn't run (voices returned nothing; "Bake track" would have failed in the editor too): core, DSP, voices, sequencer and AKSpatial are now tool scripts. The scene nodes stay runtime-only.

**Step grid** (`editor/step_grid.gd`, `AKStepGrid`): in the dock for patterns. Click cycles rest, soft, normal, accent; right-click clears; lane names mute. Edits rewrite the lane's step string in place, keeping its spacing and `|` bars, and emit `changed`, so a pattern playing live picks them up through `song_changed`. The playhead follows the music, wrapping per lane (polymeter). Notes-only lanes are read-only. "Save pattern" writes the resource.

**Save WAV** (dock): a recipe's last render, a song at the dock's intensity (its own reverb and master), or a pattern's bars, to `res://audio_kit/auditions/` (git-ignored here), then refreshes the editor's file panel.

**Doppler and occlusion**: every live voice has a native `pitch` multiplier (oscillator frequency and loop rate). `AKLiveVoice.doppler` (amount) with `speed_of_sound` (343 for metres; pick a px/s scale in 2D) bends it from the change in distance, measured on game time so fixed-fps Movie Maker renders bend correctly, smoothed against frame jitter. `occlusion` casts a ray from the listener to the source each physics frame on `occlusion_mask`, ignoring collision objects at or above the source, and eases the voice down (`occlusion_db`) and duller (`occlusion_lowpass`). `AKLiveLayers` passes both through. The test runner now awaits tests, so they can wait on physics frames.

**Section signals**: `AKLive.section_started` now fires when the section starts sounding (from `update()`); `section_scheduled` fires a lookahead earlier, for visuals that must be ready on the beat.

**Test runner**: runs on the first frame (the tree accepts nodes, so tests can place listeners and emitters), and a test that hits a script error now fails instead of passing.

**Scene nodes** (`addons/audio_kit/live/`): `AKLivePlayer` (owns an AKLive and its player; trigger, song_play/queue/stop, set_lane_gain, section_started) and `AKLiveVoice` (a continuous voice; `bindings` map node properties onto parameters with linear or exponential curves, vectors by length; optional pan from the parent's screen position). The bridge's LIVE mode gains `live_song` and pumps the sequencer, following seeks.

**Demo**: `demo/live/live_demo.tscn`: the E1 bed live with sections on 1/2/3 and stingers (riser into full), a mouse-driven drone through an AKLiveVoice binding, ducked one-shots placed where you click, a car circling with a two-layer FM engine (AKLiveLayers: idle and high crossfaded by speed; level, pan and air from position), and music intensity on Up/Down (hats and claps fade in and out); the engine has Doppler and is muffled behind a wall on the right. Under Movie Maker an autopilot plays a 10 s tour.

**CI** (`.github/workflows/native.yml`): builds Linux x86_64, Windows x86_64 and macOS universal (debug and release), runs the suite with the native core and again without it, and bundles every library into one `audio-kit-native` artifact.

**Skill**: `skills/godot-audio-kit/SKILL.md`.

**Tests**: 102 headless (`tests/run_tests.gd`). Bridge tests run when the motion kit is linked; native and live tests run when the core is built; both pass trivially otherwise. `test_native.gd` compares every kernel, every voice and a full cue sheet between C++ and GDScript (within 1e-4 of peak); `test_live.gd` holds the live mixer to `render_cues` for the race ident and E1 with music, and checks seeks, one-shots, voice glides and releases, and mixing through the engine's playback; also every master effect live, ducked music, lane faders, the sequencer (play-through parity, loops, bar-quantised queueing, edits, seek), stingers (matching, parity, on a queued jump), recipe loops (seam, rate), intensity (curve, parity, live fades), engine layers (weights, live crossfade), the dock and step grid and WAV saving (`test_dock.gd`), Doppler (factor, pitch param, a pass-by at the expected shifts) and occlusion (a wall, the source's own body), the scene nodes (`test_live_nodes.gd`) and positional audio (`test_spatial.gd`).

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
3. **Next**: Chris tries the dock and step grid in the editor on his machine (only seen under Xvfb here); note entry in the step grid (pitch per step, not just hits); undo for grid edits through the editor's undo manager; reverb zones (the shared reverb's settings following the listener's area).
4. Point the motion kit skill's sound section (section 6) at this kit's skill and the bridge.
5. Nice to have: an editor dock to audition recipes and patterns; Print and Signal ports as further test beds.
