extends SceneTree
## Confere o giro das rodas por torque (car.gd, 0x2113e0 / 0x2484c8 / 0x20df58):
##  1. inércia (W+0x3c) e raio (W+0x30) do Renegade e do Sphinx = RAM
##     (a.p2s / b.p2s: 0.00625 e 0.0060025 t·m², Mass x raio² / 2);
##  2. no chão, acelerando reto: a patinada medida (0x600) de cada roda é a
##     patinada 0x610 do passo anterior; o giro do motor com a embreagem
##     travada é o giro da roda de tração x relação (0x20c558); o visual gira
##     pelo ângulo da roda (W+0x4c);
##  3. no ar acelerando: roda de tração gira com o motor (giro / relação) e a
##     da frente perde 180°/s²; freando, a da frente perde freio / inércia;
##  4. acelerando contra um muro: depois de 0,33 s parado o carro fica preso
##     (0x890) e a roda de tração gira com o motor x embreagem / relação.
## Uso: godot --headless --path . -s res://tests/teste_roda.gd

const Car := preload("res://carro/car.gd")
const Main := preload("res://main.gd")
const VehicleData := preload("res://carro/vehicle_data.gd")
const RAM := [[0, 0.5, 0.00625], [1, 0.49, 0.0060025]]   # carro, raio, inércia (t·m²)

var car
var muro: StaticBody3D
var etapa := "ram"
var t := 0.0
var falhas := 0
# estado do passo anterior (o teste roda antes do carro em cada passo)
var slip_ant := []
var omega_ant := []
var tr_ant := 0.0
var cst_ant := -1
var gear_ant := 0
var preso_ant := false
var no_ar_ant := false
var pior_sr := 0.0
var pior_rpm := 0.0
var pior_vis := 0.0
var n_chao := 0
var pior_ar_tr := 0.0
var pior_ar_fr := 0.0
var pior_ar_frei := 0.0
var n_ar := 0
var n_frei := 0
var viu_preso := false
var pior_preso := 0.0


func _initialize() -> void:
	var chao := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000, 2, 4000)
	cs.shape = box
	cs.position = Vector3(0, -1, 0)
	chao.add_child(cs)
	root.add_child(chao)
	for r in RAM:
		var c = _novo(r[0])
		for w in c.wheels:
			var ok: bool = absf(w.r - r[1]) < 1e-6 and absf(w.inercia / 1000.0 - r[2]) < 1e-7
			if not ok:
				falhas += 1
				print("%s: raio %.4f inércia %.7f t·m² (RAM %.4f %.7f)  FALHOU" % [
					Main.VEHICLES[r[0]].name, w.r, w.inercia / 1000.0, r[1], r[2]])
		print("%s: raio e inércia das 4 rodas = RAM" % Main.VEHICLES[r[0]].name)
		c.free()
	car = _novo(0)
	etapa = "chao"


func _novo(i: int):
	var v: Dictionary = Main.VEHICLES[i]
	var c = Car.new()
	c.asset_dir = v.dir
	c.data_files = ["res://data/vehicles/buggy_base.xml", v.data]
	c.points_file = v.points
	c.vehicle_id = v.id
	c.suspension = false
	root.add_child(c)
	c.test_input = {"thr": 0.0, "brk": 0.0, "steer": 0.0}
	return c


func _tr(c) -> float:
	var m := 0.0
	for w in c.wheels:
		if c._motriz(w) and absf(m) < absf(w.omega):
			m = w.omega
	return m


func _physics_process(dt: float) -> bool:
	if car == null or not car.is_inside_tree():
		return false
	if t == 0.0 and etapa != "ar":
		car.reset_to(Vector3(0, 0.8, -1500.0 if etapa == "chao" else 0.0), 0.0)
	match etapa:
		"chao":
			_chao(dt)
		"ar":
			_ar(dt)
		"preso":
			_preso(dt)
	if car == null:
		return false
	_guardar()
	t += dt
	return false


func _guardar() -> void:
	slip_ant = []
	omega_ant = []
	for w in car.wheels:
		slip_ant.append(w.slip)
		omega_ant.append(w.omega)
	tr_ant = _tr(car)
	cst_ant = car.cstate
	gear_ant = car.gear
	preso_ant = car.preso
	no_ar_ant = car.grounded == 0


func _chao(dt: float) -> void:
	car.test_input.thr = 1.0 if t > 0.5 else 0.0
	var v_f: float = car.linear_velocity.dot(car.global_transform.basis.z)
	if t > 0.6 and car.grounded == 4 and v_f > 5.0 and slip_ant.size() == 4:
		n_chao += 1
		for i in 4:
			var w: Dictionary = car.wheels[i]
			pior_sr = maxf(pior_sr, absf(w.sr - slip_ant[i]))
			pior_vis = maxf(pior_vis, absf(w.spin_node.rotation.x - w.spin))
		if cst_ant == 3 and car.cstate == 3 and gear_ant == car.gear and not preso_ant:
			var esp: float = maxf(tr_ant / car.RPM2RAD * car._ratio(car.gear), car.P.idle)
			pior_rpm = maxf(pior_rpm, absf(car.rpm - esp))
	if t > 4.0:
		var ok := n_chao > 100 and pior_sr < 0.01 and pior_rpm < 0.5 and pior_vis < 1e-6
		if not ok:
			falhas += 1
		print("chão (%d passos): 0x600 x 0x610 do passo anterior %.4f, rpm x roda %.2f, visual %.6f  %s" % [
			n_chao, pior_sr, pior_rpm, pior_vis, "ok" if ok else "FALHOU"])
		# sobe 40 m mantendo a velocidade
		car.global_position += Vector3.UP * 40.0
		car.reset_physics_interpolation()
		car.pos_ant = car.global_position
		etapa = "ar"
		t = 0.0


func _ar(dt: float) -> void:
	var ti = car.test_input
	ti.thr = 1.0 if t < 1.0 else 0.0
	ti.brk = 0.0 if t < 1.0 else 1.0
	if car.grounded == 0 and no_ar_ant and omega_ant.size() == 4:
		var ratio: float = car._ratio(car.gear)
		for i in 4:
			var w: Dictionary = car.wheels[i]
			if car._motriz(w):
				if car.cstate == 3 and ratio != 0.0:
					pior_ar_tr = maxf(pior_ar_tr, absf(w.omega - car.rpm * car.RPM2RAD / ratio))
			elif omega_ant[i] > PI * dt * 20.0:
				var dw: float = (w.omega - omega_ant[i]) / dt
				if car.brake_in == 0.0:
					pior_ar_fr = maxf(pior_ar_fr, absf(dw + PI))
					n_ar += 1
				else:
					# freio no ar: média do atrito 0 (0x780), eixo da frente, sem a massa
					var dmax: float = car.brake_in * car.MPH_G * car.P.brake_decel \
						* VehicleData.triple(car.P.brake_fscale, 0.0)
					var t_frei: float = car.P.front_bias * dmax / 2.0 * w.r * 1000.0
					pior_ar_frei = maxf(pior_ar_frei, absf(dw + maxf(PI, t_frei / w.inercia)))
					n_frei += 1
	if t > 1.5:
		var ok := n_ar > 50 and n_frei > 10 and pior_ar_tr < 1e-3 and pior_ar_fr < 1e-3 and pior_ar_frei < 1e-2
		if not ok:
			falhas += 1
		print("ar: tração x motor %.6f rad/s, frente solta %.6f rad/s² (%d), freando %.6f (%d)  %s" % [
			pior_ar_tr, pior_ar_fr, n_ar, pior_ar_frei, n_frei, "ok" if ok else "FALHOU"])
		car.queue_free()
		car = _novo(0)
		# muro 10 cm na frente da caixa do carro (frente em z = 2.4)
		muro = StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(10, 3, 1)
		cs.shape = box
		muro.add_child(cs)
		muro.position = Vector3(0, 1.5, 3.0)
		root.add_child(muro)
		etapa = "preso"
		t = 0.0


func _preso(dt: float) -> void:
	car.test_input.thr = 1.0 if t > 0.3 else 0.0
	if car.preso:
		viu_preso = true
		var ratio: float = car._ratio(car.gear)
		for w in car.wheels:
			if car._motriz(w) and ratio != 0.0:
				pior_preso = maxf(pior_preso, absf(w.omega - car.rpm * car.RPM2RAD / ratio * car.clutch))
	if t > 3.0:
		var ok := viu_preso and pior_preso < 1e-3
		if not ok:
			falhas += 1
		print("muro: preso %s, tração x motor x embreagem %.6f rad/s  %s" % [viu_preso, pior_preso,
			"ok" if ok else "FALHOU"])
		print("teste_roda: %s" % ("ok" if falhas == 0 else "%d falhas" % falhas))
		quit(1 if falhas else 0)
		car = null
