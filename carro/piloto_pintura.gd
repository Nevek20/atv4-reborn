extends RefCounted
## Textura do piloto montada em tempo real (oficina, aba Piloto). Como o jogo
## (Setup/CharacterComposite/Textures/COMPOSITOR.xml, docs Piloto): uma caixa
## por parte (RIDER.bed) e, em cada uma, as camadas do modelo escolhido:
## BASE x cor base (Blend Off), PRIMARY x primária e SECONDARY x secundária
## por cima pelo alfa, DETAIL (já colorida) pelo alfa e WRINKLE multiplicando
## o RGB. Roupa = CLOTHING, ARMS e LEGS; capacete, óculos, luva e bota uma
## parte cada; rosto e cabelo copiados; nome e número na cor TEXT. As cores
## valem pro piloto todo. O tools/piloto_pintura.py salva as camadas já no
## tamanho da caixa (assets/piloto/camadas/) e o piloto.json; aqui a conta
## inteira é a mesma do PIL (tests/teste_piloto_pintura.gd confere pixel a
## pixel). As 7 partes no C++ (FisicaCarro.compor_piloto, ~ms); o GDScript
## fica de reserva (mesmo resultado, segundos).

const PASTA := "res://assets/piloto/camadas"
const SALVAS := "user://oficina.json"   # NOSSO (o jogo guarda no perfil): chave "piloto"
const CORES := ["base", "primary", "secondary", "text"]
const PECAS := ["roupa", "capacete", "oculos", "luva", "bota"]
const CAMADAS := ["base", "primary", "secondary", "detail", "wrinkle"]

var info := {}
var tam := 512
var _cache := {}                     # nome do png -> [largura, bytes RGBA8]


static func carregar() -> RefCounted:
	var jp := PASTA.path_join("piloto.json")
	if not FileAccess.file_exists(jp):
		return null
	var j = JSON.parse_string(FileAccess.get_file_as_string(jp))
	if typeof(j) != TYPE_DICTIONARY:
		return null
	var p = load("res://carro/piloto_pintura.gd").new()
	p.info = j
	p.tam = int(j.get("tamanho", 512))
	return p


## escolhas completas: o padrão do perfil com o que veio por cima
func completo(esc: Dictionary) -> Dictionary:
	var out: Dictionary = (info.padrao as Dictionary).duplicate(true)
	for k in esc:
		if k == "cores":
			for c in esc.cores:
				out.cores[c] = esc.cores[c]
		else:
			out[k] = esc[k]
	return out


## cores de fábrica da roupa (DefaultColours do CLOTHING.xml, uma por roupa)
func cores_da_roupa(n: int) -> Dictionary:
	var lista: Array = info.get("cores_padrao", [])
	return (lista[clampi(n - 1, 0, lista.size() - 1)] as Dictionary).duplicate(true) if not lista.is_empty() else {}


func quantos(peca: String) -> int:
	return (info.get("modelos", {}).get(peca, []) as Array).size()


## textura (Image RGB8) com estas escolhas (as que faltam = padrão)
func montar(esc := {}, cpp := true) -> Image:
	var e := completo(esc)
	var c := PackedInt32Array()
	for k in ["base", "primary", "secondary"]:
		var v: Array = e.cores[k]
		c.append_array([int(v[0]), int(v[1]), int(v[2])])
	# as 7 partes (o grosso): [x, y, w, h, base, primary, secondary, detail, wrinkle]
	var partes: Array = []
	for pt in info.partes:
		var cx: Array = info.caixas[pt[0]]
		var item: Array = [int(cx[0]), int(cx[1]), int(cx[2]), int(cx[3])]
		for cam in CAMADAS:
			var a = _png("%s_%02d_%s.png" % [pt[2], int(e[pt[1]]), cam])
			item.append(a[1] if a else PackedByteArray())
		partes.append(item)
	var px: PackedByteArray
	if cpp and ClassDB.class_exists("FisicaCarro") and ClassDB.class_has_method("FisicaCarro", "compor_piloto"):
		px = ClassDB.class_call_static("FisicaCarro", "compor_piloto", tam, partes, c)
	else:
		px = compor(tam, partes, c)
	# rosto e cabelo (Blend Off: copia) e o nome e o número na cor TEXT
	for par in [["FACE", "face_%s_%d.png" % [e.sexo, int(e.rosto)]], ["HAIR", "hair_%d.png" % int(e.cabelo)]]:
		var cx: Array = info.caixas[par[0]]
		var a = _png(par[1])
		if a:
			_copiar(px, a[1], a[0], int(cx[0]), int(cx[1]), int(cx[2]), int(cx[3]))
	var tc: Array = e.cores.text
	for box in ["PLAYER_NAME", "PLAYER_NUMBER"]:
		var t = info.textos.get(box)
		if t == null:
			continue
		if t.has("atlas"):
			# número do perfil (00..99), recortado do atlas dos 100
			var k := String(e.get("numero", "00")).to_int()
			var it = (t.itens as Array)[clampi(k, 0, (t.itens as Array).size() - 1)]
			var at = _png(t.atlas)
			if it and at:
				_texto(px, _recorte(at, it), int(it[2]), int(it[4]), int(it[5]), tc)
			continue
		var a = _png(t.png)
		if a:
			_texto(px, a[1], a[0], int(t.x), int(t.y), tc)
	return Image.create_from_data(tam, tam, false, Image.FORMAT_RGB8, px)


## a conta das partes (igual ao tools/piloto_pintura.juntar_parte e ao C++)
static func compor(t: int, partes: Array, c: PackedInt32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(t * t * 3)
	for pt in partes:
		var x0: int = pt[0]
		var y0: int = pt[1]
		var w: int = pt[2]
		var h: int = pt[3]
		var ba: PackedByteArray = pt[4]
		var pr: PackedByteArray = pt[5]
		var se: PackedByteArray = pt[6]
		var de: PackedByteArray = pt[7]
		var ru: PackedByteArray = pt[8]
		if ba.size() < w * h * 4:
			continue
		for yy in h:
			for xx in w:
				var i := (yy * w + xx) * 4
				var o := ((y0 + yy) * t + x0 + xx) * 3
				var ap: int = pr[i + 3]
				var asx: int = se[i + 3]
				var ad: int = de[i + 3]
				for k in 3:
					var v: int = ba[i + k] * c[k] / 255
					v = _div255(v * (255 - ap) + (pr[i + k] * c[3 + k] / 255) * ap)
					v = _div255(v * (255 - asx) + (se[i + k] * c[6 + k] / 255) * asx)
					v = _div255(v * (255 - ad) + de[i + k] * ad)
					out[o + k] = v * ru[i + k] / 255
	return out


static func _div255(a: int) -> int:
	var t := a + 128
	return ((t >> 8) + t) >> 8


func _copiar(dst: PackedByteArray, src: PackedByteArray, sw: int, x0: int, y0: int, w: int, h: int) -> void:
	for yy in h:
		for xx in w:
			var i := (yy * sw + xx) * 4
			var o := ((y0 + yy) * tam + x0 + xx) * 3
			dst[o] = src[i]
			dst[o + 1] = src[i + 1]
			dst[o + 2] = src[i + 2]


## alpha_composite do PIL do texto tingido (o fundo é opaco)
func _texto(dst: PackedByteArray, src: PackedByteArray, sw: int, x0: int, y0: int, cor: Array) -> void:
	var sh := src.size() / 4 / sw
	for yy in sh:
		var ty := y0 + yy
		if ty < 0 or ty >= tam:
			continue
		for xx in sw:
			var tx := x0 + xx
			if tx < 0 or tx >= tam:
				continue
			var i := (yy * sw + xx) * 4
			var sa: int = src[i + 3]
			if sa == 0:
				continue
			var o := (ty * tam + tx) * 3
			var outa255 := sa * 255 + 255 * (255 - sa)
			var c1 := sa * 255 * 255 * 128 / outa255
			var c2 := 255 * 128 - c1
			for k in 3:
				var s: int = src[i + k] * int(cor[k]) / 255
				var tt: int = s * c1 + dst[o + k] * c2 + (0x80 << 7)
				dst[o + k] = (((tt >> 8) + tt) >> 8) >> 7


## pedaço [x, y, w, h, ...] do atlas (largura, bytes RGBA8) -> bytes RGBA8
static func _recorte(at: Array, it: Array) -> PackedByteArray:
	var sw: int = at[0]
	var src: PackedByteArray = at[1]
	var out := PackedByteArray()
	for yy in int(it[3]):
		var i := ((int(it[1]) + yy) * sw + int(it[0])) * 4
		out.append_array(src.slice(i, i + int(it[2]) * 4))
	return out


func _png(nome: String):
	if not _cache.has(nome):
		var path := PASTA.path_join(nome)
		var img: Image = null
		if FileAccess.file_exists(path):
			img = Image.new()
			if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
				img = null
			elif img.get_format() != Image.FORMAT_RGBA8:
				img.convert(Image.FORMAT_RGBA8)
		_cache[nome] = [img.get_width(), img.get_data()] if img else null
	return _cache[nome]


## ---------------------------------------------------------------- salvas
static func salvas() -> Dictionary:
	var j = JSON.parse_string(FileAccess.get_file_as_string(SALVAS)) if FileAccess.file_exists(SALVAS) else null
	if typeof(j) == TYPE_DICTIONARY and typeof(j.get("piloto")) == TYPE_DICTIONARY:
		return j.piloto
	return {}


static func salvar(esc: Dictionary) -> void:
	var j = JSON.parse_string(FileAccess.get_file_as_string(SALVAS)) if FileAccess.file_exists(SALVAS) else null
	if typeof(j) != TYPE_DICTIONARY:
		j = {}
	if esc.is_empty():
		j.erase("piloto")
	else:
		j["piloto"] = esc
	var f := FileAccess.open(SALVAS, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(j, "\t"))
