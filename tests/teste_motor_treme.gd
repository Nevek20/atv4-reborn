extends SceneTree
## Motor tremendo (motor_treme.gd, melhoria nossa): em cada carro (buggies,
## trucks e o bônus; VEHS=13,14 só esses índices da frota) conta as
## peças e faces que saem da carroceria pro motor, o centro do motor e confere
## que a carroceria + motor têm as mesmas faces de antes (nada some).
## Uso: godot --headless --path . -s res://tests/teste_motor_treme.gd
const Car := preload("res://carro/car.gd")
const Main := preload("res://main.gd")

var i := -1
var car = null
var vistos := {}
var falhas := 0


func _process(_dt: float) -> bool:
	if car != null:
		_conferir()
		car.free()
		car = null
	i += 1
	var frota: Array = Main.frota()
	var so := []
	if OS.has_environment("VEHS"):
		for x in OS.get_environment("VEHS").split(","):
			so.append(int(x))
	while i < frota.size() and (vistos.has(frota[i].dir) or frota[i].get("extra", false) \
			or (not so.is_empty() and not (i in so))):
		i += 1
	if i >= frota.size():
		print("teste_motor_treme: %s" % ("ok" if falhas == 0 else "FALHA"))
		return true
	var v: Dictionary = frota[i]
	vistos[v.dir] = true
	car = Car.new()
	Main.configurar(car, v)
	car.desligadas = []             # todas as melhorias (o teste confere as faces com o painel junto)
	car.suspension = false
	root.add_child(car)
	car.set_physics_process(false)
	car.set_process(false)
	return false


func _faces(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		var ix = a[Mesh.ARRAY_INDEX]
		n += (ix.size() if ix != null and ix.size() > 0 else a[Mesh.ARRAY_VERTEX].size()) / 3
	return n


func _conferir() -> void:
	var v: Dictionary = Main.frota()[i]
	var mt = car.motor_treme
	if mt == null:
		print("%-12s sem motor separado (sem ponto EXHAUST)" % v.name)
		return
	var original: Mesh = load(car.model_path)
	var antes: int = _faces(original) - (car.painel.apagadas if car.painel else 0)   # painel.gd APAGAR
	var depois := _faces(car.body_mi.mesh)
	for m in [car.body_mi, mt.malha, mt.malha_escape]:
		if m == null:
			continue
		if m != car.body_mi:
			depois += _faces(m.mesh)
		for f in m.get_children():      # ventoinhas que giram (motor_anima.gd)
			if f is MeshInstance3D and "Ventoinha" in str(f.name):
				depois += _faces(f.mesh)
	var ok := antes == depois
	if not ok:
		falhas += 1
	var bocas := []                     # malha da boca de cada cano (a fumaça segue)
	for k in mt.bocas:
		bocas.append(["fica", "motor", "escape"][mt.bocas[k]])
	print("%-12s %2d peças %4d faces tremem (de %d, escape %d)  centro (%.2f, %.2f, %.2f)  bocas %s  %s" % [
		v.name, mt.pecas, mt.faces, antes, _faces(mt.malha_escape.mesh) if mt.malha_escape else 0,
		mt.centro.x, mt.centro.y, mt.centro.z, ",".join(bocas), "ok" if ok else "FALHA faces %d -> %d" % [antes, depois]])
