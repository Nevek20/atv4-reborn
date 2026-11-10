extends SceneTree
## Quanto cada etapa da carga de um carro leva (car.gd _marca). VEH = índice
## da frota (padrão 26, o Escort: 200 mil triângulos).
## Uso: TEMPO_CARGA=1 VEH=26 godot --headless --path . -s res://tests/tempo_carga.gd
const Car := preload("res://carro/car.gd")
const Main := preload("res://main.gd")
func _initialize() -> void:
	for i in [int(OS.get_environment("VEH")) if OS.has_environment("VEH") else 26]:
		var c = Car.new()
		Main.configurar(c, Main.frota()[i])
		var t := Time.get_ticks_msec()
		root.add_child(c)
		print(c.vehicle_name, " total ", Time.get_ticks_msec() - t, " ms")
	quit()
