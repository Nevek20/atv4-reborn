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
const POCA_ALFA := 0.5                   # NOSSO (ver _materiais), calibrado no print do jogo
const CAMADAS_SEM_ALFA := ["Crowd_ColourChange"]   # sem o "tris" do modelos.json (ver _desenha_camadas)
var _camadas := {}                       # modelo -> [{obj, textura}] (2ª textura pelo 2º UV)
var _misturadas := {}                    # materiais de lote transparente no .pingu (modelos.json)
## água (0x1bb098): uma caixa por instância WATER_* = a caixa do modelo (x, z)
## no frame da instância, superfície = o y mais alto dela. Na RAM do Matheus
## (Renegade_dentro_da_agua.p2s) o objeto em 0x10cad20 tem centro, giro (15°),
## meia-largura 21.01 x 19.88 m e superfície 206.017 = os da WATER_puddle01
var aguas: Array = []                    # [{inv, cx, cz, hx, hz, y, cor}]
## cor da água no objeto (+0x70; o espirro usa com alfa x 0.6), da RAM do RX01
const COR_AGUA := Color(0.5882, 0.6067, 0.6143, 1.0)

## Objetos interativos (Setup/InstanceDatabase.xml -> rx01_objetos.json
## "interativos"; classes registradas no 0x547738). No RX01:
##  - cObjectFlimsyFence (as 2 cercas, GEN de plástico e SAM de madeira):
##    parada (Mass 0) até quebrar. 0x141640: a cada passo soma o impulso das
##    batidas no corpo dela e passando de ShatterImpulse² (2² = 4) chama o
##    0x141908: a cerca sai do mundo e cada Fragment (as 2 peças
##    *_Particle_0x) vem de um estoque de 20 por modelo (0x140318, 0x1406f0)
##    e nasce na pose da cerca, parada (0x140cf0 copia posição e giro).
##  - cObjectTrackBlock (o fardo): corpo solto de Mass 0.1 t, Friction 0.2,
##    ActiveResetTimeout 10 s.
##  - 0x153390 (carro e rodas x cerca parada): impulso de cada contato
##    j = -(1 + e) vn / (1/m + n.((I^-1 (r x n)) x r)), o maior; 0x141a48
##    quebra com j > ShatterImpulse e aí o carro só leva n x min(j, 0.25)
##    (0x54d190) e o contato some: perde no máximo 0.75 km/h (Renegade).
##    Abaixo de 2 (~6 km/h de frente) a cerca segura.
## No remake (aproximações, marcadas): o impulso é medido ANTES do passo da
## física, pra o carro atravessar no mesmo passo em vez de bater numa parede
## e só depois ela sumir; as peças têm 10 kg (o construtor 0x140758 não dá
## massa) e não batem no carro nem na roda (no jogo a cerca não freia,
## Matheus); o fardo volta pro
## lugar 10 s depois de mexido, se o carro não estiver em cima; AngResistance
## vira angular_damp. Faltam: a palha do fardo (ParticleTrigger Impact 0.2)
## e o som de batida (CollisionSample PLASTIC_FENCE / HAY).
const INTERATIVOS := true
const Palha := preload("res://palha.gd")
const Multidao := preload("res://multidao.gd")
var multidao = null                      # multidao.gd
var palha = null                         # palha.gd (palha do fardo)
const MASSA_PECA := 10.0                 # kg, nossa
const ESTOQUE_PECAS := 20                # por modelo (0x140318: até 0x13)
const BIT_CARRO := 1 << 10               # camada só do carro, pra consulta das cercas
const CAMADA := 2                       # bit das cercas: a consulta só olha elas
var carro: RigidBody3D = null            # main.gd põe (o que bate nas cercas)
var cercas: Array = []                   # [{corpo, forma, malha, q, xf, quebrada, normal}]
var blocos: Array = []                   # [{corpo, xf0, mexido, t}]
var pecas := {}                          # modelo -> [RigidBody3D] (o estoque)
var quebradas := 0
var _separando: Array = []               # peças (não batem no carro nem na roda)
var _carro_ant = null
var _dbg := OS.get_environment("DEBUG_CERCA") == "1"
var _col_cache := {}                     # "colisao" do JSON (cascos das peças)
var _cerca_do_corpo := {}                # id do StaticBody3D -> índice em cercas
## 0x153390: depois de quebrar, o carro recebe só n x min(impulso, 0.25)
## (0x54d190) e o contato é jogado fora (0x153658 não cria contato com a
## cerca quebrada): perde no máximo 0.25 / 1.2 t = 0.2 m/s
const EMPURRAO_MAX := 0.25               # t·m/s


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
				if info[m].has("camadas"):
					_camadas[m] = info[m].camadas
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
		if INTERATIVOS and j.get("interativos", {}).has(modelo):
			for it in lista:
				_interativo(it, j.interativos[modelo], malha, j.colisao)
			instancias += lista.size()
			continue
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
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # a sombra já está na textura do chão (terrain.gd)
			add_child(mi)
			mi.global_transform = xf(lista[0])
		else:
			# o MultiMesh do Godot NÃO vira a face com instância espelhada
			# (det < 0: todas as do RX01, matriz do jogo + transposição) e
			# mostrava o lado de dentro (chevron, torre, celeiro 02,
			# arquibancadas; prints do Matheus). O espelho vai pra malha e a
			# instância fica sem ele; o MeshInstance3D sozinho já vira certo
			var esp := _espelhada(malha)
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = esp
			mm.instance_count = lista.size()
			var sx := Transform3D(Basis.from_scale(Vector3(-1, 1, 1)), Vector3.ZERO)
			for k in lista.size():
				var x := xf(lista[k])
				mm.set_instance_transform(k, x * sx if x.basis.determinant() < 0.0 else x)
			var mmi := MultiMeshInstance3D.new()
			mmi.name = String(modelo).get_basename()
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)
			mmi.global_transform = Transform3D.IDENTITY
		if not bantam:
			_desenha_camadas(modelo, lista)
		instancias += lista.size()
	_col_cache = j.get("colisao", {})
	_colisao(j)
	# multidão (RX01_Crowds.wahoo): placas de gente animadas (multidao.gd)
	if j.get("multidao") is Dictionary:
		multidao = Multidao.new()
		multidao.name = "Multidao"
		add_child(multidao)
		if not multidao.montar(j.multidao):
			multidao.queue_free()
			multidao = null
	return instancias > 0


## camada do lote (2ª textura pelo 2º UV, registro do .pingu +0x18): por
## cima do modelo. PORTA: lote com camada = tipo 0x22222222 do renderer de
## pingu (0x28db40; montado no 0x289228 -> 0x289908); a 2ª passada usa a
## palavra de estado 0x36080044 do 0x2897f0 = ALPHA 0x44 ((Cs - Cd) x As + Cd,
## a mistura comum), ABE ligado e teste de alfa >= 1. As = alfa da textura x
## alfa do VÉRTICE (0x80 = 1.0): é ele que diz onde a camada aparece (o
## artista pintou; no arco 40..128, nos celeiros a madeira e a ferrugem ~0.4
## em média). Na pista: as camisetas coloridas da
## US_Bleacher_Wood_02, a sujeira do arco de largada, madeira/ferrugem/
## concreto em celeiros e cabanas e a persiana do alto-falante. O .obj da
## camada perde o alfa do vértice (o import do Godot não lê): modelos.json
## "tris" traz a malha com ele; sem ele (rx01_objetos.py antigo) só as
## camisetas, como antes
func _desenha_camadas(modelo: String, lista: Array) -> void:
	for c in _camadas.get(modelo, []):
		var caminho: String = PASTA + String(c.obj)
		var tex_c: String = PASTA + "tex/" + String(c.textura)
		if not ResourceLoader.exists(tex_c):
			continue
		var malha: Mesh = null
		if c.has("tris"):
			malha = _malha_camada(c.tris)
		elif String(c.textura).get_basename() in CAMADAS_SEM_ALFA and ResourceLoader.exists(caminho):
			malha = load(caminho)
		if malha == null:
			continue
		var tex: Texture2D = load(tex_c)
		var m := ShaderMaterial.new()
		m.shader = _shader_camada()
		m.set_shader_parameter("tex", tex)
		m.set_shader_parameter("k", pow((COR_K_SRGB + 0.055) / 1.055, 2.4))
		m.render_priority = 1
		if lista.size() == 1:
			var mi := MeshInstance3D.new()
			mi.name = "Camada_" + String(c.obj).get_basename()
			mi.mesh = malha
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			mi.global_transform = xf(lista[0])
		else:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = _espelhada(malha)
			mm.instance_count = lista.size()
			var sx := Transform3D(Basis.from_scale(Vector3(-1, 1, 1)), Vector3.ZERO)
			for k in lista.size():
				var x := xf(lista[k])
				mm.set_instance_transform(k, x * sx if x.basis.determinant() < 0.0 else x)
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Camada_" + String(c.obj).get_basename()
			mmi.multimesh = mm
			mmi.material_override = m
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)
			mmi.global_transform = Transform3D.IDENTITY


static var _sh_camada: Shader = null


## a camada: textura x cor do vértice (sRGB, x COR_K como o resto do .pingu),
## alfa = textura x vértice, misturada por cima sem gravar profundidade.
## NOSSO: ela fica no MESMO plano do modelo e o teste de profundidade do Godot
## brigava com ele (piscava ou sumia); vai 0.05% da distância pra perto da
## câmera (5 mm a 10 m), sem mudar nada na tela
static func _shader_camada() -> Shader:
	if _sh_camada == null:
		_sh_camada = Shader.new()
		_sh_camada.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float k = 1.0;
vec3 lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v.xyz *= 0.9995;
	POSITION = PROJECTION_MATRIX * v;
}
void fragment() {
	vec4 t = texture(tex, UV);
	ALBEDO = t.rgb * lin(COLOR.rgb) * k;
	ALPHA = t.a * COLOR.a;
	ROUGHNESS = 1.0;
}
"""
	return _sh_camada


## malha da camada pelo "tris" do modelos.json (por vértice: x y z, normal,
## r g b do .obj, alfa, s t; já na ordem de giro do Godot)
static func _malha_camada(t: Array) -> ArrayMesh:
	var n := t.size() / 12
	var v := PackedVector3Array()
	var nr := PackedVector3Array()
	var cor := PackedColorArray()
	var uv := PackedVector2Array()
	v.resize(n)
	nr.resize(n)
	cor.resize(n)
	uv.resize(n)
	for i in n:
		var k := i * 12
		v[i] = Vector3(t[k], t[k + 1], t[k + 2])
		nr[i] = Vector3(t[k + 3], t[k + 4], t[k + 5])
		cor[i] = Color(t[k + 6], t[k + 7], t[k + 8], t[k + 9])
		uv[i] = Vector2(t[k + 10], t[k + 11])
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = v
	a[Mesh.ARRAY_NORMAL] = nr
	a[Mesh.ARRAY_COLOR] = cor
	a[Mesh.ARRAY_TEX_UV] = uv
	var m := ArrayMesh.new()
	if n > 0:
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return m


## cópia da malha espelhada em x (x negado, ordem dos vértices trocada),
## mesmos materiais: instância espelhada x esta = sem espelho
static func _espelhada(malha: Mesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in malha.get_surface_count():
		var a := malha.surface_get_arrays(s)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		for i in v.size():
			v[i].x = -v[i].x
		a[Mesh.ARRAY_VERTEX] = v
		if a[Mesh.ARRAY_NORMAL] != null:
			var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			for i in n.size():
				n[i].x = -n[i].x
			a[Mesh.ARRAY_NORMAL] = n
		if a[Mesh.ARRAY_TANGENT] != null:
			var t: PackedFloat32Array = a[Mesh.ARRAY_TANGENT]
			for i in range(0, t.size(), 4):
				t[i] = -t[i]
				t[i + 3] = -t[i + 3]
			a[Mesh.ARRAY_TANGENT] = t
		if a[Mesh.ARRAY_INDEX] != null:
			var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
			for i in range(0, idx.size(), 3):
				var tmp := idx[i + 1]
				idx[i + 1] = idx[i + 2]
				idx[i + 2] = tmp
			a[Mesh.ARRAY_INDEX] = idx
		else:
			# sem índice: troca o 2º e o 3º vértice de cada triângulo em tudo
			for k in a.size():
				var arr = a[k]
				if arr == null or k == Mesh.ARRAY_INDEX:
					continue
				var por := 1
				if k == Mesh.ARRAY_TANGENT:
					por = 4
				elif k in [Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
					continue
				var nv := v.size()
				if arr.size() != nv * por:
					continue
				for i in range(0, nv - 2, 3):
					for c in por:
						var t1 = arr[(i + 1) * por + c]
						arr[(i + 1) * por + c] = arr[(i + 2) * por + c]
						arr[(i + 2) * por + c] = t1
				a[k] = arr
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		out.surface_set_material(s, malha.surface_get_material(s))
	return out


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
		if m0 == null or m0.has_meta("rx01"):
			# já é um material nosso: a mesma malha volta a cada cerca quebrada
			# (load() devolve a do cache) e o x2 da cor ia acumulando (x4, x8:
			# pedaços amarelos e brancos, print do Matheus)
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
				# tela da torre (TEMP_Wire_fence): o modelo só tem uma face e no
				# jogo ela aparece dos 2 lados (Matheus, nov/2026). A poça NÃO:
				# com as 2 faces a parte de baixo da malha aparecia por cima
				# (mancha escura recortada, print do Matheus)
				if not String(m0.resource_name).to_lower().contains("water"):
					m.cull_mode = BaseMaterial3D.CULL_DISABLED
				else:
					# poça: o alfa da textura (~0x80) pela conta do PS2 dá ~92%
					# opaca, mas no jogo ela é bem transparente (print do
					# Matheus, nov/2026). O modo de mistura do lote (+0x10 = 4)
					# não foi achado no exe; NOSSO: alfa lido de 0..255 (~50%)
					m.albedo_color.a *= POCA_ALFA
			m.roughness = 1.0
			m.metallic = 0.0
			m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			if m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and m.albedo_texture and _tem_alfa(m.albedo_texture):
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				m.alpha_scissor_threshold = 0.5
				# recorte num .pingu = placa de uma face só (os torcedores da
				# cabine do locutor, WahooCrowdTex01): no jogo aparece dos 2
				# lados (print do Matheus, nov/2026)
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.set_meta("rx01", true)
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


## base ortonormal sem espelho nem escala (a do jogo tem determinante -1 no
## remake): o corpo usa ela e a malha e a forma vão no frame dela
static func _so_giro(x: Transform3D) -> Transform3D:
	var b := x.basis.orthonormalized()
	if b.determinant() < 0.0:
		b.x = -b.x
	return Transform3D(b, x.origin)


func _forma(col: Dictionary, chave: String, x: Transform3D, corpo_xf: Transform3D) -> ConvexPolygonShape3D:
	var c: Dictionary = col.get(chave, {})
	if not c.has("vertices"):
		return null
	var pts := PackedVector3Array()
	var inv := corpo_xf.affine_inverse()
	for v in c.vertices:
		pts.append(inv * (x * Vector3(v[0], v[1], v[2])))
	var f := ConvexPolygonShape3D.new()
	f.points = pts
	return f


func _malha_no(malha: Mesh, it: Dictionary, local: Transform3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = malha
	mi.transform = local
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _interativo(it: Dictionary, q: Dictionary, malha: Mesh, col: Dictionary) -> void:
	var x := xf(it)
	var cx := _so_giro(x)
	var forma := _forma(col, it.modelo, x, cx)
	if forma == null:
		return
	var mat := PhysicsMaterial.new()
	mat.friction = q.get("atrito", 0.2)
	mat.bounce = q.get("dureza", 0.2)       # Hardness = restituição (0x142698 -> corpo+0xbc)
	if q.classe == "cObjectFlimsyFence":
		var sb := StaticBody3D.new()
		sb.name = "Cerca"
		sb.collision_layer = 1 | CAMADA
		sb.physics_material_override = mat
		# contato = as ESFERAS do .hsc (como o casco dos carros): numa batida de
		# ponta a normal vai de centro a centro (com a caixa fina o Godot dava
		# a normal da placa, impulso ~0, e as cercas de lado viravam parede)
		var esferas: Array = []
		var inv := cx.affine_inverse()
		for e in col[it.modelo].get("esferas", []):
			var cs := CollisionShape3D.new()
			var sp := SphereShape3D.new()
			sp.radius = e[3]
			cs.shape = sp
			cs.position = inv * (x * Vector3(e[0], e[1], e[2]))
			sb.add_child(cs)
			esferas.append(cs)
		var cs = esferas
		var mi := _malha_no(malha, it, cx.affine_inverse() * x)
		sb.add_child(mi)
		add_child(sb)
		sb.global_transform = cx
		# normal da cerca = eixo mais fino da caixa (no mundo)
		var bb := AABB()
		for v in col[it.modelo].vertices:
			bb = bb.expand(Vector3(v[0], v[1], v[2]))
		var eixos := [x.basis.x, x.basis.y, x.basis.z]
		var tam := [bb.size.x, bb.size.y, bb.size.z]
		var fino := 0 if tam[0] <= tam[2] else 2
		_cerca_do_corpo[sb.get_instance_id()] = cercas.size()
		cercas.append({"corpo": sb, "forma": cs, "malha": mi, "q": q, "xf": x, "it": it,
			"quebrada": false, "normal": (eixos[fino] as Vector3).normalized()})
	else:
		var rb := RigidBody3D.new()
		rb.name = "Bloco"
		rb.mass = maxf(q.get("massa", 0.1), 0.001) * 1000.0
		rb.physics_material_override = mat
		var ang: Array = q.get("ang", [0, 0, 0])
		rb.angular_damp = maxf(ang[0], maxf(ang[1], ang[2]))
		rb.can_sleep = true
		rb.sleeping = true
		var cs := CollisionShape3D.new()
		cs.shape = forma
		rb.add_child(cs)
		rb.add_child(_malha_no(malha, it, cx.affine_inverse() * x))
		add_child(rb)
		rb.global_transform = cx
		var pq: Dictionary = q.get("particula", {})
		if not pq.get("pontos", []).is_empty():
			rb.contact_monitor = true         # impulso dos contatos (ParticleTrigger)
			rb.max_contacts_reported = 8
		blocos.append({"corpo": rb, "xf0": cx, "mexido": false, "t": 0.0,
			"reset": float(q.get("reset", 0.0)), "q": q, "malha_local": cx.affine_inverse() * x,
			"acum": [0.0, 0.0, 0.0, 0.0], "emite": 0.0, "som_t": 0.0})
		if palha == null and not pq.get("pontos", []).is_empty() and Palha.pronta():
			palha = Palha.new()
			palha.name = "Palha"
			add_child(palha)
			palha.montar(pq)


## 0x141640 antes do passo: o carro vai encostar na cerca neste passo? com
## impulso (t·m/s, massa x velocidade contra a cerca) > ShatterImpulse ela
## quebra antes da física resolver o contato (o carro atravessa); abaixo
## disso ela segura como parede
func _physics_process(dt: float) -> void:
	var tem_carro := carro != null and is_instance_valid(carro)
	var v: Vector3 = carro.linear_velocity if tem_carro else Vector3.ZERO
	var pc: Vector3 = carro.global_position if tem_carro else Vector3(INF, INF, INF)
	var espaco := get_world_3d().direct_space_state
	for c in cercas:
		if not tem_carro:
			break
		if c.quebrada or (c.xf as Transform3D).origin.distance_to(pc) > 8.0 + v.length() * dt:
			continue
		# só o carro (bit próprio, ninguém mais usa)
		carro.collision_layer |= BIT_CARRO
		var imp := 0.0
		var n_imp := Vector3.ZERO
		var p_imp := Vector3.ZERO
		var corpo_xf: Transform3D = (c.corpo as Node3D).global_transform
		for cs in c.forma:
			var qp := PhysicsShapeQueryParameters3D.new()
			qp.shape = (cs as CollisionShape3D).shape
			# a esfera andando contra o carro = o carro andando até ela neste passo;
			# varre o caminho todo (a esfera tem 10 cm e o carro anda 33 cm por
			# passo a 60 km/h: olhando só o fim do passo ela pulava o contato)
			qp.transform = Transform3D(Basis.IDENTITY, corpo_xf * (cs as Node3D).position)
			qp.collision_mask = BIT_CARRO
			qp.motion = -v * dt * 1.5
			var f: PackedFloat32Array = espaco.cast_motion(qp)
			if f.size() < 2 or f[1] >= 1.0:
				continue
			qp.transform = qp.transform.translated(qp.motion * f[1])
			qp.motion = Vector3.ZERO
			var info: Dictionary = espaco.get_rest_info(qp)
			if info.is_empty() or info.collider_id != carro.get_instance_id():
				continue
			# 0x153390: o maior impulso entre os contatos, contra corpo parado
			var j := impulso_contato(-(info.normal as Vector3).normalized(), info.point)
			if _dbg:
				print("    cerca f %.2f n %s j %.2f v %.1f" % [f[1], info.normal, j, v.length() * 3.6])
			if j > imp:
				imp = j
				n_imp = -(info.normal as Vector3).normalized()
				p_imp = info.point
		_bate_cerca(c, imp, n_imp, p_imp)
	# peças não batem no carro (nossa, pelo que o Matheus vê no jogo: a cerca
	# laranja não freia). Carro novo (menu): exceção com todas
	if tem_carro and carro != _carro_ant:
		_carro_ant = carro
		for pr in _separando:
			if is_instance_valid(pr):
				(pr as RigidBody3D).add_collision_exception_with(carro)
	for b in blocos:
		var rb: RigidBody3D = b.corpo
		_bloco_batida(b, dt)
		if not b.mexido and rb.global_position.distance_to((b.xf0 as Transform3D).origin) > 0.5:
			b.mexido = true
			b.t = 0.0
		if b.mexido and b.reset > 0.0:
			b.t += dt
			if b.t >= b.reset and rb.global_position.distance_to(pc) > 4.0:
				# ActiveResetTimeout: volta pro lugar
				rb.global_transform = b.xf0
				b.erase("v_ant")
				rb.linear_velocity = Vector3.ZERO
				rb.angular_velocity = Vector3.ZERO
				b.mexido = false
	if palha:
		palha.passo(dt)


## 0x153390: impulso do contato do carro com um corpo parado (a cerca), em
## t·m/s: j = -(1 + e) vn / (1/m + n . ((I^-1 (r x n)) x r)), vn = velocidade
## do ponto na normal (n aponta pra fora da cerca, pro carro), e = a
## Restitution do carro (+0xbc)
func impulso_contato(n: Vector3, ponto: Vector3) -> float:
	var com: Vector3 = carro.global_transform * carro.center_of_mass
	var r := ponto - com
	var vn := (carro.linear_velocity + carro.angular_velocity.cross(r)).dot(n)
	if vn >= 0.0:
		return 0.0
	var e := 0.0
	if carro.physics_material_override:
		e = carro.physics_material_override.bounce
	var ii: Basis = carro.get_inverse_inertia_tensor() * 1000.0     # 1/(t·m²)
	var den := 1000.0 / carro.mass + n.dot((ii * r.cross(n)).cross(r))
	return -(1.0 + e) * vn / den


## 0x141a48 + 0x153390: impulso > ShatterImpulse quebra; aí o carro leva o
## empurrão de no máximo 0.25 t·m/s (giro com o braço x 0.2) e atravessa
func _bate_cerca(c: Dictionary, imp: float, n: Vector3, ponto: Vector3) -> bool:
	if imp > 0.0:
		_som(c, String(c.q.get("som", "")))
	var lim := float(c.q.get("quebra", 0.0))
	if c.quebrada or lim <= 0.0 or imp <= lim:
		return false
	quebrar(c)
	var com: Vector3 = carro.global_transform * carro.center_of_mass
	var dj := n * minf(imp, EMPURRAO_MAX) * 1000.0                  # kg·m/s
	carro.apply_central_impulse(dj)
	carro.apply_torque_impulse(((ponto - com) * 0.2).cross(dj))
	return true


## som da batida (0x36b998 em cada contato do 0x153390): CollisionSample do
## objeto; o jogo repete por quadro (até 4 por quadro): aqui no máximo um a
## cada MinRetriggerTime do <Collisions> (0.2 s) por objeto (nossa)
func _som(o: Dictionary, amostra: String) -> void:
	if amostra == "" or carro == null or not is_instance_valid(carro) or carro.get("sfx") == null:
		return
	var agora := Time.get_ticks_msec() / 1000.0
	var sfx = carro.sfx
	if not is_instance_valid(sfx):
		return
	if agora - float(o.get("som_ultimo", -10.0)) < float(sfx.colisoes.get("MinRetriggerTime", 0.2)):
		return
	o["som_ultimo"] = agora
	sfx.batida_objeto(amostra)


## fardo: impulso dos contatos do passo (t·m/s) > Impulse do ParticleTrigger
## liga a palha por Timeout s; batida com o carro toca o CollisionSample (HAY)
func _bloco_batida(b: Dictionary, dt: float) -> void:
	var rb: RigidBody3D = b.corpo
	if not rb.contact_monitor:
		return
	var pq: Dictionary = b.q.get("particula", {})
	# impulso que o fardo recebeu no passo (t·m/s) = massa x (variação da
	# velocidade - gravidade): o Godot não informa o impulso dos contatos
	var v := rb.linear_velocity
	var g := Vector3(0, -float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)), 0)
	var imp := 0.0
	if b.has("v_ant") and not rb.sleeping:
		imp = rb.mass / 1000.0 * (v - (b.v_ant as Vector3) - g * dt).length()
	b.v_ant = v
	if imp > float(pq.get("impulso", 0.2)):
		b.emite = float(pq.get("espera", 0.1))
		var no_carro := false
		var st := PhysicsServer3D.body_get_direct_state(rb.get_rid())
		if st and carro:
			for i in st.get_contact_count():
				if st.get_contact_collider_object(i) == carro:
					no_carro = true
		if no_carro or (carro and is_instance_valid(carro) and rb.global_position.distance_to(carro.global_position) < 4.0):
			_som(b, String(b.q.get("som", "")))
		if _dbg:
			print("    fardo imp %.3f carro %s v %.1f" % [imp, no_carro, v.length()])
	if b.emite > 0.0 and palha:
		palha.emitir(b, minf(dt, b.emite))
		b.emite -= dt


## roda do carro (raio da suspensão) encostando numa cerca: o jogo trata as
## rodas pelo mesmo 0x153390 (0x154088). true = quebrou (refazer o raio)
func roda_na_cerca(corpo: Object, ponto: Vector3, normal: Vector3) -> bool:
	if corpo == null or not _cerca_do_corpo.has(corpo.get_instance_id()):
		return false
	var c: Dictionary = cercas[_cerca_do_corpo[corpo.get_instance_id()]]
	if _dbg:
		print("    roda na cerca %d: n %s j %.2f" % [_cerca_do_corpo[corpo.get_instance_id()], normal, impulso_contato(normal.normalized(), ponto)])
	return _bate_cerca(c, impulso_contato(normal.normalized(), ponto), normal.normalized(), ponto)


## peças que ainda não batem no carro: o raio da roda também ignora
func ignorar_roda() -> Array:
	var r := []
	for p in _separando:
		if is_instance_valid(p):
			r.append((p as RigidBody3D).get_rid())
	return r


## 0x141908: a cerca sai do mundo e as peças nascem na pose dela, paradas
func quebrar(c: Dictionary) -> void:
	c.quebrada = true
	quebradas += 1
	for cs in c.forma:
		(cs as CollisionShape3D).disabled = true
	(c.corpo as StaticBody3D).collision_layer = 0
	(c.malha as Node3D).visible = false
	var j_col: Dictionary = _col_cache
	for p in c.q.get("pecas", []):
		var caminho: String = PASTA + String(p.modelo).get_basename() + ".obj"
		if not ResourceLoader.exists(caminho):
			continue
		var malha: Mesh = load(caminho)
		_materiais(malha, true)
		var x: Transform3D = c.xf
		var cx := _so_giro(x)
		var forma := _forma(j_col, String(p.casco) + ".casco", x, cx)
		if forma == null:
			continue
		var lista: Array = pecas.get(p.modelo, [])
		var rb: RigidBody3D
		if lista.size() >= ESTOQUE_PECAS:
			rb = lista.pop_front()             # estoque cheio: reusa a mais velha (nossa)
			for ch in rb.get_children():
				ch.queue_free()
		else:
			rb = RigidBody3D.new()
			rb.name = "Peca"
			rb.mass = MASSA_PECA
			var pm := PhysicsMaterial.new()
			pm.friction = c.q.get("atrito", 0.2)
			rb.physics_material_override = pm
			add_child(rb)
		var cs := CollisionShape3D.new()
		cs.shape = forma
		rb.add_child(cs)
		rb.add_child(_malha_no(malha, c.it, cx.affine_inverse() * x))
		rb.global_transform = cx
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
		# a peça não bate no carro (nossa): nascendo dentro dele (na pose da
		# cerca) freava de 61 pra 13 km/h, e solta no chão logo depois da
		# batida em ângulo tirava mais 4 a 12 km/h. Rola e cai só no chão
		if not _separando.has(rb):
			_separando.append(rb)
		if carro and is_instance_valid(carro):
			rb.add_collision_exception_with(carro)
		lista.append(rb)
		pecas[p.modelo] = lista


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
