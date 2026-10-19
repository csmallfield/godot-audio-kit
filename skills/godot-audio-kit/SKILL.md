---
name: godot-audio-kit
description: Make procedural sound and music in Godot 4 with the Godot Audio Kit and score Godot Motion Kit pieces from their cue sheets, from a sound sheet to a measured, reviewed soundtrack.
---

# Making sound in Godot with the Audio Kit

The Godot Audio Kit (`addons/audio_kit`, repo `csmallfield/godot-audio-kit`) is a
GDScript addon, with an optional native core for speed and live mixing, that synthesises sound from **recipes**: small text resources naming
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
- Check for the native core: `addons/audio_kit/native/bin/` holds a library for this
  platform, and `AKLive.available()` is true. Without it, everything still works in
  GDScript, about 14× slower (music renders at roughly real time), and LIVE mode is
  unavailable. Build it with `cd native && scons platform=<linux|windows|macos>
  target=template_debug` (see `native/README.md`), or unzip CI's `audio-kit-native` artifact there.
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

Say where music goes: a song (section 4b) shaped to the piece's sections, or
none. Music under effects should leave room for the hits; keep the bed a few dB down
(`AKSong.gain_db`) and let the master chain set the overall level.

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
  between renders. `vary_variants = 4` cycles a few variants instead of rendering a new
  one every hit.
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
| Bell, electric piano, metallic pluck, FM bass | `fm` | `ratio`, `index` → `index_end`, `index_decay_s`, ADSR |
| Bass, pad, lead, stab, arp | `wavetable` | `position` (sine→square), `unison`, `cutoff_hz` + `env_octaves`, ADSR |
| Drums | `kick`, `snare`, `clap`, `hat` | `tune_hz`/`punch`; `tone_hz`/`noise`; `bursts`; `decay_s`/`metal` |

Musical pitch: equal temperament, A4 = 440 Hz; a semitone is ×1.05946, a fifth ×1.4983,
an octave ×2. Pentatonic runs (0, 2, 4, 7, 9, 12 semitones) are safe for rising sequences.

## 4. Cue map and the piece

An `AKCueMap` maps cue names to recipes: the exact name, then the longest `prefix*`,
then `*` (as the motion kit's `MotionCuePlayer`). Its `master_fx` default removes DC,
sets −16 LUFS and limits at −1.5 dB; its `reverb` dictionary sets the shared space;
`end_fade_s` fades and stops the mix on the picture's last frame.

To score a composition, add an `AKCueBridge` child with the cue map:

- **BAKED** (authored pieces, the default): renders the whole cue sheet into one track,
  puts it on the composition's `audio` player and sets `clock = AUDIO`. In the editor,
  press **Bake track** in the inspector so the game never renders at runtime.
- **LIVE** (needs the native core): the same timeline as BAKED, mixed while it plays on
  the native mixer, every hit on its exact frame, shared reverb and master chain live.
  It matches the bake to float rounding and starts without a full bake. Use it when the
  piece also takes game events (`bridge.trigger(&"name")`) or continuous voices
  (`bridge.live.voice_start(...)`). Falls back to BAKED without the core.
- **EVENTS** (interactive UI, no native core): plays cues as they fire, within a mix
  buffer; no shared reverb; negative offsets start the sound part-way in.

Without a composition, call `AK.bake(recipe, intensity, data)` for an `AudioStreamWAV`,
or `AK.render_cues(cues, map, fps, length_s)` with cues in the motion kit's
`export_cue_sheet()` shape.

Live, without a composition (`AKLive`):

```gdscript
var live := AKLive.new()
live.prepare(cues, cue_map, fps, length_s, song)  # [] for no timeline: reverb + master only
player.stream = live.stream; player.play()
live.trigger(&"hit", 0.8, {pitch = 1.1})          # one-shot into the same mix
var v := live.voice_start({shape = "saw", freq_hz = 90.0, gain = 0.3, cutoff_hz = 500.0, q = 2.0, send = 0.2})
live.voice_set(v, "cutoff_hz", 2400.0, 0.2)       # glide over ~0.2 s
live.voice_stop(v, 0.3)
```

Live music (`live.song_play(song, &"loop", "intro")`, then `live.update()` every frame):
notes render just ahead of time, so `song_queue("drop", &"bar")` changes section on the
next bar, `song_changed()` applies edits to the song resource mid-play, and
`set_lane_gain(&"drums", -12.0, 1.0)` fades a lane. Set `cue_map.duck` (depth_db 6–10,
full_at_db around −18, release_s 0.2–0.4) to sidechain music under the effects; it
applies to bakes too.

In a scene, use `AKLivePlayer` (holds the mixer; `trigger`, `song_play`, `song_queue`,
`set_lane_gain`) and `AKLiveVoice` children for continuous sounds bound to game state:
`bindings = [{param = "freq_hz", node = ^"../Car", property = "speed", from = [0, 60],
to = [60, 240], curve = "exp", glide_s = 0.08}]`. Use "exp" for pitch and cutoff.

Voice shapes: sine, saw, square (`width`), triangle, noise (or `noise` 0..1 mixed into a
shape). Parameters that glide: freq_hz, gain, cutoff_hz, q, pan, send, width, noise.
Map game state onto `voice_set` each frame (engine rpm to freq_hz, speed to cutoff_hz).
Loudness steps in the master chain are measured once at `prepare()`, so one-shots and
voices added later don't move the level; every other master effect runs live. To check
a live mix, `live.render_offline(live.length_frames())` returns exactly what playback
would produce (`live.render_playing(frames)` when the sequencer is running): save it and
review it like a bake.

## 4b. Music: patterns and songs

An `AKSong` arranges `AKPattern`s on an `AKTempoMap` (bpm, meter, `offset_s` of the
first downbeat, tempo changes). A pattern holds lanes; each lane plays one recipe:

```
{"name": "kick", "recipe": "res://music/kick.tres", "steps": "X...x...X...x..."}
{"name": "hat",  "recipe": "res://music/hat.tres",  "steps": ".o.o.o.o.o.x.o.o", "length": 16, "gain_db": -12.0}
{"name": "bass", "recipe": "res://music/bass.tres", "steps": "Xxxx" * 16, "notes": [33, 45, 33, 40], "gate": 0.85}
{"name": "pad",  "recipe": "res://music/pad.tres",  "steps": "x...............", "notes": ["A3", "G3"], "chord": [0, 3, 7, 12], "gate": 15.0}
{"name": "bell", "recipe": "res://music/bell.tres", "steps": "x..x..", "degrees": [1, 5, 3, 8], "scale": "minor", "root": "A4"}
```

- **Step strings**: `X` accent, `x` normal, `o` soft, `1`–`9` velocity, `?` half the
  time (seeded), `.` rest, `-`/`~` tie. Spaces and `|` group visually.
- **Pitch**: `notes` (names or MIDI numbers, cycled over the hits; without `steps`, one
  entry per step), or `degrees` + `scale` + `root`. `chord` adds intervals to each hit.
  The recipe is retuned to each note (`keytrack: false` moves only the pitch, not filters).
- **Feel**: pattern `swing` (0.5 straight, 0.66 shuffle), `humanize_ms`,
  `humanize_velocity`; lane `probability`; lane `length` for polymeter (a 3-step lane
  over 16 steps drifts against the bar).
- **Sections**: `{name, bars, patterns, mute, transpose, gain_db, automation}`. Bars may
  be fractional so sections can follow the picture (a section can start on beat 3).
  Patterns restart at each section. Automation: `{"bass.cutoff_hz": [[0, 300], [1, 2000]]}`
  across the section, any voice or effect parameter or `gain_db`.
- **Under a piece**: give the song to `AKCueBridge.song` (or `render_cues(..., song)`). It
  shares the cue map's reverb and master. `song_cues = true` adds every note as a cue
  (`music.<lane>`, `music.section`) to the composition, so motion can follow the music;
  those cues never play twice.
- **Fit to the picture**: set the cue map's `end_fade_s` (0.3–0.6 s) so music and tails
  fade and stop on the last frame.
- **Cost**: every distinct note and velocity is a render. Give repeating `vary` recipes
  `vary_variants = 4`; keep pads to a few chords. A 14 s piece with a full groove takes
  roughly 15 s to render in GDScript and about 1 s with the native core; bake it once in
the editor, or play it live.

To hear a song alone: `review.gd -- --song res://music/song.tres --out out/review/song`.
See `demo/music/e1/make.py` for a complete bed written as a Python batch.

## 5. Review: measure, look, fix

Export the piece's cue sheet (`composition.export_cue_sheet("res://.../piece.json")`, or
write one), then:

```
godot --headless --path . -s res://addons/audio_kit/tools/review.gd -- \
    --cues demo/cues/piece.json --map res://sfx/piece_map.tres [--song res://music/song.tres] --out out/review/piece
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
| Clean ending fails | a tail runs over the last frame | shorten the last tails, or set the cue map's `end_fade_s` |
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

- Deliver the track (or the scene with the bridge, baked), the recipes, cue map and
  song, and the review folder.
- Say what you verified (placement, loudness, peaks, clean ending) and what you could
  not (whether it sounds good). Ask the person to listen, and turn their notes into
  vocabulary moves or recipe edits, then review again.
- When a timing changes, change the composition's constant: the cue moves with it, and
  the bridge's cached track rebakes because its hash changed.
