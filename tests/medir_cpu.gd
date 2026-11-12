extends SceneTree
## Onde vai o tempo de CPU na corrida (8 carros). Começa a corrida, pula a
## intro, deixa a IA pilotar o jogador também e mede SEGUNDOS de corrida:
## média e pior quadro do _process e do _physics_process do Godot, e o custo
## de cada parte desligando uma por vez (rivais parados, batida carro com
## carro, efeitos, som). Sem tela (headless): mede só a CPU dos scripts.
## Uso: godot --headless --path . --fixed-fps 50 -s res://tests/medir_cpu.gd

const SEGUNDOS := 8.0

var main
var c
var ia
var fase := 0
var q := 0
var eu := {}
var t := 0.0
var fis: Array = []
var proc: Array = []
var real: Array = []
var _us := 0
var etapa := 0
var etapas := ["tudo ligado", "sem batida carro-carro", "sem IA (rivais sem dirigir)", "sem _process dos carros (visual)", "sem o script de física dos carros"]
var resultado: Array = []


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _physics_process(dt: float) -> bool:
	q += 1
	if main.car == null or main.corrida == null:
		return q > 300
	c = main.corrida
	match fase:
		0:
			if q < 20:
				return false
			seed(7)
			c.comecar()
			c.comecar()
			c.comecar()
			c.t_conta = 0.0
			ia = c.ia
			eu = {"nome": "Você", "car": main.car, "r": ia.jogador, "desvio": 0.0, "desvio0": 0.0,
				"prog0": ia.jogador.prog, "skill": 1.0, "preso": 0.0, "re": 0.0, "capotado": 0.0,
				"repostos": 0, "res": 0}
			fase = 1
		1:
			if c.estado != c.CORRENDO:
				return false
			if t > 3.0:            # deixa a largada passar
				fis.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
				proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
				var agora := Time.get_ticks_usec()
				if _us > 0:
					real.append((agora - _us) / 1000.0)
				_us = agora
			eu.r = ia.jogador
			eu.vigia = ia.vigia_jogador
			if etapa != 2:
				ia._dirigir(eu, main.car, dt)
			t += dt
			if t >= 3.0 + SEGUNDOS:
				_fechar()
				etapa += 1
				if etapa >= etapas.size():
					for r in resultado:
						print(r)
					return true
				_ligar(etapa)
				t = 0.0
				fis.clear()
				proc.clear()
				real.clear()
				_us = 0
	return false


func _ligar(k: int) -> void:
	match k:
		1:
			ia.batidas.set_physics_process(false)
		2:
			ia.batidas.set_physics_process(true)
			ia.set_physics_process(false)
		3:
			ia.set_physics_process(true)
			for x in [main.car] + ia.rivais.map(func(y): return y.car):
				x.set_process(false)
		4:
			for x in [main.car] + ia.rivais.map(func(y): return y.car):
				x.set_physics_process(false)


func _fechar() -> void:
	var f := _stat(fis)
	var p := _stat(proc)
	var r := _stat(real)
	resultado.append("%-34s física %5.2f ms/passo (pior %5.2f)   process %5.2f ms/quadro (pior %5.2f)   quadro real %5.2f ms (pior %5.2f)" % [
		etapas[etapa], f[0], f[1], p[0], p[1], r[0], r[1]])


static func _stat(a: Array) -> Array:
	if a.is_empty():
		return [0.0, 0.0]
	var s := 0.0
	var m := 0.0
	for v in a:
		s += v
		m = maxf(m, v)
	return [s / a.size(), m]
