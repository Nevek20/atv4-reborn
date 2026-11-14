extends Node
## Sons de pneu, suspensão e pouso do jogo (portados do exe), tocados com os
## samples do próprio jogo (tools/sfx_jogo.py -> assets/sons, som_jogo.gd).
## Parâmetros: data/sound_database.xml (Audio/SoundDatabase.xml do jogo).
## Roda a cada passo do jogo (50 Hz), chamado pelo car.gd depois do _vibracao.
##
## Entradas comuns (0x36fa28): spd = |v|·2.2374/140 e side = |v lateral|·
## 2.2374/60, as duas com x < 0.025 -> 40x² e no máximo 1; ws = 0.5 por roda
## com patinada 0x600 > 0.2, no máximo 1.
## Rodas (0x370548): só a frente esquerda (FL) e a traseira esquerda (RL)
## tocam o patch principal do material do chão; a FL toca também o
## secundário (no asfalto, o Screech). Material = SFX do materials_rx01.xml.
##   volume: V = Min + spd·(Max - Min) (x40·spd abaixo de 0.025), + side·Side
##   + ws·Wheelspin [+ WheelLock travada acima de 5 mph] [+ AttackLevel no
##   passo em que o chão muda], x (|direção|·Steer + 1)·(acelerador·Acc + 1),
##   V = (V - V·(1 - susp)·Suspension)·Volume; abaixo do MinThreshold = 0,
##   senão x Volume do material, cai devagar (DecayRate) e x SFX·Surface.
##   tom: (Pitch + spd·Speed + side·Side + ws·Wheelspin [+ WheelLock] +
##   |direção|·Steer + acelerador·Acc + roda·WheelDiff + susp·Suspension)
##   x Pitch do material. No ar o volume vai a 0 na hora.
## Suspensão (0x36e498/0x36e2d8): acima de 20 mph pra frente, quando a taxa
## da suspensão (car.susp_taxa) passa o Threshold do Small/Large do "Buggy",
## toca com a Probability, no máximo uma vez por MinRetriggerTime; volume
## (1 - VolumeSpeed·(1 - spd))·Collision·SFX·Volume, tom 1.
## Pouso (0x370df0): car.pouso (0.5 + 0.5·min(1, tempo no ar)) x Landing
## Volume duas vezes x SFX, tom Landing Pitch, material da FL.
## Sem distância 3D (o carro do jogador). Unidades de volume do 989snd não
## confirmadas: GANHO é o nosso trim contra o som do motor (que é nosso).
##
## Nossas (Matheus testou): o pneu rolando o tempo todo cansava. Com
## SO_DERRAPANDO o loop do pneu só aparece derrapando: o volume do jogo vai
## multiplicado por ROLAGEM + (1 - ROLAGEM)·d, com d = maior de side x
## DERRAPA_SIDE, ws e roda travada, suavizado (sobe em DERRAPA_SOBE, desce em
## DERRAPA_DESCE). false = mistura do jogo. Patinada só conta com o pneu
## escorregando mais de PATINA_MIN m/s: parado numa ladeira a patinada medida
## (giro x raio / v - 1) divide por quase zero e o som ligava e desligava a
## cada quadro.

const SomJogo := preload("res://som/som_jogo.gd")
const XML := "res://data/sound_database.xml"
const GANHO := 1.0                # suspensão e pouso
const GANHO_PNEU := 0.6           # loops das rodas (estavam altos)
const SO_DERRAPANDO := true
const ROLAGEM := 0.0              # quanto do pneu rolando reto fica (0 = nada)
const DERRAPA_SIDE := 4.0         # side 0.25 (~15 mph de lado) = derrapagem cheia
const DERRAPA_SOBE := 0.05        # s
const DERRAPA_DESCE := 0.25       # s
const PATINA_MIN := 1.0           # m/s de escorregada pra contar patinada

var car = null
var master := {}
var patches := {}                 # nome -> {looping: {sample, pitch:{}, volume:{}}, landing: {...}}
var materiais := {}               # nome -> {Pitch, Volume, SurfacePatch, SecondaryPatch}
var susp := {}                    # Small/Large do "Buggy"
var modelo := {}                  # BUGGY_NN (SuspensionScale, SuspensionOffset)
var rodas: Array = []             # objetos de som das rodas
var _susp_ret := {"Small": 0.0, "Large": 0.0}
var _susp_flag := {"Small": false, "Large": false}
var _uma_vez: Array = []          # sons curtos tocando (suspensão, pouso)
var objetos_som := {}             # Collisions/InteractiveObjects (PLASTIC_FENCE, HAY...)
var batidas: Array = []           # [CollisionSample, sample, volume] tocados
var colisoes := {}                # atributos do <Collisions> (MinRetriggerTime 0.2)
# batida do carro com o mundo (0x36e7a8): Collisions/Patches (Default, Metal,
# Wood, Vehicle, RiderM/F) -> {Small, Large, Scraping}
var batida_patches := {}
var batida_tocadas: Array = []    # [patch, sample, volume] (testes)
var _bat_ret := 0.0               # som+0x498: espera do MinRetriggerTime
var _raspa_t := 0.0               # som+0x49c: raspão tocando (MinScrapeTime)
var _raspa_patch := "Default"     # som+0x494
var raspa: SomJogo                # loop do raspão (Scraping)
var spd := 0.0
var side := 0.0
var ws := 0.0
var derrapa := 0.0              # 0..1 (SO_DERRAPANDO)
var _cpp: RefCounted = null     # laço das rodas em C++ (fisica_cpp/src/som.cpp, a mesma conta)


func carregar(c) -> bool:
	car = c
	if not FileAccess.file_exists(XML) or SomJogo.banco().is_empty():
		return false
	var x := XMLParser.new()
	if x.open(XML) != OK:
		return false
	var pilha: Array = []
	var patch := ""
	var bpatch := ""
	while x.read() == OK:
		var t := x.get_node_type()
		if t == XMLParser.NODE_ELEMENT_END:
			pilha.pop_back()
			continue
		if t != XMLParser.NODE_ELEMENT:
			continue
		var n := x.get_node_name()
		var a := {}
		for k in x.get_attribute_count():
			a[x.get_attribute_name(k)] = x.get_attribute_value(k)
		var caminho := "/".join(pilha)
		if n == "PS2" and caminho.ends_with("MasterSettings"):
			master = a
		elif caminho == "Root/Wheels/Patches":
			patch = n
			patches[patch] = {}
		elif caminho == "Root/Wheels/Patches/" + patch:
			if n == "Looping":
				patches[patch].looping = {"sample": a.get("Sample", ""), "pitch": {}, "volume": {}}
			elif n == "Landing":
				patches[patch].landing = a
		elif caminho == "Root/Wheels/Patches/%s/Looping" % patch:
			patches[patch].looping[n.to_lower()] = a
		elif caminho == "Root/Wheels/Materials":
			materiais[n] = a
		elif caminho == "Root/Vehicles/Suspension/Buggy":
			susp[n] = a
		elif caminho == "Root/Collisions/InteractiveObjects":
			objetos_som[n] = a
		elif caminho == "Root" and n == "Collisions":
			colisoes = a
		elif caminho == "Root/Collisions/Patches":
			bpatch = n
			batida_patches[bpatch] = {}
		elif caminho == "Root/Collisions/Patches/" + bpatch:
			batida_patches[bpatch][n] = a
		elif caminho == "Root/Vehicles/Model" and n == car.vehicle_id:
			modelo = a
		if not x.is_empty():
			pilha.append(n)
	for k in 3:
		var o := SomJogo.new()
		o.name = ["RodaFL", "RodaRL", "RodaFL2"][k]
		o.ganho = GANHO_PNEU
		o.ancora = _ancora()
		add_child(o)
		rodas.append({"som": o, "idx": 0 if k != 1 else 1, "sec": k == 2, "trava": 0.0,
			"mat": -2, "s": 0.0, "vol": 0.0})
	raspa = SomJogo.new()
	raspa.name = "Raspao"
	raspa.ganho = GANHO
	raspa.ancora = _ancora()
	add_child(raspa)
	_prepara()
	liga_cpp()
	return not patches.is_empty()


## (re)liga o laço das rodas em C++ conforme o carro_base.usar_cpp (F3)
func liga_cpp() -> void:
	_cpp = null
	if preload("res://carro/carro_base.gd").usar_cpp and ClassDB.class_exists("SomPneuCpp"):
		_cpp = ClassDB.instantiate("SomPneuCpp")
		if not _cpp.configurar(self):
			_cpp = null


func _f(d: Dictionary, k: String, padrao := 0.0) -> float:
	return float(d.get(k, padrao))


## nome do material de som do chão embaixo da roda (SFX do materials_rx01.xml)
func _sfx_chao(m: int) -> String:
	if car.terrain and car.terrain.has_method("sfx"):
		return car.terrain.sfx(m)
	return "Dirt"


func passo(dt: float, v_l: float, v_f: float) -> void:
	if car == null or car.jit_order.size() != 4:
		return
	var v: float = car.linear_velocity.length()
	spd = _curva(v * 0.015981533)
	side = _curva(absf(v_l) * 0.03729024)
	ws = 0.0
	var trava := false
	for w in car.wheels:
		if w.sr > 0.2 and absf(w.omega * w.r - v_f) > PATINA_MIN:
			ws += 0.5
		if w.hit and w.sr < -0.95 and v > 2.2347221:
			trava = true
	ws = minf(ws, 1.0)
	var alvo := clampf(maxf(maxf(side * DERRAPA_SIDE, ws), 1.0 if trava else 0.0), 0.0, 1.0)
	derrapa += (alvo - derrapa) * (1.0 - exp(-dt / (DERRAPA_SOBE if alvo > derrapa else DERRAPA_DESCE)))
	if not (_cpp and _cpp.rodas_passo(dt, v, spd, side, ws, derrapa)):
		for o in rodas:
			_roda(o, dt, v)
	_suspensao(dt, v_f)
	_pouso()


static func _curva(x: float) -> float:
	if x < 0.025:
		x = 40.0 * x * x
	return minf(x, 1.0)


func _roda(o: Dictionary, dt: float, v: float) -> void:
	var ri: int = car.jit_order[o.idx]
	var w: Dictionary = car.wheels[ri]
	var m: int = maxi(w.mat, 0)                # 0x158: -1 vira o material 0
	var mat: Dictionary = materiais.get(_sfx_chao(m), materiais.get("Default", {}))
	# 0x370548: na água (veículo+0xae8) com a roda a mais de -5 cm da superfície
	# (veículo+0xaec+4i > -0.05) o material de som é o "Water" do SoundDatabase
	if car.agua != null and car.agua_prof[ri] > -0.05 and materiais.has("Water"):
		m = -3
		mat = materiais["Water"]
	var p: Dictionary = patches.get(mat.get("SecondaryPatch" if o.sec else "SurfacePatch", "Default"), {})
	var som: SomJogo = o.som
	if not p.has("looping") or _f(p.looping.volume, "Volume") == 0.0:
		if som.tocando:
			som.parar()
		o.vol = 0.0
		return
	var lp: Dictionary = p.looping
	# troca de chão: muda o sample (com 0.07 s sem trocar de novo) e o volume
	# leva o AttackLevel nesse passo
	var ataque := false
	if o.trava <= 0.0:
		if m != o.mat:
			o.mat = m
			ataque = true
		if lp.sample != som.nome or not som.tocando:
			som.tocar("Surface", lp.sample)
			o.trava = 0.07
	else:
		o.trava -= dt
	var vol := 0.0
	if w.hit:
		var s := clampf((w.x + _f(modelo, "SuspensionOffset")) * _f(modelo, "SuspensionScale", 3.4375), 0.0, 1.0)
		o.s = s
		var trava: bool = w.sr < -0.95 and v > 2.2347221
		var pv: Dictionary = lp.volume
		var pp: Dictionary = lp.pitch
		vol = _f(pv, "MinSpeed") + spd * (_f(pv, "MaxSpeed") - _f(pv, "MinSpeed"))
		if spd < 0.025:
			vol *= 40.0 * spd
		vol += side * _f(pv, "SideSpeed") + ws * _f(pv, "Wheelspin")
		if trava:
			vol += _f(pv, "WheelLock")
		if ataque:
			vol += _f(pv, "AttackLevel")
		vol *= (absf(car.steer) * _f(pv, "Steer") + 1.0) * (car.throttle * _f(pv, "Acc") + 1.0)
		vol = (vol - vol * (1.0 - s) * _f(pv, "Suspension")) * _f(pv, "Volume")
		if vol < _f(pv, "MinThreshold"):
			vol = 0.0
		else:
			vol *= _f(mat, "Volume", 1.0)
			if vol < o.vol:
				vol = o.vol - (o.vol - vol) * (1.0 - _f(pv, "DecayRate"))
			vol *= _f(master, "SFXVolume", 1.0) * _f(master, "SurfaceVolume", 0.5)
		var tom := _f(pp, "Pitch", 1.0) + spd * _f(pp, "Speed") + side * _f(pp, "SideSpeed") + ws * _f(pp, "Wheelspin")
		if trava:
			tom += _f(pp, "WheelLock")
		tom = (tom + absf(car.steer) * _f(pp, "Steer") + car.throttle * _f(pp, "Acc")
			+ o.idx * _f(pp, "WheelDiff") + s * _f(pp, "Suspension")) * _f(mat, "Pitch", 1.0)
		som.tom = tom
	o.vol = maxf(vol, 0.0)
	som.volume = o.vol * (ROLAGEM + (1.0 - ROLAGEM) * derrapa if SO_DERRAPANDO else 1.0)


## CPU: os números do XML (texto) convertidos uma vez (antes: float("...")
## de cada atributo a cada passo). _prepara() no fim do carregar()
var _m_coll := 0.8                # master CollisionVolume
var _m_sfx := 1.0                 # master SFXVolume
var _susp_n := {}                 # Small/Large -> [Volume, Threshold, Probability, VolumeSpeed, MinRetriggerTime, FirstSample]


func _prepara() -> void:
	_m_coll = _f(master, "CollisionVolume", 0.8)
	_m_sfx = _f(master, "SFXVolume", 1.0)
	for k in ["Small", "Large"]:
		var a: Dictionary = susp.get(k, {})
		_susp_n[k] = [_f(a, "Volume"), _f(a, "Threshold"), _f(a, "Probability"), _f(a, "VolumeSpeed"),
			_f(a, "MinRetriggerTime", 0.25), a.get("FirstSample", "")]


func _suspensao(dt: float, v_f: float) -> void:
	if absf(v_f) < car.SUSP_VEL:                # 0x418: velocidade pra frente
		return
	for k in ["Small", "Large"]:
		var a: Array = _susp_n[k]
		if a[0] < 0.05:
			continue
		if _susp_ret[k] > 0.0:
			_susp_ret[k] -= dt
			if _susp_ret[k] > 0.0:
				continue
		var acima: bool = car.susp_taxa > a[1]
		if not acima:
			_susp_flag[k] = false
		elif not _susp_flag[k]:
			if randf() < a[2]:
				var vol: float = (1.0 - a[3] * (1.0 - spd)) * _m_coll * _m_sfx * a[0]
				_tocar_uma("Coll_Big", a[5], vol, 1.0)
				_susp_ret[k] = a[4]
			_susp_flag[k] = true


func _pouso() -> void:
	if car.pouso <= 0.0:
		return
	var w: Dictionary = car.wheels[car.jit_order[0]]
	var mat: Dictionary = materiais.get(_sfx_chao(maxi(w.mat, 0)), {})
	var p: Dictionary = patches.get(mat.get("SurfacePatch", "Default"), {})
	if not p.has("landing"):
		return
	var l: Dictionary = p.landing
	var vol: float = car.pouso * _f(l, "Volume") * _f(l, "Volume") * _f(master, "SFXVolume", 1.0)
	if vol > 0.0:
		_tocar_uma(l.get("Bank", "Coll_Big"), l.get("FirstSample", ""), vol, _f(l, "Pitch", 1.0))


## batida em objeto da pista (0x36b998, chamado pelo 0x153390 em cada contato
## do carro com o objeto): o CollisionSample do InstanceDatabase.xml ->
## Collisions/InteractiveObjects; volume = Volume x CollisionVolume (0.8) x
## SFXVolume, tom = Pitch, no carro (o jogo passa a posição do veículo)
func batida_objeto(amostra: String) -> void:
	var e: Dictionary = objetos_som.get(amostra, {})
	if e.is_empty():
		return
	var vol := _f(e, "Volume", 1.0) * _f(master, "CollisionVolume", 0.8) * _f(master, "SFXVolume", 1.0)
	batidas.append([amostra, e.get("FirstSample", ""), vol])     # conferência (teste_quebra)
	_tocar_uma(e.get("Bank", "Coll_Big"), e.get("FirstSample", ""), vol, _f(e, "Pitch", 1.0))


## 0x36e7a8 (a cada quadro, por veículo): som da batida com o mundo.
## c = contato do casco mais forte do passo (corpo+0x7a0 + 0x860 x 0x40), {}
## sem contato: vn = velocidade na normal (+0x00), r = ponto do contato menos
## o centro do corpo (+0x20), mat = tem material (+0x30; chão e paredes do
## RX01 têm). v = velocidade do corpo.
##  - espera do retrigger (som+0x498) e do raspão (som+0x49c) descem dt; com
##    o raspão > 0 o loop Scraping do patch toca (volume do patch x
##    CollisionVolume x SFXVolume), com 0 ele solta (key-off);
##  - patch: com material = a entrada do material na tabela Materials; as 24
##    entradas são "Default" (0x377ba8), que pede o patch "Small", que não
##    existe: a busca (0x11db48) devolve o 1º, "Default". Sem material =
##    "Vehicle" (Collisions+0x18);
##  - |v| < 2.5 mph (0x55186c): nada;
##  - vn > SmallThreshold (0.5) e a espera acabada: Small, ou Large com vn >
##    LargeThreshold (20); espera = MinRetriggerTime (0.2);
##  - |r̂ . v̂| > 0.7 (o contato na direção do movimento): raspão por
##    MinScrapeTime (0.25 s).
## Objetos interativos (outro tipo 9) são o batida_objeto; carro x carro (tipo
## 2, patch Vehicle) chega pelo car.contato_carro (carro/batida_carros.gd).
func batida_passo(dt: float, c: Dictionary, v: Vector3) -> void:
	var livre := true
	if _bat_ret > 0.0:
		_bat_ret -= dt
		livre = _bat_ret < 0.0
		if livre:
			_bat_ret = 0.0
	var vol_bat := clampf(_m_coll * _m_sfx, 0.0, 1.0)
	if _raspa_t == 0.0:
		if raspa.tocando:
			raspa.parar()
	else:
		_raspa_t = maxf(_raspa_t - dt, 0.0)
		var sc: Dictionary = batida_patches.get(_raspa_patch, {}).get("Scraping", {})
		var b := String(sc.get("Bank", ""))
		var n := String(sc.get("Sample", ""))
		if raspa.nome != n or not raspa.tocando:
			raspa.tocar(b, n)
		raspa.volume = _f(sc, "Volume", 1.0) * vol_bat
		raspa.tom = _f(sc, "Pitch", 1.0)
	if c.is_empty():
		return
	_raspa_patch = "Default" if c.get("mat", true) else "Vehicle"
	var vel := v.length()
	if vel < 2.5 * 0.44694445:
		return
	var vn: float = c.vn
	if vn > _f(colisoes, "SmallThreshold", 0.5) and livre:
		var grande := vn > _f(colisoes, "LargeThreshold", 20.0)
		var e: Dictionary = batida_patches.get(_raspa_patch, {}).get("Large" if grande else "Small", {})
		if not e.is_empty():
			var vol := _f(e, "Volume", 1.0) * vol_bat
			batida_tocadas.append([_raspa_patch, e.get("FirstSample", ""), vol])
			_tocar_uma(e.get("Bank", "Coll_Big"), e.get("FirstSample", ""), vol, _f(e, "Pitch", 1.0))
		_bat_ret = _f(colisoes, "MinRetriggerTime", 0.2)
	var r: Vector3 = c.r
	if vel > 1e-6 and r.length_squared() > 1e-12 and absf(r.normalized().dot(v / vel)) > 0.7:
		_raspa_t = _f(colisoes, "MinScrapeTime", 0.25)


func _tocar_uma(b: String, n: String, vol: float, tom: float) -> void:
	var vivos: Array = []
	for s in _uma_vez:
		if s.tocando:
			vivos.append(s)
		else:
			s.queue_free()
	_uma_vez = vivos
	if not SomJogo.existe(b, n):
		return
	var s := SomJogo.new()
	s.ganho = GANHO
	s.volume = vol
	s.tom = tom
	s.ancora = _ancora()
	add_child(s)
	s.tocar(b, n)
	_uma_vez.append(s)


## conferência (tests/teste_sfx.gd): [nome, volume, tom] de cada roda
## rival além do alcance do som 3D (ia.gd): pneus, raspão e sons curtos param
## na hora (inaudíveis, mas seguiam tocando e sendo calculados). Voltando pra
## perto, o passo religa (tocar() no _roda / rodas_passo do C++)
func calar() -> void:
	for o in rodas:
		o.som.calar()
	if raspa:
		raspa.calar()
	for s in _uma_vez:
		if is_instance_valid(s):
			s.queue_free()
	_uma_vez.clear()


func estado() -> Array:
	var out: Array = []
	for o in rodas:
		out.append([o.som.nome, o.vol, o.som.tom])
	return out


## rival da IA: o som sai do carro (3D); o jogador: 2D como sempre
func _ancora() -> Node3D:
	return car if car and car.get("som_3d") else null
