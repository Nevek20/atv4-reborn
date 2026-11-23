extends Control
## Telas do menu da corrida, desenhadas pelas camadas do jogo
## (data/fex_resultados.json, tools/fex_jogo.py), uma por vez (pagina):
##   - "resultados": tela de resultados (cSRResultsPage, tipo de evento 0):
##     LAYER_RESULTS do PostRace.fex;
##   - "pausa": menu de pausa (LAYER_PAUSE_MENU do NewPause.fex; opções do
##     0x462190, barra Select / Back do 0x457b00);
##   - "de_novo": Race again (LAYER_FINISHED_RACE do PostRace.fex, 0x4cd270:
##     Restart / Exit), depois do Continue dos resultados.
## Em todas: o título LAYER_FAKE_HISTORY (Common.fex, que traz o fundo
## LAYER_PAUSE_BACKGROUND do NewPause.fex) no ID_FAKE_HISTORY_FRAME, a
## fileira de opções LAYER_SELECTOR no ID_SELECTOR_FRAME e a barra
## LAYER_IG_BUTTON_BAR. Records e Race Finished (cRecordsPage,
## cRaceFinishedPage) ainda não portadas.
##
## Conta (conferida com a RAM do placar_final.p2s, 50 textos):
##   - quadro: rect (X, Y, W, H) em NDC (y pra cima, Y = embaixo); o filho
##     vive no NDC do pai: X = Xp + (x + 1) / 2 x Wp, W = w / 2 x Wp (o mesmo
##     em y). Tela 640 x 480 de referência num 4:3 da altura da janela.
##   - texto (cDOString): fonte do Ingame.fpj (0 FE_FontSmall, 1 FE_FontMedium,
##     2 FE_FontLarge), altura = linha da fonte (22 / 30 / 35 px) x mScale,
##     largura das letras e kerning como no HUD (menu/hud_jogo.gd glifos);
##     mJustify 17 = centrado no rect nos dois eixos; mFlags 16 = maiúsculas;
##     cor de cima mColour1, de baixo mColour2; mRotation em rad em volta do
##     canto de cima à esquerda do texto (o título: 0.05).
##   - sprite (cDOSprite): caixa U0..U1 x V1 (cima)..V0 (baixo) da textura,
##     cor em cada canto x mAlpha; mRotation em GRAUS em volta do mHotspot
##     (-1..1 no sprite, -1 -1 = canto de baixo à esquerda).
##   - cDOMovingSprite: anda mVelocityX por segundo até mEndXPos e volta.
##   - mJustify: 0x10 centra na altura, 0x01 na largura (17 = os dois; o
##     seletor usa 16: encostado à esquerda e centrado na altura).
##   - seletor (cDOMenuSelector, RAM do pause.p2s e finish_2.p2s): a opção
##     atual no ID_CURRENT_OPT_TEXT (escala 1.4, encostada no ID_SELECTOR) e
##     as outras numa linha só no ID_NEXT_OPT_TEXT (0.8), separadas por 3
##     espaços, começando 16 px (640 x 480) depois do avanço da atual.
## Preenchido pelo código do jogo (RAM): uma linha por corredor (posição,
## nome, tempo total e melhor volta "mm:ss.cc", Stunt Score), a do jogador
## com o Player_N_Highlight; o título "Race Results"; a barra com o botão
## START (new_buttons_4bit_en_GB start_button) e "Continue".
## NOSSO: os sprites que cobrem a largura toda esticam na tela larga (o
## resto fica no 4:3 do meio); Enter / A = Continue volta pro treino livre.

const ARQ := "res://data/fex_resultados.json"
const UI := "res://assets/ui/"
const HUD := "res://assets/hud/"
const FONTES := ["FONT_SMALL", "FONT_MEDIUM", "FONT_LARGE"]       # Ingame.fpj Font0..2
const LINHA := {"FONT_SMALL": 22.0, "FONT_MEDIUM": 30.0, "FONT_LARGE": 35.0}
const NOME_JOGADOR := "PLAYER"    # o nome do perfil (NOSSO: ainda sem perfil)
# barra de baixo (RAM do placar_final.p2s): o botão START no
# ID_BUTTON_BAR_FRAME ([0.59446, -2.8, 0.16552, 5.6] nele) e o texto do lado
# (canto de cima à esquerda, escala 0.8)
const CONTINUE_POS := Vector2(0.6887, -0.7417)
const CONTINUE_ESC := 0.8
# botão da barra: o ícone (new_buttons_4bit_en_GB) acaba onde o texto começa,
# do tamanho do START_RECT (0.15 x 0.2333 NDC, embaixo em -0.9083)
const BOTAO_W := 0.15
const BOTAO_Y := -0.908333
const BOTAO_H := 0.233333
# por página: [caixa do ícone, texto, x do texto (RAM)]
const BARRA := {
	"resultados": [["start_button", "CONTINUE", 0.6887]],
	"pausa": [["cross_button", "SELECT", 0.3787], ["triangle_button", "BACK", 0.7762]],
	"de_novo": [["cross_button", "CONTINUE", 0.6887]],
}
const CAMADA := {"resultados": "LAYER_RESULTS", "pausa": "LAYER_PAUSE_MENU", "de_novo": "LAYER_FINISHED_RACE"}
const TITULO := {"resultados": "RACE_RESULTS", "pausa": "PAUSE_MENU", "de_novo": "Race_again"}
# quadros que o código do jogo esconde nessas telas (erro de disco; na Race
# again do Rallycross: próxima pista, pneus e piso)
const ESCONDIDOS := ["ID_DISK_ERROR_MSG_FRAME", "ID_NEXT_TRACK", "ID_NEW_TIREBEHAVIOUR", "ID_NEW_WEATHERANDSURFACE"]
const GAP_OPCAO := 16.0           # px entre a opção atual e as próximas (RAM)
const SEP_OPCOES := "   "
# textos da tabela do jogo (text/15205_en.txt), caso o ui.json seja de antes
const TEXTOS_EN := {"PAUSE_MENU": "PAUSE MENU", "Resume": "Resume", "Respot": "Respot", "RESTART": "Restart",
	"QUIT": "Quit", "Game_options": "Game options", "Photographer": "Photographer", "Race_again": "Race again",
	"EXIT": "Exit", "SELECT": "Select", "BACK": "Back", "CONTINUE": "Continue", "RACE_RESULTS": "Race Results"}

var lay := {}
var info := {}                    # ui.json: texturas, caixas, textos
var tex := {}                     # nome -> Texture2D
var _fonte := {}                  # fonte -> {código: [caixa (px na textura), largura]}
var _kern := {}
var lingua := "en"
var linhas: Array = []            # [{pos, nome, total, melhor, score, jogador}]
var t := 0.0                      # tempo na tela (sprites que andam)
var pagina := "resultados"
var opcoes: Array = []            # chaves de texto das opções do seletor
var opcao := 0
var dono = null                   # main.gd: menu_acao(pagina, acao, opção)
var _a := Rect2()                 # área 4:3 na tela
var _cheia := Rect2()             # a tela toda
var _medindo = null               # medir(): junta os textos em vez de desenhar


func montar() -> bool:
	if not FileAccess.file_exists(ARQ) or not FileAccess.file_exists(UI + "ui.json"):
		return false
	lay = JSON.parse_string(FileAccess.get_file_as_string(ARQ))
	info = JSON.parse_string(FileAccess.get_file_as_string(UI + "ui.json"))
	var hud: Dictionary = {}
	if FileAccess.file_exists(HUD + "hud.json"):
		hud = JSON.parse_string(FileAccess.get_file_as_string(HUD + "hud.json"))
	# FONT_SMALL / MEDIUM: as mesmas do HUD (assets/hud); FONT_LARGE e o resto: assets/ui
	for k in hud.get("texturas", {}):
		if String(k) in ["FONT_SMALL", "FONT_MEDIUM"]:
			info.texturas[k] = hud.texturas[k]
			info.texturas[k]["dir"] = HUD
	for k in info.texturas:
		var d: String = info.texturas[k].get("dir", UI)
		var p: String = d + String(info.texturas[k].png)
		if ResourceLoader.exists(p):
			tex[k] = load(p)
		elif FileAccess.file_exists(p):
			tex[k] = ImageTexture.create_from_image(Image.load_from_file(ProjectSettings.globalize_path(p)))
	_preparar_fontes()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	return not tex.is_empty()


## glifos como o HUD: largura arredondada, dígitos com a largura do maior
func _preparar_fontes() -> void:
	for fonte in FONTES:
		if not info.texturas.has(fonte):
			continue
		var tx: Dictionary = info.texturas[fonte]
		var w := float(tx.w)
		var h := float(tx.h)
		var g := {}
		var wdig := 0.0
		for k in tx.caixas:
			if not String(k).is_valid_int():
				continue
			var b: Array = tx.caixas[k]
			var cx := Rect2(b[0] * w, b[1] * h, (b[2] - b[0]) * w, (b[3] - b[1]) * h)
			var c := int(k)
			g[c] = [cx, roundf(cx.size.x)]
			if c >= 48 and c <= 57:
				wdig = maxf(wdig, roundf(cx.size.x))
		for c in range(48, 58):
			if g.has(c):
				var cx: Rect2 = g[c][0]
				g[c] = [Rect2(cx.get_center().x - wdig * 0.5, cx.position.y, wdig, cx.size.y), wdig]
		_fonte[fonte] = g
		_kern[fonte] = tx.get("kern", {})


func _txt(k: String) -> String:
	return String(info.get("textos", {}).get(lingua, {}).get(k, TEXTOS_EN.get(k, k)))


# ------------------------------------------------------------------ dados
## monta as linhas a partir da classificação (pista/ia.gd classificacao()):
## [{nome, fim, jogador, score, melhor}]
func mostrar(cl: Array) -> void:
	pagina = "resultados"
	opcoes = []
	linhas_de(cl)
	t = 0.0
	visible = true
	queue_redraw()


## tela com seletor (pausa, de_novo): opções = chaves de texto
func abrir_menu(pag: String, ops: Array) -> void:
	pagina = pag
	opcoes = ops.duplicate()
	opcao = 0
	t = 0.0
	visible = true
	queue_redraw()


func mover(d: int) -> void:
	if not opcoes.is_empty():
		opcao = posmod(opcao + d, opcoes.size())
		queue_redraw()


func escolhida() -> String:
	return String(opcoes[opcao]) if opcao < opcoes.size() else ""


## setas / X (ok) / triângulo ou Esc (voltar); Start na pausa volta pro jogo
func _unhandled_input(ev: InputEvent) -> void:
	if not visible or opcoes.is_empty():
		return
	var acao := ""
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.physical_keycode:
			KEY_LEFT:
				acao = "esq"
			KEY_RIGHT:
				acao = "dir"
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				acao = "ok"
			KEY_ESCAPE, KEY_BACKSPACE:
				acao = "voltar"
	elif ev is InputEventJoypadButton and ev.pressed:
		match ev.button_index:
			JOY_BUTTON_DPAD_LEFT:
				acao = "esq"
			JOY_BUTTON_DPAD_RIGHT:
				acao = "dir"
			JOY_BUTTON_A:
				acao = "ok"
			JOY_BUTTON_Y, JOY_BUTTON_START:
				acao = "voltar"
	elif ev is InputEventJoypadMotion and ev.axis == JOY_AXIS_LEFT_X:
		var lado := 0 if absf(ev.axis_value) < 0.5 else int(signf(ev.axis_value))
		if lado != _eixo and lado != 0:
			acao = "esq" if lado < 0 else "dir"
		_eixo = lado
	if acao == "":
		return
	get_viewport().set_input_as_handled()
	if acao == "esq":
		mover(-1)
	elif acao == "dir":
		mover(1)
	elif dono:
		dono.menu_acao(pagina, acao, escolhida())


var _eixo := 0


## troca as linhas sem recomeçar a tela (os quadriculados seguem andando)
func linhas_de(cl: Array) -> void:
	linhas.clear()
	for i in cl.size():
		var e: Dictionary = cl[i]
		linhas.append({"pos": i + 1, "nome": NOME_JOGADOR if e.get("jogador", false) else String(e.nome),
			"total": float(e.get("fim", -1.0)), "melhor": float(e.get("melhor", -1.0)),
			"score": int(e.get("score", 0)), "jogador": bool(e.get("jogador", false))})
	queue_redraw()


func esconder() -> void:
	visible = false


## "mm:ss.cc" (como a tela: 01:29.98); sem tempo (não chegou, ou sem volta
## fechada) em traços (NOSSO, pedido do Matheus; no jogo offline quem não
## chegou nem entra na tabela)
static func tempo(s: float) -> String:
	if s < 0.0:
		return "--:--.--"
	var c := mini(int(s * 100.0 + 0.5), 5999 * 100 + 99)
	return "%02d:%02d.%02d" % [c / 6000, (c / 100) % 60, c % 100]


func _process(dt: float) -> void:
	if visible:
		t += dt
		queue_redraw()


# ------------------------------------------------------------------ desenho
func _draw() -> void:
	if lay.is_empty() or size.y <= 0.0:
		return
	var w := size.y * 4.0 / 3.0
	_a = Rect2((size.x - w) * 0.5, 0.0, w, size.y)
	_cheia = Rect2(Vector2.ZERO, size)
	_desenha(lay.camadas.get(CAMADA.get(pagina, "LAYER_RESULTS"), {}), Rect2(-1, -1, 2, 2))


## os textos como ficariam numa tela 640 x 480 (testes, contra a RAM):
## [{txt, letras: [Rect2 sem giro], rot}]
func medir() -> Array:
	_medindo = []
	_a = Rect2(0, 0, 640, 480)
	_cheia = _a
	_desenha(lay.camadas.get(CAMADA.get(pagina, "LAYER_RESULTS"), {}), Rect2(-1, -1, 2, 2))
	var m: Array = _medindo
	_medindo = null
	return m


## NDC (y pra cima) -> pixel; larga = sprite que cobre a largura toda (NOSSO:
## estica na tela larga)
func _px(r: Rect2, larga := false) -> Rect2:
	var a := _cheia if larga and _cheia.size.x > _a.size.x else _a
	var x0 := a.position.x + (r.position.x + 1.0) * 0.5 * a.size.x
	var x1 := a.position.x + (r.end.x + 1.0) * 0.5 * a.size.x
	var y0 := a.position.y + (1.0 - r.end.y) * 0.5 * a.size.y
	var y1 := a.position.y + (1.0 - r.position.y) * 0.5 * a.size.y
	return Rect2(x0, y0, x1 - x0, y1 - y0)


static func filho(pai: Rect2, r: Array) -> Rect2:
	return Rect2(pai.position.x + (float(r[0]) + 1.0) * 0.5 * pai.size.x,
		pai.position.y + (float(r[1]) + 1.0) * 0.5 * pai.size.y,
		float(r[2]) * 0.5 * pai.size.x, float(r[3]) * 0.5 * pai.size.y)


func _desenha(no: Dictionary, pai: Rect2, alfa := 1.0) -> void:
	var nome := String(no.get("nome", ""))
	var vis := int(no.get("mVisible", 1)) == 1
	if nome.ends_with("_Highlight"):
		vis = _linha(nome) != null and _linha(nome).jogador      # a linha do jogador
	elif nome in ["ID_SCROLL_UP", "ID_SCROLL_DOWN"]:
		vis = linhas.size() > 8                                   # só com mais de 8
	elif nome == "ID_FAKE_HISTORY_FRAME":
		vis = true
	elif nome.begins_with("ID_PLAYER_"):
		vis = int(nome.trim_prefix("ID_PLAYER_")) <= linhas.size()
	elif nome in ESCONDIDOS:
		vis = false
	if not vis:
		return
	var r := filho(pai, no.get("rect", [-1, -1, 2, 2]))
	var a := alfa * float(no.get("mAlpha", 1.0))
	match String(no.get("tipo", "quadro")):
		"sprite", "sprite_movel":
			_sprite(no, r, a)
		"texto":
			_texto_no(no, r, a)
		"ref":
			var ref: Array = no.get("ref", [])
			if ref.size() == 2 and lay.camadas.has(ref[1]):
				_desenha(lay.camadas[ref[1]], r, a)
	for f in no.get("filhos", []):
		_desenha(f, r, a)
	if nome == "ID_FAKE_HISTORY_FRAME" and lay.camadas.has("LAYER_FAKE_HISTORY"):
		_desenha(lay.camadas.LAYER_FAKE_HISTORY, r, a)
	elif nome == "ID_SELECTOR_FRAME" and not opcoes.is_empty():
		_seletor(r, a)
	elif nome == "ID_BUTTON_BAR_FRAME":
		_barra(r, a)


static func _no(pai: Dictionary, nome: String) -> Dictionary:
	for f in pai.get("filhos", []):
		if String(f.get("nome", "")) == nome:
			return f
	return {}


## LAYER_SELECTOR: a faixa (ID_SELECTOR_SPRITE), a opção atual e as outras
func _seletor(r: Rect2, a: float) -> void:
	var lf := _no(lay.camadas.get("LAYER_SELECTOR", {}), "ID_LAYER_FRAME")
	var sel := _no(lf, "ID_SELECTOR")
	if sel.is_empty():
		return
	var rs := filho(filho(r, lf.get("rect", [-1, -1, 2, 2])), sel.get("rect", [-1, -1, 2, 2]))
	a *= float(lf.get("mAlpha", 1.0)) * float(sel.get("mAlpha", 1.0))
	var faixa := _no(sel, "ID_SELECTOR_SPRITE")
	if not faixa.is_empty():
		_sprite(faixa, filho(rs, faixa.rect), a * float(faixa.get("mAlpha", 1.0)))
	var cur := _no(sel, "ID_CURRENT_OPT_TEXT")
	var prox := _no(sel, "ID_NEXT_OPT_TEXT")
	if cur.is_empty():
		return
	var s := _opcao_txt(cur, escolhida())
	var fonte: String = FONTES[clampi(int(cur.get("mFont", 1)), 0, 2)]
	var esc := float(cur.get("mScale", 1.0))
	var c1: Array = cur.get("mColour1", [1, 1, 1, 1])
	var c2: Array = cur.get("mColour2", c1)
	var topo := texto(s, fonte, filho(rs, cur.rect), esc, int(cur.get("mJustify", 16)),
		Color(c1[0], c1[1], c1[2], c1[3] * a), Color(c2[0], c2[1], c2[2], c2[3] * a))
	if prox.is_empty() or opcoes.size() < 2:
		return
	# as outras na ordem, dando a volta (NOSSO: a RAM só mostra a 1ª atual)
	var resto := []
	for k in range(1, opcoes.size()):
		resto.append(_opcao_txt(prox, String(opcoes[(opcao + k) % opcoes.size()])))
	var adv: float = glifos(s, fonte, esc)[1].x
	var rp := filho(rs, prox.rect)
	rp.position.x = topo.x + (adv + GAP_OPCAO) / 320.0
	var d1: Array = prox.get("mColour1", [0, 0, 0, 1])
	var d2: Array = prox.get("mColour2", d1)
	texto(SEP_OPCOES.join(resto), FONTES[clampi(int(prox.get("mFont", 1)), 0, 2)], rp, float(prox.get("mScale", 1.0)),
		int(prox.get("mJustify", 16)), Color(d1[0], d1[1], d1[2], d1[3] * a), Color(d2[0], d2[1], d2[2], d2[3] * a))


func _opcao_txt(no: Dictionary, k: String) -> String:
	var s := _txt(k)
	return s.to_upper() if int(no.get("mFlags", 0)) & 16 else s


func _linha(nome: String):
	var p := nome.split("_")
	if p.size() < 2 or not p[1].is_valid_int():
		return null
	var k := int(p[1]) - 1
	return linhas[k] if k >= 0 and k < linhas.size() else null


func _sprite(no: Dictionary, r: Rect2, a: float) -> void:
	var tn := String(no.get("TexName", "")).replace("\\", "/").get_file()
	var tx: Texture2D = tex.get(tn)
	if tx == null and tn.to_lower() != "white":
		return                              # Init\White: só a cor
	if String(no.get("tipo")) == "sprite_movel":
		r = _movel(no, r)
	var uv: Array = no.get("uv", [0, 1, 1, 0])
	var larga := float(no.rect[2]) >= 1.99 if no.has("rect") else false
	var p := _px(r, larga)
	if _medindo != null:
		return
	var cs := []
	for k in ["mColourTL", "mColourTR", "mColourBR", "mColourBL"]:
		var c: Array = no.get(k, no.get("mColour", [1, 1, 1, 1]))
		cs.append(Color(c[0], c[1], c[2], c[3] * a))
	var pts := PackedVector2Array([p.position, Vector2(p.end.x, p.position.y), p.end, Vector2(p.position.x, p.end.y)])
	var rot := deg_to_rad(float(no.get("mRotation", 0.0)))
	if rot != 0.0:
		# em volta do hotspot (-1..1 no sprite, y pra cima); no NDC o ângulo
		# é anti-horário: na tela (y pra baixo) vira -rot
		var hx := float(no.get("mHotspotX", 0.0))
		var hy := float(no.get("mHotspotY", 0.0))
		var piv := Vector2(p.position.x + (hx + 1.0) * 0.5 * p.size.x, p.end.y - (hy + 1.0) * 0.5 * p.size.y)
		for i in 4:
			pts[i] = piv + (pts[i] - piv).rotated(-rot)
	var uvs: PackedVector2Array
	if tx:
		uvs = PackedVector2Array([Vector2(uv[0], uv[3]), Vector2(uv[2], uv[3]), Vector2(uv[2], uv[1]), Vector2(uv[0], uv[1])])
	draw_polygon(pts, PackedColorArray(cs), uvs, tx)


## cDOMovingSprite: anda mVelocityX (NDC por segundo) do X do layout até o
## mEndXPos e volta pro começo (mScrollStyle 2)
func _movel(no: Dictionary, r: Rect2) -> Rect2:
	var vx := float(no.get("mVelocityX", 0.0))
	if vx == 0.0 or int(no.get("mMoving", 0)) == 0:
		return r
	var x0 := float(no.rect[0])
	var fim := float(no.get("mEndXPos", x0))
	var dist := absf(fim - x0)
	if dist <= 0.0:
		return r
	var d := fposmod(absf(vx) * t, dist) * signf(vx)
	r.position.x += d * r.size.x / maxf(float(no.rect[2]), 1e-6)
	return r


# ------------------------------------------------------------------ textos
func _texto_no(no: Dictionary, r: Rect2, a: float) -> void:
	var nome := String(no.get("nome", ""))
	var s := String(no.get("mpStringName", ""))
	if int(no.get("mStringNameInTable", 0)) == 1:
		s = _txt(s)
	var ln = _linha(nome)
	if ln != null:
		if nome.ends_with("_Position"):
			s = str(ln.pos)
		elif nome.ends_with("_Name"):
			s = ln.nome
		elif nome.ends_with("_Total_Time"):
			s = tempo(ln.total)
		elif nome.ends_with("_Best_Lap"):
			s = tempo(ln.melhor)
		elif nome.ends_with("_Stunt_Score"):
			s = str(ln.score)
	elif nome.begins_with("ID_FAKEHIST_TITLE_STRING"):
		s = _txt(TITULO.get(pagina, "RACE_RESULTS"))
	if int(no.get("mFlags", 0)) & 16:
		s = s.to_upper()
	var fonte: String = FONTES[clampi(int(no.get("mFont", 1)), 0, 2)]
	var c1: Array = no.get("mColour1", [1, 1, 1, 1])
	var c2: Array = no.get("mColour2", c1)
	texto(s, fonte, r, float(no.get("mScale", 1.0)), int(no.get("mJustify", 17)),
		Color(c1[0], c1[1], c1[2], c1[3] * a), Color(c2[0], c2[1], c2[2], c2[3] * a),
		float(no.get("mRotation", 0.0)), float(no.get("mAspect", 1.0)))


## letras de um texto: [[retângulo na referência 640 x 480, caixa na textura], ...]
## e o tamanho (largura pelos avanços, altura da linha x escala)
## traco_digito: o "-" ocupa a célula de um dígito (centrado), como o "--:--:--"
## do HUD: o tempo em traços fica da largura de um tempo
func glifos(s: String, fonte: String, esc: float, aspecto := 1.0, traco_digito := false) -> Array:
	var g: Dictionary = _fonte.get(fonte, {})
	if g.is_empty():
		return [[], Vector2.ZERO]
	var kern: Dictionary = _kern.get(fonte, {})
	var cods := []
	for ch in s:
		var k := ch.unicode_at(0)
		cods.append(k if g.has(k) else 32)
	var x := 0.0
	var alt: float = LINHA[fonte] * esc
	var out := []
	for n in cods.size():
		var c: int = cods[n]
		var prox: int = cods[n + 1] if n + 1 < cods.size() else 0
		var wg: float = g[c][1] if g.has(c) else 0.0
		var cel := wg
		if traco_digito and c == 45 and g.has(48):
			cel = g[48][1]
			prox = 48 if prox == 45 else prox          # o kerning de dígito com dígito
		if c != 32 and g.has(c):
			out.append([Rect2(x + (cel - wg) * 0.5 * esc * aspecto, 0.0, wg * esc * aspecto, alt), g[c][0]])
		x += (cel - _kern_de(kern, 48 if traco_digito and c == 45 else c, prox)) * esc * aspecto
	return [out, Vector2(x, alt)]


static func _kern_de(kern: Dictionary, c: int, prox: int) -> float:
	if kern.is_empty():
		return 0.0
	var base: float = kern.base
	if c < 0x40 or prox < 0x40 or c - 0x40 >= 192 or prox - 0x40 >= 192:
		return base
	var linha: int = kern.mapa[c - 0x40]
	if linha == 0xff or linha >= kern.tabela.size():
		return base
	return base + float(kern.tabela[linha][prox - 0x40]) * float(kern.passo)


## texto no rect (NDC): justify 0x10 centra na altura, 0x01 na largura
## (17 = os dois); sem eles, no canto de cima à esquerda. Devolve o canto de
## cima à esquerda (NDC)
func texto(s: String, fonte: String, r: Rect2, esc: float, just: int, c1: Color, c2: Color,
		rot := 0.0, aspecto := 1.0) -> Vector2:
	var gl: Array = glifos(s, fonte, esc, aspecto, s == tempo(-1.0))
	var tam: Vector2 = gl[1]
	# tamanho na referência 640 x 480 -> NDC
	var w_ndc := tam.x / 320.0
	var h_ndc := tam.y / 240.0
	var topo := Vector2(r.position.x, r.end.y)
	if just & 16:
		topo.y = r.get_center().y + h_ndc * 0.5
	if just & 1:
		topo.x = r.get_center().x - w_ndc * 0.5
	_letras(gl[0], fonte, topo, c1, c2, rot, s)
	return topo


## desenha as letras a partir do canto de cima à esquerda (NDC), girando rot
## (rad, anti-horário no NDC) em volta dele
func _letras(ls: Array, fonte: String, topo: Vector2, c1: Color, c2: Color, rot := 0.0, s := "") -> void:
	var o := _px(Rect2(topo, Vector2.ZERO)).position
	var kx := _a.size.x / 640.0
	var ky := _a.size.y / 480.0
	if _medindo != null:
		var rs := []
		for l in ls:
			var q: Rect2 = l[0]
			rs.append(Rect2(o.x + q.position.x * kx, o.y, q.size.x * kx, q.size.y * ky))
		_medindo.append({"txt": s, "letras": rs, "rot": rot})
		return
	var tx: Texture2D = tex.get(fonte)
	if tx == null:
		return
	var ts := tx.get_size()
	for l in ls:
		var q: Rect2 = l[0]
		var src: Rect2 = l[1]
		var pts := PackedVector2Array([Vector2(q.position.x * kx, 0), Vector2(q.end.x * kx, 0),
			Vector2(q.end.x * kx, q.size.y * ky), Vector2(q.position.x * kx, q.size.y * ky)])
		for i in 4:
			pts[i] = o + pts[i].rotated(-rot)
		var uvs := PackedVector2Array([src.position / ts, Vector2(src.end.x, src.position.y) / ts, src.end / ts,
			Vector2(src.position.x, src.end.y) / ts])
		draw_polygon(pts, PackedColorArray([c1, c1, c2, c2]), uvs, tx)


# ------------------------------------------------------------------ barra
## barra de baixo (o código do jogo põe os botões no ID_BUTTON_BAR_FRAME):
## ícone + texto por página (RAM: START + Continue nos resultados, X Select +
## triângulo Back na pausa, X Continue na Race again)
func _barra(_r: Rect2, a: float) -> void:
	var tn := "new_buttons_4bit_en_GB"
	var tx: Texture2D = tex.get(tn)
	for item in BARRA.get(pagina, []):
		var x0: float = item[2]
		if tx and _medindo == null:
			var b: Array = info.texturas[tn].caixas.get(item[0], [0, 0, 1, 1])
			var p := _px(Rect2(x0 - BOTAO_W, BOTAO_Y, BOTAO_W, BOTAO_H))
			var ts := tx.get_size()
			draw_texture_rect_region(tx, p, Rect2(b[0] * ts.x, b[1] * ts.y, (b[2] - b[0]) * ts.x, (b[3] - b[1]) * ts.y),
				Color(1, 1, 1, a))
		var s := _txt(item[1])
		var gl: Array = glifos(s, "FONT_MEDIUM", CONTINUE_ESC)
		_letras(gl[0], "FONT_MEDIUM", Vector2(x0, CONTINUE_POS.y), Color(1, 1, 1, a), Color(1, 1, 1, a), 0.0, s)
