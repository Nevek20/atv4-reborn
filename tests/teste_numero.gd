extends SceneTree
## Número do perfil (oficina, aba Piloto: Número 00..99): vai nas costas do
## piloto (PLAYER_NUMBER do COMPOSITOR.xml) e nos quadros do número do carro
## (Box com Text da pintura). Os rivais usam o Number do AIPlayers.xml.
## Confere: ◀◀ ◀ ▶ ▶▶ dão a volta em 00..99, o carro e o piloto repintam e
## salva; cada rival sai com o número dele no carro e no piloto. O
## user://oficina.json do PC volta como estava no fim.
## Uso: godot --headless --path . -s res://tests/teste_numero.gd

const SALVAS := "user://oficina.json"
var main
var q := 0
var falhas := 0
var _backup = null


func _initialize() -> void:
	_backup = FileAccess.get_file_as_string(SALVAS) if FileAccess.file_exists(SALVAS) else null
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _falha(t: String) -> void:
	print("  FALHA: " + t)
	falhas += 1


func _process(_d: float) -> bool:
	q += 1
	if q == 5:
		var car = main.car
		if car == null or car.piloto == null or car._mats_pintura.is_empty():
			_falha("carro sem piloto ou sem camadas (rode o tools/piloto.py e o gerar_pintura.py)")
			return _fim()
		var PP = load("res://carro/piloto_pintura.gd")
		car.pintar_piloto({})
		var tex0: PackedByteArray = car._mats_pintura[0].albedo_texture.get_image().get_data()
		var pil0: PackedByteArray = _tex_piloto(car)
		for d in [10, 1, -10, -10]:          # 00 -> 10 -> 11 -> 01 -> 91
			main.oficina._passo_extra("numero", d)
		var n := String(car.piloto_escolhas.get("numero", ""))
		if n != "91":
			_falha("número depois de +10 +1 -10 -10: %s (esperado 91)" % n)
		if main.oficina._nomes_peca.has("numero") and main.oficina._nomes_peca.numero.text != "91":
			_falha("a oficina mostra %s" % main.oficina._nomes_peca.numero.text)
		if car._mats_pintura[0].albedo_texture.get_image().get_data() == tex0:
			_falha("o carro não repintou")
		if _tex_piloto(car) == pil0:
			_falha("o piloto não repintou")
		if String(PP.salvas().get("numero", "")) != "91":
			_falha("não salvou: %s" % PP.salvas())
		car.pintar_piloto({})
		if car._mats_pintura[0].albedo_texture.get_image().get_data() != tex0:
			_falha("voltar pro 00 não deixou o carro igual")
		print("  oficina: 00 -> 91 pelos botões, carro e piloto repintados e salvo")
		main.corrida.comecar()
		main.corrida.comecar()            # pula a introdução
	if q == 30:
		var ia = main.corrida.ia
		var n_ok := 0
		for r in ia.rivais:
			var cp = r.car
			var num := "%02d" % (int(r.numero) % 100)
			if String(cp.piloto_escolhas.get("numero", "")) != num:
				_falha("rival nº %d sem o número (%s)" % [r.numero, cp.piloto_escolhas])
				continue
			if cp._pintura and not cp._mats_pintura.is_empty():
				var ref: PackedByteArray = cp._pintura.montar(cp.cores_pintura.merged({"numero": num})).get_data()
				if cp._mats_pintura[0].albedo_texture.get_image().get_data() != ref:
					_falha("rival nº %s: carro sem o número" % num)
					continue
			if cp.piloto and cp._piloto_pintura and _tex_piloto(cp) != cp._piloto_pintura.montar(cp.piloto_escolhas).get_data():
				_falha("rival nº %s: piloto sem o número" % num)
				continue
			n_ok += 1
		print("  rivais: %d de %d com o número do AIPlayers no carro e no piloto" % [n_ok, ia.rivais.size()])
		return _fim()
	return false


func _tex_piloto(c) -> PackedByteArray:
	var m = c.piloto.malha.mesh.surface_get_material(0) if c.piloto and c.piloto.malha and c.piloto.malha.mesh else null
	return m.albedo_texture.get_image().get_data() if m and m.albedo_texture else PackedByteArray()


func _fim() -> bool:
	if _backup == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SALVAS))
	else:
		var f := FileAccess.open(SALVAS, FileAccess.WRITE)
		f.store_string(_backup)
		f.close()
	print("teste_numero: %s" % ("ok" if falhas == 0 else "FALHA (%d)" % falhas))
	quit()
	return true
