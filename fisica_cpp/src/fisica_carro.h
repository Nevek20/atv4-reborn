// Física do carro em C++ (nov/2026). As contas pesadas do carro/car.gd,
// portadas uma a uma, com os MESMOS números do GDScript (tests/teste_cpp.gd
// compara as duas). car.gd usa esta classe quando a biblioteca existe
// (bin/atv4_fisica.gdextension); sem ela, continua no GDScript.
// Uma instância por carro: configurar(car) guarda o P, as curvas e as marchas;
// o estado (rpm, marcha, rodas...) continua nas variáveis do car.gd.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/object_id.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/string_name.hpp>

#include <vector>

#include "curvas.h"

struct EstadoMotor;

namespace godot {

class FisicaCarro : public RefCounted {
	GDCLASS(FisicaCarro, RefCounted)

protected:
	static void _bind_methods();

public:
	// nomes das variáveis do car.gd e das chaves das rodas (StringName feito uma vez)
	struct Nomes {
		StringName wheels, P, gears, drive_curve, fric_curve;
		StringName air_time, rpm, brake_in, throttle, clutch, lim_k, eng_torque, clutch_t, thr_cx;
		StringName shift_timer, slip_sign, som_carga, emb_in, mu_medio, v_ref, gear, cstate, shift_to;
		StringName preso, shift_flag, want_rev, manual, limiter, preso_t, preso_pos, pos_ant;
		StringName front, sr, omega, hit, r, slip, inercia, spin;
		Nomes();
	};
	static const Nomes &nomes();

	// P do carro (só os números que o C++ usa)
	struct Params {
		double clutch_dis_rpm = 0, idle = 0, lim_on = 0, lim_off = 0, lim_rate_on = 0, lim_rate_off = 0;
		double drive_scale = 0, fric_scale = 0, eng_inertia = 1, wheel_r = 1, rev_limit = 0, rev_cut = 0;
		double gear_r = 0, final = 1, clutch_dis_rate = 0, clutch_eng_rate = 0, clutch_rpm_lo = 0;
		double clutch_rpm_hi = 0, clutch_thr_mod = 1, manual_time = 0, auto_time = 0, clutch_lock_diff = 0;
		double up_thr_mod = 1, clutch_max = 0, brake_decel = 0, front_bias = 0, up_rpm = 0;
		std::vector<double> down_diff;
		bool rear_drive = true;
	};

private:
	ObjectID car_id;
	Params p;
	std::vector<float> gears;
	atv4::Curva drive_curve, fric_curve;
	atv4::Trio brake_fscale;

	Object *carro() const;
	double ratio(int64_t g) const;
	double up_speed(int64_t g) const;
	double down_speed(int64_t g) const;
	double gearbox(EstadoMotor &e, double dt, double v_f, double out_rpm, bool auto_ok, bool forced) const;

public:
	static String versao();
	// as curvas do VehicleData em C++ (testes de paridade: tests/teste_cpp.gd)
	static double curva_sample(const Dictionary &c, double x);
	static double curva_integrate(const Dictionary &c, double x);
	static double trio(const Dictionary &t, double mu);
	static double fcurvas(const Dictionary &c, double mu, double x);

	void configurar(Object *car);
	// motor e câmbio (motor.cpp)
	double drivetrain(double dt, double v_f, bool driven_on_ground, bool forced_open);
	void razao_patinada(double v_f);
	void giro_rodas(double dt, double v_f, int64_t rear_g);
};

} // namespace godot
