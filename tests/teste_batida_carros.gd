extends SceneTree
## Batida carro com carro (carro/batida_carros.gd): começa a corrida com os
## rivais, para o jogador no grid e solta um rival atrás dele a VEL km/h
## (padrão 50) em linha reta. Confere: os cascos do VehicleVehicle não se
## atravessam (penetração máxima pequena), o jogador é empurrado pra frente,
## o rival (o mais rápido) solta lasquinhas (tabela carro x carro, >= 25 mph) e
## o som de batida toca o patch Vehicle.
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
				fase = 9
		9:
			c.parar()
			print("teste_batida_carros: %s" % ("ok" if falhas == 0 else "FALHA"))
			return true
	return false
