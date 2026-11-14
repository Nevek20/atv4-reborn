extends MultiMeshInstance3D
## Palha do fardo (PORTA do jogo; docs/engenharia_reversa.md, Objetos
## interativos): o fardo (GEN_HayBale) tem ParticleTrigger Type="Impact"
## Impulse="0.2" Timeout="0.1" no InstanceDatabase.xml e 2 pontos
## "particle Hay" no Levels/RX_01/Models/PtS/Bantams/GEN_HayBale.pts.
## Efeito "Hay" (Setup/Particles.xml): 10 por segundo, velocidade 0.5..1,
## Spray 6, direção (0, 1, 0). Sistema "BailedHay" (Effects/WorldFX.xml):
## até 30, vida 0.5..1 s, gravidade -9.8, cor (0.9, 0.75, 0.55), largura
## 0.05..0.07 x altura 0.4..0.7, giro 0..6 rad, entra em 0.1 s e some em 1 s,
## virada pra câmera (cRendererSimpleFaceme), textura Sprites/Particles
## caixa "snow" (no .bed é Snow0: tools/fx_jogo.py -> assets/efeitos/palha.png).
## Leituras NOSSAS (o código que dispara não foi achado no exe): impacto =
## soma dos impulsos de contato do passo (t·m/s) > Impulse liga a emissão por
## Timeout s; velocidade = (direção + esfera x Spray) x VelocityVariation,
## mais a do fardo no ponto; tamanho x 0.6 como a poeira (poeira.gd ESCALA).

const TEXTURA := "res://assets/efeitos/palha.png"
const ESCALA := 0.6

var q: Dictionary = {}           # "particula" do JSON
var vivas: Array = []            # {p, v, t, vida, w, h, ang}
var _rng := RandomNumberGenerator.new()


static func pronta() -> bool:
	return ResourceLoader.exists(TEXTURA)


func montar(dados: Dictionary) -> void:
	q = dados
	var s: Dictionary = q.get("sistema", {})
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	var quad := QuadMesh.new()
	multimesh.mesh = quad
	multimesh.instance_count = 256
	multimesh.visible_instance_count = 0
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
uniform sampler2D tex : source_color, filter_linear;
varying vec4 cor;
void vertex() {
	cor = COLOR;
	// virada pra câmera, girada no plano da tela (Angle), largura x altura
	vec3 centro = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float a = INSTANCE_CUSTOM.x;
	vec2 l = vec2(VERTEX.x * INSTANCE_CUSTOM.y, VERTEX.y * INSTANCE_CUSTOM.z);
	vec2 r = vec2(l.x * cos(a) - l.y * sin(a), l.x * sin(a) + l.y * cos(a));
	vec3 c = (VIEW_MATRIX * vec4(centro, 1.0)).xyz;
	POSITION = PROJECTION_MATRIX * vec4(c + vec3(r, 0.0), 1.0);
}
void fragment() {
	vec4 t = texture(tex, UV);
	ALBEDO = t.rgb * cor.rgb;
	// alfa do PS2: 0x80 = 1.0
	ALPHA = min(t.a * 255.0 / 128.0, 1.0) * cor.a;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	if ResourceLoader.exists(TEXTURA):
		m.set_shader_parameter("tex", load(TEXTURA))
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true
	extra_cull_margin = 16384.0


## um fardo emitindo: dt de emissão restante e acumulador por ponto
func emitir(bloco: Dictionary, dt: float) -> void:
	var rb: RigidBody3D = bloco.corpo
	var s: Dictionary = q.get("sistema", {})
	var taxa: float = q.get("taxa", 10.0)
	var pontos: Array = q.get("pontos", [])
	var local: Transform3D = bloco.malha_local
	for k in pontos.size():
		bloco.acum[k] += taxa * dt
		while bloco.acum[k] >= 1.0:
			bloco.acum[k] -= 1.0
			if vivas.size() >= int(s.get("max", 30)) * 4:   # 4 fardos ao mesmo tempo (nossa)
				break
			var pt: Array = pontos[k]
			var p: Vector3 = rb.global_transform * (local * Vector3(pt[0], pt[1], pt[2]))
			var d: Array = q.get("dir", [0, 1, 0])
			var dir := rb.global_transform.basis.orthonormalized() * Vector3(d[0], d[1], d[2])
			var esf := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1))
			while esf.length() > 1.0:
				esf = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1))
			var vv: Array = q.get("vel", [0.5, 1.0])
			var v: Vector3 = (dir + esf * float(q.get("spray", 0.0))) * _rng.randf_range(vv[0], vv[1])
			v += rb.linear_velocity + rb.angular_velocity.cross(p - rb.global_position)
			vivas.append({"p": p, "v": v, "t": 0.0, "vida": _faixa(s, "Life", 0.75),
				"w": _faixa(s, "Width", 0.06) * ESCALA, "h": _faixa(s, "Height", 0.5) * ESCALA,
				"ang": _faixa(s, "Angle", 0.0)})


func _faixa(s: Dictionary, k: String, padrao: float) -> float:
	var f = s.get(k, padrao)
	if f is Array:
		return _rng.randf_range(f[0], f[1])
	return float(f)


func passo(dt: float) -> void:
	# CPU: nada vivo e o multimesh já vazio: não tem o que andar nem desenhar
	if vivas.is_empty() and multimesh.visible_instance_count == 0:
		return
	var s: Dictionary = q.get("sistema", {})
	var g: Array = s.get("gravidade", [0, -9.8, 0])
	var grav := Vector3(g[0], g[1], g[2])
	var cor: Array = s.get("Colour", [1, 1, 1, 1])
	var fin: float = s.get("FadeInTime", 0.1)
	var fout: float = s.get("FadeOutTime", 1.0)
	var k := 0
	for i in range(vivas.size() - 1, -1, -1):
		var e: Dictionary = vivas[i]
		e.t += dt
		if e.t >= e.vida:
			vivas.remove_at(i)
			continue
		e.v += grav * dt
		e.p += e.v * dt
	for e in vivas:
		if k >= multimesh.instance_count:
			break
		var a: float = minf(e.t / maxf(fin, 1e-3), 1.0) * minf((e.vida - e.t) / maxf(fout, 1e-3), 1.0)
		multimesh.set_instance_transform(k, Transform3D(Basis(), e.p))
		multimesh.set_instance_color(k, Color(cor[0], cor[1], cor[2], cor[3] * clampf(a, 0.0, 1.0)))
		multimesh.set_instance_custom_data(k, Color(e.ang, e.w, e.h, 0.0))
		k += 1
	multimesh.visible_instance_count = k
