extends SceneTree
## Câmera de órbita (game_camera.gd) com o carro parado x a RAM de 6 save
## states parados (tests/ref_ram_camera.json: Bulldog, Inferno, Phantom,
## Storm, Buccaneer e Goliath): quanto a câmera fica atrás e acima da origem
## do modelo (no plano, só com a guinada), de lado e o zoom. Cada save state
## está numa das 2 câmeras de órbita (perto/longe): vale a que bater.
## A câmera ativa do save state é a de suavização ~40/s (ler_savestate.py):
## as outras ficam paradas onde a introdução da corrida deixou.
## Uso: godot --headless --path . -s res://tests/teste_camera_ram.gd

const GameCamera := preload("res://camera/game_camera.gd")
const CAM_XML := "res://data/cameras.xml"
const TOL := 0.02                       # m
const TOL_ZOOM := 0.001


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
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/ref_ram_camera.json"))
	var falhas := 0
	for nome in ref:
		var r: Dictionary = ref[nome]
		var melhor := {}
		for qual in ["FollowOrbitNear", "FollowOrbitFar"]:
			var m := _medir(r, qual)
			m.qual = qual
			m.erro = Vector3(m.atras - r.atras, m.y - r.y, m.lado - r.lado).length()
			if melhor.is_empty() or m.erro < melhor.erro:
				melhor = m
		var ok: bool = melhor.erro < TOL and absf(melhor.zoom - r.zoom) < TOL_ZOOM
		falhas += 0 if ok else 1
		print("%-9s %-15s atrás %.3f / %.3f  y %.3f / %.3f  zoom %.4f / %.4f  erro %.1f cm  %s" % [
			nome, melhor.qual, melhor.atras, r.atras, melhor.y, r.y, melhor.zoom, r.zoom,
			melhor.erro * 100.0, "ok" if ok else "FALHOU"])
	print("teste_camera_ram: %s (remake / RAM)" % ("ok" if falhas == 0 else "%d falhas" % falhas))
	quit(1 if falhas else 0)
	return true


## carro parado no plano (origem a altura_origem do chão, arfagem do save
## state), 10 s de câmera; offset no frame do carro só com a guinada
func _medir(r: Dictionary, qual: String) -> Dictionary:
	var g = GameCamera.load_set(CAM_XML, r.set, qual)
	var f := Vector3(0.0, r.frente_y, sqrt(1.0 - r.frente_y * r.frente_y))
	var x := Vector3.UP.cross(f).normalized()
	var s := {"tp": Vector3(0.0, r.altura_origem, 0.0), "basis": Basis(x, f.cross(x), f), "vel": Vector3.ZERO,
		"v_f": 0.0, "speed": 0.0, "chao": 0.0, "air_time": 0.0, "grounded": 4, "ground_n": Vector3.UP}
	var pl := Plano.new()
	g.reset(s, pl)
	for k in 600:
		g.update(1.0 / 60.0, s, pl)
	g.apply(cam, s.tp)
	var o: Vector3 = cam.global_position - s.tp
	return {"atras": -o.z, "y": o.y, "lado": o.x, "zoom": g.zoom}
