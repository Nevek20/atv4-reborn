extends SceneTree
## Confere a tremida das rodas no chão (car.gd, 0x202760): gerador igual ao do
## jogo, amplitude dentro de min(1, WheelJitter*0.06392613*v)*0.0375, traseira
## direita igual à esquerda, sorteio a 50 Hz. Carro (Renegade) acelerando no
## plano por 8 s. Uso: godot --headless --path . -s res://tests/teste_tremida.gd

const Car := preload("res://carro/car.gd")
const Main := preload("res://main.gd")

var car
var falhas := 0
var t := 0.0
var maxj := {}          # faixa de 5 mph -> maior |tremida| visto
var trocas := 0         # quantas vezes a tremida mudou (pra medir a frequência)
var ultimo := 0.0


func _initialize() -> void:
	# gerador: x = x*31415821 + 1 mod 2^30 (valores calculados em Python)
	var x := 12345
	var esperado := [207511782, 381247407, 16588260, 728775829, 96258450]
	for e in esperado:
		x = (x * 31415821 + 1) & 0x3FFFFFFF
		if x != e:
			falhas += 1
			print("gerador FALHOU: %d != %d" % [x, e])
	var chao := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000, 2, 4000)
	cs.shape = box
	cs.position = Vector3(0, -1, 0)
	chao.add_child(cs)
	root.add_child(chao)
	var v: Dictionary = Main.VEHICLES[0]
	car = Car.new()
	car.asset_dir = v.dir
	car.data_files = ["res://data/vehicles/buggy_base.xml", v.data]
	car.points_file = v.points
	car.vehicle_id = v.id
	root.add_child(car)
	car.test_input = {"thr": 1.0, "brk": 0.0, "steer": 0.0}


func _physics_process(dt: float) -> bool:
	if car == null or not car.is_inside_tree():
		return false
	if t == 0.0:
		car.reset_to(Vector3(0, 1.0, -1500), 0.0)
		# ordem do jogo FL, RL, FR, RR; esquerda do jogo = +X no Godot
		var esperado := [[true, true], [false, true], [true, false], [false, false]]
		for k in 4:
			var w: Dictionary = car.wheels[car.jit_order[k]]
			if w.front != esperado[k][0] or (w.px > 0.0) != esperado[k][1]:
				falhas += 1
				print("jit_order[%d] é a roda errada (px %.3f, frente %s)" % [k, w.px, w.front])
	t += dt
	var o: Array = car.jit_order
	var spd: float = car.spd_ground
	var lim := minf(car.surface_jitter * car.JIT_K * spd, 1.0) * 0.0375 + 1e-6
	for i in o:
		var w: Dictionary = car.wheels[i]
		if absf(w.jit) > lim:
			falhas += 1
			print("t %.2f roda %d tremida %.4f acima do limite %.4f" % [t, i, w.jit, lim])
		if not w.hit and w.jit != 0.0:
			falhas += 1
			print("t %.2f roda %d no ar com tremida" % [t, i])
	if car.wheels[o[3]].jit != car.wheels[o[1]].jit:
		falhas += 1
		print("t %.2f traseira direita != esquerda" % t)
	var j: float = car.wheels[o[0]].jit
	if j != ultimo:
		trocas += 1
		ultimo = j
	var faixa := int(spd * 2.2374146 / 5.0) * 5
	maxj[faixa] = maxf(maxj.get(faixa, 0.0), absf(j))
	if t >= 8.0:
		print("mph   maior |tremida| (mm)   limite do jogo (mm)")
		var ks := maxj.keys()
		ks.sort()
		for k in ks:
			var vmax: float = (k + 5) / 2.2374146
			print("%3d-%-3d  %6.1f   %6.1f" % [k, k + 5, maxj[k] * 1000.0,
				minf(0.3 * car.JIT_K * vmax, 1.0) * 37.5])
		print("trocas da tremida: %.1f por segundo (jogo: 50)" % (trocas / t))
		print("teste_tremida: %s" % ("ok" if falhas == 0 else "%d falhas" % falhas))
		quit(1 if falhas > 0 else 0)
		return true
	return false
