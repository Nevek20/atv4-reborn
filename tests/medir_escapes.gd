extends SceneTree
## Direção dos canos de escape no MODELO x a do ponto EXHAUST (que o jogo não
## lê: a fumaça é nossa, fumaca.gd). Pra cada ponto EXHAUST*: pega os
## vértices da malha a menos de RAIO da boca (frame do jogo = frame da malha),
## acha o eixo do cano pela maior variância (PCA) e vira ele pra boca (do
## miolo dos vértices pra fora). Imprime o ângulo entre os dois e o eixo
## medido, pra corrigir no car.gd ESCAPE_NOSSO o que estiver torto.
## Uso: godot --headless --path . -s res://tests/medir_escapes.gd [-- BUGGY_10 TRUCK_12]
const Car := preload("res://carro/car.gd")
const Main := preload("res://main.gd")

var i := -1
var car = null
var vistos := {}
var so: PackedStringArray = []
var RAIO := float(OS.get_environment("RAIO")) if OS.has_environment("RAIO") else 0.2


func _initialize() -> void:
	so = OS.get_cmdline_user_args()


func _process(_dt: float) -> bool:
	if car != null:
		_medir()
		car.free()
		car = null
	i += 1
	while i < Main.frota().size() and (vistos.has(Main.frota()[i].dir) \
			or (not so.is_empty() and not Main.frota()[i].id in so)):
		i += 1
	if i >= Main.frota().size():
		return true
	var v: Dictionary = Main.frota()[i]
	vistos[v.dir] = true
	car = Car.new()
	Main.configurar(car, v)
	car.suspension = false
	root.add_child(car)
	car.set_physics_process(false)
	car.set_process(false)
	return false


func _medir() -> void:
	var v: Dictionary = Main.frota()[i]
	if car.body_mi == null or not (car.body_mi.mesh is ArrayMesh):
		print("%-9s sem modelo" % v.id)
		return
	# todas as malhas do modelo (a carroceria e as que o motor_treme separou:
	# motor e escape) no frame do jogo; triângulos ligados por posição
	var pos := PackedVector3Array()
	var pai := PackedInt32Array()           # union-find por vértice (posição repetida = mesmo)
	var idx := {}
	var inv: Transform3D = car.espelho.global_transform.affine_inverse()
	for mi in car.model_root.find_children("*", "MeshInstance3D", true, false):
		if not (mi.mesh is ArrayMesh) or not mi.visible:
			continue
		var xf: Transform3D = inv * mi.global_transform
		for s in mi.mesh.get_surface_count():
			var a: Array = mi.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var ids: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var loc := PackedInt32Array()
			for q in vs:
				var g: Vector3 = xf * q - car.model_offset
				var k := Vector3i(roundi(g.x * 1000), roundi(g.y * 1000), roundi(g.z * 1000))
				if not idx.has(k):
					idx[k] = pos.size()
					pos.append(g)
					pai.append(pos.size() - 1)
				loc.append(idx[k])
			if ids.is_empty():
				ids.resize(vs.size())
				for t in vs.size():
					ids[t] = t
			for t in range(0, ids.size() - 2, 3):
				_une(pai, loc[ids[t]], loc[ids[t + 1]])
				_une(pai, loc[ids[t]], loc[ids[t + 2]])
	for nm: String in car.points:
		if not nm.begins_with("EXHAUST"):
			continue
		var p: Vector3 = car.points[nm]
		var d: Vector3 = car.points_rot[nm].z.normalized()
		# a peça (componente ligada) com o vértice mais perto da boca
		var melhor := -1
		var dm := INF
		for k in pos.size():
			var e := pos[k].distance_to(p)
			if e < dm:
				dm = e
				melhor = k
		if melhor < 0 or dm > 0.4:
			print("%-9s %-10s %-10s nada a menos de 0.4 m" % [v.id, v.name, nm])
			continue
		var raiz := _acha(pai, melhor)
		var peca := PackedVector3Array()
		for k in pos.size():
			if _acha(pai, k) == raiz and pos[k].distance_to(p) < RAIO:
				peca.append(pos[k])
		var ax := _eixo(peca)
		if ax.dot(d) < 0.0:
			ax = -ax
		# boca medida: os vértices da ponta (25% mais pra fora no eixo)
		var lo := INF
		var hi := -INF
		for q in peca:
			lo = minf(lo, q.dot(ax))
			hi = maxf(hi, q.dot(ax))
		var boca := Vector3.ZERO
		var nb := 0
		for q in peca:
			if q.dot(ax) > hi - (hi - lo) * 0.25:
				boca += q
				nb += 1
		boca /= maxi(nb, 1)
		if OS.has_environment("VERTICES"):
			for q in peca:
				print("    v (%.3f, %.3f, %.3f)" % [q.x, q.y, q.z])
		var ang := rad_to_deg(acos(clampf(ax.dot(d), -1.0, 1.0)))
		print("%-9s %-10s %-10s ponto (%.3f, %.3f, %.3f) a %.2f m da peça | dir jogo (%.2f, %.2f, %.2f) eixo da peça (%.2f, %.2f, %.2f) %5.1f° | peça %d vértices, %.2f m no eixo, boca (%.3f, %.3f, %.3f)" % [
			v.id, v.name, nm, p.x, p.y, p.z, dm, d.x, d.y, d.z, ax.x, ax.y, ax.z, ang, peca.size(), hi - lo, boca.x, boca.y, boca.z])


static func _acha(pai: PackedInt32Array, k: int) -> int:
	while pai[k] != k:
		pai[k] = pai[pai[k]]
		k = pai[k]
	return k


static func _une(pai: PackedInt32Array, a: int, b: int) -> void:
	var x := _acha(pai, a)
	var y := _acha(pai, b)
	if x != y:
		pai[x] = y


## maior variância (potência na covariância)
static func _eixo(pts: PackedVector3Array) -> Vector3:
	var c := Vector3.ZERO
	for q in pts:
		c += q
	c /= maxi(pts.size(), 1)
	var m := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	for q in pts:
		var e := q - c
		for a in 3:
			for b in 3:
				m[a][b] += e[a] * e[b]
	var ax := Vector3(0.3, 0.2, 1.0).normalized()
	for _k in 80:
		ax = Vector3(m[0][0] * ax.x + m[0][1] * ax.y + m[0][2] * ax.z,
			m[1][0] * ax.x + m[1][1] * ax.y + m[1][2] * ax.z,
			m[2][0] * ax.x + m[2][1] * ax.y + m[2][2] * ax.z).normalized()
	return ax
