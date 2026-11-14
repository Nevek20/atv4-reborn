extends Node
## Rivais da corrida (pista/corrida.gd cria e chama). Nov/2026.
##
## Do jogo (tools/rx01_corrida.py e tools/ia_dados.py):
##  - Rota: o AIT do RX01 ("ExportedTrack"): cada link tem o ponto +0x00
##    (por onde um carro passou, até 12 m fora do centro), a LARGURA da pista
##    (+0x24) e o centro (+0x5c, no bloco extra). O progresso da corrida conta
##    pelos pontos (volta = 1810.4 m, igual ao jogo); a IA pilota pelo ZERO da
##    rota, que no jogo é o centro (0x32a8d0; lat_zero), dentro das bordas do
##    bloco extra (+0x68/+0x6c; DAT_0055155c = 1 durante a IA, 0x3525f8).
##  - Pilotos: Setup/AIPlayers.xml (nome, Skill, classes; Rivalry POTENTIAL).
##  - Catchup: o evento Rallycross usa o perfil STDH_04 no Normal
##    (Setup/Ai/ctchup_RALLYCROSS.xml + CatchupDatabase.xml).
##
## Do exe (nov/2026, docs/engenharia_reversa.md, Acelerador e freio da IA e
## Catchup; re/ia_alvo_ram.py confere com os save states com rivais):
##  - direção: ângulo até o zero da rota clamp(0.5 x |v|, 15, 50) m à frente
##    (mais o desvio próprio) / 20°, em sétimos e direto (cru = suavizado);
##  - acelerador e freio (0x34ed10): k = (v_alvo - v) x 0.2 preso em +-1 (k > 0
##    acelera, k < 0 freia), v no plano do chão e negativa de ré;
##  - v_alvo (0x359eb8): o menor de 2 arcos com o volante no batente
##    (_v_arco, 0x214328, o modelo de bicicleta do próprio carro): do CoM no
##    rumo do bico até o zero clamp(|v|, 15, 100) m à frente, e a curva do
##    zero depois do alvo da direção. Sem curva (menos de 4 m pro lado) = 446.5;
##  - catchup (0x34cea8): escala s de cada rival = DefaultScale + bônus da
##    Skill ((Skill - 0.5) x 0.4 acima de 0.5); com o rival da frente a 100 m
##    da linha, a distância do jogador pro carro logo à frente (logo atrás)
##    passando do Threshold leva todos os rivais da frente (de trás) até
##    AIinfrontMaxScale (AIbehindMaxScale) ao longo do Interval. s vira
##    multiplicador na física do rival (0x353408): potência x (1 + s) ou
##    / (1 - s), subesterço x (2 - 2s);
##  - Skill < 0.5 anda desviada do zero (0x360550): (0.5 - Skill) x 2 x
##    sorteio [0, 10) m, lado sorteado, no zero nos primeiros 5 s; sorteia de
##    novo toda vez que o #7 (corrida na linha) recomeça;
##  - cérebro (0x3668d0, pista/ia_ultrapassar.gd): percepção dos vizinhos e o
##    #5 ultrapassar (seguir colado, sair pro lado, passar, desviar de batida
##    prevista) no lugar do #7 enquanto roda;
##  - a lateral pedida fica dentro das bordas menos a meia largura do carro
##    (0x359730, objeto +0xf4);
##  - #2 preso (0x356e38 / 0x364640): parado a menos de 2 m da âncora
##    querendo andar por mais de 3 s, repõe (até nov/2026 era NOSSO: ré,
##    repor lento e capotado). Fora da pista e contramão: a regra do jogo,
##    pista/reposicao.gd, igual à do jogador.
##
## NOSSO (docs/historico.md, Corrida):
##  - os outros comportamentos do cérebro (#3, #4, #6), os modos 15 (x1.2) e
##    rota tipo 4 (x0.5), o limite da rota (-1 no RX01), a demora na largada
##    pela posição (0x352c98) e o corte de curva do 0x359730 (ponto da
##    direção que cruza a borda volta pra perto);
##  - escolha dos 7 pilotos e dos carros (sorteio entre os da classe).

const ARQ := "res://data/ia.json"
const Reposicao := preload("res://pista/reposicao.gd")
const SomJogo := preload("res://som/som_jogo.gd")
const VehicleData := preload("res://carro/vehicle_data.gd")
const Ultrapassar := preload("res://pista/ia_ultrapassar.gd")
const N_RIVAIS := 7
# save state com rivais (objeto do piloto, vtable 0x5ae0d0): o alvo (+0x30)
# fica 16.9..21.5 m à frente a 34..38 m/s (0.46..0.57 s) e a direção crua
# (+0xa8) = ângulo até o alvo / 20° nos 7 rivais (0.048..0.052 por grau)
# alvo da direção: clamp(v x OLHA_T, OLHA_MIN, OLHA_MAX) à frente (0x5ae6f0:
# 0.5, 15, 50; na RAM o alvo estava 16.9..21.5 m à frente a 34..38 m/s)
const OLHA_MIN := 15.0           # m
const OLHA_MAX := 50.0           # m
const OLHA_T := 0.5              # s
const GANHO_VIRA := 2.8648       # 1 / 20° em rad
# catchup (0x34cea8 / 0x3535f0): bônus da Skill e fator dos rivais atrás do
# jogador pela ordem (0x5ada80, linha 0 = a do gerente na RAM)
const BONUS_SKILL := 0.4         # (Skill - 0.5) x 2 x 0.2
# desvio dos pilotos fracos (0x360550 / 0x3603d0): (0.5 - Skill) x 2 x sorteio
# de 0 a 10 m, lado sorteado; nos primeiros 5 s do relógio fica no zero
const SKILL_DESVIO := 10.0
const SKILL_T := 5.0
const ESPERA_T := 2.0            # 0x364b08: o "esperar" solta a 2 s do Go! (save idle_antes_do_Go)
const FATOR_ATRAS := [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.0, 0.0]
# acelerador e freio do jogo (0x34ed10) e velocidade-alvo (0x359eb8 / 0x214328)
const GANHO_VEL := 0.2           # (v_alvo - v) x isso = acelerador (+) ou freio (-)
const V_SEM_LIMITE := 446.4975   # 0x43df3fae: sem curva à frente
const V_SEM_ARCO := 4.916389     # 0x35a040: arco impossível (11 mph)
const V_SEM_ARCO_LINHA := 8.938889   # 0x35a150: idem na curva da linha (20 mph)
const LAT_RETA := 4.0            # 0x5506c8: alvo a menos disso pro lado = reta
const OLHA_VEL := [1.0, 15.0, 100.0]  # 0x35a040: clamp(v x 1 s, 15, 100) m à frente
const MPH_G := 0.44694445
const DEG := 0.017453294
# só pro _v_curva antigo (NOSSO, fora do uso; teste_cpp compara o C++)
const A_LAT := 14.0
const A_FRENA := 8.0
# #2 preso (0x356e38 / 0x364640): a menos de 2 m (3D) da âncora querendo
# andar por mais de 3 s -> repõe (0x3646d0 -> 0x15bd28)
const PRESO_T := 3.0
const PRESO_R2 := 4.0            # m², 2 m
const DEG_10 := 0.17453295        # 0x359730: modo 1 mistura a lateral acima de 10° (0x3e32b8c4)
const COS_10 := 0.98480775
# CPU (nov/2026, tests/medir_cpu.gd): rival além disso da câmera não mexe
# braços do piloto nem suspensão visual; além do alcance do som 3D
# (SomJogo.MAX_3D) não calcula som de pneu. NOSSO, a física não muda
const VIS_PERTO := 50.0
const RASTREIO := 60.0           # m: o rastreio procura só nessa janela (não pula de trecho)
# VehicleLOD.xml (Buggy_Generic/Truck_Generic, Vehicle_AI): o jogo troca o
# modelo dos rivais pela fração da tela (High 0.24, Mid 0.055, Low 0.0175).
# Os modelos 2K/1K/500 ainda não são gerados: NOSSO, o carro inteiro some
# quando cai abaixo do Low (pelo tamanho da carroceria; todas as peças juntas). Sombra: uma cópia da carroceria (body_mi) juntada numa
# superfície só, só sombra (1 desenho em vez de 55); o jogo faz a sombra com
# um modelo próprio, Models_Shadow/Shadow_Buggy_NN (não portado)
const LOD_LOW := 0.0175
const LOD_TAN := 0.6             # tan(meio FOV vertical) da câmera de corrida, ~31°

var main
var corrida
var dados := {}
var linha: Array = []            # pontos da linha (mundo), na ordem da corrida
var b_lo: Array = []             # bordas da pista no link, m pro lado da linha (o sinal do
var b_hi: Array = []             # _lateral): as do bloco extra, as que a IA usa (0x3525f8)
var lat0: Array = []             # zero da IA (0x32a8d0: o centro +0x5c) pro lado da linha, m
var acc: Array = []              # distância acumulada até cada ponto (m, plano)
var esq: Array = []              # largura do AIT a partir do ponto da linha: esquerda (-) e
var dir: Array = []              # direita (+) (+0x68 / +0x6c), na ordem da corrida
var vigia_jogador                # pista/reposicao.gd do jogador
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
	comp = 0.0
	for i in linha.size():
		acc.append(comp)
		comp += _plano(linha[(i + 1) % linha.size()] - linha[i]).length()
	liga_cpp()
	s_linha = _projetar(c._cp_pos)[0]
	for i in ls.size():
		esq.append(float(ls[i].largura[0]))
		dir.append(float(ls[i].largura[1]))
		var z := _zero_jogo(ls[i])
		lat0.append(_lateral(c.mundo([z.x, z.y, z.z]), acc[i]))
		var bb: Array = _bordas_jogo(ls[i])
		var e1 := _lateral(c.mundo([bb[0].x, bb[0].y, bb[0].z]), acc[i])
		var e2 := _lateral(c.mundo([bb[1].x, bb[1].y, bb[1].z]), acc[i])
		b_lo.append(minf(e1, e2))
		b_hi.append(maxf(e1, e2))
	if _cpp:
		_cpp.bordas(esq, dir)
	batidas = preload("res://carro/batida_carros.gd").new()
	batidas.name = "BatidaCarros"
	batidas.carros = func(): return [main.car] + rivais.map(func(y): return y.car)
	add_child(batidas)
	var ev: Dictionary = dados.eventos.get("RALLYCROSS", {})
	catchup = dados.catchup.get(ev.get("NORMAL", "STDH_04"), {})
	return true


## contas da linha em C++ (fisica_cpp/src/linha_ia.cpp, as mesmas): null =
## GDScript. Segue o carro_base.usar_cpp (F3)
var _cpp: RefCounted = null


func liga_cpp() -> void:
	_cpp = null
	if preload("res://carro/carro_base.gd").usar_cpp and ClassDB.class_exists("LinhaIA") and not linha.is_empty():
		_cpp = ClassDB.instantiate("LinhaIA")
		if not _cpp.configurar(linha, acc, comp):
			_cpp = null
		elif not esq.is_empty():
			_cpp.bordas(esq, dir)


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
	if _cpp:
		return _cpp.ponto(s)
	s = fposmod(s, comp)
	var i := _seg(s)
	var a: Vector3 = linha[i]
	var b: Vector3 = linha[(i + 1) % linha.size()]
	var l := _plano(b - a).length()
	return a.lerp(b, (s - acc[i]) / maxf(l, 1e-6))


## bordas do link (coordenadas do jogo): o 0x3525f8 liga DAT_0055155c = 1
## enquanto roda os pilotos, então pra IA a borda é o ponto + eixo X do link
## (normal x direção, 0x32a338 / 0x32a418) x largura do bloco extra (+0x68
## esquerda, negativa / +0x6c direita); sem bloco, -+ largura (+0x24) / 2
static func _bordas_jogo(l: Dictionary) -> Array:
	var p := Vector3(l.p[0], l.p[1], l.p[2])
	var d := Vector3(l.dir[0], l.dir[1], l.dir[2])
	var nn: Array = l.get("n", [0.0, 1.0, 0.0])
	var x := Vector3(nn[0], nn[1], nn[2]).cross(d).normalized()
	if l.get("bloco", false):
		return [p + x * float(l.largura[0]), p + x * float(l.largura[1])]
	var w: float = l.get("largura_total", 30.0)
	return [p - x * (w * 0.5), p + x * (w * 0.5)]


## zero da IA no link (coordenadas do jogo): a fração |centro +0x5c - borda
## esquerda| / largura (0x32a8d0); sem bloco extra, no meio (o ponto).
## Conferido nos save states com rivais: o alvo da direção de 4 dos 7 fica a
## 0.0 m dessa linha (o resto tem desvio próprio)
static func _zero_jogo(l: Dictionary) -> Vector3:
	var p := Vector3(l.p[0], l.p[1], l.p[2])
	if not l.get("bloco", false):
		return p
	var bb: Array = _bordas_jogo(l)
	var borda: Vector3 = bb[0]
	var x: Vector3 = (bb[1] - bb[0]).normalized()
	return borda + x * (Vector3(l.centro[0], l.centro[1], l.centro[2]) - borda).length()


## zero da IA em s: m pro lado da linha (o sinal do _lateral), entre os links
func lat_zero(s: float) -> float:
	s = fposmod(s, comp)
	var i := _seg(s)
	var j := (i + 1) % linha.size()
	var l := _plano(linha[j] - linha[i]).length()
	return lerpf(lat0[i], lat0[j], (s - acc[i]) / maxf(l, 1e-6))


## ponto do zero da IA em s (o que o jogo chama de rota com desvio 0)
func ponto_zero(s: float) -> Vector3:
	var q := ponto(s)
	var adiante := _plano(ponto(s + 2.0) - q).normalized()
	return q + Vector3(adiante.z, 0.0, -adiante.x) * lat_zero(s)


## bordas da pista em s (m pro lado da linha), entre os links
func bordas(s: float) -> Vector2:
	s = fposmod(s, comp)
	var i := _seg(s)
	var j := (i + 1) % linha.size()
	var t: float = (s - acc[i]) / maxf(_plano(linha[j] - linha[i]).length(), 1e-6)
	return Vector2(lerpf(b_lo[i], b_lo[j], t), lerpf(b_hi[i], b_hi[j], t))


## zero da IA e bordas em s numa conta só (CPU: o cérebro pede os dois toda
## hora): x = lat_zero, y / z = as bordas (as nossas, da linha)
func zero_bordas(s: float) -> Vector3:
	s = fposmod(s, comp)
	var i := _seg(s)
	var j := (i + 1) % linha.size()
	var t: float = (s - acc[i]) / maxf(_plano(linha[j] - linha[i]).length(), 1e-6)
	return Vector3(lerpf(lat0[i], lat0[j], t), lerpf(b_lo[i], b_lo[j], t), lerpf(b_hi[i], b_hi[j], t))


## lateral do jogo em s: do zero da IA, com o sinal do jogo (o nosso mundo é
## espelhado, mundo = (z, y, x) do jogo: a do jogo = -(a nossa))
func lat_jogo(p: Vector3, s: float) -> float:
	return -(_lateral(p, s) - lat_zero(s))


## bordas em s na lateral do jogo (do zero): x = a menor (0x32a788, negativa),
## y = a maior (0x32a828)
func bordas_jogo(s: float) -> Vector2:
	var zb := zero_bordas(s)
	return Vector2(zb.x - zb.z, zb.x - zb.y)


## ponto da rota em s com a nossa lateral (do zero da IA)
func ponto_lat(s: float, lat: float) -> Vector3:
	var q := ponto(s)
	var adiante := _plano(ponto(s + 2.0) - q).normalized()
	return q + Vector3(adiante.z, 0.0, -adiante.x) * (lat_zero(s) + lat)


func _seg(s: float) -> int:
	if _cpp:
		return _cpp.seg(s)
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
	if _cpp:
		var res: PackedFloat64Array = _cpp.rastrear(r.prog, s_linha, p)
		r.prog = res[0]
		r.dist = res[1]
		return
	# procura perto do s atual (±60 m), sem pular de trecho: projeta nos
	# trechos da linha que caem na janela (até nov/2026 testava 121 pontos de
	# 1 em 1 m: 2.4 ms por passo com 8 carros, tests/medir_cpu.gd)
	var s0: float = r.prog + s_linha
	var lo := s0 - RASTREIO
	var hi := s0 + RASTREIO
	var n := linha.size()
	var lo_m := fposmod(lo, comp)
	var volta := lo - lo_m              # início da volta em que lo cai
	var i := _seg(lo_m)
	var best := INF
	var best_s := s0
	var s_ini: float = volta + acc[i]
	while s_ini <= hi:
		var a: Vector3 = linha[i]
		var ab := _plano(linha[(i + 1) % n] - a)
		var l := ab.length()
		var s := s_ini
		if l > 1e-6:
			s = clampf(s_ini + _plano(p - a).dot(ab) / l, maxf(s_ini, lo), minf(s_ini + l, hi))
		var e := _plano(p - (a + ab * ((s - s_ini) / maxf(l, 1e-6)))).length()
		if e < best:
			best = e
			best_s = s
		i += 1
		if i >= n:
			i = 0
			volta += comp
		s_ini = volta + acc[i]
	r.prog = r.prog + (best_s - s0)
	r.dist = best


## catchup do jogo (0x34cea8 + 0x34d0a0 + 0x34d250, perfil STDH_04): escala s
## de cada rival pela distância de corrida (desde a linha, a mesma do jogo
## na RAM: progresso +4) e aplicada na física (0x353408). Todo passo, como no
## jogo (o gerente roda a cada quadro e o rival aplica quando muda).
func _catchup() -> void:
	if catchup.is_empty():
		return
	# sua chegada põe os corredores no estado 4 (0x4ced48 -> 0x352790): o
	# catchup desliga e todo rival fica em s = 0, sem bônus (0x34cea8)
	if corrida.estado == corrida.CHEGOU:
		for x in rivais:
			x.cu = 0.0
			aplicar_catchup(x.car, 0.0)
		return
	var d0: float = catchup.DefaultScale
	for x in rivais:
		x.cu = d0 + x.bonus                   # 0x356880: s = escala + bônus
	# ordem da corrida (0x7f48d4+0x1c): pela distância, o jogador entre eles
	var ordem: Array = rivais.duplicate()
	ordem.sort_custom(func(a, b): return a.r.prog > b.r.prog)
	var dj: float = jogador.prog
	var pj := 0
	while pj < ordem.size() and ordem[pj].r.prog > dj:
		pj += 1
	# o rival da frente precisa ter passado do StartDelay
	if not ordem.is_empty() and ordem[0].r.prog >= catchup.StartDelay:
		# 0x34d0a0: jogador longe do carro logo à frente -> rivais da frente
		if pj > 0:
			var gap: float = ordem[pj - 1].r.prog - dj
			if gap > catchup.AIinfrontThreshold:
				var f := minf((gap - catchup.AIinfrontThreshold) / catchup.AIinfrontInterval, 1.0)
				var e: float = d0 + f * (catchup.AIinfrontMaxScale - d0)
				for x in rivais:
					if x.r.prog >= dj:
						x.cu = e + x.bonus
		# 0x34d250: carro logo atrás longe do jogador -> rivais de trás, pelo
		# fator da ordem (os 2 últimos de 8 atrás dele ficam em 0)
		if pj < ordem.size():
			var gap: float = dj - ordem[pj].r.prog
			if gap > catchup.AIbehindThreshold:
				var f := minf((gap - catchup.AIbehindThreshold) / catchup.AIbehindInterval, 1.0)
				var e: float = d0 + f * (catchup.AIbehindMaxScale - d0)
				for k in range(pj, ordem.size()):
					var x: Dictionary = ordem[k]
					if x.r.prog <= dj:
						x.cu = e * FATOR_ATRAS[mini(k - pj, FATOR_ATRAS.size() - 1)] + x.bonus
	for x in rivais:
		aplicar_catchup(x.car, x.cu)


## 0x353408: escala s -> corpo+0x720 (potência) e +0x724 (subesterço). O
## 0x356890 (s > 0.1 com a flag +0xc do catchup) dá 0 nos rivais (flag 0 nos
## 7 da RAM), então o subesterço usa s - 0.5: 1 - 2(s - 0.5)
static func aplicar_catchup(car, s: float) -> void:
	car.mult_pot = 1.0 + s if s >= 0.0 else 1.0 / (1.0 - s)
	var s2 := s - 0.5
	car.mult_sub = maxf(1.0 - (s2 + s2) if s2 <= 0.0 else 1.0 / (s2 * 0.25 + 1.0), 1e-5)


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
			"carro": v.name, "r": {}, "preso": 0.0,
			"desvio": desvio_skill(float(pl.skill)), "repostos": 0, "res": 0, "lod": 0, "lat": 0.0,
			"bonus": maxf(float(pl.skill) - 0.5, 0.0) * BONUS_SKILL, "cu": 0.0})
	posicionar()


## desvio próprio do piloto, do zero da IA (0x360550): Skill < 0.5 sorteia
## (0.5 - Skill) x 2 x [0, 10) m pra um lado sorteado; Skill >= 0.5 fica no
## zero (na RAM, 4 dos 5 rivais assim miravam a 0.0 m do centro). O jogo
## sorteia quando o comportamento de corrida começa; NOSSO: 1 vez por corrida
static func desvio_skill(skill: float) -> float:
	if skill >= 0.5:
		return 0.0
	var d := (0.5 - skill) * 2.0 * randf_range(0.0, SKILL_DESVIO)
	return -d if randf() < 0.5 else d


## LOD e sombra dos rivais (ver LOD_LOW)
func _lod(c: Node) -> void:
	# o carro inteiro some junto, pelo tamanho do maior pedaço (a carroceria):
	# até nov/2026 cada peça usava o próprio tamanho e a suspensão e as rodas
	# sumiam antes, sobrando a carroceria voando (prints do Matheus). O jogo
	# troca o modelo inteiro (2K/1K/500 têm rodas)
	var geos: Array = []
	var r_carro := 0.0
	var pilha: Array = [c]
	while not pilha.is_empty():
		var n: Node = pilha.pop_back()
		pilha.append_array(n.get_children())
		if not (n is GeometryInstance3D) or not (n is VisualInstance3D):
			continue
		# efeitos soltos no mundo (poeira, pedrinhas, lascas, espirro: MultiMesh
		# top_level na origem) não são peça do carro: no Forward+ a caixa deles
		# conta os espaços vazios da MultiMesh (zerados na origem do mundo), ia
		# da origem até a pista e o centro ficava em volta da distância de corte:
		# a terra dos rivais sumia (83% dos quadros) e piscava (Matheus, nov/2026)
		if n is MultiMeshInstance3D and (n as Node3D).top_level:
			continue
		var g := n as GeometryInstance3D
		geos.append(g)
		r_carro = maxf(r_carro, g.get_aabb().size.length() * 0.5 * absf((g as Node3D).global_transform.basis.get_scale().x))   # o espelho tem escala -1
	for g in geos:
		if r_carro > 0.0:
			g.visibility_range_end = r_carro / (LOD_LOW * LOD_TAN)
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
		x.lat = _lateral(p, x.r.prog + s_linha) - lat_zero(x.r.prog + s_linha)
		x.comp = 0
		x.viz = {}
		x.preso = 0.0
		x.erase("ancora")
		x.vigia = Reposicao.new(self, x.r.prog)
	jogador = novo_rastreio(main.car.global_position)
	vigia_jogador = Reposicao.new(self, jogador.prog)


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
	var cam := get_viewport().get_camera_3d()
	var olho: Vector3 = cam.global_position if cam else main.car.global_position
	for y in rivais:
		if is_instance_valid(y.car):
			var dc: float = y.car.global_position.distance_to(olho)
			y.car.longe_vis = dc > VIS_PERTO
			var longe: bool = dc > SomJogo.MAX_3D
			if longe and not y.car.longe_som:
				y.car.calar_som()          # saiu do alcance: para o som (religa ao voltar)
			y.car.longe_som = longe
	var est: int = corrida.estado
	if est == corrida.CORRENDO and vigia_jogador and vigia_jogador.passo(jogador, main.car, dt):
		repor_jogador()
	# o rastreio de todos antes da lista: ela leva os dados do passo de cada
	# carro (Ultrapassar.dados_carro), feitos 1 vez e lidos por quem olha
	for x in rivais:
		rastrear(x.r, x.car.global_position)
	_carros_laco = _monta_carros()
	_catchup()
	for x in rivais:
		var car = x.car
		# LOD/sombra depois que o carro montou tudo (rodas, piloto, motor vêm depois)
		if x.lod < 5:
			x.lod += 1
			if x.lod == 5:
				_lod(car)
		if est == corrida.INTRO or est == corrida.CONTANDO:
			# largada parada (relógio 0x17b118 no estado 6, corredor no estado 1):
			# o "esperar" (0x364b08 / 0x3649d0: alvo 0, pedais 0) segura o rival
			# enquanto faltam mais de ESPERA_T pro Go! (0x17aff0); depois o de
			# corrida pisa com o carro travado (lei 0x34ed10 parado = 1): o ronco.
			# Sai no Go! junto com todos (offline o 0x353750 deixa +0x150 = 0)
			var thr := 1.0 if est == corrida.CONTANDO and corrida.t_desce <= 0.0 \
				and corrida.t_conta <= ESPERA_T else 0.0
			car.test_input = {"thr": thr, "brk": 0.0, "steer": 0.0}
			continue
		if x.r.fim < 0.0 and x.r.prog >= corrida.voltas * comp:
			x.r.fim = corrida.t
		if x.r.fim >= 0.0:
			car.test_input = {"thr": 0.0, "brk": 0.0, "steer": _direcao(x, car)}
			continue
		if x.vigia.passo(x.r, car, dt):
			if OS.has_environment("IA_LOG"):
				print("IA repõe %s em %.0f m (regra do jogo, t %.1f)" % [x.nome, x.vigia.aceito, corrida.t])
			_repor(x)
			continue
		_dirigir(x, car, dt)
	_carros_laco = null


## xf_ / v_: o transform e |v| do carro já lidos no passo (_dirigir); sem
## eles, lê do carro (testes)
func _direcao(x: Dictionary, car, xf_ = null, v_ := -1.0) -> float:
	var v: float = v_ if v_ >= 0.0 else car.linear_velocity.length()
	var xf: Transform3D = xf_ if xf_ != null else car.global_transform
	# alcance do comportamento (0x359730: clamp(esc x v, mín, máx); o #7 e as
	# fases 0/3/4 do #5 usam 0.5, 15, 50)
	var o: Vector3 = x.get("olha", Ultrapassar.OLHA)
	var s: float = x.r.prog + s_linha + clampf(v * o.x, o.y, o.z)
	x.s_alvo = s
	var lat: float = lat_zero(s) + x.get("lat", 0.0)     # desvio conta do zero da IA
	if _cpp:
		x.ang = _cpp.direcao_ang(s, lat, xf)
	else:
		var alvo := ponto(s)
		var adiante := _plano(ponto(s + 2.0) - alvo).normalized()
		alvo += Vector3(adiante.z, 0.0, -adiante.x) * lat
		var loc: Vector3 = xf.affine_inverse() * alvo
		x.ang = atan2(loc.x, loc.z)
	return roundf(clampf(x.ang * GANHO_VIRA, -1.0, 1.0) * 7.0) / 7.0   # sétimos (RAM)


# CPU: lidos uma vez (antes: getenv e busca no dicionário por rival e passo)
var _ia_trace := OS.get_environment("IA_TRACE")
var _ia_trace_tudo := OS.has_environment("IA_TRACE_TUDO")


func _dirigir(x: Dictionary, car, dt: float) -> void:
	# o carro lido uma vez no passo (transform, velocidade) e passado adiante
	var xf: Transform3D = car.global_transform
	var b: Basis = xf.basis
	var lv: Vector3 = car.linear_velocity
	var vf: float = lv.dot(b.z)
	var v: float = lv.length()
	if _pensar(x, car, dt):
		return                          # #2: repôs
	_lateral_pedida(x, car, v)
	var st := _direcao(x, car, xf, v)
	# acelerador e freio do jogo (0x34ed10): k = (v_alvo - v) x 0.2, v no plano
	# do chão (0x440), negativa andando de ré (0x418), 0 abaixo de 0.01. Fases
	# do #5: teto (95% do alvo na 1, (1 - f) x ele na 2) e piso (20 mph na 2)
	var v_alvo := maxf(minf(_v_alvo(x, car, xf, lv), x.get("v_max", INF)), x.get("v_min", 0.0))
	x.v_alvo = v_alvo
	var v_ch: float = car.spd_ground
	var v_s := 0.0
	if v_ch > 0.01:
		v_s = v_ch if vf > 0.0 else -v_ch
	var k := clampf((v_alvo - v_s) * GANHO_VEL, -1.0, 1.0)
	var thr := k if k > 0.0 else 0.0
	var brk := -k if k < 0.0 else 0.0
	# derrapando (direção no batente e o carro girando pro outro lado): tira o
	# pé, a física do jogo não endireita sozinha (RecoveryTorqueCutting)
	var giro: float = car.angular_velocity.dot(b.y)
	if absf(st) > 0.8 and giro * st < -0.05:
		thr = 0.0
	elif absf(st) > 0.95:
		thr = minf(thr, 0.5)
	# acelerador e freio em sétimos, como a direção (save state freiando.p2s,
	# nov/2026: 5/7, 2/7, 1/7, 0 e freio 1/7; o valor antes de arredondar fica
	# no piloto +0xa0 freio, +0xa4 acelerador, +0xa8 direção)
	thr = roundf(thr * 7.0) / 7.0
	brk = roundf(brk * 7.0) / 7.0
	car.test_input = {"thr": thr, "brk": brk, "steer": st}
	if _ia_trace == x.nome and (_ia_trace_tudo or Engine.get_physics_frames() % 5 == 0):
		var alvo: float = x.get("v_alvo", 0.0)
		var f5: Dictionary = x.get("f5", {})
		var cmp := "#5 fase %d" % int(f5.fase) if x.get("comp", 0) == 5 else "#%d" % int(x.get("comp", 0))
		if not f5.is_empty() and is_instance_valid(f5.alvo):
			var fi: Dictionary = x.viz.get(f5.alvo, {})
			cmp += " alvo %s setor %s dl %.1f ttc %.2f l1 %.1f l2 %.1f" % [f5.alvo.name, fi.get("setor", "-"),
				fi.get("dl", -1.0), fi.get("ttc", -9.0), f5.lat1, f5.lat2]
		print("trace %5.2f  prog %5.0f  dist %4.1f  v %4.1f/%4.1f  st %5.2f thr %.1f brk %.1f  up %.2f  %s lat %.1f  pos %s" % [
			corrida.t, x.r.prog, x.r.dist, v, alvo, st, thr, brk, b.y.y, cmp, x.get("lat", 0.0), car.global_position])


## 0x214328: velocidade máxima pra sair de p0 no rumo d (no plano do chão)
## e passar por p_alvo com o volante no batente. Raio do arco R = |p_alvo -
## p0|² / (2 x lateral) e o modelo de bicicleta do carro, o mesmo da direção
## (0x20ede8, car.gd _tires: R·δ = L + U·0x724·0.001·v², com o multiplicador
## do subesterço corpo+0x724 do catchup): v = sqrt((R·δ - L) / (U·0x724·0.001)).
## Sem roda no chão, de ré ou lateral < 4 m: sem limite. Arco impossível: 0
func _v_arco(car, p_alvo: Vector3, p0: Vector3, d: Vector3, n: Vector3, delta: float, vf: float) -> float:
	if car.grounded == 0 or vf < 0.0:
		return V_SEM_LIMITE
	var dd := p_alvo - p0
	var lado := n.cross(d)
	var l := lado.length()
	if l > 0.0:
		lado /= l
	var lat := dd.dot(lado)
	if absf(lat) < LAT_RETA:
		return V_SEM_LIMITE
	var r := absf(dd.length_squared() / (lat + lat))
	var P: Dictionary = car.P
	var k: float = float(P.understeer_raw) * (car.mult_sub * 0.001)
	if k <= 1e-6:
		return 0.0
	var num: float = r * delta - (float(P.axle_f) - float(P.axle_r))
	if num < 0.0:
		return 0.0
	return sqrt(num / k)


## 0x359eb8: velocidade-alvo = o menor de 2 arcos (0x35a040 e 0x35a150):
##  1. do carro (posição, rumo da velocidade no plano do chão) até o ponto da
##     linha clamp(v x 1 s, 15, 100) m à frente;
##  2. quando o alvo da direção está a mais de 15 m: do alvo da direção (com
##     y = 0, como no jogo) no rumo da linha até clamp(v, 15, 100) além dele.
## δ = esterço máximo na velocidade de agora (corpo+0x3b4, a curva
## Angle_vs_speed). Sem o limite de velocidade da rota (link+0x44) e sem os
## fatores de modo (x1.2 no modo 15, x0.5 na rota tipo 4): NOSSO por enquanto
func _v_alvo(x: Dictionary, car, xf: Transform3D, lv: Vector3) -> float:
	var v := lv.length()                    # corpo+0xe0 (a IA guarda em +0xa0)
	var vf := lv.dot(xf.basis.z)
	var delta: float = VehicleData.sample(car.steer_curve, v / MPH_G) * DEG   # corpo+0x3b4
	var n: Vector3 = car.n_chao
	var s0: float = x.r.prog + s_linha
	var olha := clampf(v * OLHA_VEL[0], OLHA_VEL[1], OLHA_VEL[2])
	# 0x214240: do CoM (corpo+0x70) no rumo do bico (corpo+0xd0) no plano do chão
	var v1 := 0.0
	var fz: Vector3 = xf.basis.z
	var f_pl := fz - n * fz.dot(n)
	var lp := f_pl.length()
	if lp > 1e-6:
		v1 = _v_arco(car, ponto_zero(s0 + olha), xf * car.center_of_mass, f_pl / lp, n, delta, vf)
	if v1 == 0.0:
		v1 = V_SEM_ARCO
	# 0x35a150: A = o ponto da direção com a lateral pedida (req+6), C = o carro
	# (a posição de rota com a lateral dele, req+1), B = o zero clamp(v, 15,
	# 100) além de A; só com A a mais de 15 m de rota. Saves de nov/2026 (re/
	# ia_alvo_ram.py): acerta 3 dos 4 casos que o zero em A e C errava
	var v2 := V_SEM_LIMITE
	var s_a: float = x.get("s_alvo", s0 + clampf(v * OLHA_T, OLHA_MIN, OLHA_MAX))
	if s_a - s0 > 15.0:
		var pa := ponto_lat(s_a, x.get("lat", 0.0))
		var cm: Vector3 = xf * car.center_of_mass
		pa.y = 0.0
		var rumo := Vector3(cm.x, 0.0, cm.z) - pa
		var lr := rumo.length()
		if lr > 0.0:
			rumo /= lr
		v2 = _v_arco(car, ponto_zero(s_a + olha), pa, rumo, n, delta, vf)
		if v2 == 0.0:
			v2 = V_SEM_ARCO_LINHA
	return minf(v2, v1)


## NOSSO (fora do uso desde nov/2026, o jogo usa o _v_alvo; teste_cpp compara o
## C++): raio = 30 m / (quanto a linha vira em 30 m), v = sqrt(A_LAT x raio),
## mais o que dá pra frear até lá
func _v_curva(s: float) -> float:
	if _cpp:
		return _cpp.v_curva(s)
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


## cérebro (0x3668d0) a cada passo: percepção dos vizinhos, depois quem
## dirige (0x35e8a0). O #5 (ultrapassar, pista/ia_ultrapassar.gd) segura a
## vez enquanto a máquina de fases roda; quando acaba, a saída fica a do
## último passo e o próximo escolhe de novo. O #7 (corrida na linha, 0x3603d0)
## não segura: todo passo o #5 pode tomar a vez (prioridade 1 contra 0.1).
## Recomeçar o #7 sorteia o desvio da Skill de novo (0x360550)
func _pensar(x: Dictionary, car, dt: float) -> bool:
	var lista: Array = _carros_laco if _carros_laco != null else _monta_carros()
	Ultrapassar.percepcao(self, x, car, dt, lista)
	var preso := _preso(x, dt)
	var comp: int = x.get("comp", 0)
	if comp == 5:
		if not Ultrapassar.atualizar(self, x, dt):
			x.comp = 0
		_conta5(x, dt)
		return false
	# #2 (prioridade 1, antes do #5 na lista: no empate ganha ele)
	if preso:
		if OS.has_environment("IA_LOG"):
			print("IA repõe %s em %.0f m (preso, #2 do jogo, t %.1f)" % [x.get("nome", "?"), x.r.prog, corrida.t])
		_repor(x)
		return true
	if Ultrapassar.prioridade(x):
		x.comp = 5 if Ultrapassar.comecar(self, x) else 0
		x.n5 = int(x.get("n5", 0)) + 1
		_conta5(x, dt)
		return false
	if comp != 7:
		x.comp = 7
		x.desvio = desvio_skill(float(x.get("skill", 1.0)))
	# #7 (0x3603d0): nos primeiros 5 s do relógio (0 até o Go!) o modo 0 do
	# 0x359730 (o ponto da direção na fração lateral do próprio carro: cada um
	# segue na faixa do grid); depois o modo 1 com o desvio da Skill
	x.modo = 0 if corrida.t < SKILL_T else 1
	x.pede_lat = x.desvio
	x.olha = Ultrapassar.OLHA
	x.v_max = INF
	x.v_min = 0.0
	return false


## #2 preso (0x356e38, a cada passo): âncora no CoM (objeto +0x30 com a altura
## +0x50); a menos de 2 m dela (3D) e querendo andar (velocidade-alvo do passo
## anterior, piloto +0x40, > 0) o tempo conta (o 1º passo perto só marca);
## longe, âncora nova e zera. Preso com mais de 3 s (0x364640) = repor.
## O modo "fora da rota" (10 s) não acontece no RX01 (a rota cobre tudo).
## Capotado e parado cai aqui também
func _preso(x: Dictionary, dt: float) -> bool:
	var p: Vector3 = x.me.cm
	var perto: bool = x.has("ancora") and float(x.get("v_alvo", 0.0)) > 1e-6 \
		and p.distance_squared_to(x.ancora) < PRESO_R2
	if perto:
		if x.get("preso_conta", false):
			x.preso += dt
		x.preso_conta = true
	else:
		x.preso = 0.0
		x.preso_conta = false
		x.ancora = p
	return x.preso > PRESO_T


## estatística do #5 (testes): segundos em cada fase (5 = acabou no passo)
func _conta5(x: Dictionary, dt: float) -> void:
	if not x.has("t5"):
		x.t5 = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var fase: int = x.f5.fase
	x.t5[fase if fase < 5 else 5] += dt


## 0x359730: a lateral do ponto da direção (x.lat, a nossa, do zero) pelo modo
##  0: a fração lateral do próprio carro (posição de rota dele) levada pro
##     ponto, sem limite;
##  1: a pedida; com o bico torto (o ponto pedido a mais de 10° dele e o da
##     lateral do carro mais alinhado, mas também a mais de 10°) mistura com a
##     do carro: peso (ângulo - 10°) / 10°;
##  2: a pedida (as fases do #5; o corte de curva dos modos 1 e 2 é NOSSO:
##     não portado).
## Modos 1 e 2: dentro das bordas menos a meia largura do carro (objeto
## +0xf4), pelo lado do sinal dela, como no jogo
func _lateral_pedida(x: Dictionary, car, v: float) -> void:
	var o: Vector3 = x.get("olha", Ultrapassar.OLHA)
	var s_me: float = x.r.prog + s_linha
	var s: float = s_me + clampf(v * o.x, o.y, o.z)
	var bj := bordas_jogo(s)
	var modo: int = x.get("modo", 2)
	var l_carro := 0.0
	if modo != 2:
		var me: Dictionary = x.me
		var fr: float = (float(me.l) - float(me.lo)) / maxf(float(me.hi) - float(me.lo), 1e-6)
		l_carro = bj.x + fr * (bj.y - bj.x)
		if modo == 0:
			x.lat = -l_carro
			return
	var lg: float = -float(x.get("pede_lat", 0.0))
	if modo == 1:
		var cm: Vector3 = x.me.cm
		var f2: Vector2 = x.me.f
		var pp := ponto_lat(s, -lg)
		var ca := f2.dot(Vector2(pp.x - cm.x, pp.z - cm.z).normalized())
		if ca < COS_10:
			var pc := ponto_lat(s, -l_carro)
			var cc := f2.dot(Vector2(pc.x - cm.x, pc.z - cm.z).normalized())
			if ca < cc and cc < COS_10:
				var w := clampf((acos(clampf(ca, -1.0, 1.0)) - DEG_10) / DEG_10, 0.0, 1.0)
				lg = l_carro * w + lg * (1.0 - w)
	var hw: float = x.me.cx.hx
	if lg < 0.0:
		lg = maxf(lg, bj.x + hw)
	else:
		lg = minf(lg, bj.y - hw)
	x.lat = -lg


## CPU: [carro, posição, velocidade, rastreio, dados do passo] dos carros válidos, na ordem de
## sempre (jogador e rivais). No laço dos rivais (_physics_process) a lista
## vale o laço todo: lá ninguém anda (só o _repor teleporta, e ele refaz a
## lista); fora dele (testes chamando _dirigir) é feita na hora. O rastreio é
## o próprio dicionário (o progresso de quem já andou no laço é o novo)
var _carros_laco = null
func _monta_carros() -> Array:
	var out: Array = []
	if is_instance_valid(main.car):
		out.append([main.car, main.car.global_position, main.car.linear_velocity, jogador,
			Ultrapassar.dados_carro(self, main.car, jogador)])
	for y in rivais:
		if is_instance_valid(y.car):
			out.append([y.car, y.car.global_position, y.car.linear_velocity, y.r,
				Ultrapassar.dados_carro(self, y.car, y.r)])
	return out


## distância com sinal da linha (+ = pro mesmo lado do desvio em _direcao)
func _lateral(p: Vector3, s: float) -> float:
	if _cpp:
		return _cpp.lateral(p, s)
	var q := ponto(s)
	var adiante := _plano(ponto(s + 2.0) - q).normalized()
	return _plano(p - q).dot(Vector3(adiante.z, 0.0, -adiante.x))


## volta pro último progresso aceito (o jogo repõe sempre lá: 0x4d3538)
func _repor(x: Dictionary) -> void:
	x.r.prog = x.vigia.aceito
	repor_em(x.car, x.r.prog + s_linha)
	x.vigia.recomecar(x.r.prog)
	x.preso = 0.0
	x.erase("ancora")
	x.lat = x.desvio
	x.repostos += 1
	# NOSSO: reposto, o cérebro recomeça (vizinhos e comportamento)
	x.viz = {}
	x.comp = 0


func repor_jogador() -> void:
	jogador.prog = vigia_jogador.aceito
	repor_em(main.car, jogador.prog + s_linha)
	vigia_jogador.recomecar(jogador.prog)
	main.reset_camera()


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
	if _carros_laco != null:
		_carros_laco = _monta_carros()      # alguém foi teleportado


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
