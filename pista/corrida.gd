extends Node
## Modo corrida do RX01 (Enter no jogo; o treino livre continua sendo o
## padrão). Dados do jogo em data/rx01_corrida.json (tools/rx01_corrida.py):
## grid (8 cStartPosition), linha de chegada (o checkpoint do evento, caixa
## 15.8 x 5.9 x 1.4 m), traçado da IA (75 links) e 5 voltas (eventos
## Rallycross Amateur, xml 14840).
##
## Largada: o carro vai pra posição 1 do grid (a mesma da RAM) e roda a câmera
## de introdução do jogo (IntroCameras.XML: caminho Intro1 de 7 nós olhando
## pro Introlookat1 de 5, os 2 a 35 m/s, ~14 s; Enter ou o A do controle pulam, no PS2 era o X). Depois contagem
## de 3 s e o cronômetro a partir do "VAI". Na espera toda o jogador pode
## acelerar com o carro preso (car.largada_presa: embreagem aberta, freio
## ignorado; até nov/2026 o freio ficava preso e parado o freio engata a ré:
## o carro largava de ré). A largada fica 54.8 m
## antes da linha (mFirstLapLength): a 1ª passagem pela linha começa a volta
## 1, cada passagem seguinte fecha uma volta; acaba na 5ª. Tempo total desde
## o VAI. NOSSO (o jogo não foi lido): como ele conta essa 1ª passagem e a
## contagem de 3 s.
##
## Os links do arquivo vêm na ordem contrária à da corrida (a direção de cada
## um aponta pro de índice menor): a lista é invertida ao carregar.
##
## Volta do jogador (nov/2026): pelo progresso ACEITO do vigia
## (pista/reposicao.gd, o objeto de progresso do jogo) passando de múltiplos
## da volta a partir da linha, como o checkpoint do jogo (AILink 50 + fração,
## pela rota, não pela caixa). Até nov/2026 era cruzar a caixa de 15.8 m numa
## pista de 24.8 m na linha: passando aberto (desviando de retardatário) a
## volta não contava e o Matheus terminou em 1º e ficou em 5º. O aceito não
## anda com atalho (mCheatingProgress) nem pra trás. Sem a IA (reserva): a
## caixa e o atalho pelos links (AVANCO_MIN links desde a última passagem).

const ARQ := "res://data/rx01_corrida.json"
# largada do vídeo do speedrun (Amateur National, Hunter Valley; a intro
# pulada): a câmera de corrida entra com "Get Ready" por 2.25 s, 2.75 s sem
# nada, "Go!" com o sinal verde e o cronômetro começa
const CONTAGEM := 5.0
const GET_READY := 2.25
# depois do voo da intro (vídeo do Matheus, PCSX2 nov/2026, RX01 de truck):
# corta pra uma câmera alta atrás do carro, olhando pra baixo, que desce até
# a câmera de corrida em 5.0 s (7.05 -> 12.1 s no vídeo) chegando devagar
# (a mudança por quadro cai quase em linha reta: posição 1 - (1 - t)^2); o
# HUD e o "Get Ready" entram logo depois (12.2 s). A altura de saída é NOSSA,
# estimada no quadro (o carro do mesmo tamanho, ~35° pra baixo)
const DESCIDA := 5.0
const DESCIDA_ALTURA := 5.0
const AVANCO_MIN := 60          # dos 75 links
const Truques := preload("res://pista/truques.gd")
# tela de resultados (menu/resultados.gd, estado 0x4c18e0 do exe): entra na
# sua chegada; a tabela começa vazia e a cada RESULTADO_PASSO s (o relógio
# começa em RESULTADO_INI: a 1ª vez em 3 s) é refeita com quem já chegou
const RESULTADO_PASSO := 2.0
const RESULTADO_INI := -1.0
const RIVAIS := true            # 7 rivais da IA (pista/ia.gd)

enum { LIVRE, INTRO, CONTANDO, CORRENDO, CHEGOU }

var main
var estado := LIVRE
var dados := {}
var voltas := 5
var links: Array = []           # centros no mundo (Godot), na ordem da corrida
var sentido := 1                # o arquivo do RX01 tem os links ao contrário da corrida
var t := 0.0                    # cronômetro da corrida (desde o VAI)
var t_conta := 0.0
var volta := 0                  # 0 = ainda não cruzou a linha
var t_volta := 0.0              # início da volta atual
var melhor := INF
var ultima := INF
var tempos: Array = []
var link := 0
var avanco := 0
var _lado_ant := 0.0
var _k_volta := -1               # voltas inteiras do progresso aceito (-1 = antes da linha)
var _cp_pos := Vector3.ZERO
var _cp_frente := Vector3.ZERO
var _cp_lado := Vector3.ZERO
var _cp_meia := Vector3.ZERO
var hud: Label
var ia                          # rivais (pista/ia.gd)
var truques                     # Score do jogador (pista/truques.gd)
var t_fim := 0.0                # tempo total do jogador na chegada
var t_desce := 0.0              # descida da câmera que falta (s)
var caixas: Array = []          # cInstantRespotBox: [inversa da caixa, meia caixa]
var reposicoes := 0             # quantas vezes alguém caiu numa caixa
var t_rapido := 0.0             # "Too Fast For Respot" na tela (s que faltam)
var _intro_cam: Array = []      # caminho da câmera (mundo)
var _intro_alvo: Array = []
var _intro_s := 0.0             # metros andados no caminho
var _intro_comp := 0.0
var _intro_comp_alvo := 0.0
var _arco_cam: Array = []       # [pontos, metros acumulados] da curva (andar a 35 m/s de verdade)
var _arco_alvo: Array = []


## jogo (x, y, z) -> mundo do Godot (z - 1024, y, x)
static func mundo(p: Array) -> Vector3:
	return Vector3(p[2] - 1024.0, p[1], p[0])


static func dir_mundo(d: Array) -> Vector3:
	return Vector3(d[2], d[1], d[0])


func montar(m) -> bool:
	main = m
	if not FileAccess.file_exists(ARQ):
		return false
	dados = JSON.parse_string(FileAccess.get_file_as_string(ARQ))
	voltas = int(dados.voltas)
	for l in dados.links:
		links.append(mundo(l.centro))
	# a direção de cada link aponta no sentido da corrida; no RX01 ela vai
	# pro link anterior (o índice cresce ao contrário): inverte a lista
	var l0: Dictionary = dados.links[0]
	if dir_mundo(l0.dir).dot(links[1] - links[0]) < 0.0:
		sentido = -1
		links.reverse()
	var cp: Dictionary = dados.checkpoint
	_cp_pos = mundo(cp.pos)
	_cp_lado = dir_mundo(cp.row0).normalized()
	_cp_frente = _cp_lado.cross(Vector3.UP).normalized()
	# a frente da linha = o sentido da corrida (o grid olha pra ela)
	if _cp_frente.dot(dir_mundo(dados.grid[0].dir)) < 0.0:
		_cp_frente = -_cp_frente
	_cp_meia = Vector3(cp.tamanho[0], cp.tamanho[1], cp.tamanho[2]) * 0.5
	# caixas de reposição na hora (RALLYCROSS.bin): centradas em pos, Z = dir
	# (bate com o eixo Z do modelo da arquibancada embaixo), tamanho inteiro
	for c in dados.get("reposicao", {}).get("caixas", []):
		var z := dir_mundo(c.dir)
		z.y = 0.0
		z = z.normalized()
		var xx := Vector3.UP.cross(z)
		var xf := Transform3D(Basis(xx, Vector3.UP, z), mundo(c.pos))
		caixas.append([xf.affine_inverse(), Vector3(c.tamanho[0], c.tamanho[1], c.tamanho[2]) * 0.5])
	if dados.has("intro"):
		for q in dados.intro.caminho:
			_intro_cam.append(mundo(q))
		for q in dados.intro.alvo:
			_intro_alvo.append(mundo(q))
		_arco_cam = _tabela_arco(_intro_cam)
		_arco_alvo = _tabela_arco(_intro_alvo)
		_intro_comp = (_arco_cam[1] as PackedFloat32Array)[-1]
		_intro_comp_alvo = (_arco_alvo[1] as PackedFloat32Array)[-1]
	ia = preload("res://pista/ia.gd").new()
	ia.name = "IA"
	add_child(ia)
	if not ia.montar(self):
		ia.queue_free()
		ia = null
	hud = Label.new()
	hud.name = "HudCorrida"
	hud.add_theme_font_size_override("font_size", 28)
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 8)
	hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	hud.position.y = 14
	var cl := CanvasLayer.new()
	cl.name = "CamadaCorrida"
	cl.add_child(hud)
	add_child(cl)
	hud.visible = false
	return true


## posição e giro (yaw) da largada n (0 = pole)
func largada(n: int) -> Array:
	var g: Dictionary = dados.grid[n]
	var p := mundo(g.pos)
	var d := dir_mundo(g.dir)
	return [p, atan2(d.x, d.z)]


## a curva pelos nós amostrada a cada ~0.25 m com os metros acumulados: a
## câmera anda pelo comprimento da CURVA. Até nov/2026 andava pelo nó (fração
## do trecho reto): a velocidade pulava de 27 pra 50 m/s e de 64 pra 24 m/s
## na passagem dos nós, as "flicadas" que o Matheus viu
static func _tabela_arco(pts: Array) -> Array:
	var ps := PackedVector3Array()
	var acc := PackedFloat32Array()
	var n := pts.size()
	var total := 0.0
	for i in n - 1:
		var l: float = (pts[i] as Vector3).distance_to(pts[i + 1])
		var k := maxi(ceili(l / 0.25), 1)
		var p0: Vector3 = pts[maxi(i - 1, 0)]
		var p3: Vector3 = pts[mini(i + 2, n - 1)]
		for j in k:
			var q := (pts[i] as Vector3).cubic_interpolate(pts[i + 1], p0, p3, float(j) / float(k))
			if not ps.is_empty():
				total += q.distance_to(ps[ps.size() - 1])
			ps.append(q)
			acc.append(total)
	var fim: Vector3 = pts[n - 1]
	total += fim.distance_to(ps[ps.size() - 1])
	ps.append(fim)
	acc.append(total)
	return [ps, acc]


## ponto a s metros (de curva) na tabela
static func _no_arco(tab: Array, s: float) -> Vector3:
	var ps: PackedVector3Array = tab[0]
	var acc: PackedFloat32Array = tab[1]
	if s <= 0.0:
		return ps[0]
	if s >= acc[acc.size() - 1]:
		return ps[ps.size() - 1]
	var i := acc.bsearch(s)
	var a := acc[i - 1]
	return ps[i - 1].lerp(ps[i], (s - a) / maxf(acc[i] - a, 1e-6))


## a câmera de introdução, se estiver nela (o main não mexe na câmera)
func camera_intro(cam: Camera3D) -> bool:
	if estado != INTRO or _intro_cam.is_empty():
		return false
	# o _intro_s anda no passo de 50 Hz; a tela desenha entre dois passos
	# (como os carros interpolados): sem isso a câmera andava aos trancos
	var vel := float(dados.intro.vel)
	var f := Engine.get_physics_interpolation_fraction()
	var s := maxf(_intro_s - vel * (1.0 - f) / float(Engine.physics_ticks_per_second), 0.0)
	var p := _no_arco(_arco_cam, s)
	# os 2 a 35 m/s: o alvo anda o mesmo tanto no caminho dele
	var alvo := _no_arco(_arco_alvo, s * float(dados.intro.vel_alvo) / vel)
	cam.near = 0.1
	cam.global_position = p
	cam.look_at(alvo, Vector3.UP)
	return true


## Enter: reinicia tudo e começa a corrida (pela introdução)
func comecar() -> void:
	if estado == INTRO:
		_fim_intro()            # Enter de novo pula a introdução E a descida
		t_desce = 0.0           # (speedrun: pulando, entra a câmera de corrida com o Get Ready)
		return
	if estado == CONTANDO and t_desce > 0.0:
		t_desce = 0.0           # e de novo pula a descida da câmera
		return
	var l := largada(0)
	var p: Vector3 = l[0]
	main.recomecar(Vector3(p.x, main.terrain.height_at(p.x, p.z) + 1.5, p.z), l[1])
	estado = INTRO if not _intro_cam.is_empty() else CONTANDO
	_intro_s = 0.0
	t_conta = CONTAGEM
	t = 0.0
	volta = 0
	melhor = INF
	ultima = INF
	tempos.clear()
	avanco = 0
	_k_volta = -1
	link = _mais_perto(main.car.global_position)
	_lado_ant = _lado(main.car.global_position)
	main.car.test_input = null
	main.car.largada_presa = true
	truques = Truques.new(Truques.grupo_do(main.car))
	hud.visible = true
	if ia and RIVAIS:
		ia.criar()


func _fim_intro() -> void:
	estado = CONTANDO
	main.car.longe_som = false  # o som do carro volta (a ia.gd religa os rivais)
	t_conta = CONTAGEM
	t_desce = DESCIDA
	main.reset_camera()


## Enter / A pulam: a intro ou a descida da câmera
func pode_pular() -> bool:
	return estado == INTRO or (estado == CONTANDO and t_desce > 0.0)


## a descida depois da intro, por cima da câmera de corrida já calculada
## (main._update_camera)
func camera_descida(cam: Camera3D, car: Node3D) -> void:
	if estado != CONTANDO or t_desce <= 0.0:
		return
	var f := 1.0 - t_desce / DESCIDA
	var k := (1.0 - f) * (1.0 - f)          # quanto falta (1 -> 0, chegando devagar)
	var fim: Transform3D = cam.global_transform
	var p := fim.origin + Vector3.UP * DESCIDA_ALTURA * k
	var olha := Basis.looking_at(car.global_position - p, Vector3.UP)
	var q := Quaternion(olha.orthonormalized()).slerp(Quaternion(fim.basis.orthonormalized()), 1.0 - k)
	cam.global_transform = Transform3D(Basis(q), p)


func parar() -> void:
	estado = LIVRE
	if main.car:
		main.car.longe_som = false
	truques = null
	hud.visible = false
	if ia:
		ia.limpar()
	if main.car:
		main.car.test_input = null
		main.car.largada_presa = false


func _mais_perto(p: Vector3) -> int:
	var melhor_i := 0
	var d := INF
	for i in links.size():
		var e: float = Vector2(links[i].x - p.x, links[i].z - p.z).length()
		if e < d:
			d = e
			melhor_i = i
	return melhor_i


## o carro (a origem) dentro de alguma cInstantRespotBox
func na_caixa(p: Vector3) -> bool:
	for c in caixas:
		var l: Vector3 = (c[0] as Transform3D) * p
		var m: Vector3 = c[1]
		if absf(l.x) <= m.x and absf(l.y) <= m.y and absf(l.z) <= m.z:
			return true
	return false


## caiu numa caixa de reposição: volta pra linha (pista/ia.gd repor_em)
func _caixas() -> void:
	if ia == null or caixas.is_empty():
		return
	if na_caixa(main.car.global_position):
		ia.repor_jogador()
		reposicoes += 1
	for x in ia.rivais:
		if is_instance_valid(x.car) and na_caixa(x.car.global_position):
			ia._repor(x)
			reposicoes += 1


## botão de reposição (R) na corrida: o do jogo (pista/reposicao.gd
## pode_botao: abaixo de mRespotSpeed, 40 mph); acima mostra "Too Fast For
## Respot" (a mensagem fica TEMPO_RAPIDO s: NOSSO, o jogo mostra enquanto o
## botão está apertado). Devolve false fora da corrida (o R normal).
const TEMPO_RAPIDO := 1.5


func botao_repor() -> bool:
	if estado != CORRENDO or ia == null or ia.vigia_jogador == null:
		return false
	if ia.vigia_jogador.pode_botao(main.car):
		ia.repor_jogador()
	else:
		t_rapido = TEMPO_RAPIDO
	return true


## distância com sinal até a linha de chegada (+ = já passou)
func _lado(p: Vector3) -> float:
	return (p - _cp_pos).dot(_cp_frente)


func _na_linha(p: Vector3) -> bool:
	var r := p - _cp_pos
	return absf(r.dot(_cp_lado)) <= _cp_meia.x and absf(r.y) <= _cp_meia.y + 2.0


func _physics_process(dt: float) -> void:
	if estado == LIVRE or main.car == null:
		return
	var car = main.car
	if estado == INTRO:
		# na abertura o carro não se ouve (Matheus: no jogo não se ouve; a
		# câmera está a ~130 m e o som do jogador não é posicional aqui)
		if not car.longe_som:
			car.calar_som()
			car.longe_som = true
		_intro_s += float(dados.intro.vel) * dt
		if _intro_s >= _intro_comp:
			_fim_intro()
		return
	if estado == CONTANDO:
		if t_desce > 0.0:
			t_desce -= dt           # a câmera descendo: a contagem ainda não anda
			return
		t_conta -= dt
		if t_conta <= 0.0:
			estado = CORRENDO
			car.largada_presa = false
			if truques:
				truques.ligado = true   # 0x523a20: os truques contam desde a largada
			if ia:
				ia.soltar()
		return
	if estado == CHEGOU:
		t_conta += dt
		t += dt                     # os rivais ainda chegando
		return
	t += dt
	_caixas()
	if truques:
		truques.passo(dt, car)
	var p: Vector3 = car.global_position
	if ia and not ia.rivais.is_empty() and ia.vigia_jogador:
		var k := int(floor(float(ia.vigia_jogador.aceito) / float(ia.comp)))
		while _k_volta < k and estado == CORRENDO:
			_k_volta += 1
			_passou_linha()
		return
	# avança pelo traçado: só pros vizinhos (não pula pra outro trecho da pista)
	var n := links.size()
	for _i in 3:
		var a: Vector3 = links[link]
		var prox: Vector3 = links[(link + 1) % n]
		var ant: Vector3 = links[(link - 1 + n) % n]
		var d0 := Vector2(a.x - p.x, a.z - p.z).length()
		if Vector2(prox.x - p.x, prox.z - p.z).length() < d0:
			link = (link + 1) % n
			avanco += 1
		elif Vector2(ant.x - p.x, ant.z - p.z).length() < d0:
			link = (link - 1 + n) % n
			avanco -= 1
	var lado := _lado(p)
	if _lado_ant < 0.0 and lado >= 0.0 and _na_linha(p):
		_cruzou()
	_lado_ant = lado


func _cruzou() -> void:
	if volta > 0 and avanco < AVANCO_MIN:
		return                  # atalho ou deu ré pela linha
	_passou_linha()


## a tela de resultados: na hora da sua chegada (o Matheus: "é instantâneo")
func resultados_prontos() -> bool:
	return estado == CHEGOU


## quem já chegou, na ordem de chegada (0x4c1998: só os corredores com a
## corrida fechada entram na tabela, na ordem da classificação)
func chegados() -> Array:
	if ia == null or ia.rivais.is_empty():
		return [{"nome": "Você", "jogador": true, "fim": t_fim, "melhor": melhor if melhor != INF else -1.0,
			"score": truques.total if truques else 0}]
	var cl: Array = ia.classificacao().filter(func(e): return float(e.fim) >= 0.0)
	cl.sort_custom(func(a, b): return float(a.fim) < float(b.fim))
	return cl


## passou pela linha: a 1ª vez começa a volta 1, depois fecha uma volta
func _passou_linha() -> void:
	if volta == 0:
		volta = 1
		t_volta = t
		avanco = 0
		return
	ultima = t - t_volta
	tempos.append(ultima)
	melhor = minf(melhor, ultima)
	avanco = 0
	t_volta = t
	if volta >= voltas:
		estado = CHEGOU
		t_conta = 0.0
		t_fim = t
		if truques:
			truques.parar()         # 0x1596d8: na chegada o combo aberto se perde
		# no jogo a IA passa a pilotar o seu carro (o Matheus); sem rivais
		# (reserva) solta tudo e ele para sozinho
		if ia and not ia.rivais.is_empty():
			ia.pilotar_jogador()
		else:
			main.car.test_input = {"thr": 0.0, "brk": 0.0, "steer": 0.0}
		return
	volta += 1


static func relogio(s: float) -> String:
	if s == INF:
		return "--:--.--"
	return "%d:%05.2f" % [int(s) / 60, fmod(s, 60.0)]


## CPU: a cor do texto só é trocada quando muda (trocar avisa o rótulo de
## tema novo; era em todo quadro)
var _cor_atual = null
func _cor_hud(c: Color) -> void:
	if _cor_atual == null or c != _cor_atual:
		hud.add_theme_color_override("font_color", c)
		_cor_atual = c


## CPU: o texto do HUD (relógio com centésimos: muda todo quadro e o rótulo
## mede o texto de novo a cada troca) no máximo ~75 vezes por segundo, como a
## tela do PS2 (50/60 Hz). Até 75 FPS é igual a antes
const PASSO_HUD := 1.0 / 75.0
var _dt_hud := 0.0


func _process(dt: float) -> void:
	if estado == LIVRE:
		return
	_dt_hud += dt
	if _dt_hud < PASSO_HUD:
		return
	dt = _dt_hud
	_dt_hud = 0.0
	# cores do vídeo: "Get Ready" vermelho, "Go!" verde
	var cor := Color.WHITE
	if estado == CONTANDO:
		cor = Color(0.9, 0.1, 0.1)
	elif estado == CORRENDO and t < 1.0:
		cor = Color(0.3, 0.9, 0.2)
	_cor_hud(cor)
	match estado:
		INTRO:
			hud.text = "Enter / A: pular"
		CONTANDO:
			# com o HUD do jogo, "Get Ready" e "Go!" são as mensagens dele
			hud.text = "Get Ready" if t_desce <= 0.0 and t_conta > CONTAGEM - GET_READY and not main.hud_jogo else ""
		CORRENDO:
			if t < 1.0 and not main.hud_jogo:
				hud.text = "Go!"
				return
			var txt := "Volta %d/%d   %s" % [maxi(volta, 1), voltas, relogio(t)]
			if ia and not ia.rivais.is_empty():
				txt = "Pos %d/%d   " % [ia.posicao_jogador(), ia.rivais.size() + 1] + txt
			if volta > 0:
				txt += "\nvolta %s   última %s   melhor %s" % [relogio(t - t_volta), relogio(ultima), relogio(melhor)]
			# avisos do jogo (pista/reposicao.gd): contramão, fora da pista
			var aviso: String = ia.vigia_jogador.texto() if ia and ia.vigia_jogador else ""
			if t_rapido > 0.0:
				t_rapido -= dt
				aviso = "Too Fast For Respot"
			if main.hud_jogo:
				txt = ""                 # posição, volta e tempos: o HUD do jogo (menu/hud_jogo.gd)
				aviso = ""               # avisos: ERROR_MESSAGE / START_ERROR do HUD do jogo
			if aviso != "":
				txt = aviso + ("\n" + txt if txt != "" else "")
				_cor_hud(Color(0.9, 0.1, 0.1))
			hud.text = txt
		CHEGOU:
			if main.get("resultados") != null:
				# com a tela de resultados do jogo (menu/resultados.gd): o HUD
				# mostra "Race Complete" e a tela vem quando todos chegarem
				hud.text = ""
				return
			var txt := "CHEGADA!   %s\nmelhor volta %s" % [relogio(t_fim), relogio(melhor)]
			if ia and not ia.rivais.is_empty():
				var cl: Array = ia.classificacao()
				for i in cl.size():
					var e: Dictionary = cl[i]
					var tt: String = relogio(e.fim) if e.fim >= 0.0 else "volta %d" % clampi(int(e.prog / ia.comp) + 1, 1, voltas)
					txt += "\n%d. %s   %s" % [i + 1, e.nome, tt]
			hud.text = txt + "\nEnter: correr de novo   Backspace: treino livre"
