extends SceneTree
## Truck na largada do RX01 contra os vídeos do Matheus (tests/ref_buccaneer_
## video.json: Buccaneer de fábrica, HUD lido em todos os quadros). Acelerador
## no fundo e volante reto; com VIRA=-1 (esquerda) ou 1, vira tudo no tempo
## "vira_em" do vídeo da curva e compara a queda de velocidade. Imprime km/h
## do jogo x remake (HUD do jogo = 1.06 x a velocidade pra frente; entre
## parênteses o |v|), marcha, guinada e inclinação.
## Uso: godot --headless --path . -s res://tests/teste_truck_video.gd -- 13 [VIRA=-1]

const Car := preload("res://carro/car.gd")
const Main := preload("res://main.gd")
const Terrain := preload("res://pista/terrain.gd")

var terrain
var car
var ref: Dictionary
var t := 0.0
var t_anda := -1.0
var vira := 0.0
var curva := []                  # [tempo desde que anda, hud, |v|, marcha, guinada°, inclinação°]
var yaw0 := 0.0


func _initialize() -> void:
	ref = JSON.parse_string(FileAccess.get_file_as_string("res://tests/ref_buccaneer_video.json"))
	vira = float(OS.get_environment("VIRA")) if OS.has_environment("VIRA") else 0.0
	terrain = Terrain.new()
	root.add_child(terrain)
	var a := OS.get_cmdline_user_args()
	var v: Dictionary = Main.frota()[int(a[0]) if a.size() > 0 else 13]
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
		var p: Vector2 = Main.SPAWN_XZ
		car.reset_to(Vector3(p.x, terrain.height_at(p.x, p.y) + 0.8, p.y), deg_to_rad(Main.SPAWN_YAW))
	t += dt
	car.test_input.thr = 1.0 if t > 1.5 else 0.0
	var kmh: float = car.linear_velocity.length() * 3.6
	if t_anda < 0.0 and t > 1.5 and kmh >= 1.0:
		t_anda = t
		yaw0 = car.global_transform.basis.get_euler().y
	if t_anda >= 0.0:
		var ta := t - t_anda
		if vira != 0.0 and ta >= float(ref.vira_em):
			car.test_input.steer = vira
		var b: Basis = car.global_transform.basis
		var hud: float = car.linear_velocity.dot(b.z) * 3.6 * 1.06
		var guinada := rad_to_deg(wrapf(b.get_euler().y - yaw0, -PI, PI))
		var inc := rad_to_deg(acos(clampf(b.y.y, -1.0, 1.0)))
		curva.append([ta, hud, kmh, car.gear_label(), guinada, inc])
		if OS.get_environment("CHAO") == "1" and int(ta * 2.5) != int((ta - dt) * 2.5):
			var ms := []
			for w in car.wheels:
				ms.append("%s %.2f/%.1f" % [terrain.material_name(w.mat), w.mu, w.amort])
			print("%.1f s %3.0f km/h  arrasto médio %.2f  pos (%.0f, %.0f)  %s" % [ta, kmh, car.amort_medio,
				car.global_position.x, car.global_position.z, "  ".join(ms)])
		var fim: float = 8.4 if vira != 0.0 else 9.4
		if ta > fim:
			_comparar()
			quit()
	return false


func _em(tt: float) -> Array:
	for c in curva:
		if c[0] >= tt - 1e-6:
			return c
	return curva[curva.size() - 1]


func _comparar() -> void:
	var tab: Array = ref.curva if vira != 0.0 else ref.reto
	var txt := []
	var pior := 0.0
	var soma := 0.0
	for p in tab:
		if vira != 0.0 and p[0] < float(ref.vira_em) - 0.4:
			continue
		var r := _em(p[0])
		pior = maxf(pior, absf(r[1] - p[1]))
		soma += absf(r[1] - p[1])
		txt.append("%.1f %d/%.0f(%.0f) %s/%s" % [p[0], p[1], r[1], r[2], str(p[2]), r[3]])
	print("%s | vídeo/remake km/h (|v|) marcha:" % ("curva" if vira != 0.0 else "reto"))
	for i in range(0, txt.size(), 6):
		print("  " + "   ".join(txt.slice(i, i + 6)))
	print("  maior diferença %.1f km/h, média %.1f" % [pior, soma / maxf(1, txt.size())])
	if vira != 0.0:
		var g := _em(float(ref.vira_em) + 1.0)
		var g2 := _em(float(ref.vira_em) + 2.0)
		var inc_max := 0.0
		for c in curva:
			inc_max = maxf(inc_max, c[5])
		print("  guinada 1 s depois de virar %.0f°, 2 s depois %.0f° (vídeo: na contramão ~3.3 s depois); inclinação máx %.1f°" % [
			g[4], g2[4], inc_max])
