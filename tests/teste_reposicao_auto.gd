extends SceneTree
## Reposição automática fora das caixas (pista/reposicao.gd, porta do 0x4d3658).
## Confere com a corrida rodando:
##  1. o corredor do AIT: o centro da pista de cada link (+0x5c) cai dentro
##     da largura medida do ponto da linha (o sinal do lado está certo);
##  2. jogador parado 10 m além da borda: "Off Track, Go Back!" a partir de
##     0.2 s, contagem 3-2-1 e reposição em 3.2 s, de volta na pista;
##  3. contramão (velocidade pra trás na pista): "Wrong Way" a partir de
##     0.2 s, vira "Off Track" aos 2.2 s e repõe aos 5.2 s;
##  4. botão (R): a 25 m/s mostra "Too Fast For Respot"; parado repõe.
## Uso: godot --headless --path . -s res://tests/teste_reposicao_auto.gd

const DT := 0.02

var main
var c
var ia
var v
var q := 0
var fase := 0
var t := 0.0
var falhas := 0
var marcas := {}
var p0 := Vector3.ZERO
var d0 := Vector3.ZERO


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _falha(m: String) -> void:
	falhas += 1
	print("FALHA: ", m)


func _perto(a: float, b: float, tol: float, nome: String) -> void:
	if absf(a - b) > tol:
		_falha("%s: %.2f s (esperado %.2f)" % [nome, a, b])
	else:
		print("  %s: %.2f s (jogo %.2f)" % [nome, a, b])


## põe o jogador parado no link i, a `lado` m da linha (+ = direita do jogo)
func _colocar(i: int, lado: float, contra: bool) -> void:
	var n: int = ia.linha.size()
	var a: Vector3 = ia.linha[i]
	var b: Vector3 = ia.linha[(i + 1) % n]
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
	# lado do jogo no mundo: lat = dz * d.x - dx * d.z  ->  vetor (-d.z, 0, d.x)
	var l := Vector3(-d.z, 0.0, d.x)
	var p: Vector3 = a + d * 3.0 + l * lado
	p.y = main.terrain.height_at(p.x, p.z) + 1.0
	var yaw := atan2(d.x, d.z) + (PI if contra else 0.0)
	main.car.reset_to(p, yaw)
	main.car.test_input = {"thr": 0.0, "brk": 0.0, "steer": 0.0}
	p0 = p
	d0 = d
	# rastreio e progresso aceito no lugar novo
	ia.jogador.prog = ia.novo_rastreio(p).prog
	ia.vigia_jogador.recomecar(ia.jogador.prog)


func _physics_process(_dt: float) -> bool:
	q += 1
	if main.car == null or main.corrida == null:
		if q > 300:
			print("teste_reposicao_auto: FALHA (sem corrida)")
			return true
		return false
	c = main.corrida
	match fase:
		0:
			if q < 20:
				return false
			c.comecar()
			c.comecar()
			c.comecar()
			c.t_conta = 0.0
			fase = 1
		1:
			if c.estado != c.CORRENDO:
				return false
			ia = c.ia
			v = ia.vigia_jogador
			# 1. corredor: centro da pista de cada link dentro da largura
			var ls: Array = c.dados.links.duplicate()
			if c.sentido < 0:
				ls.reverse()
			var dentro := 0
			for i in ls.size():
				var pc: Vector3 = c.mundo(ls[i].centro)
				var r := {"prog": ia.novo_rastreio(pc).prog}
				var x := RigidBody3D.new()
				root.add_child(x)
				x.global_position = pc
				v.passo(r, x, 0.0)
				x.free()
				if v.fora <= 0.0:
					dentro += 1
			print("  corredor: %d de %d centros da pista dentro da largura" % [dentro, ls.size()])
			if dentro < ls.size() - 2:
				_falha("só %d de %d centros dentro do corredor (sinal do lado?)" % [dentro, ls.size()])
			v.recomecar(ia.jogador.prog)
			# 2. fora da pista: 10 m além da borda direita no link 30
			var i := 30
			_colocar(i, float(ia.dir[i]) + 10.0, false)
			t = 0.0
			marcas = {}
			fase = 2
		2:
			t += DT
			main.car.linear_velocity = Vector3.ZERO
			var txt: String = v.texto()
			if txt.begins_with("Off Track") and not marcas.has("msg"):
				marcas.msg = t
			if txt.ends_with("- 3") and not marcas.has("3"):
				marcas["3"] = t
			if v.repostos >= 1:
				_perto(marcas.get("msg", -1.0), 0.2, 0.05, "fora: mensagem")
				_perto(marcas.get("3", -1.0), 0.2, 0.05, "fora: contagem 3")
				_perto(t, 3.2, 0.05, "fora: reposição")
				fase = 3
				t = 0.0
			elif t > 6.0:
				_falha("fora da pista não repôs em 6 s (fora %.1f m)" % v.fora)
				fase = 3
		3:
			# depois de repor: na pista
			t += DT
			if t < 0.5:
				return false
			if v.fora > 0.0:
				_falha("depois de repor ainda fora da pista (%.1f m)" % v.fora)
			print("  depois de repor: %.1f m da linha, fora %.1f m" % [ia._projetar(main.car.global_position)[1], v.fora])
			# 3. contramão: na pista, de frente pra trás e andando pra trás
			_colocar(40, 0.0, true)
			t = 0.0
			marcas = {}
			fase = 4
		4:
			t += DT
			main.car.linear_velocity = -d0 * 8.0
			var txt: String = v.texto()
			if txt == "Wrong Way" and not marcas.has("ww"):
				marcas.ww = t
			if txt.begins_with("Off Track") and not marcas.has("off"):
				marcas.off = t
			if v.repostos >= 2:
				_perto(marcas.get("ww", -1.0), 0.2, 0.05, "contramão: Wrong Way")
				_perto(marcas.get("off", -1.0), 2.2, 0.05, "contramão: vira Off Track")
				_perto(t, 5.2, 0.05, "contramão: reposição")
				fase = 5
				t = 0.0
			elif t > 8.0:
				_falha("contramão não repôs em 8 s")
				fase = 5
		5:
			# 4. botão: rápido não repõe
			_colocar(50, 0.0, false)
			main.car.linear_velocity = d0 * 25.0
			var antes: int = c.ia.vigia_jogador.repostos
			if not c.botao_repor() or c.t_rapido <= 0.0:
				_falha("a 25 m/s o botão não mostrou Too Fast")
			main.car.linear_velocity = Vector3.ZERO
			c.t_rapido = 0.0
			_colocar(50, float(ia.dir[50]) + 3.0, false)
			marcas = {"pos0": main.car.global_position, "antes": antes, "alfa": 0.0}
			c.botao_repor()
			if c.t_rapido > 0.0:
				_falha("parado o botão deu Too Fast")
			t = 0.0
			fase = 6
		6:
			# 5. tela preta (menu/fader.gd, 0.2 s) e o carro reposto no passo
			# depois dos 0.3 s (0x15c0e8 estados 1 -> 2), a tela volta depois
			t += DT
			main.car.linear_velocity = Vector3.ZERO
			main.fader.passo(DT)
			marcas.alfa = maxf(marcas.alfa, main.fader.alfa)
			var andou: float = (main.car.global_position - marcas.pos0).length()
			if andou > 0.5 and not marcas.has("repos"):
				marcas.repos = t
				marcas.alfa_repos = main.fader.alfa
			if t >= 0.8:
				print("  botão parado: repôs aos %.2f s (tela preta %.2f nessa hora, máx %.2f), aos 0.8 s %.2f" % [
					marcas.get("repos", -1.0), marcas.get("alfa_repos", -1.0), marcas.alfa, main.fader.alfa])
				_perto(marcas.get("repos", -1.0), 0.32, 0.03, "botão: reposição")
				if marcas.alfa < 0.99 or main.fader.alfa > 0.0:
					_falha("tela preta: máx %.2f, aos 0.8 s %.2f" % [marcas.alfa, main.fader.alfa])
				if marcas.antes != c.ia.vigia_jogador.repostos:
					_falha("o botão contou como reposição automática")
				fase = 9
		9:
			print("teste_reposicao_auto: %s" % ("ok" if falhas == 0 else "FALHA (%d)" % falhas))
			return true
	return false
