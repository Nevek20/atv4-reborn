extends Node
## Rivais da corrida (pista/corrida.gd cria e chama). Nov/2026, 1ª versão.
##
## Do jogo (tools/rx01_corrida.py e tools/ia_dados.py):
##  - Linha e velocidade: o AIT do RX01 é uma volta gravada ("ExportedTrack"):
##    cada link tem o ponto por onde o carro passou (+0x00, até 12 m fora do
##    centro da pista) e a velocidade dele ali (+0x24, 25..34 m/s).
##  - Pilotos: Setup/AIPlayers.xml (nome, Skill, classes; Rivalry POTENTIAL).
##  - Catchup: o evento Rallycross usa o perfil STDH_04 no Normal
##    (Setup/Ai/ctchup_RALLYCROSS.xml + CatchupDatabase.xml): distância pro
##    jogador (m) -> escala, de DefaultScale até AIinfrontMaxScale (na frente)
##    ou AIbehindMaxScale (atrás), crescendo ao longo do Interval.
##
## NOSSO (o "piloto" da IA no exe não foi achado; docs/historico.md, Corrida):
##  - direção por perseguição de ponto (o ponto da linha OLHA_MIN + v x OLHA_T
##    à frente), acelerador/freio pela velocidade gravada x Skill x catchup;
##  - como a escala do catchup e a Skill mexem na velocidade (GANHO_*);
##  - preso: dá ré; capotado ou longe da linha: volta pra linha (o jogo tem
##    cInstantRespotBox no RX01, não portado);
##  - escolha dos 7 pilotos e dos carros (sorteio entre os da classe).
## Os rivais não tocam som (o som do jogo/nosso não é posicional ainda).

const ARQ := "res://data/ia.json"
const N_RIVAIS := 7
const OLHA_MIN := 7.0            # m
const OLHA_T := 0.55             # s
const GANHO_VIRA := 2.2          # direção = ângulo do alvo (rad) x isso
const GANHO_SKILL := 0.25        # velocidade x (1 - GANHO_SKILL x (1 - skill))
const GANHO_CATCHUP := 0.12      # velocidade x (1 + escala x isso)
const PRESO_T := 2.0             # s parado correndo -> ré
const RE_T := 1.5
const LONGE := 18.0              # m da linha por 1 s -> volta pra linha
const CAPOTADO_T := 2.0
const JUNTA := 150.0             # m: o desvio do grid vai sumindo até a linha

var main
var corrida
var dados := {}
var linha: Array = []            # pontos da linha (mundo), na ordem da corrida
var vel: Array = []              # m/s da volta gravada em cada ponto
var acc: Array = []              # distância acumulada até cada ponto (m, plano)
var comp := 0.0
var s_linha := 0.0               # onde a linha de chegada cai na linha da IA
var rivais: Array = []           # {car, nome, skill, numero, r (rastreio), ...}
var jogador := {}                # rastreio do jogador
var catchup := {}


func montar(c) -> bool:
	corrida = c
	main = c.main
	if not FileAccess.file_exists(ARQ):
		return false
	dados = JSON.parse_string(FileAccess.get_file_as_string(ARQ))
	var ls: Array = c.dados.links.duplicate()
	if c.sentido < 0:
		ls.reverse()
	for l in ls:
		linha.append(c.mundo(l.p))
		vel.append(float(l.get("vel", 25.0)))
	comp = 0.0
	for i in linha.size():
		acc.append(comp)
		comp += _plano(linha[(i + 1) % linha.size()] - linha[i]).length()
	s_linha = _projetar(c._cp_pos)[0]
	var ev: Dictionary = dados.eventos.get("RALLYCROSS", {})
	catchup = dados.catchup.get(ev.get("NORMAL", "STDH_04"), {})
	return true


static func _plano(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## (s, distância) do ponto mais perto da linha (busca na volta toda)
func _projetar(p: Vector3) -> Array:
	var best := INF
	var best_s := 0.0
	var n := linha.size()
	for i in n:
		var a: Vector3 = linha[i]
		var ab := _plano(linha[(i + 1) % n] - a)
		var t := clampf(_plano(p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		var d := _plano(p - (a + ab * t)).length()
		if d < best:
			best = d
			best_s = acc[i] + t * ab.length()
	return [best_s, best]


## ponto da linha a s metros (s em qualquer volta)
func ponto(s: float) -> Vector3:
	s = fposmod(s, comp)
	var i := _seg(s)
	var a: Vector3 = linha[i]
	var b: Vector3 = linha[(i + 1) % linha.size()]
	var l := _plano(b - a).length()
	return a.lerp(b, (s - acc[i]) / maxf(l, 1e-6))


func velocidade(s: float) -> float:
	s = fposmod(s, comp)
	var i := _seg(s)
	var l: float = (acc[i + 1] if i + 1 < acc.size() else comp) - acc[i]
	return lerpf(vel[i], vel[(i + 1) % vel.size()], (s - acc[i]) / maxf(l, 1e-6))


func _seg(s: float) -> int:
	var lo := 0
	var hi := acc.size() - 1
	while lo < hi:
		var m := (lo + hi + 1) / 2
		if acc[m] <= s:
			lo = m
		else:
			hi = m - 1
	return lo


## rastreio: distância de corrida desde a linha de chegada (negativa antes da
## 1ª passagem), andando só pros vizinhos (não pula pra outro trecho)
func novo_rastreio(p: Vector3) -> Dictionary:
	var s: float = _projetar(p)[0]
	var prog := s - s_linha
	prog -= comp * roundf(prog / comp)          # perto da linha: -comp/2..comp/2
	return {"prog": prog, "dist": 0.0, "fim": -1.0}


func rastrear(r: Dictionary, p: Vector3) -> void:
	# procura perto do s atual (±60 m), sem pular de trecho
	var s0: float = r.prog + s_linha
	var best := INF
	var best_d := 0.0
	var d := -60.0
	while d <= 60.0:
		var q := ponto(s0 + d)
		var e := _plano(p - q).length()
		if e < best:
			best = e
			best_d = d
		d += 1.0
	r.prog = r.prog + best_d
	r.dist = best


## escala do catchup pela distância de corrida até o jogador (+ = na frente)
func escala_catchup(frente: float, andado: float) -> float:
	if catchup.is_empty():
		return 0.0
	var e: float = catchup.DefaultScale
	if andado < catchup.StartDelay:
		return e
	if frente > catchup.AIinfrontThreshold:
		var f := clampf((frente - catchup.AIinfrontThreshold) / catchup.AIinfrontInterval, 0.0, 1.0)
		return lerpf(e, catchup.AIinfrontMaxScale, f)
	if -frente > catchup.AIbehindThreshold:
		var f := clampf((-frente - catchup.AIbehindThreshold) / catchup.AIbehindInterval, 0.0, 1.0)
		return lerpf(e, catchup.AIbehindMaxScale, f)
	return e


## 7 rivais nas posições 2..8 do grid, da classe do carro do jogador
func criar() -> void:
	limpar()
	var truck: bool = main.car.vehicle_id.begins_with("TRUCK")
	var classe := "Truck" if truck else "Buggy"
	var frota: Array = (main.TRUCKS if truck else main.VEHICLES).filter(
		func(v): return v.id != main.car.vehicle_id)
	var pilotos: Array = dados.pilotos.filter(
		func(p): return p.rivalry == "POTENTIAL" and classe in p.classes)
	pilotos.shuffle()
	frota.shuffle()
	var n := mini(N_RIVAIS, mini(pilotos.size(), corrida.dados.grid.size() - 1))
	for k in n:
		var v: Dictionary = frota[k % frota.size()]
		var c = main.Car.new()
		main.configurar(c, v)
		c.mudo = true
		c.desligadas = c.desligadas + ["painel"]
		c.terrain = main.terrain
		c.objetos = main.objetos
		c.name = "Rival%d" % (k + 1)
		main.add_child(c)
		var pl: Dictionary = pilotos[k]
		if main.objetos:
			main.objetos.rivais.append(c)
		rivais.append({"car": c, "nome": pl.nome, "skill": float(pl.skill), "numero": int(pl.numero),
			"carro": v.name, "r": {}, "preso": 0.0, "re": 0.0, "longe": 0.0, "capotado": 0.0,
			"desvio": (k % 3 - 1) * 1.5, "repostos": 0, "res": 0, "desvio0": 0.0, "prog0": 0.0})
	posicionar()


func posicionar() -> void:
	for k in rivais.size():
		var x: Dictionary = rivais[k]
		var l: Array = corrida.largada(k + 1)
		var p: Vector3 = l[0]
		x.car.reset_to(Vector3(p.x, main.terrain.height_at(p.x, p.z) + 1.5, p.z), l[1])
		x.car.objetos = main.objetos        # o recomeço monta os objetos de novo
		if main.objetos and not main.objetos.rivais.has(x.car):
			main.objetos.rivais.append(x.car)
		x.car.limpar_sujeira()
		x.car.largada_presa = true
		x.car.test_input = {"thr": 0.0, "brk": 0.0, "steer": 0.0}
		x.r = novo_rastreio(p)
		x.desvio0 = _lateral(p, x.r.prog + s_linha)
		x.prog0 = x.r.prog
		x.preso = 0.0
		x.re = 0.0
		x.longe = 0.0
		x.capotado = 0.0
	jogador = novo_rastreio(main.car.global_position)


func limpar() -> void:
	for x in rivais:
		if is_instance_valid(x.car):
			x.car.queue_free()
	rivais.clear()
	if main and main.objetos:
		main.objetos.rivais.clear()


func soltar() -> void:
	for x in rivais:
		x.car.largada_presa = false


func _physics_process(dt: float) -> void:
	if rivais.is_empty() or main.car == null:
		return
	rastrear(jogador, main.car.global_position)
	var est: int = corrida.estado
	for x in rivais:
		var car = x.car
		rastrear(x.r, car.global_position)
		if est == corrida.INTRO or est == corrida.CONTANDO:
			# na contagem: acelera no último segundo (preso, o motor sobe)
			var thr := 1.0 if est == corrida.CONTANDO and corrida.t_conta < 1.0 else 0.0
			car.test_input = {"thr": thr, "brk": 0.0, "steer": 0.0}
			continue
		if x.r.fim < 0.0 and x.r.prog >= corrida.voltas * comp:
			x.r.fim = corrida.t
		if x.r.fim >= 0.0:
			car.test_input = {"thr": 0.0, "brk": 0.0, "steer": _direcao(x, car)}
			continue
		_dirigir(x, car, dt)


func _direcao(x: Dictionary, car) -> float:
	var v: float = car.linear_velocity.length()
	var s: float = x.r.prog + s_linha + OLHA_MIN + v * OLHA_T
	var alvo := ponto(s)
	var adiante := _plano(ponto(s + 2.0) - alvo).normalized()
	var f := clampf((x.r.prog - x.get("prog0", 0.0)) / JUNTA, 0.0, 1.0)
	alvo += Vector3(adiante.z, 0.0, -adiante.x) * lerpf(x.get("desvio0", 0.0), x.desvio, f)
	var loc: Vector3 = car.global_transform.affine_inverse() * alvo
	return clampf(atan2(loc.x, loc.z) * GANHO_VIRA, -1.0, 1.0)


func _dirigir(x: Dictionary, car, dt: float) -> void:
	var b: Basis = car.global_transform.basis
	var vf: float = car.linear_velocity.dot(b.z)
	var v: float = car.linear_velocity.length()
	var st := _direcao(x, car)
	# velocidade da volta gravada um pouco à frente x Skill x catchup
	var frente: float = x.r.prog - jogador.prog
	var esc: float = escala_catchup(frente, jogador.prog + corrida.dados.get("primeira_volta", 54.8))
	var alvo: float = velocidade(x.r.prog + s_linha + v * 0.4) * (1.0 - GANHO_SKILL * (1.0 - x.skill)) \
		* (1.0 + GANHO_CATCHUP * esc)
	var thr := 0.0
	var brk := 0.0
	if v < alvo - 1.0:
		thr = 1.0
	elif v < alvo + 0.5:
		thr = 0.4
	elif v > alvo + 3.0 and vf > 5.0:
		brk = clampf((v - alvo - 3.0) / 6.0, 0.3, 1.0)
	# derrapando (direção no batente e o carro girando pro outro lado): tira o
	# pé, a física do jogo não endireita sozinha (RecoveryTorqueCutting)
	var giro: float = car.angular_velocity.dot(b.y)
	if absf(st) > 0.8 and giro * st < -0.05:
		thr = 0.0
	elif absf(st) > 0.95:
		thr = minf(thr, 0.5)
	# preso: ré virando pro outro lado
	if x.re > 0.0:
		x.re -= dt
		car.test_input = {"thr": 0.0, "brk": 1.0, "steer": -st}
		return
	x.preso = x.preso + dt if absf(vf) < 1.0 else 0.0
	if x.preso > PRESO_T:
		x.preso = 0.0
		x.re = RE_T
		x.res += 1
		if OS.has_environment("IA_LOG"):
			print("IA ré %s em %.0f m (%.1f m da linha, t %.1f)" % [x.nome, x.r.prog, x.r.dist, corrida.t])
	# capotado ou longe da linha: volta pra linha
	x.capotado = x.capotado + dt if b.y.y < 0.3 else 0.0
	x.longe = x.longe + dt if x.r.dist > LONGE else 0.0
	if x.capotado > CAPOTADO_T or x.longe > 1.0:
		if OS.has_environment("IA_LOG"):
			print("IA repõe %s em %.0f m (%s, %.1f m da linha, t %.1f)" % [x.nome, x.r.prog,
				"capotado" if x.capotado > CAPOTADO_T else "longe", x.r.dist, corrida.t])
		_repor(x)
		return
	car.test_input = {"thr": thr, "brk": brk, "steer": st}
	if OS.get_environment("IA_TRACE") == x.nome and Engine.get_physics_frames() % 5 == 0:
		print("trace %5.2f  prog %5.0f  dist %4.1f  v %4.1f/%4.1f  st %5.2f thr %.1f brk %.1f  up %.2f  pos %s  linha %s  frente %s" % [
			corrida.t, x.r.prog, x.r.dist, v, alvo, st, thr, brk, b.y.y, car.global_position,
			ponto(x.r.prog + s_linha), b.z])


## distância com sinal da linha (+ = pro mesmo lado do desvio em _direcao)
func _lateral(p: Vector3, s: float) -> float:
	var q := ponto(s)
	var adiante := _plano(ponto(s + 2.0) - q).normalized()
	return _plano(p - q).dot(Vector3(adiante.z, 0.0, -adiante.x))


func _repor(x: Dictionary) -> void:
	var s: float = x.r.prog + s_linha
	# não põe em cima de outro carro: recua pela linha até ter 6 m livres
	for _k in 8:
		var livre := true
		for o in [main.car] + rivais.map(func(y): return y.car):
			if o != x.car and is_instance_valid(o) and _plano(o.global_position - ponto(s)).length() < 6.0:
				livre = false
		if livre:
			break
		s -= 8.0
	var p := ponto(s)
	var d := _plano(ponto(s + 3.0) - p)
	x.car.reset_to(Vector3(p.x, main.terrain.height_at(p.x, p.z) + 1.5, p.z), atan2(d.x, d.z))
	x.capotado = 0.0
	x.longe = 0.0
	x.preso = 0.0
	x.desvio0 = x.desvio
	x.repostos += 1


## colocação: quem chegou (pelo tempo) e depois pela distância de corrida
func classificacao() -> Array:
	var todos: Array = [{"nome": "Você", "prog": jogador.get("prog", -INF),
		"fim": corrida.t_fim if corrida.estado == corrida.CHEGOU else -1.0, "jogador": true}]
	for x in rivais:
		todos.append({"nome": x.nome, "prog": x.r.prog, "fim": x.r.fim, "jogador": false, "carro": x.carro})
	todos.sort_custom(func(a, b):
		if (a.fim >= 0.0) != (b.fim >= 0.0):
			return a.fim >= 0.0
		if a.fim >= 0.0:
			return a.fim < b.fim
		return a.prog > b.prog)
	return todos


func posicao_jogador() -> int:
	var cl := classificacao()
	for i in cl.size():
		if cl[i].jogador:
			return i + 1
	return 0
