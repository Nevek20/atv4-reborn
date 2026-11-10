extends RefCounted
## Tremida da câmera do jogo (componente com vtable 0x5b4fb8: update 0x380418,
## aplica 0x380170). Roda no passo de 1/60 da câmera, depois da mira.
##
## Parâmetros: só os do bloco GenericCameraData do cameras.xml, pelo tipo da
## câmera (FollowOrbitNear, MountOnHood...). Os Jitter* dos CameraSet são
## ignorados pelo jogo (conferido na RAM: os componentes vivos têm os valores
## genéricos). Construtor 0x380348 / 0x380090, loader 0x38cc48.
##
## Por velocidade (0x380418):
##   f = clamp((v - JitterSpeedStart) / (JitterSpeedMax - JitterSpeedStart)),
##   v = |velocidade| (corpo+0xe0), Start/Max em mph;
##   a = veículo+0xac0 * f², e veículo+0xac0 = média do WheelJitter do chão
##   embaixo das rodas FL, RL, FR (0x202760, car.gd jitter_chao): no asfalto
##   é 0 e a câmera não treme.
## Ruído (0x380170): duas ondas de Perlin 1D, (Amp/4, Freq) e (Amp, Freq*1.05),
##   fase inicial sorteada. Cada passo: n = tabela(fase) * amp_onda * a e
##   fase += dt * freq (mod 1). Tabela de 256 (+1) valores gerada pelo jogo
##   (RAM 0xd0e7f0, igual em todos os save states): data/ruido_camera.bin.
##   A direção da câmera vira dir + direita * n1 + cima * n2.
##
## Batida (0x380418 + 0x380170): o maior contato do passo de física
##   (corpo+0x7a0 + idx*0x40, idx em corpo+0x860; 0x215140 copia |contato+0x64|,
##   a velocidade na normal em m/s, e o 0x215248 ordena 3 do maior pro menor)
##   dá c = rampa da velocidade (CollisionSpeedFor*Jitter: abaixo do Start 0,
##   acima do Max 1) x rampa da massa do outro corpo (CollisionMassFor*Jitter,
##   t; só quando o contato tem outro corpo: parede e chão não têm) x
##   CollisionJitterMagMax. amp = max(c, amp) * CollisionJitterDecayFraction a
##   cada passo, e com amp > 1e-6 soma um sorteio uniforme em [-amp, amp) nas
##   duas componentes (gerador global x = x*31415821+1 mod 2^30, 0x8383a8).
##   Não portado: a trava do 0x380418 (veículo+0xa6c->+0x8c->+0x18, +0xa74 >=
##   0.5 e +0xa78 = 0 não deixam começar uma tremida nova; no save state da
##   batida ela está desligada).

const MPH_MS := 0.44694445         # mph -> m/s, constante do exe
const TABELA := "res://data/ruido_camera.bin"
# defaults do construtor quando o XML não traz (RAM: componentes sem dado)
const PADRAO := {"JitterSpeedStart": 0.0, "JitterSpeedMax": 1.0, "JitterPerlinAmp": 0.0,
	"JitterPerlinFreq": 0.0, "CollisionJitterMagMax": 0.0, "CollisionJitterDecayFraction": 0.95,
	"CollisionSpeedForStartJitter": 10.0, "CollisionSpeedForMaxJitter": 30.0,
	"CollisionMassForStartJitter": 0.01, "CollisionMassForMaxJitter": 0.1}

static var _tab := PackedFloat32Array()
static var semente := Time.get_ticks_msec() & 0x3FFFFFFF   # DAT_008383a8, uma pra todas as câmeras

var p := {}
var ondas := []                   # [amp, freq, fase] x 2
var n := Vector2.ZERO             # última tremida (direita, cima)
var amp_batida := 0.0             # puVar4[4] do 0x380418: amplitude da tremida da batida


static func carregar(path: String, tipo: String):
	var j = new()
	j.p = PADRAO.duplicate()
	var x := XMLParser.new()
	if x.open(path) == OK:
		var no_generico := false
		while x.read() == OK:
			var t := x.get_node_type()
			if t == XMLParser.NODE_ELEMENT:
				var nome := x.get_node_name()
				if nome == "GenericCameraData":
					no_generico = true
				elif no_generico and nome == tipo:
					for k in PADRAO:
						if x.has_attribute(k):
							j.p[k] = x.get_named_attribute_value(k).to_float()
			elif t == XMLParser.NODE_ELEMENT_END and x.get_node_name() == "GenericCameraData":
				break
	var amp: float = j.p.JitterPerlinAmp
	var freq: float = j.p.JitterPerlinFreq
	j.ondas = [[amp * 0.25, freq, randf()], [amp, freq * 1.05, randf()]]
	if _tab.is_empty():
		_tab = FileAccess.get_file_as_bytes(TABELA).to_float32_array()
	return j


## 0x3aa6e0: tabela interpolada na fase (0..1)
static func ruido(fase: float) -> float:
	var x := fase * 256.0
	var i := int(x)
	var fr := x - i
	return _tab[i] * (1.0 - fr) + _tab[i + 1] * fr


## um passo da câmera (1/60 s). vel = |velocidade| (m/s), chao = média do
## WheelJitter embaixo das rodas (car.gd jitter_chao), batida = velocidade do
## maior contato do passo de física (m/s, car.gd batida), massa = do outro
## corpo (t; < 0 = sem outro corpo, como parede e chão)
func passo(dt: float, vel: float, chao: float, batida := 0.0, massa := -1.0) -> Vector2:
	var s0: float = p.JitterSpeedStart * MPH_MS
	var s1: float = p.JitterSpeedMax * MPH_MS
	var f := clampf((vel - s0) / (s1 - s0), 0.0, 1.0) if s1 != s0 else 0.0
	var a := chao * f * f
	# batida: rampa da velocidade x rampa da massa x MagMax, amp = max(c, amp) x Decay
	var c := 1.0
	if batida <= p.CollisionSpeedForMaxJitter:
		c = 0.0
		if batida > p.CollisionSpeedForStartJitter:
			c = (batida - p.CollisionSpeedForStartJitter) / (p.CollisionSpeedForMaxJitter - p.CollisionSpeedForStartJitter)
	if massa >= 0.0:
		if massa < p.CollisionMassForStartJitter:
			c = 0.0
		elif massa < p.CollisionMassForMaxJitter:
			c *= (massa - p.CollisionMassForStartJitter) / (p.CollisionMassForMaxJitter - p.CollisionMassForStartJitter)
	c *= p.CollisionJitterMagMax
	amp_batida = maxf(c, amp_batida) * p.CollisionJitterDecayFraction
	var out := Vector2.ZERO
	for k in 2:
		var o: Array = ondas[k]
		out[k] = ruido(o[2]) * o[0] * a
		o[2] = fmod(o[2] + dt * o[1], 1.0)
		if amp_batida > 1e-6:
			out[k] += 2.0 * amp_batida * sorteio() - amp_batida
	n = out
	return out


## 0x380170: x = x*31415821 + 1 mod 2^30, U = x / 2^30 em [0, 1)
static func sorteio() -> float:
	semente = (semente * 31415821 + 1) & 0x3FFFFFFF
	return semente / 1073741824.0


## dir (normalizada) + direita * n.x + cima * n.y, com a direita e o cima da
## câmera (Godot: direita = dir x UP)
static func aplicar(dir: Vector3, t: Vector2) -> Vector3:
	if t == Vector2.ZERO:
		return dir
	var direita := dir.cross(Vector3.UP)
	if direita.length() < 1e-5:
		return dir
	direita = direita.normalized()
	var cima := direita.cross(dir)
	return (dir + direita * t.x + cima * t.y).normalized()
