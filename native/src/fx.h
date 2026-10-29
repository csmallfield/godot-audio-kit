// SPDX-License-Identifier: Apache-2.0
// Sound-shaping effects that stream one stereo sample at a time: chorus and
// flanger (a modulated delay), phaser, three-band EQ, compressor and
// saturation. The same structs run inside patches (the synth engine), on
// recipe buffers (AKNative.fx_process) and as Godot bus effects (AKChorus,
// AKPhaser ...), so an effect sounds the same in all three. Each mirrors
// AKStreamFx (addons/audio_kit/dsp/stream_fx.gd) step for step.
#pragma once
#include "dsp.h"

#include <cmath>
#include <vector>

namespace ak {

struct Fx {
	enum Type { NONE, CHORUS, FLANGER, PHASER, EQ, COMPRESSOR, SATURATE };
	int type = NONE;
	int sr = 48000;
	// Shared knobs (meaning depends on the type; see AKStreamFx.compile).
	double rate_hz = 0.8, depth_ms = 3.0, delay_ms = 12.0, feedback = 0.0, mix = 0.5, spread = 1.0;
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

	// ---- state
	double ph = 0.0;
	std::vector<float> line[2];
	int w = 0;
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

	static double db(double x) { return std::pow(10.0, x / 20.0); }

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
			const int n = (int)std::ceil((delay_ms + depth_ms) * sr / 1000.0) + 4;
			line[0].assign(n < 8 ? 8 : n, 0.0f);
			line[1].assign(n < 8 ? 8 : n, 0.0f);
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
		if (type == SATURATE) {
			sat_g = db(drive_db);
			sat_off = std::tanh(asymmetry);
			sat_lp = 1.0 - std::exp(-TAU * tone_hz / sr);
			sat_out = db(output_db) / std::tanh(sat_g);   // a full-scale input peaks at output_db
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
				l = in[0] * (1.0 - mix) + wet[0] * mix;
				r = in[1] * (1.0 - mix) + wet[1] * mix;
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
					io[c] = io[c] * (1.0 - mix) + x * mix;
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
					io[c] = io[c] * (1.0 - mix) + sat_z[c] * mix;
				}
				l = io[0];
				r = io[1];
				break;
			}
			default:
				break;
		}
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
};

} // namespace ak
