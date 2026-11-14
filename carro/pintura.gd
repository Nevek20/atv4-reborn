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

const PALETA := "res://assets/pintura/paleta.json"
const SALVAS := "user://oficina.json"   # NOSSO: o jogo guarda no perfil
const CORES := ["base", "primary", "secondary"]

var w := 0
var h := 0
var masc := PackedByteArray()     # RGB8: R = máscara da primária, G = da secundária
var det := PackedByteArray()      # RGBA8
var logos := PackedByteArray()    # RGBA8
var fabrica := {}                 # {"base": Color, "primary": Color ou null, "secondary": ...}


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


## pintura com estas cores (faltando alguma, a de fábrica) -> Image RGB8
func montar(cores := {}, cpp := true) -> Image:
	var c := PackedInt32Array()
	for k in CORES:
		var v = cores.get(k, fabrica.get(k))
		if v == null:
			c.append_array([-1, -1, -1])   # sem a camada (o PIL pula: "if c")
		else:
			c.append_array([(v as Color).r8, (v as Color).g8, (v as Color).b8])
	var px: PackedByteArray
	if cpp and ClassDB.class_exists("FisicaCarro") and ClassDB.class_has_method("FisicaCarro", "compor_pintura"):
		px = ClassDB.class_call_static("FisicaCarro", "compor_pintura", masc, det, logos, c)
	else:
		px = compor(masc, det, logos, c)
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


## cores salvas do carro ({} = de fábrica)
static func salvas(chave: String) -> Dictionary:
	var j = JSON.parse_string(FileAccess.get_file_as_string(SALVAS)) if FileAccess.file_exists(SALVAS) else null
	var out := {}
	if typeof(j) == TYPE_DICTIONARY and typeof(j.get(chave)) == TYPE_DICTIONARY:
		for k in CORES:
			var v = j[chave].get(k)
			if v is Array and v.size() >= 3:
				out[k] = Color8(int(v[0]), int(v[1]), int(v[2]))
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
			var v: Color = cores[k]
			e[k] = [v.r8, v.g8, v.b8]
		j[chave] = e
	var f := FileAccess.open(SALVAS, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(j, "\t"))
