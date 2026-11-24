# The patch library

Every synth patch you can pick in the Sound Lab, in one place, with filters and ratings:
- the kit's presets and the General MIDI starter bank;
- the patches you saved in your project;
- the converted patches: 21,817 from Synth1, Surge XT, OB-Xd/OB-Xf, TAL-NoiseMaker, Helm, the DX7 and the Casio CZ.

How it was planned and built is in `docs/plans/patch-library.md`, and the tools in `tools/patch_library/README.md`.

## Setting it up

The converted patches live outside the project, in a library folder (`D:\12_library\gak\library` here). On the Synth page, **Library folders…** → **Add…** picks it. The folder list is the editor setting `audio_kit/library/roots`, so every project on the machine sees it.

The first time the Synth page opens with a library folder, it reads the folder's index (`gak_library.json`, about 14 MB) in about two seconds. After that it reads a cached copy.

## Finding a patch

- **Search** matches words anywhere in the name, bank, creator and tags: `acid mono`, `lucknow pad`, `bright evolving`.
- **Filters** opens the menus. Each one shows how many patches each choice leaves, given the others:
  - **Category**: bass, lead, pad, keys, pluck, bell, strings, brass, organ, woodwind, arp, perc, fx, voice, other.
  - **Source**: the converter that made it (`synth1`, `surge`, `obxf`, `tal`, `helm`, `dx7`, `cz`), or `kit`, `sound-lab` and `flavor` for patches made in the kit.
  - **Origin**: `default` (ships with the kit), `ingested` (a library folder) or `created` (yours).
  - **Maker** and **Model**: the hardware a patch emulates, when known (Yamaha DX7, Casio CZ-101, the Oberheim OB-X family, Clavia Nord Lead 2 for the SOS banks, and hints in names like "Juno" or "303"). Pick a maker alone or a model too.
  - **Creator**: the person or company who made it, from the patch itself (Surge, Helm), its bank's readme, or a name suffix such as "-lk" for Lloyd McKay. 18,318 patches have one.
  - **Bank**: the bank, cartridge or set it came from.
  - **Stars**, **Favourites**, **Sure category** (hides guessed categories), **Show hidden**.
- **Sort**: A-Z, stars, surest category, closest to its source (the conversion's measured spectral error; the closest conversions first), or shuffled, to discover.
- **Clear** resets the search and every filter.

The list shows 300 at a time; **More** adds the next 300. Click a patch to load it on the Synth page and double-click to hear it.

## Where categories come from

The detail under the list says how a patch's category was found:

| How | Patches | How sure |
| --- | --- | --- |
| The source's own folder (Surge, Helm, OB-Xf's factory) | 3,357 | sure |
| The patch name ("BS Wobble", "oldPad", "Hi Hat 2") | 8,801 | sure, or a "?" when the name fits two categories |
| The bank's name ("Stephan Musch Bank 2 (Bass)") | 272 | 70% |
| The arpeggiator is on | 1,758 | sure |
| **Analysis**: each patch played at three notes, measured, and compared with the patches above | 7,598 | 1,118 sure, the rest marked "?" |

A "?" after the category means it's a guess. The analysis is right about half the time on its own, so read it as a pointer, not a fact.
- It's reliable for **bass**, **pad**, **lead**, **perc** and **arp**: those guesses can be sure.
- It's never sure for keys, pluck, bell, strings, brass, organ, woodwind, fx or voice: these tell apart by playing, not by three held notes.

The detail also shows the second guess. Setting your own category (below) fixes one for good.

## Tags

Every converted patch was measured, and tags describe what it does:

| Tag | Meaning |
| --- | --- |
| `short`, `long` | dies out within a second / still sounding 1.5 s after release |
| `slow-attack` | takes over 0.6 s to swell in |
| `bright`, `dark` | spectral centroid above 3 kHz / below 300 Hz at middle C |
| `evolving` | its brightness or level moves a lot while held |
| `noisy`, `metallic` | noise-like / strongly inharmonic (bells, metal) |
| `fm` | uses FM |
| `wide` | detuned unison or a chorus |
| `sub-heavy` | strong energy under 120 Hz even at middle C |
| `gated`, `vibrato` | rhythmic re-attacks while held / pitch wobble at 3–9 Hz |
| `mono`, `arp` | mono or legato / the arpeggiator is on |

The sidecar's own feature tags (`chorus`, `delay`, `sync`, `lp24` ...) are there too. Search finds any tag.

## Rating and organising

Pick a patch, then use the row under the list:
- **★★★★★**: click a star to rate (clicking the current rating clears it).
- **♥** makes it a favourite.
- **Hide** takes it out of the list (**Show hidden** brings hidden ones back).
- **The category menu** gives the patch your own category ("library" goes back to the library's).
- **Your tags**: type them comma separated, then Enter.
- **Use in project** copies the patch into your patch folder (`res://audio/patches/`). The copy keeps its category and a note of where it came from: source, creator, bank, and the library patch's ID. Games can only load patches inside the project, so use this for any patch a game plays.

Ratings and the rest are kept in one file per machine, in the Godot editor's data folder (`audio_kit/library_user.json`), keyed by each patch's ID. They never go into a patch file. Rebuilding the library keeps them, because the IDs don't change.

## Editing a library patch

A library patch opens as a copy: the file in the library never changes. **Save** writes your version into the project, and its metadata records the library patch it came from. Patches saved from the Synth page or Flavor carry the tool that saved them, your name (the editor setting `audio_kit/library/author`) and what they were made from.

## Rebuilding

When a converter improves, or after tuning the tables:

```bash
python tools/patch_library/export.py
```

```bash
python tools/patch_library/analyze.py
```

```bash
python tools/patch_library/classify.py
```

```bash
python tools/patch_library/index.py
```

Each step skips what hasn't changed:
- `export.py` copies new and changed patches into the clean library.
- `analyze.py` measures new and changed patches: all of them take about 33 minutes.
- `classify.py` retrains and guesses again: seconds.
- `index.py` rewrites the index.

**Library folders…** → **Rebuild indexes** runs the last one from the editor.

The rules are plain tables in `tools/patch_library/`, so you can fix a mistake:
- `categories.json`: name keywords and source folders;
- `creators.json`: who made each bank;
- `emulation.json`: what each name hints at;
- `tags.json`: the tag thresholds.
