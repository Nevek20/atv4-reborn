extends SceneTree
## Reposição do RX01 (pista/corrida.gd caixas + pista/ia.gd repor_em): as 14
## cInstantRespotBox do RALLYCROSS.bin. Larga o jogador dentro de cada caixa
## com a corrida rodando e confere: volta pra linha (menos de 1 m dela), num
## chão com normal.y >= mUprightTolerance, longe dos outros carros
## (mSafePlayerDistance) e fora de qualquer caixa. Confere também que um
## ponto ao lado da caixa (fora dela) não repõe.
## Uso: godot --headless --path . -s res://tests/teste_reposicao.gd

var main
var c
var q := 0
var k := 0
var falhas := 0
var fase := 0
var espera := 0


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _falha(m: String) -> void:
	falhas += 1
	print("FALHA: ", m)


func _physics_process(_dt: float) -> bool:
	q += 1
	if main.car == null or main.corrida == null:
		if q > 300:
			print("teste_reposicao: FALHA (sem corrida)")
			return true
		return false
	c = main.corrida
	match fase:
		0:
			if q < 20:
				return false
			if c.caixas.size() != 14:
				_falha("%d caixas (esperado 14)" % c.caixas.size())
			c.comecar()
			c.comecar()
			c.comecar()             # pula a intro e a descida
			c.t_conta = 0.0
			fase = 1
		1:
			if c.estado != c.CORRENDO:
				return false
			# fora da caixa (ao lado, 3 m além da meia largura): não pode repor
			var cx = c.caixas[0]
			var xf: Transform3D = (cx[0] as Transform3D).affine_inverse()
			var fora: Vector3 = xf * Vector3(cx[1].x + 3.0, 0.0, 0.0)
			if c.na_caixa(fora):
				_falha("ponto fora da caixa contou como dentro")
			fase = 2
		2:
			if k >= c.caixas.size():
				print("teste_reposicao: %d caixas, %d reposições" % [c.caixas.size(), c.reposicoes])
				fase = 9
				return false
			var cx = c.caixas[k]
			var centro: Vector3 = (cx[0] as Transform3D).affine_inverse().origin
			if not c.na_caixa(centro):
				_falha("centro da caixa %d fora dela" % k)
			main.car.reset_to(centro, 0.0)
			main.car.test_input = {"thr": 0.0, "brk": 0.0, "steer": 0.0}
			espera = 0
			fase = 3
		3:
			espera += 1
			if espera < 3:
				return false
			var p: Vector3 = main.car.global_position
			var ia = c.ia
			var dl: float = ia._projetar(p)[1]
			var n: Vector3 = main.ground_normal(p.x, p.z)
			var perto := INF
			for x in ia.rivais:
				perto = minf(perto, Vector2(x.car.global_position.x - p.x, x.car.global_position.z - p.z).length())
			print("caixa %2d: reposto a %.1f m da linha, chão %.3f, rival mais perto %.1f m" % [k, dl, n.y, perto])
			if dl > 1.0:
				_falha("caixa %d: não voltou pra linha (%.1f m)" % [k, dl])
			if n.y < 0.93:
				_falha("caixa %d: chão inclinado (%.3f)" % [k, n.y])
			if perto < 8.0:
				_falha("caixa %d: reposto a %.1f m de um rival (mSafePlayerDistance 8)" % [k, perto])
			if c.na_caixa(p):
				_falha("caixa %d: ficou numa caixa" % k)
			k += 1
			fase = 2
		9:
			c.parar()
			print("teste_reposicao: %s" % ("ok" if falhas == 0 else "FALHA"))
			return true
	return false
