// Suspensão visual em C++ (carro/suspension_visual.gd usa quando a
// biblioteca existe): o update() por quadro. A montagem fica no GDScript.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/object_id.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <vector>

namespace godot {

class SuspensaoCpp : public RefCounted {
	GDCLASS(SuspensaoCpp, RefCounted)

	// um canto (corners do GDScript)
	struct Canto {
		bool left = false, front = false, tem_top = false;
		Vector3 pivot, w0, u, top, bottom;
		double r = 0.0;
		ObjectID frame, brake, shock, chamber, piston;
		Dictionary wheel;                // roda da física (x, jit, pivot)
		double wmin = 0.0, wmax = 0.0;
		// última pose (pras barras)
		Transform3D u_frame, u_brake;
	};
	struct Barra {
		ObjectID mi;
		Vector3 dentro, fora;
		int canto = 0;
		bool freio = false;              // peca "brake" (senão "frame")
	};
	struct Tele {
		bool tem = false;
		Vector3 b0, t0;
		ObjectID cima, baixo, mola;
	};
	struct PecaTruck {
		bool tem = false;
		std::vector<ObjectID> mis;
		Vector3 pivot, w, a0, ancora, wl, wr;
		double div = 1.0;
		Tele tele;
		std::vector<ObjectID> rodas;     // pivôs das rodas de trás (eixos)
		StringName nome;
	};

	bool ok = false;
	ObjectID car_id, susp_id;
	Vector3 off;
	bool rally = false;
	std::vector<Canto> cantos;
	std::vector<Barra> barras;
	bool truck = false;
	PecaTruck frame_l, frame_r, brake_l, brake_r, axle, livre;
	Dictionary rodas_truck;              // "FL".. -> roda (Dictionary)
	Dictionary desloca;                  // BALANCA_DESLOCA do carro

	void place(ObjectID id, const Transform3D &xf) const;
	double curso(const Dictionary &w) const;
	double inclinacao(const PecaTruck &t, double rl, double rr) const;

protected:
	static void _bind_methods();

public:
	bool configurar(Object *susp);
	bool update(double steer);
};

} // namespace godot
