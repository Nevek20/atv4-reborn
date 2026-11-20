extends RefCounted
## Borrão de movimento nas rodas (NOSSO: o jogo não tem; o mMotionBlur das
## câmeras do jogo é o borrão de tela inteira das câmeras de dentro). Sem
## ele, a 50-60 quadros por segundo a roda gira tanto entre um quadro e
## outro que o aro e os cravos parecem travar ou girar ao contrário.
## O material da roda vira este shader com a MESMA cor do material_do_jogo
## (textura x albedo x cor do vértice sRGB). Em cada pixel ele gira o ponto
## da roda de -giro/2 a +giro/2 em volta do eixo (o X do modelo da roda) e
## leva esse deslocamento pra UV pelas derivadas de tela da posição e da UV:
## serve pra qualquer mapeamento (aro de frente, banda do pneu em U, V ou
## diagonal) sem tabela por modelo. giro = |ω| x dt do quadro x OBTURADOR
## (instance uniform por roda, carro_montagem._update_visuals). Parado (giro
## pequeno) é uma amostra só: igual ao material de antes.
## Isso só borra a TEXTURA: os cravos dos pneus comprados, o contorno
## poligonal e os parafusos do cubo são geometria e continuavam nítidos ("o
## pneu parece parado e andando ao mesmo tempo", Matheus). Por isso a roda do
## jogador ganha COPIAS-1 cópias (fantasmas) giradas dentro do giro do quadro,
## transparentes (alfa 1/2, 1/3... na ordem do render_priority = média igual
## das cópias) e um pouco pra frente da câmera (VIES) pra ganhar da roda no
## mesmo lugar. Cada cópia borra a textura só na fatia dela (giro/COPIAS), aí
## a média cobre o giro inteiro sem buraco. Abaixo de GIRO_FANTASMA as cópias
## somem (sem custo parado ou devagar). Rivais: só o borrão de textura.

const OBTURADOR := 1.0        # fração do quadro com o "obturador aberto"
const GIRO_MAX := 1.3         # rad: acima disso o aro já é um disco e a conta
                              # linear riscava o aro (3 rad, print); ~130 km/h a 50 FPS
const COPIAS := 9             # roda + 8 fantasmas (ímpar: a do meio é a roda; com 5
                              # os cravos apareciam em degraus no contorno)
const GIRO_FANTASMA := 0.12   # rad por quadro (~12 km/h): abaixo disso sem cópias
const VIES := 0.015           # m pra frente da câmera (cópia sobre a roda)

const SHADER := """
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx{MODO};

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 cor : source_color = vec4(1.0);
uniform bool usa_cor_vertice = false;
uniform bool cor_vertice_srgb = true;
instance uniform float giro = 0.0;     // ângulo da roda neste quadro (rad)

varying vec3 eixo_v;     // eixo da roda (view)
varying vec3 centro_v;   // centro da roda (view)

void vertex() {
	// igual ao StandardMaterial3D (vertex_color_is_srgb): só converte quando a
	// saída não é sRGB (Forward+ sim, Compatibility não)
	if (usa_cor_vertice && cor_vertice_srgb && !OUTPUT_IS_SRGB) {
		COLOR.rgb = mix(pow((COLOR.rgb + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), COLOR.rgb * (1.0 / 12.92), lessThan(COLOR.rgb, vec3(0.04045)));
	}
	eixo_v = normalize((MODELVIEW_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz);
	centro_v = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
{VERTEX}
}

vec3 gira(vec3 v, vec3 k, float a) {   // Rodrigues
	float c = cos(a);
	float s = sin(a);
	return v * c + cross(k, v) * s + k * dot(k, v) * (1.0 - c);
}

void fragment() {
	vec4 t;
	int n = int(clamp(abs(giro) * 10.0, 1.0, 12.0));
	if (n <= 1) {
		t = texture(tex, UV);
	} else {
		vec3 dpx = dFdx(VERTEX);
		vec3 dpy = dFdy(VERTEX);
		vec2 dux = dFdx(UV);
		vec2 duy = dFdy(UV);
		float a11 = dot(dpx, dpx);
		float a12 = dot(dpx, dpy);
		float a22 = dot(dpy, dpy);
		float det = a11 * a22 - a12 * a12;
		vec3 r = VERTEX - centro_v;
		t = vec4(0.0);
		for (int i = 0; i < n; i++) {
			float a = giro * (float(i) / float(n - 1) - 0.5);
			vec3 d = gira(r, eixo_v, a) - r;
			vec2 duv = vec2(0.0);
			if (abs(det) > 1e-20) {
				float bx = dot(dpx, d);
				float by = dot(dpy, d);
				float s = (a22 * bx - a12 * by) / det;
				float q = (a11 * by - a12 * bx) / det;
				duv = s * dux + q * duy;
			}
			t += textureGrad(tex, UV + duv, dux, duy);
		}
		t /= float(n);
	}
	vec3 c = t.rgb * cor.rgb;
	if (usa_cor_vertice) {
		c *= COLOR.rgb;
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
{FRAG}
}
"""

const FANTASMA_UNIFORMS := """
uniform float alfa = 0.5;
uniform float vies = 0.015;
"""
const FANTASMA_VERTEX := """
	vec3 cam = (inverse(MODELVIEW_MATRIX) * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	VERTEX += normalize(cam - VERTEX) * vies;
"""

static var _shader: Shader
static var _shader_fantasma: Shader


static func _codigo(fantasma: bool) -> String:
	var c := SHADER
	c = c.replace("{MODO}", ", blend_mix, depth_draw_never" if fantasma else "")
	c = c.replace("{VERTEX}", FANTASMA_VERTEX if fantasma else "")
	c = c.replace("{FRAG}", "\tALPHA = alfa;" if fantasma else "")
	if fantasma:
		c = c.replace("varying vec3 eixo_v;", FANTASMA_UNIFORMS + "\nvarying vec3 eixo_v;")
	return c


## material da roda (StandardMaterial3D já com o material_do_jogo) -> o shader.
## fantasma = k (1..COPIAS-1): a k-ésima cópia transparente, alfa 1/(k+1)
static func material(m: StandardMaterial3D, fantasma := 0) -> Material:
	if m.albedo_texture == null:
		return null if fantasma else m
	if _shader == null:
		_shader = Shader.new()
		_shader.code = _codigo(false)
		_shader_fantasma = Shader.new()
		_shader_fantasma.code = _codigo(true)
	var s := ShaderMaterial.new()
	s.shader = _shader_fantasma if fantasma else _shader
	s.set_shader_parameter("tex", m.albedo_texture)
	s.set_shader_parameter("cor", m.albedo_color)
	s.set_shader_parameter("usa_cor_vertice", m.vertex_color_use_as_albedo)
	s.set_shader_parameter("cor_vertice_srgb", m.vertex_color_is_srgb)
	if fantasma:
		s.set_shader_parameter("alfa", 1.0 / float(fantasma + 1))
		s.set_shader_parameter("vies", VIES)
		s.render_priority = fantasma          # desenha na ordem: média igual
	return s


## as cópias de uma roda (filhas do giro dela, como a roda): mesma malha,
## material fantasma, sem sombra, escondidas até girar rápido
static func fantasmas(mi: MeshInstance3D) -> Array:
	var out: Array = []
	for k in range(1, COPIAS):
		var f := MeshInstance3D.new()
		f.mesh = mi.mesh
		f.set_meta("fantasma", true)       # sujeira.gd pula (lama não empilha)
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in mi.mesh.get_surface_count():
			var m = mi.mesh.surface_get_material(i)
			var base = mi.get_surface_override_material(i)
			if base is ShaderMaterial and m is StandardMaterial3D:
				var m2 := StandardMaterial3D.new()
				m2.albedo_texture = base.get_shader_parameter("tex")
				m2.albedo_color = base.get_shader_parameter("cor")
				m2.vertex_color_use_as_albedo = base.get_shader_parameter("usa_cor_vertice")
				m2.vertex_color_is_srgb = base.get_shader_parameter("cor_vertice_srgb")
				f.set_surface_override_material(i, material(m2, k))
		f.visible = false
		mi.get_parent().add_child(f)
		out.append(f)
	return out


## ângulo do borrão deste quadro: |ω| (rad/s) x dt
static func giro(omega: float, dt: float) -> float:
	return minf(absf(omega) * dt * OBTURADOR, GIRO_MAX)


## põe o borrão do quadro na roda (mi) e nas cópias dela (fantasmas):
## rápido = a roda e cada cópia num ângulo e borrando a fatia dela
static func aplicar(mi: MeshInstance3D, fant: Array, espelha: bool, a: float) -> void:
	var com := not fant.is_empty() and a >= GIRO_FANTASMA
	mi.set_instance_shader_parameter("giro", a / COPIAS if com else a)
	var meio := COPIAS / 2
	var j := 0
	for f in fant:
		if j == meio:
			j += 1                       # a do meio é a própria roda
		f.visible = com
		if com:
			var ang: float = a * ((float(j) + 0.5) / COPIAS - 0.5)
			f.transform = Transform3D(Basis(Vector3.RIGHT, ang) * Basis.from_scale(Vector3(-1.0 if espelha else 1.0, 1.0, 1.0)), Vector3.ZERO)
			f.set_instance_shader_parameter("giro", a / COPIAS)
		j += 1
