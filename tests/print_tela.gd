extends SceneTree
## Tira um print do carro parado na pista, sem abrir o editor.
## "jogo" usa a câmera de corrida portada (a mesma do F5).
## Uso (precisa de tela; na nuvem: xvfb-run -a ... --rendering-driver opengl3):
##   godot --path . -s res://tests/print_tela.gd -- saida.png [lado|tras|frente|jogo|...] [veiculo]
##
## Diagnóstico da suspensão (variáveis de ambiente, todas opcionais). Com
## VISTAS, CURSOS ou MEDIR o carro assenta, congela e tira todos os prints de
## uma vez (paga os ~70 s de carga uma vez só):
##   VISTAS=lado0,frente0,tras0 vistas; os arquivos saem <saida>_<curso>_<vista>.png
##                              (vista terminada em _sc = sem carroceria, ex. lado0_sc)
##   CURSOS=nat,0,max,min       curso x forçado nas 4 rodas (m, + = comprimida):
##                              número, max/min (Maximum/Minimum_position que a
##                              física usa) ou nat (onde a física deixou parado)
##   CURSO=0.2                  atalho pra um curso só
##   CURSO=TEmax/TD0/FE0.3      curso por roda (FE, FD, TE, TD; a que faltar fica nat; no
##                              nome do arquivo "/" vira "-")
##   MEDIR=1                    imprime as medidas de cada canto em cada curso e
##                              salva <saida>_medidas.json (ver _medir/_estatico)
##   CORPO=0                    esconde a carroceria em todas as vistas
##   CAM_MODO=3                 vista "jogo" com outra câmera do main (2 capô, 3 para-choque)
##   VIRA=1                     direção forçada (-1..1, + = esquerda) antes dos
##                              prints (só no print simples, sem VISTAS)
##   VOLANTE_COR=1              pinta o volante solto de vermelho (vista "volante")
##   VOLANTE=kart               troca o estilo do volante gerado (volantes.gd)
##   DESLIGAR=volante_nosso     desliga melhorias (nomes do car._tem) só neste print
##   PILOTO=0                   esconde o piloto (pra ver o volante)
##   VOL_DIST=0.5               vista "volante" mais perto (fração da distância)
##   CAM_OFF=0,1.6,-4 CAM_ALVO=0,1,-2  câmera livre (frame do jogo)
##   CAM_MODELO=1               CAM_OFF/CAM_ALVO no frame do modelo (pontos do jogo, PICK), CAM_FOV=30
##   vista "motor"              de cima e de trás do que treme (com MOTOR_COR=1 ou 2)
##   PICK=x,y;x,y               imprime o triângulo do carro em cada pixel
##   CULL=0                     carroceria com as 2 faces (sem descartar a de trás)
##   COR_VERTICE=0              sem a cor do vértice do jogo (só a textura, como antes)
##   FREIO=1 / FREIO=0          lanterna de freio acesa / apagada (luzes.gd; parado
##                              o jogo segura o freio, então sem isso sai acesa)
##   RE=1 / RE=0                luz de ré acesa / apagada (luzes.gd)
##   FAROL=1 / FAROL=0          farol aceso / apagado (farol.gd)
##   PASTA=res://assets/carros/buggy_02 (pasta com o pecas.json)  PONTOS=res://...
##   RODA_F=res://...  RODA_T=res://...
##                              troca pasta/pontos/rodas sem mexer no main.gd
##                              (teste de hipótese)
## Frames: as vistas (OFFS) e as medidas (MEDIR) estão no frame do carro do
## JOGO (mão esquerda, esquerda do jogo = x < 0); o car.gd põe no Godot pelo
## espelho (car.corpo / car.jogo), onde a esquerda do jogo é +X.
## Exemplo (Inferno, 3 vistas x 4 cursos, com medidas):
##   VISTAS=lado0,frente0,tras0,lado0_sc CURSOS=nat,0,max,min MEDIR=1 xvfb-run -a $GODOT --path . \
##     --rendering-driver opengl3 -s res://tests/print_tela.gd -- /tmp/inf.png lado 4

const Car := preload("res://carro/car.gd")

var frames := 0
var main
var out := "print.png"
var view := "lado"
var veh := 0

# modo diagnóstico
var multi := false
var vistas: PackedStringArray = []
var cursos: PackedStringArray = []
var medir := false
var shots := []                 # [[curso, vista], ...]
var shot_i := 0
var wait := 0
var cur_curso := ""
var nat_x := []
var medidas := {}
var vcache := {}                # Mesh -> PackedVector3Array (frame do modelo)
var body_v := PackedVector3Array()

# posição da câmera em volta do carro, frame do jogo (x > 0 = direita do jogo)
const OFFS := {"lado": Vector3(4.5, 1.2, 0.0), "tras": Vector3(0.0, 1.6, -6.0),
	"frente": Vector3(2.5, 1.0, 5.0), "outro_lado": Vector3(-4.5, 1.2, 0.0),
	"cima": Vector3(0.01, 7.0, 0.0), "tras_baixo": Vector3(1.5, 0.6, -4.0),
	"roda_tras": Vector3(-2.6, 1.0, -0.6), "persegue": Vector3(0.0, 2.3, -6.5),
	"frente_esq": Vector3(-3.5, 2.0, 4.5), "garagem_lado": Vector3(-5.0, 1.0, 0.6),
	"garagem_tras": Vector3(-3.2, 1.3, -4.6), "roda_tras_dentro": Vector3(0.0, 0.3, -0.8),
	# diagnóstico: lado (direita do jogo), frente e trás retos e baixos
	"lado0": Vector3(6.2, 0.7, 0.0), "outro_lado0": Vector3(-6.2, 0.7, 0.0),
	"frente0": Vector3(0.0, 0.7, 5.6), "tras0": Vector3(0.0, 0.7, -5.6)}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	if args.size() > 1:
		view = args[1]
	if args.size() > 2:
		veh = int(args[2])
	if OS.has_environment("VISTAS"):
		vistas = OS.get_environment("VISTAS").split(",", false)
	if OS.has_environment("CURSOS"):
		cursos = OS.get_environment("CURSOS").split(",", false)
	elif OS.has_environment("CURSO"):
		cursos = [OS.get_environment("CURSO")]
	medir = OS.get_environment("MEDIR") == "1"
	multi = not vistas.is_empty() or not cursos.is_empty() or medir
	if multi:
		if vistas.is_empty():
			vistas = [view]
		if cursos.is_empty():
			cursos = ["nat"]
		for c in cursos:
			for v in vistas:
				shots.append([c, v])
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _overrides() -> bool:
	for k in ["PASTA", "PONTOS", "RODA_F", "RODA_T", "DESLIGAR"]:
		if OS.has_environment(k):
			return true
	return false


## mesmo que main.spawn_vehicle, mas com as trocas das variáveis de ambiente
func _spawn(i: int) -> void:
	var v: Dictionary = main.frota()[i]
	main.car.queue_free()
	main.veh_idx = i
	var c = Car.new()
	main.configurar(c, v)
	if OS.has_environment("PASTA"):
		c.asset_dir = OS.get_environment("PASTA")
	if OS.has_environment("PONTOS"):
		c.points_file = OS.get_environment("PONTOS")
	if OS.has_environment("RODA_F"):
		c.wheel_front_file = OS.get_environment("RODA_F")
	if OS.has_environment("RODA_T"):
		c.wheel_rear_file = OS.get_environment("RODA_T")
	if OS.has_environment("DESLIGAR"):          # DESLIGAR=volante_nosso,luzes: melhorias fora só neste print
		c.desligadas = c.desligadas + Array(OS.get_environment("DESLIGAR").split(","))
	c.terrain = main.terrain
	main.add_child(c)
	main.car = c
	c.reset_to(main.spawn_point(), deg_to_rad(main.SPAWN_YAW))
	main.gcams.clear()
	main.cam_ready = false


func _process(_dt: float) -> bool:
	frames += 1
	if frames == 2 and (veh != main.veh_idx or _overrides()):
		if _overrides():
			_spawn(veh)
		else:
			main.car.queue_free()
			main.spawn_vehicle(veh, main.spawn_point(), deg_to_rad(main.SPAWN_YAW))
	if multi:
		return _process_multi()
	if frames == 3 and OS.has_environment("CAM_MODO"):     # vista "jogo": 0 perto, 1 longe, 2 capô, 3 para-choque, 4 piloto
		main.cam_mode = int(OS.get_environment("CAM_MODO"))
	if frames == 3 and OS.has_environment("VIRA"):
		main.car.test_input = {"thr": 0.0, "brk": 0.0, "steer": float(OS.get_environment("VIRA"))}
	if frames == 90 and view != "jogo":
		_camera(view)
	if frames == 94:
		_chao()
	if frames == 95:
		root.get_viewport().get_texture().get_image().save_png(out)
		print("print salvo em ", out)
		if OS.has_environment("PICK"):
			for xy in OS.get_environment("PICK").split(";", false):
				var q := xy.split(",")
				_pick(Vector2(float(q[0]), float(q[1])))
		return true
	return false


## PICK=x,y;x,y (pixels do print): o triângulo do carro embaixo de cada ponto
## (malha, textura, UV em pixels, ponto e normal no frame do modelo do jogo)
func _pick(px: Vector2) -> void:
	var cam := root.get_viewport().get_camera_3d()
	var o := cam.project_ray_origin(px)
	var d := cam.project_ray_normal(px)
	var melhor := INF
	var info := "nada"
	var car: Node3D = main.car
	var pilha: Array = [car]
	while not pilha.is_empty():
		var n: Node = pilha.pop_back()
		pilha.append_array(n.get_children())
		if not (n is MeshInstance3D) or not n.is_visible_in_tree() or n.mesh == null:
			continue
		if String(n.name).begins_with("Halo"):     # quadrado virado pra câmera no shader: a malha não é onde aparece
			continue
		var mi: MeshInstance3D = n
		var xf := mi.global_transform
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var uvs = arr[Mesh.ARRAY_TEX_UV]
			var ix := PackedInt32Array(range(vs.size()))
			if arr[Mesh.ARRAY_INDEX] != null:
				ix = arr[Mesh.ARRAY_INDEX]
			for t in range(0, ix.size(), 3):
				var a := xf * vs[ix[t]]
				var b := xf * vs[ix[t + 1]]
				var c := xf * vs[ix[t + 2]]
				var hit = Geometry3D.ray_intersects_triangle(o, d, a, b, c)
				if hit == null:
					hit = Geometry3D.ray_intersects_triangle(o, d, a, c, b)
				if hit == null:
					continue
				var dist: float = o.distance_to(hit)
				if dist >= melhor:
					continue
				melhor = dist
				var m: Material = mi.get_active_material(s)
				var tex := ""
				var tam := Vector2(1, 1)
				if m is BaseMaterial3D and m.albedo_texture:
					tex = m.albedo_texture.resource_path.get_file()
					tam = m.albedo_texture.get_size()
				var bc := Geometry3D.get_triangle_barycentric_coords(hit, a, b, c)
				var uv := Vector2.ZERO
				if uvs != null and uvs.size() > 0:
					uv = uvs[ix[t]] * bc.x + uvs[ix[t + 1]] * bc.y + uvs[ix[t + 2]] * bc.z
				var jogo: Vector3 = car.model_root.global_transform.affine_inverse() * hit
				var nrm := (b - a).cross(c - a).normalized()
				info = "%s sup %d %s uv (%.1f, %.1f) jogo (%.3f, %.3f, %.3f) normal (%.2f, %.2f, %.2f)" % [
					mi.name, s, tex, uv.x * tam.x, uv.y * tam.y, jogo.x, jogo.y, jogo.z, nrm.x, nrm.y, nrm.z]
	print("PICK %s: %s" % [px, info])


func _camera(v: String) -> void:
	var car: Node3D = main.car
	if multi:
		# _sc = sem carroceria (só suspensão e rodas). Esconde os filhos: o
		# main.gd mexe no model_root.visible todo quadro
		var corpo := not v.ends_with("_sc") and OS.get_environment("CORPO") != "0"
		for ch in car.model_root.get_children():
			ch.visible = corpo
		v = v.trim_suffix("_sc")
	var t := car.global_transform
	if OS.has_environment("VOLANTE"):
		car.trocar_volante(OS.get_environment("VOLANTE"))
	if OS.get_environment("CULL") == "0" and car.body_mi:
		# diagnóstico: carroceria com as 2 faces (sem descartar a de trás)
		for i in car.body_mi.mesh.get_surface_count():
			var m: Material = car.body_mi.get_active_material(i)
			if m is BaseMaterial3D:
				var m2: BaseMaterial3D = m.duplicate()
				m2.cull_mode = BaseMaterial3D.CULL_DISABLED
				car.body_mi.set_surface_override_material(i, m2)
	if OS.get_environment("PILOTO") == "0" and car.piloto:
		for ch in car.piloto.get_children():
			if ch is Node3D:
				ch.visible = false
	if v.begins_with("piloto"):
		# a mesma câmera de primeira pessoa do jogo (car.first_person_xf),
		# em 16:9 como no F5. FP_FOV/FP_PITCH/FP_UP/FP_BACK/FP_VOLANTE no
		# ambiente trocam os parâmetros (teste de calibração)
		for k in ["FP_FOV", "FP_PITCH", "FP_UP", "FP_BACK"]:
			if OS.has_environment(k):
				car.set(k, float(OS.get_environment(k)))
		if OS.has_environment("FP_VOLANTE"):
			car.FP_VOLANTE = OS.get_environment("FP_VOLANTE") == "1"
		# vista "piloto:UP:BACK:PITCH:FOV" testa uma variante por vista
		var pv := v.split(":")
		if pv.size() == 5:
			car.FP_UP = float(pv[1])
			car.FP_BACK = float(pv[2])
			car.FP_PITCH = float(pv[3])
			car.FP_FOV = float(pv[4])
		car.update_eye()
		# câmera do piloto do main (4): o piloto aparece sem o capacete
		# (CABECA=1 deixa a cabeça, pra conferir onde o olho cai)
		main.cam_mode = 0 if OS.get_environment("CABECA") == "1" else 4
		if car.piloto:
			car.piloto.sem_cabeca = main.cam_mode == 4
			car.piloto.pose(car.rider_s)
			print("olho da câmera x cabeça do piloto (frame do modelo): ",
				car.model_root.global_transform.affine_inverse() * car.first_person_xf().origin, " x ",
				car.model_root.global_transform.affine_inverse() * car.piloto.cabeca_global())
		var camp: Camera3D = root.get_node_or_null("CamPrint")
		if camp == null:
			camp = Camera3D.new()
			camp.name = "CamPrint"
			root.add_child(camp)
		camp.keep_aspect = Camera3D.KEEP_HEIGHT
		camp.global_transform = car.first_person_xf()
		camp.fov = car.FP_FOV
		camp.near = car.FP_NEAR
		camp.current = true
		return
	if v == "volante":
		# de trás do banco, olhando o volante (pinta ele se pedir)
		var c: Vector3 = car.corpo(car.SW_CENTER)
		if OS.get_environment("VOLANTE_COR") == "1" and car.sw_pivot:
			for mi in car.sw_pivot.get_children():
				var m := StandardMaterial3D.new()
				m.albedo_color = Color(1, 0, 0)
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
				for i in mi.mesh.get_surface_count():
					mi.set_surface_override_material(i, m)
		var camv: Camera3D = root.get_node_or_null("CamPrint")
		if camv == null:
			camv = Camera3D.new()
			camv.name = "CamPrint"
			root.add_child(camv)
		camv.fov = 55.0
		camv.near = 0.02
		var dist := float(OS.get_environment("VOL_DIST")) if OS.has_environment("VOL_DIST") else 1.0
		camv.global_position = t * (c + Vector3(0.25, 0.45, -0.75) * car.ESPELHO * dist)
		camv.look_at(t * c, Vector3.UP)
		camv.current = true
		return
	var off: Vector3 = OFFS.get(v, Vector3(4.5, 1.2, 0.0))
	var alvo := Vector3(0, 0.7, 0)
	if v.ends_with("0"):
		alvo = Vector3(0, 0.5, 0)
	if v.begins_with("roda_tras"):
		alvo *= car.ESPELHO
		for w in car.wheels:
			if not w.front and w.left:
				alvo = t.affine_inverse() * w.pivot.global_position
	# CAM_OFF=x,y,z e CAM_ALVO=x,y,z: câmera livre (frame do jogo, como OFFS)
	if OS.has_environment("CAM_OFF"):
		var p := OS.get_environment("CAM_OFF").split(",")
		off = Vector3(float(p[0]), float(p[1]), float(p[2]))
	if OS.has_environment("CAM_ALVO"):
		var p := OS.get_environment("CAM_ALVO").split(",")
		alvo = Vector3(float(p[0]), float(p[1]), float(p[2])) * car.ESPELHO
	if v == "motor" and car.motor_treme:      # de cima e de trás do que treme (motor_treme.centro)
		var cm: Vector3 = car.motor_treme.centro
		off = cm + Vector3(0.9, 0.5, -1.3) + car.model_offset
		alvo = (cm + car.model_offset) * car.ESPELHO
	if OS.get_environment("CAM_MODELO") == "1":     # CAM_OFF/CAM_ALVO no frame do modelo (pontos do jogo)
		off += car.model_offset
		alvo += car.model_offset * car.ESPELHO
	var cam: Camera3D = root.get_node_or_null("CamPrint")
	if cam == null:
		cam = Camera3D.new()
		cam.name = "CamPrint"
		root.add_child(cam)
	cam.fov = float(OS.get_environment("CAM_FOV")) if OS.has_environment("CAM_FOV") else 45.0
	cam.global_position = t * (off * car.ESPELHO)
	cam.look_at(t * alvo, Vector3.UP)
	cam.current = true


## folga de cada roda até o chão (raio do modelo, raycast do centro)
func _chao() -> Dictionary:
	var c = main.car
	var res := {}
	var space: PhysicsDirectSpaceState3D = c.get_world_3d().direct_space_state
	for w in c.wheels:
		var mi: MeshInstance3D = w.spin_node.get_child(0)
		var p: Vector3 = mi.global_position
		var q := PhysicsRayQueryParameters3D.create(p, p + Vector3.DOWN * 3.0)
		q.exclude = [c.get_rid()]
		var hit := space.intersect_ray(q)
		var r: float = mi.get_aabb().size.y * 0.5
		var lp: Vector3 = c.jogo(c.global_transform.affine_inverse() * p)
		var nome := _canto(w)
		print("roda %s modelo (%.4f, %.4f, %.4f) curso %.4f" % [nome, lp.x, lp.y, lp.z, w.x])
		var d := {"curso": w.x, "r_modelo": r, "r_fisica": w.r, "min": w.min, "max": w.max}
		if hit:
			var h: float = p.y - hit.position.y
			print("roda %s: centro %.3f m do chão, raio modelo %.3f, raio física %.3f, folga %.3f" % [
				nome, h, r, w.r, h - r])
			d.altura_centro = h
			d.folga_modelo = h - r
			d.folga_fisica = h - w.r
		res[nome] = d
	return res


## canto no padrão do jogo (E = esquerda do jogo = w.left do car.gd)
func _canto(w: Dictionary) -> String:
	return ("F" if w.front else "T") + ("E" if w.left else "D")


func _process_multi() -> bool:
	var car = main.car
	if frames < 90:
		return false
	if frames == 90:
		medidas.veiculo = main.frota()[veh].name
		medidas.pontos = car.points_file
		medidas.pecas = car.pecas.get("pecas", {})
		medidas.rodas = [car.wheel_front_file, car.wheel_rear_file]
		medidas.chao_nat = _chao()
		# congela: física parada, sem interpolação (as peças vão direto pro lugar)
		car.set_physics_process(false)
		car.freeze = true
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
		car.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		for w in car.wheels:
			nat_x.append(w.x)
		main.hud.visible = false
		if medir:
			_body_verts()
			medidas.estatico = _estatico()
		medidas.cursos = {}
		wait = -1
		return false
	if shot_i >= shots.size():
		if medir:
			var f := FileAccess.open(out.get_basename() + "_medidas.json", FileAccess.WRITE)
			if f:
				f.store_string(JSON.stringify(medidas, "  "))
		print("prints: %d" % shots.size())
		return true
	var s: Array = shots[shot_i]
	if wait < 0:
		if s[0] != cur_curso:
			cur_curso = s[0]
			_apply_curso(cur_curso)
			if medir:
				medidas.cursos[cur_curso] = _medir()
		_camera(s[1])
		wait = 3
		return false
	wait -= 1
	if wait == 0:
		var path := "%s_%s_%s.png" % [out.get_basename(), s[0].replace("/", "-"), s[1].replace(":", "_")]
		root.get_viewport().get_texture().get_image().save_png(path)
		print("print salvo em ", path)
		shot_i += 1
		wait = -1
	return false


func _apply_curso(c: String) -> void:
	var car = main.car
	var por_canto := {}            # "TEmax/TD0/FE0.3": curso por roda
	for p in c.split("/", false):
		if p.length() > 2 and p.substr(0, 2) in ["FE", "FD", "TE", "TD"]:
			por_canto[p.substr(0, 2)] = p.substr(2)
	for i in car.wheels.size():
		var w: Dictionary = car.wheels[i]
		var ci: String = por_canto.get(_canto(w), "nat") if not por_canto.is_empty() else c
		match ci:
			"nat":
				w.x = nat_x[i]
			"max":
				w.x = w.max
			"min":
				w.x = w.min
			_:
				w.x = float(ci)
	car._update_visuals(0.0, 0.0)
	var txt := []
	for w in car.wheels:
		txt.append("%s %.3f" % [_canto(w), w.x])
	print("curso %s: %s" % [c, ", ".join(txt)])


# ------------------------------------------------------------ medidas
func _mesh_verts(mi: MeshInstance3D) -> PackedVector3Array:
	if mi == null or mi.mesh == null:
		return PackedVector3Array()
	if vcache.has(mi.mesh):
		return vcache[mi.mesh]
	var out_v := PackedVector3Array()
	for i in mi.mesh.get_surface_count():
		var a := mi.mesh.surface_get_arrays(i)
		out_v.append_array(a[Mesh.ARRAY_VERTEX])
	vcache[mi.mesh] = out_v
	return out_v


func _body_verts() -> void:
	var car = main.car
	for ch in car.model_root.get_children():
		if ch is MeshInstance3D:
			body_v.append_array(_mesh_verts(ch))


## xf da peça no frame do modelo (a malha já vem nas coordenadas do modelo)
func _xf(mi: MeshInstance3D) -> Transform3D:
	return Transform3D(Basis(), -main.car.model_offset) * mi.transform


static func _nearest(vs: PackedVector3Array, xf: Transform3D, p: Vector3) -> float:
	var best := INF
	for v in vs:
		best = minf(best, (xf * v).distance_squared_to(p))
	return sqrt(best)


## comprimento da malha ao longo de um eixo (projeção dos vértices)
static func _extent(vs: PackedVector3Array, axis: Vector3) -> Vector2:
	var lo := INF
	var hi := -INF
	for v in vs:
		var t := v.dot(axis)
		lo = minf(lo, t)
		hi = maxf(hi, t)
	return Vector2(lo, hi)


## vértices de uma malha dentro do pneu (anel de 0.7 r a r, na largura da roda)
static func _no_pneu(vs: PackedVector3Array, xf: Transform3D, c: Vector3, r: float, hw: float) -> Array:
	var n := 0
	var fundo := 0.0
	for v in vs:
		var p := xf * v
		if absf(p.x - c.x) > hw:
			continue
		var rr := Vector2(p.y - c.y, p.z - c.z).length()
		if rr > 0.7 * r and rr < r:
			n += 1
			fundo = maxf(fundo, r - rr)
	return [n, fundo]


## coisas que não mudam com o curso: a peça bate com os pontos? corpo dentro da roda?
func _estatico() -> Dictionary:
	var car = main.car
	var susp = car.susp_vis
	var res := {}
	for w in car.wheels:
		var nome := _canto(w)
		var d := {}
		var mi: MeshInstance3D = w.spin_node.get_child(0)
		var ab := mi.get_aabb()
		var r := ab.size.y * 0.5
		var hw := ab.size.x * 0.5
		var c: Vector3 = car.jogo(Vector3(w.px, w.y0, w.pz))
		d.ponto_roda = [c.x, c.y, c.z]
		d.r_modelo = r
		d.r_fisica = w.r
		d.largura_roda = ab.size.x
		# carroceria dentro do volume da roda (cilindro inteiro) na pose de repouso
		var n := 0
		var fundo := 0.0
		for v in body_v:
			if absf(v.x - c.x) > hw:
				continue
			var rr := Vector2(v.y - c.y, v.z - c.z).length()
			if rr < r:
				n += 1
				fundo = maxf(fundo, r - rr)
		d.corpo_no_volume_da_roda = n
		d.corpo_fundo = fundo
		res[nome] = d
	if susp == null:
		return res
	for k in susp.corners:
		var nome := _canto(k.wheel)
		var d: Dictionary = res[nome]
		d.pivo = [k.pivot.x, k.pivot.y, k.pivot.z]
		d.fim = [k.end.x, k.end.y, k.end.z]
		d.fim_ate_ponto_roda = (k.end - k.w0).length()
		d.eixo = [k.u.x, k.u.y, k.u.z]
		d.braco_r = k.r
		# a malha da peça passa pelos pontos? (distância ao vértice mais perto)
		if k.frame:
			var vs: PackedVector3Array = _mesh_verts(k.frame)
			d.balanca_pivo_fora = _nearest(vs, Transform3D(), k.pivot)
			d.balanca_fim_fora = _nearest(vs, Transform3D(), k.end)
			d.balanca_pivo_ate_corpo = _nearest(body_v, Transform3D(), k.pivot)
		else:
			d.balanca = "sem peça"
		if k.brake:
			var vb: PackedVector3Array = _mesh_verts(k.brake)
			var cb: Vector3 = k.brake.mesh.get_aabb().get_center()
			d.freio_centro = [cb.x, cb.y, cb.z]
			d.freio_radial = Vector2(cb.y - k.w0.y, cb.z - k.w0.z).length()
			d.freio_fim_fora = _nearest(vb, Transform3D(), k.end)
		if k.has("top"):
			d.amort_topo_ate_corpo = _nearest(body_v, Transform3D(), k.top)
			if k.has("shock") and k.shock:
				var vs2: PackedVector3Array = _mesh_verts(k.shock)
				d.amort_topo_fora = _nearest(vs2, Transform3D(), k.top)
				d.amort_baixo_fora = _nearest(vs2, Transform3D(), k.bottom)
			if k.has("chamber") and k.chamber:
				d.camara_topo_fora = _nearest(_mesh_verts(k.chamber), Transform3D(), k.top)
			if k.has("piston") and k.piston:
				d.haste_baixo_fora = _nearest(_mesh_verts(k.piston), Transform3D(), k.bottom)
			if k.has("chamber") and k.chamber and k.has("piston") and k.piston:
				# quanto a câmara e a haste se sobrepõem no eixo do amortecedor
				var ax: Vector3 = (k.bottom - k.top).normalized()
				var ec: Vector2 = _extent(_mesh_verts(k.chamber), ax)
				var ep: Vector2 = _extent(_mesh_verts(k.piston), ax)
				d.amort_sobreposicao = ec.y - ep.x
			if k.frame:
				d.amort_baixo_ate_balanca = _nearest(_mesh_verts(k.frame), Transform3D(), k.bottom)
	return res


## medidas de cada canto no curso atual (frame do modelo, metros e graus)
func _medir() -> Dictionary:
	var car = main.car
	var susp = car.susp_vis
	var off: Vector3 = car.model_offset
	var res := {}
	for w in car.wheels:
		var nome := _canto(w)
		var c: Vector3 = w.pivot.position - off       # pivô no frame do jogo (espelho)
		var c0: Vector3 = car.jogo(Vector3(w.px, w.y0, w.pz))
		var dd := c - c0
		var side := signf(c0.x)
		var d := {"x": w.x, "centro": [c.x, c.y, c.z],
			"desloc_fora": dd.x * side, "desloc_cima": dd.y, "desloc_frente": dd.z,
			"desloc_horiz": Vector2(dd.x, dd.z).length(),
			"ang_da_vertical": rad_to_deg(atan2(Vector2(dd.x, dd.z).length(), absf(dd.y))) if dd.length() > 1e-4 else 0.0}
		res[nome] = d
	if susp == null:
		return res
	for k in susp.corners:
		var w: Dictionary = k.wheel
		var nome := _canto(w)
		var d: Dictionary = res[nome]
		var dy: float = clampf(w.x, w.min, w.max)
		var th: float = atan(dy / k.r) if k.r > 1e-6 else 0.0
		d.ang_balanca = rad_to_deg(th)
		d.eixo = "(%.2f %.2f %.2f)" % [k.u.x, k.u.y, k.u.z]
		var arm: Transform3D = susp.pose(k, dy, 0.0).frame
		var c: Vector3 = w.pivot.position - off
		d.subiu_pedido = dy
		d.subiu_de_fato = c.y - k.w0.y
		var e: Vector3 = arm * k.end
		d.fim_ate_centro = (e - c).length()
		var mi: MeshInstance3D = w.spin_node.get_child(0)
		var ab := mi.get_aabb()
		var r := ab.size.y * 0.5
		var hw := ab.size.x * 0.5
		if k.frame:
			var xf: Transform3D = _xf(k.frame)
			var vs: PackedVector3Array = _mesh_verts(k.frame)
			d.balanca_ate_centro = _nearest(vs, xf, c)
			var np: Array = _no_pneu(vs, xf, c, r, hw)
			d.balanca_no_pneu = np[0]
			d.balanca_no_pneu_fundo = np[1]
		if k.brake:
			var xb: Transform3D = _xf(k.brake)
			var cb: Vector3 = xb * k.brake.mesh.get_aabb().get_center()
			d.freio_radial = Vector2(cb.y - c.y, cb.z - c.z).length()
			d.freio_axial_fora = (cb.x - c.x) * signf(c.x)
		if k.has("top"):
			var top: Vector3 = k.top
			var bot2: Vector3 = arm * k.bottom
			d.amort_comprimento = (bot2 - top).length()
			d.amort_variacao = (bot2 - top).length() - (k.bottom - top).length()
			if k.frame:
				d.amort_baixo_ate_balanca = _nearest(_mesh_verts(k.frame), _xf(k.frame), bot2)
			var ref: MeshInstance3D = null
			if k.has("shock"):
				ref = k.shock
			elif k.has("piston"):
				ref = k.piston
			if ref:
				d.amort_peca_baixo_ate_ponto = _nearest(_mesh_verts(ref), _xf(ref), bot2)
		var s1 := " sem balança"
		if d.has("balanca_ate_centro"):
			s1 = " balança->centro %.3f no pneu %d (%.3f)" % [d.balanca_ate_centro, d.balanca_no_pneu, d.balanca_no_pneu_fundo]
		var s2 := (" freio radial %.3f" % d.freio_radial) if d.has("freio_radial") else ""
		var s3 := ""
		if d.has("amort_variacao"):
			s3 = " amort %+.3f, ponta->balança %.3f" % [d.amort_variacao, d.get("amort_baixo_ate_balanca", -1.0)]
		print("%s x=%+.3f bal %+6.1f° (%s) centro sobe %+.3f fora %+.3f frente %+.3f (%.0f° da vertical) fim->centro %.3f%s%s%s" % [
			nome, w.x, d.ang_balanca, d.eixo, d.desloc_cima, d.desloc_fora, d.desloc_frente,
			d.ang_da_vertical, d.fim_ate_centro, s1, s2, s3])
	return res
