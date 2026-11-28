extends Node
## Ícones dos botões nos menus pelo aparelho que o jogador está usando
## (NOSSO, pedido do Matheus nov/2026; o jogo só tem os do PS2).
##  - "ps": os ícones do próprio jogo (new_buttons_4bit_en_GB do HUD);
##  - "xbox": o selo do Cruz do jogo com A / B por cima (Start = o botão de
##    menu, 3 tracinhos), preto como os símbolos do jogo;
##  - "pc": o selo do L1 do jogo (uma tecla) com Esc / Enter por cima.
##  Os dois montados em pixels na resolução do selo, com a FONT_SMALL do jogo.
## Troca sozinho pelo último aparelho usado: teclado / mouse = pc; controle =
## pelo nome que o Godot dá (PlayStation, DualShock, DualSense, Sony = ps; o
## resto, Xbox e desconhecido, = xbox). Sem nenhum toque ainda: o controle
## ligado, senão pc. Ficar fixo num deles = FIXO (depois, nas opções de
## controle).
## Ação -> botão: ok = Cruz / A / Enter; voltar = Triângulo / B / Esc (o B
## foi escolha do Matheus; o Y continua voltando, é a posição do Triângulo);
## start = Start / Menu / Enter.
## Multiplayer local: hoje um estilo pra tela toda (o do último aparelho);
## com 2 jogadores cada um vai ter o do controle dele (por aparelho).

static var estilo := ""                 # "ps", "xbox" ou "pc"
static var FIXO := ""                   # "" = automático

const NOMES_PS := ["playstation", "dualshock", "dualsense", "sony", "ps2", "ps3", "ps4", "ps5"]
# ícone do jogo (caixa no atlas do HUD) -> ação
const ACAO := {"cross_button": "ok", "triangle_button": "voltar", "start_button": "start"}
const XBOX := {"ok": ["A", Color(0.38, 0.73, 0.26)], "voltar": ["B", Color(0.86, 0.2, 0.18)],
	"start": ["", Color(0.9, 0.9, 0.9)]}
const PC := {"ok": "ENTER", "voltar": "ESC", "start": "ENTER"}   # maiúsculas como os selos do jogo (L1, START)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS    # a pausa congela o resto
	if estilo == "":
		var j := Input.get_connected_joypads()
		estilo = de_controle(Input.get_joy_name(j[0])) if not j.is_empty() else "pc"


func _input(ev: InputEvent) -> void:
	var novo := ""
	if ev is InputEventKey or ev is InputEventMouseButton:
		novo = "pc"
	elif ev is InputEventJoypadButton:
		novo = de_controle(Input.get_joy_name(ev.device))
	elif ev is InputEventJoypadMotion and absf(ev.axis_value) > 0.5:
		novo = de_controle(Input.get_joy_name(ev.device))     # analógico parado com folga não troca
	if novo != "":
		estilo = novo


static func atual() -> String:
	if FIXO != "":
		return FIXO
	return estilo if estilo != "" else "ps"


static func de_controle(nome: String) -> String:
	var n := nome.to_lower()
	for k in NOMES_PS:
		if n.contains(k):
			return "ps"
	return "xbox"


## desenha o ícone (xbox / pc) no lugar do ícone do PS2 (r = a caixa dele em
## px); devolve false no "ps" (quem chama desenha o do jogo). Com o atlas do
## jogo: o selo original com a letra por cima (o Matheus: "pegar os botões
## originais e colocar por cima"), montado NA RESOLUÇÃO DO SELO (icone()):
## a letra sai com os mesmos pixels do botão (o Matheus: "as letras estão
## muito bonitas em comparação aos botões"). fontes = {"FONT_SMALL": [textura,
## glifos], "FONT_MEDIUM": [...]} (os glifos do menu/resultados.gd). Sem o
## atlas, o desenho simples
static func desenhar(ci: CanvasItem, caixa: String, r: Rect2, alfa: float, tx: Texture2D = null,
		caixas: Dictionary = {}, fontes: Dictionary = {}) -> bool:
	var e := atual()
	if e == "ps":
		return false
	var acao: String = ACAO.get(caixa, "ok")
	var ic: Array = icone(e, acao, tx, caixas, fontes) if tx else []
	if not ic.is_empty():
		# a tecla alargada cresce pra esquerda (o texto da barra vem depois)
		var k: float = ic[1]
		var r2 := Rect2(r.end.x - r.size.x * k, r.position.y, r.size.x * k, r.size.y)
		ci.draw_texture_rect(ic[0], r2, false, Color(1, 1, 1, alfa))
		return true
	_simples(ci, e, acao, r, alfa)
	return true


const COR_LETRA := Color(0.0, 0.0, 0.0)              # preta como os símbolos do jogo
static var _cache := {}                               # "xbox:ok" -> [ImageTexture, largura / a do selo]


## o ícone montado em pixels, do tamanho do selo no atlas: [textura, largura
## em relação ao selo (1 = igual)]
##  - Xbox = o selo do Cruz (45 x 56): o símbolo do meio (as peças escuras
##    soltas dentro do anel: o X e a borda clara dele) vira branco e a letra
##    entra no centro do anel. Até nov/2026 era um círculo branco por cima e
##    a ponta do X sobrava na borda (o "risquinho" que o Matheus viu);
##  - PC = o selo do L1 (46 x 55): a tecla branca de (11, 16) a (41, 32) é
##    limpa e o nome entra nela; se não cabe, a tecla alarga repetindo a
##    coluna do meio (a letra nunca encolhe).
## Letras = a FONT_SMALL do jogo (a do HUD), maiúsculas, pretas, no tamanho
## dela, só o corpo da letra (sem a sombra) e centradas pelo corpo: no
## círculo, no centro do X que saiu; na tecla, no meio dela. [] = sem a
## imagem do atlas
static func icone(e: String, acao: String, tx: Texture2D, caixas: Dictionary, fontes: Dictionary) -> Array:
	var chave := e + ":" + acao
	if _cache.has(chave):
		return _cache[chave]
	var base := "cross_button" if e == "xbox" else "L1_button"
	var atlas := _imagem(tx)
	if atlas == null or not caixas.has(base):
		return []
	var b: Array = caixas[base]
	var w := atlas.get_width()
	var h := atlas.get_height()
	var reg := Rect2i(int(b[0] * w), int(b[1] * h), int(b[2] * w) - int(b[0] * w), int(b[3] * h) - int(b[1] * h))
	var img := atlas.get_region(reg)
	var w0 := img.get_width()
	var branco := Color(1, 1, 1, 1)
	var f: Array = fontes.get("FONT_SMALL", [])
	var letras: Array = _glifos(f, XBOX[acao][0] if e == "xbox" else PC[acao])
	if e == "xbox":
		var cx := _limpa_miolo(img, Vector2(img.get_width() * 0.5 + 0.5, img.get_height() * 0.455))
		if acao == "start":
			# botão de menu: 3 tracinhos de 2 px
			for n in 3:
				img.fill_rect(Rect2i(int(cx.x) - 6, int(cx.y + (n - 1) * 4 - 1), 12, 2), COR_LETRA)
		else:
			_escrever(img, letras, cx)
	else:
		var larg_txt := _largura(letras)
		var falta := maxi(0, larg_txt + 4 - 30)
		if falta > 0:
			img = _alarga(img, 26, falta)
		var k := Rect2i(11, 16, 30 + falta, 16)
		img.fill_rect(k, branco)
		_escrever(img, letras, Vector2(k.get_center()))
	var out := [ImageTexture.create_from_image(img), float(img.get_width()) / float(w0)]
	_cache[chave] = out
	return out


## a imagem de uma textura em RGBA8 (null no servidor de testes sem GPU)
static func _imagem(t: Texture2D) -> Image:
	if t == null:
		return null
	var im := t.get_image()
	if im == null or im.is_empty():
		return null
	im = im.duplicate()
	if im.is_compressed():
		im.decompress()
	im.convert(Image.FORMAT_RGBA8)
	return im


## apaga o símbolo do meio do selo: as peças escuras (com a borda
## antisserrilhada) que não encostam no anel nem saem do selo, a partir do
## centro. Devolve o centro do símbolo apagado (o meio do anel que o
## desenhista usou; sem símbolo, c)
static func _limpa_miolo(img: Image, c: Vector2) -> Vector2:
	var w := img.get_width()
	var h := img.get_height()
	var escuro := func(x: int, y: int) -> bool:
		var p := img.get_pixel(x, y)
		return p.a > 0.25 and p.r < 0.8
	var visto := {}
	var pecas: Array = []
	var raio := minf(w, h) * 0.2            # só peças com algum pixel perto do centro
	for y in h:
		for x in w:
			var k := y * w + x
			if visto.has(k) or not escuro.call(x, y):
				continue
			# flood fill da peça (4 vizinhos)
			var peca: Array = []
			var pilha: Array = [k]
			visto[k] = true
			var perto := false
			var borda := false
			while not pilha.is_empty():
				var q: int = pilha.pop_back()
				var qx := q % w
				var qy := q / w
				peca.append(q)
				if Vector2(qx + 0.5, qy + 0.5).distance_to(c) < raio:
					perto = true
				if qx == 0 or qy == 0 or qx == w - 1 or qy == h - 1:
					borda = true
				for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx: int = qx + dv.x
					var ny: int = qy + dv.y
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					var nk := ny * w + nx
					if not visto.has(nk) and escuro.call(nx, ny):
						visto[nk] = true
						pilha.append(nk)
			# o símbolo: perto do centro, menor que o anel e sem tocar a borda
			if perto and not borda and peca.size() < w * h / 8:
				pecas.append(peca)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for peca in pecas:
		for q in peca:
			img.set_pixel(q % w, q / w, Color(1, 1, 1, 1))
			lo = lo.min(Vector2(q % w, q / w))
			hi = hi.max(Vector2(q % w + 1, q / w + 1))
		# o rastro claro em volta (o antisserrilhado do X): os vizinhos cinza
		# claro também; o anel (escuro) fica
		for q in peca:
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx: int = q % w + dx
					var ny: int = q / w + dy
					if nx >= 0 and ny >= 0 and nx < w and ny < h and img.get_pixel(nx, ny).r > 0.5:
						img.set_pixel(nx, ny, Color(1, 1, 1, 1))
	return (lo + hi) * 0.5 if lo.x < INF else c


## a tecla mais larga: repete a coluna x n vezes
static func _alarga(img: Image, x: int, n: int) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var out := Image.create(w + n, h, false, Image.FORMAT_RGBA8)
	out.blit_rect(img, Rect2i(0, 0, x, h), Vector2i(0, 0))
	for k in n:
		out.blit_rect(img, Rect2i(x, 0, 1, h), Vector2i(x + k, 0))
	out.blit_rect(img, Rect2i(x, 0, w - x, h), Vector2i(x + n, 0))
	return out


## os glifos de s na fonte do jogo, já recortados e pretos
static func _glifos(f: Array, s: String) -> Array:
	if f.size() < 2:
		return []
	var fonte := _imagem(f[0])
	var glifos: Dictionary = f[1]
	if fonte == null or glifos.is_empty():
		return []
	var out: Array = []
	for ch in s:
		var g = glifos.get(ch.unicode_at(0))
		if g == null:
			continue
		var gi := fonte.get_region(Rect2i(g[0]))
		# só o corpo da letra: na fonte do jogo a letra é o branco e a sombra
		# (cinza e escuro, pra baixo e pra direita) entortava o centro. Peso =
		# alfa x o quanto o pixel é claro (cinza = meio, o antisserrilhado)
		var lo := Vector2i(9999, 9999)
		var hi := Vector2i(-1, -1)
		for y in gi.get_height():
			for x in gi.get_width():
				var c := gi.get_pixel(x, y)
				var a := c.a * clampf((c.get_luminance() - 0.35) / 0.5, 0.0, 1.0)
				gi.set_pixel(x, y, Color(COR_LETRA.r, COR_LETRA.g, COR_LETRA.b, a))
				if a > 0.5:
					lo = lo.min(Vector2i(x, y))
					hi = hi.max(Vector2i(x + 1, y + 1))
		if hi.x < 0:
			continue
		out.append(gi.get_region(Rect2i(lo, hi - lo)))
	return out


static func _largura(letras: Array) -> int:
	var l := 0
	for gi in letras:
		l += (gi as Image).get_width() + 1
	return maxi(l - 1, 0)


## escreve os glifos (no tamanho deles) centrados no ponto
static func _escrever(img: Image, letras: Array, centro: Vector2) -> void:
	if letras.is_empty():
		return
	var alt := 0
	for gi in letras:
		alt = maxi(alt, (gi as Image).get_height())
	var x := int(floorf(centro.x - _largura(letras) * 0.5 + 0.5))
	var y := int(floorf(centro.y - alt * 0.5 + 0.5))
	for gi in letras:
		var g: Image = gi
		img.blend_rect(g, Rect2i(Vector2i.ZERO, g.get_size()), Vector2i(x, y + alt - g.get_height()))
		x += g.get_width() + 1


## texto centrado no ponto (a altura das maiúsculas no meio)
static func _texto(ci: CanvasItem, f: Font, s: String, c: Vector2, tam: int, cor: Color) -> void:
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x
	ci.draw_string(f, Vector2(c.x - w * 0.5, c.y + tam * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, cor)


## sem o atlas do jogo: círculo escuro com a letra colorida (Xbox) ou tecla
## clara (PC)
static func _simples(ci: CanvasItem, e: String, acao: String, r: Rect2, alfa: float) -> void:
	var f: Font = ThemeDB.fallback_font
	if e == "xbox":
		var d := minf(r.size.x, r.size.y) * 0.78
		var c := r.get_center()
		ci.draw_circle(c, d * 0.5, Color(0.1, 0.1, 0.11, alfa))
		ci.draw_arc(c, d * 0.5, 0.0, TAU, 40, Color(0.55, 0.55, 0.58, alfa), maxf(d * 0.06, 1.0), true)
		var x: Array = XBOX[acao]
		var cor: Color = x[1]
		cor.a = alfa
		if acao == "start":
			var w := d * 0.42
			for k in 3:
				var y := c.y + (k - 1) * d * 0.16
				ci.draw_line(Vector2(c.x - w * 0.5, y), Vector2(c.x + w * 0.5, y), cor, maxf(d * 0.07, 1.0))
		else:
			_texto(ci, f, x[0], c, int(d * 0.62), cor)
		return
	var s: String = PC[acao]
	var h := minf(r.size.y, r.size.x) * 0.62
	var tam := int(h * 0.5)
	var ts := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, tam)
	var w := maxf(h, ts.x + h * 0.5)
	var k := Rect2(r.end.x - w - r.size.x * 0.08, r.get_center().y - h * 0.5, w, h)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.9, 0.9, 0.88, alfa)
	sb.border_color = Color(0.25, 0.25, 0.27, alfa)
	sb.set_border_width_all(maxi(int(h * 0.06), 1))
	sb.border_width_bottom = maxi(int(h * 0.14), 2)
	sb.set_corner_radius_all(int(h * 0.18))
	sb.anti_aliasing = true
	sb.draw(ci.get_canvas_item(), k)
	_texto(ci, f, s, k.get_center(), tam, Color(0.12, 0.12, 0.13, alfa))
