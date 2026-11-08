extends Node3D
## Lanterna de freio e luz de ré acesas (melhoria nossa, car.gd LUZ_FREIO). No
## jogo a lente não muda: o VehicleHaloMap.xml (data/vehicle_halo_map.xml) põe
## nos pontos BRAKE_LIGHT* e REVERSE_LIGHT* um halo (VehicleHalos.xml: brilho
## laranja 1, 0.25, 0 com raios; o da ré branco quente) que o 0x203930 acende
## com o freio (0x390) >= 0.1 ou engatado de ré (aparece nos prints dos save
## states, farol.gd tem o desenho). O Matheus preferiu manter o nosso (lente
## acesa + halo vermelho). A lente vem da cor do vértice (vidro claro x vértice
## vermelho 167, 24, 24) ou da textura (Inferno, pintura do Storm).
##
## Lente = os PIXELS da cor da luz (vermelho no freio, branco na ré) na cor
## final (textura x cor do vértice, em linear) até RAIO do ponto. As faces que
## têm algum desses pixels (amostras a cada PASSO no triângulo, só as de
## dentro do raio: os triângulos da pintura do Storm são grandes e o centro
## deles caía longe do ponto da ré) ganham uma cópia por cima,
## um pouco pra fora pela normal, que SOMA a cor dela vezes GANHO + MIOLO só
## onde o pixel é da cor da luz (máscara no shader): no Storm a lanterna é
## pintada na textura (vermelho embaixo, branco da ré em cima) em triângulos
## grandes, e acender o triângulo inteiro desenhava triângulos claros.
## Cada lanterna ganha um HALO (brilho em volta, virado pra câmera, só de
## trás) no centro e no tamanho dos pixels acesos. Só somar não aparecia: a
## lente apagada já é vermelho puro (vértice 1.3 x sol). Sem luz pontual: de
## dia um OmniLight vermelho pintava gaiola, estepe e chão de rosa.
##
## Freio = brake_in (o suavizado do jogo, 0x390): inclui o freio que o jogo
## segura parado (0x202df0), então acende parado na largada, e zera na ré
## pelo freio. Ré = marcha -1 engatada. Acende e apaga em ACENDE / APAGA
## segundos (lâmpada). Só os carros com REVERSE_LIGHT no modelo têm ré.
##
## Trucks (out/2026, pedidos do Matheus): o brilho fica no RAIO do ponto
## também no shader (a cópia é do triângulo inteiro: no Shockwave a seta
## laranja, 23 cm acima do freio, está no mesmo triângulo e acendia junto);
## ponto com lente de verdade perto não acende a PINTURA em volta (o teto
## vermelho do Truggy acendia com o freio; Punisher, Chimera e Storm têm a
## lanterna pintada na pintura e continuam); pontos da mesma lanterna dão
## UM halo (Chimera: 2 pontos por lanterna); a lente acesa vai no máximo a
## BRILHO_MAX (lente clara x GANHO estourava pra salmão no Forward+). Pontos
## nossos por carro (ré nas duas lanternas, lanternas pintadas do Punisher):
## car.gd LUZES_NOSSAS.

const TIPOS := {
	"freio": {"pontos": ["BRAKE_LIGHT", "TAIL_LIGHT"], "raio": 0.15, "modo": 0,
		"halo": Color(1.0, 0.10, 0.04), "miolo": Color(0.45, 0.10, 0.06)},
	"re": {"pontos": ["REVERSE_LIGHT"], "raio": 0.12, "modo": 1,
		"halo": Color(1.0, 0.92, 0.80), "miolo": Color(0.35, 0.33, 0.30)},
}
const LIGA := 0.05            # brake_in acima disso = freando
const ACENDE := 0.06          # s
const APAGA := 0.15           # s
const GANHO := 6.0            # quanto a lente soma de luz acesa (x a cor dela)
const AFASTA := 0.002         # m: cópia pra fora da face (sem brigar no z)
const HALO_TAM := Vector2(0.10, 0.30)    # m: diâmetro = 1.6 x os pixels acesos, entre esses
const HALO_FORCA := 0.9
const JUNTA := 0.10           # m: pontos mais perto que isso viram um (TAIL_LIGHT x BRAKE_LIGHT)
const HALO_JUNTA := 0.30      # m: pixels acesos de pontos mais perto que isso dão um halo só (a mesma lanterna; Chimera 0.26)
const LENTE_MIN := 20         # amostras de lente (fora da pintura) pra o ponto ignorar a pintura em volta
# lanterna desenhada na pintura E com um pedaço de lente: a pintura acende
# junto (Mosquito: o hexágono branco da ré é da pintura, a light_64 é o miolo)
const PINTURA_E_LENTE := ["BUGGY_01"]
const BRILHO_MAX := 1.5       # teto da lente acesa (cor x GANHO), mantendo a cor
const MAX_CENTROS := 8        # pontos por tipo no shader
# máscara do freio por carro (pedido do Matheus: acender o desenho certinho;
# com o raio menor virava uma bola). Lanterna pintada na pintura:
# - Punisher: a seta laranja logo abaixo do vermelho tem razão vermelho/verde
#   2.3-2.6 (o vermelho 50+): razão a partir de 4
# - Chimera: os quadrados de cima são vermelho forte (0.4 linear), os de
#   baixo e as linhas entre os quadrados escuros (< 0.1): vermelho a partir
#   de 0.14; raio 26 cm: com 18 a borda do quadrado de dentro (perto do meio
#   do carro, 16-18 cm do ponto) apagava em curva
# razao / verm = as duas pontas do smoothstep (padrão 2-4 e 0.02-0.05)
const MASCARA_CARRO := {
	"TRUCK_05": {"freio": {"razao": Vector2(4.0, 6.0)}},
	"TRUCK_12": {"freio": {"verm": Vector2(0.14, 0.18), "raio": 0.26}},
}
const PASSO := 0.01           # m: amostras no triângulo (grade baricêntrica), até 20 por lado

# máscara da cor da luz (a mesma conta no shader e em _mascara). Branco da ré
# até saturação 0.4-0.55: a lente creme do Shockwave (0.25 a 0.5) não acendia
const GLSL_MASCARA := """
float mascara(vec3 c, int qual) {
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	if (qual == 0) {
		return smoothstep(razao.x, razao.y, c.r / max(max(c.g, c.b), 1e-4)) * smoothstep(verm.x, verm.y, c.r);
	}
	float sat = (mx - mn) / max(mx, 1e-4);
	return smoothstep(0.15, 0.30, mx) * (1.0 - smoothstep(0.40, 0.55, sat));
}
"""

const SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool tem_tex = true;
uniform float aceso = 0.0;
uniform float ganho = 6.0;
uniform float afasta = 0.002;
uniform float cor_k = 0.0;
uniform vec3 miolo = vec3(0.45, 0.10, 0.06);
uniform int modo = 0;            // 0 vermelho (freio), 1 branco (ré)
uniform vec2 razao = vec2(2.0, 4.0);   // vermelho / (verde ou azul), MASCARA_CARRO
uniform vec2 verm = vec2(0.02, 0.05);  // vermelho mínimo (linear)
uniform float brilho_max = 100.0;
uniform vec3 centros[8];         // pontos da luz (frame do modelo); n_centros 0 = sem raio (farol)
uniform int n_centros = 0;
uniform float raio = 1.0;
varying vec3 pos;

vec3 cor_v(vec3 c) {
	if (cor_k <= 0.0) {
		return vec3(1.0);
	}
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045))) * cor_k;
}
%s
void vertex() {
	pos = VERTEX;
	VERTEX += NORMAL * afasta;
}

void fragment() {
	vec3 t = tem_tex ? texture(tex, UV).rgb : vec3(1.0);
	vec3 c = t * cor_v(COLOR.rgb);
	float m = mascara(c, modo);
	if (n_centros > 0) {
		float d = 1e9;
		for (int i = 0; i < n_centros; i++) {
			d = min(d, distance(pos, centros[i]));
		}
		m *= 1.0 - smoothstep(raio * 0.85, raio, d);
	}
	float g = min(ganho, brilho_max / max(max(c.r, max(c.g, c.b)), 1e-4));
	ALBEDO = (c * g + miolo) * m * aceso;
}
"""

# brilho em volta da lanterna: quadrado virado pra câmera (montado na vista),
# puxado PUXA pra frente (não some dentro da caixa da lanterna), mais forte
# quanto mais a lente olha pra câmera
const SHADER_HALO := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform, fog_disabled;
uniform float aceso = 0.0;
uniform float tam = 0.3;
uniform vec3 frente = vec3(0.0, 0.0, -1.0);
uniform vec3 cor = vec3(1.0, 0.1, 0.04);
uniform float forca = 1.2;
uniform float puxa = 0.12;
varying float ver;

void vertex() {
	vec3 c = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 f = normalize((MODELVIEW_MATRIX * vec4(frente, 0.0)).xyz);
	vec3 cam = normalize(-c);
	ver = smoothstep(0.0, 0.5, dot(f, cam));
	VERTEX = c + vec3(VERTEX.xy * tam, 0.0) + cam * puxa;
}

void fragment() {
	float a = clamp(1.0 - length(UV - vec2(0.5)) * 2.0, 0.0, 1.0);
	a *= a;
	ALBEDO = mix(cor, vec3(1.0, 0.75, 0.65), a * a) * a * aceso * forca * ver;
}
"""

var car = null
var faces := {"freio": 0, "re": 0}     # faces de lente achadas por tipo
var halos := {"freio": 0, "re": 0}
var aceso := {"freio": 0.0, "re": 0.0}
var _mats := {"freio": [], "re": []}
var _imgs := {}


## acha as lentes na carroceria e monta as cópias. false = nada achado
func montar(c) -> bool:
	car = c
	var mi: MeshInstance3D = car.body_mi
	if mi == null or not (mi.mesh is ArrayMesh):
		return false
	var sh := Shader.new()
	sh.code = SHADER % GLSL_MASCARA
	var sh_halo := Shader.new()
	sh_halo.code = SHADER_HALO
	for tipo in TIPOS:
		_montar_tipo(mi, tipo, sh, sh_halo)
	return faces.freio + faces.re > 0


func _montar_tipo(mi: MeshInstance3D, tipo: String, sh: Shader, sh_halo: Shader) -> void:
	var def: Dictionary = TIPOS[tipo].duplicate()
	var aj: Dictionary = MASCARA_CARRO.get(car.vehicle_id, {}).get(tipo, {})
	def.raio = aj.get("raio", def.raio)
	var razao: Vector2 = aj.get("razao", Vector2(2.0, 4.0))
	var verm: Vector2 = aj.get("verm", Vector2(0.02, 0.05))
	var pts: Array[Vector3] = []
	for k in car.points:
		for p in def.pontos:
			var q: Vector3 = car.points[k]
			if String(k).begins_with(p) and pts.all(func(o): return o.distance_to(q) > JUNTA):
				pts.append(q)
	if pts.is_empty():
		return
	if pts.size() > MAX_CENTROS:
		push_warning("Luzes: %d pontos de %s, o shader usa %d" % [pts.size(), tipo, MAX_CENTROS])
	var mesh: ArrayMesh = mi.mesh
	var k_cor: float = car.cor_k()
	var modo: int = def.modo
	# 1ª passada: amostras acesas de cada triângulo perto (a cada PASSO, dentro
	# do raio), com o ponto mais perto e se é da pintura
	var tris: Array = []          # [superfície, [i0, i1, i2], [[p, ponto], ...], pintura]
	var lente := PackedInt32Array()
	lente.resize(pts.size())
	var sups := {}                # superfície -> [arrays, material, textura]
	for s in mesh.get_surface_count():
		var m := mi.get_active_material(s) as StandardMaterial3D
		if m == null or m.albedo_color.a <= 0.0:
			continue
		var a := mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ix := PackedInt32Array(range(vs.size()))
		if a[Mesh.ARRAY_INDEX] != null:
			ix = a[Mesh.ARRAY_INDEX]
		var tex: Texture2D = m.albedo_texture
		var pintura := m.resource_name.ends_with("_white")
		sups[s] = [a, tex]
		var img := _imagem(tex)
		var cols = a[Mesh.ARRAY_COLOR]
		var uvs = a[Mesh.ARRAY_TEX_UV]
		for t in range(0, ix.size(), 3):
			var i := [ix[t], ix[t + 1], ix[t + 2]]
			var v0: Vector3 = vs[i[0]]
			var v1: Vector3 = vs[i[1]]
			var v2: Vector3 = vs[i[2]]
			var cen := (v0 + v1 + v2) / 3.0
			var r_tri := maxf(cen.distance_to(v0), maxf(cen.distance_to(v1), cen.distance_to(v2)))
			if pts.all(func(q): return cen.distance_to(q) - r_tri > def.raio):
				continue
			var lado := maxf(v0.distance_to(v1), maxf(v1.distance_to(v2), v2.distance_to(v0)))
			var n_div := clampi(ceili(lado / PASSO), 2, 20)
			var acesas := []
			for u in n_div + 1:
				for w in n_div + 1 - u:
					var b := Vector3(u, w, n_div - u - w) / float(n_div)
					var p: Vector3 = v0 * b.x + v1 * b.y + v2 * b.z
					var perto := -1
					for j in pts.size():
						if p.distance_to(pts[j]) < def.raio and (perto < 0 or
								p.distance_to(pts[j]) < p.distance_to(pts[perto])):
							perto = j
					if perto < 0:
						continue
					var cor := Color(1, 1, 1)
					if img and uvs != null:
						cor = _amostra(img, uvs[i[0]] * b.x + uvs[i[1]] * b.y + uvs[i[2]] * b.z)
					if cols != null and k_cor > 0.0:
						var cv: Color = (cols[i[0]] * b.x + cols[i[1]] * b.y + cols[i[2]] * b.z).srgb_to_linear()
						cor = Color(cor.r * cv.r * k_cor, cor.g * cv.g * k_cor, cor.b * cv.b * k_cor)
					if _mascara(cor, modo, razao, verm) > 0.5:
						acesas.append([p, perto])
						if not pintura:
							lente[perto] += 1
			if not acesas.is_empty():
				tris.append([s, i, acesas, pintura])
	# 2ª passada: ponto com lente de verdade perto não acende a pintura em volta
	var por_sup := {}
	var grupos: Array = []
	for p in pts:
		grupos.append({"c": Vector3.ZERO, "n": Vector3.ZERO, "k": 0, "lo": Vector3.INF, "hi": -Vector3.INF})
	for tr in tris:
		var vale := []
		for am in tr[2]:
			if not (tr[3] and lente[am[1]] >= LENTE_MIN and not (car.vehicle_id in PINTURA_E_LENTE)):
				vale.append(am)
		if vale.is_empty():
			continue
		if not por_sup.has(tr[0]):
			por_sup[tr[0]] = PackedInt32Array()
		por_sup[tr[0]].append_array(PackedInt32Array(tr[1]))
		var nrs = sups[tr[0]][0][Mesh.ARRAY_NORMAL]
		for am in vale:
			var g: Dictionary = grupos[am[1]]
			g.c += am[0]
			g.k += 1
			g.lo = g.lo.min(am[0])
			g.hi = g.hi.max(am[0])
		if nrs != null:
			grupos[vale[-1][1]].n += nrs[tr[1][0]] + nrs[tr[1][1]] + nrs[tr[1][2]]
	var centros := PackedVector3Array(pts.slice(0, MAX_CENTROS))
	var malha := ArrayMesh.new()
	for s in por_sup:
		var arr: Array = sups[s][0].duplicate()
		var tex: Texture2D = sups[s][1]
		arr[Mesh.ARRAY_INDEX] = por_sup[s]
		arr[Mesh.ARRAY_TANGENT] = null
		malha.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("tex", tex)
		mat.set_shader_parameter("tem_tex", tex != null)
		mat.set_shader_parameter("ganho", GANHO)
		mat.set_shader_parameter("brilho_max", BRILHO_MAX)
		mat.set_shader_parameter("afasta", AFASTA)
		mat.set_shader_parameter("cor_k", k_cor)
		mat.set_shader_parameter("modo", modo)
		mat.set_shader_parameter("centros", centros)
		mat.set_shader_parameter("n_centros", centros.size())
		mat.set_shader_parameter("raio", def.raio)
		mat.set_shader_parameter("razao", razao)
		mat.set_shader_parameter("verm", verm)
		var mio: Color = def.miolo
		mat.set_shader_parameter("miolo", Vector3(mio.r, mio.g, mio.b))
		malha.surface_set_material(malha.get_surface_count() - 1, mat)
		_mats[tipo].append(mat)
		faces[tipo] += por_sup[s].size() / 3
	if faces[tipo] == 0:
		return
	var no := MeshInstance3D.new()
	no.name = "Lente_" + tipo
	no.mesh = malha
	no.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_child(no)
	for g in _juntar(grupos):
		var n: Vector3 = g.n.normalized() if g.n.length() > 0.0 else Vector3(0, 0, -1)
		var ext: Vector3 = g.hi - g.lo
		var q := QuadMesh.new()
		var mat := ShaderMaterial.new()
		mat.shader = sh_halo
		mat.set_shader_parameter("tam", clampf(1.6 * maxf(ext.x, maxf(ext.y, ext.z)), HALO_TAM.x, HALO_TAM.y))
		mat.set_shader_parameter("frente", n)
		var hc: Color = def.halo
		mat.set_shader_parameter("cor", Vector3(hc.r, hc.g, hc.b))
		mat.set_shader_parameter("forca", HALO_FORCA)
		q.material = mat
		var h := MeshInstance3D.new()
		h.name = "Halo_" + tipo
		h.mesh = q
		h.position = g.c / float(g.k) + n * 0.02
		h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		h.extra_cull_margin = 1.0
		mi.add_child(h, true)
		_mats[tipo].append(mat)
		halos[tipo] += 1


## grupos de pixels acesos com centro a menos de HALO_JUNTA viram um (a mesma lanterna)
static func _juntar(grupos: Array) -> Array:
	var out := []
	for g in grupos:
		if g.k == 0:
			continue
		var junto := false
		for o in out:
			if (o.c / float(o.k)).distance_to(g.c / float(g.k)) < HALO_JUNTA:
				o.c += g.c
				o.k += g.k
				o.n += g.n
				o.lo = o.lo.min(g.lo)
				o.hi = o.hi.max(g.hi)
				junto = true
				break
		if not junto:
			out.append(g.duplicate())
	return out


## freio 0..1 (brake_in) e ré engatada; a lâmpada sobe em ACENDE e desce em APAGA
func atualizar(delta: float, freio: float, re := false) -> void:
	var alvos := {"freio": 1.0 if freio > LIGA else 0.0, "re": 1.0 if re else 0.0}
	if OS.has_environment("FREIO"):              # print_tela: 1 acesa, 0 apagada
		alvos.freio = 1.0 if OS.get_environment("FREIO") == "1" else 0.0
	if OS.has_environment("RE"):
		alvos.re = 1.0 if OS.get_environment("RE") == "1" else 0.0
	for tipo in alvos:
		var vel := 1.0 / (ACENDE if alvos[tipo] > aceso[tipo] else APAGA)
		aceso[tipo] = move_toward(aceso[tipo], alvos[tipo], delta * vel)
		for m in _mats[tipo]:
			m.set_shader_parameter("aceso", aceso[tipo])


func _imagem(tex: Texture2D) -> Image:
	if tex == null:
		return null
	if _imgs.has(tex):
		return _imgs[tex]
	var img := tex.get_image()
	if img and img.is_compressed():
		img = img.duplicate()
		img.decompress()
	_imgs[tex] = img
	return img


## cor linear da textura no UV (repete fora de 0..1)
static func _amostra(img: Image, uv: Vector2) -> Color:
	var w := img.get_width()
	var h := img.get_height()
	var x := posmod(int(floor(uv.x * w)), w)
	var y := posmod(int(floor(uv.y * h)), h)
	return img.get_pixel(x, y).srgb_to_linear()


## a máscara do shader (GLSL_MASCARA) na CPU
static func _mascara(c: Color, qual: int, razao := Vector2(2.0, 4.0), verm := Vector2(0.02, 0.05)) -> float:
	var mx := maxf(c.r, maxf(c.g, c.b))
	var mn := minf(c.r, minf(c.g, c.b))
	if qual == 0:
		return smoothstep(razao.x, razao.y, c.r / maxf(maxf(c.g, c.b), 1e-4)) * smoothstep(verm.x, verm.y, c.r)
	var sat := (mx - mn) / maxf(mx, 1e-4)
	return smoothstep(0.15, 0.30, mx) * (1.0 - smoothstep(0.40, 0.55, sat))
