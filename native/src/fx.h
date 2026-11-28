// SPDX-License-Identifier: Apache-2.0
// Sound-shaping effects that stream one stereo sample at a time: chorus and
// flanger (a modulated delay), phaser, three-band EQ, compressor,
// saturation, and the character effects voices use: a pitch-shifted layer,
// ring modulation, growl, bitcrush, delay and reverb. The same structs run inside patches (the synth engine), on
// recipe buffers (AKNative.fx_process) and as Godot bus effects (AKChorus,
// AKPhaser ...), so an effect sounds the same in all three. Each mirrors
// AKStreamFx (addons/audio_kit/dsp/stream_fx.gd) step for step.
#pragma once
#include "dsp.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <vector>

namespace ak {

struct Fx {
	enum Type { NONE, CHORUS, FLANGER, PHASER, EQ, COMPRESSOR, SATURATE, PITCH, RING, GROWL, CRUSH, DELAY, REVERB, FILTER, LIMITER,
		FREQSHIFT, ROTARY, STUTTER, CONDITIONER, GEQ, RESONATOR, EXCITER, WAVESHAPER, MIDSIDE,
		ENSEMBLE, COMBULATOR, TAPE, TREEMONSTER, SPRING, BONSAI, CHOW, NEURON, GRANULAR, AIRWINDOWS, N_TYPES };

	// The newer effect types keep their own knobs in xk[], named and clamped by this table
	// (AKStreamFx.XKEYS, keep the two in step), and their running state in xb / xs / xw, so
	// they don't add fields to every effect. mix, dry, wet and feedback stay the shared ones.
	struct XKey {
		const char *name;
		double def, lo, hi;
	};
	static constexpr int NXK = 16;
	static const XKey *xkeys(int t, int &n) {
		static const XKey FS[] = { { "shift_hz", 100.0, -20000.0, 20000.0 }, { "stereo", 0.0, 0.0, 1.0 }, { "echo_ms", 0.0, 0.0, 1000.0 } };
		static const XKey RO[] = { { "speed", 0.0, 0.0, 1.0 }, { "horn_hz", 6.7, 0.1, 15.0 }, { "drum_hz", 5.7, 0.1, 15.0 },
			{ "accel_s", 0.5, 0.01, 10.0 }, { "drive", 0.0, 0.0, 1.0 }, { "spread", 1.0, 0.0, 1.0 }, { "crossover_hz", 800.0, 100.0, 4000.0 },
			{ "doppler", 1.0, 0.0, 2.0 }, { "tremolo", 1.0, 0.0, 2.0 } };
		static const XKey ST[] = { { "rate_hz", 8.0, 1.0, 100.0 }, { "resample_hz", 1.0, 0.05, 100.0 }, { "softness", 0.2, 0.0, 1.0 },
			{ "pitch", 0.0, -24.0, 24.0 }, { "rate_beats", 0.0, 0.0, 16.0 }, { "resample_beats", 0.0, 0.0, 64.0 } };
		static const XKey CO[] = { { "bass_db", 0.0, -24.0, 24.0 }, { "treble_db", 0.0, -24.0, 24.0 }, { "width", 1.0, 0.0, 2.0 },
			{ "balance", 0.0, -1.0, 1.0 }, { "threshold_db", 0.0, -48.0, 0.0 }, { "attack_ms", 5.0, 0.1, 200.0 },
			{ "release_ms", 120.0, 1.0, 3000.0 }, { "output_db", 0.0, -24.0, 24.0 } };
		static const XKey GQ[] = { { "band1_db", 0.0, -12.0, 12.0 }, { "band2_db", 0.0, -12.0, 12.0 }, { "band3_db", 0.0, -12.0, 12.0 },
			{ "band4_db", 0.0, -12.0, 12.0 }, { "band5_db", 0.0, -12.0, 12.0 }, { "band6_db", 0.0, -12.0, 12.0 },
			{ "band7_db", 0.0, -12.0, 12.0 }, { "band8_db", 0.0, -12.0, 12.0 }, { "band9_db", 0.0, -12.0, 12.0 },
			{ "band10_db", 0.0, -12.0, 12.0 }, { "band11_db", 0.0, -12.0, 12.0 }, { "output_db", 0.0, -24.0, 24.0 } };
		static const XKey RS[] = { { "freq1_hz", 300.0, 20.0, 20000.0 }, { "freq2_hz", 1200.0, 20.0, 20000.0 },
			{ "freq3_hz", 3500.0, 20.0, 20000.0 }, { "q1", 8.0, 0.5, 100.0 }, { "q2", 8.0, 0.5, 100.0 }, { "q3", 8.0, 0.5, 100.0 },
			{ "gain1_db", 0.0, -48.0, 24.0 }, { "gain2_db", 0.0, -48.0, 24.0 }, { "gain3_db", 0.0, -48.0, 24.0 }, { "series", 0.0, 0.0, 1.0 },
			{ "output_db", 0.0, -24.0, 24.0 } };
		static const XKey EX[] = { { "freq_hz", 3000.0, 500.0, 16000.0 }, { "drive", 0.5, 0.0, 1.0 } };
		static const XKey WS[] = { { "curve", 0.0, 0.0, 5.0 }, { "drive_db", 6.0, -24.0, 48.0 }, { "bias", 0.0, -1.0, 1.0 },
			{ "pre_hp_hz", 0.0, 0.0, 2000.0 }, { "post_lp_hz", 0.0, 0.0, 20000.0 }, { "output_db", 0.0, -48.0, 24.0 } };
		static const XKey MS[] = { { "mid_db", 0.0, -48.0, 24.0 }, { "side_db", 0.0, -48.0, 24.0 }, { "side_hp_hz", 0.0, 0.0, 2000.0 },
			{ "mid_pan", 0.0, -1.0, 1.0 } };
		static const XKey EN[] = { { "slow_hz", 0.6, 0.01, 10.0 }, { "slow_depth", 0.5, 0.0, 1.0 }, { "fast_hz", 6.0, 0.5, 20.0 },
			{ "fast_depth", 0.2, 0.0, 1.0 }, { "center_ms", 10.0, 2.0, 30.0 }, { "tone_hz", 9000.0, 1000.0, 20000.0 }, { "width", 1.0, 0.0, 1.0 } };
		static const XKey CB[] = { { "tune_hz", 220.0, 20.0, 4000.0 }, { "offset2", 7.0, -24.0, 24.0 }, { "offset3", 12.0, -24.0, 24.0 },
			{ "resonance", 0.9, -0.995, 0.995 }, { "tone_hz", 6000.0, 200.0, 20000.0 }, { "noise", 0.0, 0.0, 1.0 },
			{ "gain1_db", 0.0, -48.0, 24.0 }, { "gain2_db", 0.0, -48.0, 24.0 }, { "gain3_db", 0.0, -48.0, 24.0 }, { "width", 0.7, 0.0, 1.0 } };
		static const XKey TP[] = { { "drive_db", 6.0, -12.0, 36.0 }, { "hyst", 0.3, 0.0, 1.0 }, { "wow", 0.2, 0.0, 1.0 }, { "flutter", 0.2, 0.0, 1.0 },
			{ "bump_hz", 80.0, 30.0, 250.0 }, { "bump_db", 3.0, 0.0, 12.0 }, { "hf_hz", 12000.0, 1000.0, 20000.0 }, { "output_db", 0.0, -24.0, 24.0 } };
		static const XKey TM[] = { { "threshold_db", -40.0, -80.0, 0.0 }, { "glide_ms", 20.0, 0.0, 500.0 }, { "pitch", 0.0, -48.0, 48.0 },
			{ "track_lp_hz", 1200.0, 100.0, 8000.0 }, { "track_hp_hz", 40.0, 10.0, 1000.0 }, { "width", 0.0, 0.0, 1.0 } };
		static const XKey SP[] = { { "decay_s", 2.0, 0.2, 10.0 }, { "chirp", 0.6, 0.0, 0.85 }, { "length_ms", 35.0, 10.0, 80.0 },
			{ "tone_hz", 4500.0, 500.0, 12000.0 }, { "width", 1.0, 0.0, 1.0 } };
		static const XKey BO[] = { { "bass_hz", 120.0, 40.0, 400.0 }, { "boost_db", 6.0, 0.0, 18.0 }, { "harmonics", 0.3, 0.0, 1.0 },
			{ "drive_db", 3.0, -12.0, 24.0 }, { "tone_hz", 12000.0, 1000.0, 20000.0 }, { "output_db", 0.0, -24.0, 24.0 } };
		static const XKey CH[] = { { "threshold_db", -12.0, -48.0, 0.0 }, { "ratio", 10.0, 1.0, 100.0 }, { "flip", 0.0, 0.0, 1.0 },
			{ "drive_db", 12.0, 0.0, 48.0 }, { "tone_hz", 20000.0, 1000.0, 20000.0 }, { "output_db", 0.0, -48.0, 24.0 } };
		static const XKey NE[] = { { "size_ms", 40.0, 2.0, 250.0 }, { "regen", 0.6, 0.0, 1.2 }, { "drive", 0.3, 0.0, 1.0 }, { "wobble", 0.2, 0.0, 1.0 },
			{ "wobble_hz", 0.3, 0.01, 10.0 }, { "tone_hz", 6000.0, 200.0, 20000.0 }, { "width", 1.0, 0.0, 1.0 } };
		static const XKey GR[] = { { "position", 0.5, 0.0, 1.0 }, { "size", 0.5, 0.0, 1.0 }, { "pitch", 0.0, -48.0, 48.0 },
			{ "density", 0.7, 0.0, 1.0 }, { "texture", 0.5, 0.0, 1.0 }, { "recycle", 0.0, 0.0, 1.0 }, { "pan_spread", 0.5, 0.0, 1.0 },
			{ "reverb", 0.0, 0.0, 1.0 }, { "freeze", 0.0, 0.0, 1.0 } };
		static const XKey AW[] = { { "algo", 0.0, 0.0, AW_N - 1.0 }, { "a", -1.0, -1.0, 1.0 }, { "b", -1.0, -1.0, 1.0 }, { "c", -1.0, -1.0, 1.0 },
			{ "d", -1.0, -1.0, 1.0 }, { "e", -1.0, -1.0, 1.0 }, { "f", -1.0, -1.0, 1.0 } };
		switch (t) {
			case AIRWINDOWS: n = 7; return AW;
			case GRANULAR: n = 9; return GR;
			case ENSEMBLE: n = 7; return EN;
			case COMBULATOR: n = 10; return CB;
			case TAPE: n = 8; return TP;
			case TREEMONSTER: n = 6; return TM;
			case SPRING: n = 5; return SP;
			case BONSAI: n = 6; return BO;
			case CHOW: n = 6; return CH;
			case NEURON: n = 7; return NE;
			case CONDITIONER: n = 8; return CO;
			case GEQ: n = 12; return GQ;
			case RESONATOR: n = 11; return RS;
			case EXCITER: n = 2; return EX;
			case WAVESHAPER: n = 6; return WS;
			case MIDSIDE: n = 4; return MS;
			case FREQSHIFT: n = 3; return FS;
			case ROTARY: n = 9; return RO;
			case STUTTER: n = 6; return ST;
			default: n = 0; return nullptr;
		}
	}
	double xk[NXK] = {};
	std::vector<double> xb;
	double xs[16] = {};
	int xw = 0;
	double xc[80] = {};   // coefficients from the knobs (setup_x; not carried by retune)
	int type = NONE;
	int sr = 48000;
	// Shared knobs (meaning depends on the type; see AKStreamFx.compile).
	double rate_hz = 0.8, depth_ms = 3.0, delay_ms = 12.0, feedback = 0.0, mix = 0.5, spread = 1.0;
	// Separate dry and wet gains (the spec's dry, wet; -1: from mix). Unset, every effect mixes as before:
	// a crossfade dry (1 - mix) to wet (mix), or for delay and reverb the dry kept and the wet at mix.
	double dry = -1.0, wet = -1.0;
	// A line long enough for a modulated delay time (chorus, flanger, delay; 0: from the knobs).
	double line_ms = 0.0;
	inline double dm() const { return dry >= 0.0 ? dry : 1.0 - mix; }
	inline double wm() const { return wet >= 0.0 ? wet : mix; }
	inline double da() const { return dry >= 0.0 ? dry : 1.0; }
	int voices = 2;
	// Phaser
	int stages = 4;
	double center_hz = 800.0, range_oct = 2.0, depth = 1.0;
	// EQ
	double low_db = 0.0, low_hz = 120.0, mid_db = 0.0, mid_hz = 1000.0, mid_q = 0.7, high_db = 0.0, high_hz = 6000.0;
	// Compressor
	double threshold_db = -18.0, ratio = 4.0, attack_s = 0.01, release_s = 0.12, knee_db = 6.0, makeup_db = 0.0;
	// Saturate
	double drive_db = 12.0, tone_hz = 6000.0, asymmetry = 0.0, output_db = 0.0;
	// Pitch, ring, growl, crush, delay, reverb
	double semitones = -12.0, window_ms = 60.0, freq_hz = 220.0, jitter = 0.5, bits = 8.0, time_ms = 250.0, damp_hz = 4000.0;
	double room = 0.6, damp = 0.5, width = 1.0;
	// Reverb input: predelay and one-pole low and high cuts (0: off).
	double predelay_ms = 0.0, low_cut_hz = 0.0, high_cut_hz = 0.0;
	std::vector<double> rv_pre;
	int rv_pw = 0;
	double rv_lck = 0.0, rv_hck = 0.0, rv_lcz = 0.0, rv_hcz = 0.0;
	int hold = 1;
	// A tempo-synced delay: its time in beats (0: time_ms). Its mode (0 stereo,
	// 1 cross, 2 pingpong) and spread (ms the right side repeats later; negative: the left).
	double time_beats = 0.0;
	int mode = 0;
	double spread_ms = 0.0;
	// Filter (mode 0 lowpass, 1 highpass; slope 6, 12 or 24 dB).
	double cutoff_hz = 1000.0, q = 0.707, slope_db = 12.0;
	// Limiter (release_s shared with the compressor): its ceiling, as AKDynamics.limit.
	double ceiling_db = -1.0;
	double lim_c = 1.0, lim_k = 0.0, lim_g = 1.0;
	int f_n = 1;
	double f_a = 0.0, f_k = 1.0, f_a1 = 0.0, f_a2 = 0.0, f_a3 = 0.0;

	// ---- state
	double ph = 0.0;
	std::vector<float> line[2];
	int w = 0;
	// The delay line's length (the longest time plus the spread), and each channel's delay.
	int dn = 1, dl = 1, dr = 1;
	double fb_l = 0.0, fb_r = 0.0;
	double ap_z[2][12] = {};
	double ph_last[2] = { 0.0, 0.0 };
	struct Biquad {
		double b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0;
		double x1[2] = { 0, 0 }, x2[2] = { 0, 0 }, y1[2] = { 0, 0 }, y2[2] = { 0, 0 };
		inline double tick(double x, int c) {
			double y = b0 * x + b1 * x1[c] + b2 * x2[c] - a1 * y1[c] - a2 * y2[c];
			x2[c] = x1[c];
			x1[c] = x;
			y2[c] = y1[c];
			y1[c] = y;
			return y;
		}
	};
	Biquad bq[3];
	double gr_db = 0.0, k_att = 0.0, k_rel = 0.0;
	double sat_g = 1.0, sat_off = 0.0, sat_lp = 0.0, sat_z[2] = { 0, 0 }, sat_out = 1.0;
	double win = 1.0, ratio_step = 0.0;      // pitch: window in samples, phase step
	double cph = 0.0;                        // ring: carrier phase
	uint32_t rng = 0x9E3779B9u;              // growl: per-cycle randomness
	double gr_rate = 1.0, gr_amp = 1.0;
	int ctr = 0;                             // crush: hold counter
	double held[2] = { 0, 0 };
	double ez[2] = { 0, 0 }, e_k = 1.0;      // delay: damping in the feedback
	// Reverb (Freeverb's tunings, double maths): 8 combs then 4 all-passes per
	// channel, all in one buffer at rv_off.
	std::vector<float> rv;
	int rv_off[24] = {}, rv_len[24] = {}, rv_idx[24] = {};
	double rv_store[16] = {};
	double rv_fb = 0.84, rv_dk = 0.2, rv_w1 = 1.0, rv_w2 = 0.0;

	static constexpr int RV_COMBS[8] = { 1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617 };
	static constexpr int RV_PASSES[4] = { 556, 441, 341, 225 };

	static double db(double x) { return std::pow(10.0, x / 20.0); }

	// Each channel's delay for a time of ms, the spread added to one side.
	void delay_lengths(double ms) {
		int base = (int)std::lround(ms * sr / 1000.0);
		base = base < 1 ? 1 : base;
		const int sp = (int)std::lround(spread_ms * sr / 1000.0);
		dl = base + (sp < 0 ? -sp : 0);
		dr = base + (sp > 0 ? sp : 0);
	}

	// Take n's settings, keeping this effect's running state (delay lines, reverb tail,
	// filter and gain states, phases) when the type and buffer sizes allow; false (this
	// effect unchanged) otherwise. AKStreamFx's Effect.carry_from.
	bool retune(const Fx &n) {
		if (n.type != type) {
			return false;
		}
		Fx t = n;
		t.setup(sr);
		if (t.line[0].size() != line[0].size() || t.rv.size() != rv.size() || t.rv_pre.size() != rv_pre.size() || t.xb.size() != xb.size()) {
			return false;
		}
		t.xb.swap(xb);
		for (int k = 0; k < 16; k++) {
			t.xs[k] = xs[k];
		}
		t.xw = xw;
		t.ph = ph;
		t.line[0].swap(line[0]);
		t.line[1].swap(line[1]);
		t.w = w;
		t.fb_l = fb_l;
		t.fb_r = fb_r;
		for (int c = 0; c < 2; c++) {
			for (int s = 0; s < 12; s++) {
				t.ap_z[c][s] = ap_z[c][s];
			}
			t.ph_last[c] = ph_last[c];
			t.sat_z[c] = sat_z[c];
			t.held[c] = held[c];
			t.ez[c] = ez[c];
			for (int k = 0; k < 3; k++) {
				t.bq[k].x1[c] = bq[k].x1[c];
				t.bq[k].x2[c] = bq[k].x2[c];
				t.bq[k].y1[c] = bq[k].y1[c];
				t.bq[k].y2[c] = bq[k].y2[c];
			}
		}
		t.gr_db = gr_db;
		t.cph = cph;
		t.rng = rng;
		t.gr_rate = gr_rate;
		t.gr_amp = gr_amp;
		t.ctr = ctr;
		t.rv.swap(rv);
		for (int k = 0; k < 24; k++) {
			t.rv_idx[k] = rv_idx[k];
		}
		for (int k = 0; k < 16; k++) {
			t.rv_store[k] = rv_store[k];
		}
		t.rv_pre.swap(rv_pre);
		t.rv_pw = rv_pw;
		t.rv_lcz = rv_lcz;
		t.rv_hcz = rv_hcz;
		t.lim_g = lim_g;
		*this = std::move(t);
		return true;
	}

	// Coefficients and buffers from the knobs; clears the state.
	void setup(int p_sr) {
		sr = p_sr;
		ph = 0.0;
		w = 0;
		fb_l = fb_r = 0.0;
		for (int c = 0; c < 2; c++) {
			for (int s = 0; s < 12; s++) {
				ap_z[c][s] = 0.0;
			}
			ph_last[c] = 0.0;
			sat_z[c] = 0.0;
		}
		gr_db = 0.0;
		if (type == CHORUS || type == FLANGER) {
			const int n = (int)std::ceil(std::max(delay_ms + depth_ms, line_ms) * sr / 1000.0) + 4;
			line[0].assign(n < 8 ? 8 : n, 0.0f);
			line[1].assign(n < 8 ? 8 : n, 0.0f);
		}
		cph = 0.0;
		rng = 0x9E3779B9u;
		gr_rate = 1.0;
		gr_amp = 1.0;
		ctr = 0;
		held[0] = held[1] = 0.0;
		ez[0] = ez[1] = 0.0;
		if (type == PITCH) {
			win = window_ms * sr / 1000.0;
			ratio_step = (1.0 - std::pow(2.0, semitones / 12.0)) / win;
			const int n = (int)std::ceil(win) + 4;
			line[0].assign(n, 0.0f);
			line[1].assign(n, 0.0f);
		}
		if (type == LIMITER) {
			lim_c = std::pow(10.0, ceiling_db / 20.0);
			lim_k = std::exp(-1.0 / std::max(1e-4, release_s * sr));
		}
		if (type == FILTER) {
			const double fc = std::min(cutoff_hz, 0.49 * sr);
			f_n = slope_db < 9.0 ? 1 : (slope_db < 18.0 ? 2 : 4);
			f_a = 1.0 - std::exp(-TAU * fc / sr);
			f_k = 1.0 / std::max(0.05, q);
			const double g = std::tan(PI * fc / sr);
			f_a1 = 1.0 / (1.0 + g * (g + f_k));
			f_a2 = g * f_a1;
			f_a3 = g * f_a2;
		}
		if (type == DELAY) {
			int n = (int)std::lround(time_ms * sr / 1000.0);
			n = n < 1 ? 1 : n;
			if (time_beats > 0.0) {
				n = std::max(1, (int)std::lround(2000.0 * sr / 1000.0));
			} else if (line_ms > 0.0) {
				n = std::max(n, (int)std::lround(line_ms * sr / 1000.0));   // room for a modulated time
			}
			n += std::abs((int)std::lround(spread_ms * sr / 1000.0));
			dn = n;
			delay_lengths(time_ms);
			line[0].assign(n, 0.0f);
			line[1].assign(n, 0.0f);
			e_k = 1.0 - std::exp(-TAU * damp_hz / sr);
		}
		if (type == REVERB) {
			const double scale = double(sr) / 44100.0;
			int total = 0;
			for (int k = 0; k < 24; k++) {
				const int ch = k / 12, j = k % 12;
				const int base = j < 8 ? RV_COMBS[j] : RV_PASSES[j - 8];
				int len = (int)std::lround((base + (ch == 1 ? 23 : 0)) * scale);
				len = len < 1 ? 1 : len;
				rv_off[k] = total;
				rv_len[k] = len;
				rv_idx[k] = 0;
				total += len;
			}
			rv.assign(total, 0.0f);
			for (int k = 0; k < 16; k++) {
				rv_store[k] = 0.0;
			}
			rv_fb = room * 0.28 + 0.7;
			rv_dk = damp * 0.4;
			rv_w1 = width * 0.5 + 0.5;
			rv_w2 = (1.0 - width) * 0.5;
			rv_pre.assign((size_t)std::lround(predelay_ms * sr / 1000.0), 0.0);
			rv_pw = 0;
			rv_lck = low_cut_hz > 0.0 ? 1.0 - std::exp(-TAU * std::min(low_cut_hz, 0.49 * sr) / sr) : 0.0;
			rv_hck = high_cut_hz > 0.0 ? 1.0 - std::exp(-TAU * std::min(high_cut_hz, 0.49 * sr) / sr) : 0.0;
			rv_lcz = rv_hcz = 0.0;
		}
		if (type == EQ) {
			shelf(bq[0], low_hz, low_db, false);
			peak(bq[1], mid_hz, mid_db, mid_q);
			shelf(bq[2], high_hz, high_db, true);
		}
		if (type == COMPRESSOR) {
			k_att = std::exp(-1.0 / (attack_s * sr > 1.0 ? attack_s * sr : 1.0));
			k_rel = std::exp(-1.0 / (release_s * sr > 1.0 ? release_s * sr : 1.0));
		}
		if (type >= FREQSHIFT) {
			setup_x();
		}
		if (type == SATURATE) {
			sat_g = db(drive_db);
			sat_off = std::tanh(asymmetry);
			sat_lp = 1.0 - std::exp(-TAU * tone_hz / sr);
			sat_out = db(output_db) / std::tanh(sat_g);   // a full-scale input peaks at output_db
		}
	}

	// A setting the matrix moves (AKStreamFx.mod_keys), by name: the knob, or nullptr.
	double *knob(const char *k) {
		int n = 0;
		const XKey *t = xkeys(type, n);
		for (int i = 0; i < n; i++) {
			if (std::strcmp(k, t[i].name) == 0) {
				return &xk[i];
			}
		}
		struct Named {
			const char *name;
			double Fx::*field;
		};
		static const Named NAMED[] = { { "mix", &Fx::mix }, { "dry", &Fx::dry }, { "wet", &Fx::wet }, { "feedback", &Fx::feedback },
			{ "rate_hz", &Fx::rate_hz }, { "depth_ms", &Fx::depth_ms }, { "delay_ms", &Fx::delay_ms }, { "spread", &Fx::spread },
			{ "center_hz", &Fx::center_hz }, { "range_octaves", &Fx::range_oct }, { "depth", &Fx::depth }, { "low_db", &Fx::low_db },
			{ "low_hz", &Fx::low_hz }, { "mid_db", &Fx::mid_db }, { "mid_hz", &Fx::mid_hz }, { "mid_q", &Fx::mid_q },
			{ "high_db", &Fx::high_db }, { "high_hz", &Fx::high_hz }, { "threshold_db", &Fx::threshold_db }, { "ratio", &Fx::ratio },
			{ "knee_db", &Fx::knee_db }, { "makeup_db", &Fx::makeup_db }, { "drive_db", &Fx::drive_db }, { "tone_hz", &Fx::tone_hz },
			{ "asymmetry", &Fx::asymmetry }, { "output_db", &Fx::output_db }, { "semitones", &Fx::semitones }, { "freq_hz", &Fx::freq_hz },
			{ "jitter", &Fx::jitter }, { "bits", &Fx::bits }, { "time_ms", &Fx::time_ms }, { "damp_hz", &Fx::damp_hz },
			{ "room", &Fx::room }, { "damp", &Fx::damp }, { "width", &Fx::width }, { "cutoff_hz", &Fx::cutoff_hz }, { "q", &Fx::q },
			{ "ceiling_db", &Fx::ceiling_db } };
		for (const Named &f : NAMED) {
			if (std::strcmp(k, f.name) == 0) {
				return &(this->*f.field);
			}
		}
		return nullptr;
	}

	// What's worked out from the knobs, again, after the matrix moved one (AKStreamFx's
	// Effect.recoef): the running state stays.
	void recoef() {
		switch (type) {
			case EQ: {
				Biquad old[3] = { bq[0], bq[1], bq[2] };
				shelf(bq[0], low_hz, low_db, false);
				peak(bq[1], mid_hz, mid_db, mid_q);
				shelf(bq[2], high_hz, high_db, true);
				for (int k = 0; k < 3; k++) {
					for (int c = 0; c < 2; c++) {
						bq[k].x1[c] = old[k].x1[c];
						bq[k].x2[c] = old[k].x2[c];
						bq[k].y1[c] = old[k].y1[c];
						bq[k].y2[c] = old[k].y2[c];
					}
				}
				break;
			}
			case SATURATE:
				sat_g = db(drive_db);
				sat_off = std::tanh(asymmetry);
				sat_lp = 1.0 - std::exp(-TAU * tone_hz / sr);
				sat_out = db(output_db) / std::tanh(sat_g);
				break;
			case PITCH:
				ratio_step = (1.0 - std::pow(2.0, semitones / 12.0)) / win;
				break;
			case DELAY:
				if (time_beats <= 0.0) {
					delay_lengths(time_ms);
					const int mx = std::max(dl, dr);
					if (mx > dn) {
						// Never past the line (it holds line_ms): shorten both sides alike.
						dl = std::max(1, dl - (mx - dn));
						dr = std::max(1, dr - (mx - dn));
					}
				}
				e_k = 1.0 - std::exp(-TAU * damp_hz / sr);
				break;
			case REVERB:
				rv_fb = room * 0.28 + 0.7;
				rv_dk = damp * 0.4;
				rv_w1 = width * 0.5 + 0.5;
				rv_w2 = (1.0 - width) * 0.5;
				break;
			case FILTER: {
				const double fc = std::min(cutoff_hz, 0.49 * sr);
				f_a = 1.0 - std::exp(-TAU * fc / sr);
				f_k = 1.0 / std::max(0.05, q);
				const double g = std::tan(PI * fc / sr);
				f_a1 = 1.0 / (1.0 + g * (g + f_k));
				f_a2 = g * f_a1;
				f_a3 = g * f_a2;
				break;
			}
			case LIMITER:
				lim_c = std::pow(10.0, ceiling_db / 20.0);
				break;
			case STUTTER:
				xc[0] = std::pow(2.0, xk[3] / 12.0);
				break;
			case CONDITIONER:
			case GEQ:
			case RESONATOR:
			case EXCITER:
			case WAVESHAPER:
			case MIDSIDE:
			case ENSEMBLE:
			case COMBULATOR:
			case TAPE:
			case TREEMONSTER:
			case SPRING:
			case BONSAI:
			case CHOW:
			case NEURON:
				recoef_x();
				break;
			case GRANULAR:
				recoef_g();
				break;
			case AIRWINDOWS:
				recoef_aw();
				break;
			case ROTARY:
				xc[0] = 1.0 - std::exp(-TAU * xk[6] / sr);
				xc[1] = 1.0 - std::exp(-1.0 / (xk[3] * sr));
				xc[2] = 1.0 - std::exp(-1.0 / (5.0 * xk[3] * sr));
				xc[3] = std::sin(TAU * 0.25 * xk[5]);
				xc[4] = std::cos(TAU * 0.25 * xk[5]);
				break;
			default:
				break;
		}
	}

	// RBJ cookbook shelving (slope 1) and peaking filters.
	void shelf(Biquad &b, double f, double gain_db, bool high) {
		const double A = std::pow(10.0, gain_db / 40.0);
		const double w0 = TAU * f / sr;
		const double cw = std::cos(w0), sw = std::sin(w0);
		const double alpha = sw / 2.0 * SQRT2;
		const double t = 2.0 * std::sqrt(A) * alpha;
		double b0, b1, b2, a0, a1, a2;
		if (!high) {
			b0 = A * ((A + 1) - (A - 1) * cw + t);
			b1 = 2 * A * ((A - 1) - (A + 1) * cw);
			b2 = A * ((A + 1) - (A - 1) * cw - t);
			a0 = (A + 1) + (A - 1) * cw + t;
			a1 = -2 * ((A - 1) + (A + 1) * cw);
			a2 = (A + 1) + (A - 1) * cw - t;
		} else {
			b0 = A * ((A + 1) + (A - 1) * cw + t);
			b1 = -2 * A * ((A - 1) + (A + 1) * cw);
			b2 = A * ((A + 1) + (A - 1) * cw - t);
			a0 = (A + 1) - (A - 1) * cw + t;
			a1 = 2 * ((A - 1) - (A + 1) * cw);
			a2 = (A + 1) - (A - 1) * cw - t;
		}
		b = Biquad();
		b.b0 = b0 / a0;
		b.b1 = b1 / a0;
		b.b2 = b2 / a0;
		b.a1 = a1 / a0;
		b.a2 = a2 / a0;
	}

	void peak(Biquad &b, double f, double gain_db, double q) {
		const double A = std::pow(10.0, gain_db / 40.0);
		const double w0 = TAU * f / sr;
		const double cw = std::cos(w0), sw = std::sin(w0);
		const double alpha = sw / (2.0 * (q < 0.05 ? 0.05 : q));
		const double a0 = 1 + alpha / A;
		b = Biquad();
		b.b0 = (1 + alpha * A) / a0;
		b.b1 = -2 * cw / a0;
		b.b2 = (1 - alpha * A) / a0;
		b.a1 = -2 * cw / a0;
		b.a2 = (1 - alpha / A) / a0;
	}

	inline double read(int c, double d) const {
		const std::vector<float> &L = line[c];
		const int n = (int)L.size();
		double pos = w - d;
		while (pos < 0.0) {
			pos += n;
		}
		const int i0 = (int)pos;
		const double fr = pos - i0;
		const int i1 = (i0 + 1) % n;
		return L[i0 % n] * (1.0 - fr) + L[i1] * fr;
	}

	double rnd() {
		rng = rng * 1664525u + 1013904223u;
		return rng / 4294967296.0;
	}

	// One stereo sample, in place.
	inline void tick(double &l, double &r) {
		switch (type) {
			case CHORUS:
			case FLANGER: {
				double wet[2];
				const double in[2] = { l, r };
				for (int c = 0; c < 2; c++) {
					double p = ph + (c == 1 ? spread * 0.25 : 0.0);
					double acc = 0.0;
					for (int v = 0; v < voices; v++) {
						const double lfo = std::sin(TAU * (p + double(v) / voices));
						const double d = (delay_ms + depth_ms * 0.5 * (1.0 + lfo)) * sr / 1000.0;
						acc += read(c, d);
					}
					wet[c] = acc / voices;
				}
				const int n = (int)line[0].size();
				line[0][w] = (float)(in[0] + feedback * wet[0]);
				line[1][w] = (float)(in[1] + feedback * wet[1]);
				w = (w + 1) % n;
				l = in[0] * dm() + wet[0] * wm();
				r = in[1] * dm() + wet[1] * wm();
				ph += rate_hz / sr;
				ph -= std::floor(ph);
				break;
			}
			case PHASER: {
				double io[2] = { l, r };
				for (int c = 0; c < 2; c++) {
					const double lfo = std::sin(TAU * (ph + (c == 1 ? spread * 0.25 : 0.0)));
					double fc = center_hz * std::pow(2.0, range_oct * 0.5 * depth * lfo);
					const double nyq = 0.49 * sr;
					fc = fc < 20.0 ? 20.0 : (fc > nyq ? nyq : fc);
					const double t = std::tan(PI * fc / sr);
					const double a = (t - 1.0) / (t + 1.0);
					double x = io[c] + feedback * ph_last[c];
					for (int s = 0; s < stages; s++) {
						const double y = a * x + ap_z[c][s];
						ap_z[c][s] = x - a * y;
						x = y;
					}
					ph_last[c] = x;
					io[c] = io[c] * dm() + x * wm();
				}
				l = io[0];
				r = io[1];
				ph += rate_hz / sr;
				ph -= std::floor(ph);
				break;
			}
			case EQ: {
				for (int b = 0; b < 3; b++) {
					l = bq[b].tick(l, 0);
					r = bq[b].tick(r, 1);
				}
				break;
			}
			case COMPRESSOR: {
				const double det = std::fabs(l) > std::fabs(r) ? std::fabs(l) : std::fabs(r);
				const double lev = 20.0 * std::log(det + 1e-12) / std::log(10.0);   // as GDScript (no log10)
				const double over = lev - threshold_db;
				double target;
				const double hk = knee_db * 0.5;
				if (knee_db > 0.0 && over > -hk && over < hk) {
					const double x = over + hk;
					target = -(1.0 - 1.0 / ratio) * x * x / (2.0 * knee_db);
				} else if (over >= hk) {
					target = -(1.0 - 1.0 / ratio) * over;
				} else {
					target = 0.0;
				}
				const double k = target < gr_db ? k_att : k_rel;
				gr_db = target + (gr_db - target) * k;
				const double g = db(gr_db + makeup_db);
				l *= g;
				r *= g;
				break;
			}
			case SATURATE: {
				double io[2] = { l, r };
				for (int c = 0; c < 2; c++) {
					const double y = (std::tanh(io[c] * sat_g + asymmetry) - sat_off) * sat_out;
					sat_z[c] += sat_lp * (y - sat_z[c]);
					io[c] = io[c] * dm() + sat_z[c] * wm();
				}
				l = io[0];
				r = io[1];
				break;
			}
			case PITCH: {
				// Two taps sweep through a window, crossfaded, each reading at
				// the shifted speed (a classic delay-line pitch shifter).
				const double p2 = ph + 0.5 - std::floor(ph + 0.5);
				const double g1 = std::sin(PI * ph) * std::sin(PI * ph);
				const double g2 = 1.0 - g1;
				const double in[2] = { l, r };
				double wet[2];
				for (int c = 0; c < 2; c++) {
					wet[c] = g1 * read(c, ph * win + 1.0) + g2 * read(c, p2 * win + 1.0);
				}
				const int n = (int)line[0].size();
				line[0][w] = (float)in[0];
				line[1][w] = (float)in[1];
				w = (w + 1) % n;
				ph += ratio_step;
				ph -= std::floor(ph);
				l = in[0] * dm() + wet[0] * wm();
				r = in[1] * dm() + wet[1] * wm();
				break;
			}
			case RING: {
				const double c = std::sin(TAU * cph);
				cph += freq_hz * std::pow(2.0, depth * std::sin(TAU * ph)) / sr;
				cph -= std::floor(cph);
				ph += rate_hz / sr;
				ph -= std::floor(ph);
				l = l * dm() + l * c * wm();
				r = r * dm() + r * c * wm();
				break;
			}
			case GROWL: {
				// Loudness pulses at about rate_hz, each cycle a little off in
				// length and depth: a rasp.
				const double env = 0.5 - 0.5 * std::cos(TAU * ph);
				const double g = 1.0 - depth * gr_amp * env;
				ph += rate_hz * gr_rate / sr;
				if (ph >= 1.0) {
					ph -= std::floor(ph);
					gr_rate = 1.0 + jitter * (rnd() - 0.5);
					gr_amp = 1.0 - jitter * 0.6 * rnd();
				}
				l = l * dm() + l * g * wm();
				r = r * dm() + r * g * wm();
				break;
			}
			case CRUSH: {
				if (ctr == 0) {
					const double step = std::pow(2.0, 1.0 - bits);
					held[0] = std::floor(l / step + 0.5) * step;
					held[1] = std::floor(r / step + 0.5) * step;
				}
				ctr = (ctr + 1) % hold;
				l = l * dm() + held[0] * wm();
				r = r * dm() + held[1] * wm();
				break;
			}
			case DELAY: {
				int il = w - dl, ir = w - dr;
				il += il < 0 ? dn : 0;
				ir += ir < 0 ? dn : 0;
				const double y[2] = { line[0][il], line[1][ir] };
				const double in[2] = { l, r };
				for (int c = 0; c < 2; c++) {
					ez[c] += e_k * (y[c] - ez[c]);
				}
				if (mode == 0) {
					line[0][w] = (float)(in[0] + feedback * ez[0]);
					line[1][w] = (float)(in[1] + feedback * ez[1]);
				} else if (mode == 1) {
					line[0][w] = (float)(in[0] + feedback * ez[1]);
					line[1][w] = (float)(in[1] + feedback * ez[0]);
				} else {
					line[0][w] = (float)((in[0] + in[1]) * 0.5 + feedback * ez[1]);
					line[1][w] = (float)(feedback * ez[0]);
				}
				w = (w + 1) % dn;
				l = in[0] * da() + y[0] * wm();
				r = in[1] * da() + y[1] * wm();
				break;
			}
			case FILTER: {
				double *io[2] = { &l, &r };
				for (int ch = 0; ch < 2; ch++) {
					double *z = ap_z[ch];
					double x = *io[ch];
					if (f_n == 1) {
						z[0] += (x - z[0]) * f_a;
						x = mode == 1 ? x - z[0] : z[0];
					} else {
						for (int s = 0; s < f_n / 2; s++) {
							double *zz = z + 2 * s;
							const double v3 = x - zz[1];
							const double v1 = f_a1 * zz[0] + f_a2 * v3;
							const double v2 = zz[1] + f_a2 * zz[0] + f_a3 * v3;
							zz[0] = 2.0 * v1 - zz[0];
							zz[1] = 2.0 * v2 - zz[1];
							x = mode == 1 ? x - f_k * v1 - v2 : v2;
						}
					}
					*io[ch] = x;
				}
				break;
			}
			case LIMITER: {
				const double p = std::max(std::fabs(l), std::fabs(r));
				const double need = p > lim_c ? lim_c / p : 1.0;
				if (need < lim_g) {
					lim_g = need;
				} else {
					lim_g = need - (need - lim_g) * lim_k;
				}
				l *= lim_g;
				r *= lim_g;
				break;
			}
			case REVERB: {
				double input = (l + r) * 0.015;
				if (rv_lck > 0.0) {
					rv_lcz += (input - rv_lcz) * rv_lck;
					input -= rv_lcz;
				}
				if (rv_hck > 0.0) {
					rv_hcz += (input - rv_hcz) * rv_hck;
					input = rv_hcz;
				}
				if (!rv_pre.empty()) {
					const double pd = rv_pre[rv_pw];
					rv_pre[rv_pw] = input;
					rv_pw = rv_pw + 1 == (int)rv_pre.size() ? 0 : rv_pw + 1;
					input = pd;
				}
				double out[2];
				for (int ch = 0; ch < 2; ch++) {
					double acc = 0.0;
					for (int j = 0; j < 8; j++) {
						const int k = ch * 12 + j;
						float &cell = rv[rv_off[k] + rv_idx[k]];
						const double y = cell;
						double &st = rv_store[ch * 8 + j];
						st = y * (1.0 - rv_dk) + st * rv_dk;
						cell = (float)(input + st * rv_fb);
						acc += y;
						if (++rv_idx[k] == rv_len[k]) {
							rv_idx[k] = 0;
						}
					}
					for (int j = 8; j < 12; j++) {
						const int k = ch * 12 + j;
						float &cell = rv[rv_off[k] + rv_idx[k]];
						const double b = cell;
						const double x = acc;
						acc = b - x;
						cell = (float)(x + b * 0.5);
						if (++rv_idx[k] == rv_len[k]) {
							rv_idx[k] = 0;
						}
					}
					out[ch] = acc;
				}
				l = l * da() + (out[0] * rv_w1 + out[1] * rv_w2) * wm();
				r = r * da() + (out[1] * rv_w1 + out[0] * rv_w2) * wm();
				break;
			}
			case FREQSHIFT:
				tick_freqshift(l, r);
				break;
			case ROTARY:
				tick_rotary(l, r);
				break;
			case STUTTER:
				tick_stutter(l, r);
				break;
			case CONDITIONER:
				tick_conditioner(l, r);
				break;
			case GEQ:
				for (int b = 0; b < 11; b++) {
					if (xk[b] != 0.0 && GEQ_HZ[b] < 0.45 * sr) {
						l = xbq(13 * b, l, 0);
						r = xbq(13 * b, r, 1);
					}
				}
				l *= xc[0];
				r *= xc[0];
				break;
			case RESONATOR:
				tick_resonator(l, r);
				break;
			case EXCITER: {
				const double io[2] = { l, r };
				double out[2];
				for (int c = 0; c < 2; c++) {
					const double h = xbq(0, io[c], c);
					out[c] = xbq(13, std::tanh(xc[0] * h) * xc[1], c);
				}
				l = io[0] * da() + out[0] * wm();
				r = io[1] * da() + out[1] * wm();
				break;
			}
			case WAVESHAPER:
				tick_waveshaper(l, r);
				break;
			case ENSEMBLE:
				tick_ensemble(l, r);
				break;
			case COMBULATOR:
				tick_combulator(l, r);
				break;
			case TAPE:
				tick_tape(l, r);
				break;
			case TREEMONSTER:
				tick_treemonster(l, r);
				break;
			case SPRING:
				tick_spring(l, r);
				break;
			case BONSAI:
				tick_bonsai(l, r);
				break;
			case CHOW:
				tick_chow(l, r);
				break;
			case NEURON:
				tick_neuron(l, r);
				break;
			case GRANULAR:
				tick_granular(l, r);
				break;
			case AIRWINDOWS:
				tick_aw(l, r);
				break;
			case MIDSIDE: {
				double m = (l + r) * 0.5, sd = (l - r) * 0.5;
				if (xk[2] > 0.0) {
					xs[0] += (sd - xs[0]) * xc[0];
					sd -= xs[0];
				}
				m *= xc[1];
				sd *= xc[2];
				l = m * xc[3] + sd;
				r = m * xc[4] - sd;
				break;
			}
			default:
				break;
		}
	}

	// ---- the newer types (their knobs in xk[], state in xb / xs / xw)

	// Frequency shifter: xk shift_hz, stereo, echo_ms. A Hilbert pair (two chains of four
	// second-order allpasses, Olli Niemitalo's published 90-degree design) splits each
	// channel into I and Q; I cos + Q sin moves every partial up by shift_hz (single
	// sideband). The right channel shifts by shift_hz (1 - 2 stereo). Feedback goes back in
	// through an echo of echo_ms (0: one sample), so each repeat is shifted again.
	// xb: [0, 64) the allpass states (channel, chain, section: x1 x2 y1 y2), [64, 66) the
	// I chain's extra sample, then the echo lines (L, R). xs: 0, 1 the carrier phases, 2, 3
	// the last outputs.
	static constexpr double HB_A[4] = { 0.6923878, 0.9360654322959, 0.9882295226860, 0.9987488452737 };
	static constexpr double HB_B[4] = { 0.4021921162426, 0.8561710882420, 0.9722909545651, 0.9952884791278 };

	void setup_x() {
		for (int k = 0; k < 16; k++) {
			xs[k] = 0.0;
		}
		xw = 0;
		if (type == FREQSHIFT) {
			const int en = (int)std::lround(xk[2] * sr / 1000.0);
			xb.assign(66 + 2 * en, 0.0);
		} else if (type == ROTARY) {
			// Two mono lines (horn, drum) of RO_LINE_MS, then nothing else: xs holds
			// 0 horn angle, 1 drum angle (cycles), 2 horn rate, 3 drum rate (Hz),
			// 4, 5 the crossover's one-poles.
			const int n = (int)std::ceil(RO_LINE_MS * sr / 1000.0) + 4;
			xb.assign(2 * n, 0.0);
			xs[1] = 0.25;
			xs[2] = ro_target(xk[1]);
			xs[3] = ro_target(xk[2]);
			xc[0] = 1.0 - std::exp(-TAU * xk[6] / sr);
			xc[1] = 1.0 - std::exp(-1.0 / (xk[3] * sr));
			xc[2] = 1.0 - std::exp(-1.0 / (5.0 * xk[3] * sr));
			xc[3] = std::sin(TAU * 0.25 * xk[5]);
			xc[4] = std::cos(TAU * 0.25 * xk[5]);
		} else if (type == GRANULAR) {
			setup_g();
		} else if (type == AIRWINDOWS) {
			setup_aw();
		} else if (type >= ENSEMBLE) {
			setup_b();
		} else if (type >= CONDITIONER) {
			// Biquads in xb (13 each: b0 b1 b2 a1 a2, then x1 x2 y1 y2 per channel), the rest in xs.
			const int nb = type == CONDITIONER ? 2 : (type == GEQ ? 11 : (type == RESONATOR ? 3 : (type == EXCITER ? 2 : 0)));
			xb.assign(13 * nb, 0.0);
			recoef_x();
		} else if (type == STUTTER) {
			// Two stereo buffers of ST_MAX_S: one records, the other holds the slice (they swap at
			// each capture). xs: 0 the recording one, 1 a slice held, 2 its start, 3 its length,
			// 4 the place in this repeat, 5 samples since the capture, 6 fresh samples recorded.
			const int n = (int)std::ceil(ST_MAX_S * sr) + 2;
			xb.assign(4 * n, 0.0);
			xc[0] = std::pow(2.0, xk[3] / 12.0);
		} else {
			xb.clear();
		}
	}

	inline double hilbert_chain(double x, const double *co, double *z) {
		for (int s = 0; s < 4; s++) {
			double *q = z + 4 * s;
			const double a = co[s] * co[s];
			const double y = a * (x + q[3]) - q[1];
			q[1] = q[0];
			q[0] = x;
			q[3] = q[2];
			q[2] = y;
			x = y;
		}
		return x;
	}

	inline void tick_freqshift(double &l, double &r) {
		const int en = ((int)xb.size() - 66) / 2;
		double in[2] = { l, r };
		double fbk[2];
		if (en > 0) {
			fbk[0] = xb[66 + xw];
			fbk[1] = xb[66 + en + xw];
		} else {
			fbk[0] = xs[2];
			fbk[1] = xs[3];
		}
		double out[2];
		for (int c = 0; c < 2; c++) {
			const double x = in[c] + feedback * fbk[c];
			double *z = xb.data() + c * 32;
			const double i_now = hilbert_chain(x, HB_A, z);
			const double q = hilbert_chain(x, HB_B, z + 16);
			const double i = xb[64 + c];
			xb[64 + c] = i_now;
			const double ph = TAU * xs[c];
			out[c] = i * std::cos(ph) + q * std::sin(ph);
			const double hz = c == 0 ? xk[0] : xk[0] * (1.0 - 2.0 * xk[1]);
			xs[c] += hz / sr;
			xs[c] -= std::floor(xs[c]);
		}
		xs[2] = out[0];
		xs[3] = out[1];
		if (en > 0) {
			xb[66 + xw] = out[0];
			xb[66 + en + xw] = out[1];
			xw = xw + 1 == en ? 0 : xw + 1;
		}
		l = in[0] * dm() + out[0] * wm();
		r = in[1] * dm() + out[1] * wm();
	}

	// Rotary speaker: xk speed (0 slow .. 1 fast), horn_hz and drum_hz (the fast rates; slow is
	// RO_SLOW of them), accel_s (the horn's time constant; the heavier drum takes 5 times as
	// long), drive (a tube stage before it), spread (the two mics, 0 together .. 1 half a turn
	// apart), crossover_hz, doppler, tremolo. A two-way cabinet: the crossover splits the mono
	// sum, the horn (above) and the drum (below) turn at their own rates, each heard by two mics
	// through a delay that swings with the rotor's distance (Doppler) and a gain that swings with
	// where it points (the horn's beam more than the drum's).
	static constexpr double RO_LINE_MS = 4.0;
	static constexpr double RO_SLOW = 0.12;
	inline double ro_target(double fast) const { return fast * (RO_SLOW + (1.0 - RO_SLOW) * xk[0]); }

	inline double ro_read(int base, int n, double d) const {
		double pos = xw - d;
		if (pos < 0.0) {
			pos += n;
		}
		const int i0 = (int)pos;
		const double fr = pos - i0;
		const int i1 = i0 + 1 == n ? 0 : i0 + 1;
		return xb[base + i0] * (1.0 - fr) + xb[base + i1] * fr;
	}

	inline void tick_rotary(double &l, double &r) {
		const int n = (int)xb.size() / 2;
		double x = (l + r) * 0.5;
		if (xk[4] > 0.0) {
			const double g = 1.0 + 4.0 * xk[4];
			x = std::tanh(g * x) / g;   // unity for quiet signals, rounding off loud ones
		}
		// Crossover: two one-poles for the drum, the rest for the horn (they sum back to x).
		const double ck = xc[0];
		xs[4] += ck * (x - xs[4]);
		xs[5] += ck * (xs[4] - xs[5]);
		const double lo = xs[5];
		const double hi = x - lo;
		// Rotor speeds ease toward the target (the drum five times slower).
		xs[2] += xc[1] * (ro_target(xk[1]) - xs[2]);
		xs[3] += xc[2] * (ro_target(xk[2]) - xs[3]);
		const double hs = std::sin(TAU * xs[0]), hc = std::cos(TAU * xs[0]);
		const double ds = std::sin(TAU * xs[1]), dc = std::cos(TAU * xs[1]);
		// Mics at -+ a quarter turn times spread.
		const double ms = xc[3], mc = xc[4];
		const double sr_ms = sr / 1000.0;
		double out[2];
		for (int c = 0; c < 2; c++) {
			const double sgn = c == 0 ? -1.0 : 1.0;
			// cos(rotor - mic): 1 when the rotor points at the mic.
			const double ch = hc * mc + hs * ms * sgn;
			const double cd = dc * mc + ds * ms * sgn;
			const double h = ro_read(0, n, (2.0 - 0.5 * xk[7] * ch) * sr_ms) * (1.0 + 0.45 * xk[8] * ch);
			const double d = ro_read(n, n, (2.0 - 0.35 * xk[7] * cd) * sr_ms) * (1.0 + 0.2 * xk[8] * cd);
			out[c] = h + d;
		}
		xb[xw] = hi;
		xb[n + xw] = lo;
		xw = xw + 1 == n ? 0 : xw + 1;
		xs[0] += xs[2] / sr;
		xs[0] -= std::floor(xs[0]);
		xs[1] += xs[3] / sr;
		xs[1] -= std::floor(xs[1]);
		l = l * dm() + out[0] * wm();
		r = r * dm() + out[1] * wm();
	}

	// ---- the Surge-table effects (original designs): biquads kept in xb, coefficients in recoef_x.
	static constexpr double GEQ_HZ[11] = { 30.0, 60.0, 120.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 12000.0, 16000.0 };

	inline double xbq(int o, double x, int ch) {
		double *q = xb.data() + o;
		double *z = q + 5 + 4 * ch;
		const double y = q[0] * x + q[1] * z[0] + q[2] * z[1] - q[3] * z[2] - q[4] * z[3];
		z[1] = z[0];
		z[0] = x;
		z[3] = z[2];
		z[2] = y;
		return y;
	}
	void xbq_set(int o, const Biquad &b) {
		xb[o] = b.b0;
		xb[o + 1] = b.b1;
		xb[o + 2] = b.b2;
		xb[o + 3] = b.a1;
		xb[o + 4] = b.a2;
	}
	// RBJ band-pass (0 dB at its peak) and high-pass.
	void bandpass(Biquad &b, double f, double q) {
		const double w0 = TAU * std::min(f, 0.49 * sr) / sr;
		const double cw = std::cos(w0), alpha = std::sin(w0) / (2.0 * q);
		const double a0 = 1.0 + alpha;
		b = Biquad();
		b.b0 = alpha / a0;
		b.b1 = 0.0;
		b.b2 = -alpha / a0;
		b.a1 = -2.0 * cw / a0;
		b.a2 = (1.0 - alpha) / a0;
	}
	void highpass(Biquad &b, double f, double q) {
		const double w0 = TAU * std::min(f, 0.49 * sr) / sr;
		const double cw = std::cos(w0), alpha = std::sin(w0) / (2.0 * q);
		const double a0 = 1.0 + alpha;
		b = Biquad();
		b.b0 = (1.0 + cw) * 0.5 / a0;
		b.b1 = -(1.0 + cw) / a0;
		b.b2 = (1.0 + cw) * 0.5 / a0;
		b.a1 = -2.0 * cw / a0;
		b.a2 = (1.0 - alpha) / a0;
	}
	void lowpass(Biquad &b, double f, double q) {
		const double w0 = TAU * std::min(f, 0.49 * sr) / sr;
		const double cw = std::cos(w0), alpha = std::sin(w0) / (2.0 * q);
		const double a0 = 1.0 + alpha;
		b = Biquad();
		b.b0 = (1.0 - cw) * 0.5 / a0;
		b.b1 = (1.0 - cw) / a0;
		b.b2 = (1.0 - cw) * 0.5 / a0;
		b.a1 = -2.0 * cw / a0;
		b.a2 = (1.0 - alpha) / a0;
	}
	static inline double ws_curve(int c, double u) {
		switch (c) {
			case 1: return u < -1.0 ? -1.0 : (u > 1.0 ? 1.0 : u);
			case 2: {
				const double v = u - 1.0 - 4.0 * std::floor((u - 1.0) / 4.0);
				return std::fabs(v - 2.0) - 1.0;
			}
			case 3: return std::sin(u);
			case 4: return u >= 0.0 ? std::tanh(u) : -0.6 * (1.0 - std::exp(u / 0.6));
			case 5: {
				const double q = std::floor(u * 8.0 + 0.5) / 8.0;
				return q < -1.0 ? -1.0 : (q > 1.0 ? 1.0 : q);
			}
			default: return std::tanh(u);
		}
	}

	// Coefficients of the Surge-table effects from their knobs (setup_x and recoef).
	void recoef_x() {
		Biquad t;
		switch (type) {
			case CONDITIONER:
				shelf(t, 200.0, xk[0], false);
				xbq_set(0, t);
				shelf(t, 4000.0, xk[1], true);
				xbq_set(13, t);
				xc[0] = std::exp(-1.0 / std::max(1.0, xk[5] * sr / 1000.0));
				xc[1] = std::exp(-1.0 / std::max(1.0, xk[6] * sr / 1000.0));
				xc[2] = db(xk[7]);
				xc[3] = xk[3] > 0.0 ? 1.0 - xk[3] : 1.0;
				xc[4] = xk[3] < 0.0 ? 1.0 + xk[3] : 1.0;
				break;
			case GEQ:
				for (int b = 0; b < 11; b++) {
					peak(t, std::min(GEQ_HZ[b], 0.49 * sr), xk[b], 1.41);
					xbq_set(13 * b, t);
				}
				xc[0] = db(xk[11]);
				break;
			case RESONATOR:
				for (int b = 0; b < 3; b++) {
					bandpass(t, xk[b], xk[3 + b]);
					xbq_set(13 * b, t);
					xc[b] = db(xk[6 + b]);
				}
				xc[3] = db(xk[10]);
				break;
			case EXCITER:
				highpass(t, xk[0], 0.707);
				xbq_set(0, t);
				xbq_set(13, t);
				xc[0] = 1.0 + 24.0 * xk[1];
				xc[1] = 1.0 / xc[0];
				break;
			case WAVESHAPER:
				xc[0] = xk[3] > 0.0 ? 1.0 - std::exp(-TAU * std::min(xk[3], 0.49 * sr) / sr) : 0.0;
				xc[1] = xk[4] > 0.0 ? 1.0 - std::exp(-TAU * std::min(xk[4], 0.49 * sr) / sr) : 0.0;
				xc[2] = db(xk[1]);
				xc[3] = ws_curve((int)std::lround(xk[0]), xk[2]);
				xc[4] = db(xk[5]);
				break;
			case ENSEMBLE:
			case COMBULATOR:
			case TAPE:
			case TREEMONSTER:
			case SPRING:
			case BONSAI:
			case CHOW:
			case NEURON:
				recoef_b();
				break;
			case MIDSIDE:
				xc[0] = xk[2] > 0.0 ? 1.0 - std::exp(-TAU * std::min(xk[2], 0.49 * sr) / sr) : 0.0;
				xc[1] = db(xk[0]);
				xc[2] = db(xk[1]);
				xc[3] = 1.0 - std::max(0.0, xk[3]);
				xc[4] = 1.0 + std::min(0.0, xk[3]);
				break;
			default:
				break;
		}
	}

	// Conditioner: bass and treble shelves (200 Hz, 4 kHz), width (the side's gain), balance, then
	// a peak limiter with a 6 dB soft knee at threshold_db (attack and release in ms), output gain.
	// xs[0] the gain reduction (dB), xs[1] the held peak.
	inline void tick_conditioner(double &l, double &r) {
		l = xbq(13, xbq(0, l, 0), 0);
		r = xbq(13, xbq(0, r, 1), 1);
		const double m = (l + r) * 0.5, sd = (l - r) * 0.5 * xk[2];
		l = (m + sd) * xc[3];
		r = (m - sd) * xc[4];
		// The peak, held and falling at the release; the gain follows it at the attack.
		xs[1] = std::max(std::max(std::fabs(l), std::fabs(r)), xs[1] * xc[1]);
		const double over = 20.0 * std::log(xs[1] + 1e-12) / std::log(10.0) - xk[4];
		const double target = over <= -3.0 ? 0.0 : (over < 3.0 ? -(over + 3.0) * (over + 3.0) / 12.0 : -over);
		xs[0] = target + (xs[0] - target) * xc[0];
		const double g = db(xs[0]) * xc[2];
		l *= g;
		r *= g;
	}

	// Resonator: three band-passes (0 dB at their peaks) at freqN_hz with qN, each at gainN_db,
	// summed (parallel) or one into the next (series: their gains multiplied), then output_db.
	inline void tick_resonator(double &l, double &r) {
		const double io[2] = { l, r };
		double out[2];
		for (int c = 0; c < 2; c++) {
			if (xk[9] >= 0.5) {
				out[c] = xbq(26, xbq(13, xbq(0, io[c], c), c), c) * xc[0] * xc[1] * xc[2];
			} else {
				out[c] = xbq(0, io[c], c) * xc[0] + xbq(13, io[c], c) * xc[1] + xbq(26, io[c], c) * xc[2];
			}
			out[c] *= xc[3];
		}
		l = io[0] * dm() + out[0] * wm();
		r = io[1] * dm() + out[1] * wm();
	}

	// Waveshaper: an optional one-pole high-pass (pre_hp_hz), the curve on drive x input + bias
	// (its value at the bias taken off, so silence stays silent), an optional one-pole low-pass
	// (post_lp_hz), output_db. xs: 0, 1 the high-pass states, 2, 3 the low-pass states.
	inline void tick_waveshaper(double &l, double &r) {
		const int cv = (int)std::lround(xk[0]);
		double io[2] = { l, r };
		for (int c = 0; c < 2; c++) {
			double x = io[c];
			if (xc[0] > 0.0) {
				xs[c] += (x - xs[c]) * xc[0];
				x -= xs[c];
			}
			double y = ws_curve(cv, xc[2] * x + xk[2]) - xc[3];
			if (xc[1] > 0.0) {
				xs[2 + c] += (y - xs[2 + c]) * xc[1];
				y = xs[2 + c];
			}
			io[c] = io[c] * dm() + y * xc[4] * wm();
		}
		l = io[0];
		r = io[1];
	}

	// ---- Surge-table effects, group B (original designs). Lines in xb read with ro_read (shared
	// write place xw), coefficients in recoef_b, state in xs.
	static constexpr double EN_LINE_MS = 48.0;
	static constexpr double TP_LINE_MS = 6.0;
	static constexpr double TP_BASE_MS = 3.0;
	static constexpr int SP_STAGES = 40;
	static constexpr double SP_LINE_MS = 92.0;
	static constexpr double NE_LINE_S = 0.3;
	static constexpr double NE_R[4] = { 1.0, 0.811, 0.677, 0.543 };

	// The spring's allpass stretch: each stage's delay is K samples, so its dispersion fills the
	// band below about 4.5 kHz.
	inline int sp_k() const { return std::max(1, (int)std::lround(sr / 9000.0)); }
	inline double op(double f) const { return 1.0 - std::exp(-TAU * std::min(f, 0.49 * sr) / sr); }

	// Buffers of the group B types (setup_x).
	void setup_b() {
		int n = 0;
		switch (type) {
			case ENSEMBLE:
				n = (int)std::ceil(EN_LINE_MS * sr / 1000.0) + 4;
				xb.assign(n, 0.0);
				break;
			case COMBULATOR:
				n = (int)std::ceil(sr / 20.0) + 4;
				xb.assign(3 * n, 0.0);
				break;
			case TAPE:
				n = (int)std::ceil(TP_LINE_MS * sr / 1000.0) + 4;
				xb.assign(2 * n + 26, 0.0);
				break;
			case SPRING:
				n = (int)std::ceil(SP_LINE_MS * sr / 1000.0) + 4;
				xb.assign(2 * n + 4 * SP_STAGES * sp_k(), 0.0);
				break;
			case NEURON:
				n = (int)std::ceil(NE_LINE_S * sr) + 4;
				xb.assign(4 * n, 0.0);
				break;
			default:
				xb.clear();
				break;
		}
		recoef_b();
	}

	// The group B types' line length (one line; they all share xw).
	inline int b_line() const {
		switch (type) {
			case COMBULATOR: return (int)xb.size() / 3;
			case TAPE: return ((int)xb.size() - 26) / 2;
			case SPRING: return ((int)xb.size() - 4 * SP_STAGES * sp_k()) / 2;
			case NEURON: return (int)xb.size() / 4;
			default: return (int)xb.size();
		}
	}

	void recoef_b() {
		Biquad t;
		switch (type) {
			case ENSEMBLE: {
				const double c = xk[4] * sr / 1000.0;
				xc[0] = op(xk[5]);
				xc[1] = xk[0] / sr;
				xc[2] = xk[2] / sr;
				xc[3] = c;
				xc[4] = 0.45 * xk[1] * c;
				xc[5] = 0.06 * xk[3] * c;
				break;
			}
			case COMBULATOR: {
				for (int k = 0; k < 3; k++) {
					const double f = xk[0] * (k == 0 ? 1.0 : std::pow(2.0, xk[k] / 12.0));
					xc[k] = sr / std::clamp(f, 20.0, 0.45 * sr);
					xc[4 + k] = db(xk[6 + k]) * std::sqrt(1.0 - xk[3] * xk[3]);
				}
				xc[3] = op(xk[4]);
				xc[7] = 1.0 - std::exp(-1.0 / (0.001 * sr));
				xc[8] = 1.0 - std::exp(-1.0 / (0.05 * sr));
				// Pans: comb 1 in the middle, 2 left and 3 right by width.
				const double p[3] = { 0.0, -xk[9], xk[9] };
				for (int k = 0; k < 3; k++) {
					xc[10 + k] = (1.0 - p[k]) / 3.0;
					xc[13 + k] = (1.0 + p[k]) / 3.0;
				}
				break;
			}
			case TAPE: {
				const int n = b_line();
				xc[0] = db(xk[0]);
				xc[1] = op(2000.0);
				xc[2] = 1.0 / xc[0];
				xc[3] = db(xk[7]);
				xc[4] = 0.7 / sr;
				xc[5] = 6.1 / sr;
				xc[6] = 13.3 / sr;
				xc[7] = TP_BASE_MS * sr / 1000.0;
				xc[8] = xk[2] * 1.2 * sr / 1000.0;
				xc[9] = xk[3] * 0.06 * sr / 1000.0;
				peak(t, xk[4], xk[5], 1.0);
				xbq_set(2 * n, t);
				lowpass(t, xk[6], 0.707);
				xbq_set(2 * n + 13, t);
				break;
			}
			case TREEMONSTER:
				xc[0] = db(xk[0]);
				xc[1] = xk[1] > 0.0 ? 1.0 - std::exp(-1.0 / (xk[1] * sr / 1000.0)) : 1.0;
				xc[2] = std::pow(2.0, xk[2] / 12.0);
				xc[3] = op(xk[3]);
				xc[4] = op(xk[4]);
				break;
			case SPRING: {
				// The loop: the line and the chain's delay at low frequencies.
				const double ls = xk[2] / 1000.0 + SP_STAGES * sp_k() * (1.0 + xk[1]) / (1.0 - xk[1]) / sr;
				xc[0] = std::pow(10.0, -3.0 * ls / xk[0]);
				xc[1] = op(xk[3]);
				xc[2] = xk[2] * sr / 1000.0;
				xc[3] = xk[2] * 1.13 * sr / 1000.0;
				xc[4] = (1.0 + xk[4]) * 0.5;
				xc[5] = (1.0 - xk[4]) * 0.5;
				break;
			}
			case BONSAI:
				xc[0] = op(xk[0]);
				xc[1] = db(xk[1]);
				xc[2] = op(2.0 * xk[0]);
				xc[3] = db(xk[3]);
				xc[4] = 1.0 / xc[3];
				xc[5] = op(xk[4]);
				xc[6] = db(xk[5]);
				break;
			case CHOW:
				xc[0] = db(xk[3]);
				xc[1] = db(xk[0]);
				xc[2] = 1.0 / xk[1];
				xc[3] = op(10.0);
				xc[4] = op(xk[4]);
				xc[5] = db(xk[5]) / xc[0];
				break;
			case NEURON:
				xc[0] = xk[0] * sr / 1000.0;
				xc[1] = 0.1 * xk[3];
				xc[2] = xk[4] / sr;
				xc[3] = op(xk[5]);
				xc[4] = 1.0 + 7.0 * xk[2];
				xc[5] = 1.0 / xc[4];
				xc[6] = (1.0 + xk[6]) * 0.5;
				xc[7] = (1.0 - xk[6]) * 0.5;
				break;
			default:
				break;
		}
	}

	// Ensemble: a string-ensemble chorus as the bucket-brigade ones: the mono sum through a
	// two-pole low-pass at tone_hz (the BBD's band limit) into one line read by three taps whose
	// delays (about center_ms) swing on a slow and a fast sine, each a third of a cycle from the
	// next, so their mean delay holds still; the taps go left, middle and right by width, and
	// through one more one-pole low-pass each. xs: 0 slow phase, 1 fast phase, 2, 3 the input low-pass,
	// 4, 5 the outputs' low-passes.
	inline void tick_ensemble(double &l, double &r) {
		const int n = (int)xb.size();
		const double a = xc[0];
		xs[2] += (0.5 * (l + r) - xs[2]) * a;
		xs[3] += (xs[2] - xs[3]) * a;
		xb[xw] = xs[3];
		double t[3];
		for (int k = 0; k < 3; k++) {
			const double d = xc[3] + xc[4] * std::sin(TAU * (xs[0] + k / 3.0)) + xc[5] * std::sin(TAU * (xs[1] + k / 3.0));
			t[k] = ro_read(0, n, d);
		}
		xw = xw + 1 == n ? 0 : xw + 1;
		const double w = xk[6];
		const double wl = (t[0] * (1.0 + w) + t[1] + t[2] * (1.0 - w)) / 3.0;
		const double wr = (t[2] * (1.0 + w) + t[1] + t[0] * (1.0 - w)) / 3.0;
		xs[4] += (wl - xs[4]) * a;
		xs[5] += (wr - xs[5]) * a;
		xs[0] += xc[1];
		xs[0] -= std::floor(xs[0]);
		xs[1] += xc[2];
		xs[1] -= std::floor(xs[1]);
		l = l * dm() + xs[4] * wm();
		r = r * dm() + xs[5] * wm();
	}

	// Combulator: three combs on the mono sum, tuned to tune_hz and offset2 / offset3 semitones
	// above it, with resonance (the feedback; negative: odd harmonics, an octave down) through a
	// one-pole low-pass at tone_hz in each loop; each comb's level normalised for broadband input
	// (x sqrt(1 - resonance^2)) and gainN_db; comb 1 in the middle, 2 and 3 left and right by
	// width. noise swaps input for white noise that follows the input's envelope, so a tone that
	// misses the combs still rings them. xs: 0..2 the loops' low-passes, 3 the envelope.
	inline void tick_combulator(double &l, double &r) {
		const int n = (int)xb.size() / 3;
		double x = 0.5 * (l + r);
		if (xk[5] > 0.0) {
			const double e = std::fabs(x);
			xs[3] += (e - xs[3]) * (e > xs[3] ? xc[7] : xc[8]);
			const double nz = (2.0 * rnd() - 1.0) * xs[3] * 1.7;
			x = x * (1.0 - xk[5]) + nz * xk[5];
		}
		double ol = 0.0, orr = 0.0;
		for (int k = 0; k < 3; k++) {
			const double y = ro_read(k * n, n, xc[k]);
			xs[k] += (y - xs[k]) * xc[3];
			const double v = x + xk[3] * xs[k];
			xb[k * n + xw] = v;
			const double o = v * xc[4 + k];
			ol += o * xc[10 + k];
			orr += o * xc[13 + k];
		}
		xw = xw + 1 == n ? 0 : xw + 1;
		l = l * dm() + ol * wm();
		r = r * dm() + orr * wm();
	}

	// Tape: saturation with a memory (the curve shifts against the direction the signal moves,
	// more as it saturates, so rising and falling halves trace different paths: a hysteresis
	// loop), unity for quiet signals; then wow (0.7 Hz) and flutter (6.1 and 13.3 Hz) as a
	// swinging delay about TP_BASE_MS (skipped when both are 0, so no latency), the head bump (a
	// peak at bump_hz) and the high-frequency loss (a 12 dB/octave low-pass at hf_hz).
	// xs: 0, 1 the last driven inputs, 2, 3 their smoothed directions, 4..6 the wow and flutter phases.
	inline void tick_tape(double &l, double &r) {
		const int n = b_line();
		double io[2] = { l, r };
		double y[2];
		for (int c = 0; c < 2; c++) {
			const double u = xc[0] * io[c];
			const double du = u - xs[c];
			xs[c] = u;
			xs[2 + c] += ((du > 0.0 ? 1.0 : (du < 0.0 ? -1.0 : 0.0)) - xs[2 + c]) * xc[1];
			y[c] = std::tanh(u - xk[1] * 0.3 * xs[2 + c] * std::tanh(std::fabs(u))) * xc[2];
		}
		if (xk[2] > 0.0 || xk[3] > 0.0) {
			xb[xw] = y[0];
			xb[n + xw] = y[1];
			const double d = xc[7] + xc[8] * std::sin(TAU * xs[4]) + xc[9] * (0.7 * std::sin(TAU * xs[5]) + 0.3 * std::sin(TAU * xs[6]));
			y[0] = ro_read(0, n, d);
			y[1] = ro_read(n, n, d);
			xw = xw + 1 == n ? 0 : xw + 1;
			for (int k = 4; k < 7; k++) {
				xs[k] += xc[k];
				xs[k] -= std::floor(xs[k]);
			}
		}
		for (int c = 0; c < 2; c++) {
			double v = y[c];
			if (xk[5] > 0.0) {
				v = xbq(2 * n, v, c);
			}
			v = xbq(2 * n + 13, v, c) * xc[3];
			io[c] = io[c] * dm() + v * wm();
		}
		l = io[0];
		r = io[1];
	}

	// Treemonster: a pitch tracker on the mono sum (high-passed at track_hp_hz, low-passed twice
	// at track_lp_hz) times positive-going zero crossings, armed once the signal falls below
	// -threshold_db, to the fraction of a sample; the frequency (20 Hz .. 5 kHz) glides over
	// glide_ms and drives a sine at pitch semitones from it that ring-modulates the input (the
	// right channel's sine width x a quarter cycle ahead). Before a pitch is found the sine is
	// at 0 Hz: silence. xs: 0 the high-pass, 1, 2 the low-passes, 3 armed, 4 the last tracked
	// sample, 5 samples since the last crossing, 6 a crossing seen, 7 the frequency (gliding to
	// 9, the last measured), 8 the phase.
	inline void tick_treemonster(double &l, double &r) {
		const double m = 0.5 * (l + r);
		xs[0] += (m - xs[0]) * xc[4];
		xs[1] += (m - xs[0] - xs[1]) * xc[3];
		xs[2] += (xs[1] - xs[2]) * xc[3];
		const double t = xs[2];
		xs[5] += 1.0;
		if (t < -xc[0]) {
			xs[3] = 1.0;
		} else if (xs[3] != 0.0 && xs[4] < 0.0 && t >= 0.0) {
			const double back = 1.0 - xs[4] / (xs[4] - t);   // samples since the crossing
			if (xs[6] != 0.0) {
				const double per = xs[5] - back;
				if (per > sr / 5000.0 && per < sr / 20.0) {
					xs[9] = sr / per;
					if (xs[7] == 0.0) {
						xs[7] = xs[9];
					}
				}
			}
			xs[5] = back;
			xs[6] = 1.0;
			xs[3] = 0.0;
		}
		xs[4] = t;
		xs[7] += (xs[9] - xs[7]) * xc[1];
		const double cl = std::sin(TAU * xs[8]);
		const double cr = xk[5] > 0.0 ? std::sin(TAU * (xs[8] + 0.25 * xk[5])) : cl;
		xs[8] += xs[7] * xc[2] / sr;
		xs[8] -= std::floor(xs[8]);
		l = l * dm() + l * cl * wm();
		r = r * dm() + r * cr * wm();
	}

	// Spring: two springs (the right one 1.13 times as long) fed the mono sum, each a loop of a
	// line (length_ms) through a one-pole low-pass (tone_hz) and a chain of SP_STAGES stretched
	// allpasses, (-chirp + z^-K) / (1 - chirp z^-K) with K = sp_k(), which delay low frequencies
	// more than high (each stage K (1 + chirp) / (1 - chirp) samples at the bottom, K (1 - chirp) /
	// (1 + chirp) at about 4.5 kHz), so every echo is a falling chirp, the spring's drip; the
	// loop's gain makes a 60 dB fall in decay_s (counting the chain's low-frequency delay). Dry
	// kept, wet at mix (as reverb). xb: the two lines, then per spring and stage K inputs and K
	// outputs. xs: 0, 1 the low-passes, 2 the place in the allpasses' K-sample rings.
	inline void tick_spring(double &l, double &r) {
		const int n = b_line();
		const int K = sp_k();
		const int p = (int)xs[2];
		const double in = 0.25 * (l + r);
		const double a = -xk[1];
		double y[2];
		for (int s = 0; s < 2; s++) {
			const double fbk = ro_read(s * n, n, xc[2 + s]);
			xs[s] += (fbk - xs[s]) * xc[1];
			double x = in + xc[0] * xs[s];
			double *z = xb.data() + 2 * n + s * 2 * SP_STAGES * K;
			for (int k = 0; k < SP_STAGES; k++) {
				const double v = a * x + z[p] - a * z[K + p];
				z[p] = x;
				z[K + p] = v;
				x = v;
				z += 2 * K;
			}
			xb[s * n + xw] = x;
			y[s] = x;
		}
		xw = xw + 1 == n ? 0 : xw + 1;
		xs[2] = p + 1 == K ? 0.0 : p + 1.0;
		l = l * da() + (y[0] * xc[4] + y[1] * xc[5]) * wm();
		r = r * da() + (y[1] * xc[4] + y[0] * xc[5]) * wm();
	}

	// Bonsai: bass enhancement and tape-ish saturation. A two-pole split at bass_hz (low and the
	// rest sum back to the input); the low band lifted by boost_db, and its harmonics (a tanh of
	// it, high-passed at twice bass_hz) added by harmonics, so small speakers hear the bass; then
	// a tanh saturator of drive_db, unity for quiet signals, a one-pole low-pass at tone_hz,
	// output_db. xs: per channel 4 (the split's two poles, the harmonics' high-pass, the tone).
	inline void tick_bonsai(double &l, double &r) {
		double io[2] = { l, r };
		for (int c = 0; c < 2; c++) {
			double *z = xs + 4 * c;
			const double x = io[c];
			z[0] += (x - z[0]) * xc[0];
			z[1] += (z[0] - z[1]) * xc[0];
			const double lo = z[1];
			const double hm = std::tanh(4.0 * lo) * 0.25;
			z[2] += (hm - z[2]) * xc[2];
			const double y = (x - lo) + lo * xc[1] + 2.0 * xk[2] * (hm - z[2]);
			z[3] += (std::tanh(xc[3] * y) * xc[4] - z[3]) * xc[5];
			io[c] = x * dm() + z[3] * xc[6] * wm();
		}
		l = io[0];
		r = io[1];
	}

	// Chow: a heavy one-sided distortion. The input driven by drive_db; on one side (positive, or
	// negative with flip) whatever passes threshold_db is cut by ratio, the other side passes;
	// a DC blocker (10 Hz), a one-pole low-pass at tone_hz, output_db (with the drive taken
	// back off, so ratio 1 is unity). xs: 0, 1 the DC blockers, 2, 3 the tone.
	inline void tick_chow(double &l, double &r) {
		double io[2] = { l, r };
		const double sg = xk[2] >= 0.5 ? -1.0 : 1.0;
		for (int c = 0; c < 2; c++) {
			double s = sg * xc[0] * io[c];
			if (s > xc[1]) {
				s = xc[1] + (s - xc[1]) * xc[2];
			}
			double u = sg * s;
			xs[c] += (u - xs[c]) * xc[3];
			u -= xs[c];
			xs[2 + c] += (u - xs[2 + c]) * xc[4];
			io[c] = io[c] * dm() + xs[2 + c] * xc[5] * wm();
		}
		l = io[0];
		r = io[1];
	}

	// Neuron: a feedback network of four lines (size_ms times 1, 0.811, 0.677, 0.543, each
	// swinging by up to 10% wobble at wobble_hz, a quarter cycle apart) whose outputs mix through
	// a 4x4 Hadamard matrix back into four nodes: node = tanh(g (input + regen x mix)) / g with
	// g = 1 + 7 drive, through a one-pole low-pass at tone_hz, into its line. Regen above 1
	// keeps it going on its own (tanh bounds it). Nodes 0, 2 take the left, 1, 3 the right; the
	// left hears lines 0 and 2, the right 1 and 3, mixed by width. xs: 0..3 the low-passes, 4 the phase.
	inline void tick_neuron(double &l, double &r) {
		const int n = (int)xb.size() / 4;
		double t[4];
		for (int k = 0; k < 4; k++) {
			const double d = std::max(2.0, xc[0] * NE_R[k] * (1.0 + xc[1] * std::sin(TAU * (xs[4] + 0.25 * k))));
			t[k] = ro_read(k * n, n, d);
		}
		const double h[4] = { 0.5 * (t[0] + t[1] + t[2] + t[3]), 0.5 * (t[0] - t[1] + t[2] - t[3]), 0.5 * (t[0] + t[1] - t[2] - t[3]),
			0.5 * (t[0] - t[1] - t[2] + t[3]) };
		for (int k = 0; k < 4; k++) {
			const double v = ((k & 1) ? r : l) + xk[1] * h[k];
			xs[k] += (std::tanh(xc[4] * v) * xc[5] - xs[k]) * xc[3];
			xb[k * n + xw] = xs[k];
		}
		xw = xw + 1 == n ? 0 : xw + 1;
		xs[4] += xc[2];
		xs[4] -= std::floor(xs[4]);
		const double wl = 0.5 * (t[0] + t[2]), wr = 0.5 * (t[1] + t[3]);
		l = l * dm() + (wl * xc[6] + wr * xc[7]) * wm();
		r = r * dm() + (wr * xc[6] + wl * xc[7]) * wm();
	}

	// ---- Granular: a port of the granular mode of Mutable Instruments Clouds (Emilie Gillet, MIT;
	// clouds/dsp/granular_processor.cc, granular_sample_player.h, grain.h, audio_buffer.h,
	// fx/diffuser.h, fx/reverb.h, fx/fx_engine.h; see NOTICE), in doubles. Clouds runs at 32 kHz in
	// 32-sample blocks: every length here is scaled by sr / 32000 and its per-sample one-poles
	// rescaled, the per-block work runs every GR block (32 sr / 32000 samples), the feedback takes
	// the previous sample's output (Clouds: the previous block's), the buffer holds doubles clipped
	// at +-1 (Clouds: 16-bit), the reverb's line memory doubles (Clouds: 12-bit), the grain phase a
	// double (Clouds: 16.16 fixed point), and Clouds' output soft clip is left out.
	// xk position, size, pitch, density, texture, recycle, pan_spread, reverb, freeze.
	// xb: a header (GR_H: see tick_granular), 32 grains of GR_GV values (active, first sample,
	// phase, increment, envelope phase, envelope increment, smoothness, slope, left gain, right
	// gain, high quality), the freeze tail (256 per channel), the stereo buffer (each channel
	// gr_n() + 8: the first 8 samples mirrored past the end for interpolation), then the
	// diffuser's and the reverb's rings (powers of two; fx_engine's layout, lines one sample apart).
	static constexpr int GR_H = 64, GR_NG = 32, GR_GV = 12, GR_TAIL = 256;
	static constexpr int GR_G0 = GR_H, GR_T0 = GR_H + GR_NG * GR_GV, GR_B0 = GR_T0 + 2 * GR_TAIL;
	static constexpr int GR_DIF[8] = { 126, 180, 269, 444, 151, 205, 245, 405 };
	static constexpr int GR_REV[10] = { 113, 162, 241, 399, 1653, 2038, 3411, 1913, 1663, 4782 };

	// Clouds' grain window table (1 - cos(pi t)) / 2, 4096 steps, read with linear interpolation.
	static const std::vector<double> &gr_window() {
		static const std::vector<double> w = [] {
			std::vector<double> v(4098);
			for (int i = 0; i <= 4096; i++) {
				v[i] = 1.0 - (std::cos(i / 4096.0 * PI) + 1.0) / 2.0;
			}
			v[4097] = 1.0;
			return v;
		}();
		return w;
	}
	static inline double soft_limit(double x) { return x * (27.0 + x * x) / (27.0 + 9.0 * x * x); }
	inline int gr_n() const { return (int)std::lround(32760.0 * sr / 32000.0); }
	// A per-sample one-pole coefficient at 32 kHz, for this rate.
	inline double gr_k(double k) const { return 1.0 - std::pow(1.0 - k, 32000.0 / sr); }

	void setup_g() {
		recoef_g();
		const int n = gr_n();
		xb.assign(GR_B0 + 2 * (n + 8) + (int)xc[18] + 1 + (int)xc[19] + 1, 0.0);
		double *h = xb.data();
		h[3] = 1.0;                       // the gain normalisation, smoothed
		h[4] = 1.0;                       // and its target
		h[5] = 1024.0 * sr / 32000.0;     // the grain size hint
		h[23] = h[24] = 1.0;              // the reverb's LFO values
	}

	// xc: 0 window shape, 2 diffusion, 3 overlap, 4 target grains, 5 grain size, 6 pitch ratio, 7 its
	// inverse, 8 feedback high-pass g, 9 its h, 10 gain smoothing, 11 reverb low-pass, 12 dry gain,
	// 13 wet gain, 14 buffer length, 15 block length, 16 deterministic seeding, 17 window gain,
	// 18, 19 diffuser and reverb ring masks, 20, 21 their places in xb, 24.. the diffuser's lines
	// (base, tail), 40.. the reverb's, 60..64 the reverb's modulated offsets.
	void recoef_g() {
		const double s = sr / 32000.0;
		const double den = xk[3], tex = xk[4];
		const double ov = den >= 0.53 ? (den - 0.53) * 2.12 : (den <= 0.47 ? (0.47 - den) * 2.12 : 0.0);
		xc[0] = tex < 0.75 ? tex * 1.333 : 1.0;
		xc[2] = tex > 0.75 ? (tex - 0.75) * 4.0 : 0.0;
		xc[3] = ov;
		xc[4] = GR_NG * ov * ov * ov;
		xc[5] = std::floor(1024.0 * std::pow(2.0, 4.0 * xk[1])) * s;
		xc[6] = std::pow(2.0, xk[2] / 12.0);
		xc[7] = std::pow(2.0, -xk[2] / 12.0);
		const double fc = 20.0 + 100.0 * xk[5] * xk[5];
		const double g = std::tan(PI * fc / sr);
		xc[8] = g;
		xc[9] = 1.0 / (1.0 + g + g * g);
		xc[10] = gr_k(0.01);
		xc[11] = gr_k(0.6 + 0.37 * xk[5]);
		const double t = std::clamp(1.04 * mix - 0.02, 0.0, 1.0) * PI * 0.5;
		xc[12] = dry >= 0.0 ? dry : std::cos(t);
		xc[13] = 1.2 * (wet >= 0.0 ? wet : std::sin(t));
		const int n = gr_n();
		xc[14] = n;
		xc[15] = std::max(1L, std::lround(32.0 * s));
		xc[16] = den < 0.5 ? 1.0 : 0.0;
		const double wg = std::clamp(1.0 + 2.0 * xc[0], 1.0, 2.0);
		xc[17] = 1.0 + (wg - 1.0) * ov;
		int base = 0;
		for (int k = 0; k < 8; k++) {
			const int len = std::max(2, (int)std::lround(GR_DIF[k] * s));
			xc[24 + 2 * k] = base;
			xc[25 + 2 * k] = base + len - 1;
			base += len + 1;
		}
		int m = 1;
		while (m < base) {
			m <<= 1;
		}
		xc[18] = m - 1;
		xc[20] = GR_B0 + 2 * (n + 8);
		base = 0;
		for (int k = 0; k < 10; k++) {
			const int len = std::max(2, (int)std::lround(GR_REV[k] * s));
			xc[40 + 2 * k] = base;
			xc[41 + 2 * k] = base + len - 1;
			base += len + 1;
		}
		int mr = 1;
		while (mr < base) {
			mr <<= 1;
		}
		xc[19] = mr - 1;
		xc[21] = xc[20] + m;
		xc[60] = 10.0 * s;
		xc[61] = 60.0 * s;
		xc[62] = std::lround(100.0 * s);
		xc[63] = 4680.0 * s;
		xc[64] = 100.0 * s;
	}

	// One grain's start (granular_sample_player.h ScheduleGrain, grain.h Start).
	inline void gr_start(double *g, int head, int n, bool high) {
		double gs = xc[5];
		const double ratio = xc[6];
		const double pan = 0.5 + xk[6] * (rnd() - 0.5);
		double gl, gr;
		if (pan < 0.5) {
			gl = 1.0;
			gr = 2.0 * pan;
		} else {
			gr = 1.0;
			gl = 2.0 * (1.0 - pan);
		}
		if (ratio > 1.0) {
			gs = std::min(gs, n * 0.25 * xc[7]);
		}
		const double eaten = gs * ratio;
		const double avail = n - eaten - gs;
		const int width = (int)gs & ~1;
		const int start = head - (int)(xk[0] * avail + eaten);
		g[0] = 1.0;
		g[1] = ((start % n) + n) % n;
		g[2] = 0.0;
		g[3] = ratio;
		g[4] = 0.0;
		g[5] = 2.0 / width;
		if (xc[0] >= 0.5) {
			g[6] = (xc[0] - 0.5) * 2.0;
			g[7] = 0.0;
		} else {
			g[6] = 0.0;
			g[7] = 0.5 / (xc[0] + 0.01);
		}
		g[8] = gl;
		g[9] = gr;
		g[10] = high ? 1.0 : 0.0;
		xb[5] += 0.1 * (gs - xb[5]);
	}

	// Header: 0 write head, 1 freeze crossfade counter, 2 smoothed grain count, 3 gain normalisation,
	// 4 its target, 5 grain size hint, 6 seed phasor, 7 freeze low-pass, 8 place in the block, 9 seed
	// probability, 10 seed spacing, 11 target grains, 12 free grains, 13..16 the feedback high-pass
	// (s1 L, R, s2 L, R), 17, 18 the last output, 19, 20 the reverb's low-passes, 21 its write
	// pointer, 22 the diffuser's, 23, 24 the reverb's LFO values, 25, 26 their phases, 27 feedback
	// gain, 28 reverb amount, 29 reverb time, 32..63 the free grains' list.
	inline void tick_granular(double &l, double &r) {
		double *h = xb.data();
		const int n = (int)xc[14];
		const bool frozen = xk[8] >= 0.5;
		if (h[8] == 0.0) {
			// The block's start (GranularProcessor::Process, GranularSamplePlayer::Play).
			h[7] += 0.0005 * ((frozen ? 1.0 : 0.0) - h[7]);
			const double fb = xk[5];
			h[27] = fb * (1.0 - h[7]);
			const double ra = std::clamp(xk[7] * 0.95 + fb * (2.0 - fb) * h[7], 0.0, 1.0);
			h[28] = ra * 0.54;
			h[29] = 0.35 + 0.63 * ra;
			const double target = xc[4];
			h[11] = target;
			h[9] = target / h[5];
			h[10] = target > 0.0 ? h[5] / target : 1e30;
			if (xc[16] != 0.0) {
				h[9] = -1.0;
			} else {
				h[6] = -1000.0;
			}
			int na = 0;
			for (int i = 0; i < GR_NG; i++) {
				if (h[GR_G0 + GR_GV * i] == 0.0) {
					h[32 + na++] = i;
				}
			}
			h[12] = na;
		}
		const double in[2] = { l, r };
		// Feedback: the last output high-passed, soft-limited into the input.
		double x[2];
		for (int c = 0; c < 2; c++) {
			const double g = xc[8];
			const double hp = (h[17 + c] - h[13 + c] - g * h[13 + c] - h[15 + c]) * xc[9];
			const double bp = g * hp + h[13 + c];
			h[13 + c] = g * hp + bp;
			const double lp = g * bp + h[15 + c];
			h[15 + c] = g * bp + lp;
			const double fg = h[27];
			x[c] = in[c] + fg * (soft_limit(fg * 1.4 * hp + in[c]) - in[c]);
		}
		// The buffer (AudioBuffer::WriteFade): frozen, the next 256 samples go to the tail; after,
		// the writing fades from the tail back to the input over as many samples.
		double *tail = h + GR_T0;
		double *bl = h + GR_B0, *br = bl + n + 8;
		int cf = (int)h[1];
		int head = (int)h[0];
		if (frozen) {
			if (cf < GR_TAIL) {
				tail[cf] = std::clamp(x[0], -1.0, 1.0);
				tail[GR_TAIL + cf] = std::clamp(x[1], -1.0, 1.0);
				cf++;
			}
		} else {
			if (cf > 0) {
				cf--;
				if (cf > 0) {
					const double gn = cf / double(GR_TAIL);
					x[0] += (tail[GR_TAIL - cf] - x[0]) * gn;
					x[1] += (tail[2 * GR_TAIL - cf] - x[1]) * gn;
				}
			}
			const double vl = std::clamp(x[0], -1.0, 1.0), vr = std::clamp(x[1], -1.0, 1.0);
			bl[head] = vl;
			br[head] = vr;
			if (head < 8) {
				bl[head + n] = vl;
				br[head + n] = vr;
			}
			head = head + 1 >= n ? 0 : head + 1;
		}
		h[1] = cf;
		h[0] = head;
		// Seeding: one random draw a sample, as Clouds.
		h[6] += 1.0;
		const bool prob = rnd() < h[9] && h[11] > h[2];
		const bool det = h[6] >= h[10];
		int na = (int)h[12];
		if (na > 0 && (prob || det)) {
			na--;
			const int idx = (int)h[32 + na];
			gr_start(h + GR_G0 + GR_GV * idx, head - 1, n, na >= 3 * GR_NG / 4);
			h = xb.data();
			h[6] = 0.0;
			h[12] = na;
		}
		// The grains, overlapped (Grain::OverlapAdd).
		const std::vector<double> &win = gr_window();
		double o[2] = { 0.0, 0.0 };
		for (int i = 0; i < GR_NG; i++) {
			double *g = h + GR_G0 + GR_GV * i;
			if (g[0] == 0.0) {
				continue;
			}
			const double ep = g[4];
			double gain = ep >= 1.0 ? 2.0 - ep : ep;
			if (g[6] == 0.0) {
				gain *= g[7];
				if (gain >= 1.0) {
					gain = 1.0;
				}
			} else if (g[10] != 0.0) {
				const double ix = gain * 4096.0;
				const int ii = (int)ix;
				const double w = win[ii] + (win[ii + 1] - win[ii]) * (ix - ii);
				gain += g[6] * (w - gain);
			}
			g[4] = ep + g[5];
			if (g[4] >= 2.0) {
				g[0] = 0.0;
				continue;
			}
			const double ph = g[2];
			const int ip = (int)ph;
			const double t = ph - ip;
			int si = (int)g[1] + ip;
			if (si >= n) {
				si -= n;
			}
			double sl, sr2;
			if (g[10] != 0.0) {
				sl = gr_hermite(bl + si, t);
				sr2 = gr_hermite(br + si, t);
			} else {
				sl = bl[si] + (bl[si + 1] - bl[si]) * t;
				sr2 = br[si] + (br[si + 1] - br[si]) * t;
			}
			sl *= gain;
			sr2 *= gain;
			o[0] += sl * g[8] + sr2 * (1.0 - g[9]);
			o[1] += sr2 * g[9] + sl * (1.0 - g[8]);
			g[2] = ph + g[3];
		}
		h[3] += xc[10] * (h[4] - h[3]);
		o[0] *= h[3];
		o[1] *= h[3];
		// The diffuser (fx/diffuser.h): four allpasses a channel.
		{
			double *d = h + (int)xc[20];
			const int m = (int)xc[18];
			const int wp = ((int)h[22] - 1) & m;
			h[22] = wp;
			for (int c = 0; c < 2; c++) {
				double acc = o[c];
				for (int k = 0; k < 4; k++) {
					const int j = 4 * c + k;
					const double rd = d[(wp + (int)xc[25 + 2 * j]) & m];
					acc += rd * 0.625;
					d[(wp + (int)xc[24 + 2 * j]) & m] = acc;
					acc *= -0.625;
					acc += rd;
				}
				o[c] += xc[2] * (acc - o[c]);
			}
		}
		h[17] = o[0];
		h[18] = o[1];
		gr_reverb(h, o);
		h[8] += 1.0;
		if (h[8] >= xc[15]) {
			// The block's end: the normalisation for the grains now sounding.
			h[8] = 0.0;
			const double act = GR_NG - h[12];
			const double e = act - h[2];
			h[2] += (e > 0.0 ? 0.9 : 0.2) * e;
			h[4] = (h[2] > 2.0 ? 1.0 / std::sqrt(h[2] - 1.0) : 1.0) * xc[17];
		}
		l = in[0] * xc[12] + o[0] * xc[13];
		r = in[1] * xc[12] + o[1] * xc[13];
	}

	// Laurent de Soras's Hermite interpolator, as AudioBuffer::ReadHermite (x0 is p[1]).
	static inline double gr_hermite(const double *p, double t) {
		const double xm1 = p[0], x0 = p[1], x1 = p[2], x2 = p[3];
		const double c = (x1 - xm1) * 0.5;
		const double v = x0 - x1;
		const double w = c + v;
		const double a = w + v + (x2 - x0) * 0.5;
		const double b_neg = w + a;
		return (((a * t) - b_neg) * t + c) * t + x0;
	}

	// Clouds' reverb (fx/reverb.h: Griesinger's topology from Dattorro's paper), on fx_engine's
	// layout: one ring, its write pointer counting down, each line read at its tail.
	inline void gr_reverb(double *h, double *o) {
		double *rv_ = h + (int)xc[21];
		const int m = (int)xc[19];
		const int wp = ((int)h[21] - 1) & m;
		h[21] = wp;
		if ((wp & 31) == 0) {
			// Clouds' LFOs step every 32 samples (0.5 and 0.3 Hz, 0..1).
			h[23] = 0.5 + 0.5 * std::cos(TAU * h[25]);
			h[24] = 0.5 + 0.5 * std::cos(TAU * h[26]);
			h[25] += 0.5 * 32.0 / sr;
			h[25] -= std::floor(h[25]);
			h[26] += 0.3 * 32.0 / sr;
			h[26] -= std::floor(h[26]);
		}
		const double *L = xc + 40;   // base, tail per line
		auto at = [&](int i) -> double & { return rv_[i & m]; };
		auto interp = [&](int line, double off) {
			const int oi = (int)off;
			const double f = off - oi;
			const double a = at(wp + oi + (int)L[2 * line]);
			const double b = at(wp + oi + (int)L[2 * line] + 1);
			return a + (b - a) * f;
		};
		const double kap = 0.7, klp = xc[11], krt = h[29], amount = h[28];
		double acc = interp(0, xc[60] + xc[61] * h[23]);
		at(wp + (int)L[0] + (int)xc[62]) = acc;
		acc = (o[0] + o[1]) * 0.2;
		for (int k = 0; k < 4; k++) {
			const double rd = at(wp + (int)L[2 * k + 1]);
			acc += rd * kap;
			at(wp + (int)L[2 * k]) = acc;
			acc *= -kap;
			acc += rd;
		}
		const double apout = acc;
		// Loop 1: del2 (modulated), the low-pass, dap1a, dap1b, into del1.
		acc = apout + interp(9, xc[63] + xc[64] * h[24]) * krt;
		h[19] += klp * (acc - h[19]);
		acc = h[19];
		double rd = at(wp + (int)L[9]);
		acc += rd * -kap;
		at(wp + (int)L[8]) = acc;
		acc *= kap;
		acc += rd;
		rd = at(wp + (int)L[11]);
		acc += rd * kap;
		at(wp + (int)L[10]) = acc;
		acc *= -kap;
		acc += rd;
		at(wp + (int)L[12]) = acc;
		o[0] += (2.0 * acc - o[0]) * amount;
		// Loop 2: del1, the low-pass, dap2a, dap2b, into del2.
		acc = apout + at(wp + (int)L[13]) * krt;
		h[20] += klp * (acc - h[20]);
		acc = h[20];
		rd = at(wp + (int)L[15]);
		acc += rd * kap;
		at(wp + (int)L[14]) = acc;
		acc *= -kap;
		acc += rd;
		rd = at(wp + (int)L[17]);
		acc += rd * -kap;
		at(wp + (int)L[16]) = acc;
		acc *= kap;
		acc += rd;
		at(wp + (int)L[18]) = acc;
		o[1] += (2.0 * acc - o[1]) * amount;
	}

	// ---- Airwindows: ports of Chris Johnson's Airwindows plugins (MIT; see NOTICE), in doubles,
	// selected by xk[0] (AKStreamFx.AW_NAMES), their parameters A..F in xk[1..6] (0..1, as the
	// plugins' sliders). The DSP of each plugin's processDoubleReplacing, without the floating-
	// point dither and the denormal-guard noise (a tiny fpd value put in place of near-silence).
	// Where a plugin works per host block (Console7's gain chase, Capacitor's chase speeds) the
	// block is AW_BLOCK samples. State in xb (AW_STATE doubles; xb[0] the place in the block),
	// coefficients in xc.
	static constexpr int AW_N = 10;
	static constexpr int AW_BLOCK = 512;
	static constexpr int AW_STATE = 64;
	enum { AW_DENSITY, AW_CONSOLE7CH, AW_CONSOLE7BUSS, AW_CONSOLE7, AW_PURESTDRIVE, AW_TUBE, AW_CAPACITOR, AW_TOTAPE6, AW_AIR, AW_GALACTIC };
	// Each algorithm's parameter defaults (the plugins' own).
	static const double *aw_defaults(int algo) {
		static const double D[AW_N][6] = { { 0.2, 0.0, 1.0, 1.0, 0.0, 0.0 }, { 0.772, 0.0, 0.0, 0.0, 0.0, 0.0 },
			{ 1.0, 0.0, 0.0, 0.0, 0.0, 0.0 }, { 0.772, 1.0, 0.0, 0.0, 0.0, 0.0 }, { 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 },
			{ 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 }, { 1.0, 0.0, 1.0, 0.0, 0.0, 0.0 }, { 0.5, 0.5, 0.5, 0.5, 0.5, 1.0 },
			{ 0.5, 0.5, 0.5, 0.0, 1.0, 1.0 }, { 0.5, 0.5, 0.5, 1.0, 1.0, 0.0 } };
		return D[std::clamp(algo, 0, AW_N - 1)];
	}
	inline int aw_algo() const { return std::clamp((int)std::lround(xk[0]), 0, AW_N - 1); }

	void setup_aw() {
		// Sized by the algorithm, so retune never carries one's state to another.
		const int algo = aw_algo();
		xb.assign((algo == AW_GALACTIC ? ga_base(12, 1) + GA_LEN[12] : (algo == AW_TOTAPE6 ? 1100 : AW_STATE)) + algo, 0.0);
		double *s = xb.data();
		switch (algo) {
			case AW_TOTAPE6:
				s[30] = 0.5;
				s[31] = PI;
				s[32] = 0.5;
				s[35] = 2463534242.0;   // the fpd generator, seeded (the plugin seeds it at random)
				break;
			case AW_AIR:
				s[43] = 1.0;
				break;
			case AW_GALACTIC:
				for (int k = 30; k <= 42; k++) {
					s[k] = 1.0;
				}
				s[44] = 3.0;
				s[45] = 429496.7295;
				s[46] = 2463534242.0;
				break;
			case AW_DENSITY:
				s[8] = 1.0;
				break;
			case AW_CONSOLE7CH:
				s[12] = -1.0;
				s[13] = 64.0;
				break;
			case AW_CONSOLE7BUSS:
				s[20] = -1.0;
				s[21] = 64.0;
				break;
			case AW_CONSOLE7:
				s[12] = -1.0;
				s[13] = 64.0;
				s[30] = -1.0;
				s[31] = 64.0;
				break;
			case AW_CAPACITOR:
				s[28] = 1.0;
				s[30] = 1.0;
				s[32] = s[33] = s[34] = 1000.0;
				break;
			default:
				break;
		}
		recoef_aw();
	}

	// A Console7 low-pass at 20 kHz (capped at 0.45 of the rate) with q, as the plugins' biquads.
	void aw_lp(double *c, double q) const {
		const double K = std::tan(PI * std::min(20000.0, 0.45 * sr) / sr);
		const double norm = 1.0 / (1.0 + K / q + K * K);
		c[0] = K * K * norm;
		c[1] = 2.0 * c[0];
		c[2] = c[0];
		c[3] = 2.0 * (K * K - 1.0) * norm;
		c[4] = (1.0 - K / q + K * K) * norm;
	}

	void recoef_aw() {
		const double os = sr / 44100.0;
		switch (aw_algo()) {
			case AW_DENSITY: {
				const double dp = xk[1] * 5.0 - 1.0;
				double out = std::fabs(dp);
				while (out > 1.0) {
					out -= 1.0;
				}
				xc[20] = std::pow(xk[2], 3) / os;
				xc[21] = out;
				xc[22] = dp * std::fabs(dp);
				xc[23] = xk[3];
				xc[24] = xk[4];
				break;
			}
			case AW_CONSOLE7CH:
			case AW_CONSOLE7BUSS:
			case AW_CONSOLE7:
				aw_lp(xc, 1.618033988749894848204586);
				aw_lp(xc + 5, 0.618033988749894848204586);
				aw_lp(xc + 10, 0.5);
				break;
			case AW_TOTAPE6: {
				const double ig = std::pow(10.0, ((xk[1] - 0.5) * 24.0) / 20.0);
				xc[30] = ig;
				xc[31] = (1.0 - (std::pow(xk[2], 2) * 0.45)) / os;
				xc[32] = xk[3] * 0.25 * ig;
				xc[33] = 0.12 / os;
				for (int k = 0; k < 2; k++) {
					const double f = (k == 0 ? 0.007 : 0.032) / os, q = k == 0 ? 0.0009 : 0.0007;
					const double K = std::tan(PI * f);
					const double norm = 1.0 / (1.0 + K / q + K * K);
					double *c = xc + 34 + 4 * k;
					c[0] = K / q * norm;
					c[1] = -c[0];
					c[2] = 2.0 * (K * K - 1.0) * norm;
					c[3] = (1.0 - K / q + K * K) * norm;
				}
				xc[42] = std::pow(xk[4], 2) * os * 70;
				xc[43] = (0.0024 * std::pow(xk[4], 2)) / os;
				xc[44] = std::pow(10.0, ((xk[5] - 0.5) * 24.0) / 20.0);
				xc[45] = xk[6];
				break;
			}
			case AW_AIR:
				xc[30] = -std::pow(((xk[1] * 2.0) - 1.0), 3) * 2;
				xc[31] = -std::pow(((xk[2] * 2.0) - 1.0), 3);
				xc[32] = -std::pow(((xk[3] * 2.0) - 1.0), 3) / 2;
				xc[33] = 2.1 - xk[4];
				xc[34] = xk[5];
				xc[35] = xk[6];
				break;
			case AW_GALACTIC: {
				const double regen = 0.0625 + ((1.0 - xk[1]) * 0.0625);
				xc[30] = regen;
				xc[31] = (1.0 - (regen / 0.125)) * 1.333;
				xc[32] = std::pow(1.00001 - (1.0 - xk[2]), 2.0) / std::sqrt(os);
				xc[33] = std::pow(xk[3], 3) * 0.001;
				xc[34] = 1.0 - (std::pow(1.0 - xk[5], 3));
				xc[35] = std::clamp((int)std::floor(os), 1, 4);
				const double size = (xk[4] * 1.77) + 0.1;
				for (int k = 0; k < 12; k++) {
					xc[50 + k] = (int)(GA_DLY[k] * size);
				}
				break;
			}
			case AW_TUBE: {
				const int pf = (int)(5.0 * (1.0 - xk[1]) + 1.0);
				xc[25] = 1.0 + xk[1] * 0.2246161992650486;
				xc[26] = pf;
				xc[27] = 1.0 / double(pf + 1);
				xc[28] = 1.0 + 1.0 / double(pf);
				break;
			}
			default:
				break;
		}
	}

	// A direct-form-1 biquad: coefficients c (b0 b1 b2 a1 a2), state z (x1 x2 y1 y2).
	static inline double aw_bq(const double *c, double *z, double x) {
		const double y = c[0] * x + c[1] * z[0] + c[2] * z[1] - c[3] * z[2] - c[4] * z[3];
		z[1] = z[0];
		z[0] = x;
		z[3] = z[2];
		z[2] = y;
		return y;
	}

	// The per-block work of the chasing plugins (their processing's prelude).
	inline void aw_block(double *s, int algo) {
		auto chase = [](double *g, double target) {
			if (g[0] != target) {
				g[1] *= 2.0;
			}
			if (g[1] > AW_BLOCK) {
				g[1] = AW_BLOCK;
			}
			if (g[0] < 0.0) {
				g[0] = target;
			}
		};
		switch (algo) {
			case AW_CONSOLE7CH:
				chase(s + 12, xk[1] * 1.272019649514069);
				break;
			case AW_CONSOLE7BUSS:
				chase(s + 20, xk[1] * 1.03);
				break;
			case AW_CONSOLE7:
				chase(s + 12, xk[1] * 1.272019649514069);
				chase(s + 30, xk[2] * 1.03);
				break;
			case AW_GALACTIC:
				if (s[43] > xc[35] - 1) {
					s[43] = xc[35] - 1;
				}
				break;
			case AW_CAPACITOR:
				for (int k = 0; k < 3; k++) {
					const double ch = k == 2 ? xk[3] : xk[1 + k] * xk[1 + k];
					s[35 + k] = 300.0 / (std::fabs(s[32 + k] - ch) + 1.0);
					s[32 + k] = ch;
					s[38 + k] = ch;
				}
				break;
			default:
				break;
		}
	}

	// Console7Channel on both channels: biquad state at z (8), gain chase at g (2).
	inline void aw_c7ch(double *z, double *g, double target, double &l, double &r) {
		l = aw_bq(xc, z, l);
		r = aw_bq(xc, z + 4, r);
		g[1] *= 0.9999;
		g[1] -= 0.01;
		if (g[1] < 64.0) {
			g[1] = 64.0;
		}
		g[0] = ((g[0] * g[1]) + target) / (g[1] + 1.0);
		const double gc = g[0];
		double io[2] = { l, r };
		for (int c = 0; c < 2; c++) {
			double x = io[c];
			if (1.0 != gc) {
				x *= std::pow(gc, 3);
			}
			x = std::clamp(x, -1.097, 1.097);
			const double ax = std::fabs(x);
			x = ((std::sin(x * ax) / (ax == 0.0 ? 1.0 : ax)) * 0.8) + (std::sin(x) * 0.2);
			if (1.0 != gc && 0.0 != gc) {
				x /= gc;
			}
			io[c] = x;
		}
		l = io[0];
		r = io[1];
	}

	// Console7Buss: biquad A state at z, B at z + 8, gain chase at g.
	inline void aw_c7buss(double *z, double *g, double target, double &l, double &r) {
		l = aw_bq(xc + 5, z, l);
		r = aw_bq(xc + 5, z + 4, r);
		g[1] *= 0.9999;
		g[1] -= 0.01;
		if (g[1] < 64.0) {
			g[1] = 64.0;
		}
		g[0] = ((g[0] * g[1]) + target) / (g[1] + 1.0);
		const double gc = g[0];
		double io[2] = { l, r };
		for (int c = 0; c < 2; c++) {
			double x = io[c];
			if (1.0 != gc) {
				x *= std::sqrt(gc);
			}
			x = std::clamp(x, -1.0, 1.0);
			const double ax = std::fabs(x);
			x = ((std::asin(x * ax) / (ax == 0.0 ? 1.0 : ax)) * 0.618033988749894848204586) + (std::asin(x) * 0.381966011250105);
			x = aw_bq(xc + 10, z + 8 + 4 * c, x);
			if (1.0 != gc) {
				x *= std::sqrt(gc);
			}
			io[c] = x;
		}
		l = io[0];
		r = io[1];
	}

	inline void tick_aw(double &l, double &r) {
		double *s = xb.data();
		const int algo = aw_algo();
		if (s[0] == 0.0) {
			aw_block(s, algo);
		}
		s[0] = s[0] + 1.0 >= AW_BLOCK ? 0.0 : s[0] + 1.0;
		switch (algo) {
			case AW_DENSITY: {
				const double ia = xc[20], out = xc[21], d2 = xc[22];
				const bool flip = s[8] != 0.0;
				double io[2] = { l, r };
				for (int c = 0; c < 2; c++) {
					double x = io[c];
					double &st = s[flip ? 4 + c : 6 + c];
					st = (st * (1.0 - ia)) + (x * ia);
					x -= st;
					double count = d2;
					while (count > 1.0) {
						double br = std::fabs(x) * 1.57079633;
						if (br > 1.57079633) {
							br = 1.57079633;
						}
						br = std::sin(br);
						x = x > 0.0 ? br : -br;
						count -= 1.0;
					}
					double br = std::fabs(x) * 1.57079633;
					if (br > 1.57079633) {
						br = 1.57079633;
					}
					br = d2 > 0 ? std::sin(br) : 1 - std::cos(br);
					x = x > 0 ? (x * (1 - out)) + (br * out) : (x * (1 - out)) - (br * out);
					if (xc[23] < 1.0) {
						x *= xc[23];
					}
					if (xc[24] < 1.0) {
						x = (io[c] * (1.0 - xc[24])) + (x * xc[24]);
					}
					io[c] = x;
				}
				s[8] = flip ? 0.0 : 1.0;
				l = io[0];
				r = io[1];
				break;
			}
			case AW_CONSOLE7CH:
				aw_c7ch(s + 4, s + 12, xk[1] * 1.272019649514069, l, r);
				break;
			case AW_CONSOLE7BUSS:
				aw_c7buss(s + 4, s + 20, xk[1] * 1.03, l, r);
				break;
			case AW_CONSOLE7:
				aw_c7ch(s + 4, s + 12, xk[1] * 1.272019649514069, l, r);
				aw_c7buss(s + 14, s + 30, xk[2] * 1.03, l, r);
				break;
			case AW_PURESTDRIVE: {
				double io[2] = { l, r };
				for (int c = 0; c < 2; c++) {
					const double dry_ = io[c];
					const double x = std::sin(dry_);
					const double apply = (std::fabs(s[4 + c] + x) / 2.0) * xk[1];
					io[c] = (dry_ * (1.0 - apply)) + (x * apply);
					s[4 + c] = std::sin(dry_);
				}
				l = io[0];
				r = io[1];
				break;
			}
			case AW_TUBE: {
				const bool hi = sr / 44100.0 > 1.9;
				const int pf = (int)xc[26];
				double io[2] = { l, r };
				for (int c = 0; c < 2; c++) {
					double x = io[c];
					if (hi) {
						const double st = x;
						x += s[4 + c];
						s[4 + c] = st;
						x *= 0.5;
					}
					x *= xc[25];
					x = std::clamp(x, -1.0, 1.0);
					double f = x;
					for (int k = 0; k < pf; k++) {
						f *= x;
					}
					if ((pf % 2 == 1) && (x != 0.0)) {
						f = (f / x) * std::fabs(x);
					}
					f *= xc[27];
					x -= f;
					x *= xc[28];
					if (hi) {
						const double st = x;
						x += s[6 + c];
						s[6 + c] = st;
						x *= 0.5;
					}
					io[c] = x;
				}
				l = io[0];
				r = io[1];
				break;
			}
			case AW_CAPACITOR: {
				s[28] = ((s[28] * s[35]) + s[38]) / (s[35] + 1.0);
				s[29] = ((s[29] * s[36]) + s[39]) / (s[36] + 1.0);
				s[30] = ((s[30] * s[37]) + s[40]) / (s[37] + 1.0);
				const double lp = s[28], ilp = 1.0 - lp, hp = s[29], ihp = 1.0 - hp, wt = s[30];
				s[31] += 1.0;
				if (s[31] > 5.0) {
					s[31] = 0.0;
				}
				const int cnt = (int)s[31];
				const int st[3] = { 0, cnt % 2 == 0 ? 1 : 2, 3 + cnt % 3 };   // stages A, B or C, D E or F
				double io[2] = { l, r };
				for (int c = 0; c < 2; c++) {
					double x = io[c];
					double *h = s + 4 + 12 * c, *lo = h + 6;
					for (int k = 0; k < 3; k++) {
						const int j = st[k];
						h[j] = (h[j] * ihp) + (x * hp);
						x -= h[j];
						lo[j] = (lo[j] * ilp) + (x * lp);
						x = lo[j];
					}
					io[c] = (io[c] * (1.0 - wt)) + (x * wt);
				}
				l = io[0];
				r = io[1];
				break;
			}
			case AW_TOTAPE6:
				aw_totape6(s, l, r);
				break;
			case AW_AIR:
				aw_air(s, l, r);
				break;
			case AW_GALACTIC:
				aw_galactic(s, l, r);
				break;
			default:
				break;
		}
	}
	// ---- Airwindows group 2: ToTape6, Air, Galactic.
	static constexpr int AW_TT_D = 40;       // ToTape6's flutter lines (501 each, L then R)
	static constexpr int GA_B0 = 64;         // Galactic's lines: I J K L A B C D E F G H M, each L then R
	static constexpr int GA_LEN[13] = { 6480, 3660, 1720, 680, 9700, 6000, 2320, 940, 15220, 8460, 4540, 3200, 3111 };
	static constexpr double GA_DLY[12] = { 3407.0, 1823.0, 859.0, 331.0, 4801.0, 2909.0, 1153.0, 461.0, 7607.0, 4217.0, 2269.0, 1597.0 };
	static inline double aw_fpd(double v) {
		uint32_t x = (uint32_t)v;
		x ^= x << 13;
		x ^= x >> 17;
		x ^= x << 5;
		return (double)x;
	}
	static constexpr int GA_OFF[13] = { 64, 13024, 20344, 23784, 25144, 44544, 56544, 61184, 63064, 93504, 110424, 119504, 125904 };
	static inline int ga_base(int k, int c) { return GA_OFF[k] + c * GA_LEN[k]; }
	// ToTape6's "interleaved" biquad (transposed direct form 2; b1 is 0): c (b0 b2 a1 a2), z (2).
	static inline double aw_tdf(const double *c, double *z, double x) {
		const double t = (x * c[0]) + z[0];
		z[0] = -(t * c[2]) + z[1];
		z[1] = (x * c[1]) - (t * c[3]);
		return t;
	}

	inline void aw_totape6(double *s, double &l, double &r) {
		const double ig = xc[30], roll = xc[31], hbc = xc[32], hbf = xc[33], depth = xc[42], ft = xc[43], og = xc[44], wt = xc[45];
		double x[2] = { l, r };
		const double dry_[2] = { l, r };
		if (ig < 1.0) {
			x[0] *= ig;
			x[1] *= ig;
		}
		const double randy = s[35] / 4294967295.0;
		int gc = (int)s[29];
		if (gc < 0 || gc > 499) {
			gc = 499;
		}
		double *dl = s + AW_TT_D, *dr = dl + 501;
		dl[gc] = x[0];
		dr[gc] = x[1];
		int count = gc;
		if (depth != 0.0) {
			const double offset = depth + (depth * std::pow(s[30], 2) * std::sin(s[31]));
			count += (int)std::floor(offset);
			const double fr = offset - std::floor(offset);
			const int i0 = count - ((count > 499) ? 500 : 0), i1 = count + 1 - ((count + 1 > 499) ? 500 : 0);
			x[0] = dl[i0] * (1 - fr) + dl[i1] * fr;
			x[1] = dr[i0] * (1 - fr) + dr[i1] * fr;
			s[30] = (s[30] * (1.0 - ft)) + (s[32] * ft);
			s[31] += s[30] * ft;
			if (s[31] >= (PI * 2.0)) {
				s[31] -= PI;
				s[32] = 0.24 + (randy * 0.74);
			}
		}
		s[29] = gc - 1;
		const bool flip = s[28] != 0.0;
		double highs[2], ground[2];
		for (int c = 0; c < 2; c++) {
			const double vib = x[c];
			double &mr = s[(flip ? 4 : 6) + c];
			double &hb = s[(flip ? 8 : 10) + c];
			mr = (mr * (1.0 - roll)) + (x[c] * roll);
			highs[c] = x[c] - mr;
			hb += (x[c] * 0.05);
			hb -= (hb * hb * hb * hbf);
			hb = std::sin(hb);
			hb = aw_tdf(xc + 34, s + 12 + 4 * c + (flip ? 0 : 2), hb);
			hb = std::asin(std::clamp(hb, -1.0, 1.0));
			double v = std::sin(x[c]);
			v = aw_tdf(xc + 38, s + 20 + 4 * c + (flip ? 0 : 2), v);
			x[c] = std::asin(std::clamp(v, -1.0, 1.0));
			ground[c] = vib - x[c];
		}
		s[28] = flip ? 0.0 : 1.0;
		for (int c = 0; c < 2; c++) {
			double v = x[c];
			if (ig > 1.0) {
				v *= ig;
			}
			double so = std::fabs(highs[c]) * 1.57079633;
			if (so > 1.57079633) {
				so = 1.57079633;
			}
			so = 1 - std::cos(so);
			if (highs[c] > 0) {
				v -= so;
			}
			if (highs[c] < 0) {
				v += so;
			}
			const double sup = (1.0 - std::fabs(v)) * 0.00013;
			for (int k = 0; k < 2; k++) {
				double &hb = s[8 + 2 * k + c];
				if (hb > sup) {
					hb -= sup;
				}
				if (hb < -sup) {
					hb += sup;
				}
			}
			v += ((s[8 + c] + s[10 + c]) * hbc);
			v = std::clamp(v, -1.0, 1.0);
			const double mojo = std::pow(std::fabs(v), 0.25);
			if (mojo > 0.0) {
				v = (std::sin(v * mojo * PI * 0.5) / mojo);
			}
			v += ground[c];
			if (og != 1.0) {
				v *= og;
			}
			// ADClip.
			const double rc = 0.99, sf = 0.618033988749894848204586;
			double &last = s[33 + c];
			if (last >= rc) {
				last = v < rc ? ((rc * sf) + (v * (1.0 - sf))) : rc;
			}
			if (last <= -rc) {
				last = v > -rc ? ((-rc * sf) + (v * (1.0 - sf))) : -rc;
			}
			if (v > rc) {
				v = last < rc ? ((rc * sf) + (last * (1.0 - sf))) : rc;
			}
			if (v < -rc) {
				v = last > -rc ? ((-rc * sf) + (last * (1.0 - sf))) : -rc;
			}
			last = v;
			v = std::clamp(v, -rc, rc);
			if (wt != 1.0) {
				v = (v * wt) + (dry_[c] * (1.0 - wt));
			}
			x[c] = v;
		}
		s[35] = aw_fpd(s[35]);
		l = x[0];
		r = x[1];
	}

	inline void aw_air(double *s, double &l, double &r) {
		const double hi = xc[30], ti = xc[31], ai = xc[32], q = xc[33], out = xc[34], wt = xc[35];
		if (s[43] < 1.0 || s[43] > 3.0) {
			s[43] = 1.0;
		}
		const int cnt = (int)s[43];
		const bool flop = s[42] != 0.0, fa = s[40] != 0.0, fb = s[41] != 0.0;
		double io[2] = { l, r };
		for (int c = 0; c < 2; c++) {
			double *t = s + 4 + 14 * c;   // tripletA B C, prev, mid, even A B C, odd A B C, prev A B C
			const double x = io[c];
			double corr = 0.0;
			double tf = t[3] - x;
			const int a = cnt - 1, z = (cnt + 1) % 3;   // case 1: A +=, C -=; 2: B, A; 3: C, B
			t[a] += tf;
			t[z] -= tf;
			tf = t[a] * ti;
			t[3] = t[4];
			t[4] = x;
			t[0] /= q;
			t[1] /= q;
			t[2] /= q;
			corr += tf;
			auto air = [&](int k, bool even_first, double intensity) {
				double &ev = t[5 + k], &od = t[8 + k], &pv = t[11 + k];
				double f = pv - x;
				if (even_first) {
					ev += f;
					od -= f;
					f = ev * intensity;
				} else {
					od += f;
					ev -= f;
					f = od * intensity;
				}
				od = (od - ((od - ev) / 256.0)) / q;
				ev = (ev - ((ev - od) / 256.0)) / q;
				pv = x;
				corr += f;
			};
			if (flop) {
				air(0, fa, ai);
			} else {
				air(1, fb, ai);
			}
			air(2, flop, hi);
			double v = x + corr;
			if (out < 1.0) {
				v *= out;
			}
			if (wt < 1.0) {
				v = (x * (1.0 - wt)) + (v * wt);
			}
			io[c] = v;
		}
		s[43] += 1.0;
		if (flop) {
			s[40] = fa ? 0.0 : 1.0;
		} else {
			s[41] = fb ? 0.0 : 1.0;
		}
		s[42] = flop ? 0.0 : 1.0;
		l = io[0];
		r = io[1];
	}

	inline void aw_galactic(double *s, double &l, double &r) {
		const double regen = xc[30], att = xc[31], lp = xc[32], drift = xc[33], wt = xc[34];
		const int ce = (int)xc[35];
		const double dry_[2] = { l, r };
		s[44] += (s[45] * drift);
		if (s[44] > (3.141592653589793238 * 2.0)) {
			s[44] = 0.0;
			s[45] = 0.4294967295 + (s[46] * 0.0000000000618);
		}
		double *ml = s + ga_base(12, 0), *mrr = s + ga_base(12, 1);
		int cm = (int)s[42];
		ml[cm] = l * att;
		mrr[cm] = r * att;
		cm++;
		if (cm < 0 || cm > 256) {
			cm = 0;
		}
		s[42] = cm;
		double x[2];
		for (int c = 0; c < 2; c++) {
			const double off = (std::sin(s[44] + (c == 1 ? 3.141592653589793238 / 2.0 : 0.0)) + 1.0) * 127;
			const int w = (int)(cm + off);
			const double *m = c == 0 ? ml : mrr;
			const double fr = off - std::floor(off);
			double v = m[w - ((w > 256) ? 257 : 0)] * (1 - fr);
			v += m[w + 1 - ((w + 1 > 256) ? 257 : 0)] * fr;
			s[4 + c] = (s[4 + c] * (1.0 - lp)) + (v * lp);
			x[c] = s[4 + c];
		}
		double *refl = s + 16, *refr = s + 23;
		s[43] += 1.0;
		if ((int)s[43] == ce) {
			double *cnt = s + 30;   // counters I J K L A B C D E F G H
			auto step = [&](int k) {
				cnt[k] += 1.0;
				if (cnt[k] < 0 || cnt[k] > xc[50 + k]) {
					cnt[k] = 0;
				}
			};
			auto rd = [&](int k, int c) {
				const int i = (int)cnt[k];
				return s[ga_base(k, c) + i - ((i > (int)xc[50 + k]) ? (int)xc[50 + k] + 1 : 0)];
			};
			// Stage 1 (I J K L) fed the input and the other side's feedback.
			for (int c = 0; c < 2; c++) {
				for (int k = 0; k < 4; k++) {
					s[ga_base(k, c) + (int)cnt[k]] = x[c] + (s[8 + 4 * (1 - c) + k] * regen);
				}
			}
			for (int k = 0; k < 4; k++) {
				step(k);
			}
			for (int st = 0; st < 3; st++) {
				const int k0 = 4 * st;
				double o[2][4];
				for (int c = 0; c < 2; c++) {
					for (int k = 0; k < 4; k++) {
						o[c][k] = rd(k0 + k, c);
					}
				}
				for (int c = 0; c < 2; c++) {
					for (int k = 0; k < 4; k++) {
						double others = 0.0;
						for (int j = 0; j < 4; j++) {
							if (j != k) {
								others += o[c][j];
							}
						}
						const double v = o[c][k] - others;
						if (st < 2) {
							s[ga_base(k0 + 4 + k, c) + (int)cnt[k0 + 4 + k]] = v;
						} else {
							s[8 + 4 * c + k] = v;
						}
					}
					if (st == 2) {
						x[c] = (o[c][0] + o[c][1] + o[c][2] + o[c][3]) / 8.0;
					}
				}
				if (st < 2) {
					for (int k = 0; k < 4; k++) {
						step(k0 + 4 + k);
					}
				}
			}
			for (int c = 0; c < 2; c++) {
				double *ref = c == 0 ? refl : refr;
				const double in = x[c];
				if (ce == 4) {
					ref[0] = ref[4];
					ref[2] = (ref[0] + in) / 2;
					ref[1] = (ref[0] + ref[2]) / 2;
					ref[3] = (ref[2] + in) / 2;
					ref[4] = in;
				}
				if (ce == 3) {
					ref[0] = ref[3];
					ref[2] = (ref[0] + ref[0] + in) / 3;
					ref[1] = (ref[0] + in + in) / 3;
					ref[3] = in;
				}
				if (ce == 2) {
					ref[0] = ref[2];
					ref[1] = (ref[0] + in) / 2;
					ref[2] = in;
				}
				if (ce == 1) {
					ref[0] = in;
				}
			}
			s[43] = 0.0;
		}
		const int cy = (int)s[43];
		x[0] = refl[cy];
		x[1] = refr[cy];
		for (int c = 0; c < 2; c++) {
			s[6 + c] = (s[6 + c] * (1.0 - lp)) + (x[c] * lp);
			x[c] = s[6 + c];
			if (wt < 1.0) {
				x[c] = (x[c] * wt) + (dry_[c] * (1.0 - wt));
			}
		}
		s[46] = aw_fpd(s[46]);
		l = x[0];
		r = x[1];
	}

	// Stutter: xk rate_hz (repeats a second: a slice is 1 / rate_hz long), resample_hz (how
	// often a new slice is taken), softness (0 hard edges .. 1 each repeat a raised-cosine
	// swell), pitch (semitones: the repeats read faster or slower, looping inside the slice),
	// rate_beats and resample_beats (note lengths at the tempo in place of the Hz; set_tempo).
	// The input always records; a slice is the last 1 / rate_hz of it, captured at the end of a
	// repeat once 1 / resample_hz has passed (so never shorter than a repeat), and played over
	// and over until the next. Before the first slice the input passes.
	static constexpr double ST_MAX_S = 1.0;

	inline void st_capture(int n, int lt) {
		const int len = std::max(16, std::min(lt, (int)xs[6]));
		xs[0] = 1.0 - xs[0];   // the buffer just recorded is the slice's now
		int st = xw - len;
		if (st < 0) {
			st += n;
		}
		xs[1] = 1.0;
		xs[2] = st;
		xs[3] = len;
		xs[4] = 0.0;
		xs[5] = 0.0;
		xs[6] = 0.0;
	}

	inline void tick_stutter(double &l, double &r) {
		const int n = (int)xb.size() / 4;
		const int rec = (int)xs[0];
		xb[2 * rec * n + xw] = l;
		xb[(2 * rec + 1) * n + xw] = r;
		xw = xw + 1 == n ? 0 : xw + 1;
		xs[6] = std::min(xs[6] + 1.0, double(n - 1));
		const int lt = std::clamp((int)std::lround(sr / xk[0]), 16, n - 1);
		if (xs[1] != 0.0) {
			xs[4] += 1.0;
			xs[5] += 1.0;
			if (xs[4] >= xs[3]) {
				xs[4] -= xs[3];
				if (xs[5] >= sr / xk[1]) {
					st_capture(n, lt);
				}
			}
		} else if (xs[6] >= lt) {
			st_capture(n, lt);
		}
		double out[2] = { l, r };
		if (xs[1] != 0.0) {
			const double len = xs[3], p = xs[4];
			double q = p * xc[0];
			q -= std::floor(q / len) * len;
			const int i0 = (int)q;
			const double fr = q - i0;
			const int i1 = i0 + 1 >= (int)len ? 0 : i0 + 1;
			const int st = (int)xs[2];
			const int a = st + i0 >= n ? st + i0 - n : st + i0;
			const int b = st + i1 >= n ? st + i1 - n : st + i1;
			const int bs = 2 * (1 - (int)xs[0]) * n;   // the slice's buffer (the one not recording now)
			double w = 1.0;
			const double f = xk[2] * len * 0.5;
			if (f >= 1.0) {
				if (p < f) {
					w = 0.5 - 0.5 * std::cos(PI * p / f);
				} else if (p > len - f) {
					w = 0.5 - 0.5 * std::cos(PI * (len - p) / f);
				}
			}
			for (int c = 0; c < 2; c++) {
				const double *buf = xb.data() + bs + c * n;
				out[c] = (buf[a] * (1.0 - fr) + buf[b] * fr) * w;
			}
		}
		l = l * dm() + out[0] * wm();
		r = r * dm() + out[1] * wm();
	}
};

// Effects in order.
struct FxChain {
	std::vector<Fx> fx;
	void setup(int sr) {
		for (Fx &f : fx) {
			f.setup(sr);
		}
	}
	inline void tick(double &l, double &r) {
		for (Fx &f : fx) {
			f.tick(l, r);
		}
	}
	bool empty() const { return fx.empty(); }
	// Tempo-synced effects (a delay's time_beats) follow bpm. No allocation.
	void set_tempo(double bpm) {
		for (Fx &f : fx) {
			if (f.type == Fx::DELAY && f.time_beats > 0.0) {
				const double ms = std::clamp(f.time_beats * 60000.0 / std::max(bpm, 1.0), 1.0, 2000.0);
				f.delay_lengths(ms);
			}
			if (f.type == Fx::STUTTER) {
				// A synced stutter: its rates from note lengths at the tempo.
				if (f.xk[4] > 0.0) {
					f.xk[0] = std::clamp(std::max(bpm, 1.0) / 60.0 / f.xk[4], 1.0, 100.0);
				}
				if (f.xk[5] > 0.0) {
					f.xk[1] = std::clamp(std::max(bpm, 1.0) / 60.0 / f.xk[5], 0.05, 100.0);
				}
			}
		}
	}
};

} // namespace ak
