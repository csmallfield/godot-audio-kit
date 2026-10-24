# Synth engine, MIDI and Sound Lab: plan

The live, commentable version of this plan is the doc "Audio Kit: Synth Engine, MIDI and Sound Lab" (https://claude.ai/artifact/4mbGd8YLWw5qhZduxrDSaY). This file is the in-repo copy that work on the `sound-lab` branch follows; if the two disagree, ask.

## Goal and principles

The Audio Kit grows into a sound lab inside Godot: people design rich synthesized sounds and voices, play them from a MIDI keyboard, import MIDI music, and use the results anywhere Godot takes audio, live or baked. It is not a DAW and not a new interchange format; it makes sounds for Godot projects.

- **Sounds are Godot audio.** A patch or recipe is an `AudioStream`, so it drops into `AudioStreamPlayer`/2D/3D, `AudioStreamRandomizer`, `AudioStreamInteractive`, `AudioStreamSynchronized` and AnimationPlayer audio tracks.
- **Live and baked are one engine.** The same native code renders a note in a bake and while playing, so a baked sound matches what was heard (the kit already holds live and baked to float rounding).
- **Godot does the mixing.** Routing, buses, environment and the master go through Godot's AudioServer. The kit adds what Godot lacks: synthesis, MIDI files, bakeable sound-shaping effects, and the lab.
- **Everything stays text.** Patches, recipes and songs remain readable `.tres` resources, so people (and an LLM) can author, diff and review them.
- **Nothing ships that isn't needed.** A baked sound is a plain WAV; an exported game needs the native core only for sounds that stay live.

## Decisions

| Question | Decision | What it means |
| --- | --- | --- |
| Where the Sound Lab lives | An editor main-screen tab, beside 2D, 3D and Script | Bakes write straight into the project; no separate app to build or ship |
| MIDI in the first version | Live keyboard input, `.mid` import, a General MIDI–style starter bank | Play patches from a keyboard; drop a file in and hear it with sensible instruments. `.mid` export is out for now |
| Where effects live | Hybrid | Effects that shape a sound (chorus, phaser, EQ, compression, drive) live in patches and bake; mix effects (rooms, ducking, the master) go on Godot buses |
| Lab workflows first | SFX generator and music sketching | Quick game sounds (randomise, mutate) and the step grid with songs come first; the full patch editor follows |
| Plugins (VST3, CLAP) | Not hosted | The kit builds its own engine from the same building blocks; no third-party binaries, sounds stay deterministic and portable |

## What exists and where it goes

| Today | Becomes |
| --- | --- |
| DSP: anti-aliased saw, square, triangle, sine; noise; ADSR; one-pole and state-variable filters; plucked string; FM; Freeverb; echo; drive; bitcrush; limiter; loudness (all native) | Modules of the patch engine, unchanged in sound |
| Voices: `reed`, `fm`, `wavetable`, `pluck`, `mallet`, drums and the rest | Built-in patches, and the core of the starter bank |
| Recipes: layered voices, effects, variation, cue binding | Stay as the sound-effect format; a layer can be a patch |
| Sequencer: tempo maps, step patterns, songs, sections, stingers, intensity lanes, play-time sequencing | The target of `.mid` import and the lab's music sketching |
| Native live mixer (`AKLiveStream`): sample-accurate scheduling, live voices, buses, ducking, master chain | Host of the polyphonic voice engine; its buses, ducking and master become optional, with Godot buses preferred |
| Bake path and cache: deterministic renders keyed by content hash | Unchanged; patches and imported songs bake the same way |
| Reverb zones, sidechain ducking | Kept where they bake or cover 2D; otherwise Godot's (Area3D reverb buses, compressor sidechain) |
| Audition dock and step grid | Fold into the Sound Lab tab; the dock stays as the quick inspector companion |
| Scene nodes (`AKLivePlayer`, `AKLiveVoice`, `AKLiveLayers`), spatial, Doppler, occlusion | Unchanged; voices can play patches |

## Architecture

Every note, from a keyboard, a `.mid` file, the sequencer or game code, reaches one native voice engine; what it renders either plays live as a Godot `AudioStream` or bakes to a WAV, and Godot's AudioServer does the rest.

- **Patch (`AKPatch`, `.tres`).** Oscillators (the kit's anti-aliased shapes plus table wavetables, sync, ring and FM routing), filters (state-variable plus a resonant ladder), envelopes and LFOs, a modulation matrix (source × destination × amount: envelopes, LFOs, velocity, key, mod wheel, pitch bend, aftertouch, random), voice settings (polyphony, mono or legato, glide, unison) and sound-shaping effects. Today's voices become patches.
- **Voice engine (native).** Allocates and steals voices, takes note on/off and controller events at sample offsets, smooths parameters, renders block by block. The bake path drives the same code offline, so live and baked match.
- **Live stream (`AKSynthStream`).** An `AudioStream` holding a patch, with `note_on`, `note_off`, `set_control` from code or MIDI. Assign it to any player and route it to any Godot bus.
- **Baked sound.** A patch note, a recipe or a whole song rendered to an `AudioStreamWAV` and saved in the project, cached by content hash. Nothing from the kit is needed to play it.
- **Sound-shaping effects.** Chorus, phaser, flanger, EQ, compressor and better drive as native kit effects inside patches (they bake), also registered as Godot bus effects (`AudioEffect` subclasses) so the same chorus is available in Godot's Audio panel.
- **MIDI.** Live input through Godot's `OS.open_midi_inputs()` and `InputEventMIDI`; a router node maps channels to patches (note, velocity, pitch bend, mod wheel, sustain pedal, program change). `.mid` files import through an editor import plugin into an `AKSong`: tracks become lanes, channel 10 becomes drums, programs pick starter-bank patches.
- **Starter bank.** Original synth patches covering the 16 General MIDI families plus a drum kit, so imports sound right before anyone edits them.
- **Sound Lab tab.** An editor main screen: an on-screen and MIDI keyboard, the SFX generator (categories such as pickup, jump, laser, hit, explosion, power-up, UI; randomise and mutate, every result an editable recipe), the step grid and songs, patch panels, a scope and spectrum, and bake buttons that write into the project.

## Phases

Quick game sounds first, the synth engine underneath next. Each phase ends at a gate.

1. **Sound Lab and SFX generator**
   - Editor tab with SFX categories, randomise and mutate; every result is an editable recipe.
   - Recipes as AudioStreams (live, varying per play) and one-click bake to WAV.
   - Runs on today's voices and native core: no new engine needed.
   - *Gate: ten game sound effects made and baked in a few minutes.*
2. **Synth engine**
   - `AKPatch`: oscillators, filters, envelopes, LFOs, modulation matrix, voice settings.
   - Native polyphonic voice engine: note on/off, glide, bend, rendering block by block.
   - `AKSynthStream` for live play; bakes through the same code; today's voices become patches.
   - *Gate: a patch played live matches its bake; 32 voices under 10% of a core.*
3. **MIDI and music sketching**
   - Live input: an `InputEventMIDI` router to patches (velocity, bend, mod wheel, sustain).
   - `.mid` import plugin to `AKSong`; starter bank covering the 16 GM families plus drums.
   - Lab: on-screen keyboard, step grid and songs played with patches.
   - *Gate: real .mid files import and play recognisably; patches playable from a keyboard.*
4. **Sound breadth**
   - Ladder filter, table wavetables, sync, ring modulation, FM routing, unison spread.
   - Chorus, phaser, flanger, EQ, compressor: in patches and as Godot bus effects.
   - Starter bank re-voiced with the new modules.
   - *Gate: an effect sounds the same in a patch, a bake and on a Godot bus.*
5. **Patch editor and polish**
   - Patch panels and modulation matrix in the lab; scope and spectrum.
   - Preset browser; docs, skill and demo scenes.
   - The dock stays as the quick companion to the inspector.
   - *Gate: an instrument built from scratch in the lab without touching .tres by hand.*

The SFX generator comes first because it runs on today's recipes and voices, so the lab is useful before the synth engine exists; MIDI follows the engine, and breadth and the full patch editor come last.

## Risks and open questions

- **Godot's bus effects can't bake.** A GDExtension can only implement effects, not run Godot's own offline (`AudioEffectInstance` exposes just the `_process` hook). So anything that must bake is a kit effect. The upside: the same native code can also be registered as Godot bus effects, so a kit chorus appears in Godot's Audio panel too.
- **Live note latency.** Keyboard play goes through Godot's mix buffer (about 15–30 ms by default). Fine for playing in the lab; the lab may want a smaller buffer setting.
- **Polyphony cost.** A big chord on a rich patch (eight voices, unison, filters, effects) has to fit the audio thread. Budget: 32 voices of a two-oscillator patch under 10% of a core; measure before adding unison everywhere.
- **MIDI files are messy.** Running status, format 0 vs 1, tempo maps, overlapping notes on one key, drum channel conventions. The importer needs a test corpus of real files.
- **The starter bank is content work.** 128 GM instruments plus drums is a lot of patches. Start with family coverage (16 families, drums) and grow; an imported file falls back to its family's patch.
- **General MIDI sound expectations.** A synth bank won't sound like a sampled piano; set expectations in the lab ("sketch quality") and make swapping patches per track easy.
- **Scope creep toward a DAW.** No arrangement timeline, no audio tracks, no plugin hosting. The step grid and song sections are the music surface.
- **Open:** should the kit's own buses and master chain be deprecated in favour of Godot buses for live play, or kept for parity with bakes? Proposed: keep them for bakes and `AKCueBridge`, route new live features to Godot buses.
- **Open:** licensing of the starter bank and any imported example songs: only original patches and public-domain or self-made MIDI files in the repo.
