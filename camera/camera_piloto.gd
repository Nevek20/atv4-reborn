extends Node
## Câmera do piloto com sensação de velocidade (melhoria nossa: o jogo não tem
## câmera de dentro; a posição do olho é a calibrada no car.gd, FP_*).
## Referências do Matheus: The Crew Motorfest (a cabeça sente o carro) e o
## olhar livre do Forza.
##
## Efeitos (EFEITOS, um por um pro menu de opções que vier; G liga/desliga
## todos pra comparar):
##   forca_g  cabeça numa mola amortecida (pescoço) no frame do carro: a
##            aceleração medida a cada passo da física empurra ao contrário
##            (freou = cabeça pra frente e olha um pouco pra baixo, acelerou =
##            pra trás, curva = pra fora e inclina, pulo = afunda no pouso)
##   fov      o campo de visão abre com a velocidade
##   curva    a cabeça vira pra onde o carro está indo (ângulo de deriva) e
##            adianta pela guinada, como o "olhar pra curva" do Forza
##   borrao   zoom radial só nas bordas da tela em velocidade alta
## Olhar livre (sempre ligado): analógico direito ou mouse com o botão direito
## apertado; soltou, volta pro centro. A cabeça gira em volta do pescoço
## (PESCOCO atrás do olho), não do olho.

const EFEITOS_PADRAO := {"forca_g": true, "fov": true, "curva": true, "borrao": true}

# cabeça (mola de pescoço por eixo, no frame do carro)
const CABECA_HZ := 1.6            # frequência natural
const CABECA_AMORT := 0.7         # fração do amortecimento crítico
const CABECA_GANHO := 0.6         # 1 g de freada -> ~6 cm pra frente parado na mola
const CABECA_GANHO_Y := 0.25      # vertical mais dura (pulo, pouso)
const CABECA_MAX := Vector3(0.06, 0.05, 0.08)   # m: lado, cima, frente (chega aos poucos, tanh)
const INCLINA := 0.4              # rad por m: cabeça pra frente olha pra baixo
const ROLA := 0.5                 # rad por m: cabeça de lado inclina
const ACEL_FILTRO := 0.04         # s: tira o serrilhado do passo de 50 Hz

# campo de visão
const FOV_EXTRA := 12.0           # graus a mais no máximo
const FOV_V0 := 10.0              # m/s (36 km/h): começa a abrir
const FOV_V1 := 60.0              # m/s (216 km/h): aberto todo
const FOV_SUAVE := 0.4            # s

# olhar pra curva
const CURVA_DERIVA := 0.6         # fração do ângulo de deriva
const CURVA_GUINADA := 0.15       # s de adiantamento pela guinada
const CURVA_MAX := deg_to_rad(25.0)
const CURVA_SUAVE := 0.25         # s
const CURVA_V0 := 3.0             # m/s: abaixo disso não vira
const CURVA_V1 := 8.0             # m/s: daqui pra cima vira tudo

# olhar livre
const LIVRE_LADO := deg_to_rad(150.0)
const LIVRE_CIMA := deg_to_rad(35.0)
const LIVRE_SUAVE := 0.08         # s
const MOUSE_SENS := 0.005         # rad por pixel
const ZONA_MORTA := 0.15          # analógico
const PESCOCO := 0.10             # m: pivô da cabeça atrás do olho

# borrão nas bordas
const BORRAO_V0 := 20.0           # m/s (72 km/h)
const BORRAO_V1 := 55.0           # m/s (~200 km/h)
const BORRAO_MAX := 0.06          # quanto o zoom radial puxa no máximo

const SHADER_BORRAO := """
shader_type canvas_item;
uniform sampler2D tela : hint_screen_texture, filter_linear_mipmap;
uniform float forca = 0.0;               // 0..1
uniform vec2 centro = vec2(0.5, 0.45);

void fragment() {
	vec2 d = SCREEN_UV - centro;
	float aspecto = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float r = length(d * vec2(aspecto, 1.0));
	float m = smoothstep(0.3, 0.75, r) * forca * %f;
	vec3 c = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		c += textureLod(tela, centro + d * (1.0 - m * float(i) / 7.0), 0.0).rgb;
	}
	COLOR = vec4(c / 8.0, 1.0);
}
"""

static var efeitos := EFEITOS_PADRAO.duplicate()
var ligado := true                # G

var car = null
var _v_ant := Vector3.ZERO
var _tem_v := false
var acel := Vector3.ZERO          # aceleração filtrada, frame do carro (m/s²)
var cabeca := Vector3.ZERO        # deslocamento da cabeça, frame do carro (m)
var _cabeca_ant := Vector3.ZERO
var _mola := Vector3.ZERO         # posição da mola (sem limite)
var _cabeca_vel := Vector3.ZERO
var fov_extra := 0.0
var curva := 0.0                  # rad
var livre := Vector2.ZERO         # (lado, cima) atual, rad
var _livre_alvo := Vector2.ZERO
var _mouse := false               # botão direito apertado
var borrao := 0.0
var _tela: ColorRect = null


func _ready() -> void:
	var camada := CanvasLayer.new()
	camada.layer = 0                  # embaixo do HUD (camada 1)
	add_child(camada)
	_tela = ColorRect.new()
	_tela.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tela.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER_BORRAO % BORRAO_MAX
	var m := ShaderMaterial.new()
	m.shader = sh
	_tela.material = m
	_tela.visible = false
	camada.add_child(_tela)


func ativo(e: String) -> bool:
	return ligado and efeitos.get(e, false)


## troca de carro / recomeço: sem tranco da velocidade velha
func reiniciar() -> void:
	_tem_v = false
	acel = Vector3.ZERO
	cabeca = Vector3.ZERO
	_cabeca_ant = Vector3.ZERO
	_mola = Vector3.ZERO
	_cabeca_vel = Vector3.ZERO
	curva = 0.0


func _physics_process(dt: float) -> void:
	if car == null or not is_instance_valid(car) or dt <= 0.0:
		return
	var v: Vector3 = car.linear_velocity
	var b: Basis = car.global_transform.basis.orthonormalized()
	if not _tem_v:
		_v_ant = v
		_tem_v = true
	var a_mundo := (v - _v_ant) / dt
	_v_ant = v
	passo_cabeca(dt, b.transposed() * a_mundo)


## mola do pescoço: a cabeça fica parada no mundo e o carro acelera embaixo
## dela (deslocamento = -aceleração · ganho / ω² parado na mola). O que a
## câmera usa chega no limite aos poucos (tanh): a freada do Renegade dá 1.8 g
## e com corte seco a cabeça ficava grudada no limite
func passo_cabeca(dt: float, a_local: Vector3) -> void:
	acel += (a_local - acel) * (1.0 - exp(-dt / ACEL_FILTRO))
	_cabeca_ant = cabeca
	var alvo := Vector3.ZERO
	if ativo("forca_g"):
		alvo = -Vector3(acel.x * CABECA_GANHO, acel.y * CABECA_GANHO_Y, acel.z * CABECA_GANHO)
	var w := TAU * CABECA_HZ
	var f := alvo - _mola * w * w - _cabeca_vel * 2.0 * CABECA_AMORT * w
	_cabeca_vel += f * dt
	_mola += _cabeca_vel * dt
	cabeca = Vector3(CABECA_MAX.x * tanh(_mola.x / CABECA_MAX.x), CABECA_MAX.y * tanh(_mola.y / CABECA_MAX.y),
		CABECA_MAX.z * tanh(_mola.z / CABECA_MAX.z))


## por quadro: campo de visão, olhar pra curva e olhar livre. v_local =
## velocidade no frame do carro, guinada = rad/s em volta do eixo de cima
func passo_quadro(dt: float, v_local: Vector3, guinada: float) -> void:
	var vel := v_local.length()
	var f_fov := 0.0
	if ativo("fov"):
		f_fov = pow(clampf((vel - FOV_V0) / (FOV_V1 - FOV_V0), 0.0, 1.0), 1.2) * FOV_EXTRA
	fov_extra += (f_fov - fov_extra) * (1.0 - exp(-dt / FOV_SUAVE))
	var alvo_c := 0.0
	if ativo("curva"):
		var peso := clampf((vel - CURVA_V0) / (CURVA_V1 - CURVA_V0), 0.0, 1.0)
		var deriva := atan2(v_local.x, absf(v_local.z)) if vel > 0.5 else 0.0
		alvo_c = clampf(deriva * CURVA_DERIVA + guinada * CURVA_GUINADA, -CURVA_MAX, CURVA_MAX) * peso
	curva += (alvo_c - curva) * (1.0 - exp(-dt / CURVA_SUAVE))
	# analógico direito (o mouse mexe no alvo direto)
	if not _mouse:
		_livre_alvo = Vector2.ZERO
		if Input.get_connected_joypads().size() > 0:
			var ax := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
			if ax.length() > ZONA_MORTA:
				ax = ax.normalized() * (ax.length() - ZONA_MORTA) / (1.0 - ZONA_MORTA)
				_livre_alvo = Vector2(-ax.x * LIVRE_LADO, -ax.y * LIVRE_CIMA)
	livre += (_livre_alvo - livre) * (1.0 - exp(-dt / LIVRE_SUAVE))
	var f_b := 0.0
	if ativo("borrao"):
		f_b = clampf((vel - BORRAO_V0) / (BORRAO_V1 - BORRAO_V0), 0.0, 1.0)
	borrao += (f_b - borrao) * (1.0 - exp(-dt / FOV_SUAVE))


## mouse: botão direito apertado arrasta o olhar; soltou, volta
func mouse_botao(apertado: bool) -> void:
	_mouse = apertado
	if not apertado:
		_livre_alvo = Vector2.ZERO


func mouse_arrasto(rel: Vector2) -> void:
	if not _mouse:
		return
	_livre_alvo = Vector2(clampf(_livre_alvo.x - rel.x * MOUSE_SENS, -LIVRE_LADO, LIVRE_LADO),
		clampf(_livre_alvo.y - rel.y * MOUSE_SENS, -LIVRE_CIMA, LIVRE_CIMA))


## câmera do quadro: olho calibrado + cabeça + giros. b = base do carro
## (interpolada), olho = posição do olho no mundo, inclinacao = FP_PITCH
func transformada(b: Basis, olho: Vector3, inclinacao: float) -> Transform3D:
	var fr := Engine.get_physics_interpolation_fraction()
	var cab := _cabeca_ant.lerp(cabeca, fr)
	# (lado, cima) do olhar livre somem um pouco do olhar pra curva
	var lado := livre.x + curva * (1.0 - minf(1.0, absf(livre.x) / 0.5))
	var baixo := atan(inclinacao) - livre.y + cab.z * INCLINA
	var rola := -cab.x * ROLA
	var giro := Basis(Vector3.UP, lado) * Basis(Vector3.RIGHT, baixo)
	var cam_local := giro * Basis(Vector3.UP, PI) * Basis(Vector3.BACK, rola)
	# pescoço: o olho gira em volta de um ponto atrás dele (só pelo olhar
	# livre e pela curva; parado o olho fica no lugar calibrado)
	var pescoco := Basis(Vector3.UP, lado) * Basis(Vector3.RIGHT, -livre.y)
	var olho_local := Vector3(0, 0, -PESCOCO) + pescoco * Vector3(0, 0, PESCOCO) + cab
	return Transform3D(b * cam_local, olho + b * olho_local)


func atualizar_tela(visivel: bool) -> void:
	_tela.visible = visivel and borrao > 0.01
	if _tela.visible:
		(_tela.material as ShaderMaterial).set_shader_parameter("forca", borrao)
