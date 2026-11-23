# Audio Kit native core

A GDExtension (C++, godot-cpp) with these parts:

- **`AKNative`**: the DSP kernels (oscillators, envelopes, filters, Karplus-Strong, FM, Freeverb, limiter, loudness, mixing). Each mirrors a GDScript function in `addons/audio_kit/dsp/`, using the same algorithm, so renders agree to about 1e-4 of peak. GDScript calls them through `AKDsp.nat()` and uses its own code when the library isn't there. Turn the native path off with `AKDsp.native_enabled = false`.
- **`AKLiveStream`**: the live mixer, an `AudioStream` whose playback mixes at 48 kHz. Pre-rendered buffers are scheduled at exact timeline frames on buses (faders, sidechain ducking), continuous voices (oscillators, or recipe loops at a gliding rate) glide their parameters as they play, and a shared Freeverb send and a master chain (gain, filters, drive, bitcrush, echo, room, end fade, limiter) run on the stream. The GDScript wrapper is `AKLive` (`addons/audio_kit/core/live.gd`); the scene nodes are `AKLivePlayer` and `AKLiveVoice`.
- **`AKSynthStream`**: the synth engine (`src/synth.{h,cpp}`, `ak::SynthEngine`) as an `AudioStream`, so patches play live on any player and bus; `AKSynth.render_notes` bakes through the same engine. `AKSynthCore` (`addons/audio_kit/synth/synth_core.gd`) is its GDScript twin, step for step, for bakes without the core.
- **Bus effects** (`src/ak_fx.*`, on the `ak::Fx` effects in `src/fx.h`): `AKChorus`, `AKFlanger`, `AKPhaser`, `AKEQ3`, `AKCompressor`, `AKSaturate` and `AKLimiter`, listed in Godot's Audio panel under Add Effect. The same effect code runs in patches, recipes and the live mixer's track inserts; its GDScript twin is `AKStreamFx` (`addons/audio_kit/dsp/stream_fx.gd`).
- **`AKMatch`**: the heavy parts of sample matching (high-pass, spectra, harmonic DFT and features, the harmonic score). It has no GDScript fallback.

Recipes and patches don't change: the kit bakes the same with or without the native core, only faster. Live synth playback, the live mixer, the bus effects and sample matching need it.

## Build

You need Python 3, SCons (`pip install scons`) and a C++17 compiler (GCC or Clang on Linux, MSVC on Windows, Xcode command line tools on macOS).

```
git submodule update --init          # godot-cpp at godot-4.5-stable
cd native
scons platform=linux   target=template_debug     # editor and debug runs
scons platform=linux   target=template_release   # exported games
scons platform=windows target=template_debug
scons platform=macos   arch=universal target=template_debug
```

The libraries are written to `addons/audio_kit/native/bin/`, where `aknative.gdextension` finds them. The first build compiles godot-cpp, which takes a few minutes. `build_profile.json` keeps that build to the classes the core uses.

The CI workflow (`.github/workflows/native.yml`) builds every desktop platform and uploads them as one artifact, `audio-kit-native`. Unzip it into `addons/audio_kit/native/bin/` if you'd rather not build locally. Built libraries aren't committed.

## Check

```
godot --headless --path . --script res://tests/run_tests.gd
```

`tests/test_native.gd` renders every kernel, every voice and a full cue sheet both ways and compares them; `tests/test_synth.gd` and the other synth tests hold the native synth engine to `AKSynthCore`, and `tests/test_breadth.gd` the native effects to `AKStreamFx`. `tests/test_live.gd` holds the live mixer to the baked render (the Phase 3 gate): E1 with music matches at SNR 140 dB.
