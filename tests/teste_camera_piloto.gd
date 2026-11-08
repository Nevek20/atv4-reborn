extends SceneTree
## Câmera do piloto (camera_piloto.gd, melhoria nossa) com entradas
## sintéticas, sem carro: freada de 1 g, aceleração, curva, deriva, campo de
## visão, borrão e olhar livre (mouse). Confere os números de projeto
## (CABECA_*, FOV_*, CURVA_*, LIVRE_*) e que tudo volta pro centro.
## Uso: godot --headless --path . -s res://tests/teste_camera_piloto.gd
const CameraPiloto := preload("res://camera/camera_piloto.gd")
const DT := 1.0 / 50.0            # passo da física
const DQ := 1.0 / 60.0            # quadro

var cp
var falhas := 0


func _initialize() -> void:
	cp = CameraPiloto.new()
	root.add_child(cp)


func _process(_dt: float) -> bool:
	var g := 9.81
	# frame do carro: +Z frente, +Y cima, +X esquerda
	# 1) freada de 1 g por 1.5 s: a cabeça vai pra frente (~6 cm) e olha pra baixo
	cp.reiniciar()
	var pico := 0.0
	for k in 75:
		cp.passo_cabeca(DT, Vector3(0, 0, -g))
		pico = maxf(pico, cp.cabeca.z)
	var parado: float = cp.cabeca.z
	_conf("freada 1 g: cabeça pra frente", parado, 0.045, 0.06, "m")
	_conf("freada 1 g: passa do ponto no começo (mola)", pico / maxf(parado, 1e-6), 1.0, 1.35, "x")
	for k in 75:
		cp.passo_cabeca(DT, Vector3.ZERO)
	_conf("soltou o freio: volta (1.5 s depois)", absf(cp.cabeca.z), 0.0, 0.005, "m")
	# 2) aceleração de 0.5 g: pra trás
	cp.reiniciar()
	for k in 75:
		cp.passo_cabeca(DT, Vector3(0, 0, 0.5 * g))
	_conf("acelerando 0.5 g: cabeça pra trás", -cp.cabeca.z, 0.025, 0.035, "m")
	# 3) curva pra direita (-X): aceleração pro centro (-X), cabeça vai pra fora (+X)
	cp.reiniciar()
	for k in 75:
		cp.passo_cabeca(DT, Vector3(-0.8 * g, 0, 0))
	_conf("curva 0.8 g pra direita: cabeça pra esquerda (+X)", cp.cabeca.x, 0.035, 0.05, "m")
	# 3b) freada de 1.8 g (Renegade): perto do limite, mas sem grudar nele
	cp.reiniciar()
	for k in 75:
		cp.passo_cabeca(DT, Vector3(0, 0, -1.8 * g))
	_conf("freada 1.8 g: chega perto do limite (8 cm)", cp.cabeca.z, 0.065, 0.075, "m")
	# 4) olhar pra curva: andando a 20 m/s virando pra esquerda (guinada +0.8 rad/s)
	#    com 10° de deriva pro mesmo lado
	cp.reiniciar()
	var b := deg_to_rad(10.0)
	for k in 60:
		cp.passo_quadro(DQ, Vector3(sin(b), 0, cos(b)) * 20.0, 0.8)
	_conf("curva: olha pra dentro (graus, + = esquerda)", rad_to_deg(cp.curva), 10.0, 25.0, "°")
	for k in 60:
		cp.passo_quadro(DQ, Vector3(0, 0, 2.0), 0.0)
	_conf("parado: olha reto", absf(rad_to_deg(cp.curva)), 0.0, 1.0, "°")
	# 5) campo de visão e borrão pela velocidade
	cp.reiniciar()
	for k in 240:
		cp.passo_quadro(DQ, Vector3(0, 0, 60.0), 0.0)
	_conf("216 km/h: campo de visão a mais", cp.fov_extra, 11.5, 12.0, "°")
	_conf("216 km/h: borrão", cp.borrao, 0.95, 1.0, "")
	for k in 240:
		cp.passo_quadro(DQ, Vector3(0, 0, 8.0), 0.0)
	_conf("29 km/h: sem campo a mais", cp.fov_extra, 0.0, 0.2, "°")
	_conf("29 km/h: sem borrão", cp.borrao, 0.0, 0.02, "")
	# 6) mouse: arrasta pra direita 400 px, solta e volta
	cp.mouse_botao(true)
	cp.mouse_arrasto(Vector2(400, 0))
	for k in 30:
		cp.passo_quadro(DQ, Vector3.ZERO, 0.0)
	_conf("mouse 400 px pra direita (graus, - = direita)", rad_to_deg(cp.livre.x), -116.0, -112.0, "°")
	cp.mouse_botao(false)
	for k in 30:
		cp.passo_quadro(DQ, Vector3.ZERO, 0.0)
	_conf("soltou o botão: volta (0.5 s depois)", absf(rad_to_deg(cp.livre.x)), 0.0, 2.0, "°")
	# 7) G desliga: sem efeito nenhum
	cp.ligado = false
	cp.reiniciar()
	for k in 75:
		cp.passo_cabeca(DT, Vector3(0, 0, -g))
	for k in 120:
		cp.passo_quadro(DQ, Vector3(0.3, 0, 1.0) * 60.0, 1.0)
	_conf("G desligado: cabeça parada", cp.cabeca.length(), 0.0, 0.0001, "m")
	_conf("G desligado: sem campo a mais nem curva", cp.fov_extra + absf(cp.curva), 0.0, 0.0001, "")
	print("teste_camera_piloto: %s" % ("ok" if falhas == 0 else "FALHA"))
	return true


func _conf(nome: String, v: float, lo: float, hi: float, un: String) -> void:
	var ok := v >= lo - 1e-9 and v <= hi + 1e-9
	if not ok:
		falhas += 1
	print("%-52s %8.4f %s  (%.4f a %.4f)  %s" % [nome, v, un, lo, hi, "ok" if ok else "FALHA"])
