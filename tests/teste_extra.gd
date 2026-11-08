extends SceneTree
## Carros extras nossos (main.gd EXTRAS, tools/carro_glb.py) em chão plano:
## 1) parado: curso de cada roda x o "estático" do carro_glb (o ponto WHEEL
##    fica isso abaixo da roda do modelo; se bater, a roda desenhada parada cai
##    no lugar dela no modelo) e a folga do casco até o chão;
## 2) acelerando reto: tempo de 0 a 100 km/h, velocidade em 20 s e a marcha.
## Uso: godot --headless --path . -s res://tests/teste_extra.gd   (EXTRA=0 só o 1º;
## FROTA=16,25 compara carros da frota, ex. Jericho x Lazarus)

const Car := preload("res://carro/car.gd")
const Main := preload("res://main.gd")

var carros := []        # [car, v, estado]
var t := 0.0


class Estado:
	var curso := []
	var folga := 0.0
	var t100 := -1.0
	var v20 := 0.0
	var marcha := 0


func _initialize() -> void:
	var chao := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8000, 2, 8000)
	cs.shape = box
	cs.position = Vector3(0, -1, 0)
	chao.add_child(cs)
	root.add_child(chao)
	var so := int(OS.get_environment("EXTRA")) if OS.has_environment("EXTRA") else -1
	var lista: Array = Main.EXTRAS
	if OS.has_environment("FROTA"):           # FROTA=16,25: esses carros da frota (Jericho x Lazarus)
		lista = []
		for x in OS.get_environment("FROTA").split(","):
			lista.append(Main.frota()[int(x)])
	for i in lista.size():
		if so >= 0 and i != so:
			continue
		var v: Dictionary = lista[i]
		var c = Car.new()
		Main.configurar(c, v)
		c.suspension = false
		c.SURFACE_MU = 0.8
		c.SURFACE_AMORT = 0.0
		root.add_child(c)
		c.reset_to(Vector3(i * 40.0, 1.0, -3500), 0.0)
		c.test_input = {"thr": 0.0, "brk": 0.0, "steer": 0.0}
		carros.append([c, v, Estado.new()])


func _physics_process(dt: float) -> bool:
	t += dt
	for e in carros:
		var c = e[0]
		var s: Estado = e[2]
		if t >= 3.0 and s.curso.is_empty():
			for w in c.wheels:
				s.curso.append(w.x)
			var baixo := INF
			for sh in c.get_children():
				if sh is CollisionShape3D and sh.shape is SphereShape3D and not sh.disabled:
					baixo = minf(baixo, sh.global_position.y - sh.shape.radius)
			s.folga = baixo
		if t >= 3.0:
			c.test_input.thr = 1.0
			var kmh: float = c.linear_velocity.length() * 3.6
			if s.t100 < 0.0 and kmh >= 100.0:
				s.t100 = t - 3.0
			if t <= 23.0:
				s.v20 = kmh
				s.marcha = c.gear
	if t < 23.0:
		return false
	for e in carros:
		var v: Dictionary = e[1]
		var s: Estado = e[2]
		var p = JSON.parse_string(FileAccess.get_file_as_string(v.dir.path_join("pecas.json")))
		var est = p.get("estatico", []) if p is Dictionary else []
		print("%s: curso parado %s (estático do carro_glb frente, trás %s), casco a %.1f cm do chão" % [
			v.name, str(s.curso.map(func(x): return snappedf(x, 0.001))), str(est), s.folga * 100.0])
		print("   0-100 km/h em %.2f s, %.0f km/h em 20 s (marcha %d)" % [s.t100, s.v20, s.marcha])
	return true
