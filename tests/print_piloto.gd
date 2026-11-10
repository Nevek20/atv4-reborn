extends SceneTree
## Prints do piloto sem a carroceria (volante e painel ficam), pra ver braço e
## mão no volante. Cada carro sai em <saida>_<n>_<vista>.png.
## Uso (precisa de tela; na nuvem xvfb-run -a ... --rendering-driver opengl3):
##   godot --path . -s res://tests/print_piloto.gd -- /tmp/pil    (VEHS=0,25 só esses;
##   VISTAS=lado,janela,frente,cima,olho,maos,maos_cima,maos_lado; VIRA=0.5 volante virado, + = esquerda;
##   CORPO=1 deixa a carroceria)

const Car := preload("res://carro/car.gd")
const Main := preload("res://main.gd")

# câmera a partir do banco do piloto (car.banco(), frame do jogo: x < 0 =
# esquerda, o lado do piloto), [posição, alvo]
const VISTAS := {
	"lado": [Vector3(-2.3, 0.45, 0.3), Vector3(0.0, 0.4, 0.3)],
	"janela": [Vector3(-3.2, 0.75, 0.3), Vector3(0.0, 0.55, 0.3)],    # de fora, com a carroceria (CORPO=1)
	"frente": [Vector3(-0.8, 0.85, 1.9), Vector3(0.0, 0.4, 0.25)],
	"cima": [Vector3(-0.3, 1.9, 0.7), Vector3(0.0, 0.35, 0.3)],
	"olho": [Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 0.0)],   # câmera do piloto (car.first_person_xf)
}
# de perto, a partir do centro do volante (car.sw_centro, frame do jogo)
const PERTO := {
	"maos": [Vector3(-0.55, 0.25, 0.55), Vector3(0.0, -0.05, -0.12)],
	"maos_cima": [Vector3(-0.15, 0.6, 0.15), Vector3(0.0, -0.05, -0.12)],
	"maos_lado": [Vector3(-0.8, 0.05, -0.1), Vector3(0.0, -0.05, -0.15)],
}

var saida := "/tmp/piloto"
var fila := []          # [indice, car]
var vistas: PackedStringArray = ["lado", "frente", "cima"]
var car = null
var idx := -1
var vi := 0
var espera := 0
var cam: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		saida = args[0]
	if OS.has_environment("VISTAS"):
		vistas = OS.get_environment("VISTAS").split(",", false)
	var so: Array = []
	if OS.has_environment("VEHS"):
		for x in OS.get_environment("VEHS").split(","):
			so.append(int(x))
	var frota: Array = Main.frota()
	for i in frota.size():
		if (so.is_empty() and not frota[i].get("extra", false)) or i in so:
			fila.append(i)
	var sol := DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-50, 30, 0)
	root.add_child(sol)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.62, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	root.add_child(env)
	cam = Camera3D.new()
	cam.fov = 40.0
	root.add_child(cam)
	cam.current = true


func _process(_dt: float) -> bool:
	if car == null:
		if fila.is_empty():
			return true
		idx = fila.pop_front()
		var v: Dictionary = Main.frota()[idx]
		car = Car.new()
		Main.configurar(car, v)
		car.suspension = false
		root.add_child(car)
		car.set_physics_process(false)
		car.freeze = true             # sem chão: senão cai entre a mira e o print
		car.test_input = {"thr": 0.0, "brk": 0.0, "steer": float(OS.get_environment("VIRA")) if OS.has_environment("VIRA") else 0.0}
		vi = 0
		espera = 3
		return false
	if OS.has_environment("VIRA"):
		car.rider_s = float(OS.get_environment("VIRA"))
	if OS.get_environment("CORPO") != "1" and car.body_mi:
		car.body_mi.visible = false
	if espera > 0:
		_mira(vistas[vi])
		espera -= 1
		return false
	var img := root.get_texture().get_image()
	img.save_png("%s_%02d_%s.png" % [saida, idx, vistas[vi]])
	vi += 1
	if vi >= vistas.size():
		car.free()
		car = null
	else:
		espera = 2
	return false


func _mira(v: String) -> void:
	if v == "olho":
		cam.global_transform = car.first_person_xf()
		return
	var b: Vector3 = car.banco()
	var p: Array = VISTAS.get(v, [])
	if PERTO.has(v):
		b = car.sw_centro()
		p = PERTO[v]
	var mr: Transform3D = car.model_root.global_transform
	var pos: Vector3 = mr * (car.model_offset + b + p[0])
	var alvo: Vector3 = mr * (car.model_offset + b + p[1])
	cam.global_position = pos
	cam.look_at(alvo, Vector3.UP)
