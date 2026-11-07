# Mapa do executável (SCES_546.88, PAL)

Endereços virtuais. Dumps decompilados em `re/decomp/*.c` (gerados com o
DecompRefs.java). Unidades do jogo: massa em t, força/torque em kN e kN·m,
velocidades em mph (×0.44704 → m/s) ou m/s conforme o campo; mph = m/s ×
2.2374146 nas contas do exe.

## Carregamento de parâmetros

- `re/decomp/param_map.txt`: cada atributo do XML de física → offset no
  struct de parâmetros (ex.: Mass_non_tuned → +0x1428). Base em 0x2154c4..
- Interpolação "tunada": valor = lerp(non_tuned, fully_tuned, t), com t das
  peças (data/upgrades.xml, efeitos somados por tipo).

## Passo da física (PAL 50 Hz, NTSC 60 Hz)

- O jogo integra uma vez por quadro: 1/50 no PAL (nosso exe), 1/60 no NTSC.
  A física DEPENDE disso. Com a roda patinando em 1ª o giro vem da roda
  (0x20c558) e bate no limitador (Rev_limiter_engage/disengage_rate 15/s),
  enquanto a patinada 0x610 sobe a 3/s e volta a 4/s; o liga-desliga dessas
  rampas depende do passo. Passo menor = corte mais raso = mais força média.
- Conferido com dois vídeos: o Renegade PAL do Matheus (RX01) na 1ª vai de
  30 a 60 km/h em 1.25 s; o remake dá 1.36 s a 50 Hz e 0.92 s a 120 Hz.
  O speedrun do Sphinx (NTSC, mph) bate a 60 Hz em 1.7 mph do começo ao fim
  (a 50 Hz fica até 3.8 mph abaixo; a 120 Hz até 7 acima).
- Save state PAL patinando a 48.7 km/h (1ª): rodas de trás no limite da
  elipse (0x5c8 = 8.007 kN = 8.17 x 0.98; pedido 0x680 = 10.48), 6893 rpm,
  0x600 0.26, 0x610 0.32, limitador 1.0 naquele quadro.
- Save states PAL da largada de fábrica (acelerador no fundo, embreagem já
  travada): patinada 0x610 de trás / rpm = 0.48 / 1379 a 8.6 km/h, 0.48 /
  1568 a 9.8, 1.20 / 4763 a 19.8, 1.38 / 5766 a 22.1. A força na roda
  (0x5c8) bate com o remake na mesma patinada (7.03 kN em 0.48, 6.54 em
  1.38): o que falta é a patinada começar mais cedo. Com os pedais do
  0x202df0 e o câmbio no acelerador cru o remake dá 0.22/0.31/1.07/1.25
  (antes 0.00/0.04/0.76/0.94). Save state a 7.7 km/h: embreagem ABRINDO
  (0x314 = 2, de 1.0 pra 0.6; rpm 1013 < 1050), patinada 0.36, e o
  0x320 (rpm − rpm da roda quando começou a engatar) = 755. Ou seja, o jogo
  também cai abaixo de 1050 a ~3 km/h e reengata (remake: 786), igual ao
  remake. A diferença é que no jogo a embreagem chega a 1.0 até 7.7 km/h
  (remake 0.80): o carro anda mais devagar de 3 a 7.7 km/h. Hipótese: o
  freio automático segura mais no jogo; no remake o ABS solta o freio
  quando a roda para com o carro a ~1e-5 m/s (0x600 = −1) e o carro anda
  de passo em passo. Sobra uns 0.09 s na frente entre 5 e 14 km/h.

## Ficha do carro (tela de opções da corrida)

- **0x1f5e90** monta a ficha a partir dos parâmetros já com as peças
  (0x21d618: para cada slot i, (1-t)·P[0x1350+8i] + t·P[0x1354+8i]; slot 1 =
  Drive_torque -> P+0x58). Power HP = P+0x58 · 250 (classes 2 e 3) ou · 264
  (0 e 1); Weight lbs = massa (t, P+4) · 2204.6; Cornering = 10·(1 - (P+0x53c
  - mín)/(máx - mín)). Faixas por classe em 0x847cd0 (6 floats): classes 0/1
  potência 0.05..0.25, peso 0.07..0.18 t; classes 2/3 potência 0..3.8, peso
  0..2.4 t, cornering 16..27. O texto trunca: 1.08·250 em float dá 269.99997
  e aparece "269.9" (motor todo preparado).
- Peças de motor do buggy (upgrades.xml <Buggy>): Internals até 0.35,
  Management 0.2, Header 0.1, Exhaust 0.1, Intake 0.2 e o câmbio Prototype
  soma mais 0.05: máximo 1.0.
- **0x21d2c8** monta o vetor t[31] das peças (tipos de efeito na tabela
  0x550538: 1 EngineDriveTorque ... 0x10 FinalDriveRatio, 0x11
  CustomGearRatios, 0x12 CustomFinalDriveRatio, 0x14 FrontBrakeBias, 0x1b
  Mass ... 0x1e FrictionEllipseHeightScale). Começa tudo em −999; para cada
  slot de peça (0..0x1a) e cada efeito: 0x12 → t[0x10] = FinalDrive custom
  (0x20aac0), 0x11 → t[0xb..0xf] = marchas custom, 0x14 → bias custom;
  os outros SOMAM (−999 vira o valor) e ficam presos em 0..1. Sem
  CustomGearRatios as marchas vêm da custom do perfil. GearboxLevel_Level0/1
  dão FinalDriveRatio 0.45/0.53; Level2/3/Prototype dão
  CustomFinalDriveRatio (upgrades.xml). Conferido na RAM: Level0 → 0.45
  (Inferno, Bulldog, Phantom, Buccaneer), Level3/Prototype → 0.61.
- **0x21d618** aplica t: slot i com t[i] ≠ −999 → (1 − t)·P[0x1350+8i] +
  t·P[0x1354+8i], gravado pela tabela 0x583580 (0x10 FinalDriveRatio →
  P+0x158; 0x11 e 0x12 não gravam nada). O menu de ajuste (0x3ec5d0) pelo
  GearboxLevel: Level2 só mexe na final, Level3/Prototype nas marchas e na
  final, Level0/1 em nada. Custom do perfil (0x20a738, GearRatioTuning):
  marchas +4..+0x14, FinalDrive +0x1c, FrontBrakeBias +0x20.

## Motor e câmbio

- **0x246858 motor** (struct E em obj+0x2ac): E[1] acelerador, E[2] torque,
  E[4] carga, E[5] rpm, E[6] fator do limitador, E[8] inércia extra.
  Torque = acel·lim·curva_drive(rpm)·escala − curva_atrito(rpm)·escala_atrito.
  rpm += (T − carga)·dt / inércia, preso na marcha lenta.
  Limitador em rampa: cai a Rev_limiter_engage_rate (15/s) acima da rpm de
  corte, sobe a Rev_limiter_disengage_rate abaixo da de volta.
- **0x20c558**: embreagem travada e rodas de tração no chão → rpm = rpm da
  roda × relação. Em troca (shift flag) o acelerador é multiplicado pela
  embreagem. **0x20c7a8** entradas do câmbio: o acelerador do câmbio
  (câmbio+0xc) é o CRU 0x37c, não o suavizado. Ele entra na rampa da
  embreagem (2·(1 + t²) por s), na rpm de engate, no "engata solto acima de
  5 mph" e na troca. **0x20c808** carga = torque da embreagem quando não
  travada; travada, Σ "torque" do freio/relação (sem massa; só pesa com as
  rodas de trás fora do chão, não portado).
- **Pedais (corpo+0x368)**: cada comando tem cru e suavizado (InputRates):
  direção 0x36c/0x370, acelerador 0x37c/0x380, embreagem 0x384/0x388 (InputRates/Clutch; o jogo não tem freio de mão),
  freio 0x38c/0x390, flags 0x394. O motor (E[1] = 0x2b0) e o arrasto
  usam o suavizado; câmbio e "preso" usam o cru.
- **0x241220** suavização da direção (0x241178 é a dos pedais: sobe/desce
  na taxa, vezes Normalised_rate_vs_speed, 1 nos buggies). Abrindo do mesmo
  lado: taxa de subida, × (1 − s²) se *_damp_increase_rate (direção dos
  buggies: sim), ou seja tanh: 0.77 em 0.17 s, 0.95 em 0.3 s; voltando pro
  centro: taxa de descida; trocando de lado: taxa oposta.
- **0x202df0** pedais do jogador no AutoManual (veículo+0xb14 = 1), mph =
  v pra frente·2.2374146: acima de 1 mph modo frente (corpo+0x2d8 = 0) e
  espera 0.1 s (veículo+0xb2c). Senão: soltar o freio zera a espera; freio
  gasta a espera e depois engata a ré (0x2d8 = 1) com o freio virando
  acelerador; acelerador volta pra frente (de ré a mais de 1 mph vira
  freio). Sem pedal e |v| < 0.2 mph (DAT_00550508): freio 1.0, a barra
  vermelha cheia na largada. No ar (0x4e4 > 0) o acelerador fica cortado
  até ser solto uma vez no voo (veículo+0xb30). car.gd _pedais_auto,
  tests/teste_pedais.gd.
- **Câmbio** (struct G em obj+0x2d0, params GP = P+0x138):
  0x2474a0 AutoManual (modo 3): troca por velocidade do carro.
  Velocidade de subir = up_rpm·r·rpm2rad/(relação·final); descer como
  0x246d88. Embreagem: 0 aberta, 1 engatando, 2 desengatando, 3 travada
  (trava com |dif| < lock_diff ou quando o escorregamento troca de sinal).
  Torque: estado 3 = torque do motor; 2 = min(cap, T>0); 1 = sinal·emb·cap.
  0x2470c0 Manual. Índices: 0 = ré, 6 = neutro.
- Força de tração: 0x310/(r·n_tração) por roda de tração no chão (contagem
  estática 0x3a8). Ré: Speed_limit / Drive_cut_speed_threshold; 0x20c278
  limita a velocidade de ré.
- **Arrasto 0x20e5e8** (na força 0x1a0, contra a velocidade 0x90, |v| =
  0xe0): kN = (Air_drag_coefficient·0.00065 + Damping médio 0x788 ·
  Ground_drag_coefficient·0.01)·v² + água (veículo+0xae8 ligado: média d de
  veículo+0xaec+4i, + Water_drag_coefficient x min(d / max_wheel_depth, 1) x
  0.01 x v² se d > 0; portado nov/2026, seção Água), no máximo massa·v/dt.
  Params+0x3e0..0x3fc = Misc (Air 1.25, Ground 2.0, água 0.5/0.1, atrito
  interno 5/80/3/5; iguais nos 6 save states). Atrito interno só com
  acelerador (0x380) zero e roda no chão.
- **Slip alvo 0x2101e0**: usa RpmMax da curva (9000), ou 0.95×limitador
  quando |direção| > 0.5 e < 40 mph.

## Suspensão

- Classe da roda vtable 0x585cc0: +0x1c integra (0x2484c8), +0x24 contatos
  (0x248768), +0x2c mola (0x248a80). Ordem no passo: integra -> contato ->
  mola -> pneus (0x20a0b0). O 0x2484c8 no chão usa W+0xfc (força da mola
  do passo anterior, kN, negativa = empurra a roda pra baixo); no ar
  (W+0x10c = 0) calcula a mola e o amortecedor ali. v += W+0xfc/massa·dt,
  x += v·dt (presos em vmax e min/max). Por isso o x da RAM (W+0xe8) é o do
  contato. Parado, a soma dos W+0xfc = peso (Buccaneer 16.68 kN, Bulldog
  9.81). Campos: W+0xe8 x, +0xec min, +0xf0 max, +0xf4 v, +0xf8 vmax, +0xfc
  força, +0x100 cos do ângulo máximo, +0x110 normal do chão.
- F = k·curva(x/max ou x/min)·x + c·curva(|v|)·v (kN), ao longo da normal
  do chão no ponto de fixação. x < 0 com contato puxa o carro pra baixo.
- Batente x > max = correção de posição (regra de junção 0x23f6c0,
  aplicada em 0x23f5a0). Roda tem massa (0.05 t); x e v integrados.
- Anti-pitch 0x2100a0: acima de sen 5° (cheio a 10°) acelera I·5.5 rad/s²
  de volta. No ar, Pitch_torque constante (−0.5 kN·m).

## Pneus e derrapagem

- **Powerslide = "Clutch Turn"** (0x214610, chamado em 0x20cea0 antes do
  0x2101e0 só se Powerslide/Growth_rate P+0xf64 > 0; treino: "Tap ... to
  initiate a clutch turn"). Estado corpo+0x74c, quantidade 0x744, escala
  0x748 = Scale_vs_speed(mph do 0x440), embreagem do passo anterior 0x740.
  0 -> 1: direção suavizada 0x370 != 0, acelerador 0x380 > 0 e a embreagem
  0x388 SOLTANDO (< 0x740). 1: quantidade += Growth_rate·dt até 1 (-> 2);
  embreagem subindo ou acelerador 0 -> 3. 2: embreagem subindo -> 0 (a
  quantidade fica); acelerador 0 ou direção·derrapagem 0x6c0 >= 0 -> 3. 3:
  quantidade −= Decay_rate·dt até 0 (-> 0). No ar > Maximum_air_time (0.1)
  zera. Efeitos: em 1/2 a elipse 0x670 das rodas de tração vai pro mínimo
  da curva × Scale_of_min_friction_ellipse_scale (0x214610 e 0x2101e0); em
  qualquer estado != 0 o Side_deceleration_to_fwd vira o do Powerslide
  (P+0xf70, 1.0 x 0.75; 0x20efa0); quantidade·escala mistura a curva de
  taxa de subida da derrapagem com Maximum_sideslip_rate_vs_sideslip do
  Powerslide (P+0xecc; 0x210ce0). Estado 3 escala a tração por
  Decay_drive_force_scale (1 nos buggies) e soma Decay_boost_acceleration
  (0 nos buggies). Nos 4 save states de derrapagem o estado era 0: a
  derrapagem "natural" de virar forte não usa o powerslide.

- **Conferido com save states** (tests/teste_derrapagem.gd, tests/
  ref_derrapagem.json; Renegade no RX01 a ~120 km/h, volante todo e
  acelerador no fundo): o remake no estado exato da RAM dá a mesma força
  por roda (0x5c0: x = lateral pro lado direito do carro, z = pra frente,
  kN), maior diferença 0.13 kN (era 1.26 sem o 0x2120c0). Do drr_3
  (118 km/h, −42°, 84°/s) até o drr_2 (1.16 s depois pelo relógio do
  Screenshot.png do .p2s) o remake termina a 0.4 m: 29.4 x 30.7 km/h, girou
  124 x 120°, derrapagem −68 x −60°, giro 178 x 179°/s. No jogo o carro
  também roda segurando o volante todo.
- **Segurando o R1** (botão da embreagem, 5 save states fm_* em
  tests/ref_derrapagem.json, 30 a 148 km/h virando e acelerando): botão
  0x384/0x388 = 1, embreagem 0x2ec = 0 (aberta pelo 0x20c558), motor no
  limitador (8000 a 8100 rpm, 0x2c4 batendo 0.3/0.6), Clutch Turn 0x74c = 0.
  O remake dá a mesma força por roda (0.13 kN no pior dos 11 estados) e o
  mesmo rpm (±110). A RAM guarda o curso da roda do começo do passo e a pose
  do fim: com o carro subindo (fm_2, 0.38 m/s) o teste desce a roda o quanto
  o ponto dela subiu no passo.
- **Corte de recuperação 0x2120c0** (Sideslip/RecoveryTorqueCutting P+0xb10,
  chamado no fim dos modos B e C do 0x20efa0; o modo A pula): devolve f e o
  torque de giro do modo vira torque·(1 − f). Só com FrictionEllipse Enabled
  (P+0x430) e corpo+0x728 = 0; mph(0x440) > Speed_for_zero_sideslip e
  v_f > 0. f = Maximum_cut(mph v_f, P+0xbb8)·acel·rampa(|β|, Threshold
  P+0xb20, Maximum_angle P+0xb6c; 0 nos buggies, o cut é 0). Com
  Steering_dependent (P+0xb1c) e |β| > Threshold (12°): direção 0x370 com
  sinal contrário a β ou solta -> f = acelerador 0x380 (solta e
  |giro| > v_p / |ponto (x, z) da roda FL|: devolve 0, rodou); mesmo sinal
  (contra-esterço) -> f = (f − 1)·|direção| + 1. Com f > 0.01 a patinada
  0x610 de cada roda com W+0x10c != 0 em (−0.1, lim) sobe
  Growth_rate_during_wheel_spin·dt até lim = Maximum_increased_front/
  rear_slip_ratio (P+0xb14/0xb18, frente se W+0x40 & 4; 0 e 0.2)·f, no
  máximo SlipRatio/Maximum, e marca corpo+0x540 = 1 (zerado no começo do
  0x20efa0): aí o 0x2101e0 não devolve a patinada positiva da roda dentro
  da elipse. Na RAM dos 6 save states: Enabled 1, Steering_dependent 1,
  0x728 0, W+0x10c 1, W+0x40 0x5 na frente e 0xa atrás. Efeito: acelerando
  com o volante pra dentro ou solto o carro NÃO endireita sozinho.
- Modo A do 0x20efa0: a mistura com −erro_giro/dt (peso (10° − erro)/10°,
  DAT_00550658) só vale com DAT_00550654 = 1 e a direção crua 0x36c e a
  suavizada 0x370 do mesmo lado (estritamente).
- Versão legível de toda a derrapagem, na ordem do passo:
  docs/derrapagem.md.
- Estado da RAM pro remake: corpo = (−direita, cima, frente) do jogo
  transpostos (Terrain.dir_do_jogo), origem = origem do modelo menos
  corpo(0); velocidade angular = −dir_do_jogo(w) (vetor axial na
  transposição). O curso da RAM é do fim do passo, já subido até o chão
  (pen = 0); o teste tira 1 mm pra roda contar como no chão.

- **0x211b58 aplicação das forças**: por roda, em CoM + n·(soma do y do
  contato do eixo relativo ao CoM × escala) + frente·z_do_eixo.
  Lateral_scale_std 0.09; longitudinal = mistura de 0.5 e 0.2 por 0x474
  (= acel·frac·Side_decel_to_fwd). A escala lateral muda com a inclinação:
  s = |corpo+0xc0 (cima do carro) · corpo+0x3e0 (lateral do chão)| = seno da
  inclinação de lado em relação ao chão; s <= Params+0xf90
  (Lateral_scale_sine_threshold_roll, 0.052 = 3°) dá o std (+0xf88), s >=
  +0xf94 (sine_maximum_roll, 0.14 = 8°) dá o +0xf8c (at_maximum_roll, 0.0),
  linha reta no meio. Ou seja: inclinado mais de 8° a força lateral age na
  altura do CoM e não tomba mais o carro. Na RAM do Fireball.p2s: 0xc0 =
  (-0.0139, 0.9998, 0.014) = "cima" do corpo; 0x3e0/0x3f0/0x400 = lateral,
  normal e frente do chão. Portado em out/2026 (car.gd _h_lat); antes o
  remake usava sempre 0.09 e inclinava mais (Fireball virando a 80 km/h:
  8.8° -> 6.0°, tests/teste_capota.gd).
- **0x20bf58 eixos 0x3ac/0x3b0**: média do z das rodas em coordenadas do
  MODELO (não relativo ao CoM). Entra na curvatura, divisão lateral e ponto
  de aplicação.
- **0x210ce0 limitador da taxa de sideslip**: β' = ((v_f·ΣFx − v_l·ΣFz)/m/v²
  − guinada)·sgn; máximo das curvas Sideslip/MaximumRate increase/decrease
  (rate_vs_sideslip); excesso vai direto pra velocidade angular. Abaixo de
  30 mph: guinada ≤ v / distância até a roda dianteira se a velocidade
  estiver > 30° da direção da roda.
- Contagens estáticas: força de sideslip nas 4 rodas dividida por 2/2;
  elipse em todas; tração e freio só nas rodas no chão mas divididas pela
  contagem estática (0x20efa0 / 0x20eb98).
- **0x20e160**: no chão, cancela a componente lateral da gravidade em
  rampa, aplicada na altura do chão.
- No ar **0x2129c0**: guinada (alvo direção·máx, acel direção·acc·dt),
  empurrão lateral (Maximum_force 2.5 kN, cauda de 2 s), arfagem com freio /
  sem acelerador.
- Patinada por roda **0x610+4i** (0x2101e0, 2ª volta): roda saturada na
  elipse com força·v_f > 0 cresce Growth_rate_during_wheel_spin até o limite
  do motor (giro de referência, Maximum); com força contra o movimento e
  pedal (0x390) > 0.1 desce Growth_rate_during_wheel_lock até −1. Fora da
  elipse volta pra 0 (Recovery_rate_during_wheel_lock / _spin). Sem
  condição de acelerador nem de marcha (vale em ré).
- **Freio 0x20eb98**: desaceleração = pedal 0x390·0.44694445·
  Maximum_deceleration·escala(atrito 0x780), no máximo o que zera a
  velocidade PREVISTA (0x211e48, com a tração 0x5c8 e o 0x1a0 já somados:
  gravidade do 0x20e160 e arrasto). Ordem no passo (0x20cd2c): 0x20da90,
  0x20df58, 0x20e160, 0x20e5e8, 0x20e8d8, 0x20eb98, 0x20ede8, 0x20efa0,
  0x2100a0. Por isso o freio segura o carro parado contra a tração.
- **ABS 0x20eb98** (flag 0x620+4i): Enable_ABS do Footbrake; patinada medida
  (0x600) <
  ABS_engagement_slip_ratio (−0.2) solta o freio da roda, ≥
  ABS_disengagement_slip_ratio (−0.01) volta. Todos os buggies têm ABS
  (conferido na RAM). Roda fora do chão zera a flag.
- **Trava 0x210908** (depois da elipse, antes do 0x210ce0; globais
  0x5506a4..b4 = ligado, 2 mph, −0.25, −1, rampa linear): roda sem ABS
  soltando, com patinada medida (0x600) < −0.25, tem a força (mesmo tamanho) virada pra
  contra o deslize do contato: velocidade local do corpo (0x410, global
  0x550680 = 0) com a frente trocada por −v_f·patinada (0x630, 0x20df58).
  Em −1 fica toda contra. Com o ABS dos buggies não chega a agir.

## Giro das rodas

- Ordem do passo (0x1727a0): motor/câmbio 0x209e38 (0x20c0d0 guarda a
  posição em 0x880, 0x20c558 giro do motor) → integra corpo e rodas → pneus
  0x20a0b0 (0x20df58 patinada medida, ABS, forças, 0x20cea0: 0x2101e0
  patinada, 0x210908 trava, 0x210ce0, **0x2113e0 torque das rodas**,
  0x211b58).
- Roda (vtable 0x585cc0): raio W+0x30, inércia W+0x3c = Mass·R²/2 (RAM
  0.00625 / 0.0060025 t·m²), flags W+0x40 (2 = tração, 4 = frente), torque
  W+0x44, giro W+0x48, ângulo W+0x4c. **0x2484c8** integra: ω += T·dt/I,
  ângulo += ω·dt (mod 2π). 0x249930 é de outra classe de contato de pneu que
  os buggies não usam (sem instância na RAM).
- **0x20df58** patinada medida 0x600 = ω·R/v_f − 1 (v_f = 0x418; 0x550680 =
  0, não usa a velocidade do ponto da roda); |v_f| ≤ 1e-6 → 0.1·ω (0x550684);
  roda no ar → 0. Quem lê: ABS, trava, 0x630, 0x20c558, partículas/vibração.
- **0x211e48** v_ref = v_f + (Σ forças pra frente das rodas 0x5c8 + força
  0x1a0 · frente) · dt / massa: a velocidade prevista no fim do passo.
- **0x2113e0** torque por roda. Contagens 0x3a0 (frente), 0x3a4 (trás), 0x3a8
  (tração), 0x3cc = rodas de TRÁS no chão (W+0x18 < 0, 0x20d568).
  Motor na roda = embreagem 0x2ec · relação total 0x300 · torque 0x2b4 ·
  0x720 (=1) / 0x3a8. "Torque" do freio = pedal·0.447·Maximum_deceleration·
  escala(atrito médio 0x780)·(Front_bias ou 1 − bias)/rodas do eixo·R, SEM a
  massa. Roda solta no chão: T = I·(v_ref·(1 + 0x610)/R − ω)/dt (ω vira o
  alvo exato). Solta no ar: perde max(180°/s² 0x5506c4, freio/I). Tração
  com 0x3cc ≥ 1: igual à solta no chão (ou, preso, giro do motor·embreagem/
  relação). Tração com 0x3cc = 0: embreagem travada (0x314 = 3) → giro do
  motor/relação; senão motor − sinal(ω)·freio, com freio maior parando a
  roda e motor maior sem passar do giro do motor.
- Preso (0x890/0x894/0x870): acelerador 0x37c > 0, botão da embreagem 0x388 = 0,
  |v_f| < 0.5 e o corpo dentro de 3 cm (0.0009 m²) por mais de 0.33 s. Aí
  v_ref = deslocamento do passo (0x70 − 0x880)·frente/dt e o giro do motor
  não vem das rodas.
- **0x20c558** (motor): 0x304 = ω da roda de tração mais rápida·9.549;
  embreagem travada, não preso e 0x3cc ≥ 1 → rpm = 0x304·relação (mín.
  marcha lenta). Embreagem forçada aberta 0x31c: 0x5ac, botão da embreagem 0x388 > 0.1,
  mais de 1 s no ar (0x3d0) abaixo de câmbio+0x90 (1050 rpm), ou pedal >
  0.9 com roda de tração em 0x600 < −0.9 (0x55067c).
- No chão o 0x600 de um passo sai igual à 0x610 do anterior (por isso a
  aproximação antiga dava os mesmos números); muda em derrapagem (v_ref não
  conta o giro do carro), no ar (tração gira com o motor, frente perde
  giro), parado contra um muro e na roda da tela. tests/teste_roda.gd.

## Casco de colisão (VehicleWorld.hsc)

- 0x1fed48 monta "/Vehicles/%s/Collision/%s/VehicleWorld.hsc" com a classe
  (descritor veículo+0xa6c, +0x1c: "Buggy", "Truck") e o Name do
  vehicles.xml (+4: "TRUCK_10", "BUGGY_12"); sem o arquivo usa "Generic".
  O mesmo descritor tem +0xc nome longo, +0x14 chassi, +0x2c mapa de peças,
  +0x34 rodas genéricas, +0x3c câmeras. Também carrega o VehicleVehicle.hsc
  (carro contra carro, outro casco).
- Pelo id, não pelo chassi: o Storm (chassi Lancia, não existe
  Collision/Lancia) carrega o Buggy_12 (raios e normais na RAM do
  storm.p2s). Então o Jericho (TRUCK_04, chassi Truck_11) usa o casco do
  Truck_04, que encaixa na Silverado (a carroceria original dele, o nosso
  Lazarus: caixa 0.76 de diferença x 1.47 na carroceria do Jericho), e o
  Chimera usa o Truck_12 (as pastas Collision/Dakar sobram).
- Formato "CSH\0": versão 1, 1; n planos (normal, d; dentro = n·p + d <= 0);
  n esferas (contador em 16 bytes; centro, raio). Frame do modelo. O loader
  0x13e318 tira o CoM (d -= n·CoM, centro -= CoM): no Fireball.p2s os 13
  planos estão em RAM 0x117dae0 e as 11 esferas em 0x117dd40 (+1 esfera
  (0, 0.7, 0.188) r 0.25 no fim), e a caixa do corpo (0x117dcc0) é a das
  esferas no mundo. Os 14 planos em 0x117d320 são do VehicleVehicle.
- O corpo bate no mundo pelas ESFERAS, sem recorte dos planos. Save states
  do Matheus (out/2026), lista de contatos do corpo (corpo+0x1f0; +0x10 =
  ponto relativo ao CoM em eixos do mundo, +0x30 normal; no modelo: CoM +
  R·ponto com R = linhas corpo+0xb0/0xc0/0xd0): Fireball de lado, contato
  em (-1.186, 1.528, -1.703) = exatamente na esfera 9 (distância 0.000) e
  3.4 cm FORA do plano 8; capotado, (-0.319, 2.488, -0.008) na esfera 5.
- A roda vira esfera fora do cone da suspensão: o 2º contato do Fireball de
  lado, (-1.545, 0.198, 1.567), fica a 0.567 m do WHEEL_FRONT_LEFT (curso 0)
  = o raio da roda; o chão ali está a ~104° do eixo da suspensão (fora do
  Cosine_maximum_collision_angle 0.643 = 50°). Dentro do cone é a mola.
- No remake (car.gd _casco, _esferas_das_rodas): uma SphereShape3D por
  esfera do .hsc (tools/casco.py -> data/vehicles/<id>_casco.json) e uma
  por roda (raio da roda, no centro dela com o curso), ligada a cada passo
  só quando o chão perto dela (consulta de esfera 3 cm maior) tem normal
  fora do cone. Antes era uma caixa de 2.1 x 0.8 x 4.8 m igual pra todos
  (teto do Fireball em 2.5 m: capotado a cabine entrava 1 m no chão) e a
  roda de lado ficava presa embaixo do chão (Fireball 1.2 m, Chimera 95 cm;
  agora 0). tests/teste_de_lado.gd.

## Pontos do modelo

- Arquivo "POINT 1.00": contagem em 0x10, entradas de 0x50 bytes a partir
  de 0x14: nome 0x00..0x20, xyz em 0x20, matriz 3x3 em linhas em 0x2c
  (escala 0.01; na RAM fica normalizada, +0x30/+0x40/+0x50 do objeto).
  Loader 0x62fa18; tabela por id 0x222b38 (enum em 0x550700: 1..4 WHEEL,
  9..16 A_FRAME/A_FRAME_END, 21..24 SHOCKS_BOTTOM/TOP_FRONT, 25..28
  SHOCK_PISTON/CHAMBER, 29/30 SpareWheel, 31 LIGHTRIG, 32 BUMPER). Nomes
  também em 0x55070c. "Esquerda" do jogo = x < 0 no modelo.
- BRAKE_LIGHT*, REVERSE_LIGHT*: o exe não tem as strings porque os nomes
  vêm do Setup/VehicleHaloMap.xml (seção Halos abaixo): o jogo põe um halo
  neles. A lente em si não muda (cor do vértice vermelha ou textura).
  TAIL_LIGHT (Bulldog) não está no mapa. Nenhum carro tem HEAD_LIGHT.
  Farol comprado = componente Lighting no ponto LIGHTRIG (id 31), só modelo.
- CoM do XML em coordenadas do modelo. Corpo físico +0x70 = CoM; veículo
  +0xaa0 = origem do modelo (= CoM − R·CoM_local).

## Halos (brilho das luzes do carro)

- Setup/VehicleHaloMap.xml (data/vehicle_halo_map.xml, loader 0x22a400 ->
  0x22a568, singleton DAT_007f7248, 0x40 por entrada: +0 nome do ponto, +8
  HaloName, +0x10 Behaviour, +0x20 Normal, +0x30 Offset). Behaviour pela
  tabela 0x55084c: Brake 0, Reverse 1, Night 2. Entradas: BRAKE_LIGHT1-6
  "BrakeLight", REVERSE_LIGHT1-2 "ReverseLight", HEAD_LIGHT1-3
  "ReverseLight" (Night), FRONT_HALO1-10 "HaloTestLight1-5" e REAR_HALO1-5
  "RearHaloTestLight" (Night, Offset y -0.11).
- 0x225cf8 monta os halos do carro: pra cada entrada do mapa que tem ponto
  no modelo (0x62fd48), cria um registro de 0x90 em (render+0x1e0, conta em
  +0x1d4) e põe na lista do comportamento (render+0xf60 + b*0x70: ponteiros
  em +0x10, conta em +0x4; render = veículo+0xb00). O halo vem do
  Setup/VehicleHalos.xml (data/vehicle_halos.xml) com 4 níveis (LOWEST, LOW,
  MID, HIGH) de B1Halo: Texture, ZedBias e Layers (TextureBox, Width,
  Height, Angle, SizeScale, AngleScale, Colour; parse 0x22a8a8/0x26c458).
- 0x203930 (por quadro, render do veículo) liga o campo +0x24 de cada
  registro: Brake = carro ativo e (0x9d0+0xf4)+0x2b8 != 0 e freio suavizado
  (corpo+0x390) >= 0.1, e com (0x205200)+0x10 == 0 também acende de ré;
  Reverse = 0x2040b8 (ré); Night = carro ativo (vtable+0x84 do 0x9d0). Nos
  save states a chave +0x2b8 é 1.
- 0x2260a0: leva os halos pro mundo e, por instância, +0x1c0 (força) sobe
  dt*4 até 1 quando está ligado e foi desenhado no quadro (0x2295c0: +0x4c
  == quadro atual), e zera na hora desligado. O desenho em si é no VU1/GS
  (0x26d328 monta os registradores): AngleScale, SizeScale e ZedBias não
  foram decifrados.
- RAM: Renegade (a.p2s) 2 halos de freio em (±0.60, 1.92, -1.55) acesos com
  freio 1.0; Storm 2 de freio + 1 de ré. Screenshot.png dos save states:
  brilho laranja com raios em ±0.4 rad (nível HIGH). Tamanho medido: miolo
  ~6 px com as lanternas do Renegade 82 px uma da outra (1.2 m) e raio
  vertical ~0.75 m: Width/Height x 0.3 m.
- Textura Sprites/lightglow2alpha (128x64): o desenho é o alfa (RGB branco).
  Caixas do .bed (fração x 100000): GLOW (0, 0)-(0.509, 0.9375), RING
  (0.600, 0.247)-(0.850, 0.747), SPIKE (0.865, 0)-(0.958, 1). O alfa não
  chega a 0 na borda (12/255 no GLOW, 40 na ponta do SPIKE).
- Nenhum carro do jogo tem HEAD_LIGHT/FRONT_HALO/REAR_HALO (varredura do
  unpacked): o farol Night existe e nunca aparece. Os LIGHTRIG comprados
  (root.xml Lighting, mIsPhysical false, 8 modelos x Small/Large pelo
  LightRigCategory do vehicles.xml; .pfn só com chassis_comp03, dirt,
  light_64, light2_64, mesh_grey) não têm pontos: são só modelo.

## Câmera (BuggyCamSet_NN em data/cameras.xml = 14880)

- Loader 0x38d5f8 (offsets dos parâmetros), defaults 0x38d498, caller
  0x38ce58 (lê CameraSets, 12 câmeras de seguir + 6 montadas).
- Construtor da órbita 0x38dc30; update base 0x387320 (passo fixo 1/60;
  reset 0x38e0c0 = 0.5 s de updates). Só a câmera ativa atualiza.
- Componentes em ordem: altura por velocidade 0x383418 (m/s) → offset no
  frame do carro só com guinada 0x383588 → amortecimento Y 0x383cf8/0x384168
  (taxa de subida se vy > 1; cai na hora, volta devagar) → subida em descida
  0x385238 (−dir.y·DOWN_INCLINE, DECAY, taxa máx) → órbita 0x386950
  (direção = frente puxada pra velocidade por MaxCourseFollowAmount;
  SlerpRate e no máx SlerpMaxAngle graus por passo; distância por mph) →
  descolar/recolar 0x384ef8 (MAX_POS_CHANGE 1, BEGIN 2 s, REATTACH 2 s) →
  altura mínima do chão 0x384c80 (1.45 m, taxa 30) → mira 0x37f2f8
  (LOOK_OFFSET; y da mira some com mph/LOOK_MAX_SPEED) → tremida 0x380418
  (camera_jitter.gd, abaixo) → zoom 0x3806a0 (FOV_MIN/MAX_ZOOM por mph,
  fração dt).
- Final 0x387320: pos = ant + min(taxa·dt,1)·(nova + dir·0.2 − ant), taxa
  10 subindo 5/s até 40.
- Projeção 0x390a80 / 0x64f0a0: meia-largura 0.5/zoom, meia-altura
  0.375/zoom (4:3). Zoom menor = mais aberto.
- Tremida (vtable 0x5b4fb8: update 0x380418, aplica 0x380170; construtor
  0x380348/0x380090, loader 0x38cc48). Parâmetros só do GenericCameraData
  pelo tipo da câmera (os Jitter* dos CameraSet são ignorados: conferido nos
  componentes vivos na RAM). Defaults: SpeedStart 0, SpeedMax 1, Perlin 0,
  Decay 0.95, CollSpeed 10/30, CollMass 0.01/0.1.
  Velocidade: f = clamp((|v| − Start·0.44694445)/((Max − Start)·0.44694445)),
  a = veículo+0xac0·f², e veículo+0xac0 = média do WheelJitter embaixo de
  FL, RL, FR no chão (0x202760). Duas ondas Perlin (Amp/4, Freq) e
  (Amp, Freq·1.05), fase sorteada; n = tabela(fase)·amp·a, fase += dt·freq
  mod 1 (0x3aa668/0x3aa6e0, tabela de 257 floats em RAM 0xd0e7f0 =
  data/ruido_camera.bin). Direção nova = dir + direita·n1 + cima·n2,
  matriz refeita (0x61e010). Órbita: 70 a 100 mph, Amp 0.03, Freq 0.3;
  capô/para-choque: 0 a 75 mph, Amp 0.04, Freq 0.25.
  Batida (portada, camera_jitter.gd + car.gd batida): a cada passo de física
  o 0x215140 anda na lista de contatos do corpo (corpo+0x1f0, próximo em +4)
  e o 0x215248 guarda até 3 registros de 0x40 em corpo+0x7a0, ordenados pela
  velocidade (índices em corpo+0x860.., −1 = vazio, quantos em +0x86c):
  +0 = |contato+0x64| (velocidade do ponto na normal, m/s), +0x10 normal
  (contato+0x30), +0x20 ponto (contato+0x10), +0x34 outro corpo (contato+0xc
  → +0x1d4; 0 em parede e chão). Contato com outro carro (+0x68 == 2) entra
  nos dois, com a normal negada. A câmera lê o maior (idx[0]): c = rampa da
  velocidade (abaixo de CollisionSpeedForStartJitter 0, acima do Max 1) ×
  rampa da massa do outro (+0x60 → +0x78, t, CollisionMassFor*; só com outro
  corpo) × CollisionJitterMagMax; amp (componente[4]) = max(c, amp)·Decay a
  cada passo de 1/60 e, com amp > 1e-6, soma um sorteio uniforme [−amp, amp)
  em n1 e n2 (x·31415821+1 mod 2^30 / 2^30, semente global 0x8383a8). Trava
  (não portada): com (veículo+0xa6c)+0x8c → +0x18 ≠ 0, +0xa78 = 0, +0xa74 ≥
  0.5 e amp ≤ 1e-6 a batida não começa. Save state crash_Storm (parede de
  pedra, 44 km/h): 1 registro de 0.08 m/s (encostado), normal (−0.38, 0,
  −0.93), sem outro corpo; um registro velho de 4.86 m/s; órbita perto com
  MagMax 0.05, Decay 0.93, 4/44 m/s, amp 0.0124. No remake a velocidade é a
  do ponto ANTES do passo que achou o contato (o solver do Godot já tirou a
  aproximação). tests/teste_batida.gd.
- Câmeras montadas (MountOnHood/Front): PosOffset no frame do modelo,
  Orientation.X em graus, FOV fixo. MountOnFront fica dentro da carroceria
  (não desenha o carro).

## Peças (cCompPlace_<Position>)

- Cada componente do component map vira uma classe
  sprintf("cCompPlace_%s", Position) (0x222d88; registro 0x5502c8, fábricas
  0x208d40..0x2097e8, vtables 0x5801e0..0x580898). O método +0x1c
  (0x1fc150..0x1fd8c8) copia 4 linhas de uma pose P que fica no scratchpad
  (0x70000000, 0xe70 bytes) e é recalculada por quadro, sob demanda
  (0x21dff8..0x221d58). Monta P: 0x203930 / 0x221e48; render 0x22ace8.
- Convenção vetor-linha: v' = v·R + t, linhas = eixos. No Godot: colunas do
  Basis = linhas do jogo. Rx/Ry/Rz 0x61e1a8/0x61e2a0/0x61e528 = Basis(RIGHT/
  UP/BACK, a); eixo-ângulo 0x61e6c8 = Basis(u, a).
- Curso visual 0x222078: W+0xe8 + tremida (veículo+0xab0+4i). Rodas na
  ordem FL, RL, FR, RR (corpo+0x254).
- Balança (0x21eec0 FL, 0x21f050 FR, 0x21f1b8 RL, 0x21f320 RR): u = linha 2
  da matriz do A_FRAME_*, d = A_FRAME_END − A_FRAME, r = |d.x·u.z + d.z·u.x|,
  ângulo = atan(x/r), gira em volta do A_FRAME. Frente e trás iguais; o eixo
  sai do arquivo (Bulldog frente em x, Phantom trás e Storm em z).
- Centro da roda (0x220110..0x220460): WHEEL girado com a balança; só na
  frente o y vira WHEEL.y + x. Roda dianteira R = Rx(giro)·Ry(direção),
  traseira Rx(giro); esquerda com a linha 0 negada. Não herda a balança.
- Freios: frente (0x221748) R = Ry(direção), t = centro − WHEEL·R; trás
  (0x221928) só translada até o centro.
- Amortecedor dianteiro (0x21f590): rígido, Rz(±acos(...)) em volta do
  SHOCKS_TOP até o SHOCKS_BOTTOM girado (negativo na esquerda). Traseiro
  (0x21fb68..): câmara e haste com Rx(atan(...) − atan(...)), haste levada
  até o SHOCK_PISTON girado (x original). atan, não atan2.
- Rally (0x220528 / 0x220cf0): roda = WHEEL + x·dir, sem balança.
  Estepe/LIGHTRIG/BUMPER (0x221a88..): matriz e posição do ponto, fixos.
- Tremida 0x202760 (portada, car.gd _wheel_jitter): uma vez por passo de
  física (50 Hz no PAL: FUN_00172778, obj+0x70 = 50 se 0x7f3e8c == 3),
  todos os veículos. Zera as 5 entradas; pra FL, RL, FR (pula a RR) no chão
  (corpo+0x898+4i = W+0x10c): amp = min(1, WheelJitter·0.06392613·v), com
  v = corpo+0x440 (m/s no plano do chão, 0x20d568) e 0.06392613 =
  2.2374146/35; x = (x·31415821 + 1) mod 2^30 (gerador do piloto, semente =
  relógio em ms + índice); tremida = amp·(x·0.075/2^30 − 0.0375). Depois
  RR = RL (vem do eixo rígido dos ATVs, cCompPlace_RearFreeAxle 0x21ee00).
  WheelJitter = Materials.xml da pista (+0x3c, loader 0x3a9608): RX_01 0.3
  na terra/cascalho/grama, 0 no asfalto e gelo; material da roda = do
  triângulo do contato (W+0x140). A largada do RX_01 é asfalto. Entra em
  0x222078 (curso visual, sem clamp depois), então mexe balança, cubo,
  freio e amortecedor. tests/teste_tremida.gd.
- Vibração do controle 0x202ab8 (chamada por 0x159448, entregue por
  FUN_00649a68 aos motores 0 e 1 do DualShock). Motor 1 (grande) =
  veículo+0xa40 limitado a 1 (amplitude da tremida de batida da câmera,
  escrita em 0x202760). Motor 0 (pequeno), só com corpo+0x8a8 > 0 (rodas no
  chão, contadas em 0x20cf28 pelo W+0x10c): v = |v| (0xe0); trava = alguma
  roda com 0x600 < -0.95; pat = maior clamp(0x600, 0, 1) das rodas com giro
  W+0x48 > 3.14; r = (1.5·|0x410| + 15·[v < 8.938889 e pat > 0.1] +
  0.33561218·v·[trava])·U(0.1, 0.9), + 0.25·v em 10% das chamadas, ×0.07.
  Não usa rpm. No remake vira a tremida do volante (car.gd _vibracao,
  melhoria nossa).
- Trucks (TruckCompMap_B1/B2, A2), conferido com a RAM do Goliath:
  - Classe k da tabela 0x5502c8 -> vtable 0x580898 - k·0x28, método
    +0x1c: 2 LeftFrame 0x1fc1d8, 3 RightFrame 0x1fc278, 6 RearAxle 0x1fc428,
    12 FrontLeftBrake 0x1fc7d0, 13 FrontRightBrake 0x1fc858, 20
    RearFreeAxle 0x1fcc10.
  - Ajudantes: 0x222078 curso visual, 0x2220c8 W+0x10 (ponto de repouso,
    relativo ao CoM), 0x2221b8 W+0x20 (direção da suspensão, (0, 1, 0)),
    0x222310 CoM (corpo+0x364 -> +0xc10). 0x6894e0 = tanf.
  - LeftFrame / RightFrame (0x21e0b8 / 0x21e1f0, translação 0x21e158 /
    0x21e290): Rz(tan(x / W.x)) em volta do A_FRAME_LEFT / RIGHT (tan
    mesmo, não atan). W = entrada 1 / 2 da tabela de ids do carro, que o
    jogo enche pelo começo do nome na ordem do arquivo: no truck é o
    WHEEL_FRONT_*_VISUAL, que vem antes do WHEEL_FRONT_*.
  - FrontLeftBrake / FrontRightBrake (0x221308 / 0x221468): eixo-ângulo
    (W+0x20, esterço P+0x44) em volta de W, + W+0x20·x.
  - RearAxle (0x21e998 / 0x21eba8; os 2 modelos, Axle e Rear_Arm, usam a
    mesma pose): ponto do eixo 0x21e838. a0 = (0, ARM_PIVOT.y,
    ARM_PIVOT.z); m = meio dos centros das rodas de trás (WHEEL_REAR_* +
    (0, x, 0)) com m.x = 0; a = acos(norm(AXLE_ANCHOR − a0)·norm(m − a0)),
    negativo se AXLE_ANCHOR.y < m.y; R = Rx(−a) em volta de a0 (Goliath
    parado: 12.73°).
  - RearFreeAxle (0x21ee00): identidade, sobe (x_RL + x_RR)/2.
  - Rodas desses mapas = as do rally (WHEEL + x).
- Conferido: tests/teste_pecas.gd compara 110 matrizes de 7 carros
  (Renegade, Sphinx, Inferno, Bulldog, Phantom, Storm e o truck Goliath)
  com a RAM dos save states parados, erro < 0.01 mm. Classes das rodas de
  rally: método +0x1c 0x1fd1c0 FL, 0x1fd248 FR, 0x1fd2d0 RL, 0x1fd358 RR;
  estepe 0x1fd730. Os caminhos carregados na RAM (Models_4K/Chassis/...,
  Wheel/...) são os mesmos do pecas.json de cada carro.

## Piloto e volante

- O volante NÃO gira no jogo: faz parte do BODY.pingu, desenhado com a
  matriz do carro (cCompPlace_Body +0x1c = 0x1fc100, identidade). Nenhum
  .pingu tem índice de matriz por vértice. O volante girando do remake é
  melhoria (car.gd VOLANTE_GIRA; tools/volante.py acha o aro).
- Quem mexe com a direção é o piloto: Driver="Seated" ->
  cDriverComponentFactory_Seated (0x1fe918, 0x1b1508) -> AObjectRider
  (0x1829c8), sentado no ponto ARSE (rider+0x2f0; origem = ARSE −
  (0, 1.1315, 0.3032)). Modelo MALE_HIGH/MID/LOW.srd (other/00514..00516),
  esqueleto InGame_Mid.skl (00519, 47 ossos). Animação Truck_Riding
  (Setup/RiderAnimation.xml): clip STEER_LEFT.bac (00312) tocado no tempo
  |s|·(1/6 s), espelhado com s > 0 (0x190e50). s suavizado em 0x187060:
  s += min(1/dt, 30)·(direção − s)·dt (o volante do remake usa a mesma
  suavização com o sinal trocado: car.gd rider_s = −s, + = esquerda). mRiderMatchSteer = 0 nos buggies; IK das mãos só no ATV_Riding e
  Bike_Riding (0x1a15a0/0x1a1650), não no Truck_Riding que o Seated usa.
  Câmeras: mRenderRider = 0 em On_Front, On_Hood e Wheel (xml 14837).
  Portado: tools/piloto.py -> assets/piloto/piloto.json, piloto.gd.
- Formatos (out/2026, tools/piloto.py tem o detalhe):
  - .skl "cstfd": 0x0c nº de ossos, offsets em 0x10..0x30: pai (int16),
    osso espelho (int16, direito <-> esquerdo), matriz inversa de repouso,
    matriz de repouso, 2 tabelas de quaternions (identidade no InGame_Mid),
    posição local (x com sinal trocado em relação às matrizes), nomes.
    Pose T, 1.69 m, direita do piloto = x > 0 (mão esquerda do jogo).
  - .srd "SKRDPS2 ": 0x10 nº de ossos, 0x14 matrizes inversas de repouso,
    0x4c material ("WHITE" = textura montada), 0x48 geometria: 1ª palavra
    = tamanho em qwords (& 0xffffff), depois lotes VIF de até 51 vértices:
    V3-32 posição, V4-5 normal ((v − 15.5)/15.5 em x, y, z; bit 15 = ADC,
    não fecha triângulo), V2-16 UV (/4096), V4-8 ossos (índice x 4, 255 =
    nenhum), V4-8 pesos (/255), MSCNT. Triângulos virados pela normal do
    jogo (o PS2 desenha os dois lados). MALE_HIGH 3761 vértices, MID 1579,
    LOW 778, FEMALE_HIGH 3536, ARMS_POV 1461 (26 ossos), PONYTAIL 183.
  - .bac "BAC 2.07" (loader 0x22f090 pelo tipo em +0x44; tipo 1 =
    0x2340f8, amostrador 0x234750): +0x40 duração, +0x48 bloco D com
    ponteiros relativos: D+4 posições, D+8 índice de posição por quadro e
    osso, D+0xc nº de rotações, D+0x10 rotações (x, y, z, w), D+0x14 índice
    de rotação, D+0x24 nº de quadros, D+0x28 tempos, D+0x2c/0x2d largura do
    índice (8 = byte). osso b no quadro k = tabela[índice[k·nº_ossos + b]];
    entre quadros interpola (ou pega o mais perto). STEER_LEFT: 6 quadros a
    30/s em 1/6 s; o Buggy/Controls e o Truck/Controls são o mesmo arquivo.
- 0x187060 lê corpo+0x3c4 = direção suavizada (igual ao 0x370 nos 11 save
  states). 0x190e50: tempo = |s|·duração, espelha com s > 0 (flag 2 no
  0x22f200). Espelho no remake: cada osso pega o do outro lado (tabela do
  .skl), posição com x trocado e rotação (x, −y, −z, w). O quadro 0 do
  STEER_LEFT já é simétrico assim.
- O ROOT da animação fica em (0, 1.1315, 0.3032) do piloto: é a origem =
  ARSE − isso do doc. O ARSE tem matriz (90° em y na maioria dos buggies),
  mas o piloto não gira com ela.
- Textura: material único "WHITE" num atlas 512x512 (braços, camisa,
  calça, capacete, luvas, óculos, rosto, botas; o UV da malha cai no
  Characters/Textures/Template/Rider_Template.bog). O jogo monta o atlas com
  as 5 camadas de cada parte (Characters/Textures/#hash/<parte>/
  RIDER_NN_{BASE,DETAIL,PRIMARY,SECONDARY,WRINKLE}_<parte>, 12 roupas) e as
  cores do piloto; isso ainda não foi portado. O remake usa o
  rider_fury.bog (00970, roupa "Fury" pronta, 256x256).
- Material em camadas (0x1a6300 escolhe a parte pelo nome, 0x1a69c8 monta):
  4 camadas da tabela 0x838a40 com textura RIDER_%02d_<camada>_<parte> e
  cor RGBA do perfil (perfil+8 → +0x20 + camada·0x10, gravada no +0x30 do
  nó), mais RIDER_%02d_DETAIL/WRINKLE/SPEC_<parte>; sem peça usa
  /Setup/Init_White e Init_Seethru. A peça (RIDER_NN) vem do byte +0x1c do
  item (0x1a4610). Nas camadas o que importa está no ALFA (converter com
  gob_tex2png --alpha): BASE opaco, PRIMARY e SECONDARY = máscaras (o logo
  SINISALO do RIDER_04 está no alfa do PRIMARY), DETAIL = desenho com alfa
  até 180, WRINKLE = sombra cinza (alfa 136..254). Falta: a conta da mistura
  e onde ficam as 4 cores do perfil na RAM.
- Piloto do Matheus (RAM dos save states, objetos de textura em 0xd27490):
  roupa, braços, calça e capacete RIDER_04, óculos RIDER_05, botas e luvas
  RIDER_03, rosto FACE_MALE_FACE05; na foto dele: verde, branco e preto.
- Direção visual das rodas 0x21def8 / 0x20ede8: body+0x3c0 = direção ·
  lerp(Max_visual_steer_zero, _full, mph/SpeedMax), SpeedMax = curva
  BasicSteering/Angle_vs_speed (params+0x4e8 = 100); nos buggies 30°/30°.

## Terreno (STREAMT/RX/RX01.000)

- tools/extrair_material.py decodifica o stream (formato no cabeçalho do
  script): 64 tiles de 128 m, patches 9x9 (FUN_0029bcb0, tabela 0x550c00),
  altura = FUN_00299a60 com a diagonal (i+1, j)-(i, j+1). A mesma diagonal
  do HeightMapShape3D do Godot (Godot Physics e Jolt, testado). Grade de
  1 m em assets/terrain/rx01_height.bin; o .bin antigo errava 1,5 m em
  média (até 32 m).
- Material: entrada E do tile, uma a cada 2 m, byte0 & 0xF = índice i ->
  Material_(i+1) do Levels/RX_01/Env/Materials.xml (unpacked/xml/12280,
  copiado em data/materials_rx01.xml). Mapa em rx01_material.bin.
- Os .bin ficam no layout do jogo (linha = z, coluna = x); terrain.gd
  transpõe na carga (ver Mão abaixo).
- Conferido: contato das rodas (W+0x130) e material (W+0x140) dos 6 save
  states da largada: altura a 0,1 mm, material 2 (COMMON_3 TARMAC) igual.
  tests/teste_chao.gd + tests/ref_ram_chao.json.
- Largada: centro das rodas no jogo (580.8, z 1564.3), frente a −115,1°;
  no remake (540.3, 580.8) e −154,9° (main.gd SPAWN_XZ/SPAWN_YAW).
- Atrito por material (0x20d568): cada roda no chão copia 3 campos do
  registro do material embaixo dela (veículo+0xd0 + idx·0x60, montado na
  carga pro pneu do carro) pra corpo+0x750+12i: atrito, Hardness, Damping;
  material −1 dá (1, 0, 0) e não soma. Médias 0x780/0x784/0x788 = soma das
  rodas com material / rodas no chão (0x3c8); no ar, 0. Tabela do carro =
  24 registros (o loader 0x3a9608 aloca 0x900), igual nos 6 save states
  (tests/ref_ram_chao.json "tabela").
  Registro (conferido na RAM, 13 materiais): +0x00 atrito = override
  "FRICTION TYRE <classe> <valor>" do Materials.xml (DIRT_BUDGET: 0.80
  terra, 0.69 fora da pista, 1.10 asfalto), +0x04 Hardness, +0x08 Damping,
  +0x10..0x2c cores de poeira e sujeira, +0x3c WheelJitter, +0x40
  Bounciness, +0x44 Sink, +0x4c Rockiness. Classe do pneu =
  vehicles.xml DefaultConfig Tire (todos os buggies: DIRT_BUDGET).
- Quem usa: a elipse (0x2101e0) e a tração (0x20e8d8, só com
  TractionControl ligado, desligado nos buggies) usam o atrito da roda com
  min(·, 1); a elipse desliga com atrito ≥ Disabling_friction (2.0,
  params+0x43c). Freio, derrapagem e o resto usam a média 0x780, que acima
  de 1 cai no valor "Special" do trio. Damping médio = arrasto do chão
  (0x20e5e8): 0.2 fora da pista, 0.1 cascalho, 0 terra comum e asfalto.
- Não usados pelo buggy (varri 0x100000..0x480000 decompilado): a média da
  Hardness (0x784) não tem leitor; Bounciness (+0x40) e Sink (+0x44) são
  carregados e copiados mas ninguém lê (nem da tabela global DAT_007f4bf8,
  que só é lida pra nomes, IsDirt +0x48 e WheelDirtRate +0x54). A função
  0x238e08 que lê +0x754 é de outra classe de veículo. Os outros leitores
  do material (veículo+0xa88) são poeira, som, marca de pneu e sujeira da
  roda (esta usa o giro W+0x48 e a patinada 0x600).

## Som de pneu, suspensão e pouso

Porta em sfx_carro.gd; samples do jogo via tools/sfx_jogo.py (assets/sfx,
fora do git); parâmetros em data/sound_database.xml (Audio/SoundDatabase.xml).
- Bancos numa corrida no RX01 (RAM do SPU de 17 save states): Audio/SURFACE.bnk
  e Audio/Collide.bnk ("Coll_Big"). Suspen.bnk e VEHICLE.bnk (#01b65ec7) nunca
  carregam. Formato 989snd "SBlk" v3 no cabeçalho do sfx_jogo.py. Índice do
  som = posição da entrada no Audio/SampleBanks.xml. Taxa com tom 1.0 =
  48000·2^((CN + CF/128 − 196)/12) (registrador de pitch das vozes).
- Só veículo humano tem som de pneu (0x36bb68/0x36f460): objetos das rodas 0
  (FL) e 1 (RL), mais um do patch secundário na FL. Suspensão só com um
  jogador.
- Entradas 0x36fa28: spd = |v|(0xe0)·2.2374/140, side = |0x410|·2.2374/60,
  as duas x < 0.025 → 40x² e no máximo 1; ws = 0.5 por roda com 0x600 > 0.2.
  Dono+0x178 = 0.4·anterior + 0.1·média(d susp/dt de FL e RL), limitado a ±1.
- Roda 0x370548 (por quadro): material W+0x140 (−1 = 0) → DB+0x70+4i (pelo
  SFX do Materials.xml da pista, 0x377ce0); água se veículo+0xaec+4i > −0.05.
  Sample novo: para, toca o outro e trava 0.07 s. São 2 handles por roda
  (W+0x178/+0x17c, índice em +0x180): para o atual, troca de handle e toca
  no outro; volume e tom só vão pro handle novo. Parar = vtable +0x1c do
  handle (0x264f28, classe 0x587c48) -> 0x25afa8 -> 0x6773d0 = comando 0x13
  do 989snd (StopSound): key-off, a voz desce pelo release do ADSR do tom
  (ADSR1/ADSR2 em +0xa/+0xc do tom no banco). Dirt: ataque exponencial
  ~0.48 s, release linear 0.17 s; loop do cascalho (GRAVELEMENT2): ataque
  na hora, release 0.17 s. No cascalho escuro do RX01 (GRAVEL/ROCK em
  células de 2 m misturadas com terra) a troca Gravel <-> Dirt acontece ~2
  vezes por segundo derrapando (tests/gravar_cascalho.gd). Patch com Volume
  0 para.
  No ar o volume vai a 0 (tom fica). susp = clamp((W+0xe8 + SuspensionOffset)
  ·SuspensionScale, 0, 1). Volume e tom: fórmulas no cabeçalho do
  sfx_carro.gd (offsets do patch: 0x2c..0x4c tom, 0x50..0x7c volume, com
  0x5c MinThreshold e 0x60 SideSpeed). Conferido com o pitch das vozes do SPU
  em 7 save states (tests/teste_sfx.gd): pior 0.010.
- Pouso 0x370df0: tempo no ar com 0x8a8 = 0; ao voltar com mais de 0.1 s,
  0.5 + 0.5·min(1, t), x Landing.Volume duas vezes, x SFX; material da FL.
- Suspensão 0x36e498 → 0x36e2d8 (Small e Large): |0x418| ≥ 20 mph; dono+0x178
  passa o Threshold (subida) → toca com Probability; espera MinRetriggerTime;
  volume (1 − VolumeSpeed·(1 − spd))·Collision·SFX, tom 1.0.
- MasterSettings: SurfaceVolume 0.5, CollisionVolume 0.8, SFXVolume 1.
- Grãos do 989snd (som_jogo.gd), pelo BlockSoundHandler reimplementado no
  jak-project (game/sound/989snd: player.cpp "handlers tick at 240hz",
  blocksound_handler.cpp, sfxgrain.cpp, loader.cpp ReadGrainV2): a espera
  (s32 depois do opcode) vale ANTES do grão; contagem = espera do próximo +
  retorno do grão (RAND_DELAY devolve 0..dado). Opcode = tipo << 24 | 3
  args s8: RAND_PLAY (25) opções/grãos por opção/anterior (não repete),
  RAND_PB (27) % da faixa, SET_REGISTER_RAND (31) registrador/mín/máx. Tom:
  vol s8 (< 0: -1..-4 registrador do som, -5 sorteado), PBLow/PBHigh em
  +8/+9. Cascalho (Gravel = filhos GRAVELEMENT1 vol 75 + GRAVELEMENT2 127):
  loop com espera 0..180 ticks (2.65 estalos/s), volume 90..115, ±2
  semitons. Terra (Dirt): as 2 camadas entram juntas depois de 60 ticks.
- Não confirmado: curva de distância 3D.
- Save state 110 (1ª curva): o PS2 tocava asfalto e o mapa diz cascalho nas
  rodas da frente, mas o material da FL na RAM (veículo+0xa88[0]) também é o
  5 (GRAVEL/ROCK): o mapa está certo. As rodas saíram do asfalto 0.07 s
  antes (andando pra trás pela velocidade, 113 km/h); o loop do asfalto
  (Tarmac, ADSR2 0x9fcd, release linear shift 13) leva 0.34 s pra apagar
  depois do key-off e o loop do cascalho (GRAVELEMENT2) só entra 60 ticks
  (0.25 s) depois, então só as vozes do asfalto tocavam. tests/teste_sfx.gd
  confere ("som atrás do chão" e "material: FL RAM x mapa"; no 170 a FL
  está 1.2 mm depois da divisa da célula e a RAM já tem a célula seguinte).

## Sujeira

- Objeto da sujeira: veículo+0xa80 (0xd0 bytes, 0x223948, criado no
  0x1fe280; também em (veículo+0xa64)+0x10). +0xc0 nível do carro, +0xc4 do
  piloto, +0xc8 = 1 se o modo de jogo tem sujeira (0x171960).
- **0x223e68** (do update do veículo 0x203930, um por quadro = 50 Hz no
  PAL; sem dt): com rodas no chão (corpo+0x8a8), piloto no carro
  (piloto+0x164 = 0) e v = |corpo+0x440| >= 0.5: d = min(v, 15)·k·5e-5,
  k = maior min(WheelDirtRate, 1) dos materiais das rodas (veículo+0xa88,
  registro veículo+0xd0+i·0x60, +0x54). Nível += d (0..1); o do piloto
  também (+ piloto+0x328·0.06 se (veículo+0xa6c)+0x8c+0x18). WheelDirtRate
  é 0.2 até no asfalto (0.3 na terra úmida): suja em qualquer chão.
  Depois do 0x223e68 o 0x203930 põe (veículo+0xa68)+0x58 = +0xc8·nível.
- Desenho: +0x98 é um pintor de alfa de vértice (0x3a8680, lista de malhas
  montada no 0x223a78; 17 no Renegade = carroceria, balanças, freios e
  amortecedores). Tipo 1 (0x3b3a78): alfa do vértice = max(alfa,
  nível·128), 300 vértices por quadro. Na RAM: todos os vértices com o mesmo
  alfa (d0: 10 = 0.083·128).
- Camada: o lote de material do .pingu (0x50 bytes) tem +0x08 = quantas
  texturas e +0x18 = slot da 2ª, desenhada por cima pelo 2º UV (o V4-32
  traz s, t, s2, t2). Na carroceria só o lote da pintura ("white") tem, e a
  2ª é a "dirt" (DIRT.bog do modelo = 8x8 vazio): vale a da pista,
  TrackProperties Dirt mDirtTextureName (0x1bf220, props+0x1c) =
  GEN_DIRT_DIRT em todas (Vehicles/Generic/Textures 128x128). Alfa = alfa
  do vértice x alfa da textura. As peças do pintor não têm camada (menos 2
  balanças de trás do Kraken), então só a pintura suja.
  Nas rodas (pneu e aro) a 2ª é a UNI_TyreOverlay (128x128, 4 bits, igual
  nos 46 pneus do jogo).
- Zera só no 0x223db0 (nível 0 e alfa 0 em todos os vértices): veículo
  inativo no 0x203930 e o método virtual +0xb4 do veículo (0x200b80,
  recomeço). Nada mais escreve o nível: a água NÃO limpa a carroceria.
- Lama das rodas (0x224418 -> 0x2242d0, com roda no chão; +0x10..+0x4c do
  objeto: de, para, cor, material, t, taxa, taxa alvo): quando o material
  da FL (veículo+0xa88[0]) muda, vai da cor atual pro DustColour (registro
  +0x10) com alfa WheelDirtAlpha (+0x50; 0 no asfalto = só o alfa cai),
  taxa WheelDirtRate suavizada (0.95/0.05), t += dt·giro da FL
  (W+0x48)·0.002·taxa (x10·patinada da RL, corpo+0x604, se passar de 0.1).
  Na água (veículo+0xae8) o alvo é o registro DAT_007f4bf8+0x20.
  Desenho (0x224148, chamado no desenho do modelo 0x22bba8 nos LODs 0 e
  1): a paleta de 16 cores da UNI_TyreOverlay vira cor·128 com alfa = alfa
  da lama x alfa original de cada entrada (+0x54..+0x90). Achado pela cópia
  da cor na RAM em 0x7f72b8.
- Save state do Matheus no Hinter Valley (lama, neve e água; 100% sujo em
  ~1 min): materiais da pista com WheelDirtRate 3.0 na lama (sujeira do
  carro com k = 1: 0.0375/s, cheio em ~27 s) e 2.0 na neve (DustColour
  quase branco: pneu branco). Registro da água (DAT_007f4bf8+0x20):
  DustColour 0, WheelDirtAlpha 0, WheelDirtRate 30 = o pneu limpa quase na
  hora e a lama (taxa 3) volta em meio segundo, como ele viu. Nível 1.0 e
  lama (0.69, 0.63, 0.54, 0.86) no save state.
- Brilho: o desenho da carroceria (0x22ace8) multiplica o reflexo por
  (1 - modelo+0x58), e modelo+0x58 = nível. Não portado (o remake não tem
  esse reflexo).
- Conferido (tests/teste_derrapagem.gd): drr_3 -> drr_2 (1.16 s) o jogo
  sujou 0.0089 e o remake 0.0091; lama da roda jogo (0.561, 0.486, 0.387,
  0.431) e remake (0.561, 0.486, 0.386, 0.432). Os save states saem no
  ler_savestate --json ("sujeira", "roda_suja").

## Poeira dos pneus

Porta em poeira.gd (nov/2026). Dados: Setup/Dust.xml (data/dust.xml) e
Levels/<pista>/Env/Dust.xml (data/dust_rx01.xml: Dust 32 grupos x 32
partículas, Dirt 16 x 32). Textura Sprites/WorldFXdust (atlas 2 x 3 de
nuvens; tools/fx_jogo.py -> assets/fx/poeira.png).
- Material (0x3a9608, registro de 0x60): +0x10 DustColour, +0x20 DirtColour
  (sem ela = DustColour x 0.7, alfa 1), +0x30 DustType (None = -1, Light 0,
  Medium 1, Heavy 2; Water 3 = água), +0x34 SkidmarkIndex, +0x38
  SkidmarkType, +0x58 DirtKickupChance (padrão 0.2), +0x50 WheelDirtAlpha
  (padrão 0), +0x54 WheelDirtRate (padrão 0.1).
- Tipo (0x3affb0, registro de 0x80 por tipo, conjunto CamSubject = carro da
  câmera e Other = os outros, só "Rear"): +0x04 tamanho inicial do quadro,
  +0x08 InitSizeDelta, +0x0c TargetSize, +0x10 TargetSizeDelta, +0x20 cor do
  quadro, +0x30 grupo de partículas (0x3b5868: Power, PowerRatio,
  MaxParticleAge), +0x38 CamMinLodDist, +0x3c/0x40/0x44 ParticleSpacing /
  LookAlong / MinLod, +0x48/0x4c InitSize / MinLod, +0x5c.. SpeedScale e
  afins (mph x 0.447; não estão no XML, não lidos na emissão).
- Emissão 0x225108 (por quadro): sai se |v| (corpo+0xe0) < 0.5. Rodas: o
  0x1f1ef0 pula as de índice 0 e 2 (as da frente), só as de trás soltam. Força =
  (|v| - 0.5)/35 menos um termo da roda (2 x a folga, até 0.5; com ele
  >= 0.5 a roda fica "sem material"), presa em 0..1. Por roda (emissores
  das rodas de trás): material veículo+0xa88[i] (registro em veículo+0xd0),
  cor = DustColour; troca de material: cor vai da atual pra nova em 1 s
  (sem material ou DustType -1: alfa vai a 0 e o tipo fica o de antes).
  Solta com tipo != -1, força > 0.1 e alfa > 0.1, senão para (0x227968).
  LOD = dist² da câmera (veículo+0xb0c) / CamMinLodDist², espaçamento =
  lerp(lerp(Spacing, LookAlong, olhar), MinLod, LOD), olhar = clamp(1 -
  frente do corpo (corpo+0xd0) . normal(carro - câmera)), tamanho inicial =
  lerp(InitSize, MinLod, LOD); cor x ((1 - sombra) + sombra x
  InShadowAmbientMultiply) (veículo+0xc0 e [0x7f48e0]+0x3c0, padrão 0.5:
  só escurece na sombra).
- No ar (0x225108, ramo sem água): X = folga da roda, registro do objeto de
  colisão do carro (veículo+0x9f0, construtor 0x14a9b0: +0x20 + i x 0x20 =
  normal, +0x10 desse = X; + = roda afundada, - = acima do chão). Termo da
  força = clamp(-2X, 0, 0.5); com ele >= 0.5 (25 cm) o material vira 0 (a cor
  vai a alfa 0 em 1 s, tipo de antes), senão é veículo+0xa88[i], que o
  0x2017a8 só troca com a roda no chão (W+0x10c != 0; W+0x140) e o reset põe
  -1. Ponto = roda no mundo (corpo+0x500 + i x 0x10) - up (corpo+0xc0) x
  (raio W+0x30 - max(X, 0)) - velocidade (corpo+0x90) / 60. A marca de pneu
  (0x20ff18) usa o mesmo ponto.
- 0x227c50: uma partícula a cada espaçamento no caminho desde a última, com
  a idade espalhada no quadro. 0x3af170: tamanho inicial ± Delta, final ±
  Delta (sorteio uniforme), alfa = alfa do registro x força, GRAVADO de
  volta no registro (no mesmo quadro a 2ª sai com força², a 3ª força³...);
  cor do vértice 0 x 0.3. Parada no mundo (sem velocidade).
- 0x3af590: tamanho = ini + (fim - ini)(1 - (1 - idade/MaxParticleAge)^4),
  alfa = alfa0 (1 - t²), t = idade / vida dela. Vida (0x3b5868): tabela de
  2^Power valores pela posição no grupo, MaxParticleAge / PowerRatio^nível
  (Power 1: MaxParticleAge, MaxParticleAge/PowerRatio, alternando).
- Desenho (0x3af590 só grava tamanho em +0x10/+0x14 e o alfa = (1 - t²) x
  alfa0 x 128 nos 4 vértices; o quadrado sai no VU1): tamanho do XML x 0.6 =
  metros (calibrado em prints do jogo; a conta do VU1 não foi lida). Alfa da
  textura do PS2: 0x80 = 1.0.
- Não portado ainda: Dirt (pedrinhas WheelSpinDirt e WheelDirtTrail do
  Effects/#3ffdac18, DirtKickupChance), o canto escuro, a sombra. A água
  está na seção Água.

## Objetos da pista (RX01)

Porta em objetos_rx01.gd + tools/rx01_objetos.py (nov/2026). O RX01 não tem
modelo no stream: Levels/RX_01/Env/Default/Default/Pingus/pingustream.header
é o log "Pools Total = 0 bytes. Models Total = 0 bytes" (StreamP e StreamW
vazios). Tudo vem do evento:
- Formato de chunks (#def5772a e RALLYCROSS.bin): u32 0x00030000, chunks
  F00DABCD, u32 tamanho (até o DEADDCBA, incluso), u32 tipo (hash), campos e
  chunks filhos, DEADDCBA. Campo = chave (hash) + u32, ou chave + u32 n + n
  bytes de texto preenchido até 4 (o preenchimento às vezes tem lixo: os
  textos conhecidos são 01ee2ec7 = nome do modelo, 489c80f9 = classe da
  entidade). Vetor = chunk filho com x/y/z em 484dc9b4, 3f4af922, a643a898.
- Instâncias (Event/Rallycross/Default/#def5772a, other/12290), raiz
  4939a99a: 1c85cac0 = pingus (um e9aba222 por modelo: nome + 7db6ffbc =
  quantas; UM grupo 1b05a8d9 com os 57 registros de 160 bytes na ordem dos
  modelos: matriz 4x4 com linhas = eixos do modelo no mundo e a 4ª =
  posição, +0x40 centro, +0x6c flags 0x04100000, +0x70 cor RGBA ~0.6);
  e0baf2b2 = bantams (um e9aba222 por modelo com 21fdb9c8 grupos 1b05a8d9:
  7db6ffbc = n, c32f9493 + 40 bytes do jogo em execução + n x 96 bytes:
  matriz 3x4 com escala, posição + 1.0, +0x40 cor RGBA ~1.0, +0x50 flags
  0x17000000); 24530fce = quadtree com índice das mesmas instâncias. 651
  bantams (o cabeçalho 1c85cac0 tem ef8c259e = 651). Posições no mundo do
  jogo (x 0..1024, z 1024..2048), em cima do relevo do StreamT (moitas a
  0.00 m de média; cada modelo tem a origem num lugar).
- Entidades (Event/Rallycross/RALLYCROSS.bin, other/12289): cIntroCamera,
  8 cStartPosition (posição 1 = (581.3, 201.8, 1564.5), direção (-0.907, 0,
  -0.421); a largada da RAM é (580.8, 1564.3)), 14 cInstantRespotBox (caixas
  de reposição), 6 cCrowdEffectBox, 4 cGenTrigger, 2 cLightDirectional, 32
  cFenceNodeEntity + 26 cFenceLinkEntity (cercas entre nós, com os .clm
  GEN_Barrier_RallyFence / SAM_Barrier_RallyFence / SAM_Crowd_BarrierTG).
  Cada uma com pos (3ef310bc), dir (74f784c3), tamanho (44c2fa64).
- .pingu = o dos carros (pingu2obj). Texturas: o .pfn (nomes por linha,
  o "raw" antes do bloco). As texturas da pista vêm DEPOIS dos modelos no
  archive (gob 12324..12402), então o find_png do pingu2obj (o maior índice
  antes) não serve: o rx01_objetos.py converte os .bog do RX01 direto.
- .bantam ("TNAB" em 0x44): +0x48 ?, raio, caixa mín/máx (vec4); +0x70 n
  materiais e onde (0x40 cada), +0x78 n desenhos e onde (16 bytes: slot da
  textura, ?, ?, início do pacote). Pacote = tag de DMA (qwc nos 16 bits de
  baixo) + VIF; os vértices vêm num UNPACK V4-32 no endereço 1, 2 qwords por
  vértice: (x, y, z, flag 0x8000 = ADC) e (u | R, v | G, B, A): UV = float
  sem o byte de baixo, cor RGBA nos bytes de baixo (0x80 = 1.0). Sem normal
  (luz assada). Lista de texturas = o #hash logo DEPOIS do bantam no archive
  (u32 n + n nomes de 128 bytes). Os do GEN_HayBale e GEN_Rock_Group (132
  bytes) e o .pfn de 13 bytes da WATER_puddle01 não foram extraídos em
  nenhuma pista: por eliminação são GEN_HayBale, GEN_Rock e water_puddle (as
  3 texturas do RX01 que sobram sem modelo).
- Colisão: Models/KDt/#crc32(minúsculo("<modelo>.kdt")) ^ 0xFFFFFFFF. u32 n,
  12 bytes, n registros de 0x70 = triângulo: plano da face + 3 planos das
  arestas (n, d com n.p + d = 0), caixa mín/máx com 3 cm de folga, flag
  (0x10); depois a árvore. Vértices = face com cada par de arestas. 16 têm
  nome pelo hash; 11 sem nome no dicionário do archive foram casados pela
  caixa (tools/rx01_objetos.py KDT_POR_CAIXA): chalés 01/02/03, US_Barn_1,
  cerca de chevron, placas 02/03, arquibancadas GEN_AM e US 02/03, barreira
  da torcida, alto-falante. Models/HsC/*.hsc ("CSH", o casco dos carros):
  só a cerca de plástico, a de madeira e o fardo (15 esferas); no jogo eles
  quebram (bantams *_Particle_*, pontos "particle Hay" no GEN_HayBale.pts):
  ver Objetos interativos. Moitas sem colisão nenhuma.
- Mundo do remake: base = colunas das linhas da matriz com x <-> z
  (Terrain.dir_do_jogo), posição Terrain.do_jogo: determinante -1, o Godot
  desenha espelhado certo (o "START" do arco sai legível).
- Bantam é pré-iluminado (sem normal): desenhado SEM luz, textura x cor
  do vértice x a cor de luz da instância (a luz "Bantam" do Environment.xml
  é 1.0 no sol). Com o sol do Godot as placas de folha de costas pro sol
  ficavam pretas e as de frente amareladas (prints do Matheus, nov/2026).
  Folhagem (Alder, pinheiro, moita): material do bantam +0x38 = 5 (0 em
  todo o resto); cada folha é uma placa TRIANGULAR com UV de ~-0.3 a 1.4 em
  volta do quadrado da textura, de borda transparente: textura presa na
  borda (repetindo, os cantos do triângulo mostravam pedaços cortados da
  textura, "placas soltas" no céu). O bit exato não foi conferido no exe.
- Cercas das entidades (cFenceNodeEntity/cFenceLinkEntity): só do editor. O
  exe não tem essas classes (lista de nomes de entidade em 0x579480..); as
  peças foram geradas por uma curva pelos nós (~3.2 m) e gravadas como
  bantams no #def5772a. 2 das 6 correntes não têm peça gravada e não
  aparecem no jogo (conferido pelo Matheus).
- Não portado: LOD (TREE_*_LOD1), cor de luz por instância, cIntroCamera,
  cInstantRespotBox (reposição), cGenTrigger, cCrowdEffectBox, as 2 luzes.

- Camada do lote de pingu (2ª textura pelo 2º UV), como o GS desenha:
  - O registro do lote (0x50 bytes em 0xD0 + i·0x50) passa pelo 0x289228:
    +0x08 = quantas texturas, +0x10 modo, +0x14 slot, +0x18 slot da camada
    (vira ponteiro na carga), +0x20 = marca do tipo (0x11111111 uma
    textura, 0x22222222 com camada). 0x289148 ajusta o modo pelas flags do
    modelo e põe +0x08 = 2 se +0x18 != 0.
  - Tipos do renderer (cPinguRenderer, construtor 0x28d340): 0x28dad8 =
    0x11111111 (DAT_007f4814), 0x28db40 = 0x22222222 (DAT_007f4818), 0x28dba8
    = 0x2e2e2e2e (DAT_007fdcac: modo & 0x40 com 2 texturas, +0x04 = 1), 0x28da78
    = sem textura. Cada um guarda 2 endereços de programa do VU1 (0x283/0x303
    no de camada).
  - Estado do GS: palavra de 64 bits por contexto (0x658b40 -> registradores
    no 0x658f50): bits 0..15 = ALPHA (0x42/0x43), 16..21 = PRMODE (IIP,
    TME, FGE invertidos; ABE, AA1, FST), 24 = FBA, 25.. = TEST (ATE, ATST,
    AREF, ...). Contexto 2 (+0x150) = a 2ª passada.
  - 0x2897f0 (lote com camada, chamado no 0x289908): 2ª passada = 0x36080044
    (0x360c0044 sem névoa): ALPHA 0x44 = (Cs - Cd) x As + Cd, ABE ligado,
    teste de alfa GEQUAL 1: a mistura comum.
  - As = alfa da textura (0x80 = 1.0) x alfa do vértice (V4-8 de cor, 0x80 =
    1.0). Nos carros o pintor de sujeira mexe nesse alfa (Sujeira); nos
    objetos da pista o artista pintou: GEN_PRO_StartArch02 (Start_DirtOverlay,
    textura preta com alfa 0..0x78) 40..128 por vértice, US_Barn_1 madeira e
    ferrugem ~0.4 em média, celeiro/cabana idem, Crowd_ColourChange ~0.8.
    O import de .obj do Godot não lê o alfa do vértice (v x y z r g b a):
    o rx01_objetos.py manda a malha da camada no modelos.json ("tris").

## Luz e névoa (Environment.xml)

- Leitor 0x1c15d8 (chamado na carga da pista pelo 0x174398; objeto global
  [0x7f48e0], 0x570 bytes). Lighting/Overbright: só ActualBrightness (+0x290)
  e GrassBrightness (+0x294) são lidos (TargetBrightness, Threshold, Power e
  Colour não). InSun (i = 0) e InShadow (i = 1), base +0x110·i: pares
  (Ambient, Sun), (Bantam, __dummy__), (Rider, RiderSun), (Vehicle,
  VehicleSun), um par por 0x40: 1º Strength +0x90 / Colour +0x80, 2º
  Strength +0xb0 / Colour +0xa0; Dir só no Sun do InSun (+0x70).
  DynamicShadow: Intensity +0x3c4, InShadowMultiply +0x3c8. Fog: Start
  +0x2c0, End +0x2c4 (sem End = DrawDistance Terrain +0x29c; +0x34 = 1),
  Density +0x2c8, Colour +0x2d0. DrawDistance: Terrain +0x29c, Instances
  +0x2a0.
- Névoa: 0x390a80 / 0x38f238 põem na câmera o far = DrawDistance Terrain
  (400 no RX01), Start/End em câmera+0x170/0x174 e a cor em +0x190. RX01:
  linear de 87.5 a 400 m, cor (0.48, 0.44, 0.42), cúpulas do céu sem névoa
  (Fog="0").
- Sombra dinâmica (0x1b3fe0): força = k x Intensity x ((1 - s) + s x
  InShadowMultiply) x ... (s = quanto o objeto está na sombra assada);
  RX01: 0.5 no sol. Na tela (print do Matheus na largada) o chão na sombra
  do carro fica 0.66 do chão no sol.
- Chão: a textura do relevo (assets/terrain/rx01_terrain.jpg) tem a luz
  assada (sombra do arco, arquibancadas, morros). No print do jogo o chão da
  largada é 78, 72, 66 e a textura ali 85, 75, 65: desenhada sem luz.
- Detalhe do chão: o renderer do relevo (0x1eb758, objeto com o
  env.header de 0x48 bytes em +0x10: tile 128 m em +0x24, +0x3c = 5.0)
  carrega "<pasta Env>/detail" (RX01: DETAIL.bog, 128 x 128 4 bits, RGB 131
  fixo e alfa 12..190) em +0xd0 e "/Init/White" em +0xd4. +0x3c vai pro
  renderer 0x7f6718 +0x1e4 (padrão 5.0 no 0x29ce38; 2x no LOD de longe em
  0x1ec898) e o 0x29ed98 faz +0x138/+0x148 = +0x1e4 x 16 x +0x1e8/+0x1ec.
  O renderer também guarda o ActualBrightness (+0xe4). A mistura e o +0x1e8
  ficam no VU1 (não achados). O .gob tem os 4 níveis de mipmap (0x158 =
  10880 bytes a partir do 0x15c): o nível 0 é o primeiro.
- PS2 sem tonemap. Godot faz a luz em espaço linear e o PS2 na cor da tela:
  o mesmo ambiente 0.66 clareava muito mais no remake.

## Céu (SkyDome)

Porta em ceu.gd (nov/2026). Environment.xml da pista (Levels/RX_01/Env/
Default/Environment.xml = xml/12282, data/environment_rx01.xml): SkyDome com
Outer (SKY_Bright_LowCloud, yOffset 12.5, rotation 234.8) e Inner
(BACKDROP_Asia_1, 23.4, 154.5), alpha 1, fog 0. O XML diz .clm; o loader
(0x1d62b8, FUN_00287f50) abre o .pingu de Levels/SkyDomes (textura pela
.pfn: SKY_Bright_LowCloud, BACKDROP_ASIA_1e). Leitura 0x1d5c40, registro de
0x40: +0 modelo, +4 yOffset, +8 rotation, +0xc rotationSpeed, +0x10 alpha
(1.0), +0x14 fog, +0x18 lightning, +0x20 tint (vec4, 0..2). Desenho
0x1d6500: pula alpha < 0.01; cor do modelo = tint com o alpha (fog = 0), ou
0.5 x cor do ambiente x tint; matriz = giro em Y (0x61e2a0 com
0x6891f8 = cos e 0x6893f0 = sin do fdlibm: linhas (c, 0, -s), (0, 1, 0),
(s, 0, c)) na posição da câmera + (0, yOffset, 0), escala 1; ZBUF com ZMSK
(registradores 0x4e/0x4f), Outer e depois Inner. As cúpulas têm raio ~43 m
(céu, y -27.5..18.7) e ~39 m (montanhas, y -26.5..-1.3, alfa em 4 níveis);
cor do vértice 1.0 no céu e 0.71 nas montanhas. No remake: ESCALA 70 em
volta da câmera (mesmos ângulos; relevo e objetos ficam na frente pelo teste
de profundidade), sem luz e sem névoa. Não portado: SunHalo, rotationSpeed
(0 no RX01), lightning.

## Mão (espelho)

- O jogo é mão esquerda: x direita, y cima, z frente; WHEEL_*_LEFT em x < 0
  no modelo e, no mundo, FL - FR aponta pra -(cima x frente) se lido como
  mão direita. O Godot é mão direita, então copiar os números direto
  espelha tudo (foi assim até out/2026; o Matheus confirmou no jogo).
- Carro: S = diag(-1, 1, 1). car.gd põe malha, suspensão (cCompPlace),
  rodas e volante embaixo de um nó com escala S, em frame do jogo (o
  teste_pecas continua comparando direto com a RAM). Física no frame do
  Godot: ponto do jogo -> car.corpo(p) = (p + model_offset)·S; esquerda do
  jogo = +X (w.left). Rotação em y e z troca de sinal sob S (em x não): o
  ângulo das rodas no jogo é -steer·vis_steer (steer + = esquerda no
  remake, então no jogo ângulo + = direita, como o STEER_LEFT espelhado com
  s > 0 do piloto). Volante: -rider_s.
- Mundo: W = transposição, remake (X, Y, Z) = (z − 1024, y, x) do jogo
  (Terrain.do_jogo / dir_do_jogo / pro_jogo). Inverter só o x também
  resolveria a mão, mas trocaria a diagonal das células do terreno.
  Pose de um carro do jogo no remake: W·T_jogo·T(−model_offset)·S, yaw do
  remake = 90° − yaw do jogo.
- Câmeras (cameras.xml): PosOffset/LOOK_OFFSET com x negado e Orientation
  com y e z negados (pseudovetor), no game_camera._parse.
- Sol: Sun Dir do Environment.xml do RX_01 (12282) passado por W.
- Física: espelho exato (accel igual; curva pra esquerda nova = curva pra
  direita antiga, Renegade e Mosquito com diferença zero; Sphinx igual até
  uma derrapagem de 48° em 8,6 s, onde 1 rpm de ruído cresce).

## Archive

- Busca por caminho FUN_0066c978 (0066d110 / 0066d270 / 0066d308): CRC32 de
  cada pedaço do caminho em minúsculas (refletido, tabela 0x7d3298, init −1,
  sem xor final), árvore varint no archive.bin (RAM 0x89ab50, 0x3d00b
  bytes). Ver re/indice_archive.py e data/arquivos.tsv.

## Pintura

- Textura "white" gerada em tempo real pelas camadas do XML 150xx
  (Buggy_NN_Base/Primary/Secondary/Detail + cores + decalques + número).
  tools/gerar_pintura.py faz igual.
- Camadas (vtables em 0x59e9a8 Text, 0x59e9f0 Box, 0x59ea38 Decal,
  0x59eb10 Sprite; [parse, desenha]): Sprite 0x2fecf8/0x2fedf8, Text
  0x2ffe30/0x2fffd8, Box 0x2ffac8/0x2ffc40, Decal 0x2ff9c0/0x2ffa40.
  Construtores 0x3011c0 (Sprite: Aspect 1, KeepAspect 0, Rotation 0) e
  0x301678 (Text: Scale 1, Aspect 1, Fit 0).
- Box: lê a caixa do .bed (cantos 0 e 2) e põe o centro e o tamanho no
  contexto (NDC, y pra cima = topo da imagem).
- .bed (caixas, logos, glifos): u8 1, u8 1, nome.tga, u16 largura, altura,
  quantos; cada item u16 pontos, pontos (s32 x, s32 y), nome, u16 0xffff.
  Coordenadas inteiras = fração da textura x 100000 (máximo 100000 exato;
  22656 = 29/128 na HUD_Digital). Lidas como 16.16 dão ~1.53 no fim da
  textura: com 1.5 as caixas saíam 1.7% pra fora (4 px em 512). Conferido
  nos quadros claros do número de 12 carros (escala 1.00) e nos logos.
- Sprite: cor = Diffuse x 128 (128 = 1.0). KeepAspect: se a caixa
  (largura/altura/Aspect) é mais larga que o retângulo do logo, encolhe a
  largura, senão a altura (logo inteiro dentro da caixa, centrado). Depois
  gira Rotation graus em volta do centro, anti-horário na imagem: o logo
  encaixa na caixa deitada e fica em pé depois (os ATTACK nas faixas pretas
  verticais do teto do Renegade). Reflection (0x5513a0: 0 None, 1
  Horizontal, 2 Vertical, 3 Both) desenha 2 ou 4 metades espelhadas.
- Text: largura e altura do texto pela fonte, x vezes Aspect x 4/3 (desfaz a
  correção da tela 4:3, então o dígito sai na proporção da textura; o "01"
  do HUD na tela mede 0.73 e o glifo 0.70). Fit (tabela 0x551480: 0 No,
  1 Vertical, 2 Horizontal, 3 Both): Vertical = altura do texto = altura da
  caixa, Horizontal = largura, Both = o menor; vezes Scale. Centrado, gira
  em volta do centro. Diffuse preto = número preto (o glifo é branco).
- Decal: DecalArea + ordem. A k-ésima camada Decal de uma área usa o logo
  <ÁREA sem espaço><k> do DefaultDecals do vehicles.xml (HOOD1, SIDE3,
  REARWING1 de "Rear Wing"...), pelo nome na BuggyLogos.bed (sem diferença
  de maiúscula). Conferido no print do Renegade: lado direito, de trás pra
  frente, ITP, ATTACK com OUTERWEARS embaixo, o número e elf (SIDE3, SIDE2,
  SIDE4, número, SIDE1). BUGGY_03 e BUGGY_04 (Sphinx) têm no vehicles.xml as
  chaves de moto (FRONT_01, NOSE...): nenhuma bate, ficam sem logo.
- Número: o texto da camada PLAYER_NUMBER é o número do perfil; perfil novo
  = nome "PLAYER", número "00" (0x56b0a0, ao lado de mRiderNumber). O print
  do save state mostra 2 dígitos pretos no quadro branco. Os pilotos da IA
  têm o número no Setup/AIPlayers.xml (00 a 99).

## Save state do PCSX2

Rodas: ponteiros em corpo+0x254 (W), curso W+0xe8, giro W+0x4c (a tag
0x585cc0 fica em W−0x1c e às vezes está sobrescrita). Lista de peças do
buggy: 21 pares (flag, ptr) em 0x11dbce0 (a.ram), matriz em linhas no
pacote VIF apontado (rodas no mundo, peças no frame do modelo).
`tools/ler_savestate.py` acha a câmera (vtable 0x5b3f30 em +0x68), o alvo,
o veículo (+0x2b0 → +0xf0) e o corpo (+0x9d4). Há várias câmeras de órbita
e só a ativa atualiza: ela é a de suavização final (+0x100) ~40/s. As
outras ficam como a introdução da corrida deixou (zoom 0.6027, 17.85/s) e
parado podem estar mais perto do carro que a ativa. Câmbio em corpo+0x2d0 (+0x08
marchas, +0x20 final, +0x9c embreagem máx, +0x60 rpm de subir). Motor em
corpo+0x2ac (parâmetros; estado logo antes, com rpm e limitador).


## Água

Porta em objetos_rx01.gd (agua_em), car.gd (_agua_passo, _arrasto, lama),
poeira.gd (ramo da água) e sfx_carro.gd (nov/2026). Save states do Matheus
na poça do RX01: Renegade_dentro_da_agua.p2s (parado) e
Renegade_andando_na_agua.p2s (61 km/h). tests/teste_agua.gd.
- Objeto da água (vtable 0xe842e0; o do RX01 em 0x10cad20): +0x10 centro,
  +0x20/+0x30/+0x40 linhas do giro (15° em Y), +0x50 meia-largura x, +0x58
  meia-largura z, +0x60 superfície (206.017), +0x70 cor (0.588, 0.607, 0.614,
  1.0). É a WATER_puddle01.pingu da instância: centro/meia-largura = caixa do
  modelo (x de -20.66 a 21.35, z de -19.71 a 20.05) e a superfície = y dela.
- 0x1bb098 (busca): testa antes a água da roda anterior, depois a lista
  (DAT_007f5334+0x2c). Profundidade = superfície - y do ponto; dentro =
  profundidade >= 0 e |d . linha0| < meia x e |d . linha2| < meia z. Grava a
  profundidade da última testada mesmo fora.
- 0x201c20 (por quadro): ponto = roda no mundo (corpo+0x500 + i x 0x10) com y
  - raio (W+0x30); veículo+0xaec+4i = profundidade, veículo+0xae8 = água da
  última roda. Também testa o meio do casco (0x9f0 +0x130/+0x140) contra a
  superfície e passa de DAT_0055052c/0x550528 chama 0x159d18 (carro afundado;
  não portado, a poça é rasa).
- Arrasto 0x20e5e8: ver Forças. Lama 0x2242d0: na água o alvo é o registro
  DAT_007f4bf8+0x20 (DustColour 0, DustType 3 = Water, WheelDirtAlpha 0,
  WheelDirtRate 30; material da FL na RAM = -2). Na RAM parado: t 0.10, taxa
  30, alvo (0.6, 0.51, 0.4, alfa 0) (com alfa 0 só o alfa cai).
- Espirro 0x225108 (ramo com veículo+0xae8 e profundidade > 0): material = o
  registro da água, cor = objeto +0x70 com alfa x 0.6 (de = para = cor, sem a
  troca de 1 s), força = (|v| - 0.5)/35 sem a folga, ponto = roda no mundo com
  y = ((y - raio) + superfície) / 2, sem o recuo de velocidade/60. Tipo Water
  do Dust.xml (MaxParticleAge 0.3, Power 0), textura Sprites/WorldFXwater_dust
  (atlas igual ao da poeira; só as 4 células de cima têm desenho).
- Marca de pneu 0x224c38: na água (profundidade > 0) não deixa marca.
- Som 0x370548: veículo+0xae8 e veículo+0xaec[roda] > -0.05 = material de som
  "Water" (string 0x5b1008) do SoundDatabase (Surface/Water em loop).
- Desenho: o lote da poça é transparente (+0x00 = 1) e a water_puddle
  (128 x 128, cinza 105) tem alfa 96..254 (PS2: 0x80 = 1.0). Vértices 0.73.


## Objetos interativos (cercas e fardos)

Porta em objetos_rx01.gd (INTERATIVOS) + tools/rx01_objetos.py (quebraveis,
JSON "interativos"). tests/teste_quebra.gd.
- Setup/InstanceDatabase.xml (xml 14849; data/instance_database.xml): por
  ModelName, <Interactive CollSkin Mass Friction Hardness ActiveResetTimeout
  AIObserve ClassName> + AngResistance, Destructible ShatterImpulse com os
  Fragment (Model + CollSkin), ParticleTrigger, CollisionSample (som). No
  RX01: Gen_Barrier_Rallyfence e SAM_Barrier_RallyFence = cObjectFlimsyFence
  (Mass 0, ShatterImpulse 2, 2 peças; a 2ª da SAM usa o casco da 1ª) e
  GEN_HayBale = cObjectTrackBlock (Mass 0.1, ActiveResetTimeout 10,
  ParticleTrigger Impact 0.2 / 0.1 s).
- 0x547738 registra as classes: cObjectFlimsyFence (base
  cObjectDestructibleFixed, fábrica 0x547b70, vtable 0x600a78),
  cObjectTrackBlock e cObjectTrackDebris (base cObjectInteractive, 0x547c30 /
  0x547c78, vtables 0x600500 / 0x600958), cInstantRespotBox, cNoRespotBox...
- 0x141640 (por passo, cerca): com o corpo ativo soma +0x60 dos contatos do
  corpo (lista em +0x180) e se ShatterImpulse² (+0x104) < soma chama 0x141908.
- 0x141908: uma vez só (+0x110), tira o corpo da cerca do mundo (0x23f970) e
  pra cada peça pega uma livre no estoque (0x1406f0; 0x140318 cria até 20
  por modelo) e 0x140cf0 põe ela na posição e no giro da cerca, parada.
  0x140758 (construtor da peça) não dá massa.
- 0x153390 (contato de um corpo com objeto parado; chamado pelo 0x153658 /
  0x154520 pra corpos e 0x154088 pras rodas do carro, corpo = veículo+0x70):
  pra cada ponto, j = -(1 + e) vn / (1/m + n.((I^-1 (r x n)) x r)) com o
  corpo de +0xc0 (1/m), +0x100 (I^-1 no mundo), +0xbc (restituição) e
  vn = (v + w x r).n; fica o maior. 0x141a48(j, cerca): ShatterImpulse > 0 e
  j > ShatterImpulse -> 0x141908. Se a cerca está quebrada (+0x110) soma
  n x min(j, 0.25) (0x54d190) em +0x150 (impulso: o integrador 0x23efa8 faz
  v += +0x150 x 1/m) e (0.2 r) x isso em +0x160, e devolve 1: o chamador NÃO
  cria contato. Já quebrada, devolve 1 direto. O 0.25 só é lido ali.
- 0x142698 (corpo do objeto): dinâmico se Mass > 1e-6, massa = Mass (t, a
  mesma unidade do carro), +0xb8 = Friction, +0xbc = Hardness (restituição);
  0x23eb88 guarda a massa em +0x78 e 1/m em +0xc0. A cerca (Mass 0) é
  parada; o 0x141640 (soma dos contatos) só age em corpo com massa, então
  quem quebra a cerca é o 0x153390.
