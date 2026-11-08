extends SceneTree
## Som do pneu (sfx_carro.gd, porta do 0x370548) contra o PS2: põe o remake
## no estado da RAM de cada save state (tests/ref_derrapagem.json, mesmo
## jeito do teste_derrapagem.gd), com as rodas no chão e o material do ponto
## de contato da RAM, roda a conta do som (sem passo de física) e compara o
## tom de cada roda com o registrador de pitch das vozes do SPU
## (tests/ref_som_pneu.json).
## Também confere o sample (Dirt/Tarmac/Screech pelo SFX do material).
## Precisa de assets/sfx (python tools/sfx_jogo.py <unpacked>).
## Uso: godot --headless --path . -s res://tests/teste_sfx.gd

const Car := preload("res://carro/car.gd")
const Main := preload("res://main.gd")
const Terrain := preload("res://pista/terrain.gd")
const SomJogo := preload("res://som/som_jogo.gd")
const PASSO := 1.0 / 50.0
const TOL := 0.02

var terrain
var car
var ref: Dictionary
var som: Dictionary
var fila := []
var falhas := 0
var avisos: Array = []
var mapa_ram: Array = []
var pior := 0.0


func _initialize() -> void:
	ref = JSON.parse_string(FileAccess.get_file_as_string("res://tests/ref_derrapagem.json"))
	som = JSON.parse_string(FileAccess.get_file_as_string("res://tests/ref_som_pneu.json"))
	terrain = Terrain.new()
	root.add_child(terrain)
	var v: Dictionary = Main.VEHICLES[0]
	car = Car.new()
	car.asset_dir = v.dir
	car.data_files = ["res://data/vehicles/buggy_base.xml", v.data]
	car.points_file = v.points
	car.vehicle_id = v.id
	car.tune_override = v.get("tune", {})
	car.terrain = terrain
	car.suspension = false
	root.add_child(car)
	car.test_input = {"thr": 0.0, "brk": 0.0, "steer": 0.0}
	fila = som.estados.keys()


func _physics_process(_dt: float) -> bool:
	if not car.is_inside_tree():
		return false
	car.set_physics_process(false)
	if car.sfx == null:
		print("teste_sfx: FALHA (sem assets/sfx: python tools/sfx_jogo.py <unpacked>)")
		return true
	if fila.is_empty():
		for a in mapa_ram:
			print("material: " + a)
		for a in avisos:
			print("som atrás do chão: " + a)
		print("teste_sfx: %s (pior diferença de tom %.4f, tolerância %.2f)" % ["ok" if falhas == 0 else "FALHA", pior, TOL])
		return true
	var nome: String = fila.pop_front()
	var r: Dictionary = som.estados[nome]
	var e: Dictionary = ref.estados[nome]
	_por_no_estado(e)
	for i in 4:
		var c: Array = e.rodas[i].contato
		var w: Dictionary = car.wheels[car.jit_order[i]]
		w.hit = absf(float(c[0])) + absf(float(c[2])) > 0.0
		if w.hit:
			var p: Vector3 = Terrain.do_jogo(Vector3(c[0], c[1], c[2]))
			w.mat = terrain.material_at(p.x, p.z)
			# o som pode estar atrás do chão: a roda acabou de trocar de
			# material e as vozes do som de antes ainda descem pelo release
			# (no 110 a frente saiu do asfalto 0.06 s antes; o asfalto leva 0.34 s
			# pra apagar e o loop do cascalho só entra 60 ticks = 0.25 s depois).
			# Aqui o teste é do tom, então a roda vai pro material que o jogo tocava
			if terrain.sfx(w.mat) != r.chao:
				var t_troca := _desde(c, e.vel, r.chao)
				var rel := _release(r.chao)
				avisos.append("%s roda %d: mapa %s, PS2 ainda tocava %s: saiu dele %.2f s antes, o release dura %.2f s (%s)" % [
					nome, i, terrain.sfx(w.mat), r.chao, t_troca, rel, "explicado" if t_troca <= rel else "SEM EXPLICAÇÃO"])
				if t_troca > rel:
					falhas += 1
				w.mat = _material(r.chao)
	# material da FL na RAM (veículo+0xa88[0]) x mapa no ponto de contato dela
	if e.has("roda_suja") and e.roda_suja.has("mat"):
		var c0: Array = e.rodas[0].contato
		var p0 := Terrain.do_jogo(Vector3(c0[0], c0[1], c0[2]))
		var no_mapa: int = terrain.material_at(p0.x, p0.z)
		var ram := int(e.roda_suja.mat)
		if no_mapa != ram:
			# na borda de uma célula o material da RAM é do passo seguinte
			var borda := false
			for dx in [-0.05, 0.0, 0.05]:
				for dz in [-0.05, 0.0, 0.05]:
					borda = borda or terrain.material_at(p0.x + dx, p0.z + dz) == ram
			mapa_ram.append("%s FL: RAM %d, mapa %d (%s)" % [nome, ram, no_mapa, "borda de célula" if borda else "DIFERENTE"])
			if not borda:
				falhas += 1
		else:
			mapa_ram.append("%s FL: RAM %d = mapa" % [nome, ram])
	var bas: Basis = car.global_transform.basis
	car.sfx.passo(PASSO, car.linear_velocity.dot(bas.x), car.linear_velocity.dot(bas.z))
	var st: Array = car.sfx.estado()      # [nome, volume, tom] de FL, RL, FL secundário
	var linha := "%-6s chão %-6s" % [nome, r.chao]
	var rodas := ["FL", "RL", "Screech"]
	for k in 3:
		var chave: String = rodas[k]
		if not r.has(chave):
			continue
		var amostra: String = st[k][0]
		var esperado: String = r.chao if k < 2 else "Screech"
		var d: float = absf(float(st[k][2]) - float(r[chave]))
		pior = maxf(pior, d)
		var ruim := d > TOL or amostra != esperado
		if ruim:
			falhas += 1
		linha += "  %s %s tom %.4f (PS2 %.4f) vol %.3f%s" % [chave, amostra, st[k][2], r[chave], st[k][1], " FALHA" if ruim else ""]
	print(linha)
	return false


## primeiro material da pista com esse som
## quanto tempo atrás (s) o contato saiu do chão de som "nome", andando pra
## trás pela velocidade (frame do jogo)
func _desde(c: Array, vel: Array, nome: String) -> float:
	var p := Vector3(c[0], c[1], c[2])
	var v := Vector3(vel[0], vel[1], vel[2])
	for k in 200:
		var t := k * 0.005
		var q := Terrain.do_jogo(p - v * t)
		if terrain.sfx(terrain.material_at(q.x, q.z)) == nome:
			return t
	return INF


## tempo do release (key-off até zero) do loop do chão "nome" (ADSR do 1º tom)
func _release(nome: String) -> float:
	var mat: Dictionary = car.sfx.materiais.get(nome, {})
	var pat: Dictionary = car.sfx.patches.get(mat.get("SurfacePatch", ""), {})
	if not pat.has("looping"):
		return 0.0
	var b: Dictionary = SomJogo.banco().bancos.get("Surface", {})
	var som: Dictionary = b.get(pat.looping.sample, {})
	var tons: Array = som.get("tons", [])
	if tons.is_empty() or not tons[0].has("adsr"):
		return 0.0
	var v := {"a1": int(tons[0].adsr[0]), "a2": int(tons[0].adsr[1]), "fase": 3, "nivel": 32767.0}
	var t := 0.0
	while v.fase < 4 and t < 5.0:
		SomJogo._env_anda(v, 48.0)
		t += 0.001
	return t


func _material(nome: String) -> int:
	for m in terrain.materials.size():
		if terrain.sfx(m) == nome:
			return m
	return -1


func _d(a: Array) -> Vector3:
	return Terrain.dir_do_jogo(Vector3(a[0], a[1], a[2]))


## como no teste_derrapagem.gd: pose, velocidade, comandos e rodas da RAM
## (aqui o curso é o da RAM, sem o ajuste pro passo de física)
func _por_no_estado(e: Dictionary) -> void:
	var bas := Basis(-_d(e.direita), _d(e.cima), _d(e.frente)).orthonormalized()
	var pos: Vector3 = Terrain.do_jogo(Vector3(e.origem[0], e.origem[1], e.origem[2])) - bas * car.corpo(Vector3.ZERO)
	car.global_transform = Transform3D(bas, pos)
	car.reset_physics_interpolation()
	car.pos_ant = pos
	car.linear_velocity = _d(e.vel)
	car.angular_velocity = -_d(e.w)
	var g := func(m: int) -> int: return -1 if m == 0 else (0 if m == 6 else m)
	car.gear = g.call(int(e.marcha))
	car.shift_to = g.call(int(e.marcha_alvo))
	car.clutch = e.embreagem
	car.cstate = int(e.estado_emb)
	car.shift_timer = e.troca_t
	car.shift_flag = int(e.troca) != 0
	car.slip_sign = e.emb_sinal
	car.rpm = e.rpm
	car.lim_k = e.limitador
	car.eng_torque = e.torque * 1000.0
	car.air_time = e.ar
	car.emb_in = e.mao[1]
	car.steer = -float(e.direcao[1])
	car.throttle = e.acelerador[1]
	car.brake_in = e.freio[1]
	car.test_input = {"steer": -float(e.direcao[0]), "thr": e.acelerador[0], "brk": e.freio[0], "hb": float(e.mao[0]) > 0.5}
	for i in 4:
		var r: Dictionary = e.rodas[i]
		var w: Dictionary = car.wheels[car.jit_order[i]]
		w.x = r.curso
		w.v = r.curso_v
		w.omega = r.giro
		w.slip = r.patinada
		w.sr = r.medida
		w.abs = int(r.abs) != 0
		w.grip = r.grip
