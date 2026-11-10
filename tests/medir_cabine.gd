extends SceneTree
## Folga da cabeça do piloto até o teto, por carro: do osso "head" sobe reto
## (y do modelo) até a primeira face da carroceria. Pra acertar o banco
## (car.gd BANCO_NOSSO) de carro com cabine alta, comparando com os outros.
## Uso: godot --headless --path . -s res://tests/medir_cabine.gd   (VEHS=16,25 só esses;
## BANCO=x,y,z testa um banco no lugar do BANCO_NOSSO)

const Car := preload("res://carro/car.gd")
const Main := preload("res://main.gd")

var carros := []
var quadros := 0


func _initialize() -> void:
	var frota: Array = Main.frota()
	var so: Array = []
	if OS.has_environment("VEHS"):
		for x in OS.get_environment("VEHS").split(","):
			so.append(int(x))
	for i in frota.size():
		if (not so.is_empty() and not i in so) or frota[i].get("extra", false):
			continue
		var c = Car.new()
		Main.configurar(c, frota[i])
		c.suspension = false
		root.add_child(c)
		c.reset_to(Vector3(i * 30.0, 50.0, 0.0), 0.0)
		carros.append([i, c])


func _process(_dt: float) -> bool:
	quadros += 1
	if quadros < 3:
		return false
	for e in carros:
		var c = e[1]
		if c.piloto == null or c.body_mi == null:
			print("%2d %-12s sem piloto" % [e[0], c.chave()])
			continue
		var inv: Transform3D = c.body_mi.global_transform.affine_inverse()
		var h: Vector3 = inv * c.piloto.cabeca_global()
		var teto := _sobe(c.body_mi.mesh, h)
		var b: Vector3 = c.banco()
		# olho da câmera do piloto x osso da cabeça (frame do modelo, z = frente)
		var olho: Vector3 = c.DRIVER_EYE - h
		print("%2d %-12s cabeça %.3f acima do banco, teto %.3f acima da cabeça, olho %+.3f acima e %+.3f na frente da cabeça" % [
			e[0], c.chave(), h.y - (b.y), teto, olho.y, olho.z])
		# cotovelos x porta: com o volante de um lado ao outro, a menor folga
		# entre o cotovelo e a carroceria pro lado de fora dele (raio do
		# meio do banco até o cotovelo e além); negativo = varou
		var p = c.piloto
		var desl: Vector3 = b - p.root_pos           # esqueleto -> frame da carroceria
		var pior := INF
		var onde := ""
		for k in 21:
			var sv := -1.0 + k * 0.1
			p.pose(sv)
			var jb: Array = p.juntas_bracos()
			for jj in jb:
				var cot: Vector3 = jj[0] + desl
				var lado := signf(cot.x - b.x)
				var de := Vector3(b.x, cot.y, cot.z)
				var parede := _anda(c.body_mi.mesh, de, Vector3(lado, 0.0, 0.0))
				var folga := parede - absf(cot.x - b.x)
				if folga < pior:
					pior = folga
					onde = "s %+.1f" % sv
		print("   cotovelo até a carroceria (pro lado de fora): %.1f cm no pior caso (%s)" % [pior * 100.0, onde])
	return true


## menor distância andando de p na direção dir até uma face da malha
func _anda(m: Mesh, p: Vector3, dir: Vector3) -> float:
	var melhor := INF
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ix := PackedInt32Array(range(vs.size()))
		if a[Mesh.ARRAY_INDEX] != null:
			ix = a[Mesh.ARRAY_INDEX]
		for t in range(0, ix.size(), 3):
			var r = Geometry3D.ray_intersects_triangle(p, dir, vs[ix[t]], vs[ix[t + 1]], vs[ix[t + 2]])
			if r != null:
				melhor = minf(melhor, ((r as Vector3) - p).dot(dir))
	return melhor


## menor distância subindo reto (+y) de p até uma face da malha
func _sobe(m: Mesh, p: Vector3) -> float:
	var melhor := INF
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ix := PackedInt32Array(range(vs.size()))
		if a[Mesh.ARRAY_INDEX] != null:
			ix = a[Mesh.ARRAY_INDEX]
		for t in range(0, ix.size(), 3):
			var r = Geometry3D.ray_intersects_triangle(p, Vector3.UP, vs[ix[t]], vs[ix[t + 1]], vs[ix[t + 2]])
			if r != null:
				melhor = minf(melhor, (r as Vector3).y - p.y)
	return melhor
