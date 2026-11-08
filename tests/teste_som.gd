extends SceneTree
## Som do motor (motor_som.gd): em cada buggy e truck (+ o bônus), varre o rpm do jogo com o
## acelerador solto, pela metade e todo, e confere que tocam no máximo 4 loops
## (2 vizinhos de cada camada), que a potência somada dá 1 (crossfade sem
## buraco nem estouro), que o tom fica perto de 1 nos rpm gravados e que a
## marcha lenta do jogo toca a lenta.wav no tom dela.
## Uso: godot --headless --path . -s res://tests/teste_som.gd
const Car := preload("res://carro/car.gd")
const Main := preload("res://main.gd")

var i := -1
var car = null
var falhas := 0
var feitos := 0
var vistos := {}


func _process(_dt: float) -> bool:
	if car != null:
		_conferir()
		car.free()
		car = null
	i += 1
	var frota: Array = Main.frota()
	while i < frota.size() and vistos.has(frota[i].get("som", frota[i].id)):
		i += 1
	if i >= frota.size():
		print("teste_som: %s (%d carros, %d falhas)" % ["ok" if falhas == 0 and feitos > 0 else "FALHA", feitos, falhas])
		return true
	var v: Dictionary = frota[i]
	vistos[v.get("som", v.id)] = true
	car = Car.new()
	car.asset_dir = v.dir
	car.data_files = Main.dados(v)
	car.points_file = v.points
	car.vehicle_id = v.id
	car.som_pasta = v.get("som", "")
	car.suspension = false
	root.add_child(car)
	car.set_physics_process(false)
	car.set_process(false)
	return false


func _conferir() -> void:
	var v: Dictionary = Main.frota()[i]
	var som = car.som
	if som == null:
		print("%-12s sem som" % v.name)
		falhas += 1
		return
	feitos += 1
	var ruim := ""
	var max_tocando := 0
	var pior_pot := 0.0
	var pitch_lo := 9.0
	var pitch_hi := 0.0
	for carga in [0.0, 0.5, 1.0]:
		for rj in range(1000, 8501, 125):
			som.atualizar(float(rj), carga, 10.0)
			var t: Array = som.tocando()
			max_tocando = maxi(max_tocando, t.size())
			var pot := 0.0
			for x in t:
				pot += x[1] * x[1]
				pitch_lo = minf(pitch_lo, x[2])
				pitch_hi = maxf(pitch_hi, x[2])
			pior_pot = maxf(pior_pot, absf(pot - 1.0))
	# marcha lenta do jogo, sem acelerar: lenta.wav no tom 1
	som.atualizar(1000.0, 0.0, 10.0)
	var t0: Array = som.tocando()
	var lenta_ok: bool = t0.size() == 1 and t0[0][0] == "lenta.wav" and absf(t0[0][2] - 1.0) < 0.01
	if max_tocando > 4:
		ruim += " %d loops juntos" % max_tocando
	if pior_pot > 0.02:
		ruim += " potência fora %.3f" % pior_pot
	if not lenta_ok:
		ruim += " lenta errada %s" % str(t0)
	if ruim != "":
		falhas += 1
	print("%-12s %-28s lenta %4.0f  corte %4.0f rpm real  loops %2d+%2d  tom %.2f-%.2f  %s" % [
		v.name, som.pasta.get_file(), som.lenta_real, som.corte_real, som._on.size(), som._off.size(),
		pitch_lo, pitch_hi, "ok" if ruim == "" else "FALHA" + ruim])
