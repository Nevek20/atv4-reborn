# ATV4 Reborn

Remake em Godot 4 do **ATV Offroad Fury 4** (PS2, PAL, SCES_546.88), com o
objetivo de ficar **100% fiel ao jogo**. Os dados (física, câmera, peças,
pintura) vêm dos XMLs do próprio jogo e o comportamento vem do executável
desmontado no Ghidra. Nada de "parece certo": cada número tem que ter fonte
(XML, função do exe, save state ou vídeo). O que é invenção nossa é marcado
"melhoria nossa" / NOSSO no código e nos docs.

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
- Antes de entregar: `python tests/rodar_tudo.py` (todos os testes sem tela,
  ok / FALHA). Antes de mudar física: `python tests/rodar_testes.py` e
  comparar com as referências. Se um número piorar, explicar por quê.
- Antes de mexer num assunto, ler a seção dele no `docs/historico.md`: lá
  está o que já foi tentado, medido e reprovado. Ao terminar, a história
  nova vai pro histórico e aqui só a regra curta.

## Onde está cada coisa

- `docs/historico.md`: o porquê de cada decisão, por assunto (fontes,
  números, o que o Matheus aprovou/reprovou). Fonte da verdade do projeto.
- `docs/engenharia_reversa.md`: mapa do exe (endereços, estruturas, XMLs).
- `docs/comandos.md`: TODOS os comandos, testes e variáveis de diagnóstico.
- `docs/derrapagem.md`, `docs/assets.md`, `docs/som_motor.md`: temas grandes.

## Estrutura

```
main.gd / main.tscn  cena: terreno, carro, câmera, HUD (F1 esconde, F2 FPS), menu de carros (Tab, V);
                     VEHICLES = buggies, TRUCKS, EXTRAS (nossos), frota() = os três, configurar(car, v)
carro/               o carro
  car.gd               a FÍSICA portada do exe (suspensão, pneus, motor, câmbio, pedais, casco,
                       batida) e o _ready; herda do carro_montagem.gd, que herda do carro_base.gd
  carro_montagem.gd    montagem e visual: modelo, rodas, cabine, piloto, volante, carga dos
                       efeitos, sujeira, vibração, visual por quadro (não mexe na física)
  carro_base.gd        constantes, variáveis de estado e ajudantes pequenos (corpo, jogo, chave)
  vehicle_data.gd      leitor dos XMLs (base + veículo) e peças de fábrica
  suspension_visual.gd balanças, amortecedores e freios do jogo se mexendo
  carro_glb.gd         carros extras nossos (.glb no frame do jogo)
  piloto.gd            piloto do jogo no ARSE, braços pela direção (STEER_LEFT) e mãos no aro
  volantes.gd          volantes gerados, um estilo por carro (melhoria nossa)
  painel.gd            painel funcional (melhoria nossa)
  motor_treme.gd       motor e escape tremendo (melhoria nossa)
  motor_anima.gd       ventoinhas, polias e correia girando (melhoria nossa)
  luzes.gd, farol.gd   lanterna de freio, ré e farol acesos (melhoria nossa)
  sujeira.gd           sujeira do jogo na pintura e lama nas rodas
camera/              game_camera.gd (câmera de corrida do exe), camera_jitter.gd (tremida),
                     camera_piloto.gd e camera_orbita.gd (melhorias nossas)
efeitos/             poeira.gd, pedras.gd, lascas.gd, palha.gd (portas do jogo), fumaca.gd (nossa)
pista/               terrain.gd (relevo e material do RX01), objetos_rx01.gd, multidao.gd, ceu.gd
som/                 motor_som.gd (motor, nosso), sfx_carro.gd (pneu, suspensão, pouso, batida do jogo),
                     som_jogo.gd (tocador 989snd); engine_sim/ e loops/ (os motores gravados)
data/                XMLs e JSONs do jogo (física buggy_NN.xml, pontos, câmeras, peças, pista)
assets/              gerados pelos tools (fora do git, menos o terreno): carros/ (buggy_NN, truck_NN,
                     truck_bonus, escort, rodas), piloto/, pista/ (rx01, terreno), efeitos/, sons/
tests/               testes sem tela (rodar_tudo.py roda todos), prints e gravações
tools/               scripts Python de extração (pingu2obj, pintura, savestate, efeitos, sons)
re/                  engenharia reversa: scripts do Ghidra, exe_util, dumps
docs/                historico.md, engenharia_reversa.md, comandos.md, derrapagem.md, assets.md, som_motor.md
```

## Comandos do dia a dia

```
set GODOT=C:\caminho\Godot_v4.x-stable_win64_console.exe
python tests/rodar_tudo.py                    :: todos os testes de conferência (ok/FALHA), em paralelo
python tests/rodar_tudo.py --relatorios       :: + relatórios (capota, largada...) e o rodar_testes
python tests/rodar_tudo.py volante pedras     :: só esses
python tests/rodar_testes.py                  :: física: aceleração dos 3 carros x referências
%GODOT% --headless --path . --check-only --script res://carro/car.gd   :: checar um script
%GODOT% --path . -s res://tests/print_tela.gd -- print.png lado  :: print do carro (variáveis: docs/comandos.md)
python tools/ler_savestate.py arquivo.p2s     :: save state do PCSX2 -> valores reais do jogo
python re/exe_util.py SCES_546.88 str NOME | jal 0xEND | words 0xEND 32   :: caçar no exe
```
Gerar assets no PC (fora do git; detalhes em docs/comandos.md):
`tools/gerar_buggies.py` (carros, `--classe truck`), `tools/gerar_pintura.py`,
`tools/fx_jogo.py` (texturas de efeito), `tools/sfx_jogo.py` (sons),
`tools/rx01_objetos.py` (pista), `tools/piloto.py`, `tools/carro_glb.py`
(carros extras nossos).

Na nuvem (Claude Code web) o `.claude/hooks/session-start.sh` instala o
Godot 4.7.1 de Linux, Pillow e zstandard e já deixa `$GODOT` pronto. O
projeto roda em Forward+ e o xvfb só tem OpenGL (Compatibility, conta de cor
diferente). Pra ver igual ao PC: `apt-get install -y mesa-vulkan-drivers` e
rodar com `VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json` e
`--rendering-method forward_plus --rendering-driver vulkan` (lavapipe,
lento). Partículas (fumaça, poeira) só aparecem no Forward+.
Os arquivos do jogo ficam no repo privado `Nevek20/atv4-dados` (exe, stream,
unpacked, save states, vídeos). Texturas: `python tools/gob_tex2png.py
<dados>/unpacked/gob --out <dados>/texturas` (uns 6 min). No PC do Matheus:
`C:\Users\Guida\Desktop\Estudo de programação\ATV 4 Engenharia reversa`.

Ghidra headless (12.1.3 + ghidra-emotionengine-reloaded; na nuvem `bash
re/instalar_ghidra.sh`, ~7 min, projeto `atv4` em `~/ghidra_proj`):
```
analyzeHeadless <proj_dir> atv4 -process -noanalysis -readOnly ^
  -scriptPath re/ghidra_scripts -postScript DecompRefs.java saida.c lista.txt
```
`lista.txt` = um endereço `0x...` ou uma string por linha.

## Referências do jogo de verdade (números completos no docs/historico.md)

- Save state do Renegade (151 km/h, 4ª): massa 1.2 t, rpm 6582, curso,
  câmera. Speedrun do Sphinx (NTSC, 60 Hz): mph quadro a quadro (tabela no
  rodar_testes.py). Renegade PAL largando no RX01 (vídeo + 5 save states,
  teste_largada). Derrapagem: 4 + 5 save states (teste_derrapagem,
  teste_entrada). Buccaneer na largada (2 vídeos, teste_truck_video).
- Velocímetro do jogo ~1.06 x a velocidade pra frente (buggies; o Buccaneer
  mostra direto).

## Regras que já custaram caro (o detalhe de cada uma no docs/historico.md)

Arquivos, modelos e pintura
- Física = ordem da lista do jogo: 15145 é a base E o 1º buggy. Renegade =
  15154 (BUGGY_10), Sphinx = 15148 (BUGGY_04); 15150 é o Phantom.
- Peças de fábrica: vehicles.xml DefaultConfig + upgrades.xml; efeitos
  SOMAM. Final: Level0/1 = 0.45/0.53, Level2+ = a custom 0.61.
- Blocos: nunca pela posição no unpacked; data/arquivos.tsv dá caminho ->
  bloco. Corrida usa Models_4K.
- Pasta do carro = assets/carros/<id do jogo> (buggy_10 é o Renegade). Os
  arquivos têm o número do bloco no nome (rastreável); pecas.json é o índice.
  PC com as pastas antigas: `python tools/migrar_assets.py`.
- .obj só reimporta quando ELE muda (o .mtl não conta). Pintura nova precisa
  reimportar (`--headless --import`). Sem pintura.png o carro fica branco.
- Triângulo com giro trocado no modelo do jogo (quadrado com 1 dos 2 virado):
  carro_montagem.gd _acertar_giro conserta ao carregar (ELF do Hammerhead).
- Cor do vértice do .pingu (0x80 = 1.0, até 2.0) multiplica a textura.
  Alfa: só mesh_grey, Buggy_05_framework e driver têm furo.
- Texturas .gob com mipmap: o nível 0 começa no 0x15c.

Física
- Física a 50 Hz (PAL); o jogo DEPENDE do passo. Vídeo NTSC = 60 Hz.
- MÃO: o jogo é mão esquerda. Carro = nó `espelho` (-1,1,1), física em
  car.corpo(p), mundo = (z - 1024, y, x) do jogo. Nunca converter 2 vezes
  (teste_chao, teste_mao).
- Ordem da roda no passo: integra -> contato -> mola -> pneus.
- Suspensão = cCompPlace_* do exe (teste_pecas com a RAM). Trucks: tan(x /
  W.x), RearAxle pelo curso médio.
- Casco = só as esferas do VehicleWorld.hsc + a roda como esfera fora do
  cone da suspensão.
- Material do chão: só atrito e Damping mexem na física. Hardness, Sink e
  Bounciness o jogo não lê: não portar.
- Pedais: cru e suavizado; parado o jogo põe freio 1.0 sozinho. NÃO tem
  freio de mão: o botão é a embreagem (Clutch Turn ao soltar).
- Derrapagem não volta sozinha (RecoveryTorqueCutting). Não "afrouxar" no
  chute (o Matheus comparou e ficou pior).

Câmeras
- A câmera mira a ORIGEM DO MODELO (veículo+0xaa0), não o CoM. Zoom -> FOV:
  meia-altura = 0.375/zoom (4:3). Passos de 1/60 interpolando no frame do
  carro, cada passo com o carro no tempo dele.
- Do save state, só a câmera ativa atualiza (a de suavização ~40/s).
- Para-choque (On_Front, mRenderVehicle 0): nada do carro aparece, nem as
  rodas. Capô (On_Hood): o carro aparece, o piloto não.

Pista RX01
- Terreno e material do stream do jogo (conferidos com a RAM). Objetos vêm
  do evento (#def5772a + RALLYCROSS.bin); instâncias são espelhadas.
- Chão com luz assada: sem luz do Godot. PS2 sem tonemap; névoa linear.
- Poça: transparência POCA_ALFA 0.5 é NOSSA (o modo do GS não foi achado).
- Cercas quebram pelo impulso do jogo (ShatterImpulse 2); fardo = 100 kg.

Efeitos e som (todos FECHADOS pelo Matheus: só reabrir com prova nova)
- Poeira, pedrinhas e lasquinhas = porta do jogo, tamanho x 0.6 (VU1 não
  lido, calibrado em prints). Fumaça é melhoria nossa (o jogo não solta).
- Som de pneu, suspensão, pouso e batida = do jogo (989snd). Mistura nossa
  por cima: SO_DERRAPANDO e GANHO_PNEU 0.6.

Carro por dentro (melhorias nossas, cada uma aprovada com print)
- Lanterna e farol: o nosso (lente acesa pelos pixels), não o halo do jogo
  (o Matheus achou o do jogo mais feio). Não voltar.
- Volante: no jogo não gira; o nosso gira, um estilo por carro. Alisar o
  aro do jogo quebrou: não voltar.
- Mãos no aro por IK com tabela por carro. Mão de fora parar escorregando
  pelo aro foi reprovado: não voltar. Banco, eixo do volante e braço aberto
  por carro: car.gd BANCO_NOSSO, VOLANTE_EIXO, BRACO_ABERTO.
- Motor treme e anima, painel, cabine fechada: tabelas por carro em
  carro_base.gd e nos scripts deles (AJUSTES, NO_LUGAR...).
- car.gd em 3 camadas por herança (base -> montagem -> física): função nova
  vai na camada do assunto; a de baixo não pode chamar a de cima (o Godot
  recusa ao compilar). As tabelas por carro (BANCO_NOSSO, VOLANTE_EIXO...)
  ficam no carro_base.gd.

Frota
- 12 buggies, 12 trucks, o bônus Lazarus (CHASSIS_Truck_04, física própria
  NOSSA) e extras nossos de .glb (Escort, x 1.25). Tabelas por carro usam
  car.chave() (o Lazarus tem o id do Jericho).

## Pendente / ideias

Lista completa no fim do docs/historico.md. Os principais:
- RX01: reposição (cInstantRespotBox), câmera de introdução, 2 luzes
  direcionais, LOD das árvores.
- Lasquinhas e som da batida carro com carro (quando tiver IA).
- Piloto: textura em camadas como o jogo, LOD, piloto feminino.
- Erro antigo com tela: "Condition !v.is_finite()" quando o carro pula fora
  da pista (algum nó visual com NaN).
