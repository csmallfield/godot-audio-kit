// SPDX-License-Identifier: Apache-2.0
#include "ak_live.h"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

void AKLiveStream::_bind_methods() {
	ClassDB::bind_method(D_METHOD("add_buffer", "l", "r"), &AKLiveStream::add_buffer);
	ClassDB::bind_method(D_METHOD("remove_buffer", "id"), &AKLiveStream::remove_buffer);
	ClassDB::bind_method(D_METHOD("buffer_count"), &AKLiveStream::buffer_count);
	ClassDB::bind_method(D_METHOD("schedule", "buffer", "at_frame", "gain_l", "gain_r", "send", "tag", "bus"), &AKLiveStream::schedule, DEFVAL(1.0), DEFVAL(1.0), DEFVAL(0.0), DEFVAL(0), DEFVAL(0));
	ClassDB::bind_method(D_METHOD("play_now", "buffer", "gain_l", "gain_r", "send", "delay_frames", "bus"), &AKLiveStream::play_now, DEFVAL(1.0), DEFVAL(1.0), DEFVAL(0.0), DEFVAL(0), DEFVAL(0));
	ClassDB::bind_method(D_METHOD("cancel_after", "tag", "from_frame"), &AKLiveStream::cancel_after);
	ClassDB::bind_method(D_METHOD("set_bus_gain", "id", "gain", "glide_s"), &AKLiveStream::set_bus_gain, DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("set_bus_duck", "id", "source", "depth_db", "full", "attack_s", "release_s"), &AKLiveStream::set_bus_duck);
	ClassDB::bind_method(D_METHOD("cancel", "tag"), &AKLiveStream::cancel);
	ClassDB::bind_method(D_METHOD("clear"), &AKLiveStream::clear);
	ClassDB::bind_method(D_METHOD("hit_count"), &AKLiveStream::hit_count);
	ClassDB::bind_method(D_METHOD("set_reverb", "enabled", "room", "damp", "width", "small", "return_gain"), &AKLiveStream::set_reverb);
	ClassDB::bind_method(D_METHOD("set_chain", "steps"), &AKLiveStream::set_chain);
	ClassDB::bind_method(D_METHOD("set_reverb_params", "room", "damp", "width", "return_gain", "glide_s"), &AKLiveStream::set_reverb_params);
	ClassDB::bind_method(D_METHOD("voice_start", "params"), &AKLiveStream::voice_start);
	ClassDB::bind_method(D_METHOD("voice_set", "id", "param", "value", "glide_s"), &AKLiveStream::voice_set, DEFVAL(0.05));
	ClassDB::bind_method(D_METHOD("voice_stop", "id", "release_s"), &AKLiveStream::voice_stop, DEFVAL(0.1));
	ClassDB::bind_method(D_METHOD("voice_count"), &AKLiveStream::voice_count);
	ClassDB::bind_method(D_METHOD("get_frame"), &AKLiveStream::get_frame);
	ClassDB::bind_method(D_METHOD("seek_frame", "frame"), &AKLiveStream::seek_frame);
	ClassDB::bind_method(D_METHOD("set_playing", "playing"), &AKLiveStream::set_playing);
	ClassDB::bind_method(D_METHOD("is_playing_now"), &AKLiveStream::is_playing_now);
	ClassDB::bind_method(D_METHOD("render_offline", "frames"), &AKLiveStream::render_offline);
}

Ref<AudioStreamPlayback> AKLiveStream::_instantiate_playback() const {
	Ref<AKLivePlayback> p;
	p.instantiate();
	p->set_core(core);
	return p;
}

int AKLiveStream::add_buffer(const PackedFloat32Array &l, const PackedFloat32Array &r) {
	auto b = std::make_shared<ak::LiveCore::Buf>();
	const int n = std::min(l.size(), r.size());
	b->l.assign(l.ptr(), l.ptr() + n);
	b->r.assign(r.ptr(), r.ptr() + n);
	std::lock_guard<std::mutex> g(core->mutex);
	const int id = core->next_buf++;
	core->bufs[id] = b;
	return id;
}

void AKLiveStream::remove_buffer(int id) {
	std::lock_guard<std::mutex> g(core->mutex);
	core->bufs.erase(id);
}

int AKLiveStream::buffer_count() const {
	std::lock_guard<std::mutex> g(core->mutex);
	return (int)core->bufs.size();
}

void AKLiveStream::schedule(int buffer, int64_t at_frame, double gain_l, double gain_r, double send, int tag, int bus) {
	std::lock_guard<std::mutex> g(core->mutex);
	auto it = core->bufs.find(buffer);
	if (it == core->bufs.end()) {
		UtilityFunctions::push_error("AKLiveStream: no buffer ", buffer);
		return;
	}
	core->hits.push_back({ it->second, at_frame, (float)gain_l, (float)gain_r, (float)send, tag, false, bus });
}

void AKLiveStream::play_now(int buffer, double gain_l, double gain_r, double send, int64_t delay_frames, int bus) {
	std::lock_guard<std::mutex> g(core->mutex);
	auto it = core->bufs.find(buffer);
	if (it == core->bufs.end()) {
		UtilityFunctions::push_error("AKLiveStream: no buffer ", buffer);
		return;
	}
	core->hits.push_back({ it->second, core->frame + std::max<int64_t>(0, delay_frames), (float)gain_l, (float)gain_r, (float)send, -1, true, bus });
}

void AKLiveStream::cancel(int tag) {
	std::lock_guard<std::mutex> g(core->mutex);
	auto &h = core->hits;
	h.erase(std::remove_if(h.begin(), h.end(), [tag](const ak::LiveCore::Hit &x) { return x.tag == tag; }), h.end());
}

void AKLiveStream::cancel_after(int tag, int64_t from_frame) {
	std::lock_guard<std::mutex> g(core->mutex);
	auto &h = core->hits;
	h.erase(std::remove_if(h.begin(), h.end(), [tag, from_frame](const ak::LiveCore::Hit &x) { return x.tag == tag && x.at >= from_frame; }), h.end());
}

void AKLiveStream::set_bus_gain(int id, double gain, double glide_s) {
	std::lock_guard<std::mutex> g(core->mutex);
	ak::LiveCore::Bus &b = core->bus(id);
	if (glide_s <= 0.0) {
		b.gain.reset(gain);
	} else {
		b.gain.set(gain, glide_s, core->sr);
	}
}

void AKLiveStream::set_bus_duck(int id, int source, double depth_db, double full, double attack_s, double release_s) {
	std::lock_guard<std::mutex> g(core->mutex);
	ak::LiveCore::Bus &b = core->bus(id);
	b.duck_source = depth_db > 0.0 ? source : -1;
	b.duck.setup(core->sr, depth_db, full, attack_s, release_s);
}

void AKLiveStream::clear() {
	std::lock_guard<std::mutex> g(core->mutex);
	core->hits.clear();
}

int AKLiveStream::hit_count() const {
	std::lock_guard<std::mutex> g(core->mutex);
	return (int)core->hits.size();
}

void AKLiveStream::set_reverb(bool enabled, double room, double damp, double width, bool small, double return_gain) {
	ak::Freeverb fv;
	if (enabled) {
		fv.setup(core->sr, room, damp, width, small);
	}
	std::lock_guard<std::mutex> g(core->mutex);
	core->reverb_on = enabled;
	core->rv_room = room;
	core->rv_damp = damp;
	core->rv_width = width;
	core->rv_small = small;
	core->rv_return = return_gain;
	core->reverb = std::move(fv);
	core->z_fb.reset(core->reverb.fb);
	core->z_damp.reset(core->reverb.damp);
	core->z_width.reset(width);
	core->z_ret.reset(return_gain);
	core->z_moving = false;
}

void AKLiveStream::set_reverb_params(double room, double damp, double width, double return_gain, double glide_s) {
	std::lock_guard<std::mutex> g(core->mutex);
	room = std::clamp(room, 0.0, 1.0);
	damp = std::clamp(damp, 0.0, 1.0);
	const int sr = core->sr;
	const double gl = std::max(glide_s, 1e-4);
	core->z_fb.set(room * 0.28 + 0.7, gl, sr);
	core->z_damp.set(damp * 0.4, gl, sr);
	core->z_width.set(width, gl, sr);
	core->z_ret.set(return_gain, gl, sr);
	core->rv_room = room;
	core->rv_damp = damp;
	core->rv_width = width;
	core->z_moving = true;
}

void AKLiveStream::set_chain(const Array &steps) {
	std::vector<ak::ChainStep> chain;
	const int sr = core->sr;
	for (int i = 0; i < steps.size(); i++) {
		Dictionary d = steps[i];
		String type = d.get("type", "");
		ak::ChainStep s;
		if (type == "gain") {
			s.type = ak::ChainStep::GAIN;
			s.gain = d.get("gain", 1.0);
		} else if (type == "highpass1" || type == "lowpass1") {
			s.type = type == "highpass1" ? ak::ChainStep::HIGHPASS1 : ak::ChainStep::LOWPASS1;
			double fc = d.get("cutoff_hz", 10.0);
			s.coef = 1.0 - std::exp(-ak::TAU / sr * fc);
		} else if (type == "svf") {
			s.type = ak::ChainStep::SVF_FILTER;
			s.mode = (int)d.get("mode", 0);
			s.cutoff = d.get("cutoff_hz", 1000.0);
			s.q = d.get("q", 0.707);
			s.stages = std::clamp((int)d.get("stages", 1), 1, 2);
		} else if (type == "limit") {
			s.type = ak::ChainStep::LIMIT;
			s.ceiling = d.get("ceiling", 1.0);
			s.release_k = d.get("release_k", 0.0);
		} else if (type == "room") {
			s.type = ak::ChainStep::ROOM;
			s.room = d.get("room", 0.5);
			s.damp = d.get("damp", 0.5);
			s.width = d.get("width", 1.0);
			s.mix = d.get("mix", 0.2);
			s.small = d.get("small", false);
		} else if (type == "echo") {
			s.type = ak::ChainStep::ECHO;
			int dly = std::max(1, (int)d.get("delay", 12000));
			s.line[0].assign(dly, 0.0f);
			s.line[1].assign(dly, 0.0f);
			s.fb = std::clamp((double)d.get("feedback", 0.35), 0.0, 0.95);
			s.mix = d.get("mix", 0.3);
		} else if (type == "drive") {
			s.type = ak::ChainStep::DRIVE;
			s.k = 1.0 + std::clamp((double)d.get("amount", 0.3), 0.0, 1.0) * 19.0;
			s.norm = 1.0 / std::tanh(s.k);
		} else if (type == "bitcrush") {
			s.type = ak::ChainStep::BITCRUSH;
			s.steps = std::pow(2.0, std::clamp((double)d.get("bits", 8.0), 1.0, 24.0) - 1.0);
			s.hold = std::max(1, (int)d.get("hold", 1));
		} else if (type == "fade_end") {
			s.type = ak::ChainStep::FADE_END;
			s.start = (int64_t)d.get("start", 0);
			s.end = (int64_t)d.get("end", 0);
		} else {
			UtilityFunctions::push_error("AKLiveStream: unknown chain step '", type, "'");
			continue;
		}
		s.reset(sr);
		chain.push_back(s);
	}
	std::lock_guard<std::mutex> g(core->mutex);
	core->chain = std::move(chain);
}

int AKLiveStream::voice_start(const Dictionary &p) {
	ak::LiveVoice v;
	String shape = p.get("shape", "sine");
	v.shape = shape == "saw" ? ak::LiveVoice::SAW : shape == "square" ? ak::LiveVoice::SQUARE : shape == "triangle" ? ak::LiveVoice::TRIANGLE : shape == "noise" ? ak::LiveVoice::NOISE : shape == "loop" ? ak::LiveVoice::LOOP : ak::LiveVoice::SINE;
	v.rate.reset(p.get("rate", 1.0));
	v.pitch.reset(p.get("pitch", 1.0));
	v.pos = std::max(0.0, (double)p.get("start_frame", 0.0));
	const int sr = core->sr;
	v.freq.reset(p.get("freq_hz", 220.0));
	v.gain.reset(0.0);
	v.gain.set(p.get("gain", 0.5), std::max(0.001, (double)p.get("attack_s", 0.01)), sr);
	double cut = p.get("cutoff_hz", 0.0);
	v.filtered = cut > 0.0;
	v.cutoff.reset(cut > 0.0 ? cut : 20000.0);
	v.q.reset(p.get("q", 0.707));
	v.pan.reset(p.get("pan", 0.0));
	v.send.reset(p.get("send", 0.0));
	v.width.reset(p.get("width", 0.5));
	v.noise.reset(p.get("noise", 0.0));
	v.bus = (int)p.get("bus", 0);
	v.rng ^= (uint32_t)(int)p.get("seed", 0) * 2654435761u;
	if (v.rng == 0) {
		v.rng = 1;
	}
	v.filt.set_q(v.q.v);
	v.filt.set_cutoff(v.cutoff.v, sr);
	std::lock_guard<std::mutex> g(core->mutex);
	if (v.shape == ak::LiveVoice::LOOP) {
		auto it = core->bufs.find((int)p.get("buffer", -1));
		if (it == core->bufs.end()) {
			UtilityFunctions::push_error("AKLiveStream: loop voice needs a registered buffer");
			return -1;
		}
		v.loop = it->second;
	}
	const int id = core->next_voice++;
	core->voices[id] = v;
	return id;
}

void AKLiveStream::voice_set(int id, const String &param, double value, double glide_s) {
	std::lock_guard<std::mutex> g(core->mutex);
	auto it = core->voices.find(id);
	if (it == core->voices.end()) {
		return;
	}
	ak::LiveVoice &v = it->second;
	const int sr = core->sr;
	ak::Smooth *s = param == "freq_hz" ? &v.freq : param == "gain" ? &v.gain : param == "cutoff_hz" ? &v.cutoff : param == "q" ? &v.q : param == "pan" ? &v.pan : param == "send" ? &v.send : param == "width" ? &v.width : param == "noise" ? &v.noise : param == "rate" ? &v.rate : param == "pitch" ? &v.pitch : nullptr;
	if (s == nullptr) {
		UtilityFunctions::push_error("AKLiveStream: unknown voice parameter '", param, "'");
		return;
	}
	if (s == &v.cutoff && !v.filtered) {
		v.filtered = true;
		v.cutoff.reset(value);
	}
	s->set(value, glide_s, sr);
}

void AKLiveStream::voice_stop(int id, double release_s) {
	std::lock_guard<std::mutex> g(core->mutex);
	auto it = core->voices.find(id);
	if (it == core->voices.end()) {
		return;
	}
	it->second.releasing = true;
	it->second.release_k = std::exp(-1.0 / std::max(1.0, release_s * core->sr));
}

int AKLiveStream::voice_count() const {
	std::lock_guard<std::mutex> g(core->mutex);
	return (int)core->voices.size();
}

int64_t AKLiveStream::get_frame() const {
	std::lock_guard<std::mutex> g(core->mutex);
	return core->frame;
}

void AKLiveStream::seek_frame(int64_t frame) {
	std::lock_guard<std::mutex> g(core->mutex);
	core->seek(frame);
}

void AKLiveStream::set_playing(bool p) {
	std::lock_guard<std::mutex> g(core->mutex);
	core->playing = p;
}

bool AKLiveStream::is_playing_now() const {
	std::lock_guard<std::mutex> g(core->mutex);
	return core->playing;
}

Array AKLiveStream::render_offline(int frames) {
	PackedFloat32Array l, r;
	l.resize(std::max(0, frames));
	r.resize(std::max(0, frames));
	{
		std::lock_guard<std::mutex> g(core->mutex);
		float *pl = l.ptrw();
		float *pr = r.ptrw();
		const int block = 512;
		for (int i = 0; i < frames; i += block) {
			core->render(pl + i, pr + i, std::min(block, frames - i));
		}
	}
	Array res;
	res.push_back(l);
	res.push_back(r);
	return res;
}

// ------------------------------------------------------------------ playback

void AKLivePlayback::_start(double from_pos) {
	{
		std::lock_guard<std::mutex> g(core->mutex);
		core->seek((int64_t)std::llround(from_pos * core->sr));
		core->playing = true;
	}
	begin_resample();
}

void AKLivePlayback::_stop() {
	std::lock_guard<std::mutex> g(core->mutex);
	core->playing = false;
}

bool AKLivePlayback::_is_playing() const {
	std::lock_guard<std::mutex> g(core->mutex);
	return core->playing;
}

double AKLivePlayback::_get_playback_position() const {
	std::lock_guard<std::mutex> g(core->mutex);
	return double(core->frame) / core->sr;
}

void AKLivePlayback::_seek(double pos) {
	{
		std::lock_guard<std::mutex> g(core->mutex);
		core->seek((int64_t)std::llround(pos * core->sr));
	}
	begin_resample();
}

int32_t AKLivePlayback::_mix_resampled(AudioFrame *dst, int32_t frames) {
	if ((int)tl.size() < frames) {
		tl.resize(frames);
		tr.resize(frames);
	}
	{
		std::lock_guard<std::mutex> g(core->mutex);
		if (!core->playing) {
			for (int i = 0; i < frames; i++) {
				dst[i].left = 0.0f;
				dst[i].right = 0.0f;
			}
			return frames;
		}
		core->render(tl.data(), tr.data(), frames);
	}
	for (int i = 0; i < frames; i++) {
		dst[i].left = tl[i];
		dst[i].right = tr[i];
	}
	return frames;
}

float AKLivePlayback::_get_stream_sampling_rate() const {
	return (float)core->sr;
}
