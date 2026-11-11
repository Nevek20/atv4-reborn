extends SceneTree
## Prints da corrida com os rivais (pista/ia.gd): começa, pula a introdução e
## deixa o jogador pilotado pela IA; tira um print na câmera de corrida em cada
## tempo de QUANDO (s depois do VAI; padrão "1,30"): <saida>_<t>.png
## Uso: godot --path . --fixed-fps 50 -s res://tests/print_ia.gd -- ia

var main
var c
var ia
var eu := {}
var fase := 0
var q := 0
var tempos: Array = []
var saida := "ia"


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		saida = a[0]
	for x in (OS.get_environment("QUANDO") if OS.has_environment("QUANDO") else "1,30").split(","):
		tempos.append(float(x))
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _physics_process(dt: float) -> bool:
	q += 1
	if main.car == null or main.corrida == null:
		return false
	c = main.corrida
	if fase == 0:
		if q < 20:
			return false
		main.hud.visible = false
		c.comecar()
		c.comecar()
		ia = c.ia
		eu = {"nome": "Você", "car": main.car, "r": ia.jogador, "desvio": 0.0, "skill": 1.0, "preso": 0.0, "re": 0.0,
			"longe": 0.0, "capotado": 0.0, "repostos": 0, "res": 0,
			"desvio0": ia._lateral(main.car.global_position, ia.jogador.prog + ia.s_linha), "prog0": ia.jogador.prog}
		fase = 1
		return false
	if c.estado == c.CONTANDO:
		if not tempos.is_empty() and tempos[0] < 0.0:
			_print("grid")
			tempos.pop_front()
		return false
	eu.r = ia.jogador
	ia._dirigir(eu, main.car, dt)
	if tempos.is_empty():
		return true
	if c.t >= tempos[0]:
		_print("%.0f" % tempos[0])
		tempos.pop_front()
	return false


func _print(nome: String) -> void:
	await process_frame
	var arq := "%s_%s.png" % [saida, nome]
	root.get_texture().get_image().save_png(arq)
	print("print: ", arq, "  pos ", ia.posicao_jogador())
