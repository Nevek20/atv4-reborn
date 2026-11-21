extends SceneTree
## Modo corrida (pista/corrida.gd): carrega o main, começa a corrida, espera a
## contagem e leva o carro pelo traçado da IA (teleporte a cada quadro, 6 m
## por passo) por 5 voltas. Confere: introdução, carro preso na espera com
## acelerador e freio (o motor sobe, não anda, não engata a ré), sai pra
## frente no VAI, volta 0 até
## cruzar a linha, 5 voltas contadas (cruzando a linha 10 m fora do centro,
## além da caixa do checkpoint), chegada; e que ir e voltar pela linha
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
var p_largada := Vector3.INF
var t_intro := 0
var rpm_max := 0.0
var andou := 0.0
var fase_vai := 0
var cam_ant := Vector3.INF      # câmera da introdução no passo anterior
var passo_min := INF            # metros por passo da câmera (35 m/s = 0.7)
var passo_max := 0.0
var mudo := true                # carro calado na introdução


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
			# espera (introdução + contagem): acelerador E freio no fundo
			if c.estado == c.INTRO or c.estado == c.CONTANDO:
				if p_largada == Vector3.INF and t_intro >= 50:
					p_largada = car.global_position     # depois de assentar (larga 1.5 m acima)
				car.test_input = {"thr": 1.0, "brk": 1.0, "steer": 0.0}
				if c.estado == c.INTRO:
					t_intro += 1
					var pc: Vector3 = c._no_arco(c._arco_cam, c._intro_s)
					if cam_ant != Vector3.INF and c._intro_s < c._intro_comp:
						passo_min = minf(passo_min, pc.distance_to(cam_ant))
						passo_max = maxf(passo_max, pc.distance_to(cam_ant))
					cam_ant = pc
					if t_intro > 2 and not car.longe_som:
						mudo = false
				rpm_max = maxf(rpm_max, car.rpm)
				if p_largada != Vector3.INF:
					var dd: Vector3 = car.global_position - p_largada
					andou = maxf(andou, Vector2(dd.x, dd.z).length())
				if not car.largada_presa:
					_falha("espera sem o carro preso")
				return false
			if fase_vai < 100:
				# VAI: só acelerador por 2 s, tem que sair pra frente
				car.test_input = {"thr": 1.0, "brk": 0.0, "steer": 0.0}
				fase_vai += 1
				return false
			var vf: float = car.linear_velocity.dot(car.global_transform.basis.z)
			print("introdução %.1f s; na espera rpm até %.0f, andou %.2f m; 2 s depois do VAI: %.1f km/h pra frente, marcha %s" % [
				t_intro / 50.0, rpm_max, andou, vf * 3.6, car.gear_label()])
			print("câmera da introdução: %.3f a %.3f m por passo (35 m/s = 0.700); carro calado: %s; som depois: %s" % [
				passo_min, passo_max, mudo, not car.longe_som])
			if passo_min < 0.68 or passo_max > 0.72:
				_falha("câmera da introdução muda de velocidade")
			if not mudo or car.longe_som:
				_falha("som do carro na introdução")
			if t_intro < 50 * 10:
				_falha("introdução curta (%.1f s)" % (t_intro / 50.0))
			if andou > 0.5:
				_falha("o carro andou %.2f m na espera" % andou)
			if rpm_max < 3000.0:
				_falha("não deu pra acelerar na espera (rpm %.0f)" % rpm_max)
			if vf < 3.0:
				_falha("não saiu pra frente no VAI (%.1f km/h)" % (vf * 3.6))
			car.test_input = null
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
			# perto da linha passa 10 m pro lado do centro: fora da caixa de
			# 15.8 m do checkpoint, dentro da pista (24.8 m): tem que contar
			# (bug do Matheus, nov/2026: passando aberto a volta não contava)
			var fr := _ponto(s + 3.0) - p
			if p.distance_to(c._cp_pos) < 25.0:
				p += Vector3(fr.z, 0.0, -fr.x).normalized() * 10.0
			_por(car, p, fr)
			if c.estado == c.CHEGOU:
				print("chegada: %d voltas, %s total, melhor %s, tempos %s" % [c.tempos.size(), c.relogio(c.t), c.relogio(c.melhor), c.tempos.map(func(x): return snappedf(x, 0.01))])
				if c.tempos.size() != c.voltas:
					_falha("%d voltas contadas (esperado %d)" % [c.tempos.size(), c.voltas])
				fase = 5 if main.resultados else 3
				quadros = 0
			elif quadros > 50 * 60 * 3:
				_falha("não chegou (volta %d, estado %d)" % [c.volta, c.estado])
				fase = 9
		5:
			# tela de resultados (menu/resultados.gd): entra na chegada, vazia;
			# aos 3 s mostra quem chegou (aqui só o jogador: anda 300 m/s e os
			# rivais ficam longe); a IA pilota o carro do jogador; sem o texto
			# provisório de chegada
			var r = main.resultados
			if c.hud.text != "":
				_falha("texto provisório na chegada: '%s'" % c.hud.text.left(30))
			if quadros == 3 and (not r.visible or not r.linhas.is_empty()):
				_falha("a tela não entrou vazia na chegada (visível %s, %d linhas)" % [r.visible, r.linhas.size()])
			if quadros == 50 * 4:
				print("resultados aos 4 s: %d linha(s)" % r.linhas.size())
				if r.linhas.size() < 1 or not r.linhas[0].jogador:
					_falha("tela de resultados aos 4 s")
			if quadros < 50 * 18:
				return false
			# 15 s depois da chegada o evento fecha (0x15fae8): quem falta
			# entra com o tempo projetado; a tabela mostra os 8
			var v: float = car.linear_velocity.length()
			var tempos: Array = r.linhas.map(func(l): return l.total)
			var ordem := true
			for k in range(1, tempos.size()):
				ordem = ordem and tempos[k] >= tempos[k - 1]
			print("resultados aos 18 s: na tela %s, %d linhas, jogador em %s, tempos %s; IA pilotando a %.1f km/h" % [
				r.visible, r.linhas.size(), r.linhas.filter(func(l): return l.jogador).map(func(l): return l.pos),
				tempos.map(func(x): return snappedf(x, 0.01)), v * 3.6])
			if not r.visible or r.linhas.size() != 8 or not r.linhas[0].jogador or not ordem:
				_falha("tela de resultados (os 8 depois do fim do evento)")
			if v < 3.0:
				_falha("depois da chegada a IA não pilotou o carro")
			main._continuar_resultados()
			if r.visible or c.estado != c.LIVRE:
				_falha("Continue não voltou pro treino livre")
			fase = 3
		3:
			# atalho: começa de novo e passa pela linha indo e voltando
			c.comecar()
			fase = 4
		4:
			if c.estado == c.INTRO:
				c.comecar()             # Enter pula a introdução (e a descida)
				print("pulou a introdução: estado %d, descida %.1f s" % [c.estado, c.t_desce])
				if c.estado != c.CONTANDO or c.t_desce > 0.0:
					_falha("pular a introdução tem que pular a descida")
				return false
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
