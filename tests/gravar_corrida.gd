extends SceneTree
## Prévia da largada da corrida (pista/corrida.gd): começa a corrida, mostra a
## câmera de introdução inteira, acelera em pulsos na contagem (o carro preso
## não anda) e sai no VAI. Rodar com o Movie Maker (grava o áudio junto):
##   godot --path . --write-movie corrida.avi --fixed-fps 30 -s res://tests/gravar_corrida.gd
## (na nuvem: xvfb-run -a ... --rendering-driver opengl3). DEPOIS = segundos
## acelerando depois do VAI (padrão 6). PULAR=1 aperta o Enter no meio da intro.

var main
var t := 0.0
var t_vai := -1.0
var comecou := false
var pulou := false


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _process(dt: float) -> bool:
	if main.car == null or main.corrida == null:
		return false
	var c = main.corrida
	var car = main.car
	t += dt
	if not comecou:
		if t < 0.5:
			return false
		c.comecar()
		comecou = true
		t = 0.0
	if OS.has_environment("PULAR") and not pulou and t > 5.0 and c.estado == c.INTRO:
		c.comecar()
		pulou = true
	var thr := 0.0
	if c.estado == c.INTRO:
		thr = 1.0 if fmod(t, 3.0) > 2.2 else 0.0          # umas aceleradas na intro
	elif c.estado == c.CONTANDO:
		thr = 1.0 if c.t_conta < 1.0 or fmod(t, 0.8) < 0.4 else 0.0
	elif c.estado == c.CORRENDO:
		if t_vai < 0.0:
			t_vai = t
		thr = 1.0
	car.test_input = {"thr": thr, "brk": 0.0, "steer": 0.0}
	if OS.has_environment("CHECA_NAN"):
		_checa(main, t)
	if int(t * 2.0) != int((t - dt) * 2.0):
		print("%.1f s  %s  rpm %4.0f  %3.0f km/h  marcha %s" % [t, ["LIVRE", "INTRO", "CONTANDO", "CORRENDO", "CHEGOU"][c.estado], car.rpm, car.linear_velocity.length() * 3.6, car.gear_label()])
	return t_vai >= 0.0 and t - t_vai > float(OS.get_environment("DEPOIS") if OS.has_environment("DEPOIS") else "6")


var _achou := {}

func _checa(n: Node, tt: float) -> void:
	if n is Node3D:
		var tr: Transform3D = n.transform
		if not (tr.origin.is_finite() and tr.basis.x.is_finite() and tr.basis.y.is_finite() and tr.basis.z.is_finite()):
			var k := str(n.get_path())
			if not _achou.has(k):
				_achou[k] = true
				print("NaN %.2f s: %s  %s" % [tt, k, tr])
			return
	for f in n.get_children():
		_checa(f, tt)
