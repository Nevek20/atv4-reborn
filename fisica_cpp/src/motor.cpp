// Motor, câmbio e giro das rodas em C++ (porta linha a linha do carro/car.gd:
// _drivetrain, _gearbox, _shift_step, _up_speed, _down_speed, _razao_patinada,
// _giro_rodas, _freio_livre). O estado continua nas variáveis do car.gd (o
// resto do jogo lê de lá): aqui ele é lido no começo e gravado no fim.
// Tipos como no GDScript: escalares em double, vetores Vector3 (float).
#include "fisica_carro.h"

#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include "mat.h"

using namespace godot;

using namespace atv4;

// ---- estado do motor (variáveis do car.gd)
struct EstadoMotor {
	double air_time, rpm, brake_in, throttle, clutch, lim_k, eng_torque, clutch_t;
	double thr_cx, shift_timer, slip_sign, som_carga, emb_in, mu_medio, v_ref;
	int64_t gear, cstate, shift_to;
	bool preso, shift_flag, want_rev, manual, limiter;
};

const FisicaCarro::Nomes &FisicaCarro::nomes() {
	static Nomes n;
	return n;
}

FisicaCarro::Nomes::Nomes() :
		wheels("wheels"), P("P"), gears("gears"), drive_curve("drive_curve"), fric_curve("fric_curve"),
		air_time("air_time"), rpm("rpm"), brake_in("brake_in"), throttle("throttle"), clutch("clutch"),
		lim_k("lim_k"), eng_torque("eng_torque"), clutch_t("clutch_t"), thr_cx("thr_cx"),
		shift_timer("shift_timer"), slip_sign("slip_sign"), som_carga("som_carga"), emb_in("emb_in"),
		mu_medio("mu_medio"), v_ref("v_ref"), gear("gear"), cstate("cstate"), shift_to("shift_to"),
		preso("preso"), shift_flag("shift_flag"), want_rev("want_rev"), manual("manual"), limiter("limiter"),
		preso_t("preso_t"), preso_pos("preso_pos"), pos_ant("pos_ant"),
		front("front"), sr("sr"), omega("omega"), hit("hit"), r("r"), slip("slip"), inercia("inercia"),
		spin("spin"), agua("agua"), agua_prof("agua_prof"), ps_qtd("ps_qtd"), ps_esc("ps_esc"),
		ps_emb_ant("ps_emb_ant"), steer("steer"), steer_cx("steer_cx"), amort_medio("amort_medio"),
		ps_estado("ps_estado"), grounded("grounded"), lateral_game("lateral_game"), drive_slip("drive_slip"),
		rtc_patinou("rtc_patinou"), jit_order("jit_order"), stf_blend("stf_blend"), sideslip("sideslip"),
		abs("abs"), sat("sat"), grip("grip"), mu("mu"), y0("y0"), x("x"), px("px"), pz("pz"), fx("fx"), fz("fz"),
		steer_curve("steer_curve"), ps_rate("ps_rate"), ps_scale("ps_scale"), rtc_th("rtc_th"),
		rtc_max("rtc_max"), rtc_cut("rtc_cut"), v("v"), f("f"), point("point"), normal("normal"), mat("mat"),
		amort("amort"), objetos("objetos"), terrain("terrain"), pneu("pneu"), ignorar_roda("ignorar_roda"),
		outros_carros("outros_carros"), roda_na_cerca("roda_na_cerca"), collider("collider"),
		position("position"), rid("rid"), material_at("material_at"), atrito("atrito"),
		amortecimento("amortecimento"), kc("kc"), dc("dc"), k("k"), c("c"), mw("mw"), vmax("vmax"),
		cos_max("cos_max"), min("min"), max("max") {}

static void ler(Object *c, const FisicaCarro::Nomes &N, EstadoMotor &e) {
	e.air_time = c->get(N.air_time);
	e.rpm = c->get(N.rpm);
	e.brake_in = c->get(N.brake_in);
	e.throttle = c->get(N.throttle);
	e.clutch = c->get(N.clutch);
	e.lim_k = c->get(N.lim_k);
	e.eng_torque = c->get(N.eng_torque);
	e.clutch_t = c->get(N.clutch_t);
	e.thr_cx = c->get(N.thr_cx);
	e.shift_timer = c->get(N.shift_timer);
	e.slip_sign = c->get(N.slip_sign);
	e.som_carga = c->get(N.som_carga);
	e.emb_in = c->get(N.emb_in);
	e.mu_medio = c->get(N.mu_medio);
	e.v_ref = c->get(N.v_ref);
	e.gear = c->get(N.gear);
	e.cstate = c->get(N.cstate);
	e.shift_to = c->get(N.shift_to);
	e.preso = c->get(N.preso);
	e.shift_flag = c->get(N.shift_flag);
	e.want_rev = c->get(N.want_rev);
	e.manual = c->get(N.manual);
	e.limiter = c->get(N.limiter);
}

static void gravar(Object *c, const FisicaCarro::Nomes &N, const EstadoMotor &e) {
	c->set(N.rpm, e.rpm);
	c->set(N.clutch, e.clutch);
	c->set(N.lim_k, e.lim_k);
	c->set(N.eng_torque, e.eng_torque);
	c->set(N.clutch_t, e.clutch_t);
	c->set(N.shift_timer, e.shift_timer);
	c->set(N.slip_sign, e.slip_sign);
	c->set(N.som_carga, e.som_carga);
	c->set(N.gear, e.gear);
	c->set(N.cstate, e.cstate);
	c->set(N.shift_to, e.shift_to);
	c->set(N.shift_flag, e.shift_flag);
	c->set(N.limiter, e.limiter);
}

double FisicaCarro::ratio(int64_t g) const {
	if (g == -1) {
		return p.gear_r * p.final;
	}
	if (g <= 0) {
		return 0.0;
	}
	return (double)gears[g] * p.final;
}

double FisicaCarro::up_speed(int64_t g) const {
	return p.up_rpm * p.wheel_r * RPM2RAD / ((double)gears[g] * p.final);
}

double FisicaCarro::down_speed(int64_t g) const {
	if (g <= 1) {
		return 0.0;
	}
	if (g == 2) {
		return maxd(up_speed(1) * 0.1, up_speed(1) - p.down_diff[2] * MPH);
	}
	double a = up_speed(g - 2);
	double b = up_speed(g - 1);
	return maxd(a + (b - a) * 0.1, b - p.down_diff[g] * MPH);
}

// _shift_step
static void shift_step(EstadoMotor &e, double dt, double dis, double change_time, double diff) {
	if (e.clutch > 0.0) {
		e.clutch -= dis * dt;
		if (e.clutch < 0.0) {
			e.clutch = 0.0;
			e.cstate = 0;
		}
	} else {
		e.shift_timer += dt;
		if (e.shift_timer >= change_time) {
			e.shift_timer = 0.0;
			e.cstate = 1;
			e.slip_sign = diff;
			e.gear = e.shift_to;
		}
	}
}

// _gearbox: devolve o torque que passa pela embreagem
double FisicaCarro::gearbox(EstadoMotor &e, double dt, double v_f, double out_rpm, bool auto_ok, bool forced) const {
	int64_t n_g = (int64_t)gears.size() - 1;
	bool rev_now = e.gear == -1;
	double t2 = e.thr_cx * e.thr_cx;
	double dis = p.clutch_dis_rate;
	double eng = p.clutch_eng_rate;
	double rpm_thr = p.clutch_rpm_lo;
	bool plain = !e.manual ? e.want_rev : rev_now;
	if (!plain) {
		dis *= 1.0 + t2 * (p.clutch_thr_mod - 1.0);
		eng *= 1.0 + t2 * (p.clutch_thr_mod - 1.0);
		rpm_thr = lerpd(p.clutch_rpm_lo, p.clutch_rpm_hi, t2);
	}
	double diff = e.rpm - out_rpm;
	double change_time = e.manual ? p.manual_time : p.auto_time;

	bool open_path = false;
	bool engage = false;
	if (!e.manual) {
		if (p.clutch_dis_rpm < e.rpm || e.gear > 1) {
			if (absd(v_f) < down_speed(2) && e.gear > 1) {
				open_path = true;
			} else if (e.want_rev && e.gear != -1 && e.shift_to != -1) {
				open_path = true;
			} else if (!e.want_rev && e.gear == -1 && e.shift_to == -1) {
				open_path = true;
			} else if (forced) {
				open_path = true;
			} else if (e.shift_to != e.gear) {
				shift_step(e, dt, dis, change_time, diff);
			} else if (e.rpm > rpm_thr) {
				engage = true;
			} else if (e.cstate == 1 || e.cstate == 3) {
				engage = true;
			} else if (e.thr_cx < 0.01 && absd(v_f) > 5.0 * MPH) {
				engage = true;
			}
		} else {
			open_path = true;
		}
	} else {
		if (p.clutch_dis_rpm <= e.rpm && !forced) {
			if (e.shift_to != e.gear) {
				shift_step(e, dt, dis, change_time, diff);
			} else if (e.rpm > rpm_thr || e.cstate == 1 || e.cstate == 3) {
				engage = true;
			}
		} else {
			open_path = true;
		}
	}

	if (open_path) {
		e.cstate = 2;
		e.clutch = maxd(e.clutch - dis * dt, 0.0);
		if (e.clutch <= 0.0) {
			e.cstate = 0;
			if (!forced) {
				e.shift_timer = 0.0;
				if (e.manual) {
					e.gear = e.shift_to;
				} else {
					e.gear = e.want_rev ? -1 : 1;
					e.shift_to = e.gear;
				}
			}
			e.shift_flag = false;
		}
	} else if (engage) {
		if (e.clutch < 1.0) {
			if (e.cstate != 1) {
				e.slip_sign = diff;
			}
			e.cstate = 1;
			e.clutch = mind(e.clutch + eng * dt, 1.0);
		}
		if (e.clutch > 0.0 && e.cstate != 3) {
			if (absd(diff) < p.clutch_lock_diff || signd(diff) != signd(e.slip_sign)) {
				e.cstate = 3;
				e.clutch = 1.0;
				e.shift_flag = false;
			}
		}
		if (e.cstate == 3 && !e.manual && !e.want_rev && auto_ok && e.gear >= 1) {
			double k = 1.0 + e.thr_cx * (p.up_thr_mod - 1.0);
			if (v_f > k * up_speed(e.gear) && e.gear < n_g) {
				e.shift_to = e.gear + 1;
				e.cstate = 2;
				e.shift_flag = true;
			} else if (e.gear > 1 && v_f < k * down_speed(e.gear)) {
				e.shift_to = e.gear - 1;
				e.cstate = 2;
				e.shift_flag = true;
			}
		}
	}

	if (e.clutch <= 0.0 || e.gear == 0) {
		e.clutch_t = 0.0;
	} else if (e.cstate == 3) {
		e.clutch_t = e.eng_torque;
	} else if (e.cstate == 2) {
		double cap = e.clutch * p.clutch_max;
		e.clutch_t = e.eng_torque <= 0.0 ? 0.0 : mind(cap, e.eng_torque);
	} else if (e.cstate == 1) {
		e.clutch_t = signd(diff) * e.clutch * p.clutch_max;
	}
	return e.clutch_t;
}

// _drivetrain
double FisicaCarro::drivetrain(double dt, double v_f, bool driven_on_ground, bool forced_open) {
	Object *c = carro();
	if (c == nullptr) {
		return 0.0;
	}
	const Nomes &N = nomes();
	EstadoMotor e;
	ler(c, N, e);
	Array ws = c->get(N.wheels);

	double rt = ratio(e.gear);
	bool forced = forced_open;
	if (e.air_time > 1.0) {
		forced = forced || e.rpm < p.clutch_dis_rpm;
	} else if (e.brake_in > 0.9) {
		for (int64_t i = 0; i < ws.size(); i++) {
			Dictionary w = ws[i];
			bool motriz = !(bool)w[N.front] || !p.rear_drive;
			if (motriz && (double)w[N.sr] < -0.9) {
				forced = true;
			}
		}
	}
	double w_tr = 0.0;
	for (int64_t i = 0; i < ws.size(); i++) {
		Dictionary w = ws[i];
		bool motriz = !(bool)w[N.front] || !p.rear_drive;
		double om = w[N.omega];
		if (motriz && absd(w_tr) < absd(om)) {
			w_tr = om;
		}
	}
	double out_rpm = w_tr / RPM2RAD * rt;

	bool integrate = true;
	if (e.cstate == 3 && driven_on_ground && !e.preso) {
		e.rpm = maxd(out_rpm, p.idle);
		integrate = false;
	}
	double thr_eng = e.throttle;
	if (e.cstate != 3 && e.shift_flag) {
		thr_eng *= e.clutch;
	}

	double ct = gearbox(e, dt, v_f, out_rpm, driven_on_ground, forced);

	double e_load = e.cstate == 3 ? 0.0 : ct;
	if (e.rpm > p.lim_on) {
		e.lim_k = maxd(e.lim_k - p.lim_rate_on * dt, 0.0);
	} else if (e.rpm < p.lim_off) {
		e.lim_k = mind(e.lim_k + p.lim_rate_off * dt, 1.0);
	}
	e.limiter = e.lim_k < 0.999;
	e.som_carga = thr_eng * e.lim_k;
	e.eng_torque = thr_eng * e.lim_k * drive_curve.sample(e.rpm) * p.drive_scale
			- fric_curve.sample(e.rpm) * p.fric_scale;
	if (integrate) {
		e.rpm += (e.eng_torque - e_load) * dt / p.eng_inertia;
	}
	if (e.rpm < p.idle) {
		e.rpm = p.idle;
	}
	if (e.rpm <= p.idle && e.eng_torque < 0.0) {
		e.eng_torque = 0.0;
	}

	double f = ct * ratio(e.gear) / p.wheel_r;
	double v_mph = v_f / MPH;
	if (v_mph < -p.rev_limit) {
		f = 0.0;
	} else if (v_mph < -p.rev_cut) {
		f *= (v_mph + p.rev_limit) / (p.rev_limit - p.rev_cut);
	}
	gravar(c, N, e);
	return f;
}

// _razao_patinada
void FisicaCarro::razao_patinada(double v_f) {
	Object *c = carro();
	if (c == nullptr) {
		return;
	}
	const Nomes &N = nomes();
	Array ws = c->get(N.wheels);
	for (int64_t i = 0; i < ws.size(); i++) {
		Dictionary w = ws[i];
		double sr;
		if (!(bool)w[N.hit]) {
			sr = 0.0;
		} else if (absd(v_f) > 1e-6) {
			sr = (double)w[N.omega] * (double)w[N.r] / v_f - 1.0;
		} else {
			sr = 0.1 * (double)w[N.omega];
		}
		w[N.sr] = sr;
	}
}

// _freio_livre
static double freio_livre(double inercia, double omega, double a, double dt) {
	if (absd(omega) < a * dt) {
		a = omega / dt;
	}
	return inercia * a * -(omega < 0.0 ? -1.0 : 1.0);
}

// _giro_rodas
void FisicaCarro::giro_rodas(double dt, double v_f, int64_t rear_g) {
	Object *c = carro();
	if (c == nullptr) {
		return;
	}
	const Nomes &N = nomes();
	Node3D *n3 = Object::cast_to<Node3D>(c);
	EstadoMotor e;
	ler(c, N, e);
	double preso_t = c->get(N.preso_t);

	bool preso = false;
	double v_r = e.v_ref;
	if (e.thr_cx > 0.0 && e.emb_in == 0.0 && absd(v_f) < 0.5) {
		if (preso_t == 0.0) {
			preso_t = dt;
			c->set(N.preso_pos, n3->get_global_position());
		} else {
			Vector3 pp = c->get(N.preso_pos);
			if ((n3->get_global_position() - pp).length_squared() < 0.0009) {
				preso_t += dt;
				if (preso_t > 0.33) {
					preso = true;
					Vector3 pa = c->get(N.pos_ant);
					v_r = (n3->get_global_position() - pa).dot(n3->get_global_transform().basis.get_column(2)) / dt;
				}
			} else {
				preso_t = 0.0;
			}
		}
	} else {
		preso_t = 0.0;
	}
	c->set(N.preso, preso);
	c->set(N.preso_t, preso_t);

	Array ws = c->get(N.wheels);
	int nf_s = 0, nr_s = 0, n_tr = 0;
	for (int64_t i = 0; i < ws.size(); i++) {
		Dictionary w = ws[i];
		bool fr = w[N.front];
		if (fr) {
			nf_s += 1;
		} else {
			nr_s += 1;
		}
		if (!fr || !p.rear_drive) {
			n_tr += 1;
		}
	}
	double rt = ratio(e.gear);
	double w_mot = rt != 0.0 ? e.rpm * RPM2RAD / rt : 0.0;
	double dmax = e.brake_in * MPH_G * p.brake_decel * brake_fscale.eval(e.mu_medio);
	double d_fr = p.front_bias * dmax;
	for (int64_t i = 0; i < ws.size(); i++) {
		Dictionary w = ws[i];
		bool fr = w[N.front];
		bool motriz = !fr || !p.rear_drive;
		double I = w[N.inercia];
		double om = w[N.omega];
		double rr = w[N.r];
		double sl = w[N.slip];
		bool hit = w[N.hit];
		double t_mot = motriz ? e.clutch * rt * e.eng_torque / n_tr : 0.0;
		double t_frei = (fr ? d_fr / nf_s : (dmax - d_fr) / nr_s) * rr * 1000.0;
		double t;
		if (!motriz) {
			if (hit) {
				t = I * (v_r * (1.0 + sl) / rr - om) / dt;
			} else {
				t = freio_livre(I, om, maxd(GIRO_LIVRE, t_frei / I), dt);
			}
		} else if (rear_g >= 1) {
			double alvo = v_r * (1.0 + sl) / rr;
			if (preso) {
				alvo = w_mot * e.clutch;
			}
			t = I * (alvo - om) / dt;
		} else if (e.cstate == 3) {
			t = I * (w_mot - om) / dt;
		} else {
			double s_w = om < 0.0 ? -1.0 : 1.0;
			double liq = t_mot - s_w * t_frei;
			if (absd(liq) > 1e-6) {
				double dw = liq * dt / I;
				t = liq;
				if (absd(t_mot) < absd(t_frei)) {
					if (absd(om) < absd(dw)) {
						t = -I * om / dt;
					}
				} else if ((w_mot < 0.0 ? -1.0 : 1.0) == (dw < 0.0 ? -1.0 : 1.0) && absd(w_mot - om) < absd(dw)) {
					t = I * (w_mot - om) / dt;
				}
			} else {
				t = freio_livre(I, om, GIRO_LIVRE, dt);
			}
		}
		om += t * dt / I;
		w[N.omega] = om;
		w[N.spin] = fposmod((double)w[N.spin] + om * dt, TAU_);
	}
}
