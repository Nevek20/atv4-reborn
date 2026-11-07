extends SceneTree
## Cercas e fardos do RX01 (porta: InstanceDatabase.xml + 0x141640/0x141908):
##  1. o Renegade a 60 km/h de frente numa cerca de plástico: ela quebra
##     (impulso 1.2 t x 16.7 m/s = 20 > ShatterImpulse 2), as 2 peças nascem
##     e o carro passa sem parar;
##  2. a 4 km/h (1.2 x 1.1 = 1.3 < 2) a cerca segura;
##  3. o fardo (0.1 t, solto) sai empurrado a 30 km/h e volta pro lugar
##     depois do ActiveResetTimeout (10 s) com o carro longe.
## Uso: godot --headless --path . -s res://tests/teste_quebra.gd

const Car := preload("res://car.gd")
const Main := preload("res://main.gd")
const Terrain := preload("res://terrain.gd")
const Objetos := preload("res://objetos_rx01.gd")

var terrain
var objetos
var car = null
var falhas := 0
var fase := 0
var t := 0.0
var alvo: Dictionary
var bloco: Dictionary
var v0 := 0.0


func _initialize() -> void:
	terrain = Terrain.new()
	root.add_child(terrain)
	objetos = Objetos.new()
	root.add_child(objetos)


func _checa(ok: bool, txt: String) -> void:
	print(("ok      " if ok else "FALHOU  ") + txt)
	if not ok:
		falhas += 1


## cerca com chão plano e sem nada (guard-rail, outra cerca) 15 m atrás e
## 12 m na frente, numa faixa de 3 m
func _livre(c: Dictionary) -> bool:
	var o: Vector3 = (c.xf as Transform3D).origin
	var n: Vector3 = c.normal
	n.y = 0.0
	n = n.normalized()
	var lado := n.cross(Vector3.UP)
	var esp: PhysicsDirectSpaceState3D = objetos.get_world_3d().direct_space_state
	for k in [-1.2, 0.0, 1.2]:
		for d in range(-15, 13):
			if absf(d) < 1:
				continue
			var p: Vector3 = o + n * float(d) + lado * k
			if absf(terrain.height_at(p.x, p.z) - terrain.height_at(o.x, o.z)) > 0.8:
				return false
		var a: Vector3 = o + n * 12.0 + lado * k + Vector3(0, 0.6, 0)
		var b: Vector3 = o - n * 15.0 + lado * k + Vector3(0, 0.6, 0)
		a.y = terrain.height_at(a.x, a.z) + 0.6
		b.y = terrain.height_at(b.x, b.z) + 0.6
		var q := PhysicsRayQueryParameters3D.create(a, b)
		q.exclude = [c.corpo.get_rid()]
		var hit: Dictionary = esp.intersect_ray(q)
		if not hit.is_empty() and hit.collider != terrain.get_child(0) and not (hit.collider is StaticBody3D and hit.collider.get_parent() == terrain):
			return false
	return true


## carro a 12 m do objeto, de frente pra ele, com velocidade vel
func _carro_em(p_obj: Vector3, normal: Vector3, vel: float) -> void:
	if car:
		car.queue_free()
	car = Car.new()
	Main.configurar(car, Main.frota()[0])
	car.terrain = terrain
	car.objetos = objetos
	car.suspension = false
	root.add_child(car)
	objetos.carro = car
	var n := normal
	n.y = 0.0
	n = n.normalized()
	var p := p_obj + n * 12.0
	p.y = terrain.height_at(p.x, p.z) + 0.8
	car.reset_to(p, atan2(-n.x, -n.z))
	car.linear_velocity = -n * vel
	car.test_input = {"thr": 0.3 if vel > 5 else 0.05, "brk": 0.0, "steer": 0.0}
	t = 0.0
	v0 = vel


func _physics_process(dt: float) -> bool:
	if fase == 0:
		if not objetos.is_inside_tree():
			return false
		if not objetos.montar() or objetos.cercas.is_empty():
			print("teste_quebra: FALHA (sem assets/rx01 ou sem interativos: rode tools/rx01_objetos.py)")
			return true
		print("  %d cercas e %d fardos interativos" % [objetos.cercas.size(), objetos.blocos.size()])
		_checa(objetos.cercas.size() == 128 and objetos.blocos.size() == 51, "103 + 25 cercas e 51 fardos")
		for c in objetos.cercas:
			if String(c.it.modelo).begins_with("GEN_Barrier_RallyFence") and _livre(c):
				alvo = c
				break
		_carro_em((alvo.xf as Transform3D).origin, alvo.normal, 60.0 / 3.6)
		fase = 1
		return false
	if fase == 1:
		t += dt
		if OS.get_environment("DEBUG") == "1" and t > 0.5 and t < 0.75:
			var st := PhysicsServer3D.body_get_direct_state(car.get_rid())
			var nomes := []
			for i in st.get_contact_count():
				var o = st.get_contact_collider_object(i)
				var info := ""
				for c in objetos.cercas:
					if c.corpo == o:
						info = "cerca %s quebrada=%s dist=%.1f normal.v=%.1f layer=%d" % [c.it.modelo, c.quebrada, (c.xf as Transform3D).origin.distance_to(car.global_position), car.linear_velocity.dot(c.normal), o.collision_layer]
				if o == objetos.corpo:
					info = "KDt estatico"
				nomes.append("%s[%s]" % [o.name if o else "?", info])
			print("    passo t %.2f v %.1f contatos %s quebradas %d" % [t, car.linear_velocity.length() * 3.6, nomes, objetos.quebradas])
		if OS.get_environment("DEBUG") == "1" and int(t * 50) % 5 == 0:
			print("    t %.2f v %.1f km/h dist %.2f quebrada %s contatos %s" % [t, car.linear_velocity.length() * 3.6,
				(car.global_position - (alvo.xf as Transform3D).origin).dot(alvo.normal), alvo.quebrada,
				car.get_colliding_bodies().map(func(b): return b.name) if car.contact_monitor else "-"])
		if t < 2.0:
			return false
		var vk: float = car.linear_velocity.length() * 3.6
		var n_pecas := 0
		for k in objetos.pecas:
			n_pecas += objetos.pecas[k].size()
		print("  60 km/h na cerca: quebrou %s, %d peças, carro a %.0f km/h depois de 2 s" % [alvo.quebrada, n_pecas, vk])
		_checa(alvo.quebrada and n_pecas == 2, "cerca quebra e solta as 2 peças")
		_checa(vk > 35.0, "carro passa (não para na cerca)")
		# outra cerca devagar
		for c in objetos.cercas:
			if c != alvo and not c.quebrada and String(c.it.modelo).begins_with("GEN_Barrier_RallyFence") and _livre(c):
				alvo = c
				break
		_carro_em((alvo.xf as Transform3D).origin + alvo.normal * -8.5, alvo.normal, 4.0 / 3.6)
		fase = 2
		return false
	if fase == 2:
		t += dt
		if t < 3.0:
			return false
		var d: float = (car.global_position - (alvo.xf as Transform3D).origin).dot(alvo.normal)
		print("  4 km/h: quebrou %s, centro do carro a %.2f m do plano da cerca" % [alvo.quebrada, d])
		_checa(not alvo.quebrada, "devagar a cerca segura")
		bloco = objetos.blocos[0]
		var x0: Transform3D = bloco.xf0
		_carro_em(x0.origin, x0.basis.z, 30.0 / 3.6)
		fase = 3
		return false
	if fase == 3:
		t += dt
		if t < 2.0:
			return false
		var andou: float = (bloco.corpo as Node3D).global_position.distance_to((bloco.xf0 as Transform3D).origin)
		print("  fardo a 30 km/h: andou %.2f m" % andou)
		_checa(andou > 0.5, "fardo sai empurrado")
		car.queue_free()
		car = null
		objetos.carro = null
		fase = 4
		t = 0.0
		return false
	if fase == 4:
		t += dt
		if OS.get_environment("DEBUG") == "1" and int(t * 50) % 50 == 0:
			print("    fardo t %.1f mexido %s timer %.2f dist %.2f" % [t, bloco.mexido, bloco.t,
				(bloco.corpo as Node3D).global_position.distance_to((bloco.xf0 as Transform3D).origin)])
		if t < 11.0:
			return false
		var d: float = (bloco.corpo as Node3D).global_position.distance_to((bloco.xf0 as Transform3D).origin)
		print("  fardo depois de 11 s: a %.2f m do lugar" % d)
		_checa(d < 0.5, "fardo volta pro lugar (ActiveResetTimeout 10 s)")
		print("teste_quebra: %s" % ("ok" if falhas == 0 else "%d falhas" % falhas))
		return true
	return false
