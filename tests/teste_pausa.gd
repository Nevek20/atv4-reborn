extends SceneTree
## Menu de pausa e Race again (main.gd abrir_pausa / menu_acao, tela em
## menu/resultados.gd). Confere, com a cena do jogo:
##  1. Esc na corrida pausa (get_tree().paused): o carro e o relógio param, o
##     HUD some; opções do 0x462190 com o Respot (parado, abaixo de 40 mph);
##  2. setas andam no seletor; Enter no Respot volta pro jogo e pede a
##     reposição (tela preta, menu/fader.gd);
##  3. a 25 m/s a pausa vem sem o Respot (0x4613a0: |v| < 17.88);
##  4. Esc / triângulo na pausa = Resume; Quit pede "ARE YOU SURE?" (começa
##     no NO: volta pra pausa na mesma opção; seta = YES: treino livre);
##  5. Race again: Restart recomeça a corrida, Exit volta pro livre;
##  6. sons do menu (banco Menu_IG): abrir = ScrollVert, trocar = Scroll,
##     ponta = Back.
## Uso: godot --headless --path . --fixed-fps 50 -s res://tests/teste_pausa.gd

var main
var c
var fase := 0
var q := 0
var falhas := 0
var marca := {}


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _falha(m: String) -> void:
	falhas += 1
	print("FALHA: ", m)


func _tecla(k: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = k
	ev.keycode = k
	ev.pressed = true
	root.push_input(ev)
	var solta := ev.duplicate()
	solta.pressed = false
	root.push_input(solta)


func _physics_process(_dt: float) -> bool:
	q += 1
	if main.car == null or main.corrida == null or main.resultados == null:
		if q > 300:
			print("teste_pausa: ok (sem corrida ou sem assets/ui; pulado)")
			return true
		return false
	c = main.corrida
	var r = main.resultados
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
			if c.estado != c.CORRENDO or c.t < 0.5:
				return false
			main.car.linear_velocity = Vector3.ZERO
			_tecla(KEY_ESCAPE)
			marca = {"pos": main.car.global_position, "t": c.t, "q": q}
			fase = 2
		2:
			if q < marca.q + 10:
				return false
			print("pausa: paused %s, tela %s (%s), opções %s, HUD %s" % [paused, r.visible, r.pagina, r.opcoes,
				main.hud_jogo.visible if main.hud_jogo else false])
			if not paused or not r.visible or r.pagina != "pausa":
				_falha("Esc não pausou")
			if r.opcoes != ["Resume", "Respot", "RESTART", "QUIT", "Game_options", "Photographer"]:
				_falha("opções da pausa parado: %s" % [r.opcoes])
			var andou: float = (main.car.global_position - marca.pos).length()
			if andou > 0.01 or absf(c.t - marca.t) > 0.001:
				_falha("o jogo andou na pausa (%.3f m, relógio %.2f -> %.2f)" % [andou, marca.t, c.t])
			if main.hud_jogo and main.hud_jogo.visible:
				_falha("HUD na pausa")
			if r.ultimo_som != "ScrollVert":
				_falha("som de abrir a pausa: %s" % r.ultimo_som)
			_tecla(KEY_LEFT)
			if r.ultimo_som != "Back":
				_falha("som da ponta: %s" % r.ultimo_som)
			_tecla(KEY_RIGHT)
			fase = 3
		3:
			if r.escolhida() != "Respot":
				_falha("seta pra direita não foi pro Respot (%s)" % r.escolhida())
			if r.ultimo_som != "Scroll":
				_falha("som de trocar de opção: %s" % r.ultimo_som)
			_tecla(KEY_ENTER)
			marca.q = q
			fase = 4
		4:
			if q < marca.q + 3:
				return false
			print("Respot: paused %s, tela %s, pedido %d, tela preta indo pra %.0f" % [paused, r.visible,
				c.ia.repor_jog.estado, main.fader.alvo])
			if paused or r.visible:
				_falha("Respot não voltou pro jogo")
			if c.ia.repor_jog.estado == 0 and main.fader.alfa <= 0.0:
				_falha("Respot não pediu a reposição")
			marca.q = q
			fase = 5
		5:
			# rápido: sem o Respot
			if q < marca.q + 40:
				return false
			var frente: Vector3 = -main.car.global_transform.basis.z
			main.car.linear_velocity = main.car.global_transform.basis.z * 25.0
			if main.car.linear_velocity.length() < 20.0:
				main.car.linear_velocity = frente * 25.0
			main.abrir_pausa()
			print("pausa a 25 m/s: opções %s" % [r.opcoes])
			if r.opcoes.has("Respot"):
				_falha("Respot a 25 m/s")
			# Esc = Resume
			_tecla(KEY_ESCAPE)
			marca.q = q
			fase = 6
		6:
			if q < marca.q + 3:
				return false
			if paused or r.visible:
				_falha("Esc na pausa não voltou pro jogo")
			# Quit: pede confirmação; NO volta pra pausa; YES = treino livre
			main.abrir_pausa()
			main.menu_acao("pausa", "ok", "QUIT")
			if r.pagina != "confirma" or r.confirma.sim or not paused:
				_falha("Quit sem a confirmação (%s, sim %s)" % [r.pagina, r.confirma.sim])
			main.menu_acao("confirma", "ok", "QUIT")
			if r.pagina != "pausa" or c.estado == c.LIVRE:
				_falha("NO na confirmação não voltou pra pausa")
			main.menu_acao("pausa", "ok", "QUIT")
			_tecla(KEY_RIGHT)
			if not r.confirma.sim:
				_falha("seta na confirmação não foi pro YES")
			_tecla(KEY_ENTER)
			print("Quit + YES: estado %d (livre %d), paused %s" % [c.estado, c.LIVRE, paused])
			if c.estado != c.LIVRE or paused or r.visible:
				_falha("Quit não voltou pro treino livre")
			if main.abrir_pausa():
				_falha("pausa no treino livre")
			# Race again (Restart / Exit)
			r.mostrar([])
			c.estado = c.CHEGOU
			main._continuar_resultados()
			if r.pagina != "de_novo" or r.opcoes != ["RESTART", "EXIT"]:
				_falha("Race again: %s %s" % [r.pagina, r.opcoes])
			main.menu_acao("de_novo", "ok", "RESTART")
			print("Race again Restart: estado %d (intro %d / contando %d), tela %s" % [c.estado, c.INTRO, c.CONTANDO, r.visible])
			if r.visible or not (c.estado in [c.INTRO, c.CONTANDO]):
				_falha("Restart da Race again não recomeçou")
			fase = 9
		9:
			c.parar()
			print("teste_pausa: %s" % ("ok" if falhas == 0 else "FALHA (%d)" % falhas))
			return true
	return false
