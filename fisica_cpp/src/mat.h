// Contas do Godot do jeito que o GDScript faz (Math:: do motor), pra o C++
// dar os mesmos bits: maxf/minf/clampf/signf/lerpf/fposmod e as constantes do
// carro (carro_base.gd, carro_montagem.gd).
#pragma once

#include <cmath>

namespace atv4 {

const double TAU_ = 6.28318530717958647692;
const double PI_ = 3.14159265358979323846;
const double RPM2RAD = TAU_ / 60.0;
const double MPH = 0.44704;
const double MPH_G = 0.44694445;
const double DEG = 0.017453294;
const double GIRO_LIVRE = PI_;
const double TRAVA_MPH = 2.0;
const double TRAVA_INI = -0.25;
const double TRAVA_FIM = -1.0;

inline double absd(double x) { return x < 0.0 ? -x : x; }
inline double maxd(double a, double b) { return a > b ? a : b; }
inline double mind(double a, double b) { return a < b ? a : b; }
inline double clampd(double a, double lo, double hi) { return a < lo ? lo : (a > hi ? hi : a); }
inline double signd(double x) { return x > 0.0 ? 1.0 : (x < 0.0 ? -1.0 : 0.0); }
inline double lerpd(double a, double b, double t) { return a + (b - a) * t; }
inline double fposmod(double x, double y) {
	double v = std::fmod(x, y);
	if ((v < 0.0 && y > 0.0) || (v > 0.0 && y < 0.0)) {
		v += y;
	}
	return v;
}

} // namespace atv4
