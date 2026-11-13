// Pose do piloto em C++ (carro/piloto.gd usa quando a biblioteca existe).
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/object_id.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/quaternion.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <vector>

namespace godot {

class PilotoCpp : public RefCounted {
	GDCLASS(PilotoCpp, RefCounted)

	struct Mao {
		int sup = 0, inf = 0, mao = 0;
		Vector3 cent;
		Transform3D pega;
		Basis rel0;
		std::vector<Vector3> tab;
	};

	bool ok = false;
	ObjectID pil_id, skel_id;
	int n = 0;
	std::vector<int> pais, esp;
	std::vector<float> tempos, giro;
	double dur = 0.0;
	std::vector<std::vector<Vector3>> pos;
	std::vector<std::vector<Quaternion>> rot;
	bool vol = false;
	Vector3 vc, ve;
	int cabeca = -1;
	std::vector<Mao> maos;
	std::vector<Vector3> lp;
	std::vector<Quaternion> lr;
	std::vector<Transform3D> g;

	void quadro(double tm, int &k, double &f) const;
	double giro_volante(double s) const;
	void anima(double s);
	Vector3 cotovelo_ang(const Vector3 &a, const Vector3 &w, double l1, double l2, double th,
			const Vector3 &fora, const Vector3 &ref) const;
	void segura_volante(double giro, double s, double &alcance);

protected:
	static void _bind_methods();

public:
	bool configurar(Object *piloto);
	bool pose(double s, double extra);
};

} // namespace godot
