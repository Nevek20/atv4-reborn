extends RigidBody3D
## Base do carro (carro/car.gd -> carro_montagem.gd -> este): as constantes,
## as variáveis de estado e os ajudantes pequenos que a física e a montagem
## usam. Só declarações: a lógica fica nas camadas de cima.


const VehicleData := preload("res://carro/vehicle_data.gd")
const CarroGlb := preload("res://carro/carro_glb.gd")
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
# melhoria nossa: eixo do volante NOSSO (o do jogo sai). Fireball: o aro do
# modelo é o mais deitado dos trucks (46° acima da horizontal; os outros 14 a
# 36°) e torto ~5° pro lado (x 0.059): com a mão a 65° do topo o pulso dobrava
# 28° / 42° (direita / esquerda) com o volante reto ("braço muito torto",
# Matheus, nov/2026). Reto e a 30° (como Goliath, Chimera e Lazarus): 20° /
# 27° e braço 90% esticado (era 101%); 36° dava 24° / 31°. O banco de lado
# quase não muda (cotovelo esquerdo na porta). VOL_EIXO=x,y,z testa
const VOLANTE_EIXO := {"TRUCK_10": Vector3(0.0, 0.5, -0.866)}
# melhoria nossa: braço mais aberto (cotovelo pelo menos x graus pra fora,
# folga y m da porta). Fireball (nov/2026, "abre um pouco mais o braço, sem
# varar a porta", Matheus): o IK deixava os cotovelos pra baixo (-2°); com 25°
# e 6 cm (manga ~5 cm) eles abrem 25° a 32° com o volante reto, pulso 29°/32°
const BRACO_ABERTO := {"TRUCK_10": Vector2(25.0, 0.06)}
const COLUNA_RAIO := 0.025     # m (coluna nossa)
const COLUNA_MAX := 0.6        # m: até o painel, no máximo
var sw_coluna: MeshInstance3D
const Volantes := preload("res://carro/volantes.gd")
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
# os samples do jogo em assets/sons: tools/sfx_jogo.py). false = sem eles
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
# lasquinhas da batida (porta do jogo: 0x3bbd60, Particle_Debris.bantam na cor
# base da pintura; lascas.gd): o casco batendo no chão ou parede a >= 30 mph
const LASCAS := true
var lascas: Node3D = null
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
# (nov/2026, prints do Matheus) Buccaneer e Herbst TT: o jogo põe a
# ré só na direita, a esquerda é o espelho; no Panther e no TT o ponto do
# jogo fica 6-10 cm atrás da lente (só um canto acendia): vai pro centro dela.
# Shockwave: a lente de freio desce até 1.30 m e o ponto do jogo está em
# 1.53 (raio 15 cm cortava a ponta de baixo): mais um ponto embaixo em cada
const LUZES_NOSSAS := {
	"TRUCK_01": {"REVERSE_LIGHT": [Vector3(0.783, 0.755, -1.938), Vector3(-0.770, 0.755, -1.938)]},
	"TRUCK_02": {"REVERSE_LIGHT": [Vector3(0.94, 1.71, -3.03), Vector3(-0.94, 1.71, -3.03)],
		"BRAKE_LIGHT": [Vector3(-0.957, 1.533, -3.029), Vector3(0.953, 1.529, -3.027),
			Vector3(-0.957, 1.38, -3.0), Vector3(0.953, 1.38, -3.0)]},
	# Panther: a lente da esquerda é a mesma, mas o jogo pinta de âmbar (cor do
	# vértice 0.37, 0.22, 0.04): não é ré, fica só a da direita (no centro)
	"TRUCK_06": {"REVERSE_LIGHT": [Vector3(0.706, 1.696, -2.308)]},
	"TRUCK_08": {"REVERSE_LIGHT": [Vector3(0.615, 2.235, -1.452), Vector3(-0.625, 2.235, -1.452)]},
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
# amortecedor da frente telescópico (melhoria nossa, nov/2026, pedido do
# Matheus; suspension_visual.gd _telescopio): nos trucks com a mola e o
# amortecedor dentro da malha da balança (LeftFrame/RightFrame) o jogo gira
# tudo junto e no curso máximo a ponta sai pelo capô (igual no jogo)
const TELESCOPIO := ["TRUCK_09"]
# balança da frente deslocada só no desenho (melhoria nossa, nov/2026): no
# Fireball a RightFrame e o A_FRAME_RIGHT do jogo estão ~11 cm mais pra fora
# que o espelho da esquerda (pivô x 0.288 x -0.179, malha 0.177..1.072 x
# -0.939..-0.065; as rodas são simétricas, ±1.00) e a ponta da balança sai
# pela face da roda, igual no jogo. Mesmo espelhada, a ponta das duas ainda
# aparecia: o eixo da direção fica em x 0.73 e a ponta vai até 0.94, então
# com o volante virado ela sai do lado do cubo. As 2 vão mais 10 cm pra
# dentro (limpo no volante todo virado pros 2 lados e ainda encosta no
# cubo). Frame do jogo, m (esquerda = x < 0)
const BALANCA_DESLOCA := {"TRUCK_10": {"LeftFrame": Vector3(0.10, 0.0, 0.0),
	"RightFrame": Vector3(-0.209, 0.0, 0.0)}}
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
# textura GEN_DIRT_DIRT em assets/efeitos: tools/fx_jogo.py). false = carro limpo
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
## física em C++ (fisica_cpp/, bin/atv4_fisica.gdextension): motor e câmbio
## por enquanto. null = sem a biblioteca ou ATV4_CPP=0 (tudo no GDScript).
var cpp: RefCounted = null
static var usar_cpp := ClassDB.class_exists("FisicaCarro") and OS.get_environment("ATV4_CPP") != "0"
## a biblioteca carregou? (F2 mostra; F3 liga/desliga o usar_cpp na hora)
static func cpp_carregou() -> bool:
	return ClassDB.class_exists("FisicaCarro")

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
# medidor de CPU por parte do passo (PERF_CARRO=1; tests/medir_cpu.gd imprime)
static var perf_on: bool = OS.has_environment("PERF_CARRO")
static var perf := {}


static func _pf(nome: String, t0: int) -> int:
	var t := Time.get_ticks_usec()
	perf[nome] = perf.get(nome, 0) + (t - t0)
	return t


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
# o contato com o mundo fixo mais forte do passo, pro som da batida (0x36e7a8):
# {vn, r (ponto - centro), mat}; vazio sem contato
var contato_som := {}
var batida_max := 0.0         # testes
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
var som_3d := false           # rival da IA (pista/ia.gd): motor e pneus em som 3D preso no carro
# rival longe da câmera (pista/ia.gd põe a cada passo; NOSSO, só CPU): sem
# braços do piloto nem suspensão visual (longe_vis) e sem o som de pneu e
# suspensão (longe_som: além do alcance do som 3D). A física não muda.
var longe_vis := false
var longe_som := false
var direcao_direta := false   # rival da IA: a direção vai direto (na RAM os rivais têm cru = suavizado)
var _contato_carro := {}      # batida com outro carro neste passo (carro/batida_carros.gd)
var outros_carros: Array = []  # RIDs dos outros carros: as rodas não pisam neles (batida_carros.separar)


## batida com outro carro: entra no som (patch Vehicle) e na tremida da
## câmera do próximo _batida_passo
func contato_carro(vn: float, r: Vector3) -> void:
	if _contato_carro.is_empty() or vn > _contato_carro.vn:
		_contato_carro = {"vn": vn, "r": r, "mat": false}
# largada da corrida (pista/corrida.gd): o jogador acelera com o carro preso
# (embreagem aberta, freio ignorado: segurar o freio parado engataria a ré)
var largada_presa := false
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


## chave do carro nas tabelas por carro: o vehicle_id, menos no bônus (o
## Lazarus usa o id do Jericho, TRUCK_04, pra física e peças)
func chave() -> String:
	return "LAZARUS" if asset_dir.ends_with("truck_bonus") else vehicle_id


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


func forward() -> Vector3:
	return global_transform.basis.z
