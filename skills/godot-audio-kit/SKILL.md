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
| Saxophone-like lead, breathy melody | `reed` | `brightness`, `breath`, `growl`, `scoop_semitones`, `vibrato_cents` + `vibrato_delay_s`, formants |
| Drums | `kick`, `snare`, `clap`, `hat` | `tune_hz`/`punch`; `tone_hz`/`noise`; `bursts`; `decay_s`/`metal` |
| A sound file or recipe played at pitch | `sample` | `sample` (an AKSample or path), `freq_hz`, `velocity`, `gate_s` |

Musical pitch: equal temperament, A4 = 440 Hz; a semitone is ×1.05946, a fifth ×1.4983,
an octave ×2. Pentatonic runs (0, 2, 4, 7, 9, 12 semitones) are safe for rising sequences.

### Patches: the synth engine

For anything played as notes (a lead, a bass, pads, an instrument a game plays live), use
an `AKPatch` rather than a voice. `docs/synth.md` is the full reference.

```
oscillators = [{"shape": "saw", "level": 0.6}, {"shape": "saw", "cents": 9.0, "level": 0.6}]
filter = {"type": "lowpass", "cutoff_hz": 1800.0, "q": 1.3, "slope_db": 24.0}
amp_env = {"attack_s": 0.01, "decay_s": 0.3, "sustain": 0.8, "release_s": 0.12}
env2 = {"attack_s": 0.0, "decay_s": 0.25, "sustain": 0.2, "curve": "exp"}
mods = [{"source": "env2", "dest": "cutoff", "amount": 1.5}, {"source": "lfo1", "dest": "pitch", "amount": 0.18}]
mode = "legato"
glide_s = 0.06
```

- Shapes: sine, triangle, saw, square, pulse (`width`), noise, morph (`position`). FM: an
  oscillator's `fm_from` (1-based) and `fm_index` (radians); a modulator has `level` 0.
- Matrix sources: env1 (amp), env2, env3, lfo1, lfo2, velocity, key, mod_wheel, aftertouch,
  random, bend. Destinations: pitch (semitones), cutoff and q (octaves), amp, pan,
  `oscN.pitch|level|fm|width|position` (N 1-based, or `osc.` for all).
- Bake: `AKSynth.render_notes(patch, [{time_s, note, velocity, length_s}, {time_s, bend}])`.
  In a recipe: `{voice = &"patch", params = {patch = "res://…tres", freq_hz, gate_s}}`, so
  song lanes and cues can use patches. Live: `AKSynthStream` (native core) with
  `note_on(note, velocity, delay_s)`, `note_off`, `set_bend`, `set_mod_wheel`.
- Start from a preset in `addons/audio_kit/patches/` (saw_lead, sync_lead, sub_bass,
  acid_bass, wobble_bass, brass, pluck, strings, pwm_strings, organ, fm_epiano, fm_bell,
  ring_bell, wavetable_bass, wavetable_pad, vowel_pad, tone_beep), or `AKPatchLib.from_voice(&"wavetable", params)` to turn a voice's settings
  into a patch.
- Levels add up across voices: one note of a preset peaks near −6 dBFS; leave headroom for
  chords, and measure a render (`AKSoundFeatures.of`, `AKDynamics.lufs`) before trusting it.
- Breadth: `shape = "table"` with `table = "vowel"` (or basic, pwm, organ, bright, digital,
  or your own frames) and `position` swept by the matrix (`osc1.position`); `sync_to` and
  `ring_from` (1-based); `spread` for stereo unison; `filter = {type = "ladder", cutoff_hz,
  resonance, drive}` for a fat 24 dB low-pass.
- Effects: a patch's `effects` and a recipe's `fx` take the same specs: `chorus`, `flanger`,
  `phaser`, `eq` (low/mid/high), `compressor`, `saturate` (keys and defaults in
  `docs/synth.md`). On a Godot bus they are `AKChorus`, `AKPhaser` ... (native core), so a mix
  can use the same effect live. Prefer one shared chorus or reverb on a bus over one per
  voice when many sounds want it.
- People build patches by hand in **Sound Lab → Synth** (`docs/sound_lab.md`): a preset
  browser by `category`, panels for every key above (undoable), a scope, spectrum and
  preview note, and Save to `res://audio/patches/`. A patch you write as text opens there
  too, so give it a `category` (bass, lead, pad, keys, pluck, bell, strings, brass, organ,
  fx) and tell the person they can tweak it in the panels. From code, `AKPatchEditor`'s
  `set_param("filter.cutoff_hz", 800.0)`, `add_mod`, `add_effect` make the same undoable
  edits.
- `AKSynthStream.get_recent(frames)` and `AKSpectrum.peak_hz(samples, sr)` /
  `magnitudes_db` let you check a live or baked sound's pitch and spectrum numerically.

### MIDI files and keyboards

`docs/midi.md` is the reference.

- A `.mid` in the project loads as an `AKSong` (`load("res://music/x.mid")`, or
  `AKMidi.import_file(path, {quantize = 4})`), played by the General MIDI starter bank:
  a lane per instrument (`patch` lanes with freely timed `events`), drums split into
  `drums.kick`, `drums.snare` ... lanes, exact tempo and meter maps, markers as sections.
  `AKMidi.summary(song)` describes it. Save it (`ResourceSaver.save`) to get editable text,
  then re-voice a lane by changing its `patch`.
- Songs carry notes, velocities and the sustain pedal, not pitch bend or mod wheel.
- To check an import, compare `song.events()` with what the file should contain, and
  measure a render (pitch at each note's middle, loudness), as `tests/test_midi.gd` does.
- Live input: `AKMidiRouter` (a node; `patch`, `omni`, `bank`, `bus`) turns InputEventMIDI
  into live patch playing; `note_on(note, velocity, channel)` plays from code.
- Pattern lanes can name a `patch` instead of a `recipe`, so step-grid music can use
  patches too.

## 3b. Game sounds: the Sound Lab and AKSfxGen

For ordinary game sound effects (a coin, a jump, a shot, a hit, an explosion, a power-up,
menu clicks, a text blip), start from the generator rather than a blank recipe:

```gdscript
var r := AKSfxGen.generate(&"jump", 42)     # categories: AKSfxGen.CATEGORIES, plus &"random"
var near := AKSfxGen.mutate(r, 7, 0.15)     # nudged numbers, same shape
ResourceSaver.save(r, "res://audio/sfx/jump_42.tres")
AK.bake_wav(r, "res://audio/sfx/jump_42.wav")   # same samples as AK.bake
```

- The same category and seed always give the same recipe (and samples), so a sound can be
  named by `category + seed` in a sound sheet; `AKSfxGen.name_for(r)` gives `jump_42`.
  Try several seeds, measure them, keep the ones whose numbers fit the brief, then edit
  the recipe like any other.
- Generated recipes end with `dcblock` and `normalize -1 dBFS`: change level by editing or
  removing that last step, not `gain_db`. Loudness differs by category (explosions measure
  lower in LUFS than jumps); balance in the game's mix or by editing the normalise.
- `AKRecipeStream.of(recipe)` is an `AudioStream`: any AudioStreamPlayer/2D/3D or an
  AudioStreamRandomizer plays it, a different `vary` variant each play (`variants`, default
  4), rendered once each and cached. Call `warm()` before latency matters. Its inspector
  has "Bake to WAV"; a baked WAV needs nothing from the kit at run time.
- `godot --headless --path . -s res://addons/audio_kit/tools/sfx_listen.gd -- --seeds 4`
  renders every category to `out/sfx_lab/` and prints length, LUFS, attack, centroid,
  tonality and pitch direction; `AKSoundFeatures.of(buf)` gives the same numbers for any
  render. Use them to check a sound does what its words say (a jump rises, a laser falls,
  a UI click is short and noisy). Whether it sounds good is still the person's call.
- People use the **Sound Lab** editor tab for the same thing by hand: category buttons, a
  seed box, Randomise, Mutate, Play, an inspector on the recipe, Bake WAV, Save recipe,
  Save stream (default folder `res://audio/sfx/`).

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
Give an AKLiveVoice a `recipe` to loop it instead of an oscillator (engines, wind,
crowds: render a second or more, bind `rate`), and `spatial = "on"` (with `unit_size`,
`max_distance`, `air_absorption`) to place it at its parent; `trigger_at(&"hit", pos)`
places one-shots. Songs take `stingers` ({to, from, recipe, gain_db}: a riser with a
negative offset into the drop, a hit on any change); they play baked and live.
`section_started` fires when a section is heard, `section_scheduled` a lookahead before.
For game music, give the song `intensity_lanes` ({"hat": [0.3, 0.6]}: silent below 0.3,
full by 0.6) and call `set_music_intensity(x, glide_s)` as the action rises and falls.
For an engine, use `AKLiveLayers` (loops at a few rpm points, crossfaded by `value`).
Rooms: put `AKReverbZone2D/3D` areas (room, damp, return_db, the area's `priority`) where
the space changes; the AKLivePlayer's reverb glides to the listener's zone.
Positional voices take `doppler` (with `speed_of_sound` in your units) and `occlusion`
(a ray from the listener on `occlusion_mask`; the source's own body doesn't count).
In the editor, the Audio Kit dock under the inspector plays the selected recipe, song,
pattern (with a step grid: hits, notes on the wheel, undoable) or cue map, and saves any of them
as a WAV; it's how the person hears your work, so point them to it.

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

### Loops, samples and kits

`docs/loops.md` is the reference. An `AKLoop` is a few bars of notes for one instrument;
`to_pattern(section_beats)` makes the pattern a section plays, so loops go anywhere
patterns do.

```
kind = "percussive"                 # synth (an AKPatch) | sample (an AKSample) | percussive (an AKKit)
bars = 2
division = 16                       # 16 | 32 | 12 | 24 a bar: the grid only, never moves notes
instrument = <AKKit>                # AKLibrary.kit("punch"), or a kit .tres
notes = [[0, 24, 0, 1.0], [96, 24, 1, 0.9], [48, 24, 3, 0.7]]   # [start tick, length ticks, row, velocity]
```

- Ticks are 96 a beat: a 16th is 24, a 32nd 12, a triplet 8th 32. Rows are MIDI notes for
  synth and sample loops, piece indices for percussive ones. Write notes in ticks, not steps.
- Percussive loops make a lane per piece, `drums.<piece>`. Kit pieces: `name`, `sound`
  (AKSample, recipe or path), `gain_db`, `pan`, `tune_semitones`, `choke` (a group: a hit
  cuts the group's ringing pieces, as a closed hat stops an open one), `gate`.
- The five shipped kits (`addons/audio_kit/library/kits/`: boom, punch, room, lo-fi,
  electro) share a row order: kick, snare, clap, closed_hat, open_hat, pedal_hat, tom_low,
  tom_mid, tom_high, crash, ride, then two percussion pieces (`kit.find_piece(name)`).
- The library (`addons/audio_kit/library/<folder>/<name>.tres`) is 128 recipes: kicks,
  snares, claps, hats, cymbals, toms, perc, bass, keys, pads, fx, vox (list in
  `docs/loops.md`). `AKLibrary.sample_for(path, "gate")` makes a pitched AKSample at the
  sound's `ak_root_note`; any recipe works through `AKSample.from_recipe(recipe, root)`.
- A project sound file: `AKSample.source = "res://…wav"` (or .ogg), then `import_source()`
  so the decoded data is saved in the `.tres` (exports need it). Modes: `oneshot`,
  `gate` (+ `release_s`), `loop` (+ `loop_start_s`, `loop_end_s`). Samples are mono.
- Check a loop the way the tests do: compare `to_pattern(...).lanes[i].events` with the
  notes you meant, and measure a render (pitch at each note with the harmonic test,
  level per stem). `tools/loops_listen.gd` renders a beat on every kit for a person to hear.
- People write loops by hand in **Sound Lab → Loops** (`docs/sound_lab.md`): a grid that
  plays while they edit, a loop browser (`res://audio/loops/`), the sound library, sample and
  kit panels. A loop you write as text opens there, so give it a `category` (beat, bass,
  chords, lead, pad, arp, perc, fx) and save it under `res://audio/loops/`; tell the person
  they can open it in the tab and edit it by ear. From code, `AKLoopGrid`'s `add_note`,
  `move_notes`, `set_velocities` make the same undoable edits.
- Arrange loops as an `AKArrangement` (`res://audio/arrangements/`): `tracks` ({name, gain_db,
  pan, send, intensity}), `scenes` ({name, bars, clips = {track: loop path}}), `timeline`
  clips ({track, loop, bar, bars, offset_bars}) and `markers` ({name, bar}). `to_song("scenes")`
  gives a section per scene (games switch with `AKLive.song_queue(scene, &"bar")`);
  `to_song("timeline")` cuts at the markers. Lanes are named for tracks (`drums.kick`). Check
  the compiled `song.events()` against what you meant, and render it to measure. People
  arrange in **Sound Lab → Sequencer** (scenes grid, timeline, Paint scene, mixer, bake, stems).
- A track's `fx` (chorus, flanger, phaser, eq, compressor, saturate specs) is an insert chain
  on its mixed lanes, the same live and baked; use it for glue (a compressor on drums, an EQ
  on a bass) rather than one effect per loop. The reverb send is taken before it.

To hear a song alone: `review.gd -- --song res://music/song.tres --out out/review/song`.
See `demo/music/e1/make.py` for a complete bed written as a Python batch, and
`demo/song/last_ferry/make.py` for a whole song (chords voiced as one lane per chord tone,
since a lane's `chord` is a single shape; the melody as a notes-only lane). Balance a mix
from the review's stems: the melody on top, then bass, keys and drums a few dB under.
Write original melodies; don't transcribe an existing song's tune.

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
