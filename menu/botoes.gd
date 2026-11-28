extends Node
## Ícones dos botões nos menus pelo aparelho que o jogador está usando
## (NOSSO, pedido do Matheus nov/2026; o jogo só tem os do PS2).
##  - "ps": os ícones do próprio jogo (new_buttons_4bit_en_GB do HUD);
##  - "xbox": círculo escuro com a letra na cor de sempre (A verde, B
##    vermelho, Y amarelo, X azul; Start = o botão de menu, 3 tracinhos);
##  - "pc": tecla clara com o nome (Enter, Esc).
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
## px); devolve false no "ps" (quem chama desenha o do jogo)
static func desenhar(ci: CanvasItem, caixa: String, r: Rect2, alfa: float) -> bool:
	var e := atual()
	var acao: String = ACAO.get(caixa, "ok")
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
			# botão de menu: 3 tracinhos
			var w := d * 0.42
			for k in 3:
				var y := c.y + (k - 1) * d * 0.16
				ci.draw_line(Vector2(c.x - w * 0.5, y), Vector2(c.x + w * 0.5, y), cor, maxf(d * 0.07, 1.0))
		else:
			var tam := int(d * 0.62)
			var s: String = x[0]
			var ts := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, tam)
			ci.draw_string(f, Vector2(c.x - ts.x * 0.5, c.y + f.get_ascent(tam) * 0.5 - f.get_descent(tam) * 0.35),
				s, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, cor)
		return true
	if e == "pc":
		var s: String = PC[acao]
		var h := minf(r.size.y, r.size.x) * 0.62
		var tam := int(h * 0.5)
		var ts := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, tam)
		var w := maxf(h, ts.x + h * 0.5)
		# encostada à direita (o texto da barra vem logo depois)
		var k := Rect2(r.end.x - w - r.size.x * 0.08, r.get_center().y - h * 0.5, w, h)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.9, 0.9, 0.88, alfa)
		sb.border_color = Color(0.25, 0.25, 0.27, alfa)
		sb.set_border_width_all(maxi(int(h * 0.06), 1))
		sb.border_width_bottom = maxi(int(h * 0.14), 2)     # cara de tecla
		sb.set_corner_radius_all(int(h * 0.18))
		sb.anti_aliasing = true
		sb.draw(ci.get_canvas_item(), k)
		ci.draw_string(f, Vector2(k.get_center().x - ts.x * 0.5, k.position.y + h * 0.5 + f.get_ascent(tam) * 0.38),
			s, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, Color(0.12, 0.12, 0.13, alfa))
		return true
	return false
