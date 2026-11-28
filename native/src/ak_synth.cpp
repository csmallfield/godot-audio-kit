// SPDX-License-Identifier: Apache-2.0
#include "ak_synth.h"
#include "ak_fx.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/callable_method_pointer.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

static double num(const Dictionary &d, const char *k, double def) {
	Variant v = d.get(k, def);
	return (double)v;
}

// A voice filter's fields (filter 1 at the top level, filter 2 under "f2"; AKPatch._compile_filt).
static void parse_filt(const Dictionary &d, ak::SynthPatch::Filt &f) {
	f.type = (int)num(d, "filter_type", 1);
	f.cutoff_hz = num(d, "cutoff_hz", 18000.0);
	f.q = num(d, "q", 0.707);
	f.resonance = num(d, "resonance", 0.3);
	f.drive = num(d, "drive", 1.0);
	f.stages = std::clamp((int)num(d, "stages", 1), 1, 2);
	f.poles = std::clamp(num(d, "poles", 4.0), 1.0, 4.0);
	f.cfb = std::clamp(num(d, "cfb", 0.5), -0.99, 0.99);
	f.cdamp = std::max(0.0, num(d, "cdamp", 0.0));
	f.vowel = std::clamp(num(d, "vowel", 0.0), 0.0, 1.0);
	f.fshift = num(d, "fshift", 0.0);
	f.fq = std::max(0.05, num(d, "fq", 1.0));
	f.fset = std::clamp((int)num(d, "fset", 1), 0, 3);
	PackedFloat64Array pmix = d.get("pole_mix", PackedFloat64Array());
	for (int i = 0; i < 5; i++) {
		f.pole_mix[i] = i < pmix.size() ? pmix[i] : 0.0;
	}
	f.lmode = pmix.size() == 5 ? 2 : (f.poles < 4.0 ? 1 : 0);
	f.f_low = num(d, "f_low", 1.0);
	f.f_band = num(d, "f_band", 0.0);
	f.f_high = num(d, "f_high", 0.0);
	f.gain_db = num(d, "gain_db", 0.0);
	f.diode = (bool)d.get("diode", false);
	f.damping = num(d, "damping", 0.0);
}

ak::SynthPatch godot::synth_patch_from(const Dictionary &d) {
	ak::SynthPatch p;
	Array osc = d.get("osc", Array());
	p.n_osc = std::min<int>(osc.size(), ak::SynthPatch::MAX_OSC);
	for (int i = 0; i < p.n_osc; i++) {
		Dictionary o = osc[i];
		ak::SynthPatch::Osc &x = p.osc[i];
		x.shape = (int)num(o, "shape", 0);
		x.level = num(o, "level", 1.0);
		x.semis = num(o, "semis", 0.0);
		x.dr = std::max(0.0, num(o, "dr", 1.0));
		x.width = num(o, "width", 0.5);
		x.position = num(o, "position", 0.0);
		x.fm_from = (int)num(o, "fm_from", -1);
		x.fm_index = num(o, "fm_index", 0.0);
		x.sync = (int)num(o, "sync", -1);
		x.ring = (int)num(o, "ring", -1);
		x.table = (int)num(o, "table", -1);
		x.pan = num(o, "pan", 0.0);
		x.filtered = (bool)o.get("filtered", true);
		x.route = std::clamp((int)num(o, "route", 0), 0, 2);
		x.stack = std::clamp((int)num(o, "stack", 1.0), 1, ak::SynthPatch::MAX_STACK);
		x.stack_cents = num(o, "stack_cents", 0.0);
		x.fm_mode = std::clamp((int)num(o, "fm_mode", 0), 0, 2);
		x.phase0 = num(o, "phase0", -1.0);
		x.phase_with = (int)num(o, "phase_with", -1);
		x.ncolor = std::clamp((int)num(o, "ncolor", 0), 0, 2);
		x.sample = (int)num(o, "sample", -1);
		x.track = std::clamp(num(o, "track", 1.0), 0.0, 1.0);
		x.s_start = std::max(0.0, num(o, "s_start", 0.0));
		x.pbase = std::clamp((int)num(o, "pbase", 0), 0, ak::SynthPatch::MAX_MODES);
		x.pn = std::clamp((int)num(o, "pn", 0), 0, ak::SynthPatch::MAX_MODES - x.pbase);
		x.excite = (int)num(o, "excite", -1);
		ak::SynthPatch::OscOp &q = p.op[i];
		PackedInt64Array fs = o.get("fm_src", PackedInt64Array());
		PackedFloat64Array fa = o.get("fm_amt", PackedFloat64Array());
		q.n_fm = 0;
		for (int m = 0; m < fs.size() && m < fa.size() && q.n_fm < ak::SynthPatch::MAX_OSC; m++) {
			if (fs[m] >= 0 && fs[m] < p.n_osc) {
				q.fm_src[q.n_fm] = (int)fs[m];
				q.fm_amt[q.n_fm] = fa[m];
				q.n_fm++;
			}
		}
		q.feedback = num(o, "feedback", 0.0);
		q.ratio = num(o, "ratio", 1.0);
		q.fixed_hz = num(o, "fixed_hz", 0.0);
		q.dx_mode = std::clamp((int)num(o, "dx_mode", -1), -1, 1);
		q.dx_coarse = std::clamp((int)num(o, "dx_coarse", 1), 0, 127);
		q.dx_fine = std::clamp((int)num(o, "dx_fine", 0), 0, 127);
		q.dx_detune = std::clamp((int)num(o, "dx_detune", 7), 0, 127);
		q.level_env = std::clamp((int)num(o, "level_env", -1), -1, ak::SynthPatch::MAX_ENV - 1);
		q.vel_sens = num(o, "vel_sens", 0.0);
		q.ks = (bool)o.get("ks", false);
		q.ks_break = num(o, "ks_break", 60.0);
		q.ks_l = num(o, "ks_l", 0.0);
		q.ks_r = num(o, "ks_r", 0.0);
		q.ks_lexp = (bool)o.get("ks_lexp", false);
		q.ks_rexp = (bool)o.get("ks_rexp", false);
		q.shape_env = std::clamp((int)num(o, "shape_env", -1), -1, ak::SynthPatch::MAX_ENV - 1);
		q.pitch_env = std::clamp((int)num(o, "pitch_env", -1), -1, ak::SynthPatch::MAX_ENV - 1);
		q.pd_w1 = std::clamp((int)num(o, "pd_w1", 0), 0, 7);
		q.pd_w2 = std::clamp((int)num(o, "pd_w2", q.pd_w1), 0, 7);
		q.pd_win = std::clamp((int)num(o, "pd_win", 0), 0, 5);
		q.pd_noise = (bool)o.get("pd_noise", false);
		if (x.fm_from >= p.n_osc) {
			x.fm_from = -1;
		}
		if (x.sync >= p.n_osc) {
			x.sync = -1;
		}
		if (x.ring >= p.n_osc) {
			x.ring = -1;
		}
	}
	p.unison = std::clamp((int)num(d, "unison", 1), 1, ak::SynthPatch::MAX_U);
	p.spread = num(d, "spread", 0.0);
	p.unison_level = num(d, "unison_level", 1.0);
	p.unison_pitch = std::clamp(num(d, "unison_pitch", 0.0), -24.0, 24.0);
	Array tabs = d.get("tables", Array());
	for (int i = 0; i < tabs.size(); i++) {
		Dictionary t = tabs[i];
		auto tb = std::make_shared<ak::SynthPatch::Table>();
		tb->frames = std::max(1, (int)num(t, "frames", 1));
		tb->size = std::max(2, (int)num(t, "size", 1024));
		tb->levels = std::max(1, (int)num(t, "levels", 19));
		tb->zones = std::max(1, (int)num(t, "zones", 1));
		tb->lv0 = std::max(0, (int)num(t, "lv0", 0));
		tb->blend = (bool)t.get("blend", true);
		PackedFloat64Array keys = t.get("keys", PackedFloat64Array());
		tb->keys.assign(keys.ptr(), keys.ptr() + keys.size());
		if ((int)tb->keys.size() < tb->zones) {
			tb->zones = std::max(1, (int)tb->keys.size());
		}
		PackedFloat32Array data = t.get("data", PackedFloat32Array());
		tb->data.assign(data.ptr(), data.ptr() + data.size());
		if ((int)tb->data.size() < tb->zones * tb->frames * tb->levels * tb->size) {
			tb->data.resize(tb->zones * tb->frames * tb->levels * tb->size, 0.0f);
		}
		p.tables.push_back(tb);
	}
	PackedFloat64Array md = d.get("modes", PackedFloat64Array());
	p.n_modes = std::min((int)md.size() / 3, ak::SynthPatch::MAX_MODES);
	for (int k = 0; k < p.n_modes; k++) {
		p.mode_ratio[k] = md[3 * k];
		p.mode_level[k] = md[3 * k + 1];
		p.mode_decay[k] = md[3 * k + 2];
	}
	Array smps = d.get("samples", Array());
	for (int i = 0; i < smps.size(); i++) {
		Dictionary t = smps[i];
		auto sm = std::make_shared<ak::SynthPatch::Sample>();
		PackedFloat32Array data = t.get("data", PackedFloat32Array());
		sm->data.assign(data.ptr(), data.ptr() + data.size());
		sm->rate = std::max(1.0, num(t, "rate", 48000.0));
		sm->root = num(t, "root", 60.0);
		sm->loop = (bool)t.get("loop", false);
		sm->ls = num(t, "ls", 0.0);
		sm->le = num(t, "le", 0.0);
		sm->inc = sm->rate / (440.0 * std::pow(2.0, (sm->root - 69.0) / 12.0));
		p.samples.push_back(sm);
	}
	for (int i = 0; i < p.n_osc; i++) {
		if (p.osc[i].table >= (int)p.tables.size()) {
			p.osc[i].table = -1;
		}
		if (p.osc[i].sample >= (int)p.samples.size()) {
			p.osc[i].sample = -1;
		}
		if (p.osc[i].pbase + p.osc[i].pn > p.n_modes) {
			p.osc[i].pn = std::max(0, p.n_modes - p.osc[i].pbase);
		}
		if (p.osc[i].excite >= p.n_osc || p.osc[i].excite < -1) {
			p.osc[i].excite = -1;
		}
	}
	p.derive();
	p.detune_cents = num(d, "detune_cents", 0.0);
	parse_filt(d, p.f1);
	Dictionary f2 = d.get("f2", Dictionary());
	p.f2_on = !f2.is_empty() && (int)num(f2, "filter_type", 0) > 0;
	if (p.f2_on) {
		parse_filt(f2, p.f2);
	}
	p.routing = std::clamp((int)num(d, "routing", 0), 0, 1);
	PackedFloat64Array mac = d.get("macros", PackedFloat64Array());
	for (int i = 0; i < 4; i++) {
		p.macros[i] = i < mac.size() ? mac[i] : 0.0;
	}
	p.pre_lp_hz = num(d, "pre_lp_hz", 0.0);
	p.pre_hp_hz = num(d, "pre_hp_hz", 0.0);
	p.comb_on = (bool)d.get("comb_on", false);
	p.inc_max = num(d, "inc_max", 1e9);
	p.bl_sync = (bool)d.get("bl_sync", false);
	p.sinc_blep = (bool)d.get("sinc_blep", false);
	p.sat_g = num(d, "sat_g", 0.0);
	p.sat_tanh = (bool)d.get("sat_tanh", false);
	p.fb = num(d, "fb", 0.0);
	p.fb_on = (bool)d.get("fb_on", false);
	p.sat_c = std::max(1e-6, num(d, "sat_c", 1.0));
	p.comb_semis = num(d, "comb_semis", 0.0);
	p.comb_fb = std::clamp(num(d, "comb_fb", 0.0), -0.99, 0.99);
	p.comb_damp_hz = std::max(0.0, num(d, "comb_damp_hz", 0.0));
	p.drift_c = std::max(0.0, num(d, "drift_c", 0.0));
	p.drift_rate = std::clamp(num(d, "drift_rate", 0.5), 0.001, 50.0);
	p.comb_damp_track = std::clamp(num(d, "comb_damp_track", 0.0), 0.0, 1.0);
	PackedFloat64Array vp = d.get("voice_pan", PackedFloat64Array());
	for (int i = 0; i < ak::SynthPatch::MAX_SLOTS; i++) {
		p.voice_pan[i] = i < vp.size() ? vp[i] : 0.0;
	}
	p.slots = std::clamp((int)num(d, "slots", 0), 0, ak::SynthPatch::MAX_SLOTS);
	p.slop_pitch = num(d, "slop_pitch", 0.0);
	p.slop_cut = num(d, "slop_cut", 0.0);
	p.slop_time = num(d, "slop_time", 0.0);
	p.slop_level = num(d, "slop_level", 0.0);
	Array env = d.get("env", Array());
	p.n_env = std::clamp<int>(env.size(), 3, ak::SynthPatch::MAX_ENV);
	for (int k = 0; k < ak::SynthPatch::MAX_ENV && k < env.size(); k++) {
		Dictionary e = env[k];
		ak::SynthPatch::Env &x = p.env[k];
		x.kind = std::clamp((int)num(e, "kind", 0), 0, 4);
		x.a = num(e, "a", 0.0);
		x.d = num(e, "d", 0.2);
		x.s = num(e, "s", 0.0);
		x.r = num(e, "r", 0.15);
		x.r2 = num(e, "r2", 0.0);
		x.knee = num(e, "knee", 0.0);
		x.exp = (bool)e.get("exp", false);
		if (x.kind == 1) {
			PackedFloat64Array tm = e.get("time", PackedFloat64Array());
			PackedFloat64Array lv = e.get("level", PackedFloat64Array());
			PackedFloat64Array am = e.get("amount", PackedFloat64Array());
			PackedInt64Array cv = e.get("curve", PackedInt64Array());
			x.n = std::min<int>(tm.size(), ak::SynthPatch::MAX_STAGES);
			x.n = std::min<int>(x.n, std::min<int>(lv.size(), std::min<int>(am.size(), cv.size())));
			for (int i = 0; i < x.n; i++) {
				x.time[i] = tm[i];
				x.level[i] = lv[i];
				x.amount[i] = am[i];
				x.curve[i] = std::clamp((int)cv[i], 0, 2);
			}
			x.sustain = std::clamp((int)num(e, "sustain", x.n - 1), -1, x.n - 1);
			x.loop_a = (int)num(e, "loop_a", -1);
			x.loop_b = (int)num(e, "loop_b", -1);
			if (x.loop_a < 0 || x.loop_b < x.loop_a || x.loop_b > x.sustain) {
				x.loop_a = x.loop_b = -1;
			}
			x.quiet = std::clamp((int)num(e, "quiet", x.n), 0, x.n);
			x.trig = (bool)e.get("trig", false);
			x.start = num(e, "start", 0.0);
			x.tk = num(e, "tk", 0.0);
			x.tk_center = num(e, "tk_center", 60.0);
			x.tk_mask = (int64_t)e.get("tk_mask", (int64_t)-1);
			x.tv = num(e, "tv", 0.0);
			x.tv_mask = (int64_t)e.get("tv_mask", (int64_t)-1);
			x.lv = num(e, "lv", 0.0);
		} else if (x.kind == 4) {
			PackedInt64Array rt = e.get("rates", PackedInt64Array());
			PackedInt64Array lv = e.get("levels", PackedInt64Array());
			x.czk = std::clamp((int)num(e, "czk", 0), 0, 2);
			x.cz_n = std::min<int>(8, std::min<int>(rt.size(), lv.size()));
			for (int i = 0; i < x.cz_n; i++) {
				x.cz_rate[i] = std::clamp((int)rt[i], 0, 127);
				x.cz_level[i] = std::clamp((int)lv[i], 0, 127);
			}
			x.cz_end = std::clamp((int)num(e, "end", x.cz_n - 1), 0, std::max(0, x.cz_n - 1));
			x.cz_sus = std::clamp((int)num(e, "sustain", -1), -1, x.cz_end);
		} else if (x.kind == 3) {
			PackedInt64Array rt = e.get("rates", PackedInt64Array());
			PackedInt64Array lv = e.get("levels", PackedInt64Array());
			for (int i = 0; i < 4; i++) {
				x.rates[i] = i < rt.size() ? std::clamp((int)rt[i], 0, 99) : 99;
				x.levels[i] = i < lv.size() ? std::clamp((int)lv[i], 0, 99) : 50;
			}
		} else if (x.kind == 2) {
			PackedInt64Array rt = e.get("rates", PackedInt64Array());
			PackedInt64Array lv = e.get("levels", PackedInt64Array());
			for (int i = 0; i < 4; i++) {
				x.rates[i] = i < rt.size() ? std::clamp((int)rt[i], 0, 99) : 99;
				x.levels[i] = i < lv.size() ? std::clamp((int)lv[i], 0, 99) : 0;
			}
			x.ol = std::clamp((int)num(e, "ol", 99), 0, 99);
			x.rs = std::clamp((int)num(e, "rs", 0), 0, 7);
			x.vs = std::clamp((int)num(e, "vs", 0), 0, 7);
			x.bp = std::clamp((int)num(e, "bp", 39), 0, 99);
			x.ld = std::clamp((int)num(e, "ld", 0), 0, 99);
			x.rd = std::clamp((int)num(e, "rd", 0), 0, 99);
			x.lc = std::clamp((int)num(e, "lc", 0), 0, 3);
			x.rc = std::clamp((int)num(e, "rc", 0), 0, 3);
			x.ams = std::clamp((int)num(e, "ams", 0), 0, 3);
			x.ko = (int)num(e, "ko", 0);
		}
	}
	Array lfo = d.get("lfo", Array());
	p.n_lfo = std::clamp((int)num(d, "n_lfo", 2), 2, std::min<int>(ak::SynthPatch::MAX_LFO, std::max<int>(2, lfo.size())));
	for (int k = 0; k < ak::SynthPatch::MAX_LFO && k < lfo.size(); k++) {
		Dictionary l = lfo[k];
		p.lfo[k].shape = (int)num(l, "shape", 0);
		p.lfo[k].rate_hz = num(l, "rate_hz", 1.0);
		p.lfo[k].delay_s = num(l, "delay_s", 0.0);
		p.lfo[k].width = num(l, "width", 0.5);
		p.lfo[k].phase = num(l, "phase", 0.0);
		p.lfo[k].free = (bool)l.get("free", false);
		p.lfo[k].beats = num(l, "beats", 0.0);
		p.lfo[k].dx7 = (bool)l.get("dx7", false);
		p.lfo[k].speed = std::clamp((int)num(l, "speed", 35), 0, 99);
		p.lfo[k].delay = std::clamp((int)num(l, "delay", 0), 0, 99);
		p.lfo[k].wave = std::clamp((int)num(l, "wave", 0), 0, 5);
		p.lfo[k].sync = (bool)l.get("sync", true);
		p.lfo[k].pmd = std::clamp((int)num(l, "pmd", 0), 0, 99);
		p.lfo[k].pms = std::clamp((int)num(l, "pms", 0), 0, 7);
		p.lfo[k].amd = std::clamp((int)num(l, "amd", 0), 0, 99);
		PackedFloat64Array pts = l.get("points", PackedFloat64Array());
		p.lfo[k].pts.assign(pts.ptr(), pts.ptr() + pts.size());
		p.lfo[k].interp = std::clamp((int)num(l, "interp", 0), 0, 1);
		p.lfo[k].once = (bool)l.get("once", false);
	}
	Array mods = d.get("mods", Array());
	p.n_mods = std::min<int>(mods.size(), ak::SynthPatch::MAX_MODS);
	for (int r = 0; r < p.n_mods; r++) {
		Dictionary m = mods[r];
		p.mods[r].src = std::clamp((int)num(m, "src", 0), 0, ak::N_SRC - 1);
		p.mods[r].dst = std::clamp((int)num(m, "dst", 0), 0, ak::N_DST - 1);
		p.mods[r].osc = (int)num(m, "osc", -1);
		p.mods[r].amount = num(m, "amount", 0.0);
		p.mods[r].via = std::clamp((int)num(m, "via", -1), -1, ak::N_SRC - 1);
		p.mods[r].via2 = std::clamp((int)num(m, "via2", -1), -1, ak::N_SRC - 1);
	}
	p.mode = (int)num(d, "mode", 0);
	p.prio = std::clamp((int)num(d, "prio", 0), 0, 2);
	p.rzero = (bool)d.get("rzero", false);
	p.poly = std::clamp((int)num(d, "poly", 8), 1, 32);
	p.glide_s = num(d, "glide_s", 0.0);
	p.bend_range = num(d, "bend_range", 2.0);
	p.vel_sens = num(d, "vel_sens", 0.5);
	p.vel_curve = num(d, "vel_curve", 1.0);
	PackedFloat64Array kl = d.get("key_lv", PackedFloat64Array());
	p.key_lv.assign(kl.ptr(), kl.ptr() + kl.size());
	p.gain = num(d, "gain", 1.0);
	p.pan = num(d, "pan", 0.0);
	p.seed = (int64_t)d.get("seed", 0);
	p.tempo_bpm = std::clamp(num(d, "tempo_bpm", 120.0), 20.0, 400.0);
	Dictionary arp = d.get("arp", Dictionary());
	p.arp.on = (bool)arp.get("on", false);
	p.arp.mode = std::clamp((int)num(arp, "mode", 0), 0, 3);
	p.arp.octaves = std::clamp((int)num(arp, "octaves", 1), 1, 4);
	p.arp.beats = num(arp, "beats", 0.25);
	p.arp.gate = std::clamp(num(arp, "gate", 0.5), 0.01, 1.0);
	p.arp.on = p.arp.on && p.arp.beats > 0.0;
	Array fxs = d.get("effects", Array());
	for (int i = 0; i < fxs.size(); i++) {
		ak::Fx f = fx_from(fxs[i]);
		if (f.type != ak::Fx::NONE) {
			p.effects.push_back(f);
		}
	}
	return p;
}

void AKSynthStream::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_patch", "patch"), &AKSynthStream::set_patch);
	ClassDB::bind_method(D_METHOD("get_patch"), &AKSynthStream::get_patch);
	ClassDB::bind_method(D_METHOD("set_patch_data", "compiled"), &AKSynthStream::set_patch_data);
	ClassDB::bind_method(D_METHOD("note_on", "note", "velocity", "delay_s"), &AKSynthStream::note_on, DEFVAL(1.0), DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("note_off", "note", "delay_s"), &AKSynthStream::note_off, DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("set_bend", "value", "delay_s"), &AKSynthStream::set_bend, DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("set_mod_wheel", "value", "delay_s"), &AKSynthStream::set_mod_wheel, DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("set_aftertouch", "value", "delay_s"), &AKSynthStream::set_aftertouch, DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("set_sustain", "down", "delay_s"), &AKSynthStream::set_sustain, DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("all_notes_off", "delay_s"), &AKSynthStream::all_notes_off, DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("set_tempo", "bpm", "delay_s"), &AKSynthStream::set_tempo, DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("panic"), &AKSynthStream::panic);
	ClassDB::bind_method(D_METHOD("schedule", "frame", "type", "a", "b"), &AKSynthStream::schedule, DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("voice_count"), &AKSynthStream::voice_count);
	ClassDB::bind_method(D_METHOD("get_frame"), &AKSynthStream::get_frame);
	ClassDB::bind_method(D_METHOD("set_playing", "playing"), &AKSynthStream::set_playing);
	ClassDB::bind_method(D_METHOD("is_playing_now"), &AKSynthStream::is_playing_now);
	ClassDB::bind_method(D_METHOD("render_offline", "frames"), &AKSynthStream::render_offline);
	ClassDB::bind_method(D_METHOD("get_recent", "frames"), &AKSynthStream::get_recent);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "patch", PROPERTY_HINT_RESOURCE_TYPE, "AKPatch"), "set_patch", "get_patch");
}

Ref<AudioStreamPlayback> AKSynthStream::_instantiate_playback() const {
	Ref<AKSynthPlayback> p;
	p.instantiate();
	p->set_shared(shared);
	return p;
}

void AKSynthStream::set_patch(const Ref<Resource> &p) {
	if (patch.is_valid() && patch->is_connected("changed", callable_mp(this, &AKSynthStream::_patch_changed))) {
		patch->disconnect("changed", callable_mp(this, &AKSynthStream::_patch_changed));
	}
	patch = p;
	if (patch.is_valid()) {
		patch->connect("changed", callable_mp(this, &AKSynthStream::_patch_changed));
	}
	_patch_changed();
	emit_changed();
}

void AKSynthStream::_patch_changed() {
	if (patch.is_null()) {
		return;
	}
	if (!patch->has_method("compile")) {
		UtilityFunctions::push_error("AKSynthStream: the patch has no compile() (is it an AKPatch?)");
		return;
	}
	Dictionary d = patch->call("compile");
	set_patch_data(d);
}

void AKSynthStream::set_patch_data(const Dictionary &compiled) {
	ak::SynthPatch p = synth_patch_from(compiled);
	std::lock_guard<std::mutex> g(shared->mutex);
	shared->engine.set_patch(p);
}

int64_t AKSynthStream::_at(double delay_s) const {
	return shared->engine.frame + std::max<int64_t>(0, (int64_t)std::llround(delay_s * shared->engine.sr));
}

void AKSynthStream::note_on(double note, double velocity, double delay_s) {
	std::lock_guard<std::mutex> g(shared->mutex);
	shared->engine.queue(_at(delay_s), ak::SynthEngine::E_ON, note, velocity);
}

void AKSynthStream::note_off(double note, double delay_s) {
	std::lock_guard<std::mutex> g(shared->mutex);
	shared->engine.queue(_at(delay_s), ak::SynthEngine::E_OFF, note, 0.0);
}

void AKSynthStream::set_bend(double value, double delay_s) {
	std::lock_guard<std::mutex> g(shared->mutex);
	shared->engine.queue(_at(delay_s), ak::SynthEngine::E_BEND, value, 0.0);
}

void AKSynthStream::set_mod_wheel(double value, double delay_s) {
	std::lock_guard<std::mutex> g(shared->mutex);
	shared->engine.queue(_at(delay_s), ak::SynthEngine::E_MOD, value, 0.0);
}

void AKSynthStream::set_aftertouch(double value, double delay_s) {
	std::lock_guard<std::mutex> g(shared->mutex);
	shared->engine.queue(_at(delay_s), ak::SynthEngine::E_TOUCH, value, 0.0);
}

void AKSynthStream::set_sustain(bool down, double delay_s) {
	std::lock_guard<std::mutex> g(shared->mutex);
	shared->engine.queue(_at(delay_s), ak::SynthEngine::E_SUSTAIN, down ? 1.0 : 0.0, 0.0);
}

void AKSynthStream::all_notes_off(double delay_s) {
	std::lock_guard<std::mutex> g(shared->mutex);
	shared->engine.queue(_at(delay_s), ak::SynthEngine::E_ALL_OFF, 0.0, 0.0);
}

void AKSynthStream::set_tempo(double bpm, double delay_s) {
	std::lock_guard<std::mutex> g(shared->mutex);
	shared->engine.queue(_at(delay_s), ak::SynthEngine::E_TEMPO, bpm, 0.0);
}

void AKSynthStream::panic() {
	std::lock_guard<std::mutex> g(shared->mutex);
	shared->engine.clear_events();
	shared->engine.queue(shared->engine.frame, ak::SynthEngine::E_PANIC, 0.0, 0.0);
}

void AKSynthStream::schedule(int64_t frame, int type, double a, double b) {
	std::lock_guard<std::mutex> g(shared->mutex);
	shared->engine.queue(frame, type, a, b);
}

int AKSynthStream::voice_count() const {
	std::lock_guard<std::mutex> g(shared->mutex);
	return shared->engine.voice_count();
}

int64_t AKSynthStream::get_frame() const {
	std::lock_guard<std::mutex> g(shared->mutex);
	return shared->engine.frame;
}

void AKSynthStream::set_playing(bool p) {
	std::lock_guard<std::mutex> g(shared->mutex);
	shared->playing = p;
}

bool AKSynthStream::is_playing_now() const {
	std::lock_guard<std::mutex> g(shared->mutex);
	return shared->playing;
}

PackedFloat32Array AKSynthStream::get_recent(int frames) const {
	const int n = std::max(0, std::min(frames, SynthShared::SCOPE_SIZE));
	PackedFloat32Array out;
	out.resize(n);
	std::lock_guard<std::mutex> g(shared->mutex);
	int p = (shared->scope_pos - n + SynthShared::SCOPE_SIZE) % SynthShared::SCOPE_SIZE;
	float *w = out.ptrw();
	for (int i = 0; i < n; i++) {
		w[i] = shared->scope[p];
		p = (p + 1) % SynthShared::SCOPE_SIZE;
	}
	return out;
}

Array AKSynthStream::render_offline(int frames) {
	PackedFloat32Array l, r;
	l.resize(std::max(0, frames));
	r.resize(std::max(0, frames));
	l.fill(0.0f);
	r.fill(0.0f);
	{
		std::lock_guard<std::mutex> g(shared->mutex);
		const int block = 512;
		for (int i = 0; i < frames; i += block) {
			const int n = std::min(block, frames - i);
			shared->engine.render(l.ptrw() + i, r.ptrw() + i, n);
			shared->tap(l.ptr() + i, r.ptr() + i, n);
		}
	}
	Array res;
	res.push_back(l);
	res.push_back(r);
	return res;
}

// ------------------------------------------------------------------ playback

void AKSynthPlayback::_start(double from_pos) {
	{
		std::lock_guard<std::mutex> g(shared->mutex);
		shared->playing = true;
	}
	begin_resample();
}

void AKSynthPlayback::_stop() {
	std::lock_guard<std::mutex> g(shared->mutex);
	shared->playing = false;
}

bool AKSynthPlayback::_is_playing() const {
	std::lock_guard<std::mutex> g(shared->mutex);
	return shared->playing;
}

double AKSynthPlayback::_get_playback_position() const {
	std::lock_guard<std::mutex> g(shared->mutex);
	return double(shared->engine.frame) / shared->engine.sr;
}

int32_t AKSynthPlayback::_mix_resampled(AudioFrame *dst, int32_t frames) {
	if ((int)tl.size() < frames) {
		tl.resize(frames);
		tr.resize(frames);
	}
	std::fill(tl.begin(), tl.begin() + frames, 0.0f);
	std::fill(tr.begin(), tr.begin() + frames, 0.0f);
	{
		std::lock_guard<std::mutex> g(shared->mutex);
		if (shared->playing) {
			shared->engine.render(tl.data(), tr.data(), frames);
		}
		shared->tap(tl.data(), tr.data(), frames);
	}
	for (int i = 0; i < frames; i++) {
		dst[i].left = tl[i];
		dst[i].right = tr[i];
	}
	return frames;
}

float AKSynthPlayback::_get_stream_sampling_rate() const {
	return (float)shared->engine.sr;
}
