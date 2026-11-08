extends SceneTree
## Motor animado (motor_anima.gd, melhoria nossa): em cada buggy conta as
## placas de ventoinha que giram, as polias e correias 3D, confere que nenhuma
## face sumiu (carroceria + motor + escape + ventoinhas = modelo) e que a
## correia encosta nas polias (cada ponto dela fica a meia espessura da borda
## de uma polia ou no trecho reto entre as duas).
## Uso: godot --headless --path . -s res://tests/teste_motor_anima.gd
const Car := preload("res://carro/car.gd")
const Main := preload("res://main.gd")
const MotorAnima := preload("res://carro/motor_anima.gd")

# esperado (levantamento das texturas, out/2026): placas de ventoinha e pares de polias
const ESPERADO := {"BUGGY_10": [2, 0], "BUGGY_04": [2, 0], "BUGGY_01": [2, 0], "BUGGY_02": [2, 0],
	"BUGGY_03": [2, 0], "BUGGY_05": [1, 0], "BUGGY_06": [0, 1], "BUGGY_07": [0, 1],
	"BUGGY_08": [2, 1], "BUGGY_09": [0, 1], "BUGGY_11": [0, 0], "BUGGY_12": [0, 0],
	"TRUCK_05": [2, 0], "TRUCK_06": [2, 0], "TRUCK_07": [3, 0], "TRUCK_08": [2, 0],
	"TRUCK_09": [1, 0], "LAZARUS": [3, 0]}
	# trucks (car.gd ANIMA_TRUCKS): Punisher (radiadores na caçamba), Panther,
	# Truggy (2 radiadores, um em 2 pedaços), TT, Hammerhead (1 deitada em cima)
	# e Lazarus (3 viradas pra trás em cima dos estepes); conferido com
	# print_tela VENTOINHA_COR=1 (nov/2026)

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
	if OS.has_environment("VEHS"):        # VEHS=13,14: só esses índices da frota
		for x in OS.get_environment("VEHS").split(","):
			so.append(int(x))
	while i < frota.size() and (vistos.has(frota[i].dir) or frota[i].get("extra", false) \
			or (not so.is_empty() and not (i in so))):
		i += 1
	if i >= frota.size():
		print("teste_motor_anima: %s" % ("ok" if falhas == 0 else "FALHA"))
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


static func _faces(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		var ix = a[Mesh.ARRAY_INDEX]
		n += (ix.size() if ix != null and ix.size() > 0 else a[Mesh.ARRAY_VERTEX].size()) / 3
	return n


func _conferir() -> void:
	var v: Dictionary = Main.frota()[i]
	var ma = car.motor_anima
	var malhas: Array = [car.body_mi]
	if car.motor_treme:
		malhas.append_array([car.motor_treme.malha, car.motor_treme.malha_escape])
	var antes: int = _faces(load(car.model_path)) - (car.painel.apagadas if car.painel else 0)
	var depois := 0
	var vent_faces := 0
	var pares := 0
	var pior := 0.0
	for m in malhas:
		if m == null:
			continue
		depois += _faces(m.mesh)
		for f in m.get_children():
			if f is MeshInstance3D and "Ventoinha" in str(f.name):
				vent_faces += _faces(f.mesh)
			elif "Polias" in str(f.name):
				pares += 1
				pior = maxf(pior, _encosta(f))
	depois += vent_faces
	var placas: int = ma.n_ventoinhas if ma else 0
	var esp: Array = ESPERADO.get(car.chave(), [0, 0])
	var ok: bool = antes == depois and placas == esp[0] and pares == esp[1] and pior < 0.001
	if not ok:
		falhas += 1
	print("%-12s ventoinhas %d (%3d faces)  polias %d pares  correia fora da polia %.1f mm  faces %d -> %d  %s" % [
		v.name, placas, vent_faces, pares, pior * 1000.0, antes, depois,
		"ok" if ok else "FALHA (esperado %d ventoinhas, %d pares)" % esp])
	if ma:
		ma.atualizar(0.1, 3000.0)       # roda uma vez (shader e parâmetros)


## quanto a correia entra numa polia (m): vértice dela mais perto do eixo de
## uma polia do que o raio (eixo e raio pela tampa)
static func _encosta(no: Node) -> float:
	var polias: Array = []            # [centro, normal, raio]
	var correia: MeshInstance3D = null
	for c in no.get_children():
		if "Tampa" in str(c.name):
			var a := (c as MeshInstance3D).mesh.surface_get_arrays(0)
			var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var ce := Vector3.ZERO
			for p in vs:
				ce += p
			ce /= vs.size()
			var r := 0.0
			for p in vs:
				r = maxf(r, p.distance_to(ce))
			polias.append([ce, (a[Mesh.ARRAY_NORMAL] as PackedVector3Array)[0], r])
		elif "Correia" in str(c.name):
			correia = c
	if correia == null or polias.size() != 2:
		return INF
	var pior := 0.0
	for p in correia.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		for q in polias:
			var d: Vector3 = p - q[0]
			d -= q[1] * q[1].dot(d)
			pior = maxf(pior, q[2] - 0.0005 - d.length())
	return pior
