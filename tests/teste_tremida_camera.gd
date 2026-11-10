extends SceneTree
## Confere a tremida da câmera (camera_jitter.gd, 0x380418/0x380170):
##  - tabela de ruído (257 valores, último = primeiro) e a interpolação
##    (valores calculados em Python a partir do mesmo .bin);
##  - parâmetros e ondas iguais aos componentes vivos na RAM do save state
##    do Renegade (órbita: ondas (0.0075, 0.3) e (0.03, 0.315); capô/para-
##    choque: (0.01, 0.25) e (0.04, 0.2625));
##  - um passo: asfalto (WheelJitter 0) e abaixo de JitterSpeedStart não
##    tremem; acima de JitterSpeedMax n = ruído(fase) * amp_onda * chão, e
##    a fase anda dt * freq.
## Uso: godot --headless --path . -s res://tests/teste_tremida_camera.gd

const J := preload("res://camera/camera_jitter.gd")
const XML := "res://data/cameras.xml"
const MPH := 2.2374146

var falhas := 0


func _ok(cond: bool, txt: String) -> void:
	if not cond:
		falhas += 1
		print("  FALHOU: " + txt)


func _initialize() -> void:
	var tab := FileAccess.get_file_as_bytes(J.TABELA).to_float32_array()
	_ok(tab.size() == 257 and tab[256] == tab[0], "tabela com %d valores" % tab.size())
	var ref := {0.0: -0.5231781005859375, 0.1234: -0.31383925676345825, 0.5: -0.4015911817550659,
		0.9999: -0.520975649356842}
	J.carregar(XML, "FollowOrbitNear")   # carrega a tabela
	for f in ref:
		_ok(absf(J.ruido(f) - ref[f]) < 1e-6, "ruído(%s) = %f, Python %f" % [f, J.ruido(f), ref[f]])

	var ram := {"FollowOrbitNear": [0.0075, 0.3, 0.03, 0.315, 70.0, 100.0],
		"FollowOrbitFar": [0.0075, 0.3, 0.03, 0.315, 70.0, 100.0],
		"MountOnHood": [0.01, 0.25, 0.04, 0.2625, 0.0, 75.0],
		"MountOnFront": [0.01, 0.25, 0.04, 0.2625, 0.0, 75.0]}
	for tipo in ram:
		var j = J.carregar(XML, tipo)
		var e: Array = ram[tipo]
		var got := [j.ondas[0][0], j.ondas[0][1], j.ondas[1][0], j.ondas[1][1],
			j.p.JitterSpeedStart, j.p.JitterSpeedMax]
		for i in 6:
			_ok(absf(got[i] - e[i]) < 1e-6, "%s campo %d = %f, RAM %f" % [tipo, i, got[i], e[i]])
	print("parâmetros x RAM: %s" % ("ok" if falhas == 0 else "FALHOU"))

	var dt := 1.0 / 60.0
	var j = J.carregar(XML, "FollowOrbitNear")
	j.ondas[0][2] = 0.1234
	j.ondas[1][2] = 0.5
	_ok(j.passo(dt, 120.0 / MPH, 0.0) == Vector2.ZERO, "asfalto tremeu")
	_ok(j.passo(dt, 60.0 / MPH, 0.3) == Vector2.ZERO, "tremeu abaixo de 70 mph")
	j.ondas[0][2] = 0.1234
	j.ondas[1][2] = 0.5
	var n: Vector2 = j.passo(dt, 120.0 / MPH, 0.3)
	_ok(absf(n.x - ref[0.1234] * 0.0075 * 0.3) < 1e-7 and absf(n.y - ref[0.5] * 0.03 * 0.3) < 1e-7,
		"passo a 120 mph na terra: %s" % n)
	_ok(absf(j.ondas[0][2] - (0.1234 + dt * 0.3)) < 1e-7, "fase não andou dt*freq")
	# metade do caminho (85 mph): amplitude * 0.25 (f²)
	j.ondas[0][2] = 0.1234
	var m: Vector2 = j.passo(dt, 85.0 / MPH, 0.3)
	_ok(absf(m.x - ref[0.1234] * 0.0075 * 0.3 * 0.25) < 1e-6, "f² a 85 mph: %f" % m.x)
	# a direção gira pra direita/cima da câmera e continua unitária
	var d := Vector3(0, 0, -1)
	var d2: Vector3 = J.aplicar(d, Vector2(0.01, 0.0))
	_ok(d2.x > 0.0 and absf(d2.length() - 1.0) < 1e-6, "aplicar: %s" % d2)
	print("teste_tremida_camera: %s" % ("ok" if falhas == 0 else "%d falhas" % falhas))
	quit(1 if falhas else 0)
