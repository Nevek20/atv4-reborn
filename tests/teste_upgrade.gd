extends SceneTree
## Peças compradas (carro/pecas.gd, oficina aba Upgrade):
## 1) a conta de fábrica não muda sem troca (Renegade: motor 0.81, final
##    0.61) e trocar entra no lugar da DefaultConfig (Mosquito, tudo Level0,
##    com tudo no máximo: motor 1.0, freio 1.0, suspensão 1.0, final custom)
## 2) acelerando reto em chão plano: Mosquito de fábrica x com as peças no
##    máximo (0-100 km/h e velocidade em 20 s): o de upgrade tem que andar mais
## Uso: godot --headless --path . -s res://tests/teste_upgrade.gd

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


## a peça mais alta de cada slot do Upgrade
static func maximo(classe: String) -> Dictionary:
	var op: Dictionary = PECAS.opcoes(classe)
	var out := {}
	for slot in PECAS.SLOTS:
		var l: Array = op.slots.get(slot, [])
		if not l.is_empty():
			out[slot] = l[-1]
	return out


func _initialize() -> void:
	var a: Dictionary = VD.factory_tuning(PECAS.VEICULOS, PECAS.UPGRADES, "BUGGY_10")
	var b: Dictionary = VD.factory_tuning(PECAS.VEICULOS, PECAS.UPGRADES, "BUGGY_10", {})
	if a.engine != b.engine or a.final != b.final or absf(a.engine - 0.81) > 1e-4 or absf(a.final - 0.61) > 1e-4:
		_falha("Renegade de fábrica: motor %.3f final %.3f (esperado 0.81 e 0.61)" % [a.engine, a.final])
	var mx := maximo("Buggy")
	var f0: Dictionary = VD.factory_tuning(PECAS.VEICULOS, PECAS.UPGRADES, "BUGGY_01")
	var f1: Dictionary = VD.factory_tuning(PECAS.VEICULOS, PECAS.UPGRADES, "BUGGY_01", mx)
	print("  Mosquito de fábrica: motor %.2f freio %.2f susp %.2f final %.2f embreagem %.2f peso %.2f" % [
		f0.engine, f0.brake, f0.susp, f0.final, f0.shift, f0.mass])
	print("  Mosquito no máximo:  motor %.2f freio %.2f susp %.2f final %.2f embreagem %.2f peso %.2f" % [
		f1.engine, f1.brake, f1.susp, f1.final, f1.shift, f1.mass])
	if absf(f1.engine - 1.0) > 1e-4:
		_falha("motor no máximo devia somar 1.0 (0.35+0.2+0.1+0.1+0.2+0.05 do câmbio protótipo)")
	if f1.brake != 1.0 or f1.susp != 1.0 or f1.shift != 1.0 or f1.mass != 1.0:
		_falha("freio, suspensão, embreagem e peso no máximo deviam dar 1.0")
	# o bug do jogo: ir trocando peça e outra voltar. Aqui: cada slot só dele
	var esc := {}
	var op: Dictionary = PECAS.opcoes("Buggy")
	for slot in ["EngineInternals", "EngineManagement", "EngineHeader", "Exhaust", "IntakeKit"]:
		esc[slot] = op.slots[slot][-1]
		var tt: Dictionary = VD.factory_tuning(PECAS.VEICULOS, PECAS.UPGRADES, "BUGGY_01", esc)
		for s2 in esc:
			if tt.config.get(s2) != esc[s2]:
				_falha("trocar %s desfez %s" % [slot, s2])
	# 2) na pista plana
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
		if x.get("id", "") == "BUGGY_01":
			v = x
	for i in 2:
		var c = Car.new()
		Main.configurar(c, v)
		if i == 1:
			c.pecas_escolhidas = mx
		c.suspension = false
		c.SURFACE_MU = 0.8
		c.SURFACE_AMORT = 0.0
		root.add_child(c)
		c.reset_to(Vector3(i * 40.0, 1.0, -3500), 0.0)
		c.test_input = {"thr": 0.0, "brk": 0.0, "steer": 0.0}
		carros.append({"c": c, "t100": -1.0, "v20": 0.0})


func _physics_process(dt: float) -> bool:
	t += dt
	for e in carros:
		if t >= 3.0:
			e.c.test_input.thr = 1.0
			var kmh: float = e.c.linear_velocity.length() * 3.6
			if e.t100 < 0.0 and kmh >= 100.0:
				e.t100 = t - 3.0
			if t <= 23.0:
				e.v20 = kmh
	if t < 23.0:
		return false
	var fab: Dictionary = carros[0]
	var upg: Dictionary = carros[1]
	print("  Mosquito de fábrica: 0-100 em %.2f s, %.0f km/h em 20 s (massa %.0f kg)" % [fab.t100, fab.v20, fab.c.mass])
	print("  Mosquito no máximo:  0-100 em %.2f s, %.0f km/h em 20 s (massa %.0f kg)" % [upg.t100, upg.v20, upg.c.mass])
	if upg.t100 < 0.0 or (fab.t100 > 0.0 and upg.t100 >= fab.t100) or upg.v20 <= fab.v20:
		_falha("com as peças no máximo o carro devia acelerar mais")
	print("teste_upgrade: %s" % ("ok" if falhas == 0 else "FALHA (%d)" % falhas))
	quit()
	return true
