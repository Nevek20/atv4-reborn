extends SceneTree
## Batidas nas cercas laranjas (diagnóstico, nov/2026: "às vezes fica
## indestrutível, bati de frente um pouco de lado com o Renegade e fui jogado
## longe"). Renegade solto (sem acelerar) contra cercas de verdade do RX01, em
## vários ângulos, velocidades e pontos ao longo da cerca (ponta, meio).
## Para cada batida: quebrou? quanto perdeu de velocidade, o maior pulo pra
## cima e o maior giro. Marca "PAREDE" quando não quebrou com impulso que
## devia quebrar e "JOGOU" quando o carro foi arremessado.
## Uso: godot --headless --path . -s res://tests/medir_cerca_batida.gd
## (VELS=40,70 ANGS=0,15,30,45,60 DESL=-1.2,-0.6,0,0.6,1.2 N_CERCAS=2)

const Car := preload("res://carro/car.gd")
const Main := preload("res://main.gd")
const Terrain := preload("res://pista/terrain.gd")
const Objetos := preload("res://pista/objetos_rx01.gd")

var terrain
var objetos
var car = null
var casos: Array = []          # [cerca, ângulo, deslocamento, vel]
var caso := -1
var t := 0.0
var alvo
var v0 := 0.0
var vy_max := 0.0
var w_max := 0.0
var y0 := 0.0
var y_max := 0.0
var quebrou_t := -1.0
var ruins := 0
var total := 0
var t_med := 0.0                 # hora de medir: 4 m depois da cerca
var ctrl := {}                   # índice do caso -> [v, vy, giro] sem a cerca


func _lista(nome: String, padrao: String) -> Array:
	var s := OS.get_environment(nome)
	return Array((s if s != "" else padrao).split(",")).map(func(x): return float(x))


func _initialize() -> void:
	terrain = Terrain.new()
	root.add_child(terrain)
	objetos = Objetos.new()
	root.add_child(objetos)


func _ao_longo(c) -> Vector3:
	var n: Vector3 = c.normal
	n.y = 0.0
	return n.normalized().cross(Vector3.UP).normalized()


## pontas da cerca (mundo, no chão da cerca): pelas esferas do casco
func _pontas(c) -> Array:
	var eixo := _ao_longo(c)
	var o: Vector3 = (c.xf as Transform3D).origin
	var lo := INF
	var hi := -INF
	for cs in c.forma:
		var pw: Vector3 = (c.corpo as Node3D).global_transform * (cs as Node3D).position
		var t := (pw - o).dot(eixo)
		lo = minf(lo, t)
		hi = maxf(hi, t)
	return [o + eixo * lo, o + eixo * hi]


## 14 m até o ponto e 10 depois plano e sem nada no meio (as cercas não contam)
func _caminho(o: Vector3, d: Vector3) -> bool:
	var lado := d.cross(Vector3.UP)
	var esp: PhysicsDirectSpaceState3D = objetos.get_world_3d().direct_space_state
	var fora: Array[RID] = []
	for c in objetos.cercas:
		fora.append((c.corpo as CollisionObject3D).get_rid())
	for k in [-1.0, 0.0, 1.0]:
		for s2 in range(-10, 15):
			var p: Vector3 = o + d * float(s2) + lado * k
			if absf(terrain.height_at(p.x, p.z) - terrain.height_at(o.x, o.z)) > 0.6:
				return false
		var a: Vector3 = o + d * 14.0 + lado * k
		var b: Vector3 = o - d * 10.0 + lado * k
		a.y = terrain.height_at(a.x, a.z) + 0.6
		b.y = terrain.height_at(b.x, b.z) + 0.6
		var q := PhysicsRayQueryParameters3D.create(a, b)
		q.exclude = fora
		var hit: Dictionary = esp.intersect_ray(q)
		if not hit.is_empty() and hit.collider.get_parent() != terrain:
			return false
	return true


func _proximo() -> bool:
	caso += 1
	if caso >= casos.size():
		return false
	var k: Dictionary = casos[caso]
	alvo = k.cercas[0]
	# cercas inteiras de novo (no controle, as do caso ficam fora)
	for c in objetos.cercas:
		var fora: bool = k.controle and c in k.cercas
		c.quebrada = fora
		for cs in c.forma:
			(cs as CollisionShape3D).disabled = fora
		(c.corpo as StaticBody3D).collision_layer = 0 if fora else 1 | objetos.CAMADA
		(c.malha as Node3D).visible = not fora
	# peças das batidas anteriores fora do caminho
	for lista in objetos.pecas.values():
		for rb in lista:
			if is_instance_valid(rb):
				(rb as RigidBody3D).global_position += Vector3(0, -50, 0)
				(rb as RigidBody3D).freeze = true
	var d: Vector3 = k.d
	var o: Vector3 = k.o
	if car:
		car.queue_free()
	car = Car.new()
	Main.configurar(car, Main.frota()[0])
	car.terrain = terrain
	car.objetos = objetos
	root.add_child(car)
	objetos.carro = car
	var p := o + d * 14.0
	p.y = terrain.height_at(p.x, p.z) + 0.8
	car.reset_to(p, atan2(-d.x, -d.z) + deg_to_rad(k.guinada))
	car.linear_velocity = -d * k.vel / 3.6
	car.test_input = {"thr": float(OS.get_environment("THR")) if OS.get_environment("THR") != "" else 0.0, "brk": 0.0, "steer": 0.0}
	t = 0.0
	v0 = k.vel
	vy_max = 0.0
	w_max = 0.0
	y0 = p.y
	y_max = -INF
	quebrou_t = -1.0
	t_med = 18.0 / (k.vel / 3.6)
	return true


func _physics_process(dt: float) -> bool:
	if caso == -1:
		if not objetos.is_inside_tree():
			return false
		if not objetos.montar():
			print("medir_cerca_batida: sem assets/pista/rx01")
			return true
		var n_cercas := int(OS.get_environment("N_CERCAS")) if OS.get_environment("N_CERCAS") != "" else 2
		var usadas := 0
		var alvos: Array = []          # [cercas, ponto, normal pro lado livre, nome]
		for pref in ["GEN_Barrier_RallyFence", "SAM_Barrier_RallyFence"]:
			var achou := 0
			for c in objetos.cercas:
				if achou >= n_cercas or not String(c.it.modelo).begins_with(pref):
					continue
				var o: Vector3 = (c.xf as Transform3D).origin
				var n: Vector3 = c.normal
				n.y = 0.0
				n = n.normalized()
				for lado in [1.0, -1.0]:
					if _caminho(o, n * lado) and _caminho(o, (n * lado).rotated(Vector3.UP, deg_to_rad(45.0))):
						for desl in _lista("DESL", "-1.2,-0.6,0,0.6,1.2"):
							alvos.append([[c], o + _ao_longo(c) * desl, n * lado, "desl %+.1f" % desl])
						# emenda com a vizinha (as pontas a menos de 0.5 m)
						for pa in _pontas(c):
							for c2 in objetos.cercas:
								if c2 == c:
									continue
								for pb in _pontas(c2):
									if (pa as Vector3).distance_to(pb) < 0.5:
										alvos.append([[c, c2], ((pa as Vector3) + (pb as Vector3)) * 0.5, n * lado, "emenda"])
						usadas += 1
						achou += 1
						break
		for a in alvos:
			for vel in _lista("VELS", "40,70"):
				for ang in _lista("ANGS", "0,15,30,45"):
					for guinada in _lista("GUINADA", "0,20"):
						var d: Vector3 = (a[2] as Vector3).rotated(Vector3.UP, deg_to_rad(ang))
						if not _caminho(a[1], d):
							continue
						for controle in [true, false]:
							casos.append({"cercas": a[0], "o": a[1], "d": d, "vel": vel, "ang": ang,
								"onde": a[3], "guinada": guinada, "controle": controle})
		print("medir_cerca_batida: %d cercas, %d batidas (metade é controle)" % [usadas, casos.size()])
		_proximo()
		return false
	t += dt
	vy_max = maxf(vy_max, car.linear_velocity.y)
	w_max = maxf(w_max, car.angular_velocity.length())
	y_max = maxf(y_max, car.global_position.y)
	var k: Dictionary = casos[caso]
	if not k.controle and alvo.quebrada and quebrou_t < 0.0:
		quebrou_t = t
	if t < t_med:
		return false
	var vk: float = car.linear_velocity.length() * 3.6
	if k.controle:
		ctrl[caso + 1] = [vk, vy_max, w_max]
	else:
		var c0: Array = ctrl.get(caso, [vk, vy_max, w_max])
		total += 1
		var marca := ""
		var inteiras := (k.cercas as Array).filter(func(c): return not c.quebrada)
		if not inteiras.is_empty():
			marca = "PAREDE"
		if vy_max - c0[1] > 2.0 or w_max - c0[2] > 1.5 or c0[0] - vk > 5.0:
			marca += (" " if marca != "" else "") + "JOGOU"
		if marca != "" or OS.get_environment("TUDO") == "1":
			if marca != "":
				ruins += 1
			print("  %-24s %-9s %2.0f° guinada %2.0f° %3.0f km/h: %s, perdeu %5.1f km/h (sem a cerca %5.1f), vy %.1f (sem %.1f), giro %.1f (sem %.1f) %s" % [
				String(alvo.it.modelo).get_file().get_basename(), k.onde, k.ang, k.guinada, k.vel,
				"quebrou %d/%d" % [(k.cercas as Array).size() - inteiras.size(), (k.cercas as Array).size()],
				c0[0] - vk, c0[0], vy_max, c0[1], w_max, c0[2], marca])
	if not _proximo():
		print("medir_cerca_batida: %d de %d batidas ruins" % [ruins, total])
		return true
	return false
