extends RefCounted
## Pintura do carro montada em tempo real (oficina de pintura). O jogo gera a
## textura "white" juntando camadas (docs/engenharia_reversa.md, Pintura):
## cor BASE em tudo, a PRIMÁRIA pela máscara Primary, a SECUNDÁRIA pela
## Secondary, o Detail (já colorido) e por cima os logos e o número. O
## tools/gerar_pintura.py salva as camadas em <carro>/camadas/ (mascaras.png:
## R = primária, G = secundária; detalhe.png e logos.png RGBA) e as cores de
## fábrica no pintura.json. Aqui só troca as 3 cores e junta de novo, com a
## MESMA conta inteira do PIL (sai igual à pintura.png, pixel a pixel:
## tests/teste_pintura_jogo.gd). No C++ (FisicaCarro.compor_pintura) leva ~1
## ms; o GDScript fica de reserva (mesmo resultado, ~1 s).
## Paleta da oficina: as 128 cores do jogo (assets/pintura/paleta.json, 16
## colunas x 8 linhas, do /Setup/Palette/Palette.bog).
## Logos (oficina, aba Logos): o gerar_pintura salva camadas/logos.json com os
## lugares do carro (HOOD1, SIDE3...: a k-ésima camada Decal da área) e cada
## logo da folha já desenhado em cada caixa (atlas por caixa), mais o número;
## aqui cola as peças na ordem do XML com a conta do alpha_composite do PIL.
## Com os logos de fábrica sai igual ao logos.png (teste_pintura_jogo). O
## número (00..99) é o lugar "NUMERO", com os 100 desenhados em cada caixa.

const PALETA := "res://assets/pintura/paleta.json"
const SALVAS := "user://oficina.json"   # NOSSO: o jogo guarda no perfil
const CORES := ["base", "primary", "secondary"]

var w := 0
var h := 0
var masc := PackedByteArray()     # RGB8: R = máscara da primária, G = da secundária
var det := PackedByteArray()      # RGBA8
var logos := PackedByteArray()    # RGBA8
var fabrica := {}                 # {"base": Color, "primary": Color ou null, "secondary": ...}
var pasta := ""                   # <carro>/camadas
var info_logos := {}              # logos.json ({} = carro sem as peças)
var _atlas := {}                  # nome do png -> [largura, bytes RGBA8]
var _logos_de := {}               # escolhas da última camada de logos montada
var _logos_px := PackedByteArray()


## camadas da pasta do modelo; null se o gerar_pintura não salvou (pintura velha)
static func carregar(pasta: String, livery_file := "pintura.png") -> RefCounted:
	var c := pasta.path_join("camadas")
	var m := _png(c.path_join("mascaras.png"), Image.FORMAT_RGB8)
	var d := _png(c.path_join("detalhe.png"), Image.FORMAT_RGBA8)
	var l := _png(c.path_join("logos.png"), Image.FORMAT_RGBA8)
	if m == null or d == null or l == null or m.get_size() != d.get_size() or d.get_size() != l.get_size():
		return null
	var p = load("res://carro/pintura.gd").new()
	p.w = d.get_width()
	p.h = d.get_height()
	p.masc = m.get_data()
	p.det = d.get_data()
	p.logos = l.get_data()
	var jp := pasta.path_join(livery_file.get_basename() + ".json")
	var j = JSON.parse_string(FileAccess.get_file_as_string(jp)) if FileAccess.file_exists(jp) else null
	for k in CORES:
		var v = j.get(k) if typeof(j) == TYPE_DICTIONARY else null
		p.fabrica[k] = Color8(int(v[0]), int(v[1]), int(v[2])) if v is Array else null
	if p.fabrica.base == null:
		p.fabrica.base = Color(1, 1, 1)
	p.pasta = c
	var lj := c.path_join("logos.json")
	if FileAccess.file_exists(lj):
		var info = JSON.parse_string(FileAccess.get_file_as_string(lj))
		var tam = info.get("tamanho", []) if typeof(info) == TYPE_DICTIONARY else []
		if tam is Array and tam.size() == 2 and int(tam[0]) == p.w and int(tam[1]) == p.h:
			p.info_logos = info
	return p


## PNG cru (a pasta camadas/ tem .gdignore: o Godot não importa nem comprime)
static func _png(path: String, fmt: int) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	if img.get_format() != fmt:
		img.convert(fmt)
	return img


## pintura com estas cores (faltando alguma, a de fábrica) e, em
## cores["logos"], os logos escolhidos ({lugar: nome da folha ou ""}; o lugar
## que falta fica o de fábrica) -> Image RGB8
func montar(cores := {}, cpp := true) -> Image:
	var c := PackedInt32Array()
	for k in CORES:
		var v = cores.get(k, fabrica.get(k))
		if v == null:
			c.append_array([-1, -1, -1])   # sem a camada (o PIL pula: "if c")
		else:
			c.append_array([(v as Color).r8, (v as Color).g8, (v as Color).b8])
	var lg := logos
	if (cores.get("logos") is Dictionary or cores.has("numero")) and not info_logos.is_empty():
		# o número do perfil (piloto) entra como o lugar "NUMERO" (00..99)
		var esc: Dictionary = (cores.get("logos", {}) as Dictionary).duplicate()
		if cores.has("numero"):
			esc["NUMERO"] = String(cores.numero)
		lg = camada_logos(esc)
	var px: PackedByteArray
	if cpp and ClassDB.class_exists("FisicaCarro") and ClassDB.class_has_method("FisicaCarro", "compor_pintura"):
		px = ClassDB.class_call_static("FisicaCarro", "compor_pintura", masc, det, lg, c)
	else:
		px = compor(masc, det, lg, c)
	return Image.create_from_data(w, h, false, Image.FORMAT_RGB8, px)


## a conta (igual ao gerar_pintura.juntar e ao C++): composite do PIL =
## DIV255(fundo x (255 - m) + cor x m); alpha_composite do PIL com 7 bits
static func compor(m: PackedByteArray, d: PackedByteArray, l: PackedByteArray, c: PackedInt32Array) -> PackedByteArray:
	var n := d.size() / 4
	var out := PackedByteArray()
	out.resize(n * 3)
	var tem_p := c[3] >= 0
	var tem_s := c[6] >= 0
	for i in n:
		var i3 := i * 3
		var i4 := i * 4
		var mp: int = m[i3] if tem_p else 0
		var ms: int = m[i3 + 1] if tem_s else 0
		var md: int = d[i4 + 3]
		var la: int = l[i4 + 3]
		for k in 3:
			var v: int = c[k]
			if mp:
				v = _div255(v * (255 - mp) + c[3 + k] * mp)
			if ms:
				v = _div255(v * (255 - ms) + c[6 + k] * ms)
			if md:
				v = _div255(v * (255 - md) + d[i4 + k] * md)
			if la:
				# alpha_composite com o fundo opaco (outa255 = 255 x 255)
				var c1 := la * 255 * 255 * 128 / (la * 255 + 255 * (255 - la))
				var t := l[i4 + k] * c1 + v * (255 * 128 - c1) + (0x80 << 7)
				v = (((t >> 8) + t) >> 8) >> 7
			out[i3 + k] = v
	return out


## ---------------------------------------------------------------- logos
## lugares do carro na ordem do XML: [{chave, area, lugar}]
func lugares() -> Array:
	return info_logos.get("lugares", [])


## logos que cabem num lugar (os da folha dele), na ordem da folha
func nomes_logos(chave: String) -> Array:
	for pc in info_logos.get("pecas", []):
		if pc.chave == chave:
			return info_logos.folhas.get(pc.folha, [])
	return []


func logo_padrao(chave: String) -> String:
	return String(info_logos.get("padrao", {}).get(chave, ""))


## camada dos logos e do número (RGBA8) com estas escolhas
func camada_logos(escolhas: Dictionary) -> PackedByteArray:
	if escolhas == _logos_de and not _logos_px.is_empty():
		return _logos_px
	var out := PackedByteArray()
	out.resize(w * h * 4)
	var padrao: Dictionary = info_logos.get("padrao", {})
	for pc in info_logos.get("pecas", []):
		if pc.chave == "":
			var a = _atlas_de(pc.png)
			if a:
				_colar(out, a[1], a[0], 0, 0, a[0], a[1].size() / 4 / a[0], int(pc.x), int(pc.y))
			continue
		var nome := String(escolhas.get(pc.chave, padrao.get(pc.chave, "")))
		if nome == "":
			continue
		var k: int = info_logos.folhas.get(pc.folha, []).find(nome)
		if k < 0 or k >= pc.itens.size() or pc.itens[k] == null:
			continue
		var it: Array = pc.itens[k]
		var a = _atlas_de(pc.atlas)
		if a:
			_colar(out, a[1], a[0], int(it[0]), int(it[1]), int(it[2]), int(it[3]), int(it[4]), int(it[5]))
	_logos_de = escolhas.duplicate()
	_logos_px = out
	return out


func _atlas_de(nome: String):
	if not _atlas.has(nome):
		var img := _png(pasta.path_join(nome), Image.FORMAT_RGBA8)
		_atlas[nome] = [img.get_width(), img.get_data()] if img else null
	return _atlas[nome]


## alpha_composite do PIL (AlphaComposite.c, 7 bits) do retângulo (sx, sy,
## lw, lh) de src (largura sw) em dst (w x h) no canto (dx, dy)
func _colar(dst: PackedByteArray, src: PackedByteArray, sw: int, sx: int, sy: int, lw: int, lh: int, dx: int, dy: int) -> void:
	for yy in lh:
		var ty := dy + yy
		if ty < 0 or ty >= h:
			continue
		for xx in lw:
			var tx := dx + xx
			if tx < 0 or tx >= w:
				continue
			var si := ((sy + yy) * sw + sx + xx) * 4
			var sa: int = src[si + 3]
			if sa == 0:
				continue
			var di := (ty * w + tx) * 4
			var da: int = dst[di + 3]
			var outa255 := sa * 255 + da * (255 - sa)
			var c1 := sa * 255 * 255 * 128 / outa255
			var c2 := 255 * 128 - c1
			for k in 3:
				var t: int = src[si + k] * c1 + dst[di + k] * c2 + (0x80 << 7)
				dst[di + k] = (((t >> 8) + t) >> 8) >> 7
			var ta := outa255 + 0x80
			dst[di + 3] = ((ta >> 8) + ta) >> 8


static func _div255(a: int) -> int:
	var t := a + 128
	return ((t >> 8) + t) >> 8


## ---------------------------------------------------------------- paleta e salvas
static func paleta() -> Array[Color]:
	var out: Array[Color] = []
	if FileAccess.file_exists(PALETA):
		var j = JSON.parse_string(FileAccess.get_file_as_string(PALETA))
		if j is Array:
			for v in j:
				out.append(Color8(int(v[0]), int(v[1]), int(v[2])))
	return out


## cores (e "logos") salvas do carro ({} = de fábrica)
static func salvas(chave: String) -> Dictionary:
	var j = JSON.parse_string(FileAccess.get_file_as_string(SALVAS)) if FileAccess.file_exists(SALVAS) else null
	var out := {}
	if typeof(j) == TYPE_DICTIONARY and typeof(j.get(chave)) == TYPE_DICTIONARY:
		for k in CORES:
			var v = j[chave].get(k)
			if v is Array and v.size() >= 3:
				out[k] = Color8(int(v[0]), int(v[1]), int(v[2]))
		if j[chave].get("logos") is Dictionary:
			out["logos"] = j[chave].logos
	return out


## grava as cores do carro ({} = volta pra de fábrica)
static func salvar(chave: String, cores: Dictionary) -> void:
	var j = JSON.parse_string(FileAccess.get_file_as_string(SALVAS)) if FileAccess.file_exists(SALVAS) else null
	if typeof(j) != TYPE_DICTIONARY:
		j = {}
	if cores.is_empty():
		j.erase(chave)
	else:
		var e := {}
		for k in cores:
			if cores[k] is Color:
				var v: Color = cores[k]
				e[k] = [v.r8, v.g8, v.b8]
			elif cores[k] is Dictionary:
				e[k] = cores[k]               # logos: {lugar: nome}
		j[chave] = e
	var f := FileAccess.open(SALVAS, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(j, "\t"))
