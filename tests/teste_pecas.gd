extends SceneTree
## Confere as peças da suspensão contra o jogo: matrizes das peças tiradas da
## RAM dos save states (tests/ref_ram_pecas.json: linhas do jogo, 4ª linha =
## translação, frame do modelo), com o mesmo curso de cada roda. Carros: os
## que têm save state (Renegade, Sphinx, Inferno, Bulldog, Phantom, Storm e
## o truck Goliath: frames, freios e eixo rígido, suspension_visual.pose_truck).
## Uso: godot --headless --path . -s res://tests/teste_pecas.gd

const Car := preload("res://carro/car.gd")
const Main := preload("res://main.gd")
const TOL := 1e-3

var falhas := 0
var total := 0
var lado_errado := 0
var ref := {}
var carros := {}
var frames := 0


func _initialize() -> void:
	ref = JSON.parse_string(FileAccess.get_file_as_string("res://tests/ref_ram_pecas.json"))
	for nome in ref:
		var v: Dictionary = Main.frota()[int(ref[nome].veh)]
		var c = Car.new()
		c.asset_dir = v.dir
		c.data_files = Main.dados(v)
		c.points_file = v.points
		c.vehicle_id = v.id
		root.add_child(c)          # o _ready roda no 1º quadro
		carros[nome] = c


func _process(_dt: float) -> bool:
	frames += 1
	if frames < 2:
		return false
	for nome in ref:
		_conferir(nome, carros[nome], ref[nome])
	print("teste_pecas: %s (%d de %d matrizes batem com a RAM, tolerância %s m)%s" % [
		"ok" if falhas == 0 and total > 0 and lado_errado == 0 else "FALHA", total - falhas, total, TOL,
		"" if lado_errado == 0 else ", %d cantos com a roda da física do lado errado" % lado_errado])
	quit(1 if falhas > 0 or total == 0 or lado_errado > 0 else 0)
	return true


func _xf(linhas: Array) -> Transform3D:
	var r := []
	for l in linhas:
		r.append(Vector3(l[0], l[1], l[2]))
	return Transform3D(Basis(r[0], r[1], r[2]), r[3])


func _cmp(nome: String, a: Transform3D, b: Transform3D, so_pos := false) -> void:
	total += 1
	var e := (a.origin - b.origin).length()
	if not so_pos:
		for i in 3:
			e = maxf(e, (a.basis[i] - b.basis[i]).length())
	var ok := e < TOL
	if not ok:
		falhas += 1
	print("  %-11s erro %.6f %s" % [nome, e, "ok" if ok else "FALHOU"])


func _conferir(nome: String, c, r: Dictionary) -> void:
	print("== %s" % nome)
	var susp = c.susp_vis
	if susp == null:
		print("  sem suspension_visual (faltam assets?)")
		falhas += 1
		return
	var p: Dictionary = r.pecas
	for k in susp.corners:
		var cn: String = ("F" if k.front else "R") + ("L" if k.left else "R")
		# o canto (frame do jogo) tem que pegar a roda da física do mesmo lado:
		# esquerda do jogo = +X no Godot (car.gd, espelho)
		var w: Dictionary = k.wheel
		if w.left != k.left or w.front != k.front or (w.px > 0.0) != k.left:
			lado_errado += 1
			print("  %-11s roda da física do lado errado (px %.3f)" % [cn, w.px])
		var x: float = r.curso[cn]
		var ps: Dictionary = susp.pose(k, x, 0.0)
		_cmp("Frame_" + cn, ps.frame, _xf(p["Frame_" + cn].linhas))
		if p.has("Brake_" + cn):
			_cmp("Brake_" + cn, ps.brake, _xf(p["Brake_" + cn].linhas))
		_cmp("Wheel_" + cn, Transform3D(Basis(), ps.hub), _xf(p["Wheel_" + cn].linhas), true)
		if p.has("ShockF_" + cn):
			_cmp("ShockF_" + cn, ps.shock, _xf(p["ShockF_" + cn].linhas))
		if p.has("Chamber_" + cn):
			_cmp("Chamber_" + cn, ps.chamber, _xf(p["Chamber_" + cn].linhas))
			_cmp("Piston_" + cn, ps.piston, _xf(p["Piston_" + cn].linhas))
	if not susp.truck.is_empty():
		_conferir_truck(c, susp, r)
	if p.has("Spare"):
		if susp.spares.is_empty():
			total += 1
			falhas += 1
			print("  Spare       FALTOU (sem estepe)")
		else:
			_cmp("Spare", susp.spares[0], _xf(p.Spare.linhas))


## trucks: peças do eixo rígido (pose_truck) e as rodas, que nesses mapas são
## as do rally (WHEEL + x; o car.gd põe o pivô em (px, y0 + x, pz))
func _conferir_truck(c, susp, r: Dictionary) -> void:
	var p: Dictionary = r.pecas
	var x: Dictionary = r.curso
	var ps: Dictionary = susp.pose_truck({"FL": x.FL, "FR": x.FR, "RL": x.RL, "RR": x.RR}, 0.0)
	for nome in ["LeftFrame", "RightFrame", "FrontLeftBrake", "FrontRightBrake", "RearAxle", "RearFreeAxle"]:
		if p.has(nome):
			if ps.has(nome):
				_cmp(nome, ps[nome], _xf(p[nome].linhas))
			else:
				total += 1
				falhas += 1
				print("  %-11s FALTOU (peça não montada)" % nome)
	for w in c.wheels:
		var cn: String = ("F" if w.front else "R") + ("L" if w.left else "R")
		if p.has("Wheel_" + cn):
			var hub: Vector3 = c.jogo(Vector3(w.px, w.y0 + float(x[cn]), w.pz))
			_cmp("Wheel_" + cn, Transform3D(Basis(), hub), _xf(p["Wheel_" + cn].linhas), true)
