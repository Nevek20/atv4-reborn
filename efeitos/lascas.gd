extends Node3D
## Lasquinhas da batida (PORTA do jogo; docs/engenharia_reversa.md, Lasquinhas).
##
## Mesmo gerente das pedrinhas (0x3bade8), estoque +0x18: modelo
## Levels/Grass/Models/Bantams/Particle_Debris.bantam (pedacinho de ~25 x 7 x
## 22 cm, sombra assada no vértice, textura Debris branca), no máximo 8 vivas
## (RAM). tools/fx_jogo.py -> assets/efeitos/lasca.json + lasca.png.
##
## Emissão 0x3bbd60, chamada pelo 0x1515e0 em cada contato do veículo com o
## mundo fixo (par de colisão 2 x 0, registrado no 0x14d458; o mesmo contato
## lê o material do chão: chão e paredes). Carro com carro (0x1529d0, par 2 x
## 2) usa outros números (25..45 mph) e não está aqui (o remake tem 1 carro).
##   Só se o contato fica a >= 1 m do último (veículo+0xb50, gravado sempre
##   que passa daqui). v = velocidade do corpo, |v| >= 30 mph:
##   t = (|v| - 30 mph) / (80 - 30 mph) preso em 0..1, velocidade de saída
##   (25 + 10 t) mph x sorteio(0.5..1), quantas = int((2 + 4 t) x -(v̂ . n)),
##   no mínimo 1. Base da normal (0x61e010): linha 3 = n, linha 1 = cima x n,
##   linha 2 = n x linha 1; direção = (±2, ±2 + 1.5, 1) nessa base,
##   normalizada (sai da parede pra cima). Velocidade = direção x saída +
##   (v - n (v.n)) x 0.7. Tamanho por eixo do modelo 0.7..1.3 e, em 1/3 delas,
##   o x ou o z x 1.5..2.5 (lasca comprida). Cor = BASE da pintura
##   (veículo+0x9d0+0xc4+0x78+0xb0; RAM: Renegade 220,231,235, Storm 190,26,16)
##   x sombra do lugar (não portada). Gira em volta de um eixo sorteado 30/60
##   rad por quadro (pool +0xd0).
## Física (0x3ba650, tipo 2): vive 4 s, vy -= 30 dt, pos += v dt, alfa =
##   min(4 - idade, 1); abaixo do chão guardado: y = chão, vy = -vy, v x 0.5,
##   eixo novo e giro x 0.5. Chão = relevo + 0.02 medido em rodízio, 2 por
##   quadro (pool +0xd4/+0xdc).
## Conferido no crash_Storm (parede de pedra): 4 recém-soltas (0.216 s), giro
## 0.5, tamanhos 0.71..1.29 e uma comprida 2.58; uma de 2.24 s parada no chão.

const MODELO := "res://assets/efeitos/lasca.json"
const TEXTURA := "res://assets/efeitos/lasca.png"
const MAX := 8                        # NumParticlesPerGroup 8 x 1 grupo (0x3bade8; RAM)
const MPH := 0.44694445
const MUNDO := [30.0, 80.0, 25.0, 35.0, 2.0, 1.5, 2, 6, 0.7]   # gerente +0x64 (0x1515e0)
const VIDA := 4.0                     # pool +0xa8
const GRAVIDADE := 30.0               # pool +0xa4
const SOME := 1.0                     # pool +0xb0 (1 / 1 s)
const GIRO := 30.0                    # pool +0xd0 (x 1/60 por quadro)
const QUICA := 0.5                    # pool +0xd8
const CHAO_POR_QUADRO := 2            # pool +0xd4
const CHAO_FOLGA := 0.02              # pool +0xdc

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_always, shadows_disabled;
uniform sampler2D tex : filter_linear_mipmap;
uniform bool diag = false;        // LASCAS_COR=1: vermelho
varying vec4 inst;

void vertex() {
	inst = INSTANCE_CUSTOM;
}

void fragment() {
	vec4 t = texture(tex, UV);
	// PS2: textura x cor do vértice (sombra assada, 0x80 = 1.0) x cor da
	// lasca (base da pintura), no espaço da tela
	vec3 c = clamp(t.rgb * COLOR.rgb * inst.rgb, 0.0, 1.0);
	ALBEDO = mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
	ALPHA = min(t.a * (255.0 / 128.0), 1.0) * inst.a;
	if (diag) {
		ALBEDO = vec3(1.0, 0.0, 0.0);
		ALPHA = 1.0;
	}
}
"""

var car = null
var mm: MultiMesh
var rnd := RandomNumberGenerator.new()
var cor := Color(1, 1, 1)             # base da pintura do carro
var ultimo := Vector3(INF, INF, INF)  # veículo+0xb50
var l_pos := PackedVector3Array()
var l_ant := PackedVector3Array()
var l_vel := PackedVector3Array()
var l_idade := PackedFloat32Array()
var l_esc := PackedVector3Array()
var l_chao := PackedFloat32Array()
var l_giro := PackedFloat32Array()    # rad por quadro
var l_eixo := PackedVector3Array()
var l_base: Array[Basis] = []
var l_base_ant: Array[Basis] = []
var cursor := 0
var buf := PackedFloat32Array()
var soltas := 0                       # testes
var ultimas: Array = []               # as do último contato (testes): [velocidade, tamanho]


func montar(c) -> bool:
	car = c
	if c.terrain == null or not FileAccess.file_exists(MODELO) or not FileAccess.file_exists(TEXTURA):
		return false
	var j = JSON.parse_string(FileAccess.get_file_as_string(MODELO))
	if typeof(j) != TYPE_DICTIONARY or not j.has("tris"):
		return false
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var cs := PackedColorArray()
	for t in j.tris:
		v.append(Vector3(t[0], t[1], t[2]))
		uv.append(Vector2(t[3], t[4]))
		cs.append(Color(t[5], t[6], t[7]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_COLOR] = cs
	var malha := ArrayMesh.new()
	malha.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var img := Image.load_from_file(ProjectSettings.globalize_path(TEXTURA))
	if img == null:
		return false
	img.generate_mipmaps()
	var sh := Shader.new()
	sh.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("tex", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("diag", OS.get_environment("LASCAS_COR") == "1")
	malha.surface_set_material(0, mat)
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = malha
	mm.instance_count = MAX
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.name = "Lascas"
	mi.multimesh = mm
	mi.top_level = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0
	add_child(mi)
	mi.global_transform = Transform3D.IDENTITY
	buf.resize(MAX * 16)
	cor = cor_base(c)
	return true


## base da pintura (gerar_pintura -> pintura.json). Sem o .json (pintura velha):
## a cor que mais aparece na pintura.png (a base cobre quase tudo; NOSSO)
static func cor_base(c) -> Color:
	var dir: String = c.model_path.get_base_dir() if c.model_path != "" else ""
	var jp := dir.path_join(c.livery_file.get_basename() + ".json")
	if dir != "" and FileAccess.file_exists(jp):
		var j = JSON.parse_string(FileAccess.get_file_as_string(jp))
		if typeof(j) == TYPE_DICTIONARY and j.get("base") is Array:
			return Color8(int(j.base[0]), int(j.base[1]), int(j.base[2]))
	var pp := dir.path_join(c.livery_file)
	if dir == "" or not FileAccess.file_exists(pp):
		return Color(1, 1, 1)
	var img := Image.load_from_file(ProjectSettings.globalize_path(pp))
	if img == null:
		return Color(1, 1, 1)
	img.resize(64, 64, Image.INTERPOLATE_NEAREST)
	var conta := {}
	var melhor := Color(1, 1, 1)
	var n_melhor := 0
	for y in 64:
		for x in 64:
			var p := img.get_pixel(x, y)
			var k := Color8(int(p.r8 / 8) * 8, int(p.g8 / 8) * 8, int(p.b8 / 8) * 8).to_rgba32()
			conta[k] = conta.get(k, 0) + 1
			if conta[k] > n_melhor:
				n_melhor = conta[k]
				melhor = p
	return melhor


## 0x3bbd60 (mundo): contato do casco em p (mundo), normal n saindo do que
## foi batido, v = velocidade do corpo
func batida(p: Vector3, n: Vector3, v: Vector3) -> void:
	if p.distance_squared_to(ultimo) < 1.0:
		return
	ultimo = p
	var vel := v.length()
	var f: Array = MUNDO
	if vel < f[0] * MPH:
		return
	var t := clampf((vel - f[0] * MPH) / ((f[1] - f[0]) * MPH), 0.0, 1.0)
	var saida: float = (f[2] + t * (f[3] - f[2])) * MPH
	n = n.normalized()
	var vt := (v - n * v.dot(n)) * float(f[8])
	var de_frente := -(v / vel).dot(n)
	var quantas := int((float(f[6]) + t * float(f[7] - f[6])) * de_frente)
	if quantas <= 0:
		quantas = 1
	# 0x61e010: linha 3 = n, linha 1 = cima x n (zero com n pra cima), linha 2 = n x linha 1
	var l1 := Vector3.UP.cross(n)
	l1 = l1.normalized() if l1.length_squared() > 1e-12 else Vector3.ZERO
	var l2 := n.cross(l1)
	ultimas.clear()
	for k in quantas:
		var esc := Vector3(rnd.randf() * 0.6 + 0.7, rnd.randf() * 0.6 + 0.7, rnd.randf() * 0.6 + 0.7)
		if rnd.randf() < 1.0 / 3.0:
			var r := rnd.randf() + 1.5
			if rnd.randf() < 0.5:
				esc.x *= r
			else:
				esc.z *= r
		var dl := Vector3(rnd.randf_range(-f[4], f[4]), rnd.randf_range(-f[4], f[4]) + f[5], 1.0)
		var d := (l1 * dl.x + l2 * dl.y + n * dl.z).normalized()
		var vp := d * saida * (rnd.randf() * 0.5 + 0.5) + vt
		_nova(p, vp, esc)
		ultimas.append([vp, esc])


func _eixo() -> Vector3:
	var e := Vector3(rnd.randf_range(-1, 1), rnd.randf_range(-1, 1), rnd.randf_range(-1, 1))
	return e.normalized() if e.length_squared() > 1e-12 else Vector3.UP


func _nova(p: Vector3, v: Vector3, esc: Vector3) -> void:
	if l_pos.size() >= MAX:
		return                        # 0x3b96f8: estoque vazio, não solta
	soltas += 1
	l_pos.append(p)
	l_ant.append(p)
	l_vel.append(v)
	l_idade.append(0.0)
	l_esc.append(esc)
	l_chao.append(-INF)               # 0x5b98d8 = -FLT_MAX até a 1ª medida
	l_giro.append(GIRO / 60.0)        # 0x3b96f8: x 0.016666668
	l_eixo.append(_eixo())
	l_base.append(Basis.IDENTITY)
	l_base_ant.append(Basis.IDENTITY)


## um quadro do jogo (0x3b9d20 / 0x3ba650, tipo 2)
func passo(dt: float) -> void:
	var i := 0
	while i < l_pos.size():
		var idade := l_idade[i] + dt
		l_idade[i] = idade
		if idade > VIDA:
			_tira(i)
			continue
		l_ant[i] = l_pos[i]
		l_base_ant[i] = l_base[i]
		var v := l_vel[i]
		v.y -= dt * GRAVIDADE
		var p := l_pos[i] + v * dt
		if p.y < l_chao[i]:
			v.y = -v.y
			v *= QUICA
			p.y = l_chao[i]
			l_eixo[i] = _eixo()
			l_giro[i] *= QUICA
		l_pos[i] = p
		l_vel[i] = v
		if dt > 1e-6 and GIRO > 1e-6:
			l_base[i] = (l_base[i] * Basis(l_eixo[i], l_giro[i])).orthonormalized()
		i += 1
	var n := l_pos.size()
	for k in mini(CHAO_POR_QUADRO, n):
		cursor = cursor % n
		var q := l_pos[cursor]
		l_chao[cursor] = car.terrain.height_at(q.x, q.z) + CHAO_FOLGA
		cursor += 1


func _process(_delta: float) -> void:
	if mm == null:
		return
	var f := Engine.get_physics_interpolation_fraction()
	var n := l_pos.size()
	for k in n:
		var b: Basis = l_base_ant[k].slerp(l_base[k], f) * Basis.from_scale(l_esc[k])
		var p := l_ant[k].lerp(l_pos[k], f)
		var o := k * 16
		buf[o] = b.x.x; buf[o + 1] = b.y.x; buf[o + 2] = b.z.x; buf[o + 3] = p.x
		buf[o + 4] = b.x.y; buf[o + 5] = b.y.y; buf[o + 6] = b.z.y; buf[o + 7] = p.y
		buf[o + 8] = b.x.z; buf[o + 9] = b.y.z; buf[o + 10] = b.z.z; buf[o + 11] = p.z
		buf[o + 12] = cor.r; buf[o + 13] = cor.g; buf[o + 14] = cor.b
		buf[o + 15] = clampf((VIDA - l_idade[k]) * SOME, 0.0, 1.0)
	if n > 0:
		mm.buffer = buf
	mm.visible_instance_count = n


func _tira(i: int) -> void:
	var u := l_pos.size() - 1
	l_pos[i] = l_pos[u]
	l_ant[i] = l_ant[u]
	l_vel[i] = l_vel[u]
	l_idade[i] = l_idade[u]
	l_esc[i] = l_esc[u]
	l_chao[i] = l_chao[u]
	l_giro[i] = l_giro[u]
	l_eixo[i] = l_eixo[u]
	l_base[i] = l_base[u]
	l_base_ant[i] = l_base_ant[u]
	l_pos.resize(u)
	l_ant.resize(u)
	l_vel.resize(u)
	l_idade.resize(u)
	l_esc.resize(u)
	l_chao.resize(u)
	l_giro.resize(u)
	l_eixo.resize(u)
	l_base.resize(u)
	l_base_ant.resize(u)


func vivas() -> int:
	return l_pos.size()
