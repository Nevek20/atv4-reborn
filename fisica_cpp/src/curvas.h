// Curvas dos XMLs do jogo (as do carro/vehicle_data.gd), em C++.
// As contas são em double como no GDScript (float do GDScript = 64 bits);
// os valores das curvas vêm de PackedFloat32Array (32 bits) e sobem pra
// double na leitura, igual ao GDScript. Assim os números batem bit a bit.
#pragma once

#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

#include <vector>

namespace atv4 {

// curva {"v": PackedFloat32Array, "max": x máximo}
struct Curva {
	std::vector<float> v;
	double max = 1.0;

	Curva() {}
	explicit Curva(const godot::Dictionary &c);
	double sample(double x) const;      // VehicleData.sample
	double integrate(double x) const;   // VehicleData.integrate (mola progressiva)
};

// trio de atrito (0x21d8b0): valor pra atrito máximo, mínimo e especial
struct Trio {
	double max = 0.0, min = 0.0, sp = 0.0, lmax = 1.0, lmin = 0.1;

	Trio() {}
	explicit Trio(const godot::Dictionary &t);
	double eval(double mu) const;       // VehicleData.triple
};

// trio de curvas x velocidade (0x21d938)
struct FCurvas {
	Curva max, min, sp;
	double lmax = 1.0, lmin = 0.1;

	FCurvas() {}
	explicit FCurvas(const godot::Dictionary &c);
	double eval(double mu, double x) const;   // VehicleData.fcurve_eval
};

} // namespace atv4
