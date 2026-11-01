// SPDX-License-Identifier: Apache-2.0
#include "ak_match.h"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <cmath>
#include <complex>

using namespace godot;

namespace {

const double PI = 3.14159265358979323846;
typedef std::complex<double> cx;

void fft(std::vector<cx> &a) {
	size_t n = a.size();
	for (size_t i = 1, j = 0; i < n; i++) {
		size_t bit = n >> 1;
		for (; j & bit; bit >>= 1) {
			j ^= bit;
		}
		j |= bit;
		if (i < j) {
			std::swap(a[i], a[j]);
		}
	}
	for (size_t len = 2; len <= n; len <<= 1) {
		double ang = -2.0 * PI / (double)len;
		cx wl(std::cos(ang), std::sin(ang));
		for (size_t i = 0; i < n; i += len) {
			cx w(1.0, 0.0);
			for (size_t k = 0; k < len / 2; k++) {
				cx u = a[i + k], v = a[i + k + len / 2] * w;
				a[i + k] = u + v;
				a[i + k + len / 2] = u - v;
				w *= wl;
			}
		}
	}
}

size_t pow2_at_least(size_t n) {
	size_t p = 1;
	while (p < n) {
		p <<= 1;
	}
	return p;
}

// The patch EQ's biquads (stream_fx.gd), as their response at f.
cx biquad(const double *b, const double *a, double f, double sr) {
	cx z = std::polar(1.0, -2.0 * PI * f / sr);
	return (b[0] + b[1] * z + b[2] * z * z) / (a[0] + a[1] * z + a[2] * z * z);
}

cx shelf(double f0, double g, bool high, double f, double sr) {
	double A = std::pow(10.0, g / 40.0), w = 2.0 * PI * f0 / sr, cw = std::cos(w), sw = std::sin(w);
	double t = 2.0 * std::sqrt(A) * sw / 2.0 * std::sqrt(2.0);
	if (!high) {
		double b[3] = { A * ((A + 1) - (A - 1) * cw + t), 2 * A * ((A - 1) - (A + 1) * cw), A * ((A + 1) - (A - 1) * cw - t) };
		double a[3] = { (A + 1) + (A - 1) * cw + t, -2 * ((A - 1) + (A + 1) * cw), (A + 1) + (A - 1) * cw - t };
		return biquad(b, a, f, sr);
	}
	double b[3] = { A * ((A + 1) + (A - 1) * cw + t), -2 * A * ((A - 1) + (A + 1) * cw), A * ((A + 1) + (A - 1) * cw - t) };
	double a[3] = { (A + 1) - (A - 1) * cw + t, 2 * ((A - 1) - (A + 1) * cw), (A + 1) - (A - 1) * cw - t };
	return biquad(b, a, f, sr);
}

cx peaking(double f0, double g, double q, double f, double sr) {
	double A = std::pow(10.0, g / 40.0), w = 2.0 * PI * f0 / sr, al = std::sin(w) / (2.0 * q);
	double b[3] = { 1 + al * A, -2 * std::cos(w), 1 - al * A };
	double a[3] = { 1 + al / A, -2 * std::cos(w), 1 - al / A };
	return biquad(b, a, f, sr);
}

// A 12 dB low-pass's magnitude.
double lowpass(double f, double fc, double q) {
	double r = f / fc;
	return 1.0 / std::sqrt((1 - r * r) * (1 - r * r) + (r / q) * (r / q));
}

} // namespace

void AKMatch::_bind_methods() {
	ClassDB::bind_method(D_METHOD("highpass", "x", "sr", "hz"), &AKMatch::highpass);
	ClassDB::bind_method(D_METHOD("spectrum", "x", "start", "n", "nfft"), &AKMatch::spectrum);
	ClassDB::bind_method(D_METHOD("dft", "x", "start", "n", "freqs", "sr", "t0"), &AKMatch::dft);
	ClassDB::bind_method(D_METHOD("features", "x", "start", "length", "f0", "sr", "kmax", "fmax"), &AKMatch::features);
	ClassDB::bind_method(D_METHOD("clear"), &AKMatch::clear);
	ClassDB::bind_method(D_METHOD("add_slot", "note", "ha", "na", "frames_a", "hb", "nb", "frames_b", "k", "first_s"), &AKMatch::add_slot);
	ClassDB::bind_method(D_METHOD("setup", "center", "semis", "kp", "neq", "sr"), &AKMatch::setup);
	ClassDB::bind_method(D_METHOD("score", "params", "stages", "off", "floor"), &AKMatch::score);
	ClassDB::bind_method(D_METHOD("slot_scores", "off", "floor"), &AKMatch::slot_scores);
	ClassDB::bind_method(D_METHOD("slot_levels", "params", "stages", "off"), &AKMatch::slot_levels);
	ClassDB::bind_method(D_METHOD("slot_count"), &AKMatch::slot_count);
}

PackedFloat32Array AKMatch::highpass(const PackedFloat32Array &x, double sr, double hz) {
	int n = x.size();
	PackedFloat32Array out;
	out.resize(n);
	if (n == 0) {
		return out;
	}
	// The bilinear Butterworth (Q = 1/sqrt 2), as scipy's butter(2, hz, 'hp').
	double k = std::tan(PI * hz / sr), q = std::sqrt(0.5), a0 = 1 + k / q + k * k;
	double b0 = 1 / a0, b1 = -2 / a0, b2 = 1 / a0, a1 = 2 * (k * k - 1) / a0, a2 = (1 - k / q + k * k) / a0;
	// Odd extension at both ends, so neither pass starts with a step.
	int pad = std::min(n - 1, (int)(sr / hz));
	std::vector<double> v(n + 2 * pad);
	const float *p = x.ptr();
	for (int i = 0; i < pad; i++) {
		v[i] = 2.0 * p[0] - p[pad - i];
		v[n + pad + i] = 2.0 * p[n - 1] - p[n - 2 - i];
	}
	for (int i = 0; i < n; i++) {
		v[pad + i] = p[i];
	}
	auto run = [&](bool back) {
		double x1 = 0, x2 = 0, y1 = 0, y2 = 0;
		int m = (int)v.size();
		for (int j = 0; j < m; j++) {
			int i = back ? m - 1 - j : j;
			double in = v[i], y = b0 * in + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
			x2 = x1;
			x1 = in;
			y2 = y1;
			y1 = y;
			v[i] = y;
		}
	};
	run(false);
	run(true);
	float *o = out.ptrw();
	for (int i = 0; i < n; i++) {
		o[i] = (float)v[pad + i];
	}
	return out;
}

PackedFloat64Array AKMatch::spectrum(const PackedFloat32Array &x, int start, int n, int nfft) {
	size_t m = pow2_at_least((size_t)std::max(nfft, n));
	std::vector<cx> a(m, cx(0, 0));
	double ws = 0;
	for (int i = 0; i < n; i++) {
		double w = n > 1 ? 0.5 - 0.5 * std::cos(2 * PI * i / (n - 1)) : 1.0;
		int j = start + i;
		a[i] = (j >= 0 && j < x.size() ? x[j] : 0.0) * w;
		ws += w;
	}
	fft(a);
	PackedFloat64Array out;
	out.resize(m / 2 + 1);
	for (size_t i = 0; i <= m / 2; i++) {
		out[i] = std::abs(a[i]) * 2.0 / std::max(ws, 1e-30);
	}
	return out;
}

PackedFloat64Array AKMatch::dft(const PackedFloat32Array &x, int start, int n, const PackedFloat64Array &freqs, double sr, double t0) {
	std::vector<double> s(n), w(n);
	double ws = 0;
	for (int i = 0; i < n; i++) {
		w[i] = n > 1 ? 0.5 - 0.5 * std::cos(2 * PI * i / (n - 1)) : 1.0;
		ws += w[i];
		int j = start + i;
		s[i] = (j >= 0 && j < x.size() ? x[j] : 0.0);
	}
	PackedFloat64Array out;
	out.resize(freqs.size() * 2);
	for (int k = 0; k < freqs.size(); k++) {
		// The phasor turned by recurrence, restarted every 1024 samples to keep it exact.
		double f = freqs[k], re = 0, im = 0;
		cx step = std::polar(1.0, -2 * PI * f / sr), ph;
		for (int i = 0; i < n; i++) {
			if ((i & 1023) == 0) {
				ph = std::polar(1.0, -2 * PI * f * (t0 + i / sr));
			}
			double v = s[i] * w[i];
			re += v * ph.real();
			im += v * ph.imag();
			ph *= step;
		}
		out[2 * k] = 2 * re / std::max(ws, 1e-30);
		out[2 * k + 1] = 2 * im / std::max(ws, 1e-30);
	}
	return out;
}

Array AKMatch::features(const PackedFloat32Array &x, int start, int length, double f0, double sr, int kmax, double fmax) {
	// Frames as scipy's stft(window = 'hann' (periodic), nperseg = L, noverlap = L - hop, boundary = None,
	// padded = False): the power |FFT(x w) / sum w|^2.
	const int hop = 441;
	int L = (int)std::max(4 * sr / f0, 512.0);
	size_t nfft = pow2_at_least((size_t)(2 * L));
	int frames = length >= L ? (length - L) / hop + 1 : 0;
	int K = (int)std::min((double)kmax, std::floor(fmax / f0));
	K = std::max(K, 0);
	double df = sr / (double)nfft;
	int nb = (int)nfft / 2 + 1;
	std::vector<double> win(L);
	double ws = 0;
	for (int i = 0; i < L; i++) {
		win[i] = 0.5 - 0.5 * std::cos(2 * PI * i / L);
		ws += win[i];
	}
	// Bins near a harmonic (up to 16 kHz) don't count as noise.
	std::vector<char> mask(nb, 1);
	for (int k = 1; k <= (int)std::floor(16000.0 / f0) + 1; k++) {
		int lo = std::max((int)((k - 0.35) * f0 / df), 0), hi = std::min((int)((k + 0.35) * f0 / df) + 1, nb);
		for (int i = lo; i < hi; i++) {
			mask[i] = 0;
		}
	}
	const double bands[4][2] = { { 200, 800 }, { 800, 2500 }, { 2500, 6000 }, { 6000, 16000 } };
	PackedFloat64Array H, N;
	H.resize(frames * K);
	N.resize(frames * 4);
	std::vector<cx> a(nfft);
	std::vector<double> P(nb);
	for (int fr = 0; fr < frames; fr++) {
		std::fill(a.begin(), a.end(), cx(0, 0));
		int s0 = start + fr * hop;
		for (int i = 0; i < L; i++) {
			int j = s0 + i;
			a[i] = (j >= 0 && j < x.size() ? x[j] : 0.0) * win[i] / ws;
		}
		fft(a);
		for (int i = 0; i < nb; i++) {
			P[i] = std::norm(a[i]);
		}
		for (int k = 1; k <= K; k++) {
			int lo = (int)((k - 0.3) * f0 / df), hi = std::min((int)((k + 0.3) * f0 / df) + 1, nb);
			double m = 0;
			for (int i = lo; i < hi; i++) {
				m = std::max(m, P[i]);
			}
			H[fr * K + k - 1] = 10 * std::log10(m + 1e-14);
		}
		for (int b = 0; b < 4; b++) {
			double sum = 0;
			int in_band = 0, kept = 0;
			for (int i = 0; i < nb; i++) {
				double f = i * df;
				if (f >= bands[b][0] && f < bands[b][1]) {
					in_band++;
					if (mask[i]) {
						sum += P[i];
						kept++;
					}
				}
			}
			N[fr * 4 + b] = 10 * std::log10((kept ? sum / kept * in_band : 0.0) + 1e-14);
		}
	}
	Array out;
	out.push_back(H);
	out.push_back(N);
	out.push_back(frames);
	out.push_back(K);
	return out;
}

void AKMatch::clear() {
	slots.clear();
}

void AKMatch::add_slot(double note, const PackedFloat64Array &ha, const PackedFloat64Array &na, int frames_a,
		const PackedFloat64Array &hb, const PackedFloat64Array &nb, int frames_b, int k, double first_s) {
	Slot s;
	s.note = note;
	s.fa = frames_a;
	s.fb = frames_b;
	s.k = k;
	s.first_s = first_s;
	s.ha.assign(ha.ptr(), ha.ptr() + ha.size());
	s.na.assign(na.ptr(), na.ptr() + na.size());
	s.hb.assign(hb.ptr(), hb.ptr() + hb.size());
	s.nb.assign(nb.ptr(), nb.ptr() + nb.size());
	slots.push_back(std::move(s));
}

void AKMatch::setup(double p_center, double p_semis, const PackedFloat64Array &p_kp, int p_neq, double p_sr) {
	center = p_center;
	semis = p_semis;
	kp.assign(p_kp.ptr(), p_kp.ptr() + p_kp.size());
	neq = p_neq;
	sr = p_sr;
}

void AKMatch::correct(const std::vector<double> &p, int stages, std::vector<std::vector<double>> &out) const {
	const double floor24 = std::pow(10.0, -24.0 / 20.0);
	auto f0 = [&](double n) { return 440.0 * std::pow(2.0, (n + semis - 69.0) / 12.0); };
	double fc = std::exp(p[0]), amt = p[1], q = std::exp(p[2]), a = p[3], e2 = p[4], e3 = p[5];
	auto cut = [&](double n, double t) {
		return std::clamp(fc * std::pow(2.0, amt * (n - 60) / 12 + e2 * std::exp(-t / 0.08) + e3 * std::min(t, 1.0)), 20.0, 20000.0);
	};
	auto heq = [&](double f) {
		cx h(1, 0);
		for (int i = 0; i < neq; i++) {
			const double *e = &p[6 + i * 7];
			h *= shelf(std::exp(e[0]), e[1], false, f, sr) * peaking(std::exp(e[2]), e[3], std::exp(e[4]), f, sr) * shelf(std::exp(e[5]), e[6], true, f, sr);
		}
		return h;
	};
	double fcn = f0(center), kc = (center - 60) / 12;
	out.resize(slots.size());
	for (size_t si = 0; si < slots.size(); si++) {
		const Slot &s = slots[si];
		std::vector<double> &o = out[si];
		o = s.hb;
		double fn = f0(s.note), kn = (s.note - 60) / 12;
		std::vector<double> per_k(s.k, 0.0);
		if (stages & 2) {
			for (int k = 1; k <= s.k; k++) {
				per_k[k - 1] += 20 * std::log10(std::abs(heq(k * fn)) / std::max(std::abs(heq(k * fcn)), floor24));
			}
		}
		if ((stages & 4) && !kp.empty()) {
			const double *kd = &p[6 + neq * 7];
			double g;
			if (s.note <= kp.front()) {
				g = kd[0];
			} else if (s.note >= kp.back()) {
				g = kd[kp.size() - 1];
			} else {
				size_t j = 1;
				while (kp[j] < s.note) {
					j++;
				}
				double u = (s.note - kp[j - 1]) / (kp[j] - kp[j - 1]);
				g = kd[j - 1] + (kd[j] - kd[j - 1]) * u;
			}
			for (double &v : per_k) {
				v += g;
			}
		}
		double g = std::max(1 + a * kn, 1e-3) / std::max(1 + a * kc, 1e-3);
		for (int fr = 0; fr < s.fb; fr++) {
			double t = s.first_s + fr * 441.0 / sr;
			double ctn = (stages & 1) ? cut(s.note, t) : 0, ctc = (stages & 1) ? cut(center, t) : 0;
			for (int k = 1; k <= s.k; k++) {
				double c = per_k[k - 1];
				if (stages & 1) {
					c += 20 * std::log10(lowpass(k * fn, ctn, q) / std::max(lowpass(k * fcn, ctc, q), floor24) * g);
				}
				o[fr * s.k + k - 1] += c;
			}
		}
	}
}

double AKMatch::score_of(const std::vector<std::vector<double>> &hb, double off, double fl, bool match, double &off_out) const {
	if (match) {
		double ea = 0, eb = 0;
		for (size_t si = 0; si < slots.size(); si++) {
			for (double v : slots[si].ha) {
				ea += std::pow(10.0, v / 10);
			}
			for (double v : hb[si]) {
				eb += std::pow(10.0, v / 10);
			}
		}
		off = 10 * std::log10(ea) - 10 * std::log10(eb + 1e-30);
	}
	off_out = off;
	double num = 0, den = 0, nn = 0, nd = 0;
	for (size_t si = 0; si < slots.size(); si++) {
		const Slot &s = slots[si];
		int n = std::min(s.fa, s.fb);
		for (int fr = 0; fr < n; fr++) {
			for (int k = 0; k < s.k; k++) {
				double a = std::max(s.ha[fr * s.k + k], fl), b = std::max(hb[si][fr * s.k + k] + off, fl);
				if (a > fl + 1 || b > fl + 1) {
					double w = 1 / std::sqrt((double)(k + 1));
					num += std::fabs(a - b) * w;
					den += w;
				}
			}
			for (int b_ = 0; b_ < 4; b_++) {
				double a = std::max(s.na[fr * 4 + b_], fl), b = std::max(s.nb[fr * 4 + b_] + off, fl);
				if (a > fl + 1 || b > fl + 1) {
					nn += std::fabs(a - b);
					nd += 1;
				}
			}
		}
	}
	return num / std::max(den, 1e-9) + 0.5 * nn / std::max(nd, 1e-9);
}

PackedFloat64Array AKMatch::score(const PackedFloat64Array &params, int stages, double off, double floor) {
	std::vector<double> p(params.ptr(), params.ptr() + params.size());
	p.resize(std::max(p.size(), (size_t)(6 + neq * 7 + kp.size())), 0.0);
	std::vector<std::vector<double>> hb;
	if (stages) {
		correct(p, stages, hb);
	} else {
		for (const Slot &s : slots) {
			hb.push_back(s.hb);
		}
	}
	double fl = floor;
	if (off < -900) {
		double mx = -1e30;
		for (const Slot &s : slots) {
			for (double v : s.ha) {
				mx = std::max(mx, v);
			}
		}
		fl = mx - 60;
	}
	double off_out = 0;
	double l = score_of(hb, off, fl, off < -900, off_out);
	PackedFloat64Array out;
	out.push_back(l);
	out.push_back(off_out);
	out.push_back(fl);
	return out;
}

PackedFloat64Array AKMatch::slot_scores(double off, double floor) {
	PackedFloat64Array out;
	std::vector<Slot> all;
	all.swap(slots);
	for (Slot &s : all) {
		slots.clear();
		slots.push_back(s);
		std::vector<std::vector<double>> hb{ s.hb };
		double o;
		out.push_back(score_of(hb, off, floor, false, o));
	}
	slots.swap(all);
	return out;
}

PackedFloat64Array AKMatch::slot_levels(const PackedFloat64Array &params, int stages, double off) {
	std::vector<double> p(params.ptr(), params.ptr() + params.size());
	p.resize(std::max(p.size(), (size_t)(6 + neq * 7 + kp.size())), 0.0);
	std::vector<std::vector<double>> hb;
	correct(p, stages, hb);
	PackedFloat64Array out;
	for (size_t si = 0; si < slots.size(); si++) {
		double ea = 0, eb = 0;
		for (double v : slots[si].ha) {
			ea += std::pow(10.0, v / 10);
		}
		for (double v : hb[si]) {
			eb += std::pow(10.0, (v + off) / 10);
		}
		out.push_back(10 * std::log10(ea / std::max(eb, 1e-30)));
	}
	return out;
}
