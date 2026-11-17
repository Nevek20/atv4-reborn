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
## (instance uniform por roda, carro_montagem._borrao_rodas). Parado (giro
## pequeno) é uma amostra só: igual ao material de antes.

const OBTURADOR := 1.0        # fração do quadro com o "obturador aberto"
const GIRO_MAX := 1.3         # rad: acima disso o aro já é um disco e a conta
                              # linear riscava o aro (3 rad, print); ~130 km/h a 50 FPS

const SHADER := """
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

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
}
"""

static var _shader: Shader


## material da roda (StandardMaterial3D já com o material_do_jogo) -> o shader
static func material(m: StandardMaterial3D) -> Material:
	if m.albedo_texture == null:
		return m
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var s := ShaderMaterial.new()
	s.shader = _shader
	s.set_shader_parameter("tex", m.albedo_texture)
	s.set_shader_parameter("cor", m.albedo_color)
	s.set_shader_parameter("usa_cor_vertice", m.vertex_color_use_as_albedo)
	s.set_shader_parameter("cor_vertice_srgb", m.vertex_color_is_srgb)
	return s


## ângulo do borrão deste quadro: |ω| (rad/s) x dt
static func giro(omega: float, dt: float) -> float:
	return minf(absf(omega) * dt * OBTURADOR, GIRO_MAX)
