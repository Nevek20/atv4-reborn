extends SceneTree
## Confere a mão (espelho): o jogo é mão esquerda, o Godot mão direita, e o
## car.gd põe tudo do jogo embaixo do nó espelho. Pega lado trocado e
## conversão esquecida ou feita duas vezes. Nos 6 carros da RAM
## (tests/ref_ram_pecas.json):
##  A. carroceria, volante e olho do piloto: ponto do modelo do jogo no
##     visual = car.corpo() da física; volante na esquerda do jogo (+X)
##  B. balança, freio e amortecedores: nó na tela = espelho * pose()
##  C. malha da roda espelhada do mesmo lado que na RAM (Wheel_* linha 0)
##  D. roda da física = cubo do visual com curso 0 (inclusive y)
##  E. esterço + (esquerda): rodas da frente, freios e volante viram pra +X
## E mais:
##  F. sem suspensão (car.suspension = false) o pivô da roda fica em cima
##     da roda da física
##  G. largada (main.gd SPAWN_XZ/SPAWN_YAW) = média dos save states
## Uso: godot --headless --path . -s res://tests/teste_mao.gd

const Car := preload("res://carro/car.gd")
const Main := preload("res://main.gd")
const Terrain := preload("res://pista/terrain.gd")
const PECAS := ["frame", "brake", "shock", "chamber", "piston"]

var carros := []                 # [nome, carro]
var sem_susp
var frames := 0
var falhas := 0
var ref_pecas: Dictionary
var ref_chao: Dictionary


func _initialize() -> void:
	ref_pecas = JSON.parse_string(FileAccess.get_file_as_string("res://tests/ref_ram_pecas.json"))
	ref_chao = JSON.parse_string(FileAccess.get_file_as_string("res://tests/ref_ram_chao.json"))
	for nome in ref_pecas:
		# trucks (índice depois dos buggies em Main.frota()) não têm balança:
		# as peças deles o teste_pecas confere
		if int(ref_pecas[nome].veh) < Main.VEHICLES.size():
			carros.append([nome, _carro(int(ref_pecas[nome].veh), true)])
	sem_susp = _carro(0, false)


func _carro(i: int, susp: bool):
	var v: Dictionary = Main.VEHICLES[i]
	var c = Car.new()
	c.asset_dir = v.dir
	c.data_files = ["res://data/vehicles/buggy_base.xml", v.data]
	c.points_file = v.points
	c.vehicle_id = v.id
	c.suspension = susp
	c.freeze = true               # sem chão: fica parado onde nasceu
	root.add_child(c)
	return c


func _falha(s: String) -> void:
	falhas += 1
	print("  FALHOU: " + s)


func _process(_dt: float) -> bool:
	frames += 1
	# espera uns passos de física: o olho usa a posição INTERPOLADA do modelo,
	# que no 3º quadro às vezes ainda estava 1 passo atrás (falhava ~1 em 2
	# vezes no Bulldog, 8.5 cm, sem nada errado no carro)
	if frames < 12:
		return false
	for p in carros:
		_conferir(p[0], p[1])
	_sem_suspensao(sem_susp)
	_largada()
	print("teste_mao: %s" % ("ok" if falhas == 0 else "%d falhas" % falhas))
	quit(1 if falhas else 0)
	return true


func _conferir(nome: String, c) -> void:
	var cx: Transform3D = c.global_transform
	var n0 := falhas
	if c.susp_vis == null or c.susp_vis.corners.size() != 4:
		_falha("%s sem suspension_visual (faltam assets?)" % nome)
		return
	# A
	var vis: Vector3 = c.model_root.global_transform * (c.model_offset + c.SW_CENTER)
	var fis: Vector3 = cx * c.corpo(c.SW_CENTER)
	if vis.distance_to(fis) > 0.001:
		_falha("%s carroceria fora do frame do jogo (%.3f m)" % [nome, vis.distance_to(fis)])
	if (cx.affine_inverse() * vis).x <= 0.0:
		_falha("%s volante fora da esquerda do jogo (+X)" % nome)
	var olho_d: float = c.driver_eye().distance_to(cx * c.corpo(c.DRIVER_EYE))
	if olho_d > 0.001:
		_falha("%s olho do piloto fora do lugar (%.4f m)" % [nome, olho_d])
	# B
	var base: Transform3D = cx * Transform3D(Basis.from_scale(c.ESPELHO), Vector3.ZERO) \
		* Transform3D(Basis(), c.model_offset)
	for k in c.susp_vis.corners:
		var w: Dictionary = k.wheel
		var cn: String = ("F" if k.front else "R") + ("L" if k.left else "R")
		var ps: Dictionary = c.susp_vis.pose(k, clampf(w.x, w.min, w.max) + w.jit, 0.0)
		for nm in PECAS:
			var mi = k.get(nm)
			if mi == null or not ps.has(nm):
				continue
			var e: Transform3D = base * ps[nm]
			var g: Transform3D = mi.global_transform
			var err := g.origin.distance_to(e.origin)
			for i in 3:
				err = maxf(err, (g.basis[i] - e.basis[i]).length())
			if err > 0.001:
				_falha("%s %s de %s fora do frame do jogo (%.3f)" % [nome, nm, cn, err])
		# C
		var roda: Node3D = w.spin_node.get_child(0)
		var gj: Transform3D = c.espelho.global_transform.affine_inverse() * roda.global_transform
		var ram_x: float = ref_pecas[nome].pecas["Wheel_" + cn].linhas[0][0]
		if signf(gj.basis.x.x) != signf(ram_x):
			_falha("%s roda %s espelhada %+.0f, RAM %+.0f" % [nome, cn, gj.basis.x.x, ram_x])
		# D
		var hv: Vector3 = (c.model_offset + c.susp_vis.pose(k, 0.0, 0.0).hub) * c.ESPELHO
		var hf := Vector3(w.px, w.y0, w.pz)
		if hv.distance_to(hf) > 0.001:
			_falha("%s roda %s física x visual %.3f m" % [nome, cn, hv.distance_to(hf)])
	# E
	c.steer = 0.5
	c.rider_s = 0.5
	c._update_visuals(0.0, 0.0)
	for k in c.susp_vis.corners:
		if not k.front:
			continue
		var fz: Vector3 = k.wheel.pivot.global_transform.basis.z
		if fz.dot(cx.basis.x) <= 0.0:
			_falha("%s roda da frente vira pra direita com esterço + (esquerda)" % nome)
		if k.brake and (k.brake.global_transform.basis.z - fz).length() > 0.001:
			_falha("%s freio e roda viram pra lados diferentes" % nome)
	if c.sw_pivot:
		# topo do aro anda pra esquerda (+X) virando à esquerda
		var u: Vector3 = c.SW_AXIS.normalized()
		var topo: Vector3 = (Vector3.UP - u * Vector3.UP.dot(u)).normalized() * 0.2
		var g0: Vector3 = c.sw_pivot.get_parent().global_transform * (c.sw_pivot.position + topo)
		var g1: Vector3 = c.sw_pivot.global_transform * topo
		if (g1 - g0).dot(cx.basis.x) <= 0.0:
			_falha("%s volante gira pra direita com esterço + (esquerda)" % nome)
	c.steer = 0.0
	c.rider_s = 0.0
	c._update_visuals(0.0, 0.0)
	print("%-9s %s" % [nome, "ok" if falhas == n0 else "FALHOU"])


func _sem_suspensao(c) -> void:
	var cx: Transform3D = c.global_transform
	var n0 := falhas
	if c.susp_vis != null:
		_falha("suspension = false ainda montou o suspension_visual")
	for w in c.wheels:
		var x: float = clampf(w.x, w.min, w.max) + w.jit
		var e: Vector3 = cx * Vector3(w.px, w.y0 + x, w.pz)
		if w.pivot.global_position.distance_to(e) > 0.001:
			_falha("sem suspensão: roda %s%s fora da física (%.3f m)" % [
				"F" if w.front else "R", "L" if w.left else "R", w.pivot.global_position.distance_to(e)])
	print("%-9s %s" % ["sem susp", "ok" if falhas == n0 else "FALHOU"])


func _largada() -> void:
	var yaw := 0.0
	var centro := Vector2.ZERO
	for n in ref_chao.carros:
		var rs := []
		for r in ref_chao.carros[n]:
			rs.append(Terrain.do_jogo(Vector3(r.x, r.y, r.z)))
		var fw: Vector3 = (rs[0] + rs[2] - rs[1] - rs[3]) * 0.5
		yaw += rad_to_deg(atan2(fw.x, fw.z))
		var m: Vector3 = (rs[0] + rs[1] + rs[2] + rs[3]) * 0.25
		centro += Vector2(m.x, m.z)
	yaw /= ref_chao.carros.size()
	centro /= ref_chao.carros.size()
	var ok := absf(yaw - Main.SPAWN_YAW) < 0.5 and centro.distance_to(Main.SPAWN_XZ) < 0.2
	if not ok:
		_falha("largada %s %.1f° x RAM %s %.1f°" % [Main.SPAWN_XZ, Main.SPAWN_YAW, centro, yaw])
	print("largada   %s (RAM %.1f°, (%.1f, %.1f))" % ["ok" if ok else "FALHOU", yaw, centro.x, centro.y])
