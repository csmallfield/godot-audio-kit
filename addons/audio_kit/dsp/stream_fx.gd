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
	"ensemble", "combulator", "tape", "treemonster", "spring", "bonsai", "chow", "neuron"]
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
}
const _MIXED := ["chorus", "flanger", "phaser", "saturate", "pitch", "ring", "growl", "crush", "delay", "reverb", "freqshift", "rotary",
	"stutter", "resonator", "exciter", "waveshaper", "ensemble", "combulator", "tape", "treemonster", "spring", "bonsai", "chow", "neuron"]
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
		elif String(k) != "type":
			d[String(k)] = spec[k]
	for xk: Array in XKEYS.get(t, []):
		if not d.has(xk[0]):
			d[xk[0]] = xk[1]
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
		xc.resize(24)
		xc.fill(0.0)
		xw = 0
		if type == T_FREQSHIFT:
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
