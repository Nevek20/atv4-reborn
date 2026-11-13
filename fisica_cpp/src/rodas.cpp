// Rodas e molas em C++ (porta linha a linha do carro/car.gd: _integra_rodas,
// _spring, _damper, _add_corr e o laço de contato do _physics_process: raio
// de cada roda, curso, batente, mola + amortecedor). O terreno e as cercas
// continuam no GDScript (chamados daqui). Mesma ordem das contas e das
// forças do GDScript.
#include "fisica_carro.h"

#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <godot_cpp/classes/physics_ray_query_parameters3d.hpp>
#include <godot_cpp/classes/physics_shape_query_parameters3d.hpp>
#include <godot_cpp/classes/collision_shape3d.hpp>
#include <godot_cpp/classes/shape3d.hpp>
#include <godot_cpp/classes/rigid_body3d.hpp>
#include <godot_cpp/variant/typed_array.hpp>

#include "mat.h"

using namespace godot;
using namespace atv4;

// _spring
double FisicaCarro::mola(const RodaFixa &w, double x) const {
	double u = 0.0;
	if (x >= 0.0 && w.max > 0.0) {
		u = x / w.max;
	} else if (x < 0.0 && w.min < 0.0) {
		u = x / w.min;
	}
	return w.k * w.kc.sample(u) * x * 1000.0;
}

// _damper
double FisicaCarro::amortecedor(const RodaFixa &w, double v) const {
	return w.c * w.dc.sample(absd(v)) * v * 1000.0;
}

// _add_corr
static Vector3 add_corr(Vector3 c, const Vector3 &d) {
	for (int i = 0; i < 3; i++) {
		if (signd(c[i]) == signd(d[i]) || c[i] == 0.0f) {
			if (absd(d[i]) > absd(c[i])) {
				c[i] = d[i];
			}
		} else {
			c[i] = (real_t)((double)c[i] + (double)d[i]);   // como o GDScript (soma em double)
		}
	}
	return c;
}

// _integra_rodas + contato. Devolve [com_w, n_sum, rear_g, h_sum, corr] e
// grava grounded no carro.
Array FisicaCarro::rodas(double dt, PhysicsDirectSpaceState3D *space, Vector3 up) {
	Array res;
	Object *c = carro();
	RigidBody3D *b = Object::cast_to<RigidBody3D>(c);
	if (b == nullptr || space == nullptr) {
		return res;
	}
	const Nomes &N = nomes();
	Array wd = c->get(N.wheels);
	int64_t nw = wd.size() < (int64_t)rf.size() ? wd.size() : (int64_t)rf.size();

	// ---- _integra_rodas
	for (int64_t i = 0; i < nw; i++) {
		Dictionary d = wd[i];
		const RodaFixa &w = rf[i];
		double x = d[N.x];
		double v = d[N.v];
		double fw;
		if ((bool)d[N.hit]) {
			fw = -(double)d[N.f];
		} else {
			double damp = -amortecedor(w, v);
			double dv = damp / w.mw * dt;
			if (absd(dv) > absd(v) && absd(dv) > 1e-6) {
				damp *= absd(v / dv);
			}
			fw = -mola(w, x) + damp;
		}
		v = clampd(v + fw / w.mw * dt, -w.vmax, w.vmax);
		x = clampd(x + v * dt, w.min, w.max);
		d[N.v] = v;
		d[N.x] = x;
	}

	// ---- contato
	Transform3D xf = b->get_global_transform();
	Vector3 com_w = xf.xform(b->get_center_of_mass());
	int64_t grounded = 0;
	Vector3 n_sum;
	int64_t rear_g = 0;
	double h_sum = 0.0;
	Vector3 corr;
	Object *objetos = c->get(N.objetos);
	Object *terrain = c->get(N.terrain);
	Variant pneu = c->get(N.pneu);
	TypedArray<RID> excluir;
	excluir.push_back(b->get_rid());
	if (objetos != nullptr) {
		excluir.append_array(objetos->call(N.ignorar_roda));
	}
	excluir.append_array(c->get(N.outros_carros));
	if (query.is_null()) {
		query.instantiate();
	}
	Ref<PhysicsRayQueryParameters3D> q = query;
	Vector3 pos = b->get_global_position();
	Vector3 lin = b->get_linear_velocity();
	Vector3 ang = b->get_angular_velocity();
	for (int64_t i = 0; i < nw; i++) {
		Dictionary d = wd[i];
		const RodaFixa &w = rf[i];
		double x = d[N.x];
		Vector3 attach = xf.xform(Vector3((real_t)w.px, (real_t)w.y0, (real_t)w.pz));
		Vector3 top = xf.xform(Vector3((real_t)w.px, (real_t)(w.y0 + w.max), (real_t)w.pz));
		double reach = (w.max - w.min) + w.r + 0.05;
		q->set_from(top);
		q->set_to(top - up * (real_t)reach);
		q->set_exclude(excluir);
		Dictionary hit = space->intersect_ray(q);
		if (objetos != nullptr && !hit.is_empty() &&
				(bool)objetos->call(N.roda_na_cerca, hit[N.collider], hit[N.position], hit[N.normal])) {
			TypedArray<RID> mais = excluir.duplicate();
			mais.push_back(hit[N.rid]);
			q->set_exclude(mais);
			hit = space->intersect_ray(q);
		}
		bool w_hit = false;
		double pen = 0.0;
		if (!hit.is_empty()) {
			Vector3 hn0 = hit[N.normal];
			Vector3 hpos = hit[N.position];
			double d0 = (double)top.distance_to(hpos) - w.max;
			pen = (w.r - x) - d0;
			w_hit = pen > 0.0 && (double)hn0.dot(up) >= w.cos_max;
		}
		d[N.hit] = w_hit;
		if (!w_hit) {
			d[N.f] = 0.0;
			continue;
		}
		Vector3 hp = hit[N.position];
		Vector3 hn = hit[N.normal];
		d[N.point] = hp;
		d[N.normal] = hn;
		if (terrain != nullptr) {
			Variant mat = terrain->call(N.material_at, hp.x, hp.z);
			d[N.mat] = mat;
			d[N.mu] = terrain->call(N.atrito, mat, pneu);
			d[N.amort] = terrain->call(N.amortecimento, mat);
		}
		grounded += 1;
		n_sum += hn;
		if (!w.front) {
			rear_g += 1;
		}
		h_sum += (com_w - hp).dot(up);
		x += pen;
		if (x > w.max) {
			corr = add_corr(corr, hn * (real_t)(x - w.max));
			x = w.max;
		}
		Vector3 vp = lin + ang.cross(attach - com_w);
		double v = clampd(-(double)hn.dot(vp) * (double)hn.dot(up), -w.vmax, w.vmax);
		double f_s = mola(w, x) + amortecedor(w, v);
		d[N.x] = x;
		d[N.v] = v;
		d[N.f] = f_s;
		b->apply_force(hn * (real_t)f_s, attach - pos);
		RigidBody3D *outro = Object::cast_to<RigidBody3D>((Object *)hit[N.collider]);
		if (outro != nullptr && f_s > 0.0) {
			outro->set_sleeping(false);
			outro->apply_force(-hn * (real_t)f_s, hp - outro->get_global_position());
		}
	}
	c->set(N.grounded, grounded);
	res.push_back(com_w);
	res.push_back(n_sum);
	res.push_back(rear_g);
	res.push_back(h_sum);
	res.push_back(corr);
	return res;
}

// _passo_esferas_rodas: liga a esfera de cada roda quando o chão perto dela
// está fora do cone da suspensão
void FisicaCarro::esferas(PhysicsDirectSpaceState3D *space, Vector3 up) {
	Object *c = carro();
	RigidBody3D *b = Object::cast_to<RigidBody3D>(c);
	if (b == nullptr || space == nullptr) {
		return;
	}
	const Nomes &N = nomes();
	Array wd = c->get(N.wheels);
	int64_t nw = wd.size() < (int64_t)rf.size() ? wd.size() : (int64_t)rf.size();
	Object *objetos = c->get(N.objetos);
	TypedArray<RID> excluir;
	excluir.push_back(b->get_rid());
	excluir.append_array(c->get(N.outros_carros));
	if (query_esfera.is_null()) {
		query_esfera.instantiate();
	}
	Transform3D xf = b->get_global_transform();
	for (int64_t i = 0; i < nw; i++) {
		Dictionary d = wd[i];
		const RodaFixa &w = rf[i];
		CollisionShape3D *cs = Object::cast_to<CollisionShape3D>((Object *)d.get(N.esfera, Variant()));
		if (cs == nullptr) {
			continue;
		}
		double x = d[N.x];
		Vector3 cc((real_t)w.px, (real_t)(w.y0 + clampd(x, w.min, w.max)), (real_t)w.pz);
		Ref<PhysicsShapeQueryParameters3D> q = query_esfera;
		q->set_shape(d[N.esfera_teste]);
		q->set_transform(Transform3D(Basis(), xf.xform(cc)));
		q->set_exclude(excluir);
		Dictionary info = space->get_rest_info(q);
		if (objetos != nullptr && !info.is_empty() && (double)((Vector3)info[N.normal]).dot(up) < w.cos_max) {
			Object *col = ObjectDB::get_instance(ObjectID((uint64_t)(int64_t)info[N.collider_id]));
			if ((bool)objetos->call(N.roda_na_cerca, col, info[N.point], info[N.normal])) {
				TypedArray<RID> mais = excluir.duplicate();
				mais.push_back(info[N.rid]);
				q->set_exclude(mais);
				info = space->get_rest_info(q);
			}
		}
		bool off = info.is_empty() || (double)((Vector3)info[N.normal]).dot(up) >= w.cos_max;
		if (!off) {
			cs->set_position(cc);
		}
		if (off != (bool)d.get(N.esfera_off, true) || off != cs->is_disabled()) {
			cs->set_deferred("disabled", off);
			d[N.esfera_off] = off;
		}
	}
}
