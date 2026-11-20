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
	static constexpr int MAX_OSC = 8;
	static constexpr int MAX_U = 8;
	// Copies of one oscillator inside each unison voice (its stack), and the
	// phase slots per oscillator (unison voices x stack).
	static constexpr int MAX_STACK = 8;
	static constexpr int MAX_SLOT = MAX_U * MAX_STACK;
	static constexpr int MAX_MODS = 16;
	static constexpr int MAX_ENV = 8;
	static constexpr int MAX_STAGES = 32;
	struct Osc {
		int shape = 0;
		double level = 1.0, semis = 0.0, width = 0.5, position = 0.0, fm_index = 0.0, pan = 0.0;
		bool filtered = true;
		int fm_from = -1, sync = -1, ring = -1, table = -1;
		int stack = 1;
		double stack_cents = 0.0;
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
					op[j].feedback == 0.0 && op[j].level_env < 0;
		}
	}
	double spread = 0.0, resonance = 0.3, drive = 1.0;
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
		double start = 0.0, tk = 0.0, tk_center = 60.0, tv = 0.0, lv = 0.0;
		int64_t tk_mask = 0, tv_mask = 0;
		// dx7: raw DX7 values.
		int rates[4] = { 99, 99, 99, 99 }, levels[4] = { 99, 99, 99, 0 };
		int ol = 99, rs = 0, vs = 0, bp = 39, ld = 0, rd = 0, lc = 0, rc = 0;
		int ams = 0, ko = 0;
	};
	struct Lfo {
		int shape = 0;
		double rate_hz = 1.0, delay_s = 0.0, width = 0.5, phase = 0.0;
		bool free = false;
		double beats = 0.0;  // tempo-synced: beats per cycle (0: rate_hz)
		// A DX7 LFO (msfa lfo.cc), raw values.
		bool dx7 = false, sync = true;
		int speed = 35, delay = 0, wave = 0, pmd = 0, pms = 0, amd = 0;
	};
	struct Mod {
		int src = 0, dst = 0, osc = -1;
		double amount = 0.0;
	};
	Osc osc[MAX_OSC];
	int n_osc = 1;
	int unison = 1;
	double detune_cents = 0.0, unison_level = 1.0, unison_pitch = 0.0;
	int filter_type = 1, stages = 1;
	double cutoff_hz = 18000.0, q = 0.707;
	Lfo lfo[2];
	Mod mods[MAX_MODS];
	int n_mods = 0;
	int mode = 0, poly = 8;
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
	// Last: large, and only the envelope code reads it.
	int n_env = 3;
	Env env[MAX_ENV];
	OscOp op[MAX_OSC];
};

class SynthEngine;

// Modulation is worked out every CONTROL samples and held between
// (as AKSynthCore.CONTROL).
constexpr int CONTROL = 8;
constexpr int N_SRC = 16;
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
	double lfo_ph[2] = { 0, 0 }, lfo_sh[2] = { 0, 0 };
	double lfo_sh0[2] = { 0, 0 };  // smooth random: where each cycle starts (lfo_sh: where it goes)
	// The matrix's push on each LFO's rate, in octaves (from the last control step).
	double lfo_oct[2] = { 0, 0 };
	int64_t age = 0;
	double phase[MAX_OSC * MAX_SLOT] = {};
	double raw[MAX_OSC * MAX_SLOT] = {};
	double last_semi[MAX_OSC] = {};
	double freq[MAX_OSC] = {};
	double ic1[2] = { 0, 0 }, ic2[2] = { 0, 0 };
	double last_c = -1.0, last_q = -1.0, fk = 1.0, a1 = 0, a2 = 0, a3 = 0;
	double src[N_SRC] = {};
	double mo[5 * MAX_OSC] = {};
	double o_level[MAX_OSC] = {}, o_idx[MAX_OSC] = {}, o_width[MAX_OSC] = {}, o_pos[MAX_OSC] = {};
	double amp_mod = 1.0;
	double dt[MAX_OSC * MAX_SLOT] = {};
	double yr = 0.0;
	double wrap_t[MAX_OSC * MAX_SLOT] = {};
	int o_mip[MAX_OSC] = {}, o_zone[MAX_OSC] = {};
	double o_zw[MAX_OSC] = {};
	double ic1r[2] = { 0, 0 }, ic2r[2] = { 0, 0 };
	double lad[8] = {};
	double lg = 0, lG = 0, lbeta = 0, lk = 0;
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
	bool dq[MAX_ENV] = {};  // a dx7 envelope's block is below msfa's gain threshold
	Dx7PEnv dxp[MAX_ENV];
	Dx7Lfo dlfo[2];
	// Phase 2 operators: outputs two samples back (feedback), per-note level
	// factors, a dx7 operator's key, Q24 log frequency and increment.
	double fbp[MAX_OSC * MAX_SLOT] = {};
	double o_kv[MAX_OSC] = {};
	int o_dxnote[MAX_OSC] = {};
	int64_t o_dxbase[MAX_OSC] = {};
	double o_inc[MAX_OSC] = {};
	double ladder(const SynthPatch &c, double x, int s0);

	inline double white01() {
		rng ^= rng << 13;
		rng ^= rng >> 17;
		rng ^= rng << 5;
		return rng / 4294967295.0;
	}
	void start(SynthEngine &e, double note, double vel, double from_note);
	void retrigger();
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
	// msfa's per-rate tables (Freqlut, the LFO's and pitch envelope's units).
	int64_t freqlut_tab[1025] = {};
	int64_t lfo_unit = 0, lfo_ratio = 0, penv_unit = 0;
	int64_t freqlut(int64_t logfreq) const;
	bool lfo_dx7[2] = {};
	int dx7_lfo = -1;  // the first DX7 LFO (drives dx7 envelopes' amp modulation)
	// Envelopes that end the voice when every audible oscillator has its own.
	int carrier_envs[SynthPatch::MAX_ENV] = {};
	int n_carrier = 0;
	bool ops = false;  // any oscillator uses the phase 2 fields
	int64_t dx7_srm = 0;
	int lfo_shape[2] = {};
	double lfo_inc[2] = {}, lfo_delay[2] = {}, lfo_width[2] = { 0.5, 0.5 }, lfo_phase[2] = {};
	bool lfo_free[2] = {};
	// Tempo-synced LFOs: beats per cycle, and the free clock's cycles at lfo_base_frame.
	double lfo_beats[2] = {}, lfo_base[2] = {};
	int64_t lfo_base_frame[2] = {};
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
