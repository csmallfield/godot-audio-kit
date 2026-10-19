# Godot Audio Kit

Procedural sound for Godot 4.5+: sounds written as recipes, baked deterministically to audio, placed exactly on the cues a [Godot Motion Kit](https://github.com/csmallfield/godot-motion-kit) composition fires, and checked by measurement rather than by ear.

No samples, no licences: everything is synthesised from code.

```gdscript
var hit := AK.bake(load("res://sfx/hit.tres"))          # AudioStreamWAV, cached
$Player.stream = hit

var sheet := AK.load_cue_sheet("res://cues/ident.json")  # from MotionComposition.export_cue_sheet()
var out := AK.render_cues(sheet.cues, load("res://sfx/ident_map.tres"), sheet.fps)
out.mix.save_wav("res://out/ident.wav")
```

## Status

Phases 0 (foundations), 1 (voices, palettes, motion kit bridge), 2 (music: tempo maps, patterns, songs) and 3 (native core and live mixer) are in place. See `docs/HANDOFF.md` for what's built, measured performance and the plan. For an LLM working with the kit: `skills/godot-audio-kit/SKILL.md`.

## Pieces

| Piece | What it is |
| --- | --- |
| `AKRecipe` | A sound as data: voice layers, effects, transforms, seed, and `bind` rules mapping a cue's intensity and data onto parameters |
| `AKVoice` | A synthesis voice with a documented parameter schema: `whoosh`, `tone`, `boing`, `click`, `pluck`, `mallet`, `ratchet`, `static`, `follow`, `fm`, `wavetable`, `kick`, `snare`, `clap`, `hat` |
| `AKTempoMap`, `AKPattern`, `AKSong` | Music: tempo and meter; step-string patterns with notes, degrees, chords, swing, polymeter and probability; songs of sections with automation, lane mixing, and notes emitted as cues |
| `AK` | Render and bake recipes, render cue sheets into a mix plus stems with a shared reverb send, effects and transforms |
| `AKCueMap` | Cue names to recipes (exact, `prefix*`, `*`, as in the motion kit's `MotionCuePlayer`), master effects, shared reverb |
| `AKCueBridge` | Scores a Motion Kit composition: bakes its cue sheet into one track locked to the picture, mixes the same timeline live, or plays cues as events. The motion kit stays optional |
| `AKLive` | The live mixer (native): cues scheduled at exact frames, game-event one-shots, continuous voices with gliding parameters, buses with faders and ducking, a play-time music sequencer, shared reverb and master chain |
| `AKLivePlayer`, `AKLiveVoice` | Scene nodes: a live mixer for game code (triggers, positional triggers, music sections, lane fades), and continuous voices (oscillators or recipe loops) whose parameters follow node properties and whose level and pan follow their position |
| `AKLiveLayers` | Several recipe loops crossfaded by one value (an engine across rpm, wind across speed) |
| `AKSpatial` | Distance attenuation, pan and air absorption from the 2D or 3D listener |
| Audio Kit dock | In the editor, under the inspector: play the selected recipe (once or looped, replaying as you edit, with length, peak, loudness and a waveform), song (live, sections, intensity), pattern (with a step grid to edit it while it plays) or cue map; save any of them as a WAV |
| `AKPalette` | Named values recipes reference as `"$name"`; shipped: supergraphic, print, signal |
| `AKVocab` | Words to parameter moves ("brighter", "drier", "punchier"...) from `vocabulary.json` |
| `AKDsp`, `AKOsc`, `AKNoise`, `AKEnv`, `AKFilter`, `AKDelay`, `AKShape`, `AKReverb`, `AKDynamics` | The DSP building blocks |

Voice parameters: `docs/voices.md` (generated from the code).

## Native core and live playback

The native core (`native/`, a C++ GDExtension) makes renders about 14× faster and adds a live mixer. It's optional: without it everything runs in GDScript and sounds the same. Build it with SCons (`native/README.md`) or take the `audio-kit-native` artifact from CI.

```gdscript
var live := AKLive.new()
live.prepare(sheet.cues, cue_map, sheet.fps, length_s, song)   # exact frames, no WAV bake
$Player.stream = live.stream
$Player.play()
live.trigger(&"go")                                          # a game event, into the same mix
var hum := live.voice_start({shape = "saw", freq_hz = 80.0, cutoff_hz = 400.0, send = 0.2})
live.voice_set(hum, "freq_hz", 120.0, 0.3)                   # glides while it plays
```

Music can also be sequenced as it plays, so it loops, changes section on the bar and takes edits mid-play:

```gdscript
live.song_play(song, &"loop", "intro")     # each note rendered just before it's due; call live.update() every frame
live.song_queue("drop", &"bar")            # on the next bar line
live.set_lane_gain(&"drums", -12.0, 1.0)   # lanes are buses with faders
```

Set `duck` on the cue map to sidechain the music under the effects (baked and live alike).

Songs can also fade lanes in and out with an intensity value (`AKSong.intensity_lanes`; live, `set_music_intensity(0.8)`), the usual vertical remix for games, and carry stingers (`AKSong.stingers`: a riser into the drop, a hit on any change), which play on section changes, baked and live alike.

In a scene, `AKLivePlayer` holds the mixer (`trigger_at(&"hit", position)` places a one-shot by distance and direction) and `AKLiveVoice` binds voice parameters to game state (`{param = "freq_hz", node = ^"../Car", property = "speed", from = [0, 60], to = [60, 240], curve = "exp"}`). An `AKLiveVoice` can loop a recipe instead of an oscillator (an engine, wind, a crowd: rendered once, made seamless, its `rate` bound to rpm), and with `spatial = "on"` its level, pan and brightness follow its parent's position, with optional Doppler and occlusion (a physics ray from the listener). `AKCueBridge.mode = LIVE` scores a motion kit composition live; `live_song` sequences its music as it plays.

Live and baked renders of the same timeline match to float rounding, master effects, ducking and play-time sequencing included. `demo/live/live_demo.tscn`: the E1 bed playing live with bar-quantised section changes and stingers, a mouse-driven drone, positional ducked one-shots, music intensity on Up/Down, and a car whose two-layer engine follows its speed and position.

## Review renders

One command renders a cue sheet and measures it: loudness (BS.1770), true peak, clipping, cue placement, perceived onsets, clutter, a clean ending, plus a spectrogram with cue markers and a strip of per-cue spectrograms.

```
godot --headless --path . -s res://addons/audio_kit/tools/review.gd -- \
    --cues demo/cues/race_ident.json --map res://demo/recipes/race_ident_map.tres \
    --out out/review/race_ident
```

Output in `out/review/race_ident/`: `mix.wav`, `stems/`, `report.md`, `report.json`, `spectrogram.png`, `cues.png`. The analysis needs Python 3 with numpy, scipy and matplotlib.

## Music

```
godot --headless --path . -s res://addons/audio_kit/tools/review.gd -- \
    --cues demo/cues/e1_supergraphic.json --map res://demo/recipes/supergraphic/e1_map.tres \
    --song res://demo/music/e1/e1_song.tres --out out/review/e1_full
```

`--song` alone renders the song by itself. The E1 bed (`demo/music/e1/make.py`) is a worked example: five instruments, three patterns, three sections that follow the picture.

## Comparing with a reference

```
python3 tools/compare/compare.py out/review/e1/mix.wav reference.wav demo/cues/e1_supergraphic.json out/compare/e1
```

Hit agreement per cue, band balance and side-by-side spectrograms. The E1 Supergraphic port (`demo/cues/e1_supergraphic.json`, `demo/recipes/supergraphic/`) is the worked example.

## Motion kit demos

`tools/link_motion_kit.sh` links a local motion kit checkout into `addons/motion_kit` (git-ignored) for the bridge tests and `demo/with_motion_kit/bridge_demo.tscn`.

## Tests

```
godot --headless --path . --script res://tests/run_tests.gd    # correctness, determinism
godot --headless --path . --script res://tests/perf.gd         # bake timings

Native tests compare the C++ path with GDScript and the live mixer with the bake; they skip when the core isn't built.
```

## Licence

Apache-2.0. See `LICENSE` and `NOTICE`.
