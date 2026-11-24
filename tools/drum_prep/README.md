# drum_prep

A dev tool (not shipped in the addon). It turns a collection of drum sample ZIPs, one per
machine, into plain WAV folders, with a manifest for each machine and a catalog for the
whole collection. GAK's drum library is built from this output.

The aim, as with `open_samples_prep`, is to *keep everything and decide nothing*:

- **Lossless.** Sample bytes are copied, never re-quantised. Each file keeps its native
  rate, bit depth and channel count. AIFF is only byte-swapped into WAV. MS ADPCM is the
  one thing decoded (to 16-bit, matching ffmpeg bit for bit), because nothing else reads it.
- **Accountable.** Every output file lists the ZIP members it came from (with their SHA-256)
  and every change made to it. Nothing is dropped without a manifest line saying why and
  what was kept.

The source ZIPs are only read. The output goes to a folder outside them.

## What it does to each machine

| Step | Rule |
|---|---|
| Read | Every member whose first bytes are WAV or AIFF, whatever its extension (the Roland SPD-8 set has AIFF files named `.wav`). Other files are copied to `_extra/` (text, images, Akai `.akp` programs). macOS `__MACOSX` / `._` files are skipped. |
| Identical channels | A stereo file whose two channels are byte-identical becomes mono. Nothing is lost, and it takes half the space. |
| Split stereo | `Name-L` + `Name-R` (or `Name L`, `Name_L`, `Name 1L`) in one folder, both mono, with the same format and length, become one stereo `Name.wav`. Pairs that don't qualify are listed under `lr_not_joined`. |
| Quirks | Per machine, in `dp/machine.py` `QUIRKS`. The Alesis D4 has a short cut of each sound in its root folder beside the full one in a category folder; the short cut is dropped. |
| Duplicates | Exact duplicates (same samples and format) **in one folder** are dropped, keeping the plainest name. Copies in other folders stay, because a machine's kit folders share sounds. The catalog's `same_as` links copies anywhere in the collection. |
| Layers | `Name [V1]`, `Name [V2]` … (Roland BK-5) are tagged as velocity layers of `Name`: `layer = {group, index, of}`. |
| Kind | `loop` when the path says so (loop, bpm, groove, pattern, break, beat, fill), `long` for 8 s or more, else `oneshot`. This is a guess from the name; later steps refine it. |
| Markers | A WAV `smpl` or AIFF `INST` root note and loop are kept: in the manifest, and as a `smpl` chunk in the written WAV. |

## Output

```
<out>/
  catalog.json, catalog.csv      every file in the collection, one row each
  <Machine>/
    manifest.json                files, dropped, failed, extra, lr_not_joined, stamp
    <the machine's folders>/<sound>.wav
    _extra/…                     non-audio members
```

A manifest `files` entry holds `path`, `sources` (`member`, `sha256`, `bytes`), `rate`,
`bits`, `float`, `channels`, `frames`, `seconds`, `peak_dbfs`, `kind`, `kind_reason`,
`content_sha256` (of the format and samples), `source_format`, and when known `root_note`,
`loop`, `layer`, `notes` (what was done) and `duplicates` (members dropped in its favour).

## Usage

```bash
python -I tools/drum_prep/prep_drums.py --source "D:/12_library/gak/to_process_drums" --out "D:/12_library/gak/processed_drums/drum-machines-collection" --collection-name "drum machine samples" --collection-url "https://archive.org/details/drum-machines-collection" --license-note "No licence stated on the archive.org item; personal use."
```

| Option | |
|---|---|
| `--source DIR` | Folder of `<Machine>.zip` files (read only). |
| `--out DIR` | Output folder for the collection. Refused if inside the source or containing it. |
| `--only GLOB` | Machines (ZIP name without `.zip`) to do. Repeatable. The catalog still covers every machine already converted. |
| `--workers N` | Machines converted in parallel (default: half the CPUs, at most 4). |
| `--force` | Redo machines even when unchanged. Otherwise a machine is skipped when its manifest's stamp (tool version, ZIP size and time) matches. |
| `--dry-run` | Convert in memory and print each machine's summary; write nothing. |
| `--collection-name`, `--collection-url`, `--license-note` | Recorded in the catalog. |

A rerun of a machine replaces its output folder, which belongs to this tool.

Tests (standard library only):

```bash
python -m unittest discover -s tools/drum_prep/tests
```

## Name tags

`tag_names.py` reads the converted collection's `catalog.json` and writes `tags.json`
beside it: for each file a `name` section with what its name says. Later steps add their
own sections (analysis) to the same file; re-tagging keeps them.

```bash
python -I tools/drum_prep/tag_names.py --out "D:/12_library/gak/processed_drums/drum-machines-collection"
```

| Field | |
|---|---|
| `category` | `kick`, `snare`, `rim`, `clap`, `hat`, `cymbal`, `tom`, `perc`, `fx`, `vox`, `loop`, `tonal`, or "" when the name doesn't say |
| `kind` | Finer: hats `closed`/`open`/`pedal`, toms `low`/`mid`/`high`/`floor`, cymbals `crash`/`ride`/`ride_bell`/`china`/`splash`/`gong`, percussion `conga`, `cowbell`, `shaker` … with `:high`/`:low`/`:mute`/`:open` when the name gives it |
| `by` | `file` (its own name), `folder` (a folder it's in), `map` (the machine's name map) |
| `words` | What decided it. Ends in `~` for a piece of a run-together word (`Ambcrsh1`), `!` for a one-letter code (`78_K`, `Clsd_H2`) |
| `confidence` | `high` for a whole word in the file's name, `medium` for a folder, word piece or letter code, and a map rule's own |
| `also` | Other categories the name mentions |
| `settings`, `key` | From a map: knob settings (TR-909) or the MIDI key (key-sampled kits) |

How a name is read (`dp/names.py`): split into words at punctuation, camelCase and digits;
pairs (`bass drum`, `hi hat`, `ride bell`) before single words and abbreviations (`BD`,
`SD`, `HH`, `CH`, `OH`, `LT`, `Kik`, `Snr`, `Prc`, `Cym` …); then pieces of run-together
words; then a one-letter code after a word (Roland R-8 style `_K`, `_S`, `_T`, `_H`; `_C`
only after a short code word, since `Drums_C2` is a note). A bare slot like `T03` is never
a code, and a folder that says otherwise beats a letter code. Yamaha's "voices" (patches)
are not vocals. The file's own name wins over its folders.

**Name maps** (`name_maps/<Machine>.json`) cover sets whose names are codes. Each rule is a
regular expression on the path inside the machine. It gives a category and kind, or reads
a General MIDI key (`gm_key`: the MIDI note of octave 0's C). The first matching rule wins.

| Machine | Scheme | Source |
|---|---|---|
| Roland TR-909 | Set1: voice letters plus knob settings (`BT3A0D7` = kick, tune 3, attack 0, decay 7; `ST3T0S3` = snare, tune/tone/snappy; `LT/MT/HT` toms; `HHC/HHO` hats; `CSH` crash; `RIDE`; `RIM`; `HANDCLP`; `CLOP/OPCL` hat transitions) | Jason Baker's 1995 set readme (Rob Roy Recordings, via machines.hyperreal.org; Aminet `mods/smpl/tr-909`) |
| Korg Triton | Kits sampled key by key (`<time>_c27f0000` = C2); Korg octaves (C2 = 36), then the GM drum map. `BD kit` is all kicks; the BD & SD and percussion kits are low confidence | Checked by measuring: C2 dull, D2 bright, F♯2 a short bright hat, C♯3 a long crash |
| Yamaha RS-7000 | The same, with Yamaha octaves (C1 = 36) | Checked the same way |
| Roland MV8800 | The kit folders' codes: `Hcl/Hop/Hpd` hats, `K` kick, `S`+number snare, `Stk` side stick, `TL/TM/TH` toms, `Crs` crash, 808 `Clvs`/`Mcs` | Read from the set; no published key |

Run on the drum-machines collection: 37,387 of 48,245 files (77.5%) tagged by name.
Most of the rest are numbered slots (`01.wav`, `smpl0001.wav`, `Sample 0131`), with
evocative names (`Deep Low`, `Claptrap`) after them; analysis takes those.

## Analysis

Two steps after the name tags. Both need numpy.

```bash
python -I tools/drum_prep/measure_drums.py --out "D:/12_library/gak/processed_drums/drum-machines-collection"
python -I tools/drum_prep/classify_drums.py --out "D:/12_library/gak/processed_drums/drum-machines-collection"
```

**`measure_drums.py`** measures every file into `analysis/features.json`, keyed by path
with the file's content hash; unchanged files aren't measured again. All 48,245 take about
1½ minutes. For each file (mixed to mono, the first 3 s) it records:

- length, attack, decay to −20 and −40 dB, and the level 20–800 ms after the peak
- later onsets (loops, flams)
- spectral centroid, roll-off, flatness, zero-crossing rate and 8 band shares, for the hit (0–80 ms) and the body (80–400 ms)
- 16 log-spaced bands in three windows (transient, hit, body)
- pitch early and late, with the drop between them
- bandwidth and stereo width

**`classify_drums.py`** learns from the files whose names say what they are and tags the rest:

- **Training:** files tagged by their own name or a map count fully, by a folder at half
  weight. Three numpy models (logistic regression, an MLP, k-nearest-neighbours) are tested
  in five folds with whole machines held out, so a machine is only judged by a model that
  never heard it. The best is kept.
- **Sure:** for each category, the probability above which held-out precision reaches 80%
  becomes its "sure" line. Confidences are rescaled so that line sits at 0.8.
- **Kinds:** further models choose the kind for hats (closed/open/pedal), cymbals and
  percussion.
- **Output:** it writes an `analysis` section into each file's entry in `tags.json`:
  `category`, `confidence`, `second`, `kind`, `pitch_hz`/`note` when pitched, `describe`
  (plain words), and `agrees` (with the name).
- **Final tag:** a `final` section holds the tag to use. The name's tag wins unless the name
  was only a guess (folder, word piece, letter code, a medium or low map rule) and the sound
  is sure otherwise. Without a name, the sound's tag is used when its confidence is at least
  0.5, and `sure` says whether it reached 0.8.
- **Report:** `analysis/report.md` has the held-out accuracy per model, per-category
  precision and recall, the confusion matrix, the result counts, and the names the sound
  disagrees with most confidently. Those disagreements are a good list for fixing name
  rules.
- **Descriptive words** (`describe`): `short`/`medium`/`long` (decay to −40 dB), `very long`,
  `dark`/`bright` (against the same category's 25th and 75th percentile), `punchy`,
  `pitched`, `falling pitch`, `noisy`, `lo-fi` (a sample rate under 30 kHz, or no highs in a
  sound that should have them), `stereo`, `roomy`, `several hits`. `--describe-only`
  recomputes these without retraining.

First run on the drum-machines collection:

- **Categories:** 72.2% held out (MLP). Kicks 86% precision / 90% recall, snares 75/79,
  toms 74/78, hats 72/74, cymbals 69/72, percussion 67/68, claps 69/71, rims 53/35. Fx,
  vox, loop and tonal never reach the sure line, so their guesses stay unsure.
- **Kinds:** hats 85%, cymbals 74%, percussion 66%.
- **Coverage:** final tags for 46,637 of 48,245 files (43,158 sure), 1,608 without one.

## Kits

`build_kits.py` turns a tagged collection into drum kits: one JSON file per kit in
`<collection>/kits/<Machine>/`, and `kits/index.json` listing them. It replaces its own
`kits/` folder each run.

```bash
python -I tools/drum_prep/build_kits.py --out "D:/12_library/gak/processed_drums/drum-machines-collection"
```

| Kit | How it's made |
|---|---|
| **folder** | A machine's own kit folder becomes a kit with every sound in it. A kit folder holds a kick, a snare or clap and a hat, and isn't mostly effects, voices, loops or tonal sounds. Rows follow GAK's order (kick, snare, clap, closed/open/pedal hat, toms low to high by measured pitch, crash, ride, rim, then percussion by kind, then the rest). Repeats are numbered: `kick`, `kick_2` … |
| **assembled** | Up to 8 per machine (as many as it has kicks and snares), in the shipped kits' 13 rows. Kit *n* takes the *n*-th best sound of each row. Best means: name and sound agree, then a sure name, a sure sound, then unsure ones. Each row prefers sounds from the kick's own folder, then sounds sharing its style word ("Pop Kick" with "Pop Snare"). Kicks whose style fills the most rows lead. Toms are the ones named as toms when there are three or more, spread low to high. An open hat that's a closed-to-open transition comes after real open hats. Loops stay out. |
| **percussion** | A machine with 8 or more percussion sounds of 3 or more kinds: one piece per kind, then seconds, up to 16. |
| **all** | A machine nothing else makes a kit of (a clap box, a drum pad): all its sounds, up to 64, in row order. |

Pieces follow `AKKit`'s keys:
- **Sound:** `sound` (a path inside the collection), or `layers` for a velocity-layer group
  (`Name [V1]` … as one piece, `up_to` evenly spaced).
- **Mix:** `gain_db` sets each sample's peak to −3 dBFS, then applies the row's offset as the
  shipped kits do (kick −1, snare −3, clap −4, hats −9 to −11, toms −5, crash −10, ride −12,
  percussion −9/−10). `pan` is as the shipped kits for mono samples, `choke = "hats"` for the
  three hats.
- **Tags:** `category`, `kind` and `sure` carry the final tags along.
- **Kit level:** the kit file has `name`, `machine`, `from`, `folder`, `root` (the collection,
  relative to the file: `../..`) and `sure_share` (the share of pieces with a sure tag).

GAK loads a kit file with `AKKit.load_json(path)`. Its samples decode from the WAVs on first
play, so the library must stay where it is. Kits sharing a file share its sample.

First run on the drum-machines collection: 2,431 kits from all 470 machines. Of these, 266 come
from the machines' own folders, 1,951 are assembled, 191 are percussion kits and 23 are
all-sounds kits; 28 pieces are velocity-layered.
