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
| Lab 2 Synth engine (branch `sound-lab`) | `AKPatch`, native polyphonic voice engine with a GDScript twin, `AKSynthStream`, bakes through the same code, synth-like voices as patches | A patch played live matches its bake; 32 voices under 10% of a core | **Built; both gates met in tests** (live = bake exactly; 32 two-oscillator voices ≈ 5.5% of a core on this VM); awaiting Chris's listen |
| Lab 1 Sound Lab (branch `sound-lab`, plan `docs/plans/sound-lab.md`) | Sound Lab editor tab, SFX generator (10 categories, randomise, mutate), recipes as AudioStreams, one-click bake to WAV | Ten game sound effects made and baked in a few minutes | **Built; gate met in tests** (ten generated and baked in about 0.25 s natively, 0.85 s in GDScript); awaiting Chris's listen and UI review |

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

**Step grid** (`editor/step_grid.gd`, `AKStepGrid`): in the dock for patterns. Click cycles rest, soft, normal, accent; right-click clears; lane names mute. Edits rewrite the lane's step string in place, keeping its spacing and `|` bars, and emit `changed`, so a pattern playing live picks them up through `song_changed`. The playhead follows the music, wrapping per lane (polymeter). Notes-only lanes are read-only. "Save pattern" writes the resource. On pitched lanes the wheel moves a hit's note by a semitone (a degree on `degrees` lanes; Shift: an octave) and note names are drawn on the hits; the first such edit spreads the lane's cycled notes out to one per hit, since notes belong to hits in order (so adding a hit before others shifts which note each later hit gets). Every grid edit is an undoable action: in the editor it joins the editor's history (Ctrl+Z; checked in the running editor), elsewhere a local UndoRedo.

**Save WAV** (dock): a recipe's last render, a song at the dock's intensity (its own reverb and master), or a pattern's bars, to `res://audio_kit/auditions/` (git-ignored here), then refreshes the editor's file panel.

**Doppler and occlusion**: every live voice has a native `pitch` multiplier (oscillator frequency and loop rate). `AKLiveVoice.doppler` (amount) with `speed_of_sound` (343 for metres; pick a px/s scale in 2D) bends it from the change in distance, measured on game time so fixed-fps Movie Maker renders bend correctly, smoothed against frame jitter. `occlusion` casts a ray from the listener to the source each physics frame on `occlusion_mask`, ignoring collision objects at or above the source, and eases the voice down (`occlusion_db`) and duller (`occlusion_lowpass`). `AKLiveLayers` passes both through. The test runner now awaits tests, so they can wait on physics frames.

**Reverb zones** (`AKReverbZone2D/3D`, areas with room, damp, width, return_db, glide; overlap resolved by the area's own `priority`): `AKLivePlayer` checks which zone holds the listener each physics frame (`AKSpatial.reverb_zone_at`, a point query on areas) and glides the shared reverb there with `AKLive.set_reverb_space` (native `set_reverb_params`: feedback, damping, width and return glide per sample without clearing the reverb, so tails carry into the new space); outside every zone it returns to the cue map's reverb. Quality (small/full) stays as prepared. The native reverb only touches its settings while they move, so a still reverb is bit-identical to before.

**Fix: the live reverb is always on.** `prepare()` used to switch it on only when the prepared timeline had sends, so a mixer prepared with no cues (`prepare([], map)`, how games and the dock use it) played every trigger, voice and live-sequenced note dry. It now always runs; the gates still pass (a reverb of silence is silence).

**Reed voice** (`voices/reed.gd`): a saxophone-like lead: saw plus narrow pulse through two formant resonances and an envelope-driven low-pass (brighter as it's blown), breath noise strongest at the attack, a scoop up into each note, delayed vibrato, optional growl. About 19 ms a note natively.

**Last Ferry** (`demo/song/last_ferry/`, `demo/with_motion_kit/last_ferry_video.*`): a whole original song as a test of both kits, 56 bars at 80 bpm (168 s). Chords are voiced as four EP lanes and three pad lanes (one chord tone each, voice-led) because a lane's `chord` is one shape; the lead is a notes-only lane written from (bar, step, length, pitch) lists in `make.py`. Mix balanced from stems (lead on top, around −10 dB in the choruses; bass, piano, kick and snare a few dB under); the review passes at −16 LUFS, −1.5 dBTP. A full render with stems takes about 2 minutes natively, mostly because humanized velocities make every note a unique render. The video is a pure function of the frame: lead notes, piano hits, kick, snare and rim times come from `AKSong.events()`; the bridge bakes the song (about 70 s, then cached). Movie Maker renders it at roughly 0.2 s a frame under Xvfb software GL (about 20 minutes for the song); write `.avi` rather than PNGs (5000+ frames).

**Section signals**: `AKLive.section_started` now fires when the section starts sounding (from `update()`); `section_scheduled` fires a lookahead earlier, for visuals that must be ready on the beat.

**Test runner**: runs on the first frame (the tree accepts nodes, so tests can place listeners and emitters), and a test that hits a script error now fails instead of passing.

**Scene nodes** (`addons/audio_kit/live/`): `AKLivePlayer` (owns an AKLive and its player; trigger, song_play/queue/stop, set_lane_gain, section_started) and `AKLiveVoice` (a continuous voice; `bindings` map node properties onto parameters with linear or exponential curves, vectors by length; optional pan from the parent's screen position). The bridge's LIVE mode gains `live_song` and pumps the sequencer, following seeks.

**Demo**: `demo/live/live_demo.tscn`: the E1 bed live with sections on 1/2/3 and stingers (riser into full), a mouse-driven drone through an AKLiveVoice binding, ducked one-shots placed where you click, a car circling with a two-layer FM engine (AKLiveLayers: idle and high crossfaded by speed; level, pan and air from position), and music intensity on Up/Down (hats and claps fade in and out); the engine has Doppler and is muffled behind a wall on the right. Under Movie Maker an autopilot plays a 10 s tour.

**CI** (`.github/workflows/native.yml`): builds Linux x86_64, Windows x86_64 and macOS universal (debug and release), runs the suite with the native core and again without it, and bundles every library into one `audio-kit-native` artifact.

**Sound Lab, phase 1** (plan: `docs/plans/sound-lab.md`; branch `sound-lab`):

- *Lab tab* (`editor/sound_lab.gd`, `AKSoundLab`): an editor main screen named "Sound Lab", beside 2D, 3D and Script (`plugin.gd`: `_has_main_screen`). Left: a button per category (each press = a new random seed), a seed box (type a seed to get that sound back), Randomise, Mutate with an amount slider, Play/Stop, "new variant each play", "replay when edited", history. Centre: name, length/peak/LUFS/render time, waveform, a one-line-per-layer summary, then folder and name (default `res://audio/sfx/<category>_<seed>[_m<n>]`) with Bake WAV, Save recipe (`.tres`), Save stream (`<name>_stream.tres`, an `AKRecipeStream` with the recipe embedded). Right: an embedded `EditorInspector` on the current recipe (editor only; edits replay), plus "Open in Inspector" (so the dock follows it). Columns scroll, so a short window never clips. Checked in the running editor under Xvfb (screenshot): the tab shows, generates, and the inspector edits.
- *Generator* (`lab/sfx_generator.gd`, `AKSfxGen`): `generate(category, seed)`, `mutate(recipe, seed, amount)`, `name_for(recipe)`, `CATEGORIES`, `ABOUT`. Categories: pickup, jump, laser, hit, explosion, powerup, ui_click, ui_confirm, ui_cancel, blip; plus `random` (Randomise: one to three layers of any of ten voices, every parameter drawn from its range with times capped, zero to two effects, trimmed to 2 s). Each category is a hand-written design over existing voices (`tone`, `click`, `whoosh`, `boing`, `static`) and effects; seeded draws pick values inside its ranges (log-uniform for Hz and seconds, values rounded to four significant figures so the `.tres` reads well). Ideas follow the classic sfxr family; no code was taken from any of them. Every recipe ends `dcblock > normalize -1 dBFS`, carries `vary = {pitch_scale: 2–8%}`, and records `sfx_category`, `sfx_seed`, `sfx_version` (and `sfx_mutations`) as resource metadata, which isn't part of the bake key. Mutate moves Hz by up to ±amount octaves, dB by ±6·amount, everything else by ±1.5·amount relative, clamped to each voice's schema; it leaves text choices, the recipe's shape, its seed and the final level steps alone. Bump `AKSfxGen.VERSION` when a generator changes what a seed gives.
- *Recipes as AudioStreams* (`core/recipe_stream.gd`, `AKRecipeStream`): `_instantiate_playback` bakes the chosen variant through `AK.bake` (cached by content hash, on disk in the editor) and returns that WAV's playback, so it works in AudioStreamPlayer/2D/3D, AudioStreamRandomizer and anything that takes a stream, in the editor and in exports, native or not. `vary_per_play` picks a random one of `variants` (default 4, never the same twice in a row); `warm()` renders them up front; `intensity` and `data` feed the recipe's bind rules. The first play of each variant renders on the calling thread (about 1–5 ms natively for these sounds, 5–40 ms in GDScript): call `warm()` in `_ready` for anything latency-sensitive. Inspector button "Bake to WAV" (`@export_tool_button`) writes beside the stream or to `wav_path`.
- *Bake to WAV*: `AK.bake_wav(recipe, path, ...)` writes the exact samples (and dither) `AK.bake` gives; `AK.save_wav(buf, path)` and `AK.refresh_editor_files()` are what the dock's Save WAV now uses too. The dock shows an `AKRecipeStream` as its recipe plus a "Bake WAV" button.
- *Listening without ears* (`lab/sound_features.gd`, `AKSoundFeatures.of(buf)`; `tools/sfx_listen.gd` writes WAVs per category to `out/sfx_lab/` and prints a table): length, level, 10 ms RMS envelope (attack, decay, onsets), spectral centroid, tonality (share of energy in bins 6 dB over their neighbours), pitch at the start and end. Medians over seeds 1–5:

| Category | Length s | LUFS | Attack ms | Centroid Hz | Tonality | Pitch moves |
| --- | --- | --- | --- | --- | --- | --- |
| pickup | 0.45 | -9.4 | 60 | 1938 | 0.81 | +0.42 oct |
| jump | 0.32 | -4.6 | 10 | 685 | 0.72 | +0.66 oct |
| laser | 0.27 | -5.4 | 20 | 1716 | 0.63 | -1.30 oct |
| hit | 0.21 | -4.8 | 30 | 420 | 0.57 | -0.97 oct |
| explosion | 1.25 | -15.3 | 60 | 113 | 0.76 | -2.10 oct |
| powerup | 0.84 | -7.7 | 150 | 942 | 0.78 | +1.00 oct |
| ui_click | 0.06 | -13.1 | 0 | 2443 | 0.22 | -0.06 oct |
| ui_confirm | 0.43 | -9.7 | 60 | 979 | 0.84 | +0.33 oct |
| ui_cancel | 0.42 | -10.1 | 0 | 589 | 0.91 | -0.33 oct |
| blip | 0.07 | -5.3 | 0 | 1154 | 0.83 | +0.00 oct |

  Known limits: sounds are peak-normalised, so loudness spreads about 10 dB across categories (an explosion sits near −15 LUFS, a jump near −5); lowering a category's `gain_db` does nothing because the normalise comes last (edit or drop the normalise step instead). The RMS onset count can't see a pickup's second note (the notes join without a dip); the pitch direction catches it instead.

**Synth engine, phase 2** (reference: `docs/synth.md`):

- *Patches* (`synth/patch.gd`, `AKPatch`): up to 4 oscillators (sine, triangle, saw, square, pulse, noise, morph; levels, semitone/cent offsets, pulse width, morph position, phase-modulation routing `fm_from` + `fm_index` with feedback), unison 1–7 with detune, an SVF filter (off/low/high/band/notch, 12 or 24 dB), three envelopes (amp, env2, env3; linear attack with 0 = instant, linear or exponential decay, time-constant release), two LFOs (sine, triangle, saw, square, random; delay), a 16-row modulation matrix (11 sources, 10 destinations including per-oscillator ones), poly/mono/legato, polyphony up to 32 with oldest-releasing-first stealing, glide, bend range, velocity sensitivity, gain, pan, seed. Text throughout; `compile()` turns names into numbers for the engines, `describe()` feeds bake keys.
- *Engine*: `synth/synth_core.gd` (`AKSynthCore`, GDScript) and `native/src/synth.{h,cpp}` (`ak::SynthEngine`) are the same steps in the same order with the same 32-bit xorshift RNG; tests find them bit-identical. Events are `[frame, type, a, b]` applied at their exact sample. Envelopes, oscillators and the filter run per sample; modulation per 8 samples (`CONTROL`), which took 32 voices from about 21% to about 5.5% of a core. GDScript is roughly 100× slower (fine for bakes of a few notes, which is its job).
- *Live* (`native/src/ak_synth.*`): `AKSynthStream` (AudioStream, `patch` property; re-compiles on the patch's `changed`), `note_on/note_off/set_bend/set_mod_wheel/set_aftertouch/all_notes_off/panic` with `delay_s`, `schedule(frame, …)`, `render_offline` for tests; `AKSynthPlayback` renders under the stream's mutex like the live mixer. `AKNative.synth_render` bakes.
- *Baking* (`synth/synth.gd`, `AKSynth`): `render_notes(patch, notes)`, `render_note`, `events_for`, `render_events(compiled, events, frames, sr, force_gdscript)`. Notes take names or numbers; ties put note-offs first.
- *Recipes*: the `patch` voice (`voices/patch.gd`; params `patch` as a resource or path, `freq_hz`, `velocity`, `gate_s`, `length_s`). The sequencer's `_note_hz` retunes it like any pitched voice. Bake keys now hash resources inside recipes by content (`AK._hashable`), and a voice can add content it loads by path (`AKVoice.key_extra`; the patch voice adds its patch), so editing a patch re-bakes. Plain recipes keep their old keys.
- *Voices as patches* (`synth/patch_lib.gd`, `AKPatchLib.from_voice`, `note_of`): `tone`, `wavetable`, `fm`. Measured against the voices: plain tone ≥ 100 dB SNR, vibrato ≥ 25 dB, wavetable and FM ≥ 25–30 dB (control rate; float32 rounding inside the voices); glide (curved in semitones, timed to agree halfway) and unison (random phases) compared by pitch, length and loudness. The voices are untouched.
- *Presets*: 12 in `addons/audio_kit/patches/` (`tools/make_patches.gd` writes them from `AKPatchLib.preset`; a test fails if a file goes stale). Levels trimmed so one note peaks near −6 dBFS.
- *Dock*: an `AKPatch` gets note buttons (C2–C5), Chord, Arpeggio, Glide, Stop, Save WAV, hold and velocity sliders, stats and a waveform; live through an `AKSynthStream` with the native core, baked otherwise. Checked in the running editor under Xvfb.
- *Not in phase 2*: patch-level effects (chorus etc. are phase 4), stereo unison spread, MIDI (phase 3), patch panels in the lab (phase 5). A voice stolen at full level stops at once (a click); a short steal fade is a candidate for phase 3, when keyboards make it common.

**Skill**: `skills/godot-audio-kit/SKILL.md`.

**Tests**: 133 headless (`tests/run_tests.gd`). Bridge tests run when the motion kit is linked; native and live tests run when the core is built; both pass trivially otherwise. `test_native.gd` compares every kernel, every voice and a full cue sheet between C++ and GDScript (within 1e-4 of peak); `test_live.gd` holds the live mixer to `render_cues` for the race ident and E1 with music, and checks seeks, one-shots, voice glides and releases, and mixing through the engine's playback; also every master effect live, ducked music, lane faders, the sequencer (play-through parity, loops, bar-quantised queueing, edits, seek), stingers (matching, parity, on a queued jump), recipe loops (seam, rate), intensity (curve, parity, live fades), engine layers (weights, live crossfade), the dock and step grid and WAV saving (`test_dock.gd`), Doppler (factor, pitch param, a pass-by at the expected shifts) and occlusion (a wall, the source's own body), the scene nodes (`test_live_nodes.gd`) and positional audio (`test_spatial.gd`). `test_sound_lab.gd`: generator determinism and sanity per category and seed (no silence, no clipping, length ranges, starts at once), the numeric listening check (pitch directions, lengths, brightness, tonality per category, and every pair of categories apart on at least one axis), mutate, random, the gate (one sound per category generated, baked to WAV and loaded back byte-identical to `AK.bake`), recipe streams (playback = baked samples, variants spread and cached, players 2D/3D, inside an AudioStreamRandomizer, saved and reloaded), stream and dock bakes, generated sounds native vs GDScript, and the lab screen end to end. `test_synth.gd`: compile, native = GDScript (bit for bit, rich patches and presets), determinism and seeds, the envelope against `AKEnv.adsr`, voices rebuilt as patches, polyphony and stealing, mono/legato/glide, bend and matrix effects (velocity brightens, LFO tremolo), live = bake (gate), the stream in a playback and live patch edits, 32-voice cost (gate), the patch voice in recipes (retuning, bake keys), presets fresh and sane, the dock playing a patch.

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

0. **Sound Lab (branch `sound-lab`, PR #1)**: phases 1 and 2 are built. Chris listens to the SFX generator (`tools/sfx_listen.gd` or the tab) and the patch presets (select one, play it from the dock), and reviews the PR's flagged decisions; then phase 3 of `docs/plans/sound-lab.md` (MIDI input, `.mid` import, starter bank, on-screen keyboard).

1. **Chris listens** to the E1 renders (effects only, and with music) and the race ident; translate notes with `AKVocab` or recipe edits.
2. **Chris tries LIVE**: build the core (or take the CI artifact), run `demo/live/live_demo.tscn` and the bridge demo with `mode = LIVE`. Check that Windows and macOS CI builds load in the editor (only Linux has been run here).
3. **Next**: Chris tries the dock and step grid in the editor on his machine (only seen under Xvfb here); a velocity lane or drag-to-paint in the grid; a reverb zone in the live demo (needs a moving listener).
4. ~~Point the motion kit skill's sound section at this kit~~ (done: the motion kit skill's section 6 now points here).
5. Nice to have: an editor dock to audition recipes and patterns; Print and Signal ports as further test beds.
