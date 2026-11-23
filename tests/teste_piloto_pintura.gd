extends SceneTree
## Textura do piloto montada em tempo real (carro/piloto_pintura.gd, oficina
## aba Piloto): com o perfil padrão tem que sair IGUAL ao piloto.png do
## tools/piloto_pintura.py, e com o piloto dos saves do Matheus (roupa 11,
## capacete 9, óculos 12, luva 3, bota 10 e as cores do Paint Shop) igual ao
## camadas/teste_ref.png; o C++ (FisicaCarro.compor_piloto) igual ao GDScript.
## Uso: godot --headless --path . -s res://tests/teste_piloto_pintura.gd


func _initialize() -> void:
	var falhas := 0
	var P = load("res://carro/piloto_pintura.gd")
	var p = P.carregar()
	if p == null:
		print("teste_piloto_pintura: FALHA (sem assets/piloto/camadas: rode o tools/piloto.py)")
		quit()
		return
	var cpp := ClassDB.class_exists("FisicaCarro") and ClassDB.class_has_method("FisicaCarro", "compor_piloto")
	for caso in [["padrão", {}, "res://assets/piloto/piloto.png"],
			["saves do Matheus", p.info.get("teste", {}), "res://assets/piloto/camadas/teste_ref.png"]]:
		var ref := Image.new()
		if ref.load_png_from_buffer(FileAccess.get_file_as_bytes(caso[2])) != OK:
			print("  %s: sem a referência %s" % [caso[0], caso[2]])
			falhas += 1
			continue
		ref.convert(Image.FORMAT_RGB8)
		var t0 := Time.get_ticks_usec()
		var gd: Image = p.montar(caso[1], false)
		var t_gd := (Time.get_ticks_usec() - t0) / 1000.0
		var dif := _diferenca(gd, ref)
		print("  %s: GDScript %.0f ms, %d pixels diferentes" % [caso[0], t_gd, dif])
		if dif != 0:
			falhas += 1
		if cpp:
			t0 = Time.get_ticks_usec()
			var cc: Image = p.montar(caso[1], true)
			var t_cpp := (Time.get_ticks_usec() - t0) / 1000.0
			dif = _diferenca(cc, ref)
			print("  %s: C++ %.1f ms, %d pixels diferentes" % [caso[0], t_cpp, dif])
			if dif != 0:
				falhas += 1
	print("teste_piloto_pintura: %s" % ("ok" if falhas == 0 else "FALHA (%d)" % falhas))
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
