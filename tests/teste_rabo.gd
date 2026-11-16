extends SceneTree
## Rabo de cavalo balançando (carro/rabo.gd, a corrente do jogo 0x1886f8):
## monta a piloto feminina no carro do main e confere, passo a passo:
## - os pedaços mantêm o comprimento da PONY_TAIL_POSE e a raiz fica no pino
##   (neck + 0.09·Y - 0.08·Z)
## - parado o rabo cai pra baixo e pra trás, encostado nos ombros/costas
##   (gravidade max(8, 20 - v); o "vento" max(v, 20) vai contra o eixo Z do
##   ROOT, que no piloto sentado aponta quase pra cima: no buggy a velocidade
##   quase não mexe no rabo, igual ao jogo)
## - arrancar de 0 pra 30 m/s e virar o volante pros dois lados fazem ele
##   balançar e assentar (sem explodir)
## - os ossos do esqueleto do rabo seguem as partículas
## Uso: godot --headless --path . -s res://tests/teste_rabo.gd

var main
var q := 0
var falhas := 0


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _falha(t: String) -> void:
	print("  FALHA: " + t)
	falhas += 1


func _process(_d: float) -> bool:
	q += 1
	if q < 5:
		return false
	var car = main.car
	if not FileAccess.file_exists("res://assets/piloto/piloto_f.json"):
		print("teste_rabo: FALHA (sem assets/piloto/piloto_f.json: rode o tools/piloto.py)")
		quit()
		return true
	car.pintar_piloto({"sexo": "f"})
	var pil = car.piloto
	if pil == null or pil.rabo == null:
		print("teste_rabo: FALHA (a piloto não tem o rabo: rode o tools/piloto.py de novo)")
		quit()
		return true
	var r = pil.rabo
	var t0 := Time.get_ticks_usec()
	for i in 150:                            # 3 s parado
		r.passo(0.0, true)
	var t_passo := (Time.get_ticks_usec() - t0) / 150.0
	var parado := _angulo(r, pil)
	_confere(r, pil, "parado")
	for i in 150:                            # 3 s a 30 m/s (108 km/h)
		r.passo(30.0, true)
	var correndo := _angulo(r, pil)
	_confere(r, pil, "30 m/s")
	print("  ponta do rabo: %.0f graus da vertical parado, %.0f a 30 m/s (pra trás)" % [parado, correndo])
	if not (parado > 5.0 and parado < 80.0):
		_falha("parado o rabo devia cair pra baixo e um pouco pra trás (%.0f graus)" % parado)
	# virando o volante (STEER_LEFT mexe o pescoço): ida e volta em 1 s
	var lado := 0.0
	var pico_lado := 0.0
	for i in 100:
		pil.pose(sin(i * 0.02 * TAU))
		r.passo(20.0, true)
		var d: Vector3 = r.x[r.n - 1] - r.x[0]
		lado = d.x
		pico_lado = maxf(pico_lado, absf(lado))
	pil.pose(0.0)
	print("  virando o volante: a ponta vai até %.1f cm pro lado" % (pico_lado * 100.0))
	if pico_lado < 0.01:
		_falha("virando o volante o rabo devia balançar pro lado")
	# arranca: 0 -> 30 m/s de uma vez e vê o balanço da ponta
	for i in 150:
		r.passo(0.0, true)
	var hist: Array = []
	var pico := 0.0
	for i in 150:
		r.passo(30.0, true)
		var a := _angulo(r, pil)
		hist.append(a)
		pico = maxf(pico, a)
	var final: float = hist[-1]
	var mexeu := 0
	for i in range(1, hist.size()):
		if absf(hist[i] - hist[i - 1]) > 0.05:
			mexeu = i
	print("  arrancando: ponta vai a %.0f graus e assenta em %.0f (%.2f s balançando)" % [pico, final, mexeu * 0.02])
	if pico > 120.0 or not is_finite(final):
		_falha("balanço exagerado")
	if mexeu < 5:
		_falha("o rabo não balançou na arrancada")
	# o esqueleto do rabo na tela segue as partículas
	r.avancar(0.02, 30.0)
	var pior := 0.0
	for b in r.n:
		pior = maxf(pior, r.skel.get_bone_global_pose(b).origin.distance_to(r.x[b]))
	if pior > 1e-4:
		_falha("osso do rabo longe da partícula (%.4f m)" % pior)
	print("  passo: %.1f us (7 partículas, 4 colisores)" % t_passo)
	print("teste_rabo: %s" % ("ok" if falhas == 0 else "FALHA (%d)" % falhas))
	quit()
	return true


## ângulo (graus) do pino até a ponta em relação à vertical, no plano do
## corpo (+ = pra trás, eixo -Z do ROOT)
func _angulo(r, pil) -> float:
	var raiz: Transform3D = pil.skel.get_bone_global_pose(pil.skel.find_bone("ROOT"))
	var d: Vector3 = r.x[r.n - 1] - r.x[0]
	var tras: float = d.dot(-raiz.basis.z)
	return rad_to_deg(atan2(tras, -d.y))


func _confere(r, pil, nome: String) -> void:
	var pior := 0.0
	for i in r.n - 1:
		pior = maxf(pior, absf(r.x[i].distance_to(r.x[i + 1]) - r.resto[i]))
	if pior > 1e-4:
		_falha("%s: pedaço mudou de tamanho (%.5f m)" % [nome, pior])
	var pe: Transform3D = pil.skel.get_bone_global_pose(pil.skel.find_bone("neck"))
	var pino: Vector3 = pe.origin + pe.basis.y * r.PINO_Y + pe.basis.z * r.PINO_Z
	if r.x[0].distance_to(pino) > 1e-4:
		_falha("%s: a raiz saiu do pino (%.4f m)" % [nome, r.x[0].distance_to(pino)])
	for i in r.n:
		if not r.x[i].is_finite():
			_falha("%s: NaN na partícula %d" % [nome, i])
			return
