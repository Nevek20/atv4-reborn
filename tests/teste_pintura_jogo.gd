extends SceneTree
## Pintura montada em tempo real (carro/pintura.gd, oficina): com as cores de
## fábrica tem que sair IGUAL à pintura.png do gerar_pintura.py (pixel a
## pixel), e o C++ (FisicaCarro.compor_pintura) igual ao GDScript com cores
## da paleta do jogo. Logos: as peças do logos.json com os de fábrica = o
## logos.png, e trocar um logo muda a camada. Precisa das camadas (gerar_pintura.py salva em
## assets/carros/<id>/camadas/). Uso:
##   godot --headless --path . -s res://tests/teste_pintura_jogo.gd


func _initialize() -> void:
	var P = load("res://carro/pintura.gd")
	var pal: Array[Color] = P.paleta()
	var falhas := 0
	var carros := 0
	var t_gd := 0.0
	var t_cpp := 0.0
	var t_logos := 0.0
	var n_logos := 0
	var n_numero := 0
	var cpp := ClassDB.class_exists("FisicaCarro") and ClassDB.class_has_method("FisicaCarro", "compor_pintura")
	if pal.size() != 128:
		print("  paleta: %d cores (esperado 128; rode o gerar_pintura.py)" % pal.size())
		falhas += 1
	elif pal[79] != Color8(35, 188, 153):
		print("  paleta: a cor 80 (coluna 16, linha 5) devia ser 35, 188, 153 (save state pintura.p2s)")
		falhas += 1
	var d := DirAccess.open("res://assets/carros")
	var pastas := d.get_directories() if d else PackedStringArray()
	for nome in pastas:
		var pasta := "res://assets/carros".path_join(nome)
		var p = P.carregar(pasta)
		if p == null:
			continue
		carros += 1
		var ref := Image.new()
		ref.load_png_from_buffer(FileAccess.get_file_as_bytes(pasta.path_join("pintura.png")))
		ref.convert(Image.FORMAT_RGB8)
		var t0 := Time.get_ticks_usec()
		var gd: Image = p.montar({}, false)
		t_gd += (Time.get_ticks_usec() - t0) / 1000.0
		var dif := _diferenca(gd, ref)
		if dif != 0:
			print("  %s: GDScript x pintura.png, %d pixels diferentes" % [nome, dif])
			falhas += 1
		if not cpp:
			continue
		t0 = Time.get_ticks_usec()
		var cc: Image = p.montar({}, true)
		t_cpp += (Time.get_ticks_usec() - t0) / 1000.0
		dif = _diferenca(cc, ref)
		if dif != 0:
			print("  %s: C++ x pintura.png, %d pixels diferentes" % [nome, dif])
			falhas += 1
		# logos: as peças com os de fábrica = o logos.png; trocar um muda a camada
		if not p.info_logos.is_empty():
			n_logos += 1
			t0 = Time.get_ticks_usec()
			var cam: PackedByteArray = p.camada_logos({})
			t_logos += (Time.get_ticks_usec() - t0) / 1000.0
			if cam != p.logos:
				var n := 0
				for i in range(0, cam.size(), 4):
					if cam[i] != p.logos[i] or cam[i + 1] != p.logos[i + 1] or cam[i + 2] != p.logos[i + 2] or cam[i + 3] != p.logos[i + 3]:
						n += 1
				print("  %s: logos de fábrica pelas peças x logos.png, %d pixels diferentes" % [nome, n])
				falhas += 1
			var lug: Array = p.lugares()
			if not lug.is_empty():
				var ch: String = lug[0].chave
				var nomes: Array = p.nomes_logos(ch)
				var outro := ""
				for nm in nomes:
					if nm != p.logo_padrao(ch):
						outro = nm
						break
				if outro != "" and p.camada_logos({ch: outro}) == p.logos:
					print("  %s: trocar o logo de %s não mudou nada" % [nome, ch])
					falhas += 1
			# número do perfil (oficina, Piloto: Número): "00" = o de fábrica, outro muda
			if not p.nomes_logos("NUMERO").is_empty():
				n_numero += 1
				if p.camada_logos({"NUMERO": "00"}) != p.logos:
					print("  %s: número 00 pelas peças x logos.png diferente" % nome)
					falhas += 1
				if p.camada_logos({"NUMERO": "42"}) == p.logos:
					print("  %s: trocar o número não mudou nada" % nome)
					falhas += 1
		# cores da paleta (as do save state: base 80, primária e secundária)
		var cores := {"base": pal[79] if pal.size() > 79 else Color.RED,
			"primary": pal[86] if pal.size() > 86 else Color.GREEN,
			"secondary": pal[0] if pal.size() > 0 else Color.BLUE}
		dif = _diferenca(p.montar(cores, false), p.montar(cores, true))
		if dif != 0:
			print("  %s: C++ x GDScript com outras cores, %d pixels diferentes" % [nome, dif])
			falhas += 1
	if carros == 0:
		print("  nenhum carro com camadas (rode o gerar_pintura.py)")
		falhas += 1
	else:
		print("  %d carros; montar: GDScript %.0f ms, C++ %s por carro; logos (%d carros): %.0f ms; número em %d" % [carros, t_gd / carros,
			"%.1f ms" % (t_cpp / carros) if cpp else "sem a biblioteca", n_logos, t_logos / maxi(n_logos, 1), n_numero])
	print("teste_pintura_jogo: %s" % ("ok" if falhas == 0 else "FALHA (%d)" % falhas))
	quit()


static func _diferenca(a: Image, b: Image) -> int:
	if a == null or b == null or a.get_size() != b.get_size():
		return -1
	var x := a.get_data()
	var y := b.get_data()
	var n := 0
	for i in range(0, x.size(), 3):
		if x[i] != y[i] or x[i + 1] != y[i + 1] or x[i + 2] != y[i + 2]:
			n += 1
	return n
