# The Sound Lab

The **Sound Lab** is a main screen in the Godot editor, beside 2D, 3D and Script, with two pages: **SFX** for quick game sounds and **Synth** for building and playing instruments. Everything it makes is an ordinary resource or WAV in your project.

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

- Live play, the scope and the automatic preview need the native core; without it the panels, preset browser, preview **Render**, saving and baking all work (GDScript rendering is about 100× slower).
- Custom wavetables (`{frames = ...}`) show as "(custom)" in the table menu and are kept as they are; author them in text (`docs/synth.md`).
