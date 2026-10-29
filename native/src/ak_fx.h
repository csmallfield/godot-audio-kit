// SPDX-License-Identifier: Apache-2.0
// The kit's sound-shaping effects as Godot bus effects: AKChorus, AKFlanger,
// AKPhaser, AKEQ3, AKCompressor and AKSaturate appear in Godot's Audio panel
// ("Add Effect"). They run the same ak::Fx code as patches and recipes, so
// an effect sounds the same on a bus, in a patch and in a bake.
#pragma once
#include "fx.h"

#include <godot_cpp/classes/audio_effect.hpp>
#include <godot_cpp/classes/audio_effect_instance.hpp>
#include <godot_cpp/classes/audio_frame.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#include <atomic>
#include <mutex>

namespace godot {

// A compiled effect spec (AKStreamFx.compile()) as an ak::Fx (not set up).
ak::Fx fx_from(const Dictionary &compiled);

// The shared base: knobs live in a Dictionary named like the spec keys, shown
// as properties with ranges from a per-type table.
class AKBusEffect : public AudioEffect {
	GDCLASS(AKBusEffect, AudioEffect)

protected:
	static void _bind_methods();
	bool _set(const StringName &p_name, const Variant &p_value);
	bool _get(const StringName &p_name, Variant &r_ret) const;
	void _get_property_list(List<PropertyInfo> *p_list) const;
	bool _property_can_revert(const StringName &p_name) const;
	bool _property_get_revert(const StringName &p_name, Variant &r_property) const;

	Dictionary knobs;
	mutable std::mutex mutex;
	std::atomic<int> version{ 1 };

public:
	// The effect type name: "chorus", "phaser" ... (set by each subclass).
	virtual String fx_type() const { return ""; }
	// The spec dictionary, as a recipe or patch would write it.
	Dictionary get_spec() const;
	// A ready-to-run ak::Fx (copied under the lock) and the version it reflects.
	ak::Fx make_fx(int sr, int &r_version) const;
	int get_version() const { return version.load(); }
	Ref<AudioEffectInstance> _instantiate() override;
	// Run the bus effect's own instance over stereo arrays at `sr` (tests and
	// bakes that want exactly what the bus does): [l, r].
	Array process_offline(const PackedFloat32Array &l, const PackedFloat32Array &r, int sr);
	void init_defaults();
};

class AKBusEffectInstance : public AudioEffectInstance {
	GDCLASS(AKBusEffectInstance, AudioEffectInstance)

	Ref<AKBusEffect> effect;
	ak::Fx fx;
	int seen = -1;
	int sr = 0;

protected:
	static void _bind_methods() {}

public:
	void set_effect(const Ref<AKBusEffect> &e, int p_sr) {
		effect = e;
		sr = p_sr;
	}
	void _process(const void *p_src_buffer, AudioFrame *p_dst_buffer, int32_t p_frame_count) override;
	bool _process_silence() const override { return true; }   // let tails ring out
};

#define AK_BUS_EFFECT(NAME, TYPE)                                \
	class NAME : public AKBusEffect {                            \
		GDCLASS(NAME, AKBusEffect)                               \
	protected:                                                   \
		static void _bind_methods() {}                           \
	public:                                                      \
		NAME() { init_defaults(); }                              \
		String fx_type() const override { return TYPE; }         \
	};

AK_BUS_EFFECT(AKChorus, "chorus")
AK_BUS_EFFECT(AKFlanger, "flanger")
AK_BUS_EFFECT(AKPhaser, "phaser")
AK_BUS_EFFECT(AKEQ3, "eq")
AK_BUS_EFFECT(AKCompressor, "compressor")
AK_BUS_EFFECT(AKSaturate, "saturate")

} // namespace godot
