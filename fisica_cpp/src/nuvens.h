// Nuvens da poeira em C++ (efeitos/poeira.gd usa quando a biblioteca existe):
// guarda as nuvens soltas e, a cada quadro, envelhece, tira as mortas e
// escreve o buffer da MultiMesh. Onde e quando nasce cada nuvem (e o sorteio)
// continua no GDScript.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/object_id.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <vector>

namespace godot {

class NuvensCpp : public RefCounted {
	GDCLASS(NuvensCpp, RefCounted)

	// os mesmos arrays do poeira.gd (n_pos, n_idade...), com os mesmos tipos
	std::vector<Vector3> pos;
	std::vector<float> idade, vida, maxi, ini, alvo, a0, cel;
	std::vector<Color> cor;
	std::vector<uint8_t> agua;
	PackedFloat32Array buf, buf_agua;
	ObjectID mm, mm_agua;
	int64_t cap = 64;
	int64_t max_nuvens = 1024;

protected:
	static void _bind_methods();

public:
	void configurar(Object *mm, Object *mm_agua, int64_t cap, int64_t max_nuvens);
	void add(Vector3 p, double idade, double vida, double maxi, double ini, double alvo, double a0, Color cor,
			double cel, int64_t agua);
	int64_t vivas() const;
	PackedByteArray agua_vivas() const;
	Array exportar() const;
	Array buffers() const;   // [buf, buf_agua] (testes)
	int64_t quadro(double delta, double escala);
};

} // namespace godot
