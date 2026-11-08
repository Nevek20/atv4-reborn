extends RefCounted
## Desenho da sujeira no carro, nas rodas e no piloto (car.gd SUJEIRA; os
## números vêm do car.gd: _sujeira_passo = 0x223e68, _roda_suja_passo =
## 0x224418).
##
## Carro: o lote da pintura ("white") de cada carroceria tem uma 2ª textura,
## "dirt" (registro do lote +0x18, 2 texturas em +0x08), desenhada por cima
## pelo 2º UV. A "dirt" do modelo é um 8x8 vazio: vale a da pista
## (TrackProperties Dirt mDirtTextureName = GEN_DIRT_DIRT em todas). O alfa
## dela é o alfa da cor do vértice, que o 0x3b3a78 põe em nível·128 em todo o
## carro. O tools/pingu2obj.py salva essas tiras com o 2º UV em
## <modelo>_camada.obj (no Kraken também 2 peças da suspensão de trás).
##
## Rodas: a camada é a UNI_TyreOverlay (igual nos 46 pneus do jogo, pneu e
## aro) e o jogo troca a paleta de 16 cores dela (0x224148): cor = a lama de
## agora ·128, alfa = alfa da lama x alfa original da entrada. Não depende do
## nível do carro.
##
## Piloto (nosso): a textura de sujeira do piloto (Characters/Textures/Dirt)
## projetada nos 3 eixos da pose de repouso (CUSTOM0/1 da malha, piloto.gd:
## a posição animada fazia o braço andar por dentro da textura) com o nível
## do carro. O jeito do jogo no piloto não foi achado.

const TEX := "res://assets/fx/sujeira.png"
const TEX_PILOTO := "res://assets/fx/sujeira_piloto.png"
const TEX_LAMA := "res://assets/fx/lama_pneu.png"
const ESCALA_PILOTO := 0.6    # metros por repetição no piloto (nosso)

const SHADER_CAMADA := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 cor = vec4(1.0);     // rodas: cor da lama; carro: branco
uniform float nivel = 0.0;        // carro: alfa do vértice; rodas: 1
uniform bool so_alfa = false;     // rodas: a cor sai da paleta trocada
uniform float cor_k = 0.0;        // cor do vértice do jogo (car.gd cor_k; 0 = sem)

vec3 cor_v(vec3 c) {
	if (cor_k <= 0.0) {
		return vec3(1.0);
	}
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045))) * cor_k;
}

void fragment() {
	vec4 t = texture(tex, UV);
	ALBEDO = (so_alfa ? cor.rgb : t.rgb) * cor_v(COLOR.rgb);
	ALPHA = t.a * cor.a * nivel;
}
"""

const SHADER_PILOTO := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float nivel = 0.0;
uniform float escala = 0.6;

varying vec3 p_obj;
varying vec3 n_obj;

void vertex() {
	p_obj = CUSTOM0.xyz;
	n_obj = CUSTOM1.xyz;
}

void fragment() {
	vec3 w = pow(abs(normalize(n_obj)), vec3(4.0));
	w /= w.x + w.y + w.z;
	vec4 t = texture(tex, p_obj.zy / escala) * w.x
		+ texture(tex, p_obj.xz / escala) * w.y
		+ texture(tex, p_obj.xy / escala) * w.z;
	ALBEDO = t.rgb;
	ALPHA = t.a * nivel;
}
"""

var carro: ShaderMaterial          # camada "dirt" (pintura)
var lama: ShaderMaterial           # UNI_TyreOverlay (rodas)
var piloto: ShaderMaterial
var camadas := 0                   # quantas malhas de camada achou
var aviso := ""                    # o que falta gerar (o HUD mostra)
var byte := -1


## põe as camadas. Sem as texturas (assets/fx, tools/fx_jogo.py) ou sem os
## _camada.obj (tools/gerar_buggies.py) não desenha e devolve false.
func montar(car) -> bool:
	if not ResourceLoader.exists(TEX):
		return false
	carro = _material(SHADER_CAMADA, load(TEX))
	carro.set_shader_parameter("cor_k", car.cor_k())
	if ResourceLoader.exists(TEX_LAMA):
		lama = _material(SHADER_CAMADA, load(TEX_LAMA))
		lama.set_shader_parameter("so_alfa", true)
		lama.set_shader_parameter("nivel", 1.0)
		lama.set_shader_parameter("cor_k", car.cor_k())
	# carroceria: a malha dela pode ter sido trocada (motor_treme), então vai
	# pelo caminho do modelo
	if car.body_mi:
		_camada(car.body_mi, car.model_path, carro)
		if camadas == 0:
			aviso = "sem _camada.obj: rode o gerar_buggies"
	var rodas: Array = [car.wheel_front_file, car.wheel_rear_file]
	for mi in _malhas(car):
		var path: String = mi.mesh.resource_path
		if mi == car.body_mi or path == "" or path.ends_with("_camada.obj"):
			continue
		if path in rodas:
			if lama:
				_camada(mi, path, lama)
			elif aviso == "":
				aviso = "sem lama_pneu.png: rode o fx_jogo"
		else:
			_camada(mi, path, carro)
	if car.piloto and car.piloto.malha and ResourceLoader.exists(TEX_PILOTO):
		piloto = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = SHADER_PILOTO
		piloto.shader = sh
		piloto.set_shader_parameter("tex", load(TEX_PILOTO))
		piloto.set_shader_parameter("escala", ESCALA_PILOTO)
		car.piloto.malha.material_overlay = piloto
	if aviso != "":
		push_warning("Sujeira: " + aviso)
	return camadas > 0 or piloto != null


## nível do carro 0..1 e cor da lama das rodas. O jogo grava o alfa do
## vértice como byte (int)(nível·128): muda em degraus.
func atualizar(nivel: float, cor_roda: Color) -> void:
	if lama:
		# paleta: cor·128 (o png das texturas vai de 0 a 255) e alfa x alfa da entrada
		lama.set_shader_parameter("cor", Color(cor_roda.r * 128.0 / 255.0,
			cor_roda.g * 128.0 / 255.0, cor_roda.b * 128.0 / 255.0, cor_roda.a))
	var b := int(nivel * 128.0)
	if b == byte:
		return
	byte = b
	carro.set_shader_parameter("nivel", b / 128.0)
	if piloto:
		piloto.set_shader_parameter("nivel", b / 128.0)


func _camada(mi: MeshInstance3D, path: String, mat: ShaderMaterial) -> void:
	var cp := path.get_basename() + "_camada.obj"
	if not ResourceLoader.exists(cp):
		return
	var c := MeshInstance3D.new()
	c.name = "Camada"
	c.mesh = load(cp)
	c.material_override = mat
	c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_child(c)
	camadas += 1


static func _material(code: String, tex: Texture2D) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("tex", tex)
	return m


static func _malhas(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for c in n.get_children():
		if c is MeshInstance3D and c.mesh:
			out.append(c)
		out.append_array(_malhas(c))
	return out
