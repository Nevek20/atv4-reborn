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
