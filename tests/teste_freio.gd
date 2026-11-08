extends SceneTree
## Confere patinada por roda, ABS e roda travando (car.gd, 0x2101e0 /
## 0x20eb98 / 0x210908; ABS e trava leem a patinada medida 0x600, w.sr,
## que vem do giro da roda), no Renegade num plano: acelera até ~135 km/h e
## freia com o volante todo virado (rodas no limite da elipse; virando só
## metade elas não chegam no limite).
##  1. com o ABS do XML (Enable_ABS = true nos buggies): o ABS solta alguma
##     roda e a trava nunca age (só age em roda sem ABS soltando);
##  2. sem ABS: alguma roda chega em -1 (travada) e a força dela fica contra
##     o deslize do contato.
## Uso: godot --headless --path . -s res://tests/teste_freio.gd

const Car := preload("res://carro/car.gd")
const Main := preload("res://main.gd")

var car
var t := 0.0
var rodada := 0                # 0 com ABS, 1 sem
var falhas := 0
var abs_viu := false
var min_slip := 0.0
var travou := false
var pior_cos := -1.0           # força travada . deslize (tem que dar ~ -1)


func _initialize() -> void:
	var chao := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000, 2, 4000)
	cs.shape = box
	cs.position = Vector3(0, -1, 0)
	chao.add_child(cs)
	root.add_child(chao)
	_novo()


func _novo() -> void:
	var v: Dictionary = Main.VEHICLES[0]
	car = Car.new()
	car.asset_dir = v.dir
	car.data_files = ["res://data/vehicles/buggy_base.xml", v.data]
	car.points_file = v.points
	car.vehicle_id = v.id
	car.suspension = false
	root.add_child(car)
	car.test_input = {"thr": 0.0, "brk": 0.0, "steer": 0.0}
	t = 0.0


func _physics_process(dt: float) -> bool:
	if car == null or not car.is_inside_tree():
		return false
	if t == 0.0:
		car.reset_to(Vector3(0, 1.0, -1500), 0.0)
		if rodada == 1:
			car.P.abs_on = false
	t += dt
	var ti = car.test_input
	ti.thr = 1.0 if t > 0.5 and t < 5.5 else 0.0
	ti.brk = 1.0 if t >= 5.5 else 0.0
	ti.steer = 1.0 if t >= 5.5 else 0.0
	if t >= 5.5:
		var v: Vector3 = car.linear_velocity
		var b: Basis = car.global_transform.basis
		var v_f := v.dot(b.z)
		var v_l := v.dot(b.x)
		for w in car.wheels:
			min_slip = minf(min_slip, w.sr)
			abs_viu = abs_viu or w.abs
			if w.sr < car.TRAVA_INI and not w.abs and v.length() > car.TRAVA_MPH * car.MPH_G:
				travou = true
			if w.sr <= -1.0 + 1e-6 and not w.abs and v.length() > car.TRAVA_MPH * car.MPH_G:
				travou = true
				var f := Vector2(w.fx, w.fz)
				var d := Vector2(v_l, -v_f * w.sr)
				if f.length() > 1.0 and d.length() > 0.1:
					pior_cos = maxf(pior_cos, f.normalized().dot(d.normalized()))
	if t > 9.0:
		_fim()
	return false


func _fim() -> void:
	if rodada == 0:
		var ok: bool = abs_viu and not travou
		if not ok:
			falhas += 1
		print("com ABS: ABS soltou %s, menor patinada %.3f, travou %s  %s" % [abs_viu, min_slip, travou,
			"ok" if ok else "FALHOU"])
		car.queue_free()
		rodada = 1
		abs_viu = false
		min_slip = 0.0
		travou = false
		pior_cos = -1.0
		_novo()
		return
	var ok2: bool = travou and pior_cos < -0.99
	if not ok2:
		falhas += 1
	print("sem ABS: menor patinada %.3f, travou %s, força x deslize (cos) %.4f  %s" % [min_slip, travou,
		pior_cos, "ok" if ok2 else "FALHOU"])
	print("teste_freio: %s" % ("ok" if falhas == 0 else "%d falhas" % falhas))
	quit(1 if falhas else 0)
