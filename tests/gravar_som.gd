extends SceneTree
## Prévia do som do motor: põe o buggy na largada, espera parado, acelera
## tudo (sobe as marchas sozinho), solta e volta pra lenta. Rodar com o
## Movie Maker do Godot, que grava o áudio junto:
##   godot --path . --write-movie previa.avi --fixed-fps 60 -s res://tests/gravar_som.gd -- 7
## (na nuvem: xvfb-run -a ... --rendering-driver opengl3). O argumento é o
## índice em main.VEHICLES. Tempos (s): PARADO, ACELERA, SOLTA.
## VIRA=4 vira tudo a partir de 4 s de aceleração (derrapa: pneu e suspensão),
## SEM_MOTOR=1 tira o som do motor (só pneu, suspensão e pouso).
## SOM_PASTA=/caminho/dos/loops troca os loops do motor (comparar variantes).

const PARADO := 1.5
const ACELERA := 9.0
const SOLTA := 5.0

var main
var veh := 0
var t := 0.0
var pronto := false


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		veh = int(a[0])
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _process(dt: float) -> bool:
	if not pronto:
		if main.car == null:
			return false
		if main.veh_idx != veh:
			main.car.queue_free()
			main.spawn_vehicle(veh, main.spawn_point(), deg_to_rad(main.SPAWN_YAW))
			return false
		pronto = true
		if OS.get_environment("SOM_PASTA") != "" and main.car.som:
			var c = main.car
			c.som.queue_free()
			c.som = preload("res://som/motor_som.gd").new()
			c.som.name = "SomMotorTeste"
			if c.som.carregar(OS.get_environment("SOM_PASTA")):
				c.add_child(c.som)
				print("loops do motor: ", OS.get_environment("SOM_PASTA"))
			else:
				c.som = null
				print("SOM_PASTA sem info.csv: ", OS.get_environment("SOM_PASTA"))
	var car = main.car
	t += dt
	var thr := 1.0 if t > PARADO and t < PARADO + ACELERA else 0.0
	var vira := 0.0
	if OS.has_environment("VIRA") and t > PARADO + float(OS.get_environment("VIRA")) and t < PARADO + ACELERA:
		vira = 1.0
	if OS.has_environment("SEM_MOTOR") and car.som:
		car.som.queue_free()
		car.som = null
	car.test_input = {"thr": thr, "steer": vira}
	if OS.has_environment("DETALHE") or int(t * 4.0) != int((t - dt) * 4.0):
		print("%.2f s  %3.0f km/h  marcha %s  rpm %4.0f  real %4.0f  carga %.2f" % [
			t, car.linear_velocity.length() * 3.6, car.gear_label(), car.rpm, car.som.r_real if car.som else 0.0, car.som_carga])
	return t > PARADO + ACELERA + SOLTA
