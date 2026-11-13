// Nuvens da poeira em C++ (porta do efeitos/poeira.gd: _process e o guardar
// do _nuvem). Mesmas contas: escalar em double, os arrays em float de 32 bits
// como os Packed*32 do GDScript, mesma compactação e mesmos campos do buffer.
#include "nuvens.h"

#include <godot_cpp/variant/aabb.hpp>

#include <godot_cpp/classes/multi_mesh.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

#include "mat.h"

using namespace godot;
using namespace atv4;

void NuvensCpp::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configurar", "mm", "mm_agua", "cap", "max_nuvens"), &NuvensCpp::configurar);
	ClassDB::bind_method(D_METHOD("add", "p", "idade", "vida", "maxi", "ini", "alvo", "a0", "cor", "cel", "agua"), &NuvensCpp::add);
	ClassDB::bind_method(D_METHOD("vivas"), &NuvensCpp::vivas);
	ClassDB::bind_method(D_METHOD("agua_vivas"), &NuvensCpp::agua_vivas);
	ClassDB::bind_method(D_METHOD("exportar"), &NuvensCpp::exportar);
	ClassDB::bind_method(D_METHOD("quadro", "delta", "escala"), &NuvensCpp::quadro);
	ClassDB::bind_method(D_METHOD("buffers"), &NuvensCpp::buffers);
}

void NuvensCpp::configurar(Object *mm_, Object *mm_agua_, int64_t cap_, int64_t max_nuvens_) {
	mm = mm_ ? mm_->get_instance_id() : ObjectID();
	mm_agua = mm_agua_ ? mm_agua_->get_instance_id() : ObjectID();
	cap = cap_;
	max_nuvens = max_nuvens_;
}

void NuvensCpp::add(Vector3 p, double idade_, double vida_, double maxi_, double ini_, double alvo_, double a0_,
		Color cor_, double cel_, int64_t agua_) {
	pos.push_back(p);
	idade.push_back((float)idade_);
	vida.push_back((float)vida_);
	maxi.push_back((float)maxi_);
	ini.push_back((float)ini_);
	alvo.push_back((float)alvo_);
	a0.push_back((float)a0_);
	cor.push_back(cor_);
	cel.push_back((float)cel_);
	agua.push_back((uint8_t)agua_);
}

int64_t NuvensCpp::vivas() const {
	return (int64_t)pos.size();
}

PackedByteArray NuvensCpp::agua_vivas() const {
	PackedByteArray out;
	out.resize((int64_t)agua.size());
	for (size_t i = 0; i < agua.size(); i++) {
		out[(int64_t)i] = agua[i];
	}
	return out;
}

// [n_pos, n_idade, n_vida, n_max, n_ini, n_alvo, n_a0, n_cor, n_cel, n_agua] (F3: volta pro GDScript)
Array NuvensCpp::exportar() const {
	PackedVector3Array p;
	PackedFloat32Array f[7];
	PackedColorArray c;
	int64_t n = (int64_t)pos.size();
	p.resize(n);
	c.resize(n);
	for (int k = 0; k < 7; k++) {
		f[k].resize(n);
	}
	for (int64_t i = 0; i < n; i++) {
		p[i] = pos[i];
		f[0][i] = idade[i];
		f[1][i] = vida[i];
		f[2][i] = maxi[i];
		f[3][i] = ini[i];
		f[4][i] = alvo[i];
		f[5][i] = a0[i];
		f[6][i] = cel[i];
		c[i] = cor[i];
	}
	Array out;
	out.push_back(p);
	for (int k = 0; k < 6; k++) {
		out.push_back(f[k]);
	}
	out.push_back(c);
	out.push_back(f[6]);
	out.push_back(agua_vivas());
	return out;
}

Array NuvensCpp::buffers() const {
	Array out;
	out.push_back(buf);
	out.push_back(buf_agua);
	return out;
}

// _process: envelhece, tira as mortas, escreve o buffer. Devolve o cap
int64_t NuvensCpp::quadro(double delta, double escala) {
	MultiMesh *m = Object::cast_to<MultiMesh>(ObjectDB::get_instance(mm));
	if (m == nullptr) {
		return cap;
	}
	MultiMesh *ma = Object::cast_to<MultiMesh>(ObjectDB::get_instance(mm_agua));
	size_t w = 0;
	size_t total = pos.size();
	for (size_t i = 0; i < total; i++) {
		double id = (double)idade[i] + delta;
		if (id >= (double)vida[i]) {
			continue;
		}
		if (w != i) {
			pos[w] = pos[i];
			vida[w] = vida[i];
			maxi[w] = maxi[i];
			ini[w] = ini[i];
			alvo[w] = alvo[i];
			a0[w] = a0[i];
			cor[w] = cor[i];
			cel[w] = cel[i];
			agua[w] = agua[i];
		}
		idade[w] = (float)id;
		w += 1;
	}
	if (w != total) {
		pos.resize(w);
		idade.resize(w);
		vida.resize(w);
		maxi.resize(w);
		ini.resize(w);
		alvo.resize(w);
		a0.resize(w);
		cor.resize(w);
		cel.resize(w);
		agua.resize(w);
	}
	int64_t n = (int64_t)pos.size();
	if (n > cap) {
		while (cap < n) {
			cap *= 2;
		}
		cap = cap < max_nuvens ? cap : max_nuvens;
		m->set_instance_count(cap);
		if (ma) {
			ma->set_instance_count(cap);
		}
	}
	if (buf.size() != cap * 20) {
		buf.resize(cap * 20);
		buf_agua.resize(cap * 20);
	}
	float *b = buf.ptrw();
	float *ba = buf_agua.ptrw();
	int64_t np = 0;
	int64_t na = 0;
	// caixa das nuvens vivas (custom_aabb): sem ela o Forward+ mede a MultiMesh
	// com os espaços vazios (zerados na origem do mundo), o centro fica a
	// centenas de metros e a ordem das transparentes (e o LOD dos rivais) erra
	Vector3 lo_p, hi_p, lo_a, hi_a;
	float r_p = 0.0f;
	float r_a = 0.0f;
	for (int64_t k = 0; k < n; k++) {
		double tg = clampd((double)idade[k] / (double)maxi[k], 0.0, 1.0);
		double u = 1.0 - tg;
		double f = 1.0 - u * u * u * u;
		double tam = ((double)ini[k] * (1.0 - f) + (double)alvo[k] * f) * escala;
		double t = (double)idade[k] / (double)vida[k];
		double a = (double)a0[k] * (1.0 - t * t);
		const Vector3 &p = pos[k];
		const Color &c = cor[k];
		float *o;
		if (agua[k] == 1 && ma != nullptr) {
			o = ba + na * 20;
			lo_a = na == 0 ? p : lo_a.min(p);
			hi_a = na == 0 ? p : hi_a.max(p);
			r_a = r_a > (float)tam ? r_a : (float)tam;
			na += 1;
		} else {
			o = b + np * 20;
			lo_p = np == 0 ? p : lo_p.min(p);
			hi_p = np == 0 ? p : hi_p.max(p);
			r_p = r_p > (float)tam ? r_p : (float)tam;
			np += 1;
		}
		o[0] = (float)tam;
		o[5] = (float)tam;
		o[10] = (float)tam;
		o[3] = p.x;
		o[7] = p.y;
		o[11] = p.z;
		o[12] = c.r;
		o[13] = c.g;
		o[14] = c.b;
		o[15] = (float)a;
		o[16] = cel[k];
	}
	if (np > 0) {
		Vector3 e(r_p, r_p, r_p);
		m->set_custom_aabb(AABB(lo_p - e, hi_p - lo_p + e * 2.0f));
		m->set_buffer(buf);
	}
	m->set_visible_instance_count(np);
	if (ma) {
		if (na > 0) {
			Vector3 e(r_a, r_a, r_a);
			ma->set_custom_aabb(AABB(lo_a - e, hi_a - lo_a + e * 2.0f));
			ma->set_buffer(buf_agua);
		}
		ma->set_visible_instance_count(na);
	}
	return cap;
}
