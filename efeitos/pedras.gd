extends Node3D
## Pedrinhas do pneu (PORTA do jogo; docs/engenharia_reversa.md, Pedrinhas).
##
## Gerente 0x3bade8 (global 0x7f58cc, um por corrida) com 2 estoques: o de
## pedras/terra (textura Sprites/dirt_rocks, caixas Dirt01..05) e o de
## lasquinhas da batida (Particle_Debris.bantam, 0x3bbd60; não portado aqui).
## O WheelSpinDirt/WheelDirtTrail do Effects/#3ffdac18 o exe não usa.
##
## Emissão (0x3bb618, um por quadro = 50 Hz no PAL, carro a >= 1 mph, fora
## da água), só nas rodas de TRÁS (0x1f1ef0 pula a 0 e a 2 = FL e FR), com o
## material da roda (0x20ff18; o último que ela tocou) IsDirt:
##   curso = (x - x parado) / (máx - x parado), preso em 0..1 (W+0xe8,
##   corpo+0x4c0, W+0xf0). Se curso <= 1 - DirtKickupChance, só solta com a
##   patinada (0x600, presa em 0..1) > sorteio(0, 0.3) + 0.05. Uma partícula
##   por roda por quadro.
##   Tipo: sorteio < Rockiness = PEDRA (tipo 0: caixa Dirt01..04 sorteada,
##   0.14 m, 10 m/s), senão BORRIFO de terra (tipo 1: Dirt05, 2.0 m, 5 m/s)
##   (0.12/7.5 e 1.2/4 com o flag veículo+0xa6c+0x8c+0x18, 0 nos buggies e
##   trucks da RAM).
##   Direção: atrás do carro (-frente) girada em Y pela derrapagem 0x6c0
##   (presa em ±1 rad) x 90°, pro lado em que o carro escorrega; a altura y é
##   trocada por c3 ± c4 e normaliza. Os 5 números c vão de RETO (|β| = 0:
##   0.16, 3.1, 0.5, 10, 10) a DE LADO (|β| = 1: 0.3, 12, 1, 1, 0.3), lerp
##   (0x3bad60): reto = quase pra cima, de lado = 45° pro lado.
##   Ponto = contato da roda (0x20ff18, recuado v/60) + lado x l, l = sorteio
##   ±c0 (lado = direção x cima). Velocidade = direção x (vel ± 1) + lado x l x
##   c1 + v do carro x c2. Cor = DirtColour do material (registro +0x20) x
##   sombra do lugar (não portada, como na poeira).
## Física (0x3b9d20 -> 0x3ba650, mesmo quadro, depois da emissão):
##   pedra: vive 1 s, vy -= 30·dt, pos += v·dt, alfa = min((1 - idade)·5, 1);
##   abaixo do chão guardado: y = chão, vy = -vy e v x 0.4 (quica). O chão de
##   cada pedra é o relevo + 0.02 (0x1edb50), medido em rodízio, 5 pedras por
##   quadro (pool +0xd4/+0xdc); antes da 1ª medida não quica.
##   borrifo: vive 0.6 s, vy -= 10·dt, pos += v·dt, tamanho += dt, alfa =
##   min((0.6 - idade)·2, 1), sem chão.
## Estoque: 256 (RAM: livres + vivas). Conferido no save state da derrapagem
## (drr2: 80 vivas, 2 por quadro, tamanhos, velocidades e o rodízio do chão).
## Desenho (0x3b9fd0): quadrado virado pra câmera, mistura comum (ALPHA 0x44),
## textura x cor (0x80 = 1.0), alfa da textura do PS2 (0x80 = 1.0, satura).
## Tamanho x ESCALA (o desenho é no VU1, a unidade não sai do exe): a mesma
## 0.6 da poeira; no vídeo do Matheus (nov/2026) a pedra tem ~10 px ao lado da
## roda de trás (~140 px/m) = 0.14 x 0.6 x 85% da caixa.

const TEXTURA := "res://assets/efeitos/pedras.png"
const CAIXAS := "res://assets/efeitos/pedras.json"
const ESCALA := 0.6
## melhoria nossa (a mesma da poeira): o borrifo nasce no chão e o quadrado
## cortaria o chão numa reta; some onde encosta (só no borrifo, a pedra não)
const CHAO_SUAVE := 0.4
const MAX := 256
const RETO := [0.16, 3.1, 0.5, 10.0, 10.0]
const LADO := [0.3, 12.0, 1.0, 1.0, 0.3]
const CHAO_POR_QUADRO := 5            # pool +0xd4
const CHAO_FOLGA := 0.02              # pool +0xdc

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
uniform sampler2D tex : filter_linear_mipmap, repeat_disable;
uniform sampler2D prof : hint_depth_texture, filter_nearest;
uniform vec4 caixas[5];
uniform float chao = 0.4;
uniform bool diag = false;        // PEDRAS_COR=1: vermelho opaco
varying float borrifo;

void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s,
		INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	vec4 c = caixas[int(INSTANCE_CUSTOM.x + 0.5)];
	borrifo = INSTANCE_CUSTOM.y;
	UV = mix(c.xy, c.zw, UV);
}

void fragment() {
	vec4 t = texture(tex, UV);
	vec3 c = t.rgb * COLOR.rgb;
	ALBEDO = mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
	ALPHA = min(t.a * (255.0 / 128.0), 1.0) * COLOR.a;
	if (borrifo > 0.5 && chao > 0.0) {
		float z = texture(prof, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		z = z * 2.0 - 1.0;
#endif
		vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, z, 1.0);
		ALPHA *= clamp((-v.z / v.w + VERTEX.z) / chao, 0.0, 1.0);
	}
	if (diag) {
		ALBEDO = vec3(1.0, 0.0, 0.0);
		ALPHA = 1.0;
	}
}
"""

var car = null
var mm: MultiMesh
var rnd := RandomNumberGenerator.new()
# partículas vivas (arrays paralelos)
var p_pos := PackedVector3Array()
var p_ant := PackedVector3Array()     # posição no quadro anterior (desenho interpolado)
var p_vel := PackedVector3Array()
var p_idade := PackedFloat32Array()
var p_tam := PackedFloat32Array()
var p_chao := PackedFloat32Array()
var p_tipo := PackedByteArray()       # 0 pedra, 1 borrifo
var p_cel := PackedByteArray()        # caixa (0..3 pedras, 4 = Dirt05)
var p_cor := PackedColorArray()
var cursor := 0                       # rodízio do chão
var buf := PackedFloat32Array()
var soltas := 0                       # partículas soltas desde o começo (testes)
var soltas_tipo := [0, 0]


func montar(c) -> bool:
	car = c
	if c.terrain == null or not FileAccess.file_exists(TEXTURA) or not FileAccess.file_exists(CAIXAS):
		return false
	var cx = JSON.parse_string(FileAccess.get_file_as_string(CAIXAS))
	if typeof(cx) != TYPE_DICTIONARY:
		return false
	var caixas := PackedVector4Array()
	for n in ["Dirt01", "Dirt02", "Dirt03", "Dirt04", "Dirt05"]:
		if not cx.has(n):
			return false
		caixas.append(Vector4(cx[n][0], cx[n][1], cx[n][2], cx[n][3]))
	var img := Image.load_from_file(ProjectSettings.globalize_path(TEXTURA))
	if img == null:
		return false
	img.generate_mipmaps()
	var sh := Shader.new()
	sh.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("tex", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("caixas", caixas)
	mat.set_shader_parameter("chao", CHAO_SUAVE if OS.get_environment("SUAVE") != "0" else 0.0)
	mat.set_shader_parameter("diag", OS.get_environment("PEDRAS_COR") == "1")
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = mat
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = q
	mm.instance_count = MAX
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.name = "Pedras"
	mi.multimesh = mm
	mi.top_level = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0
	add_child(mi)
	mi.global_transform = Transform3D.IDENTITY
	buf.resize(MAX * 20)
	return true


## um quadro do jogo (0x3bb5d0): emite (0x3bb618) e anda (0x3b9d20).
## v = velocidade do carro (mundo, corpo+0x90)
func passo(dt: float, v: Vector3) -> void:
	_emitir(v)
	_andar(dt)


func _emitir(v: Vector3) -> void:
	if v.length() < 0.44694445:          # veículo+0xb18 >= 1 mph
		return
	if car.agua != null:                  # veículo+0xae8: na água não solta
		for k in car.agua_prof.size():
			if car.agua_prof[k] > 0.0:
				return
	var beta := clampf(absf(car.sideslip), 0.0, 1.0)
	var c := []
	for k in 5:                           # 0x3bad60
		c.append(lerpf(RETO[k], LADO[k], beta))
	var fwd: Vector3 = car.forward()
	var atras := -fwd
	# gira em Y |β| x 90° pro lado em que o carro escorrega (0x6c0 com sinal;
	# drr2: β -1.05, atrás (-0.84, 0.54) -> (0.54, 0.84), o lado da velocidade)
	var ang := beta * PI * 0.5
	var a1 := atras.rotated(Vector3.UP, ang)
	var a2 := atras.rotated(Vector3.UP, -ang)
	var dir0 := a1 if a1.dot(v) >= a2.dot(v) else a2
	var lado := dir0.cross(Vector3.UP)    # sem normalizar (como o jogo)
	var xf: Transform3D = car.global_transform
	var up: Vector3 = xf.basis.y
	var mats: Array = car.terrain.materials
	for w in car.wheels:
		if w.front:
			continue                      # 0x1f1ef0: FL e FR não
		if w.mat < 0 or w.mat >= mats.size():
			continue
		var m: Dictionary = mats[w.mat]
		if String(m.get("IsDirt", "false")) != "true":
			continue
		var curso := 0.0
		if w.max - w.xs > 1e-6:
			curso = clampf((w.x - w.xs) / (w.max - w.xs), 0.0, 1.0)
		var kick := float(m.get("DirtKickupChance", "0.2"))
		if curso <= 1.0 - kick:
			var pat := clampf(w.sr, 0.0, 1.0)
			if pat <= rnd.randf() * 0.3 + 0.05:
				continue
		var centro: Vector3 = xf * Vector3(w.px, w.y0 + w.x, w.pz)
		var ponto: Vector3 = (w.point if w.hit else centro - up * w.r) - v / 60.0
		var cor: Color = m.get("DirtColour", Color(0.5, 0.4, 0.3, 1.0))
		var l: float = rnd.randf_range(-c[0], c[0])
		var d := Vector3(dir0.x, c[3] + rnd.randf_range(-c[4], c[4]), dir0.z).normalized()
		var pedra := rnd.randf() < float(m.get("Rockiness", "0.0"))
		var vel := (10.0 if pedra else 5.0) + rnd.randf_range(-1.0, 1.0)
		var vp: Vector3 = d * vel + lado * (l * float(c[1])) + v * float(c[2])
		_nova(ponto + lado * l, vp, 0 if pedra else 1, 0.14 if pedra else 2.0,
			rnd.randi_range(0, 3) if pedra else 4, cor)


func _nova(p: Vector3, v: Vector3, tipo: int, tam: float, cel: int, cor: Color) -> void:
	if p_pos.size() >= MAX:
		return
	soltas += 1
	soltas_tipo[tipo] += 1
	p_pos.append(p)
	p_ant.append(p)
	p_vel.append(v)
	p_idade.append(0.0)
	p_tam.append(tam)
	p_chao.append(-INF)               # 0x5b98d8 = -FLT_MAX até a 1ª medida
	p_tipo.append(tipo)
	p_cel.append(cel)
	p_cor.append(Color(cor.r, cor.g, cor.b, 1.0))


## 0x3b9d20 / 0x3ba650
func _andar(dt: float) -> void:
	var i := 0
	while i < p_pos.size():
		var idade := p_idade[i] + dt
		p_idade[i] = idade
		p_ant[i] = p_pos[i]
		var v := p_vel[i]
		if p_tipo[i] == 1:
			if idade > 0.6:
				_tira(i)
				continue
			v.y -= dt * 10.0
			p_tam[i] += dt
			p_pos[i] += v * dt
		else:
			if idade > 1.0:
				_tira(i)
				continue
			v.y -= dt * 30.0
			var p := p_pos[i] + v * dt
			if p.y < p_chao[i]:
				p.y = p_chao[i]
				v.y = -v.y
				v *= 0.4
			p_pos[i] = p
		p_vel[i] = v
		i += 1
	# chão em rodízio, 5 por quadro (relevo + 0.02)
	var n := p_pos.size()
	for k in mini(CHAO_POR_QUADRO, n):
		cursor = cursor % n
		var q := p_pos[cursor]
		p_chao[cursor] = car.terrain.height_at(q.x, q.z) + CHAO_FOLGA
		cursor += 1


func _process(_delta: float) -> void:
	if mm == null:
		return
	var n := p_pos.size()
	# CPU: nenhuma no ar e nada desenhado: não tem o que fazer
	if n == 0 and mm.visible_instance_count == 0:
		return
	var f := Engine.get_physics_interpolation_fraction()
	# CPU: as casas que são sempre 0 (fora da diagonal e as 2 últimas) já
	# nascem 0 no buffer e ninguém mais escreve nelas: não regrava
	for k in n:
		var a := minf((0.6 - p_idade[k]) * 2.0, 1.0) if p_tipo[k] == 1 else minf((1.0 - p_idade[k]) * 5.0, 1.0)
		var p := p_ant[k].lerp(p_pos[k], f)
		var s := p_tam[k] * ESCALA
		var o := k * 20
		buf[o] = s; buf[o + 3] = p.x
		buf[o + 5] = s; buf[o + 7] = p.y
		buf[o + 10] = s; buf[o + 11] = p.z
		var c := p_cor[k]
		buf[o + 12] = c.r; buf[o + 13] = c.g; buf[o + 14] = c.b; buf[o + 15] = maxf(a, 0.0)
		buf[o + 16] = float(p_cel[k]); buf[o + 17] = float(p_tipo[k])
	if n > 0:
		mm.buffer = buf
	mm.visible_instance_count = n


func _tira(i: int) -> void:
	var u := p_pos.size() - 1
	p_pos[i] = p_pos[u]
	p_ant[i] = p_ant[u]
	p_vel[i] = p_vel[u]
	p_idade[i] = p_idade[u]
	p_tam[i] = p_tam[u]
	p_chao[i] = p_chao[u]
	p_tipo[i] = p_tipo[u]
	p_cel[i] = p_cel[u]
	p_cor[i] = p_cor[u]
	# um a um: Packed*Array num Array/parâmetro vira cópia
	p_pos.resize(u)
	p_ant.resize(u)
	p_vel.resize(u)
	p_idade.resize(u)
	p_tam.resize(u)
	p_chao.resize(u)
	p_tipo.resize(u)
	p_cel.resize(u)
	p_cor.resize(u)


## quantas vivas (testes)
func vivas() -> int:
	return p_pos.size()
