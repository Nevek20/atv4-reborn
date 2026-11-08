extends RigidBody3D
## Carro com a física lida dos XMLs do próprio jogo (data/vehicles).
##
## O modelo de direção do ATV Offroad Fury 4 é "arcade de dados": em vez de
## simular pneu, ele trabalha com acelerações. O que foi reproduzido aqui:
##   - suspensão (portada): curso e velocidade próprios por roda, mola que
##     também puxa esticada, batente que empurra o carro, anti-pitch
##   - motor (portado do executável): curva de torque x rpm, atrito do motor,
##     inércia, limitador em rampa
##   - câmbio (portado): AutoManual troca por velocidade, Manual com E/Q,
##     embreagem com 4 estados (aberta, engatando, abrindo, travada)
##   - pneus: elipse de atrito por eixo (força máxima lateral e longitudinal)
##   - direção: ângulo x velocidade, subesterço, aceleração de guinada limitada
##   - derrapagem: ângulo máximo de sideslip e taxas de aumento/redução
##   - no ar (portado): gravidade maior subindo/descendo, guinada, arfagem,
##     empurrão lateral virando e torque de arfagem constante
## Unidades do jogo: massa em toneladas, torque/força em kN, velocidades em mph
## e desacelerações em mph/s. Tudo é convertido pra SI ao carregar.

const VehicleData := preload("res://vehicle_data.gd")
const CarroGlb := preload("res://carro_glb.gd")
const MPH := 0.44704
const G := 9.81
const RPM2RAD := TAU / 60.0

var model_path := ""
var data_files := ["res://data/vehicles/buggy_base.xml", "res://data/vehicles/buggy_10.xml"]
# arquivo de pontos do modelo (POINT 1.00): posição das rodas no modelo do jogo
var points_file := "res://data/vehicles/buggy_10_points.bin"
var points := {}              # pontos lidos do arquivo acima
var points_rot := {}          # matriz 3x3 de cada ponto (Basis: colunas = linhas do jogo)
# pasta do carro em assets/ com o pecas.json do tools/gerar_buggies.py:
# Position do component map -> .obj (Body, FrontLeftFrame, ...), rodas, rally
var asset_dir := ""
var pecas := {}
var livery_file := "pintura.png"   # gerada pelo gerar_pintura.py, ao lado do modelo
var suspension := true        # desenha balanças, freios e amortecedores
var susp_vis    # suspension_visual.gd
# rodas do jogo (componente Wheel, TYRE_GENERIC_* nos buggies de fábrica):
# modelo da frente e de trás (Models_4K, o que o jogo carrega na corrida). Já
# vêm com o aro (ALLOY) e o pneu (TYRE). Sem escala: o tamanho é o do modelo
var wheel_front_file := ""
var wheel_rear_file := ""
var vehicle_name := "Renegade (Buggy)"

# peças de fábrica (DefaultConfig do jogo). Cada número diz quanto o valor
# anda de _non_tuned até _fully_tuned. Vêm de data/vehicles.xml (DefaultConfig
# do veículo) + data/upgrades.xml (efeito de cada peça), ver
# VehicleData.factory_tuning. Os valores abaixo são os do Renegade (BUGGY_10),
# conferidos no save state: torque 0.81, final 0.61, massa e embreagem no máximo.
var vehicle_id := "BUGGY_10"
var som_pasta := ""            # pasta dos loops do motor, se não for a do id (o bônus)
# carros extras nossos (main.gd EXTRAS, tools/carro_glb.py): peças de fábrica
# de outro carro do jogo (o Escort usa as do Storm) e motor que não aparece
# (só a ponta do escape treme, como nos trucks; nada de ventoinha)
var tuning_id := ""
var motor_escondido := false
var _cena_glb: Node = null     # cena do .glb enquanto monta carroceria, rodas e volante
var tune_override := {}       # ex.: {"engine": 0.3} pra simular peças compradas
var TUNE_ENGINE := 0.81       # Internals L3 + Management L2 + Header L2 + Intake L3 + Exhaust L3
var TUNE_BRAKE := 0.9         # Brake_Level2
var TUNE_SUSP := 1.0          # Suspension_Level3: curso máximo
var TUNE_UNDERSTEER := 1.0    # Suspension_Level3
var TUNE_FINAL := 0.61        # GearboxLevel_Level3 = relação final custom (CustomTunings FinalDrive)
var TUNE_SHIFT := 1.0         # Clutch_Level2
var TUNE_MASS := 1.0          # BodyMass_Level2
var TUNE_SPRING := 0.5        # Shocks_Medium
var TUNE_DAMPING := 0.91      # Shocks_Medium
var TUNE_GEARS := [0.5, 0.5, 0.5, 0.5, 0.5]   # CustomTunings/GearRatioTuning
const REAR_DRIVE := true      # tração só atrás (o XML não diz; buggy de motor traseiro)

# aderência do chão (TireBehaviour do jogo, nota 0-10): terra com pneu de fábrica
# (DIRT_BUDGET) = 8. Os XMLs trazem cada valor pra atrito máximo (1.0) e mínimo
# (0.1); o jogo interpola entre os dois conforme o chão.
# atrito do chão: cada roda pega o do material embaixo dela pro pneu do carro
# (terrain.atrito, 0x20d568 -> corpo+0x750+12i); a média das rodas no chão é
# o 0x780. O Damping do material (+0x08, corpo+0x758+12i) é o arrasto do chão:
# a média (0x788) entra no 0x20e5e8. Sem terreno (teste no plano) vale o
# material de reserva: terra comum do RX_01 (COMMON_1, DIRT/COMMON).
# Hardness, Sink e Bounciness o jogo carrega mas nenhum código do buggy lê
# (docs/engenharia_reversa.md, Terreno).
var SURFACE_MU := 0.8          # pneu DIRT_BUDGET na terra comum do RX_01
var SURFACE_AMORT := 0.0       # Damping da terra comum (COMMON_1)
var pneu := "DIRT_BUDGET"      # classe do pneu (vehicles.xml DefaultConfig Tire)
var mu_medio := 0.8            # 0x780: atrito médio das rodas no chão
var amort_medio := 0.0         # 0x788: Damping médio das rodas no chão
var TUNE_FRONT_BIAS := 0.5    # DefaultConfig/CustomTunings FrontBrakeBias

# geometria medida no modelo (o XML não traz a posição das rodas)
# posição das rodas no chute, só se faltar o arquivo de pontos do modelo
const WHEEL_X := 1.0
const WHEEL_Z := 1.75
const WHEEL_Y := 0.45         # altura do cubo com o carro parado

# volante: no jogo ele é parte da carroceria e NÃO gira. Girar é melhoria do
# remake (tools/volante.py acha o aro em cada carro e o gerar_buggies.py
# separa; centro e eixo vêm do pecas.json). VOLANTE_GIRA = false deixa igual
# ao jogo.
const VOLANTE_GIRA := true
var SW_CENTER := Vector3(-0.434, 1.351, 0.396)    # Renegade, se faltar no pecas.json
var SW_AXIS := Vector3(0.0, 0.684, -0.729)
const SW_TURNS := 2.6         # sem fonte no jogo (escolha do remake); com o piloto, o giro sai da animação dele
# melhoria nossa: as mãos do piloto ficam presas no aro (piloto.gd); o volante
# gira o quanto as mãos giram no STEER_LEFT do jogo (~50°), não SW_TURNS
const MAOS_NO_VOLANTE := true
# melhoria nossa: o volante do jogo (aro de 6 a 12 lados, raios tortos) vira um
# gerado, redondo e centralizado (volantes.gd: um estilo por carro), no mesmo
# centro, raio e inclinação. false = malha do jogo.
const VOLANTE_NOSSO := true
# melhoria nossa: volante trazido pro piloto ao longo do eixo dele (como um
# espaçador de cubo), em m, pra mão alcançar: no Chimera o aro fica a 80 cm do
# banco (braço 144% esticado) e no Lazarus a 71 cm (128%); nos outros 54-62 cm.
# A câmera do piloto vem junto (o olho é medido do centro do aro). AVANCO=x
# no ambiente testa um valor. Lazarus e Chimera saíram daqui (nov/2026):
# resolvidos pelo banco (BANCO_NOSSO)
const AVANCO_VOLANTE := {}
# melhoria nossa: piloto mais alto/pra frente que o ponto ARSE do jogo (só o
# desenho dele; a física não usa). No Chimera o ARSE fica 15 cm mais pra trás
# e 13 mais baixo que nos outros (em relação ao volante): só trazer o volante
# não chegava (134%), subir mais que uns 5 cm bate o capacete no teto (75 cm
# acima do banco). Com o banco + AVANCO_VOLANTE: Chimera 105%, Lazarus 101%
# (teste_volante; com o volante inteiro do tools/volante.py o aro do Lazarus
# ficou 2.4 cm mais alto e o banco foi mais 4 cm pra frente). BANCO=x,y,z no
# ambiente testa.
# Lazarus (nov/2026, "parece um anão", Matheus): cabine de Silverado, o aro
# ficava 50 cm acima do banco (ARSE + 6 cm; nos outros 25 carros 27 a 39) e o
# teto 62 cm acima da cabeça (trucks 33 a 56). Banco +21 cm: aro a 35 cm, teto a 47, braço 89%
# sem AVANCO_VOLANTE (o volante fica no lugar do modelo) e o olho da câmera do
# piloto volta pra dentro da cabeça (19 cm acima do osso; antes 39).
# tests/medir_cabine.gd. Depois (Matheus: "Goliath, Chimera e TT baixinhos"):
# TT +10 cm (teto 56 -> 46 cm, braço 95%), Goliath +8 (aro 46 cm acima do
# banco, teto 45 -> 37, braço 73%), Chimera +15 e 20 pra frente sem o
# AVANCO_VOLANTE (aro 50 -> 35, teto 43 -> 32, braço 107 -> 92%); o olho da
# câmera do piloto fica 16 a 20 cm acima do osso da cabeça (antes 24 a 34)
const BANCO_NOSSO := {"TRUCK_12": Vector3(0.0, 0.15, 0.20), "LAZARUS": Vector3(0.0, 0.21, 0.09),
	"TRUCK_08": Vector3(0.0, 0.10, 0.0), "TRUCK_11": Vector3(0.0, 0.08, 0.0)}
# melhoria nossa: volante onde o modelo não tem (Shockwave e Punisher não têm
# interior: o tools/volante.py não acha aro nenhum). Posto onde ele fica nos
# outros trucks em relação ao banco (ARSE + 0.37 de altura e 0.46 pra frente,
# média dos 9 normais; eixo e raio típicos), com uma coluna nossa até o painel
const VOLANTE_SEM_MODELO := {
	"TRUCK_02": {"centro": [-0.475, 1.883, 0.523], "eixo": [0.0, 0.41, -0.912], "raio": 0.185},
	"TRUCK_05": {"centro": [-0.565, 1.706, 0.695], "eixo": [0.0, 0.41, -0.912], "raio": 0.185},
}
const COLUNA_RAIO := 0.025     # m (coluna nossa)
const COLUNA_MAX := 0.6        # m: até o painel, no máximo
var sw_coluna: MeshInstance3D
const Volantes := preload("res://volantes.gd")
var volante_estilo := ""      # "" = o do carro (Volantes.POR_CARRO); B no jogo troca
var sw_malha: MeshInstance3D
var sw_avanco := 0.0          # volante gerado avançado pro piloto pra coluna não atravessar o cubo
var sw_ponta_coluna := -INF   # ponta da coluna de direção da carroceria (m no eixo, + = pro piloto)
var rider_s := 0.0            # direção suavizada do piloto (rider+0x2d8 com sinal trocado: + = esquerda)
# piloto do jogo (piloto.gd, tools/piloto.py): sentado no ponto ARSE, braços pela rider_s
const PILOTO_DIR := "res://assets/piloto"
var piloto: Node3D = null
# melhoria nossa: som do motor com os loops do Engine Simulator de cada buggy
# (motor_som.gd, som/loops). O som do jogo (3 bancos pros 12) não foi portado
const SOM_MOTOR := true
var som: Node = null
# sons de pneu, suspensão e pouso do jogo (sfx_carro.gd, portados do exe com
# os samples do jogo em assets/sfx: tools/sfx_jogo.py). false = sem eles
const SOM_PNEU := true
var sfx: Node = null
# fumaça do escapamento (melhoria nossa, fumaca.gd: o efeito ExhaustSmokeTrail
# que o jogo tem no XML e não usa, nos pontos EXHAUST). false = sem fumaça
const FUMACA := true
var fumaca: Node3D = null
# poeira dos pneus (porta do jogo: Setup/Dust.xml, 0x225108; poeira.gd): nuvens
# da cor do chão (DustColour) atrás das rodas de trás, pelo DustType do material
const POEIRA := true
var poeira: Node3D = null
# pedrinhas do pneu (porta do jogo: 0x3bb618, textura Sprites/dirt_rocks;
# pedras.gd): pedras e borrifos de terra das rodas de trás patinando na terra
const PEDRAS := true
var pedras: Node3D = null
# melhoria nossa: escapes no lugar dos pontos EXHAUST do jogo (que ele não
# usa). Storm (BUGGY_12), o único buggy sem ponto: medido no modelo, boca das
# duas ponteiras cromadas (peças de 46 faces na traseira, embaixo), viradas
# 27° pra fora. Chimera (TRUCK_12): pontos do jogo, mas o EXHAUST2 (esquerda)
# tem a matriz copiada do da direita e soltava fumaça pra dentro do carro:
# espelhado. Só a fumaça e o escape tremendo usam (frame do jogo: [ponto, direção])
const ESCAPE_NOSSO := {
	"BUGGY_12": [[Vector3(0.569, 0.644, -2.489), Vector3(0.45, 0.0, -0.89)],
		[Vector3(-0.580, 0.644, -2.489), Vector3(-0.45, 0.0, -0.89)]],
	"TRUCK_12": [[Vector3(0.5535, 0.6811, -2.1867), Vector3(1.0, 0.0, 0.0)],
		[Vector3(-0.5531, 0.6811, -2.1867), Vector3(-1.0, 0.0, 0.0)]],
}
# melhoria nossa: pontos de luz no lugar dos do jogo (frame do jogo; troca
# todos os pontos que começam com o nome). Pedidos do Matheus (out/2026), lentes
# achadas com o print_tela PICK: ré nas DUAS lanternas do Shockwave e do
# Fireball (o jogo põe um ponto só, na direita; a esquerda é o espelho);
# Punisher: além das 2 luzes do teto, as lanternas grandes pintadas na
# pintura (vermelho em cima, laranja, branco da ré embaixo); Truggy: a ré do
# jogo fica no ar (perto de uma chapa escura), as de verdade são as caixinhas
# cinza do lado das de freio no teto (textura chassis_tri02); Hammerhead:
# as lanternas grandes dos lados (pedido dele)
const LUZES_NOSSAS := {
	"TRUCK_02": {"REVERSE_LIGHT": [Vector3(0.94, 1.71, -3.03), Vector3(-0.94, 1.71, -3.03)]},
	"TRUCK_05": {"BRAKE_LIGHT": [Vector3(-0.55, 2.39, -1.00), Vector3(0.55, 2.39, -1.00),
			Vector3(-0.98, 1.53, -3.19), Vector3(0.98, 1.53, -3.19)],
		"REVERSE_LIGHT": [Vector3(-0.98, 1.34, -3.19), Vector3(0.98, 1.34, -3.19)]},
	"TRUCK_07": {"REVERSE_LIGHT": [Vector3(-0.56, 2.41, -0.34), Vector3(0.52, 2.41, -0.34)]},
	"TRUCK_10": {"REVERSE_LIGHT": [Vector3(0.99, 1.07, -3.18), Vector3(-0.99, 1.07, -3.18)]},
	# Hammerhead: além das 2 do teto, as lanternas grandes dos lados (2 bolhas
	# vermelhas cada, chassis_tri02), achadas com o PICK
	"TRUCK_09": {"BRAKE_LIGHT": [Vector3(-0.56, 2.13, -0.88), Vector3(0.62, 2.13, -0.88),
			Vector3(-0.95, 1.39, -3.19), Vector3(0.95, 1.39, -3.19),
			Vector3(-0.95, 1.19, -3.23), Vector3(0.95, 1.19, -3.23)]},
}
# motor e escape tremendo (melhoria nossa, motor_treme.gd: peças soltas da
# carroceria no cofre do motor; vibração pela rotação e balanço pela carga)
const MOTOR_TREME := true
var motor_treme: Node3D = null
# motor animado (melhoria nossa, motor_anima.gd): ventoinhas dos radiadores
# girando (elétricas) e polias e correia 3D por cima das polias desenhadas
const MOTOR_ANIMA := true
var motor_anima: Node = null
# trucks (lote 4, out/2026): o motor fica embaixo do capô; ventoinhas à mostra
# no Punisher (os 2 radiadores na caçamba) e (nov/2026, Matheus) no Panther,
# Truggy, TT, Hammerhead e Lazarus (3 em cima dos estepes, textura
# preRunnerTruck_fan). Nos trucks elas têm raio de 27 a 31 cm
# (motor_anima.RAIO_MAX_TRUCK); conferido com print_tela VENTOINHA_COR=1
const ANIMA_TRUCKS := ["TRUCK_05", "TRUCK_06", "TRUCK_07", "TRUCK_08", "TRUCK_09", "LAZARUS"]
# lanterna de freio e luz de ré acesas (melhoria nossa, luzes.gd: a lente da
# cor da luz acende e ganha um halo nosso; o jogo põe só um halo laranja com
# raios nos pontos BRAKE_LIGHT/REVERSE_LIGHT, VehicleHaloMap.xml)
const LUZ_FREIO := true
var luzes: Node = null
# farol aceso (melhoria nossa, farol.gd): lente e brilho como a lanterna de
# freio, nas lâmpadas do modelo (Hurricane, Storm); H liga e desliga
const FAROL := true
var farol: Node = null
var body_mi: MeshInstance3D = null
# sujeira do jogo (0x223e68, _sujeira_passo) e desenho dela (sujeira.gd, com a
# textura GEN_DIRT_DIRT em assets/fx: tools/fx_jogo.py). false = carro limpo
const SUJEIRA := true
# painel funcional (melhoria nossa, painel.gd): ponteiros, marcha e luz de troca
const PAINEL := true
var painel: Node3D = null
var sujeira_nivel := 0.0      # objeto da sujeira (veículo+0xa80) +0xc0, 0..1
var sujeira = null
# lama das rodas (0x224418/0x2242d0, mesmo objeto +0x10..+0x4c): vira a
# paleta da UNI_TyreOverlay (0x224148). Alvo = DustColour do chão com alfa
# WheelDirtAlpha (0 no asfalto: a lama some aos poucos)
var roda_de := Color(0, 0, 0, 0)        # +0x10 cor de onde saiu
var roda_para := Color(0, 0, 0, 0)      # +0x20 alvo
var roda_cor := Color(0, 0, 0, 0)       # +0x30 cor de agora
var roda_mat := -1                      # +0x40 material do chão da FL
var roda_t := 0.0                       # +0x44 quanto já foi (0..1)
var roda_taxa := 0.0                    # +0x48 WheelDirtRate suavizada
var roda_taxa_alvo := 0.0               # +0x4c
var som_carga := 0.0          # carga do motor pro som: acelerador x limitador x troca
var DRIVER_EYE := Vector3(-0.434, 1.78, -0.12)   # Renegade; nos outros vem do ponto ARSE
const EYE_FROM_ARSE := Vector3(0.047, 0.78, -0.169)   # medido no Renegade (ARSE -> olho)
const MAX_STEER := 1.0        # steer já é normalizado (-1..1)
# o pingu2obj acerta o giro dos triângulos pelas normais do jogo, então a face
# de trás pode ser descartada (painéis de duas faces não piscam mais).
# Modelos gerados com o pingu2obj antigo precisam de CULL_DISABLED.
const MODEL_CULL := BaseMaterial3D.CULL_BACK
# cor do vértice do jogo: o PS2 multiplica a textura por ela (sombra "assada"
# no modelo e a cor das lanternas: vidro claro na textura x vértice vermelho).
# 0x80 = 1.0, vai até 2.0. pecas.json "cor_vertice" 2 = pingu2obj novo, que
# guarda codificada (docs/assets.md); sem ela = antigo, cortada em 1.0.
# false = só a textura (como era até out/2026: lanterna branca)
const COR_VERTICE := true
const COR_K_SRGB := 255.0 / 128.0   # no albedo (sRGB) vira o COR_K do pingu2obj
# carroceria fechada (melhoria nossa: só a nossa câmera do piloto fica dentro
# dela). A casca do jogo só tem a face de fora e de dentro do Storm via-se a
# estrada pelas chapas. _face_de_dentro dá a face de dentro às chapas que não
# têm (as de 2 faces já modeladas ficam, senão piscam): na pintura ("white")
# vira FORRO (de dentro não se vê a pintura de fora espelhada), no resto a
# mesma textura.
# Trucks (lote 2): olhando pro lado da câmera do piloto, Shockwave, Jericho,
# Fireball, Goliath, Chimera e Lazarus mostravam o chão onde devia estar a
# porta; vale pros 13 (nos abertos só aparece a chapa por dentro, que é o certo)
const CABINE_FECHADA := ["BUGGY_12", "TRUCK_01", "TRUCK_02", "TRUCK_03", "TRUCK_04", "TRUCK_05",
	"TRUCK_06", "TRUCK_07", "TRUCK_08", "TRUCK_09", "TRUCK_10", "TRUCK_11", "TRUCK_12", "LAZARUS"]
const FORRO := Color(0.16, 0.16, 0.17)
# vidro das janelas (só o Lazarus): alfa da Dakar_window_8 do jogo (0x1B/0x80)
const VIDRO_ALFA := 27.0 / 128.0
# estepes NOSSOS (Matheus, nov/2026): o modelo do Lazarus tem SpareWheel01Centre
# e SpareWheel02Centre lado a lado na caçamba, mas o mapa do Jericho
# (TruckCompMap_B1) só põe roda no 01 e sobrava o buraco do 2º
const ESTEPES_NOSSOS := {"LAZARUS": ["SpareWheel01", "SpareWheel02"]}

# O jogo é mão esquerda (x direita, y cima, z frente; esquerda do jogo = x < 0
# no modelo) e o Godot é mão direita. Tudo que vem do jogo em frame do modelo
# (malhas, pontos, peças, volante, olho) fica em frame do JOGO embaixo do nó
# espelho (escala (-1, 1, 1) na origem do corpo). A física roda no frame do
# Godot (+X = esquerda): ponto do jogo entra nela por corpo(). Nunca converter
# a mesma coisa nos dois lugares.
const ESPELHO := Vector3(-1.0, 1.0, 1.0)
var espelho: Node3D             # filhos em frame do jogo (model_root, susp_vis, rodas)
var model_root: Node3D
var model_offset := Vector3.ZERO  # origem do modelo no frame do JOGO (dentro do espelho)
var sw_pivot: Node3D

# ---- parâmetros carregados do XML ----
var P := {}
var wheels: Array = []
var drive_curve: Dictionary
var fric_curve: Dictionary
var steer_curve: Dictionary
var ss_inc_curve: Dictionary
var ss_dec_zero: Dictionary
var ss_dec_full: Dictionary
var ss_inc_min: Dictionary
var ss_dec_zero_min: Dictionary
var ss_dec_full_min: Dictionary
var rate_inc_max: Dictionary
var rate_inc_min: Dictionary
var rate_dec_max: Dictionary
var rate_dec_min: Dictionary
var ps_rate: Dictionary
var ps_scale: Dictionary
var rtc_th: Dictionary        # RecoveryTorqueCutting (0x2120c0): ângulo onde começa,
var rtc_max: Dictionary       # onde corta tudo e quanto corta, pela velocidade
var rtc_cut: Dictionary
var mu_t := 1.0               # 0 = atrito mínimo do XML, 1 = máximo
var gears := PackedFloat32Array()

# ---- estado ----
var steer := 0.0              # direção (-1..1), + = esquerda
var throttle := 0.0
var brake_in := 0.0
var gear := 1                 # -1 = ré, 0 = neutro
var rpm := 1000.0
var clutch := 1.0
var shift_timer := 0.0
var shift_to := 1
var manual := false
var limiter := false
var cstate := 0               # embreagem (0x314): 0 aberta, 1 engatando, 2 abrindo, 3 travada
var shift_flag := false       # troca em andamento: acelerador cai junto com a embreagem
var slip_sign := 0.0          # sinal da diferença de giro quando começou a engatar
var lim_k := 1.0              # fator do limitador de giro (rampa)
var eng_torque := 0.0         # torque líquido do motor (N·m)
var clutch_t := 0.0           # torque passando pela embreagem (N·m)
var want_rev := false         # pedido de ré (o câmbio abre, engata a ré e fecha)
var reverse_hold := 0.0
# pedais crus depois do 0x202df0 (corpo+0x37c / +0x38c); o throttle e o
# brake_in são os suavizados (+0x380 / +0x390). O câmbio e o "preso" leem o cru.
var steer_cx := 0.0            # direção crua (corpo+0x36c)
var thr_cx := 0.0
var brk_cx := 0.0
var rev_timer := 0.0          # veículo+0xb2c: espera do freio virar ré quando vinha andando
var ar_libera := false        # veículo+0xb30: soltou o acelerador nesse voo
# botão da embreagem (corpo+0x384 cru / +0x388 suavizado, InputRates/Clutch).
# O jogo não tem freio de mão: segurar abre a embreagem (0x20c558) e dar um
# toque virando e acelerando faz a "Clutch Turn" (powerslide, 0x214610)
var emb_in := 0.0
# powerslide (0x214610): estado corpo+0x74c (0 nada, 1 crescendo, 2 ativo,
# 3 sumindo), quantidade 0x744, escala pela velocidade 0x748 e a embreagem do
# passo anterior 0x740
var ps_estado := 0
var ps_qtd := 0.0
var ps_esc := 0.0
var ps_emb_ant := 0.0
# corpo+0x540: o corte de recuperação (0x2120c0) subiu a patinada neste passo;
# aí a roda dentro da elipse não devolve a patinada (0x2101e0)
var rtc_patinou := false
var air_time := 0.0
var air_lat_state := 0        # empurrão lateral no ar (0x6f4): 0 nada, 1 direita, 2 esquerda
var air_lat_timer := 0.0
var air_lat_scale := 1.0
var sideslip := 0.0           # rad, + = bico à direita da trajetória (0x6c0 do jogo com sinal trocado)
var grounded := 0

# tremida das rodas no chão (0x202760, só visual). A cada passo de física do
# jogo (50 Hz no PAL) cada roda no chão sorteia um deslocamento do curso:
# amp = min(1, WheelJitter * 0.06392613 * v) e tremida = amp * (U*0.075 - 0.0375),
# com v a velocidade no plano do chão (m/s) e U do gerador do piloto
# (x = x*31415821 + 1 mod 2^30). A traseira direita do jogo copia a esquerda.
# WheelJitter vem do Materials.xml da pista, pelo material do chão embaixo de
# cada roda (W+0x140, terrain.gd): 0.3 na terra/cascalho do RX_01, 0 no asfalto.
# No ar a roda fica com o último material (o jogo não mexe no W+0x140).
const JIT_K := 0.06392613     # 2.2374146 / 35: amplitude cheia a 35 mph com WheelJitter 1
const JIT_HZ := 50.0          # passo de física do PAL (FUN_00172778)
var surface_jitter := 0.3     # sem terreno (teste no plano): terra (Material_1 DIRT/COMMON)
var terrain = null            # terrain.gd (main.gd põe): material do chão por roda
var objetos = null            # objetos_rx01.gd (main.gd põe): caixas de água
## água (0x201c20, por quadro): veículo+0xae8 = a água da última roda testada
## (null = fora) e veículo+0xaec+4i = profundidade de cada roda (superfície -
## fundo da roda; > 0 = dentro). Usada no arrasto, na lama, no espirro e no som
var agua = null
var agua_prof := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
## registro da água (DAT_007f4bf8+0x20, igual no RX01 e no Hinter Valley):
## DustColour 0, DustType Water, WheelDirtAlpha 0, WheelDirtRate 30
const AGUA_REG := {"DustColour": Color(0, 0, 0, 0), "DustType": "Water",
	"WheelDirtAlpha": 0.0, "WheelDirtRate": 30.0}
var jit_seed := 0
var jit_acc := 0.0
var spd_ground := 0.0         # corpo+0x440: velocidade no plano do chão (m/s)
var jit_order := []           # índices das rodas na ordem do jogo: FL, RL, FR, RR
var jitter_chao := 0.0        # veículo+0xac0: média do WheelJitter embaixo de FL, RL, FR no chão (câmera)
# batida (0x215140): a cada passo o jogo guarda os contatos do casco por
# |contato+0x64| = velocidade do ponto na normal (m/s) e a câmera lê o maior
# (camera_jitter.gd). Aqui o solver do Godot já tirou essa velocidade quando o
# contato aparece, então vale a velocidade do ponto ANTES do passo que achou o
# contato. No save state da batida (crash_Storm): parede de pedra, outro corpo
# nenhum, 4.86 m/s num registro velho e 0.08 m/s encostado.
var batida := 0.0             # corpo+0x7a0: maior velocidade de contato do último passo (m/s)
var _v_antes := Vector3.ZERO
var _w_antes := Vector3.ZERO

# melhoria nossa: o volante treme (as mãos vão junto pela IK). No jogo ele não
# treme; a força vem do que o jogo usa pra sacudir o CONTROLE e pro som:
#   vibracao (0x202ab8, motor pequeno do controle, só com roda no chão):
#     0.07 x U(0.1, 0.9) x (1.5 |v lateral| + 15 se patinando abaixo de 20 mph
#     + 0.3356 |v| se alguma roda travada), + 0.07 x 0.25 |v| em 10% dos passos
#   pancada: pouso depois de mais de 0.1 s no ar (0x370df0: 0.5 + 0.5 min(1, t))
#     e suspensão afundando rápido acima de 20 mph (0x36e498/0x36e2d8, limites
#     Small/Large do "Buggy" no SoundDatabase.xml)
#   terra: a tremida do curso das rodas da frente (0x202760), uma contra a outra
# Os graus são escolha nossa. VOLANTE_TREME = false deixa parado.
const VOLANTE_TREME := true
const TREME_GRAUS := 2.5          # giro com vibracao 1
const TREME_PANCADA_GRAUS := 6.0  # tranco com pancada 1
const TREME_TERRA := 60.0         # graus por metro de diferença no curso das rodas da frente
const TREME_SUAVE := 0.015        # s: o volante segue o sorteio com essa constante
const PANCADA_SOLTA := 0.15       # s: o tranco some com essa constante
const SUSP_ESCALA := 3.4375       # SuspensionScale (SoundDatabase.xml, Model, igual nos 12 buggies)
const SUSP_PEQUENA := 0.4945      # Suspension "Buggy": Small Threshold
const SUSP_GRANDE := 0.6563       # Large Threshold
const SUSP_VEL := 8.938889        # 20 mph: abaixo disso o 0x36e498 não toca a suspensão
var vibracao := 0.0
var pancada := 0.0
var treme := 0.0                  # rad somados ao giro do volante
var _treme_alvo := 0.0
var susp_taxa := 0.0              # dono do som +0x178: d(suspensão)/dt filtrado de FL e RL
var _susp_ant := [0.0, 0.0]       # roda do som +0x164 de FL e RL
var _susp_acima := [false, false]
var ar_som := 0.0                 # tempo no ar contado pelo som (0x370df0)
var pouso := 0.0                  # > 0 no passo em que pousou: volume do pouso (0x370df0)

var lateral_game := true     # L alterna: força lateral por eixo (jogo) x remendo antigo
var use_ported := true      # P alterna: física portada do jogo x modelo antigo
var stf_blend := 0.0          # 0x474: quanto da força pra frente veio da derrapagem
var drive_slip := 0.0         # maior patinada (0x610) das rodas de tração (HUD e testes)
# giro das rodas por torque (0x2113e0 + 0x2484c8). Cada roda tem giro w.omega
# (W+0x48, rad/s), ângulo w.spin (W+0x4c) e inércia w.inercia (W+0x3c = Mass x
# raio² / 2). No chão o giro segue a velocidade prevista do carro x (1 + 0x610);
# a patinada medida w.sr (0x600 = giro x raio / v - 1, 0x20df58) é a que o ABS,
# a trava e a embreagem forçada leem. O giro do motor vem do w.omega.
const GIRO_LIVRE := PI        # DAT_005506c4 = 180°/s²: o que a roda solta perde no ar
var v_ref := 0.0              # 0x211e48: velocidade pra frente prevista no fim do passo
var preso := false            # 0x890: acelerando parado sem sair do lugar
var preso_t := 0.0            # 0x894
var preso_pos := Vector3.ZERO # 0x870
var pos_ant := Vector3.ZERO   # 0x880: posição antes do último passo
# roda travando (0x210908, globais 0x5506a4..b4): acima de 2 mph, roda sem ABS
# segurando com patinada abaixo de -0.25 tem a força virada contra o deslize
# do contato (rampa linear até -1, aí fica toda contra). Nos buggies o ABS
# (Enable_ABS) solta o freio em -0.2, então o pedal não chega a travar.
const TRAVA_MPH := 2.0
const TRAVA_INI := -0.25
const TRAVA_FIM := -1.0
var test_input = null         # {thr, brk, steer} pra testes automáticos
# false desliga as melhorias nossas (volante girando e gerado, mãos na IK,
# som do Engine Simulator, fumaça, painel, motor tremendo e animado, luzes,
# farol, volante tremendo): fica só o que o jogo faz
var melhorias := true
# melhorias desligadas só neste carro (nomes de _tem). Nos trucks main.gd e
# print_tela põem PENDENTES_TRUCK: cada uma sai daqui quando for ligada e
# conferida neles (lote 1, out/2026: luzes, farol e fumaça; o som do motor
# veio antes, com os 13 motores dos trucks; lote 2: volante e mãos)
var desligadas := []
const PENDENTES_TRUCK := []


## TEMPO_CARGA=1: quanto cada etapa da carga do carro leva (ms)
var _t_carga := 0
func _marca(etapa: String) -> void:
	if OS.get_environment("TEMPO_CARGA") != "1":
		return
	var t := Time.get_ticks_msec()
	print("  carga %-18s %6d ms" % [etapa, t - _t_carga])
	_t_carga = t


## melhoria nossa ligada neste carro
func _tem(nome: String) -> bool:
	return melhorias and not (nome in desligadas)


func _ready() -> void:
	_t_carga = Time.get_ticks_msec()
	espelho = Node3D.new()
	espelho.name = "Espelho"
	espelho.scale = ESPELHO
	add_child(espelho)
	model_root = Node3D.new()
	espelho.add_child(model_root)
	_load_pecas()
	_load_model()                 # antes da física: define model_offset
	_marca("modelo")
	_load_physics()
	_load_piloto()                # depois da física: precisa do ponto ARSE
	_marca("física+piloto")
	_load_painel()
	_marca("painel")
	_load_motor_treme()
	_marca("motor_treme")
	_load_motor_anima()
	_marca("motor_anima")
	_load_luzes()
	_marca("luzes")
	_load_farol()
	_marca("farol")
	_load_som()
	_load_sfx()
	_load_fumaca()
	_load_poeira()
	_load_pedras()
	_casco()
	_marca("som+fumaça+casco")
	contact_monitor = true            # batida: contatos do casco (_batida_passo)
	max_contacts_reported = 8
	for w in wheels:
		_make_wheel_mesh(w)
	if _cena_glb:
		_cena_glb.free()               # rodas e volante já saíram dela
		_cena_glb = null
	_esferas_das_rodas()
	_marca("rodas")
	if suspension and not pecas.is_empty() and not points.is_empty():
		susp_vis = preload("res://suspension_visual.gd").new()
		espelho.add_child(susp_vis)
		var spare_mesh: Mesh = null
		if ResourceLoader.exists(wheel_rear_file):
			spare_mesh = load(wheel_rear_file) as Mesh
		susp_vis.build(self, points, points_rot, asset_dir, pecas.get("pecas", {}),
			pecas.get("rally", false), ESTEPES_NOSSOS.get(chave(), pecas.get("estepe", [])), spare_mesh)
	_load_sujeira()               # por último: precisa das rodas e das peças
	_marca("suspensão+sujeira")


## casco de colisão contra o mundo = as ESFERAS do VehicleWorld.hsc do jogo
## pelo id do veículo (tools/casco.py -> data/vehicles/<id>_casco.json). Os
## planos do arquivo não entram: nos save states do Fireball de lado e
## capotado (out/2026) o contato do corpo cai exatamente na superfície de uma
## esfera, num caso 3.4 cm FORA dos planos. Até out/2026 era uma caixa de 2.1
## x 0.8 x 4.8 m igual pra todos (o teto dos trucks ficava 1 m acima dela).
## Sem o .json volta a caixa
func _casco() -> void:
	var path := "res://data/vehicles/%s_casco.json" % vehicle_id.to_lower()
	var info = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if info is Dictionary and info.has("esferas"):
		var i := 0
		for e in info.esferas:
			var cs := CollisionShape3D.new()
			cs.name = "Casco%d" % i
			var sph := SphereShape3D.new()
			sph.radius = e[3]
			cs.shape = sph
			cs.position = corpo(Vector3(e[0], e[1], e[2]))
			add_child(cs)
			i += 1
		return
	push_warning("sem %s: casco de colisão genérico (rode tools/casco.py)" % path)
	var shape := CollisionShape3D.new()
	shape.name = "Casco"
	var box := BoxShape3D.new()
	box.size = Vector3(2.1, 0.8, 4.8)
	shape.shape = box
	shape.position = Vector3(0, 0.95, 0)
	add_child(shape)


## roda como esfera (0x248768, Cosine_maximum_collision_angle): contato com o
## chão até ~50° do eixo da suspensão é da mola; fora disso (carro de lado,
## capotado, roda batendo de lado) a roda vira uma esfera do raio dela e bate
## como o corpo. Fireball de lado (save state do Matheus, out/2026): um dos 2
## contatos do corpo fica a 0.567 m do centro da roda dianteira = o raio dela.
## Até out/2026 a roda de lado entrava no chão
func _esferas_das_rodas() -> void:
	for w in wheels:
		var cs := CollisionShape3D.new()
		cs.name = "Roda" + ("F" if w.front else "T") + ("E" if w.left else "D")
		var sph := SphereShape3D.new()
		sph.radius = w.r
		cs.shape = sph
		cs.disabled = true
		cs.position = Vector3(w.px, w.y0, w.pz)
		add_child(cs)
		w.esfera = cs
		var q := SphereShape3D.new()
		q.radius = w.r + 0.03                # acha o chão um pouco antes de encostar
		w.esfera_teste = q


## liga a esfera de cada roda quando o chão perto dela está fora do cone da
## suspensão (chamado a cada passo, depois do contato das molas)
func _passo_esferas_rodas(space: PhysicsDirectSpaceState3D, up: Vector3) -> void:
	for w in wheels:
		var cs: CollisionShape3D = w.get("esfera")
		if cs == null:
			continue
		var c := Vector3(w.px, w.y0 + clampf(w.x, w.min, w.max), w.pz)
		cs.position = c
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = w.esfera_teste
		q.transform = Transform3D(Basis(), global_transform * c)
		q.exclude = [get_rid()]
		var info := space.get_rest_info(q)
		# roda de lado na cerca: o jogo mede pelo 0x153390 (0x154088, rodas)
		# antes do contato; quebrou, a esfera não liga (senão vira parede)
		if objetos and not info.is_empty() and (info.normal as Vector3).dot(up) < w.cos_max \
				and objetos.roda_na_cerca(instance_from_id(info.collider_id), info.point, info.normal):
			q.exclude = q.exclude + [info.rid]
			info = space.get_rest_info(q)
		cs.set_deferred("disabled", info.is_empty() or (info.normal as Vector3).dot(up) >= w.cos_max)


## material de uma malha do jogo (carroceria, rodas, peças, volante do
## jogo): descarta a face de trás e multiplica pela cor do vértice
func material_do_jogo(m: StandardMaterial3D) -> void:
	m.cull_mode = MODEL_CULL
	if not _com_cor_vertice():
		return
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	if int(pecas.get("cor_vertice", 1)) >= 2:
		var c := m.albedo_color
		m.albedo_color = Color(c.r * COR_K_SRGB, c.g * COR_K_SRGB, c.b * COR_K_SRGB, c.a)


## a mesma conta pros shaders nossos que desenham por cima de malha do jogo
## (sujeira, ventoinha): multiplicador linear da cor do vértice, 0 = sem
func cor_k() -> float:
	if not _com_cor_vertice():
		return 0.0
	if int(pecas.get("cor_vertice", 1)) >= 2:
		return pow((COR_K_SRGB + 0.055) / 1.055, 2.4)
	return 1.0


static func _com_cor_vertice() -> bool:
	return COR_VERTICE and OS.get_environment("COR_VERTICE") != "0"    # print_tela: antes x depois


## pecas.json (tools/gerar_buggies.py): modelo, peças e rodas do carro
func _load_pecas() -> void:
	var p := asset_dir.path_join("pecas.json")
	if asset_dir == "" or not FileAccess.file_exists(p):
		return
	pecas = JSON.parse_string(FileAccess.get_file_as_string(p))
	if pecas == null:
		pecas = {}
		return
	if not pecas.has("volante") and VOLANTE_SEM_MODELO.has(chave()):
		pecas["volante"] = VOLANTE_SEM_MODELO[chave()]
	var pc: Dictionary = pecas.get("pecas", {})
	if model_path == "" and pc.has("Body"):
		model_path = asset_dir.path_join(pc.Body)
	var rd: Dictionary = pecas.get("rodas", {})
	if wheel_front_file == "" and rd.has("FrontWheel"):
		wheel_front_file = asset_dir.path_join(rd.FrontWheel).simplify_path()
	if wheel_rear_file == "" and rd.has("RearWheel"):
		wheel_rear_file = asset_dir.path_join(rd.RearWheel).simplify_path()


# ------------------------------------------------------------------ dados
func _load_tuning() -> void:
	if not FileAccess.file_exists("res://data/vehicles.xml"):
		return
	var t := VehicleData.factory_tuning("res://data/vehicles.xml", "res://data/upgrades.xml",
		tuning_id if tuning_id != "" else vehicle_id)
	TUNE_ENGINE = t.engine
	pneu = String(t.config.get("Tire", pneu))
	TUNE_BRAKE = t.brake
	TUNE_SUSP = t.susp
	TUNE_UNDERSTEER = t.understeer
	TUNE_FINAL = t.final
	TUNE_SHIFT = t.shift
	TUNE_MASS = t.mass
	TUNE_SPRING = t.spring
	TUNE_DAMPING = t.damping
	TUNE_GEARS = t.gears
	TUNE_FRONT_BIAS = t.front_bias
	for k in tune_override:
		if String(k) == "tire":
			pneu = String(tune_override[k])     # classe do pneu (override de atrito do chão)
		else:
			set("TUNE_" + String(k).to_upper(), tune_override[k])


func _load_physics() -> void:
	_load_tuning()
	var d = VehicleData.new()
	d.load_files(data_files)

	mass = d.tuned("RigidBody", "Mass", TUNE_MASS) * 1000.0
	var bw := d.f("RigidBody", "Inertia_dimensions_width", 2.0)
	var bh := d.f("RigidBody", "Inertia_dimensions_height", 1.5)
	var bl := d.f("RigidBody", "Inertia_dimensions_length", 4.0)
	inertia = Vector3(bh * bh + bl * bl, bw * bw + bl * bl, bw * bw + bh * bh) * mass / 12.0
	P.ang_res = Vector3(d.f("RigidBody/Angular_resistance_3d", "X", 1.0),
		d.f("RigidBody/Angular_resistance_3d", "Y", 0.1),
		d.f("RigidBody/Angular_resistance_3d", "Z", 2.5))
	var pm := PhysicsMaterial.new()
	pm.friction = d.f("RigidBody", "Friction", 0.2)
	pm.bounce = d.f("RigidBody", "Restitution", 0.2)
	physics_material_override = pm
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.0
	continuous_cd = true

	var com := Vector3(d.f("Stability/General/Centre_of_mass", "X"),
		d.f("Stability/General/Centre_of_mass", "Y", 0.6),
		d.f("Stability/General/Centre_of_mass", "Z"))
	# o centro de massa do XML está nas coordenadas do modelo (no jogo, a origem
	# do modelo fica em corpo - CoM, 0x20ca88); aqui o modelo foi deslocado
	# por model_offset, então o CoM anda junto (e passa pro frame do Godot)
	com = corpo(com)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = com

	# motor
	P.idle = d.f("Engine", "Idle_rpm", 1000.0)
	P.lim_on = d.tuned("Engine", "Rev_limiter_engage_rpm", TUNE_ENGINE)
	P.lim_off = d.tuned("Engine", "Rev_limiter_disengage_rpm", TUNE_ENGINE)
	P.lim_rate_on = d.f("Engine", "Rev_limiter_engage_rate", 15.0)
	P.lim_rate_off = d.f("Engine", "Rev_limiter_disengage_rate", 15.0)
	P.eng_inertia = d.tuned("Engine", "Inertia", TUNE_ENGINE) * 1000.0   # N·m por (rpm/s)
	P.drive_scale = d.tuned("Engine", "Drive_torque", TUNE_ENGINE) * 1000.0
	P.fric_scale = d.tuned("Engine", "Friction_torque", TUNE_ENGINE) * 1000.0
	drive_curve = d.curve("Engine/Drive_torque_vs_rpm")
	fric_curve = d.curve("Engine/Friction_torque_vs_rpm")

	# câmbio
	var n := int(d.f("Gearbox", "Number_of_forward_gears", 5))
	gears.resize(n + 1)
	for g in range(1, n + 1):
		gears[g] = d.tuned("Gearbox/Ratios", "Gear_%d" % g, TUNE_GEARS[g - 1])
	P.gear_r = d.f("Gearbox/Ratios", "Gear_R", -15.0)
	P.final = d.tuned("Gearbox/Ratios", "Final_drive", TUNE_FINAL)
	P.up_rpm = d.f("Gearbox/AutoManual", "Change_up_rpm", 7000.0)
	var dd := PackedFloat32Array()
	dd.resize(n + 1)
	for g in range(2, n + 1):
		dd[g] = d.f("Gearbox/AutoManual", "Change_down_speed_difference_gear_%d" % g, 10.0)
	P.down_diff = dd
	P.clutch_dis_rate = d.f("Gearbox/AutoManual", "Clutch_disengagement_rate", 10.0)
	P.clutch_eng_rate = d.f("Gearbox/AutoManual", "Clutch_engagement_rate", 2.0)
	P.clutch_thr_mod = d.f("Gearbox/AutoManual", "Clutch_rate_throttle_modifier", 1.0)
	P.clutch_dis_rpm = d.f("Gearbox/AutoManual", "Clutch_disengagement_rpm", 1050.0)
	# ClutchTorque vem das peças de motor (mesma soma do torque), não do Clutch_Level:
	# no save state do Renegade a embreagem vale 0.6127 = lerp(0.445, 0.652, 0.81)
	P.clutch_max = d.tuned("Gearbox/AutoManual", "Maximum_clutch_torque", TUNE_ENGINE) * 1000.0
	P.clutch_rpm_lo = d.f("Gearbox/AutoManual", "Clutch_engagement_rpm_no_throttle", 1000.0)
	P.clutch_rpm_hi = d.f("Gearbox/AutoManual", "Clutch_engagement_rpm_full_throttle", 1000.0)
	P.clutch_lock_diff = d.f("Gearbox/AutoManual", "Clutch_lock_rpm_difference", 100.0)
	P.up_thr_mod = d.f("Gearbox/AutoManual", "Change_rpm_throttle_modifier", 1.0)
	P.auto_time = d.tuned("Gearbox/AutoManual", "Change_time", TUNE_SHIFT)
	P.manual_time = d.tuned("Gearbox/Manual", "Change_time", TUNE_SHIFT)

	# comandos (taxas de subida/descida do acelerador, freio e direção)
	P.thr_up = d.f("InputRates/Throttle", "Digital_increase_rate", 2.0)
	P.thr_down = d.f("InputRates/Throttle", "Digital_decrease_rate", 2.0)
	P.brk_up = d.f("InputRates/Footbrake", "Digital_increase_rate", 2.0)
	P.brk_down = d.f("InputRates/Footbrake", "Digital_decrease_rate", 2.0)
	P.st_up = d.f("InputRates/Steer", "Digital_increase_rate", 6.0)
	P.st_down = d.f("InputRates/Steer", "Digital_decrease_rate", 4.0)
	P.st_opp = d.f("InputRates/Steer", "Digital_opposite_rate", 6.0)
	P.st_damp = d.f("InputRates/Steer", "Digital_damp_increase_rate", 0.0)   # "true" = 1

	# arrasto e freio
	P.air_drag = d.f("Misc", "Air_drag_coefficient", 1.0)
	P.ground_drag = d.f("Misc", "Ground_drag_coefficient", 2.0)
	P.water_drag = d.f("Misc", "Water_drag_coefficient", 0.1)
	P.water_depth = d.f("Misc", "Water_drag_max_wheel_depth", 0.5)
	P.ifd_lo_speed = d.f("Misc", "Internal_friction_drag_lower_speed", 5.0)
	P.ifd_hi_speed = d.f("Misc", "Internal_friction_drag_upper_speed", 80.0)
	P.ifd_lo = d.f("Misc", "Internal_friction_drag_lower_speed_decel", 3.0)
	P.ifd_hi = d.f("Misc", "Internal_friction_drag_upper_speed_decel", 5.0)
	P.brake_decel = d.tuned("Footbrake", "Maximum_deceleration", TUNE_BRAKE)
	P.rev_cut = d.f("ReverseSpeedLimit", "Drive_cut_speed_threshold", 25.0)
	P.rev_limit = d.f("ReverseSpeedLimit", "Speed_limit", 30.0)

	# elipse de atrito por eixo (kN -> N)
	var ws := d.tuned("FrictionEllipse", "Width_scale", 0.0)
	var hs := d.tuned("FrictionEllipse", "Height_scale", 0.0)
	P.ell_w_f = d.f("FrictionEllipse/FrontWheels/HalfWidth", "Maximum_friction_half_width", 10.0) * ws * 1000.0
	P.ell_w_r = d.f("FrictionEllipse/RearWheels/HalfWidth", "Maximum_friction_half_width", 10.0) * ws * 1000.0
	P.ell_h_f = d.f("FrictionEllipse/FrontWheels/HalfHeight", "Maximum_friction_half_height", 5.0) * hs * 1000.0
	P.ell_h_r = d.f("FrictionEllipse/RearWheels/HalfHeight", "Maximum_friction_half_height", 5.0) * hs * 1000.0

	# direção
	steer_curve = d.curve("BasicSteering/Angle_vs_speed")
	P.vis_steer = deg_to_rad(d.f("BasicSteering", "Maximum_visual_steer_angle_zero_speed", 30.0))
	P.understeer = deg_to_rad(d.tuned("BasicSteering", "Understeer_coefficient", TUNE_UNDERSTEER)) / G
	P.yaw_acc = deg_to_rad(d.f("BasicSteering/MaximumYawAcceleration", "Standard_value", 2000.0))

	# derrapagem
	P.ss_zero = d.f("Sideslip", "Speed_for_zero_sideslip", 5.0)
	P.ss_full = d.f("Sideslip", "Speed_for_maximum_sideslip", 100.0)
	P.ss_max = d.f("Sideslip", "Maximum_sideslip_angle", 10.0)
	P.side_to_fwd = d.f("Sideslip", "Side_deceleration_to_fwd_acceleration", 0.75)
	P.side_to_fwd_min = d.f("Sideslip", "Side_deceleration_to_fwd_acceleration_min_sideslip", 5.0)
	P.side_to_fwd_max = d.f("Sideslip", "Side_deceleration_to_fwd_acceleration_max_sideslip", 30.0)
	var fmax := d.f("Sideslip/SideVelocityDecelerationStandard", "Maximum_friction", 1.0)
	var fmin := d.f("Sideslip/SideVelocityDecelerationStandard", "Minimum_friction", 0.1)
	mu_t = clampf((SURFACE_MU - fmin) / maxf(fmax - fmin, 0.01), 0.0, 1.0)
	P.side_decel = lerpf(d.f("Sideslip/SideVelocityDecelerationStandard", "Minimum_friction_deceleration", 10.0),
		d.f("Sideslip/SideVelocityDecelerationStandard", "Maximum_friction_deceleration", 30.0), mu_t)
	P.tail_off = d.f("Sideslip", "Increase_tail_off_threshold", 10.0)
	P.legacy_side_decel = P.side_decel
	var sp := "Sideslip/SideslipIncreaseYawAcceleration/"
	ss_inc_curve = d.curve(sp + "Maximum_friction_acceleration_vs_speed")
	ss_inc_min = d.curve(sp + "Minimum_friction_acceleration_vs_speed")
	sp = "Sideslip/SideslipDecreaseYawAccelerationStandard/"
	ss_dec_zero = d.curve(sp + "ZeroThrottle/Maximum_friction_acceleration_vs_speed")
	ss_dec_zero_min = d.curve(sp + "ZeroThrottle/Minimum_friction_acceleration_vs_speed")
	ss_dec_full = d.curve(sp + "FullThrottle/Maximum_friction_acceleration_vs_speed")
	ss_dec_full_min = d.curve(sp + "FullThrottle/Minimum_friction_acceleration_vs_speed")
	sp = "Sideslip/MaximumRate/"
	rate_inc_max = d.curve(sp + "Maximum_increase_rate_vs_sideslip/Maximum_friction_rate_vs_sideslip")
	rate_inc_min = d.curve(sp + "Maximum_increase_rate_vs_sideslip/Minimum_friction_rate_vs_sideslip")
	rate_dec_max = d.curve(sp + "Maximum_decrease_rate_vs_sideslip/Maximum_friction_rate_vs_sideslip")
	rate_dec_min = d.curve(sp + "Maximum_decrease_rate_vs_sideslip/Minimum_friction_rate_vs_sideslip")
	ps_rate = d.curve("Powerslide/Maximum_sideslip_rate_vs_sideslip")
	ps_scale = d.curve("Powerslide/Scale_vs_speed")
	P.ps_ellipse = d.f("Powerslide", "Scale_of_min_friction_ellipse_scale", 0.8)
	var rt := "Sideslip/RecoveryTorqueCutting"
	# o 0x2120c0 só roda com a elipse ligada (FrictionEllipse Enabled, 0x430)
	P.rtc_on = d.f(rt, "Enabled", 0.0) != 0.0 and d.f("FrictionEllipse", "Enabled", 1.0) != 0.0
	P.rtc_front = d.f(rt, "Maximum_increased_front_slip_ratio", 0.0)
	P.rtc_rear = d.f(rt, "Maximum_increased_rear_slip_ratio", 0.0)
	P.rtc_steer = d.f(rt, "Steering_dependent", 0.0) != 0.0
	rtc_th = d.curve(rt + "/Threshold_angle_vs_speed")
	rtc_max = d.curve(rt + "/Maximum_angle_vs_speed")
	rtc_cut = d.curve(rt + "/Maximum_cut_vs_speed")

	# ---- parte 1: pneus e derrapagem, como no executável (funções 0x20ede8,
	# 0x20eb98, 0x20efa0 e 0x2101e0). Detalhes nos comentários do _tires().
	P.understeer_raw = d.tuned("BasicSteering", "Understeer_coefficient", TUNE_UNDERSTEER)
	P.width_scale = d.tuned("FrictionEllipse", "Width_scale", 0.0)
	P.height_scale = d.tuned("FrictionEllipse", "Height_scale", 0.0)
	P.ell_disable = d.f("FrictionEllipse", "Disabling_friction", 2.0)   # params+0x43c
	for ax in ["FrontWheels", "RearWheels"]:
		var fe: String = "FrictionEllipse/" + ax
		P["ell_" + ax] = {"w": d.ftriple(fe + "/HalfWidth", "half_width"),
			"h": d.ftriple(fe + "/HalfHeight", "half_height"),
			"ms": d.ftriple(fe + "/MinimumScale", "minimum_scale"),
			"shrink": d.f(fe, "Shrink_rate", 1.0), "recover": d.f(fe, "Recovery_rate", 1.0)}
	P.front_bias = d.tuned("Footbrake", "Front_bias", TUNE_FRONT_BIAS)
	P.brake_fscale = d.ftriple("Footbrake", "scale")
	P.side_std = d.ftriple("Sideslip/SideVelocityDecelerationStandard", "deceleration")
	P.side_cs = d.ftriple("Sideslip/SideVelocityDecelerationCounterSteer", "deceleration")
	P.yaw_inc = d.fcurves("Sideslip/SideslipIncreaseYawAcceleration")
	P.yaw_dec_zero = d.fcurves("Sideslip/SideslipDecreaseYawAccelerationStandard/ZeroThrottle")
	P.yaw_dec_full = d.fcurves("Sideslip/SideslipDecreaseYawAccelerationStandard/FullThrottle")
	P.yaw_dec_cs = d.fcurves("Sideslip/SideslipDecreaseYawAccelerationCounterSteer")
	P.cs_scale = d.f("BasicSteering/MaximumYawAcceleration", "Counter_steer_maximum_scale", 1.0)
	P.cs_scale_ss = d.f("BasicSteering/MaximumYawAcceleration", "Counter_steer_maximum_scale_sideslip", 60.0)
	P.ps_side_to_fwd = d.f("Powerslide", "Side_deceleration_to_fwd_acceleration", 1.0)
	P.ps_growth = d.f("Powerslide", "Growth_rate", 60.0)
	P.ps_decay = d.f("Powerslide", "Decay_rate", 1.0)
	P.ps_air = d.f("Powerslide", "Maximum_air_time", 0.1)
	P.emb_up = d.f("InputRates/Clutch", "Digital_increase_rate", 8.0)
	P.emb_down = d.f("InputRates/Clutch", "Digital_decrease_rate", 8.0)
	P.ss_rate_inc = d.fcurves("Sideslip/MaximumRate/Maximum_increase_rate_vs_sideslip", "rate_vs_sideslip")
	P.ss_rate_dec = d.fcurves("Sideslip/MaximumRate/Maximum_decrease_rate_vs_sideslip", "rate_vs_sideslip")
	P.slip_grow = d.f("SlipRatio", "Growth_rate_during_wheel_spin", 3.0)
	P.slip_recover = d.f("SlipRatio", "Recovery_rate_during_wheel_spin", 4.0)
	P.slip_max = d.f("SlipRatio", "Maximum", 10.0)
	P.lock_grow = d.f("SlipRatio", "Growth_rate_during_wheel_lock", 2.0)
	P.lock_recover = d.f("SlipRatio", "Recovery_rate_during_wheel_lock", 2.0)
	# ABS (0x20eb98): solta o freio da roda com patinada < engagement e volta
	# com patinada >= disengagement
	P.abs_on = d.f("Footbrake", "Enable_ABS", 0.0) != 0.0
	P.abs_eng = d.f("Footbrake", "ABS_engagement_slip_ratio", -0.2)
	P.abs_dis = d.f("Footbrake", "ABS_disengagement_slip_ratio", -0.01)

	# estabilidade e ar
	P.h_long = d.f("Stability/WheelForceHeightScales", "Longitudinal_scale_std", 0.5)
	P.h_long_stf = d.f("Stability/WheelForceHeightScales", "Longitudinal_scale_side_decel_to_fwd_accel", 0.5)
	P.h_lat = d.f("Stability/WheelForceHeightScales", "Lateral_scale_std", 0.1)
	P.h_lat_roll = d.f("Stability/WheelForceHeightScales", "Lateral_scale_at_maximum_roll", P.h_lat)
	P.h_lat_s0 = d.f("Stability/WheelForceHeightScales", "Lateral_scale_sine_threshold_roll", 1.0)
	P.h_lat_s1 = d.f("Stability/WheelForceHeightScales", "Lateral_scale_sine_maximum_roll", 1.0)
	P.grav_up = d.f("Stability/InAir", "Gravity_scale_moving_up", 1.0)
	P.grav_down = d.f("Stability/InAir", "Gravity_scale_moving_down", 1.0)
	P.air_yaw_time = d.f("Stability/InAir/Yaw_control", "Minimum_time", 0.3)
	P.air_yaw_acc = deg_to_rad(d.f("Stability/InAir/Yaw_control", "Yaw_acceleration", 60.0))
	P.air_yaw_max = deg_to_rad(d.f("Stability/InAir/Yaw_control", "Maximum_yaw_velocity", 30.0))
	P.air_brk_acc = deg_to_rad(d.f("Stability/InAir/Brake_pitch_control", "Acceleration", 0.0))
	P.air_brk_max = deg_to_rad(d.f("Stability/InAir/Brake_pitch_control", "Maximum_pitch_velocity", 0.0))
	P.air_nt_acc = deg_to_rad(d.f("Stability/InAir/No_throttle_pitch_control", "Acceleration", 0.0))
	P.air_nt_max = deg_to_rad(d.f("Stability/InAir/No_throttle_pitch_control", "Maximum_pitch_velocity", 0.0))
	P.air_pitch_torque = d.f("Stability/InAir", "Pitch_torque", 0.0) * 1000.0
	P.air_lat_time = d.f("Stability/InAir/Lateral_control", "Minimum_time", 0.3)
	P.air_lat_tail = d.f("Stability/InAir/Lateral_control", "Tail_off_time", 2.0)
	P.air_lat_thr = d.f("Stability/InAir/Lateral_control", "Steer_threshold", 0.3)
	P.air_lat_change = d.f("Stability/InAir/Lateral_control", "Steer_change_scale", 0.15)
	P.air_lat_force = d.f("Stability/InAir/Lateral_control", "Maximum_force", 0.0) * 1000.0
	P.ap_th = d.f("Stability/AntiPitch", "Sine_threshold_angle", 0.087)
	P.ap_max = d.f("Stability/AntiPitch", "Sine_maximum_angle", 0.174)
	P.ap_acc = d.f("Stability/AntiPitch", "Acceleration", 0.0)

	# rodas: esquerda = +X (o carro anda pra +Z). Com o arquivo de pontos do
	# jogo, a roda fica onde o jogo põe (WHEEL_FRONT_LEFT...), passada pro frame
	# do Godot por corpo(): a esquerda do jogo (x < 0) vira +X. Sem ele, no chute.
	wheels.clear()
	var pts := _load_points(points_file)
	if ESCAPE_NOSSO.has(vehicle_id):
		for k in pts.keys():
			if String(k).begins_with("EXHAUST"):
				pts.erase(k)
				points_rot.erase(k)
		var e: Array = ESCAPE_NOSSO[vehicle_id]
		for k in e.size():
			var nm: String = "EXHAUST" if k == 0 else "EXHAUST%d" % (k + 1)
			var dz: Vector3 = e[k][1].normalized()
			var dx := Vector3.UP.cross(dz).normalized()
			pts[nm] = e[k][0]
			points_rot[nm] = Basis(dx, dz.cross(dx), dz)    # linha 2 = direção, como no _points.bin
	for pref: String in LUZES_NOSSAS.get(vehicle_id, {}):
		for k in pts.keys():
			if String(k).begins_with(pref):
				pts.erase(k)
				points_rot.erase(k)
		var lista: Array = LUZES_NOSSAS[vehicle_id][pref]
		for i in lista.size():
			var nm: String = pref if i == 0 else "%s~n%d" % [pref, i]
			pts[nm] = lista[i]
			points_rot[nm] = Basis()
	points = pts
	update_eye()
	var wpos := {}
	for k in ["FRONT_LEFT", "FRONT_RIGHT", "REAR_LEFT", "REAR_RIGHT"]:
		if pts.has("WHEEL_" + k):
			var pp: Vector3 = corpo(pts["WHEEL_" + k])
			var side := "Left" if k.ends_with("LEFT") else "Right"
			var key: String = ("Front" if k.begins_with("FRONT") else "Rear") + side
			wpos[key] = pp
	var from_points := wpos.size() == 4
	var com_z := com.z
	var wb := WHEEL_Z * 2.0
	if from_points:
		wb = (wpos.FrontLeft.z + wpos.FrontRight.z - wpos.RearLeft.z - wpos.RearRight.z) * 0.5
	P.wheelbase = wb
	P.wheels_from_points = from_points
	for info in [["FrontLeft", 1, 1], ["FrontRight", -1, 1], ["RearLeft", 1, -1], ["RearRight", -1, -1]]:
		var path: String = "Wheels/" + info[0]
		var w := {}
		w.front = info[2] > 0
		w.left = info[1] > 0                # esquerda do jogo = +X no Godot
		w.px = WHEEL_X * info[1]
		w.pz = WHEEL_Z * info[2]
		if from_points:
			w.px = wpos[info[0]].x
			w.pz = wpos[info[0]].z
		w.r = d.f(path, "Radius", 0.45)
		w.k = d.tuned(path, "Spring_rate", TUNE_SPRING)
		w.c = d.tuned(path, "Damping_coefficient", TUNE_DAMPING)
		w.min = d.f(path, "Minimum_position", -0.2)
		w.max = d.tuned(path, "Maximum_position", TUNE_SUSP)
		w.vmax = d.f(path, "Maximum_velocity", 10.0)
		w.kc = d.curve(path + "/Normalised_spring_rate_vs_position")
		w.dc = d.curve(path + "/Normalised_damping_coeff_vs_velocity")
		w.mw = d.f(path, "Mass", 0.05) * 1000.0           # massa da roda (kg)
		w.inercia = w.mw * w.r * w.r * 0.5                # W+0x3c (kg·m²; RAM 0.00625 t·m²)
		w.cos_max = d.f(path, "Cosine_maximum_collision_angle", 0.643)
		# peso parado nessa roda -> quanto a mola afunda. y0 = cubo com a mola
		# solta (x = 0); assim o cubo fica em WHEEL_Y com o carro parado
		var share: float = (WHEEL_Z + com_z) / wb if w.front else (WHEEL_Z - com_z) / wb
		var x_static := _solve_static(w, mass * G * share * 0.5)
		w.y0 = WHEEL_Y - x_static
		w.xs = x_static                     # curso parado (corpo+0x4c0; pedras.gd)
		if from_points:
			w.y0 = wpos[info[0]].y          # cubo com a mola solta = ponto do jogo
		w.x = 0.0                           # curso (0x0e8): + = comprimida, - = esticada
		w.v = 0.0                           # velocidade do curso (0x0f4)
		w.f = 0.0                           # força da mola no carro (N, 0x0fc)
		w.hit = false
		w.jit = 0.0                         # tremida visual do curso (m)
		w.mat = -1                          # material do chão embaixo da roda (W+0x140)
		w.point = Vector3.ZERO
		w.normal = Vector3.UP
		w.spin = 0.0                        # ângulo da roda (W+0x4c, 0..2π)
		w.omega = 0.0                       # giro (W+0x48, rad/s, + = rolando pra frente)
		w.sr = 0.0                          # patinada medida (0x600)
		w.grip = 1.0                        # escala da elipse (encolhe patinando)
		w.mu = SURFACE_MU                   # atrito do chão nesta roda (0x750)
		w.amort = SURFACE_AMORT             # Damping do chão nesta roda (0x758)
		w.slip = 0.0                        # patinada (0x610): + girando, - travando (até -1)
		w.abs = false                       # ABS soltando o freio desta roda (0x620)
		w.sat = false
		w.fx = 0.0                          # força lateral do passo (N, + = esquerda)
		w.fz = 0.0                          # força longitudinal do passo (N)
		wheels.append(w)
	P.wheel_r = wheels[2].r
	# ordem do jogo (corpo+0x254): FL, RL, FR, RR
	jit_order = []
	for fl in [[true, true], [false, true], [true, false], [false, false]]:
		for i in wheels.size():
			var w: Dictionary = wheels[i]
			if w.front == fl[0] and w.left == fl[1]:
				jit_order.append(i)
	jit_seed = Time.get_ticks_msec() & 0x3FFFFFFF   # o jogo semeia com o relógio
	# 0x20bf58: o jogo mede os eixos a partir da ORIGEM DO MODELO, não do CoM
	# (a média do z das rodas, antes de descontar o centro de massa). Esses
	# valores entram na curvatura, na divisão da força lateral entre os eixos e
	# no ponto onde ela é aplicada (CoM + frente x eixo).
	P.axle_f = (wheels[0].pz + wheels[1].pz) * 0.5 - model_offset.z
	P.axle_r = (wheels[2].pz + wheels[3].pz) * 0.5 - model_offset.z
	reset_drivetrain()


## Mola do jogo (0x248a80): F = k x curva(x normalizado) x x, em kN.
## Normaliza por Maximum_position comprimindo e por Minimum_position esticando;
## esticada (x < 0) com a roda no chão, ela puxa o carro pra baixo.
func _spring(w: Dictionary, x: float) -> float:
	var u := 0.0
	if x >= 0.0 and w.max > 0.0:
		u = x / w.max
	elif x < 0.0 and w.min < 0.0:
		u = x / w.min
	return w.k * VehicleData.sample(w.kc, u) * x * 1000.0


func _damper(w: Dictionary, v: float) -> float:
	return w.c * VehicleData.sample(w.dc, absf(v)) * v * 1000.0


## 0x2484c8: curso de cada roda anda com a massa dela, com a força do passo
## anterior (no chão, a mola + amortecedor guardados em w.f). No ar a mola e
## o amortecedor levam a roda de volta pro meio (x = 0)
func _integra_rodas(dt: float) -> void:
	for w in wheels:
		var fw: float
		if w.hit:
			fw = -w.f
		else:
			var damp: float = -_damper(w, w.v)
			var dv: float = damp / w.mw * dt
			if absf(dv) > absf(w.v) and absf(dv) > 1e-6:
				damp *= absf(w.v / dv)
			fw = -_spring(w, w.x) + damp
		w.v = clampf(w.v + fw / w.mw * dt, -w.vmax, w.vmax)
		w.x = clampf(w.x + w.v * dt, w.min, w.max)


## Arquivo de pontos do modelo: "POINT 1.00", contagem em 0x10, entradas de
## 0x50 bytes a partir de 0x14: nome (0x00..0x20), posição x, y, z (0x20) e
## matriz 3x3 em linhas (0x2c, escala 0.01; o jogo usa normalizada). A linha
## 2 da matriz do A_FRAME_* é o eixo da balança (suspension_visual.gd).
## Nome repetido: o último fica com o nome (como sempre foi), os outros NOME~k.
func _load_points(path: String) -> Dictionary:
	var out := {}
	points_rot = {}
	if path == "" or not FileAccess.file_exists(path):
		return out
	if path.ends_with(".json"):          # carro extra nosso (tools/carro_glb.py)
		var j = JSON.parse_string(FileAccess.get_file_as_string(path))
		for nm in j.pontos:
			var p: Array = j.pontos[nm]
			out[nm] = Vector3(p[0], p[1], p[2])
			var r: Array = j.rot.get(nm, [[1, 0, 0], [0, 1, 0], [0, 0, 1]])
			points_rot[nm] = Basis(Vector3(r[0][0], r[0][1], r[0][2]), Vector3(r[1][0], r[1][1], r[1][2]),
				Vector3(r[2][0], r[2][1], r[2][2]))
		return out
	var buf := FileAccess.get_file_as_bytes(path)
	if buf.size() < 0x60 or buf.slice(0, 5).get_string_from_ascii() != "POINT":
		push_warning("%s não é um arquivo de pontos" % path)
		return out
	var off := 0x14
	while off + 0x50 <= buf.size():
		var nm := buf.slice(off, off + 0x20).get_string_from_ascii()
		# nome repetido (os 2 EXHAUST dos trucks, TAIL_LIGHT do Trident, estepe
		# do Chimera): o último fica com o nome, os de antes viram NOME~1, NOME~2
		if out.has(nm):
			var k := 1
			while out.has("%s~%d" % [nm, k]):
				k += 1
			out["%s~%d" % [nm, k]] = out[nm]
			points_rot["%s~%d" % [nm, k]] = points_rot[nm]
		out[nm] = Vector3(buf.decode_float(off + 0x20), buf.decode_float(off + 0x24), buf.decode_float(off + 0x28))
		var rows := []
		for r in 3:
			var o := off + 0x2c + r * 12
			rows.append(Vector3(buf.decode_float(o), buf.decode_float(o + 4), buf.decode_float(o + 8)).normalized())
		points_rot[nm] = Basis(rows[0], rows[1], rows[2])
		off += 0x50
	return out


## 0x23f6c0: soma correções de posição; no mesmo sentido fica a maior
func _add_corr(c: Vector3, d: Vector3) -> Vector3:
	for i in 3:
		if signf(c[i]) == signf(d[i]) or c[i] == 0.0:
			if absf(d[i]) > absf(c[i]):
				c[i] = d[i]
		else:
			c[i] += d[i]
	return c


func _solve_static(w: Dictionary, f_load: float) -> float:
	var lo := 0.0
	var hi: float = w.max
	for i in 40:
		var mid := (lo + hi) * 0.5
		if _spring(w, mid) < f_load:
			lo = mid
		else:
			hi = mid
	return lo


# ------------------------------------------------------------------ visual
func _make_wheel_mesh(w: Dictionary) -> void:
	var pivot := Node3D.new()       # frame do jogo (dentro do espelho)
	espelho.add_child(pivot)
	var spin := Node3D.new()
	pivot.add_child(spin)
	w.pivot = pivot
	w.spin_node = spin
	var canto: String = ("F" if w.front else "R") + ("L" if w.left else "R")
	var rg: Dictionary = pecas.get("rodas_glb", {}).get(canto, {})
	if _cena_glb and not rg.is_empty():
		# carro extra: a roda de cada canto do modelo (não espelha) e o cubo
		# dela (SUSP_xx: segue o curso e o esterço, não gira)
		var c := Vector3(rg.centro[0], rg.centro[1], rg.centro[2])
		var rmi := MeshInstance3D.new()
		rmi.mesh = CarroGlb.malha(_cena_glb, [rg.no], [], c, pecas.get("escala", 1.0))
		spin.add_child(rmi)
		if not rg.get("cubo", []).is_empty():
			var cmi := MeshInstance3D.new()
			cmi.mesh = CarroGlb.malha(_cena_glb, rg.cubo, [], c, pecas.get("escala", 1.0))
			pivot.add_child(cmi)
		return
	var path: String = wheel_front_file if w.front else wheel_rear_file
	if path != "" and ResourceLoader.exists(path):
		var mesh: Mesh = load(path) as Mesh
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i)
			if m is StandardMaterial3D:
				var m2: StandardMaterial3D = m.duplicate()
				material_do_jogo(m2)
				mi.set_surface_override_material(i, m2)
		# component map (14881): Mirror="1" nas rodas da esquerda do jogo
		# (o pivô está no frame do jogo, dentro do espelho)
		if w.left:
			mi.scale.x = -1.0
		# centro do modelo = centro da roda (sem deslocamento: matriz da RAM)
		spin.add_child(mi)
		return
	push_warning("Roda não encontrada em %s. Veja docs/assets.md (rodas)." % path)
	var cyl := CylinderMesh.new()
	cyl.top_radius = w.r
	cyl.bottom_radius = w.r
	cyl.height = 0.34
	cyl.radial_segments = 20
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.08, 0.08)
	mat.roughness = 0.9
	cyl.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.rotation_degrees = Vector3(0, 0, 90)
	spin.add_child(mi)
	# um risco claro pra dar pra ver a roda girando
	var mark := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.36, 0.08, w.r * 1.6)
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.35, 0.35, 0.35)
	bm.material = mm
	mark.mesh = bm
	spin.add_child(mark)


func _load_model() -> void:
	var mi := MeshInstance3D.new()
	var mesh: Mesh = null
	var glb := model_path.ends_with(".glb")
	if glb and ResourceLoader.exists(model_path):
		# carro extra nosso: a cena fica aberta até as rodas e o volante saírem dela
		_cena_glb = (load(model_path) as PackedScene).instantiate()
		CarroGlb.configurar(pecas)
		mesh = CarroGlb.malha(_cena_glb, [], pecas.get("excluir", []), Vector3.ZERO, pecas.get("escala", 1.0))
	elif model_path != "" and ResourceLoader.exists(model_path):
		mesh = load(model_path) as Mesh
	if mesh == null:
		push_warning("Modelo não encontrado em %s. Copie a pasta renegade pra assets/renegade." % model_path)
		var bm := BoxMesh.new()
		bm.size = Vector3(2.2, 1.0, 4.6)
		mi.mesh = bm
		mi.position = Vector3(0, 1.0, 0)
		model_root.add_child(mi)
		return
	mi.mesh = mesh
	# pintura: a carroceria usa a textura "white", que o jogo gera em tempo
	# real juntando camadas (Base/Primary/Secondary/Detail + cores do XML).
	# O gerar_pintura.py faz isso e salva pintura.png do lado do modelo.
	var livery: Texture2D = null
	var lp := model_path.get_base_dir().path_join(livery_file)
	if ResourceLoader.exists(lp):
		livery = load(lp)
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i)
		if glb:
			continue                  # materiais do .glb como vieram (PBR, sem cor de vértice)
		var m2: StandardMaterial3D
		if m is StandardMaterial3D:
			m2 = m.duplicate()
		else:
			m2 = StandardMaterial3D.new()
			m2.albedo_color = Color(0.85, 0.85, 0.85)
		if livery and m and m.resource_name.ends_with("_white"):
			m2.albedo_texture = livery
		# textura com furo no jogo (redes das janelas, treliça do Trident):
		# tools/alfa_texturas.py devolve o alfa e aqui vira recorte
		if m2.albedo_texture and _tem_alfa(m2.albedo_texture):
			m2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m2.alpha_scissor_threshold = 0.5
		# vidro (só o Lazarus tem: Dakar_window_Index): o lote do .pingu vem
		# marcado transparente (+0x00 = 1, como decalques, sombras e o carro
		# fantasma), mas a textura _Index tem alfa cheio e o vidro saía uma
		# placa azul opaca por fora. A mesma imagem na Truck/Textures/Generic
		# (Dakar_window_8) tem alfa 0x1B = 21%: é o que vale aqui
		if m2.albedo_texture and m2.albedo_texture.resource_path.get_file().to_lower().contains("window"):
			m2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m2.albedo_color.a = VIDRO_ALFA
		material_do_jogo(m2)
		mi.set_surface_override_material(i, m2)
	var aabb := mesh.get_aabb()
	var c := aabb.get_center()
	model_offset = Vector3(-c.x, -aabb.position.y + 0.12, -c.z)
	mi.position = model_offset
	model_root.add_child(mi)
	body_mi = mi
	if chave() in CABINE_FECHADA:
		_face_de_dentro(mi)
	_load_steering_wheel()


## depois da física (precisa dos pontos ARSE, rodas e EXHAUST)
func _load_motor_treme() -> void:
	if not (MOTOR_TREME and _tem("motor_treme")) or body_mi == null:
		return
	motor_treme = preload("res://motor_treme.gd").new()
	motor_treme.name = "MotorTreme"
	# trucks e extras: só o escape; extra (200 mil triângulos): só busca a 1 m da boca
	if motor_treme.separar(body_mi, points, vehicle_id, vehicle_id.begins_with("TRUCK") or motor_escondido,
			1.0 if _cena_glb else 0.0):
		model_root.add_child(motor_treme)
	else:
		motor_treme.free()
		motor_treme = null


func _load_luzes() -> void:
	if not (LUZ_FREIO and _tem("luzes")) or body_mi == null:
		return
	luzes = preload("res://luzes.gd").new()
	luzes.name = "Luzes"
	if luzes.montar(self):
		add_child(luzes)
	else:
		luzes.free()
		luzes = null


func _load_farol() -> void:
	if not (FAROL and _tem("farol")) or body_mi == null:
		return
	farol = preload("res://farol.gd").new()
	farol.name = "Farol"
	if farol.montar(self):
		add_child(farol)
	else:
		farol.free()
		farol = null


func _load_motor_anima() -> void:
	if not (MOTOR_ANIMA and _tem("motor_anima")) or body_mi == null:
		return
	if (vehicle_id.begins_with("TRUCK") and not (chave() in ANIMA_TRUCKS)) or motor_escondido:
		return
	motor_anima = preload("res://motor_anima.gd").new()
	motor_anima.name = "MotorAnima"
	if motor_anima.montar(self):
		add_child(motor_anima)
	else:
		motor_anima.free()
		motor_anima = null


## copia virada (ordem dos vértices e normal) de cada triângulo que não tem
## gêmeo do outro lado (mesmos 3 pontos); fica numa malha filha
func _face_de_dentro(mi: MeshInstance3D) -> void:
	var mesh: Mesh = mi.mesh
	var chave := func(a: Vector3, b: Vector3, c: Vector3) -> Array:
		var k := [Vector3i((a * 1000.0).round()), Vector3i((b * 1000.0).round()), Vector3i((c * 1000.0).round())]
		k.sort()
		return k
	var existe := {}
	var arrs: Array = []
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		arrs.append(a)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ix := PackedInt32Array(range(vs.size()))
		if a[Mesh.ARRAY_INDEX] != null:
			ix = a[Mesh.ARRAY_INDEX]
		for t in range(0, ix.size(), 3):
			var k: Array = chave.call(vs[ix[t]], vs[ix[t + 1]], vs[ix[t + 2]])
			existe[k] = existe.get(k, 0) + 1
	var costas := _com_costas(arrs)
	var dentro := ArrayMesh.new()
	var mats: Array = []
	var forro := StandardMaterial3D.new()
	forro.albedo_color = FORRO
	forro.roughness = 0.9
	forro.cull_mode = MODEL_CULL
	for s in arrs.size():
		# vidro (textura *window*, o Lazarus tem os vidros fechados no modelo):
		# fica sem face de dentro, senão de dentro a janela vira parede
		var ms := mi.get_active_material(s) as BaseMaterial3D
		if ms and ms.albedo_texture and ms.albedo_texture.resource_path.get_file().to_lower().contains("window"):
			continue
		var a: Array = arrs[s].duplicate()
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ix := PackedInt32Array(range(vs.size()))
		if a[Mesh.ARRAY_INDEX] != null:
			ix = a[Mesh.ARRAY_INDEX]
		var novo := PackedInt32Array()
		var painel := PackedInt32Array()     # painel de 2 lados: a cópia leva o material de fora
		for t in range(0, ix.size(), 3):
			if existe[chave.call(vs[ix[t]], vs[ix[t + 1]], vs[ix[t + 2]])] > 1:
				continue                  # chapa de 2 faces: já tem o lado de dentro
			var ct: int = costas.get(Vector2i(s, t), 0)
			if ct == 1:
				continue                  # idem, com os triângulos cortados diferente
			if ct == 2:
				painel.append_array([ix[t], ix[t + 2], ix[t + 1]])
				continue
			novo.append_array([ix[t], ix[t + 2], ix[t + 1]])
		if novo.is_empty() and painel.is_empty():
			continue
		if a[Mesh.ARRAY_NORMAL] != null:
			var ns: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			for i in ns.size():
				ns[i] = -ns[i]
			a[Mesh.ARRAY_NORMAL] = ns
		a[Mesh.ARRAY_TANGENT] = null
		var m: Material = mi.get_active_material(s)
		if not novo.is_empty():
			a[Mesh.ARRAY_INDEX] = novo
			dentro.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			mats.append(forro if m and m.resource_name.ends_with("_white") else m)
		if not painel.is_empty():
			a[Mesh.ARRAY_INDEX] = painel
			dentro.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			mats.append(m)
	if dentro.get_surface_count() == 0:
		return
	var d := MeshInstance3D.new()
	d.name = "FaceDeDentro"
	d.mesh = dentro
	for s in mats.size():
		d.set_surface_override_material(s, mats[s])
	mi.add_child(d)


## triângulos que já têm o lado de trás modelado com outra divisão em
## triângulos (o mesmo quadrado cortado pela outra diagonal, virado pro outro
## lado): o centro deles cai num triângulo de sentido oposto no mesmo plano (até
## 3 mm), ou o centro dele cai neles. No painel do ELF atrás da cabine do Hammerhead a cópia de dentro
## desses ficava no plano da pintura de fora, com o forro cinza, e piscava
## (nov/2026). Devolve {Vector2i(superfície, índice do 1º vértice): 1}; e 2
## quando o triângulo não é coberto mas divide uma aresta com um do outro
## lado no mesmo plano: o painel é de 2 lados no jogo (o ELF aparece dos 2
## lados) e a cópia leva a pintura em vez do forro
static func _com_costas(arrs: Array) -> Dictionary:
	const CEL := 0.25
	var tris: Array = []              # [s, t, a, b, c, normal]
	var grade := {}
	for s in arrs.size():
		var a: Array = arrs[s]
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ix := PackedInt32Array(range(vs.size()))
		if a[Mesh.ARRAY_INDEX] != null:
			ix = a[Mesh.ARRAY_INDEX]
		for t in range(0, ix.size(), 3):
			var p0 := vs[ix[t]]
			var p1 := vs[ix[t + 1]]
			var p2 := vs[ix[t + 2]]
			var n := (p1 - p0).cross(p2 - p0)
			if n.length_squared() < 1e-14:
				continue
			var k := tris.size()
			tris.append([s, t, p0, p1, p2, n.normalized()])
			var lo := Vector3i((p0.min(p1).min(p2) / CEL).floor())
			var hi := Vector3i((p0.max(p1).max(p2) / CEL).floor())
			if (hi - lo).length_squared() > 64:
				continue                  # placa enorme: não é desses painéis
			for x in range(lo.x, hi.x + 1):
				for y in range(lo.y, hi.y + 1):
					for z in range(lo.z, hi.z + 1):
						var c := Vector3i(x, y, z)
						if not grade.has(c):
							grade[c] = []
						grade[c].append(k)
	var out := {}
	for tr in tris:
		var g: Vector3 = (tr[2] + tr[3] + tr[4]) / 3.0
		var n: Vector3 = tr[5]
		for k in grade.get(Vector3i((g / CEL).floor()), []):
			var u: Array = tris[k]
			var nu: Vector3 = u[5]
			if nu.dot(n) > -0.99 or absf((g - u[2]).dot(nu)) > 0.003:
				continue
			var bc := Geometry3D.get_triangle_barycentric_coords(g, u[2], u[3], u[4])
			var gu: Vector3 = (u[2] + u[3] + u[4]) / 3.0
			var bu := Geometry3D.get_triangle_barycentric_coords(gu, tr[2], tr[3], tr[4])
			if (bc.x > 0.0 and bc.y > 0.0 and bc.z > 0.0) or (bu.x > 0.0 and bu.y > 0.0 and bu.z > 0.0):
				out[Vector2i(tr[0], tr[1])] = 1
				break
			var comum := 0
			for p in [tr[2], tr[3], tr[4]]:
				for q in [u[2], u[3], u[4]]:
					if (p as Vector3).distance_squared_to(q) < 1e-6:
						comum += 1
			if comum >= 2:
				out[Vector2i(tr[0], tr[1])] = 2
	return out


static var _alfa_cache := {}


static func _tem_alfa(t: Texture2D) -> bool:
	var k := t.resource_path if t.resource_path != "" else str(t.get_instance_id())
	if not _alfa_cache.has(k):
		var img := t.get_image()
		if img and img.is_compressed():
			img = img.duplicate()
			img.decompress()
		_alfa_cache[k] = img != null and img.detect_alpha() != Image.ALPHA_NONE
	return _alfa_cache[k]


## piloto (piloto.gd): o osso ROOT da animação fica em cima do ponto ARSE
## (rider+0x2f0; no Renegade origem = ARSE - (0, 1.1315, 0.3032)), sem girar
## com a matriz do ponto
func _load_piloto() -> void:
	if not points.has("ARSE"):
		return
	piloto = preload("res://piloto.gd").new()
	if not piloto.carregar(PILOTO_DIR, MODEL_CULL):
		piloto.free()
		piloto = null
		return
	piloto.name = "Piloto"
	piloto.position = model_offset + banco() - piloto.root_pos
	model_root.add_child(piloto)
	piloto.paredes = _paredes_do_piloto()
	if MAOS_NO_VOLANTE and VOLANTE_GIRA and _tem("maos") and _tem("volante_gira") and sw_pivot:
		var vol: Dictionary = pecas.get("volante", {})
		# aro no frame do esqueleto (o piloto não gira em relação ao modelo)
		piloto.prender_no_volante(sw_centro() - (banco() - piloto.root_pos), SW_AXIS, vol.get("raio", 0.19))


## onde fica a carroceria dos lados do piloto, pros cotovelos não varar a
## porta (Fireball: 6.4 cm pra dentro dela; piloto.gd PAREDE_FOLGA). Grade em
## (altura, frente) em volta do banco; em cada ponto um raio sai do meio do
## banco pros 2 lados e guarda onde bate na carroceria (ignora o que fica a
## menos de PAREDE_INICIO do meio: banco e o próprio piloto). Frame do
## esqueleto do piloto. Os triângulos vão numa grade (altura, frente) pra cada
## raio testar só os dele (~5 ms)
const PAREDE_INICIO := 0.18
func _paredes_do_piloto() -> Dictionary:
	if body_mi == null or not (body_mi.mesh is ArrayMesh):
		return {}
	var b := banco()
	var desl: Vector3 = b - piloto.root_pos      # esqueleto -> frame da carroceria
	var y0 := b.y + 0.05
	var z0 := b.z - 0.35
	var passo := Vector2(0.06, 0.06)
	var n := Vector2i(13, 18)                   # 0.05..0.77 acima e -0.35..+0.67 do banco
	var tris: Array = []
	var cel := {}
	var m: ArrayMesh = body_mi.mesh
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ix := PackedInt32Array(range(vs.size()))
		if a[Mesh.ARRAY_INDEX] != null:
			ix = a[Mesh.ARRAY_INDEX]
		for t in range(0, ix.size(), 3):
			var p0 := vs[ix[t]]
			var p1 := vs[ix[t + 1]]
			var p2 := vs[ix[t + 2]]
			var lo := p0.min(p1).min(p2)
			var hi := p0.max(p1).max(p2)
			if hi.x < b.x - 1.2 or lo.x > b.x + 1.2:
				continue
			var i0 := floori((lo.y - y0) / passo.x)
			var i1 := floori((hi.y - y0) / passo.x)
			var j0 := floori((lo.z - z0) / passo.y)
			var j1 := floori((hi.z - z0) / passo.y)
			if i1 < 0 or j1 < 0 or i0 >= n.x or j0 >= n.y:
				continue
			var k := tris.size()
			tris.append([p0, p1, p2])
			for i in range(maxi(i0, 0), mini(i1, n.x - 1) + 1):
				for j in range(maxi(j0, 0), mini(j1, n.y - 1) + 1):
					var c := Vector2i(i, j)
					if not cel.has(c):
						cel[c] = []
					cel[c].append(k)
	var dist := {1: PackedFloat32Array(), -1: PackedFloat32Array()}
	for lado in [1, -1]:
		var d: PackedFloat32Array = dist[lado]
		d.resize(n.x * n.y)
		for i in n.x:
			for j in n.y:
				var o := Vector3(b.x, y0 + (i + 0.5) * passo.x, z0 + (j + 0.5) * passo.y)
				var dir := Vector3(lado, 0.0, 0.0)
				var melhor := 2.0
				for k in cel.get(Vector2i(i, j), []):
					var tr: Array = tris[k]
					var r = Geometry3D.ray_intersects_triangle(o, dir, tr[0], tr[1], tr[2])
					if r != null:
						var dd: float = ((r as Vector3) - o).x * lado
						if dd > PAREDE_INICIO and dd < melhor:
							melhor = dd
				d[i * n.y + j] = melhor
	# no frame do esqueleto: x do meio do banco, y0/z0 deslocados
	return {"x": b.x - desl.x, "y0": y0 - desl.y, "z0": z0 - desl.z, "passo": passo, "n": n, "dist": dist}


## centro do aro do volante que aparece (o do jogo, ou o gerado avançado)
func sw_centro() -> Vector3:
	return SW_CENTER + SW_AXIS.normalized() * (avanco_volante() + sw_avanco)


## chave do carro nas tabelas por carro: o vehicle_id, menos no bônus (o
## Lazarus usa o id do Jericho, TRUCK_04, pra física e peças)
func chave() -> String:
	return "LAZARUS" if asset_dir.ends_with("truck_bonus") else vehicle_id


## onde o piloto senta (frame do jogo): o ponto ARSE + BANCO_NOSSO
func banco() -> Vector3:
	var b: Vector3 = BANCO_NOSSO.get(chave(), Vector3.ZERO)
	if OS.has_environment("BANCO"):
		var p := OS.get_environment("BANCO").split(",")
		b = Vector3(float(p[0]), float(p[1]), float(p[2]))
	return points.get("ARSE", Vector3.ZERO) + b


## quanto o volante vem pro piloto (AVANCO_VOLANTE), além do da coluna
func avanco_volante() -> float:
	if OS.has_environment("AVANCO"):
		return float(OS.get_environment("AVANCO"))
	return AVANCO_VOLANTE.get(chave(), 0.0)


func _load_fumaca() -> void:
	if not (FUMACA and _tem("fumaca")):
		return
	fumaca = preload("res://fumaca.gd").new()
	fumaca.name = "Fumaca"
	add_child(fumaca)
	if not fumaca.montar(self):
		fumaca.queue_free()
		fumaca = null


func _load_poeira() -> void:
	if not (POEIRA and _tem("poeira")):
		return
	poeira = preload("res://poeira.gd").new()
	poeira.name = "Poeira"
	add_child(poeira)
	if not poeira.montar(self):
		poeira.queue_free()
		poeira = null


func _load_pedras() -> void:
	if not (PEDRAS and _tem("pedras")):
		return
	pedras = preload("res://pedras.gd").new()
	pedras.name = "Pedras"
	add_child(pedras)
	if not pedras.montar(self):
		pedras.queue_free()
		pedras = null


func _load_painel() -> void:
	if not (PAINEL and _tem("painel")):
		return
	painel = preload("res://painel.gd").new()
	painel.name = "Painel"
	painel.position = model_offset
	model_root.add_child(painel)
	if not painel.montar(self):
		painel.queue_free()
		painel = null


func _load_sujeira() -> void:
	if not SUJEIRA or not _tem("sujeira"):    # carro extra sem a 2ª textura (main.gd "desligar")
		return
	if OS.has_environment("SUJEIRA"):          # prints: nível fixo (e lama de terra nas rodas)
		sujeira_nivel = clampf(float(OS.get_environment("SUJEIRA")), 0.0, 1.0)
		if terrain and terrain.materials.size() > 0:
			roda_cor = Color(terrain.materials[0].get("DustColour", Color.BLACK), 0.8 * sujeira_nivel)
	sujeira = preload("res://sujeira.gd").new()
	if not sujeira.montar(self):
		sujeira = null
		return
	sujeira.atualizar(sujeira_nivel, roda_cor)


func _load_sfx() -> void:
	if not SOM_PNEU:
		return
	sfx = preload("res://sfx_carro.gd").new()
	sfx.name = "SomPneu"
	add_child(sfx)
	if not sfx.carregar(self):
		sfx.queue_free()
		sfx = null


func _load_som() -> void:
	if not (SOM_MOTOR and _tem("som_motor")):
		return
	var dir: String = som_pasta if som_pasta != "" else preload("res://motor_som.gd").pasta_do_carro(vehicle_id)
	if dir == "":
		return
	som = preload("res://motor_som.gd").new()
	som.name = "SomMotor"
	if som.carregar(dir):
		add_child(som)
	else:
		som.free()
		som = null


func _process(delta: float) -> void:
	if som:
		som.atualizar(rpm, som_carga, delta)
	if fumaca:
		fumaca.atualizar(som_carga, rpm)
	if motor_treme:
		motor_treme.atualizar(rpm, som_carga, delta)
	if fumaca:
		fumaca.seguir()             # depois do motor_treme: o cano já tremeu neste quadro
	if motor_anima:
		motor_anima.atualizar(delta, rpm)
	if luzes:
		luzes.atualizar(delta, brake_in, gear == -1)
	if farol:
		farol.atualizar(delta)
	if sujeira:
		sujeira.atualizar(sujeira_nivel, roda_cor)
	if painel:
		painel.atualizar(delta)


func _load_steering_wheel() -> void:
	var path := model_path.get_basename() + "_volante.obj"
	var nosso := VOLANTE_NOSSO and _tem("volante_nosso")
	var vg: Dictionary = pecas.get("volante", {})
	if _cena_glb and vg.has("no") and not nosso:
		# carro extra: o volante do próprio modelo (STEER_HR) gira
		SW_CENTER = Vector3(vg.centro[0], vg.centro[1], vg.centro[2])
		SW_AXIS = Vector3(vg.eixo[0], vg.eixo[1], vg.eixo[2])
		sw_pivot = Node3D.new()
		sw_pivot.position = model_offset + SW_CENTER
		model_root.add_child(sw_pivot)
		var vmi := MeshInstance3D.new()
		vmi.mesh = CarroGlb.malha(_cena_glb, [vg.no], [], SW_CENTER, pecas.get("escala", 1.0))
		sw_pivot.add_child(vmi)
		return
	if not ResourceLoader.exists(path) and not (nosso and VOLANTE_SEM_MODELO.has(chave())):
		return
	var vol: Dictionary = pecas.get("volante", {})
	if vol.has("centro"):
		SW_CENTER = Vector3(vol.centro[0], vol.centro[1], vol.centro[2])
		SW_AXIS = Vector3(vol.eixo[0], vol.eixo[1], vol.eixo[2])
	sw_pivot = Node3D.new()
	sw_pivot.position = model_offset + SW_CENTER
	model_root.add_child(sw_pivot)
	var mi := MeshInstance3D.new()
	if nosso:
		sw_pivot.add_child(mi)
		sw_malha = mi
		sw_ponta_coluna = _ponta_coluna()
		_montar_volante(volante_estilo if volante_estilo != "" else Volantes.do_carro(chave()))
		return
	var mesh := load(path) as Mesh
	if mesh == null:
		return
	mi.mesh = mesh
	mi.position = -SW_CENTER
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i)
		var m2: StandardMaterial3D = m.duplicate() if m is StandardMaterial3D else StandardMaterial3D.new()
		material_do_jogo(m2)
		mi.set_surface_override_material(i, m2)
	sw_pivot.add_child(mi)


## monta o volante gerado. O centro dele é recuado pro painel (dish) e a
## coluna de direção do jogo, feita pro volante chato, termina quase no plano
## do aro: o volante avança pro piloto até a coluna acabar atrás do miolo
## (Kraken 5.5 cm, Viper 3.5, Trident 2.5, Storm 2.9; Renegade e Bulldog 0)
func _montar_volante(nome: String) -> void:
	volante_estilo = nome
	sw_malha.mesh = Volantes.montar(pecas.get("volante", {}).get("raio", 0.19), SW_AXIS, nome)
	sw_avanco = maxf(0.0, sw_ponta_coluna - avanco_volante() + 0.004 + Volantes.fundo(nome))
	sw_pivot.position = model_offset + sw_centro()
	_montar_coluna(nome)
	if piloto and piloto.no_volante():
		piloto.prender_no_volante(sw_centro() - (banco() - piloto.root_pos), SW_AXIS,
			pecas.get("volante", {}).get("raio", 0.19))


## coluna de direção nossa, quando a do modelo não encosta no volante: o volante
## trazido pro piloto (AVANCO_VOLANTE) ou sem volante no modelo
## (VOLANTE_SEM_MODELO). Vai do miolo pra trás no eixo até a ponta da coluna
## do modelo ou, sem ela, até a carroceria (raio no eixo; até COLUNA_MAX)
func _montar_coluna(nome: String) -> void:
	if sw_coluna:
		sw_coluna.queue_free()
		sw_coluna = null
	var ate := -INF                # onde a coluna acaba, no eixo a partir do SW_CENTER (- = pro painel)
	if VOLANTE_SEM_MODELO.has(chave()):
		ate = -_painel_no_eixo()
	elif avanco_volante() > 0.0 and sw_ponta_coluna > -INF:
		ate = sw_ponta_coluna - 0.02
	if ate == -INF:
		return
	var n := SW_AXIS.normalized()
	var ini := avanco_volante() + sw_avanco - Volantes.fundo(nome)    # atrás do miolo
	var comp := ini - ate
	if comp <= 0.01:
		return
	var cil := CylinderMesh.new()
	cil.top_radius = COLUNA_RAIO
	cil.bottom_radius = COLUNA_RAIO
	cil.height = comp
	cil.radial_segments = 16
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.07, 0.07, 0.075)
	m.metallic = 0.6
	m.roughness = 0.45
	cil.material = m
	sw_coluna = MeshInstance3D.new()
	sw_coluna.name = "ColunaNossa"
	sw_coluna.mesh = cil
	var y := n
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	sw_coluna.transform = Transform3D(Basis(x, y, x.cross(y)), model_offset + SW_CENTER + n * (ate + comp * 0.5))
	model_root.add_child(sw_coluna)


## distância do centro do aro até a carroceria, andando pra trás no eixo
## (o painel); COLUNA_MAX se não bater em nada
func _painel_no_eixo() -> float:
	var m := load(model_path) as Mesh
	if m == null:
		return COLUNA_MAX
	var o := SW_CENTER
	var d := -SW_AXIS.normalized()
	var melhor := COLUNA_MAX
	for si in m.get_surface_count():
		var a := m.surface_get_arrays(si)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ix := PackedInt32Array(range(vs.size()))
		if a[Mesh.ARRAY_INDEX] != null:
			ix = a[Mesh.ARRAY_INDEX]
		for t in range(0, ix.size(), 3):
			var hit = Geometry3D.ray_intersects_triangle(o, d, vs[ix[t]], vs[ix[t + 1]], vs[ix[t + 2]])
			if hit == null:
				hit = Geometry3D.ray_intersects_triangle(o, d, vs[ix[t]], vs[ix[t + 2]], vs[ix[t + 1]])
			if hit != null:
				melhor = minf(melhor, o.distance_to(hit))
	return melhor


## ponta da coluna de direção na carroceria: o vértice mais pro lado do piloto
## perto do eixo do volante (até 6 cm dele e 8 cm atrás do aro). -INF = sem coluna
func _ponta_coluna() -> float:
	var m := load(model_path) as Mesh
	var ponta := -INF
	if m == null:
		return ponta
	var n := SW_AXIS.normalized()
	for si in m.get_surface_count():
		var vs: PackedVector3Array = m.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
		for v in vs:
			var d := v - SW_CENTER
			var t := d.dot(n)
			if t > -0.08 and t < 0.1 and (d - n * t).length() < 0.06:
				ponta = maxf(ponta, t)
	return ponta


## troca o volante gerado (nome = "" passa pro próximo estilo); devolve o nome
func trocar_volante(nome := "") -> String:
	if sw_malha == null:
		return ""
	if nome == "":
		var lista := Volantes.nomes()
		nome = lista[(lista.find(volante_estilo) + 1) % lista.size()]
	_montar_volante(nome)
	return nome


func driver_eye() -> Vector3:
	return model_root.get_global_transform_interpolated() * (model_offset + DRIVER_EYE)


## ponto do modelo do jogo -> frame do corpo no Godot (física, câmera)
func corpo(p: Vector3) -> Vector3:
	return (p + model_offset) * ESPELHO


## frame do corpo no Godot -> ponto do modelo do jogo
func jogo(q: Vector3) -> Vector3:
	return q * ESPELHO - model_offset


# câmera de primeira pessoa (não existe no jogo; é do remake). O olho fica
# centralizado atrás do volante de cada carro (pecas.json, tools/volante.py):
# FP_UP acima e FP_BACK atrás do centro do aro. Sem volante, usa o banco
# (ponto ARSE + EYE_FROM_ARSE, medido no Renegade).
# Calibrado pelos prints dos 12 carros contra a referência do Matheus (cockpit
# do Dirt Rally 2.0: horizonte perto do meio, volante cortado embaixo, muita
# estrada pelo para-brisa)
# Os valores abaixo são o padrão; cada carro tem os seus em main.gd VEHICLES "fp".
var FP_FOV := 65.0            # graus na vertical (KEEP_HEIGHT), igual em todos
var FP_PITCH := 0.10          # quanto olha pra baixo (componente -y da direção, ~6°)
var FP_NEAR := 0.05
var FP_UP := 0.35             # olho acima do centro do volante (m)
var FP_BACK := 0.50           # olho atrás do centro do volante (m)
var FP_VOLANTE := true        # olho pelo volante (false = pelo banco)


## posição do olho no frame do modelo (chame de novo se mudar FP_*)
func update_eye() -> void:
	var vol: Dictionary = pecas.get("volante", {})
	if FP_VOLANTE and vol.has("centro"):
		var c := Vector3(vol.centro[0], vol.centro[1], vol.centro[2])
		var e := Vector3(vol.eixo[0], vol.eixo[1], vol.eixo[2]).normalized() if vol.has("eixo") else Vector3.ZERO
		DRIVER_EYE = c + e * avanco_volante() + Vector3(0.0, FP_UP, -FP_BACK)
	elif points.has("ARSE"):
		DRIVER_EYE = points["ARSE"] + EYE_FROM_ARSE


## transform da câmera de primeira pessoa (mundo, interpolado)
func first_person_xf() -> Transform3D:
	var eye: Vector3 = driver_eye()
	var b: Basis = get_global_transform_interpolated().basis
	var turn: float = steer / MAX_STEER
	var look_dir: Vector3 = (b.z + b.x * turn * 0.25 - b.y * FP_PITCH).normalized()
	return Transform3D(Basis.looking_at(look_dir, b.y), eye)


func flip_model() -> void:
	model_root.rotation.y = PI - model_root.rotation.y


func forward() -> Vector3:
	return global_transform.basis.z


func reset_to(pos: Vector3, yaw: float) -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	reset_physics_interpolation()   # teleporte: não interpolar do lugar antigo
	pos_ant = pos
	_v_antes = Vector3.ZERO         # o contato do lugar antigo não vira batida
	_w_antes = Vector3.ZERO
	reset_drivetrain()


func reset_drivetrain() -> void:
	drive_slip = 0.0
	v_ref = 0.0
	preso = false
	preso_t = 0.0
	for w in wheels:
		w.slip = 0.0
		w.sr = 0.0
		w.omega = 0.0
		w.abs = false
	gear = 1
	shift_to = 1
	rpm = P.get("idle", 1000.0)
	clutch = 0.0
	cstate = 0
	shift_flag = false
	shift_timer = 0.0
	lim_k = 1.0
	eng_torque = 0.0
	clutch_t = 0.0
	want_rev = false
	limiter = false
	throttle = 0.0
	brake_in = 0.0
	steer_cx = 0.0
	thr_cx = 0.0
	brk_cx = 0.0
	rev_timer = 0.0
	ar_libera = false
	emb_in = 0.0
	ps_estado = 0
	ps_qtd = 0.0
	ps_esc = 0.0
	ps_emb_ant = 0.0
	rtc_patinou = false


func gear_label() -> String:
	if shift_to != gear:
		return "-"
	if gear == -1:
		return "R"
	if gear == 0:
		return "N"
	return str(gear)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_M:
				manual = not manual
			KEY_P:
				use_ported = not use_ported
			KEY_L:
				lateral_game = not lateral_game
			KEY_E, KEY_PAGEUP:
				if manual:
					if gear == -1:
						want_rev = false
						_start_shift(1)
					elif gear < gears.size() - 1:
						_start_shift(gear + 1)
			KEY_Q, KEY_PAGEDOWN:
				if manual:
					if gear > 1:
						_start_shift(gear - 1)
					elif gear == 1:
						want_rev = true       # no jogo, abaixo da 1ª vem a ré
						_start_shift(-1)


# ------------------------------------------------------------------ física
func _physics_process(dt: float) -> void:
	_batida_passo()
	# ---- comandos
	var thr_raw := 0.0
	var brk_raw := 0.0
	var st_raw := 0.0
	var emb_btn := 0.0
	if test_input != null:
		thr_raw = test_input.get("thr", 0.0)
		brk_raw = test_input.get("brk", 0.0)
		st_raw = test_input.get("steer", 0.0)
		emb_btn = test_input.get("emb", 1.0 if test_input.get("hb", false) else 0.0)
	else:
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
			thr_raw = 1.0
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
			brk_raw = 1.0
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
			st_raw += 1.0
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
			st_raw -= 1.0
		emb_btn = 1.0 if Input.is_physical_key_pressed(KEY_SPACE) else 0.0
		if Input.get_connected_joypads().size() > 0:
			thr_raw = maxf(thr_raw, Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT))
			brk_raw = maxf(brk_raw, Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT))
			var ax := -Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
			if absf(ax) > 0.12:
				st_raw = ax
		# botão da embreagem / Clutch Turn no A do controle (no PS2 é o R1;
		# escolha do Matheus)
		if Input.is_joy_button_pressed(0, JOY_BUTTON_A):
			emb_btn = 1.0

	var b := global_transform.basis
	var up := b.y
	var fwd_body := b.z
	var v_body_f := linear_velocity.dot(fwd_body)

	if not manual:
		_pedais_auto(dt, v_body_f, thr_raw, brk_raw)
		thr_raw = thr_cx
		brk_raw = brk_cx
	# manual (nosso): segurando freio parado engata a ré; na ré os pedais se invertem
	elif want_rev:
		if thr_raw > 0.1 and v_body_f > -0.5:
			want_rev = false
			if manual:
				_start_shift(1)
		else:
			var t := thr_raw
			thr_raw = brk_raw
			brk_raw = t
	elif brk_raw > 0.5 and thr_raw < 0.1 and absf(v_body_f) < 0.6:
		reverse_hold += dt
		if reverse_hold > 0.25:
			want_rev = true
			if manual:
				_start_shift(-1)
			reverse_hold = 0.0
	else:
		reverse_hold = 0.0
	thr_cx = thr_raw
	brk_cx = brk_raw

	throttle = move_toward(throttle, thr_raw, dt * (P.thr_up if thr_raw > throttle else P.thr_down))
	brake_in = move_toward(brake_in, brk_raw, dt * (P.brk_up if brk_raw > brake_in else P.brk_down))
	emb_in = move_toward(emb_in, emb_btn, dt * (P.emb_up if emb_btn > emb_in else P.emb_down))
	# 0x241220: direção. Abrindo do mesmo lado sobe na taxa de subida, que com
	# damp_increase_rate vira (1 - s²) x taxa (o volante chega no fim devagar,
	# como tanh: 0.77 em 0.17 s, 0.95 em 0.3 s); voltando pro centro, taxa de
	# descida; passando pro outro lado, taxa oposta. (Normalised_rate_vs_speed
	# é 1 em todas as velocidades nos buggies.)
	var st_rate: float = P.st_down
	if (st_raw > steer and st_raw > 0.0) or (st_raw < steer and st_raw < 0.0):
		if steer * st_raw >= 0.0:
			st_rate = P.st_up * (1.0 - steer * steer) if P.st_damp != 0.0 else P.st_up
		else:
			st_rate = P.st_opp
	steer = move_toward(steer, st_raw, dt * st_rate)
	steer_cx = st_raw

	# ---- suspensão portada (0x248768 contato, 0x248a80 mola, 0x2484c8 roda)
	# Cada roda tem curso x e velocidade v próprios. A roda só "pega" no chão se
	# na posição atual dela ela encosta; aí o curso sobe até a superfície, a
	# velocidade vem do carro no ponto da roda e a força sai ao longo da normal
	# do chão, no ponto de fixação da roda.
	# Ordem do jogo no passo: integra (0x2484c8) -> contato -> mola -> pneus.
	# Assim o x que sobra no fim do passo (o da RAM, W+0xe8, e o desenhado) é
	# o do contato. Integrando no fim, como o remake fazia até out/2026, o x
	# guardado ficava f/m·dt² mais baixo (1 a 4 cm parado; tests/teste_curso.gd).
	# A física é a mesma: o ciclo de operações não muda.
	_integra_rodas(dt)
	var space := get_world_3d().direct_space_state
	var com_w := global_transform * center_of_mass
	grounded = 0
	var n_sum := Vector3.ZERO
	var rear_g := 0
	var h_sum := 0.0
	var corr := Vector3.ZERO                # correção de posição (batente), 0x23f6c0
	var ignorar: Array = objetos.ignorar_roda() if objetos else []
	for w in wheels:
		var attach: Vector3 = global_transform * Vector3(w.px, w.y0, w.pz)
		var top: Vector3 = global_transform * Vector3(w.px, w.y0 + w.max, w.pz)
		var reach: float = (w.max - w.min) + w.r + 0.05
		var q := PhysicsRayQueryParameters3D.create(top, top - up * reach)
		q.exclude = [get_rid()] + ignorar
		var hit := space.intersect_ray(q)
		# roda na cerca (0x154088 -> 0x153390): quebrou, o raio passa por ela
		if objetos and not hit.is_empty() and objetos.roda_na_cerca(hit.collider, hit.position, hit.normal):
			q.exclude = q.exclude + [hit.rid]
			hit = space.intersect_ray(q)
		w.hit = false
		var pen := 0.0
		if not hit.is_empty():
			var hn0: Vector3 = hit.normal
			# distância do ponto de fixação até o chão, e quanto a roda (no
			# curso atual) entra nele
			var d0: float = top.distance_to(hit.position) - w.max
			pen = (w.r - w.x) - d0
			w.hit = pen > 0.0 and hn0.dot(up) >= w.cos_max
		if not w.hit:
			w.f = 0.0
			continue
		var hp: Vector3 = hit.position
		var hn: Vector3 = hit.normal
		w.point = hp
		w.normal = hn
		if terrain:
			w.mat = terrain.material_at(hp.x, hp.z)
			w.mu = terrain.atrito(w.mat, pneu)
			w.amort = terrain.amortecimento(w.mat)
		grounded += 1
		n_sum += hn
		if not w.front:
			rear_g += 1
		h_sum += (com_w - hp).dot(up)
		w.x += pen
		if w.x > w.max:
			# batente: o jogo empurra o carro pra fora, sem mexer na velocidade
			corr = _add_corr(corr, hn * (w.x - w.max))
			w.x = w.max
		var vp: Vector3 = linear_velocity + angular_velocity.cross(attach - com_w)
		w.v = clampf(-hn.dot(vp) * hn.dot(up), -w.vmax, w.vmax)
		var f_s: float = _spring(w, w.x) + _damper(w, w.v)
		w.f = f_s
		apply_force(hn * f_s, attach - global_position)
		# roda em cima de corpo solto (fardo, peça da cerca): a reação vai
		# nele, senão ele vira rampa fixa (no jogo é contato entre os dois)
		if hit.collider is RigidBody3D and f_s > 0.0:
			(hit.collider as RigidBody3D).sleeping = false
			(hit.collider as RigidBody3D).apply_force(-hn * f_s, hp - (hit.collider as RigidBody3D).global_position)

	_passo_esferas_rodas(space, up)
	_material_medio()
	var ground_n := up if grounded == 0 else n_sum.normalized()
	var fwd := (fwd_body - ground_n * fwd_body.dot(ground_n)).normalized()
	var left := ground_n.cross(fwd)
	var v := linear_velocity
	var v_f := v.dot(fwd)
	var spd := v.length()
	if grounded > 0:
		spd_ground = (v - ground_n * v.dot(ground_n)).length()   # no ar fica o último

	# ---- motor e câmbio
	var driven_g := rear_g if REAR_DRIVE else grounded
	var drive := _drivetrain(dt, v_f, driven_g > 0, emb_in > 0.1)   # 0x20c558: embreagem > 0.1 abre
	_razao_patinada(v_f)

	var f_fwd := 0.0                        # forças das rodas pra frente (0x5c8) + atrito interno
	if grounded > 0:
		air_time = 0.0
		air_lat_state = 0
		air_lat_scale = 1.0
		gravity_scale = 1.0
		if use_ported:
			f_fwd = _tires(dt, v, fwd, left, ground_n, com_w, h_sum / grounded, drive)
		else:
			_tires_legacy(dt, v, fwd, left, ground_n, com_w, h_sum / grounded, drive, false)
		# 0x20e160: no chão o jogo anula a parte da gravidade que puxa o carro
		# de lado num barranco, aplicada na altura do chão (vira rolagem)
		var g_side: float = mass * G * Vector3.DOWN.dot(left)
		apply_force(-left * g_side, com_w - ground_n * (h_sum / grounded) - global_position)
		# 0x2100a0 anti-pitch: passou de ~5° de arfagem em relação ao chão,
		# acelera de volta (cheio a ~10°)
		var s_p: float = -up.dot(fwd)
		if P.ap_acc != 0.0 and absf(s_p) > P.ap_th:
			var a_p: float = P.ap_acc
			if absf(s_p) < P.ap_max:
				a_p *= (absf(s_p) - P.ap_th) / (P.ap_max - P.ap_th)
			apply_torque(b.x * inertia.x * a_p * signf(s_p))
	else:
		# no ar (0x20e160 gravidade, 0x2100a0 torque de arfagem, 0x2129c0 controles)
		air_time += dt
		gravity_scale = P.grav_up if v.dot(Vector3.UP) > 0.0 else P.grav_down
		apply_torque(b.x * P.air_pitch_torque)
		var wl := b.transposed() * angular_velocity
		# guinada: só depois de um tempo no ar, proporcional à direção
		if air_time > P.air_yaw_time and steer != 0.0:
			var tgt: float = steer * P.air_yaw_max
			var acc_y: float = steer * P.air_yaw_acc * dt
			if not (signf(wl.y) == signf(tgt) and absf(tgt) < absf(wl.y)):
				if (tgt > 0.0 and wl.y + acc_y > tgt) or (tgt < 0.0 and wl.y + acc_y < tgt):
					acc_y = tgt - wl.y
				apply_torque(b.y * inertia.y * acc_y / dt)
		# empurrão lateral: virando forte no ar, uma força de lado que some em 2 s
		if air_time > P.air_lat_time:
			if air_lat_state == 0:
				if absf(steer) >= P.air_lat_thr:
					air_lat_state = 1 if steer < 0.0 else 2
					air_lat_timer = P.air_lat_tail
			elif air_lat_timer > 0.0:
				air_lat_timer -= dt
				var old_state := air_lat_state
				if steer < 0.0:
					air_lat_state = 1
				elif steer > 0.0:
					air_lat_state = 2
				if old_state != air_lat_state:
					air_lat_scale *= P.air_lat_change
				apply_central_force(left * steer * P.air_lat_force * (air_lat_timer / P.air_lat_tail) * air_lat_scale)
		# arfagem: freando o bico desce; sem acelerar também (mais devagar)
		var tgt_p := 0.0
		var acc_p := 0.0
		if brake_in > 0.0:
			tgt_p = P.air_brk_max
			acc_p = brake_in * P.air_brk_acc * dt
		if throttle == 0.0:
			tgt_p = maxf(tgt_p, P.air_nt_max)
			acc_p = maxf(acc_p, P.air_nt_acc * dt)
		if acc_p != 0.0 and not (signf(wl.x) == signf(tgt_p) and absf(tgt_p) < absf(wl.x)):
			if tgt_p > 0.0 and wl.x > 0.0 and wl.x + acc_p > tgt_p:
				acc_p = tgt_p - wl.x
			apply_torque(b.x * inertia.x * acc_p / dt)

	# resistência angular do jogo (amortece rolagem e arfagem)
	var w_loc := b.transposed() * angular_velocity
	var res_loc: Vector3 = -Vector3(inertia.x * P.ang_res.x * w_loc.x, inertia.y * P.ang_res.y * w_loc.y, inertia.z * P.ang_res.z * w_loc.z)
	apply_torque(b * res_loc)

	_agua_passo()
	# 0x20e5e8: arrasto do ar + do chão, contra a velocidade
	var f_arr := 0.0
	if spd > 1e-6:
		f_arr = _arrasto(spd, dt)
		apply_central_force(-v / spd * f_arr)

	# 0x211e48: velocidade pra frente prevista no fim do passo = a de agora +
	# (forças pra frente) x dt / massa. Com ela o giro da roda no chão fica
	# v_ref x (1 + 0x610) / raio e o 0x600 do passo seguinte sai igual à 0x610
	var f_arr_f: float = f_arr * v_f / spd if spd > 1e-6 else 0.0
	var a_f: float = (f_fwd - f_arr_f) / mass + get_gravity().dot(fwd) * gravity_scale
	v_ref = v_f + a_f * dt
	_giro_rodas(dt, v_f, rear_g)

	if corr != Vector3.ZERO:
		global_position += corr
	pos_ant = global_position
	# 0x20c278: de ré no chão, a velocidade para no limite do jogo
	if grounded > 0 and v_f < -P.rev_limit * MPH:
		linear_velocity -= fwd * (v_f + P.rev_limit * MPH)

	jit_acc += dt
	while jit_acc >= 1.0 / JIT_HZ:
		jit_acc -= 1.0 / JIT_HZ
		_wheel_jitter()
		_vibracao(1.0 / JIT_HZ, v.dot(left), v_f)
		_sujeira_passo()
		_roda_suja_passo(1.0 / JIT_HZ)
		if poeira:
			poeira.passo(1.0 / JIT_HZ, v)
		if pedras:
			pedras.passo(1.0 / JIT_HZ, v)
		if sfx:
			sfx.passo(1.0 / JIT_HZ, v.dot(left), v_f)
	_update_visuals(dt, v_f)


## 0x223e68 (do update do veículo 0x203930, um por quadro = 50 Hz no PAL):
## com roda no chão (corpo+0x8a8), piloto no carro e |v| no plano do chão
## (0x440) >= 0.5, o nível sobe min(|v|, 15)·k·5e-5, k = maior WheelDirtRate
## (até 1) dos materiais das rodas (veículo+0xa88; 0.2 até no asfalto, 0.3 na
## terra úmida). Não tem dt: o passo é fixo. Vai até 1 e só zera quando o carro
## reinicia (0x223db0); a água não limpa a carroceria no jogo, só a cor da
## roda (0x224418, não portada). Confere com 2 save states: tests/teste_derrapagem.gd.
## 0x215140: maior velocidade na normal dos contatos do casco no último passo,
## com a velocidade do ponto de antes desse passo (_v_antes, _w_antes)
func _batida_passo() -> void:
	batida = 0.0
	var st := PhysicsServer3D.body_get_direct_state(get_rid())
	if st:
		var com := global_transform * center_of_mass
		for i in st.get_contact_count():
			var vp := _v_antes + _w_antes.cross(st.get_contact_local_position(i) - com)
			batida = maxf(batida, absf(vp.dot(st.get_contact_local_normal(i))))
	_v_antes = linear_velocity
	_w_antes = angular_velocity


func _sujeira_passo() -> void:
	if not SUJEIRA or grounded == 0 or spd_ground < 0.5 or terrain == null:
		return
	var k := 0.0
	for w in wheels:
		if w.mat >= 0:
			k = maxf(k, minf(terrain.taxa_sujeira(w.mat), 1.0))
	sujeira_nivel = clampf(sujeira_nivel + minf(spd_ground, 15.0) * k * 5e-5, 0.0, 1.0)


## 0x224418 + 0x2242d0 (do 0x203930, depois da sujeira): com roda no chão e
## material embaixo da FL (veículo+0xa88[0]), quando o material muda a cor
## parte da de agora pro DustColour dele (alfa = WheelDirtAlpha; com alfa 0
## só o alfa cai). t sobe giro da FL (W+0x48)·dt·0.002·WheelDirtRate
## suavizada (0.95/0.05), x 10·patinada da RL (0x604) se passar de 1. Na água
## (veículo+0xae8) o alvo é o registro DAT_007f4bf8+0x20 (AGUA_REG). Confere com a RAM: tests/teste_derrapagem.gd.
func _roda_suja_passo(dt: float) -> void:
	if not SUJEIRA or grounded == 0 or terrain == null:
		return
	var fl: Dictionary = wheels[0]
	# na água o alvo é o registro da água (material -2, como na RAM)
	var mid: int = -2 if agua != null else fl.mat
	if mid != -2 and (fl.mat < 0 or fl.mat >= terrain.materials.size()):
		return
	var p: float = fl.omega * dt * 0.002
	var pat := clampf(wheels[2].sr, 0.0, 1.0)
	if pat * 10.0 > 1.0:
		p *= pat * 10.0
	if mid != roda_mat:
		var m: Dictionary = AGUA_REG if mid == -2 else terrain.materials[mid]
		var alfa := float(m.get("WheelDirtAlpha", 0.0))
		var poeira: Color = m.get("DustColour", Color(0, 0, 0, 0))
		roda_mat = mid
		roda_t = 0.0
		roda_de = roda_cor
		roda_taxa_alvo = float(m.get("WheelDirtRate", 0.0))
		if roda_de.a < 1e-6:
			roda_de = Color(poeira, 0.0)
			roda_para = Color(poeira, alfa)
		elif alfa > 1e-6:
			roda_para = Color(poeira, alfa)
		else:
			roda_para.a = alfa
	roda_taxa = roda_taxa * 0.95 + roda_taxa_alvo * 0.05
	roda_t = clampf(roda_t + p * roda_taxa, 0.0, 1.0)
	roda_cor = roda_de.lerp(roda_para, roda_t)


## recomeço (0x223db0): carro e rodas limpos
func limpar_sujeira() -> void:
	sujeira_nivel = 0.0
	roda_de = Color(0, 0, 0, 0)
	roda_para = Color(0, 0, 0, 0)
	roda_cor = Color(0, 0, 0, 0)
	roda_mat = -1
	roda_t = 0.0
	roda_taxa = 0.0
	roda_taxa_alvo = 0.0


## 0x20e5e8: tamanho do arrasto (N). Em kN = (Air_drag_coefficient x 0.00065 +
## Damping médio (0x788) x Ground_drag_coefficient x 0.01) x v², nunca mais do
## que para o carro neste passo. Água (veículo+0xae8): média d das
## profundidades das rodas (todas, se d > 0) soma Water_drag_coefficient x
## min(d / Water_drag_max_wheel_depth, 1) x 0.01 x v² (0.1 e 0.5 m nos XMLs:
## na poça do RX01, d ~0.17, ~95 N a 60 km/h, quase nada)
func _arrasto(spd: float, dt: float) -> float:
	var k: float = P.air_drag * 0.65 + amort_medio * P.ground_drag * 10.0
	if agua != null:
		var d := 0.0
		for i in mini(wheels.size(), agua_prof.size()):
			d += agua_prof[i]
		d /= float(wheels.size())
		if d > 0.0:
			var c: float = P.water_drag
			if d < P.water_depth:
				c *= d / P.water_depth
			k += c * 10.0
	return minf(k * spd * spd, mass * spd / dt)


## 0x201c20: profundidade de cada roda na água (fundo = centro - raio em y, no
## mundo) pela caixa da água (objetos_rx01.agua_em = 0x1bb098); a água que fica
## é a da última roda, testando antes a do quadro anterior
func _agua_passo() -> void:
	var ant = agua
	agua = null
	if objetos == null or objetos.aguas.is_empty():
		return
	var xf := global_transform
	for i in mini(wheels.size(), agua_prof.size()):
		var w: Dictionary = wheels[i]
		var c: Vector3 = xf * Vector3(w.px, w.y0 + w.x, w.pz)
		var r: Array = objetos.agua_em(c - Vector3(0, w.r, 0), ant)
		agua = r[0]
		agua_prof[i] = r[1]


## 0x20d568: médias do atrito (0x780) e do Damping (0x788) das rodas no chão.
## O jogo soma só as rodas com material e divide por todas as rodas no chão
## (roda sem material, -1, puxa a média pra baixo); sem roda no chão, 0. Sem
## terreno vale o material de reserva em todas.
func _material_medio() -> void:
	mu_medio = 0.0
	amort_medio = 0.0
	if grounded == 0:
		return
	for w in wheels:
		if w.hit and (terrain == null or w.mat >= 0):
			mu_medio += w.mu
			amort_medio += w.amort
	mu_medio /= grounded
	amort_medio /= grounded


## 0x202760: sorteia a tremida das rodas no chão (FL, RL, FR; RR = RL)
func _wheel_jitter() -> void:
	for w in wheels:
		w.jit = 0.0
	jitter_chao = 0.0
	if jit_order.size() != 4:
		return
	var no_chao := 0
	for k in 3:
		var w: Dictionary = wheels[jit_order[k]]
		if not w.hit:
			continue
		var wj: float = terrain.wheel_jitter(w.mat, surface_jitter) if terrain else surface_jitter
		jitter_chao += wj
		no_chao += 1
		var amp := minf(wj * JIT_K * spd_ground, 1.0)
		jit_seed = (jit_seed * 31415821 + 1) & 0x3FFFFFFF
		w.jit = amp * (float(jit_seed) * 0.075 / 1073741824.0 - 0.0375)
	wheels[jit_order[3]].jit = wheels[jit_order[1]].jit
	if no_chao > 0:
		jitter_chao /= no_chao


## A cada passo do jogo (50 Hz): vibração do controle (0x202ab8), pouso
## (0x370df0) e taxa da suspensão do som (0x36fa28/0x370548) -> tremida do
## volante (melhoria nossa, VOLANTE_TREME)
func _vibracao(dt: float, v_l: float, v_f: float) -> void:
	var v := linear_velocity.length()       # corpo+0xe0
	vibracao = 0.0
	if grounded > 0:                        # corpo+0x8a8: rodas no chão
		var trava := false
		var pat := 0.0
		for w in wheels:
			if w.sr < -0.95:                    # 0x600: roda travada
				trava = true
			if w.omega > 3.14:                  # W+0x48: só roda girando
				pat = maxf(pat, clampf(w.sr, 0.0, 1.0))
		var base := 1.5 * absf(v_l)
		if v < 8.938889 and pat > 0.1:
			base += 15.0
		if trava:
			base += v * 0.33561218
		vibracao = base * randf_range(0.1, 0.9)
		if randf() < 0.1:
			vibracao += v * 0.25
		vibracao *= 0.07
	# pouso: o som conta o tempo com nenhuma roda no chão e toca ao voltar
	pouso = 0.0
	if grounded == 0:
		ar_som += dt
	else:
		if ar_som > 0.1:
			pouso = 0.5 + 0.5 * minf(1.0, ar_som)
		ar_som = 0.0
	# suspensão: por roda (FL, RL) s = clamp(curso x SuspensionScale, 0, 1) e
	# a taxa ds/dt (0 no ar); o dono filtra 0.4 x anterior + 0.1 x média
	var media := 0.0
	if jit_order.size() == 4:
		for k in 2:
			var w: Dictionary = wheels[jit_order[k]]
			var d := 0.0
			if w.hit:
				var s := clampf(w.x * SUSP_ESCALA, 0.0, 1.0)
				d = (s - _susp_ant[k]) / dt
				_susp_ant[k] = s
			else:
				_susp_ant[k] = 0.0
			media += d * 0.5
	susp_taxa = clampf(0.4 * susp_taxa + 0.1 * media, -1.0, 1.0)
	var tranco := pouso
	if absf(v_f) >= SUSP_VEL:
		for k in 2:
			var lim: float = [SUSP_PEQUENA, SUSP_GRANDE][k]
			var acima := susp_taxa > lim
			if acima and not _susp_acima[k]:
				tranco = maxf(tranco, 0.4 if k == 0 else 1.0)
			_susp_acima[k] = acima
	else:
		_susp_acima = [false, false]
	if not (VOLANTE_TREME and _tem("volante_treme")):
		return
	pancada = maxf(pancada * exp(-dt / PANCADA_SOLTA), tranco)
	# alvo do giro: sorteio pela vibração, tranco com sinal sorteado, e a
	# diferença de curso das rodas da frente (uma batendo e a outra não)
	var terra := 0.0
	if jit_order.size() == 4:
		terra = (wheels[jit_order[0]].jit - wheels[jit_order[2]].jit) * TREME_TERRA
	_treme_alvo = deg_to_rad(TREME_GRAUS * vibracao * randf_range(-1.0, 1.0)
		+ TREME_PANCADA_GRAUS * pancada * (1.0 if randf() < 0.5 else -1.0) + terra)


# ------------------------------------------------------------------ pneus
## Parte 1 portada do executável do jogo. Ordem igual à do jogo:
##   0x20ede8  curvatura pedida pela direção (com subesterço)
##   0x20e8d8  força de tração por roda
##   0x20eb98  força de freio por roda (com divisão frente/trás)
##   0x20efa0  derrapagem: força lateral total + torque de guinada, divididos
##             entre eixo dianteiro e traseiro
##   0x2101e0  elipse de atrito por roda, com a aderência que encolhe quando
##             a roda satura e volta quando ela para de saturar
## Unidades do jogo: mph (x 0.44694445 = 1609/3600) e graus.
const MPH_G := 0.44694445
const DEG := 0.017453294

## 0x211b58: altura da força lateral pela inclinação. s = seno da inclinação
## de lado em relação ao chão (|cima do carro (corpo+0xc0) · lateral do chão
## (corpo+0x3e0)|): Lateral_scale_std até o limiar, cai em linha reta até o
## Lateral_scale_at_maximum_roll no máximo. Nos XMLs (buggy e truck) vai de
## 0.09 a 0 entre 3° e 8°: inclinado, a força lateral para de tombar o carro.
## Até out/2026 o remake usava sempre o std (capotava mais que o jogo)
func _h_lat(left: Vector3) -> float:
	var s := absf(global_transform.basis.y.dot(left))
	if s > P.h_lat_s1:
		return P.h_lat_roll
	if s > P.h_lat_s0:
		return P.h_lat + (s - P.h_lat_s0) / (P.h_lat_s1 - P.h_lat_s0) * (P.h_lat_roll - P.h_lat)
	return P.h_lat


func _tires(dt: float, v: Vector3, fwd: Vector3, left: Vector3, n: Vector3, com_w: Vector3,
		h: float, drive: float) -> float:
	var v_f := v.dot(fwd)                   # 0x418
	var v_l := v.dot(left)                  # 0x410 (+ = esquerda)
	var v_p := sqrt(v_f * v_f + v_l * v_l)  # 0x440 velocidade no plano do chão
	var mph := v_p / MPH_G
	var mu := mu_medio                      # 0x780 (_material_medio)
	var yaw := angular_velocity.dot(n)      # + = virando pra esquerda
	var sgn_v := -1.0 if v_f < 0.0 else 1.0
	stf_blend = 0.0

	# ângulo de derrapagem atual (0x6c0): direção da velocidade em relação ao bico
	sideslip = asin(clampf(v_l / v_p, -1.0, 1.0)) if v_p >= 0.316 else 0.0

	# ---- 0x20ede8: curvatura. Subesterço entra como U * v² * 0.001
	var delta: float = steer * VehicleData.sample(steer_curve, mph) * DEG
	var kappa: float = delta / ((P.axle_f - P.axle_r) + v_p * v_p * P.understeer_raw * 0.001)
	if absf(v_f) < 0.223472:
		kappa *= absf(v_f) / 0.223472

	# rodas no chão por eixo
	var nf := 0
	var nr := 0
	for w in wheels:
		w.fx = 0.0
		w.fz = 0.0
		if w.hit:
			if w.front:
				nf += 1
			else:
				nr += 1

	# O jogo divide as forças pelo número FIXO de rodas de cada eixo (0x3a0,
	# 0x3a4, 0x3a8), não pelas que estão no chão. Tração e freio só vão pras
	# rodas no chão (a parte da roda no ar some); a força da derrapagem vai pras
	# 4 rodas sempre, no chão ou não.
	var nf_s := 0
	var nr_s := 0
	for w in wheels:
		if w.front:
			nf_s += 1
		else:
			nr_s += 1

	# ---- 0x20e8d8: tração (só rodas motrizes no chão)
	var n_drive := nr_s if REAR_DRIVE else nf_s + nr_s
	if n_drive > 0:
		for w in wheels:
			if w.hit and (not w.front or not REAR_DRIVE):
				w.fz += drive / n_drive

	# ---- 0x20eb98: freio. Desaceleração máxima (mph/s) x escala do chão,
	# nunca mais do que o necessário pra parar neste passo. "Parar" é pela
	# velocidade PREVISTA (0x211e48): a de agora + (tração já somada nas rodas
	# + gravidade e arrasto do 0x1a0) x dt / massa. Assim o freio segura o
	# carro parado contra a tração (o freio automático da largada).
	var brk := brake_in                     # só o pedal (0x390): o jogo não tem freio de mão
	if brk > 0.0 and (nf + nr) > 0:
		var dmax: float = brk * MPH_G * P.brake_decel * VehicleData.triple(P.brake_fscale, mu)
		var f_prev: float = mass * get_gravity().dot(fwd) * gravity_scale
		var spd := v.length()
		if spd > 1e-6:
			f_prev -= _arrasto(spd, dt) * v_f / spd
		for w in wheels:
			f_prev += w.fz
		var v_prev := v_f + f_prev * dt / mass
		var dec: float = -v_prev / dt if absf(v_prev) < dmax * dt else dmax * -signf(v_prev)
		var dec_front: float = P.front_bias * dec
		for w in wheels:
			if not w.hit:
				w.abs = false
				continue
			# o ABS é do pedal (0x390) e lê a patinada medida (0x600)
			if P.abs_on:
				if w.sr < P.abs_eng:
					w.abs = true
				elif w.sr >= P.abs_dis:
					w.abs = false
			if w.abs:
				continue                    # ABS: sem freio nesta roda agora
			if w.front:
				w.fz += mass * dec_front / nf_s
			else:
				w.fz += mass * (dec - dec_front) / nr_s

	# ---- 0x20efa0: derrapagem
	rtc_patinou = false
	var f_cent: float = mass * v_p * v_p * kappa          # força centrípeta pedida
	var ss_deg := absf(sideslip) / DEG
	# alvo de derrapagem: acima de Speed_for_zero_sideslip o bico aponta pra dentro
	# (proporcional à direção); abaixo disso é a geometria do eixo traseiro
	var target := 0.0
	if mph > P.ss_full:
		target = P.ss_max * DEG * -steer
	elif mph > P.ss_zero:
		target = (mph - P.ss_zero) / (P.ss_full - P.ss_zero) * P.ss_max * DEG * -steer
	else:
		if v_p > 1e-6:
			target = asin(clampf(absf(P.axle_r) * kappa, -1.0, 1.0))
		target *= 1.0 - mph / P.ss_zero
		if v_f < 0.0:
			target = -target
	if mph < 5.0:
		target *= mph / 5.0
	var err := target - sideslip
	var w_err := sgn_v * v_p * kappa - yaw                 # falta de giro pra seguir a curva
	var low: bool = mph <= P.ss_zero
	var f_lat := 0.0
	var torque := 0.0
	var f_fwd := 0.0
	# forças externas no plano (gravidade na rampa + tração/freio já somados)
	var g_vec := Vector3.DOWN * 9.81 * gravity_scale * mass
	var sum_x: float = g_vec.dot(left)
	var sum_z: float = g_vec.dot(fwd)
	for w in wheels:
		sum_z += w.fz

	if sideslip * target >= 0.0 or low:
		if absf(sideslip) < absf(target):
			# A) derrapagem crescendo até o alvo
			f_lat = f_cent
			var path := 0.0
			if v_p > 1e-6:
				path = sgn_v * ((v_f * (f_cent + sum_x) - v_l * sum_z) / mass / (v_p * v_p) - yaw)
			var rate: float = VehicleData.fcurve_eval(P.yaw_inc, mu, mph) * DEG
			var acc: float = rate * signf(err) * sgn_v
			var err_deg := absf(err) / DEG
			if signf(path) == signf(err) and err_deg < P.tail_off:
				# chegando no alvo: rampa em cosseno (Increase_tail_off_threshold)
				acc *= (cos((P.tail_off - err_deg) / P.tail_off * PI) + 1.0) * 0.5
				# DAT_00550654 = 1: só com a direção crua e a suavizada do mesmo
				# lado (DAT_00550658 = 10°)
				if steer * steer_cx > 0.0:
					var k := maxf((10.0 - err_deg) / 10.0, 0.0)
					acc = (1.0 - k) * acc + k * (-w_err / dt)
			var step := -acc * dt
			if low:
				var s1 := signf(step + yaw)
				var s2 := signf(steer * sgn_v)
				if s1 == -s2:
					step = w_err
					if absf(yaw) >= 0.5 * DEG:
						step = -0.25 * yaw
			var cap: float = P.yaw_acc * dt
			step = clampf(step, -cap, cap)
			torque = inertia.y * step / dt
		else:
			# B) passou do alvo: segura a velocidade lateral no ângulo alvo
			var corte := _corte_recuperacao(dt, v_f, v_p, yaw)
			var decel: float = VehicleData.triple(P.side_std, mu) * MPH_G
			var vt := tan(target) * absf(v_f)
			var a: float = (vt - v_l) / dt if absf(vt - v_l) < decel * dt else decel * -signf(v_l)
			var f_side := mass * a
			f_fwd = _side_to_fwd(f_side, ss_deg)
			f_lat = f_cent + f_side
			var lim: float = dt * lerpf(VehicleData.fcurve_eval(P.yaw_dec_zero, mu, mph),
				VehicleData.fcurve_eval(P.yaw_dec_full, mu, mph), throttle) * DEG
			torque = inertia.y * clampf(w_err, -lim, lim) / dt
			torque *= 1.0 - corte
	else:
		# C) derrapando pro lado contrário (contra-esterço)
		var fc := f_cent
		fc = 0.0 if ss_deg > 5.0 else fc * (5.0 - ss_deg) / 5.0
		var decel: float = VehicleData.triple(P.side_cs, mu) * MPH_G
		var vv := v_l + fc / mass * dt
		var a: float = -vv / dt if absf(vv) < decel * dt else decel * -signf(vv)
		var f_side := mass * a
		f_fwd = _side_to_fwd(f_side, ss_deg)
		f_lat = fc + f_side
		var rate: float = signf(err) * VehicleData.fcurve_eval(P.yaw_dec_cs, mu, mph) * DEG
		var s := 1.0
		if ss_deg < P.cs_scale_ss:
			s = (ss_deg / P.cs_scale_ss) * (ss_deg / P.cs_scale_ss)
		s *= throttle
		var cap: float = P.yaw_acc * ((1.0 - s) + s * P.cs_scale)
		rate = clampf(rate, -cap, cap)
		if v_f < 0.0:
			rate = -rate
		torque = inertia.y * -rate
		torque *= 1.0 - _corte_recuperacao(dt, v_f, v_p, yaw)

	# divide força lateral e torque entre os eixos (estática de bicicleta)
	var a_f: float = P.axle_f
	var b_r: float = P.axle_r
	var span := a_f - b_r
	if v_f < 0.0:
		f_fwd = 0.0
	var n_all := nf_s + nr_s
	for w in wheels:
		if w.front:
			w.fx += (-b_r / span) * (f_lat + torque / -b_r) / nf_s
		else:
			w.fx += (a_f / span) * (f_lat - torque / a_f) / nr_s
		w.fz += f_fwd / n_all

	# ---- 0x20cea0 -> 0x214610: powerslide (antes da elipse)
	_powerslide(dt, v_p)

	# ---- 0x2101e0: elipse de atrito por roda
	var lat_dem := 0.0
	var lat_got := 0.0
	for w in wheels:
		var e: Dictionary = P.ell_FrontWheels if w.front else P.ell_RearWheels
		# a elipse usa o atrito da própria roda, no máximo 1 (0x2101e0), e
		# desliga com atrito >= Disabling_friction
		var mu_w: float = minf(w.mu, 1.0)
		var W: float = w.grip * VehicleData.triple(e.w, mu_w) * P.width_scale * 1000.0
		var H: float = w.grip * VehicleData.triple(e.h, mu_w) * P.height_scale * 1000.0
		if w.mu >= P.ell_disable:
			W = INF
			H = INF
		var fx: float = w.fx
		var fz: float = w.fz
		var clamped := false
		if absf(fx) < 0.01:
			if absf(fz) > H:
				w.fz = fz * H / absf(fz)
				clamped = true
		elif absf(fz) < 0.01:
			if absf(fx) > W:
				w.fx = fx * W / absf(fx)
				clamped = true
		else:
			var t := fz / fx
			var lim := 1.0 / sqrt(1.0 / (W * W) + t * t / (H * H))
			if lim < absf(fx):
				var k := lim / absf(fx)
				w.fx = fx * k
				w.fz = fz * k
				clamped = true
		var min_scale: float = VehicleData.triple(e.ms, mu_w)
		if _motriz(w) and (ps_estado == 1 or ps_estado == 2):
			min_scale *= P.ps_ellipse          # powerslide: elipse de trás encolhe mais
		w.sat = clamped
		lat_dem += absf(fx)
		lat_got += absf(w.fx)
		if clamped:
			w.grip = maxf(w.grip - e.shrink * dt, min_scale)
		else:
			w.grip = minf(w.grip + e.recover * dt, 1.0)


	# ---- 0x2101e0: patinada de cada roda (0x610). Roda saturada na elipse:
	# empurrando pra frente, cresce (Growth_rate_during_wheel_spin) até onde o
	# motor consegue girar; freando (força contra o movimento, pedal > 0.1),
	# desce (Growth_rate_during_wheel_lock) até -1 (travada). Roda dentro da
	# elipse: volta pra 0 (Recovery_rate_during_wheel_spin / _lock).
	var lim_slip := -INF                    # sem marcha ou parado: não cresce
	if absf(_ratio(gear)) > 1e-6 and absf(v_f) > 0.5:
		# giro de referência do jogo: o máximo da curva do motor (9000); virando
		# forte abaixo de 40 mph, 95% do limitador
		var ref_rpm: float = drive_curve["max"]
		if absf(steer) > 0.5 and absf(v_f) < 40.0 * MPH:
			ref_rpm = P.lim_on * 0.95
		lim_slip = minf(ref_rpm * RPM2RAD * P.wheel_r / (absf(_ratio(gear)) * absf(v_f)) - 1.0, P.slip_max)
	drive_slip = -INF
	for w in wheels:
		if w.sat:
			var fl: float = w.fz * v_f
			if fl > 1e-6:
				if lim_slip > -INF:
					w.slip = minf(w.slip + P.slip_grow * dt, lim_slip)
			elif fl < -1e-6 and brake_in > 0.1:
				w.slip = maxf(w.slip - P.lock_grow * dt, -1.0)
		elif w.slip < 0.0:
			w.slip = minf(w.slip + P.lock_recover * dt, 0.0)
		elif not rtc_patinou:
			w.slip = maxf(w.slip - P.slip_recover * dt, 0.0)
		if not w.front or not REAR_DRIVE:
			drive_slip = maxf(drive_slip, w.slip)

	# ---- 0x210908: roda travando (pela patinada medida, 0x600). A força da
	# roda (mesmo tamanho) vira contra o deslize do contato: velocidade do
	# corpo com a frente trocada por -v_f * patinada (0x630, 0x20df58)
	if v_p > TRAVA_MPH * MPH_G:
		var v_up := v.dot(n)
		for w in wheels:
			if w.abs:
				continue
			var f := 0.0
			if w.sr < TRAVA_FIM:
				f = 1.0
			elif w.sr < TRAVA_INI:
				f = (w.sr - TRAVA_INI) / (TRAVA_FIM - TRAVA_INI)
			if f <= 0.0:
				continue
			var fv := Vector3(w.fx, 0.0, w.fz)
			var tam := fv.length()
			var desl := Vector3(v_l, v_up, -v_f * w.sr)
			if tam < 1e-6 or desl.length() < 1e-6:
				continue
			var fh := fv / tam
			var contra := -desl.normalized()
			var d := contra
			if f < 1.0:
				d = fh * (1.0 - f) + contra * f
				if d.length() > 1e-6:
					d = d.normalized()
				else:
					d = fh if f < 0.5 else contra
			w.fx = d.x * tam
			w.fz = d.z * tam

	# ---- 0x210ce0: limite da velocidade de derrapagem. Com as forças que
	# sobraram depois da elipse, calcula quão rápido o ângulo de derrapagem vai
	# mudar (curva da trajetória - giro do carro). Se passar do máximo do XML
	# (MaximumRate), o jogo mexe direto no giro do carro. É isso que segura o
	# carro de rodar quando a traseira solta.
	if grounded > 0:
		var sx := 0.0
		var sz := 0.0
		for w in wheels:
			sx += w.fx
			sz += w.fz
		var yaw_now := angular_velocity.dot(n)
		var beta_rate: float = -yaw_now * sgn_v
		if v_p > 1e-6:
			beta_rate = ((v_f * sx - v_l * sz) / mass / (v_p * v_p) - yaw_now) * sgn_v
		# baixa velocidade: o giro não passa de v / distância até a roda da frente
		if v_f > 0.0 and v_p < 30.0 * MPH_G and steer != 0.0 and yaw_now * steer > 0.0:
			var fw: Dictionary = wheels[0] if steer > 0.0 else wheels[1]
			var r_fw := Vector3(fw.px, 0.0, fw.pz) - Vector3(center_of_mass.x, 0.0, center_of_mass.z)
			var dir_loc := Vector3(v_l, 0.0, v_f).normalized()
			if dir_loc.dot(r_fw.normalized()) < 0.8660254:
				var cap_w: float = v_p / r_fw.length()
				if absf(yaw_now) > cap_w:
					angular_velocity += n * (signf(steer) * cap_w - yaw_now)
					yaw_now = signf(steer) * cap_w
		if absf(v_f) > 2.0:
			var ss_d: float = absf(sideslip) / DEG
			var growing: bool = beta_rate * sideslip > 0.0
			var mr: float = VehicleData.fcurve_eval(P.ss_rate_inc if growing else P.ss_rate_dec, mu, ss_d)
			# powerslide: mistura com a curva própria pela quantidade x escala
			var a_ps := ps_qtd * ps_esc
			if a_ps > 0.0 and growing:
				mr = (1.0 - a_ps) * mr + a_ps * VehicleData.sample(ps_rate, ss_d)
			if absf(beta_rate) > mr * DEG:
				var ex: float = beta_rate - signf(beta_rate) * mr * DEG
				if ex * yaw_now > 0.0:
					ex = 0.0
				elif absf(yaw_now) < absf(ex):
					ex = -yaw_now
				if absf(v_f) < 20.0:
					ex *= (absf(v_f) - 2.0) / 18.0
				if ex != 0.0:
					angular_velocity += n * (sgn_v * ex)

	# ---- 0x211b58: aplica as forças de cada roda. O jogo põe a força no meio
	# do eixo dela (na linha do carro), numa altura = soma das alturas do contato
	# das rodas desse eixo (em relação ao CoM) x a escala do XML. É daí que sai a
	# guinada (eixo da frente x eixo de trás) e o quanto o carro afunda/agacha.
	var sum_f := 0.0
	var sum_r := 0.0
	for w in wheels:
		var hy: float = w.y0 + w.x - w.r - center_of_mass.y
		if w.front:
			sum_f += hy
		else:
			sum_r += hy
	var hl: float = stf_blend * P.h_long_stf + (1.0 - stf_blend) * P.h_long
	var h_lat := _h_lat(left)
	var base := com_w - global_position
	var lat_sum := 0.0
	for w in wheels:
		var az: float = P.axle_f if w.front else P.axle_r
		var sy: float = sum_f if w.front else sum_r
		if w.fx != 0.0:
			if lateral_game:
				apply_force(left * w.fx, base + n * (sy * h_lat) + fwd * az)
			else:
				lat_sum += w.fx
		if w.fz != 0.0:
			apply_force(fwd * w.fz, base + n * (sy * hl) + fwd * az)
	if not lateral_game:
		# modo antigo (remendo da parte 1): lateral toda no CoM e a guinada que o
		# jogo pediu aplicada direto, cortada na proporção que a elipse cortou
		var keep := 1.0 if lat_dem < 1.0 else lat_got / lat_dem
		apply_force(left * lat_sum, base + n * (sum_r * h_lat))
		apply_torque(n * torque * keep)

	# atrito interno (só sem acelerar): o carro perde velocidade sozinho
	var f_int := 0.0
	if throttle < 0.05 and absf(v_f) > 0.1:
		# 0x20e5e8: abaixo da velocidade mínima vale a desaceleração mínima
		var k2 := clampf((absf(mph) - P.ifd_lo_speed) / (P.ifd_hi_speed - P.ifd_lo_speed), 0.0, 1.0)
		var dec2: float = lerpf(P.ifd_lo, P.ifd_hi, k2) * MPH
		f_int = -sgn_v * minf(dec2 * mass, mass * absf(v_f) / dt)
		apply_central_force(fwd * f_int)
	# forças pra frente deste passo (0x5c8 das rodas + o resto), pra 0x211e48
	for w in wheels:
		f_int += w.fz
	return f_int


## Modelo anterior (palpites meus), mantido pra comparar com o portado.
## Tecla P alterna entre os dois.
func _tires_legacy(dt: float, v: Vector3, fwd: Vector3, left: Vector3, ground_n: Vector3,
		com_w: Vector3, h: float, drive: float, handbrake: bool) -> void:
	var v_f := v.dot(fwd)
	var v_l := v.dot(left)
	var spd := v.length()
	var spd_mph := spd / MPH
	var front_g := 0
	var rear_g := 0
	for w in wheels:
		if w.hit:
			if w.front:
				front_g += 1
			else:
				rear_g += 1
	var frac_f := front_g * 0.5
	var frac_r := rear_g * 0.5
	var cap_long: float = P.ell_h_f * frac_f + P.ell_h_r * frac_r
	var cap_drive: float = P.ell_h_r * frac_r if REAR_DRIVE else cap_long
	var cap_lat: float = P.ell_w_f * frac_f + P.ell_w_r * frac_r * (P.ps_ellipse * 0.6 if handbrake else 1.0)
	var f_long := clampf(drive, -cap_drive, cap_drive)
	var brk := brake_in if not handbrake else maxf(brake_in, 0.4)
	if brk > 0.0:
		var fb: float = P.brake_decel * MPH * mass * brk
		fb = minf(fb, mass * absf(v_f) / dt)
		f_long -= signf(v_f) * fb
	var f_lat := -mass * v_l / dt
	var lat_max: float = P.legacy_side_decel * mass * (grounded / 4.0)
	f_lat = clampf(f_lat, -lat_max, lat_max)
	var ex := f_long / maxf(cap_long, 1.0)
	var ey := f_lat / maxf(cap_lat, 1.0)
	var e := sqrt(ex * ex + ey * ey)
	if e > 1.0:
		f_long /= e
		f_lat /= e
	var ss_l := atan2(-v_l, absf(v_f)) if spd > 1.0 else 0.0
	sideslip = -ss_l
	var ss := absf(ss_l)
	var stf_min := deg_to_rad(P.side_to_fwd_min)
	var stf_max := deg_to_rad(P.side_to_fwd_max)
	if throttle > 0.0 and ss > stf_min and v_f > 0.0:
		var k := clampf((ss - stf_min) / (stf_max - stf_min), 0.0, 1.0)
		f_long += absf(f_lat) * P.side_to_fwd * k * throttle
	if throttle < 0.05 and absf(v_f) > 0.1:
		var k2 := clampf((spd_mph - P.ifd_lo_speed) / (P.ifd_hi_speed - P.ifd_lo_speed), 0.0, 1.0)
		var dec: float = lerpf(P.ifd_lo, P.ifd_hi, k2) * MPH
		dec *= clampf(spd_mph / P.ifd_lo_speed, 0.3, 1.0)
		f_long -= signf(v_f) * minf(dec * mass, mass * absf(v_f) / dt)
	apply_force(fwd * f_long, com_w - ground_n * h * P.h_long - global_position)
	apply_force(left * f_lat, com_w - ground_n * h * _h_lat(left) - global_position)

	var ang: float = deg_to_rad(VehicleData.sample(steer_curve, spd_mph)) * steer
	var yaw_target: float = v_f * ang / (P.wheelbase + P.understeer * v_f * v_f)
	var yaw_rate := angular_velocity.dot(ground_n)
	var acc_max: float = P.yaw_acc
	if spd > 2.0 and v_f > 0.0:
		var ss_lim: float = deg_to_rad(P.ss_max) * clampf((spd_mph - P.ss_zero) / (P.ss_full - P.ss_zero), 0.0, 1.0)
		var w_path := (f_lat / mass) / maxf(v_f, 1.0)
		var s_deg := rad_to_deg(ss)
		var dir := signf(yaw_target)
		if dir != 0.0:
			var into := ss_l * dir
			var into_deg := rad_to_deg(maxf(into, 0.0))
			var rate: float
			if handbrake:
				rate = deg_to_rad(VehicleData.sample(ps_rate, into_deg) * VehicleData.sample(ps_scale, spd_mph))
			else:
				rate = deg_to_rad(lerpf(VehicleData.sample(rate_inc_min, into_deg), VehicleData.sample(rate_inc_max, into_deg), mu_t)) * lerpf(1.0, 0.65, 0.5)
				if into > ss_lim:
					rate *= clampf(1.0 - (into - ss_lim) / (deg_to_rad(P.tail_off) * 0.65), 0.0, 1.0)
			var allowed := maxf(0.0, w_path * dir + rate)
			yaw_target = dir * minf(absf(yaw_target), allowed)
		if ss > 0.01:
			var sg := signf(ss_l)
			var dec_rate := deg_to_rad(lerpf(VehicleData.sample(rate_dec_min, s_deg), VehicleData.sample(rate_dec_max, s_deg), mu_t))
			if sg * yaw_target < sg * w_path - dec_rate:
				yaw_target = w_path - sg * dec_rate
		var dw0 := yaw_target - yaw_rate
		if signf(dw0) == signf(ss_l) and ss > 0.01:
			acc_max = minf(acc_max, deg_to_rad(lerpf(VehicleData.sample(ss_inc_min, spd_mph), VehicleData.sample(ss_inc_curve, spd_mph), mu_t)))
		elif ss > 0.01:
			var dz := lerpf(VehicleData.sample(ss_dec_zero_min, spd_mph), VehicleData.sample(ss_dec_zero, spd_mph), mu_t)
			var df := lerpf(VehicleData.sample(ss_dec_full_min, spd_mph), VehicleData.sample(ss_dec_full, spd_mph), mu_t)
			acc_max = minf(acc_max, deg_to_rad(lerpf(dz, df, throttle)))
	var step := clampf(yaw_target - yaw_rate, -acc_max * dt, acc_max * dt)
	apply_torque(ground_n * inertia.y * step / dt * (grounded / 4.0))


## 0x214610: powerslide ("Clutch Turn" do treino: "tap ... to initiate a
## clutch turn"). Só com Powerslide/Growth_rate > 0 (todos os buggies).
##  0 nada: virando (direção suavizada != 0), acelerando e a embreagem
##    SOLTANDO (menor que no passo anterior) -> 1;
##  1 crescendo: quantidade += Growth_rate x dt até 1 (-> 2); apertou a
##    embreagem de novo ou soltou o acelerador -> 3;
##  2 ativo: apertou a embreagem de novo -> 0 (a quantidade fica); soltou o
##    acelerador ou contra-esterçou (direção x derrapagem >= 0) -> 3;
##  3 sumindo: quantidade -= Decay_rate x dt até 0 (-> 0).
## Mais de Maximum_air_time no ar zera tudo. Em 1 e 2 a elipse das rodas de
## tração vai pro mínimo dela x Scale_of_min_friction_ellipse_scale. A
## quantidade x Scale_vs_speed (0x748) mistura a curva de taxa de derrapagem
## (0x210ce0). Decay_drive_force_scale e Decay_boost_acceleration (estado 3)
## são 1 e 0 nos buggies: sem efeito, não portados.
func _powerslide(dt: float, v_p: float) -> void:
	if air_time > P.ps_air:
		ps_qtd = 0.0
		ps_estado = 0
	elif ps_estado == 0:
		if absf(steer) > 0.0 and throttle > 0.0 and emb_in < ps_emb_ant:
			ps_estado = 1
	elif ps_estado == 1:
		if ps_emb_ant < emb_in or throttle == 0.0:
			ps_estado = 3
		else:
			ps_qtd += P.ps_growth * dt
			if ps_qtd > 1.0:
				ps_qtd = 1.0
				ps_estado = 2
	elif ps_estado == 2:
		# direção e derrapagem têm o sinal trocado nos dois no remake: o produto é o do jogo
		if ps_emb_ant < emb_in:
			ps_estado = 0
		elif throttle == 0.0 or steer * sideslip >= 0.0:
			ps_estado = 3
	elif ps_estado == 3:
		ps_qtd -= P.ps_decay * dt
		if ps_qtd < 0.0:
			ps_qtd = 0.0
			ps_estado = 0
	ps_esc = VehicleData.sample(ps_scale, v_p / MPH_G)
	ps_emb_ant = emb_in
	if ps_estado == 1 or ps_estado == 2:
		for w in wheels:
			if _motriz(w):
				var e: Dictionary = P.ell_FrontWheels if w.front else P.ell_RearWheels
				w.grip = VehicleData.triple(e.ms, minf(w.mu, 1.0)) * P.ps_ellipse


## 0x2120c0 (Sideslip/RecoveryTorqueCutting): quanto do torque que ENDIREITA
## o carro (modos B e C do 0x20efa0) é cortado, 0 a 1. Com Steering_dependent,
## passou do Threshold_angle (12°) e o volante está pra dentro da curva (sinal
## contrário ao da derrapagem) ou solto, o corte é o acelerador suavizado: no
## fundo, o carro NÃO volta sozinho. Contra-esterçando, o corte cai com o
## volante (1 - |volante|, o Maximum_cut dos buggies é 0). Volante solto e o
## carro girando mais rápido que v / (distância da roda FL ao CoM): rodando,
## sem corte. Com corte > 0.01 a patinada de cada roda sobe (Growth_rate da
## SlipRatio) até Maximum_increased_*_slip_ratio x corte (trás 0.2, frente 0).
func _corte_recuperacao(dt: float, v_f: float, v_p: float, yaw: float) -> float:
	if not P.rtc_on or v_p / MPH_G <= P.ss_zero or v_f <= 0.0:
		return 0.0
	var ang := absf(sideslip) / DEG
	var mph_f := v_f / MPH_G
	var th: float = VehicleData.sample(rtc_th, mph_f)
	var mx: float = VehicleData.sample(rtc_max, mph_f)
	var cut: float = VehicleData.sample(rtc_cut, mph_f)
	if mx - th < 0.1:
		mx = th + 0.1
	var f := 0.0
	if ang > mx:
		f = cut * throttle
	elif ang > th:
		f = (ang - th) / (mx - th) * cut * throttle
	var rodando := false
	if P.rtc_steer and ang > th:
		# direção e derrapagem têm o sinal trocado nos dois no remake: o produto é o do jogo
		if steer * sideslip < 0.0 or absf(steer) < 1e-6:
			if absf(steer) < 1e-6:
				var fl: Dictionary = wheels[jit_order[0]]
				var r := Vector2(fl.px - center_of_mass.x, fl.pz - center_of_mass.z).length()
				rodando = v_p / r < absf(yaw)
			f = throttle
		else:
			f = (f - 1.0) * absf(steer) + 1.0
	if f > 0.01:
		for w in wheels:
			var lim: float = minf((P.rtc_front if w.front else P.rtc_rear) * f, P.slip_max)
			if w.slip > -0.1 and w.slip < lim:
				rtc_patinou = true
				w.slip = minf(w.slip + P.slip_grow * dt, lim)
	return 0.0 if rodando else f


func _side_to_fwd(f_side: float, ss_deg: float) -> float:
	# parte da desaceleração lateral vira aceleração pra frente (com acelerador)
	var frac := 0.0
	if ss_deg > P.side_to_fwd_max:
		frac = 1.0
	elif ss_deg > P.side_to_fwd_min:
		frac = (ss_deg - P.side_to_fwd_min) / (P.side_to_fwd_max - P.side_to_fwd_min)
	if frac <= 0.0:
		return 0.0
	# no powerslide (qualquer estado) vale o Side_deceleration_to_fwd dele
	var k: float = P.side_to_fwd if ps_estado == 0 else P.ps_side_to_fwd
	stf_blend = throttle * frac * k     # 0x474: muda a altura da força longitudinal
	return throttle * absf(f_side) * frac * k



func _engine_torque(r: float, thr: float) -> float:
	return thr * VehicleData.sample(drive_curve, r) * P.drive_scale - VehicleData.sample(fric_curve, r) * P.fric_scale


func _ratio(g: int) -> float:
	if g == -1:
		return P.gear_r * P.final
	if g <= 0:
		return 0.0
	return gears[g] * P.final


func _speed_at(g: int, r: float) -> float:
	return r * RPM2RAD / absf(_ratio(g)) * P.wheel_r


func _start_shift(to: int) -> void:
	# 0x247aa0: pedido de troca (manual). Só aceita sem outra troca em andamento
	if shift_timer > 0.0 or to == gear:
		return
	shift_to = to
	cstate = 2
	shift_flag = true


## 0x202df0: pedais do jogador no AutoManual (corpo+0x2d4 = 3, veículo+0xb14
## ligado), velocidades em mph (x 2.2374146):
##  - pra frente a mais de 1 mph: modo frente (corpo+0x2d8 = 0) e espera
##    de 0.1 s (veículo+0xb2c) pro freio virar ré;
##  - senão: soltar o freio zera a espera; freio apertado gasta a espera e
##    depois engata a ré com o freio virando acelerador; acelerador volta pra
##    frente (de ré a mais de 1 mph ele vira freio até parar);
##  - sem pedal nenhum e |v| < 0.2 mph o jogo segura no freio (1.0). É a
##    barra vermelha cheia na largada: ao acelerar o freio cai a 2/s;
##  - no ar (corpo+0x4e4 > 0) o acelerador fica cortado até ser solto uma vez
##    nesse voo (veículo+0xb30).
func _pedais_auto(dt: float, v_f: float, thr_raw: float, brk_raw: float) -> void:
	var v_mph := v_f / MPH_G
	if v_mph > 1.0:
		want_rev = false
		rev_timer = 0.1
	else:
		if rev_timer > 0.0 and brk_raw == 0.0:
			rev_timer = 0.0
		if brk_raw > 0.0:
			if rev_timer > 0.0:
				rev_timer -= dt
			else:
				want_rev = true
				thr_raw = brk_raw
				brk_raw = 0.0
		elif thr_raw > 0.0:
			if v_mph < -1.0 and want_rev:
				brk_raw = thr_raw
				thr_raw = 0.0
			else:
				want_rev = false
	if thr_raw == 0.0 and brk_raw == 0.0 and linear_velocity.length() / MPH_G < 0.2:
		brk_raw = 1.0
	if air_time == 0.0:
		ar_libera = false
	elif not ar_libera:
		if thr_raw == 0.0:
			ar_libera = true
		else:
			thr_raw = 0.0
	thr_cx = thr_raw
	brk_cx = brk_raw


## Motor e câmbio portados do executável:
##   0x20c558  giro vem das rodas (W+0x48) quando a embreagem está travada,
##             com roda de trás no chão e o carro não está preso; embreagem
##             forçada aberta; durante a troca o acelerador cai junto com ela
##   0x2474a0  câmbio AutoManual (embreagem com 4 estados, troca por velocidade)
##   0x2470c0  câmbio Manual (mesma embreagem, sem troca sozinho)
##   0x20c808  carga que a embreagem põe no motor
##   0x246858  motor: torque = acelerador x limitador x curva - atrito; giro
##             integra pela inércia; limitador é uma rampa (15/s), não corte seco
## Marchas aqui: -1 = ré (0 no jogo), 0 = neutro (6 no jogo), 1..5.
func _drivetrain(dt: float, v_f: float, driven_on_ground: bool, forced_open: bool) -> float:
	var ratio := _ratio(gear)
	# ---- 0x20c558: embreagem forçada aberta (0x31c): botão da embreagem > 0.1; mais de 1 s
	# no ar abaixo do giro de desengate (câmbio+0x90); ou pedal de freio > 0.9
	# com roda de tração travando (0x600 < DAT_0055067c = -0.9)
	var forced := forced_open
	if air_time > 1.0:
		forced = forced or rpm < P.clutch_dis_rpm
	elif brake_in > 0.9:
		for w in wheels:
			if _motriz(w) and w.sr < -0.9:
				forced = true
	# 0x304: giro da roda de tração mais rápida (com sinal), em rpm, e o lado
	# de fora da embreagem
	var w_tr := 0.0
	for w in wheels:
		if _motriz(w) and absf(w_tr) < absf(w.omega):
			w_tr = w.omega
	var out_rpm: float = w_tr / RPM2RAD * ratio

	var integrate := true
	if cstate == 3 and driven_on_ground and not preso:
		rpm = maxf(out_rpm, P.idle)
		integrate = false
	var thr_eng := throttle
	if cstate != 3 and shift_flag:
		thr_eng *= clutch

	# ---- câmbio (usa o torque do motor do passo anterior, como o jogo)
	var ct := _gearbox(dt, v_f, out_rpm, driven_on_ground, forced)

	# ---- 0x20c808 + 0x246858
	var e_load := 0.0 if cstate == 3 else ct
	if rpm > P.lim_on:
		lim_k = maxf(lim_k - P.lim_rate_on * dt, 0.0)
	elif rpm < P.lim_off:
		lim_k = minf(lim_k + P.lim_rate_off * dt, 1.0)
	limiter = lim_k < 0.999
	som_carga = thr_eng * lim_k
	eng_torque = thr_eng * lim_k * VehicleData.sample(drive_curve, rpm) * P.drive_scale \
		- VehicleData.sample(fric_curve, rpm) * P.fric_scale
	if integrate:
		rpm += (eng_torque - e_load) * dt / P.eng_inertia
	if rpm < P.idle:
		rpm = P.idle
	if rpm <= P.idle and eng_torque < 0.0:
		eng_torque = 0.0

	# torque na roda -> força (0x20e8d8), com o corte de velocidade da ré
	var f: float = ct * _ratio(gear) / P.wheel_r
	var v_mph := v_f / MPH
	if v_mph < -P.rev_limit:
		f = 0.0
	elif v_mph < -P.rev_cut:
		f *= (v_mph + P.rev_limit) / (P.rev_limit - P.rev_cut)
	return f


func _motriz(w: Dictionary) -> bool:
	return not w.front or not REAR_DRIVE


## 0x20df58: patinada medida de cada roda (0x600) = giro x raio / v - 1, com v
## a velocidade pra frente do carro (0x418; DAT_00550680 = 0, não usa a do
## ponto da roda). Quase parado (|v| <= 1e-6) vale 0.1 x giro; roda no ar, 0.
func _razao_patinada(v_f: float) -> void:
	for w in wheels:
		if not w.hit:
			w.sr = 0.0
		elif absf(v_f) > 1e-6:
			w.sr = w.omega * w.r / v_f - 1.0
		else:
			w.sr = 0.1 * w.omega


## 0x2113e0: torque em cada roda (W+0x44); 0x2484c8: giro += torque x dt /
## inércia, ângulo += giro x dt.
##  - roda solta no chão: giro = v_ref x (1 + 0x610) / raio;
##  - roda solta no ar: perde max(180°/s², freio / inércia) até parar;
##  - tração com roda de trás no chão (0x3cc): igual à solta no chão, ou, com o
##    carro preso, giro do motor x embreagem / relação;
##  - tração sem roda de trás no chão: embreagem travada, giro do motor /
##    relação; senão motor (embreagem x relação x torque / rodas de tração)
##    contra o freio, sem passar do giro do motor.
## O "torque" do freio aqui é desaceleração x parte do eixo / rodas x raio, sem
## a massa (o jogo divide pela inércia em t·m²; com a inércia em kg·m² entra
## x1000). 0x720 = 1 (RAM, multiplica o motor).
func _giro_rodas(dt: float, v_f: float, rear_g: int) -> void:
	# 0x2113e0: preso. Acelerando (botão da embreagem em 0) a menos de 0,5 m/s e o
	# carro não sai de 3 cm (0.0009 m²) por 0,33 s
	preso = false
	var v_r := v_ref
	if thr_cx > 0.0 and emb_in == 0.0 and absf(v_f) < 0.5:
		if preso_t == 0.0:
			preso_t = dt
			preso_pos = global_position
		elif (global_position - preso_pos).length_squared() < 0.0009:
			preso_t += dt
			if preso_t > 0.33:
				preso = true
				# 0x880: velocidade pelo deslocamento do último passo
				v_r = (global_position - pos_ant).dot(global_transform.basis.z) / dt
		else:
			preso_t = 0.0
	else:
		preso_t = 0.0

	var nf_s := 0
	var nr_s := 0
	var n_tr := 0
	for w in wheels:
		if w.front:
			nf_s += 1
		else:
			nr_s += 1
		if _motriz(w):
			n_tr += 1
	var ratio := _ratio(gear)
	var w_mot := rpm * RPM2RAD / ratio if ratio != 0.0 else 0.0     # giro do motor na roda
	var dmax: float = brake_in * MPH_G * P.brake_decel * VehicleData.triple(P.brake_fscale, mu_medio)
	var d_fr: float = P.front_bias * dmax
	for w in wheels:
		var I: float = w.inercia
		var t_mot := clutch * ratio * eng_torque / n_tr if _motriz(w) else 0.0
		var t_frei: float = (d_fr / nf_s if w.front else (dmax - d_fr) / nr_s) * w.r * 1000.0
		var t: float
		if not _motriz(w):
			if w.hit:
				t = I * (v_r * (1.0 + w.slip) / w.r - w.omega) / dt
			else:
				t = _freio_livre(w, maxf(GIRO_LIVRE, t_frei / I), dt)
		elif rear_g >= 1:
			var alvo: float = v_r * (1.0 + w.slip) / w.r
			if preso:
				alvo = w_mot * clutch
			t = I * (alvo - w.omega) / dt
		elif cstate == 3:
			t = I * (w_mot - w.omega) / dt
		else:
			var s_w := -1.0 if w.omega < 0.0 else 1.0
			var liq: float = t_mot - s_w * t_frei
			if absf(liq) > 1e-6:
				var dw: float = liq * dt / I
				t = liq
				if absf(t_mot) < absf(t_frei):
					if absf(w.omega) < absf(dw):
						t = -I * w.omega / dt                    # o freio para a roda
				elif (-1.0 if w_mot < 0.0 else 1.0) == (-1.0 if dw < 0.0 else 1.0) \
						and absf(w_mot - w.omega) < absf(dw):
					t = I * (w_mot - w.omega) / dt               # não passa do motor
			else:
				t = _freio_livre(w, GIRO_LIVRE, dt)
		# 0x2484c8
		w.omega += t * dt / I
		w.spin = fposmod(w.spin + w.omega * dt, TAU)


## 0x2113e0: roda solta perdendo giro a uma taxa a (rad/s²). Como no jogo,
## perto de parar usa giro / dt com sinal (girando pra trás ela dobra antes
## de parar; pra frente para certinho).
func _freio_livre(w: Dictionary, a: float, dt: float) -> float:
	if absf(w.omega) < a * dt:
		a = w.omega / dt
	return w.inercia * a * -(-1.0 if w.omega < 0.0 else 1.0)


## Devolve o torque que passa pela embreagem (lado do motor).
func _gearbox(dt: float, v_f: float, out_rpm: float, auto_ok: bool, forced: bool) -> float:
	var n_g := gears.size() - 1
	var rev_now := gear == -1
	var t2 := thr_cx * thr_cx              # câmbio+0xc = acelerador cru (0x20c7a8)
	var dis: float = P.clutch_dis_rate
	var eng: float = P.clutch_eng_rate
	var rpm_thr: float = P.clutch_rpm_lo
	var plain := (want_rev if not manual else rev_now)
	if not plain:
		dis *= 1.0 + t2 * (P.clutch_thr_mod - 1.0)
		eng *= 1.0 + t2 * (P.clutch_thr_mod - 1.0)
		rpm_thr = lerpf(P.clutch_rpm_lo, P.clutch_rpm_hi, t2)
	var diff := rpm - out_rpm
	var change_time: float = P.manual_time if manual else P.auto_time

	var open_path := false
	var engage := false
	if not manual:
		# 0x2474a0 (AutoManual)
		if P.clutch_dis_rpm < rpm or gear > 1:
			if absf(v_f) < _down_speed(2) and gear > 1:
				open_path = true
			elif want_rev and gear != -1 and shift_to != -1:
				open_path = true
			elif not want_rev and gear == -1 and shift_to == -1:
				open_path = true
			elif forced:
				open_path = true
			elif shift_to != gear:
				_shift_step(dt, dis, change_time, diff)
			elif rpm > rpm_thr:
				engage = true
			elif cstate == 1 or cstate == 3:
				engage = true
			elif thr_cx < 0.01 and absf(v_f) > 5.0 * MPH:
				engage = true
		else:
			open_path = true
	else:
		# 0x2470c0 (Manual)
		if P.clutch_dis_rpm <= rpm and not forced:
			if shift_to != gear:
				_shift_step(dt, dis, change_time, diff)
			elif rpm > rpm_thr or cstate == 1 or cstate == 3:
				engage = true
		else:
			open_path = true

	if open_path:
		cstate = 2
		clutch = maxf(clutch - dis * dt, 0.0)
		if clutch <= 0.0:
			cstate = 0
			if not forced:
				shift_timer = 0.0
				if manual:
					gear = shift_to
				else:
					gear = -1 if want_rev else 1
					shift_to = gear
			shift_flag = false
	elif engage:
		if clutch < 1.0:
			if cstate != 1:
				slip_sign = diff
			cstate = 1
			clutch = minf(clutch + eng * dt, 1.0)
		if clutch > 0.0 and cstate != 3:
			if absf(diff) < P.clutch_lock_diff or signf(diff) != signf(slip_sign):
				cstate = 3
				clutch = 1.0
				shift_flag = false
		# troca automática por velocidade (só com as rodas de tração no chão)
		if cstate == 3 and not manual and not want_rev and auto_ok and gear >= 1:
			var k: float = 1.0 + thr_cx * (P.up_thr_mod - 1.0)
			if v_f > k * _up_speed(gear) and gear < n_g:
				shift_to = gear + 1
				cstate = 2
				shift_flag = true
			elif gear > 1 and v_f < k * _down_speed(gear):
				shift_to = gear - 1
				cstate = 2
				shift_flag = true

	# torque que a embreagem passa
	if clutch <= 0.0 or gear == 0:
		clutch_t = 0.0
	elif cstate == 3:
		clutch_t = eng_torque
	elif cstate == 2:
		var cap: float = clutch * P.clutch_max
		clutch_t = 0.0 if eng_torque <= 0.0 else minf(cap, eng_torque)
	elif cstate == 1:
		clutch_t = signf(diff) * clutch * P.clutch_max
	return clutch_t


func _shift_step(dt: float, dis: float, change_time: float, diff: float) -> void:
	# embreagem abre; aberta, conta o tempo da troca; aí engata a marcha nova
	if clutch > 0.0:
		clutch -= dis * dt
		if clutch < 0.0:
			clutch = 0.0
			cstate = 0
	else:
		shift_timer += dt
		if shift_timer >= change_time:
			shift_timer = 0.0
			cstate = 1
			slip_sign = diff
			gear = shift_to


## velocidades de troca do jogo (0x246d88), em m/s
func _up_speed(g: int) -> float:
	return P.up_rpm * P.wheel_r * RPM2RAD / (gears[g] * P.final)


func _down_speed(g: int) -> float:
	if g <= 1:
		return 0.0
	if g == 2:
		return maxf(_up_speed(1) * 0.1, _up_speed(1) - P.down_diff[2] * MPH)
	var a := _up_speed(g - 2)
	var b := _up_speed(g - 1)
	return maxf(a + (b - a) * 0.1, b - P.down_diff[g] * MPH)


func _update_visuals(dt: float, _v_f: float) -> void:
	# o visual fica no frame do jogo (espelho): rotação em y troca de sinal
	# (S Ry(a) S = Ry(-a)), em x não. a_jogo = ângulo das rodas no jogo
	var a_jogo: float = -steer * P.vis_steer
	for w in wheels:
		var x: float = clampf(w.x, w.min, w.max) + w.jit   # 0x222078: sem clamp depois
		w.pivot.position = Vector3(w.px, w.y0 + x, w.pz) * ESPELHO
		w.pivot.rotation.y = a_jogo if w.front else 0.0
		w.spin_node.rotation.x = w.spin            # ângulo da roda (W+0x4c, _giro_rodas)
	# direção suavizada do piloto (0x187060: s += min(1/dt, 30)·(direção - s)·dt):
	# é o que move os braços dele no jogo, então o volante anda junto
	if dt > 0.0:
		rider_s = clampf(rider_s + minf(1.0 / dt, 30.0) * (steer - rider_s) * dt, -1.0, 1.0)
	if dt > 0.0:
		treme += (_treme_alvo - treme) * (1.0 - exp(-dt / TREME_SUAVE))
	if sw_pivot and VOLANTE_GIRA and _tem("volante_gira"):
		var giro := -rider_s * SW_TURNS
		if piloto and piloto.no_volante():
			giro = piloto.giro_volante(rider_s)
		sw_pivot.basis = Basis(SW_AXIS.normalized(), giro + treme)
	if piloto:
		piloto.pose(rider_s, treme if VOLANTE_GIRA else 0.0)
	if susp_vis:
		susp_vis.update(a_jogo)
