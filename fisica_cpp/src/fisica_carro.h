// Física do carro em C++ (nov/2026). As contas pesadas do carro/car.gd,
// portadas uma a uma, com os MESMOS números do GDScript (tests/teste_cpp.gd
// compara as duas). car.gd usa esta classe quando a biblioteca existe
// (bin/atv4_fisica.gdextension); sem ela, continua no GDScript.
// Uma instância por carro: configurar(car) guarda o P, as curvas e as marchas;
// o estado (rpm, marcha, rodas...) continua nas variáveis do car.gd.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/object_id.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/physics_ray_query_parameters3d.hpp>
#include <godot_cpp/classes/physics_shape_query_parameters3d.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <vector>

namespace godot {
class RigidBody3D;
class PhysicsDirectSpaceState3D;
class PhysicsRayQueryParameters3D;
}

#include "curvas.h"

struct EstadoMotor;
struct EstadoPneu;
struct Roda;

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
		StringName agua, agua_prof, ps_qtd, ps_esc, ps_emb_ant, steer, steer_cx, amort_medio, ps_estado;
		StringName grounded, lateral_game, drive_slip, rtc_patinou, jit_order, stf_blend, sideslip;
		StringName abs, sat, grip, mu, y0, x, px, pz, fx, fz;
		StringName steer_curve, ps_rate, ps_scale, rtc_th, rtc_max, rtc_cut;
		StringName v, f, point, normal, mat, amort, objetos, terrain, pneu, ignorar_roda, outros_carros;
		StringName roda_na_cerca, collider, position, rid, material_at, atrito, amortecimento;
		StringName kc, dc, k, c, mw, vmax, cos_max, min, max;
		StringName esfera, esfera_teste, esfera_off, collider_id;
		Nomes();
	};
	static const Nomes &nomes();

	// elipse de atrito de um eixo (P.ell_FrontWheels / P.ell_RearWheels)
	struct Elipse {
		atv4::Trio w, h, ms;
		double shrink = 1, recover = 1;
	};

	// P do carro (só os números que o C++ usa)
	struct Params {
		double clutch_dis_rpm = 0, idle = 0, lim_on = 0, lim_off = 0, lim_rate_on = 0, lim_rate_off = 0;
		double drive_scale = 0, fric_scale = 0, eng_inertia = 1, wheel_r = 1, rev_limit = 0, rev_cut = 0;
		double gear_r = 0, final = 1, clutch_dis_rate = 0, clutch_eng_rate = 0, clutch_rpm_lo = 0;
		double clutch_rpm_hi = 0, clutch_thr_mod = 1, manual_time = 0, auto_time = 0, clutch_lock_diff = 0;
		double up_thr_mod = 1, clutch_max = 0, brake_decel = 0, front_bias = 0, up_rpm = 0;
		std::vector<double> down_diff;
		bool rear_drive = true;
		// pneus
		double axle_f = 0, axle_r = -1, understeer_raw = 0, abs_eng = 0, abs_dis = 0, ss_full = 1, ss_zero = 1;
		double ss_max = 0, tail_off = 1, yaw_acc = 0, cs_scale_ss = 1, cs_scale = 1, width_scale = 0;
		double height_scale = 0, ell_disable = 2, ps_ellipse = 1, slip_max = 0, slip_grow = 0, lock_grow = 0;
		double lock_recover = 0, slip_recover = 0, h_long_stf = 0, h_long = 0, h_lat = 0, h_lat_s0 = 1;
		double h_lat_s1 = 1, h_lat_roll = 0, ifd_lo_speed = 0, ifd_hi_speed = 1, ifd_lo = 0, ifd_hi = 0;
		double air_drag = 0, ground_drag = 0, water_drag = 0, water_depth = 1, ps_air = 0, ps_growth = 0;
		double ps_decay = 0, rtc_front = 0, rtc_rear = 0, side_to_fwd_max = 1, side_to_fwd_min = 0;
		double side_to_fwd = 0, ps_side_to_fwd = 0;
		bool abs_on = false, rtc_on = false, rtc_steer = false;
		atv4::Trio side_std, side_cs;
		atv4::FCurvas yaw_inc, yaw_dec_zero, yaw_dec_full, yaw_dec_cs, ss_rate_inc, ss_rate_dec;
		Elipse ell_f, ell_r;
	};

	// o que não muda numa roda (mola, amortecedor, curso, posição)
	struct RodaFixa {
		double px = 0, y0 = 0, pz = 0, max = 0, min = 0, r = 0, cos_max = 0, vmax = 0, k = 0, c = 0, mw = 1;
		bool front = false;
		atv4::Curva kc, dc;
	};

private:
	ObjectID car_id;
	std::vector<RodaFixa> rf;
	Ref<PhysicsRayQueryParameters3D> query;
	Ref<PhysicsShapeQueryParameters3D> query_esfera;
	Params p;
	std::vector<float> gears;
	atv4::Curva drive_curve, fric_curve, steer_curve, ps_rate, ps_scale, rtc_th, rtc_max, rtc_cut;
	atv4::Trio brake_fscale;

	Object *carro() const;
	double ratio(int64_t g) const;
	double up_speed(int64_t g) const;
	double down_speed(int64_t g) const;
	double gearbox(EstadoMotor &e, double dt, double v_f, double out_rpm, bool auto_ok, bool forced) const;
	double arrasto_de(Object *c, double amort_medio, int64_t n_rodas, double spd, double dt) const;
	double corte_recuperacao(EstadoPneu &e, std::vector<Roda> &ws, RigidBody3D *b, int64_t i_fl,
			double dt, double v_f, double v_p, double yaw) const;
	void powerslide(EstadoPneu &e, std::vector<Roda> &ws, double dt, double v_p) const;
	double mola(const RodaFixa &w, double x) const;
	double amortecedor(const RodaFixa &w, double v) const;

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
	// pneus (pneus.cpp)
	double pneus(double dt, Vector3 v, Vector3 fwd, Vector3 left, Vector3 n, Vector3 com_w, double h, double drive);
	double arrasto(double spd, double dt) const;
	// rodas e molas (rodas.cpp)
	Array rodas(double dt, PhysicsDirectSpaceState3D *space, Vector3 up);
	void esferas(PhysicsDirectSpaceState3D *space, Vector3 up);
};

} // namespace godot
