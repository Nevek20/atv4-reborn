extends SceneTree
## Ordem de desenho dos efeitos transparentes (poeira, espirro, pedras,
## lascas, fumaça) numa corrida com os 8 carros. O Godot desenha cada
## MultiMesh/partícula inteira de uma vez e ordena as transparentes da mesma
## prioridade pela profundidade do centro da caixa (sorting_use_aabb_center)
## ou da origem do nó. Se duas que se cruzam na tela trocam de ordem de um
## quadro pro outro, a de cima vira a de baixo: pisca. Conta essas trocas.
## Uso: godot --headless --path . --fixed-fps 50 -s res://tests/medir_ordem_fx.gd
## (PASSOS=n, padrão 3000 = 60 s; o jogador é pilotado pela IA)
var PASSOS: int = int(OS.get_environment("PASSOS")) if OS.has_environment("PASSOS") else 3000
var main
var c
var ia
var q := 0
var n := 0
var eu := {}
var antes := {}          # par (id a, id b) -> sinal da ordem no quadro anterior
var antes_c := {}        # o mesmo pela ordem por carro (a correção)
var trocas_c := {}
var trocas := {}         # tipo do par -> trocas
var pares := {}          # tipo do par -> quadros com o par se cruzando
const DESEMPATE := {"Nuvens": 0.0, "Espirro": 0.01, "Pedras": 0.02, "Lascas": 0.03, "Fumaca": -0.01}


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	# mede depois de todos os _process do quadro (câmera, caixas e o
	# efeitos/ordem_fx.gd), que é o que o desenho vê
	var m := Node.new()
	m.name = "MedeOrdem"
	m.process_priority = 2000
	m.set_script(_Mede)
	m.set("dono", self)
	root.add_child.call_deferred(m)


class _Mede extends Node:
	var dono
	func _process(dt: float) -> void:
		if dono:
			dono._medir(dt)


func _physics_process(dt: float) -> bool:
	q += 1
	if main.car == null or main.corrida == null:
		return q > 300
	c = main.corrida
	if q == 20:
		seed(7)
		c.comecar()
		c.comecar()
		c.comecar()
		c.t_conta = 0.0
		ia = c.ia
		eu = {"nome": "Você", "car": main.car, "r": ia.jogador, "desvio": 0.0, "skill": 1.0, "preso": 0.0,
			"re": 0.0, "capotado": 0.0, "repostos": 0, "res": 0}
	if q > 20 and c.estado == c.CORRENDO:
		eu.r = ia.jogador
		eu.vigia = ia.vigia_jogador
		ia._dirigir(eu, main.car, dt)
		n += 1
		if n >= PASSOS:
			_relatorio()
			return true
	return false


func _medir(_dt: float) -> bool:
	if ia == null or c.estado != c.CORRENDO:
		return false
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	if cam == null:
		return false
	var fx: Array = []
	for car in [main.car] + ia.rivais.map(func(y): return y.car):
		if not is_instance_valid(car):
			continue
		for g in car.find_children("*", "GeometryInstance3D", true, false):
			var tipo := _tipo(g)
			if tipo == "" or not g.is_visible_in_tree():
				continue
			var cx := _caixa(g)
			if cx.size == Vector3.ZERO:
				continue
			var r := _retangulo(cam, cx)
			if r.size == Vector2.ZERO:
				continue
			fx.append([g, tipo, car, _profundidade(cam, g, cx), r,
				cam.global_position.distance_to(car.get_global_transform_interpolated().origin) - DESEMPATE.get(tipo, 0.0)])
	if OS.has_environment("DEPURA") and Engine.get_process_frames() % 240 == 0:
		for e in fx:
			print("  dep %-10s %-8s real %.3f ideal %.3f dif %.3f" % [e[2].name, e[1], e[3], e[5], float(e[3]) - float(e[5])])
	for i in fx.size():
		for j in range(i + 1, fx.size()):
			var a: Array = fx[i]
			var b: Array = fx[j]
			if not (a[4] as Rect2).intersects(b[4]):
				continue
			var k := "%s-%s %s" % [a[1], b[1], "mesmo carro" if a[2] == b[2] else "carros diferentes"]
			pares[k] = pares.get(k, 0) + 1
			var id := Vector2i((a[0] as Object).get_instance_id(), (b[0] as Object).get_instance_id())
			var s := signf(float(a[3]) - float(b[3]))
			if antes.has(id) and antes[id] != s and s != 0.0:
				trocas[k] = trocas.get(k, 0) + 1
			antes[id] = s
			var sc := signf(float(a[5]) - float(b[5]))
			if antes_c.has(id) and antes_c[id] != sc and sc != 0.0:
				trocas_c[k] = trocas_c.get(k, 0) + 1
			antes_c[id] = sc
	# par que deixou de se cruzar esquece a ordem (só conta troca em quadros seguidos)
	var vivos := {}
	for i in fx.size():
		for j in range(i + 1, fx.size()):
			vivos[Vector2i((fx[i][0] as Object).get_instance_id(), (fx[j][0] as Object).get_instance_id())] = true
	for id in antes.keys():
		if not vivos.has(id):
			antes.erase(id)
			antes_c.erase(id)
	return false


static func _tipo(g) -> String:
	if g is MultiMeshInstance3D and (g as Node3D).top_level and (g as MultiMeshInstance3D).multimesh != null:
		var mm: MultiMesh = (g as MultiMeshInstance3D).multimesh
		if mm.visible_instance_count == 0:
			return ""
		return String(g.name)
	if g is GPUParticles3D and (g as GPUParticles3D).emitting:
		return "Fumaca"
	return ""


static func _caixa(g) -> AABB:
	var a: AABB
	if g is MultiMeshInstance3D:
		var mm: MultiMesh = (g as MultiMeshInstance3D).multimesh
		a = mm.custom_aabb if mm.custom_aabb.size != Vector3.ZERO else mm.get_aabb()
	else:
		a = (g as GPUParticles3D).visibility_aabb
	return (g as Node3D).global_transform * a


## o que o Godot usa pra ordenar (forward clustered, perspectiva): distância
## da câmera ao centro da caixa (ou à origem do nó), menos o sorting_offset
static func _profundidade(cam: Camera3D, g, cx: AABB) -> float:
	var p: Vector3 = cx.get_center() if (g as GeometryInstance3D).sorting_use_aabb_center else (g as Node3D).global_position
	return cam.global_position.distance_to(p) - (g as GeometryInstance3D).sorting_offset


func _retangulo(cam: Camera3D, cx: AABB) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var algum := false
	for k in 8:
		var p := cx.get_endpoint(k)
		if cam.is_position_behind(p):
			continue
		var s := cam.unproject_position(p)
		lo = lo.min(s)
		hi = hi.max(s)
		algum = true
	if not algum:
		return Rect2()
	var r := Rect2(lo, hi - lo).intersection(Rect2(Vector2.ZERO, root.get_viewport().get_visible_rect().size))
	return r


func _relatorio() -> void:
	print("medir_ordem_fx: %d passos" % n)
	var ks: Array = pares.keys()
	ks.sort()
	var tot := 0
	var tot_c := 0
	for k in ks:
		var t: int = trocas.get(k, 0)
		tot += t
		tot_c += int(trocas_c.get(k, 0))
		print("  %-40s cruzando %6d quadros  trocas de ordem %5d   pelo carro %5d" % [k, pares[k], t, trocas_c.get(k, 0)])
	print("  total de trocas: %d (%.1f por segundo); ordenando pelo carro: %d" % [tot, tot / (n / 50.0), tot_c])
