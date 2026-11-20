# open_samples_prep

A dev tool (not shipped in the addon) that prepares the
[Open Samples](https://github.com/pumodi/open-samples) collection for Godot Audio Kit:

- **Sampler instruments** that GAK can't read (Kontakt `.nki`/`.nkm`, Logic `.exs`,
  SoundFont `.sf2`) are converted once with
  [ConvertWithMoss](https://github.com/git-moss/ConvertWithMoss) into WAV plus SFZ, plus a
  DecentSampler preset.
- **Every instrument** in the collection, plain WAV included, gets an `instrument.json`
  sidecar, a `README.txt` and an entry in `catalog.json` / `catalog.csv`.

The aim is *keep everything, decide nothing*. Samples keep their original rate, bit depth
and channel count. The mapping is written in the formats that keep the most. The sidecar
records where everything came from and what could not be carried over. A future importer
can then work from this output without running the conversion again.

The source collection is only read. The output goes to a folder outside it.

It began with Open Samples but works on any collection. It also handles **DX7 voice banks**
(`.syx`): it renders every voice to held notes through Dexed's DX7 engine and keeps the full
patch data. It reads **sampler disk images** (Ensoniq Mirage and others) through
ConvertWithMoss. See [Other collections](#other-collections-soundarchive).

## Requirements

- Python 3.9+ (standard library only).
- ConvertWithMoss 20.x for the conversions. On this machine it is at
  `D:\tools\ConvertWithMoss\ConvertWithMoss\ConvertWithMossCLI.exe`. It was installed from
  the official 20.3.0 installer as an administrative (files only) MSI install. It carries its
  own Java runtime. Point to another copy with `--cwm` or the `OSP_CWM` environment variable.
  Plain-WAV entries and `--dry-run` don't need it.

## Usage

```bash
python tools/open_samples_prep/prep.py --source "D:/12_library/gak/to_process/Open Samples" --out "D:/12_library/gak/processed"
```

| Option | |
|---|---|
| `--source DIR` | Root of the collection (read only). |
| `--out DIR` | Output root. Refused if it is inside the source or contains it. |
| `--cwm PATH` | `ConvertWithMossCLI.exe`. Default: `OSP_CWM`, then the path above, then `PATH`. |
| `--workers N` | Conversions run in parallel. Default: half the CPU count, at most 4. |
| `--only GLOB` | Work only on sources whose collection-relative path (with `/`) matches. A folder path selects everything under it. Repeatable. The catalog still lists every instrument; ones never processed show as `pending`. |
| `--exclude GLOB` | Leave out matching sources (same matching as `--only`). They show in the catalog as `excluded`, and their `.ncw` files aren't reported as unreferenced. Repeatable. |
| `--dry-run` | Print the plan (action, kind, source, output path) and write nothing. |
| `--force` | Redo instruments even when unchanged. |
| `--retry-failed` | Redo unchanged instruments whose last attempt failed or was encrypted. |
| `--copy-wav` | Also copy plain-WAV instruments into their output folder, byte for byte. |
| `--no-decentsampler` | Write only the SFZ. |
| `--timeout S` | Seconds allowed per ConvertWithMoss call (default 3600). |
| `--collection-name`, `--collection-url`, `--license-note` | What to record as the collection, when it isn't Open Samples. |
| `--disk-images FORMAT` | Treat `.img/.hfe/.edm/.ede/.eda/.iso` as disk images of this ConvertWithMoss source format (`mirage`, `ensoniq`, `emax`, `s1000`). |
| `--dx7render PATH` | `dx7render.exe`. Default: `OSP_DX7RENDER`, then `D:\tools\dx7render\dx7render.exe`. |
| `--dx7-notes`, `--dx7-velocities`, `--dx7-hold`, `--dx7-release`, `--dx7-gap`, `--dx7-rate`, `--dx7-engine` | How DX7 voices are rendered. Defaults: keys `36,48,60,72,84`, velocity `100`, 2 s held, 2.5 s release, 0.25 s gap, 48 kHz, engine `mki`. |
| `--collection-version`, `--collection-commit`, `--download-date` | Origin facts to record. The version is otherwise read from the collection README's "Patch Number" badge. The download date is otherwise estimated from the folder's creation time. |

The run used for GAK leaves out the Solo Marching Percussion kit, which is outside GAK's
scope (synthesis, not drum sampling):

```bash
python tools/open_samples_prep/prep.py --source "D:/12_library/gak/to_process/Open Samples" --out "D:/12_library/gak/processed" --exclude "PercussionInstruments/Solo Marching Percussion"
```

More examples:

```bash
python tools/open_samples_prep/prep.py --source "D:/12_library/gak/to_process/Open Samples" --out "D:/12_library/gak/processed" --dry-run --only "Pianos"
```

```bash
python tools/open_samples_prep/prep.py --source "D:/12_library/gak/to_process/Open Samples" --out "D:/12_library/gak/processed" --only "Keyboards" --only "Synthesizers/KorgSynthesizers/Korg M1"
```

Tests (no ConvertWithMoss needed; `tests/fake_cwm.py` stands in for it):

```bash
python -m unittest discover -s tools/open_samples_prep/tests
```

## What counts as an instrument

| Kind | Rule | Status |
|---|---|---|
| `kontakt`, `exs24`, `sf2` | each `.nki`/`.nkm`, `.exs`, `.sf2` file | `converted`, `failed` or `encrypted` |
| `wav-file` | each `.wav` under `Synthesizers/` or `OneShotSamples/`, where one file is one patch | `skipped-wav` |
| `wav-folder` | every other folder that directly holds `.wav` files | `skipped-wav` |
| `unsupported` | `.phaseplant`, `.sitala`, `.nbkt`, `.nkx` | `unsupported` |

`skipped-wav` means the WAVs are usable as they are. They are referenced in place, not converted
or copied unless you pass `--copy-wav`. The collection's own `docs/` folder is skipped, and so
are `__NI_SMPL_ADD__` folders. MP3 demos are not catalogued: the licence reserves all rights
to them.

Kontakt instruments that load their samples from folders (rather than monoliths) read the
`.ncw` files next to them. After the run, `unreferenced_ncw.txt` lists any `.ncw` that no
converted instrument maps, matched by file name, so nothing is silently left behind.

## Other collections: SoundArchive

A pilot on [SoundArchive](https://www.soundarchive.co/), using the Yamaha DX7 factory ROMs (8
banks, 256 voices) and the Ensoniq Mirage factory library (30 disks). The source is
`D:\12_library\gak\to_process\SoundArchive` (the original zips are in `_dl/`). The output is
`D:\12_library\gak\processed_soundarchive`.

```bash
python tools/open_samples_prep/prep.py --source "D:/12_library/gak/to_process/SoundArchive" --out "D:/12_library/gak/processed_soundarchive" --collection-name SoundArchive --collection-url https://www.soundarchive.co/ --disk-images mirage --exclude "Ensoniq Mirage/Ensoniq Factory Library/HFE" --exclude "_dl"
```

The Mirage library ships every disk twice, as `IMG/` and as `HFE/`. Only `IMG/` is converted.
The HFE copies still claim the plain output names, so the converted disks end in `-img`.

### DX7 voices (`dx7-voice`, status `rendered`)

Each `.syx` file that is a DX7 32-voice bulk dump becomes 32 entries. Their source path is
`<bank>.syx#NN NAME`, and their output path is `<folders>/<bank>/<NN-name>/`. Each one holds:

- `voice.syx`: the voice as a standard single-voice dump (163 bytes) that any DX7 or
  emulator loads.
- `render_vNNN.wav`: one render per velocity, mono 16-bit (the engine's own resolution).
  The keys are played in order. Each is held, released and left to ring, then followed by
  silence. `content.render` records `first_note`, `step`, the note on and off times, and the
  voice transpose. GAK's `run_wav(path, first_note, step)` can read it directly.
- `content.dx7`: the packed (128-byte) and unpacked (155-byte) voice as hex. `params` has
  every parameter named: algorithm, feedback, oscillator sync, pitch envelope, LFO,
  transpose, and per operator 1–6 the envelope rates and levels, keyboard scaling, velocity
  and amp-mod sensitivity, output level, ratio or fixed frequency, and detune. It also lists
  the algorithm's carriers and a `sound_sha256` of the voice without its name.
- `catalog.json` marks a voice that sounds the same as an earlier one (same data, other
  name) with `duplicate_of`.

The renderer is `dx7render/dx7render.cpp`, a small driver for Dexed's engine
([asb2m10/dexed](https://github.com/asb2m10/dexed), pinned commit). `dx7render/build.ps1`
fetches the engine sources into `D:\tools\dx7render`, adds stand-ins for Dexed's plugin-only
dependencies, and builds with MSVC. The driver copies Dexed's own processing: the same
inits, 64-sample blocks, LFO handling, output scaling and voice transpose. The default
engine is Dexed's "Mark I", its default and the one closest to the hardware. `--dx7-engine
msfa` selects the original Music Synthesizer for Android core. The licences are msfa
Apache-2.0 and Mark I GPL-3.0. None of Dexed's code is in this repo. Each note starts from
zeroed engine state, because msfa never initialises the LFO's phase and random state or the
note's feedback buffer; without that, renders depend on whatever memory held. Mark I renders
made before this fix weren't re-rendered.

### Korg M3R and Casio CZ (`m3r-program`, `m3r-combination`, `cz-tone`, status `decoded`)

A SysEx file holding an M3R all-data dump (`F0 42 3n 24 4C` programs, `4D` combinations, Korg
7-bit packing) becomes 100 program entries (`<bank>.syx#P00 NAME`) and 100 combination
entries (`#C00`). `osp/korg.py` names every parameter from the M3R manual's Tables 1 and 2:
- **Programs:** oscillator and multisound (with its name), the pitch and cutoff MGs,
  aftertouch and controller routing, the pitch envelope, the VDF and its envelope, the VDA
  and its envelope.
- **Combinations:** type, and the 8 timbres with their program, level, transpose, detune,
  pan, and key and velocity windows. The effects are kept as raw bytes.

Programs on plain waveforms (sine, square, saw, 10% and 20% pulse) have
`direct_candidate: true` and the tag `basic-wave`. Programs whose bytes match an earlier one
(name aside) get `duplicate_of` in the catalog.

A Casio CZ "send tone" dump (`F0 44 00 00 7n 20 60`, nibbles) becomes one `cz-tone` entry
with its 128 bytes of tone data. Naming its parameters is still to do.

No renderer exists for either, so these entries carry data only, no audio.

### Mirage disks (`mirage`)

ConvertWithMoss reads Mirage `.img`, `.hfe` and `.edm` disks. Each disk becomes one entry,
with an SFZ and DecentSampler preset for each of its programs. The samples are the Mirage's
own 8-bit, 29.4 kHz data. Mirage disks don't store root notes, so the root keys in the
mapping are placeholders; the sidecar says so. A `sound_list.txt` beside the disks, with
lines like `SND-A02 | Clav, Electric Piano #1, Drawbar Organ #1`, fills in
`identity.description` and adds tags.

## Files added to the collection later

The local copy came from the older Dropbox release (v1.08). Eight Kontakt instruments that
exist only on GitHub were then added into it at their GitHub paths, together with the samples
they load: Atari Jaguar Raiden Lead, Asahi Bottle Organ, ABS Bucket, Bike Horn, the three
Adufe instruments and Bohemian Upright – Legato. Nothing existing was overwritten. Those
files are listed in `.open_samples_additions.json` at the collection root, with the GitHub
commit, date and sha256 of each. The tool reads that file, and a sidecar whose source is
listed there has `origin.added_from = {source, commit, date, sha256}`.

## Output layout

```
<out>/
  catalog.json             every instrument: status, paths, key fields (schema 1)
  catalog.csv              the same, flat
  failures.txt             status<TAB>source<TAB>reason for failed / encrypted / unsupported
  unreferenced_ncw.txt     .ncw samples no converted instrument uses
  LICENSE-open-samples.md  copy of the collection licence
  logs/run-YYYYMMDD-HHMMSS.log
  .hash_cache.json         sha256 per source file, keyed on size + mtime (speeds up re-runs)
  <family>/<folders...>/<patch>/
      instrument.json      the sidecar (below)
      README.txt           the essentials, for people
      <Name>.sfz           converted only: ConvertWithMoss's SFZ
      <Name>.dspreset      converted only: ConvertWithMoss's DecentSampler preset
      <Name> Samples/*.wav converted only: the samples, ConvertWithMoss's naming
      cwm/analysis.txt     ConvertWithMoss's own per-zone description (-ad), verbatim
      cwm/convert_*.log    console output of each conversion
      samples/             plain-WAV entries with --copy-wav only
```

### Paths

The output path depends only on the source path:

1. Every folder name and the file stem are slugified: NFKD to ASCII, camelCase split, `&` to
   `and`, everything else to `-`, lower case, at most 64 characters. An empty result becomes
   `x-<hash>`. Windows device names get `-x`.
2. Folder names that only describe contents (`Instruments`, `Samples`, `EXS24`, ...) are
   dropped. A segment equal to its parent is collapsed (`Cuica/Cuica.nki` becomes `cuica`).
   Below the family folder, a `...Synthesizers` suffix is dropped (`RolandSynthesizers`
   becomes `roland`).
3. When two sources land on the same path, they are ranked by kind (sampler instruments
   first) and then by source path. The first keeps the path. The others get `-<extension>`
   (`-wav`, `-nki`, `-sitala`, ...), or `-<6-char hash of the source path>` if that is
   taken too.
4. No output folder may contain another one. A path that would be a parent gets the same
   suffix. For example, `pianos/archive-lo-fi-piano-nki` sits beside
   `pianos/archive-lo-fi-piano/samples`.

The rules see the whole collection at once, so the same collection always gives the same
paths. A path changes only if a new file collides with it.

### Re-runs and interruptions

Each instrument has a fingerprint, stored in `processing.fingerprint`. It is the sha256 of
the source hash, the tool version, the schema and the options that affect that instrument,
plus the ConvertWithMoss version for conversions. A re-run skips an instrument whose
fingerprint is unchanged and whose output files still exist, and redoes it otherwise. For a
WAV folder, the source hash covers every WAV in the folder.

Each instrument is built in `<out>/.work/<hash>/` and moved into place in one step, so an
interrupted run never leaves a half-written instrument. Run the same command again to
resume. `catalog.json` is rebuilt from the sidecars at the end of every run.

Kontakt instruments that load samples from a folder are fingerprinted by the `.nki` alone. If
only their `.ncw` files change, use `--force`.

## What ConvertWithMoss is asked to do

Commands, from the docs and `ConvertWithMossCLI.exe -h` (20.3.0):

```
ConvertWithMossCLI -s <nki|exs24|sf2> -d sfz -ad <file> <scratch>          # analysis, kept as cwm/analysis.txt
ConvertWithMossCLI -s <fmt> -d sfz -f -p<SFZ params> <file> <work>         # mapping + samples
ConvertWithMossCLI -s <fmt> -d decentsampler -f -p<DS params> <file> <tmp> # second mapping
```

- **No processing.** `-Ze` is never passed, so there is no resampling, no bit-depth change,
  no loop snapping, crossfades or transposition. Samples come out at the source's rate,
  depth and channel count. NCW is decoded to PCM WAV.
- Destination parameters: `...WriteSampleChunk=true`, `...WriteInstrumentChunk=true`,
  `...WriteBroadcastAudioChunk=false` (the broadcast chunk holds a date and would make
  files differ between runs), `...RemoveJunkChunk=false`, `SFZConvertToFlac=false`, and for
  DecentSampler no bundle, no mono, no added filter. In 20.3.0 the sample/instrument chunk
  options had no visible effect on Kontakt sources. Root keys and loops therefore live in
  the SFZ/DecentSampler mapping and the sidecar, not inside the WAVs.
- `-f` (flat) puts the mapping and its `<Name> Samples/` folder directly in the instrument's
  folder.
- **Why both SFZ and DecentSampler.** On this collection they carry the same mapping.
  SFZ hoists shared values to `<global>`/`<group>` and adds the velocity curve and pitch bend
  range. DecentSampler writes every value on every sample. Where ConvertWithMoss maps
  something to only one of them (group-level filters as DS effects, LFO details), having
  both keeps it. The DecentSampler run's samples are byte-compared with the SFZ run's. When
  they are identical (the normal case) they are shared. Otherwise they are kept apart in
  `decentsampler/` with a warning. The `.dspreset` also contains ConvertWithMoss's default
  UI, delay and reverb template. Those are not from the source instrument, and the sidecar
  says so.

## instrument.json (schema 1)

```jsonc
{
  "schema": 1,
  "id": "keyboards/electric-pianos/wurlitzer-200a-electric-piano",  // = output path
  "status": "converted",   // converted | rendered | decoded | skipped-wav | failed | encrypted | unsupported
                           // (catalog only: excluded | pending)
  "reason": null,          // why, when not converted
  "origin": {
    "collection": {"name", "url", "root", "version", "version_source", "commit",
                   "download_date", "download_date_source", "readme"},
    "source_path": "Keyboards/Electric Pianos/Instruments/Wurlitzer 200A Electric Piano.nki",
    "source_kind": "kontakt",          // kontakt | exs24 | sf2 | wav-folder | wav-file | unsupported
    "format": "Kontakt instrument (.nki)",
    "source_sha256": "...", "source_sha256_of": "file",   // or the folder manifest, for wav-folder
    "source_size": 123456,
    "instrument_root": "Keyboards/Electric Pianos",
    "related_files": {"resources": [".nkc/.nkr/... under the root"], "scripts": ["KSP sources"]},
    "related_instruments": ["ids of sampler instruments that map these WAVs (wav entries)"],
    "notes": [{"path": "README/LICENSE files, nearest first", "text": "their text"}],
    "license": {"name", "path", "sha256", "copy_in_output", "summary"},
    "added_from": null               // or {source, commit, date, sha256} for files added later
  },
  "identity": {
    "family", "family_folder", "folders": [...], "manufacturer", "model", "instrument", "patch",
    // converted only, from the file itself (via ConvertWithMoss):
    "category", "creator", "keywords": [...],
    "names_in_file": {"instruments": [...], "groups": [...], "detected_as": [...]}
  },
  "content": {
    // converted:
    "zones_summary": {
      "zone_count", "root_notes": [...], "key_span": [lo, hi],
      "velocity_ranges": [[lo, hi], ...],
      "velocity_layer_count",        // most distinct velocity ranges on any one key
      "max_zones_per_key_velocity",
      "round_robin": {"seq_length", "groups_named_rr": [...], "max_stacked_zones", "likely"},
      "looped", "looped_zone_count", "release_trigger_zones", "exclusive_groups": [...],
      "groups": [...]
    },
    "samples_summary": {"sample_count", "sample_rates", "bit_depths", "channels", "stereo",
                        "mono", "sample_formats", "total_duration_s", "min_duration_s",
                        "max_duration_s"},
    "features_used": ["Loop", "Amplitude envelope", ...],   // from ConvertWithMoss's analysis
    "presets": [{
      "name", "sfz", "dspreset", "sfz_header": {"creator", "category"},
      "zones": [{
        "index", "sample",                       // path relative to the instrument folder
        "group_index", "group_label", "region_label",
        "root_key", "key_range": [lo, hi], "velocity_range": [lo, hi],
        "fine_tune_cents", "transpose_semitones", "pitch_keytrack",
        "gain_db", "pan", "amp_veltrack",
        "sample_start", "sample_end",            // frames, as in the SFZ (offset / end)
        "loop": {"looped", "mode", "start", "end", "crossfade"},
        "trigger", "release_trigger", "exclusive_group", "off_by", "seq_length", "seq_position",
        "amp_envelope": {"ampeg_*"}, "filter": {"fil_type", "cutoff", "resonance", ...},
        "filter_envelope": {"fileg_*"}, "pitch_envelope": {"pitcheg_*"},
        "lfos": {"*lfo_*"}, "crossfade": {"xfin_*", "xfout_*"},
        "opcodes": {"...": "every SFZ opcode that applies to this zone, merged from <global>/<master>/<group>/<region>, as text"}
      }]
    }],
    "samples": [{"file", "sha256", "format", "format_tag", "channels", "sample_rate",
                 "bit_depth", "frames", "duration_s", "smpl"?, "inst"?, "info"?}],
    // plain WAV:
    "notes_from_names": [48, 60],      // note names in file names, C4 = 60, hints only
    "root_notes_from_smpl_chunks": [], "looped_in_wav": false
  },
  "processing": {
    "tool": "open_samples_prep", "tool_version": "1.0.0", "convertwithmoss_version": "20.3.0",
    "date": "2026-11-20T12:47:16+01:00", "options": {...}, "fingerprint": "...",
    "commands": ["exact command lines"],
    "warnings": ["ConvertWithMoss notes, missing samples, ..."],
    "lost": ["what could not be carried over: KSP scripts, effects, modulation, group start options, ..."]
  },
  "outputs": {"sfz": [...], "dspreset": [...], "samples_dirs": [...], "cwm_analysis", "cwm_logs"},
  "tags": ["flat", "search", "words"]
}
```

`catalog.json` has `schema`, tool and ConvertWithMoss versions, the collection and licence
blocks, `counts_by_status`, `counts_by_kind`, `unreferenced_ncw_count`, and `entries`. Each
entry carries id, status, kind, source and output paths, source sha256, identity fields,
zone and sample counts, root notes, velocity layers, round robin, looped, channels, rates,
depths, total duration, tags, the warning count and the reason.

When the layout changes, bump `SCHEMA` in `osp/__init__.py`. When output content changes,
bump `TOOL_VERSION`; every instrument is then redone on the next run.

## Known limits

- Kontakt scripts (KSP), effects and most modulation are not converted by ConvertWithMoss.
  Every Kontakt sidecar lists this under `processing.lost`. Instruments that ship
  `Resources/` (`.nkc`/`.nkr`) or a KSP source are flagged by name.
- Round robins in Kontakt are usually group start options or scripts. These don't survive.
  Groups keep their names (`rr1`, `rr2`...), and `round_robin.groups_named_rr` /
  `max_stacked_zones` show where they were.
- ConvertWithMoss sometimes fills in a default envelope (for example "Using default volume
  envelope for category 'Piano'"). That line is copied into `processing.warnings`.
- Octave numbers in sample file names are read as C4 = 60 (`notes_from_names`). Sample
  makers differ, so treat them as hints. ConvertWithMoss's `analysis.txt` names notes with
  C3 = 60; the MIDI numbers next to them are what count.
