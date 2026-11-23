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
