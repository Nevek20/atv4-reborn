extends RefCounted
## Carros extras NOSSOS em .glb (tools/carro_glb.py; padrão do Assetto Corsa:
## WHEEL_LF..., STEER_HR, SUSP_xx). O Godot importa o .glb com os materiais
## PBR (textura, normal map, metálico, vidro); aqui as malhas da cena viram um
## ArrayMesh só no frame do modelo do jogo, como os .obj dos carros do jogo:
## x virado (o glTF com +z pra frente tem +x na ESQUERDA; o jogo, mão
## esquerda, tem +x na direita) e a ordem dos vértices trocada pra a face da
## frente continuar a da frente. O car.gd põe isso dentro do espelho, igual
## aos outros carros.

const ESPELHO := Vector3(-1, 1, 1)
# metal de verdade (nome do material, minúsculo): o resto perde o metálico.
# O export do Sketchfab põe metallicFactor 1.0 em quase tudo (pneu, borracha,
# plástico, banco): metal mostra o reflexo do céu cinza no lugar da cor e o
# carro inteiro ficava "apagado" do lado dos do jogo (Matheus, nov/2026)
const METAIS := ["chrome", "metal_shiny", "mirror", "mirrror", "rim", "disk", "caliper", "exhaust", "nuts_bolt"]
static var _materiais := {}
static var _pintura := ""        # material da pintura (pecas.json "pintura") e quanto clarear
static var _brilho := 1.0


## antes de juntar as malhas de um carro: a pintura dele (tools/carro_glb.py)
static func configurar(pecas: Dictionary) -> void:
	var p: Dictionary = pecas.get("pintura", {})
	_pintura = String(p.get("material", "")) if p.get("material") != null else ""
	_brilho = float(p.get("brilho", 1.0))
	_materiais.clear()


## junta as malhas: raizes = nomes dos nós (com os filhos; vazio = a cena
## toda), fora = nós que não entram (com os filhos), origem = ponto do frame
## do jogo que vira o zero da malha (centro da roda, do volante), escala =
## tamanho no jogo (pecas.json "escala": os carros do jogo são ~25% maiores
## que os de verdade)
static func malha(cena: Node, raizes: Array, fora: Array, origem := Vector3.ZERO, escala := 1.0) -> ArrayMesh:
	var nos: Array = []
	if raizes.is_empty():
		nos = [cena]
	else:
		for nome in raizes:
			var n := _achar(cena, String(nome))
			if n:
				nos.append(n)
	var out := ArrayMesh.new()
	var fila := nos.duplicate()
	while not fila.is_empty():
		var n: Node = fila.pop_front()
		if String(n.name) in fora:
			continue
		if n is MeshInstance3D and n.mesh:
			_juntar(out, n, _rel(n, cena), origem, escala)
		fila.append_array(n.get_children())
	return out


static func _achar(raiz: Node, nome: String) -> Node:
	if String(raiz.name) == nome:
		return raiz
	return raiz.find_child(nome, true, false)


## transform do nó no frame da cena (fora da árvore não tem global_transform)
static func _rel(n: Node, raiz: Node) -> Transform3D:
	var t := Transform3D()
	var x := n
	while x != null and x != raiz:
		if x is Node3D:
			t = (x as Node3D).transform * t
		x = x.get_parent()
	return t


static func _juntar(out: ArrayMesh, mi: MeshInstance3D, xf: Transform3D, origem: Vector3, escala: float) -> void:
	var m: Mesh = mi.mesh
	var nb := xf.basis.inverse().transposed()
	for s in m.get_surface_count():
		if _vidro_janela(_material(mi, m, s)):
			continue
		var a := m.surface_get_arrays(s)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		for i in vs.size():
			vs[i] = (xf * vs[i]) * ESPELHO * escala - origem
		a[Mesh.ARRAY_VERTEX] = vs
		if a[Mesh.ARRAY_NORMAL] != null:
			var ns: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			for i in ns.size():
				ns[i] = ((nb * ns[i]) * ESPELHO).normalized()
			a[Mesh.ARRAY_NORMAL] = ns
		if a[Mesh.ARRAY_TANGENT] != null:
			# espelho troca a mão da base tangente: o sinal (w) vira
			var ts: PackedFloat32Array = a[Mesh.ARRAY_TANGENT]
			for i in range(0, ts.size(), 4):
				var t := (xf.basis * Vector3(ts[i], ts[i + 1], ts[i + 2])) * ESPELHO
				t = t.normalized()
				ts[i] = t.x
				ts[i + 1] = t.y
				ts[i + 2] = t.z
				ts[i + 3] = -ts[i + 3]
			a[Mesh.ARRAY_TANGENT] = ts
		var ix = a[Mesh.ARRAY_INDEX]
		if ix == null or (ix as PackedInt32Array).is_empty():
			ix = PackedInt32Array(range(vs.size()))
		var iv: PackedInt32Array = ix
		for t in range(0, iv.size() - 2, 3):
			var k := iv[t + 1]
			iv[t + 1] = iv[t + 2]
			iv[t + 2] = k
		a[Mesh.ARRAY_INDEX] = iv
		a[Mesh.ARRAY_BONES] = null
		a[Mesh.ARRAY_WEIGHTS] = null
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		out.surface_set_material(out.get_surface_count() - 1, do_jogo(_material(mi, m, s)))


static func _material(mi: MeshInstance3D, m: Mesh, s: int) -> Material:
	var mat: Material = mi.get_surface_override_material(s)
	if mat == null:
		mat = mi.material_override if mi.material_override else m.surface_get_material(s)
	return mat


## vidro das janelas sai (pedido do Matheus, nov/2026): o do modelo é
## verde-água a 53% em 2 camadas (dentro e fora) e deixava a estrada azul na
## câmera do piloto; neutro a 12% ficava leitoso (reflete o céu). Os carros do
## jogo não têm vidro. Farol e lanterna ficam (são "glass_headlight/rear").
## MATERIAL_GLB=1 deixa
static func _vidro_janela(mat: Material) -> bool:
	if mat == null or OS.get_environment("MATERIAL_GLB") == "1":
		return false
	var n := mat.resource_name.to_lower()
	return "glass" in n and "window" in n


## material do modelo no jeito dos carros do jogo (foscos): metálico só no
## metal de verdade, sem verniz (clearcoat) na pintura, vidro liso. Uma cópia
## por material. MATERIAL_GLB=1 deixa como veio do modelo (pra comparar)
static func do_jogo(m: Material) -> Material:
	if not (m is BaseMaterial3D) or OS.get_environment("MATERIAL_GLB") == "1":
		return m
	if _materiais.has(m):
		return _materiais[m]
	var b: BaseMaterial3D = m.duplicate()
	var nome := m.resource_name.to_lower()
	b.clearcoat_enabled = false
	if "glass" in nome:
		b.metallic = 0.0
		b.roughness = 0.05
		pass
	elif METAIS.any(func(x): return x in nome):
		pass
	else:
		b.metallic = 0.0
		b.roughness = maxf(b.roughness, 0.55)
	if _pintura != "" and m.resource_name == _pintura:
		# o branco da textura vira o branco do jogo (ver tools/carro_glb.py pintura)
		var c := b.albedo_color
		b.albedo_color = Color(c.r * _brilho, c.g * _brilho, c.b * _brilho, c.a)
	_materiais[m] = b
	return b
