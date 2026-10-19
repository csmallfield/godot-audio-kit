# Audio Kit native core

A GDExtension (C++, godot-cpp) with two jobs:

- **`AKNative`**: the DSP kernels (oscillators, envelopes, filters, Karplus-Strong, FM, Freeverb, limiter, loudness, mixing). Each mirrors a GDScript function in `addons/audio_kit/dsp/`, using the same algorithm, so renders agree to about 1e-4 of peak. GDScript calls them through `AKDsp.nat()` and uses its own code when the library isn't there. Turn the native path off with `AKDsp.native_enabled = false`.
- **`AKLiveStream`**: the live mixer, an `AudioStream` whose playback mixes at 48 kHz. Pre-rendered buffers are scheduled at exact timeline frames on buses (faders, sidechain ducking), continuous voices (oscillators, or recipe loops at a gliding rate) glide their parameters as they play, and a shared Freeverb send and a master chain (gain, filters, drive, bitcrush, echo, room, end fade, limiter) run on the stream. The GDScript wrapper is `AKLive` (`addons/audio_kit/core/live.gd`); the scene nodes are `AKLivePlayer` and `AKLiveVoice`.

Recipes don't change: the kit renders the same with or without the native core, only faster.

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

`tests/test_native.gd` renders every kernel, every voice and a full cue sheet both ways and compares them. `tests/test_live.gd` holds the live mixer to the baked render (the Phase 3 gate): E1 with music matches at SNR 140 dB.
