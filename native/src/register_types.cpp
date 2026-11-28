// SPDX-License-Identifier: Apache-2.0
#include "register_types.h"
#include "ak_live.h"
#include "ak_native.h"
#include "ak_match.h"
#include "ak_synth.h"
#include "ak_fx.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

void initialize_aknative(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(AKNative);
	GDREGISTER_CLASS(AKMatch);
	GDREGISTER_CLASS(AKLiveStream);
	GDREGISTER_CLASS(AKLivePlayback);   // not internal: the engine may look it up by name
	GDREGISTER_CLASS(AKSynthStream);
	GDREGISTER_CLASS(AKSynthPlayback);
	GDREGISTER_VIRTUAL_CLASS(AKBusEffect);
	GDREGISTER_CLASS(AKBusEffectInstance);
	GDREGISTER_CLASS(AKChorus);
	GDREGISTER_CLASS(AKFlanger);
	GDREGISTER_CLASS(AKPhaser);
	GDREGISTER_CLASS(AKEQ3);
	GDREGISTER_CLASS(AKCompressor);
	GDREGISTER_CLASS(AKSaturate);
	GDREGISTER_CLASS(AKLimiter);
	GDREGISTER_CLASS(AKFreqShift);
	GDREGISTER_CLASS(AKRotary);
	GDREGISTER_CLASS(AKStutter);
	GDREGISTER_CLASS(AKConditioner);
	GDREGISTER_CLASS(AKGraphicEQ);
	GDREGISTER_CLASS(AKResonator);
	GDREGISTER_CLASS(AKExciter);
	GDREGISTER_CLASS(AKWaveshaper);
	GDREGISTER_CLASS(AKMidSide);
	GDREGISTER_CLASS(AKEnsemble);
	GDREGISTER_CLASS(AKCombulator);
	GDREGISTER_CLASS(AKTape);
	GDREGISTER_CLASS(AKTreemonster);
	GDREGISTER_CLASS(AKSpringReverb);
	GDREGISTER_CLASS(AKBonsai);
	GDREGISTER_CLASS(AKChow);
	GDREGISTER_CLASS(AKNeuron);
}

void uninitialize_aknative(ModuleInitializationLevel p_level) {
}

extern "C" {
GDExtensionBool GDE_EXPORT aknative_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
		const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_aknative);
	init_obj.register_terminator(uninitialize_aknative);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
