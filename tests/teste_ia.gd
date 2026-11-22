extends SceneTree
## Rivais da IA (pista/ia.gd): começa a corrida, pula a introdução e deixa
## os 7 rivais (e o jogador, pilotado pela mesma IA) correrem VOLTAS_TESTE
## voltas. Confere: todos completam, sem ficar presos/repostos demais, tempo
## de volta perto da volta gravada do AIT (1810 m a ~28 m/s = ~64 s).
## Uso: godot --headless --path . --fixed-fps 50 -s res://tests/teste_ia.gd
## (VOLTAS=n muda as voltas; 1 por padrão; SEMENTE=n sorteia outros pilotos/carros)

var main
var c
var ia
var fase := 0
var q := 0
var falhas := 0
var eu := {}
var t_max := 0.0


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _falha(m: String) -> void:
	falhas += 1
	print("FALHA: ", m)


func _physics_process(dt: float) -> bool:
	q += 1
	if main.car == null or main.corrida == null:
		if q > 300:
			print("teste_ia: FALHA (sem corrida)")
			return true
		return false
	c = main.corrida
	match fase:
		0:
			if q < 20:
				return false
			seed(int(OS.get_environment("SEMENTE")) if OS.has_environment("SEMENTE") else 7)
			c.comecar()
			c.comecar()          # pula a introdução
			ia = c.ia
			if ia == null or ia.rivais.size() != 7:
				_falha("rivais: %d" % (0 if ia == null else ia.rivais.size()))
				fase = 9
				return false
			# carro só do jogador (Sphinx speedrun, NOSSO) não vai pros rivais
			var so: Array = main.VEHICLES.filter(func(v): return v.get("so_jogador", false)).map(func(v): return v.name)
			for x in ia.rivais:
				if x.carro in so:
					_falha("rival %s com o carro só do jogador %s" % [x.nome, x.carro])
			eu = {"nome": "Você", "car": main.car, "r": ia.jogador, "desvio": 0.0, "desvio0": ia._lateral(main.car.global_position, ia.jogador.prog + ia.s_linha) - ia.lat_zero(ia.jogador.prog + ia.s_linha), "prog0": ia.jogador.prog, "skill": 1.0, "preso": 0.0,
				"re": 0.0, "capotado": 0.0, "repostos": 0, "res": 0}
			fase = 1
			q = 0
		1:
			if c.estado == c.CONTANDO:
				return false
			eu.r = ia.jogador
			eu.vigia = ia.vigia_jogador     # a reposição do jogo do jogador (pista/reposicao.gd)
			ia._dirigir(eu, main.car, dt)
			var voltas := int(OS.get_environment("VOLTAS")) if OS.has_environment("VOLTAS") else 1
			var todos: bool = ia.rivais.all(func(x): return x.r.prog >= voltas * ia.comp)
			if OS.has_environment("DBG") and q % 25 == 0:
				for x in ia.rivais:
					var v: float = x.car.linear_velocity.length()
					var alvo: float = x.get("v_alvo", 0.0)
					if v < alvo * 0.6:
						print("  lento %-9s prog %5.0f  v %4.1f  alvo %4.1f  dist linha %4.1f  up %.2f  thr %s" % [x.nome, x.r.prog, v, alvo, x.r.dist, x.car.global_transform.basis.y.y, x.car.test_input])
			if q % 500 == 0:
				var linha: String = "%5.1f s  pos %d  " % [c.t, ia.posicao_jogador()]
				for x in ia.rivais:
					linha += "%.0f " % (x.r.prog)
				print(linha)
			if todos or c.t > 100.0 * voltas:
				var piores := 0
				for x in ia.rivais:
					var t5: Array = x.get("t5", [0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
					print("%-10s skill %.2f  %-10s  andou %6.0f m  %4.1f km/h média  repostos %d  ré %d  ultrapassar %d (s nas fases 0-4: %.0f %.0f %.0f %.0f %.0f)  cortes de curva %d" % [
						x.nome, x.skill, x.carro, x.r.prog, (x.r.prog + 54.8) / c.t * 3.6, x.repostos, x.res,
						x.get("n5", 0), t5[0], t5[1], t5[2], t5[3], t5[4], x.get("cortes", 0)])
					if x.r.prog < voltas * ia.comp:
						_falha("%s não completou %d volta(s) em %.0f s" % [x.nome, voltas, c.t])
					if x.repostos > 2 * voltas:
						piores += 1
				if piores > 1:
					_falha("%d rivais repostos demais" % piores)
				# Score dos rivais (pista/truques.gd, um por rival como no jogo)
				var scores: Array = ia.rivais.map(func(x): return x.truques.total)
				print("Score dos rivais: %s" % [scores])
				if scores.max() <= 0:
					_falha("nenhum rival fez Score")
				# melhor volta de cada rival (tela de resultados)
				var melhores: Array = ia.rivais.map(func(x): return snappedf(x.melhor, 0.01))
				print("melhor volta dos rivais: %s" % [melhores])
				if melhores.min() <= 0.0:
					_falha("rival sem melhor volta")
				print("jogador (IA): andou %.0f m, repostos %d, ré %d; classificação %s" % [
					eu.r.prog, eu.repostos, eu.res, ia.classificacao().map(func(e): return e.nome)])
				fase = 9
		9:
			c.parar()
			print("teste_ia: %s" % ("ok" if falhas == 0 else "FALHA"))
			return true
	return false
