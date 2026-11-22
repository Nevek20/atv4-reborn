extends SceneTree
## Diagnóstico do Score dos rivais (pista/truques.gd): corre VOLTAS voltas (2
## por padrão, como o placar_final.p2s) com os 7 rivais e o jogador pilotado
## pela IA e conta, por rival, os truques fechados (Slide / AirTime), os pontos
## de cada um, os combos bancados, o tempo no ar e derrapando, e onde (prog na
## rota) cada AirTime aconteceu. Compara com a RAM do jogo (re/truques_ram.py).
## CU=s fixa o catchup dos rivais em s (o placar_final tem 0.04..0.32 na sua
## chegada); SEMENTE=n sorteia outros pilotos/carros; VOLTAS=n.
## Uso: godot --headless --path . --fixed-fps 50 -s res://tests/medir_truques_ia.gd

var main
var c
var ia
var fase := 0
var q := 0
var eu := {}
var med := {}


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _novo() -> Dictionary:
	return {"ant": 8, "t_est": 0.0, "slides": [], "airs": [], "bancos": [], "total_ant": 0,
		"t_ar": 0.0, "t_slide": 0.0, "voos": [], "voo": 0.0, "beta_max": 0.0, "v_ar": []}


func _medir(x: Dictionary, m: Dictionary, dt: float) -> void:
	var tr = x.truques
	var car = x.car
	if not tr.ligado:
		return
	var est: int = tr.estado
	if est != m.ant:
		if m.ant in [4, 5, 6] and m.t_est > 0.0:
			var lista: Array = m.airs if m.ant == 6 else m.slides
			lista.append([snappedf(m.t_est, 0.01), int(tr.combo), int(x.r.prog) % int(ia.comp)])
		m.t_est = 0.0
	if est in [4, 5, 6]:
		m.t_est += dt
	m.ant = est
	if est == 6:
		m.t_ar += dt
	if est == 4 or est == 5:
		m.t_slide += dt
	if int(car.grounded) == 0:
		if m.voo == 0.0:
			m.v_ar.append(snappedf(car.linear_velocity.length(), 0.1))
		m.voo += dt
	elif m.voo > 0.0:
		if m.voo >= 0.3:
			m.voos.append([snappedf(m.voo, 0.01), int(x.r.prog) % int(ia.comp)])
		m.voo = 0.0
	if tr.total != m.total_ant:
		m.bancos.append(tr.total - m.total_ant)
		m.total_ant = tr.total


func _physics_process(dt: float) -> bool:
	q += 1
	if main.car == null or main.corrida == null:
		return q > 300
	c = main.corrida
	match fase:
		0:
			if q < 20:
				return false
			seed(int(OS.get_environment("SEMENTE")) if OS.has_environment("SEMENTE") else 7)
			c.comecar()
			c.comecar()
			ia = c.ia
			eu = {"nome": "Você", "car": main.car, "r": ia.jogador, "desvio": 0.0, "desvio0": ia._lateral(main.car.global_position, ia.jogador.prog + ia.s_linha) - ia.lat_zero(ia.jogador.prog + ia.s_linha), "prog0": ia.jogador.prog, "skill": 1.0, "preso": 0.0,
				"re": 0.0, "capotado": 0.0, "repostos": 0, "res": 0}
			for x in ia.rivais:
				med[x.nome] = _novo()
			# CU=s: catchup fixo em s (+ bônus da Skill) pra todos os rivais
			if OS.has_environment("CU"):
				ia.catchup.DefaultScale = float(OS.get_environment("CU"))
				ia.catchup.AIinfrontThreshold = 1e9
				ia.catchup.AIbehindThreshold = 1e9
			fase = 1
			q = 0
		1:
			if c.estado == c.CONTANDO:
				return false
			eu.r = ia.jogador
			eu.vigia = ia.vigia_jogador
			ia._dirigir(eu, main.car, dt)
			for x in ia.rivais:
				_medir(x, med[x.nome], dt)
				med[x.nome].cu = med[x.nome].get("cu", 0.0) + float(x.get("cu", 0.0)) * dt
				med[x.nome].t = med[x.nome].get("t", 0.0) + dt
			var voltas := int(OS.get_environment("VOLTAS")) if OS.has_environment("VOLTAS") else 2
			var todos: bool = ia.rivais.all(func(x): return x.r.prog >= voltas * ia.comp)
			if todos or c.t > 100.0 * voltas:
				for x in ia.rivais:
					var m: Dictionary = med[x.nome]
					print("%-9s %-10s Score %5d (%4.0f/min)  bancos %d (maior %d)  slides %d (%.1f s)  airtime %d (%.1f s)  voos>=0.3s %d  catchup médio %.2f" % [
						x.nome, x.carro, x.truques.total, x.truques.total / m.t * 60.0, m.bancos.size(), (m.bancos.max() if m.bancos.size() else 0),
						m.slides.size(), m.t_slide, m.airs.size(), m.t_ar, m.voos.size(), m.cu / m.t])
					print("    slides (s, combo, prog): %s" % [m.slides.slice(0, 14)])
					print("    airtime (s, combo, prog): %s" % [m.airs])
					print("    voos (s, prog): %s" % [m.voos])
					print("    bancos: %s" % [m.bancos])
				fase = 9
		9:
			c.parar()
			return true
	return false
