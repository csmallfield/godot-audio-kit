# Recording: playing into loops and the timeline

This plan continues `docs/plans/loops-sequencer.md` (phases 6 to 10, built) on the `sound-lab` branch. Chris asked for it on Oct 28: "set up your loops, then play along, improvise, riff freely and record it: pick the synth or kit, hit record, it counts you in and starts the song, you play as long as you like; stop, continue, edit the recording".

## Goal and principles

Record notes played on a MIDI keyboard (or pads) while the music plays, and keep them as ordinary loops on the Sequencer's timeline, editable on the Loops grid.

- **In the Sequencer, not a new tab.** Recording needs what the Sequencer already has: the arrangement playing, its tempo, a playhead and tracks to land on. A take becomes a clip on a track. Editing a take is the Loops grid, which a double-click on a clip already opens with the music around it.
- **A take is a loop.** A recording is an `AKLoop` that doesn't repeat (as long as the take, in whole bars), saved under `res://audio/loops/takes/`. Everything that works on loops works on takes: the grid, velocity tools, the arrangement, bakes, games.
- **Notes, not audio.** MIDI notes with velocity; no microphone recording.
- **Timed by what you heard.** A note is placed where the music was when you heard it: the mixer's position, less the audio output's latency, less a latency setting the player can adjust.
- **Live and baked stay one.** A recorded take plays live and bakes like any loop (the existing gates hold it).

## Decisions

| Question | Decision | Why |
| --- | --- | --- |
| Where it lives | The Sequencer: an arm button on each track, Record in the transport | Recording needs the transport, tempo, playhead and tracks; a new tab would duplicate them |
| What a take is | An `AKLoop` saved in `res://audio/loops/takes/`, placed as one clip | Takes edit, arrange, bake and play in games with no new code paths |
| Where a take goes | At the bar of its first note, for whole bars to its last; clips on that track are trimmed around it (as Paint does) | Recording again later in the song ("continue") just adds a take there; earlier takes stay |
| Which instrument | "Record with": a patch or a kit, defaulting to the instrument of the clip under the playhead on the armed track | Tracks have no instrument of their own; loops carry them |
| Pads and kits | General MIDI drum notes by piece name (36 kick, 38 snare, 42 closed hat, 46 open hat ...); other notes, and kits without those names, by pad order from note 36 | The MPK's pads send 36 to 51; GM keyboards play kits as expected |
| Timing resolution | Whole ticks (96 a beat: 5.2 ms at 120 bpm) | The loop format; finer than Godot's MIDI delivery (once a frame, 8 ms at 60 fps) |
| Sustain pedal | Held notes end when the pedal lifts | What the player heard |
| Count-in | 0, 1 or 2 bars of clicks before the music starts | As asked; 1 bar by default |

## Phases

### 1. Record onto the timeline (built first)

- `AKRecorder` (`loops/recorder.gd`): song frames to ticks over a tempo map, note on and off, the sustain pedal, the pad map, and the take as an `AKLoop` (start bar, bars, notes).
- `AKLive.heard_frame()`: the frame being heard now (the mixer's frame, less the output latency, plus the time since the last mix).
- Sequencer: an arm button (●) per track; in the transport **Record**, **Count-in** (0 to 2 bars), **Click** (a metronome while recording), **Latency** (ms) and **Record with** (patches and kits). Record starts the timeline from the playhead's section after the count-in; you hear what you play (patches through an `AKMidiRouter`, kit pieces and samples on the live mixer); **Stop** saves the take and places it, as one undoable edit.
- MIDI input: the Sequencer opens the inputs while a track is armed; the take records what the router hears.
- *Gate: a drum take and a synth take recorded through the Sequencer from MIDI events at known song times land within half a tick of where they were played (the sustain pedal holding notes), after a one-bar count-in whose clicks fall on its beats; the take is a clip at its first note's bar, undo removes it, and the timeline with the take plays live as it bakes.*
- Status: built on `sound-lab` (PR #1): the gate is met in `tests/test_recording.gd` (ten hits, the worst 0.47 ticks from where played; three notes held by the pedal to its release; the timeline with both takes live vs baked at 154.4 dB). Not yet played from a real keyboard.

### 2. Takes and cycle recording

- Takes: a track keeps every take of a span; a menu on a take's clip swaps in another; delete takes you don't want.
- Cycle recording: with **Loop bars** on, recording goes round the range; each pass layers onto the same take (**Overdub**) or replaces it (**Replace**).
- The Loops page: Record into the open loop while it cycles, with the same count-in, click, monitoring and overdub or replace.
- *Gate: three passes round a two-bar range overdub into one take with every note in place, Replace keeps only the last pass, a take swapped in from the menu plays in place of the other, and a loop recorded on the Loops page reloads note for note.*
- Status: built on `sound-lab` (PR #1): the gate is met in `tests/test_recording.gd` (kick, snares and a hat over three passes in one take, pass 1's kick replayed in pass 2 at the level it was heard when played; replace keeping the hat; the takes menu and Delete take; a loop on the Loops page recorded over two passes, undone, redone, saved and reloaded; replace on the Loops page). The shared keyboard handling is `AKPlayAlong` (`editor/play_along.gd`).

### 3. Quantize and controllers

- Quantize on the Loops grid: the selection (or all) to the grid's division or a chosen one, with a strength (0 to 100%) and an option to keep lengths; undoable.
- Controller lanes: pitch bend and mod wheel recorded with a take and played back by synth patches (a lane per controller on the loop, drawn under the velocity strip).
- Recording from the computer keyboard (as on the Synth page) for people without a MIDI keyboard.
- *Gate: quantize at 100% puts every start on the grid and at 50% halves each distance to it; a recorded bend and mod-wheel sweep play back live and baked as performed.*

## Risks

- **MIDI timing in Godot.** `InputEventMIDI` arrives once a frame without a timestamp, so notes can be up to a frame late (8 ms at 60 fps). The editor slows its redraws when idle; the Sequencer keeps it redrawing at full rate while recording. Quantize (phase 3) tidies what remains.
- **Latency.** The player hears the music late by the output latency and plays to what they hear; `heard_frame` corrects for it, and the Latency setting covers the rest (a MIDI interface's delay, habit). A small "tap along" calibration could come later.
- **Monitoring kits and samples.** Kit pieces and sample notes are rendered on the first press and cached; the very first hit of a piece can be a few milliseconds late to hear (not to record).
- **Long takes.** A take is one loop; a ten-minute improvisation is a few thousand notes, fine for the grid and the sequencer.
