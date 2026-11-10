# Assets do jogo → projeto

Tudo sai da pasta `unpacked` (other/raw/gob/xml + manifest.json) gerada a
partir do archive.imp. Os scripts estão em `tools/` (rodar na pasta que tem
o `unpacked`). As texturas PNG vêm do `gob_tex2png.py` (pasta `texturas`).

## Pastas (assets/, fora do git)

```
assets/carros/buggy_01..12   o número do jogo (BUGGY_NN): buggy_10 = Renegade, buggy_04 = Sphinx
assets/carros/truck_01..12   trucks (TRUCK_NN), truck_bonus = Lazarus
assets/carros/escort         carro extra nosso (tools/carro_glb.py)
assets/carros/rodas          rodas de todos (o pecas.json aponta "../rodas/...")
assets/piloto                piloto (tools/piloto.py)
assets/pista/rx01            objetos e céu do RX01 (tools/rx01_objetos.py)
assets/pista/terreno         relevo, material e textura do chão (no git; hd/ fora)
assets/efeitos               texturas de efeito (tools/fx_jogo.py)
assets/sons                  sons do jogo (tools/sfx_jogo.py)
```
Dentro de cada carro os arquivos guardam o número do bloco do archive
(`20800_bloco.obj`, `15199_white.png`): dá pra voltar no `data/arquivos.tsv`
e no unpacked. Quem diz o que é cada um é o `pecas.json` da pasta (Body,
FrontLeftFrame..., rodas, volante). Até nov/2026 era tudo solto em assets/
(renegade, sphinx, buggy_NN, fx, sfx, rx01, terrain): `tools/migrar_assets.py`
move pro lugar novo sem gerar nada.

## Índice do archive: caminho -> bloco (data/arquivos.tsv)

O jogo abre tudo pelo caminho e o índice do archive (archive.bin, inteiro na
RAM em 0x89ab50) guarda o CRC32 de cada nome. `re/indice_archive.py`
decodifica o índice de um save state e volta do CRC pro nome testando todas
as strings do exe, da RAM e dos XMLs: `data/arquivos.tsv` tem os 48351
arquivos (caminho, offset, tamanho, comprimido, bloco do unpacked). Pastas
sem nome achado aparecem como `#crc`. Cada pasta é alfabética (BODY,
Brake_*, texturas, Frames_*, shadow_ui, SHOCK_*), então as peças de um carro
vêm DEPOIS da carroceria dele. Antes a gente pegava as de antes, que são do
carro anterior (Renegade com a suspensão do Viper etc.).

## Blocos de cada carro (corrida = Models_4K)

Na corrida o jogo carrega o grupo "High" do component map, LOD 4K (caminhos
achados na RAM dos 2 save states):
`/Vehicles/Buggy/Models_4K/Chassis/<Chassis>/<Model>.pingu` e
`/Vehicles/Buggy/Models_4K/Wheel/<Wheel>/FrontWheel|RearWheel.pingu`.
Chassis e Wheel vêm do DefaultConfig (data/vehicles.xml); os Model, do grupo
High do ComponentMap do carro (unpacked/xml/14881). O Models_5K é o da
garagem. `tools/gerar_buggies.py` monta tudo pelo índice e grava um
`pecas.json` em cada pasta (Position do component map -> .obj).

| # | carro | id | física | chassis | mapa | corpo 4K | pontos | roda (4K) | câmera |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Mosquito | BUGGY_01 | 15145 | CHASSIS_Buggy_01 | C1 | 20540 | 20541 | MEDIUM | BuggyCamSet_01 |
| 2 | Inferno | BUGGY_02 | 15146 | CHASSIS_Buggy_02 | B | 20565 | 20566 | SANDCAR | BuggyCamSet_02 |
| 3 | Trident | BUGGY_03 | 15147 | CHASSIS_Buggy_03 | A | 20589 | 20590 | SANDCAR | BuggyCamSet_03 |
| 4 | Sphinx | BUGGY_04 | 15148 | CHASSIS_Buggy_04 | B | 20618 | 20619 | MEDIUM | BuggyCamSet_04 |
| 5 | Bulldog | BUGGY_05 | 15149 | CHASSIS_Buggy_05 | A1 | 20648 | 20649 | SMALL | BuggyCamSet_05 |
| 6 | Phantom | BUGGY_06 | 15150 | CHASSIS_Buggy_06 | B1 | 20686 | 20687 | MEDIUM | BuggyCamSet_06 |
| 7 | Kraken V8 | BUGGY_07 | 15151 | CHASSIS_Buggy_07 | A1 | 20714 | 20715 | LARGE | BuggyCamSet_07 |
| 8 | McKenzies | BUGGY_08 | 15152 | CHASSIS_Buggy_08 | A1 | 20742 | 20743 | LARGE | BuggyCamSet_08 |
| 9 | Viper | BUGGY_09 | 15153 | CHASSIS_Buggy_09 | B1 | 20772 | 20773 | MEDIUM | BuggyCamSet_09 |
| 10 | Renegade | BUGGY_10 | 15154 | CHASSIS_Buggy_10 | B | 20800 | 20801 | MEDIUM | BuggyCamSet_10 |
| 11 | Hurricane | BUGGY_11 | 15155 | CHASSIS_Buggy_11 | B1 | 20825 | 20826 | MEDIUM | BuggyCamSet_11 |
| 12 | Storm | BUGGY_12 | 15156 | Lancia | Rally | 20852 | 20853 | Wheel_Rally | LanciaCam |

- Mapa A (Trident): sem amortecedor dianteiro (comentado no XML). A1/B1/C1:
  estepe (RearWheel no ponto SpareWheel01Centre). Rally (Storm): só corpo,
  4 balanças e rodas em FrontLeftWheel... (sem Frame no nome: a roda não
  segue a balança), sem freio nem amortecedor.
- As hastes 4K do Renegade (SHOCK_PISTON_RL/RR) estão cruas dentro de um raw
  (sem bloco próprio); o gerador usa as do Models_5K (mesma malha).
- Os pontos são iguais em todos os LODs. 21587 = BODY.pts do BUGGY_GHOST;
  21737/21738 = Axle_RL/RR do Hurricane (não estão no mapa, o jogo não
  desenha).

Ordem da lista do jogo (= FEOrder em data/vehicles.xml):
1 Mosquito (01), 2 Inferno, 3 Trident, 4 Sphinx, 5 Bulldog, 6 Phantom,
7 Kraken V8, 8 McKenzies, 9 Viper, 10 Renegade, 11 Hurricane, 12 Storm.
Física: 15144 + N (15145 = base e Mosquito).

## Rodas

DefaultConfig (data/vehicles.xml): Wheel=TYRE_GENERIC_<tamanho> (Storm usa
Wheel_Rally), Tire=DIRT_BUDGET, Alloy=WHEEL_01. Models_4K/Wheel:

| roda | frente | trás | raio | carros |
|---|---|---|---|---|
| TYRE_GENERIC_LARGE | 21044 | 21045 | 0,60 | Kraken, McKenzies |
| TYRE_GENERIC_MEDIUM | 21049 | 21050 | 0,54/0,55 | Mosquito, Sphinx, Phantom, Viper, Renegade, Hurricane |
| TYRE_GENERIC_SANDCAR | 21059 | 21060 | 0,51/0,56 (traseira larga) | Inferno, Trident |
| TYRE_GENERIC_SMALL | 21064 | 21065 | 0,46/0,47 | Bulldog |
| Wheel_Rally | 21267 | 21268 | 0,42 | Storm |

- Sem escala: as matrizes das rodas na RAM têm linhas de norma 1. O tamanho
  é o do modelo. A "roda minúscula" do Inferno/Trident era o bloco
  21973/21974, que é TYRE_GENERIC_RALLY do 5K, não SANDCAR.
- As rodas da esquerda do jogo (x < 0) saem espelhadas (linha 0 negada).
- O modelo já traz o aro: materiais ALLOY e TYRE (iguais às texturas de
  fábrica IG_WHEEL_HEAVYCLASS_01 / IG_TYRE_DIRT_BUDGET).
- Posição: ver docs/engenharia_reversa.md (Peças). Na frente o centro da
  roda gira com a balança em x/z e o y vira WHEEL.y + curso; atrás vale o
  arco inteiro. O pneu afunda 0,2 a 5,8 cm no chão parado (no jogo também).

## Modelos que o jogo não usa (inventário de out/2026)

Varredura do data/arquivos.tsv contra o vehicles.xml (DefaultConfig de cada
veículo) e o catálogo de peças (xml 14882). Nome com # = só o crc32 do nome
está no archive; o nome real saiu por força bruta (o crc() do
re/indice_archive.py contra palavras dos XMLs, textos e exe).
Os `*_GHOST` (BUGGY/TRUCK/ATV/BIKE_GHOST, NotForPlayer e NotForAI) são o
carro fantasma do replay: o jogo usa.

- **Buggies: nada sobrando.** CHASSIS_Buggy_01..11 + Lancia, todos usados.
- **Trucks: CHASSIS_Truck_04** (o "Lazarus"). O TRUCK_04 (Jericho) usa o
  CHASSIS_Truck_11, o TRUCK_11 o 12 e o TRUCK_12 o Dakar, então sobra o 04.
  Completo no 4K: BODY + pontos, Axle, Rear_Arm, Frames_Left/Right,
  Brake_Front_Left/Right, sombra (Shadow_Truck_04) e pintura
  (VehicleComposite). Texturas `preRunnerTruck_*`: é uma pré-runner. Não tem
  arquivo de física extra de truck (os sem nome são TRUCK_AI.xml = comandos
  da IA, TRUCK_ball.xml = física do modo com bola e ~15 com só
  Air_drag_coefficient).
- **ATVs** (cada ATV = chassis + carenagem; os 10 usam só o CHASSIS_ATV_01
  ou 02 e as carenagens FAIRING_ATV_01..10, todas usadas):
  - CHASSIS_ATV_03 a 08: quadro, motor, guidão e suspensão completos (20
    arquivos cada no 4K), sem carenagem. Variações do quadro dos usados.
  - CHASSIS_AI_2STROKE / AI_4STROKE e #9731c529 (crc de "CHASSIS_Mid"): os
    mesmos quadros com nerf bar, para-choque e escape já na malha.
  - Carenagens SandStorm e WolfTrekker: só pintura, sem modelo próprio. O
    COMPOSITOR (xml 15074/15075) cita camadas Base/Primary/Secondary/Detail
    que não existem; o que existe é a textura pronta Generic/SandStorm.bog e
    WolfTrekker.bog (256x256, número 4 e logos já pintados: amarela/preta e
    branca/vermelha/laranja). As 14 caixas do .bed delas batem com as do
    FAIRING_ATV_04 (WolfTrekker até 0.03 da textura): são pinturas da
    carenagem 04.
- **Motos** (as 10 usam CHASSIS_Bike_2Stroke, 4Stroke ou 08 + carenagem):
  #73f00a07 = **CHASSIS_Bike_01** e #eaf95bbd = **CHASSIS_Bike_02**, nomes
  que nenhum arquivo do jogo cita. Completos em todas as resoluções (500 a
  5K). Diferente das usadas: banco, paralamas e plásticos vêm na própria
  malha (não usam carenagem). A pintura (VehicleComposite/Bike/#...) é uma
  textura pronta só, Bike_01_Fairing / Bike_02_Fairing, que não está no
  archive: saem brancas.
  O Matheus não reconhece nenhuma das duas (pinturas cortadas da beta):
  entram no remake como "pinturas resgatadas", marcadas assim no menu.
- **Pistas** (pastas Levels/ x lista de ambientes do jogo, xml 14850, e os
  campeonatos, Track= nos xml 14840..14880):
  - NAT_09: pista inteira (242 modelos, Env e Event como as outras) fora da
    lista. O NAT09 do jogo é a pasta NAT_NEW (eventos NAT09_Bikes e
    NAT09_Trucks): a NAT_09 original foi trocada.
  - NAT_WAHOO: pista inteira (248 modelos) fora da lista. O exe só cita no
    menu de teste (cMainMenuPlaceholderState, com "-- TEST --" e
    "test-one-track"): pista de teste dos devs.
  - NAT_10 (26 modelos: inacabada) e RX_AI (88 modelos; rallycross de IA?).
  - Minigames fora da lista: MIN_02, MIN_Target (nenhum arquivo cita) e
    MIN_RING_OF_FIRE (o jogo usa MIN_ROF_01..03).
  - Ao contrário: SX_02 está na lista (Supercross SX02, LOCKED) mas não tem
    pasta: pista apagada.
  - O relevo de cada pista fica no stream do disco (STREAMT/<tipo>/<pista>.000,
    como o RX01.000), não no archive: sem o stream dessas pistas só dá pra
    ver os objetos.
- Piloto: Characters/Models/Arms_POV (ARMS_POV.srd + Arms_POV.skl + 5
  animações por classe, AtV e Bike) = braços da câmera de guidão. O exe
  carrega ("Rider POV Skeleton/Animation/Instance", HANDLEBAR): é usado, serve
  pra câmera de primeira pessoa do ATV.
- Rodas: 56 pastas sem nome com roda completa (Front/RearWheel, ALLOY, TYRE)
  nos buggies e 45 nos trucks. 56 = 8 pneus x 7 aros do catálogo: devem ser
  as rodas compráveis (pendente "pneu e aro comprados"). Nome não achado.
- Prints: modelos convertidos com o pingu2obj num projeto Godot à parte;
  as peças da suspensão saem fora do lugar porque no jogo quem posiciona
  é o cCompPlace.

## Referência em vídeo

Speedrun do Sphinx (Amateur National Buggy, 26m39s) no repo `atv4-dados`,
pasta `videos/` (720p, 60 fps, 6 partes de ~5 min). A câmera fica atrás do
carro quase o tempo todo; de lado só nas curvas e nos saltos.
- Pintura do speedrun: V grande azul (camada Secondary) e laterais laranja
  (Primary). Teto com listras vermelho/branco/azul: decalque escolhido pelo
  jogador (o Sphinx de fábrica não tem logo), não dá pra saber qual no vídeo.
- De trás: balança cinza até a roda, aro aparecendo por dentro embaixo.

## Comandos

```
python tools\gerar_buggies.py <unpacked> <texturas>            :: os 12 + rodas + física/pontos
python tools\gerar_buggies.py <unpacked> <texturas> --tabela   :: só a tabela de blocos
python re\indice_archive.py <save.p2s> <unpacked> <SCES_546.88>  :: refaz data\arquivos.tsv
python tools\gerar_pintura.py <unpacked> BUGGY_04 assets\carros\buggy_04 --nome pintura_speedrun.png --base 225,225,230 --primary 215,85,20 --secondary 45,35,175
```
O Renegade sai com o volante separado (4K: `--split
volante:43,46,47,144[16-28],145-150`, cubo + aro); os outros ainda não.

## Formato .pingu (resumo)

- Malha em pacotes VIF (tiras de triângulos): UNPACK V4-32 posição (bit
  ADC 0x8000 no 4º campo = não fecha triângulo), V3-8 normal, V4-32/V2-32
  UV, V4-8 cor. Ver cabeçalho do pingu2obj.py.
- Cor do vértice (V4-8): 0x80 = 1.0, até 255 = 2.0, alfa sempre 0x80. O PS2
  multiplica a textura por ela: sombra "assada" (média 0.4 a 0.66 na
  carroceria) e a cor das lanternas (vidro claro da chassis_comp03 x vértice
  167, 24, 24 no Renegade). O .obj sai com sRGB(linear(c/128) / COR_K),
  COR_K = linear(255/128) = 4.909; o car.gd (material_do_jogo) liga
  vertex_color_is_srgb e multiplica o albedo por 255/128 (sRGB), que dá
  exatamente linear(c/128). pecas.json "cor_vertice": 2 marca o .obj novo;
  sem ela o car.gd lê o .obj antigo (cortado em 1.0) sem o fator.
- Lotes de material: registros de 0x50 bytes a partir de 0xD0; total em
  0xAC (0xBC às vezes conta menos); +0x14 slot de textura, +0x28 início,
  +0x48 nº de tiras. Lista de nomes de textura = o .pfn do mesmo nome, que
  fica cru no raw logo antes do modelo.
- Texturas com o mesmo nome em blocos diferentes são idênticas (byte a byte).
