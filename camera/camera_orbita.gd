extends RefCounted
## Órbita da câmera de corrida (melhoria nossa; referência do Matheus: o
## analógico direito do Forza). O jogo não tem: a câmera de corrida
## (game_camera.gd) fica sempre atrás do carro.
##
## Analógico direito: o ÂNGULO dele é pra onde a câmera olha (direita = olha
## pra direita do carro, pra baixo = olha pra trás, de frente pro carro);
## girando o analógico em volta a câmera dá a volta inteira no carro, quantas
## vezes quiser. Meio caminho gira menos (até CHEIO). Mouse: botão direito
## apertado arrasta (pros lados sem limite, pra cima e pra baixo um pouco).
## Soltou, volta pro lugar pelo caminho mais curto.
##
## A câmera do jogo continua rodando por baixo (altura, distância, zoom,
## tremida): aqui só gira o resultado dela em volta da origem do modelo (onde
## ela mira, veículo +0xaa0), mirando no mesmo ponto. Sem mexer no analógico
## nada muda (0 de giro = a câmera do jogo).

const GameCamera := preload("res://camera/game_camera.gd")

const ZONA_MORTA := 0.2           # analógico
const CHEIO := 0.75               # deflexão (fora da zona morta) do ângulo todo
const SEGUE := 0.08               # s: vai pro ângulo do analógico
const VOLTA := 0.30               # s: soltou, volta pra trás do carro
const VEL_MIN := 0.25             # rad/s: no fim da volta anda pelo menos isso (chega certinho, sem rabo)
const MOUSE_SENS := 0.006         # rad por pixel
const CIMA_MIN := deg_to_rad(-12.0)   # mouse: desce até aqui
const CIMA_MAX := deg_to_rad(40.0)    # e sobe até aqui

var giro := 0.0                   # rad em volta do eixo de cima (+ = câmera pra direita do carro, olhando pra esquerda)
var cima := 0.0                   # rad: + = câmera mais alta
var _alvo_giro := 0.0
var _alvo_cima := 0.0
var _segura := false              # analógico ou mouse segurando
var _mouse := false
var _ang_ant := 0.0               # ângulo do analógico do quadro anterior (desenrolado)
var analogico_teste = null        # Vector2: testes sem controle (tests/teste_camera_orbita.gd)


func ativa() -> bool:
	return absf(giro) > 1e-4 or absf(cima) > 1e-4


## um quadro: lê o analógico e anda pro alvo
func passo(dt: float) -> void:
	var segura_analogico := false
	var tem := analogico_teste != null or Input.get_connected_joypads().size() > 0
	if not _mouse and tem:
		var ax: Vector2 = analogico_teste if analogico_teste != null else \
			Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
		var m := ax.length()
		if m > ZONA_MORTA:
			m = minf((m - ZONA_MORTA) / (1.0 - ZONA_MORTA), 1.0)
			# olhar pra direita = ângulo + (Godot: y do analógico pra baixo = +)
			var a := atan2(ax.x, -ax.y)
			# desenrola perto do anterior: girando o analógico em volta não pula
			# de +180 pra -180 (a câmera continua dando a volta)
			var ref := _ang_ant if _segura else -giro
			a += TAU * roundf((ref - a) / TAU)
			var esc := minf(m / CHEIO, 1.0)
			if esc >= 1.0 and absf(a) > PI:
				# deflexão toda: tira as voltas inteiras do ângulo e do giro
				# juntos (a câmera fica onde está); senão, depois de várias voltas,
				# aliviar o analógico desenrolava todas
				var k := TAU * roundf(a / TAU)
				a -= k
				giro += k
			_ang_ant = a
			_alvo_giro = -a * esc
			_alvo_cima = 0.0
			segura_analogico = true
	if not segura_analogico and not _mouse and _segura:
		_solta()
	_segura = segura_analogico or _mouse
	var tau := SEGUE if _segura else VOLTA
	var k := 1.0 - exp(-dt / tau)
	giro = _anda(giro, _alvo_giro, k, VEL_MIN * dt)
	cima = _anda(cima, _alvo_cima, k, VEL_MIN * dt)


## anda a fração k do que falta, mas pelo menos passo_min (chega no alvo)
static func _anda(x: float, alvo: float, k: float, passo_min: float) -> float:
	var falta := alvo - x
	var d := falta * k
	if absf(d) < passo_min:
		d = clampf(falta, -passo_min, passo_min)
	return x + d


## soltou: volta pelo caminho mais curto (depois de dar várias voltas também)
func _solta() -> void:
	giro = wrapf(giro, -PI, PI)
	_alvo_giro = 0.0
	_alvo_cima = 0.0


func mouse_botao(apertado: bool) -> void:
	if apertado and not _mouse:
		_alvo_giro = giro
		_alvo_cima = cima
	_mouse = apertado
	if not apertado:
		_segura = false
		_solta()


func mouse_arrasto(rel: Vector2) -> void:
	if not _mouse:
		return
	_alvo_giro -= rel.x * MOUSE_SENS
	_alvo_cima = clampf(_alvo_cima + rel.y * MOUSE_SENS, CIMA_MIN, CIMA_MAX)


## troca de carro / recomeço / troca de câmera: atrás do carro na hora
func reiniciar() -> void:
	giro = 0.0
	cima = 0.0
	_alvo_giro = 0.0
	_alvo_cima = 0.0
	_segura = false
	_mouse = false


## gira a câmera que a do jogo deixou (cam) em volta de tp (origem do modelo)
func aplicar(cam: Camera3D, tp: Vector3, terrain) -> void:
	if not ativa():
		return
	var pos := cam.global_position
	var d := -cam.global_transform.basis.z
	# ponto mirado: o da linha de mira mais perto do carro
	var mira := pos + d * maxf((tp - pos).dot(d), 1.0)
	var r := Basis(Vector3.UP, giro)
	var off := r * (pos - tp)
	var alvo := tp + r * (mira - tp)
	if absf(cima) > 1e-5:
		var eixo := off.cross(Vector3.UP)
		if eixo.length() > 1e-4:
			off = off.rotated(eixo.normalized(), cima)
	var p := tp + off
	# não entra no chão: a mesma folga da câmera do jogo (0x384c80, 1.45 m),
	# entrando aos poucos com o giro (sem giro fica a do jogo)
	if terrain:
		var h: float = terrain.height_at(p.x, p.z) + GameCamera.GROUND_CLEAR
		if p.y < h:
			p.y = lerpf(p.y, h, clampf(absf(giro) / 0.3 + absf(cima) / 0.1, 0.0, 1.0))
	cam.global_position = p
	if not p.is_equal_approx(alvo):
		cam.look_at(alvo, Vector3.UP)
