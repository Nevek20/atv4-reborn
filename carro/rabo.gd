extends Node3D
## Rabo de cavalo da piloto balançando: a corrente de partículas do jogo.
## O rabo é um modelo à parte com os 7 ossos dele (PONY_A..PONY_END), como no
## jogo (0x1a9588), no espaço do corpo do piloto (o mesmo do esqueleto dele).
## Cada osso é uma partícula (Verlet, massa 1: 0x235640/0x1b1648) e, a cada
## quadro do jogo (50 Hz no PAL), 0x1886f8 + restrições 0x1abdf0:
##   1. força pra baixo max(8, 20 - v) e, correndo, "vento" contra o eixo Z
##      do ROOT: max(v, 20) nas 4 primeiras e max(v, 10) nas outras (v = |v|
##      do carro em m/s, corpo+0xe0)
##   2. Verlet: d = (x - x_anterior) + F·dt²; o osso anda 0.8·d
##   3. restrições numa passada só, na ordem em que o jogo cria (0x1a9880):
##      esfera na cabeça (head + 1.0·Z, raio 0.15: fica longe de tudo, é o
##      que o exe faz), cilindro entre os ombros (cada ombro + 0.035·Z, raio
##      0.17), esfera nas costas (upper_back + 0.15·Y + 0.01·Z, raio 0.15),
##      pino no pescoço (neck + 0.09·Y - 0.08·Z) e as distâncias da pose
##      (só o filho anda; o osso filho gira o mesmo que a direção do pedaço)
## Colisor empurra x·(1 - dist/raio) pra fora (não até a borda: 0x1ae618).
## Os pontos dos colisores saíram do re/emu_ee.py rodando o 0x1a9db0.
## NOSSO: o passo fixo de 0.02 com interpolação pra telas acima de 50 FPS, a
## pose começar com a raiz no pino e assentar 1 s parado ao montar (no jogo a
## introdução já assentou).

const PASSO := 0.02                    # um quadro do jogo (PAL)
const PUXA := 0.8                      # 0x1886f8: osso += 0.8·(partícula - osso)
const G_PARADO := 20.0                 # gravidade = max(G_MIN, G_PARADO - v)
const G_MIN := 8.0
const VENTO_RAIZ := 20.0               # vento = max(v, isto); 4 primeiras partículas
const VENTO_PONTA := 10.0
const N_RAIZ := 4
const PINO_Y := 0.09                   # neck + 0.09·Y - 0.08·Z (0x1aa03c / 0x1aa21c)
const PINO_Z := -0.08
const CABECA_Z := 1.0                  # head + 1.0·Z (0x1aa698)
const R_CABECA := 0.15
const OMBRO_Z := 0.035                 # 0x54d824
const R_OMBROS := 0.17
const COSTAS_Y := 0.15                 # 0x54d818 / 0x54d81c
const COSTAS_Z := 0.01
const R_COSTAS := 0.15
const ASSENTA := 50                    # passos parado ao montar (NOSSO)

var skel: Skeleton3D
var malha: MeshInstance3D
var n := 0
var x := PackedVector3Array()          # posição de cada osso (partícula)
var x_ant := PackedVector3Array()      # no passo anterior (Verlet)
var rot: Array[Basis] = []
var resto := PackedFloat32Array()      # comprimento de cada pedaço (pose)
var _vis_x := PackedVector3Array()     # estado anterior, pra interpolar na tela
var _vis_r: Array[Basis] = []
var _acum := 0.0
var _piloto                            # carro/piloto.gd (os ossos do corpo)
var _ob := {}                          # nome -> índice do osso no corpo


## d = o "rabo" do piloto_f.json; mat = o material do corpo (mesma textura)
func montar(d: Dictionary, mat: Material, piloto) -> void:
	_piloto = piloto
	skel = Skeleton3D.new()
	add_child(skel)
	var skin := Skin.new()
	var ossos: Array = d.ossos
	n = ossos.size()
	for b in n:
		skel.add_bone(ossos[b].nome)
		var m: Array = ossos[b].inv
		skin.add_bind(b, Transform3D(Basis(Vector3(m[0], m[1], m[2]), Vector3(m[4], m[5], m[6]),
			Vector3(m[8], m[9], m[10])), Vector3(m[12], m[13], m[14])))
	for b in n:
		var p: Array = d.pose[b]
		x.append(Vector3(p[0], p[1], p[2]))
		rot.append(Basis(Quaternion(p[3], p[4], p[5], p[6]).normalized()))
	x_ant = x.duplicate()
	for b in n - 1:
		resto.append(x[b].distance_to(x[b + 1]))
	# malha (mesmo sentido de triângulo e mesmas pernas do corpo, piloto.gd)
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var p: Array = d.pos
	var q: Array = d.normal
	var t: Array = d.uv
	for i in p.size() / 3:
		pos.append(Vector3(p[3 * i], p[3 * i + 1], p[3 * i + 2]))
		nrm.append(Vector3(q[3 * i], q[3 * i + 1], q[3 * i + 2]).normalized())
		uv.append(Vector2(t[2 * i], t[2 * i + 1]))
	var pes := PackedFloat32Array(d.pesos)
	for i in pes.size() / 4:
		var s := pes[4 * i] + pes[4 * i + 1] + pes[4 * i + 2] + pes[4 * i + 3]
		if s > 0.0:
			for k in 4:
				pes[4 * i + k] /= s
	var tri: Array = d.tris
	var idx := PackedInt32Array()
	for i in tri.size() / 3:
		idx.append_array([tri[3 * i], tri[3 * i + 2], tri[3 * i + 1]])
	var rp := PackedFloat32Array()
	var rn := PackedFloat32Array()
	for i in pos.size():
		rp.append_array([pos[i].x, pos[i].y, pos[i].z])
		rn.append_array([nrm[i].x, nrm[i].y, nrm[i].z])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_BONES] = PackedInt32Array(d.ossos_v)
	arr[Mesh.ARRAY_WEIGHTS] = pes
	arr[Mesh.ARRAY_INDEX] = idx
	arr[Mesh.ARRAY_CUSTOM0] = rp           # pose de repouso: a sujeira projeta por ela
	arr[Mesh.ARRAY_CUSTOM1] = rn
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {},
		(Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		| (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT))
	am.surface_set_material(0, mat)
	malha = MeshInstance3D.new()
	malha.mesh = am
	malha.skin = skin
	skel.add_child(malha)
	malha.skeleton = NodePath("..")
	for nome in ["ROOT", "upper_back", "neck", "head", "right_shoulder", "left_shoulder"]:
		_ob[nome] = piloto.skel.find_bone(nome)
	# a pose do jogo começa com a raiz ~16 cm atrás do pino (piloto sentado):
	# encaixar no 1º passo dava um tranco que jogava o rabo por cima dos
	# ombros. NOSSO: a pose já começa com a raiz no pino, parada
	var pe: Transform3D = piloto.skel.get_bone_global_pose(_ob.neck)
	var leva: Vector3 = pe.origin + pe.basis.y * PINO_Y + pe.basis.z * PINO_Z - x[0]
	for b in n:
		x[b] += leva
	x_ant = x.duplicate()
	for i in ASSENTA:
		passo(0.0, false)
	_vis_x = x.duplicate()
	_vis_r = rot.duplicate()
	_aplica(1.0)


## avança o tempo da tela: passos fixos de 0.02 s (v em m/s; correndo = vento)
func avancar(dt: float, v: float, correndo := true) -> void:
	if n == 0:
		return
	_acum = minf(_acum + dt, PASSO * 5.0)
	while _acum >= PASSO:
		_acum -= PASSO
		_vis_x = x.duplicate()
		_vis_r = rot.duplicate()
		passo(v, correndo)
	_aplica(_acum / PASSO)


## um quadro do jogo
func passo(v: float, correndo: bool) -> void:
	var g := {}
	for k in _ob:
		g[k] = _piloto.skel.get_bone_global_pose(_ob[k])
	var inicio := x.duplicate()               # partícula +0x2d0: onde cada osso estava
	var forca := Vector3(0.0, -maxf(G_MIN, G_PARADO - v), 0.0)
	var vento: Vector3 = g.ROOT.basis.z
	for i in n:
		var f := forca
		if correndo:
			f -= vento * maxf(v, VENTO_RAIZ if i < N_RAIZ else VENTO_PONTA)
		var d := (x[i] - x_ant[i]) + f * (PASSO * PASSO)
		x_ant[i] = x[i]
		x[i] += d * PUXA
	# restrições, na ordem do jogo
	var h: Transform3D = g.head
	_esfera(h.origin + h.basis.z * CABECA_Z, R_CABECA)
	var od: Transform3D = g.right_shoulder
	var oe: Transform3D = g.left_shoulder
	_cilindro(od.origin + od.basis.z * OMBRO_Z, oe.origin + oe.basis.z * OMBRO_Z, R_OMBROS)
	var c: Transform3D = g.upper_back
	_esfera(c.origin + c.basis.y * COSTAS_Y + c.basis.z * COSTAS_Z, R_COSTAS)
	var pe: Transform3D = g.neck
	x[0] = pe.origin + pe.basis.y * PINO_Y + pe.basis.z * PINO_Z
	for i in n - 1:
		var dir := x[i] - x[i + 1]
		var l := dir.length()
		if l < 1e-6:
			continue
		x[i + 1] += dir * (1.0 - resto[i] / l)
		var antes := inicio[i] - inicio[i + 1]
		if antes.length_squared() > 1e-12:
			var gira := Quaternion(antes.normalized(), dir / l)
			rot[i + 1] = (Basis(gira) * rot[i + 1]).orthonormalized()


## 0x1ae618: dentro da esfera, empurra d·(1 - |d|/r)
func _esfera(c: Vector3, r: float) -> void:
	for i in n:
		var d := x[i] - c
		var l := d.length()
		if l < r:
			x[i] += d * (1.0 - l / r)


## 0x1ae2e0: a reta (sem pontas) entre a e b, mesma conta da esfera
func _cilindro(a: Vector3, b: Vector3, r: float) -> void:
	var u := b - a
	var uu := u.length_squared()
	if uu < 1e-12:
		return
	for i in n:
		var d := x[i] - (a + u * (u.dot(x[i] - a) / uu))
		var l := d.length()
		if l < r:
			x[i] += d * (1.0 - l / r)


func _aplica(f: float) -> void:
	for b in n:
		var p := _vis_x[b].lerp(x[b], f)
		var q := Quaternion(_vis_r[b]).slerp(Quaternion(rot[b]), f)
		skel.set_bone_pose_position(b, p)
		skel.set_bone_pose_rotation(b, q)
