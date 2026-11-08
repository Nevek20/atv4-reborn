extends SceneTree
## Lasquinhas da batida (lascas.gd) na câmera de corrida: o carro numa reta
## de terra perto da largada do RX01 bate numa parede nossa a VEL m/s (padrão
## 25 m/s = 56 mph) e tira prints QUANDO segundos depois da batida.
##   godot --path . --fixed-fps 60 -s res://tests/gravar_lascas.gd -- 0 /tmp/lascas
##   godot --path . --write-movie lascas.avi --fixed-fps 60 -s res://tests/gravar_lascas.gd -- 0
## QUANDO=0.1,0.3,1.0 (prints <prefixo>_<t>.png), LASCAS_COR=1 vermelhas

const TesteP := preload("res://tests/teste_pedras.gd")

var main
var veh := 0
var prefixo := ""
var vel := 25.0
var t := -1.0
var bateu := -1.0
var quando: Array = [0.1, 0.3, 1.0]
var pronto := false
var fwd := Vector3.FORWARD


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		veh = int(a[0])
	if a.size() > 1:
		prefixo = a[1]
	if OS.get_environment("VEL") != "":
		vel = float(OS.get_environment("VEL"))
	if OS.get_environment("QUANDO") != "":
		quando = Array(OS.get_environment("QUANDO").split(",")).map(func(s): return float(s))
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


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
	t += dt
	car.test_input = {"thr": 0.0, "brk": 0.0, "steer": 0.0}
	if t >= 0.0 and t - dt < 0.0:
		fwd = car.forward()
		fwd.y = 0.0
		fwd = fwd.normalized()
		var c: Vector3 = car.global_position + fwd * 14.5
		var sb := StaticBody3D.new()
		sb.name = "Parede"
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(20, 4, 1)
		cs.shape = b
		sb.add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = b.size
		mi.mesh = bm
		sb.add_child(mi)
		root.add_child(sb)
		sb.global_transform = Transform3D(Basis.looking_at(fwd), Vector3(c.x, main.terrain.height_at(c.x, c.z) + 1.5, c.z))
	if t >= 0.0 and bateu < 0.0:
		var vy: float = car.linear_velocity.y
		car.linear_velocity = fwd * vel + Vector3(0, vy, 0)
		if car.lascas and car.lascas.soltas > 0:
			bateu = t
			print("bateu: %d lascas" % car.lascas.soltas)
	if bateu >= 0.0 and prefixo != "":
		for q in quando:
			if t - bateu >= q and t - dt - bateu < q:
				var img := root.get_viewport().get_texture().get_image()
				img.save_png("%s_%.1f.png" % [prefixo, q])
				print("print %s_%.1f.png  lascas %d" % [prefixo, q, car.lascas.vivas()])
	return t > 4.0 or (bateu >= 0.0 and t - bateu > 2.0)
