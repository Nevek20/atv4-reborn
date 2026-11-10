"""
rx01_corrida.py
===============
Dados da corrida do RX01 (Rallycross) -> data/rx01_corrida.json.

Fontes (Levels/RX_01/Event/Rallycross, data/arquivos.tsv):
  #b953876a (other/12288) "AIT 1.1 ExportedTrack": o traçado da IA. Cabeçalho
    0x14 = n de links (75); links de 0x70 bytes a partir de 0x3c:
    +0x00 ponto, +0x0c direção, +0x18 normal, +0x24 ?, +0x28 próximo link,
    +0x2c 4 anteriores (o último é o usado), +0x3c 4 seguintes, +0x5c centro,
    +0x68 / +0x6c largura à esquerda (negativa) / direita. Depois, 24 bytes
    por link (todos iguais no RX01: 1, 1.0, -1, -1, -1, 0).
  #7c14cf48 (raw/12289+366) XML dos checkpoints: 1 CP (Type 2) na linha de
    chegada, AILink 50.
  #c0675b52 (raw/12289+1230) XML do circuito: mFirstLink 51,
    mCircuitLength 1810.4, mStartingOffset 1759.7, mFirstLapLength 54.8.
  RALLYCROSS.bin (other/12289): 8 cStartPosition (o grid).
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
    sai = os.path.join(PROJ, "data", "rx01_corrida.json")
    json.dump(out, open(sai, "w"), indent=1)
    print(n, "links,", out["comprimento"], "m ->", sai)


if __name__ == "__main__":
    main()
