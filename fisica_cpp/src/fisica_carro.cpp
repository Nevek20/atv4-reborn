#include "fisica_carro.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

using namespace godot;

void FisicaCarro::_bind_methods() {
	ClassDB::bind_static_method("FisicaCarro", D_METHOD("versao"), &FisicaCarro::versao);
	ClassDB::bind_static_method("FisicaCarro", D_METHOD("curva_sample", "c", "x"), &FisicaCarro::curva_sample);
	ClassDB::bind_static_method("FisicaCarro", D_METHOD("curva_integrate", "c", "x"), &FisicaCarro::curva_integrate);
	ClassDB::bind_static_method("FisicaCarro", D_METHOD("trio", "t", "mu"), &FisicaCarro::trio);
	ClassDB::bind_static_method("FisicaCarro", D_METHOD("fcurvas", "c", "mu", "x"), &FisicaCarro::fcurvas);
	ClassDB::bind_method(D_METHOD("configurar", "car"), &FisicaCarro::configurar);
	ClassDB::bind_method(D_METHOD("drivetrain", "dt", "v_f", "driven_on_ground", "forced_open"), &FisicaCarro::drivetrain);
	ClassDB::bind_method(D_METHOD("razao_patinada", "v_f"), &FisicaCarro::razao_patinada);
	ClassDB::bind_method(D_METHOD("giro_rodas", "dt", "v_f", "rear_g"), &FisicaCarro::giro_rodas);
}

String FisicaCarro::versao() {
	return "atv4_fisica 0.3";
}

double FisicaCarro::curva_sample(const Dictionary &c, double x) {
	return atv4::Curva(c).sample(x);
}

double FisicaCarro::curva_integrate(const Dictionary &c, double x) {
	return atv4::Curva(c).integrate(x);
}

double FisicaCarro::trio(const Dictionary &t, double mu) {
	return atv4::Trio(t).eval(mu);
}

double FisicaCarro::fcurvas(const Dictionary &c, double mu, double x) {
	return atv4::FCurvas(c).eval(mu, x);
}

Object *FisicaCarro::carro() const {
	return ObjectDB::get_instance(car_id);
}

// guarda o P, as marchas e as curvas do carro (chamar depois do _load_physics)
void FisicaCarro::configurar(Object *car) {
	car_id = car != nullptr ? car->get_instance_id() : ObjectID();
	if (car == nullptr) {
		return;
	}
	const Nomes &N = nomes();
	Dictionary P = car->get(N.P);
	auto f = [&P](const char *k) -> double { return P.get(String(k), 0.0); };
	p.clutch_dis_rpm = f("clutch_dis_rpm");
	p.idle = f("idle");
	p.lim_on = f("lim_on");
	p.lim_off = f("lim_off");
	p.lim_rate_on = f("lim_rate_on");
	p.lim_rate_off = f("lim_rate_off");
	p.drive_scale = f("drive_scale");
	p.fric_scale = f("fric_scale");
	p.eng_inertia = f("eng_inertia");
	p.wheel_r = f("wheel_r");
	p.rev_limit = f("rev_limit");
	p.rev_cut = f("rev_cut");
	p.gear_r = f("gear_r");
	p.final = f("final");
	p.clutch_dis_rate = f("clutch_dis_rate");
	p.clutch_eng_rate = f("clutch_eng_rate");
	p.clutch_rpm_lo = f("clutch_rpm_lo");
	p.clutch_rpm_hi = f("clutch_rpm_hi");
	p.clutch_thr_mod = f("clutch_thr_mod");
	p.manual_time = f("manual_time");
	p.auto_time = f("auto_time");
	p.clutch_lock_diff = f("clutch_lock_diff");
	p.up_thr_mod = f("up_thr_mod");
	p.clutch_max = f("clutch_max");
	p.brake_decel = f("brake_decel");
	p.front_bias = f("front_bias");
	p.up_rpm = f("up_rpm");
	p.down_diff.clear();
	PackedFloat32Array dd = P.get(String("down_diff"), PackedFloat32Array());
	for (int64_t i = 0; i < dd.size(); i++) {
		p.down_diff.push_back(dd[i]);
	}
	brake_fscale = atv4::Trio(P.get(String("brake_fscale"), Dictionary()));
	PackedFloat32Array g = car->get(N.gears);
	gears.assign(g.ptr(), g.ptr() + g.size());
	drive_curve = atv4::Curva(car->get(N.drive_curve));
	fric_curve = atv4::Curva(car->get(N.fric_curve));
}
