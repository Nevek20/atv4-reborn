extends PanelContainer
## Oficina (O; provisório até ter a Garagem: Veículo -> Pintura e Logos).
## Do jogo: as 3 cores (base, primária, secundária), as 128 da paleta dele
## (16 x 8, carro/pintura.gd), os logos por lugar (áreas do carro, 1º, 2º...,
## logo da folha ou nenhum) e voltar pro de fábrica. A tela é NOSSA. Trocou,
## pinta na hora (car.pintar) e salva por carro (user://oficina.json).

const P := preload("res://carro/pintura.gd")
const NOMES := {"base": "Base", "primary": "Primária", "secondary": "Secundária"}
const AREAS := {"Hood": "Capô", "Side": "Lateral", "Roof": "Teto", "Rear Wing": "Asa",
	"RearWing": "Asa", "Rearwing": "Asa", "FrontWing": "Asa da frente", "Wing": "Asa",
	"Nose": "Bico", "Spoiler": "Aerofólio", "Pillar": "Coluna", "Rearwindow": "Vidro de trás",
	"Windscreen": "Para-brisa", "Intake": "Entrada de ar", "Intakes": "Entradas de ar",
	"Front": "Frente", "Rear": "Traseira", "Back": "Traseira"}
const LADO := 26                  # px de cada quadrinho da paleta

var main
var camada := "base"
var paleta: Array[Color] = []
var _abas := {}                   # camada -> Button
var _quadros: Array[Button] = []
var _amostra: ColorRect
var _aviso: Label
var _pag_pintura: VBoxContainer
var _pag_logos: VBoxContainer
var _lista_logos: VBoxContainer
var _nomes_lugar := {}            # chave do lugar -> Label com o logo escolhido


func _init(m) -> void:
	main = m
	name = "Oficina"
	visible = false
	position = Vector2(16, 60)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.09, 0.9)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(12)
	add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	# Pintura | Logos
	var topo := HBoxContainer.new()
	col.add_child(topo)
	var g_pag := ButtonGroup.new()
	for par in [["Pintura", true], ["Logos", false]]:
		var b := Button.new()
		b.text = par[0]
		b.toggle_mode = true
		b.button_group = g_pag
		b.button_pressed = par[1]
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(_pagina.bind(par[0] == "Logos"))
		topo.add_child(b)
	_pag_pintura = VBoxContainer.new()
	_pag_pintura.add_theme_constant_override("separation", 10)
	col.add_child(_pag_pintura)
	_pag_logos = VBoxContainer.new()
	_pag_logos.add_theme_constant_override("separation", 6)
	_pag_logos.visible = false
	col.add_child(_pag_logos)
	_montar_pintura()
	_montar_logos()
	_aviso = Label.new()
	_aviso.add_theme_color_override("font_color", Color(1, 0.75, 0.3))
	_aviso.autowrap_mode = TextServer.AUTOWRAP_WORD
	_aviso.custom_minimum_size.x = 16 * (LADO + 2)
	col.add_child(_aviso)


func _montar_pintura() -> void:
	var abas := HBoxContainer.new()
	_pag_pintura.add_child(abas)
	var grupo := ButtonGroup.new()
	for k in P.CORES:
		var b := Button.new()
		b.text = NOMES[k]
		b.toggle_mode = true
		b.button_group = grupo
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_aba.bind(k))
		abas.add_child(b)
		_abas[k] = b
	var padrao := Button.new()
	padrao.text = "De fábrica"
	padrao.focus_mode = Control.FOCUS_NONE
	padrao.pressed.connect(_padrao_cores)
	abas.add_child(padrao)
	var linha := HBoxContainer.new()
	_pag_pintura.add_child(linha)
	var l := Label.new()
	l.text = "Cor escolhida"
	linha.add_child(l)
	_amostra = ColorRect.new()
	_amostra.custom_minimum_size = Vector2(60, 22)
	linha.add_child(_amostra)
	var grade := GridContainer.new()
	grade.columns = 16
	grade.add_theme_constant_override("h_separation", 2)
	grade.add_theme_constant_override("v_separation", 2)
	_pag_pintura.add_child(grade)
	paleta = P.paleta()
	for i in paleta.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(LADO, LADO)
		b.focus_mode = Control.FOCUS_NONE
		for estado in ["normal", "hover", "pressed"]:
			var s := StyleBoxFlat.new()
			s.bg_color = paleta[i]
			if estado != "normal":
				s.set_border_width_all(2)
				s.border_color = Color.WHITE
			b.add_theme_stylebox_override(estado, s)
		b.pressed.connect(_escolher.bind(i))
		grade.add_child(b)
		_quadros.append(b)


func _montar_logos() -> void:
	var botoes := HBoxContainer.new()
	_pag_logos.add_child(botoes)
	for par in [["Sem logos", _sem_logos], ["De fábrica", _padrao_logos]]:
		var b := Button.new()
		b.text = par[0]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(par[1])
		botoes.add_child(b)
	var rolar := ScrollContainer.new()
	rolar.custom_minimum_size = Vector2(16 * (LADO + 2), 340)
	rolar.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_pag_logos.add_child(rolar)
	_lista_logos = VBoxContainer.new()
	_lista_logos.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rolar.add_child(_lista_logos)


func abrir() -> void:
	visible = not visible
	if not visible:
		return
	var car = main.car
	_aviso.text = ""
	if paleta.is_empty():
		_aviso.text = "Sem a paleta: rode o tools/gerar_pintura.py (docs/comandos.md)."
	elif not car.tem_camadas():
		_aviso.text = "Este carro não tem as camadas da pintura: rode o tools/gerar_pintura.py de novo."
	# camadas que o carro não tem (o XML sem a cor) ficam apagadas
	var tem: Dictionary = car._pintura.fabrica if car.get("_pintura") else {}
	for k in P.CORES:
		_abas[k].disabled = tem.get(k) == null
	if _abas[camada].disabled:
		camada = "base"
	_abas[camada].button_pressed = true
	_atualizar()
	_refazer_logos()


func _pagina(logos: bool) -> void:
	_pag_pintura.visible = not logos
	_pag_logos.visible = logos


func _aba(k: String) -> void:
	camada = k
	_atualizar()


func _cor_atual() -> Color:
	var car = main.car
	var v = car.cores_pintura.get(camada)
	if v == null and car.get("_pintura"):
		v = car._pintura.fabrica.get(camada)
	return v if v is Color else Color.WHITE


func _atualizar() -> void:
	var c := _cor_atual()
	_amostra.color = c
	for i in _quadros.size():
		var s: StyleBoxFlat = _quadros[i].get_theme_stylebox("normal")
		var marcado := paleta[i] == c
		s.set_border_width_all(3 if marcado else 0)
		s.border_color = Color.WHITE


## pinta e salva (cores e logos juntos, no car.cores_pintura)
func _aplicar(estado: Dictionary) -> void:
	var car = main.car
	if car.pintar(estado):
		P.salvar(car.chave(), estado)


func _escolher(i: int) -> void:
	var estado: Dictionary = main.car.cores_pintura.duplicate()
	estado[camada] = paleta[i]
	_aplicar(estado)
	_atualizar()


func _padrao_cores() -> void:
	var estado := {}
	if main.car.cores_pintura.has("logos"):
		estado["logos"] = main.car.cores_pintura.logos
	_aplicar(estado)
	_atualizar()


## ---------------------------------------------------------------- logos
## uma linha por lugar: "Capô 1º  ◀ nome ▶", agrupado pela área
func _refazer_logos() -> void:
	for c in _lista_logos.get_children():
		c.queue_free()
	_nomes_lugar.clear()
	var p = main.car.get("_pintura")
	var lugares: Array = p.lugares() if p else []
	if lugares.is_empty():
		var l := Label.new()
		l.text = "Este carro não tem os lugares de logo (rode o tools/gerar_pintura.py de novo)."
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		_lista_logos.add_child(l)
		return
	var area_antes := ""
	for lg in lugares:
		if lg.area != area_antes:
			area_antes = lg.area
			var t := Label.new()
			t.text = AREAS.get(lg.area, lg.area)
			t.add_theme_font_size_override("font_size", 18)
			t.add_theme_color_override("font_color", Color(1, 0.8, 0.4))
			_lista_logos.add_child(t)
		var linha := HBoxContainer.new()
		_lista_logos.add_child(linha)
		var n := Label.new()
		n.text = "%dº" % int(lg.lugar)
		n.custom_minimum_size.x = 36
		linha.add_child(n)
		var menos := Button.new()
		menos.text = "◀"
		menos.focus_mode = Control.FOCUS_NONE
		menos.pressed.connect(_passo_logo.bind(lg.chave, -1))
		linha.add_child(menos)
		var nome := Label.new()
		nome.custom_minimum_size.x = 300
		nome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nome.clip_text = true
		linha.add_child(nome)
		var mais := Button.new()
		mais.text = "▶"
		mais.focus_mode = Control.FOCUS_NONE
		mais.pressed.connect(_passo_logo.bind(lg.chave, 1))
		linha.add_child(mais)
		_nomes_lugar[lg.chave] = nome
	_mostrar_logos()


func _logo_atual(chave: String) -> String:
	var escolhas = main.car.cores_pintura.get("logos", {})
	if escolhas is Dictionary and escolhas.has(chave):
		return String(escolhas[chave])
	return main.car._pintura.logo_padrao(chave)


func _mostrar_logos() -> void:
	for chave in _nomes_lugar:
		var nm := _logo_atual(chave)
		_nomes_lugar[chave].text = nm if nm != "" else "(sem logo)"


## anda na lista da folha (o "sem logo" fica antes do 1º)
func _passo_logo(chave: String, d: int) -> void:
	var p = main.car._pintura
	var opcoes: Array = [""] + p.nomes_logos(chave)
	var i := opcoes.find(_logo_atual(chave))
	i = posmod(i + d, opcoes.size())
	var estado: Dictionary = main.car.cores_pintura.duplicate(true)
	var escolhas: Dictionary = estado.get("logos", {}).duplicate()
	escolhas[chave] = opcoes[i]
	estado["logos"] = escolhas
	_aplicar(estado)
	_mostrar_logos()


func _sem_logos() -> void:
	var estado: Dictionary = main.car.cores_pintura.duplicate(true)
	var escolhas := {}
	for lg in main.car._pintura.lugares():
		escolhas[lg.chave] = ""
	estado["logos"] = escolhas
	_aplicar(estado)
	_mostrar_logos()


func _padrao_logos() -> void:
	var estado: Dictionary = main.car.cores_pintura.duplicate(true)
	estado.erase("logos")
	_aplicar(estado)
	_mostrar_logos()


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode in [KEY_ESCAPE, KEY_O]:
		visible = false
		get_viewport().set_input_as_handled()
