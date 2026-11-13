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
## Atalho: a volta só conta se o carro passou pelos links do traçado (anda pelo
## link mais perto, só pros vizinhos) e avançou pelo menos AVANCO_MIN links
## desde a última passagem.

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
var _cp_pos := Vector3.ZERO
var _cp_frente := Vector3.ZERO
var _cp_lado := Vector3.ZERO
var _cp_meia := Vector3.ZERO
var hud: Label
var ia                          # rivais (pista/ia.gd)
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
		_intro_comp = _comprimento(_intro_cam)
		_intro_comp_alvo = _comprimento(_intro_alvo)
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


static func _comprimento(pts: Array) -> float:
	var l := 0.0
	for i in pts.size() - 1:
		l += pts[i].distance_to(pts[i + 1])
	return l


## ponto a s metros num caminho Catmull-Rom pelos nós (o jogo não foi lido:
## a curva entre os nós é NOSSA)
static func _no_caminho(pts: Array, s: float) -> Vector3:
	var n := pts.size()
	for i in n - 1:
		var l: float = pts[i].distance_to(pts[i + 1])
		if s <= l or i == n - 2:
			var f := clampf(s / maxf(l, 1e-4), 0.0, 1.0)
			var p0: Vector3 = pts[maxi(i - 1, 0)]
			var p3: Vector3 = pts[mini(i + 2, n - 1)]
			return (pts[i] as Vector3).cubic_interpolate(pts[i + 1], p0, p3, f)
		s -= l
	return pts[n - 1]


## a câmera de introdução, se estiver nela (o main não mexe na câmera)
func camera_intro(cam: Camera3D) -> bool:
	if estado != INTRO or _intro_cam.is_empty():
		return false
	var p := _no_caminho(_intro_cam, _intro_s)
	# os 2 a 35 m/s: o alvo anda o mesmo tanto no caminho dele
	var alvo := _no_caminho(_intro_alvo, _intro_s * float(dados.intro.vel_alvo) / float(dados.intro.vel))
	cam.near = 0.1
	cam.global_position = p
	cam.look_at(alvo, Vector3.UP)
	return true


## Enter: reinicia tudo e começa a corrida (pela introdução)
func comecar() -> void:
	if estado == INTRO:
		_fim_intro()            # Enter de novo pula a introdução
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
	link = _mais_perto(main.car.global_position)
	_lado_ant = _lado(main.car.global_position)
	main.car.test_input = null
	main.car.largada_presa = true
	hud.visible = true
	if ia and RIVAIS:
		ia.criar()


func _fim_intro() -> void:
	estado = CONTANDO
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
			if ia:
				ia.soltar()
		return
	if estado == CHEGOU:
		t_conta += dt
		t += dt                     # os rivais ainda chegando
		return
	t += dt
	_caixas()
	var p: Vector3 = car.global_position
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
	if volta == 0:
		volta = 1
		t_volta = t
		avanco = 0
		return
	if avanco < AVANCO_MIN:
		return                  # atalho ou deu ré pela linha
	ultima = t - t_volta
	tempos.append(ultima)
	melhor = minf(melhor, ultima)
	avanco = 0
	t_volta = t
	if volta >= voltas:
		estado = CHEGOU
		t_conta = 0.0
		t_fim = t
		# solta tudo: o carro para sozinho (segurar o freio parado engata a ré)
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


func _process(dt: float) -> void:
	if estado == LIVRE:
		return
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
			hud.text = "Get Ready" if t_desce <= 0.0 and t_conta > CONTAGEM - GET_READY else ""
		CORRENDO:
			if t < 1.0:
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
			if aviso != "":
				txt = aviso + "\n" + txt
				_cor_hud(Color(0.9, 0.1, 0.1))
			hud.text = txt
		CHEGOU:
			var txt := "CHEGADA!   %s\nmelhor volta %s" % [relogio(t_fim), relogio(melhor)]
			if ia and not ia.rivais.is_empty():
				var cl: Array = ia.classificacao()
				for i in cl.size():
					var e: Dictionary = cl[i]
					var tt: String = relogio(e.fim) if e.fim >= 0.0 else "volta %d" % clampi(int(e.prog / ia.comp) + 1, 1, voltas)
					txt += "\n%d. %s   %s" % [i + 1, e.nome, tt]
			hud.text = txt + "\nEnter: correr de novo   Backspace: treino livre"
