// Som dos pneus em C++ (porta do som/sfx_carro.gd _roda, linha a linha). O
// tocador (som_jogo.gd) continua no GDScript: daqui só liga, desliga e muda
// volume e tom dele.
#include "som.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

#include "mat.h"

using namespace godot;
using namespace atv4;

namespace {

// float(d.get(k, padrao)) do GDScript (os atributos do XML vêm como texto)
double f_de(const Dictionary &d, const char *k, double padrao = 0.0) {
	Variant v = d.get(String(k), padrao);
	if (v.get_type() == Variant::STRING) {
		return ((String)v).to_float();
	}
	return (double)v;
}

} // namespace

void SomPneuCpp::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configurar", "sfx"), &SomPneuCpp::configurar);
	ClassDB::bind_method(D_METHOD("rodas_passo", "dt", "v", "spd", "side", "ws", "derrapa"), &SomPneuCpp::rodas_passo);
}

const SomPneuCpp::Mat &SomPneuCpp::mat_de(const String &nome) const {
	auto it = materiais.find(nome);
	return it != materiais.end() ? it->second : padrao;
}

bool SomPneuCpp::configurar(Object *sfx) {
	ok = false;
	if (sfx == nullptr) {
		return false;
	}
	Object *car = sfx->get("car");
	if (car == nullptr) {
		return false;
	}
	car_id = car->get_instance_id();
	auto ler_mat = [](const Dictionary &a) {
		Mat m;
		m.existe = true;
		m.pitch = f_de(a, "Pitch", 1.0);
		m.volume = f_de(a, "Volume", 1.0);
		m.surface = a.get("SurfacePatch", "Default");
		m.secondary = a.get("SecondaryPatch", "Default");
		return m;
	};
	materiais.clear();
	Dictionary ms = sfx->get("materiais");
	Array mk = ms.keys();
	for (int64_t i = 0; i < mk.size(); i++) {
		materiais[(String)mk[i]] = ler_mat(ms[mk[i]]);
	}
	padrao = Mat();
	padrao.surface = "Default";
	padrao.secondary = "Default";
	if (ms.has("Default")) {
		padrao = materiais["Default"];
	}
	tem_agua = ms.has("Water");
	if (tem_agua) {
		agua = materiais["Water"];
	}
	patches.clear();
	Dictionary ps = sfx->get("patches");
	Array pk = ps.keys();
	for (int64_t i = 0; i < pk.size(); i++) {
		Dictionary pd = ps[pk[i]];
		Patch p;
		p.looping = pd.has("looping");
		if (p.looping) {
			Dictionary lp = pd["looping"];
			p.sample = lp.get("sample", "");
			Dictionary pv = lp.get("volume", Dictionary());
			Dictionary pp = lp.get("pitch", Dictionary());
			p.v_min = f_de(pv, "MinSpeed");
			p.v_max = f_de(pv, "MaxSpeed");
			p.v_side = f_de(pv, "SideSpeed");
			p.v_spin = f_de(pv, "Wheelspin");
			p.v_lock = f_de(pv, "WheelLock");
			p.v_attack = f_de(pv, "AttackLevel");
			p.v_steer = f_de(pv, "Steer");
			p.v_acc = f_de(pv, "Acc");
			p.v_susp = f_de(pv, "Suspension");
			p.v_vol = f_de(pv, "Volume");
			p.v_thr = f_de(pv, "MinThreshold");
			p.v_decay = f_de(pv, "DecayRate");
			p.p_pitch = f_de(pp, "Pitch", 1.0);
			p.p_speed = f_de(pp, "Speed");
			p.p_side = f_de(pp, "SideSpeed");
			p.p_spin = f_de(pp, "Wheelspin");
			p.p_lock = f_de(pp, "WheelLock");
			p.p_steer = f_de(pp, "Steer");
			p.p_acc = f_de(pp, "Acc");
			p.p_diff = f_de(pp, "WheelDiff");
			p.p_susp = f_de(pp, "Suspension");
		}
		patches[(String)pk[i]] = p;
	}
	Dictionary modelo = sfx->get("modelo");
	susp_off = f_de(modelo, "SuspensionOffset");
	susp_esc = f_de(modelo, "SuspensionScale", 3.4375);
	Dictionary master = sfx->get("master");
	master_sfx = f_de(master, "SFXVolume", 1.0);
	master_surface = f_de(master, "SurfaceVolume", 0.5);
	rolagem = sfx->get("ROLAGEM");
	so_derrapando = sfx->get("SO_DERRAPANDO");
	rodas.clear();
	Array rs = sfx->get("rodas");
	for (int64_t i = 0; i < rs.size(); i++) {
		Dictionary o = rs[i];
		Roda r;
		Object *som = o["som"];
		if (som == nullptr) {
			return false;
		}
		r.som = som->get_instance_id();
		r.idx = (int)(int64_t)o["idx"];
		r.sec = o["sec"];
		r.trava = o["trava"];
		r.mat = o["mat"];
		r.s = o["s"];
		r.vol = o["vol"];
		r.o = o;
		rodas.push_back(r);
	}
	sfx_chao.clear();
	ok = true;
	return true;
}

// o laço das rodas do passo() (_roda pra cada uma)
bool SomPneuCpp::rodas_passo(double dt, double v, double spd, double side, double ws, double derrapa) {
	if (!ok) {
		return false;
	}
	Object *car = ObjectDB::get_instance(car_id);
	if (car == nullptr) {
		return false;
	}
	static const StringName S_JIT("jit_order"), S_WHEELS("wheels"), S_TERRAIN("terrain"), S_AGUA("agua"),
			S_AGUA_PROF("agua_prof"), S_STEER("steer"), S_THROTTLE("throttle"), S_MAT("mat"), S_HIT("hit"),
			S_X("x"), S_SR("sr"), S_TOCANDO("tocando"), S_NOME("nome"), S_TOCAR("tocar"), S_PARAR("parar"),
			S_TOM("tom"), S_VOLUME("volume"), S_SFX("sfx"), S_HAS("has_method"), S_TRAVA("trava"), S_S("s"),
			S_VOL("vol");
	Array jo = car->get(S_JIT);
	Array wheels = car->get(S_WHEELS);
	Object *terrain = car->get(S_TERRAIN);
	bool tem_sfx = terrain != nullptr && (bool)terrain->call(S_HAS, S_SFX);
	bool na_agua = car->get(S_AGUA).get_type() != Variant::NIL;
	PackedFloat32Array prof;
	if (na_agua) {
		prof = car->get(S_AGUA_PROF);
	}
	double steer = car->get(S_STEER);
	double throttle = car->get(S_THROTTLE);
	for (Roda &o : rodas) {
		Object *som = ObjectDB::get_instance(o.som);
		if (som == nullptr) {
			continue;
		}
		int64_t ri = jo[o.idx];
		Dictionary w = wheels[ri];
		int64_t wm = w[S_MAT];
		int64_t m = wm > 0 ? wm : 0;
		// _sfx_chao(m)
		String nome = "Dirt";
		if (tem_sfx) {
			auto it = sfx_chao.find(m);
			if (it == sfx_chao.end()) {
				nome = terrain->call(S_SFX, m);
				sfx_chao[m] = nome;
			} else {
				nome = it->second;
			}
		}
		const Mat *mat = &mat_de(nome);
		if (na_agua && (double)prof[ri] > -0.05 && tem_agua) {
			m = -3;
			mat = &agua;
		}
		const String &pn = o.sec ? mat->secondary : mat->surface;
		auto pit = patches.find(pn);
		if (pit == patches.end() || !pit->second.looping || pit->second.v_vol == 0.0) {
			if ((bool)som->get(S_TOCANDO)) {
				som->call(S_PARAR);
			}
			o.vol = 0.0;
			o.o[S_VOL] = o.vol;
			continue;
		}
		const Patch &lp = pit->second;
		bool ataque = false;
		if (o.trava <= 0.0) {
			if (m != o.mat) {
				o.mat = m;
				ataque = true;
				o.o[S_MAT] = m;
			}
			if (lp.sample != (String)som->get(S_NOME) || !(bool)som->get(S_TOCANDO)) {
				som->call(S_TOCAR, "Surface", lp.sample);
				o.trava = 0.07;
			}
		} else {
			o.trava -= dt;
		}
		double vol = 0.0;
		if ((bool)w[S_HIT]) {
			double s = clampd(((double)w[S_X] + susp_off) * susp_esc, 0.0, 1.0);
			o.s = s;
			bool trava = (double)w[S_SR] < -0.95 && v > 2.2347221;
			vol = lp.v_min + spd * (lp.v_max - lp.v_min);
			if (spd < 0.025) {
				vol *= 40.0 * spd;
			}
			vol += side * lp.v_side + ws * lp.v_spin;
			if (trava) {
				vol += lp.v_lock;
			}
			if (ataque) {
				vol += lp.v_attack;
			}
			vol *= (absd(steer) * lp.v_steer + 1.0) * (throttle * lp.v_acc + 1.0);
			vol = (vol - vol * (1.0 - s) * lp.v_susp) * lp.v_vol;
			if (vol < lp.v_thr) {
				vol = 0.0;
			} else {
				vol *= mat->volume;
				if (vol < o.vol) {
					vol = o.vol - (o.vol - vol) * (1.0 - lp.v_decay);
				}
				vol *= master_sfx * master_surface;
			}
			double tom = lp.p_pitch + spd * lp.p_speed + side * lp.p_side + ws * lp.p_spin;
			if (trava) {
				tom += lp.p_lock;
			}
			tom = (tom + absd(steer) * lp.p_steer + throttle * lp.p_acc + o.idx * lp.p_diff + s * lp.p_susp) * mat->pitch;
			som->set(S_TOM, tom);
		}
		o.vol = maxd(vol, 0.0);
		som->set(S_VOLUME, o.vol * (so_derrapando ? rolagem + (1.0 - rolagem) * derrapa : 1.0));
		o.o[S_TRAVA] = o.trava;
		o.o[S_S] = o.s;
		o.o[S_VOL] = o.vol;
	}
	return true;
}

// ---------------------------------------------------------------- motor
#include <godot_cpp/classes/audio_stream_player.hpp>
#include <godot_cpp/classes/audio_stream_player3d.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cmath>

namespace {
const double JOGO_LENTA = 1000.0;   // motor_som.gd
const double JOGO_CORTE = 8000.0;
const double SUAVE = 0.03;
const double RPM_SUAVE = 0.08;
const double PITCH_MIN = 0.5;
const double PITCH_MAX = 1.25;
const double VOLUME_DB = -4.0;
} // namespace

void MotorSomCpp::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configurar", "som"), &MotorSomCpp::configurar);
	ClassDB::bind_method(D_METHOD("atualizar", "rpm_jogo", "carga", "dt"), &MotorSomCpp::atualizar);
}

bool MotorSomCpp::configurar(Object *som) {
	ok = false;
	if (som == nullptr) {
		return false;
	}
	som_id = som->get_instance_id();
	auto ler = [](const Array &a, std::vector<Loop> &out) -> bool {
		out.clear();
		for (int64_t i = 0; i < a.size(); i++) {
			Dictionary d = a[i];
			Loop l;
			l.rpm = d["rpm"];
			l.db = d["db"];
			Object *p = d["p"];
			if (p == nullptr) {
				return false;
			}
			l.p = p->get_instance_id();
			out.push_back(l);
		}
		return !out.empty();
	};
	if (!ler(som->get("_on"), on) || !ler(som->get("_off"), off)) {
		return false;
	}
	lenta_real = som->get("lenta_real");
	corte_real = som->get("corte_real");
	carga = som->get("_carga");
	rpm = som->get("_rpm");
	ok = true;
	return true;
}

void MotorSomCpp::camada(const std::vector<Loop> &lista, double r, double ganho) const {
	int n = (int)lista.size();
	// pesos: no máximo 2 loops (vizinhos), o resto 0
	int i0 = -1, i1 = -1;
	double w0 = 0.0, w1 = 0.0;
	if (r <= lista[0].rpm) {
		i0 = 0;
		w0 = 1.0;
	} else if (r >= lista[n - 1].rpm) {
		i0 = n - 1;
		w0 = 1.0;
	} else {
		for (int i = 0; i < n - 1; i++) {
			if (r < lista[i + 1].rpm) {
				double t = (r - lista[i].rpm) / (lista[i + 1].rpm - lista[i].rpm);
				i0 = i;
				w0 = std::cos(t * PI_ * 0.5);
				i1 = i + 1;
				w1 = std::sin(t * PI_ * 0.5);
				break;
			}
		}
	}
	for (int k = 0; k < n; k++) {
		const Loop &s = lista[k];
		Object *o = ObjectDB::get_instance(s.p);
		AudioStreamPlayer *p2 = Object::cast_to<AudioStreamPlayer>(o);
		AudioStreamPlayer3D *p3 = p2 ? nullptr : Object::cast_to<AudioStreamPlayer3D>(o);
		if (p2 == nullptr && p3 == nullptr) {
			continue;
		}
		double w = (k == i0 ? w0 : (k == i1 ? w1 : 0.0)) * ganho;
		bool tocando = p2 ? p2->is_playing() : p3->is_playing();
		if (w < 0.003) {
			if (tocando) {
				p2 ? p2->stop() : p3->stop();
			}
			continue;
		}
		double pitch = clampd(r / s.rpm, PITCH_MIN, PITCH_MAX);
		double db = VOLUME_DB + s.db + UtilityFunctions::linear_to_db(w);
		if (p2) {
			p2->set_pitch_scale(pitch);
			p2->set_volume_db(db);
			if (!tocando) {
				p2->play();
			}
		} else {
			p3->set_pitch_scale(pitch);
			p3->set_volume_db(db);
			if (!tocando) {
				p3->play();
			}
		}
	}
}

bool MotorSomCpp::atualizar(double rpm_jogo, double carga_, double dt) {
	if (!ok) {
		return false;
	}
	Object *som = ObjectDB::get_instance(som_id);
	if (som == nullptr) {
		return false;
	}
	carga += (clampd(carga_, 0.0, 1.0) - carga) * (1.0 - std::exp(-dt / SUAVE));
	if (rpm < 0.0) {
		rpm = rpm_jogo;
	}
	rpm += (rpm_jogo - rpm) * (1.0 - std::exp(-dt / RPM_SUAVE));
	double r_real = lenta_real + (rpm - JOGO_LENTA) / (JOGO_CORTE - JOGO_LENTA) * (corte_real - lenta_real);
	camada(on, r_real, std::sin(carga * PI_ * 0.5));
	camada(off, r_real, std::cos(carga * PI_ * 0.5));
	som->set("r_real", r_real);
	som->set("_carga", carga);
	som->set("_rpm", rpm);
	return true;
}
