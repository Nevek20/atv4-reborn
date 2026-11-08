extends SceneTree
## Poeira dos pneus (poeira.gd, porta do jogo) no RX01: o Renegade larga com o
## acelerador no fundo e o volante reto. A cada segundo imprime a velocidade,
## o material das rodas de trás (DustType), a força, as nuvens vivas e o
## tamanho e alfa médios delas. Confere: parado não solta, no asfalto
## (DustType None) a cor some em 1 s e para de soltar, na terra solta. No
## reto ele sai da pista a ~180 km/h e pula (11 s): no ar a roda continua com o
## material da terra até ficar a 25 cm do chão e depois a cor some em 1 s, então
## sobra um rastro curto (o jogo, 0x225108). Imprime quanto tempo soltou no ar.
## Uso: godot --headless --path . -s res://tests/teste_poeira.gd [-- veh]

const Car := preload("res://carro/car.gd")
const Main := preload("res://main.gd")
const Terrain := preload("res://pista/terrain.gd")

var terrain
var car
var t := 0.0
var prox := 1.0
var max_vivas := 0
var parado_vivas := -1
var falhas := 0
var ar_desde := -1.0        # rodas de trás no ar desde
var ar_ultima := -1.0       # última nuvem solta com elas no ar
var ar_longe := -1.0        # quando passaram de 25 cm do chão
var ar_soltas := 0
var ar_n := 0
var ar_max := 0.0           # maior rastro no ar (s, depois de sair do chão)
var ar_tempo := 0.0         # mais tempo no ar


func _initialize() -> void:
	terrain = Terrain.new()
	root.add_child(terrain)
	var a := OS.get_cmdline_user_args()
	var v: Dictionary = Main.frota()[int(a[0]) if a.size() > 0 else 0]
	car = Car.new()
	Main.configurar(car, v)
	car.terrain = terrain
	car.suspension = false
	root.add_child(car)
	car.test_input = {"thr": 0.0, "brk": 0.0, "steer": 0.0}


func _physics_process(dt: float) -> bool:
	if not car.is_inside_tree():
		return false
	if t == 0.0:
		var p: Vector2 = Main.SPAWN_XZ
		car.reset_to(Vector3(p.x, terrain.height_at(p.x, p.y) + 0.8, p.y), deg_to_rad(Main.SPAWN_YAW))
		if car.poeira == null:
			print("teste_poeira: FALHA (sem poeira: falta assets/efeitos/poeira.png? rode tools/fx_jogo.py)")
			return true
	t += dt
	car.test_input.thr = 1.0 if t > 1.5 else 0.0
	var pq = car.poeira
	if t >= 1.4 and parado_vivas < 0:
		parado_vivas = pq.vivas()
	max_vivas = maxi(max_vivas, pq.vivas())
	_mede_ar(pq)
	if t >= prox:
		prox += 1.0
		var tipos := ""
		for e in pq.emissores:
			var w: Dictionary = car.wheels[e.roda]
			var m: Dictionary = terrain.materials[w.mat] if w.hit and w.mat >= 0 else {}
			tipos += " %s(%s, alfa %.2f)" % [String(m.get("Name", "ar")).get_slice("(", 1).trim_suffix(")*"),
				m.get("DustType", "-"), (e.cor as Color).a]
		var tam := 0.0
		var alfa := 0.0
		var n: int = pq.vivas()
		for k in n:
			var tg := clampf(pq.n_idade[k] / pq.n_max[k], 0.0, 1.0)
			var f := 1.0 - pow(1.0 - tg, 4.0)
			tam += pq.n_ini[k] * (1.0 - f) + pq.n_alvo[k] * f
			var tt: float = pq.n_idade[k] / pq.n_vida[k]
			alfa += pq.n_a0[k] * (1.0 - tt * tt)
		var kmh: float = car.linear_velocity.length() * 3.6
		print("%4.1f s  %5.1f km/h  força %.2f  nuvens %4d  tamanho médio %.2f m  alfa médio %.2f %s" % [
			t, kmh, clampf((kmh / 3.6 - 0.5) / 35.0, 0.0, 1.0), n, tam / maxf(n, 1), alfa / maxf(n, 1), tipos])
	if t < 12.0:
		return false
	if parado_vivas != 0:
		falhas += 1
		print("FALHA: parado soltou %d nuvens" % parado_vivas)
	if max_vivas < 20:
		falhas += 1
		print("FALHA: andando soltou só %d nuvens" % max_vivas)
	if ar_tempo > 1.5 and ar_max <= 0.05:
		falhas += 1
		print("FALHA: no ar parou de soltar na hora (o jogo deixa um rastro)")
	if ar_longe >= 0.0 and ar_ultima - ar_longe > 1.05:
		falhas += 1
		print("FALHA: longe do chão soltou por %.2f s (a cor some em 1 s)" % (ar_ultima - ar_longe))
	print("teste_poeira: %s (máximo de nuvens vivas %d de %d)" % ["ok" if falhas == 0 else "FALHA", max_vivas, pq.max_nuvens])
	return true


## rastro no ar: quanto tempo as rodas de trás soltam depois de sair do chão
func _mede_ar(pq) -> void:
	var no_ar := true
	var folga := 0.0
	for e in pq.emissores:
		var w: Dictionary = car.wheels[e.roda]
		if w.hit:
			no_ar = false
		else:
			var xf: Transform3D = car.global_transform
			folga = maxf(folga, pq._folga(xf * Vector3(w.px, w.y0 + w.x, w.pz), xf.basis.y, w.r))
	if no_ar and ar_desde < 0.0 and t < 11.99:
		ar_desde = t
		ar_ultima = -1.0
		ar_longe = -1.0
		ar_soltas = pq.soltas
		ar_n = 0
	if no_ar:
		if folga >= 0.25 and ar_longe < 0.0:
			ar_longe = t
		if pq.soltas > ar_soltas:
			ar_n += pq.soltas - ar_soltas
			ar_soltas = pq.soltas
			ar_ultima = t
	if ar_desde >= 0.0 and (not no_ar or t >= 11.99):
		var dur := t - ar_desde
		var rastro := maxf(ar_ultima - ar_desde, 0.0)
		print("  no ar %.2f s (aos %.1f s): soltou %d nuvens por %.2f s; a 25 cm do chão aos %s" % [
			dur, ar_desde, ar_n, rastro, "%.2f s" % (ar_longe - ar_desde) if ar_longe >= 0.0 else "nunca"])
		ar_max = maxf(ar_max, rastro)
		ar_tempo = maxf(ar_tempo, dur)
		ar_desde = -1.0
