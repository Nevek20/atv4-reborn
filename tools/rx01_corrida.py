"""
rx01_corrida.py
===============
Dados da corrida do RX01 (Rallycross) -> data/rx01_corrida.json.

Fontes (Levels/RX_01/Event/Rallycross, data/arquivos.tsv):
  #b953876a (other/12288) "AIT 1.1 ExportedTrack": o traçado da IA. Cabeçalho
    0x14 = n de links (75); links de 0x70 bytes a partir de 0x3c (loader
    0x329f98): +0x00 ponto (a linha da volta gravada, até 12 m fora do
    centro), +0x0c direção, +0x18 normal, +0x24 LARGURA da pista (m, 25..34;
    não é velocidade: 0x32a6c8/0x32a708 = -/+ metade dela), +0x28 4 ligações
    pra um lado e +0x38 4 pro outro (-1 = nenhuma; +0x28 = "prox"), +0x48 tem
    bloco extra (68 de 75), +0x4c bloco (0x32a990): limite de velocidade em
    mph (-1 em todos = nenhum; vale 1..150 mph), +0x5c centro, +0x68 / +0x6c
    largura à esquerda (negativa) / direita. Pra IA (o 0x3525f8 liga
    DAT_0055155c = 1) a pista vai dessas larguras do bloco e o zero
    (0x32a8d0) é o centro +0x5c; sem bloco, -+largura/2 em volta do ponto e
    o zero no meio (o próprio ponto). Depois, 24 bytes por link (todos
    iguais no RX01: 1, 1.0, -1, -1, -1, 0).
  #7c14cf48 (raw/12289+366) XML dos checkpoints: 1 CP (Type 2) na linha de
    chegada, AILink 50.
  #c0675b52 (raw/12289+1230) XML do circuito: mFirstLink 51,
    mCircuitLength 1810.4, mStartingOffset 1759.7, mFirstLapLength 54.8.
  RALLYCROSS.bin (other/12289): 8 cStartPosition (o grid) e 14
    cInstantRespotBox (reposição na hora: em cima das arquibancadas e cabanas).
  TrackSetup/RALLYCROSS.xml (raw/12290): Respotting (mSafePlayerDistance 8,
    mUprightTolerance 0.93, mWaterUprightTolerance 0.99, mWaterDepthTolerance
    0.01), Logic, Boundary, RollingStart.
  IntroCameras.XML (raw/12287) + CameraSpline.XML (xml/12287_Intro1): a
    câmera de introdução (caminho Intro1, 7 nós, alvo Introlookat1, 5 nós,
    as duas a 35 m/s).
  14840 (eventos): Rallycross Amateur buggy/truck Laps="5" NumRankings="8".
Uso:
    python tools/rx01_corrida.py <unpacked>
"""
import json
import os
import re
import struct
import sys

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    u = sys.argv[1]
    d = open(os.path.join(u, "other", "12288_bloco.bin"), "rb").read()
    assert d[:7] == b"AIT 1.1"
    n = struct.unpack_from("<i", d, 0x14)[0]
    links = []
    for k in range(n):
        o = 0x3c + k * 0x70
        links.append({
            "p": [round(x, 3) for x in struct.unpack_from("<3f", d, o)],
            "dir": [round(x, 4) for x in struct.unpack_from("<3f", d, o + 12)],
            "centro": [round(x, 3) for x in struct.unpack_from("<3f", d, o + 0x5c)],
            "largura": [round(x, 2) for x in struct.unpack_from("<2f", d, o + 0x68)],
            "prox": struct.unpack_from("<i", d, o + 0x28)[0],
            "largura_total": round(struct.unpack_from("<f", d, o + 0x24)[0], 2),
            "n": [round(x, 4) for x in struct.unpack_from("<3f", d, o + 0x18)],
            "bloco": struct.unpack_from("<i", d, o + 0x48)[0] != 0,
        })
    b = open(os.path.join(u, "raw", "12289r_bloco.bin"), "rb").read()
    cp = b[366:366 + 555].decode()
    circ = b[1230:1230 + 633].decode()
    pega = lambda s, k: float(re.search(k + r'="([-\d.]+)"', s).group(1))
    out = {
        "fonte": "Levels/RX_01/Event/Rallycross (tools/rx01_corrida.py)",
        "voltas": 5, "corredores": 8,
        "links": links,
        "checkpoint": {
            "pos": [pega(cp, "X"), pega(cp, "Y"), pega(cp, "Z")],
            "row0": [float(x) for x in re.search(r'<Row0 X="([-\d.]+)" Y="([-\d.]+)" Z="([-\d.]+)"', cp).groups()],
            "tamanho": [float(x) for x in re.search(r'<Size X="([-\d.]+)" Y="([-\d.]+)" Z="([-\d.]+)"', cp).groups()],
            "link": int(pega(cp, "mLinkIndex")), "fracao": pega(cp, "mHitFraction"),
        },
        "primeiro_link": int(pega(circ, "mFirstLink")),
        "comprimento": pega(circ, "mCircuitLength"),
        "largada_offset": pega(circ, "mStartingOffset"),
        "primeira_volta": pega(circ, "mFirstLapLength"),
    }
    # grid: os 8 cStartPosition do RALLYCROSS.bin, pela posição (campo 43b8a9bf)
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import rx01_objetos
    ents = rx01_objetos.entidades(open(os.path.join(u, "other", "12289_bloco.bin"), "rb").read())
    grid = [e for e in ents if e["classe"] == "cStartPosition"]
    grid.sort(key=lambda e: e["campos"]["43b8a9bf"])
    out["grid"] = [{"pos": [round(x, 3) for x in e["pos"]], "dir": [round(x, 4) for x in e["dir"]]} for e in grid]
    # reposição: as 14 cInstantRespotBox do RALLYCROSS.bin (caixa centrada em
    # pos, Z = dir na horizontal, tamanho inteiro: em cima das arquibancadas e
    # das cabanas) e as seções Respotting/Logic do TrackSetup/RALLYCROSS.xml
    out["reposicao"] = {
        "caixas": [{"pos": [round(x, 3) for x in e["pos"]], "dir": [round(x, 4) for x in e["dir"]],
                    "tamanho": [round(x, 3) for x in e["tamanho"]]}
                   for e in ents if e["classe"] == "cInstantRespotBox"],
    }
    ts = open(os.path.join(u, "raw", "12290r_root.xml"), "rb").read()
    ts = ts[:ts.find(b"</Root>")].decode("latin1")
    for sec in ("Respotting", "Logic", "Boundary", "RollingStart"):
        m = re.search(r"<%s ([^/>]*)/>" % sec, ts)
        if m:
            out["reposicao" if sec == "Respotting" else sec.lower()] = dict(
                out.get("reposicao", {}) if sec == "Respotting" else {},
                **{k: float(v) for k, v in re.findall(r'(\w+)="([-\d.]+)"', m.group(1))})
    # câmera de introdução: IntroCameras.XML (raw/12287) diz os 2 caminhos e as
    # velocidades; CameraSpline.XML (xml/12287_Intro1.xml) tem os nós
    ic = open(os.path.join(u, "raw", "12287r_root.xml"), encoding="utf-8", errors="replace").read()
    sp = open(os.path.join(u, "xml", "12287_Intro1.xml"), encoding="utf-8").read()
    grupos = {}
    for nome, corpo in re.findall(r'<cGroupEntity Name="(\w+)">(.*?)</cGroupEntity>', sp, re.S):
        grupos[nome] = [[float(x) for x in m] for m in re.findall(r'X="([-\d.]+)" Y="([-\d.]+)" Z="([-\d.]+)"', corpo)]
    out["intro"] = {
        "caminho": grupos[re.search(r' SplineName="(\w+)"', ic).group(1)],
        "alvo": grupos[re.search(r'LookAtSplineName="(\w+)"', ic).group(1)],
        "vel": pega(ic, "SpeedOnSpline"), "vel_alvo": pega(ic, "SpeedOnLookAtSpline"),
    }
    sai = os.path.join(PROJ, "data", "rx01_corrida.json")
    json.dump(out, open(sai, "w"), indent=1)
    print(n, "links,", out["comprimento"], "m ->", sai)


if __name__ == "__main__":
    main()
