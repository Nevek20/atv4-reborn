extends SceneTree
## Lasquinhas da batida (lascas.gd, porta do 0x3bbd60) no RX01: o Storm vai
## reto numa parede (caixa nossa na terra perto da largada) a VEL m/s.
## Confere: a 20 m/s (45 mph) de frente solta int((2 + 4 t) x 1) = 3 (t =
## 0.3); a 10 m/s (22 mph < 30) não solta; nunca mais de 8 vivas; somem em 4 s;
## saem da parede pra fora e pra cima (25..35 mph); quicam e param no chão.
## Uso: godot --headless --path . -s res://tests/teste_lascas.gd   (VEL=20)

const Car := preload("res://carro/car.gd")
const Main := preload("res://main.gd")
const Terrain := preload("res://pista/terrain.gd")
const TesteP := preload("res://tests/teste_pedras.gd")

var terrain
var car
var vel := 20.0
var t := 0.0
var p0: Vector2
var parede_d := 12.0
var fwd := Vector3.FORWARD
var max_vivas := 0
var bateu := -1.0
var falhas := 0
var saidas: Array = []
var abaixo := 0
var raspou := false
var encostou := false


func _initialize() -> void:
	vel = float(OS.get_environment("VEL")) if OS.has_environment("VEL") else vel
	terrain = Terrain.new()
	root.add_child(terrain)
	var v: Dictionary = {}
	for x in Main.VEHICLES:
		if x.name == "Storm":
			v = x
	car = Car.new()
	Main.configurar(car, v)
	car.terrain = terrain
	car.suspension = false
	root.add_child(car)
	car.test_input = {"thr": 0.0, "brk": 0.0, "steer": 0.0}


func _physics_process(dt: float) -> bool:
	if not car.is_inside_tree():
		return false
	if t == 0.0:
		p0 = TesteP.terra_perto(terrain, Main.SPAWN_XZ)
		car.reset_to(Vector3(p0.x, terrain.height_at(p0.x, p0.y) + 0.8, p0.y), deg_to_rad(Main.SPAWN_YAW))
		if car.lascas == null:
			print("teste_lascas: FALHA (sem lascas: falta assets/fx/lasca.json? rode tools/fx_jogo.py)")
			return true
		print("cor da lasca (base da pintura): ", car.lascas.cor)
	t += dt
	if t < 0.6:
		return false
	if t - dt < 0.6:
		fwd = car.forward()
		fwd.y = 0.0
		fwd = fwd.normalized()
		# parede de 20 x 4 x 1 m de frente pro carro, a parede_d metros
		var c: Vector3 = car.global_position + fwd * (parede_d + 0.5)
		var sb := StaticBody3D.new()
		sb.name = "Parede"
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(20, 4, 1)
		cs.shape = b
		sb.add_child(cs)
		root.add_child(sb)
		sb.global_transform = Transform3D(Basis.looking_at(fwd), Vector3(c.x, terrain.height_at(c.x, c.z) + 1.5, c.z))
		car.linear_velocity = fwd * vel
	var lq = car.lascas
	# segura a velocidade até encostar (na terra o carro solto perde ~14 m/s
	# nos 12 m até a parede)
	if car.batida > 0.0:
		encostou = true
	if not encostou and t < 3.0:
		var vy: float = car.linear_velocity.y
		car.linear_velocity = fwd * vel + Vector3(0, vy, 0)
	max_vivas = maxi(max_vivas, lq.vivas())
	car.batida_max = maxf(car.batida_max, car.batida)
	if car.sfx and car.sfx.raspa.tocando:
		raspou = true
	if bateu < 0.0 and lq.soltas > 0:
		bateu = t
		for u in lq.ultimas:
			var vp: Vector3 = u[0]
			saidas.append(vp)
		print("bateu aos %.2f s a %.1f m/s: %d lascas" % [t, vel, lq.ultimas.size()])
		for u in lq.ultimas:
			var vp: Vector3 = u[0]
			print("  vel %.1f m/s (%.0f mph), pra fora %.1f, pra cima %.1f, tamanho %s" % [
				vp.length(), vp.length() / 0.44694445, -vp.dot(fwd), vp.y, u[1]])
	for k in lq.vivas():
		var q: Vector3 = lq.l_pos[k]
		if lq.l_chao[k] > -1e30 and q.y < terrain.height_at(q.x, q.z) - 0.05:
			abaixo += 1
	if t < 6.0:
		return false
	var esperado := 0 if vel / 0.44694445 < 30.0 else 1
	if esperado == 0 and lq.soltas > 0:
		falhas += 1
		print("FALHA: a %.0f mph (< 30) soltou %d" % [vel / 0.44694445, lq.soltas])
	if esperado == 1 and lq.soltas == 0:
		falhas += 1
		print("FALHA: bateu a %.0f mph e não soltou" % (vel / 0.44694445))
	if max_vivas > lq.MAX:
		falhas += 1
		print("FALHA: %d vivas (máximo 8)" % max_vivas)
	if lq.vivas() > 0 and bateu > 0.0 and t - bateu > 4.1 and lq.soltas == saidas.size():
		falhas += 1
		print("FALHA: ainda vivas 4 s depois")
	for vp in saidas:
		# direção (±2, ±2 + 1.5, 1) na base da parede: y de -0.5 a 3.5, pode
		# sair um pouco pra baixo (o jogo)
		if -vp.dot(fwd) < -1.0 or vp.y < -0.5 * vp.length():
			falhas += 1
			print("FALHA: lasca não saiu pra fora/cima: ", vp)
	# som da batida (0x36e7a8): SmallImpact acima de 0.5 m/s na normal,
	# BigImpact acima de 20, um a cada 0.2 s no máximo
	if car.sfx:
		var tocadas: Array = car.sfx.batida_tocadas
		print("  som: ", tocadas, "  raspão tocou: ", raspou)
		if tocadas.is_empty():
			falhas += 1
			print("FALHA: bateu e não tocou som")
		else:
			var esperado_som := "BigImpact" if car.batida_max > 20.0 else "SmallImpact"
			if String(tocadas[0][1]) != esperado_som:
				falhas += 1
				print("FALHA: batida a %.1f m/s na normal tocou %s (esperado %s)" % [car.batida_max, tocadas[0][1], esperado_som])
	else:
		print("  (sem sfx: rode tools/sfx_jogo.py)")
	print("  lasca mais de 5 cm abaixo do relevo (chão guardado velho): %d amostras" % abaixo)
	print("teste_lascas: %s (soltas %d, máximo vivas %d, agora %d)" % ["ok" if falhas == 0 else "FALHA", lq.soltas, max_vivas, lq.vivas()])
	return true
