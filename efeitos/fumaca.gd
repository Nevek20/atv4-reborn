extends Node3D
## Fumaça do escapamento (melhoria nossa, car.gd FUMACA). O jogo NÃO solta
## fumaça: o efeito "ExhaustSmokeTrail" existe no Effects/#3ffdac18 (xml 01416)
## e os pontos EXHAUST/EXHAUST2 no _points.bin, mas o exe não lê nenhum dos
## dois (sem as strings cBehaviour*/cRenderer*, tabela de pontos 0x550700 sem
## EXHAUST). Aqui o efeito dos devs vai nos pontos:
##   Life 0.5 s, cor 0.35 cinza com alfa 0.3, 0.2 m, cresce 0.6-0.8 m/s
##   (ExpandFromCentre), ângulo sorteado 0..pi, some nos últimos 30% da vida
##   (FadeOutTime 0.3 x Life), Momentum sem velocidade inicial = rastro parado
##   no mundo, no máximo 60 partículas por cano, textura Sprites/Particles
##   caixa Dust0 (tools/fx_jogo.py -> assets/efeitos/fumaca.png).
## O que o XML não tem (era do código que não existe) é escolha nossa: a taxa
## (TAXA_LENTA na marcha lenta até 120/s com o motor cheio, pela carga e pelo
## rpm) e o movimento do gás (nov/2026, pedido do Matheus: "uma leve força
## inicial de expulsão... o vento relativo deve influenciar... nada de mudar
## de direção na hora"). Física NOSSA, num shader de partícula (ar parado no
## mundo, sem vento):
##   - sai com a velocidade da boca (carro + giro) mais um JATO na direção do
##     cano (cone de 8°);
##   - o ar freia o gás: a diferença pra velocidade do ar cai exp(-ARRASTO t)
##     (nada muda na hora). Atrás do carro o ar é puxado junto (ESTEIRA:
##     fração da velocidade do carro, some em ESTEIRA_COMP atrás da boca e
##     ESTEIRA_LARG pro lado);
##   - gás quente sobe (EMPUXO, esfria em ESFRIA s) e mexe (TURBULENCIA, mais
##     forte com o vento relativo);
##   - cresce o do XML; CRESCE_VENTO (m/s a mais por m/s de vento) e DILUI
##     (alfa x (tamanho inicial / tamanho)^DILUI) ficam em 0: ligados, a
##     fumaça engrossava andando.
## Tamanho: a fumaça antiga (aprovada, "fininha") ficava SEMPRE em 0.2 m: o
## billboard das partículas do Godot jogava fora a escala (falta o
## billboard_keep_scale), então o ExpandRate do XML nunca valeu. Aqui a
## escala vale e cresce pouco (CRESCE). Transparência, vida e taxa = XML.
## Movimento (simulado, média de 40 partículas): parado o jato anda ~0.4 m
## pra trás e sobe ~0.15 m; andando o rastro tem ~80% do comprimento do
## antigo (o gás sai com a velocidade do carro e o ar freia em ~0.1 s).

const TEXTURA := "res://assets/efeitos/fumaca.png"
const VIDA := 0.5
const MAX := 60                     # MaxParticles
const TAMANHO := 0.2
const CRESCE := 0.2                 # m/s (NOSSO: o ExpandRate do XML é 0.6..0.8, mas a antiga
                                    # aprovada nunca cresceu, ficava 0.2 m; 0.2 -> 0.3 m em 0.5 s)
const COR := Color(0.35, 0.35, 0.35, 0.3)
const SOME := 0.3                   # FadeOutTime x Life
const TAXA_LENTA := 0.15            # fração do máximo (120/s) parado
# física do gás (NOSSA, ver acima)
const JATO := 5.0                   # m/s pra fora do cano
const ABERTURA := 0.14              # tan(8°): cone do jato
const ARRASTO := 12.0               # 1/s
const ESTEIRA := 0.3                # fração da velocidade do carro no ar logo atrás
const ESTEIRA_COMP := 1.5           # m atrás da boca (cai 1/e)
const ESTEIRA_LARG := 0.6           # m pro lado
const EMPUXO := 6.0                 # m/s² pra cima, gás quente
const ESFRIA := 0.8                 # s (o empuxo cai 1/e)
const TURBULENCIA := 1.2            # m/s² (x (1 + vento/10))
const CRESCE_VENTO := 0.0           # m/s a mais de crescimento por m/s de vento
const DILUI := 0.0                  # alfa x (tamanho inicial / tamanho)^DILUI

var canos: Array = []
var bases: Array = []               # boca de cada cano no frame do corpo (+Z = saída)
var nomes: Array = []               # ponto EXHAUST* de cada emissor
var antes: Array = []               # boca no quadro anterior (mundo)
var car


## Boca x fumaça (out/2026, "não sincroniza", buggy e truck): o GPUParticles3D
## solta as partículas de cada passo dele TODAS no ponto do emissor naquele
## quadro, e o passo padrão é 30/s. Andando, a fumaça saía em bolos (a 108 km/h
## um a cada 1 m) e em metade dos quadros a boca ficava sem fumaça encostada
## (o bolo mais novo meio metro atrás). Medido numa cena mínima com caixa a
## 30 m/s (o emissor filho do corpo interpolado não tem atraso: o problema é
## só o passo). Agora: passo a cada quadro (fixed_fps 0) e as partículas do
## quadro saem espalhadas no trecho que a boca andou desde o quadro anterior
## (caixa de emissão fina ao longo dele): rastro contínuo até a boca. Cada
## emissor é top_level e segue o carro desenhado (interpolado) e a malha
## tremendo onde fica a boca (motor_treme.bocas), a cada quadro (seguir).


## monta um emissor por ponto EXHAUST* do carro (frame do corpo): EXHAUST,
## EXHAUST2 e os repetidos dos trucks (EXHAUST~1, car._load_points)
func montar(c) -> bool:
	car = c
	if not FileAccess.file_exists(TEXTURA) and not ResourceLoader.exists(TEXTURA):
		return false
	var tex := _textura()
	for nome: String in car.points:
		if not nome.begins_with("EXHAUST"):
			continue
		var p: Vector3 = car.corpo(car.points[nome])
		var d: Vector3 = car.points_rot[nome].z * car.ESPELHO   # linha 2 da matriz, jogo -> corpo
		var e := GPUParticles3D.new()
		e.name = nome
		e.amount = MAX
		e.lifetime = VIDA
		e.local_coords = false
		e.fixed_fps = 0                 # passo a cada quadro (padrão 30: bolos)
		e.interpolate = false
		e.visibility_aabb = AABB(Vector3(-20, -20, -20), Vector3(40, 40, 40))
		e.process_material = _processo()
		e.draw_pass_1 = _malha(tex)
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(e)
		e.top_level = true
		e.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		var up := Vector3.UP if absf(d.normalized().dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
		canos.append(e)
		bases.append(Transform3D(Basis.looking_at(-d, up), p))   # +Z local = saída do cano
		nomes.append(nome)
		antes.append(Vector3.INF)
	seguir()
	return not canos.is_empty()


## a cada quadro: boca no carro desenhado (interpolado) com a malha tremendo
## onde ela fica (motor ou escape, no frame do modelo dentro do espelho, vira
## um deslocamento no frame do corpo); o emissor vai pro meio do trecho que a
## boca andou desde o quadro anterior, com a caixa de emissão ao longo dele
func seguir() -> void:
	if car == null or not car.is_inside_tree():
		return
	var xf: Transform3D = car.get_global_transform_interpolated()
	var mt = car.motor_treme
	var pai := Transform3D()
	if mt and mt.is_inside_tree():
		pai = car.global_transform.affine_inverse() * mt.global_transform
	var vc: Vector3 = car.linear_velocity
	var com: Vector3 = car.global_transform * car.center_of_mass
	var frente: Vector3 = xf.basis.z.normalized()      # +Z do corpo = frente do carro
	for i in canos.size():
		var d := Transform3D()
		if mt and mt.is_inside_tree():
			var m: Node3D = [null, mt.malha, mt.malha_escape][mt.bocas.get(nomes[i], 0)]
			if m:
				d = pai * m.transform * pai.affine_inverse()
		var boca: Transform3D = xf * d * bases[i]
		var seg: Vector3 = boca.origin - antes[i] if antes[i].is_finite() else Vector3.ZERO
		if seg.length() > 3.0:          # teleporte (T, troca de carro)
			seg = Vector3.ZERO
		antes[i] = boca.origin
		var e: GPUParticles3D = canos[i]
		var pm: ShaderMaterial = e.process_material
		# o gás sai com a velocidade da boca (carro andando e girando)
		var vb: Vector3 = vc + car.angular_velocity.cross(boca.origin - com)
		pm.set_shader_parameter("v_boca", vb)
		pm.set_shader_parameter("dir_saida", boca.basis.z.normalized())
		pm.set_shader_parameter("v_carro", vc)
		pm.set_shader_parameter("boca", boca.origin)
		pm.set_shader_parameter("frente", frente)
		if seg.length() < 0.002:
			e.global_transform = boca
			pm.set_shader_parameter("meio_trecho", 0.0)
			continue
		var z := seg.normalized()
		var up := Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT
		var b := Basis.looking_at(-z, up)          # +Z local = o trecho andado
		e.global_transform = Transform3D(b, boca.origin - seg * 0.5)
		pm.set_shader_parameter("meio_trecho", seg.length() * 0.5)


## taxa pela carga do motor (car.som_carga) e pelo rpm
var _taxa := -1.0
func atualizar(carga: float, rpm: float) -> void:
	var r := clampf((rpm - 1000.0) / 7000.0, 0.0, 1.0)
	var t := clampf(TAXA_LENTA + (1.0 - TAXA_LENTA) * carga * (0.4 + 0.6 * r), 0.0, 1.0)
	if t == _taxa:                       # CPU: só regrava quando muda
		return
	_taxa = t
	for e in canos:
		e.amount_ratio = t


static var _shader: Shader = null


## o gás (shader de partícula, NOSSO; a conta está no cabeçalho)
func _processo() -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	var cor := COR if OS.get_environment("FUMACA_COR").strip_edges() != "1" else Color(1, 0, 0, 1)   # conferência: vermelha
	var pars := {"jato": JATO, "abertura": ABERTURA, "arrasto": ARRASTO, "esteira": ESTEIRA,
		"esteira_comp": ESTEIRA_COMP, "esteira_larg": ESTEIRA_LARG, "empuxo": EMPUXO,
		"esfria": ESFRIA, "turbulencia": TURBULENCIA, "tamanho": TAMANHO, "cresce": CRESCE,
		"cresce_vento": CRESCE_VENTO, "dilui": DILUI, "alfa": cor.a, "some": SOME}
	for k in pars:
		m.set_shader_parameter(k, pars[k])
	m.set_shader_parameter("cor", Vector3(cor.r, cor.g, cor.b))
	return m


const SHADER := """
shader_type particles;

uniform vec3 v_boca;          // velocidade da boca no mundo (m/s)
uniform vec3 dir_saida;       // direção do cano no mundo
uniform vec3 v_carro;         // velocidade do carro
uniform vec3 boca;            // boca agora (mundo)
uniform vec3 frente;          // frente do carro (mundo)
uniform float meio_trecho;    // metade do trecho que a boca andou no quadro
uniform float jato;
uniform float abertura;
uniform float arrasto;
uniform float esteira;
uniform float esteira_comp;
uniform float esteira_larg;
uniform float empuxo;
uniform float esfria;
uniform float turbulencia;
uniform float tamanho;
uniform float cresce;
uniform float cresce_vento;
uniform float dilui;
uniform float alfa;
uniform float some;
uniform vec3 cor;

// os mesmos sorteios do ParticleProcessMaterial
float rand_from_seed(inout uint seed) {
	int k;
	int s = int(seed);
	if (s == 0) {
		s = 305420679;
	}
	k = s / 127773;
	s = 16807 * (s - k * 127773) - 2836 * k;
	if (s < 0) {
		s += 2147483647;
	}
	seed = uint(s);
	return float(seed % uint(65536)) / 65535.0;
}

uint hash(uint x) {
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = (x >> uint(16)) ^ x;
	return x;
}

void start() {
	uint s = hash(NUMBER + uint(1) + RANDOM_SEED);
	float r0 = rand_from_seed(s);
	float r1 = rand_from_seed(s);
	float r2 = rand_from_seed(s);
	float r3 = rand_from_seed(s);
	float r4 = rand_from_seed(s);
	float r5 = rand_from_seed(s);
	// nasce num ponto do trecho que a boca andou no quadro (rastro contínuo)
	vec3 p = EMISSION_TRANSFORM[3].xyz + normalize(EMISSION_TRANSFORM[2].xyz) * (r0 * 2.0 - 1.0) * meio_trecho;
	vec3 d = normalize(dir_saida);
	vec3 a = normalize(cross(d, abs(d.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
	vec3 b = cross(d, a);
	vec3 dd = normalize(d + (a * (r1 * 2.0 - 1.0) + b * (r2 * 2.0 - 1.0)) * abertura);
	VELOCITY = v_boca + dd * jato * (0.8 + 0.4 * r3);
	CUSTOM = vec4(r4 * 3.14159, 0.0, r5, tamanho);    // giro, idade, fase, tamanho
	TRANSFORM = mat4(vec4(tamanho, 0.0, 0.0, 0.0), vec4(0.0, tamanho, 0.0, 0.0),
		vec4(0.0, 0.0, tamanho, 0.0), vec4(p, 1.0));
	COLOR = vec4(cor, alfa);
}

void process() {
	float idade = CUSTOM.y + DELTA;
	CUSTOM.y = idade;
	if (idade >= LIFETIME) {
		ACTIVE = false;
	}
	vec3 p = TRANSFORM[3].xyz;
	// ar: parado, menos atrás do carro (esteira puxada junto)
	vec3 rel = p - boca;
	float atras = -dot(rel, frente);
	vec3 lat = rel + frente * atras;
	float w = esteira * exp(-max(atras, 0.0) / esteira_comp) * exp(-dot(lat, lat) / (esteira_larg * esteira_larg));
	vec3 ar = v_carro * w;
	vec3 vr = VELOCITY - ar;
	float vento = length(vr);
	// arrasto exato (estável em qualquer FPS) + empuxo + turbulência
	float fase = CUSTOM.z * 6.2832;
	vec3 ruido = vec3(sin(p.y * 1.7 + TIME * 2.3 + fase), sin(p.z * 1.3 + TIME * 1.9 + fase * 1.3),
		sin(p.x * 1.5 + TIME * 2.1 + fase * 0.7));
	float turb = turbulencia * min(idade / 0.3, 1.0) * (1.0 + vento / 10.0);
	VELOCITY = ar + vr * exp(-arrasto * DELTA)
		+ (vec3(0.0, empuxo * exp(-idade / esfria), 0.0) + ruido * turb) * DELTA;
	// cresce (mais com vento) e dilui
	float tam = CUSTOM.w + (cresce + cresce_vento * vento) * DELTA;
	CUSTOM.w = tam;
	CUSTOM.x += (CUSTOM.z - 0.5) * DELTA;       // giro lento
	TRANSFORM[0] = vec4(tam, 0.0, 0.0, 0.0);
	TRANSFORM[1] = vec4(0.0, tam, 0.0, 0.0);
	TRANSFORM[2] = vec4(0.0, 0.0, tam, 0.0);
	float fim = clamp((1.0 - idade / LIFETIME) / some, 0.0, 1.0);
	COLOR = vec4(cor, alfa * pow(tamanho / tam, dilui) * fim);
}
"""


func _malha(tex: Texture2D) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2.ONE                # o shader põe o tamanho (m) na escala da partícula
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	# sem isto o billboard joga fora a escala da partícula e desenha o quad
	# inteiro (medido no lavapipe: escala 0.2 e 1.0 saem do mesmo tamanho). A
	# fumaça antiga (quad de 0.2 m) nunca cresceu por isso; a 1ª física (quad
	# de 1 m) saiu com bolas de 1 m ("ce ta de sacanagem ne?")
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	q.material = mat
	return q


static func _textura() -> Texture2D:
	if ResourceLoader.exists(TEXTURA):
		var t = load(TEXTURA)
		if t:
			return t
	var img := Image.load_from_file(ProjectSettings.globalize_path(TEXTURA))
	return ImageTexture.create_from_image(img) if img else null
