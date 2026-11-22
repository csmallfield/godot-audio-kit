# Flavor: checks to run against the native core

The Flavor page (`docs/flavor.md`, plan in `docs/plans/flavor-tab.md`) was designed, tuned and built in an environment with no native core, no sound output and no MIDI device. Every example that was approved by ear was rendered by the GDScript engine, offline. This note lists what a session on a machine with the native core built should check, what would count as a problem, and what to report.

Nothing here has been run yet. Where a threshold is given it is a proposal for what to flag, not a measured target.

## Setup

1. Check out the branch `claude/awesome-ptolemy-gjyzkn` (or `main` once it is merged).
2. Build the native core (`native/README.md`) or unzip the CI artifact into `addons/audio_kit/native/bin/`.
3. Confirm it loads: `AKSynth.available()` is true, and the test run below prints no "GDExtension dynamic library not found".
4. Import once: `godot --headless --path . --import`.

Godot writes `.uid` files next to scripts that lack one when it imports. Some under `tools/patch_convert/` are not tracked; leave them out of any commit.

## Part A: checks a session can run on its own

Write these as a headless script (`godot --headless --path . -s <script>`), not as changes to the page. `AKSynthStream.render_offline(frames)` runs the live engine without an audio device, and `tests/test_synth.gd` (`test_live_matches_bake`) shows the pattern.

### A1. The whole test suite

```
godot --headless --path . --script res://tests/run_tests.gd
```

Report the totals. `tests/test_flavor.gd` and `tests/test_flavor_lab.gd` are the last two suites; they were only ever run alone, on the GDScript engine. The whole suite could not be finished where the page was built (too slow without the native core).

### A2. The native engine reproduces the approved sounds

Every approved sound came from the GDScript engine. For each setting below, render the standard phrase with `AKSynth.render_notes` (native) and with `AKSynth.render_events(..., force_gdscript = true)` and report the difference in dB relative to the signal.

- The base (`{}`).
- Each two-way knob at −1 and +1, each add-only knob at 1, each switch on (Minor with `note_chord = 1`).
- The combinations in `docs/plans/flavor-tab.md`, including everything at full and the resonance stack (`silky_gritty = 1, woody_glassy = -1, shut_quack = 1, polite_farty = 1`).

The standard phrase is in `addons/audio_kit/tools/flavor_listen.gd` (`_phrase`). Flag anything worse than about −60 dB, and say which control it involves: the kit expects the two engines to agree to float rounding, and controls that use random or smooth LFOs (Wonky), the growl's jitter (Filthy, Farty) or `random` matrix rows (Crowd, Farty, Wonky) are the likeliest to differ.

### A3. A patch played live matches its bake

For the same settings, play the phrase through an `AKSynthStream` with `render_offline` and compare with `AKSynth.render_notes`, as `test_live_matches_bake` does. Flavor patches use a free-running LFO (Pump), tempo-synced delay and LFO, the arpeggiator (Bounce), mono mode with glide (Slinky) and a limiter last; those are the parts worth naming if live and baked differ.

### A4. What heavy sounds cost live

Time `render_offline` for a held four-note chord, 5 seconds, and report it as a share of real time (render seconds ÷ 5) for:

- The base.
- `solo_crowd = 1` (seven unison voices).
- `murky_sparkly = 1, note_chord = 1, solo_crowd = 1` (many oscillators, each seven times).
- Everything at full.
- Everything at full with eight notes held.

A 2-oscillator patch with 16 voices was measured at about 4% of a core when the engine limits were raised. Flag any Flavor sound over about 50% of real time on one core: the editor's audio thread would be at risk of dropouts. If everything-at-full is far over, say which control accounts for most of it (turn them off one at a time); Crowd's seven voices multiplying thirteen oscillators is the suspect.

### A5. Turning a knob while a note is held

The page rebuilds the same `AKPatch` object in place on every move (`AKFlavor.apply_to`) and emits `changed`. Unknown: whether a note that is already sounding follows, and whether it does so cleanly.

Set a stream's `patch` to a Flavor patch, start a note, render 0.5 seconds, then sweep one control in about 20 steps with `AKFlavor.apply_to`, rendering 20 ms between steps, and keep rendering 0.5 seconds after. Do this for at least:

- `lean_beefy` 0 → 1 (adds an oscillator, an EQ and a compressor).
- `murky_sparkly` 0 → −1 (filter and matrix amounts only).
- `clean_filthy` 0 → 1 (effects appear at 0.3 and 0.65).
- `note_chord` 0 → 1 (oscillators appear).
- `dry_drenched` 0 → 1 (delay and reverb settings change every step; a second reverb appears at 0.6).
- `stiff_slinky` 0 → 0.5 (poly to mono mid-note).
- `pump` off → on.

Report for each:

- Does the note survive (`voice_count()` stays above 0, the output does not fall silent)?
- Does the sound change during the sweep, or only on the next note? Compare with the same render without the sweep.
- Are there clicks? Look for sample-to-sample jumps much larger than the same note renders without a sweep, at the step boundaries.
- Do effect tails survive? With `dry_drenched`, check whether the reverb and delay tails carry across a step or are cut each time the settings change.

Also report how many times `changed` fires per `apply_to` call (it sets about twenty properties, then emits once; if the property setters emit too, the stream may recompile many times per move) and how long one `apply_to` takes.

### A6. How long levelling takes

Time `AKFlavor.measure(patch)` and `AKFlavor.level(patch)` for the base, full Beefy and everything at full. The page runs `level` each time the controls settle when the native core is present. Flag anything over about 100 ms: it would be felt as a hitch after every knob move, and the page should then level on a thread, less often, or only on Save.

Also confirm the numbers: with the standard reference notes, the base should need no gain and full Beefy (`lean_beefy = 1`) should come down by a few dB. On the GDScript engine with the longer standard phrase, the base measured −15.0 LUFS and full Beefy −7.7.

### A7. The listening tool

```
godot --headless --path . -s res://addons/audio_kit/tools/flavor_listen.gd -- --out out/flavor
```

It should finish in seconds with the native core (it took minutes per control without). Report the table it prints, and flag any step that peaks above −1.0 dBFS (the limiter's ceiling) or any control whose steps all measure the same.

## Part B: checks that need a person

These need ears, a mouse and, for the last group, a MIDI controller. A session can prepare the editor and list them; it cannot do them.

### B1. Playing it

- Open the Sound Lab's Flavor tab. Play the keyboard at rest: is it the base sound that was approved?
- Turn each knob to both ends while playing. Does each still do what its words say, as in the examples?
- Hold a note and turn a knob slowly. Does the note follow smoothly, step, click, or only change on the next note?
- Turn several knobs up, including Crowd and Chord, and play chords. Any dropouts or crackle?
- Tick Bounce and hold a chord; tick Pump; raise Slinky and play a line. Do they behave as described in `docs/flavor.md`?

### B2. The page

- Knob feel: is the drag distance right (180 px for the full range), is Shift fine enough, does double-click reliably return to rest?
- Is anything cut off or crowded at your editor scale and window size? The page was only ever seen at one size, at scale 1.
- Does the Limiter light come on with the resonance stack (Gritty, Woody, Quack and Farty all up) and stay off for the base?
- After a knob settles, is there a hitch (levelling) or an audible jump in level? The level gain is dropped while a knob moves and set again when it settles.
- Randomise a dozen times. Are the results varied and usable, or too mild or too wild? Mutate at the default amount: a near neighbour, or too far?
- Save a sound, Reset, and reopen it from the menu. Open in Synth, change something there, save over it, and reopen it on the Flavor page: is the "edited since" notice clear?

### B3. MIDI

- Tick MIDI input. Does a MIDI keyboard play the sound?
- Right-click a knob, Learn, turn a hardware knob. Does it link (the dot appears) and follow?
- With the hardware knob far from the on-screen one, does the on-screen knob stay put until the hardware reaches it, then follow?
- On a two-way knob, is the controller's middle a comfortable rest position?
- Restart the editor. Are the links still there?

## What to do with results

- **Report first.** Give the numbers for Part A and a short list of what failed or looked wrong.
- **Fix what is clearly a bug**, with a test, on the branch: a crash, a parse error, a control that does nothing, a failing test.
- **Do not re-tune the sound.** Every control's end values in `AKFlavor` were approved by ear (`tests/test_flavor.gd` pins them). If the native engine makes one sound different, report it; do not change the values to compensate.
- **Do not change the engine** (`native/src`, `synth/synth_core.gd`, `dsp/`) for Flavor's sake without asking. If a held note cannot follow a knob, or levelling is too slow, describe what the engine does and propose options.
