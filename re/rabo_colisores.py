"""Pontos do rabo de cavalo no corpo do piloto (pino e colisores), rodando o
0x1a9db0 do exe no re/emu_ee.py com ossos inventados e resolvendo os
coeficientes no frame de cada osso (carro/rabo.gd usa estes números).

    analyzeHeadless ~/ghidra_proj atv4 -process -noanalysis -readOnly \\
      -scriptPath re/ghidra_scripts -postScript DumpAsm.java rabo.asm 0x1a9db0 0x1ab488
    python re/rabo_colisores.py rabo.asm <dados>/exe/SCES_546.88
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_ee import Emu  # noqa: E402

PT, R, X, Y, MATS, MODEL = 0x1000000, 0x1100000, 0x1110000, 0x1120000, 0x1200000, 0x1300000
C = [0x1400000 + k * 0x100 for k in range(4)]
OSSOS = {3: "upper_back", 4: "neck", 5: "head", 6: "right_shoulder", 18: "left_shoulder"}


def rodar(asm, exe, mats):
    e = Emu(asm, exe)
    e.gravar32(PT, R)
    e.gravar32(PT + 0xc, MODEL)
    for k, off in enumerate((0x1c, 0x20, 0x24, 0x28)):
        e.gravar32(PT + off, C[k])
    e.gravar32(R + 0x2cc, X)
    e.gravar32(X + 8, Y)
    e.gravar32(Y + 8, MATS)
    for b, (rot, pos) in enumerate(mats):         # matriz do jogo: linhas = eixos, posição na 4ª
        for i in range(3):
            e.escrever_f(MATS + b * 0x40 + 0x10 * i, list(rot[i]) + [0.0])
        e.escrever_f(MATS + b * 0x40 + 0x30, list(pos) + [1.0])
    e.escrever_f(0x1500000, [0, 0, 0, 1])
    e.escrever_f(0x1500100, [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0])
    e.setr("a0", PT)
    e.setr("a1", 0x1500000)
    e.setr("a2", 0x1500100)
    e.fpr[12] = 0.02
    e.rodar(0x1a9db0, parar_em={0x1ab394})       # antes de animar o rabo
    return {k: e.ler_f(C[k], 8) for k in range(4)}


def main():
    asm = open(sys.argv[1]).read()
    exe = open(sys.argv[2], "rb").read()
    rng = np.random.default_rng(1)

    def rot():
        q = rng.normal(size=4)
        q /= np.linalg.norm(q)
        x, y, z, w = q
        return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                         [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                         [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    mats = [(rot(), rng.normal(size=3)) for _ in range(47)]
    out = rodar(asm, exe, mats)

    def coef(v, b):            # v = P + c0·R0 + c1·R1 + c2·R2 (linhas = eixos X, Y, Z)
        rr, p = mats[b]
        return np.round(np.linalg.solve(rr.T, np.array(v) - p), 4)
    print("pino (+0x1c)     %s: %s" % (OSSOS[4], coef(out[0][4:7], 4)))
    print("esfera (+0x20)   %s: %s" % (OSSOS[5], coef(out[1][2:5], 5)))
    print("cilindro (+0x24) %s: %s  %s: %s" % (OSSOS[6], coef(out[2][2:5], 6), OSSOS[18], coef(out[2][5:8], 18)))
    print("esfera (+0x28)   %s: %s" % (OSSOS[3], coef(out[3][2:5], 3)))


if __name__ == "__main__":
    main()
