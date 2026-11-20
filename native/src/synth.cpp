// SPDX-License-Identifier: Apache-2.0
// See synth.h. Every function here follows its namesake in synth_core.gd.
#include "synth.h"

#include <algorithm>
#include <cmath>

namespace ak {

namespace {
enum { ATTACK, DECAY, SUSTAIN, RELEASE, IDLE };
enum { SRC_ENV1, SRC_ENV2, SRC_ENV3, SRC_LFO1, SRC_LFO2, SRC_VEL, SRC_KEY, SRC_MOD, SRC_TOUCH, SRC_RANDOM, SRC_BEND,
	SRC_ENV4, SRC_ENV5, SRC_ENV6, SRC_ENV7, SRC_ENV8 };
enum { K_ADSR, K_STAGES, K_DX7, K_DX7P };
// msfa's operator gain threshold (1120 in Q24, gain 2 = level 99) in dx7 envelope units.
constexpr double DX7_THRESH = 1120.0 / 33554432.0;
// The stages and dx7 envelopes stay out of line, so env_tick (today's ADSR) still inlines into tick.
#if defined(_MSC_VER)
#define AK_NOINLINE __declspec(noinline)
#else
#define AK_NOINLINE __attribute__((noinline))
#endif
// A stages envelope's stage length meaning "hold here" and "falling with release_s".
constexpr int64_t ST_HOLD = -1, ST_FALL = -2;
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
			a.hold == b.hold && a.time_ms == b.time_ms && a.time_beats == b.time_beats && a.mode == b.mode && a.spread_ms == b.spread_ms && a.damp_hz == b.damp_hz && a.room == b.room && a.damp == b.damp && a.width == b.width;
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
	n_env = std::clamp(p.n_env, 3, SynthPatch::MAX_ENV);
	{
		// msfa's Freqlut::init, Lfo::init, PitchEnv::init for this rate.
		double y = double(int64_t(1) << 44) / sr;
		const double inc = std::pow(2.0, 1.0 / 1024.0);
		for (int i = 0; i < 1025; i++) {
			freqlut_tab[i] = (int64_t)std::floor(y + 0.5);
			y *= inc;
		}
		lfo_unit = (int64_t)(64 * 25190424 / double(sr) + 0.5);
		lfo_ratio = (int64_t)(4437500000.0 * 64 / sr);
		penv_unit = (int64_t)(64 * (1 << 24) / (21.3 * sr) + 0.5);
	}
	dx7_tables();
	dx7_lfo = -1;
	for (int k = 0; k < 2; k++) {
		lfo_dx7[k] = p.lfo[k].dx7;
		if (lfo_dx7[k] && dx7_lfo < 0) {
			dx7_lfo = k;
		}
	}
	ops = false;
	n_carrier = 0;
	bool all_own = true;
	for (int j = 0; j < p.n_osc; j++) {
		const SynthPatch::Osc &o = p.osc[j];
		const SynthPatch::OscOp &q = p.op[j];
		ops = ops || q.n_fm > 0 || q.feedback != 0.0 || q.ratio != 1.0 || q.fixed_hz > 0.0 || q.dx_mode >= 0 || q.level_env >= 0 ||
				q.vel_sens > 0.0 || q.ks;
		if (o.level != 0.0) {
			if (q.level_env < 0 || q.level_env >= n_env) {
				all_own = false;
			} else {
				bool seen = false;
				for (int i = 0; i < n_carrier; i++) {
					seen = seen || carrier_envs[i] == q.level_env;
				}
				if (!seen) {
					carrier_envs[n_carrier++] = q.level_env;
				}
			}
		}
	}
	if (!all_own) {
		n_carrier = 0;
	}
	adsr_only = n_env == 3;
	for (int k = 0; k < n_env; k++) {
		adsr_only = adsr_only && p.env[k].kind == K_ADSR;
	}
	dx7_srm = (int64_t)(44100.0 / sr * 16777216.0);
	for (int k = 0; k < n_env; k++) {
		const SynthPatch::Env &e = p.env[k];
		env_kind[k] = e.kind;
		if (e.kind == K_STAGES) {
			env_kr[k] = std::exp(-1.0 / (e.r * sr));
			continue;
		}
		if (e.kind != K_ADSR) {
			continue;
		}
		env_a[k] = (int64_t)std::llround(e.a * sr);
		env_d[k] = std::max<int64_t>(1, (int64_t)std::llround(e.d * sr));
		env_s[k] = e.s;
		env_kd[k] = std::exp(-1.0 / (e.d * sr));
		env_kr[k] = std::exp(-1.0 / (e.r * sr));
		env_kr2[k] = e.r2 > 0.0 ? std::exp(-1.0 / (e.r2 * sr)) : env_kr[k];
		env_knee[k] = e.knee;
		env_exp[k] = e.exp;
	}
	for (int k = 0; k < 2; k++) {
		lfo_shape[k] = p.lfo[k].shape;
		const double beats = p.lfo[k].beats;
		if (beats != lfo_beats[k]) {
			// Newly synced (or unsynced): the free clock starts again at playback's start.
			lfo_base[k] = 0.0;
			lfo_base_frame[k] = 0;
		}
		lfo_beats[k] = beats;
		lfo_inc[k] = beats <= 0.0 ? p.lfo[k].rate_hz / sr : tempo_bpm / 60.0 / beats / sr;
		lfo_width[k] = p.lfo[k].width;
		lfo_delay[k] = p.lfo[k].delay_s * sr;
		lfo_phase[k] = p.lfo[k].phase;
		lfo_free[k] = p.lfo[k].free;
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
	{
		// Each oscillator's slots (AKSynthCore._slots): its stack inside every
		// unison voice, the odd unison voices raised by unison_pitch.
		const double pf = p.unison_pitch != 0.0 ? std::pow(2.0, p.unison_pitch / 12.0) : 1.0;
		for (int j = 0; j < SynthPatch::MAX_OSC; j++) {
			slot_n[j] = 0;
			slot_s[j] = 1;
		}
		for (int j = 0; j < p.n_osc; j++) {
			const int sn = std::clamp(p.osc[j].stack, 1, SynthPatch::MAX_STACK);
			const double sc = p.osc[j].stack_cents;
			slot_s[j] = sn;
			slot_n[j] = u * sn;
			oinv[j] = sn == 1 ? inv_su : inv_su / std::sqrt(double(sn));
			double rmax = 0.0;
			for (int i = 0; i < u; i++) {
				double r = ratio[i];
				if (pf != 1.0 && i % 2 == 1) {
					r *= pf;
				}
				for (int s = 0; s < sn; s++) {
					const int k = j * SynthPatch::MAX_SLOT + i * sn + s;
					double rs = r;
					if (sn > 1) {
						rs *= std::pow(2.0, (double(s) / (sn - 1) - 0.5) * 2.0 * sc / 1200.0);
					}
					sratio[k] = rs;
					sw[k] = uw[i];
					swl[k] = uwl[i];
					swr[k] = uwr[i];
					rmax = std::max(rmax, rs);
				}
			}
			ormax[j] = rmax;
		}
		for (int j = 0; j < p.n_osc; j++) {
			for (int r = 0; r < p.n_osc; r++) {
				const int b = (j * SynthPatch::MAX_OSC + r) * SynthPatch::MAX_SLOT;
				for (int k = 0; k < slot_n[j]; k++) {
					smap[b + k] = (uint8_t)(slot_s[r] == slot_s[j] ? k : (k / slot_s[j]) * slot_s[r] + (k % slot_s[j]) % slot_s[r]);
				}
			}
		}
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
	const bool was_on = arp_on;
	arp_on = p.arp.on;
	if (was_on && !arp_on) {
		arp_stop();
	}
	retempo(tempo_set ? tempo_bpm : p.tempo_bpm);
}

void SynthEngine::retempo(double bpm) {
	tempo_bpm = clampd(bpm, 20.0, 400.0);
	for (int k = 0; k < 2; k++) {
		if (lfo_beats[k] > 0.0) {
			lfo_base[k] += lfo_inc[k] * double(frame - lfo_base_frame[k]);
			lfo_base_frame[k] = frame;
			lfo_inc[k] = tempo_bpm / 60.0 / lfo_beats[k] / sr;
		}
	}
	fx.set_tempo(tempo_bpm);
}

void SynthEngine::arp_key_on(double note, double vel) {
	const bool first = arp_n == 0;
	int i = 0;
	while (i < arp_n && arp_note[i] < note) {
		i++;
	}
	if (i < arp_n && arp_note[i] == note) {
		arp_vel[i] = vel;
	} else if (arp_n < ARP_MAX) {
		for (int j = arp_n; j > i; j--) {
			arp_note[j] = arp_note[j - 1];
			arp_vel[j] = arp_vel[j - 1];
		}
		arp_note[i] = note;
		arp_vel[i] = vel;
		arp_n++;
	}
	if (first) {
		// The first key starts the pattern: its first step plays on this sample.
		arp_pos = 0.0;
		arp_next = 0.0;
		arp_gate_at = -1.0;
		arp_step = 0;
		arp_starts++;
		const uint64_t x = (uint64_t)p.seed * 2654435761ull + (uint64_t)arp_starts * 40503ull;
		arp_rng = (uint32_t)(x & 0xFFFFFFFFull) | 1u;
	}
}

void SynthEngine::arp_key_off(double note) {
	for (int i = 0; i < arp_n; i++) {
		if (arp_note[i] == note) {
			for (int j = i; j < arp_n - 1; j++) {
				arp_note[j] = arp_note[j + 1];
				arp_vel[j] = arp_vel[j + 1];
			}
			arp_n--;
			break;
		}
	}
	if (arp_n == 0 && arp_sounding) {
		off(arp_cur, false);
		arp_sounding = false;
	}
}

void SynthEngine::arp_stop() {
	arp_n = 0;
	if (arp_sounding) {
		off(arp_cur, false);
		arp_sounding = false;
	}
}

void SynthEngine::arp_tick() {
	if (arp_sounding && arp_gate_at >= 0.0 && arp_pos >= arp_gate_at) {
		off(arp_cur, false);
		arp_sounding = false;
		arp_gate_at = -1.0;
	}
	if (arp_pos >= arp_next) {
		arp_fire();
		arp_next += p.arp.beats;
	}
	arp_pos += tempo_bpm / 60.0 / sr;
}

void SynthEngine::arp_fire() {
	const int64_t nk = arp_n;
	const int64_t n = nk * p.arp.octaves;
	int64_t i = 0;
	switch (p.arp.mode) {
		case 0: i = arp_step % n; break;
		case 1: i = n - 1 - arp_step % n; break;
		case 2:
			if (n > 1) {
				const int64_t q = arp_step % (2 * n - 2);
				i = q < n ? q : 2 * n - 2 - q;
			}
			break;
		case 3:
			arp_rng ^= arp_rng << 13;
			arp_rng ^= arp_rng >> 17;
			arp_rng ^= arp_rng << 5;
			i = (int64_t)(arp_rng % (uint32_t)n);
			break;
	}
	const double note = arp_note[i % nk] + 12.0 * double(i / nk);
	const double vel = arp_vel[i % nk];
	if (p.arp.gate >= 1.0) {
		// Tied: the new note starts before the old one ends (legato, glide).
		on(note, vel);
		if (arp_sounding && arp_cur != note) {
			off(arp_cur, false);
		}
		arp_gate_at = -1.0;
	} else {
		if (arp_sounding) {
			off(arp_cur, false);
		}
		on(note, vel);
		arp_gate_at = arp_next + p.arp.beats * p.arp.gate;
	}
	arp_cur = note;
	arp_sounding = true;
	arp_step++;
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
		if (arp_on && arp_n > 0) {
			arp_tick();
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
		case E_ON:
			if (arp_on) {
				arp_key_on(a, b);
			} else {
				on(a, b);
			}
			break;
		case E_OFF:
			if (arp_on) {
				arp_key_off(a);
			} else {
				off(a);
			}
			break;
		case E_TEMPO:
			tempo_set = true;
			retempo(a);
			break;
		case E_BEND: bend = clampd(a, -1.0, 1.0); break;
		case E_MOD: mod_wheel = clampd(a, 0.0, 1.0); break;
		case E_TOUCH: aftertouch = clampd(a, 0.0, 1.0); break;
		case E_ALL_OFF:
			arp_stop();
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
			arp_n = 0;
			arp_sounding = false;
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

// The pedal holds a released note unless `pedal` is false (the arpeggiator's own note-offs).
void SynthEngine::off(double note, bool pedal) {
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
			if (sustain && pedal) {
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
			if (sustain && pedal) {
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
	for (int i = 0; i < MAX_OSC * MAX_SLOT; i++) {
		phase[i] = 0.0;
		raw[i] = 0.0;
	}
	for (int j = 0; j < MAX_OSC; j++) {
		last_semi[j] = -1e9;
	}
	for (int j = 0; j < c.n_osc; j++) {
		if (c.unison > 1 || e.slot_n[j] > 1) {
			for (int k = 0; k < e.slot_n[j]; k++) {
				phase[j * MAX_SLOT + k] = white01();
			}
		}
	}
	for (int k = 0; k < 2; k++) {
		// A free LFO is where the playback clock has taken it; otherwise each note starts it at its phase.
		const double lp = e.lfo_phase[k] + (e.lfo_free[k] ? e.lfo_base[k] + e.lfo_inc[k] * (double)(e.frame - e.lfo_base_frame[k]) : 0.0);
		lfo_ph[k] = lp - std::floor(lp);
		lfo_oct[k] = 0.0;
		lfo_sh[k] = e.lfo_shape[k] >= 4 ? white01() * 2.0 - 1.0 : 0.0;
		if (e.lfo_shape[k] == 5) {
			lfo_sh0[k] = lfo_sh[k];
			lfo_sh[k] = white01() * 2.0 - 1.0;
		}
	}
	for (int k = 0; k < 2; k++) {
		if (e.lfo_dx7[k]) {
			dlfo[k].reset(e.lfo_unit, e.lfo_ratio, c.lfo[k]);
		}
	}
	if (e.ops) {
		for (int i = 0; i < MAX_OSC * MAX_SLOT; i++) {
			fbp[i] = 0.0;
		}
		for (int j = 0; j < MAX_OSC; j++) {
			o_dxnote[j] = -1;
		}
		note_levels(e, p_note, p_vel);
	}
	age = 0;
	ne = e.n_env;
	for (int k = 0; k < ne; k++) {
		stage[k] = ATTACK;
		t[k] = 0;
		level[k] = 0.0;
		start_level[k] = 0.0;
		rel_from[k] = 0.0;
		ev[k] = 1.0;
		pend[k] = 0;
		dead[k] = false;
		dq[k] = false;
		const SynthPatch::Env &en = c.env[k];
		if (e.env_kind[k] == K_STAGES) {
			note_scales(en, k, p_note, p_vel);
			level[k] = en.start * lsc[k];
			stage_enter(e, en, k, 0);
		} else if (e.env_kind[k] == K_DX7) {
			Dx7Env &d = dx[k];
			d.srm = e.dx7_srm;
			dx7_note(en, k, p_note, p_vel);
			d.level = 0;
			d.down = true;
			d.advance(en, 0);
			dg2[k] = 0.0;
		} else if (e.env_kind[k] == K_DX7P) {
			dxp[k].unit = e.penv_unit;
			dxp[k].set_up(en);
			level[k] = 0.0;
		}
	}
	ic1[0] = ic1[1] = ic2[0] = ic2[1] = 0.0;
	ic1r[0] = ic1r[1] = ic2r[0] = ic2r[1] = 0.0;
	for (int i = 0; i < 8; i++) {
		lad[i] = 0.0;
	}
	for (int i = 0; i < MAX_OSC * MAX_SLOT; i++) {
		wrap_t[i] = -1.0;
	}
	last_c = -1.0;
	last_q = -1.0;
}

void SynthVoice::retrigger() {
	for (int k = 0; k < ne; k++) {
		stage[k] = ATTACK;
		t[k] = 0;
		start_level[k] = level[k];
		ev[k] = 1.0;
		pend[k] = 1;
		dead[k] = false;
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
	for (int k = 0; k < ne; k++) {
		if (stage[k] != RELEASE) {
			rel_from[k] = level[k];
			pend[k] = 2;
		}
		stage[k] = RELEASE;
	}
}

// ---------------------------------------------------------------- dx7 (msfa)

static const int DX7_LEVELLUT[] = { 0, 5, 9, 13, 17, 20, 23, 25, 27, 29, 31, 33, 35, 37, 39, 41, 42, 43, 45, 46 };
static const int DX7_STATICS[] = { 1764000, 1764000, 1411200, 1411200, 1190700, 1014300, 992250,
	882000, 705600, 705600, 584325, 507150, 502740, 441000, 418950,
	352800, 308700, 286650, 253575, 220500, 220500, 176400, 145530,
	145530, 125685, 110250, 110250, 88200, 88200, 74970, 61740,
	61740, 55125, 48510, 44100, 37485, 31311, 30870, 27562, 27562,
	22050, 18522, 17640, 15435, 14112, 13230, 11025, 9261, 9261, 7717,
	6615, 6615, 5512, 5512, 4410, 3969, 3969, 3439, 2866, 2690, 2249,
	1984, 1896, 1808, 1411, 1367, 1234, 1146, 926, 837, 837, 705,
	573, 573, 529, 441, 441 };
static const int DX7_VELOCITY[] = { 0, 70, 86, 97, 106, 114, 121, 126, 132, 138, 142, 148, 152, 156, 160, 163,
	166, 170, 173, 174, 178, 181, 184, 186, 189, 190, 194, 196, 198, 200, 202,
	205, 206, 209, 211, 214, 216, 218, 220, 222, 224, 225, 227, 229, 230, 232,
	233, 235, 237, 238, 240, 241, 242, 243, 244, 246, 246, 248, 249, 250, 251,
	252, 253, 254 };
static const int DX7_EXP_SCALE[] = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 14, 16, 19, 23, 27, 33, 39, 47, 56, 66,
	80, 94, 110, 126, 142, 158, 174, 190, 206, 222, 238, 250 };

static int64_t dx7_scale_out(int64_t ol) {
	return ol >= 20 ? 28 + ol : DX7_LEVELLUT[ol];
}

static int64_t dx7_curve(int64_t group, int64_t depth, int curve) {
	int64_t scale;
	if (curve == 0 || curve == 3) {
		scale = (group * depth * 329) >> 12;
	} else {
		const int64_t n = (int64_t)(sizeof(DX7_EXP_SCALE) / sizeof(DX7_EXP_SCALE[0]));
		scale = (DX7_EXP_SCALE[std::min(group, n - 1)] * depth * 329) >> 15;
	}
	return curve < 2 ? -scale : scale;
}

int64_t dx7_outlevel(const SynthPatch::Env &e, int midinote, int midivel) {
	int64_t ol = dx7_scale_out(e.ol);
	const int64_t offset = midinote - e.bp - 17;
	if (offset >= 0) {
		ol += dx7_curve((offset + 1) / 3, e.rd, e.rc);
	} else {
		ol += dx7_curve(-(offset - 1) / 3, e.ld, e.lc);
	}
	ol = std::min<int64_t>(127, ol) << 5;
	const int64_t vel_value = DX7_VELOCITY[std::clamp(midivel, 0, 127) >> 1] - 239;
	ol += ((e.vs * vel_value + 7) >> 3) << 4;
	return std::max<int64_t>(0, ol);
}

int64_t dx7_rate_scaling(const SynthPatch::Env &e, int midinote) {
	return (e.rs * std::min(31, std::max(0, midinote / 3 - 7))) >> 3;
}

static const int64_t DX7_COARSE[] = { -16777216, 0, 16777216, 26591258, 33554432, 38955489, 43368474, 47099600,
	50331648, 53182516, 55732705, 58039632, 60145690, 62083076, 63876816,
	65546747, 67108864, 68576247, 69959732, 71268397, 72509921, 73690858,
	74816848, 75892776, 76922906, 77910978, 78860292, 79773775, 80654032,
	81503396, 82323963, 83117622 };
static const double DX7_LFO_SPEED[] = { 0.062541, 0.125031, 0.312393, 0.437120, 0.624610,
	0.750694, 0.936330, 1.125302, 1.249609, 1.436782,
	1.560915, 1.752081, 1.875117, 2.062494, 2.247191,
	2.374451, 2.560492, 2.686728, 2.873976, 2.998950,
	3.188013, 3.369840, 3.500175, 3.682224, 3.812065,
	4.000800, 4.186202, 4.310716, 4.501260, 4.623209,
	4.814636, 4.930480, 5.121901, 5.315191, 5.434783,
	5.617346, 5.750431, 5.946717, 6.062811, 6.248438,
	6.431695, 6.564264, 6.749460, 6.868132, 7.052186,
	7.250580, 7.375719, 7.556294, 7.687577, 7.877738,
	7.993605, 8.181967, 8.372405, 8.504848, 8.685079,
	8.810573, 8.986341, 9.122423, 9.300595, 9.500285,
	9.607994, 9.798158, 9.950249, 10.117361, 11.251125,
	11.384335, 12.562814, 13.676149, 13.904338, 15.092062,
	16.366612, 16.638935, 17.869907, 19.193858, 19.425019,
	20.833333, 21.034918, 22.502250, 24.003841, 24.260068,
	25.746653, 27.173913, 27.578599, 29.052876, 30.693677,
	31.191516, 32.658393, 34.317090, 34.674064, 36.416606,
	38.197097, 38.550501, 40.387722, 40.749796, 42.625746,
	44.326241, 44.883303, 46.772685, 48.590865, 49.261084 };
static const int DX7_PENV_RATE[] = { 1, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12,
	12, 13, 13, 14, 14, 15, 16, 16, 17, 18, 18, 19, 20, 21, 22, 23, 24,
	25, 26, 27, 28, 30, 31, 33, 34, 36, 37, 38, 39, 41, 42, 44, 46, 47,
	49, 51, 53, 54, 56, 58, 60, 62, 64, 66, 68, 70, 72, 74, 76, 79, 82,
	85, 88, 91, 94, 98, 102, 106, 110, 115, 120, 125, 130, 135, 141, 147,
	153, 159, 165, 171, 178, 185, 193, 202, 211, 232, 243, 254, 255 };
static const int DX7_PENV_TAB[] = { -128, -116, -104, -95, -85, -76, -68, -61, -56, -52, -49, -46, -43,
	-41, -39, -37, -35, -33, -32, -31, -30, -29, -28, -27, -26, -25, -24,
	-23, -22, -21, -20, -19, -18, -17, -16, -15, -14, -13, -12, -11, -10,
	-9, -8, -7, -6, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
	11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27,
	28, 29, 30, 31, 32, 33, 34, 35, 38, 40, 43, 46, 49, 53, 58, 65, 73,
	82, 92, 103, 115, 127 };
static const int64_t DX7_PMS[] = { 0, 10, 20, 33, 55, 92, 153, 255 };
static const int64_t DX7_AMS[] = { 0, 4342338, 7171437, 16777216 };

// msfa's sine table (Sin::init, SIN_DELTA), built once.
static int64_t g_sintab[2048];
static bool g_sintab_ready = false;
static void build_sintab() {
	if (g_sintab_ready) {
		return;
	}
	const double dphase = 2.0 * PI / 1024.0;
	const int64_t cc = (int64_t)std::floor(std::cos(dphase) * (1 << 30) + 0.5);
	const int64_t ss = (int64_t)std::floor(std::sin(dphase) * (1 << 30) + 0.5);
	int64_t u = int64_t(1) << 30, v = 0;
	for (int i = 0; i < 512; i++) {
		g_sintab[(i << 1) + 1] = (v + 32) >> 6;
		g_sintab[((i + 512) << 1) + 1] = -((v + 32) >> 6);
		const int64_t t = (u * ss + v * cc + (int64_t(1) << 29)) >> 30;
		u = (u * cc - v * ss + (int64_t(1) << 29)) >> 30;
		v = t;
	}
	for (int i = 0; i < 1023; i++) {
		g_sintab[i << 1] = g_sintab[(i << 1) + 3] - g_sintab[(i << 1) + 1];
	}
	g_sintab[2046] = -g_sintab[2047];
	g_sintab_ready = true;
}

int64_t dx7_sin(int64_t phase) {
	const int64_t pi_ = (phase >> 13) & 2046;
	return g_sintab[pi_ + 1] + ((g_sintab[pi_] * (phase & 0x3fff)) >> 14);
}

// msfa's sine table read in float (a dx7 operator's sine, as msfa's Sin::lookup):
// `q` in cycles, linear between the table's 1024 points.
double dx7_sinf(double q) {
	// floor without a library call (exact for any phase this sees).
	double fl = (double)(int64_t)q;
	if (fl > q) {
		fl -= 1.0;
	}
	q -= fl;
	const double x = q * 1024.0;
	const int i = std::min(1023, (int)x);
	return (double(g_sintab[(i << 1) + 1]) + double(g_sintab[i << 1]) * (x - i)) / 16777216.0;
}

int64_t SynthEngine::freqlut(int64_t logfreq) const {
	const int64_t ix = (logfreq & 0xffffff) >> 14;
	const int64_t y0 = freqlut_tab[ix], y1 = freqlut_tab[ix + 1];
	const int64_t y = y0 + (((y1 - y0) * (logfreq & 0x3fff)) >> 14);
	return y >> (20 - (logfreq >> 24));
}

int64_t dx7_osc_logfreq(int midinote, int mode, int coarse, int fine, int detune) {
	int64_t logfreq;
	if (mode == 0) {
		logfreq = 50857777 + ((1 << 24) / 12) * (int64_t)midinote;
		const double detune_ratio = 0.0209 * std::exp(-0.396 * ((double)(float)logfreq / double(1 << 24))) / 7.0;
		logfreq = (int64_t)((double)logfreq + detune_ratio * (double)logfreq * double(detune - 7));
		logfreq += DX7_COARSE[coarse & 31];
		if (fine != 0) {
			logfreq += (int64_t)std::floor(24204406.323123 * std::log(1.0 + 0.01 * fine) + 0.5);
		}
	} else {
		logfreq = (int64_t(4458616) * ((coarse & 3) * 100 + fine)) >> 3;
		logfreq += detune > 7 ? 13457 * (detune - 7) : 0;
	}
	return logfreq;
}

int64_t dx7_amp_mod(int64_t lq, int64_t amd, int ams) {
	const int64_t sensamp = (amd * DX7_AMS[ams]) >> 24;
	const int64_t pt = (int64_t)std::exp((double)(float)sensamp / 262144.0 * 0.07 + 12.2) & 0xFFFFFFFF;
	return (lq * (pt << 4)) >> 28;
}

void Dx7PEnv::set_up(const SynthPatch::Env &e) {
	level = (int64_t)DX7_PENV_TAB[e.levels[3]] * (int64_t(1) << 19);
	down = true;
	advance(e, 0);
}

void Dx7PEnv::advance(const SynthPatch::Env &e, int newix) {
	ix = newix;
	if (ix < 4) {
		target = (int64_t)DX7_PENV_TAB[e.levels[ix]] * (int64_t(1) << 19);
		rising = target > level;
		inc = DX7_PENV_RATE[e.rates[ix]] * unit;
	}
}

int64_t Dx7PEnv::getsample(const SynthPatch::Env &e) {
	if (ix < 3 || (ix < 4 && !down)) {
		if (rising) {
			level += inc;
			if (level >= target) {
				level = target;
				advance(e, ix + 1);
			}
		} else {
			level -= inc;
			if (level <= target) {
				level = target;
				advance(e, ix + 1);
			}
		}
	}
	return level;
}

void dx7_tables() {
	build_sintab();
}

void Dx7Lfo::reset(int64_t unit, int64_t ratio, const SynthPatch::Lfo &l) {
	build_sintab();
	phase = 0;
	rand = 0;
	delta = (int64_t)(DX7_LFO_SPEED[l.speed] * (double)ratio) & 0xFFFFFFFF;
	int64_t a = 99 - l.delay;
	if (a == 99) {
		dinc = dinc2 = 0xFFFFFFFF;
	} else {
		a = (16 + (a & 15)) << (1 + (a >> 4));
		dinc = (unit * a) & 0xFFFFFFFF;
		a &= 0xff80;
		a = std::max<int64_t>(0x80, a);
		dinc2 = (unit * a) & 0xFFFFFFFF;
	}
	if (l.sync) {
		phase = (int64_t(1) << 31) - 1;
	}
	dstate = 0;
	pitch_mod = 0;
	amd = 0;
}

int64_t Dx7Lfo::getsample(int wave) {
	phase = (phase + delta) & 0xFFFFFFFF;
	switch (wave) {
		case 0: {
			int64_t x = phase >> 7;
			if ((phase >> 31) != 0) {
				x = ~x;
			}
			return x & ((1 << 24) - 1);
		}
		case 1: return ((~phase & 0xFFFFFFFF) ^ (int64_t(1) << 31)) >> 8;
		case 2: return (phase ^ (int64_t(1) << 31)) >> 8;
		case 3: return ((~phase & 0xFFFFFFFF) >> 7) & (1 << 24);
		case 4: return (1 << 23) + (dx7_sin(phase >> 8) >> 1);
		default:
			if (phase < delta) {
				rand = (rand * 179 + 17) & 0xff;
			}
			return ((rand ^ 0x80) + 1) << 16;
	}
}

int64_t Dx7Lfo::getdelay() {
	const int64_t d = dstate + (dstate < (int64_t(1) << 31) ? dinc : dinc2);
	if (d > 0xFFFFFFFF) {
		return 1 << 24;
	}
	dstate = d;
	if (d < (int64_t(1) << 31)) {
		return 0;
	}
	return (d >> 7) & ((1 << 24) - 1);
}

void Dx7Lfo::step(const SynthPatch::Lfo &l) {
	const int64_t lv = getsample(l.wave);
	const int64_t ld = getdelay();
	const int64_t pmd = ((((int64_t)l.pmd * 165) >> 6) * ld) & 0xFFFFFFFF;
	const int64_t senslfo = DX7_PMS[l.pms] * (lv - (1 << 23));
	const int64_t p1 = std::llabs((pmd * senslfo) >> 39);
	pitch_mod = senslfo < 0 ? -p1 : p1;
	const int64_t a1 = (((((int64_t)l.amd * 165) >> 6) * ld) >> 8) & 0xFFFFFFFF;
	amd = ((a1 * ((int64_t(1) << 24) - lv)) >> 24) & 0xFFFFFFFF;
}

double SynthVoice::dx7p_tick(const SynthEngine &e, int k) {
	if (t[k] == 0) {
		const SynthPatch::Env &en = e.p.env[k];
		Dx7PEnv &d = dxp[k];
		if (pend[k] == 1) {
			d.down = true;
			d.advance(en, 0);
		} else if (pend[k] == 2 && d.down) {
			d.down = false;
			d.advance(en, 3);
		}
		pend[k] = 0;
		level[k] = double(d.getsample(en)) / 16777216.0;
	}
	t[k]++;
	if (t[k] == DX7_N) {
		t[k] = 0;
	}
	return level[k];
}

void SynthVoice::note_levels(const SynthEngine &e, double p_note, double p_vel) {
	const SynthPatch &c = e.p;
	for (int j = 0; j < c.n_osc; j++) {
		const SynthPatch::OscOp &q = c.op[j];
		double kv = 1.0 - q.vel_sens * (1.0 - p_vel);
		if (q.ks) {
			const double oct = (p_note - q.ks_break) / 12.0;
			const bool right = oct >= 0.0;
			const double depth = right ? q.ks_r : q.ks_l;
			const double x = std::fabs(oct);
			const double db = depth * ((right ? q.ks_rexp : q.ks_lexp) ? (std::pow(2.0, x) - 1.0) : x);
			kv *= std::pow(10.0, db / 20.0);
		}
		o_kv[j] = kv;
	}
}

void SynthVoice::op_freq(const SynthEngine &e, const SynthPatch::Osc &o, int j, double s) {
	const SynthPatch::OscOp &q = e.p.op[j];
	if (q.dx_mode >= 0) {
		// GDScript's roundi: half away from zero, as llround.
		const int mn = (int)std::clamp<long long>(std::llround(target + o.semis), 0, 127);
		if (mn != o_dxnote[j]) {
			o_dxnote[j] = mn;
			o_dxbase[j] = dx7_osc_logfreq(mn, q.dx_mode, q.dx_coarse, q.dx_fine, q.dx_detune);
		}
		const double off = q.dx_mode == 0 ? (s - target - o.semis) : e.bend * e.p.bend_range;
		const int64_t inc = e.freqlut(o_dxbase[j] + (int64_t)std::llround(off * 16777216.0 / 12.0));
		o_inc[j] = double(inc) / 16777216.0;
		freq[j] = o_inc[j] * e.sr;
		return;
	}
	if (q.fixed_hz > 0.0) {
		freq[j] = q.fixed_hz * std::pow(2.0, (s - cur) / 12.0);
	} else {
		freq[j] = 440.0 * std::pow(2.0, (s - 69.0) / 12.0) * q.ratio;
	}
}

bool SynthVoice::env_done(const SynthEngine &e, int k) const {
	if (level[k] >= SILENT) {
		return false;
	}
	switch (e.env_kind[k]) {
		case K_DX7: return dead[k] || killing;
		case K_STAGES: return stage[k] == RELEASE && si[k] >= e.p.env[k].quiet;
		default: return stage[k] == RELEASE;
	}
}

void Dx7Env::advance(const SynthPatch::Env &e, int newix) {
	ix = newix;
	if (ix >= 4) {
		return;
	}
	const int64_t newlevel = e.levels[ix];
	int64_t actual = dx7_scale_out(newlevel) >> 1;
	actual = (actual << 6) + outlevel - 4256;
	actual = std::max<int64_t>(16, actual);
	target = actual << 16;
	rising = target > level;
	int64_t qrate = ((int64_t)e.rates[ix] * 41) >> 6;
	qrate = std::min<int64_t>(qrate + rate_scaling, 63);
	if (target == level || (ix == 0 && newlevel == 0)) {
		const int64_t staticrate = std::min<int64_t>(e.rates[ix] + rate_scaling, 99);
		staticcount = staticrate < 77 ? DX7_STATICS[staticrate] : 20 * (99 - staticrate);
		if (staticrate < 77 && ix == 0 && newlevel == 0) {
			staticcount /= 20;
		}
		staticcount = (staticcount * srm) >> 24;
	} else {
		staticcount = 0;
	}
	inc = (4 + (qrate & 3)) << (2 + 6 + (qrate >> 2));
	inc = (inc * srm) >> 24;
}

int64_t Dx7Env::getsample(const SynthPatch::Env &e) {
	if (staticcount != 0) {
		staticcount -= DX7_N;
		if (staticcount <= 0) {
			staticcount = 0;
			advance(e, ix + 1);
		}
	}
	if (ix < 3 || (ix < 4 && !down)) {
		if (staticcount != 0) {
		} else if (rising) {
			if (level < (1716 << 16)) {
				level = 1716 << 16;
			}
			level += (((int64_t(17) << 24) - level) >> 24) * inc;
			if (level >= target) {
				level = target;
				advance(e, ix + 1);
			}
		} else {
			level -= inc;
			if (level <= target) {
				level = target;
				advance(e, ix + 1);
			}
		}
	}
	return level;
}

void SynthVoice::dx7_note(const SynthPatch::Env &en, int k, double p_note, double p_vel) {
	// GDScript's roundi: half away from zero, as llround.
	const int mn = (int)std::clamp<long long>(std::llround(p_note) + en.ko, 0, 127);
	const int mv = (int)std::clamp<long long>(std::llround(p_vel * 127.0), 0, 127);
	dx[k].outlevel = dx7_outlevel(en, mn, mv);
	dx[k].rate_scaling = dx7_rate_scaling(en, mn);
}

AK_NOINLINE double SynthVoice::dx7_tick(const SynthEngine &e, int k) {
	if (killing) {
		level[k] *= e.kill_k;
		return level[k];
	}
	if (t[k] == 0) {
		if (dead[k]) {
			level[k] = 0.0;
			return 0.0;
		}
		const SynthPatch::Env &en = e.p.env[k];
		Dx7Env &d = dx[k];
		if (pend[k] == 1) {
			dx7_note(en, k, target, vel);
			d.down = true;
			d.advance(en, 0);
		} else if (pend[k] == 2 && d.down) {
			d.down = false;
			d.advance(en, 3);
		}
		pend[k] = 0;
		int64_t lq = d.getsample(en);
		if (en.ams > 0 && e.dx7_lfo >= 0) {
			lq -= dx7_amp_mod(lq, dlfo[e.dx7_lfo].amd, en.ams);
		}
		dg1[k] = dg2[k];
		dg2[k] = std::pow(2.0, double(lq - DX7_FULL) / 16777216.0);
		dq[k] = dg1[k] < DX7_THRESH && dg2[k] < DX7_THRESH;
		if (d.ix >= 4 && en.levels[3] == 0) {
			dead[k] = true;
		}
	}
	t[k]++;
	level[k] = dq[k] ? 0.0 : dg1[k] + (dg2[k] - dg1[k]) * double(t[k]) / DX7_N;
	if (t[k] == DX7_N) {
		t[k] = 0;
	}
	return level[k];
}

// ---------------------------------------------------------------- stages

void SynthVoice::note_scales(const SynthPatch::Env &en, int k, double p_note, double p_vel) {
	tkf[k] = en.tk != 0.0 ? std::pow(2.0, -en.tk * (p_note - en.tk_center) / 12.0) : 1.0;
	tvf[k] = en.tv != 0.0 ? std::pow(2.0, -en.tv * (p_vel - 1.0)) : 1.0;
	lsc[k] = 1.0 - en.lv * (1.0 - p_vel);
}

AK_NOINLINE void SynthVoice::stage_enter(const SynthEngine &e, const SynthPatch::Env &en, int k, int i) {
	const int n = en.n;
	for (int guard = 0; guard < 4 * n + 4; guard++) {
		if (i < 0 || i >= n) {
			si[k] = n;
			sn[k] = ST_HOLD;
			return;
		}
		si[k] = i;
		t[k] = 0;
		double scale = 1.0;
		if ((en.tk_mask >> i) & 1) {
			scale *= tkf[k];
		}
		if ((en.tv_mask >> i) & 1) {
			scale *= tvf[k];
		}
		// GDScript's roundi.
		const int64_t length = (int64_t)std::llround(en.time[i] * scale * e.sr);
		sfrom[k] = level[k];
		sto[k] = en.curve[i] == 2 ? level[k] : en.level[i] * lsc[k];
		if (length > 0) {
			sn[k] = length;
			const double am = en.amount[i];
			if (en.curve[i] == 1 && std::fabs(am) > 1e-9) {
				sg[k] = 1.0;
				sk[k] = std::exp(am / length);
				sden[k] = std::exp(am) - 1.0;
			} else {
				sden[k] = 0.0;
			}
			return;
		}
		level[k] = sto[k];
		i = stage_next(en, k, i);
		if (i == ST_HOLD) {
			sn[k] = ST_HOLD;
			return;
		}
	}
	sn[k] = ST_HOLD;
}

int SynthVoice::stage_next(const SynthPatch::Env &en, int k, int i) const {
	if (stage[k] != RELEASE) {
		if (i == en.loop_b) {
			return en.loop_a;
		}
		if (i == en.sustain) {
			return (int)ST_HOLD;
		}
	}
	return i + 1;
}

AK_NOINLINE double SynthVoice::stages_tick(const SynthEngine &e, int k) {
	if (killing) {
		level[k] *= e.kill_k;
		return level[k];
	}
	const SynthPatch::Env &en = e.p.env[k];
	if (pend[k] != 0) {
		const int pk = pend[k];
		pend[k] = 0;
		if (pk == 1) {
			note_scales(en, k, target, vel);
			stage_enter(e, en, k, 0);
		} else if (en.sustain >= 0) {
			if (en.sustain + 1 < en.n) {
				stage_enter(e, en, k, en.sustain + 1);
			} else {
				si[k] = en.n;
				sn[k] = ST_FALL;
			}
		}
	}
	const int64_t n = sn[k];
	if (n == ST_HOLD) {
		return level[k];
	}
	if (n == ST_FALL) {
		level[k] *= e.env_kr[k];
		return level[k];
	}
	t[k]++;
	if (t[k] >= n) {
		level[k] = sto[k];
		const int nx = stage_next(en, k, si[k]);
		if (nx == ST_HOLD) {
			sn[k] = ST_HOLD;
		} else {
			stage_enter(e, en, k, nx);
		}
		return level[k];
	}
	if (sden[k] != 0.0) {
		sg[k] *= sk[k];
		level[k] = sfrom[k] + (sto[k] - sfrom[k]) * (sg[k] - 1.0) / sden[k];
	} else if (en.curve[si[k]] != 2) {
		level[k] = sfrom[k] + (sto[k] - sfrom[k]) * double(t[k]) / n;
	}
	return level[k];
}

double SynthVoice::env_tick(const SynthEngine &e, int k) {
	const int kind = e.env_kind[k];
	if (t[k] != 0 && !killing) {
		// Between msfa's 64-sample steps (the same arithmetic as dx7_tick, dx7p_tick).
		if (kind == K_DX7) {
			t[k]++;
			level[k] = dq[k] ? 0.0 : dg1[k] + (dg2[k] - dg1[k]) * double(t[k]) / DX7_N;
			if (t[k] == DX7_N) {
				t[k] = 0;
			}
			return level[k];
		}
		if (kind == K_DX7P) {
			t[k]++;
			if (t[k] == DX7_N) {
				t[k] = 0;
			}
			return level[k];
		}
	}
	if (kind == K_STAGES) {
		return stages_tick(e, k);
	}
	if (kind == K_DX7) {
		return dx7_tick(e, k);
	}
	if (kind == K_DX7P) {
		return dx7p_tick(e, k);
	}
	return adsr_tick(e, k);
}

inline double SynthVoice::adsr_tick(const SynthEngine &e, int k) {
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
		if (killing) {
			level[k] *= e.kill_k;
		} else {
			level[k] *= level[k] > rel_from[k] * e.env_knee[k] ? e.env_kr[k] : e.env_kr2[k];
		}
	}
	return level[k];
}

double SynthVoice::lfo_tick(const SynthEngine &e, int k) {
	if (e.lfo_dx7[k]) {
		return double(dlfo[k].pitch_mod) / 16777216.0;
	}
	double ph = lfo_ph[k];
	const int shape = e.lfo_shape[k];
	double v;
	switch (shape) {
		case 0: v = std::sin(TAU * ph); break;
		case 1: v = 1.0 - 4.0 * std::fabs(ph - 0.5); break;
		case 2: v = 2.0 * ph - 1.0; break;
		case 3: v = ph < e.lfo_width[k] ? 1.0 : -1.0; break;
		case 5: v = lfo_sh0[k] + (lfo_sh[k] - lfo_sh0[k]) * (0.5 - 0.5 * std::cos(PI * ph)); break;
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
		} else if (shape == 5) {
			lfo_sh0[k] = lfo_sh[k];
			lfo_sh[k] = white01() * 2.0 - 1.0;
		}
	}
	lfo_ph[k] = ph;
	return v;
}

// The key_levels gain at a key, as AKSynthCore.key_level.
static double key_level(const std::vector<double> &kl, double key) {
	const size_t n = kl.size() / 2;
	if (key <= kl[0] || n == 1) {
		return kl[1];
	}
	for (size_t i = 1; i < n; i++) {
		if (key < kl[2 * i]) {
			const double t = (key - kl[2 * i - 2]) / (kl[2 * i] - kl[2 * i - 2]);
			return kl[2 * i - 1] * std::pow(kl[2 * i + 1] / kl[2 * i - 1], t);
		}
	}
	return kl[2 * n - 1];
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
	for (int k = 3; k < ne; k++) {
		src[SRC_ENV4 + k - 3] = level[k];
	}
	double m_pitch = 0.0, m_cut = 0.0, m_q = 0.0, m_amp = 0.0, m_pan = 0.0;
	const int no = c.n_osc;
	for (int slot = 0; slot < 5 * MAX_OSC; slot += MAX_OSC) {
		for (int j = 0; j < no; j++) {
			mo[slot + j] = 0.0;
		}
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
			if (e.ops) {
				op_freq(e, o, j, s);
			} else {
				freq[j] = 440.0 * std::pow(2.0, (s - 69.0) / 12.0);
			}
		}
		o_level[j] = o.level + mo[MAX_OSC + j];
		if (e.ops) {
			o_level[j] *= o_kv[j];
		}
		o_idx[j] = o.fm_index + mo[2 * MAX_OSC + j];
		o_width[j] = clampd(o.width + mo[3 * MAX_OSC + j], 0.01, 0.99);
		o_pos[j] = clampd(o.position + mo[4 * MAX_OSC + j], 0.0, 1.0);
		const int sb = j * MAX_SLOT;
		for (int k = 0; k < e.slot_n[j]; k++) {
			dt[sb + k] = freq[j] * e.sratio[sb + k] / e.sr;
		}
		if (e.ops && c.op[j].dx_mode >= 0) {
			// A dx7 operator advances exactly msfa's increment.
			for (int k = 0; k < e.slot_n[j]; k++) {
				dt[sb + k] = o_inc[j] * e.sratio[sb + k];
			}
		}
		if (o.table >= 0) {
			const double top = 0.5 / (dt[sb] * e.ormax[j]);
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
	if (c.key_lv.size() >= 2) {
		amp_mod *= key_level(c.key_lv, target);
	}
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
	if (e.dx7_lfo >= 0 && age % DX7_N == 0) {
		// The DX7 LFOs step before the envelopes read their amp modulation, as msfa.
		for (int k = 0; k < 2; k++) {
			if (e.lfo_dx7[k]) {
				dlfo[k].step(c.lfo[k]);
			}
		}
	}
	double e0, e1, e2;
	if (e.adsr_only) {
		e0 = adsr_tick(e, 0);
		e1 = adsr_tick(e, 1);
		e2 = adsr_tick(e, 2);
	} else {
		e0 = env_tick(e, 0);
		e1 = env_tick(e, 1);
		e2 = env_tick(e, 2);
		for (int k = 3; k < ne; k++) {
			env_tick(e, k);
		}
	}
	if (age % CONTROL == 0) {
		control(e, e0, e1, e2);
	}
	age++;
	const int no = c.n_osc;
	const bool st = e.stereo;
	double mix = 0.0, mix_r = 0.0, dry = 0.0, dry_r = 0.0;
	for (int j = no - 1; j >= 0; j--) {
		const SynthPatch::Osc &o = c.osc[j];
		const SynthPatch::OscOp &qo = c.op[j];
		double acc = 0.0, acc_r = 0.0;
		const int n = e.slot_n[j];
		const int sb = j * MAX_SLOT;
		const uint8_t *mp = e.smap + j * MAX_OSC * MAX_SLOT;
		if (o.shape == SH_NOISE) {
			acc = white01() * 2.0 - 1.0;
			for (int k = 0; k < n; k++) {
				raw[sb + k] = acc;
			}
			acc_r = acc;
		} else {
			const double idx = o_idx[j];
			const double width = o_width[j];
			const double pos = o_pos[j];
			const SynthPatch::Table *tab = o.table >= 0 && o.table < (int)c.tables.size() ? c.tables[o.table].get() : nullptr;
			const bool simple = c.plain[j] && !st;
			if (simple && (o.shape == SH_SAW || o.shape == SH_SQUARE || o.shape == SH_PULSE)) {
				// The common case, unrolled: same arithmetic as below, fewer branches.
				const double wd = o.shape == SH_PULSE ? width : 0.5;
				for (int k = 0; k < n; k++) {
					const double d = dt[sb + k];
					double ph = phase[sb + k];
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
					phase[sb + k] = ph;
					acc += x * e.sw[sb + k];
				}
			} else {
			const int le = qo.level_env;
			const double eg = le >= 0 ? level[le] : 1.0;
			for (int k = 0; k < n; k++) {
				const double d = dt[sb + k];
				double ph = phase[sb + k];
				if (o.sync >= 0) {
					const double ws = wrap_t[o.sync * MAX_SLOT + mp[o.sync * MAX_SLOT + k]];
					if (ws >= 0.0) {
						ph = ws * d;
						ph -= std::floor(ph);
					}
				}
				double pm = o.fm_from >= 0 ? idx * raw[o.fm_from * MAX_SLOT + mp[o.fm_from * MAX_SLOT + k]] : 0.0;
				for (int m = 0; m < qo.n_fm; m++) {
					pm += qo.fm_amt[m] * raw[qo.fm_src[m] * MAX_SLOT + mp[qo.fm_src[m] * MAX_SLOT + k]];
				}
				if (qo.feedback != 0.0) {
					pm += qo.feedback * 0.5 * (fbp[sb + k] + raw[sb + k]);
				}
				double x;
				if (o.shape == SH_SINE) {
					// An operator silent this block (msfa skips it) needs no sine: its output is 0 either way.
					x = qo.dx_mode >= 0 ? (eg == 0.0 ? 0.0 : dx7_sinf(ph + pm / TAU)) : std::sin(TAU * ph + pm);
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
					x *= raw[o.ring * MAX_SLOT + mp[o.ring * MAX_SLOT + k]];
				}
				if (le >= 0) {
					x *= eg;
				}
				if (qo.feedback != 0.0) {
					fbp[sb + k] = raw[sb + k];
				}
				raw[sb + k] = x;
				ph += d;
				if (ph >= 1.0) {
					ph -= std::floor(ph);
					wrap_t[sb + k] = ph / d;
				} else {
					wrap_t[sb + k] = -1.0;
				}
				phase[sb + k] = ph;
				if (st) {
					acc += x * e.swl[sb + k];
					acc_r += x * e.swr[sb + k];
				} else {
					acc += x * e.sw[sb + k];
				}
			}
			}
			acc *= e.oinv[j];
			acc_r *= e.oinv[j];
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
	// As AKSynthCore: a stages amp envelope ends its voice once no stage ahead can rise again; a dx7
	// one when msfa's note would end.
	if (env_done(e, 0)) {
		active = false;
	} else if (e.n_carrier > 0) {
		bool all_done = true;
		for (int i = 0; i < e.n_carrier && all_done; i++) {
			all_done = env_done(e, e.carrier_envs[i]);
		}
		if (all_done) {
			active = false;
		}
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
