"""
ia_alvo_ram.py
==============
Confere a IA do jogo com um save state de corrida com rivais (RX01): refaz a
velocidade-alvo (0x359eb8 -> 0x35a040 / 0x35a150 -> 0x214328) e a lei do
acelerador/freio (0x34ed10) a partir do estado da RAM e compara com o que o
piloto de cada rival guardou (piloto+0x40 alvo, +0xa0 freio, +0xa4
acelerador, +0x30 ponto-alvo da direção). Mesmas contas do pista/ia.gd.

Uso:
    python re/ia_alvo_ram.py arquivo.p2s

Endereços (RX01, buggy Normal; iguais em corrida_no_normal.p2s e
freiando.p2s): corredor k (1..7) em 0x14eee80 + (k - 1) x 0x200 (+0xc
veículo, +0x14 piloto vtable 0x5ae0d0); piloto+0x18 -> objeto com +0x30
posição (y = 0), +0xa0 |v|; veículo+0x9d4 = corpo; corpo+0x364 = P.

A rota: zero da IA = centro +0x5c do link. Durante o update dos pilotos
(0x3525f8) DAT_0055155c = 1 (no save state aparece 0): a borda esquerda é o
ponto +0x00 + eixo (normal x direção) x largura esquerda do bloco (+0x68) e
o zero fica em |centro - borda| / largura (0x32a8d0). Sem bloco extra (+0x48
= 0), o próprio ponto.
"""

import json
import math
import os
import struct
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(AQUI, "..", "tools"))
from ler_savestate import ler_ram  # noqa: E402

V_SEM = 446.4975


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return
    m = ler_ram(sys.argv[1])
    f = lambda a: struct.unpack_from("<f", m, a & 0x1FFFFFF)[0]
    u = lambda a: struct.unpack_from("<I", m, a & 0x1FFFFFF)[0]
    V = lambda a: [f(a + 4 * j) for j in range(3)]
    sub = lambda a, b: [a[j] - b[j] for j in range(3)]
    add = lambda a, b: [a[j] + b[j] for j in range(3)]
    mul = lambda a, s: [x * s for x in a]
    dot = lambda a, b: sum(a[j] * b[j] for j in range(3))
    cross = lambda a, b: [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
    norm = lambda a: math.sqrt(dot(a, a))
    xz = lambda a: [a[0], 0.0, a[2]]

    d = json.load(open(os.path.join(AQUI, "..", "data", "rx01_corrida.json")))
    links = d["links"]
    ordem = [d["primeiro_link"]]
    while links[ordem[-1]]["prox"] not in (ordem[0], -1) and len(ordem) <= len(links):
        ordem.append(links[ordem[-1]]["prox"])
    ordem.reverse()                      # sentido da corrida

    def zero(l):
        if not l.get("bloco"):
            return l["p"]
        x = cross(l["n"], l["dir"])
        x = mul(x, 1.0 / norm(x))
        borda = add(l["p"], mul(x, l["largura"][0]))
        return add(borda, mul(x, norm(sub(l["centro"], borda))))

    pts = [zero(links[k]) for k in ordem]
    n = len(pts)
    acc = [0.0]
    for a in range(n):
        acc.append(acc[-1] + math.dist(pts[a], pts[(a + 1) % n]))
    comp = acc[-1]

    def projetar(p):
        melhor = None
        for a in range(n):
            pa, pb = xz(pts[a]), xz(pts[(a + 1) % n])
            ab = sub(pb, pa)
            t = max(0.0, min(1.0, dot(sub(xz(p), pa), ab) / dot(ab, ab)))
            e = norm(sub(xz(p), add(pa, mul(ab, t))))
            if melhor is None or e < melhor[0]:
                melhor = (e, acc[a] + t * (acc[a + 1] - acc[a]))
        return melhor[1]

    def ponto(s):
        s %= comp
        for a in range(n):
            if acc[a + 1] >= s:
                return add(pts[a], mul(sub(pts[(a + 1) % n], pts[a]), (s - acc[a]) / (acc[a + 1] - acc[a])))
        return pts[0]

    def arco(c, alvo, p0, rumo):
        if u(c + 0x8A8) == 0 or f(c + 0x418) < 0.0:
            return V_SEM
        dd = sub(alvo, p0)
        lado = cross(V(c + 0x3F0), rumo)
        lado = mul(lado, 1.0 / max(norm(lado), 1e-9))
        lat = dot(dd, lado)
        if abs(lat) < 4.0:
            return V_SEM
        r = dot(dd, dd) / (lat + lat)
        k = f(u(c + 0x364) + 0x53C) * f(c + 0x724) * 0.001
        num = abs(r) * f(c + 0x3B4) - (f(c + 0x3AC) - f(c + 0x3B0))
        if k <= 1e-6 or num < 0.0:
            return 0.0
        return math.sqrt(num / k)

    print("rival  alvo jogo / nosso   (erro)  |  acel jogo / lei   freio jogo / lei  |  ponto da direção x zero")
    for k in range(1, 8):
        w = 0x14EEE80 + (k - 1) * 0x200
        pil = u(w + 0x14)
        c = u(u(w + 0xC) + 0x9D4)
        ob = u(pil + 0x18)
        v = f(ob + 0xA0)
        s_car = projetar(V(ob + 0x30))
        p0 = V(c + 0x70)
        fwd, nn = V(c + 0xD0), V(c + 0x3F0)
        rumo = sub(fwd, mul(nn, dot(fwd, nn)))
        rumo = mul(rumo, 1.0 / norm(rumo))
        olha = min(max(v, 15.0), 100.0)
        v1 = arco(c, ponto(s_car + olha), p0, rumo) or 4.916389
        v2 = V_SEM
        d_dir = min(max(0.5 * v, 15.0), 50.0)
        if d_dir > 15.0:
            p1, p2 = ponto(s_car), ponto(s_car + d_dir)
            p1[1] = p2[1] = 0.0
            r2 = sub(p1, p2)
            v2 = arco(c, ponto(s_car + d_dir + olha), p2, mul(r2, 1.0 / norm(r2))) or 8.938889
        nosso = min(v1, v2)
        jogo = f(pil + 0x40)
        vs = f(c + 0x440) if f(c + 0x418) > 0.0 else -f(c + 0x440)
        kk = max(-1.0, min(1.0, (jogo - vs) * 0.2))
        alvo = V(pil + 0x30)
        fora = norm(sub(xz(alvo), xz(ponto(projetar(alvo)))))
        print("%d   %8.2f / %8.2f  (%+5.1f%%)  |  %.3f / %.3f    %.3f / %.3f     |  %.1f m" % (
            k, jogo, nosso, 100.0 * (nosso - jogo) / jogo, f(pil + 0xA4), max(kk, 0.0),
            f(pil + 0xA0), max(-kk, 0.0), fora))


if __name__ == "__main__":
    main()
