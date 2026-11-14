// Som dos pneus em C++ (som/sfx_carro.gd usa quando a biblioteca existe):
// o laço das rodas do passo() (_roda), com os números do sound_database.xml
// lidos uma vez no configurar.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/object_id.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

#include <map>
#include <string>
#include <vector>

namespace godot {

class SomPneuCpp : public RefCounted {
	GDCLASS(SomPneuCpp, RefCounted)

	struct Mat {
		bool existe = false;
		double pitch = 1.0, volume = 1.0;
		String surface, secondary;      // nome do patch ("Default" se faltar)
	};
	struct Patch {
		bool looping = false;
		String sample;
		// volume
		double v_min, v_max, v_side, v_spin, v_lock, v_attack, v_steer, v_acc, v_susp, v_vol, v_thr, v_decay;
		// tom
		double p_pitch, p_speed, p_side, p_spin, p_lock, p_steer, p_acc, p_diff, p_susp;
	};
	struct Roda {
		ObjectID som;
		int idx = 0;
		bool sec = false;
		double trava = 0.0, s = 0.0, vol = 0.0;
		int64_t mat = -2;
		Dictionary o;                   // o dicionário do GDScript (grava mat, trava, s, vol)
	};

	bool ok = false;
	ObjectID car_id;
	std::map<String, Mat> materiais;
	Mat padrao;                         // materiais["Default"] ou {}
	Mat agua;
	bool tem_agua = false;
	std::map<String, Patch> patches;
	double susp_off = 0.0, susp_esc = 3.4375;
	double master_sfx = 1.0, master_surface = 0.5;
	double rolagem = 0.0;
	bool so_derrapando = true;
	std::vector<Roda> rodas;
	std::map<int64_t, String> sfx_chao;   // material do terreno -> nome do som

	const Mat &mat_de(const String &nome) const;

protected:
	static void _bind_methods();

public:
	bool configurar(Object *sfx);
	bool rodas_passo(double dt, double v, double spd, double side, double ws, double derrapa);
};

} // namespace godot

namespace godot {

// som do motor (som/motor_som.gd atualizar/_camada): os loops gravados
class MotorSomCpp : public RefCounted {
	GDCLASS(MotorSomCpp, RefCounted)

	struct Loop {
		double rpm = 1.0, db = 0.0;
		ObjectID p;
	};
	bool ok = false;
	ObjectID som_id;
	std::vector<Loop> on, off;
	double lenta_real = 800.0, corte_real = 6000.0;
	double carga = 0.0, rpm = -1.0;

	void camada(const std::vector<Loop> &lista, double r, double ganho) const;

protected:
	static void _bind_methods();

public:
	bool configurar(Object *som);
	bool atualizar(double rpm_jogo, double carga_, double dt);
};

} // namespace godot
