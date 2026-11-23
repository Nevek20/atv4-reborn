extends SceneTree
## Pneu comprado (carro/pecas.gd slot Tire, oficina aba Upgrade): os 11 pneus
## do catálogo (componentes.xml) pra buggy e truck; cada um troca a roda pelo
## modelo TYRE_<pneu>_<tamanho> do jogo (pecas.json "pneus", gerar_buggies) e
## o atrito na terra pelo Override do material (terrain.atrito). De fábrica
## (DIRT_BUDGET) o jogo põe a TYRE_GENERIC (RAM); aqui a TYRE_DIRT_BUDGET com
## cravos (NOSSO, carro_base DIRT_BUDGET_CRAVOS) quando o pecas.json tem ela
## (gerar_buggies novo). Aro (Alloy): os 7 do
## catálogo; troca a textura ALLOY da roda pela IG_WHEEL_HEAVYCLASS_0N.
## Uso: godot --headless --path . -s res://tests/teste_pneu.gd

const PECAS := preload("res://carro/pecas.gd")
var main
var q := 0
var falhas := 0
var fab := {}


func _initialize() -> void:
	for cls in ["Buggy", "Truck"]:
		var op: Dictionary = PECAS.opcoes(cls)
		var n: int = op.slots.get("Tire", []).size()
		print("  %s: %d pneus (%s)" % [cls, n, ", ".join(op.slots.get("Tire", []).map(func(p): return PECAS.rotulo(p)))])
		if n != 11:
			_falha("%s devia ter 11 pneus" % cls)
		var na: int = op.slots.get("Alloy", []).size()
		print("  %s: %d aros (%s)" % [cls, na, ", ".join(op.slots.get("Alloy", []).map(func(p): return PECAS.rotulo(p)))])
		if na != 8:
			_falha("%s devia ter 8 aros (7 do catálogo + o 8 extra)" % cls)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _falha(t: String) -> void:
	print("  FALHA: " + t)
	falhas += 1


func _process(_d: float) -> bool:
	q += 1
	if q == 40:               # carro de fábrica assentado no chão
		fab = _medir()
		print("  de fábrica: %s, roda %s, atrito %s" % [fab.pneu, fab.roda.get_file(), fab.mu])
		var pjf = JSON.parse_string(FileAccess.get_file_as_string(main.car.asset_dir.path_join("pecas.json")))
		if pjf.get("pneus", {}).has("DIRT_BUDGET"):
			var cravos: String = String(pjf.pneus.DIRT_BUDGET.FrontWheel).get_file()
			print("  de fábrica com cravos (NOSSO): roda %s (a do pecas.json %s)" % [fab.roda.get_file(), cravos])
			if not fab.roda.ends_with(cravos):
				_falha("de fábrica devia usar a TYRE_DIRT_BUDGET com cravos")
		else:
			print("  (pecas.json sem DIRT_BUDGET: rode o gerar_buggies; fica a genérica)")
		main.car.queue_free()
		var c = main.car
		var p: Vector3 = c.global_position
		var i: int = main.veh_idx
		main.car = null
		var Car = load("res://carro/car.gd")
		var novo = Car.new()
		main.configurar(novo, main.frota()[i])
		novo.pecas_escolhidas = {"Tire": "SAND_BUDGET", "Alloy": "WHEEL_08"}
		novo.terrain = main.terrain
		novo.objetos = main.objetos
		main.add_child(novo)
		main.car = novo
		novo.reset_to(p, c.global_rotation.y)
	if q == 80:
		var com := _medir()
		print("  Areia Budget: %s, roda %s, atrito %s" % [com.pneu, com.roda.get_file(), com.mu])
		if com.pneu != "SAND_BUDGET":
			_falha("a física não pegou o pneu")
		if com.roda == fab.roda:
			_falha("a roda não trocou de modelo")
		var pj = JSON.parse_string(FileAccess.get_file_as_string(main.car.asset_dir.path_join("pecas.json")))
		if not com.roda.ends_with(String(pj.pneus.SAND_BUDGET.FrontWheel).get_file()):
			_falha("a roda não é a do pneu no pecas.json")
		# atrito na terra comum (DIRT/COMMON) pelo material do terreno, pro pneu de cada um
		var t = main.terrain
		var terra := -1
		for m in t.materials.size():
			if t.material_name(m) == "DIRT/COMMON":
				terra = m
		var a0: float = t.atrito(terra, fab.pneu)
		var a1: float = t.atrito(terra, com.pneu)
		print("  na terra comum: de fábrica %.2f, Areia Budget %.2f (no asfalto do spawn os dois %.2f)" % [a0, a1, com.mu])
		if terra < 0 or a1 >= a0:
			_falha("areia na terra devia agarrar menos que o de fábrica")
		print("  aro: de fábrica %s, com WHEEL_08 (extra) %s" % [fab.aro, com.aro])
		if not fab.aro.contains("ALLOY") or not com.aro.contains("HEAVYCLASS_08"):
			_falha("a textura do aro não trocou")
		print("teste_pneu: %s" % ("ok" if falhas == 0 else "FALHA (%d)" % falhas))
		quit()
		return true
	return false


func _medir() -> Dictionary:
	var c = main.car
	var mus: Array = []
	for w in c.wheels:
		mus.append(snappedf(float(w.get("mu", 0.0)), 0.01))
	# textura do aro na roda da frente (material ALLOY / HEAVYCLASS)
	var aro := ""
	for mi in c.wheels[0].spin_node.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var m = mi.get_surface_override_material(i)
			var tx = m.get_shader_parameter("tex") if m is ShaderMaterial else (m.albedo_texture if m is StandardMaterial3D else null)
			if tx:
				var f: String = tx.resource_path.get_file()
				if f.contains("ALLOY") or f.contains("HEAVYCLASS"):
					aro = f
	return {"pneu": c.pneu, "roda": String(c.wheel_front_file), "mu": mus.max(), "aro": aro}
