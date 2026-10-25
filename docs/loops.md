# Loops, samples and kits

A **loop** is a few bars of notes for one instrument: a synth patch, a sample played at pitch, or a drum kit with a row per piece. Loops compile to the kit's `AKPattern`, so they play anywhere patterns do: in songs, live through `AKLive`, in bakes and cue renders. This page covers the data (phase 6 of `docs/plans/loops-sequencer.md`). The Sound Lab's **Loops** tab (phase 7) edits loops on a grid while they play, and the **Sequencer** (phase 8) arranges them as an `AKArrangement` (below): see `docs/sound_lab.md`. The mixer (phase 9) adds track effects, and games play arrangements through `AKLivePlayer` (phase 10, In games below).

```gdscript
var beat := AKLoop.new()
beat.kind = "percussive"
beat.instrument = AKLibrary.kit("punch")          # or load("res://addons/audio_kit/library/kits/punch.tres")
beat.bars = 1
beat.notes = [[0, 24, 0, 1.0], [96, 24, 1, 0.9], [192, 24, 0, 1.0], [288, 24, 1, 0.9]]   # kick, snare, kick, snare
for i in 8:
	beat.notes.append([i * 48, 24, 3, 0.7])       # closed hats on the 8ths

var song := AKSong.new()
song.tempo = AKTempoMap.new()
song.sections = [{name = "verse", bars = 4, patterns = [beat.to_pattern(16.0)]}]
var buf: AKBuffer = song.render().mix               # or AKLive.song_play(song)
```

## AKLoop

| Property | What it is |
| --- | --- |
| `kind` | `synth` (the instrument is an `AKPatch`), `sample` (an `AKSample`) or `percussive` (an `AKKit`) |
| `bars`, `beats_per_bar` | Length: 1 bar or more; 4 beats a bar by default |
| `division` | Cells a bar on the grid: 16, 32, 12 or 24. Only the view and the snap: it never moves or drops a note |
| `instrument` | The patch, sample or kit |
| `notes` | `[start tick, length ticks, row, velocity 0..1]`, in any order |
| `swing` | 0.5 straight; higher delays notes that start on an off-beat 16th (0.66 is a triplet shuffle) |
| `gain_db` | The loop's level |
| `category` | For the loop browser: beat, bass, chords, lead, fx ... |

**Ticks.** Notes are stored in ticks, 96 to a beat, so every division lands on whole ticks:

| Division (4/4) | One cell |
| --- | --- |
| 16 a bar (16ths) | 24 ticks |
| 32 a bar (32nds) | 12 ticks |
| 12 a bar (triplet 8ths) | 32 ticks |
| 24 a bar (triplet 16ths) | 16 ticks |

A note can sit off the current grid (written at 32nds, viewed at 16ths, or typed at tick 101): it still plays where it is. `cell_ticks()`, `snap(tick)` and `on_grid(note)` work at the loop's division or one you pass. Notes that start outside the loop (before 0, or at or past its length) are kept but don't play.

**Rows.** A synth or sample loop's row is a MIDI note (60 = middle C). A percussive loop's row is a piece of the kit: `instrument.pieces[row]`.

**`to_pattern(section_beats, lane)`** unrolls the notes over a section, repeating the loop to fill it (default: one pass), into `events` lanes of an `AKPattern`:

- Synth: one lane named `lane` (default: the loop's resource name, else its file name, else `loop`) with `patch = instrument`.
- Sample: one lane playing the sample through the `sample` voice.
- Percussive: one lane per piece in use, named `drums.<piece>`, as `.mid` drums import. A piece that isn't gated gets length 0 (it plays out; see Kits).

Swing is applied there, in beats; the stored ticks don't change.

`to_pattern(section_beats, lane, from_beats, at_beats, length_beats, drum_prefix)` can also place a window of the endlessly repeating loop (how arrangement clips play): the notes from `from_beats` into it, for `length_beats`, starting `at_beats` into the section, with drum lanes named `<drum_prefix>.<piece>`.

### From patterns and .mid files

Music that already exists becomes loops, its notes quantised to ticks:

```gdscript
var song := AKMidi.import_file("res://music/tune.mid")
var beat := AKLoop.from_song(song, ["drums.kick", "drums.snare", "drums.hat"], 0, 0.0, 2)   # section 0, two bars from its start
var bass := AKLoop.from_song(song, ["bass"], "verse", 4.0, 4)                               # four bars, from bar 5 of "verse"
var lead := AKLoop.from_pattern(load("res://music/p_race.tres"), ["lead"], 8)
```

- **Drum lanes** (unpitched) together become a percussive loop on a new kit made of their recipes, a piece per lane (named without the `drums.` prefix, with the lane's level).
- **One pitched lane** becomes a synth loop (a `patch` lane) or a sample loop (a recipe lane: the recipe as an `AKSample` rooted at its own pitch, gated).
- Step lanes and freely timed `events` lanes both work; velocities, lengths (gate) and swing come across as they play. `quantize` (cells a bar) snaps the starts; 0 keeps every tick.
- In the Loops tab: **From a song, pattern or .mid** (a path), **Load**, pick a lane ("drums (all)" for the whole kit) and a section, the number of bars, **Make loop**; the new loop opens unsaved.

### Scales and chords

The Loops tab's guides (`docs/sound_lab.md`) read the same data code can use. `AKNotes.SCALES` has 35 scales as semitone steps (the modes, harmonic and melodic minor and their modes, symmetric, pentatonic, blues, bebop and others); `AKNotes.scale_steps("ionian")` also takes other names. `AKChords.parse` reads chord symbols:

```gdscript
var c := AKChords.parse("Cm9")        # {ok, root = 0, tones = [0, 3, 7, 10, 14], pcs, bass = -1, ...}
AKChords.note_names(c)                # "C Eb G Bb D", spelt by interval from the root
AKChords.interval_name(c, 63)         # "b3"
AKChords.parse("D/F#").bass           # 6
```

Triads (m, dim, aug, sus2, sus4, 5), sevenths (7, maj7, m7, m(maj7), m7b5, dim7), upper extensions (6, 6/9, 9, 11, 13), alterations (b5, #5, b9, #9, #11, b13, alt), add and no tones, and slash basses; words (`C minor 9`, `B flat major 7`) work too. `tones` are semitones above the root: add `60 + root` to each to voice the chord from middle C up.

## AKArrangement

The Sequencer's document (`res://audio/arrangements/*.tres`): loops on tracks, as scenes and as a timeline, compiled to an `AKSong` by `to_song("scenes")` or `to_song("timeline")`.

```gdscript
tempo = AKTempoMap.make(120.0)
tracks = [{name = "drums"}, {name = "bass", gain_db = -2.0}, {name = "chords", send = 0.25, intensity = [0.2, 0.6]}]
scenes = [{name = "race", bars = 0.0, clips = {"drums": "res://audio/loops/beat_a.tres", "bass": "res://audio/loops/bass_a.tres"}}]
timeline = [{track = "drums", loop = "res://audio/loops/beat_a.tres", bar = 4.0, bars = 16.0, offset_bars = 0.0}]
markers = [{name = "intro", bar = 0.0}, {name = "race", bar = 4.0}]
```

| Property | What it is |
| --- | --- |
| `tempo` | Bpm, meter, tempo changes (an `AKTempoMap`) |
| `tracks` | `{name, gain_db, pan, send, mute, solo, intensity, fx, color}`; only `name` is needed |
| `scenes` | `{name, bars, clips}`: `clips` maps a track name to a loop (path or resource); `bars` 0 = the longest loop's |
| `timeline` | Clips `{track, loop, bar, bars, offset_bars}`: the loop plays from `offset_bars` into it, repeating, for `bars` |
| `markers` | `{name, bar}`: where the timeline's sections start |
| `length_bars` | The timeline's length; 0 = to the end of the last clip |
| `stingers`, `reverb`, `master_fx`, `intensity` | As on `AKSong` |

**Compiling.** Scenes: one section per scene, each loop repeating to fill it. Timeline: sections cut at the markers (before the first, "start"); each clip contributes the part of its loop that falls in the section, so a clip crossing a marker carries on in phase. A track plays one clip at a time: where clips overlap, the one that starts later plays and the earlier one resumes after it (`clip_spans`). Tracks become lanes named for the track (a synth or sample loop on "bass" is lane `bass`; a drum loop on "drums" is `drums.kick`, `drums.snare` ...). A track's `gain_db`, `pan` and `send` become the song's `mix` for its lanes, its `intensity` range `intensity_lanes`; muted tracks, and with any solo the others, are left out. A track's lanes form one group (`AKSong.lane_groups`) and its `fx` become the group's insert chain (`AKSong.group_fx`): see Track effects below. Compiled songs are cached by a hash of the arrangement and its loops (`key()`), so call `to_song` freely, but don't modify what it returns: copy it.

`painted(scene, from_bar, to_bar)` gives a new timeline with the scene's clips across that range (clips there on its tracks are trimmed or split), which the Sequencer's Paint uses.

```gdscript
var arr: AKArrangement = load("res://audio/arrangements/race.tres")
var live := AKLive.new()
live.prepare([], cue_map, 30.0, 0.0, arr.to_song("scenes"), true)
live.song_play(arr.to_song("scenes"), &"loop", "menu")
live.song_queue("race", &"bar")      # switches on the next bar, to the sample
var wav := arr.to_song("timeline").render().mix
```

### In games

`AKLivePlayer` plays an arrangement directly (native core):

```gdscript
$Music.arrangement = load("res://audio/arrangements/race.tres")
$Music.play_scene("menu")                # starts the scenes there; each loops until the next
# later, from game state:
$Music.play_scene("race", &"bar")        # switches on the next bar ("beat", "section" = the scene's end, "now")
$Music.set_music_intensity(0.8, 1.0)     # tracks with an intensity range fade in
$Music.play_timeline("intro")            # or the fixed piece, from a marker
```

- `play_scene` starts the scenes (`to_song("scenes")`) on the first call and queues a switch after that; `current_scene` and `arrangement_mode` say what's playing; `section_started` fires when a scene starts sounding. With `autoplay_song`, the player starts on `autoplay_scene` (or the first scene; "timeline" plays the timeline).
- While an arrangement plays, its `reverb` and `master_fx` are the mixer's; the player's `cue_map` still gives `trigger()` its sounds and the ducking.
- `audio_output = false` keeps the player silent while code pulls the stream (`live.render_playing`), as the tests do.
- A stinger with a lead-in (a negative `offset_s`, like a riser) can only play whole when the switch is known that far ahead; a game's switch is known at most a bar ahead, so give game scenes stingers that land on the downbeat (a crash), and keep risers for the timeline.
- `AKCueBridge.arrangement` scores a motion kit composition with the arrangement's timeline (it takes over from `song`), baked or LIVE; `AK.render_cues(..., arrangement)` and `AK.track_key` take one too (`AK.as_song`).

The racing demo is all of this in one scene: `demo/racing/race_demo.tscn` (see `demo/racing/README.md`).

### Track effects

`tracks = [{name = "drums", fx = [{type = "compressor", threshold_db = -24.0, ratio = 6.0}, {type = "eq", high_db = 3.0}]}]`

A track's `fx` is an insert chain of the six streaming effects (chorus, flanger, phaser, eq, compressor, saturate; the specs of a patch's `effects`, `docs/synth.md`). It runs on the track's lanes mixed together:

```
notes (level, pan, intensity fade) -> track sum -> inserts -> + shared reverb return -> master chain
                                   \-> reverb send (before the inserts)
```

- **Baked** (`AKSong.render`): the group's lanes are summed from song time 0 and run through `AKStreamFx` over the whole song plus a settling tail (`AKSong.INSERT_TAIL_S`, 1 s, or a delay's longer tail), so filters and compressors finish moving; the stem is `music.<track>`.
- **Live** (`AKLive`): the track's lanes share one bus (`lane_bus` follows `lane_groups`), whose insert chain (`AKLiveStream.set_bus_fx`, `ak::Fx`) runs after the bus fader (where intensity fades happen, as the bake's note levels) and before ducking. Chains restart clean when a song starts playing, so they line up with a bake; an edit restarts only the chains that changed.
- The two agree to float rounding: each effect measured live against its bake at about 141 dB SNR (`tests/test_mixer.gd`).
- Cost: 10 tracks with two effects each take about 7% of a core on the test VM (the gate is 10%).
- `AKLive.levels()` gives each track's (and the master's) peak of the last block for meters.

## AKSample

One sound to play at pitch: the instrument of a sample loop, a piece of a kit, or the `sample` voice in any recipe.

| Property | What it is |
| --- | --- |
| `source` | A `.wav` or `.ogg` in the project, or a recipe `.tres` path |
| `recipe` | A recipe to render as the sample (wins over `source`). Rendered once and cached by its bake key |
| `root_note` | The MIDI note it was made at: playing that note plays it as made |
| `start_s`, `end_s` | Trim (end 0 = the sound's end) |
| `mode` | `oneshot` plays to its end whatever the note's length; `gate` stops at the note's end with a `release_s` fade; `loop` repeats `loop_start_s`..`loop_end_s` while the note is held, then releases |
| `loop_start_s`, `loop_end_s` | The loop, in seconds of the trimmed sound (end 0 = the trimmed end) |
| `release_s` | Fade after the note ends (gate and loop), a time constant |
| `gain_db`, `reverse` | Level; play the trimmed sound backwards |
| `data`, `data_rate` | A file source's decoded mono samples, saved with the resource |

```gdscript
var s := AKSample.new()
s.source = "res://audio/samples/marimba_c4.wav"
s.import_source(true)      # decode into data; true also takes a WAV smpl chunk's root note and loop
s.mode = "gate"
ResourceSaver.save(s, "res://audio/samples/marimba_c4.sample.tres")
```

**How it plays.** The `sample` voice resamples by `2^((note - root_note) / 12)` (times the file's rate over 48 kHz) with 4-point Hermite interpolation, the same interpolation `AKLive` loops use. At the root note a sample made at 48 kHz plays back sample for sample. Velocity scales the level. Samples are mono: a stereo file is the mean of its channels, and the recipe or lane pans it. The voice is in GDScript (`AKSampler.play`) and in the native core (`AKNative.sample_play`), the same steps in doubles, so both give the same bits.

**In exported games.** Godot imports project audio into streams that can't be read back sample by sample (and often compresses them), and exports don't carry the source files. So a file source is decoded in the editor into `data`, which is saved in the `.tres` and is what plays. Recipe sources store nothing: recipes render anywhere, natively or in GDScript. Anything baked is a plain WAV, as before.

**Bake keys** hash the sample's settings and its sound (a recipe's bake key, or a hash of the data), so editing either re-bakes.

### Reading audio files

`AKAudioFile.read(path)` gives `data` (mono floats), `rate`, `channels`, `bits`, `error` ("" when it read), and from a WAV `smpl` chunk `root_note` and `loop`.

| Format | How |
| --- | --- |
| WAV | The kit's own reader: PCM at 8, 16, 24 or 32 bits; 32- or 64-bit float; WAVE_FORMAT_EXTENSIBLE; any channel count and rate. Compressed WAVs (ADPCM and the like) are refused with a message |
| OGG Vorbis | Godot's own decoder: `AudioStreamOggVorbis.load_from_file`, pulled through its playback at exactly one source sample per output sample. Measured at 136 dB SNR against a reference decode (`tests/loops/`); the playback's first 2 frames (its interpolator's history) are dropped |
| Anything else | Not read; convert to WAV or OGG |

## The `sample` voice

```gdscript
{voice = &"sample", params = {sample = "res://audio/samples/marimba_c4.sample.tres", freq_hz = 392.0, gate_s = 0.3}}
```

| Parameter | Default | What it does |
| --- | --- | --- |
| `sample` | "" | The AKSample or its path; empty plays a soft mallet at C4 |
| `freq_hz` | 261.63 | Pitch to play (the sample's root pitch plays it as made; the sequencer retunes it) |
| `velocity` | 1 | Level |
| `gate_s` | 0.3 | How long the note is held (gate and loop modes) |
| `length_s` | 0 | Total length; 0 = to the sample's end (one-shot) or the gate plus five release times |

`sample.to_recipe(semitones, gain_db, pan)` makes such a recipe at the sample's root, with velocity bound to intensity; loops and kits use it.

## AKKit

The instrument of a percussive loop: `pieces`, one per row.

```gdscript
pieces = [
	{name = "kick", sound = "res://addons/audio_kit/library/kicks/kick_punch.tres", gain_db = -1.0},
	{name = "closed_hat", sound = "res://addons/audio_kit/library/hats/hat_closed_tight.tres", gain_db = -9.0, pan = 0.15, choke = "hats"},
	{name = "open_hat", sound = "res://addons/audio_kit/library/hats/hat_open_short.tres", gain_db = -10.0, pan = 0.15, choke = "hats"},
]
```

| Key | What it does |
| --- | --- |
| `name` | The row's name, and the lane `drums.<name>` |
| `sound` | An AKSample, an AKRecipe, or a path to either; recipes are wrapped in a sample (rendered once) |
| `gain_db`, `pan` | Level and balance in the kit |
| `tune_semitones` | Retune the piece (by resampling) |
| `choke` | A group name. A hit cuts every piece of its group still ringing, itself included: a closed hat stops an open one, and an open hat hit again restarts. "" = no group |
| `gate` | true: the piece stops at the note's end, with its sample's release (a held open hat). false (default): it plays out, the usual drum behaviour, and the note's length is ignored |

**Choke groups, exactly.** When the loop is unrolled, each hit of a grouped piece gets the time to the next hit (strictly later) of any piece in its group in the same section, written as a fifth value on the pattern event (`[beat, length, midi, velocity, cut_beats]`). The sequencer turns it into seconds through the tempo map and renders the note with the `_cut_s` override: `AK.cut` fades the sound over 3 ms (`AK.CHOKE_FADE_S`) into the cut and stops it there. Baked and live playback render notes through the same overrides, so they cut identically. Hits at the same instant don't cut each other, and nothing cuts across a section boundary: the last open hat of a section rings into the next.

## The kit-made library

`addons/audio_kit/library/` holds 128 one-shots made from the kit's own voices, shipped as recipes (text, original, Apache-2.0; nothing binary). Each is rendered on demand and cached by its bake key, so it behaves like a sample. Every sound ends with a DC block and a peak normalise to −3 dBFS, so sounds of one kind sit at one level; kits balance them with each piece's `gain_db`.

| Folder | Sounds |
| --- | --- |
| `kicks` (14) | round, punch, sub, boom_long, 909, tight, click, dusty, room, distorted, soft, deep, electro, thump |
| `snares` (12) | tight, fat, crack, 808, 909, room, dusty, brush, rimshot, electro, soft, long |
| `claps` (8) | classic, tight, wide, 808, room, dusty, snap, crowd |
| `hats` (14) | closed (plain, tight, soft, 808, dusty), open (plain, short, 808, dusty), pedal (plain, 808), room, open room, noise |
| `cymbals` (8) | crash (plain, bright, dark), ride (plain, dry), ride bell, splash, china |
| `toms` (9) | low, mid, high; each plain, electro (a longer pitch drop, driven) and room |
| `perc` (16) | rim, rim dry, cowbell, cowbell 808, clave, wood block high and low, conga high and low, bongo high and low, shaker, shaker long, tambourine, triangle, snap |
| `bass` (12, root C2) | sub, 808, saw, square, reese, fm, fm growl, pluck, acid, wood, soft, pulse |
| `keys` (12, root C4; glass and music box C5) | pluck bright and soft, harp, marimba, vibes, glass, kalimba, music box, epiano, fm bell, steel drum, organ hit |
| `pads` (8) | warm, bright, hollow (root C3), glass (C4), drone low (C2); textures air, vinyl, wind (unpitched) |
| `fx` (9) | riser, riser tone, downlifter, impact, zap, noise sweep, reverse crash, tape stop, glitch |
| `vox` (6, root A3) | formant hits: ah, eh, ee, oh, oo, hey |

Pitched sounds record the note they were made at as metadata `ak_root_note` (unpitched −1); `AKLibrary.sample_for(path, mode)` makes an AKSample rooted there, 3 dB down (`PITCHED_TRIM_DB`), so one note peaks near −6 dBFS as a preset patch does and chords have room:

```gdscript
var keys := AKLoop.new()
keys.kind = "sample"
keys.instrument = AKLibrary.sample_for("res://addons/audio_kit/library/keys/epiano.tres")
keys.notes = [[0, 192, 57, 0.6], [0, 192, 60, 0.6], [0, 192, 64, 0.6]]   # an A minor chord, two beats
```

### Default kits

`addons/audio_kit/library/kits/`: five `AKKit`s of 13 pieces each, in this row order: kick, snare, clap, closed_hat, open_hat, pedal_hat (the three hats choke each other, group `hats`), tom_low, tom_mid, tom_high, crash, ride, and two percussion pieces.

| Kit | Character | Its percussion |
| --- | --- | --- |
| `boom` | Long 808-style kick and snare, 808 hats | cowbell 808, rim |
| `punch` | Tight and dry | rim, shaker |
| `room` | Everything in a small room | rim, tambourine |
| `lo-fi` | Dusty: low-passed and bit-crushed | rim, shaker |
| `electro` | Bright 909-style, driven toms | cowbell 808, clave |

`tools/make_library.gd` writes the library and the kits from `AKLibrary` (as `make_patches.gd` and `make_bank.gd` do), and a test fails if a file goes stale. To change a sound, edit `loops/library.gd` and run the tool, or copy a recipe into your project and edit it there. `tools/loops_listen.gd` renders the same beat on every kit (and a bass and keys sample loop on `boom`) to `out/loops/`; `--sounds` adds every library sound.

## Limits

- Samples are mono; stereo files are folded to mono when read.
- Notes don't carry across notes: each note is its own cached render (as for songs since phase 3), so a synth loop's glide or legato between notes doesn't carry.
- Choke groups act within a loop and a section (an arrangement clip's stretch of a section), not across loops or section boundaries.
- Velocity changes only the level (no velocity low-pass yet).
- The OGG path relies on Godot's Vorbis playback; it is pinned by a test against a reference decode, so a Godot change that moved it would show.
- The library's sounds are the kit's synthesis: drum-machine and synth character, not acoustic recordings.
