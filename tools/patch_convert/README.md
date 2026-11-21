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

**Caveats.** `dx7render` zeroes each note's engine state (LFO phase, sample-and-hold state, feedback buffer), so the references are reproducible. The one caveat left is feedback 7, which can be chaotic: float and msfa's integers can drift apart, and noise voices (snares, Train, Wasp Sting) can't be matched sample by sample. Weak voices without a caveat are quiet ones, where the 16-bit reference is the limit (an error floor near −95 dBFS).

## Synth1

1. **Catalogue.** The prep tool (`tools/open_samples_prep`) writes a sidecar per `.sy1` with every parameter named (`content.synth1`).
2. **Reference renders.** `D:/tools/dawdreamer/venv/Scripts/python.exe -I tools/patch_convert/render_synth1.py [library] [--jobs n] [--force]` renders each patch with Synth1 itself, through DawDreamer, as `render_synth1_v100.wav` (16-bit stereo) and adds `content.render_synth1` to the sidecar. Default library: `D:/12_library/gak/processed_synth1`. The layout is the DX7 one: notes 36, 48, 60, 72 and 84 at velocity 100, each held 2 s, released for 2.5 s, then 0.25 s, at 48 kHz and 120 bpm. Unchanged patches are skipped.

**How it renders, and why.**
- Synth1 under DawDreamer crashes (an access violation) as soon as two voices sound at once: a plain chord on a fresh instance, or a note starting while the last one still releases. So each note renders alone, on a fresh instance, for its own slot (a tail longer than the slot is cut there), and the slots are joined. A fresh instance per note also means nothing carries over between notes or patches.
- Each patch renders in its own process, several at once (`--jobs`), so a crash costs only that patch. A poly arpeggiator whose steps overlap still crashes; such a patch is rendered again in mono mode and flagged (`forced_mono`, and a note): its steps cut each other's release.
- Synth1 can go well past full scale. A render louder than that is scaled down to fit and the file records `scale`: divide by it for Synth1's real level.
- Synth1 isn't repeatable sample by sample (free-running oscillators unless "osc phase" is set; noise, unison and S&H are random), so the check compares loudness envelopes and spectra, not samples.
- About 4.6 MB per patch: 3.3 GB for the 713-patch subset, about 76 GB for all 16,706.
