extends SceneTree
## Score (pista/truques.gd + menu/hud_jogo.gd passo_truques) contra as contas
## do exe e a RAM:
##  1. estado do carro (0x524980) com os números do seta.p2s (derrapagem
##     0.2996 rad a 25.46 m/s = Slide 5) e os limites (17°, 10 m/s, 0.4 s);
##  2. 1º quadro do truque igual à RAM do seta.p2s (tempo 0.02, taxa 500,
##     pontos 0);
##  3. Slide de 50 quadros: pontos = 500 x dt x soma(1.005^k, k = 1..49)
##     (taxa += taxa x 0.25 x dt), banca 0.5 + 0.75 s depois no chão;
##  4. Slide esquerda -> direita direto: 2 truques diferentes (X2), o 2º
##     começa sem zerar os pontos (0x522550) e o banco = combo x 2;
##  5. AirTime: conta a partir de 0.4 s no ar; batida no ar zera o tempo;
##     batida no 1º quadro não deixa começar; devagar não soma;
##  6. chegada com o combo aberto perde (mensagem vermelha, total igual);
##  7. HUD: nome na fila só quando muda ("Slide + Air Time"), "%u X%u",
##     cor da RAM, texto parado em 1.1 s com o combo aberto e sumindo depois;
##  8. o carro de verdade (física) na reta do RX01: andando reto o casco não
##     encosta (senão nenhum truque começa); caindo de 4 m vira AirTime e
##     derrapando vira Slide.
## Uso: godot --headless --path . -s res://tests/teste_truques.gd

const Truques := preload("res://pista/truques.gd")
const Car := preload("res://carro/car.gd")
const Main := preload("res://main.gd")
const Terrain := preload("res://pista/terrain.gd")
const DT := 0.02

var falhas := 0
var terrain
var car
var tr
var fase := ""
var n := 0
var contatos_max := 0
var viu := {}
var eventos: Array = []


func _falha(m: String) -> void:
	falhas += 1
	print("FALHA: ", m)


## pontos do truque depois de n quadros (1 começa + n-1 somando)
static func formula(nq: int, score := 500.0, accel := 0.25, dt := DT) -> float:
	var q := 1.0 + accel * dt
	var s := 0.0
	var taxa := score
	for k in nq - 1:
		taxa *= q
		s += taxa * dt
	return s


func _novo() -> Object:
	var t = Truques.new("Buggy")
	t.ligado = true
	return t


## n quadros com os mesmos dados; devolve os eventos que apareceram
func _rodar(t, nq: int, rodas: int, beta: float, v: float, contatos := 0) -> Array:
	var evs: Array = []
	for i in nq:
		t.passo_dados(DT, rodas, contatos, beta, v, v)
		var e: Dictionary = t.ler_evento()
		if not e.is_empty():
			evs.append(e)
	return evs


func _initialize() -> void:
	_tabela()
	_estados()
	_primeiro_quadro()
	_slide()
	_esquerda_direita()
	_airtime()
	_chegada()
	_hud()
	terrain = Terrain.new()
	root.add_child(terrain)
	var v: Dictionary = Main.VEHICLES[0]
	car = Car.new()
	car.asset_dir = v.dir
	car.data_files = ["res://data/vehicles/buggy_base.xml", v.data]
	car.points_file = v.points
	car.vehicle_id = v.id
	car.tune_override = v.get("tune", {})
	car.terrain = terrain
	car.suspension = false
	root.add_child(car)


func _tabela() -> void:
	var b: Dictionary = Truques.ler_tabela("Buggy")
	var t: Dictionary = Truques.ler_tabela("Truck")
	print("  TRICKS.xml Buggy %s, Truck %s" % [b, t])
	for d in [b, t]:
		if d.get(4) != [500, 99999, 0.25] or d.get(5) != [500, 99999, 0.25] or d.get(6) != [500, 99999, 0.25]:
			_falha("tabela do TRICKS.xml")


func _estados() -> void:
	var casos := [
		[4, 0.0, 0.2996, 25.46, 5, "seta.p2s (RAM: estado 5)"],
		[4, 0.0, -0.2996, 25.46, 4, "derrapagem pro outro lado"],
		[4, 0.0, deg_to_rad(16.9), 25.0, 8, "16.9°"],
		[4, 0.0, deg_to_rad(17.1), 9.9, 8, "9.9 m/s"],
		[4, 0.0, deg_to_rad(95.0), 25.0, 8, "> 89° vale 0"],
		[0, 0.38, 0.0, 25.0, 9, "0.38 s no ar"],
		[0, 0.41, 0.0, 25.0, 6, "0.41 s no ar"],
	]
	for c in casos:
		var e: int = Truques.estado_carro(c[0], c[1], c[2], c[3])
		if e != c[4]:
			_falha("estado %s: %d (devia %d)" % [c[5], e, c[4]])
	print("  estados (0x524980): %d casos" % casos.size())


func _primeiro_quadro() -> void:
	var t = _novo()
	_rodar(t, 1, 4, 0.2996, 25.46)
	print("  1º quadro do Slide: estado %d, tempo %.3f, taxa %.1f, pontos %.1f (RAM seta.p2s: 5, 0.020, 500.0, 0.0)" % [
		t.estado, t.t_truque, t.taxa, t.pts])
	if t.estado != 5 or absf(t.t_truque - 0.02) > 1e-6 or t.taxa != 500.0 or t.pts != 0.0:
		_falha("1º quadro do truque")


func _slide() -> void:
	var t = _novo()
	var evs := _rodar(t, 50, 4, 0.4, 20.0)
	var esperado := int(formula(50))
	var antes: int = t.combo
	evs += _rodar(t, 1, 4, 0.0, 20.0)       # endireitou: fecha
	var fechou: int = t.combo
	var q := 0
	while t.total == 0 and q < 200:
		_rodar(t, 1, 4, 0.0, 20.0)
		q += 1
	print("  Slide 50 quadros: fechou %d (fórmula %d), combo antes %d, banco %d depois de %d quadros (0.5 + 0.75 s = 63)" % [
		fechou, esperado, antes, t.total, q + 1])
	if fechou != esperado or antes != 0 or t.total != esperado or absi(q + 1 - 63) > 2:
		_falha("Slide simples")
	if evs.is_empty() or evs[0].nome != "Slide" or evs[0].tipo != Truques.AO_VIVO:
		_falha("Slide aparece ao vivo")
	# curto (0.2 s) não vale
	var t2 = _novo()
	_rodar(t2, 10, 4, 0.4, 20.0)
	_rodar(t2, 80, 4, 0.0, 20.0)
	if t2.total != 0 or t2.combo_ativo:
		_falha("Slide de 0.2 s não vale")
	# devagar (abaixo de 2.2347 m/s no plano) não começa
	var t3 = _novo()
	for i in 30:
		t3.passo_dados(DT, 4, 0, 0.4, 20.0, 2.0)
	if t3.estado != 8:
		_falha("devagar não começa")


func _esquerda_direita() -> void:
	var t = _novo()
	var evs := _rodar(t, 30, 4, -0.4, 20.0)
	evs += _rodar(t, 30, 4, 0.4, 20.0)
	evs += _rodar(t, 1, 4, 0.0, 20.0)
	var p1 := formula(30)
	var p2 := p1 + formula(30)                  # 0x522550: o 2º começa sem zerar os pontos
	var combo := int(p1) + int(p2)
	var vivo: Dictionary = {}
	for e in evs:
		if e.tipo == Truques.AO_VIVO and e.mult == 2:
			vivo = e
			break
	print("  esquerda -> direita: combo %d (fórmula %d), multiplicador %d, ao vivo X%d" % [
		t.combo, combo, t.mult, vivo.get("mult", 0)])
	if t.combo != combo or t.mult != 2 or vivo.is_empty():
		_falha("combo esquerda -> direita")
	_rodar(t, 100, 4, 0.0, 20.0)
	print("  banco: %d (= %d x 2)" % [t.total, combo])
	if t.total != combo * 2:
		_falha("banco = combo x multiplicador")


func _airtime() -> void:
	var t = _novo()
	var evs := _rodar(t, 50, 0, 0.0, 20.0)     # 1 s no ar
	evs += _rodar(t, 1, 4, 0.0, 20.0)          # pousou
	# 0.4 s no ar: o estado 6 começa no 20º quadro (ar >= 0.4), 31 quadros de truque
	var lim := [int(formula(30)), int(formula(32))]
	var nome := ""
	for e in evs:
		if e.tipo == Truques.FECHOU:
			nome = e.nome
	print("  AirTime 1 s: %d pontos (fórmula entre %d e %d), %s" % [t.combo, lim[0], lim[1], nome])
	if nome != "AirTime" or t.combo < lim[0] or t.combo > lim[1]:
		_falha("AirTime")
	# batida no ar zera o tempo (0x215248): nunca chega a 0.4 s
	var t2 = _novo()
	for i in 50:
		t2.passo_dados(DT, 0, 1 if i % 15 == 14 else 0, 0.0, 20.0, 20.0)
	if t2.estado != 8 or t2.ar > 0.3:
		_falha("batida no ar zera o tempo")
	# batida no quadro de começar: não começa
	var t3 = _novo()
	_rodar(t3, 1, 4, 0.4, 20.0, 1)
	var e3: int = t3.estado
	_rodar(t3, 1, 4, 0.4, 20.0, 0)
	print("  batida: no ar o tempo fica em %.2f s; começando com batida estado %d, sem %d" % [t2.ar, e3, t3.estado])
	if e3 != 8 or t3.estado != 5:
		_falha("batida no começo do truque")


func _chegada() -> void:
	var t = _novo()
	_rodar(t, 40, 4, 0.4, 20.0)
	var p := int(formula(40))
	t.parar()
	var e: Dictionary = t.ler_evento()
	print("  chegada com o Slide aberto: %s, total %d" % [e, t.total])
	if e.get("tipo", -1) != Truques.PERDEU or e.get("pontos", 0) != p or e.get("mult", 0) != 1 or t.total != 0 or t.ligado:
		_falha("chegada perde o combo")


func _hud() -> void:
	var h = load("res://menu/hud_jogo.gd").new()
	if not h.montar():
		print("  HUD: sem assets/hud (pulado)")
		h.free()
		return
	var t = _novo()
	var passo := func(nq: int, rodas: int, beta: float) -> void:
		for i in nq:
			t.passo_dados(DT, rodas, 0, beta, 20.0, 20.0)
			h.passo_truques(DT, t)
	passo.call(30, 4, 0.4)                     # Slide aparecendo
	var n1: String = h.mensagem_atual("TRICK_NAME")
	var s1: String = h.valores.get("TRICK_SCORE", "")
	var vis1: bool = h.grupo_visivel("TRICK_MESSAGE")
	passo.call(50, 0, 0.0)                     # pulou: Slide fecha, AirTime
	var n2: String = h.mensagem_atual("TRICK_NAME")
	var s2: String = h.valores.get("TRICK_SCORE", "")
	passo.call(1, 4, 0.0)                      # pousou
	passo.call(40, 4, 0.0)                     # combo aberto (folga + chão): o texto fica parado
	var c_aberto: Color = h.valores.get("TRICK_NAME#cor", Color())
	var dc_aberto: float = h._tr.dc
	passo.call(30, 4, 0.0)                     # bancou e vai sumindo
	var s3: String = h.valores.get("TRICK_SCORE", "")
	var total: int = h.valores.get("TOTAL_TRICK_SCORE", -1)
	var c_fim: Color = h.valores.get("TRICK_NAME#cor", Color())
	passo.call(40, 4, 0.0)
	var vis4: bool = h.grupo_visivel("TRICK_MESSAGE")
	print("  HUD: '%s' '%s' (grupo %s) -> '%s' '%s' -> aberto alfa %.2f (dc %.2f) -> banco '%s' total %d alfa %.2f -> some %s" % [
		n1, s1, vis1, n2, s2, c_aberto.a, dc_aberto, s3, total, c_fim.a, not vis4])
	var c: Color = h.COR_TRUQUE
	if n1 != "Slide" or not vis1 or n2 != "Slide + Air Time" or not s2.ends_with(" X2") \
			or c_aberto.a != 1.0 or absf(dc_aberto - 1.1) > 0.03 or not c_aberto.is_equal_approx(Color(c.r, c.g, c.b, 1.0)) \
			or s3 != str(total) or total != t.total or total <= 0 or c_fim.a >= 1.0 or vis4:
		_falha("HUD do truque")
	# perdeu: vermelho com a última cadeia, 3 s
	var t2 = _novo()
	var passo2 := func(nq: int) -> void:
		for i in nq:
			t2.passo_dados(DT, 4, 0, 0.4, 20.0, 20.0)
			h.passo_truques(DT, t2)
	passo2.call(40)
	t2.parar()
	h.passo_truques(DT, t2)
	var cp: Color = h.valores.get("TRICK_NAME#cor", Color())
	print("  perdeu: '%s' '%s' cor %s, fila %.1f s" % [h.mensagem_atual("TRICK_NAME"), h.valores.get("TRICK_SCORE", ""),
		cp, h._msgs.TRICK_NAME[0][2]])
	if h.mensagem_atual("TRICK_NAME") != "Slide" or cp.r != 1.0 or cp.g != 0.0 or h._msgs.TRICK_NAME[0][2] != 3.0:
		_falha("HUD perdeu")
	h.free()


func _physics_process(_dt: float) -> bool:
	if not car.is_inside_tree():
		return false
	n += 1
	var g := Vector3(1564.546 - 1024.0, 0.0, 581.276)        # grid 1 do RX01 (mundo)
	var frente := Vector3(-0.421, 0.0, -0.907).normalized()
	var lado := Vector3.UP.cross(frente)
	if fase == "":
		_por(g, frente, 0.5, frente * 15.0)
		car.test_input = {"thr": 0.5, "brk": 0.0, "steer": 0.0}
		tr = _novo()
		fase = "reta"
		n = 0
		return false
	tr.passo(DT, car)
	var e: Dictionary = tr.ler_evento()
	if not e.is_empty():
		eventos.append(e)
	viu[tr.estado] = true
	if fase == "reta":
		if n > 25:
			contatos_max = maxi(contatos_max, car.contatos)
		if n == 75:
			print("  carro andando reto 1.5 s: casco encostou %d vezes, estados %s, total %d" % [contatos_max, viu.keys(), tr.total])
			if contatos_max > 0 or tr.total != 0 or tr.combo_ativo:
				_falha("andando reto não é truque")
			_por(g + frente * 5.0, frente, 4.0, frente * 15.0)
			tr = _novo()
			viu = {}
			eventos = []
			fase = "pulo"
			n = 0
	elif fase == "pulo":
		if n == 150:
			var air := eventos.filter(func(x): return x.tipo == Truques.FECHOU and x.nome == "AirTime")
			print("  caiu de 4 m: estados %s, AirTime %s, total %d" % [viu.keys(), air, tr.total])
			if not viu.has(6) or air.is_empty() or tr.total <= 0:
				_falha("pulo vira AirTime")
			# derrapando: 20 m/s com o bico 35° pra fora, volante todo e acelerador
			var bico := frente.rotated(Vector3.UP, deg_to_rad(35.0))
			_por(g + frente * 10.0, bico, 0.5, frente * 20.0)
			car.test_input = {"thr": 1.0, "brk": 0.0, "steer": -1.0}
			tr = _novo()
			viu = {}
			eventos = []
			fase = "derrapa"
			n = 0
	elif fase == "derrapa":
		if n == 75:
			var vivos := eventos.filter(func(x): return x.nome == "Slide")
			print("  derrapando 1.5 s: estados %s, %d eventos de Slide, combo %d total %d" % [
				viu.keys(), vivos.size(), tr.combo, tr.total])
			if not (viu.has(4) or viu.has(5)) or vivos.is_empty():
				_falha("derrapagem vira Slide")
			print("teste_truques: ", "ok" if falhas == 0 else "%d falhas" % falhas)
			quit(1 if falhas else 0)
	return false


func _por(p: Vector3, frente: Vector3, altura: float, vel: Vector3) -> void:
	var y: float = terrain.height_at(p.x, p.z) + altura
	car.global_transform = Transform3D(Basis.looking_at(-frente, Vector3.UP), Vector3(p.x, y, p.z))
	car.reset_physics_interpolation()
	car.linear_velocity = vel
	car.angular_velocity = Vector3.ZERO
