---
name: godot-audio-kit
description: Make procedural sound effects in Godot 4 with the Godot Audio Kit addon (synthesised, no samples) and score Godot Motion Kit pieces from their cue sheets, from a sound sheet to a reviewed, measured soundtrack. Use for idents, intros, UI and game sounds, and any motion piece that needs sound.
---

# Making sound in Godot with the Audio Kit

The Godot Audio Kit (`addons/audio_kit`, repo `csmallfield/godot-audio-kit`) is a
pure-GDScript addon that synthesises sound from **recipes**: small text resources naming
voices, parameters, effects and a seed. Recipes bake deterministically to audio. A
**cue map** says which recipe plays on which cue, and a Godot Motion Kit composition's
**cue sheet** says when; the kit renders one sample-accurate track per piece.

You cannot hear what you make. The kit is built for that: every render can be measured
(loudness, peaks, placement, onsets, clutter, a clean ending) and pictured (spectrograms
with cue markers). Timing and level are proven by numbers; whether it sounds right is
the person's call, and you say so.

The repo's `docs/voices.md` lists every voice parameter (generated from the code) and
`docs/HANDOFF.md` describes the current state. Read them when the repo is available.

## 0. Before starting

- Check the project has `addons/audio_kit/` with the plugin enabled. If not, copy the
  folder from the repo, plus `tools/analyze/` (and `tools/compare/`, `tools/write_recipes.py`).
- The review analysis needs Python 3 with numpy, scipy and matplotlib.
- Find the Godot 4.5+ binary. Rendering sound needs no display: everything runs headless.
- For a motion piece, find its composition script and its cues (`cue(frame, name,
  intensity, data)` calls; the motion kit skill tells the motion side to declare them).
  If the piece has no cues yet, add them from its beat-sheet constants in the
  composition, not as a separate list, so picture and sound share one number.
- Look for existing recipes, cue maps and palettes in the project before writing new ones.

## 1. The sound sheet

Before any recipe, write a short sound sheet: one line per cue name, what it should
sound like in plain words, and which voice plays it. Pick a palette (section 6) for the
family. For example:

```
# Sound (palette: supergraphic, shared reverb 0.45):
#   wipe.*      airy whoosh building into the cover, a bit different each time
#   m.land      springy boing, mid pitch, small sub
#   letter      rising plucks, one per letter, soft and short
#   land.S/C/F  pitched boings with a sub thump, S < C < F
#   node        quick metal mallet notes climbing a pentatonic scale
#   launch      upward glide plus whoosh as each disc leaves
```

Say where music will go. The kit has no sequencer yet (phase 2); until then an
authored piece is effects only, or a supplied music file goes on the composition.

## 2. Recipes

A recipe is an `AKRecipe` `.tres` (or built in code with `AKRecipe.make`):

```
voice = &"boing"
params = {"start_hz": 260.0, "end_hz": 82.0, "decay_s": 0.22, "sub": 0.7, "click": 0.4}
layers = Array[Dictionary]([{"voice": &"click", "params": {"freq_hz": 2500.0}, "gain_db": -10.0}])
fx = Array[Dictionary]([{"type": "lowpass", "cutoff_hz": 6000.0, "slope_db": 24.0}])
bind = {"intensity": {"gain_db": [-8.0, 0.0]}, "data.pitch": "pitch_scale"}
vary = {"decay_s": 0.1}
send = 0.2
seed = 18
```

- **voice / params / layers.** Unset parameters take the voice default. Layers sum with
  the main voice; layer `offset_s` must be ≥ 0.
- **bind.** `intensity` maps names to `[at 0, at 1]`; `"data.<key>"` copies a cue data
  value. Targets: `gain_db`, `pan`, `send`, `pitch_scale` (multiplies every `*_hz`), any
  voice parameter, any effect parameter, or `fx<i>.<param>`. One recipe then covers every
  hit of its kind: pitch the letters by putting `pitch` in each cue's data.
- **vary.** Seeded per-hit spread (0.1 = up to ±10%). Use it for anything that repeats
  (plucks, ticks, whooshes) so repeats don't sound copy-pasted. Repeats stay identical
  between renders.
- **send.** How much feeds the cue map's shared reverb. Prefer this to a `room` effect on
  each recipe: it costs one reverb per track, and the sounds sit in one space.
- **offset_s.** Where the sound starts relative to its cue. Sample 0 of every voice is
  its cue: hits need nothing. A swell that should peak on the cue (a reversed sound, a
  riser) gets a negative offset of about its length.
- **"$token" values** come from the recipe's palette (section 6).
- **Effects** (`fx`, in order): lowpass, highpass, bandpass, notch (`cutoff_hz`, `q`,
  `slope_db` 12/24), lowpass1, highpass1, drive, bitcrush, room (`quality` small/full),
  echo, gain, limit, normalize, loudness, dcblock.
- **Transforms** (after effects): reverse, fade, varispeed (`from`→`to` rate; 1→0 is a
  tape stop), width, trim. An outro that runs the build-in backwards is the same recipe
  with `reverse` and a negative offset.

For a batch, write a small Python script with `tools/write_recipes.py` (see
`demo/recipes/supergraphic/make.py`) so the set stays editable as one file.

## 3. Voices: which one for what

| Sound | Voice | Key parameters |
| --- | --- | --- |
| Whoosh, wipe, swish, pass-by | `whoosh` | `length_s`, `low_hz`/`high_hz`, `peak`, `noise` |
| Beep, blip, chime, line-up tone, pop, rising/falling glide | `tone` | `wave`, `freq_hz`, `end_hz` + `glide_s`, ADSR |
| Hit, thump, landing, boing, kick-like | `boing` | `start_hz`→`end_hz`, `drop_s`, `wobble_hz`, `sub`, `click` |
| Tick, clack, key, stamp, snap | `click` | `freq_hz`, `mode`, `q`, `decay_s`, `body_hz` |
| Pluck, harp, muted ping | `pluck` | `freq_hz`, `brightness`, `decay_s`, `tone_hz` |
| Marimba, glockenspiel, vibes, glass, UI ping | `mallet` | `freq_hz`, `material`, `hardness`, `decay_s` |
| Ratchet, zip, gear, stepped slide, film rattle | `ratchet` | rates, `click_hz`, `jitter`, `accent_every` |
| Static, radio noise, crackle, decoding glitch | `static` | `hiss`, `color_hz`, `crackles_per_s`, `flicker_hz` |
| A sound tracing a motion (scope, needle, bar) | `follow` | `pitch` / `level` breakpoints `[[s, value], ...]` |

Musical pitch: equal temperament, A4 = 440 Hz; a semitone is ×1.05946, a fifth ×1.4983,
an octave ×2. Pentatonic runs (0, 2, 4, 7, 9, 12 semitones) are safe for rising sequences.

## 4. Cue map and the piece

An `AKCueMap` maps cue names to recipes: the exact name, then the longest `prefix*`,
then `*` (as the motion kit's `MotionCuePlayer`). Its `master_fx` default removes DC,
sets −16 LUFS and limits at −1.5 dB; its `reverb` dictionary sets the shared space.

To score a composition, add an `AKCueBridge` child with the cue map:

- **BAKED** (authored pieces, the default): renders the whole cue sheet into one track,
  puts it on the composition's `audio` player and sets `clock = AUDIO`. In the editor,
  press **Bake track** in the inspector so the game never renders at runtime.
- **EVENTS** (interactive UI): plays cues as they fire, within a mix buffer; no shared
  reverb; negative offsets start the sound part-way in.

Without a composition, call `AK.bake(recipe, intensity, data)` for an `AudioStreamWAV`,
or `AK.render_cues(cues, map, fps, length_s)` with cues in the motion kit's
`export_cue_sheet()` shape.

## 5. Review: measure, look, fix

Export the piece's cue sheet (`composition.export_cue_sheet("res://.../piece.json")`, or
write one), then:

```
godot --headless --path . -s res://addons/audio_kit/tools/review.gd -- \
    --cues demo/cues/piece.json --map res://sfx/piece_map.tres --out out/review/piece
```

Read `report.md`, then look at `spectrogram.png` (cue lines over the whole mix) and
`cues.png` (one small spectrogram per hit). A single recipe: `--recipe res://...tres`.

| Report says | Usually means | Fix |
| --- | --- | --- |
| Loudness off target | master chain missing loudness | add `{type: loudness}` before the limiter |
| True peak above −1 dBTP | limiter ceiling at −1 or higher | ceiling −1.5 dB |
| Placement error > 1 ms | a hit moved, or overlapped tails confused the measure | check offsets; overlaps are reported, not failed |
| Long lead-in on a hit | the voice fades in (attack, bump) | intended for swells; otherwise shorten attack |
| Many hits peak late | slow envelopes, or whooshes (expected) | punchier, or move the cue earlier with `offset_s` |
| Clutter pairs | two sounds within 40 ms | drop one, or lower the lesser hit |
| Clean ending fails | a tail runs over the last frame | shorten the last tails or the reverb (`tail_s`) |
| DC offset | low sub-sines, Karplus noise | keep `dcblock` in the master chain |

To compare with a reference soundtrack:
`python3 tools/compare/compare.py out/review/piece/mix.wav ref.wav piece.json out/compare/piece`
(hit agreement per cue, band balance, side-by-side spectrograms). "Close enough" is a
judgement; a reference with music under it registers fewer hits.

## 6. Palettes and vocabulary

Palettes (`addons/audio_kit/palettes/`): **supergraphic** (springy, pitched, bright),
**print** (dry, mechanical, no reverb), **signal** (broadcast tones, static, lo-fi).
Recipes reference their tokens as `"$root_hz"`, so a new family is a new palette file
and the recipes restyle with it.

Turn notes into moves with `AKVocab.apply(recipe, ["brighter", "drier"], amount)`
(returns a new recipe). Words: brighter / darker, punchier / softer, wetter / drier,
grittier / cleaner, longer / shorter, higher / lower (two semitones), louder / quieter,
tighter / looser, metallic / woody, gamey. Use half steps (`amount` 0.5) for "a bit".

## 7. Handing over

- Deliver the track (or the scene with the bridge, baked), the recipes and the cue map,
  and the review folder.
- Say what you verified (placement, loudness, peaks, clean ending) and what you could
  not (whether it sounds good). Ask the person to listen, and turn their notes into
  vocabulary moves or recipe edits, then review again.
- When a timing changes, change the composition's constant: the cue moves with it, and
  the bridge's cached track rebakes because its hash changed.
