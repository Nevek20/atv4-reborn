extends Node3D
## Piloto do jogo sentado no carro (cDriverComponentFactory_Seated ->
## AObjectRider 0x1829c8). Malha MALE_HIGH com 47 ossos, esqueleto
## InGame_Mid e a animação STEER_LEFT do Truck_Riding, tirados do jogo pelo
## tools/piloto.py (assets/piloto/piloto.json + piloto.png).
##
## Fica dentro do espelho do carro (frame do jogo), com o osso ROOT em cima do
## ponto ARSE do modelo. O jogo (0x190e50) toca o STEER_LEFT no tempo
## |s| x duração (1/6 s), s = direção suavizada do piloto (0x187060), e
## espelha a pose quando s > 0 (virando pra direita no jogo): cada osso pega
## o do outro lado (tabela de espelho do .skl) com x da posição e y, z da
## rotação trocados de sinal.

var skel: Skeleton3D
var malha: MeshInstance3D
var root_pos := Vector3.ZERO      # osso ROOT na animação: vai em cima do ARSE
# câmera do piloto (nossa, não existe no buggy do jogo): o capacete some (osso
# head encolhido) e ficam o corpo, os braços e as mãos no volante
var sem_cabeca := false
var _cabeca := -1
var _esp := PackedInt32Array()
var _tempos := PackedFloat32Array()
var _dur := 0.0
var _pos: Array = []              # [quadro][osso] Vector3
var _rot: Array = []              # [quadro][osso] Quaternion
var _pais := PackedInt32Array()
var _lp: Array = []               # pose local de agora (posição, rotação)
var _lr: Array = []

# Mãos no volante (melhoria nossa, car.gd MAOS_NO_VOLANTE: no buggy do jogo o
# volante não gira e o piloto não segue ele, mRiderMatchSteer = 0). O centro
# do punho de cada mão fica preso num ponto do aro, que gira com o volante; o
# braço chega lá por IK de dois ossos e o resto do corpo é a animação do jogo.
# O giro do volante sai da própria animação: em cada quadro do STEER_LEFT, a
# média do quanto os dois punhos giraram em volta do centro do aro.
var _vol := false
var _vc := Vector3.ZERO           # centro do aro (frame do esqueleto)
var _ve := Vector3.UP             # eixo do aro
var _giro := PackedFloat32Array() # giro do volante em cada quadro (rad, em volta de _ve)
var _maos: Array = []             # {sup, inf, mao, cent (punho no frame da mão), pega}
var _punho := {}                  # osso da mão -> centro do punho no frame dela
var alcance := 0.0                # conferência: distância até o alvo / braço esticado (> 1 = não alcança)
# onde as mãos pegam o aro, em graus a partir do topo (melhoria nossa; ~9h30
# e 2h30 como no vídeo de referência do Matheus). O quadro 0 do jogo dá 44°
const PEGA_GRAUS := 65.0
# braço natural (melhoria nossa, nov/2026: "braço quebrado", Matheus). Medido
# no teste_volante: o pulso dobrava 23° a 115° em relação à animação do jogo
# (a mão ia sempre com o pulso no eixo do volante e o antebraço do IK chegava
# por outro ângulo) e torcia até 60°.
# ROLA_MAX: quanto a mão pode rolar em volta do aro (o único giro que mantém a
# pegada) pro pulso seguir o antebraço; ROLA_PESO = custo de rolar (rad de
# dobra por rad de giro: sem ele, com o antebraço na linha do aro, o giro
# fica solto e pula de um quadro pro outro)
const ROLA_MAX := 75.0
const ROLA_PESO := 0.12
# e inclinar (em volta do raio do aro: o aro atravessa o punho meio de
# diagonal), até INCLINA_MAX graus; mais caro que rolar
const INCLINA_MAX := 30.0
const INCLINA_PESO := 0.35
# metade da torção da mão vai pro antebraço (sem osso de torção no esqueleto:
# toda no pulso vira "pano torcido")
const TORCAO_ANTEBRACO := 0.5
# cotovelo: entre pra baixo (0°) e COTOVELO_FORA graus pra fora do corpo (a
# animação deixava até 76°, braço de galinha no volante todo). Dentro da faixa
# ele vai onde o antebraço chega na direção que a mão pede (pulso reto)
const COTOVELO_FORA := 55.0
# cotovelo longe da carroceria (car.gd _paredes_do_piloto): pelo menos
# PAREDE_FOLGA da porta (a manga tem ~5 cm); se precisar ele vai pra dentro,
# até COTOVELO_DENTRO graus (Fireball: varava 6.4 cm a porta)
const PAREDE_FOLGA := 0.07
# cotovelo aberto no mínimo isso pra fora (graus; car.gd COTOVELO_MIN_CARRO);
# a porta ainda puxa pra dentro. COT_MIN=graus testa (diagnóstico)
var cotovelo_min := float(OS.get_environment("COT_MIN")) if OS.get_environment("COT_MIN") != "" else 0.0
# por carro (car.gd PAREDE_FOLGA_CARRO); PAREDE=m testa (diagnóstico)
var parede_folga := float(OS.get_environment("PAREDE")) if OS.get_environment("PAREDE") != "" else PAREDE_FOLGA
# a parede vale pros 2 braços (espelhada no plano do volante): no Fireball só
# o cotovelo esquerdo batia na porta e ia pra dentro (-2°) e o direito ficava
# a 56° pra fora: braços diferentes ("o esquerdo mais torto", Matheus, nov/2026)
const PAREDE_SIMETRICA := true
const COTOVELO_DENTRO := 30.0
var paredes := {}                 # car.gd _paredes_do_piloto (frame do esqueleto)
# a solução (giro da mão e cotovelo) é tabelada em TAB_N direções do volante
const TAB_N := 41
const SUAVIZA := 6          # passadas de [1 2 1]/4 na tabela (~1.7 casa)
# pose em C++ (fisica_cpp/src/piloto.cpp, a mesma conta): null = GDScript
var _cpp: RefCounted = null
var _cpp_vol := false          # o C++ foi configurado já com o volante (a tabela)


## (re)copia tudo pro C++ depois de montar (carregar, prender_no_volante)
func _liga_cpp() -> void:
	_cpp = null
	_cpp_vol = false
	if preload("res://carro/carro_base.gd").usar_cpp and ClassDB.class_exists("PilotoCpp"):
		_cpp = ClassDB.instantiate("PilotoCpp")
		if not _cpp.configurar(self):
			_cpp = null
		else:
			_cpp_vol = _vol


## monta tudo a partir de dir/piloto.json; false se o asset não existe
func carregar(dir: String, cull: int) -> bool:
	var arq := dir.path_join("piloto.json")
	if not FileAccess.file_exists(arq):
		return false
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(arq))
	var ossos: Array = d.ossos
	var n := ossos.size()
	skel = Skeleton3D.new()
	add_child(skel)
	var skin := Skin.new()
	var glob: Array = []
	for b in n:
		skel.add_bone(ossos[b].nome)
		var m: Array = ossos[b].inv              # 4x4, translação em 12..14
		var inv := Transform3D(Basis(Vector3(m[0], m[1], m[2]), Vector3(m[4], m[5], m[6]),
			Vector3(m[8], m[9], m[10])), Vector3(m[12], m[13], m[14]))
		skin.add_bind(b, inv)
		glob.append(inv.affine_inverse())
		_esp.append(int(ossos[b].espelho))
		_pais.append(int(ossos[b].pai))
	for b in n:
		var pai: int = ossos[b].pai
		if pai >= 0:
			skel.set_bone_parent(b, pai)
			skel.set_bone_rest(b, glob[pai].affine_inverse() * glob[b])
		else:
			skel.set_bone_rest(b, glob[b])

	# malha: o .srd vem com o triângulo no sentido da normal do jogo (anti-
	# horário de frente); o Godot quer horário
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var p: Array = d.pos
	var q: Array = d.normal
	var t: Array = d.uv
	for i in p.size() / 3:
		pos.append(Vector3(p[3 * i], p[3 * i + 1], p[3 * i + 2]))
		nrm.append(Vector3(q[3 * i], q[3 * i + 1], q[3 * i + 2]).normalized())
		uv.append(Vector2(t[2 * i], t[2 * i + 1]))
	var pes := PackedFloat32Array(d.pesos)
	for i in pes.size() / 4:                     # o jogo soma 254/255 às vezes
		var s := pes[4 * i] + pes[4 * i + 1] + pes[4 * i + 2] + pes[4 * i + 3]
		if s > 0.0:
			for k in 4:
				pes[4 * i + k] /= s
	var tri: Array = d.tris
	var idx := PackedInt32Array()
	for i in tri.size() / 3:
		idx.append_array([tri[3 * i], tri[3 * i + 2], tri[3 * i + 1]])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_BONES] = PackedInt32Array(d.ossos_v)
	arr[Mesh.ARRAY_WEIGHTS] = pes
	arr[Mesh.ARRAY_INDEX] = idx
	# pose de repouso em CUSTOM0/1: a sujeira (sujeira.gd) projeta por ela e
	# fica grudada na roupa (a posição do vertex() já vem animada)
	var rp := PackedFloat32Array()
	var rn := PackedFloat32Array()
	for i in pos.size():
		rp.append_array([pos[i].x, pos[i].y, pos[i].z])
		rn.append_array([nrm[i].x, nrm[i].y, nrm[i].z])
	arr[Mesh.ARRAY_CUSTOM0] = rp
	arr[Mesh.ARRAY_CUSTOM1] = rn
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {},
		(Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		| (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT))
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _textura(dir.path_join("piloto.png"))
	mat.cull_mode = cull
	am.surface_set_material(0, mat)
	malha = MeshInstance3D.new()
	malha.mesh = am
	malha.skin = skin
	skel.add_child(malha)
	malha.skeleton = NodePath("..")

	# animação
	var a: Dictionary = d.steer_left
	_dur = a.dur
	_tempos = PackedFloat32Array(a.tempos)
	for qd in a.quadros:
		var ps: Array = []
		var rs: Array = []
		for o in qd:
			ps.append(Vector3(o[0], o[1], o[2]))
			rs.append(Quaternion(o[3], o[4], o[5], o[6]).normalized())
		_pos.append(ps)
		_rot.append(rs)
	# ROOT no quadro 0 = MAIN_CONTROL x ROOT local (0, 1.1315, 0.3032 no Renegade)
	_cabeca = skel.find_bone("head")
	var raiz := skel.find_bone("ROOT")
	var pai_raiz := skel.get_bone_parent(raiz)
	root_pos = _pos[0][pai_raiz] + _rot[0][pai_raiz] * _pos[0][raiz]
	_lp.resize(n)
	_lr.resize(n)

	# centro de cada punho = média dos vértices da mão (osso principal da mão
	# ou dos dedos) no quadro 0, guardado no frame do osso da mão
	var g0 := _globais_quadro(0)
	var ov := PackedInt32Array(d.ossos_v)
	for nome in ["right_hand", "left_hand"]:
		var mao := skel.find_bone(nome)
		var soma := Vector3.ZERO
		var cnt := 0
		for i in pos.size():
			var o := ov[4 * i]
			if pes[4 * i] < 0.5 or (o != mao and not _desce_de(o, mao)):
				continue
			var v := Vector3.ZERO
			for k in 4:
				if pes[4 * i + k] > 0.0:
					var ob := ov[4 * i + k]
					v += pes[4 * i + k] * (g0[ob] * (glob[ob].affine_inverse() * pos[i]))
			soma += v
			cnt += 1
		if cnt > 0:
			_punho[mao] = g0[mao].affine_inverse() * (soma / cnt)
	pose(0.0)
	_liga_cpp()
	return true


func _desce_de(b: int, ancestral: int) -> bool:
	while b >= 0:
		b = _pais[b]
		if b == ancestral:
			return true
	return false


## transforms globais (frame do esqueleto) de todos os ossos num quadro da animação
func _globais_quadro(k: int) -> Array:
	var g: Array = []
	g.resize(_pais.size())
	for b in _pais.size():
		var t := Transform3D(Basis(_rot[k][b]), _pos[k][b])
		g[b] = t if _pais[b] < 0 else g[_pais[b]] * t
	return g


## liga as mãos no volante: centro, eixo e raio do aro no frame do esqueleto
func prender_no_volante(centro: Vector3, eixo: Vector3, raio: float) -> void:
	if _punho.size() < 2:
		return
	_vc = centro
	_ve = eixo.normalized()
	var g0 := _globais_quadro(0)
	_maos.clear()
	# a mão esquerda pega o aro e a direita é o espelho dela no plano do
	# volante (no quadro 0 do jogo a direita fica a 22° do topo e a esquerda a
	# 44°: na câmera do piloto os braços saíam tortos)
	var esq := skel.find_bone("left_hand")
	var c_esq: Vector3 = g0[esq] * _punho[esq]
	var rel := c_esq - _vc
	rel -= _ve * rel.dot(_ve)
	var no_aro := _vc + rel.normalized() * raio
	# a mão gira (o mínimo) até a linha dos nós dos dedos (indicador ->
	# anelar) ficar ao longo do aro: na animação ela fica 25° a 43° torta e o
	# aro saía de lado do punho (mão "mal encostando")
	var nos: Vector3 = g0[skel.find_bone("left_ring_01")].origin - g0[skel.find_bone("left_index_01")].origin
	var tang := _ve.cross(rel.normalized())
	if tang.dot(nos) < 0.0:
		tang = -tang
	var b_esq: Basis = Basis(Quaternion(nos.normalized(), tang)) * g0[esq].basis
	var pega_esq := Transform3D(b_esq, no_aro - b_esq * _punho[esq])
	# desce pela borda do aro até PEGA_GRAUS do topo, girando junto com ele
	# (a 44° os braços subiam na frente da câmera do piloto)
	var cima := (Vector3.UP - _ve * _ve.y).normalized()
	var ang := cima.signed_angle_to(rel, _ve)
	var gira := Basis(_ve, deg_to_rad(PEGA_GRAUS) * signf(ang) - ang)
	pega_esq = Transform3D(gira, _vc - gira * _vc) * pega_esq
	no_aro = _vc + gira * (no_aro - _vc)
	tang = gira * tang
	# pulso reto atrás do punho: a mão gira em volta da linha dos nós até o
	# pulso ficar na direção do eixo do volante, pro lado do piloto. Nos
	# carros bons ele já ficava assim (-28° a +10°); seguir o antebraço do IK
	# não serve no Renegade (volante perto e deitado: o antebraço fica quase
	# na linha do aro e o pulso ia 7 cm pra dentro, braço em zigue-zague)
	var h: Vector3 = pega_esq.basis * _punho[esq].normalized()
	var phi := (h - tang * h.dot(tang)).signed_angle_to(-_ve, tang)
	var r := Basis(tang, phi)
	pega_esq = Transform3D(r * pega_esq.basis, no_aro + r * (pega_esq.origin - no_aro))
	# reflexão no plano do volante (normal = lado do carro) e, nos ossos, a
	# troca de lado do esqueleto (x negado, como o espelho da animação)
	var nl := _ve.cross(Vector3.UP).normalized()
	var S := Basis(Vector3.RIGHT - 2.0 * nl * nl.x, Vector3.UP - 2.0 * nl * nl.y, Vector3.BACK - 2.0 * nl * nl.z)
	var reflexo := Transform3D(S, 2.0 * nl * nl.dot(_vc))
	var dir_ := skel.find_bone("right_hand")
	var pega_dir := Transform3D(S * pega_esq.basis * Basis.FLIP_X, reflexo * pega_esq.origin)
	pega_dir = pega_dir.translated(reflexo * no_aro - pega_dir * _punho[dir_])
	for lado in [["right_upper_arm", "right_lower_arm", dir_, pega_dir], ["left_upper_arm", "left_lower_arm", esq, pega_esq]]:
		var bi := skel.find_bone(lado[1])
		var bm: int = lado[2]
		# rel0 = mão no frame do antebraço na animação; ax = direção do
		# antebraço (cotovelo -> pulso) no frame da mão: com o pulso reto, a
		# mão no mundo leva ax pra direção do antebraço
		var rel0: Basis = g0[bi].basis.inverse() * g0[bm].basis
		var ax: Vector3 = (g0[bm].basis.inverse() * (g0[bm].origin - g0[bi].origin)).normalized()
		var pega: Transform3D = lado[3]
		var r0: Vector3 = pega * _punho[bm] - _vc
		r0 -= _ve * r0.dot(_ve)
		_maos.append({"sup": skel.find_bone(lado[0]), "inf": bi, "mao": bm,
			"cent": _punho[bm], "pega": pega, "rel0": rel0, "ax": ax,
			"ang0": cima.signed_angle_to(r0, _ve)})
	_giro.clear()
	for k in _tempos.size():
		var gk := _globais_quadro(k)
		var soma := 0.0
		for m in _maos:
			var a0: Vector3 = g0[m.mao] * m.cent - _vc
			var a1: Vector3 = gk[m.mao] * m.cent - _vc
			soma += (a0 - _ve * a0.dot(_ve)).signed_angle_to(a1 - _ve * a1.dot(_ve), _ve)
		_giro.append(soma / _maos.size())
	_vol = true
	_montar_tabela()
	_liga_cpp()


func no_volante() -> bool:
	return _vol


## giro do volante (rad, em volta do eixo do aro) pra direção suavizada s do
## remake, o mesmo que as mãos fazem no STEER_LEFT (espelhado: sinal trocado)
func giro_volante(s: float) -> float:
	if _cpp and _cpp_vol:
		return _cpp.giro_volante(s)
	var kf := _quadro(absf(s) * _dur)
	var g := lerpf(_giro[int(kf.x)], _giro[int(kf.x) + 1], kf.y)
	return -g if -s > 0.0 else g


## quadro e fração no tempo tm do STEER_LEFT
func _quadro(tm: float) -> Vector2:
	var k := 0
	while k < _tempos.size() - 2 and tm > _tempos[k + 1]:
		k += 1
	return Vector2(k, clampf((tm - _tempos[k]) / maxf(_tempos[k + 1] - _tempos[k], 1e-6), 0.0, 1.0))


func _textura(caminho: String) -> Texture2D:
	if ResourceLoader.exists(caminho):
		return load(caminho)
	var img := Image.load_from_file(ProjectSettings.globalize_path(caminho))
	return ImageTexture.create_from_image(img) if img else null


## s = direção suavizada do piloto do remake (car.gd rider_s, + = esquerda);
## no jogo é -s. extra = giro a mais do volante (rad, car.gd treme): as mãos
## acompanham
func pose(s: float, extra := 0.0) -> void:
	if skel == null:
		return
	if _cpp and _cpp.pose(s, extra):
		return
	_anima(s)
	if _vol:
		_segura_volante(giro_volante(s) + extra, s)
	for b in skel.get_bone_count():
		skel.set_bone_pose_position(b, _lp[b])
		skel.set_bone_pose_rotation(b, _lr[b])
	if _cabeca >= 0:
		skel.set_bone_pose_scale(_cabeca, Vector3.ONE * (0.001 if sem_cabeca else 1.0))


## pose da animação STEER_LEFT do jogo pra direção s em _lp/_lr
func _anima(s: float) -> void:
	var s_jogo := -s
	var esp := s_jogo > 0.0
	var kf := _quadro(absf(s_jogo) * _dur)
	var k := int(kf.x)
	var f := kf.y
	for b in skel.get_bone_count():
		var src := _esp[b] if esp else b
		var p: Vector3 = _pos[k][src].lerp(_pos[k + 1][src], f)
		var r: Quaternion = _rot[k][src].slerp(_rot[k + 1][src], f)
		if esp:
			p.x = -p.x
			r = Quaternion(r.x, -r.y, -r.z, r.w)
		_lp[b] = p
		_lr[b] = r


## cada punho no seu ponto do aro, girado com o volante; o braço (ombro ->
## cotovelo -> pulso) chega lá por IK de dois ossos e a mão gira junto com o
## volante. Por cima (braço natural): a mão rola e inclina no aro e o cotovelo
## vai pro lado onde o pulso fica reto; esses 3 ângulos saem da tabela do
## carro (_montar_tabela) interpolada em s. busca = montando a tabela: a
## solução vizinha de cada mão ([Vector3(rola, inclina, cotovelo), ângulo do
## cotovelo sem limite]); devolve as escolhidas
func _segura_volante(giro: float, s: float, busca: Array = []) -> Array:
	var g: Array = []
	g.resize(_pais.size())
	for b in _pais.size():
		var t := Transform3D(Basis(_lr[b]), _lp[b])
		g[b] = t if _pais[b] < 0 else g[_pais[b]] * t
	var rot := Basis(_ve, giro)
	var gira := Transform3D(rot, _vc - rot * _vc)
	var escolhas: Array = []
	for hi in _maos.size():
		var m: Dictionary = _maos[hi]
		var alvo: Transform3D = gira * m.pega
		var sup: int = m.sup
		var inf: int = m.inf
		var mao: int = m.mao
		var a: Vector3 = g[sup].origin
		var b0: Vector3 = g[inf].origin
		var w0: Vector3 = g[mao].origin
		var l1 := a.distance_to(b0)
		var l2 := b0.distance_to(w0)
		# volante longe (5 carros: braço esticado não chega): o ombro avança,
		# girando a clavícula na direção do aro até o pulso alcançar (até 35°)
		var omb: int = _pais[sup]
		var s0: Vector3 = g[omb].origin
		var alc := (l1 + l2) * 0.98
		alcance = maxf(alcance, (alvo.origin - a).length() / (l1 + l2))
		var eixo := (a - s0).cross(alvo.origin - s0)
		if (alvo.origin - a).length() > alc and eixo.length_squared() > 1e-10:
			eixo = eixo.normalized()
			var lo := 0.0
			var hi_ := deg_to_rad(35.0)
			for it in 12:
				var meio := (lo + hi_) * 0.5
				if (alvo.origin - (s0 + Basis(eixo, meio) * (a - s0))).length() > alc:
					lo = meio
				else:
					hi_ = meio
			var q := Basis(eixo, hi_)
			_lr[omb] = (g[_pais[omb]].basis.inverse() * (q * g[omb].basis)).get_rotation_quaternion()
			for o in [omb, sup, inf, mao]:
				g[o] = Transform3D(q * g[o].basis, s0 + q * (g[o].origin - s0))
			a = g[sup].origin
			b0 = g[inf].origin
			w0 = g[mao].origin
		var fora := Vector3(signf(a.x - g[_pais[omb]].origin.x), 0.0, 0.0)
		var punho: Vector3 = alvo * m.cent
		var raio_p := punho - _vc
		raio_p = (raio_p - _ve * raio_p.dot(_ve)).normalized()
		var tg := _ve.cross(raio_p).normalized()
		var ax_m: Vector3 = m.ax
		var sol := Vector3.ZERO
		if busca.size() > hi:
			var achada: Array = _busca_mao(a, l1, l2, alvo, punho, raio_p, tg, ax_m, fora, b0 - a, busca[hi])
			sol = achada[0]
			escolhas.append(achada)
		elif m.has("tab"):
			var tab: PackedVector3Array = m.tab
			var x := clampf((s + 1.0) * 0.5, 0.0, 1.0) * (tab.size() - 1)
			var k0 := mini(int(x), tab.size() - 2)
			sol = tab[k0].lerp(tab[k0 + 1], x - k0)
		var rr := Basis(raio_p, sol.y) * Basis(tg, sol.x)
		alvo = Transform3D(rr * alvo.basis, punho + rr * (alvo.origin - punho))
		var para := alvo.origin - a
		var d := clampf(para.length(), absf(l1 - l2) + 1e-4, l1 + l2 - 1e-4)
		var dir := para.normalized()
		var cot: Vector3
		if m.has("tab") or busca.size() > hi:
			cot = _cotovelo_ang(a, alvo.origin, l1, l2, sol.z, fora, b0 - a)
		else:
			cot = _cotovelo_ang(a, alvo.origin, l1, l2,
				_limita_cotovelo(a, alvo.origin, l1, l2, _angulo_polo(a, alvo.origin, b0 - a, fora, 0.0), fora, b0 - a), fora, b0 - a)
		var r1 := Quaternion((b0 - a).normalized(), (cot - a).normalized())
		var w1: Vector3 = cot + r1 * (w0 - b0)
		var r2 := Quaternion((w1 - cot).normalized(), (a + dir * d - cot).normalized())
		var b_sup: Basis = Basis(r1) * g[sup].basis
		var b_inf: Basis = Basis(r2 * r1) * g[inf].basis
		# parte da torção da mão (em volta do antebraço) vai pro antebraço
		var f := (a + dir * d - cot).normalized()
		var rel0_m: Basis = m.rel0
		var q: Quaternion = (alvo.basis * (b_inf * rel0_m).inverse()).get_rotation_quaternion()
		var tor := wrapf(2.0 * atan2(Vector3(q.x, q.y, q.z).dot(f), q.w), -PI, PI)
		b_inf = Basis(f, tor * TORCAO_ANTEBRACO) * b_inf
		_lr[sup] = (g[_pais[sup]].basis.inverse() * b_sup).get_rotation_quaternion()
		_lr[inf] = (b_sup.inverse() * b_inf).get_rotation_quaternion()
		_lr[mao] = (b_inf.inverse() * alvo.basis).get_rotation_quaternion()
	return escolhas


## folga do cotovelo e até a carroceria pro lado de fora dele (paredes do
## car.gd; INF fora da grade)
func _folga_parede(e: Vector3, fora: Vector3) -> float:
	if paredes.is_empty():
		return INF
	var lado := 1 if fora.x > 0.0 else -1
	var f := _folga_lado(e, lado)
	if PAREDE_SIMETRICA and _vol:
		# o mesmo cotovelo espelhado no plano do volante contra a parede do
		# outro lado: a porta de um lado segura os dois braços igual
		var nl := _ve.cross(Vector3.UP).normalized()
		f = minf(f, _folga_lado(e - 2.0 * nl * nl.dot(e - _vc), -lado))
	return f


func _folga_lado(e: Vector3, lado: int) -> float:
	var passo: Vector2 = paredes.passo
	var n: Vector2i = paredes.n
	var i := floori((e.y - paredes.y0) / passo.x)
	var j := floori((e.z - paredes.z0) / passo.y)
	if i < 0 or j < 0 or i >= n.x or j >= n.y:
		return INF
	var d: PackedFloat32Array = paredes.dist[lado]
	return d[i * n.y + j] - (e.x - paredes.x) * lado


## ângulo do cotovelo final: preso em 0..COTOVELO_FORA e, se o cotovelo fica a
## menos de PAREDE_FOLGA da carroceria, vai pra dentro (até COTOVELO_DENTRO)
func _limita_cotovelo(a: Vector3, w: Vector3, l1: float, l2: float, th: float, fora: Vector3, ref: Vector3) -> float:
	var t := clampf(th, deg_to_rad(cotovelo_min), deg_to_rad(COTOVELO_FORA))
	if paredes.is_empty():
		return t
	var passo := deg_to_rad(5.0)
	while t > -deg_to_rad(COTOVELO_DENTRO) and _folga_parede(_cotovelo_ang(a, w, l1, l2, t, fora, ref), fora) < parede_folga:
		t -= passo
	return t


## melhor (rola, inclina, cotovelo) de uma mão perto da solução vizinha (viz;
## em s = 0 a grade inteira): a mão rola em volta do aro (tg) e inclina em volta
## do raio (raio_p) no punho, e o cotovelo vai onde o antebraço chega na
## direção que a mão pede (preso na faixa do COTOVELO_FORA, contínuo com o do
## vizinho). Custo = dobra do pulso + ROLA_PESO/INCLINA_PESO
func _busca_mao(a: Vector3, l1: float, l2: float, alvo: Transform3D, punho: Vector3, raio_p: Vector3,
		tg: Vector3, ax_m: Vector3, fora: Vector3, ref: Vector3, viz) -> Array:
	var lim := Vector2(deg_to_rad(ROLA_MAX), deg_to_rad(INCLINA_MAX))
	var best: Array = [Vector3.ZERO, 0.0]
	var custo_min := INF
	var centro := Vector2.ZERO
	var passo := Vector2(deg_to_rad(ROLA_MAX) / 6.0, deg_to_rad(INCLINA_MAX) / 2.0)
	var nk := Vector2i(6, 2)
	var polo_viz := _angulo_polo(a, alvo.origin, ref, fora, 0.0)
	if viz != null:
		var vs: Vector3 = viz[0]
		centro = Vector2(vs.x, vs.y)
		passo = Vector2(deg_to_rad(2.0), deg_to_rad(1.5))
		nk = Vector2i(3, 2)
		polo_viz = viz[1]
	for fase in 3:
		var c0 := centro
		for kp in range(-nk.x, nk.x + 1):
			for ki in range(-nk.y, nk.y + 1):
				var ang := (c0 + Vector2(kp * passo.x, ki * passo.y)).clamp(-lim, lim)
				var r := Basis(raio_p, ang.y) * Basis(tg, ang.x)
				var w := punho + r * (alvo.origin - punho)
				var u := (r * alvo.basis) * ax_m
				var bruto := _angulo_polo(a, w, (w - u * l2) - a, fora, polo_viz)
				var th := _limita_cotovelo(a, w, l1, l2, bruto, fora, ref)
				var e := _cotovelo_ang(a, w, l1, l2, th, fora, ref)
				var custo: float = u.angle_to(w - e) + ROLA_PESO * absf(ang.x) + INCLINA_PESO * absf(ang.y)
				if custo < custo_min:
					custo_min = custo
					best = [Vector3(ang.x, ang.y, th), bruto]
					centro = ang
		passo /= 4.0
		nk = Vector2i(3, 2)
	return best


## tabela do braço natural: a solução de cada mão em TAB_N direções do volante
## (-1..1), partindo do volante reto (grade inteira) e andando pros dois lados
## sempre perto da vizinha: os ângulos variam liso com o volante (busca solta
## por quadro trocava de solução e a mão estalava: até 62° e 26 cm por passo
## de 2% do volante)
func _montar_tabela() -> void:
	var n := TAB_N
	var tabs: Array = []
	var brutos: Array = []
	for m in _maos:
		var t := PackedVector3Array()
		t.resize(n)
		tabs.append(t)
		var bt := PackedFloat32Array()
		bt.resize(n)
		brutos.append(bt)
		m.erase("tab")
	var meio := n / 2
	var ordem: Array = [meio]
	for k in range(meio + 1, n):
		ordem.append(k)
	for k in range(meio - 1, -1, -1):
		ordem.append(k)
	for k in ordem:
		var s: float = -1.0 + 2.0 * k / (n - 1)
		var viz: Array = []
		for h in tabs.size():
			var kv: int = k - 1 if k > meio else k + 1
			viz.append(null if k == meio else [tabs[h][kv], brutos[h][kv]])
		_anima(s)
		var sol: Array = _segura_volante(giro_volante(s), s, viz)
		for h in tabs.size():
			tabs[h][k] = sol[h][0]
			brutos[h][k] = sol[h][1]
	# tudo suavizado ao longo do volante: perto do volante todo o braço fica
	# quase esticado, a direção do cotovelo fica mal definida e mudava 70° numa
	# casa da tabela (Fireball)
	for h in _maos.size():
		var t: PackedVector3Array = tabs[h]
		for passada in SUAVIZA:
			var u := t.duplicate()
			for k in range(1, n - 1):
				u[k] = t[k - 1] * 0.25 + t[k] * 0.5 + t[k + 1] * 0.25
			t = u
		_maos[h]["tab"] = t


## ângulo do cotovelo (0 = pra baixo, + = pra fora) pro cotovelo ir na
## direção de ref (em volta da linha ombro -> pulso), contínuo com o perto
## (sem pular de +180° pra -180°). SEM o limite: a tabela guarda esse e o
## limite (0..COTOVELO_FORA) entra no _cotovelo_ang; preso antes, passar por
## "pra cima" virava um pulo de 0° pra 55° (9 cm no Fireball)
func _angulo_polo(a: Vector3, w: Vector3, ref: Vector3, fora: Vector3, perto: float) -> float:
	var dir := (w - a).normalized()
	var baixo := Vector3.DOWN - dir * Vector3.DOWN.dot(dir)
	if baixo.length_squared() < 1e-8:
		return perto
	baixo = baixo.normalized()
	var lado := dir.cross(baixo)
	if lado.dot(fora) < 0.0:
		lado = -lado
	var polo := ref - dir * ref.dot(dir)
	var ang := atan2(polo.dot(lado), polo.dot(baixo))
	return perto + wrapf(ang - perto, -PI, PI)


## cotovelo do IK de dois ossos (ombro a, pulso w) com a direção dada pelo
## ângulo th (0 = pra baixo, + = pra fora do corpo, fora = lado do braço),
## preso em -COTOVELO_DENTRO..COTOVELO_FORA
func _cotovelo_ang(a: Vector3, w: Vector3, l1: float, l2: float, th: float, fora: Vector3, ref: Vector3) -> Vector3:
	var para := w - a
	var d := clampf(para.length(), absf(l1 - l2) + 1e-4, l1 + l2 - 1e-4)
	var dir := para.normalized()
	var baixo := Vector3.DOWN - dir * Vector3.DOWN.dot(dir)
	var polo: Vector3
	if baixo.length_squared() > 1e-8:
		baixo = baixo.normalized()
		var lado := dir.cross(baixo)
		if lado.dot(fora) < 0.0:
			lado = -lado
		var t := clampf(th, -deg_to_rad(COTOVELO_DENTRO), deg_to_rad(COTOVELO_FORA))
		polo = baixo * cos(t) + lado * sin(t)
	else:
		polo = ref - dir * ref.dot(dir)
		if polo.length_squared() < 1e-10:
			polo = dir.cross(_ve)
		polo = polo.normalized()
	var x := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	return a + dir * x + polo * sqrt(maxf(l1 * l1 - x * x, 0.0))


## transforms globais da pose de agora, lidos do esqueleto (o pose() grava
## lá o _lp/_lr, no GDScript ou no C++)
func _globais_agora() -> Array:
	var g: Array = []
	g.resize(_pais.size())
	for b in _pais.size():
		var t := Transform3D(Basis(skel.get_bone_pose_rotation(b)), skel.get_bone_pose_position(b))
		g[b] = t if _pais[b] < 0 else g[_pais[b]] * t
	return g


## conferência (tests/teste_volante.gd): distância de cada punho até o seu
## ponto no aro e do cotovelo até o da animação, na pose de agora (m)
func erro_maos(s: float, extra := 0.0) -> Array:
	var g := _globais_agora()
	# o ponto de cada mão no aro girado com o volante (giro + tremida): a mão
	# não pode escorregar (nov/2026 testamos a mão de fora parando a 40° do
	# topo com o volante girando por baixo: no teclado, volante todo quase
	# sempre, uma mão ficava parada e não tremia junto; o Matheus achou bugado)
	var rot := Basis(_ve, giro_volante(s) + extra)
	var gira := Transform3D(rot, _vc - rot * _vc)
	var out: Array = []
	for m in _maos:
		var alvo: Vector3 = (gira * m.pega) * m.cent
		out.append((g[m.mao] * m.cent).distance_to(alvo))
	return out


## conferência (tests/teste_volante.gd), na pose de agora, por braço
## (direito, esquerdo): ângulo do cotovelo (180 = esticado), dobra e torção do
## pulso em relação à animação do jogo (quadro 0, graus) e pra onde o cotovelo
## aponta (0 = pra baixo, + = pra fora do corpo, - = pra dentro, 180 = pra cima)
func medidas_bracos() -> Array:
	var g := _globais_agora()
	var g0 := _globais_quadro(0)
	var meio: Vector3 = g[skel.find_bone("upper_back")].origin
	var out: Array = []
	for m in _maos:
		var a: Vector3 = g[m.sup].origin
		var c: Vector3 = g[m.inf].origin
		var w: Vector3 = g[m.mao].origin
		var rel: Basis = g[m.inf].basis.inverse() * g[m.mao].basis
		var rel0: Basis = g0[m.inf].basis.inverse() * g0[m.mao].basis
		var d: Quaternion = (rel0.inverse() * rel).get_rotation_quaternion()
		var ax: Vector3 = (rel0.inverse() * (g0[m.inf].basis.inverse() * (g0[m.mao].origin - g0[m.inf].origin))).normalized()
		var tw := ax * Vector3(d.x, d.y, d.z).dot(ax)
		var twist := Quaternion(tw.x, tw.y, tw.z, d.w).normalized()
		var swing := d * twist.inverse()
		var polo := (c - a) - (w - a).normalized() * (c - a).dot((w - a).normalized())
		var fora := Vector3(signf(a.x - meio.x), 0.0, 0.0)
		out.append({"cotovelo": rad_to_deg((a - c).angle_to(w - c)),
			"pulso": rad_to_deg(2.0 * acos(clampf(absf(swing.w), 0.0, 1.0))),
			"torcao": rad_to_deg(2.0 * acos(clampf(absf(twist.w), 0.0, 1.0))),
			"aponta": rad_to_deg(atan2(polo.dot(fora), polo.dot(Vector3.DOWN)))})
	return out


## conferência: cotovelo e mão de cada braço na pose de agora (frame do
## esqueleto), pra medir pulos de um quadro pro outro
func juntas_bracos() -> Array:
	var g := _globais_agora()
	var out: Array = []
	for m in _maos:
		out.append([g[m.inf].origin, g[m.mao].basis.get_rotation_quaternion()])
	return out


## posição do osso da cabeça no mundo (pra conferir a câmera do piloto)
func cabeca_global() -> Vector3:
	return skel.global_transform * skel.get_bone_global_pose(_cabeca).origin
