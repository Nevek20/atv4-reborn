extends Node3D
## Farol aceso (melhoria nossa, car.gd FAROL; H no jogo liga e desliga), com a
## mesma cara da lanterna de freio (luzes.gd: lente acesa nos pixels claros +
## brilho suave virado pra câmera; escolha do Matheus, que achou o halo do
## jogo com raios mais feio). O jogo tem um farol pronto e não usa: o
## VehicleHaloMap.xml liga os pontos HEAD_LIGHT* ao halo "ReverseLight" com o
## comportamento Night, mas nenhum carro do jogo tem ponto HEAD_LIGHT
## (docs/engenharia_reversa.md, Halos).
##
## As lâmpadas saem das faces com textura de farol do modelo (LAMPADAS),
## agrupadas pelos vértices e viradas pra frente pela normal do jogo (a ordem
## dos vértices vem virada do pingu2obj): Hurricane (2) e Storm (2 faróis + 4
## milhas no para-choque). No Mosquito a light_64 é a lanterna de trás; os
## outros não têm farol no modelo. Trucks: Shockwave, Jericho, Goliath e
## Chimera (2 cada), Lazarus nos 2 redondos do para-choque; no Shinto e no Punisher a light_64 é luz de teto virada
## pra trás e a cadilac_light do Fireball é lanterna.

const Luzes := preload("res://carro/luzes.gd")
# nome da textura (minúsculo) das lentes. Trucks: a desert_jeep_style_light
# (Shockwave) é um atlas de farol + lanterna e a trophy_truck_light (Goliath)
# de farol + relógio, a preRunnerTruck_light (Lazarus) de farol + lanterna;
# o lado vem da normal (lanterna e relógio olham pra trás)
const LAMPADAS := ["light_64", "headlight", "desert_jeep_style_light", "trophy_truck_light",
	"prerunnertruck_light"]
const FRENTE_MIN := 0.5      # lente conta como farol com a normal média nesse cone pra frente
const JUNTA := 0.002         # m: vértices mais perto que isso ligam as faces (mesma lâmpada)
const HALO_COR := Color(1.0, 0.95, 0.85)
const MIOLO := Color(0.35, 0.33, 0.30)
const MODO := 1              # máscara branca do luzes.gd (a da luz de ré)

static var ligado := true    # H no jogo (main.gd); vale pra todos os carros

var car = null
var lampadas := []           # [{c, n, tam, faces}] no frame do jogo
var faces := 0
var halos := 0
var aceso := 0.0
var _mats := []


## acha as lâmpadas na carroceria e monta a lente acesa e o brilho de cada uma.
## false = carro sem farol
func montar(c) -> bool:
	car = c
	var mi: MeshInstance3D = car.body_mi
	if mi == null or not (mi.mesh is ArrayMesh):
		return false
	var z_min := -INF
	if car.points.has("WHEEL_FRONT_LEFT"):
		z_min = car.points["WHEEL_FRONT_LEFT"].z
	lampadas = achar_lampadas(mi, z_min)
	if lampadas.is_empty():
		return false
	var sh := Shader.new()
	sh.code = Luzes.SHADER % Luzes.GLSL_MASCARA
	var sh_halo := Shader.new()
	sh_halo.code = Luzes.SHADER_HALO
	# lente: as faces das lâmpadas por superfície, com o shader da lanterna
	var por_sup := {}
	for l in lampadas:
		for f in l.faces:
			if not por_sup.has(f[0]):
				por_sup[f[0]] = PackedInt32Array()
			por_sup[f[0]].append_array(PackedInt32Array([f[1], f[2], f[3]]))
	var mesh: ArrayMesh = mi.mesh
	var malha := ArrayMesh.new()
	for s in por_sup:
		var arr: Array = mesh.surface_get_arrays(s).duplicate()
		arr[Mesh.ARRAY_INDEX] = por_sup[s]
		arr[Mesh.ARRAY_TANGENT] = null
		malha.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var m := mi.get_active_material(s) as StandardMaterial3D
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("tex", m.albedo_texture)
		mat.set_shader_parameter("tem_tex", m.albedo_texture != null)
		mat.set_shader_parameter("ganho", Luzes.GANHO)
		mat.set_shader_parameter("afasta", Luzes.AFASTA)
		mat.set_shader_parameter("cor_k", car.cor_k())
		mat.set_shader_parameter("modo", MODO)
		mat.set_shader_parameter("miolo", Vector3(MIOLO.r, MIOLO.g, MIOLO.b))
		malha.surface_set_material(malha.get_surface_count() - 1, mat)
		_mats.append(mat)
		faces += por_sup[s].size() / 3
	var lente := MeshInstance3D.new()
	lente.name = "Lente_farol"
	lente.mesh = malha
	lente.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_child(lente)
	# brilho: um por lâmpada, no centro, do tamanho dela (os limites do freio)
	for l in lampadas:
		var q := QuadMesh.new()
		var mat := ShaderMaterial.new()
		mat.shader = sh_halo
		mat.set_shader_parameter("tam", clampf(1.6 * l.tam, Luzes.HALO_TAM.x, Luzes.HALO_TAM.y))
		mat.set_shader_parameter("frente", l.n)
		mat.set_shader_parameter("cor", Vector3(HALO_COR.r, HALO_COR.g, HALO_COR.b))
		mat.set_shader_parameter("forca", Luzes.HALO_FORCA)
		q.material = mat
		var h := MeshInstance3D.new()
		h.name = "Halo_farol"
		h.mesh = q
		h.position = l.c + l.n * 0.02
		h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		h.extra_cull_margin = 1.0
		mi.add_child(h, true)
		_mats.append(mat)
		halos += 1
	return true


## liga e desliga como a lâmpada do freio (Luzes.ACENDE / APAGA)
func atualizar(delta: float) -> void:
	var alvo := 1.0 if ligado else 0.0
	if OS.has_environment("FAROL"):              # print_tela: 1 aceso, 0 apagado
		alvo = 1.0 if OS.get_environment("FAROL") == "1" else 0.0
	aceso = move_toward(aceso, alvo, delta / (Luzes.ACENDE if alvo > aceso else Luzes.APAGA))
	for m in _mats:
		m.set_shader_parameter("aceso", aceso)


## faces com textura de farol, agrupadas pelas que se tocam (cada grupo é uma
## lâmpada); fica o grupo virado pra frente e na frente da roda dianteira
## (z_min: no Goliath um pedaço da trophy_truck_light acende dentro da cabine).
## Centro e normal pela área, tam = maior lado da caixa. faces = [superfície, i0, i1, i2]
static func achar_lampadas(mi: MeshInstance3D, z_min := -INF) -> Array:
	var tris := []                 # [v0, v1, v2, normal da face, superfície, i0, i1, i2]
	var mesh: ArrayMesh = mi.mesh
	for s in mesh.get_surface_count():
		var m := mi.get_active_material(s) as StandardMaterial3D
		if m == null or m.albedo_texture == null or m.albedo_color.a <= 0.0:
			continue
		var nome := m.albedo_texture.resource_path.get_file().to_lower()
		if not LAMPADAS.any(func(x): return nome.contains(x)):
			continue
		var a := mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var nrs = a[Mesh.ARRAY_NORMAL]
		var ix := PackedInt32Array(range(vs.size()))
		if a[Mesh.ARRAY_INDEX] != null:
			ix = a[Mesh.ARRAY_INDEX]
		for t in range(0, ix.size(), 3):
			var v0 := vs[ix[t]]
			var v1 := vs[ix[t + 1]]
			var v2 := vs[ix[t + 2]]
			# área pela face, lado pela normal do jogo (a ordem dos vértices não diz)
			var n := (v1 - v0).cross(v2 - v0)
			if nrs != null and n.dot(nrs[ix[t]] + nrs[ix[t + 1]] + nrs[ix[t + 2]]) < 0.0:
				n = -n
			tris.append([v0, v1, v2, n, s, ix[t], ix[t + 1], ix[t + 2]])
	# grupos: faces que dividem um vértice (a menos de JUNTA)
	var grupo := range(tris.size())
	var donos := {}
	for i in tris.size():
		for k in 3:
			var chave: Vector3i = Vector3i((tris[i][k] / JUNTA).round())
			if donos.has(chave):
				_une(grupo, i, donos[chave])
			else:
				donos[chave] = i
	var soma := {}
	for i in tris.size():
		var g: int = _raiz(grupo, i)
		var t: Array = tris[i]
		var area: float = t[3].length() * 0.5
		if not soma.has(g):
			soma[g] = {"c": Vector3.ZERO, "n": Vector3.ZERO, "a": 0.0, "lo": Vector3.INF,
				"hi": -Vector3.INF, "faces": []}
		var s: Dictionary = soma[g]
		s.c += (t[0] + t[1] + t[2]) / 3.0 * area
		s.n += t[3]
		s.a += area
		s.faces.append([t[4], t[5], t[6], t[7]])
		for k in 3:
			s.lo = s.lo.min(t[k])
			s.hi = s.hi.max(t[k])
	var out := []
	for g in soma:
		var s: Dictionary = soma[g]
		if s.a <= 0.0 or s.n.length() <= 0.0:
			continue
		var n: Vector3 = s.n.normalized()
		if n.z < FRENTE_MIN or s.c.z / s.a < z_min:
			continue
		var ext: Vector3 = s.hi - s.lo
		out.append({"c": s.c / s.a, "n": n, "tam": maxf(ext.x, maxf(ext.y, ext.z)), "faces": s.faces})
	out.sort_custom(func(x, y): return x.c.x < y.c.x)
	return out


static func _raiz(g: Array, i: int) -> int:
	while g[i] != i:
		g[i] = g[g[i]]
		i = g[i]
	return i


static func _une(g: Array, a: int, b: int) -> void:
	g[_raiz(g, a)] = _raiz(g, b)
