extends Node3D
## Poeira dos pneus (porta do jogo; docs/engenharia_reversa.md, Poeira).
##
## Tipos (Setup/Dust.xml -> data/dust.xml, carregado em 0x3affb0): Light,
## Medium, Heavy e Water, um conjunto pro carro da câmera (CamSubject) e outro
## pros outros (Other); só "Rear": sai das rodas de trás. O material do chão
## diz o tipo (DustType, None = sem poeira) e a cor (DustColour, RGBA).
##
## Emissão (0x225108, um por quadro do jogo = 50 Hz no PAL): com |v| >= 0.5
## m/s a força é (|v| - 0.5)/35 (cheia a ~128 km/h) menos 2 x a folga da roda
## até o chão (até 0.5), presa em 0..1; a roda solta poeira com força > 0.1 e
## alfa da cor > 0.1. Quando o material muda, a cor vai da de agora pra
## DustColour dele em 1 s (sem poeira, ou a roda a 25 cm ou mais do chão: o
## alfa vai a 0 em 1 s, com o tipo de antes). No ar o material é o último que a
## roda tocou: saindo da terra ou pulando sobra um rastro que some (~0.8 s). Espaçamento entre nuvens e
## tamanho inicial pelo LOD (distância da câmera até CamMinLodDist, 30 m) e
## pela direção da câmera: 1 - frente do carro . (câmera -> carro); atrás do
## carro vale o ParticleSpacing, de lado ou de frente o ParticleSpacingLookAlong.
##
## Nuvens (0x227c50): uma a cada ParticleSpacing metros do caminho da roda,
## espalhadas no trecho do quadro (a de trás nasce mais velha). PARADAS no
## mundo (sem velocidade): nascem no ponto de contato (no ar, embaixo da roda),
## recuado velocidade x 1/60, com tamanho
## ParticleInitSize ± Delta e crescem até ParticleTargetSize ± Delta com
## 1 - (1 - idade/MaxParticleAge)^4 (0x3af590); alfa = força x alfa da cor x
## (1 - t²), t = idade / vida dela. Vida (0x3b5868, Power 1): uma nuvem vive
## MaxParticleAge e a seguinte MaxParticleAge/PowerRatio, alternando. O alfa
## de cada nuvem nova do mesmo quadro é multiplicado pela força de novo
## (0x3af170 grava alfa x força de volta no registro do tipo): no mesmo quadro
## a 1ª sai com força, a 2ª com força², ... (o jogo é assim).
## Desenho: textura Sprites/WorldFXdust (atlas 2 x 3 de nuvens, tools/fx_jogo.py
## -> assets/efeitos/poeira.png), quadrado virado pra câmera, centrado no ponto,
## cor = textura x DustColour (PS2: 0x80 = 1.0). Não portado: o canto escuro
## (o vértice 0 sai com a cor x 0.3; a ordem dos cantos não foi achada), a
## luz do lugar (corpo+0xc0) e a água.

const TEXTURA := "res://assets/efeitos/poeira.png"
## espirro na água (tipo Water do Dust.xml, Sprites/WorldFXwater_dust; mesmo
## atlas 2 x 3 da poeira, só as 4 de cima desenhadas). Sem ela não espirra
const TEXTURA_AGUA := "res://assets/efeitos/agua.png"
const TIPOS := ["Light", "Medium", "Heavy", "Water"]
## tamanho do Dust.xml -> metros. O desenho é no VU1 (não decifrado) e a
## unidade não sai do exe: calibrado nos prints do Matheus (nov/2026). Com
## 1.0 a poeira cobria o carro ("muito grande"), com 0.3 ficava fina
## ("fininho"); com 0.6 fica como nos prints do jogo: na altura das rodas,
## atrás e dos lados, sem passar do para-choque. POEIRA_ESCALA=x troca
## (diagnóstico)
const ESCALA := 0.6
var escala := float(OS.get_environment("POEIRA_ESCALA")) if OS.get_environment("POEIRA_ESCALA") != "" else ESCALA
## melhoria nossa (o "quadriculado" que o Matheus viu): as nuvens do atlas
## encostam na borda da célula (alfa 250 na 1ª linha) e o quadrado corta o
## chão numa reta. BORDA_SUAVE apaga o alfa perto da borda da célula e
## CHAO_SUAVE (m) some a nuvem onde ela encosta no chão/objetos (profundidade)
const BORDA_SUAVE := 0.12
const CHAO_SUAVE := 0.4
const COLUNAS := 2                # atlas da WorldFXdust
const LINHAS := 3

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
uniform sampler2D tex : filter_linear_mipmap, repeat_disable;
uniform sampler2D prof : hint_depth_texture, filter_nearest;
uniform vec2 grade = vec2(2.0, 3.0);
uniform bool diag = false;        // POEIRA_COR=1: vermelho opaco (onde nasce e o tamanho)
uniform float borda = 0.12;       // BORDA_SUAVE
uniform float chao = 0.4;         // CHAO_SUAVE
varying vec2 local_uv;

void vertex() {
	// quadrado virado pra câmera, com o tamanho da instância
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s,
		INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	float k = INSTANCE_CUSTOM.x;
	vec2 cel = vec2(mod(k, grade.x), floor(k / grade.x));
	local_uv = UV;
	UV = (UV + cel) / grade;
}

void fragment() {
	vec4 t = texture(tex, UV);
	// PS2: textura x cor do vértice (0x80 = 1.0) no espaço de cor da tela
	vec3 c = t.rgb * COLOR.rgb;
	ALBEDO = mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
	// alfa da textura no PS2: 0x80 = 1.0 (as da poeira e do espirro vão até
	// ~250 = satura); lido como 255 = 1.0 saía com metade da opacidade
	ALPHA = min(t.a * (255.0 / 128.0), 1.0) * COLOR.a;
	// borda da célula: sobe de 0 a 1 nos primeiros `borda` de cada lado
	if (borda > 0.0) {
		vec2 b = smoothstep(vec2(0.0), vec2(borda), local_uv) * smoothstep(vec2(0.0), vec2(borda), 1.0 - local_uv);
		ALPHA *= b.x * b.y;
	}
	// perto do que já está desenhado atrás (chão, objetos): some aos poucos
	if (chao > 0.0) {
	float z = texture(prof, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	z = z * 2.0 - 1.0;
#endif
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, z, 1.0);
	float atras = -v.z / v.w;
	ALPHA *= clamp((atras - (-VERTEX.z)) / chao, 0.0, 1.0);
	}
	if (diag) {
		ALBEDO = vec3(1.0, 0.0, 0.0);
		ALPHA = 1.0;
	}
}
"""

var car = null
var tipos: Array = []             # um dict por tipo (CamSubject/Rear)
var max_nuvens := 1024            # NumGroups x NumParticlesPerGroup da pista (RX01: 32 x 32)
var por_grupo := 32
var emissores: Array = []         # um por roda de trás
var mm: MultiMesh
var mmi: MultiMeshInstance3D
var mm_agua: MultiMesh               # espirro (outra textura)
var buf_agua := PackedFloat32Array()
var n_agua := PackedByteArray()      # 1 = nuvem de água
var rnd := RandomNumberGenerator.new()
# nuvens vivas (arrays paralelos)
var n_pos := PackedVector3Array()
var n_idade := PackedFloat32Array()
var n_vida := PackedFloat32Array()
var n_max := PackedFloat32Array()     # MaxParticleAge do tipo (crescimento)
var n_ini := PackedFloat32Array()
var n_alvo := PackedFloat32Array()
var n_a0 := PackedFloat32Array()
var n_cor := PackedColorArray()
var n_cel := PackedFloat32Array()
var buf := PackedFloat32Array()   # buffer da MultiMesh (20 floats por nuvem)
var soltas := 0                   # nuvens soltas desde o começo (testes)
var conjunto := "CamSubject"      # CamSubject (o jogador) ou Other (rivais)
# CPU: a MultiMesh cresce conforme as nuvens vivas (dobra a partir de
# CAP_INI até max_nuvens) em vez de mandar 1024 x 20 floats por carro a cada
# quadro pra GPU. Mesmo desenho
const CAP_INI := 64
var cap := CAP_INI


func montar(c) -> bool:
	car = c
	if c.terrain == null or not FileAccess.file_exists(TEXTURA):
		return false
	# 0x3affb0: CamSubject = o carro da câmera (o jogador), Other = os outros
	# (rivais: espaço 0.2/0.4 m e 2 m de longe, contra 0.15/0.1/0.1 do
	# jogador, nuvens maiores). Até nov/2026 os rivais usavam o CamSubject
	conjunto = "Other" if car.get("som_3d") else "CamSubject"
	tipos = _ler_tipos("res://data/dust.xml", conjunto)
	if tipos.is_empty():
		return false
	var cfg := _ler_config("res://data/dust_rx01.xml")
	if not cfg.is_empty():
		max_nuvens = cfg.grupos * cfg.por_grupo
		por_grupo = cfg.por_grupo
	for i in car.wheels.size():
		if not car.wheels[i].front:
			emissores.append({"roda": i, "estado": 0, "ultimo": Vector3.ZERO, "cont": 0,
				"mat": -99, "tipo": -1, "cor": Color(0, 0, 0, 0), "de": Color(0, 0, 0, 0),
				"para": Color(0, 0, 0, 0), "t": 1.0})
	mm = _multimesh(TEXTURA, "Nuvens")
	if mm == null:
		return false
	if FileAccess.file_exists(TEXTURA_AGUA):
		mm_agua = _multimesh(TEXTURA_AGUA, "Espirro")
	mmi = get_node("Nuvens")
	return true


func _multimesh(arq: String, nome: String) -> MultiMesh:
	var img := Image.load_from_file(ProjectSettings.globalize_path(arq))
	if img == null:
		return null
	img.generate_mipmaps()
	var sh := Shader.new()
	sh.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("tex", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("grade", Vector2(COLUNAS, LINHAS))
	mat.set_shader_parameter("diag", OS.get_environment("POEIRA_COR") == "1")
	var suave := OS.get_environment("SUAVE") != "0"      # SUAVE=0: sem as 2 melhorias (diagnóstico)
	mat.set_shader_parameter("borda", BORDA_SUAVE if suave else 0.0)
	mat.set_shader_parameter("chao", CHAO_SUAVE if suave else 0.0)
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = mat
	var m := MultiMesh.new()
	m.transform_format = MultiMesh.TRANSFORM_3D
	m.use_colors = true
	m.use_custom_data = true
	m.mesh = q
	m.instance_count = CAP_INI
	m.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.name = nome
	mi.multimesh = m
	mi.top_level = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0
	add_child(mi)
	mi.global_transform = Transform3D.IDENTITY
	return m


## um quadro do jogo (0x225108): v = velocidade do carro (mundo)
func passo(dt: float, v: Vector3) -> void:
	var vel := v.length()
	if vel < 0.5:
		return
	var forca_vel := (vel - 0.5) / 35.0
	var cam: Camera3D = car.get_viewport().get_camera_3d() if car.is_inside_tree() else null
	var lod := 0.0
	var olha := 0.0
	if cam:
		var dc: Vector3 = car.global_position - cam.global_position
		# 0x225108: 1 - frente do corpo (corpo+0xd0) . direção câmera -> carro;
		# câmera de corrida atrás do carro = ~0 (vale o ParticleSpacing), de lado
		# ou de frente = 1 (o LookAlong). Até nov/2026 estava invertido (usava o
		# LookAlong atrás do carro: 10 cm em vez de 15, 1.5x mais nuvens)
		olha = clampf(1.0 - car.forward().dot(dc.normalized()), 0.0, 1.0)
		lod = dc.length_squared()
	var xf: Transform3D = car.global_transform
	var up: Vector3 = xf.basis.y
	for e in emissores:
		var w: Dictionary = car.wheels[e.roda]
		# folga até o chão (0x9f0 + 0x20 + i*0x20, +0x10: + = roda afundada, - =
		# acima do chão): a força perde 2 x a folga (até 0.5) e com folga >= 0.25
		# a roda fica sem material (a cor some em 1 s). Material = o último que
		# a roda tocou (veículo+0xa88 só muda com a roda no chão, 0x2017a8): no ar
		# continua soltando um rastro que vai sumindo
		var centro: Vector3 = xf * Vector3(w.px, w.y0 + w.x, w.pz)
		var na_agua: bool = car.agua != null and car.agua_prof[e.roda] > 0.0
		var folga := 0.0 if (w.hit or na_agua) else _folga(centro, up, w.r)
		var tira := clampf(2.0 * folga, 0.0, 0.5)
		var mat: int = -2 if na_agua else (w.mat if tira < 0.5 else -1)
		if mat != e.mat:
			if na_agua:
				# ramo da água: registro da água (DustType Water), cor do objeto
				# da água (+0x70) com alfa x 0.6, na hora (de = para = cor)
				var ca: Color = car.agua.cor
				e.mat = -2
				e.tipo = TIPOS.find("Water")
				e.cor = Color(ca.r, ca.g, ca.b, ca.a * 0.6)
				e.de = e.cor
				e.para = e.cor
				e.t = 1.0
			else:
				_troca_material(e, mat)
		e.t = minf(e.t + dt, 1.0)
		e.cor = (e.de as Color).lerp(e.para, e.t)
		var forca := clampf(forca_vel - tira, 0.0, 1.0)
		if e.tipo < 0 or forca <= 0.1 or (e.cor as Color).a <= 0.1:
			e.estado = 0                  # 0x227968: o grupo acaba
			continue
		var tp: Dictionary = tipos[e.tipo]
		var l := clampf(lod / (tp.lod * tp.lod), 0.0, 1.0)
		var espaco := lerpf(lerpf(tp.espaco, tp.espaco_olha, olha), tp.espaco_lod, l)
		var ini := lerpf(tp.ini, tp.ini_lod, l)
		# ponto: centro da roda - up x (raio - afundado) = o contato no chão, a
		# base da roda no ar; menos a velocidade x 1/60 (0x225108 e 0x20ff18)
		var ponto: Vector3 = (w.point if w.hit else centro - up * w.r) - v / 60.0
		if na_agua:
			# no meio do caminho entre o fundo da roda e a superfície, sem o
			# recuo da velocidade
			ponto = Vector3(centro.x, ((centro.y - w.r) + car.agua.y) * 0.5, centro.z)
		_emitir(e, ponto, maxf(espaco, 0.01), ini, forca, tp, dt)


## folga da roda no ar até o chão embaixo dela (o raio da física só alcança
## 5 cm abaixo da roda esticada; aqui até 0.3 m, além da regra dos 0.25)
func _folga(centro: Vector3, up: Vector3, r: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(centro, centro - up * (r + 0.3))
	q.exclude = [car.get_rid()]
	var hit: Dictionary = car.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return 1.0
	return maxf(centro.distance_to(hit.position) - r, 0.0)


## 0x225108: material novo embaixo da roda. Sem material ou DustType None:
## o alfa vai a 0 (o tipo fica o de antes)
func _troca_material(e: Dictionary, mat: int) -> void:
	e.mat = mat
	e.de = e.cor
	e.t = 0.0
	var tipo := -1
	var cor := Color(0, 0, 0, 0)
	if mat >= 0 and mat < car.terrain.materials.size():
		var m: Dictionary = car.terrain.materials[mat]
		tipo = TIPOS.find(String(m.get("DustType", "None")))
		cor = m.get("DustColour", Color(0, 0, 0, 0))
	if tipo < 0:
		e.para = Color((e.cor as Color).r, (e.cor as Color).g, (e.cor as Color).b, 0.0)
		return
	e.tipo = tipo
	if cor.a < 1e-6:
		e.para = Color((e.cor as Color).r, (e.cor as Color).g, (e.cor as Color).b, 0.0)
	else:
		e.para = cor


## 0x227c50: nuvens a cada `espaco` metros do caminho desde a última
func _emitir(e: Dictionary, p: Vector3, espaco: float, ini: float, forca: float, tp: Dictionary, dt: float) -> void:
	var cor: Color = e.cor
	if e.estado == 0:
		e.estado = 2
		e.ultimo = p
		e.cont = 0
		_nuvem(e, p, 0.0, ini, cor.a * forca, cor, tp)
		return
	var d: Vector3 = p - e.ultimo
	var n := int(d.length() / espaco)
	if n < 1:
		return
	var passo_v := d.normalized() * espaco
	var a := cor.a
	for k in n:
		e.ultimo += passo_v
		a *= forca                        # 0x3af170 grava alfa x força no registro
		_nuvem(e, e.ultimo, dt * float(n - 1 - k) / float(n), ini, a, cor, tp)


## 0x3af170: uma nuvem nova
func _nuvem(e: Dictionary, p: Vector3, idade: float, ini: float, alfa: float, cor: Color, tp: Dictionary) -> void:
	if n_pos.size() >= max_nuvens:
		return
	var idx: int = e.cont
	e.cont = (idx + 1) % por_grupo
	soltas += 1
	n_pos.append(p)
	n_idade.append(idade)
	n_vida.append(tp.vidas[idx % tp.vidas.size()])
	n_max.append(tp.idade_max)
	n_ini.append(ini + rnd.randf_range(-tp.ini_delta, tp.ini_delta))
	n_alvo.append(tp.alvo + rnd.randf_range(-tp.alvo_delta, tp.alvo_delta))
	n_a0.append(clampf(alfa, 0.0, 1.0))
	n_cor.append(cor)
	n_cel.append(float(idx % (COLUNAS * LINHAS)))
	n_agua.append(1 if e.mat == -2 else 0)


## envelhece e desenha (0x3af590)
func _process(delta: float) -> void:
	if mm == null:
		return
	# envelhece e tira as mortas numa passada só (compacta e redimensiona 1
	# vez; tirar uma por uma fazia 10 resize por nuvem). A ordem das vivas
	# muda em relação ao jeito antigo (troca com a última): só a ordem de
	# desenho, nuvens transparentes iguais
	var w := 0
	var total := n_pos.size()
	for i in total:
		var idade := n_idade[i] + delta
		if idade >= n_vida[i]:
			continue
		if w != i:
			n_pos[w] = n_pos[i]
			n_vida[w] = n_vida[i]
			n_max[w] = n_max[i]
			n_ini[w] = n_ini[i]
			n_alvo[w] = n_alvo[i]
			n_a0[w] = n_a0[i]
			n_cor[w] = n_cor[i]
			n_cel[w] = n_cel[i]
			n_agua[w] = n_agua[i]
		n_idade[w] = idade
		w += 1
	if w != total:
		n_pos.resize(w)
		n_idade.resize(w)
		n_vida.resize(w)
		n_max.resize(w)
		n_ini.resize(w)
		n_alvo.resize(w)
		n_a0.resize(w)
		n_cor.resize(w)
		n_cel.resize(w)
		n_agua.resize(w)
	var n := n_pos.size()
	if n > cap:
		while cap < n:
			cap *= 2
		cap = mini(cap, max_nuvens)
		mm.instance_count = cap
		if mm_agua:
			mm_agua.instance_count = cap
	if buf.size() != cap * 20:
		buf.resize(cap * 20)
		buf_agua.resize(cap * 20)
	var np := 0
	var na := 0
	# grava direto no buffer (escala nas 3 diagonais, posição, cor, célula):
	# até nov/2026 montava 3 arrays por nuvem por quadro e a poeira dos 8
	# carros custava ~3.9 ms por quadro (tests/medir_cpu.gd)
	for k in n:
		var tg := clampf(n_idade[k] / n_max[k], 0.0, 1.0)
		var u := 1.0 - tg
		var f := 1.0 - u * u * u * u
		var tam := (n_ini[k] * (1.0 - f) + n_alvo[k] * f) * escala
		var t := n_idade[k] / n_vida[k]
		var a := n_a0[k] * (1.0 - t * t)
		var p := n_pos[k]
		var c := n_cor[k]
		if n_agua[k] == 1 and mm_agua != null:
			var o := na * 20
			buf_agua[o] = tam
			buf_agua[o + 5] = tam
			buf_agua[o + 10] = tam
			buf_agua[o + 3] = p.x
			buf_agua[o + 7] = p.y
			buf_agua[o + 11] = p.z
			buf_agua[o + 12] = c.r
			buf_agua[o + 13] = c.g
			buf_agua[o + 14] = c.b
			buf_agua[o + 15] = a
			buf_agua[o + 16] = n_cel[k]
			na += 1
		else:
			var o := np * 20
			buf[o] = tam
			buf[o + 5] = tam
			buf[o + 10] = tam
			buf[o + 3] = p.x
			buf[o + 7] = p.y
			buf[o + 11] = p.z
			buf[o + 12] = c.r
			buf[o + 13] = c.g
			buf[o + 14] = c.b
			buf[o + 15] = a
			buf[o + 16] = n_cel[k]
			np += 1
	if np > 0:
		mm.buffer = buf
	mm.visible_instance_count = np
	if mm_agua:
		if na > 0:
			mm_agua.buffer = buf_agua
		mm_agua.visible_instance_count = na
func vivas() -> int:
	return n_pos.size()


## Setup/Dust.xml: Dust/Vehicle/<conjunto>/Rear/<tipo>, na ordem de TIPOS
static func _ler_tipos(arq: String, conjunto: String) -> Array:
	var x := XMLParser.new()
	if x.open(arq) != OK:
		return []
	var dentro := false
	var achados := {}
	while x.read() == OK:
		if x.get_node_type() == XMLParser.NODE_ELEMENT_END and x.get_node_name() == conjunto:
			dentro = false
		if x.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		var nome := x.get_node_name()
		if nome == conjunto:
			dentro = true
		elif dentro and nome in TIPOS:
			var g := func(k: String) -> float: return x.get_named_attribute_value_safe(k).to_float()
			var idade_max: float = g.call("MaxParticleAge")
			var potencia := int(g.call("Power"))
			var razao: float = g.call("PowerRatio")
			achados[nome] = {"lod": g.call("CamMinLodDist"), "espaco": g.call("ParticleSpacing"),
				"espaco_olha": g.call("ParticleSpacingLookAlong"), "espaco_lod": g.call("ParticleSpacingMinLod"),
				"ini": g.call("ParticleInitSize"), "ini_lod": g.call("ParticleInitSizeMinLod"),
				"ini_delta": g.call("ParticleInitSizeDelta"), "alvo": g.call("ParticleTargetSize"),
				"alvo_delta": g.call("ParticleTargetSizeDelta"), "idade_max": idade_max,
				"vidas": _vidas(idade_max, potencia, razao)}
	var out: Array = []
	for t in TIPOS:
		if not achados.has(t):
			return []
		out.append(achados[t])
	return out


## 0x3b5868: vida de cada nuvem pela posição dela no grupo (2^Power valores):
## a 1ª MaxParticleAge, as outras divididas por PowerRatio^nível
static func _vidas(idade_max: float, potencia: int, razao: float) -> PackedFloat32Array:
	var n := 1 << potencia
	var t := PackedFloat32Array()
	t.resize(n)
	var passo := 1
	for nivel in potencia + 1:
		var v := idade_max / pow(razao, float(potencia - nivel))
		for s in range(1, n + 1):
			if s % passo == 0:
				t[n - s] = v
		passo *= 2
	return t


static func _ler_config(arq: String) -> Dictionary:
	var x := XMLParser.new()
	if x.open(arq) != OK:
		return {}
	var em_poeira := false
	while x.read() == OK:
		if x.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		var nome := x.get_node_name()
		if nome == "Dust":
			em_poeira = true
		elif nome == "Dirt":
			em_poeira = false
		elif nome == "Settings" and em_poeira:
			return {"grupos": x.get_named_attribute_value_safe("NumGroups").to_int(),
				"por_grupo": x.get_named_attribute_value_safe("NumParticlesPerGroup").to_int()}
	return {}
