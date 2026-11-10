extends Node3D
## Teste de física sem tela: chão plano infinito, um carro e um roteiro de
## entradas escolhido por variável de ambiente. Imprime uma linha por
## intervalo (t, velocidade, marcha, rpm, embreagem, curso das rodas...).
## Quem lê a saída é o tests/rodar_testes.py.
##
## Variáveis:
##   SC    roteiro: accel (padrão), coast, man, s50, half, hs, turn, turnslow, freio, freiocurva,
##         mid, hb, reverse
##   VEH   índice do carro em main.gd VEHICLES (0 Renegade, 1 Sphinx, 2 Sphinx speedrun)
##   TUNE  JSON sobrescrevendo peças, ex.: {"engine":0.81,"mass":1.0}
##   MU    aderência do chão (padrão 0.8)
##   AMORT Damping do chão (arrasto, padrão 0 = terra comum; fora da pista 0.2)
##   ST    direção no roteiro hs (padrão 1)
##   LDT   intervalo do log em s (padrão 0.25)
##   HZ    passos de física por segundo (padrão do projeto: 50 = PAL, como o
##         nosso exe; 60 = NTSC, pra comparar com vídeo da versão americana)
##   LEG=1 pneus antigos   LAT=0 lateral remendo
const Car := preload("res://carro/car.gd")
const Main := preload("res://main.gd")
var car
var t := 0.0
var log_t := 0.0


func _ready():
	if OS.get_environment("HZ") != "":
		Engine.physics_ticks_per_second = int(OS.get_environment("HZ"))
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000, 2, 4000)
	cs.shape = box
	cs.position = Vector3(0, -1, 0)
	body.add_child(cs)
	add_child(body)
	var vi := int(OS.get_environment("VEH")) if OS.get_environment("VEH") != "" else 0
	var v: Dictionary = Main.VEHICLES[vi]
	car = Car.new()
	car.asset_dir = v.dir
	car.data_files = ["res://data/vehicles/buggy_base.xml", v.data]
	car.points_file = v.points
	car.vehicle_id = v.id
	car.vehicle_name = v.name
	car.tune_override = v.get("tune", {})
	car.suspension = false
	if OS.get_environment("TUNE") != "":
		car.tune_override = JSON.parse_string(OS.get_environment("TUNE"))
	if OS.get_environment("MU") != "":
		car.SURFACE_MU = OS.get_environment("MU").to_float()   # antes do _ready
	if OS.get_environment("AMORT") != "":
		car.SURFACE_AMORT = OS.get_environment("AMORT").to_float()
	add_child(car)
	car.reset_to(Vector3(0, 1.0, -1500), 0.0)
	car.test_input = {"thr": 0.0, "brk": 0.0, "steer": 0.0}
	car.use_ported = OS.get_environment("LEG") == ""
	car.lateral_game = OS.get_environment("LAT") != "0"
	print("veiculo=%s massa=%.0f com=%s" % [car.vehicle_name, car.mass, car.center_of_mass])
	print("gears=%s final=%.3f up_rpm=%.0f auto_time=%.2f clutch_max=%.0f drive=%.0f fric=%.0f" % [car.gears, car.P.final, car.P.up_rpm, car.P.auto_time, car.P.clutch_max, car.P.drive_scale, car.P.fric_scale])


func _physics_process(d):
	t += d
	var sc: String = OS.get_environment("SC")
	if sc == "": sc = "accel"
	var ti = car.test_input
	if sc == "accel":
		ti.thr = 1.0 if t > 1.0 and t < 25.0 else 0.0
		ti.brk = 1.0 if t >= 25.0 else 0.0
	elif sc == "coast":
		ti.thr = 1.0 if t > 1.0 and t < 14.0 else 0.0
	elif sc == "man":
		car.manual = true
		ti.thr = 1.0 if t > 1.0 and t < 9.0 else 0.0
		ti.brk = 1.0 if t > 9.0 else 0.0
		for ts in [3.0, 4.5, 6.0]:
			if t - d < ts and t >= ts: car._start_shift(car.gear + 1)
		for ts in [10.0, 10.5, 11.0, 11.5]:
			if t - d < ts and t >= ts: car._start_shift(car.gear - 1)
	elif sc == "s50":
		ti.thr = 1.0 if t > 1.0 and t < 2.6 else 0.5
		ti.steer = 1.0 if t > 3.0 and t < 9.0 else 0.0
	elif sc == "half":
		ti.thr = 1.0 if t > 1.0 and t < 4.5 else 0.6
		ti.steer = 0.5 if t > 5.0 and t < 10.0 else 0.0
	elif sc == "hs":
		var st := float(OS.get_environment("ST")) if OS.get_environment("ST") != "" else 1.0
		ti.thr = 1.0 if t > 1.0 else 0.0
		ti.steer = st if t > 8.0 and t < 11.0 else 0.0
	elif sc == "turn":
		ti.thr = 1.0 if t > 1.0 else 0.0
		if t > 8.0: ti.thr = 0.6
		ti.steer = 1.0 if t > 8.0 else 0.0
	elif sc == "turnslow":
		ti.thr = 1.0 if t > 1.0 and t < 3.5 else 0.0
		ti.steer = 1.0 if t > 4.0 else 0.0
	elif sc == "mid":
		ti.thr = 1.0 if t > 1.0 and t < 4.5 else 0.5
		ti.steer = 1.0 if t > 5.0 and t < 9.0 else 0.0
	elif sc == "hb":
		ti.thr = 1.0 if t > 1.0 else 0.0
		ti.steer = 1.0 if t > 5.0 and t < 8.0 else 0.0
		ti.hb = t > 5.0 and t < 6.0      # botão da embreagem (o jogo não tem freio de mão)
	elif sc == "freio" or sc == "freiocurva":
		# acelera até ~7 s e pisa no freio (curva: virando metade)
		ti.thr = 1.0 if t > 1.0 and t < 7.0 else 0.0
		ti.brk = 1.0 if t >= 7.0 else 0.0
		if sc == "freiocurva":
			ti.steer = 0.5 if t >= 7.0 else 0.0
	elif sc == "reverse":
		ti.brk = 1.0 if t > 1.0 and t < 6 else 0.0
	log_t += d
	if log_t >= float(OS.get_environment("LDT") if OS.get_environment("LDT") != "" else "0.25"):
		log_t = 0.0
		var v = car.linear_velocity
		var xs = []
		for w in car.wheels: xs.append("%.2f" % w.x)
		print("t=%5.1f v=%6.1fkm/h g=%s rpm=%5.0f cl=%.2f thr=%.2f y=%.2f yaw=%5.2f ss=%5.1f pitch=%5.1f roll=%5.1f x=%s grd=%d sl=%.2f" % [t, v.length()*3.6 * signf(v.dot(car.forward())), car.gear_label(), car.rpm, car.clutch, car.throttle, car.global_position.y, car.angular_velocity.y, rad_to_deg(car.sideslip), rad_to_deg(car.rotation.x), rad_to_deg(car.rotation.z), xs, car.grounded, car.drive_slip])
	var end := 30.0 if sc == "accel" else 16.0
	if t > end: get_tree().quit()
