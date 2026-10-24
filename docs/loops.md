# Loops, samples and kits

A **loop** is a few bars of notes for one instrument: a synth patch, a sample played at pitch, or a drum kit with a row per piece. Loops compile to the kit's `AKPattern`, so they play anywhere patterns do: in songs, live through `AKLive`, in bakes and cue renders. This page covers the data (phase 6 of `docs/plans/loops-sequencer.md`); the Loops and Sequencer tabs that edit it come in phases 7 to 10.

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

Pitched sounds record the note they were made at as metadata `ak_root_note` (unpitched −1); `AKLibrary.sample_for(path, mode)` makes an AKSample rooted there:

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
- Choke groups act within a loop and a section, not across loops or section boundaries.
- Velocity changes only the level (no velocity low-pass yet).
- The OGG path relies on Godot's Vorbis playback; it is pinned by a test against a reference decode, so a Godot change that moved it would show.
- The library's sounds are the kit's synthesis: drum-machine and synth character, not acoustic recordings.
