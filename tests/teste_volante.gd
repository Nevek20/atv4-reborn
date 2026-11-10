extends SceneTree
## Mãos do piloto no volante (melhoria nossa, car.gd MAOS_NO_VOLANTE): em cada
## carro e em várias posições do volante, o centro do punho tem que estar no
## seu ponto do aro (girado com o volante). Imprime também o giro do volante no
## volante todo, que sai da animação STEER_LEFT do jogo.
## Buggies e trucks (Main.frota, uma vez por pasta de modelo).
## Uso: godot --headless --path . -s res://tests/teste_volante.gd   (VEHS=25 só esses;
## BANCO=x,y,z e AVANCO=m testam o banco e o volante, car.gd BANCO_NOSSO;
## PERFIL=1 imprime o pulo do cotovelo passo a passo)
const Car := preload("res://carro/car.gd")
const Main := preload("res://main.gd")

var i := -1
var car = null
var pior := 0.0
var feitos := 0
var vistos := {}


func _process(_dt: float) -> bool:
	if car != null:
		_conferir()
		car.free()
		car = null
	i += 1
	while i < Main.frota().size() and (vistos.has(Main.frota()[i].dir)
			or not FileAccess.file_exists(Main.frota()[i].dir.path_join("pecas.json"))
			or (OS.has_environment("VEHS") and not str(i) in OS.get_environment("VEHS").split(","))):
		i += 1
	if i >= Main.frota().size():
		print("teste_volante: %s (%d carros, pior %.1f cm)" % ["ok" if pior < 0.01 and feitos > 0 else "FALHA", feitos, pior * 100.0])
		return true
	var v: Dictionary = Main.frota()[i]
	vistos[v.dir] = true
	car = Car.new()
	car.asset_dir = v.dir
	car.data_files = Main.dados(v)
	car.points_file = v.points
	car.vehicle_id = v.id
	car.suspension = false
	if v.id.begins_with("TRUCK"):
		car.desligadas = Car.PENDENTES_TRUCK
	root.add_child(car)
	car.set_physics_process(false)
	return false


func _conferir() -> void:
	var nome: String = Main.frota()[i].name
	if car.piloto == null or not car.piloto.no_volante():
		print("%-24s sem piloto ou sem volante" % nome)
		return
	var pior_carro := 0.0
	car.piloto.alcance = 0.0
	var ruins := ""
	# volante parado e tremendo (extra = tremida do volante, car.gd _vibracao)
	for se in [[-1.0, 0.0], [-0.5, 0.0], [-0.2, 0.0], [0.0, 0.0], [0.2, 0.0], [0.5, 0.0], [1.0, 0.0],
			[1.0, 0.06], [-1.0, -0.06], [0.0, 0.06], [0.7, -0.06]]:
		var s: float = se[0]
		car.piloto.pose(s, se[1])
		var es: Array = car.piloto.erro_maos(s, se[1])
		for e in es:
			pior_carro = maxf(pior_carro, e)
		if es.max() > 0.005:
			ruins += " s=%+.1f (%.1f/%.1f cm)" % [s, es[0] * 100.0, es[1] * 100.0]
	pior = maxf(pior, pior_carro)
	feitos += 1
	# braço: cotovelo (180 = esticado), dobra/torção do pulso x animação e pra
	# onde o cotovelo aponta (0 baixo, + fora, - dentro), volante reto e todo
	var bracos := ""
	for s in [0.0, 1.0]:
		car.piloto.pose(s)
		for mb in car.piloto.medidas_bracos():
			bracos += "  [%+.0f] cot %3.0f° pulso %3.0f° torção %3.0f° aponta %+4.0f°" % [
				s, mb.cotovelo, mb.pulso, mb.torcao, mb.aponta]
	print("   braços D/E:%s" % bracos)
	# volante de um lado ao outro em 100 passos: maior pulo do cotovelo e da
	# mão de um passo pro seguinte (pulo = a busca do giro da mão trocando de
	# solução: a mão "estala")
	var antes: Array = []
	var pulo_cot := 0.0
	var pulo_mao := 0.0
	for k in 101:
		car.piloto.pose(-1.0 + k * 0.02)
		var j: Array = car.piloto.juntas_bracos()
		if not antes.is_empty():
			if OS.get_environment("PERFIL") == "1":
				print("      s %+.2f cotovelo D %.1f E %.1f cm" % [-1.0 + k * 0.02,
					(j[0][0] - antes[0][0]).length() * 100.0, (j[1][0] - antes[1][0]).length() * 100.0])
			for h in j.size():
				pulo_cot = maxf(pulo_cot, (j[h][0] - antes[h][0]).length())
				pulo_mao = maxf(pulo_mao, rad_to_deg((j[h][1] as Quaternion).angle_to(antes[h][1])))
		antes = j
	print("   pulo máximo por passo de 2%% do volante: cotovelo %.1f cm, mão %.1f°" % [pulo_cot * 100.0, pulo_mao])
	print("%-24s giro do volante no volante todo %5.1f°  punho fora do aro no pior caso %.1f cm  braço até %.0f%% esticado  volante %s avançado %.1f cm (coluna %+.1f cm)%s" % [
		nome, rad_to_deg(car.piloto.giro_volante(1.0)), pior_carro * 100.0, car.piloto.alcance * 100.0,
		car.volante_estilo, car.sw_avanco * 100.0, car.sw_ponta_coluna * 100.0, ruins])
