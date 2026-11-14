extends PanelContainer
## Oficina de pintura (O; provisório até ter a Garagem: Veículo -> Pintura).
## Do jogo: as 3 cores (base, primária, secundária), as 128 da paleta dele
## (16 x 8, carro/pintura.gd) e voltar pra de fábrica. A tela é NOSSA. Trocou,
## pinta na hora (car.pintar) e salva por carro (user://oficina.json).

const P := preload("res://carro/pintura.gd")
const NOMES := {"base": "Base", "primary": "Primária", "secondary": "Secundária"}
const LADO := 26                  # px de cada quadrinho da paleta

var main
var camada := "base"
var paleta: Array[Color] = []
var _abas := {}                   # camada -> Button
var _quadros: Array[Button] = []
var _amostra: ColorRect
var _aviso: Label


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
	var titulo := Label.new()
	titulo.text = "Pintura"
	titulo.add_theme_font_size_override("font_size", 22)
	col.add_child(titulo)
	var abas := HBoxContainer.new()
	col.add_child(abas)
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
	padrao.pressed.connect(_padrao)
	abas.add_child(padrao)
	var linha := HBoxContainer.new()
	col.add_child(linha)
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
	col.add_child(grade)
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
	_aviso = Label.new()
	_aviso.add_theme_color_override("font_color", Color(1, 0.75, 0.3))
	_aviso.autowrap_mode = TextServer.AUTOWRAP_WORD
	_aviso.custom_minimum_size.x = 16 * (LADO + 2)
	col.add_child(_aviso)


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


func _escolher(i: int) -> void:
	var car = main.car
	var cores: Dictionary = car.cores_pintura.duplicate()
	cores[camada] = paleta[i]
	if car.pintar(cores):
		P.salvar(car.chave(), cores)
	_atualizar()


func _padrao() -> void:
	var car = main.car
	if car.pintar({}):
		P.salvar(car.chave(), {})
	_atualizar()


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode in [KEY_ESCAPE, KEY_O]:
		visible = false
		get_viewport().set_input_as_handled()
