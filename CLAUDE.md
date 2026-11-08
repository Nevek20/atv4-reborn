# ATV4 Reborn

Remake em Godot 4 do **ATV Offroad Fury 4** (PS2, PAL, SCES_546.88), com o
objetivo de ficar **100% fiel ao jogo**. Os dados (física, câmera, peças,
pintura) vêm dos XMLs do próprio jogo e o comportamento vem do executável
desmontado no Ghidra. Nada de "parece certo": cada número tem que ter fonte
(XML, função do exe, save state ou vídeo).

## Como trabalhar comigo (Matheus)

- Português do Brasil, informal. Textos curtos. **Nunca usar travessão (—)**.
- Atuar como dev sênior: propor direção, revisar, apontar problema. Não só
  executar.
- Ciclos curtos e testados: muda, roda o teste, mostra o número, entrega.
- Toda entrega vem com:
  1. o que mudou (curto),
  2. o **commit como comando de cmd do Windows** pronto pra colar
     (`chcp 65001 >nul` + `git add ...` + `git commit -m "..." -m "..."`),
     **sem linha de co-autoria do Claude**,
  3. como rodar (abrir no Godot e F5, ou o comando).
- Antes de mudar física, rodar `python tests/rodar_testes.py` e comparar
  com as referências (ver abaixo). Se um número piorar, explicar por quê.

## Estrutura

```
car.gd               física do carro (portada do exe), visual das rodas
game_camera.gd       câmera de corrida do jogo (componentes do exe, 1/60 s)
camera_jitter.gd     tremida da câmera (Perlin por velocidade, só na terra, e sorteio na batida)
camera_piloto.gd     câmera do piloto (melhoria nossa): força G na cabeça, FOV e borrão pela velocidade, olhar pra curva e olhar livre
camera_orbita.gd     órbita da câmera de corrida (melhoria nossa, o Forza): analógico direito / mouse giram em volta do carro, soltou volta
suspension_visual.gd balanças, amortecedores e freios do jogo se mexendo
vehicle_data.gd      leitor dos XMLs (base + veículo) e peças de fábrica
main.gd              cena: terreno, carro, câmera, HUD (F1 esconde, F2 contador de FPS), menu de carros (Tab, V); VEHICLES = buggies, TRUCKS, EXTRAS (nossos), frota() = os três, configurar(car, v)
carro_glb.gd         carros extras nossos: junta as malhas do .glb no frame do jogo (carroceria, rodas, volante)
piloto.gd            piloto do jogo sentado no ARSE, braços pela direção (STEER_LEFT)
volantes.gd          volantes gerados, um estilo por carro (melhoria nossa, no lugar do do jogo)
motor_som.gd         som do motor: loops do Engine Simulator por rpm e carga (melhoria nossa)
sfx_carro.gd         som de pneu, suspensão e pouso do jogo (portado do exe); som_jogo.gd toca os sons 989snd
fumaca.gd            fumaça do escapamento (melhoria nossa com o efeito ExhaustSmokeTrail que o jogo não usa)
poeira.gd            poeira dos pneus (porta do jogo: Setup/Dust.xml, DustType/DustColour do chão, 0x225108)
pedras.gd            pedrinhas e borrifo de terra das rodas de trás patinando (porta do jogo: 0x3bb618, Sprites/dirt_rocks)
sujeira.gd           sujeira do jogo na pintura e lama nas rodas, pelo 2º UV (_camada.obj); nível e cor vêm do car.gd
painel.gd            painel funcional (melhoria nossa): ponteiros, marcha e luz de troca, amador x PRO
motor_treme.gd       motor e escape tremendo (melhoria nossa): separa as peças do cofre da carroceria
motor_anima.gd       ventoinhas girando e polias + correia 3D (melhoria nossa) por cima do desenho do jogo
luzes.gd             lanterna de freio e luz de ré acesas (melhoria nossa): lente pelos pixels da cor da luz
farol.gd             farol aceso (melhoria nossa, no estilo da lanterna de freio) nas lentes de farol do modelo; H liga
terrain.gd           relevo e material do chão da pista RX01 (do stream do jogo)
objetos_rx01.gd      objetos da pista RX01 (porta do jogo): casas, arquibancadas, arco, placas, guard-rail, pedras, árvores + colisão KDt
multidao.gd          multidão do RX01 (porta do jogo: RX01_Crowds.wahoo, fotos de gente em placas, UV animado pelo UVRGBAAnim.xml)
palha.gd             palha do fardo (porta do jogo: .pts + Particles.xml + WorldFX.xml), disparada pelo objetos_rx01.gd
ceu.gd               céu da pista (porta do jogo): cúpulas do SkyDome do Environment.xml (nuvens + montanhas) presas na câmera
data/                XMLs do jogo (física buggy_NN.xml, pontos, câmeras, peças)
assets/              modelos do pingu2obj: renegade, sphinx, buggy_NN, truck_NN, rodas; sfx (sons) e fx (fumaça) do jogo (fora do git)
tests/               teste de física sem tela + rodar_testes.py
tools/               scripts Python de extração (pingu2obj, pintura, savestate)
som/engine_sim/      um .mr do Engine Simulator por buggy (NN_) e por truck (tNN_, t13 = Lazarus), tools/gerar_motores.py
som/loops/           loops .wav de cada motor (lenta, on/off a cada 500 rpm), tools/gravar_loops.py
re/                  engenharia reversa: scripts do Ghidra, exe_util, dumps
docs/                engenharia_reversa.md (mapa do exe), derrapagem.md (código da derrapagem legível), assets.md, som_motor.md
```

## Comandos

```
:: testes de física (precisa do Godot de console)
set GODOT=C:\caminho\Godot_v4.x-stable_win64_console.exe
python tests/rodar_testes.py                  :: aceleração dos 3 carros
python tests/rodar_testes.py hs --veh 0       :: curva em alta no Renegade
python tests/rodar_testes.py accel --veh 1 --tune "{\"engine\":0.81}"
python tests/rodar_testes.py accel --veh 0 --mu 0.69 --amort 0.2   :: fora da pista
python tests/rodar_testes.py accel --veh 0 --hz 60                 :: passo NTSC (padrão 50 = PAL)

:: save state do PCSX2 -> valores reais do jogo
python tools/ler_savestate.py arquivo.p2s
python tools/ler_savestate.py arquivo.p2s --json estado.json   :: estado do carro pro remake

:: print do carro parado (na nuvem: xvfb-run -a ... --rendering-driver opengl3)
%GODOT% --path . -s res://tests/print_tela.gd -- print.png lado
:: + CAM_OFF=0.3,0.9,-4 CAM_ALVO=0,0.85,-2.6 câmera livre (frame do jogo); PICK=x,y;x,y diz
::   a malha, textura, UV e ponto do jogo embaixo de cada pixel do print; CULL=0 carroceria com as 2 faces
::   CAM_MODELO=1 põe CAM_OFF/CAM_ALVO no frame do modelo (os pontos do jogo e do PICK), CAM_FOV=40

:: peças da suspensão x RAM do jogo (130 matrizes, 6 buggies + Goliath, Buccaneer e Fireball), tremida e chão
%GODOT% --headless --path . -s res://tests/teste_pecas.gd
%GODOT% --headless --path . -s res://tests/teste_tremida.gd
%GODOT% --headless --path . -s res://tests/teste_chao.gd
%GODOT% --headless --path . -s res://tests/teste_curso.gd    :: curso parado x RAM (9 save states, até 0.6 cm)
%GODOT% --headless --path . -s res://tests/teste_capota.gd   :: vira tudo a VEL em chão plano: inclinação e capotagem, regra do jogo x antes
%GODOT% --headless --path . -s res://tests/teste_de_lado.gd  :: carro caído de lado e capotado: casco do jogo, carroceria e rodas no chão
%GODOT% --headless --path . -s res://tests/teste_mao.gd     :: espelho (lado das peças, esterço)
%GODOT% --headless --path . -s res://tests/teste_tremida_camera.gd
set VEL=20 & %GODOT% --headless --path . -s res://tests/teste_batida.gd   :: Storm na parede: velocidade da batida e tremida da câmera
%GODOT% --headless --path . -s res://tests/teste_freio.gd   :: patinada, ABS e trava
%GODOT% --headless --path . -s res://tests/teste_roda.gd    :: giro das rodas por torque (no ar, preso)
%GODOT% --headless --path . -s res://tests/teste_camera_passo.gd  :: câmera de órbita sem vai e volta
%GODOT% --headless --path . -s res://tests/teste_camera_ram.gd    :: câmera parada x RAM de 6 save states (4 buggies, 2 trucks)
%GODOT% --headless --path . -s res://tests/teste_camera_piloto.gd :: câmera do piloto: freada, curva, FOV, borrão, mouse (números de projeto)
%GODOT% --headless --path . -s res://tests/teste_camera_orbita.gd  :: órbita: solto = câmera do jogo, lados, 3 voltas, volta curta, chão, mouse
%GODOT% --path . --write-movie camera.avi --fixed-fps 60 -s res://tests/gravar_camera.gd -- 0   :: prévia: acelera, freia, curva e olha pro lado (EFEITOS=0 sem efeitos)
%GODOT% --headless --path . -s res://tests/teste_largada.gd       :: largada do Renegade no RX01 x vídeo PAL e save states
%GODOT% --headless --path . -s res://tests/teste_pedais.gd        :: freio parado, ré pelo freio, corte no ar (0x202df0)
%GODOT% --headless --path . -s res://tests/teste_derrapagem.gd    :: remake no estado da RAM: força por roda, 1.16 s de derrapagem, sujeira e lama das rodas
%GODOT% --headless --path . -s res://tests/teste_volante.gd       :: punhos do piloto no aro nos 25 carros (0 cm), giro do volante, braço (cotovelo, pulso, torção) e pulo por passo (VEHS=25, BANCO=x,y,z, AVANCO=m, PERFIL=1)
%GODOT% --headless --path . -s res://tests/medir_cabine.gd        :: folga da cabeça até o teto, olho da câmera do piloto x cabeça e cotovelo x porta, por carro
%GODOT% --path . -s res://tests/print_piloto.gd -- /tmp/pil          :: prints do piloto sem carroceria (VEHS=0,25 VISTAS=lado,frente,cima,maos,maos_cima,maos_lado; CORPO=1)
%GODOT% --headless --path . --fixed-fps 50 -s res://tests/teste_treme.gd -- 0   :: volante tremendo: parado, reto, derrapando, solto
%GODOT% --headless --path . -s res://tests/teste_som.gd           :: som do motor: loops, tom e crossfade nos 12 buggies, 12 trucks e o bônus
%GODOT% --headless --path . -s res://tests/teste_sfx.gd           :: tom do pneu x pitch das vozes do SPU em 7 save states; material da FL x RAM
%GODOT% --headless --path . --fixed-fps 50 -s res://tests/teste_ladeira.gd -- 0   :: pneu parado em barranco: som não pode piscar
%GODOT% --path . --write-movie cascalho.avi --fixed-fps 60 -s res://tests/gravar_cascalho.gd -- 0  :: derrapando no cascalho escuro: trocas Gravel/Dirt e áudio do pneu
%GODOT% --headless --path . -s res://tests/teste_motor_treme.gd   :: peças e faces do motor que treme nos 25 carros (VEHS=13,14 só esses)
%GODOT% --headless --path . -s res://tests/teste_motor_anima.gd   :: ventoinhas, polias e correia nos 25 (nada some, correia encosta)
%GODOT% --headless --path . -s res://tests/teste_luzes.gd         :: cor do vértice nos materiais e lanterna de freio e ré nos 25 (acende e apaga)
%GODOT% --headless --path . -s res://tests/teste_farol.gd         :: farol: lentes achadas (Hurricane 2, Storm 6, 4 trucks e o Lazarus), lente e brilho, acende e apaga
:: + print_tela com FAROL=1/0 força o farol aceso/apagado
:: + print_tela com FREIO=1/0 e RE=1/0 forçam lanterna e ré acesas/apagadas, COR_VERTICE=0 tira a cor do vértice
%GODOT% --path . --write-movie motor.avi --fixed-fps 60 -s res://tests/gravar_motor.gd -- 7   :: prévia: lenta, 7000 e volta (CAM_OFF/CAM_ALVO)
%GODOT% --path . --write-movie fumaca.avi --fixed-fps 60 -s res://tests/gravar_fumaca.gd -- 0  :: câmera presa no cano acelerando (FUMACA_COR=1 vermelha)
%GODOT% --headless --path . -s res://tests/teste_poeira.gd        :: poeira dos pneus na largada do RX01: parado não, asfalto não, terra sim, rastro no pulo
%GODOT% --path . -s res://tests/print_largada.gd -- largada.png   :: largada do RX01 na câmera de corrida sem HUD (comparar cor com print do jogo; QUADRO=n)
%GODOT% --headless --path . -s res://tests/teste_objetos.gd       :: objetos do RX01: 707 instâncias, no chão, céu, largada livre, guard-rail segura o carro
%GODOT% --headless --path . -s res://tests/teste_agua.gd          :: poça do RX01 x 2 save states: caixa, profundidade por roda, lama, arrasto, espirro e som
%GODOT% --headless --path . -s res://tests/teste_quebra.gd        :: cercas que quebram (60 km/h passa, 4 km/h segura) e fardo que sai empurrado e volta
set VEL=30 & %GODOT% --headless --path . -s res://tests/medir_perda.gd   :: quanto o carro perde na cerca e no fardo (0/30/60°), com x sem o objeto
%GODOT% --path . --write-movie poeira.avi --fixed-fps 30 -s res://tests/gravar_poeira.gd -- 0  :: sai pra terra na câmera de corrida (SEM_POEIRA=1, POEIRA_COR=1)
%GODOT% --headless --path . -s res://tests/teste_pedras.gd        :: pedrinhas: larga na terra, vira (VIRA=7): parado não, ~80 vivas, pro lado derrapando
%GODOT% --path . --fixed-fps 60 -s res://tests/gravar_pedras.gd -- 0 pedras   :: prints da largada na terra (QUANDO=0.6,1.0,1.4; SEM_PEDRAS=1, PEDRAS_COR=1, VIRA=1)
:: + print_tela com MOTOR_COR=1 pinta de vermelho as peças que tremem, VENTOINHA_COR=1 as ventoinhas que giram
%GODOT% --path . --write-movie previa.avi --fixed-fps 60 -s res://tests/gravar_som.gd -- 8   :: prévia com áudio (acelera e solta; VIRA=5 derrapa, SEM_MOTOR=1)
set VEL=110 & %GODOT% --headless --path . res://tests/teste_entrada.tscn   :: reto até VEL e vira tudo: quando passa de 20° (jogo: 110 não derrapa)
:: + SOLTA=1.3 solta o volante (DEPOIS=-1 contra-esterça, ACEL=0 solta o acelerador), DUR=8 segundos depois de virar
%GODOT% --headless --path . -s res://tests/medir_tremor.gd -- 60 tremor.csv  :: distância câmera-carro por quadro

:: carro extra NOSSO de um .glb no padrão Assetto Corsa (WHEEL_LF..., STEER_HR) -> assets/<nome> + data/vehicles/<nome>*
python tools/carro_glb.py <modelo.glb> Escort [--estatico 0.114,0.074] [--escala 1.25] [--massa 0.9] [--base buggy_12]
%GODOT% --headless --path . -s res://tests/teste_extra.gd   :: extras: curso parado x estático, casco, 0-100 e velocidade
set TEMPO_CARGA=1& %GODOT% --headless --path . -s res://tests/tempo_carga.gd   :: ms de cada etapa da carga (VEH=26 Escort)

:: casco de colisão de cada carro (esferas do VehicleWorld.hsc pelo id) -> data/vehicles/<id>_casco.json
python tools/casco.py <unpacked>          :: --tabela mostra a caixa de todos os cascos do archive

:: terreno do RX01 (alturas + material) a partir do stream do jogo
python tools/extrair_material.py <dados>/stream/RX01.000 assets/terrain --materiais <dados>/unpacked/xml/12280
:: objetos e céu do RX01 (posições + colisão -> data/rx01_objetos.json, Environment.xml -> data/environment_rx01.xml;
:: modelos, texturas e cúpulas do céu -> assets/rx01)
python tools/rx01_objetos.py <unpacked>          :: --so-json só o JSON; depois abrir o editor (importa os .obj)

:: checar um script sem abrir o editor
%GODOT% --headless --path . --check-only --script res://car.gd

:: sons de pneu, suspensão e pouso do jogo -> assets/sfx (wav + sons.json com o ADSR de cada tom)
python tools/sfx_jogo.py <unpacked>
:: textura da fumaça (Sprites/Particles, caixa Dust0), da palha (Snow0), da sujeira (GEN_DIRT_DIRT), da lama do pneu (UNI_TyreOverlay) e da poeira (WorldFXdust) -> assets/fx
python tools/fx_jogo.py <unpacked>
:: + print_tela com SUJEIRA=0.8 força o nível da sujeira, PAINEL=6900,137 fixa rpm e km/h no painel,
::   SEM_PAINEL=1 esconde o nosso (pra ver o que sobrou do modelo)

:: piloto (malha, esqueleto, animação da direção, textura) -> assets/piloto
python tools/piloto.py <unpacked>

:: assets dos 12 buggies (modelo, peças, freios, rodas, pintura; + <modelo>_camada.obj com o 2º UV)
python tools/gerar_buggies.py <unpacked> [<texturas>]   :: sem a pasta: "texturas" do lado da unpacked; para se não achar .png
python tools/gerar_buggies.py <unpacked> [<texturas>] --classe truck   :: os 12 trucks -> assets/truck_NN, data/vehicles/truck_NN*
:: só o alfa das texturas com furo (redes das janelas, treliça do Trident); o gerar_buggies já chama
python tools/alfa_texturas.py <unpacked>
:: só a pintura (cores, logos e número "00"; --numero 27, --sem-decalques); depois reimportar no Godot
python tools/gerar_pintura.py <unpacked> BUGGY_10 assets/renegade
python tests/teste_pintura.py <unpacked>      :: caixas do .bed x quadros do número (12 carros) e logos do DefaultDecals

:: motores do Engine Simulator (12 .mr) e dinamômetro sem tela (Linux)
python tools/gerar_motores.py
bash tools/engine_sim_dyno/preparar.sh
tools/engine_sim_dyno/build/dyno som/engine_sim/08_mckenzies_gm_ls6.mr
python tools/gravar_loops.py [08 11]          :: loops de 2 s on/off a cada 500 rpm -> som/loops

:: caçar coisas no exe
python re/exe_util.py SCES_546.88 str NOME | jal 0xENDERECO | words 0xEND 32
```

Na nuvem (Claude Code web) o `.claude/hooks/session-start.sh` instala o
Godot 4.7.1 de Linux, Pillow e zstandard e já deixa `$GODOT` pronto.
O projeto roda em Forward+ (padrão) e o xvfb só tem OpenGL (Compatibility,
conta de cor diferente). Pra ver igual ao PC: `apt-get install -y
mesa-vulkan-drivers` e rodar com `VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json`
e `--rendering-method forward_plus --rendering-driver vulkan` (lavapipe, lento).
Os arquivos do jogo ficam no repo privado `Nevek20/atv4-dados` (exe,
stream, unpacked). As texturas não vão pra lá: saem do unpacked com
`python tools/gob_tex2png.py <dados>/unpacked/gob --out <dados>/texturas`
(uns 6 min).

Ghidra headless (Ghidra 12.1.3 + extensão ghidra-emotionengine-reloaded).
Na nuvem: `bash re/instalar_ghidra.sh` baixa os dois e importa o exe com a
análise (~7 min) em `~/ghidra_proj` (projeto `atv4`).

```
analyzeHeadless <proj_dir> atv4 -process -noanalysis -readOnly ^
  -scriptPath re/ghidra_scripts -postScript DecompRefs.java saida.c lista.txt
```
`lista.txt` = um endereço `0x...` ou uma string por linha; decompila as
funções que contêm o endereço ou referenciam a string.

Arquivos do jogo ficam fora do repo, na pasta de engenharia reversa do
Matheus: `C:\Users\Guida\Desktop\Estudo de programação\ATV 4 Engenharia reversa`
(`unpacked\` com other/raw/gob/xml, o exe, os scripts antigos).

## Referências pra conferir (o jogo de verdade)

- **Save state do Renegade** (151 km/h, 4ª, sem acelerar): massa 1.2 t,
  CoM (0, 0.639, -0.4), marchas 18.2/11.9/8.9/7.1/5.9, final 1.1636,
  embreagem máx 0.6127, rpm 6582, torque -0.094 kN·m, curso frente
  ~0.22-0.25 / trás ~0.11-0.13, câmera (longe) zoom 0.41, suavização 40/s.
- **Speedrun do Sphinx** (versão NTSC = física a 60 Hz; atv4-dados/videos,
  parte_00_00, largada em 25 s; relógio da corrida + HUD em mph lidos quadro
  a quadro, tabela em tests/rodar_testes.py). Carro pela ficha da tela de
  opções: DIRT PREMIUM, 269.9 HP (motor 1.0), 2204 lbs (BodyMass L2),
  embreagem L2 (troca 2->3 para 0.28 s); motor 1.0 = câmbio Prototype, que
  libera a final custom 0.61. A 60 Hz o remake fica a 1.2 mph.
- **Renegade PAL** (gravação do Matheus no RX01, sozinho na pista, de
  fábrica = 440.6 HP; tabela em tests/teste_largada.gd) + save state
  patinando a 48.7 km/h em 1ª: 6893 rpm, roda de trás 34.09 rad/s (0x600
  0.26, 0x610 0.32), 8.0 kN por roda traseira (elipse 8.17 x 0.98).
  Mais 4 save states da largada (5_a_10, 15_a_20 e os _teste_2 do Matheus,
  ainda fora do atv4-dados/savestates): patinada de trás / rpm 0.48 /
  1379 a 8.6 km/h, 0.48 / 1568 a 9.8, 1.20 / 4763 a 19.8, 1.38 / 5766 a 22.1
  (teste_largada imprime remake x jogo). No vídeo, as barrinhas do lado do
  conta-giros são acelerador (verde) e freio (vermelho).
- **Derrapagem** (4 save states do Matheus a ~120 km/h na terra, volante
  todo e acelerador; tests/ref_derrapagem.json): forças por roda e 1.16 s
  de derrapagem batem (tests/teste_derrapagem.gd: 0.13 kN por roda, 0.4 m no fim).
  Mais 5 segurando o R1 do controle (= botão da embreagem, "freio de mão"),
  virando e acelerando: embreagem aberta (0x2ec = 0), motor batendo no
  limitador (~8000 rpm), Clutch Turn em 0. O remake bate (rpm, embreagem e
  força por roda). Segurar não faz Clutch Turn: ele só começa ao SOLTAR. Todo .p2s
  traz Screenshot.png: o relógio da corrida dá o tempo entre save states.
  Derrapagem natural ("SLIDE - Steer hard into turn" no treino): virando
  tudo a 173 km/h o remake chega no save state "170" (133 km/h, 35.7°,
  82°/s, HUD 114) em 1.6 s, e o HUD marca 130 / 160 quando solta, como o
  Matheus leu no jogo. O velocímetro do jogo é ~1.06 x a velocidade PRA
  FRENTE (cai quando o carro fica de lado). tests/teste_entrada.tscn.
- **Gravação PCSX2 do Renegade**: carro ocupa ~27% da largura (em 4:3) a
  122 km/h na câmera perto; bate com a câmera portada.
- **Buccaneer de fábrica na largada do RX01** (2 vídeos PAL do Matheus,
  nov/2026; HUD lido em TODOS os quadros por um leitor de dígitos:
  tests/ref_buccaneer_video.json, tests/teste_truck_video.gd). Reto: 1ª e 2ª
  batem quase número por número (5..103 km/h a 1-2 km/h; limitador da 1ª 68,
  da 2ª 103; 2ª aos 3.4 s, 3ª aos 6.2-6.4 s): motor, câmbio, embreagem e
  tração dos trucks conferidos. Na 3ª o jogo sai da pista e sobe um morro
  (platô de 111 km/h) e o remake segue no asfalto: caminhos diferentes, não
  compara. Nesse truck o HUD do jogo mostra a velocidade direto (o "1.06 x"
  saiu de save states derrapando com o acelerador no fundo). Curva (volante
  todo pra esquerda a ~102 km/h, acelerador no fundo): o jogo e o remake
  escorregam, rodam (148° em 2 s no remake; "Wrong Way" no jogo) e caem pra
  ~20 km/h, mas o HUD do jogo começa a cair ~0.3 s antes. Falta save state
  na curva pra separar física, HUD e o instante em que virou.

## Fatos que já custaram caro (não reabrir sem motivo)

- Arquivos de física = ordem da lista do jogo: 15145 é a base E o 1º buggy,
  15146 o 2º... Renegade = 15154 (BUGGY_10), Sphinx = 15148 (BUGGY_04).
  O 15150 é o Phantom (já usamos por engano).
- Peças de fábrica: `data/vehicles.xml` DefaultConfig + `data/upgrades.xml`
  (efeitos). Embreagem máx usa a soma das peças de MOTOR, não o Clutch_Level.
  Relação final (0x21d2c8): GearboxLevel_Level0/1 dão FinalDriveRatio
  0.45/0.53; Level2/3/Prototype dão CustomFinalDriveRatio = a custom
  (GearRatioTuning FinalDrive, 0.61). RAM: Inferno, Bulldog, Phantom e
  Buccaneer de fábrica (Level0) 0.45; Renegade, Storm (Level3) e Goliath 0.61.
  Até out/2026 o remake usava sempre a custom (achado só com carros de
  câmbio Level3/Prototype). O Sphinx do b.p2s dá 0.61 com motor de fábrica:
  aquele Sphinx tinha câmbio comprado. Os efeitos das peças SOMAM (cada tipo,
  preso em 0..1); de fábrica nenhum tipo se repete fora o motor.
- A câmera mira a ORIGEM DO MODELO (veículo +0xaa0), não o CoM.
- Zoom -> FOV: meia-altura do frustum = 0.375/zoom (tela 4:3), KEEP_HEIGHT.
- Blocos: nunca pela posição no unpacked. data/arquivos.tsv (índice do
  archive, re/indice_archive.py) dá caminho -> bloco. Corrida usa
  Models_4K; as peças do carro N vêm DEPOIS do BODY dele (pasta alfabética).
  SANDCAR 4K = 21059/21060; 21973/21974 é TYRE_GENERIC_RALLY 5K.
- Suspensão = cCompPlace_* do exe (docs/engenharia_reversa.md, Peças): eixo
  da balança = linha 2 da matriz do ponto A_FRAME_*, ângulo atan(x/r). Roda
  e freio não giram com a balança. tests/teste_pecas.gd confere com a RAM
  de 6 carros (save states em atv4-dados/savestates: Bulldog, Phantom,
  Storm, Inferno; Renegade e Sphinx são os a.p2s/b.p2s), inclusive a frente
  do Bulldog em x, a traseira do Phantom e o Storm em z, rally e estepe.
  Trucks (eixo rígido): LeftFrame/RightFrame giram tan(x / W.x) (tan, não
  atan) com W = WHEEL_FRONT_*_VISUAL (o jogo acha o ponto pelo começo do
  nome, na ordem do arquivo); RearAxle (Axle + Rear_Arm) gira em volta do
  ARM_PIVOT até o meio das rodas de trás. Goliath (goliath_dirt_budget.p2s)
  e Buccaneer (Buccaneer_Standard.p2s) batem com erro 0 (docs Peças,
  suspension_visual.pose_truck).
- Modelos: o pingu2obj vira os triângulos pelas normais do jogo e o Godot
  descarta a face de trás (`MODEL_CULL`). Total de materiais do .pingu em
  0xAC (0xBC conta menos).
- Carroceria usa a textura "white" = pintura gerada (tools/gerar_pintura.py).
  Logos e número (camadas Decal e Box/Text do XML 150xx, docs Pintura):
  caixas do .bed = fração x 100000 (não é 16.16); a k-ésima Decal de uma área
  usa o <ÁREA><k> do DefaultDecals (HOOD1, SIDE3, REARWING1); KeepAspect
  encaixa o logo na caixa e DEPOIS gira; número = "00" do perfil novo, altura
  = caixa x 0.55. Conferido no print do Renegade (ITP, ATTACK, OUTERWEARS,
  00, elf na ordem). Sphinx e BUGGY_03 ficam sem logo (o vehicles.xml deles
  tem chaves de moto). Depois de gerar, o Godot precisa reimportar a
  pintura.png (abrir o editor ou `--headless --import`), senão usa a velha.
- Cor do vértice (car.gd COR_VERTICE, material_do_jogo): o .pingu tem RGBA
  por vértice (0x80 = 1.0, até 2.0) e o PS2 multiplica a textura por ela:
  sombra "assada" do modelo e a cor das lanternas. Até out/2026 o remake
  ignorava (lanterna do Renegade branca: vidro claro x vértice 167, 24, 24;
  gaiola do Mosquito quase branca). O pingu2obj cortava em 1.0: agora sai
  codificada (docs/assets.md, pecas.json "cor_vertice": 2). Vale pra
  carroceria, rodas, peças, volante do jogo e os shaders por cima (sujeira,
  ventoinha: car.cor_k()). Sem rodar o gerar_buggies de novo o .obj velho
  funciona, só sem o acima de 1.0.
- Import do Godot: o .obj só é reimportado quando ELE muda; o .mtl não conta.
  Um gerar_buggies com a pasta de texturas errada (out/2026) gerou .mtl sem
  textura e o carro ficou branco; rodar de novo com a pasta certa não
  adiantava (o .obj saía igual). O pingu2obj põe "# mtl <md5>" no topo do
  .obj e o gerar_buggies para se a pasta de texturas não tiver .png.
- Halos do jogo (out/2026; até então achávamos que o jogo não usava os
  pontos BRAKE_LIGHT, porque o nome não está no exe): Setup/VehicleHaloMap.xml
  (data/vehicle_halo_map.xml) liga nome de ponto -> halo (VehicleHalos.xml,
  data/vehicle_halos.xml) + comportamento: BRAKE_LIGHT1-6 "BrakeLight"/Brake,
  REVERSE_LIGHT1-2 "ReverseLight"/Reverse, HEAD_LIGHT1-3 / FRONT_HALO1-10 /
  REAR_HALO1-5 / Night. O 0x203930 acende por quadro: freio com 0x390 >= 0.1,
  ré engatada, Night sempre (carro ativo); 0x2260a0 sobe 4/s e apaga na hora.
  RAM: halos de freio acesos com freio 1.0 (a.p2s, storm.p2s); nos prints do
  Screenshot.png aparece o brilho laranja com raios. Nenhum carro do jogo tem
  ponto HEAD_LIGHT/FRONT_HALO: o farol "Night" existe e nunca aparece. Os
  LIGHTRIG comprados (Lighting, 8 modelos Small/Large pelo LightRigCategory,
  mIsPhysical false) são só modelo, sem halo. Desenho: textura
  Sprites/lightglow2alpha (o desenho é o alfa; caixas GLOW e SPIKE), uma
  camada por Layer, tamanho Width/Height x 0.3 m (medido nos prints), nível
  HIGH (os raios a ±0.4 rad aparecem). docs/engenharia_reversa.md, Halos.
- Lanterna de freio e luz de ré (melhoria nossa, car.gd LUZ_FREIO,
  luzes.gd): no lugar do halo do jogo (o Matheus preferiu o nosso, out/2026).
  Lente = PIXELS da cor da luz (vermelho no freio, branco na
  ré) na cor final (textura x cor do vértice) até 15/12 cm do ponto,
  amostrados a cada 1 cm no triângulo; a cópia por cima soma a cor x 6 + um
  miolo claro só nesses pixels (máscara no shader) e cada lanterna ganha um
  halo virado pra câmera (só de trás) no centro e tamanho dos pixels acesos.
  No Storm a lanterna é pintada na textura (vermelho + branco da ré) em
  triângulos grandes: acender o triângulo inteiro desenhava triângulos
  claros. Freio = brake_in (0x390, inclui o freio que o jogo segura parado:
  acende na largada; zera na ré pelo freio); ré = marcha -1. Ré só nos 5
  com REVERSE_LIGHT (Mosquito, Bulldog, McKenzies, Viper, Storm). Sem
  OmniLight: de dia pintava gaiola, estepe e chão de rosa.
  Trucks (out/2026, prints do Matheus): a cópia acesa é do triângulo
  inteiro, então o brilho agora fica no RAIO do ponto também no shader (no
  Shockwave a seta laranja, 23 cm acima do freio, acendia junto); ponto com
  lente de verdade (>= 20 amostras fora da pintura) não acende a PINTURA em
  volta (o teto vermelho do Truggy acendia; Renegade e Inferno também
  tinham um anel de pintura aceso); quem tem a lanterna PINTADA na pintura
  (Storm, Chimera, Punisher) continua. Pontos da mesma lanterna dão um halo
  só (HALO_JUNTA 0.30: Chimera tem 2 pontos por lanterna). Lente acesa até
  BRILHO_MAX 1.5 mantendo a cor (lente clara x 6 estourava pra salmão no
  Forward+). Branco da ré até saturação 0.4-0.55 (a lente creme do
  Shockwave não acendia). Pontos nossos (car.gd LUZES_NOSSAS, achados com o
  print_tela PICK, que agora pula os halos): ré nas duas lanternas do
  Shockwave e do Fireball, as lanternas grandes pintadas do Punisher
  (vermelho, laranja, branco da ré), as bolhas dos lados do Hammerhead e a
  ré do Truggy nas caixinhas cinza do lado das de freio (o ponto do jogo
  fica no ar).
  Lanterna pintada com outra cor do lado (luzes.gd MASCARA_CARRO): no
  Punisher a seta laranja logo abaixo do vermelho sai pela razão
  vermelho/verde (>= 4; laranja 2.3-2.6), no Chimera só os quadrados de cima
  pelo vermelho forte (>= 0.14 linear; os de baixo e as linhas < 0.1), com
  raio 26 cm (a cor já separa; com 18 a borda do quadrado de dentro apagava).
  Raio menor NÃO serve: acende uma bola no meio do desenho (o Matheus
  reprovou). Hammerhead: as lanternas grandes dos lados também (LUZES_NOSSAS).
  Ferramenta de cor das lentes: o PICK do print_tela dá o ponto no frame
  do model_root (= ponto do jogo + model_offset do car.gd).
- Farol (melhoria nossa, car.gd FAROL, farol.gd; H no jogo liga e desliga,
  vale pra todos): mesma cara da lanterna de freio (lente acesa nos pixels
  claros com o shader do luzes.gd + brilho suave virado pra câmera). Testamos
  o halo do HEAD_LIGHT do jogo (brilho com raios, out/2026) e o Matheus achou
  mais feio: não voltar. Lentes = faces com textura de farol (farol.gd
  LAMPADAS: light_64, headlight e nos trucks desert_jeep_style_light e
  trophy_truck_light, atlas com lanterna/relógio), agrupadas pelos vértices,
  viradas pra frente pela NORMAL do jogo (a ordem dos vértices vem virada do
  pingu2obj) e na frente da roda dianteira (no Goliath um pedaço da
  trophy_truck_light acendia dentro da cabine). Buggies: só o Hurricane (2) e
  o Storm (2 faróis + 4 milhas); no Mosquito a light_64 é a lanterna de trás.
  Trucks: Shockwave, Jericho, Goliath e Chimera (2 cada); no Shinto e no
  Punisher a light_64 é luz de teto virada pra trás. Lazarus (bônus): os 2
  faróis redondos da barra do para-choque (preRunnerTruck_light); os da
  grade são pintados na preRunnerTruck_front e ficam apagados.
- Alfa: o gob_tex2png salva sem alfa (no PS2 ele muitas vezes é brilho). Nos
  carros só 3 texturas têm furo de verdade: mesh_grey (redes das janelas,
  54%), Buggy_05_framework (treliça do Trident, 71%) e driver (7%).
  tools/alfa_texturas.py devolve o alfa delas e o car.gd vira recorte
  (_tem_alfa); as outras têm alfa cheio e não mudam.
- Ordem da roda no passo (out/2026): o jogo faz integra (0x2484c8, com a
  força W+0xfc do passo anterior) -> contato (0x248768) -> mola (0x248a80)
  -> pneus, e o x que sobra no fim (RAM W+0xe8, o desenhado) é o do contato.
  O remake integrava no FIM do passo: mesma física (o ciclo é igual), mas o
  x guardado ficava f/m·dt² mais baixo e parecia que o carro sentava 1 a 4
  cm mais alto (roda afundada no chão no visual, som e tremida lendo o x
  caído). Agora car._integra_rodas roda no começo do passo. A mola já batia:
  W+0xfc parado = peso (Buccaneer 16.68 kN, Bulldog 9.81).
  tests/teste_curso.gd: 8 save states parados, até 0.6 cm.
- Rodas sem escala (tamanho = modelo). Frente: centro gira com a balança em
  x/z e y = WHEEL.y + curso; trás: arco inteiro. O pneu afunda uns cm parado
  no jogo também.
- Física roda a 50 Hz = passo do PAL (nosso exe). O jogo DEPENDE do passo:
  com a roda patinando o motor fica batendo no limitador (rampas de 15/s) e
  a patinada sobe e desce (3/s, 4/s); com passo menor o corte é raso e a
  força média sobe. A 120 Hz a 1ª saía 28% forte. Vídeo NTSC (EUA) = 60 Hz
  (rodar_testes --hz 60; o veh=2 já roda assim). Interpolação ligada;
  câmera em passos de 1/60 interpolando no frame do carro (senão aparece
  "fantasma").
  Cada passo da câmera de órbita usa o carro NO TEMPO DELE (posição de agora
  menos velocidade x o que sobrou do acumulador). Sem isso, a 60 Hz saem
  quadros com 0 e 2 passos e o carro vai e volta na tela (14 cm a 60 km/h,
  42 cm a 180; tests/teste_camera_passo.gd).
- MÃO: o jogo é mão esquerda (esquerda do jogo = x < 0 no modelo), o Godot
  mão direita. Até out/2026 o remake saía todo ESPELHADO. Agora: carro =
  nó `espelho` (escala (-1,1,1)) com tudo do jogo em frame do jogo dentro
  (malha, suspensão, rodas, volante); a física usa car.corpo(p) e a
  esquerda do jogo é +X (w.left). Mundo = Terrain.do_jogo: remake
  (X, Y, Z) = (z - 1024, y, x) do jogo (transposição, mantém a diagonal do
  terreno). Ângulo de esterço no frame do jogo = -steer (car.gd a_jogo).
  Câmeras do XML: x negado no _parse. Nunca converter a mesma coisa duas
  vezes. tests/teste_chao.gd põe os 6 carros na pose da RAM e confere roda
  por roda (lado trocado = 2,4 m de erro); tests/teste_mao.gd confere
  carroceria, volante, olho, peças, espelho da roda e sinal do esterço.
- Terreno RX01: .bin no layout do jogo, transposto na carga (terrain.gd).
  Alturas e material saem do stream (tools/extrair_material.py), conferidos
  com a RAM (tests/teste_chao.gd). Diagonal da célula (i+1, j)-(i, j+1) = a
  do HeightMapShape3D. Material i = Material_(i+1) do data/materials_rx01.xml.
- Mapa de material do RX01 CONFERIDO (out/2026): o material da FL na RAM
  (veículo+0xa88[0]) bate com o mapa no ponto de contato em drr_1, drr_3 e
  110; no 170 a roda está 1.2 mm depois da divisa da célula (o material da
  RAM é do passo seguinte). No 110 o PS2 tocava asfalto com as rodas da
  frente no cascalho porque elas saíram do asfalto 0.07 s antes: o loop do
  asfalto leva 0.34 s pra apagar (release) e o do cascalho só entra 0.25 s
  depois (espera do grão). Não tem malha de estrada por cima do relevo.
  tests/teste_sfx.gd confere os 2 (material x RAM e "som atrás do chão").
  O "grip" do ref_derrapagem.json NÃO é o atrito do material (0.80 até no
  asfalto).
- Objetos do RX01 (PORTA, nov/2026; objetos_rx01.gd, tools/rx01_objetos.py,
  docs Objetos da pista): o RX01 não tem modelo no stream (StreamP/StreamW
  com "Models Total = 0 bytes"); vem tudo do evento: Event/Rallycross/
  Default/#def5772a (other/12290) = 57 pingus + 651 bantams com a matriz do
  jogo (linhas = eixos com escala) e RALLYCROSS.bin = 93 entidades (largadas,
  reposição, cercas, gatilhos). Formato de chunks F00DABCD/DEADDCBA com chave
  em hash. Bantam ("TNAB") decifrado: VIF com 2 qwords por vértice (posição
  + ADC; UV com a cor RGBA no byte de baixo), sem normal (luz assada), lista
  de texturas no #hash DEPOIS dele. Conferido: posições em cima do relevo
  (moitas 0.00 m), guard-rail, fardos e cercas na borda da pista no mapa de
  material, "START" do arco legível (espelho certo). Colisão = KDt
  (triângulos: face + 3 arestas), nome = crc32('<modelo>.kdt'); 11 sem nome
  casados pela caixa (KDT_POR_CAIXA). Cerca de plástico/madeira e fardo
  (PORTA, nov/2026, ver "Cercas e fardos" abaixo) são interativos. teste_objetos: o
  Renegade a 60 km/h para no guard-rail (sem os objetos atravessa 29 m).
  Sem assets/rx01 (rodar o tools/rx01_objetos.py no PC) nada aparece e não
  entra parede invisível; o HUD avisa.
  Árvores "meio diferentes" (prints do jogo do Matheus, nov/2026): bantam é
  PRÉ-ILUMINADO (sem normal): sem luz do Godot (as placas de folha de costas
  pro sol ficavam pretas, as de frente amareladas), textura x cor do vértice
  (Alder: folha oliva x 0.70 = oliva escuro como no jogo), sem sombra
  dinâmica. Folha = placa TRIANGULAR em volta do quadrado da textura (UV
  -0.3..1.4, borda transparente): textura PRESA na borda nos materiais com
  +0x38 = 5 (só Alder, pinheiro e moita); repetindo, os cantos mostravam
  pedaços cortados ("placas soltas" no céu).
  Face sumindo / lado de dentro aparecendo (prints do Matheus, nov/2026:
  placa de chevron, telhado do celeiro, tela da torre): TODAS as instâncias
  do RX01 são espelhadas (det < 0: matriz do jogo + transposição) e o
  MultiMesh do Godot não vira a face por instância (o MeshInstance3D vira).
  Os .pingu com mais de 1 instância usam uma cópia espelhada da malha
  (_espelhada) e a matriz sem espelho. Bantam não tem isso (2 faces).
  Lote transparente (tela da torre; a poça NÃO, com as 2 faces ela ficou
  preta no Forward+, nov/2026) e recorte de .pingu (torcedores
  da cabine do locutor, WahooCrowdTex01) desenham as 2 faces.
- Céu (PORTA, nov/2026; ceu.gd, docs Céu): "a skybox tá faltando" (Matheus).
  SkyDome do Environment.xml: SKY_Bright_LowCloud (nuvens) +
  BACKDROP_Asia_1 (montanhas azuis), .pingu de Levels/SkyDomes (o XML diz
  .clm). 0x1d6500: na posição da câmera + yOffset, giro em Y pela rotation,
  cor = tint (1.0) com o alpha, sem gravar profundidade, céu e depois
  montanhas. No remake x70 em volta da câmera (cabe no far de 4 km, relevo e
  objetos na frente pelo teste de profundidade), sem luz nem névoa.
  Céu HD (melhoria nossa, ceu.gd CEU_HD): o Matheus ampliou as 2 texturas
  x4 no Upscayl; o alfa das montanhas do jogo é liga/desliga em blocos de 4 px
  (escadinha nos picos), refeito borrando e cortando com curva suave. Ficam em
  assets/rx01/ceu/hd/ com o nome da original (fora do git); sem elas, a do jogo.
  Chão HD (terrain.gd CHAO_HD): qualquer imagem em assets/terrain/hd/ cujo
  nome começa com rx01_terrain (o Upscayl põe sufixo), lida DIRETO do arquivo
  pelo conteúdo (PNG/JPG/WEBP, qualquer extensão), sem o import do Godot. PNG
  renomeado pra .jpg pelo import deixava o chão branco, e sem textura nenhuma
  ficava a cor lisa marrom. O console diz "chão: <arquivo usado> (LxA)".
  Lida assim ela ia CRUA pra placa (4096 = ~85 MB): acima de 2048 vira DXT1
  (~11 MB, 156 ms na carga). Disco: 2x em JPG qualidade 90 (~2-4 MB); o PNG
  do Upscayl dá 13-20 MB. 4x+ não muda nada na altura do carro (Matheus).
- Água (PORTA, nov/2026; save states do Matheus Renegade_dentro_da_agua e
  _andando_na_agua; tests/teste_agua.gd, docs Água): o RX01 TEM água, a poça
  WATER_puddle01 (pingu) perto da largada. Não é material do chão: o jogo
  cria uma caixa por instância WATER_* (0x1bb098) = caixa do modelo no frame
  dela, superfície = o y mais alto (RAM: centro, giro 15°, 21.01 x 19.88 m,
  206.017 = os da malha). 0x201c20 por quadro: profundidade de cada roda =
  superfície - (centro - raio) em y (veículo+0xaec, ordem FL RL FR RR) e
  veículo+0xae8 = a água da última roda. Usada em: arrasto 0x20e5e8
  (Water_drag 0.1 x min(média/0.5, 1) x 0.01 x v²: ~95 N a 60 km/h, quase
  nada, como o Matheus lembrava), lama da roda (registro AGUA_REG: cor 0,
  alfa 0, taxa 30 = lava), espirro (0x225108 ramo da água: tipo Water do
  Dust.xml, textura WorldFXwater_dust -> assets/fx/agua.png, cor do objeto
  +0x70 com alfa x 0.6, no meio entre o fundo da roda e a superfície) e som
  (0x370548: roda a mais de -5 cm da superfície = material "Water" do
  SoundDatabase). Desenho: o lote da poça é transparente (+0x00 = 1) e a
  water_puddle tem alfa do PS2 0.75..2 (o PNG velho vinha sem alfa e a malha
  cinza opaca ficava azulada no Godot: o "pedaço azul"); agora sai com o alfa
  (x 2, modelos.json "misturada"). Precisa rodar de novo o rx01_objetos.py e
  o fx_jogo.py. Transparência (nov/2026, "MUITO azul, não dá pra ver o
  fundo", print do jogo do Matheus): pela conta do PS2 (alfa ~0x80, vértice
  94/128) a poça fica ~92% opaca, mas no jogo é bem transparente. O lote tem
  +0x10 = 4 no registro do .pingu (a tela da torre 6, peças opacas 0 ou 2:
  bit 2 = 2 faces, bit 4 = transparente); o modo de mistura do GS desse
  lote não foi achado. NOSSO: objetos_rx01.gd POCA_ALFA 0.5 (= alfa lido de
  0..255), calibrado no print.
- Cercas e fardos (PORTA, nov/2026; objetos_rx01.gd INTERATIVOS,
  tests/teste_quebra.gd, docs Objetos interativos): Setup/InstanceDatabase.xml
  (data/instance_database.xml) diz a classe de cada modelo (registro das
  classes no 0x547738). As 2 cercas (GEN plástico, SAM madeira) são
  cObjectFlimsyFence: paradas até o impulso das batidas passar de
  ShatterImpulse (0x141640 compara a soma com 2² = 4); aí 0x141908 tira a
  cerca e as peças (Fragment, *_Particle_01/02) nascem paradas na pose dela,
  de um estoque de 20 por modelo. O fardo é cObjectTrackBlock: corpo solto de
  0.1 t, atrito 0.2, ActiveResetTimeout 10 s. Contato da cerca = as ESFERAS
  do .hsc (como o casco dos carros): com a caixa fina, batendo na ponta, o
  Godot dava a normal da placa e as cercas de lado viravam parede.
  Batida (nov/2026, "a cerca laranja não freia no jogo", Matheus): o
  0x153390 (carro E rodas x cerca parada, 0x154088) mede o impulso de cada
  contato contra corpo parado, j = -(1 + e) vn / (1/m + n.((I^-1 (r x n))
  x r)) em t·m/s, pega o maior e o 0x141a48 quebra com j > ShatterImpulse
  (2). Quebrou: o carro só leva n x min(j, 0.25) (0x54d190, giro com o braço
  x 0.2) e o contato é jogado fora: perde no máximo 0.75 km/h no Renegade.
  O fardo NÃO tem essa trava (o 0.25 só é usado ali): 0.1 t na mesma unidade
  do carro (1.2 t) = 100 kg, Hardness 0.2 = restituição (0x142698 -> corpo
  +0xbc). O que freava no remake era nosso: o raio da suspensão via cerca,
  peça e fardo como chão fixo (a roda subia na cerca; o fardo virava rampa
  parada) e as peças soltas batiam no carro logo depois (até 12 km/h em
  ângulo). Agora a roda quebra a cerca pela mesma conta, a reação da roda vai
  no corpo solto e as peças nunca batem no carro nem na roda.
  De lado ("vira parede", Matheus): quem encosta é a esfera da roda
  (_esferas_das_rodas), que só liga depois da checagem; agora ela também
  passa pelo roda_na_cerca antes de ligar. Pedaços brancos/amarelos: o
  load() devolve a mesma malha a cada cerca e o _materiais dobrava a cor de
  novo (x4, x8); material nosso agora tem meta "rx01" e não é refeito.
  DEBUG_CERCA=1 imprime o impulso de cada contato.
  tests/medir_perda.gd (mesmo caminho com e sem o objeto): cerca 0.1 a 0.8
  km/h a 30 e 60 km/h em 0/30/60°, fardo 1.5 km/h a 20 e ~5 a 55 (física de
  100 kg contra 1.2 t).
  Aproximações NOSSAS (marcadas no código): a quebra é decidida ANTES do
  passo (varrendo o passo com cast_motion: a esfera de 10 cm pulava o
  contato a 60 km/h), pra o carro atravessar; peça de 10 kg (o construtor
  0x140758 não dá massa) que não bate no carro; fardo volta 10 s depois de
  mexido (> 0.5 m), com o carro a > 4 m; AngResistance -> angular_damp.
  teste_quebra: a 60 km/h a cerca quebra e o carro segue a 63; a 4 km/h
  (impulso 1.3) segura; fardo sai 13 m e volta.
  Som da batida (PORTA, 0x36b998, chamado pelo 0x153390 em cada contato):
  CollisionSample do objeto -> SoundDatabase Collisions/InteractiveObjects
  (PLASTIC_FENCE = FencePlastic, HAY = Hay, do Collide.bnk), volume Volume x
  CollisionVolume 0.8 x SFXVolume, tom Pitch, na posição do carro. O jogo
  repete por quadro (até 4): aqui 1 a cada MinRetriggerTime 0.2 s por objeto
  (nossa). sfx_carro.batida_objeto. No fardo (corpo solto) o caminho do exe
  não foi achado: toca no impacto com o carro (nossa).
  Palha do fardo (palha.gd; dados PORTA): 2 pontos "particle Hay" do
  PtS/Bantams/GEN_HayBale.pts (formato: "POINT 1.00", n em +16, n x [nome
  32 + posição + matriz 3x3 x 0.01]), efeito Hay do Setup/Particles.xml
  (data/particles.xml: 10/s, vel 0.5..1, Spray 6, pra cima) e sistema
  BailedHay do Effects/WorldFX.xml (data/world_fx.xml: até 30, vida 0.5..1,
  gravidade, cor de palha, 0.05..0.07 x 0.4..0.7 x 0.6 como a poeira, caixa
  "snow" = Snow0 do Particles.bed, tools/fx_jogo.py -> assets/fx/palha.png).
  Disparo NOSSO (não achado no exe): impulso do passo no fardo (massa x
  variação da velocidade sem a gravidade; o Godot dá 0 no impulso dos
  contatos) > Impulse 0.2 liga a emissão por Timeout 0.1 s: ~1 palhinha por
  ponto por batida (teste_quebra: até 6 no ar). Matheus (nov/2026): "sai
  poucas palhinhas, mas dá pra ver, ficou bom". FECHADO.
- Multidão (PORTA, nov/2026; multidao.gd, tools/rx01_objetos.py multidao(),
  docs Multidão): Levels/RX_01/Models/Wahoos/RX01_Crowds.wahoo ("OHAW" 1.3,
  carregador 0x2821c8/0x2825b8, renderer cWahooRenderer) + o .wfn
  (#5d1b7d96: 7 texturas de 0x80 e 20 nomes de animação de 0x20). 26
  objetos de 0x60 (+0x30 material, +0x48 animação, +0x50/+0x54 VIF);
  material (+0x104 -> tabela de 0x40, +4 = textura do .wfn: a ordem NÃO é a
  do objeto). VIF: V4-32 posição no mundo do jogo (w 0x8000 = sem
  triângulo, tira de 4 = 1 pessoa), V3-8 normal, V2-32 UV, V4-8 cor. 233
  pessoas (fotos da equipe: Rory, Rupert, Graham, Jez, Trev, Joe/Ben/Rob +
  WahooCrowdTex01), 20 objetos animados pelo Setup/UVRGBAAnim.xml
  (data/uv_anim.xml: FEX_Crowd_anim 4 quadros de 0.25 com 0.1/0.05/0.05/0.75
  s, FEX_Crowd_3frame 3 de 0.33, ping-pong; Set_UV soma no UV). As texturas
  saem com o alfa do PS2 x 2 (recorte). NOSSO: todos com a mesma animação
  andam juntos (a fase do controle 0x27b930 não foi achada). As pessoas
  paradas pintadas nas arquibancadas (Crowd_01/02) são do modelo e paradas
  no jogo também (o Matheus conferiu no jogo, nov/2026). Camisetas
  coloridas (nov/2026): o lote da US_Bleacher_Wood_02 tem 2 texturas, a
  Crowd_02 e a Crowd_ColourChange (camisetas no mesmo lugar, 2º UV = 1º)
  como camada (registro +0x18).
  Camadas (PORTA, nov/2026, docs Objetos da pista; "o arco do jogo é meio
  cinza gasto desde o início", prints do Matheus): lote com camada = tipo
  0x22222222 do renderer de pingu (0x28db40, montado no 0x289228 ->
  0x289908); a 2ª passada usa a palavra de estado 0x36080044 (0x2897f0) =
  ALPHA 0x44, a mistura comum (Cs - Cd) x As + Cd, com teste de alfa >= 1.
  As = alfa da textura x ALFA DO VÉRTICE, e o artista pintou o alfa do
  vértice pra dizer onde a camada aparece (arco 40..128, celeiros ~0.4 em
  média). O import de .obj do Godot joga fora o alfa do vértice: por isso a
  sujeira do arco saía cheia (cinza riscado) e as camadas de madeira,
  ferrugem e concreto pareciam cobrir os celeiros. tools/rx01_objetos.py põe
  a malha da camada com o alfa no modelos.json ("tris",
  pingu2obj.camada_tris) e o objetos_rx01.gd monta por ela: TODAS ligadas
  (arco, camisetas, celeiros, cabana, persiana do alto-falante). Sem o
  "tris" (rx01_objetos.py antigo) só as camisetas (CAMADAS_SEM_ALFA), como
  antes.
  Piscando / sumindo (nov/2026, prints do Matheus): a camada fica no MESMO
  plano do modelo; no Forward+ o Godot grava a profundidade do modelo numa
  passada antes e a camada perdia o empate (sumia inteira: arco limpo) ou
  brigava (camisetas e celeiro piscando). NOSSO: o shader da camada
  (_shader_camada) puxa ela 0.05% da distância pra câmera (5 mm a 10 m) e a
  posição vai com as mesmas 6 casas do .obj. Conferido no lavapipe: sem
  isso o arco sai limpo, com isso a sujeira aparece. Matheus (nov/2026):
  "agora sim ficou bom". FECHADO.
  Cercas das entidades (cFenceNodeEntity/cFenceLinkEntity do RALLYCROSS.bin,
  32 nós + 26 ligações em 6 correntes): só do EDITOR. A lista de classes que
  o exe cria (nomes em 0x579480..) não tem nenhuma cFence; o editor gerou as
  peças por uma curva pelos nós (~3.2 m cada) e gravou como bantams comuns
  no #def5772a (4 correntes; o remake já desenha). As outras 2 (GEN do lado
  da torre do locutor, SAM no meio das moitas) não têm peça gravada e não
  existem no jogo (o Matheus conferiu, nov/2026). FECHADO.
- Luz e névoa (PORTA, nov/2026, "a cor tá muito clara", prints do Matheus na
  largada; docs Luz e névoa; main.gd ler_ambiente/_make_environment): o
  leitor do Environment.xml é o 0x1c15d8. Medido no mesmo enquadramento
  (tests/print_largada.gd, Forward+): o remake estava 30-50% mais claro. (1)
  O chão tem a LUZ ASSADA na textura (sombra do arco, arquibancadas, morros):
  o jogo desenha a cor dela (chão 78, 72, 66 no print x textura 85, 75, 65).
  terrain.gd: sem luz nem ambiente do Godot, só a sombra dinâmica do carro
  (SOMBRA 0.66 na tela, NOSSO medido no print; o jogo usa Intensity 0.5 x
  ((1 - s) + InShadowMultiply 0.8 x s), 0x1b3fe0, mas a textura da sombra
  não foi achada). Objetos não fazem sombra dinâmica (já está na textura).
  (2) PS2 sem tonemap: linear (o filmic achatava). (3) Névoa LINEAR de Start
  87.5 até End = DrawDistance Terrain 400 (0x390a80 põe na câmera), cor
  (0.48, 0.44, 0.42); antes era exponencial nossa. (4) Ambiente 0.66 x cor e
  sol 1.0 x cor do XML; o PS2 soma a luz na cor da TELA e o Godot em linear,
  então a força vai ^2.2 (ambiente 0.40). Resultado (jogo x antes x agora):
  chão 53-78 x 98-111 x 62-73; para-choque 123 x 95 x 115; tampa branca 135
  x 162 x 142; arquibancada 109 x ? x 116; azul do céu 115,144,178 x 122,150,
  180 agora. Não portado: luz própria do carro (Vehicle/VehicleSun) e do
  piloto, InShadow, Overbright (ActualBrightness 1.756, uso não achado).
  Falta: o vermelho da lateral do Renegade fica 98 x 72 do jogo (pintura?).
  AMB_E / SOL_E = força da luz no Godot (diagnóstico).
  Grão do chão (nov/2026, "o chão do jogo tem mais qualidade", prints do
  Matheus no mesmo lugar): o renderer do relevo (0x1eb758) põe por cima a
  textura "detail" da pista (Levels/RX_01/Env/Default/Default/DETAIL.bog,
  128 x 128, desenho no ALFA; tools/rx01_objetos.py ->
  assets/terrain/rx01_detalhe.png, no git). env.header +0x2c = 5.0 e o
  0x29ed98 (x16) = 80 repetições por bloco de 128 m (1.6 m cada; leitura
  nossa). A mistura fica no VU1 (não achada): NOSSO terrain.gd fator 1 +
  0.55 x (alfa/média - 1), mesmo brilho médio, repetindo a cada 2.4 m,
  apagando de 4 a 20 m da câmera. Primeiro calibrado pelo desvio do grão
  fino (0.9, 1.6 m: 11.3 perto / 5.3 meio x jogo 14.2 / 4.5); depois o
  Matheus (nov/2026): "tá bem preto e roubando a cor do chão, deixa mais
  fraca e estica um pouco" -> 0.55 e 2.4 m (6.7 / 4.2).
  DETALHE=x, DETALHE_M=x, DETALHE_SOME=a,b (diagnóstico).
  ERRO NOSSO que custou caro ("parece ruído, não parece o chão do jogo",
  Matheus): textura com MIPMAP no .gob (0x158 = tamanho de todos os níveis,
  ex: DETAIL.bog 10880 = 128x128 + 64 + 32 + 16 em 4 bits) caía no "pega o
  fim do arquivo" do gob_tex2png e saía embaralhada (ruído puro, e o terço
  de baixo diferente = os níveis menores). Agora o nível 0 vem do 0x15c. 477
  das 15681 texturas do unpacked têm mipmap: quase todas DETAIL das pistas
  (PlaceHolder), "dirt" vazias dos carros e umas de menu; nada do RX01 nem
  dos carros que já usávamos.
- Material do chão: só o atrito (pneu) e o Damping (arrasto do chão,
  0x20e5e8) mexem na física do buggy. Hardness, Sink e Bounciness o jogo
  carrega e não lê (varredura do exe, docs Terreno). Não "portar" eles.
- Giro da roda (0x2113e0): no chão ω = v_prevista·(1 + 0x610)/R, então o
  0x600 (ω·R/v − 1, que ABS/trava/embreagem leem) é a 0x610 do passo
  anterior. 0x3cc = rodas de TRÁS no chão (não "tração no chão"). O
  "torque" do freio ali não tem a massa (×1000 com inércia em kg·m²).
- Pedais: cada comando tem cru e suavizado (corpo+0x368; acelerador
  0x37c/0x380, freio 0x38c/0x390). Motor usa o suavizado; o CÂMBIO
  (0x20c7a8) e o "preso" usam o CRU. Parado sem pedal (< 0.2 mph) o jogo põe
  freio 1.0 sozinho (0x202df0): a barra vermelha cheia na largada não é o
  jogador freando. Freio parado vira ré na hora (0.1 s se vinha andando);
  no ar o acelerador corta até ser solto uma vez. car.gd _pedais_auto.
- O jogo NÃO tem freio de mão. O botão (corpo+0x384/0x388) é a EMBREAGEM:
  segurando abre a embreagem (> 0.1, 0x20c558); um toque virando e
  acelerando faz a "Clutch Turn" (powerslide 0x214610, car.gd
  _powerslide). O freio só tem o pedal (0x390). No remake é o Espaço ou o
  A do controle (escolha do Matheus; no PS2 é o R1). Select troca a câmera.
- Derrapagem não volta sozinha: o 0x2120c0 (RecoveryTorqueCutting) corta o
  torque que endireita (modos B/C do 0x20efa0) pelo acelerador quando o
  volante está pra dentro da curva ou solto, e sobe a patinada de trás até
  0.2. Sai contra-esterçando ou soltando o acelerador. Sem ele o remake
  "consertava o carro pra pista" (docs/derrapagem.md).
  Testamos um ajuste NOSSO pro teclado por cima (cortar também abaixo dos
  12°, out/2026): o Matheus comparou lado a lado e ficou pior. O fiel é o
  certo; não "afrouxar" a derrapagem no chute.
- Piloto (piloto.gd, tools/piloto.py): .skl/.srd/.bac decifrados
  (docs Piloto). ROOT da animação em cima do ARSE, sem a rotação do ponto.
  STEER_LEFT no tempo |s|/6, espelhado com s > 0 do jogo (= rider_s < 0 no
  remake). Índice de osso no .srd vem x4. Some no capô e no para-choque
  (mRenderRider 0); na nossa câmera do piloto aparece sem o capacete (osso
  head encolhido: o olho fica dentro da cabeça dele), com braços e mãos no
  volante.
- Mãos no volante (melhoria nossa, car.gd MAOS_NO_VOLANTE): o volante gira o
  quanto os punhos giram no STEER_LEFT do jogo (39° a 62° no volante todo,
  por carro; antes era SW_TURNS = 149° sem fonte) e cada punho fica preso no
  aro por IK de dois ossos. Em 5 carros (Sphinx, Inferno, Kraken, McKenzies,
  Storm) o volante fica além do braço esticado (até 108%): a clavícula avança
  até 35°. tests/teste_volante.gd: 0.0 cm nos 13 carros.
  No quadro 0 do STEER_LEFT a mão direita pega a 22° do topo e a esquerda a
  44° (braços tortos na câmera do piloto): a direita agora é o espelho da
  esquerda no plano do volante (piloto.gd prender_no_volante). A mão
  também gira até a linha dos nós (indicador -> anelar) ficar ao longo do
  aro: na animação ela fica 25° a 43° torta e o aro saía de lado do punho
  ("mão mal encostando"). O ponto do punho (média dos vértices da mão) cai no
  buraco dos dedos dobrados, a ~5 mm do centro dele (corte da malha).
  Depois ela desce pelo aro até PEGA_GRAUS = 65° do topo (~9h30/2h30, vídeo
  de referência do Matheus; a 44° os braços subiam na frente da câmera no
  Bulldog e no Viper) e gira em volta da linha dos nós até o pulso ficar
  reto atrás do punho, na direção do eixo do volante (os carros bons já
  ficavam entre -28° e +10° disso). Seguir o antebraço do IK NÃO serve: no
  Renegade (volante perto e deitado) o antebraço fica quase na linha do aro,
  o ajuste fica indefinido e o pulso ia 7 cm pra dentro (braço em
  zigue-zague). No volante todo a mão de fora vai perto do topo e o
  antebraço passa na frente da câmera (pendente).
  Braço natural (nov/2026, "braço quebrado esquisito", Matheus): medido no
  teste_volante, o pulso dobrava 23° a 115° em relação à animação do jogo
  (a mão ia com o pulso no eixo do volante e o antebraço do IK chegava por
  outro ângulo) e torcia até 60°. Agora (piloto.gd) a mão ROLA em volta do
  aro (até 75°) e INCLINA em volta do raio (até 30°), os giros que mantêm a
  pegada, e o cotovelo vai pro lado onde o pulso fica reto, preso entre pra
  baixo e COTOVELO_FORA 55° pra fora; metade da torção vai pro antebraço (o
  esqueleto não tem osso de torção). Pulso: 0 a 14° na maioria, 31 a 40° no
  pior (Goliath, Fireball, Hammerhead, Renegade; antes 65 a 86°). Busca
  solta por quadro trocava de solução e a mão estalava (até 62° e 26 cm por
  passo de 2% do volante): a solução é uma TABELA por carro (_montar_tabela,
  41 direções, partindo do volante reto e andando sempre perto da vizinha,
  ângulo do cotovelo guardado sem o limite pra não pular de 0° pra 55° ao
  passar por "pra cima", e suavizada), interpolada no jogo: pulo de 0.4 a
  2.6 cm e 1.3 a 3.4° por passo (antes 0.4 a 1.3 cm). Carga: ~50 ms.
  teste_volante imprime cotovelo, pulso, torção e pra onde o cotovelo
  aponta, e o pulo (PERFIL=1 passo a passo); tests/print_piloto.gd tira
  prints do piloto sem a carroceria (vistas lado, frente, cima, maos;
  janela com CORPO=1).
  Porta e tela (nov/2026, "braço do Fireball varando a tela e a porta"): o
  cotovelo do Fireball entrava 6.4 cm na porta (Kraken encostava). car.gd
  _paredes_do_piloto mede na carga onde a carroceria fica dos 2 lados do
  banco (grade de raios saindo do meio do banco, ignora até 18 cm) e o
  cotovelo fica a PAREDE_FOLGA 7 cm dela, indo pra dentro se precisar (até
  30°): Fireball 11 cm, Kraken 6.5 (medir_cabine imprime a folga de cada
  carro ao longo do volante). No volante todo a mão de fora sobe até perto
  do topo e o antebraço cruza a câmera do piloto (pendente). Testamos a mão
  de fora PARAR a 40° do topo com o volante girando por baixo (escorregando):
  como ela pega a 65°, já escorregava com 25° de volante, no teclado (volante
  todo quase sempre) uma mão ficava parada e não tremia junto com o volante.
  O Matheus achou bugado: não voltar. teste_volante agora mede a mão contra
  o aro girando de verdade, com a tremida (erro_maos(s, extra)).
  Trucks (lote 2, out/2026): 9 dos 13 alcançam igual aos buggies (aro a
  54-60 cm do banco, braço até 102%). Chimera (80 cm, 144%) e Lazarus (71 cm,
  128%): o ARSE do jogo fica baixo e pra trás do volante; trazer o volante no
  eixo dele sobe o aro e ajuda pouco (134%), subir o banco mais que ~5 cm bate
  o capacete no teto (75 cm acima do banco no Chimera). Ficou car.gd
  BANCO_NOSSO (só o desenho do piloto: Chimera +4 cm e 20 pra frente, Lazarus
  +6 e 5) + AVANCO_VOLANTE (10 cm nos dois, com coluna nossa até a coluna do
  modelo): 106% e 101%, erro 0. Lazarus refeito (nov/2026, "parece um
  anão", Matheus): o aro ficava 50 cm acima do banco (nos outros 25 carros
  27 a 39) e o teto 62 cm acima da cabeça (trucks 33 a 56); com o banco
  +21 cm (e 9 pra frente) fica 35 / 47, braço 89% SEM o AVANCO_VOLANTE e o
  olho da câmera do piloto volta pra 19 cm acima do osso da cabeça (antes
  39; os outros 15 a 30). tests/medir_cabine.gd (teto, olho x cabeça).
  Depois TT, Goliath e Chimera ("baixinhos", mesmo critério): TT +10 cm
  (teto 56 -> 46), Goliath +8 (aro 46 cm acima do banco; teto 45 -> 37),
  Chimera +15 e 20 pra frente sem o AVANCO_VOLANTE (aro 50 -> 35, teto 43 ->
  32, braço 107 -> 92%); AVANCO_VOLANTE ficou vazio. Shockwave e Punisher não têm interior (o
  tools/volante.py não acha aro): VOLANTE_SEM_MODELO põe o nosso onde ele
  fica nos outros trucks (ARSE + 0.37 de altura e 0.46 pra frente, eixo e
  raio típicos) com coluna nossa até o painel (raio no eixo), 103%. O
  Lazarus tem o id do Jericho: tabelas por carro usam car.chave() ("LAZARUS").
- Câmera do piloto (melhoria nossa, camera_piloto.gd, main.gd modo 4): o
  olho fica no lugar calibrado (car.gd FP_*) e por cima vêm os efeitos de
  velocidade (referência do Matheus: The Crew Motorfest, com o olhar livre do
  Forza), cada um com chave em CameraPiloto.efeitos pro menu de opções; G liga
  e desliga todos. Força G: a cabeça é uma mola de pescoço (1.6 Hz, 70% do
  crítico) no frame do carro, empurrada pela aceleração medida a cada passo
  de 50 Hz (1 g de freada = 5 cm pra frente e olha pra baixo; curva = pra
  fora e inclina). Limite de 8 cm (6 de lado) chegando aos poucos (tanh): a
  freada do Renegade dá 1.8 g e com corte seco a cabeça grudava no limite. FOV +12° de 36 a 216 km/h. Olha pra curva: 60% do ângulo
  de deriva + 0.15 s de guinada, até 25°. Borrão: zoom radial só nas bordas
  de 72 a 200 km/h (CanvasLayer embaixo do HUD). Olhar livre: analógico
  direito ou mouse com o botão direito (150° pros lados, 35° pra cima e pra
  baixo), volta sozinho; a cabeça gira em volta do pescoço (10 cm atrás do
  olho). Sem efeitos a câmera olha reto (a de antes virava 1/4 do volante;
  o print_tela ainda usa essa, car.first_person_xf).
- Órbita da câmera de corrida (melhoria nossa, nov/2026, pedido do Matheus:
  "o analógico direito do Forza, solta e volta pro lugar"; camera_orbita.gd,
  main.gd ORBITA): nas câmeras perto e longe o ÂNGULO do analógico direito é
  pra onde a câmera olha (direita = olha pra direita, câmera do lado esquerdo
  do carro; pra baixo = olha pra trás); girando o analógico a câmera dá
  quantas voltas quiser. Meia deflexão gira menos (cheio a 75%). Mouse: botão
  direito arrasta (lados sem limite, -12° a +40° de altura). Soltou: volta
  pelo caminho curto em ~0.3 s e chega certinho (velocidade mínima no fim).
  A câmera do jogo roda por baixo sem mudar: a órbita só gira o resultado
  dela em volta da origem do modelo (o ponto que ela mira) e mantém a folga
  de 1.45 m do chão do jogo (0x384c80) quando girada. Analógico parado =
  câmera do jogo (diferença 0, tests/teste_camera_orbita.gd). C, R e T zeram.
- Cabine fechada (melhoria nossa, car.gd CABINE_FECHADA, _face_de_dentro):
  a casca do jogo só tem a face de fora (ninguém entra no carro no jogo). No
  Storm, o único fechado, a nossa câmera do piloto via a estrada pelas portas,
  teto e piso. Cada triângulo sem gêmeo do outro lado ganha uma cópia virada
  (os de 2 faces já modelados ficam, senão piscam): na pintura "white" com
  FORRO cinza (de dentro não aparece a pintura de fora espelhada), no resto
  a mesma textura (a rede da janela aparece por dentro). Por fora só muda o
  que se vê pela janela. print_tela CULL=0 desliga o descarte da face de
  trás na carroceria (diagnóstico). Trucks (lote 2): ligada nos 13 (olhando
  pra porta, Shockwave, Jericho, Fireball, Goliath, Chimera e Lazarus
  mostravam o chão; agora a chapa e a rede da janela aparecem por dentro).
  Vidro (textura *window*: só o Lazarus tem, os vidros fechados no modelo)
  fica sem face de dentro, senão de dentro a janela virava parede cinza.
  Por fora (nov/2026) era uma placa azul opaca: o lote do .pingu é marcado
  transparente (+0x00 = 1; no jogo todo só decalques, sombras, cercas,
  brilhos e o Ghost_White do carro fantasma têm isso), mas a
  Dakar_window_Index tem alfa cheio. A mesma imagem em
  Truck/Textures/Generic/Dakar_window_8 tem alfa 0x1B = 21%: car.gd
  VIDRO_ALFA.
  Painel com os 2 lados cortados diferente (nov/2026, ELF atrás da cabine do
  Hammerhead piscando): o jogo modela o mesmo quadrado 2 vezes, uma de cada
  lado, mas pela outra diagonal; o gêmeo só era achado com os 3 vértices
  iguais, e as cópias de dentro (forro cinza) ficavam no plano da pintura de
  fora e brigavam com ela. car.gd _com_costas: centro do triângulo dentro de
  um do outro lado no mesmo plano (3 mm), ou o dele dentro deste = já tem
  costas (sem cópia); dividindo aresta com um do outro lado = painel de 2
  lados, a cópia leva a PINTURA (o ELF aparece dos 2 lados, como com CULL=0).
  Pares brigando (simulação, carroceria + cópias): TT 152 -> 19, Fireball
  133 -> 14, Storm 187 -> 31, Hammerhead 44 -> 38; os que sobram são
  decalques do próprio modelo colados a < 1 mm da chapa (faixas "ban" na
  lateral da caçamba do Hammerhead).
- Volantes gerados (melhoria nossa, car.gd VOLANTE_NOSSO, volantes.gd): o
  do jogo tem aro de 6 a 12 lados e raios tortos; 8 carros usam o mesmo X
  furado girado ~20°. No lugar vai um volante redondo e centralizado, no
  centro, raio e eixo do pecas.json (a IK das mãos não muda). Um estilo por
  carro (Volantes.POR_CARRO): os únicos do jogo melhorados (Renegade barra
  + losango, Bulldog barra larga, Inferno/Storm X de aço com rebites, Sphinx
  o X furado) e os das fotos do Matheus (buggy no Phantom, Sparco preto no
  Kraken, Sparco azul no Viper, Mountney no McKenzies, kart no Hurricane,
  espuma no Trident, Fusca Itamar no Mosquito; couro sobra). B no jogo troca;
  print_tela VOLANTE=nome PILOTO=0. Alisar o aro do jogo (VOLANTE_LISO)
  quebrou no Renegade e no Bulldog: não voltar. Trucks (out/2026, pedido do
  Matheus): cada um com o PRÓPRIO desenho melhorado. Repetidos dos buggies
  reaproveitam o estilo pronto: Shinto e Panther = X furado ("furado"), TT e
  Hammerhead = X liso de aro prateado do Storm ("storm"). Únicos, estilo
  novo: Buccaneer (3 varões, 12h/4h/8h), Jericho (2 frisos, X de lâminas
  afinando, chapa quadrada), Lazarus (o mesmo com aro cromado e lâminas
  pretas), Truggy (X liso + placa em T, cubo "t"), Fireball (aro grosso e 4
  tubos cromados, os de cima a 75° pra não cair na mão), Goliath (2 frisos,
  X largo de alumínio com 2 furos), Chimera (aro grosso de camurça, X com 3
  furos, anel de parafusos). Shockwave e Punisher não têm volante no modelo
  (bulldog e sparco_preto, escolha nossa). Desenho do jogo de frente: o
  print_tela com DESLIGAR=volante_nosso PILOTO=0 (VOL_DIST=0.5 chega perto).
  tools/volante.py achava o aro numa bola de 40 cm em volta de ARSE +
  DO_BANCO: no Chimera e no Lazarus o banco fica longe (31 e 23 cm do
  chute) e só metade do volante saía (o resto ficava na carroceria, por
  baixo do nosso). Agora busca de novo em volta do aro achado (os outros 23
  saem iguais); precisa rodar o gerar_buggies --classe truck --so 12,13.
  A coluna de direção da carroceria termina 1.1 cm atrás do aro (Renegade
  1.7, Storm 0.7 cm NA FRENTE) e atravessava o miolo recuado (dish): o
  volante avança pro piloto até a coluna acabar atrás dele (car.gd
  _montar_volante, de 0 a 5.6 cm no Kraken; teste_volante imprime). Os X
  ficam a 45° do topo, longe das mãos (65°).
  Eixo nosso (car.gd VOLANTE_EIXO, nov/2026, "braço muito torto no
  Fireball"): o aro do Fireball no modelo é o mais deitado dos trucks (46°
  acima da horizontal; os outros 14 a 36°) e torto ~5° pro lado; o pulso
  dobrava 28°/42° com o volante reto. O nosso volante fica reto a 30° (como
  Goliath, Chimera e Lazarus): 20°/27°, braço 90% (era 101%). Banco de lado
  quase não muda. VOL_EIXO=x,y,z testa.
  Braços iguais (piloto.gd PAREDE_SIMETRICA, nov/2026, "o esquerdo mais
  torto que o direito", Matheus): a pegada já era espelhada, mas só o
  cotovelo esquerdo batia na porta (ia pra -2°) e o direito ficava a +56°
  pra fora. Agora a folga da porta vale pros 2 (o cotovelo espelhado no
  plano do volante contra a parede do outro lado): no Fireball, com o
  volante reto, D pulso 26° cotovelo -1°, E 27° e -2°.
  Braço mais aberto (car.gd BRACO_ABERTO, piloto.gd cotovelo_min /
  parede_folga; "abre um pouco, sem varar a porta", Matheus): o -2° não era
  a porta, era a pose de pulso mais reto do IK. Fireball: cotovelo pelo
  menos 25° pra fora e folga de 6 cm da porta (manga ~5): abre 25° a 32°,
  pulso 29°/32°, medir_cabine 5.9 cm no pior caso. COT_MIN=graus e
  PAREDE=m testam.
- Volante: no jogo NÃO gira (é parte da carroceria). Girar é melhoria nossa
  (VOLANTE_GIRA no car.gd; tools/volante.py acha o aro). O que gira no jogo
  são os braços do piloto (piloto.gd).
- Som de pneu, suspensão e pouso = do jogo (sfx_carro.gd, docs Som de
  pneu): Suspen.bnk e VEHICLE.bnk existem mas o jogo NÃO carrega; a
  suspensão sai do Collide.bnk (BigSuspension/SmallSuspension) e o pneu do
  SURFACE.bnk, pelo SFX do material da pista. Só FL e RL tocam (+ Screech na
  FL no asfalto). Tom conferido com o SPU (tests/teste_sfx.gd).
  Programa de grãos = BlockSoundHandler do 989snd (som_jogo.gd; a mesma
  biblioteca foi reimplementada no jak-project, game/sound/989snd): relógio
  de 240 Hz, espera de cada grão ANTES dele, RAND_PLAY sem repetir, RAND_PB
  pela faixa PBLow/PBHigh do tom, SET_REGISTER_RAND (tom com volume < 0 lê
  o registrador). Antes era 1 ms e espera depois: no cascalho escuro os
  estalos de pedrinha (GRAVELEMENT1) saíam ~11/s, todos no máximo e no
  mesmo tom ("barulho bugado"); agora 2.65/s, volume 90-115, ±2 semitons.
  Envelope do SPU (_env_anda, ADSR de cada tom): parar é key-off (StopSound,
  0x264f28), a voz desce pelo release (0.17 s na terra e no cascalho) e a
  terra sobe em ~0.5 s. sons.json sem "versao" 2 = sfx_jogo.py antigo (o HUD
  avisa).
  Mistura NOSSA por cima (o Matheus achou o pneu rolando cansativo e alto):
  sfx_carro.gd SO_DERRAPANDO (pneu só derrapando, patinando ou travado;
  ROLAGEM = quanto do rolar reto fica) e GANHO_PNEU 0.6. Patinada só conta
  com o pneu escorregando > 1 m/s (PATINA_MIN): parado num barranco a
  patinada medida divide por quase zero e o som piscava (teste_ladeira).
- Fumaça do escapamento (melhoria nossa, car.gd FUMACA, fumaca.gd): o jogo
  NÃO solta fumaça. O efeito ExhaustSmokeTrail (xml 01416) e os pontos
  EXHAUST/EXHAUST2 existem, mas o exe não lê nenhum (sem cBehaviour*/
  cRenderer*; tabela de pontos 0x550700 sem EXHAUST; vídeo sem fumaça).
  Usamos os parâmetros do efeito; taxa de emissão e saída do cano são nossas.
  Storm não tem ponto EXHAUST no jogo: car.gd ESCAPE_NOSSO põe dois, medidos
  na boca das ponteiras cromadas do modelo (±0.57, 0.64, -2.49), 27° pra fora.
  Trucks: os 2 canos têm o MESMO nome EXHAUST (car._load_points guarda o de
  antes como EXHAUST~1; antes só saía fumaça de um) e 6 deles (Buccaneer,
  Shockwave, Jericho, Truggy, TT, Goliath) têm a mesma matriz copiada; o
  ESCAPE_NOSSO também troca os pontos do jogo quando a direção está errada
  (Chimera: o da esquerda veio com a matriz do da direita e soltava fumaça
  pra dentro). Nos outros a direção do jogo ficou (prints de perto: sai pra
  fora/baixo/trás no canto do cano). Punisher e Fireball não têm ponto.
  Fumaça x boca do cano (out/2026, "não sincroniza", buggy e truck): o
  GPUParticles3D solta as partículas de cada passo dele TODAS no ponto do
  emissor naquele quadro, e o passo padrão é 30/s: andando saíam bolos (a
  108 km/h um a cada 1 m) e em metade dos quadros a boca ficava sem fumaça
  encostada. Medido numa cena mínima (caixa a 30 m/s, quadros do Movie
  Maker): o emissor filho do corpo interpolado NÃO tem atraso, o problema é
  só o passo (fixed_fps 0 ainda dá um bolo por quadro). Agora fixed_fps 0 e
  as partículas do quadro saem numa caixa fina ao longo do trecho que a boca
  andou desde o quadro anterior (fumaca.seguir): rastro contínuo até a boca.
  Cada emissor é top_level, segue o carro desenhado e a malha tremendo da
  boca (motor_treme.bocas: Renegade no "escape"; Inferno, Trident, Phantom,
  Kraken, McKenzies, Viper, Hurricane e Storm no "motor"; Sphinx, Mosquito e
  Bulldog a boca não treme). tests/gravar_fumaca.gd (só no Forward+: no
  Compatibility do xvfb as partículas não aparecem).
- Poeira dos pneus (PORTA do jogo, nov/2026, car.gd POEIRA, poeira.gd;
  docs/engenharia_reversa.md, Poeira): o material do chão diz o tipo
  (DustType None/Light/Medium/Heavy) e a cor (DustColour); Setup/Dust.xml
  (data/dust.xml, conjunto CamSubject, "Rear" = rodas de trás) dá
  espaçamento, tamanho e vida por tipo. Força (|v| - 0.5)/35, solta acima de
  0.1; a cada ParticleSpacing metros nasce uma nuvem PARADA no ponto de
  contato, que cresce de ~0.8 m até 3-10 m e some (alfa x (1 - t²)); cor
  muda em 1 s quando o material muda (no asfalto, DustType None, apaga).
  Quirk do jogo mantido: no mesmo quadro cada nuvem nova sai com alfa x
  força de novo. Espaçamento: 1 - frente do carro . (câmera -> carro) puxa
  pro ParticleSpacingLookAlong; na câmera de corrida (atrás) vale o
  ParticleSpacing (15 cm). Até nov/2026 estava invertido (10 cm, 1.5x mais
  nuvens; o Matheus achou "denso demais"). A cor é a DustColour x textura (RX01 terra: marrom médio,
  alfa 0.5): é uma névoa marrom baixa atrás das rodas, como no vídeo; o
  fator de sombra (InShadowAmbientMultiply 0.5) só escurece e não está
  portado. Sem o fx_jogo.py novo não há assets/fx/poeira.png e não sai
  poeira. Falta: a "Dirt" (pedrinhas WheelSpinDirt/WheelDirtTrail,
  DirtKickupChance).
  No ar (nov/2026, "um restinho de rastro quando pulava", Matheus): o jogo
  continua soltando. A força perde 2 x a folga da roda até o chão (até 0.5;
  objeto de colisão veículo+0x9f0, +0x30 por roda) e com a roda a 25 cm ou
  mais do chão o material vira "nenhum" (a cor some em 1 s); antes disso
  fica o último que a roda tocou (0x2017a8 só troca veículo+0xa88 com a roda
  no chão). Ponto = centro da roda - up x (raio - afundado), recuado
  velocidade/60 (0x225108 e 0x20ff18). Pulando a 180 km/h no RX01
  (teste_poeira, 11 s) sai rastro por 0.78 s depois de sair do chão; antes
  parava na hora. O raio da suspensão só alcança 5 cm abaixo da roda: a folga
  no ar é um raio a mais (poeira._folga, até 0.3 m).
  "Muito grandes e quadriculadas" (Matheus, nov/2026, poeira e espirro): (1)
  TAMANHO: o do Dust.xml vai x 0.6 pra metros (poeira.gd ESCALA; o desenho
  é no VU1 e a unidade não sai do exe). Calibrado com 4 prints do jogo do
  Matheus (terra e poça) x renders do remake em 0.3/0.6/1.0: com 1.0 cobria o
  carro, com 0.3 ficava "fininho", 0.6 = na altura das rodas, atrás e dos
  lados. POEIRA_ESCALA=x troca (diagnóstico). Asfalto: a borda é
  TARMAC/DUSTY (DustType Light) e o asfalto limpo é None (cor some em 1 s):
  "vai diminuindo até sair", como o Matheus viu no jogo. (2) ALFA: o da
  textura é do PS2 (0x80 = 1.0, a poeira vai até 250 = satura); lido como
  255 = 1.0 saía com metade da opacidade. (3) Melhoria nossa: as nuvens do
  atlas encostam na borda da célula e o quadrado cortava o chão numa reta
  (os "quadrados"): BORDA_SUAVE apaga o alfa perto da borda da célula e
  CHAO_SUAVE (0.4 m, pela profundidade da tela) some a nuvem onde encosta no
  chão. SUAVE=0 desliga os 2 (diagnóstico). No Compatibility do xvfb a poeira
  não aparece: conferir em Forward+ (lavapipe).
  FECHADO pelo Matheus (nov/2026, escala 0.6): "não quero mexer mais, senão
  vira caça-rato". Só reabrir com save state ou vídeo novo que mostre erro.
- Pedrinhas do pneu (PORTA, nov/2026; pedras.gd, docs Pedrinhas): o
  WheelSpinDirt/WheelDirtTrail do XML o exe NÃO usa. Quem solta é o gerente
  0x3bade8 (string "dirt_rocks"): 0x3bb618 por quadro, só rodas de TRÁS, no
  material IsDirt, com patinada > sorteio(0..0.3) + 0.05 (ou curso acima de
  1 - DirtKickupChance), 1 por roda por quadro: pedra (Rockiness, 0.14,
  10 m/s, quica no chão com 0.4, vive 1 s, gravidade 30) ou borrifo de terra
  (Dirt05, 2.0 crescendo, 5 m/s, vive 0.6 s). Reto = quase pra cima, de
  lado (|β| 1 rad) = 45° pro lado em que escorrega; cor = DirtColour.
  Conferido no save state drr2 (80 vivas, 2 por quadro, tamanhos e
  velocidades). Tamanho x 0.6 como a poeira (vídeo do Matheus: pedra de ~10
  px do lado da roda). O mesmo gerente tem o estoque das lasquinhas da
  batida (Particle_Debris.bantam, 0x3bbd60): ainda não portado.
- Motor e escape tremendo (melhoria nossa, car.gd MOTOR_TREME,
  motor_treme.gd): no jogo são parte da Body e não tremem. Separação pelas
  peças soltas da malha que cabem inteiras no cofre (atrás do banco até o
  escape, entre as rodas de trás), sem pintura "white", pneu, sem textura,
  chapas/travessas e peças grandes. A textura "engie/engine" NÃO serve: é um
  atlas usado no painel, na frente e na gaiola. Conferido com prints
  vermelhos x normais (Sphinx, Phantom, McKenzies, Viper, Hurricane, Trident:
  só o metal do cofre). Também ficam de fora: lanternas (10 cm dos pontos
  BRAKE_LIGHT etc.), vigas/tubos retos (até 8 faces e > 30 cm; compridos e
  finos), chapas deitadas; a gêmea espelhada entra junto (os 2 escapes do
  Renegade). O que a regra erra vai em motor_treme.gd AJUSTES por carro
  (Viper: bloco de 8 faces e coletor; Phantom: barra em L do escape), achado
  com print_tela MOTOR_COR=2 (uma cor por peça, legenda no console,
  MOTOR_PAGINA=1,2 pras seguintes). Storm (motor escondido): só as 2
  ponteiras tremem (pelos pontos do ESCAPE_NOSSO).
  Vibração: 6 mm por quadro ficou "tremelento"; depois 4 mm filtrados em
  30 ms + balanço do torque de 3° numa mola mole (3 Hz, 25% do crítico)
  pareciam peças "desparafusadas" (Matheus, out/2026: o sorteio lento vira
  passeio e o balanço, 4.3° no pico, jogava a ponta do escape a 1 m do
  centro até 7 cm). Agora:
  zumbido de 1.5 mm na lenta (0.5 no corte) quase por quadro (8 ms), mais na
  vertical, e tranco de 0.8° num coxim firme (7 Hz, 60% do crítico, assenta
  sem quicar). O escape separado (Renegade) só vibra, não gira com o motor.
  Trucks (lote 4, out/2026; o Matheus: "99% só precisam de um toque no
  escapamento"): o motor fica embaixo do capô e a regra do cofre dos buggies
  pegava gaiola, estepe e caçamba (prints MOTOR_COR=2, vista "motor" do
  print_tela). Só o escape vibra (separar so_escape): peças pequenas soltas
  que encostam no EXHAUST + as faces a até PONTA 20 cm da boca (o cano quase
  sempre é a mesma peça da longarina ou da gaiola: Shinto 1.9 m). Pega no
  Buccaneer, Shockwave, Shinto, Jericho, Panther, Truggy (saída do lado),
  Hammerhead e Chimera; TT e Goliath têm a boca na pintura "white", Punisher
  e Fireball não têm ponto, o Lazarus fica com 1 face. Motor animado nos
  trucks (car.gd ANIMA_TRUCKS): Punisher (os 2 radiadores na caçamba) e,
  pedido do Matheus (nov/2026), Panther (2), Truggy (2 radiadores, 3 placas),
  TT (2), Hammerhead (1 deitada em cima) e Lazarus (3 viradas pra trás em cima
  dos estepes, textura preRunnerTruck_fan inteira = ventoinha, centro 32,32).
  Nos trucks elas têm raio de 27 a 31 cm e o limite de placa dos buggies (25
  cm, pra não pegar um painel do Mosquito) barrava: motor_anima
  RAIO_MAX_TRUCK 35 cm. Conferido com print_tela VENTOINHA_COR=1 (o que gira
  sai vermelho); de cima as do Lazarus ficam escondidas.
- Motor animado (melhoria nossa, car.gd MOTOR_ANIMA, motor_anima.gd): no
  jogo nada gira (ventoinha e polia são desenho parado na textura).
  Ventoinhas dos radiadores (textura "black" centro (89, 26) r 23 px; Trident
  "tube02" (48, 48) r 15): os triângulos da placa (caixa do UV com o centro
  do círculo; uma peça do cockpit do Renegade usa só um pedaço e fica) saem
  pra uma malha com shader que gira o círculo da textura. Elétricas (escolha
  do Matheus): 3 voltas/s fixas. 2 no Renegade, Sphinx, Mosquito, Inferno,
  Trident e McKenzies, 1 no Bulldog. Polias e correia 3D (escolha dele, no
  lugar de só girar o desenho): a "chassis_tri02" tem 2 polias desenhadas
  ((99, 23) r 9 e (100, 51) r 8 px; no Phantom e no McKenzies o UV dá uma
  volta na textura); onde caem (Phantom, Kraken, McKenzies, Viper) vira
  cilindro do raio desenhado com a tampa = o desenho do jogo girando, e uma
  correia pelas tangentes de fora com nervuras correndo. Faces em planos
  diferentes (Phantom e Viper): tampas no plano da mais saliente. Giro
  "legível": polia maior 1 volta/s a cada 1000 rpm (o real, 17 a 133
  voltas/s, é só um disco borrado), borrão do quanto girou no quadro. Presas
  na malha "Motor" (tremem junto). Trident fica sem polia: lá a textura cai
  esticada em outras peças.
- Volante tremendo (melhoria nossa, car.gd VOLANTE_TREME, _vibracao): no
  jogo nada treme (nem volante, nem mãos, nem motor: varredura do exe e
  vídeo). A força é a do motor pequeno da vibração do CONTROLE (0x202ab8:
  carro de lado, roda patinando devagar, roda travada, trancos pela
  velocidade) + pouso (0x370df0) e suspensão (0x36e498) do som + a tremida
  de curso das rodas da frente na terra (0x202760). Graus = escolha nossa.
- Sujeira (car.gd SUJEIRA, _sujeira_passo; sujeira.gd; docs Sujeira): o
  nível sobe min(v, 15)·WheelDirtRate·5e-5 a cada passo de 50 Hz com roda
  no chão (suja até no asfalto), igual em todo o carro, e só zera no
  recomeço (T no remake, car.limpar_sujeira). A água NÃO limpa a carroceria
  no jogo (só a lama da roda). Desenho: o lote do .pingu tem uma 2ª textura pelo 2º UV
  (pingu2obj -> <modelo>_camada.obj). Na carroceria só a pintura ("white")
  tem: a "dirt", trocada pela GEN_DIRT_DIRT da pista, alfa = nível x alfa
  da textura. Gaiola e peças ficam limpas (como no jogo). Nas rodas é a
  UNI_TyreOverlay: lama com a cor do DustColour do chão e alfa
  WheelDirtAlpha (some no asfalto; a água lava, 0x224418), car.gd
  _roda_suja_passo. teste_derrapagem confere os 2 com a RAM. Piloto: nível
  do carro com projeção nos 3 eixos da POSE DE REPOUSO (CUSTOM0/1 da malha;
  pela posição animada a sujeira ficava parada e o braço andava por dentro
  dela). Nosso: o jeito do jogo no piloto não foi achado.
  Sem rodar o gerar_buggies de novo não há _camada.obj e o carro não suja;
  sem o fx_jogo novo não há lama_pneu.png e o pneu não suja (o HUD avisa).
  No RX01 (taxa 0.2) a lama do pneu cresce devagar e quase só patinando
  (x10) e some no asfalto (alfa 0); na lama do Hinter Valley a taxa é 3.0.
- Painel funcional (melhoria nossa, car.gd PAINEL, painel.gd): no jogo os
  relógios são textura parada e 9 dos 12 buggies não têm. Amador (Level do
  vehicles.xml: Mosquito, Inferno, Trident, Sphinx) = conta-giros e
  velocímetro de ponteiro, fundo branco; PRO = os dois + marcha digital +
  luz de troca (5 LEDs de 85% ao rpm de troca, piscam no limitador), fundo
  preto (escolha do Matheus). Conjunto preso na coluna, atrás do volante, na
  linha do olho pela metade de cima do aro (sobe até caber na câmera do
  piloto); LADO = do lado direito do volante (Phantom, McKenzies, Hurricane,
  Storm: o volante tampava). AJUSTE por carro = números do Matheus com 9/0
  (desce/sobe) e -/= (lado) na câmera do piloto (o HUD mostra; só o
  conjunto mexe). Os relógios do modelo saem pra o nosso não ficar em cima
  de outro (pedido dele): a placa cadilac_clock do Renegade some, os
  relógios pintados da chapa b_2 do Sphinx são repintados com pixels do
  fundo (_sem_relogios; LED = mancha pequena ou vermelha fora dos discos).
  Pelo editor (F5) a textura vem com mipmaps (import "Detect 3D"): pinta o
  nível 0 e refaz os mipmaps, senão de lado os relógios velhos voltavam. O Inferno tem 5 buracos de relógio vazios em losango:
  o aro e o fundo preto saem da malha (APAGAR, _apagar_faces), e no lugar
  vão conta-giros (13 cm, pra não varar o capô), velocímetro (DO_MODELO) e
  3 auxiliares de enfeite (AUX: temperatura que esquenta no 1º minuto, óleo
  pelo giro, voltagem 12.4/14.1). No Renegade as 3 placas lisas do painel,
  as caixas pretas atrás delas e o "V" embaixo do volante (2 barras sem
  textura da coluna até o painel; APAGAR com textura "") saem e 2
  auxiliares vão presos no conjunto, um de cada lado (AUX_CONJUNTO, nos
  círculos que o Matheus marcou no print). Velocímetro = 1.06 x velocidade
  pra frente (como o do jogo); conta-giros até o limitador + 1000. Telas 2D em
  SubViewport (texto sai certo: base com determinante -1 dentro do espelho).
  Trucks (lote 3, out/2026): Buccaneer, Shockwave, Shinto, Jericho e Lazarus
  amadores, do Punisher em diante PRO (vehicles.xml). Tabelas pelo
  car.chave() (o Lazarus tem o id do Jericho). Shockwave, Jericho, Lazarus e
  Goliath: o relógio do jogo SAI INTEIRO (mostrador e o "pote" em volta) e o
  nosso fica NO LUGAR dele, com a caixinha preta atrás (pedido do Matheus,
  depois de 3 tentativas: só o conjunto atrás do volante não era; o nosso
  por cima do mostrador com o pote do jogo em volta também não). painel.gd
  NO_LUGAR [textura, centro e raio do mostrador no UV, texturas que saem,
  raio que sai]: Stock_truck_clock (relógio inteiro num hexágono, raio 0.38
  = até o meio das arestas; sai com cadilac_shock no Shockwave e
  cadilac_chrom2 no Jericho e no Lazarus, 1.9 x o raio) e, no Goliath, o
  canto de baixo à esquerda do atlas trophy_truck_light (UV (0.22, 0.79),
  raio 0.19, pote da mesma textura, 2.4 x; o atlas também é farol: só perto
  do volante). _mostradores_do_modelo acha centro, plano e tamanho pela conta
  UV -> 3D do maior triângulo de cada grupo (a até 50 cm do volante) e
  _tirar_relogios apaga da carroceria e da FaceDeDentro (cópia de dentro da
  cabine fechada; senão sobravam as viseiras). Maior = conta-giros, direita =
  velocímetro, o outro = temperatura; no Goliath (PRO) o outro é a marcha e a
  luz de troca vai em cima do conta-giros. APAGAR também apaga na
  FaceDeDentro (cópia de dentro da cabine
  fechada). Buccaneer: os mostradores
  pintados na willys_jeep_style_panel viram os nossos (posição pelo UV do
  texel; os 2 atrás do volante = conta-giros e velocímetro, o grande do meio
  e os 2 pequenos, abaixo da câmera, óleo, temperatura e voltagem). AJUSTE
  do Matheus: Shinto e Panther -0.03, Punisher e Fireball -0.04 de altura,
  Truggy -0.04 de lado, Chimera +0.01 lado e +0.02 altura; LADO: Truggy, TT,
  Hammerhead e Chimera (o volante tampava).
  Shockwave ("todo torto", out/2026): os 3 potes do modelo apontam cada um
  pra um lado (normais até 25° diferentes; a chapa do painel é virada 21° pra
  esquerda) e os da ponta ficam 2.6 cm desnivelados. NO_LUGAR "alinhar"
  (painel._alinhar): um plano só, virado pro olho do piloto, passando pelo
  conta-giros (fica onde está); os outros mantêm o x, ficam na altura média
  e a caixa preta vai até a chapa (o pote do jogo saía 12-13 cm dela).
  Auxiliares: o rótulo (TEMP °C, ÓLEO psi, VOLTS) caía em cima do C e do H
  embaixo; agora fica na metade de cima.

- Trucks (out/2026, base): 12 (TRUCK_01..12, nomes do menu do jogo em
  text/15205_en.txt: Buccaneer, Shockwave, Shinto, Jericho, Punisher, Panther,
  Herbst Truggy, Herbst TT, Hammerhead, Fireball, Goliath, Chimera). Física =
  data/vehicles/truck_base.xml (Setup/VehicleParams/Truck/TRUCK.xml, mesmo
  formato do buggy, outros números) + truck_NN.xml pelo caminho do arquivo
  (o TRUCK_03.xml do jogo é vazio: só a base). Chassis trocados: TRUCK_04 usa
  o CHASSIS_Truck_11, TRUCK_11 o CHASSIS_Truck_12, TRUCK_12 o Dakar (a
  pintura é do chassis: gerar_pintura acha pelo vehicles.xml). Mapas:
  TruckCompMap_B1/B2 (LeftFrame, RightFrame, FrontLeft/RightBrake, RearAxle
  com 2 modelos, Axle e Rear_Arm; o Rear_Arm do Shinto no 4K é vazio),
  TruckCompMap_A2 (Punisher, RearFreeAxle), BuggyCompMap_A1 (Panther, igual
  buggy) e RallyCompMap (Chimera, igual Storm). Melhorias nossas nos trucks:
  ligadas aos poucos, cada uma conferida com print (car.gd PENDENTES_TRUCK =
  as que faltam; main.gd e print_tela põem em car.desligadas). Lote 1
  (out/2026): luzes, farol e fumaça (o som do motor já tinha vindo). Lote 3:
  painel (ver Painel funcional). Lote 4: motor tremendo (só a ponta do
  escape) e motor animado (só o Punisher); PENDENTES_TRUCK ficou vazio. Lote 2:
  volante nosso, mãos no aro, volante girando e tremendo; câmera do piloto
  com o olho pelos números do Matheus (main.gd "fp"; padrão dos buggies
  [0.36, 0.47, 0.00] onde ele não mudou). Goliath parado (RAM): massa 1.90 t, marchas
  21.9/14.3/10.6/8.5/7.0, final 1.1636, CoM (0, 0.85, -0.609), curso máx
  0.55 / 0.76 = remake. O Goliath do save state tem as peças Prototype
  (motor 0.35 + 0.2 + 0.1 + 0.2, escape L3 0.1, câmbio Prototype 0.05 =
  1.0; de fábrica 0.81): com --tune engine 1.0 o remake dá embreagem
  1.023 e torque 2.964, igual à RAM. O Storm do storm.p2s também (torque
  1.764 = fully_tuned). Buccaneer de fábrica ("tudo Standard", DIRT_BUDGET):
  massa 1.70 t, marchas 17.5/11.4/8.5/6.8/5.6, final 1.0825 (Level0),
  embreagem 0.379, torque 1.088, CoM (0, 0.679, 0.414), curso máx 0.28/0.35
  = remake. Pintura dos trucks: o logo é achado sem diferenciar maiúscula
  nem espaço (o vehicles.xml pede "HERBST 1", a TruckLogos tem "Herbst  1";
  antes os dois Herbst saíam sem o logo) e o Chassis_Truck_10.bed diz 25
  itens com o 25º vazio (o gerar_pintura quebrava no Fireball; quem gerou
  os assets antes disso ficou com o Fireball BRANCO, sem pintura.png: o
  gerar_buggies agora avisa quando o gerar_pintura falha). Assets
  gerados dos 13 (12 + bônus) também estão no atv4-dados/cars (out/2026).
  Câmera dos trucks = a dos buggies (FollowOrbitFar parada: 6.87 m
  atrás e 3.0 acima no Buccaneer, 7.65/3.39 no Goliath, zoom 0.5;
  tests/teste_camera_ram.gd).
- Carro bônus resgatado (out/2026): a CHASSIS_Truck_04 está completa no
  jogo (4K, 5K, menu, COMPOSITOR 15106 com a pintura Truck_04_*) e nenhum
  veículo usa. É uma Chevrolet Silverado cabine dupla pre-runner (texturas
  preRunnerTruck_*, gravatinha da Chevrolet na preRunnerTruck_front): a
  carroceria original do Jericho ("Pre Runner"), que no vehicles.xml ficou
  com a CHASSIS_Truck_11 (sem logo nenhum; nenhum outro carro tem marca
  real). No remake é o "Lazarus" (nome escolhido pelo Matheus), último do menu (gerar_buggies.py BONUS,
  --so 13; main.gd "bonus"): peças de fábrica, mapa (TruckCompMap_B1) e
  decalques do Jericho, câmera TruckCamSet_04 (o Jericho usa a 11). Não
  substitui o Jericho. 2 estepes na caçamba (car.gd ESTEPES_NOSSOS): o
  modelo tem SpareWheel01Centre e 02 lado a lado, o mapa do Jericho só
  põe roda no 01. Física PRÓPRIA (nov/2026, números nossos com
  liberdade do Matheus): data/vehicles/lazarus.xml = cópia do Jericho com
  cabine dupla mais pesada (1.85 t, inércia maior), V8 com mais torque
  (1.30, embreagem 0.42), marchas mais longas (14.0/8.6/6.5/5.5/5.0),
  mais curso (0.50/0.68) com mola mais mole (40/27) e amortecedor 7,
  traseira mais grudada (elipse 12.8), mais subesterço (27) e CoM mais alto
  e pra frente (0.98, 0.13). O truck_bonus.xml (gerar_buggies) continua a
  cópia do Jericho. teste_extra com FROTA=16,25: 0-100 em 6.06 s (Jericho
  5.74), 182 km/h em 20 s (176), curso parado 0.21/0.26 (0.16/0.22);
  teste_capota a 80 igual (5.0°).
- Carros extras NOSSOS (nov/2026, main.gd EXTRAS; o Matheus quer alguns,
  começando pelo Escort): modelo .glb no padrão do Assetto Corsa (o que o
  Sketchfab tem: WHEEL_LF/RF/LR/RR com a origem no centro da roda, STEER_HR,
  SUSP_xx = cubo, COCKPIT_HR, ARROW_RPM...). tools/carro_glb.py mede no
  modelo e gera, no frame do jogo (x = -x do glTF): pecas.json (nós que saem
  da carroceria, roda e cubo de cada canto, volante centro/eixo/raio pelo
  PCA do STEER_HR, fonte e licença), _points.json (WHEEL_* = roda do modelo
  menos o curso parado, ARSE = volante - (0, 0.37, 0.46) como o
  VOLANTE_SEM_MODELO, EXHAUST na ponta do material de escape mais perto da
  borda com a direção do cano, BRAKE_LIGHT/HEAD_LIGHT pelos lados das
  luzes), _casco.json (2 fileiras de esferas de 0.36 + cabine de 0.42) e a
  física do --base (Storm) com rodas, curso, massa, CoM (53% na frente) e
  caixa trocados, e a relação final x raio novo / raio base (mesma velocidade
  por rpm). car.gd: carroceria pela cena importada do .glb (CarroGlb.malha:
  ordem dos vértices trocada e sinal da tangente virado pelo espelho;
  materiais PBR como vieram, sem material_do_jogo), roda e cubo de cada canto
  (não espelha), volante do próprio modelo girando, pontos .json,
  tuning_id (peças de fábrica de outro carro) e motor_escondido (só a ponta
  do escape treme, sem ventoinha). main.configurar(car, v) monta o carro igual
  no main, print_tela e testes. "desligar": volante_nosso, painel (o modelo
  tem relógios), sujeira (sem 2ª textura), farol (sem textura de farol).
  Escort RS1600 Mk1 1974 (vecarz, Sketchfab, CC-BY-NC-SA 4.0: dá crédito,
  sem uso comercial, derivado com a mesma licença; ripado de um mod do AC):
  200 mil triângulos, mão inglesa (volante na direita), escape saindo do
  lado esquerdo embaixo da porta. Curso parado medido no teste_extra: 0.114
  frente / 0.074 trás (o --estatico tem que ser esse, senão a roda parada
  fica fora do lugar do modelo); 0-100 em 4.0 s e 193 km/h em 20 s com a
  física do Storm (escolha de partida, falta afinar com o Matheus). Som =
  loops do Storm (I4) por enquanto. assets/escort/ fica fora do git (o .glb
  tem 17 MB): no PC, rodar o carro_glb.py com o .glb.
  "Pequeno e apagado" (Matheus, nov/2026): (1) ESCALA: o jogo desenha os
  carros ~25% maiores que os de verdade (entre-eixos: Storm = Delta S4 x
  1.24, Lazarus = Silverado x 1.27); o extra entra x 1.25 (pecas.json
  "escala", CarroGlb.malha; pontos, rodas, volante, casco, curso e CoM
  também). (2) MATERIAL: o export do Sketchfab põe metallicFactor 1.0 em
  pneu, borracha, plástico e banco (metal mostra o céu cinza no lugar da
  cor) e a pintura tem verniz (clearcoat): CarroGlb.do_jogo deixa metálico só
  no metal de verdade (METAIS), sem verniz, áspero >= 0.55 (fosco como os do
  jogo). (3) BRANCO: a textura do AC tem a sombra assada (branco do Escort
  200 de 255 = 0.58 linear; os do jogo ficam ~1.0 com a cor do vértice): o
  carro_glb mede o branco da pintura e clareia o material dela (x 1.25 no
  Escort, pecas.json "pintura"). Medido no mesmo print: 81 -> 116. (4)
  VIDRO das janelas verde-água a 53% em 2 camadas (a estrada ficava azul na
  câmera do piloto); neutro a 12% ficou leitoso (reflete o céu): o vidro das
  janelas SAI da malha (CarroGlb._vidro_janela; os carros do jogo não têm
  vidro), farol e lanterna ficam. MATERIAL_GLB=1 no print_tela mostra o
  material e o vidro como vieram do modelo.
  Carga (TEMPO_CARGA=1, tests/tempo_carga.gd): o motor_treme levava 3.3 s
  nos 200 mil triângulos (busca de peças em tudo + uma passada por
  superfície com PackedInt32Array copiado a cada append). Agora o extra só
  busca a 1 m da boca do escape e a repartição é uma passada só: 0.5 s; a
  carga toda ~1.2 s (fora a 1ª importação do .glb no editor).
- Casco de colisão (out/2026, docs Casco de colisão): até então era uma caixa
  de 2.1 x 0.8 x 4.8 m igual pra todos, sem fonte. O jogo carrega
  Vehicles/<Classe>/Collision/<Name>/VehicleWorld.hsc (0x1fed48) pelo ID do
  veículo, não pelo chassi (Storm = Buggy_12 na RAM; Fireball = Truck_10):
  o Jericho usa o casco da Silverado (Truck_04) e o Chimera o Truck_12.
  Contato com o mundo = só as ESFERAS do arquivo (os planos não recortam:
  Fireball de lado/capotado, save states do Matheus, contato exatamente na
  esfera e 3.4 cm fora dos planos) + a RODA como esfera do raio dela quando
  o chão está fora do cone da suspensão (Cosine_maximum_collision_angle
  0.643 = 50°): de lado o 2º contato fica a 0.567 m do centro da roda
  dianteira = o raio. car.gd _casco (SphereShape3D por esfera) e
  _esferas_das_rodas (ligada a cada passo por uma consulta de esfera 3 cm
  maior). Testamos antes esferas recortadas pelos planos num envoltório
  convexo: com ~700 pontos o Godot deixava o carro atravessar o chão.
- Força lateral pela inclinação (0x211b58, out/2026): a altura onde a força
  lateral do pneu age (Lateral_scale) cai de 0.09 a 0 entre 3° e 8° de
  inclinação em relação ao chão (sine_threshold/maximum_roll do XML, buggy e
  truck). O remake usava sempre 0.09 e os trucks tombavam mais (Fireball
  virando a 80 km/h: 8.8° -> 6.0°, tests/teste_capota.gd). Aceleração,
  derrapagem e entrada a 110 não mudaram (o Renegade fica abaixo de ~4.5°).
- Fireball parado (Fireball.p2s do Matheus, out/2026): curso FL/FR 0.248/0.240,
  RL/RR 0.350/0.354 (máx 0.50/0.70) e as 10 peças = remake (erro 0). O
  desalinhamento com curso grande é a fórmula do exe: RearAxle gira pelo
  curso MÉDIO das 2 rodas de trás (sem inclinar quando uma sobe e a outra
  desce) e cada roda sobe sozinha (WHEEL + x); LeftFrame/RightFrame giram
  tan(x/W.x) com a roda subindo reto. No curso máximo a roda de trás do
  Fireball fica 50 cm abaixo do fundo do casco (o batente 0x23f6c0 segura).
  Melhoria nossa (pedido do Matheus, out/2026; car.gd "eixo_rigido",
  suspension_visual.pose_truck(inclina)): o eixo de trás (RearAxle e
  RearFreeAxle) também inclina pra ligar os 2 cubos, girando em volta da
  linha ARM_PIVOT -> meio do eixo (phi = atan(s / u.z), s = dy/dx entre as
  rodas), e as rodas de trás inclinam junto (só giram no lugar: o centro é o
  da física). A frente ficou como o jogo: o tan do braço fica a ~2° da conta
  exata. O teste_pecas usa a fórmula do jogo (inclina = false).
  print_tela CURSO=TEmax/TDmin força curso por roda; DESLIGAR=eixo_rigido
  mostra o do jogo.
- Câmera do save state: só a câmera ativa atualiza. ler_savestate pegava a
  mais perto do carro, e parado essa é uma que a introdução da corrida
  deixou (zoom 0.6027, suavização 17.85/s em a.p2s, b.p2s, Goliath e
  Buccaneer). A ativa é a de suavização ~40/s (corrigido out/2026).

## Pendente / ideias

- Lazarus: física própria feita (lazarus.xml); peças, mapa e decalques
  ainda são os do Jericho. Não suja: a CHASSIS_Truck_04 do jogo não tem a 2ª textura (sem _camada.obj
  mesmo gerando de novo; o aviso do HUD não se aplica).
- Trucks: FECHADO pelo Matheus (nov/2026). Aceleração conferida (Buccaneer,
  vídeo); a curva usa o mesmo código de pneu dos buggies (conferido com save
  states na derrapagem) e no vídeo tem o mesmo comportamento. Só reabrir com
  save state na curva se algo parecer estranho jogando.

- Pneu e aro comprados (hipótese: troca de textura, ver docs/assets.md).
  Provável resposta: 56 rodas completas sem nome no archive dos buggies (45
  nos trucks) = 8 pneus x 7 aros (docs/assets.md, Modelos que o jogo não usa).
- Modelos que o jogo não usa (docs/assets.md): CHASSIS_Truck_04 (pré-runner,
  o "Lazarus", nome escolhido pelo Matheus), CHASSIS_ATV_03..08 e os de IA
  (quadros sem carenagem), carenagens SandStorm e WolfTrekker (pinturas da
  carenagem do ATV_04, cortadas da beta: entram como "pinturas resgatadas"),
  CHASSIS_Bike_01/02 (motos inteiras com plásticos na malha). Buggy: nada.
  Pistas fora da lista do jogo: NAT_09 original (o NAT09 do jogo é a pasta
  NAT_NEW), NAT_WAHOO (pista de teste), NAT_10 e RX_AI incompletas, minigames
  MIN_02/MIN_Target/MIN_RING_OF_FIRE; o relevo delas depende do stream do
  disco (STREAMT).
- RX01, falta: LOD das árvores, reposição (cInstantRespotBox),
  câmera de introdução, as 2 luzes direcionais. A tremida da batida
  (0x380418) agora tem objeto pra bater; trava (veículo+0xa6c/0xa74/0xa78)
  não portada.
- Som do motor (melhoria nossa, plano combinado com o Matheus): o jogo só
  tem 3 bancos de motor (02/03/04, XMLs 00002/00004/00005) repetidos nos 12
  buggies (o Mosquito soa igual ao Kraken V8). Plano: o Matheus monta cada
  motor no Engine Simulator e grava loops de 1-2 s a cada 500 rpm,
  acelerando e soltando, cortados no zero da onda; no Godot um tocador faz
  crossfade + pitch entre os 2 samples vizinhos e mistura acelerando/
  soltando pelo acelerador. RPM: opção (b), o 1000-8000 do jogo (igual nos
  12) esticado pra faixa real de cada motor. Constante pra voltar ao som do
  jogo quando ele for portado. Motor proposto por buggy (nome interno do
  vehicles.xml + base real + HP de fábrica, com fontes) e o jeito de
  gravar: docs/som_motor.md. Feito: os 12 .mr (som/engine_sim, LEIA-ME
  com cv e lenta medidos), os loops (som/loops) e o tocador (motor_som.gd,
  car.gd SOM_MOTOR; N no jogo deixa mudo). Ajuste de volume: K_RPM, K_OFF
  e PISO_DB no motor_som.gd. FECHADO (out/2026, o Matheus aprovou os 12):
  Trident e Viper com escape/filtro escolhidos de ouvido entre variantes.
  Zumbido ou apito num tom só = filtro mild_exhaust do engine-sim (pico em
  133 Hz), não o tamanho do tubo (som/engine_sim/LEIA-ME.md).
  Trucks (out/2026): 13 motores (t01..t12 + t13 Lazarus, motor da Silverado), carro real pelo
  modelo 3D ou escolha nossa variando a família (docs/som_motor.md, Trucks);
  o som do motor ficou fora do car.gd PENDENTES_TRUCK (toca nos trucks); pasta pelo id (motor_som.pasta_do_carro, tNN_) ou pela
  entrada "som" do main.gd (bônus). Falta o Matheus ouvir.
- Piloto: montar a textura dele como o jogo (5 camadas por parte + cores do
  perfil; hoje usa o rider_fury pronto), LOD MID/LOW, piloto feminino.
- Câmera do piloto: referência do Matheus = cockpit do Dirt Rally 2.0
  (horizonte perto do meio, volante cortado embaixo, muita estrada).
- Sinal do giro/direção visual: falta save state andando com volante virado.
- Sujeira: reflexo menor com o carro sujo (0x22ace8, 1 - nível) não
  portado. Sujeira do piloto como o jogo.
- Erro antigo com tela (não é da poeira): "Condition !v.is_finite()" em
  instance_set_transform quando o carro pula fora da pista (gravar_poeira na
  terra: 238 vezes em 2 s, com a poeira desligada também); sem tela não
  aparece. Algum nó visual recebe transformação com NaN.
- Para-choque e luzes comprados (componentes Bumper/Lighting; de fábrica é NOT_INSTALLED).
  Os LIGHTRIG são só modelo (sem halo); o Matheus acha feios.
