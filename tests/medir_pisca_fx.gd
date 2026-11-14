extends SceneTree
## Pisca dos efeitos na imagem (Forward+, precisa de tela: na nuvem lavapipe,
## docs/comandos.md). Corrida fixa (semente 7, a IA pilota o jogador), grava
## QUADROS quadros a partir do passo INICIO e conta pixels que piscam: mudam
## mais que LIMIAR de um quadro pro outro e voltam no seguinte (sobe e desce).
## SAIDA=pasta grava os quadros em PNG. ORDEM_FX=0 compara sem efeitos/ordem_fx.
##   godot --path . --resolution 480x270 --fixed-fps 50 -s res://tests/medir_pisca_fx.gd
var INICIO: int = int(OS.get_environment("INICIO")) if OS.has_environment("INICIO") else 150
var QUADROS: int = int(OS.get_environment("QUADROS")) if OS.has_environment("QUADROS") else 150
var LIMIAR: float = float(OS.get_environment("LIMIAR")) if OS.has_environment("LIMIAR") else 0.08
var SAIDA := OS.get_environment("SAIDA")
var main
var c
var ia
var q := 0
var n := 0
var eu := {}
var lum: Array = []              # PackedFloat32Array por quadro


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _physics_process(dt: float) -> bool:
	q += 1
	if main.car == null or main.corrida == null:
		return q > 300
	c = main.corrida
	if q == 20:
		seed(7)
		c.comecar()
		c.comecar()
		c.comecar()
		c.t_conta = 0.0
		ia = c.ia
		eu = {"nome": "Você", "car": main.car, "r": ia.jogador, "desvio": 0.0, "skill": 1.0, "preso": 0.0,
			"re": 0.0, "capotado": 0.0, "repostos": 0, "res": 0}
	if q > 20 and c.estado == c.CORRENDO:
		eu.r = ia.jogador
		eu.vigia = ia.vigia_jogador
		ia._dirigir(eu, main.car, dt)
		n += 1
	return false


func _process(_dt: float) -> bool:
	if n < INICIO:
		return false
	if lum.is_empty():
		for l in main.find_children("*", "CanvasLayer", true, false):
			(l as CanvasLayer).visible = false       # sem HUD na imagem
		var nuv := 0
		for car in [main.car] + ia.rivais.map(func(y): return y.car):
			if car.poeira:
				nuv += car.poeira.vivas()
		print("medir_pisca_fx: começa no passo %d com %d nuvens vivas" % [n, nuv])
	var img: Image = root.get_viewport().get_texture().get_image()
	if SAIDA != "":
		img.save_png("%s/q%04d.png" % [SAIDA, lum.size()])
	var l := PackedFloat32Array()
	l.resize(img.get_width() * img.get_height())
	var k := 0
	for y in img.get_height():
		for x in img.get_width():
			l[k] = img.get_pixel(x, y).get_luminance()
			k += 1
	lum.append(l)
	if lum.size() >= QUADROS:
		var pisca := 0
		for i in range(1, lum.size() - 1):
			var a: PackedFloat32Array = lum[i - 1]
			var b: PackedFloat32Array = lum[i]
			var d: PackedFloat32Array = lum[i + 1]
			for j in a.size():
				var d1 := b[j] - a[j]
				var d2 := d[j] - b[j]
				if absf(d1) > LIMIAR and absf(d2) > LIMIAR and d1 * d2 < 0.0:
					pisca += 1
		print("medir_pisca_fx: %d quadros, %d pixels piscando (%.3f%% por quadro), ORDEM_FX=%s" % [
			lum.size(), pisca, 100.0 * pisca / float((lum.size() - 2) * (lum[0] as PackedFloat32Array).size()),
			OS.get_environment("ORDEM_FX")])
		return true
	return false
