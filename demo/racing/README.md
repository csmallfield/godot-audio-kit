# Racing demo: sound effects and "Neon Circuit"

An example of what the Audio Kit makes for one game: a set of racing sound effects and a title track. Everything is synthesized and stored as text, so it can be opened, played and edited in the Sound Lab. `make_racing.gd` writes all of it:

```
godot --headless --path . -s res://demo/racing/make_racing.gd            # write the resources
godot --headless --path . -s res://demo/racing/make_racing.gd -- --bake  # and bake WAVs to out/racing/
```

## Sound effects (`sfx/`)

| Sound | What it is | Built from |
| --- | --- | --- |
| `engine_idle`, `engine_mid`, `engine_high` | Engine loops at three speeds (2 s each) | The `engine` patch at 30, 62 and 118 Hz |
| `engine_rev` | A blip of the throttle | `engine_rev`: the engine patch with an envelope on pitch and filter |
| `engine_start` | Starter motor cranking, then the engine catches | Ratchet clicks, then `engine_rev` |
| `gear_shift` | The lever's clack and the drivetrain's thunk | Clicks and a short boing; varies per play |
| `turbo_blowoff` | A sharp falling pssh | A band-passed whoosh |
| `tire_screech`, `skid_short` | A tyre squeal and a short skid | The `screech` patch: wobbling triangles and noise through a band-pass |
| `crash_heavy` | The hit, crumpling metal and debris | Kick, static, metal mallets and a ratchet |
| `bump` | A light knock between cars | Boing and metal |
| `wall_scrape` | Grinding along a barrier | Static and a fast ratchet |
| `countdown_beep`, `countdown_go` | Start lights | Square tones |
| `nitro_boost` | A rising rush | A whoosh and a rising saw through a flanger |
| `pass_by` | Another car passing close | Saw and square engines falling in pitch (Doppler), widened |
| `horn` | A car horn | Two square tones through a band-pass |
| `checkpoint`, `lap_complete` | Pickups for the track | Glass mallets; FM bells |
| `finish_fanfare` | Race won | The kit's `brass` patch, arpeggio to a chord |
| `item_pickup`, `menu_select`, `menu_back`, `menu_move` | Power-up and menu sounds | The SFX generator at fixed seeds |

Sustained sounds are levelled by loudness (so a screech and a horn sit together) and hits are peak-normalised. Sounds with `vary` render a few variants and cycle through them as they replay.

Play them in a game as recipe streams, or bake them:

```gdscript
$Crash.stream = AKRecipeStream.of(load("res://demo/racing/sfx/crash_heavy.tres"))   # varies per play
AK.bake_wav(load("res://demo/racing/sfx/horn.tres"), "res://audio/sfx/horn.wav")    # or a plain WAV
```

The engine loops are meant for `AKLiveLayers` (native core), which crossfades them and pitches them with the revs:

```gdscript
var engine := AKLiveLayers.new()
engine.live_player = $AKLivePlayer
engine.layers = [{recipe = load("res://demo/racing/sfx/engine_idle.tres"), at = 900.0},
	{recipe = load("res://demo/racing/sfx/engine_mid.tres"), at = 3000.0},
	{recipe = load("res://demo/racing/sfx/engine_high.tres"), at = 6500.0}]
engine.value_node = ^"../Car"
engine.value_property = "rpm"
add_child(engine)
```

As baked WAVs they loop seamlessly once crossfaded (`AKLive.make_loop`, which `--bake` applies); set Loop Mode to Forward when importing them.

## Song (`song/`)

"Neon Circuit": synthwave in A minor at 128 bpm, about a minute, on Am, F, C, G. Sections: intro (pad and arpeggio), build (bass and hats, a kick fill), race (drums and the lead's hook), break (the lead answers over the pad), final_lap (the hook an octave up, doubled), finish (a last hit). A riser with a crash leads into the race and the final lap.

The synths are patches in `patches/` (`neon_bass`, `neon_arp`, `neon_pad`, `neon_lead`) played from note events; the drums are recipes. Open `song/neon_circuit.tres` in Sound Lab → Synth to play it and swap any lane's patch, or play it in a game:

```gdscript
var live := AKLive.new()
$Music.stream = live.stream
live.prepare([], AKCueMap.new())
live.song_play(load("res://demo/racing/song/neon_circuit.tres"), &"loop", "race")   # loop the race section
$Music.play()
# ... live.song_queue("final_lap", &"bar") on the last lap; call live.update() every frame
```

## The song as loops and an arrangement (`loops/`, `arrangement/`)

`make_arrangement.gd` turns the song's patterns into loops (`AKLoop.from_pattern`, the conversion the Loops tab's import uses) and arranges them:

```
godot --headless --path . -s res://demo/racing/make_arrangement.gd
```

| Loops | From |
| --- | --- |
| `pad`, `arp`, `bass`, `lead` | The race section's lanes (4 bars; the lead's hook 8) |
| `arp_soft`, `break_lead` | The break |
| `lead_high`, `lead_low` | The final lap's doubled hook |
| `pad_end`, `bass_end`, `end_hit` | The finish |
| `beat`, `build_beat` | The race's drums (one bar) and the build's hats and kick fill, on `neon_kit` (the song's drum recipes as one kit; the hats choke each other) |

`arrangement/neon_circuit.tres` has six tracks (pad, arp, bass, drums with a gentle compressor, lead, lead_low), a scene per section (intro, build, race, break, final_lap, finish) and the same sections on the timeline, so it plays the song's notes. The stingers are a crash on the downbeat into the race (from the build) and into the final lap (from the race): a game's switch is known only a bar ahead, too late for the song's 1.85 s riser.

## The race demo (`race_demo.tscn`)

A small race whose state drives the music. An `AKLivePlayer` plays the arrangement and the race switches its scenes on the next bar:

| Race state | Scene |
| --- | --- |
| menu (Space, or the autopilot after a few seconds, starts) | intro |
| countdown: three beeps and GO, two beats apart | build |
| racing, laps 1 to 2 (a lap chime each lap) | race |
| final lap | final_lap |
| finished (the fanfare) | finish |

The car drives itself round the oval; Up and Down change its speed. The sound effects come from `race_cues.tres` (the music ducks a little under them). Needs the native core for the music; with Movie Maker the autopilot runs the whole race (about 40 s). `tests/test_games.gd` drives it at 60 frames a second and checks each switch lands on the next bar and the music matches a bake of the scenes as they played.

```gdscript
$Music.arrangement = load("res://demo/racing/arrangement/neon_circuit.tres")
$Music.play_scene("intro")
# on GO:
$Music.play_scene("race", &"bar")
```

All of it is original, made for this kit, and under the kit's licence (Apache-2.0).
