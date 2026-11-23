extends VBoxContainer
## HUD básico (NOSSO, provisório até portar o HUD do jogo): marcha e
## velocidade no canto inferior direito, só nas câmeras de terceira pessoa
## (perto e longe) e fora da introdução e da descida da câmera na corrida.
## Velocidade = a do velocímetro do jogo: 1.06 x a velocidade PRA FRENTE
## (save states derrapando, docs/historico.md; a mesma conta do painel.gd).
## Marcha = car.gear_label() ("-" trocando, N, R). F1 alterna no main: tudo /
## só este HUD / nada. O texto muda no máximo ~75 vezes por segundo (PASSO,
## como o PASSO_HUD da corrida).

const PASSO := 1.0 / 75.0
const VELOCIMETRO := 1.06

var main
var marcha: Label
var vel: Label
var _dt := 0.0


func _init(m) -> void:
	main = m
	name = "HudBasico"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_top = 1.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_right = -32.0
	offset_bottom = -20.0
	add_theme_constant_override("separation", -14)
	marcha = _rotulo(76)
	add_child(marcha)
	var linha := HBoxContainer.new()
	linha.alignment = BoxContainer.ALIGNMENT_END
	linha.mouse_filter = Control.MOUSE_FILTER_IGNORE
	linha.add_theme_constant_override("separation", 6)
	add_child(linha)
	vel = _rotulo(44)
	vel.custom_minimum_size.x = 84.0          # 3 dígitos: o "km/h" não pula
	linha.add_child(vel)
	var un := _rotulo(20)
	un.text = "km/h"
	un.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	un.size_flags_vertical = Control.SIZE_FILL
	linha.add_child(un)


func _rotulo(tam: int) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", maxi(6, tam / 7))
	return l


## km/h do velocímetro do jogo
static func kmh(car) -> float:
	return absf(car.linear_velocity.dot(car.global_transform.basis.z)) * 3.6 * VELOCIMETRO


func atualizar(dt: float, car, mostrar: bool) -> void:
	visible = mostrar and car != null
	if not visible:
		_dt = PASSO
		return
	_dt += dt
	if _dt < PASSO:
		return
	_dt = 0.0
	marcha.text = car.gear_label()
	vel.text = str(int(kmh(car)))
