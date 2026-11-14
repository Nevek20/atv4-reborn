extends RefCounted
## Cérebro dos rivais (nov/2026): o comportamento #5 "ultrapassar" do jogo
## (0x360aa8) e a percepção dos vizinhos que ele usa (0x353b68 + 0x354d20).
## Do exe e dos saves tentando_ultrapassar, tentando_passar_2 e
## andando_em_linha_reta (docs/engenharia_reversa.md, Cérebro da IA;
## re/ia_vizinhos_ram.py lê a percepção da RAM). pista/ia.gd (_pensar) chama
## percepcao, prioridade, comecar e atualizar a cada passo de cada rival
## correndo; os dados de cada carro no passo (dados_carro) vêm feitos na
## lista de carros (ia._monta_carros), 1 vez por passo.
##
## Como o jogo escolhe (0x35e8a0): o #7 (corrida na linha, prioridade 0.1)
## não segura a vez, então todo passo o cérebro olha as prioridades; o #5 vale
## 1.0 quando acha um alvo e segura a vez até a máquina de fases acabar.
##
## Lateral: o jogo conta do zero da rota pra borda +0x6c do link; o nosso
## mundo é espelhado (mundo = (z, y, x) do jogo), então a lateral do jogo é
## -(a nossa, do zero). Aqui tudo é na do jogo (ia.lat_jogo / bordas_jogo) e
## vira a nossa só na saída (x.pede_lat).
##
## NOSSO: a caixa da IA de cada carro (ver caixa()), o +0xf0 do objeto (<= 2
## pro #5 rodar; 0 nos 3 saves) sempre ok e a ficha nunca vem de fora da rota
## (todos os corredores estão na rota do RX01: +0x38 = +0x3c = 1 na RAM).

# piloto->[0]+0x118 (RAM, os 7 rivais dos 3 saves): 45 m de rota à frente
# (+8) e atrás (+0xc); a ficha vence 5 s (+0x1c) depois da última vez visto
const VIZ_ALCANCE := 45.0
const VIZ_VENCE := 5.0
const TTC_MAX := 20.0            # 0x354d20: tempo até bater só conta abaixo de 20 s
const TTC_PERTO := 10.0          # 0x3614a0: batida prevista em 0..10 s
const ATIVA_N := 10              # 0x360c10: o mesmo alvo sem batida prevista > 10 vezes seguidas
const FOLGA := 1.0               # 0x3614a0: meia largura + 1 m + meia largura do alvo
const COLADO := 2.0              # 0x3612b0: para-choque a menos de 2 m -> fase 1
const V_MIN_ALVO := 4.4694443    # 0x362100: alvo abaixo de 10 mph aborta a fase 1
const SEGUE := 0.95              # 0x3622d0: fase 1 anda a 95% do alvo
const V_FUGA := 8.938889         # 0x3626c8: na fase 2 não desce de 20 mph
const AFASTA := 1.0              # 0x362bc0: alvo se afastando > 1 m/s ...
const AFASTA_T := 1.0            # ... por mais de 1 s: acabou
const RELOGIO := 5.0             # 0x3614a0: DAT_007f4820+0x24 (relógio) > 5 s
# Skill do piloto (*piloto+0x100, 0x3535f0): slots 1, 3 e 4 = 1, 1 e 0.1 só
# com rivalidade (0x35b1b0); offline todos 0 (RAM). Com 0 a fase 0 nunca é
# escolhida (0x3612b0 / 0x361aa8) e o contato não muda nada (0x3552f8)
const SKILL3 := 0.0
const DV_PARALELO := [0.0, 4.4694443]   # DAT_00837e40 / 44: |dv| < lerp(isso, Skill 3)
const COS_PARALELO := 0.9397             # DAT_00837e48: cos 20°
# alcance do ponto da direção (0x359730: clamp(esc x v, mín, máx))
const OLHA := Vector3(0.5, 15.0, 50.0)   # 0x5ae6f0..f8
const FIM := 0xfe                # fase acabou bem
const ABORTA := 0xff
const NADA := 0xfd

# caixa da IA (objeto +0x08..+0x20, raio +0xc0, meia largura +0xf4) na RAM
# (rival 2 do tentando_passar_2): a de um carro sem casco
const CAIXA_PADRAO := Vector3(1.088, 0.8715, 2.9)
static var _caixas := {}


## caixa da IA de um carro: meia largura hx, meio comprimento hz e o raio r
## (meia diagonal 3D), centrada no CoM (objeto +0x30 = CoM no plano). No jogo
## vem do carro (RAM: hx 1.04..1.19, hz 2.51..2.90, r 2.93..3.22); NOSSO: a
## metade da caixa dos vértices do VehicleWorld.hsc (o casco do carro;
## data/vehicles/<id>_casco.json), ou das esferas
static func caixa(car) -> Dictionary:
	var id := String(car.get("vehicle_id")).to_lower()
	if _caixas.has(id):
		return _caixas[id]
	var h := CAIXA_PADRAO
	var path := "res://data/vehicles/%s_casco.json" % id
	if FileAccess.file_exists(path):
		var info = JSON.parse_string(FileAccess.get_file_as_string(path))
		if info is Dictionary:
			var pts: Array = []
			for v in info.get("vertices", []):
				pts.append(Vector3(v[0], v[1], v[2]))
			if pts.is_empty():
				for e in info.get("esferas", []):
					var r: float = e[3]
					pts.append(Vector3(e[0] - r, e[1] - r, e[2] - r))
					pts.append(Vector3(e[0] + r, e[1] + r, e[2] + r))
			if not pts.is_empty():
				var lo: Vector3 = pts[0]
				var hi: Vector3 = pts[0]
				for p in pts:
					lo = lo.min(p)
					hi = hi.max(p)
				h = (hi - lo) * 0.5
	var cx := {"hx": h.x, "hz": h.z, "r": h.length()}
	_caixas[id] = cx
	return cx


## dados de um carro no passo (ia._monta_carros: 1 vez por passo, lidos por
## todos que olham pra ele): CoM (objeto +0x30 = o CoM no plano), bico no
## plano (+0x90), s na rota, lateral e bordas do jogo ali, a caixa, a pegada
## (0x34df50 / 0x34dff8: a caixa no CoM girada pelo bico, como [centro, bico,
## meia largura, meio comprimento]) e a velocidade no plano (+0x40) e |v| (+0xa0)
static func dados_carro(ia, car, r: Dictionary) -> Dictionary:
	var xf: Transform3D = car.global_transform
	var cm: Vector3 = xf * car.center_of_mass
	var s: float = float(r.get("prog", 0.0)) + ia.s_linha
	var zb: Vector3 = ia.zero_bordas(s)
	var lv: Vector3 = car.linear_velocity
	var cx := caixa(car)
	var f := Vector2(xf.basis.z.x, xf.basis.z.z).normalized()
	var p := Vector2(cm.x, cm.z)
	return {"cm": cm, "p": p, "f": f, "s": s, "l": -(ia._lateral(cm, s) - zb.x),
		"lo": zb.x - zb.z, "hi": zb.x - zb.y, "cx": cx,
		"forma": [p, f, float(cx.hx), float(cx.hz), Vector2(cx.hx, cx.hz).length()],
		"vel": Vector2(lv.x, lv.z), "v": lv.length()}


## 0x34e0c0: as pegadas A e B se movendo com a velocidade relativa vel (a de B
## menos a de A): SAT com tempo. Eixos = as normais dos lados (numa caixa, o
## bico e o lado de cada uma; os lados paralelos e a ordem dão a mesma conta),
## projeção da caixa = centro +- (meio comprimento |bico.n| + meia largura
## |lado.n|). Devolve o tempo até encostar (0 se já encostam) ou -1 se não
## bate. CPU (NOSSO, mesmo resultado): antes, os círculos que envolvem as
## caixas; se eles não se tocam antes de t_max, as caixas também não
static func varredura(a: Array, b: Array, vel: Vector2, t_max := INF) -> float:
	var ca: Vector2 = a[0]
	var cb: Vector2 = b[0]
	var rel := cb - ca
	var rr: float = float(a[4]) + float(b[4])
	var c0 := rel.length_squared() - rr * rr
	if c0 > 0.0:
		var bq := rel.dot(vel)
		if bq >= 0.0:
			return -1.0                 # se afastando (ou parados): nunca mais perto
		var vv := vel.length_squared()
		var disc := bq * bq - vv * c0
		if disc < 0.0 or (-bq - sqrt(disc)) >= t_max * vv:
			return -1.0
	var fa: Vector2 = a[1]
	var fb: Vector2 = b[1]
	var hxa: float = a[2]
	var hza: float = a[3]
	var hxb: float = b[2]
	var hzb: float = b[3]
	var la := Vector2(fa.y, -fa.x)
	var lb := Vector2(fb.y, -fb.x)
	var t0 := 0.0
	var t1 := 9e30
	for k in 4:
		var n: Vector2 = fa if k == 0 else (la if k == 1 else (fb if k == 2 else lb))
		var sp := n.dot(vel)
		var pa := ca.dot(n)
		var ra := hza * absf(fa.dot(n)) + hxa * absf(la.dot(n))
		var pb := cb.dot(n)
		var rb := hzb * absf(fb.dot(n)) + hxb * absf(lb.dot(n))
		if pb + rb < pa - ra:
			if sp <= 0.0:
				return -1.0
			t0 = maxf(t0, (pa - ra - pb - rb) / sp)
			t1 = minf(t1, (pa + ra - pb + rb) / sp)
		elif pa + ra < pb - rb:
			if sp >= 0.0:
				return -1.0
			t0 = maxf(t0, (pa + ra - pb + rb) / sp)
			t1 = minf(t1, (pa - ra - pb - rb) / sp)
		elif sp > 0.0:
			t1 = minf(t1, (pa + ra - pb + rb) / sp)
		elif sp < 0.0:
			t1 = minf(t1, (pa - ra - pb - rb) / sp)
		if t1 < t0:
			return -1.0
	return t0


## 0x3591f0: setor do outro pelo bico: à frente 0/1, atrás 2/3; 0/2 = do lado
## da lateral menor do jogo, que no nosso mundo espelhado é o da maior
static func setor(f: Vector2, rel: Vector2) -> int:
	if rel.length_squared() < 1e-12:
		return 1
	var n := rel.normalized()
	var lado_maior := n.dot(Vector2(f.y, -f.x)) < 0.0      # (bico x rel).y > 0 no jogo
	if n.dot(f) < 0.0:
		return 3 if lado_maior else 2
	return 1 if lado_maior else 0


## percepção (a cada passo): os corredores a menos de 45 m de rota viram
## fichas (0x353d60 / 0x3547f0): setor, distância de rota (+0x28) e lateral
## (+0x2c, contada da borda esquerda) sem sinal, as taxas delas (+0x30 /
## +0x34; ficha nova = 0) e os dados dele no passo (d: a lateral +0x40, a
## pegada +0x50...). Não visto no passo: inválida; 5 s sem ver: some. Depois
## (0x354d20): tempo até bater com cada um (0x34e0c0, < 20 s, senão -1), as 4
## vagas (por setor, o que bate primeiro) e o recuo (+0x64: o da frente
## chegando mais rápido). lista = ia._monta_carros()
static func percepcao(ia, x: Dictionary, car, dt: float, lista: Array) -> void:
	var t: float = ia.corrida.t
	if not x.has("viz"):
		x.viz = {}
	var viz: Dictionary = x.viz
	var comp: float = ia.comp
	var me: Dictionary = {}
	for e: Array in lista:
		if e[0] == car:
			me = e[4]
			break
	if me.is_empty():
		me = dados_carro(ia, car, x.r)
	x.me = me
	var s_me: float = me.s
	var p_me: Vector2 = me.p
	var f_me: Vector2 = me.f
	var lb_me: float = float(me.l) - float(me.lo)
	for e: Array in lista:
		var o = e[0]
		if o == car:
			continue
		var d: Dictionary = e[4]
		var ds: float = fposmod(float(d.s) - s_me + comp * 0.5, comp) - comp * 0.5
		if absf(ds) >= VIZ_ALCANCE:
			continue
		var dl := absf(ds)
		var dlat := absf(float(d.l) - float(d.lo) - lb_me)
		var st := setor(f_me, (d.p as Vector2) - p_me)
		var info = viz.get(o)
		if info == null:
			info = {"setor": 5, "taxa_l": 0.0, "taxa_lat": 0.0, "dl": dl, "dlat": dlat}
			viz[o] = info               # ficha nova: taxas 0 (0x354b68 / 0x3547f0)
		else:
			var antigo: int = info.setor
			info.taxa_l = (dl - float(info.dl) if (antigo < 2) == (st < 2) else dl) / dt
			var a0 := antigo == 0 or antigo == 2
			var a1 := st == 0 or st == 2
			info.taxa_lat = (dlat - float(info.dlat) if a0 == a1 else dlat) / dt
		info.valida = true
		info.visto = t
		info.vence = t + VIZ_VENCE
		info.setor = st
		info.dl = dl
		info.dlat = dlat
		info.d = d
	var some: Array = []
	for o in viz:
		var info: Dictionary = viz[o]
		if float(info.visto) < t:
			info.valida = false
			if float(info.vence) < t or not is_instance_valid(o):
				some.append(o)
	for o in some:
		viz.erase(o)
	var vagas := [null, null, null, null]
	var recuo = null
	var menor := 0.0
	var forma: Array = me.forma
	var v_me: Vector2 = me.vel
	for o in viz:
		var info: Dictionary = viz[o]
		if not info.valida:
			continue
		var tt := varredura(forma, info.d.forma, (info.d.vel as Vector2) - v_me, TTC_MAX)
		if tt < 0.0 or tt >= TTC_MAX:
			info.ttc = -1.0
		else:
			info.ttc = tt
			var k: int = info.setor
			if vagas[k] == null or tt < float(viz[vagas[k]].ttc):
				vagas[k] = o
		if int(info.setor) < 2 and float(info.taxa_l) < menor:
			recuo = o
			menor = info.taxa_l
	x.vagas = vagas
	x.recuo = recuo


## raio da caixa de quem a ficha aponta (+0xc0)
static func _raio(info: Dictionary) -> float:
	return float(info.d.cx.r) if info.has("d") else CAIXA_PADRAO.length()


## 0x360e30: alvo = o das vagas da frente com a menor batida prevista (a vaga
## 0 sempre conta); atrás só quem já está lado a lado (para-choques
## sobrepostos); sem nenhum, o recuo. [carro, ficha] ou []
static func busca(x: Dictionary) -> Array:
	var viz: Dictionary = x.get("viz", {})
	var vagas: Array = x.get("vagas", [])
	var alvo = null
	var melhor := 9e30
	var r_me: float = x.me.cx.r
	for k in vagas.size():
		var o = vagas[k]
		if o == null or not viz.has(o):
			continue
		var info: Dictionary = viz[o]
		var ttc: float = info.ttc if info.valida else 9e30
		if k == 0:
			alvo = o
			melhor = ttc
		elif ttc < melhor and (k == 1 or float(info.dl) - (r_me + _raio(info)) <= 0.0):
			alvo = o
			melhor = ttc
	var rc = x.get("recuo")
	if alvo == null and rc != null and viz.has(rc):
		alvo = rc
	return [alvo, viz[alvo]] if alvo != null else []


## 0x360c10: prioridade do #5 (corredor correndo e 0x361238 ok): com alvo e
## batida prevista, na hora; sem batida (o recuo), depois de mais de 10
## passos seguidos com o mesmo alvo
static func prioridade(x: Dictionary) -> bool:
	var b := busca(x)
	if b.is_empty():
		return false
	var info: Dictionary = b[1]
	var ttc: float = info.ttc if info.valida else 0.0
	var id: int = (b[0] as Object).get_instance_id()
	if ttc == -1.0:
		x.p5_n = int(x.get("p5_n", 0)) + 1 if x.get("p5_alvo", 0) == id else 0
	else:
		x.p5_n = 0
	x.p5_alvo = id
	return ttc != -1.0 or int(x.p5_n) > ATIVA_N


## 0x360d00: começa o #5 com o alvo da prioridade: plano (0x3612b0) e entra na
## fase (0x367298). Devolve false se já acabou
static func comecar(ia, x: Dictionary) -> bool:
	x.f5 = {"alvo": instance_from_id(int(x.p5_alvo)), "lat1": 0.0, "lat2": 0.0, "fase": NADA, "t": 0.0}
	var p := _plano(ia, x)
	x.f5.fase = p
	_troca(ia, x, _entra(ia, x, p))
	return int(x.f5.fase) < FIM


## 0x360dd8: roda a fase atual (0x3673e0). Devolve false quando o #5 acaba
static func atualizar(ia, x: Dictionary, dt: float) -> bool:
	_troca(ia, x, _atualiza(ia, x, int(x.f5.fase), dt))
	return int(x.f5.fase) < FIM


## 0x3671a8: troca de fase (a entrada pode devolver outra, em cadeia)
static func _troca(ia, x: Dictionary, nova: int) -> void:
	var f5: Dictionary = x.f5
	while nova != int(f5.fase):
		f5.fase = nova
		if nova >= FIM:
			return
		nova = _entra(ia, x, nova)


## 0x361238 + 0x3611d8: o alvo ainda é um vizinho visto neste passo
static func _ficha(x: Dictionary) -> Dictionary:
	var o = x.f5.alvo
	if o == null or not is_instance_valid(o):
		return {}
	var info: Dictionary = x.viz.get(o, {})
	if info.is_empty() or not info.valida:
		return {}
	return info


## 0x3612b0: plano (fase inicial). Sem espaço do lado (0x3614a0 falso): 1
## (seguir colado) com o para-choque a menos de 2 m, senão 4 (sair pro lado
## do alvo). Com espaço: 2 com batida prevista (desviar), senão 3 (passar)
static func _plano(ia, x: Dictionary) -> int:
	var o = x.f5.alvo
	var info: Dictionary = x.viz.get(o, {}) if o != null else {}
	var valida: bool = not info.is_empty() and info.valida
	if not _lado_livre(ia, x, info):
		var dist: float = info.dl if valida else 0.0
		var r_me: float = x.me.cx.r
		var r_o: float = _raio(info) if not info.is_empty() else CAIXA_PADRAO.length()
		var f9 := r_o - dist if valida and int(info.setor) >= 2 else r_o + dist
		if r_me <= f9:
			return 1 if maxf(dist - (r_me + r_o), 0.0) < COLADO else 4
		return 4
	if _paralelo(x, info):
		return 0
	var ttc: float = info.ttc if valida else 0.0
	return 2 if ttc >= 0.0 else 3


## 0x361aa8: lado a lado na mesma velocidade e rumo (só com a Skill 3 > 0)
static func _paralelo(x: Dictionary, info: Dictionary) -> bool:
	if info.is_empty():
		return false
	var lim: float = lerpf(DV_PARALELO[0], DV_PARALELO[1], SKILL3)
	if lim <= 0.0 or not info.has("d"):
		return false                    # sem rivalidade: |dv| < 0 nunca
	return absf(float(x.me.v) - float(info.d.v)) < lim and (x.me.f as Vector2).dot(info.d.f) > COS_PARALELO


## 0x3614a0: acha a lateral pra passar o alvo (ctx[1]) e a borda do lado
## (ctx[2]). Folga = minha meia largura + 1 m + a dele. Com batida prevista
## em 0..10 s, vai pro lado contrário ao dele em relação a mim; sem, pro lado
## contrário ao dele em relação ao zero. A lateral = a dele + a folga (ou a
## minha, se já estou além), não cruza o zero (relógio > 5 s) e fica dentro da
## borda menos a meia largura + 1 m. Livre se ficou mais longe dele que a
## folga (o PS2 corta o arredondamento: dele + folga exata NÃO é livre, só
## quem já está além) e, com batida prevista, a minha pegada indo pro ponto da
## borda não bate nele (0x361ba8). Tenta o outro lado se o 1º não der
static func _lado_livre(ia, x: Dictionary, info: Dictionary) -> bool:
	var o = x.f5.alvo
	var valida: bool = not info.is_empty() and info.valida
	var hw: float = x.me.cx.hx
	var folga: float = hw + FOLGA + (float(info.d.cx.hx) if info.has("d") else CAIXA_PADRAO.x)
	var l_me: float = x.me.l
	var l_o: float
	var s_o: float
	if valida:
		l_o = info.d.l                  # +0x3c = 1: a posição de rota dele (+0x40)
		s_o = info.d.s
	else:
		l_o = l_me
		s_o = x.me.s
	var ttc: float = info.ttc if valida else 0.0
	var perto := true
	var menor: bool
	if ttc < 0.0 or ttc > TTC_PERTO:
		menor = l_o < 0.0
		perto = false
	else:
		menor = l_o < l_me
	var sinal := 1.0 if menor else -1.0
	var bs: Vector2 = ia.bordas_jogo(s_o)
	var lim_lo: float = bs.x + hw + FOLGA
	var lim_hi: float = bs.y - hw - FOLGA
	var tarde: bool = ia.corrida.t > RELOGIO
	var r1 := _um_lado(sinal * folga, l_me - l_o, l_o, lim_lo, lim_hi, tarde, folga)
	if r1[2] and (not perto or _caminho_livre(ia, x, o, s_o, r1[1])):
		x.f5.lat1 = r1[0]
		x.f5.lat2 = r1[1]
		return true
	var r2 := _um_lado(-sinal * folga, l_me - l_o, l_o, lim_lo, lim_hi, tarde, folga)
	if r2[2] and (not perto or _caminho_livre(ia, x, o, s_o, r2[1])):
		x.f5.lat1 = r2[0]
		x.f5.lat2 = r2[1]
		return true
	x.f5.lat1 = r1[0]
	x.f5.lat2 = r1[1]
	return false


## um lado do 0x3614a0: [lateral pra passar, borda do lado, livre]
static func _um_lado(off: float, d_me: float, l_o: float, lim_lo: float, lim_hi: float, tarde: bool, folga: float) -> Array:
	var exata := true                   # dele + folga exata (o PS2 não passa no teste)
	if off < 0.0 and d_me < off or off > 0.0 and off < d_me:
		off = d_me                      # já estou além: fico onde estou
		exata = false
	var pas := l_o + off
	if tarde and off * pas < 0.0:
		pas = 0.0
		exata = false
	var lim := lim_lo if off < 0.0 else lim_hi
	if off < 0.0 and pas < lim or off >= 0.0 and lim < pas:
		pas = lim
		exata = false
	return [pas, lim, not exata and folga < absf(l_o - pas)]


## 0x361ba8: a minha pegada indo pro ponto da borda (na rota dele) não bate na
## dele. A velocidade "minha" é (ponto - eu) x |v|, sem normalizar como no
## exe: na prática um raio do carro até o ponto
static func _caminho_livre(ia, x: Dictionary, o, s_o: float, lat_jogo: float) -> bool:
	var info: Dictionary = x.viz.get(o, {})
	if info.is_empty() or not info.has("d"):
		return true
	var q: Vector3 = ia.ponto_lat(s_o, -lat_jogo)
	var cm: Vector3 = x.me.cm
	var rel: Vector2 = Vector2(q.x - cm.x, q.z - cm.z) * float(x.me.v)
	return varredura(x.me.forma, info.d.forma, (info.d.vel as Vector2) - rel) < 0.0


## 0x3673e0 -> fase +0x14: entrar (a 1ª passada já dirige)
static func _entra(ia, x: Dictionary, fase: int) -> int:
	var f5: Dictionary = x.f5
	if fase == 2 or fase == 3:
		f5.t = 0.0
	var info := _ficha(x)
	if info.is_empty():
		return ABORTA
	match fase:
		0:
			f5.t = 0.0
			_anda(x, f5.lat1, OLHA)
		1:
			_anda1(x, info)
		2:
			_anda2(x, info)
		3, 4:
			_anda(x, f5.lat1, OLHA)
	return fase


## fase +0x1c: atualizar
static func _atualiza(ia, x: Dictionary, fase: int, dt: float) -> int:
	var f5: Dictionary = x.f5
	if fase == 0 or fase == 2:
		f5.t += dt
	var info := _ficha(x)
	if info.is_empty():
		return ABORTA
	if fase == 1 and float(info.d.v) < V_MIN_ALVO:
		return ABORTA                   # 0x362100: alvo a menos de 10 mph
	var b := busca(x)
	match fase:
		0, 1, 4:
			if b.is_empty() or b[0] != f5.alvo:
				return FIM
			var p := _plano(ia, x)
			if p != fase:
				return p
			if fase == 1:
				_anda1(x, info)
			else:
				_anda(x, f5.lat1, OLHA)
			# 0x361d20: a cada 4..4.5 s sorteados a fase 0 zera o relógio
			if fase == 0 and f5.t >= 4.0 + randf() * 0.5:
				f5.t = 0.0
			return fase
		2:
			if b.is_empty():
				return 3
			if b[0] != f5.alvo:
				return FIM
			var p := _plano(ia, x)
			if p != 2:
				return p
			_anda2(x, info)
			return 2
		3:
			# 0x362bc0: batida prevista de novo -> desviar (2); passou (atrás e
			# sem encostar) ou ele se afastando > 1 m/s por mais de 1 s: acabou
			if not b.is_empty() and float(info.ttc) != -1.0:
				return 2 if b[0] == f5.alvo else ABORTA
			var gap := maxf(float(info.dl) - (float(x.me.cx.r) + _raio(info)), 0.0)
			if int(info.setor) >= 2:
				if gap > 0.0:
					return FIM
			elif float(info.taxa_l) <= AFASTA:
				f5.t = 0.0
			else:
				f5.t += dt
				if f5.t > AFASTA_T:
					return FIM
			_anda(x, f5.lat1, OLHA)
			return 3
	return ABORTA


## saída das fases 0, 3 e 4 (0x361eb8, 0x362df8, 0x363160): anda na rota na
## lateral pedida, alcance padrão, velocidade = a da linha (0x359eb8)
static func _anda(x: Dictionary, lat_jogo: float, olha: Vector3, v_max := INF, v_min := 0.0) -> void:
	x.modo = 2                          # 0x359660(..., 2)
	x.pede_lat = -lat_jogo
	x.olha = olha
	x.v_max = v_max
	x.v_min = v_min


## fase 1 (0x3622d0): na borda do lado (ctx[2]), mirando no alvo (alcance =
## a distância até ele) a 95% da velocidade dele
static func _anda1(x: Dictionary, info: Dictionary) -> void:
	var d: float = info.dl
	_anda(x, x.f5.lat2, Vector3(1.0, d, d), SEGUE * float(info.d.v))


## fase 2 (0x3626c8): batida prevista em f = relógio / tempo até bater (1 se
## já encostam, 0 acima de 1 s): da lateral de passar até a borda (ctx[1] ->
## ctx[2]) e, com o alvo à frente, freia até (1 - f) x a velocidade dele (não
## abaixo de 20 mph). Alcance: alvo atrás = padrão; à frente = o vão entre os
## para-choques (mín. 5 m), ou lado a lado: padrão se há vão lateral, senão 5 m
static func _anda2(x: Dictionary, info: Dictionary) -> void:
	var f5: Dictionary = x.f5
	var ttc: float = info.ttc
	var f := 0.0
	if ttc <= 1.0:
		f = 1.0
		if ttc > 0.0:
			f = f5.t / ttc
	f = clampf(f, 0.0, 1.0)
	var lat: float = f5.lat1 + f * (f5.lat2 - f5.lat1)
	if int(info.setor) >= 2:
		_anda(x, lat, OLHA)
		return
	var soma: float = float(x.me.cx.r) + _raio(info)
	var vao: float = float(info.dl) - soma
	var olha := OLHA
	if vao > 0.0:
		var d := maxf(vao, 5.0)
		olha = Vector3(1.0, d, d)
	elif float(info.dlat) - soma <= 0.0:
		olha = Vector3(1.0, 5.0, 5.0)
	if f > 0.0:
		_anda(x, lat, olha, float(info.d.v) * (1.0 - f), V_FUGA)
	else:
		_anda(x, lat, olha)
