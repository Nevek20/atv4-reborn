# ATV4 Reborn

**Remake em Godot 4 do *ATV Offroad Fury 4* (PS2, 2006), feito com os dados e o código do próprio jogo.**

🇺🇸 [Read in English](README.md)

O objetivo é ficar **100% fiel ao jogo de PS2**. Física, câmeras, peças e
pinturas vêm dos XMLs do jogo, e o comportamento é portado do executável
desmontado no Ghidra (PAL, `SCES_546.88`). Cada número tem fonte: XML, função
do exe, save state do PCSX2 ou quadro de vídeo. O que é invenção nossa está
marcado no código e nos docs.

> **Situação:** jogável. Uma pista (RX01, Rallycross) com corrida completa:
> introdução, contagem, 7 rivais da IA, voltas, o HUD do jogo, Score, tela
> de resultados e menu de pausa. 12 buggies, 12 trucks, um truck que o jogo
> não usa (resgatado dos arquivos) e um carro extra nosso. O primeiro ATV
> (Samurai 650) já anda com a física do buggy; o piloto dele, a física só
> de ATV e as motos são os próximos.

## Destaques

**Portado do jogo**

- Física: pneus e derrapagem, motor, embreagem, câmbio, roda patinando,
  suspensão, anti-pitch, controle no ar, arrasto, atrito por tipo de chão.
  Roda a 50 Hz como a versão PAL (60 Hz pra comparar com o NTSC)
- Câmera de corrida: órbita, distância e zoom pela velocidade, altura
  amortecida, folga do chão, solta/volta e tremida
- Corrida no RX01: câmera de introdução, contagem, rivais da IA (linha,
  ultrapassagem, catch-up), volta pelo checkpoint, reposição automática
  (fora da pista, contramão, checkpoint perdido) e caixas de reposição
- HUD do jogo, Score (Slide e AirTime), tela de resultados, menu de pausa e
  Race Again, montados pelos arquivos do jogo e conferidos com a RAM
- Objetos da pista que quebram (cercas, fardos), torcida, céu e névoa
- Peças de fábrica e compradas, pneus, aros, para-choques e Tune & Setup por
  veículo (`vehicles.xml` + `upgrades.xml`)
- Suspensão visual, cascos de colisão, piloto com a animação da direção,
  sons de pneu, suspensão, pouso e batida (989snd), poeira, pedrinhas,
  lasquinhas e sujeira
- Pinturas e roupa do piloto pelo sistema de camadas do jogo (cores, logos,
  número)

**Melhorias nossas** (marcadas no código e nos docs)

- Câmera do piloto com cabeça pela força G, FOV e borrão pela velocidade,
  olhar livre
- Órbita da câmera no analógico direito
- Som de motor gravado por carro no Engine Simulator
- Painel funcionando, volante girando com as mãos do piloto, lanterna, ré e
  farol, fumaça do escape, motor tremendo, ventoinhas girando e borrão nas
  rodas
- Oficina (pintura, logos, piloto, peças, ajuste) até o menu da garagem do
  jogo ser portado

**Conferido com o jogo de verdade**

Save states do PCSX2 (massa, centro de massa, marchas, rpm, curso da
suspensão, forças por roda, câmera, HUD, IA, menus) e leitura quadro a quadro
de vídeos. A pasta `tests/` tem uns 50 testes sem tela que comparam o remake
com essas referências.

## Requisitos

- **Sua cópia do ATV Offroad Fury 4 (PS2).** Os scripts em `tools/` extraem
  modelos, texturas e sons da sua cópia do jogo.
- [Godot 4.7](https://godotengine.org/) (Forward+)
- Python 3 com Pillow e zstandard (`pip install pillow zstandard`)
- A física em C++ já vem compilada em `bin/` (Windows e Linux). Sem ela o
  jogo usa o GDScript. Como compilar está no `docs/comandos.md`.

## Como rodar

`<unpacked>` é o arquivo do jogo descompactado e `<texturas>` a pasta criada
no passo 1.

```
:: 1. texturas do arquivo do jogo (~6 min)
python tools\gob_tex2png.py <unpacked>\gob --out <texturas>

:: 2. buggies, trucks e o ATV (carroceria, peças, freios, rodas, pneus, pintura)
python tools\gerar_buggies.py <unpacked> <texturas>
python tools\gerar_buggies.py <unpacked> <texturas> --classe truck
python tools\gerar_buggies.py <unpacked> <texturas> --classe atv --so 10

:: 3. piloto, sons e efeitos
python tools\piloto.py <unpacked>
python tools\sfx_jogo.py <unpacked>
python tools\fx_jogo.py <unpacked>

:: 4. objetos e céu do RX01, HUD e telas do menu
python tools\rx01_objetos.py <unpacked>
python tools\hud_jogo.py <unpacked>
python tools\fex_jogo.py <unpacked>
```

Depois abra o `project.godot` no Godot, espere a importação e aperte **F5**.
**Enter** começa uma corrida. Sem os assets extraídos o carro aparece como
uma caixa e entra um HUD simples.

## Controles

| Tecla | Ação |
|---|---|
| W / S ou setas | acelerar / frear (segure S parado pra dar ré) |
| A / D | direção |
| Espaço | embreagem (toque virando e acelerando pra um Clutch Turn) |
| E / Q | sobe / desce marcha (manual) · M troca auto/manual |
| C | câmera: perto, longe, capô, para-choque, piloto |
| Enter | começa uma corrida (pula a introdução) · Continue nos resultados |
| Esc | pausa na corrida · sai do jogo fora da corrida |
| R | reposiciona (na corrida só abaixo de 40 mph, como no jogo) |
| T / Backspace | volta pro início / sai da corrida |
| Tab / V | menu de veículos / próximo veículo |
| O | oficina (pintura, logos, piloto, peças, ajuste) |
| H | farol · B estilo do volante · G efeitos da cabine · N mudo |
| F1 / F2 / F3 | modos do HUD / FPS e tempos / física em C++ liga e desliga |

Controle também funciona: gatilhos, analógico esquerdo, A = embreagem (e
pula a introdução), Start = pausa, analógico direito = órbita da câmera,
Select = câmera.

## Estrutura

```
main.gd / main.tscn   a cena: terreno, carro, câmera, HUD, menus
carro/                o veículo: física portada do exe, modelo, piloto, peças, pintura
camera/               câmera de corrida (do exe) e as nossas (piloto, órbita)
pista/                terreno e objetos do RX01, corrida, rivais da IA, reposição, Score
menu/                 HUD do jogo, telas de resultados e pausa, oficina
efeitos/, som/        poeira, pedrinhas, lasquinhas, fumaça; sons do jogo e dos motores
fisica_cpp/, bin/     a física em C++ (GDExtension) e as bibliotecas compiladas
data/                 XMLs e JSONs do jogo lidos pelo remake (física, câmeras, peças, pista, HUD)
tools/                extratores em Python (modelos, texturas, pinturas, sons, pista, HUD, save states)
tests/                testes sem tela (python tests/rodar_tudo.py roda todos)
re/                   engenharia reversa (scripts do Ghidra, exe_util, leitores de RAM)
docs/                 histórico de cada decisão, mapa do exe, comandos, formatos dos assets
```

O `docs/historico.md`, o `docs/engenharia_reversa.md` e o `CLAUDE.md` são as
notas técnicas completas: endereços de memória e de funções e o porquê de
cada decisão.

## Próximos passos

1. ATVs e motos, até fechar todos os veículos
2. Os menus do jogo, com opções de vídeo, áudio e controle, perfil e save
3. Todas as pistas
4. Todos os modos de jogo, depois a carreira
5. Opções gráficas (modo "fiel" e modo "melhorado"), depois polimento
6. Um launcher: escolhe a ISO uma vez, ele extrai tudo pra pasta do jogo
   e depois o atalho abre o jogo direto
7. Multiplayer local (tela dividida) pensado desde já; online no fim

## Aviso legal

Projeto de fã, sem fins comerciais, feito para estudo e preservação. Não tem
ligação, apoio ou patrocínio da Sony Interactive Entertainment nem da Climax
Racing. *ATV Offroad Fury* e todos os nomes, modelos, texturas, sons e dados
relacionados pertencem aos seus donos.

Nenhum executável do jogo, imagem de disco ou código descompilado é
distribuído aqui, e modelos, texturas e sons são extraídos da sua cópia
pelos scripts. O repositório traz alguns arquivos de dados tirados do jogo
que o remake lê ao rodar (XML/JSON em `data/`) e o terreno do RX01
(`assets/pista/terreno`). Você precisa de uma cópia do jogo obtida
legalmente.

## Licença

O código original deste repositório (GDScript, C++, Python, Java e shell
script) está sob a [Licença MIT](LICENSE). Dados e assets derivados do
*ATV Offroad Fury 4* **não** são cobertos por essa licença e continuam
sendo dos seus donos.
