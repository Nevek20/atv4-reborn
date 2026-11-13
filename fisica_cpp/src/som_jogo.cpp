// Vozes do tocador do jogo em C++ (porta do som/som_jogo.gd: _vivas,
// _env_anda, _fase, _aplicar, _dobra). O sequenciador (programas, grãos,
// sorteios) continua no GDScript; aqui só o que roda por voz e por quadro.
// Mesmas contas: double, pow/log da libm, linear_to_db do Godot.
#include "som_jogo.h"

#include <godot_cpp/classes/audio_stream_player.hpp>
#include <godot_cpp/classes/audio_stream_player3d.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cmath>

#include "mat.h"

using namespace godot;
using namespace atv4;

namespace {

struct Fase {
	bool exp;      // exponencial
	bool sobe;
	int64_t sh;    // shift
	int64_t passo;
	double alvo;
};

// _fase (no GDScript & liga antes de ==: aqui com parênteses)
Fase fase_de(int64_t a1, int64_t a2, int64_t fase) {
	switch (fase) {
		case 0:
			return { (a1 >> 15) == 1, true, (a1 >> 10) & 31, 7 - ((a1 >> 8) & 3), 32767.0 };
		case 1:
			return { true, false, (a1 >> 4) & 15, -8, (double)((a1 & 15) + 1) * 2048.0 };
		case 2: {
			bool sobe = ((a2 >> 14) & 1) == 0;
			int64_t k = (a2 >> 6) & 3;
			return { (a2 >> 15) == 1, sobe, (a2 >> 8) & 31, sobe ? 7 - k : -8 + k, sobe ? 32767.0 : 0.0 };
		}
		default:
			return { ((a2 >> 5) & 1) == 1, false, a2 & 31, -8, 0.0 };
	}
}

struct Nomes {
	StringName p, fase, a1, a2, nivel, vol, tom, amp, cur, pb, db_ult, pt_ult;
	Nomes() :
			p("p"), fase("fase"), a1("a1"), a2("a2"), nivel("nivel"), vol("vol"), tom("tom"), amp("amp"),
			cur("cur"), pb("pb"), db_ult("db_ult"), pt_ult("pt_ult") {}
};

const Nomes &nm() {
	static Nomes n;
	return n;
}

// _env_anda: anda o envelope n passos do SPU
void env_anda(Dictionary &v, double n) {
	const Nomes &N = nm();
	int64_t fase = v[N.fase];
	double nivel = v[N.nivel];
	int64_t a1 = v[N.a1];
	int64_t a2 = v[N.a2];
	while (n > 0.0 && fase < 4) {
		Fase f = fase_de(a1, a2, fase);
		int64_t sh = f.sh;
		double ciclos = (double)((int64_t)1 << (sh - 11 > 0 ? sh - 11 : 0));
		double passo = (double)f.passo * (double)((int64_t)1 << (11 - sh > 0 ? 11 - sh : 0));
		double alvo = f.alvo;
		if (f.sobe) {
			double limite = alvo;
			if (f.exp && nivel < 24576.0) {
				limite = 24576.0;
			} else if (f.exp) {
				ciclos *= 4.0;
			}
			double t = (limite - nivel) * ciclos / passo;
			if (t > n) {
				nivel += passo * n / ciclos;
				n = 0.0;
			} else {
				nivel = limite;
				n -= t;
				if (limite == alvo) {
					if (fase == 0) {
						fase = 1;
					} else {
						n = 0.0;
					}
				}
			}
		} else {
			bool chegou = false;
			if (f.exp) {
				double fator = 1.0 + passo / 32768.0;
				double k = n / ciclos;
				if (nivel > alvo + 1.0 && fator > 0.0) {
					k = mind(k, std::log((alvo + 1.0) / nivel) / std::log(fator));
				}
				nivel *= std::pow(maxd(fator, 0.0), k);
				n -= k * ciclos;
				chegou = nivel <= alvo + 1.0;
			} else {
				double t = (alvo - nivel) * ciclos / passo;
				if (t > n) {
					nivel += passo * n / ciclos;
					n = 0.0;
				} else {
					n -= t;
					chegou = true;
				}
			}
			if (chegou) {
				nivel = alvo;
				if (fase == 1) {
					fase = 2;
				} else if (fase == 3) {
					fase = 4;
				} else {
					n = 0.0;
				}
			}
		}
	}
	v[N.fase] = fase;
	v[N.nivel] = nivel;
}

// _dobra: pitch bend do 989snd
double dobra(const Dictionary &v) {
	const Nomes &N = nm();
	Dictionary cur = v[N.cur];
	int64_t pb = cur[N.pb];
	Array lim = v[N.pb];
	double semi = pb >= 0 ? (double)lim[1] * (double)pb / 32767.0 : (double)lim[0] * (double)pb / 32768.0;
	return std::pow(2.0, semi / 12.0);
}

} // namespace

void SomJogoCpp::_bind_methods() {
	ClassDB::bind_method(D_METHOD("vivas", "vozes", "ticks", "volume", "ganho", "tom"), &SomJogoCpp::vivas);
}

// _vivas + _aplicar: devolve a mesma lista se ninguém morreu
Array SomJogoCpp::vivas(Array vozes, double ticks, double volume, double ganho, double tom) {
	const Nomes &N = nm();
	Array out;
	bool mudou = false;
	int64_t n = vozes.size();
	for (int64_t i = 0; i < n; i++) {
		Dictionary v = vozes[i];
		Object *po = v[N.p];
		env_anda(v, ticks);
		AudioStreamPlayer *p2 = Object::cast_to<AudioStreamPlayer>(po);
		AudioStreamPlayer3D *p3 = p2 ? nullptr : Object::cast_to<AudioStreamPlayer3D>(po);
		bool tocando = p2 ? p2->is_playing() : (p3 ? p3->is_playing() : false);
		if (!tocando || (int64_t)v[N.fase] == 4) {
			Node *nd = Object::cast_to<Node>(po);
			if (nd) {
				nd->queue_free();
			}
			if (!mudou) {
				out = vozes.slice(0, i);
				mudou = true;
			}
			continue;
		}
		if (mudou) {
			out.push_back(v);
		}
		// _aplicar
		bool solta = (int64_t)v[N.fase] >= 3;
		double vol = solta ? (double)v[N.vol] : volume * ganho * (double)v[N.amp];
		double db = UtilityFunctions::linear_to_db(maxd(vol * (double)v[N.nivel] / 32767.0, 1e-5));
		if (db != (double)v.get(N.db_ult, INFINITY)) {
			if (p2) {
				p2->set_volume_db(db);
			} else if (p3) {
				p3->set_volume_db(db);
			}
			v[N.db_ult] = db;
		}
		double pt = clampd(solta ? (double)v[N.tom] : tom * dobra(v), 0.05, 8.0);
		if (pt != (double)v.get(N.pt_ult, INFINITY)) {
			if (p2) {
				p2->set_pitch_scale(pt);
			} else if (p3) {
				p3->set_pitch_scale(pt);
			}
			v[N.pt_ult] = pt;
		}
	}
	return mudou ? out : vozes;
}
