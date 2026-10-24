// SPDX-License-Identifier: Apache-2.0
#include "register_types.h"
#include "ak_live.h"
#include "ak_native.h"
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
