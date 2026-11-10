extends RefCounted
## Câmera de corrida do jogo (CameraSet "FollowOrbitNear/Far"), portada do exe.
##
## No jogo a câmera é uma lista de componentes que rodam em passo fixo de 1/60 s
## (construtor 0x38dc30, update base 0x387320). A ordem aqui é a mesma:
##   altura por velocidade (0x383418) -> offset no frame do carro (0x383588)
##   -> amortecimento em Y (0x383cf8/0x384168) -> subida em descida (0x385238)
##   -> órbita (0x386950) -> descolar/recolar (0x384ef8) -> altura mínima do
##   chão (0x384c80) -> mira (0x37f2f8) -> tremida (0x380418, camera_jitter.gd)
##   -> zoom por velocidade (0x3806a0) -> suavização final (0x387320).
## Parâmetros: data/cameras.xml (14880), defaults de 0x38d498.

const CameraJitter := preload("res://camera/camera_jitter.gd")
const STEP := 1.0 / 60.0
const MPH := 2.2374146          # m/s -> mph, mesma constante do exe

# defaults do jogo (0x38d498) pra quando o XML não traz o campo
const DEFAULTS := {
	"FOV_MIN_ZOOM": 0.65, "FOV_MAX_ZOOM": 0.65, "FOV_MIN_SPEED": 40.0, "FOV_MAX_SPEED": 50.0,
	"LOOK_OFFSET_MIN_SPEED": 0.0, "LOOK_OFFSET_MAX_SPEED": 150.0,
	"POS_DAMPING_Y_GOING_UP": 15.0, "POS_DAMPING_Y_GOING_DOWN": 5.0,
	"UP_INCLINE_MULTIPLIER": 2.0, "DOWN_INCLINE_MULTIPLIER": 2.0, "DECAY_FRACTION": 0.01,
	"MAX_WHEELS_OFF_GROUND_TIME": 0.1, "MAX_EXTRA_HEIGHT_RATE": 1.0,
	"MAX_Y_OFFSET": 4.0, "MAX_Y_SPEED_MIN": 1.0, "MAX_Y_SPEED_MAX": 85.0,
	"MAX_POS_CHANGE": 1.0, "BEGIN_REATTACH_TIME": 2.0, "REATTACHMENT_TIME": 2.0,
	"SlerpRate": 3.5, "SlerpMaxAngle": 3.5, "NoCourseFollowSpeed": 10.0,
	"MaxCourseFollowSpeed": 65.0, "MaxCourseFollowAmount": 0.4, "UseTotalSpeed": 1.0,
	"MinDistance": 5.0, "MinDistanceSpeed": 20.0, "MaxDistance": 6.0, "MaxDistanceSpeed": 80.0,
	"FOV": 0.5,
}

# altura mínima acima do chão (0x384c80, fixo no construtor: 1.45 m, taxa 30)
const GROUND_CLEAR := 1.45
const GROUND_RATE := 30.0
# zoom -> campo de visão. No exe o frustum tem meia-largura 0.5/zoom e
# meia-altura 0.375/zoom (tela 4:3, 0x390a80 / 0x64f0a0): zoom MENOR = mais
# aberto. Aqui fixa a altura (KEEP_HEIGHT), então em 16:9 sobra imagem dos
# lados, igual hack de widescreen. Bateu com a gravação do PCSX2.
const VIEW_HALF_H := 0.375

var p := {}
var pos_off := Vector3(0, 2.5, -5)
var look_off := Vector3(0, 2.2, 0)
var mount := false              # MountOnHood/MountOnFront: presa no carro
var jit                         # tremida (camera_jitter.gd), parâmetros genéricos do tipo

# estado (o que o jogo guarda nos componentes)
var pos := Vector3.ZERO         # posição final (cam+0x10)
var dir := Vector3.FORWARD      # direção de mira (cam+0x40)
var zoom := 0.5                 # cam+0x50
var y_rate := 0.0
var y_s := 0.0
var extra := 0.0
var ground_s := 0.0
var base_rate := 10.0
var ra_state := 0
var ra_prev := Vector3.ZERO
var ra_tether := 0.0
var ra_timer := 0.0
var ra_held := Vector3.ZERO

# pra interpolar entre passos de 1/60 quando a tela roda em outra taxa
var acc := 0.0
# A interpolação é feita no frame do carro (offset câmera - carro), assim a
# câmera nunca "escorrega" em relação ao carro desenhado (era o fantasma).
var _po := Vector3.ZERO         # offset do passo anterior
var _co := Vector3.ZERO         # offset do passo atual
var _pd := Vector3.FORWARD
var _pz := 0.5


static func load_set(path: String, set_name: String, cam_name: String):
	var c = new()
	c._parse(path, set_name, cam_name)
	c.jit = CameraJitter.carregar(path, cam_name)
	return c


func _parse(path: String, set_name: String, cam_name: String) -> void:
	p = DEFAULTS.duplicate()
	var x := XMLParser.new()
	if x.open(path) != OK:
		push_warning("câmera: não abriu " + path)
		return
	var in_set := false
	var in_cam := false
	while x.read() == OK:
		var t := x.get_node_type()
		if t == XMLParser.NODE_ELEMENT:
			var n := x.get_node_name()
			if n == "CameraSet":
				in_set = x.get_named_attribute_value_safe("Name") == set_name
			elif in_set and n == cam_name:
				in_cam = true
				mount = n.begins_with("MountOn")
				for i in x.get_attribute_count():
					var k := x.get_attribute_name(i)
					var v := x.get_attribute_value(i)
					p[k] = 1.0 if v == "true" else (0.0 if v == "false" else v.to_float())
				if x.is_empty():
					in_cam = false
			# o XML é frame do carro do jogo (mão esquerda): passa pro Godot aqui,
			# um lugar só. Posição: x negado. Ângulos (pseudovetor): y e z negados
			elif in_cam and (n == "POS_OFFSET" or n == "PosOffset"):
				pos_off = _vec(x) * Vector3(-1.0, 1.0, 1.0)
			elif in_cam and n == "LOOK_OFFSET":
				look_off = _vec(x) * Vector3(-1.0, 1.0, 1.0)
			elif in_cam and n == "Orientation":
				p["orient"] = _vec(x) * Vector3(1.0, -1.0, -1.0)
		elif t == XMLParser.NODE_ELEMENT_END:
			var n := x.get_node_name()
			if in_set and n == cam_name:
				in_cam = false
			elif n == "CameraSet":
				in_set = false


func _vec(x: XMLParser) -> Vector3:
	return Vector3(x.get_named_attribute_value_safe("X").to_float(),
		x.get_named_attribute_value_safe("Y").to_float(),
		x.get_named_attribute_value_safe("Z").to_float())


func fov_deg(z: float) -> float:
	# vertical (Camera3D com KEEP_HEIGHT)
	return rad_to_deg(2.0 * atan(VIEW_HALF_H / maxf(z, 0.05)))


## s: estado do carro (ver main.gd: tp, basis, vel, v_f, air_time, grounded, ground_n)
func reset(s: Dictionary, terrain) -> void:
	var tp: Vector3 = s.tp
	var fz: Vector3 = s.basis.z
	var ff := Vector3(fz.x, 0.0, fz.z)
	dir = ff.normalized() if ff.length() > 1e-4 else Vector3.FORWARD
	y_rate = p.POS_DAMPING_Y_GOING_DOWN
	y_s = tp.y + pos_off.y
	extra = 0.0
	ground_s = terrain.height_at(tp.x, tp.z)
	zoom = p.FOV_MIN_ZOOM
	ra_state = 0
	ra_timer = 0.0
	base_rate = 10.0
	pos = tp + Vector3.UP * pos_off.y - dir * absf(pos_off.z)
	# 0x38e0c0: o reset roda 0.5 s de updates de 1/60
	var t := 0.0
	while t < 0.5:
		t += STEP
		_step(STEP, s, terrain)
	_co = pos - tp
	_po = _co
	_pd = dir
	_pz = zoom
	acc = 0.0


func update(delta: float, s: Dictionary, terrain) -> void:
	acc += minf(delta, 0.25)
	while acc >= STEP:
		acc -= STEP
		_po = _co
		_pd = dir
		_pz = zoom
		# este passo foi `acc` s antes deste quadro: o carro estava lá atrás.
		# Sem isso, num quadro com 2 passos (60 Hz quase nunca bate certinho
		# com o 1/60) os dois usam o carro de agora e a câmera vai e volta
		var sp := s
		if acc > 0.0:
			sp = s.duplicate()
			sp.tp = s.tp - s.vel * acc
		_step(STEP, sp, terrain)
		_co = pos - sp.tp


func apply(cam: Camera3D, tp: Vector3) -> void:
	var a := acc / STEP
	var ps := tp + _po.lerp(_co, a)
	var d := _pd.lerp(dir, a)
	if d.length() < 1e-4:
		d = dir
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.global_position = ps
	cam.look_at(ps + d.normalized() * 10.0, Vector3.UP)
	cam.fov = fov_deg(lerpf(_pz, zoom, a))


static func _c01(v: float) -> float:
	return clampf(v, 0.0, 1.0)


static func _slerp_flat(a: Vector3, b: Vector3, t: float) -> Vector3:
	# a, b no plano XZ, normalizados: gira a em direção a b pela fração t do ângulo
	var ang := atan2(a.cross(b).y, a.dot(b))
	return a.rotated(Vector3.UP, ang * t)


func _step(dt: float, s: Dictionary, terrain) -> void:
	var tp: Vector3 = s.tp
	var b: Basis = s.basis
	var vel: Vector3 = s.vel
	var v_f: float = s.v_f
	var spd := vel.length()
	var prev := pos

	# 0x383418 altura: POS_OFFSET.y -> MAX_Y_OFFSET conforme a velocidade (m/s)
	var h: float = pos_off.y
	if p.MAX_Y_SPEED_MAX != p.MAX_Y_SPEED_MIN:
		h += (p.MAX_Y_OFFSET - pos_off.y) * _c01((spd - p.MAX_Y_SPEED_MIN) / (p.MAX_Y_SPEED_MAX - p.MAX_Y_SPEED_MIN))

	# 0x383588 offset no frame do carro, só com a guinada (up do mundo)
	# lado = +X do carro no Godot (esquerda); pos_off já está no frame do Godot
	var fz: Vector3 = b.z
	var lado := Vector3.UP.cross(fz)
	if lado.length() < 1e-5:
		lado = b.x
	lado = lado.normalized()
	var ffl := lado.cross(Vector3.UP)
	var c := tp + lado * pos_off.x + Vector3.UP * h + ffl * pos_off.z

	# 0x383cf8 + 0x384168 amortecimento em Y. Subindo (vy > 1) usa a taxa de
	# subida; a taxa cai na hora mas volta devagar.
	var y_tgt: float = p.POS_DAMPING_Y_GOING_UP if vel.y > 1.0 else p.POS_DAMPING_Y_GOING_DOWN
	if y_rate < y_tgt:
		y_rate += dt * (y_tgt - y_rate)
	else:
		y_rate = y_tgt
	y_s += minf(y_rate * dt, 1.0) * (c.y - y_s)
	c.y = y_s

	# 0x385238 descida: com as rodas no chão, se o carro aponta morro abaixo
	# a câmera sobe (-dir.y * DOWN_INCLINE_MULTIPLIER), com taxa limitada
	var tgt := 0.0
	if s.air_time < p.MAX_WHEELS_OFF_GROUND_TIME:
		var n: Vector3 = s.ground_n
		var d := fz - n * fz.dot(n)
		if d.length() > 1e-6:
			d = d.normalized()
			tgt = -d.y * (p.UP_INCLINE_MULTIPLIER if d.y > 0.0 else p.DOWN_INCLINE_MULTIPLIER)
	var de: float = p.DECAY_FRACTION * (tgt - extra)
	var lim: float = p.MAX_EXTRA_HEIGHT_RATE * dt
	de = clampf(de, -lim, lim)
	extra += de
	c.y += extra

	# 0x386950 órbita: direção alvo = frente do carro puxada pra direção da
	# velocidade (MaxCourseFollowAmount), a câmera gira até ela com
	# SlerpRate e no máximo SlerpMaxAngle graus por passo
	var ff := Vector3(fz.x, 0.0, fz.z)
	var cur := Vector3(dir.x, 0.0, dir.z)
	if ff.length() > 1e-6 and cur.length() > 1e-6:
		ff = ff.normalized()
		cur = cur.normalized()
		var spd_m: float = (spd if p.UseTotalSpeed != 0.0 else absf(v_f)) * MPH
		var a := 0.0
		if v_f >= 0.0:
			if spd_m > p.MaxCourseFollowSpeed:
				a = p.MaxCourseFollowAmount
			elif spd_m > p.NoCourseFollowSpeed:
				a = (spd_m - p.NoCourseFollowSpeed) / (p.MaxCourseFollowSpeed - p.NoCourseFollowSpeed) * p.MaxCourseFollowAmount
		var want := ff
		var vfl := Vector3(vel.x, 0.0, vel.z)
		if a > 0.0 and vfl.length() >= 1e-6:
			want = _slerp_flat(ff, vfl.normalized(), a)
		var fr := minf(p.SlerpRate * dt, 1.0)
		var ang := rad_to_deg(acos(clampf(cur.dot(want), -1.0, 1.0)))
		if ang > 1e-6 and fr * ang > p.SlerpMaxAngle:
			fr = p.SlerpMaxAngle / ang
		var nd := _slerp_flat(cur, want, fr)
		var dist: float = p.MinDistance
		if spd_m > p.MaxDistanceSpeed:
			dist = p.MaxDistance
		elif spd_m > p.MinDistanceSpeed:
			dist += (spd_m - p.MinDistanceSpeed) / (p.MaxDistanceSpeed - p.MinDistanceSpeed) * (p.MaxDistance - p.MinDistance)
		c.x = tp.x - nd.x * dist
		c.z = tp.z - nd.z * dist

	# 0x384ef8 descolar/recolar: se o offset da câmera pula mais que
	# MAX_POS_CHANGE num passo, ela fica presa numa corda e só volta depois de
	# BEGIN_REATTACH_TIME com rodas no chão, misturando em REATTACHMENT_TIME
	var off := c - tp
	if ra_state == 0:
		ra_prev = off
		ra_held = c
		ra_state = 1
	var jump := (off - ra_prev).length()
	if jump > p.MAX_POS_CHANGE:
		if ra_state != 2:
			ra_tether = ra_prev.length()
		ra_state = 2
	ra_prev = off
	if ra_state == 2:
		var anchor := tp + Vector3.UP * h
		var o := ra_held - anchor
		if o.length() > ra_tether and o.length() > 1e-6:
			o *= ra_tether / o.length()
		ra_held = anchor + o
		if jump > p.MAX_POS_CHANGE:
			ra_timer = 0.0
		else:
			if s.grounded > 0:
				ra_timer += dt
			var f := _c01((ra_timer - p.BEGIN_REATTACH_TIME) / p.REATTACHMENT_TIME)
			ra_held = ra_held * (1.0 - f) + c * f
			if f >= 1.0:
				ra_state = 1
		c = ra_held
	ra_held = c

	# 0x384c80 nunca menos de 1.45 m acima do chão (altura do chão suavizada)
	var gh: float = terrain.height_at(c.x, c.z)
	ground_s += minf(GROUND_RATE * dt, 1.0) * (gh - ground_s)
	if c.y - ground_s < GROUND_CLEAR:
		c.y = ground_s + GROUND_CLEAR

	# 0x37f2f8 mira: ponto = carro + LOOK_OFFSET (x/z no frame do carro, y do
	# mundo). Em velocidade o componente vertical da mira vai sumindo.
	var lp := tp + b * Vector3(look_off.x, 0.0, look_off.z)
	lp.y = tp.y + look_off.y
	var ld := lp - c
	var lf := 0.0
	if p.LOOK_OFFSET_MAX_SPEED != p.LOOK_OFFSET_MIN_SPEED:
		lf = _c01((v_f * MPH - p.LOOK_OFFSET_MIN_SPEED) / (p.LOOK_OFFSET_MAX_SPEED - p.LOOK_OFFSET_MIN_SPEED))
	ld.y *= 1.0 - lf
	if ld.length() > 1e-5:
		dir = ld.normalized()

	# 0x380418 tremida: na terra (WheelJitter) acima de JitterSpeedStart e na batida
	dir = CameraJitter.aplicar(dir, jit.passo(dt, s.get("speed", 0.0), s.get("chao", 0.0),
		s.get("batida", 0.0)))

	# 0x3806a0 zoom por velocidade, aproxima com fração dt por passo
	var zf := 0.0
	if p.FOV_MAX_SPEED != p.FOV_MIN_SPEED:
		zf = _c01((absf(v_f) * MPH - p.FOV_MIN_SPEED) / (p.FOV_MAX_SPEED - p.FOV_MIN_SPEED))
	var zt: float = p.FOV_MIN_ZOOM + (p.FOV_MAX_ZOOM - p.FOV_MIN_ZOOM) * zf
	zoom += (zt - zoom) * dt

	# 0x387320 suavização final por eixo (taxa 10 subindo até 40, +5/s) e o
	# empurrão de 0.2 m pra frente da esfera de clipping
	if base_rate < 40.0:
		base_rate += dt * 5.0
	var k := minf(base_rate * dt, 1.0)
	pos = prev + (c + dir * 0.2 - prev) * k
