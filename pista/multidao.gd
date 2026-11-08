extends Node3D
## Multidão do RX01 (PORTA do jogo; docs/engenharia_reversa.md, Multidão):
## Levels/RX_01/Models/Wahoos/RX01_Crowds.wahoo ("Wahoo" = fotos de gente
## em placas, renderer cWahooRenderer), decifrado no tools/rx01_objetos.py
## (multidao()): 26 objetos, 233 pessoas, cada uma uma tira de 4 vértices em
## coordenadas do mundo do jogo, UV, cor (0x80 = 1.0) e textura pelo
## material. 20 objetos animam o UV por Setup/UVRGBAAnim.xml (AnimUV1
## FEX_Crowd_anim: 4 quadros de 0.25, FEX_Crowd_3frame: 3 de 0.33; cada
## chave fica "time" s e soma o Set_UV no UV; Ping_Pong = vai e volta).
## NOSSO: todos os objetos com a mesma animação andam juntos (o jogo cria
## um controle por objeto no 0x27b930; a fase não foi achada).

const Terrain := preload("res://pista/terrain.gd")
const PASTA := "res://assets/rx01/tex/"
const COR_K_SRGB := 255.0 / 128.0

var anims := {}                  # nome -> {chaves, ping_pong}
var mats := {}                   # "textura|anim" -> ShaderMaterial
var t := 0.0
var pessoas := 0


func montar(md: Dictionary) -> bool:
	anims = md.get("anims", {})
	var por: Dictionary = {}      # "textura|anim" -> SurfaceTool
	for o in md.get("objetos", []):
		var tex: String = o.get("textura", "")
		if tex == "" or not ResourceLoader.exists(PASTA + tex + ".png"):
			continue
		var anim = o.get("anim")
		var chave := "%s|%s" % [tex, anim if anim != null else ""]
		if not por.has(chave):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			por[chave] = st
		var st2: SurfaceTool = por[chave]
		for l in o.get("lotes", []):
			var pos: Array = l.pos
			var sem: Array = l.sem
			var uv: Array = l.uv
			var cor: Array = l.cor
			# tira do VIF: cada vértice sem o 0x8000 fecha um triângulo com os 2 de antes
			for i in range(2, pos.size()):
				if int(sem[i]) != 0:
					continue
				pessoas += 1 if i % 4 == 3 else 0
				for j in [i - 2, i - 1, i]:
					var c: Array = cor[j] if j < cor.size() else [128, 128, 128, 128]
					st2.set_color(Color(c[0] / 255.0 * COR_K_SRGB, c[1] / 255.0 * COR_K_SRGB,
						c[2] / 255.0 * COR_K_SRGB, 1.0))
					st2.set_uv(Vector2(uv[j][0], uv[j][1]))
					var p: Array = pos[j]
					st2.add_vertex(Terrain.do_jogo(Vector3(p[0], p[1], p[2])))
	for chave in por:
		var partes: PackedStringArray = String(chave).split("|")
		var m := ShaderMaterial.new()
		m.shader = _shader()
		m.set_shader_parameter("tex", load(PASTA + partes[0] + ".png"))
		m.set_meta("anim", partes[1])
		mats[chave] = m
		var mi := MeshInstance3D.new()
		mi.name = "Multidao_" + partes[0]
		mi.mesh = (por[chave] as SurfaceTool).commit()
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	_atualiza()
	return not mats.is_empty()


static var _sh: Shader = null


static func _shader() -> Shader:
	if _sh == null:
		_sh = Shader.new()
		_sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 uv_off = vec2(0.0);
void vertex() {
	UV += uv_off;
}
void fragment() {
	vec4 c = texture(tex, UV);
	ALBEDO = c.rgb * COLOR.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
"""
	return _sh


## UV da animação no tempo t: chaves com duração; ping-pong vai e volta
## sem repetir as pontas
static func uv_em(a: Dictionary, tt: float) -> Vector2:
	var ks: Array = a.get("chaves", [])
	if ks.is_empty():
		return Vector2.ZERO
	var ordem: Array = range(ks.size())
	if a.get("ping_pong", false) and ks.size() > 2:
		for i in range(ks.size() - 2, 0, -1):
			ordem.append(i)
	var total := 0.0
	for i in ordem:
		total += maxf(float(ks[i][0]), 0.001)
	var x := fmod(tt, total)
	for i in ordem:
		x -= maxf(float(ks[i][0]), 0.001)
		if x < 0.0:
			return Vector2(ks[i][1], ks[i][2])
	return Vector2(ks[ordem[-1]][1], ks[ordem[-1]][2])


func _process(dt: float) -> void:
	t += dt
	_atualiza()


func _atualiza() -> void:
	for chave in mats:
		var m: ShaderMaterial = mats[chave]
		var nome: String = m.get_meta("anim", "")
		m.set_shader_parameter("uv_off", uv_em(anims[nome], t) if anims.has(nome) else Vector2.ZERO)
