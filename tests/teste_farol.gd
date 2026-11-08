extends SceneTree
## Farol (farol.gd, melhoria nossa no estilo da lanterna de freio) nos 12
## buggies e nos 12 trucks: quantas lâmpadas acharam pelas texturas de farol
## do modelo (Farol.LAMPADAS), onde ficam, faces de lente e brilhos, e se acende
## e apaga no tempo da lâmpada do freio (Luzes.ACENDE / APAGA).
## Buggies: só o Hurricane (2 faróis) e o Storm (2 faróis + 4 milhas) têm lente
## de farol; no Mosquito a light_64 é a lanterna de trás. Trucks: Shockwave,
## Jericho, Goliath e Chimera (2 cada). Os outros ficam sem (ok).
## Uso: godot --headless --path . -s res://tests/teste_farol.gd
const Car := preload("res://carro/car.gd")
const Main := preload("res://main.gd")
const Farol := preload("res://carro/farol.gd")
const Luzes := preload("res://carro/luzes.gd")
# lâmpadas por carro, pelo nome (o bônus tem o id do Jericho)
const ESPERADO := {"Hurricane": 2, "Storm": 6,
	"Shockwave": 2, "Jericho": 2, "Goliath": 2, "Chimera": 2, "Lazarus": 2}

var i := -1
var car = null
var vistos := {}
var falhas := 0
var com_farol := 0


func _process(_dt: float) -> bool:
	if car != null:
		_conferir()
		car.free()
		car = null
	i += 1
	while i < Main.frota().size() and vistos.has(Main.frota()[i].dir):
		i += 1
	if i >= Main.frota().size():
		var ok := com_farol == ESPERADO.size()
		falhas += 0 if ok else 1
		print("carros com farol: %d (esperado %d)  %s" % [com_farol, ESPERADO.size(), "ok" if ok else "FALHA"])
		print("teste_farol: %s" % ("ok" if falhas == 0 else "FALHA"))
		return true
	var v: Dictionary = Main.frota()[i]
	vistos[v.dir] = true   # pela pasta: a variação do Sphinx sai, o bônus (id do Jericho) entra
	car = Car.new()
	car.asset_dir = v.dir
	car.data_files = Main.dados(v)
	car.points_file = v.points
	car.vehicle_id = v.id
	car.suspension = false
	if v.id.begins_with("TRUCK"):
		car.desligadas = Car.PENDENTES_TRUCK
	root.add_child(car)
	car.set_physics_process(false)
	car.set_process(false)
	return false


func _conferir() -> void:
	var v: Dictionary = Main.frota()[i]
	var f = car.farol
	if f == null:
		print("%-9s %-10s sem farol no modelo" % [v.id, v.name])
		return
	com_farol += 1
	Farol.ligado = true
	f.atualizar(Luzes.ACENDE * 0.5)
	var meio: float = f.aceso
	f.atualizar(Luzes.ACENDE)
	var cheio: float = f.aceso
	Farol.ligado = false
	f.atualizar(Luzes.APAGA * 0.5)
	var meio_apaga: float = f.aceso
	f.atualizar(Luzes.APAGA)
	var apagado: float = f.aceso
	Farol.ligado = true
	var ok: bool = f.lampadas.size() == ESPERADO.get(v.name, -1) and f.halos == f.lampadas.size() \
		and f.faces > 0 and absf(meio - 0.5) < 1e-4 and cheio >= 1.0 and absf(meio_apaga - 0.5) < 1e-4 \
		and apagado == 0.0 and f.lampadas.all(func(l): return l.n.z > 0.5 and l.c.z > 0.5)
	falhas += 0 if ok else 1
	print("%-9s %-10s %d lâmpadas %s  %d faces de lente, %d brilhos  acende %.2f/%.2f apaga %.2f/%.2f  %s" % [
		v.id, v.name, f.lampadas.size(),
		" ".join(f.lampadas.map(func(l): return "(%.2f, %.2f, %.2f)" % [l.c.x, l.c.y, l.c.z])),
		f.faces, f.halos, meio, cheio, meio_apaga, apagado, "ok" if ok else "FALHA"])
