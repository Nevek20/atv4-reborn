extends Node3D
## Cena principal do protótipo: monta mundo, chão, carro, câmera e HUD
## tudo por código, pra ficar fácil de ler e mexer.

# veículos do jogo: física (base + veículo), pontos, câmera e a pasta dos
# assets ("dir", com o pecas.json do gerar_buggies.py: modelo, peças, rodas).
# "id" é o nome no vehicles.xml (posição na lista do jogo, contando do 1).
# Os 3 primeiros ficam fixos (os testes usam --veh 0/1/2).
# "fp" = câmera do piloto [altura, distância, inclinação] em relação ao volante
# (car.gd FP_UP/FP_BACK/FP_PITCH), ajustada pelo Matheus carro a carro no jogo.
# Trucks: números dele (out/2026); o do Chimera foi medido com o volante pela
# metade (tools/volante.py antigo, centro 1.4 cm mais baixo e 1.2 cm mais pra
# frente) e foi refeito pro mesmo olho com o centro novo (0.32, 0.47 -> 0.31, 0.46).
const VEHICLES := [
	{"name": "Renegade", "id": "BUGGY_10", "cams": "BuggyCamSet_10", "dir": "res://assets/renegade",
		"data": "res://data/vehicles/buggy_10.xml", "points": "res://data/vehicles/buggy_10_points.bin", "fp": [0.39, 0.52, 0.00]},
	{"name": "Sphinx", "id": "BUGGY_04", "cams": "BuggyCamSet_04", "dir": "res://assets/sphinx",
		"data": "res://data/vehicles/buggy_04.xml", "points": "res://data/vehicles/buggy_04_points.bin", "fp": [0.35, 0.48, 0.00]},
	# Sphinx do speedrun, pela ficha da tela de opções do vídeo (0:00): pneu
	# DIRT PREMIUM; 269,9 HP = Drive_torque 1,08 x 250 (0x1f5e90), ou seja,
	# motor todo Prototype + câmbio Prototype (soma 1.0); 2204 lbs = 1,0 t
	# (BodyMass L2). Embreagem L2: na troca 2->3 do vídeo a velocidade para
	# 0,28 s (L2 dá 0,30, L1 0,40). O câmbio Prototype libera a relação final
	# custom (0.61; o Level0 de fábrica dá 0.45, vehicle_data.factory_tuning)
	{"name": "Sphinx speedrun", "id": "BUGGY_04", "cams": "BuggyCamSet_04", "dir": "res://assets/sphinx",
		"data": "res://data/vehicles/buggy_04.xml", "points": "res://data/vehicles/buggy_04_points.bin", "fp": [0.35, 0.48, 0.00],
		"livery": "pintura_speedrun.png", "tune": {"engine": 1.0, "mass": 1.0, "shift": 1.0, "final": 0.61, "tire": "DIRT_PREMIUM"}},
	# os outros buggies, na ordem da lista do jogo (tools/gerar_buggies.py)
	{"name": "Mosquito", "id": "BUGGY_01", "cams": "BuggyCamSet_01", "dir": "res://assets/buggy_01",
		"data": "res://data/vehicles/buggy_01.xml", "points": "res://data/vehicles/buggy_01_points.bin", "fp": [0.35, 0.46, 0.00]},
	{"name": "Inferno", "id": "BUGGY_02", "cams": "BuggyCamSet_02", "dir": "res://assets/buggy_02",
		"data": "res://data/vehicles/buggy_02.xml", "points": "res://data/vehicles/buggy_02_points.bin", "fp": [0.37, 0.50, 0.00]},
	{"name": "Trident", "id": "BUGGY_03", "cams": "BuggyCamSet_03", "dir": "res://assets/buggy_03",
		"data": "res://data/vehicles/buggy_03.xml", "points": "res://data/vehicles/buggy_03_points.bin", "fp": [0.37, 0.56, -0.06]},
	{"name": "Bulldog", "id": "BUGGY_05", "cams": "BuggyCamSet_05", "dir": "res://assets/buggy_05",
		"data": "res://data/vehicles/buggy_05.xml", "points": "res://data/vehicles/buggy_05_points.bin", "fp": [0.27, 0.40, -0.08]},
	{"name": "Phantom", "id": "BUGGY_06", "cams": "BuggyCamSet_06", "dir": "res://assets/buggy_06",
		"data": "res://data/vehicles/buggy_06.xml", "points": "res://data/vehicles/buggy_06_points.bin", "fp": [0.37, 0.44, -0.04]},
	{"name": "Kraken V8", "id": "BUGGY_07", "cams": "BuggyCamSet_07", "dir": "res://assets/buggy_07",
		"data": "res://data/vehicles/buggy_07.xml", "points": "res://data/vehicles/buggy_07_points.bin", "fp": [0.35, 0.44, 0.00]},
	{"name": "McKenzies", "id": "BUGGY_08", "cams": "BuggyCamSet_08", "dir": "res://assets/buggy_08",
		"data": "res://data/vehicles/buggy_08.xml", "points": "res://data/vehicles/buggy_08_points.bin", "fp": [0.37, 0.40, 0.02]},
	{"name": "Viper", "id": "BUGGY_09", "cams": "BuggyCamSet_09", "dir": "res://assets/buggy_09",
		"data": "res://data/vehicles/buggy_09.xml", "points": "res://data/vehicles/buggy_09_points.bin", "fp": [0.25, 0.46, -0.10]},
	{"name": "Hurricane", "id": "BUGGY_11", "cams": "BuggyCamSet_11", "dir": "res://assets/buggy_11",
		"data": "res://data/vehicles/buggy_11.xml", "points": "res://data/vehicles/buggy_11_points.bin", "fp": [0.37, 0.48, 0.00]},
	{"name": "Storm", "id": "BUGGY_12", "cams": "LanciaCam", "dir": "res://assets/buggy_12",
		"data": "res://data/vehicles/buggy_12.xml", "points": "res://data/vehicles/buggy_12_points.bin", "fp": [0.33, 0.46, 0.00]},
]
# física: base da classe + o arquivo do veículo
const BASE_BUGGY := "res://data/vehicles/buggy_base.xml"
const BASE_TRUCK := "res://data/vehicles/truck_base.xml"     # Setup/VehicleParams/Truck/TRUCK.xml
# os 12 trucks na ordem da lista do jogo (tools/gerar_buggies.py --classe truck),
# nomes do menu do jogo (text/15205_en.txt). Ficam fora do VEHICLES pra os
# testes dos buggies não mudarem; o menu, o V e o print_tela usam frota()
const TRUCKS := [
	{"name": "Buccaneer", "id": "TRUCK_01", "cams": "TruckCamSet_01", "dir": "res://assets/truck_01",
		"data": "res://data/vehicles/truck_01.xml", "points": "res://data/vehicles/truck_01_points.bin", "base": BASE_TRUCK, "fp": [0.36, 0.47, 0.00]},
	{"name": "Shockwave", "id": "TRUCK_02", "cams": "TruckCamSet_02", "dir": "res://assets/truck_02",
		"data": "res://data/vehicles/truck_02.xml", "points": "res://data/vehicles/truck_02_points.bin", "base": BASE_TRUCK, "fp": [0.42, 0.49, 0.00]},
	{"name": "Shinto", "id": "TRUCK_03", "cams": "TruckCamSet_03", "dir": "res://assets/truck_03",
		"data": "res://data/vehicles/truck_03.xml", "points": "res://data/vehicles/truck_03_points.bin", "base": BASE_TRUCK, "fp": [0.36, 0.47, 0.00]},
	{"name": "Jericho", "id": "TRUCK_04", "cams": "TruckCamSet_11", "dir": "res://assets/truck_04",
		"data": "res://data/vehicles/truck_04.xml", "points": "res://data/vehicles/truck_04_points.bin", "base": BASE_TRUCK, "fp": [0.30, 0.47, -0.04]},
	{"name": "Punisher", "id": "TRUCK_05", "cams": "TruckCamSet_05", "dir": "res://assets/truck_05",
		"data": "res://data/vehicles/truck_05.xml", "points": "res://data/vehicles/truck_05_points.bin", "base": BASE_TRUCK, "fp": [0.36, 0.47, 0.00]},
	{"name": "Panther", "id": "TRUCK_06", "cams": "TruckCamSet_06", "dir": "res://assets/truck_06",
		"data": "res://data/vehicles/truck_06.xml", "points": "res://data/vehicles/truck_06_points.bin", "base": BASE_TRUCK, "fp": [0.36, 0.47, 0.00]},
	{"name": "Herbst Truggy", "id": "TRUCK_07", "cams": "TruckCamSet_07", "dir": "res://assets/truck_07",
		"data": "res://data/vehicles/truck_07.xml", "points": "res://data/vehicles/truck_07_points.bin", "base": BASE_TRUCK, "fp": [0.40, 0.47, 0.00]},
	{"name": "Herbst TT", "id": "TRUCK_08", "cams": "TruckCamSet_08", "dir": "res://assets/truck_08",
		"data": "res://data/vehicles/truck_08.xml", "points": "res://data/vehicles/truck_08_points.bin", "base": BASE_TRUCK, "fp": [0.48, 0.57, -0.04]},
	{"name": "Hammerhead", "id": "TRUCK_09", "cams": "TruckCamSet_09", "dir": "res://assets/truck_09",
		"data": "res://data/vehicles/truck_09.xml", "points": "res://data/vehicles/truck_09_points.bin", "base": BASE_TRUCK, "fp": [0.44, 0.55, 0.00]},
	{"name": "Fireball", "id": "TRUCK_10", "cams": "TruckCamSet_10", "dir": "res://assets/truck_10",
		"data": "res://data/vehicles/truck_10.xml", "points": "res://data/vehicles/truck_10_points.bin", "base": BASE_TRUCK, "fp": [0.32, 0.47, 0.00]},
	{"name": "Goliath", "id": "TRUCK_11", "cams": "TruckCamSet_11", "dir": "res://assets/truck_11",
		"data": "res://data/vehicles/truck_11.xml", "points": "res://data/vehicles/truck_11_points.bin", "base": BASE_TRUCK, "fp": [0.30, 0.47, -0.04]},
	{"name": "Chimera", "id": "TRUCK_12", "cams": "TruckCamSet_12", "dir": "res://assets/truck_12",
		"data": "res://data/vehicles/truck_12.xml", "points": "res://data/vehicles/truck_12_points.bin", "base": BASE_TRUCK, "fp": [0.31, 0.46, -0.02]},
	# bônus resgatado: a CHASSIS_Truck_04 está completa no jogo e nenhum carro
	# usa. É a Chevrolet Silverado pre-runner, carroceria original do Jericho;
	# no remake o "Lazarus" (nome escolhido pelo Matheus)
	# (texturas preRunnerTruck_*); peças de fábrica do Jericho (id TRUCK_04),
	# câmera TruckCamSet_04 (tools/gerar_buggies.py BONUS). Física NOSSA
	# (data/vehicles/lazarus.xml, nov/2026): cabine dupla mais pesada, V8 com
	# mais torque, câmbio mais longo, curso maior e traseira mais presa que o
	# Jericho (o truck_bonus.xml que o gerar_buggies escreve é a do Jericho)
	{"name": "Lazarus", "id": "TRUCK_04", "cams": "TruckCamSet_04", "dir": "res://assets/truck_bonus",
		"data": "res://data/vehicles/lazarus.xml", "points": "res://data/vehicles/truck_bonus_points.bin",
		"base": BASE_TRUCK, "fp": [0.36, 0.47, 0.00], "bonus": true, "som": "res://som/loops/t13_silverado_chevy_53_vortec"},
]
# carros extras NOSSOS (não existem no jogo): modelo .glb no padrão do Assetto
# Corsa convertido pelo tools/carro_glb.py (pontos, casco e física medidos no
# modelo). "tune_id" = peças de fábrica de um carro do jogo; "desligar" =
# melhorias que não servem (o modelo já tem volante e relógios próprios, não
# tem a 2ª textura da sujeira); "motor_escondido" = só a ponta do escape treme.
# Escort RS1600 Mk1 1974: modelo de vecarz no Sketchfab (CC-BY-NC-SA 4.0,
# assets/escort/pecas.json "fonte"); física de partida = a do Storm (o rally
# do jogo) com rodas, curso, massa, CoM e caixa do Escort. Mão inglesa (o
# volante fica na direita, como no modelo). Som: o I4 do Storm por enquanto
const EXTRAS := [
	{"name": "Escort RS1600", "id": "ESCORT", "tune_id": "BUGGY_12", "cams": "LanciaCam",
		"dir": "res://assets/escort", "data": "res://data/vehicles/escort.xml",
		"points": "res://data/vehicles/escort_points.json", "fp": [0.36, 0.50, 0.00], "extra": true,
		"motor_escondido": true, "desligar": ["volante_nosso", "painel", "sujeira", "farol"],
		"som": "res://som/loops/12_storm_lancia_delta_s4"},
]
var veh_idx := 0
# largada do RX_01: centro das 4 rodas e direção do carro nos 6 save states
# parados na largada (tests/ref_ram_chao.json), passados pro remake por
# Terrain.do_jogo (jogo (580.8, z 1564.3), frente a -115.1° no jogo).
# É asfalto (COMMON_3 TARMAC), então ali a roda não treme.
const SPAWN_XZ := Vector2(540.3, 580.8)
const SPAWN_YAW := -154.9                 # graus, frente = +Z do carro

const Car := preload("res://car.gd")
const Terrain := preload("res://terrain.gd")
const SomJogo := preload("res://som_jogo.gd")
const CameraPiloto := preload("res://camera_piloto.gd")
const CameraOrbita := preload("res://camera_orbita.gd")
const Farol := preload("res://farol.gd")
const ObjetosRX01 := preload("res://objetos_rx01.gd")
const Ceu := preload("res://ceu.gd")

var car  # instância de car.gd (sem tipo estático de propósito: métodos próprios do script)
var cam: Camera3D
var hud: Label
var fps_label: Label                     # contador de FPS (F2 liga e desliga); F1 esconde o HUD
var cam_mode := 0                        # 0 perto, 1 longe, 2 capô, 3 para-choque, 4 piloto
var terrain
var objetos                              # objetos_rx01.gd (aviso() no HUD se faltar o assets/rx01)
var ceu                                  # ceu.gd (null sem assets/rx01/ceu)
var cam_piloto                           # camera_piloto.gd: efeitos de velocidade e olhar livre
# órbita da câmera de corrida pelo analógico direito / mouse (melhoria nossa,
# o Forza; camera_orbita.gd). false = só a câmera do jogo
const ORBITA := true
var orbita = CameraOrbita.new()


func _ready() -> void:
	_make_environment()
	terrain = Terrain.new()
	add_child(terrain)
	# casas, arquibancadas, placas, guard-rail, pedras, árvores... do evento
	# Rallycross do RX01 (porta do jogo, objetos_rx01.gd)
	objetos = ObjetosRX01.new()
	objetos.name = "Objetos"
	add_child(objetos)
	objetos.montar()
	# céu do jogo (SkyDome do Environment.xml: nuvens + montanhas, ceu.gd)
	ceu = Ceu.new()
	ceu.name = "Ceu"
	add_child(ceu)
	if not ceu.montar():
		ceu.queue_free()
		ceu = null

	spawn_vehicle(0, spawn_point(), deg_to_rad(SPAWN_YAW))

	cam = Camera3D.new()
	cam.far = 4000.0
	cam.near = 0.1
	cam.fov = 70.0
	add_child(cam)
	cam.current = true
	# a câmera é posta no _process a partir do carro interpolado
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cam.global_position = spawn_point() + Vector3(-8, 4, 0)

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 18)
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(hud)
	fps_label = Label.new()
	fps_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	fps_label.offset_left = -140
	fps_label.offset_right = -16
	fps_label.offset_top = 12
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fps_label.add_theme_font_size_override("font_size", 18)
	fps_label.add_theme_color_override("font_outline_color", Color.BLACK)
	fps_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(fps_label)
	_make_menu(layer)
	cam_piloto = CameraPiloto.new()
	cam_piloto.name = "CameraPiloto"
	add_child(cam_piloto)
	cam_piloto.car = car


## buggies + trucks + extras nossos (menu, V, print_tela); os testes dos
## buggies usam só VEHICLES
static func frota() -> Array:
	return VEHICLES + TRUCKS + EXTRAS


## carro pronto pra entrar na cena (main, print_tela e testes da frota)
static func configurar(c, v: Dictionary) -> void:
	c.asset_dir = v.dir
	c.data_files = dados(v)
	c.points_file = v.points
	c.vehicle_id = v.id
	c.som_pasta = v.get("som", "")
	c.tune_override = v.get("tune", {})
	c.livery_file = v.get("livery", "pintura.png")
	c.tuning_id = v.get("tune_id", "")
	c.motor_escondido = v.get("motor_escondido", false)
	if v.has("fp"):
		c.FP_UP = v.fp[0]
		c.FP_BACK = v.fp[1]
		c.FP_PITCH = v.fp[2]
	c.vehicle_name = "%s (%s)" % [v.name, v.id]
	if v.id.begins_with("TRUCK"):
		c.desligadas = Car.PENDENTES_TRUCK   # trucks: melhorias ligadas aos poucos
	c.desligadas = c.desligadas + v.get("desligar", [])


## arquivos de física do veículo: base da classe + o dele
static func dados(v: Dictionary) -> Array:
	return [v.get("base", BASE_BUGGY), v.data]


func spawn_vehicle(i: int, pos: Vector3, yaw: float) -> void:
	var manual := false
	if car != null:
		manual = car.manual
		car.queue_free()
	veh_idx = i
	var v: Dictionary = frota()[i]
	car = Car.new()
	configurar(car, v)
	car.terrain = terrain
	car.objetos = objetos
	add_child(car)
	car.manual = manual
	car.reset_to(pos, yaw)
	gcams.clear()
	cam_ready = false


func _make_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.52, 0.74)
	sky_mat.sky_horizon_color = Color(0.78, 0.74, 0.66)
	sky_mat.ground_horizon_color = Color(0.62, 0.55, 0.45)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.68, 0.6)
	env.fog_density = 0.0012
	env.fog_sky_affect = 0.15   # sem isso a névoa pinta o céu inteiro de bege

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	# Sun Dir do Environment.xml do RX_01 (12282), passado pro remake
	sun.basis = Basis.looking_at(Terrain.dir_do_jogo(Vector3(0.396, -0.780, 0.483)))
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0
	add_child(sun)


func spawn_point() -> Vector3:
	return Vector3(SPAWN_XZ.x, terrain.height_at(SPAWN_XZ.x, SPAWN_XZ.y) + 1.5, SPAWN_XZ.y)


func _input(event: InputEvent) -> void:
	# Tab antes da interface (senão a lista usa o Tab pra trocar de foco)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_TAB or (menu.visible and event.physical_keycode == KEY_ESCAPE):
			_toggle_menu()
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_F1:
				hud.visible = not hud.visible
			KEY_F2:
				fps_label.visible = not fps_label.visible
			KEY_C:
				_troca_camera()
			KEY_G:
				cam_piloto.ligado = not cam_piloto.ligado
			KEY_R:
				var p: Vector3 = car.global_position
				car.reset_to(Vector3(p.x, terrain.height_at(p.x, p.z) + 1.5, p.z), car.global_rotation.y)
				reset_camera()
			KEY_T:
				car.reset_to(spawn_point(), deg_to_rad(SPAWN_YAW))
				car.limpar_sujeira()        # recomeço da corrida: o jogo zera (0x223db0)
				reset_camera()
			KEY_V:
				_swap_vehicle((veh_idx + 1) % frota().size())
			KEY_F:
				car.flip_model()
			KEY_B:
				car.trocar_volante()
			KEY_N:
				AudioServer.set_bus_mute(0, not AudioServer.is_bus_mute(0))
			KEY_H:
				Farol.ligado = not Farol.ligado
			# ajuste ao vivo da câmera do piloto (1/2 altura, 3/4 distância,
			# 5/6 inclinação, 7/8 campo de visão); os valores aparecem no HUD
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8:
				if cam_mode == 4:
					_ajusta_piloto(event.physical_keycode)
			# ajuste ao vivo do painel (9/0 desce/sobe, -/= esquerda/direita, 1 cm)
			KEY_9, KEY_0, KEY_MINUS, KEY_EQUAL:
				if cam_mode == 4 and car.painel:
					car.painel.mover({KEY_9: Vector2(0, -0.01), KEY_0: Vector2(0, 0.01),
						KEY_MINUS: Vector2(-0.01, 0), KEY_EQUAL: Vector2(0.01, 0)}[event.physical_keycode])
			KEY_ESCAPE:
				get_tree().quit()
	# controle: Select troca a câmera (o A é a embreagem, car.gd)
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_BACK:
		_troca_camera()
	# olhar livre na câmera do piloto e órbita nas de corrida: botão direito
	# do mouse apertado
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		cam_piloto.mouse_botao(event.pressed and cam_mode == 4)
		orbita.mouse_botao(event.pressed and cam_mode <= 1 and ORBITA)
	elif event is InputEventMouseMotion and cam_mode == 4:
		cam_piloto.mouse_arrasto(event.relative)
	elif event is InputEventMouseMotion and cam_mode <= 1:
		orbita.mouse_arrasto(event.relative)


func _troca_camera() -> void:
	cam_mode = (cam_mode + 1) % 5
	orbita.reiniciar()


# ------------------------------------------------------------ menu de carros
var menu: ItemList
var menu_idx := []                       # linha do menu -> índice em frota()


func _make_menu(layer: CanvasLayer) -> void:
	menu = ItemList.new()
	menu.anchor_left = 1.0
	menu.anchor_right = 1.0
	menu.offset_left = -300
	menu.offset_right = -16
	menu.offset_top = 12
	menu.auto_height = true
	menu.add_theme_font_size_override("font_size", 18)
	# ordem da lista do jogo (BUGGY_01..12, TRUCK_01..12), as variações logo
	# depois e os bônus no fim
	var todos := frota()
	var order := range(todos.size())
	order.sort_custom(func(a, b): return [_grupo(todos[a]), todos[a].id, a] < [_grupo(todos[b]), todos[b].id, b])
	for i in order:
		var v: Dictionary = todos[i]
		if v.get("extra", false):
			menu.add_item("Extra. %s" % v.name)
		elif v.get("bonus", false):
			menu.add_item("Bônus. %s" % v.name)
		else:
			menu.add_item("%s%d. %s" % ["Truck " if v.id.begins_with("TRUCK") else "", v.id.to_int(), v.name])
		menu_idx.append(i)
	menu.item_activated.connect(func(row): _swap_vehicle(menu_idx[row]); _toggle_menu())
	menu.item_clicked.connect(func(row, _p, _b): _swap_vehicle(menu_idx[row]); _toggle_menu())
	menu.visible = false
	layer.add_child(menu)


## ordem do menu: jogo, bônus, extras nossos
static func _grupo(v: Dictionary) -> int:
	if v.get("extra", false):
		return 2
	return 1 if v.get("bonus", false) else 0


func _toggle_menu() -> void:
	menu.visible = not menu.visible
	if menu.visible:
		var row := menu_idx.find(veh_idx)
		menu.select(row)
		menu.ensure_current_is_visible()
		menu.grab_focus()
	else:
		menu.release_focus()


func _swap_vehicle(i: int) -> void:
	var p: Vector3 = car.global_position
	spawn_vehicle(i, Vector3(p.x, terrain.height_at(p.x, p.z) + 1.5, p.z), car.global_rotation.y)


func _ajusta_piloto(k: int) -> void:
	match k:
		KEY_1: car.FP_UP -= 0.02
		KEY_2: car.FP_UP += 0.02
		KEY_3: car.FP_BACK -= 0.02
		KEY_4: car.FP_BACK += 0.02
		KEY_5: car.FP_PITCH -= 0.02
		KEY_6: car.FP_PITCH += 0.02
		KEY_7: car.FP_FOV -= 2.0
		KEY_8: car.FP_FOV += 2.0
	car.update_eye()


func _process(delta: float) -> void:
	if car == null:
		return
	_update_camera(delta)
	if ceu:
		ceu.seguir(cam, delta)
	if fps_label.visible:
		var f := Engine.get_frames_per_second()
		fps_label.text = "%d FPS" % f
		fps_label.add_theme_color_override("font_color",
			Color(0.5, 1, 0.5) if f >= 55 else (Color(1, 0.9, 0.3) if f >= 30 else Color(1, 0.4, 0.4)))
	if not hud.visible:
		return
	var kmh: float = car.linear_velocity.length() * 3.6
	var fp := ""
	if cam_mode == 4:
		fp = "\n\npiloto: altura %.2f (1/2)  distância %.2f (3/4)  inclinação %.2f (5/6)  campo de visão %.0f° (7/8)  efeitos %s (G)" % [
			car.FP_UP, car.FP_BACK, car.FP_PITCH, car.FP_FOV, "ligados" if cam_piloto.ligado else "desligados"]
		if car.painel:
			fp += "\npainel: lado %+.2f (-/=)  altura %+.2f (9/0)" % [car.painel.ajuste.x, car.painel.ajuste.y]
	hud.text = "%d km/h   %d mph\nmarcha %s   %d rpm   câmbio %s   sujeira %d%%%s\nfísica: %s (%s)\n\nW/S ou setas: acelerar/frear (parado, segurar S = ré)   A/D: virar   Espaço ou A: embreagem (toque virando e acelerando = Clutch Turn)\nP: pneus portados/antigos   L: lateral jogo/remendo   M: câmbio auto/manual   E/Q: sobe/desce marcha   R: desvirar   T: voltar pro início\nC ou Select: câmera (%s)%s   V: próximo carro   Tab: menu de carros   F: girar o modelo   B: volante (%s)   N: som %s   H: farol %s   F1: esconder tudo   F2: FPS   Esc: sair" % [
		int(kmh), int(kmh / 1.609), car.gear_label(), int(car.rpm), "MANUAL" if car.manual else "AUTO", int(car.sujeira_nivel * 100.0), (" (%s)" % car.sujeira.aviso if car.sujeira and car.sujeira.aviso != "" else ("" if car.sujeira else " (sem assets/fx: rode o fx_jogo)")), car.vehicle_name, ("pneus portados do jogo" if car.use_ported else "pneus antigos") + (", lateral do jogo" if car.lateral_game else ", lateral remendo"), CAM_NAMES[cam_mode],
		" (analógico direito ou botão direito do mouse: girar em volta do carro)" if ORBITA and cam_mode <= 1 else "", car.volante_estilo if car.sw_malha else "do jogo", ("mudo" if AudioServer.is_bus_mute(0) else (car.som.pasta.get_file() if car.som else "sem loops")),
		("ligado" if Farol.ligado else "desligado") if car.farol else "(sem farol no modelo)"]
	hud.text += fp
	var aviso_som: String = SomJogo.aviso()
	if aviso_som != "":
		hud.text += "\n" + aviso_som
	if objetos and objetos.aviso() != "":
		hud.text += "\n" + objetos.aviso()
	hud.text += "\n\nchão: " + _chao()


## material do chão embaixo de cada roda (FE FD TE TD), o WheelJitter, o
## atrito do pneu e o Damping (arrasto do chão) nele
func _chao() -> String:
	var o: Array = car.jit_order
	if o.size() != 4:
		return "?"
	var out := []
	for k in [[0, "FE"], [2, "FD"], [1, "TE"], [3, "TD"]]:
		var w: Dictionary = car.wheels[o[k[0]]]
		out.append("%s %s (tremida %.1f, atrito %.2f, arrasto %.1f)%s" % [k[1], terrain.material_name(w.mat),
			terrain.wheel_jitter(w.mat, car.surface_jitter), w.mu, w.amort, "" if w.hit else " no ar"])
	return "   ".join(out)


const GameCamera := preload("res://game_camera.gd")
const CAM_XML := "res://data/cameras.xml"
const CAM_NAMES := ["perto", "longe", "capô", "para-choque", "piloto"]
var gcams := []                           # câmeras do jogo, uma por modo (0..3)
var cam_ready := false
# a câmera do piloto não existe no jogo; tremer igual à do capô é melhoria nossa
const TREMIDA_PILOTO := true
var jit_piloto
var jit_acc := 0.0                        # passos de 1/60 das câmeras presas


func _make_cameras() -> void:
	var cs: String = frota()[veh_idx].cams
	gcams = [
		GameCamera.load_set(CAM_XML, cs, "FollowOrbitNear"),
		GameCamera.load_set(CAM_XML, cs, "FollowOrbitFar"),
		GameCamera.load_set(CAM_XML, cs, "MountOnHood"),
		GameCamera.load_set(CAM_XML, cs, "MountOnFront"),
	]


func cam_state() -> Dictionary:
	# transform interpolado: é o que aparece na tela (física roda a 50 Hz)
	var xf: Transform3D = car.get_global_transform_interpolated()
	var b := xf.basis.orthonormalized()
	var tp: Vector3 = xf * car.corpo(Vector3.ZERO)   # origem do modelo
	var v: Vector3 = car.linear_velocity
	return {
		"tp": tp, "basis": b, "vel": v, "v_f": v.dot(b.z),
		"speed": v.length(), "chao": car.jitter_chao, "batida": car.batida,
		"air_time": car.air_time, "grounded": car.grounded,
		"ground_n": ground_normal(tp.x, tp.z),
	}


func ground_normal(x: float, z: float) -> Vector3:
	var e := 0.5
	return Vector3(terrain.height_at(x - e, z) - terrain.height_at(x + e, z), 2.0 * e,
		terrain.height_at(x, z - e) - terrain.height_at(x, z + e)).normalized()


func reset_camera() -> void:
	if cam_piloto:
		cam_piloto.car = car
		cam_piloto.reiniciar()
	orbita.reiniciar()
	if gcams.is_empty():
		_make_cameras()
	var s := cam_state()
	for g in gcams:
		if not g.mount:
			g.reset(s, terrain)
	cam_ready = true


func _update_camera(delta: float) -> void:
	if not cam_ready:
		reset_camera()
	var s := cam_state()
	# as câmeras de órbita rodam sempre (como no jogo, trocar não dá tranco)
	for i in 2:
		gcams[i].update(delta, s, terrain)

	# MountOnFront fica dentro da carroceria (no ATV também: Z -0.2), então o
	# jogo não desenha o veículo nela. As rodas continuam.
	car.model_root.visible = cam_mode != 3
	if car.susp_vis:
		car.susp_vis.visible = cam_mode != 3
	# mRenderRider (xml 14837): 0 em On_Hood e On_Front. Na nossa câmera do
	# piloto ele aparece sem o capacete (braços e mãos no volante)
	if car.piloto:
		car.piloto.visible = cam_mode <= 1 or cam_mode == 4
		car.piloto.sem_cabeca = cam_mode == 4

	if cam_mode <= 1:
		gcams[cam_mode].apply(cam, s.tp)
		if ORBITA:
			orbita.passo(delta)
			orbita.aplicar(cam, s.tp, terrain)
		return

	if cam_piloto.car != car:
		cam_piloto.car = car
		cam_piloto.reiniciar()
	cam_piloto.atualizar_tela(cam_mode == 4)
	if cam_mode == 4:
		# primeira pessoa (não é do jogo): nos olhos do piloto, com os efeitos
		# de velocidade e o olhar livre do camera_piloto.gd
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		var bx: Basis = car.get_global_transform_interpolated().basis.orthonormalized()
		cam_piloto.passo_quadro(delta, bx.transposed() * car.linear_velocity, car.angular_velocity.dot(bx.y))
		var fp: Transform3D = cam_piloto.transformada(bx, car.driver_eye(), car.FP_PITCH)
		if TREMIDA_PILOTO:
			if jit_piloto == null:
				jit_piloto = GameCamera.CameraJitter.carregar(CAM_XML, "MountOnHood")
			_passo_tremida(delta, jit_piloto, s)
			var d: Vector3 = GameCamera.CameraJitter.aplicar(-fp.basis.z, jit_piloto.n)
			fp.basis = Basis.looking_at(d, fp.basis.y)
		cam.global_transform = fp
		cam.fov = car.FP_FOV + cam_piloto.fov_extra
		cam.near = car.FP_NEAR
		return

	cam.near = 0.1
	# MountOnHood / MountOnFront: presa no carro, PosOffset no frame do modelo,
	# Orientation.X = inclinação em graus, FOV = zoom fixo
	var g = gcams[cam_mode]
	_passo_tremida(delta, g.jit, s)
	var xf: Transform3D = car.get_global_transform_interpolated()
	var bb := xf.basis.orthonormalized()
	var pos: Vector3 = xf * (car.corpo(Vector3.ZERO) + g.pos_off)
	var o: Vector3 = g.p.get("orient", Vector3.ZERO)
	var fwd := bb.z.rotated(bb.x, deg_to_rad(-o.x))
	fwd = GameCamera.CameraJitter.aplicar(fwd, g.jit.n)
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.global_position = pos
	cam.look_at(pos + fwd * 10.0, bb.y)
	cam.fov = g.fov_deg(g.p.FOV)


## tremida das câmeras presas no passo de 1/60 do jogo
func _passo_tremida(delta: float, j, s: Dictionary) -> void:
	jit_acc += minf(delta, 0.25)
	while jit_acc >= GameCamera.STEP:
		jit_acc -= GameCamera.STEP
		j.passo(GameCamera.STEP, s.speed, s.chao, s.batida)
