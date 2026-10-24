# Loops and Sequencer tabs: plan

The live, commentable version of this plan, with its diagrams, is the doc "Audio Kit: Loops and Sequencer tabs" (https://claude.ai/artifact/6fXPfohHSYZmHXvFRG7Kmm). This file is the in-repo copy that work on the `sound-lab` branch follows; if the two disagree, ask. It continues `docs/plans/sound-lab.md` (phases 1-5, built).

## Goal and principles

Two new Sound Lab tabs turn the kit into a small loop-based music tool, in the spirit of Auxy: **Loops** to write short patterns on a grid, and **Sequencer** to arrange them on tracks, as a timeline and as scenes a game can switch between. They sit beside SFX and Synth on the `sound-lab` branch and build on what's there; they don't replace the step grid, songs or `.mid` import.

- **One instrument per loop.** A loop is a synth loop (a patch), a sample loop (one sample, played at pitch) or a percussive loop (one drum kit, a row per piece).
- **Loops compile to what exists.** A loop becomes an `AKPattern`, an arrangement becomes an `AKSong`. Baking, live play, `AKLive` section queueing, intensity, stingers and cue export all work unchanged.
- **Live and baked stay one.** Track effects run the same code (`ak::Fx` / `AKStreamFx`) on a live lane bus and on a baked stem, so what you hear arranging is what bakes.
- **Everything stays text.** Loops, kits and arrangements are readable `.tres`, so people and an LLM can author, diff and review them.
- **Not a DAW.** No audio recording, no plugin hosting, no free-time audio clips. Grids, loops, tracks, scenes and a timeline in bars.

## Decisions

| Question | Decision | What it means |
| --- | --- | --- |
| What a percussive loop's rows are | A drum kit, one per loop | Rows are the kit's pieces (kick, snare, hats, toms...), as in Auxy's drum loops. The kit is the loop's one instrument |
| Default sample library | Kit-made samples | One-shots synthesized by the kit, shipped as recipes and rendered on demand: original, Apache-2.0, nothing binary to license. The project's own audio files sit beside them |
| How the Sequencer arranges | Timeline and scenes | A multitrack timeline in bars for a fixed piece, and scenes (one loop per track) that a game launches and switches between on the beat or bar |
| Where notes are stored | In ticks, 96 per beat | The grid's division (16, 32, 12 or 24 a bar) is only a view and a snap. Changing it never moves or loses a note |
| Where effects go | Instrument effects in the patch or sample; track effects on the track | Track effects are an insert chain on the track's bus, continuous across notes and clips, live and baked alike |
| Where loops are saved | `res://audio/loops/`, arrangements in `res://audio/arrangements/` | Plain resources in the project, next to the lab's patches and songs |

### What exists and what it becomes

| Today | With Loops and Sequencer |
| --- | --- |
| `AKPattern` lanes with `events` (\[beat, length, midi, velocity\]) | What a loop compiles to: one lane, its instrument, its notes unrolled to the section's length |
| `AKSong` sections, `intensity_lanes`, `stingers`, `mix` | What an arrangement compiles to: timeline markers or scenes become sections, tracks become lanes |
| `AKLive` song sequencer: lane buses, `song_queue` on the bar, `set_music_intensity` | Plays arrangements live; lane buses gain an insert effect chain |
| Patches and presets, the preset browser | The instruments of synth loops; the browser picks them |
| Drum voices (`kick`, `snare`, `hat`, `clap`) and the GM drum lanes | The pieces of the default kits |
| SFX generator and recipes | Sources for the sample library (any recipe can be a sample) |
| Step grid in the dock | Stays as the quick editor for hand-written patterns |

## Data model

Four new resources hold the music; each compiles to the kit's existing `AKPattern` and `AKSong`, so nothing below the editor changes how sound is made.

```
Editors                 Resources (text)                 Compiled          Sound
Library browser  ---->  AKSample, AKKit    AKPatch
                              \ instrument  /
Loops tab        ---->  AKLoop  --------- to_pattern() -->  AKPattern
                          ^ clips                              | sections
Sequencer tab    ---->  AKArrangement --- to_song() ----->  AKSong  --> AKLive (buses + inserts)
                                                                     --> Bake (WAV, stems)
```

**`AKLoop`** (`res://audio/loops/*.tres`): one instrument and its notes.

```gdscript
kind = "synth"            # synth | sample | percussive
bars = 2                  # 1 or more
beats_per_bar = 4
division = 16             # 16 | 32 | 12 | 24 per bar: the grid shown and the snap
instrument = "res://audio/patches/neon_bass.tres"   # an AKPatch, an AKSample or an AKKit
notes = [[0, 24, 45, 0.9], [48, 24, 57, 0.7]]       # [start tick, length ticks, row, velocity]
swing = 0.5
gain_db = 0.0
category = "bass"         # for the loop browser
```

- A row is a MIDI note for synth and sample loops, and a piece index for percussive ones (`kit.pieces[row]`).
- Ticks are 96 to a beat, so every division lands on whole ticks (a 16th = 24, a 32nd = 12, a triplet 8th = 32, a triplet 16th = 16). Notes off the current grid still play and show where they are.
- `to_pattern(section_beats)` unrolls the notes across a section into one `events` lane playing the instrument. For percussive loops, one lane per piece in use (`drums.kick`, `drums.snare`...), which is how `.mid` drums already import.

**`AKSample`**: one sound to play at pitch. Its `source` is an audio file in the project (`.wav`, `.ogg`) or a recipe (rendered once, cached by its bake key). Plus `root_note` (the pitch it was made at), `start_s` / `end_s` (trim), `mode` (`oneshot`: plays to its end; `gate`: stops on note-off with `release_s`; `loop`: loops between `loop_start_s` and `loop_end_s` while held), `gain_db`, `reverse`. A new `sample` voice plays it: resampled by `2^((note - root_note) / 12)`, so a sample is also a valid recipe voice everywhere else in the kit.

**`AKKit`**: a drum kit, the instrument of a percussive loop. `pieces = [{name = "kick", sound = <AKSample or recipe>, gain_db, pan, tune_semitones, choke = "hats"}]`. A choke group cuts a ringing piece when another in the group plays (an open hat stopped by the closed hat). Default kits are built from the kit's drum voices and the sample library.

**`AKArrangement`** (`res://audio/arrangements/*.tres`): the Sequencer's document.

```gdscript
tempo = AKTempoMap        # bpm, meter, tempo changes
tracks = [{name = "drums", gain_db = 0.0, pan = 0.0, send = 0.1, mute = false, solo = false,
           fx = [{type = "compressor", ...}], intensity = [0.0, 1.0]}]
scenes = [{name = "race", bars = 4, clips = {"drums": "res://audio/loops/beat_a.tres", "bass": ...}}]
timeline = [{track = "drums", loop = "res://audio/loops/beat_a.tres", bar = 8.0, bars = 16.0, offset_bars = 0.0}]
markers = [{name = "intro", bar = 0.0}, {name = "race", bar = 8.0}]
stingers = [...]          # as AKSong
reverb = {...}; master_fx = [...]
```

- A clip plays its loop from `offset_bars`, repeating, for `bars`. One clip per track sounds at a time.
- `to_song(mode)`: `"timeline"` cuts the timeline at its markers into sections, unrolling each clip into the section's events (so a clip that crosses a marker carries on in phase); `"scenes"` makes one section per scene, each the length of its longest loop. Tracks become lanes; a track's `intensity` becomes `intensity_lanes`; its gain, pan and send become the song's `mix`; its `fx` become the lane's insert chain.
- The compiled song is cached by a hash of the arrangement and its loops, as bakes already are.

## Loops tab

The Loops tab is a grid editor for one loop at a time: rows are notes or drum pieces, columns are steps, and it plays in a loop while you edit.

```
[bass_a] [New] [Type: synth] [Patch: neon_bass] [Bars: 2] [Division: 16] [Scale: A minor] [Play] [Save]
+-----------------+ +--+----------------------------------------------------------+
| Loops           | |  | Bar 1                 ¦playhead      Bar 2               |
| [search]        | |G3|           ===                                            |
| beat_a · perc   | |  |     =====                   =====                        |
| bass_a · synth  | |  |        ==¦==                         =====               |
| chords_a        | |A2|==  ==                  ==  ==                            |
| ...             | |  +----------------------------------------------------------+
+-----------------+ |Velocity  | | |   |  |   | |  |  |                          |
```

**Toolbar** (left to right): loop name; **New** (asks synth, sample or percussive); **Type**; **Instrument**, which lists patches for a synth loop, samples for a sample loop and kits for a percussive loop, with a button to open the instrument in the Synth tab or the sample library; **Bars** (1, 2, 4, 8, or typed); **Division** (16, 32, 12, 24 per bar); **Swing**; **Scale** and **Root** (highlight and, optionally, fold the rows to the scale); **Play / Stop**, **Tempo** (the arrangement's, or the lab's own when no arrangement is open); **Save**.

**Rows.** Synth and sample loops show a piano column (a click auditions the note) over a range that follows the notes, with octave shift; **Fold** hides rows outside the scale. Percussive loops show one row per kit piece, named, in the kit's order, with a mute per row.

**The grid.** Bars are separated by strong lines and beats by lighter ones; triplet divisions draw three cells a beat-pair. Then:

- Click an empty cell: a note one step long at the default velocity. Drag right from it: longer. Click a note: delete it.
- Drag a note's body to move it (time and row); drag its right edge to resize; Shift snaps off the grid to the next finer division.
- Box-select with right-drag; then arrow keys move by a step or a semitone, Ctrl+D duplicates, Delete removes.
- Percussive rows ignore length unless the piece is gated (a held open hat); a hit is a cell.
- **Velocity strip** under the grid: a bar per note, dragged up or down. Accent tools: a ramp across a selection, or randomise by an amount.
- Every edit is undoable and joins the editor's history, as the patch panels do.

**Playing.** The loop plays live through `AKLive` (native core), and edits reach the next pass of the loop, so you hear changes without stopping. The playhead sweeps the grid. Without the native core, Play renders the loop and plays the bake. A **Context** toggle plays the rest of the open scene with it, so a bass line is written against the drums.

**Loop browser** (left column): the project's loops by kind and category, with search, like the preset browser. Click to open, double-click to audition, drag into the Sequencer.

**From elsewhere:** **Duplicate**, **Transpose**, **Double** (two bars become four, notes copied), **Halve**. A pattern lane or a `.mid` track can be turned into a loop (its notes quantised to ticks), so imported music becomes editable loops.

## Sequencer tab

The Sequencer arranges loops on tracks in two linked views, **Scenes** and **Timeline**, over one mixer; both compile to the same `AKSong`, so either plays live or bakes.

```
race_music   Play Stop Loop   128 bpm 4/4   Bar 9.1                    Bake Stems Song
Tracks   M S FX | Scenes: menu  race>  final_lap | Timeline: intro   race          final_lap
drums           |         -     beat_a  beat_b   |                  [=====================]
bass            |         -     bass_a  bass_a   |              [=========================]
chords          |   chords_a  chords_a chords_b  |  [=================================]
lead            |         -     hook    hook_hi  |                  [=======]       [======]
fx              |         -      -      riser    |                 |               |
Master: eq, limiter · shared reverb · track inserts (drums compressor, chords chorus ...)
```

**Tracks** run down the left: name, colour, mute, solo, level, pan, reverb send, an **FX** button for the track's insert chain, and an **Intensity** range (the track fades in between its low and high values when a game sets music intensity). Add, rename, reorder, delete. A track plays one clip at a time; any loop can go on any track, since each loop carries its own instrument.

**Scenes view** (a grid, as in Auxy or a clip launcher): a column per scene, a cell per track. Drop or pick a loop into a cell. Click a scene to launch it; the switch lands on the next bar (or beat, or the end of the scene, from a menu), exactly as `AKLive.song_queue` does for games. Each scene has a name and a length (its longest loop, or set). Scenes are what a game switches between: "menu", "race", "final\_lap".

**Timeline view**: bars across, tracks down. Drag a loop from the browser or a cell from the scenes view onto a track; a clip repeats its loop to fill its length. Drag a clip's body to move it, its right edge to lengthen it (more repeats), its left edge to start part-way in. Snap to the bar, the beat, or off. Alt-drag copies. **Markers** name sections (intro, verse, race) on a strip above the bars. **Paint scene** writes a scene's clips across a bar range in one go, so a sketch made in scenes becomes a timeline quickly.

**Transport**: play, stop, loop a bar range, tempo and meter (with tempo changes on the marker strip), a playhead that follows, a bar and beat readout. Double-click a clip to edit its loop in the Loops tab with the arrangement playing around it.

**Mixer**: a row of strips (or the track headers, widened): level meter, fader, pan, send, the insert chain (any of chorus, flanger, phaser, eq, compressor, saturate, in order, edited with the same effect panels as patches), mute and solo; a master strip with the song's `master_fx` and the shared reverb's settings.

**Export**: **Bake** the timeline or one scene to a WAV; **Stems** writes a WAV per track; **Save as song** writes the compiled `AKSong` (for projects that want only the old format); **Cue sheet** exports note and section cues for the motion kit.

## Sound library

The sample library lists two kinds of sound side by side: the project's own audio files, and a default library of kit-made one-shots that ship as recipes, not WAVs.

| Source | Where | What it holds |
| --- | --- | --- |
| Kit library | `addons/audio_kit/library/` | About 120 recipes in folders: kicks, snares, claps, hats and cymbals, toms, percussion, bass one-shots, plucks and keys, pads and textures, hits and risers, vocal-like formant hits; plus default kits (`boom`, `punch`, `room`, `lo-fi`, `electro`) made from them. Each recipe is rendered once and cached by its bake key, so it behaves like a sample |
| Project audio | Any folder the user picks, `res://audio/` by default | `.wav` and `.ogg` files, read by the editor; `AKSample` resources wrapping them (root note, trim, mode, loop points) |
| Recipes and SFX | Anywhere in the project | Any recipe can be dropped in as a sample, including SFX-tab results |

**The library browser** (shared by the Loops tab's instrument picker and the kit editor): folders and categories, search, a waveform preview, click to audition. Choosing a file for a sample loop makes an `AKSample` beside it (`kick_01.wav` → `kick_01.sample.tres`) holding its root note and trim, so the WAV itself stays untouched. Root note: typed, or detected (the kit's harmonic pitch test from the MIDI gate) with a confirm.

**Kits** are edited in a small panel: a row per piece (name, sound picked from the library, level, pan, tune, choke group, gate). A new kit starts from a default one.

**How a sample plays**: resampled with 4-point interpolation (as `AKLive` loops already are) by the note's distance from the root; one-shot, gated with a release, or looped while held; velocity scales level and, optionally, a low-pass. Samples longer than their note in percussive loops ring on unless choked.

**In exported games**: samples a live arrangement needs are packed as decoded float data (`AKSample.data`, saved with the resource), so playback doesn't depend on Godot's import compression. Anything baked is a plain WAV, as before.

## In games

An arrangement plays in a game the way songs already do, through `AKLive` (native core), with scenes as the sections a game switches between; without the native core it bakes.

```gdscript
var music: AKArrangement = load("res://audio/arrangements/race.tres")
$AKLivePlayer.arrangement = music          # compiles to a song, scenes as sections
$AKLivePlayer.play_scene("menu")
# later, from game state:
$AKLivePlayer.play_scene("race", &"bar")    # switches on the next bar, in time
$AKLivePlayer.set_music_intensity(0.8, 1.0) # tracks fade in by their intensity ranges
$AKLivePlayer.play_timeline("intro")       # or the fixed piece from a marker
```

- `AKLivePlayer` and `AKCueBridge` accept an `AKArrangement` where they take an `AKSong` today; it compiles (cached) and plays through the existing sequencer, so queueing, intensity, stingers, ducking under effects and reverb zones keep working.
- A scene loops until the next `play_scene`; `stingers` mark a scene change as they mark a section change today.
- **Baked**: `AK.render_cues(..., arrangement)` or **Bake** in the Sequencer writes a WAV of the timeline or a scene; a motion-kit composition can carry a timeline as its soundtrack, as songs do now.
- **Live = bake**: the gate tests hold a live scene and a timeline to their bakes, as phases 2 and 4 did, including track insert effects (the same `ak::Fx` code on the lane bus and on the baked stem).
- **Cost**: the live sequencer renders each note a lookahead before it sounds and caches it; samples are cheap, synth notes cost what they do today. Track insert effects run per track bus; budget about 10 tracks with two effects each well under 10% of a core, measured in a test.

## Phases

Five phases on the `sound-lab` branch (PR #1 grows), numbered on from the Sound Lab's five; each ends at a gate checked by a test, as before. Loops come before the Sequencer because a loop is useful on its own.

6. **Loop data and samples**
   - `AKLoop` (ticks, divisions, kinds), `to_pattern()`; `AKSample` and the `sample` voice (native and GDScript, bit-identical); `AKKit` with choke groups.
   - The kit-made library (recipes in folders) and five default kits.
   - *Gate: a loop of each kind compiles to the expected events; changing division keeps every note; a sample plays at the written pitch (harmonic pitch test); live = bake for a sample loop.*
   - Status: built on `sound-lab` (PR #1): the gate is met in `tests/test_loops.gd` (16/16 sample notes at the written pitch; sample and drum loops live vs baked at 107 dB; choke groups cut as specified). Audio files: WAV through the kit's own reader, OGG through Godot 4.5's Vorbis decoder (136 dB against a reference decode), so both are supported. The library has 128 sounds and the five kits. Reference: `docs/loops.md`.
7. **Loops tab**
   - The grid editor (piano and kit rows, notes with length and velocity, selection, undo), the toolbar, the loop and library browsers, live looping with edits heard on the next pass, Context play.
   - *Gate: a two-bar beat, a bass line and a chord loop built from New through the tab's own controls, saved and reloaded field for field, and measured (as phase 5's gate).*
   - Status: built on `sound-lab` (PR #1): the gate is met in `tests/test_loops_tab.gd` (the three loops built by simulated clicks, drags and menu picks, reloaded note for note and measured; the beat live vs baked ≥ 90 dB; an edit mid-pass heard exactly on the next pass). Context plays loops picked in the browser until scenes exist (phase 8); the tempo is the tab's own until arrangements exist. Guide: `docs/sound_lab.md`.
8. **Sequencer: scenes and timeline**
   - `AKArrangement`, `to_song()` for scenes and timeline; tracks, the scenes grid with launching on the bar, the timeline with clips, markers and paint scene; transport; bake and stems.
   - *Gate: an arrangement of a minute built from loops in the tab; scene and timeline playback live = bake; a scene switch lands on the bar to the sample.*
   - Status: built on `sound-lab` (PR #1): the gate is met in `tests/test_sequencer.gd` (a 60 s arrangement made through the tab's controls; the timeline live vs baked at 350.7 dB over the minute; a scene launched mid-bar starts on the next bar to the frame and matches a bake at 347.4 dB). Overlapping clips on a track: the later-starting one plays and the earlier resumes in phase after. Loops are placed by picking in the list and clicking (no drag and drop yet). Guide: `docs/sound_lab.md`; reference: `docs/loops.md`.
9. **Mixer and track effects**
   - Per-track level, pan, send, mute, solo, intensity range; insert chains on `AKLive` lane buses (native) and on baked stems (both through `ak::Fx`); meters; the master strip.
   - *Gate: each effect on a track sounds the same live and baked (within float rounding); 10 tracks with two effects each stay under 10% of a core.*
10. **Games and polish**
    - `AKLivePlayer.arrangement`, `play_scene`, `play_timeline`; `AKCueBridge` and `render_cues` with arrangements; `.mid` and pattern lanes to loops; the racing demo re-made as loops and an arrangement; docs (`docs/loops.md`), README, HANDOFF, the skill.
    - *Gate: the racing song rebuilt as an arrangement plays in a demo scene that switches scenes from game state.*

## Risks and open questions

- **Reading audio files.** Godot imports WAVs (often compressed) and OGGs into streams the kit can't easily read sample by sample. Plan: read the source file in the editor (the kit's own WAV reader; OGG through Godot's decoder if 4.5 exposes one, else WAV only at first) and store decoded data in `AKSample`. Confirmed in phase 6: the kit reads WAV itself, and Godot 4.5's `AudioStreamOggVorbis.load_from_file` plus `AudioStreamPlayback.mix_audio` decode OGG exactly (after a fixed 2-frame lead), so both are in.
- **Notes held across notes.** Songs render each note as its own cached bake, so a synth loop's glide or legato between notes doesn't carry (known since phase 3). Fine for most loops; a mono, gliding loop may want a per-track live `AKSynthStream` later.
- **Grid editor performance.** A 4-bar loop at 32 a bar over 4 octaves is about 6,000 cells; draw the grid in one `_draw`, not as controls.
- **Live edits while looping.** Edits must re-derive the notes not yet sounding without a click or a doubled note; `song_changed()` already does this for songs and gets a test with a loop edited mid-pass.
- **Scope creep.** Automation lanes on the timeline, MIDI recording into loops, a delay send, swing per track and loop variations (A/B/C per cell) are candidates after phase 10, not in it.
- **Settled:** should tracks also take a whole `AKSong` or a `.mid` as a clip (play it as one block)? Decided (Chris, Oct 24): no; convert to loops instead.
- **Settled:** default tempo for a loop opened on its own: 120 bpm, or the last arrangement's? Decided (Chris, Oct 24): the last arrangement's, shown in the toolbar.
- **Settled:** library size and contents: decided (Chris, Oct 24): about 120 sounds and five kits; the list is drafted in phase 6 and can be trimmed or extended after.
