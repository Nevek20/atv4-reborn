extends RefCounted
## Score: pontos de truque dos buggies e trucks, porta do gerenciador de
## truques do jogo (um por corredor, corredor+0x15c; passo 0x522c18 a cada
## quadro de 50 Hz). Números do Setup/TRICKS.xml (data/tricks.xml).
##
## Estado do carro (0x524980, vtable dos 4 rodas 0x5fa2d8/0x5fa298):
##   nenhuma roda no chão (corpo+0x8a8): 6 AirTime se o tempo no ar
##   (corpo+0x3d0, zera com batida do casco) >= 0.4 s, senão 9;
##   no chão: |derrapagem| (corpo+0x6c0, graus; > 89 vale 0) >= 17 e |v|
##   (corpo+0xe0) >= 10 m/s: Slide, 4 com derrapagem < 0 e 5 com > 0 (dois
##   truques diferentes pro multiplicador: "Slide left then right for a
##   combo", TRAINING_TEXT_HEAVY_5); senão 8 (nada).
## Truque (0x5220d8, casos da tabela 0x5f9630):
##   começa (8 -> 4/5/6) sem batida no quadro (corpo+0x5a4) e com velocidade
##   no plano do chão (corpo+0x440) >= 2.2347 m/s: tempo = dt, taxa = Score;
##   segue (mesmo estado, < 51 quadros com batida, v >= 2.2347): tempo += dt,
##   taxa += taxa x Accel x dt, pontos += taxa x dt (Score 500, Accel 0.25:
##   ~500/s crescendo); passou 0.2 s: pontos = min(pontos, Max) e mostra
##   (0x5234f8, combo ativo); troca direta de truque (4 <-> 5 <-> 6) fecha o
##   anterior e começa o novo com tempo 0.1 SEM zerar os pontos (0x522550:
##   o jogo é assim, portado igual); volta pra 8 fecha (0x522648). Fechar
##   (0x5230b0) só com tempo > 0.2: combo += int(pontos) (trunca), +1 truque
##   e +1 no multiplicador se o estado é novo no combo. No ar curto (9) nada
##   muda (o giro 0x521828 só anda nos ATVs).
## Combo (0x523e18): depois de fechar um truque espera pousar (fase 1 -> 2);
##   no chão, passada a folga de 0.5 s do fim do truque, com 3+ rodas no chão
##   por 0.75 s (ou 5 s com menos) e sem truque andando: banca (0x523718)
##   total += combo x multiplicador. Na chegada o combo aberto se perde
##   (0x1596d8 -> 0x523ff0 -> 0x523570: mensagem vermelha).
## Fora do RX01 / não portado: Holeshot (+1000, cHoleshotBox: o evento do
## RX01 não tem a caixa), multiplicador por posição (RaceStuntMultipliers, só
## no tipo de evento 0xc; o RX01 é 0 na RAM) e recordes (+0x19c..).
## Conferido com a RAM (seta.p2s: total 6512 = 3256 x 2; estado 5 com
## derrapagem 17.2° a 25.5 m/s, tempo 0.02 e taxa 500 no 1º quadro).

const ARQ := "res://data/tricks.xml"
const V_MIN := 2.2347221          # corpo+0x440 (m/s): começa e soma acima disso
const V_SLIDE := 10.0             # corpo+0xe0 (m/s)
const ANG_SLIDE := 17.0           # graus
const AR_MIN := 0.4               # s no ar pro AirTime
const MOSTRA := 0.2               # s de truque pra valer
const BATIDAS_MAX := 51           # quadros com batida dentro do truque
const FOLGA := 0.5                # s depois do fim do truque (+0x288)
const CHAO_BANCA := 0.75          # s com 3+ rodas no chão (+0x278)
const FIM_BANCA := 5.0            # s com menos rodas (+0x27c)
const AR_ZERA := 0.75             # s no ar que zeram os relógios (+0x284)
const NOMES := {4: "Slide", 5: "Slide", 6: "AirTime"}   # enum 0x7f64a8 (RAM)

# tipos do evento pro HUD (+0x3d8): 0 mostrando, 2 fechou, 3 perdeu, 4 bancou
enum { AO_VIVO = 0, FECHOU = 2, PERDEU = 3, BANCOU = 4 }

var tabela := {}                  # estado -> [Score, Max, Accel]
var ligado := false               # +0x294 (a corrida começou) e não chegou (+8)
var total := 0                    # +4: o Score do HUD
var combo := 0                    # +0x1f8
var mult := 0                     # +0x1f4: truques diferentes no combo
var n_truques := 0                # +0x200
var combo_ativo := false          # +0x1fc
var usados := {}                  # +0x84 + 4 x estado
var estado := 8                   # +0xbc
var t_truque := 0.0               # +0x16c
var taxa := 0.0                   # +0x170
var pts := 0.0                    # +0x174
var batidas := 0                  # +0x274
var fase := 0                     # +0x3e0
var t_fase1 := 0.0                # +0x280
var t_chao := 0.0                 # +0x278
var t_fim := 0.0                  # +0x27c
var t_no_ar := 0.0                # +0x284
var folga := 0.0                  # +0x288
var ar := 0.0                     # corpo+0x3d0 (zera com batida)
var evento := {}                  # +0x338..+0x3d8 (o HUD lê e apaga)
var vivo := []                    # +0x210/+0x20c/+0x214: truque mostrado e ainda não fechado [pontos, novo]
var ultimo := 0                   # testes: pontos do último banco


func _init(grupo := "Buggy") -> void:
	tabela = ler_tabela(grupo)


## GroundTricks do grupo (Buggy / Truck) na ordem do enum: Slide vale pros
## estados 4 e 5, AirTime pro 6 (0x1a34e8 lê os 7 nomes do 0x7f64a8)
static func ler_tabela(grupo: String) -> Dictionary:
	var out := {}
	var f := FileAccess.open(ARQ, FileAccess.READ)
	if f == null:
		return out
	var x := f.get_as_text()
	var i := x.find('<Group Name="%s">' % grupo)
	if i < 0:
		return out
	var j := x.find("</GroundTricks>", i)
	var bloco := x.substr(i, j - i)
	var rx := RegEx.create_from_string('<(\\w+) Score="([-\\d.]+)" Accel="([-\\d.]+)" Max="([-\\d.]+)"')
	for m in rx.search_all(bloco):
		for e in NOMES:
			if NOMES[e] == m.get_string(1):
				out[e] = [int(m.get_string(2)), int(m.get_string(4)), float(m.get_string(3))]
	return out


static func grupo_do(car) -> String:
	return "Truck" if String(car.vehicle_id).begins_with("TRUCK") else "Buggy"


func zerar() -> void:
	total = 0
	_zerar_combo()
	estado = 8
	t_truque = 0.0
	taxa = 0.0
	pts = 0.0
	batidas = 0
	fase = 0
	folga = 0.0
	t_no_ar = 0.0
	ar = 0.0
	evento = {}
	ultimo = 0


func _zerar_combo() -> void:
	combo = 0
	mult = 0
	n_truques = 0
	combo_ativo = false
	usados.clear()
	vivo = []


## 0x524980: estado dos 4 rodas
static func estado_carro(rodas: int, ar_: float, beta: float, v: float) -> int:
	if rodas == 0:
		return 6 if ar_ >= AR_MIN else 9
	var g := beta * 57.295776
	var a := absf(g)
	if a > 89.0:
		g = 0.0
		a = 0.0
	if a >= ANG_SLIDE and v >= V_SLIDE:
		return 4 if g < 0.0 else 5
	return 8


## um quadro (0x522c18) com o carro do jogador
func passo(dt: float, car) -> void:
	var n: Vector3 = car.n_chao
	var v: Vector3 = car.linear_velocity
	# derrapagem do jogo (0x6c0) = -sideslip (o carro é espelhado)
	passo_dados(dt, int(car.grounded), int(car.contatos), -float(car.sideslip), v.length(),
		(v - n * v.dot(n)).length())


func passo_dados(dt: float, rodas: int, contatos: int, beta: float, v3: float, vp: float) -> void:
	if not ligado:
		return
	var bateu := contatos > 0
	# corpo+0x3d0: no ar soma, no chão zera; batida do casco zera (0x215248)
	ar = ar + dt if rodas == 0 else 0.0
	if bateu:
		ar = 0.0
	_chao(dt, estado_carro(rodas, ar, beta, v3), vp, bateu)
	if combo_ativo:
		_fim_combo(dt, rodas)
	if rodas == 0:
		t_no_ar += dt
		if t_no_ar >= AR_ZERA:
			t_chao = 0.0
			t_fim = 0.0
	else:
		t_no_ar = 0.0
	if folga > 0.0:
		folga = maxf(folga - dt, 0.0)


## 0x5220d8
func _chao(dt: float, est: int, vp: float, bateu: bool) -> void:
	var ant := estado
	var novo := est
	var sem := est == 8 or est == 9
	if not sem:                         # 0x5230a0: com truque, o combo não fecha
		t_chao = 0.0
		t_fim = 0.0
	if ant != 8 and ant != 9 and sem:   # truque acabou: folga
		t_chao = 0.0
		t_fim = 0.0
		folga = FOLGA
	var caso := 0
	if est == 8:
		caso = 0 if (ant == 8 or ant == 9) else 5
	elif est == 9:
		caso = 3                        # no ar curto: segue como estava
		novo = ant
	elif est >= 0 and est <= 6:
		if ant == 8:
			if not bateu and (vp >= V_MIN or est == 3):
				caso = 1
			else:
				novo = 8
		elif ant == est:
			caso = 5
			if batidas < BATIDAS_MAX:
				caso = 2 if (vp >= V_MIN or est == 3) else 3
			elif n_truques < 2:
				caso = 0
		else:
			caso = 3 if (ant == 8 or ant == 9) else 4
	match caso:
		1:                              # 0x522378
			t_truque = dt
			batidas = 0
			pts = 0.0
			taxa = float(_e(est)[0])
		2:                              # 0x5223d0
			var e := _e(est)
			t_truque += dt
			taxa += taxa * float(e[2]) * dt
			if bateu:
				batidas += 1
			pts += taxa * dt
			if t_truque > MOSTRA:
				pts = minf(pts, float(e[1]))
				_mostrar(est, int(pts))
		4:                              # 0x522550
			if t_truque > MOSTRA:
				pts = minf(pts, float(_e(ant)[1]))
				_fechar(ant, int(pts))
				t_truque = 0.1
				taxa = float(_e(est)[0])
			else:
				t_truque = 0.0
		5:                              # 0x522648
			if t_truque > MOSTRA:
				pts = minf(pts, float(_e(ant)[1]))
				_fechar(ant, int(pts))
			t_truque = 0.0
	estado = novo


func _e(est: int) -> Array:
	return tabela.get(est, [0, 0, 0.0])


## 0x5234f8: o truque andando aparece com o combo + ele
func _mostrar(est: int, p: int) -> void:
	combo_ativo = true
	var novo := int(usados.get(est, 0)) == 0
	vivo = [p, novo]
	evento = {"nome": NOMES.get(est, ""), "pontos": combo + p, "mult": mult + (1 if novo else 0), "tipo": AO_VIVO}


## 0x5230b0
func _fechar(est: int, p: int) -> void:
	vivo = []
	combo += p
	n_truques += 1
	if int(usados.get(est, 0)) == 0:
		mult += 1
	usados[est] = int(usados.get(est, 0)) + 1
	evento = {"nome": NOMES.get(est, ""), "pontos": combo, "mult": mult, "tipo": FECHOU}
	_fase(1)


## 0x523e00
func _fase(f: int) -> void:
	fase = f
	t_no_ar = 0.0
	t_chao = 0.0
	t_fim = 0.0
	t_fase1 = 0.0


## 0x523e18 (sem truque do piloto: índice -1)
func _fim_combo(dt: float, rodas: int) -> void:
	if fase == 1:
		t_fase1 += dt
		if rodas != 0:
			_fase(2)
		return
	if fase != 2:
		return
	var parado := folga <= 0.0
	if parado:
		t_fim += dt
		t_chao += dt
	if estado != 8 and estado != 9 and t_truque > MOSTRA:
		_fase(0)                        # outro truque andando: espera ele fechar
		return
	if not parado:
		return
	if rodas > 4 >> 1:
		if t_chao >= CHAO_BANCA:
			bancar()
	elif t_fim >= FIM_BANCA:
		bancar()


## 0x523718: total += combo x multiplicador
func bancar() -> void:
	var p := combo * mult
	ultimo = p
	evento = {"nome": "", "pontos": combo, "mult": mult, "tipo": BANCOU}
	total += p
	_zerar_combo()
	estado = 8
	_fase(0)


## 0x523ff0 (chegada): o combo aberto se perde (0x523570, com o truque que
## estava aparecendo) e para de contar
func parar() -> void:
	if ligado and combo_ativo:
		var p := combo
		var m := mult
		if not vivo.is_empty():
			p += int(vivo[0])
			m += 1 if vivo[1] else 0
		evento = {"nome": "", "pontos": p, "mult": m, "tipo": PERDEU}
		_zerar_combo()
		estado = 8
		_fase(0)
	ligado = false


## 0x524038: o HUD pega o evento e apaga
func ler_evento() -> Dictionary:
	var e := evento
	evento = {}
	return e
