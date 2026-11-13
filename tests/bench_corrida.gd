extends SceneTree
## Corrida fixa pra comparar CPU entre versões (tempo de CPU do processo:
## /usr/bin/time -f %U godot --headless --path . --fixed-fps 50 -s
## res://tests/bench_corrida.gd). Pula a intro, a IA pilota o jogador
## também, roda PASSOS passos (750 = 15 s) e sai. Mesma semente sempre.
var PASSOS: int = int(OS.get_environment("PASSOS")) if OS.has_environment("PASSOS") else 750
var main
var c
var ia
var q := 0
var n := 0
var eu := {}
var som_soma := 0.0      # soma de volume e tom das rodas de som e dos loops do motor (C++ x GDScript)


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _physics_process(dt: float) -> bool:
	q += 1
	if main.car == null or main.corrida == null:
		return q > 300
	c = main.corrida
	if q == 20:
		seed(7)
		c.comecar()
		c.comecar()
		c.comecar()
		c.t_conta = 0.0
		ia = c.ia
		eu = {"nome": "Você", "car": main.car, "r": ia.jogador, "desvio": 0.0, "desvio0": 0.0,
			"prog0": ia.jogador.prog, "skill": 1.0, "preso": 0.0, "re": 0.0, "capotado": 0.0,
			"repostos": 0, "res": 0}
	if q > 20 and c.estado == c.CORRENDO:
		eu.r = ia.jogador
		eu.vigia = ia.vigia_jogador
		ia._dirigir(eu, main.car, dt)
		n += 1
		for car in [main.car] + ia.rivais.map(func(y): return y.car):
			if car.sfx:
				for e in car.sfx.estado():
					som_soma += e[1] * 1.0001 + e[2] * 0.37
			if car.som:
				for e in car.som.tocando():
					som_soma += e[1] * 0.53 + e[2] * 1.7
		if n >= PASSOS:
			print("bench: %d passos, jogador em %.0f m, C++ %s" % [n, ia.jogador.prog, main.car.cpp != null])
			print("  som: soma %.12f" % som_soma)
			for car in [main.car] + ia.rivais.map(func(y): return y.car):
				# estado final (pra comparar ATV4_CPP=0 x 1: tem que sair igual)
				print("  %-10s pos %s  rpm %.6f  marcha %d" % [car.name, car.global_position, car.rpm, car.gear])
				if car.poeira:
					print("  poeira %-10s %-10s soltas %5d  vivas %4d  cap %d" % [car.name, car.poeira.conjunto, car.poeira.soltas, car.poeira.vivas(), car.poeira.cap])
			return true
	return false
