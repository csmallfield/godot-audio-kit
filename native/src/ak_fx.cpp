// SPDX-License-Identifier: Apache-2.0
#include "ak_fx.h"

#include <godot_cpp/classes/audio_server.hpp>
#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

namespace {

struct Knob {
	const char *name;
	double def, lo, hi;
	bool integer;
	const char *doc;
};

struct TypeKnobs {
	const char *type;
	int index;
	std::vector<Knob> knobs;
};

// As AKStreamFx.DEFAULTS (keep the two in step), with the inspector's ranges.
const std::vector<TypeKnobs> &tables() {
	static const std::vector<TypeKnobs> t = {
		{ "chorus", ak::Fx::CHORUS, { { "rate_hz", 0.8, 0.01, 10.0, false, "" }, { "depth_ms", 3.0, 0.0, 20.0, false, "" },
				{ "delay_ms", 12.0, 0.5, 40.0, false, "" }, { "voices", 2, 1, 4, true, "" }, { "mix", 0.5, 0.0, 1.0, false, "" },
				{ "spread", 1.0, 0.0, 2.0, false, "" }, { "feedback", 0.0, -0.95, 0.95, false, "" } } },
		{ "flanger", ak::Fx::FLANGER, { { "rate_hz", 0.25, 0.01, 10.0, false, "" }, { "depth_ms", 2.0, 0.0, 10.0, false, "" },
				{ "delay_ms", 1.0, 0.05, 10.0, false, "" }, { "voices", 1, 1, 4, true, "" }, { "mix", 0.5, 0.0, 1.0, false, "" },
				{ "spread", 1.0, 0.0, 2.0, false, "" }, { "feedback", 0.6, -0.95, 0.95, false, "" } } },
		{ "phaser", ak::Fx::PHASER, { { "rate_hz", 0.4, 0.01, 10.0, false, "" }, { "stages", 4, 1, 12, true, "" },
				{ "center_hz", 800.0, 50.0, 8000.0, false, "" }, { "range_octaves", 2.0, 0.0, 6.0, false, "" },
				{ "depth", 1.0, 0.0, 1.0, false, "" }, { "feedback", 0.4, -0.95, 0.95, false, "" }, { "mix", 0.5, 0.0, 1.0, false, "" },
				{ "spread", 1.0, 0.0, 2.0, false, "" } } },
		{ "eq", ak::Fx::EQ, { { "low_db", 0.0, -24.0, 24.0, false, "" }, { "low_hz", 120.0, 20.0, 1000.0, false, "" },
				{ "mid_db", 0.0, -24.0, 24.0, false, "" }, { "mid_hz", 1000.0, 100.0, 10000.0, false, "" },
				{ "mid_q", 0.7, 0.1, 10.0, false, "" }, { "high_db", 0.0, -24.0, 24.0, false, "" }, { "high_hz", 6000.0, 1000.0, 20000.0, false, "" } } },
		{ "compressor", ak::Fx::COMPRESSOR, { { "threshold_db", -18.0, -60.0, 0.0, false, "" }, { "ratio", 4.0, 1.0, 20.0, false, "" },
				{ "attack_s", 0.01, 0.0001, 1.0, false, "" }, { "release_s", 0.12, 0.001, 3.0, false, "" },
				{ "knee_db", 6.0, 0.0, 24.0, false, "" }, { "makeup_db", 0.0, -12.0, 24.0, false, "" } } },
		{ "saturate", ak::Fx::SATURATE, { { "drive_db", 12.0, 0.0, 36.0, false, "" }, { "tone_hz", 6000.0, 200.0, 20000.0, false, "" },
				{ "asymmetry", 0.0, -1.0, 1.0, false, "" }, { "mix", 1.0, 0.0, 1.0, false, "" }, { "output_db", 0.0, -24.0, 12.0, false, "" } } },
	};
	return t;
}

const TypeKnobs *table_for(const String &type) {
	for (const TypeKnobs &t : tables()) {
		if (type == t.type) {
			return &t;
		}
	}
	return nullptr;
}

double num(const Dictionary &d, const char *k, double def) {
	return d.has(k) ? (double)d[k] : def;
}

} // namespace

// The compiled spec's numbers, clamped as AKStreamFx.compile does.
ak::Fx godot::fx_from(const Dictionary &c) {
	ak::Fx f;
	f.type = (int)num(c, "type", 0);
	f.rate_hz = num(c, "rate_hz", 0.0);
	f.depth_ms = std::max(0.0, num(c, "depth_ms", 0.0));
	f.delay_ms = std::max(num(c, "delay_ms", 1.0), 1000.0 / 48000.0);
	f.feedback = std::clamp(num(c, "feedback", 0.0), -0.95, 0.95);
	f.mix = std::clamp(num(c, "mix", 0.5), 0.0, 1.0);
	f.spread = num(c, "spread", 1.0);
	f.voices = std::clamp((int)num(c, "voices", 1), 1, 4);
	f.stages = std::clamp((int)num(c, "stages", 4), 1, 12);
	f.center_hz = num(c, "center_hz", 800.0);
	f.range_oct = num(c, "range_octaves", 2.0);
	f.depth = num(c, "depth", 1.0);
	f.low_db = num(c, "low_db", 0.0);
	f.low_hz = num(c, "low_hz", 120.0);
	f.mid_db = num(c, "mid_db", 0.0);
	f.mid_hz = num(c, "mid_hz", 1000.0);
	f.mid_q = num(c, "mid_q", 0.7);
	f.high_db = num(c, "high_db", 0.0);
	f.high_hz = num(c, "high_hz", 6000.0);
	f.threshold_db = num(c, "threshold_db", -18.0);
	f.ratio = std::max(1.0, num(c, "ratio", 4.0));
	f.attack_s = num(c, "attack_s", 0.01);
	f.release_s = num(c, "release_s", 0.12);
	f.knee_db = num(c, "knee_db", 6.0);
	f.makeup_db = num(c, "makeup_db", 0.0);
	f.drive_db = num(c, "drive_db", 12.0);
	f.tone_hz = num(c, "tone_hz", 6000.0);
	f.asymmetry = num(c, "asymmetry", 0.0);
	f.output_db = num(c, "output_db", 0.0);
	return f;
}

// ------------------------------------------------------------------ AKBusEffect

void AKBusEffect::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_spec"), &AKBusEffect::get_spec);
	ClassDB::bind_method(D_METHOD("process_offline", "l", "r", "sr"), &AKBusEffect::process_offline);
}

void AKBusEffect::init_defaults() {
	const TypeKnobs *t = table_for(fx_type());
	if (!t) {
		return;
	}
	for (const Knob &k : t->knobs) {
		knobs[k.name] = k.integer ? Variant((int64_t)k.def) : Variant(k.def);
	}
}

bool AKBusEffect::_set(const StringName &p_name, const Variant &p_value) {
	const TypeKnobs *t = table_for(fx_type());
	if (!t) {
		return false;
	}
	const String n = p_name;
	for (const Knob &k : t->knobs) {
		if (n == k.name) {
			std::lock_guard<std::mutex> g(mutex);
			knobs[k.name] = k.integer ? Variant((int64_t)p_value) : Variant((double)p_value);
			version++;
			emit_changed();
			return true;
		}
	}
	return false;
}

bool AKBusEffect::_get(const StringName &p_name, Variant &r_ret) const {
	const String n = p_name;
	std::lock_guard<std::mutex> g(mutex);
	if (knobs.has(n)) {
		r_ret = knobs[n];
		return true;
	}
	return false;
}

void AKBusEffect::_get_property_list(List<PropertyInfo> *p_list) const {
	const TypeKnobs *t = table_for(fx_type());
	if (!t) {
		return;
	}
	for (const Knob &k : t->knobs) {
		String hint = String::num(k.lo) + "," + String::num(k.hi) + "," + (k.integer ? "1" : "0.001");
		p_list->push_back(PropertyInfo(k.integer ? Variant::INT : Variant::FLOAT, k.name, PROPERTY_HINT_RANGE, hint));
	}
}

bool AKBusEffect::_property_can_revert(const StringName &p_name) const {
	const TypeKnobs *t = table_for(fx_type());
	if (!t) {
		return false;
	}
	const String n = p_name;
	for (const Knob &k : t->knobs) {
		if (n == k.name) {
			return true;
		}
	}
	return false;
}

bool AKBusEffect::_property_get_revert(const StringName &p_name, Variant &r_property) const {
	const TypeKnobs *t = table_for(fx_type());
	if (!t) {
		return false;
	}
	const String n = p_name;
	for (const Knob &k : t->knobs) {
		if (n == k.name) {
			r_property = k.integer ? Variant((int64_t)k.def) : Variant(k.def);
			return true;
		}
	}
	return false;
}

Dictionary AKBusEffect::get_spec() const {
	std::lock_guard<std::mutex> g(mutex);
	Dictionary d = knobs.duplicate();
	d["type"] = fx_type();
	return d;
}

ak::Fx AKBusEffect::make_fx(int sr, int &r_version) const {
	Dictionary c;
	{
		std::lock_guard<std::mutex> g(mutex);
		c = knobs.duplicate();
		r_version = version.load();
	}
	const TypeKnobs *t = table_for(fx_type());
	c["type"] = t ? t->index : 0;
	ak::Fx f = fx_from(c);
	f.setup(sr);
	return f;
}

Ref<AudioEffectInstance> AKBusEffect::_instantiate() {
	Ref<AKBusEffectInstance> inst;
	inst.instantiate();
	AudioServer *as = AudioServer::get_singleton();
	inst->set_effect(Ref<AKBusEffect>(this), as ? (int)as->get_mix_rate() : 48000);
	return inst;
}

Array AKBusEffect::process_offline(const PackedFloat32Array &l, const PackedFloat32Array &r, int sr) {
	Ref<AKBusEffectInstance> inst;
	inst.instantiate();
	inst->set_effect(Ref<AKBusEffect>(this), sr);
	const int n = std::min(l.size(), r.size());
	std::vector<AudioFrame> in(512), out(512);
	PackedFloat32Array ol, orr;
	ol.resize(n);
	orr.resize(n);
	for (int i = 0; i < n; i += 512) {
		const int m = std::min(512, n - i);
		for (int j = 0; j < m; j++) {
			in[j].left = l[i + j];
			in[j].right = r[i + j];
		}
		inst->_process(in.data(), out.data(), m);
		for (int j = 0; j < m; j++) {
			ol.set(i + j, out[j].left);
			orr.set(i + j, out[j].right);
		}
	}
	Array res;
	res.push_back(ol);
	res.push_back(orr);
	return res;
}

// ------------------------------------------------------------------ instance

void AKBusEffectInstance::_process(const void *p_src_buffer, AudioFrame *p_dst_buffer, int32_t p_frame_count) {
	const AudioFrame *src = (const AudioFrame *)p_src_buffer;
	if (effect.is_valid() && effect->get_version() != seen) {
		// New settings: rebuild (a delay or phaser restarts clean).
		fx = effect->make_fx(sr > 0 ? sr : 48000, seen);
	}
	for (int i = 0; i < p_frame_count; i++) {
		double l = src[i].left;
		double r = src[i].right;
		fx.tick(l, r);
		p_dst_buffer[i].left = (float)l;
		p_dst_buffer[i].right = (float)r;
	}
}
