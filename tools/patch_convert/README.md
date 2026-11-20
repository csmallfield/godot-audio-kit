# patch_convert

Direct conversions of synth patch formats into `AKPatch`, checked against reference renders. See `docs/plans/synth-expansion.md`.

## DX7

1. **Reference renders.** `python tools/patch_convert/render_msfa.py [library]` renders each DX7 voice in a prep-tool library (`tools/open_samples_prep`) with msfa's FM engine (Dexed's "Modern" engine, Apache-2.0) as `render_msfa_v100.wav`. It uses the layout in the sidecar's `content.render`, and needs `D:\tools\dx7render\dx7render.exe`, which the prep tool builds.
2. **Convert and check.** `godot --headless --path . --script res://tools/patch_convert/dx7_batch.gd -- [library]` writes `gak_patch.tres` and `gak_report.json` beside each sidecar, and `gak_dx7_summary.json` in the library. The report holds the SNR per note against the msfa render, plus caveats.

`dx7.gd` maps each DX7 operator to oscillator N:
- the frequency through `dx7_freq`;
- the algorithm through `fm` lists from `AKPatchLib.dx7_algorithm`, and `feedback` = 4π / 2^(8 − feedback);
- each operator's amplitude block onto its own `dx7` envelope (env2–env7, through `level_env`);
- the pitch envelope onto env8 (`dx7_pitch`), and the LFO onto `lfo1` (`mode = "dx7"`);
- the gain to 1/8, as `dx7render` scales its output.

**Caveats.** `dx7render` doesn't initialise each note's LFO state or feedback buffer. Voices that depend on them (unsynced or sample-and-hold LFOs, feedback 7) are flagged, because their reference isn't reproducible.
