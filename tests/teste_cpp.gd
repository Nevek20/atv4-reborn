extends SceneTree
## Física do carro em C++ (fisica_cpp/, bin/atv4_fisica.gdextension): a
## extensão carrega e cada conta portada dá EXATAMENTE os mesmos números do
## GDScript (comparação com ==, não com tolerância).
##  - curvas do VehicleData (sample, integrate, triple, fcurve_eval): todas
##    as do P do Renegade, do Jericho e do Lazarus numa grade de x e mu.
##  - pose do piloto (piloto.cpp): ossos iguais ao GDScript até TOL_POSE
##    (só desenho; o Godot do C++ é o godot-cpp, conta igual mas outra
##    compilação), numa grade de direção e tremida.
##  - suspensão visual (suspensao.cpp): todas as peças e pivôs das rodas
##    iguais até TOL_POSE, com cursos e esterço variados (Mosquito: barras;
##    Storm: rally; Hammerhead: telescópio; Fireball: balança deslocada).
## Uso: godot --headless --path . -s res://tests/teste_cpp.gd

const VD := preload("res://carro/vehicle_data.gd")

var main
var q := 0
var falhas := 0
var contas := 0
var carros := ["Renegade", "Jericho", "Lazarus", "Mosquito", "Storm", "Hammerhead", "Fireball"]
var k := 0
var espera := 0
const TOL_POSE := 1e-5
var pior_pose := 0.0


func _initialize() -> void:
	if not ClassDB.class_exists("FisicaCarro"):
		print("teste_cpp: FALHA (extensão não carregou: falta a biblioteca em bin/?)")
		quit()
		return
	print("  extensão: ", ClassDB.class_call_static("FisicaCarro", "versao"))
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _falha(m: String) -> void:
	falhas += 1
	if falhas <= 10:
		print("FALHA: ", m)


func _igual(nome: String, a: float, b: float) -> void:
	contas += 1
	if a != b and not (is_nan(a) and is_nan(b)):
		_falha("%s: GDScript %.17g, C++ %.17g" % [nome, a, b])


## chama o C++ pelo ClassDB (o script carrega mesmo sem a biblioteca)
static func _cpp(f: String, a = null, b = null, c = null) -> float:
	if c != null:
		return ClassDB.class_call_static("FisicaCarro", f, a, b, c)
	return ClassDB.class_call_static("FisicaCarro", f, a, b)


func _curvas(P: Dictionary) -> void:
	var xs := [-1.0, 0.0, 0.013, 0.5, 1.0, 3.7, 12.0, 37.5, 80.0, 133.3, 250.0, 1e4]
	var mus := [0.0, 0.05, 0.1, 0.33, 0.7, 0.999, 1.0, 1.2]
	for nome in P:
		var c = P[nome]
		if not (c is Dictionary):
			continue
		if c.has("v"):
			for x in xs:
				_igual("%s sample(%s)" % [nome, x], VD.sample(c, x), _cpp("curva_sample", c, x))
				_igual("%s integrate(%s)" % [nome, x], VD.integrate(c, x), _cpp("curva_integrate", c, x))
		elif c.has("lmin") and c.get("min") is Dictionary:
			for mu in mus:
				for x in xs:
					_igual("%s fcurve(%s, %s)" % [nome, mu, x], VD.fcurve_eval(c, mu, x), _cpp("fcurvas", c, mu, x))
		elif c.has("lmin"):
			for mu in mus:
				_igual("%s triple(%s)" % [nome, mu], VD.triple(c, mu), _cpp("trio", c, mu))


func _ossos(sk: Skeleton3D) -> Array:
	var out := []
	for b in sk.get_bone_count():
		out.append([sk.get_bone_pose_position(b), sk.get_bone_pose_rotation(b), sk.get_bone_pose_scale(b)])
	return out


func _piloto(car) -> void:
	var pil = car.piloto
	if pil == null:
		print("  %s: sem piloto" % car.vehicle_name)
		return
	if pil._cpp == null:
		_falha("%s: piloto sem C++" % car.vehicle_name)
		return
	var cpp = pil._cpp
	for s in [-1.0, -0.73, -0.31, -0.02, 0.0, 0.05, 0.4, 0.88, 1.0]:
		for extra in [0.0, 0.03, -0.05]:
			pil._cpp = cpp
			pil.alcance = 0.0
			pil.pose(s, extra)
			var b := _ossos(pil.skel)
			var alc_cpp: float = pil.alcance
			pil._cpp = null
			pil.alcance = 0.0
			pil.pose(s, extra)
			var a := _ossos(pil.skel)
			var alc_gd: float = pil.alcance
			pil._cpp = cpp
			contas += 1
			for i in a.size():
				var d: float = maxf(a[i][0].distance_to(b[i][0]), (a[i][1] - b[i][1]).length())
				d = maxf(d, a[i][2].distance_to(b[i][2]))
				pior_pose = maxf(pior_pose, d)
				if d > TOL_POSE:
					_falha("%s piloto s=%s extra=%s osso %d: diferença %s" % [car.vehicle_name, s, extra, i, d])
					break
			if absf(alc_gd - alc_cpp) > TOL_POSE:
				_falha("%s piloto alcance %s x %s" % [car.vehicle_name, alc_gd, alc_cpp])


func _nos(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Node3D:
			out.append(c)
		_nos(c, out)


func _suspensao(car) -> void:
	var sv = car.susp_vis
	if sv == null:
		print("  %s: sem suspensão visual" % car.vehicle_name)
		return
	if sv._cpp == null:
		_falha("%s: suspensão sem C++" % car.vehicle_name)
		return
	var cpp = sv._cpp
	var nos: Array = []
	_nos(car.espelho, nos)
	var guarda := []
	for w in car.wheels:
		guarda.append([w.x, w.get("jit", 0.0)])
	var casos := [[0.0, 0.0, 0.0], [1.0, 0.004, 0.2], [-1.0, -0.003, -0.35], [0.4, 0.0, 0.05]]
	for c in casos:
		for i in car.wheels.size():
			var w: Dictionary = car.wheels[i]
			# frente e trás, esquerda e direita com cursos diferentes
			var f: float = c[0] * (0.3 + 0.2 * i)
			w.x = w.max * f if f > 0.0 else -w.min * f
			w.jit = c[1] * (1 if i % 2 == 0 else -1)
		# C++ primeiro: se ele não mexesse em nada, as peças ficariam na pose do
		# caso anterior e não bateriam com a do GDScript
		sv._cpp = cpp
		sv.update(c[2])
		var b := nos.map(func(n): return n.transform)
		sv._cpp = null
		sv.update(c[2])
		sv._cpp = cpp
		contas += 1
		for j in nos.size():
			var ta: Transform3D = nos[j].transform
			var tb: Transform3D = b[j]
			var d := ta.origin.distance_to(tb.origin)
			for e in 3:
				d = maxf(d, ta.basis[e].distance_to(tb.basis[e]))
			pior_pose = maxf(pior_pose, d)
			if d > TOL_POSE:
				_falha("%s suspensão caso %s: %s diferença %s" % [car.vehicle_name, c, nos[j].name, d])
				break
	for i in car.wheels.size():
		car.wheels[i].x = guarda[i][0]
		car.wheels[i].jit = guarda[i][1]


func _physics_process(_dt: float) -> bool:
	q += 1
	if main.car == null:
		return q > 300
	if q < 5:
		return false
	# troca de carro, espera 3 quadros, confere as curvas dele, próximo
	if espera > 0:
		espera -= 1
		if espera == 0:
			_curvas(main.car.P)
			_piloto(main.car)
			_suspensao(main.car)
			print("  %s: curvas conferidas" % main.car.vehicle_name)
		return false
	if k < carros.size():
		var lista: Array = main.frota()
		for i in lista.size():
			if lista[i].name == carros[k]:
				main._swap_vehicle(i)
				break
		k += 1
		espera = 3
		return false
	print("  %d contas comparadas (piloto e suspensão: pior diferença %s)" % [contas, pior_pose])
	print("teste_cpp: %s" % ("ok" if falhas == 0 and contas > 0 else "FALHA (%d de %d)" % [falhas, contas]))
	return true
