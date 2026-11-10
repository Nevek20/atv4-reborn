extends Node3D
## Painel funcional (melhoria nossa; car.gd PAINEL). No jogo os relógios são
## textura parada (ponteiro pintado) e a maioria dos buggies não tem painel.
##
## Amador (vehicles.xml Level="Amateur": Mosquito, Inferno, Trident, Sphinx):
## conta-giros e velocímetro de ponteiro, mostrador branco. PRO (Level="Pro"):
## conta-giros, velocímetro, marcha digital e luz de troca, mostrador preto.
##
## Conjunto preso na coluna da direção, atrás do volante, na linha entre o
## olho (câmera do piloto) e a metade de cima do aro, subindo até caber na
## tela (McKenzies). No Phantom o volante tampa tudo: vai do lado direito
## (LADO). AJUSTE por carro por cima, com os números que o Matheus acha na
## câmera do piloto (9/0 desce/sobe, -/= lado, main.gd).
## Os relógios do modelo saem pra o nosso não ficar em cima de outro
## (pedido do Matheus): a placa do relógio do Renegade some e os relógios
## pintados da chapa do Sphinx são repintados com o fundo da chapa. O
## Inferno tem 5 buracos de relógio vazios em losango: os aros e o fundo
## preto saem da malha (APAGAR) e no lugar vão os nossos (DO_MODELO) e 3
## auxiliares de enfeite (AUX: temperatura, óleo, voltagem).
##
## Valores: rpm do motor (car.rpm), velocímetro como o do jogo (1.06 x a
## velocidade pra frente, tests/teste_entrada.gd), marcha do car.gear_label().
## Escalas: conta-giros até o limitador + 1000 (vermelho do limitador),
## velocímetro até a velocidade no limitador na última marcha.
##
## Tudo no frame do modelo do jogo (filho do model_root, como a carroceria).

# buracos de relógio do modelo: tipo -> [centro, normal (pro piloto), diâmetro]
const DO_MODELO := {
	# o grande do meio e o pequeno à direita dele (o da esquerda fica atrás da
	# mão); 13 cm no grande pra não varar o capô (o buraco tem 15.6)
	"BUGGY_02": {"rpm": [Vector3(0.01, 1.377, 0.606), Vector3(0.0, 0.34, -0.94), 0.13],
		"vel": [Vector3(0.154, 1.331, 0.589), Vector3(0.0, 0.34, -0.94), 0.075]},
	# Buccaneer (jipe): os 5 mostradores pintados na willys_jeep_style_panel
	# (posição pelo UV do texel na chapa do painel): os 2 atrás do volante (o
	# vermelho e o azul) viram conta-giros e velocímetro; o grande do meio e os
	# 2 pequenos ficam abaixo da câmera do piloto (AUX)
	"TRUCK_01": {"rpm": [Vector3(-0.546, 1.416, 0.492), Vector3(0.0, -0.21, -0.98), 0.10],
		"vel": [Vector3(-0.32, 1.411, 0.493), Vector3(0.0, -0.21, -0.98), 0.10]},
}
# relógios do modelo trocados pelos nossos NO MESMO LUGAR (pedido do Matheus,
# out/2026): o relógio do jogo sai inteiro (o mostrador e o "pote" em volta,
# também na cópia de dentro da cabine fechada) e o nosso fica no centro, no
# plano e do tamanho do mostrador, com a caixinha preta atrás. Achados pelo UV
# (_mostradores_do_modelo): [textura, centro do mostrador no UV (do Godot, y
# pra baixo), raio no UV, texturas que saem, raio que sai (x o do mostrador)].
# A Stock_truck_clock é um relógio inteiro num hexágono (0.38 = até o meio das
# arestas); no Goliath o relógio é o canto de baixo à esquerda do atlas
# trophy_truck_light (o atlas também é farol: só perto do volante). Maior =
# conta-giros, o da direita = velocímetro, o outro = temperatura (amador) ou a
# marcha (PRO, luz de troca em cima do conta-giros)
# "alinhar" (6º item): os potes do modelo saem tortos, cada um num plano; os
# nossos vão pra um plano só (_alinhar)
const NO_LUGAR := {
	"TRUCK_02": ["stock_truck_clock", Vector2(0.5, 0.5), 0.38, ["stock_truck_clock", "cadilac_shock"], 1.9, "alinhar"],
	"TRUCK_04": ["stock_truck_clock", Vector2(0.5, 0.5), 0.38, ["stock_truck_clock", "cadilac_chrom2"], 1.9],
	"LAZARUS": ["stock_truck_clock", Vector2(0.5, 0.5), 0.38, ["stock_truck_clock", "cadilac_chrom2"], 1.9],
	"TRUCK_11": ["trophy_truck_light", Vector2(0.22, 0.79), 0.19, ["trophy_truck_light"], 2.4],   # Goliath
}
const ESCONDER := {"BUGGY_10": "cadilac_clock"}     # textura da placa do relógio
const REPINTAR := {"BUGGY_04": "_b_2"}              # textura com relógios pintados
# peças do modelo que saem da malha: [parte do nome da textura, [[centro, raio], ...]]
# (Inferno: os losangos dos 5 buracos de relógio, aro chassis_comp03 e fundo preto)
const _BURACOS_INFERNO := [[Vector3(0.01, 1.376, 0.61), 0.1], [Vector3(-0.233, 1.33, 0.593), 0.05],
	[Vector3(-0.137, 1.33, 0.593), 0.05], [Vector3(0.154, 1.33, 0.593), 0.05], [Vector3(0.254, 1.33, 0.593), 0.05]]
# (Renegade: as 3 placas quadradas lisas do painel, um texel da cadilac_engine,
# as caixas pretas atrás delas e do relógio, e o "V" embaixo do volante, 2 barras
# sem textura da coluna até o painel que apareciam entre os nossos relógios;
# "" = superfície sem textura)
const APAGAR := {"BUGGY_02": [["chassis_comp03", _BURACOS_INFERNO], ["_black", _BURACOS_INFERNO]],
	"BUGGY_10": [["cadilac_engine", [[Vector3(-0.573, 1.338, 0.691), 0.06],
		[Vector3(-0.669, 1.338, 0.693), 0.06], [Vector3(-0.3, 1.34, 0.692), 0.06]]],
		["_black", [[Vector3(-0.437, 1.314, 0.7), 0.1], [Vector3(-0.559, 1.322, 0.711), 0.075],
			[Vector3(-0.312, 1.331, 0.718), 0.075]]],
		["", [[Vector3(-0.534, 1.212, 0.837), 0.1], [Vector3(-0.334, 1.212, 0.837), 0.1]]]]}
# relógios auxiliares de enfeite (temperatura, óleo, voltagem; o Matheus pediu
# "que finjam fazer algo") nos buracos livres do Inferno: [tipo, centro, normal, diâmetro]
const AUX := {
	"BUGGY_02": [["temp", Vector3(-0.233, 1.331, 0.589), Vector3(0.0, 0.34, -0.94), 0.075],
		["oleo", Vector3(-0.138, 1.333, 0.59), Vector3(0.0, 0.34, -0.94), 0.075],
		["volt", Vector3(0.254, 1.331, 0.589), Vector3(0.0, 0.34, -0.94), 0.075]],
	# Buccaneer: o grande do meio e os 2 pequenos à direita dele
	"TRUCK_01": [["oleo", Vector3(-0.076, 1.239, 0.515), Vector3(0.0, -0.04, -1.0), 0.15],
		["temp", Vector3(0.084, 1.239, 0.515), Vector3(0.0, -0.04, -1.0), 0.07],
		["volt", Vector3(0.18, 1.239, 0.515), Vector3(0.0, -0.04, -1.0), 0.07]],
}
# auxiliares presos no conjunto (andam com ele): [tipo, posição no plano do
# conjunto em relação ao centro do conta-giros (m, x direita, y cima), diâmetro].
# Renegade: nos círculos que o Matheus marcou no print, um de cada lado
const AUX_CONJUNTO := {
	"BUGGY_10": [["temp", Vector2(-0.105, 0.038), 0.06], ["oleo", Vector2(0.165, 0.032), 0.06]],
}
# ajuste por carro (m, no plano do conjunto): x = pra direita, y = pra cima.
# Números do Matheus com as teclas 9/0 e -/= (out/2026)
const AJUSTE := {
	"BUGGY_10": Vector2(-0.01, -0.06),
	"BUGGY_01": Vector2(0.0, -0.015),
	"BUGGY_03": Vector2(0.0, -0.03),
	"BUGGY_05": Vector2(-0.01, -0.02),
	"BUGGY_07": Vector2(-0.01, -0.05),
	"BUGGY_09": Vector2(0.0, 0.01),
	"BUGGY_08": Vector2(-0.04, 0.0),
	"BUGGY_11": Vector2(-0.02, 0.04),
	"BUGGY_12": Vector2(0.08, 0.01),
	"TRUCK_03": Vector2(0.0, -0.03),      # Shinto
	"TRUCK_05": Vector2(0.0, -0.04),      # Punisher
	"TRUCK_06": Vector2(0.0, -0.03),      # Panther
	"TRUCK_10": Vector2(0.0, -0.04),      # Fireball
	"TRUCK_07": Vector2(-0.04, 0.0),      # Herbst Truggy
	"TRUCK_12": Vector2(0.01, 0.02),      # Chimera
}
# o volante tampa o conjunto: do lado direito dele (Phantom; McKenzies,
# Hurricane e Storm pedidos pelo Matheus)
const LADO := ["BUGGY_06", "BUGGY_08", "BUGGY_11", "BUGGY_12",
	"TRUCK_07", "TRUCK_08", "TRUCK_09", "TRUCK_12"]     # Truggy, TT, Hammerhead, Chimera
const NA_FRENTE := 0.004      # nosso mostrador acima do buraco do modelo (m)
const CAIXA := 0.045          # fundo da caixa preta atrás do mostrador (m)
const DIST := 0.13            # conjunto: além do aro, na linha do olho (m)
const ALTURA_ARO := 0.5       # ponto do aro que o olho mira (x raio, pra cima)
const MARGEM := 4.0           # graus acima da borda de baixo da câmera do piloto
const D_RPM_PRO := 0.095      # diâmetros (m)
const D_VEL_PRO := 0.075
const D_AMADOR := 0.08
const GAP := 0.008
const PONTEIRO_T := 0.05      # inércia do ponteiro (s)
const LEDS := 5
const LED_INICIO := 0.85      # 1º LED a 85% do rpm de troca, último na troca

var car
var pro := false
var mostradores := []         # [desenho 2D, tipo]
var marcha_lcd = null
var leds: Array[StandardMaterial3D] = []
var rpm_max := 9.0
var vel_max := 200.0
var t := 0.0
var fixo := Vector2(-1, -1)   # prints: PAINEL="rpm,km/h" fixa os ponteiros
var ajuste := Vector2.ZERO    # AJUSTE + teclas
var base_ajuste := Basis()
var conjunto: Node3D = null   # o que as teclas movem (o do modelo fica)
var apagadas := 0             # faces do modelo que saíram (APAGAR; os testes descontam)


func montar(c) -> bool:
	car = c
	pro = _nivel(car.vehicle_id) == "Pro"
	if OS.has_environment("PAINEL"):
		var f := OS.get_environment("PAINEL").split(",")
		fixo = Vector2(float(f[0]), float(f[1]) if f.size() > 1 else 0.0)
	var lim: float = car.P.get("lim_on", 8000.0)
	rpm_max = ceilf(lim / 1000.0) + 1.0
	var top: float = 0.0
	if car.gears.size() > 1:
		top = lim * car.P.wheel_r * car.RPM2RAD / (car.gears[car.gears.size() - 1] * car.P.final) * 3.6 * 1.06
	vel_max = maxf(ceilf(top / 20.0) * 20.0, 100.0)
	_tirar_do_modelo()
	var tem: Dictionary = DO_MODELO.get(car.chave(), {})
	var aux: Array = AUX.get(car.chave(), [])
	var na_caixa := false                     # relógio no lugar do do modelo (que saiu)
	if NO_LUGAR.has(car.chave()):
		var regra: Array = NO_LUGAR[car.chave()]
		var r := _mostradores_do_modelo(regra[0], regra[1], regra[2])
		if r.size() >= 2:
			_tirar_relogios(r, regra[3], regra[4])
			na_caixa = true
			tem = {}
			aux = []
			r.sort_custom(func(a, b): return a[2] > b[2])
			if regra.size() > 5 and regra[5] == "alinhar":
				_alinhar(r)
			tem.rpm = r.pop_front()
			r.sort_custom(func(a, b): return a[0].x > b[0].x)     # direita = x maior
			tem.vel = r.pop_front()
			if pro and not r.is_empty():
				tem.marcha = r.pop_front()
			if pro:
				var cr: Array = tem.rpm
				tem.luz = [cr[0] + _base(cr[1]).y * (cr[2] * 0.5 + 0.016), cr[1], 0.0]
			var tipos_aux := ["temp", "oleo", "volt"]
			for i in r.size():
				aux.append([tipos_aux[i % 3]] + r[i])
	var tipos := ["rpm", "vel"] + (["marcha", "luz"] if pro else [])
	var falta := tipos.filter(func(k): return not tem.has(k))
	for k in tem:
		if k in tipos:
			var m: Array = tem[k]
			_instrumento(k, m[0] + m[1].normalized() * NA_FRENTE, m[1], m[2], na_caixa and k != "luz", self,
				m[3] if m.size() > 3 else CAIXA)
	for a in aux:
		_instrumento(a[0], a[1] + a[2].normalized() * NA_FRENTE, a[2], a[3], na_caixa, self,
			a[4] if a.size() > 4 else CAIXA)
	if not falta.is_empty() and not _conjunto(falta) and tem.is_empty():
		return false
	mover(AJUSTE.get(car.chave(), Vector2.ZERO))
	visible = OS.get_environment("SEM_PAINEL") != "1"     # prints: só o que sobrou do modelo
	return true


## desloca o conjunto no plano dele (teclas 9/0 e -/= na câmera do piloto)
func mover(d: Vector2) -> void:
	ajuste += d
	if conjunto:
		conjunto.position = base_ajuste.x * ajuste.x + base_ajuste.y * ajuste.y


## conjunto atrás do volante com o que falta
func _conjunto(falta: Array) -> bool:
	var vol: Dictionary = car.pecas.get("volante", {})
	if not vol.has("centro"):
		return false
	var ce: Vector3 = car.sw_centro()
	var eixo: Vector3 = car.SW_AXIS.normalized()
	var raio: float = vol.get("raio", 0.19)
	var olho := ce + Vector3(0.0, car.FP_UP, -car.FP_BACK)
	var cima := (Vector3.UP - eixo * Vector3.UP.dot(eixo)).normalized()
	var direita := eixo.cross(cima).normalized()
	if direita.x < 0.0:
		direita = -direita
	var d_rpm := D_RPM_PRO if pro else D_AMADOR
	var d_vel := D_VEL_PRO if pro else D_AMADOR
	var h_baixo := d_rpm * 0.5 + 0.01
	var largura := (d_rpm + d_vel + 0.06 + GAP * 2) if pro else (d_rpm + d_vel + GAP)
	# ângulo de um ponto na câmera do piloto (vertical, graus)
	var olhar := Vector3(0.0, -car.FP_PITCH, 1.0).normalized()
	var cima_cam := Vector3(0.0, 1.0, car.FP_PITCH).normalized()
	var ang := func(p: Vector3) -> float:
		var v := p - olho
		return rad_to_deg(atan2(v.dot(cima_cam), v.dot(olhar)))
	var chao: float = -car.FP_FOV * 0.5 + MARGEM
	var ancora := Vector3.ZERO
	var n := Vector3.BACK
	var mira := ce + cima * raio * ALTURA_ARO
	if car.chave() in LADO:
		# do lado direito do aro (o conjunto fica menor de longe: 0.8)
		mira = ce + direita * (raio + 0.02 + largura * 0.25) + cima * raio * 0.2
	var sobe := 0.0
	while sobe <= 0.3:
		var dir := (mira + cima * sobe - olho).normalized()
		ancora = mira + cima * sobe + dir * DIST
		n = -dir
		if ang.call(ancora - _base(n).y * h_baixo) >= chao:
			break
		sobe += 0.01
	var b := _base(n)
	base_ajuste = b
	conjunto = Node3D.new()
	conjunto.name = "Conjunto"
	add_child(conjunto)
	var lugar := {}
	if pro:
		lugar.rpm = ancora
		lugar.vel = ancora + b.x * (d_rpm * 0.5 + GAP + d_vel * 0.5) - b.y * (d_rpm - d_vel) * 0.5
		lugar.marcha = ancora - b.x * (d_rpm * 0.5 + GAP + 0.03) - b.y * (d_rpm * 0.5 - 0.02)
		lugar.luz = ancora + b.y * (d_rpm * 0.5 + 0.014)
	else:
		lugar.rpm = ancora - b.x * (d_rpm * 0.5 + GAP * 0.5)
		lugar.vel = ancora + b.x * (d_vel * 0.5 + GAP * 0.5)
	for k in falta:
		var d: float = {"rpm": d_rpm, "vel": d_vel, "marcha": 0.05, "luz": 0.0}[k]
		_instrumento(k, lugar[k], n, d, true, conjunto)
	for a in AUX_CONJUNTO.get(car.chave(), []):
		_instrumento(a[0], ancora + b.x * a[1].x + b.y * a[1].y, n, a[2], true, conjunto)
	_suporte(ancora, b, ce - eixo * 0.06)
	return true


## mostradores do modelo pela textura e pelo UV: [centro, normal (pro piloto),
## diâmetro] de cada grupo de triângulos ligados com o UV perto do mostrador e
## a até 50 cm do volante (frame do modelo). Centro e tamanho pela conta
## UV -> 3D do maior triângulo do grupo
func _mostradores_do_modelo(tex: String, uvc: Vector2, ruv: float) -> Array:
	var mi: MeshInstance3D = car.body_mi
	if mi == null:
		return []
	var tris: Array = []         # [p0, p1, p2, uv0, uv1, uv2]
	for s in mi.mesh.get_surface_count():
		var m: Material = mi.get_active_material(s)
		if not (m is BaseMaterial3D) or m.albedo_texture == null \
				or not (tex in m.albedo_texture.resource_path.to_lower()):
			continue
		var arr := mi.mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var us: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		if ix.is_empty():
			ix = PackedInt32Array(range(vs.size()))
		for t in range(0, ix.size(), 3):
			var tri := [vs[ix[t]], vs[ix[t + 1]], vs[ix[t + 2]], us[ix[t]], us[ix[t + 1]], us[ix[t + 2]]]
			if _no_mostrador(tri, uvc, ruv):
				tris.append(tri)
	var grupos: Array = []         # [chaves, triângulos]
	for tri in tris:
		var ks := {}
		for i in 3:
			ks[(tri[i] * 1000.0).round()] = true
		var junta := []
		for g in grupos:
			for k in ks:
				if g[0].has(k):
					junta.append(g)
					break
		var novo := [ks, [tri]]
		for g in junta:
			novo[0].merge(g[0])
			novo[1].append_array(g[1])
			grupos.erase(g)
		grupos.append(novo)
	var out := []
	for g in grupos:
		var melhor: Array = []
		var area := 0.0
		for tri in g[1]:
			var a2: float = absf((tri[4] - tri[3]).cross(tri[5] - tri[3]))
			if a2 > area:
				area = a2
				melhor = tri
		if area < 1e-6:
			continue
		var e1: Vector3 = melhor[1] - melhor[0]
		var e2: Vector3 = melhor[2] - melhor[0]
		var f1: Vector2 = melhor[4] - melhor[3]
		var f2: Vector2 = melhor[5] - melhor[3]
		var det := f1.x * f2.y - f1.y * f2.x
		var du := (e1 * f2.y - e2 * f1.y) / det
		var dv := (e2 * f1.x - e1 * f2.x) / det
		var c: Vector3 = melhor[0] + du * (uvc.x - melhor[3].x) + dv * (uvc.y - melhor[3].y)
		var n := du.cross(dv).normalized()
		if n.z > 0.0:
			n = -n                   # pro piloto = -z
		out.append([c, n, 2.0 * ruv * (du.length() + dv.length()) * 0.5])
	return out


## Shockwave (pedido do Matheus, out/2026: "todo torto"): os 3 potes do
## modelo apontam cada um pra um lado (normais até 25° diferentes, a chapa do
## painel virada 21° pra esquerda) e os da ponta ficam 2.6 cm desnivelados.
## Os nossos vão pra um plano só, virado pro olho do piloto e passando pelo
## grande (r[0], que fica onde está); os outros mantêm o x, ficam na mesma
## altura (a média deles) e caem no plano. A caixa preta de cada um vai até a
## chapa do painel (o pote do jogo saía 12 a 13 cm dela), 4º item.
func _alinhar(r: Array) -> void:
	var g: Vector3 = r[0][0]
	var n0: Vector3 = (car.DRIVER_EYE - g).normalized()
	var y := 0.0
	for i in range(1, r.size()):
		y += r[i][0].y
	y /= maxf(r.size() - 1, 1)
	for i in r.size():
		var c: Vector3 = r[i][0]
		if i > 0:
			c.y = y
		c.z = g.z - (n0.x * (c.x - g.x) + n0.y * (c.y - g.y)) / n0.z
		r[i][0] = c
		r[i][1] = n0
		r[i].append(clampf(_ate_a_carroceria(c, -n0) + 0.01, CAIXA, 0.3))


## distância de p até a carroceria na direção dir (Möller-Trumbore nos
## triângulos do body_mi); CAIXA se não bater em nada até 30 cm
func _ate_a_carroceria(p: Vector3, dir: Vector3) -> float:
	var mi: MeshInstance3D = car.body_mi
	var melhor := INF
	for s in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		if ix.is_empty():
			ix = PackedInt32Array(range(vs.size()))
		for t in range(0, ix.size(), 3):
			var a := vs[ix[t]]
			if a.distance_to(p) > 0.6:
				continue
			var e1 := vs[ix[t + 1]] - a
			var e2 := vs[ix[t + 2]] - a
			var h := dir.cross(e2)
			var det := e1.dot(h)
			if absf(det) < 1e-9:
				continue
			var sv := p - a
			var u := sv.dot(h) / det
			if u < 0.0 or u > 1.0:
				continue
			var q := sv.cross(e1)
			var v := dir.dot(q) / det
			if v < 0.0 or u + v > 1.0:
				continue
			var d := e2.dot(q) / det
			if d > 0.005 and d < melhor:
				melhor = d
	return melhor if melhor < 0.3 else CAIXA


## triângulo do mostrador: UV perto do centro do mostrador e perto do volante
func _no_mostrador(tri: Array, uvc: Vector2, ruv: float) -> bool:
	var u: Vector2 = (tri[3] + tri[4] + tri[5]) / 3.0
	var p: Vector3 = (tri[0] + tri[1] + tri[2]) / 3.0
	return u.distance_to(uvc) < ruv * 1.6 and p.distance_to(car.SW_CENTER) < 0.5


## tira da carroceria (e da cópia de dentro da cabine fechada) as faces das
## texturas do relógio do jogo em volta de cada mostrador achado
func _tirar_relogios(mostradores: Array, texturas: Array, k: float) -> void:
	var mi: MeshInstance3D = car.body_mi
	var pontos := []
	for m in mostradores:
		pontos.append([m[0], m[2] * 0.5 * k])
	var malhas := [mi]
	var dentro := mi.get_node_or_null("FaceDeDentro")
	if dentro:
		malhas.append(dentro)
	for tex in texturas:
		for m in malhas:
			var n := _apagar_faces(m, tex, pontos)
			if m == mi:
				apagadas += n


## tira os relógios do modelo (placa do Renegade, pintura da chapa do Sphinx)
func _tirar_do_modelo() -> void:
	var mi: MeshInstance3D = car.body_mi
	if mi == null:
		return
	for s in mi.mesh.get_surface_count():
		var m: Material = mi.get_active_material(s)
		if not (m is BaseMaterial3D) or m.albedo_texture == null:
			continue
		var tp: String = m.albedo_texture.resource_path
		if ESCONDER.has(car.chave()) and ESCONDER[car.chave()] in tp:
			var some := StandardMaterial3D.new()
			some.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			some.albedo_color = Color(0, 0, 0, 0)
			mi.set_surface_override_material(s, some)
		elif REPINTAR.has(car.chave()) and REPINTAR[car.chave()] in tp:
			var m2: BaseMaterial3D = m.duplicate()
			m2.albedo_texture = _sem_relogios(m.albedo_texture)
			mi.set_surface_override_material(s, m2)
	# a carroceria e a cópia de dentro da cabine fechada (car.gd, FaceDeDentro,
	# filha dela no mesmo frame): senão de dentro sobrava o relógio virado
	var malhas := [mi]
	var dentro := mi.get_node_or_null("FaceDeDentro")
	if dentro:
		malhas.append(dentro)
	for ap in APAGAR.get(car.chave(), []):
		for m in malhas:
			var n := _apagar_faces(m, ap[0], ap[1])
			if m == mi:
				apagadas += n



## tira da malha os triângulos de uma textura perto dos pontos (frame do modelo)
static func _apagar_faces(mi: MeshInstance3D, tex: String, pontos: Array) -> int:
	var velha: Mesh = mi.mesh
	var nova := ArrayMesh.new()
	var mats := []
	var saiu := 0
	for s in velha.get_surface_count():
		var arr := velha.surface_get_arrays(s)
		var m: Material = mi.get_active_material(s)
		var tp := ""
		if m is BaseMaterial3D and m.albedo_texture:
			tp = m.albedo_texture.resource_path
		if (tp == "") if tex == "" else (tex.to_lower() in tp.to_lower()):
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			if ix.is_empty():
				ix = PackedInt32Array(range(vs.size()))
			var fica := PackedInt32Array()
			for t in range(0, ix.size(), 3):
				var c := (vs[ix[t]] + vs[ix[t + 1]] + vs[ix[t + 2]]) / 3.0
				var longe := true
				for p in pontos:
					if c.distance_to(p[0]) < p[1]:
						longe = false
						break
				if longe:
					fica.append_array([ix[t], ix[t + 1], ix[t + 2]])
			saiu += (ix.size() - fica.size()) / 3
			if fica.is_empty():
				continue
			arr[Mesh.ARRAY_INDEX] = fica
		nova.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mats.append(m)
	mi.mesh = nova
	for s in mats.size():
		mi.set_surface_override_material(s, mats[s])
	return saiu


## pinta os mostradores (manchas claras grandes) com pixels do fundo da chapa
## (sorteados, pra manter o granulado); os LEDs (pontinhos e vermelhos) ficam. Rodando pelo editor a textura vem comprimida e
## com mipmaps (o import "Detect 3D" liga sozinho): pinta o nível 0 e refaz
## os mipmaps, senão de longe ou de lado a placa mostrava os relógios velhos
static func _sem_relogios(tex: Texture2D) -> Texture2D:
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	var mip := img.has_mipmaps()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var fundo: Array[Color] = []       # pixels escuros da chapa (o granulado dela)
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.get_luminance() < 0.2 and maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b)) < 0.08:
				fundo.append(c)
	if fundo.is_empty():
		fundo.append(Color(0, 0, 0))
	# manchas claras: as grandes são mostradores (disco = parte clara + 5 px, o
	# aro escuro fica fora dela); pequenas e vermelhas FORA dos discos são os
	# LEDs (ficam). Dentro dos discos: pedaços do aro, números e o ponteiro
	var visto := {}
	var pequenas := []
	var relogios := []                 # [centro, raio]
	for y in h:
		for x in w:
			if visto.has(Vector2i(x, y)) or img.get_pixel(x, y).get_luminance() < 0.55:
				continue
			var pilha := [Vector2i(x, y)]
			var mancha := []
			visto[Vector2i(x, y)] = true
			var lo := Vector2i(x, y)
			var hi := Vector2i(x, y)
			while not pilha.is_empty():
				var q: Vector2i = pilha.pop_back()
				mancha.append(q)
				lo = Vector2i(mini(lo.x, q.x), mini(lo.y, q.y))
				hi = Vector2i(maxi(hi.x, q.x), maxi(hi.y, q.y))
				for dq in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var r: Vector2i = q + dq
					if r.x >= 0 and r.y >= 0 and r.x < w and r.y < h and not visto.has(r) \
							and img.get_pixel(r.x, r.y).get_luminance() >= 0.55:
						visto[r] = true
						pilha.append(r)
			if mancha.size() < 20:
				pequenas.append(mancha)
			else:
				relogios.append([Vector2(lo + hi) * 0.5, maxf(hi.x - lo.x, hi.y - lo.y) * 0.5 + 5.0])
	var no_disco := func(p: Vector2) -> bool:
		for rel in relogios:
			if p.distance_to(rel[0]) <= rel[1]:
				return true
		return false
	var protegido := {}
	var leds: Array = []
	for mancha in pequenas:
		var cen := Vector2.ZERO
		for q in mancha:
			cen += Vector2(q)
		if not no_disco.call(cen / mancha.size()):
			leds.append_array(mancha)
	for y in h:
		for x in w:
			var c0 := img.get_pixel(x, y)
			if c0.r - maxf(c0.g, c0.b) > 0.25 and not no_disco.call(Vector2(x, y)):
				leds.append(Vector2i(x, y))
	for q in leds:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				protegido[q + Vector2i(dx, dy)] = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for rel in relogios:
		var cen: Vector2 = rel[0]
		var rr: float = rel[1]
		for py in range(maxi(0, int(cen.y - rr)), mini(h, int(cen.y + rr) + 1)):
			for px in range(maxi(0, int(cen.x - rr)), mini(w, int(cen.x + rr) + 1)):
				if Vector2(px, py).distance_to(cen) <= rr and not protegido.has(Vector2i(px, py)):
					img.set_pixel(px, py, fundo[rng.randi() % fundo.size()])
	if mip:
		img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func atualizar(delta: float) -> void:
	t += delta
	var k := 1.0 - exp(-delta / PONTEIRO_T)
	var v_f: float = car.linear_velocity.dot(car.global_transform.basis.z) * 3.6 * 1.06
	var rpm: float = car.rpm if fixo.x < 0.0 else fixo.x
	if fixo.x >= 0.0:
		v_f = fixo.y
		k = 1.0
	var carga := clampf(rpm / car.P.get("lim_on", 8000.0), 0.0, 1.0)
	var k_aux := 1.0 if fixo.x >= 0.0 else 1.0 - exp(-delta / 0.6)
	for m in mostradores:
		var alvo: float = absf(v_f)
		var kk := k
		match m.tipo:
			"rpm":
				alvo = rpm / 1000.0
			"temp":   # esquenta no primeiro minuto e sobe um pouco com o giro
				alvo = 60.0 + 30.0 * (1.0 - exp(-t / 60.0)) + 8.0 * carga
				kk = k_aux
			"oleo":   # pressão pelo giro
				alvo = 20.0 + 60.0 * carga
				kk = k_aux
			"volt":   # alternador carregando acima da lenta
				alvo = 12.4 if rpm < 1100.0 else 14.1
				kk = k_aux
		var novo: float = m.valor + (alvo - m.valor) * kk
		if absf(novo - m.valor) > 0.0005 * m.maximo:
			m.valor = novo
			m.queue_redraw()
	if marcha_lcd:
		var g: String = car.gear_label()
		if g != marcha_lcd.texto:
			marcha_lcd.texto = g
			marcha_lcd.queue_redraw()
	if not leds.is_empty():
		var troca: float = car.P.get("up_rpm", 7000.0)
		var no_limite: bool = rpm >= car.P.get("lim_on", 8000.0) - 50.0
		var pisca := fmod(t, 0.12) < 0.06
		for i in leds.size():
			var acende: float = troca * (LED_INICIO + (1.0 - LED_INICIO) * i / (leds.size() - 1))
			var on: bool = (rpm >= acende) and (not no_limite or pisca)
			leds[i].emission_energy_multiplier = 2.5 if on else 0.0


# ------------------------------------------------------------------ montagem
## x = direita do jogo (direita de quem olha), y = cima, z = pro olho. Dentro
## do espelho isso dá determinante -1, que o espelho desfaz: o texto sai certo.
static func _base(n: Vector3) -> Basis:
	var z := n.normalized()
	var x := -Vector3.UP.cross(z).normalized()
	var y := (Vector3.UP - z * Vector3.UP.dot(z)).normalized()
	return Basis(x, y, z)


func _instrumento(tipo: String, p: Vector3, n: Vector3, d: float, caixa: bool, pai: Node3D,
		fundo := CAIXA) -> void:
	var no := Node3D.new()
	no.name = "Painel_" + tipo
	no.transform = Transform3D(_base(n), p)
	pai.add_child(no)
	if tipo == "luz":
		_leds(no)
		return
	var tela: Node2D
	var tam := Vector2(d, d)
	if tipo == "marcha":
		tela = Lcd.new()
		tam = Vector2(0.05, 0.036)
		marcha_lcd = tela
	else:
		var m := Mostrador.new()
		m.tipo = tipo
		m.maximo = rpm_max if tipo == "rpm" else vel_max
		m.vermelho = car.P.get("lim_on", 8000.0) / 1000.0 if tipo == "rpm" else -1.0
		match tipo:
			"temp":
				m.minimo = 50.0
				m.maximo = 130.0
				m.vermelho = 115.0
				m.marcas = [[50.0, "C"], [90.0, "90"], [130.0, "H"]]
				m.rotulo = "TEMP °C"
			"oleo":
				m.maximo = 100.0
				m.marcas = [[0.0, "0"], [50.0, "50"], [100.0, "100"]]
				m.rotulo = "ÓLEO psi"
			"volt":
				m.minimo = 8.0
				m.maximo = 16.0
				m.marcas = [[8.0, "8"], [12.0, "12"], [16.0, "16"]]
				m.rotulo = "VOLTS"
		m.valor = m.minimo
		m.preto = pro
		tela = m
		mostradores.append(m)
	var vp := SubViewport.new()
	vp.size = Vector2i(256, int(256 * tam.y / tam.x))
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.add_child(tela)
	no.add_child(vp)
	var q := QuadMesh.new()
	q.size = tam
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = vp.get_texture()
	mat.emission_enabled = true
	mat.emission_texture = vp.get_texture()
	mat.emission_energy_multiplier = 0.35 if tipo != "marcha" else 1.2
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.35
	var face := MeshInstance3D.new()
	face.mesh = q
	face.material_override = mat
	no.add_child(face)
	if tipo != "marcha":
		# aro (cromado no amador, preto no PRO)
		var aro := MeshInstance3D.new()
		var to := TorusMesh.new()
		to.inner_radius = d * 0.5 - 0.001
		to.outer_radius = d * 0.5 + 0.006
		aro.mesh = to
		aro.rotation.x = PI * 0.5
		aro.material_override = _metal(pro)
		no.add_child(aro)
	if caixa:
		var cx := MeshInstance3D.new()
		if tipo == "marcha":
			var bx := BoxMesh.new()
			bx.size = Vector3(tam.x + 0.01, tam.y + 0.01, 0.03)
			cx.mesh = bx
		else:
			var cy := CylinderMesh.new()
			cy.top_radius = d * 0.5 + 0.004
			cy.bottom_radius = d * 0.5 + 0.002
			cy.height = fundo
			cx.mesh = cy
			cx.rotation.x = PI * 0.5
		cx.position = Vector3(0, 0, -0.0015 - (fundo if tipo != "marcha" else 0.045) * 0.5)
		cx.material_override = _preto()
		no.add_child(cx)


func _leds(no: Node3D) -> void:
	const CORES := [Color(0.1, 1, 0.2), Color(0.1, 1, 0.2), Color(1, 0.85, 0.1), Color(1, 0.15, 0.1), Color(1, 0.15, 0.1)]
	var passo := 0.016
	var barra := MeshInstance3D.new()
	var bx := BoxMesh.new()
	bx.size = Vector3(passo * LEDS + 0.006, 0.014, 0.012)
	barra.mesh = bx
	barra.position = Vector3(0, 0, -0.006)
	barra.material_override = _preto()
	no.add_child(barra)
	for i in LEDS:
		var led := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.0045
		s.height = 0.009
		led.mesh = s
		led.position = Vector3((i - (LEDS - 1) * 0.5) * passo, 0, 0.001)
		var m := StandardMaterial3D.new()
		var c: Color = CORES[i * CORES.size() / LEDS]
		m.albedo_color = c.darkened(0.7)
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 0.0
		led.material_override = m
		leds.append(m)
		no.add_child(led)


## suporte do conjunto: uma haste da caixa até a coluna da direção
func _suporte(ancora: Vector3, b: Basis, coluna: Vector3) -> void:
	var de := ancora - b.z * 0.04 - b.y * 0.03
	var v := coluna - de
	if v.length() < 0.02:
		return
	var h := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = 0.008
	cy.bottom_radius = 0.008
	cy.height = v.length()
	h.mesh = cy
	var y := v.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	h.transform = Transform3D(Basis(x, y, x.cross(y)), de + v * 0.5)
	h.material_override = _preto()
	conjunto.add_child(h)


static func _metal(escuro: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.08, 0.08, 0.09) if escuro else Color(0.85, 0.86, 0.88)
	m.metallic = 0.6 if escuro else 1.0
	m.roughness = 0.35 if escuro else 0.18
	return m


static func _preto() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.04, 0.04, 0.045)
	m.roughness = 0.6
	return m


## Level do vehicles.xml (Amateur / Pro)
static func _nivel(id: String) -> String:
	var txt := FileAccess.get_file_as_string("res://data/vehicles.xml")
	var i := txt.find('<Vehicle Name="%s"' % id)
	if i < 0:
		return ""
	var j := txt.find('Level="', i)
	if j < 0 or j > txt.find(">", i):
		return ""
	j += 7
	return txt.substr(j, txt.find('"', j) - j)


# ------------------------------------------------------------------ 2D
## mostrador de ponteiro (256 x 256): 0 embaixo à esquerda, 270° no sentido
## do relógio até o máximo embaixo à direita
class Mostrador extends Node2D:
	var tipo := "rpm"
	var minimo := 0.0
	var maximo := 9.0
	var vermelho := -1.0
	var preto := false
	var valor := 0.0
	var marcas := []              # auxiliares: [valor, texto]
	var rotulo := ""

	func _ang(v: float) -> float:
		return deg_to_rad(135.0 + 270.0 * clampf((v - minimo) / (maximo - minimo), -0.02, 1.04))

	func _draw() -> void:
		var c := Vector2(128, 128)
		var r := 124.0
		var fundo := Color(0.06, 0.06, 0.07) if preto else Color(0.95, 0.95, 0.93)
		var tinta := Color(0.95, 0.95, 0.95) if preto else Color(0.08, 0.08, 0.08)
		var fonte := ThemeDB.fallback_font
		draw_circle(c, r, fundo)
		if vermelho > 0.0:
			draw_arc(c, r - 14, _ang(vermelho), _ang(maximo), 32, Color(0.85, 0.08, 0.05), 12.0)
		if not marcas.is_empty():
			# auxiliar: 8 traços, texto só nas marcas, letras maiores
			for i in 9:
				var a := _ang(minimo + (maximo - minimo) * i / 8.0)
				var dirv := Vector2(cos(a), sin(a))
				draw_line(c + dirv * (r - (24 if i % 2 == 0 else 14)), c + dirv * (r - 4), tinta, 5.0 if i % 2 == 0 else 3.0)
			for mk in marcas:
				var dirv := Vector2(cos(_ang(mk[0])), sin(_ang(mk[0])))
				draw_string(fonte, c + dirv * (r - 50) + Vector2(-30, 12), mk[1], HORIZONTAL_ALIGNMENT_CENTER, 60, 32, tinta)
			# rótulo na metade de cima: embaixo ele caía em cima do C e do H
			draw_string(fonte, c + Vector2(-70, -34), rotulo, HORIZONTAL_ALIGNMENT_CENTER, 140, 24, tinta)
			_ponteiro(c, r)
			return
		var passo := 1.0 if tipo == "rpm" else (20.0 if maximo <= 200.0 else 40.0)
		var n := int(round(maximo / passo))
		for i in n * 2 + 1:
			var v := i * passo * 0.5
			var a := _ang(v)
			var dirv := Vector2(cos(a), sin(a))
			var grande := i % 2 == 0
			draw_line(c + dirv * (r - (22 if grande else 14)), c + dirv * (r - 4), tinta, 4.0 if grande else 2.0)
			if grande:
				var txt := str(int(v))
				var p := c + dirv * (r - 42)
				draw_string(fonte, p + Vector2(-24, 9), txt, HORIZONTAL_ALIGNMENT_CENTER, 48, 24, tinta)
		draw_string(fonte, c + Vector2(-60, 52), "x1000 RPM" if tipo == "rpm" else "km/h",
			HORIZONTAL_ALIGNMENT_CENTER, 120, 18, tinta)
		_ponteiro(c, r)

	func _ponteiro(c: Vector2, r: float) -> void:
		var a := _ang(valor)
		var d := Vector2(cos(a), sin(a))
		var lado := Vector2(-d.y, d.x)
		var ponta := Color(1.0, 0.35, 0.05) if preto else Color(0.85, 0.05, 0.05)
		draw_colored_polygon(PackedVector2Array([c + d * (r - 16), c + lado * 5 - d * 18, c - lado * 5 - d * 18]), ponta)
		draw_circle(c, 12, Color(0.12, 0.12, 0.12))


## marcha digital (LCD âmbar)
class Lcd extends Node2D:
	var texto := "N"

	func _draw() -> void:
		var s := get_viewport_rect().size
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.03, 0.03, 0.02))
		draw_rect(Rect2(Vector2(6, 6), s - Vector2(12, 12)), Color(0.12, 0.09, 0.02))
		draw_string(ThemeDB.fallback_font, Vector2(0, s.y * 0.78), texto, HORIZONTAL_ALIGNMENT_CENTER,
			s.x, int(s.y * 0.8), Color(1.0, 0.62, 0.08))
