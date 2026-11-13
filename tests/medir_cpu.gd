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
var nos := {}
var procs: Array = []
var t_proc := {}
var t_nos := {}
var etapa := 0
var etapas := ["tudo ligado", "sem batida carro-carro", "sem IA (rivais sem dirigir)", "sem _process dos carros (visual)", "sem o script de física dos carros", "por nó (chamado na mão)", "_process por script (chamado na mão)", "objetos da pista sem colisão"]
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
			if t > 3.0 and t - dt <= 3.0:
				main.car.perf.clear()
			if t > 3.0:            # deixa a largada passar
				fis.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
				proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
				var agora := Time.get_ticks_usec()
				if _us > 0:
					real.append((agora - _us) / 1000.0)
				_us = agora
			if etapa == 5:
				for k in nos:
					if nos[k]:
						var t0 := Time.get_ticks_usec()
						nos[k]._physics_process(dt)
						t_nos[k] += Time.get_ticks_usec() - t0
			if etapa == 6:
				for n in procs:
					if is_instance_valid(n):
						var t0 := Time.get_ticks_usec()
						n._process(dt)
						var chave: String = n.get_script().resource_path.get_file()
						t_proc[chave] = t_proc.get(chave, 0) + Time.get_ticks_usec() - t0
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
		6:
			for nome in nos:
				if nos[nome]:
					nos[nome].set_physics_process(true)
			nos = {}
			var pilha: Array = [root]
			while not pilha.is_empty():
				var n: Node = pilha.pop_back()
				pilha.append_array(n.get_children())
				if n != self and n.get_script() and n.has_method("_process") and n.is_processing():
					procs.append(n)
					n.set_process(false)
		7:
			for n in procs:
				if is_instance_valid(n):
					n.set_process(true)
			procs.clear()
			var pilha: Array = [main.objetos] if main.objetos else []
			var desl := 0
			while not pilha.is_empty():
				var n: Node = pilha.pop_back()
				pilha.append_array(n.get_children())
				if n is CollisionObject3D and not (n is VehicleBody3D):
					(n as CollisionObject3D).collision_layer = 0
					(n as CollisionObject3D).collision_mask = 0
					desl += 1
			print("  objetos sem colisão: ", desl)
		5:
			main.car.perf.clear()
			for x in [main.car] + ia.rivais.map(func(y): return y.car):
				x.set_physics_process(true)
				x.set_process(true)
			nos = {"ia": ia, "batida carro-carro": ia.batidas, "objetos (cercas, fardos)": main.objetos, "corrida": c}
			for nome in nos:
				if nos[nome]:
					nos[nome].set_physics_process(false)
					t_nos[nome] = 0


func _fechar() -> void:
	if etapa == 0 and not main.car.perf.is_empty():
		var n: float = float(fis.size()) * (1 + ia.rivais.size())    # passos x carros
		var tot := 0.0
		for k in main.car.perf:
			tot += main.car.perf[k]
		for k in main.car.perf:
			resultado.append("  car.gd %-48s %6.3f ms por carro/passo" % [k, main.car.perf[k] / 1000.0 / n])
		resultado.append("  car.gd %-48s %6.3f ms por carro/passo" % ["TOTAL", tot / 1000.0 / n])
	var f := _stat(fis)
	var p := _stat(proc)
	var r := _stat(real)
	if etapa == 6:
		var nq: float = maxf(fis.size(), 1)
		var ks: Array = t_proc.keys()
		ks.sort_custom(func(x, y): return t_proc[x] > t_proc[y])
		for k in ks:
			resultado.append("  _process %-40s %6.3f ms por quadro" % [k, t_proc[k] / 1000.0 / nq])
	if etapa == 5:
		var n: float = maxf(fis.size(), 1)
		var scripts := 0.0
		for k in t_nos:
			resultado.append("  nó %-44s %6.3f ms por passo" % [k, t_nos[k] / 1000.0 / n])
			scripts += t_nos[k] / 1000.0 / n
		if not main.car.perf.is_empty():
			var carros := 0.0
			for k in main.car.perf:
				if not String(k).begins_with("q:"):
					carros += main.car.perf[k] / 1000.0 / n
			resultado.append("  %-47s %6.3f ms por passo" % ["car.gd física (8 carros)", carros])
			scripts += carros
			resultado.append("  %-47s %6.3f ms por passo" % ["MOTOR DO GODOT (física - scripts)", f[0] - scripts])
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
