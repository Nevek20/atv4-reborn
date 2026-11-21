extends SceneTree
## Tela de resultados (menu/resultados.gd) contra a RAM do save state
## placar_final.p2s do Matheus (tests/ref_resultados.json, re/resultados_ram.py):
##  1. cada texto (cabeçalho, 8 linhas, Continue): canto esquerdo da 1ª letra,
##     direito da última, topo e base, na tela 640 x 480 (< 0.5 px);
##  2. título "Race Results" girado (0.05 rad em volta do canto de cima à
##     esquerda): os 4 cantos da 1ª letra (< 1 px), e a sombra 0.02 NDC à
##     esquerda;
##  3. tempo "mm:ss.cc";
##  4. quando aparece (pista/corrida.gd resultados_prontos): só com todos
##     chegados ou passados RESULTADO_MAX s (NOSSO), e quem não chegou ganha
##     o tempo projetado pelo ritmo.
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
	_layout(r)
	_tempo(r)
	r.free()
	_fluxo()
	print("teste_resultados: %s" % ("ok" if falhas == 0 else "%d falhas" % falhas))
	quit(1 if falhas else 0)


func _layout(r) -> void:
	r.mostrar(CL)
	var nossos: Array = r.medir()
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/ref_resultados.json"))
	var pior := 0.0
	var conferidos := 0
	var usados := {}
	for e in ref.textos:
		var s := String(e.txt)
		if s == "Race Results":
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
		var erros := [absf(ls[0].position.x - float(e.x[0][0])), absf(ls[-1].end.x - float(e.x[-1][1])),
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
	var tit: Array = nossos.filter(func(n): return String(n.txt) == "Race Results")
	var ram: Array = ref.textos.filter(func(e): return String(e.txt) == "Race Results")
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


func _tempo(r) -> void:
	var a: String = r.tempo(89.98)
	var b: String = r.tempo(-1.0)
	var c: String = r.tempo(59.996)
	print("  tempo: %s, %s, %s" % [a, b, c])
	if a != "01:29.98" or b != "00:00.00" or c != "01:00.00":
		_falha("formato do tempo")


func _fluxo() -> void:
	var c = load("res://pista/corrida.gd").new()
	var ia := IaFalsa.new()
	c.ia = ia
	c.dados = {"primeira_volta": 54.8}
	c.voltas = 2
	ia.rivais = [{"r": {"fim": 100.0, "prog": 3620.8}}, {"r": {"fim": -1.0, "prog": 1800.0}}]
	ia.lista = [{"nome": "Você", "jogador": true, "fim": 90.0, "prog": 3620.8, "score": 5, "melhor": 44.0},
		{"nome": "A", "fim": 100.0, "prog": 3620.8, "score": 1, "melhor": 47.0},
		{"nome": "B", "fim": -1.0, "prog": 1800.0, "score": 2, "melhor": 60.0}]
	c.estado = c.CORRENDO
	var p0: bool = c.resultados_prontos()
	c.estado = c.CHEGOU
	c.t = 110.0
	c.t_conta = 5.0
	var p1: bool = c.resultados_prontos()
	c.t_conta = c.RESULTADO_MAX
	var p2: bool = c.resultados_prontos()
	var cl: Array = c.classificacao_final()
	var proj: float = cl[2].fim
	var esp := 110.0 * (2 * 1810.4 + 54.8) / (1800.0 + 54.8)
	print("  aparece: correndo %s, falta um %s, depois de %.0f s %s; projetado %.2f s (ritmo %.2f)" % [p0, p1,
		c.RESULTADO_MAX, p2, proj, esp])
	if p0 or p1 or not p2 or absf(proj - esp) > 0.01 or cl[0].nome != "Você":
		_falha("quando a tela aparece")
	ia.rivais[1].r.fim = 120.0
	c.t_conta = 1.0
	if not c.resultados_prontos():
		_falha("todos chegaram e não apareceu")
	c.free()
