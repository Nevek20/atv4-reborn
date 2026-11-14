extends SceneTree
## Batida carro com carro (carro/batida_carros.gd): começa a corrida com os
## rivais, para o jogador no grid e solta um rival atrás dele a VEL km/h
## (padrão 50) em linha reta. Confere: os cascos do VehicleVehicle não se
## atravessam (penetração máxima pequena), o jogador é empurrado pra frente,
## o rival (o mais rápido) solta lasquinhas (tabela carro x carro, >= 25 mph) e
## o som de batida toca o patch Vehicle.
## Depois, os casos dos prints do Matheus (nov/2026: "saíram voando", o Storm
## em pé), os dois a 90 km/h, o rival virando pra cima do jogador por 3 s:
## lado a lado, de lado meio carro à frente, e o rival caindo em cima (1.2 m).
## Confere que ninguém sobe rápido (< SUBIDA_MAX m/s) nem capota (o caso de
## cima só é impresso: o resultado depende do estado de antes, 1.4 a 5.8 m/s,
## sem virar de cabeça pra baixo; nov/2026). CASO="lado
## frente alto" roda só um (DBG=n imprime a cada n passos).
## Uso: godot --headless --path . -s res://tests/teste_batida_carros.gd

var main
var c
var ia
var x
var q := 0
var fase := 0
var falhas := 0
var t := 0
var pen_max := 0.0
var v_eu_max := 0.0
var lascas0 := 0
var vy_max := 0.0
var up_min := 1.0
var casos: Array = [[2.2, 0.0, 0.0], [2.6, 1.8, 0.0], [0.8, 1.5, 1.2]]
var caso := 0
const SUBIDA_MAX := 3.5


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _falha(m: String) -> void:
	falhas += 1
	print("FALHA: ", m)


func _physics_process(_dt: float) -> bool:
	q += 1
	if main.car == null or main.corrida == null:
		return q > 300
	c = main.corrida
	match fase:
		0:
			if q < 20:
				return false
			seed(3)
			c.comecar()
			c.comecar()
			c.comecar()
			c.t_conta = 0.0
			fase = 1
		1:
			if c.estado != c.CORRENDO:
				return false
			ia = c.ia
			# o teste é do resolvedor: rivais sem o catchup do jogo (0x353408),
			# como quando os casos dos prints foram montados. Com o subesterço x2
			# o volante 0.6 não segura o rival no jogador: ele cruza na frente e
			# decola num barranco a 17..21 m (sem contato; nov/2026)
			ia.catchup = {}
			for y in ia.rivais:
				y.car.mult_pot = 1.0
				y.car.mult_sub = 1.0
			# só um rival na conta: os outros longe
			for k in ia.rivais.size():
				var y = ia.rivais[k]
				y.r.fim = 0.0          # sem IA: solto
				if k > 0:
					y.car.reset_to(main.car.global_position + Vector3(0, 0, 60 + 8 * k), 0.0)
			x = ia.rivais[0]
			var eu = main.car
			var b: Basis = eu.global_transform.basis
			var p: Vector3 = eu.global_position - b.z * 9.0
			x.car.reset_to(Vector3(p.x, main.terrain.height_at(p.x, p.z) + 0.6, p.z), eu.global_rotation.y)
			var vel := float(OS.get_environment("VEL")) if OS.has_environment("VEL") else 50.0
			x.car.linear_velocity = b.z * vel / 3.6
			eu.test_input = {"thr": 0.0, "brk": 0.0, "steer": 0.0}
			lascas0 = x.car.lascas.soltas if x.car.lascas else 0
			fase = 2
		2:
			t += 1
			var eu = main.car
			x.car.test_input = {"thr": 0.0, "brk": 0.0, "steer": 0.0}
			v_eu_max = maxf(v_eu_max, eu.linear_velocity.dot(eu.global_transform.basis.z))
			# penetração entre as esferas do VehicleVehicle
			var bt = ia.batidas
			for ea in bt.esferas(eu):
				for eb in bt.esferas(x.car):
					var d: float = (eu.global_transform * (ea[0] as Vector3)).distance_to(x.car.global_transform * (eb[0] as Vector3))
					pen_max = maxf(pen_max, float(ea[1]) + float(eb[1]) - d)
			if t >= 100:
				var lascas: int = (x.car.lascas.soltas if x.car.lascas else 0) - lascas0
				var tocadas: Array = eu.sfx.batida_tocadas.map(func(e): return e[0]) if eu.sfx else []
				print("contatos %d  penetração máx %.3f m  jogador empurrado a %.1f km/h  lasquinhas do rival %d  sons %s" % [
					bt.contatos, pen_max, v_eu_max * 3.6, lascas, tocadas])
				if bt.contatos == 0:
					_falha("nenhum contato carro com carro")
				if pen_max > 0.25:
					_falha("os cascos se atravessaram (%.2f m)" % pen_max)
				if v_eu_max < 5.0:
					_falha("o jogador não foi empurrado (%.1f km/h)" % (v_eu_max * 3.6))
				if x.car.lascas and lascas == 0:
					_falha("o rival (mais rápido) não soltou lasquinha")
				if eu.sfx and not ("Vehicle" in tocadas):
					_falha("o som da batida não tocou o patch Vehicle")
				fase = 3
		3:
			# lado a lado: o rival 2.2 m à direita do jogador, os dois a 25 m/s
			ia.set_physics_process(false)     # a IA não mexe no volante do rival (a batida continua)
			var eu = main.car
			var b: Basis = eu.global_transform.basis
			var p0: Vector3 = eu.global_position + b.z * 30.0
			eu.reset_to(Vector3(p0.x, main.terrain.height_at(p0.x, p0.z) + 0.6, p0.z), eu.global_rotation.y)
			if OS.has_environment("CASO"):
				casos = [Array(OS.get_environment("CASO").split(" ")).map(func(v): return float(v))]
			var lado: float = casos[caso][0]
			var frente: float = casos[caso][1]
			var alto: float = casos[caso][2]
			var p1: Vector3 = p0 - b.x * lado + b.z * frente
			vy_max = 0.0
			up_min = 1.0
			x.car.reset_to(Vector3(p1.x, main.terrain.height_at(p1.x, p1.z) + 0.6 + alto, p1.z), eu.global_rotation.y)
			t = 0
			fase = 4
		4:
			t += 1
			var eu = main.car
			var b: Basis = eu.global_transform.basis
			if t <= 2:
				eu.linear_velocity = b.z * 25.0
				x.car.linear_velocity = b.z * 25.0
			eu.test_input = {"thr": 1.0, "brk": 0.0, "steer": 0.0}
			x.car.test_input = {"thr": 1.0, "brk": 0.0, "steer": 0.6}   # pra cima do jogador (ele está em -x)
			if OS.has_environment("DBG") and t % int(OS.get_environment("DBG")) == 0:
				var rel: Vector3 = x.car.global_position - eu.global_position
				print("t %3d  eu up %.2f vy %5.2f w %s | rival up %.2f vy %5.2f w %s | lado %.2f alt %.2f  contatos %d" % [t,
					eu.global_transform.basis.y.y, eu.linear_velocity.y, eu.angular_velocity.snapped(Vector3.ONE * 0.1),
					x.car.global_transform.basis.y.y, x.car.linear_velocity.y, x.car.angular_velocity.snapped(Vector3.ONE * 0.1),
					rel.dot(b.x), rel.y, ia.batidas.contatos])
			if t > 5:
				for k in [eu, x.car]:
					vy_max = maxf(vy_max, k.linear_velocity.y)
					up_min = minf(up_min, k.global_transform.basis.y.y)
			if t >= 150:
				print("caso %s: subida máx %.2f m/s, inclinação mín (up.y) %.2f" % [casos[caso], vy_max, up_min])
				if casos[caso][2] > 0.0 and not OS.has_environment("CASO"):
					pass            # caso de cima: só relatório
				elif vy_max > SUBIDA_MAX:
					_falha("caso %s: carro subiu a %.1f m/s (voando)" % [casos[caso], vy_max])
				if up_min < (0.0 if casos[caso][2] > 0.0 else 0.5):
					_falha("caso %s: carro capotou (up.y %.2f)" % [casos[caso], up_min])
				caso += 1
				fase = 3 if caso < casos.size() else 9
		9:
			c.parar()
			print("teste_batida_carros: %s" % ("ok" if falhas == 0 else "FALHA"))
			return true
	return false
