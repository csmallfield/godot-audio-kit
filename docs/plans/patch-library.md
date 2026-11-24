# Patch library: sorting, filtering and rating

Status: **agreed scope** (2026-11-23); steps 1 (categories and library metadata) 2 (the clean library: 21,817 patches in 264 banks, 296 duplicates folded) 3 (the index: a category from sources, names and banks for 13,332 patches, a creator for 18,318, an emulated synth for 4,697) 4 (`AKPatchLibrary` and `AKLibraryBrowser`, replacing the preset list) 5 (analysis: every patch measured, descriptive tags) and 6 (the classifier: 57% held-out accuracy, 1,118 sure guesses; report in `tools/patch_library/README.md`) built. Tools: `tools/patch_library/README.md`. Execution order at the end. It continues the goal in `docs/plans/synth-expansion.md`: a personal library of synthesized GAK instruments from patch and sample collections.

## Why

The converters have written 22,113 patches into libraries outside the repo, each a `gak_patch.tres` beside its `instrument.json` sidecar:

| Library (`D:\12_library\gak\...`) | Source | Patches |
| --- | --- | --- |
| `processed_synth1` | Synth1 (182 banks) | 16,706 |
| `processed_surge` | Surge XT | 3,008 |
| `processed_obx` | OB-Xd / OB-Xf | 1,620 |
| `processed_tal` | TAL-NoiseMaker | 259 |
| `processed_soundarchive` | DX7 (and 30 Mirage disks, no patches yet) | 256 |
| `processed_helm` | Helm | 216 |
| `processed_polynominal` | Casio CZ (and M3R programs, not converted) | 48 |
| `processed` | Open Samples: sampler instruments and 1,417 WAVs, no patches yet | 0 |

The Sound Lab can't use them yet. Its preset browser (`addons/audio_kit/editor/preset_browser.gd`) lists three folders inside the project (kit, bank, yours), loads every file to read its category, and filters by category and name only: fine for 21 presets, not for 22,000 outside the project.

What's known about the patches today:
- **Category:**
  - All 3,008 Surge patches have one, from their folders, already mapped to GAK's categories.
  - About 160 Helm patches have one, from their folders.
  - OB-Xf has one on some patches.
  - A keyword search of Synth1 names finds one for 6,905 of 16,706 (41%). The rest are names like "Glut-lk".
- **Creator:**
  - Surge and Helm patches carry an author.
  - Synth1 banks name theirs in the bank name or readme ("Bryan Lake", "Lila K", "-lk" and "(AK)" suffixes).
  - Factory banks are their maker's.
- **Duplicates:** Synth1 sidecars hold a sound fingerprint (`content.synth1.sound_sha256`), so the same patch in two banks can be found.

The library folders are also work folders. Beside each patch sit the sidecar (up to 14 kB, with the source's full parameter dump), the conversion's notes, and sometimes reference renders, source files and logs, with catalogues, chunk lists and failure lists at the top. That's right for converting, not for pulling sounds from.

## Goal

Find a patch among tens of thousands by what it is, where it came from and how much you like it, and play it at once:

- **Filters** (the main way in): category, ingestion source, origin, engine, emulated maker and model, creator, bank, descriptive tags, rating, favourites.
- **A category for every patch**: from the source's own data where it has one, from the name, or else from analysis of the patch itself, with a confidence.
- **Ratings** (0–5 stars), favourites, your own tags and category overrides, in a user file, never in the patches.
- **A clean library**: every converted patch copied out of the work folders into one tidy tree, with only what's needed to use, credit and find it.

## Principles

- **Patches stay as converted.** Metadata lives in a generated index and a user file. Converter output, sidecars and `.tres` files aren't rewritten.
- **The index is rebuildable; the user file isn't.** Rebuilding the index never touches your ratings or overrides, and stable IDs keep them attached.
- **Every value says where it came from.** A category from Surge's folder, from a name or from a guess is marked as such, so filters can ask for confident values only.
- **Approximate is useful, if labelled.** An analysis guess is better than "other", as long as it shows as a guess.
- **Fast with 25,000 patches.** The browser reads one index, not 25,000 files, and loads a patch only when you pick it.

## Decisions (2026-11-23)

1. **Categories** gain `arp`, `perc` and `woodwind`: 15 in all.
2. **The user file** is one per machine, in the Godot editor's data folder, shared by every project.
3. **"Emulates"** means hardware a patch recreates: the DX7, the CZ, the Oberheim family (OB-Xf), recordings of a maker's instrument, and hints in patch names. A software synth's design lineage doesn't count: Synth1 patches aren't marked as Nord Lead 2s.
4. **The library browser replaces** the Synth page's preset list (the kit, bank and your folders become sources in it).

## The clean library

`tools/patch_library/export.py` copies the converted patches out of the work folders into one library, `D:\12_library\gak\library` (the default; any folder works). The work folders stay as they are: they're where converters run, and the export is rerun from them whenever a converter improves.

**What goes in:**
- every patch a converter has made: Synth1, Surge, OB-Xf, TAL, DX7, Helm, CZ;
- later, patches from the sample matcher and sampler zones, when they exist.

**What stays out:**
- the 1,417 WAVs and the sampler instruments that have no patch yet;
- the M3R programs and combinations;
- reference and GAK renders, `.syx` and other source files;
- the full sidecars, `gak_convert.json`;
- catalogues, logs, chunk lists, failure lists, `unreferenced_ncw.txt`.

**Layout:**

```
library/
  README.md                      what this is, how it's rebuilt, the licences
  gak_library.json               the index (written by index.py)
  analysis/features.json         the analysis features, by patch ID (step 5)
  synth1/
    kvr-lila-k/
      BANK.txt                   the bank's readme, creator and licence
      017 Glut-lk.tres
      017 Glut-lk.json
  surge/
    factory/  third-party-a-liv/ ...
  obxf/ tal/ helm/ dx7/ cz/
```

- **One folder per source, then one per bank.** The bank folder takes the bank's name made safe for file names. A source's own grouping is kept as part of the bank name where it carries meaning: Surge's factory and third-party sets with the author's folder, DX7's cartridge, the CZ's set.
- **Two files per patch.** The patch is `<number> <name>.tres`, made safe and unique in the bank. Beside it, `<number> <name>.json` holds the metadata the index is built from:
  - the patch's ID, name, source, engine and bank;
  - the source's declared category, author, maker and model;
  - its licence;
  - the source file and its SHA-256, for provenance;
  - the converter and its version;
  - the conversion's scores (median level, envelope and spectral error) and caveats;
  - the sidecar's useful tags.

  The source's parameter dump stays in the work folder.
- **`BANK.txt`** holds the bank's readme text, as found, and its creator and licence. The licence matters most for the community banks, which are for a personal library only.
- **Duplicates are copied once.** The first copy, in bank order, goes in. The others are listed in its `.json` as `also_in` (their IDs and banks), so filtering by bank still finds them.
- **The patch files are the converters' own.** A `.tres` refers to the kit's `AKPatch` script by its `res://` path, so it loads in any project that has the addon.

**Rerunning:**
- A patch whose source is unchanged keeps its files. Changed patches are rewritten; patches no longer in any work folder are removed. Nothing outside the library folder is written.
- A run prints counts per source (copied, unchanged, removed, duplicates folded) and writes them to `README.md`.

## Fields

Each patch in the index has:

| Field | Values | Filter | Where it comes from |
| --- | --- | --- | --- |
| `id` | stable ID (below) | – | – |
| `name` | the patch's name | search | `identity.patch` from the sidecar, via the patch's `.json` |
| `path` | the `.tres`, relative to the library folder | – | – |
| `category` | one of the 15, with `category_from` and `category_conf` (0..1) and `category_alt` (second guess) | yes, with "confident only" | see Categories |
| `source` | `synth1`, `surge`, `helm`, `obxf`, `tal`, `dx7`, `cz`, `wav-match`, `sampler-zones`, `sound-lab`, `flavor`, `kit` | yes | the converter or tool that made it |
| `origin` | `default` (ships with the kit), `ingested` (a library folder), `created` (saved in your project) | yes | where the file lives (below) |
| `engine` | Synth1, Surge XT, Helm, OB-Xf, TAL-NoiseMaker, DX7, CZ-101, GAK | yes | the source |
| `emulates_maker`, `emulates_model` | Yamaha / DX7, Casio / CZ-101, Oberheim / OB-X family, Korg / M1 ... ; `emulates_from` `source` or `name` | yes, each alone or both | see Emulation |
| `creator` | person or company | yes | see Creators |
| `bank` | bank or pack (and the other banks a folded duplicate was in) | yes | the library's bank folder, `also_in` |
| `tags` | descriptive tags (below) plus the sidecar's useful ones | yes | analysis and sidecar |
| `also_in` | the duplicates folded into this patch | shown on the patch | Duplicates |
| `report` | spectral error against its source, when there is one | sort | `gak_report.json` |

The user file adds `rating`, `favourite`, `hidden`, `user_tags` and `user_category` per ID, and the browser merges them over the index.

### Stable IDs

- Ingested: `<source>:<sidecar id>`, for example `synth1:daichi-factory/soundbank00/001-synth1-brastring`. The sidecar ID is already unique and stable across reprocessing.
- Inside a project (kit, bank, yours): `res:<resource uid>` (the `uid://` Godot gives each resource), so renaming or moving a file keeps its rating.

### Origin

- **default**: `res://addons/audio_kit/patches/` and `res://addons/audio_kit/bank/patches/`.
- **ingested**: the clean library, or any other library folder in the setting (below).
- **created**: the Sound Lab's save folder (`res://audio/patches/` by default), from the Synth page or Flavor.
- A patch copied into the project with **Use in project** keeps its origin, source, creator and emulation, and records `derived_from` (the original's ID). Saving it after editing makes it `created`, with `derived_from` kept. These live in the `.tres` as resource metadata (`ak_library`), which Godot saves and loads with the resource.

## Categories

`AKPatch.CATEGORIES` becomes: bass, lead, pad, keys, pluck, bell, strings, brass, organ, woodwind, arp, perc, fx, voice, other. "other" stays last (the Synth page falls back to the last entry).

The category a patch shows is the first of:

1. **Yours** (`user_category` in the user file).
2. **Declared by the source**: Surge's and Helm's folders, OB-Xf's, a sampler's own category. Mapped through a table (Helm "SFX" → fx, "Arp" → arp; Surge's are already mapped). `category_from = "source"`, confidence 1.
3. **From the name**: keywords and prefixes, matched on whole words. Examples: bass, bs-, sub → bass; pad, pd- → pad; lead, ld- → lead; pluck, pizz → pluck; bell, chime → bell; string, str → strings; brass, horn, trumpet → brass; organ, org → organ; piano, ep, rhodes, clav, wurli, keys → keys; flute, reed, sax, clarinet, oboe → woodwind; arp, seq → arp; drum, kick, snare, hat, perc, tom → perc; fx, sfx, noise, laser, siren → fx; vox, voice, choir → voice. `category_from = "name"`. Confidence 0.9, or 0.6 when two categories match.
4. **From analysis** (below). `category_from = "analysis"`, the classifier's confidence, and its second guess in `category_alt`.

A patch with the arpeggiator on gets the `arp` tag whatever its category, and the `arp` category when nothing above gives one.

### Analysis

**Render.** Every patch in the clean library is played the same way through GAK:
- notes 36, 60 and 84;
- velocity 100;
- each held 2 s, released for 1.5 s;
- mono, 24 kHz.

A Godot batch (`tools/patch_library/render_batch.gd`, split across processes like `vsynth_batch.gd`) writes the WAVs a chunk at a time, in a temporary folder. A Python driver computes the features and deletes each chunk's WAVs, as `synth1_chunks.py` does. The features go to the library's `analysis/features.json`, by patch ID, with the renderer version and the patch file's hash, so a later run redoes only changed patches.

**Features** (per note and summed):
- *Envelope:*
  - attack time (to 90% of the peak);
  - level after 0.5 s and at the end of the hold, against the peak (decay and sustain);
  - release time (to −40 dB after note-off);
  - whether it goes silent before the release.
- *Spectrum:*
  - spectral centroid, and how much it moves over the note;
  - spectral flatness (noisy against tonal);
  - inharmonicity: energy away from the note's harmonics, which is high for bells and metal;
  - energy below 120 Hz;
  - level by register: the low note against the high one.
- *Pitch and movement:*
  - pitch stability, and periodic movement (vibrato, wobble);
  - onsets during a held note (arps, gates, sequences).
- *From the patch:*
  - mono or legato, polyphony, arpeggiator on;
  - oscillator count, noise share, FM depth, detune or stack width;
  - filter envelope depth;
  - LFOs on pitch, amp or cutoff;
  - effect types.

**Classifier.** The labels from steps 2 and 3 (about 10,000 patches) train it.
- It runs in Python with numpy only (already installed): multinomial logistic regression on standardized features, with k-nearest-neighbours as the comparison.
- Use scikit-learn in its own venv only if neither is good enough.
- **Held out by bank, not by patch**, so it isn't tested on near-copies from the bank it trained on.
- The tool writes a report:
  - accuracy and a confusion matrix per category;
  - per category, the confidence above which precision is at least 80%.
- Patches above their category's threshold are **confident**. The rest show the guess with an "unsure" mark.
- Name labels are noisy, so they weigh less than source labels in training.

Expect bass, pad, pluck, keys, fx and lead to sort well. Brass, strings, woodwind and lead will mix, and so will voice and pad. The report decides what's trusted.

### Descriptive tags

These come from the features, by thresholds kept in one table (`tools/patch_library/tags.json`) so they can be tuned:
- **Length:** `short` / `long`.
- **Attack:** `slow-attack`.
- **Brightness:** `bright` / `dark`.
- **Movement:** `evolving` (the spectrum moves).
- **Noise:** `noisy`.
- **Tone:** `metallic` (inharmonic); `fm`.
- **Width:** `wide` (detune, stacks, unison).
- **Bottom end:** `sub-heavy`.
- **Playing:** `mono`, `arp`, `gated` (onsets in a held note), `vibrato`.

Of the sidecars' own tags, the technical ones (`decoded`, `patch-data`, bank slugs) are dropped. Feature tags (`chorus`, `delay`, `sync`, `ring`) are kept.

## Emulation

`tools/patch_library/emulation.json` holds:
- **Per source:**
  - `dx7` → Yamaha / DX7;
  - `cz` → Casio / CZ-101;
  - `obxf` → Oberheim / OB-X family;
  - recordings and sampler instruments → the sidecar's `identity.manufacturer` and `model` (Korg, Roland, Kawai ...).
- **Name patterns:** a list of `[regex, maker, model]`, for example:
  - `\bjuno\b` → Roland / Juno;
  - `\b(tb-?)?303\b` → Roland / TB-303;
  - `jp-?8000` → Roland / JP-8000;
  - `\bmoog\b|minimoog` → Moog / Minimoog;
  - `prophet` → Sequential / Prophet;
  - `\bdx-?7\b` → Yamaha / DX7;
  - `\bm1\b` → Korg / M1.

  These are marked `emulates_from = "name"`.
- **Aliases** that fold spellings into one maker and model.

Maker and model are separate fields, so the browser can filter "Roland" alone or "Roland Juno".

## Creators

- **Surge** and **Helm**: the patch's author field.
- **Synth1**: per bank, from `tools/patch_library/creators.json`, which maps each of the 182 bank folders to a creator.
  - The indexer proposes entries from bank names and readme text ("by …", "(c) …", "presets by …") and from name suffixes ("-lk" → Lila K, "(AK)").
  - The table is reviewed once by hand; unknown banks stay empty.
- **OB-Xf**: per bank, from the same table (bank names often carry the author).
- **Factory banks**: DX7 → Yamaha, CZ → Casio, TAL factory → TAL, Helm factory → the patch's author, Surge factory → the patch's author.
- **Your own patches**: a name you set once (`audio_kit/library/author` in the editor settings), written into the patch's `ak_library` metadata on save.

## Duplicates

- Synth1: patches with the same `sound_sha256` form a group. The first, in bank order, is the original; the export copies it alone and lists the others in its `also_in`.
- Other sources: the same, with a hash of the `.tres` text without the patch's name.
- The browser shows the other banks a patch is in, and its bank filter finds it under each of them.

## Files

| File | Where | Written by |
| --- | --- | --- |
| the clean library (`.tres`, `.json`, `BANK.txt`, `README.md`) | `D:\12_library\gak\library` | `tools/patch_library/export.py` |
| `gak_library.json` | the library folder | `tools/patch_library/index.py` |
| `analysis/features.json` | the library folder | the analysis driver |
| `gak_library_report.json` | the library folder | the classifier: accuracy, thresholds, counts |
| `library_user.json` | the editor's data folder (`EditorInterface.get_editor_paths().get_data_dir()` + `/audio_kit/`) | the browser |
| `creators.json`, `emulation.json`, `tags.json`, `categories.json` (the name keywords and source mappings) | `tools/patch_library/` | by hand |

**The index:**
- It holds one entry per patch with the fields above, as compact JSON (about 300 bytes each, about 7 MB for every library).
- It is built from the clean library's `.json` files, the features and the tables, never from the work folders, and rebuilt incrementally: a patch whose `.json`, `.tres`, features and tables are unchanged keeps its entry.
- The browser caches each parsed index in the editor's cache folder as Godot binary, so opening is fast.

**The user file:**

```json
{"version": 1, "author": "", "patches": {
  "synth1:kvr-cleanzipbank/lila-k/017-glut-lk": {"rating": 4, "favourite": true, "user_tags": ["intro"], "user_category": "pad"}}}
```

It is written on every change, atomically (to a temporary file, then renamed). Keys of patches no longer found are kept, in case a library folder is offline.

**Settings** (editor settings):
- `audio_kit/library/roots`: the library folders (the clean library by default). Each one holds a `gak_library.json` or is offered to be indexed.
- `audio_kit/library/author`.

## The browser

It replaces `AKPresetBrowser` on the Synth page, as `AKLibraryBrowser`:

- **Search** on name, bank, creator and tags.
- **Filters:**
  - category;
  - source;
  - origin;
  - maker, then model;
  - creator;
  - bank;
  - minimum rating;
  - favourites only;
  - "confident category only";
  - show duplicates.

  Each filter shows how many patches match. Tags are chips you can add.
- **Sort:** name, rating, category confidence, the conversion's spectral error, or random (to discover).
- **The list:** name, category (a mark when it's a guess), stars, source. It's virtualized or paged, since 25,000 rows are too many for one `ItemList` fill on every keystroke.
- **Picking a patch** loads its `.tres` and plays it as the preset list does today, through the same Synth page path, so editing works on it.
  - A patch from a library folder is read-only: Save writes a copy into the project, as kit presets do today.
  - **Use in project** copies it with its library metadata.
- **On a selected patch:**
  - stars (0–5; clicking the current rating clears it);
  - favourite;
  - category override (a menu);
  - your tags;
  - hide.

  All of these write the user file.
- **Rebuild index** runs the indexer on a folder, from the browser.

The kit, the bank and your folder are indexed by the browser itself, as they're small and inside the project, so the same filters and ratings work on them.

## Out of scope

- Editing patches' sound in bulk, or moving files between libraries.
- Sharing ratings between machines (the user file can be copied by hand).
- Category analysis for sounds without a patch: the 1,417 WAVs join the index when the matcher makes patches of them, as source `wav-match`.
- M3R programs and combinations: not converted (F8 and the `m1` timing).
- Online lookups of creators or emulations.

## Execution order

Each step ends with its tests passing and is useful on its own. The browser (step 4) works before analysis exists, with categories from sources and names.

1. **Categories and stable IDs (small).**
   - Add `woodwind`, `arp`, `perc` to `AKPatch.CATEGORIES`, before "other".
   - Check the Synth page's category menu, Flavor and the preset browser with the longer list.
   - Add the `ak_library` resource metadata on save: source `sound-lab` or `flavor`, `derived_from`, author.
   - *Done when:* the affected tests pass and saved patches carry the metadata.
2. **The clean library (medium).**
   - `tools/patch_library/export.py`: the layout, the per-patch `.json`, `BANK.txt`, duplicate folding, `README.md` with counts and licences.
   - Run it on all the work folders into `D:\12_library\gak\library`.
   - *Done when:*
     - every converted patch is in the library once (duplicates folded), with its `.json`;
     - a sample of patches from each source loads in the editor and plays as before;
     - nothing but the listed files is in the tree;
     - a rerun with nothing changed writes nothing.
3. **The indexer, from what's already known (medium).**
   - `tools/patch_library/index.py` reads the clean library and covers every field except analysis: source, origin, engine, emulation by source and name, creator by field and table, bank, declared and name categories, tags, duplicates, report scores.
   - Write the first `creators.json` (proposed by the tool, reviewed by hand), `emulation.json` and `categories.json`.
   - *Done when:*
     - every patch has an entry;
     - the counts per field are reported (how many have a category, a creator, an emulation);
     - a rerun with nothing changed rewrites nothing.
4. **The user file and the library browser (large).**
   - `AKLibraryBrowser`: settings, index loading and caching, the in-project sources, filters with counts, search, sort, a virtualized list, stars, favourites, overrides, tags, hide, Use in project, Rebuild index.
   - Replace the preset list on the Synth page.
   - Tests (`tests/test_library.gd`) cover:
     - index reading and filtering;
     - user file merge and atomic save;
     - IDs surviving a rename;
     - read-only library patches saving as copies;
     - speed: filtering 25,000 entries under 50 ms.
   - Update `docs/sound_lab.md` and tutorial 2's preset step.
   - *Done when:* all of the above pass and a library of 22,000 opens and filters smoothly in the editor.
5. **Analysis renders and features (medium).**
   - `render_batch.gd` and the chunked Python driver.
   - `analysis/features.json` for every patch, and descriptive tags from `tags.json` into the index.
   - *Done when:* every patch has features and tags, timed for the whole library, and a rerun skips unchanged patches.
6. **The classifier (medium).**
   - Training with held-out banks, the report (accuracy, confusion matrix, per-category thresholds), and categories, confidences and second guesses into the index for patches without a source or name category.
   - Review the report together before trusting it.
   - *Done when:* every patch has a category, confident or marked unsure, and the report is in the library folder.
7. **Curation and polish (small, ongoing).**
   - Spot-check categories per source and fix the keyword and mapping tables.
   - Fill gaps in `creators.json`.
   - Tune tag thresholds.
   - Document the library in `docs/library.md` (user guide) and in the agent skill.
