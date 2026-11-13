extends SceneTree
## Física do carro em C++ (fisica_cpp/, bin/atv4_fisica.gdextension): a
## extensão carrega e cada conta portada dá EXATAMENTE os mesmos números do
## GDScript (comparação com ==, não com tolerância).
##  - curvas do VehicleData (sample, integrate, triple, fcurve_eval): todas
##    as do P do Renegade, do Jericho e do Lazarus numa grade de x e mu.
## Uso: godot --headless --path . -s res://tests/teste_cpp.gd

const VD := preload("res://carro/vehicle_data.gd")

var main
var q := 0
var falhas := 0
var contas := 0
var carros := ["Renegade", "Jericho", "Lazarus"]
var k := 0
var espera := 0


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
	print("  %d contas comparadas" % contas)
	print("teste_cpp: %s" % ("ok" if falhas == 0 and contas > 0 else "FALHA (%d de %d)" % [falhas, contas]))
	return true
