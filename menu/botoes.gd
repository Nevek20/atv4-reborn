extends Node
## Ícones dos botões nos menus pelo aparelho que o jogador está usando
## (NOSSO, pedido do Matheus nov/2026; o jogo só tem os do PS2).
##  - "ps": os ícones do próprio jogo (new_buttons_4bit_en_GB do HUD);
##  - "xbox": o selo do Cruz do jogo com A / B por cima (Start = o botão de
##    menu, 3 tracinhos), preto como os símbolos do jogo;
##  - "pc": o selo do L1 do jogo (uma tecla) com Esc / Enter por cima.
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
const PC := {"ok": "Enter", "voltar": "Esc", "start": "Enter"}


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
## jogo (tx + caixas do new_buttons_4bit_en_GB): o selo original com a letra
## por cima (o Matheus: "pegar os botões originais e colocar por cima"):
## Xbox = o selo do Cruz com o miolo apagado e A / B (ou os 3 tracinhos do
## menu); PC = o selo do L1 (a tecla) com Esc / Enter. Sem o atlas, o desenho
## simples de antes
static func desenhar(ci: CanvasItem, caixa: String, r: Rect2, alfa: float, tx: Texture2D = null,
		caixas: Dictionary = {}) -> bool:
	var e := atual()
	if e == "ps":
		return false
	var acao: String = ACAO.get(caixa, "ok")
	var base := "cross_button" if e == "xbox" else "L1_button"
	if tx and caixas.has(base):
		_selo(ci, e, acao, r, alfa, tx, caixas[base])
		return true
	_simples(ci, e, acao, r, alfa)
	return true


## o miolo de cada selo, em fração da caixa dele no atlas (medido no
## new_buttons_4bit_en_GB, 256 x 256): o Cruz (45 x 56) tem o anel com
## centro em (22.5, 25.5) e 11 px por dentro; o L1 (46 x 55) tem a tecla
## branca de (11, 16) a (41, 32)
const MIOLO_CRUZ := Vector3(0.5, 0.455, 0.215)        # centro x, y e raio (x largura)
const MIOLO_L1 := Rect2(0.239, 0.291, 0.652, 0.291)
const COR_LETRA := Color(0.0, 0.0, 0.0)              # preta como os símbolos do jogo
static var _fonte: Font = null


static func _fonte_negrito() -> Font:
	if _fonte == null:
		var fv := FontVariation.new()
		fv.base_font = ThemeDB.fallback_font
		fv.variation_embolden = 0.9
		_fonte = fv
	return _fonte


static func _selo(ci: CanvasItem, e: String, acao: String, r: Rect2, alfa: float, tx: Texture2D, b: Array) -> void:
	var ts := tx.get_size()
	ci.draw_texture_rect_region(tx, r, Rect2(b[0] * ts.x, b[1] * ts.y, (b[2] - b[0]) * ts.x, (b[3] - b[1]) * ts.y),
		Color(1, 1, 1, alfa))
	var f := _fonte_negrito()
	var branco := Color(1, 1, 1, alfa)
	var cor := Color(COR_LETRA.r, COR_LETRA.g, COR_LETRA.b, alfa)
	if e == "xbox":
		var c := Vector2(r.position.x + MIOLO_CRUZ.x * r.size.x, r.position.y + MIOLO_CRUZ.y * r.size.y)
		var raio := MIOLO_CRUZ.z * minf(r.size.x, r.size.y * 45.0 / 56.0)
		ci.draw_circle(c, raio, branco)
		if acao == "start":
			var w := raio * 1.1
			for k in 3:
				var y := c.y + (k - 1) * raio * 0.42
				ci.draw_line(Vector2(c.x - w * 0.5, y), Vector2(c.x + w * 0.5, y), cor, maxf(raio * 0.2, 1.0))
		else:
			_texto(ci, f, XBOX[acao][0], c, int(raio * 1.45), cor)
		return
	var k := Rect2(r.position.x + MIOLO_L1.position.x * r.size.x, r.position.y + MIOLO_L1.position.y * r.size.y,
		MIOLO_L1.size.x * r.size.x, MIOLO_L1.size.y * r.size.y)
	ci.draw_rect(k, branco)
	var s: String = PC[acao]
	# a maior letra que cabe na tecla
	var tam := int(k.size.y * 0.8)
	while tam > 6 and f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x > k.size.x * 0.9:
		tam -= 1
	_texto(ci, f, s, k.get_center(), tam, cor)


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
