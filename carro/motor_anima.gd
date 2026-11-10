extends Node
## Motor animado (melhoria nossa, car.gd MOTOR_ANIMA). No jogo nada gira: as
## ventoinhas dos radiadores e as polias do motor são desenho parado na
## textura (placas planas da Body).
##
## Ventoinhas (VENTOINHAS): os triângulos que desenham o círculo da ventoinha
## (textura "black": Renegade, Sphinx, Mosquito, Inferno, Bulldog, McKenzies;
## "tube02": Trident) saem pra uma malha própria e o SHADER gira o círculo da
## textura em volta do centro. Elétrica (escolha do Matheus): liga com o motor
## e gira fixa, VENTOINHA_VOLTAS por segundo, subindo em VENTOINHA_SOBE.
## Placa grande demais (mais de RAIO_MAX) não gira: no Mosquito a textura
## cobre um painel do lado.
##
## Polias e correia 3D (POLIA_CARROS: Phantom, Kraken, McKenzies, Viper): a
## textura "chassis_tri02" tem 2 polias desenhadas (POLIAS); onde elas caem
## na malha (o centro do círculo dentro do UV do triângulo, com a textura
## repetindo) vira uma polia de verdade: cilindro do raio desenhado com a
## tampa mostrando o próprio desenho do jogo girando. As 2 polias de cada
## carro levam uma correia fechada pelas tangentes de fora, com nervuras
## correndo na velocidade da borda. Faces em planos diferentes (Phantom e
## Viper, 8 a 11 cm): as tampas ficam todas no plano da mais saliente.
## Giro "legível" (escolha do Matheus): a polia maior (virabrequim) dá
## VOLTAS_POR_1000 voltas por segundo a cada 1000 rpm (na lenta dá pra ver
## girar; o real seria 17 a 133 voltas/s, um disco borrado) e a outra gira na
## proporção dos raios.
## Borrão de movimento: o shader mistura RASTRO amostras do ângulo que a peça
## andou no quadro.
## Tudo fica preso na malha onde a face está ("Motor" do motor_treme.gd
## treme junto).

const VENTOINHAS := [            # [parte do nome da textura, centro (px), raio (px)]
	["_black", Vector2(89, 26), 23.0],
	["tube02", Vector2(48, 48), 15.0],
	["preRunnerTruck_fan", Vector2(32, 32), 31.0],     # Lazarus: a textura é a ventoinha inteira
]
const VENTOINHA_VOLTAS := 3.0     # voltas/s (elétrica, fixa)
const VENTOINHA_SOBE := 0.7       # s: constante da partida
const RAIO_MAX := 0.25            # m: placa maior que isso não é ventoinha
const RAIO_MAX_TRUCK := 0.35      # m: nos trucks elas têm 27 a 31 cm (Panther, Truggy, Hammerhead)
const POLIA_TEX := "chassis_tri02"
const POLIAS := [[Vector2(99, 23), 9.0], [Vector2(100, 51), 8.0]]   # desenho (px)
const POLIA_CARROS := ["BUGGY_06", "BUGGY_07", "BUGGY_08", "BUGGY_09"]
const VOLTAS_POR_1000 := 1.0      # voltas/s da polia maior a cada 1000 rpm
const POLIA_LARG := 0.025         # m: largura da polia (sai da face)
const CORREIA_LARG := 0.016       # m
const CORREIA_ESP := 0.006        # m
const PAR_MAX := 0.6              # m: polias mais longe que isso não levam correia
const DEGRAU_MAX := 0.15          # m: diferença de plano máxima entre as polias
const NERVURA := 0.012            # m: comprimento de uma nervura da correia
const RASTRO := 6                 # amostras do borrão

const SHADER_ROTOR := """
shader_type spatial;
render_mode cull_back;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 tam = vec2(128.0, 64.0);   // pixels da textura
uniform vec2 centro;                     // centro do círculo (px)
uniform float raio;                      // px
uniform float ang = 0.0;                 // rad
uniform float rastro = 0.0;              // rad que andou no quadro (borrão)
uniform float cor_k = 0.0;        // cor do vértice do jogo (car.gd cor_k; 0 = sem)
uniform bool diag = false;        // VENTOINHA_COR=1: vermelho

vec3 cor_v(vec3 c) {
	if (cor_k <= 0.0) {
		return vec3(1.0);
	}
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045))) * cor_k;
}

void fragment() {
	vec2 p = UV * tam;
	vec2 c = centro + round((p - centro) / tam) * tam;   // a textura repete
	vec2 d = p - c;
	vec2 gx = dFdx(UV);
	vec2 gy = dFdy(UV);
	if (length(d) < raio) {
		vec3 soma = vec3(0.0);
		for (int i = 0; i < %d; i++) {
			float a = ang - rastro * (float(i) / float(%d - 1) - 0.5);
			float s = sin(a);
			float co = cos(a);
			vec2 q = vec2(co * d.x - s * d.y, s * d.x + co * d.y);
			soma += textureGrad(tex, (c + q) / tam, gx, gy).rgb;
		}
		ALBEDO = soma / float(%d);
	} else {
		ALBEDO = textureGrad(tex, UV, gx, gy).rgb;
	}
	ALBEDO *= cor_v(COLOR.rgb);
	if (diag) {
		ALBEDO = vec3(1.0, 0.0, 0.0);
	}
}
"""

const SHADER_CORREIA := """
shader_type spatial;
render_mode cull_back;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float desloc = 0.0;              // nervuras que a correia andou
uniform float rastro = 0.0;              // nervuras andadas no quadro (borrão)

void fragment() {
	vec3 soma = vec3(0.0);
	for (int i = 0; i < %d; i++) {
		float k = desloc + rastro * (float(i) / float(%d - 1) - 0.5);
		soma += texture(tex, UV - vec2(k, 0.0)).rgb;
	}
	ALBEDO = soma / float(%d);
	ROUGHNESS = 0.8;
}
"""

var car = null
var ventoinhas: Array = []        # ShaderMaterial de cada malha de ventoinha
var polias: Array = []            # {mat: ShaderMaterial, raio: float, sinal: float}
var correias: Array = []          # {mat, polia (raio da que puxa)}
var n_ventoinhas := 0             # placas de ventoinha (conferência)
var _t := 0.0
var _ang_v := 0.0
var _ang_p := 0.0                 # ângulo da polia maior (rad)
var _raio_p := 0.0                # raio da polia maior (m)
var _shader_rotor: Shader
var _shader_correia: Shader


func montar(c) -> bool:
	car = c
	_shader_rotor = Shader.new()
	_shader_rotor.code = SHADER_ROTOR % [RASTRO, RASTRO, RASTRO]
	_shader_correia = Shader.new()
	_shader_correia.code = SHADER_CORREIA % [RASTRO, RASTRO, RASTRO]
	var alvos: Array = [car.body_mi]
	if car.motor_treme:
		alvos.append_array([car.motor_treme.malha, car.motor_treme.malha_escape])
	for mi in alvos:
		if mi and mi.mesh is ArrayMesh:
			_ventoinhas(mi)
	if car.vehicle_id in POLIA_CARROS:
		for mi in alvos:
			if mi and mi.mesh is ArrayMesh:
				_polias(mi)
	return not ventoinhas.is_empty() or not polias.is_empty()


func atualizar(delta: float, rpm: float) -> void:
	if delta <= 0.0:
		return
	_t += delta
	var wv := TAU * VENTOINHA_VOLTAS * (1.0 - exp(-_t / VENTOINHA_SOBE))
	_ang_v = fmod(_ang_v + wv * delta, TAU)
	for m in ventoinhas:
		m.set_shader_parameter("ang", _ang_v)
		m.set_shader_parameter("rastro", wv * delta)
	if polias.is_empty():
		return
	var wp := TAU * VOLTAS_POR_1000 * maxf(rpm, 0.0) / 1000.0
	_ang_p += wp * delta
	for p in polias:
		var k: float = _raio_p / p.raio
		p.mat.set_shader_parameter("ang", fmod(_ang_p * k, TAU) * p.sinal)
		p.mat.set_shader_parameter("rastro", wp * k * delta)
	for c in correias:
		var andou: float = _ang_p * _raio_p / NERVURA
		c.mat.set_shader_parameter("desloc", fmod(andou, 1024.0))
		c.mat.set_shader_parameter("rastro", wp * _raio_p * delta / NERVURA)


# ---------------------------------------------------------------- ventoinhas

## tira da malha os triângulos que desenham o círculo de uma ventoinha e põe
## numa malha filha com o shader que gira
func _ventoinhas(mi: MeshInstance3D) -> void:
	var velha: ArrayMesh = mi.mesh
	var nova := ArrayMesh.new()
	var mats := []
	var achou := false
	for s in velha.get_surface_count():
		var arr := velha.surface_get_arrays(s)
		var m: Material = mi.get_active_material(s)
		var tex: Texture2D = m.albedo_texture if m is BaseMaterial3D else null
		var def: Array = []
		if tex:
			for v in VENTOINHAS:
				if v[0] in tex.resource_path:
					def = v
		if def.is_empty() or arr[Mesh.ARRAY_TEX_UV] == null:
			nova.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			mats.append(m)
			continue
		var tam := tex.get_size()
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var ix := PackedInt32Array(range(vs.size()))
		if arr[Mesh.ARRAY_INDEX] != null:
			ix = arr[Mesh.ARRAY_INDEX]
		var fica := PackedInt32Array()
		var gira := PackedInt32Array()
		var cand := {}
		for t in range(0, ix.size(), 3):
			if _na_ventoinha(vs, uvs, [ix[t], ix[t + 1], ix[t + 2]], tam, def[1], def[2],
					RAIO_MAX_TRUCK if car.vehicle_id.begins_with("TRUCK") else RAIO_MAX):
				cand[t] = true
		var placa := _placas_ventoinha(vs, uvs, ix, cand, tam, def[1], def[2])
		for t in range(0, ix.size(), 3):
			if placa.has(t):
				gira.append_array([ix[t], ix[t + 1], ix[t + 2]])
			else:
				fica.append_array([ix[t], ix[t + 1], ix[t + 2]])
		if not fica.is_empty():
			var a := arr.duplicate()
			a[Mesh.ARRAY_INDEX] = fica
			nova.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			mats.append(m)
		if not gira.is_empty():
			achou = true
			var a := arr.duplicate()
			a[Mesh.ARRAY_INDEX] = gira
			var mm := ArrayMesh.new()
			mm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			var vmi := MeshInstance3D.new()
			vmi.name = "Ventoinha"
			vmi.mesh = mm
			var mat := _rotor(tex, def[1], def[2] + 0.5)
			vmi.material_override = mat
			mi.add_child(vmi, true)
			ventoinhas.append(mat)
			n_ventoinhas += _placas(vs, gira)
	if not achou:
		return
	mi.mesh = nova
	for s in mats.size():
		mi.set_surface_override_material(s, mats[s])


## triângulo de ventoinha: o centro do UV dele cai no círculo, não é um
## triângulo degenerado (um texel só, como as peças pretas do Renegade) e a
## placa não é grande demais
static func _na_ventoinha(vs: PackedVector3Array, uvs: PackedVector2Array, tri: Array,
		tam: Vector2, centro: Vector2, raio: float, raio_max := RAIO_MAX) -> bool:
	var p0: Vector2 = uvs[tri[0]] * tam
	var p1: Vector2 = uvs[tri[1]] * tam
	var p2: Vector2 = uvs[tri[2]] * tam
	var area := absf((p1 - p0).cross(p2 - p0)) * 0.5
	if area < 0.03 * raio * raio:
		return false
	var g := (p0 + p1 + p2) / 3.0
	var c := centro + ((g - centro) / tam).round() * tam
	if g.distance_to(c) > raio:
		return false
	# metros por pixel, pela aresta mais comprida
	var escala := 0.0
	for k in 3:
		var a: int = tri[k]
		var b: int = tri[(k + 1) % 3]
		var dp := (uvs[a] * tam).distance_to(uvs[b] * tam)
		if dp > 1.0:
			escala = maxf(escala, vs[a].distance_to(vs[b]) / dp)
	return escala * raio <= raio_max


## dos triângulos candidatos, os das placas (pedaços ligados) cuja caixa de
## UV contém o centro do círculo: a ventoinha inteira ou em quartos (Inferno,
## Bulldog). Um pedaço que só usa uma parte do desenho (no Renegade, uma
## peça da frente do cockpit) fica parado
static func _placas_ventoinha(vs: PackedVector3Array, uvs: PackedVector2Array, ix: PackedInt32Array,
		cand: Dictionary, tam: Vector2, centro: Vector2, raio: float) -> Dictionary:
	var pai := {}
	for t in cand:
		var a := Vector3i((vs[ix[t]] * 1000.0).round())
		for k in [1, 2]:
			_unir(pai, a, Vector3i((vs[ix[t + k]] * 1000.0).round()))
	var caixa := {}                   # raiz -> Rect2 do UV (px, no ladrilho do centro)
	for t in cand:
		var r := _raiz(pai, Vector3i((vs[ix[t]] * 1000.0).round()))
		var g := (uvs[ix[t]] + uvs[ix[t + 1]] + uvs[ix[t + 2]]) * tam / 3.0
		var desl := ((g - centro) / tam).round() * tam
		for k in 3:
			var p: Vector2 = uvs[ix[t + k]] * tam - desl
			caixa[r] = caixa[r].expand(p) if caixa.has(r) else Rect2(p, Vector2.ZERO)
	var sai := {}
	for t in cand:
		var r := _raiz(pai, Vector3i((vs[ix[t]] * 1000.0).round()))
		if caixa[r].grow(2.0).has_point(centro):
			sai[t] = true
	return sai


## quantas placas (pedaços ligados) tem nos triângulos
static func _placas(vs: PackedVector3Array, ix: PackedInt32Array) -> int:
	var pai := {}
	for t in range(0, ix.size(), 3):
		var a := Vector3i((vs[ix[t]] * 1000.0).round())
		for k in [1, 2]:
			_unir(pai, a, Vector3i((vs[ix[t + k]] * 1000.0).round()))
	var raizes := {}
	for k in pai:
		raizes[_raiz(pai, k)] = true
	return raizes.size()


static func _raiz(pai: Dictionary, k: Vector3i) -> Vector3i:
	while pai.get(k, k) != k:
		k = pai[k]
	return k


static func _unir(pai: Dictionary, a: Vector3i, b: Vector3i) -> void:
	var ra := _raiz(pai, a)
	var rb := _raiz(pai, b)
	if ra != rb:
		pai[ra] = rb


func _rotor(tex: Texture2D, centro: Vector2, raio: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader_rotor
	m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("tam", tex.get_size())
	m.set_shader_parameter("centro", centro)
	m.set_shader_parameter("raio", raio)
	m.set_shader_parameter("cor_k", car.cor_k())
	if OS.get_environment("VENTOINHA_COR") == "1":     # print_tela: o que gira sai vermelho
		m.set_shader_parameter("cor_k", 0.0)
		m.set_shader_parameter("diag", true)
	return m


# ------------------------------------------------------------ polias e correia

## acha as polias desenhadas na malha e monta polias e correia 3D
func _polias(mi: MeshInstance3D) -> void:
	var achadas: Array = []       # {c, n, r, j: [J coluna u, J coluna v], px, tex}
	var mesh: ArrayMesh = mi.mesh
	for s in mesh.get_surface_count():
		var m: Material = mi.get_active_material(s)
		var tex: Texture2D = m.albedo_texture if m is BaseMaterial3D else null
		if tex == null or not POLIA_TEX in tex.resource_path:
			continue
		var arr := mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var ix := PackedInt32Array(range(vs.size()))
		if arr[Mesh.ARRAY_INDEX] != null:
			ix = arr[Mesh.ARRAY_INDEX]
		var tam := tex.get_size()
		for t in range(0, ix.size(), 3):
			for pd in POLIAS:
				var a := _no_triangulo(vs, uvs, ns, [ix[t], ix[t + 1], ix[t + 2]], tam, pd[0], pd[1])
				if a.is_empty():
					continue
				a.tex = tex
				var repetida := false
				for b in achadas:
					if b.c.distance_to(a.c) < 0.01:
						repetida = true
				if not repetida:
					achadas.append(a)
	if achadas.is_empty():
		return
	# pares: as 2 mais perto uma da outra, no mesmo plano (mais ou menos)
	var usadas := {}
	for i in achadas.size():
		if usadas.has(i):
			continue
		var melhor := -1
		var dmin := PAR_MAX
		for j in achadas.size():
			if j == i or usadas.has(j):
				continue
			var a: Dictionary = achadas[i]
			var b: Dictionary = achadas[j]
			if a.n.dot(b.n) < 0.95 or absf(a.n.dot(b.c - a.c)) > DEGRAU_MAX:
				continue
			var d: float = a.c.distance_to(b.c)
			if d < dmin and d > a.r + b.r:
				dmin = d
				melhor = j
		if melhor >= 0:
			usadas[i] = true
			usadas[melhor] = true
			_montar_par(mi, achadas[i], achadas[melhor])


## polia desenhada neste triângulo: o centro do círculo (com a textura
## repetindo) dentro do UV dele. Devolve centro, normal, raio e o mapa
## pixel -> 3D do triângulo
static func _no_triangulo(vs: PackedVector3Array, uvs: PackedVector2Array, ns: PackedVector3Array,
		tri: Array, tam: Vector2, centro: Vector2, raio: float) -> Dictionary:
	var p := [uvs[tri[0]] * tam, uvs[tri[1]] * tam, uvs[tri[2]] * tam]
	var e1: Vector2 = p[1] - p[0]
	var e2: Vector2 = p[2] - p[0]
	var det := e1.cross(e2)
	if absf(det) < 1e-6:
		return {}
	var lo: Vector2 = p[0].min(p[1]).min(p[2])
	var hi: Vector2 = p[0].max(p[1]).max(p[2])
	for kx in range(floori((lo.x - centro.x) / tam.x), ceili((hi.x - centro.x) / tam.x) + 1):
		for ky in range(floori((lo.y - centro.y) / tam.y), ceili((hi.y - centro.y) / tam.y) + 1):
			var cp := centro + Vector2(kx * tam.x, ky * tam.y)
			var q: Vector2 = cp - p[0]
			var l1 := q.cross(e2) / det
			var l2 := e1.cross(q) / det
			if l1 < -0.02 or l2 < -0.02 or l1 + l2 > 1.02:
				continue
			var x0: Vector3 = vs[tri[0]]
			var a1: Vector3 = vs[tri[1]] - x0
			var a2: Vector3 = vs[tri[2]] - x0
			# J = A · M⁻¹ (3D por pixel), M = [e1 e2]
			var ju := (a1 * e2.y - a2 * e1.y) / det
			var jv := (a2 * e1.x - a1 * e2.x) / det
			var n: Vector3 = (ns[tri[0]] + ns[tri[1]] + ns[tri[2]]).normalized() if ns.size() > 0 \
				else a1.cross(a2).normalized()
			return {"c": x0 + a1 * l1 + a2 * l2, "n": n, "r": (ju.length() + jv.length()) * 0.5 * raio,
				"ju": ju, "jv": jv, "px": cp, "raio_px": raio}
	return {}


func _montar_par(mi: MeshInstance3D, a: Dictionary, b: Dictionary) -> void:
	var n: Vector3 = (a.n + b.n).normalized()
	# base do plano: e1 de a pra b, e2 = n x e1 (e1 x e2 = n)
	var e1: Vector3 = (b.c - a.c - n * n.dot(b.c - a.c)).normalized()
	var e2 := n.cross(e1)
	var frente: float = maxf(n.dot(a.c), n.dot(b.c))      # face mais saliente
	var no := Node3D.new()
	no.name = "Polias"
	mi.add_child(no, true)
	var maior: Dictionary = a if a.r >= b.r else b
	if maior.r > _raio_p:
		_raio_p = maior.r
	for p in [a, b]:
		_polia(no, p, n, e1, e2, frente)
	_correia(no, a, b, n, e1, e2, frente)


## polia: cilindro do raio desenhado, da face até a frente comum + largura,
## com a tampa mostrando o desenho do jogo (o mesmo mapa do triângulo)
func _polia(no: Node3D, p: Dictionary, n: Vector3, e1: Vector3, e2: Vector3, frente: float) -> void:
	var r: float = p.r
	var c0: Vector3 = p.c                                  # na face
	var c1: Vector3 = p.c + n * (frente - n.dot(p.c) + POLIA_LARG)   # tampa
	var lados := 32
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in lados:
		var a0 := TAU * k / lados
		var a1 := TAU * (k + 1) / lados
		var d0 := e1 * cos(a0) + e2 * sin(a0)
		var d1 := e1 * cos(a1) + e2 * sin(a1)
		_quad(st, c0 + d0 * r, c0 + d1 * r, c1 + d1 * r, c1 + d0 * r, d0, d1, 0.0, 1.0)
	var aro := MeshInstance3D.new()
	aro.name = "Aro"
	aro.mesh = st.commit()
	aro.material_override = _aco()
	no.add_child(aro, true)
	# tampa: leque com UV pelo mapa inverso do triângulo (pixel = J⁺ · 3D)
	var jtj := Basis(Vector3(p.ju.dot(p.ju), p.ju.dot(p.jv), 0), Vector3(p.ju.dot(p.jv), p.jv.dot(p.jv), 0), Vector3(0, 0, 1))
	var inv := jtj.inverse()
	var tam: Vector2 = p.tex.get_size()
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	var uv_de := func(off: Vector3) -> Vector2:
		var b := Vector3(p.ju.dot(off), p.jv.dot(off), 0)
		var px: Vector3 = inv * b
		return (p.px + Vector2(px.x, px.y)) / tam
	for k in lados:
		var a0 := TAU * k / lados
		var a1 := TAU * (k + 1) / lados
		var d0 := (e1 * cos(a0) + e2 * sin(a0)) * r
		var d1 := (e1 * cos(a1) + e2 * sin(a1)) * r
		var ofs := [Vector3.ZERO, d0, d1]
		if d0.cross(d1).dot(n) > 0.0:       # frente = sentido horário visto de fora
			ofs = [Vector3.ZERO, d1, d0]
		for off in ofs:
			st2.set_normal(n)
			st2.set_uv(uv_de.call(off))
			st2.add_vertex(c1 + off)
	var tampa := MeshInstance3D.new()
	tampa.name = "Tampa"
	tampa.mesh = st2.commit()
	var mat := _rotor(p.tex, p.px, p.raio_px + 0.5)
	tampa.material_override = mat
	no.add_child(tampa, true)
	# sentido: girar a amostra +a gira o desenho -a no pixel; no 3D depende de
	# o mapa pixel -> plano (e1, e2) virar ou não (determinante)
	var det: float = p.ju.dot(e1) * p.jv.dot(e2) - p.ju.dot(e2) * p.jv.dot(e1)
	polias.append({"mat": mat, "raio": r, "sinal": -signf(det)})


## correia: laço pelas tangentes de fora das 2 polias, no meio da largura
func _correia(no: Node3D, a: Dictionary, b: Dictionary, n: Vector3, e1: Vector3, e2: Vector3, frente: float) -> void:
	var meio := frente + POLIA_LARG * 0.5
	var ca: Vector3 = a.c + n * (meio - n.dot(a.c))
	var cb: Vector3 = b.c + n * (meio - n.dot(b.c))
	var ra: float = a.r + CORREIA_ESP * 0.5
	var rb: float = b.r + CORREIA_ESP * 0.5
	var d := ca.distance_to(cb)
	# no plano: a em (0, 0), b em (d, 0); tangentes de fora: normal com
	# cos(phi) = (ra - rb) / d
	var phi := acos(clampf((ra - rb) / d, -1.0, 1.0))
	var pts: Array = []           # [ponto 3D, normal pra fora no plano]
	var passos := 24
	# arco em b: de +phi até -phi passando por 0 (o lado de fora, longe de a)
	for k in passos + 1:
		var t := phi - 2.0 * phi * k / passos
		var dir := e1 * cos(t) + e2 * sin(t)
		pts.append([cb + dir * rb, dir])
	# arco em a: de -phi até -2pi + phi, pelo lado de fora (pi)
	for k in passos + 1:
		var t := -phi - (TAU - 2.0 * phi) * k / passos
		var dir := e1 * cos(t) + e2 * sin(t)
		pts.append([ca + dir * ra, dir])
	pts.append(pts[0])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var u := 0.0
	var h := n * (CORREIA_LARG * 0.5)
	var e := CORREIA_ESP * 0.5
	for k in pts.size() - 1:
		var p0: Vector3 = pts[k][0]
		var p1: Vector3 = pts[k + 1][0]
		var o0: Vector3 = pts[k][1]
		var o1: Vector3 = pts[k + 1][1]
		var u1 := u + p0.distance_to(p1) / NERVURA
		# por fora (nervuras), por dentro, e as 2 bordas
		_quad(st, p0 + o0 * e - h, p1 + o1 * e - h, p1 + o1 * e + h, p0 + o0 * e + h, o0, o1, u, u1)
		_quad(st, p0 - o0 * e + h, p1 - o1 * e + h, p1 - o1 * e - h, p0 - o0 * e - h, -o0, -o1, u, u1)
		_quad(st, p0 + o0 * e + h, p1 + o1 * e + h, p1 - o1 * e + h, p0 - o0 * e + h, n, n, u, u1)
		_quad(st, p0 - o0 * e - h, p1 - o1 * e - h, p1 + o1 * e - h, p0 + o0 * e - h, -n, -n, u, u1)
		u = u1
	var mi := MeshInstance3D.new()
	mi.name = "Correia"
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = _shader_correia
	mat.set_shader_parameter("tex", _textura_correia())
	mi.material_override = mat
	no.add_child(mi, true)
	correias.append({"mat": mat})


## quadrilátero a-b-c-d com a normal dada (o lado de fora é o da normal)
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		na: Vector3, nb: Vector3, u0: float, u1: float) -> void:
	var tris := [[a, na, Vector2(u0, 0)], [b, nb, Vector2(u1, 0)], [c, nb, Vector2(u1, 1)],
		[a, na, Vector2(u0, 0)], [c, nb, Vector2(u1, 1)], [d, na, Vector2(u0, 1)]]
	# frente = sentido horário visto do lado da normal (convenção do Godot)
	var fn := (b - a).cross(c - a)
	if fn.dot(na) > 0.0:
		tris = [tris[0], tris[2], tris[1], tris[3], tris[5], tris[4]]
	for q in tris:
		st.set_normal(q[1])
		st.set_uv(q[2])
		st.add_vertex(q[0])


static var _tex_correia: Texture2D = null


## borracha preta com uma nervura clara por repetição
static func _textura_correia() -> Texture2D:
	if _tex_correia == null:
		var img := Image.create(16, 4, false, Image.FORMAT_RGB8)
		for x in 16:
			var c := 0.07 if x < 11 else 0.16
			for y in 4:
				img.set_pixel(x, y, Color(c, c, c * 1.05))
		_tex_correia = ImageTexture.create_from_image(img)
	return _tex_correia


static var _mat_aco: StandardMaterial3D = null


static func _aco() -> StandardMaterial3D:
	if _mat_aco == null:
		_mat_aco = StandardMaterial3D.new()
		_mat_aco.albedo_color = Color(0.62, 0.63, 0.66)
		_mat_aco.metallic = 0.6
		_mat_aco.roughness = 0.35
	return _mat_aco
