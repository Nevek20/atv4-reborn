// Pneus em C++ (porta linha a linha do carro/car.gd: _tires, _powerslide,
// _corte_recuperacao, _side_to_fwd, _h_lat, _arrasto). Mesmos números do
// GDScript: escalar em double, vetor em Vector3 (float), mesma ordem das
// contas e das forças aplicadas. Os comentários com endereço do exe estão no
// car.gd; aqui só o que ajuda a ler.
#include "fisica_carro.h"

#include <godot_cpp/classes/rigid_body3d.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

#include "mat.h"

using namespace godot;
using namespace atv4;

// roda (Dictionary do car.gd) copiada pra cá no começo e gravada no fim
struct Roda {
	bool hit, front, abs, sat;
	double fx, fz, sr, slip, grip, mu, y0, x, r, px, pz;
};

// estado do carro que os pneus usam
struct EstadoPneu {
	double stf_blend, sideslip, steer, steer_cx, ps_qtd, ps_esc, ps_emb_ant, drive_slip;
	double throttle, brake_in, mu_medio, amort_medio, air_time, emb_in;
	int64_t ps_estado, gear, grounded;
	bool rtc_patinou, lateral_game;
};

static bool motriz(const Roda &w, const FisicaCarro::Params &p) {
	return !w.front || !p.rear_drive;
}

// _h_lat
static double h_lat_de(const FisicaCarro::Params &p, RigidBody3D *b, const Vector3 &left) {
	double s = absd(b->get_global_transform().basis.get_column(1).dot(left));
	if (s > p.h_lat_s1) {
		return p.h_lat_roll;
	}
	if (s > p.h_lat_s0) {
		return p.h_lat + (s - p.h_lat_s0) / (p.h_lat_s1 - p.h_lat_s0) * (p.h_lat_roll - p.h_lat);
	}
	return p.h_lat;
}

// _arrasto
double FisicaCarro::arrasto_de(Object *c, double amort_medio, int64_t n_rodas, double spd, double dt) const {
	const Nomes &N = nomes();
	double k = p.air_drag * 0.65 + amort_medio * p.ground_drag * 10.0;
	Variant agua = c->get(N.agua);
	if (agua.get_type() != Variant::NIL) {
		PackedFloat32Array prof = c->get(N.agua_prof);
		double d = 0.0;
		int64_t m = n_rodas < prof.size() ? n_rodas : prof.size();
		for (int64_t i = 0; i < m; i++) {
			d += prof[i];
		}
		d /= (double)n_rodas;
		if (d > 0.0) {
			double cc = p.water_drag;
			if (d < p.water_depth) {
				cc *= d / p.water_depth;
			}
			k += cc * 10.0;
		}
	}
	double mass = Object::cast_to<RigidBody3D>(c)->get_mass();
	return mind(k * spd * spd, mass * spd / dt);
}

double FisicaCarro::arrasto(double spd, double dt) const {
	Object *c = carro();
	if (c == nullptr) {
		return 0.0;
	}
	Array ws = c->get(nomes().wheels);
	return arrasto_de(c, c->get(nomes().amort_medio), ws.size(), spd, dt);
}

// _side_to_fwd
static double side_to_fwd(const FisicaCarro::Params &p, EstadoPneu &e, double f_side, double ss_deg) {
	double frac = 0.0;
	if (ss_deg > p.side_to_fwd_max) {
		frac = 1.0;
	} else if (ss_deg > p.side_to_fwd_min) {
		frac = (ss_deg - p.side_to_fwd_min) / (p.side_to_fwd_max - p.side_to_fwd_min);
	}
	if (frac <= 0.0) {
		return 0.0;
	}
	double k = e.ps_estado == 0 ? p.side_to_fwd : p.ps_side_to_fwd;
	e.stf_blend = e.throttle * frac * k;
	return e.throttle * absd(f_side) * frac * k;
}

// _corte_recuperacao
double FisicaCarro::corte_recuperacao(EstadoPneu &e, std::vector<Roda> &ws, RigidBody3D *b, int64_t i_fl,
		double dt, double v_f, double v_p, double yaw) const {
	if (!p.rtc_on || v_p / MPH_G <= p.ss_zero || v_f <= 0.0) {
		return 0.0;
	}
	double ang = absd(e.sideslip) / DEG;
	double mph_f = v_f / MPH_G;
	double th = rtc_th.sample(mph_f);
	double mx = rtc_max.sample(mph_f);
	double cut = rtc_cut.sample(mph_f);
	if (mx - th < 0.1) {
		mx = th + 0.1;
	}
	double f = 0.0;
	if (ang > mx) {
		f = cut * e.throttle;
	} else if (ang > th) {
		f = (ang - th) / (mx - th) * cut * e.throttle;
	}
	bool rodando = false;
	if (p.rtc_steer && ang > th) {
		if (e.steer * e.sideslip < 0.0 || absd(e.steer) < 1e-6) {
			if (absd(e.steer) < 1e-6) {
				const Roda &fl = ws[i_fl];
				Vector3 com = b->get_center_of_mass();
				double r = Vector2(fl.px - com.x, fl.pz - com.z).length();
				rodando = v_p / r < absd(yaw);
			}
			f = e.throttle;
		} else {
			f = (f - 1.0) * absd(e.steer) + 1.0;
		}
	}
	if (f > 0.01) {
		for (Roda &w : ws) {
			double lim = mind((w.front ? p.rtc_front : p.rtc_rear) * f, p.slip_max);
			if (w.slip > -0.1 && w.slip < lim) {
				e.rtc_patinou = true;
				w.slip = mind(w.slip + p.slip_grow * dt, lim);
			}
		}
	}
	return rodando ? 0.0 : f;
}

// _powerslide
void FisicaCarro::powerslide(EstadoPneu &e, std::vector<Roda> &ws, double dt, double v_p) const {
	if (e.air_time > p.ps_air) {
		e.ps_qtd = 0.0;
		e.ps_estado = 0;
	} else if (e.ps_estado == 0) {
		if (absd(e.steer) > 0.0 && e.throttle > 0.0 && e.emb_in < e.ps_emb_ant) {
			e.ps_estado = 1;
		}
	} else if (e.ps_estado == 1) {
		if (e.ps_emb_ant < e.emb_in || e.throttle == 0.0) {
			e.ps_estado = 3;
		} else {
			e.ps_qtd += p.ps_growth * dt;
			if (e.ps_qtd > 1.0) {
				e.ps_qtd = 1.0;
				e.ps_estado = 2;
			}
		}
	} else if (e.ps_estado == 2) {
		if (e.ps_emb_ant < e.emb_in) {
			e.ps_estado = 0;
		} else if (e.throttle == 0.0 || e.steer * e.sideslip >= 0.0) {
			e.ps_estado = 3;
		}
	} else if (e.ps_estado == 3) {
		e.ps_qtd -= p.ps_decay * dt;
		if (e.ps_qtd < 0.0) {
			e.ps_qtd = 0.0;
			e.ps_estado = 0;
		}
	}
	e.ps_esc = ps_scale.sample(v_p / MPH_G);
	e.ps_emb_ant = e.emb_in;
	if (e.ps_estado == 1 || e.ps_estado == 2) {
		for (Roda &w : ws) {
			if (motriz(w, p)) {
				const Elipse &el = w.front ? p.ell_f : p.ell_r;
				w.grip = el.ms.eval(mind(w.mu, 1.0)) * p.ps_ellipse;
			}
		}
	}
}

// _tires: devolve as forças pra frente do passo (0x211e48)
double FisicaCarro::pneus(double dt, Vector3 v, Vector3 fwd, Vector3 left, Vector3 n, Vector3 com_w,
		double h, double drive) {
	Object *c = carro();
	RigidBody3D *b = Object::cast_to<RigidBody3D>(c);
	if (b == nullptr) {
		return 0.0;
	}
	(void)h;
	const Nomes &N = nomes();
	EstadoPneu e;
	e.ps_qtd = c->get(N.ps_qtd);
	e.ps_esc = c->get(N.ps_esc);
	e.ps_emb_ant = c->get(N.ps_emb_ant);
	e.steer = c->get(N.steer);
	e.steer_cx = c->get(N.steer_cx);
	e.throttle = c->get(N.throttle);
	e.brake_in = c->get(N.brake_in);
	e.mu_medio = c->get(N.mu_medio);
	e.amort_medio = c->get(N.amort_medio);
	e.air_time = c->get(N.air_time);
	e.emb_in = c->get(N.emb_in);
	e.ps_estado = c->get(N.ps_estado);
	e.gear = c->get(N.gear);
	e.grounded = c->get(N.grounded);
	e.lateral_game = c->get(N.lateral_game);
	e.drive_slip = c->get(N.drive_slip);
	e.rtc_patinou = c->get(N.rtc_patinou);

	Array wd = c->get(N.wheels);
	std::vector<Roda> ws((size_t)wd.size());
	for (int64_t i = 0; i < wd.size(); i++) {
		Dictionary d = wd[i];
		Roda &w = ws[i];
		w.hit = d[N.hit];
		w.front = d[N.front];
		w.abs = d[N.abs];
		w.sat = d[N.sat];
		w.sr = d[N.sr];
		w.slip = d[N.slip];
		w.grip = d[N.grip];
		w.mu = d[N.mu];
		w.y0 = d[N.y0];
		w.x = d[N.x];
		w.r = d[N.r];
		w.px = d[N.px];
		w.pz = d[N.pz];
	}
	Array jo = c->get(N.jit_order);
	int64_t i_fl = jo.size() > 0 ? (int64_t)jo[0] : 0;

	double mass = b->get_mass();
	double gravity_scale = b->get_gravity_scale();
	double inertia_y = b->get_inertia().y;
	Vector3 com = b->get_center_of_mass();

	double v_f = v.dot(fwd);
	double v_l = v.dot(left);
	double v_p = std::sqrt(v_f * v_f + v_l * v_l);
	double mph = v_p / MPH_G;
	double mu = e.mu_medio;
	double yaw = b->get_angular_velocity().dot(n);
	double sgn_v = v_f < 0.0 ? -1.0 : 1.0;
	e.stf_blend = 0.0;

	e.sideslip = v_p >= 0.316 ? std::asin(clampd(v_l / v_p, -1.0, 1.0)) : 0.0;

	// curvatura
	double delta = e.steer * steer_curve.sample(mph) * DEG;
	double kappa = delta / ((p.axle_f - p.axle_r) + v_p * v_p * p.understeer_raw * 0.001);
	if (absd(v_f) < 0.223472) {
		kappa *= absd(v_f) / 0.223472;
	}

	int nf = 0, nr = 0;
	for (Roda &w : ws) {
		w.fx = 0.0;
		w.fz = 0.0;
		if (w.hit) {
			if (w.front) {
				nf += 1;
			} else {
				nr += 1;
			}
		}
	}
	int nf_s = 0, nr_s = 0;
	for (Roda &w : ws) {
		if (w.front) {
			nf_s += 1;
		} else {
			nr_s += 1;
		}
	}

	// tração
	int n_drive = p.rear_drive ? nr_s : nf_s + nr_s;
	if (n_drive > 0) {
		for (Roda &w : ws) {
			if (w.hit && (!w.front || !p.rear_drive)) {
				w.fz += drive / n_drive;
			}
		}
	}

	// freio
	double brk = e.brake_in;
	if (brk > 0.0 && (nf + nr) > 0) {
		double dmax = brk * MPH_G * p.brake_decel * brake_fscale.eval(mu);
		double f_prev = mass * (double)b->get_gravity().dot(fwd) * gravity_scale;
		double spd = v.length();
		if (spd > 1e-6) {
			f_prev -= arrasto_de(c, e.amort_medio, (int64_t)ws.size(), spd, dt) * v_f / spd;
		}
		for (Roda &w : ws) {
			f_prev += w.fz;
		}
		double v_prev = v_f + f_prev * dt / mass;
		double dec = absd(v_prev) < dmax * dt ? -v_prev / dt : dmax * -signd(v_prev);
		double dec_front = p.front_bias * dec;
		for (Roda &w : ws) {
			if (!w.hit) {
				w.abs = false;
				continue;
			}
			if (p.abs_on) {
				if (w.sr < p.abs_eng) {
					w.abs = true;
				} else if (w.sr >= p.abs_dis) {
					w.abs = false;
				}
			}
			if (w.abs) {
				continue;
			}
			if (w.front) {
				w.fz += mass * dec_front / nf_s;
			} else {
				w.fz += mass * (dec - dec_front) / nr_s;
			}
		}
	}

	// derrapagem
	e.rtc_patinou = false;
	double f_cent = mass * v_p * v_p * kappa;
	double ss_deg = absd(e.sideslip) / DEG;
	double target = 0.0;
	if (mph > p.ss_full) {
		target = p.ss_max * DEG * -e.steer;
	} else if (mph > p.ss_zero) {
		target = (mph - p.ss_zero) / (p.ss_full - p.ss_zero) * p.ss_max * DEG * -e.steer;
	} else {
		if (v_p > 1e-6) {
			target = std::asin(clampd(absd(p.axle_r) * kappa, -1.0, 1.0));
		}
		target *= 1.0 - mph / p.ss_zero;
		if (v_f < 0.0) {
			target = -target;
		}
	}
	if (mph < 5.0) {
		target *= mph / 5.0;
	}
	double err = target - e.sideslip;
	double w_err = sgn_v * v_p * kappa - yaw;
	bool low = mph <= p.ss_zero;
	double f_lat = 0.0;
	double torque = 0.0;
	double f_fwd = 0.0;
	Vector3 g_vec = Vector3(0, -1, 0) * (real_t)9.81 * (real_t)gravity_scale * (real_t)mass;
	double sum_x = g_vec.dot(left);
	double sum_z = g_vec.dot(fwd);
	for (Roda &w : ws) {
		sum_z += w.fz;
	}

	if (e.sideslip * target >= 0.0 || low) {
		if (absd(e.sideslip) < absd(target)) {
			// A) derrapagem crescendo até o alvo
			f_lat = f_cent;
			double path = 0.0;
			if (v_p > 1e-6) {
				path = sgn_v * ((v_f * (f_cent + sum_x) - v_l * sum_z) / mass / (v_p * v_p) - yaw);
			}
			double rate = p.yaw_inc.eval(mu, mph) * DEG;
			double acc = rate * signd(err) * sgn_v;
			double err_deg = absd(err) / DEG;
			if (signd(path) == signd(err) && err_deg < p.tail_off) {
				acc *= (std::cos((p.tail_off - err_deg) / p.tail_off * PI_) + 1.0) * 0.5;
				if (e.steer * e.steer_cx > 0.0) {
					double k = maxd((10.0 - err_deg) / 10.0, 0.0);
					acc = (1.0 - k) * acc + k * (-w_err / dt);
				}
			}
			double step = -acc * dt;
			if (low) {
				double s1 = signd(step + yaw);
				double s2 = signd(e.steer * sgn_v);
				if (s1 == -s2) {
					step = w_err;
					if (absd(yaw) >= 0.5 * DEG) {
						step = -0.25 * yaw;
					}
				}
			}
			double cap = p.yaw_acc * dt;
			step = clampd(step, -cap, cap);
			torque = inertia_y * step / dt;
		} else {
			// B) passou do alvo
			double corte = corte_recuperacao(e, ws, b, i_fl, dt, v_f, v_p, yaw);
			double decel = p.side_std.eval(mu) * MPH_G;
			double vt = std::tan(target) * absd(v_f);
			double a = absd(vt - v_l) < decel * dt ? (vt - v_l) / dt : decel * -signd(v_l);
			double f_side = mass * a;
			f_fwd = side_to_fwd(p, e, f_side, ss_deg);
			f_lat = f_cent + f_side;
			double lim = dt * lerpd(p.yaw_dec_zero.eval(mu, mph), p.yaw_dec_full.eval(mu, mph), e.throttle) * DEG;
			torque = inertia_y * clampd(w_err, -lim, lim) / dt;
			torque *= 1.0 - corte;
		}
	} else {
		// C) contra-esterço
		double fc = f_cent;
		fc = ss_deg > 5.0 ? 0.0 : fc * (5.0 - ss_deg) / 5.0;
		double decel = p.side_cs.eval(mu) * MPH_G;
		double vv = v_l + fc / mass * dt;
		double a = absd(vv) < decel * dt ? -vv / dt : decel * -signd(vv);
		double f_side = mass * a;
		f_fwd = side_to_fwd(p, e, f_side, ss_deg);
		f_lat = fc + f_side;
		double rate = signd(err) * p.yaw_dec_cs.eval(mu, mph) * DEG;
		double s = 1.0;
		if (ss_deg < p.cs_scale_ss) {
			s = (ss_deg / p.cs_scale_ss) * (ss_deg / p.cs_scale_ss);
		}
		s *= e.throttle;
		double cap = p.yaw_acc * ((1.0 - s) + s * p.cs_scale);
		rate = clampd(rate, -cap, cap);
		if (v_f < 0.0) {
			rate = -rate;
		}
		torque = inertia_y * -rate;
		torque *= 1.0 - corte_recuperacao(e, ws, b, i_fl, dt, v_f, v_p, yaw);
	}

	// divide entre os eixos
	double a_f = p.axle_f;
	double b_r = p.axle_r;
	double span = a_f - b_r;
	if (v_f < 0.0) {
		f_fwd = 0.0;
	}
	int n_all = nf_s + nr_s;
	for (Roda &w : ws) {
		if (w.front) {
			w.fx += (-b_r / span) * (f_lat + torque / -b_r) / nf_s;
		} else {
			w.fx += (a_f / span) * (f_lat - torque / a_f) / nr_s;
		}
		w.fz += f_fwd / n_all;
	}

	powerslide(e, ws, dt, v_p);

	// elipse de atrito
	double lat_dem = 0.0;
	double lat_got = 0.0;
	for (Roda &w : ws) {
		const Elipse &el = w.front ? p.ell_f : p.ell_r;
		double mu_w = mind(w.mu, 1.0);
		double W = w.grip * el.w.eval(mu_w) * p.width_scale * 1000.0;
		double H = w.grip * el.h.eval(mu_w) * p.height_scale * 1000.0;
		if (w.mu >= p.ell_disable) {
			W = INFINITY;
			H = INFINITY;
		}
		double fx = w.fx;
		double fz = w.fz;
		bool clamped = false;
		if (absd(fx) < 0.01) {
			if (absd(fz) > H) {
				w.fz = fz * H / absd(fz);
				clamped = true;
			}
		} else if (absd(fz) < 0.01) {
			if (absd(fx) > W) {
				w.fx = fx * W / absd(fx);
				clamped = true;
			}
		} else {
			double t = fz / fx;
			double lim = 1.0 / std::sqrt(1.0 / (W * W) + t * t / (H * H));
			if (lim < absd(fx)) {
				double k = lim / absd(fx);
				w.fx = fx * k;
				w.fz = fz * k;
				clamped = true;
			}
		}
		double min_scale = el.ms.eval(mu_w);
		if (motriz(w, p) && (e.ps_estado == 1 || e.ps_estado == 2)) {
			min_scale *= p.ps_ellipse;
		}
		w.sat = clamped;
		lat_dem += absd(fx);
		lat_got += absd(w.fx);
		if (clamped) {
			w.grip = maxd(w.grip - el.shrink * dt, min_scale);
		} else {
			w.grip = mind(w.grip + el.recover * dt, 1.0);
		}
	}

	// patinada de cada roda (0x610)
	double lim_slip = -INFINITY;
	if (absd(ratio(e.gear)) > 1e-6 && absd(v_f) > 0.5) {
		double ref_rpm = drive_curve.max;
		if (absd(e.steer) > 0.5 && absd(v_f) < 40.0 * MPH) {
			ref_rpm = p.lim_on * 0.95;
		}
		lim_slip = mind(ref_rpm * RPM2RAD * p.wheel_r / (absd(ratio(e.gear)) * absd(v_f)) - 1.0, p.slip_max);
	}
	e.drive_slip = -INFINITY;
	for (Roda &w : ws) {
		if (w.sat) {
			double fl = w.fz * v_f;
			if (fl > 1e-6) {
				if (lim_slip > -INFINITY) {
					w.slip = mind(w.slip + p.slip_grow * dt, lim_slip);
				}
			} else if (fl < -1e-6 && e.brake_in > 0.1) {
				w.slip = maxd(w.slip - p.lock_grow * dt, -1.0);
			}
		} else if (w.slip < 0.0) {
			w.slip = mind(w.slip + p.lock_recover * dt, 0.0);
		} else if (!e.rtc_patinou) {
			w.slip = maxd(w.slip - p.slip_recover * dt, 0.0);
		}
		if (!w.front || !p.rear_drive) {
			e.drive_slip = maxd(e.drive_slip, w.slip);
		}
	}

	// roda travando
	if (v_p > TRAVA_MPH * MPH_G) {
		double v_up = v.dot(n);
		for (Roda &w : ws) {
			if (w.abs) {
				continue;
			}
			double f = 0.0;
			if (w.sr < TRAVA_FIM) {
				f = 1.0;
			} else if (w.sr < TRAVA_INI) {
				f = (w.sr - TRAVA_INI) / (TRAVA_FIM - TRAVA_INI);
			}
			if (f <= 0.0) {
				continue;
			}
			Vector3 fv((real_t)w.fx, 0.0f, (real_t)w.fz);
			double tam = fv.length();
			Vector3 desl((real_t)v_l, (real_t)v_up, (real_t)(-v_f * w.sr));
			if (tam < 1e-6 || desl.length() < 1e-6) {
				continue;
			}
			Vector3 fh = fv / (real_t)tam;
			Vector3 contra = -desl.normalized();
			Vector3 d = contra;
			if (f < 1.0) {
				d = fh * (real_t)(1.0 - f) + contra * (real_t)f;
				if (d.length() > 1e-6) {
					d = d.normalized();
				} else {
					d = f < 0.5 ? fh : contra;
				}
			}
			w.fx = (double)d.x * tam;
			w.fz = (double)d.z * tam;
		}
	}

	// limite da velocidade de derrapagem (0x210ce0)
	if (e.grounded > 0) {
		double sx = 0.0;
		double sz = 0.0;
		for (Roda &w : ws) {
			sx += w.fx;
			sz += w.fz;
		}
		double yaw_now = b->get_angular_velocity().dot(n);
		double beta_rate = -yaw_now * sgn_v;
		if (v_p > 1e-6) {
			beta_rate = ((v_f * sx - v_l * sz) / mass / (v_p * v_p) - yaw_now) * sgn_v;
		}
		if (v_f > 0.0 && v_p < 30.0 * MPH_G && e.steer != 0.0 && yaw_now * e.steer > 0.0) {
			const Roda &fw = e.steer > 0.0 ? ws[0] : ws[1];
			Vector3 r_fw = Vector3((real_t)fw.px, 0.0f, (real_t)fw.pz) - Vector3(com.x, 0.0f, com.z);
			Vector3 dir_loc = Vector3((real_t)v_l, 0.0f, (real_t)v_f).normalized();
			if ((double)dir_loc.dot(r_fw.normalized()) < 0.8660254) {
				double cap_w = v_p / (double)r_fw.length();
				if (absd(yaw_now) > cap_w) {
					b->set_angular_velocity(b->get_angular_velocity() + n * (real_t)(signd(e.steer) * cap_w - yaw_now));
					yaw_now = signd(e.steer) * cap_w;
				}
			}
		}
		if (absd(v_f) > 2.0) {
			double ss_d = absd(e.sideslip) / DEG;
			bool growing = beta_rate * e.sideslip > 0.0;
			double mr = (growing ? p.ss_rate_inc : p.ss_rate_dec).eval(mu, ss_d);
			double a_ps = e.ps_qtd * e.ps_esc;
			if (a_ps > 0.0 && growing) {
				mr = (1.0 - a_ps) * mr + a_ps * ps_rate.sample(ss_d);
			}
			if (absd(beta_rate) > mr * DEG) {
				double ex = beta_rate - signd(beta_rate) * mr * DEG;
				if (ex * yaw_now > 0.0) {
					ex = 0.0;
				} else if (absd(yaw_now) < absd(ex)) {
					ex = -yaw_now;
				}
				if (absd(v_f) < 20.0) {
					ex *= (absd(v_f) - 2.0) / 18.0;
				}
				if (ex != 0.0) {
					b->set_angular_velocity(b->get_angular_velocity() + n * (real_t)(sgn_v * ex));
				}
			}
		}
	}

	// aplica as forças de cada roda (0x211b58)
	double sum_f = 0.0;
	double sum_r = 0.0;
	for (Roda &w : ws) {
		double hy = w.y0 + w.x - w.r - (double)com.y;
		if (w.front) {
			sum_f += hy;
		} else {
			sum_r += hy;
		}
	}
	double hl = e.stf_blend * p.h_long_stf + (1.0 - e.stf_blend) * p.h_long;
	double h_lat = h_lat_de(p, b, left);
	Vector3 base = com_w - b->get_global_position();
	double lat_sum = 0.0;
	for (Roda &w : ws) {
		double az = w.front ? p.axle_f : p.axle_r;
		double sy = w.front ? sum_f : sum_r;
		if (w.fx != 0.0) {
			if (e.lateral_game) {
				b->apply_force(left * (real_t)w.fx, base + n * (real_t)(sy * h_lat) + fwd * (real_t)az);
			} else {
				lat_sum += w.fx;
			}
		}
		if (w.fz != 0.0) {
			b->apply_force(fwd * (real_t)w.fz, base + n * (real_t)(sy * hl) + fwd * (real_t)az);
		}
	}
	if (!e.lateral_game) {
		double keep = lat_dem < 1.0 ? 1.0 : lat_got / lat_dem;
		b->apply_force(left * (real_t)lat_sum, base + n * (real_t)(sum_r * h_lat));
		b->apply_torque(n * (real_t)torque * (real_t)keep);
	}

	// atrito interno
	double f_int = 0.0;
	if (e.throttle < 0.05 && absd(v_f) > 0.1) {
		double k2 = clampd((absd(mph) - p.ifd_lo_speed) / (p.ifd_hi_speed - p.ifd_lo_speed), 0.0, 1.0);
		double dec2 = lerpd(p.ifd_lo, p.ifd_hi, k2) * MPH;
		f_int = -sgn_v * mind(dec2 * mass, mass * absd(v_f) / dt);
		b->apply_central_force(fwd * (real_t)f_int);
	}
	for (Roda &w : ws) {
		f_int += w.fz;
	}

	// grava o estado
	for (int64_t i = 0; i < wd.size(); i++) {
		Dictionary d = wd[i];
		const Roda &w = ws[i];
		d[N.fx] = w.fx;
		d[N.fz] = w.fz;
		d[N.abs] = w.abs;
		d[N.sat] = w.sat;
		d[N.slip] = w.slip;
		d[N.grip] = w.grip;
	}
	c->set(N.stf_blend, e.stf_blend);
	c->set(N.sideslip, e.sideslip);
	c->set(N.rtc_patinou, e.rtc_patinou);
	c->set(N.ps_estado, e.ps_estado);
	c->set(N.ps_qtd, e.ps_qtd);
	c->set(N.ps_esc, e.ps_esc);
	c->set(N.ps_emb_ant, e.ps_emb_ant);
	c->set(N.drive_slip, e.drive_slip);
	return f_int;
}
