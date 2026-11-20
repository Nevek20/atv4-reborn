extends SceneTree
## HUD do jogo (menu/hud_jogo.gd) contra a RAM dos save states do Matheus:
## 1) layout: a 640x480 (o PAL 4:3 dos save states) cada quadro tem que cair
##    na matriz da RAM (tests/ref_hud_4x3.json, re/hud_ref.py, 52 quadros),
##    tolerância 0.5 px
## 2) tela larga (1916x741, a do Matheus): sprite em pixel continua quadrado
##    e do tamanho px x altura / 480 (antes escalava pela largura e o
##    conta-giros estourava pra fora da tela)
## 3) ponteiro e barras com os números dos save states: rpm 6171 -> 1.6607
##    rad, 5841 -> 1.4941 (0.006: o ponteiro ainda andando), 1000 -> -1.0465 (parado); freio
##    suavizado 0.20 acende 3 blocos de 16; velocidade 35.655 m/s -> 128
## 4) kerning (0x2689c0) encurtando "POSITION"
## 5) lista de pilotos (caixas e textos de 8 linhas) e ponto do minimapa nas
##    posições da RAM (save states andando_em_linha_reta e idle_antes_do_Go)
## 6) fonte carregada e cada letra dos textos (rótulos, números, tempos,
##    nomes) nos vértices da RAM (tests/ref_hud_textos.json, re/hud_textos.py),
##    0.75 px; células do tempo ("--:--:--", sinal só negativo) e a troca da
##    lista (0x48af80: 1 s freando, quem desce some no meio)
## Uso: godot --headless --path . -s res://tests/teste_hud.gd

var falhas := 0
# bandeiras (OBJECT_SPRITE_ANIM) ainda não portadas: o 1º quadro dá 1 px a mais
const AINDA_NAO := ["START_FLAG", "WHITE_FLAG", "CHECK_FLAG"]


func _falha(t: String) -> void:
	print("  FALHA: " + t)
	falhas += 1


func _initialize() -> void:
	var h = load("res://menu/hud_jogo.gd").new()
	if not h.montar():
		print("teste_hud: FALHA (sem assets/hud: rode o tools/hud_jogo.py)")
		quit()
		return
	h.set_anchors_preset(Control.PRESET_TOP_LEFT)
	h.em_corrida = true
	# 1) layout x RAM
	var ref = JSON.parse_string(FileAccess.get_file_as_string("res://tests/ref_hud_4x3.json"))
	h.size = Vector2(640, 480)
	var r: Dictionary = h.retangulos()
	var pior := 0.0
	var pior_nome := ""
	var n := 0
	for nome in ref:
		if not r.has(nome) or String(nome).begins_with("m"):
			continue
		var m: Array = ref[nome]          # sx, sy, tx, ty em NDC (y pra cima)
		var esp := Rect2((m[2] + 1.0) * 0.5 * 640.0, (1.0 - (m[3] + m[1]) * 0.5 - 0.5) * 480.0,
			m[0] * 0.5 * 640.0, m[1] * 0.5 * 480.0)
		var q: Rect2 = r[nome]
		var d := maxf(maxf(absf(q.position.x - esp.position.x), absf(q.position.y - esp.position.y)),
			maxf(absf(q.size.x - esp.size.x), absf(q.size.y - esp.size.y)))
		n += 1
		if d > pior:
			pior = d
			pior_nome = nome
		if d > 0.5 and not (nome in AINDA_NAO):
			_falha("%s: %s x RAM %s" % [nome, q, esp])
	print("  layout x RAM (640x480): %d quadros, pior diferença %.3f px (%s)" % [n, pior, pior_nome])
	if n < 40:
		_falha("poucos quadros comparados (%d)" % n)
	# 1b) lista de pilotos e minimapa x RAM (save state andando_em_linha_reta,
	# NDC 4:3): caixa da posição da 1ª e 8ª linha (centro), nome (esquerda),
	# textos (canto de cima); ponto do jogador parado no grid (idle_antes_do_Go)
	var rf: Dictionary = h.retangulos_frac()
	var ndc := func(x: float, y: float) -> Vector2:
		return Vector2((x + 1.0) * 0.5 * 640.0, (1.0 - (y + 1.0) * 0.5) * 480.0)
	var lc: Array = h.linhas_caixas(h._no("PLAYERLIST_SPRITE"), rf.PLAYERLIST_SPRITE, 8)
	var lt: Array = h.linhas_textos(h._no("PLAYERLIST_TEXT"), rf.PLAYERLIST_TEXT, 8)
	var checa := [
		["caixa 1", lc[0][0].get_center(), ndc.call(-0.8656, 0.4562)],
		["caixa 8", lc[7][0].get_center(), ndc.call(-0.8656, -0.1869)],
		["nome 1 (esq.)", Vector2(lc[0][1].position.x, lc[0][1].get_center().y), ndc.call(-0.8278, 0.4562)],
		["número 1 (topo)", h._tela(lt[0][0]).position, ndc.call(-0.8805, 0.5)],
		["número 8 (topo)", h._tela(lt[7][0]).position, ndc.call(-0.8805, -0.15625)],
		["nome 8 (topo)", h._tela(lt[7][1]).position, ndc.call(-0.8102, -0.15625)],
		["ponto do jogador", h._tela(h.ponto_mapa(rf.MINIMAP_CIRCUIT, 580.8, 1564.3)).get_center(), ndc.call(-0.7188, -0.7559)],
	]
	var pior_l := 0.0
	for c in checa:
		var dd: float = (c[1] as Vector2).distance_to(c[2])
		pior_l = maxf(pior_l, dd)
		if dd > 0.6:
			_falha("%s: %s x RAM %s" % [c[0], c[1], c[2]])
	print("  lista de pilotos e minimapa x RAM: %d pontos, pior %.2f px" % [checa.size(), pior_l])
	# 1c) fonte carregada e cada letra x RAM (tests/ref_hud_textos.json,
	# re/hud_textos.py): largura e caixa de cada caractere; os quadradinhos
	# das letras de cada texto (rótulos, números, tempos, nomes da lista)
	var rt = JSON.parse_string(FileAccess.get_file_as_string("res://tests/ref_hud_textos.json"))
	var pior_f := 0.0
	var nf := 0
	for fonte in rt.fontes:
		var t: Dictionary = h.info.texturas[fonte]
		for k in rt.fontes[fonte].glifos:
			var c := int(k)
			if c == 32 or not h._fonte[fonte].has(c):
				continue
			var gr: Array = rt.fontes[fonte].glifos[k]
			var cx: Rect2 = h._fonte[fonte][c][0]
			var d := maxf(absf(h.largura_glifo(fonte, c) - gr[0]), maxf(absf(cx.position.x - gr[1] * t.w),
				absf(cx.end.x - gr[3] * t.w)))
			nf += 1
			pior_f = maxf(pior_f, d)
			if d > 0.1:
				_falha("%s '%c': largura %.2f caixa %s x RAM %s" % [fonte, c, h.largura_glifo(fonte, c), cx, gr])
	print("  fonte x RAM: %d caracteres, pior %.3f px" % [nf, pior_f])
	h.valores = {}
	var pior_t := 0.0
	var pior_tn := ""
	var nt := 0
	for e in rt.textos:
		var nome: String = e.nome
		var no = h._no(nome)
		var fonte: String = e.fonte
		var rr: Rect2 = rf[nome]
		if nome == "PLAYERLIST_TEXT":
			rr = h.linha_textos(no, rf[nome], float(e.linha))[e.coluna]
		var cel: Rect2 = h._tela(rr)
		var gl: Array
		if e.get("classe", "") == "tempo":
			gl = h.glifos(h.celulas_tempo(no, e.valor)[0], fonte, cel, no.at)   # todas as células
		elif e.get("classe", "") == "numero":
			var txt := str(int(e.valor))
			if nome != "PLAYERLIST_TEXT":
				h.valores[nome] = int(e.valor)
				txt = h._valor(no)
			gl = h.glifos(txt, fonte, cel, no.at if nome != "PLAYERLIST_TEXT" else {}, str(int(e.valor)).length())
		elif nome == "PLAYERLIST_TEXT":
			gl = h.glifos(e.txt, fonte, cel, {})
		else:
			var k := String(no.at.get("mText", ""))
			gl = h.glifos(h.info.textos.en.get(k, k), fonte, cel, no.at)
		if gl.size() > e.x.size() or gl.is_empty():
			_falha("%s: %d letras x %d na RAM" % [nome, gl.size(), e.x.size()])
			continue
		for i in gl.size():
			var q: Rect2 = gl[i][0]
			var d := maxf(maxf(absf(q.position.x - e.x[i][0]), absf(q.end.x - e.x[i][1])),
				maxf(absf(q.position.y - e.y[0]), absf(q.end.y - e.y[1])))
			nt += 1
			if d > pior_t:
				pior_t = d
				pior_tn = "%s[%d]" % [nome, i]
			if d > 0.75:
				_falha("%s letra %d: %s x RAM x %s y %s" % [nome, i, q, e.x[i], e.y])
	print("  letras x RAM (640x480): %d letras em %d textos, pior %.3f px (%s)" % [nt, rt.textos.size(), pior_t, pior_tn])
	# o tempo: células do modelo, dígito na célula, sinal só negativo
	var tl: Array = h.celulas_tempo(h._no("LEAD_TIMER"), -1.2848)
	var tp: Array = h.celulas_tempo(h._no("LAP_TIMER"), 7.0188)
	var tn: Array = h.celulas_tempo(h._no("LAP_TIMER"), null)
	var str_de := func(m: Array) -> String:
		return "".join(m.map(func(c): return " " if c < 0 else char(c)))
	print("  tempo: LEAD %s / %s, LAP %s, sem tempo %s" % [tl[0], str_de.call(tl[1]), str_de.call(tp[1]), str_de.call(tn[1])])
	if str_de.call(tl[1]) != "-00:01:28" or str_de.call(tp[1]) != "00:07:02" or str_de.call(tn[1]) != "--:--:--" \
			or tl[0] != "---:--:--":
		_falha("células do tempo")
	# 1d) troca na lista (0x48af80): o 2º passa o 1º; em 0.5 s (e = 0.75) quem
	# sobe está em 0.25 inteiro, quem desce em 0.75 com alfa 0.5; depois de
	# mShuffleSpeed (1 s) acaba
	h.lista = [{"nome": "A", "jogador": false}, {"nome": "B", "jogador": true}, {"nome": "C", "jogador": false}]
	h.animar_lista(0.02)
	h.lista = [h.lista[1], h.lista[0], h.lista[2]]
	h.animar_lista(0.02)
	h.animar_lista(0.5)
	var ll: Array = h.lista_linhas()
	var em := {}
	for l in ll:
		em[l[2].nome] = l
	print("  lista trocando (0.5 s): B linha %.2f alfa %.2f, A linha %.2f alfa %.2f, C %.2f" % [
		em.B[0], em.B[1], em.A[0], em.A[1], em.C[0]])
	if absf(em.B[0] - 0.25) > 1e-4 or em.B[1] != 1.0 or absf(em.A[0] - 0.75) > 1e-4 or absf(em.A[1] - 0.5) > 1e-4 or em.C[0] != 2.0:
		_falha("animação da lista")
	h.animar_lista(0.6)
	ll = h.lista_linhas()
	if ll[0][2].nome != "B" or ll[0][0] != 0.0 or ll[1][0] != 1.0 or ll[1][1] != 1.0:
		_falha("a lista não terminou a troca")
	h.lista = []
	h._lista_mostrada = []
	# 2) tela larga
	h.size = Vector2(1916, 741)
	r = h.retangulos()
	var cx: Rect2 = h._caixa("hud_tpage_rev9000", "main_speedo")
	var sp: Rect2 = r.SPEEDO
	var esp_sp: Vector2 = cx.size * 741.0 / 480.0
	print("  1916x741: conta-giros %s (esperado %.1f x %.1f), dentro da tela: %s" % [sp, esp_sp.x, esp_sp.y,
		Rect2(0, 0, 1916, 741).encloses(sp)])
	if sp.size.distance_to(esp_sp) > 0.5 or not Rect2(0, 0, 1916, 741).encloses(sp):
		_falha("conta-giros na tela larga")
	# 3) ponteiro, barras, velocidade (dados dos save states)
	var sv := {"rpm": 0.0, "P": {"max_rpm": 9000.0}, "throttle": 0.0, "brake_in": 0.20, "gear": 3,
		"linear_velocity": Vector3(0, 0, 35.655), "global_transform": Transform3D()}
	var carro := Carro.new()
	for k in sv:
		carro.set(k, sv[k])
	for caso in [[6171.0, 1.6607], [5841.0, 1.4941], [1000.0, -1.0465]]:
		carro.rpm = caso[0]
		for i in 200:
			h._dt = 1.0
			h.atualizar(0.02, carro, null)
		print("  %d rpm: ponteiro %.4f rad (RAM %.4f)" % [caso[0], -h.agulha, caso[1]])
		if absf(-h.agulha - caso[1]) > 0.01:     # o save state pega o ponteiro andando (10 rad/s)
			_falha("ponteiro em %d rpm" % caso[0])
	print("  freio 0.20: %d blocos (RAM 3); velocidade %s (RAM 128)" % [h._barra_estado.y, h.valores.SPEED])
	if h._barra_estado.y != 3 or h.valores.SPEED != 128:
		_falha("barra do freio ou velocidade")
	# 4) kerning
	var k: Dictionary = h.info.texturas.FONT_SMALL.kern
	var bruto := 0.0
	var junto := 0.0
	var s := "POSITION"
	for i in s.length():
		var c := s.unicode_at(i)
		var w: float = h._caixa("FONT_SMALL", str(c)).size.x
		bruto += w
		junto += w - h._kern(k, c, s.unicode_at(i + 1) if i + 1 < s.length() else 0)
	print("  POSITION: %.0f px sem kerning, %.0f com (fonte de 22 px)" % [bruto, junto])
	if not (junto < bruto - 8.0):
		_falha("kerning não encurtou o texto")
	print("teste_hud: %s" % ("ok" if falhas == 0 else "FALHA (%d)" % falhas))
	h.free()
	quit()


## carro de mentira com o que o HUD lê
class Carro:
	extends RefCounted
	var rpm := 0.0
	var P := {}
	var throttle := 0.0
	var brake_in := 0.0
	var gear := 1
	var linear_velocity := Vector3.ZERO
	var global_transform := Transform3D()
