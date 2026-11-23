"""
truques_ram.py
==============
Score de cada corredor direto da RAM de um save state PAL (gerente de
truques, corredor+0x15c; lista dos corredores em DAT_007f48d4 +0x10):
total (+4), pontos por minuto (relógio do gerente +0x334), recordes do banco
(0x523718: +0x1a4 combo com mais truques, +0x1b0 maior combo e +0x1a8 os
truques dele, +0x1b8 maior multiplicador, +0x1c0 combo mais longo em s),
último banco (+0x28c, relógio da corrida), parado (+8) e o catchup do corpo
(veículo+0x9d4: +0x720 potência, +0x724 subesterço).

Serve pra comparar com tests/medir_truques_ia.gd (o nosso).
Uso:
    python re/truques_ram.py save1.p2s [save2.p2s ...]
"""
import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tools"))
from ler_savestate import ler_ram  # noqa: E402


def main():
    for p in sys.argv[1:]:
        m = ler_ram(p)
        u = lambda a: struct.unpack_from("<I", m, a & 0x1FFFFFF)[0]
        f = lambda a: struct.unpack_from("<f", m, a & 0x1FFFFFF)[0]
        lista = u(u(0x7F48D4) + 0x10)
        print("== %s  (relógio da corrida %.2f s)" % (os.path.basename(p), f(u(0x7F4820) + 0x24)))
        print("   #  Score  por min  maior combo (truques)  mult  combo mais longo  último banco  parado  catchup pot/sub")
        for k in range(8):
            w = u(lista + 4 * k)
            s = u(w + 0x15C)
            c = u(u(w + 0xF0) + 0x9D4)
            t = f(s + 0x334)
            print("   %d  %5d  %7.0f  %11d (%d)  %12d  %15.2f  %12.1f  %6d  %.2f / %.2f" % (
                k, u(s + 4), u(s + 4) / t * 60.0 if t > 0 else 0.0, u(s + 0x1B0), u(s + 0x1A8),
                u(s + 0x1B8), f(s + 0x1C0), f(s + 0x28C), u(s + 8), f(c + 0x720), f(c + 0x724)))


if __name__ == "__main__":
    main()
