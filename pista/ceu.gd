extends Node3D
## Céu da pista (PORTA do jogo; docs/engenharia_reversa.md, Céu): as cúpulas
## do SkyDome do Environment.xml do RX01 (data/environment_rx01.xml):
##   Outer = SKY_Bright_LowCloud (o céu com nuvens), Inner = BACKDROP_Asia_1
##   (a faixa de montanhas azuis em volta)
## Leitura (0x1d5c40): fileName, yOffset, rotation (graus), rotationSpeed,
## alpha (1.0), fog, tint (cor, padrão 1.0). Desenho (0x1d6500): pula alfa <
## 0.01; cor = tint com o alfa (com fog = 0, o caso do RX01); matriz = giro
## em Y pela rotação (0x61e2a0: linhas (c, 0, -s), (0, 1, 0), (s, 0, c)) na
## POSIÇÃO DA CÂMERA com y + yOffset, escala 1; sem gravar profundidade
## (ZBUF ZMSK, registradores 0x4e/0x4f), o Outer primeiro e o Inner por cima.
## Modelo .pingu (o XML diz .clm), sem luz: textura x cor do vértice.
##
## No Godot a cúpula (raio ~43 m no jogo) vai ESCALA vezes maior em volta da
## câmera: o ângulo de tudo fica igual e o relevo (até ~1.5 km) e os objetos
## sempre ficam na frente pelo teste de profundidade normal; as montanhas
## ficam mais perto que o céu (39 x 43 m), como na ordem do jogo.

const Terrain := preload("res://pista/terrain.gd")
const ARQ := "res://data/environment_rx01.xml"
const PASTA := "res://assets/rx01/ceu/"
const ESCALA := 70.0                     # 43 m -> 3 km (a câmera vê até 4 km)
const COR_K_SRGB := 255.0 / 128.0       # cor do vértice do pingu2obj (0x80 = 1.0)
## melhoria nossa: texturas do céu ampliadas (Upscayl x4 do Matheus, montanhas
## com o contorno do alfa refeito) em assets/rx01/ceu/hd/ com o MESMO nome da
## original; sem o arquivo (ou false) usa a do jogo (512 x 256)
const CEU_HD := true

var cupulas: Array = []                  # [{no, y, rot, vel}]
var t := 0.0


func montar() -> bool:
	if not FileAccess.file_exists(ARQ):
		return false
	var x := XMLParser.new()
	if x.open(ARQ) != OK:
		return false
	var dentro := false
	while x.read() == OK:
		if x.get_node_type() == XMLParser.NODE_ELEMENT_END and x.get_node_name() == "SkyDome":
			dentro = false
		if x.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		var nome := x.get_node_name()
		if nome == "SkyDome":
			dentro = true
		elif dentro and (nome == "Outer" or nome.begins_with("Inner")):
			var g := func(k: String, p: float) -> float:
				var v := x.get_named_attribute_value_safe(k)
				return v.to_float() if v != "" else p
			var arq := x.get_named_attribute_value_safe("Filename").replace("\\", "/").get_file().get_basename()
			_cupula(arq, g.call("YOffset", 0.0), g.call("Rotation", 0.0), g.call("RotationSpeed", 0.0),
				g.call("Alpha", 1.0), cupulas.size())
	return not cupulas.is_empty()


func _cupula(arq: String, y: float, rot: float, vel: float, alfa: float, ordem: int) -> void:
	var caminho := PASTA + arq + ".obj"
	if alfa < 0.01 or not ResourceLoader.exists(caminho):
		return
	var malha: Mesh = load(caminho)
	if malha == null:
		return
	for s in malha.get_surface_count():
		var m0 := malha.surface_get_material(s) as StandardMaterial3D
		if m0 == null:
			continue
		var m := m0.duplicate() as StandardMaterial3D
		if CEU_HD and m.albedo_texture:
			var hd := PASTA + "hd/" + m.albedo_texture.resource_path.get_file()
			if ResourceLoader.exists(hd):
				m.albedo_texture = load(hd)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		var c := m.albedo_color
		m.albedo_color = Color(c.r * COR_K_SRGB, c.g * COR_K_SRGB, c.b * COR_K_SRGB, alfa)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.disable_fog = true                 # Fog="0" no XML
		m.disable_receive_shadows = true
		m.texture_repeat = true
		if alfa < 1.0 or (m.albedo_texture and _tem_alfa(m.albedo_texture)):
			# montanhas: borda com alfa em 4 níveis, mistura (a do céu, opaca, embaixo)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.render_priority = ordem
		malha.surface_set_material(s, m)
	var mi := MeshInstance3D.new()
	mi.name = arq
	mi.mesh = malha
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	mi.extra_cull_margin = 16384.0
	add_child(mi)
	cupulas.append({"no": mi, "y": y, "rot": rot, "vel": vel})


static func _tem_alfa(tex: Texture2D) -> bool:
	var img := tex.get_image()
	if img and img.is_compressed():
		img = img.duplicate()
		img.decompress()
	return img != null and img.detect_alpha() != Image.ALPHA_NONE


## matriz do jogo da cúpula -> remake, presa na câmera
static func xf(pos_cam: Vector3, y: float, graus: float) -> Transform3D:
	var a := deg_to_rad(graus)
	var c := cos(a)
	var s := sin(a)
	var b := Basis(Terrain.dir_do_jogo(Vector3(c, 0, -s)), Terrain.dir_do_jogo(Vector3(0, 1, 0)),
		Terrain.dir_do_jogo(Vector3(s, 0, c)))
	return Transform3D(b.scaled(Vector3.ONE * ESCALA), pos_cam + Vector3(0, y * ESCALA, 0))


## por quadro, depois da câmera andar
func seguir(cam: Camera3D, dt: float) -> void:
	t += dt
	for c in cupulas:
		(c.no as Node3D).global_transform = xf(cam.global_position, c.y, c.rot + c.vel * t)
