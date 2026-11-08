extends SceneTree
## Pedais do jogador no AutoManual (0x202df0, car._pedais_auto): freio
## automático parado, ré pelo freio, volta pra frente e corte no ar.
## Uso: godot --headless --path . -s res://tests/teste_pedais.gd

const Car := preload("res://carro/car.gd")
const MPH_G := 0.44694445
const DT := 0.02

var car
var falhas := 0


func _initialize() -> void:
	car = Car.new()
	# parado sem pedal: o jogo segura no freio (barra vermelha cheia na largada)
	_passo(0.0, 0.0, 0.0)
	_conf("parado sem pedal: freio 1, sem ré", car.brk_cx == 1.0 and car.thr_cx == 0.0 and not car.want_rev)
	_passo(0.05, 0.0, 0.0)
	_conf("andando 0.11 mph sem pedal: freio 1", car.brk_cx == 1.0)
	_passo(0.3, 0.0, 0.0)
	_conf("andando 0.67 mph sem pedal: sem freio", car.brk_cx == 0.0)
	# acelerando parado: sem freio automático (ele cai na rampa do pedal)
	_passo(0.0, 1.0, 0.0)
	_conf("acelerando parado: acelerador 1, freio 0", car.thr_cx == 1.0 and car.brk_cx == 0.0)
	# vindo andando pra frente (> 1 mph) o freio espera 0.1 s antes de virar ré
	_passo(5.0, 0.0, 1.0)
	_conf("freando a 11 mph: freio, espera 0.1 s", car.brk_cx == 1.0 and not car.want_rev and absf(car.rev_timer - 0.1) < 1e-6)
	var n := 0
	while not car.want_rev and n < 20:
		_passo(0.0, 0.0, 1.0)
		n += 1
	_conf("parou segurando o freio: ré depois de %d passos (0.1 s / 0.02 = 5 + 1)" % n, n == 6)
	_conf("na ré o freio vira acelerador", car.thr_cx == 1.0 and car.brk_cx == 0.0)
	# soltando o freio a espera zera: freio de novo parado = ré na hora
	car.want_rev = false
	_passo(0.0, 0.0, 0.0)
	_passo(0.0, 0.0, 1.0)
	_conf("freio de novo parado: ré na hora", car.want_rev)
	# de ré a mais de 1 mph o acelerador freia; devagar volta pra frente
	_passo(-2.0, 1.0, 0.0)
	_conf("de ré a 4.5 mph acelerando: vira freio, continua de ré", car.want_rev and car.brk_cx == 1.0 and car.thr_cx == 0.0)
	_passo(-0.2, 1.0, 0.0)
	_conf("de ré a 0.45 mph acelerando: volta pra frente", not car.want_rev and car.thr_cx == 1.0)
	# no ar o acelerador fica cortado até ser solto uma vez nesse voo
	car.air_time = 0.1
	_passo(20.0, 1.0, 0.0)
	_conf("decolou acelerando: cortado", car.thr_cx == 0.0)
	_passo(20.0, 0.0, 0.0)
	_passo(20.0, 1.0, 0.0)
	_conf("soltou no ar e apertou de novo: acelera", car.thr_cx == 1.0)
	car.air_time = 0.0
	_passo(20.0, 1.0, 0.0)
	car.air_time = 0.1
	_passo(20.0, 1.0, 0.0)
	_conf("pousou e decolou de novo acelerando: cortado de novo", car.thr_cx == 0.0)
	car.free()
	print("teste_pedais: %s" % ("ok" if falhas == 0 else "%d FALHA(S)" % falhas))
	quit(0 if falhas == 0 else 1)


## um passo do 0x202df0 com o carro andando v (m/s) pra frente do corpo
func _passo(v: float, thr: float, brk: float) -> void:
	car.linear_velocity = Vector3(0.0, 0.0, v)
	car._pedais_auto(DT, v, thr, brk)


func _conf(txt: String, ok: bool) -> void:
	print("%s  %s" % [txt, "ok" if ok else "FALHA"])
	if not ok:
		falhas += 1
