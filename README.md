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

Phases 0 (foundations) and 1 (voices, palettes, motion kit bridge) are in place; music (the pattern sequencer) is next. See `docs/HANDOFF.md` for what's built, measured performance and the plan. For an LLM working with the kit: `skills/godot-audio-kit/SKILL.md`.

## Pieces

| Piece | What it is |
| --- | --- |
| `AKRecipe` | A sound as data: voice layers, effects, transforms, seed, and `bind` rules mapping a cue's intensity and data onto parameters |
| `AKVoice` | A synthesis voice with a documented parameter schema: `whoosh`, `tone`, `boing`, `click`, `pluck`, `mallet`, `ratchet`, `static`, `follow` |
| `AK` | Render and bake recipes, render cue sheets into a mix plus stems with a shared reverb send, effects and transforms |
| `AKCueMap` | Cue names to recipes (exact, `prefix*`, `*`, as in the motion kit's `MotionCuePlayer`), master effects, shared reverb |
| `AKCueBridge` | Scores a Motion Kit composition: bakes its cue sheet into one track locked to the picture, or plays cues as events. The motion kit stays optional |
| `AKPalette` | Named values recipes reference as `"$name"`; shipped: supergraphic, print, signal |
| `AKVocab` | Words to parameter moves ("brighter", "drier", "punchier"...) from `vocabulary.json` |
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

## Comparing with a reference

```
python3 tools/compare/compare.py out/review/e1/mix.wav reference.wav demo/cues/e1_supergraphic.json out/compare/e1
```

Hit agreement per cue, band balance and side-by-side spectrograms. The E1 Supergraphic port (`demo/cues/e1_supergraphic.json`, `demo/recipes/supergraphic/`) is the worked example.

## Motion kit demos

`tools/link_motion_kit.sh` links a local motion kit checkout into `addons/motion_kit` (git-ignored) for the bridge tests and `demo/with_motion_kit/bridge_demo.tscn`.

## Tests

```
godot --headless --path . --script res://tests/run_tests.gd    # correctness, determinism
godot --headless --path . --script res://tests/perf.gd         # bake timings
```

## Licence

Apache-2.0. See `LICENSE` and `NOTICE`.
