extends RefCounted
## Reposição automática fora das caixas (nov/2026): porta do objeto de
## progresso de cada corredor do exe (classe base 0x4d2cc0, vtable 0x5eb940;
## a da corrida 0x4d4b18, vtable 0x5eb8f8; update 0x4d3658). Um por carro
## (o jogador e os 7 rivais têm o mesmo, todos com reposição ligada na RAM).
## pista/ia.gd cria e chama passo() a cada passo da física.
##
## Logic do TrackSetup/RALLYCROSS.xml (lida em 0x1bf6d8; data/rx01_corrida.json
## "logic"): mWarningStray 4, mCheatingStray 8, mCheatingProgress 30,
## mBackwardLimit 100 (m), mRespotSpeed 40 (mph, o botão).
##
## Fora da pista (+0x7c do rastreio, 0x4d57e0): a distância lateral ao link
## do AIT (eixo de lado do link, medido a partir do PONTO DA LINHA, não do
## centro) que passa da borda: largura esquerda +0x68 / direita +0x6c do AIT,
## interpoladas ao longo do link (0x329620/0x329680). Dentro = 0.
##
## Cada passo (0x4d3658), nesta ordem:
##  - contramão (0x4d58e0): frente do link . direção da velocidade (plano) <
##    -0.5 -> pedido tipo 1 (0.2, 2.0, 3.0);
##  - senão, trapaça ou fora > WarningStray -> pedido tipo 2 (0.2, 0, 3.0).
##    Trapaça: fora > CheatingStray, progresso < aceito - BackwardLimit ou um
##    avanço > CheatingProgress (0x4e0b68); com trapaça o avanço não é aceito;
##  - senão o pedido é apagado (tem que valer em todo passo seguido).
## Pedido (corredor+0x148, 0x4d4ef0 / contagem 0x4d4f60): fase 1 espera a,
## fase 2 espera b (mostra a mensagem; o tipo 1 vira 2 aqui), fase 3 espera
## c com a contagem "- 3, 2, 1" e repõe (0x4d3538 -> 0x15bd28) no último
## progresso aceito. Fora da pista = 3.2 s; contramão = 5.2 s.
## HUD (0x47bb58): tipo 1 WRONG_WAY, 2 Off_Track_Go_Back, 3 MISSED_CHECKPOINT
## (textos do text/15205_en.txt), nas fases 2 e 3.
##
## Checkpoint (nov/2026; o RX01 tem 1, a linha de chegada: AILink 50, fração
## 0.0954 = a face de entrada da caixa, 1.44 m antes do centro). O registro
## aceito (+0x40) guarda o checkpoint pendente (+0x4c): o aceito entrar no link
## dele liga (0x4d50a8 / 0x4d3168). Cada passo, com pendente:
##  - caixa (0x4d3658): |local| <= meias medidas (15.83 x 5.94 x 1.44 m, RAM:
##    o tamanho do XML JÁ É a meia medida) e a frente do carro . frente do
##    link > 0 -> passou (0x4d43f0): apaga o pendente, estado 0 e conta a volta
##    (0x4d50d0: só se andou > 1/4 de volta desde a última, 0x4d2b30);
##  - com avanço > 0 o estado (+0x30) = 0x4d5188: 1 se o rastreio saiu do link
##    ou passou 5 m da face de entrada sem a caixa. Sem pendente, o caminho
##    do aceito até o rastreio (0x4d31f0 / 0x4d32c8) pulando o link do
##    checkpoint também dá 1. Com estado 1 o avanço não é aceito.
##  - estado 1 -> pedido tipo 3 (0.2, 1, 3; 0x4d4808), que passa na frente
##    de um pedido 1/2 andando (0x4d4ef0: vai direto pra fase 2 com 0, 1, 3).
## Repor com pendente além do centro da caixa volta pro começo do link
## (0x4d3fe0), antes da caixa: senão repunha depois dela pra sempre.
##
## Não portado: 2 flags do objeto do corredor (+0x120 +0x24/+0x28, zeradas na
## RAM, quem liga não foi achado), as caixas do 0x543b88 (a lista está vazia no
## RX01) e o ponto salvo de 0.5 em 0.5 s (0x4d44c0; o nosso repõe no aceito).

const PARAMS := {1: [0.2, 2.0, 3.0], 2: [0.2, 0.0, 3.0], 3: [0.2, 1.0, 3.0]}   # 0x4d4808
const PARAMS_3_POR_CIMA := [0.0, 1.0, 3.0]     # 0x4d4ef0: tipo 3 em cima de outro, fase 2
const TEXTO := {1: "Wrong Way", 2: "Off Track, Go Back!", 3: "Missed Checkpoint"}
const CP_PASSOU := 5.0           # 0x4d5188: m depois da face de entrada sem a caixa
const VOLTA_MIN := 0.25          # 0x4d50d0: fração da volta desde a última contada
const MPH := 0.44704

var ia
var logic := {}
var tipo := 0
var fase := 0
var tempo := 0.0
var a := 0.0
var b := 0.0
var c := 0.0
var aceito := 0.0               # último progresso aceito (m de corrida)
var pulo := true                # o 1º passo depois de repor não confere trapaça
var fora := 0.0                 # m além da borda (diagnóstico e testes)
var repostos := 0
var pendente := false           # checkpoint pendente no registro aceito (+0x4c)
var estado := 0                 # +0x30: 1 = checkpoint perdido
var voltas := 0                 # passagens contadas pela caixa (+0x50)
var _volta_ini := 0.0           # progresso do começo da volta atual (0x4d2800)

# o checkpoint na linha da IA (do data/rx01_corrida.json "checkpoint")
var _cp_seg := -1               # trecho da linha = o AILink do checkpoint
var _cp_ent := 0.0              # s (m na volta) da face de entrada (a fração do link)
var _cp_centro := 0.0           # s do centro da caixa (= s_linha)


# CPU: os limites do <Logic> lidos uma vez (antes: 4 buscas por carro e passo)
var _cheat_stray := 8.0
var _backward := 100.0
var _cheat_prog := 30.0
var _warn_stray := 4.0


func _init(ia_, prog: float) -> void:
	ia = ia_
	logic = ia.corrida.dados.get("logic", {})
	_cheat_stray = logic.get("mCheatingStray", 8.0)
	_backward = logic.get("mBackwardLimit", 100.0)
	_cheat_prog = logic.get("mCheatingProgress", 30.0)
	_warn_stray = logic.get("mWarningStray", 4.0)
	var cp: Dictionary = ia.corrida.dados.get("checkpoint", {})
	var n: int = ia.linha.size()
	if cp.has("link") and n > 1:
		var k := int(cp.link)
		_cp_seg = n - 1 - k if ia.corrida.sentido < 0 else k
		var l: float = ia._plano(ia.linha[(_cp_seg + 1) % n] - ia.linha[_cp_seg]).length()
		_cp_ent = float(ia.acc[_cp_seg]) + float(cp.get("fracao", 0.0)) * l
		_cp_centro = fposmod(float(ia.s_linha), float(ia.comp))
	# a 1ª volta vai da largada até a linha (0x4d2800 com 0 voltas)
	_volta_ini = prog
	recomecar(prog)


## depois de repor (0x4d3538: estado 0, pulo; o pendente fica no registro)
func recomecar(prog: float) -> void:
	aceito = prog
	pulo = true
	tipo = 0
	fase = 0
	tempo = 0.0
	estado = 0


## onde repor: o último progresso aceito; com checkpoint pendente e o ponto
## além do centro da caixa, o começo do link dele (0x4d3fe0)
func ponto_repor() -> float:
	if pendente and _cp_seg >= 0:
		var s: float = fposmod(aceito + ia.s_linha, ia.comp)
		if ia._seg(s) == _cp_seg and s >= _cp_centro:
			return aceito - (s - float(ia.acc[_cp_seg]))
	return aceito


## trecho da linha com a volta (pra comparar links de voltas diferentes)
func _seg_g(prog: float) -> int:
	var s: float = prog + ia.s_linha
	var v := floorf(s / ia.comp)
	return int(v) * ia.linha.size() + ia._seg(s - v * ia.comp)


## um passo; devolve true quando é pra repor (em aceito)
func passo(r: Dictionary, car: RigidBody3D, dt: float) -> bool:
	var d: Vector3
	var cpp = ia.get("_cpp")
	if cpp:
		# a mesma geometria em C++ (fisica_cpp/src/linha_ia.cpp fora)
		var g: PackedFloat64Array = cpp.fora(r.prog, ia.s_linha, car.global_position)
		fora = g[0]
		d = Vector3(g[1], 0.0, g[2])
	else:
		var g: Array = _fora_gd(r.prog, car.global_position)
		fora = g[0]
		d = g[1]
	# caixa do checkpoint pendente (antes do aceite, 0x4d3658)
	if pendente and _na_caixa(car, d):
		_passou_caixa()
	# trapaça e progresso aceito
	var trapaca: bool = fora > _cheat_stray
	var delta: float = r.prog - aceito
	if not pulo:
		if delta < -_backward:
			trapaca = true
		if delta > _cheat_prog:
			trapaca = true
	if delta > 0.0:
		estado = _estado_cp(r.prog)
		if (pulo or not trapaca) and estado == 0:
			_aceitar(r.prog)
	pulo = false
	# pedido
	var lv: Vector3 = car.linear_velocity
	var v := Vector3(lv.x, 0.0, lv.z)
	if estado != 0:
		_pedir(3)
	elif v.length() > 1e-3 and d.dot(v.normalized()) < -0.5:
		_pedir(1)
	elif trapaca or fora > _warn_stray:
		_pedir(2)
	else:
		tipo = 0
		fase = 0
		tempo = 0.0
	return _contar(dt)


## quanto o ponto p passou da borda do AIT e a direção do trecho: [fora, d]
## (o fora do linha_ia.cpp é o mesmo)
func _fora_gd(prog: float, p: Vector3) -> Array:
	var s: float = fposmod(prog + ia.s_linha, ia.comp)
	var i: int = ia._seg(s)
	var n: int = ia.linha.size()
	var pa: Vector3 = ia.linha[i]
	var pb: Vector3 = ia.linha[(i + 1) % n]
	var d := Vector3(pb.x - pa.x, 0.0, pb.z - pa.z)
	var l := d.length()
	d = d / maxf(l, 1e-6)
	var t := clampf(Vector3(p.x - pa.x, 0.0, p.z - pa.z).dot(d) / maxf(l, 1e-6), 0.0, 1.0)
	# lado do jogo (x, z) = (d.z, -d.x) do link; no mundo (z - 1024, y, x):
	# lat = dz_mundo * d.x - dx_mundo * d.z
	var lat: float = (p.z - pa.z) * d.x - (p.x - pa.x) * d.z
	var esq: float = lerpf(ia.esq[i], ia.esq[(i + 1) % n], t)
	var dir_: float = lerpf(ia.dir[i], ia.dir[(i + 1) % n], t)
	return [esq - lat if lat < esq else (lat - dir_ if lat > dir_ else 0.0), d]


## 0x4d5188: checkpoint pendente e o rastreio já fora do link dele ou mais de
## 5 m depois da face de entrada -> 1 (perdido)
func _estado_cp(prog: float) -> int:
	if not pendente or _cp_seg < 0:
		return 0
	if _seg_g(prog) != _seg_g(aceito):
		return 1
	var s: float = fposmod(prog + ia.s_linha, ia.comp)
	return 1 if s - _cp_ent > CP_PASSOU else 0


## 0x4d31f0 / 0x4d32c8 e o aceite (0x4d50a8): o caminho do link aceito até o
## do rastreio não pode pular o do checkpoint (o aceito só se ele estiver
## pendente; o do rastreio não conta). Entrar no link liga o pendente
func _aceitar(prog: float) -> void:
	var a := _seg_g(aceito)
	var t := _seg_g(prog)
	if t != a and _cp_seg >= 0:
		var n: int = ia.linha.size()
		var i0 := a if pendente else a + 1
		for g in range(i0, t):
			if posmod(g, n) == _cp_seg:
				estado = 1
				return
		pendente = posmod(t, n) == _cp_seg
	aceito = prog


## dentro da caixa do checkpoint (eixos e meias medidas da RAM; a posição do
## corpo) e de frente pro sentido do link aceito (a frente do carro)
func _na_caixa(car: RigidBody3D, d: Vector3) -> bool:
	var c = ia.corrida
	var r: Vector3 = car.global_position - c._cp_pos
	var m: Vector3 = c._cp_meia
	if absf(r.dot(c._cp_lado)) > m.x or absf(r.y) > m.y or absf(r.dot(c._cp_frente)) > m.z:
		return false
	return car.global_transform.basis.z.dot(d) > 0.0


## 0x4d43f0 + 0x4d50d0: apaga o pendente e o estado; a volta conta se andou
## mais de 1/4 dela desde a última (0x4d2b30)
func _passou_caixa() -> void:
	pendente = false
	estado = 0
	var fim: float = float(voltas) * ia.comp       # 0x4d2800: a volta n acaba em n x comp
	if (aceito - _volta_ini) / maxf(fim - _volta_ini, 1e-3) > VOLTA_MIN:
		_volta_ini = fim
		voltas += 1


func _pedir(k: int) -> void:
	if tipo != 0:
		if k == 3 and tipo != 3:
			tipo = 3
			fase = 2
			tempo = 0.0
			a = PARAMS_3_POR_CIMA[0]
			b = PARAMS_3_POR_CIMA[1]
			c = PARAMS_3_POR_CIMA[2]
		return
	tipo = k
	fase = 1
	tempo = 0.0
	a = PARAMS[k][0]
	b = PARAMS[k][1]
	c = PARAMS[k][2]


func _contar(dt: float) -> bool:
	if fase == 0:
		return false
	tempo += dt
	if fase == 1 and tempo >= a:
		fase = 2
		tempo = 0.0
	elif fase == 2 and tempo >= b:
		fase = 3
		tempo = 0.0
		if tipo == 1:
			tipo = 2
	elif fase == 3 and tempo >= c:
		tipo = 0
		fase = 0
		tempo = 0.0
		repostos += 1
		return true
	return false


## mensagem do HUD (fases 2 e 3; na 3 com a contagem)
func texto() -> String:
	if fase < 2 or not TEXTO.has(tipo):
		return ""
	if fase == 3:
		return "%s - %d" % [TEXTO[tipo], clampi(int(c - tempo) + 1, 1, int(c))]
	return TEXTO[tipo]


## o botão de reposição (0x158f.. no update do corredor): só abaixo de
## mRespotSpeed (17.88 m/s = 40 mph, |v| do corpo); acima, "Too Fast For Respot"
func pode_botao(car: RigidBody3D) -> bool:
	return car.linear_velocity.length() < logic.get("mRespotSpeed", 40.0) * MPH
