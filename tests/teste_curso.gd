extends SceneTree
## Curso parado x RAM: cada carro dos save states parados (tests/
## ref_ram_pecas.json: 6 buggies, Goliath e Buccaneer) assenta 4 s num plano
## e o curso de cada roda tem que bater com o W+0xe8 da RAM. No jogo o passo
## é integra (0x2484c8) -> contato (0x248768) -> mola (0x248a80) -> pneus, então
## o x guardado (e desenhado) é o do contato; antes o remake integrava no fim
## do passo e o x ficava f/m·dt² mais baixo (1 a 4 cm). Os save states são na
## largada do RX01, quase plana: a folga cobre a inclinação.
## Uso: godot --headless --path . -s res://tests/teste_curso.gd

const Car := preload("res://carro/car.gd")
const Main := preload("res://main.gd")
const TOL := 0.006                      # m
# peças compradas nos save states (o resto é de fábrica): o Sphinx do b.p2s
# tem massa 1.0 t (BodyMass L2) e curso máximo 0.75 (Suspension no máximo)
const TUNE := {"sphinx": {"mass": 1.0, "susp": 1.0}}

var ref := {}
var nomes := []
var i := -1
var car
var t := 0.0
var falhas := 0


func _initialize() -> void:
	ref = JSON.parse_string(FileAccess.get_file_as_string("res://tests/ref_ram_pecas.json"))
	nomes = ref.keys()
	var chao := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 2, 400)
	cs.shape = box
	cs.position = Vector3(0, -1, 0)
	chao.add_child(cs)
	root.add_child(chao)
	_proximo()


func _proximo() -> void:
	if car:
		car.queue_free()
	i += 1
	if i >= nomes.size():
		print("teste_curso: %s" % ("ok" if falhas == 0 else "%d falhas" % falhas))
		quit(1 if falhas else 0)
		return
	var v: Dictionary = Main.frota()[int(ref[nomes[i]].veh)]
	car = Car.new()
	car.asset_dir = v.dir
	car.data_files = Main.dados(v)
	car.points_file = v.points
	car.vehicle_id = v.id
	car.suspension = false
	car.melhorias = false
	car.tune_override = TUNE.get(nomes[i], v.get("tune", {}))
	root.add_child(car)
	car.test_input = {"thr": 0.0, "brk": 0.0, "steer": 0.0}
	car.reset_to(Vector3(0, 1.5, 0), 0.0)
	t = 0.0


func _physics_process(dt: float) -> bool:
	if car == null or not car.is_inside_tree():
		return false
	t += dt
	if t > 4.0:
		var r: Dictionary = ref[nomes[i]].curso
		var s := ""
		var pior := 0.0
		for w in car.wheels:
			var k: String = ("F" if w.front else "R") + ("L" if w.left else "R")
			pior = maxf(pior, absf(w.x - r[k]))
			s += "  %s %.3f/%.3f" % [k, w.x, r[k]]
		var ok := pior < TOL
		falhas += 0 if ok else 1
		print("%-9s%s  maior diferença %.1f cm  %s" % [nomes[i], s, pior * 100.0, "ok" if ok else "FALHOU"])
		_proximo()
	return false
