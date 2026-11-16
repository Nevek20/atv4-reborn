extends PanelContainer
## Oficina (O; provisório até ter a Garagem: Veículo -> Pintura e Logos,
## Piloto -> Gear e Paint Shop).
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
const PP := preload("res://carro/piloto_pintura.gd")
const PECAS := {"roupa": "Roupa", "capacete": "Capacete", "oculos": "Óculos", "luva": "Luva", "bota": "Bota"}
const CORES_PILOTO := {"base": "Base", "primary": "Primária", "secondary": "Secundária", "text": "Texto"}

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
var _pag_piloto: VBoxContainer
var _pp = null                     # carro/piloto_pintura.gd (as camadas)
var _nomes_peca := {}              # peça -> Label com o modelo
var camada_piloto := "base"
var _abas_piloto := {}
var _quadros_piloto: Array[Button] = []
var _amostra_piloto: ColorRect
var _pag_upgrade: VBoxContainer
var _lista_upg: VBoxContainer
var _resumo_upg: Label
var _upg := {}                     # opções da classe (carro/pecas.gd opcoes)
var _upg_fab := {}                 # DefaultConfig do carro
var _upg_esc := {}                 # escolha ainda não aplicada {slot: peça}
var _upg_veh := ""
var _upg_chave := ""


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
	for par in [["Pintura", true], ["Logos", false], ["Piloto", false], ["Upgrade", false]]:
		var b := Button.new()
		b.text = par[0]
		b.toggle_mode = true
		b.button_group = g_pag
		b.button_pressed = par[1]
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(_pagina.bind(par[0]))
		topo.add_child(b)
	_pag_pintura = VBoxContainer.new()
	_pag_pintura.add_theme_constant_override("separation", 10)
	col.add_child(_pag_pintura)
	_pag_logos = VBoxContainer.new()
	_pag_logos.add_theme_constant_override("separation", 6)
	_pag_logos.visible = false
	col.add_child(_pag_logos)
	_pag_piloto = VBoxContainer.new()
	_pag_piloto.add_theme_constant_override("separation", 8)
	_pag_piloto.visible = false
	col.add_child(_pag_piloto)
	_pag_upgrade = VBoxContainer.new()
	_pag_upgrade.add_theme_constant_override("separation", 6)
	_pag_upgrade.visible = false
	col.add_child(_pag_upgrade)
	_montar_pintura()
	_montar_logos()
	_montar_piloto()
	_montar_upgrade()
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
	for par in [["Nenhum em todos", _sem_logos], ["De fábrica", _padrao_logos]]:
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
	_mostrar_piloto()
	_abrir_upgrade()


func _pagina(nome: String) -> void:
	_pag_pintura.visible = nome == "Pintura"
	_pag_logos.visible = nome == "Logos"
	_pag_piloto.visible = nome == "Piloto"
	_pag_upgrade.visible = nome == "Upgrade"


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
## uma linha por lugar: "1º  ◀ nome ▶  Nenhum", agrupado pela área
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
		# nenhum direto (o No_Logo do jogo), sem dar a volta na lista
		var nenhum := Button.new()
		nenhum.text = "Nenhum"
		nenhum.focus_mode = Control.FOCUS_NONE
		nenhum.pressed.connect(_nenhum_logo.bind(lg.chave))
		linha.add_child(nenhum)
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
		_nomes_lugar[chave].text = nm if nm != "" else "(nenhum)"


## anda na lista da folha (o "nenhum" fica antes do 1º)
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


func _nenhum_logo(chave: String) -> void:
	var estado: Dictionary = main.car.cores_pintura.duplicate(true)
	var escolhas: Dictionary = estado.get("logos", {}).duplicate()
	escolhas[chave] = ""
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


## ---------------------------------------------------------------- piloto
## Gear: um modelo por peça (roupa, capacete, óculos, luva, bota; 12 cada, do
## CLOTHING.xml); Paint Shop: base, primária, secundária e texto pro piloto
## todo, na paleta do jogo. "De fábrica" = as cores da roupa escolhida
## (DefaultColours), "Perfil padrão" = tudo de volta
## Change Rider do jogo (sexo, rosto, cabelo e número 00..99; nome ainda não).
## O número vai nas costas do piloto e nos quadros do número do carro
const PILOTO_EXTRA := {"sexo": "Sexo", "rosto": "Rosto", "cabelo": "Cabelo", "numero": "Número"}


func _montar_piloto() -> void:
	var t0 := Label.new()
	t0.text = "Piloto"
	t0.add_theme_color_override("font_color", Color(1, 0.8, 0.4))
	_pag_piloto.add_child(t0)
	for k in PILOTO_EXTRA:
		var linha := HBoxContainer.new()
		_pag_piloto.add_child(linha)
		var l := Label.new()
		l.text = PILOTO_EXTRA[k]
		l.custom_minimum_size.x = 90
		linha.add_child(l)
		# número: ◀◀ ▶▶ pulam de 10 (NOSSO, o jogo digita)
		var passos := [[-10, "◀◀"], [-1, "◀"], [0, ""], [1, "▶"], [10, "▶▶"]] if k == "numero" \
			else [[-1, "◀"], [0, ""], [1, "▶"]]
		for ps in passos:
			if ps[0] == 0:
				var nome := Label.new()
				nome.custom_minimum_size.x = 120
				nome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				linha.add_child(nome)
				_nomes_peca[k] = nome
				continue
			var b := Button.new()
			b.text = ps[1]
			b.focus_mode = Control.FOCUS_NONE
			b.pressed.connect(_passo_extra.bind(k, ps[0]))
			linha.add_child(b)
	var titulo := Label.new()
	titulo.text = "Equipamento"
	titulo.add_theme_color_override("font_color", Color(1, 0.8, 0.4))
	_pag_piloto.add_child(titulo)
	for k in PECAS:
		var linha := HBoxContainer.new()
		_pag_piloto.add_child(linha)
		var l := Label.new()
		l.text = PECAS[k]
		l.custom_minimum_size.x = 90
		linha.add_child(l)
		var menos := Button.new()
		menos.text = "◀"
		menos.focus_mode = Control.FOCUS_NONE
		menos.pressed.connect(_passo_peca.bind(k, -1))
		linha.add_child(menos)
		var nome := Label.new()
		nome.custom_minimum_size.x = 120
		nome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		linha.add_child(nome)
		var mais := Button.new()
		mais.text = "▶"
		mais.focus_mode = Control.FOCUS_NONE
		mais.pressed.connect(_passo_peca.bind(k, 1))
		linha.add_child(mais)
		_nomes_peca[k] = nome
	var t2 := Label.new()
	t2.text = "Cores"
	t2.add_theme_color_override("font_color", Color(1, 0.8, 0.4))
	_pag_piloto.add_child(t2)
	var abas := HBoxContainer.new()
	_pag_piloto.add_child(abas)
	var grupo := ButtonGroup.new()
	for k in CORES_PILOTO:
		var b := Button.new()
		b.text = CORES_PILOTO[k]
		b.toggle_mode = true
		b.button_group = grupo
		b.button_pressed = k == "base"
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): camada_piloto = k; _mostrar_piloto())
		abas.add_child(b)
		_abas_piloto[k] = b
	var linha_cor := HBoxContainer.new()
	_pag_piloto.add_child(linha_cor)
	var lc := Label.new()
	lc.text = "Cor escolhida"
	linha_cor.add_child(lc)
	_amostra_piloto = ColorRect.new()
	_amostra_piloto.custom_minimum_size = Vector2(60, 22)
	linha_cor.add_child(_amostra_piloto)
	var grade := GridContainer.new()
	grade.columns = 16
	grade.add_theme_constant_override("h_separation", 2)
	grade.add_theme_constant_override("v_separation", 2)
	_pag_piloto.add_child(grade)
	for i in paleta.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(LADO, LADO)
		b.focus_mode = Control.FOCUS_NONE
		for estado in ["normal", "hover", "pressed"]:
			var st := StyleBoxFlat.new()
			st.bg_color = paleta[i]
			if estado != "normal":
				st.set_border_width_all(2)
				st.border_color = Color.WHITE
			b.add_theme_stylebox_override(estado, st)
		b.pressed.connect(_cor_piloto.bind(i))
		grade.add_child(b)
		_quadros_piloto.append(b)
	var botoes := HBoxContainer.new()
	_pag_piloto.add_child(botoes)
	for par in [["Cores de fábrica", _piloto_cores_fabrica], ["Perfil padrão", _piloto_padrao]]:
		var b := Button.new()
		b.text = par[0]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(par[1])
		botoes.add_child(b)


func _pp_ok() -> bool:
	if _pp == null:
		_pp = PP.carregar()
	return _pp != null


func _esc_piloto() -> Dictionary:
	return _pp.completo(main.car.piloto_escolhas) if _pp_ok() else {}


func _mostrar_piloto() -> void:
	if not _pp_ok():
		for k in _nomes_peca:
			_nomes_peca[k].text = "-"
		_aviso.text = "Sem as camadas do piloto: rode o tools/piloto.py (docs/comandos.md)."
		return
	if main.car.get("piloto") == null and _pag_piloto.visible:
		_aviso.text = "Este carro está sem o piloto (rode o tools/piloto.py)."
	var e := _esc_piloto()
	for k in _nomes_peca:
		if k == "sexo":
			_nomes_peca[k].text = "Feminino" if String(e.sexo) == "f" else "Masculino"
		elif k == "cabelo":
			var cab: Array = _pp.info.get("cabelos", [])
			var i := int(e.cabelo) - 1
			_nomes_peca[k].text = String(cab[i]).capitalize() if i >= 0 and i < cab.size() else str(e.cabelo)
		elif k == "rosto":
			_nomes_peca[k].text = "Rosto %d" % int(e.rosto)
		elif k == "numero":
			_nomes_peca[k].text = "%02d" % String(e.get("numero", "00")).to_int()
		else:
			_nomes_peca[k].text = "Modelo %d" % int(e[k])
	var v: Array = e.cores[camada_piloto]
	var c := Color8(int(v[0]), int(v[1]), int(v[2]))
	_amostra_piloto.color = c
	for i in _quadros_piloto.size():
		var st: StyleBoxFlat = _quadros_piloto[i].get_theme_stylebox("normal")
		st.set_border_width_all(3 if paleta[i] == c else 0)
		st.border_color = Color.WHITE


func _aplicar_piloto(esc: Dictionary) -> void:
	if main.car.pintar_piloto(esc):
		PP.salvar(esc)
	_mostrar_piloto()


func _passo_peca(k: String, d: int) -> void:
	if not _pp_ok():
		return
	var esc: Dictionary = main.car.piloto_escolhas.duplicate(true)
	var n := maxi(_pp.quantos(k), 1)
	esc[k] = posmod(int(_esc_piloto()[k]) - 1 + d, n) + 1
	_aplicar_piloto(esc)


func _passo_extra(k: String, d: int) -> void:
	if not _pp_ok():
		return
	var esc: Dictionary = main.car.piloto_escolhas.duplicate(true)
	var e := _esc_piloto()
	if k == "sexo":
		esc["sexo"] = "m" if String(e.sexo) == "f" else "f"
	elif k == "numero":
		esc["numero"] = "%02d" % posmod(String(e.get("numero", "00")).to_int() + d, 100)
	else:
		var n := maxi((_pp.info.get("rostos", {}).get(String(e.sexo), []) as Array).size(), 1) if k == "rosto" \
			else maxi((_pp.info.get("cabelos", []) as Array).size(), 1)
		esc[k] = posmod(int(e[k]) - 1 + d, n) + 1
	_aplicar_piloto(esc)


func _cor_piloto(i: int) -> void:
	if not _pp_ok():
		return
	var esc: Dictionary = main.car.piloto_escolhas.duplicate(true)
	var cores: Dictionary = esc.get("cores", {}).duplicate()
	cores[camada_piloto] = [paleta[i].r8, paleta[i].g8, paleta[i].b8]
	esc["cores"] = cores
	_aplicar_piloto(esc)


func _piloto_cores_fabrica() -> void:
	if not _pp_ok():
		return
	var esc: Dictionary = main.car.piloto_escolhas.duplicate(true)
	esc["cores"] = _pp.cores_da_roupa(int(_esc_piloto().roupa))
	_aplicar_piloto(esc)


func _piloto_padrao() -> void:
	_aplicar_piloto({})


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode in [KEY_ESCAPE, KEY_O]:
		visible = false
		get_viewport().set_input_as_handled()


## ---------------------------------------------------------------- upgrade
## Garage > Vehicle > Upgrade do jogo: uma peça por slot (upgrades.xml da
## classe). Mexer nas setas só escolhe; "Aplicar" salva e monta o carro de
## novo no lugar (a física lê as peças no _ready). NOSSO: a tela
const PECAS_UPG := preload("res://carro/pecas.gd")


func _montar_upgrade() -> void:
	var t := Label.new()
	t.text = "Peças (efeitos do upgrades.xml; Aplicar monta o carro de novo)"
	t.add_theme_color_override("font_color", Color(1, 0.8, 0.4))
	_pag_upgrade.add_child(t)
	_lista_upg = VBoxContainer.new()
	_lista_upg.add_theme_constant_override("separation", 4)
	_pag_upgrade.add_child(_lista_upg)
	_resumo_upg = Label.new()
	_resumo_upg.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	_pag_upgrade.add_child(_resumo_upg)
	var botoes := HBoxContainer.new()
	_pag_upgrade.add_child(botoes)
	for par in [["De fábrica", _upg_fabrica], ["Tudo no máximo", _upg_maximo], ["Aplicar", _upg_aplicar]]:
		var b := Button.new()
		b.text = par[0]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(par[1])
		botoes.add_child(b)


func _abrir_upgrade() -> void:
	var car = main.car
	var veh: String = car.tuning_id if car.tuning_id != "" else car.vehicle_id
	# reabrir no mesmo carro mantém a escolha que ainda não foi aplicada (no
	# jogo, ir trocando peça fazia outra voltar: aqui cada slot é só dele)
	var mesmo: bool = veh == _upg_veh and car.chave() == _upg_chave
	_upg_veh = veh
	_upg_chave = car.chave()
	var f: Dictionary = PECAS_UPG.fabrica(_upg_veh)
	_upg_fab = f.config
	_upg = PECAS_UPG.opcoes(f.classe)
	if not mesmo:
		_upg_esc = (car.pecas_escolhidas as Dictionary).duplicate()
	for c in _lista_upg.get_children():
		c.queue_free()
	for slot in PECAS_UPG.SLOTS:
		if not _upg.slots.has(slot) or not _upg_fab.has(slot):
			continue
		var linha := HBoxContainer.new()
		_lista_upg.add_child(linha)
		var l := Label.new()
		l.text = PECAS_UPG.NOMES.get(slot, slot)
		l.custom_minimum_size.x = 130
		linha.add_child(l)
		for d in [-1, 1]:
			var b := Button.new()
			b.text = "◀" if d < 0 else "▶"
			b.focus_mode = Control.FOCUS_NONE
			b.pressed.connect(_upg_passo.bind(slot, d))
			linha.add_child(b)
			if d < 0:
				var nome := Label.new()
				nome.name = "Nome"
				nome.custom_minimum_size.x = 170
				nome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				linha.add_child(nome)
		var fx := Label.new()
		fx.name = "Efeito"
		fx.modulate = Color(1, 1, 1, 0.7)
		linha.add_child(fx)
		linha.set_meta("slot", slot)
	_mostrar_upgrade()


func _upg_peca(slot: String) -> String:
	return String(_upg_esc.get(slot, _upg_fab.get(slot, "")))


func _mostrar_upgrade() -> void:
	for linha in _lista_upg.get_children():
		if not linha.has_meta("slot"):
			continue
		var slot: String = linha.get_meta("slot")
		var p := _upg_peca(slot)
		var nome: Label = linha.get_node("Nome")
		nome.text = PECAS_UPG.rotulo(p) + ("  (fábrica)" if p == _upg_fab.get(slot) else "")
		var fx: Dictionary = _upg.efeitos.get(p, {})
		var txt: Array = []
		for k in fx:
			if String(fx[k]) != "" and k not in ["EngineFrictionTorque", "EngineInertia", "ClutchTorque",
					"RearSuspMaxCompression", "ManualGearChangeTime"]:
				txt.append("%s %s" % [k, fx[k]])
			elif String(fx[k]) == "":
				txt.append(k)
		(linha.get_node("Efeito") as Label).text = ", ".join(txt)
	# o que a física vai usar (0..1 entre _non_tuned e _fully_tuned)
	var t: Dictionary = preload("res://carro/vehicle_data.gd").factory_tuning(PECAS_UPG.VEICULOS, PECAS_UPG.UPGRADES, _upg_veh, _upg_esc)
	_resumo_upg.text = "Motor %.2f   Freio %.2f   Suspensão %.2f (subesterço %.2f)   Final %.2f   Embreagem %.2f   Peso %.2f" % [
		t.engine, t.brake, t.susp, t.understeer, t.final, t.shift, t.mass]
	var mudou: bool = _upg_esc != main.car.pecas_escolhidas
	_aviso.text = "Peças mudadas: aperte Aplicar." if mudou else ""


func _upg_passo(slot: String, d: int) -> void:
	var lista: Array = _upg.slots.get(slot, [])
	if lista.is_empty():
		return
	var i := posmod(lista.find(_upg_peca(slot)) + d, lista.size())
	if lista[i] == _upg_fab.get(slot):
		_upg_esc.erase(slot)
	else:
		_upg_esc[slot] = lista[i]
	_mostrar_upgrade()


func _upg_fabrica() -> void:
	_upg_esc = {}
	_mostrar_upgrade()


func _upg_maximo() -> void:
	for slot in PECAS_UPG.SLOTS:
		var lista: Array = _upg.slots.get(slot, [])
		if lista.is_empty() or not _upg_fab.has(slot):
			continue
		var ult: String = lista[-1]
		if ult == _upg_fab.get(slot):
			_upg_esc.erase(slot)
		else:
			_upg_esc[slot] = ult
	_mostrar_upgrade()


func _upg_aplicar() -> void:
	PECAS_UPG.salvar(main.car.chave(), _upg_esc)
	main.remontar_carro()
	_aviso.text = "Peças aplicadas."
