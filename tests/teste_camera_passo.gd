extends SceneTree
## Confere que a câmera de órbita (game_camera.gd, passos de 1/60 s) não vai e
## volta quando o quadro não bate certinho com o passo: carro a velocidade
## constante numa reta e quadros de 1/60 s com uma variação pequena (monitor
## de 60 Hz), o que dá quadros com 0 e com 2 passos. Com a câmera certa a
## distância câmera -> carro fica parada; antes do conserto ela pulava de um
## quadro pro outro (mais quanto maior a velocidade).
## Uso: godot --headless --path . -s res://tests/teste_camera_passo.gd

const GameCamera := preload("res://camera/game_camera.gd")
const CAM_XML := "res://data/cameras.xml"
const TOL := 0.005                      # m de vai e volta entre quadros


class Plano:
	func height_at(_x: float, _z: float) -> float:
		return 0.0


var cam: Camera3D


func _initialize() -> void:
	cam = Camera3D.new()
	root.add_child(cam)


func _process(_d: float) -> bool:
	if not cam.is_inside_tree():
		return false
	var falhas := 0
	var plano := Plano.new()
	for nome in ["FollowOrbitNear", "FollowOrbitFar"]:
		for kmh in [60.0, 120.0, 180.0]:
			var g = GameCamera.load_set(CAM_XML, "BuggyCamSet_10", nome)
			var v: float = kmh / 3.6
			var rng := RandomNumberGenerator.new()
			rng.seed = 7
			var t := 0.0
			var s := _estado(t, v)
			g.reset(s, plano)
			var dist := []
			for k in 600:
				var dt := 1.0 / 60.0 + rng.randf_range(-0.0003, 0.0003)
				t += dt
				s = _estado(t, v)
				g.update(dt, s, plano)
				g.apply(cam, s.tp)
				dist.append(cam.global_position.distance_to(s.tp))
			# depois de 4 s a câmera já assentou: mede o pulo de um quadro pro outro
			var pior := 0.0
			for k in range(240, dist.size() - 1):
				pior = maxf(pior, absf(dist[k + 1] - dist[k]))
			var ok := pior < TOL
			if not ok:
				falhas += 1
			print("%-15s %3.0f km/h: distância %.2f m, maior pulo entre quadros %.1f cm  %s" % [nome, kmh,
				dist[-1], pior * 100.0, "ok" if ok else "FALHOU"])
	print("teste_camera_passo: %s" % ("ok" if falhas == 0 else "%d falhas" % falhas))
	quit(1 if falhas else 0)
	return true


## carro andando reto pra +Z a v m/s, chão plano
func _estado(t: float, v: float) -> Dictionary:
	return {"tp": Vector3(0.0, 0.6, v * t), "basis": Basis(), "vel": Vector3(0.0, 0.0, v), "v_f": v,
		"speed": v, "chao": 0.0, "air_time": 0.0, "grounded": 4, "ground_n": Vector3.UP}
