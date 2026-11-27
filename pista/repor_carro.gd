extends RefCounted
## Objeto de reposição de cada corredor (nov/2026): porta do 0x15ba00
## (corredor+0xfc; o jogador e os 7 rivais têm um). Pedido 0x15bd28 e update
## 0x15c0e8 (docs/engenharia_reversa.md, Reposição automática):
##  1 = espera ESPERA s (+0x64; a tela do jogador vai pro preto), o carro
##      continua andando;
##  2 = repõe (0x15bc50: põe o carro e liga o fantasma, veículo+0xb28 = 0);
##  3 = espera o quadro seguinte e 0x15bfe0 vai pro 4 (a tela volta);
##  4 = conta FANTASMA s; depois só termina (0x15c090: fantasma desligado)
##      quando a caixa do carro não encosta na de nenhum outro (0x15c350).
## Quem pede (0x15bd28(tempo, obj, forçar, na_hora, sem_tela)):
##  - o progresso (fora, contramão, checkpoint; 0x4d3538) e as
##    cInstantRespotBox (0x542208, só com o objeto parado): forçar, com a
##    espera e a tela preta (o "instant" é sem a contagem 3-2-1);
##  - o preso da IA (#2, 0x3646d0): forçar e na hora (pula o 1, vai pro 4);
##  - o preso do jogador (0x2017a8) e o botão: sem forçar.
## Sem forçar, com pedido andando, não entra. Forçado com pedido andando
## volta pro 1 com o tempo que estava (só o objeto parado começa em 0.3 s).
##
## Fantasma = sem batida carro com carro (o 0x151028 só cria o contato se os
## dois veículos têm +0xb28 != 0): carro/batida_carros.gd pula o par.
## O +0x68 (1 -> 0 na espera, (1 - cos(178 t)) / 2 no fantasma) NÃO é
## portado: nenhum código do exe lê esse campo (varredura do ELF inteiro), o
## carro não pisca no PAL.
## Multiplayer local: um objeto por carro, cada jogador com a sua tela preta.

const ESPERA := 0.3              # +0x64 no estado 1 (0x15bd28)
const FANTASMA := 0.3            # estado 4 (0x15c0e8)

var car: RigidBody3D
var estado := 0
var t := 0.0
var fader = null                 # tela preta do dono (só jogador)
var repor: Callable              # põe o carro no ponto (o ia.gd)
var outros: Callable             # () -> Array dos outros carros (a caixa do 4)
var esferas: Callable            # carro -> esferas do VehicleVehicle (batida_carros.gd)


func _init(car_: RigidBody3D, repor_: Callable, outros_: Callable, esferas_: Callable, fader_ = null) -> void:
	car = car_
	repor = repor_
	outros = outros_
	esferas = esferas_
	fader = fader_


## 0x15bd28: sem forçar e com pedido andando não faz nada; "na hora" repõe
## no ato
func pedir(na_hora := false, forcar := false) -> void:
	if not forcar and estado != 0:
		return
	if na_hora:
		t = 0.0
		_repor()
		estado = 4
		return
	if estado == 0:
		t = ESPERA
	estado = 1
	if fader:
		fader.escurecer()


func passo(dt: float) -> void:
	match estado:
		1:
			t -= dt
			if t <= 0.0:
				estado = 2
				t = 0.0
		2:
			_repor()
			estado = 3
		3:
			if fader:
				fader.clarear()      # 0x15bfe0 -> 0x4576e0
			estado = 4
			t = 0.0
		4:
			t += dt
			if t >= FANTASMA and not _encosta():
				terminar()


## 0x15c090: fim do fantasma (e o recomeço da corrida)
func terminar() -> void:
	estado = 0
	t = 0.0
	if is_instance_valid(car):
		car.fantasma = false


func _repor() -> void:
	repor.call()
	if is_instance_valid(car):
		car.fantasma = true


## 0x15c350: a caixa do carro (mundo, alinhada aos eixos) encosta na de
## outro? A caixa = as esferas do VehicleVehicle (NOSSO: o exe usa a caixa do
## veículo pela vtable +0x94)
func _encosta() -> bool:
	if not is_instance_valid(car):
		return false
	var a := caixa(car)
	for o in outros.call():
		if o != car and is_instance_valid(o) and a.intersects(caixa(o)):
			return true
	return false


func caixa(c: Node3D) -> AABB:
	var xf: Transform3D = c.global_transform
	var esf: Array = esferas.call(c) if esferas.is_valid() else []
	if esf.is_empty():
		return AABB(xf.origin - Vector3(1.0, 0.75, 2.0), Vector3(2.0, 1.5, 4.0))
	var cx := AABB(xf * Vector3(esf[0][0]), Vector3.ZERO)
	for e in esf:
		var p: Vector3 = xf * Vector3(e[0])
		var r := float(e[1])
		cx = cx.merge(AABB(p - Vector3(r, r, r), Vector3(r, r, r) * 2.0))
	return cx
