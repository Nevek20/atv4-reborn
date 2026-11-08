extends SceneTree
## Objetos do RX01 (objetos_rx01.gd, porta do jogo): confere
##  1. quantos modelos e instâncias carregam (57 pingus + 651 bantams; a
##     multidão .wahoo ainda não é convertida);
##  2. cada instância apoiada no terreno do remake: vértice mais baixo x chão
##     embaixo dele, de -3 a +1 m (o jogo põe cacto a 0.57 m e árvore 2.5 m
##     enterrada; eixo trocado na conversão daria dezenas de metros);
##  3. a largada livre (nenhum triângulo de colisão a 3 m das 8 largadas);
##  4. o céu (2 cúpulas do SkyDome) dentro do far da câmera, montanhas na
##     frente das nuvens;
##  5. o Renegade a 60 km/h de frente num guard-rail (Armco): com os objetos
##     ele para antes do plano da barreira; sem, ele atravessa.
## Uso: godot --headless --path . -s res://tests/teste_objetos.gd

const Car := preload("res://car.gd")
const Main := preload("res://main.gd")
const Terrain := preload("res://terrain.gd")
const Objetos := preload("res://objetos_rx01.gd")
const Ceu := preload("res://ceu.gd")

var terrain
var objetos
var falhas := 0
var fase := 0
var car = null
var t := 0.0
var armco: Transform3D
var normal := Vector3.ZERO
var minimo := INF
var com_objetos := true
var resultado := {}


func _initialize() -> void:
	terrain = Terrain.new()
	root.add_child(terrain)
	objetos = Objetos.new()
	root.add_child(objetos)


func _checa(ok: bool, txt: String) -> void:
	print(("ok      " if ok else "FALHOU  ") + txt)
	if not ok:
		falhas += 1


func _physics_process(dt: float) -> bool:
	if fase == 0:
		if not objetos.is_inside_tree():
			return false
		if not objetos.montar():
			print("teste_objetos: FALHA (sem data/rx01_objetos.json ou assets/rx01: rode tools/rx01_objetos.py)")
			return true
		var j = JSON.parse_string(FileAccess.get_file_as_string(Objetos.ARQ))
		_checa(objetos.instancias == 707 and objetos.modelos == 34,
			"%d instâncias de %d modelos (707 de 34; falta: %s)" % [objetos.instancias, objetos.modelos, ", ".join(objetos.faltando)])
		_checa(objetos.triangulos > 5000, "%d triângulos de colisão (KDt)" % objetos.triangulos)
		_ceu()
		# no chão: o vértice mais baixo do modelo fica no chão ou enterrado,
		# nunca voando
		var por := {}
		for it in j.instancias:
			if String(it.modelo).ends_with(".wahoo"):
				continue
			var x := Objetos.xf(it)
			# vértice mais baixo no mundo x chão embaixo dele (a caixa girada
			# de uma árvore inclinada de 48 m de copa desce metros)
			var dy := INF
			var baixo := Vector3(0, INF, 0)
			for v in _vertices(it.modelo):
				var w: Vector3 = x * v
				if w.y < baixo.y:
					baixo = w
			dy = baixo.y - terrain.height_at(baixo.x, baixo.z)
			if not por.has(it.modelo):
				por[it.modelo] = [INF, -INF]
			por[it.modelo] = [minf(por[it.modelo][0], dy), maxf(por[it.modelo][1], dy)]
		var pior := ""
		var lista := ""
		for m in por:
			lista += "\n    %-38s base %+.2f a %+.2f m do chão" % [m, por[m][0], por[m][1]]
			if por[m][0] < -3.0 or por[m][1] > 1.0:
				pior += " %s" % m
		print("  base dos modelos x chão do remake:" + lista)
		# limites largos: pegam conversão errada (eixo trocado = metros de
		# erro); o resto é o jogo (cacto 0.57 m acima, árvore de outono 2.5 m
		# enterrada no barranco, arquibancada larga num declive)
		_checa(pior == "", "nenhum modelo voando (até +1 m) nem afundado mais de 3 m%s" % pior)
		# largada livre
		var space: PhysicsDirectSpaceState3D = objetos.get_world_3d().direct_space_state
		var bola := SphereShape3D.new()
		bola.radius = 3.0
		var batidas := 0
		for e in j.entidades:
			if e.classe == "cStartPosition":
				var q := PhysicsShapeQueryParameters3D.new()
				q.shape = bola
				var p := Terrain.do_jogo(Vector3(e.pos[0], e.pos[1], e.pos[2]))
				q.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * 1.0)
				for h in space.intersect_shape(q, 8):
					if h.collider == objetos.corpo:
						batidas += 1
		_checa(batidas == 0, "largadas livres (%d batidas a 3 m)" % batidas)
		# guard-rail perto da largada: o 1º Armco a mais de 40 m dela, com
		# chão plano dos 2 lados
		var sp: Vector2 = Main.SPAWN_XZ
		var melhor := INF
		for it in j.instancias:
			if it.modelo != "GEN_Barrier_Armco_straight.bantam":
				continue
			var x := Objetos.xf(it)
			var d := Vector2(x.origin.x, x.origin.z).distance_to(sp)
			if d > 40.0 and d < melhor:
				# a barreira é fina no x do modelo: a normal dela é a 1ª coluna
				var n := x.basis.x.normalized()
				n.y = 0.0
				n = n.normalized()
				var lado := 1.0
				var a: Vector3 = x.origin + n * 12.0
				var b: Vector3 = x.origin - n * 12.0
				if absf(terrain.height_at(b.x, b.z) - x.origin.y) < absf(terrain.height_at(a.x, a.z) - x.origin.y):
					lado = -1.0
				armco = x
				normal = n * lado
				melhor = d
		_comeca(true)
		fase = 1
		return false
	if fase == 1:
		t += dt
		var dist: float = (car.global_position - armco.origin).dot(normal)
		minimo = minf(minimo, dist)
		if t < 3.0:
			return false
		resultado[com_objetos] = [minimo, car.linear_velocity.length() * 3.6]
		car.queue_free()
		if com_objetos:
			# de novo sem a colisão dos objetos: tem que atravessar
			objetos.corpo.process_mode = Node.PROCESS_MODE_DISABLED
			objetos.corpo.get_child(0).disabled = true
			_comeca(false)
			return false
		var c: Array = resultado[true]
		var s: Array = resultado[false]
		print("  guard-rail a %.0f m da largada, carro a 12 m de frente a 60 km/h" % Vector2(armco.origin.x, armco.origin.z).distance_to(Main.SPAWN_XZ))
		print("  com objetos: centro do carro chega a %.2f m do plano da barreira (%.0f km/h aos 3 s)" % [c[0], c[1]])
		print("  sem objetos: %.2f m (%.0f km/h)" % [s[0], s[1]])
		_checa(c[0] > 0.3 and s[0] < -1.0, "o guard-rail segura o carro (e sem ele o carro atravessa)")
		print("teste_objetos: %s" % ("ok" if falhas == 0 else "%d falhas" % falhas))
		return true
	return false


## céu (ceu.gd): as 2 cúpulas do Environment.xml carregam, cabem no far da
## câmera do main (4 km) e as montanhas (Inner) ficam na frente do céu (Outer)
func _ceu() -> void:
	var ceu = Ceu.new()
	root.add_child(ceu)
	if not ceu.montar():
		_checa(false, "céu: sem data/environment_rx01.xml ou assets/rx01/ceu (rode tools/rx01_objetos.py)")
		return
	var longe := 0.0
	var raios := []
	for c in ceu.cupulas:
		var x: Transform3D = Ceu.xf(Vector3.ZERO, c.y, c.rot)
		var r := 0.0
		for k in (c.no as MeshInstance3D).mesh.get_surface_count():
			for v in (c.no as MeshInstance3D).mesh.surface_get_arrays(k)[Mesh.ARRAY_VERTEX]:
				var w: Vector3 = x * v
				longe = maxf(longe, w.length())
				r = maxf(r, Vector2(w.x, w.z).length())
		raios.append(r)
	_checa(ceu.cupulas.size() == 2 and longe < 4000.0 and raios[1] < raios[0],
		"céu: %d cúpulas, ponto mais longe %.0f m (far 4000), raio do céu %.0f m e das montanhas %.0f m" % [
			ceu.cupulas.size(), longe, raios[0], raios[1] if raios.size() > 1 else 0.0])
	ceu.queue_free()


var _cache_v := {}


func _vertices(modelo: String) -> PackedVector3Array:
	if not _cache_v.has(modelo):
		var malha: Mesh = load(Objetos.PASTA + modelo.get_basename() + ".obj")
		var vs := PackedVector3Array()
		for k in malha.get_surface_count():
			vs.append_array(malha.surface_get_arrays(k)[Mesh.ARRAY_VERTEX])
		_cache_v[modelo] = vs
	return _cache_v[modelo]


func _comeca(com: bool) -> void:
	com_objetos = com
	t = 0.0
	minimo = INF
	car = Car.new()
	Main.configurar(car, Main.frota()[0])
	car.terrain = terrain
	car.suspension = false
	root.add_child(car)
	var p: Vector3 = armco.origin + normal * 12.0
	p.y = terrain.height_at(p.x, p.z) + 0.8
	# de frente pra barreira: a frente do carro (z) aponta pra -normal
	var yaw := atan2(-normal.x, -normal.z)
	car.reset_to(p, yaw)
	car.linear_velocity = -normal * (60.0 / 3.6)
	car.test_input = {"thr": 0.3, "brk": 0.0, "steer": 0.0}
