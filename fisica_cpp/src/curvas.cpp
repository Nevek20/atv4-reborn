#include "curvas.h"

#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <algorithm>

using namespace godot;

namespace atv4 {

static inline double clamp01(double x) {
	return x < 0.0 ? 0.0 : (x > 1.0 ? 1.0 : x);
}

// lerpf do Godot: a + (b - a) * t
static inline double lerp(double a, double b, double t) {
	return a + (b - a) * t;
}

Curva::Curva(const Dictionary &c) {
	PackedFloat32Array a = c.get(String("v"), PackedFloat32Array());
	v.resize(a.size());
	for (int64_t i = 0; i < a.size(); i++) {
		v[i] = a[i];
	}
	max = c.get(String("max"), 1.0);
}

double Curva::sample(double x) const {
	const int n = (int)v.size();
	if (n == 1) {
		return v[0];
	}
	if (n == 0) {
		return 0.0;
	}
	double pos = clamp01(x / max) * (double)(n - 1);
	int i = std::min((int)pos, n - 2);
	return lerp(v[i], v[i + 1], pos - i);
}

double Curva::integrate(double x) const {
	const int n = (int)v.size();
	if (n == 1) {
		return v[0] * x;
	}
	if (n == 0) {
		return 0.0;
	}
	double seg = max / (double)(n - 1);
	double total = 0.0;
	int i = 0;
	while (i < n - 1 && x > i * seg) {
		double x0 = i * seg;
		double x1 = std::min(x, (i + 1) * seg);
		double y0 = v[i];
		double y1 = lerp(v[i], v[i + 1], (x1 - x0) / seg);
		total += (y0 + y1) * 0.5 * (x1 - x0);
		i += 1;
	}
	if (x > max) {
		total += v[n - 1] * (x - max);
	}
	return total;
}

Trio::Trio(const Dictionary &t) {
	max = t.get(String("max"), 0.0);
	min = t.get(String("min"), 0.0);
	sp = t.get(String("sp"), 0.0);
	lmax = t.get(String("lmax"), 1.0);
	lmin = t.get(String("lmin"), 0.1);
}

double Trio::eval(double mu) const {
	if (mu <= lmin) {
		return min;
	}
	if (mu > 1.0) {
		return sp;
	}
	if (mu >= lmax) {
		return max;
	}
	return min + (mu - lmin) / (lmax - lmin) * (max - min);
}

FCurvas::FCurvas(const Dictionary &c) {
	max = Curva(c.get(String("max"), Dictionary()));
	min = Curva(c.get(String("min"), Dictionary()));
	sp = Curva(c.get(String("sp"), Dictionary()));
	lmax = c.get(String("lmax"), 1.0);
	lmin = c.get(String("lmin"), 0.1);
}

double FCurvas::eval(double mu, double x) const {
	if (mu <= lmin) {
		return min.sample(x);
	}
	if (mu > 1.0) {
		return sp.sample(x);
	}
	if (mu >= lmax) {
		return max.sample(x);
	}
	double lo = min.sample(x);
	return lo + (mu - lmin) / (lmax - lmin) * (max.sample(x) - lo);
}

} // namespace atv4
