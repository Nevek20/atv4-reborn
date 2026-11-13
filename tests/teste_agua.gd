extends SceneTree
## Água do RX01 (porta: 0x201c20, 0x1bb098, 0x20e5e8, 0x2242d0, 0x225108,
## 0x370548), com os save states do Matheus na poça (nov/2026):
##  1. Renegade parado na pose do Renegade_dentro_da_agua.p2s: as 4 rodas
##     dentro da água, profundidade de cada roda x RAM (veículo+0xaec);
##  2. a lama da roda vai pro registro da água (alfa cai rápido: taxa 30);
##  3. passando a 60 km/h: espirro (nuvens de água), arrasto da água pequeno
##     (o Matheus: "acho que não desacelera") e som "Water";
##  4. fora da poça nada disso.
## Uso: godot --headless --path . -s res://tests/teste_agua.gd

const Car := preload("res://carro/car.gd")
const Main := preload("res://main.gd")
const Terrain := preload("res://pista/terrain.gd")
const Objetos := preload("res://pista/objetos_rx01.gd")

# Renegade_dentro_da_agua.p2s: origem do modelo, frente, profundidade das rodas
const ORIGEM := Vector3(760.8506, 206.0475, 1584.0409)
const FRENTE := Vector3(-0.1269, 0.0796, 0.9887)
## na ordem do veículo do jogo (veículo+0xaec: FL, RL, FR, RR); no car.gd
## a ordem é FL, FR, RL, RR (ORDEM_RAM leva uma na outra)
const PROF_RAM := [0.123, 0.280, 0.029, 0.262]
const ORDEM_RAM := [0, 2, 1, 3]

var terrain
var objetos
var car = null
var falhas := 0
var fase := 0
var t := 0.0
var medidas := {}


func _initialize() -> void:
	terrain = Terrain.new()
	root.add_child(terrain)
	objetos = Objetos.new()
	root.add_child(objetos)


func _checa(ok: bool, txt: String) -> void:
	print(("ok      " if ok else "FALHOU  ") + txt)
	if not ok:
		falhas += 1


func _novo(p_jogo: Vector3, frente_jogo: Vector3, vel: float) -> void:
	if car:
		car.queue_free()
	car = Car.new()
	Main.configurar(car, Main.frota()[0])
	car.terrain = terrain
	car.objetos = objetos
	car.suspension = false
	root.add_child(car)
	var p: Vector3 = Terrain.do_jogo(p_jogo)
	var f: Vector3 = Terrain.dir_do_jogo(frente_jogo)
	f.y = 0.0
	f = f.normalized()
	p.y = terrain.height_at(p.x, p.z) + 0.6
	car.reset_to(p, atan2(f.x, f.z))
	car.linear_velocity = f * vel
	t = 0.0


func _physics_process(dt: float) -> bool:
	if fase == 0:
		if not objetos.is_inside_tree():
			return false
		if not objetos.montar() or objetos.aguas.is_empty():
			print("teste_agua: FALHA (sem assets/pista/rx01 ou sem a WATER_puddle01: rode tools/rx01_objetos.py)")
			return true
		var a: Dictionary = objetos.aguas[0]
		print("  água: superfície %.3f (RAM 206.017), meia-largura %.2f x %.2f (RAM 21.01 x 19.88)" % [
			a.y, a.hx, a.hz])
		_checa(absf(a.y - 206.017) < 0.01 and absf(a.hx - 21.01) < 0.02 and absf(a.hz - 19.88) < 0.02,
			"caixa da água = objeto da RAM")
		_novo(ORIGEM, FRENTE, 0.0)
		car.test_input = {"thr": 0.0, "brk": 0.0, "steer": 0.0}
		# roda suja antes de entrar
		car.roda_cor = Color(0.6, 0.51, 0.4, 0.6)
		car.roda_mat = 3
		fase = 1
		return false
	if fase == 1:
		t += dt
		if t < 3.0:
			return false
		var txt := ""
		var erro := 0.0
		for i in 4:
			var r: float = car.agua_prof[ORDEM_RAM[i]]
			txt += " %.3f/%.3f" % [r, PROF_RAM[i]]
			erro = maxf(erro, absf(r - PROF_RAM[i]))
		print("  profundidade remake/RAM por roda (FL RL FR RR):" + txt)
		_checa(erro < 0.06, "profundidade roda a roda até %.1f cm da RAM (pose aproximada: só posição e direção)" % (erro * 100.0))
		_checa(car.agua != null, "parado na poça: dentro da água")
		var media := 0.0
		for i in 4:
			media += car.agua_prof[i]
		media /= 4.0
		_checa(absf(media - 0.1735) < 0.06, "profundidade média %.3f (RAM 0.174)" % media)
		print("  lama da roda: alfa %.3f (começou 0.6; RAM: alvo alfa 0, taxa 30)" % car.roda_cor.a)
		_checa(car.roda_mat == -2 and car.roda_taxa_alvo == 30.0, "lama da roda vai pro registro da água")
		# passa a 60 km/h pela poça, de fora pra dentro
		var dirj := FRENTE
		_novo(ORIGEM - dirj * 30.0, dirj, 60.0 / 3.6)
		car.test_input = {"thr": 0.35, "brk": 0.0, "steer": 0.0}
		medidas = {"agua_max": 0, "espirro": 0, "drag_max": 0.0, "som": false}
		fase = 2
		return false
	if fase == 2:
		t += dt
		if car.agua != null:
			medidas.agua_max += 1
			var spd: float = car.linear_velocity.length()
			var seco: float = (car.P.air_drag * 0.65 + car.amort_medio * car.P.ground_drag * 10.0) * spd * spd
			medidas.drag_max = maxf(medidas.drag_max, car._arrasto(spd, dt) - minf(seco, car.mass * spd / dt))
		if car.poeira:
			var aguas: PackedByteArray = car.poeira.agua_vivas()
			for k in aguas.size():
				if aguas[k] == 1:
					medidas.espirro += 1
					break
		if car.sfx:
			for o in car.sfx.rodas:
				if o.mat == -3:
					medidas.som = true
		if t < 4.0:
			return false
		print("  passando a ~60 km/h: %d passos na água, arrasto extra máx %.0f N, espirro em %d passos, som Water %s" % [
			medidas.agua_max, medidas.drag_max, medidas.espirro, medidas.som])
		_checa(medidas.agua_max > 20, "passou pela água")
		_checa(medidas.drag_max > 0.0 and medidas.drag_max < 400.0, "arrasto da água pequeno (< 400 N)")
		_checa(car.poeira == null or medidas.espirro > 0, "espirro de água" + ("" if car.poeira else " (sem assets/efeitos: pulado)"))
		_checa(car.sfx == null or medidas.som, "som Water" + ("" if car.sfx else " (sem assets/sons: pulado)"))
		print("teste_agua: %s" % ("ok" if falhas == 0 else "%d falhas" % falhas))
		return true
	return false
