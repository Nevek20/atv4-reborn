#include "fisica_carro.h"

#include <godot_cpp/core/class_db.hpp>

#include "curvas.h"

using namespace godot;

void FisicaCarro::_bind_methods() {
	ClassDB::bind_static_method("FisicaCarro", D_METHOD("versao"), &FisicaCarro::versao);
	ClassDB::bind_static_method("FisicaCarro", D_METHOD("curva_sample", "c", "x"), &FisicaCarro::curva_sample);
	ClassDB::bind_static_method("FisicaCarro", D_METHOD("curva_integrate", "c", "x"), &FisicaCarro::curva_integrate);
	ClassDB::bind_static_method("FisicaCarro", D_METHOD("trio", "t", "mu"), &FisicaCarro::trio);
	ClassDB::bind_static_method("FisicaCarro", D_METHOD("fcurvas", "c", "mu", "x"), &FisicaCarro::fcurvas);
}

String FisicaCarro::versao() {
	return "atv4_fisica 0.2";
}

double FisicaCarro::curva_sample(const Dictionary &c, double x) {
	return atv4::Curva(c).sample(x);
}

double FisicaCarro::curva_integrate(const Dictionary &c, double x) {
	return atv4::Curva(c).integrate(x);
}

double FisicaCarro::trio(const Dictionary &t, double mu) {
	return atv4::Trio(t).eval(mu);
}

double FisicaCarro::fcurvas(const Dictionary &c, double mu, double x) {
	return atv4::FCurvas(c).eval(mu, x);
}
