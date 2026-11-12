extends Node
## Batida carro com carro (nov/2026). pista/ia.gd cria um por corrida com
## rivais.
##
## Do jogo:
##  - Casco: as esferas do VehicleVehicle.hsc (o outro casco do carro, que o
##    0x1fed48 carrega junto com o VehicleWorld.hsc; tools/casco.py ->
##    esferas_carro no <id>_casco.json). As esferas do VehicleWorld (as
##    CollisionShape do car.gd) não batem em outro carro: exceção de colisão
##    entre os carros.
##  - Par de colisão (2, 2) da tabela do 0x14d458 -> 0x1529d0: um contato
##    comum do resolvedor por ponto (0x23e6f0 / 0x23f600, como o do mundo) e
##    as lasquinhas (0x3bbd60) só do carro mais rápido (|v| corpo+0x70), com
##    a velocidade relativa e a tabela de carro com carro do gerente (+0x88:
##    25, 45, 24, 27, 4, 3, 4, 6, 0.7; lascas.gd CARRO).
##  - Som: contato sem material = patch "Vehicle" (sfx_carro, Collisions+0x18)
##    e a tremida da câmera pela maior velocidade na normal (car.batida).
##
## NOSSO (o resolvedor do jogo não foi portado; o do mundo é o do Godot):
## impulso com restituição e atrito médios dos dois (RigidBody Restitution e
## Friction do XML), 2 passadas, no máximo 4 contatos por par (os mais
## fundos). A velocidade só cancela a aproximação (+ restituição na 1ª
## passada); a penetração acima de 1 cm é desfeita MEXENDO A POSIÇÃO (EMPURRA
## dela por passo, até EMPURRA_MAX), pela massa de cada um, sem virar
## velocidade. Até nov/2026 a penetração virava velocidade (20%/passo): lado
## a lado o contato durava vários passos, cada um somava empurrão (parte pra
## cima: as esferas ficam em alturas diferentes) e os carros saíam voando
## (prints do Matheus; teste_batida_carros, lado a lado).

const PASSADAS := 2
const EMPURRA := 0.4
const EMPURRA_MAX := 0.05         # m por passo
const FOLGA := 0.01
const NORMAL_DE_CIMA := 0.7       # |n.y| acima disso o contato é de cima
const MAX_CONTATOS := 4
const PERTO := 9.0                # m entre as origens pra testar o par

var carros: Callable              # () -> Array dos carros (jogador + rivais)
var _esferas := {}                # carro -> [[centro no corpo, raio], ...]
var contatos := 0                 # testes: contatos resolvidos desde o começo


## as esferas do VehicleVehicle.hsc do carro, no frame do corpo
func esferas(car) -> Array:
	if _esferas.has(car):
		return _esferas[car]
	var out: Array = []
	var path := "res://data/vehicles/%s_casco.json" % String(car.vehicle_id).to_lower()
	if FileAccess.file_exists(path):
		var info = JSON.parse_string(FileAccess.get_file_as_string(path))
		if info is Dictionary:
			for e in info.get("esferas_carro", info.get("esferas", [])):
				out.append([car.corpo(Vector3(e[0], e[1], e[2])), float(e[3])])
	_esferas[car] = out
	return out


## sem colisão do Godot entre os cascos de mundo de dois carros, e as rodas
## (raio e esfera do car.gd) de um não pisam no outro: carro com carro é só
## pelas esferas do VehicleVehicle. Até nov/2026 a roda subia no casco do
## vizinho lado a lado e o carro capotava/voava (teste_batida_carros).
static func separar(a: PhysicsBody3D, b: PhysicsBody3D) -> void:
	a.add_collision_exception_with(b)
	b.add_collision_exception_with(a)
	if "outros_carros" in a and not a.outros_carros.has(b.get_rid()):
		a.outros_carros.append(b.get_rid())
	if "outros_carros" in b and not b.outros_carros.has(a.get_rid()):
		b.outros_carros.append(a.get_rid())


func _physics_process(dt: float) -> void:
	if not carros.is_valid():
		return
	var lista: Array = carros.call().filter(func(c): return c != null and is_instance_valid(c))
	for i in lista.size():
		for j in range(i + 1, lista.size()):
			_par(lista[i], lista[j], dt)


func _par(a: RigidBody3D, b: RigidBody3D, dt: float) -> void:
	if a.global_position.distance_to(b.global_position) > PERTO:
		return
	var xa := a.global_transform
	var xb := b.global_transform
	var cs: Array = []
	for ea in esferas(a):
		var pa: Vector3 = xa * (ea[0] as Vector3)
		for eb in esferas(b):
			var pb: Vector3 = xb * (eb[0] as Vector3)
			var d := pa - pb
			var dist := d.length()
			var pen: float = ea[1] + eb[1] - dist
			if pen <= 0.0 or dist < 1e-5:
				continue
			var n := d / dist                      # de B pra A
			var pc := pb + n * (float(eb[1]) - pen * 0.5)
			# NOSSO: contato de lado empurra só na horizontal (a normal de
			# esferas em alturas diferentes é inclinada e o nosso resolvedor
			# fazia um carro subir no outro lado a lado, a cada passo um
			# pouco; o resolvedor do jogo não foi portado). De cima (|n.y| >=
			# NORMAL_DE_CIMA, cair em cima do outro) fica como está.
			if absf(n.y) < NORMAL_DE_CIMA:
				var h := Vector3(n.x, 0.0, n.z)
				if h.length_squared() > 1e-6:
					n = h.normalized()
			cs.append([pc, n, pen])
	if cs.is_empty():
		return
	cs.sort_custom(func(x, y): return x[2] > y[2])
	cs.resize(mini(cs.size(), MAX_CONTATOS))
	var e: float = 0.5 * (_mat(a).bounce + _mat(b).bounce)
	var mu: float = 0.5 * (_mat(a).friction + _mat(b).friction)
	var ia_inv: Basis = a.get_inverse_inertia_tensor()
	var ib_inv: Basis = b.get_inverse_inertia_tensor()
	var ma_inv := 1.0 / a.mass
	var mb_inv := 1.0 / b.mass
	var ca: Vector3 = xa * a.center_of_mass
	var cb: Vector3 = xb * b.center_of_mass
	# antes do impulso: pro som, a câmera e as lasquinhas
	var forte := 0.0
	var forte_c: Array = cs[0]
	for c in cs:
		var vn0 := _vrel(a, b, c[0], ca, cb).dot(c[1])
		if -vn0 > forte:
			forte = -vn0
			forte_c = c
	var va := a.linear_velocity
	var vb := b.linear_velocity
	for _k in PASSADAS:
		for c in cs:
			var p: Vector3 = c[0]
			var n: Vector3 = c[1]
			var ra := p - ca
			var rb := p - cb
			var vrel := _vrel(a, b, p, ca, cb)
			var vn := vrel.dot(n)
			if vn >= 0.0:
				continue            # já se afastando
			var k := ma_inv + mb_inv + n.dot((ia_inv * ra.cross(n)).cross(ra)) + n.dot((ib_inv * rb.cross(n)).cross(rb))
			var j := -(1.0 + (e if _k == 0 else 0.0)) * vn / k
			a.apply_impulse(n * j, p - a.global_position)
			b.apply_impulse(-n * j, p - b.global_position)
			# atrito (Coulomb, até mu x j)
			vrel = _vrel(a, b, p, ca, cb)
			var vt := vrel - n * vrel.dot(n)
			var vtl := vt.length()
			if vtl > 1e-4:
				var t := vt / vtl
				var kt := ma_inv + mb_inv + t.dot((ia_inv * ra.cross(t)).cross(ra)) + t.dot((ib_inv * rb.cross(t)).cross(rb))
				var jt := minf(vtl / kt, mu * j)
				a.apply_impulse(-t * jt, p - a.global_position)
				b.apply_impulse(t * jt, p - b.global_position)
			contatos += 1
	# penetração: separa mexendo a posição (o contato mais fundo), pela massa
	var fundo: Array = cs[0]
	var corr := minf(EMPURRA * maxf(float(fundo[2]) - FOLGA, 0.0), EMPURRA_MAX)
	if corr > 0.0:
		var nn: Vector3 = fundo[1]
		var soma := ma_inv + mb_inv
		a.global_position += nn * corr * ma_inv / soma
		b.global_position -= nn * corr * mb_inv / soma
	if forte <= 0.0:
		return
	var pf: Vector3 = forte_c[0]
	var nf: Vector3 = forte_c[1]
	for par in [[a, pf - ca], [b, pf - cb]]:
		if par[0].has_method("contato_carro"):
			par[0].contato_carro(forte, par[1])
	# 0x1529d0: lasquinhas só do mais rápido, normal saindo do outro,
	# velocidade relativa
	if va.length() >= vb.length():
		_lascas(a, pf, nf, va - vb)
	else:
		_lascas(b, pf, -nf, vb - va)


static func _vrel(a: RigidBody3D, b: RigidBody3D, p: Vector3, ca: Vector3, cb: Vector3) -> Vector3:
	return (a.linear_velocity + a.angular_velocity.cross(p - ca)) - (b.linear_velocity + b.angular_velocity.cross(p - cb))


static func _mat(c: RigidBody3D) -> PhysicsMaterial:
	return c.physics_material_override if c.physics_material_override else PhysicsMaterial.new()


func _lascas(car, p: Vector3, n: Vector3, v: Vector3) -> void:
	var l = car.get("lascas")
	if l:
		l.batida(p, n, v, l.CARRO)
