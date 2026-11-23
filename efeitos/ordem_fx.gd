extends Node
## Ordem de desenho dos efeitos transparentes (NOSSO; melhoria nossa, o PS2
## não tem esse problema). O Godot desenha cada MultiMesh (poeira, espirro,
## pedrinhas, lascas, palha) e cada GPUParticles3D (fumaça) inteira de uma
## vez e ordena as transparentes da mesma prioridade pela distância da
## câmera ao centro da caixa. A caixa da poeira é a das nuvens vivas (o
## rastro todo, até dezenas de metros): de um quadro pro outro o centro pula
## e duas nuvens que se cruzam na tela trocavam de ordem (a de cima virava a
## de baixo): a poeira e a água piscavam (Matheus, nov/2026).
## tests/medir_ordem_fx.gd (corrida com os 8 carros): sem isto 368 trocas
## de ordem entre efeitos que se cruzavam na tela em 80 s a 50 FPS e 569 em
## 40 s a 240 FPS. Agora todos os efeitos de um carro ordenam pela distância
## do CARRO desenhado (interpolado) mais um desempate fixo por tipo: o
## sorting_offset de cada um compensa a diferença entre o centro da caixa e o
## carro. Com isso 117 (50 FPS) e 109 (240 FPS), as que sobram são carros
## cruzando a mesma distância da câmera (uma vez cada). 0.07 ms por quadro.
## Roda todo quadro e depois de todos (os efeitos gravam a caixa e a câmera
## anda no _process): process_priority alto. NÃO pular quadro: o centro do
## rastro pula quando nasce ou morre nuvem e o offset velho erra (testado a
## 75 Hz com a tela a 240 FPS: 14 mil trocas em 40 s).

## desempate por tipo dentro do mesmo carro (m; maior = desenhado depois)
const DESEMPATE := {"Nuvens": 0.0, "Espirro": 0.01, "Pedras": 0.02, "Lascas": 0.03, "Palha": 0.04}
const DESEMPATE_FUMACA := -0.01
const RELER := 1.0               # s: de quanto em quanto tempo procura efeitos novos nos carros
var ligado := OS.get_environment("ORDEM_FX") != "0"   # ORDEM_FX=0 desliga (diagnóstico)

var main
var _carros: Array = []          # carros da última leitura
var _ref := PackedInt32Array()   # por efeito: índice do carro em _carros
var _fx: Array[GeometryInstance3D] = []
var _mm: Array = []              # MultiMesh do efeito (null = partículas)
var _tb := PackedFloat32Array()  # desempate
var _t := RELER


func _init(m) -> void:
	main = m
	name = "OrdemFx"
	process_priority = 1000


func _process(dt: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null or not ligado:
		return
	_t += dt
	var n_carros := 1
	if main.corrida and main.corrida.ia:
		n_carros += main.corrida.ia.rivais.size()
	if _t >= RELER or n_carros != _carros.size():
		_t = 0.0
		_reler()
	var olho: Vector3 = cam.global_position
	var d_carro := PackedFloat32Array()
	d_carro.resize(_carros.size())
	for i in _carros.size():
		var car = _carros[i]
		# a posição desenhada (interpolada): a crua só muda a cada passo de
		# física e, com a câmera andando todo quadro, a distância de 2 carros
		# quase empatados ficava oscilando (a 240 FPS piorava a troca)
		d_carro[i] = olho.distance_to(car.get_global_transform_interpolated().origin) if is_instance_valid(car) else 0.0
	for i in _fx.size():
		var g := _fx[i]
		if not is_instance_valid(g):
			continue
		var centro: Vector3
		var mm = _mm[i]
		if mm != null:
			if (mm as MultiMesh).visible_instance_count == 0:
				continue
			# os nós da poeira, pedras e lascas ficam na origem (top_level,
			# identidade): a caixa já está no mundo
			centro = (mm as MultiMesh).custom_aabb.get_center()
		else:
			centro = g.global_position       # fumaça: caixa centrada no nó
		# Godot (perspectiva): profundidade = distância ao centro - offset
		var off: float = olho.distance_to(centro) - d_carro[_ref[i]] + _tb[i]
		if absf(off - g.sorting_offset) > 0.0001:   # 0.1 mm, bem abaixo dos desempates (1 cm)
			g.sorting_offset = off


func _reler() -> void:
	_carros = [main.car]
	if main.corrida and main.corrida.ia:
		for y in main.corrida.ia.rivais:
			_carros.append(y.car)
	_ref.clear()
	_fx.clear()
	_mm.clear()
	_tb.clear()
	for i in _carros.size():
		var car = _carros[i]
		if not is_instance_valid(car):
			continue
		var canos := 0
		for g in car.find_children("*", "GeometryInstance3D", true, false):
			if g is MultiMeshInstance3D and (g as Node3D).top_level:
				_add(i, g, (g as MultiMeshInstance3D).multimesh, DESEMPATE.get(String(g.name), 0.05))
			elif g is GPUParticles3D:
				# um desempate por escape (os 2 canos empatavam e trocavam)
				_add(i, g, null, DESEMPATE_FUMACA - 0.01 * canos)
				canos += 1


func _add(i: int, g: GeometryInstance3D, mm, tb: float) -> void:
	_ref.append(i)
	_fx.append(g)
	_mm.append(mm)
	_tb.append(tb)
