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
		ENSEMBLE, COMBULATOR, TAPE, TREEMONSTER, SPRING, BONSAI, CHOW, NEURON, N_TYPES };

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
		switch (t) {
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
	double xc[24] = {};   // coefficients from the knobs (setup_x; not carried by retune)
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
