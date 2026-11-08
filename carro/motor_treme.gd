extends Node3D
## Motor e escape tremendo (melhoria nossa, car.gd MOTOR_TREME). No jogo nada
## treme: o motor e o escape são parte da malha Body (sem peça Engine/Exhaust
## nos BuggyCompMap_*, cCompPlace_Body = identidade) e nenhum leitor do rpm
## monta matriz (varredura do exe; vídeo do Sphinx parado no corte: 0 px).
##
## Separação: as peças soltas da Body (pedaços sem vértice em comum com o
## resto) que cabem inteiras no cofre do motor saem pra uma malha própria:
## cofre = atrás do banco (ARSE.z - 0.45) até o escapamento (EXHAUST.z - 0.15)
## ou 0.8 m atrás do eixo traseiro, entre as rodas de trás (|x| < roda - 0.35)
## e de 0.25 a 1.75 m de altura. Ficam de fora a carroceria pintada ("white"),
## pneu ("ban"), preto, banco ("chair"), direção ("STEER"), painéis ("sheet",
## sem textura), luzes ("light" e peças a menos de 10 cm dos pontos
## BRAKE_LIGHT/REVERSE_LIGHT/HEAD_LIGHT: as lanternas mexiam), chapas e
## travessas (espessura < 8 cm e mais de 80 cm), peças grandes (mais de 300
## faces ou 1.6 m), vigas e tubos (até 30 faces, compridos 3x a largura e mais
## de 40 cm; ou até 8 faces e mais de 30 cm), chapas deitadas (menos de 25 cm
## de altura e mais de 0.3 m²). Escape: as peças a menos de 12 cm dos pontos EXHAUST,
## atrás do banco, até 2.2 m (os canos compridos que saem do motor).
## A gêmea espelhada de uma peça que treme também treme. AJUSTES por carro
## corrigem o que a regra erra (achado nos prints com MOTOR_COR=2).
## Carro sem ponto EXHAUST não treme (o Storm ganhou um, car.gd ESCAPE_NOSSO:
## motor escondido, só as ponteiras tremem). Trucks: só o escape (_tipo_escape).
## Movimento (escolha nossa): vibração sorteada, curta e rápida, mais forte
## na lenta (coxim de borracha) e menor no giro alto, quase só na vertical, e
## o balanço do torque: o motor gira em volta do virabrequim (eixo z) puxado
## pela carga, num coxim firme (acelerou ou soltou = um tranco curto que
## assenta sem quicar). O escape só vibra junto: não gira com o motor (preso
## no chassi pelos suportes).

# na câmera de corrida (6 m) 1 pixel é ~8 mm. 6 mm sorteados a cada quadro
# ficou "tremelento" demais (Matheus). Depois, 4 mm filtrados em 30 ms e
# balanço de 3° numa mola mole (3 Hz, 25% do crítico) pareciam peças soltas,
# "desparafusadas" (Matheus, out/2026): o sorteio lento vira um passeio e o
# balanço (4.3° no pico) jogava a ponta do escape (1 m do centro) até 7 cm. Agora
# é um zumbido fino e um tranco seco
const VIB_LENTA := 0.0015         # m na marcha lenta
const VIB_ALTO := 0.0005          # m no corte
const VIB_SUAVE := 0.008          # s: o motor segue o sorteio com essa constante
const VIB_EIXOS := Vector3(0.4, 1.0, 0.15)   # mais na vertical (o pistão sobe e desce)
const PONTA := 0.20               # m: trucks, faces em volta da boca do escape que vibram
const BALANCO_GRAUS := 0.8        # inclinação com carga cheia
const BALANCO_HZ := 7.0           # frequência da mola do coxim
const BALANCO_AMORT := 0.6        # amortecimento (fração do crítico)

# ajustes por carro (conferidos nos prints com MOTOR_COR=2): peça pelo centro
# da caixa dela (frame do modelo, 3 cm de folga). "motor" entra, "fica" sai
const AJUSTES := {
	# o bloco é uma caixa de 8 faces com as polias na textura; o coletor da
	# direita é mais comprido que o da esquerda; travessa fina atrás
	"BUGGY_09": {"motor": [Vector3(0.04, 1.01, -2.18), Vector3(0.26, 0.93, -2.24)],
		"fica": [Vector3(0.00, 0.91, -2.88)]},
	# barra traseira em L e os dois suportes dela: encostam no ponto do escape
	"BUGGY_06": {"fica": [Vector3(0.00, 1.07, -2.99), Vector3(-0.10, 1.08, -2.98), Vector3(0.10, 1.08, -2.98)]},
}

var malha: MeshInstance3D         # peças do motor
var malha_escape: MeshInstance3D  # canos do escape (tremem junto)
var bocas := {}                   # ponto EXHAUST* -> malha da boca (0 fica, 1 motor, 2 escape): fumaca.gd segue
var centro := Vector3.ZERO        # centro do motor (frame do modelo)
var faces := 0
var pecas := 0
var _ang := 0.0
var _vel := 0.0
var _vib := Vector3.ZERO


## tira as peças do cofre da malha da carroceria (mi) e monta a malha delas
## aqui (filho do mesmo pai, mesma posição). false = nada pra tremer
func separar(mi: MeshInstance3D, pontos: Dictionary, id := "", so_escape := false, raio_busca := 0.0) -> bool:
	if not (mi.mesh is ArrayMesh) or not pontos.has("ARSE") or not pontos.has("WHEEL_REAR_LEFT") \
			or not pontos.has("EXHAUST"):
		return false
	var escapes: Array = []
	var luzes: Array = []
	for k in pontos:
		if k.begins_with("EXHAUST"):
			escapes.append(pontos[k])
		elif k.begins_with("BRAKE_LIGHT") or k.begins_with("REVERSE_LIGHT") or k.begins_with("HEAD_LIGHT"):
			luzes.append(pontos[k])
	var mesh: ArrayMesh = mi.mesh
	var lo: Vector3
	var hi: Vector3
	var cof := _cofre(pontos)
	lo = cof[0]
	hi = cof[1]
	# triângulos de todas as superfícies, vértices soldados pela posição
	var pai := {}
	var tri: Array = []               # [superfície, i0, i1, i2, chave]
	var arrs: Array = []
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		arrs.append(a)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var n := ix.size() if ix.size() > 0 else v.size()
		for t in range(0, n - 2, 3):
			var ids := [ix[t], ix[t + 1], ix[t + 2]] if ix.size() > 0 else [t, t + 1, t + 2]
			if raio_busca > 0.0:
				# carro extra (200 mil triângulos): só o que fica perto da boca do
				# escape entra na busca de peças; o resto fica na carroceria
				var longe := true
				for e in escapes:
					if v[ids[0]].distance_squared_to(e) < raio_busca * raio_busca:
						longe = false
						break
				if longe:
					tri.append([s, ids[0], ids[1], ids[2], Vector3i((v[ids[0]] * 10000.0).round()), true])
					continue
			var ks := []
			for i in ids:
				ks.append(Vector3i((v[i] * 10000.0).round()))
			_unir(pai, ks[0], ks[1])
			_unir(pai, ks[0], ks[2])
			tri.append([s, ids[0], ids[1], ids[2], ks[0], false])
	# peças: caixa, faces e material por peça
	var info := {}
	for t in tri:
		if t[5]:
			continue
		var r = _raiz(pai, t[4])
		if not info.has(r):
			info[r] = {"lo": Vector3.INF, "hi": -Vector3.INF, "n": 0, "mat": {}, "d_esc": INF, "d_luz": INF}
		var p: Dictionary = info[r]
		var v: PackedVector3Array = arrs[t[0]][Mesh.ARRAY_VERTEX]
		for k in 3:
			var q: Vector3 = v[t[1 + k]]
			p.lo = p.lo.min(q)
			p.hi = p.hi.max(q)
			for e in escapes:
				p.d_esc = minf(p.d_esc, q.distance_to(e))
			for l in luzes:
				p.d_luz = minf(p.d_luz, q.distance_to(l))
		p.n += 1
		var nome := _nome_mat(mesh, mi, t[0])
		p.mat[nome] = p.mat.get(nome, 0) + 1
	var sai := {}
	var c_lo := Vector3.INF
	var c_hi := -Vector3.INF
	var e_lo := Vector3.INF          # tudo que treme (carro sem motor à mostra: só o escape)
	var e_hi := -Vector3.INF
	var ajuste: Dictionary = AJUSTES.get(id, {})
	for r in info:
		var p: Dictionary = info[r]
		var tipo := _tipo_escape(p) if so_escape else _tipo(p, lo, hi)
		var c: Vector3 = (p.lo + p.hi) * 0.5
		for q in ajuste.get("motor", []):
			if c.distance_to(q) < 0.03:
				tipo = 1
		for q in ajuste.get("fica", []):
			if c.distance_to(q) < 0.03:
				tipo = 0
		if tipo == 0:
			if OS.has_environment("MOTOR_LISTA") and p.d_esc < 0.3:     # perto do escape e ficou
				var d0: Vector3 = p.hi - p.lo
				print("  fica   %3d faces %-26s tam %.2f %.2f %.2f centro (%.2f, %.2f, %.2f) esc %.2f luz %.2f" % [
					p.n, _material(p), d0.x, d0.y, d0.z, (p.lo.x + p.hi.x) / 2, (p.lo.y + p.hi.y) / 2,
					(p.lo.z + p.hi.z) / 2, p.d_esc, p.d_luz])
			continue
		sai[r] = tipo
		pecas += 1
		e_lo = e_lo.min(p.lo)
		e_hi = e_hi.max(p.hi)
		if OS.has_environment("MOTOR_LISTA"):
			var d: Vector3 = p.hi - p.lo
			print("  %s %3d faces %-26s tam %.2f %.2f %.2f centro (%.2f, %.2f, %.2f) esc %.2f luz %.2f" % [
				["", "MOTOR ", "ESCAPE"][tipo], p.n, _material(p), d.x, d.y, d.z,
				(p.lo.x + p.hi.x) / 2, (p.lo.y + p.hi.y) / 2, (p.lo.z + p.hi.z) / 2, p.d_esc, p.d_luz])
		if tipo == 1:
			c_lo = c_lo.min(p.lo)
			c_hi = c_hi.max(p.hi)
	# a gêmea do outro lado (mesmas faces e tamanho, centro com x trocado)
	# treme junto: no Renegade só um dos escapes passava no limite de 12 cm
	for r in info:
		if sai.has(r):
			continue
		var p: Dictionary = info[r]
		if _proibido(_material(p)) or p.d_luz < 0.10:
			continue
		var c: Vector3 = (p.lo + p.hi) * 0.5
		for r2 in sai.keys():
			var q: Dictionary = info[r2]
			var c2: Vector3 = (q.lo + q.hi) * 0.5
			if q.n == p.n and absf(c.x + c2.x) < 0.02 and absf(c.y - c2.y) < 0.02 and absf(c.z - c2.z) < 0.02 \
					and ((p.hi - p.lo) - (q.hi - q.lo)).length() < 0.03:
				sai[r] = sai[r2]
				pecas += 1
				break
	# trucks: a ponta do cano (faces a até PONTA da boca), que quase sempre é a
	# mesma peça da longarina, do para-choque ou da gaiola (Shinto: cano de
	# 1.9 m; Jericho: tubos cromados da caçamba)
	var ponta := {}                   # índice do triângulo -> true
	if so_escape:
		var proib := {}
		for s2 in mesh.get_surface_count():
			proib[s2] = _proibido(_nome_mat(mesh, mi, s2))
		for i in tri.size():
			var t: Array = tri[i]
			if t[5] or sai.has(_raiz(pai, t[4])) or proib[t[0]] or info[_raiz(pai, t[4])].d_luz < 0.10:
				continue
			var v: PackedVector3Array = arrs[t[0]][Mesh.ARRAY_VERTEX]
			var c3: Vector3 = (v[t[1]] + v[t[2]] + v[t[3]]) / 3.0
			for e in escapes:
				if c3.distance_to(e) < PONTA:
					ponta[i] = true
					for k in 3:
						e_lo = e_lo.min(v[t[1 + k]])
						e_hi = e_hi.max(v[t[1 + k]])
					break
	if not c_lo.is_finite():
		if not e_lo.is_finite():
			return false
		c_lo = e_lo
		c_hi = e_hi
	centro = (c_lo + c_hi) * 0.5
	# malha de cada boca de escapamento: a face mais perto do ponto (no
	# Renegade o cano é do "escape"; nos outros buggies ele é peça do motor)
	for nome in pontos:
		if not String(nome).begins_with("EXHAUST"):
			continue
		var pe: Vector3 = pontos[nome]
		var perto := INF
		var k := 0
		for i in tri.size():
			var t: Array = tri[i]
			var v: PackedVector3Array = arrs[t[0]][Mesh.ARRAY_VERTEX]
			var d := ((v[t[1]] + v[t[2]] + v[t[3]]) / 3.0).distance_to(pe)
			if d < perto:
				perto = d
				k = 2 if ponta.has(i) else sai.get(_raiz(pai, t[4]), 0)
		bocas[String(nome)] = k if perto < 0.15 else 0
	# duas malhas com as mesmas superfícies e materiais
	var malhas := [ArrayMesh.new(), ArrayMesh.new(), ArrayMesh.new()]   # fica, motor, escape
	var mats := [[], [], []]
	# uma passada só pelos triângulos (antes era uma por superfície, e o
	# PackedInt32Array copiado a cada append: 2 s no Escort, 200 mil triângulos)
	var listas := []                  # [superfície][fica, motor, escape] -> índices
	for s in mesh.get_surface_count():
		listas.append([[], [], []])
	for i in tri.size():
		var t: Array = tri[i]
		var k: int = 2 if ponta.has(i) else (0 if t[5] else sai.get(_raiz(pai, t[4]), 0))
		var l: Array = listas[t[0]][k]
		l.append(t[1])
		l.append(t[2])
		l.append(t[3])
	for s in mesh.get_surface_count():
		var ixs := [PackedInt32Array(listas[s][0]), PackedInt32Array(listas[s][1]), PackedInt32Array(listas[s][2])]
		var m: Material = mi.get_surface_override_material(s)
		if m == null:
			m = mesh.surface_get_material(s)
		for k in 3:
			var ix: PackedInt32Array = ixs[k]
			if ix.is_empty():
				continue
			var a: Array = arrs[s].duplicate()
			a[Mesh.ARRAY_INDEX] = ix
			malhas[k].add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			mats[k].append(m)
			if k > 0:
				faces += ix.size() / 3
	mi.mesh = malhas[0]
	for s in mats[0].size():
		mi.set_surface_override_material(s, mats[0][s])
	malha = _instancia("Motor", malhas[1], mats[1], Color(1, 0, 0))
	malha_escape = _instancia("Escape", malhas[2], mats[2], Color(0, 0.3, 1))
	if OS.get_environment("MOTOR_COR") == "2":
		_cores_por_peca(tri, arrs, pai, sai, info)
	position = mi.position
	return true


## conferência (MOTOR_COR=2): cada peça que treme numa cor, com legenda no console
func _cores_por_peca(tri: Array, arrs: Array, pai: Dictionary, sai: Dictionary, info: Dictionary) -> void:
	const CORES := [Color(1, 0, 0), Color(0, 0.8, 0), Color(0, 0.3, 1), Color(1, 1, 0), Color(1, 0, 1),
		Color(0, 1, 1), Color(1, 0.5, 0), Color(0.5, 0, 1), Color(0.6, 0.3, 0.1), Color(1, 1, 1), Color(0.1, 0.1, 0.1), Color(1, 0.6, 0.7)]
	const NOMES := ["vermelho", "verde", "azul", "amarelo", "magenta", "ciano", "laranja", "roxo", "marrom", "branco", "preto", "rosa"]
	for m in [malha, malha_escape]:
		if m:
			m.visible = false
	var k := -1
	var pag := int(OS.get_environment("MOTOR_PAGINA")) if OS.has_environment("MOTOR_PAGINA") else 0
	for r in sai:
		k += 1
		if k < pag * CORES.size() or k >= (pag + 1) * CORES.size():
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for t in tri:
			if _raiz(pai, t[4]) != r:
				continue
			var v: PackedVector3Array = arrs[t[0]][Mesh.ARRAY_VERTEX]
			for j in 3:
				st.add_vertex(v[t[1 + j]])
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		var mat := StandardMaterial3D.new()
		mat.albedo_color = CORES[k % CORES.size()]
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = mat
		add_child(mi)
		var p: Dictionary = info[r]
		var c: Vector3 = (p.lo + p.hi) * 0.5
		print("  peça %2d %-8s %3d faces %-24s centro (%.2f, %.2f, %.2f) tam (%.2f, %.2f, %.2f)%s" % [k, NOMES[k % NOMES.size()],
			p.n, _material(p), c.x, c.y, c.z, p.hi.x - p.lo.x, p.hi.y - p.lo.y, p.hi.z - p.lo.z, ""])


## conferência (print_tela com MOTOR_COR=1): motor vermelho, escape azul
func _instancia(nome: String, m: ArrayMesh, mats: Array, cor: Color) -> MeshInstance3D:
	if m.get_surface_count() == 0:
		return null
	var mi := MeshInstance3D.new()
	mi.name = nome
	mi.mesh = m
	for s in mats.size():
		var mat: Material = mats[s]
		if OS.has_environment("MOTOR_COR"):
			var mc := StandardMaterial3D.new()
			mc.albedo_color = cor
			mat = mc
		mi.set_surface_override_material(s, mat)
	add_child(mi)
	return mi


static func _cofre(pontos: Dictionary) -> Array:
	var a: Vector3 = pontos["ARSE"]
	var rl: Vector3 = pontos["WHEEL_REAR_LEFT"]
	var z_tras := rl.z - 0.8
	for k in ["EXHAUST", "EXHAUST2"]:
		if pontos.has(k):
			z_tras = minf(z_tras, pontos[k].z)
	z_tras -= 0.15
	var meia := absf(rl.x) - 0.35
	return [Vector3(-meia, 0.25, z_tras), Vector3(meia, 1.75, a.z - 0.45)]


## 0 = fica na carroceria, 1 = motor, 2 = escape
static func _tipo(p: Dictionary, lo: Vector3, hi: Vector3) -> int:
	if p.n >= 300 or _proibido(_material(p)) or p.d_luz < 0.10:
		return 0
	var d: Vector3 = p.hi - p.lo
	var dims := [d.x, d.y, d.z]
	dims.sort()
	# vigas e tubos da estrutura: compridos e finos, com poucas faces (no
	# Bulldog e no Phantom as vigas de sustentação do motor tremiam)
	if p.n <= 30 and dims[2] >= 0.4 and dims[2] >= 3.0 * dims[1]:
		return 0
	# tubo reto ou chapa simples (até 8 faces e mais de 30 cm): os triângulos
	# laterais e as diagonais do Trident, os montantes do Bulldog
	if p.n <= 8 and dims[2] >= 0.3:
		return 0
	# chapa deitada (tampa do cofre do Phantom): baixa e larga
	if d.y < 0.25 and d.x * d.z > 0.3:
		return 0
	var no_cofre := true
	for k in 3:
		if p.lo[k] < lo[k] or p.hi[k] > hi[k]:
			no_cofre = false
	if no_cofre and dims[2] < 1.6 and not (dims[0] < 0.08 and dims[2] > 0.8):
		return 1
	# canos do escape: encostam no ponto EXHAUST, atrás do banco, entre as rodas
	if p.d_esc < 0.12 and dims[2] < 2.2 and p.hi.z <= hi.z and p.lo.x >= lo.x and p.hi.x <= hi.x:
		return 2
	return 0


## trucks (pedido do Matheus, out/2026: "99% só precisam de um toque no
## escapamento"): o motor fica embaixo do capô e a regra do cofre dos buggies
## (atrás do banco) pegava gaiola, estepe e caçamba. Só os canos que encostam
## no ponto EXHAUST, em qualquer lugar do carro (saem do lado ou atrás)
static func _tipo_escape(p: Dictionary) -> int:
	if p.n >= 300 or _proibido(_material(p)) or p.d_luz < 0.10 or p.d_esc >= 0.12:
		return 0
	var d: Vector3 = p.hi - p.lo
	var dims := [d.x, d.y, d.z]
	dims.sort()
	if dims[2] >= 1.2 or (d.y < 0.25 and d.x * d.z > 0.3):    # chassi, para-choque, chapa
		return 0
	return 2


static func _material(p: Dictionary) -> String:
	var maior := ""
	for m in p.mat:
		if maior == "" or p.mat[m] > p.mat[maior]:
			maior = m
	return maior


## pintura, pneu, preto, banco, direção, painéis e luzes nunca tremem
static func _proibido(nome: String) -> bool:
	var n := nome.to_lower()
	var suf := n.get_slice("_", 1) if "_" in n else n
	if suf in ["textura", "white", "ban", "black", "chair", "steer"]:
		return true
	for x in ["sheet", "light", "dakar"]:
		if x in n:
			return true
	return false


static func _nome_mat(mesh: ArrayMesh, mi: MeshInstance3D, s: int) -> String:
	var m := mesh.surface_get_material(s)
	if m and m.resource_name != "":
		return m.resource_name
	var o := mi.get_surface_override_material(s)
	return o.resource_name if o else "sem_textura"


static func _raiz(pai: Dictionary, k):
	var r = k
	while pai.has(r) and pai[r] != r:
		r = pai[r]
	var c = k
	while pai.has(c) and pai[c] != r:
		var prox = pai[c]
		pai[c] = r
		c = prox
	return r


static func _unir(pai: Dictionary, a, b) -> void:
	if not pai.has(a):
		pai[a] = a
	if not pai.has(b):
		pai[b] = b
	var ra = _raiz(pai, a)
	var rb = _raiz(pai, b)
	if ra != rb:
		pai[ra] = rb


## rpm do jogo (1000..8000), carga 0..1 (car.som_carga)
func atualizar(rpm: float, carga: float, dt: float) -> void:
	if dt <= 0.0 or (malha == null and malha_escape == null):
		return
	var r := clampf((rpm - 1000.0) / 7000.0, 0.0, 1.0)
	var amp := lerpf(VIB_LENTA, VIB_ALTO, r)
	var sorteio := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * VIB_EIXOS * amp
	_vib += (sorteio - _vib) * (1.0 - exp(-dt / VIB_SUAVE))
	var vib := _vib
	# mola do coxim: alvo pela carga, tranco quando a carga muda
	var w := TAU * BALANCO_HZ
	var alvo := deg_to_rad(BALANCO_GRAUS) * clampf(carga, 0.0, 1.0)
	var acc := w * w * (alvo - _ang) - 2.0 * BALANCO_AMORT * w * _vel
	_vel += acc * dt
	_ang += _vel * dt
	var giro := Basis(Vector3(0, 0, 1), _ang)
	if malha:
		malha.transform = Transform3D(giro, centro - giro * centro + vib)
	if malha_escape:
		malha_escape.transform = Transform3D(Basis(), vib)
