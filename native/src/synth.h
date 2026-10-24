// SPDX-License-Identifier: Apache-2.0
// The polyphonic synth engine, free of Godot types. It mirrors AKSynthCore
// (addons/audio_kit/synth/synth_core.gd) step for step: the GDScript version
// is the reference and the fallback; this one is what plays live and bakes
// fast. The same events give the same samples, live or offline.
#pragma once
#include "dsp.h"

#include <cstdint>
#include <vector>

namespace ak {

struct SynthPatch {
	static constexpr int MAX_OSC = 4;
	static constexpr int MAX_U = 7;
	static constexpr int MAX_MODS = 16;
	struct Osc {
		int shape = 0;
		double level = 1.0, semis = 0.0, width = 0.5, position = 0.0, fm_index = 0.0;
		int fm_from = -1;
	};
	struct Env {
		double a = 0.0, d = 0.2, s = 0.0, r = 0.15;
		bool exp = false;
	};
	struct Lfo {
		int shape = 0;
		double rate_hz = 1.0, delay_s = 0.0;
	};
	struct Mod {
		int src = 0, dst = 0, osc = -1;
		double amount = 0.0;
	};
	Osc osc[MAX_OSC];
	int n_osc = 1;
	int unison = 1;
	double detune_cents = 0.0;
	int filter_type = 1, stages = 1;
	double cutoff_hz = 18000.0, q = 0.707;
	Env env[3];
	Lfo lfo[2];
	Mod mods[MAX_MODS];
	int n_mods = 0;
	int mode = 0, poly = 8;
	double glide_s = 0.0, bend_range = 2.0, vel_sens = 0.5, gain = 1.0, pan = 0.0;
	int64_t seed = 0;
};

class SynthEngine;

// Modulation is worked out every CONTROL samples and held between
// (as AKSynthCore.CONTROL).
constexpr int CONTROL = 8;

struct SynthVoice {
	static constexpr int MAX_OSC = SynthPatch::MAX_OSC;
	static constexpr int MAX_U = SynthPatch::MAX_U;
	bool active = false, gated = false;
	int64_t serial = 0;
	double note = 60.0, target = 60.0, cur = 60.0, vel = 1.0, rnd = 0.0;
	uint32_t rng = 1;
	double gl = 1.0, gr = 1.0;
	int stage[3] = { 4, 4, 4 };
	int64_t t[3] = { 0, 0, 0 };
	double level[3] = { 0, 0, 0 }, start_level[3] = { 0, 0, 0 }, ev[3] = { 1, 1, 1 };
	double lfo_ph[2] = { 0, 0 }, lfo_sh[2] = { 0, 0 };
	int64_t age = 0;
	double phase[MAX_OSC * MAX_U] = {};
	double raw[MAX_OSC * MAX_U] = {};
	double last_semi[MAX_OSC] = {};
	double freq[MAX_OSC] = {};
	double ic1[2] = { 0, 0 }, ic2[2] = { 0, 0 };
	double last_c = -1.0, last_q = -1.0, fk = 1.0, a1 = 0, a2 = 0, a3 = 0;
	double src[11] = {};
	double mo[5 * MAX_OSC] = {};
	double o_level[MAX_OSC] = {}, o_idx[MAX_OSC] = {}, o_width[MAX_OSC] = {}, o_pos[MAX_OSC] = {};
	double amp_mod = 1.0;
	double dt[MAX_OSC * MAX_U] = {};

	inline double white01() {
		rng ^= rng << 13;
		rng ^= rng >> 17;
		rng ^= rng << 5;
		return rng / 4294967295.0;
	}
	void start(SynthEngine &e, double note, double vel, double from_note);
	void retrigger();
	void release();
	double env_tick(const SynthEngine &e, int k);
	double lfo_tick(const SynthEngine &e, int k);
	void control(SynthEngine &e, double e0, double e1, double e2);
	double tick(SynthEngine &e);
};

class SynthEngine {
public:
	enum { E_ON, E_OFF, E_BEND, E_MOD, E_TOUCH, E_ALL_OFF, E_PANIC };
	struct Event {
		int64_t frame;
		int64_t seq;
		int type;
		double a, b;
	};

	int sr = 48000;
	int64_t frame = 0;
	double bend = 0.0, mod_wheel = 0.0, aftertouch = 0.0;
	SynthPatch p;
	std::vector<SynthVoice> voices;

	// Per-patch numbers (as AKSynthCore.set_patch).
	int64_t env_a[3] = { 0, 0, 0 }, env_d[3] = { 1, 1, 1 };
	double env_s[3] = {}, env_kd[3] = {}, env_kr[3] = {};
	bool env_exp[3] = {};
	int lfo_shape[2] = {};
	double lfo_inc[2] = {}, lfo_delay[2] = {};
	double ratio[SynthPatch::MAX_U] = {};
	double inv_su = 1.0, kg = 0.0;

	SynthEngine() { voices.reserve(32); }
	void set_patch(const SynthPatch &patch);
	void queue(int64_t at, int type, double a, double b);
	// Adds into out_l / out_r (n frames).
	void render(float *out_l, float *out_r, int n);
	int voice_count() const;
	void clear_events() { events.clear(); }
	int64_t next_serial() { return ++serial; }
	double last_note = -1.0;

private:
	std::vector<Event> events;
	size_t ev_head = 0;
	int64_t seq = 0;
	int64_t serial = 0;
	std::vector<double> held_note, held_vel;
	void apply(int type, double a, double b);
	void on(double note, double vel);
	void off(double note);
	SynthVoice &steal();
};

} // namespace ak
