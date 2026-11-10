extends SceneTree
## Largada do Renegade de fábrica no RX01 (terreno de verdade, ponto da
## largada do jogo), acelerador no fundo e volante reto, contra a gravação do
## jogo PAL (Matheus, out/2026: Renegade de fábrica = 440.6 HP na tela de
## peças, sozinho na pista, relógio da corrida e km/h lidos quadro a quadro).
## Tempo contado desde que o carro anda (>= 1 km/h). Na 1ª as rodas patinam e
## o motor fica batendo no limitador; isso depende do passo da física (o jogo
## PAL roda a 50 Hz), então rode no passo do projeto.
## Uso: godot --headless --path . -s res://tests/teste_largada.gd [-- veh [passos_por_segundo]]
##      (com -- 0 0 imprime também a curva inteira)

const Car := preload("res://carro/car.gd")
const Main := preload("res://main.gd")
const Terrain := preload("res://pista/terrain.gd")
# gravação PAL: segundos desde que anda -> km/h (marcha 2 aparece em 2.60 s,
# marcha 3 em 3.70 s)
const VIDEO := [[0.2, 7], [0.4, 13], [0.6, 21], [0.8, 27], [1.0, 31], [1.2, 35], [1.4, 39], [1.6, 43],
	[1.8, 49], [2.0, 54], [2.2, 60], [2.4, 65], [2.6, 65], [2.8, 69], [3.0, 78], [3.2, 87], [3.4, 95],
	[3.6, 97], [3.8, 98], [4.0, 105], [4.2, 111], [4.4, 117]]
# save states PAL da largada de fábrica (Matheus, out/2026, acelerador no
# fundo): km/h, patinada 0x610 das rodas de trás, rpm (embreagem já travada)
const RAM := [[8.6, 0.48, 1379], [9.8, 0.48, 1568], [19.8, 1.20, 4763], [22.1, 1.38, 5766]]

var terrain
var car
var t := 0.0
var t_anda := -1.0
var curva := []                  # [tempo desde que anda, km/h, marcha, patinada, rpm]
var imprime := false


func _initialize() -> void:
	terrain = Terrain.new()
	root.add_child(terrain)
	var a := OS.get_cmdline_user_args()
	var v: Dictionary = Main.VEHICLES[int(a[0]) if a.size() > 0 else 0]
	if a.size() > 1 and int(a[1]) > 0:
		Engine.physics_ticks_per_second = int(a[1])
	imprime = a.size() > 1 and int(a[1]) == 0
	car = Car.new()
	car.asset_dir = v.dir
	car.data_files = ["res://data/vehicles/buggy_base.xml", v.data]
	car.points_file = v.points
	car.vehicle_id = v.id
	car.tune_override = v.get("tune", {})
	car.terrain = terrain
	car.suspension = false
	root.add_child(car)
	car.test_input = {"thr": 0.0, "brk": 0.0, "steer": 0.0}


func _physics_process(dt: float) -> bool:
	if not car.is_inside_tree():
		return false
	if t == 0.0:
		var p: Vector2 = Main.SPAWN_XZ
		car.reset_to(Vector3(p.x, terrain.height_at(p.x, p.y) + 0.8, p.y), deg_to_rad(Main.SPAWN_YAW))
	t += dt
	car.test_input.thr = 1.0 if t > 1.5 else 0.0
	var kmh: float = car.linear_velocity.length() * 3.6
	if t_anda < 0.0 and t > 1.5 and kmh >= 1.0:
		t_anda = t
	if t_anda >= 0.0:
		curva.append([t - t_anda, kmh, car.gear_label(), car.drive_slip, car.rpm])
		if imprime:
			print("%.3f %.2f %s %d" % [t - t_anda, kmh, car.gear_label(), int(car.rpm)])
		if t - t_anda > 4.6:
			_comparar()
			quit()
	return false


func _em(tt: float) -> float:
	for i in curva.size() - 1:
		var a: Array = curva[i]
		var b: Array = curva[i + 1]
		if a[0] <= tt and tt <= b[0]:
			return a[1] + (b[1] - a[1]) * (tt - a[0]) / maxf(b[0] - a[0], 1e-9)
	return NAN


func _troca(g: String) -> float:
	for c in curva:
		if c[2] == g:
			return c[0]
	return NAN


func _comparar() -> void:
	var txt := []
	var pior := 0.0
	for p in VIDEO:
		var r := _em(p[0])
		pior = maxf(pior, absf(r - p[1]))
		txt.append("%.1f %d/%.0f" % [p[0], p[1], r])
	print("passo %d Hz | vídeo/remake (km/h): %s" % [Engine.physics_ticks_per_second, "  ".join(txt)])
	# 1ª no limitador: tempo de 30 a 60 km/h (vídeo 0.95 -> 2.2 s = 1.25 s)
	var t30 := -1.0
	var t60 := -1.0
	for c in curva:
		if t30 < 0.0 and c[1] >= 30.0:
			t30 = c[0]
		if t60 < 0.0 and c[1] >= 60.0:
			t60 = c[0]
	print("1ª de 30 a 60 km/h: %.2f s (vídeo 1.25)  2ª aparece em %.2f s (vídeo 2.60)  3ª em %.2f s (vídeo 3.70)  maior diferença %.1f km/h" % [
		t60 - t30, _troca("2"), _troca("3"), pior])
	# patinada e rpm na velocidade de cada save state
	txt = []
	for r in RAM:
		for i in curva.size() - 1:
			var a: Array = curva[i]
			var b: Array = curva[i + 1]
			if a[1] <= r[0] and r[0] < b[1]:
				var f: float = (r[0] - a[1]) / maxf(b[1] - a[1], 1e-9)
				txt.append("%.1f: %.2f/%.2f %d/%d" % [r[0], r[1], lerpf(a[3], b[3], f), r[2], lerpf(a[4], b[4], f)])
				break
	print("save states (km/h: patinada jogo/remake, rpm jogo/remake): %s" % "  ".join(txt))
