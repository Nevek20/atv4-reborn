extends SceneTree
## Órbita da câmera de corrida (camera_orbita.gd, melhoria nossa: o analógico
## direito do Forza). Carro numa reta em subida (pra a câmera da frente ter que
## desviar do chão) a 60 km/h, câmera FollowOrbitNear do Renegade, quadros de
## 1/60 s. Fases: solto (= câmera do jogo), analógico pra direita (olha pra
## direita: câmera do lado esquerdo), 3 voltas girando o analógico, solta (volta
## pelo caminho curto), meia deflexão, pra baixo (olha pra trás), mouse.
## Uso: godot --headless --path . -s res://tests/teste_camera_orbita.gd

const GameCamera := preload("res://camera/game_camera.gd")
const CameraOrbita := preload("res://camera/camera_orbita.gd")
const CAM_XML := "res://data/cameras.xml"
const RAMPA := 0.3                       # subida do chão (m por m)


class Rampa:
	func height_at(_x: float, z: float) -> float:
		return z * RAMPA


var cam: Camera3D
var ref: Camera3D                        # a câmera do jogo sem órbita


func _initialize() -> void:
	cam = Camera3D.new()
	root.add_child(cam)
	ref = Camera3D.new()
	root.add_child(ref)


func _estado(t: float, v: float) -> Dictionary:
	var z := v * t
	var dirv := Vector3(0, RAMPA, 1).normalized()
	var b := Basis(Vector3.RIGHT, -atan(RAMPA))
	return {"tp": Vector3(0, z * RAMPA + 0.8, z), "basis": b, "vel": dirv * v * sqrt(1.0 + RAMPA * RAMPA),
		"v_f": v, "speed": v, "chao": 0, "batida": 0.0, "air_time": 0.0, "grounded": 4,
		"ground_n": Vector3(0, 1, -RAMPA).normalized()}


## ângulo da câmera em volta do carro: 0 = atrás, + = do lado esquerdo do
## carro (olhando pra direita)
static func _azimute(c: Vector3, s: Dictionary) -> float:
	# no plano horizontal (a órbita gira em volta do eixo vertical do mundo)
	var o: Vector3 = c - s.tp
	var fz: Vector3 = Vector3(s.basis.z.x, 0, s.basis.z.z).normalized()
	var fx: Vector3 = Vector3(s.basis.x.x, 0, s.basis.x.z).normalized()   # esquerda do carro
	return atan2(o.dot(fx), -o.dot(fz))


func _process(_d: float) -> bool:
	if not cam.is_inside_tree():
		return false
	var falhas := 0
	var chao := Rampa.new()
	var g = GameCamera.load_set(CAM_XML, "BuggyCamSet_10", "FollowOrbitNear")
	var o = CameraOrbita.new()
	var v := 60.0 / 3.6
	var t := 0.0
	var s := _estado(t, v)
	g.reset(s, chao)
	var dt := 1.0 / 60.0
	var dif_solto := 0.0
	var az_ant := 0.0
	var volta := 0.0                       # quanto girou desenrolado
	var pulo := 0.0                        # maior giro de um quadro pro outro
	var volta_mono := true
	var abaixo := 0.0                      # quanto ficou abaixo do chão + 1.45 (girada)
	var mira := 0.0                        # carro fora do meio da tela (graus)
	var notas := {}
	var fases := [[2.0, "solto"], [3.0, "direita"], [6.0, "voltas"], [6.5, "alivia"], [8.5, "solta"],
		[9.5, "meia"], [11.0, "tras"], [13.0, "solta2"], [14.0, "mouse"], [16.0, "solta_mouse"]]
	var falhas_n := [0]
	var mira_ref := 0.0
	var alivia := 0.0                      # aliviando depois das voltas: quanto girou
	var fi := 0
	while fi < fases.size():
		t += dt
		var fase: String = fases[fi][1]
		match fase:
			"solto", "solta", "solta2", "solta_mouse":
				o.analogico_teste = Vector2.ZERO
			"alivia":                       # depois das 3 voltas, alivia pra meia deflexão
				o.analogico_teste = Vector2(0.5, 0)
			"direita":
				o.analogico_teste = Vector2(1, 0)
			"voltas":                       # 1 volta por segundo, começando pela direita
				var a := PI * 0.5 + TAU * (t - 3.0)
				o.analogico_teste = Vector2(sin(a), -cos(a))
			"meia":
				o.analogico_teste = Vector2(0.5, 0)
			"tras":
				o.analogico_teste = Vector2(0.001, 1)
			"mouse":
				o.analogico_teste = Vector2.ZERO
				if not notas.has("mouse_ini"):
					notas["mouse_ini"] = true
					o.mouse_botao(true)
					o.mouse_arrasto(Vector2(150, 0))     # 0.9 rad pra direita
					o.mouse_arrasto(Vector2(0, 50))      # 0.3 rad pra cima
		if fase == "solta_mouse" and not notas.has("mouse_fim"):
			notas["mouse_fim"] = true
			o.mouse_botao(false)
		s = _estado(t, v)
		g.update(dt, s, chao)
		g.apply(cam, s.tp)
		g.apply(ref, s.tp)
		o.passo(dt)
		o.aplicar(cam, s.tp, chao)
		var az := _azimute(cam.global_position, s)
		var da := wrapf(az - az_ant, -PI, PI)
		az_ant = az
		volta += da
		if fase == "voltas" and t > 3.3:
			pulo = maxf(pulo, absf(da))
		if fase == "alivia":
			alivia += absf(da)
		var para_carro: Vector3 = (s.tp - cam.global_position).normalized()
		var frente: Vector3 = -cam.global_transform.basis.z
		var para_ref: Vector3 = (s.tp - ref.global_position).normalized()
		var a_ref := rad_to_deg((-ref.global_transform.basis.z).angle_to(para_ref))
		mira_ref = maxf(mira_ref, a_ref)
		mira = maxf(mira, rad_to_deg(frente.angle_to(para_carro)) - a_ref)
		if absf(o.giro) > 0.3:
			var p := cam.global_position
			abaixo = maxf(abaixo, chao.height_at(p.x, p.z) + GameCamera.GROUND_CLEAR - p.y)
		if fase == "solto":
			dif_solto = maxf(dif_solto, cam.global_transform.origin.distance_to(ref.global_transform.origin)
				+ cam.global_transform.basis.z.distance_to(ref.global_transform.basis.z))
		if fase == "solta" and t > 6.2:
			# volta pelo caminho curto: o ângulo até "atrás" só diminui
			if notas.has("solta_az") and absf(wrapf(az, -PI, PI)) > notas["solta_az"] + 1e-3:
				volta_mono = false
			notas["solta_az"] = absf(wrapf(az, -PI, PI))
		if t >= fases[fi][0]:
			notas[fase] = {"az": rad_to_deg(az), "giro": rad_to_deg(o.giro), "alto": cam.global_position.y - ref.global_position.y,
				"frente": (cam.global_position - s.tp).dot(s.basis.z), "dist": cam.global_position.distance_to(ref.global_position)}
			if fase == "voltas":
				notas["voltas_n"] = volta / TAU
			fi += 1
	var checa := func(ok: bool, txt: String) -> void:
		print(("ok      " if ok else "FALHOU  ") + txt)
		if not ok:
			falhas_n[0] += 1
	checa.call(dif_solto < 1e-5, "solto = câmera do jogo (diferença %.6f)" % dif_solto)
	checa.call(absf(notas.direita.az - 90.0) < 3.0, "analógico pra direita: câmera a %.1f° (esquerda do carro, olhando pra direita; 90)" % notas.direita.az)
	checa.call(absf(notas.voltas_n + 3.0) < 0.35 or absf(notas.voltas_n - 3.0) < 0.35,
		"3 voltas no analógico: a câmera deu %.2f voltas no carro" % absf(notas.voltas_n))
	checa.call(pulo < deg_to_rad(12.0), "maior giro de um quadro pro outro %.1f° (girando 1 volta/s)" % rad_to_deg(pulo))
	checa.call(alivia < PI, "depois das voltas, meia deflexão: girou %.0f° (sem desenrolar as voltas)" % rad_to_deg(alivia))
	checa.call(volta_mono, "soltou: volta pelo caminho curto")
	checa.call(notas.solta.giro == 0.0 and notas.solta.dist < 1e-4,
		"2 s depois de soltar: giro %.2f°, %.1f cm da câmera do jogo" % [notas.solta.giro, notas.solta.dist * 100.0])
	checa.call(absf(notas.meia.az - 45.0) < 4.0, "meia deflexão pra direita: %.1f° (45)" % notas.meia.az)
	checa.call(absf(absf(notas.tras.az) - 180.0) < 4.0 and notas.tras.frente > 2.0,
		"analógico pra baixo: %.1f°, câmera %.1f m na frente do carro" % [notas.tras.az, notas.tras.frente])
	checa.call(absf(notas.mouse.az - 51.6) < 3.0 and notas.mouse.alto > 0.5,
		"mouse 150 px pra direita e 50 pra baixo: %.1f° (51.6), %.2f m mais alta" % [notas.mouse.az, notas.mouse.alto])
	checa.call(notas.solta_mouse.dist < 0.02, "soltou o mouse: %.1f cm da câmera do jogo" % (notas.solta_mouse.dist * 100.0))
	checa.call(abaixo < 0.01, "girada nunca abaixo do chão + 1.45 m (pior %.2f m)" % abaixo)
	checa.call(mira < 6.0, "carro no mesmo lugar da tela que na câmera do jogo (pior %.1f° a mais; a do jogo até %.1f° do meio)" % [mira, mira_ref])
	falhas = falhas_n[0]
	print("teste_camera_orbita: %s" % ("ok" if falhas == 0 else "%d falhas" % falhas))
	quit(1 if falhas else 0)
	return true
