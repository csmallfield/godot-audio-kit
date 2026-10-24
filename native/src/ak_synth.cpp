// SPDX-License-Identifier: Apache-2.0
#include "ak_synth.h"

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
		x.width = num(o, "width", 0.5);
		x.position = num(o, "position", 0.0);
		x.fm_from = (int)num(o, "fm_from", -1);
		x.fm_index = num(o, "fm_index", 0.0);
		if (x.fm_from >= p.n_osc) {
			x.fm_from = -1;
		}
	}
	p.unison = std::clamp((int)num(d, "unison", 1), 1, ak::SynthPatch::MAX_U);
	p.detune_cents = num(d, "detune_cents", 0.0);
	p.filter_type = (int)num(d, "filter_type", 1);
	p.cutoff_hz = num(d, "cutoff_hz", 18000.0);
	p.q = num(d, "q", 0.707);
	p.stages = std::clamp((int)num(d, "stages", 1), 1, 2);
	Array env = d.get("env", Array());
	for (int k = 0; k < 3 && k < env.size(); k++) {
		Dictionary e = env[k];
		p.env[k].a = num(e, "a", 0.0);
		p.env[k].d = num(e, "d", 0.2);
		p.env[k].s = num(e, "s", 0.0);
		p.env[k].r = num(e, "r", 0.15);
		p.env[k].exp = (bool)e.get("exp", false);
	}
	Array lfo = d.get("lfo", Array());
	for (int k = 0; k < 2 && k < lfo.size(); k++) {
		Dictionary l = lfo[k];
		p.lfo[k].shape = (int)num(l, "shape", 0);
		p.lfo[k].rate_hz = num(l, "rate_hz", 1.0);
		p.lfo[k].delay_s = num(l, "delay_s", 0.0);
	}
	Array mods = d.get("mods", Array());
	p.n_mods = std::min<int>(mods.size(), ak::SynthPatch::MAX_MODS);
	for (int r = 0; r < p.n_mods; r++) {
		Dictionary m = mods[r];
		p.mods[r].src = std::clamp((int)num(m, "src", 0), 0, 10);
		p.mods[r].dst = std::clamp((int)num(m, "dst", 0), 0, 9);
		p.mods[r].osc = (int)num(m, "osc", -1);
		p.mods[r].amount = num(m, "amount", 0.0);
	}
	p.mode = (int)num(d, "mode", 0);
	p.poly = std::clamp((int)num(d, "poly", 8), 1, 32);
	p.glide_s = num(d, "glide_s", 0.0);
	p.bend_range = num(d, "bend_range", 2.0);
	p.vel_sens = num(d, "vel_sens", 0.5);
	p.gain = num(d, "gain", 1.0);
	p.pan = num(d, "pan", 0.0);
	p.seed = (int64_t)d.get("seed", 0);
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
	ClassDB::bind_method(D_METHOD("all_notes_off", "delay_s"), &AKSynthStream::all_notes_off, DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("panic"), &AKSynthStream::panic);
	ClassDB::bind_method(D_METHOD("schedule", "frame", "type", "a", "b"), &AKSynthStream::schedule, DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("voice_count"), &AKSynthStream::voice_count);
	ClassDB::bind_method(D_METHOD("get_frame"), &AKSynthStream::get_frame);
	ClassDB::bind_method(D_METHOD("set_playing", "playing"), &AKSynthStream::set_playing);
	ClassDB::bind_method(D_METHOD("is_playing_now"), &AKSynthStream::is_playing_now);
	ClassDB::bind_method(D_METHOD("render_offline", "frames"), &AKSynthStream::render_offline);
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

void AKSynthStream::all_notes_off(double delay_s) {
	std::lock_guard<std::mutex> g(shared->mutex);
	shared->engine.queue(_at(delay_s), ak::SynthEngine::E_ALL_OFF, 0.0, 0.0);
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
			shared->engine.render(l.ptrw() + i, r.ptrw() + i, std::min(block, frames - i));
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
