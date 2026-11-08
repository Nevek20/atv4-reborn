extends SceneTree
## Pneu parado na ladeira (sfx_carro.gd): procura no RX01, perto da largada,
## barrancos de 8 a 30 graus (o mais inclinado, o do meio e o mais suave), põe o buggy lá parado e sem pedal (de frente
## pra descida e de lado) e conta, em 6 s, quantas vezes o som das rodas liga
## e desliga. A patinada medida (giro x raio / v - 1) com o carro quase parado
## pula (divide por quase zero): sem a trava PATINA_MIN o som piscava.
## Uso: godot --headless --path . -s res://tests/teste_ladeira.gd -- [veiculo]

const ASSENTA := 1.5
const MEDE := 6.0
const INC_MIN := 8.0
const INC_MAX := 30.0

var main
var veh := 0
var t := 0.0
var lugares: Array = []           # [posição, yaw]
var k := -1
var falhas := 0
var liga := 0
var pisca_bruto := 0
var vol_max := 0.0
var ant := false
var ant_bruto := false
var nome := ""


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		veh = int(a[0])
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _achar() -> void:
	var tr = main.terrain
	var c: Vector2 = main.SPAWN_XZ
	var melhor := []
	for r in range(20, 200, 10):
		for i in 24:
			var ang := TAU * i / 24.0
			var p := c + Vector2(cos(ang), sin(ang)) * r
			var h: float = tr.height_at(p.x, p.y)
			var gx: float = (tr.height_at(p.x + 1.0, p.y) - tr.height_at(p.x - 1.0, p.y)) * 0.5
			var gz: float = (tr.height_at(p.x, p.y + 1.0) - tr.height_at(p.x, p.y - 1.0)) * 0.5
			var inc := rad_to_deg(atan(Vector2(gx, gz).length()))
			if inc > INC_MIN and inc < INC_MAX:
				# yaw com a frente (+Z do carro) pra descida
				var desce := Vector2(-gx, -gz).normalized()
				melhor.append([Vector3(p.x, h + 1.0, p.y), atan2(desce.x, desce.y), inc, tr.sfx(tr.material_at(p.x, p.y))])
	melhor.sort_custom(func(a, b): return a[2] > b[2])
	for m in [melhor[0], melhor[melhor.size() / 2], melhor[-1]] if melhor.size() > 2 else melhor:
		lugares.append([m[0], m[1], "de frente %.0f° %s" % [m[2], m[3]]])
		lugares.append([m[0], m[1] + PI * 0.5, "de lado %.0f° %s" % [m[2], m[3]]])


func _physics_process(dt: float) -> bool:
	if main.car == null:
		return false
	if lugares.is_empty() and k < 0:
		_achar()
		if lugares.is_empty():
			print("teste_ladeira: FALHA (não achei barranco de 10 a 20°)")
			return true
	var car = main.car
	if k < 0 or t >= ASSENTA + MEDE:
		if k >= 0:
			_fim()
		k += 1
		if k >= lugares.size():
			print("teste_ladeira: %s" % ("ok" if falhas == 0 else "FALHA"))
			return true
		main.car.queue_free()
		main.spawn_vehicle(veh, lugares[k][0], lugares[k][1])
		nome = lugares[k][2]
		t = 0.0
		liga = 0
		pisca_bruto = 0
		vol_max = 0.0
		ant = false
		ant_bruto = false
		return false
	if car.sfx == null:
		print("teste_ladeira: FALHA (sem assets/sons)")
		return true
	car.test_input = {"thr": 0.0}
	t += dt
	if t < ASSENTA:
		return false
	var v := 0.0
	for o in car.sfx.rodas:
		if o.som.tocando:
			v = maxf(v, o.som.volume * o.som.ganho)
	vol_max = maxf(vol_max, v)
	var on := v > 0.01
	if on and not ant:
		liga += 1
	ant = on
	var bruto := false
	for w in car.wheels:
		if w.sr > 0.2:
			bruto = true
	if bruto != ant_bruto:
		pisca_bruto += 1
	ant_bruto = bruto
	if OS.has_environment("DETALHE"):
		var srs := []
		for w in car.wheels:
			srs.append("%5.2f%s" % [w.sr, "" if w.hit else "*"])
		print("  %.2f %5.2f km/h sr %s vol %.3f derrapa %.2f ws %.1f freio %.2f" % [t, car.linear_velocity.length() * 3.6, " ".join(srs), v, car.sfx.derrapa, car.sfx.ws, car.brake_in])
	return false


func _fim() -> void:
	var car = main.car
	var ok := liga <= 1
	if not ok:
		falhas += 1
	print("%-22s %4.1f km/h  som ligou %2d vezes (volume máx %.3f)  patinada > 0.2 sem trava trocou %3d vezes  %s" % [
		nome, car.linear_velocity.length() * 3.6, liga, vol_max, pisca_bruto, "ok" if ok else "FALHA"])
