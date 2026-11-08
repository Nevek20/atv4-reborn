extends Node3D
## Peças da suspensão do jeito que o jogo põe. Cada peça do component map vira
## uma classe cCompPlace_<Position> (fábricas 0x208d40..0x2097e8) que copia uma
## matriz de pose recalculada a cada quadro (0x21dff8..0x221d58). Tudo no frame
## do modelo e a partir do curso x de cada roda. Conferido contra as matrizes
## das peças na RAM do Renegade e do Sphinx (tests/teste_pecas.gd).
##
## balança (0x21eec0): eixo u = linha 2 da matriz do ponto A_FRAME_* (vem do
##   arquivo de pontos, muda por carro), d = A_FRAME_END - A_FRAME,
##   r = |d.x*u.z + d.z*u.x|, ângulo = atan(x / r), gira em volta do A_FRAME.
## roda (0x220110): centro = WHEEL girado com a balança; na frente o y vira
##   WHEEL.y + x. A roda não herda a rotação da balança (só giro e direção).
## freio (0x221748 / 0x221928): o da frente gira só com a direção em volta do
##   WHEEL e vai junto com o centro da roda; o de trás só translada.
## amortecedor dianteiro (0x21f590): peça rígida, gira em z em volta do
##   SHOCKS_TOP até apontar pro SHOCKS_BOTTOM girado com a balança; ângulo
##   negativo na esquerda.
## traseiro (0x21fb68): câmara e haste com a mesma rotação em x; a haste é
##   levada até o SHOCK_PISTON girado (com o x original).
## rally (Storm, 0x220528 / 0x220cf0): roda = WHEEL + x, sem balança no meio.
## estepe (0x221a88): fixo, matriz e posição do ponto SpareWheel01Centre.
## trucks (TruckCompMap_A2/B1/B2), conferido com a RAM do Goliath (erro 0):
##   LeftFrame/RightFrame (0x21e0b8 / 0x21e1f0, translação 0x21e158 /
##   0x21e290): Rz(tan(x / W.x)) em volta do A_FRAME_LEFT/RIGHT, com W = o
##   ponto de id 1/2 da tabela do carro, que no truck é o
##   WHEEL_FRONT_*_VISUAL (vem antes no arquivo: o jogo acha pelo começo do
##   nome; ver _ponto). tan mesmo (0x6894e0), não atan.
##   FrontLeft/RightBrake (0x221308 / 0x221468): gira com a direção em volta
##   do eixo da suspensão (W+0x20, (0, 1, 0)) no mesmo W e desce x por ele.
##   RearAxle (0x21e998 / 0x21eba8; Axle e Rear_Arm juntos): Rx(-a) em volta
##   de a0 = (0, ARM_PIVOT.y, ARM_PIVOT.z), a = ângulo entre AXLE_ANCHOR - a0
##   e o meio dos centros das rodas de trás (x = 0) - a0 (0x21e838; negativo
##   quando o AXLE_ANCHOR está abaixo do meio).
##   RearFreeAxle (0x21ee00): sem giro, sobe a média do curso de trás.
##   As rodas desses mapas são as do rally (WHEEL + x).
##   Melhoria nossa (car.gd "eixo_rigido"): com uma roda de trás subindo e a
##   outra descendo o eixo do jogo fica reto e as rodas soltam das pontas;
##   aqui ele inclina pra ligar os 2 cubos e as rodas de trás inclinam junto.
##   Só o desenho: o centro das rodas continua o da física.
## O curso usado em tudo isso já tem a tremida das rodas no chão (car.gd,
## 0x202760), então balança, cubo, freio e amortecedor tremem juntos.
##
## Convenção: o jogo usa vetor-linha (v' = v*R + t, linhas = eixos). No Godot
## as colunas do Basis são as linhas do jogo: EixoAngulo(a, u) = Basis(u, a),
## Rx/Ry/Rz = Basis(RIGHT/UP/BACK, a), t = p - B*p pra girar em volta de p.
## "Esquerda" do jogo é x < 0 no modelo. Este nó fica dentro do espelho do
## carro (car.gd, escala (-1, 1, 1)): tudo aqui é frame do JOGO e o espelho
## põe no Godot, onde a esquerda do jogo vira +X. O ângulo de esterço que
## chega em update() já é o do jogo (car.gd a_jogo).

var car                      # car.gd
var off := Vector3.ZERO      # model_offset do carro
var corners := []            # um por roda
var rally := false
var spares := []             # transform de cada estepe (frame do modelo)
var truck := {}              # peças dos trucks: frames, freios e eixo (ver o topo)


func build(c, pts: Dictionary, rot: Dictionary, dir: String, pecas: Dictionary,
		is_rally: bool, spare: Array, spare_mesh: Mesh) -> void:
	car = c
	off = c.model_offset
	rally = is_rally
	for side in ["LEFT", "RIGHT"]:
		for axle in ["FRONT", "REAR"]:
			var left: bool = side == "LEFT"
			var front: bool = axle == "FRONT"
			var k := {"left": left, "front": front}
			# roda da física do mesmo canto (w.left = esquerda do jogo)
			for w in c.wheels:
				if w.front == front and w.left == left:
					k.wheel = w
			var piv_name := "A_FRAME_%s_%s" % [axle, side]
			var end_name := "A_FRAME_END_%s_%s" % [axle, side]
			var wheel_name := "WHEEL_%s_%s" % [axle, side]
			if not (k.has("wheel") and pts.has(piv_name) and pts.has(end_name) and rot.has(piv_name)):
				continue
			k.pivot = pts[piv_name]
			k.end = pts[end_name]
			k.w0 = pts.get(wheel_name, c.jogo(Vector3(k.wheel.px, k.wheel.y0, k.wheel.pz)))
			k.u = (rot[piv_name] as Basis).z          # linha 2 do jogo
			var d: Vector3 = pts[end_name] - k.pivot
			k.r = absf(d.x * k.u.z + d.z * k.u.x)
			var pos := ("Front" if front else "Rear") + ("Left" if left else "Right")
			k.frame = _part(dir, pecas.get(pos + "Frame", ""))
			k.brake = _part(dir, pecas.get(pos + "FrameBrake", ""))
			if front:
				var t := "SHOCKS_TOP_FRONT_%s" % side
				var b := "SHOCKS_BOTTOM_FRONT_%s" % side
				k.shock = _part(dir, pecas.get(pos + "Shocks", ""))
				if k.shock and pts.has(t) and pts.has(b):
					k.top = pts[t]
					k.bottom = pts[b]
			else:
				var s := "L" if left else "R"
				var ch := "SHOCK_CHAMBER_R%s" % s
				var pi := "SHOCK_PISTON_R%s" % s
				k.chamber = _part(dir, pecas.get(pos + "ShockChamber", ""))
				k.piston = _part(dir, pecas.get(pos + "ShockPiston", ""))
				if (k.chamber or k.piston) and pts.has(ch) and pts.has(pi):
					k.top = pts[ch]
					k.bottom = pts[pi]
			corners.append(k)
	_build_truck(pts, dir, pecas)
	# estepe (BuggyCompMap_A1/B1/C1: RearWheel em SpareWheel01)
	for s in spare:
		var pn: String = s + "Centre"
		if spare_mesh and pts.has(pn):
			var mi := _mesh_instance(spare_mesh)
			var xf := Transform3D(rot.get(pn, Basis()), pts[pn])
			_place(mi, xf)
			spares.append(xf)


## peças do eixo rígido dos trucks (só monta as que o pecas.json tem)
func _build_truck(pts: Dictionary, dir: String, pecas: Dictionary) -> void:
	var rodas := {}
	for w in car.wheels:
		rodas[("F" if w.front else "R") + ("L" if w.left else "R")] = w
	for lado: String in ["LEFT", "RIGHT"]:
		var l := lado.substr(0, 1)
		var nome := lado.capitalize()                  # Left / Right
		var w0 = _ponto(pts, "WHEEL_FRONT_" + lado)    # id 1/2 da tabela (o _VISUAL no truck)
		var piv := "A_FRAME_" + lado
		var fr := _part(dir, pecas.get(nome + "Frame", ""))
		if fr and w0 != null and pts.has(piv) and rodas.has("F" + l):
			truck[nome + "Frame"] = {"mi": fr, "pivot": pts[piv], "div": w0.x, "roda": rodas["F" + l]}
		var br := _part(dir, pecas.get("Front" + nome + "Brake", ""))
		if br and w0 != null and rodas.has("F" + l):
			truck["Front" + nome + "Brake"] = {"mi": br, "w": w0, "roda": rodas["F" + l]}
	var traseiras := [rodas.get("RL"), rodas.get("RR")]
	if traseiras.has(null):
		return
	var axle := []
	for k in pecas:
		if k == "RearAxle" or k.begins_with("RearAxle/"):
			var mi := _part(dir, pecas[k])
			if mi:
				axle.append(mi)
	if not axle.is_empty() and pts.has("ARM_PIVOT") and pts.has("AXLE_ANCHOR") \
			and pts.has("WHEEL_REAR_LEFT") and pts.has("WHEEL_REAR_RIGHT"):
		var ap: Vector3 = pts["ARM_PIVOT"]
		truck.RearAxle = {"mis": axle, "a0": Vector3(0.0, ap.y, ap.z), "ancora": pts["AXLE_ANCHOR"],
			"wl": pts["WHEEL_REAR_LEFT"], "wr": pts["WHEEL_REAR_RIGHT"], "rodas": traseiras}
	var livre := _part(dir, pecas.get("RearFreeAxle", ""))
	if livre and pts.has("WHEEL_REAR_LEFT") and pts.has("WHEEL_REAR_RIGHT"):
		truck.RearFreeAxle = {"mi": livre, "rodas": traseiras,
			"wl": pts["WHEEL_REAR_LEFT"], "wr": pts["WHEEL_REAR_RIGHT"]}


## ponto pelo começo do nome, na ordem do arquivo (o jogo enche a tabela de
## ids assim: no truck o WHEEL_FRONT_LEFT_VISUAL vem antes do WHEEL_FRONT_LEFT)
static func _ponto(pts: Dictionary, nome: String):
	for k in pts:
		if String(k).begins_with(nome):
			return pts[k]
	return null


## matrizes das peças dos trucks pros cursos x (FL, FR, RL, RR) e o esterço do
## jogo. Separado do update pro teste comparar com a RAM. inclina = melhoria
## nossa (car.gd "eixo_rigido"): o eixo de trás também inclina pra ligar as
## 2 rodas (o jogo só sobe ele pela média e a roda soltava da ponta)
func pose_truck(x: Dictionary, steer: float, inclina := false) -> Dictionary:
	var out := {}
	for nome in ["LeftFrame", "RightFrame"]:
		if truck.has(nome):
			var t: Dictionary = truck[nome]
			var xi: float = x["FL" if nome == "LeftFrame" else "FR"]
			out[nome] = _about(t.pivot, Basis(Vector3.BACK, tan(xi / t.div)))
	for nome in ["FrontLeftBrake", "FrontRightBrake"]:
		if truck.has(nome):
			var t: Dictionary = truck[nome]
			var xi: float = x["FL" if nome == "FrontLeftBrake" else "FR"]
			var b := Basis(Vector3.UP, steer)
			out[nome] = Transform3D(b, t.w - b * t.w + Vector3(0.0, xi, 0.0))
	if truck.has("RearAxle"):
		var t: Dictionary = truck.RearAxle
		var m: Vector3 = (t.wl + t.wr) * 0.5 + Vector3(0.0, (x.RL + x.RR) * 0.5, 0.0)
		m.x = 0.0
		var a0: Vector3 = t.a0
		var a := acos(clampf((t.ancora - a0).normalized().dot((m - a0).normalized()), -1.0, 1.0))
		if t.ancora.y < m.y:
			a = -a
		out.RearAxle = _about(a0, Basis(Vector3.RIGHT, -a))
		if inclina:
			# gira em volta da linha braço -> meio do eixo (como um eixo rígido
			# de verdade, preso no ARM_PIVOT): o eixo (x do modelo) girado de
			# phi em volta de u = (0, uy, uz) fica com inclinação tan(phi)·uz,
			# então phi = atan(s / uz), s = inclinação entre os 2 cubos
			var u := (m - a0).normalized()
			if absf(u.z) > 0.1:
				var phi := atan(_inclinacao(t, x) / u.z)
				out.RearAxle = _about(a0, Basis(u, phi)) * out.RearAxle
	if truck.has("RearFreeAxle"):
		var t: Dictionary = truck.RearFreeAxle
		out.RearFreeAxle = Transform3D(Basis(), Vector3(0.0, (x.RL + x.RR) * 0.5, 0.0))
		if inclina:
			var c: Vector3 = (t.wl + t.wr) * 0.5 + Vector3(0.0, (x.RL + x.RR) * 0.5, 0.0)
			c.x = 0.0
			out.RearFreeAxle = _about(c, Basis(Vector3.BACK, atan(_inclinacao(t, x)))) * out.RearFreeAxle
	return out


## inclinação (dy/dx) da linha entre os centros das 2 rodas de trás
static func _inclinacao(t: Dictionary, x: Dictionary) -> float:
	var hl: Vector3 = t.wl + Vector3(0.0, x.RL, 0.0)
	var hr: Vector3 = t.wr + Vector3(0.0, x.RR, 0.0)
	if absf(hl.x - hr.x) < 0.01:
		return 0.0
	return (hl.y - hr.y) / (hl.x - hr.x)


func _part(dir: String, file: String) -> MeshInstance3D:
	if file == "":
		return null
	var path := dir.path_join(file)
	if not ResourceLoader.exists(path):
		return null
	var mesh := load(path) as Mesh
	return _mesh_instance(mesh) if mesh else null


func _mesh_instance(mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i)
		var m2: StandardMaterial3D = m.duplicate() if m is StandardMaterial3D else StandardMaterial3D.new()
		car.material_do_jogo(m2)
		mi.set_surface_override_material(i, m2)
	add_child(mi)
	mi.position = off
	return mi


## transform (no frame do modelo) que gira em volta de p
static func _about(p: Vector3, b: Basis) -> Transform3D:
	return Transform3D(b, p - b * p)


func _place(mi: MeshInstance3D, xf: Transform3D) -> void:
	if mi:
		mi.transform = Transform3D(Basis(), off) * xf


## matrizes de todas as peças pro curso x de cada canto (frame do modelo do
## jogo). steer = ângulo do jogo (Ry no frame do jogo). Separado do update pra
## o teste comparar com a RAM.
func pose(k: Dictionary, x: float, steer: float) -> Dictionary:
	var out := {}
	var b := Basis(k.u, atan(x / k.r)) if k.r > 1e-6 else Basis()
	var arm := _about(k.pivot, b)
	out.frame = arm
	var w0: Vector3 = k.w0
	var h: Vector3 = arm * w0
	if k.front:
		h.y = w0.y + x
	if rally:
		h = w0 + Vector3(0.0, x, 0.0)
	out.hub = h
	var bb := Basis(Vector3.UP, steer) if k.front else Basis()
	out.brake = Transform3D(bb, h - bb * w0)
	if k.has("top"):
		var top: Vector3 = k.top
		var bot: Vector3 = k.bottom
		if k.front:
			var b2: Vector3 = arm * bot
			var a := acos(clampf((bot - top).normalized().dot((b2 - top).normalized()), -1.0, 1.0))
			if k.left:
				a = -a
			out.shock = _about(top, Basis(Vector3.BACK, a))
		else:
			var q: Vector3 = arm * bot
			var p2 := Vector3(bot.x, q.y, q.z)
			# atan (não atan2), igual ao jogo
			var a := atan((top.y - bot.y) / (top.z - bot.z)) - atan((top.y - p2.y) / (top.z - p2.z))
			var r := Basis(Vector3.RIGHT, a)
			out.chamber = _about(top, r)
			out.piston = Transform3D(r, p2 - r * bot)
	return out


## steer_angle: ângulo das rodas no frame do jogo (car.gd a_jogo)
func update(steer_angle: float) -> void:
	for k in corners:
		var w: Dictionary = k.wheel
		# curso visual do jogo (0x222078) = curso + tremida (car.gd)
		var x: float = clampf(w.x, w.min, w.max) + w.get("jit", 0.0)
		var p := pose(k, x, steer_angle)
		_place(k.frame, p.frame)
		w.pivot.position = off + p.hub
		_place(k.brake, p.brake)
		if p.has("shock"):
			_place(k.shock, p.shock)
		if p.has("chamber"):
			_place(k.get("chamber"), p.chamber)
			_place(k.get("piston"), p.piston)
	if truck.is_empty():
		return
	var x := {}
	for w in car.wheels:
		x[("F" if w.front else "R") + ("L" if w.left else "R")] = clampf(w.x, w.min, w.max) + w.get("jit", 0.0)
	var inclina: bool = car._tem("eixo_rigido")
	var p := pose_truck(x, steer_angle, inclina)
	for nome in p:
		var t: Dictionary = truck[nome]
		for mi in t.get("mis", [t.get("mi")]):
			_place(mi, p[nome])
	# as rodas de trás inclinam junto com o eixo (só giram no lugar: o centro
	# continua o da física)
	for nome in ["RearAxle", "RearFreeAxle"]:
		if truck.has(nome):
			var t: Dictionary = truck[nome]
			var cam := atan(_inclinacao(t, x)) if inclina else 0.0
			for w in t.rodas:
				w.pivot.rotation.z = cam
