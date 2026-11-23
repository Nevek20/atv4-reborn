extends SceneTree
## Tela de resultados (menu/resultados.gd) contra a RAM do save state
## placar_final.p2s do Matheus (tests/ref_resultados.json, re/resultados_ram.py):
##  1. cada texto (cabeçalho, 8 linhas, Continue): canto esquerdo da 1ª letra,
##     direito da última, topo e base, na tela 640 x 480 (< 0.5 px);
##  2. título "Race Results" girado (0.05 rad em volta do canto de cima à
##     esquerda): os 4 cantos da 1ª letra (< 1 px), e a sombra 0.02 NDC à
##     esquerda;
##  3. tempo "mm:ss.cc";
##  4. quando aparece (pista/corrida.gd, estado 0x4c18e0): na sua chegada, com
##     todos (NOSSO: quem não chegou com o tempo em traços);
##  5. a pausa (pause.p2s, tests/ref_pausa.json) e a Race again (finish_2.p2s,
##     tests/ref_de_novo.json): título, opção atual, as outras, a barra; e o
##     seletor dando a volta.
## Uso: godot --headless --path . -s res://tests/teste_resultados.gd

const CL := [
	{"nome": "Você", "jogador": true, "fim": 89.98, "melhor": 42.63, "score": 11266},
	{"nome": "Manu", "fim": 94.21, "melhor": 51.29, "score": 11744},
	{"nome": "Eagle", "fim": 96.89, "melhor": 53.31, "score": 10953},
	{"nome": "Fordyce", "fim": 98.70, "melhor": 53.69, "score": 10361},
	{"nome": "Ritchie", "fim": 99.63, "melhor": 54.47, "score": 10535},
	{"nome": "Sheppard", "fim": 101.39, "melhor": 55.31, "score": 15525},
	{"nome": "Brown", "fim": 102.44, "melhor": 56.63, "score": 11711},
	{"nome": "Russell", "fim": 109.79, "melhor": 59.67, "score": 15190},
]
var falhas := 0


class IaFalsa:
	var rivais: Array = []
	var comp := 1810.4
	var lista: Array = []
	func classificacao() -> Array:
		return lista.duplicate(true)


func _falha(m: String) -> void:
	falhas += 1
	print("FALHA: ", m)


func _initialize() -> void:
	var r = load("res://menu/resultados.gd").new()
	if not r.montar():
		print("teste_resultados: ok (sem assets/ui: rode tools/fex_jogo.py; pulado)")
		quit()
		return
	r.mostrar(CL)
	print("  resultados (placar_final.p2s):")
	_layout(r, "res://tests/ref_resultados.json", "Race Results")
	# pausa (pause.p2s: a 106 km/h, sem o Respot) e Race again (finish_2.p2s)
	r.abrir_menu("pausa", ["Resume", "RESTART", "QUIT", "Game_options", "Photographer"])
	print("  pausa (pause.p2s):")
	_layout(r, "res://tests/ref_pausa.json", "PAUSE MENU")
	r.abrir_menu("de_novo", ["RESTART", "EXIT"])
	print("  race again (finish_2.p2s):")
	_layout(r, "res://tests/ref_de_novo.json", "Race again")
	_seletor(r)
	r.mostrar(CL)
	_tempo(r)
	r.free()
	_fluxo()
	print("teste_resultados: %s" % ("ok" if falhas == 0 else "%d falhas" % falhas))
	quit(1 if falhas else 0)


func _layout(r, arq: String, titulo: String) -> void:
	var nossos: Array = r.medir()
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(arq))
	var pior := 0.0
	var conferidos := 0
	var usados := {}
	for e in ref.textos:
		var s := String(e.txt)
		if s == titulo:
			continue
		var achado = null
		for k in nossos.size():
			var n: Dictionary = nossos[k]
			if usados.has(k) or String(n.txt).to_lower() != s.to_lower() or n.letras.is_empty():
				continue
			if absf((n.letras[0] as Rect2).position.y - float(e.y[0])) < 3.0:
				achado = n
				usados[k] = true
				break
		if achado == null:
			_falha("sem o texto '%s' (y %.1f)" % [s, e.y[0]])
			continue
		var ls: Array = achado.letras
		# o fim de texto longo escorrega 0.25% (a RAM anda 0.9975 do nosso em x:
		# 1.1 px em 435 px; a conta da escala do GS não foi achada)
		var larg: float = ls[-1].end.x - ls[0].position.x
		var erros := [absf(ls[0].position.x - float(e.x[0][0])),
			maxf(absf(ls[-1].end.x - float(e.x[-1][1])) - 0.0026 * larg, 0.0),
			absf(ls[0].position.y - float(e.y[0])), absf(ls[0].end.y - float(e.y[1]))]
		var m: float = erros.max()
		pior = maxf(pior, m)
		conferidos += 1
		if m > 0.5:
			print("  %-12s nosso x %.2f..%.2f y %.2f..%.2f  RAM x %.2f..%.2f y %.2f..%.2f" % [s, ls[0].position.x,
				ls[-1].end.x, ls[0].position.y, ls[0].end.y, e.x[0][0], e.x[-1][1], e.y[0], e.y[1]])
	print("  textos x RAM: %d conferidos (de %d), pior %.3f px" % [conferidos, ref.textos.size() - 2, pior])
	if pior > 0.5 or conferidos < ref.textos.size() - 2:
		_falha("posição dos textos")
	# título: 1ª letra girada (RAM: baixo esq, cima esq, baixo dir, cima dir)
	var tit: Array = nossos.filter(func(n): return String(n.txt) == titulo)
	var ram: Array = ref.textos.filter(func(e): return String(e.txt) == titulo)
	if tit.size() != 2 or ram.size() != 2:
		_falha("título: %d nossos, %d na RAM" % [tit.size(), ram.size()])
		return
	var pior_t := 0.0
	for k in 2:
		var l: Rect2 = tit[k].letras[0]
		var o := Vector2(l.position.x, l.position.y)
		var rot: float = tit[k].rot
		var cantos := [Vector2(l.position.x, l.end.y), l.position, l.end, Vector2(l.end.x, l.position.y)]
		var ram_k: Dictionary = ram[0] if (ram[0].pos[0] < ram[1].pos[0]) == (k == 0) else ram[1]
		for c in 4:
			var p: Vector2 = o + (cantos[c] - o).rotated(-rot)
			pior_t = maxf(pior_t, p.distance_to(Vector2(ram_k.letra0[c][0], ram_k.letra0[c][1])))
	print("  título girado: pior canto %.2f px" % pior_t)
	if pior_t > 1.0:
		_falha("título")


## seletor (0x2d1280): não passa das pontas, não anda no meio da troca; as
## outras opções são só as de depois da atual. Troca (0x2d23a8): pra esquerda
## a nova entra por fora da esquerda e chega no lugar da atual em T_ANIM
func _seletor(r) -> void:
	r.abrir_menu("pausa", ["Resume", "Respot", "RESTART", "QUIT"])
	var ponta: bool = r.mover(-1)
	var anda: bool = r.mover(1)
	var no_meio: bool = r.mover(1)
	r.anim = -1.0
	r.mover(1)
	r.anim = -1.0
	var txts: Array = r.medir().map(func(n): return String(n.txt))
	print("  seletor: esquerda no 1º %s, direita %s, no meio da troca %s; em %s as outras %s" % [ponta, anda,
		no_meio, r.escolhida(), txts.slice(2, 4)])
	if ponta or not anda or no_meio or r.escolhida() != "RESTART" or not txts.has("QUIT") or txts.has("RESUME"):
		_falha("seletor (pontas / troca / ordem das outras)")
	# troca pra esquerda: x da 1ª letra da nova no começo e no fim
	var x_resto: float = _x_de(r, "RESTART")
	r.mover(-1)
	r.anim = 0.0
	var x0: float = _x_de(r, "RESPOT")
	r.anim = r.T_ANIM * 0.999
	var x1: float = _x_de(r, "RESPOT")
	r.anim = -1.0
	var x2: float = _x_de(r, "RESPOT")
	print("  troca pra esquerda: a nova de x %.1f a %.1f px (no lugar: %.1f; a atual ficava em %.1f)" % [x0, x1, x2, x_resto])
	if x0 >= x_resto - 20.0 or absf(x1 - x2) > 1.0 or absf(x2 - x_resto) > 0.5:
		_falha("animação da troca")


## x da 1ª letra do texto s (o de escala maior, se tiver 2: a opção atual;
## os fantasmas em 1.5, 45 px de altura, ficam de fora)
func _x_de(r, s: String) -> float:
	var ns: Array = r.medir().filter(func(n): return String(n.txt) == s and not n.letras.is_empty() \
		and (n.letras[0] as Rect2).size.y < 44.0)
	if ns.is_empty():
		return INF
	ns.sort_custom(func(a, b): return (a.letras[0] as Rect2).size.y > (b.letras[0] as Rect2).size.y)
	return (ns[0].letras[0] as Rect2).position.x


func _tempo(r) -> void:
	var a: String = r.tempo(89.98)
	var b: String = r.tempo(-1.0)
	var c: String = r.tempo(59.996)
	print("  tempo: %s, %s, %s" % [a, b, c])
	if a != "01:29.98" or b != "--:--.--" or c != "01:00.00":
		_falha("formato do tempo")


func _fluxo() -> void:
	var c = load("res://pista/corrida.gd").new()
	var ia := IaFalsa.new()
	c.ia = ia
	c.dados = {"primeira_volta": 54.8}
	c.voltas = 2
	ia.rivais = [{"r": {"fim": 100.0, "prog": 3620.8}}, {"r": {"fim": -1.0, "prog": 1800.0}}]
	ia.lista = [{"nome": "Você", "jogador": true, "fim": 90.0, "prog": 3620.8, "score": 5, "melhor": 44.0},
		{"nome": "B", "fim": -1.0, "prog": 1800.0, "score": 2, "melhor": 60.0},
		{"nome": "A", "fim": 100.0, "prog": 3620.8, "score": 1, "melhor": 47.0}]
	c.estado = c.CORRENDO
	var p0: bool = c.resultados_prontos()
	c.estado = c.CHEGOU
	var p1: bool = c.resultados_prontos()
	var ch: Array = c.tabela()
	print("  aparece: correndo %s, na chegada %s; na tabela %s (relógio %.0f, a cada %.0f s)" % [p0, p1,
		ch.map(func(e): return e.nome), c.RESULTADO_INI, c.RESULTADO_PASSO])
	if p0 or not p1 or ch.size() != 3 or ch[0].nome != "Você":
		_falha("quando a tela aparece / quem entra na tabela")
	c.free()
