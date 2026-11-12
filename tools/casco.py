"""
casco.py
========
Casco de colisão dos carros contra o mundo: Vehicles/<Classe>/Collision/
<Nome>/VehicleWorld.hsc (o jogo também tem o VehicleVehicle.hsc, carro contra
carro). Formato "CSH\\0": versão (1, 1), n planos, n x (normal, d) com o lado
de dentro em n·p + d <= 0, n esferas (contador em 16 bytes), n x (centro,
raio). Frame do modelo do jogo. Na RAM (Fireball.p2s, out/2026) os 13 planos e
as 11 esferas do Truck_10 aparecem no frame do CoM (o loader 0x13e318 tira o
CoM: d -= n·CoM, centro -= CoM).

Pasta = id do veículo (0x1fed48: "/Vehicles/%s/Collision/%s/VehicleWorld.hsc"
com a classe (descritor veículo+0xa6c, +0x1c) e o Name do vehicles.xml (+4);
sem o arquivo usa "Generic"). Conferido na RAM: Fireball = TRUCK_10, Storm =
BUGGY_12 (chassi Lancia). Então o Jericho (TRUCK_04, chassi Truck_11) usa o
casco do Truck_04, feito pra Silverado (a carroceria original dele, o nosso
Lazarus), e o Chimera o do Truck_12; as pastas Dakar sobram.

Forma: o corpo bate no mundo pelas ESFERAS (sem recorte dos planos): nos save
states do Fireball de lado e capotado (out/2026) o contato do corpo cai
exatamente na superfície de uma esfera, num caso 3.4 cm fora dos planos. Os
planos ficam no .json só de referência.

Saída: data/vehicles/<id>_casco.json com planos, esferas e vértices do
poliedro dos planos (frame do modelo do jogo) e esferas_carro (as esferas do
VehicleVehicle.hsc da mesma pasta: carro contra carro, pista/batida_carros.gd).

Uso: python tools/casco.py <unpacked> [--tabela]
"""

import argparse
import itertools
import json
import os
import struct

import numpy as np

AQUI = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(AQUI)

# id do veículo -> pasta de colisão (o Lazarus tem o id do Jericho)
CARROS = {"buggy_%02d" % n: "Buggy/Buggy_%02d" % n for n in range(1, 13)}
CARROS.update({"truck_%02d" % n: "Truck/Truck_%02d" % n for n in range(1, 13)})


def ler_indice():
    out = {}
    for linha in open(os.path.join(PROJ, "data", "arquivos.tsv"), encoding="utf-8"):
        if linha.startswith("#"):
            continue
        p = linha.rstrip("\n").split("\t")
        if len(p) >= 5:
            out[p[0].lower()] = (int(p[2]), p[4])
    return out


def bytes_do_arquivo(unpacked, indice, caminho):
    tam, fonte = indice[caminho.lower()]
    arq, _, off = fonte.partition("+")
    b = open(os.path.join(unpacked, arq), "rb").read()
    o = int(off or 0)
    return b[o:o + tam]


def hsc(d):
    if d[:4] != b"CSH\0":
        raise ValueError("não é CSH: %r" % d[:4])
    _, _, n_p = struct.unpack_from("<3I", d, 4)
    o = 16
    planos = [list(struct.unpack_from("<4f", d, o + 16 * i)) for i in range(n_p)]
    o += 16 * n_p
    n_e = struct.unpack_from("<I", d, o)[0]
    o += 16
    esferas = [list(struct.unpack_from("<4f", d, o + 16 * i)) for i in range(n_e)]
    return planos, esferas


def vertices(planos, tol=1e-4):
    P = np.array(planos, dtype=float)
    out = []
    for i, j, k in itertools.combinations(range(len(P)), 3):
        A = P[[i, j, k], :3]
        if abs(np.linalg.det(A)) < 1e-6:
            continue
        x = np.linalg.solve(A, -P[[i, j, k], 3])
        if np.all(P[:, :3] @ x + P[:, 3] <= tol):
            if not any(np.linalg.norm(x - y) < 1e-4 for y in out):
                out.append(x)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("unpacked")
    ap.add_argument("--tabela", action="store_true", help="só mostra a caixa de cada casco")
    a = ap.parse_args()
    indice = ler_indice()
    pastas = sorted({k.split("/collision/")[1].split("/")[0] + "|" + k.split("/")[1]
                     for k in indice if "/collision/" in k and k.endswith("vehicleworld.hsc")})
    if a.tabela:
        for p in pastas:
            nome, classe = p.split("|")
            d = bytes_do_arquivo(a.unpacked, indice, "Vehicles/%s/Collision/%s/VehicleWorld.hsc" % (classe, nome))
            pl, es = hsc(d)
            v = np.array(vertices(pl))
            print("%-8s %-12s %2d planos %2d esferas  x %6.3f..%6.3f  y %6.3f..%6.3f  z %6.3f..%6.3f" % (
                classe, nome, len(pl), len(es), *[f for ax in range(3) for f in (v[:, ax].min(), v[:, ax].max())]))
        return
    for carro, pasta in sorted(CARROS.items()):
        classe, nome = pasta.split("/")
        d = bytes_do_arquivo(a.unpacked, indice, "Vehicles/%s/Collision/%s/VehicleWorld.hsc" % (classe, nome))
        pl, es = hsc(d)
        v = vertices(pl)
        info = {"fonte": "Vehicles/%s/Collision/%s/VehicleWorld.hsc" % (classe, nome),
                "planos": [[round(x, 5) for x in p] for p in pl],
                "esferas": [[round(x, 5) for x in e] for e in es],
                "vertices": [[round(float(x), 5) for x in p] for p in v]}
        # carro contra carro: o VehicleVehicle.hsc da mesma pasta (o par 2 x 2
        # do exe, 0x1529d0, cria um contato por ponto como o do mundo)
        vv = "Vehicles/%s/Collision/%s/VehicleVehicle.hsc" % (classe, nome)
        if vv.lower() in indice:
            pv, ev = hsc(bytes_do_arquivo(a.unpacked, indice, vv))
            info["fonte_carro"] = vv
            info["esferas_carro"] = [[round(x, 5) for x in e] for e in ev]
        saida = os.path.join(PROJ, "data", "vehicles", carro + "_casco.json")
        json.dump(info, open(saida, "w", newline="\n"), separators=(",", ":"))
        E = np.array(es)
        print("%-10s %-16s %2d planos %2d esferas  esferas x %5.2f..%4.2f y %4.2f..%4.2f z %5.2f..%4.2f" % (
            carro, pasta, len(pl), len(es), *[f for ax in range(3) for f in ((E[:, ax] - E[:, 3]).min(), (E[:, ax] + E[:, 3]).max())]))


if __name__ == "__main__":
    main()
