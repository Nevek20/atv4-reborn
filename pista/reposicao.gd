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
## Não portado: o pedido tipo 3 (checkpoint perdido; o RX01 tem 1 caminho só),
## 2 flags do objeto do corredor (+0x120 +0x24/+0x28, zeradas na RAM, quem liga
## não foi achado) e as caixas do 0x543b88 (a lista está vazia no RX01).

const PARAMS := {1: [0.2, 2.0, 3.0], 2: [0.2, 0.0, 3.0]}     # 0x4d4808
const TEXTO := {1: "Wrong Way", 2: "Off Track, Go Back!"}
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


func _init(ia_, prog: float) -> void:
	ia = ia_
	logic = ia.corrida.dados.get("logic", {})
	recomecar(prog)


func recomecar(prog: float) -> void:
	aceito = prog
	pulo = true
	tipo = 0
	fase = 0
	tempo = 0.0


## um passo; devolve true quando é pra repor (em aceito)
func passo(r: Dictionary, car: RigidBody3D, dt: float) -> bool:
	var s: float = fposmod(r.prog + ia.s_linha, ia.comp)
	var i: int = ia._seg(s)
	var n: int = ia.linha.size()
	var pa: Vector3 = ia.linha[i]
	var pb: Vector3 = ia.linha[(i + 1) % n]
	var d := Vector3(pb.x - pa.x, 0.0, pb.z - pa.z)
	var l := d.length()
	d = d / maxf(l, 1e-6)
	var p: Vector3 = car.global_position
	var t := clampf(Vector3(p.x - pa.x, 0.0, p.z - pa.z).dot(d) / maxf(l, 1e-6), 0.0, 1.0)
	# lado do jogo (x, z) = (d.z, -d.x) do link; no mundo (z - 1024, y, x):
	# lat = dz_mundo * d.x - dx_mundo * d.z
	var lat: float = (p.z - pa.z) * d.x - (p.x - pa.x) * d.z
	var esq: float = lerpf(ia.esq[i], ia.esq[(i + 1) % n], t)
	var dir_: float = lerpf(ia.dir[i], ia.dir[(i + 1) % n], t)
	fora = esq - lat if lat < esq else (lat - dir_ if lat > dir_ else 0.0)
	# trapaça e progresso aceito
	var trapaca: bool = fora > logic.get("mCheatingStray", 8.0)
	var delta: float = r.prog - aceito
	if not pulo:
		if delta < -logic.get("mBackwardLimit", 100.0):
			trapaca = true
		if delta > logic.get("mCheatingProgress", 30.0):
			trapaca = true
	if delta > 0.0 and (pulo or not trapaca):
		aceito = r.prog
	pulo = false
	# pedido
	var v := Vector3(car.linear_velocity.x, 0.0, car.linear_velocity.z)
	if v.length() > 1e-3 and d.dot(v.normalized()) < -0.5:
		_pedir(1)
	elif trapaca or fora > logic.get("mWarningStray", 4.0):
		_pedir(2)
	else:
		tipo = 0
		fase = 0
		tempo = 0.0
	return _contar(dt)


func _pedir(k: int) -> void:
	if tipo != 0:
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
