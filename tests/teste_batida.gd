extends SceneTree
## Tremida da câmera na batida (camera_jitter.gd, 0x380418/0x380170) com a
## velocidade de contato do casco (car.gd batida, 0x215140). O Storm vai reto
## numa parede a VEL m/s (como no save state crash_Storm: parede de pedra, sem
## outro corpo) e duas câmeras recebem o car.batida a cada passo de 1/60:
##  1. a maior batida medida tem que dar a velocidade de chegada (±15%);
##  2. amp = rampa(batida) x MagMax x Decay no passo da batida e cai Decay por
##     passo depois (FollowOrbitNear 0.05 / 0.93, MountOnHood 0.1 / 0.95);
##  3. o sorteio fica dentro de [-amp, amp) (tremida - Perlin);
##  4. encostado na parede depois não é batida (< CollisionSpeedForStartJitter).
## Uso: godot --headless --path . -s res://tests/teste_batida.gd   (VEL=20)
const Car := preload("res://carro/car.gd")
const Main := preload("res://main.gd")
const GameCamera := preload("res://camera/game_camera.gd")
const CameraJitter := preload("res://camera/camera_jitter.gd")

const PAREDE_Z := 20.0
var vel := 20.0
var car
var t := 0.0
var cam_acc := 0.0
var cams := {}                 # nome -> jitter
var pico := 0.0                # maior car.batida
var vel_chegada := 0.0
var hist := []                 # velocidade pra frente dos últimos passos
var depois_max := 0.0          # maior batida encostado (t > batida + 1 s)
var t_batida := -1.0
var amp_pico := {}
var amp_fim := {}
var fora_faixa := 0
var falhas := 0


func _initialize() -> void:
	vel = float(OS.get_environment("VEL")) if OS.has_environment("VEL") else vel
	var chao := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 2, 400)
	cs.shape = box
	cs.position = Vector3(0, -1, 0)
	chao.add_child(cs)
	var parede := CollisionShape3D.new()
	var pb := BoxShape3D.new()
	pb.size = Vector3(40, 4, 1)
	parede.shape = pb
	parede.position = Vector3(0, 2, PAREDE_Z + 0.5)
	chao.add_child(parede)
	root.add_child(chao)
	var v: Dictionary = {}
	for x in Main.VEHICLES:
		if x.name == "Storm":
			v = x
	car = Car.new()
	car.asset_dir = v.dir
	car.data_files = ["res://data/vehicles/buggy_base.xml", v.data]
	car.points_file = v.points
	car.vehicle_id = v.id
	car.suspension = false
	root.add_child(car)
	car.test_input = {"thr": 0.0, "brk": 0.0, "steer": 0.0}
	for nome in ["FollowOrbitNear", "MountOnHood"]:
		cams[nome] = CameraJitter.carregar(Main.CAM_XML, nome)
		amp_pico[nome] = 0.0
		amp_fim[nome] = 0.0


func _physics_process(dt: float) -> bool:
	if car == null or not car.is_inside_tree():
		return false
	if t == 0.0:
		car.reset_to(Vector3(0, 1.0, 0), 0.0)
	t += dt
	if t < 0.6:
		return false
	if t - dt < 0.6:
		car.linear_velocity = car.forward() * vel
	# o batida que chega aqui é do passo de 2 passos atrás (teste -> car -> física)
	hist.push_back(car.linear_velocity.dot(car.forward()))
	if hist.size() > 3:
		hist.pop_front()
	if car.batida > pico:
		pico = car.batida
		if t_batida < 0.0 and car.batida > 1.0:
			t_batida = t
			vel_chegada = hist.max()
	if t_batida >= 0.0 and t > t_batida + 1.0:
		depois_max = maxf(depois_max, car.batida)
	# câmeras no passo de 1/60 do jogo, lendo o batida do último passo de física
	cam_acc += dt
	while cam_acc >= GameCamera.STEP:
		cam_acc -= GameCamera.STEP
		for nome in cams:
			var j = cams[nome]
			# chao 0 (sem terra): o Perlin some e sobra só o sorteio da batida
			var n: Vector2 = j.passo(GameCamera.STEP, car.linear_velocity.length(), 0.0, car.batida)
			amp_pico[nome] = maxf(amp_pico[nome], j.amp_batida)
			if absf(n.x) > j.amp_batida + 1e-7 or absf(n.y) > j.amp_batida + 1e-7:
				fora_faixa += 1
			amp_fim[nome] = j.amp_batida
	if (t_batida >= 0.0 and t > t_batida + 2.0) or t > 12.0:
		_fim()
		return true
	return false


func _fim() -> void:
	var ok_vel := t_batida > 0.0 and absf(pico - vel_chegada) <= 0.15 * vel_chegada
	print("teste_batida: Storm a %.1f m/s na parede: batida máx %.2f m/s (chegou a %.2f)  %s" % [
		vel, pico, vel_chegada, "ok" if ok_vel else "FALHA"])
	falhas += 0 if ok_vel else 1
	for nome in cams:
		var p: Dictionary = cams[nome].p
		# pico = rampa da maior batida x MagMax x Decay (a rampa só sobe com a velocidade)
		var c := clampf((pico - p.CollisionSpeedForStartJitter)
			/ (p.CollisionSpeedForMaxJitter - p.CollisionSpeedForStartJitter), 0.0, 1.0)
		var esp: float = c * p.CollisionJitterMagMax * p.CollisionJitterDecayFraction
		# e 2 s depois (120 passos) sobrou no máximo 1% (0.93^120 e 0.95^120 dão menos)
		var ok: bool = absf(amp_pico[nome] - esp) < 1e-6 and amp_fim[nome] <= amp_pico[nome] * 0.01
		# quanto tempo até cair pra 0.0124 (amp lida na RAM do crash_Storm)
		var passos: int = ceili(log(0.0124 / amp_pico[nome]) / log(p.CollisionJitterDecayFraction)) \
			if amp_pico[nome] > 0.0124 else 0
		print("  %-15s MagMax %.3f Decay %.2f  amp no pico %.4f (esperado %.4f, %.1f°)  até 0.0124: %.2f s  fim %.6f  %s" % [
			nome, p.CollisionJitterMagMax, p.CollisionJitterDecayFraction, amp_pico[nome], esp,
			rad_to_deg(atan(amp_pico[nome])), passos * GameCamera.STEP, amp_fim[nome], "ok" if ok else "FALHA"])
		falhas += 0 if ok else 1
	var ok_enc := depois_max < 4.0
	print("  encostado na parede: batida máx %.2f m/s (início da rampa 4)  %s" % [depois_max, "ok" if ok_enc else "FALHA"])
	print("  sorteio fora de [-amp, amp): %d  %s" % [fora_faixa, "ok" if fora_faixa == 0 else "FALHA"])
	falhas += (0 if ok_enc else 1) + (0 if fora_faixa == 0 else 1)
	print("teste_batida: %s" % ("ok" if falhas == 0 else "FALHA"))
