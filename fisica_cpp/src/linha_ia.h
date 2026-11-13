// Contas da linha da IA em C++ (pista/ia.gd usa quando a biblioteca existe).
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <vector>

namespace godot {

class LinhaIA : public RefCounted {
	GDCLASS(LinhaIA, RefCounted)

	std::vector<Vector3> linha;
	std::vector<double> acc;
	double comp = 0.0;

protected:
	static void _bind_methods();

public:
	bool configurar(const Array &linha, const Array &acc, double comp);
	int64_t seg(double s) const;
	Vector3 ponto(double s) const;
	double v_curva(double s) const;
	double lateral(Vector3 p, double s) const;
	double direcao_ang(double s, double lat, Transform3D xf) const;
	PackedFloat64Array rastrear(double prog, double s_linha, Vector3 p) const;
};

} // namespace godot
