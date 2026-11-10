extends SceneTree
## Confere o chão do RX_01 (terrain.gd) e a mão (espelho) com a RAM:
##  1. altura (height_at e o raio na colisão) e material no contato das 24
##     rodas dos 6 save states da largada (tests/ref_ram_chao.json, mundo do
##     jogo, passado pro remake por Terrain.do_jogo);
##  2. cada um dos 6 carros posto na pose da RAM: as rodas da física e as do
##     visual (FL, RL, FR, RR pela ordem do jogo) caem em cima do contato das
##     rodas da RAM. Lado trocado dá uns 2,4 m de erro. O cubo do visual anda
##     com a balança (até ~11 cm do contato no Inferno), por isso a folga dele
##     é maior;
##  3. Renegade na largada (asfalto, WheelJitter 0) não treme; numa terra
##     plana ali perto (COMMON_2 DIRT/OFFTRACK2, 0.3) treme;
##  4. atrito e Damping de cada roda e as médias (corpo+0x750/0x758, 0x780/
##     0x788): na largada iguais à RAM (1.10 e 0, pneu DIRT_BUDGET no
##     asfalto); na terra 0.69 e 0.2 (COMMON_2 no Materials.xml);
##     O arrasto (0x20e5e8) a 20 m/s confere com Air 1.25 / Ground 2.0 da RAM;
##  5. a tabela de materiais do carro na RAM (veículo+0xd0, 24 registros:
##     atrito do pneu e Damping) = terrain.atrito / terrain.amortecimento.
## Uso: godot --headless --path . -s res://tests/teste_chao.gd

const Car := preload("res://carro/car.gd")
const Main := preload("res://main.gd")
const Terrain := preload("res://pista/terrain.gd")
const TERRA := Vector2(576.0, 572.0)     # remake (jogo x 572, z 1600)
const TOL_FISICA := 0.05                 # m, no plano xz
const TOL_VISUAL := 0.30

var terrain
var ref: Dictionary
var fila := []                           # carros da RAM ainda por conferir
var car
var nome := ""
var falhas := 0
var passo := 0
var t := 0.0
var etapa := "ram"


func _initialize() -> void:
	terrain = Terrain.new()
	root.add_child(terrain)
	ref = JSON.parse_string(FileAccess.get_file_as_string("res://tests/ref_ram_chao.json"))
	fila = ref.carros.keys()


func _physics_process(dt: float) -> bool:
	passo += 1
	if passo < 2:
		return false
	match etapa:
		"ram":
			_conferir_ram()
			_conferir_tabela()
			etapa = "pose"
		"pose":
			if car == null:
				if fila.is_empty():
					etapa = "tremida"
					_novo_carro(0)
					t = 0.0
					return false
				nome = fila.pop_front()
				_novo_carro(_veiculo(nome))
				t = 0.0
				return false
			if t == 0.0:
				_pose_da_ram()
			t += dt
			if t > 3.0 * dt:
				_conferir_rodas()
				car.queue_free()
				car = null
		"tremida":
			if not car.is_inside_tree():
				return false
			if t == 0.0:
				car.reset_to(Vector3(Main.SPAWN_XZ.x, terrain.height_at(Main.SPAWN_XZ.x, Main.SPAWN_XZ.y) + 0.8,
					Main.SPAWN_XZ.y), deg_to_rad(Main.SPAWN_YAW))
			t += dt
			if absf(t - 2.0) < dt * 0.5:
				_tremida("largada (asfalto)", 0.0, _atrito_ram(), _amort_ram())
				car.reset_to(Vector3(TERRA.x, terrain.height_at(TERRA.x, TERRA.y) + 0.8, TERRA.y), 0.0)
			if absf(t - 4.0) < dt * 0.5:
				_tremida("terra", 0.3, 0.69, 0.2)
				print("teste_chao: %s" % ("ok" if falhas == 0 else "%d falhas" % falhas))
				quit(1 if falhas else 0)
	return false


func _veiculo(n: String) -> int:
	for i in Main.VEHICLES.size():
		if Main.VEHICLES[i].name.to_lower() == n:
			return i
	push_error("carro %s não está no main.gd" % n)
	return 0


func _novo_carro(i: int) -> void:
	var v: Dictionary = Main.VEHICLES[i]
	car = Car.new()
	car.asset_dir = v.dir
	car.data_files = ["res://data/vehicles/buggy_base.xml", v.data]
	car.points_file = v.points
	car.vehicle_id = v.id
	car.terrain = terrain
	root.add_child(car)


## rodas da RAM de um carro no remake, na ordem FL, RL, FR, RR
func _rodas_ram(n: String) -> Array:
	var out := []
	for r in ref.carros[n]:
		out.append(Terrain.do_jogo(Vector3(r.x, r.y, r.z)))
	return out


func _conferir_ram() -> void:
	var space: PhysicsDirectSpaceState3D = root.get_world_3d().direct_space_state
	var pior_h := 0.0
	var pior_raio := 0.0
	var n := 0
	for c in ref.carros:
		var rs := _rodas_ram(c)
		var k := 0
		for r in ref.carros[c]:
			var p: Vector3 = rs[k]
			k += 1
			var h: float = terrain.height_at(p.x, p.z)
			var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 5.0, p - Vector3.UP * 5.0)
			var hit := space.intersect_ray(q)
			var hr: float = hit.position.y if not hit.is_empty() else INF
			pior_h = maxf(pior_h, absf(h - p.y))
			pior_raio = maxf(pior_raio, absf(hr - p.y))
			var m: int = terrain.material_at(p.x, p.z)
			if m != int(r.mat):
				falhas += 1
				print("%s %s: material %d, RAM %d" % [c, r.roda, m, r.mat])
			n += 1
		# mão: no Godot a esquerda do carro é UP x frente
		var fwd: Vector3 = (rs[0] + rs[2] - rs[1] - rs[3]) * 0.5
		var mao: float = (rs[0] - rs[2]).dot(Vector3.UP.cross(fwd).normalized())
		if mao <= 0.0:
			falhas += 1
			print("%s: FL não está à esquerda do FR no remake (%.2f m)" % [c, mao])
	print("%d rodas da RAM: maior erro de altura %.2f mm (height_at), %.2f mm (colisão)" % [
		n, pior_h * 1000.0, pior_raio * 1000.0])
	if pior_h > 0.002 or pior_raio > 0.002:
		falhas += 1
		print("altura FALHOU (limite 2 mm)")


## põe o carro com a frente e o centro das rodas iguais aos da RAM
func _pose_da_ram() -> void:
	var rs := _rodas_ram(nome)
	var fwd: Vector3 = (rs[0] + rs[2] - rs[1] - rs[3]) * 0.5
	var yaw := atan2(fwd.x, fwd.z)
	var c_ram: Vector3 = (rs[0] + rs[1] + rs[2] + rs[3]) * 0.25
	var c_car := Vector3.ZERO
	for w in car.wheels:
		c_car += Vector3(w.px, 0.0, w.pz) * 0.25
	var pos: Vector3 = c_ram - Basis(Vector3.UP, yaw) * c_car
	pos.y = terrain.height_at(pos.x, pos.z) + 0.6
	car.reset_to(pos, yaw)


func _conferir_rodas() -> void:
	var rs := _rodas_ram(nome)
	var pior_f := 0.0
	var pior_v := 0.0
	var txt := []
	var nomes := ["FL", "RL", "FR", "RR"]
	for k in 4:
		var w: Dictionary = car.wheels[car.jit_order[k]]
		var f: Vector3 = car.global_transform * Vector3(w.px, w.y0, w.pz)
		var v: Vector3 = w.pivot.global_position
		var ef := Vector2(f.x - rs[k].x, f.z - rs[k].z).length()
		var ev := Vector2(v.x - rs[k].x, v.z - rs[k].z).length()
		pior_f = maxf(pior_f, ef)
		pior_v = maxf(pior_v, ev)
		txt.append("%s %.0f/%.0f" % [nomes[k], ef * 100.0, ev * 100.0])
	var ok := pior_f < TOL_FISICA and pior_v < TOL_VISUAL
	if not ok:
		falhas += 1
	print("%-9s rodas x RAM (cm, física/visual): %s  %s" % [nome, "  ".join(txt), "ok" if ok else "FALHOU"])


## atrito / Damping das rodas do Renegade na RAM (todas iguais na largada)
func _atrito_ram() -> float:
	return _igual_nas_rodas("atrito")


func _amort_ram() -> float:
	return _igual_nas_rodas("amort")


func _igual_nas_rodas(campo: String) -> float:
	var a: float = ref.carros.renegade[0][campo]
	for r in ref.carros.renegade:
		if absf(r[campo] - a) > 1e-6:
			push_error("%s diferente entre as rodas na RAM" % campo)
	return a


## tabela de materiais do carro na RAM x Materials.xml da pista
func _conferir_tabela() -> void:
	var ruins := []
	for i in ref.tabela.size():
		var r: Dictionary = ref.tabela[i]
		var a: float = terrain.atrito(i, "DIRT_BUDGET")
		var d: float = terrain.amortecimento(i)
		if absf(a - r.atrito) > 1e-4 or absf(d - r.amort) > 1e-4:
			ruins.append("%d %s: atrito %.2f/%.2f Damping %.2f/%.2f" % [i, terrain.material_name(i), a,
				r.atrito, d, r.amort])
	if not ruins.is_empty():
		falhas += 1
	print("tabela de materiais x RAM (%d, atrito e Damping): %s" % [ref.tabela.size(),
		"ok" if ruins.is_empty() else "FALHOU " + "; ".join(ruins)])


## força 20 m/s no plano do chão e sorteia uma vez: só a roda no chão de
## material com WheelJitter > 0 treme
func _tremida(onde: String, wj: float, mu: float, amort: float) -> void:
	car.spd_ground = 20.0
	car._wheel_jitter()
	var txt := []
	var max_j := 0.0
	for i in car.jit_order:
		var w: Dictionary = car.wheels[i]
		txt.append("%s(%.1f)%s" % [terrain.material_name(w.mat), terrain.wheel_jitter(w.mat, -1.0),
			"" if w.hit else " no ar"])
		max_j = maxf(max_j, absf(w.jit))
		if not w.hit or absf(terrain.wheel_jitter(w.mat, -1.0) - wj) > 1e-6:
			falhas += 1
	var ok := max_j == 0.0 if wj == 0.0 else max_j > 0.0
	# câmera: veículo+0xac0 = média do WheelJitter embaixo de FL, RL, FR
	ok = ok and absf(car.jitter_chao - wj) < 1e-6
	# atrito e Damping por roda e as médias (com as 4 no chão)
	for w in car.wheels:
		ok = ok and absf(w.mu - mu) < 1e-6 and absf(w.amort - amort) < 1e-6
	ok = ok and absf(car.mu_medio - mu) < 1e-6 and absf(car.amort_medio - amort) < 1e-6
	# arrasto a 20 m/s (0x20e5e8) com Air 1.25 e Ground 2.0 (params+0x3e0/0x3e4 na RAM)
	var arr: float = car._arrasto(20.0, 1.0 / 50.0)
	var arr_esp: float = (1.25 * 0.65 + amort * 2.0 * 10.0) * 400.0
	ok = ok and car.P.air_drag == 1.25 and car.P.ground_drag == 2.0 and absf(arr - arr_esp) < 1e-3
	if not ok:
		falhas += 1
	print("%s: %s  maior tremida %.1f mm, atrito %.2f (esperado %.2f), Damping %.2f (esperado %.2f), arrasto a 20 m/s %.0f N  %s" % [
		onde, ", ".join(txt), max_j * 1000.0, car.mu_medio, mu, car.amort_medio, amort, arr, "ok" if ok else "FALHOU"])
