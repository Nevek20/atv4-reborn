// Pintura do carro (oficina, nov/2026): junta as camadas que o
// tools/gerar_pintura.py salva (mascaras.png, detalhe.png, logos.png) com as 3
// cores. A MESMA conta inteira do carro/pintura.gd e do PIL (composite =
// DIV255, alpha_composite com 7 bits): sai igual à pintura.png, pixel a pixel
// (tests/teste_pintura_jogo.gd).
#include "fisica_carro.h"

#include <cstdint>

using namespace godot;

static inline uint32_t div255(uint32_t a) {
	uint32_t t = a + 128;
	return ((t >> 8) + t) >> 8;
}

// masc RGB8 (R = primária, G = secundária), det e logos RGBA8; cores = base,
// primária, secundária (r, g, b; -1 = sem a camada) -> RGB8
PackedByteArray FisicaCarro::compor_pintura(const PackedByteArray &masc, const PackedByteArray &det,
		const PackedByteArray &logos, const PackedInt32Array &cores) {
	PackedByteArray out;
	const int64_t n = det.size() / 4;
	if (cores.size() < 9 || masc.size() < n * 3 || logos.size() < n * 4) {
		return out;
	}
	out.resize(n * 3);
	const uint8_t *m = masc.ptr();
	const uint8_t *d = det.ptr();
	const uint8_t *l = logos.ptr();
	const int32_t *c = cores.ptr();
	uint8_t *o = out.ptrw();
	const bool tem_p = c[3] >= 0, tem_s = c[6] >= 0;
	for (int64_t i = 0; i < n; i++) {
		const uint32_t mp = tem_p ? m[i * 3] : 0, ms = tem_s ? m[i * 3 + 1] : 0;
		const uint32_t md = d[i * 4 + 3], la = l[i * 4 + 3];
		for (int k = 0; k < 3; k++) {
			uint32_t v = (uint32_t)c[k];
			if (mp) {
				v = div255(v * (255 - mp) + (uint32_t)c[3 + k] * mp);
			}
			if (ms) {
				v = div255(v * (255 - ms) + (uint32_t)c[6 + k] * ms);
			}
			if (md) {
				v = div255(v * (255 - md) + d[i * 4 + k] * md);
			}
			if (la) {
				const uint32_t c1 = la * 255 * 255 * 128 / (la * 255 + 255 * (255 - la));
				const uint32_t t = l[i * 4 + k] * c1 + v * (255 * 128 - c1) + (0x80 << 7);
				v = (((t >> 8) + t) >> 8) >> 7;
			}
			o[i * 3 + k] = (uint8_t)v;
		}
	}
	return out;
}

// Piloto (oficina, nov/2026): as 7 partes da textura (roupa, braços, pernas,
// óculos, bota, luva, capacete), cada uma [x, y, w, h, base, primary,
// secondary, detail, wrinkle] (RGBA8 já no tamanho da caixa); cores = base,
// primária, secundária (r, g, b) -> RGB8 tam x tam. A mesma conta do
// carro/piloto_pintura.gd e do tools/piloto_pintura.py (pixel a pixel:
// tests/teste_piloto_pintura.gd)
PackedByteArray FisicaCarro::compor_piloto(int64_t tam, const Array &partes, const PackedInt32Array &cores) {
	PackedByteArray out;
	if (tam <= 0 || cores.size() < 9) {
		return out;
	}
	out.resize(tam * tam * 3);
	uint8_t *o = out.ptrw();
	const int32_t *c = cores.ptr();
	for (int64_t n = 0; n < partes.size(); n++) {
		const Array pt = partes[n];
		if (pt.size() < 9) {
			continue;
		}
		const int64_t x0 = pt[0], y0 = pt[1], w = pt[2], h = pt[3];
		const PackedByteArray ba = pt[4], pr = pt[5], se = pt[6], de = pt[7], ru = pt[8];
		const int64_t px = w * h * 4;
		if (ba.size() < px || pr.size() < px || se.size() < px || de.size() < px || ru.size() < px ||
				x0 < 0 || y0 < 0 || x0 + w > tam || y0 + h > tam) {
			continue;
		}
		const uint8_t *b = ba.ptr(), *p = pr.ptr(), *s = se.ptr(), *d = de.ptr(), *r = ru.ptr();
		for (int64_t yy = 0; yy < h; yy++) {
			for (int64_t xx = 0; xx < w; xx++) {
				const int64_t i = (yy * w + xx) * 4;
				uint8_t *q = o + ((y0 + yy) * tam + x0 + xx) * 3;
				const uint32_t ap = p[i + 3], as = s[i + 3], ad = d[i + 3];
				for (int k = 0; k < 3; k++) {
					uint32_t v = b[i + k] * (uint32_t)c[k] / 255;
					v = div255(v * (255 - ap) + (p[i + k] * (uint32_t)c[3 + k] / 255) * ap);
					v = div255(v * (255 - as) + (s[i + k] * (uint32_t)c[6 + k] / 255) * as);
					v = div255(v * (255 - ad) + d[i + k] * ad);
					q[k] = (uint8_t)(v * r[i + k] / 255);
				}
			}
		}
	}
	return out;
}
