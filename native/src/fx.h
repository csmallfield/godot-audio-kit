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
#include <vector>

namespace ak {

struct Fx {
	enum Type { NONE, CHORUS, FLANGER, PHASER, EQ, COMPRESSOR, SATURATE, PITCH, RING, GROWL, CRUSH, DELAY, REVERB, FILTER };
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
	// Pitch, ring, growl, crush, delay, reverb
	double semitones = -12.0, window_ms = 60.0, freq_hz = 220.0, jitter = 0.5, bits = 8.0, time_ms = 250.0, damp_hz = 4000.0;
	double room = 0.6, damp = 0.5, width = 1.0;
	int hold = 1;
	// A tempo-synced delay: its time in beats (0: time_ms). Its mode (0 stereo,
	// 1 cross, 2 pingpong) and spread (ms the right side repeats later; negative: the left).
	double time_beats = 0.0;
	int mode = 0;
	double spread_ms = 0.0;
	// Filter (mode 0 lowpass, 1 highpass; slope 6, 12 or 24 dB).
	double cutoff_hz = 1000.0, q = 0.707, slope_db = 12.0;
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
				l = in[0] * (1.0 - mix) + wet[0] * mix;
				r = in[1] * (1.0 - mix) + wet[1] * mix;
				break;
			}
			case RING: {
				const double c = std::sin(TAU * cph);
				cph += freq_hz * std::pow(2.0, depth * std::sin(TAU * ph)) / sr;
				cph -= std::floor(cph);
				ph += rate_hz / sr;
				ph -= std::floor(ph);
				l = l * (1.0 - mix) + l * c * mix;
				r = r * (1.0 - mix) + r * c * mix;
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
				l = l * (1.0 - mix) + l * g * mix;
				r = r * (1.0 - mix) + r * g * mix;
				break;
			}
			case CRUSH: {
				if (ctr == 0) {
					const double step = std::pow(2.0, 1.0 - bits);
					held[0] = std::floor(l / step + 0.5) * step;
					held[1] = std::floor(r / step + 0.5) * step;
				}
				ctr = (ctr + 1) % hold;
				l = l * (1.0 - mix) + held[0] * mix;
				r = r * (1.0 - mix) + held[1] * mix;
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
				l = in[0] + y[0] * mix;
				r = in[1] + y[1] * mix;
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
			case REVERB: {
				const double input = (l + r) * 0.015;
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
				l += (out[0] * rv_w1 + out[1] * rv_w2) * mix;
				r += (out[1] * rv_w1 + out[0] * rv_w2) * mix;
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
	// Tempo-synced effects (a delay's time_beats) follow bpm. No allocation.
	void set_tempo(double bpm) {
		for (Fx &f : fx) {
			if (f.type == Fx::DELAY && f.time_beats > 0.0) {
				const double ms = std::clamp(f.time_beats * 60000.0 / std::max(bpm, 1.0), 1.0, 2000.0);
				f.delay_lengths(ms);
			}
		}
	}
};

} // namespace ak
