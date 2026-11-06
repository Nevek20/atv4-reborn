extends Node3D
## Objetos da pista RX01 (PORTA do jogo; tools/rx01_objetos.py,
## docs/engenharia_reversa.md, Objetos da pista): casas, celeiros,
## arquibancadas, arco de largada, torres de luz, alto-falantes, placas,
## guard-rail, cercas, fardos, pedras, cactos, árvores e moitas.
##
## Posições: Levels/RX_01/Event/Rallycross/Default/#def5772a (57 pingus e 651
## bantams, data/rx01_objetos.json). Cada instância tem a matriz do jogo
## (linhas = eixos do modelo no mundo, com escala) e a posição; o remake leva
## pro mundo dele com Terrain.do_jogo (X = z - 1024, Y = y, Z = x), o que vira
## uma base com determinante -1 (o Godot desenha espelhado certo, como o nó
## "espelho" do carro).
##
## Desenho: .obj do tools/rx01_objetos.py em assets/rx01 (pingu pelo
## pingu2obj, bantam pelo decodificador de lá), cor do vértice x textura como
## os carros (car.gd material_do_jogo: 0x80 = 1.0, até 2.0). Bantam não tem
## normal no jogo (luz assada na cor): SEM luz do Godot, sem sombra dinâmica,
## dos 2 lados, numa MultiMesh por modelo com a cor de luz da instância.
## Pingu (casas, arco...) tem normal e recebe o sol.
##
## Colisão: os triângulos do KDt de cada modelo (Models/KDt, nome =
## crc32('<modelo>.kdt')), levados pro mundo e juntos num
## ConcavePolygonShape3D (2 lados). Cerca de plástico, cerca de madeira e
## fardo de feno só têm HsC (esferas) e no jogo QUEBRAM (bantams *_Particle_*,
## pontos "particle Hay"): ficam sem colisão até portar isso.

const Terrain := preload("res://terrain.gd")
const ARQ := "res://data/rx01_objetos.json"
const PASTA := "res://assets/rx01/"
const COR_K_SRGB := 255.0 / 128.0       # car.gd: no albedo vira o COR_K do pingu2obj

var instancias := 0
var modelos := 0
var triangulos := 0
var faltando: PackedStringArray = []
var corpo: StaticBody3D = null
var carregados := {}                     # modelo -> true (só eles ganham colisão)
var _mats := {}                          # material do .mtl -> nosso (cache)
var _presas := {}                        # materiais com a textura presa na borda (modelos.json)
var _misturadas := {}                    # materiais de lote transparente no .pingu (modelos.json)
## água (0x1bb098): uma caixa por instância WATER_* = a caixa do modelo (x, z)
## no frame da instância, superfície = o y mais alto dela. Na RAM do Matheus
## (Renegade_dentro_da_agua.p2s) o objeto em 0x10cad20 tem centro, giro (15°),
## meia-largura 21.01 x 19.88 m e superfície 206.017 = os da WATER_puddle01
var aguas: Array = []                    # [{inv, cx, cz, hx, hz, y, cor}]
## cor da água no objeto (+0x70; o espirro usa com alfa x 0.6), da RAM do RX01
const COR_AGUA := Color(0.5882, 0.6067, 0.6143, 1.0)


func montar() -> bool:
	if not FileAccess.file_exists(ARQ):
		return false
	var j = JSON.parse_string(FileAccess.get_file_as_string(ARQ))
	if j == null:
		return false
	if FileAccess.file_exists(PASTA + "modelos.json"):
		var info = JSON.parse_string(FileAccess.get_file_as_string(PASTA + "modelos.json"))
		if info is Dictionary:
			for m in info:
				for nome in info[m].get("textura_presa", []):
					_presas[nome] = true
				for nome in info[m].get("misturada", []):
					_misturadas[nome] = true
	var por := {}
	for it in j.instancias:
		if not por.has(it.modelo):
			por[it.modelo] = []
		por[it.modelo].append(it)
	for modelo in por:
		var caminho: String = PASTA + String(modelo).get_basename() + ".obj"
		if not ResourceLoader.exists(caminho):
			faltando.append(modelo)
			continue
		var malha: Mesh = load(caminho)
		if malha == null:
			faltando.append(modelo)
			continue
		carregados[modelo] = true
		var bantam: bool = String(modelo).ends_with(".bantam")
		var lista: Array = por[modelo]
		if String(modelo).to_upper().begins_with("WATER_"):
			var bb := malha.get_aabb()
			for it in lista:
				var x := xf(it)
				var c := bb.get_center()
				aguas.append({"inv": x.affine_inverse(), "cx": c.x, "cz": c.z,
					"hx": bb.size.x * 0.5, "hz": bb.size.z * 0.5,
					"y": (x * Vector3(c.x, bb.end.y, c.z)).y, "cor": COR_AGUA})
		_materiais(malha, bantam)
		modelos += 1
		if bantam:
			# bantam = pré-iluminado (sem normal no jogo): MultiMesh com a cor de
			# luz de cada instância (registro +0x40, ~1.0) e sem sombra dinâmica
			var mb := MultiMesh.new()
			mb.transform_format = MultiMesh.TRANSFORM_3D
			mb.use_colors = true
			mb.mesh = malha
			mb.instance_count = lista.size()
			for k in lista.size():
				mb.set_instance_transform(k, xf(lista[k]))
				var c: Array = lista[k].get("cor", [1, 1, 1, 1])
				mb.set_instance_color(k, Color(c[0], c[1], c[2], 1.0))
			var mbi := MultiMeshInstance3D.new()
			mbi.name = String(modelo).get_basename()
			mbi.multimesh = mb
			mbi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mbi)
			mbi.global_transform = Transform3D.IDENTITY
		elif lista.size() == 1:
			var mi := MeshInstance3D.new()
			mi.name = String(modelo).get_basename()
			mi.mesh = malha
			add_child(mi)
			mi.global_transform = xf(lista[0])
		else:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = malha
			mm.instance_count = lista.size()
			for k in lista.size():
				mm.set_instance_transform(k, xf(lista[k]))
			var mmi := MultiMeshInstance3D.new()
			mmi.name = String(modelo).get_basename()
			mmi.multimesh = mm
			add_child(mmi)
			mmi.global_transform = Transform3D.IDENTITY
		instancias += lista.size()
	_colisao(j)
	return instancias > 0


## matriz do jogo da instância -> transformação do remake
static func xf(it: Dictionary) -> Transform3D:
	var l: Array = it.linhas
	var b := Basis(Terrain.dir_do_jogo(_v(l[0])), Terrain.dir_do_jogo(_v(l[1])), Terrain.dir_do_jogo(_v(l[2])))
	return Transform3D(b, Terrain.do_jogo(_v(it.pos)))


static func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


## materiais do .obj como os do carro: cor do vértice (até 2.0) x textura;
## textura com furo (alfa do jogo) vira recorte
func _materiais(malha: Mesh, bantam: bool) -> void:
	for s in malha.get_surface_count():
		var m0 := malha.surface_get_material(s) as StandardMaterial3D
		if m0 == null:
			continue
		var chave := "%d:%s" % [m0.get_instance_id(), bantam]
		if not _mats.has(chave):
			var m := m0.duplicate() as StandardMaterial3D
			m.vertex_color_use_as_albedo = true
			m.vertex_color_is_srgb = true
			var c := m.albedo_color
			m.albedo_color = Color(c.r * COR_K_SRGB, c.g * COR_K_SRGB, c.b * COR_K_SRGB, c.a)
			m.cull_mode = BaseMaterial3D.CULL_DISABLED if bantam else BaseMaterial3D.CULL_BACK
			if bantam:
				# o PS2 não acende bantam: textura x cor do vértice (luz assada) x
				# a luz "Bantam" do Environment.xml (1.0 no sol). Com o sol do
				# Godot as placas de folha de costas pro sol ficavam pretas e as
				# de frente amareladas (prints do Matheus, nov/2026)
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				# folhagem: placa triangular em volta do quadrado da textura,
				# borda transparente; presa na borda (material +0x38 = 5)
				if _presas.has(m0.resource_name):
					m.texture_repeat = false
			if not bantam and _misturadas.has(m0.resource_name):
				# lote transparente do .pingu (+0x00 = 1): mistura pelo alfa da
				# textura (PS2: 0x80 = 1.0; o da poça vai de 0.75 a ~2)
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.render_priority = -1
			m.roughness = 1.0
			m.metallic = 0.0
			m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			if m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and m.albedo_texture and _tem_alfa(m.albedo_texture):
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				m.alpha_scissor_threshold = 0.5
			_mats[chave] = m
		malha.surface_set_material(s, _mats[chave])


static func _tem_alfa(t: Texture2D) -> bool:
	var img := t.get_image()
	if img and img.is_compressed():
		img = img.duplicate()
		img.decompress()
	return img != null and img.detect_alpha() != Image.ALPHA_NONE


## 0x1bb098: a água que contém o ponto (o fundo da roda) e a profundidade
## (superfície - y). Testa antes a da roda anterior (`antes`), como o jogo.
## Dentro = profundidade >= 0 e |x|, |z| no frame da caixa < meia-largura.
## A profundidade sai da última caixa testada, mesmo fora dela (o jogo grava
## assim em veículo+0xaec); sem água nenhuma, 0
func agua_em(p: Vector3, antes) -> Array:
	var prof := 0.0
	var lista: Array = aguas if antes == null else [antes] + aguas
	for a in lista:
		prof = a.y - p.y
		if prof >= 0.0:
			var l: Vector3 = a.inv * p
			if absf(l.x - a.cx) < a.hx and absf(l.z - a.cz) < a.hz:
				return [a, prof]
	return [null, prof]


## aviso pro HUD (vazio = tudo carregado)
func aviso() -> String:
	if instancias == 0:
		return "objetos da pista: rode tools/rx01_objetos.py <unpacked>"
	var f := Array(faltando).filter(func(m): return not String(m).ends_with(".wahoo"))
	return "" if f.is_empty() else "objetos da pista: faltam %d modelos (rode tools/rx01_objetos.py)" % f.size()


## KDt de cada instância no mundo, num corpo estático só
func _colisao(j: Dictionary) -> void:
	var col: Dictionary = j.get("colisao", {})
	var faces := PackedVector3Array()
	for it in j.instancias:
		var c: Dictionary = col.get(it.modelo, {})
		# sem o modelo desenhado (assets/rx01 não gerado) não põe parede invisível
		if not c.has("triangulos") or not carregados.has(it.modelo):
			continue
		var t := xf(it)
		# no mundo do jogo a matriz da instância é linha x matriz; os pontos do
		# KDt estão no frame do modelo do jogo, como os vértices do .obj
		for tri in c.triangulos:
			for k in 3:
				faces.append(t * Vector3(tri[3 * k], tri[3 * k + 1], tri[3 * k + 2]))
	triangulos = faces.size() / 3
	if faces.is_empty():
		return
	var forma := ConcavePolygonShape3D.new()
	forma.backface_collision = true
	forma.set_faces(faces)
	corpo = StaticBody3D.new()
	corpo.name = "Colisao"
	var cs := CollisionShape3D.new()
	cs.shape = forma
	corpo.add_child(cs)
	add_child(corpo)
