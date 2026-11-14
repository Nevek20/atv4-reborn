// Vozes do tocador do jogo em C++ (som/som_jogo.gd usa quando a biblioteca
// existe): anda o envelope do SPU, tira as vozes mortas e regrava volume e
// tom no player. O sequenciador dos grãos continua no GDScript.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>

namespace godot {

class SomJogoCpp : public RefCounted {
	GDCLASS(SomJogoCpp, RefCounted)

protected:
	static void _bind_methods();

public:
	Array vivas(Array vozes, double ticks, double volume, double ganho, double tom);
};

} // namespace godot
