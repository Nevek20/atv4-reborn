extends Control
## HUD do jogo (HUD_PS2/HUD_CIRCUIT.xml, cFEXHUDManager_CIRCUIT), desenhado
## pelo layout do próprio jogo (data/hud_circuit.xml) com as texturas, caixas
## .bed e fontes do archive (tools/hud_jogo.py -> assets/hud). Conferido com a
## RAM dos save states do Matheus (re/hud_ram.py, re/hud_ref.py,
## tests/ref_hud_4x3.json: 52 quadros a 640x480).
##
## Quadro (exe 0x46f7c0, enums da RAM em 0x83d1c0..0x83d1e0): X LEFT/RIGHT/
## CENTRE, Y BOTTOM/TOP/CENTRE (y pra cima), offset e escala. Modos:
##   SCALE_RELATIVE      fração do pai
##   SCALE_UNIT_RELATIVE fração do pai, quadrada pelo lado menor do pai
##   SCALE_ABSOLUTE      fração da altura da tela (X dividido pela razão)
## mOffsetAbsolute: offset na unidade do ABSOLUTE. Sprite com
## mPixelScaleRatio > 0 (0x472778 -> 0x46f6e8): tamanho = caixa do .bed em
## pixels x razão, numa tela de 480 de altura (no 4:3 da RAM: px x 4/3 / 640;
## no widescreen o exe ainda multiplica por 0.75, que dá o mesmo px / 480).
## Pela altura e não pela largura: em tela larga o conta-giros não estoura.
## Ordem: os objetos fixos (mStatic="1": molduras, caixas, rótulos) antes,
## os que mudam (números, ponteiro, barras) por cima.
##
## Texto (0x474e08 / 0x2689c0): glifo com a altura do quadro, topo no topo,
## kerning da fonte. Número com mAlignCentre (0x475390): centrado na borda
## esquerda do quadro pela largura do "8". (RAM: POSITION com escala 1.58 =
## 0.0725 da altura, igual à conta.) Fonte carregada (RAM, as 2 fontes):
## largura de cada letra arredondada pro pixel e os dígitos todos com a
## largura do maior, a caixa aberta em volta do meio (o "1" e o "7" ficam
## centrados). Tempo (OBJECT_TIMER, 0x494fb0 / 0x495208): o jogo monta o
## MODELO "--:--:--" (com uma célula de sinal no LEAD) e só troca a textura
## de cada célula pelo dígito: o número fica espremido na largura do traço.
## Lista de pilotos (0x48af80): caixas e números das posições fixos; quem
## muda de posição tem a placa e o nome deslizando da linha velha pra nova em
## mShuffleSpeed segundos, freando (1 - (1 - t)^2); quem desce some no meio
## do caminho (alfa |2t - 1|).
## Conta-giros (OBJECT_SPEEDO, 0x4890d8 / 0x488fd0 / 0x489068): alvo =
## -(mNeedleMinRot + (mNeedleMaxRot - mNeedleMinRot) x clamp(rpm / MAXREVS)),
## o ponteiro anda até ele a 10 rad/s. MAXREVS = Max_rpm do motor (9000 em
## todos; corpo+0x2ac -> +0xc) e a textura hud_tpage_rev[MAXREVS]. O ponteiro
## gira em volta do canto superior esquerdo da needle_base, posto no canto
## superior esquerdo da speedo_base (RAM: pivô 0.578/0.009 do quad, 0.439/
## 0.472 do mostrador); a base redonda já faz parte do sprite do ponteiro.
## Velocidade (0x477fc0) = int(|corpo+0x418| x 3.6) até 999 (a velocidade
## pra frente: 35.655 m/s -> 128 na RAM); marcha = corpo+0x2f0, neutro em
## branco (0x474f58).
## Barras (OBJECT_FILLBAR, 0x489ad0/0x489ee0): acendem trocando cores da CLUT
## da hud_tpage_bar por bloco; blocos = int(pedal suavizado x 16) (corpo
## +0x380 / +0x390); cores do XML (mActiveColour / mInactiveColour) x 128
## (verde 0,128,0; vermelho 255,0,0; apagado 38,38,38, como na RAM), alfa da
## paleta. PRELOAD_BAR: não existe nos buggies (a RAM tem o quadro mas o
## objeto foi liberado).
##
## NOSSO / ainda não portado: a conta do LEAD (diferença pro líder);
## bandeiras, mensagens e a seta.

const LAYOUT := "res://data/hud_circuit.xml"
const DIR := "res://assets/hud/"
const LINHA := {"FONT_SMALL": 22.0, "FONT_MEDIUM": 30.0}   # altura da linha (px da fonte)
const ALTURA_REF := 480.0          # pixel do sprite = altura / 480
const AGULHA_VEL := 10.0           # rad/s (0x489068)
const PASSO := 1.0 / 75.0          # como o PASSO_HUD
const NAO_PORTADOS := ["OBJECT_MESSAGE", "OBJECT_3DARROW", "OBJECT_PLACEMENT_MARKER", "OBJECT_SPRITE_ANIM"]
# treino livre: só o conta-giros (NOSSO: o treino do jogo não foi lido)
const SO_CORRIDA := ["LEFT_BORDER", "RIGHT_BORDER", "LeadPosFrm", "LapTimeFrm", "BestLapTotalFrm",
	"TrickScoreFrm", "MINIMAP_SPRITE", "MINIMAP_CIRCUIT", "PLAYERLIST_SPRITE", "PLAYERLIST_TEXT"]
const COR_JOGADOR := Color(1.0, 1.0, 0.2)   # nome e ponto do jogador (print do PAL: 248,248,44)
const NOME_JOGADOR := "PLAYER"            # o nome do perfil do jogo (NOSSO: ainda sem perfil)
# melhorias NOSSAS (pedido do Matheus; no PAL o número sai torto/vaza da caixa):
const SCORE_CENTRADO := true              # o SCORE embaixo do meio do rótulo
const VELOCIDADE_CABE := 0.8              # 3 dígitos: largura x 0.8 (cabem na caixa)
# LEAD: atrás do líder vermelho com "-" (print do PAL: 248,44,44); na frente
# verde (vídeo NTSC ~30,208,24; o par do vermelho). NOSSO: a conta (o tempo
# que o outro passou no mesmo ponto da pista; o exe não foi lido)
const COR_ATRAS := Color8(248, 44, 44)
const COR_FRENTE := Color8(44, 248, 44)

var info := {}
var raiz := {}
var tex := {}
var lingua := "en"
var maxrevs := 9000
var valores := {}          # nome do objeto -> valor (int, float, String)
var rpm := 1000.0
var agulha := 1.0472       # ângulo do ponteiro (rad, como na RAM: +0x98)
var em_corrida := false
var lista: Array = []            # classificação: [{nome, jogador}] na ordem
var _lista_mostrada: Array = []  # a ordem que a lista mostra (a animação vai até ela)
var _anim_lista := {}            # nome -> [linha de onde sai, linha pra onde vai]
var _anim_t := -1.0              # tempo da troca (s); < 0: parada
var pontos: Array = []           # minimapa: [x do jogo, z do jogo, jogador]
var _fonte := {}                 # fonte -> {código: [caixa na textura (px), largura (px)]}
var _hist := {}                  # LEAD: nome -> [[progresso, tempo], ...] (subindo)
var acel := 0.0            # pedais suavizados 0..1
var freio := 0.0
var _barra_img: Image
var _barra_idx: PackedByteArray
var _barra_tex: ImageTexture
var _barra_estado := Vector2i(-1, -1)
var _pix_barra: Array = []         # [x, y, alfa, 0 acel / 1 freio, bloco]
var _cores_barra := {}             # "ACCEL_BAR" -> [ativa, apagada]
var _dt := 0.0


func _init() -> void:
	name = "HudJogo"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


## false = sem assets/hud (rode o tools/hud_jogo.py)
func montar() -> bool:
	if not FileAccess.file_exists(DIR + "hud.json") or not FileAccess.file_exists(LAYOUT):
		return false
	info = JSON.parse_string(FileAccess.get_file_as_string(DIR + "hud.json"))
	for k in info.texturas:
		var p: String = DIR + String(info.texturas[k].png)
		if ResourceLoader.exists(p):
			tex[k] = load(p)
	raiz = _ler_layout()
	_preparar_fontes()
	_preparar_barras()
	return not raiz.is_empty()


## a fonte como o jogo deixa na RAM depois de carregar (FONT_SMALL e
## FONT_MEDIUM conferidas, tests/ref_hud_textos.json): largura = a da caixa
## do .bed arredondada pro pixel (6.82 -> 7, 29.66 -> 30; a textura estica);
## dígitos com a largura do maior e a caixa aberta em volta do meio
func _preparar_fontes() -> void:
	for fonte in LINHA:
		if not info.texturas.has(fonte):
			continue
		var g := {}
		var wdig := 0.0
		for k in info.texturas[fonte].caixas:
			if not String(k).is_valid_int():
				continue
			var c := int(k)
			var cx := _caixa(fonte, k)
			g[c] = [cx, roundf(cx.size.x)]
			if c >= 48 and c <= 57:
				wdig = maxf(wdig, roundf(cx.size.x))
		for c in range(48, 58):
			if g.has(c):
				var cx: Rect2 = g[c][0]
				g[c] = [Rect2(cx.get_center().x - wdig * 0.5, cx.position.y, wdig, cx.size.y), wdig]
		_fonte[fonte] = g


## largura (px da fonte) do caractere; fora da fonte vira espaço, como no jogo
func largura_glifo(fonte: String, c: int) -> float:
	var g: Dictionary = _fonte.get(fonte, {})
	if g.has(c):
		return g[c][1]
	return g[32][1] if g.has(32) else 0.0


# ------------------------------------------------------------------ layout
func _ler_layout() -> Dictionary:
	var x := XMLParser.new()
	if x.open(LAYOUT) != OK:
		return {}
	var topo := {"nome": "", "tipo": "OBJECT_FRAME", "at": {}, "frame": {}, "cor": Color.WHITE,
		"cores": {}, "filhos": []}
	var pilha: Array = [topo]
	while x.read() == OK:
		var t := x.get_node_type()
		if t == XMLParser.NODE_ELEMENT:
			var n := x.get_node_name()
			var at := {}
			for i in x.get_attribute_count():
				at[x.get_attribute_name(i)] = x.get_attribute_value(i)
			var dono: Dictionary = pilha[-1]
			if n == "Frame":
				if dono.frame.is_empty():
					dono.frame = at
			elif n.begins_with("m") and n.ends_with("Colour"):
				# mColour, mActiveColour, mInactiveColour, mInactiveColour2
				var c := Color(float(at.get("R", 1)), float(at.get("G", 1)), float(at.get("B", 1)), float(at.get("A", 1)))
				if n == "mColour":
					dono.cor = c
				dono.cores[n] = c
			elif n == "Children" or n == "Root":
				if not x.is_empty():
					pilha.append(dono)          # os filhos vão pro mesmo dono
			else:
				var no := {"nome": n, "tipo": at.get("mObjectType", "OBJECT_FRAME"), "at": at,
					"frame": {}, "cor": Color.WHITE, "cores": {}, "filhos": []}
				dono.filhos.append(no)
				if not x.is_empty():
					pilha.append(no)
		elif t == XMLParser.NODE_ELEMENT_END:
			var n := x.get_node_name()
			if n != "Frame" and not (n.begins_with("m") and n.ends_with("Colour")) and pilha.size() > 1:
				pilha.pop_back()
	return topo


static func _f(d: Dictionary, k: String, padrao := 0.0) -> float:
	return float(d.get(k, padrao))


## retângulo do objeto em fração da tela (x, y de baixo, w, h); pai idem.
## px = tamanho em pixels (sprite com mPixelScaleRatio) ou ZERO
func _rect(fr: Dictionary, pai: Rect2, a: float, px := Vector2.ZERO) -> Rect2:
	if fr.is_empty():
		return pai
	var fx := a * pai.size.x
	var fy := pai.size.y
	var sx := _f(fr, "mScaleX", 1.0)
	var sy := _f(fr, "mScaleY", 1.0)
	if px != Vector2.ZERO:
		# 0x46f6e8: px x razão / 640, x 0.75 no widescreen: razão 4/3 no 4:3 e
		# 16/9 x 0.75 = 4/3 no 16:9, sempre px / 480 (aí entra o modo, como no exe)
		sx = px.x / ALTURA_REF
		sy = px.y / ALTURA_REF
	match String(fr.get("mScaleMode", "SCALE_RELATIVE")):
		"SCALE_UNIT_RELATIVE":
			if fy < fx:
				sx *= fy / fx
			else:
				sy *= fx / fy
		"SCALE_ABSOLUTE":
			sx /= fx
			sy /= fy
	var ox := _f(fr, "mOffsetX")
	var oy := _f(fr, "mOffsetY")
	if String(fr.get("mOffsetAbsolute", "0")) == "1":
		ox /= fx
		oy /= fy
	var x := ox
	match String(fr.get("mAlignX", "ALIGN_LEFT")):
		"ALIGN_RIGHT": x = 1.0 - sx - ox
		"ALIGN_CENTRE": x = 0.5 - sx * 0.5 + ox
	var y := oy
	match String(fr.get("mAlignY", "ALIGN_BOTTOM")):
		"ALIGN_TOP": y = 1.0 - sy - oy
		"ALIGN_CENTRE": y = 0.5 - sy * 0.5 + oy
	return Rect2(pai.position.x + x * pai.size.x, pai.position.y + y * pai.size.y, sx * pai.size.x, sy * pai.size.y)


## O layout é montado numa tela 4:3 da altura da janela (o PS2 PAL do
## Matheus é 4:3: a RAM confere 1:1). Em janela mais larga, cada bloco (os
## filhos da raiz e das SafeScreen) encosta no lado do seu alinhamento X:
## LEFT fica, RIGHT vai pra borda direita, CENTRE pro meio. Por dentro de um
## bloco nada muda (NOSSO: o PS2 não tem janela larga; no 16:9 o exe espalha
## molduras e números por referências diferentes e o "01" da volta saía da
## caixa).
const RAZAO_HUD := 4.0 / 3.0
var _dx := 0.0                      # deslocamento do bloco atual (px)


func _largura_hud() -> float:
	return minf(size.x, size.y * RAZAO_HUD)


func _ancora(no: Dictionary) -> float:
	match String(no.frame.get("mAlignX", "ALIGN_LEFT")):
		"ALIGN_RIGHT": return 1.0
		"ALIGN_CENTRE": return 0.5
	return 0.0


## dx dos filhos: na raiz e dentro das SafeScreen cada filho é um bloco
func _dx_filho(no: Dictionary, filho: Dictionary) -> float:
	if no.nome == "" or String(no.nome).begins_with("SafeScreen"):
		if String(filho.nome).begins_with("SafeScreen"):
			return 0.0
		return (size.x - _largura_hud()) * _ancora(filho)
	return _dx


## fração da tela HUD (y de baixo) -> pixels do Control (y de cima)
func _tela(r: Rect2) -> Rect2:
	var w := _largura_hud()
	var h := size.y
	return Rect2(r.position.x * w + _dx, (1.0 - r.position.y - r.size.y) * h, r.size.x * w, r.size.y * h)


func _textura(nome: String) -> String:
	if nome == "Minimaps/[LEVEL_EVENT]":
		return "RX_01_RALLYCROSS"       # o minimapa do evento (só o RX01 por enquanto)
	nome = nome.get_file()
	if nome.begins_with("hud_tpage_rev"):
		var t := "hud_tpage_rev%d" % maxrevs
		return t if tex.has(t) else "hud_tpage_rev9000"
	return nome


func _caixa(tnome: String, caixa: String) -> Rect2:
	var t: Dictionary = info.texturas.get(tnome, {})
	var cx: Dictionary = t.get("caixas", {})
	var c: Array = cx.get(caixa, [])
	if c.is_empty():
		for k in cx:                    # o layout escreve MAP / flag_01, o .bed map / FLAG_01
			if String(k).to_lower() == caixa.to_lower():
				c = cx[k]
	if c.is_empty():
		return Rect2(0, 0, t.get("w", 0), t.get("h", 0))
	return Rect2(c[0] * t.w, c[1] * t.h, (c[2] - c[0]) * t.w, (c[3] - c[1]) * t.h)


## tamanho em pixels do sprite com mPixelScaleRatio (0x472778: inteiro de
## textura x razão x caixa; a caixa é a mBedBox, a mSpeedoBedBox, a
## mPosBedBox da lista ou o 1º quadro da animação, mBedBoxStub + "_01")
func _px(no: Dictionary) -> Vector2:
	var at: Dictionary = no.at
	var razao := float(at.get("mPixelScaleRatio", -1.0))
	if razao <= 0.0:
		return Vector2.ZERO
	var tnome := _textura(String(at.get("mTexture", "")))
	if no.tipo == "OBJECT_FILLBAR":
		tnome = "hud_tpage_bar"
	var caixa := String(at.get("mBedBox", at.get("mSpeedoBedBox", at.get("mPosBedBox", ""))))
	if no.tipo == "OBJECT_SPRITE_ANIM" and at.has("mBedBoxStub"):
		caixa = String(at.mBedBoxStub) + "_01"
	if not tex.has(tnome) or caixa == "":
		return Vector2.ZERO
	var c := _caixa(tnome, caixa).size * razao
	return Vector2(int(c.x), int(c.y))


# ------------------------------------------------------------------ desenho
func _draw() -> void:
	if raiz.is_empty() or size.y <= 0.0:
		return
	var a := _largura_hud() / size.y
	for passe in 2:                 # 0: fixos (mStatic 1), 1: os que mudam
		for f in raiz.filhos:
			_dx = _dx_filho(raiz, f)
			_desenha(f, Rect2(0, 0, 1, 1), a, passe)
	_dx = 0.0


func _visivel(no: Dictionary) -> bool:
	if no.at.has("mVisGroup") or no.tipo in NAO_PORTADOS:
		return false               # grupos que só aparecem em hora certa e objetos ainda não portados
	return em_corrida or not (no.nome in SO_CORRIDA)


func _desenha(no: Dictionary, pai: Rect2, a: float, passe: int) -> void:
	if not _visivel(no):
		return
	var at: Dictionary = no.at
	var r := _rect(no.frame, pai, a, _px(no))
	var fixo := String(at.get("mStatic", "1")) == "1"
	if fixo == (passe == 0):
		var tnome := _textura(String(at.get("mTexture", "")))
		match no.tipo:
			"OBJECT_SPRITE":
				if tex.has(tnome):
					_sprite(tex[tnome], _caixa(tnome, String(at.get("mBedBox", ""))), _tela(r),
						String(at.get("mMirrorX", "0")) == "1", no.cor)
			"OBJECT_SPEEDO":
				_speedo(no, tnome, r)
			"OBJECT_FILLBAR":
				_barra(no, r)
			"OBJECT_TEXT":
				var k := String(at.get("mText", ""))
				var txt: String = info.get("textos", {}).get(lingua, {}).get(k, k)
				_texto(txt, String(at.get("mFont", "FONT_SMALL")), r, no.cor, at)
			"OBJECT_TIMER":
				var tc := celulas_tempo(no, valores.get(no.nome, null))
				_texto(tc[0], String(at.get("mFont", "FONT_SMALL")), r, valores.get(no.nome + "#cor", no.cor), at,
					-1, NAN, 1.0, tc[1])
			"OBJECT_INTEGER":
				var v = valores.get(no.nome, 0)
				if v != null:
					var dig := str(absi(int(v))).length()
					var cx := NAN
					var cond := 1.0
					if no.nome == "TOTAL_TRICK_SCORE" and SCORE_CENTRADO:
						var rot = _no("TOTAL_TRICK_SCORE_LABEL")
						if rot:
							cx = _tela(_rect(rot.frame, pai, a)).get_center().x
					if no.nome == "SPEED" and dig >= 3:
						cond = VELOCIDADE_CABE
					_texto(_valor(no), String(at.get("mFont", "FONT_SMALL")), r, no.cor, at, dig, cx, cond)
			"OBJECT_PLAYERLIST_SPRITE":
				_lista_caixas(no, r)
			"OBJECT_PLAYERLIST_TEXT":
				_lista_textos(no, r)
			"OBJECT_MINIMAP":
				_mapa_pontos(no, r)
	var dx := _dx
	for f in no.filhos:
		_dx = _dx_filho(no, f)
		_desenha(f, r, a, passe)
		_dx = dx


## {nome: Rect2 em fração da tela HUD (y de baixo)} de todos os objetos
func retangulos_frac() -> Dictionary:
	var out := {}
	if not raiz.is_empty() and size.y > 0.0:
		_ret_frac(raiz, Rect2(0, 0, 1, 1), _largura_hud() / size.y, out)
	return out


func _ret_frac(no: Dictionary, pai: Rect2, a: float, out: Dictionary) -> void:
	var r := _rect(no.frame, pai, a, _px(no))
	if no.nome != "":
		out[no.nome] = r
	for f in no.filhos:
		_ret_frac(f, r, a, out)


## {nome: Rect2 em pixels} de todos os objetos (testes e conferência)
func retangulos() -> Dictionary:
	var out := {}
	if not raiz.is_empty() and size.y > 0.0:
		_dx = 0.0
		_ret(raiz, Rect2(0, 0, 1, 1), _largura_hud() / size.y, out)
		_dx = 0.0
	return out


func _ret(no: Dictionary, pai: Rect2, a: float, out: Dictionary) -> void:
	var r := _rect(no.frame, pai, a, _px(no))
	if no.nome != "":
		out[no.nome] = _tela(r)
	var dx := _dx
	for f in no.filhos:
		_dx = _dx_filho(no, f)
		_ret(f, r, a, out)
		_dx = dx


func _sprite(t: Texture2D, src: Rect2, dst: Rect2, espelha: bool, cor: Color) -> void:
	if espelha:                  # mMirrorX: vira no meio do próprio retângulo
		draw_set_transform(Vector2(dst.position.x * 2.0 + dst.size.x, 0.0), 0.0, Vector2(-1, 1))
		draw_texture_rect_region(t, dst, src, cor)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	draw_texture_rect_region(t, dst, src, cor)


## número (OBJECT_INTEGER, 0x494a78 / 0x494c10): células "0" do mText (o
## zero à esquerda com mZeroPad), o valor da esquerda pra direita
func _valor(no: Dictionary) -> String:
	var v = valores.get(no.nome, null)
	var modelo := String(no.at.get("mText", "0"))
	var n: int = v if v != null else 0
	if String(no.at.get("mZeroPad", "0")) == "1":
		return ("%0" + str(modelo.length()) + "d") % n
	return str(n)


## tempo (OBJECT_TIMER, 0x494fb0 / 0x495208): [modelo, o que cada célula
## mostra]. O modelo é o mText com traços ("--:--:--") e uma célula de sinal
## na frente se mAllowNegative; cada célula mostra o dígito (ou "-" sem
## tempo), o sinal só aparece negativo. Valor = int(t x 100 + 0.5) até
## 5999.99 s: mm:ss:cc
func celulas_tempo(no: Dictionary, v) -> Array:
	var modelo := String(no.at.get("mText", "00:00:00"))
	var sinal := String(no.at.get("mAllowNegative", "0")) == "1"
	var tpl := "-" if sinal else ""
	for ch in modelo:
		tpl += "-" if ch >= "0" and ch <= "9" else ch
	var dig := []
	if v != null:
		var t := minf(absf(float(v)), 5999.99)
		var cent := modelo.length() >= 7
		var iv := int(t * 100.0 + 0.5) if cent else int(t + 0.5)
		var seg := iv / 100 if cent else iv
		dig = [(seg / 60 / 10) % 10, (seg / 60) % 10, (seg % 60 / 10) % 10, seg % 60 % 10]
		if cent:
			dig += [(iv / 10) % 10, iv % 10]
	var mostra := []
	var d := 0
	for i in tpl.length():
		if sinal and i == 0:
			mostra.append(45 if v != null and float(v) < 0.0 else -1)
		elif tpl[i] == "-":
			mostra.append(48 + dig[d] if d < dig.size() else 45)
			d += 1
		else:
			mostra.append(tpl.unicode_at(i))
	return [tpl, mostra]


func _texto(txt: String, fonte: String, r: Rect2, cor: Color, at: Dictionary, digitos := -1,
		centro_x := NAN, cond := 1.0, mostra: Array = []) -> void:
	if not tex.has(fonte):
		return
	for g in glifos(txt, fonte, _tela(r), at, digitos, centro_x, cond, mostra):
		draw_texture_rect_region(tex[fonte], g[0], g[1], cor)


## letras de um texto: [[retângulo na tela, caixa na textura], ...] (exe
## 0x474e08 / 0x2689c0). Glifo com a altura do quadro (escala = altura do
## quadro / linha da fonte), topo no topo do quadro, largura da fonte x
## escala; avanço = largura - kerning. mTextAlignX: LEFT começa na borda
## esquerda, CENTRE no meio, RIGHT termina na direita. Número com
## mAlignCentre (0x475390): centrado na borda ESQUERDA do quadro pela largura
## do "8" x dígitos do valor. `mostra` troca a textura de cada célula (tempo:
## -1 = célula vazia). Espaço não desenha
func glifos(txt: String, fonte: String, cel: Rect2, at: Dictionary, digitos := -1, centro_x := NAN,
		cond := 1.0, mostra: Array = []) -> Array:
	var g: Dictionary = _fonte.get(fonte, {})
	if g.is_empty():
		return []
	var linha: float = LINHA.get(fonte, 22.0)
	var esc_x := cel.size.x / linha * cond
	var kern: Dictionary = info.texturas[fonte].get("kern", {})
	var cods := []
	for ch in txt:
		var k := ch.unicode_at(0)
		cods.append(k if g.has(k) else 32)
	var avancos := []
	var largura := 0.0
	for n in cods.size():
		var prox: int = cods[n + 1] if n + 1 < cods.size() else 0
		var av: float = (largura_glifo(fonte, cods[n]) - _kern(kern, cods[n], prox)) * esc_x
		avancos.append(av)
		largura += av
	var x := cel.position.x
	var al := String(at.get("mTextAlignX", "ALIGN_LEFT"))
	if not is_nan(centro_x):
		x = centro_x - largura * 0.5            # NOSSO (SCORE_CENTRADO)
	elif digitos >= 0:
		if String(at.get("mAlignCentre", "0")) == "1":
			# 0x475390 desconta em NDC (largura do "8" / altura da linha x escala
			# X do quadro) sem a razão 4:3 da escala das letras: anda só 3/4 da
			# metade do número (RAM: SPEED e SCORE). Por isso o Score do PAL é torto
			x -= largura_glifo(fonte, 56) * esc_x * digitos * 0.5 / RAZAO_HUD
	elif al == "ALIGN_CENTRE":
		x = cel.position.x + cel.size.x * 0.5 - largura * 0.5
	elif al == "ALIGN_RIGHT":
		x = cel.end.x - largura
	var out := []
	for n in cods.size():
		var c: int = cods[n]
		var vis: int = mostra[n] if n < mostra.size() else c
		if c != 32 and vis >= 0 and vis != 32 and g.has(vis):
			out.append([Rect2(x, cel.position.y, largura_glifo(fonte, c) * esc_x, cel.size.y), g[vis][0]])
		x += avancos[n]
	return out


## lista de pilotos, caixas (OBJECT_PLAYERLIST_SPRITE; RAM do save state):
## caixa da posição (pos_box, em pixel) no canto do quadro, a do nome
## (name_box) logo à direita com folga de mGapSize x a largura da caixa, da
## mesma altura e largura = caixa x (nome / posição) nas UV; cada linha
## desce altura x (1 + mGapSize), a 1ª no topo do quadro. As caixas das
## posições ficam; as dos nomes andam com o piloto (lista_linhas)
func _lista_caixas(no: Dictionary, r: Rect2) -> void:
	var tnome := _textura(String(no.at.get("mTexture", "")))
	if not tex.has(tnome):
		return
	var pos := _caixa(tnome, String(no.at.get("mPosBedBox", "pos_box")))
	var nome := _caixa(tnome, String(no.at.get("mNameBedBox", "name_box")))
	var ll := lista_linhas()
	for k in ll.size():
		_sprite(tex[tnome], pos, linha_caixas(no, r, float(k))[0], false, Color.WHITE)
	for passe in 2:                  # quem some primeiro, os inteiros por cima
		for l in ll:
			if (l[1] < 1.0) == (passe == 0):
				_sprite(tex[tnome], nome, linha_caixas(no, r, l[0])[1], false, Color(1, 1, 1, l[1]))


## [caixa da posição, caixa do nome] de cada linha, em pixels
func linhas_caixas(no: Dictionary, r: Rect2, n: int) -> Array:
	var out := []
	for k in n:
		out.append(linha_caixas(no, r, float(k)))
	return out


## as 2 caixas da linha k (k fracionário: o nome andando entre 2 linhas)
func linha_caixas(no: Dictionary, r: Rect2, k: float) -> Array:
	var tnome := _textura(String(no.at.get("mTexture", "")))
	var pos := _caixa(tnome, String(no.at.get("mPosBedBox", "pos_box")))
	var nome := _caixa(tnome, String(no.at.get("mNameBedBox", "name_box")))
	var gap := float(no.at.get("mGapSize", 0.05))
	var q := _tela(r)                      # já do tamanho da pos_box (mPixelScaleRatio)
	var w_nome := q.size.x * nome.size.x / pos.size.x
	var y := q.position.y + k * q.size.y * (1.0 + gap)
	return [Rect2(q.position.x, y, q.size.x, q.size.y), Rect2(q.end.x + gap * q.size.x, y, w_nome, q.size.y)]


## lista de pilotos, textos (OBJECT_PLAYERLIST_TEXT; RAM): número no canto do
## quadro, nome mHorzSpacing x a largura à direita; cada linha desce
## mVertSpacing x a altura. Jogador em amarelo. Os números ficam, os nomes
## andam e somem junto com a caixa deles
func _lista_textos(no: Dictionary, r: Rect2) -> void:
	var fonte := String(no.at.get("mFont", "FONT_SMALL"))
	var esq := {"mTextAlignX": "ALIGN_LEFT"}
	var ll := lista_linhas()
	for k in ll.size():
		_texto(str(k + 1), fonte, linha_textos(no, r, float(k))[0], Color.WHITE, esq)
	for passe in 2:
		for l in ll:
			if (l[1] < 1.0) == (passe == 0):
				var e: Dictionary = l[2]
				var cor := COR_JOGADOR if e.jogador else Color.WHITE
				cor.a = l[1]
				_texto(String(e.nome), fonte, linha_textos(no, r, l[0])[1], cor, esq)


## [célula do número, célula do nome] de cada linha, em fração da tela HUD
func linhas_textos(no: Dictionary, r: Rect2, n: int) -> Array:
	var out := []
	for k in n:
		out.append(linha_textos(no, r, float(k)))
	return out


func linha_textos(no: Dictionary, r: Rect2, k: float) -> Array:
	var hx := float(no.at.get("mHorzSpacing", 1.172))
	var vy := float(no.at.get("mVertSpacing", 1.172))
	var rk := Rect2(r.position.x, r.position.y - k * r.size.y * vy, r.size.x, r.size.y)
	return [rk, Rect2(rk.position.x + r.size.x * hx, rk.position.y, r.size.x, r.size.y)]


## [linha (fracionária), alfa, {nome, jogador}] de cada piloto na lista
func lista_linhas() -> Array:
	var mostrada: Array = _lista_mostrada if not _lista_mostrada.is_empty() else lista
	var e := anim_lista_e()
	var out := []
	for k in mostrada.size():
		var en: Dictionary = mostrada[k]
		var a: Array = _anim_lista.get(en.nome, [])
		if a.is_empty() or _anim_t < 0.0:
			out.append([float(k), 1.0, en])
		else:
			out.append([lerpf(a[0], a[1], e), absf(e - 0.5) * 2.0 if a[1] > a[0] else 1.0, en])
	return out


## andamento da troca da lista (0x48af80): t / mShuffleSpeed, freando
func anim_lista_e() -> float:
	if _anim_t < 0.0:
		return 1.0
	var s = _no("PLAYERLIST_SPRITE")
	var dur := float(s.at.get("mShuffleSpeed", 1.0)) if s else 1.0
	var t := clampf(_anim_t / maxf(dur, 1e-3), 0.0, 1.0)
	return 1.0 - (1.0 - t) * (1.0 - t)


## nova classificação: se a lista está parada e a ordem mudou, cada piloto
## que trocou de linha anda da velha pra nova; durante a troca a ordem nova
## espera (o jogo enfileira e só compara de novo quando a animação acaba)
func animar_lista(dt: float) -> void:
	if _anim_t >= 0.0:
		_anim_t += dt
		if anim_lista_e() >= 1.0:
			_anim_t = -1.0
			_anim_lista.clear()
		return
	var novos := lista.map(func(e): return e.nome)
	var velhos := _lista_mostrada.map(func(e): return e.nome)
	if velhos.size() != novos.size() or novos.any(func(n): return not (n in velhos)):
		_lista_mostrada = lista.duplicate()   # outra corrida, outro grid: sem animação
		return
	if novos == velhos:
		_lista_mostrada = lista.duplicate()
		return
	_anim_lista.clear()
	for i in novos.size():
		var j := velhos.find(novos[i])
		if j != i:
			_anim_lista[novos[i]] = [float(j), float(i)]
	_lista_mostrada = lista.duplicate()
	_anim_t = 0.0


## pontos do minimapa (OBJECT_MINIMAP; MINIMAPS.xml + RAM dos 4 save states):
## centro = canto do quadro + (mOffsetX - (x - mXBase) x mScaleX / 1000,
## mOffsetZ - (z - mZBase) x mScaleZ / 1000) em NDC da tela 4:3 (x, z do
## jogo). Rivais brancos, o jogador amarelo por cima
func _mapa_pontos(no: Dictionary, r: Rect2) -> void:
	var tnome := _textura(String(no.at.get("mTexture", "")))
	var mm: Dictionary = info.get("minimapa", {})
	if not tex.has(tnome) or mm.is_empty():
		return
	var dot := _caixa(tnome, String(no.at.get("mBedBox", "map_dot")))
	for passe in 2:
		for p in pontos:
			if bool(p[2]) != (passe == 1):
				continue
			_sprite(tex[tnome], dot, _tela(ponto_mapa(r, p[0], p[1])), false, COR_JOGADOR if p[2] else Color.WHITE)


## retângulo (fração da tela HUD) do ponto de um carro em (x, z) do jogo
func ponto_mapa(r: Rect2, x: float, z: float) -> Rect2:
	var mm: Dictionary = info.get("minimapa", {})
	var u: float = mm.mOffsetX - (x - mm.mXBase) * mm.mScaleX / 1000.0
	var v: float = mm.mOffsetZ - (z - mm.mZBase) * mm.mScaleZ / 1000.0
	return Rect2(r.position.x + u * 0.5 - r.size.x * 0.5, r.position.y + v * 0.5 - r.size.y * 0.5, r.size.x, r.size.y)


## quanto o par (c, prox) encosta, em pixels da fonte (0x2689c0, flag 0x40)
static func _kern(kern: Dictionary, c: int, prox: int) -> float:
	if kern.is_empty():
		return 0.0
	var base: float = kern.base
	if c < 0x40 or prox < 0x40 or c - 0x40 >= 192 or prox - 0x40 >= 192:
		return base
	var linha: int = kern.mapa[c - 0x40]
	if linha == 0xff or linha >= kern.tabela.size():
		return base
	return base + float(kern.tabela[linha][prox - 0x40]) * float(kern.passo)


## conta-giros: mostrador + ponteiro (0x4890d8 / 0x489448 / 0x489798)
func _speedo(no: Dictionary, tnome: String, r: Rect2) -> void:
	if not tex.has(tnome):
		return
	var at: Dictionary = no.at
	var mostrador := _caixa(tnome, String(at.get("mSpeedoBedBox", "main_speedo")))
	var dst := _tela(r)
	_sprite(tex[tnome], mostrador, dst, false, no.cor)
	var esc := dst.size / mostrador.size
	var base := _caixa(tnome, String(at.get("mSpeedoBaseBedBox", "speedo_base")))
	var ponteiro := _caixa(tnome, String(at.get("mNeedleBedBox", "needle")))
	var nbase := _caixa(tnome, String(at.get("mNeedleBaseBedBox", "needle_base")))
	# pivô = canto (x0, y0) da speedo_base no mostrador e da needle_base no
	# ponteiro (o exe usa os cantos das caixas: RAM 0.4392/0.4717, 0.578/0.009)
	var pivo := dst.position + (base.position - mostrador.position) * esc
	# ângulo do jogo é y pra cima (anti-horário); no Godot y pra baixo: inverte
	draw_set_transform(pivo, -agulha, Vector2.ONE)
	_sprite(tex[tnome], ponteiro, Rect2((ponteiro.position - nbase.position) * esc, ponteiro.size * esc), false, no.cor)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ------------------------------------------------------------------ barras
func _preparar_barras() -> void:
	var p := DIR + "hud_tpage_bar_idx.png"
	if not tex.has("hud_tpage_bar") or not FileAccess.file_exists(p):
		return
	var ii := Image.load_from_file(ProjectSettings.globalize_path(p))
	ii.convert(Image.FORMAT_L8)
	_barra_idx = ii.get_data()
	_barra_img = (tex.hud_tpage_bar as Texture2D).get_image()
	_barra_img.decompress()
	_barra_img.convert(Image.FORMAT_RGBA8)
	_barra_img.clear_mipmaps()
	# o importador sangra a cor vizinha nos pixels transparentes (fix_alpha_border)
	# e o filtro linear trazia o vermelho da paleta de marcação pra borda dos blocos
	for y in _barra_img.get_height():
		for x in _barra_img.get_width():
			if _barra_img.get_pixel(x, y).a == 0.0:
				_barra_img.set_pixel(x, y, Color(0, 0, 0, 0))
	_barra_tex = ImageTexture.create_from_image(_barra_img)
	var w := _barra_img.get_width()
	for i in _barra_idx.size():
		var k := _barra_idx[i]
		if k >= 224:               # ACCEL 239 -> 224, BRAKE 255 -> 240 (mReverseEntries)
			var pxv := Vector2i(i % w, i / w)
			_pix_barra.append([pxv.x, pxv.y, _barra_img.get_pixelv(pxv).a, 0 if k <= 239 else 1,
				(239 - k) if k <= 239 else (255 - k)])
	_cores_barra = {"ACCEL_BAR": [Color8(0, 128, 0), Color8(38, 38, 38)],
		"BRAKE_BAR": [Color8(255, 0, 0), Color8(38, 38, 38)]}
	_achar_cores(raiz)


## cores das barras do XML x 128, presas em 255 (0x489ad0)
func _achar_cores(no: Dictionary) -> void:
	if no.nome in _cores_barra:
		var c: Dictionary = no.cores
		var ps2 := func(k: Color) -> Color:
			return Color8(mini(int(k.r * 128.0), 255), mini(int(k.g * 128.0), 255), mini(int(k.b * 128.0), 255))
		if c.has("mActiveColour"):
			_cores_barra[no.nome][0] = ps2.call(c.mActiveColour)
		if c.has("mInactiveColour"):
			_cores_barra[no.nome][1] = ps2.call(c.mInactiveColour)
	for f in no.filhos:
		_achar_cores(f)


## pinta os blocos acesos/apagados das 2 barras (só quando muda)
func _pintar_barras() -> void:
	if _barra_img == null:
		return
	var n_acel := int(acel * 16.0)       # 0x4898a8: parte inteira
	var n_freio := int(freio * 16.0)
	var est := Vector2i(n_acel, n_freio)
	if est == _barra_estado:
		return
	_barra_estado = est
	var ca: Array = _cores_barra.ACCEL_BAR
	var cf: Array = _cores_barra.BRAKE_BAR
	for p in _pix_barra:
		var cor: Color
		if p[3] == 0:
			cor = ca[0] if p[4] < n_acel else ca[1]
		else:
			cor = cf[0] if p[4] < n_freio else cf[1]
		_barra_img.set_pixel(p[0], p[1], Color(cor.r, cor.g, cor.b, p[2]))
	_barra_tex.update(_barra_img)


func _barra(no: Dictionary, r: Rect2) -> void:
	if _barra_tex == null or not (no.nome in _cores_barra):
		return                       # PRELOAD_BAR: não existe nos buggies (RAM)
	draw_texture_rect_region(_barra_tex, _tela(r), _caixa("hud_tpage_bar", String(no.at.get("mBedBox", ""))))


# ------------------------------------------------------------------ dados
## car: o carro do jogador; corrida: pista/corrida.gd (ou null no treino)
func atualizar(dt: float, car, corrida) -> void:
	_dt += dt
	if _dt < PASSO:
		return
	var passo := _dt
	_dt = 0.0
	if car == null:
		return
	maxrevs = int(car.P.get("max_rpm", 9000.0))
	rpm = car.rpm
	# 0x488fd0: alvo e ponteiro andando a 10 rad/s (0x489068)
	var sp = _no("SPEEDO")
	var mn := float(sp.at.get("mNeedleMinRot", -1.57)) if sp else -1.57
	var mx := float(sp.at.get("mNeedleMaxRot", 3.1416)) if sp else 3.1416
	var alvo := -(mn + (mx - mn) * clampf(rpm / float(maxrevs), 0.0, 1.0))
	agulha = move_toward(agulha, alvo, passo * AGULHA_VEL)
	acel = clampf(car.throttle, 0.0, 1.0)      # pedais suavizados (+0x380 / +0x390)
	freio = clampf(car.brake_in, 0.0, 1.0)
	valores.SPEED = clampi(int(absf(car.linear_velocity.dot(car.global_transform.basis.z)) * 3.6), 0, 999)
	var g: int = car.gear
	valores.GEAR = null if g == 0 else g       # neutro: em branco (0x474f58)
	em_corrida = corrida != null and corrida.estado != 0
	if em_corrida:
		valores.CURRENT_LAP = maxi(corrida.volta, 1)
		valores.TOTAL_LAPS = corrida.voltas
		var correndo: bool = corrida.estado >= corrida.CORRENDO
		# PAL: a 1ª volta conta desde o VAI (TIME = TOTAL até cruzar a linha)
		valores.LAP_TIMER = (corrida.t - corrida.t_volta if corrida.volta > 1 else corrida.t) if correndo else null
		valores.TOTAL_TIMER = corrida.t if correndo else null
		valores.BEST_LAP_TIMER = corrida.melhor if corrida.melhor != INF else null
		valores.LEAD_TIMER = null
		lista.clear()
		pontos.clear()
		if corrida.ia and not corrida.ia.rivais.is_empty():
			valores.PLAYER_POS = corrida.ia.posicao_jogador()
			valores.NUM_PLAYERS = corrida.ia.rivais.size() + 1
			var cl: Array = corrida.ia.classificacao()
			for e in cl:
				lista.append({"nome": NOME_JOGADOR if e.jogador else String(e.nome), "jogador": e.jogador})
				var c = car if e.jogador else e.get("no")
				if c:
					pontos.append(_jogo_xz(c.global_position) + [e.jogador])
			if correndo:
				_lead(cl, corrida.t)
			else:
				_hist.clear()
		else:
			valores.PLAYER_POS = 1
			valores.NUM_PLAYERS = 1
			lista.append({"nome": NOME_JOGADOR, "jogador": true})
			pontos.append(_jogo_xz(car.global_position) + [true])
		animar_lista(passo)
	_pintar_barras()
	queue_redraw()


## LEAD (NOSSO): guarda quando cada carro passou em cada progresso; atrás =
## -(agora - quando o líder passou onde o jogador está), na frente = agora -
## quando o jogador passou onde o 2º está
func _lead(cl: Array, t: float) -> void:
	for e in cl:
		var h: Array = _hist.get(e.nome, [])
		if h.is_empty() or float(e.prog) > h[-1][0]:
			h.append([float(e.prog), t])
			if h.size() > 4000:
				h = h.slice(h.size() - 3000)
		_hist[e.nome] = h
	var eu := -1
	for i in cl.size():
		if cl[i].jogador:
			eu = i
	if eu < 0 or cl.size() < 2:
		return
	var gap := NAN
	if eu == 0:
		var tp := _quando(_hist.get(cl[0].nome, []), float(cl[1].prog))
		if not is_nan(tp):
			gap = t - tp
	else:
		var tl := _quando(_hist.get(cl[0].nome, []), float(cl[eu].prog))
		if not is_nan(tl):
			gap = -(t - tl)
	if is_nan(gap):
		return
	valores.LEAD_TIMER = gap
	valores["LEAD_TIMER#cor"] = COR_ATRAS if gap < 0.0 else COR_FRENTE


## o tempo em que o histórico passou pelo progresso p (interpolado)
static func _quando(h: Array, p: float) -> float:
	if h.is_empty() or p < h[0][0] or p > h[-1][0]:
		return NAN
	var a := 0
	var b := h.size() - 1
	while b - a > 1:
		var m := (a + b) / 2
		if h[m][0] <= p:
			a = m
		else:
			b = m
	var p0: float = h[a][0]
	var p1: float = h[b][0]
	if p1 <= p0:
		return h[a][1]
	return lerpf(h[a][1], h[b][1], (p - p0) / (p1 - p0))


## mundo do Godot -> (x, z) do jogo: mundo = (z - 1024, y, x) do jogo
static func _jogo_xz(p: Vector3) -> Array:
	return [p.z, p.x + 1024.0]


var _cache_nos := {}
func _no(nome: String):
	if not _cache_nos.has(nome):
		_cache_nos[nome] = _busca(raiz, nome)
	return _cache_nos[nome]


func _busca(no: Dictionary, nome: String):
	if no.get("nome", "") == nome:
		return no
	for f in no.get("filhos", []):
		var r = _busca(f, nome)
		if r:
			return r
	return null
