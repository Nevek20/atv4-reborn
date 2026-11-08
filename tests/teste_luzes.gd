extends SceneTree
## Lanterna de freio e luz de ré (luzes.gd, melhoria nossa) e cor do vértice
## (car.gd COR_VERTICE) nos 12 buggies e nos 12 trucks: quantas faces de lente acharam perto
## dos pontos BRAKE_LIGHT (vermelhas) e REVERSE_LIGHT (brancas, só nos carros
## que têm o ponto), se os materiais do jogo usam a cor do vértice e se as
## luzes acendem (freando, de ré) e apagam.
## Uso: godot --headless --path . -s res://tests/teste_luzes.gd
const Car := preload("res://carro/car.gd")
const Main := preload("res://main.gd")
const Luzes := preload("res://carro/luzes.gd")

var i := -1
var car = null
var vistos := {}
var falhas := 0


func _process(_dt: float) -> bool:
	if car != null:
		_conferir()
		car.free()
		car = null
	i += 1
	while i < Main.frota().size() and vistos.has(Main.frota()[i].dir):
		i += 1
	if i >= Main.frota().size():
		print("teste_luzes: %s" % ("ok" if falhas == 0 else "FALHA"))
		return true
	var v: Dictionary = Main.frota()[i]
	vistos[v.dir] = true   # pela pasta: a variação do Sphinx sai, o bônus (id do Jericho) entra
	car = Car.new()
	Main.configurar(car, v)
	car.suspension = false
	root.add_child(car)
	car.set_physics_process(false)
	car.set_process(false)
	return false


func _conferir() -> void:
	var v: Dictionary = Main.frota()[i]
	var lz = car.luzes
	# cor do vértice ligada nos materiais da carroceria
	var com_cor := 0
	var mats := 0
	for s in car.body_mi.mesh.get_surface_count():
		var m := car.body_mi.get_active_material(s) as StandardMaterial3D
		if m and m.albedo_color.a > 0.0:      # a placa que o painel esconde fica de fora
			mats += 1
			com_cor += 1 if m.vertex_color_use_as_albedo else 0
	var ok_cor: bool = com_cor == mats and car.cor_k() > 4.0
	if v.get("extra", false):
		ok_cor = com_cor == 0          # carro extra (.glb): materiais PBR do modelo, sem cor de vértice
	var linha := "%-9s %-10s cor do vértice %d/%d (k %.2f)" % [v.id, v.name, com_cor, mats, car.cor_k()]
	if lz == null:
		print(linha + "  sem lente achada  %s" % ("ok" if ok_cor else "FALHA"))
		falhas += 0 if ok_cor else 1
		return
	# acende freando / de ré, apaga soltando
	for k in 30:
		lz.atualizar(1.0 / 60.0, 1.0, true)
	var aceso_freando: float = lz.aceso.freio
	var aceso_re: float = lz.aceso.re
	for k in 30:
		lz.atualizar(1.0 / 60.0, 0.0, false)
	var solto: float = lz.aceso.freio + lz.aceso.re
	var tem_re: bool = car.points.keys().any(func(k): return String(k).begins_with("REVERSE_LIGHT"))
	var ok_re: bool = not tem_re or (lz.faces.re >= 1 and lz.halos.re >= 1 and aceso_re > 0.99)
	var ok: bool = ok_cor and ok_re and lz.faces.freio >= 2 and lz.halos.freio >= 2 \
		and aceso_freando > 0.99 and solto < 0.01
	falhas += 0 if ok else 1
	print(linha + "  freio %3d faces %d halos  ré %s  acesa %.2f/%.2f solta %.2f  %s" % [
		lz.faces.freio, lz.halos.freio,
		("%2d faces %d halos" % [lz.faces.re, lz.halos.re]) if tem_re else "(sem ponto)",
		aceso_freando, aceso_re, solto, "ok" if ok else "FALHA"])
