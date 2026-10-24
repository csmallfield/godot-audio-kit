// SPDX-License-Identifier: Apache-2.0
#include "ak_native.h"
#include "dsp.h"
#include "ak_synth.h"

#include <godot_cpp/core/class_db.hpp>
#include <algorithm>
#include <cmath>

using namespace godot;
using ak::TAU;

void AKNative::_bind_methods() {
	ClassDB::bind_static_method("AKNative", D_METHOD("version"), &AKNative::version);
	ClassDB::bind_method(D_METHOD("glide", "n", "sr", "a", "b", "time_s"), &AKNative::glide);
	ClassDB::bind_method(D_METHOD("mul", "a", "b"), &AKNative::mul);
	ClassDB::bind_method(D_METHOD("add", "a", "b", "gain", "at"), &AKNative::add);
	ClassDB::bind_method(D_METHOD("scale", "a", "gain"), &AKNative::scale);
	ClassDB::bind_method(D_METHOD("sine", "freq", "sr", "phase0"), &AKNative::sine);
	ClassDB::bind_method(D_METHOD("sine_const", "n", "freq", "sr", "phase0"), &AKNative::sine_const);
	ClassDB::bind_method(D_METHOD("saw", "freq", "sr", "phase0"), &AKNative::saw);
	ClassDB::bind_method(D_METHOD("square", "freq", "sr", "width", "phase0"), &AKNative::square);
	ClassDB::bind_method(D_METHOD("triangle", "freq", "sr", "phase0"), &AKNative::triangle);
	ClassDB::bind_method(D_METHOD("env_decay", "n", "sr", "attack_s", "decay_s"), &AKNative::env_decay);
	ClassDB::bind_method(D_METHOD("env_adsr", "n", "sr", "a", "d", "s", "r", "gate"), &AKNative::env_adsr);
	ClassDB::bind_method(D_METHOD("lowpass1", "x", "cutoffs", "cutoff", "sr"), &AKNative::lowpass1);
	ClassDB::bind_method(D_METHOD("svf", "x", "cutoffs", "cutoff", "q", "sr", "mode"), &AKNative::svf);
	ClassDB::bind_method(D_METHOD("karplus", "init", "n", "sr", "decay_s", "brightness"), &AKNative::karplus);
	ClassDB::bind_method(D_METHOD("reverb_wet", "l", "r", "sr", "room", "damp", "width", "tail", "small"), &AKNative::reverb_wet);
	ClassDB::bind_method(D_METHOD("limit", "l", "r", "ceiling", "release_k"), &AKNative::limit);
	ClassDB::bind_method(D_METHOD("lufs", "l", "r", "sr"), &AKNative::lufs);
	ClassDB::bind_method(D_METHOD("fm", "n", "sr", "freq", "ratio", "index", "index_end", "index_decay_s", "ratio2", "index2"), &AKNative::fm);
	ClassDB::bind_method(D_METHOD("duck", "l", "r", "src_l", "src_r", "sr", "depth_db", "full", "attack_s", "release_s"), &AKNative::duck);
	ClassDB::bind_method(D_METHOD("synth_render", "patch", "events", "frames", "sr"), &AKNative::synth_render);
	ClassDB::bind_method(D_METHOD("mix_into", "dst_l", "dst_r", "src_l", "src_r", "at", "gain"), &AKNative::mix_into);
}

String AKNative::version() {
	return "aknative 0.3";
}

static PackedFloat32Array make(int n) {
	PackedFloat32Array a;
	a.resize(n < 0 ? 0 : n);
	return a;
}

// ------------------------------------------------------------------ AKDsp

PackedFloat32Array AKNative::glide(int n, int sr, double a, double b, double time_s) {
	PackedFloat32Array out = make(n);
	float *o = out.ptrw();
	double k = std::exp(-1.0 / std::max(1e-6, time_s * sr));
	double v = a - b;
	for (int i = 0; i < n; i++) {
		o[i] = (float)(b + v);
		v *= k;
	}
	return out;
}

PackedFloat32Array AKNative::mul(const PackedFloat32Array &a, const PackedFloat32Array &b) {
	PackedFloat32Array out = a;
	float *o = out.ptrw();
	const float *pb = b.ptr();
	int n = std::min(a.size(), b.size());
	for (int i = 0; i < n; i++) {
		o[i] *= pb[i];
	}
	return out;
}

PackedFloat32Array AKNative::add(const PackedFloat32Array &a, const PackedFloat32Array &b, double gain, int at) {
	PackedFloat32Array out = a;
	int n = b.size();
	if (at + n > out.size()) {
		int old = out.size();
		out.resize(at + n);
		float *o = out.ptrw();
		for (int i = old; i < at + n; i++) {
			o[i] = 0.0f;
		}
	}
	float *o = out.ptrw();
	const float *pb = b.ptr();
	for (int i = std::max(0, -at); i < n; i++) {
		o[at + i] += (float)(pb[i] * gain);
	}
	return out;
}

PackedFloat32Array AKNative::scale(const PackedFloat32Array &a, double gain) {
	PackedFloat32Array out = a;
	float *o = out.ptrw();
	for (int i = 0; i < out.size(); i++) {
		o[i] = (float)(o[i] * gain);
	}
	return out;
}

Array AKNative::mix_into(const PackedFloat32Array &dl, const PackedFloat32Array &dr, const PackedFloat32Array &sl, const PackedFloat32Array &sr_, int at, double gain) {
	PackedFloat32Array ol = dl, orr = dr;
	int n = sl.size();
	if (at + n > ol.size()) {
		int old = ol.size();
		ol.resize(at + n);
		orr.resize(at + n);
		float *a = ol.ptrw();
		float *b = orr.ptrw();
		for (int i = old; i < at + n; i++) {
			a[i] = 0.0f;
			b[i] = 0.0f;
		}
	}
	float *a = ol.ptrw();
	float *b = orr.ptrw();
	const float *x = sl.ptr();
	const float *y = sr_.ptr();
	for (int i = std::max(0, -at); i < n; i++) {
		a[at + i] += (float)(x[i] * gain);
		b[at + i] += (float)(y[i] * gain);
	}
	Array res;
	res.push_back(ol);
	res.push_back(orr);
	return res;
}

// ------------------------------------------------------------------ AKOsc

PackedFloat32Array AKNative::sine(const PackedFloat32Array &freq, int sr, double phase0) {
	int n = freq.size();
	PackedFloat32Array out = make(n);
	float *o = out.ptrw();
	const float *f = freq.ptr();
	double ph = phase0, inv = 1.0 / sr;
	for (int i = 0; i < n; i++) {
		o[i] = (float)std::sin(TAU * ph);
		ph += f[i] * inv;
		ph -= std::floor(ph);
	}
	return out;
}

PackedFloat32Array AKNative::sine_const(int n, double freq, int sr, double phase0) {
	PackedFloat32Array out = make(n);
	float *o = out.ptrw();
	double w = TAU * freq / sr;
	double c = 2.0 * std::cos(w);
	double y2 = std::sin(TAU * phase0 - w);
	double y1 = std::sin(TAU * phase0);
	for (int i = 0; i < n; i++) {
		o[i] = (float)y1;
		double y = c * y1 - y2;
		y2 = y1;
		y1 = y;
	}
	return out;
}

PackedFloat32Array AKNative::saw(const PackedFloat32Array &freq, int sr, double phase0) {
	int n = freq.size();
	PackedFloat32Array out = make(n);
	float *o = out.ptrw();
	const float *f = freq.ptr();
	double ph = phase0, inv = 1.0 / sr;
	for (int i = 0; i < n; i++) {
		double dt = f[i] * inv;
		o[i] = (float)(2.0 * ph - 1.0 - ak::blep(ph, dt));
		ph += dt;
		ph -= std::floor(ph);
	}
	return out;
}

PackedFloat32Array AKNative::square(const PackedFloat32Array &freq, int sr, double width, double phase0) {
	int n = freq.size();
	PackedFloat32Array out = make(n);
	float *o = out.ptrw();
	const float *f = freq.ptr();
	double ph = phase0, inv = 1.0 / sr;
	double w = std::clamp(width, 0.01, 0.99);
	for (int i = 0; i < n; i++) {
		double dt = f[i] * inv;
		double v = ph < w ? 1.0 : -1.0;
		v += ak::blep(ph, dt);
		double p2 = ph - w;
		p2 -= std::floor(p2);
		v -= ak::blep(p2, dt);
		o[i] = (float)v;
		ph += dt;
		ph -= std::floor(ph);
	}
	return out;
}

PackedFloat32Array AKNative::triangle(const PackedFloat32Array &freq, int sr, double phase0) {
	int n = freq.size();
	PackedFloat32Array out = make(n);
	float *o = out.ptrw();
	const float *f = freq.ptr();
	double ph = phase0, inv = 1.0 / sr;
	for (int i = 0; i < n; i++) {
		o[i] = (float)(1.0 - 4.0 * std::fabs(ph - 0.5));
		ph += f[i] * inv;
		ph -= std::floor(ph);
	}
	return out;
}

// ------------------------------------------------------------------ AKEnv

PackedFloat32Array AKNative::env_decay(int n, int sr, double attack_s, double decay_s) {
	PackedFloat32Array out = make(n);
	float *o = out.ptrw();
	int a = std::max(1, (int)std::lround(attack_s * sr));
	double k = std::exp(-1.0 / std::max(1e-6, decay_s * sr));
	double v = 1.0;
	for (int i = 0; i < n; i++) {
		if (i < a) {
			o[i] = (float)(double(i) / a);
		} else {
			o[i] = (float)v;
			v *= k;
		}
	}
	return out;
}

PackedFloat32Array AKNative::env_adsr(int n, int sr, double attack_s, double decay_s, double sustain, double release_s, double gate_s) {
	PackedFloat32Array out = make(n);
	float *o = out.ptrw();
	int a = std::max(1, (int)std::lround(attack_s * sr));
	int d = std::max(1, (int)std::lround(decay_s * sr));
	int g = (int)std::lround(gate_s * sr);
	double k = std::exp(-1.0 / std::max(1e-6, release_s * sr));
	double level = 0.0;
	for (int i = 0; i < n; i++) {
		if (i < g) {
			if (i < a) {
				level = double(i) / a;
			} else if (i < a + d) {
				level = 1.0 - (1.0 - sustain) * double(i - a) / d;
			} else {
				level = sustain;
			}
		} else {
			level *= k;
		}
		o[i] = (float)level;
	}
	return out;
}

// ------------------------------------------------------------------ AKFilter

PackedFloat32Array AKNative::lowpass1(const PackedFloat32Array &x, const PackedFloat32Array &cutoffs, double cutoff, int sr) {
	int n = x.size();
	PackedFloat32Array out = make(n);
	float *o = out.ptrw();
	const float *px = x.ptr();
	double acc = 0.0, w = -TAU / sr;
	if (cutoffs.size() == 0) {
		double a = 1.0 - std::exp(w * cutoff);
		for (int i = 0; i < n; i++) {
			acc += a * (px[i] - acc);
			o[i] = (float)acc;
		}
		return out;
	}
	const float *c = cutoffs.ptr();
	int cn = cutoffs.size();
	for (int i = 0; i < n; i++) {
		double a = 1.0 - std::exp(w * c[i < cn ? i : cn - 1]);
		acc += a * (px[i] - acc);
		o[i] = (float)acc;
	}
	return out;
}

PackedFloat32Array AKNative::svf(const PackedFloat32Array &x, const PackedFloat32Array &cutoffs, double cutoff, double q, int sr, int mode) {
	int n = x.size();
	PackedFloat32Array out = make(n);
	float *o = out.ptrw();
	const float *px = x.ptr();
	ak::SVF f;
	f.set_q(q);
	bool varying = cutoffs.size() > 0;
	const float *c = varying ? cutoffs.ptr() : nullptr;
	int cn = cutoffs.size();
	f.set_cutoff(varying ? 1000.0 : cutoff, sr);
	for (int i = 0; i < n; i++) {
		if (varying) {
			f.set_cutoff(c[i < cn ? i : cn - 1], sr);
		}
		o[i] = (float)f.tick(px[i], mode);
	}
	return out;
}

// ------------------------------------------------------------------ AKDelay

PackedFloat32Array AKNative::karplus(const PackedFloat32Array &init, int n, int sr, double decay_s, double brightness) {
	std::vector<float> buf(init.ptr(), init.ptr() + init.size());
	int period = (int)buf.size();
	PackedFloat32Array out = make(n);
	if (period < 2) {
		return out;
	}
	float *o = out.ptrw();
	double g = std::exp(-double(period) / std::max(1e-4, decay_s * sr));
	double b = std::clamp(brightness, 0.0, 1.0);
	int idx = 0;
	for (int i = 0; i < n; i++) {
		double cur = buf[idx];
		double nxt = buf[(idx + 1) % period];
		o[i] = (float)cur;
		double avg = 0.5 * (cur + nxt);
		buf[idx] = (float)((avg + (cur - avg) * (b * 0.5)) * g);
		idx = (idx + 1) % period;
	}
	return out;
}

// ------------------------------------------------------------------ AKReverb

Array AKNative::reverb_wet(const PackedFloat32Array &l, const PackedFloat32Array &r, int sr, double room, double damp, double width, int tail, bool small) {
	int n0 = l.size();
	int n = n0 + std::max(0, tail);
	ak::Freeverb fv;
	fv.setup(sr, room, damp, width, small);
	PackedFloat32Array ol = make(n), orr = make(n);
	float *a = ol.ptrw();
	float *b = orr.ptrw();
	const float *pl = l.ptr();
	const float *pr = r.ptr();
	for (int i = 0; i < n; i++) {
		float il = i < n0 ? pl[i] : 0.0f;
		float ir = i < n0 ? pr[i] : 0.0f;
		fv.process(il, ir, a[i], b[i]);
	}
	Array res;
	res.push_back(ol);
	res.push_back(orr);
	return res;
}

// ------------------------------------------------------------------ AKDynamics

Array AKNative::duck(const PackedFloat32Array &l, const PackedFloat32Array &r, const PackedFloat32Array &sl, const PackedFloat32Array &sr_, int sr, double depth_db, double full, double attack_s, double release_s) {
	PackedFloat32Array ol = l, orr = r;
	float *a = ol.ptrw();
	float *b = orr.ptrw();
	const float *pl = sl.ptr();
	const float *pr = sr_.ptr();
	const int ns = std::min(sl.size(), sr_.size());
	ak::Ducker d;
	d.setup(sr, depth_db, full, attack_s, release_s);
	for (int i = 0; i < ol.size(); i++) {
		const double x = i < ns ? std::max(std::fabs((double)pl[i]), std::fabs((double)pr[i])) : 0.0;
		const double g = d.tick(x);
		a[i] = (float)(a[i] * g);
		b[i] = (float)(b[i] * g);
	}
	Array res;
	res.push_back(ol);
	res.push_back(orr);
	return res;
}

Array AKNative::limit(const PackedFloat32Array &l, const PackedFloat32Array &r, double ceiling, double release_k) {
	PackedFloat32Array ol = l, orr = r;
	float *a = ol.ptrw();
	float *b = orr.ptrw();
	double g = 1.0;
	for (int i = 0; i < ol.size(); i++) {
		double p = std::max(std::fabs((double)a[i]), std::fabs((double)b[i]));
		double need = p > ceiling ? ceiling / p : 1.0;
		if (need < g) {
			g = need;
		} else {
			g = need - (need - g) * release_k;
		}
		a[i] = (float)(a[i] * g);
		b[i] = (float)(b[i] * g);
	}
	Array res;
	res.push_back(ol);
	res.push_back(orr);
	return res;
}

static void k_weight(const float *x, int n, double sr, std::vector<double> &out) {
	auto biquad = [](const std::vector<double> &in, std::vector<double> &o, double b0, double b1, double b2, double a1, double a2) {
		double x1 = 0, x2 = 0, y1 = 0, y2 = 0;
		for (size_t i = 0; i < in.size(); i++) {
			double v = in[i];
			double y = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
			x2 = x1;
			x1 = v;
			y2 = y1;
			y1 = y;
			o[i] = y;
		}
	};
	std::vector<double> in(x, x + n), mid(n);
	out.assign(n, 0.0);
	double f0 = 1681.974450955533, gain = 3.999843853973347, q = 0.7071752369554196;
	double k = std::tan(ak::PI * f0 / sr);
	double vh = std::pow(10.0, gain / 20.0);
	double vb = std::pow(vh, 0.4996667741545416);
	double a0 = 1.0 + k / q + k * k;
	biquad(in, mid, (vh + vb * k / q + k * k) / a0, 2.0 * (k * k - vh) / a0, (vh - vb * k / q + k * k) / a0,
			2.0 * (k * k - 1.0) / a0, (1.0 - k / q + k * k) / a0);
	f0 = 38.13547087602444;
	q = 0.5003270373238773;
	k = std::tan(ak::PI * f0 / sr);
	a0 = 1.0 + k / q + k * k;
	biquad(mid, out, 1.0, -2.0, 1.0, 2.0 * (k * k - 1.0) / a0, (1.0 - k / q + k * k) / a0);
}

double AKNative::lufs(const PackedFloat32Array &l, const PackedFloat32Array &r, int sr) {
	int n = l.size();
	if (n == 0) {
		return -INFINITY;
	}
	std::vector<double> kl, kr;
	k_weight(l.ptr(), n, sr, kl);
	k_weight(r.ptr(), n, sr, kr);
	int block = (int)(0.4 * sr), step = (int)(0.1 * sr);
	auto to_l = [](double z) { return -0.691 + 10.0 * std::log10(std::max(z, 1e-12)); };
	if (n < block) {
		double s = 0;
		for (int i = 0; i < n; i++) {
			s += kl[i] * kl[i] + kr[i] * kr[i];
		}
		return to_l(s / n);
	}
	std::vector<double> cum(n + 1, 0.0);
	for (int i = 0; i < n; i++) {
		cum[i + 1] = cum[i] + kl[i] * kl[i] + kr[i] * kr[i];
	}
	std::vector<double> zs;
	for (int i0 = 0; i0 + block <= n; i0 += step) {
		double z = (cum[i0 + block] - cum[i0]) / block;
		if (to_l(z) > -70.0) {
			zs.push_back(z);
		}
	}
	if (zs.empty()) {
		return -INFINITY;
	}
	double mean = 0;
	for (double z : zs) {
		mean += z;
	}
	mean /= zs.size();
	double rel = to_l(mean) - 10.0;
	double kept = 0;
	int count = 0;
	for (double z : zs) {
		if (to_l(z) > rel) {
			kept += z;
			count++;
		}
	}
	return to_l(count > 0 ? kept / count : mean);
}

// ------------------------------------------------------------------ voices

PackedFloat32Array AKNative::fm(int n, int sr, double freq, double ratio, double index, double index_end, double index_decay_s, double ratio2, double index2) {
	PackedFloat32Array out = make(n);
	float *o = out.ptrw();
	double fc = freq / sr, fmod = freq * ratio / sr, f2 = freq * ratio2 / sr;
	bool use2 = ratio2 > 0.0;
	double k = std::exp(-1.0 / std::max(1.0, index_decay_s * sr));
	double di = index - index_end;
	double pc = 0, pm = 0, p2 = 0;
	for (int i = 0; i < n; i++) {
		double m2 = use2 ? std::sin(TAU * p2) * index2 : 0.0;
		double mod = std::sin(TAU * pm + m2);
		o[i] = (float)std::sin(TAU * pc + (index_end + di) * mod);
		di *= k;
		pc += fc;
		pm += fmod;
		p2 += f2;
		pc -= std::floor(pc);
		pm -= std::floor(pm);
		p2 -= std::floor(p2);
	}
	return out;
}

// ------------------------------------------------------------------ AKSynth

Array AKNative::synth_render(const Dictionary &patch, const Array &events, int frames, int sr) {
	ak::SynthEngine eng;
	eng.sr = sr;
	eng.set_patch(synth_patch_from(patch));
	for (int i = 0; i < events.size(); i++) {
		Array e = events[i];
		eng.queue((int64_t)e[0], (int)e[1], (double)e[2], e.size() > 3 ? (double)e[3] : 0.0);
	}
	PackedFloat32Array l = make(frames);
	PackedFloat32Array r = make(frames);
	l.fill(0.0f);
	r.fill(0.0f);
	eng.render(l.ptrw(), r.ptrw(), std::max(0, frames));
	Array res;
	res.push_back(l);
	res.push_back(r);
	return res;
}
