#include "fisica_carro.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

using namespace godot;

void FisicaCarro::_bind_methods() {
	ClassDB::bind_static_method("FisicaCarro", D_METHOD("versao"), &FisicaCarro::versao);
	ClassDB::bind_static_method("FisicaCarro", D_METHOD("curva_sample", "c", "x"), &FisicaCarro::curva_sample);
	ClassDB::bind_static_method("FisicaCarro", D_METHOD("curva_integrate", "c", "x"), &FisicaCarro::curva_integrate);
	ClassDB::bind_static_method("FisicaCarro", D_METHOD("trio", "t", "mu"), &FisicaCarro::trio);
	ClassDB::bind_static_method("FisicaCarro", D_METHOD("fcurvas", "c", "mu", "x"), &FisicaCarro::fcurvas);
	ClassDB::bind_static_method("FisicaCarro", D_METHOD("contatos_esferas", "xa", "ca", "ra", "xb", "cb", "rb"), &FisicaCarro::contatos_esferas);
	ClassDB::bind_method(D_METHOD("configurar", "car"), &FisicaCarro::configurar);
	ClassDB::bind_method(D_METHOD("drivetrain", "dt", "v_f", "driven_on_ground", "forced_open"), &FisicaCarro::drivetrain);
	ClassDB::bind_method(D_METHOD("razao_patinada", "v_f"), &FisicaCarro::razao_patinada);
	ClassDB::bind_method(D_METHOD("giro_rodas", "dt", "v_f", "rear_g"), &FisicaCarro::giro_rodas);
	ClassDB::bind_method(D_METHOD("pneus", "dt", "v", "fwd", "left", "n", "com_w", "h", "drive"), &FisicaCarro::pneus);
	ClassDB::bind_method(D_METHOD("arrasto", "spd", "dt"), &FisicaCarro::arrasto);
	ClassDB::bind_method(D_METHOD("rodas", "dt", "space", "up"), &FisicaCarro::rodas);
	ClassDB::bind_method(D_METHOD("esferas", "space", "up"), &FisicaCarro::esferas);
	ClassDB::bind_method(D_METHOD("tremida", "dt", "v_l", "v_f"), &FisicaCarro::tremida);
}

String FisicaCarro::versao() {
	return "atv4_fisica 0.7";
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
	// pneus
	p.axle_f = f("axle_f");
	p.axle_r = f("axle_r");
	p.understeer_raw = f("understeer_raw");
	p.abs_eng = f("abs_eng");
	p.abs_dis = f("abs_dis");
	p.ss_full = f("ss_full");
	p.ss_zero = f("ss_zero");
	p.ss_max = f("ss_max");
	p.tail_off = f("tail_off");
	p.yaw_acc = f("yaw_acc");
	p.cs_scale_ss = f("cs_scale_ss");
	p.cs_scale = f("cs_scale");
	p.width_scale = f("width_scale");
	p.height_scale = f("height_scale");
	p.ell_disable = f("ell_disable");
	p.ps_ellipse = f("ps_ellipse");
	p.slip_max = f("slip_max");
	p.slip_grow = f("slip_grow");
	p.lock_grow = f("lock_grow");
	p.lock_recover = f("lock_recover");
	p.slip_recover = f("slip_recover");
	p.h_long_stf = f("h_long_stf");
	p.h_long = f("h_long");
	p.h_lat = f("h_lat");
	p.h_lat_s0 = f("h_lat_s0");
	p.h_lat_s1 = f("h_lat_s1");
	p.h_lat_roll = f("h_lat_roll");
	p.ifd_lo_speed = f("ifd_lo_speed");
	p.ifd_hi_speed = f("ifd_hi_speed");
	p.ifd_lo = f("ifd_lo");
	p.ifd_hi = f("ifd_hi");
	p.air_drag = f("air_drag");
	p.ground_drag = f("ground_drag");
	p.water_drag = f("water_drag");
	p.water_depth = f("water_depth");
	p.ps_air = f("ps_air");
	p.ps_growth = f("ps_growth");
	p.ps_decay = f("ps_decay");
	p.rtc_front = f("rtc_front");
	p.rtc_rear = f("rtc_rear");
	p.side_to_fwd_max = f("side_to_fwd_max");
	p.side_to_fwd_min = f("side_to_fwd_min");
	p.side_to_fwd = f("side_to_fwd");
	p.ps_side_to_fwd = f("ps_side_to_fwd");
	p.abs_on = P.get(String("abs_on"), false);
	p.rtc_on = P.get(String("rtc_on"), false);
	p.rtc_steer = P.get(String("rtc_steer"), false);
	auto dic = [&P](const char *k) -> Dictionary { return P.get(String(k), Dictionary()); };
	p.side_std = atv4::Trio(dic("side_std"));
	p.side_cs = atv4::Trio(dic("side_cs"));
	p.yaw_inc = atv4::FCurvas(dic("yaw_inc"));
	p.yaw_dec_zero = atv4::FCurvas(dic("yaw_dec_zero"));
	p.yaw_dec_full = atv4::FCurvas(dic("yaw_dec_full"));
	p.yaw_dec_cs = atv4::FCurvas(dic("yaw_dec_cs"));
	p.ss_rate_inc = atv4::FCurvas(dic("ss_rate_inc"));
	p.ss_rate_dec = atv4::FCurvas(dic("ss_rate_dec"));
	for (int i = 0; i < 2; i++) {
		Dictionary e = dic(i == 0 ? "ell_FrontWheels" : "ell_RearWheels");
		Elipse &el = i == 0 ? p.ell_f : p.ell_r;
		el.w = atv4::Trio(e.get(String("w"), Dictionary()));
		el.h = atv4::Trio(e.get(String("h"), Dictionary()));
		el.ms = atv4::Trio(e.get(String("ms"), Dictionary()));
		el.shrink = e.get(String("shrink"), 1.0);
		el.recover = e.get(String("recover"), 1.0);
	}
	PackedFloat32Array g = car->get(N.gears);
	gears.assign(g.ptr(), g.ptr() + g.size());
	drive_curve = atv4::Curva(car->get(N.drive_curve));
	fric_curve = atv4::Curva(car->get(N.fric_curve));
	steer_curve = atv4::Curva(car->get(N.steer_curve));
	ps_rate = atv4::Curva(car->get(N.ps_rate));
	ps_scale = atv4::Curva(car->get(N.ps_scale));
	rtc_th = atv4::Curva(car->get(N.rtc_th));
	rtc_max = atv4::Curva(car->get(N.rtc_max));
	rtc_cut = atv4::Curva(car->get(N.rtc_cut));
	// rodas
	rf.clear();
	Array ws = car->get(N.wheels);
	for (int64_t i = 0; i < ws.size(); i++) {
		Dictionary w = ws[i];
		RodaFixa r;
		r.px = w[N.px];
		r.y0 = w[N.y0];
		r.pz = w[N.pz];
		r.max = w[N.max];
		r.min = w[N.min];
		r.r = w[N.r];
		r.cos_max = w[N.cos_max];
		r.vmax = w[N.vmax];
		r.k = w[N.k];
		r.c = w[N.c];
		r.mw = w[N.mw];
		r.front = w[N.front];
		r.kc = atv4::Curva(w[N.kc]);
		r.dc = atv4::Curva(w[N.dc]);
		rf.push_back(r);
	}
}
