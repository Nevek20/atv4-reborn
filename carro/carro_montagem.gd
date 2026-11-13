extends "res://carro/carro_base.gd"
## Montagem do carro (carro/car.gd -> este -> carro_base.gd): modelo do jogo,
## rodas, cabine, piloto, volante, carga dos efeitos (fumaça, poeira, pedras,
## lascas, luzes, farol, painel, motor, som), sujeira, vibração e o visual
## por quadro. Nada aqui mexe na física: ela fica no car.gd.

## material de uma malha do jogo (carroceria, rodas, peças, volante do
## jogo): descarta a face de trás e multiplica pela cor do vértice
func material_do_jogo(m: StandardMaterial3D) -> void:
	m.cull_mode = MODEL_CULL
	if not _com_cor_vertice():
		return
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	if int(pecas.get("cor_vertice", 1)) >= 2:
		var c := m.albedo_color
		m.albedo_color = Color(c.r * COR_K_SRGB, c.g * COR_K_SRGB, c.b * COR_K_SRGB, c.a)


## a mesma conta pros shaders nossos que desenham por cima de malha do jogo
## (sujeira, ventoinha): multiplicador linear da cor do vértice, 0 = sem
func cor_k() -> float:
	if not _com_cor_vertice():
		return 0.0
	if int(pecas.get("cor_vertice", 1)) >= 2:
		return pow((COR_K_SRGB + 0.055) / 1.055, 2.4)
	return 1.0


static func _com_cor_vertice() -> bool:
	return COR_VERTICE and OS.get_environment("COR_VERTICE") != "0"    # print_tela: antes x depois


# ------------------------------------------------------------------ visual
func _make_wheel_mesh(w: Dictionary) -> void:
	var pivot := Node3D.new()       # frame do jogo (dentro do espelho)
	espelho.add_child(pivot)
	var spin := Node3D.new()
	pivot.add_child(spin)
	w.pivot = pivot
	w.spin_node = spin
	var canto: String = ("F" if w.front else "R") + ("L" if w.left else "R")
	var rg: Dictionary = pecas.get("rodas_glb", {}).get(canto, {})
	if _cena_glb and not rg.is_empty():
		# carro extra: a roda de cada canto do modelo (não espelha) e o cubo
		# dela (SUSP_xx: segue o curso e o esterço, não gira)
		var c := Vector3(rg.centro[0], rg.centro[1], rg.centro[2])
		var rmi := MeshInstance3D.new()
		rmi.mesh = CarroGlb.malha(_cena_glb, [rg.no], [], c, pecas.get("escala", 1.0))
		spin.add_child(rmi)
		if not rg.get("cubo", []).is_empty():
			var cmi := MeshInstance3D.new()
			cmi.mesh = CarroGlb.malha(_cena_glb, rg.cubo, [], c, pecas.get("escala", 1.0))
			pivot.add_child(cmi)
		return
	var path: String = wheel_front_file if w.front else wheel_rear_file
	if path != "" and ResourceLoader.exists(path):
		var mesh: Mesh = load(path) as Mesh
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i)
			if m is StandardMaterial3D:
				var m2: StandardMaterial3D = m.duplicate()
				material_do_jogo(m2)
				mi.set_surface_override_material(i, m2)
		# component map (14881): Mirror="1" nas rodas da esquerda do jogo
		# (o pivô está no frame do jogo, dentro do espelho)
		if w.left:
			mi.scale.x = -1.0
		# centro do modelo = centro da roda (sem deslocamento: matriz da RAM)
		spin.add_child(mi)
		return
	push_warning("Roda não encontrada em %s. Veja docs/assets.md (rodas)." % path)
	var cyl := CylinderMesh.new()
	cyl.top_radius = w.r
	cyl.bottom_radius = w.r
	cyl.height = 0.34
	cyl.radial_segments = 20
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.08, 0.08)
	mat.roughness = 0.9
	cyl.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.rotation_degrees = Vector3(0, 0, 90)
	spin.add_child(mi)
	# um risco claro pra dar pra ver a roda girando
	var mark := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.36, 0.08, w.r * 1.6)
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.35, 0.35, 0.35)
	bm.material = mm
	mark.mesh = bm
	spin.add_child(mark)


func _load_model() -> void:
	var mi := MeshInstance3D.new()
	var mesh: Mesh = null
	var glb := model_path.ends_with(".glb")
	if glb and ResourceLoader.exists(model_path):
		# carro extra nosso: a cena fica aberta até as rodas e o volante saírem dela
		_cena_glb = (load(model_path) as PackedScene).instantiate()
		CarroGlb.configurar(pecas)
		mesh = CarroGlb.malha(_cena_glb, [], pecas.get("excluir", []), Vector3.ZERO, pecas.get("escala", 1.0))
	elif model_path != "" and ResourceLoader.exists(model_path):
		mesh = load(model_path) as Mesh
	if mesh == null:
		push_warning("Modelo não encontrado em %s. Rode o tools/gerar_buggies.py (docs/comandos.md)." % model_path)
		var bm := BoxMesh.new()
		bm.size = Vector3(2.2, 1.0, 4.6)
		mi.mesh = bm
		mi.position = Vector3(0, 1.0, 0)
		model_root.add_child(mi)
		return
	if not glb and mesh is ArrayMesh and _tem("acertar_giro"):
		mesh = _acertar_giro(mesh)
	mi.mesh = mesh
	# pintura: a carroceria usa a textura "white", que o jogo gera em tempo
	# real juntando camadas (Base/Primary/Secondary/Detail + cores do XML).
	# O gerar_pintura.py faz isso e salva pintura.png do lado do modelo.
	var livery: Texture2D = null
	var lp := model_path.get_base_dir().path_join(livery_file)
	if ResourceLoader.exists(lp):
		livery = load(lp)
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i)
		if glb:
			continue                  # materiais do .glb como vieram (PBR, sem cor de vértice)
		var m2: StandardMaterial3D
		if m is StandardMaterial3D:
			m2 = m.duplicate()
		else:
			m2 = StandardMaterial3D.new()
			m2.albedo_color = Color(0.85, 0.85, 0.85)
		if livery and m and m.resource_name.ends_with("_white"):
			m2.albedo_texture = livery
		# textura com furo no jogo (redes das janelas, treliça do Trident):
		# tools/alfa_texturas.py devolve o alfa e aqui vira recorte
		if m2.albedo_texture and _tem_alfa(m2.albedo_texture):
			m2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m2.alpha_scissor_threshold = 0.5
		# vidro (só o Lazarus tem: Dakar_window_Index): o lote do .pingu vem
		# marcado transparente (+0x00 = 1, como decalques, sombras e o carro
		# fantasma), mas a textura _Index tem alfa cheio e o vidro saía uma
		# placa azul opaca por fora. A mesma imagem na Truck/Textures/Generic
		# (Dakar_window_8) tem alfa 0x1B = 21%: é o que vale aqui
		if m2.albedo_texture and m2.albedo_texture.resource_path.get_file().to_lower().contains("window"):
			m2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m2.albedo_color.a = VIDRO_ALFA
		material_do_jogo(m2)
		mi.set_surface_override_material(i, m2)
	var aabb := mesh.get_aabb()
	var c := aabb.get_center()
	model_offset = Vector3(-c.x, -aabb.position.y + 0.12, -c.z)
	mi.position = model_offset
	model_root.add_child(mi)
	body_mi = mi
	if chave() in CABINE_FECHADA:
		_face_de_dentro(mi)
	_load_steering_wheel()


## depois da física (precisa dos pontos ARSE, rodas e EXHAUST)
func _load_motor_treme() -> void:
	if not (MOTOR_TREME and _tem("motor_treme")) or body_mi == null:
		return
	motor_treme = preload("res://carro/motor_treme.gd").new()
	motor_treme.name = "MotorTreme"
	# trucks e extras: só o escape; extra (200 mil triângulos): só busca a 1 m da boca
	if motor_treme.separar(body_mi, points, vehicle_id, vehicle_id.begins_with("TRUCK") or motor_escondido,
			1.0 if _cena_glb else 0.0):
		model_root.add_child(motor_treme)
	else:
		motor_treme.free()
		motor_treme = null


func _load_luzes() -> void:
	if not (LUZ_FREIO and _tem("luzes")) or body_mi == null:
		return
	luzes = preload("res://carro/luzes.gd").new()
	luzes.name = "Luzes"
	if luzes.montar(self):
		add_child(luzes)
	else:
		luzes.free()
		luzes = null


func _load_farol() -> void:
	if not (FAROL and _tem("farol")) or body_mi == null:
		return
	farol = preload("res://carro/farol.gd").new()
	farol.name = "Farol"
	if farol.montar(self):
		add_child(farol)
	else:
		farol.free()
		farol = null


func _load_motor_anima() -> void:
	if not (MOTOR_ANIMA and _tem("motor_anima")) or body_mi == null:
		return
	if (vehicle_id.begins_with("TRUCK") and not (chave() in ANIMA_TRUCKS)) or motor_escondido:
		return
	motor_anima = preload("res://carro/motor_anima.gd").new()
	motor_anima.name = "MotorAnima"
	if motor_anima.montar(self):
		add_child(motor_anima)
	else:
		motor_anima.free()
		motor_anima = null


## Triângulo com o giro trocado no modelo do jogo (nov/2026, ELF atrás da
## cabine do Hammerhead): num quadrado, um dos 2 triângulos vem virado pro
## outro lado. No PS2 não aparece (empate na profundidade: ganha o último
## desenhado), aqui com a face de trás descartada vira buraco, ou o forro de
## dentro fica pra fora no plano da pintura e briga com ela (a diagonal no
## ELF). Vizinhos que são o MESMO pedaço de superfície: mesma superfície,
## aresta com os mesmos 2 pontos E o mesmo UV, quase no mesmo plano (|cos|
## > 0.7) e um de cada lado da aresta (sobrepostos = painel de 2 lados, fica).
## Em cada grupo ligado assim, vira os triângulos que discordam da maioria
## (área); empate ou grupo contraditório fica como está. O virado ganha
## vértices próprios, com a normal do lado da convenção do modelo.
static func _acertar_giro(mesh: ArrayMesh) -> ArrayMesh:
	var novo := ArrayMesh.new()
	var total := 0
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ix := PackedInt32Array(range(vs.size()))
		if a[Mesh.ARRAY_INDEX] != null:
			ix = a[Mesh.ARRAY_INDEX]
		var uvs = a[Mesh.ARRAY_TEX_UV]
		var nt := ix.size() / 3
		var nrm := PackedVector3Array()
		var area := PackedFloat32Array()
		nrm.resize(nt)
		area.resize(nt)
		for t in nt:
			var c := (vs[ix[3 * t + 1]] - vs[ix[3 * t]]).cross(vs[ix[3 * t + 2]] - vs[ix[3 * t]])
			area[t] = c.length()
			nrm[t] = c / area[t] if area[t] > 1e-12 else Vector3.ZERO
		var pk := func(i: int) -> Vector4i:
			var p: Vector3 = vs[i]
			var u: Vector2 = uvs[i] if uvs != null else Vector2.ZERO
			return Vector4i(roundi(p.x * 1e4), roundi(p.y * 1e4), roundi(p.z * 1e4),
				roundi(u.x * 1e4) * 100003 + roundi(u.y * 1e4))
		var arestas := {}
		for t in nt:
			if area[t] <= 1e-12:
				continue
			for e in 3:
				var i0 := ix[3 * t + e]
				var i1 := ix[3 * t + (e + 1) % 3]
				var k0: Vector4i = pk.call(i0)
				var k1: Vector4i = pk.call(i1)
				var frente := k0 < k1
				var k := [k0, k1] if frente else [k1, k0]
				if not arestas.has(k):
					arestas[k] = []
				arestas[k].append([t, frente, i0, i1, ix[3 * t + (e + 2) % 3]])
		var viz := {}                 # t -> [[outro, mesmo_giro]]
		for k in arestas:
			var l: Array = arestas[k]
			if l.size() != 2:
				continue
			var t1: int = l[0][0]
			var t2: int = l[1][0]
			if t1 == t2 or absf(nrm[t1].dot(nrm[t2])) < 0.7:
				continue
			var p0: Vector3 = vs[l[0][2]]
			var ed: Vector3 = (vs[l[0][3]] - p0).normalized()
			var w1: Vector3 = vs[l[0][4]] - p0
			var w2: Vector3 = vs[l[1][4]] - p0
			w1 -= ed * w1.dot(ed)
			w2 -= ed * w2.dot(ed)
			if w1.dot(w2) >= 0.0:
				continue              # sobrepostos: painel de 2 lados
			var mesmo: bool = l[0][1] != l[1][1]
			if not viz.has(t1):
				viz[t1] = []
			if not viz.has(t2):
				viz[t2] = []
			viz[t1].append([t2, mesmo])
			viz[t2].append([t1, mesmo])
		var vira := {}
		var visto := {}
		for t0 in viz:
			if visto.has(t0):
				continue
			var lado := {t0: false}
			var fila := [t0]
			var ok := true
			visto[t0] = true
			while not fila.is_empty():
				var t: int = fila.pop_back()
				for v in viz[t]:
					var quer: bool = lado[t] if v[1] else not lado[t]
					if lado.has(v[0]):
						if lado[v[0]] != quer:
							ok = false
					else:
						lado[v[0]] = quer
						visto[v[0]] = true
						fila.append(v[0])
			if not ok:
				continue
			var a0 := 0.0
			var a1 := 0.0
			for t in lado:
				if lado[t]:
					a1 += area[t]
				else:
					a0 += area[t]
			if absf(a0 - a1) < 1e-9:
				continue
			for t in lado:
				if lado[t] == (a1 < a0):
					vira[t] = true
		if vira.is_empty():
			novo.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		else:
			# vértices próprios pros virados (com a normal trocada)
			var b: Array = a.duplicate()
			var novos_ix := PackedInt32Array(ix)
			for att in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_COLOR]:
				if b[att] != null:
					b[att] = b[att].duplicate()
			b[Mesh.ARRAY_TANGENT] = null
			# sinal da normal: o mesmo dos triângulos certos do modelo (normal
			# do vértice x normal do giro). O jogo às vezes erra só o giro e
			# deixa a normal certa: inverter sempre escurecia o triângulo
			var conv := 1.0
			var ns = a[Mesh.ARRAY_NORMAL]
			if ns != null:
				var soma := 0.0
				for t in nt:
					if not vira.has(t):
						soma += (ns[ix[3 * t]] + ns[ix[3 * t + 1]] + ns[ix[3 * t + 2]]).dot(nrm[t]) * area[t]
				conv = 1.0 if soma >= 0.0 else -1.0
			var n0: int = vs.size()
			var k := 0
			for t in vira:
				for j in [0, 2, 1]:
					var i := ix[3 * t + j]
					for att in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_COLOR]:
						if b[att] != null:
							b[att].append(b[att][i])
					if b[Mesh.ARRAY_NORMAL] != null:
						var nv: Vector3 = ns[i]
						b[Mesh.ARRAY_NORMAL].append(nv if nv.dot(-nrm[t]) * conv >= 0.0 else -nv)
					novos_ix[3 * t + [0, 2, 1].find(j)] = n0 + k
					k += 1
			b[Mesh.ARRAY_INDEX] = novos_ix
			novo.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b)
			total += vira.size()
		novo.surface_set_material(s, mesh.surface_get_material(s))
		novo.surface_set_name(s, mesh.surface_get_name(s))
	if total > 0 and OS.has_environment("GIRO_DEBUG"):
		print("acertar_giro: %d triângulos virados" % total)
	return novo


## copia virada (ordem dos vértices e normal) de cada triângulo que não tem
## gêmeo do outro lado (mesmos 3 pontos); fica numa malha filha
func _face_de_dentro(mi: MeshInstance3D) -> void:
	var mesh: Mesh = mi.mesh
	var chave := func(a: Vector3, b: Vector3, c: Vector3) -> Array:
		var k := [Vector3i((a * 1000.0).round()), Vector3i((b * 1000.0).round()), Vector3i((c * 1000.0).round())]
		k.sort()
		return k
	var existe := {}
	var arrs: Array = []
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		arrs.append(a)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ix := PackedInt32Array(range(vs.size()))
		if a[Mesh.ARRAY_INDEX] != null:
			ix = a[Mesh.ARRAY_INDEX]
		for t in range(0, ix.size(), 3):
			var k: Array = chave.call(vs[ix[t]], vs[ix[t + 1]], vs[ix[t + 2]])
			existe[k] = existe.get(k, 0) + 1
	var costas := _com_costas(arrs)
	var dentro := ArrayMesh.new()
	var mats: Array = []
	var forro := StandardMaterial3D.new()
	forro.albedo_color = FORRO
	forro.roughness = 0.9
	forro.cull_mode = MODEL_CULL
	for s in arrs.size():
		# vidro (textura *window*, o Lazarus tem os vidros fechados no modelo):
		# fica sem face de dentro, senão de dentro a janela vira parede
		var ms := mi.get_active_material(s) as BaseMaterial3D
		if ms and ms.albedo_texture and ms.albedo_texture.resource_path.get_file().to_lower().contains("window"):
			continue
		var a: Array = arrs[s].duplicate()
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ix := PackedInt32Array(range(vs.size()))
		if a[Mesh.ARRAY_INDEX] != null:
			ix = a[Mesh.ARRAY_INDEX]
		var novo := PackedInt32Array()
		var painel := PackedInt32Array()     # painel de 2 lados: a cópia leva o material de fora
		for t in range(0, ix.size(), 3):
			if existe[chave.call(vs[ix[t]], vs[ix[t + 1]], vs[ix[t + 2]])] > 1:
				continue                  # chapa de 2 faces: já tem o lado de dentro
			var ct: int = costas.get(Vector2i(s, t), 0)
			if ct == 1:
				continue                  # idem, com os triângulos cortados diferente
			if ct == 2:
				painel.append_array([ix[t], ix[t + 2], ix[t + 1]])
				continue
			novo.append_array([ix[t], ix[t + 2], ix[t + 1]])
		if novo.is_empty() and painel.is_empty():
			continue
		if a[Mesh.ARRAY_NORMAL] != null:
			var ns: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			for i in ns.size():
				ns[i] = -ns[i]
			a[Mesh.ARRAY_NORMAL] = ns
		a[Mesh.ARRAY_TANGENT] = null
		var m: Material = mi.get_active_material(s)
		if not novo.is_empty():
			a[Mesh.ARRAY_INDEX] = novo
			dentro.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			mats.append(forro if m and m.resource_name.ends_with("_white") else m)
		if not painel.is_empty():
			a[Mesh.ARRAY_INDEX] = painel
			dentro.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			mats.append(m)
	if dentro.get_surface_count() == 0:
		return
	var d := MeshInstance3D.new()
	d.name = "FaceDeDentro"
	d.mesh = dentro
	for s in mats.size():
		d.set_surface_override_material(s, mats[s])
	mi.add_child(d)


## triângulos que já têm o lado de trás modelado com outra divisão em
## triângulos (o mesmo quadrado cortado pela outra diagonal, virado pro outro
## lado): o centro deles cai num triângulo de sentido oposto no mesmo plano (até
## 3 mm), ou o centro dele cai neles. No painel do ELF atrás da cabine do Hammerhead a cópia de dentro
## desses ficava no plano da pintura de fora, com o forro cinza, e piscava
## (nov/2026). Devolve {Vector2i(superfície, índice do 1º vértice): 1}; e 2
## quando o triângulo não é coberto mas divide uma aresta com um do outro
## lado no mesmo plano: o painel é de 2 lados no jogo (o ELF aparece dos 2
## lados) e a cópia leva a pintura em vez do forro
static func _com_costas(arrs: Array) -> Dictionary:
	const CEL := 0.25
	var tris: Array = []              # [s, t, a, b, c, normal]
	var grade := {}
	for s in arrs.size():
		var a: Array = arrs[s]
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ix := PackedInt32Array(range(vs.size()))
		if a[Mesh.ARRAY_INDEX] != null:
			ix = a[Mesh.ARRAY_INDEX]
		for t in range(0, ix.size(), 3):
			var p0 := vs[ix[t]]
			var p1 := vs[ix[t + 1]]
			var p2 := vs[ix[t + 2]]
			var n := (p1 - p0).cross(p2 - p0)
			if n.length_squared() < 1e-14:
				continue
			var k := tris.size()
			tris.append([s, t, p0, p1, p2, n.normalized()])
			var lo := Vector3i((p0.min(p1).min(p2) / CEL).floor())
			var hi := Vector3i((p0.max(p1).max(p2) / CEL).floor())
			if (hi - lo).length_squared() > 64:
				continue                  # placa enorme: não é desses painéis
			for x in range(lo.x, hi.x + 1):
				for y in range(lo.y, hi.y + 1):
					for z in range(lo.z, hi.z + 1):
						var c := Vector3i(x, y, z)
						if not grade.has(c):
							grade[c] = []
						grade[c].append(k)
	var out := {}
	for tr in tris:
		var g: Vector3 = (tr[2] + tr[3] + tr[4]) / 3.0
		var n: Vector3 = tr[5]
		for k in grade.get(Vector3i((g / CEL).floor()), []):
			var u: Array = tris[k]
			var nu: Vector3 = u[5]
			if nu.dot(n) > -0.99 or absf((g - u[2]).dot(nu)) > 0.003:
				continue
			var bc := Geometry3D.get_triangle_barycentric_coords(g, u[2], u[3], u[4])
			var gu: Vector3 = (u[2] + u[3] + u[4]) / 3.0
			var bu := Geometry3D.get_triangle_barycentric_coords(gu, tr[2], tr[3], tr[4])
			if (bc.x > 0.0 and bc.y > 0.0 and bc.z > 0.0) or (bu.x > 0.0 and bu.y > 0.0 and bu.z > 0.0):
				out[Vector2i(tr[0], tr[1])] = 1
				break
			var comum := 0
			for p in [tr[2], tr[3], tr[4]]:
				for q in [u[2], u[3], u[4]]:
					if (p as Vector3).distance_squared_to(q) < 1e-6:
						comum += 1
			if comum >= 2:
				out[Vector2i(tr[0], tr[1])] = 2
	return out


static var _alfa_cache := {}


static func _tem_alfa(t: Texture2D) -> bool:
	var k := t.resource_path if t.resource_path != "" else str(t.get_instance_id())
	if not _alfa_cache.has(k):
		var img := t.get_image()
		if img and img.is_compressed():
			img = img.duplicate()
			img.decompress()
		_alfa_cache[k] = img != null and img.detect_alpha() != Image.ALPHA_NONE
	return _alfa_cache[k]


## piloto (piloto.gd): o osso ROOT da animação fica em cima do ponto ARSE
## (rider+0x2f0; no Renegade origem = ARSE - (0, 1.1315, 0.3032)), sem girar
## com a matriz do ponto
func _load_piloto() -> void:
	if not points.has("ARSE"):
		return
	piloto = preload("res://carro/piloto.gd").new()
	if not piloto.carregar(PILOTO_DIR, MODEL_CULL):
		piloto.free()
		piloto = null
		return
	piloto.name = "Piloto"
	piloto.position = model_offset + banco() - piloto.root_pos
	model_root.add_child(piloto)
	piloto.paredes = _paredes_do_piloto()
	if BRACO_ABERTO.has(chave()) and OS.get_environment("COT_MIN") == "" and OS.get_environment("PAREDE") == "":
		piloto.cotovelo_min = BRACO_ABERTO[chave()].x
		piloto.parede_folga = BRACO_ABERTO[chave()].y
	if MAOS_NO_VOLANTE and VOLANTE_GIRA and _tem("maos") and _tem("volante_gira") and sw_pivot:
		var vol: Dictionary = pecas.get("volante", {})
		# aro no frame do esqueleto (o piloto não gira em relação ao modelo)
		piloto.prender_no_volante(sw_centro() - (banco() - piloto.root_pos), SW_AXIS, vol.get("raio", 0.19))


## onde fica a carroceria dos lados do piloto, pros cotovelos não varar a
## porta (Fireball: 6.4 cm pra dentro dela; piloto.gd PAREDE_FOLGA). Grade em
## (altura, frente) em volta do banco; em cada ponto um raio sai do meio do
## banco pros 2 lados e guarda onde bate na carroceria (ignora o que fica a
## menos de PAREDE_INICIO do meio: banco e o próprio piloto). Frame do
## esqueleto do piloto. Os triângulos vão numa grade (altura, frente) pra cada
## raio testar só os dele (~5 ms)
const PAREDE_INICIO := 0.18
func _paredes_do_piloto() -> Dictionary:
	if body_mi == null or not (body_mi.mesh is ArrayMesh):
		return {}
	var b := banco()
	var desl: Vector3 = b - piloto.root_pos      # esqueleto -> frame da carroceria
	var y0 := b.y + 0.05
	var z0 := b.z - 0.35
	var passo := Vector2(0.06, 0.06)
	var n := Vector2i(13, 18)                   # 0.05..0.77 acima e -0.35..+0.67 do banco
	var tris: Array = []
	var cel := {}
	var m: ArrayMesh = body_mi.mesh
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ix := PackedInt32Array(range(vs.size()))
		if a[Mesh.ARRAY_INDEX] != null:
			ix = a[Mesh.ARRAY_INDEX]
		for t in range(0, ix.size(), 3):
			var p0 := vs[ix[t]]
			var p1 := vs[ix[t + 1]]
			var p2 := vs[ix[t + 2]]
			var lo := p0.min(p1).min(p2)
			var hi := p0.max(p1).max(p2)
			if hi.x < b.x - 1.2 or lo.x > b.x + 1.2:
				continue
			var i0 := floori((lo.y - y0) / passo.x)
			var i1 := floori((hi.y - y0) / passo.x)
			var j0 := floori((lo.z - z0) / passo.y)
			var j1 := floori((hi.z - z0) / passo.y)
			if i1 < 0 or j1 < 0 or i0 >= n.x or j0 >= n.y:
				continue
			var k := tris.size()
			tris.append([p0, p1, p2])
			for i in range(maxi(i0, 0), mini(i1, n.x - 1) + 1):
				for j in range(maxi(j0, 0), mini(j1, n.y - 1) + 1):
					var c := Vector2i(i, j)
					if not cel.has(c):
						cel[c] = []
					cel[c].append(k)
	var dist := {1: PackedFloat32Array(), -1: PackedFloat32Array()}
	for lado in [1, -1]:
		var d: PackedFloat32Array = dist[lado]
		d.resize(n.x * n.y)
		for i in n.x:
			for j in n.y:
				var o := Vector3(b.x, y0 + (i + 0.5) * passo.x, z0 + (j + 0.5) * passo.y)
				var dir := Vector3(lado, 0.0, 0.0)
				var melhor := 2.0
				for k in cel.get(Vector2i(i, j), []):
					var tr: Array = tris[k]
					var r = Geometry3D.ray_intersects_triangle(o, dir, tr[0], tr[1], tr[2])
					if r != null:
						var dd: float = ((r as Vector3) - o).x * lado
						if dd > PAREDE_INICIO and dd < melhor:
							melhor = dd
				d[i * n.y + j] = melhor
	# no frame do esqueleto: x do meio do banco, y0/z0 deslocados
	return {"x": b.x - desl.x, "y0": y0 - desl.y, "z0": z0 - desl.z, "passo": passo, "n": n, "dist": dist}


## centro do aro do volante que aparece (o do jogo, ou o gerado avançado)
func sw_centro() -> Vector3:
	return SW_CENTER + SW_AXIS.normalized() * (avanco_volante() + sw_avanco)


## onde o piloto senta (frame do jogo): o ponto ARSE + BANCO_NOSSO
func banco() -> Vector3:
	var b: Vector3 = BANCO_NOSSO.get(chave(), Vector3.ZERO)
	if OS.has_environment("BANCO"):
		var p := OS.get_environment("BANCO").split(",")
		b = Vector3(float(p[0]), float(p[1]), float(p[2]))
	return points.get("ARSE", Vector3.ZERO) + b


## quanto o volante vem pro piloto (AVANCO_VOLANTE), além do da coluna
func avanco_volante() -> float:
	if OS.has_environment("AVANCO"):
		return float(OS.get_environment("AVANCO"))
	return AVANCO_VOLANTE.get(chave(), 0.0)


func _load_fumaca() -> void:
	if not (FUMACA and _tem("fumaca")):
		return
	fumaca = preload("res://efeitos/fumaca.gd").new()
	fumaca.name = "Fumaca"
	add_child(fumaca)
	if not fumaca.montar(self):
		fumaca.queue_free()
		fumaca = null


func _load_poeira() -> void:
	if not (POEIRA and _tem("poeira")):
		return
	poeira = preload("res://efeitos/poeira.gd").new()
	poeira.name = "Poeira"
	add_child(poeira)
	if not poeira.montar(self):
		poeira.queue_free()
		poeira = null


func _load_pedras() -> void:
	if not (PEDRAS and _tem("pedras")):
		return
	pedras = preload("res://efeitos/pedras.gd").new()
	pedras.name = "Pedras"
	add_child(pedras)
	if not pedras.montar(self):
		pedras.queue_free()
		pedras = null


func _load_lascas() -> void:
	if not (LASCAS and _tem("lascas")):
		return
	lascas = preload("res://efeitos/lascas.gd").new()
	lascas.name = "Lascas"
	add_child(lascas)
	if not lascas.montar(self):
		lascas.queue_free()
		lascas = null


func _load_painel() -> void:
	if not (PAINEL and _tem("painel")):
		return
	painel = preload("res://carro/painel.gd").new()
	painel.name = "Painel"
	painel.position = model_offset
	model_root.add_child(painel)
	if not painel.montar(self):
		painel.queue_free()
		painel = null


func _load_sujeira() -> void:
	if not SUJEIRA or not _tem("sujeira"):    # carro extra sem a 2ª textura (main.gd "desligar")
		return
	if OS.has_environment("SUJEIRA"):          # prints: nível fixo (e lama de terra nas rodas)
		sujeira_nivel = clampf(float(OS.get_environment("SUJEIRA")), 0.0, 1.0)
		if terrain and terrain.materials.size() > 0:
			roda_cor = Color(terrain.materials[0].get("DustColour", Color.BLACK), 0.8 * sujeira_nivel)
	sujeira = preload("res://carro/sujeira.gd").new()
	if not sujeira.montar(self):
		sujeira = null
		return
	sujeira.atualizar(sujeira_nivel, roda_cor)


func _load_sfx() -> void:
	if not SOM_PNEU:
		return
	sfx = preload("res://som/sfx_carro.gd").new()
	sfx.name = "SomPneu"
	add_child(sfx)
	if not sfx.carregar(self):
		sfx.queue_free()
		sfx = null


func _load_som() -> void:
	if not (SOM_MOTOR and _tem("som_motor")):
		return
	var dir: String = som_pasta if som_pasta != "" else preload("res://som/motor_som.gd").pasta_do_carro(vehicle_id)
	if dir == "":
		return
	som = preload("res://som/motor_som.gd").new()
	som.name = "SomMotor"
	if som_3d:
		som.ancora = self
	if som.carregar(dir):
		add_child(som)
	else:
		som.free()
		som = null


func _process(delta: float) -> void:
	var _t := Time.get_ticks_usec() if perf_on else 0
	if som:
		som.atualizar(rpm, som_carga, delta)
	if perf_on: _t = _pf("q: som do motor", _t)
	if fumaca:
		fumaca.atualizar(som_carga, rpm)
	if motor_treme:
		motor_treme.atualizar(rpm, som_carga, delta)
	if perf_on: _t = _pf("q: motor treme", _t)
	if fumaca:
		fumaca.seguir()             # depois do motor_treme: o cano já tremeu neste quadro
	if perf_on: _t = _pf("q: fumaça", _t)
	if motor_anima:
		motor_anima.atualizar(delta, rpm)
	if perf_on: _t = _pf("q: motor anima", _t)
	if luzes:
		luzes.atualizar(delta, brake_in, gear == -1)
	if farol:
		farol.atualizar(delta)
	if perf_on: _t = _pf("q: luzes e farol", _t)
	if sujeira:
		sujeira.atualizar(sujeira_nivel, roda_cor)
	if perf_on: _t = _pf("q: sujeira", _t)
	if painel:
		painel.atualizar(delta)
	if perf_on: _t = _pf("q: painel", _t)


func _load_steering_wheel() -> void:
	var path := model_path.get_basename() + "_volante.obj"
	var nosso := VOLANTE_NOSSO and _tem("volante_nosso")
	var vg: Dictionary = pecas.get("volante", {})
	if _cena_glb and vg.has("no") and not nosso:
		# carro extra: o volante do próprio modelo (STEER_HR) gira
		SW_CENTER = Vector3(vg.centro[0], vg.centro[1], vg.centro[2])
		SW_AXIS = Vector3(vg.eixo[0], vg.eixo[1], vg.eixo[2])
		sw_pivot = Node3D.new()
		sw_pivot.position = model_offset + SW_CENTER
		model_root.add_child(sw_pivot)
		var vmi := MeshInstance3D.new()
		vmi.mesh = CarroGlb.malha(_cena_glb, [vg.no], [], SW_CENTER, pecas.get("escala", 1.0))
		sw_pivot.add_child(vmi)
		return
	if not ResourceLoader.exists(path) and not (nosso and VOLANTE_SEM_MODELO.has(chave())):
		return
	var vol: Dictionary = pecas.get("volante", {})
	if vol.has("centro"):
		SW_CENTER = Vector3(vol.centro[0], vol.centro[1], vol.centro[2])
		SW_AXIS = Vector3(vol.eixo[0], vol.eixo[1], vol.eixo[2])
	if nosso:
		var ve := OS.get_environment("VOL_EIXO").split(",")
		if ve.size() == 3:
			SW_AXIS = Vector3(float(ve[0]), float(ve[1]), float(ve[2])).normalized()
		elif VOLANTE_EIXO.has(chave()):
			SW_AXIS = (VOLANTE_EIXO[chave()] as Vector3).normalized()
	sw_pivot = Node3D.new()
	sw_pivot.position = model_offset + SW_CENTER
	model_root.add_child(sw_pivot)
	var mi := MeshInstance3D.new()
	if nosso:
		sw_pivot.add_child(mi)
		sw_malha = mi
		sw_ponta_coluna = _ponta_coluna()
		_montar_volante(volante_estilo if volante_estilo != "" else Volantes.do_carro(chave()))
		return
	var mesh := load(path) as Mesh
	if mesh == null:
		return
	mi.mesh = mesh
	mi.position = -SW_CENTER
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i)
		var m2: StandardMaterial3D = m.duplicate() if m is StandardMaterial3D else StandardMaterial3D.new()
		material_do_jogo(m2)
		mi.set_surface_override_material(i, m2)
	sw_pivot.add_child(mi)


## monta o volante gerado. O centro dele é recuado pro painel (dish) e a
## coluna de direção do jogo, feita pro volante chato, termina quase no plano
## do aro: o volante avança pro piloto até a coluna acabar atrás do miolo
## (Kraken 5.5 cm, Viper 3.5, Trident 2.5, Storm 2.9; Renegade e Bulldog 0)
func _montar_volante(nome: String) -> void:
	volante_estilo = nome
	sw_malha.mesh = Volantes.montar(pecas.get("volante", {}).get("raio", 0.19), SW_AXIS, nome)
	sw_avanco = maxf(0.0, sw_ponta_coluna - avanco_volante() + 0.004 + Volantes.fundo(nome))
	sw_pivot.position = model_offset + sw_centro()
	_montar_coluna(nome)
	if piloto and piloto.no_volante():
		piloto.prender_no_volante(sw_centro() - (banco() - piloto.root_pos), SW_AXIS,
			pecas.get("volante", {}).get("raio", 0.19))


## coluna de direção nossa, quando a do modelo não encosta no volante: o volante
## trazido pro piloto (AVANCO_VOLANTE) ou sem volante no modelo
## (VOLANTE_SEM_MODELO). Vai do miolo pra trás no eixo até a ponta da coluna
## do modelo ou, sem ela, até a carroceria (raio no eixo; até COLUNA_MAX)
func _montar_coluna(nome: String) -> void:
	if sw_coluna:
		sw_coluna.queue_free()
		sw_coluna = null
	var ate := -INF                # onde a coluna acaba, no eixo a partir do SW_CENTER (- = pro painel)
	if VOLANTE_SEM_MODELO.has(chave()):
		ate = -_painel_no_eixo()
	elif avanco_volante() > 0.0 and sw_ponta_coluna > -INF:
		ate = sw_ponta_coluna - 0.02
	if ate == -INF:
		return
	var n := SW_AXIS.normalized()
	var ini := avanco_volante() + sw_avanco - Volantes.fundo(nome)    # atrás do miolo
	var comp := ini - ate
	if comp <= 0.01:
		return
	var cil := CylinderMesh.new()
	cil.top_radius = COLUNA_RAIO
	cil.bottom_radius = COLUNA_RAIO
	cil.height = comp
	cil.radial_segments = 16
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.07, 0.07, 0.075)
	m.metallic = 0.6
	m.roughness = 0.45
	cil.material = m
	sw_coluna = MeshInstance3D.new()
	sw_coluna.name = "ColunaNossa"
	sw_coluna.mesh = cil
	var y := n
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	sw_coluna.transform = Transform3D(Basis(x, y, x.cross(y)), model_offset + SW_CENTER + n * (ate + comp * 0.5))
	model_root.add_child(sw_coluna)


## distância do centro do aro até a carroceria, andando pra trás no eixo
## (o painel); COLUNA_MAX se não bater em nada
func _painel_no_eixo() -> float:
	var m := load(model_path) as Mesh
	if m == null:
		return COLUNA_MAX
	var o := SW_CENTER
	var d := -SW_AXIS.normalized()
	var melhor := COLUNA_MAX
	for si in m.get_surface_count():
		var a := m.surface_get_arrays(si)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ix := PackedInt32Array(range(vs.size()))
		if a[Mesh.ARRAY_INDEX] != null:
			ix = a[Mesh.ARRAY_INDEX]
		for t in range(0, ix.size(), 3):
			var hit = Geometry3D.ray_intersects_triangle(o, d, vs[ix[t]], vs[ix[t + 1]], vs[ix[t + 2]])
			if hit == null:
				hit = Geometry3D.ray_intersects_triangle(o, d, vs[ix[t]], vs[ix[t + 2]], vs[ix[t + 1]])
			if hit != null:
				melhor = minf(melhor, o.distance_to(hit))
	return melhor


## ponta da coluna de direção na carroceria: o vértice mais pro lado do piloto
## perto do eixo do volante (até 6 cm dele e 8 cm atrás do aro). -INF = sem coluna
func _ponta_coluna() -> float:
	var m := load(model_path) as Mesh
	var ponta := -INF
	if m == null:
		return ponta
	var n := SW_AXIS.normalized()
	for si in m.get_surface_count():
		var vs: PackedVector3Array = m.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
		for v in vs:
			var d := v - SW_CENTER
			var t := d.dot(n)
			if t > -0.08 and t < 0.1 and (d - n * t).length() < 0.06:
				ponta = maxf(ponta, t)
	return ponta


## troca o volante gerado (nome = "" passa pro próximo estilo); devolve o nome
func trocar_volante(nome := "") -> String:
	if sw_malha == null:
		return ""
	if nome == "":
		var lista := Volantes.nomes()
		nome = lista[(lista.find(volante_estilo) + 1) % lista.size()]
	_montar_volante(nome)
	return nome


func driver_eye() -> Vector3:
	return model_root.get_global_transform_interpolated() * (model_offset + DRIVER_EYE)


## posição do olho no frame do modelo (chame de novo se mudar FP_*)
func update_eye() -> void:
	var vol: Dictionary = pecas.get("volante", {})
	if FP_VOLANTE and vol.has("centro"):
		var c := Vector3(vol.centro[0], vol.centro[1], vol.centro[2])
		var e := Vector3(vol.eixo[0], vol.eixo[1], vol.eixo[2]).normalized() if vol.has("eixo") else Vector3.ZERO
		DRIVER_EYE = c + e * avanco_volante() + Vector3(0.0, FP_UP, -FP_BACK)
	elif points.has("ARSE"):
		DRIVER_EYE = points["ARSE"] + EYE_FROM_ARSE


## transform da câmera de primeira pessoa (mundo, interpolado)
func first_person_xf() -> Transform3D:
	var eye: Vector3 = driver_eye()
	var b: Basis = get_global_transform_interpolated().basis
	var turn: float = steer / MAX_STEER
	var look_dir: Vector3 = (b.z + b.x * turn * 0.25 - b.y * FP_PITCH).normalized()
	return Transform3D(Basis.looking_at(look_dir, b.y), eye)


func flip_model() -> void:
	model_root.rotation.y = PI - model_root.rotation.y


func _sujeira_passo() -> void:
	if not SUJEIRA or grounded == 0 or spd_ground < 0.5 or terrain == null:
		return
	var k := 0.0
	for w in wheels:
		if w.mat >= 0:
			k = maxf(k, minf(terrain.taxa_sujeira(w.mat), 1.0))
	sujeira_nivel = clampf(sujeira_nivel + minf(spd_ground, 15.0) * k * 5e-5, 0.0, 1.0)


## 0x224418 + 0x2242d0 (do 0x203930, depois da sujeira): com roda no chão e
## material embaixo da FL (veículo+0xa88[0]), quando o material muda a cor
## parte da de agora pro DustColour dele (alfa = WheelDirtAlpha; com alfa 0
## só o alfa cai). t sobe giro da FL (W+0x48)·dt·0.002·WheelDirtRate
## suavizada (0.95/0.05), x 10·patinada da RL (0x604) se passar de 1. Na água
## (veículo+0xae8) o alvo é o registro DAT_007f4bf8+0x20 (AGUA_REG). Confere com a RAM: tests/teste_derrapagem.gd.
func _roda_suja_passo(dt: float) -> void:
	if not SUJEIRA or grounded == 0 or terrain == null:
		return
	var fl: Dictionary = wheels[0]
	# na água o alvo é o registro da água (material -2, como na RAM)
	var mid: int = -2 if agua != null else fl.mat
	if mid != -2 and (fl.mat < 0 or fl.mat >= terrain.materials.size()):
		return
	var p: float = fl.omega * dt * 0.002
	var pat := clampf(wheels[2].sr, 0.0, 1.0)
	if pat * 10.0 > 1.0:
		p *= pat * 10.0
	if mid != roda_mat:
		var m: Dictionary = AGUA_REG if mid == -2 else terrain.materials[mid]
		var alfa := float(m.get("WheelDirtAlpha", 0.0))
		var poeira: Color = m.get("DustColour", Color(0, 0, 0, 0))
		roda_mat = mid
		roda_t = 0.0
		roda_de = roda_cor
		roda_taxa_alvo = float(m.get("WheelDirtRate", 0.0))
		if roda_de.a < 1e-6:
			roda_de = Color(poeira, 0.0)
			roda_para = Color(poeira, alfa)
		elif alfa > 1e-6:
			roda_para = Color(poeira, alfa)
		else:
			roda_para.a = alfa
	roda_taxa = roda_taxa * 0.95 + roda_taxa_alvo * 0.05
	roda_t = clampf(roda_t + p * roda_taxa, 0.0, 1.0)
	roda_cor = roda_de.lerp(roda_para, roda_t)


## recomeço (0x223db0): carro e rodas limpos
func limpar_sujeira() -> void:
	sujeira_nivel = 0.0
	roda_de = Color(0, 0, 0, 0)
	roda_para = Color(0, 0, 0, 0)
	roda_cor = Color(0, 0, 0, 0)
	roda_mat = -1
	roda_t = 0.0
	roda_taxa = 0.0
	roda_taxa_alvo = 0.0


## 0x202760: sorteia a tremida das rodas no chão (FL, RL, FR; RR = RL)
func _wheel_jitter() -> void:
	for w in wheels:
		w.jit = 0.0
	jitter_chao = 0.0
	if jit_order.size() != 4:
		return
	var no_chao := 0
	for k in 3:
		var w: Dictionary = wheels[jit_order[k]]
		if not w.hit:
			continue
		var wj: float = terrain.wheel_jitter(w.mat, surface_jitter) if terrain else surface_jitter
		jitter_chao += wj
		no_chao += 1
		var amp := minf(wj * JIT_K * spd_ground, 1.0)
		jit_seed = (jit_seed * 31415821 + 1) & 0x3FFFFFFF
		w.jit = amp * (float(jit_seed) * 0.075 / 1073741824.0 - 0.0375)
	wheels[jit_order[3]].jit = wheels[jit_order[1]].jit
	if no_chao > 0:
		jitter_chao /= no_chao


## A cada passo do jogo (50 Hz): vibração do controle (0x202ab8), pouso
## (0x370df0) e taxa da suspensão do som (0x36fa28/0x370548) -> tremida do
## volante (melhoria nossa, VOLANTE_TREME)
func _vibracao(dt: float, v_l: float, v_f: float) -> void:
	var v := linear_velocity.length()       # corpo+0xe0
	vibracao = 0.0
	if grounded > 0:                        # corpo+0x8a8: rodas no chão
		var trava := false
		var pat := 0.0
		for w in wheels:
			if w.sr < -0.95:                    # 0x600: roda travada
				trava = true
			if w.omega > 3.14:                  # W+0x48: só roda girando
				pat = maxf(pat, clampf(w.sr, 0.0, 1.0))
		var base := 1.5 * absf(v_l)
		if v < 8.938889 and pat > 0.1:
			base += 15.0
		if trava:
			base += v * 0.33561218
		vibracao = base * randf_range(0.1, 0.9)
		if randf() < 0.1:
			vibracao += v * 0.25
		vibracao *= 0.07
	# pouso: o som conta o tempo com nenhuma roda no chão e toca ao voltar
	pouso = 0.0
	if grounded == 0:
		ar_som += dt
	else:
		if ar_som > 0.1:
			pouso = 0.5 + 0.5 * minf(1.0, ar_som)
		ar_som = 0.0
	# suspensão: por roda (FL, RL) s = clamp(curso x SuspensionScale, 0, 1) e
	# a taxa ds/dt (0 no ar); o dono filtra 0.4 x anterior + 0.1 x média
	var media := 0.0
	if jit_order.size() == 4:
		for k in 2:
			var w: Dictionary = wheels[jit_order[k]]
			var d := 0.0
			if w.hit:
				var s := clampf(w.x * SUSP_ESCALA, 0.0, 1.0)
				d = (s - _susp_ant[k]) / dt
				_susp_ant[k] = s
			else:
				_susp_ant[k] = 0.0
			media += d * 0.5
	susp_taxa = clampf(0.4 * susp_taxa + 0.1 * media, -1.0, 1.0)
	var tranco := pouso
	if absf(v_f) >= SUSP_VEL:
		for k in 2:
			var lim: float = [SUSP_PEQUENA, SUSP_GRANDE][k]
			var acima := susp_taxa > lim
			if acima and not _susp_acima[k]:
				tranco = maxf(tranco, 0.4 if k == 0 else 1.0)
			_susp_acima[k] = acima
	else:
		_susp_acima = [false, false]
	if not (VOLANTE_TREME and _tem("volante_treme")):
		return
	pancada = maxf(pancada * exp(-dt / PANCADA_SOLTA), tranco)
	# alvo do giro: sorteio pela vibração, tranco com sinal sorteado, e a
	# diferença de curso das rodas da frente (uma batendo e a outra não)
	var terra := 0.0
	if jit_order.size() == 4:
		terra = (wheels[jit_order[0]].jit - wheels[jit_order[2]].jit) * TREME_TERRA
	_treme_alvo = deg_to_rad(TREME_GRAUS * vibracao * randf_range(-1.0, 1.0)
		+ TREME_PANCADA_GRAUS * pancada * (1.0 if randf() < 0.5 else -1.0) + terra)


# ------------------------------------------------------------------ pneus
## Parte 1 portada do executável do jogo. Ordem igual à do jogo:
##   0x20ede8  curvatura pedida pela direção (com subesterço)
##   0x20e8d8  força de tração por roda
##   0x20eb98  força de freio por roda (com divisão frente/trás)
##   0x20efa0  derrapagem: força lateral total + torque de guinada, divididos
##             entre eixo dianteiro e traseiro
##   0x2101e0  elipse de atrito por roda, com a aderência que encolhe quando
##             a roda satura e volta quando ela para de saturar
## Unidades do jogo: mph (x 0.44694445 = 1609/3600) e graus.
const MPH_G := 0.44694445
const DEG := 0.017453294

## posição e giros de cada roda (fisica_cpp rodas.cpp visual_rodas é o mesmo)
func _visual_rodas_gd(a_jogo: float) -> void:
	for w in wheels:
		var x: float = clampf(w.x, w.min, w.max) + w.jit   # 0x222078: sem clamp depois
		w.pivot.position = Vector3(w.px, w.y0 + x, w.pz) * ESPELHO
		w.pivot.rotation.y = a_jogo if w.front else 0.0
		w.spin_node.rotation.x = w.spin            # ângulo da roda (W+0x4c, _giro_rodas)


func _update_visuals(dt: float, _v_f: float) -> void:
	# o visual fica no frame do jogo (espelho): rotação em y troca de sinal
	# (S Ry(a) S = Ry(-a)), em x não. a_jogo = ângulo das rodas no jogo
	var a_jogo: float = -steer * P.vis_steer
	var fc = get("cpp")                           # física em C++ (car.gd): as rodas lá
	if fc:
		fc.visual_rodas(a_jogo)
	else:
		_visual_rodas_gd(a_jogo)
	# direção suavizada do piloto (0x187060: s += min(1/dt, 30)·(direção - s)·dt):
	# é o que move os braços dele no jogo, então o volante anda junto
	if dt > 0.0:
		rider_s = clampf(rider_s + minf(1.0 / dt, 30.0) * (steer - rider_s) * dt, -1.0, 1.0)
	if dt > 0.0:
		treme += (_treme_alvo - treme) * (1.0 - exp(-dt / TREME_SUAVE))
	if sw_pivot and VOLANTE_GIRA and _tem("volante_gira"):
		var giro := -rider_s * SW_TURNS
		if piloto and piloto.no_volante():
			giro = piloto.giro_volante(rider_s)
		sw_pivot.basis = Basis(SW_AXIS.normalized(), giro + treme)
	var _t := Time.get_ticks_usec() if perf_on else 0
	if piloto and not longe_vis:
		piloto.pose(rider_s, treme if VOLANTE_GIRA else 0.0)
	if perf_on: _t = _pf("vis: piloto (braços IK)", _t)
	if susp_vis and not longe_vis:
		susp_vis.update(a_jogo)
	if perf_on: _t = _pf("vis: suspensão", _t)
