# Your own samples

How WAV, AIFF and OGG files you recorded or downloaded become instruments, drum kits and library entries. Step by step in the Sound Lab: tutorial 12 in `docs/tutorials/index.md`. The data types (`AKSample`, `AKKit`, the `sample` voice) are described in `docs/loops.md`.

There are four routes, by what you have:

| You have | Route | Where it ends up |
| --- | --- | --- |
| A few sounds for this project | Copy them under `res://audio/` and pick them on the Loops page | `AKSample`s beside the files; kits in `res://audio/kits/` |
| A pitched instrument recorded at several notes | Sample matching (`AKSampleMatch.run_wav`) | A synth patch made of the instrument's own tone (`docs/sample_matching.md`) |
| A large collection of drum sample packs | The drum library tools (`tools/drum_prep/`) | A drum library folder, browsed in the Drums tab (`docs/drums.md`) |
| A sound made by code | A recipe as the sample's source | Rendered on demand, nothing binary stored |

## Formats

`AKAudioFile` reads the files itself rather than through Godot's import, because imported streams can't be read back sample by sample and are often compressed.

| Format | Read | Refused |
| --- | --- | --- |
| WAV | 8, 16, 24, 32-bit PCM; 32, 64-bit float; WAVE_FORMAT_EXTENSIBLE; any rate and channel count; a `smpl` chunk's root note and first loop | Compressed WAVs (ADPCM and the like) |
| AIFF, AIFF-C | 8, 16, 24, 32-bit PCM, big- or little-endian (`sowt`); 32, 64-bit float; an `INST` chunk's base note and sustain loop | Compressed AIFF-C (`ima4`, `ulaw` and the like) |
| OGG Vorbis | Godot's decoder, sample-exact | – |

The format is told from the file's first bytes, so an AIFF named `.wav` reads. A two-channel file stays stereo unless its channels are identical (then it's kept mono). Files with more channels are mixed to mono. Anything else (MP3, FLAC): convert to WAV first.

## In a project

1. **Put the files under `res://audio/`.** The Loops page's **Sounds** tab lists every audio file and `.sample.tres` there (folder menu: **project**). It reads the folder when the Sound Lab opens; after adding files while it's open, use **Project → Reload Current Project**.
2. **Pick one.** Double-clicking a file with a sample loop open (or **Use selected** / **+ Piece** on a kit) makes an `AKSample` beside it: `snare.wav` → `snare.sample.tres`, reused on later picks.
3. **Check the root note.** It comes from the file's `smpl` / `INST` chunk when there is one; otherwise the harmonic pitch test measures it (MIDI 24–108, on the loudest stretch just after the attack; unpitched sounds keep 60). **Detect** measures again, and the **Root** box takes a MIDI note number. Check by ear: a strong overtone can fool the test.
4. **Set how it plays** in the sample panel: **Mode** (`oneshot`, `gate`, `loop`), **Start s** / **End s** (trim), **Loop from** / **Loop to**, **Release s**, **Gain dB**, **Reverse**.

The `.sample.tres` holds the decoded audio (`data`, plus `data_r` for stereo), so exported games play it without the source file or the import settings. It's stored as text, several times the WAV's size, so trim long files before you import them.

In code:

```gdscript
var s := AKSample.new()
s.source = "res://audio/samples/cello_c3.wav"
var err := s.import_source(true)          # "" when it read; true takes the root note and loop from the file
s.mode = "loop"
ResourceSaver.save(s, "res://audio/samples/cello_c3.sample.tres")

var f := AKAudioFile.read("res://audio/samples/cello_c3.wav")   # just the samples
print(f.rate, " Hz, ", f.channels, " ch, root ", f.root_note, ", loop ", f.loop)
```

`AKSample.samples()` gives `[mono, rate]` and `stereo_samples()` `[left, right, rate]`, for analysis.

## Kits from your files

On a percussive loop, the kit panel's **Use selected** puts the sound selected in **Sounds** on a row, and **+ Piece** adds it as a new row (named after the file). Name rows after the General MIDI drum map (`kick`, `snare`, `clap`, `closed_hat`, `open_hat`, `pedal_hat`, `tom_low`, `tom_mid`, `tom_high`, `crash`, `ride`, ...) so `.mid` drum parts and pad controllers play the right pieces. Give the hats one choke group so a closed hat cuts an open one; tick **Gate** for a piece that stops when its note ends. **Save kit** writes `res://audio/kits/<name>.tres`; a shipped kit is edited as a copy.

**Velocity layers and round-robin** have no panel yet. In the kit `.tres` (or the Inspector), give a piece `layers` instead of `sound`:

```gdscript
{name = "snare", choke = "", layers = [
	{sound = "res://audio/samples/snare_soft.sample.tres", up_to = 0.4},
	{sound = ["res://audio/samples/snare_hard_1.sample.tres", "res://audio/samples/snare_hard_2.sample.tres"], up_to = 1.0}]}
```

A hit plays the first layer whose `up_to` reaches its velocity; a list is a set of takes played in turn. Details: `docs/loops.md`, AKKit.

## Pitched instruments: sample matching

A WAV of an instrument's held notes up the keyboard (a multisample) can become a synth patch rather than a sample: the matcher takes the instrument's own waveforms every few semitones into a key-zoned wavetable, with its decay and level across the keyboard, and fits a lighter version too. It needs the native core.

```gdscript
var res := AKSampleMatch.new().run_wav("res://audio/rec/epiano_holds.wav", 36, 12)   # first note C2, a note every 12 semitones
ResourceSaver.save(res.full, "res://audio/patches/epiano.tres")
ResourceSaver.save(res.lite, "res://audio/patches/epiano_lite.tres")
```

The arguments and what it can copy (detuned layers, vibrato, chorus-like movement, delay, reverb): `docs/sample_matching.md`. The Auxy route, with a panel, is tutorial 9.

## Large collections: the drum library

For hundreds of sample packs, the drum library tools (Python 3 with numpy) convert them losslessly to WAV folders, tag each sound from its name and its sound, and build kits; the **Drums** tab then browses and copies from the result. See "Adding your own collection" in `docs/drums.md`, and `tools/drum_prep/README.md` for each step.

## Recipes as samples

A sample's `source` (or `recipe`) can be a recipe instead of a file: it's rendered once per bake key and cached, and nothing binary is stored. The kit-made library's 128 sounds work this way (`docs/loops.md`, The kit-made library).

## Limits

- The Sounds list only looks under `res://audio/`, and only re-reads it when the Sound Lab opens.
- The `.sample.tres` is text: large for long sounds.
- Resampling is the only way to change pitch, so a sample played far from its root changes length and character with it. For a playable instrument across a wide range, record several notes (and make a kit-style layer set or match it as a patch).
- MP3 and FLAC aren't read.
