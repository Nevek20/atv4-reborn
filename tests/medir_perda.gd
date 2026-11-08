extends SceneTree
## Quanto o carro perde batendo nas cercas e nos fardos do RX01 (diagnóstico):
## Renegade solto (sem acelerar) a VEL km/h, de frente e em ângulo. Perda =
## queda de velocidade nos 0.4 s em volta da batida menos a queda que ele
## já tinha (arrasto) nos 0.4 s antes. Jogo (0x153390): cerca quebrada tira
## no máximo 0.25 t·m/s / 1.2 t = 0.75 km/h.
## Uso: godot --headless --path . -s res://tests/medir_perda.gd

const Car := preload("res://carro/car.gd")
const Main := preload("res://main.gd")
const Terrain := preload("res://pista/terrain.gd")
const Objetos := preload("res://pista/objetos_rx01.gd")

var terrain
var objetos
var car = null
var casos: Array = []          # [tipo, alvo, ângulo]
var caso := -1
var t := 0.0
var vs: Array = []
var t_bate := -1.0
var alvo
var vel := 60.0
var _layer := 0
var _v_ctrl := 0.0


func _initialize() -> void:
	terrain = Terrain.new()
	root.add_child(terrain)
	objetos = Objetos.new()
	root.add_child(objetos)
	vel = float(OS.get_environment("VEL")) if OS.get_environment("VEL") != "" else 60.0


## caminho de 14 m até o objeto (e 10 depois) plano e sem nada no meio
func _caminho(c, o: Vector3, n: Vector3, ang: float) -> bool:
	n.y = 0.0
	n = n.normalized().rotated(Vector3.UP, deg_to_rad(ang))
	var lado := n.cross(Vector3.UP)
	var esp: PhysicsDirectSpaceState3D = objetos.get_world_3d().direct_space_state
	var corpo: CollisionObject3D = c.corpo
	for k in [-1.0, 0.0, 1.0]:
		for d in range(-10, 15):
			var p: Vector3 = o + n * float(d) + lado * k
			if absf(terrain.height_at(p.x, p.z) - terrain.height_at(o.x, o.z)) > 0.6:
				return false
		var a: Vector3 = o + n * 14.0 + lado * k
		var b: Vector3 = o - n * 10.0 + lado * k
		a.y = terrain.height_at(a.x, a.z) + 0.6
		b.y = terrain.height_at(b.x, b.z) + 0.6
		var q := PhysicsRayQueryParameters3D.create(a, b)
		q.exclude = [corpo.get_rid()]
		var hit: Dictionary = esp.intersect_ray(q)
		if not hit.is_empty() and hit.collider.get_parent() != terrain:
			return false
	return true


func _proximo() -> bool:
	caso += 1
	if caso >= casos.size():
		return false
	var k: Array = casos[caso]
	alvo = k[1]
	# controle: o mesmo caminho sem o objeto (cerca fora / fardo sem colisão)
	var corpo: CollisionObject3D = alvo.corpo
	if k[3]:
		_layer = corpo.collision_layer
		corpo.collision_layer = 0
		corpo.collision_mask = 0 if k[0] == "fardo" else corpo.collision_mask
		if k[0] == "cerca":
			alvo.quebrada = true
		else:
			(corpo as RigidBody3D).freeze = true
	else:
		if caso > 0 and casos[caso - 1][1] == alvo:
			corpo.collision_layer = _layer
			if k[0] == "cerca":
				alvo.quebrada = false
			else:
				corpo.collision_mask = 1
				(corpo as RigidBody3D).freeze = false
	var o: Vector3
	var n: Vector3
	if k[0] == "cerca":
		o = (alvo.xf as Transform3D).origin
		n = alvo.normal
	else:
		o = (alvo.xf0 as Transform3D).origin
		n = (alvo.xf0 as Transform3D).basis.z
	n.y = 0.0
	n = n.normalized().rotated(Vector3.UP, deg_to_rad(k[2]))
	if car:
		car.queue_free()
	car = Car.new()
	Main.configurar(car, Main.frota()[0])
	car.terrain = terrain
	car.objetos = objetos
	root.add_child(car)
	car.contact_monitor = true
	car.max_contacts_reported = 16
	objetos.carro = car
	var p := o + n * 14.0
	p.y = terrain.height_at(p.x, p.z) + 0.8
	car.reset_to(p, atan2(-n.x, -n.z))
	car.linear_velocity = -n * vel / 3.6
	car.test_input = {"thr": 0.0, "brk": 0.0, "steer": 0.0}
	t = 0.0
	vs = []
	t_bate = -1.0
	return true


func _physics_process(dt: float) -> bool:
	if caso == -1:
		if not objetos.is_inside_tree():
			return false
		if not objetos.montar():
			print("medir_perda: sem assets/rx01")
			return true
		for ang in [0.0, 30.0, 60.0]:
			for c in objetos.cercas:
				if String(c.it.modelo).begins_with("GEN_Barrier_RallyFence") and not c.quebrada \
						and not casos.any(func(e): return e[1] == c) and _caminho(c, (c.xf as Transform3D).origin, c.normal, ang):
					casos.append(["cerca", c, ang])
					break
		for ang in [0.0, 30.0]:
			for b in objetos.blocos:
				if not casos.any(func(e): return e[1] == b) and _caminho(b, (b.xf0 as Transform3D).origin, (b.xf0 as Transform3D).basis.z, ang):
					casos.append(["fardo", b, ang])
					break
		var dup := []
		for e in casos:
			dup.append(e + [true])
			dup.append(e + [false])
		casos = dup
		_proximo()
		return false
	t += dt
	if t < 1.6:
		return false
	var k: Array = casos[caso]
	var vk: float = car.linear_velocity.length() * 3.6
	if k[3]:
		_v_ctrl = vk
	else:
		print("  %s %2.0f°: sem ele %.1f km/h, com ele %.1f, perdeu %.2f km/h%s" % [k[0], k[2], _v_ctrl, vk, _v_ctrl - vk,
			"" if k[0] == "fardo" else " (quebrou %s)" % alvo.quebrada])
	if not _proximo():
		return true
	return false
