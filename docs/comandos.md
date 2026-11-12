# Comandos (lista completa)

O CLAUDE.md tem só os do dia a dia. Aqui estão todos, com as variáveis de
diagnóstico de cada teste e ferramenta.

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
CAM_MODO=3 %GODOT% --path . -s res://tests/print_tela.gd -- p.png jogo 23   :: print com a câmera do main (2 capô, 3 para-choque)
:: DESLIGAR=barras_presas no print_tela: barras da traseira dos buggies girando com a balança como o jogo (soltas)
:: DESLIGAR=haste_estica no print_tela: haste do amortecedor de trás dos buggies rígida como o jogo (solta e vara comprimindo)
:: DESLIGAR=balanca_desloca no print_tela: balança da frente do Fireball onde o jogo põe (a ponta sai pela roda)
:: DESLIGAR=telescopio no print_tela: amortecedor da frente do Hammerhead como o jogo (gira com a balança e sai pelo capô)
set GIRO_DEBUG=1 & %GODOT% --headless --path . -s res://tests/teste_luzes.gd   :: + quantos triângulos com o giro trocado do jogo cada carro consertou (carro_montagem _acertar_giro)
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
set VEL=20 & %GODOT% --headless --path . -s res://tests/teste_lascas.gd   :: lasquinhas e som da batida: Storm numa parede (20 m/s = 3 lascas + BigImpact, 10 m/s = 0 + SmallImpact, até 8 vivas, 4 s)
%GODOT% --path . --fixed-fps 60 -s res://tests/gravar_lascas.gd -- 0 lascas    :: prints depois da batida (QUANDO=0.1,0.3,1.0; VEL=25, LASCAS_COR=1)
:: + print_tela com MOTOR_COR=1 pinta de vermelho as peças que tremem, VENTOINHA_COR=1 as ventoinhas que giram
%GODOT% --path . --write-movie previa.avi --fixed-fps 60 -s res://tests/gravar_som.gd -- 8   :: prévia com áudio (acelera e solta; VIRA=5 derrapa, SEM_MOTOR=1, SOM_PASTA=<pasta dos loops> troca o motor pra comparar variantes)
set VEL=110 & %GODOT% --headless --path . res://tests/teste_entrada.tscn   :: reto até VEL e vira tudo: quando passa de 20° (jogo: 110 não derrapa)
:: + SOLTA=1.3 solta o volante (DEPOIS=-1 contra-esterça, ACEL=0 solta o acelerador), DUR=8 segundos depois de virar
%GODOT% --headless --path . -s res://tests/medir_tremor.gd -- 60 tremor.csv  :: distância câmera-carro por quadro

:: carro extra NOSSO de um .glb no padrão Assetto Corsa (WHEEL_LF..., STEER_HR) -> assets/carros/<nome> + data/vehicles/<nome>*
python tools/carro_glb.py <modelo.glb> Escort [--estatico 0.114,0.074] [--escala 1.25] [--massa 0.9] [--base buggy_12]
%GODOT% --headless --path . -s res://tests/teste_extra.gd   :: extras: curso parado x estático, casco, 0-100 e velocidade
set TEMPO_CARGA=1& %GODOT% --headless --path . -s res://tests/tempo_carga.gd   :: ms de cada etapa da carga (VEH=26 Escort)

:: casco de colisão de cada carro (esferas do VehicleWorld.hsc pelo id) -> data/vehicles/<id>_casco.json
python tools/casco.py <unpacked>          :: --tabela mostra a caixa de todos os cascos do archive

:: terreno do RX01 (alturas + material) a partir do stream do jogo
python tools/extrair_material.py <dados>/stream/RX01.000 assets/pista/terreno --materiais <dados>/unpacked/xml/12280
:: objetos e céu do RX01 (posições + colisão -> data/rx01_objetos.json, Environment.xml -> data/environment_rx01.xml;
:: modelos, texturas e cúpulas do céu -> assets/pista/rx01)
python tools/rx01_objetos.py <unpacked>          :: --so-json só o JSON; depois abrir o editor (importa os .obj)
%GODOT% --path . --write-movie corrida.avi --fixed-fps 30 -s res://tests/gravar_corrida.gd  :: vídeo da largada: intro, acelerando preso, VAI (DEPOIS=6 s, PULAR=1 pula a intro, CHECA_NAN=1 acha nó com NaN)
%GODOT% --headless --path . -s res://tests/teste_corrida.gd   :: modo corrida: introdução, espera acelerando sem andar, VAI pra frente, 5 voltas pelo traçado, atalho pela linha não conta
%GODOT% --headless --path . -s res://tests/teste_batida_carros.gd   :: rival a VEL km/h (50) na traseira do jogador: cascos do VehicleVehicle, empurrão, lasquinhas, som Vehicle
%GODOT% --headless --path . --fixed-fps 50 -s res://tests/medir_cpu.gd   :: CPU da corrida com 8 carros: física e process por parte (IA, batida, visual, script do carro)
%GODOT% --headless --path . -s res://tests/teste_reposicao_auto.gd   :: reposição automática do jogo: corredor do AIT, fora da pista 3.2 s, contramão 5.2 s, botão (40 mph)
%GODOT% --headless --path . -s res://tests/teste_reposicao.gd   :: as 14 caixas de reposição do RX01: cada uma repõe na linha, chão plano, longe dos rivais
%GODOT% --headless --path . --fixed-fps 50 -s res://tests/teste_ia.gd   :: rivais da IA: 1 volta (VOLTAS=n, SEMENTE=n, DBG=1 quem fica lento, IA_LOG=1 reposições e ré, IA_TRACE=<nome> quadro a quadro)
%GODOT% --path . --fixed-fps 50 -s res://tests/print_ia.gd -- ia   :: prints da corrida com rivais (QUANDO=-1,2,25: -1 = no grid)
python tools/ia_dados.py <unpacked>             :: pilotos (AIPlayers) e catchup -> data/ia.json
python tools/rx01_corrida.py <unpacked>          :: traçado da IA, checkpoint e voltas do RX01 -> data/rx01_corrida.json

:: checar um script sem abrir o editor
%GODOT% --headless --path . --check-only --script res://carro/car.gd

:: sons de pneu, suspensão e pouso do jogo -> assets/sons (wav + sons.json com o ADSR de cada tom)
python tools/sfx_jogo.py <unpacked>
:: textura da fumaça (Sprites/Particles, caixa Dust0), da palha (Snow0), da sujeira (GEN_DIRT_DIRT), da lama do pneu (UNI_TyreOverlay) e da poeira (WorldFXdust) -> assets/efeitos
python tools/fx_jogo.py <unpacked>
:: + print_tela com SUJEIRA=0.8 força o nível da sujeira, PAINEL=6900,137 fixa rpm e km/h no painel,
::   SEM_PAINEL=1 esconde o nosso (pra ver o que sobrou do modelo)

:: piloto (malha, esqueleto, animação da direção, textura) -> assets/piloto
python tools/piloto.py <unpacked>

:: assets/ das pastas antigas (renegade, sphinx, fx, sfx, rx01, terrain...) pras novas (carros/, pista/, efeitos/, sons/)
python tools/migrar_assets.py            :: --ver só mostra; depois %GODOT% --headless --path . --import

:: assets dos 12 buggies (modelo, peças, freios, rodas, pintura; + <modelo>_camada.obj com o 2º UV) -> assets/carros/buggy_NN
python tools/gerar_buggies.py <unpacked> [<texturas>]   :: sem a pasta: "texturas" do lado da unpacked; para se não achar .png
python tools/gerar_buggies.py <unpacked> [<texturas>] --classe truck   :: os 12 trucks -> assets/carros/truck_NN, data/vehicles/truck_NN*
:: só o alfa das texturas com furo (redes das janelas, treliça do Trident); o gerar_buggies já chama
python tools/alfa_texturas.py <unpacked>
:: só a pintura (cores, logos e número "00"; --numero 27, --sem-decalques); depois reimportar no Godot
python tools/gerar_pintura.py <unpacked> BUGGY_10 assets/carros/buggy_10
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

No jogo: F2 = FPS + onde vai o tempo (quadro, física por passo, desenho CPU/GPU,
chamadas de desenho, rivais), média de 0.5 s.
