extends SceneTree
## ATV (etapa 1a, nov/2026): o ATV_10 (Samurai 650, o do save state
## atv_cl01_largada.p2s) monta e anda no RX01 com a física de hoje.
## Confere:
##  - câmbio = o da RAM do save state (23.1 / 11.5 / 7.7 / 5.8 / 4.6, ré -15);
##    final de fábrica 1.12 = 1.02 -> 1.22 a 0.5 (FinalDriveRatio_Standard do
##    upgrades.xml, classe ATV). Na RAM os 4 rivais (ATV.xml base, 0.96 ->
##    1.20) têm 1.08 = o mesmo 0.5; o 1.02 do jogador é do perfil do Matheus;
##  - peças do ATVCompMap_Generic: carenagem, escape e nerfbar presos na
##    carroceria (a carenagem com a pintura), balanças, amortecedores, eixo
##    de trás, guidão e coroa; só os 2 cantos da frente (a roda de trás é a do
##    rally) e "rally" falso (a da frente vai pela balança, 0x220f08);
##  - guidão (0x21dff8): o HANDLEBAR fica parado e o giro é o esterço;
##  - amortecedor (0x21e328 / 0x21e5b0): gira pro lado do SHOCKS_BOTTOM
##    levado pela balança (o ângulo é o acos 3D aplicado só em z, então não
##    alinha exato: é a conta do jogo);
##  - coroa (0x21ec78): gira com a roda RL em volta do AXLE_ANCHOR;
##  - visual em C++ = GDScript;
##  - acelerando 6 s reto: anda, sobe marcha, as 4 rodas no chão quase o
##    tempo todo.
## E os 10 ATVs montam (peças, pintura na carenagem; o Wildcat, ATVCompMap_A,
## com os para-lamas na classe FrontLeftBrake e a pintura), visual em C++ =
## GDScript em cada um, e o câmbio dos 7 rivais do mesmo save state: 4 com o
## ATV.xml base (ATV_01 e 03: 23.1 / 13.2 / 9.2 / 7.1 / 5.8) e 3 com 28.8 /
## 16.5 / 11.5 / 8.9 / 7.2 (ATV_02 e 04), todos com final 1.08.
## Uso: godot --headless --path . -s res://tests/teste_atv.gd

const Car := preload("res://carro/car.gd")
const Main := preload("res://main.gd")
const Terrain := preload("res://pista/terrain.gd")

const MARCHAS_RAM := [23.1, 11.5, 7.7, 5.8, 4.6]
# câmbio efetivo dos rivais na RAM do atv_cl01_largada (marchas 1..5, final)
const RIVAIS_RAM := {"ATV_01": [[23.1, 13.2, 9.2, 7.1, 5.8], 1.08], "ATV_03": [[23.1, 13.2, 9.2, 7.1, 5.8], 1.08],
	"ATV_02": [[28.8, 16.5, 11.5, 8.9, 7.2], 1.08], "ATV_04": [[28.8, 16.5, 11.5, 8.9, 7.2], 1.08]}
const FINAL_FABRICA := 1.12
const RE_RAM := -15.0

var terrain
var car
var t := 0.0
var falhas := 0
var maxd := 0.0
var quadros_cpp := 0
var no_chao := 0
var passos := 0
var marcha_max := 0
var erro_guidao := 0.0
var erro_amort := 0.0
var erro_coroa := 0.0


func _initialize() -> void:
	terrain = Terrain.new()
	root.add_child(terrain)
	var v := {}
	for x in Main.frota_jogo():
		if x.id == "ATV_10":
			v = x
	if v.is_empty():
		_falha("ATV_10 fora do main.frota_jogo()")
		return
	if not FileAccess.file_exists(String(v.dir).path_join("pecas.json")):
		print("teste_atv: FALHA (sem %s/pecas.json: rode o tools/gerar_buggies.py --classe atv)" % v.dir)
		quit()
		return
	car = Car.new()
	Main.configurar(car, v)
	car.terrain = terrain
	root.add_child(car)
	car.test_input = {"thr": 0.0, "brk": 0.0, "steer": 0.0}


## os 10 ATVs: monta cada um, confere e solta (antes de qualquer passo)
func _frota() -> void:
	for v in Main.ATVS:
		if not FileAccess.file_exists(String(v.dir).path_join("pecas.json")):
			_falha("sem %s/pecas.json (gerar_buggies --classe atv)" % v.dir)
			continue
		var c = Car.new()
		Main.configurar(c, v)
		c.terrain = terrain
		root.add_child(c)
		var nomes := []
		var pinta := 0
		for n in c.model_root.get_children():
			nomes.append(String(n.name))
			if n.name == "Fairing" and n is MeshInstance3D:
				for i in n.mesh.get_surface_count():
					if c._mats_pintura.has(n.get_surface_override_material(i)):
						pinta += 1
		var sv = c.susp_vis
		var faltam := []
		for k in ["Fairing", "Exhaust", "Nerfbar"]:
			if not k in nomes:
				faltam.append(k)
		for k in ["LeftFrame", "RightFrame", "RearAxle", "LeftShocks", "RightShocks", "Handlebar", "Sprocket"]:
			if not sv.truck.has(k):
				faltam.append(k)
		if pinta == 0:
			faltam.append("pintura da carenagem")
		var lamas := ""
		if v.id == "ATV_08":
			for k in ["FrontLeftBrake", "FrontRightBrake"]:
				var mis: Array = sv.truck.get(k, {}).get("mis", [])
				var pl := 0
				for mi in mis:
					for i in mi.mesh.get_surface_count():
						if c._mats_pintura.has(mi.get_surface_override_material(i)):
							pl += 1
				if mis.size() != 1 or pl == 0:
					faltam.append("%s (para-lama: %d peças, %d com pintura)" % [k, mis.size(), pl])
			lamas = " + para-lamas"
		if sv.rally or sv.corners.size() != 2:
			faltam.append("rally %s / %d cantos" % [sv.rally, sv.corners.size()])
		# C++ x GDScript parado, com esterço
		var d := 0.0
		if sv._cpp:
			sv._cpp.update(0.3)
			var a := {}
			for k in sv.truck:
				var tk: Dictionary = sv.truck[k]
				for mi in tk.get("mis", [tk.get("mi")]):
					a[mi] = mi.transform
			var cp = sv._cpp
			sv._cpp = null
			sv.update(0.3)
			sv._cpp = cp
			for mi in a:
				var b: Transform3D = mi.transform
				d = maxf(d, (a[mi].origin - b.origin).length() + (a[mi].basis.x - b.basis.x).length()
					+ (a[mi].basis.y - b.basis.y).length() + (a[mi].basis.z - b.basis.z).length())
		if d > 1e-5:
			faltam.append("C++ diferente do GDScript (%.6f)" % d)
		var g := Array(c.gears).slice(1)
		var cambio := "%s final %.2f" % [str(g.map(func(x): return snappedf(x, 0.01))), c.P.final]
		if RIVAIS_RAM.has(v.id):
			var r: Array = RIVAIS_RAM[v.id]
			for i in 5:
				if absf(g[i] - r[0][i]) > 1e-3:
					faltam.append("marcha %d %.2f (RAM %.1f)" % [i + 1, g[i], r[0][i]])
			if absf(c.P.final - r[1]) > 1e-3:
				faltam.append("final %.3f (RAM %.2f)" % [c.P.final, r[1]])
			cambio += " = RAM"
		print("  %-12s %s  %.0f kg  %s%s %s" % [v.name, v.id, c.mass, cambio, lamas,
			"ok" if faltam.is_empty() else "FALHA: " + ", ".join(faltam)])
		if not faltam.is_empty():
			falhas += 1
		root.remove_child(c)
		c.free()


func _falha(msg: String) -> void:
	falhas += 1
	print("FALHA: " + msg)


func _montagem() -> void:
	for g in range(1, 6):
		if absf(car.gears[g] - MARCHAS_RAM[g - 1]) > 1e-4:
			_falha("marcha %d = %.3f (RAM %.1f)" % [g, car.gears[g], MARCHAS_RAM[g - 1]])
	if absf(car.P.final - FINAL_FABRICA) > 1e-4 or absf(car.P.gear_r - RE_RAM) > 1e-4:
		_falha("final %.3f / ré %.1f (fábrica %.2f / RAM %.0f)" % [car.P.final, car.P.gear_r, FINAL_FABRICA, RE_RAM])
	print("  câmbio %s final %.2f ré %.0f, massa %.0f kg" % [str(Array(car.gears).slice(1)), car.P.final, car.P.gear_r, car.mass])
	var nomes := []
	for n in car.model_root.get_children():
		nomes.append(String(n.name))
	for k in ["Fairing", "Exhaust", "Nerfbar"]:
		if not k in nomes:
			_falha("sem a peça %s na carroceria" % k)
	var pinta := false
	for n in car.model_root.get_children():
		if n.name == "Fairing" and n is MeshInstance3D:
			for i in n.mesh.get_surface_count():
				if car._mats_pintura.has(n.get_surface_override_material(i)):
					pinta = true
	if not pinta:
		_falha("carenagem sem a pintura (white)")
	var sv = car.susp_vis
	for k in ["LeftFrame", "RightFrame", "RearAxle", "LeftShocks", "RightShocks", "Handlebar", "Sprocket"]:
		if not sv.truck.has(k):
			_falha("sem %s no visual" % k)
	if sv.rally or sv.corners.size() != 2:
		_falha("rally %s, %d cantos (esperado falso e 2: só a frente)" % [sv.rally, sv.corners.size()])
	print("  peças: %s + %s, cantos %d" % [str(nomes), str(sv.truck.keys()), sv.corners.size()])


## guidão, amortecedores e coroa pela geometria (independe do C++)
func _geometria(steer: float) -> void:
	var sv = car.susp_vis
	var x := {}
	for w in car.wheels:
		x[("F" if w.front else "R") + ("L" if w.left else "R")] = clampf(w.x, w.min, w.max) + w.get("jit", 0.0)
	var p: Dictionary = sv.pose_truck(x, steer)
	var h: Dictionary = sv.truck.Handlebar
	var gx: Transform3D = p.Handlebar
	erro_guidao = maxf(erro_guidao, (gx * h.pivot - h.pivot).length())
	# o eixo de giro é o do ponto e o ângulo é o esterço
	var q := gx.basis.get_rotation_quaternion()
	var ang := q.get_angle() * signf(q.get_axis().dot(h.eixo))
	if absf(steer) > 0.01:
		erro_guidao = maxf(erro_guidao, absf(ang - steer))
	for lado in ["Left", "Right"]:
		var s: Dictionary = sv.truck[lado + "Shocks"]
		var b2: Vector3 = p[lado + "Frame"] * s.bottom
		var b1: Vector3 = p[lado + "Shocks"] * s.bottom
		# ângulo no plano xy até o alvo: depois do giro tem que ser menor
		var antes := absf(Vector2(s.bottom.x - s.top.x, s.bottom.y - s.top.y).angle_to(Vector2(b2.x - s.top.x, b2.y - s.top.y)))
		var depois := absf(Vector2(b1.x - s.top.x, b1.y - s.top.y).angle_to(Vector2(b2.x - s.top.x, b2.y - s.top.y)))
		if antes > 0.01:
			erro_amort = maxf(erro_amort, maxf(0.0, depois - 0.5 * antes))
	var c: Dictionary = sv.truck.Sprocket
	var cx: Transform3D = p.Sprocket
	# a coroa sem o eixo: gira em x em volta do AXLE_ANCHOR pelo giro da RL
	var so: Transform3D = (p.RearAxle as Transform3D).affine_inverse() * cx
	erro_coroa = maxf(erro_coroa, (so * c.ancora - c.ancora).length())
	var r := Basis(Vector3.RIGHT, c.spin.rotation.x)
	erro_coroa = maxf(erro_coroa, (so.basis.x - r.x).length() + (so.basis.y - r.y).length() + (so.basis.z - r.z).length())


func _physics_process(dt: float) -> bool:
	if car == null or not car.is_inside_tree():
		return false
	if t == 0.0:
		_frota()
		var p: Vector2 = Main.SPAWN_XZ
		car.reset_to(Vector3(p.x, terrain.height_at(p.x, p.y) + 0.8, p.y), deg_to_rad(Main.SPAWN_YAW))
		_montagem()
	t += dt
	car.test_input.thr = 1.0 if t > 0.5 else 0.0
	# reto: virando, o ATV levanta a roda de dentro (o esterço das contas do
	# visual vai direto no pose_truck)
	if t > 1.0:
		passos += 1
		if car.grounded == 4:
			no_chao += 1
		marcha_max = maxi(marcha_max, car.gear)
		var steer := 0.5 * sin(t * 1.7)
		_geometria(steer)
		# C++ x GDScript (o mesmo quadro, o mesmo esterço)
		var sv = car.susp_vis
		if sv._cpp:
			sv._cpp.update(steer)
			var a := {}
			for k in sv.truck:
				var tk: Dictionary = sv.truck[k]
				for mi in tk.get("mis", [tk.get("mi")]):
					a[mi] = mi.transform
			var c = sv._cpp
			sv._cpp = null
			sv.update(steer)
			sv._cpp = c
			for mi in a:
				var d: Transform3D = mi.transform
				maxd = maxf(maxd, (a[mi].origin - d.origin).length() + (a[mi].basis.x - d.basis.x).length()
					+ (a[mi].basis.y - d.basis.y).length() + (a[mi].basis.z - d.basis.z).length())
			quadros_cpp += 1
	if t < 7.0:
		return false
	var v: float = car.linear_velocity.length() * 3.6
	var chao := float(no_chao) / maxf(passos, 1)
	print("  7 s: %.0f km/h, marcha até %d, 4 rodas no chão %.0f%% dos passos" % [v, marcha_max, chao * 100.0])
	print("  guidão (pivô parado, ângulo = esterço): erro %.6f" % erro_guidao)
	print("  amortecedor (gira pro SHOCKS_BOTTOM na balança): erro %.6f" % erro_amort)
	print("  coroa (gira com a RL em volta do AXLE_ANCHOR): erro %.6f" % erro_coroa)
	print("  C++ x GDScript: %d quadros, maior diferença %.6f" % [quadros_cpp, maxd])
	if v < 50.0 or marcha_max < 3:
		_falha("não andou (%.0f km/h, marcha %d)" % [v, marcha_max])
	if chao < 0.8:
		_falha("rodas fora do chão demais (%.0f%%)" % (chao * 100.0))
	if erro_guidao > 1e-4 or erro_amort > 1e-4 or erro_coroa > 1e-4:
		_falha("guidão / amortecedor / coroa fora da conta do exe")
	if quadros_cpp == 0:
		print("  (sem o C++: só o GDScript)")
	elif maxd > 1e-5:
		_falha("visual em C++ diferente do GDScript")
	print("teste_atv: %s" % ("ok" if falhas == 0 else "FALHA (%d)" % falhas))
	return true
