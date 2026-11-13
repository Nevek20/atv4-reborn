// Tremida das rodas e vibração em C++ (porta do carro/carro_montagem.gd:
// _wheel_jitter e _vibracao, um depois do outro como no car.gd). O sorteio é
// o global do Godot (randf/randf_range), na mesma ordem: sai igual.
#include "fisica_carro.h"

#include <godot_cpp/classes/rigid_body3d.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cmath>

#include "mat.h"

using namespace godot;
using namespace atv4;

void FisicaCarro::tremida(double dt, double v_l, double v_f) {
	Object *c = carro();
	RigidBody3D *b = Object::cast_to<RigidBody3D>(c);
	if (b == nullptr) {
		return;
	}
	static const StringName S_JIT("jit"), S_JIT_ORDER("jit_order"), S_JITTER_CHAO("jitter_chao"),
			S_TERRAIN("terrain"), S_WJ("wheel_jitter"), S_SURF("surface_jitter"), S_SEED("jit_seed"),
			S_SPD_G("spd_ground"), S_VIBRACAO("vibracao"), S_POUSO("pouso"), S_AR_SOM("ar_som"),
			S_SUSP_TAXA("susp_taxa"), S_PANCADA("pancada"), S_TREME_ALVO("_treme_alvo"), S_TEM("_tem"),
			S_GROUNDED("grounded");
	const Nomes &N = nomes();
	Array wd = c->get(N.wheels);
	Array jo = c->get(S_JIT_ORDER);
	int64_t nw = wd.size();

	// ---- _wheel_jitter
	for (int64_t i = 0; i < nw; i++) {
		Dictionary w = wd[i];
		w[S_JIT] = 0.0;
	}
	double jitter_chao = 0.0;
	if (jo.size() == 4) {
		Object *terrain = c->get(S_TERRAIN);
		double surf = c->get(S_SURF);
		double spd_ground = c->get(S_SPD_G);
		int64_t seed = c->get(S_SEED);
		int no_chao = 0;
		for (int k = 0; k < 3; k++) {
			Dictionary w = wd[(int64_t)jo[k]];
			if (!(bool)w[N.hit]) {
				continue;
			}
			double wj = surf;
			if (terrain != nullptr) {
				int64_t m = w[N.mat];
				auto it = jitter_mat.find(m);
				if (m >= 0 && it != jitter_mat.end()) {
					wj = it->second;
				} else {
					wj = terrain->call(S_WJ, m, surf);
					if (m >= 0) {
						jitter_mat[m] = wj;
					}
				}
			}
			jitter_chao += wj;
			no_chao += 1;
			double amp = mind(wj * JIT_K * spd_ground, 1.0);
			seed = (seed * 31415821 + 1) & 0x3FFFFFFF;
			w[S_JIT] = amp * ((double)seed * 0.075 / 1073741824.0 - 0.0375);
		}
		Dictionary w3 = wd[(int64_t)jo[3]];
		Dictionary w1 = wd[(int64_t)jo[1]];
		w3[S_JIT] = w1[S_JIT];
		if (no_chao > 0) {
			jitter_chao /= no_chao;
		}
		c->set(S_SEED, seed);
	}
	c->set(S_JITTER_CHAO, jitter_chao);

	// ---- _vibracao
	double v = b->get_linear_velocity().length();
	int64_t grounded = c->get(S_GROUNDED);
	double vibracao = 0.0;
	if (grounded > 0) {
		bool trava = false;
		double pat = 0.0;
		for (int64_t i = 0; i < nw; i++) {
			Dictionary w = wd[i];
			double sr = w[N.sr];
			if (sr < -0.95) {
				trava = true;
			}
			if ((double)w[N.omega] > 3.14) {
				pat = maxd(pat, clampd(sr, 0.0, 1.0));
			}
		}
		double base = 1.5 * absd(v_l);
		if (v < 8.938889 && pat > 0.1) {
			base += 15.0;
		}
		if (trava) {
			base += v * 0.33561218;
		}
		vibracao = base * UtilityFunctions::randf_range(0.1, 0.9);
		if (UtilityFunctions::randf() < 0.1) {
			vibracao += v * 0.25;
		}
		vibracao *= 0.07;
	}
	c->set(S_VIBRACAO, vibracao);
	double pouso = 0.0;
	double ar_som = c->get(S_AR_SOM);
	if (grounded == 0) {
		ar_som += dt;
	} else {
		if (ar_som > 0.1) {
			pouso = 0.5 + 0.5 * mind(1.0, ar_som);
		}
		ar_som = 0.0;
	}
	c->set(S_POUSO, pouso);
	c->set(S_AR_SOM, ar_som);
	static const StringName S_SUSP_ANT("_susp_ant"), S_SUSP_ACIMA("_susp_acima");
	Array susp_ant = c->get(S_SUSP_ANT);
	Array susp_acima = c->get(S_SUSP_ACIMA);
	double media = 0.0;
	if (jo.size() == 4 && susp_ant.size() >= 2) {
		for (int k = 0; k < 2; k++) {
			Dictionary w = wd[(int64_t)jo[k]];
			double d = 0.0;
			if ((bool)w[N.hit]) {
				double s = clampd((double)w[N.x] * SUSP_ESCALA, 0.0, 1.0);
				d = (s - (double)susp_ant[k]) / dt;
				susp_ant[k] = s;
			} else {
				susp_ant[k] = 0.0;
			}
			media += d * 0.5;
		}
	}
	double susp_taxa = clampd(0.4 * (double)c->get(S_SUSP_TAXA) + 0.1 * media, -1.0, 1.0);
	c->set(S_SUSP_TAXA, susp_taxa);
	double tranco = pouso;
	if (absd(v_f) >= SUSP_VEL && susp_acima.size() >= 2) {
		for (int k = 0; k < 2; k++) {
			double lim = k == 0 ? SUSP_PEQUENA : SUSP_GRANDE;
			bool acima = susp_taxa > lim;
			if (acima && !(bool)susp_acima[k]) {
				tranco = maxd(tranco, k == 0 ? 0.4 : 1.0);
			}
			susp_acima[k] = acima;
		}
	} else {
		c->set(S_SUSP_ACIMA, Array::make(false, false));   // _susp_acima = [false, false]
	}
	if (!(bool)c->call(S_TEM, "volante_treme")) {   // VOLANTE_TREME é true
		return;
	}
	double pancada = maxd((double)c->get(S_PANCADA) * std::exp(-dt / PANCADA_SOLTA), tranco);
	c->set(S_PANCADA, pancada);
	double terra = 0.0;
	if (jo.size() == 4) {
		Dictionary w0 = wd[(int64_t)jo[0]];
		Dictionary w2 = wd[(int64_t)jo[2]];
		terra = ((double)w0[S_JIT] - (double)w2[S_JIT]) * TREME_TERRA;
	}
	double r1 = UtilityFunctions::randf_range(-1.0, 1.0);
	double sinal = UtilityFunctions::randf() < 0.5 ? 1.0 : -1.0;
	double alvo = (TREME_GRAUS * vibracao * r1 + TREME_PANCADA_GRAUS * pancada * sinal + terra) * (PI_ / 180.0);
	c->set(S_TREME_ALVO, alvo);
}
