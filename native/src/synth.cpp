// SPDX-License-Identifier: Apache-2.0
// See synth.h. Every function here follows its namesake in synth_core.gd.
#include "synth.h"

#include <algorithm>
#include <cmath>

namespace ak {

namespace {
enum { ATTACK, DECAY, SUSTAIN, RELEASE, IDLE };
enum { SRC_ENV1, SRC_ENV2, SRC_ENV3, SRC_LFO1, SRC_LFO2, SRC_VEL, SRC_KEY, SRC_MOD, SRC_TOUCH, SRC_RANDOM, SRC_BEND };
enum { D_PITCH, D_CUTOFF, D_Q, D_AMP, D_PAN, D_OPITCH, D_OLEVEL, D_OFM, D_OWIDTH, D_OPOS, D_LFO1R, D_LFO2R };
enum { SH_SINE, SH_TRI, SH_SAW, SH_SQUARE, SH_PULSE, SH_NOISE, SH_MORPH, SH_TABLE };
enum { F_OFF, F_LOW, F_HIGH, F_BAND, F_NOTCH, F_LADDER };
constexpr int WT_LEVELS = 19;

inline int level_limit(int lv) { return (int)std::floor(std::pow(2.0, lv * 0.5)); }

inline double table_read(const SynthPatch::Table &t, double pos, int lv, double ph, int zone) {
	const int n = t.size;
	lv = std::min(std::max(lv, t.lv0), t.lv0 + t.levels - 1) - t.lv0;
	const double fp = pos * (t.frames - 1);
	const int fz = std::min(t.frames - 1, (int)std::floor(fp));
	const int f0 = fz + zone * t.frames;
	const double x = ph * n;
	int i0 = (int)x;
	const double fr = x - i0;
	const int i1 = (i0 + 1) % n;
	i0 = i0 % n;
	const size_t b0 = (size_t)(f0 * t.levels + lv) * n;
	double v = t.data[b0 + i0] * (1.0 - fr) + t.data[b0 + i1] * fr;
	const double ff = fp - fz;
	if (ff > 0.0 && fz + 1 < t.frames) {
		const size_t b1 = (size_t)((f0 + 1) * t.levels + lv) * n;
		const double v1 = t.data[b1 + i0] * (1.0 - fr) + t.data[b1 + i1] * fr;
		v = v * (1.0 - ff) + v1 * ff;
	}
	return v;
}
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

// Two effects with the same settings (their state may differ).
static bool same_fx(const Fx &a, const Fx &b) {
	return a.type == b.type && a.rate_hz == b.rate_hz && a.depth_ms == b.depth_ms && a.delay_ms == b.delay_ms && a.feedback == b.feedback &&
			a.mix == b.mix && a.spread == b.spread && a.voices == b.voices && a.stages == b.stages && a.center_hz == b.center_hz &&
			a.range_oct == b.range_oct && a.depth == b.depth && a.low_db == b.low_db && a.low_hz == b.low_hz && a.mid_db == b.mid_db &&
			a.mid_hz == b.mid_hz && a.mid_q == b.mid_q && a.high_db == b.high_db && a.high_hz == b.high_hz && a.threshold_db == b.threshold_db &&
			a.ratio == b.ratio && a.attack_s == b.attack_s && a.release_s == b.release_s && a.knee_db == b.knee_db && a.makeup_db == b.makeup_db &&
			a.drive_db == b.drive_db && a.tone_hz == b.tone_hz && a.asymmetry == b.asymmetry && a.output_db == b.output_db &&
			a.semitones == b.semitones && a.window_ms == b.window_ms && a.freq_hz == b.freq_hz && a.jitter == b.jitter && a.bits == b.bits &&
			a.hold == b.hold && a.time_ms == b.time_ms && a.damp_hz == b.damp_hz && a.room == b.room && a.damp == b.damp && a.width == b.width;
}

void SynthEngine::set_patch(const SynthPatch &patch) {
	// Effects keep running (no click) when a patch edit leaves them as they were.
	bool keep = patch.effects.size() == fx.fx.size();
	for (size_t i = 0; keep && i < fx.fx.size(); i++) {
		keep = same_fx(patch.effects[i], fx.fx[i]);
	}
	if (!keep) {
		fx.fx = patch.effects;
		fx.setup(sr);
	}
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
		lfo_width[k] = p.lfo[k].width;
		lfo_delay[k] = p.lfo[k].delay_s * sr;
	}
	const int u = p.unison;
	for (int i = 0; i < SynthPatch::MAX_U; i++) {
		double spread = u == 1 ? 0.0 : (double(i) / (u - 1) - 0.5) * 2.0;
		ratio[i] = std::pow(2.0, spread * p.detune_cents / 1200.0);
	}
	double power = 0.0;
	for (int i = 0; i < SynthPatch::MAX_U; i++) {
		const bool mid = std::abs(double(i) - (u - 1) * 0.5) <= 0.5;
		uw[i] = mid || i >= u ? 1.0 : p.unison_level;
		if (i < u) {
			power += uw[i] * uw[i];
		}
	}
	inv_su = 1.0 / std::sqrt(power);
	stereo = p.spread > 0.0;
	for (int i = 0; i < SynthPatch::MAX_U; i++) {
		const double pp = u == 1 ? 0.0 : p.spread * (double(i) / (u - 1) * 2.0 - 1.0);
		const double ang = (pp + 1.0) * PI * 0.25;
		uwl[i] = std::cos(ang) * SQRT2 * uw[i];
		uwr[i] = std::sin(ang) * SQRT2 * uw[i];
	}
	for (int j = 0; j < SynthPatch::MAX_OSC; j++) {
		const double op = j < p.n_osc ? p.osc[j].pan : 0.0;
		stereo = stereo || op != 0.0;
		const double ang = (op + 1.0) * PI * 0.25;
		opl[j] = op == 0.0 ? 1.0 : std::cos(ang) * SQRT2;
		opr[j] = op == 0.0 ? 1.0 : std::sin(ang) * SQRT2;
	}
	bypass = false;
	for (int j = 0; j < p.n_osc; j++) {
		bypass = bypass || !p.osc[j].filtered;
	}
	kg = p.glide_s > 0.0 ? std::exp(-double(CONTROL) / (p.glide_s * sr)) : 0.0;
	kill_k = std::exp(-1.0 / (STEAL_FADE_S * sr));
	vel_k = 1.0 - std::exp(-1.0 / (VEL_GLIDE_S * sr));
	ctl_k = 1.0 - std::exp(-double(CONTROL) / (CTL_GLIDE_S * sr));
}

void SynthEngine::queue(int64_t at, int type, double a, double b) {
	// Drop what's been applied before inserting, so the vector stays short.
	if (ev_head > 0) {
		events.erase(events.begin(), events.begin() + std::min(ev_head, events.size()));
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
				sr_ += (stereo ? v.yr : y) * v.gr;
			}
		}
		if (!fx.empty()) {
			fx.tick(sl, sr_);
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
			sustain = false;
			for (SynthVoice &v : voices) {
				if (v.active && v.gated) {
					v.release();
				}
			}
			break;
		case E_SUSTAIN:
			sustain = a >= 0.5;
			if (!sustain) {
				for (SynthVoice &v : voices) {
					if (v.active && v.pedal) {
						v.release();
					}
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
			v.pedal = false;
			if (p.mode == 1) {
				v.retrigger();
			}
			last_note = note;
			return;
		}
		if (v.active && !v.killing) {
			// Still ringing out: take the voice from where it is (envelopes
			// rise from their level, phases and filters carry on). Starting
			// it afresh would cut the tail in one sample: a click.
			v.target = note;
			v.vel = vel;
			v.pedal = false;
			v.retrigger();
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
	// Past the polyphony, the oldest voice fades out over a few ms (a stolen
	// voice doesn't click) while the new note starts in a free slot.
	int live = 0;
	for (const SynthVoice &w : voices) {
		if (w.active && !w.killing) {
			live++;
		}
	}
	int victim = -1;
	if (live >= p.poly) {
		victim = steal();
		voices[victim].kill();
	}
	int free_i = -1;
	for (int i = 0; i < (int)voices.size(); i++) {
		if (!voices[i].active) {
			free_i = i;
			break;
		}
	}
	SynthVoice *v;
	if (free_i >= 0) {
		v = &voices[free_i];
	} else if ((int)voices.size() < 2 * p.poly) {
		voices.emplace_back();
		v = &voices.back();
	} else {
		v = &voices[victim >= 0 ? victim : steal()];
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
			if (sustain) {
				v.pedal = true;
			} else {
				v.release();
			}
		} else if (note == top) {
			v.target = held_note.back();
			last_note = v.target;
		}
		return;
	}
	for (SynthVoice &v : voices) {
		if (v.active && v.gated && v.note == note) {
			if (sustain) {
				v.pedal = true;
			} else {
				v.release();
			}
		}
	}
}

int SynthEngine::steal() {
	int best = -1;
	for (int i = 0; i < (int)voices.size(); i++) {
		const SynthVoice &v = voices[i];
		if (v.active && !v.killing && !v.gated && (best < 0 || v.serial < voices[best].serial)) {
			best = i;
		}
	}
	if (best >= 0) {
		return best;
	}
	for (int i = 0; i < (int)voices.size(); i++) {
		const SynthVoice &v = voices[i];
		if (v.active && !v.killing && (best < 0 || v.serial < voices[best].serial)) {
			best = i;
		}
	}
	return best < 0 ? 0 : best;
}

// ------------------------------------------------------------------ voice

void SynthVoice::start(SynthEngine &e, double p_note, double p_vel, double from_note) {
	const SynthPatch &c = e.p;
	active = true;
	gated = true;
	pedal = false;
	killing = false;
	serial = e.next_serial();
	note = p_note;
	target = p_note;
	cur = (e.kg > 0.0 && from_note >= 0.0) ? from_note : p_note;
	vel = p_vel;
	gvel = p_vel;
	gmod = e.mod_wheel;
	gtouch = e.aftertouch;
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
		lfo_oct[k] = 0.0;
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
	ic1r[0] = ic1r[1] = ic2r[0] = ic2r[1] = 0.0;
	for (int i = 0; i < 8; i++) {
		lad[i] = 0.0;
	}
	for (int i = 0; i < MAX_OSC * MAX_U; i++) {
		wrap_t[i] = -1.0;
	}
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

void SynthVoice::kill() {
	release();
	killing = true;
}

void SynthVoice::release() {
	gated = false;
	pedal = false;
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
		level[k] *= killing ? e.kill_k : e.env_kr[k];
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
		case 3: v = ph < e.lfo_width[k] ? 1.0 : -1.0; break;
		default: v = lfo_sh[k]; break;
	}
	const double d = e.lfo_delay[k];
	if (d > 0.0 && age < d) {
		v *= double(age) / d;
	}
	ph += e.lfo_inc[k] * CONTROL * (lfo_oct[k] == 0.0 ? 1.0 : std::pow(2.0, lfo_oct[k]));
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
	src[SRC_VEL] = gvel;
	src[SRC_KEY] = (target - 60.0) / 12.0;
	gmod += (e.mod_wheel - gmod) * e.ctl_k;
	gtouch += (e.aftertouch - gtouch) * e.ctl_k;
	src[SRC_MOD] = gmod;
	src[SRC_TOUCH] = gtouch;
	src[SRC_RANDOM] = rnd;
	src[SRC_BEND] = e.bend;
	double m_pitch = 0.0, m_cut = 0.0, m_q = 0.0, m_amp = 0.0, m_pan = 0.0;
	const int no = c.n_osc;
	for (int i = 0; i < 5 * MAX_OSC; i++) {
		mo[i] = 0.0;
	}
	lfo_oct[0] = lfo_oct[1] = 0.0;
	for (int r = 0; r < c.n_mods; r++) {
		const SynthPatch::Mod &row = c.mods[r];
		const double x = row.amount * src[row.src];
		switch (row.dst) {
			case D_PITCH: m_pitch += x; break;
			case D_CUTOFF: m_cut += x; break;
			case D_Q: m_q += x; break;
			case D_AMP: m_amp += x; break;
			case D_PAN: m_pan += x; break;
			case D_LFO1R: lfo_oct[0] += x; break;
			case D_LFO2R: lfo_oct[1] += x; break;
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
		if (o.table >= 0) {
			const double top = 0.5 / (dt[j * MAX_U] * std::max(e.ratio[0], e.ratio[c.unison - 1]));
			int lv = 0;
			while (lv + 1 < WT_LEVELS && level_limit(lv + 1) <= top) {
				lv++;
			}
			o_mip[j] = lv;
			const SynthPatch::Table &tb = *c.tables[o.table];
			int z = 0;
			double zw = 0.0;
			if (tb.zones > 1) {
				while (z + 1 < tb.zones && tb.keys[z + 1] <= cur) {
					z++;
				}
				if (z + 1 < tb.zones && cur > tb.keys[z]) {
					zw = (cur - tb.keys[z]) / (tb.keys[z + 1] - tb.keys[z]);
				}
				if (!tb.blend) {
					z += zw > 0.5 ? 1 : 0;
					zw = 0.0;
				}
			}
			o_zone[j] = z;
			o_zw[j] = zw;
		}
	}
	if (c.filter_type == F_LADDER) {
		double cut = c.cutoff_hz;
		if (m_cut != 0.0) {
			cut *= std::pow(2.0, m_cut);
		}
		double res = c.resonance;
		if (m_q != 0.0) {
			res = clampd(res * std::pow(2.0, m_q), 0.0, 1.2);
		}
		if (cut != last_c || res != last_q) {
			last_c = cut;
			last_q = res;
			lg = std::tan(PI * clampd(cut, 10.0, 0.49 * e.sr) / e.sr);
			lG = lg / (1.0 + lg);
			lbeta = 1.0 / (1.0 + lg);
			lk = 4.0 * res;
		}
	} else if (c.filter_type > 0) {
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
	const bool st = e.stereo;
	double mix = 0.0, mix_r = 0.0, dry = 0.0, dry_r = 0.0;
	for (int j = no - 1; j >= 0; j--) {
		const SynthPatch::Osc &o = c.osc[j];
		double acc = 0.0, acc_r = 0.0;
		if (o.shape == SH_NOISE) {
			acc = white01() * 2.0 - 1.0;
			for (int k = 0; k < u; k++) {
				raw[j * MAX_U + k] = acc;
			}
			acc_r = acc;
		} else {
			const double idx = o_idx[j];
			const double width = o_width[j];
			const double pos = o_pos[j];
			const SynthPatch::Table *tab = o.table >= 0 && o.table < (int)c.tables.size() ? c.tables[o.table].get() : nullptr;
			const bool simple = o.sync < 0 && o.ring < 0 && o.fm_from < 0 && !c.is_source[j] && !c.is_master[j] && !st;
			if (simple && (o.shape == SH_SAW || o.shape == SH_SQUARE || o.shape == SH_PULSE)) {
				// The common case, unrolled: same arithmetic as below, fewer branches.
				const double wd = o.shape == SH_PULSE ? width : 0.5;
				for (int k = 0; k < u; k++) {
					const double d = dt[j * MAX_U + k];
					double ph = phase[j * MAX_U + k];
					double x;
					if (o.shape == SH_SAW) {
						x = 2.0 * ph - 1.0 - blep(ph, d);
					} else {
						x = ph < wd ? 1.0 : -1.0;
						x += blep(ph, d);
						double p2 = ph - wd;
						p2 -= std::floor(p2);
						x -= blep(p2, d);
					}
					ph += d;
					if (ph >= 1.0) {
						ph -= std::floor(ph);
					}
					phase[j * MAX_U + k] = ph;
					acc += x * e.uw[k];
				}
			} else {
			for (int k = 0; k < u; k++) {
				const double d = dt[j * MAX_U + k];
				double ph = phase[j * MAX_U + k];
				if (o.sync >= 0 && wrap_t[o.sync * MAX_U + k] >= 0.0) {
					ph = wrap_t[o.sync * MAX_U + k] * d;
					ph -= std::floor(ph);
				}
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
					} else if (o.shape == SH_TABLE) {
						if (tab) {
							x = table_read(*tab, pos, o_mip[j], q, o_zone[j]);
							if (o_zw[j] > 0.0) {
								x += (table_read(*tab, pos, o_mip[j], q, o_zone[j] + 1) - x) * o_zw[j];
							}
						}
					} else {
						x = shape_at(o.shape, q, d, o.shape == SH_PULSE ? width : 0.5);
					}
				}
				if (o.ring >= 0) {
					x *= raw[o.ring * MAX_U + k];
				}
				raw[j * MAX_U + k] = x;
				ph += d;
				if (ph >= 1.0) {
					ph -= std::floor(ph);
					wrap_t[j * MAX_U + k] = ph / d;
				} else {
					wrap_t[j * MAX_U + k] = -1.0;
				}
				phase[j * MAX_U + k] = ph;
				if (st) {
					acc += x * e.uwl[k];
					acc_r += x * e.uwr[k];
				} else {
					acc += x * e.uw[k];
				}
			}
			}
			acc *= e.inv_su;
			acc_r *= e.inv_su;
		}
		if (e.bypass && !o.filtered) {
			dry += o_level[j] * acc * e.opl[j];
			dry_r += o_level[j] * acc_r * e.opr[j];
		} else {
			mix += o_level[j] * acc * e.opl[j];
			mix_r += o_level[j] * acc_r * e.opr[j];
		}
	}
	double y = mix;
	const int ft = c.filter_type;
	if (ft == F_LADDER) {
		y = ladder(c, y, 0);
		if (st) {
			mix_r = ladder(c, mix_r, 4);
		}
	} else if (ft > 0) {
		for (int s = 0; s < c.stages; s++) {
			const double v3 = y - ic2[s];
			const double v1 = a1 * ic1[s] + a2 * v3;
			const double v2 = ic2[s] + a2 * ic1[s] + a3 * v3;
			ic1[s] = 2.0 * v1 - ic1[s];
			ic2[s] = 2.0 * v2 - ic2[s];
			switch (ft) {
				case 1: y = v2; break;
				case 2: y = y - fk * v1 - v2; break;
				case 3: y = v1; break;
				default: y = y - fk * v1; break;
			}
			if (st) {
				const double r3 = mix_r - ic2r[s];
				const double r1 = a1 * ic1r[s] + a2 * r3;
				const double r2 = ic2r[s] + a2 * ic1r[s] + a3 * r3;
				ic1r[s] = 2.0 * r1 - ic1r[s];
				ic2r[s] = 2.0 * r2 - ic2r[s];
				switch (ft) {
					case 1: mix_r = r2; break;
					case 2: mix_r = mix_r - fk * r1 - r2; break;
					case 3: mix_r = r1; break;
					default: mix_r = mix_r - fk * r1; break;
				}
			}
		}
	}
	if (e.bypass) {
		y += dry;
		mix_r += st ? dry_r : dry;
	}
	gvel += (vel - gvel) * e.vel_k;
	const double gv = c.vel_curve == 1.0 ? gvel : std::pow(gvel, c.vel_curve);
	const double amp = e0 * (1.0 - c.vel_sens * (1.0 - gv)) * amp_mod * c.gain;
	y *= amp;
	yr = mix_r * amp;
	if (stage[0] == RELEASE && level[0] < SILENT) {
		active = false;
	}
	return y;
}

double SynthVoice::ladder(const SynthPatch &c, double x, int s0) {
	const double G = lG;
	const double b = lbeta;
	const double S = G * G * G * b * lad[s0] + G * G * b * lad[s0 + 1] + G * b * lad[s0 + 2] + b * lad[s0 + 3];
	const double drive = c.drive;
	double u = (x - lk * S) / (1.0 + lk * G * G * G * G);
	// Soft saturation, linear until |u| nears 2 / drive (as AKSynthCore).
	u = std::tanh(u * drive * 0.5) * 2.0 / drive;
	for (int i = 0; i < 4; i++) {
		const double v = (u - lad[s0 + i]) * G;
		const double yy = v + lad[s0 + i];
		lad[s0 + i] = yy + v;
		u = yy;
	}
	// Make up some of the bass a resonant ladder loses.
	return u * (1.0 + 0.5 * lk);
}

} // namespace ak
