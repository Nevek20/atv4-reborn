extends ColorRect
## Tela preta da reposição do jogador: o fader da câmera do jogo (viewport
## +0x114, update 0x2b3700). Indo pro preto: alfa += dt / +0xd0; voltando:
## alfa -= dt / +0xd4; os dois 0.2 s na RAM (pause, placar_final e
## andando_em_linha_reta). O pedido de reposição (0x15bd28) liga o preto
## (0x4576c8) e, com o carro já reposto (0x15bfe0), volta (0x4576e0).
## Fica embaixo do HUD (main.gd).

const T_ESCURECE := 0.2          # fader+0xd0
const T_CLAREIA := 0.2           # fader+0xd4

var alvo := 0.0                  # fader+0xd8: 1 indo pro preto, 0 voltando
var alfa := 0.0                  # fader+0xdc


func _init() -> void:
	color = Color.BLACK
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_aplicar()


func escurecer() -> void:
	alvo = 1.0


func clarear() -> void:
	alvo = 0.0


## corrida recomeçou ou parou: some na hora
func zerar() -> void:
	alvo = 0.0
	alfa = 0.0
	_aplicar()


func passo(dt: float) -> void:
	if alvo > 0.0:
		alfa = minf(alfa + dt / T_ESCURECE, 1.0)
	else:
		alfa = maxf(alfa - dt / T_CLAREIA, 0.0)
	_aplicar()


func _process(dt: float) -> void:
	if alfa > 0.0 or alvo > 0.0:
		passo(dt)


func _aplicar() -> void:
	color.a = alfa
	visible = alfa > 0.0
