extends SceneTree
## Pedrinhas do pneu (pedras.gd) na câmera de corrida: o carro larga num
## ponto de terra comum perto da largada do RX01 (o mesmo do teste_pedras),
## acelerador no fundo e volante reto, como no vídeo do Matheus (nov/2026).
## Tira prints nos tempos de QUANDO (s depois de acelerar) ou grava:
##   godot --path . --fixed-fps 60 -s res://tests/gravar_pedras.gd -- 0 /tmp/pedras
##   godot --path . --write-movie pedras.avi --fixed-fps 60 -s res://tests/gravar_pedras.gd -- 0
## QUANDO=0.6,1.0,1.4 (prints <prefixo>_<t>.png), DUR=4 segundos,
## SEM_PEDRAS=1 esconde as pedras, PEDRAS_COR=1 pedras vermelhas, VIRA=1 vira
## tudo depois de 2 s (derrapa)

const TesteP := preload("res://tests/teste_pedras.gd")

var main
var veh := 0
var prefixo := ""
var t := -1.0
var dur := 4.0
var quando: Array = [0.6, 1.0, 1.4]
var pronto := false


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		veh = int(a[0])
	if a.size() > 1:
		prefixo = a[1]
	if _env("DUR") != "":
		dur = float(_env("DUR"))
	if _env("QUANDO") != "":
		quando = Array(_env("QUANDO").split(",")).map(func(s): return float(s))
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


static func _env(nome: String) -> String:
	return OS.get_environment(nome).strip_edges()


func _process(dt: float) -> bool:
	if main == null:
		return true
	if not pronto:
		if main.car == null:
			return false
		var p: Vector2 = TesteP.terra_perto(main.terrain, main.SPAWN_XZ)
		main.car.queue_free()
		main.spawn_vehicle(veh, Vector3(p.x, main.terrain.height_at(p.x, p.y) + 0.8, p.y), deg_to_rad(main.SPAWN_YAW))
		pronto = true
		return false
	var car = main.car
	main.hud.visible = false
	for n in main.get_children():
		if n is CanvasLayer:
			n.visible = false
	if car.pedras and _env("SEM_PEDRAS") == "1":
		car.pedras.visible = false
	t += dt
	var acel := t > 0.0
	car.test_input = {"thr": 1.0 if acel else 0.0, "brk": 0.0,
		"steer": 1.0 if _env("VIRA") == "1" and t > 2.0 else 0.0}
	if int(t * 4.0) != int((t - dt) * 4.0):
		print("%.2f s  %.0f km/h  pedras %d" % [t, car.linear_velocity.length() * 3.6, car.pedras.vivas() if car.pedras else -1])
	if prefixo != "":
		for q in quando:
			if t >= q and t - dt < q:
				var img := root.get_viewport().get_texture().get_image()
				img.save_png("%s_%.1f.png" % [prefixo, q])
				print("print ", "%s_%.1f.png" % [prefixo, q])
	return t > dur
