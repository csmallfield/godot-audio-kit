# SPDX-License-Identifier: Apache-2.0
@tool
## Sound-shaping effects that stream a stereo sample at a time: chorus,
## flanger, phaser, eq, compressor, saturate, and the character effects
## speech voices use: pitch (a shifted layer), ring, growl, crush, delay, reverb. The reference for the native
## effects (native/src/fx.h), which run the same steps in the same order, and
## the fallback without the native core. One effect is a spec dictionary:
##
##   {type = "chorus", rate_hz = 0.8, depth_ms = 3.0, delay_ms = 12.0, voices = 2, mix = 0.5, spread = 1.0, feedback = 0.0}
##   {type = "flanger", rate_hz = 0.25, depth_ms = 2.0, delay_ms = 1.0, feedback = 0.6, mix = 0.5, spread = 1.0}
##   {type = "phaser", rate_hz = 0.4, stages = 4, center_hz = 800.0, range_octaves = 2.0, depth = 1.0, feedback = 0.4, mix = 0.5, spread = 1.0}
##   {type = "eq", low_db = 0.0, low_hz = 120.0, mid_db = 0.0, mid_hz = 1000.0, mid_q = 0.7, high_db = 0.0, high_hz = 6000.0}
##   {type = "compressor", threshold_db = -18.0, ratio = 4.0, attack_s = 0.01, release_s = 0.12, knee_db = 6.0, makeup_db = 0.0}
##   {type = "saturate", drive_db = 12.0, tone_hz = 6000.0, asymmetry = 0.0, mix = 1.0, output_db = 0.0}
##   {type = "pitch", semitones = -12.0, window_ms = 60.0, mix = 0.5}         a copy shifted in pitch, blended
##   {type = "ring", freq_hz = 220.0, rate_hz = 0.0, depth = 0.0, mix = 1.0}  ring modulation (depth: octaves the carrier sweeps)
##   {type = "growl", rate_hz = 45.0, depth = 0.6, jitter = 0.5, mix = 1.0}   rough loudness pulses: a rasp
##   {type = "crush", bits = 8.0, hold = 1, mix = 1.0}                        fewer bits, held samples
##   {type = "delay", time_ms = 250.0, feedback = 0.35, damp_hz = 4000.0, mix = 0.3}
##     (also mode = stereo|cross|pingpong, spread_ms -100..100: the right channel's
##     repeats later by that much, the left's for a negative value)
##     (or time_sync = "1/8." in place of time_ms: a note length at the tempo,
##     which a synth patch's player sets; 120 BPM elsewhere)
##   {type = "reverb", room = 0.6, damp = 0.5, width = 1.0, mix = 0.25}
##     (also predelay_ms, and low_cut_hz / high_cut_hz: one-pole filters on what goes
##     into the reverb; 0, the default, leaves each off)
##   {type = "filter", mode = "lowpass", cutoff_hz = 1000.0, q = 0.707, slope_db = 12.0}
##     (mode lowpass|highpass; slope_db 6 one pole, 12 or 24 a state-variable filter)
##   {type = "freqshift", shift_hz = 100.0, stereo = 0.0, echo_ms = 0.0, feedback = 0.0, mix = 1.0}
##     (every partial moved by shift_hz, single sideband; stereo 1 shifts the right
##     channel the other way; feedback runs back in through an echo of echo_ms)
##   {type = "rotary", speed = 0.0, horn_hz = 6.7, drum_hz = 5.7, accel_s = 0.5, drive = 0.0,
##     spread = 1.0, crossover_hz = 800.0, doppler = 1.0, tremolo = 1.0, mix = 1.0}
##     (a two-way rotary speaker; speed 0 slow .. 1 fast, or "slow" / "fast")
##   {type = "stutter", rate_hz = 8.0, resample_hz = 1.0, softness = 0.2, pitch = 0.0, mix = 1.0}
##     (repeats the last slice of the input, 1 / rate_hz long, taking a new one every
##     1 / resample_hz; or rate_sync / resample_sync = note lengths at the tempo)
##   {type = "conditioner", bass_db, treble_db, width, balance, threshold_db, attack_ms, release_ms, output_db}
##   {type = "geq", band1_db .. band11_db, output_db}   (30 Hz .. 16 kHz, peaks of +-12 dB)
##   {type = "resonator", freq1_hz, freq2_hz, freq3_hz, q1 .. q3, gain1_db .. gain3_db, series, output_db, mix}
##   {type = "exciter", freq_hz = 3000.0, drive = 0.5, mix = 0.5}
##   {type = "waveshaper", curve = "soft", drive_db = 6.0, bias, pre_hp_hz, post_lp_hz, output_db, mix}
##   {type = "midside", mid_db, side_db, side_hp_hz, mid_pan}
##   {type = "ensemble", slow_hz, slow_depth, fast_hz, fast_depth, center_ms, tone_hz, width, mix}
##   {type = "combulator", tune_hz, offset2, offset3, resonance, tone_hz, noise, gain1_db .. gain3_db, width, mix}
##   {type = "tape", drive_db, hyst, wow, flutter, bump_hz, bump_db, hf_hz, output_db, mix}
##   {type = "treemonster", threshold_db, glide_ms, pitch, track_lp_hz, track_hp_hz, width, mix}
##   {type = "spring", decay_s, chirp, length_ms, tone_hz, width, mix}
##   {type = "bonsai", bass_hz, boost_db, harmonics, drive_db, tone_hz, output_db, mix}
##   {type = "chow", threshold_db, ratio, flip, drive_db, tone_hz, output_db, mix}
##   {type = "neuron", size_ms, regen, drive, wobble, wobble_hz, tone_hz, width, mix}
##   {type = "granular", position, size, pitch, density, texture, recycle, pan_spread, reverb, freeze, mix}
##     (a port of Mutable Instruments Clouds' granular mode, MIT: see NOTICE)
##   {type = "airwindows", name = "density", a .. f}
##     (ports of Airwindows plugins, MIT: see NOTICE; name one of AW_NAMES, a .. f its parameters
##     in order, 0..1 as the plugin's sliders, or by AW_PARAMS' names; unset ones take the plugin's defaults)
##   {type = "limiter", ceiling_db = -1.0, release_s = 0.08}
##     (a peak limiter, as AKDynamics.limit: instant attack, exponential release,
##     both channels linked, no lookahead; nothing leaves above the ceiling, and a
##     signal that stays under it passes unchanged)
## Delay and reverb add their wet signal at `mix` and keep the dry; the filter and
## the limiter are all wet; the others crossfade dry to wet.
##
## The same specs go in a recipe's `fx`, a patch's `effects`, and (as the
## AKChorus, AKPhaser ... bus effects' properties) on a Godot bus.
class_name AKStreamFx
extends RefCounted

## A delay's modes: each channel repeating itself, the repeats crossing
## sides, or the input (both channels) bouncing left, right, left.
const DELAY_MODES := ["stereo", "cross", "pingpong"]
const FILTER_MODES := ["lowpass", "highpass"]
const TYPES := ["", "chorus", "flanger", "phaser", "eq", "compressor", "saturate", "pitch", "ring", "growl", "crush", "delay", "reverb",
	"filter", "limiter", "freqshift", "rotary", "stutter", "conditioner", "geq", "resonator", "exciter", "waveshaper", "midside",
	"ensemble", "combulator", "tape", "treemonster", "spring", "bonsai", "chow", "neuron", "granular", "airwindows"]
const T_FREQSHIFT := 15
const T_ROTARY := 16
const T_STUTTER := 17
const T_CONDITIONER := 18
const T_GEQ := 19
const T_RESONATOR := 20
const T_EXCITER := 21
const T_WAVESHAPER := 22
const T_MIDSIDE := 23
const T_ENSEMBLE := 24
const T_COMBULATOR := 25
const T_TAPE := 26
const T_TREEMONSTER := 27
const T_SPRING := 28
const T_BONSAI := 29
const T_CHOW := 30
const T_NEURON := 31
const T_GRANULAR := 32
const T_AIRWINDOWS := 33
## The Airwindows algorithms (the `name` setting; its index is the compiled `algo`), their
## parameters' names in order (a, b, c ...), and their defaults (ak::Fx::aw_defaults).
const AW_NAMES := ["density", "console7channel", "console7buss", "console7", "purestdrive", "tube", "capacitor", "totape6", "air",
	"galactic"]
const AW_PARAMS := {"density": ["density", "highpass", "out_level", "dry_wet"], "console7channel": ["fader"],
	"console7buss": ["master"], "console7": ["fader", "master"], "purestdrive": ["drive"], "tube": ["tube"],
	"capacitor": ["lowpass", "highpass", "dry_wet"], "totape6": ["input", "soften", "head_bump", "flutter", "output", "dry_wet"],
	"air": ["tap_22k", "tap_15k", "tap_11k", "filters_q", "output_level", "dry_wet"],
	"galactic": ["replace", "brightness", "detune", "bigness", "dry_wet"]}
const AW_DEFAULTS := [[0.2, 0.0, 1.0, 1.0, 0.0, 0.0], [0.772, 0.0, 0.0, 0.0, 0.0, 0.0], [1.0, 0.0, 0.0, 0.0, 0.0, 0.0],
	[0.772, 1.0, 0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0, 0.0, 0.0], [1.0, 0.0, 1.0, 0.0, 0.0, 0.0],
	[0.5, 0.5, 0.5, 0.5, 0.5, 1.0], [0.5, 0.5, 0.5, 0.0, 1.0, 1.0], [0.5, 0.5, 0.5, 1.0, 1.0, 0.0]]
const AW_LETTERS := ["a", "b", "c", "d", "e", "f"]
const AW_DENSITY := 0
const AW_CONSOLE7CH := 1
const AW_CONSOLE7BUSS := 2
const AW_CONSOLE7 := 3
const AW_PURESTDRIVE := 4
const AW_TUBE := 5
const AW_CAPACITOR := 6
const AW_TOTAPE6 := 7
const AW_AIR := 8
const AW_GALACTIC := 9
const AW_TT_D := 40
const GA_B0 := 64
const GA_OFF := [64, 13024, 20344, 23784, 25144, 44544, 56544, 61184, 63064, 93504, 110424, 119504, 125904]
const GA_LEN := [6480, 3660, 1720, 680, 9700, 6000, 2320, 940, 15220, 8460, 4540, 3200, 3111]
const GA_DLY := [3407.0, 1823.0, 859.0, 331.0, 4801.0, 2909.0, 1153.0, 461.0, 7607.0, 4217.0, 2269.0, 1597.0]
const AW_STATE := 64
const AW_BLOCK := 512
## The granular effect's layout and Clouds' line lengths (ak::Fx::GR_*).
const GR_NG := 32
const GR_GV := 12
const GR_TAIL := 256
const GR_G0 := 64
const GR_T0 := 64 + 32 * 12
const GR_B0 := 64 + 32 * 12 + 2 * 256
const GR_DIF := [126, 180, 269, 444, 151, 205, 245, 405]
const GR_REV := [113, 162, 241, 399, 1653, 2038, 3411, 1913, 1663, 4782]
## Clouds' grain window table, (1 - cos(pi t)) / 2 in 4096 steps (built on first use).
static var _gr_win := PackedFloat64Array()
## Group B's line sizes and constants (ak::Fx::EN_LINE_MS ... NE_R).
const EN_LINE_MS := 48.0
const TP_LINE_MS := 6.0
const TP_BASE_MS := 3.0
const SP_STAGES := 40
const SP_LINE_MS := 92.0
const NE_LINE_S := 0.3
const NE_R := [1.0, 0.811, 0.677, 0.543]
## The graphic EQ's band centres, and the waveshaper's curves by name (ak::Fx::GEQ_HZ, ws_curve).
const GEQ_HZ := [30.0, 60.0, 120.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 12000.0, 16000.0]
const WS_CURVES := ["soft", "hard", "fold", "sine", "asym", "digital"]
## The stutter's longest slice (ak::Fx::ST_MAX_S).
const ST_MAX_S := 1.0
const DEFAULTS := {
	"chorus": {rate_hz = 0.8, depth_ms = 3.0, delay_ms = 12.0, voices = 2, mix = 0.5, spread = 1.0, feedback = 0.0},
	"flanger": {rate_hz = 0.25, depth_ms = 2.0, delay_ms = 1.0, voices = 1, mix = 0.5, spread = 1.0, feedback = 0.6},
	"phaser": {rate_hz = 0.4, stages = 4, center_hz = 800.0, range_octaves = 2.0, depth = 1.0, feedback = 0.4, mix = 0.5, spread = 1.0},
	"eq": {low_db = 0.0, low_hz = 120.0, mid_db = 0.0, mid_hz = 1000.0, mid_q = 0.7, high_db = 0.0, high_hz = 6000.0},
	"compressor": {threshold_db = -18.0, ratio = 4.0, attack_s = 0.01, release_s = 0.12, knee_db = 6.0, makeup_db = 0.0},
	"saturate": {drive_db = 12.0, tone_hz = 6000.0, asymmetry = 0.0, mix = 1.0, output_db = 0.0},
	"pitch": {semitones = -12.0, window_ms = 60.0, mix = 0.5},
	"ring": {freq_hz = 220.0, rate_hz = 0.0, depth = 0.0, mix = 1.0},
	"growl": {rate_hz = 45.0, depth = 0.6, jitter = 0.5, mix = 1.0},
	"crush": {bits = 8.0, hold = 1, mix = 1.0},
	"delay": {time_ms = 250.0, feedback = 0.35, damp_hz = 4000.0, mix = 0.3},
	"reverb": {room = 0.6, damp = 0.5, width = 1.0, mix = 0.25, predelay_ms = 0.0, low_cut_hz = 0.0, high_cut_hz = 0.0},
	"filter": {mode = 0, cutoff_hz = 1000.0, q = 0.707, slope_db = 12.0},
	"limiter": {ceiling_db = -1.0, release_s = 0.08},
	"freqshift": {shift_hz = 100.0, stereo = 0.0, echo_ms = 0.0, feedback = 0.0, mix = 1.0},
	"rotary": {speed = 0.0, horn_hz = 6.7, drum_hz = 5.7, accel_s = 0.5, drive = 0.0, spread = 1.0, crossover_hz = 800.0,
		doppler = 1.0, tremolo = 1.0, mix = 1.0},
	"stutter": {rate_hz = 8.0, resample_hz = 1.0, softness = 0.2, pitch = 0.0, mix = 1.0},
	"conditioner": {bass_db = 0.0, treble_db = 0.0, width = 1.0, balance = 0.0, threshold_db = 0.0, attack_ms = 5.0, release_ms = 120.0, output_db = 0.0},
	"geq": {band1_db = 0.0, band2_db = 0.0, band3_db = 0.0, band4_db = 0.0, band5_db = 0.0, band6_db = 0.0, band7_db = 0.0, band8_db = 0.0, band9_db = 0.0, band10_db = 0.0, band11_db = 0.0, output_db = 0.0},
	"resonator": {freq1_hz = 300.0, freq2_hz = 1200.0, freq3_hz = 3500.0, q1 = 8.0, q2 = 8.0, q3 = 8.0, gain1_db = 0.0, gain2_db = 0.0, gain3_db = 0.0, series = 0.0, output_db = 0.0, mix = 1.0},
	"exciter": {freq_hz = 3000.0, drive = 0.5, mix = 0.5},
	"waveshaper": {curve = 0.0, drive_db = 6.0, bias = 0.0, pre_hp_hz = 0.0, post_lp_hz = 0.0, output_db = 0.0, mix = 1.0},
	"midside": {mid_db = 0.0, side_db = 0.0, side_hp_hz = 0.0, mid_pan = 0.0},
	"ensemble": {slow_hz = 0.6, slow_depth = 0.5, fast_hz = 6.0, fast_depth = 0.2, center_ms = 10.0, tone_hz = 9000.0, width = 1.0, mix = 0.5},
	"combulator": {tune_hz = 220.0, offset2 = 7.0, offset3 = 12.0, resonance = 0.9, tone_hz = 6000.0, noise = 0.0, gain1_db = 0.0,
		gain2_db = 0.0, gain3_db = 0.0, width = 0.7, mix = 1.0},
	"tape": {drive_db = 6.0, hyst = 0.3, wow = 0.2, flutter = 0.2, bump_hz = 80.0, bump_db = 3.0, hf_hz = 12000.0, output_db = 0.0, mix = 1.0},
	"treemonster": {threshold_db = -40.0, glide_ms = 20.0, pitch = 0.0, track_lp_hz = 1200.0, track_hp_hz = 40.0, width = 0.0, mix = 1.0},
	"spring": {decay_s = 2.0, chirp = 0.6, length_ms = 35.0, tone_hz = 4500.0, width = 1.0, mix = 0.3},
	"bonsai": {bass_hz = 120.0, boost_db = 6.0, harmonics = 0.3, drive_db = 3.0, tone_hz = 12000.0, output_db = 0.0, mix = 1.0},
	"chow": {threshold_db = -12.0, ratio = 10.0, flip = 0.0, drive_db = 12.0, tone_hz = 20000.0, output_db = 0.0, mix = 1.0},
	"neuron": {size_ms = 40.0, regen = 0.6, drive = 0.3, wobble = 0.2, wobble_hz = 0.3, tone_hz = 6000.0, width = 1.0, mix = 0.5},
	"granular": {position = 0.5, size = 0.5, pitch = 0.0, density = 0.7, texture = 0.5, recycle = 0.0, pan_spread = 0.5, reverb = 0.0,
		freeze = 0.0, mix = 0.5},
	"airwindows": {algo = 0.0, a = -1.0, b = -1.0, c = -1.0, d = -1.0, e = -1.0, f = -1.0},
}
## The newer types' own knobs: [name, default, low, high] in the order ak::Fx::xkeys
## keeps them (its xk[]); compile fills and clamps them.
const XKEYS := {
	"freqshift": [["shift_hz", 100.0, -20000.0, 20000.0], ["stereo", 0.0, 0.0, 1.0], ["echo_ms", 0.0, 0.0, 1000.0]],
	"rotary": [["speed", 0.0, 0.0, 1.0], ["horn_hz", 6.7, 0.1, 15.0], ["drum_hz", 5.7, 0.1, 15.0], ["accel_s", 0.5, 0.01, 10.0],
		["drive", 0.0, 0.0, 1.0], ["spread", 1.0, 0.0, 1.0], ["crossover_hz", 800.0, 100.0, 4000.0], ["doppler", 1.0, 0.0, 2.0],
		["tremolo", 1.0, 0.0, 2.0]],
	"stutter": [["rate_hz", 8.0, 1.0, 100.0], ["resample_hz", 1.0, 0.05, 100.0], ["softness", 0.2, 0.0, 1.0], ["pitch", 0.0, -24.0, 24.0],
		["rate_beats", 0.0, 0.0, 16.0], ["resample_beats", 0.0, 0.0, 64.0]],
	"conditioner": [["bass_db", 0.0, -24.0, 24.0], ["treble_db", 0.0, -24.0, 24.0], ["width", 1.0, 0.0, 2.0], ["balance", 0.0, -1.0, 1.0], ["threshold_db", 0.0, -48.0, 0.0], ["attack_ms", 5.0, 0.1, 200.0], ["release_ms", 120.0, 1.0, 3000.0], ["output_db", 0.0, -24.0, 24.0]],
	"geq": [["band1_db", 0.0, -12.0, 12.0], ["band2_db", 0.0, -12.0, 12.0], ["band3_db", 0.0, -12.0, 12.0], ["band4_db", 0.0, -12.0, 12.0], ["band5_db", 0.0, -12.0, 12.0], ["band6_db", 0.0, -12.0, 12.0], ["band7_db", 0.0, -12.0, 12.0], ["band8_db", 0.0, -12.0, 12.0], ["band9_db", 0.0, -12.0, 12.0], ["band10_db", 0.0, -12.0, 12.0], ["band11_db", 0.0, -12.0, 12.0], ["output_db", 0.0, -24.0, 24.0]],
	"resonator": [["freq1_hz", 300.0, 20.0, 20000.0], ["freq2_hz", 1200.0, 20.0, 20000.0], ["freq3_hz", 3500.0, 20.0, 20000.0], ["q1", 8.0, 0.5, 100.0], ["q2", 8.0, 0.5, 100.0], ["q3", 8.0, 0.5, 100.0], ["gain1_db", 0.0, -48.0, 24.0], ["gain2_db", 0.0, -48.0, 24.0], ["gain3_db", 0.0, -48.0, 24.0], ["series", 0.0, 0.0, 1.0], ["output_db", 0.0, -24.0, 24.0]],
	"exciter": [["freq_hz", 3000.0, 500.0, 16000.0], ["drive", 0.5, 0.0, 1.0]],
	"waveshaper": [["curve", 0.0, 0.0, 5.0], ["drive_db", 6.0, -24.0, 48.0], ["bias", 0.0, -1.0, 1.0], ["pre_hp_hz", 0.0, 0.0, 2000.0], ["post_lp_hz", 0.0, 0.0, 20000.0], ["output_db", 0.0, -48.0, 24.0]],
	"midside": [["mid_db", 0.0, -48.0, 24.0], ["side_db", 0.0, -48.0, 24.0], ["side_hp_hz", 0.0, 0.0, 2000.0], ["mid_pan", 0.0, -1.0, 1.0]],
	"ensemble": [["slow_hz", 0.6, 0.01, 10.0], ["slow_depth", 0.5, 0.0, 1.0], ["fast_hz", 6.0, 0.5, 20.0], ["fast_depth", 0.2, 0.0, 1.0],
		["center_ms", 10.0, 2.0, 30.0], ["tone_hz", 9000.0, 1000.0, 20000.0], ["width", 1.0, 0.0, 1.0]],
	"combulator": [["tune_hz", 220.0, 20.0, 4000.0], ["offset2", 7.0, -24.0, 24.0], ["offset3", 12.0, -24.0, 24.0], ["resonance", 0.9, -0.995, 0.995],
		["tone_hz", 6000.0, 200.0, 20000.0], ["noise", 0.0, 0.0, 1.0], ["gain1_db", 0.0, -48.0, 24.0], ["gain2_db", 0.0, -48.0, 24.0],
		["gain3_db", 0.0, -48.0, 24.0], ["width", 0.7, 0.0, 1.0]],
	"tape": [["drive_db", 6.0, -12.0, 36.0], ["hyst", 0.3, 0.0, 1.0], ["wow", 0.2, 0.0, 1.0], ["flutter", 0.2, 0.0, 1.0], ["bump_hz", 80.0, 30.0, 250.0],
		["bump_db", 3.0, 0.0, 12.0], ["hf_hz", 12000.0, 1000.0, 20000.0], ["output_db", 0.0, -24.0, 24.0]],
	"treemonster": [["threshold_db", -40.0, -80.0, 0.0], ["glide_ms", 20.0, 0.0, 500.0], ["pitch", 0.0, -48.0, 48.0], ["track_lp_hz", 1200.0, 100.0, 8000.0],
		["track_hp_hz", 40.0, 10.0, 1000.0], ["width", 0.0, 0.0, 1.0]],
	"spring": [["decay_s", 2.0, 0.2, 10.0], ["chirp", 0.6, 0.0, 0.85], ["length_ms", 35.0, 10.0, 80.0], ["tone_hz", 4500.0, 500.0, 12000.0],
		["width", 1.0, 0.0, 1.0]],
	"bonsai": [["bass_hz", 120.0, 40.0, 400.0], ["boost_db", 6.0, 0.0, 18.0], ["harmonics", 0.3, 0.0, 1.0], ["drive_db", 3.0, -12.0, 24.0],
		["tone_hz", 12000.0, 1000.0, 20000.0], ["output_db", 0.0, -24.0, 24.0]],
	"chow": [["threshold_db", -12.0, -48.0, 0.0], ["ratio", 10.0, 1.0, 100.0], ["flip", 0.0, 0.0, 1.0], ["drive_db", 12.0, 0.0, 48.0],
		["tone_hz", 20000.0, 1000.0, 20000.0], ["output_db", 0.0, -48.0, 24.0]],
	"neuron": [["size_ms", 40.0, 2.0, 250.0], ["regen", 0.6, 0.0, 1.2], ["drive", 0.3, 0.0, 1.0], ["wobble", 0.2, 0.0, 1.0], ["wobble_hz", 0.3, 0.01, 10.0],
		["tone_hz", 6000.0, 200.0, 20000.0], ["width", 1.0, 0.0, 1.0]],
	"granular": [["position", 0.5, 0.0, 1.0], ["size", 0.5, 0.0, 1.0], ["pitch", 0.0, -48.0, 48.0], ["density", 0.7, 0.0, 1.0],
		["texture", 0.5, 0.0, 1.0], ["recycle", 0.0, 0.0, 1.0], ["pan_spread", 0.5, 0.0, 1.0], ["reverb", 0.0, 0.0, 1.0], ["freeze", 0.0, 0.0, 1.0]],
	"airwindows": [["algo", 0.0, 0.0, 9.0], ["a", -1.0, -1.0, 1.0], ["b", -1.0, -1.0, 1.0], ["c", -1.0, -1.0, 1.0],
		["d", -1.0, -1.0, 1.0], ["e", -1.0, -1.0, 1.0], ["f", -1.0, -1.0, 1.0]],
}
## Effect settings the matrix moves (`fxN.key` rows, AKPatch): per type, key -> [low, high, log].
## A log key takes a row's amount in octaves (value x 2^amount), the others in the key's units;
## the result is clamped to [low, high]. Settings that size a buffer (window_ms, echo_ms, predelay)
## or pick a structure (voices, stages, mode, slope) aren't here. mod_keys() adds mix, dry, wet and
## feedback to the types that have them.
const MOD_KEYS := {
	"chorus": {rate_hz = [0.001, 100.0, true], depth_ms = [0.0, 50.0, false], delay_ms = [0.03, 50.0, true], spread = [0.0, 1.0, false]},
	"flanger": {rate_hz = [0.001, 100.0, true], depth_ms = [0.0, 50.0, false], delay_ms = [0.03, 50.0, true], spread = [0.0, 1.0, false]},
	"phaser": {rate_hz = [0.001, 100.0, true], center_hz = [20.0, 20000.0, true], range_octaves = [0.0, 8.0, false],
		depth = [0.0, 1.0, false], spread = [0.0, 1.0, false]},
	"eq": {low_db = [-48.0, 48.0, false], low_hz = [10.0, 24000.0, true], mid_db = [-48.0, 48.0, false], mid_hz = [10.0, 24000.0, true],
		mid_q = [0.05, 20.0, true], high_db = [-48.0, 48.0, false], high_hz = [10.0, 24000.0, true]},
	"compressor": {threshold_db = [-80.0, 0.0, false], ratio = [1.0, 100.0, false], knee_db = [0.0, 48.0, false], makeup_db = [-24.0, 48.0, false]},
	"saturate": {drive_db = [-24.0, 60.0, false], tone_hz = [20.0, 24000.0, true], asymmetry = [-2.0, 2.0, false], output_db = [-60.0, 24.0, false]},
	"pitch": {semitones = [-36.0, 36.0, false]},
	"ring": {freq_hz = [0.1, 8000.0, true], rate_hz = [0.001, 100.0, true], depth = [0.0, 8.0, false]},
	"growl": {rate_hz = [0.1, 1000.0, true], depth = [0.0, 1.0, false], jitter = [0.0, 1.0, false]},
	"crush": {bits = [1.0, 24.0, false]},
	"delay": {time_ms = [1.0, 2000.0, true], damp_hz = [100.0, 20000.0, true]},
	"reverb": {room = [0.0, 1.0, false], damp = [0.0, 2.5, false], width = [0.0, 1.0, false]},
	"filter": {cutoff_hz = [10.0, 24000.0, true], q = [0.05, 50.0, true]},
	"limiter": {ceiling_db = [-60.0, 0.0, false]},
	"freqshift": {shift_hz = [-20000.0, 20000.0, false], stereo = [0.0, 1.0, false]},
	"rotary": {speed = [0.0, 1.0, false], horn_hz = [0.1, 15.0, true], drum_hz = [0.1, 15.0, true], accel_s = [0.01, 10.0, true],
		drive = [0.0, 1.0, false], spread = [0.0, 1.0, false], crossover_hz = [100.0, 4000.0, true], doppler = [0.0, 2.0, false],
		tremolo = [0.0, 2.0, false]},
	"stutter": {rate_hz = [1.0, 100.0, true], resample_hz = [0.05, 100.0, true], softness = [0.0, 1.0, false], pitch = [-24.0, 24.0, false]},
	"conditioner": {bass_db = [-24.0, 24.0, false], treble_db = [-24.0, 24.0, false], width = [0.0, 2.0, false], balance = [-1.0, 1.0, false],
		threshold_db = [-48.0, 0.0, false], output_db = [-24.0, 24.0, false]},
	"geq": {band1_db = [-12.0, 12.0, false], band2_db = [-12.0, 12.0, false], band3_db = [-12.0, 12.0, false], band4_db = [-12.0, 12.0, false],
		band5_db = [-12.0, 12.0, false], band6_db = [-12.0, 12.0, false], band7_db = [-12.0, 12.0, false], band8_db = [-12.0, 12.0, false],
		band9_db = [-12.0, 12.0, false], band10_db = [-12.0, 12.0, false], band11_db = [-12.0, 12.0, false], output_db = [-24.0, 24.0, false]},
	"resonator": {freq1_hz = [20.0, 20000.0, true], freq2_hz = [20.0, 20000.0, true], freq3_hz = [20.0, 20000.0, true], q1 = [0.5, 100.0, true],
		q2 = [0.5, 100.0, true], q3 = [0.5, 100.0, true], gain1_db = [-48.0, 24.0, false], gain2_db = [-48.0, 24.0, false],
		gain3_db = [-48.0, 24.0, false], output_db = [-24.0, 24.0, false]},
	"exciter": {freq_hz = [500.0, 16000.0, true], drive = [0.0, 1.0, false]},
	"waveshaper": {drive_db = [-24.0, 48.0, false], bias = [-1.0, 1.0, false], output_db = [-48.0, 24.0, false]},
	"midside": {mid_db = [-48.0, 24.0, false], side_db = [-48.0, 24.0, false], mid_pan = [-1.0, 1.0, false]},
	"ensemble": {slow_hz = [0.01, 10.0, true], slow_depth = [0.0, 1.0, false], fast_hz = [0.5, 20.0, true], fast_depth = [0.0, 1.0, false],
		center_ms = [2.0, 30.0, true], tone_hz = [1000.0, 20000.0, true], width = [0.0, 1.0, false]},
	"combulator": {tune_hz = [20.0, 4000.0, true], offset2 = [-24.0, 24.0, false], offset3 = [-24.0, 24.0, false], resonance = [-0.995, 0.995, false],
		tone_hz = [200.0, 20000.0, true], noise = [0.0, 1.0, false], gain1_db = [-48.0, 24.0, false], gain2_db = [-48.0, 24.0, false],
		gain3_db = [-48.0, 24.0, false], width = [0.0, 1.0, false]},
	"tape": {drive_db = [-12.0, 36.0, false], hyst = [0.0, 1.0, false], wow = [0.0, 1.0, false], flutter = [0.0, 1.0, false],
		bump_hz = [30.0, 250.0, true], bump_db = [0.0, 12.0, false], hf_hz = [1000.0, 20000.0, true], output_db = [-24.0, 24.0, false]},
	"treemonster": {threshold_db = [-80.0, 0.0, false], glide_ms = [0.0, 500.0, false], pitch = [-48.0, 48.0, false],
		track_lp_hz = [100.0, 8000.0, true], track_hp_hz = [10.0, 1000.0, true], width = [0.0, 1.0, false]},
	"spring": {decay_s = [0.2, 10.0, true], chirp = [0.0, 0.85, false], length_ms = [10.0, 80.0, true], tone_hz = [500.0, 12000.0, true],
		width = [0.0, 1.0, false]},
	"bonsai": {bass_hz = [40.0, 400.0, true], boost_db = [0.0, 18.0, false], harmonics = [0.0, 1.0, false], drive_db = [-12.0, 24.0, false],
		tone_hz = [1000.0, 20000.0, true], output_db = [-24.0, 24.0, false]},
	"chow": {threshold_db = [-48.0, 0.0, false], ratio = [1.0, 100.0, true], drive_db = [0.0, 48.0, false], tone_hz = [1000.0, 20000.0, true],
		output_db = [-48.0, 24.0, false]},
	"neuron": {size_ms = [2.0, 250.0, true], regen = [0.0, 1.2, false], drive = [0.0, 1.0, false], wobble = [0.0, 1.0, false],
		wobble_hz = [0.01, 10.0, true], tone_hz = [200.0, 20000.0, true], width = [0.0, 1.0, false]},
	"granular": {position = [0.0, 1.0, false], size = [0.0, 1.0, false], pitch = [-48.0, 48.0, false], density = [0.0, 1.0, false],
		texture = [0.0, 1.0, false], recycle = [0.0, 1.0, false], pan_spread = [0.0, 1.0, false], reverb = [0.0, 1.0, false],
		freeze = [0.0, 1.0, false]},
	"airwindows": {a = [0.0, 1.0, false], b = [0.0, 1.0, false], c = [0.0, 1.0, false], d = [0.0, 1.0, false],
		e = [0.0, 1.0, false], f = [0.0, 1.0, false]},
}
const _MIXED := ["chorus", "flanger", "phaser", "saturate", "pitch", "ring", "growl", "crush", "delay", "reverb", "freqshift", "rotary",
	"stutter", "resonator", "exciter", "waveshaper", "ensemble", "combulator", "tape", "treemonster", "spring", "bonsai", "chow", "neuron", "granular"]
const _FEEDBACK := ["chorus", "flanger", "phaser", "delay", "freqshift"]
## The rotary's speed by name.
const ROTARY_SPEEDS := {"slow": 0.0, "fast": 1.0}
## Clamps for the character effects' knobs (as ak::Fx's parser).
const LIMITS := {semitones = [-36.0, 36.0], window_ms = [5.0, 200.0], freq_hz = [0.1, 8000.0], jitter = [0.0, 1.0],
	bits = [1.0, 24.0], hold = [1, 64], time_ms = [1.0, 2000.0], damp_hz = [100.0, 20000.0], room = [0.0, 1.0],
	damp = [0.0, 2.5], width = [0.0, 1.0], predelay_ms = [0.0, 500.0], low_cut_hz = [0.0, 20000.0],
	high_cut_hz = [0.0, 24000.0]}
# The frequency shifter's Hilbert pair (ak::Fx::HB_A, HB_B) and the rotary's line and slow speed.
const HB_A := [0.6923878, 0.9360654322959, 0.9882295226860, 0.9987488452737]
const HB_B := [0.4021921162426, 0.8561710882420, 0.9722909545651, 0.9952884791278]
const RO_LINE_MS := 4.0
const RO_SLOW := 0.12
const RV_COMBS := [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617]
const RV_PASSES := [556, 441, 341, 225]


## Clouds' grain window table (ak::Fx::gr_window), built once.
static func _gr_window() -> void:
	if not _gr_win.is_empty():
		return
	var w := PackedFloat64Array()
	w.resize(4098)
	for i in 4097:
		w[i] = 1.0 - (cos(i / 4096.0 * PI) + 1.0) / 2.0
	w[4097] = 1.0
	_gr_win = w


## The settings of an effect type the matrix can move: key -> [low, high, log] (MOD_KEYS, with
## mix, dry and wet for the types that blend and feedback for those that have it).
static func mod_keys(t: String) -> Dictionary:
	var d: Dictionary = MOD_KEYS.get(t, {}).duplicate()
	if t in _MIXED:
		d.mix = [0.0, 1.0, false]
		d.dry = [0.0, 4.0, false]
		d.wet = [0.0, 4.0, false]
	if t in _FEEDBACK:
		d.feedback = [-0.95, 0.95, false]
	return d


## True for the types this class streams (recipes route these here).
static func handles(type: StringName) -> bool:
	return DEFAULTS.has(String(type))


## A spec with defaults filled and ranges clamped, as plain numbers (the
## form the native effects take). `type` becomes its index in TYPES.
static func compile(spec: Dictionary) -> Dictionary:
	var t := String(spec.get("type", ""))
	var d: Dictionary = DEFAULTS.get(t, {}).duplicate()
	var beats := 0.0
	for k in spec:
		if String(k) == "time_sync":
			beats = AKPatch.sync_beats(spec[k])
		elif (String(k) == "rate_sync" or String(k) == "resample_sync") and t == "stutter":
			# A synced stutter: its rate (Hz at 120 BPM until the tempo is set) from a note length.
			var sb := AKPatch.sync_beats(spec[k])
			var which := "rate" if String(k) == "rate_sync" else "resample"
			d[which + "_beats"] = sb
			if sb > 0.0:
				d[which + "_hz"] = 2.0 / sb
		elif String(k) == "mode" and t == "delay":
			var m := DELAY_MODES.find(String(spec[k]))
			if m < 0:
				push_warning("AKStreamFx: unknown delay mode '%s'" % spec[k])
			d.mode = maxi(0, m)
		elif String(k) == "mode" and t == "filter":
			var fm := FILTER_MODES.find(String(spec[k]))
			if fm < 0:
				push_warning("AKStreamFx: unknown filter mode '%s'" % spec[k])
			d.mode = maxi(0, fm)
		elif String(k) == "curve" and t == "waveshaper" and spec[k] is String:
			var cv := WS_CURVES.find(String(spec[k]))
			if cv < 0:
				push_warning("AKStreamFx: unknown waveshaper curve '%s'" % spec[k])
			d.curve = maxi(0, cv)
		elif String(k) == "mode" and t == "resonator":
			d.series = 1.0 if String(spec[k]) == "series" else 0.0
		elif String(k) == "speed" and t == "rotary" and spec[k] is String:
			if not ROTARY_SPEEDS.has(spec[k]):
				push_warning("AKStreamFx: unknown rotary speed '%s'" % spec[k])
			d.speed = ROTARY_SPEEDS.get(spec[k], 0.0)
		elif String(k) == "name" and t == "airwindows":
			var ai := AW_NAMES.find(String(spec[k]).to_lower())
			if ai < 0:
				push_warning("AKStreamFx: unknown airwindows algorithm '%s'" % spec[k])
			d.algo = maxi(0, ai)
		elif String(k) != "type":
			d[String(k)] = spec[k]
	for xk: Array in XKEYS.get(t, []):
		if not d.has(xk[0]):
			d[xk[0]] = xk[1]
	if t == "airwindows":
		# Parameters by the plugin's names, and the plugin's defaults for those left unset.
		var algo := clampi(roundi(float(d.algo)), 0, AW_NAMES.size() - 1)
		var names: Array = AW_PARAMS[AW_NAMES[algo]]
		for i in names.size():
			if d.has(names[i]):
				d[AW_LETTERS[i]] = d[names[i]]
				d.erase(names[i])
		for i in 6:
			if float(d[AW_LETTERS[i]]) < 0.0:
				d[AW_LETTERS[i]] = AW_DEFAULTS[algo][i]
	if beats > 0.0 and t == "delay":
		d.time_ms = delay_ms_at(beats, 120.0)
		d.time_beats = beats
	var c := {type = TYPES.find(t)}
	for k in d:
		c[k] = float(d[k]) if not (d[k] is bool) else (1.0 if d[k] else 0.0)
	if c.has("voices"):
		c.voices = clampi(int(c.voices), 1, 4)
	if c.has("stages"):
		c.stages = clampi(int(c.stages), 1, 12)
	if c.has("mix"):
		c.mix = clampf(c.mix, 0.0, 1.0)
	if c.has("feedback"):
		c.feedback = clampf(c.feedback, -0.95, 0.95)
	if c.has("delay_ms"):
		c.delay_ms = maxf(c.delay_ms, 1000.0 / 48000.0)   # at least about a sample
	if c.has("depth_ms"):
		c.depth_ms = maxf(0.0, c.depth_ms)
	if c.has("ratio"):
		c.ratio = maxf(1.0, c.ratio)
	for k in LIMITS:
		if c.has(k):
			c[k] = clampf(c[k], LIMITS[k][0], LIMITS[k][1])
	if c.has("hold"):
		c.hold = int(c.hold)
	if c.has("spread_ms"):
		c.spread_ms = clampf(c.spread_ms, -100.0, 100.0)
	if t == "filter":
		c.cutoff_hz = clampf(c.cutoff_hz, 10.0, 24000.0)
		c.q = maxf(0.05, c.q)
		c.slope_db = 6.0 if c.slope_db < 9.0 else (12.0 if c.slope_db < 18.0 else 24.0)
	if t == "limiter":
		c.ceiling_db = clampf(c.ceiling_db, -60.0, 0.0)
		c.release_s = clampf(c.release_s, 0.001, 10.0)
	for xk: Array in XKEYS.get(t, []):
		c[xk[0]] = clampf(c[xk[0]], xk[2], xk[3])
	return c


## A synced delay's time: `beats` at `bpm`, within the delay's range.
static func delay_ms_at(beats: float, bpm: float) -> float:
	return clampf(beats * 60000.0 / maxf(bpm, 1.0), LIMITS.time_ms[0], LIMITS.time_ms[1])


## Run a chain of specs over stereo arrays (in place on copies): [l, r].
static func process(specs: Array, l: PackedFloat32Array, r: PackedFloat32Array, sr: int) -> Array:
	var nn := AKDsp.nat()
	var compiled := []
	for s in specs:
		compiled.append(compile(s))
	if nn and nn.has_method(&"fx_process"):
		return nn.fx_process(compiled, l, r, sr)
	var chain := Chain.new(compiled, sr)
	var ol := l.duplicate()
	var orr := r.duplicate()
	var io := PackedFloat64Array([0.0, 0.0])
	for i in ol.size():
		io[0] = ol[i]
		io[1] = orr[i]
		chain.tick(io)
		ol[i] = io[0]
		orr[i] = io[1]
	return [ol, orr]


## The tail an effect chain adds (delay lines ring on): a little room so
## a recipe doesn't cut it off.
static func tail_s(specs: Array) -> float:
	var t := 0.0
	for s in specs:
		match String(s.get("type", "")):
			"chorus", "flanger":
				var c := compile(s)
				t += (c.delay_ms + c.depth_ms) / 1000.0 * (1.0 + 6.0 * absf(c.get("feedback", 0.0)))
			"phaser":
				t += 0.05
			"pitch":
				t += compile(s).window_ms / 1000.0
			"delay":
				var c := compile(s)
				var fb := absf(c.feedback)
				t += c.time_ms / 1000.0 * (1.0 + (log(0.001) / log(fb) if fb > 0.01 else 0.0)) if c.mix > 0.0 else 0.0
			"reverb":
				t += 0.3 + 2.2 * compile(s).room if compile(s).mix > 0.0 else 0.0
			"freqshift":
				var c := compile(s)
				var fb := absf(c.feedback)
				if fb > 0.01:
					t += maxf(c.echo_ms / 1000.0, 0.01) * log(0.001) / log(fb)
			"rotary":
				t += 0.01
			"stutter":
				var c := compile(s)
				t += 1.0 / c.resample_hz + 1.0 / c.rate_hz
			"resonator":
				var c := compile(s)
				t += maxf(c.q1 / c.freq1_hz, maxf(c.q2 / c.freq2_hz, c.q3 / c.freq3_hz)) * 2.0
			"ensemble", "tape":
				t += 0.05
			"combulator":
				var c := compile(s)
				var lo := clampf(c.tune_hz * pow(2.0, minf(0.0, minf(c.offset2, c.offset3)) / 12.0), 20.0, 20000.0)
				var rs := absf(c.resonance)
				t += (log(0.001) / log(rs) / lo if rs > 0.01 else 0.01)
			"spring":
				t += compile(s).decay_s if compile(s).mix > 0.0 else 0.0
			"airwindows":
				var c := compile(s)
				t += 4.0 if int(c.algo) == AW_GALACTIC else 0.05
			"granular":
				var c := compile(s)
				t += 8.0 if c.freeze >= 0.5 else 1.1 + 4.0 * maxf(c.reverb, c.recycle)
			"neuron":
				var c := compile(s)
				t += (c.size_ms / 1000.0 * log(0.001) / log(c.regen) if c.regen < 0.95 and c.regen > 0.01 else (8.0 if c.regen >= 0.95 else 0.3))
	return minf(t, 8.0)


## A chain of compiled effects with state, ticking one stereo sample (a
## PackedFloat64Array [l, r]) at a time.
class Chain:
	var fx: Array[Effect] = []

	func _init(compiled: Array, sr: int) -> void:
		for c: Dictionary in compiled:
			if int(c.get("type", 0)) > 0:
				fx.append(Effect.new(c, sr))

	func tick(io: PackedFloat64Array) -> void:
		for f in fx:
			f.tick(io)

	func is_empty() -> bool:
		return fx.is_empty()

	## Tempo-synced effects (a delay's time_sync) follow `bpm`.
	func set_tempo(bpm: float) -> void:
		for f in fx:
			f.set_tempo(bpm)

	## A chain for `compiled` that carries this one's running state over: each new effect
	## takes the next unused old effect of its type (in order) when their buffers match, so
	## a settings change keeps delay lines, reverb tails, filter and gain states; effects
	## that are new, gone or resized start afresh. (As ak::SynthEngine::set_patch.)
	func retuned(compiled: Array, sr: int) -> Chain:
		var out := Chain.new([], sr)
		var used: Array[bool] = []
		used.resize(fx.size())
		used.fill(false)
		var from := 0
		for c: Dictionary in compiled:
			if int(c.get("type", 0)) <= 0:
				continue
			var e := Effect.new(c, sr)
			for j in range(from, fx.size()):
				if not used[j] and fx[j].type == e.type:
					if e.carry_from(fx[j]):
						used[j] = true
						from = j + 1
					break
			out.fx.append(e)
		return out


## One effect (mirrors ak::Fx).
class Effect:
	var type := 0
	var sr := 48000
	var p := {}
	var _own_p := false
	var ph := 0.0
	# Members, not arrays of arrays: a packed array inside an Array would be
	# copied on every write.
	var line_l := PackedFloat32Array()
	var line_r := PackedFloat32Array()
	var w := 0
	var ap_z := PackedFloat64Array()   # 12 allpass states for L, then 12 for R
	var ph_last := PackedFloat64Array([0.0, 0.0])
	var bq := PackedFloat64Array()     # 3 biquads x 13: b0 b1 b2 a1 a2, x1 x2 y1 y2 for L, then for R
	var gr_db := 0.0
	var k_att := 0.0
	var k_rel := 0.0
	var sat_g := 1.0
	var sat_off := 0.0
	var sat_lp := 0.0
	var sat_out := 1.0
	var sat_z := PackedFloat64Array([0.0, 0.0])
	# Knobs as fields (looked up per sample otherwise).
	var rate := 0.0
	var depth_ms := 0.0
	var delay_ms := 0.0
	var feedback := 0.0
	var mix := 0.5
	# The dry and wet gains the mixing uses (from mix, or the spec's dry and wet).
	var dmx := 0.5
	var wmx := 0.5
	var dad := 1.0
	var spread := 1.0
	var voices := 1
	var stages := 4
	var center := 800.0
	var range_oct := 2.0
	var depth := 1.0
	var threshold := -18.0
	var ratio := 4.0
	var knee := 6.0
	var makeup := 0.0
	var asym := 0.0
	# Pitch, ring, growl, crush, delay, reverb (as ak::Fx)
	var win := 1.0
	var ratio_step := 0.0
	var freq := 220.0
	var jitter := 0.5
	var bits := 8.0
	var hold := 1
	var cph := 0.0
	var rng := 0x9E3779B9
	var gr_rate := 1.0
	var gr_amp := 1.0
	var ctr := 0
	var held := PackedFloat64Array([0.0, 0.0])
	var ez := PackedFloat64Array([0.0, 0.0])
	var e_k := 1.0
	# The delay's length in samples: its whole line, or for a synced delay
	# (time_beats > 0, line allocated at the longest time) the tempo's share.
	var dn := 1
	var time_beats := 0.0
	# Each channel's delay in samples (dn plus any spread), and the mode.
	var dl := 1
	var dr := 1
	var dmode := 0
	var spread_ms := 0.0
	var rv := PackedFloat32Array()
	var rv_off := PackedInt32Array()
	var rv_len := PackedInt32Array()
	var rv_idx := PackedInt32Array()
	var rv_store := PackedFloat64Array()
	var rv_fb := 0.84
	var rv_dk := 0.2
	var rv_w1 := 1.0
	var rv_w2 := 0.0
	# The reverb's input: predelay line and position, low cut and high cut (one-pole) and their states.
	var rv_pre := PackedFloat64Array()
	var rv_pw := 0
	var rv_lck := 0.0
	var rv_hck := 0.0
	var rv_lcz := 0.0
	var rv_hcz := 0.0
	# Filter: highpass, poles (1 one-pole, 2 or 4 the state-variable's stages), its coefficients.
	var f_hp := false
	var f_n := 1
	var f_a := 0.0
	var f_k := 1.0
	var f_a1 := 0.0
	var f_a2 := 0.0
	var f_a3 := 0.0
	# Limiter: the ceiling (gain), the release coefficient, the gain now.
	var lim_c := 1.0
	var lim_k := 0.0
	var lim_g := 1.0
	# The newer types (as ak::Fx): their knobs by XKEYS order, their state, coefficients.
	var xk := PackedFloat64Array()
	var xb := PackedFloat64Array()
	var xs := PackedFloat64Array()
	var xw := 0
	var xc := PackedFloat64Array()

	## Take `o`'s running state (lines, phases, filter and gain states) when it is the same
	## type with the same buffer sizes; false (and nothing taken) otherwise.
	func carry_from(o: Effect) -> bool:
		if o.type != type or o.sr != sr or o.line_l.size() != line_l.size() or o.rv.size() != rv.size() \
				or o.rv_pre.size() != rv_pre.size() or o.ap_z.size() != ap_z.size() or o.bq.size() != bq.size() \
				or o.xb.size() != xb.size():
			return false
		xb = o.xb
		xs = o.xs
		xw = o.xw
		ph = o.ph
		line_l = o.line_l
		line_r = o.line_r
		w = o.w
		ap_z = o.ap_z
		ph_last = o.ph_last
		for k in bq.size() / 13:
			for i in range(5, 13):
				bq[k * 13 + i] = o.bq[k * 13 + i]
		gr_db = o.gr_db
		sat_z = o.sat_z
		cph = o.cph
		rng = o.rng
		gr_rate = o.gr_rate
		gr_amp = o.gr_amp
		ctr = o.ctr
		held = o.held
		ez = o.ez
		rv = o.rv
		rv_idx = o.rv_idx
		rv_store = o.rv_store
		rv_pre = o.rv_pre
		rv_pw = o.rv_pw
		rv_lcz = o.rv_lcz
		rv_hcz = o.rv_hcz
		lim_g = o.lim_g
		return true

	func _init(c: Dictionary, p_sr: int) -> void:
		p = c
		sr = p_sr
		type = int(c.type)
		rate = float(c.get("rate_hz", 0.0))
		depth_ms = float(c.get("depth_ms", 0.0))
		delay_ms = float(c.get("delay_ms", 0.0))
		feedback = float(c.get("feedback", 0.0))
		mix = float(c.get("mix", 0.5))
		dmx = maxf(0.0, float(c.dry)) if c.has("dry") else 1.0 - mix
		wmx = maxf(0.0, float(c.wet)) if c.has("wet") else mix
		dad = maxf(0.0, float(c.dry)) if c.has("dry") else 1.0
		spread = float(c.get("spread", 1.0))
		voices = int(c.get("voices", 1))
		stages = int(c.get("stages", 4))
		center = float(c.get("center_hz", 800.0))
		range_oct = float(c.get("range_octaves", 2.0))
		depth = float(c.get("depth", 1.0))
		threshold = float(c.get("threshold_db", -18.0))
		ratio = float(c.get("ratio", 4.0))
		knee = float(c.get("knee_db", 6.0))
		makeup = float(c.get("makeup_db", 0.0))
		asym = float(c.get("asymmetry", 0.0))
		ap_z.resize(24)
		ap_z.fill(0.0)
		if type == 1 or type == 2:
			var n := maxi(8, ceili(maxf(delay_ms + depth_ms, float(c.get("line_ms", 0.0))) * sr / 1000.0) + 4)
			line_l.resize(n)
			line_l.fill(0.0)
			line_r.resize(n)
			line_r.fill(0.0)
		if type == 4:
			bq = _shelf(float(c.low_hz), float(c.low_db), false) + _peak(float(c.mid_hz), float(c.mid_db), float(c.mid_q)) \
				+ _shelf(float(c.high_hz), float(c.high_db), true)
		if type == 5:
			var a := float(c.attack_s) * sr
			var r := float(c.release_s) * sr
			k_att = exp(-1.0 / (a if a > 1.0 else 1.0))
			k_rel = exp(-1.0 / (r if r > 1.0 else 1.0))
		if type == 6:
			sat_g = pow(10.0, float(c.drive_db) / 20.0)
			sat_off = tanh(asym)
			sat_lp = 1.0 - exp(-TAU * float(c.tone_hz) / sr)
			sat_out = pow(10.0, float(c.output_db) / 20.0) / tanh(sat_g)
		freq = float(c.get("freq_hz", 220.0))
		jitter = float(c.get("jitter", 0.5))
		bits = float(c.get("bits", 8.0))
		hold = int(c.get("hold", 1))
		if type == 7:
			win = float(c.window_ms) * sr / 1000.0
			ratio_step = (1.0 - pow(2.0, float(c.semitones) / 12.0)) / win
			var n := ceili(win) + 4
			line_l.resize(n)
			line_l.fill(0.0)
			line_r.resize(n)
			line_r.fill(0.0)
		if type == 11:
			dmode = int(c.get("mode", 0.0))
			spread_ms = float(c.get("spread_ms", 0.0))
			time_beats = float(c.get("time_beats", 0.0))
			# The line holds the longest delay (a synced one's at any tempo) and
			# the spread; each channel reads its own length back from the write.
			var n := maxi(1, roundi(float(c.time_ms) * sr / 1000.0))
			if time_beats > 0.0:
				n = maxi(1, roundi(LIMITS.time_ms[1] * sr / 1000.0))
			elif float(c.get("line_ms", 0.0)) > 0.0:
				n = maxi(n, roundi(float(c.line_ms) * sr / 1000.0))   # room for a modulated time
			n += absi(roundi(spread_ms * sr / 1000.0))
			dn = n
			_delay_lengths(float(c.time_ms))
			line_l.resize(n)
			line_l.fill(0.0)
			line_r.resize(n)
			line_r.fill(0.0)
			e_k = 1.0 - exp(-TAU * float(c.damp_hz) / sr)
		if type == 12:
			var scale := float(sr) / 44100.0
			var total := 0
			rv_off.resize(24)
			rv_len.resize(24)
			rv_idx.resize(24)
			rv_idx.fill(0)
			for k in 24:
				var j := k % 12
				var base: int = RV_COMBS[j] if j < 8 else RV_PASSES[j - 8]
				var ln := maxi(1, roundi((base + (23 if k >= 12 else 0)) * scale))
				rv_off[k] = total
				rv_len[k] = ln
				total += ln
			rv.resize(total)
			rv.fill(0.0)
			rv_store.resize(16)
			rv_store.fill(0.0)
			rv_fb = float(c.room) * 0.28 + 0.7
			rv_dk = float(c.damp) * 0.4
			rv_w1 = float(c.width) * 0.5 + 0.5
			rv_w2 = (1.0 - float(c.width)) * 0.5
			var pn := roundi(float(c.get("predelay_ms", 0.0)) * sr / 1000.0)
			rv_pre.resize(pn)
			rv_pre.fill(0.0)
			rv_pw = 0
			var lc := float(c.get("low_cut_hz", 0.0))
			var hc := float(c.get("high_cut_hz", 0.0))
			rv_lck = 1.0 - exp(-TAU * minf(lc, 0.49 * sr) / sr) if lc > 0.0 else 0.0
			rv_hck = 1.0 - exp(-TAU * minf(hc, 0.49 * sr) / sr) if hc > 0.0 else 0.0
			rv_lcz = 0.0
			rv_hcz = 0.0
		if type == 14:
			# As AKDynamics.limit.
			lim_c = AKDsp.db_to_gain(float(c.ceiling_db))
			lim_k = exp(-1.0 / maxf(1e-4, float(c.release_s) * sr))
		if type >= T_FREQSHIFT:
			_setup_x()
		if type == 13:
			var fc := minf(float(c.cutoff_hz), 0.49 * sr)
			f_hp = int(c.get("mode", 0.0)) == 1
			var sl := float(c.slope_db)
			f_n = 1 if sl < 9.0 else (2 if sl < 18.0 else 4)
			f_a = 1.0 - exp(-TAU * fc / sr)
			f_k = 1.0 / maxf(0.05, float(c.q))
			var g := tan(PI * fc / sr)
			f_a1 = 1.0 / (1.0 + g * (g + f_k))
			f_a2 = g * f_a1
			f_a3 = g * f_a2

	func _setup_x() -> void:
		var keys: Array = XKEYS[TYPES[type]]
		xk.resize(keys.size())
		for i in keys.size():
			xk[i] = float(p[keys[i][0]])
		xs.resize(16)
		xs.fill(0.0)
		xc.resize(80)
		xc.fill(0.0)
		xw = 0
		if type == T_GRANULAR:
			_setup_g()
		elif type == T_AIRWINDOWS:
			_setup_aw()
		elif type == T_FREQSHIFT:
			var en := roundi(xk[2] * sr / 1000.0)
			xb.resize(66 + 2 * en)
			xb.fill(0.0)
		elif type >= T_ENSEMBLE:
			_setup_b()
		elif type >= T_CONDITIONER:
			# Biquads in xb (13 each, as bq), the rest in xs (ak::Fx::setup_x).
			var nb: int = {T_CONDITIONER: 2, T_GEQ: 11, T_RESONATOR: 3, T_EXCITER: 2}.get(type, 0)
			xb.resize(13 * nb)
			xb.fill(0.0)
			_recoef_x()
		elif type == T_STUTTER:
			# Two stereo buffers (ak::Fx::setup_x): one records, the other holds the slice.
			var n := ceili(ST_MAX_S * sr) + 2
			xb.resize(4 * n)
			xb.fill(0.0)
			xc[0] = pow(2.0, xk[3] / 12.0)
		elif type == T_ROTARY:
			var n := ceili(RO_LINE_MS * sr / 1000.0) + 4
			xb.resize(2 * n)
			xb.fill(0.0)
			xs[1] = 0.25
			xs[2] = _ro_target(xk[1])
			xs[3] = _ro_target(xk[2])
			xc[0] = 1.0 - exp(-TAU * xk[6] / sr)
			xc[1] = 1.0 - exp(-1.0 / (xk[3] * sr))
			xc[2] = 1.0 - exp(-1.0 / (5.0 * xk[3] * sr))
			xc[3] = sin(TAU * 0.25 * xk[5])
			xc[4] = cos(TAU * 0.25 * xk[5])

	# ---- the Surge-table effects (original designs, as ak::Fx): biquads in xb, coefficients in _recoef_x.
	func _xbq(o: int, x: float, ch: int) -> float:
		var z := o + 5 + 4 * ch
		var y := xb[o] * x + xb[o + 1] * xb[z] + xb[o + 2] * xb[z + 1] - xb[o + 3] * xb[z + 2] - xb[o + 4] * xb[z + 3]
		xb[z + 1] = xb[z]
		xb[z] = x
		xb[z + 3] = xb[z + 2]
		xb[z + 2] = y
		return y

	func _xbq_set(o: int, c: PackedFloat64Array) -> void:
		for i in 5:
			xb[o + i] = c[i]

	func _bandpass(f: float, q: float) -> PackedFloat64Array:
		var w0 := TAU * minf(f, 0.49 * sr) / sr
		var cw := cos(w0)
		var alpha := sin(w0) / (2.0 * q)
		var a0 := 1.0 + alpha
		return PackedFloat64Array([alpha / a0, 0.0, -alpha / a0, -2.0 * cw / a0, (1.0 - alpha) / a0])

	func _highpass(f: float, q: float) -> PackedFloat64Array:
		var w0 := TAU * minf(f, 0.49 * sr) / sr
		var cw := cos(w0)
		var alpha := sin(w0) / (2.0 * q)
		var a0 := 1.0 + alpha
		return PackedFloat64Array([(1.0 + cw) * 0.5 / a0, -(1.0 + cw) / a0, (1.0 + cw) * 0.5 / a0, -2.0 * cw / a0, (1.0 - alpha) / a0])

	static func _ws_curve(c: int, u: float) -> float:
		match c:
			1:
				return clampf(u, -1.0, 1.0)
			2:
				var v := u - 1.0 - 4.0 * floorf((u - 1.0) / 4.0)
				return absf(v - 2.0) - 1.0
			3:
				return sin(u)
			4:
				return tanh(u) if u >= 0.0 else -0.6 * (1.0 - exp(u / 0.6))
			5:
				return clampf(floorf(u * 8.0 + 0.5) / 8.0, -1.0, 1.0)
		return tanh(u)

	func _recoef_x() -> void:
		match type:
			T_CONDITIONER:
				_xbq_set(0, _shelf(200.0, xk[0], false))
				_xbq_set(13, _shelf(4000.0, xk[1], true))
				xc[0] = exp(-1.0 / maxf(1.0, xk[5] * sr / 1000.0))
				xc[1] = exp(-1.0 / maxf(1.0, xk[6] * sr / 1000.0))
				xc[2] = pow(10.0, xk[7] / 20.0)
				xc[3] = 1.0 - xk[3] if xk[3] > 0.0 else 1.0
				xc[4] = 1.0 + xk[3] if xk[3] < 0.0 else 1.0
			T_GEQ:
				for b in 11:
					_xbq_set(13 * b, _peak(minf(GEQ_HZ[b], 0.49 * sr), xk[b], 1.41))
				xc[0] = pow(10.0, xk[11] / 20.0)
			T_RESONATOR:
				for b in 3:
					_xbq_set(13 * b, _bandpass(xk[b], xk[3 + b]))
					xc[b] = pow(10.0, xk[6 + b] / 20.0)
				xc[3] = pow(10.0, xk[10] / 20.0)
			T_EXCITER:
				var hp := _highpass(xk[0], 0.707)
				_xbq_set(0, hp)
				_xbq_set(13, hp)
				xc[0] = 1.0 + 24.0 * xk[1]
				xc[1] = 1.0 / xc[0]
			T_WAVESHAPER:
				xc[0] = 1.0 - exp(-TAU * minf(xk[3], 0.49 * sr) / sr) if xk[3] > 0.0 else 0.0
				xc[1] = 1.0 - exp(-TAU * minf(xk[4], 0.49 * sr) / sr) if xk[4] > 0.0 else 0.0
				xc[2] = pow(10.0, xk[1] / 20.0)
				xc[3] = _ws_curve(roundi(xk[0]), xk[2])
				xc[4] = pow(10.0, xk[5] / 20.0)
			T_ENSEMBLE, T_COMBULATOR, T_TAPE, T_TREEMONSTER, T_SPRING, T_BONSAI, T_CHOW, T_NEURON:
				_recoef_b()
			T_MIDSIDE:
				xc[0] = 1.0 - exp(-TAU * minf(xk[2], 0.49 * sr) / sr) if xk[2] > 0.0 else 0.0
				xc[1] = pow(10.0, xk[0] / 20.0)
				xc[2] = pow(10.0, xk[1] / 20.0)
				xc[3] = 1.0 - maxf(0.0, xk[3])
				xc[4] = 1.0 + minf(0.0, xk[3])

	func _tick_conditioner(io: PackedFloat64Array) -> void:
		var l := _xbq(13, _xbq(0, io[0], 0), 0)
		var r := _xbq(13, _xbq(0, io[1], 1), 1)
		var m := (l + r) * 0.5
		var sd := (l - r) * 0.5 * xk[2]
		l = (m + sd) * xc[3]
		r = (m - sd) * xc[4]
		xs[1] = maxf(maxf(absf(l), absf(r)), xs[1] * xc[1])
		var over := 20.0 * log(xs[1] + 1e-12) / log(10.0) - xk[4]
		var target := 0.0 if over <= -3.0 else (-(over + 3.0) * (over + 3.0) / 12.0 if over < 3.0 else -over)
		xs[0] = target + (xs[0] - target) * xc[0]
		var g := pow(10.0, xs[0] / 20.0) * xc[2]
		io[0] = l * g
		io[1] = r * g

	func _tick_resonator(io: PackedFloat64Array) -> void:
		for ch in 2:
			var x := io[ch]
			var o := 0.0
			if xk[9] >= 0.5:
				o = _xbq(26, _xbq(13, _xbq(0, x, ch), ch), ch) * xc[0] * xc[1] * xc[2]
			else:
				o = _xbq(0, x, ch) * xc[0] + _xbq(13, x, ch) * xc[1] + _xbq(26, x, ch) * xc[2]
			io[ch] = x * dmx + o * xc[3] * wmx

	func _tick_waveshaper(io: PackedFloat64Array) -> void:
		var cv := roundi(xk[0])
		for ch in 2:
			var x := io[ch]
			if xc[0] > 0.0:
				xs[ch] += (x - xs[ch]) * xc[0]
				x -= xs[ch]
			var y := _ws_curve(cv, xc[2] * x + xk[2]) - xc[3]
			if xc[1] > 0.0:
				xs[2 + ch] += (y - xs[2 + ch]) * xc[1]
				y = xs[2 + ch]
			io[ch] = io[ch] * dmx + y * xc[4] * wmx

	# ---- Surge-table effects, group B (original designs, as ak::Fx): lines in xb read with
	# _ro_read (shared write place xw), coefficients in _recoef_b, state in xs.
	func _sp_k() -> int:
		return maxi(1, roundi(sr / 9000.0))

	func _op(f: float) -> float:
		return 1.0 - exp(-TAU * minf(f, 0.49 * sr) / sr)

	func _setup_b() -> void:
		var n := 0
		match type:
			T_ENSEMBLE:
				n = ceili(EN_LINE_MS * sr / 1000.0) + 4
				xb.resize(n)
			T_COMBULATOR:
				n = ceili(sr / 20.0) + 4
				xb.resize(3 * n)
			T_TAPE:
				n = ceili(TP_LINE_MS * sr / 1000.0) + 4
				xb.resize(2 * n + 26)
			T_SPRING:
				n = ceili(SP_LINE_MS * sr / 1000.0) + 4
				xb.resize(2 * n + 4 * SP_STAGES * _sp_k())
			T_NEURON:
				n = ceili(NE_LINE_S * sr) + 4
				xb.resize(4 * n)
			_:
				xb.resize(0)
		xb.fill(0.0)
		_recoef_b()

	func _b_line() -> int:
		match type:
			T_COMBULATOR:
				return xb.size() / 3
			T_TAPE:
				return (xb.size() - 26) / 2
			T_SPRING:
				return (xb.size() - 4 * SP_STAGES * _sp_k()) / 2
			T_NEURON:
				return xb.size() / 4
		return xb.size()

	func _lowpass(f: float, q: float) -> PackedFloat64Array:
		var w0 := TAU * minf(f, 0.49 * sr) / sr
		var cw := cos(w0)
		var alpha := sin(w0) / (2.0 * q)
		var a0 := 1.0 + alpha
		return PackedFloat64Array([(1.0 - cw) * 0.5 / a0, (1.0 - cw) / a0, (1.0 - cw) * 0.5 / a0, -2.0 * cw / a0, (1.0 - alpha) / a0])

	func _recoef_b() -> void:
		match type:
			T_ENSEMBLE:
				var c := xk[4] * sr / 1000.0
				xc[0] = _op(xk[5])
				xc[1] = xk[0] / sr
				xc[2] = xk[2] / sr
				xc[3] = c
				xc[4] = 0.45 * xk[1] * c
				xc[5] = 0.06 * xk[3] * c
			T_COMBULATOR:
				for k in 3:
					var f := xk[0] * (1.0 if k == 0 else pow(2.0, xk[k] / 12.0))
					xc[k] = sr / clampf(f, 20.0, 0.45 * sr)
					xc[4 + k] = pow(10.0, xk[6 + k] / 20.0) * sqrt(1.0 - xk[3] * xk[3])
				xc[3] = _op(xk[4])
				xc[7] = 1.0 - exp(-1.0 / (0.001 * sr))
				xc[8] = 1.0 - exp(-1.0 / (0.05 * sr))
				var pp := [0.0, -xk[9], xk[9]]
				for k in 3:
					xc[10 + k] = (1.0 - pp[k]) / 3.0
					xc[13 + k] = (1.0 + pp[k]) / 3.0
			T_TAPE:
				var n := _b_line()
				xc[0] = pow(10.0, xk[0] / 20.0)
				xc[1] = _op(2000.0)
				xc[2] = 1.0 / xc[0]
				xc[3] = pow(10.0, xk[7] / 20.0)
				xc[4] = 0.7 / sr
				xc[5] = 6.1 / sr
				xc[6] = 13.3 / sr
				xc[7] = TP_BASE_MS * sr / 1000.0
				xc[8] = xk[2] * 1.2 * sr / 1000.0
				xc[9] = xk[3] * 0.06 * sr / 1000.0
				_xbq_set(2 * n, _peak(xk[4], xk[5], 1.0))
				_xbq_set(2 * n + 13, _lowpass(xk[6], 0.707))
			T_TREEMONSTER:
				xc[0] = pow(10.0, xk[0] / 20.0)
				xc[1] = 1.0 - exp(-1.0 / (xk[1] * sr / 1000.0)) if xk[1] > 0.0 else 1.0
				xc[2] = pow(2.0, xk[2] / 12.0)
				xc[3] = _op(xk[3])
				xc[4] = _op(xk[4])
			T_SPRING:
				var ls := xk[2] / 1000.0 + SP_STAGES * _sp_k() * (1.0 + xk[1]) / (1.0 - xk[1]) / sr
				xc[0] = pow(10.0, -3.0 * ls / xk[0])
				xc[1] = _op(xk[3])
				xc[2] = xk[2] * sr / 1000.0
				xc[3] = xk[2] * 1.13 * sr / 1000.0
				xc[4] = (1.0 + xk[4]) * 0.5
				xc[5] = (1.0 - xk[4]) * 0.5
			T_BONSAI:
				xc[0] = _op(xk[0])
				xc[1] = pow(10.0, xk[1] / 20.0)
				xc[2] = _op(2.0 * xk[0])
				xc[3] = pow(10.0, xk[3] / 20.0)
				xc[4] = 1.0 / xc[3]
				xc[5] = _op(xk[4])
				xc[6] = pow(10.0, xk[5] / 20.0)
			T_CHOW:
				xc[0] = pow(10.0, xk[3] / 20.0)
				xc[1] = pow(10.0, xk[0] / 20.0)
				xc[2] = 1.0 / xk[1]
				xc[3] = _op(10.0)
				xc[4] = _op(xk[4])
				xc[5] = pow(10.0, xk[5] / 20.0) / xc[0]
			T_NEURON:
				xc[0] = xk[0] * sr / 1000.0
				xc[1] = 0.1 * xk[3]
				xc[2] = xk[4] / sr
				xc[3] = _op(xk[5])
				xc[4] = 1.0 + 7.0 * xk[2]
				xc[5] = 1.0 / xc[4]
				xc[6] = (1.0 + xk[6]) * 0.5
				xc[7] = (1.0 - xk[6]) * 0.5

	func _tick_ensemble(io: PackedFloat64Array) -> void:
		var n := xb.size()
		var a := xc[0]
		xs[2] += (0.5 * (io[0] + io[1]) - xs[2]) * a
		xs[3] += (xs[2] - xs[3]) * a
		xb[xw] = xs[3]
		var t0 := _ro_read(0, n, xc[3] + xc[4] * sin(TAU * xs[0]) + xc[5] * sin(TAU * xs[1]))
		var t1 := _ro_read(0, n, xc[3] + xc[4] * sin(TAU * (xs[0] + 1 / 3.0)) + xc[5] * sin(TAU * (xs[1] + 1 / 3.0)))
		var t2 := _ro_read(0, n, xc[3] + xc[4] * sin(TAU * (xs[0] + 2 / 3.0)) + xc[5] * sin(TAU * (xs[1] + 2 / 3.0)))
		xw = 0 if xw + 1 == n else xw + 1
		var w := xk[6]
		var wl := (t0 * (1.0 + w) + t1 + t2 * (1.0 - w)) / 3.0
		var wr := (t2 * (1.0 + w) + t1 + t0 * (1.0 - w)) / 3.0
		xs[4] += (wl - xs[4]) * a
		xs[5] += (wr - xs[5]) * a
		xs[0] += xc[1]
		xs[0] -= floorf(xs[0])
		xs[1] += xc[2]
		xs[1] -= floorf(xs[1])
		io[0] = io[0] * dmx + xs[4] * wmx
		io[1] = io[1] * dmx + xs[5] * wmx

	func _tick_combulator(io: PackedFloat64Array) -> void:
		var n := xb.size() / 3
		var x := 0.5 * (io[0] + io[1])
		if xk[5] > 0.0:
			var e := absf(x)
			xs[3] += (e - xs[3]) * (xc[7] if e > xs[3] else xc[8])
			var nz := (2.0 * _rnd() - 1.0) * xs[3] * 1.7
			x = x * (1.0 - xk[5]) + nz * xk[5]
		var ol := 0.0
		var orr := 0.0
		for k in 3:
			var y := _ro_read(k * n, n, xc[k])
			xs[k] += (y - xs[k]) * xc[3]
			var v := x + xk[3] * xs[k]
			xb[k * n + xw] = v
			var o := v * xc[4 + k]
			ol += o * xc[10 + k]
			orr += o * xc[13 + k]
		xw = 0 if xw + 1 == n else xw + 1
		io[0] = io[0] * dmx + ol * wmx
		io[1] = io[1] * dmx + orr * wmx

	func _tick_tape(io: PackedFloat64Array) -> void:
		var n := _b_line()
		var y := PackedFloat64Array([0.0, 0.0])
		for ch in 2:
			var u := xc[0] * io[ch]
			var du := u - xs[ch]
			xs[ch] = u
			xs[2 + ch] += ((1.0 if du > 0.0 else (-1.0 if du < 0.0 else 0.0)) - xs[2 + ch]) * xc[1]
			y[ch] = tanh(u - xk[1] * 0.3 * xs[2 + ch] * tanh(absf(u))) * xc[2]
		if xk[2] > 0.0 or xk[3] > 0.0:
			xb[xw] = y[0]
			xb[n + xw] = y[1]
			var d := xc[7] + xc[8] * sin(TAU * xs[4]) + xc[9] * (0.7 * sin(TAU * xs[5]) + 0.3 * sin(TAU * xs[6]))
			y[0] = _ro_read(0, n, d)
			y[1] = _ro_read(n, n, d)
			xw = 0 if xw + 1 == n else xw + 1
			for k in range(4, 7):
				xs[k] += xc[k]
				xs[k] -= floorf(xs[k])
		for ch in 2:
			var v := y[ch]
			if xk[5] > 0.0:
				v = _xbq(2 * n, v, ch)
			v = _xbq(2 * n + 13, v, ch) * xc[3]
			io[ch] = io[ch] * dmx + v * wmx

	func _tick_treemonster(io: PackedFloat64Array) -> void:
		var m := 0.5 * (io[0] + io[1])
		xs[0] += (m - xs[0]) * xc[4]
		xs[1] += (m - xs[0] - xs[1]) * xc[3]
		xs[2] += (xs[1] - xs[2]) * xc[3]
		var t := xs[2]
		xs[5] += 1.0
		if t < -xc[0]:
			xs[3] = 1.0
		elif xs[3] != 0.0 and xs[4] < 0.0 and t >= 0.0:
			var back := 1.0 - xs[4] / (xs[4] - t)
			if xs[6] != 0.0:
				var per := xs[5] - back
				if per > sr / 5000.0 and per < sr / 20.0:
					xs[9] = sr / per
					if xs[7] == 0.0:
						xs[7] = xs[9]
			xs[5] = back
			xs[6] = 1.0
			xs[3] = 0.0
		xs[4] = t
		xs[7] += (xs[9] - xs[7]) * xc[1]
		var cl := sin(TAU * xs[8])
		var cr := sin(TAU * (xs[8] + 0.25 * xk[5])) if xk[5] > 0.0 else cl
		xs[8] += xs[7] * xc[2] / sr
		xs[8] -= floorf(xs[8])
		io[0] = io[0] * dmx + io[0] * cl * wmx
		io[1] = io[1] * dmx + io[1] * cr * wmx

	func _tick_spring(io: PackedFloat64Array) -> void:
		var n := _b_line()
		var kk := _sp_k()
		var p := int(xs[2])
		var inp := 0.25 * (io[0] + io[1])
		var a := -xk[1]
		var y := PackedFloat64Array([0.0, 0.0])
		for s in 2:
			var fbk := _ro_read(s * n, n, xc[2 + s])
			xs[s] += (fbk - xs[s]) * xc[1]
			var x := inp + xc[0] * xs[s]
			var z := 2 * n + s * 2 * SP_STAGES * kk
			for k in SP_STAGES:
				var v := a * x + xb[z + p] - a * xb[z + kk + p]
				xb[z + p] = x
				xb[z + kk + p] = v
				x = v
				z += 2 * kk
			xb[s * n + xw] = x
			y[s] = x
		xw = 0 if xw + 1 == n else xw + 1
		xs[2] = 0.0 if p + 1 == kk else p + 1.0
		io[0] = io[0] * dad + (y[0] * xc[4] + y[1] * xc[5]) * wmx
		io[1] = io[1] * dad + (y[1] * xc[4] + y[0] * xc[5]) * wmx

	func _tick_bonsai(io: PackedFloat64Array) -> void:
		for ch in 2:
			var z := 4 * ch
			var x := io[ch]
			xs[z] += (x - xs[z]) * xc[0]
			xs[z + 1] += (xs[z] - xs[z + 1]) * xc[0]
			var lo := xs[z + 1]
			var hm := tanh(4.0 * lo) * 0.25
			xs[z + 2] += (hm - xs[z + 2]) * xc[2]
			var y := (x - lo) + lo * xc[1] + 2.0 * xk[2] * (hm - xs[z + 2])
			xs[z + 3] += (tanh(xc[3] * y) * xc[4] - xs[z + 3]) * xc[5]
			io[ch] = x * dmx + xs[z + 3] * xc[6] * wmx

	func _tick_chow(io: PackedFloat64Array) -> void:
		var sg := -1.0 if xk[2] >= 0.5 else 1.0
		for ch in 2:
			var s := sg * xc[0] * io[ch]
			if s > xc[1]:
				s = xc[1] + (s - xc[1]) * xc[2]
			var u := sg * s
			xs[ch] += (u - xs[ch]) * xc[3]
			u -= xs[ch]
			xs[2 + ch] += (u - xs[2 + ch]) * xc[4]
			io[ch] = io[ch] * dmx + xs[2 + ch] * xc[5] * wmx

	func _tick_neuron(io: PackedFloat64Array) -> void:
		var n := xb.size() / 4
		var t := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
		for k in 4:
			var d := maxf(2.0, xc[0] * NE_R[k] * (1.0 + xc[1] * sin(TAU * (xs[4] + 0.25 * k))))
			t[k] = _ro_read(k * n, n, d)
		var h := PackedFloat64Array([0.5 * (t[0] + t[1] + t[2] + t[3]), 0.5 * (t[0] - t[1] + t[2] - t[3]), 0.5 * (t[0] + t[1] - t[2] - t[3]),
			0.5 * (t[0] - t[1] - t[2] + t[3])])
		for k in 4:
			var v := (io[1] if (k & 1) else io[0]) + xk[1] * h[k]
			xs[k] += (tanh(xc[4] * v) * xc[5] - xs[k]) * xc[3]
			xb[k * n + xw] = xs[k]
		xw = 0 if xw + 1 == n else xw + 1
		xs[4] += xc[2]
		xs[4] -= floorf(xs[4])
		var wl := 0.5 * (t[0] + t[2])
		var wr := 0.5 * (t[1] + t[3])
		io[0] = io[0] * dmx + (wl * xc[6] + wr * xc[7]) * wmx
		io[1] = io[1] * dmx + (wr * xc[6] + wl * xc[7]) * wmx

	## The stutter (ak::Fx::tick_stutter): the input records, a slice of the last 1 / rate_hz is
	## captured at the end of a repeat once 1 / resample_hz has passed, and repeats until the next.
	func _st_capture(n: int, lt: int) -> void:
		var ln := maxi(16, mini(lt, int(xs[6])))
		xs[0] = 1.0 - xs[0]
		var st := xw - ln
		if st < 0:
			st += n
		xs[1] = 1.0
		xs[2] = st
		xs[3] = ln
		xs[4] = 0.0
		xs[5] = 0.0
		xs[6] = 0.0

	func _tick_stutter(io: PackedFloat64Array) -> void:
		var n := xb.size() / 4
		var rec := int(xs[0])
		xb[2 * rec * n + xw] = io[0]
		xb[(2 * rec + 1) * n + xw] = io[1]
		xw = 0 if xw + 1 == n else xw + 1
		xs[6] = minf(xs[6] + 1.0, float(n - 1))
		var lt := clampi(roundi(sr / xk[0]), 16, n - 1)
		if xs[1] != 0.0:
			xs[4] += 1.0
			xs[5] += 1.0
			if xs[4] >= xs[3]:
				xs[4] -= xs[3]
				if xs[5] >= sr / xk[1]:
					_st_capture(n, lt)
		elif xs[6] >= lt:
			_st_capture(n, lt)
		var ol := io[0]
		var orr := io[1]
		if xs[1] != 0.0:
			var ln := xs[3]
			var pp := xs[4]
			var q := pp * xc[0]
			q -= floorf(q / ln) * ln
			var i0 := int(q)
			var fr := q - i0
			var i1 := 0 if i0 + 1 >= int(ln) else i0 + 1
			var st := int(xs[2])
			var a := st + i0 - n if st + i0 >= n else st + i0
			var b := st + i1 - n if st + i1 >= n else st + i1
			var bs := 2 * (1 - int(xs[0])) * n
			var w := 1.0
			var f := xk[2] * ln * 0.5
			if f >= 1.0:
				if pp < f:
					w = 0.5 - 0.5 * cos(PI * pp / f)
				elif pp > ln - f:
					w = 0.5 - 0.5 * cos(PI * (ln - pp) / f)
			ol = (xb[bs + a] * (1.0 - fr) + xb[bs + b] * fr) * w
			orr = (xb[bs + n + a] * (1.0 - fr) + xb[bs + n + b] * fr) * w
		io[0] = io[0] * dmx + ol * wmx
		io[1] = io[1] * dmx + orr * wmx

	func _ro_target(fast: float) -> float:
		return fast * (RO_SLOW + (1.0 - RO_SLOW) * xk[0])

	func _hilbert(x: float, co: Array, zo: int) -> float:
		for s in 4:
			var q := zo + 4 * s
			var a: float = co[s] * co[s]
			var y := a * (x + xb[q + 3]) - xb[q + 1]
			xb[q + 1] = xb[q]
			xb[q] = x
			xb[q + 3] = xb[q + 2]
			xb[q + 2] = y
			x = y
		return x

	func _tick_freqshift(io: PackedFloat64Array) -> void:
		var en := (xb.size() - 66) / 2
		var fb0 := xs[2]
		var fb1 := xs[3]
		if en > 0:
			fb0 = xb[66 + xw]
			fb1 = xb[66 + en + xw]
		var o0 := 0.0
		var o1 := 0.0
		for ch in 2:
			var x := io[ch] + feedback * (fb0 if ch == 0 else fb1)
			var i_now := _hilbert(x, HB_A, ch * 32)
			var q := _hilbert(x, HB_B, ch * 32 + 16)
			var i := xb[64 + ch]
			xb[64 + ch] = i_now
			var ph := TAU * xs[ch]
			var o := i * cos(ph) + q * sin(ph)
			if ch == 0:
				o0 = o
			else:
				o1 = o
			var hz := xk[0] if ch == 0 else xk[0] * (1.0 - 2.0 * xk[1])
			xs[ch] += hz / sr
			xs[ch] -= floorf(xs[ch])
		xs[2] = o0
		xs[3] = o1
		if en > 0:
			xb[66 + xw] = o0
			xb[66 + en + xw] = o1
			xw = 0 if xw + 1 == en else xw + 1
		io[0] = io[0] * dmx + o0 * wmx
		io[1] = io[1] * dmx + o1 * wmx

	func _ro_read(base: int, n: int, d: float) -> float:
		var pos := xw - d
		if pos < 0.0:
			pos += n
		var i0 := int(pos)
		var fr := pos - i0
		var i1 := 0 if i0 + 1 == n else i0 + 1
		return xb[base + i0] * (1.0 - fr) + xb[base + i1] * fr

	func _tick_rotary(io: PackedFloat64Array) -> void:
		var n := xb.size() / 2
		var x := (io[0] + io[1]) * 0.5
		if xk[4] > 0.0:
			var g := 1.0 + 4.0 * xk[4]
			x = tanh(g * x) / g
		xs[4] += xc[0] * (x - xs[4])
		xs[5] += xc[0] * (xs[4] - xs[5])
		var lo := xs[5]
		var hi := x - lo
		xs[2] += xc[1] * (_ro_target(xk[1]) - xs[2])
		xs[3] += xc[2] * (_ro_target(xk[2]) - xs[3])
		var hs := sin(TAU * xs[0])
		var hc := cos(TAU * xs[0])
		var ds := sin(TAU * xs[1])
		var dc := cos(TAU * xs[1])
		var ms := xc[3]
		var mc := xc[4]
		var sr_ms := sr / 1000.0
		var out := PackedFloat64Array([0.0, 0.0])
		for ch in 2:
			var sgn := -1.0 if ch == 0 else 1.0
			var chh := hc * mc + hs * ms * sgn
			var cd := dc * mc + ds * ms * sgn
			var h := _ro_read(0, n, (2.0 - 0.5 * xk[7] * chh) * sr_ms) * (1.0 + 0.45 * xk[8] * chh)
			var d := _ro_read(n, n, (2.0 - 0.35 * xk[7] * cd) * sr_ms) * (1.0 + 0.2 * xk[8] * cd)
			out[ch] = h + d
		xb[xw] = hi
		xb[n + xw] = lo
		xw = 0 if xw + 1 == n else xw + 1
		xs[0] += xs[2] / sr
		xs[0] -= floorf(xs[0])
		xs[1] += xs[3] / sr
		xs[1] -= floorf(xs[1])
		io[0] = io[0] * dmx + out[0] * wmx
		io[1] = io[1] * dmx + out[1] * wmx

	## A matrix row moved setting `key` (one of mod_keys()) to v: the knob and whatever is worked
	## out from it change, the running state stays (ak::Fx::knob, then recoef()).
	func set_knob(key: String, v: float) -> void:
		if not _own_p:
			p = p.duplicate()   # the compiled spec stays as compiled
			_own_p = true
		p[key] = v
		var keys: Array = XKEYS.get(TYPES[type], [])
		for i in keys.size():
			if keys[i][0] == key:
				xk[i] = v
				return
		match key:
			"mix", "dry", "wet":
				mix = float(p.get("mix", 0.5))
				dmx = maxf(0.0, float(p.dry)) if p.has("dry") else 1.0 - mix
				wmx = maxf(0.0, float(p.wet)) if p.has("wet") else mix
				dad = maxf(0.0, float(p.dry)) if p.has("dry") else 1.0
			"feedback":
				feedback = v
			"rate_hz":
				rate = v
			"depth_ms":
				depth_ms = v
			"delay_ms":
				delay_ms = v
			"spread":
				spread = v
			"center_hz":
				center = v
			"range_octaves":
				range_oct = v
			"depth":
				depth = v
			"threshold_db":
				threshold = v
			"ratio":
				ratio = v
			"knee_db":
				knee = v
			"makeup_db":
				makeup = v
			"asymmetry":
				asym = v
			"freq_hz":
				freq = v
			"jitter":
				jitter = v
			"bits":
				bits = v

	## What's worked out from the knobs, again, after set_knob (ak::Fx::recoef): filter and EQ
	## coefficients (their states kept), the saturator's gains, the pitch shifter's step, the
	## delay's lengths and damping, the reverb's feedback and widths, the limiter's ceiling, the
	## rotary's crossover, ease and mics.
	func recoef() -> void:
		match type:
			4:
				var nb := _shelf(float(p.low_hz), float(p.low_db), false) + _peak(float(p.mid_hz), float(p.mid_db), float(p.mid_q)) \
					+ _shelf(float(p.high_hz), float(p.high_db), true)
				for k in 3:
					for i in 5:
						bq[k * 13 + i] = nb[k * 13 + i]
			6:
				sat_g = pow(10.0, float(p.drive_db) / 20.0)
				sat_off = tanh(asym)
				sat_lp = 1.0 - exp(-TAU * float(p.tone_hz) / sr)
				sat_out = pow(10.0, float(p.output_db) / 20.0) / tanh(sat_g)
			7:
				ratio_step = (1.0 - pow(2.0, float(p.semitones) / 12.0)) / win
			11:
				if time_beats <= 0.0:
					_delay_lengths(float(p.time_ms))
					var mx := maxi(dl, dr)
					if mx > dn:
						# Never past the line (it holds line_ms): shorten both sides alike.
						dl -= mx - dn
						dr -= mx - dn
						dl = maxi(1, dl)
						dr = maxi(1, dr)
				e_k = 1.0 - exp(-TAU * float(p.damp_hz) / sr)
			12:
				rv_fb = float(p.room) * 0.28 + 0.7
				rv_dk = float(p.damp) * 0.4
				rv_w1 = float(p.width) * 0.5 + 0.5
				rv_w2 = (1.0 - float(p.width)) * 0.5
			13:
				var fc := minf(float(p.cutoff_hz), 0.49 * sr)
				f_a = 1.0 - exp(-TAU * fc / sr)
				f_k = 1.0 / maxf(0.05, float(p.q))
				var g := tan(PI * fc / sr)
				f_a1 = 1.0 / (1.0 + g * (g + f_k))
				f_a2 = g * f_a1
				f_a3 = g * f_a2
			14:
				lim_c = AKDsp.db_to_gain(float(p.ceiling_db))
			T_STUTTER:
				xc[0] = pow(2.0, xk[3] / 12.0)
			T_CONDITIONER, T_GEQ, T_RESONATOR, T_EXCITER, T_WAVESHAPER, T_MIDSIDE, T_ENSEMBLE, T_COMBULATOR, T_TAPE, T_TREEMONSTER, T_SPRING, T_BONSAI, T_CHOW, T_NEURON:
				_recoef_x()
			T_GRANULAR:
				_recoef_g()
			T_AIRWINDOWS:
				_recoef_aw()
			T_ROTARY:
				xc[0] = 1.0 - exp(-TAU * xk[6] / sr)
				xc[1] = 1.0 - exp(-1.0 / (xk[3] * sr))
				xc[2] = 1.0 - exp(-1.0 / (5.0 * xk[3] * sr))
				xc[3] = sin(TAU * 0.25 * xk[5])
				xc[4] = cos(TAU * 0.25 * xk[5])

	func set_tempo(bpm: float) -> void:
		if type == T_STUTTER:
			# A synced stutter: its rates from note lengths at the tempo.
			if xk[4] > 0.0:
				xk[0] = clampf(maxf(bpm, 1.0) / 60.0 / xk[4], 1.0, 100.0)
			if xk[5] > 0.0:
				xk[1] = clampf(maxf(bpm, 1.0) / 60.0 / xk[5], 0.05, 100.0)
			return
		if type != 11 or time_beats <= 0.0:
			return
		_delay_lengths(AKStreamFx.delay_ms_at(time_beats, bpm))

	## Each channel's delay for a time of `ms`, the spread added to one side.
	func _delay_lengths(ms: float) -> void:
		var base := maxi(1, roundi(ms * sr / 1000.0))
		var sp := roundi(spread_ms * sr / 1000.0)
		dl = base + (-sp if sp < 0 else 0)
		dr = base + (sp if sp > 0 else 0)

	func _coef(b0: float, b1: float, b2: float, a0: float, a1: float, a2: float) -> PackedFloat64Array:
		var q := PackedFloat64Array([b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0, 0, 0, 0, 0, 0, 0, 0, 0])
		return q

	func _shelf(f: float, gain_db: float, high: bool) -> PackedFloat64Array:
		var A := pow(10.0, gain_db / 40.0)
		var w0 := TAU * f / sr
		var cw := cos(w0)
		var sw := sin(w0)
		var alpha := sw / 2.0 * sqrt(2.0)
		var t := 2.0 * sqrt(A) * alpha
		if not high:
			return _coef(A * ((A + 1) - (A - 1) * cw + t), 2 * A * ((A - 1) - (A + 1) * cw), A * ((A + 1) - (A - 1) * cw - t),
				(A + 1) + (A - 1) * cw + t, -2 * ((A - 1) + (A + 1) * cw), (A + 1) + (A - 1) * cw - t)
		return _coef(A * ((A + 1) + (A - 1) * cw + t), -2 * A * ((A - 1) + (A + 1) * cw), A * ((A + 1) + (A - 1) * cw - t),
			(A + 1) - (A - 1) * cw + t, 2 * ((A - 1) - (A + 1) * cw), (A + 1) - (A - 1) * cw - t)

	func _peak(f: float, gain_db: float, q: float) -> PackedFloat64Array:
		var A := pow(10.0, gain_db / 40.0)
		var w0 := TAU * f / sr
		var cw := cos(w0)
		var sw := sin(w0)
		var alpha := sw / (2.0 * (q if q >= 0.05 else 0.05))
		var a0 := 1 + alpha / A
		return PackedFloat64Array([(1 + alpha * A) / a0, -2 * cw / a0, (1 - alpha * A) / a0, -2 * cw / a0, (1 - alpha / A) / a0, 0, 0, 0, 0, 0, 0, 0, 0])

	func _read(ch: int, d: float) -> float:
		var n := line_l.size()
		var pos := w - d
		while pos < 0.0:
			pos += n
		var i0 := int(pos)
		var fr := pos - i0
		var i1 := (i0 + 1) % n
		if ch == 0:
			return line_l[i0 % n] * (1.0 - fr) + line_l[i1] * fr
		return line_r[i0 % n] * (1.0 - fr) + line_r[i1] * fr

	# ---- Granular: a port of Clouds' granular mode (Mutable Instruments, MIT; see NOTICE), as
	# ak::Fx (setup_g, recoef_g, tick_granular): its comments there.
	func _gr_k(k: float) -> float:
		return 1.0 - pow(1.0 - k, 32000.0 / sr)

	func _gr_n() -> int:
		return roundi(32760.0 * sr / 32000.0)

	func _setup_g() -> void:
		AKStreamFx._gr_window()
		_recoef_g()
		var n := _gr_n()
		xb.resize(GR_B0 + 2 * (n + 8) + int(xc[18]) + 1 + int(xc[19]) + 1)
		xb.fill(0.0)
		xb[3] = 1.0
		xb[4] = 1.0
		xb[5] = 1024.0 * sr / 32000.0
		xb[23] = 1.0
		xb[24] = 1.0

	func _recoef_g() -> void:
		var s := sr / 32000.0
		var den := xk[3]
		var tex := xk[4]
		var ov := 0.0
		if den >= 0.53:
			ov = (den - 0.53) * 2.12
		elif den <= 0.47:
			ov = (0.47 - den) * 2.12
		xc[0] = tex * 1.333 if tex < 0.75 else 1.0
		xc[2] = (tex - 0.75) * 4.0 if tex > 0.75 else 0.0
		xc[3] = ov
		xc[4] = GR_NG * ov * ov * ov
		xc[5] = floorf(1024.0 * pow(2.0, 4.0 * xk[1])) * s
		xc[6] = pow(2.0, xk[2] / 12.0)
		xc[7] = pow(2.0, -xk[2] / 12.0)
		var fc := 20.0 + 100.0 * xk[5] * xk[5]
		var g := tan(PI * fc / sr)
		xc[8] = g
		xc[9] = 1.0 / (1.0 + g + g * g)
		xc[10] = _gr_k(0.01)
		xc[11] = _gr_k(0.6 + 0.37 * xk[5])
		var t := clampf(1.04 * mix - 0.02, 0.0, 1.0) * PI * 0.5
		xc[12] = maxf(0.0, float(p.dry)) if p.has("dry") else cos(t)
		xc[13] = 1.2 * (maxf(0.0, float(p.wet)) if p.has("wet") else sin(t))
		var n := _gr_n()
		xc[14] = n
		xc[15] = maxi(1, roundi(32.0 * s))
		xc[16] = 1.0 if den < 0.5 else 0.0
		var wg := clampf(1.0 + 2.0 * xc[0], 1.0, 2.0)
		xc[17] = 1.0 + (wg - 1.0) * ov
		var base := 0
		for k in 8:
			var ln := maxi(2, roundi(GR_DIF[k] * s))
			xc[24 + 2 * k] = base
			xc[25 + 2 * k] = base + ln - 1
			base += ln + 1
		var m := 1
		while m < base:
			m <<= 1
		xc[18] = m - 1
		xc[20] = GR_B0 + 2 * (n + 8)
		base = 0
		for k in 10:
			var ln := maxi(2, roundi(GR_REV[k] * s))
			xc[40 + 2 * k] = base
			xc[41 + 2 * k] = base + ln - 1
			base += ln + 1
		var mr := 1
		while mr < base:
			mr <<= 1
		xc[19] = mr - 1
		xc[21] = xc[20] + m
		xc[60] = 10.0 * s
		xc[61] = 60.0 * s
		xc[62] = roundi(100.0 * s)
		xc[63] = 4680.0 * s
		xc[64] = 100.0 * s

	func _gr_start(g: int, head: int, n: int, high: bool) -> void:
		var gs := xc[5]
		var ratio := xc[6]
		var pan := 0.5 + xk[6] * (_rnd() - 0.5)
		var gl := 1.0
		var gr := 1.0
		if pan < 0.5:
			gr = 2.0 * pan
		else:
			gl = 2.0 * (1.0 - pan)
		if ratio > 1.0:
			gs = minf(gs, n * 0.25 * xc[7])
		var eaten := gs * ratio
		var avail := n - eaten - gs
		var width := int(gs) & ~1
		var start := head - int(xk[0] * avail + eaten)
		xb[g] = 1.0
		xb[g + 1] = posmod(start, n)
		xb[g + 2] = 0.0
		xb[g + 3] = ratio
		xb[g + 4] = 0.0
		xb[g + 5] = 2.0 / width
		if xc[0] >= 0.5:
			xb[g + 6] = (xc[0] - 0.5) * 2.0
			xb[g + 7] = 0.0
		else:
			xb[g + 6] = 0.0
			xb[g + 7] = 0.5 / (xc[0] + 0.01)
		xb[g + 8] = gl
		xb[g + 9] = gr
		xb[g + 10] = 1.0 if high else 0.0
		xb[5] += 0.1 * (gs - xb[5])

	static func _gr_hermite(b: PackedFloat64Array, i: int, t: float) -> float:
		var xm1 := b[i]
		var x0 := b[i + 1]
		var x1 := b[i + 2]
		var x2 := b[i + 3]
		var c := (x1 - xm1) * 0.5
		var v := x0 - x1
		var w := c + v
		var a := w + v + (x2 - x0) * 0.5
		var b_neg := w + a
		return (((a * t) - b_neg) * t + c) * t + x0

	func _tick_granular(io: PackedFloat64Array) -> void:
		var n := int(xc[14])
		var frozen := xk[8] >= 0.5
		if xb[8] == 0.0:
			xb[7] += 0.0005 * ((1.0 if frozen else 0.0) - xb[7])
			var fb := xk[5]
			xb[27] = fb * (1.0 - xb[7])
			var ra := clampf(xk[7] * 0.95 + fb * (2.0 - fb) * xb[7], 0.0, 1.0)
			xb[28] = ra * 0.54
			xb[29] = 0.35 + 0.63 * ra
			var target := xc[4]
			xb[11] = target
			xb[9] = target / xb[5]
			xb[10] = xb[5] / target if target > 0.0 else 1e30
			if xc[16] != 0.0:
				xb[9] = -1.0
			else:
				xb[6] = -1000.0
			var na0 := 0
			for i in GR_NG:
				if xb[GR_G0 + GR_GV * i] == 0.0:
					xb[32 + na0] = i
					na0 += 1
			xb[12] = na0
		var in0 := io[0]
		var in1 := io[1]
		var x := [0.0, 0.0]
		var g := xc[8]
		var fg := xb[27]
		for c in 2:
			var hp := (xb[17 + c] - xb[13 + c] - g * xb[13 + c] - xb[15 + c]) * xc[9]
			var bp := g * hp + xb[13 + c]
			xb[13 + c] = g * hp + bp
			var lp := g * bp + xb[15 + c]
			xb[15 + c] = g * bp + lp
			var iv := io[c]
			var v := fg * 1.4 * hp + iv
			x[c] = iv + fg * (v * (27.0 + v * v) / (27.0 + 9.0 * v * v) - iv)
		var bl := GR_B0
		var br := GR_B0 + n + 8
		var cf := int(xb[1])
		var head := int(xb[0])
		if frozen:
			if cf < GR_TAIL:
				xb[GR_T0 + cf] = clampf(x[0], -1.0, 1.0)
				xb[GR_T0 + GR_TAIL + cf] = clampf(x[1], -1.0, 1.0)
				cf += 1
		else:
			if cf > 0:
				cf -= 1
				if cf > 0:
					var gn := cf / float(GR_TAIL)
					x[0] += (xb[GR_T0 + GR_TAIL - cf] - x[0]) * gn
					x[1] += (xb[GR_T0 + 2 * GR_TAIL - cf] - x[1]) * gn
			var vl := clampf(x[0], -1.0, 1.0)
			var vr := clampf(x[1], -1.0, 1.0)
			xb[bl + head] = vl
			xb[br + head] = vr
			if head < 8:
				xb[bl + head + n] = vl
				xb[br + head + n] = vr
			head = 0 if head + 1 >= n else head + 1
		xb[1] = cf
		xb[0] = head
		xb[6] += 1.0
		var prob := _rnd() < xb[9] and xb[11] > xb[2]
		var det := xb[6] >= xb[10]
		var na := int(xb[12])
		if na > 0 and (prob or det):
			na -= 1
			var idx := int(xb[32 + na])
			_gr_start(GR_G0 + GR_GV * idx, head - 1, n, na >= 3 * GR_NG / 4)
			xb[6] = 0.0
			xb[12] = na
		var win := AKStreamFx._gr_win
		var o0 := 0.0
		var o1 := 0.0
		for i in GR_NG:
			var q := GR_G0 + GR_GV * i
			if xb[q] == 0.0:
				continue
			var ep := xb[q + 4]
			var gain := 2.0 - ep if ep >= 1.0 else ep
			if xb[q + 6] == 0.0:
				gain *= xb[q + 7]
				if gain >= 1.0:
					gain = 1.0
			elif xb[q + 10] != 0.0:
				var ix := gain * 4096.0
				var ii := int(ix)
				var wv := win[ii] + (win[ii + 1] - win[ii]) * (ix - ii)
				gain += xb[q + 6] * (wv - gain)
			xb[q + 4] = ep + xb[q + 5]
			if xb[q + 4] >= 2.0:
				xb[q] = 0.0
				continue
			var ph := xb[q + 2]
			var ip := int(ph)
			var t := ph - ip
			var si := int(xb[q + 1]) + ip
			if si >= n:
				si -= n
			var sl := 0.0
			var sr2 := 0.0
			if xb[q + 10] != 0.0:
				sl = _gr_hermite(xb, bl + si, t)
				sr2 = _gr_hermite(xb, br + si, t)
			else:
				sl = xb[bl + si] + (xb[bl + si + 1] - xb[bl + si]) * t
				sr2 = xb[br + si] + (xb[br + si + 1] - xb[br + si]) * t
			sl *= gain
			sr2 *= gain
			o0 += sl * xb[q + 8] + sr2 * (1.0 - xb[q + 9])
			o1 += sr2 * xb[q + 9] + sl * (1.0 - xb[q + 8])
			xb[q + 2] = ph + xb[q + 3]
		xb[3] += xc[10] * (xb[4] - xb[3])
		o0 *= xb[3]
		o1 *= xb[3]
		# The diffuser.
		var d := int(xc[20])
		var m := int(xc[18])
		var wp := (int(xb[22]) - 1) & m
		xb[22] = wp
		var o := [o0, o1]
		for c in 2:
			var acc: float = o[c]
			for k in 4:
				var j := 4 * c + k
				var rd := xb[d + ((wp + int(xc[25 + 2 * j])) & m)]
				acc += rd * 0.625
				xb[d + ((wp + int(xc[24 + 2 * j])) & m)] = acc
				acc *= -0.625
				acc += rd
			o[c] = o[c] + xc[2] * (acc - o[c])
		xb[17] = o[0]
		xb[18] = o[1]
		_gr_reverb(o)
		xb[8] += 1.0
		if xb[8] >= xc[15]:
			xb[8] = 0.0
			var act := GR_NG - xb[12]
			var e := act - xb[2]
			xb[2] += (0.9 if e > 0.0 else 0.2) * e
			xb[4] = (1.0 / sqrt(xb[2] - 1.0) if xb[2] > 2.0 else 1.0) * xc[17]
		io[0] = in0 * xc[12] + o[0] * xc[13]
		io[1] = in1 * xc[12] + o[1] * xc[13]

	func _gr_reverb(o: Array) -> void:
		var rb := int(xc[21])
		var m := int(xc[19])
		var wp := (int(xb[21]) - 1) & m
		xb[21] = wp
		if (wp & 31) == 0:
			xb[23] = 0.5 + 0.5 * cos(TAU * xb[25])
			xb[24] = 0.5 + 0.5 * cos(TAU * xb[26])
			xb[25] += 0.5 * 32.0 / sr
			xb[25] -= floorf(xb[25])
			xb[26] += 0.3 * 32.0 / sr
			xb[26] -= floorf(xb[26])
		var kap := 0.7
		var klp := xc[11]
		var krt := xb[29]
		var amount := xb[28]
		# ap1, smeared: read at a swinging offset, written 100 (scaled) in.
		var off := xc[60] + xc[61] * xb[23]
		var oi := int(off)
		var a := xb[rb + ((wp + oi + int(xc[40])) & m)]
		var acc := a + (xb[rb + ((wp + oi + int(xc[40]) + 1) & m)] - a) * (off - oi)
		xb[rb + ((wp + int(xc[40]) + int(xc[62])) & m)] = acc
		acc = (float(o[0]) + float(o[1])) * 0.2
		for k in 4:
			var rd := xb[rb + ((wp + int(xc[41 + 2 * k])) & m)]
			acc += rd * kap
			xb[rb + ((wp + int(xc[40 + 2 * k])) & m)] = acc
			acc *= -kap
			acc += rd
		var apout := acc
		off = xc[63] + xc[64] * xb[24]
		oi = int(off)
		a = xb[rb + ((wp + oi + int(xc[58])) & m)]
		acc = apout + (a + (xb[rb + ((wp + oi + int(xc[58]) + 1) & m)] - a) * (off - oi)) * krt
		xb[19] += klp * (acc - xb[19])
		acc = xb[19]
		var rd := xb[rb + ((wp + int(xc[49])) & m)]
		acc += rd * -kap
		xb[rb + ((wp + int(xc[48])) & m)] = acc
		acc *= kap
		acc += rd
		rd = xb[rb + ((wp + int(xc[51])) & m)]
		acc += rd * kap
		xb[rb + ((wp + int(xc[50])) & m)] = acc
		acc *= -kap
		acc += rd
		xb[rb + ((wp + int(xc[52])) & m)] = acc
		o[0] = float(o[0]) + (2.0 * acc - float(o[0])) * amount
		acc = apout + xb[rb + ((wp + int(xc[53])) & m)] * krt
		xb[20] += klp * (acc - xb[20])
		acc = xb[20]
		rd = xb[rb + ((wp + int(xc[55])) & m)]
		acc += rd * kap
		xb[rb + ((wp + int(xc[54])) & m)] = acc
		acc *= -kap
		acc += rd
		rd = xb[rb + ((wp + int(xc[57])) & m)]
		acc += rd * -kap
		xb[rb + ((wp + int(xc[56])) & m)] = acc
		acc *= kap
		acc += rd
		xb[rb + ((wp + int(xc[58])) & m)] = acc
		o[1] = float(o[1]) + (2.0 * acc - float(o[1])) * amount

	# ---- Airwindows (Chris Johnson, MIT; see NOTICE), as ak::Fx (setup_aw, recoef_aw, tick_aw).
	func _aw_algo() -> int:
		return clampi(roundi(xk[0]), 0, AW_NAMES.size() - 1)

	func _setup_aw() -> void:
		var algo := _aw_algo()
		xb.resize((_ga_base(12, 1) + GA_LEN[12] if algo == AW_GALACTIC else (1100 if algo == AW_TOTAPE6 else AW_STATE)) + algo)
		xb.fill(0.0)
		match algo:
			AW_TOTAPE6:
				xb[30] = 0.5
				xb[31] = PI
				xb[32] = 0.5
				xb[35] = 2463534242.0
			AW_AIR:
				xb[43] = 1.0
			AW_GALACTIC:
				for k in range(30, 43):
					xb[k] = 1.0
				xb[44] = 3.0
				xb[45] = 429496.7295
				xb[46] = 2463534242.0
			AW_DENSITY:
				xb[8] = 1.0
			AW_CONSOLE7CH:
				xb[12] = -1.0
				xb[13] = 64.0
			AW_CONSOLE7BUSS:
				xb[20] = -1.0
				xb[21] = 64.0
			AW_CONSOLE7:
				xb[12] = -1.0
				xb[13] = 64.0
				xb[30] = -1.0
				xb[31] = 64.0
			AW_CAPACITOR:
				xb[28] = 1.0
				xb[30] = 1.0
				xb[32] = 1000.0
				xb[33] = 1000.0
				xb[34] = 1000.0
		_recoef_aw()

	func _aw_lp(o: int, q: float) -> void:
		var k := tan(PI * minf(20000.0, 0.45 * sr) / sr)
		var norm := 1.0 / (1.0 + k / q + k * k)
		xc[o] = k * k * norm
		xc[o + 1] = 2.0 * xc[o]
		xc[o + 2] = xc[o]
		xc[o + 3] = 2.0 * (k * k - 1.0) * norm
		xc[o + 4] = (1.0 - k / q + k * k) * norm

	func _recoef_aw() -> void:
		var os := sr / 44100.0
		match _aw_algo():
			AW_DENSITY:
				var dp := xk[1] * 5.0 - 1.0
				var out := absf(dp)
				while out > 1.0:
					out -= 1.0
				xc[20] = pow(xk[2], 3) / os
				xc[21] = out
				xc[22] = dp * absf(dp)
				xc[23] = xk[3]
				xc[24] = xk[4]
			AW_CONSOLE7CH, AW_CONSOLE7BUSS, AW_CONSOLE7:
				_aw_lp(0, 1.618033988749894848204586)
				_aw_lp(5, 0.618033988749894848204586)
				_aw_lp(10, 0.5)
			AW_TOTAPE6:
				var ig := pow(10.0, ((xk[1] - 0.5) * 24.0) / 20.0)
				xc[30] = ig
				xc[31] = (1.0 - (pow(xk[2], 2) * 0.45)) / os
				xc[32] = xk[3] * 0.25 * ig
				xc[33] = 0.12 / os
				for k in 2:
					var f := (0.007 if k == 0 else 0.032) / os
					var q := 0.0009 if k == 0 else 0.0007
					var kk := tan(PI * f)
					var norm := 1.0 / (1.0 + kk / q + kk * kk)
					var c := 34 + 4 * k
					xc[c] = kk / q * norm
					xc[c + 1] = -xc[c]
					xc[c + 2] = 2.0 * (kk * kk - 1.0) * norm
					xc[c + 3] = (1.0 - kk / q + kk * kk) * norm
				xc[42] = pow(xk[4], 2) * os * 70
				xc[43] = (0.0024 * pow(xk[4], 2)) / os
				xc[44] = pow(10.0, ((xk[5] - 0.5) * 24.0) / 20.0)
				xc[45] = xk[6]
			AW_AIR:
				xc[30] = -pow(((xk[1] * 2.0) - 1.0), 3) * 2
				xc[31] = -pow(((xk[2] * 2.0) - 1.0), 3)
				xc[32] = -pow(((xk[3] * 2.0) - 1.0), 3) / 2
				xc[33] = 2.1 - xk[4]
				xc[34] = xk[5]
				xc[35] = xk[6]
			AW_GALACTIC:
				var regen := 0.0625 + ((1.0 - xk[1]) * 0.0625)
				xc[30] = regen
				xc[31] = (1.0 - (regen / 0.125)) * 1.333
				xc[32] = pow(1.00001 - (1.0 - xk[2]), 2.0) / sqrt(os)
				xc[33] = pow(xk[3], 3) * 0.001
				xc[34] = 1.0 - (pow(1.0 - xk[5], 3))
				xc[35] = clampi(int(floorf(os)), 1, 4)
				var size := (xk[4] * 1.77) + 0.1
				for k in 12:
					xc[50 + k] = int(GA_DLY[k] * size)
			AW_TUBE:
				var pf := int(5.0 * (1.0 - xk[1]) + 1.0)
				xc[25] = 1.0 + xk[1] * 0.2246161992650486
				xc[26] = pf
				xc[27] = 1.0 / float(pf + 1)
				xc[28] = 1.0 + 1.0 / float(pf)

	# A direct-form-1 biquad: coefficients xc[c..c+5), state xb[z..z+4).
	func _aw_bq(c: int, z: int, x: float) -> float:
		var y := xc[c] * x + xc[c + 1] * xb[z] + xc[c + 2] * xb[z + 1] - xc[c + 3] * xb[z + 2] - xc[c + 4] * xb[z + 3]
		xb[z + 1] = xb[z]
		xb[z] = x
		xb[z + 3] = xb[z + 2]
		xb[z + 2] = y
		return y

	func _aw_chase(g: int, target: float) -> void:
		if xb[g] != target:
			xb[g + 1] *= 2.0
		if xb[g + 1] > AW_BLOCK:
			xb[g + 1] = AW_BLOCK
		if xb[g] < 0.0:
			xb[g] = target

	func _aw_block(algo: int) -> void:
		match algo:
			AW_CONSOLE7CH:
				_aw_chase(12, xk[1] * 1.272019649514069)
			AW_CONSOLE7BUSS:
				_aw_chase(20, xk[1] * 1.03)
			AW_CONSOLE7:
				_aw_chase(12, xk[1] * 1.272019649514069)
				_aw_chase(30, xk[2] * 1.03)
			AW_GALACTIC:
				if xb[43] > xc[35] - 1:
					xb[43] = xc[35] - 1
			AW_CAPACITOR:
				for k in 3:
					var ch := xk[3] if k == 2 else xk[1 + k] * xk[1 + k]
					xb[35 + k] = 300.0 / (absf(xb[32 + k] - ch) + 1.0)
					xb[32 + k] = ch
					xb[38 + k] = ch

	func _aw_gain(g: int, target: float) -> float:
		xb[g + 1] *= 0.9999
		xb[g + 1] -= 0.01
		if xb[g + 1] < 64.0:
			xb[g + 1] = 64.0
		xb[g] = ((xb[g] * xb[g + 1]) + target) / (xb[g + 1] + 1.0)
		return xb[g]

	func _aw_c7ch(z: int, g: int, target: float, io: PackedFloat64Array) -> void:
		io[0] = _aw_bq(0, z, io[0])
		io[1] = _aw_bq(0, z + 4, io[1])
		var gc := _aw_gain(g, target)
		for c in 2:
			var x := io[c]
			if 1.0 != gc:
				x *= pow(gc, 3)
			x = clampf(x, -1.097, 1.097)
			var ax := absf(x)
			x = ((sin(x * ax) / (1.0 if ax == 0.0 else ax)) * 0.8) + (sin(x) * 0.2)
			if 1.0 != gc and 0.0 != gc:
				x /= gc
			io[c] = x

	func _aw_c7buss(z: int, g: int, target: float, io: PackedFloat64Array) -> void:
		io[0] = _aw_bq(5, z, io[0])
		io[1] = _aw_bq(5, z + 4, io[1])
		var gc := _aw_gain(g, target)
		for c in 2:
			var x := io[c]
			if 1.0 != gc:
				x *= sqrt(gc)
			x = clampf(x, -1.0, 1.0)
			var ax := absf(x)
			x = ((asin(x * ax) / (1.0 if ax == 0.0 else ax)) * 0.618033988749894848204586) + (asin(x) * 0.381966011250105)
			x = _aw_bq(10, z + 8 + 4 * c, x)
			if 1.0 != gc:
				x *= sqrt(gc)
			io[c] = x

	func _tick_aw(io: PackedFloat64Array) -> void:
		var algo := _aw_algo()
		if xb[0] == 0.0:
			_aw_block(algo)
		xb[0] = 0.0 if xb[0] + 1.0 >= AW_BLOCK else xb[0] + 1.0
		match algo:
			AW_DENSITY:
				var ia := xc[20]
				var out := xc[21]
				var d2 := xc[22]
				var flip := xb[8] != 0.0
				for c in 2:
					var x := io[c]
					var si := 4 + c if flip else 6 + c
					xb[si] = (xb[si] * (1.0 - ia)) + (x * ia)
					x -= xb[si]
					var count := d2
					while count > 1.0:
						var b := minf(absf(x) * 1.57079633, 1.57079633)
						b = sin(b)
						x = b if x > 0.0 else -b
						count -= 1.0
					var br := minf(absf(x) * 1.57079633, 1.57079633)
					br = sin(br) if d2 > 0 else 1 - cos(br)
					x = (x * (1 - out)) + (br * out) if x > 0 else (x * (1 - out)) - (br * out)
					if xc[23] < 1.0:
						x *= xc[23]
					if xc[24] < 1.0:
						x = (io[c] * (1.0 - xc[24])) + (x * xc[24])
					io[c] = x
				xb[8] = 0.0 if flip else 1.0
			AW_CONSOLE7CH:
				_aw_c7ch(4, 12, xk[1] * 1.272019649514069, io)
			AW_CONSOLE7BUSS:
				_aw_c7buss(4, 20, xk[1] * 1.03, io)
			AW_CONSOLE7:
				_aw_c7ch(4, 12, xk[1] * 1.272019649514069, io)
				_aw_c7buss(14, 30, xk[2] * 1.03, io)
			AW_PURESTDRIVE:
				for c in 2:
					var d := io[c]
					var x := sin(d)
					var apply := (absf(xb[4 + c] + x) / 2.0) * xk[1]
					io[c] = (d * (1.0 - apply)) + (x * apply)
					xb[4 + c] = sin(d)
			AW_TUBE:
				var hi := sr / 44100.0 > 1.9
				var pf := int(xc[26])
				for c in 2:
					var x := io[c]
					if hi:
						var st := x
						x += xb[4 + c]
						xb[4 + c] = st
						x *= 0.5
					x *= xc[25]
					x = clampf(x, -1.0, 1.0)
					var f := x
					for k in pf:
						f *= x
					if (pf % 2 == 1) and (x != 0.0):
						f = (f / x) * absf(x)
					f *= xc[27]
					x -= f
					x *= xc[28]
					if hi:
						var st := x
						x += xb[6 + c]
						xb[6 + c] = st
						x *= 0.5
					io[c] = x
			AW_CAPACITOR:
				xb[28] = ((xb[28] * xb[35]) + xb[38]) / (xb[35] + 1.0)
				xb[29] = ((xb[29] * xb[36]) + xb[39]) / (xb[36] + 1.0)
				xb[30] = ((xb[30] * xb[37]) + xb[40]) / (xb[37] + 1.0)
				var lp := xb[28]
				var ilp := 1.0 - lp
				var hp := xb[29]
				var ihp := 1.0 - hp
				var wt := xb[30]
				xb[31] += 1.0
				if xb[31] > 5.0:
					xb[31] = 0.0
				var cnt := int(xb[31])
				var st := [0, 1 if cnt % 2 == 0 else 2, 3 + cnt % 3]
				for c in 2:
					var x := io[c]
					var h := 4 + 12 * c
					for k in 3:
						var j: int = st[k]
						xb[h + j] = (xb[h + j] * ihp) + (x * hp)
						x -= xb[h + j]
						xb[h + 6 + j] = (xb[h + 6 + j] * ilp) + (x * lp)
						x = xb[h + 6 + j]
					io[c] = (io[c] * (1.0 - wt)) + (x * wt)
			AW_TOTAPE6:
				_aw_totape6(io)
			AW_AIR:
				_aw_air(io)
			AW_GALACTIC:
				_aw_galactic(io)

	# ---- Airwindows group 2 (as ak::Fx aw_totape6, aw_air, aw_galactic).
	static func _aw_fpd(v: float) -> float:
		var x := int(v)
		x ^= (x << 13) & 0xFFFFFFFF
		x ^= x >> 17
		x ^= (x << 5) & 0xFFFFFFFF
		return float(x)

	static func _ga_base(k: int, c: int) -> int:
		return GA_OFF[k] + c * GA_LEN[k]

	func _aw_tdf(c: int, z: int, x: float) -> float:
		var t := (x * xc[c]) + xb[z]
		xb[z] = -(t * xc[c + 2]) + xb[z + 1]
		xb[z + 1] = (x * xc[c + 1]) - (t * xc[c + 3])
		return t

	func _aw_totape6(io: PackedFloat64Array) -> void:
		var ig := xc[30]
		var roll := xc[31]
		var hbc := xc[32]
		var hbf := xc[33]
		var depth := xc[42]
		var ft := xc[43]
		var og := xc[44]
		var wt := xc[45]
		var x := [io[0], io[1]]
		var dry := [io[0], io[1]]
		if ig < 1.0:
			x[0] *= ig
			x[1] *= ig
		var randy := xb[35] / 4294967295.0
		var gc := int(xb[29])
		if gc < 0 or gc > 499:
			gc = 499
		var dl := AW_TT_D
		var dr := AW_TT_D + 501
		xb[dl + gc] = x[0]
		xb[dr + gc] = x[1]
		var count := gc
		if depth != 0.0:
			var offset := depth + (depth * pow(xb[30], 2) * sin(xb[31]))
			count += int(floorf(offset))
			var fr := offset - floorf(offset)
			var i0 := count - (500 if count > 499 else 0)
			var i1 := count + 1 - (500 if count + 1 > 499 else 0)
			x[0] = xb[dl + i0] * (1 - fr) + xb[dl + i1] * fr
			x[1] = xb[dr + i0] * (1 - fr) + xb[dr + i1] * fr
			xb[30] = (xb[30] * (1.0 - ft)) + (xb[32] * ft)
			xb[31] += xb[30] * ft
			if xb[31] >= (PI * 2.0):
				xb[31] -= PI
				xb[32] = 0.24 + (randy * 0.74)
		xb[29] = gc - 1
		var flip := xb[28] != 0.0
		var highs := [0.0, 0.0]
		var ground := [0.0, 0.0]
		for c in 2:
			var vib: float = x[c]
			var mi := (4 if flip else 6) + c
			var hi := (8 if flip else 10) + c
			xb[mi] = (xb[mi] * (1.0 - roll)) + (x[c] * roll)
			highs[c] = x[c] - xb[mi]
			var hb := xb[hi]
			hb += (x[c] * 0.05)
			hb -= (hb * hb * hb * hbf)
			hb = sin(hb)
			hb = _aw_tdf(34, 12 + 4 * c + (0 if flip else 2), hb)
			xb[hi] = asin(clampf(hb, -1.0, 1.0))
			var v := sin(x[c])
			v = _aw_tdf(38, 20 + 4 * c + (0 if flip else 2), v)
			x[c] = asin(clampf(v, -1.0, 1.0))
			ground[c] = vib - x[c]
		xb[28] = 0.0 if flip else 1.0
		for c in 2:
			var v: float = x[c]
			if ig > 1.0:
				v *= ig
			var so := minf(absf(highs[c]) * 1.57079633, 1.57079633)
			so = 1 - cos(so)
			if highs[c] > 0:
				v -= so
			if highs[c] < 0:
				v += so
			var sup := (1.0 - absf(v)) * 0.00013
			for k in 2:
				var h := 8 + 2 * k + c
				if xb[h] > sup:
					xb[h] -= sup
				if xb[h] < -sup:
					xb[h] += sup
			v += ((xb[8 + c] + xb[10 + c]) * hbc)
			v = clampf(v, -1.0, 1.0)
			var mojo := pow(absf(v), 0.25)
			if mojo > 0.0:
				v = (sin(v * mojo * PI * 0.5) / mojo)
			v += ground[c]
			if og != 1.0:
				v *= og
			var rc := 0.99
			var sf := 0.618033988749894848204586
			var last := xb[33 + c]
			if last >= rc:
				last = ((rc * sf) + (v * (1.0 - sf))) if v < rc else rc
			if last <= -rc:
				last = ((-rc * sf) + (v * (1.0 - sf))) if v > -rc else -rc
			if v > rc:
				v = ((rc * sf) + (last * (1.0 - sf))) if last < rc else rc
			if v < -rc:
				v = ((-rc * sf) + (last * (1.0 - sf))) if last > -rc else -rc
			xb[33 + c] = v
			v = clampf(v, -rc, rc)
			if wt != 1.0:
				v = (v * wt) + (dry[c] * (1.0 - wt))
			io[c] = v
		xb[35] = _aw_fpd(xb[35])

	func _aw_air1(t: int, k: int, even_first: bool, intensity: float, x: float, q: float) -> float:
		var ev := t + 5 + k
		var od := t + 8 + k
		var pv := t + 11 + k
		var f := xb[pv] - x
		if even_first:
			xb[ev] += f
			xb[od] -= f
			f = xb[ev] * intensity
		else:
			xb[od] += f
			xb[ev] -= f
			f = xb[od] * intensity
		xb[od] = (xb[od] - ((xb[od] - xb[ev]) / 256.0)) / q
		xb[ev] = (xb[ev] - ((xb[ev] - xb[od]) / 256.0)) / q
		xb[pv] = x
		return f

	func _aw_air(io: PackedFloat64Array) -> void:
		var hi := xc[30]
		var ti := xc[31]
		var ai := xc[32]
		var q := xc[33]
		var out := xc[34]
		var wt := xc[35]
		if xb[43] < 1.0 or xb[43] > 3.0:
			xb[43] = 1.0
		var cnt := int(xb[43])
		var flop := xb[42] != 0.0
		var fa := xb[40] != 0.0
		var fb := xb[41] != 0.0
		for c in 2:
			var t := 4 + 14 * c
			var x := io[c]
			var corr := 0.0
			var tf := xb[t + 3] - x
			var a := cnt - 1
			var z := (cnt + 1) % 3
			xb[t + a] += tf
			xb[t + z] -= tf
			tf = xb[t + a] * ti
			xb[t + 3] = xb[t + 4]
			xb[t + 4] = x
			xb[t] /= q
			xb[t + 1] /= q
			xb[t + 2] /= q
			corr += tf
			if flop:
				corr += _aw_air1(t, 0, fa, ai, x, q)
			else:
				corr += _aw_air1(t, 1, fb, ai, x, q)
			corr += _aw_air1(t, 2, flop, hi, x, q)
			var v := x + corr
			if out < 1.0:
				v *= out
			if wt < 1.0:
				v = (x * (1.0 - wt)) + (v * wt)
			io[c] = v
		xb[43] += 1.0
		if flop:
			xb[40] = 0.0 if fa else 1.0
		else:
			xb[41] = 0.0 if fb else 1.0
		xb[42] = 0.0 if flop else 1.0

	func _ga_rd(k: int, c: int) -> float:
		var i := int(xb[30 + k])
		var d := int(xc[50 + k])
		return xb[_ga_base(k, c) + i - (d + 1 if i > d else 0)]

	func _ga_step(k: int) -> void:
		xb[30 + k] += 1.0
		if xb[30 + k] < 0 or xb[30 + k] > xc[50 + k]:
			xb[30 + k] = 0

	func _aw_galactic(io: PackedFloat64Array) -> void:
		var regen := xc[30]
		var att := xc[31]
		var lp := xc[32]
		var drift := xc[33]
		var wt := xc[34]
		var ce := int(xc[35])
		var dry := [io[0], io[1]]
		xb[44] += (xb[45] * drift)
		if xb[44] > (3.141592653589793238 * 2.0):
			xb[44] = 0.0
			xb[45] = 0.4294967295 + (xb[46] * 0.0000000000618)
		var ml := _ga_base(12, 0)
		var mr := _ga_base(12, 1)
		var cm := int(xb[42])
		xb[ml + cm] = io[0] * att
		xb[mr + cm] = io[1] * att
		cm += 1
		if cm < 0 or cm > 256:
			cm = 0
		xb[42] = cm
		var x := [0.0, 0.0]
		for c in 2:
			var off := (sin(xb[44] + (3.141592653589793238 / 2.0 if c == 1 else 0.0)) + 1.0) * 127
			var w := int(cm + off)
			var m := ml if c == 0 else mr
			var fr := off - floorf(off)
			var v := xb[m + w - (257 if w > 256 else 0)] * (1 - fr)
			v += xb[m + w + 1 - (257 if w + 1 > 256 else 0)] * fr
			xb[4 + c] = (xb[4 + c] * (1.0 - lp)) + (v * lp)
			x[c] = xb[4 + c]
		xb[43] += 1.0
		if int(xb[43]) == ce:
			for c in 2:
				for k in 4:
					xb[_ga_base(k, c) + int(xb[30 + k])] = x[c] + (xb[8 + 4 * (1 - c) + k] * regen)
			for k in 4:
				_ga_step(k)
			for st in 3:
				var k0 := 4 * st
				var o := [[0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0]]
				for c in 2:
					for k in 4:
						o[c][k] = _ga_rd(k0 + k, c)
				for c in 2:
					for k in 4:
						var others := 0.0
						for j in 4:
							if j != k:
								others += o[c][j]
						var v: float = o[c][k] - others
						if st < 2:
							xb[_ga_base(k0 + 4 + k, c) + int(xb[30 + k0 + 4 + k])] = v
						else:
							xb[8 + 4 * c + k] = v
					if st == 2:
						x[c] = (o[c][0] + o[c][1] + o[c][2] + o[c][3]) / 8.0
				if st < 2:
					for k in 4:
						_ga_step(k0 + 4 + k)
			for c in 2:
				var rf := 16 if c == 0 else 23
				var inp: float = x[c]
				if ce == 4:
					xb[rf] = xb[rf + 4]
					xb[rf + 2] = (xb[rf] + inp) / 2
					xb[rf + 1] = (xb[rf] + xb[rf + 2]) / 2
					xb[rf + 3] = (xb[rf + 2] + inp) / 2
					xb[rf + 4] = inp
				if ce == 3:
					xb[rf] = xb[rf + 3]
					xb[rf + 2] = (xb[rf] + xb[rf] + inp) / 3
					xb[rf + 1] = (xb[rf] + inp + inp) / 3
					xb[rf + 3] = inp
				if ce == 2:
					xb[rf] = xb[rf + 2]
					xb[rf + 1] = (xb[rf] + inp) / 2
					xb[rf + 2] = inp
				if ce == 1:
					xb[rf] = inp
			xb[43] = 0.0
		var cy := int(xb[43])
		x[0] = xb[16 + cy]
		x[1] = xb[23 + cy]
		for c in 2:
			xb[6 + c] = (xb[6 + c] * (1.0 - lp)) + (x[c] * lp)
			var v := xb[6 + c]
			if wt < 1.0:
				v = (v * wt) + (dry[c] * (1.0 - wt))
			io[c] = v
		xb[46] = _aw_fpd(xb[46])

	func _rnd() -> float:
		rng = (rng * 1664525 + 1013904223) & 0xFFFFFFFF
		return rng / 4294967296.0

	func tick(io: PackedFloat64Array) -> void:
		match type:
			1, 2:
				var inl := io[0]
				var inr := io[1]
				var wet := PackedFloat64Array([0.0, 0.0])
				for ch in 2:
					var pp := ph + (spread * 0.25 if ch == 1 else 0.0)
					var acc := 0.0
					for v in voices:
						var lfo := sin(TAU * (pp + float(v) / voices))
						var d := (delay_ms + depth_ms * 0.5 * (1.0 + lfo)) * sr / 1000.0
						acc += _read(ch, d)
					wet[ch] = acc / voices
				var n := line_l.size()
				line_l[w] = inl + feedback * wet[0]
				line_r[w] = inr + feedback * wet[1]
				w = (w + 1) % n
				io[0] = inl * dmx + wet[0] * wmx
				io[1] = inr * dmx + wet[1] * wmx
				ph += rate / sr
				ph -= floorf(ph)
			3:
				for ch in 2:
					var lfo := sin(TAU * (ph + (spread * 0.25 if ch == 1 else 0.0)))
					var fc := center * pow(2.0, range_oct * 0.5 * depth * lfo)
					var nyq := 0.49 * sr
					fc = 20.0 if fc < 20.0 else (nyq if fc > nyq else fc)
					var t := tan(PI * fc / sr)
					var a := (t - 1.0) / (t + 1.0)
					var x := io[ch] + feedback * ph_last[ch]
					var zo := ch * 12
					for s in stages:
						var y := a * x + ap_z[zo + s]
						ap_z[zo + s] = x - a * y
						x = y
					ph_last[ch] = x
					io[ch] = io[ch] * dmx + x * wmx
				ph += rate / sr
				ph -= floorf(ph)
			4:
				for b in 3:
					var q := b * 13
					for ch in 2:
						var o := q + 5 + ch * 4
						var x := io[ch]
						var y := bq[q] * x + bq[q + 1] * bq[o] + bq[q + 2] * bq[o + 1] - bq[q + 3] * bq[o + 2] - bq[q + 4] * bq[o + 3]
						bq[o + 1] = bq[o]
						bq[o] = x
						bq[o + 3] = bq[o + 2]
						bq[o + 2] = y
						io[ch] = y
			5:
				var det := absf(io[0]) if absf(io[0]) > absf(io[1]) else absf(io[1])
				var lev := 20.0 * log(det + 1e-12) / log(10.0)
				var over := lev - threshold
				var target := 0.0
				var hk := knee * 0.5
				if knee > 0.0 and over > -hk and over < hk:
					var x := over + hk
					target = -(1.0 - 1.0 / ratio) * x * x / (2.0 * knee)
				elif over >= hk:
					target = -(1.0 - 1.0 / ratio) * over
				var k := k_att if target < gr_db else k_rel
				gr_db = target + (gr_db - target) * k
				var g := pow(10.0, (gr_db + makeup) / 20.0)
				io[0] *= g
				io[1] *= g
			6:
				for ch in 2:
					var y := (tanh(io[ch] * sat_g + asym) - sat_off) * sat_out
					sat_z[ch] += sat_lp * (y - sat_z[ch])
					io[ch] = io[ch] * dmx + sat_z[ch] * wmx
			7:
				var p2 := ph + 0.5 - floorf(ph + 0.5)
				var g1 := sin(PI * ph) * sin(PI * ph)
				var g2 := 1.0 - g1
				var wl := g1 * _read(0, ph * win + 1.0) + g2 * _read(0, p2 * win + 1.0)
				var wr := g1 * _read(1, ph * win + 1.0) + g2 * _read(1, p2 * win + 1.0)
				line_l[w] = io[0]
				line_r[w] = io[1]
				w = (w + 1) % line_l.size()
				ph += ratio_step
				ph -= floorf(ph)
				io[0] = io[0] * dmx + wl * wmx
				io[1] = io[1] * dmx + wr * wmx
			8:
				var c := sin(TAU * cph)
				cph += freq * pow(2.0, depth * sin(TAU * ph)) / sr
				cph -= floorf(cph)
				ph += rate / sr
				ph -= floorf(ph)
				io[0] = io[0] * dmx + io[0] * c * wmx
				io[1] = io[1] * dmx + io[1] * c * wmx
			9:
				var env := 0.5 - 0.5 * cos(TAU * ph)
				var g := 1.0 - depth * gr_amp * env
				ph += rate * gr_rate / sr
				if ph >= 1.0:
					ph -= floorf(ph)
					gr_rate = 1.0 + jitter * (_rnd() - 0.5)
					gr_amp = 1.0 - jitter * 0.6 * _rnd()
				io[0] = io[0] * dmx + io[0] * g * wmx
				io[1] = io[1] * dmx + io[1] * g * wmx
			10:
				if ctr == 0:
					var step := pow(2.0, 1.0 - bits)
					held[0] = floorf(io[0] / step + 0.5) * step
					held[1] = floorf(io[1] / step + 0.5) * step
				ctr = (ctr + 1) % hold
				io[0] = io[0] * dmx + held[0] * wmx
				io[1] = io[1] * dmx + held[1] * wmx
			11:
				var il := w - dl
				if il < 0:
					il += dn
				var ir := w - dr
				if ir < 0:
					ir += dn
				var yl: float = line_l[il]
				var yr: float = line_r[ir]
				ez[0] += e_k * (yl - ez[0])
				ez[1] += e_k * (yr - ez[1])
				match dmode:
					0:
						line_l[w] = io[0] + feedback * ez[0]
						line_r[w] = io[1] + feedback * ez[1]
					1:
						line_l[w] = io[0] + feedback * ez[1]
						line_r[w] = io[1] + feedback * ez[0]
					_:
						line_l[w] = (io[0] + io[1]) * 0.5 + feedback * ez[1]
						line_r[w] = feedback * ez[0]
				w = (w + 1) % dn
				io[0] = io[0] * dad + yl * wmx
				io[1] = io[1] * dad + yr * wmx
			12:
				var input := (io[0] + io[1]) * 0.015
				if rv_lck > 0.0:
					rv_lcz += (input - rv_lcz) * rv_lck
					input -= rv_lcz
				if rv_hck > 0.0:
					rv_hcz += (input - rv_hcz) * rv_hck
					input = rv_hcz
				if rv_pre.size() > 0:
					var pd := rv_pre[rv_pw]
					rv_pre[rv_pw] = input
					rv_pw = 0 if rv_pw + 1 == rv_pre.size() else rv_pw + 1
					input = pd
				var o := PackedFloat64Array([0.0, 0.0])
				for ch in 2:
					var acc := 0.0
					for j in 8:
						var k := ch * 12 + j
						var at := rv_off[k] + rv_idx[k]
						var y: float = rv[at]
						var si := ch * 8 + j
						rv_store[si] = y * (1.0 - rv_dk) + rv_store[si] * rv_dk
						rv[at] = input + rv_store[si] * rv_fb
						acc += y
						rv_idx[k] = 0 if rv_idx[k] + 1 == rv_len[k] else rv_idx[k] + 1
					for j in range(8, 12):
						var k := ch * 12 + j
						var at := rv_off[k] + rv_idx[k]
						var b: float = rv[at]
						var x := acc
						acc = b - x
						rv[at] = x + b * 0.5
						rv_idx[k] = 0 if rv_idx[k] + 1 == rv_len[k] else rv_idx[k] + 1
					o[ch] = acc
				io[0] = io[0] * dad + (o[0] * rv_w1 + o[1] * rv_w2) * wmx
				io[1] = io[1] * dad + (o[1] * rv_w1 + o[0] * rv_w2) * wmx
			13:
				for ch in 2:
					var zo := ch * 12
					var x := io[ch]
					if f_n == 1:
						ap_z[zo] += (x - ap_z[zo]) * f_a
						x = x - ap_z[zo] if f_hp else ap_z[zo]
					else:
						for s in f_n / 2:
							var i1 := zo + 2 * s
							var v3 := x - ap_z[i1 + 1]
							var v1 := f_a1 * ap_z[i1] + f_a2 * v3
							var v2 := ap_z[i1 + 1] + f_a2 * ap_z[i1] + f_a3 * v3
							ap_z[i1] = 2.0 * v1 - ap_z[i1]
							ap_z[i1 + 1] = 2.0 * v2 - ap_z[i1 + 1]
							x = x - f_k * v1 - v2 if f_hp else v2
					io[ch] = x
			14:
				var p := maxf(absf(io[0]), absf(io[1]))
				var need := lim_c / p if p > lim_c else 1.0
				if need < lim_g:
					lim_g = need
				else:
					lim_g = need - (need - lim_g) * lim_k
				io[0] *= lim_g
				io[1] *= lim_g
			15:
				_tick_freqshift(io)
			16:
				_tick_rotary(io)
			17:
				_tick_stutter(io)
			18:
				_tick_conditioner(io)
			19:
				for b in 11:
					if xk[b] != 0.0 and GEQ_HZ[b] < 0.45 * sr:
						io[0] = _xbq(13 * b, io[0], 0)
						io[1] = _xbq(13 * b, io[1], 1)
				io[0] *= xc[0]
				io[1] *= xc[0]
			20:
				_tick_resonator(io)
			21:
				for ch in 2:
					var h := _xbq(0, io[ch], ch)
					var o := _xbq(13, tanh(xc[0] * h) * xc[1], ch)
					io[ch] = io[ch] * dad + o * wmx
			22:
				_tick_waveshaper(io)
			23:
				var m := (io[0] + io[1]) * 0.5
				var sd := (io[0] - io[1]) * 0.5
				if xk[2] > 0.0:
					xs[0] += (sd - xs[0]) * xc[0]
					sd -= xs[0]
				m *= xc[1]
				sd *= xc[2]
				io[0] = m * xc[3] + sd
				io[1] = m * xc[4] - sd
			24:
				_tick_ensemble(io)
			25:
				_tick_combulator(io)
			26:
				_tick_tape(io)
			27:
				_tick_treemonster(io)
			28:
				_tick_spring(io)
			29:
				_tick_bonsai(io)
			30:
				_tick_chow(io)
			31:
				_tick_neuron(io)
			32:
				_tick_granular(io)
			33:
				_tick_aw(io)
