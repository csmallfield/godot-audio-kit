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

Phases 0 (foundations), 1 (voices, palettes, motion kit bridge), 2 (music: tempo maps, patterns, songs) and 3 (native core and live mixer) are in place, and the first four phases of the Sound Lab (`docs/plans/sound-lab.md`): an editor tab that makes game sounds, a polyphonic synth engine whose patches play live and bake identically, MIDI (keyboards, `.mid` import with a General MIDI starter bank), and sound breadth (ladder filter, wavetables, sync, ring modulation, and effects that work the same in patches, bakes and Godot buses). See `docs/HANDOFF.md` for what's built, measured performance and the plan. For an LLM working with the kit: `skills/godot-audio-kit/SKILL.md`.

## Pieces

| Piece | What it is |
| --- | --- |
| `AKRecipe` | A sound as data: voice layers, effects, transforms, seed, and `bind` rules mapping a cue's intensity and data onto parameters |
| `AKVoice` | A synthesis voice with a documented parameter schema: `whoosh`, `tone`, `boing`, `click`, `pluck`, `mallet`, `ratchet`, `static`, `follow`, `fm`, `wavetable`, `reed`, `kick`, `snare`, `clap`, `hat`, and `patch` (plays an AKPatch) |
| `AKTempoMap`, `AKPattern`, `AKSong` | Music: tempo and meter; step-string patterns with notes, degrees, chords, swing, polymeter and probability; songs of sections with automation, lane mixing, and notes emitted as cues |
| `AK` | Render and bake recipes, render cue sheets into a mix plus stems with a shared reverb send, effects and transforms |
| `AKCueMap` | Cue names to recipes (exact, `prefix*`, `*`, as in the motion kit's `MotionCuePlayer`), master effects, shared reverb |
| `AKCueBridge` | Scores a Motion Kit composition: bakes its cue sheet into one track locked to the picture, mixes the same timeline live, or plays cues as events. The motion kit stays optional |
| `AKLive` | The live mixer (native): cues scheduled at exact frames, game-event one-shots, continuous voices with gliding parameters, buses with faders and ducking, a play-time music sequencer, shared reverb and master chain |
| `AKLivePlayer`, `AKLiveVoice` | Scene nodes: a live mixer for game code (triggers, positional triggers, music sections, lane fades), and continuous voices (oscillators or recipe loops) whose parameters follow node properties and whose level and pan follow their position |
| `AKLiveLayers` | Several recipe loops crossfaded by one value (an engine across rpm, wind across speed) |
| `AKSpatial` | Distance attenuation, pan and air absorption from the 2D or 3D listener |
| `AKReverbZone2D`, `AKReverbZone3D` | Areas with their own reverb: the live reverb glides to the zone the listener is in |
| Sound Lab | An editor main screen beside 2D, 3D and Script. **SFX**: generate game sounds by category (pickup, jump, laser, hit, explosion, power-up, UI click, confirm and cancel, blip) or at random, mutate them, edit the recipe in place, and bake a WAV or save the recipe into the project. **Synth**: play patches from an on-screen or MIDI keyboard while editing them, open `.mid` files and songs, re-voice their lanes, save them |
| `AKSfxGen` | The lab's generator in code: `generate(&"jump", 42)` always gives the same editable recipe; `mutate(recipe, seed)` a near neighbour |
| `AKRecipeStream` | A recipe as an `AudioStream`: plays in any AudioStreamPlayer (2D, 3D) or AudioStreamRandomizer, a new variant each play, rendered once and cached; "Bake to WAV" in the inspector |
| `AKPatch`, `AKSynthStream`, `AKSynth` | Synth patches (oscillators and wavetables with FM, sync and ring modulation, stereo unison, state-variable or ladder filter, three envelopes, two LFOs, a modulation matrix, poly/mono/legato, glide, effects), played live as an AudioStream or baked with the same engine; 17 presets in `addons/audio_kit/patches/`. Reference: `docs/synth.md` |
| Effects: `AKChorus`, `AKFlanger`, `AKPhaser`, `AKEQ3`, `AKCompressor`, `AKSaturate` | Chorus, flanger, phaser, three-band EQ, compressor and saturation: in a patch's `effects`, a recipe's `fx`, or on a Godot bus (Audio panel → Add Effect; native core), the same code in all three |
| `AKMidi`, `AKMidiRouter`, `AKBank` | `.mid` files into songs (tempo and meter maps, a lane per instrument, drums split by kind; .mid files import as songs in the editor), a router from MIDI keyboards to live patches, and a General MIDI starter bank of original patches. Reference: `docs/midi.md` |
| Audio Kit dock | In the editor, under the inspector: play the selected recipe or recipe stream (once or looped, replaying as you edit, with length, peak, loudness and a waveform), song (live, sections, intensity), pattern (with a step grid to edit hits and notes while it plays, undoable) or cue map; save any of them as a WAV |
| `AKPalette` | Named values recipes reference as `"$name"`; shipped: supergraphic, print, signal |
| `AKVocab` | Words to parameter moves ("brighter", "drier", "punchier"...) from `vocabulary.json` |
| `AKDsp`, `AKOsc`, `AKNoise`, `AKEnv`, `AKFilter`, `AKDelay`, `AKShape`, `AKReverb`, `AKDynamics` | The DSP building blocks |

Voice parameters: `docs/voices.md` (generated from the code).

## Sound Lab

Open the **Sound Lab** tab at the top of the editor. Press a category to hear a new sound of that kind; type a seed to get one back; Mutate to nudge it; edit any number in the inspector on the right and it replays. **Bake WAV** writes it into the project (default `res://audio/sfx/`) as an ordinary WAV that needs nothing from the kit to play; **Save recipe** keeps it as text to edit later; **Save stream** keeps it as an `AKRecipeStream`, an AudioStream that varies a little on each play.

```gdscript
var jump := AKSfxGen.generate(&"jump", 42)               # an ordinary AKRecipe, the same every time
$Player.stream = AKRecipeStream.of(jump)                 # plays anywhere a stream goes, varying per play
AK.bake_wav(jump, "res://audio/sfx/jump_42.wav")         # or bake it once and forget the kit
```

`tools/sfx_listen.gd` renders a few seeds of every category to WAVs and prints what they measure like (length, loudness, attack, brightness, tonality, pitch direction).

## Synth patches

```gdscript
var s := AKSynthStream.new()                                   # live (native core)
s.patch = load("res://addons/audio_kit/patches/fm_epiano.tres")
$Player.stream = s                                              # any player, any bus
$Player.play()
s.note_on(60, 0.8)
s.note_off(60, 0.4)                                             # 0.4 s from now, to the sample

var phrase := AKSynth.render_notes(s.patch, [{time_s = 0.0, note = "C4", length_s = 0.3},
	{time_s = 0.3, note = "E4", length_s = 0.3}])                 # the same samples, baked
```

A patch is text: oscillators (including wavetables, sync and ring modulation), a state-variable or ladder filter, envelopes, LFOs, a modulation matrix and effects (`docs/synth.md`). The effects (chorus, flanger, phaser, EQ, compressor, saturation) also go in a recipe's `fx`, and, with the native core, on Godot buses as `AKChorus`, `AKPhaser` and so on, sounding the same everywhere. Select one in the editor and play it from the Audio Kit dock. In a recipe, the `patch` voice plays one, so patches work in songs, cue maps and recipe streams too. `AKPatchLib.from_voice` rebuilds the `tone`, `wavetable` and `fm` voices as patches.

## MIDI

Drop a `.mid` file into the project and it imports as an `AKSong`, played by the General MIDI starter bank (one original synth patch per GM family, plus a drum kit from the kit's drum voices). Open it in Sound Lab → Synth to play it, swap any lane's patch, and save it as an editable song. A MIDI keyboard plays patches live through `AKMidiRouter` (notes, velocity, bend, mod wheel, sustain):

```gdscript
var song := AKMidi.import_file("res://music/tune.mid")      # or load("res://music/tune.mid")
var r := AKMidiRouter.new()
r.patch = load("res://addons/audio_kit/patches/fm_epiano.tres")
add_child(r)                                                  # listens to connected MIDI keyboards
```

See `docs/midi.md`.

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

## A whole song: Last Ferry

`demo/song/last_ferry/make.py` writes an original late-night ballad (F minor, 80 bpm, 2:48): a saxophone-like `reed` lead over FM electric piano, pad, bass and a drum machine with a gated snare; intro, verse, chorus, verse, chorus, a solo over new changes, a last chorus a semitone up, outro; crash and riser stingers. `demo/with_motion_kit/last_ferry_video.tscn` is its music video, made with the motion kit: a night harbour where the lead writes a glowing ribbon across the sky, windows answer the piano, the water pulses on the kick, a lighthouse flashes on the snare and a ferry crosses the bay. The picture reads the song's own notes (`AKSong.events()`), and an `AKCueBridge` bakes the soundtrack and locks the clock to it.

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
