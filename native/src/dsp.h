// SPDX-License-Identifier: Apache-2.0
// Shared DSP pieces used by both the offline kernels (AKNative) and the live
// mixer (AKLivePlayback). Plain C++, no Godot types.
#pragma once
#include <cmath>
#include <cstdint>
#include <vector>

namespace ak {

constexpr double TAU = 6.283185307179586;
constexpr double PI = 3.141592653589793;
constexpr double SQRT2 = 1.4142135623730951;

inline double blep(double t, double dt) {
	if (dt <= 0.0) {
		return 0.0;
	}
	if (t < dt) {
		double x = t / dt;
		return x + x - x * x - 1.0;
	}
	if (t > 1.0 - dt) {
		double x = (t - 1.0) / dt;
		return x * x + x + x + 1.0;
	}
	return 0.0;
}

// Freeverb (Jezar, public domain), streaming: process one sample at a time.
struct Freeverb {
	static constexpr int COMBS[8] = { 1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617 };
	static constexpr int PASSES[4] = { 556, 441, 341, 225 };
	static constexpr int SPREAD = 23;

	struct Comb {
		std::vector<float> line;
		int idx = 0;
		double store = 0.0;
	};
	struct Pass {
		std::vector<float> line;
		int idx = 0;
	};
	Comb combs[2][8];
	Pass passes[2][4];
	int n_combs = 8;
	int n_passes = 4;
	double fb = 0.84, damp = 0.2, gain = 0.015, w1 = 1.0, w2 = 0.0;

	void setup(int sr, double room, double damp_, double width, bool small) {
		double scale = double(sr) / 44100.0;
		n_combs = small ? 4 : 8;
		n_passes = small ? 2 : 4;
		for (int ch = 0; ch < 2; ch++) {
			int spread = ch == 0 ? 0 : SPREAD;
			for (int c = 0; c < n_combs; c++) {
				int len = (int)std::lround((COMBS[small ? c * 2 : c] + spread) * scale);
				combs[ch][c].line.assign(len < 1 ? 1 : len, 0.0f);
				combs[ch][c].idx = 0;
				combs[ch][c].store = 0.0;
			}
			for (int a = 0; a < n_passes; a++) {
				int len = (int)std::lround((PASSES[small ? a * 2 : a] + spread) * scale);
				passes[ch][a].line.assign(len < 1 ? 1 : len, 0.0f);
				passes[ch][a].idx = 0;
			}
		}
		room = room < 0 ? 0 : (room > 1 ? 1 : room);
		damp_ = damp_ < 0 ? 0 : (damp_ > 1 ? 1 : damp_);
		fb = room * 0.28 + 0.7;
		damp = damp_ * 0.4;
		gain = 0.015 * (small ? 2.0 : 1.0);
		w1 = width * 0.5 + 0.5;
		w2 = (1.0 - width) * 0.5;
	}

	// In: one stereo sample (already scaled by the send). Out: wet l, r.
	inline void process(float in_l, float in_r, float &out_l, float &out_r) {
		float input = (float)((in_l + in_r) * gain);
		float ch_out[2];
		for (int ch = 0; ch < 2; ch++) {
			float acc = 0.0f;
			for (int c = 0; c < n_combs; c++) {
				Comb &cb = combs[ch][c];
				float y = cb.line[cb.idx];
				cb.store = y * (1.0 - damp) + cb.store * damp;
				cb.line[cb.idx] = (float)(input + cb.store * fb);
				acc += y;
				if (++cb.idx == (int)cb.line.size()) {
					cb.idx = 0;
				}
			}
			for (int a = 0; a < n_passes; a++) {
				Pass &p = passes[ch][a];
				float bufout = p.line[p.idx];
				float x = acc;
				acc = bufout - x;
				p.line[p.idx] = x + bufout * 0.5f;
				if (++p.idx == (int)p.line.size()) {
					p.idx = 0;
				}
			}
			ch_out[ch] = acc;
		}
		out_l = (float)(ch_out[0] * w1 + ch_out[1] * w2);
		out_r = (float)(ch_out[1] * w1 + ch_out[0] * w2);
	}
};

// Sidechain ducking: an envelope follower on the source sets how far the
// target is turned down. Full `depth_db` once the source reaches `full`
// (linear), proportionally below that. Shared by the offline kernel and the
// live buses so both duck identically.
struct Ducker {
	double env = 0.0, att = 1.0, rel = 0.0, depth_db = 0.0, full = 0.06;
	void setup(int sr, double depth_db_, double full_, double attack_s, double release_s) {
		depth_db = depth_db_;
		full = full_ < 1e-6 ? 1e-6 : full_;
		att = 1.0 - std::exp(-1.0 / std::max(1.0, attack_s * sr));
		rel = 1.0 - std::exp(-1.0 / std::max(1.0, release_s * sr));
		env = 0.0;
	}
	inline double tick(double x) {
		env += (x - env) * (x > env ? att : rel);
		double amt = env / full;
		amt = amt > 1.0 ? 1.0 : amt;
		return std::pow(10.0, -depth_db * amt / 20.0);
	}
};

// Topology-preserving state-variable filter (as AKFilter.svf).
struct SVF {
	double ic1 = 0.0, ic2 = 0.0, k = 1.414;
	double g = 0, a1 = 0, a2 = 0, a3 = 0;
	void set_q(double q) { k = 1.0 / (q < 0.05 ? 0.05 : q); }
	void set_cutoff(double fc, int sr) {
		double nyq = 0.49 * sr;
		fc = fc < 10.0 ? 10.0 : (fc > nyq ? nyq : fc);
		g = std::tan(PI * fc / sr);
		a1 = 1.0 / (1.0 + g * (g + k));
		a2 = g * a1;
		a3 = g * a2;
	}
	inline double tick(double v0, int mode) {
		double v3 = v0 - ic2;
		double v1 = a1 * ic1 + a2 * v3;
		double v2 = ic2 + a2 * ic1 + a3 * v3;
		ic1 = 2.0 * v1 - ic1;
		ic2 = 2.0 * v2 - ic2;
		switch (mode) {
			case 0: return v2;
			case 1: return v0 - k * v1 - v2;
			case 2: return v1;
			default: return v0 - k * v1;
		}
	}
};

} // namespace ak
