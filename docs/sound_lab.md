# The Sound Lab

The **Sound Lab** is a main screen in the Godot editor, beside 2D, 3D and Script, with four pages: **SFX** for quick game sounds, **Synth** for building and playing instruments, **Loops** for writing loops on a grid while they play, and **Sequencer** for arranging loops as scenes and on a timeline. Everything it makes is an ordinary resource or WAV in your project.

## SFX

Press a category (pickup, jump, laser, hit, explosion, power-up, UI click, confirm, cancel, blip, or random) to hear a new sound of that kind; type a seed to get one back; **Mutate** nudges it. Edit any number in the inspector on the right and it replays. **Bake WAV** writes it into the project (`res://audio/sfx/` unless changed), **Save recipe** keeps it as text, **Save stream** keeps it as an `AKRecipeStream` that varies a little on each play. In code: `AKSfxGen.generate(&"jump", 42)`.

## Synth

```
┌ Presets ───────┐┌ name   New  [save name]  Save  category  Inspector ┐
│ search  [all]  ││ ┌ Oscillator 1 ┐┌ Oscillator 2 ┐ + Oscillator ┌Scope──┐│
│ acid_bass bass ││ │ shape level  ││ ...          │              │ wave  ││
│ brass   brass  ││ └──────────────┘└──────────────┘              │Spectrum│
│ ...            ││ ┌ Voice ┐┌ Filter ┐┌ Amp envelope ┐ ...       │Preview │
├ Song ──────────┤│ ┌ Modulation matrix ──────────┐┌ Effect 1 ┐  │ note   │
│ open play save ││ └─────────────────────────────┘└──────────┘  └────────┘│
│ lanes          ││ Oct- Oct+ Velocity Sustain  All off  MIDI input        │
└────────────────┘│ [ keyboard ]                                           ┘
```

**Presets.** Every patch in the kit (`addons/audio_kit/patches/`), the General MIDI starter bank and your own folder (`res://audio/patches/`, listed as "yours"), filtered by category (bass, lead, pad, keys, pluck, bell, strings, brass, organ, fx, other) and by a search on the name. Click to pick, double-click to hear it. A kit or bank preset opens as a copy, so the shipped files never change; **Save** writes your version to `res://audio/patches/<name>.tres` and from then on you're editing that file. **New** starts from a blank patch (one saw, an open filter, a plain envelope). The category menu in the toolbar sets the patch's category for the browser.

**Panels.** Every part of the patch, in panels that flow to fit the width:

| Panel | What's in it |
| --- | --- |
| Oscillator 1–4 | Shape (sine, triangle, saw, square, pulse, noise, morph, table), level, semitones, cents; width for pulse; position for morph and table; the wavetable for table; FM from (another oscillator, or itself for feedback) with its depth; sync to; ring from. **x** removes one (links to it are cleared, later ones renumbered); **+ Oscillator** adds one (up to four) |
| Voice | Mode (poly, mono, legato), polyphony, unison, detune, spread, glide, bend range, velocity sensitivity, gain, pan, seed (**New** rolls one) |
| Filter | Type; cutoff; Q and slope for the state-variable types, resonance and drive for the ladder |
| Amp envelope, Envelope 2, Envelope 3 | Attack, decay, sustain, release, decay curve, with a picture of the shape |
| LFO 1, LFO 2 | Shape, rate, delay |
| Modulation matrix | Rows of source → destination × amount; the amount slider's range follows the destination (±24 semitones for pitch, ±8 octaves for cutoff ...). **+ Row** adds one, **x** removes it |
| Effect 1 ... | Each effect's settings; **↑ ↓** reorder, **x** removes. **Add effect** offers chorus, flanger, phaser, eq, compressor, saturate |

Sliders for frequencies and times are logarithmic. Click a value to type one (typed values can go past the slider's range). Every change is heard at once (the next note, and a playing note's stream picks it up), and every change is undoable: in the editor it joins the editor's history, so **Ctrl+Z** works; a slider drag counts as one step. The panels are an editor over the same text the `.tres` holds (see `docs/synth.md`), so a patch made here reads and diffs like any other.

**Scope.** The wave and spectrum show what the keyboard is playing (with the native core). **Preview note** renders middle C held 0.6 s and draws the whole note, its attack, decay and release; with the native core it re-renders a moment after each edit, without it press **Render**. When nothing is playing the spectrum shows the preview note's held part. **Play** plays a short phrase (or the preview note without the native core).

**Keyboard.** Click or drag (lower on a key is louder), or the computer keys (`Z S X D C V G B H N J M`, `Q 2 W 3 E R 5 T 6 Y 7 U`; `[` `]` change octave). Tick **MIDI input** for a connected keyboard: velocity, pitch bend, mod wheel, aftertouch and the sustain pedal reach the patch.

**Song.** Open a `.mid` file or a song `.tres`, play it, give any lane another patch from its menu, and save it as text (`res://audio/songs/`). See `docs/midi.md`.

**Inspector** shows the patch in Godot's own inspector, where the Audio Kit dock plays notes, chords and arpeggios and saves WAVs; the dock's **Open in Sound Lab** comes back here.

## Loops

```
[Loops|Sounds] [name] New Type Instrument Open  Bars Division Swing  Play 120bpm category Save
search  [all]  Oct- Oct+  -1st +1st  Duplicate Double Halve  Ramp up/down Humanize  Undo Redo  Context
               Guides: Scale Root Fold | [x] Chord Root Type [Cm9      ] C Eb G Bb D
beat_a · perc  +----+------------------------------------------------+
bass_a · synth |kick|#     #           #     #                       |
...            |snr |   #     #           #     #                    |
               |hat |# # # # # # # # # # # # # # # #                 |
               |Velocity  | | | | | |                                |
               Sample or kit settings (root note, mode, trim; or each piece's sound, level, pan, tune, choke, gate)
```

A loop is a few bars of notes for one instrument: a patch (**synth**), a sample played at pitch (**sample**) or a drum kit with a row per piece (**percussive**). The data and the sound library are described in `docs/loops.md`.

**Toolbar.** Type a name; **New** offers synth, sample or percussive (a new loop starts with the pluck preset, the library's epiano, or the punch kit). **Type** changes the kind of the open loop. **Instrument** lists patches (the kit's presets, the bank and yours) for a synth loop, sounds (the kit-made library and the project's own files) for a sample loop, and kits for a percussive loop; **Open** takes a patch to the Synth page. **Bars** (1, 2, 4, 8), **Division** (16, 32, 12 or 24 cells a bar: only the grid and the snap, never the notes), **Swing**, **Play**/Stop, **Tempo**, a category for the browser, and **Save** (to `res://audio/loops/<name>.tres`).

**Guides.** Two tints on the piano rows help you stay in key; neither changes the notes, and neither is saved with the loop.

- **Scale** and **Root** tint the rows in the scale a cool blue (the root a little stronger) and mark them on the key's edge; **Fold** hides the rest. All the common scales are there: major and minor, the modes (dorian, phrygian, lydian, mixolydian, locrian), harmonic and melodic minor with lydian dominant, phrygian dominant and altered, the pentatonics and blues, whole tone, both diminished scales, bebop, and others (double harmonic, hungarian minor, hirajoshi, in sen...).
- **Chord** tints a chord's rows warm (its root stronger) and writes each tone's interval by the key (R, b3, 5, b7, 9). Pick a root and a type from the menus, or type a symbol and press Enter: `Cm9`, `G7b9`, `Fmaj7#11`, `Bbm7b5`, `D/F#`, `C9sus4`, or words such as `C minor 9`. The notes, spelt from the root (C Eb G Bb D), show beside it. A sus chord replaces the third, so `C minor sus 9` shows C9sus4 (C F G Bb D); for a minor chord with a 9th, use `Cm9` or `Cmadd9`. Scale and chord can be on together: a chord tone outside the scale stands out as warm without the blue mark.

**The grid.** Rows are a piano (C3 to C5 for a new loop; **Oct-** / **Oct+** move it, and it opens wherever an existing loop's notes are) or the kit's pieces. Bars are strong lines, beats lighter ones; triplet divisions put three cells on a beat-pair.

| Do | To |
| --- | --- |
| Click an empty cell | Add a note one cell long (drag right to make it longer) |
| Click a note | Delete it |
| Drag a note's body | Move it in time and pitch (a selected group moves together) |
| Drag a note's right edge | Resize it |
| Hold Shift while dragging | Snap to the next finer division |
| Right-drag | Select the notes in a box |
| Arrows (Shift: an octave) | Move the selection by a cell or a row |
| Ctrl+D, Delete, Ctrl+A, Esc | Duplicate the selection after itself, delete it, select all, select none |
| Drag in the velocity strip | Set a note's velocity (the selection's, if there is one) |
| Click a key or a piece name | Hear the row; a kit row's **M** mutes it while you work (not saved) |

Drum hits are a cell whatever their length, unless the piece is gated. A small yellow corner marks a note that sits off the current grid (it still plays where it is). Every edit is undoable and joins the editor's history (Ctrl+Z), and a drag is one step.

**Tools.** **-1 st** / **+1 st** transpose the selection (or every note), **Duplicate** makes a copy of the loop to save under a new name, **Double** makes it twice as long with the notes copied, **Halve** keeps the first half, **Ramp up/down** spreads velocities across the selection in time order, **Humanize** nudges them at random.

**Playing.** With the native core the loop plays live, and an edit reaches every note that hasn't sounded yet: add a note just behind the playhead and you hear it on the next pass, without stopping. Without the native core **Play** renders one pass and loops the bake (and re-renders after each edit). Tick **Context** and click other loops in the browser to play them with this one (a bass line against the drums); **Clear context** empties it. The tempo is the tab's own for now; with arrangements (the Sequencer, next) it follows the open one.

**Sounds.** The library browser beside the loops: the kit-made library by folder, and the project's `.wav`, `.ogg` and `.sample.tres` files under `res://audio/`, with a search and a waveform; click to hear one, double-click to make it the sample loop's instrument. Picking a project file makes an `AKSample` beside it (`kick_01.wav` → `kick_01.sample.tres`) with its root note detected by the harmonic pitch test (check it by ear; the Root box changes it). A pitched library sound plays gated, so a note's length is heard; drums play out.

**Sample and kit panels.** Under the grid: for a sample loop the sample's root note (**Detect** measures it), mode (oneshot, gate, loop), start and end, loop points, release, gain and reverse; for a percussive loop a row per piece with its name, sound (**Use selected** takes the sound selected in Sounds), level, pan, tune, choke group, gate and ▶. **+ Piece** adds the selected sound as a piece. A shipped kit is edited as a copy kept in the loop; **Save kit** writes it to `res://audio/kits/`.

## Sequencer

```
[loops]        name New (open) Save "Import Auxy…" "Auxy pad kit…"  Play Stop  Loop bars 1 to 4  120 bpm 4/4  race bar 3.2  next bar
beat_a · perc  Bake Stems "Save as song" "Cue sheet" Undo Redo
bass_a · synth [Scenes | Timeline]
...            Scenes:   +Scene name bars | Paint into bars 1 to 8 | Paint scene
                         ▶ intro  ▶ race   ▶ final
               drums       -      beat_a   beat_b
               bass        -      bass_a   bass_a
               chords   chords_a chords_a chords_a
               Timeline: snap Zoom marker name
                 intro      race                        final
               drums       [beat_a==================][beat_b========]
               Tracks: drums ↑ ↓ x  bass ↑ ↓ x  chords ↑ ↓ x  + Track
```

The Sequencer arranges loops on tracks in two linked views over the same tracks: **Scenes** (a game switches between them) and **Timeline** (a fixed piece). Both compile to an `AKSong` (`AKArrangement.to_song`), so either plays live or bakes; see `docs/loops.md`.

**Placing loops.** Click a loop in the list on the left: it's what the next click places ("placing: bass_a"). Click a scene cell to put it there, or an empty stretch of a track in the timeline to place a clip as long as the loop. Right-click a cell or a clip to clear it. Any loop can go on any track, since each loop carries its own instrument; a drum loop on a track called "drums" plays as lanes `drums.kick`, `drums.snare` ...

**Scenes.** A column per scene, a cell per track. Click a scene's name to launch it; while scenes are playing, a launch switches on the next bar (or beat, or the end of the scene: the menu at the end of the transport), exactly as `AKLive.song_queue` does for a game, and the scene waits highlighted in yellow until it starts. Right-click a scene's name to select it without launching: then the toolbar renames it, sets its length (0 = its longest loop), deletes it, or **Paint**s its clips across a bar range of the timeline (what was there on those tracks is trimmed around it), so a sketch made in scenes becomes a timeline quickly.

**Timeline.** Bars across, tracks down. Drag a clip's body to move it (to another track, too); drag its right edge to make it longer (more repeats) or shorter; drag its left edge to start part-way into the loop; Alt-drag copies; Delete removes the selected clip. Thin lines inside a clip mark where its loop repeats. Snap to the bar, the beat or off; zoom in and out. Where clips overlap on a track, the one that starts later plays and the earlier one resumes after it, in phase. **Markers**: click the strip above the bars to add one, drag to move, right-click to remove; select one and type its name in the toolbar. Markers cut the timeline into the sections a song (and a game) knows by name; before the first marker the section is called "start". A clip that crosses a marker carries on in phase. Click the bar numbers to move the playhead.

**Transport.** **Play** plays the selected scene (Scenes view) or the timeline from the marker at or before the playhead (Timeline view); **Loop bars** plays a bar range round and round instead. Tempo and meter are the arrangement's; the Loops tab follows the tempo of the arrangement last opened here. With the native core everything plays live and edits reach the notes not yet sounding; without it, Play bakes and plays the bake. Live loudness (the master's loudness step) is measured once when Play starts, over the timeline or over every scene in order.

**Tracks.** Add, rename (the clips and cells follow), move up or down, delete (with its clips).

**Import Auxy…** opens a song made in Auxy (iOS). In Auxy: Settings → Export Project → **Export for Bitwig Studio**, and pick the `.axbw` it makes. Its loops land in the loop list (named after the song), each drum channel gets a kit in `kits/`, the song's stems go to `stems/<song>/`, and the arrangement opens: a track per Auxy instrument, the song on the timeline (a marker wherever the loops change) and a scene per distinct set of loops. Instruments play on a preset guessed from Auxy's preset name. Drums play Auxy's own sounds, cut from the song's drum stem (`samples/auxy/`); pads the song doesn't play come from a pad kit made with **Auxy pad kit…** (pick an export of a loop hitting every pad once, in order), else from a library kit. Swap sounds in the song's kit and every loop follows. The status line lists what was imported and any warnings. Details and why that export: `docs/loops.md`, Importing from Auxy.

**Mixer.** The third view: a strip per track and a master strip.

| Track strip | What it does |
| --- | --- |
| Meter | The track's level as it plays live (after its fader and inserts) |
| Fader | Level in dB (−48 to +12) |
| M, S | Mute; solo (when any track is soloed, only soloed tracks play) |
| Pan, Send | Balance; how much feeds the shared reverb (taken before the inserts) |
| Intensity | Tick it to fade the track in with the music's intensity, between **from** and **to** (a game sets the intensity; see `AKLive.set_music_intensity`) |
| FX | Show the track's insert chain below the strips: chorus, flanger, phaser, eq, compressor, saturate, in order, with the same settings as a patch's effects; ↑ ↓ reorder, x removes |

The **master strip** has the output meter, the arrangement's intensity (what bakes use; moving it while playing also moves the live music intensity), the shared reverb (room, damp, width, return) and **FX**: the master chain (gain, filters, dcblock, loudness, limit and the six effects). A track's inserts run on its lanes mixed together, after its notes' levels and its intensity fade, live on the track's bus and baked on its stem through the same code, so what you hear arranging is what bakes. Every change is undoable; a slider drag is one step. While playing, level, pan, send and mute reach the notes not yet sounding (after the lookahead, about 0.3 s), an insert's settings restart that insert, and a master chain change restarts playback.

**Recording.** Play along on a MIDI keyboard (or pads) and keep what you played as a take. Click the **●** beside a track's name in **Tracks** to arm it: the keyboard now plays that track's instrument (the loop of its clip at the playhead; a track named like drums with no clips gets the punch kit, others the pluck preset), or what **with** picks (any drum kit or patch). **● Record** counts in (**count-in**, 0 to 4 bars of clicks), plays the timeline from the playhead's section and takes down every note with its velocity, the sustain pedal holding notes as you heard them; **Click** keeps a metronome going. Press **● Record** again or **Stop** to finish: the take is saved as a loop in `res://audio/loops/takes/` (`<arrangement>_<track>_take<n>.tres`) and placed on the armed track from the bar of its first note to the end of the bar of its last, trimming what was there (one undoable step). Record again later in the song to continue; a take is an ordinary loop, so double-click it to fix notes on the Loops grid with the music around it. Pads and drum keys play a kit's pieces by their General MIDI names (36 kick, 38 snare, 42 closed hat, 46 open hat, 49 crash ...), others by pad order. Notes go where you heard the music when you played them (the mixer's position less the audio output's latency); if your takes still come out late, raise **latency** (ms). Notes before the section's first bar are dropped, except a pickup just before it.

**Editing a loop in place.** Double-click a cell or a clip: its loop opens in the Loops tab with the rest of the scene (or the clips overlapping it) as context, at the arrangement's tempo.

**Export.** **Bake** writes the timeline (or, in the Scenes view, the selected scene) to `res://audio/renders/<name>.wav`; **Stems** a WAV per track (and the shared reverb) to `res://audio/renders/<name>_stems/`; **Save as song** the compiled timeline as an `AKSong` (`res://audio/songs/`) for projects that want only songs; **Cue sheet** the timeline's notes and sections as motion-kit cues (`res://audio/cues/<name>.json`). **Save** keeps the arrangement as text in `res://audio/arrangements/<name>.tres`; the menu beside New opens saved ones.

## Building an instrument: an example

A resonant bass, from nothing:

1. **New**. Oscillator 1: shape *square*, semitones −12. **+ Oscillator**; oscillator 2: *saw*, cents 7.
2. Filter: type *ladder*, cutoff 300 Hz, resonance 0.55.
3. Envelope 2: decay 0.25 s. Matrix: **+ Row**, *env2 → cutoff*, amount 4 (a pluck of the filter four octaves up); **+ Row**, *velocity → cutoff*, 1 (harder notes brighter).
4. Amp envelope: sustain 0.6, release 0.3 s. Voice: unison 2, detune 12 c, spread 0.8.
5. **Add effect** → chorus, mix 0.35.
6. Type a name, **Save**. It's `res://audio/patches/<name>.tres`: play it with an `AKSynthStream`, an `AKMidiRouter`, a song lane or the `patch` voice in a recipe.

This is the phase 5 gate, and `tests/test_patch_editor.gd` does exactly these steps through the lab's own controls, then checks the saved file and measures the sound (the attack brighter than the held note, harder notes brighter, stereo from the spread and chorus).

## Demo scenes

In `demo/sound_lab/`, each a runnable scene:

| Scene | Shows |
| --- | --- |
| `keyboard_demo.tscn` | Presets played in a game from an on-screen, computer or MIDI keyboard, with mod wheel and bend sliders and a scope, through a Godot bus carrying the kit's `AKChorus` (native core) |
| `sfx_demo.tscn` | A button per SFX category, each an `AKRecipeStream` that varies per play; **New sounds** rolls seeds (no native core needed) |
| `midi_song_demo.tscn` | `minuet.mid` imported as a song through the starter bank and played live (baked without the native core, which takes a while) |

## Limits

- Live loop play, live play, the scope and the automatic preview need the native core; without it the panels, preset browser, preview **Render**, saving and baking all work (GDScript rendering is about 100× slower).
- Custom wavetables (`{frames = ...}`) show as "(custom)" in the table menu and are kept as they are; author them in text (`docs/synth.md`).
- In the Loops tab, row mutes aren't saved. The import row (**From a song, pattern or .mid**) makes a loop from one lane or all the drums at a time, quantised to the grid you pick; a drum import makes a kit with a piece per lane. Context plays loops picked by hand, or the scene or clips around a loop opened from the Sequencer.
- In the Sequencer, dragging loops from the list isn't supported: pick, then click. Mixer moves aren't instant while playing (notes already scheduled keep their level), and editing an insert restarts it (its delay lines empty).
