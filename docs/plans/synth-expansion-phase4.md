# Synth expansion, phase 4: phase distortion and CZ envelopes (F4, F2 `cz`), layered instruments (F8)

Status: **built** (2026-11-23): F4 phase distortion and the F2 `cz` mode, with the CZ converter (see "As built"); F8 is deferred (2026-11-23: no source in the library needs it yet). Part of `docs/plans/synth-expansion.md`. Phases 0 to 3 are built.

## Sources and references

- **Patches:** the 48 Casio CZ-101 tones from Polynominal (`D:/12_library/gak/to_process/Polynominal/Casio CZ-101`, raw SysEx), decoded by `tools/open_samples_prep/osp/cz.py`.
- **The sound chip:** MAME's uPD933 emulation (`src/devices/sound/upd933.cpp`, Devin Acker, BSD-3-Clause), the CZ's phase-distortion chip: its eight transfer functions (saw, square, pulse, double sine, saw-pulse, resonance, and two undocumented ones), its six windows, its envelopes (a rate and a target per step, linear in its own units, 40 kHz), its log volume curve, ring modulation and noise pitch modulation. BSD-3 lets the engine port it, with the notice kept, as msfa (Apache-2.0) was for the DX7.
- **The firmware:** no CZ ROM is available, so how tone data becomes chip writes (the step sequencing, key follow, vibrato, line modes and detune) comes from the CZ's documented SysEx format and the manual. What is known and what is guessed is listed in the converter's README.
- **Reference renders:** `tools/cz_ref`, a harness that builds MAME's `upd933.cpp` unchanged (with small shims for MAME's device classes) and drives it from a tone's data through that firmware model, at the chip's 40 kHz. It checks the engine port exactly. It can't check the firmware model, which it shares with the converter.

## What this phase builds

### F4. Phase distortion oscillator

- `shape = "pd"`, with `pd_wave` (`saw`, `square`, `pulse`, `double_sine`, `saw_pulse`, `resonance`, `double_pulse`), an optional `pd_wave2` (the chip alternates the two, a cycle each: the CZ's wave pairs), `pd_window` (`none`, `saw`, `triangle`, `trapezoid`, `pulse`, `double_saw`) and `pd_amount` (0..1, the CZ's DCW).
- `shape_env`: an envelope that drives `pd_amount`, and a matrix destination `oscN.pd`.
- The chip's high-pitch limit on the DCW (narrow waves stay audible, very high notes don't alias) applies, as on the chip.
- `pd_noise`: the chip's noise pitch modulation (CZ line 2's "noise" modulation).
- Usable by hand-made patches; nothing CZ-only in it.

### F2. `cz` envelope mode

- `{mode = "cz", kind = "dca" | "dcw" | "dco", steps = [[rate, level], ...], sustain, end}` in the CZ's values, run as the chip runs them: linear in the chip's units at its rate table, scaled from 40 kHz to the mix rate.
- `dca` drives an oscillator's level through the chip's log volume curve (as `level_env`); `dcw` drives `pd_amount` (as `shape_env`); `dco` drives pitch in the chip's semitone units (routed with the matrix, as `dx7_pitch`).

### F8. Layered instruments (deferred, 2026-11-23)

Deferred by the user: the M3R combinations wait on measured `m1` timing (and most M3R programs on PCM waves the library lacks), the CZ's line modes fit one patch, and live layering needs native engine work and changes wherever a patch is played (the MIDI router, recipe voices, sequencer lanes, loops). Taken up when a source needs it.


- `AKLayered` (decided 2026-11-20), beside `AKPatch`: `layers: [{patch, key_range, velocity_range, transpose, detune_cents, level_db, pan}]` and `mode` (`stack`, `split`, `velocity_switch`). Each layer is an ordinary patch. Players accept it wherever they take a patch.
- The CZ's line modes 1+1' and 1+2' don't need it: they fit one patch with per-oscillator envelopes (F3). It serves M3R combinations (their 232 basic-wave programs, once `m1` timing is measured), D-50 upper/lower if those are fetched, and hand-made splits and stacks.

## Promise (as before)

- **Old patches keep their samples.** Patches without the new fields render the same samples, natively and in GDScript (the before/after hashes). New fields enter `describe()` only when set.
- **Both engines agree** within 1e-6 on the new features.
- **The port matches the chip:** GAK's render of a converted CZ tone at 40 kHz against `tools/cz_ref`'s, per tone.

## As built (F4, F2 `cz`; 2026-11-23)

- **Engine.** `shape = "pd"` (`pd_wave`, `pd_wave2`, `pd_window`, `pd_amount` as the oscillator's position, `pd_noise`), and per oscillator `shape_env` and `pitch_env`; `mode = "cz"` envelopes (`kind` dca, dcw, dco). Both engines; user docs in `docs/synth.md` (Oscillators: Phase distortion; Envelopes: CZ). The waveform is the chip's own integer arithmetic (an 11-bit phase, integer divisions, a 12-bit cosine table), the envelopes float in the chip's units. Native and GDScript agree to the bit on the reference cases.
- **Against the chip.** `tools/cz_ref` builds MAME's `upd933.cpp` unchanged, behind a small shim (`emu.h`), and steps the envelopes as the firmware is documented to; `make_ref.py` writes `tests/data/cz_ref.json` (15 cases: every wave, every window with the resonance wave, a wave pair, a high note, a pitch envelope, ring modulation). `tests/test_cz.gd` holds the native engine to it: 29–45 dB SNR per case (most near 45). What's left is an edge a sample apart (the double pulse and resonance windows), the chip's coarse fine-pitch table under a pitch envelope, and the envelope running a sample ahead.
- **Old patches** render the same samples (hashes unchanged). The engine's `VERSION` stays 3: no existing patch's output changed.
- **Not built:** the cz envelope's key follow (the firmware's tables are documented as numbers, not as what they do); the `pd` oscillator ignores `fm`, `sync_to` and `fm_mode`.
- **Converter.** `osp/cz.py` decodes the tone SysEx (layout, formulas and sources in its docstring); `tools/patch_convert/cz.gd` and `cz_batch.gd` convert Polynominal's 48 CZ-101 tones (README: Casio CZ). Vibrato units, DCW key follow and tuning are approximations; DCA key follow is left out.
