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
##    à frente), em sétimos e direto (como na RAM: -6/7, -4/7, 2/7, 5/7; cru
##    = suavizado); acelerador cheio, alivia acima de ANG_ALIVIO e freia acima
##    de ANG_FREIO (na RAM, 6 de 7 rivais de acelerador cheio a 123..139 km/h,
##    1.15..1.40 x o +0x24 do AIT, que NÃO é a velocidade-alvo);
##  - como a escala do catchup e a Skill mexem na velocidade (GANHO_*);
##  - preso: dá ré; capotado ou longe da linha: volta pra linha (o jogo tem
##    cInstantRespotBox no RX01, não portado);
##  - escolha dos 7 pilotos e dos carros (sorteio entre os da classe);
##  - desvio: carro até OLHA_CARRO m à frente e mais lento -> vai pro lado
##    com mais espaço (dentro da pista: centro e larguras do AIT, MARGEM da
##    borda); sem espaço, acompanha a velocidade dele.

const ARQ := "res://data/ia.json"
const N_RIVAIS := 7
# save state com rivais (objeto do piloto, vtable 0x5ae0d0): o alvo (+0x30)
# fica 16.9..21.5 m à frente a 34..38 m/s (0.46..0.57 s) e a direção crua
# (+0xa8) = ângulo até o alvo / 20° nos 7 rivais (0.048..0.052 por grau)
const OLHA_MIN := 5.0            # m (NOSSO: a RAM só tem rivais rápidos)
const OLHA_T := 0.5              # s
const GANHO_VIRA := 2.8648       # 1 / 20° em rad
const GANHO_SKILL := 0.1         # velocidade x (1 - GANHO_SKILL x (1 - skill))
const GANHO_CATCHUP := 0.12      # acelerador máximo x (1 + escala x isso)
const ANG_ALIVIO := 0.30         # rad entre o nariz e o alvo: tira o pé
const ANG_FREIO := 0.60          # rad: freia (acima de V_FREIO)
const V_FREIO := 15.0            # m/s
const A_LAT := 14.0              # m/s²: curva à frente (a linha é cortada: a IA do jogo passa de 20 na linha)
const A_FRENA := 8.0             # m/s²: quanto dá pra frear até a curva
const PRESO_T := 2.0             # s parado correndo -> ré
const RE_T := 1.5
const LONGE := 18.0              # m da linha por 1 s -> volta pra linha
const CAPOTADO_T := 2.0
const JUNTA := 150.0             # m: o desvio do grid vai sumindo até a linha
const OLHA_CARRO := 25.0         # m: carro à frente que conta pro desvio
const LADO := 3.5                # m: distância lateral pra passar
const MARGEM := 2.5              # m da borda da pista
const DESVIO_MAX := 6.0          # m: o desvio não se afasta mais que isso da linha
const DESVIO_VEL := 4.0          # m/s: quão rápido muda de lado
# VehicleLOD.xml (Buggy_Generic/Truck_Generic, Vehicle_AI): o jogo troca o
# modelo dos rivais pela fração da tela (High 0.24, Mid 0.055, Low 0.0175).
# Os modelos 2K/1K/500 ainda não são gerados: NOSSO, cada peça some quando
# ela mesma cai abaixo do Low (quase nada some: as malhas são por material e
# pegam o carro todo). Sombra: uma cópia da carroceria (body_mi) juntada numa
# superfície só, só sombra (1 desenho em vez de 55); o jogo faz a sombra com
# um modelo próprio, Models_Shadow/Shadow_Buggy_NN (não portado)
const LOD_LOW := 0.0175
const LOD_TAN := 0.6             # tan(meio FOV vertical) da câmera de corrida, ~31°

var main
var corrida
var dados := {}
var linha: Array = []            # pontos da linha (mundo), na ordem da corrida
var vel: Array = []              # m/s da volta gravada em cada ponto
var acc: Array = []              # distância acumulada até cada ponto (m, plano)
var centro_lat: Array = []       # centro da pista em relação à linha (m, lateral)
var meia: Array = []             # meia largura da pista (m)
var comp := 0.0
var s_linha := 0.0               # onde a linha de chegada cai na linha da IA
var rivais: Array = []           # {car, nome, skill, numero, r (rastreio), ...}
var jogador := {}                # rastreio do jogador
var catchup := {}
var batidas                      # carro/batida_carros.gd


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
	for i in ls.size():
		centro_lat.append(_lateral(c.mundo(ls[i].centro), acc[i]))
		meia.append((absf(ls[i].largura[0]) + absf(ls[i].largura[1])) * 0.5)
	batidas = preload("res://carro/batida_carros.gd").new()
	batidas.name = "BatidaCarros"
	batidas.carros = func(): return [main.car] + rivais.map(func(y): return y.car)
	add_child(batidas)
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
		c.som_3d = true
		c.direcao_direta = true
		c.desligadas = c.desligadas + ["painel"] + (Array(OS.get_environment("IA_DESL").split(",")) if OS.has_environment("IA_DESL") else [])
		c.terrain = main.terrain
		c.objetos = main.objetos
		c.name = "Rival%d" % (k + 1)
		main.add_child(c)
		# carro com carro só pelas esferas do VehicleVehicle (batida_carros.gd)
		batidas.separar(c, main.car)
		for y in rivais:
			batidas.separar(c, y.car)
		var pl: Dictionary = pilotos[k]
		if main.objetos:
			main.objetos.rivais.append(c)
		rivais.append({"car": c, "nome": pl.nome, "skill": float(pl.skill), "numero": int(pl.numero),
			"carro": v.name, "r": {}, "preso": 0.0, "re": 0.0, "longe": 0.0, "capotado": 0.0,
			"desvio": (k - 3) * 1.6, "repostos": 0, "res": 0, "desvio0": 0.0, "prog0": 0.0, "lod": 0, "lat": 0.0})
	posicionar()


## LOD e sombra dos rivais (ver LOD_LOW)
func _lod(c: Node) -> void:
	var pilha: Array = [c]
	while not pilha.is_empty():
		var n: Node = pilha.pop_back()
		pilha.append_array(n.get_children())
		if not (n is GeometryInstance3D) or not (n is VisualInstance3D):
			continue
		var g := n as GeometryInstance3D
		var r: float = g.get_aabb().size.length() * 0.5 * absf((g as Node3D).global_transform.basis.get_scale().x)   # o espelho tem escala -1
		if r <= 0.0:
			continue
		g.visibility_range_end = r / (LOD_LOW * LOD_TAN)
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var body: MeshInstance3D = c.get("body_mi")
	if body and body.mesh:
		if body.has_node("SombraRival"):
			return
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in body.mesh.get_surface_count():
			st.append_from(body.mesh, i, Transform3D.IDENTITY)
		var sombra := MeshInstance3D.new()
		sombra.name = "SombraRival"
		sombra.mesh = st.commit()
		sombra.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		body.add_child(sombra)


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
		x.lat = x.desvio0
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
		# LOD/sombra depois que o carro montou tudo (rodas, piloto, motor vêm depois)
		if x.lod < 5:
			x.lod += 1
			if x.lod == 5:
				_lod(car)
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
	var s: float = x.r.prog + s_linha + maxf(OLHA_MIN, v * OLHA_T)
	var alvo := ponto(s)
	var adiante := _plano(ponto(s + 2.0) - alvo).normalized()
	alvo += Vector3(adiante.z, 0.0, -adiante.x) * x.get("lat", 0.0)
	var loc: Vector3 = car.global_transform.affine_inverse() * alvo
	x.ang = atan2(loc.x, loc.z)
	return roundf(clampf(x.ang * GANHO_VIRA, -1.0, 1.0) * 7.0) / 7.0   # sétimos (RAM)


func _dirigir(x: Dictionary, car, dt: float) -> void:
	var b: Basis = car.global_transform.basis
	var vf: float = car.linear_velocity.dot(b.z)
	var v: float = car.linear_velocity.length()
	var st := _direcao(x, car)
	# acelerador cheio; alivia/freia pelo ângulo até o alvo; Skill e catchup
	# limitam o acelerador máximo
	var frente: float = x.r.prog - jogador.prog
	var esc: float = escala_catchup(frente, jogador.prog + corrida.dados.get("primeira_volta", 54.8))
	var teto := clampf((1.0 - GANHO_SKILL * (1.0 - x.skill)) * (1.0 + GANHO_CATCHUP * esc), 0.3, 1.0)
	var v_lim: float = _desviar(x, car, dt, INF)
	var ang := absf(x.get("ang", 0.0))
	var thr := teto
	var brk := 0.0
	v_lim = minf(v_lim, _v_curva(x.r.prog + s_linha))
	if (ang > ANG_ALIVIO and v > V_FREIO) or v > v_lim + 1.0:
		thr = 0.0
	if (ang > ANG_FREIO and v > V_FREIO) or (v > v_lim + 4.0 and vf > 5.0):
		brk = 1.0
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
		# 3 rés sem andar 20 m: volta pra linha
		if x.r.prog - x.get("prog_re", -INF) < 20.0:
			x.n_re = x.get("n_re", 0) + 1
		else:
			x.n_re = 1
		x.prog_re = x.r.prog
		if x.n_re >= 3:
			x.n_re = 0
			x.re = 0.0
			if OS.has_environment("IA_LOG"):
				print("IA repõe %s em %.0f m (preso)" % [x.nome, x.r.prog])
			_repor(x)
			return
		if OS.has_environment("IA_LOG"):
			print("IA ré %s em %.0f m (%.1f m da linha, t %.1f)" % [x.nome, x.r.prog, x.r.dist, corrida.t])
	# vigia: menos de 15 m em 5 s correndo -> volta pra linha
	x.vigia_t = x.get("vigia_t", 0.0) + dt
	if x.vigia_t >= 5.0:
		var andou: float = x.r.prog - x.get("vigia_prog", x.r.prog)
		x.vigia_t = 0.0
		x.vigia_prog = x.r.prog
		if andou < 15.0 and x.has("vigia_ok"):
			if OS.has_environment("IA_LOG"):
				print("IA repõe %s em %.0f m (lento: %.0f m em 5 s)" % [x.nome, x.r.prog, andou])
			_repor(x)
			return
		x.vigia_ok = true
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
		var alvo := v_lim
		print("trace %5.2f  prog %5.0f  dist %4.1f  v %4.1f/%4.1f  st %5.2f thr %.1f brk %.1f  up %.2f  pos %s  linha %s  frente %s" % [
			corrida.t, x.r.prog, x.r.dist, v, alvo, st, thr, brk, b.y.y, car.global_position,
			ponto(x.r.prog + s_linha), b.z])


## velocidade máxima pelas curvas à frente: raio = 30 m / (quanto a linha
## vira em 30 m), v = sqrt(A_LAT x raio), mais o que dá pra frear até lá
func _v_curva(s: float) -> float:
	var v_max := INF
	var d := 5.0
	while d <= 65.0:
		var a := _plano(ponto(s + d + 3.0) - ponto(s + d)).normalized()
		var b := _plano(ponto(s + d + 33.0) - ponto(s + d + 30.0)).normalized()
		var vira := absf(a.signed_angle_to(b, Vector3.UP))
		if vira > 0.05:
			var vc := sqrt(A_LAT * 30.0 / vira)
			v_max = minf(v_max, sqrt(vc * vc + 2.0 * A_FRENA * d))
		d += 10.0
	return v_max


## desvio dos outros carros: muda x.lat (lado em relação à linha) e devolve a
## velocidade-alvo (limitada à do carro da frente se não der pra passar)
func _desviar(x: Dictionary, car, dt: float, alvo: float) -> float:
	var s: float = x.r.prog + s_linha
	var f := clampf((x.r.prog - x.get("prog0", 0.0)) / JUNTA, 0.0, 1.0)
	var base: float = lerpf(x.get("desvio0", 0.0), x.desvio, f)
	var i := _seg(fposmod(s, comp))
	var lo: float = maxf(centro_lat[i] - meia[i] + MARGEM, -DESVIO_MAX)
	var hi: float = minf(centro_lat[i] + meia[i] - MARGEM, DESVIO_MAX)
	var b: Basis = car.global_transform.basis
	var p: Vector3 = car.global_position
	var minha: float = car.linear_velocity.dot(b.z)
	var lat_alvo := base
	var v_lim := INF
	var perto := INF
	for o in [main.car] + rivais.map(func(y): return y.car):
		if o == car or not is_instance_valid(o):
			continue
		var rel: Vector3 = o.global_position - p
		var frente: float = rel.dot(b.z)
		var lado: float = rel.dot(b.x)
		var dele: float = o.linear_velocity.dot(b.z)
		if frente <= 0.0 or frente > OLHA_CARRO or absf(lado) > LADO or dele > minha - 0.5:
			continue
		if frente >= perto:
			continue
		perto = frente
		# o lado do outro em relação à linha; passa pelo lado com mais espaço
		var o_lat := _lateral(o.global_position, s + frente)
		var por_dentro := o_lat - LADO
		var por_fora := o_lat + LADO
		var cabe_dentro := por_dentro >= lo
		var cabe_fora := por_fora <= hi
		if cabe_dentro and (not cabe_fora or absf(por_dentro - x.lat) < absf(por_fora - x.lat)):
			lat_alvo = por_dentro
		elif cabe_fora:
			lat_alvo = por_fora
		elif frente < 10.0 and dele > 5.0:
			v_lim = dele          # sem espaço: atrás dele (parado não: desvia igual)
		else:
			lat_alvo = por_dentro if absf(por_dentro - x.lat) < absf(por_fora - x.lat) else por_fora
	x.lat = move_toward(x.get("lat", base), clampf(lat_alvo, lo, hi) if lo < hi else base, DESVIO_VEL * dt)
	return minf(alvo, v_lim)


## distância com sinal da linha (+ = pro mesmo lado do desvio em _direcao)
func _lateral(p: Vector3, s: float) -> float:
	var q := ponto(s)
	var adiante := _plano(ponto(s + 2.0) - q).normalized()
	return _plano(p - q).dot(Vector3(adiante.z, 0.0, -adiante.x))


func _repor(x: Dictionary) -> void:
	repor_em(x.car, x.r.prog + s_linha)
	x.capotado = 0.0
	x.longe = 0.0
	x.preso = 0.0
	x.desvio0 = x.desvio
	x.lat = x.desvio
	x.repostos += 1


## reposição na linha (todos os carros: rivais e o jogador nas caixas do
## jogo). Do TrackSetup (seção Respotting): o ponto tem que ter o chão plano
## (normal.y >= mUprightTolerance 0.93), sem água mais funda que
## mWaterDepthTolerance (0.01; na água, plano >= mWaterUprightTolerance) e
## ninguém a menos de mSafePlayerDistance (8 m). NOSSO: voltar pela linha de
## 4 em 4 m a partir de onde o carro está e cair de 1 m de altura
func repor_em(car: Node3D, s: float) -> void:
	var rp: Dictionary = corrida.dados.get("reposicao", {})
	var seguro: float = rp.get("mSafePlayerDistance", 8.0)
	var plano: float = rp.get("mUprightTolerance", 0.93)
	var plano_agua: float = rp.get("mWaterUprightTolerance", 0.99)
	var fundo: float = rp.get("mWaterDepthTolerance", 0.01)
	var outros: Array = [main.car] + rivais.map(func(y): return y.car)
	var escolhido := s
	for k in 40:
		var q := ponto(s - 4.0 * k)
		var y: float = main.terrain.height_at(q.x, q.z)
		var n: Vector3 = main.ground_normal(q.x, q.z)
		var ok := n.y >= plano
		if ok and main.objetos:
			var ag: Array = main.objetos.agua_em(Vector3(q.x, y, q.z), null)
			if ag[0] != null:
				ok = ag[1] <= fundo and n.y >= plano_agua
		if ok:
			for o in outros:
				if o != car and is_instance_valid(o) and _plano(o.global_position - q).length() < seguro:
					ok = false
		if ok:
			escolhido = s - 4.0 * k
			break
	var p := ponto(escolhido)
	var d := _plano(ponto(escolhido + 3.0) - p)
	car.reset_to(Vector3(p.x, main.terrain.height_at(p.x, p.z) + 1.0, p.z), atan2(d.x, d.z))


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
