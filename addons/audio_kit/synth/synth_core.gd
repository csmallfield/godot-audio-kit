# SPDX-License-Identifier: Apache-2.0
@tool
## The synth engine in GDScript: the reference for the native engine
## (native/src/synth.cpp) and the fallback that bakes patches when the
## native core isn't installed. Both follow the same steps in the same order,
## so they agree to float rounding (tests/test_synth.gd holds them to it).
##
##   var core := AKSynthCore.new(patch.compile())
##   core.note_on(0, 60.0, 0.8)
##   core.note_off(24000, 60.0)
##   var lr := core.render(48000)      # [PackedFloat32Array l, r]
##
## Events carry an absolute frame; render() applies each at its exact sample.
## Per voice and sample: envelopes, then LFOs, then the matrix, then pitch and
## oscillators (last to first, so an oscillator hears the ones after it this
## sample and the ones before it from the previous sample), filter, amp, pan,
## with the modulation worked out every CONTROL samples.
class_name AKSynthCore
extends RefCounted

## Bumped when the engine's output changes (part of every patch's bake key).
const VERSION := 3
const MAX_OSC := 16
const MAX_U := 16
## Copies of one oscillator inside each unison voice (its `stack`).
const MAX_STACK := 16
## Phase slots per oscillator: unison voices x stack, at most 64 (a stack is cut to fit under
## wide unison).
const MAX_SLOT := 64
## The highest phase increment an oscillator plays (cycles per sample, just under Nyquist):
## a pitch pushed past it holds there instead of folding back down as aliasing.
const MAX_INC := 0.49
## Pink noise: Paul Kellet's three-pole filter on the white noise, scaled to white's level;
## red noise: a leaky integrator, likewise.
const PINK_G := 0.33695
const RED_G := 10.1011

enum { E_ON, E_OFF, E_BEND, E_MOD, E_TOUCH, E_ALL_OFF, E_PANIC, E_SUSTAIN, E_TEMPO }
enum { ATTACK, DECAY, SUSTAIN, RELEASE, IDLE }
enum { SRC_ENV1, SRC_ENV2, SRC_ENV3, SRC_LFO1, SRC_LFO2, SRC_VEL, SRC_KEY, SRC_MOD, SRC_TOUCH, SRC_RANDOM, SRC_BEND,
	SRC_ENV4, SRC_ENV5, SRC_ENV6, SRC_ENV7, SRC_ENV8, SRC_LFO3, SRC_LFO4, SRC_LFO5, SRC_LFO6, SRC_LFO7, SRC_LFO8,
	SRC_MAC1, SRC_MAC2, SRC_MAC3, SRC_MAC4 }
const N_SRC := 26
## LFOs per patch (lfo1 .. lfo8).
const N_LFO := 8
## The comb's buffer, in samples (AKPatch.COMB_MAX).
const COMB_MAX := 4096
## Envelopes: amp_env, env2, env3, then AKPatch.envelopes.
const MAX_ENV := 8
## Envelope kinds (AKPatch._compile_env).
enum { K_ADSR, K_STAGES, K_DX7, K_DX7P, K_CZ }
## A stages envelope's stage length meaning "hold here" (sustain, or past the
## last stage), and "falling with release_s" (no release stages).
const ST_HOLD := -1
const ST_FALL := -2
## The dx7 mode: msfa's block (N = 64 samples), and its level for envelope
## level 99 at output level 99 (gain 1).
const DX7_N := 64
const DX7_FULL := 251658240
const DX7_LEVELLUT: Array[int] = [0, 5, 9, 13, 17, 20, 23, 25, 27, 29, 31, 33, 35, 37, 39, 41, 42, 43, 45, 46]
const DX7_STATICS: Array[int] = [1764000, 1764000, 1411200, 1411200, 1190700, 1014300, 992250,
	882000, 705600, 705600, 584325, 507150, 502740, 441000, 418950,
	352800, 308700, 286650, 253575, 220500, 220500, 176400, 145530,
	145530, 125685, 110250, 110250, 88200, 88200, 74970, 61740,
	61740, 55125, 48510, 44100, 37485, 31311, 30870, 27562, 27562,
	22050, 18522, 17640, 15435, 14112, 13230, 11025, 9261, 9261, 7717,
	6615, 6615, 5512, 5512, 4410, 3969, 3969, 3439, 2866, 2690, 2249,
	1984, 1896, 1808, 1411, 1367, 1234, 1146, 926, 837, 837, 705,
	573, 573, 529, 441, 441]
const DX7_VELOCITY: Array[int] = [0, 70, 86, 97, 106, 114, 121, 126, 132, 138, 142, 148, 152, 156, 160, 163,
	166, 170, 173, 174, 178, 181, 184, 186, 189, 190, 194, 196, 198, 200, 202,
	205, 206, 209, 211, 214, 216, 218, 220, 222, 224, 225, 227, 229, 230, 232,
	233, 235, 237, 238, 240, 241, 242, 243, 244, 246, 246, 248, 249, 250, 251,
	252, 253, 254]
## msfa's operator gain threshold (1120 in Q24, gain 2 = level 99), in the dx7
## envelope's units (gain 1 = level 99): below it at both ends of a block, an
## operator is silent for the block.
const DX7_THRESH := 1120.0 / 33554432.0
const DX7_COARSE: Array[int] = [-16777216, 0, 16777216, 26591258, 33554432, 38955489, 43368474, 47099600,
	50331648, 53182516, 55732705, 58039632, 60145690, 62083076, 63876816,
	65546747, 67108864, 68576247, 69959732, 71268397, 72509921, 73690858,
	74816848, 75892776, 76922906, 77910978, 78860292, 79773775, 80654032,
	81503396, 82323963, 83117622]
const DX7_LFO_SPEED: Array[float] = [0.062541, 0.125031, 0.312393, 0.437120, 0.624610,
	0.750694, 0.936330, 1.125302, 1.249609, 1.436782,
	1.560915, 1.752081, 1.875117, 2.062494, 2.247191,
	2.374451, 2.560492, 2.686728, 2.873976, 2.998950,
	3.188013, 3.369840, 3.500175, 3.682224, 3.812065,
	4.000800, 4.186202, 4.310716, 4.501260, 4.623209,
	4.814636, 4.930480, 5.121901, 5.315191, 5.434783,
	5.617346, 5.750431, 5.946717, 6.062811, 6.248438,
	6.431695, 6.564264, 6.749460, 6.868132, 7.052186,
	7.250580, 7.375719, 7.556294, 7.687577, 7.877738,
	7.993605, 8.181967, 8.372405, 8.504848, 8.685079,
	8.810573, 8.986341, 9.122423, 9.300595, 9.500285,
	9.607994, 9.798158, 9.950249, 10.117361, 11.251125,
	11.384335, 12.562814, 13.676149, 13.904338, 15.092062,
	16.366612, 16.638935, 17.869907, 19.193858, 19.425019,
	20.833333, 21.034918, 22.502250, 24.003841, 24.260068,
	25.746653, 27.173913, 27.578599, 29.052876, 30.693677,
	31.191516, 32.658393, 34.317090, 34.674064, 36.416606,
	38.197097, 38.550501, 40.387722, 40.749796, 42.625746,
	44.326241, 44.883303, 46.772685, 48.590865, 49.261084]
const DX7_PENV_RATE: Array[int] = [1, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12,
	12, 13, 13, 14, 14, 15, 16, 16, 17, 18, 18, 19, 20, 21, 22, 23, 24,
	25, 26, 27, 28, 30, 31, 33, 34, 36, 37, 38, 39, 41, 42, 44, 46, 47,
	49, 51, 53, 54, 56, 58, 60, 62, 64, 66, 68, 70, 72, 74, 76, 79, 82,
	85, 88, 91, 94, 98, 102, 106, 110, 115, 120, 125, 130, 135, 141, 147,
	153, 159, 165, 171, 178, 185, 193, 202, 211, 232, 243, 254, 255]
const DX7_PENV_TAB: Array[int] = [-128, -116, -104, -95, -85, -76, -68, -61, -56, -52, -49, -46, -43,
	-41, -39, -37, -35, -33, -32, -31, -30, -29, -28, -27, -26, -25, -24,
	-23, -22, -21, -20, -19, -18, -17, -16, -15, -14, -13, -12, -11, -10,
	-9, -8, -7, -6, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
	11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27,
	28, 29, 30, 31, 32, 33, 34, 35, 38, 40, 43, 46, 49, 53, 58, 65, 73,
	82, 92, 103, 115, 127]
const DX7_PMS: Array[int] = [0, 10, 20, 33, 55, 92, 153, 255]
const DX7_AMS: Array[int] = [0, 4342338, 7171437, 16777216]
const DX7_EXP_SCALE: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 14, 16, 19, 23, 27, 33, 39, 47, 56, 66,
	80, 94, 110, 126, 142, 158, 174, 190, 206, 222, 238, 250]
enum { D_PITCH, D_CUTOFF, D_Q, D_AMP, D_PAN, D_OPITCH, D_OLEVEL, D_OFM, D_OWIDTH, D_OPOS, D_LFO1R, D_LFO2R, D_LFO3R, D_LFO4R,
	D_LFO5R, D_LFO6R, D_LFO7R, D_LFO8R, D_COMBFB, D_COMBP, D_CUT2, D_Q2, D_E1T, D_E2T, D_E3T, D_E4T, D_E5T, D_E6T, D_E7T, D_E8T,
	D_FB, D_E1A, D_E1D = D_E1A + 8, D_E1R = D_E1D + 8 }
enum { SH_SINE, SH_TRI, SH_SAW, SH_SQUARE, SH_PULSE, SH_NOISE, SH_MORPH, SH_TABLE, SH_PD }
## 2^(32/12): the CZ chip's noise pitch jump.
const PD_NOISE_UP := 6.3496042078727978
enum { F_OFF, F_LOW, F_HIGH, F_BAND, F_NOTCH, F_LADDER, F_MIX, F_LSHELF, F_HSHELF, F_BSHELF, F_ALLPASS, F_COMB }
## Modulation (LFOs, the matrix, pitch, filter coefficients, levels) is
## worked out every CONTROL samples and held between; envelopes, oscillators
## and the filter run every sample.
const CONTROL := 8
## A stolen voice fades out with this time constant instead of cutting.
const STEAL_FADE_S := 0.003
## A legato note's new velocity reaches the level over this time constant
## (a jump in level is a click).
const VEL_GLIDE_S := 0.004
## The mod wheel and aftertouch, as a voice hears them, follow the controller
## over this time constant (a step in cutoff or FM depth is a crackle).
const CTL_GLIDE_S := 0.006
## Below this amp-envelope level a releasing voice is finished.
const SILENT := 1e-5

var sr := 48000
var frame := 0
var bend := 0.0
var mod_wheel := 0.0
var aftertouch := 0.0
## The sustain pedal: while down, released notes keep sounding.
var sustain := false
## The tempo: the patch's tempo_bpm until set_tempo sets one.
var tempo_bpm := 120.0
var _tempo_set := false
var voices: Array[_Voice] = []

var _p := {}
# Per-patch numbers derived once (sample counts, coefficients).
var _env_a := PackedInt64Array([0, 0, 0, 0, 0, 0, 0, 0])
var _env_d := PackedInt64Array([1, 1, 1, 1, 1, 1, 1, 1])
var _env_s := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
var _env_kd := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
var _env_kr := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
# The second release stage: its rate, and the knee (a share of the level at key-up) where it takes over.
var _env_kr2 := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
var _env_knee := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
var _env_exp := [false, false, false, false, false, false, false, false]
## Each envelope's kind (K_ADSR ...), and how many the patch has (3 .. 8).
var _env_kind := PackedInt64Array([0, 0, 0, 0, 0, 0, 0, 0])
var _n_env := 3
## The dx7 mode's rate factor: msfa's sr_multiplier (44100 / rate, Q24).
var _dx7_srm := 0
## The CZ chip's 40 kHz over the mix rate (cz envelopes).
var _cz_scale := 1.0
## msfa's tables for this rate: Freqlut (log frequency to phase increment) and
## the LFO's and pitch envelope's units; the sine table (for the LFO's sine).
var _freqlut := PackedInt64Array()
var _lfo_unit := 0
var _lfo_ratio := 0
var _penv_unit := 0
static var _sintab := PackedInt64Array()
## Which LFOs are DX7 LFOs, and the first one (its amp modulation reaches dx7 envelopes; -1: none).
var _lfo_dx7 := [false, false, false, false, false, false, false, false]
var _dx7_lfo := -1
## A pd oscillator's sample (native pd_sample): the CZ's uPD933 transfer functions and windows
## (after MAME's upd933.cpp, BSD-3-Clause, Devin Acker) in the chip's integer arithmetic.
## `dcw` 0-1023 of 1024; returns -1 .. 1.
static var _pd_cos := PackedInt32Array()

@warning_ignore("integer_division")
static func pd_sample(wave: int, win: int, ph: float, dcw_f: float) -> float:
	if _pd_cos.is_empty():
		_pd_cos.resize(0x800)
		for i in 0x800:
			_pd_cos[i] = int(0xfff * (1 - cos(2.0 * PI * i / 0x7ff)) / 2)
	var pos := clampi(int(ph * 2048.0), 0, 0x7ff)
	var dcw := clampi(int(dcw_f), 0, 0x3ff)
	var pivot := 0x400 - dcw
	var phase := 0
	match wave:
		0:
			phase = pos * 0x400 / pivot if pos < pivot else 0x400 + (pos - pivot) * 0x400 / (0x800 - pivot)
		1:
			phase = ((pos & 0x3ff) * 0x400 / pivot if (pos & 0x3ff) < pivot else 0x3ff) | (pos & 0x400)
		2:
			phase = pos * 0x800 / (pivot * 2) if pos < pivot * 2 else 0x7ff
		4:
			phase = pos * 0x800 / pivot if pos < pivot else (pos - pivot) * 0x800 / (0x800 - pivot)
		5:
			phase = pos if pos < 0x400 else (0x400 + (pos & 0x3ff) * 0x400 / pivot if pos < pivot + 0x400 else 0x7ff)
		6:
			phase = (pos + ((pos * dcw) >> 6)) & 0x7ff
		7:
			phase = (pos & 0x3ff) * 0x400 / pivot if (pos & 0x3ff) < pivot else 0x7ff
	phase &= 0x7ff
	var w := 0
	match win:
		1:
			w = pos
		2:
			w = (pos & 0x3ff) * 2
			if pos < 0x400:
				w ^= 0x7fe
		3:
			w = (pos & 0x3ff) * 2 if pos >= 0x400 else 0
		4:
			w = pos * 2 if pos < 0x400 else 0x7ff
		5:
			w = (0x3ff ^ (pos & 0x3ff)) * 2
	var s := _pd_cos[phase]
	if w != 0:
		s = s * (0x800 - w) / 0x800
	return s * (2.0 / 4095.0) - 1.0


## When every audible oscillator follows its own envelope (level_env): those
## envelopes, and the voice ends when they all have (as a DX7 voice ends with
## its carriers). Empty otherwise.
var _carrier_envs := PackedInt64Array()
## Any oscillator using the phase 2 operator fields.
var _ops := false
var _lfo_shape := PackedInt64Array([0, 0, 0, 0, 0, 0, 0, 0])
var _lfo_inc := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
var _lfo_delay := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
var _lfo_width := PackedFloat64Array([0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5])
var _lfo_phase := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
var _lfo_free := [false, false, false, false, false, false, false, false]
## Custom LFO shapes: the points, linear (0) or step (1), one-shot.
var _lfo_pts: Array = [PackedFloat64Array(), PackedFloat64Array(), PackedFloat64Array(), PackedFloat64Array(),
	PackedFloat64Array(), PackedFloat64Array(), PackedFloat64Array(), PackedFloat64Array()]
var _lfo_interp := PackedInt64Array([0, 0, 0, 0, 0, 0, 0, 0])
var _lfo_once := [false, false, false, false, false, false, false, false]
## LFOs running: lfo1, lfo2 and the patch's `lfos`.
var _n_lfo := 2
## Voice slots (AKPatch voice_pan, slop): how many, the next to take, and each one's pan, pitch
## (semitones), cutoff (octaves), level (gain) and envelope time factor.
var _n_slot := 0
var _rr := 0
var _slot_pan := PackedFloat64Array()
var _sl_pitch := PackedFloat64Array()
var _sl_cut := PackedFloat64Array()
var _sl_gain := PackedFloat64Array()
var _sl_tf := PackedFloat64Array()
var _slop_time := false
## The ladder's output: 0 the fourth pole, 1 `poles`, 2 `pole_mix`.
var _lmode := 0
var _lpoles := 4.0
var _lmix := PackedFloat64Array()
## The pre-filter's one-pole coefficients (0: off), the comb.
var _pre_lp := 0.0
var _pre_hp := 0.0
var _comb_on := false
## The highest oscillator phase increment (MAX_INC with nyquist_clamp; otherwise none).
var _inc_max := 1e9
## Band-limited hard sync (AKPatch.band_limited_sync).
var _bl_sync := false
## The windowed-sinc BLEP on saw and pulse edges (AKPatch.sinc_blep).
var _sinc_blep := false
## filter2 (AKPatch.filter2; empty: off), its routing (0 series, 1 parallel), the macros.
var _f2 := {}
var _f2_on := false
## Filter feedback (filter_feedback) and the saturation's tanh curve.
var _fb_on := false
var _fb := 0.0
var _sat_tanh := false
var _routing := 0
var _macros := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _comb_semis := 0.0
var _comb_fb := 0.0
## Tempo-synced LFOs: the rate in beats per cycle (0: rate_hz), and the free
## clock's cycles at _lfo_base_frame (a tempo change starts a new segment).
var _lfo_beats := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
var _lfo_base := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
var _lfo_base_frame := PackedInt64Array([0, 0, 0, 0, 0, 0, 0, 0])
## The arpeggiator (AKPatch.arp compiled): held keys [note, velocity] in key
## order, its clock in beats since the first key, the next step and gate-off
## (beats; -1 none), the note it is sounding, steps taken, its random state.
var _arp := {}
var _arp_on := false
var _arp_keys: Array = []
var _arp_pos := 0.0
var _arp_next := 0.0
var _arp_gate_at := -1.0
var _arp_cur := 0.0
var _arp_sounding := false
var _arp_step := 0
var _arp_rng := 1
var _arp_starts := 0
## Any oscillator around the filter.
var _bypass := false
var _ratio := PackedFloat64Array()
var _inv_su := 1.0
## Unison voices' stereo weights (equal power across `spread`).
var _uwl := PackedFloat64Array()
var _uwr := PackedFloat64Array()
## Unison voices' levels (unison_level for all but the middle one or two).
var _uw := PackedFloat64Array()
## Oscillators' stereo weights (equal power across their pan).
var _opl := PackedFloat64Array()
var _opr := PackedFloat64Array()
## Per oscillator slot (j * MAX_SLOT + unison voice * stack + copy): frequency
## ratio, level and stereo weights; per oscillator its slot count, stack,
## normalisation and highest ratio; and, per pair of oscillators, which slot of
## the second one a slot of the first reads (FM, sync, ring).
var _sratio := PackedFloat64Array()
var _sw := PackedFloat64Array()
var _swl := PackedFloat64Array()
var _swr := PackedFloat64Array()
var _slot_n := PackedInt64Array()
var _slot_s := PackedInt64Array()
var _oinv := PackedFloat64Array()
var _ormax := PackedFloat64Array()
var _smap := PackedInt64Array()
var _stereo := false
## Wavetables: per table {frames, size, levels, data}.
var _tables: Array = []
var _kg := 0.0
var _kill_k := 0.0
var _vel_k := 0.0
var _ctl_k := 0.0
var _events: Array = []   # [frame, seq, type, a, b], sorted
var _seq := 0
var _serial := 0
var _last_note := -1.0
var _held: Array = []      # mono/legato note stack: [note, velocity]
var _fx: AKStreamFx.Chain
var _fx_spec: Array = []
var _io := PackedFloat64Array([0.0, 0.0])


func _init(compiled := {}, sample_rate := 48000) -> void:
	sr = sample_rate
	if not compiled.is_empty():
		set_patch(compiled)


## Use a compiled patch (AKPatch.compile()). Playing voices carry on with it.
func set_patch(c: Dictionary) -> void:
	# Effects keep running when an edit leaves their settings alone; changed settings keep
	# each effect's running state (tails, filter states) where its buffers allow.
	var fx_spec: Array = c.get("effects", [])
	if _fx == null:
		_fx = AKStreamFx.Chain.new(fx_spec, sr)
		_fx_spec = fx_spec.duplicate(true)
	elif var_to_str(fx_spec) != var_to_str(_fx_spec):
		_fx = _fx.retuned(fx_spec, sr)
		_fx_spec = fx_spec.duplicate(true)
	_p = c
	_n_env = mini(MAX_ENV, (c.env as Array).size())
	_dx7_srm = int(44100.0 / sr * 16777216.0)
	_cz_scale = 40000.0 / sr
	_dx7_tables()
	_lfo_dx7 = [false, false, false, false, false, false, false, false]
	_dx7_lfo = -1
	for k in 2:
		_lfo_dx7[k] = bool((c.lfo[k] as Dictionary).get("dx7", false))
		if _lfo_dx7[k] and _dx7_lfo < 0:
			_dx7_lfo = k
	_carrier_envs = PackedInt64Array()
	_ops = false
	var all_own := true
	for o: Dictionary in c.osc:
		_ops = _ops or not (o.get("fm_src", PackedInt64Array()) as PackedInt64Array).is_empty() or float(o.get("feedback", 0.0)) != 0.0 \
			or float(o.get("ratio", 1.0)) != 1.0 or float(o.get("fixed_hz", 0.0)) > 0.0 or int(o.get("dx_mode", -1)) >= 0 \
			or int(o.get("level_env", -1)) >= 0 or float(o.get("vel_sens", 0.0)) > 0.0 or bool(o.get("ks", false)) \
			or int(o.get("shape_env", -1)) >= 0 or int(o.get("pitch_env", -1)) >= 0
		if float(o.level) != 0.0:
			var le := int(o.get("level_env", -1))
			if le < 0 or le >= _n_env:
				all_own = false
			elif not le in _carrier_envs:
				_carrier_envs.append(le)
	if not all_own:
		_carrier_envs = PackedInt64Array()
	for k in _n_env:
		var e: Dictionary = c.env[k]
		_env_kind[k] = int(e.get("kind", K_ADSR))
		if _env_kind[k] == K_STAGES:
			_env_kr[k] = exp(-1.0 / (float(e.r) * sr))
			continue
		if _env_kind[k] != K_ADSR:
			continue
		_env_a[k] = roundi(float(e.a) * sr)
		_env_d[k] = maxi(1, roundi(float(e.d) * sr))
		_env_s[k] = float(e.s)
		_env_kd[k] = exp(-1.0 / (float(e.d) * sr))
		_env_kr[k] = exp(-1.0 / (float(e.r) * sr))
		var r2 := float(e.get("r2", 0.0))
		_env_kr2[k] = exp(-1.0 / (r2 * sr)) if r2 > 0.0 else _env_kr[k]
		_env_knee[k] = float(e.get("knee", 0.0))
		_env_exp[k] = bool(e.exp)
	var lfos: Array = c.lfo
	_n_lfo = clampi(int(c.get("n_lfo", 2)), 2, mini(N_LFO, lfos.size()))
	for k in _n_lfo:
		var l: Dictionary = lfos[k]
		_lfo_shape[k] = int(l.shape)
		_lfo_pts[k] = l.get("points", PackedFloat64Array())
		_lfo_interp[k] = int(l.get("interp", 0))
		_lfo_once[k] = bool(l.get("once", false))
		if _lfo_shape[k] == 6 and (_lfo_pts[k] as PackedFloat64Array).size() < 2:
			_lfo_shape[k] = 0
		var beats := float(l.get("beats", 0.0))
		if beats != _lfo_beats[k]:
			# Newly synced (or unsynced): the free clock starts again at playback's start.
			_lfo_base[k] = 0.0
			_lfo_base_frame[k] = 0
		_lfo_beats[k] = beats
		_lfo_inc[k] = float(l.rate_hz) / sr if beats <= 0.0 else tempo_bpm / 60.0 / beats / sr
		_lfo_delay[k] = float(l.delay_s) * sr
		_lfo_width[k] = float(l.get("width", 0.5))
		_lfo_phase[k] = float(l.get("phase", 0.0))
		_lfo_free[k] = bool(l.get("free", false))
	_set_extras(c)
	_bypass = false
	for o: Dictionary in c.osc:
		_bypass = _bypass or not bool(o.get("filtered", true))
	var u := int(c.unison)
	_ratio.resize(MAX_U)
	for i in MAX_U:
		var spread := 0.0 if u == 1 else (float(i) / (u - 1) - 0.5) * 2.0
		_ratio[i] = pow(2.0, spread * float(c.detune_cents) / 1200.0)
	_uw.resize(MAX_U)
	var side := float(c.get("unison_level", 1.0))
	var power := 0.0
	for i in MAX_U:
		var mid := absf(float(i) - (u - 1) * 0.5) <= 0.5
		_uw[i] = 1.0 if mid or i >= u else side
		if i < u:
			power += _uw[i] * _uw[i]
	_inv_su = 1.0 / sqrt(power)
	_uwl.resize(MAX_U)
	_uwr.resize(MAX_U)
	var spr := float(c.get("spread", 0.0))
	_stereo = spr > 0.0
	for i in MAX_U:
		var p := 0.0 if u == 1 else spr * (float(i) / (u - 1) * 2.0 - 1.0)
		var ang := (p + 1.0) * PI * 0.25
		_uwl[i] = cos(ang) * sqrt(2.0) * _uw[i]
		_uwr[i] = sin(ang) * sqrt(2.0) * _uw[i]
	_slots(c, u)
	var oscs: Array = c.osc
	_opl.resize(oscs.size())
	_opr.resize(oscs.size())
	for j in oscs.size():
		var op := float(oscs[j].get("pan", 0.0))
		_stereo = _stereo or op != 0.0
		var ang := (op + 1.0) * PI * 0.25
		_opl[j] = 1.0 if op == 0.0 else cos(ang) * sqrt(2.0)
		_opr[j] = 1.0 if op == 0.0 else sin(ang) * sqrt(2.0)
	_tables = c.get("tables", [])
	_kg = exp(-float(CONTROL) / (float(c.glide_s) * sr)) if float(c.glide_s) > 0.0 else 0.0
	_kill_k = exp(-1.0 / (STEAL_FADE_S * sr))
	_vel_k = 1.0 - exp(-1.0 / (VEL_GLIDE_S * sr))
	_ctl_k = 1.0 - exp(-float(CONTROL) / (CTL_GLIDE_S * sr))
	var was_on := _arp_on
	_arp = c.get("arp", {})
	_arp_on = bool(_arp.get("on", false))
	if was_on and not _arp_on:
		_arp_stop()
	_retempo(tempo_bpm if _tempo_set else float(c.get("tempo_bpm", 120.0)))


## The newer per-patch numbers: voice slots and their slop, the ladder's output, the pre-filter, the comb.
func _set_extras(c: Dictionary) -> void:
	_slot_pan = c.get("voice_pan", PackedFloat64Array())
	_n_slot = clampi(int(c.get("slots", 0)), 0, 32)
	var sp := float(c.get("slop_pitch", 0.0))
	var sc := float(c.get("slop_cut", 0.0))
	var st := float(c.get("slop_time", 0.0))
	var sl := float(c.get("slop_level", 0.0))
	_slop_time = st > 0.0
	_sl_pitch.resize(_n_slot)
	_sl_cut.resize(_n_slot)
	_sl_gain.resize(_n_slot)
	_sl_tf.resize(_n_slot)
	var seed := int(c.get("seed", 0))
	for s in _n_slot:
		_sl_pitch[s] = sp * slot_rand(seed, s, 0)
		_sl_cut[s] = sc * slot_rand(seed, s, 1)
		_sl_tf[s] = 1.0 + st * slot_rand(seed, s, 2)
		_sl_gain[s] = db_to_linear(sl * slot_rand(seed, s, 3)) if sl > 0.0 else 1.0
	if _slot_pan.size() < _n_slot:
		_slot_pan = _slot_pan.duplicate()
		var was := _slot_pan.size()
		_slot_pan.resize(_n_slot)
		for s in range(was, _n_slot):
			_slot_pan[s] = 0.0
	var pm: PackedFloat64Array = c.get("pole_mix", PackedFloat64Array())
	_lpoles = float(c.get("poles", 4.0))
	_lmix = pm
	_lmode = 2 if pm.size() == 5 else (1 if _lpoles < 4.0 else 0)
	var lp := float(c.get("pre_lp_hz", 0.0))
	var hp := float(c.get("pre_hp_hz", 0.0))
	_pre_lp = 1.0 - exp(-TAU * minf(lp, 0.49 * sr) / sr) if lp > 0.0 else 0.0
	_pre_hp = 1.0 - exp(-TAU * minf(hp, 0.49 * sr) / sr) if hp > 0.0 else 0.0
	_comb_on = bool(c.get("comb_on", false))
	_inc_max = float(c.get("inc_max", 1e9))
	_bl_sync = bool(c.get("bl_sync", false))
	_sinc_blep = bool(c.get("sinc_blep", false))
	_f2 = c.get("f2", {})
	_f2_on = not _f2.is_empty() and int(_f2.get("filter_type", 0)) > 0
	_fb_on = bool(c.get("fb_on", false))
	_fb = float(c.get("fb", 0.0))
	_sat_tanh = bool(c.get("sat_tanh", false))
	_routing = int(c.get("routing", 0))
	var mac: PackedFloat64Array = c.get("macros", PackedFloat64Array())
	for i in 4:
		_macros[i] = mac[i] if i < mac.size() else 0.0
	_comb_semis = float(c.get("comb_semis", 0.0))
	_comb_fb = float(c.get("comb_fb", 0.0))


## A voice slot's fixed random offset k, -1..1, from the patch seed (the same numbers as the native engine).
static func slot_rand(seed: int, slot: int, k: int) -> float:
	var h := (seed * 2654435761 + slot * 40503 + k * 9973 + 12345) & 0xFFFFFFFF
	if h == 0:
		h = 0x9E3779B9
	for i in 3:
		h ^= (h << 13) & 0xFFFFFFFF
		h ^= h >> 17
		h ^= (h << 5) & 0xFFFFFFFF
	return float(h) / 4294967295.0 * 2.0 - 1.0


## A new tempo: synced LFOs keep their phase and change speed from here, and
## synced effects follow.
## Each oscillator's slots: its copies (`stack`, detuned across
## `stack_cents`) inside every unison voice, the odd unison voices raised by
## `unison_pitch`. With a stack of 1 and no unison pitch these are the unison
## voices' own ratios and weights, so older patches render as before.
func _slots(c: Dictionary, u: int) -> void:
	var oscs: Array = c.osc
	var upitch := float(c.get("unison_pitch", 0.0))
	var pf := pow(2.0, upitch / 12.0) if upitch != 0.0 else 1.0
	_sratio.resize(MAX_OSC * MAX_SLOT)
	_sw.resize(MAX_OSC * MAX_SLOT)
	_swl.resize(MAX_OSC * MAX_SLOT)
	_swr.resize(MAX_OSC * MAX_SLOT)
	_slot_n.resize(MAX_OSC)
	_slot_s.resize(MAX_OSC)
	_oinv.resize(MAX_OSC)
	_ormax.resize(MAX_OSC)
	_slot_n.fill(0)
	_slot_s.fill(1)
	for j in oscs.size():
		var sn := clampi(int(oscs[j].get("stack", 1)), 1, mini(MAX_STACK, MAX_SLOT / u))
		var sc := float(oscs[j].get("stack_cents", 0.0))
		_slot_s[j] = sn
		_slot_n[j] = u * sn
		_oinv[j] = _inv_su if sn == 1 else _inv_su / sqrt(float(sn))
		var rmax := 0.0
		for i in u:
			var r := _ratio[i]
			if pf != 1.0 and i % 2 == 1:
				r *= pf
			for s in sn:
				var k := j * MAX_SLOT + i * sn + s
				var rs := r
				if sn > 1:
					rs *= pow(2.0, (float(s) / (sn - 1) - 0.5) * 2.0 * sc / 1200.0)
				_sratio[k] = rs
				_sw[k] = _uw[i]
				_swl[k] = _uwl[i]
				_swr[k] = _uwr[i]
				rmax = maxf(rmax, rs)
		_ormax[j] = rmax
	# Slot k of oscillator j (unison voice k / stack, copy k % stack) reads the
	# same unison voice of oscillator r, and its copy if r has as many.
	_smap.resize(MAX_OSC * MAX_OSC * MAX_SLOT)
	for j in oscs.size():
		for r in oscs.size():
			var b := (j * MAX_OSC + r) * MAX_SLOT
			for k in _slot_n[j]:
				_smap[b + k] = k if _slot_s[r] == _slot_s[j] else (k / _slot_s[j]) * _slot_s[r] + (k % _slot_s[j]) % _slot_s[r]


func _retempo(bpm: float) -> void:
	tempo_bpm = clampf(bpm, 20.0, 400.0)
	for k in _n_lfo:
		if _lfo_beats[k] > 0.0:
			_lfo_base[k] += _lfo_inc[k] * float(frame - _lfo_base_frame[k])
			_lfo_base_frame[k] = frame
			_lfo_inc[k] = tempo_bpm / 60.0 / _lfo_beats[k] / sr
	if _fx:
		_fx.set_tempo(tempo_bpm)


func note_on(at: int, note: float, velocity := 1.0) -> void:
	_queue(at, E_ON, note, velocity)


func note_off(at: int, note: float) -> void:
	_queue(at, E_OFF, note, 0.0)


func set_bend(at: int, value: float) -> void:
	_queue(at, E_BEND, value, 0.0)


func set_mod_wheel(at: int, value: float) -> void:
	_queue(at, E_MOD, value, 0.0)


func set_aftertouch(at: int, value: float) -> void:
	_queue(at, E_TOUCH, value, 0.0)


## The sustain pedal down (true) or up.
func set_sustain(at: int, down: bool) -> void:
	_queue(at, E_SUSTAIN, 1.0 if down else 0.0, 0.0)


## Change the tempo (beats per minute): synced LFOs, delays and the
## arpeggiator follow from that frame. Overrides the patch's tempo_bpm.
func set_tempo(at: int, bpm: float) -> void:
	_queue(at, E_TEMPO, bpm, 0.0)


## Release every note (and lift the pedal).
func all_notes_off(at: int) -> void:
	_queue(at, E_ALL_OFF, 0.0, 0.0)


## Silence at once.
func panic(at: int) -> void:
	_queue(at, E_PANIC, 0.0, 0.0)


func voice_count() -> int:
	var n := 0
	for v in voices:
		if v.active:
			n += 1
	return n


## Render `n` frames: [l, r].
func render(n: int) -> Array:
	var l := PackedFloat32Array()
	var r := PackedFloat32Array()
	l.resize(n)
	r.resize(n)
	for i in n:
		while not _events.is_empty() and int(_events[0][0]) <= frame:
			var e: Array = _events.pop_front()
			_apply(int(e[2]), float(e[3]), float(e[4]))
		if _arp_on and not _arp_keys.is_empty():
			_arp_tick()
		var sl := 0.0
		var sr_ := 0.0
		for v in voices:
			if v.active:
				var y := v.tick(self)
				sl += y * v.gl
				sr_ += (v.yr if _stereo else y) * v.gr
		if _fx and not _fx.is_empty():
			_io[0] = sl
			_io[1] = sr_
			_fx.tick(_io)
			sl = _io[0]
			sr_ = _io[1]
		l[i] = sl
		r[i] = sr_
		frame += 1
	return [l, r]


# ------------------------------------------------------------------ events

func _queue(at: int, type: int, a: float, b: float) -> void:
	var e := [at, _seq, type, a, b]
	_seq += 1
	var i := _events.size()
	while i > 0 and int(_events[i - 1][0]) > at:
		i -= 1
	_events.insert(i, e)


func _apply(type: int, a: float, b: float) -> void:
	match type:
		E_ON:
			if _arp_on:
				_arp_key_on(a, b)
			else:
				_on(a, b)
		E_OFF:
			if _arp_on:
				_arp_key_off(a)
			else:
				_off(a)
		E_TEMPO:
			_tempo_set = true
			_retempo(a)
		E_BEND: bend = clampf(a, -1.0, 1.0)
		E_MOD: mod_wheel = clampf(a, 0.0, 1.0)
		E_TOUCH: aftertouch = clampf(a, 0.0, 1.0)
		E_ALL_OFF:
			_arp_stop()
			_held.clear()
			sustain = false
			for v in voices:
				if v.active and v.gated:
					v.release()
		E_SUSTAIN:
			sustain = a >= 0.5
			if not sustain:
				for v in voices:
					if v.active and v.pedal:
						v.release()
		E_PANIC:
			_arp_keys.clear()
			_arp_sounding = false
			_held.clear()
			for v in voices:
				v.active = false


## The held key that sounds (AKPatch.note_priority): the newest, the lowest or the highest.
func _pick_held() -> int:
	var prio := int(_p.get("prio", 0))
	var best := _held.size() - 1
	if prio == 0:
		return best
	for i in _held.size():
		var n := float(_held[i][0])
		if (prio == 1 and n < float(_held[best][0])) or (prio == 2 and n > float(_held[best][0])):
			best = i
	return best


func _on(note: float, vel: float) -> void:
	var mode := int(_p.mode)
	if mode != 0:
		var v := _mono_voice()
		_held.append([note, vel])
		var w := _pick_held()
		note = float(_held[w][0])
		vel = float(_held[w][1])
		if int(_p.get("prio", 0)) != 0 and v.active and v.gated and note == v.target:
			return   # the new key doesn't win: the sounding one carries on
		if v.active and v.gated:
			v.target = note
			v.vel = vel
			v.pedal = false
			if mode == 1:
				v.retrigger(bool(_p.get("rzero", false)))
			_last_note = note
			return
		if v.active and not v.killing:
			# Still ringing out: take the voice from where it is (envelopes
			# rise from their level, phases and filters carry on). Starting
			# it afresh would cut the tail in one sample: a click.
			v.target = note
			v.vel = vel
			v.pedal = false
			v.retrigger(bool(_p.get("rzero", false)))
			_last_note = note
			return
		var from := v.cur if v.active else _last_note
		v.slot = 0 if _n_slot > 0 else -1
		v.start(self, note, vel, from)
		_last_note = note
		return
	for v in voices:
		if v.active and v.gated and v.note == note:
			v.release()
	# Past the polyphony, the oldest voice fades out over a few ms (a stolen
	# voice doesn't click) while the new note starts in a free slot.
	var live := 0
	for w in voices:
		if w.active and not w.killing:
			live += 1
	var victim: _Voice = null
	if live >= int(_p.poly):
		victim = _steal()
		victim.kill()
	var v: _Voice = null
	for w in voices:
		if not w.active:
			v = w
			break
	if v == null:
		if voices.size() < 2 * int(_p.poly):
			v = _Voice.new()
			voices.append(v)
		else:
			v = victim if victim else _steal()
	v.slot = -1
	if _n_slot > 0:
		v.slot = _rr % _n_slot
		_rr += 1
	v.start(self, note, vel, _last_note)
	_last_note = note


# The pedal holds a released note unless `pedal` is false (the arpeggiator's own note-offs).
func _off(note: float, pedal := true) -> void:
	var mode := int(_p.mode)
	if mode != 0:
		var top := -1.0 if _held.is_empty() else float(_held[_pick_held()][0])
		for i in range(_held.size() - 1, -1, -1):
			if float(_held[i][0]) == note:
				_held.remove_at(i)
		if voices.is_empty() or not voices[0].active:
			return
		var v := voices[0]
		if _held.is_empty():
			if sustain and pedal:
				v.pedal = true
			else:
				v.release()
		elif note == top:
			v.target = float(_held[_pick_held()][0])
			_last_note = v.target
		return
	for v in voices:
		if v.active and v.gated and v.note == note:
			if sustain and pedal:
				v.pedal = true
			else:
				v.release()


# ------------------------------------------------------------------ arpeggiator

func _arp_key_on(note: float, vel: float) -> void:
	var first := _arp_keys.is_empty()
	var i := 0
	while i < _arp_keys.size() and float(_arp_keys[i][0]) < note:
		i += 1
	if i < _arp_keys.size() and float(_arp_keys[i][0]) == note:
		_arp_keys[i][1] = vel
	else:
		_arp_keys.insert(i, [note, vel])
	if first:
		# The first key starts the pattern: its first step plays on this sample.
		_arp_pos = 0.0
		_arp_next = 0.0
		_arp_gate_at = -1.0
		_arp_step = 0
		_arp_starts += 1
		_arp_rng = ((int(_p.get("seed", 0)) * 2654435761 + _arp_starts * 40503) & 0xFFFFFFFF) | 1


func _arp_key_off(note: float) -> void:
	for i in _arp_keys.size():
		if float(_arp_keys[i][0]) == note:
			_arp_keys.remove_at(i)
			break
	if _arp_keys.is_empty() and _arp_sounding:
		_off(_arp_cur, false)
		_arp_sounding = false


func _arp_stop() -> void:
	_arp_keys.clear()
	if _arp_sounding:
		_off(_arp_cur, false)
		_arp_sounding = false


## One sample of the arpeggiator: the gate closes, a step plays, the clock moves on.
func _arp_tick() -> void:
	if _arp_sounding and _arp_gate_at >= 0.0 and _arp_pos >= _arp_gate_at:
		_off(_arp_cur, false)
		_arp_sounding = false
		_arp_gate_at = -1.0
	if _arp_pos >= _arp_next:
		_arp_fire()
		_arp_next += float(_arp.beats)
	_arp_pos += tempo_bpm / 60.0 / sr


func _arp_fire() -> void:
	var nk := _arp_keys.size()
	var n := nk * int(_arp.octaves)
	var i := 0
	match int(_arp.mode):
		0:
			i = _arp_step % n
		1:
			i = n - 1 - _arp_step % n
		2:
			if n > 1:
				var p := _arp_step % (2 * n - 2)
				i = p if p < n else 2 * n - 2 - p
		3:
			_arp_rng ^= (_arp_rng << 13) & 0xFFFFFFFF
			_arp_rng ^= _arp_rng >> 17
			_arp_rng ^= (_arp_rng << 5) & 0xFFFFFFFF
			i = _arp_rng % n
	var key: Array = _arp_keys[i % nk]
	var note := float(key[0]) + 12.0 * float(i / nk)
	var vel := float(key[1])
	var gate := float(_arp.gate)
	if gate >= 1.0:
		# Tied: the new note starts before the old one ends (legato, glide).
		_on(note, vel)
		if _arp_sounding and _arp_cur != note:
			_off(_arp_cur, false)
		_arp_gate_at = -1.0
	else:
		if _arp_sounding:
			_off(_arp_cur, false)
		_on(note, vel)
		_arp_gate_at = _arp_next + float(_arp.beats) * gate
	_arp_cur = note
	_arp_sounding = true
	_arp_step += 1


func _mono_voice() -> _Voice:
	if voices.is_empty():
		voices.append(_Voice.new())
	return voices[0]


## The voice to replace when all are busy: the oldest releasing one, else
## the oldest.
func _steal() -> _Voice:
	var best: _Voice = null
	for v in voices:
		if v.active and not v.killing and not v.gated and (best == null or v.serial < best.serial):
			best = v
	if best:
		return best
	for v in voices:
		if v.active and not v.killing and (best == null or v.serial < best.serial):
			best = v
	return best


func _next_serial() -> int:
	_serial += 1
	return _serial


## The key_levels gain at a key: [key, gain, ...] joined by straight lines in
## dB, flat past the ends.
static func key_level(kl: PackedFloat64Array, key: float) -> float:
	var n := kl.size() / 2
	if key <= kl[0] or n == 1:
		return kl[1]
	for i in range(1, n):
		if key < kl[2 * i]:
			var t := (key - kl[2 * i - 2]) / (kl[2 * i] - kl[2 * i - 2])
			return kl[2 * i - 1] * pow(kl[2 * i + 1] / kl[2 * i - 1], t)
	return kl[2 * n - 1]


static func _blep(t: float, dt: float) -> float:
	if dt <= 0.0:
		return 0.0
	if t < dt:
		var x := t / dt
		return x + x - x * x - 1.0
	if t > 1.0 - dt:
		var x := (t - 1.0) / dt
		return x * x + x + x + 1.0
	return 0.0


const BLEP_N := 8
const BLEP_RES := 256
const BLEP_SUB := 8
const BLEP_CUT := 0.9
static var _blep_tab := PackedFloat64Array()


## The windowed-sinc BLEP's table (AKPatch.sinc_blep; the native ak::blep_table): the band-limited
## step's smooth part 2 C(x) - 1 at x = -N + i / RES, C the integral of a Blackman-windowed sinc
## (cut at 0.9 of Nyquist) over 8 samples each side, by the trapezoid rule on RES * SUB steps per sample.
static func _blep_table() -> PackedFloat64Array:
	if not _blep_tab.is_empty():
		return _blep_tab
	var fine := 2 * BLEP_N * BLEP_RES * BLEP_SUB
	var h := 1.0 / (BLEP_RES * BLEP_SUB)
	var c := PackedFloat64Array()
	c.resize(fine + 1)
	c[0] = 0.0
	var prev := 0.0
	for j in range(fine + 1):
		var x := (j - BLEP_N * BLEP_RES * BLEP_SUB) * h
		var s := 1.0 if x == 0.0 else sin(PI * BLEP_CUT * x) / (PI * BLEP_CUT * x)
		var k := s * (0.42 + 0.5 * cos(PI * x / BLEP_N) + 0.08 * cos(2.0 * PI * x / BLEP_N))
		if j > 0:
			c[j] = c[j - 1] + (prev + k) * 0.5 * h
		prev = k
	var total := c[fine]
	var t := PackedFloat64Array()
	t.resize(2 * BLEP_N * BLEP_RES + 1)
	for i in range(t.size()):
		t[i] = 2.0 * c[i * BLEP_SUB] / total - 1.0
	_blep_tab = t
	return t


## The windowed-sinc BLEP's residual at phase t (the same sign convention as _blep), summed
## over every discontinuity within reach.
static func _blep_sinc(t: float, dt: float) -> float:
	if dt <= 0.0:
		return 0.0
	var w := BLEP_N * dt
	if t >= w and t <= 1.0 - w:
		return 0.0
	var tab := _blep_table()
	var r := 0.0
	for m in range(ceili(t - w), floori(t + w) + 1):
		var x := (t - m) / dt
		if x <= -BLEP_N or x >= BLEP_N:
			continue
		var u := (x + BLEP_N) * BLEP_RES
		var i := mini(int(u), 2 * BLEP_N * BLEP_RES - 1)
		var f := u - i
		r += tab[i] + (tab[i + 1] - tab[i]) * f + (1.0 if x < 0.0 else -1.0)
	return r


## A wavetable read: frames blended by `pos`, band-limit level `lv`, linear
## between samples; `zone` picks a key zone's frames.
static func _table(t: Dictionary, pos: float, lv: int, ph: float, zone: int = 0) -> float:
	var data: PackedFloat32Array = t.data
	var n: int = t.size
	var frames: int = t.frames
	var levels: int = t.levels
	var lv0: int = t.get("lv0", 0)
	lv = clampi(lv, lv0, lv0 + levels - 1) - lv0
	var fp := pos * (frames - 1)
	var f0 := mini(frames - 1, floori(fp))
	var ff := fp - f0
	var x := ph * n
	var i0 := int(x)
	var fr := x - i0
	var i1 := (i0 + 1) % n
	i0 = i0 % n
	f0 += zone * frames
	frames += zone * frames
	var b0 := (f0 * levels + lv) * n
	var v := data[b0 + i0] * (1.0 - fr) + data[b0 + i1] * fr
	if ff > 0.0 and f0 + 1 < frames:
		var b1 := ((f0 + 1) * levels + lv) * n
		var v1 := data[b1 + i0] * (1.0 - fr) + data[b1 + i1] * fr
		v = v * (1.0 - ff) + v1 * ff
	return v


## An oscillator's plain (not band-limited) value at phase q: what a band-limited sync
## reset jumps between.
static func _naive(shape: int, q: float, width: float, pos: float, tab: Dictionary, mip: int, zone: int, zw: float) -> float:
	if shape == SH_SINE:
		return sin(TAU * q)
	if shape == SH_MORPH:
		var p3 := pos * 3.0
		var a := mini(2, floori(p3))
		var w := p3 - a
		var x := _shape(a, q, 0.0, 0.5)
		if w > 0.0:
			x = x * (1.0 - w) + _shape(a + 1, q, 0.0, 0.5) * w
		return x
	if shape == SH_TABLE:
		if tab.is_empty():
			return 0.0
		var x := _table(tab, pos, mip, q, zone)
		if zw > 0.0:
			x += (_table(tab, pos, mip, q, zone + 1) - x) * zw
		return x
	return _shape(shape, q, 0.0, width if shape == SH_PULSE else 0.5)


static func _shape(shape: int, ph: float, dt: float, width: float, sinc := false) -> float:
	match shape:
		SH_SINE:
			return sin(TAU * ph)
		SH_TRI:
			return 1.0 - 4.0 * absf(ph - 0.5)
		SH_SAW:
			return 2.0 * ph - 1.0 - (_blep_sinc(ph, dt) if sinc else _blep(ph, dt))
		_:
			var v := 1.0 if ph < width else -1.0
			var p2 := ph - width
			p2 -= floorf(p2)
			if sinc:
				return v + _blep_sinc(ph, dt) - _blep_sinc(p2, dt)
			v += _blep(ph, dt)
			return v - _blep(p2, dt)


## msfa's per-rate tables (Freqlut::init, Lfo::init, PitchEnv::init) and its sine table (Sin::init).
func _dx7_tables() -> void:
	if _freqlut.size() == 1025 and _lfo_unit == int(64 * 25190424 / float(sr) + 0.5):
		return
	_freqlut.resize(1025)
	var y := float(1 << 44) / sr
	var inc := pow(2.0, 1.0 / 1024.0)
	for i in 1025:
		_freqlut[i] = int(floorf(y + 0.5))
		y *= inc
	_lfo_unit = int(64 * 25190424 / float(sr) + 0.5)
	_lfo_ratio = int(4437500000.0 * 64 / sr)
	_penv_unit = int(64 * (1 << 24) / (21.3 * sr) + 0.5)
	if _sintab.is_empty():
		_sintab.resize(2048)
		var dphase := 2.0 * PI / 1024.0
		var cc := int(floorf(cos(dphase) * (1 << 30) + 0.5))
		var ss := int(floorf(sin(dphase) * (1 << 30) + 0.5))
		var u := 1 << 30
		var v := 0
		for i in 512:
			_sintab[(i << 1) + 1] = (v + 32) >> 6
			_sintab[((i + 512) << 1) + 1] = -((v + 32) >> 6)
			var t := (u * ss + v * cc + (1 << 29)) >> 30
			u = (u * cc - v * ss + (1 << 29)) >> 30
			v = t
		for i in 1023:
			_sintab[i << 1] = _sintab[(i << 1) + 3] - _sintab[(i << 1) + 1]
		_sintab[2046] = -_sintab[2047]


## msfa's Freqlut::lookup: Q24 log frequency (1 = an octave) to a Q24 phase increment.
func freqlut(logfreq: int) -> int:
	var ix := (logfreq & 0xffffff) >> 14
	var y0 := _freqlut[ix]
	var y1 := _freqlut[ix + 1]
	var y := y0 + (((y1 - y0) * (logfreq & 0x3fff)) >> 14)
	return y >> (20 - (logfreq >> 24))


## msfa's Sin::lookup (Q24 phase, Q24 out).
static func dx7_sin(phase: int) -> int:
	var pi_ := (phase >> 13) & 2046
	return _sintab[pi_ + 1] + ((_sintab[pi_] * (phase & 0x3fff)) >> 14)


## Dx7Note::compute's amp modulation: how far an operator's Q24 envelope level
## drops for the LFO's amp modulation `amd` at sensitivity `ams` (1..3).
static func dx7_amp_mod(lq: int, amd: int, ams: int) -> int:
	var sensamp := (amd * DX7_AMS[ams]) >> 24
	var pt := int(exp(_f32(float(sensamp)) / 262144.0 * 0.07 + 12.2)) & 0xFFFFFFFF
	return (lq * (pt << 4)) >> 28


## msfa's sine table read in float (a dx7 operator's sine, as msfa's
## Sin::lookup): `q` in cycles, linear between the table's 1024 points.
static func dx7_sinf(q: float) -> float:
	q -= floorf(q)
	var x := q * 1024.0
	var i := mini(1023, int(x))
	return (float(_sintab[(i << 1) + 1]) + float(_sintab[i << 1]) * (x - i)) / 16777216.0


## A float rounded to single precision, as msfa's (float) casts.
static func _f32(x: float) -> float:
	return PackedFloat32Array([x])[0]


## msfa's Dx7Note::osc_freq with standard tuning: an operator's Q24 log frequency.
static func dx7_osc_logfreq(midinote: int, mode: int, coarse: int, fine: int, detune: int) -> int:
	var logfreq := 0
	if mode == 0:
		logfreq = 50857777 + ((1 << 24) / 12) * midinote
		var detune_ratio := 0.0209 * exp(-0.396 * (_f32(float(logfreq)) / float(1 << 24))) / 7.0
		logfreq = int(float(logfreq) + detune_ratio * float(logfreq) * float(detune - 7))
		logfreq += DX7_COARSE[coarse & 31]
		if fine != 0:
			logfreq += int(floorf(24204406.323123 * log(1.0 + 0.01 * fine) + 0.5))
	else:
		logfreq = (4458616 * ((coarse & 3) * 100 + fine)) >> 3
		logfreq += 13457 * (detune - 7) if detune > 7 else 0
	return logfreq


## msfa's Env::scaleoutlevel.
static func dx7_scale_out(ol: int) -> int:
	return 28 + ol if ol >= 20 else DX7_LEVELLUT[ol]


## msfa's ScaleCurve.
static func _dx7_curve(group: int, depth: int, curve: int) -> int:
	var scale := 0
	if curve == 0 or curve == 3:
		scale = (group * depth * 329) >> 12
	else:
		scale = (DX7_EXP_SCALE[mini(group, DX7_EXP_SCALE.size() - 1)] * depth * 329) >> 15
	return -scale if curve < 2 else scale


## A dx7 envelope's outlevel for a note (msfa's Dx7Note::init: output level,
## keyboard level scaling, velocity), in microsteps.
static func dx7_outlevel(e: Dictionary, midinote: int, midivel: int) -> int:
	var ol := dx7_scale_out(int(e.ol))
	var offset := midinote - int(e.bp) - 17
	if offset >= 0:
		ol += _dx7_curve((offset + 1) / 3, int(e.rd), int(e.rc))
	else:
		ol += _dx7_curve(-(offset - 1) / 3, int(e.ld), int(e.lc))
	ol = mini(127, ol) << 5
	var vel_value: int = DX7_VELOCITY[clampi(midivel, 0, 127) >> 1] - 239
	ol += ((int(e.vs) * vel_value + 7) >> 3) << 4
	return maxi(0, ol)


## msfa's ScaleRate: the rate offset (qRate units) for a note.
static func dx7_rate_scaling(e: Dictionary, midinote: int) -> int:
	return (int(e.rs) * mini(31, maxi(0, midinote / 3 - 7))) >> 3


## How long a dx7 envelope's release takes, from its loudest level at the
## slowest key (no rate scaling), at full output: the bake's tail.
static func dx7_release_s(e: Dictionary, sample_rate := 48000) -> float:
	var st := _Dx7.new()
	st.srm = int(44100.0 / sample_rate * 16777216.0)
	st.outlevel = dx7_outlevel({ol = 99, bp = 0, ld = 0, rd = 0, lc = 0, rc = 0, vs = 0}, 0, 127)
	var lv: PackedInt64Array = e.levels
	var top := maxi(maxi(lv[0], lv[1]), maxi(lv[2], lv[3]))
	var actual := maxi(16, ((dx7_scale_out(top) >> 1) << 6) + st.outlevel - 4256)
	st.level = actual << 16
	st.down = false
	st.advance(e, 3)
	var blocks := 0
	while st.ix < 4 and blocks < 1000000:
		st.getsample(e)
		blocks += 1
	return float(blocks * DX7_N) / sample_rate


## msfa's Env (env.cc, ACCURATE_ENVELOPE), the state of one envelope. The
## integer steps are msfa's, so its levels come out exactly.
class _Dx7:
	var level := 0
	var target := 0
	var rising := false
	var ix := 0
	var inc := 0
	var staticcount := 0
	var down := true
	var outlevel := 0
	var rate_scaling := 0
	var srm := 0

	func advance(e: Dictionary, newix: int) -> void:
		ix = newix
		if ix >= 4:
			return
		var lv: PackedInt64Array = e.levels
		var rt: PackedInt64Array = e.rates
		var newlevel := lv[ix]
		var actual := (AKSynthCore.dx7_scale_out(newlevel) >> 1)
		actual = (actual << 6) + outlevel - 4256
		actual = maxi(16, actual)
		target = actual << 16
		rising = target > level
		var qrate := (rt[ix] * 41) >> 6
		qrate = mini(qrate + rate_scaling, 63)
		if target == level or (ix == 0 and newlevel == 0):
			var staticrate := mini(rt[ix] + rate_scaling, 99)
			staticcount = AKSynthCore.DX7_STATICS[staticrate] if staticrate < 77 else 20 * (99 - staticrate)
			if staticrate < 77 and ix == 0 and newlevel == 0:
				staticcount /= 20
			staticcount = (staticcount * srm) >> 24
		else:
			staticcount = 0
		inc = (4 + (qrate & 3)) << (2 + 6 + (qrate >> 2))
		inc = (inc * srm) >> 24

	func getsample(e: Dictionary) -> int:
		if staticcount != 0:
			staticcount -= AKSynthCore.DX7_N
			if staticcount <= 0:
				staticcount = 0
				advance(e, ix + 1)
		if ix < 3 or (ix < 4 and not down):
			if staticcount != 0:
				pass
			elif rising:
				if level < (1716 << 16):
					level = 1716 << 16
				level += (((17 << 24) - level) >> 24) * inc
				if level >= target:
					level = target
					advance(e, ix + 1)
			else:
				level -= inc
				if level <= target:
					level = target
					advance(e, ix + 1)
		return level


## msfa's PitchEnv (pitchenv.cc): Q24 log pitch (1 = an octave), per 64-sample block.
class _Dx7P:
	var level := 0
	var target := 0
	var rising := false
	var ix := 0
	var inc := 0
	var down := true
	var unit := 0

	func set_up(e: Dictionary) -> void:
		level = AKSynthCore.DX7_PENV_TAB[(e.levels as PackedInt64Array)[3]] << 19
		down = true
		advance(e, 0)

	func advance(e: Dictionary, newix: int) -> void:
		ix = newix
		if ix < 4:
			target = AKSynthCore.DX7_PENV_TAB[(e.levels as PackedInt64Array)[ix]] << 19
			rising = target > level
			inc = AKSynthCore.DX7_PENV_RATE[(e.rates as PackedInt64Array)[ix]] * unit

	func getsample(e: Dictionary) -> int:
		if ix < 3 or (ix < 4 and not down):
			if rising:
				level += inc
				if level >= target:
					level = target
					advance(e, ix + 1)
			else:
				level -= inc
				if level <= target:
					level = target
					advance(e, ix + 1)
		return level


## msfa's Lfo (lfo.cc) and Dx7Note's use of it: per 64-sample block, the
## pitch modulation (Q24 log) and the amp modulation for dx7 envelopes.
class _Dx7Lfo:
	var phase := 0
	var delta := 0
	var rand := 0
	var dstate := 0
	var dinc := 0
	var dinc2 := 0
	var pitch_mod := 0
	var amd := 0
	## The last block's wave value and delay ramp (Q24), for checks.
	var value := 0
	var delay_q24 := 0

	func reset(core: AKSynthCore, l: Dictionary) -> void:
		phase = 0
		rand = 0
		delta = int(AKSynthCore.DX7_LFO_SPEED[int(l.speed)] * core._lfo_ratio) & 0xFFFFFFFF
		var a := 99 - int(l.delay)
		if a == 99:
			dinc = 0xFFFFFFFF
			dinc2 = 0xFFFFFFFF
		else:
			a = (16 + (a & 15)) << (1 + (a >> 4))
			dinc = (core._lfo_unit * a) & 0xFFFFFFFF
			a &= 0xff80
			a = maxi(0x80, a)
			dinc2 = (core._lfo_unit * a) & 0xFFFFFFFF
		if bool(l.sync):
			phase = (1 << 31) - 1
		dstate = 0
		pitch_mod = 0
		amd = 0

	func getsample(wave: int) -> int:
		phase = (phase + delta) & 0xFFFFFFFF
		match wave:
			0:
				var x := phase >> 7
				if (phase >> 31) != 0:
					x = ~x
				return x & ((1 << 24) - 1)
			1:
				return ((~phase & 0xFFFFFFFF) ^ (1 << 31)) >> 8
			2:
				return (phase ^ (1 << 31)) >> 8
			3:
				return ((~phase & 0xFFFFFFFF) >> 7) & (1 << 24)
			4:
				return (1 << 23) + (AKSynthCore.dx7_sin(phase >> 8) >> 1)
			_:
				if phase < delta:
					rand = (rand * 179 + 17) & 0xff
				return ((rand ^ 0x80) + 1) << 16

	func getdelay() -> int:
		var d := dstate + (dinc if dstate < (1 << 31) else dinc2)
		if d > 0xFFFFFFFF:
			return 1 << 24
		dstate = d
		if d < (1 << 31):
			return 0
		return (d >> 7) & ((1 << 24) - 1)

	## One block: Dx7Note::compute's pitch and amp modulation (no controllers).
	func step(l: Dictionary) -> void:
		var lv := getsample(int(l.wave))
		var ld := getdelay()
		value = lv
		delay_q24 = ld
		var pmd := (((int(l.pmd) * 165) >> 6) * ld) & 0xFFFFFFFF
		var senslfo := AKSynthCore.DX7_PMS[int(l.pms)] * (lv - (1 << 23))
		var p1 := absi((pmd * senslfo) >> 39)
		pitch_mod = -p1 if senslfo < 0 else p1
		var a1 := ((((int(l.amd) * 165) >> 6) * ld) >> 8) & 0xFFFFFFFF
		amd = ((a1 * ((1 << 24) - lv)) >> 24) & 0xFFFFFFFF


## One voice of the engine.
## One voice filter's state and coefficients (filter 2; ak::FiltState, whose filter 1 _Voice runs
## inline): the same arithmetic, on a compiled filter (AKPatch._compile_filt).
class _Filt:
	var ic1 := PackedFloat64Array([0.0, 0.0])
	var ic2 := PackedFloat64Array([0.0, 0.0])
	var ic1r := PackedFloat64Array([0.0, 0.0])
	var ic2r := PackedFloat64Array([0.0, 0.0])
	var lad := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var last_c := -1.0
	var last_q := -1.0
	var fk := 1.0
	var a1 := 0.0
	var a2 := 0.0
	var a3 := 0.0
	var lg := 0.0
	var lG := 0.0
	var lbeta := 0.0
	var lk := 0.0
	var sm0 := 0.0
	var sm1 := 0.0
	var sm2 := 0.0
	## The comb type: its line (left, right), write positions, period and feedback.
	var cb := PackedFloat64Array()
	var cbw := PackedInt64Array([0, 0])
	var cbper := 1.0
	var cbfb := 0.0

	func reset() -> void:
		if not cb.is_empty():
			cb.fill(0.0)
		cbw.fill(0)
		ic1.fill(0.0)
		ic2.fill(0.0)
		ic1r.fill(0.0)
		ic2r.fill(0.0)
		lad.fill(0.0)
		last_c = -1.0
		last_q = -1.0

	func control(f: Dictionary, m_cut: float, m_q: float, sr: float) -> void:
		var ft := int(f.filter_type)
		if ft == F_COMB:
			if cb.size() != 2 * COMB_MAX:
				cb.resize(2 * COMB_MAX)
				cb.fill(0.0)
			var ccut := float(f.cutoff_hz)
			if m_cut != 0.0:
				ccut *= pow(2.0, m_cut)
			cbper = clampf(sr / maxf(ccut, 1.0), 1.0, float(COMB_MAX - 2))
			var cfb0 := float(f.get("cfb", 0.5))
			cbfb = cfb0 if m_q == 0.0 else clampf(cfb0 * pow(2.0, m_q), -0.99, 0.99)
			return
		if ft == F_LADDER:
			var cut := float(f.cutoff_hz)
			if m_cut != 0.0:
				cut *= pow(2.0, m_cut)
			var res := float(f.resonance)
			if m_q != 0.0:
				res = clampf(res * pow(2.0, m_q), 0.0, 1.2)
			if cut != last_c or res != last_q:
				last_c = cut
				last_q = res
				lg = tan(PI * clampf(cut, 10.0, 0.49 * sr) / sr)
				lG = lg / (1.0 + lg)
				lbeta = 1.0 / (1.0 + lg)
				lk = 4.0 * res
		elif ft > 0:
			var cut := float(f.cutoff_hz)
			if m_cut != 0.0:
				cut *= pow(2.0, m_cut)
			var q := float(f.q)
			if m_q != 0.0:
				q *= pow(2.0, m_q)
			if cut != last_c or q != last_q:
				last_c = cut
				last_q = q
				fk = 1.0 / maxf(0.05, q)
				var g := tan(PI * clampf(cut, 10.0, 0.49 * sr) / sr)
				if ft >= F_MIX:
					var a := pow(10.0, float(f.gain_db) / 40.0)
					match ft:
						F_MIX:
							var hi := float(f.f_high)
							sm0 = hi
							sm1 = float(f.f_band) - fk * hi
							sm2 = float(f.f_low) - hi
						F_LSHELF:
							g /= sqrt(a)
							sm0 = 1.0
							sm1 = fk * (a - 1.0)
							sm2 = a * a - 1.0
						F_HSHELF:
							g *= sqrt(a)
							sm0 = a * a
							sm1 = fk * (1.0 - a) * a
							sm2 = 1.0 - a * a
						F_ALLPASS:
							sm0 = 1.0
							sm1 = -2.0 * fk
							sm2 = 0.0
						_:
							fk /= a
							sm0 = 1.0
							sm1 = fk * (a * a - 1.0)
							sm2 = 0.0
				a1 = 1.0 / (1.0 + g * (g + fk))
				a2 = g * a1
				a3 = g * a2

	func tick(f: Dictionary, y: float, right: bool) -> float:
		var ft := int(f.filter_type)
		if ft == F_LADDER:
			return _ladder(f, y, 4 if right else 0)
		if ft == F_COMB:
			if cb.is_empty():
				return y
			var ch := 1 if right else 0
			var base := ch * COMB_MAX
			var rp := float(cbw[ch]) - cbper
			if rp < 0.0:
				rp += float(COMB_MAX)
			var i := floori(rp)
			var fr := rp - float(i)
			var a := cb[base + i]
			var b := cb[base + (i + 1) % COMB_MAX]
			var out := y + cbfb * (a + (b - a) * fr)
			cb[base + cbw[ch]] = out
			cbw[ch] = (cbw[ch] + 1) % COMB_MAX
			return out
		if ft <= 0:
			return y
		for s in int(f.stages):
			var i1: float = ic1r[s] if right else ic1[s]
			var i2: float = ic2r[s] if right else ic2[s]
			var v3 := y - i2
			var v1 := a1 * i1 + a2 * v3
			var v2 := i2 + a2 * i1 + a3 * v3
			if right:
				ic1r[s] = 2.0 * v1 - i1
				ic2r[s] = 2.0 * v2 - i2
			else:
				ic1[s] = 2.0 * v1 - i1
				ic2[s] = 2.0 * v2 - i2
			match ft:
				1: y = v2
				2: y = y - fk * v1 - v2
				3: y = v1
				4: y = y - fk * v1
				_: y = sm0 * y + sm1 * v1 + sm2 * v2
		return y

	func _ladder(f: Dictionary, x: float, s0: int) -> float:
		var G := lG
		var b := lbeta
		var S := G * G * G * b * lad[s0] + G * G * b * lad[s0 + 1] + G * b * lad[s0 + 2] + b * lad[s0 + 3]
		var drive := float(f.drive)
		var u := (x - lk * S) / (1.0 + lk * G * G * G * G)
		u = tanh(u * drive * 0.5) * 2.0 / drive
		var ys := PackedFloat64Array([u, 0.0, 0.0, 0.0, 0.0])
		for i in 4:
			var v := (u - lad[s0 + i]) * G
			var yy := v + lad[s0 + i]
			lad[s0 + i] = yy + v
			u = yy
			ys[i + 1] = u
		var lm := int(f.lmode)
		if lm == 0:
			return u * (1.0 + 0.5 * lk)
		var out := 0.0
		if lm == 2:
			var m: PackedFloat64Array = f.pole_mix
			out = m[0] * ys[0] + m[1] * ys[1] + m[2] * ys[2] + m[3] * ys[3] + m[4] * ys[4]
		else:
			var p := float(f.poles)
			var lo := floori(p)
			var w := p - float(lo)
			out = ys[lo] if w == 0.0 else ys[lo] * (1.0 - w) + ys[lo + 1] * w
		return out * (1.0 + 0.5 * lk)


class _Voice:
	var active := false
	var gated := false
	## Held only by the sustain pedal.
	var pedal := false
	## Stolen: fading out fast.
	var killing := false
	var serial := 0
	var note := 60.0
	var target := 60.0
	var cur := 60.0
	var vel := 1.0
	## The velocity as heard: follows vel over VEL_GLIDE_S.
	var gvel := 1.0
	## The mod wheel and aftertouch as heard: follow the core's over CTL_GLIDE_S.
	var gmod := 0.0
	var gtouch := 0.0
	var rnd := 0.0
	var rng := 1
	## lfo3 .. lfo8's own random streams (random and smooth shapes), so adding one leaves the
	## voice's stream (lfo1, lfo2, the random source, noise) as it was.
	var lrng := PackedInt64Array([1, 1, 1, 1, 1, 1, 1, 1])
	## cz envelopes: the chip's current value and target (its own units), rate per 40 kHz
	## sample, step, direction (down) and whether the key-off has been taken.
	var czc := PackedFloat64Array([0, 0, 0, 0, 0, 0, 0, 0])
	var czt := PackedFloat64Array([0, 0, 0, 0, 0, 0, 0, 0])
	var czr := PackedFloat64Array([0, 0, 0, 0, 0, 0, 0, 0])
	var czi := PackedInt64Array([0, 0, 0, 0, 0, 0, 0, 0])
	var czd := PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0])
	var czrel := PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0])
	## pd oscillators: each slot's wave of the two, the noise modulation's clock and factor.
	var pdb := PackedByteArray()
	var pdn_t := PackedFloat64Array()
	var pdn_m := PackedFloat64Array()
	var gl := 1.0
	var gr := 1.0
	var stage := PackedInt64Array([4, 4, 4, 4, 4, 4, 4, 4])
	var t := PackedInt64Array([0, 0, 0, 0, 0, 0, 0, 0])
	var level := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var start_level := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var rel_from := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])  # each envelope's level at key-up
	var ev := PackedFloat64Array([1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0])
	## How many envelopes this voice runs (the patch's, when it started).
	var ne := 3
	## A key change waiting for a stages or dx7 envelope's next tick: 1 retrigger, 2 release.
	var pend := PackedInt64Array([0, 0, 0, 0, 0, 0, 0, 0])
	# Stages envelopes: the stage, its length (or ST_HOLD, ST_FALL), the level it
	# left from and goes to, the power curve's running exponential, its step and
	# denominator (0: straight), and this note's time and level factors.
	var si := PackedInt64Array([0, 0, 0, 0, 0, 0, 0, 0])
	var sn := PackedInt64Array([0, 0, 0, 0, 0, 0, 0, 0])
	var sfrom := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var sto := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var sg := PackedFloat64Array([1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0])
	var sk := PackedFloat64Array([1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0])
	var sden := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var tkf := PackedFloat64Array([1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0])
	var tvf := PackedFloat64Array([1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0])
	var lsc := PackedFloat64Array([1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0])
	# dx7 envelopes: msfa's state, the gains at the last two block steps, and
	# whether it has finished (released to level 4 = 0: silent from the next block).
	var dx: Array[_Dx7] = []
	var dg1 := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var dg2 := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var dead := PackedInt64Array([0, 0, 0, 0, 0, 0, 0, 0])
	## A dx7 envelope's block is below msfa's gain threshold: silent.
	var dq := PackedInt64Array([0, 0, 0, 0, 0, 0, 0, 0])
	var dxp: Array[_Dx7P] = []
	var dlfo: Array[_Dx7Lfo] = []
	## Each oscillator's output two samples back (feedback averages the last two).
	var fbp := PackedFloat64Array()
	## Per oscillator: the level factor from velocity_sens and key_scaling, and
	## a dx7 operator's key and Q24 log frequency for it.
	var o_kv := PackedFloat64Array()
	var o_dxnote := PackedInt64Array()
	var o_dxbase := PackedInt64Array()
	var o_inc := PackedFloat64Array()
	var lfo_ph := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var lfo_sh := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	## Smooth random: the value each cycle starts from (lfo_sh is where it goes).
	var lfo_sh0 := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	## The matrix's push on each LFO's rate, in octaves (from the last control step).
	var lfo_oct := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	## A one-shot custom LFO has run its cycle.
	var lfo_done := PackedInt64Array([0, 0, 0, 0, 0, 0, 0, 0])
	## The voice slot (-1: none) and its pan, pitch, cutoff, gain and envelope time factor.
	var slot := -1
	var s_pan := 0.0
	var s_pitch := 0.0
	var s_cut := 0.0
	var s_gain := 1.0
	var s_tf := 1.0
	## ADSR numbers with this voice's envelope time factor (slop), when it has one.
	var vtime := false
	var va := PackedInt64Array([0, 0, 0, 0, 0, 0, 0, 0])
	var vd := PackedInt64Array([1, 1, 1, 1, 1, 1, 1, 1])
	var vkd := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var vkr := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var vkr2 := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	## Filter 2; each envelope's time factor from the matrix (envN.time), read as its stages start.
	var f2 := AKSynthCore._Filt.new()
	## Filter 1 when it is the comb type (the voice's own filter code runs the others).
	var f1x := AKSynthCore._Filt.new()
	var etf := PackedFloat64Array([1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0])
	## Each envelope's attack, decay and release time factors: [k * 3 + part].
	var ets := PackedFloat64Array([1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1])
	## Filter feedback: this voice's amount and the filter block's last outputs.
	var o_fb := 0.0
	var fby := PackedFloat64Array([0.0, 0.0])
	## The newer state-variable types' output weights (input, band, low).
	var sm0 := 0.0
	var sm1 := 0.0
	var sm2 := 0.0
	## Pre-filter states (left, right): the lowpass, the highpass's lowpass.
	var plp := PackedFloat64Array([0.0, 0.0])
	var php := PackedFloat64Array([0.0, 0.0])
	## The comb: its lines (left, then right), write position and period in samples.
	var comb := PackedFloat64Array()
	var cw := 0
	var cper := 1.0
	## The comb's feedback for this voice (the patch's, moved by comb.feedback rows).
	var cfb := 0.0
	var age := 0
	var phase := PackedFloat64Array()
	var raw := PackedFloat64Array()
	## Band-limited sync: each slot's correction carried to its next sample.
	var sync_c := PackedFloat64Array()
	## Pink and red noise filter states, three per oscillator.
	var nzs := PackedFloat64Array()
	var last_semi := PackedFloat64Array()
	var freq := PackedFloat64Array()
	var ic1 := PackedFloat64Array([0.0, 0.0])
	var ic2 := PackedFloat64Array([0.0, 0.0])
	var last_c := -1.0
	var last_q := -1.0
	var fg := 0.0
	var fk := 1.0
	var a1 := 0.0
	var a2 := 0.0
	var a3 := 0.0
	var src := PackedFloat64Array()
	## Matrix sums per oscillator: pitch, level, fm, width, position.
	var mo := PackedFloat64Array()
	# Held between control steps.
	var o_level := PackedFloat64Array()
	var o_idx := PackedFloat64Array()
	var o_width := PackedFloat64Array()
	var o_pos := PackedFloat64Array()
	var amp_mod := 1.0
	var dt := PackedFloat64Array()
	## The right channel's sample when the patch spreads (tick returns the left).
	var yr := 0.0
	## Time since each oscillator (x unison) last wrapped, in samples, or -1.
	var wrap_t := PackedFloat64Array()
	## Wavetable reads: band-limit level per oscillator, and the key zone and
	## the blend toward the next one.
	var o_mip := PackedInt64Array()
	var o_zone := PackedInt64Array()
	var o_zw := PackedFloat64Array()
	# Right-channel SVF states and the ladder's four stages per channel.
	var ic1r := PackedFloat64Array([0.0, 0.0])
	var ic2r := PackedFloat64Array([0.0, 0.0])
	var lad := PackedFloat64Array()
	var lg := 0.0
	var lG := 0.0
	var lbeta := 0.0
	var lk := 0.0
	var _core_p: Dictionary

	func _init() -> void:
		dt.resize(MAX_OSC * MAX_SLOT)
		wrap_t.resize(MAX_OSC * MAX_SLOT)
		pdb.resize(MAX_OSC * MAX_SLOT)
		pdn_t.resize(MAX_OSC)
		pdn_m.resize(MAX_OSC)
		o_mip.resize(MAX_OSC)
		o_zone.resize(MAX_OSC)
		o_zw.resize(MAX_OSC)
		lad.resize(8)
		mo.resize(5 * MAX_OSC)
		o_level.resize(MAX_OSC)
		o_idx.resize(MAX_OSC)
		o_width.resize(MAX_OSC)
		o_pos.resize(MAX_OSC)
		phase.resize(MAX_OSC * MAX_SLOT)
		raw.resize(MAX_OSC * MAX_SLOT)
		sync_c.resize(MAX_OSC * MAX_SLOT)
		nzs.resize(3 * MAX_OSC)
		last_semi.resize(MAX_OSC)
		freq.resize(MAX_OSC)
		src.resize(N_SRC)
		for k in MAX_ENV:
			dx.append(_Dx7.new())
			dxp.append(_Dx7P.new())
		dlfo.append(_Dx7Lfo.new())
		dlfo.append(_Dx7Lfo.new())
		fbp.resize(MAX_OSC * MAX_SLOT)
		o_kv.resize(MAX_OSC)
		o_dxnote.resize(MAX_OSC)
		o_dxbase.resize(MAX_OSC)
		o_inc.resize(MAX_OSC)

	## 32-bit xorshift, the same sequence as the native engine.
	func white01() -> float:
		rng ^= (rng << 13) & 0xFFFFFFFF
		rng ^= rng >> 17
		rng ^= (rng << 5) & 0xFFFFFFFF
		return float(rng) / 4294967295.0

	## Oscillator start phases set by the patch (after the random ones, which are drawn
	## either way): `phase` puts every slot of an oscillator there; `phase_with` takes
	## another oscillator's start phases (its slot for slot, wrapping), plus `phase`.
	func _start_phases(core: AKSynthCore) -> void:
		var oscs: Array = core._p.osc
		for j in oscs.size():
			var o: Dictionary = oscs[j]
			var p0 := float(o.get("phase0", -1.0))
			var pw := int(o.get("phase_with", -1))
			if pw >= oscs.size() or pw == j:
				pw = -1
			if p0 < 0.0 and pw < 0:
				continue
			var off := maxf(0.0, p0)
			for k in core._slot_n[j]:
				var base := 0.0
				if pw >= 0:
					var n := maxi(1, core._slot_n[pw])
					base = phase[pw * MAX_SLOT + k % n]
				var ph := base + off
				phase[j * MAX_SLOT + k] = ph - floorf(ph)

	## A random value for LFO k: lfo1 and lfo2 draw from the voice's stream, the others from their own.
	func lfo_rand(k: int) -> float:
		if k < 2:
			return white01()
		var r := lrng[k]
		r ^= (r << 13) & 0xFFFFFFFF
		r ^= r >> 17
		r ^= (r << 5) & 0xFFFFFFFF
		lrng[k] = r
		return float(r) / 4294967295.0

	func start(core: AKSynthCore, p_note: float, p_vel: float, from_note: float) -> void:
		var c: Dictionary = core._p
		active = true
		gated = true
		pedal = false
		killing = false
		serial = core._next_serial()
		note = p_note
		target = p_note
		cur = from_note if (core._kg > 0.0 and from_note >= 0.0) else p_note
		vel = p_vel
		gvel = p_vel
		gmod = core.mod_wheel
		gtouch = core.aftertouch
		rng = (int(c.seed) * 73856093 ^ serial * 19349663 ^ 83492791) & 0xFFFFFFFF
		if rng == 0:
			rng = 0x9E3779B9
		for k in range(2, core._n_lfo):
			lrng[k] = rng ^ ((k * 2654435761) & 0xFFFFFFFF)
			if lrng[k] == 0:
				lrng[k] = 0x9E3779B9
		rnd = white01() * 2.0 - 1.0
		phase.fill(0.0)
		raw.fill(0.0)
		sync_c.fill(0.0)
		nzs.fill(0.0)
		last_semi.fill(-1e9)
		var u := int(c.unison)
		for j in (c.osc as Array).size():
			if u > 1 or core._slot_n[j] > 1:
				for k in core._slot_n[j]:
					phase[j * MAX_SLOT + k] = white01()
		_start_phases(core)
		for k in core._n_lfo:
			lfo_done[k] = 0
			# A free LFO is where the playback clock has taken it; otherwise each note starts it at its phase.
			var lp := core._lfo_phase[k] + (core._lfo_base[k] + core._lfo_inc[k] * float(core.frame - core._lfo_base_frame[k]) if core._lfo_free[k] else 0.0)
			lfo_ph[k] = lp - floorf(lp)
			lfo_oct[k] = 0.0
			lfo_sh[k] = lfo_rand(k) * 2.0 - 1.0 if core._lfo_shape[k] == 4 or core._lfo_shape[k] == 5 else 0.0
			if core._lfo_shape[k] == 5:
				# Smooth random glides from one random value to the next each cycle.
				lfo_sh0[k] = lfo_sh[k]
				lfo_sh[k] = lfo_rand(k) * 2.0 - 1.0
			if k < 2 and core._lfo_dx7[k]:
				dlfo[k].reset(core, c.lfo[k])
		_start_slot(core)
		# Operator state, cleared and at full level for every note, so a patch edit that
		# turns operators on while this note sounds (an fm list, a ratio, a level_env)
		# finds it ready instead of silent.
		fbp.fill(0.0)
		o_dxnote.fill(-1)
		o_kv.fill(1.0)
		if core._ops:
			_note_levels(core, p_note, p_vel)
		age = 0
		ne = core._n_env
		_note_time_mods(core)
		for k in ne:
			stage[k] = ATTACK
			t[k] = 0
			level[k] = 0.0
			start_level[k] = 0.0
			rel_from[k] = 0.0
			ev[k] = 1.0
			pend[k] = 0
			dead[k] = 0
			dq[k] = 0
			match core._env_kind[k]:
				K_STAGES:
					var e: Dictionary = c.env[k]
					_note_scales(e, k, p_note, p_vel)
					level[k] = float(e.start) * lsc[k]
					_stage_enter(core, e, k, 0)
				K_DX7:
					var d := dx[k]
					d.srm = core._dx7_srm
					_dx7_note(c.env[k], k, p_note, p_vel)
					d.level = 0
					d.down = true
					d.advance(c.env[k], 0)
					dg2[k] = 0.0
				K_DX7P:
					dxp[k].unit = core._penv_unit
					dxp[k].set_up(c.env[k])
					level[k] = 0.0
				K_CZ:
					czc[k] = 0.0
					czrel[k] = 0
					_cz_enter(c.env[k], k, 0)
		pdb.fill(0)
		pdn_t.fill(0.0)
		pdn_m.fill(1.0)
		ic1.fill(0.0)
		ic2.fill(0.0)
		ic1r.fill(0.0)
		ic2r.fill(0.0)
		lad.fill(0.0)
		f2.reset()
		f1x.reset()
		fby.fill(0.0)
		wrap_t.fill(-1.0)
		last_c = -1.0
		last_q = -1.0
		plp.fill(0.0)
		php.fill(0.0)
		if core._comb_on:
			if comb.size() != 2 * COMB_MAX:
				comb.resize(2 * COMB_MAX)
			comb.fill(0.0)
			cw = 0

	## This voice's slot numbers, and its ADSR numbers scaled by the slot's time factor.
	func _start_slot(core: AKSynthCore) -> void:
		var s := slot if slot < core._n_slot else -1
		s_pan = core._slot_pan[s] if s >= 0 else 0.0
		s_pitch = core._sl_pitch[s] if s >= 0 else 0.0
		s_cut = core._sl_cut[s] if s >= 0 else 0.0
		s_gain = core._sl_gain[s] if s >= 0 else 1.0
		s_tf = core._sl_tf[s] if s >= 0 else 1.0
		vtime = core._slop_time and s_tf != 1.0
		if vtime:
			for k in core._n_env:
				va[k] = roundi(float(core._env_a[k]) * s_tf)
				vd[k] = maxi(1, roundi(float(core._env_d[k]) * s_tf))
				vkd[k] = pow(core._env_kd[k], 1.0 / s_tf)
				vkr[k] = pow(core._env_kr[k], 1.0 / s_tf)
				vkr2[k] = pow(core._env_kr2[k], 1.0 / s_tf)

	func retrigger(from_zero := false) -> void:
		for k in ne:
			stage[k] = ATTACK
			t[k] = 0
			if from_zero:
				level[k] = 0.0
			start_level[k] = level[k]
			ev[k] = 1.0
			pend[k] = 1
			dead[k] = 0
		gated = true

	func release() -> void:
		gated = false
		pedal = false
		for k in ne:
			if stage[k] != RELEASE:
				rel_from[k] = level[k]
				pend[k] = 2
			stage[k] = RELEASE

	func kill() -> void:
		release()
		killing = true

	func env_tick(core: AKSynthCore, k: int) -> float:
		var kind := core._env_kind[k]
		if kind == K_STAGES:
			return _stages_tick(core, k)
		if kind == K_DX7:
			return _dx7_tick(core, k)
		if kind == K_DX7P:
			return _dx7p_tick(core, k)
		if kind == K_CZ:
			return _cz_tick(core, k)
		if vtime:
			return _adsr_slot(core, k)
		if stage[k] == ATTACK:
			if t[k] < core._env_a[k]:
				level[k] = start_level[k] + (1.0 - start_level[k]) * float(t[k]) / core._env_a[k]
				t[k] += 1
				return level[k]
			stage[k] = DECAY
			t[k] = 0
			ev[k] = 1.0
		if stage[k] == DECAY:
			var s := core._env_s[k]
			if core._env_exp[k]:
				level[k] = s + (1.0 - s) * ev[k]
				ev[k] *= core._env_kd[k]
				return level[k]
			if t[k] < core._env_d[k]:
				level[k] = 1.0 - (1.0 - s) * float(t[k]) / core._env_d[k]
				t[k] += 1
				return level[k]
			stage[k] = SUSTAIN
		if stage[k] == SUSTAIN:
			level[k] = core._env_s[k]
		elif stage[k] == RELEASE:
			if killing:
				level[k] *= core._kill_k
			else:
				level[k] *= core._env_kr[k] if level[k] > rel_from[k] * core._env_knee[k] else core._env_kr2[k]
		return level[k]

	## The ADSR with this voice's own (slop-scaled) times.
	func _adsr_slot(core: AKSynthCore, k: int) -> float:
		if stage[k] == ATTACK:
			if t[k] < va[k]:
				level[k] = start_level[k] + (1.0 - start_level[k]) * float(t[k]) / va[k]
				t[k] += 1
				return level[k]
			stage[k] = DECAY
			t[k] = 0
			ev[k] = 1.0
		if stage[k] == DECAY:
			var s := core._env_s[k]
			if core._env_exp[k]:
				level[k] = s + (1.0 - s) * ev[k]
				ev[k] *= vkd[k]
				return level[k]
			if t[k] < vd[k]:
				level[k] = 1.0 - (1.0 - s) * float(t[k]) / vd[k]
				t[k] += 1
				return level[k]
			stage[k] = SUSTAIN
		if stage[k] == SUSTAIN:
			level[k] = core._env_s[k]
		elif stage[k] == RELEASE:
			if killing:
				level[k] *= core._kill_k
			else:
				level[k] *= vkr[k] if level[k] > rel_from[k] * core._env_knee[k] else vkr2[k]
		return level[k]

	## A stages envelope's time and level factors for a note.
	func _note_scales(e: Dictionary, k: int, p_note: float, p_vel: float) -> void:
		tkf[k] = pow(2.0, -float(e.tk) * (p_note - float(e.tk_center)) / 12.0) if float(e.tk) != 0.0 else 1.0
		tvf[k] = pow(2.0, -float(e.tv) * (p_vel - 1.0)) if float(e.tv) != 0.0 else 1.0
		lsc[k] = 1.0 - float(e.lv) * (1.0 - p_vel)

	## Start stage `i` of a stages envelope from the level where it is. Stages of
	## no length are passed at once; ends where it holds or a stage has length.
	func _stage_enter(core: AKSynthCore, e: Dictionary, k: int, i: int) -> void:
		var times: PackedFloat64Array = e.time
		var n := times.size()
		var curves: PackedInt64Array = e.curve
		for guard in 4 * n + 4:
			if i < 0 or i >= n:
				si[k] = n
				sn[k] = ST_HOLD
				return
			si[k] = i
			t[k] = 0
			var scale := 1.0
			if (int(e.tk_mask) >> i) & 1:
				scale *= tkf[k]
			if (int(e.tv_mask) >> i) & 1:
				scale *= tvf[k]
			if s_tf != 1.0:
				scale *= s_tf
			if etf[k] != 1.0:
				scale *= etf[k]
			var sus_i := int(e.sustain)
			var part := ets[k * 3 + (0 if i == 0 else (1 if (sus_i < 0 or i <= sus_i) else 2))]
			if part != 1.0:
				scale *= part
			var length := roundi(times[i] * scale * core.sr)
			sfrom[k] = level[k]
			sto[k] = level[k] if curves[i] == 2 else (e.level as PackedFloat64Array)[i] * lsc[k]
			if length > 0:
				sn[k] = length
				var am: float = (e.amount as PackedFloat64Array)[i]
				if curves[i] == 1 and absf(am) > 1e-9:
					sg[k] = 1.0
					sk[k] = exp(am / length)
					sden[k] = exp(am) - 1.0
				else:
					sden[k] = 0.0
				return
			level[k] = sto[k]
			i = _stage_next(e, k, i)
			if i == ST_HOLD:
				sn[k] = ST_HOLD
				return
		sn[k] = ST_HOLD

	## The stage after `i`: back round a loop, holding at the sustain while the key is down, or on.
	func _stage_next(e: Dictionary, k: int, i: int) -> int:
		if stage[k] != RELEASE:
			if i == int(e.loop_b):
				return int(e.loop_a)
			if i == int(e.sustain):
				return ST_HOLD
		return i + 1

	func _stages_tick(core: AKSynthCore, k: int) -> float:
		if killing:
			level[k] *= core._kill_k
			return level[k]
		var e: Dictionary = core._p.env[k]
		if pend[k] != 0:
			var pk := pend[k]
			pend[k] = 0
			if pk == 1:
				_note_scales(e, k, target, vel)
				_stage_enter(core, e, k, 0)
			else:
				var sus := int(e.sustain)
				if sus >= 0:
					if sus + 1 < (e.time as PackedFloat64Array).size():
						_stage_enter(core, e, k, sus + 1)
					else:
						si[k] = (e.time as PackedFloat64Array).size()
						sn[k] = ST_FALL
		var n := sn[k]
		if n == ST_HOLD:
			return level[k]
		if n == ST_FALL:
			level[k] *= core._env_kr[k]
			return level[k]
		t[k] += 1
		if t[k] >= n:
			level[k] = sto[k]
			var nx := _stage_next(e, k, si[k])
			if nx == ST_HOLD:
				sn[k] = ST_HOLD
			else:
				_stage_enter(core, e, k, nx)
			return level[k]
		if sden[k] != 0.0:
			sg[k] *= sk[k]
			level[k] = sfrom[k] + (sto[k] - sfrom[k]) * (sg[k] - 1.0) / sden[k]
		elif (e.curve as PackedInt64Array)[si[k]] != 2:
			level[k] = sfrom[k] + (sto[k] - sfrom[k]) * float(t[k]) / n
		return level[k]

	## A dx7 envelope's per-note numbers (key and velocity as MIDI).
	func _dx7_note(e: Dictionary, k: int, p_note: float, p_vel: float) -> void:
		var mn := clampi(roundi(p_note) + int(e.get("ko", 0)), 0, 127)
		dx[k].outlevel = AKSynthCore.dx7_outlevel(e, mn, clampi(roundi(p_vel * 127.0), 0, 127))
		dx[k].rate_scaling = AKSynthCore.dx7_rate_scaling(e, mn)

	## msfa's getsample() every DX7_N samples (key changes are taken there, as
	## msfa takes them between blocks); the gain ramps linearly between, as
	## msfa's operator kernel ramps it.
	func _dx7_tick(core: AKSynthCore, k: int) -> float:
		if killing:
			level[k] *= core._kill_k
			return level[k]
		if t[k] == 0:
			if dead[k] != 0:
				level[k] = 0.0
				return 0.0
			var e: Dictionary = core._p.env[k]
			var d := dx[k]
			if pend[k] == 1:
				_dx7_note(e, k, target, vel)
				d.down = true
				d.advance(e, 0)
			elif pend[k] == 2 and d.down:
				d.down = false
				d.advance(e, 3)
			pend[k] = 0
			var lq := d.getsample(e)
			var ams := int(e.get("ams", 0))
			if ams > 0 and core._dx7_lfo >= 0:
				lq -= AKSynthCore.dx7_amp_mod(lq, dlfo[core._dx7_lfo].amd, ams)
			dg1[k] = dg2[k]
			dg2[k] = pow(2.0, float(lq - DX7_FULL) / 16777216.0)
			dq[k] = 1 if dg1[k] < DX7_THRESH and dg2[k] < DX7_THRESH else 0
			if d.ix >= 4 and (e.levels as PackedInt64Array)[3] == 0:
				dead[k] = 1
		t[k] += 1
		level[k] = 0.0 if dq[k] != 0 else dg1[k] + (dg2[k] - dg1[k]) * float(t[k]) / DX7_N
		if t[k] == DX7_N:
			t[k] = 0
		return level[k]

	## A dx7_pitch envelope: msfa's level each 64-sample block, held between, in octaves.
	## A cz envelope step (as the native SynthVoice::cz_enter, after MAME's uPD933): its target in
	## the chip's units, its rate per 40 kHz sample, and its direction from where the value is.
	func _cz_enter(e: Dictionary, k: int, i: int) -> void:
		czi[k] = i
		var rates: PackedInt64Array = e.rates
		var lvls: PackedInt64Array = e.levels
		var lv := int(lvls[i]) if i < lvls.size() else 0
		var r := (int(rates[i]) & 127) if i < rates.size() else 127
		var kz := int(e.czk)
		if kz == 0:
			czt[k] = float((lv & 127) << 18)
		elif kz == 1:
			czt[k] = float((lv & 127) << 19)
		else:
			czt[k] = float((lv & 63) << 16) * (32.0 if (lv & 64) != 0 else 1.0)
		czr[k] = float((8 | (r & 7)) << (r >> 3))
		czd[k] = 1 if czt[k] < czc[k] else 0

	func _cz_tick(core: AKSynthCore, k: int) -> float:
		var e: Dictionary = core._p.env[k]
		var sus := int(e.sustain)
		var endi := int(e.end)
		if pend[k] == 1:
			pend[k] = 0
			czrel[k] = 0
			_cz_enter(e, k, 0)
		elif stage[k] == RELEASE and czrel[k] == 0:
			pend[k] = 0
			czrel[k] = 1
			if czi[k] <= sus and sus < endi:
				_cz_enter(e, k, sus + 1)
		var r := czr[k] * core._cz_scale
		if czc[k] != czt[k]:
			if czd[k] == 0:
				czc[k] = czt[k] if (czc[k] > czt[k] or czt[k] - czc[k] <= r) else czc[k] + r
			else:
				czc[k] = czt[k] if (czc[k] < czt[k] or czc[k] - czt[k] <= r) else czc[k] - r
		if czc[k] == czt[k] and czi[k] < endi and (czrel[k] != 0 or czi[k] != sus):
			_cz_enter(e, k, czi[k] + 1)
		var kz := int(e.czk)
		if kz == 0:
			var v := floorf(czc[k] / 65536.0)
			level[k] = 0.0 if v <= 0.0 else pow(2.0, 13.0 * (v / 511.0 - 1.0))
		elif kz == 1:
			level[k] = floorf(czc[k] / 65536.0) / 1024.0
		else:
			level[k] = floorf(czc[k] / 2048.0) / 512.0
		return level[k]

	func _dx7p_tick(core: AKSynthCore, k: int) -> float:
		if t[k] == 0:
			var e: Dictionary = core._p.env[k]
			var d := dxp[k]
			if pend[k] == 1:
				d.down = true
				d.advance(e, 0)
			elif pend[k] == 2 and d.down:
				d.down = false
				d.advance(e, 3)
			pend[k] = 0
			level[k] = float(d.getsample(e)) / 16777216.0
		t[k] += 1
		if t[k] == DX7_N:
			t[k] = 0
		return level[k]

	## The DX7 LFOs' block step, before the envelopes read their amp modulation.
	func _dx7_lfo_step(core: AKSynthCore) -> void:
		for k in 2:
			if core._lfo_dx7[k]:
				dlfo[k].step(core._p.lfo[k])

	## Per note: each oscillator's level factor from velocity_sens and key_scaling.
	func _note_levels(core: AKSynthCore, p_note: float, p_vel: float) -> void:
		var oscs: Array = core._p.osc
		for j in oscs.size():
			var o: Dictionary = oscs[j]
			var kv := 1.0 - float(o.get("vel_sens", 0.0)) * (1.0 - p_vel)
			if bool(o.get("ks", false)):
				var oct := (p_note - float(o.ks_break)) / 12.0
				var right := oct >= 0.0
				var depth := float(o.ks_r) if right else float(o.ks_l)
				var x := absf(oct)
				var db := depth * ((pow(2.0, x) - 1.0) if bool(o.ks_rexp if right else o.ks_lexp) else x)
				kv *= pow(10.0, db / 20.0)
			o_kv[j] = kv

	## An LFO's value now; its phase then moves on a whole control period.
	func lfo_tick(core: AKSynthCore, k: int) -> float:
		if core._lfo_dx7[k]:
			return float(dlfo[k].pitch_mod) / 16777216.0
		var ph := lfo_ph[k]
		var shape := core._lfo_shape[k]
		var v := 0.0
		if shape == 6:
			return _lfo_custom(core, k)
		match shape:
			0: v = sin(TAU * ph)
			1: v = 1.0 - 4.0 * absf(ph - 0.5)
			2: v = 2.0 * ph - 1.0
			3: v = 1.0 if ph < core._lfo_width[k] else -1.0
			5: v = lfo_sh0[k] + (lfo_sh[k] - lfo_sh0[k]) * (0.5 - 0.5 * cos(PI * ph))
			_: v = lfo_sh[k]
		var d := core._lfo_delay[k]
		if d > 0.0 and age < d:
			v *= float(age) / d
		ph += core._lfo_inc[k] * CONTROL * (1.0 if lfo_oct[k] == 0.0 else pow(2.0, lfo_oct[k]))
		if ph >= 1.0:
			ph -= floorf(ph)
			if shape == 4:
				lfo_sh[k] = lfo_rand(k) * 2.0 - 1.0
			elif shape == 5:
				lfo_sh0[k] = lfo_sh[k]
				lfo_sh[k] = lfo_rand(k) * 2.0 - 1.0
		lfo_ph[k] = ph
		return v

	## A custom LFO shape: its points across a cycle, joined by lines or held as steps. A one-shot
	## one runs from the first point to the last once, then holds the last.
	func _lfo_custom(core: AKSynthCore, k: int) -> float:
		var pts: PackedFloat64Array = core._lfo_pts[k]
		var n := pts.size()
		var once: bool = core._lfo_once[k]
		var v := 0.0
		var ph := lfo_ph[k]
		if lfo_done[k] != 0:
			v = pts[n - 1]
		else:
			var x := ph * float(n - 1 if once else n)
			var i := mini(floori(x), n - 1)
			if core._lfo_interp[k] == 1:
				v = pts[i]
			else:
				var nx := pts[(i + 1) % n] if not once else pts[mini(i + 1, n - 1)]
				v = pts[i] + (nx - pts[i]) * (x - float(i))
		var d := core._lfo_delay[k]
		if d > 0.0 and age < d:
			v *= float(age) / d
		ph += core._lfo_inc[k] * CONTROL * (1.0 if lfo_oct[k] == 0.0 else pow(2.0, lfo_oct[k]))
		if ph >= 1.0:
			ph -= floorf(ph)
			if once:
				lfo_done[k] = 1
		lfo_ph[k] = ph
		return v

	## The control step (every CONTROL samples): LFOs, the matrix, glide,
	## pitches, oscillator settings, filter coefficients, amp and pan.
	func control(core: AKSynthCore, e0: float, e1: float, e2: float) -> void:
		var c: Dictionary = core._p
		src[SRC_ENV1] = e0
		src[SRC_ENV2] = e1
		src[SRC_ENV3] = e2
		src[SRC_LFO1] = lfo_tick(core, 0)
		src[SRC_LFO2] = lfo_tick(core, 1)
		src[SRC_VEL] = gvel
		src[SRC_KEY] = (target - 60.0) / 12.0
		gmod += (core.mod_wheel - gmod) * core._ctl_k
		gtouch += (core.aftertouch - gtouch) * core._ctl_k
		src[SRC_MOD] = gmod
		src[SRC_TOUCH] = gtouch
		src[SRC_RANDOM] = rnd
		src[SRC_BEND] = core.bend
		for k in range(3, ne):
			src[SRC_ENV4 + k - 3] = level[k]
		for k in range(2, core._n_lfo):
			src[SRC_LFO3 + k - 2] = lfo_tick(core, k)
		for k in 4:
			src[SRC_MAC1 + k] = core._macros[k]
		var m_cut2 := 0.0
		var m_q2 := 0.0
		var m_et := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
		var m_es := PackedFloat64Array()
		m_es.resize(24)
		var m_fb := 0.0
		var m_pitch := 0.0
		var m_cut := 0.0
		var m_q := 0.0
		var m_amp := 0.0
		var m_pan := 0.0
		var m_cfb := 0.0
		var m_cst := 0.0
		var oscs: Array = c.osc
		var no := oscs.size()
		mo.fill(0.0)
		lfo_oct.fill(0.0)
		for row: Dictionary in c.mods:
			var x := float(row.amount) * src[int(row.src)]
			var via := int(row.get("via", -1))
			if via >= 0:
				x *= src[via]
			var via2 := int(row.get("via2", -1))
			if via2 >= 0:
				x *= src[via2]
			var dst := int(row.dst)
			if dst >= D_FB:
				if dst == D_FB:
					m_fb += x
				else:
					var d := dst - D_E1A
					m_es[(d % 8) * 3 + floori(d / 8.0)] += x
				continue
			match dst:
				D_PITCH: m_pitch += x
				D_CUTOFF: m_cut += x
				D_Q: m_q += x
				D_AMP: m_amp += x
				D_PAN: m_pan += x
				D_LFO1R, D_LFO2R, D_LFO3R, D_LFO4R, D_LFO5R, D_LFO6R, D_LFO7R, D_LFO8R: lfo_oct[int(row.dst) - D_LFO1R] += x
				D_COMBFB: m_cfb += x
				D_COMBP: m_cst += x
				D_CUT2: m_cut2 += x
				D_Q2: m_q2 += x
				D_E1T, D_E2T, D_E3T, D_E4T, D_E5T, D_E6T, D_E7T, D_E8T: m_et[int(row.dst) - D_E1T] += x
				_:
					var slot := (int(row.dst) - D_OPITCH) * MAX_OSC
					var o := int(row.osc)
					if o < 0:
						for j in no:
							mo[slot + j] += x
					elif o < no:
						mo[slot + o] += x
		for k in ne:
			etf[k] = 1.0 if m_et[k] == 0.0 else pow(2.0, m_et[k])
			for g in 3:
				ets[k * 3 + g] = 1.0 if m_es[k * 3 + g] == 0.0 else pow(2.0, m_es[k * 3 + g])
		if core._fb_on:
			o_fb = clampf(core._fb + m_fb, -1.0, 1.0)
		var semi := cur + core.bend * float(c.bend_range) + m_pitch
		if slot >= 0:
			semi += s_pitch
			m_cut += s_cut
			m_cut2 += s_cut
		if core._comb_on:
			# One period of the voice's pitch moved by the comb's interval.
			cper = clampf(core.sr / (440.0 * pow(2.0, (semi + core._comb_semis + m_cst - 69.0) / 12.0)), 1.0, float(COMB_MAX - 2))
			cfb = core._comb_fb if m_cfb == 0.0 else clampf(core._comb_fb + m_cfb, -0.99, 0.99)
		cur = target + (cur - target) * core._kg
		for j in no:
			var o: Dictionary = oscs[j]
			var s := semi + float(o.semis) + mo[j]
			if s != last_semi[j]:
				last_semi[j] = s
				if core._ops:
					_op_freq(core, o, j, s)
				else:
					freq[j] = 440.0 * pow(2.0, (s - 69.0) / 12.0)
			o_level[j] = float(o.level) + mo[MAX_OSC + j]
			if core._ops:
				o_level[j] *= o_kv[j]
			o_idx[j] = float(o.fm_index) + mo[2 * MAX_OSC + j]
			o_width[j] = clampf(float(o.width) + mo[3 * MAX_OSC + j], 0.01, 0.99)
			o_pos[j] = clampf(float(o.position) + mo[4 * MAX_OSC + j], 0.0, 1.0)
			var sb := j * MAX_SLOT
			for k in core._slot_n[j]:
				dt[sb + k] = minf(freq[j] * core._sratio[sb + k] / core.sr, core._inc_max)
			if core._ops and int(o.get("dx_mode", -1)) >= 0:
				# A dx7 operator advances exactly msfa's increment.
				for k in core._slot_n[j]:
					dt[sb + k] = o_inc[j] * core._sratio[sb + k]
			if int(o.table) >= 0:
				# The richest band-limit level whose top harmonic stays below
				# Nyquist for the highest unison voice.
				var top := 0.5 / (dt[sb] * core._ormax[j])
				var lv := 0
				while lv + 1 < AKWavetables.LEVELS and AKWavetables.level_limit(lv + 1) <= top:
					lv += 1
				o_mip[j] = lv
				var tb: Dictionary = core._tables[int(o.table)]
				var keys: PackedFloat64Array = tb.get("keys", PackedFloat64Array())
				var z := 0
				var zw := 0.0
				if keys.size() > 1:
					while z + 1 < keys.size() and keys[z + 1] <= cur:
						z += 1
					if z + 1 < keys.size() and cur > keys[z]:
						zw = (cur - keys[z]) / (keys[z + 1] - keys[z])
					if not bool(tb.get("blend", true)):
						z += 1 if zw > 0.5 else 0
						zw = 0.0
				o_zone[j] = z
				o_zw[j] = zw
		if int(c.filter_type) == F_COMB:
			f1x.control(c, m_cut, m_q, core.sr)
		elif int(c.filter_type) == F_LADDER:
			var cut := float(c.cutoff_hz)
			if m_cut != 0.0:
				cut *= pow(2.0, m_cut)
			var res := float(c.resonance)
			if m_q != 0.0:
				res = clampf(res * pow(2.0, m_q), 0.0, 1.2)
			if cut != last_c or res != last_q:
				last_c = cut
				last_q = res
				lg = tan(PI * clampf(cut, 10.0, 0.49 * core.sr) / core.sr)
				lG = lg / (1.0 + lg)
				lbeta = 1.0 / (1.0 + lg)
				lk = 4.0 * res
		elif int(c.filter_type) > 0:
			var cut := float(c.cutoff_hz)
			if m_cut != 0.0:
				cut *= pow(2.0, m_cut)
			var q := float(c.q)
			if m_q != 0.0:
				q *= pow(2.0, m_q)
			if cut != last_c or q != last_q:
				last_c = cut
				last_q = q
				fk = 2.0 * float(c.damping) * float(c.q) / q if c.diode else 1.0 / maxf(0.05, q)
				var g := tan(PI * clampf(cut, 10.0, 0.49 * core.sr) / core.sr)
				if int(c.filter_type) >= F_MIX:
					g = _svf_weights(c, g)
				fg = g
				a1 = 1.0 / (1.0 + g * (g + fk))
				a2 = g * a1
				a3 = g * a2
		if core._f2_on:
			f2.control(core._f2, m_cut2, m_q2, core.sr)
		amp_mod = maxf(0.0, 1.0 + m_amp)
		var kl: PackedFloat64Array = c.get("key_lv", PackedFloat64Array())
		if kl.size() >= 2:
			amp_mod *= AKSynthCore.key_level(kl, target)
		var pp := clampf(float(c.pan) + m_pan + s_pan, -1.0, 1.0)
		if pp == 0.0:
			gl = 1.0
			gr = 1.0
		else:
			var ang := (pp + 1.0) * PI * 0.25
			gl = cos(ang) * sqrt(2.0)
			gr = sin(ang) * sqrt(2.0)

	## The newer state-variable types (Simper's): the output's weights of input, band and low, and the
	## frequency warp a shelf needs (returned). fk may change too (the bell's).
	func _svf_weights(c: Dictionary, g: float) -> float:
		var ft := int(c.filter_type)
		var a := pow(10.0, float(c.get("gain_db", 0.0)) / 40.0)
		match ft:
			F_MIX:
				var hi := float(c.f_high)
				sm0 = hi
				sm1 = float(c.f_band) - fk * hi
				sm2 = float(c.f_low) - hi
			F_LSHELF:
				g /= sqrt(a)
				sm0 = 1.0
				sm1 = fk * (a - 1.0)
				sm2 = a * a - 1.0
			F_HSHELF:
				g *= sqrt(a)
				sm0 = a * a
				sm1 = fk * (1.0 - a) * a
				sm2 = 1.0 - a * a
			F_ALLPASS:
				# x - 2k band: flat, the phase turning through the cutoff.
				sm0 = 1.0
				sm1 = -2.0 * fk
				sm2 = 0.0
			_:
				fk /= a
				sm0 = 1.0
				sm1 = fk * (a * a - 1.0)
				sm2 = 0.0
		return g

	## An operator's frequency (phase 2): dx7 (msfa's integer increment from its
	## Q24 log frequency: the matrix pitch for ratio operators, only the bend for
	## fixed ones, as msfa), fixed_hz (the key ignored), or the key's x ratio.
	func _op_freq(core: AKSynthCore, o: Dictionary, j: int, s: float) -> void:
		var dxm := int(o.get("dx_mode", -1))
		if dxm >= 0:
			var mn := clampi(roundi(target + float(o.semis)), 0, 127)
			if mn != o_dxnote[j]:
				o_dxnote[j] = mn
				o_dxbase[j] = AKSynthCore.dx7_osc_logfreq(mn, dxm, int(o.dx_coarse), int(o.dx_fine), int(o.dx_detune))
			var off := (s - target - float(o.semis)) if dxm == 0 else core.bend * float(core._p.bend_range)
			var inc := core.freqlut(o_dxbase[j] + roundi(off * 16777216.0 / 12.0))
			o_inc[j] = float(inc) / 16777216.0
			freq[j] = o_inc[j] * core.sr
			return
		if float(o.get("fixed_hz", 0.0)) > 0.0:
			freq[j] = float(o.fixed_hz) * pow(2.0, (s - cur) / 12.0)
		else:
			freq[j] = 440.0 * pow(2.0, (s - 69.0) / 12.0) * float(o.get("ratio", 1.0))

	## One sample, mono (pan goes to gl, gr).
	func tick(core: AKSynthCore) -> float:
		var c: Dictionary = core._p
		_core_p = c
		if core._dx7_lfo >= 0 and age % DX7_N == 0:
			_dx7_lfo_step(core)
		var e0 := env_tick(core, 0)
		var e1 := env_tick(core, 1)
		var e2 := env_tick(core, 2)
		for k in range(3, ne):
			env_tick(core, k)
		if age % CONTROL == 0:
			control(core, e0, e1, e2)
		age += 1
		var oscs: Array = c.osc
		var no := oscs.size()
		var stereo := core._stereo
		var mix := 0.0
		var mix_r := 0.0
		var dry := 0.0
		var dry_r := 0.0
		var mix2 := 0.0
		var mix2_r := 0.0
		for j in range(no - 1, -1, -1):
			var o: Dictionary = oscs[j]
			var shape := int(o.shape)
			var acc := 0.0
			var acc_r := 0.0
			var n := core._slot_n[j]
			var sb := j * MAX_SLOT
			if shape == SH_NOISE:
				acc = white01() * 2.0 - 1.0
				var nc := int(o.get("ncolor", 0))
				if nc == 1:
					var zb := j * 3
					nzs[zb] = 0.99765 * nzs[zb] + acc * 0.0990460
					nzs[zb + 1] = 0.96300 * nzs[zb + 1] + acc * 0.2965164
					nzs[zb + 2] = 0.57000 * nzs[zb + 2] + acc * 1.0526913
					acc = (nzs[zb] + nzs[zb + 1] + nzs[zb + 2] + acc * 0.1848) * PINK_G
				elif nc == 2:
					nzs[j * 3] = (nzs[j * 3] + 0.02 * acc) / 1.02
					acc = nzs[j * 3] * RED_G
				var nle := int(o.level_env) if core._ops else -1
				if nle >= 0:
					acc *= level[nle]
				for k in n:
					raw[sb + k] = acc
				acc_r = acc
			elif shape == SH_PD:
				# The CZ's oscillator (as the native pd branch): no fm or sync.
				var ring := int(o.ring)
				var mb := j * MAX_OSC * MAX_SLOT
				var le := int(o.level_env)
				var eg := level[le] if le >= 0 else 1.0
				var se := int(o.get("shape_env", -1))
				var pe := int(o.get("pitch_env", -1))
				var amt := clampf(o_pos[j] + (level[se] if se >= 0 else 0.0), 0.0, 1.0) * 1024.0
				var pmul := pow(2.0, level[pe] / 12.0) if pe >= 0 else 1.0
				if bool(o.get("pd_noise", false)):
					pdn_t[j] += 5000.0 / core.sr
					if pdn_t[j] >= 1.0:
						pdn_t[j] -= floorf(pdn_t[j])
						pdn_m[j] = 1.0 if white01() < 0.5 else PD_NOISE_UP
					pmul *= pdn_m[j]
				var w1 := int(o.get("pd_w1", 0))
				var w2 := int(o.get("pd_w2", w1))
				var win := int(o.get("pd_win", 0))
				for k in n:
					var d := dt[sb + k] * pmul
					var ph := phase[sb + k]
					var lim := 1024.0 - minf(1024.0, floorf(absf(d) * core.sr * 8192.0 / 40000.0))
					var dcw := minf(minf(amt, lim), 1023.0)
					var x := AKSynthCore.pd_sample(w2 if pdb[sb + k] != 0 else w1, win, ph, dcw)
					if ring >= 0:
						x *= raw[ring * MAX_SLOT + core._smap[mb + ring * MAX_SLOT + k]]
					x *= eg
					raw[sb + k] = x
					ph += d
					if ph >= 1.0:
						ph -= floorf(ph)
						pdb[sb + k] ^= 1
						wrap_t[sb + k] = ph / d
					else:
						wrap_t[sb + k] = -1.0
						if ph < 0.0:
							ph -= floorf(ph)
					phase[sb + k] = ph
					if stereo:
						acc += x * core._swl[sb + k]
						acc_r += x * core._swr[sb + k]
					else:
						acc += x * core._sw[sb + k]
				acc *= core._oinv[j]
				acc_r *= core._oinv[j]
			else:
				var fm_from := int(o.fm_from)
				var sync := int(o.sync)
				var ring := int(o.ring)
				var fsrc: PackedInt64Array = o.fm_src if core._ops else PackedInt64Array()
				var famt: PackedFloat64Array = o.fm_amt if core._ops else PackedFloat64Array()
				var fb := float(o.feedback) if core._ops else 0.0
				var le := int(o.level_env) if core._ops else -1
				var eg := level[le] if le >= 0 else 1.0
				var dxo := core._ops and int(o.get("dx_mode", -1)) >= 0
				var idx := o_idx[j]
				var width := o_width[j]
				var pos := o_pos[j]
				var tab: Dictionary = core._tables[int(o.table)] if int(o.table) >= 0 else {}
				var mb := j * MAX_OSC * MAX_SLOT
				var fmode := int(o.get("fm_mode", 0))
				var bls := core._bl_sync and sync >= 0
				for k in n:
					var d := dt[sb + k]
					var ph := phase[sb + k]
					# Band-limited: the master wrapped `reset` samples before the next one; this
					# sample plays on, and the jump is smoothed across this one and the next.
					var reset := -1.0
					if sync >= 0:
						var ms := sync * MAX_SLOT + core._smap[mb + sync * MAX_SLOT + k]
						if bls:
							if sync > j:
								# The master ran first this sample: its wrap (if any) is in the coming sample.
								reset = wrap_t[ms]
							else:
								# It runs after this one: its wrap in the coming sample, from its phase now.
								var mph := phase[ms]
								var md := dt[ms]
								if md > 0.0 and mph + md >= 1.0:
									reset = (mph + md - 1.0) / md
						else:
							var ws := wrap_t[ms]
							if ws >= 0.0:
								ph = ws * d
								ph -= floorf(ph)
					var pm := idx * raw[fm_from * MAX_SLOT + core._smap[mb + fm_from * MAX_SLOT + k]] if fm_from >= 0 else 0.0
					for m in fsrc.size():
						pm += famt[m] * raw[fsrc[m] * MAX_SLOT + core._smap[mb + fsrc[m] * MAX_SLOT + k]]
					if fmode != 0:
						# Pitch (semitones) or linear (Hz, through zero) FM: the modulators move this
						# sample's increment, not the phase.
						d = d * pow(2.0, pm / 12.0) if fmode == 1 else d + pm / core.sr
						d = clampf(d, -core._inc_max, core._inc_max)
						pm = 0.0
					if fb != 0.0:
						pm += fb * 0.5 * (fbp[sb + k] + raw[sb + k])
					var x := 0.0
					if shape == SH_SINE:
						if dxo:
							# An operator silent this block (msfa skips it) needs no sine: its output is 0 either way.
							x = 0.0 if eg == 0.0 else AKSynthCore.dx7_sinf(ph + pm / TAU)
						else:
							x = sin(TAU * ph + pm)
					else:
						var q := ph
						if pm != 0.0:
							q = ph + pm / TAU
							q -= floorf(q)
						if shape == SH_MORPH:
							var p3 := pos * 3.0
							var a := mini(2, floori(p3))
							var w := p3 - a
							x = AKSynthCore._shape(a, q, d, 0.5, core._sinc_blep)
							if w > 0.0:
								x = x * (1.0 - w) + AKSynthCore._shape(a + 1, q, d, 0.5, core._sinc_blep) * w
						elif shape == SH_TABLE:
							x = AKSynthCore._table(tab, pos, o_mip[j], q, o_zone[j])
							if o_zw[j] > 0.0:
								x += (AKSynthCore._table(tab, pos, o_mip[j], q, o_zone[j] + 1) - x) * o_zw[j]
						else:
							x = AKSynthCore._shape(shape, q, absf(d), width if shape == SH_PULSE else 0.5, core._sinc_blep)
					if bls:
						x += sync_c[sb + k]
						sync_c[sb + k] = 0.0
						if reset >= 0.0:
							var po := pm / TAU
							var qa := po - floorf(po)
							var qb := ph + (1.0 - reset) * d + po
							qb -= floorf(qb)
							var jmp := AKSynthCore._naive(shape, qa, width, pos, tab, o_mip[j], o_zone[j], o_zw[j]) \
								- AKSynthCore._naive(shape, qb, width, pos, tab, o_mip[j], o_zone[j], o_zw[j])
							# Restarting just past phase 0, the next sample's own band-limiting already
							# smooths the waveform's natural jump there: carry only the rest.
							var jnat := 0.0
							if pm == 0.0 and shape != SH_TABLE and shape != SH_SINE:
								jnat = AKSynthCore._naive(shape, 0.0, width, pos, tab, o_mip[j], o_zone[j], o_zw[j]) 									- AKSynthCore._naive(shape, 1.0 - 1e-9, width, pos, tab, o_mip[j], o_zone[j], o_zw[j])
							x += jmp * reset * reset * 0.5
							sync_c[sb + k] = -(jmp - jnat) * (1.0 - reset) * (1.0 - reset) * 0.5
					if ring >= 0:
						x *= raw[ring * MAX_SLOT + core._smap[mb + ring * MAX_SLOT + k]]
					if le >= 0:
						x *= eg
					if fb != 0.0:
						fbp[sb + k] = raw[sb + k]
					raw[sb + k] = x
					ph = reset * d if reset >= 0.0 else ph + d
					if ph >= 1.0:
						ph -= floorf(ph)
						wrap_t[sb + k] = ph / d
					else:
						wrap_t[sb + k] = -1.0
						if ph < 0.0:
							ph -= floorf(ph)
					phase[sb + k] = ph
					if stereo:
						acc += x * core._swl[sb + k]
						acc_r += x * core._swr[sb + k]
					else:
						acc += x * core._sw[sb + k]
				acc *= core._oinv[j]
				acc_r *= core._oinv[j]
			if core._bypass and not bool(o.get("filtered", true)):
				dry += o_level[j] * acc * core._opl[j]
				dry_r += o_level[j] * acc_r * core._opr[j]
			elif not core._f2_on or int(o.get("route", 0)) == 0:
				mix += o_level[j] * acc * core._opl[j]
				mix_r += o_level[j] * acc_r * core._opr[j]
			else:
				# Filter 2 only (1), or both filters (2: parallel).
				var av := o_level[j] * acc * core._opl[j]
				var ar := o_level[j] * acc_r * core._opr[j]
				if int(o.route) == 2:
					mix += av
					mix_r += ar
				mix2 += av
				mix2_r += ar
		if core._comb_on:
			mix = _comb(core, mix, 0)
			if stereo:
				mix_r = _comb(core, mix_r, COMB_MAX)
			cw = (cw + 1) % COMB_MAX
		if core._pre_lp > 0.0:
			plp[0] += (mix - plp[0]) * core._pre_lp
			mix = plp[0]
			if stereo:
				plp[1] += (mix_r - plp[1]) * core._pre_lp
				mix_r = plp[1]
		if core._pre_hp > 0.0:
			php[0] += (mix - php[0]) * core._pre_hp
			mix -= php[0]
			if stereo:
				php[1] += (mix_r - php[1]) * core._pre_hp
				mix_r -= php[1]
		if core._fb_on:
			# The filter block's last output, through tanh, back into filter 1 (Surge's feedback).
			mix += o_fb * tanh(fby[0])
			if stereo:
				mix_r += o_fb * tanh(fby[1])
		var y := mix
		var ft := int(c.filter_type)
		if ft == F_COMB:
			y = f1x.tick(c, y, false)
			if stereo:
				mix_r = f1x.tick(c, mix_r, true)
		elif ft == F_LADDER:
			y = _ladder(core, y, 0)
			if stereo:
				mix_r = _ladder(core, mix_r, 4)
		elif ft > 0 and c.diode:
			# The diode pair's damping follows each stage's band state, sample by sample (OB-Xf's
			# resolveFeedback2Pole): the same filter, its coefficients from that damping.
			for st in int(c.stages):
				y = _diode_stage(c, y, st, false)
				if stereo:
					mix_r = _diode_stage(c, mix_r, st, true)
		elif ft > 0:
			for st in int(c.stages):
				var v3 := y - ic2[st]
				var v1 := a1 * ic1[st] + a2 * v3
				var v2 := ic2[st] + a2 * ic1[st] + a3 * v3
				ic1[st] = 2.0 * v1 - ic1[st]
				ic2[st] = 2.0 * v2 - ic2[st]
				match ft:
					1: y = v2
					2: y = y - fk * v1 - v2
					3: y = v1
					4: y = y - fk * v1
					_: y = sm0 * y + sm1 * v1 + sm2 * v2
				if stereo:
					var r3 := mix_r - ic2r[st]
					var r1 := a1 * ic1r[st] + a2 * r3
					var r2 := ic2r[st] + a2 * ic1r[st] + a3 * r3
					ic1r[st] = 2.0 * r1 - ic1r[st]
					ic2r[st] = 2.0 * r2 - ic2r[st]
					match ft:
						1: mix_r = r2
						2: mix_r = mix_r - fk * r1 - r2
						3: mix_r = r1
						4: mix_r = mix_r - fk * r1
						_: mix_r = sm0 * mix_r + sm1 * r1 + sm2 * r2
		var sg := float(c.sat_g)
		if sg > 0.0:
			# Saturation after the filter, before the amp (Synth1's): c (1 - e^-|u|), u = g x / c.
			var sc := float(c.sat_c)
			if core._sat_tanh:
				y = sc * tanh(sg * y / sc)
				if stereo:
					mix_r = sc * tanh(sg * mix_r / sc)
			else:
				var u := sg * y / sc
				y = sc * (1.0 - exp(-u)) if u >= 0.0 else -sc * (1.0 - exp(u))
				if stereo:
					u = sg * mix_r / sc
					mix_r = sc * (1.0 - exp(-u)) if u >= 0.0 else -sc * (1.0 - exp(u))
		if core._f2_on:
			# Series: filter 1's output and filter 2's own oscillators into filter 2; parallel: summed.
			if core._routing == 0:
				y = f2.tick(core._f2, y + mix2, false)
				if stereo:
					mix_r = f2.tick(core._f2, mix_r + mix2_r, true)
			else:
				y += f2.tick(core._f2, mix2, false)
				if stereo:
					mix_r += f2.tick(core._f2, mix2_r, true)
		if core._fb_on:
			fby[0] = y
			fby[1] = mix_r
		if core._bypass:
			y += dry
			mix_r += dry_r if stereo else dry
		gvel += (vel - gvel) * core._vel_k
		var vc := float(c.get("vel_curve", 1.0))
		var gv := gvel if vc == 1.0 else pow(gvel, vc)
		var amp := e0 * (1.0 - float(c.vel_sens) * (1.0 - gv)) * amp_mod * float(c.gain)
		if slot >= 0:
			amp *= s_gain
		y *= amp
		yr = mix_r * amp
		# A stages amp envelope ends its voice once no stage ahead can rise again; a dx7 one when msfa's
		# note would end (it can pass level 4 with the key down, when levels 3 and 4 are both silent).
		if _env_done(core, 0):
			active = false
		elif not core._carrier_envs.is_empty():
			var all_done := true
			for k in core._carrier_envs:
				if not _env_done(core, k):
					all_done = false
					break
			if all_done:
				active = false
		return y

	## envN.time at note-on, before the first stages begin: the rows from sources a note has at its
	## start (velocity, key, random, the controllers, macros; envelopes and LFOs read 0).
	func _note_time_mods(core: AKSynthCore) -> void:
		etf.fill(1.0)
		ets.fill(1.0)
		var m_et := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
		var m_es := PackedFloat64Array()
		m_es.resize(24)
		var any := false
		for row: Dictionary in core._p.mods:
			if int(row.dst) < D_E1T or int(row.dst) == D_FB:
				continue
			if not any:
				any = true
				src.fill(0.0)
				src[SRC_VEL] = gvel
				src[SRC_KEY] = (target - 60.0) / 12.0
				src[SRC_MOD] = gmod
				src[SRC_TOUCH] = gtouch
				src[SRC_RANDOM] = rnd
				src[SRC_BEND] = core.bend
				for k in 4:
					src[SRC_MAC1 + k] = core._macros[k]
			var x := float(row.amount) * src[int(row.src)]
			var via := int(row.get("via", -1))
			if via >= 0:
				x *= src[via]
			var via2 := int(row.get("via2", -1))
			if via2 >= 0:
				x *= src[via2]
			if int(row.dst) >= D_E1A:
				var d := int(row.dst) - D_E1A
				m_es[(d % 8) * 3 + floori(d / 8.0)] += x
			else:
				m_et[int(row.dst) - D_E1T] += x
		for k in 8:
			if m_et[k] != 0.0:
				etf[k] = pow(2.0, m_et[k])
		for k in 24:
			if m_es[k] != 0.0:
				ets[k] = pow(2.0, m_es[k])

	## An envelope has finished: released (or, dx7, past msfa's last stage) and silent, with no stage
	## ahead that could rise again.
	func _env_done(core: AKSynthCore, k: int) -> bool:
		if level[k] >= SILENT:
			return false
		match core._env_kind[k]:
			K_DX7:
				# Silent blocks (msfa's gain threshold) don't end a note; msfa's note ending does.
				return dead[k] != 0 or killing
			K_STAGES:
				return stage[k] == RELEASE and si[k] >= int(core._p.env[k].quiet)
			K_CZ:
				return killing or (stage[k] == RELEASE and czi[k] >= int(core._p.env[k].end) and czc[k] == czt[k])
			_:
				return stage[k] == RELEASE

	## The comb on one channel (line from `base`): y = x + feedback x y one period back, read between
	## samples by a straight line. The caller moves the write position.
	func _comb(core: AKSynthCore, x: float, base: int) -> float:
		var core_fb := cfb
		var rp := float(cw) - cper
		if rp < 0.0:
			rp += float(COMB_MAX)
		var i := floori(rp)
		var f := rp - float(i)
		var a := comb[base + i]
		var b := comb[base + (i + 1) % COMB_MAX]
		var y := x + core_fb * (a + (b - a) * f)
		comb[base + cw] = y
		return y

	## The four-pole ladder (zero-delay feedback, solved per sample), states
	## lad[s0 .. s0 + 3], with tanh saturation at its input. The output is the fourth pole, or (poles,
	## pole_mix) fewer poles or a mix of them with the input.
	## One diode-damped state-variable stage (ak::SynthVoice::diode_stage), on the left or right states.
	func _diode_stage(c: Dictionary, x: float, st: int, right: bool) -> float:
		var i1: float = ic1r[st] if right else ic1[st]
		var i2: float = ic2r[st] if right else ic2[st]
		var u := i1 * 0.0876
		var k := fk + 2.0 * (((((0.0103592 * u + 0.00920833) * u + 0.185) * u + 0.05) * u + 1.0) - 1.0)
		var b1 := 1.0 / (1.0 + fg * (fg + k))
		var b2 := fg * b1
		var b3 := fg * b2
		var v3 := x - i2
		var v1 := b1 * i1 + b2 * v3
		var v2 := i2 + b2 * i1 + b3 * v3
		if right:
			ic1r[st] = 2.0 * v1 - i1
			ic2r[st] = 2.0 * v2 - i2
		else:
			ic1[st] = 2.0 * v1 - i1
			ic2[st] = 2.0 * v2 - i2
		match int(c.filter_type):
			1: return v2
			2: return x - k * v1 - v2
			3: return v1
			4: return x - k * v1
		return float(c.f_high) * x + (float(c.f_band) - k * float(c.f_high)) * v1 + (float(c.f_low) - float(c.f_high)) * v2

	func _ladder(core: AKSynthCore, x: float, s0: int) -> float:
		var c: Dictionary = _core_p
		var G := lG
		var b := lbeta
		var S := G * G * G * b * lad[s0] + G * G * b * lad[s0 + 1] + G * b * lad[s0 + 2] + b * lad[s0 + 3]
		var drive := float(c.drive)
		var u := (x - lk * S) / (1.0 + lk * G * G * G * G)
		# Soft saturation, linear until |u| nears 2 / drive.
		u = tanh(u * drive * 0.5) * 2.0 / drive
		if core._lmode == 0:
			for i in 4:
				var v := (u - lad[s0 + i]) * G
				var yy := v + lad[s0 + i]
				lad[s0 + i] = yy + v
				u = yy
			# Make up some of the bass a resonant ladder loses.
			return u * (1.0 + 0.5 * lk)
		var p0 := u
		var y1 := 0.0
		var y2 := 0.0
		var y3 := 0.0
		for i in 4:
			var v := (u - lad[s0 + i]) * G
			var yy := v + lad[s0 + i]
			lad[s0 + i] = yy + v
			u = yy
			if i == 0:
				y1 = u
			elif i == 1:
				y2 = u
			elif i == 2:
				y3 = u
		var out := 0.0
		if core._lmode == 2:
			var m: PackedFloat64Array = core._lmix
			out = m[0] * p0 + m[1] * y1 + m[2] * y2 + m[3] * y3 + m[4] * u
		else:
			var p := core._lpoles
			var lo := floori(p)
			var w := p - float(lo)
			var ys := [p0, y1, y2, y3, u]
			out = float(ys[lo]) if w == 0.0 else float(ys[lo]) * (1.0 - w) + float(ys[lo + 1]) * w
		return out * (1.0 + 0.5 * lk)
