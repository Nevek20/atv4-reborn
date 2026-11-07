extends SceneTree
## print da largada do RX01 na câmera de corrida, sem HUD (comparar a cor com
## os prints do jogo). QUADRO=n tira no quadro n (padrão 90).
## Uso: godot --path . -s res://tests/print_largada.gd -- saida.png
var main
var n := 0
func _initialize():
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func _process(_dt) -> bool:
	n += 1
	if n == 5:
		for c in main.find_children("*", "CanvasLayer", true, false):
			c.visible = false
	if n == int(OS.get_environment("QUADRO") if OS.get_environment("QUADRO") != "" else "90"):
		root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
		return true
	return false
