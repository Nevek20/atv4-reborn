extends SceneTree
## Derrapagem do Renegade contra save states PAL (tests/ref_derrapagem.json,
## tools/ler_savestate.py --json). Põe o remake no estado exato da RAM (pose,
## velocidade, giro, câmbio, rodas, comandos) e:
##  1. roda 1 passo e compara a força de cada roda (corpo+0x5c0: lateral e
##     pra frente) com a do jogo;
##  2. do drr_3 roda até o relógio do drr_2 (mesma derrapagem, volante todo e
##     acelerador no fundo) e compara velocidade, rumo, derrapagem e giro, e
##     quanto o carro sujou (0x223e68, objeto veículo+0xa80 +0xc0) e a lama
##     das rodas (0x2242d0, +0x10..+0x4c).
## Uso: godot --headless --path . -s res://tests/teste_derrapagem.gd [-- curva]
##      (com "curva" imprime a derrapagem passo a passo)

const Car := preload("res://carro/car.gd")
const Main := preload("res://main.gd")
const Terrain := preload("res://pista/terrain.gd")
const PASSO := 1.0 / 50.0

var terrain
var car
var ref: Dictionary
var fila := []          # estados pra conferir a força (1 passo cada)
var fase := ""
var n := 0
var alvo := 0
var e0: Dictionary
var imprime := false
var ok_fim := false
var pior_forca := 0.0
var seq := []


func _initialize() -> void:
	ref = JSON.parse_string(FileAccess.get_file_as_string("res://tests/ref_derrapagem.json"))
	imprime = "curva" in OS.get_cmdline_user_args()
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
	fila = ref.estados.keys()


func _physics_process(_dt: float) -> bool:
	if not car.is_inside_tree():
		return false
	car.set_physics_process(false)    # o _ready do carro liga de novo; aqui fica desligado
	# o passo do carro é chamado daqui, logo depois de pôr o estado (o Godot
	# integra depois de todos os _physics_process)
	if not fila.is_empty():
		e0 = ref.estados[fila.pop_front()]
		_por_no_estado(e0)
		car._physics_process(PASSO)
		_conferir_forca(e0)
		return false
	if fase == "":
		e0 = ref.estados["drr_3"]
		_por_no_estado(e0)
		car.sujeira_nivel = e0.sujeira
		var rs: Dictionary = e0.roda_suja
		car.roda_de = _cor(rs.de)
		car.roda_para = _cor(rs.para)
		car.roda_cor = _cor(rs.cor)
		car.roda_mat = int(rs.mat)
		car.roda_t = rs.t
		car.roda_taxa = rs.taxa
		car.roda_taxa_alvo = rs.taxa_alvo
		alvo = roundi((ref.estados["drr_2"].relogio - e0.relogio) / PASSO)
		n = 0
		fase = "sim"
		print("\n== drr_3 -> drr_2: %d passos (%.2f s), volante e acelerador como na RAM" % [alvo, alvo * PASSO])
	if fase == "emb":
		_clutch_turn()
		return false
	if n >= alvo:
		_comparar_fim(ref.estados["drr_2"])
		fase = "emb"
		n = 0
		return false
	if imprime and n % 5 == 0 and n > 0:
		var s := _medir()
		print("  %.2f s  %5.1f km/h  derrapagem %6.1f°  giro %6.1f°/s  marcha %s" % [n * PASSO, s.kmh, s.beta, s.giro, car.gear_label()])
	car._physics_process(PASSO)
	n += 1
	return false


func _cor(a: Array) -> Color:
	return Color(a[0], a[1], a[2], a[3])


func _txt(c: Color) -> String:
	return "(%.3f, %.3f, %.3f, %.3f)" % [c.r, c.g, c.b, c.a]


## direção do mundo do jogo -> remake (mesma transposição do Terrain.do_jogo)
func _d(a: Array) -> Vector3:
	return Terrain.dir_do_jogo(Vector3(a[0], a[1], a[2]))


func _por_no_estado(e: Dictionary) -> void:
	# frame do corpo do remake: +X = esquerda do jogo (espelho), então a
	# coluna X é o eixo da direita do jogo com o sinal trocado
	var bas := Basis(-_d(e.direita), _d(e.cima), _d(e.frente)).orthonormalized()
	var pos: Vector3 = Terrain.do_jogo(Vector3(e.origem[0], e.origem[1], e.origem[2])) - bas * car.corpo(Vector3.ZERO)
	car.global_transform = Transform3D(bas, pos)
	car.reset_physics_interpolation()
	car.pos_ant = pos
	car.linear_velocity = _d(e.vel)
	car.angular_velocity = -_d(e.w)          # vetor axial: a transposição troca o sinal
	# câmbio e motor (marcha do jogo: 0 = ré, 6 = neutro)
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
	# botão da embreagem ("freio de mão") suavizado e o do passo anterior (Clutch Turn)
	car.emb_in = e.mao[1]
	var ps: Dictionary = e.get("powerslide", {})
	car.ps_estado = int(ps.get("estado", 0))
	car.ps_qtd = ps.get("qtd", 0.0)
	car.ps_emb_ant = ps.get("emb_ant", e.mao[1])
	# comandos: direção do jogo + = direita, no remake + = esquerda
	car.steer = -float(e.direcao[1])
	car.throttle = e.acelerador[1]
	car.brake_in = e.freio[1]
	car.test_input = {"steer": -float(e.direcao[0]), "thr": e.acelerador[0], "brk": e.freio[0], "hb": float(e.mao[0]) > 0.5}
	for i in 4:
		var r: Dictionary = e.rodas[i]
		var w: Dictionary = car.wheels[car.jit_order[i]]
		# o curso da RAM é o do contato no começo do passo (pose de antes de
		# integrar), subido até o chão (pen = 0). A pose da RAM é a do fim:
		# a roda que estava no chão desce o quanto o ponto dela subiu no passo
		# (carro subindo, fm_2), mais 1 mm pra contar como no chão
		var sobe := 0.0
		if absf(float(r.contato[0])) + absf(float(r.contato[2])) > 0.0:
			var at: Vector3 = car.global_transform * Vector3(w.px, w.y0, w.pz)
			var com_w: Vector3 = car.global_transform * car.center_of_mass
			var vp: Vector3 = car.linear_velocity + car.angular_velocity.cross(at - com_w)
			sobe = maxf(vp.dot(car.global_transform.basis.y) * PASSO, 0.0)
		w.x = r.curso - 0.001 - sobe
		w.v = r.curso_v
		w.omega = r.giro
		w.slip = r.patinada
		w.sr = r.medida
		w.abs = int(r.abs) != 0
		w.grip = r.grip
	# conferência: o CoM do remake cai no CoM da RAM
	var com_r: Vector3 = car.global_transform * car.center_of_mass
	var com_j: Vector3 = Terrain.do_jogo(Vector3(e.com[0], e.com[1], e.com[2]))
	print("\n== %s (relógio %.2f): CoM remake x RAM %.1f cm" % [e.arquivo, e.relogio, (com_r - com_j).length() * 100.0])


func _conferir_forca(e: Dictionary) -> void:
	var s := _medir()
	print("  remake %.1f km/h  derrapagem %.1f° (RAM %.1f°)  giro %.1f°/s  rodas no chão %d" % [s.kmh, s.beta, rad_to_deg(e.derrapagem), s.giro, car.grounded])
	print("  motor: rpm jogo %d remake %d | limitador %.2f/%.2f | embreagem %.3f/%.3f | botão %.2f" % [
		int(e.rpm), int(car.rpm), e.limitador, car.lim_k, e.embreagem, car.clutch, float(e.mao[0])])
	var nomes := ["FL", "RL", "FR", "RR"]
	for i in 4:
		var r: Dictionary = e.rodas[i]
		var w: Dictionary = car.wheels[car.jit_order[i]]
		# jogo: x = pro lado direito do carro (kN); remake: fx + = esquerda (N)
		print("  %s lateral jogo %6.2f remake %6.2f | frente jogo %6.2f remake %6.2f kN | patinada %.2f/%.2f elipse %.2f/%.2f" % [
			nomes[i], r.forca[0], -w.fx / 1000.0, r.forca[2], w.fz / 1000.0, r.patinada, w.slip, r.grip, w.grip])
		pior_forca = maxf(pior_forca, absf(float(r.forca[0]) + w.fx / 1000.0))


## velocidade, derrapagem (graus, + = jogo: velocidade pra direita do bico) e
## giro (graus/s, + = jogo: virando pra direita), no sentido do jogo
func _medir() -> Dictionary:
	var b: Basis = car.global_transform.basis
	var v: Vector3 = car.linear_velocity
	var vf := v.dot(b.z)
	var vd := -v.dot(b.x)
	return {"kmh": v.length() * 3.6, "beta": rad_to_deg(atan2(vd, vf)),
		"giro": -rad_to_deg(car.angular_velocity.dot(b.y)), "rumo": rad_to_deg(atan2(b.z.z, b.z.x))}


func _comparar_fim(e: Dictionary) -> void:
	var s := _medir()
	var fj := Vector3(e.frente[0], e.frente[1], e.frente[2])
	var f0 := Vector3(e0.frente[0], e0.frente[1], e0.frente[2])
	var rumo_j := rad_to_deg(atan2(fj.x, fj.z) - atan2(f0.x, f0.z))
	var b0 := Basis(-_d(e0.direita), _d(e0.cima), _d(e0.frente))
	var b1: Basis = car.global_transform.basis
	var rumo_r := -rad_to_deg(atan2(b1.z.x, b1.z.z) - atan2(b0.z.x, b0.z.z))
	var vel := Vector3(e.vel[0], e.vel[1], e.vel[2])
	var dir := Vector3(e.direita[0], e.direita[1], e.direita[2])
	var cima := Vector3(e.cima[0], e.cima[1], e.cima[2])
	var w := Vector3(e.w[0], e.w[1], e.w[2])
	var p_j: Vector3 = Terrain.do_jogo(Vector3(e.origem[0], e.origem[1], e.origem[2]))
	var p_r: Vector3 = car.global_transform * car.corpo(Vector3.ZERO)
	print("  velocidade   jogo %5.1f  remake %5.1f km/h" % [vel.length() * 3.6, s.kmh])
	print("  girou        jogo %5.1f  remake %5.1f°" % [wrapf(rumo_j, -180.0, 180.0), wrapf(rumo_r, -180.0, 180.0)])
	print("  derrapagem   jogo %5.1f  remake %5.1f°" % [rad_to_deg(atan2(vel.dot(dir), vel.dot(fj))), s.beta])
	print("  giro         jogo %5.1f  remake %5.1f°/s" % [rad_to_deg(w.dot(cima)), s.giro])
	print("  posição: remake a %.1f m da RAM  marcha jogo %d remake %s" % [(p_r - p_j).length(), int(e.marcha), car.gear_label()])
	var suj_j: float = e.sujeira - e0.sujeira
	var suj_r: float = car.sujeira_nivel - e0.sujeira
	print("  sujou        jogo %.4f  remake %.4f (nível %.4f -> %.4f)" % [suj_j, suj_r, e0.sujeira, car.sujeira_nivel])
	ok_fim = (p_r - p_j).length() < 1.5 and absf(wrapf(rumo_r - rumo_j, -180.0, 180.0)) < 10.0
	if not ok_fim:
		print("  FALHA: mais de 1.5 m ou 10° do jogo")
	if absf(suj_r - suj_j) > 0.1 * suj_j:
		ok_fim = false
		print("  FALHA: sujeira mais de 10% longe do jogo")
	var rj: Dictionary = e.roda_suja
	var cj := _cor(rj.cor)
	var dc := Vector4(cj.r - car.roda_cor.r, cj.g - car.roda_cor.g, cj.b - car.roda_cor.b, cj.a - car.roda_cor.a)
	print("  lama da roda jogo %s t %.4f mat %d | remake %s t %.4f mat %d" % [_txt(cj), rj.t, int(rj.mat),
		_txt(car.roda_cor), car.roda_t, car.roda_mat])
	if int(rj.mat) != car.roda_mat or dc.length() > 0.03:
		ok_fim = false
		print("  FALHA: lama da roda longe do jogo (%.3f)" % dc.length())


## Clutch Turn (0x214610) a partir do drr_3, já de lado: botão da embreagem
## 3 passos e solta (0 -> 1 -> 2), segura em 2 com a elipse de trás no
## mínimo x 0.8, solta o acelerador (-> 3) e some a Decay_rate (1/s)
func _clutch_turn() -> void:
	if n == 0:
		_por_no_estado(ref.estados["drr_3"])
		print("\n== Clutch Turn no drr_3: embreagem 3 passos e solta, acelerador solto em 0.12 s")
	var ti: Dictionary = car.test_input
	ti.emb = 1.0 if n < 3 else 0.0
	ti.thr = 1.0 if n < 6 else 0.0
	car._physics_process(PASSO)
	seq.append([car.ps_estado, car.ps_qtd])
	n += 1
	if n < 60:
		return
	var estados := []
	for x in seq:
		if estados.is_empty() or estados[-1] != x[0]:
			estados.append(x[0])
	var q_fim: float = seq[-1][1]
	# solta a embreagem no 4º passo (-> 1), cresce no 5º (-> 2); o acelerador
	# suavizado zera 0.5 s depois de soltar (-> 3) e aí some a 1/s
	var i3 := 0
	while seq[i3][0] != 3:
		i3 += 1
	var esperado := 1.0 - (seq.size() - i3) * PASSO
	var ok: bool = estados == [0, 1, 2, 3] and absf(q_fim - esperado) < 0.03 and seq[3][0] == 1 and seq[4][0] == 2
	print("  estados %s  (3 a partir do passo %d)  quantidade no fim %.2f (esperado %.2f)" % [estados, i3 + 1, q_fim, esperado])
	print("  maior diferença de força lateral por roda: %.2f kN (limite 0.5)" % pior_forca)
	print("teste_derrapagem: %s" % ("ok" if ok and ok_fim and pior_forca < 0.5 else "FALHA"))
	quit()
