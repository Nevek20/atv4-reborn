extends SceneTree
## Modo corrida (pista/corrida.gd): carrega o main, começa a corrida, espera a
## contagem e leva o carro pelo traçado da IA (teleporte a cada quadro, 6 m
## por passo) por 5 voltas. Confere: freio preso na contagem, volta 0 até
## cruzar a linha, 5 voltas contadas, chegada; e que ir e voltar pela linha
## (atalho) não conta volta.
## Uso: godot --headless --path . -s res://tests/teste_corrida.gd

var main
var c
var fase := 0
var quadros := 0
var s := 0.0                    # distância andada no traçado (m)
var falhas := 0
var pontos: Array = []          # o traçado como polilinha (mundo)
var comp := 0.0


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _falha(m: String) -> void:
	falhas += 1
	print("FALHA: ", m)


func _ponto(dist: float) -> Vector3:
	dist = fposmod(dist, comp)
	var acc := 0.0
	for i in pontos.size():
		var a: Vector3 = pontos[i]
		var b: Vector3 = pontos[(i + 1) % pontos.size()]
		var l := Vector2(b.x - a.x, b.z - a.z).length()
		if acc + l >= dist:
			return a.lerp(b, (dist - acc) / l)
		acc += l
	return pontos[0]


func _por(car, p: Vector3, para_frente: Vector3) -> void:
	var y: float = main.terrain.height_at(p.x, p.z) + 1.0
	car.global_position = Vector3(p.x, y, p.z)
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.rotation = Vector3(0, atan2(para_frente.x, para_frente.z), 0)


func _physics_process(_dt: float) -> bool:
	quadros += 1
	if main.car == null or main.corrida == null:
		if quadros > 300:
			print("teste_corrida: FALHA (sem corrida: falta data/rx01_corrida.json?)")
			return true
		return false
	c = main.corrida
	var car = main.car
	match fase:
		0:
			if quadros < 20:
				return false
			pontos = c.links
			for i in pontos.size():
				var a: Vector3 = pontos[i]
				var b: Vector3 = pontos[(i + 1) % pontos.size()]
				comp += Vector2(b.x - a.x, b.z - a.z).length()
			c.comecar()
			fase = 1
			quadros = 0
		1:
			if c.estado == c.CONTANDO:
				if car.test_input == null or car.test_input.brk < 1.0:
					_falha("contagem sem o freio preso")
				return false
			print("contagem: %.2f s (esperado %.1f)" % [quadros / 50.0, c.CONTAGEM])
			# começa no link mais perto do grid e anda pra frente
			var p0: Vector3 = car.global_position
			var melhor := INF
			var acc := 0.0
			for i in pontos.size():
				var a: Vector3 = pontos[i]
				var d := Vector2(a.x - p0.x, a.z - p0.z).length()
				if d < melhor:
					melhor = d
					s = acc
				var b: Vector3 = pontos[(i + 1) % pontos.size()]
				acc += Vector2(b.x - a.x, b.z - a.z).length()
			if c.volta != 0:
				_falha("volta %d antes de cruzar a linha" % c.volta)
			fase = 2
		2:
			s += 6.0
			var p := _ponto(s)
			_por(car, p, _ponto(s + 3.0) - p)
			if c.estado == c.CHEGOU:
				print("chegada: %d voltas, %s total, melhor %s, tempos %s" % [c.tempos.size(), c.relogio(c.t), c.relogio(c.melhor), c.tempos.map(func(x): return snappedf(x, 0.01))])
				if c.tempos.size() != c.voltas:
					_falha("%d voltas contadas (esperado %d)" % [c.tempos.size(), c.voltas])
				fase = 3
				quadros = 0
			elif quadros > 50 * 60 * 3:
				_falha("não chegou (volta %d, estado %d)" % [c.volta, c.estado])
				fase = 9
		3:
			# atalho: começa de novo e passa pela linha indo e voltando
			c.comecar()
			fase = 4
		4:
			if c.estado == c.CONTANDO:
				quadros = 0
				return false
			# 12 quadros: antes, depois, antes (de ré)... 4 vezes
			var d: Vector3 = c._cp_frente
			var base: Vector3 = c._cp_pos
			var q := quadros % 3
			_por(car, base + d * (3.0 if q == 1 else -3.0), d if q < 2 else -d)
			if quadros >= 12:
				print("atalho: volta %d, %d tempos" % [c.volta, c.tempos.size()])
				if c.tempos.size() != 0:
					_falha("ir e voltar pela linha contou volta")
				fase = 9
		9:
			c.parar()
			print("teste_corrida: %s" % ("ok" if falhas == 0 else "FALHA"))
			return true
	return false
