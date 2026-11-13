// Pose do piloto em C++ (porta do carro/piloto.gd: pose, _anima, _quadro,
// giro_volante, _segura_volante pelo caminho da tabela e _cotovelo_ang).
// Só o desenho: a montagem (carregar, prender_no_volante, _montar_tabela)
// continua no GDScript, que é de onde esta classe copia tudo no configurar.
#include "piloto.h"

#include <godot_cpp/classes/skeleton3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cmath>

#include "mat.h"

using namespace godot;
using namespace atv4;

namespace {
const double TORCAO_ANTEBRACO = 0.5;   // piloto.gd
const double COTOVELO_FORA = 55.0;
const double COTOVELO_DENTRO = 30.0;
inline double deg_to_rad(double d) { return d * (PI_ / 180.0); }
} // namespace

void PilotoCpp::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configurar", "piloto"), &PilotoCpp::configurar);
	ClassDB::bind_method(D_METHOD("pose", "s", "extra"), &PilotoCpp::pose);
	ClassDB::bind_method(D_METHOD("giro_volante", "s"), &PilotoCpp::giro_volante);
}

bool PilotoCpp::configurar(Object *pil) {
	ok = false;
	if (pil == nullptr) {
		return false;
	}
	pil_id = pil->get_instance_id();
	Object *sk = pil->get("skel");
	if (sk == nullptr) {
		return false;
	}
	skel_id = sk->get_instance_id();
	PackedInt32Array pais_ = pil->get("_pais");
	PackedInt32Array esp_ = pil->get("_esp");
	n = (int)pais_.size();
	pais.assign(pais_.ptr(), pais_.ptr() + pais_.size());
	esp.assign(esp_.ptr(), esp_.ptr() + esp_.size());
	PackedFloat32Array t = pil->get("_tempos");
	tempos.assign(t.ptr(), t.ptr() + t.size());
	PackedFloat32Array gr = pil->get("_giro");
	giro.assign(gr.ptr(), gr.ptr() + gr.size());
	dur = pil->get("_dur");
	Array ps = pil->get("_pos");
	Array rs = pil->get("_rot");
	pos.clear();
	rot.clear();
	for (int64_t k = 0; k < ps.size(); k++) {
		Array pk = ps[k];
		Array rk = rs[k];
		std::vector<Vector3> vp(n);
		std::vector<Quaternion> vr(n);
		for (int b = 0; b < n; b++) {
			vp[b] = pk[b];
			vr[b] = rk[b];
		}
		pos.push_back(vp);
		rot.push_back(vr);
	}
	if (pos.size() < 2 || (int)esp.size() != n || tempos.size() < 2) {
		return false;
	}
	vol = pil->get("_vol");
	vc = pil->get("_vc");
	ve = pil->get("_ve");
	cabeca = (int)(int64_t)pil->get("_cabeca");
	maos.clear();
	Array ms = pil->get("_maos");
	for (int64_t i = 0; i < ms.size(); i++) {
		Dictionary m = ms[i];
		if (!m.has("tab")) {
			return false;    // sem tabela o GDScript faz (caminho das paredes)
		}
		Mao h;
		h.sup = (int)(int64_t)m["sup"];
		h.inf = (int)(int64_t)m["inf"];
		h.mao = (int)(int64_t)m["mao"];
		h.cent = m["cent"];
		h.pega = m["pega"];
		h.rel0 = m["rel0"];
		PackedVector3Array tb = m["tab"];
		h.tab.assign(tb.ptr(), tb.ptr() + tb.size());
		if (h.tab.size() < 2) {
			return false;
		}
		maos.push_back(h);
	}
	if (vol && giro.size() < tempos.size()) {
		return false;
	}
	lp.assign(n, Vector3());
	lr.assign(n, Quaternion());
	g.assign(n, Transform3D());
	ok = true;
	return true;
}

// _quadro: quadro e fração (a fração passa por Vector2, float, como no GDScript)
void PilotoCpp::quadro(double tm, int &k, double &f) const {
	k = 0;
	while (k < (int)tempos.size() - 2 && tm > (double)tempos[k + 1]) {
		k += 1;
	}
	double fr = clampd((tm - (double)tempos[k]) / maxd((double)tempos[k + 1] - (double)tempos[k], 1e-6), 0.0, 1.0);
	f = (double)(real_t)fr;
}

double PilotoCpp::giro_volante(double s) const {
	if (!ok || tempos.size() < 2 || giro.size() < tempos.size()) {
		return 0.0;   // sem o volante (o GDScript não chama assim: _cpp_vol)
	}
	int k;
	double f;
	quadro(absd(s) * dur, k, f);
	double gv = lerpd(giro[k], giro[k + 1], f);
	return -s > 0.0 ? -gv : gv;
}

void PilotoCpp::anima(double s) {
	double s_jogo = -s;
	bool e = s_jogo > 0.0;
	int k;
	double f;
	quadro(absd(s_jogo) * dur, k, f);
	for (int b = 0; b < n; b++) {
		int src = e ? esp[b] : b;
		Vector3 p = pos[k][src].lerp(pos[k + 1][src], (real_t)f);
		Quaternion r = rot[k][src].slerp(rot[k + 1][src], (real_t)f);
		if (e) {
			p.x = -p.x;
			r = Quaternion(r.x, -r.y, -r.z, r.w);
		}
		lp[b] = p;
		lr[b] = r;
	}
}

// _cotovelo_ang
Vector3 PilotoCpp::cotovelo_ang(const Vector3 &a, const Vector3 &w, double l1, double l2, double th,
		const Vector3 &fora, const Vector3 &ref) const {
	Vector3 para = w - a;
	double d = clampd(para.length(), absd(l1 - l2) + 1e-4, l1 + l2 - 1e-4);
	Vector3 dir = para.normalized();
	Vector3 baixo = Vector3(0, -1, 0) - dir * Vector3(0, -1, 0).dot(dir);
	Vector3 polo;
	if ((double)baixo.length_squared() > 1e-8) {
		baixo = baixo.normalized();
		Vector3 lado = dir.cross(baixo);
		if ((double)lado.dot(fora) < 0.0) {
			lado = -lado;
		}
		double t = clampd(th, -deg_to_rad(COTOVELO_DENTRO), deg_to_rad(COTOVELO_FORA));
		polo = baixo * (real_t)std::cos(t) + lado * (real_t)std::sin(t);
	} else {
		polo = ref - dir * ref.dot(dir);
		if ((double)polo.length_squared() < 1e-10) {
			polo = dir.cross(ve);
		}
		polo = polo.normalized();
	}
	double x = (l1 * l1 - l2 * l2 + d * d) / (2.0 * d);
	return a + dir * (real_t)x + polo * (real_t)std::sqrt(maxd(l1 * l1 - x * x, 0.0));
}

// _segura_volante (caminho da tabela)
void PilotoCpp::segura_volante(double giro_, double s, double &alcance) {
	for (int b = 0; b < n; b++) {
		Transform3D t(Basis(lr[b]), lp[b]);
		g[b] = pais[b] < 0 ? t : g[pais[b]] * t;
	}
	Basis rotb(ve, (real_t)giro_);
	Transform3D gira(rotb, vc - rotb.xform(vc));
	for (const Mao &m : maos) {
		Transform3D alvo = gira * m.pega;
		int sup = m.sup, inf = m.inf, mao = m.mao;
		Vector3 a = g[sup].origin;
		Vector3 b0 = g[inf].origin;
		Vector3 w0 = g[mao].origin;
		double l1 = a.distance_to(b0);
		double l2 = b0.distance_to(w0);
		int omb = pais[sup];
		Vector3 s0 = g[omb].origin;
		double alc = (l1 + l2) * 0.98;
		alcance = maxd(alcance, (double)(alvo.origin - a).length() / (l1 + l2));
		Vector3 eixo = (a - s0).cross(alvo.origin - s0);
		if ((double)(alvo.origin - a).length() > alc && (double)eixo.length_squared() > 1e-10) {
			eixo = eixo.normalized();
			double lo = 0.0;
			double hi_ = deg_to_rad(35.0);
			for (int it = 0; it < 12; it++) {
				double meio = (lo + hi_) * 0.5;
				if ((double)(alvo.origin - (s0 + Basis(eixo, (real_t)meio).xform(a - s0))).length() > alc) {
					lo = meio;
				} else {
					hi_ = meio;
				}
			}
			Basis q(eixo, (real_t)hi_);
			lr[omb] = (g[pais[omb]].basis.inverse() * (q * g[omb].basis)).get_rotation_quaternion();
			int os_[4] = { omb, sup, inf, mao };
			for (int o : os_) {
				g[o] = Transform3D(q * g[o].basis, s0 + q.xform(g[o].origin - s0));
			}
			a = g[sup].origin;
			b0 = g[inf].origin;
			w0 = g[mao].origin;
		}
		Vector3 fora((real_t)signd((double)a.x - (double)g[pais[omb]].origin.x), 0, 0);
		Vector3 punho = alvo.xform(m.cent);
		Vector3 raio_p = punho - vc;
		raio_p = (raio_p - ve * raio_p.dot(ve)).normalized();
		Vector3 tg = ve.cross(raio_p).normalized();
		int ts = (int)m.tab.size();
		double x = clampd((s + 1.0) * 0.5, 0.0, 1.0) * (ts - 1);
		int k0 = (int)x < ts - 2 ? (int)x : ts - 2;
		Vector3 sol = m.tab[k0].lerp(m.tab[k0 + 1], (real_t)(x - k0));
		Basis rr = Basis(raio_p, sol.y) * Basis(tg, sol.x);
		alvo = Transform3D(rr * alvo.basis, punho + rr.xform(alvo.origin - punho));
		Vector3 para = alvo.origin - a;
		double d = clampd(para.length(), absd(l1 - l2) + 1e-4, l1 + l2 - 1e-4);
		Vector3 dir = para.normalized();
		Vector3 cot = cotovelo_ang(a, alvo.origin, l1, l2, sol.z, fora, b0 - a);
		Quaternion r1((b0 - a).normalized(), (cot - a).normalized());
		Vector3 w1 = cot + r1.xform(w0 - b0);
		Vector3 ponta = a + dir * (real_t)d;
		Quaternion r2((w1 - cot).normalized(), (ponta - cot).normalized());
		Basis b_sup = Basis(r1) * g[sup].basis;
		Basis b_inf = Basis(r2 * r1) * g[inf].basis;
		Vector3 f = (ponta - cot).normalized();
		Quaternion qq = (alvo.basis * (b_inf * m.rel0).inverse()).get_rotation_quaternion();
		double tor = UtilityFunctions::wrapf(2.0 * std::atan2((double)Vector3(qq.x, qq.y, qq.z).dot(f), (double)qq.w), -PI_, PI_);
		b_inf = Basis(f, (real_t)(tor * TORCAO_ANTEBRACO)) * b_inf;
		lr[sup] = (g[pais[sup]].basis.inverse() * b_sup).get_rotation_quaternion();
		lr[inf] = (b_sup.inverse() * b_inf).get_rotation_quaternion();
		lr[mao] = (b_inf.inverse() * alvo.basis).get_rotation_quaternion();
	}
}

// pose: false = não configurado (o GDScript faz)
bool PilotoCpp::pose(double s, double extra) {
	if (!ok) {
		return false;
	}
	Skeleton3D *sk = Object::cast_to<Skeleton3D>(ObjectDB::get_instance(skel_id));
	Object *pil = ObjectDB::get_instance(pil_id);
	if (sk == nullptr || pil == nullptr) {
		return false;
	}
	anima(s);
	if (vol) {
		double alcance = pil->get("alcance");
		segura_volante(giro_volante(s) + extra, s, alcance);
		pil->set("alcance", alcance);
	}
	for (int b = 0; b < n; b++) {
		sk->set_bone_pose_position(b, lp[b]);
		sk->set_bone_pose_rotation(b, lr[b]);
	}
	if (cabeca >= 0) {
		bool sem = pil->get("sem_cabeca");
		sk->set_bone_pose_scale(cabeca, Vector3(1, 1, 1) * (real_t)(sem ? 0.001 : 1.0));
	}
	return true;
}
