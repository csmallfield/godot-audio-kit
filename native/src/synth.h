// SPDX-License-Identifier: Apache-2.0
// The polyphonic synth engine, free of Godot types. It mirrors AKSynthCore
// (addons/audio_kit/synth/synth_core.gd) step for step: the GDScript version
// is the reference and the fallback; this one is what plays live and bakes
// fast. The same events give the same samples, live or offline.
#pragma once
#include "dsp.h"
#include "fx.h"

#include <cstdint>
#include <memory>
#include <vector>

namespace ak {

struct SynthPatch {
	static constexpr int MAX_OSC = 16;
	static constexpr int MAX_U = 16;
	// Copies of one oscillator inside each unison voice (its stack), and the
	// phase slots per oscillator (unison voices x stack, at most 64: a stack is
	// cut to fit under wide unison).
	static constexpr int MAX_STACK = 16;
	static constexpr int MAX_SLOT = 64;
	static constexpr int MAX_MODS = 32;
	static constexpr int MAX_ENV = 8;
	static constexpr int MAX_STAGES = 32;
	struct Osc {
		int shape = 0;
		double level = 1.0, semis = 0.0, width = 0.5, position = 0.0, fm_index = 0.0, pan = 0.0;
		bool filtered = true;
		int fm_from = -1, sync = -1, ring = -1, table = -1;
		int stack = 1;
		double stack_cents = 0.0;
		double dr = 1.0;  // its share of the patch's drift
		int fm_mode = 0;  // 0 phase, 1 pitch (semitones), 2 linear (Hz)
		double phase0 = -1.0;  // start phase in cycles (-1: as before)
		int phase_with = -1;   // take this oscillator's start phases (-1: none)
		int ncolor = 0;        // noise: 0 white, 1 pink, 2 red
		int route = 0;         // with filter 2: 0 filter 1 (series: then 2), 1 filter 2 only, 2 both
		int sample = -1;       // a sample layer: its sound in samples (-1: none, silent)
		double track = 1.0;    // how far the sample follows the key (0: at its root on every key)
		double s_start = 0.0;  // where it starts, in frames of the sound
		int pbase = 0, pn = 0;  // partials / modal: its modes in the patch's `modes` and the voice's bank
		int excite = -1;        // modal: the oscillator it resonates (-1: struck once at note-on)
		// grains: the source (a shape: sine, triangle, saw, square, noise or sample), grains per
		// second, grain length (s), timing jitter, pitch spray (semitones), pan spread, position
		// jitter (sample source), window (0 hann, 1 tri, 2 perc) and each grain's level.
		int gsrc = 0, genv = 0;
		double gdens = 20.0, glen = 0.05, gjit = 0.0, gspray = 0.0, gpan = 0.0, gposj = 0.0, glev = 1.0;
	};
	// Phase 2 operator fields per oscillator (AKPatch._compile_operator): more
	// modulators, feedback, frequency (ratio, fixed, dx7), its own envelope,
	// velocity and key scaling. Apart from Osc, so today's patches don't carry them
	// through the per-sample loop.
	struct OscOp {
		int n_fm = 0;
		int fm_src[MAX_OSC] = {};
		double fm_amt[MAX_OSC] = {};
		double feedback = 0.0, ratio = 1.0, fixed_hz = 0.0;
		int dx_mode = -1, dx_coarse = 1, dx_fine = 0, dx_detune = 7;
		int level_env = -1;
		double vel_sens = 0.0;
		bool ks = false, ks_lexp = false, ks_rexp = false;
		double ks_break = 60.0, ks_l = 0.0, ks_r = 0.0;
		// Phase 4: envelopes for the phase distortion amount and the pitch (semitones), and
		// a pd oscillator's two waves, window and noise pitch modulation (the CZ's uPD933).
		int shape_env = -1, pitch_env = -1;
		int pd_w1 = 0, pd_w2 = 0, pd_win = 0;
		bool pd_noise = false;
	};
	// A wavetable as AKWavetables.build() makes it: [zone][frame][level][sample],
	// with each zone's key (ascending).
	struct Table {
		int frames = 1, size = 1024, levels = 19, lv0 = 0, zones = 1;
		bool blend = true;
		std::vector<double> keys;
		std::vector<float> data;
	};
	std::vector<std::shared_ptr<const Table>> tables;
	// A sample layer's sound (AKPatch._compile_sample_osc): mono, trimmed, at `rate`, played
	// at its own pitch on the `root` note; looping le - ls frames from ls once it passes le.
	struct Sample {
		std::vector<float> data;
		double rate = 48000.0, root = 60.0, ls = 0.0, le = 0.0, inc = 1.0;  // inc: rate / root's Hz
		bool loop = false;
	};
	std::vector<std::shared_ptr<const Sample>> samples;
	// Partials and modal oscillators' modes (AKPatch._compile_partials): ratio to the oscillator's
	// pitch, level and decay time (0: none), MAX_MODES in all.
	static constexpr int MAX_MODES = 64;
	int n_modes = 0;
	double mode_ratio[MAX_MODES] = {}, mode_level[MAX_MODES] = {}, mode_decay[MAX_MODES] = {};
	// Derived when parsed: which oscillators others read (fm or ring) and
	// which are sync masters, so the rest can skip that bookkeeping.
	bool is_source[MAX_OSC] = {}, is_master[MAX_OSC] = {};
	// Per oscillator: nothing reads it and it reads nothing (the unrolled path,
	// when the patch is mono), and it uses no phase 2 operator field.
	bool plain[MAX_OSC] = {};
	void derive() {
		for (int j = 0; j < MAX_OSC; j++) {
			is_source[j] = is_master[j] = false;
		}
		for (int j = 0; j < n_osc; j++) {
			if (osc[j].fm_from >= 0) {
				is_source[osc[j].fm_from] = true;
			}
			for (int m = 0; m < op[j].n_fm; m++) {
				is_source[op[j].fm_src[m]] = true;
			}
			if (osc[j].ring >= 0) {
				is_source[osc[j].ring] = true;
			}
			if (osc[j].sync >= 0) {
				is_master[osc[j].sync] = true;
			}
		}
		for (int j = 0; j < n_osc; j++) {
			const Osc &o = osc[j];
			plain[j] = o.sync < 0 && o.ring < 0 && o.fm_from < 0 && !is_source[j] && !is_master[j] && op[j].n_fm == 0 &&
					op[j].feedback == 0.0 && op[j].level_env < 0 && op[j].shape_env < 0 && op[j].pitch_env < 0;
		}
	}
	double spread = 0.0;
	// An envelope (AKPatch._compile_env): kind 0 ADSR, 1 stages, 2 dx7.
	struct Env {
		int kind = 0;
		double a = 0.0, d = 0.2, s = 0.0, r = 0.15, r2 = 0.0, knee = 0.0;
		bool exp = false;
		// Stages: per stage its time, level, curve (0 linear, 1 power, 2 hold)
		// and power amount; the sustain stage (-1: one-shot), the loop, the
		// level at note-on, per-note time and level scaling (masks: which
		// stages), and the stage from which every level is silent.
		int n = 0;
		double time[MAX_STAGES] = {}, level[MAX_STAGES] = {}, amount[MAX_STAGES] = {};
		int curve[MAX_STAGES] = {};
		int sustain = -1, loop_a = -1, loop_b = -1, quiet = 0;
		bool trig = false;  // started by the key-up (a one-shot stages envelope held at 0 until then)
		double start = 0.0, tk = 0.0, tk_center = 60.0, tv = 0.0, lv = 0.0;
		int64_t tk_mask = 0, tv_mask = 0;
		// dx7: raw DX7 values.
		int rates[4] = { 99, 99, 99, 99 }, levels[4] = { 99, 99, 99, 0 };
		int ol = 99, rs = 0, vs = 0, bp = 39, ld = 0, rd = 0, lc = 0, rc = 0;
		int ams = 0, ko = 0;
		// cz: the CZ's 8-step envelope in the uPD933's own values: what it drives (0 DCA
		// level, 1 DCW, 2 DCO pitch), each step's rate and level (0-127; a DCO level's bit 6
		// picks 2-semitone units), the sustain step (-1: none) and the end step.
		int czk = 0, cz_n = 0, cz_sus = -1, cz_end = 0;
		int cz_rate[8] = {}, cz_level[8] = {};
	};
	struct Lfo {
		int shape = 0;
		double rate_hz = 1.0, delay_s = 0.0, width = 0.5, phase = 0.0;
		bool free = false;
		double beats = 0.0;  // tempo-synced: beats per cycle (0: rate_hz)
		// A DX7 LFO (msfa lfo.cc), raw values.
		bool dx7 = false, sync = true;
		int speed = 35, delay = 0, wave = 0, pmd = 0, pms = 0, amd = 0;
		// A custom shape (shape 6): its points, linear (0) or step (1), one-shot.
		std::vector<double> pts;
		int interp = 0;
		bool once = false;
	};
	static constexpr int MAX_LFO = 8;
	static constexpr int MAX_SLOTS = 32;
	static constexpr int COMB_MAX = 4096;
	struct Mod {
		int src = 0, dst = 0, osc = -1;
		int via = -1;  // a second source the row is multiplied by (-1: none)
		int via2 = -1;  // and a third
		double amount = 0.0;
	};
	Osc osc[MAX_OSC];
	int n_osc = 1;
	bool has_grains = false;  // an oscillator is `grains` (the voices keep a grain bank)
	int unison = 1;
	double detune_cents = 0.0, unison_level = 1.0, unison_pitch = 0.0;
	// A voice filter (filter 1, or filter 2): type, slopes, cutoff, q, the ladder's resonance,
	// drive, poles and pole mix (lmode 0 the fourth pole, 1 poles, 2 pole_mix), the state-variable
	// mix weights, the shelves' gain; a 2-pole state-variable filter's diode-pair damping
	// (OB-Xf's): damping = 1 / (2 q), or `damping` (which may be negative: it self-oscillates),
	// plus the diodes' term on the band state.
	struct Filt {
		int type = 1, stages = 1;
		double cutoff_hz = 18000.0, q = 0.707, resonance = 0.3, drive = 1.0;
		int lmode = 0;
		double poles = 4.0, pole_mix[5] = { 0, 0, 0, 0, 0 };
		double f_low = 1.0, f_band = 0.0, f_high = 0.0, gain_db = 0.0;
		bool diode = false;
		double damping = 0.0;
		double cfb = 0.5;  // the comb type's feedback (comb_feedback), -0.99..0.99
		double cdamp = 0.0;  // the comb type's damping cutoff in Hz (comb_damp_hz), 0 = off
		// The formant type: vowel 0..1 (a e i o u), shift in semitones, Q scale, voice set (0 bass .. 3 soprano).
		double vowel = 0.0, fshift = 0.0, fq = 1.0;
		int fset = 1;
	};
	Filt f1, f2;
	bool f2_on = false;
	int routing = 0;  // filter 2: 0 series (after filter 1), 1 parallel
	double macros[4] = { 0, 0, 0, 0 };  // macro1 .. macro4 (sources)
	// The pre-filter, the comb.
	double pre_lp_hz = 0.0, pre_hp_hz = 0.0;
	bool comb_on = false;
	double inc_max = 1e9;  // the highest oscillator phase increment (nyquist_clamp: MAX_INC)
	bool bl_sync = false;  // band-limited hard sync
	bool sinc_blep = false;  // the windowed-sinc BLEP on saw and pulse edges (ak::blep_sinc)
	// Saturation after the filter (filter.sat_gain_db, sat_ceiling): small-signal gain (0 = off) and ceiling.
	double sat_g = 0.0, sat_c = 1.0;
	double comb_semis = 0.0, comb_fb = 0.0;
	double comb_damp_hz = 0.0, comb_damp_track = 0.0;  // the comb's damping (0 = off) and its key tracking
	double drift_c = 0.0, drift_rate = 0.5;  // oscillator drift: depth in cents (0 = off), new targets a second
	// Voice slots: each one's pan, and the slop ranges.
	int slots = 0;
	double voice_pan[MAX_SLOTS] = {};
	double slop_pitch = 0.0, slop_cut = 0.0, slop_time = 0.0, slop_level = 0.0;
	int n_lfo = 2;
	Lfo lfo[MAX_LFO];
	Mod mods[MAX_MODS];
	int n_mods = 0;
	int mode = 0, poly = 8;
	int prio = 0;  // mono/legato note priority: 0 last, 1 low, 2 high
	bool rzero = false;  // mono retrigger: envelopes from zero
	double glide_s = 0.0, bend_range = 2.0, vel_sens = 0.5, vel_curve = 1.0, gain = 1.0, pan = 0.0;
	// Level by key: key, gain, key, gain ... (sorted), straight lines in dB.
	std::vector<double> key_lv;
	double tempo_bpm = 120.0;
	// The arpeggiator (AKPatch._compile_arp).
	struct Arp {
		bool on = false;
		int mode = 0, octaves = 1;
		double beats = 0.25, gate = 0.5;
	} arp;
	int64_t seed = 0;
	// Patch effects (chorus, phaser ...), run on the summed voices in order.
	std::vector<Fx> effects;
	// The saturation's curve: c tanh(g x / c) instead of c (1 - e^-|u|).
	bool sat_tanh = false;
	// Filter feedback (filter_feedback): the filter block's output, through tanh, back into
	// filter 1's input; on when set or a matrix row moves it.
	double fb = 0.0;
	bool fb_on = false;
	// Last: large, and only the envelope code reads it.
	int n_env = 3;
	Env env[MAX_ENV];
	OscOp op[MAX_OSC];
};

class SynthEngine;

// Modulation is worked out every CONTROL samples and held between
// (as AKSynthCore.CONTROL).
constexpr int CONTROL = 8;
constexpr int N_SRC = 26;
// Matrix destinations (pitch .. env8.time).
constexpr int N_DST = 58;
// The dx7 mode: msfa's block, and its level for envelope level 99 at output level 99 (gain 1).
constexpr int DX7_N = 64;
constexpr int64_t DX7_FULL = 251658240;

// msfa's Env (env.cc, Dexed, Apache-2.0; ACCURATE_ENVELOPE), as AKSynthCore._Dx7:
// the same integer steps, so its levels come out exactly.
struct Dx7Env {
	int64_t level = 0, target = 0, inc = 0, staticcount = 0;
	bool rising = false, down = true;
	int ix = 0;
	int64_t outlevel = 0, rate_scaling = 0, srm = 0;
	void advance(const SynthPatch::Env &e, int newix);
	int64_t getsample(const SynthPatch::Env &e);
};
int64_t dx7_outlevel(const SynthPatch::Env &e, int midinote, int midivel);
int64_t dx7_rate_scaling(const SynthPatch::Env &e, int midinote);
int64_t dx7_osc_logfreq(int midinote, int mode, int coarse, int fine, int detune);
int64_t dx7_amp_mod(int64_t lq, int64_t amd, int ams);
int64_t dx7_sin(int64_t phase);
double dx7_sinf(double q);
void dx7_tables();

// msfa's PitchEnv (pitchenv.cc), as AKSynthCore._Dx7P.
struct Dx7PEnv {
	int64_t level = 0, target = 0, inc = 0, unit = 0;
	bool rising = false, down = true;
	int ix = 0;
	void set_up(const SynthPatch::Env &e);
	void advance(const SynthPatch::Env &e, int newix);
	int64_t getsample(const SynthPatch::Env &e);
};

// msfa's Lfo (lfo.cc) and Dx7Note's use of it, as AKSynthCore._Dx7Lfo.
struct Dx7Lfo {
	int64_t phase = 0, delta = 0, rand = 0, dstate = 0, dinc = 0, dinc2 = 0;
	int64_t pitch_mod = 0, amd = 0;
	void reset(int64_t unit, int64_t ratio, const SynthPatch::Lfo &l);
	int64_t getsample(int wave);
	int64_t getdelay();
	void step(const SynthPatch::Lfo &l);
};

// One voice filter's state (filter 1 or 2) and its coefficients from the last control step.
struct FiltState {
	// The state-variable stages' states, [channel][stage].
	double ic1[2][2] = {}, ic2[2][2] = {};
	double lad[8] = {};
	double last_c = -1.0, last_q = -1.0, fk = 1.0, a1 = 0, a2 = 0, a3 = 0, fg = 0.0;
	double lg = 0, lG = 0, lbeta = 0, lk = 0;
	double sm0 = 0.0, sm1 = 0.0, sm2 = 0.0;
	// The comb type: its line (left, right; in the engine's pool, null when the voice has none),
	// write positions, period in samples and feedback.
	double *cb = nullptr;
	int cbw[2] = { 0, 0 };
	double cbper = 1.0, cbfb = 0.0;
	double cbda = 0.0, cbds[2] = { 0.0, 0.0 };  // its damping: coefficient (0 = off), states
	double comb(int ch, double x);
	// The formant type: per formant a1, a2, a3, k, level; states (left, right); what they were made for.
	double fmc[5][5] = {}, fms1[2][5] = {}, fms2[2][5] = {};
	double fm_v = -1.0, fm_sh = 0.0, fm_qm = 0.0;
	bool fm_ready = false;
	void formant_control(const SynthPatch::Filt &c, double m_cut, double m_q, double sr, double m_vow);
	double formant(int ch, double x);
	void reset() {
		cbw[0] = cbw[1] = 0;
		cbds[0] = cbds[1] = 0.0;
		for (int ch = 0; ch < 2; ch++) {
			for (int i = 0; i < 5; i++) {
				fms1[ch][i] = fms2[ch][i] = 0.0;
			}
		}
		fm_v = -1.0;
		ic1[0][0] = ic1[0][1] = ic2[0][0] = ic2[0][1] = 0.0;
		ic1[1][0] = ic1[1][1] = ic2[1][0] = ic2[1][1] = 0.0;
		for (int i = 0; i < 8; i++) {
			lad[i] = 0.0;
		}
		last_c = -1.0;
		last_q = -1.0;
	}
	void control(const SynthPatch::Filt &f, double m_cut, double m_q, double sr, double m_vow = 0.0);
	double svf_weights(const SynthPatch::Filt &f, double g);
	double ladder(const SynthPatch::Filt &f, double x, int s0);
	double diode_stage(const SynthPatch::Filt &f, double x, double &i1, double &i2);
	// One channel (right: the right states) through the filter; type 0 passes it.
	// One sample on the left (R false) or right channel's state, chosen at compile time.
	template <bool R> double tick(const SynthPatch::Filt &f, double x);
};

struct SynthVoice {
	static constexpr int MAX_OSC = SynthPatch::MAX_OSC;
	static constexpr int MAX_U = SynthPatch::MAX_U;
	static constexpr int MAX_SLOT = SynthPatch::MAX_SLOT;
	bool active = false, gated = false, pedal = false, killing = false;
	int64_t serial = 0;
	double note = 60.0, target = 60.0, cur = 60.0, vel = 1.0, rnd = 0.0;
	double gvel = 1.0;  // the velocity as heard: follows vel over VEL_GLIDE_S
	double gmod = 0.0, gtouch = 0.0;  // mod wheel and aftertouch as heard (CTL_GLIDE_S)
	uint32_t rng = 1;
	double gl = 1.0, gr = 1.0;
	static constexpr int MAX_ENV = SynthPatch::MAX_ENV;
	int stage[MAX_ENV] = { 4, 4, 4, 4, 4, 4, 4, 4 };
	int64_t t[MAX_ENV] = {};
	double level[MAX_ENV] = {}, start_level[MAX_ENV] = {}, ev[MAX_ENV] = { 1, 1, 1, 1, 1, 1, 1, 1 };
	double rel_from[MAX_ENV] = {};  // each envelope's level at key-up
	static constexpr int MAX_LFO = SynthPatch::MAX_LFO;
	double lfo_ph[MAX_LFO] = {}, lfo_sh[MAX_LFO] = {};
	double lfo_sh0[MAX_LFO] = {};  // smooth random: where each cycle starts (lfo_sh: where it goes)
	// The matrix's push on each LFO's rate, in octaves (from the last control step).
	double lfo_oct[MAX_LFO] = {};
	bool lfo_done[MAX_LFO] = {};  // a one-shot custom LFO has run its cycle
	// The voice slot (-1: none) and its pan, pitch, cutoff, gain and envelope time factor.
	int slot = -1;
	double s_pan = 0.0, s_pitch = 0.0, s_cut = 0.0, s_gain = 1.0, s_tf = 1.0;
	// ADSR numbers with this voice's envelope time factor (slop), when it has one.
	bool vtime = false;
	int64_t va[MAX_ENV] = {}, vd[MAX_ENV] = {};
	double vkd[MAX_ENV] = {}, vkr[MAX_ENV] = {}, vkr2[MAX_ENV] = {};
	// Filter 1 and filter 2; pre-filter states; the comb's lines (left, right: the engine's
	// pool), write position and period.
	FiltState fs[2];
	double plp[2] = {}, php[2] = {};
	double *comb = nullptr;
	int cw = 0;
	double cper = 1.0;
	double cfb = 0.0;  // the comb's feedback for this voice (comb.feedback rows)
	double cda = 0.0, cds[2] = { 0.0, 0.0 };  // the comb's damping: coefficient (0 = off), states
	int64_t age = 0;
	double phase[MAX_OSC * MAX_SLOT] = {};
	double raw[MAX_OSC * MAX_SLOT] = {};
	double last_semi[MAX_OSC] = {};
	// Drift: its own random stream; per oscillator the wander's start, target, phase (0..1) and
	// current offset in semitones.
	uint32_t drng = 1;
	double dfrom[MAX_OSC] = {}, dto[MAX_OSC] = {}, dph[MAX_OSC] = {}, dv[MAX_OSC] = {};
	double freq[MAX_OSC] = {};
	// The matrix sources, then a constant 1 (SRC_ONE: a row's missing via).
	double src[N_SRC + 1] = {};
	double mo[5 * MAX_OSC] = {};
	double o_level[MAX_OSC] = {}, o_idx[MAX_OSC] = {}, o_width[MAX_OSC] = {}, o_pos[MAX_OSC] = {};
	double amp_mod = 1.0;
	double dt[MAX_OSC * MAX_SLOT] = {};
	double yr = 0.0;
	double wrap_t[MAX_OSC * MAX_SLOT] = {};
	int o_mip[MAX_OSC] = {}, o_zone[MAX_OSC] = {};
	double o_zw[MAX_OSC] = {};
	// Each envelope's time factor from the matrix (envN.time), read as its stages start.
	double etf[SynthPatch::MAX_ENV] = { 1, 1, 1, 1, 1, 1, 1, 1 };
	// (Kept after the per-sample state.) How many envelopes this voice runs; a key change waiting for a stages or
	// dx7 envelope's next tick (1 retrigger, 2 release).
	int ne = 3;
	int pend[MAX_ENV] = {};
	// Stages envelopes (as AKSynthCore._Voice): stage, its length (or ST_HOLD,
	// ST_FALL), from and to levels, the power curve's running exponential, step
	// and denominator (0: straight), and the note's time and level factors.
	int si[MAX_ENV] = {};
	int64_t sn[MAX_ENV] = {};
	double sfrom[MAX_ENV] = {}, sto[MAX_ENV] = {}, sg[MAX_ENV] = {}, sk[MAX_ENV] = {}, sden[MAX_ENV] = {};
	double tkf[MAX_ENV] = {}, tvf[MAX_ENV] = {}, lsc[MAX_ENV] = {};
	// dx7 envelopes: msfa's state, gains at the last two block steps, finished.
	Dx7Env dx[MAX_ENV];
	double dg1[MAX_ENV] = {}, dg2[MAX_ENV] = {};
	bool dead[MAX_ENV] = {};
	bool rtrig[MAX_ENV] = {};  // envelopes started by the key-up (trigger = "release")
	bool dq[MAX_ENV] = {};  // a dx7 envelope's block is below msfa's gain threshold
	Dx7PEnv dxp[MAX_ENV];
	Dx7Lfo dlfo[2];
	// Phase 2 operators: outputs two samples back (feedback), per-note level
	// factors, a dx7 operator's key, Q24 log frequency and increment.
	double fbp[MAX_OSC * MAX_SLOT] = {};
	// Band-limited sync: each slot's correction carried to its next sample.
	double sync_c[MAX_OSC * MAX_SLOT] = {};
	// Pink and red noise filter states, three per oscillator.
	double nzs[3 * MAX_OSC] = {};
	double o_kv[MAX_OSC] = {};
	int o_dxnote[MAX_OSC] = {};
	int64_t o_dxbase[MAX_OSC] = {};
	double o_inc[MAX_OSC] = {};
	// lfo3 .. lfo8's own random streams (AKSynthCore's lrng).
	uint32_t lrng[SynthPatch::MAX_LFO] = { 1, 1, 1, 1, 1, 1, 1, 1 };
	// cz envelopes: the chip's current value and target (its own units), rate per 40 kHz
	// sample, step, direction (down) and whether the key-off has been taken.
	double czc[MAX_ENV] = {}, czt[MAX_ENV] = {}, czr[MAX_ENV] = {};
	int czi[MAX_ENV] = {};
	bool czd[MAX_ENV] = {}, czrel[MAX_ENV] = {};
	// pd oscillators: which of the two waves each slot is on, and the noise modulation's
	// clock and pitch factor.
	uint8_t pdb[MAX_OSC * MAX_SLOT] = {};
	double pdn_t[MAX_OSC] = {}, pdn_m[MAX_OSC] = {};
	double spos[MAX_OSC] = {};  // a sample layer's play position (frames of its sound)
	// Partials / modal: each mode's state (a phasor), its rotation per sample (with its decay)
	// and its level now (0 above Nyquist).
	double mzr[SynthPatch::MAX_MODES] = {}, mzi[SynthPatch::MAX_MODES] = {};
	double mcr[SynthPatch::MAX_MODES] = {}, mci[SynthPatch::MAX_MODES] = {}, mlv[SynthPatch::MAX_MODES] = {};
	// Grains: the voice's bank (owner oscillator or -1, phase or read position, increment, age and
	// length in samples, left and right gains), each oscillator's countdown to its next grain and
	// the grains' own random stream.
	static constexpr int MAX_GRAINS = 32;
	int g_own[MAX_GRAINS] = {};
	double g_ph[MAX_GRAINS] = {}, g_inc[MAX_GRAINS] = {}, g_l[MAX_GRAINS] = {}, g_r[MAX_GRAINS] = {};
	// The hann window and a sine source as phasors (no per-sample cos or sin): state and rotation.
	double g_c[MAX_GRAINS] = {}, g_s[MAX_GRAINS] = {}, g_wc[MAX_GRAINS] = {}, g_ws[MAX_GRAINS] = {};
	double g_zr[MAX_GRAINS] = {}, g_zi[MAX_GRAINS] = {}, g_oc[MAX_GRAINS] = {}, g_os[MAX_GRAINS] = {};
	int g_age[MAX_GRAINS] = {}, g_len[MAX_GRAINS] = {};
	double g_next[MAX_OSC] = {};
	uint32_t grng = 1;
	// Each envelope's attack, decay and release time factors (envN.attack, .decay, .release): [k * 3 + part].
	double ets[3 * SynthPatch::MAX_ENV] = { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 };
	// Filter feedback: this voice's amount and the filter block's last outputs.
	double o_fb = 0.0;
	double fby[2] = {};
	void cz_enter(const SynthPatch::Env &en, int k, int i);
	double cz_tick(const SynthEngine &e, int k);
	double comb_tick(const SynthPatch &c, double x, int base);
	double lfo_custom(const SynthEngine &e, int k);
	void note_time_mods(const SynthEngine &e);
	void start_slot(const SynthEngine &e);
	double adsr_slot(const SynthEngine &e, int k);

	inline double white01() {
		rng ^= rng << 13;
		rng ^= rng >> 17;
		rng ^= rng << 5;
		return rng / 4294967295.0;
	}
	inline double grain_rand() {
		grng ^= grng << 13;
		grng ^= grng >> 17;
		grng ^= grng << 5;
		return grng / 4294967295.0;
	}
	inline double drift_rand() {
		drng ^= drng << 13;
		drng ^= drng >> 17;
		drng ^= drng << 5;
		return drng / 4294967295.0;
	}
	inline double lfo_rand(int k) {
		if (k < 2) {
			return white01();
		}
		uint32_t r = lrng[k];
		r ^= r << 13;
		r ^= r >> 17;
		r ^= r << 5;
		lrng[k] = r;
		return r / 4294967295.0;
	}
	void start(SynthEngine &e, double note, double vel, double from_note);
	void retrigger(bool from_zero = false);
	void sample_start(const SynthPatch &c);
	double grains_tick(const SynthEngine &e, int j, double &r);
	void release();
	void kill();
	double env_tick(const SynthEngine &e, int k);
	inline double adsr_tick(const SynthEngine &e, int k);
	void note_scales(const SynthPatch::Env &en, int k, double p_note, double p_vel);
	void stage_enter(const SynthEngine &e, const SynthPatch::Env &en, int k, int i);
	int stage_next(const SynthPatch::Env &en, int k, int i) const;
	double stages_tick(const SynthEngine &e, int k);
	void dx7_note(const SynthPatch::Env &en, int k, double p_note, double p_vel);
	double dx7_tick(const SynthEngine &e, int k);
	double dx7p_tick(const SynthEngine &e, int k);
	void note_levels(const SynthEngine &e, double p_note, double p_vel);
	void op_freq(const SynthEngine &e, const SynthPatch::Osc &o, int j, double s);
	bool env_done(const SynthEngine &e, int k) const;
	double lfo_tick(const SynthEngine &e, int k);
	void control(SynthEngine &e, double e0, double e1, double e2);
	double tick(SynthEngine &e);
};

class SynthEngine {
public:
	enum { E_ON, E_OFF, E_BEND, E_MOD, E_TOUCH, E_ALL_OFF, E_PANIC, E_SUSTAIN, E_TEMPO };
	struct Event {
		int64_t frame;
		int64_t seq;
		int type;
		double a, b;
	};

	int sr = 48000;
	int64_t frame = 0;
	double bend = 0.0, mod_wheel = 0.0, aftertouch = 0.0;
	bool sustain = false;
	// The tempo: the patch's tempo_bpm until an E_TEMPO event sets one.
	double tempo_bpm = 120.0;
	bool tempo_set = false;
	SynthPatch p;
	std::vector<SynthVoice> voices;
	FxChain fx;

	// Per-patch numbers (as AKSynthCore.set_patch).
	int64_t env_a[SynthPatch::MAX_ENV] = {}, env_d[SynthPatch::MAX_ENV] = { 1, 1, 1, 1, 1, 1, 1, 1 };
	double env_s[SynthPatch::MAX_ENV] = {}, env_kd[SynthPatch::MAX_ENV] = {}, env_kr[SynthPatch::MAX_ENV] = {};
	double env_kr2[SynthPatch::MAX_ENV] = {}, env_knee[SynthPatch::MAX_ENV] = {};
	bool env_exp[SynthPatch::MAX_ENV] = {};
	int env_kind[SynthPatch::MAX_ENV] = {};
	int n_env = 3;
	// Only ADSRs (today's patches): tick runs them directly.
	bool adsr_only = true;
	bool time_rows = false;  // a matrix row moves an envelope's times (envN.time, .attack ...)
	// msfa's per-rate tables (Freqlut, the LFO's and pitch envelope's units).
	int64_t freqlut_tab[1025] = {};
	int64_t lfo_unit = 0, lfo_ratio = 0, penv_unit = 0;
	// Each mode's decay per sample at this rate and its input gain (1 - decay) when it resonates.
	double mode_d[SynthPatch::MAX_MODES] = {}, mode_g[SynthPatch::MAX_MODES] = {};
	int64_t freqlut(int64_t logfreq) const;
	bool lfo_dx7[SynthPatch::MAX_LFO] = {};
	int dx7_lfo = -1;  // the first DX7 LFO (drives dx7 envelopes' amp modulation)
	// Envelopes that end the voice when every audible oscillator has its own.
	int carrier_envs[SynthPatch::MAX_ENV] = {};
	int n_carrier = 0;
	bool ops = false;  // any oscillator uses the phase 2 fields
	int64_t dx7_srm = 0;
	double cz_scale = 1.0;  // the CZ chip's 40 kHz over the mix rate (cz envelopes)
	int lfo_shape[SynthPatch::MAX_LFO] = {};
	double lfo_inc[SynthPatch::MAX_LFO] = {}, lfo_delay[SynthPatch::MAX_LFO] = {};
	double lfo_width[SynthPatch::MAX_LFO] = { 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5 }, lfo_phase[SynthPatch::MAX_LFO] = {};
	bool lfo_free[SynthPatch::MAX_LFO] = {};
	// Tempo-synced LFOs: beats per cycle, and the free clock's cycles at lfo_base_frame.
	double lfo_beats[SynthPatch::MAX_LFO] = {}, lfo_base[SynthPatch::MAX_LFO] = {};
	int64_t lfo_base_frame[SynthPatch::MAX_LFO] = {};
	int n_lfo = 2;
	// Voice slots (AKSynthCore._set_extras): how many, the next, each one's offsets.
	int n_slot = 0;
	int64_t rr = 0;
	double sl_pitch[SynthPatch::MAX_SLOTS] = {}, sl_cut[SynthPatch::MAX_SLOTS] = {}, sl_gain[SynthPatch::MAX_SLOTS] = {};
	double sl_tf[SynthPatch::MAX_SLOTS] = {};
	bool slop_time = false;
	double pre_lp = 0.0, pre_hp = 0.0;
	// The comb's lines, two per voice (allocated by set_patch, never on the audio thread).
	std::vector<double> comb_pool;
	std::vector<double> fcomb_pool;  // comb-type filters' lines: per voice, filter 1 and 2, left and right
	// Any oscillator around the filter.
	bool bypass = false;
	double ratio[SynthPatch::MAX_U] = {};
	// Per oscillator slot (j * MAX_SLOT + unison voice * stack + copy): ratio,
	// level and stereo weights; per oscillator its slot count, stack,
	// normalisation and highest ratio; per pair, the slot of the second a slot
	// of the first reads (FM, sync, ring). See AKSynthCore._slots.
	double sratio[SynthPatch::MAX_OSC * SynthPatch::MAX_SLOT] = {};
	double sw[SynthPatch::MAX_OSC * SynthPatch::MAX_SLOT] = {};
	double swl[SynthPatch::MAX_OSC * SynthPatch::MAX_SLOT] = {}, swr[SynthPatch::MAX_OSC * SynthPatch::MAX_SLOT] = {};
	int slot_n[SynthPatch::MAX_OSC] = {}, slot_s[SynthPatch::MAX_OSC] = {};
	double oinv[SynthPatch::MAX_OSC] = {}, ormax[SynthPatch::MAX_OSC] = {};
	uint8_t smap[SynthPatch::MAX_OSC * SynthPatch::MAX_OSC * SynthPatch::MAX_SLOT] = {};
	double inv_su = 1.0, kg = 0.0, kill_k = 0.0, vel_k = 0.0, ctl_k = 0.0;
	double uwl[SynthPatch::MAX_U] = {}, uwr[SynthPatch::MAX_U] = {};
	// Unison voices' levels; oscillators' stereo weights (equal power across their pan).
	double uw[SynthPatch::MAX_U] = {}, opl[SynthPatch::MAX_OSC] = {}, opr[SynthPatch::MAX_OSC] = {};
	bool stereo = false;
	// A stolen voice fades out with this time constant (AKSynthCore.STEAL_FADE_S).
	static constexpr double STEAL_FADE_S = 0.003;
	// A legato note's new velocity reaches the level over this (AKSynthCore.VEL_GLIDE_S).
	static constexpr double VEL_GLIDE_S = 0.004;
	// Mod wheel and aftertouch glide over this (AKSynthCore.CTL_GLIDE_S).
	static constexpr double CTL_GLIDE_S = 0.006;

	// Up to twice the polyphony while stolen voices fade; reserved so the
	// audio thread never reallocates.
	SynthEngine() { voices.reserve(64); }
	void set_patch(const SynthPatch &patch);
	void queue(int64_t at, int type, double a, double b);
	// Adds into out_l / out_r (n frames).
	void render(float *out_l, float *out_r, int n);
	int voice_count() const;
	// The read position goes with the events: left behind, the next queue()
	// would erase past the end (Godot crashed stopping a line mid-play).
	void clear_events() {
		events.clear();
		ev_head = 0;
	}
	int64_t next_serial() { return ++serial; }
	double last_note = -1.0;

private:
	std::vector<Event> events;
	size_t ev_head = 0;
	int64_t seq = 0;
	int64_t serial = 0;
	std::vector<double> held_note, held_vel;
	// The held key that sounds (SynthPatch::prio).
	int pick_held() const;
	// The arpeggiator (as AKSynthCore): held keys in key order, its clock in
	// beats, the next step and gate-off, the sounding note, steps, random state.
	static constexpr int ARP_MAX = 128;
	double arp_note[ARP_MAX] = {}, arp_vel[ARP_MAX] = {};
	int arp_n = 0;
	bool arp_on = false, arp_sounding = false;
	double arp_pos = 0.0, arp_next = 0.0, arp_gate_at = -1.0, arp_cur = 0.0;
	int64_t arp_step = 0, arp_starts = 0;
	uint32_t arp_rng = 1;
	void apply(int type, double a, double b);
	void retempo(double bpm);
	void arp_key_on(double note, double vel);
	void arp_key_off(double note);
	void arp_stop();
	void arp_tick();
	void arp_fire();
	void on(double note, double vel);
	void off(double note, bool pedal = true);
	int steal();
};

} // namespace ak
