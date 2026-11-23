extends SceneTree
## Tune & Setup (oficina, aba Ajuste; carro/pecas.gd + vehicle_data.factory_tuning):
## 1) marchas e final custom (GearRatioTuning 0..1) entram na conta; com câmbio
##    Level0/1 a final continua a do FinalDriveRatio (0.45/0.53), como no jogo
##    (0x21d2c8); amortecedor Hard = mola e amortecimento 1.0; Level2 libera só
##    a final, Level3/Prototype as marchas também (0x3ec5d0)
## 2) Renegade em chão plano: marchas longas (0.0) chegam mais rápido no fim
##    e curtas (1.0) menos; no extremo curto a 1ª bate no limitador e o 0-100
##    piora (4 trocas até 100 contra 1): é a física, não "sempre acelera mais"
## Uso: godot --headless --path . -s res://tests/teste_ajuste.gd

const Main := preload("res://main.gd")
const Car := preload("res://carro/car.gd")
const VD := preload("res://carro/vehicle_data.gd")
const PECAS := preload("res://carro/pecas.gd")

var carros: Array = []
var t := 0.0
var falhas := 0


func _falha(s: String) -> void:
	print("  FALHA: " + s)
	falhas += 1


static func marchas(v: float) -> Dictionary:
	return {"GearRatioTuning": {"Gear1": v, "Gear2": v, "Gear3": v, "Gear4": v, "Gear5": v, "FinalDrive": v}}


func _initialize() -> void:
	var r0: Dictionary = VD.factory_tuning(PECAS.VEICULOS, PECAS.UPGRADES, "BUGGY_10")
	var r1: Dictionary = VD.factory_tuning(PECAS.VEICULOS, PECAS.UPGRADES, "BUGGY_10", marchas(1.0))
	print("  Renegade (câmbio Level3): marchas %s final %.2f -> custom 1.0: marchas %s final %.2f" % [r0.gears, r0.final, r1.gears, r1.final])
	if r1.gears != [1.0, 1.0, 1.0, 1.0, 1.0] or absf(r1.final - 1.0) > 1e-6:
		_falha("marchas/final custom não entraram (Level3)")
	var m1: Dictionary = VD.factory_tuning(PECAS.VEICULOS, PECAS.UPGRADES, "BUGGY_01", marchas(1.0))
	print("  Mosquito (câmbio Level0) com final custom 1.0: final %.2f (o jogo usa a 0.45 do FinalDriveRatio)" % m1.final)
	if absf(m1.final - 0.45) > 1e-6:
		_falha("Level0 devia ignorar a final custom")
	var h: Dictionary = VD.factory_tuning(PECAS.VEICULOS, PECAS.UPGRADES, "BUGGY_10", {"Shocks": "Shocks_Hard"})
	var so: Dictionary = VD.factory_tuning(PECAS.VEICULOS, PECAS.UPGRADES, "BUGGY_10", {"Shocks": "Shocks_Soft"})
	print("  amortecedor: Soft mola %.2f amort %.2f, Medium %.2f %.2f, Hard %.2f %.2f" % [so.spring, so.damping, r0.spring, r0.damping, h.spring, h.damping])
	if h.spring != 1.0 or h.damping != 1.0 or so.spring != 0.0:
		_falha("amortecedor não entrou")
	var lib := {}
	for n in ["Level0", "Level1", "Level2", "Level3", "Prototype"]:
		lib[n] = PECAS.ajuste_libera("GearboxLevel_" + n)
	print("  libera: %s" % lib)
	if lib.Level1.final or not lib.Level2.final or lib.Level2.marchas or not lib.Level3.marchas or not lib.Prototype.marchas:
		_falha("o que cada câmbio libera não bate com o 0x3ec5d0")
	# 2) chão plano
	var chao := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8000, 2, 8000)
	cs.shape = box
	cs.position = Vector3(0, -1, 0)
	chao.add_child(cs)
	root.add_child(chao)
	var v: Dictionary = {}
	for x in Main.frota():
		if x.get("id", "") == "BUGGY_10":
			v = x
	for i in 3:
		var c = Car.new()
		Main.configurar(c, v)
		c.pecas_escolhidas = [{}, marchas(1.0), marchas(0.0)][i]
		c.suspension = false
		c.SURFACE_MU = 0.8
		c.SURFACE_AMORT = 0.0
		root.add_child(c)
		c.reset_to(Vector3(i * 40.0, 1.0, -3500), 0.0)
		c.test_input = {"thr": 0.0, "brk": 0.0, "steer": 0.0}
		carros.append({"c": c, "nome": ["perfil de fábrica", "marchas curtas (1.0)", "marchas longas (0.0)"][i], "t100": -1.0, "v20": 0.0, "v1": 0.0, "trocas": 0, "g": 0})


func _physics_process(dt: float) -> bool:
	t += dt
	for e in carros:
		if t >= 3.0:
			e.c.test_input.thr = 1.0
			var kmh: float = e.c.linear_velocity.length() * 3.6
			if e.t100 < 0.0 and kmh >= 100.0:
				e.t100 = t - 3.0
			if t <= 4.5:
				e.v1 = kmh
			if e.t100 < 0.0 and e.c.gear != e.g:
				e.trocas += 1
			e.g = e.c.gear
			if t <= 33.0:
				e.v20 = kmh
	if t < 33.0:
		return false
	for e in carros:
		print("  Renegade %s: %.0f km/h em 1.5 s, 0-100 em %.2f s (%d trocas), %.0f km/h em 30 s" % [e.nome, e.v1, e.t100, e.trocas, e.v20])
	var fab: Dictionary = carros[0]
	var curta: Dictionary = carros[1]
	var longa: Dictionary = carros[2]
	# no extremo (tudo curto) a 1ª do Renegade bate no limitador logo e as
	# trocas comem o ganho no 0-100: o certo garantido é a velocidade final
	if not (longa.v20 > fab.v20 and fab.v20 > curta.v20):
		_falha("velocidade final devia ser longas > fábrica > curtas")
	if curta.t100 == fab.t100 and longa.t100 == fab.t100:
		_falha("o ajuste não mudou a aceleração")
	print("teste_ajuste: %s" % ("ok" if falhas == 0 else "FALHA (%d)" % falhas))
	quit()
	return true
