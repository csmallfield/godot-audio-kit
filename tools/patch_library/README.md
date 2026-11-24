# patch_library

Tools for the patch library (plan: `docs/plans/patch-library.md`). They read the converters' work folders (`D:\12_library\gak\processed_*`) and write the clean library (`D:\12_library\gak\library`) and its index. Python 3 with the standard library unless noted.

## export.py: the clean library

```
python tools/patch_library/export.py [--work D:/12_library/gak] [--out D:/12_library/gak/library] [--dry-run]
```

Copies every converted patch (a `gak_patch.tres` beside an `instrument.json` sidecar) into `<out>/<source>/<bank>/`:
- `<number> <name>.tres`: the patch, byte for byte as the converter wrote it.
- `<number> <name>.json`: its metadata. That is its ID (`<source>:<sidecar id>`), name, source, engine, bank, number, the source's declared category, author, maker and model, licence, source file and SHA-256, converter, scores (median level, envelope and spectral error, or the DX7's SNR), caveats, the sidecar's tags, and `also_in`: the duplicates folded into it.
- `BANK.txt` per bank: its creators, licence, patch count and readme text.
- `README.md`: counts per source and the licences.

Banks are as follows:
- Synth1: the bank folder.
- Surge: `factory`, or `third-party <author>`.
- OB-Xf: the `.fxb` bank, or `factory <folder>` for single patch files.
- DX7: the cartridge.
- Helm, TAL and the CZ: their set.

Duplicates are found by the sidecar's sound fingerprint, or by the `.tres` without its name. The first copy, in ID order, goes in.

A rerun writes only what changed, renames and removes what the work folders no longer produce, and leaves `gak_library.json` and `analysis/` alone. On 2026-11-23: 22,113 converted patches, 21,817 in the library (296 duplicates folded), 264 banks, 412 MB.

## index.py: the index

```
python tools/patch_library/index.py [--library D:/12_library/gak/library] [--dry-run]
```

Writes `<library>/gak_library.json`, one entry per patch. Each entry has:
- id, name, path, source, origin, engine, bank;
- category, with where it came from, its confidence and a second guess;
- emulated maker and model, and where they came from;
- creator, and where it came from;
- tags, the banks its duplicates were in, its spectral error or SNR, and its number of caveats.

The rules are in three tables beside the script, edited by hand:
- **`categories.json`** holds the categories, a source's folder names that declare one (for Surge, Helm and OB-Xf's factory), and keyword patterns for names and bank names.
  - The order of precedence: the source's folder, then the name (confidence 0.9, or 0.6 when two categories match), then the bank name (0.7), then the arpeggiator being on (0.8), then the analysis (steps 5 and 6).
  - Anything left is `other`, with no `category_from`.
- **`emulation.json`** holds the maker and model per source (DX7, CZ, OB-Xf) and name patterns (`emulates_from = "name"`), tried on the patch name and then the bank name.
- **`creators.json`** holds creators per bank (reviewed from each `BANK.txt`) and name suffixes ("-lk", "(AK)", "-Tek" ...). A patch's own author field (Surge, Helm) wins.

`mono` and `arp` tags are read from the patch itself. The file is rewritten only when it changes.

On 2026-11-23 (all 21,817 patches):

| How the category was found | Patches |
| --- | --- |
| Name | 8,801 (camelCase and underscores split since step 6) |
| Source folder | 3,357 |
| Arpeggiator on | 1,758 |
| Bank name | 272 |
| Not found | 7,629 (7,598 guessed by classify.py, 31 silent) |

A creator was found for 18,318 patches. An emulated synth was found for 4,697: 1,906 by source and 2,791 from names, 2,504 of those being the SOS banks' Nord Lead 2 recreations. The index is 13.4 MB.

## analyze.py: measurements and descriptive tags

```
python tools/patch_library/analyze.py [--library ...] [--jobs 12] [--chunk 1000] [--limit n] [--tags-only]
```

Plays every patch through GAK with `render_batch.gd`:
- notes 36, 60 and 84 at velocity 100, each alone;
- each held 2 s, then released for 1.5 s;
- mono, 24 kHz, 16-bit, in a temporary folder.

Several Godot processes share each chunk. Then it measures each note with numpy:
- **Envelope:** attack time, level at 0.5 s, at 1 s and at the end of the hold, release time.
- **Brightness:** the spectral centroid (magnitude-weighted), and how far it moves.
- **Noise:** spectral flatness.
- **Spectrum shares:** below 120 Hz and above 4 kHz.
- **Harmonicity:** the share of power within 40 cents of the detected pitch's harmonics, and the pitch's clarity.
- **Movement:** pitch spread and vibrato (3–9 Hz), level movement, and onsets during the hold.

It also records the settings a render hides: oscillators, noise share, FM depth, unison and detune, mono, glide, arpeggiator, envelope-to-cutoff and LFO rows, effects, filter type and cutoff.

Everything goes to `<library>/analysis/features.json`, by patch ID, with the patch file's hash. A rerun measures only new or changed patches, and the file is saved after every chunk.

**Tags** come from `tags.json` (thresholds set from the spread over the library). They are `short`, `long`, `slow-attack`, `bright`, `dark`, `evolving`, `noisy`, `metallic`, `fm`, `wide`, `sub-heavy`, `gated`, `vibrato`, `mono`, `arp` and `silent`. `--tags-only` reapplies the thresholds without rendering; `index.py` then puts the tags into the index.

On 2026-11-24, all 21,817 patches took 33 minutes with 16 processes on 24 cores. 124 render silent.

| Tag | Share of patches |
| --- | --- |
| wide | 60% (most Synth1 patches use the chorus) |
| long | 42% |
| slow-attack | 29% |
| mono | 28% |
| sub-heavy, evolving, fm | 24% each |
| metallic | 18% |
| gated | 17% |
| bright | 15% |
| dark, arp | 14% each |
| noisy | 12% |
| vibrato | 10% |
| short | 6% |

## classify.py: categories for the rest

```
python tools/patch_library/classify.py [--library ...] [--folds 5]
```

Trains on the patches index.py could categorise and guesses the rest. Labels are weighted by where they came from: source folder 1, arpeggiator 0.8, name 0.7 (0.42 when two categories matched), bank 0.5.

- **Models:** three, numpy only: multinomial logistic regression, a one-hidden-layer network and k-nearest-neighbours.
- **Features:** the measurements at the three notes (envelope, brightness, noise, harmonicity, octave bands, decay rate, attack against hold brightness), the first 12 harmonics at the hold and the attack, and the settings.
- **Testing:** with whole banks held out (5 folds), so a bank's near-copies never test it. The best is kept.
- **Thresholds:** per category, the probability above which held-out precision reaches 80%.

It writes the following:
- `analysis/categories.json`: guess, confidence and second guess per patch. The confidence is rescaled so the category's threshold sits at 0.8, the browser's "sure" line.
- `gak_library_report.json` and `analysis/report.md`: per-category precision and recall, thresholds and the confusion matrix.

Run `index.py` afterwards.

On 2026-11-24 it trained on 14,095 patches and guessed 7,598:
- **Overall:** held-out accuracy 57.4% with logistic regression (the network 52.7%, neighbours 50.1%). Without the arp labels (mostly the arpeggiator setting, easy to tell) it is 49.4%. Regularisation and class balancing moved it by under 1 point.
- **Sure guesses:** 1,118, in bass (506), pad (281), lead (151), perc (118) and arp (36).
- **Never sure:** keys, pluck, bell, strings, brass, organ, woodwind, fx and voice never reach 80% precision, so their guesses always show as unsure. The browser still shows the guess, with "?", and the second guess in the detail.
- **Why:** the confusions are what you'd expect from three plain notes. Strings land in pad, plucks in keys, brass across bass, pad and keys, and voice in pad.
