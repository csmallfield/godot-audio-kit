# Godot Audio Kit

Procedural sound for Godot 4.5+: sounds written as recipes, baked deterministically to audio, placed exactly on the cues a [Godot Motion Kit](https://github.com/csmallfield/godot-motion-kit) composition fires, and checked by measurement rather than by ear.

No samples, no licences: everything is synthesised from code.

```gdscript
var hit := AK.bake(load("res://sfx/hit.tres"))          # AudioStreamWAV, cached
$Player.stream = hit

var sheet := AK.load_cue_sheet("res://cues/ident.json")  # from MotionComposition.export_cue_sheet()
var out := AK.render_cues(sheet.cues, load("res://sfx/ident_map.tres"), sheet.fps)
out.mix.save_wav("res://out/ident.wav")
```

## Status

Phase 0 (foundations) is in place. See `docs/HANDOFF.md` for what's built, measured performance and what comes next. The design document lives as a Claude doc; the summary is in `docs/HANDOFF.md`.

## Pieces

| Piece | What it is |
| --- | --- |
| `AKRecipe` | A sound as data: voice layers, effects, transforms, seed, and `bind` rules mapping a cue's intensity and data onto parameters |
| `AKVoice` | A synthesis voice (`whoosh`, `tone`, `boing`, `click`, `pluck` so far), with a documented parameter schema |
| `AK` | Render and bake recipes, render cue sheets into a mix plus stems, effects and transforms |
| `AKCueMap` | Cue names to recipes (exact, `prefix*`, `*`, as in the motion kit's `MotionCuePlayer`), plus master effects |
| `AKPalette` | Named values recipes reference as `"$name"`, so a family of sounds can be restyled at once |
| `AKDsp`, `AKOsc`, `AKNoise`, `AKEnv`, `AKFilter`, `AKDelay`, `AKShape`, `AKReverb`, `AKDynamics` | The DSP building blocks |

Voice parameters: `docs/voices.md` (generated from the code).

## Review renders

One command renders a cue sheet and measures it: loudness (BS.1770), true peak, clipping, cue placement, perceived onsets, clutter, a clean ending, plus a spectrogram with cue markers and a strip of per-cue spectrograms.

```
godot --headless --path . -s res://addons/audio_kit/tools/review.gd -- \
    --cues demo/cues/race_ident.json --map res://demo/recipes/race_ident_map.tres \
    --out out/review/race_ident
```

Output in `out/review/race_ident/`: `mix.wav`, `stems/`, `report.md`, `report.json`, `spectrogram.png`, `cues.png`. The analysis needs Python 3 with numpy, scipy and matplotlib.

## Tests

```
godot --headless --path . --script res://tests/run_tests.gd    # correctness, determinism
godot --headless --path . --script res://tests/perf.gd         # bake timings
```

## Licence

Apache-2.0. See `LICENSE` and `NOTICE`.
