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
##  5. checkpoint (tipo 3, 0x4d5188 / 0x4d43f0): passar 10 m fora do centro
##     conta a volta; pular por cima da caixa dá "Missed Checkpoint" 5 m depois
##     da face de entrada, repõe 4.2 s depois no começo do link (antes da
##     caixa) e aí passar conta; largo demais (18 m) com "Off Track" andando,
##     o tipo 3 passa na frente direto na fase 2.
##  6. fantasma (repor_carro.gd, 0x15c0e8 estado 4): reposto, o carro fica
##     sem batida com outro carro 0.3 s e enquanto a caixa dele encosta na
##     de outro; um rival pedido espera 0.3 s andando e repõe;
##  7. jogador capotado parado (0x2017a8): pede a reposição depois de 0.69 s
##     e é reposto 0.3 s depois, de pé.
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
			# as partes 1 a 6 seguram o carro parado (velocidade zerada, ele
			# fica no ar): a regra do capotado fica pra parte 7
			ia.preso_jog_ligado = false
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
				fase = 7
		7:
			_teste_checkpoint()
			fase = 12
		12:
			_teste_fantasma()
			fase = 13
			t = 0.0
			marcas = {}
			# 7. capotado: de cabeça pra baixo, parado, no link 60
			_colocar(60, 0.0, false)
			var xf: Transform3D = main.car.global_transform
			xf.basis = xf.basis.rotated(xf.basis.z.normalized(), PI)
			xf.origin.y += 0.6
			main.car.global_transform = xf
			main.car.reset_physics_interpolation()
			marcas.antes = ia.repor_jog.estado
			ia.repor_jog.terminar()
			ia._preso_jog_t = 0.0
			ia.preso_jog_ligado = true
		13:
			t += DT
			if ia._preso_jog_t > 0.0 and not marcas.has("ini"):
				marcas.ini = t
			if ia.repor_jog.estado == 1 and not marcas.has("pediu"):
				marcas.pediu = t
			if ia.repor_jog.estado >= 3 and not marcas.has("repos"):
				marcas.repos = t
				marcas.up = main.car.global_transform.basis.y.y
			if marcas.has("repos") or t > 6.0:
				if not marcas.has("pediu"):
					_falha("capotado não pediu a reposição em 6 s (preso %.2f s, rodas %d)" % [
						ia._preso_jog_t, main.car.grounded])
				else:
					print("  capotado: preso desde %.2f s, pediu aos %.2f s, reposto aos %.2f s (de pé %.2f)" % [
						marcas.get("ini", -1.0), marcas.pediu, marcas.get("repos", -1.0), marcas.get("up", -1.0)])
					_perto(marcas.pediu - marcas.get("ini", 0.0), 0.70, 0.03, "capotado: pedido")
					_perto(marcas.get("repos", -1.0) - marcas.pediu, 0.32, 0.03, "capotado: reposição")
					if marcas.get("up", -1.0) < 0.9:
						_falha("reposto não ficou de pé")
				fase = 9
		9:
			print("teste_reposicao_auto: %s" % ("ok" if falhas == 0 else "FALHA (%d)" % falhas))
			return true
	return false


## 5. checkpoint com um vigia novo e um corpo parado (sem física): anda na
## mão pela linha de chegada a 15 m/s (0.3 m por passo)
func _teste_checkpoint() -> void:
	var R = load("res://pista/reposicao.gd")
	var x := RigidBody3D.new()
	x.freeze = true
	root.add_child(x)
	var d: Vector3 = c._cp_frente
	var y_cp: float = c._cp_pos.y
	# A. passando 10 m fora do centro (o tamanho do XML é a meia medida: 15.83 m)
	var r := _r_em(x, -20.0, 10.0, 0.0, d)
	var w = R.new(ia, r.prog)
	var tipo3 := false
	for k in 170:
		_mover(x, r, -20.0 + 0.3 * k, 10.0, 0.0, d)
		w.passo(r, x, DT)
		tipo3 = tipo3 or w.tipo == 3
	print("  checkpoint 10 m fora do centro: voltas %d, pendente %s, tipo 3 %s" % [w.voltas, w.pendente, tipo3])
	if w.voltas != 1 or w.pendente or tipo3:
		_falha("passar 10 m fora do centro não contou a volta")
	# B. por cima da caixa (7 m acima do centro, a meia altura é 5.94 m)
	r = _r_em(x, -20.0, 0.0, 0.0, d)
	w = R.new(ia, r.prog)
	var t_perdeu := -1.0
	var t_msg := -1.0
	var t_3 := -1.0
	var t_repos := -1.0
	var tt := 0.0
	var al := -20.0
	for k in 400:
		tt += DT
		if al < 12.0:
			al += 0.3
		var alto := 7.0 if al > -4.0 and al < 4.0 else 0.0
		_mover(x, r, al, 0.0, alto, d)
		var repos: bool = w.passo(r, x, DT)
		if w.estado == 1 and t_perdeu < 0.0:
			t_perdeu = tt
			print("  por cima: perdeu a %.2f m do centro (face de entrada %.2f m antes)" % [
				al, fposmod(float(ia.s_linha), float(ia.comp)) - w._cp_ent])
		var txt: String = w.texto()
		if txt == "Missed Checkpoint" and t_msg < 0.0:
			t_msg = tt
		if txt == "Missed Checkpoint - 3" and t_3 < 0.0:
			t_3 = tt
		if repos:
			t_repos = tt
			break
	if t_perdeu < 0.0:
		_falha("por cima da caixa não perdeu o checkpoint")
	else:
		_perto(t_msg - t_perdeu, 0.2, 0.03, "por cima: Missed Checkpoint")
		_perto(t_3 - t_perdeu, 1.2, 0.03, "por cima: contagem 3")
		_perto(t_repos - t_perdeu, 4.2, 0.03, "por cima: reposição")
	if w.voltas != 0:
		_falha("por cima da caixa contou a volta")
	var pr: float = w.ponto_repor()
	var ini: float = float(ia.acc[w._cp_seg]) - fposmod(float(ia.s_linha), float(ia.comp))
	print("  por cima: aceito %.2f m, repõe em %.2f m (começo do link %.2f m)" % [w.aceito, pr, ini])
	if absf(pr - ini) > 0.05:
		_falha("repor com checkpoint pendente não voltou pro começo do link")
	# reposto antes da caixa: passar agora conta
	w.recomecar(pr)
	r = _r_em(x, pr, 0.0, 0.0, d)
	for k in 80:
		_mover(x, r, pr + 0.3 * k, 0.0, 0.0, d)
		w.passo(r, x, DT)
	print("  depois de repor: voltas %d, pendente %s, tipo %d" % [w.voltas, w.pendente, w.tipo])
	if w.voltas != 1 or w.pendente or w.tipo != 0:
		_falha("depois de repor, passar pela caixa não contou")
	# C. largo demais (18 m): fora da pista andando e o tipo 3 passa na frente
	var lado := 18.0
	r = _r_em(x, -20.0, lado, 0.0, d)
	w = R.new(ia, r.prog)
	var fase_3 := -1
	var tipo_antes := 0
	for k in 120:
		_mover(x, r, -20.0 + 0.3 * k, lado, 0.0, d)
		var antes: int = w.tipo
		w.passo(r, x, DT)
		if w.tipo == 3 and fase_3 < 0:
			fase_3 = w.fase
			tipo_antes = antes
	print("  18 m fora: tipo 3 entrou na fase %d (antes tipo %d), voltas %d" % [fase_3, tipo_antes, w.voltas])
	if fase_3 < 0 or w.voltas != 0:
		_falha("18 m fora do centro não deu Missed Checkpoint")
	elif tipo_antes != 0 and fase_3 != 2:
		_falha("tipo 3 por cima do %d não foi direto pra fase 2" % tipo_antes)
	x.free()


func _pos(al: float, lat: float, alto: float) -> Vector3:
	var p: Vector3 = c._cp_pos + c._cp_frente * al + c._cp_lado * lat
	# alto > 0: acima do centro da caixa (o chão ali fica ~1.5 m abaixo dele)
	p.y = c._cp_pos.y + alto if alto > 0.0 else main.terrain.height_at(p.x, p.z) + 0.6
	return p


func _r_em(x: RigidBody3D, al: float, lat: float, alto: float, d: Vector3) -> Dictionary:
	var p := _pos(al, lat, alto)
	x.global_transform = Transform3D(Basis(Vector3.UP, atan2(d.x, d.z)), p)
	return ia.novo_rastreio(p)


func _mover(x: RigidBody3D, r: Dictionary, al: float, lat: float, alto: float, d: Vector3) -> void:
	var p := _pos(al, lat, alto)
	x.global_transform = Transform3D(Basis(Vector3.UP, atan2(d.x, d.z)), p)
	ia.rastrear(r, p)


## 6. fantasma e a espera dos rivais: com os passos chamados na mão
func _teste_fantasma() -> void:
	var x: Dictionary = ia.rivais[0]
	var rr = x.repor
	var antes: Vector3 = x.car.global_position
	rr.pedir()
	var t_rep := -1.0
	var tt := 0.0
	for k in 30:
		tt += DT
		rr.passo(DT)
		if t_rep < 0.0 and rr.estado >= 3:
			t_rep = tt
	_perto(t_rep, 0.32, 0.03, "rival: reposição depois do pedido")
	if not x.car.fantasma:
		_falha("rival reposto não ficou fantasma")
	# encosta o jogador em cima dele: fica fantasma passando dos 0.3 s
	var xf: Transform3D = x.car.global_transform
	main.car.global_transform = Transform3D(xf.basis, xf.origin + xf.basis.x * 0.5)
	for k in 30:
		rr.passo(DT)
	var preso_fant: bool = x.car.fantasma and rr.estado == 4
	# o jogador sai de cima: termina
	main.car.global_transform = Transform3D(xf.basis, xf.origin + Vector3(30.0, 0.0, 0.0))
	rr.passo(DT)
	print("  fantasma: encostado depois de 0.6 s %s, longe %s (estado %d)" % [preso_fant, x.car.fantasma, rr.estado])
	if not preso_fant:
		_falha("encostado em outro carro o fantasma acabou")
	if x.car.fantasma or rr.estado != 0:
		_falha("longe dos outros o fantasma não acabou")
	# batida_carros pula o par com fantasma (só esses 2 carros na lista)
	var lista_antes: Callable = ia.batidas.carros
	var par := [main.car, x.car]
	ia.batidas.carros = func(): return par
	x.car.fantasma = true
	var n0: int = ia.batidas.contatos
	main.car.global_transform = Transform3D(xf.basis, xf.origin + xf.basis.x * 0.3)
	ia.batidas._physics_process(DT)
	var n_f: int = ia.batidas.contatos - n0
	x.car.fantasma = false
	ia.batidas._physics_process(DT)
	var n_n: int = ia.batidas.contatos - n0 - n_f
	ia.batidas.carros = lista_antes
	print("  batida carro com carro: fantasma %d contatos, normal %d" % [n_f, n_n])
	if n_f != 0 or n_n == 0:
		_falha("fantasma não pulou a batida (fantasma %d, normal %d)" % [n_f, n_n])
	x.car.global_position = antes
