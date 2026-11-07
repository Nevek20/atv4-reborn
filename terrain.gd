extends Node3D
## Terreno da pista RX_01 tirado do stream do jogo (STREAMT/RX/RX01.000) por
## tools/extrair_material.py. Grade de SIZE x SIZE pontos, 1 m entre eles.
## Bate com a RAM dos save states da largada: altura do contato das rodas a
## 0.1 mm e material igual (tests/teste_chao.gd).
##   rx01_height.bin   float32, altura do jogo (FUN_00299a60)
##   rx01_material.bin u8, índice i do material = Material_(i+1) do
##                     Levels/RX_01/Env/Materials.xml (data/materials_rx01.xml);
##                     célula de 2 m (entrada E do tile, byte0 & 0xF)
## Os .bin estão no layout do jogo (linha = z do jogo, coluna = x).
##
## O jogo é mão esquerda e o Godot mão direita, então o mundo passa por um
## espelho: remake (X, Y, Z) = (z - 1024, y, x) do jogo (do_jogo). É uma
## transposição (x <-> z), feita na carga. Com ela o triângulo de cada célula
## continua pela diagonal (i+1, j)-(i, j+1), igual ao jogo e ao
## HeightMapShape3D do Godot (Godot Physics e Jolt, testado). Inverter só o x
## trocaria a diagonal.

@export var height_path := "res://assets/terrain/rx01_height.bin"
@export var material_path := "res://assets/terrain/rx01_material.bin"
@export var materials_xml := "res://data/materials_rx01.xml"
@export var texture_path := "res://assets/terrain/rx01_terrain.jpg"
## melhoria nossa: textura do chão ampliada (Upscayl do Matheus) em
## assets/terrain/hd/ com o nome da original, .png ou .jpg (fora do git); sem
## ela (ou false) usa a do jogo (2048 x 2048, ~1 m por pixel)
const CHAO_HD := true
@export var size := 1025          # pontos por lado
@export var mesh_step := 2        # malha visual usa 1 ponto a cada N (colisão usa todos)

var heights := PackedFloat32Array()   # já no remake: [Z * size + X]
var mat_map := PackedByteArray()
var materials := []               # atributos de cada Material_N do XML (N - 1)
const Z0 := 1024.0                # z do jogo na linha 0 dos .bin


## ponto do mundo do jogo -> remake
static func do_jogo(p: Vector3) -> Vector3:
	return Vector3(p.z - Z0, p.y, p.x)


## direção do mundo do jogo -> remake
static func dir_do_jogo(d: Vector3) -> Vector3:
	return Vector3(d.z, d.y, d.x)


## ponto do remake -> mundo do jogo
static func pro_jogo(p: Vector3) -> Vector3:
	return Vector3(p.z, p.y, p.x + Z0)


func _ready() -> void:
	var f := FileAccess.open(height_path, FileAccess.READ)
	if f == null:
		push_error("Não achei %s" % height_path)
		return
	heights = _transpor(f.get_buffer(size * size * 4), Image.FORMAT_RF).to_float32_array()
	f.close()
	f = FileAccess.open(material_path, FileAccess.READ)
	if f:
		mat_map = _transpor(f.get_buffer(size * size), Image.FORMAT_R8)
		f.close()
	materials = load_materials(materials_xml)
	_build_collision()
	_build_mesh()


## grade do jogo [z * size + x] -> remake [Z * size + X], com X = z e Z = x
## do jogo (troca linha e coluna)
func _transpor(dados: PackedByteArray, formato: Image.Format) -> PackedByteArray:
	var img := Image.create_from_data(size, size, false, formato, dados)
	img.rotate_90(CLOCKWISE)
	img.flip_x()
	return img.get_data()


## Material_1..N do Materials.xml da pista, em ordem: os atributos e, em
## "pneu", o atrito de cada classe de pneu ("FRICTION TYRE <classe> <valor>"
## do <Overrides>)
static func load_materials(path: String) -> Array:
	var out := []
	var x := XMLParser.new()
	if x.open(path) != OK:
		push_error("Não achei %s" % path)
		return out
	var i := -1
	while x.read() == OK:
		if x.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		var nome := x.get_node_name()
		if nome.begins_with("Material_"):
			i = nome.trim_prefix("Material_").to_int() - 1
			var at := {"pneu": {}}
			for k in x.get_attribute_count():
				at[x.get_attribute_name(k)] = x.get_attribute_value(k)
			while out.size() <= i:
				out.append({"pneu": {}})
			out[i] = at
		elif nome == "DustColour" and i >= 0:
			# cor da poeira (registro +0x10): a lama das rodas puxa pra ela (0x2242d0)
			out[i]["DustColour"] = Color(x.get_named_attribute_value_safe("R").to_float(),
				x.get_named_attribute_value_safe("G").to_float(),
				x.get_named_attribute_value_safe("B").to_float(),
				x.get_named_attribute_value_safe("A").to_float())
		elif nome == "Overrides" and i >= 0:
			for k in x.get_attribute_count():
				var p := x.get_attribute_value(k).split(" ", false)
				if p.size() == 4 and p[0] == "FRICTION" and p[1] == "TYRE":
					out[i].pneu[p[2]] = p[3].to_float()
	return out


func height_at(x: float, z: float) -> float:
	# altura no triângulo da célula, diagonal (i+1, j)-(i, j+1) como o jogo
	x = clampf(x, 0.0, size - 1.001)
	z = clampf(z, 0.0, size - 1.001)
	var ix := int(x)
	var iz := int(z)
	var fx := x - ix
	var fz := z - iz
	var h00 := heights[iz * size + ix]
	var h10 := heights[iz * size + ix + 1]
	var h01 := heights[(iz + 1) * size + ix]
	var h11 := heights[(iz + 1) * size + ix + 1]
	if fx + fz <= 1.0:
		return h00 + (h10 - h00) * fx + (h01 - h00) * fz
	return h11 + (h01 - h11) * (1.0 - fx) + (h10 - h11) * (1.0 - fz)


## índice do material do chão no ponto (x, z) do remake (-1 sem mapa)
func material_at(x: float, z: float) -> int:
	if mat_map.is_empty():
		return -1
	var ix := clampi(floori(x), 0, size - 1)
	var iz := clampi(floori(z), 0, size - 1)
	return mat_map[iz * size + ix]


## WheelJitter do material (0x202760); -1 = sem material
func wheel_jitter(m: int, fallback: float) -> float:
	if m < 0 or m >= materials.size():
		return fallback
	return float(materials[m].get("WheelJitter", fallback))


## atrito do pneu no material (registro veículo+0xd0+i*0x60, campo 0; conferido
## na RAM: DIRT_BUDGET dá 0.80 na terra, 0.69 fora da pista e 1.10 no
## asfalto). Sem override da classe vale o Friction do material (1.0 em todos
## do RX_01). Roda sem material (-1): 1.0 (0x20d568).
func atrito(m: int, pneu: String) -> float:
	if m < 0 or m >= materials.size():
		return 1.0
	var mat: Dictionary = materials[m]
	if mat.pneu.has(pneu):
		return mat.pneu[pneu]
	return float(mat.get("Friction", 1.0))


## Damping do material (registro veículo+0xd0+i*0x60, +0x08; conferido na
## RAM): entra no arrasto do chão (0x20e5e8). 0.2 fora da pista, 0.1 no
## cascalho, 0 na terra comum e no asfalto. Roda sem material (-1): 0.
func amortecimento(m: int) -> float:
	if m < 0 or m >= materials.size():
		return 0.0
	return float(materials[m].get("Damping", 0.0))


## WheelDirtRate do material (registro +0x54): quanto suja o carro (0x223e68)
func taxa_sujeira(m: int) -> float:
	if m < 0 or m >= materials.size():
		return 0.0
	return float(materials[m].get("WheelDirtRate", 0.0))


## som do pneu no material (atributo SFX: Dirt, Tarmac, Gravel, Grass, Snow);
## o 0x377ce0 liga o material i da pista ao material de som desse nome
func sfx(m: int) -> String:
	if m < 0 or m >= materials.size():
		return "Default"
	return str(materials[m].get("SFX", "Default"))


## nome curto do material: "COMMON_3(TARMAC/COMMON)*" -> "TARMAC/COMMON"
func material_name(m: int) -> String:
	if m < 0 or m >= materials.size():
		return "?"
	var n: String = materials[m].get("Name", "?")
	var a := n.find("(")
	var b := n.find(")")
	return n.substr(a + 1, b - a - 1) if a >= 0 and b > a else n


func _build_collision() -> void:
	var shape := HeightMapShape3D.new()
	shape.map_width = size
	shape.map_depth = size
	shape.map_data = heights
	var cs := CollisionShape3D.new()
	cs.shape = shape
	var body := StaticBody3D.new()
	var pm := PhysicsMaterial.new()
	pm.friction = 1.0
	body.physics_material_override = pm
	body.add_child(cs)
	# o HeightMapShape3D fica centralizado na origem do nó
	body.position = Vector3((size - 1) / 2.0, 0.0, (size - 1) / 2.0)
	add_child(body)


func _build_mesh() -> void:
	@warning_ignore("integer_division")
	var n := (size - 1) / mesh_step + 1     # divisão inteira de propósito
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(n * n)
	norms.resize(n * n)
	uvs.resize(n * n)
	var span := float(size - 1)
	for j in n:
		var z := j * mesh_step
		for i in n:
			var x := i * mesh_step
			var h := heights[z * size + x]
			var k := j * n + i
			verts[k] = Vector3(x, h, z)
			uvs[k] = Vector2(z / span, x / span)    # a textura está no layout do jogo
			# normal pela diferença central
			var xl := maxi(x - 1, 0)
			var xr := mini(x + 1, size - 1)
			var zu := maxi(z - 1, 0)
			var zd := mini(z + 1, size - 1)
			var dx := heights[z * size + xr] - heights[z * size + xl]
			var dz := heights[zd * size + x] - heights[zu * size + x]
			norms[k] = Vector3(-dx / float(xr - xl), 1.0, -dz / float(zd - zu)).normalized()

	var idx := PackedInt32Array()
	idx.resize((n - 1) * (n - 1) * 6)
	var p := 0
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			var b := a + 1
			var c := a + n
			var d := c + 1
			idx[p] = a; idx[p + 1] = b; idx[p + 2] = c
			idx[p + 3] = b; idx[p + 4] = d; idx[p + 5] = c
			p += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var textura: Texture2D = _textura_hd() if CHAO_HD else null
	if textura == null:
		textura = _carrega(texture_path)
	print("chão: ", textura_usada)
	var mat := ShaderMaterial.new()
	mat.shader = _shader_chao()
	if textura:
		mat.set_shader_parameter("tex", textura)
	mat.set_shader_parameter("sombra", SOMBRA)
	var det := _detalhe()
	if det:
		mat.set_shader_parameter("detalhe", det)
		mat.set_shader_parameter("det_forca", DETALHE_FORCA if not OS.has_environment("DETALHE") else float(OS.get_environment("DETALHE")))
		mat.set_shader_parameter("det_metros", DETALHE_M if not OS.has_environment("DETALHE_M") else float(OS.get_environment("DETALHE_M")))
		var some := DETALHE_SOME
		if OS.has_environment("DETALHE_SOME"):
			var ps := OS.get_environment("DETALHE_SOME").split(",")
			some = Vector2(float(ps[0]), float(ps[1]))
		mat.set_shader_parameter("det_some", some)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)


var textura_usada := "nenhuma (cor lisa)"

## A textura do chão já vem com a luz assada (sombra do arco, das
## arquibancadas e dos morros nela): o jogo desenha a cor dela direto. Medido
## no print do Matheus na largada (nov/2026): chão 78, 72, 66 x textura 85, 75,
## 65 ali. Antes o Godot iluminava de novo (sol 1.2 + ambiente 0.8 + filmic):
## o chão saía ~105 cinza frio. Sem luz nem ambiente do Godot; só a sombra
## dinâmica (o carro) escurece. Os objetos não fazem sombra dinâmica (a deles
## já está na textura).
## SOMBRA: NOSSO, medida no mesmo print (chão na sombra do carro / no sol =
## 0.66 na tela; o DynamicShadow Intensity 0.5 / InShadowMultiply 0.8 do
## Environment.xml não foram achados no exe)
const SOMBRA := 0.66
static var _sh_chao: Shader = null


## Detalhe do chão (PORTA parcial, nov/2026, "o chão do jogo tem mais
## qualidade", prints do Matheus): o renderer do relevo (0x1eb758) carrega a
## textura "detail" da pasta Env da pista (RX01: DETAIL.bog, 128 x 128, cinza
## fixo com o desenho no ALFA, 12..190 do PS2) e a repete por cima da textura
## do chão. env.header +0x2c = 5.0 vai pro renderer +0x1e4 e o 0x29ed98 faz
## 5 x 16 x (+0x1e8): lido como 80 repetições por bloco de 128 m (1.6 m cada).
## O jeito de misturar fica no VU1 (não achado). NOSSO: fator = 1 + força x
## (alfa / média - 1), média do brilho igual (a cor média já batia com o
## jogo) e só o grão; DETALHE_FORCA calibrada no desvio do grão fino dos
## prints do jogo (perto do carro ~13 de 255, largada ~11). DETALHE=x e
## DETALHE_M=x trocam (diagnóstico). Sem assets/terrain/rx01_detalhe.png
## (tools/rx01_objetos.py) o chão fica liso como antes.
const DETALHE_ARQ := "res://assets/terrain/rx01_detalhe.png"
const DETALHE_M := 2.4
const DETALHE_FORCA := 0.55
const DETALHE_SOME := Vector2(4.0, 20.0)    # NOSSO: apaga de 4 a 20 m (o grão do jogo some antes que o nosso)


func _detalhe() -> Texture2D:
	if not FileAccess.file_exists(DETALHE_ARQ):
		return null
	var img := Image.load_from_file(ProjectSettings.globalize_path(DETALHE_ARQ))
	if img == null or img.is_empty():
		return null
	img.convert(Image.FORMAT_L8)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)



static func _shader_chao() -> Shader:
	if _sh_chao == null:
		_sh_chao = Shader.new()
		_sh_chao.code = """
shader_type spatial;
render_mode cull_disabled, ambient_light_disabled, specular_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float sombra = 0.66;
uniform sampler2D detalhe : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float det_forca = 0.0;
uniform float det_metros = 1.6;
uniform vec2 det_some = vec2(4.0, 20.0);   // de / até (m da câmera)
const float DET_MEDIA = 0.3594;   // média do alfa do DETAIL.bog do RX01 (91.6 / 255)
varying vec3 mundo;
void vertex() {
	mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec3 c = texture(tex, UV).rgb;
	float d = texture(detalhe, mundo.xz / det_metros).r;
	// fator na cor da tela (sRGB): mesmo brilho médio, só o grão
	float longe = clamp((length(VERTEX) - det_some.x) / (det_some.y - det_some.x), 0.0, 1.0);
	float f = max(1.0 + det_forca * (1.0 - longe) * (d / DET_MEDIA - 1.0), 0.0);
	ALBEDO = c * pow(f, 2.2);
	ROUGHNESS = 1.0;
}
void light() {
	// sem luz: a cor da textura no sol, x sombra (na tela, sRGB) na sombra
	float k = pow(sombra, 2.2);
	DIFFUSE_LIGHT += vec3(mix(k, 1.0, ATTENUATION));
}
"""
	return _sh_chao


## a versão ampliada: qualquer imagem em assets/terrain/hd/ com o nome da
## original no começo (o Upscayl põe "_upscayl_2x..." no fim). Lida direto do
## arquivo pelo CONTEÚDO (PNG, JPG ou WEBP, seja qual for a extensão), sem
## depender do import do Godot; null se não tiver
func _textura_hd() -> Texture2D:
	var pasta := texture_path.get_base_dir() + "/hd/"
	var nome := texture_path.get_file().get_basename().to_lower()
	var d := DirAccess.open(pasta)
	if d == null:
		return null
	for f in d.get_files():
		if f.to_lower().begins_with(nome) and not f.ends_with(".import"):
			var t := _do_arquivo(pasta + f)
			if t:
				return t
	return null


## pelo import do Godot; se falhar (arquivo trocado sem reimportar), direto
func _carrega(caminho: String) -> Texture2D:
	if ResourceLoader.exists(caminho):
		var t = load(caminho)
		if t is Texture2D:
			textura_usada = caminho
			return t
	return _do_arquivo(caminho)


func _do_arquivo(caminho: String) -> Texture2D:
	var b := FileAccess.get_file_as_bytes(caminho)
	if b.size() < 12:
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if b[0] == 0x89 and b[1] == 0x50:
		err = img.load_png_from_buffer(b)
	elif b[0] == 0xFF and b[1] == 0xD8:
		err = img.load_jpg_from_buffer(b)
	elif b[0] == 0x52 and b[8] == 0x57:
		err = img.load_webp_from_buffer(b)
	if err != OK:
		push_warning("chão: não consegui ler %s" % caminho)
		return null
	# na placa comprimida (DXT1/BC1, 8x menor): 4096 x 4096 = ~11 MB com os
	# mipmaps no lugar de ~85 MB cru; o import do Godot faria o mesmo
	var t0 := Time.get_ticks_msec()
	img.convert(Image.FORMAT_RGB8)
	img.generate_mipmaps()
	if img.get_width() > 2048:
		img.compress(Image.COMPRESS_S3TC)
	textura_usada = "%s (%dx%d, %s, %d ms)" % [caminho, img.get_width(), img.get_height(),
		"comprimida" if img.is_compressed() else "crua", Time.get_ticks_msec() - t0]
	return ImageTexture.create_from_image(img)
