// Suspensão visual em C++ (porta do carro/suspension_visual.gd: update, pose,
// pose_truck, _inclinacao, pose_telescopio, pose_barra, haste_estica, _about,
// _place). Só o desenho; as contas na mesma ordem do GDScript.
#include "suspensao.h"

#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/quaternion.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cmath>

#include "mat.h"

using namespace godot;
using namespace atv4;

namespace {

const Vector3 UP_(0, 1, 0);
const Vector3 RIGHT_(1, 0, 0);
const Vector3 BACK_(0, 0, 1);

Transform3D about(const Vector3 &p, const Basis &b) {
	return Transform3D(b, p - b.xform(p));
}

ObjectID id_de(const Variant &v) {
	Object *o = v;
	return o != nullptr ? ObjectID(o->get_instance_id()) : ObjectID();
}

// Basis(Vector3(w,0,0) + d*d.x*(k-w), ...) do GDScript (colunas)
Basis escala_eixo(const Vector3 &d, double k, double w) {
	real_t kw = (real_t)(k - w);
	real_t ww = (real_t)w;
	Basis b;
	b.set_columns(Vector3(ww, 0, 0) + d * d.x * kw, Vector3(0, ww, 0) + d * d.y * kw,
			Vector3(0, 0, ww) + d * d.z * kw);
	return b;
}

} // namespace

void SuspensaoCpp::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configurar", "susp"), &SuspensaoCpp::configurar);
	ClassDB::bind_method(D_METHOD("update", "steer"), &SuspensaoCpp::update);
}

void SuspensaoCpp::place(ObjectID id, const Transform3D &xf) const {
	Node3D *mi = Object::cast_to<Node3D>(ObjectDB::get_instance(id));
	if (mi != nullptr) {
		mi->set_transform(Transform3D(Basis(), off) * xf);
	}
}

double SuspensaoCpp::curso(const Dictionary &w) const {
	return clampd((double)w["x"], (double)w["min"], (double)w["max"]) + (double)w.get("jit", 0.0);
}

double SuspensaoCpp::inclinacao(const PecaTruck &t, double rl, double rr) const {
	Vector3 hl = t.wl + Vector3(0, (real_t)rl, 0);
	Vector3 hr = t.wr + Vector3(0, (real_t)rr, 0);
	if (absd((double)hl.x - (double)hr.x) < 0.01) {
		return 0.0;
	}
	return ((double)hl.y - (double)hr.y) / ((double)hl.x - (double)hr.x);
}

static void ler_tele(const Dictionary &t, SuspensaoCpp *, Vector3 &b0, Vector3 &t0, ObjectID &cima,
		ObjectID &baixo, ObjectID &mola, bool &tem) {
	tem = false;
	if (!t.has("tele")) {
		return;
	}
	Dictionary te = t["tele"];
	Dictionary pc = te["pecas"];
	b0 = te["b0"];
	t0 = te["t0"];
	cima = id_de(pc.get("cima", Variant()));
	baixo = id_de(pc.get("baixo", Variant()));
	mola = id_de(pc.get("mola", Variant()));
	tem = true;
}

bool SuspensaoCpp::configurar(Object *susp) {
	ok = false;
	if (susp == nullptr) {
		return false;
	}
	Object *car = susp->get("car");
	if (car == nullptr) {
		return false;
	}
	susp_id = susp->get_instance_id();
	car_id = car->get_instance_id();
	off = susp->get("off");
	rally = susp->get("rally");
	cantos.clear();
	Array cs = susp->get("corners");
	for (int64_t i = 0; i < cs.size(); i++) {
		Dictionary k = cs[i];
		Canto c;
		c.left = k["left"];
		c.front = k["front"];
		c.pivot = k["pivot"];
		c.w0 = k["w0"];
		c.u = k["u"];
		c.r = k["r"];
		c.frame = id_de(k.get("frame", Variant()));
		c.brake = id_de(k.get("brake", Variant()));
		c.shock = id_de(k.get("shock", Variant()));
		c.chamber = id_de(k.get("chamber", Variant()));
		c.piston = id_de(k.get("piston", Variant()));
		c.tem_top = k.has("top");
		if (c.tem_top) {
			c.top = k["top"];
			c.bottom = k["bottom"];
		}
		c.wheel = k["wheel"];
		cantos.push_back(c);
	}
	barras.clear();
	Array bs = susp->get("barras");
	for (int64_t i = 0; i < bs.size(); i++) {
		Dictionary b = bs[i];
		Barra br;
		br.mi = id_de(b["mi"]);
		br.dentro = b["dentro"];
		br.fora = b["fora"];
		String peca = b["peca"];
		if (peca != "frame" && peca != "brake") {
			return false;
		}
		br.freio = peca == "brake";
		br.canto = -1;
		for (int64_t j = 0; j < cs.size(); j++) {
			if (UtilityFunctions::is_same(cs[j], b["canto"])) {
				br.canto = (int)j;
			}
		}
		if (br.canto < 0) {
			return false;
		}
		barras.push_back(br);
	}
	// trucks
	Dictionary tr = susp->get("truck");
	truck = !tr.is_empty();
	frame_l = frame_r = brake_l = brake_r = axle = livre = PecaTruck();
	if (truck) {
		auto ler = [&](const char *nome, PecaTruck &p) {
			p.nome = nome;
			if (!tr.has(nome)) {
				return;
			}
			Dictionary t = tr[nome];
			p.tem = true;
			if (t.has("mis")) {
				Array ms = t["mis"];
				for (int64_t i = 0; i < ms.size(); i++) {
					p.mis.push_back(id_de(ms[i]));
				}
			} else {
				p.mis.push_back(id_de(t.get("mi", Variant())));
			}
			if (t.has("pivot")) {
				p.pivot = t["pivot"];
			}
			if (t.has("div")) {
				p.div = t["div"];
			}
			if (t.has("w")) {
				p.w = t["w"];
			}
			if (t.has("a0")) {
				p.a0 = t["a0"];
				p.ancora = t["ancora"];
			}
			if (t.has("wl")) {
				p.wl = t["wl"];
				p.wr = t["wr"];
			}
			if (t.has("rodas")) {
				Array rs = t["rodas"];
				for (int64_t i = 0; i < rs.size(); i++) {
					Dictionary w = rs[i];
					p.rodas.push_back(id_de(w["pivot"]));
				}
			}
			ler_tele(t, this, p.tele.b0, p.tele.t0, p.tele.cima, p.tele.baixo, p.tele.mola, p.tele.tem);
		};
		ler("LeftFrame", frame_l);
		ler("RightFrame", frame_r);
		ler("FrontLeftBrake", brake_l);
		ler("FrontRightBrake", brake_r);
		ler("RearAxle", axle);
		ler("RearFreeAxle", livre);
		rodas_truck.clear();
		Array ws = car->get("wheels");
		for (int64_t i = 0; i < ws.size(); i++) {
			Dictionary w = ws[i];
			String k = String((bool)w["front"] ? "F" : "R") + String((bool)w["left"] ? "L" : "R");
			rodas_truck[k] = w;
		}
		Dictionary tab = car->get("BALANCA_DESLOCA");
		desloca = tab.get(car->call("chave"), Dictionary());
	}
	ok = true;
	return true;
}

bool SuspensaoCpp::update(double steer) {
	if (!ok) {
		return false;
	}
	Object *car = ObjectDB::get_instance(car_id);
	if (car == nullptr) {
		return false;
	}
	int haste = -1;   // car._tem("haste_estica"), lido só se precisar
	for (Canto &k : cantos) {
		double x = curso(k.wheel);
		// pose(k, x, steer)
		Basis b = k.r > 1e-6 ? Basis(k.u, (real_t)std::atan(x / k.r)) : Basis();
		Transform3D arm = about(k.pivot, b);
		Vector3 h = arm.xform(k.w0);
		if (k.front) {
			h.y = (real_t)((double)k.w0.y + x);
		}
		if (rally) {
			h = k.w0 + Vector3(0, (real_t)x, 0);
		}
		Basis bb = k.front ? Basis(UP_, (real_t)steer) : Basis();
		Transform3D brake(bb, h - bb.xform(k.w0));
		k.u_frame = arm;
		k.u_brake = brake;
		place(k.frame, arm);
		Node3D *piv = Object::cast_to<Node3D>((Object *)k.wheel["pivot"]);
		if (piv != nullptr) {
			piv->set_position(off + h);
		}
		place(k.brake, brake);
		if (!k.tem_top) {
			continue;
		}
		const Vector3 &top = k.top;
		const Vector3 &bot = k.bottom;
		if (k.front) {
			Vector3 b2 = arm.xform(bot);
			double a = std::acos(clampd((bot - top).normalized().dot((b2 - top).normalized()), -1.0, 1.0));
			if (k.left) {
				a = -a;
			}
			place(k.shock, about(top, Basis(BACK_, (real_t)a)));
		} else {
			Vector3 q = arm.xform(bot);
			Vector3 p2(bot.x, q.y, q.z);
			double a = std::atan(((double)top.y - (double)bot.y) / ((double)top.z - (double)bot.z)) -
					std::atan(((double)top.y - (double)p2.y) / ((double)top.z - (double)p2.z));
			Basis r(RIGHT_, (real_t)a);
			place(k.chamber, about(top, r));
			Transform3D hs(r, p2 - r.xform(bot));
			if (haste < 0) {
				haste = (bool)car->call("_tem", "haste_estica") ? 1 : 0;
			}
			if (haste == 1) {
				// haste_estica
				double l0 = top.distance_to(bot);
				if (l0 >= 1e-4) {
					double s = top.distance_to(hs.xform(bot)) / l0;
					Vector3 d = (top - bot) / (real_t)l0;
					Basis e = escala_eixo(d, s, 1.0);
					hs = hs * Transform3D(e, bot - e.xform(bot));
				}
			}
			place(k.piston, hs);
		}
	}
	for (const Barra &br : barras) {
		const Canto &k = cantos[br.canto];
		const Transform3D &t = br.freio ? k.u_brake : k.u_frame;
		// pose_barra
		const Vector3 &i = br.dentro;
		const Vector3 &o0 = br.fora;
		Vector3 o = t.xform(o0);
		double l0 = i.distance_to(o0);
		Vector3 d0 = (o0 - i) / (real_t)l0;
		Basis giro(Quaternion(d0, (o - i).normalized()));
		double s = i.distance_to(o) / l0;
		Basis m = giro * escala_eixo(d0, s, 1.0);
		place(br.mi, Transform3D(m, i - m.xform(i)));
	}
	if (!truck) {
		return true;
	}
	// pose_truck
	double xs[4];
	const char *nomes[4] = { "FL", "FR", "RL", "RR" };
	for (int i = 0; i < 4; i++) {
		xs[i] = rodas_truck.has(nomes[i]) ? curso(rodas_truck[nomes[i]]) : 0.0;
	}
	double fl = xs[0], fr = xs[1], rl = xs[2], rr = xs[3];
	bool inclina = car->call("_tem", "eixo_rigido");
	bool usa_desloca = !desloca.is_empty() && (bool)car->call("_tem", "balanca_desloca");
	auto coloca = [&](const PecaTruck &t, Transform3D xf) {
		if (usa_desloca && desloca.has(t.nome)) {
			xf = Transform3D(Basis(), (Vector3)desloca[t.nome]) * xf;
		}
		for (ObjectID id : t.mis) {
			place(id, xf);
		}
		if (t.tele.tem) {
			// pose_telescopio
			const double METADE = 0.6;
			const double HASTE = 0.75;
			Vector3 b0 = t.tele.b0;
			Vector3 t0 = t.tele.t0;
			Vector3 b = xf.xform(b0);
			Vector3 tt = t0;
			Vector3 d0 = (t0 - b0).normalized();
			double l0 = t0.distance_to(b0);
			Basis giro(Quaternion(d0, (tt - b).normalized()));
			Basis cima = giro * escala_eixo(d0, METADE, 1.0);
			Basis baixo = giro * escala_eixo(d0, METADE, HASTE);
			Basis mola = giro * escala_eixo(d0, tt.distance_to(b) / l0, 1.0);
			place(t.tele.cima, Transform3D(cima, tt - cima.xform(t0)));
			place(t.tele.baixo, Transform3D(baixo, b - baixo.xform(b0)));
			place(t.tele.mola, Transform3D(mola, b - mola.xform(b0)));
		}
	};
	const PecaTruck *frames[2] = { &frame_l, &frame_r };
	for (int i = 0; i < 2; i++) {
		const PecaTruck &t = *frames[i];
		if (t.tem) {
			double xi = i == 0 ? fl : fr;
			coloca(t, about(t.pivot, Basis(BACK_, (real_t)std::tan(xi / t.div))));
		}
	}
	const PecaTruck *freios[2] = { &brake_l, &brake_r };
	for (int i = 0; i < 2; i++) {
		const PecaTruck &t = *freios[i];
		if (t.tem) {
			double xi = i == 0 ? fl : fr;
			Basis b(UP_, (real_t)steer);
			coloca(t, Transform3D(b, t.w - b.xform(t.w) + Vector3(0, (real_t)xi, 0)));
		}
	}
	if (axle.tem) {
		const PecaTruck &t = axle;
		Vector3 m = (t.wl + t.wr) * (real_t)0.5 + Vector3(0, (real_t)((rl + rr) * 0.5), 0);
		m.x = 0;
		Vector3 a0 = t.a0;
		double a = std::acos(clampd((t.ancora - a0).normalized().dot((m - a0).normalized()), -1.0, 1.0));
		if (t.ancora.y < m.y) {
			a = -a;
		}
		Transform3D out = about(a0, Basis(RIGHT_, (real_t)-a));
		if (inclina) {
			Vector3 u = (m - a0).normalized();
			if (absd(u.z) > 0.1) {
				double phi = std::atan(inclinacao(t, rl, rr) / (double)u.z);
				out = about(a0, Basis(u, (real_t)phi)) * out;
			}
		}
		coloca(t, out);
	}
	if (livre.tem) {
		const PecaTruck &t = livre;
		Transform3D out(Basis(), Vector3(0, (real_t)((rl + rr) * 0.5), 0));
		if (inclina) {
			Vector3 c = (t.wl + t.wr) * (real_t)0.5 + Vector3(0, (real_t)((rl + rr) * 0.5), 0);
			c.x = 0;
			out = about(c, Basis(BACK_, (real_t)std::atan(inclinacao(t, rl, rr)))) * out;
		}
		coloca(t, out);
	}
	// rodas de trás inclinam junto com o eixo
	const PecaTruck *eixos[2] = { &axle, &livre };
	for (const PecaTruck *t : eixos) {
		if (!t->tem) {
			continue;
		}
		double cam = inclina ? std::atan(inclinacao(*t, rl, rr)) : 0.0;
		for (ObjectID id : t->rodas) {
			Node3D *pv = Object::cast_to<Node3D>(ObjectDB::get_instance(id));
			if (pv != nullptr) {
				Vector3 rot = pv->get_rotation();
				rot.z = (real_t)cam;
				pv->set_rotation(rot);
			}
		}
	}
	return true;
}
