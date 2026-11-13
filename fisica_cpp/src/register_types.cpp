// Registro da extensão ATV4 Reborn (física do carro em C++).
#include "register_types.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "fisica_carro.h"
#include "piloto.h"
#include "suspensao.h"
#include "som.h"
#include "linha_ia.h"
#include "nuvens.h"
#include "som_jogo.h"

using namespace godot;

void initialize_atv4_fisica(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(FisicaCarro);
	GDREGISTER_CLASS(PilotoCpp);
	GDREGISTER_CLASS(SuspensaoCpp);
	GDREGISTER_CLASS(SomPneuCpp);
	GDREGISTER_CLASS(MotorSomCpp);
	GDREGISTER_CLASS(LinhaIA);
	GDREGISTER_CLASS(NuvensCpp);
	GDREGISTER_CLASS(SomJogoCpp);
}

void uninitialize_atv4_fisica(ModuleInitializationLevel p_level) {
}

extern "C" {
GDExtensionBool GDE_EXPORT atv4_fisica_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
		const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_atv4_fisica);
	init_obj.register_terminator(uninitialize_atv4_fisica);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
