extends SceneTree
## Print da tela de resultados (menu/resultados.gd) com os números do save
## state placar_final.p2s do Matheus (nome do perfil trocado por PLAYER), por
## cima de um fundo cinza. Uso:
##   godot --path . --resolution 640x480 -s res://tests/print_resultados.gd -- saida.png [t]
## t = segundos de tela (os quadriculados andam)

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
var r
var q := 0


func _initialize() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.45, 0.42, 0.38)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	r = load("res://menu/resultados.gd").new()
	if not r.montar():
		print("print_resultados: sem assets/ui (rode tools/fex_jogo.py)")
		quit(1)
		return
	root.add_child(r)
	r.mostrar(CL)
	var a := OS.get_cmdline_user_args()
	if a.size() > 1:
		r.t = float(a[1])


func _process(_d: float) -> bool:
	q += 1
	if q == 5:
		var a := OS.get_cmdline_user_args()
		root.get_viewport().get_texture().get_image().save_png(a[0] if a.size() > 0 else "resultados.png")
		quit()
		return true
	return false
