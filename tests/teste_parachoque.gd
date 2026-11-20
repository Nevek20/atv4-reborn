extends SceneTree
## Para-choque comprado (carro/pecas.gd slot Bumper, oficina aba Upgrade):
## 1) o catálogo (componentes.xml) tem 9 opções por classe (NOT_INSTALLED +
##    BUMPER_01..08_HEAVYCLASS_LARGE) e o de fábrica é NOT_INSTALLED
## 2) frota toda (pecas.json do gerar_buggies): os carros com Bumper no
##    component map têm os 8 modelos e o ponto BUMPER; o RallyCompMap (Storm,
##    Chimera) não tem nenhum. Montado no ponto BUMPER (matriz identidade), a
##    frente do para-choque fica de 0 a ~0.6 m à frente da carroceria e acima
##    do fundo dela (se o ponto ou o frame estivessem errados, cairia dentro
##    do carro ou no chão)
## 3) carro montado (Renegade, Buccaneer, Storm): o para-choque escolhido entra
##    no model_root na posição do ponto; de fábrica não tem; só visual: massa,
##    casco e motor iguais aos de fábrica
## Uso: godot --headless --path . -s res://tests/teste_parachoque.gd

const Main := preload("res://main.gd")
const Car := preload("res://carro/car.gd")
const PECAS := preload("res://carro/pecas.gd")
const BP := "BUMPER_04_HEAVYCLASS_LARGE"

var falhas := 0
var carros: Array = []
var q := 0


func _falha(t: String) -> void:
	print("  FALHA: " + t)
	falhas += 1


func _initialize() -> void:
	for cls in ["Buggy", "Truck"]:
		var l: Array = PECAS.opcoes(cls).slots.get("Bumper", [])
		print("  %s: %d opções (%s)" % [cls, l.size(), ", ".join(l.map(func(p): return PECAS.rotulo(p)))])
		if l.size() != 9 or l[0] != "NOT_INSTALLED":
			_falha("%s devia ter Nenhum + 8 para-choques" % cls)
	if PECAS.fabrica("BUGGY_10").config.get("Bumper") != "NOT_INSTALLED":
		_falha("de fábrica devia ser NOT_INSTALLED")
	# 2) a frota pelo pecas.json
	var pts_de = Car.new()
	var vistos := {}
	var pior := [INF, -INF]
	for v in Main.frota():
		var dir: String = v.dir
		if vistos.has(dir) or not FileAccess.file_exists(dir.path_join("pecas.json")):
			continue
		vistos[dir] = true
		var pj = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("pecas.json")))
		if not pj.has("parachoques"):
			if not String(v.get("id", "")).begins_with("ESCORT"):
				_falha("%s: pecas.json sem parachoques (rode o gerar_buggies)" % v.name)
			continue
		var rally: bool = String(v.id) in ["BUGGY_12", "TRUCK_12"]
		var lista: Dictionary = pj.parachoques
		if rally != lista.is_empty():
			_falha("%s: %s" % [v.name, "rally não devia ter para-choque" if rally else "sem os para-choques"])
		if rally:
			continue
		if lista.size() != 8:
			_falha("%s: %d para-choques" % [v.name, lista.size()])
		var pts: Dictionary = pts_de._load_points(v.points)
		if not pts.has(pj.ponto_parachoque):
			_falha("%s: sem o ponto %s" % [v.name, pj.ponto_parachoque])
			continue
		var p: Vector3 = pts[pj.ponto_parachoque]
		var corpo: AABB = (load(dir.path_join(pj.pecas.Body)) as Mesh).get_aabb()
		for k in lista:
			var path := dir.path_join(lista[k]).simplify_path()
			if not ResourceLoader.exists(path):
				_falha("%s: falta %s" % [v.name, path])
				continue
			var a: AABB = (load(path) as Mesh).get_aabb()
			var frente := p.z + a.end.z - corpo.end.z
			var baixo := p.y + a.position.y - corpo.position.y
			pior = [minf(pior[0], frente), maxf(pior[1], frente)]
			if frente < -0.1 or frente > 0.65 or baixo < 0.0:
				_falha("%s %s: frente %.2f m da carroceria, %.2f m acima do fundo" % [v.name, k, frente, baixo])
	pts_de.free()
	print("  frota: %d carros, a frente do para-choque fica de %.2f a %.2f m à frente da carroceria" % [vistos.size(), pior[0], pior[1]])
	# 3) montado
	for id in ["BUGGY_10", "TRUCK_01", "BUGGY_12"]:
		var v: Dictionary = {}
		for x in Main.frota():
			if x.get("id", "") == id and v.is_empty():
				v = x
		for com in [false, true]:
			var c = Car.new()
			Main.configurar(c, v)
			if com:
				c.pecas_escolhidas = {"Bumper": BP}
			root.add_child(c)
			c.reset_to(Vector3(carros.size() * 30.0, 50.0, 0.0), 0.0)
			carros.append({"c": c, "nome": v.name, "com": com, "rally": id == "BUGGY_12"})


func _process(_d: float) -> bool:
	q += 1
	if q < 2:
		return false
	for i in range(0, carros.size(), 2):
		var fab = carros[i].c
		var com = carros[i + 1].c
		var nome: String = carros[i].nome
		if fab.parachoque_mi != null:
			_falha("%s de fábrica com para-choque" % nome)
		if carros[i].rally:
			if com.tem_parachoque() or com.parachoque_mi != null:
				_falha("%s (rally) não devia montar para-choque" % nome)
			else:
				print("  %s: sem para-choque (RallyCompMap), como no jogo" % nome)
			continue
		var mi: MeshInstance3D = com.parachoque_mi
		if mi == null or mi.get_parent() != com.model_root:
			_falha("%s: para-choque não montou" % nome)
			continue
		var alvo: Vector3 = com.model_offset + com.points[com.pecas.ponto_parachoque]
		if mi.position.distance_to(alvo) > 1e-5:
			_falha("%s: fora do ponto BUMPER" % nome)
		var cascos := func(c) -> int:
			return c.get_children().filter(func(n): return n is CollisionShape3D).size()
		print("  %s com %s: no ponto %s, massa %.0f x %.0f kg, casco %d x %d esferas, motor %.2f x %.2f" % [
			nome, PECAS.rotulo(BP), com.points[com.pecas.ponto_parachoque], com.mass, fab.mass,
			cascos.call(com), cascos.call(fab), com.TUNE_ENGINE, fab.TUNE_ENGINE])
		if com.mass != fab.mass or cascos.call(com) != cascos.call(fab) or com.TUNE_ENGINE != fab.TUNE_ENGINE:
			_falha("%s: o para-choque mexeu na física (é só visual no jogo)" % nome)
	print("teste_parachoque: %s" % ("ok" if falhas == 0 else "FALHA (%d)" % falhas))
	quit()
	return true
