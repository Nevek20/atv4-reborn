extends SceneTree
## Borrão de movimento das rodas (NOSSO, carro/roda_borrao.gd): todas as rodas
## do carro usam o shader, o giro do quadro = |ω| x dt (preso em GIRO_MAX) e
## segue a velocidade: parado 0, andando > 0. Uso:
##   godot --headless --path . -s res://tests/teste_borrao_rodas.gd
var main
var q := 0
var falhas := 0
var parado := 0.0


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _falha(t: String) -> void:
	print("  FALHA: " + t)
	falhas += 1


func _giro() -> float:
	var g := 0.0
	for w in main.car.wheels:
		g = maxf(g, float(w.malha_roda.get_instance_shader_parameter("giro")))
	return g


func _process(_d: float) -> bool:
	q += 1
	if q == 10:
		var n := 0
		for w in main.car.wheels:
			var mi: MeshInstance3D = w.get("malha_roda")
			if mi == null:
				_falha("roda sem malha_roda")
				continue
			for i in mi.mesh.get_surface_count():
				if not (mi.get_surface_override_material(i) is ShaderMaterial):
					_falha("material da roda sem o borrão")
			n += 1
		print("  %d rodas com o shader" % n)
		parado = _giro()
		main.car.test_input = {"thr": 1.0, "brk": 0.0, "steer": 0.0}
	if q == 160:
		var g := _giro()
		var v: float = main.car.linear_velocity.length() * 3.6
		print("  giro do borrão: parado %.3f rad, a %.0f km/h %.3f rad (máx %.1f)" % [parado, v, g, main.car.RodaBorrao.GIRO_MAX])
		if parado > 0.02:
			_falha("parado devia ser ~0")
		if g <= 0.05:
			_falha("andando devia borrar")
		print("teste_borrao_rodas: %s" % ("ok" if falhas == 0 else "FALHA (%d)" % falhas))
		quit()
		return true
	return false
