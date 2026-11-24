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
