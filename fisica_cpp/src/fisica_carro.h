// Física do carro em C++ (nov/2026). As contas pesadas do carro/car.gd,
// portadas uma a uma, com os MESMOS números do GDScript (tests/teste_cpp.gd
// compara as duas). car.gd usa esta classe quando a biblioteca existe
// (bin/atv4_fisica.gdextension); sem ela, continua no GDScript.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class FisicaCarro : public RefCounted {
	GDCLASS(FisicaCarro, RefCounted)

protected:
	static void _bind_methods();

public:
	static String versao();
	// as curvas do VehicleData em C++ (testes de paridade: tests/teste_cpp.gd)
	static double curva_sample(const Dictionary &c, double x);
	static double curva_integrate(const Dictionary &c, double x);
	static double trio(const Dictionary &t, double mu);
	static double fcurvas(const Dictionary &c, double mu, double x);
};

} // namespace godot
