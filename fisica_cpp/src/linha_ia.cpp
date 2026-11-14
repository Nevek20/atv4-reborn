// Contas da linha da IA em C++ (porta do pista/ia.gd: _seg, ponto, _v_curva,
// _lateral, _direcao e rastrear). Mesmos números do GDScript: escalar em
// double, vetor em Vector3 (float), mesma ordem das contas.
#include "linha_ia.h"

#include <godot_cpp/core/class_db.hpp>

#include <cmath>

#include "mat.h"

using namespace godot;
using namespace atv4;

namespace {
const double RASTREIO = 60.0;   // ia.gd
const double A_LAT = 14.0;
const double A_FRENA = 8.0;

inline Vector3 plano(const Vector3 &v) {
	return Vector3(v.x, 0.0f, v.z);
}
} // namespace

void LinhaIA::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configurar", "linha", "acc", "comp"), &LinhaIA::configurar);
	ClassDB::bind_method(D_METHOD("seg", "s"), &LinhaIA::seg);
	ClassDB::bind_method(D_METHOD("ponto", "s"), &LinhaIA::ponto);
	ClassDB::bind_method(D_METHOD("v_curva", "s"), &LinhaIA::v_curva);
	ClassDB::bind_method(D_METHOD("lateral", "p", "s"), &LinhaIA::lateral);
	ClassDB::bind_method(D_METHOD("direcao_ang", "s", "lat", "xf"), &LinhaIA::direcao_ang);
	ClassDB::bind_method(D_METHOD("rastrear", "prog", "s_linha", "p"), &LinhaIA::rastrear);
	ClassDB::bind_method(D_METHOD("bordas", "esq", "dir"), &LinhaIA::bordas);
	ClassDB::bind_method(D_METHOD("fora", "prog", "s_linha", "p"), &LinhaIA::fora);
}

bool LinhaIA::configurar(const Array &linha_, const Array &acc_, double comp_) {
	linha.clear();
	acc.clear();
	for (int64_t i = 0; i < linha_.size(); i++) {
		linha.push_back(linha_[i]);
	}
	for (int64_t i = 0; i < acc_.size(); i++) {
		acc.push_back(acc_[i]);
	}
	comp = comp_;
	return !linha.empty() && linha.size() == acc.size() && comp > 0.0;
}

// _seg: último trecho com acc[i] <= s
int64_t LinhaIA::seg(double s) const {
	int64_t lo = 0;
	int64_t hi = (int64_t)acc.size() - 1;
	while (lo < hi) {
		int64_t m = (lo + hi + 1) / 2;
		if (acc[m] <= s) {
			lo = m;
		} else {
			hi = m - 1;
		}
	}
	return lo;
}

// ponto da linha a s metros (s em qualquer volta)
Vector3 LinhaIA::ponto(double s) const {
	s = fposmod(s, comp);
	int64_t i = seg(s);
	const Vector3 &a = linha[i];
	const Vector3 &b = linha[(i + 1) % linha.size()];
	double l = plano(b - a).length();
	return a.lerp(b, (real_t)((s - acc[i]) / maxd(l, 1e-6)));
}

// _v_curva: velocidade máxima pelas curvas à frente
double LinhaIA::v_curva(double s) const {
	double v_max = INFINITY;
	double d = 5.0;
	const Vector3 up(0, 1, 0);
	while (d <= 65.0) {
		Vector3 a = plano(ponto(s + d + 3.0) - ponto(s + d)).normalized();
		Vector3 b = plano(ponto(s + d + 33.0) - ponto(s + d + 30.0)).normalized();
		double vira = absd(a.signed_angle_to(b, up));
		if (vira > 0.05) {
			double vc = std::sqrt(A_LAT * 30.0 / vira);
			v_max = mind(v_max, std::sqrt(vc * vc + 2.0 * A_FRENA * d));
		}
		d += 10.0;
	}
	return v_max;
}

// _lateral: distância com sinal da linha
double LinhaIA::lateral(Vector3 p, double s) const {
	Vector3 q = ponto(s);
	Vector3 adiante = plano(ponto(s + 2.0) - q).normalized();
	return plano(p - q).dot(Vector3(adiante.z, 0.0f, -adiante.x));
}

// _direcao (sem o arredondamento): ângulo até o alvo no frame do carro
double LinhaIA::direcao_ang(double s, double lat, Transform3D xf) const {
	Vector3 alvo = ponto(s);
	Vector3 adiante = plano(ponto(s + 2.0) - alvo).normalized();
	alvo += Vector3(adiante.z, 0.0f, -adiante.x) * (real_t)lat;
	Vector3 loc = xf.affine_inverse().xform(alvo);
	return std::atan2((double)loc.x, (double)loc.z);
}

// rastrear: [prog novo, distância da linha]
PackedFloat64Array LinhaIA::rastrear(double prog, double s_linha, Vector3 p) const {
	double s0 = prog + s_linha;
	double lo = s0 - RASTREIO;
	double hi = s0 + RASTREIO;
	int64_t n = (int64_t)linha.size();
	double lo_m = fposmod(lo, comp);
	double volta = lo - lo_m;
	int64_t i = seg(lo_m);
	double best = INFINITY;
	double best_s = s0;
	double s_ini = volta + acc[i];
	while (s_ini <= hi) {
		const Vector3 &a = linha[i];
		Vector3 ab = plano(linha[(i + 1) % n] - a);
		double l = ab.length();
		double s = s_ini;
		if (l > 1e-6) {
			s = clampd(s_ini + (double)plano(p - a).dot(ab) / l, maxd(s_ini, lo), mind(s_ini + l, hi));
		}
		double e = plano(p - (a + ab * (real_t)((s - s_ini) / maxd(l, 1e-6)))).length();
		if (e < best) {
			best = e;
			best_s = s;
		}
		i += 1;
		if (i >= n) {
			i = 0;
			volta += comp;
		}
		s_ini = volta + acc[i];
	}
	PackedFloat64Array out;
	out.push_back(prog + (best_s - s0));
	out.push_back(best);
	return out;
}

void LinhaIA::bordas(const Array &esq_, const Array &dir_) {
	esq.clear();
	dir.clear();
	for (int64_t i = 0; i < esq_.size(); i++) {
		esq.push_back(esq_[i]);
	}
	for (int64_t i = 0; i < dir_.size(); i++) {
		dir.push_back(dir_[i]);
	}
}

// pista/reposicao.gd passo (a parte da geometria): [fora, d.x, d.z], d = a
// direção do trecho (plano, normalizada). Mesmas contas, mesmos tipos
PackedFloat64Array LinhaIA::fora(double prog, double s_linha, Vector3 p) const {
	PackedFloat64Array out;
	int64_t n = (int64_t)linha.size();
	if (n == 0 || (int64_t)esq.size() < n || (int64_t)dir.size() < n) {
		return out;
	}
	double s = fposmod(prog + s_linha, comp);
	int64_t i = seg(s);
	const Vector3 &pa = linha[i];
	const Vector3 &pb = linha[(i + 1) % n];
	// Vector3(pb.x - pa.x, ...) do GDScript: diferença em double, depois float
	Vector3 d((real_t)((double)pb.x - (double)pa.x), 0.0f, (real_t)((double)pb.z - (double)pa.z));
	double l = d.length();
	d = d / (real_t)maxd(l, 1e-6);
	Vector3 pp((real_t)((double)p.x - (double)pa.x), 0.0f, (real_t)((double)p.z - (double)pa.z));
	double t = clampd((double)pp.dot(d) / maxd(l, 1e-6), 0.0, 1.0);
	double lat = ((double)p.z - (double)pa.z) * (double)d.x - ((double)p.x - (double)pa.x) * (double)d.z;
	double e = lerpd(esq[i], esq[(i + 1) % n], t);
	double r = lerpd(dir[i], dir[(i + 1) % n], t);
	double f = lat < e ? e - lat : (lat > r ? lat - r : 0.0);
	out.push_back(f);
	out.push_back(d.x);
	out.push_back(d.z);
	return out;
}
