# The drum library

Drum kits and sounds from sampled drum machines, ready to play in loops and songs:
- **48,245 sounds** from 470 machines (the archive.org "drum machine samples" collection);
- **2,431 kits**: the machines' own kits, kits assembled from each machine's sounds, percussion kits.

The tools that made it are in `tools/drum_prep/README.md`. The library lives outside the project
(`D:\12_library\gak\processed_drums` here), like the patch library. A game plays a kit or sound
once you copy it into the project with **Use in project**.

## Setting it up

On the Loops page, open the **Drums** tab, then **Library folders…** → **Add…** and pick the drum
library folder (the one holding `gak_drums.json`). The folder list is the editor setting
`audio_kit/drum_library/roots`, so every project on the machine sees it.

The tab reads the index the first time it opens, in about three seconds.

## Finding a kit or a sound

- **Kits / Sounds** switches what the list shows.
- **Search** matches words in the name, machine, folder, category, kind and tags: `909`, `linn snare`, `bright hat`, `stereo crash`.
- **Filters** opens the menus. Each shows how many entries each choice leaves, given the others:
  - **Kits**: **Machine**, and **Kit type**:
    - *folder*: the machine's own kit folder, every sound in it;
    - *assembled*: put together from the machine's sounds (up to 8 per machine);
    - *percussion*: the machine's percussion, one of each kind;
    - *all*: every sound of a machine that has no kit otherwise.
  - **Sounds**:
    - **Category**: kick, snare, rim, clap, hat, cymbal, tom, perc, fx, vox, loop, tonal.
    - **Kind**: closed / open / pedal hats; low / mid / high toms; crash / ride / ride_bell / china / splash; conga, cowbell, shaker …
    - **Machine**.
    - **Sounds**: the descriptive words (below).
  - **Sure category** hides sounds whose category is a guess. **Favourites** and **Show hidden** do what they say.
- **Sort**: A-Z, by machine (then folder), by stars, or shuffled.

A click plays it: a sound as it is, a kit as a two-bar beat (kick, snare, hats, crash) at
100 bpm. A double-click uses it: the kit or sound is copied into the project (below). If the
loop being edited takes it (a kit for a drum loop, a sound for a sample loop), it becomes the
loop's instrument.

## What the details say

**A kit**: its machine, its piece count, how it was made (and from which folder), and how many
of its pieces have a sure category. If its pieces include velocity layers, it says how many.
Rows follow GAK's order: kick, snare, clap, closed / open / pedal hat (choking each other),
toms low to high, crash, ride, rim, then percussion. Piece names match the General MIDI drum
map, so a .mid drum part or a keyboard plays the right pieces.

**A sound**: its machine and folder; its category and kind, with how they were found:

| How | Means |
| --- | --- |
| *name and sound agree* | its name says so and its sound does too |
| *its name* | its name says so (the sound disagrees or wasn't sure) |
| *its sound* | its name doesn't say; the analysis does |

A "?" marks a guess. Then come its length, mono or stereo, its sample rate, its pitch when it
has a clear one, and its velocity layer (`[V2]` of a group). Last are the descriptive words:

| Word | Meaning |
| --- | --- |
| `short`, `medium`, `long` | dies away 40 dB within 0.25 s / 0.25–1 s / over 1 s |
| `very long` | the file runs over 4 s |
| `dark`, `bright` | darker / brighter than three quarters of its category |
| `punchy` | a fast attack (under 5 ms) and a quick fall |
| `pitched`, `falling pitch` | a clear pitch / a pitch that drops (kicks, toms) |
| `noisy` | mostly noise |
| `lo-fi` | a low sample rate, or no highs in a sound that should have them |
| `stereo` | real stereo (identical channels count as mono) |
| `roomy` | a long, quiet tail |
| `several hits` | more than one onset (flams, rolls) |
| `loop`, `long` | a loop by its name / over 8 s |

How sure the categories are, measured on machines the analysis never learned from: kicks 86%,
snares 75%, toms 74%, hats 72%, cymbals 69%, percussion 67%. Fx, vox, loop and tonal are never
called sure. The report is `analysis/report.md` in the collection folder.

## Rating and organising

Under the details:
- **★★★★★** rates; click the current rating to clear it.
- **♥** makes it a favourite.
- **Hide** takes it out of the list.
- **Your tags**: type them comma separated, then Enter. Search finds them.
- **Play** plays it again.
- **Use in project** copies it in.

Ratings and the rest are kept per machine in the Godot editor's data folder
(`audio_kit/drum_library_user.json`), keyed by each entry's ID, never in a kit or sound.
Rebuilding the library keeps them.

## Use in project

The library's WAVs stay where they are, and kits read them when they play. A game needs its
sounds inside the project, so **Use in project** (or a double-click) copies:
- **a sound**: its WAV to `res://audio/samples/drums/<machine>/`, with an `AKSample` beside it
  (`<name>.sample.tres`) holding the decoded sound, so an exported game plays it.
- **a kit**: each of its WAVs the same way, and the kit to `res://audio/kits/<name>.tres`, its
  pieces pointing at those samples. It then appears in the drum loop's instrument menu
  ("yours").

Copied files remember where they came from (meta `drum_library`: the entry's ID, machine and
collection). Copying the same kit or sound again reuses the copy.

In code:

```gdscript
var lib := AKDrumLibrary.new()
lib.roots = AKDrumLibrary.editor_roots()     # or PackedStringArray(["D:/12_library/gak/processed_drums"])
lib.load_all()
var e: Dictionary = lib.filter({type = "kit", machine = "Linn Linndrum"})[0]
var kit := lib.kit(e)                         # plays from the library folder
var path := lib.copy_kit(e, "res://audio/")   # res://audio/kits/Linn Linndrum 1.tres
```

`AKKit.load_json(path)` loads any kit file directly (`docs/loops.md`, AKKit).

## Rebuilding

After changing the tools or adding a collection, run the steps in `tools/drum_prep/README.md`:
convert, tag names, measure, classify, build kits. Then rebuild the index:

```bash
python -I tools/drum_prep/index_drums.py --root "D:/12_library/gak/processed_drums"
```

The tab rereads the index the next time it opens.

## Limits

- The collection has no stated licence: keep it to personal use.
- About a quarter of the sounds were tagged by analysis alone. Their categories are right about seven times in ten, so check before trusting a "?".
- Assembled kits pick sounds by tag and name. A machine sorted by instrument rather than by kit gives kits that may mix styles; the machine's own folder kits are the safer choice.
- 1,608 sounds have no category: mostly silence, odd effects and numbered sounds the analysis couldn't place.
