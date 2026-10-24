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

All of it is original, made for this kit, and under the kit's licence (Apache-2.0).
