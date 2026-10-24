# MIDI: files, keyboards and the starter bank

## Playing patches from a keyboard

```gdscript
var r := AKMidiRouter.new()
r.patch = load("res://addons/audio_kit/patches/saw_lead.tres")
add_child(r)              # opens the OS's MIDI inputs and listens for InputEventMIDI
```

Each channel gets an `AKSynthStream` on its own `AudioStreamPlayer` (on `bus`), so the sound goes through Godot's mixer. The router passes on:

| MIDI | Engine |
| --- | --- |
| Note on / off (on with velocity 0 counts as off) | `note_on` / `note_off`, velocity 0..1 through `velocity_curve` |
| Pitch bend | `set_bend` (the patch's `bend_range` in semitones at full bend) |
| CC 1 (mod wheel) | `set_mod_wheel` (the `mod_wheel` matrix source) |
| CC 64 (sustain pedal) | `set_sustain`: released notes keep sounding until the pedal lifts |
| Channel pressure | `set_aftertouch` |
| CC 120 / 123 | all notes off |
| CC 7 | the channel player's volume |
| Program change | the bank's patch for that program (with `follow_program_changes`) |

`omni` (on by default) plays every channel through `patch`; turn it off to give channels their own patches (`channel_patches`) and to play channel 10 as drums. `note_on(note, velocity, channel)` plays from code or an on-screen keyboard. Melodic channels need the native core; drums are baked recipes and play without it.

Latency is Godot's mix buffer (about 15–30 ms by default). For playing in, a smaller buffer helps: Project Settings → Audio → Driver → Output Latency.

## The Sound Lab's Synth page

In the **Sound Lab** tab, **Synth**: pick a patch (presets and the bank's family patches), edit it in the inspector on the right while playing, and save a copy (`res://audio/patches/`). Play it from the on-screen keyboard (click, drag; lower on a key is louder) or the computer keyboard (`Z S X D C V G B H N J M` for one octave, `Q 2 W 3 E R 5 T 6 Y 7 U` for the next, `[` and `]` to move an octave), or tick **MIDI input** for a connected keyboard. **Sustain** and **All off** do what they say.

Under **Song**, open a `.mid` file or a song `.tres`, play it (live with the native core), pick another patch for any lane from its menu, and save the song as text (`res://audio/songs/`).

## Importing .mid files

Drop a `.mid` or `.midi` file into the project: it imports as an `AKSong` (the Import dock has the options), so it can go anywhere a song goes: the dock, `AKLive.song_play`, an `AKCueBridge`, `AK.render_cues(..., song)`. In code:

```gdscript
var song := AKMidi.import_file("res://music/tune.mid", {quantize = 4})
ResourceSaver.save(song, "res://music/tune_song.tres")      # editable text from here on
print(AKMidi.summary(song))
```

| In the file | In the song |
| --- | --- |
| Tempo and time-signature changes | The song's `AKTempoMap`, exactly: changes mid-bar sit at fractional bars; 7/8 is 3.5 beats a bar |
| Each track, channel and program | A lane playing the bank's patch for the program (`patch` key); a program change mid-track starts a new lane |
| Channel 10 | A lane per kind of drum (`drums.kick`, `drums.snare`, `drums.hat` ...) playing the bank's drum recipes |
| Notes | The lane's `events`: `[beat, length_beats, midi, velocity]`, beats from the section start; drum events are unpitched (`-1`) |
| Overlapping notes on one key | Closed first in, first out |
| Sustain pedal (CC 64) | Notes held on until the pedal lifts |
| CC 7, CC 10, CC 91 at a lane's first note | The lane's `gain_db` (40·log10(v/127)), `pan`, `send` |
| Marker meta events | Sections (named after the markers; before the first marker, "intro"); otherwise one section, "song" |

Options: `bank` (an `AKBank` or path), `quantize` (steps per beat to snap note starts to; 0 = off), `velocity_curve`, `min_length_beats`, `reverb_send` (when the file sets none), `sections`.

Not carried into songs: pitch bend, the mod wheel and aftertouch. Songs render note by note (each note a cached bake, so live and baked playback match exactly), which also means a song lane doesn't glide between notes the way a mono patch played live does.

The reader handles formats 0, 1 and 2, running status, note-on with velocity 0 as note-off, SysEx, SMPTE time (turned into ticks of a 120 bpm quarter note) and RIFF-wrapped files; a file that is cut off reports an error and imports what was readable.

## The starter bank

`addons/audio_kit/bank/gm_bank.tres` (`AKBank`): one original patch per General MIDI family, so any GM file plays with roughly the right kind of instrument:

| Programs | Family | Patch |
| --- | --- | --- |
| 0–7 | Piano | `gm_piano`: struck FM, brighter with velocity, a touch of EQ and chorus |
| 8–15 | Chromatic percussion | `gm_chromatic_percussion`: FM bell, shorter |
| 16–23 | Organ | `gm_organ`: drawbar sines, tremolo, fast chorus |
| 24–31 | Guitar | `gm_guitar`: plucked saw through a ladder, light chorus |
| 32–39 | Bass | `gm_bass`: saw and sub through a ladder with a filter blip |
| 40–47 | Strings | `gm_strings`: spread unison saws, chorus, slow attack |
| 48–55 | Ensemble | `gm_ensemble`: a wide choir on the vowel wavetable, chorus |
| 56–63 | Brass | `gm_brass`: saws through a swept ladder, EQ |
| 64–71 | Reed | `gm_reed`: nasal pulse, breath, vibrato, a little saturation |
| 72–79 | Pipe | `gm_pipe`: sine and breath |
| 80–87 | Synth lead | `gm_synth_lead`: two detuned saws through a ladder |
| 88–95 | Synth pad | `gm_synth_pad`: wide wavetable pad with chorus |
| 96–103 | Synth effects | `gm_synth_effects`: a digital wavetable through a resonant ladder and phaser |
| 104–111 | Ethnic | `gm_ethnic`: buzzy plucked string with a ring-modulated jangle |
| 112–119 | Percussive | `gm_percussive`: short metallic hit |
| 120–127 | Sound effects | `gm_sound_effects`: swept noise through a flanger |

Drums (channel 10) map GM notes to 17 lanes built from the kit's drum voices: kick, snare, rim, clap, hat, open_hat, three toms, crash, ride, ride_bell, tambourine, cowbell, shaker, wood, conga; anything else plays `perc`. A single note of each family patch peaks near −6 dBFS.

This is sketch quality: recognisable families, not a sampled GM set. A piano is a synth piano. To change a sound, edit its patch, or copy the bank and point `families`, `programs` (per program) or `drums` at your own files. `tools/make_bank.gd` rebuilds the shipped bank from `AKGeneralMidi`.

## Patch lanes in patterns

Any pattern lane can play a patch instead of a recipe, and hold freely timed notes instead of steps:

```gdscript
{name = "lead", patch = "res://addons/audio_kit/patches/pluck.tres", steps = "x.x.x.x.", notes = ["C4", "E4", "G4", "C5"]}
{name = "line", patch = some_patch, events = [[0.0, 0.5, 60, 0.9], [0.75, 0.25, 64, 0.6]]}
```

Velocity reaches the patch (its `velocity` source and level). The step grid edits step lanes as before, now with patches.
