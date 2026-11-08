extends SceneTree
## Pedrinhas do pneu (pedras.gd, porta do 0x3bb618) no RX01: o Renegade larga
## com o acelerador no fundo e o volante reto, e aos VIRA s (padrão 7) vira
## tudo (derrapa). A cada 0.5 s imprime velocidade, material e patinada das
## rodas de trás, partículas vivas (pedras / borrifos), soltas no meio
## segundo, altura máxima acima do chão e onde elas estão em relação ao carro
## (atrás, do lado). Larga num ponto de terra comum perto da largada.
## Confere: parado não solta; patinando na terra solta (o save state da
## derrapagem tem 80 vivas); o estoque (256) não estoura; derrapando as
## pedras saem pro lado em que o carro escorrega (o jogo, drr2).
## Uso: godot --headless --path . -s res://tests/teste_pedras.gd [-- veh]

const Car := preload("res://carro/car.gd")
const Main := preload("res://main.gd")
const Terrain := preload("res://pista/terrain.gd")

var terrain
var car
var t := 0.0
var prox := 0.5
var vira := 7.0
var parado := -1
var max_vivas := 0
var soltas_ant := 0
var abaixo := 0
var lado_soma := 0.0          # derrapando: pedras do lado da velocidade
var lado_n := 0
var falhas := 0


func _initialize() -> void:
	terrain = Terrain.new()
	root.add_child(terrain)
	var a := OS.get_cmdline_user_args()
	var v: Dictionary = Main.frota()[int(a[0]) if a.size() > 0 else 0]
	if OS.get_environment("VIRA") != "":
		vira = float(OS.get_environment("VIRA"))
	car = Car.new()
	Main.configurar(car, v)
	car.terrain = terrain
	car.suspension = false
	root.add_child(car)
	car.test_input = {"thr": 0.0, "brk": 0.0, "steer": 0.0}


## ponto de terra comum (COMMON_1, IsDirt) mais perto da largada, com terra
## em volta (8 m pra frente e 3 m pros lados) e chão quase plano
static func terra_perto(terrain, c: Vector2) -> Vector2:
	var fr := Vector2(sin(deg_to_rad(Main.SPAWN_YAW)), cos(deg_to_rad(Main.SPAWN_YAW)))
	var la := Vector2(fr.y, -fr.x)
	for r in range(5, 200, 2):
		for k in 36:
			var a := TAU * k / 36.0
			var p := c + Vector2(cos(a), sin(a)) * r
			var ok := true
			for f in [-3.0, 0.0, 4.0, 8.0, 12.0]:
				for l in [-3.0, 0.0, 3.0]:
					var q: Vector2 = p + fr * f + la * l
					if terrain.material_at(q.x, q.y) != 0:
						ok = false
			if ok and absf(terrain.height_at(p.x, p.y) - terrain.height_at(p.x + fr.x * 8, p.y + fr.y * 8)) < 0.4:
				return p
	return c


func _physics_process(dt: float) -> bool:
	if not car.is_inside_tree():
		return false
	if t == 0.0:
		var p := terra_perto(terrain, Main.SPAWN_XZ)
		print("largada na terra em (%.1f, %.1f): %s" % [p.x, p.y, terrain.materials[terrain.material_at(p.x, p.y)].get("Name")])
		car.reset_to(Vector3(p.x, terrain.height_at(p.x, p.y) + 0.8, p.y), deg_to_rad(Main.SPAWN_YAW))
		if car.pedras == null:
			print("teste_pedras: FALHA (sem pedras: falta assets/fx/pedras.png? rode tools/fx_jogo.py)")
			return true
	t += dt
	car.test_input.thr = 1.0 if t > 1.5 else 0.0
	car.test_input.steer = 1.0 if t > vira else 0.0
	var pq = car.pedras
	if t >= 1.4 and parado < 0:
		parado = pq.soltas
	max_vivas = maxi(max_vivas, pq.vivas())
	var v: Vector3 = car.linear_velocity
	var fwd: Vector3 = car.forward()
	var dir_lat := (v - fwd * v.dot(fwd))
	dir_lat.y = 0.0
	for k in pq.vivas():
		var q: Vector3 = pq.p_pos[k]
		# 1 cm de folga: o chão guardado é o relevo + 0.02 medido em rodízio
		if pq.p_tipo[k] == 0 and pq.p_chao[k] > -1e30 and q.y < terrain.height_at(q.x, q.z) - 0.05:
			abaixo += 1
		# recém-soltas derrapando: velocidade - v do carro x c2 = direção x vel +
		# lado x l x c1; o lado (|l c1| até 3.6 m/s) não passa da direção (5..11)
		var beta := clampf(absf(car.sideslip), 0.0, 1.0)
		if beta > 0.5 and pq.p_idade[k] < 0.021 and dir_lat.length() > 1.0:
			var c2 := lerpf(pq.RETO[2], pq.LADO[2], beta)
			var rel: Vector3 = pq.p_vel[k] - v * c2
			lado_soma += signf(rel.dot(dir_lat))
			lado_n += 1
	if t >= prox:
		prox += 0.5
		var n: int = pq.vivas()
		var npedra := 0
		var alt := 0.0
		var atras := 0.0
		var lado := 0.0
		for k in n:
			var q: Vector3 = pq.p_pos[k]
			if pq.p_tipo[k] == 0:
				npedra += 1
			alt = maxf(alt, q.y - terrain.height_at(q.x, q.z))
			var rel: Vector3 = q - car.global_position
			atras += -rel.dot(fwd)
			lado += absf(rel.dot(fwd.cross(Vector3.UP)))
		var rodas := ""
		for w in car.wheels:
			if w.front:
				continue
			var m: Dictionary = terrain.materials[w.mat] if w.mat >= 0 else {}
			rodas += " %s(pat %.2f)" % [String(m.get("Name", "-")).get_slice("(", 1).trim_suffix(")*"), w.sr]
		print("%4.1f s %5.1f km/h β %5.1f°  vivas %3d (pedras %3d, borrifos %3d)  soltas +%3d  alto %.2f m  atrás %.1f m  lado %.1f m %s" % [
			t, v.length() * 3.6, rad_to_deg(car.sideslip), n, npedra, n - npedra, pq.soltas - soltas_ant,
			alt, atras / maxf(n, 1), lado / maxf(n, 1), rodas])
		soltas_ant = pq.soltas
	if t < vira + 4.0:
		return false
	if parado != 0:
		falhas += 1
		print("FALHA: parado soltou %d" % parado)
	if max_vivas < 20:
		falhas += 1
		print("FALHA: patinando soltou só %d vivas" % max_vivas)
	if max_vivas > pq.MAX:
		falhas += 1
		print("FALHA: passou do estoque (%d)" % max_vivas)
	# o chão de cada pedra é medido em rodízio (5 por quadro) e fica parado: a
	# pedra que anda pra um lugar mais alto passa por baixo do relevo (o jogo)
	print("  pedra mais de 5 cm abaixo do relevo (chão guardado velho): %d amostras" % abaixo)
	var lado_m := lado_soma / maxf(lado_n, 1)
	print("  derrapando: lado das pedras x lado da velocidade = %.2f (%d recém-soltas; 1 = todas pro lado em que o carro escorrega)" % [lado_m, lado_n])
	if lado_n < 10 or lado_m < 0.8:
		falhas += 1
		print("FALHA: derrapando as pedras não vão pro lado do escorregão")
	if car.sfx:
		print("  sons de batida no caminho (sem parede): %d %s" % [car.sfx.batida_tocadas.size(), car.sfx.batida_tocadas.slice(0, 4)])
	print("teste_pedras: %s (máximo vivas %d de %d; soltas %d pedras, %d borrifos)" % [
		"ok" if falhas == 0 else "FALHA", max_vivas, pq.MAX, pq.soltas_tipo[0], pq.soltas_tipo[1]])
	return true
