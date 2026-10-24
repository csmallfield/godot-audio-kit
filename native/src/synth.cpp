// SPDX-License-Identifier: Apache-2.0
// See synth.h. Every function here follows its namesake in synth_core.gd.
#include "synth.h"

#include <algorithm>
#include <cmath>

namespace ak {

namespace {
enum { ATTACK, DECAY, SUSTAIN, RELEASE, IDLE };
enum { SRC_ENV1, SRC_ENV2, SRC_ENV3, SRC_LFO1, SRC_LFO2, SRC_VEL, SRC_KEY, SRC_MOD, SRC_TOUCH, SRC_RANDOM, SRC_BEND };
enum { D_PITCH, D_CUTOFF, D_Q, D_AMP, D_PAN, D_OPITCH, D_OLEVEL, D_OFM, D_OWIDTH, D_OPOS };
enum { SH_SINE, SH_TRI, SH_SAW, SH_SQUARE, SH_PULSE, SH_NOISE, SH_MORPH };
constexpr double SILENT = 1e-5;

inline double clampd(double x, double lo, double hi) { return x < lo ? lo : (x > hi ? hi : x); }

inline double shape_at(int shape, double ph, double dt, double width) {
	switch (shape) {
		case SH_SINE: return std::sin(TAU * ph);
		case SH_TRI: return 1.0 - 4.0 * std::fabs(ph - 0.5);
		case SH_SAW: return 2.0 * ph - 1.0 - blep(ph, dt);
		default: {
			double v = ph < width ? 1.0 : -1.0;
			v += blep(ph, dt);
			double p2 = ph - width;
			p2 -= std::floor(p2);
			return v - blep(p2, dt);
		}
	}
}
} // namespace

// ------------------------------------------------------------------ engine

void SynthEngine::set_patch(const SynthPatch &patch) {
	p = patch;
	for (int k = 0; k < 3; k++) {
		const SynthPatch::Env &e = p.env[k];
		env_a[k] = (int64_t)std::llround(e.a * sr);
		env_d[k] = std::max<int64_t>(1, (int64_t)std::llround(e.d * sr));
		env_s[k] = e.s;
		env_kd[k] = std::exp(-1.0 / (e.d * sr));
		env_kr[k] = std::exp(-1.0 / (e.r * sr));
		env_exp[k] = e.exp;
	}
	for (int k = 0; k < 2; k++) {
		lfo_shape[k] = p.lfo[k].shape;
		lfo_inc[k] = p.lfo[k].rate_hz / sr;
		lfo_delay[k] = p.lfo[k].delay_s * sr;
	}
	const int u = p.unison;
	for (int i = 0; i < SynthPatch::MAX_U; i++) {
		double spread = u == 1 ? 0.0 : (double(i) / (u - 1) - 0.5) * 2.0;
		ratio[i] = std::pow(2.0, spread * p.detune_cents / 1200.0);
	}
	inv_su = 1.0 / std::sqrt(double(u));
	kg = p.glide_s > 0.0 ? std::exp(-double(CONTROL) / (p.glide_s * sr)) : 0.0;
}

void SynthEngine::queue(int64_t at, int type, double a, double b) {
	// Drop what's been applied before inserting, so the vector stays short.
	if (ev_head > 0) {
		events.erase(events.begin(), events.begin() + ev_head);
		ev_head = 0;
	}
	Event e{ at, seq++, type, a, b };
	size_t i = events.size();
	while (i > 0 && events[i - 1].frame > at) {
		i--;
	}
	events.insert(events.begin() + i, e);
}

int SynthEngine::voice_count() const {
	int n = 0;
	for (const SynthVoice &v : voices) {
		n += v.active ? 1 : 0;
	}
	return n;
}

void SynthEngine::render(float *out_l, float *out_r, int n) {
	for (int i = 0; i < n; i++) {
		while (ev_head < events.size() && events[ev_head].frame <= frame) {
			const Event e = events[ev_head++];
			apply(e.type, e.a, e.b);
		}
		double sl = 0.0, sr_ = 0.0;
		for (SynthVoice &v : voices) {
			if (v.active) {
				double y = v.tick(*this);
				sl += y * v.gl;
				sr_ += y * v.gr;
			}
		}
		out_l[i] += (float)sl;
		out_r[i] += (float)sr_;
		frame++;
	}
	if (ev_head == events.size()) {
		events.clear();
		ev_head = 0;
	}
}

void SynthEngine::apply(int type, double a, double b) {
	switch (type) {
		case E_ON: on(a, b); break;
		case E_OFF: off(a); break;
		case E_BEND: bend = clampd(a, -1.0, 1.0); break;
		case E_MOD: mod_wheel = clampd(a, 0.0, 1.0); break;
		case E_TOUCH: aftertouch = clampd(a, 0.0, 1.0); break;
		case E_ALL_OFF:
			held_note.clear();
			held_vel.clear();
			for (SynthVoice &v : voices) {
				if (v.active && v.gated) {
					v.release();
				}
			}
			break;
		case E_PANIC:
			held_note.clear();
			held_vel.clear();
			for (SynthVoice &v : voices) {
				v.active = false;
			}
			break;
	}
}

void SynthEngine::on(double note, double vel) {
	if (p.mode != 0) {
		if (voices.empty()) {
			voices.emplace_back();
		}
		SynthVoice &v = voices[0];
		held_note.push_back(note);
		held_vel.push_back(vel);
		if (v.active && v.gated) {
			v.target = note;
			v.vel = vel;
			if (p.mode == 1) {
				v.retrigger();
			}
			last_note = note;
			return;
		}
		double from = v.active ? v.cur : last_note;
		v.start(*this, note, vel, from);
		last_note = note;
		return;
	}
	for (SynthVoice &v : voices) {
		if (v.active && v.gated && v.note == note) {
			v.release();
		}
	}
	int live = 0;
	int free_i = -1;
	for (int i = 0; i < (int)voices.size(); i++) {
		if (voices[i].active) {
			live++;
		} else if (free_i < 0) {
			free_i = i;
		}
	}
	SynthVoice *v;
	if (live >= p.poly || (free_i < 0 && (int)voices.size() >= p.poly)) {
		v = &steal();
	} else if (free_i < 0) {
		voices.emplace_back();
		v = &voices.back();
	} else {
		v = &voices[free_i];
	}
	v->start(*this, note, vel, last_note);
	last_note = note;
}

void SynthEngine::off(double note) {
	if (p.mode != 0) {
		double top = held_note.empty() ? -1.0 : held_note.back();
		for (int i = (int)held_note.size() - 1; i >= 0; i--) {
			if (held_note[i] == note) {
				held_note.erase(held_note.begin() + i);
				held_vel.erase(held_vel.begin() + i);
			}
		}
		if (voices.empty() || !voices[0].active) {
			return;
		}
		SynthVoice &v = voices[0];
		if (held_note.empty()) {
			v.release();
		} else if (note == top) {
			v.target = held_note.back();
			last_note = v.target;
		}
		return;
	}
	for (SynthVoice &v : voices) {
		if (v.active && v.gated && v.note == note) {
			v.release();
		}
	}
}

SynthVoice &SynthEngine::steal() {
	SynthVoice *best = nullptr;
	for (SynthVoice &v : voices) {
		if (v.active && !v.gated && (best == nullptr || v.serial < best->serial)) {
			best = &v;
		}
	}
	if (best) {
		return *best;
	}
	for (SynthVoice &v : voices) {
		if (best == nullptr || v.serial < best->serial) {
			best = &v;
		}
	}
	return *best;
}

// ------------------------------------------------------------------ voice

void SynthVoice::start(SynthEngine &e, double p_note, double p_vel, double from_note) {
	const SynthPatch &c = e.p;
	active = true;
	gated = true;
	serial = e.next_serial();
	note = p_note;
	target = p_note;
	cur = (e.kg > 0.0 && from_note >= 0.0) ? from_note : p_note;
	vel = p_vel;
	// As GDScript's wrapping 64-bit ints, then the low 32 bits.
	const uint64_t s = ((uint64_t)c.seed * 73856093ULL) ^ ((uint64_t)serial * 19349663ULL) ^ 83492791ULL;
	rng = (uint32_t)(s & 0xFFFFFFFFULL);
	if (rng == 0) {
		rng = 0x9E3779B9u;
	}
	rnd = white01() * 2.0 - 1.0;
	for (int i = 0; i < MAX_OSC * MAX_U; i++) {
		phase[i] = 0.0;
		raw[i] = 0.0;
	}
	for (int j = 0; j < MAX_OSC; j++) {
		last_semi[j] = -1e9;
	}
	if (c.unison > 1) {
		for (int j = 0; j < c.n_osc; j++) {
			for (int k = 0; k < c.unison; k++) {
				phase[j * MAX_U + k] = white01();
			}
		}
	}
	for (int k = 0; k < 2; k++) {
		lfo_ph[k] = 0.0;
		lfo_sh[k] = e.lfo_shape[k] == 4 ? white01() * 2.0 - 1.0 : 0.0;
	}
	age = 0;
	for (int k = 0; k < 3; k++) {
		stage[k] = ATTACK;
		t[k] = 0;
		level[k] = 0.0;
		start_level[k] = 0.0;
		ev[k] = 1.0;
	}
	ic1[0] = ic1[1] = ic2[0] = ic2[1] = 0.0;
	last_c = -1.0;
	last_q = -1.0;
}

void SynthVoice::retrigger() {
	for (int k = 0; k < 3; k++) {
		stage[k] = ATTACK;
		t[k] = 0;
		start_level[k] = level[k];
		ev[k] = 1.0;
	}
	gated = true;
}

void SynthVoice::release() {
	gated = false;
	for (int k = 0; k < 3; k++) {
		stage[k] = RELEASE;
	}
}

double SynthVoice::env_tick(const SynthEngine &e, int k) {
	if (stage[k] == ATTACK) {
		if (t[k] < e.env_a[k]) {
			level[k] = start_level[k] + (1.0 - start_level[k]) * double(t[k]) / e.env_a[k];
			t[k]++;
			return level[k];
		}
		stage[k] = DECAY;
		t[k] = 0;
		ev[k] = 1.0;
	}
	if (stage[k] == DECAY) {
		const double s = e.env_s[k];
		if (e.env_exp[k]) {
			level[k] = s + (1.0 - s) * ev[k];
			ev[k] *= e.env_kd[k];
			return level[k];
		}
		if (t[k] < e.env_d[k]) {
			level[k] = 1.0 - (1.0 - s) * double(t[k]) / e.env_d[k];
			t[k]++;
			return level[k];
		}
		stage[k] = SUSTAIN;
	}
	if (stage[k] == SUSTAIN) {
		level[k] = e.env_s[k];
	} else if (stage[k] == RELEASE) {
		level[k] *= e.env_kr[k];
	}
	return level[k];
}

double SynthVoice::lfo_tick(const SynthEngine &e, int k) {
	double ph = lfo_ph[k];
	const int shape = e.lfo_shape[k];
	double v;
	switch (shape) {
		case 0: v = std::sin(TAU * ph); break;
		case 1: v = 1.0 - 4.0 * std::fabs(ph - 0.5); break;
		case 2: v = 2.0 * ph - 1.0; break;
		case 3: v = ph < 0.5 ? 1.0 : -1.0; break;
		default: v = lfo_sh[k]; break;
	}
	const double d = e.lfo_delay[k];
	if (d > 0.0 && age < d) {
		v *= double(age) / d;
	}
	ph += e.lfo_inc[k] * CONTROL;
	if (ph >= 1.0) {
		ph -= std::floor(ph);
		if (shape == 4) {
			lfo_sh[k] = white01() * 2.0 - 1.0;
		}
	}
	lfo_ph[k] = ph;
	return v;
}

void SynthVoice::control(SynthEngine &e, double e0, double e1, double e2) {
	const SynthPatch &c = e.p;
	src[SRC_ENV1] = e0;
	src[SRC_ENV2] = e1;
	src[SRC_ENV3] = e2;
	src[SRC_LFO1] = lfo_tick(e, 0);
	src[SRC_LFO2] = lfo_tick(e, 1);
	src[SRC_VEL] = vel;
	src[SRC_KEY] = (target - 60.0) / 12.0;
	src[SRC_MOD] = e.mod_wheel;
	src[SRC_TOUCH] = e.aftertouch;
	src[SRC_RANDOM] = rnd;
	src[SRC_BEND] = e.bend;
	double m_pitch = 0.0, m_cut = 0.0, m_q = 0.0, m_amp = 0.0, m_pan = 0.0;
	const int no = c.n_osc;
	for (int i = 0; i < 5 * MAX_OSC; i++) {
		mo[i] = 0.0;
	}
	for (int r = 0; r < c.n_mods; r++) {
		const SynthPatch::Mod &row = c.mods[r];
		const double x = row.amount * src[row.src];
		switch (row.dst) {
			case D_PITCH: m_pitch += x; break;
			case D_CUTOFF: m_cut += x; break;
			case D_Q: m_q += x; break;
			case D_AMP: m_amp += x; break;
			case D_PAN: m_pan += x; break;
			default: {
				const int slot = (row.dst - D_OPITCH) * MAX_OSC;
				if (row.osc < 0) {
					for (int j = 0; j < no; j++) {
						mo[slot + j] += x;
					}
				} else if (row.osc < no) {
					mo[slot + row.osc] += x;
				}
			}
		}
	}
	const double semi = cur + e.bend * c.bend_range + m_pitch;
	cur = target + (cur - target) * e.kg;
	for (int j = 0; j < no; j++) {
		const SynthPatch::Osc &o = c.osc[j];
		const double s = semi + o.semis + mo[j];
		if (s != last_semi[j]) {
			last_semi[j] = s;
			freq[j] = 440.0 * std::pow(2.0, (s - 69.0) / 12.0);
		}
		o_level[j] = o.level + mo[MAX_OSC + j];
		o_idx[j] = o.fm_index + mo[2 * MAX_OSC + j];
		o_width[j] = clampd(o.width + mo[3 * MAX_OSC + j], 0.01, 0.99);
		o_pos[j] = clampd(o.position + mo[4 * MAX_OSC + j], 0.0, 1.0);
		for (int k = 0; k < c.unison; k++) {
			dt[j * MAX_U + k] = freq[j] * e.ratio[k] / e.sr;
		}
	}
	if (c.filter_type > 0) {
		double cut = c.cutoff_hz;
		if (m_cut != 0.0) {
			cut *= std::pow(2.0, m_cut);
		}
		double q = c.q;
		if (m_q != 0.0) {
			q *= std::pow(2.0, m_q);
		}
		if (cut != last_c || q != last_q) {
			last_c = cut;
			last_q = q;
			fk = 1.0 / std::max(0.05, q);
			const double g = std::tan(PI * clampd(cut, 10.0, 0.49 * e.sr) / e.sr);
			a1 = 1.0 / (1.0 + g * (g + fk));
			a2 = g * a1;
			a3 = g * a2;
		}
	}
	amp_mod = std::max(0.0, 1.0 + m_amp);
	const double pp = clampd(c.pan + m_pan, -1.0, 1.0);
	if (pp == 0.0) {
		gl = 1.0;
		gr = 1.0;
	} else {
		const double ang = (pp + 1.0) * PI * 0.25;
		gl = std::cos(ang) * SQRT2;
		gr = std::sin(ang) * SQRT2;
	}
}

double SynthVoice::tick(SynthEngine &e) {
	const SynthPatch &c = e.p;
	const double e0 = env_tick(e, 0);
	const double e1 = env_tick(e, 1);
	const double e2 = env_tick(e, 2);
	if (age % CONTROL == 0) {
		control(e, e0, e1, e2);
	}
	age++;
	const int no = c.n_osc;
	const int u = c.unison;
	double mix = 0.0;
	for (int j = no - 1; j >= 0; j--) {
		const SynthPatch::Osc &o = c.osc[j];
		double acc = 0.0;
		if (o.shape == SH_NOISE) {
			acc = white01() * 2.0 - 1.0;
			for (int k = 0; k < u; k++) {
				raw[j * MAX_U + k] = acc;
			}
		} else {
			const double idx = o_idx[j];
			const double width = o_width[j];
			const double pos = o_pos[j];
			for (int k = 0; k < u; k++) {
				const double d = dt[j * MAX_U + k];
				double ph = phase[j * MAX_U + k];
				const double pm = o.fm_from >= 0 ? idx * raw[o.fm_from * MAX_U + k] : 0.0;
				double x;
				if (o.shape == SH_SINE) {
					x = std::sin(TAU * ph + pm);
				} else {
					double q = ph;
					if (pm != 0.0) {
						q = ph + pm / TAU;
						q -= std::floor(q);
					}
					if (o.shape == SH_MORPH) {
						const double p3 = pos * 3.0;
						const int a = std::min(2, (int)std::floor(p3));
						const double w = p3 - a;
						x = shape_at(a, q, d, 0.5);
						if (w > 0.0) {
							x = x * (1.0 - w) + shape_at(a + 1, q, d, 0.5) * w;
						}
					} else {
						x = shape_at(o.shape, q, d, o.shape == SH_PULSE ? width : 0.5);
					}
				}
				raw[j * MAX_U + k] = x;
				ph += d;
				if (ph >= 1.0) {
					ph -= std::floor(ph);
				}
				phase[j * MAX_U + k] = ph;
				acc += x;
			}
			acc *= e.inv_su;
		}
		mix += o_level[j] * acc;
	}
	double y = mix;
	const int ft = c.filter_type;
	if (ft > 0) {
		for (int st = 0; st < c.stages; st++) {
			const double v3 = y - ic2[st];
			const double v1 = a1 * ic1[st] + a2 * v3;
			const double v2 = ic2[st] + a2 * ic1[st] + a3 * v3;
			ic1[st] = 2.0 * v1 - ic1[st];
			ic2[st] = 2.0 * v2 - ic2[st];
			switch (ft) {
				case 1: y = v2; break;
				case 2: y = y - fk * v1 - v2; break;
				case 3: y = v1; break;
				default: y = y - fk * v1; break;
			}
		}
	}
	y *= e0 * (1.0 - c.vel_sens * (1.0 - vel)) * amp_mod * c.gain;
	if (stage[0] == RELEASE && level[0] < SILENT) {
		active = false;
	}
	return y;
}

} // namespace ak
