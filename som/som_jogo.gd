extends Node
## Toca um som do jogo (989snd) extraído por tools/sfx_jogo.py pra
## assets/sfx: cada som é um programa de grãos (sons.json), rodado como o
## BlockSoundHandler do 989snd (reimplementado no jak-project, mesma
## biblioteca): o relógio dos grãos anda a 240 Hz e a espera de cada grão vale
## ANTES dele (contagem = espera do próximo + o que o grão devolveu).
##   tom                   toca um .wav (loop se o banco marca loop); volume
##                         do tom < 0 = registrador (-1..-4) ou sorteado (-5)
##   filho                 roda outro som junto, com volume próprio
##   repete / volta        LOOP_START / LOOP_END
##   sorteia n, k          RAND_PLAY: toca k grãos de 1 das n opções, nunca a
##                         mesma da vez anterior
##   espera_sorteada m     RAND_DELAY: soma 0..m à espera do próximo
##   desvio_tom p          RAND_PB: dobra o tom de -p% a +p% da faixa do tom
##                         (PBLow/PBHigh semitons)
##   registrador_sorteado  SET_REGISTER_RAND: registrador r = lo..hi
## No cascalho (GRAVELEMENT1) isso dá ~2.7 estalos de pedrinha por segundo,
## volume 90..115 e tom ±2 semitons; com o relógio de 1 ms de antes eram ~11
## por segundo, todos no máximo e no mesmo tom ("barulho bugado").
## volume (linear, do jeito que o exe calcula) e tom (multiplica a taxa do
## .wav) valem pra todas as vozes do som.
##
## Envelope: cada tom traz o ADSR1/ADSR2 do SPU (sons.json "adsr"), que roda
## a 48 kHz (_env_anda, regras do SPU do PS1/PS2): ataque, decaimento,
## sustentação e, no parar, release. Parar é o StopSound do 989snd (0x264f28
## -> 0x25afa8 -> comando 0x13): key-off, a voz desce pelo release com o
## volume e o tom de quando parou (o jogo troca de handle e só mexe no novo,
## 0x370548). Ex.: Dirt sobe em ~0.5 s e desce em 0.17 s; o loop do cascalho
## (GRAVELEMENT2) entra na hora.

const PASTA := "res://assets/sfx"
const MAX_VOZES := 6
const TICK_HZ := 240.0            # relógio dos grãos do 989snd (48000 / 200)
const SPU_HZ := 48000.0           # o envelope do SPU2 anda um passo por amostra
const ADSR_SECO := [0x80ff, 0x9fc0]   # sem "adsr": entra e sai na hora
const VERSAO := 2                 # sons.json do sfx_jogo.py com ADSR e argumentos

static var _db: Dictionary = {}
static var _cache: Dictionary = {}
static var _anterior: Dictionary = {}     # RAND_PLAY: última opção de cada grão
static var _regs_globais: Array = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

var volume := 1.0
var tom := 1.0
var ganho := 1.0                  # trim nosso (sfx_carro.gd), multiplica o volume
var nome := ""
var _som: Dictionary = {}
var _cursores: Array = []
var _vozes: Array = []            # {p, amp, loop, a1, a2, fase, nivel, vol, tom, cur, pb}
var _soltas: Array = []           # vozes no release (depois do parar)
var _acum := 0.0                  # tempo que sobrou do relógio de 240 Hz
var tocando := false


static func banco() -> Dictionary:
	if _db.is_empty():
		var f := FileAccess.open(PASTA.path_join("sons.json"), FileAccess.READ)
		if f:
			_db = JSON.parse_string(f.get_as_text())
	return _db


## "" ou o que falta (o HUD mostra)
static func aviso() -> String:
	var d := banco()
	if d.is_empty():
		return ""
	if int(d.get("versao", 1)) < VERSAO:
		return "sons do pneu antigos: rode o sfx_jogo"
	return ""


static func existe(b: String, n: String) -> bool:
	var d := banco()
	return not d.is_empty() and d.bancos.has(b) and d.bancos[b].has(n)


func tocar(b: String, n: String) -> void:
	parar()
	if not existe(b, n):
		return
	_som = banco().bancos[b]
	nome = n
	tocando = true
	_acum = 0.0
	_novo_cursor(n, 1.0, [0, 0, 0, 0], 0)


## key-off: as vozes vão pro release com o volume e o tom de agora
func parar() -> void:
	for v in _vozes:
		if v.fase < 3:
			v.fase = 3
		v.vol = volume * ganho * v.amp
		v.tom = tom * _dobra(v)
		_soltas.append(v)
	_vozes.clear()
	_cursores.clear()
	tocando = false
	nome = ""


func _process(dt: float) -> void:
	if tocando:
		_acum += dt
		while _acum >= 1.0 / TICK_HZ:
			_acum -= 1.0 / TICK_HZ
			_tick()
	_vozes = _vivas(_vozes, dt * SPU_HZ)
	_soltas = _vivas(_soltas, dt * SPU_HZ)
	if tocando and _cursores.is_empty() and _vozes.is_empty():
		tocando = false


func _vivas(vozes: Array, ticks: float) -> Array:
	var out: Array = []
	for v in vozes:
		var p: AudioStreamPlayer = v.p
		_env_anda(v, ticks)
		if not p.playing or v.fase == 4:
			p.queue_free()
			continue
		out.append(v)
		_aplicar(v)
	return out


func _aplicar(v: Dictionary) -> void:
	var p: AudioStreamPlayer = v.p
	var solta: bool = v.fase >= 3
	var vol: float = v.vol if solta else volume * ganho * v.amp
	p.volume_db = linear_to_db(maxf(vol * v.nivel / 32767.0, 1e-5))
	p.pitch_scale = clampf(v.tom if solta else tom * _dobra(v), 0.05, 8.0)


## pitch bend do 989snd (PitchBend): pb >= 0 sobe até PBHigh semitons, < 0
## desce até PBLow
static func _dobra(v: Dictionary) -> float:
	var pb: int = v.cur.pb
	var semi: float = v.pb[1] * pb / 32767.0 if pb >= 0 else v.pb[0] * pb / 32768.0
	return pow(2.0, semi / 12.0)


## fase do envelope: [exponencial, sobe, shift, passo, alvo]. ADSR1: 15 ataque
## exponencial, 14-10 shift, 9-8 passo (+7..+4), 7-4 shift do decaimento
## (exponencial, -8), 3-0 nível de sustentação ((n + 1)·0x800). ADSR2: 15
## sustentação exponencial, 14 desce, 12-8 shift, 7-6 passo (+7..+4 ou
## -8..-5), 5 release exponencial, 4-0 shift do release (-8).
static func _fase(a1: int, a2: int, fase: int) -> Array:
	match fase:
		0:
			return [a1 >> 15 == 1, true, (a1 >> 10) & 31, 7 - ((a1 >> 8) & 3), 32767.0]
		1:
			return [true, false, (a1 >> 4) & 15, -8, ((a1 & 15) + 1) * 2048.0]
		2:
			var sobe := (a2 >> 14) & 1 == 0
			var k := (a2 >> 6) & 3
			return [a2 >> 15 == 1, sobe, (a2 >> 8) & 31, 7 - k if sobe else -8 + k, 32767.0 if sobe else 0.0]
	return [(a2 >> 5) & 1 == 1, false, a2 & 31, -8, 0.0]


## anda o envelope n passos do SPU: a cada 2^max(0, shift - 11) passos o
## nível anda passo << max(0, 11 - shift); exponencial subindo acima de
## 0x6000 vai 4x mais devagar, descendo anda proporcional ao nível
static func _env_anda(v: Dictionary, n: float) -> void:
	while n > 0.0 and v.fase < 4:
		var f := _fase(v.a1, v.a2, v.fase)
		var sh: int = f[2]
		var ciclos := float(1 << maxi(0, sh - 11))
		var passo := float(f[3]) * float(1 << maxi(0, 11 - sh))
		var alvo: float = f[4]
		if f[1]:
			var limite := alvo
			if f[0] and v.nivel < 24576.0:
				limite = 24576.0
			elif f[0]:
				ciclos *= 4.0
			var t: float = (limite - v.nivel) * ciclos / passo
			if t > n:
				v.nivel += passo * n / ciclos
				n = 0.0
			else:
				v.nivel = limite
				n -= t
				if limite == alvo:
					if v.fase == 0:
						v.fase = 1
					else:
						n = 0.0
		else:
			var chegou := false
			if f[0]:
				var fator := 1.0 + passo / 32768.0
				var k := n / ciclos
				if v.nivel > alvo + 1.0 and fator > 0.0:
					k = minf(k, log((alvo + 1.0) / v.nivel) / log(fator))
				v.nivel *= pow(maxf(fator, 0.0), k)
				n -= k * ciclos
				chegou = v.nivel <= alvo + 1.0
			else:
				var t: float = (alvo - v.nivel) * ciclos / passo
				if t > n:
					v.nivel += passo * n / ciclos
					n = 0.0
				else:
					n -= t
					chegou = true
			if chegou:
				v.nivel = alvo
				if v.fase == 1:
					v.fase = 2
				elif v.fase == 3:
					v.fase = 4
				else:
					n = 0.0


## programa de grãos (BlockSoundHandler): um cursor por som (e por filho)
func _novo_cursor(n: String, amp: float, regs: Array, pb: int) -> Dictionary:
	var s: Dictionary = _som[n]
	var c := {"s": s, "nome": n, "prox": 0, "conta": 0, "fim": s.prog.is_empty(),
		"amp": amp * float(s.vol) / 127.0, "regs": regs.duplicate(), "pb": pb, "filhos": [],
		"pular": false, "tocar_n": 0, "pular_n": 0}
	_cursores.append(c)
	if not c.fim:
		c.conta = _espera(s.prog[0])
		_anda(c)
	return c


## espera (em ticks de 240 Hz) que vale antes do grão
static func _espera(g: Array) -> int:
	match g[0]:
		"repete", "volta":
			return int(g[1])
		"filho":
			return int(g[3])
	return int(g[2])


func _tick() -> void:
	for c in _cursores.duplicate():
		if c.fim:
			continue
		c.conta -= 1
		_anda(c)
	var vivos: Array = []
	for c in _cursores:
		if not c.fim:
			vivos.append(c)
	_cursores = vivos


func _anda(c: Dictionary) -> void:
	var guarda := 0
	while c.conta <= 0 and not c.fim and guarda < 256:
		guarda += 1
		_grao(c)


func _grao(c: Dictionary) -> void:
	var prog: Array = c.s.prog
	var g: Array = prog[c.prox]
	var ret := 0
	match g[0]:
		"tom":
			_voz(c.s.tons[int(g[1])], c)
		"filho":
			if _som.has(g[1]):
				c.filhos.append(_novo_cursor(g[1], c.amp * float(g[2]) / 127.0, c.regs, c.pb))
		"volta":
			for i in range(c.prox - 1, -1, -1):
				if prog[i][0] == "repete":
					c.prox = i - 1
					break
		"sorteia":
			var opcoes := maxi(int(g[1]), 1)
			var quantos: int = int(g[3]) if g.size() > 3 else 1
			var chave := "%s/%d" % [c.nome, c.prox]
			var r := randi() % opcoes
			if r == int(_anterior.get(chave, 0)):
				r = (r + 1) % opcoes
			_anterior[chave] = r
			c.prox += r * quantos
			c.tocar_n = quantos + 1
			c.pular_n = (opcoes - 1 - r) * quantos
			c.pular = true
		"espera_sorteada":
			ret = randi() % (int(g[1]) + 1)
		"desvio_tom":
			var p := int(g[1]) & 0xff
			if p > 127:
				p -= 256
			_dobrar(c, p * ((0xffff * (randi() % 0x7fff)) / 0x7fff - 0x8000) / 100)
		"registrador_sorteado":
			var r := int(g[1])
			var v := randi() % (int(g[4]) - int(g[3]) + 1) + int(g[3])
			if r >= 0:
				c.regs[r] = v
			else:
				_regs_globais[-r - 1] = v
	if c.pular:
		c.tocar_n -= 1
		if c.tocar_n == 0:
			c.prox += c.pular_n
			c.pular = false
	c.prox += 1
	if c.prox >= prog.size():
		c.fim = true
		return
	c.conta = _espera(prog[c.prox]) + ret


func _dobrar(c: Dictionary, pb: int) -> void:
	for f in c.filhos:
		_dobrar(f, pb)
	c.pb = pb


func _voz(t: Dictionary, c: Dictionary) -> void:
	var tv := int(t.vol)
	if tv > 127:
		tv -= 256
	if tv < 0:
		if tv >= -4:
			tv = c.regs[-tv - 1]
		elif tv == -5:
			tv = randi() % 127
		else:
			tv = _regs_globais[clampi(-tv - 6, 0, 15)]
	tv = maxi(tv, 0)
	if _vozes.size() >= MAX_VOZES:
		# sai a voz curta mais velha; os loops (camadas do som) ficam
		var k := -1
		for j in _vozes.size():
			if not _vozes[j].loop:
				k = j
				break
		if k < 0:
			return
		_vozes[k].p.queue_free()
		_vozes.remove_at(k)
	var p := AudioStreamPlayer.new()
	p.stream = _wav(t)
	add_child(p)
	var adsr: Array = t.get("adsr", ADSR_SECO)
	var v := {"p": p, "amp": c.amp * tv / 127.0, "loop": bool(t.loop), "cur": c,
		"pb": t.get("pb", [0, 0]), "a1": int(adsr[0]), "a2": int(adsr[1]),
		"fase": 0, "nivel": 0.0, "vol": 0.0, "tom": 1.0}
	# o volume vale até o próximo quadro: começa no meio dele (60 Hz)
	_env_anda(v, SPU_HZ / 120.0)
	_aplicar(v)
	p.play()
	_vozes.append(v)


static func _wav(t: Dictionary) -> AudioStreamWAV:
	var caminho: String = PASTA.path_join(t.arq)
	if _cache.has(caminho):
		return _cache[caminho]
	var st: AudioStreamWAV = null
	if ResourceLoader.exists(caminho):
		st = load(caminho)
	if st == null:
		st = AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(caminho))
	if st and t.loop:
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = int(t.ini)
		st.loop_end = int(t.fim)
	elif st:
		st.loop_mode = AudioStreamWAV.LOOP_DISABLED
	_cache[caminho] = st
	return st
