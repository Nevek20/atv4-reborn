extends Control
## HUD do jogo (HUD_PS2/HUD_CIRCUIT.xml, cFEXHUDManager_CIRCUIT), desenhado
## pelo layout do próprio jogo (data/hud_circuit.xml) com as texturas, caixas
## .bed e fontes do archive (tools/hud_jogo.py -> assets/hud).
##
## Layout (exe 0x46f7c0, enums da RAM em 0x83d1c0..0x83d1e0): cada objeto tem
## um Frame dentro do pai: ALIGN_LEFT/RIGHT/CENTRE em X, ALIGN_BOTTOM/TOP/
## CENTRE em Y (y pra cima), offset e escala. Modos de escala:
##   SCALE_RELATIVE      fração do pai
##   SCALE_UNIT_RELATIVE fração do pai, mas quadrada pelo lado menor do pai
##   SCALE_ABSOLUTE      fração da tela (X dividido pela razão da tela)
## mOffsetAbsolute: offset em fração da tela (como o ABSOLUTE). Sprite com
## mPixelScaleRatio > 0 (0x472778 -> 0x46f6e8): o tamanho vira o da caixa do
## .bed em pixels x razão, com 640 de largura de referência (pixel quadrado).
## Texto: célula = o Frame; a altura da célula é a altura da linha da fonte
## (FONT_SMALL 22 px, FONT_MEDIUM 30 px: o texto de 0.045 da tela cai 1:1).
## Velocímetro (OBJECT_SPEEDO, 0x4890d8): conta-giros main_speedo; o ponteiro
## (needle) gira em volta da needle_base, posta na speedo_base do mostrador,
## de mNeedleMinRot a mNeedleMaxRot pelas rpm / MAXREVS (a textura
## hud_tpage_rev9000/10000/12000 escolhida pelo limitador do carro).
## Barras (OBJECT_FILLBAR, 0x489ad0/0x489ee0): acendem trocando cores da CLUT
## da hud_tpage_bar por bloco (mFirstPaletteEntry, mNumBlocks,
## mEntriesPerBlock, mReverseEntries), o alfa fica o da paleta.
##
## NOSSO / ainda não lido do jogo: as cores das barras (mActiveColour não está
## no XML; o verde do acelerador e o preto apagado medidos no vídeo do
## speedrun; o vermelho do freio é chute), o LEAD (diferença pro líder) e os
## objetos ainda não portados: minimapa, lista de pilotos, bandeiras,
## mensagens e a seta (próximas etapas).

const LAYOUT := "res://data/hud_circuit.xml"
const DIR := "res://assets/hud/"
const LINHA := {"FONT_SMALL": 22.0, "FONT_MEDIUM": 30.0}   # altura da linha (px da fonte)
const REVS := [9000, 10000, 12000]
const COR_ACEL := Color8(13, 105, 15)      # vídeo do speedrun (acelerador no fundo)
const COR_FREIO := Color8(200, 20, 20)     # NOSSO: não aparece aceso no vídeo
const COR_APAGADA := Color(0, 0, 0)        # vídeo: as barras apagadas são pretas
const PASSO := 1.0 / 75.0                  # como o PASSO_HUD

var info := {}
var raiz := {}
var tex := {}
var lingua := "en"
var maxrevs := 10000
var valores := {}          # nome do objeto -> valor (int, float, String)
var rpm := 0.0
var em_corrida := false    # treino livre: só o conta-giros (NOSSO: o treino do jogo não foi lido)
const SO_CORRIDA := ["LEFT_BORDER", "RIGHT_BORDER", "LeadPosFrm", "LapTimeFrm", "BestLapTotalFrm",
	"TrickScoreFrm"]
var acel := 0.0            # 0..1
var freio := 0.0
var _barra_img: Image
var _barra_idx: PackedByteArray
var _barra_pal_a: PackedByteArray
var _barra_tex: ImageTexture
var _barra_estado := Vector2i(-1, -1)
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
	_preparar_barras()
	return not raiz.is_empty()


# ------------------------------------------------------------------ layout
func _ler_layout() -> Dictionary:
	var x := XMLParser.new()
	if x.open(LAYOUT) != OK:
		return {}
	var topo := {"nome": "", "tipo": "OBJECT_FRAME", "at": {}, "frame": {}, "cor": Color.WHITE, "filhos": []}
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
			elif n == "mColour":
				dono.cor = Color(float(at.get("R", 1)), float(at.get("G", 1)), float(at.get("B", 1)), float(at.get("A", 1)))
			elif n == "Children" or n == "Root":
				if not x.is_empty():
					pilha.append(dono)          # os filhos vão pro mesmo dono
			else:
				var no := {"nome": n, "tipo": at.get("mObjectType", "OBJECT_FRAME"), "at": at,
					"frame": {}, "cor": Color.WHITE, "filhos": []}
				dono.filhos.append(no)
				if not x.is_empty():
					pilha.append(no)
		elif t == XMLParser.NODE_ELEMENT_END:
			var n := x.get_node_name()
			if n != "Frame" and n != "mColour" and pilha.size() > 1:
				pilha.pop_back()
	return topo


static func _f(d: Dictionary, k: String, padrao := 0.0) -> float:
	return float(d.get(k, padrao))


## retângulo do objeto em fração da tela (x, y de baixo, w, h); pai idem.
## px = tamanho em pixels de referência (sprite com mPixelScaleRatio) ou ZERO
func _rect(fr: Dictionary, pai: Rect2, a: float, px := Vector2.ZERO) -> Rect2:
	if fr.is_empty():
		return pai
	var fx := a * pai.size.x
	var fy := pai.size.y
	var sx := _f(fr, "mScaleX", 1.0)
	var sy := _f(fr, "mScaleY", 1.0)
	if px != Vector2.ZERO:
		sx = px.x * a / 640.0
		sy = px.y * a / 640.0
		# 0x46f6e8: com a tela widescreen (DAT_007f3e3c+0x18 = 1) x 0.75; no
		# 4:3 (os save states do Matheus) 1. O vídeo do speedrun é 16:9 e o
		# conta-giros e as molduras batem com o 0.75
		if a > 1.5:
			sx *= 0.75
			sy *= 0.75
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


## fração da tela (y de baixo) -> pixels do Control (y de cima)
func _tela(r: Rect2) -> Rect2:
	var s := size
	return Rect2(r.position.x * s.x, (1.0 - r.position.y - r.size.y) * s.y, r.size.x * s.x, r.size.y * s.y)


func _textura(nome: String) -> String:
	nome = nome.get_file()
	if nome.begins_with("hud_tpage_rev"):
		return "hud_tpage_rev%d" % maxrevs
	return nome


func _caixa(tnome: String, caixa: String) -> Rect2:
	var t: Dictionary = info.texturas.get(tnome, {})
	var c: Array = t.get("caixas", {}).get(caixa, [])
	if c.is_empty():
		return Rect2(0, 0, t.get("w", 0), t.get("h", 0))
	return Rect2(c[0] * t.w, c[1] * t.h, (c[2] - c[0]) * t.w, (c[3] - c[1]) * t.h)


# ------------------------------------------------------------------ desenho
func _draw() -> void:
	if raiz.is_empty() or size.y <= 0.0:
		return
	var a := size.x / size.y
	for f in raiz.filhos:
		_desenha(f, Rect2(0, 0, 1, 1), a)


func _desenha(no: Dictionary, pai: Rect2, a: float) -> void:
	var at: Dictionary = no.at
	if at.has("mVisGroup") or no.tipo in ["OBJECT_MINIMAP", "OBJECT_PLAYERLIST_SPRITE", "OBJECT_PLAYERLIST_TEXT",
			"OBJECT_MESSAGE", "OBJECT_3DARROW", "OBJECT_PLACEMENT_MARKER", "OBJECT_SPRITE_ANIM"]:
		return                     # grupos que só aparecem em hora certa e objetos ainda não portados
	if not em_corrida and no.nome in SO_CORRIDA:
		return
	var px := Vector2.ZERO
	var tnome := _textura(String(at.get("mTexture", "")))
	var caixa := String(at.get("mBedBox", at.get("mSpeedoBedBox", "")))
	if float(at.get("mPixelScaleRatio", -1.0)) > 0.0 and tex.has(tnome):
		px = _caixa(tnome, caixa).size * float(at.mPixelScaleRatio)
	var r := _rect(no.frame, pai, a, px)
	match no.tipo:
		"OBJECT_SPRITE":
			if tex.has(tnome) and not (no.nome == "MINIMAP_SPRITE"):
				_sprite(tex[tnome], _caixa(tnome, caixa), _tela(r), String(at.get("mMirrorX", "0")) == "1", no.cor)
		"OBJECT_SPEEDO":
			_speedo(no, tnome, r)
		"OBJECT_FILLBAR":
			_barra(no, r)
		"OBJECT_TEXT":
			var k := String(at.get("mText", ""))
			var txt: String = info.get("textos", {}).get(lingua, {}).get(k, k)
			_texto(txt.to_upper(), String(at.get("mFont", "FONT_SMALL")), r, no.cor, at)
		"OBJECT_TIMER":
			_texto(_valor(no), String(at.get("mFont", "FONT_SMALL")), r, valores.get(no.nome + "#cor", no.cor), at)
		"OBJECT_INTEGER":
			var v: int = valores.get(no.nome, 0)
			_texto(_valor(no), String(at.get("mFont", "FONT_SMALL")), r, no.cor, at, str(absi(v)).length())
	for f in no.filhos:
		_desenha(f, r, a)


## {nome: Rect2 em pixels} de todos os objetos (testes e conferência)
func retangulos() -> Dictionary:
	var out := {}
	if not raiz.is_empty() and size.y > 0.0:
		_ret(raiz, Rect2(0, 0, 1, 1), size.x / size.y, out)
	return out


func _ret(no: Dictionary, pai: Rect2, a: float, out: Dictionary) -> void:
	var at: Dictionary = no.at
	var px := Vector2.ZERO
	var tnome := _textura(String(at.get("mTexture", "")))
	var caixa := String(at.get("mBedBox", at.get("mSpeedoBedBox", "")))
	if float(at.get("mPixelScaleRatio", -1.0)) > 0.0 and tex.has(tnome):
		px = _caixa(tnome, caixa).size * float(at.mPixelScaleRatio)
	var r := _rect(no.frame, pai, a, px)
	if no.nome != "":
		out[no.nome] = _tela(r)
	for f in no.filhos:
		_ret(f, r, a, out)


func _sprite(t: Texture2D, src: Rect2, dst: Rect2, espelha: bool, cor: Color) -> void:
	if espelha:                  # mMirrorX: vira no meio do próprio retângulo
		draw_set_transform(Vector2(dst.position.x * 2.0 + dst.size.x, 0.0), 0.0, Vector2(-1, 1))
		draw_texture_rect_region(t, dst, src, cor)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	draw_texture_rect_region(t, dst, src, cor)


func _valor(no: Dictionary) -> String:
	var v = valores.get(no.nome, null)
	var modelo := String(no.at.get("mText", "0"))
	if no.tipo == "OBJECT_TIMER":
		var s: float = v if v != null else 0.0
		var neg := s < 0.0
		s = absf(s)
		var cs := int(s * 100.0)
		var txt := "%02d:%02d:%02d" % [mini(cs / 6000, 99), (cs / 100) % 60, cs % 100]
		return ("-" + txt) if neg and String(no.at.get("mAllowNegative", "0")) == "1" else txt
	var n: int = v if v != null else 0
	if String(no.at.get("mZeroPad", "0")) == "1":
		return ("%0" + str(modelo.length()) + "d") % n
	return str(n)


## texto (exe 0x474e08 / 0x2689c0): glifo com a altura do quadro (escala =
## altura do quadro / linha da fonte), topo no topo do quadro. mTextAlignX:
## LEFT começa na borda esquerda, CENTRE no meio, RIGHT termina na direita.
## Número com mAlignCentre (0x475390): centrado na borda ESQUERDA do quadro
## pela largura do "8" x dígitos do valor. Avanço com o kerning da fonte.
func _texto(txt: String, fonte: String, r: Rect2, cor: Color, at: Dictionary, digitos := -1) -> void:
	if not tex.has(fonte):
		return
	var cel := _tela(r)
	var linha: float = LINHA.get(fonte, 22.0)
	var esc_y := cel.size.y / linha
	var esc_x := cel.size.x / linha
	var t: Dictionary = info.texturas[fonte]
	var cx: Dictionary = t.caixas
	var kern: Dictionary = t.get("kern", {})
	var cods := []
	for ch in txt:
		var k := ch.unicode_at(0)
		cods.append(k if cx.has(str(k)) else 32)
	var avancos := []
	var largura := 0.0
	for n in cods.size():
		var w: float = _caixa(fonte, str(cods[n])).size.x
		var prox: int = cods[n + 1] if n + 1 < cods.size() else 0
		var av := w - _kern(kern, cods[n], prox)
		avancos.append(av * esc_x)
		largura += av * esc_x
	var x := cel.position.x
	var al := String(at.get("mTextAlignX", "ALIGN_LEFT"))
	if digitos >= 0:
		if String(at.get("mAlignCentre", "0")) == "1":
			x -= _caixa(fonte, "56").size.x * esc_x * digitos * 0.5
	elif al == "ALIGN_CENTRE":
		x = cel.position.x + cel.size.x * 0.5 - largura * 0.5
	elif al == "ALIGN_RIGHT":
		x = cel.end.x - largura
	for n in cods.size():
		var c := _caixa(fonte, str(cods[n]))
		draw_texture_rect_region(tex[fonte], Rect2(x, cel.position.y, c.size.x * esc_x, c.size.y * esc_y), c, cor)
		x += avancos[n]


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


## conta-giros: mostrador + ponteiro girando em volta da needle_base, que fica
## na speedo_base do mostrador
func _speedo(no: Dictionary, tnome: String, r: Rect2) -> void:
	if not tex.has(tnome):
		return
	var at: Dictionary = no.at
	var mostrador := _caixa(tnome, String(at.get("mSpeedoBedBox", "main_speedo")))
	var dst := _tela(r)
	_sprite(tex[tnome], mostrador, dst, false, no.cor)
	var esc := dst.size / mostrador.size
	var base := _caixa(tnome, String(at.get("mSpeedoBaseBedBox", "speedo_base")))
	var pivo := dst.position + (base.get_center() - mostrador.position) * esc
	var agulha := _caixa(tnome, String(at.get("mNeedleBedBox", "needle")))
	var nbase := _caixa(tnome, String(at.get("mNeedleBaseBedBox", "needle_base")))
	var f := clampf(rpm / float(maxrevs), 0.0, 1.0)
	var ang := lerpf(float(at.get("mNeedleMinRot", -1.57)), float(at.get("mNeedleMaxRot", 3.1416)), f)
	# o ponteiro da textura aponta pra esquerda; 0 rpm aponta pro "0" (embaixo)
	draw_set_transform(pivo, ang, Vector2.ONE)
	var p0 := (agulha.position - nbase.get_center()) * esc
	_sprite(tex[tnome], agulha, Rect2(p0, agulha.size * esc), false, no.cor)
	_sprite(tex[tnome], nbase, Rect2((nbase.position - nbase.get_center()) * esc, nbase.size * esc), false, no.cor)
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


## pinta os blocos acesos/apagados das 2 barras (só quando muda). CPU: a
## lista dos pixels de barra sai uma vez (são ~700 de 16 mil)
var _pix_barra: Array = []         # [x, y, alfa, 0 acel / 1 freio, bloco]
func _pintar_barras() -> void:
	if _barra_img == null:
		return
	if _pix_barra.is_empty():
		var w := _barra_img.get_width()
		for i in _barra_idx.size():
			var k := _barra_idx[i]
			if k >= 224:               # ACCEL 239 -> 224, BRAKE 255 -> 240 (mReverseEntries)
				var px := Vector2i(i % w, i / w)
				_pix_barra.append([px.x, px.y, _barra_img.get_pixelv(px).a, 0 if k <= 239 else 1, (239 - k) if k <= 239 else (255 - k)])
	var n_acel := int(round(acel * 16.0))
	var n_freio := int(round(freio * 16.0))
	var est := Vector2i(n_acel, n_freio)
	if est == _barra_estado:
		return
	_barra_estado = est
	for p in _pix_barra:
		var cor := COR_APAGADA
		if p[3] == 0 and p[4] < n_acel:
			cor = COR_ACEL
		elif p[3] == 1 and p[4] < n_freio:
			cor = COR_FREIO
		_barra_img.set_pixel(p[0], p[1], Color(cor.r, cor.g, cor.b, p[2]))
	_barra_tex.update(_barra_img)


func _barra(no: Dictionary, r: Rect2) -> void:
	if _barra_tex == null or no.nome == "PRELOAD_BAR":
		return                       # preload: carga da suspensão pro pulo (ATV), apagada
	var at: Dictionary = no.at
	var c := _caixa("hud_tpage_bar", String(at.get("mBedBox", "")))
	draw_texture_rect_region(_barra_tex, _tela(r), c)


# ------------------------------------------------------------------ dados
## car: o carro do jogador; corrida: pista/corrida.gd (ou null no treino)
func atualizar(dt: float, car, corrida) -> void:
	_dt += dt
	if _dt < PASSO:
		return
	_dt = 0.0
	if car == null:
		return
	var lim: float = car.P.get("lim_on", 8000.0)
	maxrevs = REVS[-1]
	for rv in REVS:
		if lim <= rv:
			maxrevs = rv
			break
	rpm = car.rpm
	acel = clampf(car.throttle, 0.0, 1.0)      # pedais suavizados (+0x380 / +0x390)
	freio = clampf(car.brake_in, 0.0, 1.0)
	valores.SPEED = int(absf(car.linear_velocity.dot(car.global_transform.basis.z)) * 3.6 * 1.06)
	var g: int = car.gear
	valores.GEAR = maxi(g, 0)
	em_corrida = corrida != null and corrida.estado != 0
	if em_corrida:
		valores.CURRENT_LAP = maxi(corrida.volta, 1)
		valores.TOTAL_LAPS = corrida.voltas
		valores.LAP_TIMER = corrida.t - corrida.t_volta if corrida.volta > 0 else corrida.t
		valores.TOTAL_TIMER = corrida.t
		valores.BEST_LAP_TIMER = corrida.melhor if corrida.melhor != INF else 0.0
		if corrida.ia and not corrida.ia.rivais.is_empty():
			valores.PLAYER_POS = corrida.ia.posicao_jogador()
			valores.NUM_PLAYERS = corrida.ia.rivais.size() + 1
		else:
			valores.PLAYER_POS = 1
			valores.NUM_PLAYERS = 1
	_pintar_barras()
	queue_redraw()
