# ATV4 Reborn

**Remake em Godot 4 do *ATV Offroad Fury 4* (PS2, 2006), feito com os dados e o código do próprio jogo.**

🇺🇸 [Read in English](README.md)

O objetivo é ficar **100% fiel ao jogo de PS2**. Física, câmeras, peças e
pinturas vêm dos XMLs do jogo, e o comportamento é portado do executável
desmontado no Ghidra (PAL, `SCES_546.88`). Cada número tem fonte: XML, função
do exe, save state do PCSX2 ou quadro de vídeo.

> **Situação:** protótipo jogável. Uma pista (RX01), 12 buggies, 12 trucks,
> um truck que o jogo não usa (resgatado dos arquivos) e um carro extra nosso.

## Destaques

**Portado do jogo**

- Física: pneus e derrapagem, motor, embreagem, câmbio, roda patinando,
  suspensão, anti-pitch, controle no ar, arrasto, atrito e arrasto por tipo
  de chão. Roda a 50 Hz como o PAL (60 Hz pra comparar com vídeo NTSC)
- Câmera de corrida: órbita, distância e zoom pela velocidade, amortecimento
  de altura, folga do chão, solta/prende e tremida
- Peças de fábrica e upgrades por carro (`vehicles.xml` + `upgrades.xml`)
- Suspensão visual (balanças, amortecedores, eixo rígido), casco de colisão,
  piloto com a animação da direção, som de pneu, suspensão e pouso (989snd),
  poeira e sujeira
- Pinturas montadas pelas camadas do jogo (cores, logos, número)

**Melhorias nossas** (marcadas no código e nos docs)

- Câmera do piloto com força G na cabeça, FOV e borrão pela velocidade, olhar livre
- Órbita da câmera no analógico direito, estilo Forza
- Som do motor gravado por carro no Engine Simulator
- Painel funcional, volante girando com as mãos do piloto, lanterna de freio,
  ré e farol, fumaça do escape, motor tremendo e ventoinhas girando

**Conferido com o jogo de verdade**

Save states do PCSX2 (massa, centro de massa, marchas, rpm, curso da
suspensão, força por roda, câmera) e HUD lido quadro a quadro em vídeos.
Os testes em `tests/` rodam sem tela e comparam o remake com essas referências.

## Requisitos

- **A sua cópia do ATV Offroad Fury 4 (PS2).** As ferramentas em `tools/`
  extraem modelos, texturas e sons da sua imagem do disco.
- [Godot 4.7](https://godotengine.org/) (Forward+)
- Python 3 com Pillow e zstandard (`pip install pillow zstandard`)

## Como rodar

```
:: 1. texturas do archive do jogo (uns 6 min)
python tools\gob_tex2png.py <jogo>\unpacked\gob --out <jogo>\texturas

:: 2. buggies e trucks (carroceria, peças, freios, rodas, pintura)
python tools\gerar_buggies.py <jogo>\unpacked <jogo>\texturas
python tools\gerar_buggies.py <jogo>\unpacked <jogo>\texturas --classe truck

:: 3. piloto, sons e efeitos
python tools\piloto.py <jogo>\unpacked
python tools\sfx_jogo.py <jogo>\unpacked
python tools\fx_jogo.py <jogo>\unpacked
```

Depois abra o `project.godot` no Godot, espere importar e aperte **F5**. Sem
os assets o carro aparece como caixa. Rode o `gerar_buggies` de novo sempre
que o `pingu2obj.py` mudar.

## Controles

| tecla | ação |
|---|---|
| W / S ou setas | acelerar / frear (parado, segure S pra engatar a ré) |
| A / D | virar |
| Espaço | embreagem: segurando abre; um toque virando e acelerando faz a "Clutch Turn". O jogo não tem freio de mão |
| E / Q | sobe / desce marcha (manual; abaixo da 1ª vem a ré) |
| M | câmbio automático / manual |
| C | câmera: perto, longe, capô, para-choque, piloto |
| Tab / V | menu de carros / próximo carro |
| H | farol |
| B | troca o estilo do volante |
| G | liga e desliga os efeitos da câmera do piloto |
| N | som mudo |
| R / T | desvirar o carro / voltar pra largada |
| F | girar o modelo 180° (se parecer andar de ré) |
| P / L | comparar pneus e força lateral do jogo x modelo antigo |
| 1 a 8 | câmera do piloto: altura, distância, inclinação e campo de visão |
| 9 0 - = | câmera do piloto: posição do painel |
| Esc | sair |

Controle de videogame: gatilhos, analógico esquerdo, A = embreagem,
analógico direito = órbita da câmera, Select = câmera.

## Estrutura

```
car.gd, game_camera.gd ...  scripts do jogo (física e câmera portadas do exe)
data/                       XMLs do jogo usados em tempo de execução
tools/                      extratores em Python (modelos, texturas, pintura, sons, save states)
tests/                      testes de física sem tela + rodar_testes.py
re/                         engenharia reversa (scripts do Ghidra, exe_util)
docs/                       mapa do exe, derrapagem, formatos dos assets, som do motor
som/                        motores do Engine Simulator e loops gravados
```

O `CLAUDE.md` e o `docs/engenharia_reversa.md` têm as notas técnicas
completas: offsets, endereços de função e o porquê de cada decisão. Com o
Claude Code, `/teste` roda os testes e `/entrega` fecha uma entrega.

## Aviso legal

Projeto de fã, sem fins comerciais, feito pra estudo e preservação. Não tem
ligação com a Sony Interactive Entertainment nem com a Climax Racing, nem
apoio delas. *ATV Offroad Fury* e todos os nomes, modelos, texturas, sons e
dados relacionados pertencem aos seus donos. Este repositório não distribui o
executável, a imagem do disco nem código decompilado do jogo: é preciso ter a
sua própria cópia, obtida de forma legal.

## Licença

O código original deste repositório (GDScript, Python, Java e scripts shell)
está sob a [licença MIT](LICENSE). Dados e assets derivados do *ATV Offroad
Fury 4* **não** entram nessa licença e continuam sendo dos seus donos.
